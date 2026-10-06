// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#include "nvs_store.h"
#include <Preferences.h>
#include <WiFi.h>

static Preferences prefs;
static String cachedDeviceId;

void store::init() {
  prefs.begin("pager", false);
}

bool store::getWifiCreds(String &ssid, String &pass) {
  ssid = prefs.getString("wifi_ssid", "");
  pass = prefs.getString("wifi_pass", "");
  return ssid.length() > 0;
}

void store::setWifiCreds(const String &ssid, const String &pass) {
  prefs.putString("wifi_ssid", ssid);
  prefs.putString("wifi_pass", pass);
}

void store::clearWifiCreds() {
  prefs.remove("wifi_ssid");
  prefs.remove("wifi_pass");
}

String store::deviceId() {
  if (cachedDeviceId.length() > 0) return cachedDeviceId;

  String stored = prefs.getString("device_id", "");
  if (stored.startsWith("esp32-")) {
    stored = "13years-" + stored.substring(6);
    prefs.putString("device_id", stored);
  }
  if (stored.length() > 0) {
    cachedDeviceId = stored;
    return cachedDeviceId;
  }

  uint64_t mac = ESP.getEfuseMac();
  char buf[24];
  snprintf(buf, sizeof(buf), "13years-%06llx", (unsigned long long)((mac >> 24) & 0xFFFFFFULL));
  cachedDeviceId = String(buf);
  prefs.putString("device_id", cachedDeviceId);
  return cachedDeviceId;
}

String store::getRoleId() {
  return prefs.getString("role_id", "default");
}

void store::setRoleId(const String &roleId) {
  prefs.putString("role_id", roleId);
}

bool store::getRoleChosen() {
  return prefs.getBool("role_chosen", false);
}

void store::setRoleChosen(bool chosen) {
  prefs.putBool("role_chosen", chosen);
}

bool store::getProducerHost(String &host) {
  host = prefs.getString("producer_host", "");
  return host.length() > 0;
}

void store::setProducerHost(const String &host) {
  prefs.putString("producer_host", host);
}

void store::clearProducerHost() {
  prefs.remove("producer_host");
}

bool store::getDisplayFlipped() {
  return prefs.getBool("disp_flip", false);
}

void store::setDisplayFlipped(bool flipped) {
  prefs.putBool("disp_flip", flipped);
}

bool store::getTouchCalibration(uint16_t calData[5]) {
  size_t got = prefs.getBytes("touch_cal", calData, sizeof(uint16_t) * 5);
  return got == sizeof(uint16_t) * 5;
}

void store::setTouchCalibration(const uint16_t calData[5]) {
  prefs.putBytes("touch_cal", calData, sizeof(uint16_t) * 5);
}

void store::clearTouchCalibration() {
  prefs.remove("touch_cal");
}

void store::clearAll() {
  prefs.clear();
  cachedDeviceId = "";
}
