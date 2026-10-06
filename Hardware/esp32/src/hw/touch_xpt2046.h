// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#pragma once
#include <Arduino.h>

namespace touch {

void init();

void readRaw(uint16_t &x, uint16_t &y, uint16_t &z);

bool read(uint16_t &x, uint16_t &y);

void setFlipped(bool flipped);

}
