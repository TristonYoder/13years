// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#pragma once
#include <Arduino.h>
#include "../ui/palette.h"

enum class CueState {
  Off,
  Standby,
  Go,
};

inline CueState cueStateFromString(const String &s) {
  if (s == "STANDBY") return CueState::Standby;
  if (s == "GO") return CueState::Go;
  if (s == "FLASH_STANDBY") return CueState::Standby;
  if (s == "FLASH_GO") return CueState::Go;
  return CueState::Off;
}

inline bool cueStateIsStandby(CueState s) {
  return s == CueState::Standby;
}

inline bool cueStateIsGo(CueState s) {
  return s == CueState::Go;
}

inline const char *cueStateDisplayName(CueState s) {
  if (cueStateIsStandby(s)) return "STANDBY";
  if (cueStateIsGo(s)) return "GO!";
  return "";
}

inline const char *cueStateLogName(CueState s) {
  if (cueStateIsStandby(s)) return "STANDBY";
  if (cueStateIsGo(s)) return "GO";
  return "OFF";
}

inline uint32_t cueStateBgColor(CueState s) {
  if (cueStateIsStandby(s)) return kCueStandbyHex;
  if (cueStateIsGo(s)) return kCueGoHex;
  return kDisplayBlackHex;
}

inline uint32_t cueStateTextColor(CueState s) {
  if (cueStateIsStandby(s)) return kCueDarkTextHex;
  return kCueLightTextHex;
}
