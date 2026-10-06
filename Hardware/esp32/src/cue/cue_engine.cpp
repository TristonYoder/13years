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

void Engine::handlePacketJson(const char *json, size_t len) {
  JsonDocument doc;
  DeserializationError err = deserializeJson(doc, json, len);
  if (err) return;

  const char *senderId = doc["senderId"] | "";
  if (String(senderId) == store::deviceId()) return;

  const char *type = doc["type"] | "";

  if (strcmp(type, "CUE_UPDATE") == 0 || strcmp(type, "TIMER_UPDATE") == 0 || strcmp(type, "PONG") == 0) {
    hasSyncedWithProducer_ = true;
    lastProducerPacketAtMillis_ = millis();
  }

  if (strcmp(type, "CUE_UPDATE") == 0 || strcmp(type, "PONG") == 0) {
    if (doc["roleCues"].is<JsonArrayConst>()) applyRoleCues(doc["roleCues"].as<JsonArrayConst>());
    if (doc["timerItem"].is<JsonObjectConst>()) applyTimerItem(doc["timerItem"].as<JsonObjectConst>());
    if (doc["messages"].is<JsonArrayConst>()) mergeMessages(doc["messages"].as<JsonArrayConst>());
  } else if (strcmp(type, "TIMER_UPDATE") == 0) {
    if (doc["timerItem"].is<JsonObjectConst>()) applyTimerItem(doc["timerItem"].as<JsonObjectConst>());
  } else if (strcmp(type, "MESSAGE") == 0) {
    if (doc["message"].is<JsonObjectConst>()) addOneMessage(doc["message"].as<JsonObjectConst>());
  } else if (strcmp(type, "CLEAR_MESSAGES") == 0) {
    messageCount_ = 0;
  }

  checkForCueTransition();
  checkForRelevantNewMessage();
}

void Engine::applyRoleCues(JsonArrayConst roles) {
  roleCount_ = 0;
  for (JsonObjectConst r : roles) {
    if (roleCount_ >= kMaxRoles) break;
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

void Engine::applyTimerItem(JsonObjectConst t) {
  timer_.found = true;
  timer_.id = t["id"] | "";
  timer_.title = t["title"] | "";
  timer_.itemType = t["itemType"] | "Item";
  timer_.lengthInSeconds = t["lengthInSeconds"] | 0;
  timer_.elapsedSecondsAtSync = t["elapsedSeconds"] | 0;
  timer_.isRunning = t["isRunning"] | false;
  timer_.isDurationActual = t["isDurationActual"] | false;
  timer_.syncedAtMillis = millis();

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
