import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const html = fs.readFileSync(path.join(here, "../../Packages/13YearsClockKit/Sources/ThirteenYearsClockKit/Resources/WebPager/pager.html"), "utf8");
const source = /<script id="core">([\s\S]*?)<\/script>/.exec(html)[1];
const names = [
  "decodeDetailsEntities", "safeDetailsLink", "parseDetailsColor", "detailsContrast", "resolveDetailsColors",
  "parseDetailsHTML", "renderDetailsInto", "detailsSourceFor", "clampSplit", "splitFractionForX", "splitAllowedFor",
  "splitPagerWidth", "pagerFieldsForRole", "itemDetailSegments", "itemDetailsLine",
  "SPLIT_DEFAULT", "SPLIT_MIN", "SPLIT_MAX", "DETAILS_MAX_CHARS", "DETAILS_MAX_NODES", "DETAILS_MAX_DEPTH",
];
const core = vm.runInNewContext(`${source}\n({${names.join(",")}})`, { TextEncoder, JSON, Math, Map, String, Number, Intl, Date, RegExp, parseInt, isFinite });

class FakeNode {
  constructor(tag) {
    this.tag = tag;
    this.children = [];
    this.attrs = {};
    this.style = {};
  }
  appendChild(child) { this.children.push(child); return child; }
  removeChild(child) { this.children.splice(this.children.indexOf(child), 1); }
  setAttribute(name, value) { this.attrs[name] = value; }
  get firstChild() { return this.children[0] || null; }
}

const fakeDoc = {
  createElement: (tag) => new FakeNode(tag),
  createTextNode: (value) => ({ text: value }),
};

function render(htmlText, ground) {
  const root = new FakeNode("#container");
  core.renderDetailsInto(root, htmlText, fakeDoc, ground);
  return root;
}

function walk(node, visit) {
  visit(node);
  for (const child of node.children || []) walk(child, visit);
}

function tags(root) {
  const found = [];
  walk(root, (n) => { if (n.tag && n.tag !== "#container") found.push(n.tag); });
  return found;
}

function text(root) {
  let out = "";
  walk(root, (n) => { if (typeof n.text === "string") out += n.text; });
  return out;
}

test("itemDetails is a selectable field but never part of the line", () => {
  assert.deepEqual(Array.from(core.pagerFieldsForRole({ pagerFields: ["itemDetails", "key"] })), ["key", "itemDetails"]);
  const item = { itemType: "Song", details: { keyName: "G", htmlDetails: "<p>x</p>" } };
  assert.equal(core.itemDetailsLine(item, ["key", "itemDetails"], null, null, "twentyFourHour"), "G");
  assert.equal(core.itemDetailsLine(item, ["itemDetails"], null, null, "twentyFourHour"), "");
});

test("details source needs the field, prefers html, skips headers", () => {
  const item = { itemType: "Song", details: { htmlDetails: "<p>Hi</p>", description: "plain" } };
  assert.equal(core.detailsSourceFor(item, ["itemDetails"]), "<p>Hi</p>");
  assert.equal(core.detailsSourceFor(item, ["key"]), "");
  assert.equal(core.detailsSourceFor({ itemType: "Item", details: { description: "plain" } }, ["itemDetails"]), "plain");
  assert.equal(core.detailsSourceFor({ itemType: "Header", details: { htmlDetails: "<p>x</p>" } }, ["itemDetails"]), "");
  assert.equal(core.detailsSourceFor({ itemType: "Item" }, ["itemDetails"]), "");
  assert.equal(core.detailsSourceFor(null, ["itemDetails"]), "");
});

test("script, style, iframe and friends are dropped with their content", () => {
  const root = render('<p>a</p><script>alert(1)</script><style>p{x:y}</style><iframe src="http://x"><b>hidden</b></iframe><object><p>no</p></object><p>b</p>');
  assert.deepEqual(tags(root), ["p", "p"]);
  assert.equal(text(root), "ab");
});

test("images and form controls never reach the DOM", () => {
  const root = render('<p>x<img src="http://e/x.png" onerror="alert(1)">y<input value="z"><svg><script>1</script></svg></p>');
  assert.deepEqual(tags(root), ["p"]);
  assert.equal(text(root), "xy");
});

test("event handlers and unknown attributes are discarded", () => {
  const root = render('<p onclick="alert(1)" id="x" class="y">hi</p><a href="https://example.com/a" onclick="x()" target="_self">l</a>');
  walk(root, (n) => {
    for (const key of Object.keys(n.attrs || {})) assert.ok(["href", "rel", "target"].includes(key), key);
  });
  const link = root.children[1];
  assert.equal(link.tag, "a");
  assert.equal(link.attrs.href, "https://example.com/a");
  assert.equal(link.attrs.rel, "noopener noreferrer");
  assert.equal(link.attrs.target, "_blank");
});

test("only http and https links survive, even when obfuscated", () => {
  for (const bad of ["javascript:alert(1)", "  JaVaScRiPt:alert(1)", "jav&#x09;ascript:alert(1)", "java\nscript:alert(1)", "data:text/html,<script>1</script>", "vbscript:x", "//evil.example/x", "/relative", "ftp://host/x", "mailto:a@b.c", "https:///nohost"]) {
    const root = render(`<a href="${bad}">t</a>`);
    assert.equal(root.children[0].attrs.href, undefined, bad);
  }
  for (const good of ["http://example.com", "HTTPS://Example.com/path?q=1#h"]) {
    const root = render(`<a href="${good}">t</a>`);
    assert.equal(root.children[0].attrs.href, good);
  }
});

test("markup in text is inert because everything goes through text nodes", () => {
  const root = render("<p>&lt;script&gt;alert(1)&lt;/script&gt; &amp; &#60;b&#62;</p>");
  assert.deepEqual(tags(root), ["p"]);
  assert.equal(text(root), "<script>alert(1)</script> & <b>");
});

test("entities decode, bad numeric entities vanish", () => {
  assert.equal(core.decodeDetailsEntities("a&nbsp;b &amp; &#x41;&#66; &#0; &#xD800; &bogus;"), "a" + String.fromCharCode(160) + "b & AB   &bogus;");
});

test("unknown wrappers unwrap and keep their text", () => {
  const root = render("<section><custom-x>kept <b>bold</b></custom-x></section>");
  assert.deepEqual(tags(root), ["b"]);
  assert.equal(text(root), "kept bold");
});

test("lists, headings, tables and inline formatting are kept", () => {
  const root = render("<h2>T</h2><ul><li>a</li><li>b</li></ul><table><tr><td>c</td></tr></table><p><em>e</em><strong>s</strong><u>u</u></p>");
  assert.deepEqual(tags(root), ["h2", "ul", "li", "li", "table", "tr", "td", "p", "em", "strong", "u"]);
});

test("comments, doctype and unterminated constructs do not leak or throw", () => {
  assert.equal(text(render("<!doctype html><!-- <b>x</b> --><p>ok</p>")), "ok");
  assert.doesNotThrow(() => render("<p"));
  assert.doesNotThrow(() => render("<p class='a"));
  assert.doesNotThrow(() => render("<!-- never closed <p>x</p>"));
  assert.doesNotThrow(() => render("<script>never closed <p>x</p>"));
  assert.equal(text(render("<script>never closed <p>x</p>")), "");
  assert.equal(text(render("a < b and c > d")), "a < b and c > d");
});

test("an unclosed iframe cannot reveal what follows it", () => {
  assert.equal(text(render("<p>before</p><iframe src='x'><p>after</p>")), "before");
});

test("quoted attribute values may contain angle brackets without ending the tag", () => {
  const root = render('<a href="https://e.com/?a=<b>" title="x>y">go</a><p>next</p>');
  assert.deepEqual(tags(root), ["a", "p"]);
  assert.equal(text(root), "gonext");
});

test("size, node and depth limits hold", () => {
  const long = "x".repeat(core.DETAILS_MAX_CHARS * 2);
  assert.equal(text(render(long)).length, core.DETAILS_MAX_CHARS);
  const many = "<b>a</b>".repeat(20000);
  let count = 0;
  walk(render(many), () => { count++; });
  assert.ok(count <= core.DETAILS_MAX_NODES + 2, String(count));
  const deep = "<div>".repeat(500) + "deep" + "</div>".repeat(500);
  let depth = 0;
  (function measure(node, level) {
    depth = Math.max(depth, level);
    for (const child of node.children || []) measure(child, level + 1);
  })(render(deep), 0);
  assert.ok(depth <= core.DETAILS_MAX_DEPTH + 2, String(depth));
  assert.equal(text(render(deep)), "deep");
});

test("colors are normalised and held to a contrast floor against the panel", () => {
  const ground = { r: 27, g: 27, b: 32, a: 1 };
  const bright = render('<span style="color: #ff8800">a</span>', ground).children[0];
  assert.equal(bright.style.color, "rgb(255, 136, 0)");
  const dark = render('<span style="color: #111111">a</span>', ground).children[0];
  assert.equal(dark.style.color, undefined);
  const onYellow = render('<span style="color:#ffffff; background-color:#ffee00">a</span>', ground).children[0];
  assert.equal(onYellow.style.backgroundColor, "rgb(255, 238, 0)");
  assert.equal(onYellow.style.color, "rgb(0, 0, 0)");
  const font = render('<font color="rgb(10, 200, 30)">a</font>', ground).children[0];
  assert.equal(font.tag, "span");
  assert.equal(font.style.color, "rgb(10, 200, 30)");
});

test("hostile style values never reach the element", () => {
  const root = render('<span style="color: expression(alert(1)); background: url(javascript:alert(1)); position: fixed">a</span>');
  const span = root.children[0];
  assert.deepEqual(Object.keys(span.style), []);
  assert.deepEqual(Object.keys(span.attrs), []);
  assert.equal(core.parseDetailsColor("red"), null);
  assert.equal(core.parseDetailsColor("rgb(300, 0, 0)"), null);
  assert.deepEqual(JSON.parse(JSON.stringify(core.parseDetailsColor("#0f0"))), { r: 0, g: 255, b: 0, a: 1 });
});

test("rendering twice replaces the previous content", () => {
  const root = render("<p>one</p>");
  core.renderDetailsInto(root, "<p>two</p>", fakeDoc);
  assert.equal(text(root), "two");
});

test("split fraction clamps to 40 to 80 percent and resets on garbage", () => {
  assert.equal(core.clampSplit(0.1), 0.4);
  assert.equal(core.clampSplit(0.95), 0.8);
  assert.equal(core.clampSplit(0.5), 0.5);
  assert.equal(core.clampSplit("abc"), 2 / 3);
  assert.equal(core.clampSplit(NaN), 2 / 3);
  assert.equal(core.SPLIT_DEFAULT, 2 / 3);
});

test("divider position maps to a fraction of the usable width", () => {
  assert.equal(core.splitFractionForX(11 + 600, 1822, 22), 600 / 1800 < 0.4 ? 0.4 : 600 / 1800);
  assert.ok(Math.abs(core.splitFractionForX(11 + 900, 1822, 22) - 0.5) < 1e-9);
  assert.equal(core.splitFractionForX(0, 1000, 22), 0.4);
  assert.equal(core.splitFractionForX(5000, 1000, 22), 0.8);
  assert.equal(core.splitFractionForX(300, 0, 22), 2 / 3);
});

test("pager side width excludes the divider and follows the fraction", () => {
  assert.ok(Math.abs(core.splitPagerWidth(1822, 22, 2 / 3) - 1200) < 1e-9);
  assert.equal(core.splitPagerWidth(1822, 22, 0.1), 1800 * 0.4);
  assert.equal(core.splitPagerWidth(10, 22, 0.5), 0);
});

test("the split only applies to genuinely wide viewports", () => {
  assert.equal(core.splitAllowedFor(1920, 1080), true);
  assert.equal(core.splitAllowedFor(1180, 820), true);
  assert.equal(core.splitAllowedFor(900, 800), false);
  assert.equal(core.splitAllowedFor(800, 1200), false);
  assert.equal(core.splitAllowedFor(100, 0), false);
});
