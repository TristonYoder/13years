// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#include "buzzer.h"
#include <Arduino.h>

static const int kMaxSteps = 16;
static unsigned long stepDurationsMs[kMaxSteps];
static int stepCount = 0;
static int currentStep = -1;
static unsigned long stepStartedAt = 0;

static void setPin(bool on) {
  digitalWrite(BUZZER_PIN, on ? HIGH : LOW);
}

static void startPulsePattern(int pulseCount, unsigned long onMs, unsigned long gapMs, const char *label) {
  int steps = pulseCount * 2 - 1;
  if (steps > kMaxSteps) steps = kMaxSteps;
  for (int i = 0; i < steps; i++) {
    stepDurationsMs[i] = (i % 2 == 0) ? onMs : gapMs;
  }
  stepCount = steps;
  currentStep = 0;
  stepStartedAt = millis();
  setPin(true);
  Serial.printf("[buzzer] %s — %d pulse(s), %lums on / %lums gap (pin=%d, hardware not yet installed)\n",
                label, pulseCount, onMs, gapMs, BUZZER_PIN);
}

void buzzer::init() {
  pinMode(BUZZER_PIN, OUTPUT);
  setPin(false);
  pinMode(AUDIO_ENABLE_PIN, OUTPUT);
  digitalWrite(AUDIO_ENABLE_PIN, LOW);
  Serial.printf("[buzzer] init — pin=GPIO%d, amp enable=GPIO%d (no speaker/buzzer confirmed connected yet — see README.md)\n",
                BUZZER_PIN, AUDIO_ENABLE_PIN);
}

void buzzer::loop() {
  if (currentStep < 0) return;
  if (millis() - stepStartedAt < stepDurationsMs[currentStep]) return;

  currentStep++;
  stepStartedAt = millis();
  if (currentStep >= stepCount) {
    setPin(false);
    currentStep = -1;
    Serial.println("[buzzer] pattern complete");
    return;
  }
  setPin(currentStep % 2 == 0);
}

void buzzer::playCueTransition(CueState state) {
  if (state == CueState::Off) return;
  if (cueStateIsGo(state)) {
    startPulsePattern(6, 500, 100, "cue -> GO!");
  } else {
    startPulsePattern(1, 2000, 0, "cue -> Standby");
  }
}

void buzzer::playMessageReceived(CueState currentDisplayState) {
  if (cueStateIsGo(currentDisplayState)) {
    startPulsePattern(5, 50, 100, "message received (Go)");
  } else {
    startPulsePattern(3, 450, 200, "message received (Standby)");
  }
}
