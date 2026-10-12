import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const html = fs.readFileSync(path.join(here, "../../Sources/Shared/Resources/WebPager/pager.html"), "utf8");
const source = /<script id="core">([\s\S]*?)<\/script>/.exec(html)[1];
const names = [
  "fnv1a64", "rolesCanonical", "timerCanonical", "messagesCanonical", "planCanonical", "localHashes",
  "createClockSync", "anchorElapsedMs", "anchorRemainingSeconds", "anchorNextBoundaryMs", "createLink",
];
const core = vm.runInNewContext(`${source}\n({${names.join(",")}})`, { TextEncoder, JSON, Math, Map, BigInt, String, Number });

const US = "\u001f";
const RS = "\u001e";

test("script parses", () => {
  const scripts = [...html.matchAll(/<script(?: id="core")?>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
  assert.equal(scripts.length, 2);
  for (const code of scripts) new vm.Script(code);
});

test("fnv1a64 spec vectors", () => {
  const vectors = [
    ["", "cbf29ce484222325"],
    ["a", "af63dc4c8601ec8c"],
    ["foobar", "85944171f73967e8"],
    [`host${US}Host${US}GO${RS}band${US}Band${US}OFF${RS}`, "aded3b3c0e486304"],
    [`item-1${US}300${US}1${US}0${US}120000${US}1760000000000`, "20a9d930a0849518"],
    ["none", "3c0d17bad169557b"],
    [`m2${RS}m1`, "dddb4a3dc4d94432"],
    [`i1${US}Song${US}300${US}0${RS}i2${US}Sermon${US}2700${US}1${RS}1`, "218cc3247b5ee3f9"],
  ];
  for (const [input, hash] of vectors) assert.equal(core.fnv1a64(input), hash);
});

test("canonical strings reproduce spec vectors", () => {
  const roles = [
    { id: "host", name: "Host", state: "GO" },
    { id: "band", name: "Band", state: "OFF" },
  ];
  assert.equal(core.fnv1a64(core.rolesCanonical(roles)), "aded3b3c0e486304");
  const anchor = {
    itemId: "item-1", lengthInSeconds: 300, elapsedMs: 120000, anchorMs: 1760000000000,
    isRunning: true, isDurationActual: false,
  };
  assert.equal(core.fnv1a64(core.timerCanonical(anchor)), "20a9d930a0849518");
  assert.equal(core.fnv1a64(core.timerCanonical(null)), "3c0d17bad169557b");
  assert.equal(core.fnv1a64(core.messagesCanonical([{ id: "m2" }, { id: "m1" }])), "dddb4a3dc4d94432");
  const plan = {
    items: [
      { id: "i1", title: "Song", lengthInSeconds: 300, isDurationActual: false },
      { id: "i2", title: "Sermon", lengthInSeconds: 2700, isDurationActual: true },
    ],
    activeItemIndex: 1,
  };
  assert.equal(core.fnv1a64(core.planCanonical(plan)), "218cc3247b5ee3f9");
  const local = core.localHashes({ roles, timer: { anchor }, messages: [{ id: "m2" }, { id: "m1" }], plan });
  assert.equal(local.plan, "218cc3247b5ee3f9");
  assert.equal(local.timer, "20a9d930a0849518");
});

test("offset from symmetric exchange", () => {
  const clock = core.createClockSync();
  clock.addSample(1000, 6050, 6052, 1102);
  assert.equal(clock.offset, 5000);
  assert.equal(clock.producerNow(2000), 7000);
});

test("asymmetric rtt biases offset by half the asymmetry", () => {
  const clock = core.createClockSync();
  clock.addSample(0, 1090, 1090, 100);
  assert.equal(clock.offset, 1040);
});

test("min rtt sample wins over newer slower samples", () => {
  const clock = core.createClockSync();
  clock.addSample(0, 1005, 1005, 10);
  assert.equal(clock.offset, 1000);
  clock.addSample(100, 1500, 1500, 400);
  assert.equal(clock.offset, 1000);
  clock.addSample(500, 1530, 1530, 560);
  assert.equal(clock.offset, 1000);
});

test("old best sample ages out after eight samples", () => {
  const clock = core.createClockSync();
  clock.addSample(0, 1005, 1005, 10);
  for (let i = 0; i < 8; i++) clock.addSample(1000 * (i + 1), 1000 * (i + 1) + 2000 + 50, 1000 * (i + 1) + 2000 + 50, 1000 * (i + 1) + 100);
  assert.ok(Math.abs(clock.offset - 2000) < 1000);
  assert.ok(clock.offset > 1000);
});

test("change under 20 ms slews a quarter of the way", () => {
  const clock = core.createClockSync();
  clock.addSample(0, 1000, 1000, 0);
  clock.addSample(100, 1110, 1110, 100);
  assert.equal(clock.offset, 1002.5);
  clock.addSample(200, 1210, 1210, 200);
  assert.equal(clock.offset, 1002.5 + (1010 - 1002.5) * 0.25);
});

test("change of 20 ms or more jumps", () => {
  const clock = core.createClockSync();
  clock.addSample(0, 1000, 1000, 0);
  clock.addSample(100, 1120, 1120, 100);
  assert.equal(clock.offset, 1020);
  clock.addSample(200, 1500, 1500, 200);
  assert.equal(clock.offset, 1300);
});

test("slower samples with a better old sample keep the old offset", () => {
  const clock = core.createClockSync();
  clock.addSample(0, 1000, 1000, 0);
  clock.addSample(100, 1510, 1510, 300);
  assert.equal(clock.offset, 1000);
});

test("anchor evaluation across pause and resume", () => {
  const base = { itemId: "x", lengthInSeconds: 300, isDurationActual: false };
  const running = { ...base, elapsedMs: 120000, anchorMs: 1000000, isRunning: true };
  assert.equal(core.anchorElapsedMs(running, 1000000), 120000);
  assert.equal(core.anchorRemainingSeconds(running, 1000000), 180);
  assert.equal(core.anchorRemainingSeconds(running, 1000999), 180);
  assert.equal(core.anchorRemainingSeconds(running, 1001000), 179);
  const paused = { ...base, elapsedMs: 150500, anchorMs: 1005000, isRunning: false };
  assert.equal(core.anchorRemainingSeconds(paused, 1005000), 150);
  assert.equal(core.anchorRemainingSeconds(paused, 9999999), 150);
  assert.equal(core.anchorNextBoundaryMs(paused, 1005000), null);
  const resumed = { ...base, elapsedMs: 150500, anchorMs: 1100000, isRunning: true };
  assert.equal(core.anchorRemainingSeconds(resumed, 1100000), 150);
  assert.equal(core.anchorRemainingSeconds(resumed, 1100499), 150);
  assert.equal(core.anchorRemainingSeconds(resumed, 1100500), 149);
});

test("anchor never goes below zero elapsed and overtime goes negative", () => {
  const anchor = { itemId: "x", lengthInSeconds: 10, elapsedMs: 0, anchorMs: 5000, isRunning: true, isDurationActual: false };
  assert.equal(core.anchorElapsedMs(anchor, 4000), 0);
  assert.equal(core.anchorRemainingSeconds(anchor, 4000), 10);
  assert.equal(core.anchorRemainingSeconds(anchor, 17000), -2);
});

test("next boundary is aligned to the anchor second grid", () => {
  const anchor = { itemId: "x", lengthInSeconds: 60, elapsedMs: 500, anchorMs: 10000, isRunning: true, isDurationActual: false };
  assert.equal(core.anchorNextBoundaryMs(anchor, 10000), 501);
  assert.equal(core.anchorNextBoundaryMs(anchor, 10499), 2);
  assert.equal(core.anchorNextBoundaryMs(anchor, 10500), 1001);
});

class FakeSocket {
  static instances = [];
  constructor(url) {
    this.url = url;
    this.readyState = 0;
    this.sent = [];
    FakeSocket.instances.push(this);
  }
  send(text) { this.sent.push(JSON.parse(text)); }
  close() {
    this.readyState = 3;
    if (this.onclose) this.onclose();
  }
  open() {
    this.readyState = 1;
    this.onopen();
  }
  receive(payload) { this.onmessage({ data: JSON.stringify(payload) }); }
  lastOp(op) { return this.sent.filter((m) => m.op === op).at(-1); }
}

function harness() {
  FakeSocket.instances = [];
  const h = {
    time: 1_000_000,
    timers: [],
    fetches: [],
    fullCalls: [],
    timerCalls: [],
    snapshot: null,
    stateBody: { rev: 50, roles: [], messages: [], plan: { items: [], activeItemIndex: 0 }, timer: null },
  };
  h.env = {
    WebSocket: FakeSocket,
    url: "ws://x/v1/socket",
    now: () => h.time,
    setTimeout: (fn, ms) => {
      const entry = { fn, at: h.time + ms, cancelled: false };
      h.timers.push(entry);
      return entry;
    },
    clearTimeout: (entry) => { if (entry) entry.cancelled = true; },
    fetch: async (url) => {
      h.fetches.push(url);
      return { ok: true, json: async () => h.stateBody };
    },
    getSnapshot: () => h.snapshot,
    onFull: (state) => { h.snapshot = state; h.fullCalls.push(state); },
    onTimer: (timer) => { h.snapshot.timer = timer; h.timerCalls.push(timer); },
    onStatus: () => {},
  };
  h.advance = (ms) => {
    const target = h.time + ms;
    for (;;) {
      const due = h.timers.filter((t) => !t.cancelled && t.at <= target).sort((a, b) => a.at - b.at)[0];
      if (!due) break;
      due.cancelled = true;
      h.time = due.at;
      due.fn();
    }
    h.time = target;
  };
  h.link = core.createLink(h.env);
  return h;
}

const flush = () => new Promise((r) => setImmediate(r));

test("proto 200 selects v2 and starts a sync burst of five", () => {
  const h = harness();
  h.link.connect();
  const ws = FakeSocket.instances[0];
  ws.open();
  const proto = ws.lastOp("proto");
  assert.deepEqual(proto.body, { version: 2 });
  assert.equal(h.link.mode, "pending");
  ws.receive({ id: proto.id, status: 200, data: { version: 2 } });
  assert.equal(h.link.mode, "v2");
  h.advance(450);
  assert.equal(ws.sent.filter((m) => m.op === "sync").length, 5);
  for (const m of ws.sent.filter((s) => s.op === "sync")) {
    ws.receive({ id: m.id, status: 200, data: { t0: m.body.t0, t1: m.body.t0 + 5000, t2: m.body.t0 + 5000 } });
  }
  assert.equal(h.link.clockReady, true);
  assert.ok(Math.abs(h.link.offset - 5000) <= 250);
  h.advance(30000);
  assert.equal(ws.sent.filter((m) => m.op === "sync").length, 6);
});

test("proto error reply keeps legacy behaviour", async () => {
  const h = harness();
  h.link.connect();
  const ws = FakeSocket.instances[0];
  ws.open();
  const proto = ws.lastOp("proto");
  ws.receive({ id: proto.id, status: 404, error: "unknown op" });
  assert.equal(h.link.mode, "legacy");
  h.advance(60000);
  assert.equal(ws.sent.filter((m) => m.op === "sync").length, 0);
  ws.receive({ event: "hello", data: { rev: 5, roles: [] } });
  ws.receive({ event: "timer", data: { rev: 1, timer: { remainingSeconds: 9 } } });
  assert.equal(h.timerCalls.length, 1);
  assert.equal(h.link.clockReady, false);
  h.time += 1500;
  h.link.pollTick();
  assert.equal(h.fetches.length, 0);
  h.time += 600;
  h.link.pollTick();
  await flush();
  assert.equal(h.fetches.length, 1);
});

test("unanswered proto times out to legacy", () => {
  const h = harness();
  h.link.connect();
  FakeSocket.instances[0].open();
  assert.equal(h.link.mode, "pending");
  h.advance(3100);
  assert.equal(h.link.mode, "legacy");
});

test("no polling while v2 socket is healthy, slow polling when down", async () => {
  const h = harness();
  h.link.connect();
  const ws = FakeSocket.instances[0];
  ws.open();
  ws.receive({ id: ws.lastOp("proto").id, status: 200, data: { version: 2 } });
  ws.receive({ event: "hello", data: { rev: 1, roles: [] } });
  for (let i = 0; i < 20; i++) {
    h.advance(1000);
    ws.receive({ event: "digest", data: { rev: 1, hashes: { roles: core.fnv1a64("") } } });
    h.link.pollTick();
  }
  await flush();
  assert.equal(h.fetches.length, 0);
  ws.close();
  assert.equal(h.link.mode, null);
  for (let i = 0; i < 4; i++) {
    h.time += 1000;
    h.link.pollTick();
  }
  await flush();
  assert.equal(h.fetches.length, 0);
  h.time += 1000;
  h.link.pollTick();
  await flush();
  assert.equal(h.fetches.length, 1);
  assert.equal(h.fetches[0], "/v1/state");
  h.time += 4000;
  h.link.pollTick();
  await flush();
  assert.equal(h.fetches.length, 1);
  h.time += 1000;
  h.link.pollTick();
  await flush();
  assert.equal(h.fetches.length, 2);
});

test("reconnect after close creates a new socket with backoff", () => {
  const h = harness();
  h.link.connect();
  FakeSocket.instances[0].open();
  FakeSocket.instances[0].close();
  assert.equal(FakeSocket.instances.length, 1);
  h.advance(1100);
  assert.equal(FakeSocket.instances.length, 2);
});

function v2Ready() {
  const h = harness();
  h.link.connect();
  const ws = FakeSocket.instances[0];
  ws.open();
  ws.receive({ id: ws.lastOp("proto").id, status: 200, data: { version: 2 } });
  return { h, ws };
}

test("rev guard ignores lower rev timer events, accepts equal and higher, hello resets", () => {
  const { h, ws } = v2Ready();
  ws.receive({ event: "hello", data: { rev: 10, roles: [] } });
  ws.receive({ event: "timer", data: { rev: 9, timer: { tag: "old" } } });
  assert.equal(h.timerCalls.length, 0);
  ws.receive({ event: "timer", data: { rev: 10, timer: { tag: "equal" } } });
  ws.receive({ event: "timer", data: { rev: 12, timer: { tag: "new" } } });
  ws.receive({ event: "timer", data: { rev: 11, timer: { tag: "stale" } } });
  assert.deepEqual(h.timerCalls.map((t) => t.tag), ["equal", "new"]);
  ws.receive({ event: "hello", data: { rev: 2, roles: [] } });
  ws.receive({ event: "timer", data: { rev: 3, timer: { tag: "after-restart" } } });
  assert.equal(h.timerCalls.at(-1).tag, "after-restart");
});

test("matching digest does nothing, mismatch triggers exactly one fetch", async () => {
  const { h, ws } = v2Ready();
  const anchor = { itemId: "a", lengthInSeconds: 60, elapsedMs: 0, anchorMs: 1, isRunning: false, isDurationActual: false };
  const state = {
    rev: 7,
    roles: [{ id: "host", name: "Host", state: "GO" }],
    timer: { anchor },
    messages: [{ id: "m1" }],
    plan: { items: [{ id: "i1", title: "Song", lengthInSeconds: 60, isDurationActual: false }], activeItemIndex: 0 },
  };
  ws.receive({ event: "hello", data: state });
  const good = core.localHashes(state);
  ws.receive({ event: "digest", data: { rev: 7, serverNowMs: 1, hashes: good } });
  await flush();
  assert.equal(h.fetches.length, 0);
  ws.receive({ event: "digest", data: { rev: 7, serverNowMs: 1, hashes: { ...good, messages: core.fnv1a64("m1" + RS + "m0") } } });
  ws.receive({ event: "digest", data: { rev: 7, serverNowMs: 1, hashes: { ...good, plan: "0000000000000000" } } });
  await flush();
  assert.equal(h.fetches.length, 1);
  assert.equal(h.fullCalls.length, 2);
  assert.equal(h.fullCalls.at(-1), h.stateBody);
});

test("v2 liveness is 25 s of silence, legacy keeps 6.5 s", () => {
  const { h, ws } = v2Ready();
  ws.receive({ event: "hello", data: { rev: 1, roles: [] } });
  h.time += 24000;
  assert.equal(h.link.isLive(), true);
  h.time += 1500;
  assert.equal(h.link.isLive(), false);
  h.link.pollTick();
  assert.equal(ws.readyState, 3);

  const legacy = harness();
  legacy.link.connect();
  const lws = FakeSocket.instances.at(-1);
  lws.open();
  lws.receive({ id: lws.lastOp("proto").id, status: 400 });
  lws.receive({ event: "hello", data: { roles: [] } });
  legacy.time += 6000;
  assert.equal(legacy.link.isLive(), true);
  legacy.time += 600;
  assert.equal(legacy.link.isLive(), false);
});
