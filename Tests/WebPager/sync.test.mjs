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
  "backoffDelay", "lowerThirdForViewport", "layoutFor", "formatLocalTime", "msUntilNextSecond", "countdownEmWidth", "createRoleSelection", "matchRole", "countdownStage",
  "createWakeLock", "restRequest", "validAnchor", "sanitizeTimer", "nextItemFor", "notesForRole", "cueWordFor", "escapeHtml", "noteEntryHTML", "formatProjectedLength", "clockSlotFor", "fitScale", "bottomRowMode", "parseCueDisplay", "cueDisplayFor",
];
const core = vm.runInNewContext(`${source}\n({${names.join(",")}})`, { TextEncoder, JSON, Math, Map, String, Number, Intl });

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
  const stamp = (n) => new Date(1760000000000 + n * 1000).toISOString();
  assert.equal(core.fnv1a64(core.messagesCanonical([{ id: "m1", timestamp: stamp(1) }, { id: "m2", timestamp: stamp(2) }])), "dddb4a3dc4d94432");
  const plan = {
    items: [
      { id: "i1", title: "Song", lengthInSeconds: 300, isDurationActual: false },
      { id: "i2", title: "Sermon", lengthInSeconds: 2700, isDurationActual: true },
    ],
    activeItemIndex: 1,
  };
  assert.equal(core.fnv1a64(core.planCanonical(plan)), "218cc3247b5ee3f9");
  const local = core.localHashes({ roles, timer: { anchor }, messages: [{ id: "m1", timestamp: stamp(1) }, { id: "m2", timestamp: stamp(2) }], plan });
  assert.equal(local.plan, "218cc3247b5ee3f9");
  assert.equal(local.timer, "20a9d930a0849518");
  assert.equal(local.messages, "dddb4a3dc4d94432");
});

test("messages tie vector: equal timestamps order by id ascending", () => {
  const at = "2025-10-09T08:00:00.000Z";
  const forward = [{ id: "a", timestamp: at }, { id: "b", timestamp: at }];
  const backward = [{ id: "b", timestamp: at }, { id: "a", timestamp: at }];
  assert.equal(core.messagesCanonical(forward), "a" + RS + "b");
  assert.equal(core.messagesCanonical(backward), "a" + RS + "b");
  assert.equal(core.fnv1a64(core.messagesCanonical(backward)), "e5e7b9190438f91c");
  const mixed = [
    { id: "a", timestamp: "2025-10-09T08:00:00.000Z" },
    { id: "z", timestamp: "2025-10-09T08:00:01.000Z" },
    { id: "b", timestamp: "2025-10-09T08:00:00.000Z" },
  ];
  assert.equal(core.messagesCanonical(mixed), "z" + RS + "a" + RS + "b");
});

test("fnv1a64 handles multi-byte text and long input without BigInt", () => {
  assert.equal(core.fnv1a64("caf\u00e9").length, 16);
  assert.notEqual(core.fnv1a64("caf\u00e9"), core.fnv1a64("cafe"));
  assert.equal(/BigInt|\d+n\b/.test(source), false);
  let expected = 0xcbf29ce484222325n;
  const input = "The quick brown fox \u2603 ".repeat(40);
  for (const byte of new TextEncoder().encode(input)) {
    expected ^= BigInt(byte);
    expected = (expected * 0x100000001b3n) & 0xffffffffffffffffn;
  }
  assert.equal(core.fnv1a64(input), expected.toString(16).padStart(16, "0"));
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
    random: 0.5,
    stateBody: { rev: 50, roles: [], messages: [], plan: { items: [], activeItemIndex: 0 }, timer: null },
  };
  h.env = {
    WebSocket: FakeSocket,
    url: "ws://x/v1/socket",
    now: () => h.time,
    mono: () => h.time,
    random: () => h.random,
    setTimeout: (fn, ms) => {
      const entry = { fn, at: h.time + ms, cancelled: false };
      h.timers.push(entry);
      return entry;
    },
    clearTimeout: (entry) => { if (entry) entry.cancelled = true; },
    fetch: async (url) => {
      h.fetches.push(url);
      if (h.fetchImpl) return h.fetchImpl(url);
      return { ok: true, status: 200, json: async () => h.stateBody };
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

test("rev guard is strict for timer events and hello resets", () => {
  const { h, ws } = v2Ready();
  ws.receive({ event: "hello", data: { rev: 10, roles: [] } });
  ws.receive({ event: "timer", data: { rev: 9, timer: { tag: "old" } } });
  assert.equal(h.timerCalls.length, 0);
  ws.receive({ event: "timer", data: { rev: 10, timer: { tag: "equal" } } });
  ws.receive({ event: "timer", data: { rev: 12, timer: { tag: "new" } } });
  ws.receive({ event: "timer", data: { rev: 11, timer: { tag: "stale" } } });
  assert.deepEqual(h.timerCalls.map((t) => t.tag), ["new"]);
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
  assert.equal(ws.onclose, null);
  assert.equal(FakeSocket.instances.length, 2);

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

function clockAt() {
  const t = { now: 0 };
  t.clock = core.createClockSync(() => t.now);
  return t;
}

test("samples older than 90 s are ignored", () => {
  const t = clockAt();
  t.clock.addSample(0, 1005, 1005, 10);
  assert.equal(t.clock.offset, 1000);
  t.now = 60000;
  t.clock.addSample(0, 1300, 1300, 400);
  assert.equal(t.clock.count, 2);
  assert.equal(t.clock.offset, 1000);
  t.now = 91000;
  t.clock.addSample(0, 1300, 1300, 400);
  assert.equal(t.clock.count, 2);
  assert.equal(t.clock.offset, 1100);
});

test("fresh offset beyond max(50 ms, 2 rtt) discards older samples", () => {
  const t = clockAt();
  t.clock.addSample(0, 1000, 1000, 0);
  t.now = 1000;
  t.clock.addSample(0, 1040, 1040, 0);
  assert.equal(t.clock.count, 2);
  t.now = 2000;
  t.clock.addSample(0, 1090, 1090, 0);
  assert.equal(t.clock.count, 3);
  t.now = 3000;
  t.clock.addSample(0, 1300, 1300, 20);
  assert.equal(t.clock.count, 1);
  t.now = 4000;
  t.clock.addSample(0, 1700, 1700, 400);
  assert.equal(t.clock.count, 2);
});

test("negative rtt clamps to zero and absurd samples are ignored", () => {
  const t = clockAt();
  t.clock.addSample(100, 1100, 1105, 102);
  assert.equal(t.clock.ready, true);
  const held = t.clock.offset;
  t.clock.addSample(0, 5, 5, 10001);
  assert.equal(t.clock.offset, held);
  t.clock.addSample(0, 90000000, 90000000, 10);
  assert.equal(t.clock.offset, held);
  assert.equal(t.clock.count, 1);
});

test("clear keeps the offset, reset forgets it", () => {
  const t = clockAt();
  t.clock.addSample(0, 500, 500, 0);
  t.clock.clear();
  assert.equal(t.clock.count, 0);
  assert.equal(t.clock.ready, true);
  t.clock.reset();
  assert.equal(t.clock.ready, false);
  assert.equal(t.clock.offset, 0);
});

function answerSyncs(ws, offset) {
  for (const m of ws.sent.filter((s) => s.op === "sync" && !s.answered)) {
    m.answered = true;
    ws.receive({ id: m.id, status: 200, data: { t0: m.body.t0, t1: m.body.t0 + offset, t2: m.body.t0 + offset } });
  }
}

test("epoch change resets anchor hook, rev gate and samples, bursts sync and refetches", async () => {
  const { h, ws } = v2Ready();
  let epochResets = 0;
  h.env.onEpoch = () => { epochResets++; };
  h.link = core.createLink(h.env);
  FakeSocket.instances = [];
  h.link.connect();
  const sock = FakeSocket.instances[0];
  sock.open();
  sock.receive({ id: sock.lastOp("proto").id, status: 200, data: { version: 2 } });
  sock.receive({ event: "hello", data: { rev: 500, epoch: 7, roles: [] } });
  h.advance(450);
  answerSyncs(sock, 3000);
  assert.equal(h.link.clockReady, true);
  assert.ok(h.link.sampleCount > 0);
  assert.equal(h.link.heldRev, 500);
  const syncsBefore = sock.sent.filter((m) => m.op === "sync").length;
  sock.receive({ event: "timer", data: { rev: 3, epoch: 7, timer: { tag: "low" } } });
  assert.equal(h.timerCalls.length, 0);
  sock.receive({ event: "timer", data: { rev: 4, epoch: 8, timer: { tag: "restarted" } } });
  assert.equal(epochResets, 1);
  assert.equal(h.link.epoch, 8);
  assert.equal(h.link.heldRev, 4);
  assert.equal(h.link.clockReady, false);
  assert.equal(h.link.sampleCount, 0);
  assert.equal(h.timerCalls.at(-1).tag, "restarted");
  assert.ok(sock.sent.filter((m) => m.op === "sync").length > syncsBefore);
  await flush();
  assert.equal(h.fetches.length, 1);
  assert.equal(h.fullCalls.at(-1), h.stateBody);
  assert.equal(h.link.heldRev, 50);
});

test("epoch change on digest triggers a fetch even when the hashes match", async () => {
  const { h, ws } = v2Ready();
  ws.receive({ event: "hello", data: { rev: 5, epoch: 1, roles: [] } });
  ws.receive({ event: "digest", data: { rev: 5, epoch: 1, hashes: { roles: core.fnv1a64("") } } });
  await flush();
  assert.equal(h.fetches.length, 0);
  ws.receive({ event: "digest", data: { rev: 1, epoch: 2, hashes: { roles: core.fnv1a64("") } } });
  await flush();
  assert.equal(h.fetches.length, 1);
  assert.equal(h.link.heldRev, 50);
});

test("hello with a new epoch rebases and bursts a sync", () => {
  const { h, ws } = v2Ready();
  ws.receive({ event: "hello", data: { rev: 900, epoch: 1, roles: [] } });
  const before = ws.sent.filter((m) => m.op === "sync").length;
  ws.receive({ event: "hello", data: { rev: 2, epoch: 2, roles: [] } });
  assert.equal(h.link.heldRev, 2);
  assert.ok(ws.sent.filter((m) => m.op === "sync").length > before);
  ws.receive({ event: "timer", data: { rev: 3, epoch: 2, timer: { tag: "ok" } } });
  assert.equal(h.timerCalls.at(-1).tag, "ok");
});

test("strict rev: equal is dropped, jump over 1,000,000 is ignored unless epoch changed", () => {
  const { h, ws } = v2Ready();
  ws.receive({ event: "hello", data: { rev: 10, epoch: 1, roles: [] } });
  ws.receive({ event: "state", data: { rev: 10, roles: [{ id: "x" }] } });
  assert.equal(h.fullCalls.length, 1);
  ws.receive({ event: "state", data: { rev: 11, roles: [{ id: "y" }] } });
  assert.equal(h.fullCalls.length, 2);
  ws.receive({ event: "timer", data: { rev: 11 + 1000001, epoch: 1, timer: { tag: "wild" } } });
  assert.equal(h.timerCalls.length, 0);
  assert.equal(h.link.heldRev, 11);
  ws.receive({ event: "timer", data: { rev: 11 + 1000000, epoch: 1, timer: { tag: "edge" } } });
  assert.equal(h.timerCalls.at(-1).tag, "edge");
  ws.receive({ event: "timer", data: { rev: 5000000, epoch: 9, timer: { tag: "newepoch" } } });
  assert.equal(h.timerCalls.at(-1).tag, "newepoch");
});

test("fetched state never lowers heldRev and is dropped when stale", async () => {
  const { h, ws } = v2Ready();
  ws.receive({ event: "hello", data: { rev: 100, roles: [] } });
  h.stateBody = { rev: 60, roles: [], messages: [], plan: { items: [], activeItemIndex: 0 }, timer: null };
  const fullsBefore = h.fullCalls.length;
  await h.link.fetchState();
  assert.equal(h.fullCalls.length, fullsBefore);
  assert.equal(h.link.heldRev, 100);
  h.stateBody = { ...h.stateBody, rev: 120 };
  await h.link.fetchState();
  assert.equal(h.fullCalls.length, fullsBefore + 1);
  assert.equal(h.link.heldRev, 120);
});

test("fetched state following a reconnect is accepted even with a lower rev", async () => {
  const { h, ws } = v2Ready();
  ws.receive({ event: "hello", data: { rev: 100, roles: [] } });
  ws.close();
  h.advance(600);
  const next = FakeSocket.instances[1];
  next.open();
  h.stateBody = { rev: 3, roles: [], messages: [], plan: { items: [], activeItemIndex: 0 }, timer: null };
  await h.link.fetchState();
  assert.equal(h.fullCalls.at(-1), h.stateBody);
  assert.equal(h.link.heldRev, 3);
});

test("anchors outside bounds are ignored but the rest of the timer is kept", () => {
  const good = { itemId: "a", lengthInSeconds: 604800, elapsedMs: 604800000, anchorMs: 1, isRunning: true, isDurationActual: false };
  assert.equal(core.validAnchor(good), true);
  assert.equal(core.validAnchor({ ...good, lengthInSeconds: 604801 }), false);
  assert.equal(core.validAnchor({ ...good, elapsedMs: -1 }), false);
  assert.equal(core.validAnchor({ ...good, elapsedMs: 604800001 }), false);
  assert.equal(core.validAnchor({ ...good, anchorMs: NaN }), false);
  const timer = { remainingSeconds: 9, anchor: { ...good, lengthInSeconds: -5 } };
  const cleaned = core.sanitizeTimer(timer);
  assert.equal(cleaned.remainingSeconds, 9);
  assert.equal("anchor" in cleaned, false);
  assert.equal(core.sanitizeTimer({ anchor: good }).anchor, good);
  const { h, ws } = v2Ready();
  ws.receive({ event: "hello", data: { rev: 1, roles: [] } });
  ws.receive({ event: "timer", data: { rev: 2, timer: timer } });
  assert.equal("anchor" in h.timerCalls.at(-1), false);
});

test("backoff delay is jittered and capped at 5 s", () => {
  for (let attempt = 0; attempt < 12; attempt++) {
    const base = Math.min(5000, 500 * 2 ** attempt);
    for (const r of [0, 0.25, 0.5, 0.999, 1]) {
      const d = core.backoffDelay(attempt, r);
      assert.ok(d >= Math.round(base / 2) && d <= base, `${attempt} ${r} ${d}`);
      assert.ok(d <= 5000);
    }
  }
  assert.equal(core.backoffDelay(0, 1), 500);
  assert.equal(core.backoffDelay(20, 1), 5000);
});

test("reconnect delays grow with attempts and honour jitter", () => {
  const h = harness();
  h.random = 1;
  h.link.connect();
  const delays = [];
  for (let i = 0; i < 6; i++) {
    const sock = FakeSocket.instances.at(-1);
    const before = FakeSocket.instances.length;
    sock.close();
    let waited = 0;
    while (FakeSocket.instances.length === before && waited < 6000) {
      h.advance(50);
      waited += 50;
    }
    delays.push(waited);
  }
  assert.deepEqual(delays, [500, 1000, 2000, 4000, 5000, 5000]);
});

test("socket constructor throwing is retried", () => {
  const h = harness();
  let calls = 0;
  h.env.WebSocket = function Throwing(url) {
    calls++;
    if (calls < 3) throw new Error("boom");
    return new FakeSocket(url);
  };
  h.link = core.createLink(h.env);
  h.link.connect();
  assert.equal(calls, 1);
  h.advance(600);
  assert.equal(calls, 2);
  h.advance(1100);
  assert.equal(calls, 3);
  assert.equal(FakeSocket.instances.length, 1);
});

test("half-open socket is detached and replaced immediately after 25 s of silence", () => {
  const { h, ws } = v2Ready();
  ws.receive({ event: "hello", data: { rev: 1, roles: [] } });
  h.time += 25000;
  h.link.pollTick();
  assert.equal(FakeSocket.instances.length, 2);
  assert.equal(ws.onmessage, null);
  assert.equal(ws.onclose, null);
  assert.equal(h.link.mode, null);
  FakeSocket.instances[1].open();
  assert.equal(h.link.mode, "pending");
});

test("wake with a stale last frame reconnects, with a fresh one it only resamples", () => {
  const { h, ws } = v2Ready();
  ws.receive({ event: "hello", data: { rev: 1, roles: [] } });
  h.time += 2000;
  const syncs = ws.sent.filter((m) => m.op === "sync").length;
  h.link.wake();
  assert.equal(FakeSocket.instances.length, 1);
  assert.ok(ws.sent.filter((m) => m.op === "sync").length > syncs);
  h.time += 6000;
  h.link.wake();
  assert.equal(FakeSocket.instances.length, 2);
});

test("hung state fetch times out and does not pin the fetching flag", async () => {
  const h = harness();
  let calls = 0;
  h.fetchImpl = () => {
    calls++;
    if (calls === 1) return new Promise(() => {});
    return Promise.resolve({ ok: true, status: 200, json: async () => h.stateBody });
  };
  const first = h.link.fetchState();
  assert.equal(h.link.fetchState(), first);
  await flush();
  h.advance(3000);
  await first;
  await flush();
  await h.link.fetchState();
  assert.equal(calls, 2);
  assert.equal(h.fullCalls.length, 1);
});

test("restRequest passes an abort signal and rejects on timeout", async () => {
  const h = harness();
  let seen = null;
  const env = {
    fetch: (url, init) => { seen = init; return new Promise(() => {}); },
    setTimeout: h.env.setTimeout,
    clearTimeout: h.env.clearTimeout,
    timeoutSignal: (ms) => ({ ms }),
  };
  const outcome = core.restRequest(env, "/v1/messages", { method: "POST" }, false).then(() => "ok", (e) => e.message);
  await flush();
  assert.deepEqual(seen.signal, { ms: 3000 });
  assert.equal(seen.method, "POST");
  h.advance(3000);
  assert.equal(await outcome, "timeout");
});

test("lower-third needs aspect ratio of at least 3:1", () => {
  assert.equal(core.lowerThirdForViewport(1920, 360), true);
  assert.equal(core.lowerThirdForViewport(1200, 400), true);
  assert.equal(core.lowerThirdForViewport(844, 390), false);
  assert.equal(core.lowerThirdForViewport(667, 375), false);
  assert.equal(core.lowerThirdForViewport(1920, 1080), false);
  assert.equal(core.lowerThirdForViewport(300, 100), true);
  assert.equal(core.lowerThirdForViewport(100, 0), false);
});

test("role param applies only at load, later choices persist", () => {
  const roles = [{ id: "r1", name: "Host" }, { id: "r2", name: "Band" }];
  const sel = core.createRoleSelection("band", "r1");
  assert.equal(sel.adopt([]), "band");
  assert.equal(sel.adopt(roles), "r2");
  sel.select("r1");
  assert.equal(sel.adopt(roles), "r1");
  assert.equal(sel.adopt(roles), "r1");
  const stored = core.createRoleSelection("", "r2");
  assert.equal(stored.adopt(roles), "r2");
  const empty = core.createRoleSelection("", "");
  assert.equal(empty.adopt(roles), "r1");
  const unknown = core.createRoleSelection("nobody", "");
  assert.equal(unknown.adopt(roles), "nobody");
  assert.equal(core.matchRole(roles, "R2"), "r2");
  assert.equal(core.matchRole(roles, "host"), "r1");
});

test("countdown stages", () => {
  assert.equal(core.countdownStage(61), "");
  assert.equal(core.countdownStage(60), "");
  assert.equal(core.countdownStage(59), "amber");
  assert.equal(core.countdownStage(30), "amber");
  assert.equal(core.countdownStage(29), "red");
  assert.equal(core.countdownStage(0), "red");
  assert.equal(core.countdownStage(-12), "red");
  assert.equal(core.countdownStage(null), "");
});

test("wake lock is feature detected and re-acquired after release", async () => {
  assert.equal(await core.createWakeLock({ navigator: {}, visible: () => true }).acquire(), false);
  assert.equal(await core.createWakeLock({ navigator: undefined, visible: () => true }).acquire(), false);
  let requests = 0;
  const listeners = [];
  const nav = { wakeLock: { request: async (kind) => { requests++; assert.equal(kind, "screen"); return { addEventListener: (_, fn) => listeners.push(fn) }; } } };
  let visible = false;
  const lock = core.createWakeLock({ navigator: nav, visible: () => visible });
  assert.equal(await lock.acquire(), false);
  visible = true;
  assert.equal(await lock.acquire(), true);
  assert.equal(await lock.acquire(), false);
  assert.equal(requests, 1);
  assert.equal(lock.held, true);
  listeners[0]();
  assert.equal(lock.held, false);
  assert.equal(await lock.acquire(), true);
  assert.equal(requests, 2);
  const failing = core.createWakeLock({ navigator: { wakeLock: { request: async () => { throw new Error("denied"); } } }, visible: () => true });
  assert.equal(await failing.acquire(), false);
});

test("digest is accepted at equal rev, ignored when lower, and never advances the gate", async () => {
  const { h, ws } = v2Ready();
  ws.receive({ event: "hello", data: { rev: 10, epoch: 1, roles: [{ id: "a", name: "A", state: "OFF" }] } });
  const bad = { roles: "0000000000000000" };
  ws.receive({ event: "digest", data: { rev: 9, epoch: 1, hashes: bad } });
  await flush();
  assert.equal(h.fetches.length, 0);
  ws.receive({ event: "digest", data: { rev: 10, epoch: 1, hashes: bad } });
  await flush();
  assert.equal(h.fetches.length, 1);
  h.stateBody = { ...h.stateBody, rev: 10 };
  ws.receive({ event: "digest", data: { rev: 11, epoch: 1, hashes: bad } });
  assert.equal(h.link.heldRev, 50);
  const fresh = v2Ready();
  fresh.ws.receive({ event: "hello", data: { rev: 10, epoch: 1, roles: [] } });
  fresh.ws.receive({ event: "digest", data: { rev: 10, epoch: 1, hashes: { roles: core.fnv1a64("") } } });
  fresh.ws.receive({ event: "state", data: { rev: 11, roles: [] } });
  assert.equal(fresh.h.fullCalls.length, 2);
});

test("next item falls back to the first non-header item after the active one", () => {
  const items = [
    { id: "a", title: "A", itemType: "song" },
    { id: "h", title: "H", itemType: "Header" },
    { id: "h2", title: "H2", itemType: "HEADER" },
    { id: "b", title: "B", itemType: "song" },
  ];
  const snap = { plan: { items, activeItemIndex: 0 }, timer: { isRunning: true } };
  assert.equal(core.nextItemFor(snap).id, "b");
  assert.equal(core.nextItemFor({ plan: { items, activeItemIndex: 3 }, timer: null }), null);
  assert.equal(core.nextItemFor({ plan: { items: [items[0], items[1]], activeItemIndex: 0 } }), null);
  assert.equal(core.nextItemFor(null), null);
});

test("timer.nextItem wins over the plan and null hides the card", () => {
  const items = [{ id: "a", itemType: "song" }, { id: "b", itemType: "song" }];
  const plan = { items, activeItemIndex: 0 };
  assert.equal(core.nextItemFor({ plan, timer: { nextItem: { id: "z", title: "Z" } } }).id, "z");
  assert.equal(core.nextItemFor({ plan, timer: { nextItem: null } }), null);
  assert.equal(core.nextItemFor({ plan, timer: {} }).id, "b");
});

test("next item notes are filtered by the role's categories", () => {
  const item = { notes: { audio: "mute", lights: "dim", video: "" } };
  const role = { assignedNoteCategories: ["lights", "video", "audio"] };
  assert.equal(core.notesForRole(item, role).map((n) => n.category).join(","), "lights,audio");
  assert.equal(core.notesForRole(item, { assignedNoteCategories: [] }).length, 0);
  assert.equal(core.notesForRole(item, null).length, 0);
  assert.equal(core.notesForRole(null, role).length, 0);
});

test("cue word is empty for OFF and unknown states", () => {
  assert.equal(core.cueWordFor("OFF"), "");
  assert.equal(core.cueWordFor(undefined), "");
  assert.equal(core.cueWordFor("STANDBY"), "STANDBY");
  assert.equal(core.cueWordFor("FLASH_GO"), "GO!");
  assert.equal(core.cueWordFor("GO"), "GO!");
});

test("pager never shows CLEAR as a cue word", () => {
  assert.equal(/return "CLEAR"/.test(html), false);
  assert.equal(/id="cueWord"[^>]*>CLEAR/.test(html), false);
});

test("layoutFor picks landscape for wide-but-not-strip viewports", () => {
  assert.equal(core.layoutFor(1920, 1080, "auto"), "landscape");
  assert.equal(core.layoutFor(1024, 768, undefined), "landscape");
  assert.equal(core.layoutFor(1180, 820, ""), "landscape");
  assert.equal(core.layoutFor(844, 390, "auto"), "landscape");
  assert.equal(core.layoutFor(1200, 401, "auto"), "landscape");
  assert.equal(core.layoutFor(390, 844, "auto"), "standard");
  assert.equal(core.layoutFor(800, 800, "auto"), "standard");
  assert.equal(core.layoutFor(1200, 400, "auto"), "lowerthird");
  assert.equal(core.layoutFor(1920, 360, "auto"), "lowerthird");
  assert.equal(core.layoutFor(100, 0, "auto"), "standard");
});

test("layoutFor honours the override", () => {
  assert.equal(core.layoutFor(390, 844, "landscape"), "landscape");
  assert.equal(core.layoutFor(1920, 360, "Landscape"), "landscape");
  assert.equal(core.layoutFor(1920, 1080, "standard"), "standard");
  assert.equal(core.layoutFor(1920, 1080, "full"), "standard");
  assert.equal(core.layoutFor(1920, 1080, "lowerthird"), "lowerthird");
  assert.equal(core.layoutFor(1920, 1080, "third"), "lowerthird");
  assert.equal(core.layoutFor(1920, 1080, "bogus"), "landscape");
});

test("formatLocalTime follows locale and time zone", () => {
  const date = new Date(Date.UTC(2026, 0, 5, 15, 7, 42));
  assert.equal(core.formatLocalTime(date, "en-GB", "UTC"), "15:07");
  assert.match(core.formatLocalTime(date, "en-US", "UTC"), /^3:07\s?PM$/);
  assert.match(core.formatLocalTime(date, "en-US", "America/New_York"), /^10:07\s?AM$/);
  assert.equal(core.formatLocalTime(date, "de-DE", "Asia/Tokyo"), "0:07");
});

test("formatLocalTime falls back on a bad time zone", () => {
  const date = new Date(Date.UTC(2026, 0, 5, 15, 7, 42));
  assert.equal(typeof core.formatLocalTime(date, "en-US", "Not/AZone"), "string");
  assert.ok(core.formatLocalTime(date, "en-US", "Not/AZone").length > 0);
});

test("msUntilNextSecond aligns to the second boundary", () => {
  assert.equal(core.msUntilNextSecond(1500), 500);
  assert.equal(core.msUntilNextSecond(1999), 1);
  assert.equal(core.msUntilNextSecond(2000), 1000);
  assert.equal(core.msUntilNextSecond(1760000000123), 877);
});

test("countdownEmWidth grows with the digits and the overtime prefix", () => {
  assert.ok(core.countdownEmWidth("10:00") < core.countdownEmWidth("1:10:00"));
  assert.ok(core.countdownEmWidth("10:00") < core.countdownEmWidth("+10:00"));
  assert.equal(core.countdownEmWidth(""), 1);
});

test("note entries: bold category, colon, text on one line, escaped", () => {
  assert.equal(core.noteEntryHTML("Lighting", "warm wash"), "<strong>Lighting:</strong> warm wash");
  assert.equal(
    core.noteEntryHTML("A<b>", `x & "y" <script>'z'</script>`),
    "<strong>A&lt;b&gt;:</strong> x &amp; &quot;y&quot; &lt;script&gt;&#39;z&#39;&lt;/script&gt;"
  );
});

test("projected length formats m:ss and h:mm:ss over the threshold", () => {
  assert.equal(core.formatProjectedLength(0, 5400), "0:00");
  assert.equal(core.formatProjectedLength(65, 5400), "1:05");
  assert.equal(core.formatProjectedLength(5399, 5400), "89:59");
  assert.equal(core.formatProjectedLength(5400, 5400), "1:30:00");
  assert.equal(core.formatProjectedLength(3725, 3600), "1:02:05");
  assert.equal(core.formatProjectedLength(7200, null), "120:00");
  assert.equal(core.formatProjectedLength(-5, 3600), "0:00");
});

test("clock slot: cue word replaces the clock while STANDBY or GO", () => {
  assert.deepEqual({ ...core.clockSlotFor("STANDBY") }, { mode: "cue", word: "STANDBY" });
  assert.deepEqual({ ...core.clockSlotFor("FLASH_GO") }, { mode: "cue", word: "GO!" });
  assert.deepEqual({ ...core.clockSlotFor("OFF") }, { mode: "clock", word: "" });
  assert.deepEqual({ ...core.clockSlotFor(undefined) }, { mode: "clock", word: "" });
});

test("fitScale keeps full size when content fits", () => {
  assert.equal(core.fitScale((k) => 100 * k, 100, 0.3), 1);
});

test("fitScale shrinks to the largest scale that fits", () => {
  const k = core.fitScale((s) => 200 * s, 100, 0.3);
  assert.ok(k <= 0.5 && k > 0.49);
});

test("fitScale never goes below the floor", () => {
  assert.equal(core.fitScale((s) => 1000 * s, 100, 0.3), 0.3);
});

test("fitScale treats infinite measures as not fitting", () => {
  const k = core.fitScale((s) => (s > 0.6 ? Infinity : 10), 100, 0.25);
  assert.ok(k <= 0.6 && k > 0.59);
});

test("bottomRowMode picks message, both, one card, or none", () => {
  assert.equal(core.bottomRowMode(true, true, true), "message");
  assert.equal(core.bottomRowMode(true, false, false), "message");
  assert.equal(core.bottomRowMode(false, true, true), "both");
  assert.equal(core.bottomRowMode(false, true, false), "left");
  assert.equal(core.bottomRowMode(false, false, true), "right");
  assert.equal(core.bottomRowMode(false, false, false), "none");
});

test("parseCueDisplay accepts outline, full and fullscreen", () => {
  assert.equal(core.parseCueDisplay("outline"), "outline");
  assert.equal(core.parseCueDisplay("Full"), "full");
  assert.equal(core.parseCueDisplay("fullscreen"), "full");
  assert.equal(core.parseCueDisplay("full-screen"), "full");
  assert.equal(core.parseCueDisplay("bogus"), null);
  assert.equal(core.parseCueDisplay(""), null);
  assert.equal(core.parseCueDisplay(null), null);
  assert.equal(core.parseCueDisplay(undefined), null);
});

test("cueDisplayFor prefers the query, then storage, then outline", () => {
  assert.equal(core.cueDisplayFor("full", "outline"), "full");
  assert.equal(core.cueDisplayFor("outline", "full"), "outline");
  assert.equal(core.cueDisplayFor(null, "full"), "full");
  assert.equal(core.cueDisplayFor("bogus", "fullscreen"), "full");
  assert.equal(core.cueDisplayFor("bogus", "bogus"), "outline");
  assert.equal(core.cueDisplayFor(null, null), "outline");
  assert.equal(core.cueDisplayFor(undefined, undefined), "outline");
});

test("layoutFor maps portrait to the framed standard layout", () => {
  assert.equal(core.layoutFor(1920, 1080, "portrait"), "standard");
  assert.equal(core.layoutFor(390, 844, "auto"), "standard");
  assert.equal(core.layoutFor(844, 390, "auto"), "landscape");
});

test("every element id the page script looks up exists in the markup", () => {
  const wanted = [...html.matchAll(/getElementById\("([^"]+)"\)/g)].map((m) => m[1]);
  const present = new Set([...html.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1]));
  const missing = [...new Set(wanted)].filter((id) => !present.has(id));
  assert.deepEqual(missing, []);
});
