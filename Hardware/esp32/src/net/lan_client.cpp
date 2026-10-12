// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#include "lan_client.h"
#include "wifi_manager.h"
#include "storage/nvs_store.h"
#include <WiFi.h>
#include <WiFiUdp.h>
#include <ESPmDNS.h>
#include <ArduinoJson.h>
#include <string.h>
#include <stdlib.h>

static cue::Engine *engineRef = nullptr;
static WiFiClient client;

static const uint16_t kServerPort = 13380;

static bool mdnsStarted = false;

static WiFiUDP assignUdp;
static const uint16_t kAssignPort = 13381;
static bool assignUdpStarted = false;
static char assignRxBuf[256];

static const unsigned long kDiscoveryRetryIntervalMs = 3000;
static unsigned long lastDiscoveryAttemptAt = 0;
static IPAddress targetIp;
static uint16_t targetPort = 0;
static bool haveTarget = false;

static const unsigned long kPingRetryIntervalMs = 5000;
static unsigned long lastPingAt = 0;
static unsigned long lastCatchUpAt = 0;
static const unsigned long kCatchUpMinIntervalMs = 3000;

static const unsigned long kSyncBurstIntervalMs = 100;
static const unsigned long kSyncIntervalMs = 30000;
static const int kSyncBurstCount = 5;
static int syncBurstRemaining = 0;
static unsigned long lastSyncAt = 0;

static const size_t kRxBufPreferred = 12288;
static const size_t kRxBufFallback = 4096;
static const size_t kRxHeapReserve = 60000;
static uint8_t rxFallbackBuf[kRxBufFallback];
static uint8_t *rxBuf = rxFallbackBuf;
static size_t rxBufCap = kRxBufFallback;
static pagersync::FrameAssembler assembler;

static const unsigned long kOversizeCatchUpBackoffMs = 5000;
static bool oversizeCatchUpPending = false;
static unsigned long oversizeCatchUpAt = 0;

static const unsigned long kWatchdogGraceMs = 5000;
static bool watchdogPinged = false;
static unsigned long watchdogPingAt = 0;

static const int kConnectTimeoutMs = 3000;

static uint8_t txBuf[512];

static void allocRxBuffer() {
  if (rxBuf != rxFallbackBuf) return;
  if (ESP.getMaxAllocHeap() >= kRxBufPreferred + kRxHeapReserve) {
    uint8_t *p = (uint8_t *)malloc(kRxBufPreferred);
    if (p) {
      rxBuf = p;
      rxBufCap = kRxBufPreferred;
    }
  }
  Serial.printf("[lan] receive buffer %u bytes, free heap %u, max block %u\n",
                (unsigned)rxBufCap, (unsigned)ESP.getFreeHeap(), (unsigned)ESP.getMaxAllocHeap());
}

static void resetRxState() {
  assembler.init(rxBuf, rxBufCap);
  oversizeCatchUpPending = false;
  watchdogPinged = false;
}

static bool sendDoc(const JsonDocument &doc) {
  size_t len = serializeJson(doc, (char *)txBuf + 4, sizeof(txBuf) - 4);
  if (len == 0 || len >= sizeof(txBuf) - 4) return false;
  txBuf[0] = (uint8_t)((len >> 24) & 0xFF);
  txBuf[1] = (uint8_t)((len >> 16) & 0xFF);
  txBuf[2] = (uint8_t)((len >> 8) & 0xFF);
  txBuf[3] = (uint8_t)(len & 0xFF);
  size_t total = len + 4;
  size_t written = client.write(txBuf, total);
  if (written != total) {
    Serial.printf("[lan] short write %u/%u — closing socket\n", (unsigned)written, (unsigned)total);
    client.stop();
    return false;
  }
  return true;
}

static void sendPing() {
  if (!client.connected()) return;
  JsonDocument doc;
  doc["type"] = "PING";
  doc["senderId"] = store::deviceId();
  doc["timestamp"] = (double)millis() / 1000.0;
  doc["proto"] = 2;
  sendDoc(doc);
  lastCatchUpAt = millis();
  Serial.println("[lan] sent PING — requesting catch-up burst");
}

static void sendSync() {
  if (!client.connected()) return;
  JsonDocument doc;
  doc["type"] = "SYNC";
  doc["senderId"] = store::deviceId();
  doc["t0"] = (int64_t)cue::Engine::localNowMs();
  sendDoc(doc);
}

static void serviceSync() {
  unsigned long now = millis();
  if (engineRef && engineRef->takeSyncBurstRequest() && syncBurstRemaining == 0) {
    syncBurstRemaining = kSyncBurstCount;
    lastSyncAt = now - kSyncBurstIntervalMs;
  }
  if (syncBurstRemaining > 0) {
    if (now - lastSyncAt >= kSyncBurstIntervalMs) {
      sendSync();
      lastSyncAt = now;
      syncBurstRemaining--;
    }
    return;
  }
  if (engineRef && engineRef->producerIsV2() && now - lastSyncAt >= kSyncIntervalMs) {
    sendSync();
    lastSyncAt = now;
  }
}

static bool targetIsStatic = false;
static int staticFailureCount = 0;
static const int kStaticFailureThreshold = 3;
static bool staticFallbackActive = false;

static bool discoverViaStaticIp() {
  if (staticFallbackActive) return false;
  String host;
  if (!store::getProducerHost(host)) return false;
  IPAddress ip;
  if (!ip.fromString(host)) {
    Serial.printf("[lan] configured producer host \"%s\" is not a valid IP — ignoring, falling back to mDNS\n", host.c_str());
    return false;
  }
  targetIp = ip;
  targetPort = kServerPort;
  targetIsStatic = true;
  haveTarget = true;
  return true;
}

static bool discoverViaMdns() {
  int n = MDNS.queryService("13years", "tcp");
  if (n <= 0) {
    Serial.printf("[lan] mDNS query for _13years._tcp returned %d results\n", n);
    return false;
  }
  targetIp = MDNS.IP(0);
  targetPort = MDNS.port(0);
  targetIsStatic = false;
  haveTarget = true;
  Serial.printf("[lan] discovered producer via mDNS: %s (%s:%u)\n",
                MDNS.hostname(0).c_str(), targetIp.toString().c_str(), targetPort);
  return true;
}

static void attemptDiscovery() {
  if (millis() - lastDiscoveryAttemptAt < kDiscoveryRetryIntervalMs) return;
  if (!discoverViaStaticIp()) discoverViaMdns();
  lastDiscoveryAttemptAt = millis();
}

static void attemptConnect() {
  if (!haveTarget) return;
  Serial.printf("[lan] connecting to %s:%u\n", targetIp.toString().c_str(), targetPort);
  bool ok = client.connect(targetIp, targetPort, kConnectTimeoutMs);
  lastDiscoveryAttemptAt = millis();
  if (ok) {
    Serial.println("[lan] connected");
    client.setNoDelay(true);
    allocRxBuffer();
    resetRxState();
    if (engineRef) engineRef->onConnected();
    sendPing();
    lastPingAt = millis();
    syncBurstRemaining = kSyncBurstCount;
    lastSyncAt = millis() - kSyncBurstIntervalMs;
    staticFailureCount = 0;
  } else {
    Serial.println("[lan] connect failed — will rediscover and retry");
    if (targetIsStatic) {
      staticFailureCount++;
      if (staticFailureCount >= kStaticFailureThreshold) {
        Serial.printf("[lan] configured producer host unreachable after %d attempts — falling back to mDNS discovery\n", kStaticFailureThreshold);
        staticFallbackActive = true;
      }
    }
    haveTarget = false;
  }
}

static void serviceReceive() {
  uint8_t chunk[512];
  for (int pass = 0; pass < 8; pass++) {
    int avail = client.available();
    if (avail <= 0) return;
    int want = avail < (int)sizeof(chunk) ? avail : (int)sizeof(chunk);
    int got = client.read(chunk, want);
    if (got <= 0) return;
    bool ok = assembler.feed(chunk, (size_t)got,
      [](const uint8_t *data, size_t n) {
        Serial.printf("[lan] recv %u bytes\n", (unsigned)n);
        if (engineRef) engineRef->handlePacketJson((const char *)data, n);
      },
      [](size_t n) {
        Serial.printf("[lan] discarded oversized frame of %u bytes (buffer %u) — catch-up in %lus\n",
                      (unsigned)n, (unsigned)rxBufCap, kOversizeCatchUpBackoffMs / 1000);
        if (!oversizeCatchUpPending) {
          oversizeCatchUpPending = true;
          oversizeCatchUpAt = millis() + kOversizeCatchUpBackoffMs;
        }
      });
    if (!ok) {
      Serial.println("[lan] frame header implausible — resynchronising by reconnecting");
      client.stop();
      resetRxState();
      return;
    }
    if (!client.connected()) return;
  }
}

static void serviceWatchdog() {
  if (!engineRef) return;
  unsigned long limit = engineRef->stalenessLimitMs() + kWatchdogGraceMs;
  unsigned long silence = engineRef->silenceMs();
  if (silence <= limit) {
    watchdogPinged = false;
    return;
  }
  unsigned long now = millis();
  if (!watchdogPinged) {
    Serial.printf("[lan] producer silent for %lums — sending catch-up PING\n", silence);
    sendPing();
    lastPingAt = now;
    watchdogPinged = true;
    watchdogPingAt = now;
    return;
  }
  if (now - watchdogPingAt >= kWatchdogGraceMs) {
    Serial.println("[lan] no answer to watchdog PING — closing socket to reconnect");
    watchdogPinged = false;
    client.stop();
  }
}

static void serviceAssignPing() {
  int packetSize = assignUdp.parsePacket();
  if (packetSize <= 0) return;
  int len = assignUdp.read(assignRxBuf, sizeof(assignRxBuf) - 1);
  if (len <= 0) return;
  assignRxBuf[len] = '\0';

  JsonDocument doc;
  if (deserializeJson(doc, assignRxBuf, (size_t)len)) return;
  const char *type = doc["type"] | "";
  if (strcmp(type, "ASSIGN_PRODUCER") != 0) return;
  const char *host = doc["host"] | "";
  if (strlen(host) == 0) return;

  IPAddress ip;
  if (!ip.fromString(host)) {
    Serial.printf("[lan] ASSIGN_PRODUCER carried an invalid host \"%s\" — ignoring\n", host);
    return;
  }

  Serial.printf("[lan] producer assigned via network ping: %s\n", host);
  store::setProducerHost(String(host));
  staticFallbackActive = false;
  staticFailureCount = 0;
  targetIp = ip;
  targetPort = kServerPort;
  targetIsStatic = true;
  haveTarget = true;
  if (client.connected()) client.stop();
}

void lan::begin(cue::Engine *engine) {
  engineRef = engine;
}

void lan::loop() {
  if (!wifinet::isConnected()) {
    if (client.connected()) client.stop();
    haveTarget = false;
    mdnsStarted = false;
    assignUdpStarted = false;
    return;
  }

  if (!mdnsStarted) {
    WiFi.setSleep(false);
    MDNS.begin(store::deviceId());
    mdnsStarted = true;
    Serial.printf("[lan] mDNS started, resolvable as \"%s.local\"\n", store::deviceId().c_str());
  }

  if (!assignUdpStarted) {
    assignUdp.begin(kAssignPort);
    assignUdpStarted = true;
  }
  serviceAssignPing();

  if (!client.connected()) {
    if (!haveTarget) attemptDiscovery();
    if (haveTarget) attemptConnect();
    return;
  }

  serviceReceive();
  if (!client.connected()) return;
  serviceSync();
  serviceWatchdog();
  if (!client.connected()) return;

  if (oversizeCatchUpPending && (long)(millis() - oversizeCatchUpAt) >= 0) {
    oversizeCatchUpPending = false;
    sendPing();
    lastPingAt = millis();
  }

  if (engineRef && engineRef->takeCatchUpRequest() && millis() - lastCatchUpAt >= kCatchUpMinIntervalMs) {
    sendPing();
    lastPingAt = millis();
  }

  if (engineRef && engineRef->roleCount() == 0 && millis() - lastPingAt >= kPingRetryIntervalMs) {
    sendPing();
    lastPingAt = millis();
  }
}

bool lan::isConnected() {
  return client.connected();
}

bool lan::isStaticFallbackActive() {
  return staticFallbackActive;
}

void lan::resetStaticFallback() {
  staticFallbackActive = false;
  staticFailureCount = 0;
  haveTarget = false;
  lastDiscoveryAttemptAt = 0;
  if (client.connected()) client.stop();
}
