// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#include "cue_engine.h"
#include "storage/nvs_store.h"

using cue::Engine;

void Engine::begin() {
  selectedRoleId_ = store::getRoleId();
}

void Engine::setSelectedRoleId(const String &roleId) {
  selectedRoleId_ = roleId;
  store::setRoleId(roleId);
  store::setRoleChosen(true);
  lastSeenMessageId_ = latestRelevantMessage().id;
  lastNotifiedState_ = activeRole().state;
  hasNotifiedState_ = true;
}

static int64_t jsonInt64(JsonVariantConst v, int64_t fallback = 0) {
  if (v.isNull()) return fallback;
  if (v.is<int64_t>()) return v.as<int64_t>();
  return (int64_t)llround(v.as<double>());
}

static const char *wireState(CueState s) {
  if (s == CueState::Go) return "GO";
  if (s == CueState::Standby) return "STANDBY";
  return "OFF";
}

int64_t Engine::producerNowMs() const {
  int64_t local = localNowMs();
  if (clock_.hasOffset()) return clock_.producerNow(local);
  if (anchor_.valid) return anchor_.anchorMs + (local - anchorRecvLocalMs_);
  return local;
}

void Engine::onConnected() {
  producerV2_ = false;
  rev_.reset();
  clock_.reset();
  catchUpWanted_ = false;
  messageMismatchStreak_ = 0;
  anchorKnown_ = false;
}

bool Engine::takeCatchUpRequest() {
  bool wanted = catchUpWanted_;
  catchUpWanted_ = false;
  return wanted;
}

void Engine::handleSyncReply(JsonObjectConst doc) {
  int64_t t0 = jsonInt64(doc["t0"], -1);
  int64_t t1 = jsonInt64(doc["t1"], -1);
  int64_t t2 = jsonInt64(doc["t2"], -1);
  if (t0 < 0 || t1 < 0 || t2 < 0) return;
  clock_.addSample(t0, t1, t2, localNowMs());
}

std::string Engine::rolesHash() const {
  std::string c;
  for (int i = 0; i < roleCount_; i++) {
    pagersync::appendRole(c, roles_[i].id.c_str(), roles_[i].name.c_str(), wireState(roles_[i].state));
  }
  return pagersync::hashHex(c);
}

std::string Engine::timerHash() const {
  return pagersync::hashHex(pagersync::timerCanonical(anchor_));
}

std::string Engine::messagesHash() const {
  std::string c;
  for (int i = 0; i < messageCount_; i++) pagersync::appendMessageId(c, messages_[i].id.c_str());
  return pagersync::hashHex(c);
}

void Engine::handleDigest(JsonObjectConst doc) {
  JsonObjectConst h = doc["hashes"];
  if (h.isNull()) return;
  bool mismatch = false;
  const char *roles = h["roles"] | "";
  if (roles[0] && !rolesTruncated_ && rolesHash() != roles) mismatch = true;
  const char *timer = h["timer"] | "";
  if (timer[0] && anchorKnown_ && timerHash() != timer) mismatch = true;
  const char *messages = h["messages"] | "";
  if (messages[0] && !messagesOverflowed_ && messageMismatchStreak_ < kMaxMessageMismatchStreak) {
    if (messagesHash() != messages) {
      messageMismatchStreak_++;
      mismatch = true;
    } else {
      messageMismatchStreak_ = 0;
    }
  }
  if (mismatch) {
    Serial.println("[cue] digest mismatch — requesting catch-up");
    catchUpWanted_ = true;
  }
}

void Engine::applyCueDeltas(JsonArrayConst deltas) {
  for (JsonObjectConst d : deltas) {
    const char *id = d["id"] | "";
    bool found = false;
    for (int i = 0; i < roleCount_; i++) {
      if (roles_[i].id == id) {
        roles_[i].state = cueStateFromString(String((const char *)(d["state"] | "OFF")));
        found = true;
        break;
      }
    }
    if (!found) catchUpWanted_ = true;
  }
}

void Engine::applyAnchor(JsonVariantConst a) {
  anchorKnown_ = true;
  if (!a.is<JsonObjectConst>()) {
    anchor_ = pagersync::Anchor();
    anchored_ = false;
    timer_.found = false;
    return;
  }
  JsonObjectConst o = a.as<JsonObjectConst>();
  anchor_.valid = true;
  anchor_.itemId = (const char *)(o["itemId"] | "");
  anchor_.lengthInSeconds = jsonInt64(o["lengthInSeconds"]);
  anchor_.elapsedMs = jsonInt64(o["elapsedMs"]);
  anchor_.anchorMs = jsonInt64(o["anchorMs"]);
  anchor_.isRunning = o["isRunning"] | false;
  anchor_.isDurationActual = o["isDurationActual"] | false;
  anchorRecvLocalMs_ = localNowMs();
  anchored_ = true;
  timer_.id = anchor_.itemId.c_str();
  timer_.lengthInSeconds = (int)anchor_.lengthInSeconds;
  timer_.isRunning = anchor_.isRunning;
  timer_.isDurationActual = anchor_.isDurationActual;
}

void Engine::handlePacketJson(const char *json, size_t len) {
  JsonDocument doc;
  DeserializationError err = deserializeJson(doc, json, len);
  if (err) return;

  const char *senderId = doc["senderId"] | "";
  if (String(senderId) == store::deviceId()) return;

  const char *type = doc["type"] | "";
  int64_t rev = doc["rev"].isNull() ? -1 : jsonInt64(doc["rev"], -1);

  bool isCueUpdate = strcmp(type, "CUE_UPDATE") == 0;
  bool isPong = strcmp(type, "PONG") == 0;
  bool isAnchor = strcmp(type, "TIMER_ANCHOR") == 0;
  bool isDelta = strcmp(type, "CUE_DELTA") == 0;
  bool isDigest = strcmp(type, "DIGEST") == 0;
  bool isSyncReply = strcmp(type, "SYNC_REPLY") == 0;

  if (isCueUpdate || strcmp(type, "TIMER_UPDATE") == 0 || isPong) {
    hasSyncedWithProducer_ = true;
    lastProducerPacketAtMillis_ = millis();
  }

  if (isAnchor || isDelta || isDigest || isSyncReply) {
    producerV2_ = true;
    lastProducerPacketAtMillis_ = millis();
  }

  if (isPong) {
    if (!doc["rev"].isNull()) producerV2_ = true;
    rev_.resetTo(rev);
    messageMismatchStreak_ = 0;
  } else if ((isCueUpdate || isAnchor || isDelta || isDigest) && !rev_.accept(rev)) {
    return;
  }

  if (isSyncReply) {
    handleSyncReply(doc.as<JsonObjectConst>());
    return;
  }

  if (isDigest) {
    handleDigest(doc.as<JsonObjectConst>());
    return;
  }

  if (isCueUpdate || isPong) {
    if (doc["roleCues"].is<JsonArrayConst>()) applyRoleCues(doc["roleCues"].as<JsonArrayConst>());
    bool hasAnchor = doc.as<JsonObjectConst>()["anchor"].is<JsonObjectConst>();
    if (doc["timerItem"].is<JsonObjectConst>()) {
      applyTimerItem(doc["timerItem"].as<JsonObjectConst>(), hasAnchor || !(anchored_ && producerV2_));
    }
    if (hasAnchor) applyAnchor(doc["anchor"]);
    if (doc["messages"].is<JsonArrayConst>()) {
      if (isPong && producerV2_) {
        messageCount_ = 0;
        messagesOverflowed_ = false;
      }
      mergeMessages(doc["messages"].as<JsonArrayConst>());
    }
  } else if (isAnchor) {
    if (doc["timerItem"].is<JsonObjectConst>()) applyTimerItem(doc["timerItem"].as<JsonObjectConst>(), false);
    applyAnchor(doc["anchor"]);
  } else if (isDelta) {
    if (doc["cueDeltas"].is<JsonArrayConst>()) applyCueDeltas(doc["cueDeltas"].as<JsonArrayConst>());
  } else if (strcmp(type, "TIMER_UPDATE") == 0) {
    if (doc["timerItem"].is<JsonObjectConst>()) applyTimerItem(doc["timerItem"].as<JsonObjectConst>());
  } else if (strcmp(type, "MESSAGE") == 0) {
    if (doc["message"].is<JsonObjectConst>()) addOneMessage(doc["message"].as<JsonObjectConst>());
  } else if (strcmp(type, "CLEAR_MESSAGES") == 0) {
    messageCount_ = 0;
    messagesOverflowed_ = false;
  }

  checkForCueTransition();
  checkForRelevantNewMessage();
}

void Engine::applyRoleCues(JsonArrayConst roles) {
  roleCount_ = 0;
  rolesTruncated_ = false;
  for (JsonObjectConst r : roles) {
    if (roleCount_ >= kMaxRoles) { rolesTruncated_ = true; break; }
    RoleView &v = roles_[roleCount_++];
    v.found = true;
    v.id = r["id"] | "";
    v.name = r["name"] | "";
    v.personName = r["personName"] | "";
    v.assignedNoteCategoryCount = 0;
    if (r["assignedNoteCategories"].is<JsonArrayConst>()) {
      for (JsonVariantConst c : r["assignedNoteCategories"].as<JsonArrayConst>()) {
        if (v.assignedNoteCategoryCount >= kMaxNoteCategoriesPerRole) break;
        v.assignedNoteCategories[v.assignedNoteCategoryCount++] = c.as<String>();
      }
    }
    v.state = cueStateFromString(String((const char *)(r["state"] | "OFF")));
  }

  if (roleCount_ > 0) {
    bool stillPresent = false;
    for (int i = 0; i < roleCount_; i++) {
      if (roles_[i].id == selectedRoleId_) { stillPresent = true; break; }
    }
    if (!stillPresent) {
      Serial.printf("[cue] previously-selected role \"%s\" not in the latest roster — defaulting to \"%s\"\n",
                    selectedRoleId_.c_str(), roles_[0].id.c_str());
      selectedRoleId_ = roles_[0].id;
      store::setRoleId(selectedRoleId_);
    }
  }
}

void Engine::applyTimerItem(JsonObjectConst t, bool timing) {
  timer_.found = true;
  timer_.id = t["id"] | "";
  timer_.title = t["title"] | "";
  timer_.itemType = t["itemType"] | "Item";
  if (timing) {
    timer_.lengthInSeconds = t["lengthInSeconds"] | 0;
    timer_.elapsedSecondsAtSync = t["elapsedSeconds"] | 0;
    timer_.isRunning = t["isRunning"] | false;
    timer_.isDurationActual = t["isDurationActual"] | false;
    timer_.syncedAtMillis = millis();
    anchored_ = false;
  }

  noteCount_ = 0;
  if (t["notes"].is<JsonObjectConst>()) {
    for (JsonPairConst kv : t["notes"].as<JsonObjectConst>()) {
      if (noteCount_ >= kMaxNoteCategories) break;
      notes_[noteCount_].category = kv.key().c_str();
      notes_[noteCount_].text = kv.value().as<const char *>();
      noteCount_++;
    }
  }
}

void Engine::addOneMessage(JsonObjectConst msg) {
  String id = msg["id"] | "";
  if (id.length() == 0) return;

  int existingIndex = -1;
  for (int i = 0; i < messageCount_; i++) {
    if (messages_[i].id == id) { existingIndex = i; break; }
  }

  MessageView v;
  v.found = true;
  v.id = id;
  v.sender = msg["sender"] | "Producer";
  v.text = msg["text"] | "";
  v.targetRoleId = msg["targetRoleId"] | "";
  v.senderRoleId = msg["senderRoleId"] | "";
  v.timestamp = msg["timestamp"] | 0.0;
  v.isHighPriority = msg["isHighPriority"] | false;

  if (existingIndex >= 0) {
    messages_[existingIndex] = v;
  } else if (messageCount_ < kMaxMessages) {
    messages_[messageCount_++] = v;
  } else {
    messages_[kMaxMessages - 1] = v;
    messagesOverflowed_ = true;
  }

  for (int i = messageCount_ - 1; i > 0; i--) {
    if (messages_[i].timestamp > messages_[i - 1].timestamp) {
      MessageView tmp = messages_[i];
      messages_[i] = messages_[i - 1];
      messages_[i - 1] = tmp;
    } else {
      break;
    }
  }
}

void Engine::mergeMessages(JsonArrayConst msgs) {
  for (JsonObjectConst m : msgs) addOneMessage(m);
}

cue::RoleView Engine::activeRole() const {
  for (int i = 0; i < roleCount_; i++) {
    if (roles_[i].id == selectedRoleId_) return roles_[i];
  }
  if (roleCount_ > 0) return roles_[0];
  return RoleView{};
}

String Engine::currentNote() const {
  RoleView role = activeRole();
  if (role.assignedNoteCategoryCount == 0 || !timer_.found) return "";
  for (int i = 0; i < noteCount_; i++) {
    if (role.hasNoteCategory(notes_[i].category)) return notes_[i].text;
  }
  return "";
}

cue::MessageView Engine::latestRelevantMessage() const {
  for (int i = 0; i < messageCount_; i++) {
    if (messages_[i].targetRoleId.length() == 0 || messages_[i].targetRoleId == selectedRoleId_) {
      return messages_[i];
    }
  }
  return MessageView{};
}

void Engine::checkForCueTransition() {
  CueState now = activeRole().state;
  bool changed = hasNotifiedState_ && (now != lastNotifiedState_);
  lastNotifiedState_ = now;
  hasNotifiedState_ = true;
  if (changed && onCueTransition) onCueTransition(now);
}

void Engine::checkForRelevantNewMessage() {
  MessageView latest = latestRelevantMessage();
  if (!latest.found || latest.id == lastSeenMessageId_) return;
  lastSeenMessageId_ = latest.id;
  if (latest.senderRoleId == selectedRoleId_) return;
  if (onMessageReceived) onMessageReceived(activeRole().state);
}
