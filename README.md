# 13 Years

Cue lights and pagers for live production teams. A producer runs the show from a Mac or iPad, pulling the plan from Planning Center, and every role on the team (host, tech, band, and so on) gets a pager that shows its cue state, the active item with its countdown, notes, and messages.

## Components

| Path | What it is |
| --- | --- |
| `Sources/ProducerMac`, `Sources/ProducerIOS` | Producer apps (macOS, iPadOS/iOS). Run the plan, fire cues, serve the control API. |
| `Sources/PagerIOS`, `Sources/PagerTV`, `Sources/ProducerWatch` | Pager apps (iOS, tvOS, watchOS). |
| `Sources/Shared` | Models, services and views shared across every app target. |
| `Hardware/esp32` | Firmware for a hardware pager on an ESP32 "Cheap Yellow Display" board. See its [README](Hardware/esp32/README.md). |
| `Server` | Small WebSocket relay for pagers that are not on the producer's LAN. See its [README](Server/README.md) and [PROTOCOL](Server/PROTOCOL.md). |
| `CONTROL-API.md` | HTTP and WebSocket control API (Stream Deck, Companion, QLab, scripts). |

On a shared LAN, devices find each other over Bonjour (`_13years._tcp`) and talk point-to-point over TCP.

## Building

The Xcode project is generated from `project.yml` and is not checked in.

```bash
brew install xcodegen
xcodegen generate
open ThirteenYears.xcodeproj
```

Signing and the Planning Center OAuth client ID are not in the repository. `Config/Base.xcconfig` defines them empty and includes an optional, git-ignored `Config/Local.xcconfig`:

```
DEVELOPMENT_TEAM = YOUR_TEAM_ID
PCO_OAUTH_CLIENT_ID = your-planning-center-oauth-client-id
```

Register your own OAuth application at Planning Center (redirect URI `thirteenyears://oauth/callback`, scope `services`). Without a client ID the app builds, but PCO sign-in reports that none is configured. Bundle identifiers use the `dev.7co.13years` prefix in `project.yml`; change them to build under your own account.

CI (`.github/workflows/apple-build.yml`) writes `Config/Local.xcconfig` from two repository secrets:

```bash
gh secret set APPLE_TEAM_ID
gh secret set PCO_OAUTH_CLIENT_ID
```

```bash
cd Server && npm ci && npm test
```

Firmware builds with PlatformIO; see `Hardware/esp32/README.md`.

## Contributing

Pull requests need a signed [CLA](CLA.md); see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Copyright (C) 2026 Triston Yoder. Licensed under the GNU Affero General Public License v3.0 only (`AGPL-3.0-only`); see [LICENSE](LICENSE). Bundled third-party material and its licenses are listed in [NOTICE.md](NOTICE.md).
