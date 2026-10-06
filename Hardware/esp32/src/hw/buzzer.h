// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#pragma once
#include "cue/cue_state.h"

#ifndef BUZZER_PIN
#define BUZZER_PIN 26
#endif

#ifndef AUDIO_ENABLE_PIN
#define AUDIO_ENABLE_PIN 4
#endif

namespace buzzer {

void init();

void loop();

void playCueTransition(CueState state);

void playMessageReceived(CueState currentDisplayState);

}
