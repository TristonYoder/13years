// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#include "../src/sync/sync_core.h"
#include "../src/net/endpoint_parse.h"
#include <stdio.h>
#include <string>
#include <vector>
#include <algorithm>

#if defined(__has_include)
#if __has_include(<ArduinoJson.h>)
#include <ArduinoJson.h>
#define HAVE_ARDUINOJSON 1
#endif
#endif

static int failures = 0;
static int checks = 0;

#define CHECK(cond) do { checks++; if (!(cond)) { failures++; printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #cond); } } while (0)
#define CHECK_STR(a, b) do { checks++; std::string _a = (a), _b = (b); if (_a != _b) { failures++; printf("FAIL %s:%d got %s want %s\n", __FILE__, __LINE__, _a.c_str(), _b.c_str()); } } while (0)
#define CHECK_NEAR(a, b, eps) do { checks++; double _a = (a), _b = (b); if (fabs(_a - _b) > (eps)) { failures++; printf("FAIL %s:%d got %f want %f\n", __FILE__, __LINE__, _a, _b); } } while (0)

static void testEndpointParse() {
  std::string host;
  uint16_t port = 1;
  CHECK(endpointparse::splitHostPort("100.75.81.4", host, port));
  CHECK_STR(host, "100.75.81.4");
  CHECK(port == 0);
  CHECK(endpointparse::splitHostPort("192.168.1.20:9000", host, port));
  CHECK_STR(host, "192.168.1.20");
  CHECK(port == 9000);
  CHECK(endpointparse::splitHostPort("10.0.0.5:65535", host, port));
  CHECK(port == 65535);
  CHECK(!endpointparse::splitHostPort("10.0.0.5:0", host, port));
  CHECK(!endpointparse::splitHostPort("10.0.0.5:70000", host, port));
  CHECK(!endpointparse::splitHostPort("10.0.0.5:abc", host, port));
  CHECK(!endpointparse::splitHostPort("10.0.0.5:", host, port));
  CHECK(!endpointparse::splitHostPort(":9000", host, port));
  CHECK(!endpointparse::splitHostPort("", host, port));
  CHECK(!endpointparse::splitHostPort("1.2.3.4:5:6", host, port));
  {
    using namespace endpointparse;
    IntroducerTarget t = decideIntroducer("mac.local", "9000", "10.0.0.7", "introducer");
    CHECK(t.kind == IntroducerKind::Direct && t.ip == "10.0.0.7" && t.port == 9000);
    t = decideIntroducer("10.0.0.9", "9001", "", "introducer");
    CHECK(t.kind == IntroducerKind::Direct && t.ip == "10.0.0.9" && t.port == 9001);
    t = decideIntroducer("mac.local", "9000", "bad", "introducer");
    CHECK(t.kind == IntroducerKind::NeedsResolve && t.host == "mac.local" && t.port == 9000);
    t = decideIntroducer("mac.local", "9000", "", "");
    CHECK(t.kind == IntroducerKind::NeedsResolve);
    CHECK(decideIntroducer("mac.local", "0", "", "introducer").kind == IntroducerKind::None);
    CHECK(decideIntroducer("mac.local", "70000", "", "introducer").kind == IntroducerKind::None);
    CHECK(decideIntroducer("mac.local", "abc", "", "introducer").kind == IntroducerKind::None);
    CHECK(decideIntroducer("mac.local", "", "", "introducer").kind == IntroducerKind::None);
    CHECK(decideIntroducer("", "9000", "10.0.0.7", "introducer").kind == IntroducerKind::None);
    CHECK(decideIntroducer("mac.local", "9000", "10.0.0.7", "relay").kind == IntroducerKind::None);
    CHECK(decideIntroducer("0.0.0.0", "9000", "", "introducer").kind == IntroducerKind::None);
    CHECK(decideIntroducer("10.0.0.256", "9000", "", "introducer").kind == IntroducerKind::NeedsResolve);
    t = decideIntroducer("mac.local", "9000", "0.0.0.0", "introducer");
    CHECK(t.kind == IntroducerKind::NeedsResolve);
  }
}

static void testHashVectors() {
  CHECK_STR(pagersync::hashHex(""), "cbf29ce484222325");
  CHECK_STR(pagersync::hashHex("a"), "af63dc4c8601ec8c");
  CHECK_STR(pagersync::hashHex("foobar"), "85944171f73967e8");

  std::string roles;
  pagersync::appendRole(roles, "host", "Host", "GO");
  pagersync::appendRole(roles, "band", "Band", "OFF");
  CHECK_STR(pagersync::hashHex(roles), "aded3b3c0e486304");

  pagersync::Anchor a;
  a.valid = true;
  a.itemId = "item-1";
  a.lengthInSeconds = 300;
  a.isRunning = true;
  a.isDurationActual = false;
  a.elapsedMs = 120000;
  a.anchorMs = 1760000000000LL;
  CHECK_STR(pagersync::hashHex(pagersync::timerCanonical(a)), "20a9d930a0849518");
  CHECK_STR(pagersync::hashHex(pagersync::timerCanonical(pagersync::Anchor())), "3c0d17bad169557b");

  std::string messages;
  pagersync::appendMessageId(messages, "m2");
  pagersync::appendMessageId(messages, "m1");
  CHECK_STR(pagersync::hashHex(messages), "dddb4a3dc4d94432");

  std::string plan = std::string("i1\x1f" "Song\x1f" "300\x1f" "0\x1e" "i2\x1f" "Sermon\x1f" "2700\x1f" "1\x1e" "1");
  CHECK_STR(pagersync::hashHex(plan), "218cc3247b5ee3f9");
}

static void testOffsetFormula() {
  pagersync::Sample s = pagersync::OffsetEstimator::compute(1000, 5000, 5002, 1010);
  CHECK_NEAR(s.rtt, 8, 1e-9);
  CHECK_NEAR(s.offset, 3996, 1e-9);

  double trueOffset = 1000;
  double up = 30, down = 10;
  int64_t t0 = 100;
  int64_t t1 = (int64_t)(t0 + up + trueOffset);
  int64_t t2 = t1 + 1;
  int64_t t3 = (int64_t)(t2 - trueOffset + down);
  pagersync::Sample a2 = pagersync::OffsetEstimator::compute(t0, t1, t2, t3);
  CHECK_NEAR(a2.offset - trueOffset, (up - down) / 2.0, 1e-9);
  CHECK_NEAR(a2.rtt, up + down, 1e-9);

  pagersync::Sample sym = pagersync::OffsetEstimator::compute(100, 1120, 1121, 141);
  CHECK_NEAR(sym.offset - 1000, 0.0, 1e-9);
}

static void feed(pagersync::OffsetEstimator &e, double trueOffset, double up, double down, int64_t t0) {
  int64_t t1 = (int64_t)(t0 + up + trueOffset);
  int64_t t2 = t1;
  int64_t t3 = (int64_t)(t0 + up + down);
  e.addSample(t0, t1, t2, t3);
}

static void testMinRtt() {
  pagersync::OffsetEstimator e;
  feed(e, 5000, 50, 50, 1000);
  feed(e, 5000, 80, 20, 1100);
  feed(e, 5000, 5, 5, 1200);
  feed(e, 5000, 40, 60, 1300);
  CHECK_NEAR(e.bestOffset(), 5000, 0.5);
  CHECK(e.sampleCount() == 4);
}

static void testRingKeepsEight() {
  pagersync::OffsetEstimator e;
  feed(e, 7000, 2, 2, 0);
  for (int i = 0; i < 8; i++) feed(e, 7100, 30, 30, 100 + i * 100);
  CHECK(e.sampleCount() == 8);
  CHECK_NEAR(e.bestOffset(), 7100, 0.5);
}

static void testSlewVsJump() {
  pagersync::OffsetEstimator e;
  CHECK(!e.hasOffset());
  e.addSample(0, 1000, 1000, 10);
  CHECK(e.hasOffset());
  CHECK_NEAR(e.offsetMs(), 995, 1e-9);

  e.addSample(100, 1112, 1112, 102);
  CHECK_NEAR(e.bestOffset(), 1011, 1e-9);
  CHECK_NEAR(e.offsetMs(), 995 + 0.25 * 16, 1e-9);

  e.reset();
  e.addSample(0, 1000, 1000, 10);
  e.addSample(100, 1200, 1200, 101);
  CHECK_NEAR(e.bestOffset(), 1099.5, 1e-9);
  CHECK_NEAR(e.offsetMs(), 1099.5, 1e-9);

  e.reset();
  e.addSample(0, 1000, 1000, 2);
  double first = e.offsetMs();
  e.addSample(100, 1105, 1105, 200);
  CHECK_NEAR(e.offsetMs(), first, 1e-9);
}

static void testProducerNow() {
  pagersync::OffsetEstimator e;
  e.setMaxAbsOffsetMs(4.2e12);
  e.addSample(0, 1760000000000LL + 5, 1760000000000LL + 5, 10);
  CHECK(e.producerNow(100) == 100 + (int64_t)llround(e.offsetMs()));
  CHECK(e.producerNow(100) > 1760000000000LL);
}

static void testAnchor() {
  pagersync::Anchor a;
  a.valid = true;
  a.itemId = "x";
  a.lengthInSeconds = 300;
  a.elapsedMs = 120500;
  a.anchorMs = 1760000000000LL;
  a.isRunning = true;

  CHECK(pagersync::anchorElapsedMs(a, a.anchorMs) == 120500);
  CHECK(pagersync::anchorElapsedSeconds(a, a.anchorMs) == 120);
  CHECK(pagersync::anchorElapsedSeconds(a, a.anchorMs + 499) == 120);
  CHECK(pagersync::anchorElapsedSeconds(a, a.anchorMs + 500) == 121);
  CHECK(pagersync::anchorRemainingSeconds(a, a.anchorMs + 500) == 179);
  CHECK(pagersync::anchorRemainingSeconds(a, a.anchorMs + 179500) == 0);
  CHECK(pagersync::anchorRemainingSeconds(a, a.anchorMs + 181500) == -2);
  CHECK(pagersync::anchorElapsedMs(a, a.anchorMs - 500000) == 0);

  pagersync::Anchor paused = a;
  paused.isRunning = false;
  paused.elapsedMs = 150000;
  paused.anchorMs = a.anchorMs + 30000;
  CHECK(pagersync::anchorElapsedSeconds(paused, paused.anchorMs + 99999) == 150);
  CHECK(pagersync::anchorRemainingSeconds(paused, paused.anchorMs + 99999) == 150);

  pagersync::Anchor resumed = paused;
  resumed.isRunning = true;
  resumed.anchorMs = paused.anchorMs + 60000;
  CHECK(pagersync::anchorElapsedSeconds(resumed, resumed.anchorMs) == 150);
  CHECK(pagersync::anchorElapsedSeconds(resumed, resumed.anchorMs + 1000) == 151);
  CHECK(pagersync::anchorElapsedSeconds(resumed, resumed.anchorMs + 10000) == 160);
}

static void testRevGuard() {
  using pagersync::RevKind;
  pagersync::RevGuard g;
  CHECK(g.accept(5));
  CHECK(g.accept(6));
  CHECK(!g.accept(6));
  CHECK(!g.accept(5));
  CHECK(g.accept(7));
  CHECK(g.accept(-1));
  CHECK(!g.accept(3));
  g.reset();
  CHECK(g.accept(3));
  g.resetTo(2);
  CHECK(!g.accept(1));
  CHECK(!g.accept(2));
  CHECK(g.accept(3));

  g.reset();
  CHECK(g.accept(10, RevKind::Rebase));
  CHECK(g.accept(10, RevKind::NotLower));
  CHECK(!g.accept(9, RevKind::NotLower));
  CHECK(!g.accept(10, RevKind::Strict));
  CHECK(g.accept(11, RevKind::Strict));
  CHECK(g.accept(4, RevKind::Rebase));
  CHECK(g.highest == 4);
  CHECK(g.accept(3, RevKind::Rebase));
  CHECK(g.highest == 3);

  g.reset();
  CHECK(g.accept(100));
  CHECK(g.accept(100 + 1000000));
  CHECK(!g.accept(100 + 1000000 + 1000001));
  CHECK(g.highest == 100 + 1000000);
  CHECK(g.accept(100 + 1000000 + 1000001, RevKind::Strict, true));
  CHECK(g.accept(5000000, RevKind::Rebase));
  g.reset();
  CHECK(g.accept(9999999, RevKind::Strict));
  CHECK(!g.accept(9999999 + 1000001, RevKind::NotLower));
  CHECK(g.accept(9999999 + 1000000, RevKind::NotLower));
}

static void testEpoch() {
  pagersync::EpochTracker e;
  CHECK(!e.observe(1234));
  CHECK(!e.observe(1234));
  CHECK(e.observe(99));
  CHECK(!e.observe(99));
  e.reset();
  CHECK(!e.observe(5));
}

static void testAnchorBounds() {
  CHECK(pagersync::anchorInBounds(0, 0));
  CHECK(pagersync::anchorInBounds(604800, 604800000LL));
  CHECK(!pagersync::anchorInBounds(604801, 0));
  CHECK(!pagersync::anchorInBounds(-1, 0));
  CHECK(!pagersync::anchorInBounds(300, -1));
  CHECK(!pagersync::anchorInBounds(300, 604800001LL));
}

struct Msg { std::string id; double ts; };

static std::string messagesHashOf(std::vector<Msg> m) {
  std::sort(m.begin(), m.end(), [](const Msg &x, const Msg &y) {
    return pagersync::messageOrderBefore(x.ts, x.id.c_str(), y.ts, y.id.c_str());
  });
  std::string c;
  for (const Msg &x : m) pagersync::appendMessageId(c, x.id);
  return pagersync::hashHex(c);
}

static void testMessageOrder() {
  CHECK(pagersync::messageOrderBefore(5, "a", 4, "a"));
  CHECK(!pagersync::messageOrderBefore(4, "a", 5, "a"));
  CHECK(pagersync::messageOrderBefore(5, "a", 5, "b"));
  CHECK(!pagersync::messageOrderBefore(5, "b", 5, "a"));
  CHECK(!pagersync::messageOrderBefore(5, "a", 5, "a"));
  CHECK_STR(messagesHashOf({{"b", 7}, {"a", 7}}), "e5e7b9190438f91c");
  CHECK_STR(messagesHashOf({{"a", 7}, {"b", 7}}), "e5e7b9190438f91c");
  CHECK_STR(messagesHashOf({{"m1", 1}, {"m2", 2}}), "dddb4a3dc4d94432");
}

static void testSampleAging() {
  pagersync::OffsetEstimator e;
  CHECK(e.addSample(0, 1000, 1000, 10));
  CHECK(e.sampleCount() == 1);
  CHECK(e.addSample(100, 1100, 1100, 120));
  CHECK(e.sampleCount() == 2);
  CHECK(e.addSample(95000, 96000, 96000, 95010));
  CHECK(e.sampleCount() == 1);
  CHECK_NEAR(e.bestOffset(), 995, 1e-9);

  e.reset();
  e.addSample(0, 1000, 1000, 10);
  e.addSample(100, 1105, 1105, 110);
  e.addSample(200, 1200, 1200, 210);
  CHECK(e.sampleCount() == 3);
  e.prune(90010);
  CHECK(e.sampleCount() == 3);
  e.prune(90011);
  CHECK(e.sampleCount() == 2);
  e.prune(90111);
  CHECK(e.sampleCount() == 1);
  e.prune(90211);
  CHECK(e.sampleCount() == 0);

  e.reset();
  e.addSample(0, 1000, 1000, 10);
  e.addSample(100, 1100, 1100, 110);
  e.addSample(200, 1200, 1200, 210);
  CHECK(e.sampleCount() == 3);
  e.addSample(300, 1400, 1400, 310);
  CHECK(e.sampleCount() == 1);
  CHECK_NEAR(e.bestOffset(), 1095, 1e-9);

  e.reset();
  e.addSample(0, 1000, 1000, 400);
  CHECK_NEAR(e.bestOffset(), 800, 1e-9);
  e.addSample(1000, 2050, 2050, 1200);
  CHECK(e.sampleCount() == 2);
  e.addSample(2000, 3000, 3000, 2010);
  CHECK(e.sampleCount() == 3);
  e.addSample(3000, 4105, 4105, 3010);
  CHECK(e.sampleCount() == 1);

  e.reset();
  CHECK(e.addSample(0, 1000, 1000, 0));
  CHECK(e.addSample(100, 1100, 1099, 100));
  pagersync::Sample neg = pagersync::OffsetEstimator::compute(100, 1100, 1101, 100);
  CHECK(neg.rtt < 0);
  e.reset();
  CHECK(e.addSample(100, 1100, 1101, 100));
  CHECK(e.sampleCount() == 1);
  CHECK_NEAR(e.bestOffset(), 1000.5, 1e-9);

  e.reset();
  CHECK(!e.addSample(0, 50000, 50000, 10001));
  CHECK(e.sampleCount() == 0);
  CHECK(e.addSample(0, 1000, 1000, 10000));
  CHECK(!e.addSample(0, 1000, 1000, 10001));
  e.reset();
  CHECK(!e.addSample(0, 86400000LL + 1000, 86400000LL + 1000, 10));
  CHECK(e.addSample(0, 86400000LL - 1000, 86400000LL - 1000, 10));
  CHECK(e.hasOffset());
  e.reset();
  e.setMaxAbsOffsetMs(4.2e12);
  CHECK(e.addSample(0, 1760000000000LL, 1760000000000LL, 10));
  pagersync::OffsetEstimator fresh;
  CHECK(!fresh.addSample(0, -86400000LL - 100, -86400000LL - 100, 10));
  CHECK(!fresh.hasOffset());
}

struct Collector {
  std::vector<std::string> frames;
  std::vector<size_t> skipped;
  size_t maxFrame = 0;
};

static bool feedAll(pagersync::FrameAssembler &fa, Collector &c, const std::string &bytes, size_t chunk) {
  for (size_t i = 0; i < bytes.size(); i += chunk) {
    size_t n = std::min(chunk, bytes.size() - i);
    bool ok = fa.feed((const uint8_t *)bytes.data() + i, n,
      [&](const uint8_t *d, size_t len) { c.frames.push_back(std::string((const char *)d, len)); },
      [&](size_t len) { c.skipped.push_back(len); });
    if (!ok) return false;
  }
  return true;
}

static std::string frameOf(const std::string &body) {
  uint32_t n = (uint32_t)body.size();
  std::string out;
  out += (char)((n >> 24) & 0xFF);
  out += (char)((n >> 16) & 0xFF);
  out += (char)((n >> 8) & 0xFF);
  out += (char)(n & 0xFF);
  return out + body;
}

static void testFrameAssembler() {
  uint8_t buf[64];
  std::string big(200, 'x');
  std::string stream = frameOf("hello") + frameOf(big) + frameOf("world") + frameOf(std::string(64, 'y')) + frameOf(std::string(65, 'z')) + frameOf("end");
  size_t chunks[] = {1, 2, 3, 7, 64, 1000};
  for (size_t chunk : chunks) {
    pagersync::FrameAssembler fa;
    fa.init(buf, sizeof(buf));
    Collector c;
    CHECK(feedAll(fa, c, stream, chunk));
    CHECK(c.frames.size() == 4);
    CHECK(c.skipped.size() == 2);
    if (c.frames.size() == 4) {
      CHECK_STR(c.frames[0], "hello");
      CHECK_STR(c.frames[1], "world");
      CHECK(c.frames[2] == std::string(64, 'y'));
      CHECK_STR(c.frames[3], "end");
    }
    if (c.skipped.size() == 2) {
      CHECK(c.skipped[0] == 200);
      CHECK(c.skipped[1] == 65);
    }
    CHECK(!fa.desynced());
  }

  pagersync::FrameAssembler fa;
  fa.init(buf, sizeof(buf));
  Collector c;
  CHECK(feedAll(fa, c, frameOf("") + frameOf("a"), 2));
  CHECK(c.frames.size() == 1);

  std::string huge;
  huge += (char)0x7F; huge += (char)0xFF; huge += (char)0xFF; huge += (char)0xFF;
  Collector c2;
  fa.reset();
  CHECK(!feedAll(fa, c2, huge, 4));
  CHECK(fa.desynced());
  fa.reset();
  CHECK(!fa.desynced());

  std::string mid = frameOf(std::string(300, 'q'));
  Collector c3;
  CHECK(feedAll(fa, c3, mid.substr(0, 100), 50));
  CHECK(c3.skipped.empty());
  CHECK(feedAll(fa, c3, mid.substr(100) + frameOf("ok"), 33));
  CHECK(c3.skipped.size() == 1);
  CHECK(c3.frames.size() == 1);
}

static void testFilteredLargeFrame() {
#ifdef HAVE_ARDUINOJSON
  JsonDocument filter;
  filter["type"] = true;
  filter["rev"] = true;
  filter["roleCues"] = true;
  JsonObject m = filter["messages"][0].to<JsonObject>();
  m["id"] = true;
  m["text"] = true;
  std::string src = "{\"type\":\"PONG\",\"rev\":9,\"junk\":{\"a\":[1,2,3]},\"roleCues\":[{\"id\":\"host\"}],\"messages\":[";
  for (int i = 0; i < 20; i++) {
    if (i) src += ",";
    src += "{\"id\":\"m" + std::to_string(i) + "\",\"text\":\"t\",\"extra\":\"" + std::string(100, 'e') + "\"}";
  }
  src += "]}";
  JsonDocument doc;
  DeserializationError err = deserializeJson(doc, src.data(), src.size(), DeserializationOption::Filter(filter));
  CHECK(!err);
  CHECK(doc["messages"].size() == 20);
  CHECK(doc["messages"][0]["extra"].isNull());
  CHECK(doc["junk"].isNull());
  CHECK(doc["rev"].as<int>() == 9);
  CHECK(doc["roleCues"].is<JsonArrayConst>());
  JsonDocument bad;
  CHECK(deserializeJson(bad, src.data(), src.size() / 2, DeserializationOption::Filter(filter)));
#endif
}

static void testTruncation() {
  char buf[8];
  CHECK(!pagersync::copyTruncated(buf, sizeof(buf), "abc"));
  CHECK_STR(buf, "abc");
  CHECK(pagersync::copyTruncated(buf, sizeof(buf), "abcdefghij"));
  CHECK_STR(buf, "abcdefg");
  CHECK(!pagersync::copyTruncated(buf, sizeof(buf), "abcdefg"));
  CHECK(pagersync::copyTruncated(buf, sizeof(buf), "abcdef\xC3\xA9"));
  CHECK_STR(buf, "abcdef");
  CHECK(pagersync::copyTruncated(buf, sizeof(buf), "abcd\xC3\xA9\xC3\xA9"));
  CHECK_STR(buf, "abcd\xC3\xA9");
  CHECK(pagersync::utf8TruncatedLength("\xE2\x82\xAC\xE2\x82\xAC", 4) == 3);
  CHECK(pagersync::utf8TruncatedLength("", 4) == 0);
  CHECK(!pagersync::copyTruncated(buf, 0, "x"));
}

static void testNextItemFilter() {
#ifdef HAVE_ARDUINOJSON
  JsonDocument filter;
  filter["type"] = true;
  filter["nextItem"] = true;
  filter["timerItem"] = true;
  const char *src = "{\"type\":\"TIMER_ANCHOR\",\"junk\":1,\"nextItem\":{\"id\":\"n1\",\"title\":\"Sermon\",\"itemType\":\"Item\",\"lengthInSeconds\":1800,\"notes\":{\"Audio\":\"Lav mic\",\"Video\":\"\"}}}";
  JsonDocument doc;
  CHECK(!deserializeJson(doc, src, strlen(src), DeserializationOption::Filter(filter)));
  CHECK(doc["junk"].isNull());
  CHECK(doc["nextItem"].is<JsonObjectConst>());
  CHECK_STR(doc["nextItem"]["title"].as<const char *>(), "Sermon");
  CHECK(doc["nextItem"]["lengthInSeconds"].as<int>() == 1800);
  CHECK_STR(doc["nextItem"]["notes"]["Audio"].as<const char *>(), "Lav mic");
  const char *nul = "{\"type\":\"PONG\",\"nextItem\":null}";
  JsonDocument d2;
  CHECK(!deserializeJson(d2, nul, strlen(nul), DeserializationOption::Filter(filter)));
  CHECK(!d2["nextItem"].is<JsonObjectConst>());
#endif
}

static void testJson64() {
#ifdef HAVE_ARDUINOJSON
  JsonDocument doc;
  const char *src = "{\"a\":1760000000123,\"b\":1760000000123.0,\"c\":1.760000000123e12}";
  deserializeJson(doc, src);
  CHECK(doc["a"].is<int64_t>());
  CHECK(doc["a"].as<int64_t>() == 1760000000123LL);
  CHECK((int64_t)llround(doc["b"].as<double>()) == 1760000000123LL);
  CHECK((int64_t)llround(doc["c"].as<double>()) == 1760000000123LL);
  JsonDocument out;
  out["t0"] = (int64_t)1760000000123LL;
  std::string s;
  serializeJson(out, s);
  CHECK_STR(s, "{\"t0\":1760000000123}");
#else
  printf("ArduinoJson not found on include path; JSON 64-bit checks skipped\n");
#endif
}

static std::string tod(int64_t ms, int64_t off) {
  char b[24];
  pagersync::formatTimeOfDay(ms, off, b, sizeof(b));
  return b;
}

static std::string len(int64_t s) {
  char b[24];
  pagersync::formatLength(s, b, sizeof(b));
  return b;
}

static void testTimeOfDay() {
  CHECK_STR(tod(0, 0), "12:00:00 AM");
  CHECK_STR(tod(12 * 3600 * 1000LL, 0), "12:00:00 PM");
  CHECK_STR(tod(11 * 3600 * 1000LL + 59 * 60000LL + 59000LL, 0), "11:59:59 AM");
  CHECK_STR(tod(13 * 3600 * 1000LL + 5 * 60000LL + 7000LL, 0), "1:05:07 PM");
  CHECK_STR(tod(23 * 3600 * 1000LL + 59 * 60000LL + 59999LL, 0), "11:59:59 PM");
  CHECK_STR(tod(86400000LL, 0), "12:00:00 AM");
  CHECK_STR(tod(1760000000123LL, 0), "8:53:20 AM");
  CHECK_STR(tod(1760000000123LL, -14400), "4:53:20 AM");
  CHECK_STR(tod(1760000000123LL, 19800), "2:23:20 PM");
  CHECK_STR(tod(0, -1), "11:59:59 PM");
  CHECK_STR(tod(-1, 0), "11:59:59 PM");
  CHECK_STR(tod(-86400000LL, 0), "12:00:00 AM");
  CHECK_STR(tod(1000, 12 * 3600), "12:00:01 PM");
  CHECK_STR(tod(0, 43200 + 3600), "1:00:00 PM");
  CHECK(pagersync::floorDiv(-1, 86400) == -1);
  CHECK(pagersync::floorDiv(86400, 86400) == 1);
  CHECK(pagersync::utcOffsetInBounds(-14400));
  CHECK(pagersync::utcOffsetInBounds(86400));
  CHECK(!pagersync::utcOffsetInBounds(86401));
  CHECK(!pagersync::utcOffsetInBounds(-86401));
}

static void testFormatLength() {
  CHECK_STR(len(0), "0:00");
  CHECK_STR(len(59), "0:59");
  CHECK_STR(len(90), "1:30");
  CHECK_STR(len(3599), "59:59");
  CHECK_STR(len(3600), "1:00:00");
  CHECK_STR(len(3725), "1:02:05");
  CHECK_STR(len(-5), "0:00");
}

static void testCueDisplay() {
  pagersync::CueDisplay d = pagersync::CueDisplay::Outline;
  CHECK(pagersync::parseCueDisplay("full", d) && d == pagersync::CueDisplay::Fullscreen);
  CHECK(pagersync::parseCueDisplay("OUTLINE", d) && d == pagersync::CueDisplay::Outline);
  CHECK(pagersync::parseCueDisplay("Fullscreen", d) && d == pagersync::CueDisplay::Fullscreen);
  CHECK(!pagersync::parseCueDisplay("bogus", d) && d == pagersync::CueDisplay::Fullscreen);
  CHECK(!pagersync::parseCueDisplay("", d));
  CHECK(!pagersync::parseCueDisplay(nullptr, d));
  CHECK_STR(pagersync::cueDisplayName(pagersync::CueDisplay::Outline), "outline");
  CHECK_STR(pagersync::cueDisplayName(pagersync::CueDisplay::Fullscreen), "fullscreen");
}

static void testLinkPhase() {
  using pagersync::LinkPhase;
  CHECK(pagersync::linkPhase(0) == LinkPhase::Live);
  CHECK(pagersync::linkPhase(4999) == LinkPhase::Live);
  CHECK(pagersync::linkPhase(5000) == LinkPhase::Stale);
  CHECK(pagersync::linkPhase(19999) == LinkPhase::Stale);
  CHECK(pagersync::linkPhase(20000) == LinkPhase::Lost);
  CHECK(pagersync::linkPhase(600000) == LinkPhase::Lost);
  CHECK(pagersync::STALE_AFTER_MS == 5000 && pagersync::LOST_AFTER_MS == 20000);
  CHECK(pagersync::msSince(10, 4294967290u) == 16);
  CHECK(pagersync::linkPhase(pagersync::msSince(4998, 4294967295u)) == LinkPhase::Live);
  CHECK(pagersync::linkPhase(pagersync::msSince(4999, 4294967295u)) == LinkPhase::Stale);
  CHECK(pagersync::linkPhase(pagersync::msSince(19998, 0xFFFFFFFFu)) == LinkPhase::Stale);
  CHECK(pagersync::linkPhase(pagersync::msSince(19999, 0xFFFFFFFFu)) == LinkPhase::Lost);
  CHECK(pagersync::linkPhase(pagersync::msSince(100, 0xFFFFFF00u)) == LinkPhase::Live);
  CHECK_STR(pagersync::linkStatusText(true, true, LinkPhase::Live), "Live");
  CHECK_STR(pagersync::linkStatusText(true, true, LinkPhase::Stale), "Disconnected - retrying");
  CHECK_STR(pagersync::linkStatusText(true, false, LinkPhase::Live), "Disconnected - retrying");
  CHECK_STR(pagersync::linkStatusText(false, true, LinkPhase::Live), "Not connected");
}

static void testUtcOffsetFilter() {
#ifdef HAVE_ARDUINOJSON
  JsonDocument filter;
  filter["type"] = true;
  filter["utcOffsetSeconds"] = true;
  JsonDocument a;
  deserializeJson(a, "{\"type\":\"TIMER_ANCHOR\",\"junk\":1,\"utcOffsetSeconds\":-14400}", DeserializationOption::Filter(filter));
  CHECK(a["utcOffsetSeconds"].is<int64_t>());
  CHECK(a["utcOffsetSeconds"].as<int64_t>() == -14400);
  JsonDocument b;
  deserializeJson(b, "{\"type\":\"PONG\"}", DeserializationOption::Filter(filter));
  CHECK(!b["utcOffsetSeconds"].is<int64_t>());
#endif
}

static void testReconnectKeepsState() {
  using namespace pagersync;
  CHECK(keepStateOnReconnect(0));
  CHECK(keepStateOnReconnect(STALE_AFTER_MS));
  CHECK(keepStateOnReconnect(LOST_AFTER_MS - 1));
  CHECK(!keepStateOnReconnect(LOST_AFTER_MS));

  Anchor a;
  a.valid = true;
  a.itemId = "t1";
  a.lengthInSeconds = 600;
  a.elapsedMs = 0;
  a.anchorMs = 1000000;
  a.isRunning = true;
  RevGuard rev;
  EpochTracker epoch;
  OffsetEstimator clock;
  CHECK(rev.accept(40));
  CHECK(!epoch.observe(7));
  CHECK(clock.addSample(1000, 1500, 1500, 1000));
  double held = clock.offsetMs();

  CHECK(a.valid);
  CHECK_STR(a.itemId, "t1");
  CHECK(clock.hasOffset());
  CHECK_NEAR(clock.offsetMs(), held, 0.001);
  CHECK(anchorRemainingSeconds(a, clock.producerNow(1000000 - held + 12000)) == 588);
  CHECK(rev.highest == 40);

  CHECK(rev.accept(40, RevKind::Rebase));
  CHECK(rev.accept(41, RevKind::Rebase));
  CHECK(rev.accept(41, RevKind::NotLower));
  CHECK(!epoch.observe(7));
  CHECK(a.valid);

  CHECK(epoch.observe(8));
  rev.reset();
  clock.reset();
  a = Anchor();
  CHECK(!a.valid);
  CHECK(!clock.hasOffset());
  CHECK(rev.accept(1, RevKind::Strict, true));

  CHECK(!keepStateOnReconnect(LOST_AFTER_MS + 1));
}

int main() {
  testEndpointParse();
  testHashVectors();
  testOffsetFormula();
  testMinRtt();
  testRingKeepsEight();
  testSlewVsJump();
  testProducerNow();
  testAnchor();
  testRevGuard();
  testEpoch();
  testReconnectKeepsState();
  testAnchorBounds();
  testMessageOrder();
  testSampleAging();
  testFrameAssembler();
  testFilteredLargeFrame();
  testTruncation();
  testNextItemFilter();
  testJson64();
  testTimeOfDay();
  testFormatLength();
  testCueDisplay();
  testLinkPhase();
  testUtcOffsetFilter();
  printf("%d checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
