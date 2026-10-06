// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#pragma once
#include <Arduino.h>

namespace store {

void init();

bool getWifiCreds(String &ssid, String &pass);
void setWifiCreds(const String &ssid, const String &pass);
void clearWifiCreds();

String deviceId();

String getRoleId();
void setRoleId(const String &roleId);

bool getRoleChosen();
void setRoleChosen(bool chosen);

bool getProducerHost(String &host);
void setProducerHost(const String &host);
void clearProducerHost();

bool getDisplayFlipped();
void setDisplayFlipped(bool flipped);

bool getTouchCalibration(uint16_t calData[5]);
void setTouchCalibration(const uint16_t calData[5]);
void clearTouchCalibration();

void clearAll();

}
