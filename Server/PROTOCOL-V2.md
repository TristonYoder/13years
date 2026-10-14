# Sync Protocol v2

Normative spec for the clock-synchronised, hash-checked, delta-based update protocol. It is additive: a device that does not announce `proto: 2` keeps receiving exactly what it receives today.

## Principles

- The producer's system clock (`Date()`, epoch milliseconds) is the one reference clock. Every other device measures its offset to it and converts every producer timestamp through that offset. A device's own clock is irrelevant once it has an offset.
- The producer pushes only when something changes. Each device runs the timer locally from an anchor, and a small digest every 2 seconds is the consistency check and the heartbeat.
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

`DIGEST` (producer to v2 clients) every 2 s and immediately after a catch-up reply. CuePacket: `{"type":"DIGEST","senderId":"…","rev":N,"digestMs":<producer now>,"hashes":{"roles":"…","timer":"…","messages":"…"}}`. Control API v2 socket event `digest`: `{"event":"digest","data":{"rev":N,"serverNowMs":…,"hashes":{"roles","timer","plan","messages"}}}`. A v2 client treats any received packet as liveness and follows the signal thresholds of the v2.4 amendment.

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

## Next item (v2.2)

Pagers show a second card with the next item. The producer adds an optional `nextItem` to the packets that carry the active timer item: v2 `TIMER_ANCHOR`, the v2 catch-up `PONG`, and the legacy `CUE_UPDATE`, `TIMER_UPDATE` and `PONG`. It is `null` or absent when there is no next item.

```
nextItem: {
  "id": string,
  "title": string,
  "itemType": string,
  "lengthInSeconds": int,
  "notes": { "<category>": "<text>" }
}
```

- It is the first non-header item after the active one. Header items are never "next".
- `notes` holds only the categories assigned to at least one role, so the packet stays small; a pager shows the notes for its own role's categories.
- When the next item changes without the timer changing (a plan edit, a reorder), the producer sends a new `TIMER_ANCHOR` (with a new `rev`) carrying the new `nextItem`.
- The 4096-byte limit on a v2 `PONG` still holds: drop the oldest messages first, then the longest note values of `nextItem`.
- `nextItem` is not part of any digest hash. A pager that misses a change recovers on the next catch-up.
- Control API: `timer.nextItem` carries the full next item (all notes) in the snapshot and the `timer` event, so clients that already hold the plan need no extra data.

## Pager presentation rules

- A role whose cue is `OFF` shows no cue word; the layout keeps its place. `STANDBY` and `GO` show as before.
- The next-item card sits below the current-item card: the title in uppercase, then the notes for the pager's role categories; no card when there is no next item. Compact layouts (lower third, the ESP32 panel) may omit or shrink it.

## Landscape layout ("timer first")

Used by the Swift pager (iPad, Apple TV, any window wider than tall) and the web pager (`layout=auto` when the viewport is wider than tall and its aspect ratio is under 3:1; `?layout=landscape` forces it; wider than 3:1 is still the lower third). All sizes are fractions of the shorter side `s` of the pager window so it scales from an iPad to a TV.

- Ground and frame: near-black ground (`#111114`) inside a frame in the cue colour (STANDBY yellow, GO green) of thickness `max(14 px, 0.022 s)`. The frame's INNER corners are rounded with radius `max(18 px, 0.04 s)`; the outer edge follows the window. With no cue the frame stays at the same thickness in a barely visible neutral so the layout never shifts.
- Top-left slot (far left, inside the frame): shows the local time while there is no cue and is REPLACED by the cue badge while the cue is `STANDBY` or `GO`. The clock is styled like the web pager's lower-third clock: the device's local time of day with seconds (`h:mm:ss`, locale AM/PM style), heavy weight at about `0.075 s`, near white, left aligned, with a small letter-spaced `LOCAL TIME` caption beneath, updating on the second boundary. The badge is a filled rounded rectangle in the cue colour with dark text and the cue word (`GO!`, `STANDBY`) about `0.11 s` high, heaviest weight. The slot reserves the height of the badge and the width of the widest word (`STANDBY`) so nothing moves when it switches.
- Top right: the connection state (dot and short text) above the role chooser, which is a visible dropdown chip with a chevron. The person's name (`FOR: PERSON`) is not shown.
- Centre: the current item title in uppercase (about `0.05 s`, up to two lines), the countdown (about `0.32 s`, heaviest weight; negative values keep the `+` prefix), then `PROJECTED` or `ACTUAL` (about `0.035 s`, letter-spaced, dimmed but clearly legible from a distance). It is positioned from the window alone and must not move between cue states.
- Bottom row: two cards of equal width (half the width minus the gap) that size to their content: no reserved or minimum height, so nothing takes more space than its text needs. The two cards share the taller card's height. A card is capped at `0.28 s` tall and its text scales down to fit that cap, never overflowing or clipping. Left, the current item's notes; right, the next item. The next-item card's first row holds the item title in uppercase at about `0.035 s` with the item's projected length (`m:ss`, or `h:mm:ss` over the hour threshold) right aligned in the same row; then its notes. A card with nothing to show is omitted and the other takes the full width (no placeholder, no empty space).
- Standing message: while a message is standing, it REPLACES the bottom row. It is a full-width yellow panel with dark text, sized for a distant screen like the lower third: the message at about `0.06 s` to `0.07 s` (scaling down to fit at most three lines within `0.25 s` of height, so it never covers the `PROJECTED`/`ACTUAL` tag under the countdown), with the sender in a small caption, until it is dismissed or expires; then the cards return. It never overlays or covers the cards.

## Cue replaces the clock

In every layout that shows a local-time clock (landscape, and the lower third), the clock slot is taken over by the cue word while the cue is `STANDBY` or `GO`, and returns when the cue clears.

## Note format

Everywhere notes are shown (every layout), each note is one entry: the category name in bold followed by a colon, then the text on the same line, wrapping as needed, e.g. **Lighting:** warm wash, slow fade. One entry per category assigned to the pager's role; nothing for empty notes.

## Portrait layout ("framed")

Used by the Swift pager and the web pager when the window is taller than wide (the web pager's standard layout). Sizes are fractions of the window width `w`.

- Ground and frame: same as the landscape layout (near-black ground, a frame in the cue colour of thickness `max(10 px, 0.022 w)` with rounded inner corners, a barely visible neutral frame with no cue so nothing shifts).
- Top row (fixed height): left slot is the local-time clock (lower-third style, `LOCAL TIME` caption) while there is no cue and is replaced by the cue badge (`GO!`, `STANDBY`) while the cue is active, reserving the widest word so nothing moves; right column is the connection state above the role chooser (dropdown chip with chevron). No `FOR: PERSON`.
- Current item card, vertically centred in the space between the top row and the bottom stack: the item title in uppercase, the countdown (about `0.2 w`, heaviest weight, `+` prefix in overtime), the `PROJECTED`/`ACTUAL` tag, then the current item's notes inside the same card below a hairline divider (one entry per assigned category in the note format). Heading items show the title only.
- Bottom stack, aligned to the bottom edge: the Next card (item title in uppercase with its projected length right aligned in the same row, then its notes; omitted when there is no next item), and below it, when a message is standing, the message panel (full width, yellow, dark text, about `0.055 w` scaling down to fit at most four lines within `0.34 w`, sender caption). The message pushes the Next card up; it never overlays or replaces it.

## Cue display setting

A setting chooses how the cue is shown, in portrait and landscape:

- `outline` (default): the framed look above.
- `fullscreen`: no frame; the whole window is filled with the cue colour (STANDBY yellow, GO green) and the cards become dark translucent panels (`rgba(0,0,0,0.28)`). The top-left cue word is plain large text in the dark cue-contrast colour, without the pill. With no cue the ground is the near-black ground.

The Swift pager stores it in app settings (`pagerCueDisplay`: `outline` or `fullscreen`) with a control in its settings screen. The web pager reads `?cue=outline|full`, remembers the last choice in `localStorage` (`pagerCueDisplay`), and exposes a control in its settings sheet (the gear). The ESP32 panel is unchanged.

## Producer time zone (v2.3)

A pager with no wall clock of its own (the ESP32) shows the local time of day as the producer's time (its synced offset applied to its monotonic counter) plus the producer's UTC offset. The producer therefore adds an optional integer `utcOffsetSeconds` (its current offset from UTC including daylight saving, e.g. `-14400`) to `TIMER_ANCHOR` and to every `PONG` (and to the legacy `TIMER_UPDATE`). Every pager's "LOCAL TIME" shows the producer's wall clock: device time plus the Sync v2 clock offset (the same offset the timer uses; the `sync` socket op on the Control API, including a remote mirror), rendered in the producer's `utcOffsetSeconds` (the Control API state carries `utcOffsetSeconds` as well). The displayed second flips at the local instant of the next whole producer second, not the device's own second. Before the first sync, or when no UTC offset is known, a pager falls back to its own clock and time zone. A producer shows its own local time.

## ESP32 panel

The 240 by 320 panel follows the portrait framed layout and the cue display setting with the same structure (frame or full colour, clock/cue slot top left, connection status above the role chooser top right, current item card with notes centred, Next card then the message panel at the bottom), scaled to the fonts available on the device. The clock is `h:mm:ss` with AM/PM. The cue display setting is stored in the device's non-volatile preferences and can be changed on the device.

## Connection notice, footer icons and extended disconnect

- Connection notice: the connection state text ("Live — <producer>") is no longer shown on the main pager screens (portrait, landscape, the ESP32 panel). The top-right column holds only the role chooser. The connection state, the producer name and, where available, the clock sync quality appear in the settings screen (the web pager's settings sheet, the Swift pager's settings screen, the ESP32's role picker screen). A lost connection is still always visible on the main screens: the existing "No connection — last update N s ago" strip (web) or equivalent keeps showing, and the extended-disconnect rule below applies.
- Header icons (Swift and web pagers): the chat button and the settings button are icon-only buttons (chat bubble and gear, accessible names "Messages" and "Settings", at least 44 pt tall) in a row directly BELOW the role chooser in the top-right column. The row is exactly as wide as the role chooser dropdown, and the buttons share that width equally (a single remaining button takes the whole width). There is no footer strip: nothing is reserved at the bottom edge, so the bottom row (cards, message) runs to the bottom of the frame. The icons never move the centre block. In portrait the same rule applies to the top-right column. The lower third keeps its own controls.
- Extended disconnect: when no packet has arrived from the producer for 20 seconds, every full layout (portrait and landscape) replaces its content with the logo animation: the animated stoplight mark and the text "Waiting for Producer…" on the near-black ground (the same loader the pager shows before it first connects), until the connection returns, when the normal screen comes back. From 5 to 20 seconds the last known screen stays up, greyed and dimmed (v2.4), with the "Reconnecting" strip.

## Signal loss and heartbeat (v2.4)

Every pager (iOS, Mac, tvOS, watch, web, ESP32) uses the same signal-loss behaviour, measured as time since the last accepted producer packet on a monotonic clock. Any producer packet counts: DIGEST, PONG, SYNC_REPLY, TIMER_ANCHOR, CUE_DELTA, legacy updates, or on the watch and the web fallback a successful state poll.

- Heartbeat: the producer sends `DIGEST` (LAN and relay) and the Control API v2 socket sends the `digest` event every 2 seconds. Legacy peers are unchanged (CUE_UPDATE and TIMER_UPDATE every 5 seconds).
- Live: under 5 seconds of silence.
- Stale: from 5 seconds. The display greys and dims. The timer keeps counting from its anchor and the cues stay visible, with a small "Reconnecting" tag. A client talking to a legacy producer (5-second beat) uses 8 seconds so the beat does not flicker the display.
- Lost: from 20 seconds. The connection-error screen ("Waiting for Producer…") replaces the content. A client also forces a reconnect at this point.
- Recovery is immediate on the next producer packet. A socket disconnect does not jump to lost; it follows the same clock, because a reconnect normally lands inside the window.
- A producer (master) is always live.
- Bandwidth: a digest packet is about 60 bytes, so an idle pager receives roughly 30 bytes per second.

## Standing message on pagers (v2.3)

Every pager (Swift, web, ESP32) derives the standing message the same way from the message list, newest first:

- It is the newest message that has no `senderRoleId` (a Producer message) and is addressed to the pager's role or to everyone (`targetRoleId` absent). Messages from roles, including the pager's own, never stand.
- It is cleared when a message sent by the pager's own role (`senderRoleId` equal to its role) is as new as or newer than it. A newer Producer message after that stands again.

Role messages remain in the thread; this rule only decides what a pager screen shows.

## Lower third on Swift pagers (v2.3)

The Swift pager offers the lower third described for the web pager: one strip with the clock (replaced by the cue word while STANDBY or GO), the element name and the countdown with its PROJECTED/ACTUAL tag; a standing message replaces the clock and the title. It is used when the viewer chooses Lower third in settings, or automatically when the window is at least 3:1 wide. Tapping the strip reveals the role chooser, messages and settings for six seconds. Not offered on tvOS.


## Assigning a pager to a producer (ASSIGN_PRODUCER)

A producer (or any app) can point a pager at a clock server with one UDP datagram to the pager's port 13381:

```json
{"type":"ASSIGN_PRODUCER","host":"192.168.1.20","port":13380,"mode":"introducer"}
```

- `host` (required): IPv4 address or hostname of the server the pager should connect to. Any well-formed host is accepted, public or private.
- `port` (optional): the pager TCP port, 1-65535, default 13380. A packet with a port outside that range is ignored.
- `mode` (optional): `"introducer"` marks a packet whose `host` is not the sender, as when a Producer in a remote session introduces a pager to the remote clock server. Without it the pager only accepts a packet whose `host` equals the datagram's source address, so a third party cannot redirect it.

The pager remembers the host and port and reconnects to them until it is told to forget the assignment. A Producer sends its own address (no `port`, no `mode`) when it serves the pager itself, including a remote session in Local Relay mode; in Introducer or Control Only mode it sends the remote server's IPv4, its `network.lanPort`, and `"mode":"introducer"`.
