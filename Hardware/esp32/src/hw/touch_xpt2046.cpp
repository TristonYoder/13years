// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#include "touch_xpt2046.h"
#include <SPI.h>

#ifndef TOUCH_SCLK_PIN
#define TOUCH_SCLK_PIN 25
#endif
#ifndef TOUCH_MOSI_PIN
#define TOUCH_MOSI_PIN 32
#endif
#ifndef TOUCH_MISO_PIN
#define TOUCH_MISO_PIN 39
#endif
#ifndef TOUCH_CS_PIN
#define TOUCH_CS_PIN 33
#endif
#ifndef TOUCH_IRQ_PIN
#define TOUCH_IRQ_PIN 36
#endif

static SPIClass touchSPI(HSPI);
static const uint32_t kTouchSpiHz = 2500000;

static const uint16_t kPressureThreshold = 400;

#define TOUCH_SWAP_XY 0
#define TOUCH_INVERT_X 0
#define TOUCH_INVERT_Y 0
static const uint16_t kRawXMin = 300, kRawXMax = 3800;
static const uint16_t kRawYMin = 300, kRawYMax = 3800;

static void beginTransaction() {
  touchSPI.beginTransaction(SPISettings(kTouchSpiHz, MSBFIRST, SPI_MODE0));
  digitalWrite(TOUCH_CS_PIN, LOW);
}

static void endTransaction() {
  digitalWrite(TOUCH_CS_PIN, HIGH);
  touchSPI.endTransaction();
}

void touch::readRaw(uint16_t &x, uint16_t &y, uint16_t &z) {
  beginTransaction();

  touchSPI.transfer(0xd0);
  uint16_t tx = touchSPI.transfer(0);
  tx = tx << 5;
  tx |= 0x1f & (touchSPI.transfer(0x90) >> 3);

  uint16_t ty = touchSPI.transfer(0);
  ty = ty << 5;
  ty |= 0x1f & (touchSPI.transfer(0x00) >> 3);

  int32_t tz = 0xFFF;
  touchSPI.transfer(0xb0);
  tz += touchSPI.transfer16(0xc0) >> 3;
  tz -= touchSPI.transfer16(0x00) >> 3;
  if (tz == 4095) tz = 0;

  endTransaction();

  x = tx;
  y = ty;
  z = (uint16_t)tz;
}

static bool flipped180 = false;

void touch::setFlipped(bool flipped) {
  flipped180 = flipped;
}

bool touch::read(uint16_t &x, uint16_t &y) {
  uint16_t rawX, rawY, rawZ;
  readRaw(rawX, rawY, rawZ);
  if (rawZ < kPressureThreshold) return false;

  uint16_t px = (uint16_t)constrain((int32_t)map(rawX, kRawXMin, kRawXMax, 0, 239), 0, 239);
  uint16_t py = (uint16_t)constrain((int32_t)map(rawY, kRawYMin, kRawYMax, 0, 319), 0, 319);

#if TOUCH_INVERT_X
  px = 239 - px;
#endif
#if TOUCH_INVERT_Y
  py = 319 - py;
#endif
#if TOUCH_SWAP_XY
  uint16_t tmp = px; px = py; py = tmp;
#endif

  if (flipped180) {
    px = 239 - px;
    py = 319 - py;
  }

  x = px;
  y = py;
  return true;
}

void touch::init() {
  pinMode(TOUCH_CS_PIN, OUTPUT);
  digitalWrite(TOUCH_CS_PIN, HIGH);
  pinMode(TOUCH_IRQ_PIN, INPUT);
  touchSPI.begin(TOUCH_SCLK_PIN, TOUCH_MISO_PIN, TOUCH_MOSI_PIN, TOUCH_CS_PIN);
  Serial.printf("[touch] init — SCLK=GPIO%d MOSI=GPIO%d MISO=GPIO%d CS=GPIO%d IRQ=GPIO%d (own SPI bus, per Elegoo's official pinout)\n",
                TOUCH_SCLK_PIN, TOUCH_MOSI_PIN, TOUCH_MISO_PIN, TOUCH_CS_PIN, TOUCH_IRQ_PIN);
}
