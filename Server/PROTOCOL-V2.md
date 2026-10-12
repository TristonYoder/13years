# Sync Protocol v2

Normative spec for the clock-synchronised, hash-checked, delta-based update protocol. It is additive: a device that does not announce `proto: 2` keeps receiving exactly what it receives today.

## Principles

- The producer's system clock (`Date()`, epoch milliseconds) is the one reference clock. Every other device measures its offset to it and converts every producer timestamp through that offset. A device's own clock is irrelevant once it has an offset.
- The producer pushes only when something changes. Each device runs the timer locally from an anchor, and a small digest every 10 seconds is the consistency check and the heartbeat.
- On any digest mismatch the device asks for a full catch-up (the existing PING which the producer answers with a full PONG). On a reconnect it does the same.

## Capability

- LAN TCP and relay (`CuePacket` JSON): the client's first PING (its catch-up request) carries `"proto": 2`. The producer records the capability per connection. Connections without it receive legacy traffic unchanged (5 s CUE_UPDATE/TIMER_UPDATE). The Bonjour TXT record of pagers is not involved.
- Control API WebSocket: after opening, the client sends `{"id":"…","op":"proto","body":{"version":2}}` and receives `{"id":"…","status":200,"data":{"version":2}}`. Sockets that never send it keep the legacy 1 Hz `timer` events.

## Time synchronisation

`SYNC` (client to producer) and `SYNC_REPLY` (producer to client). All times are epoch milliseconds as JSON numbers.

- CuePacket: `{"type":"SYNC","senderId":"…","t0":<client send>}` answered by `{"type":"SYNC_REPLY","senderId":"…","t0":<echo>,"t1":<producer receive>,"t2":<producer send>}`.
- Control API: socket op `sync` with body `{"t0":…}` and REST `POST /v1/sync` with the same body. Both return `{"t0":…,"t1":…,"t2":…}`.

The client records `t3` (its receive time) and computes `rtt = (t3 - t0) - (t2 - t1)` and `offset = ((t1 - t0) + (t2 - t3)) / 2`, where `offset` is producer time minus local time. It keeps the last 8 samples and uses the sample with the smallest `rtt`. It sends a burst of 5 samples (100 ms apart) on connect, then one every 30 s, and one on every return to foreground or wake. It applies a new offset gradually: if the change is under 20 ms move 25% of the way, otherwise jump. `producerNowMs = localNowMs + offset`.

## Timer anchor

`TIMER_ANCHOR` (producer to v2 clients) replaces the periodic TIMER_UPDATE. It is sent only when the timer changes: start, pause, toggle, reset, adjust or set remaining, item change, PCO live-sync correction, projected/actual change. CuePacket form: `{"type":"TIMER_ANCHOR","senderId":"…","rev":N,"anchor":{…},"timerItem":{…full item…}}`. `anchor` is `null` and `timerItem` absent when there is no active item.

```
anchor: {
  "itemId": string,
  "lengthInSeconds": int,
  "elapsedMs": int,        elapsed time at anchorMs, in ms
  "anchorMs": int,         producer epoch ms at which elapsedMs was true
  "isRunning": bool,
  "isDurationActual": bool
}
```

Clients compute: `elapsedMs(now) = elapsedMs + (isRunning ? producerNowMs - anchorMs : 0)` (never below 0), `elapsedSeconds = floor(elapsedMs(now) / 1000)`, `remainingSeconds = lengthInSeconds - elapsedSeconds`. Digits flip at `anchorMs + k * 1000` on the producer clock, so the producer's own display must flip at those instants too (the producer evaluates its timer at 10 Hz or aligned to the anchor, and only changes the published value when the integer changes).

The Control API timer event and `ActiveTimer` carry the same `anchor` object (additive field, always present when a timer is active). On a v2 socket the `timer` event is sent only on change; on a legacy socket it stays at 1 Hz.

## Cue deltas

`CUE_DELTA`: `{"type":"CUE_DELTA","senderId":"…","rev":N,"cueDeltas":[{"id":"role-id","state":"GO","lastUpdated":<same encoding as CUE_UPDATE roles>}]}`. Sent when only cue states changed. Structural role changes (add, remove, rename, reorder, person name, note categories) still send a full CUE_UPDATE. v2 clients accept both. Control API `state` events are unchanged (they already carry the whole snapshot only when something other than the timer changed).

## Digest

`DIGEST` (producer to v2 clients) every 10 s and immediately after a catch-up reply. CuePacket: `{"type":"DIGEST","senderId":"…","rev":N,"digestMs":<producer now>,"hashes":{"roles":"…","timer":"…","messages":"…"}}`. Control API v2 socket event `digest`: `{"event":"digest","data":{"rev":N,"serverNowMs":…,"hashes":{"roles","timer","plan","messages"}}}`. A v2 client treats any received packet as liveness and considers the producer lost after 25 s of silence (legacy stays 12 s).

A client hashes its local copy of each section the same way and compares. Any difference triggers one catch-up (PING for CuePacket, `GET /v1/state` for the Control API) and the section is replaced. Equal digests need no action.

`rev` is a per-producer counter incremented for every state-changing broadcast. A client ignores a packet whose `rev` is lower than the highest it holds; a lower `rev` from a new connection (producer restart) is accepted after the connect catch-up.

### Hash

FNV-1a 64-bit over the UTF-8 bytes of a canonical string, rendered as exactly 16 lowercase hex digits. Offset basis `0xcbf29ce484222325`, prime `0x100000001b3`, wrapping multiplication. US is byte `0x1F`, RS is byte `0x1E`.

| Section | Canonical string |
| --- | --- |
| `roles` | for each role in array order: `id` US `name` US `state` RS, where `state` is the wire string `OFF`, `STANDBY` or `GO` |
| `timer` | no active item: `none`. Otherwise `itemId` US `lengthInSeconds` US `isRunning` (1 or 0) US `isDurationActual` (1 or 0) US `elapsedMs` US `anchorMs`, taken from the last anchor |
| `messages` | the ids of the 16 newest messages, ordered by `timestamp` descending with ties broken by `id` ascending (byte order), joined with RS (no trailing RS); fewer than 16 messages hash all of them |
| `plan` (Control API only) | for each item in order: `id` US `title` US `lengthInSeconds` US `isDurationActual` (1 or 0) RS, then the decimal `activeItemIndex` |

Integers are base-10 with no padding or sign for non-negative values.

### Test vectors

| Input | Hash |
| --- | --- |
| empty string | `cbf29ce484222325` |
| `a` | `af63dc4c8601ec8c` |
| `foobar` | `85944171f73967e8` |
| roles: `host` US `Host` US `GO` RS `band` US `Band` US `OFF` RS | `aded3b3c0e486304` |
| timer: `item-1` US `300` US `1` US `0` US `120000` US `1760000000000` | `20a9d930a0849518` |
| timer: `none` | `3c0d17bad169557b` |
| messages: `m2` RS `m1` | `dddb4a3dc4d94432` |
| messages with equal timestamps, ids `a` and `b`: `a` RS `b` | `e5e7b9190438f91c` |
| plan: `i1` US `Song` US `300` US `0` RS `i2` US `Sermon` US `2700` US `1` RS `1` | `218cc3247b5ee3f9` |

## Compatibility

All new keys are optional. Old pagers ignore unknown types and keys. A producer sends legacy packets to connections without the capability and v2 packets to those with it. Companion and the web pager upgrade by sending the `proto` op.

## Amendments (v2.1)

These resolve findings from the first review pass. They are additive; a v2.0 peer ignores the new keys.

### Producer epoch

The producer picks a random positive 31-bit integer `epoch` when it starts and puts it in every v2 packet it sends (`PONG`, `TIMER_ANCHOR`, `CUE_DELTA`, `DIGEST`, `SYNC_REPLY`) and in the Control API v2 events `hello`, `timer` and `digest` (inside `data`). A client remembers the last `epoch`. A different `epoch` means the producer restarted: the client discards its held anchor, `rev` gate and clock samples, bursts a sync, and sends one catch-up PING. A v2 client that receives a legacy `CUE_UPDATE` or `TIMER_UPDATE` that has no `rev` from a producer it believes is v2 sends one catch-up PING (at most one per 5 s).

### Capability detection

A client marks the producer as v2 only after receiving a `PONG` with `rev`, a `TIMER_ANCHOR`, `CUE_DELTA`, `DIGEST`, or a `SYNC_REPLY` addressed to it. A `PING`, `SYNC` or `proto` field seen on a packet from another peer never marks the producer as v2.

### Addressing

`SYNC_REPLY` and the catch-up `PONG` (and the `TIMER_ANCHOR` and `DIGEST` sent with it) carry `"to": "<requester senderId>"`. A pager ignores a packet whose `to` is present and not its own `senderId`. Packets without `to` are for everyone.

### Catch-up PONG

A v2 `PONG` carries `rev`, `proto: 2`, `epoch`, and at most the 20 newest messages (the ordering rule above). A v2 client replaces its message list with the PONG's list. Producers must not send more than 4096 bytes of JSON in a PONG to a v2 peer; drop the oldest messages first.

### Clock samples

Each sample stores its local monotonic receive time. Samples older than 90 s are ignored. On a system clock change, wake from sleep, reconnect, or producer epoch change, all samples are cleared and a burst is sent. If a fresh sample's offset differs from the held best offset by more than `max(50 ms, 2 * rtt)`, all older samples are discarded. A computed `rtt` below 0 (millisecond rounding) is treated as 0. A reply with `rtt` above 10 s is ignored. A client whose local clock is epoch-based also ignores an offset beyond one day; a client whose local clock is a monotonic counter (such as the ESP32, whose offset is about the producer's epoch time) skips that check and instead ignores a sample whose offset differs from the held best by more than one hour. A client sends the first burst on connect over any path, and when it receives its first v2 packet while it has no offset; it does not discard samples because the LAN link dropped while a relay link is up.

### Ordering and bounds

`CUE_UPDATE`, `CUE_DELTA`, `TIMER_ANCHOR` and `MESSAGE`-carrying state packets are accepted only when `rev` is strictly greater than the held `rev`. `DIGEST` carries the producer's current `rev`, so it is accepted when `rev` is greater than or equal to the held `rev` (it is used only for verification and never advances the gate past the highest applied packet; a digest with a lower `rev` than held is ignored). A `PONG` rebases the gate. A packet whose `rev` exceeds the held `rev` by more than 1,000,000 is ignored unless its `epoch` changed or it is a `PONG`. Anchor values outside these ranges are ignored: `lengthInSeconds` 0 to 604800, `elapsedMs` 0 to 604800000.
