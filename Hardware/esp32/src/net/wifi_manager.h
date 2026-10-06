// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#pragma once
#include <Arduino.h>

namespace wifinet {

enum class State { Disconnected, Connecting, Connected };

void begin();

State loop();

bool isConnected();

void applyNewCredentials(const String &ssid, const String &pass);

}
