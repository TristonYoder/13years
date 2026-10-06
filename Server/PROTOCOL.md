# Realtime protocol: relay vs. LAN

13 Years already has a working local-network protocol — point-to-point TCP
over Bonjour discovery (service `_13years._tcp`, JSON `CuePacket`s, see
`Sources/Shared/Services/LANUnicastServer.swift` and `LANUnicastClient.swift`).
This relay exists for exactly one case that protocol can't cover: **the
Producer and a Pager aren't on the same LAN.**

The design goal: the most real-time, least data-impacting connection possible. The producer does
all the heavy lifting; the server only handles auth and proxying. Everything below follows from that.

## Transport: WebSocket, not polling

- **WebSocket (`wss://`) over TLS**, one persistent connection per device.
  A poll loop (even a fast one) trades latency for simplicity — every poll
  either wastes a round trip finding nothing new, or waits up to the poll
  interval before it can carry good news. A push-based WS connection has
  neither problem: a cue lands the instant it's sent.
- **Not WebRTC DataChannels.** True peer-to-peer would take the server
  *out* of the data path entirely (it'd only do SDP/ICE signaling) — even
  less server load than a relay. But the server's job is to *proxy* realtime data, not just introduce two peers and step
  aside — and P2P also fights NAT/firewall traversal on venue Wi-Fi in a way
  a plain outbound WS connection never has to. A relay is the right shape
  for "auth & proxy."

## Framing: reuse `CuePacket` verbatim, as binary frames

- The relay never parses a message — see `rooms.js`'s `relay()`. It reads
  `Authorization` once, at the handshake, and after that just forwards
  whatever bytes arrive to whoever else is in the room. This is what makes
  "server should only handle auth & proxy" literally true: the Producer can
  change `CuePacket`'s shape tomorrow and this server needs zero changes.
- Send `CuePacket.encode()`'s JSON bytes as a **binary** WS frame (not a
  text frame). Same bytes either way, but it sidesteps UTF-8 validation on
  every hop and matches how the LAN TCP transport (`LANUnicastServer`) already
  treats the wire format — one `CuePacket ↔ Data` codec for both transports,
  no transport-specific serialization to maintain.
- **No compression** (`permessage-deflate` off). A `CuePacket` is a couple
  hundred bytes; deflate's per-message context/flush overhead costs more
  in CPU and latency than it saves in bytes at that size. Compression pays
  for itself on large, repetitive payloads — this isn't one.
- **No batching/coalescing.** Forward each packet the moment it arrives.
  Buffering to send fewer, bigger frames trades latency for a marginal
  reduction in per-frame overhead (2–14 bytes) that doesn't matter at this
  message rate.

## Liveness: WebSocket ping/pong, not an app-level heartbeat

`index.js` pings every open socket every 30s and terminates one that didn't
pong the last cycle (`ws.isAlive`). Ping/pong is a 2-byte control frame the
protocol already gives you for free — reinventing this with a JSON
`{"type":"heartbeat"}` message every N seconds would cost real bandwidth on
every connected device, for a problem the transport already solved.

## What the server deliberately does NOT do

This is the "producer does the heavy lifting" half of the design:

- **No cue state.** The relay never stores a "last known packet" to hand a
  late-joining device — that would mean the server understanding and
  owning state, which is exactly what it shouldn't do. A Pager that joins
  mid-service just waits for the Producer's next broadcast. `CueEngine`
  already re-broadcasts the running timer every 5 elapsed seconds
  (`tickTimer()` in `CueEngine.swift`), so the wait is bounded and short —
  the sync behavior a newly-connected LAN pager already gets today.
- **No database, no file writes, no `.env`.** Two optional env vars
  (`PORT`, `PLOTIPHAR_API_BASE`), both with defaults. Restarting the
  process loses nothing that mattered — every room is rebuilt the instant
  its devices reconnect.
- **No per-message auth check.** Bearer token is checked once, at the
  WebSocket handshake (`httpServer.on('upgrade', ...)` in `index.js`) —
  the *only* outbound call this server ever makes, to
  `GET {PLOTIPHAR_API_BASE}/api/organizations`, reusing the exact session
  the pairing flow already produces (`resolveOrgIdForToken` in `auth.js`).
  A short in-memory cache (60s) avoids re-checking on every reconnect, but
  losing that cache costs one extra request, not correctness.

## Room model

Two devices are relayed to each other iff their Bearer tokens resolve to
the same `orgId` via that one call to plotiphar.com. No separate
"pairing code" concept on the relay side — the org boundary you already get
from signing in to Plotiphar *is* the isolation boundary here.
