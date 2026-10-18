// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#pragma once
#include "sync_core.h"

#if defined(__has_include)
#if __has_include(<ArduinoJson.h>)
#include <ArduinoJson.h>
#define PAGERSYNC_HAVE_JSON 1
#endif
#endif

namespace pagersync {

enum PagerFieldBit : uint16_t {
  kFieldKey = 1 << 0,
  kFieldBpm = 1 << 1,
  kFieldMeter = 1 << 2,
  kFieldArrangement = 1 << 3,
  kFieldSequence = 1 << 4,
  kFieldDescription = 1 << 5,
  kFieldMediaType = 1 << 6,
  kFieldServicePosition = 1 << 7,
  kFieldStartTime = 1 << 8,
  kFieldLeader = 1 << 9,
  kFieldType = 1 << 10,
  kFieldLength = 1 << 11,
};

static const int kFieldBitCount = 12;

inline uint16_t parsePagerField(const char *name) {
  if (!name) return 0;
  if (strcmp(name, "key") == 0) return kFieldKey;
  if (strcmp(name, "bpm") == 0) return kFieldBpm;
  if (strcmp(name, "meter") == 0) return kFieldMeter;
  if (strcmp(name, "arrangement") == 0) return kFieldArrangement;
  if (strcmp(name, "sequence") == 0) return kFieldSequence;
  if (strcmp(name, "description") == 0) return kFieldDescription;
  if (strcmp(name, "mediaType") == 0) return kFieldMediaType;
  if (strcmp(name, "servicePosition") == 0) return kFieldServicePosition;
  if (strcmp(name, "startTime") == 0) return kFieldStartTime;
  if (strcmp(name, "leader") == 0) return kFieldLeader;
  if (strcmp(name, "type") == 0) return kFieldType;
  if (strcmp(name, "length") == 0) return kFieldLength;
  return 0;
}

struct FieldOrder {
  static const int kMax = 16;
  uint16_t bits[kMax] = {0};
  int count = 0;

  bool add(uint16_t bit) {
    if (bit == 0 || count >= kMax) return false;
    for (int i = 0; i < count; i++) {
      if (bits[i] == bit) return false;
    }
    bits[count++] = bit;
    return true;
  }

  uint16_t mask() const {
    uint16_t m = 0;
    for (int i = 0; i < count; i++) m |= bits[i];
    return m;
  }

  static FieldOrder fromMask(uint16_t mask) {
    FieldOrder order;
    for (int b = 0; b < kFieldBitCount; b++) {
      if (mask & (1u << b)) order.add((uint16_t)(1u << b));
    }
    return order;
  }
};

struct NoteRef {
  const char *category;
  const char *text;
};

inline int orderedNoteIndex(const char *const *roleCategories, int roleCategoryCount, const NoteRef *notes, int noteCount, int nth) {
  int seen = 0;
  for (int c = 0; c < roleCategoryCount; c++) {
    if (!roleCategories[c]) continue;
    for (int n = 0; n < noteCount; n++) {
      if (!notes[n].category || !notes[n].text || !notes[n].text[0]) continue;
      if (strcmp(notes[n].category, roleCategories[c]) != 0) continue;
      if (seen == nth) return n;
      seen++;
      break;
    }
  }
  return -1;
}

enum class ServicePosition : uint8_t { During, Pre, Post };

struct ItemDetails {
  static const size_t kKeyCap = 12;
  static const size_t kBpmCap = 8;
  static const size_t kMeterCap = 12;
  static const size_t kArrangementCap = 32;
  static const size_t kSequenceCap = 64;
  static const size_t kDescriptionCap = 96;
  static const size_t kMediaCap = 24;
  static const size_t kLeaderCap = 40;
  static const size_t kTypeCap = 24;
  static const size_t kLengthCap = 12;

  char key[kKeyCap] = {0};
  char bpm[kBpmCap] = {0};
  char meter[kMeterCap] = {0};
  char arrangement[kArrangementCap] = {0};
  char sequence[kSequenceCap] = {0};
  char description[kDescriptionCap] = {0};
  char mediaType[kMediaCap] = {0};
  char leader[kLeaderCap] = {0};
  char type[kTypeCap] = {0};
  char length[kLengthCap] = {0};
  ServicePosition position = ServicePosition::During;

  void clear() { *this = ItemDetails(); }
};

inline bool isSpaceChar(char c) {
  return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v';
}

inline void collapseWhitespace(char *dst, size_t cap, const char *src) {
  if (cap == 0) return;
  size_t n = 0;
  bool pendingSpace = false;
  for (const char *p = src ? src : ""; *p && n + 1 < cap; p++) {
    if (isSpaceChar(*p)) {
      pendingSpace = n > 0;
      continue;
    }
    if (pendingSpace) {
      if (n + 2 >= cap) break;
      dst[n++] = ' ';
      pendingSpace = false;
    }
    dst[n++] = *p;
  }
  dst[n] = '\0';
}

inline void titleCaseWords(char *dst, size_t cap, const char *src) {
  if (cap == 0) return;
  size_t n = 0;
  bool startOfWord = true;
  for (const char *p = src ? src : ""; *p && n + 1 < cap; p++) {
    char c = *p == '_' ? ' ' : *p;
    if (isSpaceChar(c)) {
      startOfWord = true;
    } else if (startOfWord) {
      if (c >= 'a' && c <= 'z') c = (char)(c - 32);
      startOfWord = false;
    } else if (c >= 'A' && c <= 'Z') {
      c = (char)(c + 32);
    }
    dst[n++] = c;
  }
  dst[n] = '\0';
}

inline void formatBpm(double bpm, char *out, size_t cap) {
  if (cap == 0) return;
  out[0] = '\0';
  if (!(bpm > 0) || !isfinite(bpm)) return;
  if (bpm == floor(bpm)) snprintf(out, cap, "%d", (int)bpm);
  else snprintf(out, cap, "%.1f", bpm);
}

inline void formatClockHM(int64_t epochMs, int64_t utcOffsetSeconds, bool use24h, char *out, size_t cap) {
  int64_t local = floorDiv(epochMs, 1000) + utcOffsetSeconds;
  int64_t sod = local - floorDiv(local, 86400) * 86400;
  int h24 = (int)(sod / 3600);
  int m = (int)((sod % 3600) / 60);
  if (use24h) {
    snprintf(out, cap, "%02d:%02d", h24, m);
    return;
  }
  int h12 = h24 % 12;
  if (h12 == 0) h12 = 12;
  snprintf(out, cap, "%d:%02d %s", h12, m, h24 < 12 ? "AM" : "PM");
}

inline bool currentStartMs(bool isRunning, int elapsedSeconds, int64_t nowMs, int64_t &out) {
  if (!isRunning && elapsedSeconds <= 0) return false;
  out = nowMs - (int64_t)elapsedSeconds * 1000;
  return true;
}

inline bool nextStartMs(bool haveProjected, int64_t projectedMs, bool isRunning, int remainingSeconds, int64_t nowMs, int64_t &out) {
  bool have = false;
  int64_t best = 0;
  if (haveProjected) {
    best = projectedMs;
    have = true;
  }
  if (isRunning) {
    int64_t viaRemaining = nowMs + (int64_t)(remainingSeconds > 0 ? remainingSeconds : 0) * 1000;
    if (!have || viaRemaining > best) best = viaRemaining;
    have = true;
  }
  if (have) out = best;
  return have;
}

inline void appendSegment(char *out, size_t cap, size_t &len, const char *separator, const char *text) {
  if (!text || !text[0] || cap == 0) return;
  size_t sepLen = len > 0 ? strlen(separator) : 0;
  size_t textLen = strlen(text);
  if (len + sepLen + 1 >= cap) return;
  if (len + sepLen + textLen + 1 > cap) textLen = cap - 1 - len - sepLen;
  if (len > 0) {
    memcpy(out + len, separator, sepLen);
    len += sepLen;
  }
  memcpy(out + len, text, textLen);
  len += textLen;
  out[len] = '\0';
}

inline void setItemBasics(ItemDetails &d, const char *itemType, int lengthInSeconds) {
  titleCaseWords(d.type, sizeof(d.type), itemType);
  d.length[0] = '\0';
  if (lengthInSeconds > 0) formatLength(lengthInSeconds, d.length, sizeof(d.length));
}

inline void formatLeaders(char *dst, size_t cap, const char *first, const char *second, int count) {
  if (cap == 0) return;
  dst[0] = '\0';
  if (count <= 0 || !first || !first[0]) return;
  if (count == 1) snprintf(dst, cap, "%s", first);
  else if (count == 2) snprintf(dst, cap, "%s & %s", first, second ? second : "");
  else snprintf(dst, cap, "%s + %d", first, count - 1);
}

inline bool formatDetailsLine(const ItemDetails &d, const FieldOrder &order, bool haveStart, int64_t startMs, int64_t utcOffsetSeconds, bool use24h, char *out, size_t cap) {
  if (cap == 0) return false;
  out[0] = '\0';
  size_t len = 0;
  const char *sep = " | ";
  for (int i = 0; i < order.count; i++) {
    switch (order.bits[i]) {
      case kFieldKey: appendSegment(out, cap, len, sep, d.key); break;
      case kFieldBpm:
        if (d.bpm[0]) {
          char b[ItemDetails::kBpmCap + 8];
          snprintf(b, sizeof(b), "%s BPM", d.bpm);
          appendSegment(out, cap, len, sep, b);
        }
        break;
      case kFieldMeter: appendSegment(out, cap, len, sep, d.meter); break;
      case kFieldArrangement: appendSegment(out, cap, len, sep, d.arrangement); break;
      case kFieldSequence: appendSegment(out, cap, len, sep, d.sequence); break;
      case kFieldDescription: appendSegment(out, cap, len, sep, d.description); break;
      case kFieldMediaType: appendSegment(out, cap, len, sep, d.mediaType); break;
      case kFieldServicePosition:
        if (d.position == ServicePosition::Pre) appendSegment(out, cap, len, sep, "Pre-service");
        else if (d.position == ServicePosition::Post) appendSegment(out, cap, len, sep, "Post-service");
        break;
      case kFieldStartTime:
        if (haveStart) {
          char t[16];
          formatClockHM(startMs, utcOffsetSeconds, use24h, t, sizeof(t));
          char s[24];
          snprintf(s, sizeof(s), "@ %s", t);
          appendSegment(out, cap, len, sep, s);
        }
        break;
      case kFieldLeader: appendSegment(out, cap, len, sep, d.leader); break;
      case kFieldType: appendSegment(out, cap, len, sep, d.type); break;
      case kFieldLength: appendSegment(out, cap, len, sep, d.length); break;
      default: break;
    }
  }
  return len > 0;
}

inline bool formatDetailsLine(const ItemDetails &d, uint16_t fields, bool haveStart, int64_t startMs, int64_t utcOffsetSeconds, bool use24h, char *out, size_t cap) {
  return formatDetailsLine(d, FieldOrder::fromMask(fields), haveStart, startMs, utcOffsetSeconds, use24h, out, cap);
}

#ifdef PAGERSYNC_HAVE_JSON

inline uint16_t parsePagerFields(JsonVariantConst v) {
  uint16_t mask = 0;
  if (!v.is<JsonArrayConst>()) return 0;
  for (JsonVariantConst f : v.as<JsonArrayConst>()) {
    mask |= parsePagerField(f.is<const char *>() ? f.as<const char *>() : nullptr);
  }
  return mask;
}

inline FieldOrder parsePagerFieldOrder(JsonVariantConst v) {
  FieldOrder order;
  if (!v.is<JsonArrayConst>()) return order;
  for (JsonVariantConst f : v.as<JsonArrayConst>()) {
    order.add(parsePagerField(f.is<const char *>() ? f.as<const char *>() : nullptr));
  }
  return order;
}

inline void buildRoleCueFilter(JsonObject role) {
  role["id"] = true;
  role["name"] = true;
  role["personName"] = true;
  role["clockFormat"] = true;
  role["state"] = true;
  role["assignedNoteCategories"] = true;
  role["pagerFields"] = true;
}

inline const char *firstNonEmpty(const char *a, const char *b, const char *c) {
  if (a && a[0]) return a;
  if (b && b[0]) return b;
  if (c && c[0]) return c;
  return "";
}

inline void joinSequence(char *dst, size_t cap, JsonArrayConst items) {
  size_t n = 0;
  if (cap == 0) return;
  dst[0] = '\0';
  for (JsonVariantConst v : items) {
    const char *s = v.is<const char *>() ? v.as<const char *>() : "";
    size_t l = strlen(s);
    if (l == 0) continue;
    size_t need = l + (n > 0 ? 1 : 0);
    if (n + need + 1 > cap) break;
    if (n > 0) dst[n++] = ' ';
    memcpy(dst + n, s, l);
    n += l;
    dst[n] = '\0';
  }
}

inline void parseItemDetails(ItemDetails &d, JsonVariantConst v) {
  d.clear();
  if (!v.is<JsonObjectConst>()) return;
  JsonObjectConst o = v.as<JsonObjectConst>();
  const char *position = o["servicePosition"] | "";
  if (strcmp(position, "pre") == 0) d.position = ServicePosition::Pre;
  else if (strcmp(position, "post") == 0) d.position = ServicePosition::Post;
  const char *key = firstNonEmpty(o["key"]["startingKey"] | "", o["keyName"] | "", o["key"]["name"] | "");
  copyTruncated(d.key, sizeof(d.key), key);
  formatBpm(o["arrangement"]["bpm"] | 0.0, d.bpm, sizeof(d.bpm));
  copyTruncated(d.meter, sizeof(d.meter), o["arrangement"]["meter"] | "");
  copyTruncated(d.arrangement, sizeof(d.arrangement), o["arrangement"]["name"] | "");
  JsonArrayConst custom = o["customSequenceShort"].as<JsonArrayConst>();
  if (!custom.isNull() && custom.size() > 0) joinSequence(d.sequence, sizeof(d.sequence), custom);
  else joinSequence(d.sequence, sizeof(d.sequence), o["arrangement"]["sequenceShort"].as<JsonArrayConst>());
  collapseWhitespace(d.description, sizeof(d.description), o["description"] | "");
  titleCaseWords(d.mediaType, sizeof(d.mediaType), o["media"]["mediaType"] | "");
  JsonArrayConst leaders = o["leaders"].as<JsonArrayConst>();
  if (!leaders.isNull()) {
    char names[2][16] = {{0}, {0}};
    int count = 0;
    for (JsonVariantConst l : leaders) {
      const char *name = l["firstName"] | (l["name"] | "");
      if (!name[0]) continue;
      if (count < 2) copyTruncated(names[count], sizeof(names[count]), name);
      count++;
    }
    formatLeaders(d.leader, sizeof(d.leader), names[0], names[1], count);
  }
}

inline void buildDetailsFilter(JsonObject details) {
  details["servicePosition"] = true;
  details["keyName"] = true;
  details["description"] = true;
  details["customSequenceShort"] = true;
  JsonObject key = details["key"].to<JsonObject>();
  key["name"] = true;
  key["startingKey"] = true;
  JsonObject arrangement = details["arrangement"].to<JsonObject>();
  arrangement["name"] = true;
  arrangement["bpm"] = true;
  arrangement["meter"] = true;
  arrangement["sequenceShort"] = true;
  details["media"].to<JsonObject>()["mediaType"] = true;
  details["leaders"][0]["firstName"] = true;
}

inline void buildTimerItemFilter(JsonObject item) {
  item["id"] = true;
  item["title"] = true;
  item["itemType"] = true;
  item["lengthInSeconds"] = true;
  item["elapsedSeconds"] = true;
  item["isRunning"] = true;
  item["isDurationActual"] = true;
  item["notes"] = true;
  buildDetailsFilter(item["details"].to<JsonObject>());
}

inline void buildNextItemFilter(JsonObject item) {
  item["id"] = true;
  item["title"] = true;
  item["itemType"] = true;
  item["lengthInSeconds"] = true;
  item["notes"] = true;
  item["startsAtMs"] = true;
  buildDetailsFilter(item["details"].to<JsonObject>());
}

#endif

}
