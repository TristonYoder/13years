<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="stoplight-13-mark-dark.png">
    <img src="stoplight-13-mark-light.png" width="96" alt="The 13 Years mark: a traffic-light column of red, amber and green dots beside a 3">
  </picture>
</p>

<h1 align="center">13 Years</h1>

<p align="center"><b>Cue lights for whoever’s on the floor. No headset needed.</b></p>

<p align="center">The producer calls it. Every role sees STANDBY, GO, a synced countdown and their own notes, on the phone already in their pocket.</p>

<p align="center">
  <a href="https://testflight.apple.com/join/sbn2ecQQ"><img src="https://img.shields.io/badge/Join_the_beta-Pager_on_TestFlight-26C759?style=for-the-badge&labelColor=1E1F23" alt="Join the beta: Pager on TestFlight"></a>
  <a href="https://github.com/TristonYoder/13years/releases/latest"><img src="https://img.shields.io/badge/Producer_for_Mac-GitHub_Releases-F5F5F3?style=for-the-badge&labelColor=1E1F23" alt="Producer for Mac on GitHub Releases"></a>
  <a href="https://13years.app"><img src="https://img.shields.io/badge/13years.app-1E1F23?style=for-the-badge" alt="13years.app"></a>
</p>

<p align="center"><sub>No account. No analytics. Nothing sent to us. Open source under AGPL-3.0.</sub></p>

<p align="center">
  <img src=".github/readme/producer-pagers.png" width="620" alt="Producer for Mac, Pagers view: the current item None Like Jesus with a 05:42 clock, STANDBY, GO and CLEAR buttons, role cards for Host, Band, Backstage and Lighting, and a live preview of the Host pager.">
  <img src=".github/readme/pager-standby.png" width="178" alt="The Pager for the Host role: STANDBY in amber, None Like Jesus with a countdown, and Host // Worship Close coming up next.">
</p>

## From the booth

The Producer runs on a Mac or iPad, or headless on a server. It holds the plan, the clock and every role, and it shows you exactly what each pager is showing.

- **Standby. Go. Clear.** Big buttons for the call. Arrows step through the plan; play starts the item’s clock.
- **Every role, one tap.** Cue the host, the band, backstage or lighting together or one at a time, and see who’s on standby.
- **See their screen.** A live preview of any role’s pager, so you know what they’re looking at.

## Everyone gets a pager

Pick a role (host, tech, band, anything) and the pager shows only what that role needs, readable from across the stage: its cue state, the active item with its countdown, what’s next, notes, and messages. Portrait, landscape, or a lower third over your own screen.

<table>
  <tr>
    <td align="center" valign="bottom"><img src=".github/readme/pager-go.png" width="160" alt="Pager in portrait on iPhone, showing GO in green with the item and its countdown."></td>
    <td align="center" valign="bottom"><img src=".github/readme/pager-tv-go.png" width="340" alt="Pager on Apple TV, showing GO in green with a large countdown and the next item."></td>
    <td align="center" valign="bottom"><img src=".github/readme/pager-lower-third.png" width="260" alt="Pager in the lower-third layout: a slim GO and countdown bar inside a green frame."></td>
  </tr>
  <tr>
    <td align="center"><b>Phone or iPad</b><br><sub>STANDBY and GO in big colour</sub></td>
    <td align="center"><b>Apple TV or Mac</b><br><sub>for the green room or a confidence monitor</sub></td>
    <td align="center"><b>Lower third</b><br><sub>cue and countdown, out of the way</sub></td>
  </tr>
</table>

Crew who would rather not hold a phone on stage can use a small dedicated pager built on an ESP32 board (see [`Hardware/esp32`](Hardware/esp32/README.md)).

## The plan you already built

<img src=".github/readme/producer-runsheet.png" alt="Producer run sheet: grouped items with start times, planned and elapsed time and drift, the current item highlighted, and a Now and Next panel with role notes.">

The producer’s run sheet pulls everything it can from a Planning Center plan: item descriptions, songs with key, BPM, meter and sequence, media, and per-time exclusions. It has a list and (on Mac) a customizable table view, projected start times and totals, and a plan panel with notes, times and team (roles can link to a team position). It records actual lengths per event, lets you skip items or rehearse without logging, and can save actual lengths back to the plan. Each role chooses which item details its pagers show. Attachments and lyric or chord charts open on demand from the producer without being sent to pagers. Planning Center is optional; you can build a plan by hand too.

## Say it without the headset

<img src=".github/readme/producer-messages.png" alt="Producer Messages view: a thread with the Band role, including a high-priority message to stretch the last chorus.">

Message one role or everyone. Pagers show it on screen, the reply comes back to the booth, and a high-priority message doesn’t wait for someone to look down.

## Set up before doors

🔴 **Run the Producer** on a Mac or iPad, or a hosted headless Producer your team keeps on.<br>
🟡 **Open a Pager** on an iPhone, iPad, Apple TV, Mac or ESP32 on the same network. It finds the Producer, or type `host:13380`.<br>
🟢 **Pick a role.** Host, tech, band, anything. STANDBY, GO, the countdown and your notes, just for you.

**Runs on** iPhone · iPad · Apple TV · Mac · ESP32 <sub>(pager)</sub> · Linux <sub>(hosted Producer)</sub>

## Nothing to sign up for

No account. No analytics. No tracking. No ads. No developer server. Cue and message data stays between your devices and your Producer; see the [privacy policy](https://13years.app/privacy/).

## Doors in eight. Get it on the floor.

The Pager is heading to the App Store. Until then, the public beta is open on [TestFlight](https://testflight.apple.com/join/sbn2ecQQ). The Producer for Mac and the Mac Pager are disk images on [GitHub Releases](https://github.com/TristonYoder/13years/releases/latest).

---

## Components

| Path | What it is |
| --- | --- |
| `Sources/ProducerMac`, `Sources/ProducerIOS` | Producer apps (macOS, iPadOS/iOS). Run the plan, fire cues, serve the control API. |
| `Sources/PagerIOS`, `Sources/PagerTV`, `Sources/PagerMac`, `Sources/ProducerWatch` | Pager apps (iOS/iPadOS, tvOS, macOS, watchOS). |
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

Register your own OAuth application at Planning Center (redirect URI `thirteenyears://oauth/callback`, scope `services`). Without a client ID the app builds, but PCO sign-in reports that none is configured. Bundle identifiers use the `app.13years` prefix in `project.yml`; change them to build under your own account.

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
