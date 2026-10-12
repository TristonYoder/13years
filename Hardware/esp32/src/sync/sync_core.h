// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#pragma once
#include <stdint.h>
#include <stddef.h>
#include <math.h>
#include <string>

namespace pagersync {

inline uint64_t fnv1a64(const char *data, size_t len) {
  uint64_t h = 0xcbf29ce484222325ULL;
  for (size_t i = 0; i < len; i++) {
    h ^= (uint8_t)data[i];
    h *= 0x100000001b3ULL;
  }
  return h;
}

inline uint64_t fnv1a64(const std::string &s) {
  return fnv1a64(s.data(), s.size());
}

inline std::string hex16(uint64_t v) {
  static const char digits[] = "0123456789abcdef";
  std::string out(16, '0');
  for (int i = 15; i >= 0; i--) {
    out[i] = digits[v & 0xF];
    v >>= 4;
  }
  return out;
}

inline std::string hashHex(const std::string &canonical) {
  return hex16(fnv1a64(canonical));
}

static const char kUS = '\x1F';
static const char kRS = '\x1E';

inline void appendRole(std::string &out, const std::string &id, const std::string &name, const char *state) {
  out += id;
  out += kUS;
  out += name;
  out += kUS;
  out += state;
  out += kRS;
}

inline void appendMessageId(std::string &out, const std::string &id) {
  if (!out.empty()) out += kRS;
  out += id;
}

struct Anchor {
  bool valid = false;
  std::string itemId;
  int64_t lengthInSeconds = 0;
  int64_t elapsedMs = 0;
  int64_t anchorMs = 0;
  bool isRunning = false;
  bool isDurationActual = false;
};

inline std::string timerCanonical(const Anchor &a) {
  if (!a.valid) return "none";
  std::string out = a.itemId;
  out += kUS;
  out += std::to_string((long long)a.lengthInSeconds);
  out += kUS;
  out += a.isRunning ? '1' : '0';
  out += kUS;
  out += a.isDurationActual ? '1' : '0';
  out += kUS;
  out += std::to_string((long long)a.elapsedMs);
  out += kUS;
  out += std::to_string((long long)a.anchorMs);
  return out;
}

inline int64_t anchorElapsedMs(const Anchor &a, int64_t producerNowMs) {
  int64_t e = a.elapsedMs + (a.isRunning ? producerNowMs - a.anchorMs : 0);
  return e < 0 ? 0 : e;
}

inline int64_t anchorElapsedSeconds(const Anchor &a, int64_t producerNowMs) {
  return anchorElapsedMs(a, producerNowMs) / 1000;
}

inline int64_t anchorRemainingSeconds(const Anchor &a, int64_t producerNowMs) {
  return a.lengthInSeconds - anchorElapsedSeconds(a, producerNowMs);
}

struct RevGuard {
  int64_t highest = -1;

  bool accept(int64_t rev) {
    if (rev < 0) return true;
    if (rev < highest) return false;
    highest = rev;
    return true;
  }

  void reset() { highest = -1; }
  void resetTo(int64_t rev) { highest = rev; }
};

struct Sample {
  double rtt = 0;
  double offset = 0;
};

class OffsetEstimator {
public:
  static const int kMaxSamples = 8;
  static constexpr double kJumpThresholdMs = 20.0;
  static constexpr double kSlewFraction = 0.25;

  static Sample compute(int64_t t0, int64_t t1, int64_t t2, int64_t t3) {
    Sample s;
    s.rtt = (double)(t3 - t0) - (double)(t2 - t1);
    s.offset = ((double)(t1 - t0) + (double)(t2 - t3)) / 2.0;
    return s;
  }

  void reset() {
    count_ = 0;
    next_ = 0;
    have_ = false;
    offset_ = 0;
  }

  void addSample(int64_t t0, int64_t t1, int64_t t2, int64_t t3) {
    samples_[next_] = compute(t0, t1, t2, t3);
    next_ = (next_ + 1) % kMaxSamples;
    if (count_ < kMaxSamples) count_++;
    double target = bestOffset();
    if (!have_) {
      offset_ = target;
      have_ = true;
      return;
    }
    double delta = target - offset_;
    if (fabs(delta) < kJumpThresholdMs) offset_ += delta * kSlewFraction;
    else offset_ = target;
  }

  double bestOffset() const {
    int best = -1;
    for (int i = 0; i < count_; i++) {
      if (best < 0 || samples_[i].rtt < samples_[best].rtt) best = i;
    }
    return best < 0 ? 0.0 : samples_[best].offset;
  }

  bool hasOffset() const { return have_; }
  double offsetMs() const { return offset_; }
  int sampleCount() const { return count_; }

  int64_t producerNow(int64_t localNowMs) const {
    return localNowMs + (int64_t)llround(offset_);
  }

private:
  Sample samples_[kMaxSamples];
  int count_ = 0;
  int next_ = 0;
  bool have_ = false;
  double offset_ = 0;
};

}
