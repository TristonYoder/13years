// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#include <Arduino.h>
#include <ArduinoJson.h>
#include <lvgl.h>
#include "storage/nvs_store.h"
#include "net/wifi_manager.h"
#include "net/lan_client.h"
#include "cue/cue_engine.h"
#include "hw/rgb_led.h"
#include "hw/buzzer.h"
#include "ui/ui.h"

static cue::Engine engine;
static String serialLineBuf;

static void onCueTransition(CueState newState) {
  Serial.printf("[cue] role \"%s\" transitioned -> %s\n", engine.selectedRoleId().c_str(), cueStateDisplayName(newState));
  led::setForCueState(newState);
  buzzer::playCueTransition(newState);
}

static void onMessageReceived(CueState currentDisplayState) {
  Serial.println("[cue] new relevant message received");
  buzzer::playMessageReceived(currentDisplayState);
}

static bool takeToken(String &rest, String &token) {
  rest.trim();
  if (rest.length() == 0) return false;
  if (rest[0] == '"') {
    int close = rest.indexOf('"', 1);
    if (close < 0) return false;
    token = rest.substring(1, close);
    rest = rest.substring(close + 1);
  } else {
    int sp = rest.indexOf(' ');
    if (sp < 0) { token = rest; rest = ""; }
    else { token = rest.substring(0, sp); rest = rest.substring(sp + 1); }
  }
  rest.trim();
  return true;
}

static void handleProvision(const String &payload) {
  JsonDocument doc;
  DeserializationError err = deserializeJson(doc, payload);
  if (err) {
    Serial.printf("[err] provision malformed-json %s\n", err.c_str());
    return;
  }
  if (!doc.is<JsonObject>()) {
    Serial.println("[err] provision expected-json-object");
    return;
  }

  if (doc["ssid"].isNull()) {
    Serial.println("[err] provision missing-ssid");
    return;
  }
  String ssid = doc["ssid"].as<String>();
  String pass = doc["pass"].isNull() ? String("") : doc["pass"].as<String>();

  if (ssid.length() == 0 || ssid.length() > 32) {
    Serial.println("[err] provision bad-ssid-length");
    return;
  }
  if (pass.length() > 63) {
    Serial.println("[err] provision bad-password-length");
    return;
  }

  String role;
  if (!doc["role"].isNull()) {
    role = doc["role"].as<String>();
    role.trim();
    if (role.length() == 0) {
      Serial.println("[err] provision bad-role");
      return;
    }
  }

  bool haveRotation = false, rotate180 = false;
  if (!doc["rotate180"].isNull()) {
    if (!doc["rotate180"].is<bool>()) {
      Serial.println("[err] provision bad-rotate180");
      return;
    }
    haveRotation = true;
    rotate180 = doc["rotate180"].as<bool>();
  }

  String producer;
  bool clearProducer = false;
  if (!doc["producer"].isNull()) {
    producer = doc["producer"].as<String>();
    producer.trim();
    if (producer == "auto") {
      clearProducer = true;
      producer = "";
    } else {
      IPAddress ip;
      if (!ip.fromString(producer)) {
        Serial.println("[err] provision bad-producer-ip");
        return;
      }
    }
  }

  if (role.length() > 0) {
    engine.setSelectedRoleId(role);
    store::setRoleChosen(true);
    led::setForCueState(engine.activeRole().state);
  }
  if (haveRotation) {
    ui::setDisplayFlipped(rotate180);
  }
  if (clearProducer) {
    store::clearProducerHost();
    lan::resetStaticFallback();
  } else if (producer.length() > 0) {
    store::setProducerHost(producer);
    lan::resetStaticFallback();
  }
  wifinet::applyNewCredentials(ssid, pass);

  String producerReport;
  if (clearProducer || producer.length() > 0) {
    producerReport = clearProducer ? "auto" : producer;
  } else {
    String existing;
    producerReport = store::getProducerHost(existing) ? existing : String("auto");
  }
  JsonDocument ack;
  ack["deviceId"] = store::deviceId();
  ack["ssid"] = ssid;
  ack["role"] = engine.selectedRoleId();
  ack["producer"] = producerReport;
  ack["rotate180"] = ui::isDisplayFlipped();
  Serial.print("[ok] provision ");
  serializeJson(ack, Serial);
  Serial.println();
}

static void handleSerialLine(String line) {
  line.trim();
  if (line.length() == 0) return;
  Serial.printf("[serial] > %s\n", line.c_str());

  if (line.startsWith("wifi ")) {
    String rest = line.substring(5);
    String ssid;
    if (!takeToken(rest, ssid) || ssid.length() == 0) {
      Serial.println("[serial] usage: wifi <ssid> <password>   (quote an SSID with spaces: wifi \"My Network\" pw)");
      return;
    }
    wifinet::applyNewCredentials(ssid, rest);

  } else if (line.startsWith("provision ")) {
    handleProvision(line.substring(10));

  } else if (line.startsWith("role ")) {
    String roleId = line.substring(5);
    roleId.trim();
    engine.setSelectedRoleId(roleId);
    led::setForCueState(engine.activeRole().state);
    Serial.printf("[serial] role set to \"%s\"\n", roleId.c_str());

  } else if (line.startsWith("producer")) {
    String rest = line.length() > 8 ? line.substring(8) : "";
    rest.trim();
    if (rest == "") {
      String host;
      if (store::getProducerHost(host)) {
        Serial.printf("[serial] producer host is set to %s — `producer auto` to use mDNS discovery instead\n", host.c_str());
      } else {
        Serial.println("[serial] producer host is unset — discovering via mDNS");
      }
    } else if (rest == "auto") {
      store::clearProducerHost();
      lan::resetStaticFallback();
      Serial.println("[serial] producer host cleared — will discover via mDNS");
    } else {
      IPAddress ip;
      if (!ip.fromString(rest)) {
        Serial.printf("[serial] \"%s\" isn't a valid IP address — usage: producer <ip>|auto\n", rest.c_str());
      } else {
        store::setProducerHost(rest);
        lan::resetStaticFallback();
        Serial.printf("[serial] producer host set to %s\n", rest.c_str());
      }
    }

  } else if (line.startsWith("rotate")) {
    String rest = line.length() > 6 ? line.substring(6) : "";
    rest.trim();
    if (rest == "") {
      Serial.printf("[serial] display rotation is %s — `rotate 180` or `rotate normal` to change\n",
                    ui::isDisplayFlipped() ? "180 degrees" : "normal");
    } else if (rest == "180" || rest == "flip") {
      ui::setDisplayFlipped(true);
    } else if (rest == "normal" || rest == "0") {
      ui::setDisplayFlipped(false);
    } else {
      Serial.println("[serial] usage: rotate 180|normal   (bare `rotate` reports the current setting)");
    }

  } else if (line == "status") {
    cue::RoleView role = engine.activeRole();
    cue::TimerView timer = engine.activeTimer();
    String producerHost;
    bool hasStaticHost = store::getProducerHost(producerHost);
    String producerDisplay = hasStaticHost
      ? (lan::isStaticFallbackActive() ? producerHost + " (unreachable — fell back to mDNS)" : producerHost)
      : String("(mDNS)");
    Serial.printf("[serial] rotation=%s\n", ui::isDisplayFlipped() ? "180" : "normal");
    Serial.printf("[serial] deviceId=%s role=%s wifi=%s lan=%s producer=%s cueState=%s\n",
                  store::deviceId().c_str(), engine.selectedRoleId().c_str(),
                  wifinet::isConnected() ? "connected" : "disconnected",
                  lan::isConnected() ? "connected" : "not connected",
                  producerDisplay.c_str(),
                  role.found ? cueStateDisplayName(role.state) : "(no role data yet)");
    if (timer.found) {
      Serial.printf("[serial]   timer: \"%s\" remaining=%ds running=%d actual=%d note=\"%s\"\n",
                    timer.title.c_str(), timer.remainingSeconds(), timer.isRunning, timer.isDurationActual,
                    engine.currentNote().c_str());
    }
    cue::MessageView msg = engine.latestRelevantMessage();
    if (msg.found) {
      Serial.printf("[serial]   latest relevant message: \"%s\" (from=%s target=%s)\n",
                    msg.text.c_str(), msg.sender.c_str(), msg.targetRoleId.length() ? msg.targetRoleId.c_str() : "(everyone)");
    }

  } else if (line.startsWith("ledpin ")) {
    String rest = line.substring(7);
    rest.trim();
    int sp = rest.indexOf(' ');
    if (sp < 0) {
      Serial.println("[serial] usage: ledpin <gpio> <lo|hi|off>");
    } else {
      int gpio = rest.substring(0, sp).toInt();
      String level = rest.substring(sp + 1);
      level.trim();
      if (gpio >= 6 && gpio <= 11) {
        Serial.printf("[ledpin] refusing GPIO%d — reserved for this module's internal SPI flash\n", gpio);
        return;
      }
      pinMode(gpio, OUTPUT);
      if (level == "lo") { digitalWrite(gpio, LOW); Serial.printf("[ledpin] GPIO%d -> LOW\n", gpio); }
      else if (level == "hi") { digitalWrite(gpio, HIGH); Serial.printf("[ledpin] GPIO%d -> HIGH\n", gpio); }
      else if (level == "off") { digitalWrite(gpio, HIGH); Serial.printf("[ledpin] GPIO%d -> HIGH (off, active-LOW assumption)\n", gpio); }
      else Serial.println("[serial] usage: ledpin <gpio> <lo|hi|off>");
    }

  } else if (line.startsWith("tonepin ")) {
    String rest = line.substring(8);
    rest.trim();
    if (rest == "") {
      Serial.println("[serial] usage: tonepin <gpio> <freq_hz>  (or `tonepin off` to silence)");
    } else if (rest == "off") {
      noTone(BUZZER_PIN);
      Serial.println("[tonepin] silenced");
    } else {
      int sp = rest.indexOf(' ');
      int gpio = sp < 0 ? rest.toInt() : rest.substring(0, sp).toInt();
      int freq = sp < 0 ? 2000 : rest.substring(sp + 1).toInt();
      if (gpio >= 6 && gpio <= 11) {
        Serial.printf("[tonepin] refusing GPIO%d — reserved for this module's internal SPI flash\n", gpio);
      } else {
        pinMode(gpio, OUTPUT);
        tone(gpio, freq, 1000);
        Serial.printf("[tonepin] GPIO%d @ %dHz for 1s\n", gpio, freq);
      }
    }

  } else if (line.startsWith("led ")) {
    String arg = line.substring(4);
    arg.trim();
    if (arg == "red") { led::setRGB(true, false, false); Serial.println("[led] raw: RED channel only"); }
    else if (arg == "green") { led::setRGB(false, true, false); Serial.println("[led] raw: GREEN channel only"); }
    else if (arg == "blue") { led::setRGB(false, false, true); Serial.println("[led] raw: BLUE channel only"); }
    else if (arg == "rg") { led::setRGB(true, true, false); Serial.println("[led] raw: RED+GREEN"); }
    else if (arg == "rb") { led::setRGB(true, false, true); Serial.println("[led] raw: RED+BLUE"); }
    else if (arg == "gb") { led::setRGB(false, true, true); Serial.println("[led] raw: GREEN+BLUE"); }
    else if (arg == "all") { led::setRGB(true, true, true); Serial.println("[led] raw: RED+GREEN+BLUE"); }
    else if (arg == "off") { led::off(); Serial.println("[led] raw: OFF"); }
    else Serial.println("[serial] usage: led <red|green|blue|rg|rb|gb|all|off>");

  } else if (line.startsWith("testpacket ")) {
    String json = line.substring(11);
    Serial.printf("[serial] injecting test packet (%d bytes)\n", json.length());
    engine.handlePacketJson(json.c_str(), json.length());

  } else if (line == "calibrate") {
    ui::runTouchCalibration();

  } else if (line.startsWith("touchraw")) {
    String arg = line.substring(8);
    arg.trim();
    uint32_t ms = arg.length() > 0 ? (uint32_t)arg.toInt() : 5000;
    if (ms == 0) ms = 5000;
    ui::runRawTouchReadout(ms);

  } else if (line == "reset") {
    Serial.println("[serial] clearing all stored config (WiFi creds, device id, role, producer host, touch calibration) and restarting");
    store::clearAll();
    delay(200);
    ESP.restart();

  } else if (line == "help") {
    Serial.println("[serial] commands:");
    Serial.println("  wifi <ssid> <password>   set/replace stored WiFi credentials and connect (quote an SSID with spaces)");
    Serial.println("  provision <json>         set ssid/pass/role/producer in one shot from a JSON object, replying [ok]/[err] — what the Producer app drives over USB after flashing");
    Serial.println("  role <id>                set this pager's role (whatever ids the Producer's roster has — see the on-screen picker)");
    Serial.println("  rotate 180|normal        turn the display (and touch with it) 180 degrees, for upside-down mounting");
    Serial.println("  producer <ip>|auto       set a static Producer IP (skips mDNS discovery), or `auto` to discover via mDNS again; bare `producer` reports the current setting");
    Serial.println("  status                   print device id / role / connection state");
    Serial.println("  testpacket <json>        inject a raw CuePacket JSON string directly into the engine (debug aid, bypasses the network)");
    Serial.println("  led <red|green|blue|rg|rb|gb|all|off>  drive the RGB LED's raw channels directly (debug aid)");
    Serial.println("  ledpin <gpio> <lo|hi|off> raw single-GPIO toggle, for hunting LED/other pins (debug aid)");
    Serial.println("  tonepin <gpio> <freq_hz> raw single-GPIO tone test, for confirming the buzzer pin once wired (debug aid; `tonepin off` to silence)");
    Serial.println("  calibrate                run touch calibration now (touch each corner as prompted on-screen) — safe to redo any time");
    Serial.println("  touchraw [ms]            print raw touch controller readings for [ms] (default 5000) — diagnostic, bypasses calibration entirely");
    Serial.println("  reset                    wipe all stored config and restart (also available via the on-screen role picker's role choice, minus the wipe)");

  } else {
    Serial.printf("[serial] unknown command \"%s\" — try `help`\n", line.c_str());
  }
}

static void serviceSerialCommands() {
  while (Serial.available() > 0) {
    char c = (char)Serial.read();
    if (c == '\n') {
      handleSerialLine(serialLineBuf);
      serialLineBuf = "";
    } else if (c != '\r') {
      serialLineBuf += c;
      if (serialLineBuf.length() > 4000) serialLineBuf = "";
    }
  }
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println();
  Serial.println("=== 13years ESP32 Hardware Pager ===");
  Serial.println("Send `help` over Serial (115200 baud) for configuration commands.");

  store::init();
  Serial.printf("[boot] deviceId=%s\n", store::deviceId().c_str());

  ui::init();
  ui::update(ui::Phase::Boot, engine, false, false);

  engine.begin();
  engine.onCueTransition = onCueTransition;
  engine.onMessageReceived = onMessageReceived;
  Serial.printf("[boot] assigned role: %s (change with `role <id>` or the on-screen picker)\n", engine.selectedRoleId().c_str());

  led::init();
  buzzer::init();
  led::setForCueState(CueState::Off);

  wifinet::begin();
  lan::begin(&engine);
}

void loop() {
  serviceSerialCommands();

  wifinet::State wifiState = wifinet::loop();
  lan::loop();

  bool nowSearching = wifiState != wifinet::State::Connected || !lan::isConnected() || !engine.isProducerLive();
  static bool wasSearching = false;
  static bool searchingStateInitialized = false;
  if (!searchingStateInitialized || nowSearching != wasSearching) {
    searchingStateInitialized = true;
    wasSearching = nowSearching;
    if (nowSearching) {
      led::setSearching();
    } else {
      led::setForCueState(engine.activeRole().state);
    }
  }

  buzzer::loop();
  led::loop();

  ui::Phase phase;
  if (wifiState == wifinet::State::Connected) {
    phase = ui::Phase::Running;
  } else if (wifiState == wifinet::State::Connecting) {
    phase = ui::Phase::Connecting;
  } else {
    phase = ui::Phase::WifiPrompt;
  }
  ui::update(phase, engine, wifinet::isConnected(), lan::isConnected());

  lv_timer_handler();
  delay(5);
}
