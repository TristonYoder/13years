// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#pragma once
#include <stdint.h>
#include <string.h>
#include <math.h>

// The producer's timer color scale (the `timerColors` field of TIMER_UPDATE, TIMER_ANCHOR, CUE_UPDATE and
// PONG), and how to turn it into a countdown color and effect. Pure logic, so the native test can run it.
// The pager colors nothing when the producer sent no scale; it never makes one up.

namespace pagersync {

enum class TimerEffect : uint8_t { None = 0, Pulse, Blink, Flicker, Glitch };

static const int kMaxTimerColorStops = 12;

struct TimerColorStop {
  bool overtime = false;
  bool percent = false;
  int32_t value = 0;
  uint32_t rgb = 0;
  TimerEffect effect = TimerEffect::None;
};

struct TimerColorScale {
  bool valid = false;
  bool hasOnTime = false;
  uint32_t onTimeRgb = 0;
  uint32_t overtimeRgb = 0xCC1717;
  TimerEffect overtimeEffect = TimerEffect::None;
  // How far over before the overtime color starts; until then the lead-up look continues.
  bool overtimeStartPercent = false;
  int32_t overtimeStartValue = 0;
  int stopCount = 0;
  TimerColorStop stops[kMaxTimerColorStops];

  void clear() {
    valid = false;
    hasOnTime = false;
    stopCount = 0;
    overtimeEffect = TimerEffect::None;
    overtimeStartPercent = false;
    overtimeStartValue = 0;
  }
};

struct TimerStyle {
  bool hasColor = false;
  uint32_t rgb = 0;
  TimerEffect effect = TimerEffect::None;
};

inline bool parseHexRgb(const char *s, uint32_t &out) {
  if (!s || strlen(s) != 6) return false;
  uint32_t v = 0;
  for (int i = 0; i < 6; i++) {
    char c = s[i];
    uint32_t d;
    if (c >= '0' && c <= '9') d = c - '0';
    else if (c >= 'a' && c <= 'f') d = 10 + c - 'a';
    else if (c >= 'A' && c <= 'F') d = 10 + c - 'A';
    else return false;
    v = (v << 4) | d;
  }
  out = v;
  return true;
}

inline TimerEffect parseTimerEffect(const char *s) {
  if (!s) return TimerEffect::None;
  if (strcmp(s, "pulse") == 0) return TimerEffect::Pulse;
  if (strcmp(s, "blink") == 0) return TimerEffect::Blink;
  if (strcmp(s, "flicker") == 0) return TimerEffect::Flicker;
  if (strcmp(s, "glitch") == 0) return TimerEffect::Glitch;
  return TimerEffect::None;
}

// Remaining seconds at which a stop takes over (lead-up), or overtime seconds it takes over at.
inline double timerStopThreshold(const TimerColorStop &stop, int lengthSeconds) {
  if (stop.percent) {
    int pct = stop.value < 0 ? 0 : (stop.value > 100 ? 100 : stop.value);
    return (double)(lengthSeconds > 0 ? lengthSeconds : 0) * pct / 100.0;
  }
  return (double)(stop.value < 0 ? 0 : stop.value);
}

// Lead-up stops: of those reached (remaining <= threshold) the one closest to zero. Overtime: the deepest stop
// reached, else the scale's overtime color. On time: the on-time color, if there is one.
inline TimerStyle evaluateTimerColors(const TimerColorScale &scale, int remainingSeconds, int lengthSeconds) {
  TimerStyle out;
  if (!scale.valid) return out;
  if (remainingSeconds < 0) {
    double over = (double)(-(int64_t)remainingSeconds);
    TimerColorStop start;
    start.percent = scale.overtimeStartPercent;
    start.value = scale.overtimeStartValue;
    if (over < timerStopThreshold(start, lengthSeconds)) return evaluateTimerColors(scale, 0, lengthSeconds);
    int best = -1;
    double bestT = 0;
    for (int i = 0; i < scale.stopCount; i++) {
      const TimerColorStop &s = scale.stops[i];
      if (!s.overtime) continue;
      double t = timerStopThreshold(s, lengthSeconds);
      if (over >= t && (best < 0 || t > bestT)) { best = i; bestT = t; }
    }
    out.hasColor = true;
    if (best >= 0) {
      out.rgb = scale.stops[best].rgb;
      out.effect = scale.stops[best].effect;
    } else {
      out.rgb = scale.overtimeRgb;
      out.effect = scale.overtimeEffect;
    }
    return out;
  }
  int best = -1;
  double bestT = 0;
  for (int i = 0; i < scale.stopCount; i++) {
    const TimerColorStop &s = scale.stops[i];
    if (s.overtime) continue;
    double t = timerStopThreshold(s, lengthSeconds);
    if ((double)remainingSeconds <= t && (best < 0 || t < bestT)) { best = i; bestT = t; }
  }
  if (best >= 0) {
    out.hasColor = true;
    out.rgb = scale.stops[best].rgb;
    out.effect = scale.stops[best].effect;
  } else if (scale.hasOnTime) {
    out.hasColor = true;
    out.rgb = scale.onTimeRgb;
  }
  return out;
}

inline uint32_t timerEffectHash(uint32_t n) {
  n ^= n >> 16; n *= 0x7feb352dU; n ^= n >> 15; n *= 0x846ca68bU; n ^= n >> 16;
  return n;
}

// One animation frame of an effect: text opacity 0..255 and a horizontal offset in pixels (glitch only).
struct TimerEffectFrame {
  uint8_t opacity = 255;
  int16_t offsetX = 0;
};

inline TimerEffectFrame timerEffectFrame(TimerEffect effect, uint32_t nowMs) {
  TimerEffectFrame f;
  switch (effect) {
    case TimerEffect::Pulse: {
      double phase = (double)(nowMs % 1400) / 1400.0;
      f.opacity = (uint8_t)(158.0 + 97.0 * (0.5 + 0.5 * sin(phase * 2.0 * 3.14159265358979)));
      break;
    }
    case TimerEffect::Blink:
      f.opacity = (nowMs % 1000) < 600 ? 255 : 26;
      break;
    case TimerEffect::Flicker: {
      uint32_t r = timerEffectHash(nowMs / 70) % 100;
      f.opacity = r < 62 ? 255 : (r < 85 ? 140 : 50);
      break;
    }
    case TimerEffect::Glitch:
      if ((nowMs % 2200) < 280) {
        uint32_t r = timerEffectHash(nowMs / 42) % 100;
        f.offsetX = (int16_t)(((int)r - 50) / 10);
        f.opacity = r % 3 == 0 ? 170 : 255;
      }
      break;
    case TimerEffect::None:
      break;
  }
  return f;
}

}  // namespace pagersync

#if defined(ARDUINOJSON_VERSION)
namespace pagersync {

// Reads `timerColors`. Anything malformed leaves the scale invalid (nothing colored).
inline bool parseTimerColorScale(JsonVariantConst v, TimerColorScale &out) {
  out.clear();
  if (!v.is<JsonObjectConst>()) return false;
  JsonObjectConst obj = v.as<JsonObjectConst>();
  uint32_t rgb = 0;
  if (obj["onTimeHex"].is<const char *>() && parseHexRgb(obj["onTimeHex"].as<const char *>(), rgb)) {
    out.hasOnTime = true;
    out.onTimeRgb = rgb;
  }
  if (obj["overtimeHex"].is<const char *>() && parseHexRgb(obj["overtimeHex"].as<const char *>(), rgb)) {
    out.overtimeRgb = rgb;
  }
  out.overtimeEffect = parseTimerEffect(obj["overtimeEffect"] | "");
  if (obj["overtimeStart"].is<JsonObjectConst>()) {
    JsonObjectConst start = obj["overtimeStart"].as<JsonObjectConst>();
    out.overtimeStartValue = start["value"] | 0;
    out.overtimeStartPercent = strcmp(start["unit"] | "seconds", "percent") == 0;
  }
  if (obj["stops"].is<JsonArrayConst>()) {
    for (JsonObjectConst s : obj["stops"].as<JsonArrayConst>()) {
      if (out.stopCount >= kMaxTimerColorStops) break;
      if (!(s["colorHex"].is<const char *>()) || !parseHexRgb(s["colorHex"].as<const char *>(), rgb)) continue;
      TimerColorStop stop;
      stop.rgb = rgb;
      stop.overtime = strcmp(s["phase"] | "remaining", "overtime") == 0;
      stop.percent = strcmp(s["unit"] | "seconds", "percent") == 0;
      stop.value = s["value"] | 0;
      stop.effect = parseTimerEffect(s["effect"] | "");
      out.stops[out.stopCount++] = stop;
    }
  }
  out.valid = true;
  return true;
}

}  // namespace pagersync
#endif
