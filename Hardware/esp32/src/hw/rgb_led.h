// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#pragma once
#include "cue/cue_state.h"

namespace led {

void init();

void loop();

void setForCueState(CueState state);

void setSearching();

void setRGB(bool red, bool green, bool blue);
void off();

}
