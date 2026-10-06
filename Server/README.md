# 13 Years Relay

A dumb WebSocket relay: authenticate a connection against plotiphar.com,
then forward every message it sends to every other device signed into the
same Plotiphar org. Nothing else. See [PROTOCOL.md](PROTOCOL.md) for why
it's built this way.

- **State**: none. No database, no disk writes, no `.env` file.
- **Config**: two optional env vars, both defaulted —
  `PORT` (default `8080`) and `PLOTIPHAR_API_BASE`
  (default `https://plotiphar.com`).
- **Auth**: every connecting client presents its own Plotiphar session
  token (the one it already got from device pairing —
  `PlotipharPairingClient` in the app) as `Authorization: Bearer <token>`
  on the WebSocket handshake to `/relay`. The server asks plotiphar.com who
  that is; there's no separate server-side secret to configure.

## Run it

```bash
npm install
npm start          # listens on :8080
```

```bash
npm test           # unit tests for auth.js + rooms.js (no network)
```

## Endpoints

- `GET /healthz` — plain JSON `{"status":"ok","rooms":<n>}`, for container
  health checks / load balancer probes.
- `WS /relay` — the actual relay. Requires `Authorization: Bearer <token>`
  on the upgrade request; an invalid or missing token gets a real HTTP 401
  at the handshake, not a WS connection that immediately closes.

## Deploy

### Docker (plain)

```bash
docker build -t thirteenyears-relay .
docker run -p 8080:8080 thirteenyears-relay
```

or `docker compose up`.

### Nix (reproducible image)

```bash
nix build .#docker
docker load < result
docker run -p 8080:8080 thirteenyears-relay:latest
```

`flake.nix` targets `aarch64-linux` by default (cheap ARM VPS / Graviton / a Pi next to the console).
Change `system` in `flake.nix` if your host is `x86_64-linux`, and
regenerate `npmDepsHash` if `package-lock.json` changes:

```bash
REV=$(jq -r '.nodes.nixpkgs.locked.rev' flake.lock)
nix run "github:NixOS/nixpkgs/$REV#prefetch-npm-deps" -- package-lock.json
```

## What the app needs to point at this

Nothing yet — `PlotipharProxyClient`/the app-side relay client is a
separate piece of work from this server. This repo is the "auth & proxy"
half of the DoD; wiring the Producer/Pager apps to actually dial `/relay`
when they're off-LAN is next.
