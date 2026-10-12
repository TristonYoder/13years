// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#pragma once
#include <Arduino.h>
#include <ArduinoJson.h>
#include <esp_timer.h>
#include "cue_state.h"
#include "sync/sync_core.h"

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
  bool anchored = false;
  pagersync::Anchor anchor;
  int64_t nowProducerMs = 0;

  bool isHeader() const { return itemType.equalsIgnoreCase("header"); }

  int currentElapsedSeconds() const {
    if (anchored) return (int)pagersync::anchorElapsedSeconds(anchor, nowProducerMs);
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

struct NextItemView {
  static const int kMaxNotes = 6;
  static const size_t kIdCap = 48;
  static const size_t kTitleCap = 96;
  static const size_t kCategoryCap = 32;
  static const size_t kNoteCap = 160;

  struct Note {
    char category[kCategoryCap];
    char text[kNoteCap];
  };

  bool found = false;
  char id[kIdCap] = {0};
  char title[kTitleCap] = {0};
  int lengthInSeconds = 0;
  Note notes[kMaxNotes];
  int noteCount = 0;
};

class Engine {
public:
  void begin();

  void handlePacketJson(const char *json, size_t len);

  String selectedRoleId() const { return selectedRoleId_; }
  void setSelectedRoleId(const String &roleId);

  RoleView activeRole() const;
  TimerView activeTimer() const {
    TimerView t = timer_;
    t.anchored = anchored_ && anchor_.valid && t.found;
    t.anchor = anchor_;
    t.nowProducerMs = producerNowMs();
    return t;
  }

  static int64_t localNowMs() { return esp_timer_get_time() / 1000; }
  int64_t producerNowMs() const;
  bool hasClockOffset() const { return clock_.hasOffset(); }
  bool hasUtcOffset() const { return hasUtcOffset_; }
  int32_t utcOffsetSeconds() const { return hasUtcOffset_ ? utcOffsetSeconds_ : 0; }
  bool wallClockMs(int64_t &ms) const;
  double clockOffsetMs() const { return clock_.offsetMs(); }
  bool producerIsV2() const { return producerV2_; }
  void onConnected();
  bool takeCatchUpRequest();
  bool takeSyncBurstRequest();
  unsigned long silenceMs() const { return millis() - lastRxAnyMillis_; }
  unsigned long stalenessLimitMs() const { return producerV2_ ? kProducerStalenessV2Ms : kProducerStalenessMs; }

  const String &selectedRoleIdRef() const { return selectedRoleId_; }
  const RoleView *activeRoleRef() const;
  const MessageView *latestRelevantMessageRef() const;
  const char *currentNoteText() const;
  bool timerFound() const { return timer_.found; }
  bool timerIsHeader() const { return timer_.isHeader(); }
  bool timerIsDurationActual() const { return timer_.isDurationActual; }
  const String &timerTitle() const { return timer_.title; }
  int timerRemainingSeconds() const;

  bool nextFound() const { return next_.found; }
  const char *nextTitle() const { return next_.title; }
  const char *nextId() const { return next_.id; }
  const char *nextNoteText() const;
  bool nextFirstNote(const char *&category, const char *&text) const;
  int nextLengthSeconds() const { return next_.lengthInSeconds; }
  int roleNoteCount() const;
  bool roleNoteAt(int index, const char *&category, const char *&text) const;

  String currentNote() const;
  MessageView latestRelevantMessage() const;

  int roleCount() const { return roleCount_; }
  RoleView roleAt(int index) const { return index >= 0 && index < roleCount_ ? roles_[index] : RoleView{}; }

  bool hasSyncedWithProducer() const { return hasSyncedWithProducer_; }
  bool isProducerLive() const {
    unsigned long limit = producerV2_ ? kProducerStalenessV2Ms : kProducerStalenessMs;
    return hasSyncedWithProducer_ && (millis() - lastProducerPacketAtMillis_ < limit);
  }

  void (*onCueTransition)(CueState newState) = nullptr;
  void (*onMessageReceived)(CueState currentDisplayState) = nullptr;

private:
  static const int kMaxRoles = 8;
  static const int kMaxMessages = 16;
  static const int kMaxNoteCategories = 6;
  static const unsigned long kProducerStalenessMs = 12000;
  static const unsigned long kProducerStalenessV2Ms = 25000;
  static const int kMaxMessageMismatchStreak = 2;
  static const unsigned long kCatchUpRateLimitMs = 5000;
  static constexpr double kMaxMonotonicOffsetMs = 4.2e12;

  bool hasSyncedWithProducer_ = false;
  unsigned long lastProducerPacketAtMillis_ = 0;
  unsigned long lastRxAnyMillis_ = 0;
  unsigned long lastLegacyCatchUpMillis_ = 0;
  unsigned long lastParseErrorCatchUpMillis_ = 0;

  struct NoteEntry { String category; String text; };

  RoleView roles_[kMaxRoles];
  int roleCount_ = 0;
  TimerView timer_;
  NoteEntry notes_[kMaxNoteCategories];
  int noteCount_ = 0;
  NextItemView next_;
  MessageView messages_[kMaxMessages];
  int messageCount_ = 0;

  String selectedRoleId_;
  CueState lastNotifiedState_ = CueState::Off;
  bool hasNotifiedState_ = false;
  String lastSeenMessageId_;

  pagersync::OffsetEstimator clock_;
  pagersync::RevGuard rev_;
  pagersync::Anchor anchor_;
  bool anchored_ = false;
  bool anchorKnown_ = false;
  int64_t anchorRecvLocalMs_ = 0;
  bool producerV2_ = false;
  int32_t utcOffsetSeconds_ = 0;
  bool hasUtcOffset_ = false;
  bool catchUpWanted_ = false;
  bool syncBurstWanted_ = false;
  bool noOffsetBurstDone_ = false;
  pagersync::EpochTracker epoch_;
  bool rolesTruncated_ = false;
  bool messagesOverflowed_ = false;
  int messageMismatchStreak_ = 0;

  void applyRoleCues(JsonArrayConst roles);
  void applyTimerItem(JsonObjectConst timer, bool timing = true);
  bool applyAnchor(JsonVariantConst anchor);
  void applyNextItem(JsonVariantConst next);
  bool categoryAssignedToAnyRole(const char *category) const;
  void resetForEpochChange();
  void applyCueDeltas(JsonArrayConst deltas);
  void handleSyncReply(JsonObjectConst doc);
  void insertMessageSorted(const MessageView &v);
  void handleDigest(JsonObjectConst doc);
  std::string rolesHash() const;
  std::string timerHash() const;
  std::string messagesHash() const;
  void mergeMessages(JsonArrayConst messages);
  void addOneMessage(JsonObjectConst msg);
  void checkForRelevantNewMessage();
  void checkForCueTransition();
};

}
