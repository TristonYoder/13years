// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#pragma once
#include "cue/cue_engine.h"

namespace ui {

enum class Phase { Boot, WifiPrompt, Connecting, Running };

void init();

void setDisplayFlipped(bool flipped);
bool isDisplayFlipped();

void update(Phase phase, cue::Engine &engine, bool wifiConnected, bool lanConnected);

void setBacklight(uint8_t percent);

void runTouchCalibration();

void runRawTouchReadout(uint32_t durationMs);

}
