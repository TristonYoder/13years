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

}
