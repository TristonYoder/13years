// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#include "cue_engine.h"
#include "storage/nvs_store.h"

using cue::Engine;

void Engine::begin() {
  clock_.setMaxAbsOffsetMs(kMaxMonotonicOffsetMs);
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

bool Engine::wallClockMs(int64_t &ms) const {
  if (!clock_.hasOffset() && !anchor_.valid) return false;
  ms = producerNowMs();
  return true;
}

void Engine::onConnected() {
  catchUpWanted_ = true;
  syncBurstWanted_ = true;
  noOffsetBurstDone_ = true;
  messageMismatchStreak_ = 0;
  if (pagersync::keepStateOnReconnect(pagersync::msSince(millis(), lastRxAnyMillis_))) return;
  producerV2_ = false;
  rev_.reset();
  clock_.reset();
  epoch_.reset();
  anchor_ = pagersync::Anchor();
  anchored_ = false;
  anchorKnown_ = false;
  next_.found = false;
  hasSyncedWithProducer_ = false;
  noOffsetBurstDone_ = false;
  lastRxAnyMillis_ = millis();
}

bool Engine::takeCatchUpRequest() {
  bool wanted = catchUpWanted_;
  catchUpWanted_ = false;
  return wanted;
}

bool Engine::takeSyncBurstRequest() {
  bool wanted = syncBurstWanted_;
  syncBurstWanted_ = false;
  return wanted;
}

void Engine::resetForEpochChange() {
  Serial.println("[cue] producer epoch changed — discarding anchor, rev gate and clock samples");
  anchor_ = pagersync::Anchor();
  anchored_ = false;
  anchorKnown_ = false;
  next_.found = false;
  rev_.reset();
  clock_.reset();
  messageMismatchStreak_ = 0;
  syncBurstWanted_ = true;
  noOffsetBurstDone_ = true;
  catchUpWanted_ = true;
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
  if (messages[0] && messageMismatchStreak_ < kMaxMessageMismatchStreak) {
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

static bool anchorPayloadOk(JsonVariantConst a) {
  if (!a.is<JsonObjectConst>()) return true;
  JsonObjectConst o = a.as<JsonObjectConst>();
  return pagersync::anchorInBounds(jsonInt64(o["lengthInSeconds"]), jsonInt64(o["elapsedMs"]));
}

bool Engine::applyAnchor(JsonVariantConst a) {
  if (!anchorPayloadOk(a)) {
    Serial.println("[cue] anchor out of bounds — ignored");
    return false;
  }
  anchorKnown_ = true;
  if (!a.is<JsonObjectConst>()) {
    anchor_ = pagersync::Anchor();
    anchored_ = false;
    timer_.found = false;
    return true;
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
  return true;
}

static JsonDocument &packetFilter() {
  static JsonDocument filter;
  static bool built = false;
  if (!built) {
    built = true;
    filter["type"] = true;
    filter["senderId"] = true;
    filter["to"] = true;
    filter["rev"] = true;
    filter["epoch"] = true;
    filter["utcOffsetSeconds"] = true;
    filter["clockFormat"] = true;
    filter["t0"] = true;
    filter["t1"] = true;
    filter["t2"] = true;
    pagersync::buildRoleCueFilter(filter["roleCues"][0].to<JsonObject>());
    pagersync::buildTimerItemFilter(filter["timerItem"].to<JsonObject>());
    filter["anchor"] = true;
    pagersync::buildNextItemFilter(filter["nextItem"].to<JsonObject>());
    filter["hashes"] = true;
    filter["cueDeltas"] = true;
    filter["message"] = true;
    JsonObject m = filter["messages"][0].to<JsonObject>();
    m["id"] = true;
    m["sender"] = true;
    m["text"] = true;
    m["targetRoleId"] = true;
    m["senderRoleId"] = true;
    m["timestamp"] = true;
    m["isHighPriority"] = true;
  }
  return filter;
}

void Engine::handlePacketJson(const char *json, size_t len) {
  JsonDocument doc;
  DeserializationError err = deserializeJson(doc, json, len, DeserializationOption::Filter(packetFilter()));
  if (err) {
    Serial.printf("[cue] packet parse failed: %s (%u bytes, free heap %u)\n", err.c_str(), (unsigned)len, (unsigned)ESP.getFreeHeap());
    unsigned long now = millis();
    if (now - lastParseErrorCatchUpMillis_ >= kCatchUpRateLimitMs) {
      lastParseErrorCatchUpMillis_ = now;
      catchUpWanted_ = true;
    }
    return;
  }

  const char *senderId = doc["senderId"] | "";
  if (store::deviceId().equals(senderId)) return;

  bool hasTo = doc["to"].is<const char *>();
  if (hasTo && !store::deviceId().equals(doc["to"].as<const char *>())) return;

  lastRxAnyMillis_ = millis();

  const char *type = doc["type"] | "";
  int64_t rev = doc["rev"].isNull() ? -1 : jsonInt64(doc["rev"], -1);

  bool isCueUpdate = strcmp(type, "CUE_UPDATE") == 0;
  bool isTimerUpdate = strcmp(type, "TIMER_UPDATE") == 0;
  bool isPong = strcmp(type, "PONG") == 0;
  bool isAnchor = strcmp(type, "TIMER_ANCHOR") == 0;
  bool isDelta = strcmp(type, "CUE_DELTA") == 0;
  bool isDigest = strcmp(type, "DIGEST") == 0;
  bool isSyncReply = strcmp(type, "SYNC_REPLY") == 0;

  if (isSyncReply && !hasTo) return;

  bool epochChanged = false;
  if (!doc["epoch"].isNull() && (isPong || isAnchor || isDelta || isDigest || isSyncReply)) {
    epochChanged = epoch_.observe(jsonInt64(doc["epoch"], 0));
    if (epochChanged) resetForEpochChange();
  }

  if (isCueUpdate || isTimerUpdate || isPong) {
    hasSyncedWithProducer_ = true;
    lastProducerPacketAtMillis_ = millis();
  }

  bool v2Evidence = isAnchor || isDelta || isDigest || isSyncReply || (isPong && rev >= 0);
  if (v2Evidence) {
    producerV2_ = true;
    lastProducerPacketAtMillis_ = millis();
    if (!isSyncReply && !clock_.hasOffset() && !noOffsetBurstDone_) {
      noOffsetBurstDone_ = true;
      syncBurstWanted_ = true;
    }
  }

  if (producerV2_ && rev < 0 && (isCueUpdate || isTimerUpdate)) {
    unsigned long now = millis();
    if (now - lastLegacyCatchUpMillis_ >= kCatchUpRateLimitMs) {
      lastLegacyCatchUpMillis_ = now;
      catchUpWanted_ = true;
    }
  }

  bool pongV2 = isPong && rev >= 0;
  if (isPong) {
    if (pongV2) rev_.accept(rev, pagersync::RevKind::Rebase);
    messageMismatchStreak_ = 0;
  } else if (isCueUpdate || isAnchor || isDelta) {
    if (!rev_.accept(rev, pagersync::RevKind::Strict, epochChanged)) return;
  } else if (isDigest) {
    if (!rev_.accept(rev, pagersync::RevKind::NotLower, epochChanged)) return;
  }

  if ((isAnchor || isPong || isTimerUpdate) && doc["utcOffsetSeconds"].is<int64_t>()) {
    int64_t off = doc["utcOffsetSeconds"].as<int64_t>();
    if (pagersync::utcOffsetInBounds(off)) {
      utcOffsetSeconds_ = (int32_t)off;
      hasUtcOffset_ = true;
    }
  }

  if (doc["clockFormat"].is<const char *>()) {
    producerClockFormat_ = pagersync::parseClockFormat(doc["clockFormat"].as<const char *>());
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
    bool hasAnchor = doc["anchor"].is<JsonObjectConst>();
    bool anchorOk = !hasAnchor || anchorPayloadOk(doc["anchor"]);
    if (anchorOk) {
      if (doc["timerItem"].is<JsonObjectConst>()) {
        applyTimerItem(doc["timerItem"].as<JsonObjectConst>(), hasAnchor || !(anchored_ && producerV2_));
      }
      if (hasAnchor) applyAnchor(doc["anchor"]);
      if (hasAnchor || doc["timerItem"].is<JsonObjectConst>() || !doc["nextItem"].isNull()) applyNextItem(doc["nextItem"]);
    } else {
      Serial.println("[cue] anchor out of bounds — timer ignored");
    }
    if (doc["messages"].is<JsonArrayConst>()) {
      if (pongV2) {
        messageCount_ = 0;
        messagesOverflowed_ = false;
      }
      mergeMessages(doc["messages"].as<JsonArrayConst>());
    }
  } else if (isAnchor) {
    if (!anchorPayloadOk(doc["anchor"])) {
      Serial.println("[cue] anchor out of bounds — ignored");
      return;
    }
    if (doc["timerItem"].is<JsonObjectConst>()) applyTimerItem(doc["timerItem"].as<JsonObjectConst>(), false);
    applyAnchor(doc["anchor"]);
    applyNextItem(doc["nextItem"]);
  } else if (isDelta) {
    if (doc["cueDeltas"].is<JsonArrayConst>()) applyCueDeltas(doc["cueDeltas"].as<JsonArrayConst>());
  } else if (isTimerUpdate) {
    if (doc["timerItem"].is<JsonObjectConst>()) applyTimerItem(doc["timerItem"].as<JsonObjectConst>());
    applyNextItem(doc["nextItem"]);
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
    v.clockFormat = pagersync::parseClockFormat(r["clockFormat"].is<const char *>() ? r["clockFormat"].as<const char *>() : nullptr);
    v.assignedNoteCategoryCount = 0;
    if (r["assignedNoteCategories"].is<JsonArrayConst>()) {
      for (JsonVariantConst c : r["assignedNoteCategories"].as<JsonArrayConst>()) {
        if (v.assignedNoteCategoryCount >= kMaxNoteCategoriesPerRole) break;
        v.assignedNoteCategories[v.assignedNoteCategoryCount++] = c.as<String>();
      }
    }
    v.pagerFieldOrder = pagersync::parsePagerFieldOrder(r["pagerFields"]);
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

  pagersync::parseItemDetails(timerDetails_, t["details"]);
  pagersync::setItemBasics(timerDetails_, timer_.itemType.c_str(), timer_.lengthInSeconds);

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

bool Engine::categoryAssignedToAnyRole(const char *category) const {
  if (roleCount_ == 0) return true;
  for (int i = 0; i < roleCount_; i++) {
    if (roles_[i].hasNoteCategory(category)) return true;
  }
  return false;
}

void Engine::applyNextItem(JsonVariantConst v) {
  if (!v.is<JsonObjectConst>()) {
    next_.found = false;
    return;
  }
  JsonObjectConst o = v.as<JsonObjectConst>();
  next_.found = true;
  pagersync::copyTruncated(next_.id, sizeof(next_.id), o["id"] | "");
  pagersync::copyTruncated(next_.title, sizeof(next_.title), o["title"] | "");
  next_.lengthInSeconds = o["lengthInSeconds"] | 0;
  next_.hasStartsAt = o["startsAtMs"].is<int64_t>();
  next_.startsAtMs = next_.hasStartsAt ? o["startsAtMs"].as<int64_t>() : 0;
  pagersync::parseItemDetails(next_.details, o["details"]);
  pagersync::setItemBasics(next_.details, o["itemType"] | "", next_.lengthInSeconds);
  next_.noteCount = 0;
  if (o["notes"].is<JsonObjectConst>()) {
    for (JsonPairConst kv : o["notes"].as<JsonObjectConst>()) {
      if (next_.noteCount >= NextItemView::kMaxNotes) break;
      const char *category = kv.key().c_str();
      if (!categoryAssignedToAnyRole(category)) continue;
      NextItemView::Note &n = next_.notes[next_.noteCount++];
      pagersync::copyTruncated(n.category, sizeof(n.category), category);
      pagersync::copyTruncated(n.text, sizeof(n.text), kv.value().as<const char *>() ? kv.value().as<const char *>() : "");
    }
  }
}

void Engine::insertMessageSorted(const MessageView &v) {
  for (int i = 0; i < messageCount_; i++) {
    if (messages_[i].id == v.id) {
      for (int j = i; j < messageCount_ - 1; j++) messages_[j] = messages_[j + 1];
      messageCount_--;
      break;
    }
  }
  int pos = 0;
  while (pos < messageCount_ &&
         pagersync::messageOrderBefore(messages_[pos].timestamp, messages_[pos].id.c_str(), v.timestamp, v.id.c_str())) {
    pos++;
  }
  if (messageCount_ >= kMaxMessages) {
    messagesOverflowed_ = true;
    if (pos >= kMaxMessages) return;
    messageCount_ = kMaxMessages - 1;
  }
  for (int j = messageCount_; j > pos; j--) messages_[j] = messages_[j - 1];
  messages_[pos] = v;
  messageCount_++;
}

void Engine::addOneMessage(JsonObjectConst msg) {
  String id = msg["id"] | "";
  if (id.length() == 0) return;

  MessageView v;
  v.found = true;
  v.id = id;
  v.sender = msg["sender"] | "Producer";
  v.text = msg["text"] | "";
  v.targetRoleId = msg["targetRoleId"] | "";
  v.senderRoleId = msg["senderRoleId"] | "";
  v.timestamp = msg["timestamp"] | 0.0;
  v.isHighPriority = msg["isHighPriority"] | false;
  insertMessageSorted(v);
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

static int roleOrderedNote(const cue::RoleView &role, const pagersync::NoteRef *refs, int count, int nth) {
  const char *categories[cue::kMaxNoteCategoriesPerRole];
  for (int i = 0; i < role.assignedNoteCategoryCount; i++) categories[i] = role.assignedNoteCategories[i].c_str();
  return pagersync::orderedNoteIndex(categories, role.assignedNoteCategoryCount, refs, count, nth);
}

int Engine::currentNoteIndex(const RoleView &role, int nth) const {
  pagersync::NoteRef refs[kMaxNoteCategories];
  for (int i = 0; i < noteCount_; i++) {
    refs[i].category = notes_[i].category.c_str();
    refs[i].text = notes_[i].text.c_str();
  }
  return roleOrderedNote(role, refs, noteCount_, nth);
}

int Engine::nextNoteIndex(const RoleView &role, int nth) const {
  pagersync::NoteRef refs[NextItemView::kMaxNotes];
  for (int i = 0; i < next_.noteCount; i++) {
    refs[i].category = next_.notes[i].category;
    refs[i].text = next_.notes[i].text;
  }
  return roleOrderedNote(role, refs, next_.noteCount, nth);
}

String Engine::currentNote() const {
  RoleView role = activeRole();
  if (role.assignedNoteCategoryCount == 0 || !timer_.found) return "";
  int index = currentNoteIndex(role, 0);
  return index >= 0 ? notes_[index].text : String("");
}

cue::MessageView Engine::latestRelevantMessage() const {
  const MessageView *standing = latestRelevantMessageRef();
  return standing ? *standing : MessageView{};
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

const cue::RoleView *Engine::activeRoleRef() const {
  for (int i = 0; i < roleCount_; i++) {
    if (roles_[i].id == selectedRoleId_) return &roles_[i];
  }
  if (roleCount_ > 0) return &roles_[0];
  return nullptr;
}

const cue::MessageView *Engine::latestRelevantMessageRef() const {
  const MessageView *incoming = nullptr;
  for (int i = 0; i < messageCount_; i++) {
    bool addressed = messages_[i].targetRoleId.length() == 0 || messages_[i].targetRoleId == selectedRoleId_;
    if (addressed && messages_[i].senderRoleId.length() == 0) {
      incoming = &messages_[i];
      break;
    }
  }
  if (!incoming) return nullptr;
  for (int i = 0; i < messageCount_; i++) {
    if (messages_[i].senderRoleId == selectedRoleId_) {
      if (messages_[i].timestamp >= incoming->timestamp) return nullptr;
      break;
    }
  }
  return incoming;
}

const char *Engine::currentNoteText() const {
  const RoleView *role = activeRoleRef();
  if (!role || role->assignedNoteCategoryCount == 0 || !timer_.found) return "";
  int index = currentNoteIndex(*role, 0);
  return index >= 0 ? notes_[index].text.c_str() : "";
}

int Engine::timerRemainingSeconds() const {
  if (anchored_ && anchor_.valid && timer_.found) {
    return (int)pagersync::anchorRemainingSeconds(anchor_, producerNowMs());
  }
  int elapsed = timer_.elapsedSecondsAtSync;
  if (timer_.isRunning) elapsed += (int)((millis() - timer_.syncedAtMillis) / 1000UL);
  return timer_.lengthInSeconds - elapsed;
}


const char *Engine::nextNoteText() const {
  const RoleView *role = activeRoleRef();
  if (!next_.found || !role) return "";
  int index = nextNoteIndex(*role, 0);
  return index >= 0 ? next_.notes[index].text : "";
}

bool Engine::timerDetailsLine(char *out, size_t cap) const {
  const RoleView *role = activeRoleRef();
  if (cap > 0) out[0] = '\0';
  if (!role || role->pagerFieldOrder.count == 0 || !timer_.found || timer_.isHeader()) return false;
  int64_t now = 0;
  int64_t start = 0;
  bool haveStart = wallClockMs(now) && pagersync::currentStartMs(timer_.isRunning, timer_.lengthInSeconds - timerRemainingSeconds(), now, start);
  return pagersync::formatDetailsLine(timerDetails_, role->pagerFieldOrder, haveStart, start, utcOffsetSeconds(), use24HourClock(), out, cap);
}

bool Engine::nextDetailsLine(char *out, size_t cap) const {
  const RoleView *role = activeRoleRef();
  if (cap > 0) out[0] = '\0';
  if (!role || role->pagerFieldOrder.count == 0 || !next_.found) return false;
  int64_t now = 0;
  int64_t start = 0;
  bool haveStart = wallClockMs(now) &&
                   pagersync::nextStartMs(next_.hasStartsAt, next_.startsAtMs, timer_.found && timer_.isRunning && !timer_.isHeader(), timerRemainingSeconds(), now, start);
  return pagersync::formatDetailsLine(next_.details, role->pagerFieldOrder, haveStart, start, utcOffsetSeconds(), use24HourClock(), out, cap);
}

bool Engine::nextFirstNote(const char *&category, const char *&text) const {
  const RoleView *role = activeRoleRef();
  if (!next_.found || !role) return false;
  int index = nextNoteIndex(*role, 0);
  if (index < 0) return false;
  category = next_.notes[index].category;
  text = next_.notes[index].text;
  return true;
}

int Engine::roleNoteCount() const {
  const RoleView *role = activeRoleRef();
  if (!role || !timer_.found) return 0;
  int n = 0;
  while (currentNoteIndex(*role, n) >= 0) n++;
  return n;
}

bool Engine::roleNoteAt(int index, const char *&category, const char *&text) const {
  const RoleView *role = activeRoleRef();
  if (!role || !timer_.found) return false;
  int at = currentNoteIndex(*role, index);
  if (at < 0) return false;
  category = notes_[at].category.c_str();
  text = notes_[at].text.c_str();
  return true;
}
