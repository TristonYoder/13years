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

static uint8_t rxLenBuf[4];
static int rxLenFilled = 0;
static uint8_t rxPayloadBuf[4096];
static int rxPayloadExpected = 0;
static int rxPayloadFilled = 0;
static bool readingPayload = false;

static void resetRxState() {
  rxLenFilled = 0;
  rxPayloadFilled = 0;
  rxPayloadExpected = 0;
  readingPayload = false;
}

static void sendFrame(const String &json) {
  uint32_t len = json.length();
  uint8_t header[4] = {
    (uint8_t)((len >> 24) & 0xFF), (uint8_t)((len >> 16) & 0xFF),
    (uint8_t)((len >> 8) & 0xFF), (uint8_t)(len & 0xFF)
  };
  client.write(header, 4);
  client.write((const uint8_t *)json.c_str(), len);
}

static void sendPing() {
  if (!client.connected()) return;
  JsonDocument doc;
  doc["type"] = "PING";
  doc["senderId"] = store::deviceId();
  doc["timestamp"] = (double)millis() / 1000.0;
  String out;
  serializeJson(doc, out);
  sendFrame(out);
  Serial.println("[lan] sent PING — requesting catch-up burst");
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
  lastDiscoveryAttemptAt = millis();
  if (discoverViaStaticIp()) return;
  discoverViaMdns();
}

static void attemptConnect() {
  if (!haveTarget) return;
  Serial.printf("[lan] connecting to %s:%u\n", targetIp.toString().c_str(), targetPort);
  if (client.connect(targetIp, targetPort)) {
    Serial.println("[lan] connected");
    resetRxState();
    sendPing();
    lastPingAt = millis();
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
  while (client.available() > 0) {
    if (!readingPayload) {
      int need = 4 - rxLenFilled;
      int got = client.read(rxLenBuf + rxLenFilled, need);
      if (got <= 0) return;
      rxLenFilled += got;
      if (rxLenFilled == 4) {
        uint32_t len = ((uint32_t)rxLenBuf[0] << 24) | ((uint32_t)rxLenBuf[1] << 16) |
                       ((uint32_t)rxLenBuf[2] << 8) | (uint32_t)rxLenBuf[3];
        if (len == 0 || len > sizeof(rxPayloadBuf)) {
          Serial.printf("[lan] frame length %u out of range — dropping connection\n", (unsigned)len);
          client.stop();
          resetRxState();
          return;
        }
        rxPayloadExpected = (int)len;
        rxPayloadFilled = 0;
        readingPayload = true;
      }
    } else {
      int need = rxPayloadExpected - rxPayloadFilled;
      int got = client.read(rxPayloadBuf + rxPayloadFilled, need);
      if (got <= 0) return;
      rxPayloadFilled += got;
      if (rxPayloadFilled == rxPayloadExpected) {
        Serial.printf("[lan] recv %d bytes\n", rxPayloadExpected);
        if (engineRef) engineRef->handlePacketJson((const char *)rxPayloadBuf, (size_t)rxPayloadExpected);
        rxLenFilled = 0;
        readingPayload = false;
      }
    }
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
