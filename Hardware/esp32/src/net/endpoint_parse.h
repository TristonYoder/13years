// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#pragma once

#include <stdint.h>
#include <string>

namespace endpointparse {

inline bool parsePort(const std::string &text, uint16_t &port) {
  if (text.empty() || text.size() > 5) return false;
  unsigned long value = 0;
  for (char c : text) {
    if (c < '0' || c > '9') return false;
    value = value * 10 + (unsigned long)(c - '0');
  }
  if (value < 1 || value > 65535) return false;
  port = (uint16_t)value;
  return true;
}

inline bool splitHostPort(const std::string &input, std::string &host, uint16_t &port) {
  size_t colon = input.find(':');
  if (colon == std::string::npos) {
    if (input.empty()) return false;
    host = input;
    port = 0;
    return true;
  }
  if (input.find(':', colon + 1) != std::string::npos) return false;
  std::string h = input.substr(0, colon);
  if (h.empty()) return false;
  uint16_t p = 0;
  if (!parsePort(input.substr(colon + 1), p)) return false;
  host = h;
  port = p;
  return true;
}


enum class IntroducerKind { None, Direct, NeedsResolve };

struct IntroducerTarget {
  IntroducerKind kind = IntroducerKind::None;
  std::string ip;
  std::string host;
  uint16_t port = 0;
};

inline bool parseIPv4(const std::string &text, std::string &canonical) {
  unsigned parts[4];
  size_t pos = 0;
  for (int i = 0; i < 4; i++) {
    size_t start = pos;
    unsigned value = 0;
    while (pos < text.size() && text[pos] >= '0' && text[pos] <= '9') {
      value = value * 10 + (unsigned)(text[pos] - '0');
      if (value > 255) return false;
      pos++;
    }
    if (pos == start || pos - start > 3) return false;
    parts[i] = value;
    if (i < 3) {
      if (pos >= text.size() || text[pos] != '.') return false;
      pos++;
    }
  }
  if (pos != text.size()) return false;
  canonical = std::to_string(parts[0]) + "." + std::to_string(parts[1]) + "." +
              std::to_string(parts[2]) + "." + std::to_string(parts[3]);
  return true;
}

inline IntroducerTarget decideIntroducer(const std::string &host, const std::string &portText,
                                         const std::string &hostIp, const std::string &mode) {
  IntroducerTarget result;
  if (!mode.empty() && mode != "introducer") return result;
  if (host.empty()) return result;
  uint16_t port = 0;
  if (!parsePort(portText, port)) return result;
  std::string canonical;
  if (parseIPv4(hostIp, canonical) && canonical != "0.0.0.0") {
    result.kind = IntroducerKind::Direct;
    result.ip = canonical;
  } else if (parseIPv4(host, canonical) && canonical != "0.0.0.0") {
    result.kind = IntroducerKind::Direct;
    result.ip = canonical;
  } else if (parseIPv4(host, canonical)) {
    return result;
  } else {
    result.kind = IntroducerKind::NeedsResolve;
  }
  result.host = host;
  result.port = port;
  return result;
}

struct AssignDecision {
  bool accept = false;
  std::string host;
  uint16_t port = 13380;
};

inline bool parseIPv4Octets(const std::string &text, unsigned o[4]) {
  std::string canonical;
  if (!parseIPv4(text, canonical)) return false;
  size_t pos = 0;
  for (int i = 0; i < 4; i++) {
    size_t dot = canonical.find('.', pos);
    o[i] = (unsigned)std::stoul(canonical.substr(pos, dot == std::string::npos ? std::string::npos : dot - pos));
    pos = dot + 1;
  }
  return true;
}

inline bool isPrivateIPv4(const std::string &text) {
  unsigned o[4];
  if (!parseIPv4Octets(text, o)) return false;
  if (o[0] == 10 || o[0] == 127) return true;
  if (o[0] == 172 && o[1] >= 16 && o[1] <= 31) return true;
  if (o[0] == 192 && o[1] == 168) return true;
  if (o[0] == 169 && o[1] == 254) return true;
  if (o[0] == 100 && o[1] >= 64 && o[1] <= 127) return true;
  return false;
}

inline AssignDecision decideAssign(const std::string &host, bool hasPort, long long portValue,
                                   const std::string &mode, const std::string &sender) {
  AssignDecision result;
  std::string canonical;
  if (!parseIPv4(host, canonical) || !isPrivateIPv4(canonical)) return result;
  uint16_t port = 13380;
  if (hasPort) {
    if (portValue < 1 || portValue > 65535) return result;
    port = (uint16_t)portValue;
  }
  std::string senderCanonical;
  bool senderValid = parseIPv4(sender, senderCanonical);
  if (!senderValid || senderCanonical != canonical) {
    if (mode != "introducer") return result;
    if (!senderValid || !isPrivateIPv4(senderCanonical)) return result;
  }
  result.accept = true;
  result.host = canonical;
  result.port = port;
  return result;
}

}
