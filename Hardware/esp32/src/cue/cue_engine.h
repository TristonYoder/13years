// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#pragma once
#include <Arduino.h>
#include <ArduinoJson.h>
#include "cue_state.h"

namespace cue {

static const int kMaxNoteCategoriesPerRole = 4;

struct RoleView {
  bool found = false;
  String id;
  String name;
  String personName;
  String assignedNoteCategories[kMaxNoteCategoriesPerRole];
  int assignedNoteCategoryCount = 0;
  CueState state = CueState::Off;

  bool hasNoteCategory(const String &category) const {
    for (int i = 0; i < assignedNoteCategoryCount; i++) {
      if (assignedNoteCategories[i] == category) return true;
    }
    return false;
  }
};

struct TimerView {
  bool found = false;
  String id;
  String title;
  String itemType;
  int lengthInSeconds = 0;
  int elapsedSecondsAtSync = 0;
  bool isRunning = false;
  bool isDurationActual = false;
  unsigned long syncedAtMillis = 0;

  bool isHeader() const { return itemType.equalsIgnoreCase("header"); }

  int currentElapsedSeconds() const {
    if (!isRunning) return elapsedSecondsAtSync;
    unsigned long elapsedMs = millis() - syncedAtMillis;
    return elapsedSecondsAtSync + (int)(elapsedMs / 1000UL);
  }

  int remainingSeconds() const { return lengthInSeconds - currentElapsedSeconds(); }
};

struct MessageView {
  bool found = false;
  String id;
  String sender;
  String text;
  String targetRoleId;
  String senderRoleId;
  double timestamp = 0;
  bool isHighPriority = false;
};

class Engine {
public:
  void begin();

  void handlePacketJson(const char *json, size_t len);

  String selectedRoleId() const { return selectedRoleId_; }
  void setSelectedRoleId(const String &roleId);

  RoleView activeRole() const;
  TimerView activeTimer() const { return timer_; }

  String currentNote() const;
  MessageView latestRelevantMessage() const;

  int roleCount() const { return roleCount_; }
  RoleView roleAt(int index) const { return index >= 0 && index < roleCount_ ? roles_[index] : RoleView{}; }

  bool hasSyncedWithProducer() const { return hasSyncedWithProducer_; }
  bool isProducerLive() const {
    return hasSyncedWithProducer_ && (millis() - lastProducerPacketAtMillis_ < kProducerStalenessMs);
  }

  void (*onCueTransition)(CueState newState) = nullptr;
  void (*onMessageReceived)(CueState currentDisplayState) = nullptr;

private:
  static const int kMaxRoles = 8;
  static const int kMaxMessages = 16;
  static const int kMaxNoteCategories = 6;
  static const unsigned long kProducerStalenessMs = 12000;

  bool hasSyncedWithProducer_ = false;
  unsigned long lastProducerPacketAtMillis_ = 0;

  struct NoteEntry { String category; String text; };

  RoleView roles_[kMaxRoles];
  int roleCount_ = 0;
  TimerView timer_;
  NoteEntry notes_[kMaxNoteCategories];
  int noteCount_ = 0;
  MessageView messages_[kMaxMessages];
  int messageCount_ = 0;

  String selectedRoleId_;
  CueState lastNotifiedState_ = CueState::Off;
  bool hasNotifiedState_ = false;
  String lastSeenMessageId_;

  void applyRoleCues(JsonArrayConst roles);
  void applyTimerItem(JsonObjectConst timer);
  void mergeMessages(JsonArrayConst messages);
  void addOneMessage(JsonObjectConst msg);
  void checkForRelevantNewMessage();
  void checkForCueTransition();
};

}
