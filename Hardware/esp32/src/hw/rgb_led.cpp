// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#include "rgb_led.h"
#include <Arduino.h>
#include <math.h>

#ifndef LED_RED_PIN
#define LED_RED_PIN 22
#endif
#ifndef LED_GREEN_PIN
#define LED_GREEN_PIN 16
#endif
#ifndef LED_BLUE_PIN
#define LED_BLUE_PIN 17
#endif

static const int kRedLedcChannel = 1;
static const int kGreenLedcChannel = 2;
static const int kBlueLedcChannel = 3;
static const int kLedcFreqHz = 5000;
static const int kLedcResBits = 8;

static void setBrightness(int ledcChannel, uint8_t brightness) {
  ledcWrite(ledcChannel, 255 - brightness);
}

static void writeChannel(int ledcChannel, bool on) {
  setBrightness(ledcChannel, on ? 255 : 0);
}

enum class AnimState { Idle, StandbyPulse, GoFlash, GoSolid, SearchFade };
static AnimState animState = AnimState::Idle;
static unsigned long animStartedAt = 0;
static unsigned long lastToggleAt = 0;
static bool litNow = false;

static const unsigned long kStandbyPulsePeriodMs = 1800;
static unsigned long standbyPulseStartedAt = 0;
static const unsigned long kGoFlashHalfPeriodMs = 200;
static const unsigned long kGoFlashDurationMs = 5000;

static const unsigned long kSearchSegmentMs = 3000;
static int searchSegment = 0;
static unsigned long searchSegmentStartedAt = 0;

void led::init() {
  pinMode(LED_RED_PIN, OUTPUT);
  pinMode(LED_GREEN_PIN, OUTPUT);
  pinMode(LED_BLUE_PIN, OUTPUT);
  ledcSetup(kRedLedcChannel, kLedcFreqHz, kLedcResBits);
  ledcSetup(kGreenLedcChannel, kLedcFreqHz, kLedcResBits);
  ledcSetup(kBlueLedcChannel, kLedcFreqHz, kLedcResBits);
  ledcAttachPin(LED_RED_PIN, kRedLedcChannel);
  ledcAttachPin(LED_GREEN_PIN, kGreenLedcChannel);
  ledcAttachPin(LED_BLUE_PIN, kBlueLedcChannel);
  off();
  Serial.printf("[led] init — R=GPIO%d G=GPIO%d B=GPIO%d (active-LOW PWM, per Elegoo's official pinout)\n",
                LED_RED_PIN, LED_GREEN_PIN, LED_BLUE_PIN);
}

void led::setRGB(bool red, bool green, bool blue) {
  animState = AnimState::Idle;
  writeChannel(kRedLedcChannel, red);
  writeChannel(kGreenLedcChannel, green);
  writeChannel(kBlueLedcChannel, blue);
}

void led::off() {
  setRGB(false, false, false);
}

void led::setForCueState(CueState state) {
  unsigned long now = millis();
  if (cueStateIsGo(state)) {
    animState = AnimState::GoFlash;
    animStartedAt = now;
    lastToggleAt = now;
    litNow = true;
    writeChannel(kRedLedcChannel, false);
    writeChannel(kGreenLedcChannel, true);
    writeChannel(kBlueLedcChannel, false);
    Serial.println("[led] -> GREEN flash (Go) for 5s, then solid");
  } else if (cueStateIsStandby(state)) {
    animState = AnimState::StandbyPulse;
    standbyPulseStartedAt = now;
    writeChannel(kBlueLedcChannel, false);
    setBrightness(kRedLedcChannel, 255);
    setBrightness(kGreenLedcChannel, 255);
    Serial.println("[led] -> YELLOW pulse (Standby)");
  } else {
    animState = AnimState::Idle;
    writeChannel(kRedLedcChannel, false);
    writeChannel(kGreenLedcChannel, false);
    writeChannel(kBlueLedcChannel, false);
    Serial.println("[led] -> OFF (Clear)");
  }
}

void led::setSearching() {
  animState = AnimState::SearchFade;
  searchSegment = 0;
  searchSegmentStartedAt = millis();
  writeChannel(kBlueLedcChannel, false);
  setBrightness(kRedLedcChannel, 255);
  setBrightness(kGreenLedcChannel, 0);
  Serial.println("[led] -> searching (red/yellow/green fade loop)");
}

void led::loop() {
  unsigned long now = millis();

  if (animState == AnimState::StandbyPulse) {
    unsigned long elapsed = (now - standbyPulseStartedAt) % kStandbyPulsePeriodMs;
    float phase = (float)elapsed / (float)kStandbyPulsePeriodMs;
    uint8_t brightness = (uint8_t)((1.0f - cosf(phase * 2.0f * (float)PI)) * 0.5f * 255.0f);
    setBrightness(kRedLedcChannel, brightness);
    setBrightness(kGreenLedcChannel, brightness);
    return;
  }

  if (animState == AnimState::GoFlash) {
    if (now - animStartedAt >= kGoFlashDurationMs) {
      animState = AnimState::GoSolid;
      writeChannel(kGreenLedcChannel, true);
      Serial.println("[led] Go flash done -> solid green");
      return;
    }
    if (now - lastToggleAt >= kGoFlashHalfPeriodMs) {
      lastToggleAt = now;
      litNow = !litNow;
      writeChannel(kGreenLedcChannel, litNow);
    }
    return;
  }

  if (animState == AnimState::SearchFade) {
    unsigned long elapsed = now - searchSegmentStartedAt;
    if (elapsed >= kSearchSegmentMs) {
      searchSegment = (searchSegment + 1) % 3;
      searchSegmentStartedAt = now;
      elapsed = 0;
    }
    uint8_t t = (uint8_t)((elapsed * 255UL) / kSearchSegmentMs);
    switch (searchSegment) {
      case 0:
        setBrightness(kRedLedcChannel, 255);
        setBrightness(kGreenLedcChannel, t);
        break;
      case 1:
        setBrightness(kRedLedcChannel, 255 - t);
        setBrightness(kGreenLedcChannel, 255);
        break;
      case 2:
        setBrightness(kRedLedcChannel, t);
        setBrightness(kGreenLedcChannel, 255 - t);
        break;
    }
    return;
  }

}
