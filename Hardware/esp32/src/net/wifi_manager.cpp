// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#include "wifi_manager.h"
#include "storage/nvs_store.h"
#include <WiFi.h>

using wifinet::State;

static State currentState = State::Disconnected;
static String storedSsid, storedPass;
static bool hasCredentials = false;

static const int kQuickRetryAttempts = 5;
static const unsigned long kSlowRetryIntervalMs = 10000;
static int connectAttempt = 0;
static unsigned long nextAttemptAt = 0;
static unsigned long connectStartedAt = 0;
static const unsigned long kPerAttemptTimeoutMs = 15000;

static void beginConnectAttempt() {
  connectAttempt++;
  connectStartedAt = millis();
  currentState = State::Connecting;
  Serial.printf("[wifi] connecting to \"%s\" (attempt %d)\n", storedSsid.c_str(), connectAttempt);
  WiFi.mode(WIFI_STA);
  WiFi.setHostname(store::deviceId().c_str());
  WiFi.begin(storedSsid.c_str(), storedPass.c_str());
}

static void scheduleRetry() {
  currentState = State::Disconnected;
  unsigned long delayMs;
  if (connectAttempt < kQuickRetryAttempts) {
    delayMs = 300UL * connectAttempt;
  } else {
    delayMs = kSlowRetryIntervalMs;
    if (connectAttempt == kQuickRetryAttempts) {
      Serial.printf("[wifi] still not connected after %d quick attempts — retrying every %lums in the background\n",
                    kQuickRetryAttempts, kSlowRetryIntervalMs);
    }
  }
  nextAttemptAt = millis() + delayMs;
}

void wifinet::begin() {
  hasCredentials = store::getWifiCreds(storedSsid, storedPass);
  if (hasCredentials) {
    connectAttempt = 0;
    beginConnectAttempt();
  } else {
    Serial.println("[wifi] no stored credentials — send `wifi <ssid> <password>` over Serial to configure");
    currentState = State::Disconnected;
  }
}

void wifinet::applyNewCredentials(const String &ssid, const String &pass) {
  storedSsid = ssid;
  storedPass = pass;
  hasCredentials = true;
  store::setWifiCreds(ssid, pass);
  Serial.printf("[wifi] credentials saved for \"%s\" — connecting\n", ssid.c_str());
  connectAttempt = 0;
  WiFi.disconnect();
  beginConnectAttempt();
}

wifinet::State wifinet::loop() {
  if (!hasCredentials) return currentState;

  if (currentState == State::Connecting) {
    if (WiFi.status() == WL_CONNECTED) {
      currentState = State::Connected;
      connectAttempt = 0;
      Serial.printf("[wifi] connected — IP %s\n", WiFi.localIP().toString().c_str());
    } else if (millis() - connectStartedAt > kPerAttemptTimeoutMs) {
      Serial.println("[wifi] connect attempt timed out");
      scheduleRetry();
    }
    return currentState;
  }

  if (currentState == State::Connected) {
    if (WiFi.status() != WL_CONNECTED) {
      Serial.println("[wifi] connection dropped — reconnecting");
      currentState = State::Disconnected;
      connectAttempt = 0;
      scheduleRetry();
    }
    return currentState;
  }

  if (millis() >= nextAttemptAt) {
    beginConnectAttempt();
  }
  return currentState;
}

bool wifinet::isConnected() {
  return currentState == State::Connected;
}
