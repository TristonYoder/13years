// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#include "../src/sync/sync_core.h"
#include <stdio.h>
#include <string>

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
  pagersync::RevGuard g;
  CHECK(g.accept(5));
  CHECK(g.accept(6));
  CHECK(g.accept(6));
  CHECK(!g.accept(5));
  CHECK(g.accept(7));
  CHECK(g.accept(-1));
  CHECK(!g.accept(3));
  g.reset();
  CHECK(g.accept(3));
  g.resetTo(2);
  CHECK(!g.accept(1));
  CHECK(g.accept(2));
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

int main() {
  testHashVectors();
  testOffsetFormula();
  testMinRtt();
  testRingKeepsEight();
  testSlewVsJump();
  testProducerNow();
  testAnchor();
  testRevGuard();
  testJson64();
  printf("%d checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
