import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const html = fs.readFileSync(path.join(here, "../../Packages/13YearsClockKit/Sources/ThirteenYearsClockKit/Resources/WebPager/pager.html"), "utf8");
const source = /<script id="core">([\s\S]*?)<\/script>/.exec(html)[1];
const names = ["splitPagerLayout", "layoutFor", "splitPagerWidth", "splitAllowedFor", "SPLIT_DEFAULT", "SPLIT_MIN", "SPLIT_MAX"];
const core = vm.runInNewContext(`${source}\n({${names.join(",")}})`, { TextEncoder, JSON, Math, Map, String, Number, Intl, Date, RegExp, parseInt, isFinite });

test("pager area wider than tall stays landscape", () => {
  assert.equal(core.splitPagerLayout(1000, 800, ""), "landscape");
  assert.equal(core.splitPagerLayout(1000, 800, "auto"), "landscape");
});

test("pager area taller than wide goes portrait", () => {
  assert.equal(core.splitPagerLayout(600, 800, ""), "standard");
  assert.equal(core.splitPagerLayout(800, 800, null), "standard");
});

test("zero or missing height is portrait", () => {
  assert.equal(core.splitPagerLayout(600, 0, ""), "standard");
});

test("explicit landscape parameter keeps landscape", () => {
  assert.equal(core.splitPagerLayout(300, 800, "landscape"), "landscape");
});

test("explicit portrait parameters use standard", () => {
  for (const param of ["standard", "portrait", "full", "Portrait"]) {
    assert.equal(core.splitPagerLayout(2000, 800, param), "standard");
  }
});

test("lower third never splits", () => {
  assert.equal(core.splitPagerLayout(2000, 400, "lowerthird"), "lowerthird");
  assert.equal(core.splitPagerLayout(2000, 400, "third"), "lowerthird");
});

test("agrees with layoutFor for ordinary shapes", () => {
  for (const [w, h] of [[1000, 800], [600, 800], [800, 800], [1200, 700]]) {
    assert.equal(core.splitPagerLayout(w, h, ""), core.layoutFor(w, h, ""));
  }
});

test("a wide window flips to portrait as the divider widens the details panel", () => {
  const width = 1600;
  const height = 900;
  assert.equal(core.splitAllowedFor(width, height), true);
  const at = (fraction) => core.splitPagerLayout(core.splitPagerWidth(width, 22, fraction), height, "");
  assert.equal(at(core.SPLIT_DEFAULT), "landscape");
  assert.equal(at(core.SPLIT_MIN), "standard");
  assert.equal(at(core.SPLIT_MAX), "landscape");
});
