// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#pragma once
#include "cue/cue_engine.h"

namespace lan {

void begin(cue::Engine *engine);

void loop();

bool isConnected();

bool isStaticFallbackActive();

void resetStaticFallback();

}
