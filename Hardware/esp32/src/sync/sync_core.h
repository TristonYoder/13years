// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#pragma once
#include <stdint.h>
#include <stddef.h>
#include <math.h>
#include <string.h>
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

inline bool messageOrderBefore(double tsA, const char *idA, double tsB, const char *idB) {
  if (tsA != tsB) return tsA > tsB;
  return strcmp(idA, idB) < 0;
}

inline bool anchorInBounds(int64_t lengthInSeconds, int64_t elapsedMs) {
  return lengthInSeconds >= 0 && lengthInSeconds <= 604800 &&
         elapsedMs >= 0 && elapsedMs <= 604800000LL;
}

inline size_t utf8TruncatedLength(const char *s, size_t maxBytes) {
  size_t n = strlen(s);
  if (n <= maxBytes) return n;
  size_t cut = maxBytes;
  while (cut > 0 && (((uint8_t)s[cut]) & 0xC0) == 0x80) cut--;
  return cut;
}

inline bool copyTruncated(char *dst, size_t dstCap, const char *src) {
  if (dstCap == 0) return false;
  size_t n = utf8TruncatedLength(src, dstCap - 1);
  memcpy(dst, src, n);
  dst[n] = '\0';
  return src[n] != '\0';
}

enum class RevKind { Strict, NotLower, Rebase };

struct RevGuard {
  static const int64_t kMaxJump = 1000000;
  int64_t highest = -1;

  bool accept(int64_t rev, RevKind kind = RevKind::Strict, bool epochChanged = false) {
    if (rev < 0) return true;
    if (kind == RevKind::Rebase) {
      highest = rev;
      return true;
    }
    if (highest >= 0) {
      if (kind == RevKind::Strict ? rev <= highest : rev < highest) return false;
      if (rev - highest > kMaxJump && !epochChanged) return false;
    }
    highest = rev;
    return true;
  }

  void reset() { highest = -1; }
  void resetTo(int64_t rev) { highest = rev; }
};

struct EpochTracker {
  bool have = false;
  int64_t value = 0;

  bool observe(int64_t epoch) {
    if (!have) {
      have = true;
      value = epoch;
      return false;
    }
    if (epoch == value) return false;
    value = epoch;
    return true;
  }

  void reset() { have = false; }
};

class FrameAssembler {
public:
  static const uint32_t kMaxSkipBytes = 1u << 20;

  void init(uint8_t *buf, size_t cap) {
    buf_ = buf;
    cap_ = cap;
    reset();
  }

  void reset() {
    state_ = Header;
    hdr_ = 0;
    acc_ = 0;
    len_ = 0;
    filled_ = 0;
    desync_ = false;
  }

  bool desynced() const { return desync_; }

  template <class OnFrame, class OnSkip>
  bool feed(const uint8_t *d, size_t n, OnFrame onFrame, OnSkip onSkip) {
    size_t i = 0;
    while (i < n) {
      if (state_ == Header) {
        acc_ = (acc_ << 8) | d[i++];
        if (++hdr_ < 4) continue;
        hdr_ = 0;
        len_ = acc_;
        acc_ = 0;
        filled_ = 0;
        if (len_ == 0) continue;
        if (len_ > kMaxSkipBytes) {
          desync_ = true;
          return false;
        }
        state_ = len_ > cap_ ? Skip : Payload;
      } else if (state_ == Payload) {
        size_t take = n - i;
        if (take > len_ - filled_) take = len_ - filled_;
        memcpy(buf_ + filled_, d + i, take);
        filled_ += (uint32_t)take;
        i += take;
        if (filled_ == len_) {
          state_ = Header;
          onFrame(buf_, (size_t)len_);
        }
      } else {
        size_t take = n - i;
        if (take > len_ - filled_) take = len_ - filled_;
        filled_ += (uint32_t)take;
        i += take;
        if (filled_ == len_) {
          state_ = Header;
          onSkip((size_t)len_);
        }
      }
    }
    return true;
  }

private:
  enum State { Header, Payload, Skip };
  uint8_t *buf_ = nullptr;
  size_t cap_ = 0;
  State state_ = Header;
  int hdr_ = 0;
  uint32_t acc_ = 0;
  uint32_t len_ = 0;
  uint32_t filled_ = 0;
  bool desync_ = false;
};

struct Sample {
  double rtt = 0;
  double offset = 0;
  int64_t recvMs = 0;
};

class OffsetEstimator {
public:
  static const int kMaxSamples = 8;
  static constexpr double kJumpThresholdMs = 20.0;
  static constexpr double kSlewFraction = 0.25;
  static constexpr int64_t kMaxAgeMs = 90000;
  static constexpr double kMaxRttMs = 10000.0;
  static constexpr double kDefaultMaxOffsetMs = 86400000.0;
  static constexpr double kDivergeFloorMs = 50.0;

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

  bool addSample(int64_t t0, int64_t t1, int64_t t2, int64_t t3) {
    Sample s = compute(t0, t1, t2, t3);
    if (s.rtt < 0) s.rtt = 0;
    if (s.rtt > kMaxRttMs || fabs(s.offset) > maxAbsOffsetMs_) return false;
    s.recvMs = t3;
    prune(t3);
    if (count_ > 0) {
      double limit = fmax(kDivergeFloorMs, 2.0 * s.rtt);
      if (fabs(s.offset - bestOffset()) > limit) {
        count_ = 0;
        next_ = 0;
      }
    }
    samples_[next_] = s;
    next_ = (next_ + 1) % kMaxSamples;
    if (count_ < kMaxSamples) count_++;
    double target = bestOffset();
    if (!have_) {
      offset_ = target;
      have_ = true;
      return true;
    }
    double delta = target - offset_;
    if (fabs(delta) < kJumpThresholdMs) offset_ += delta * kSlewFraction;
    else offset_ = target;
    return true;
  }

  void prune(int64_t nowMs) {
    Sample kept[kMaxSamples];
    int n = 0;
    int start = (next_ - count_ + kMaxSamples) % kMaxSamples;
    for (int i = 0; i < count_; i++) {
      const Sample &s = samples_[(start + i) % kMaxSamples];
      if (nowMs - s.recvMs <= kMaxAgeMs) kept[n++] = s;
    }
    for (int i = 0; i < n; i++) samples_[i] = kept[i];
    count_ = n;
    next_ = n % kMaxSamples;
  }

  double bestOffset() const {
    int best = -1;
    for (int i = 0; i < count_; i++) {
      int idx = (next_ - count_ + i + 2 * kMaxSamples) % kMaxSamples;
      if (best < 0 || samples_[idx].rtt < samples_[best].rtt) best = idx;
    }
    return best < 0 ? 0.0 : samples_[best].offset;
  }

  void setMaxAbsOffsetMs(double v) { maxAbsOffsetMs_ = v; }

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
  double maxAbsOffsetMs_ = kDefaultMaxOffsetMs;
};

}
