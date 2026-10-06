# 13years — ESP32 Hardware Pager

A hardware parallel of the iPhone Host Pager
([`HostPagerView.swift`](../../Sources/Shared/Views/HostPagerView.swift)):
an ESP32 "CYD" (Cheap Yellow Display) board that connects to the same local
TCP-based cue channel the Producer/iOS apps use (discovered via mDNS as
`_13years._tcp`), and reflects this device's assigned role's cue state —
full-screen color, active PCO item + countdown, assigned note category,
message-received indicator — plus an RGB LED visible from across a room and
(once the buzzer arrives) haptic-style buzz patterns matching
[`PagerHaptics.swift`](../../Sources/Shared/Services/PagerHaptics.swift).

Developed and flashed against a real unit (ESP32-D0WD-V3, 4MB flash, ILI9341
240×320 SPI TFT, resistive touch, CH340 USB-UART).

## Layout

```
src/
  main.cpp              top-level state machine, Serial command console
  storage/nvs_store.*    WiFi creds, device id, assigned role, static Producer IP — Preferences/NVS
  net/wifi_manager.*      WiFi join + reconnect-with-backoff
  net/lan_client.*        TCP point-to-point client + mDNS discovery, dispatches CuePackets into cue::Engine
  cue/cue_state.h          CueState enum + colors (mirrors CueState.swift)
  cue/cue_engine.*         parses CuePacket JSON, holds role/timer/message state, local timer ticking
  hw/rgb_led.*             onboard RGB LED, mirrors on-screen cue color
  hw/buzzer.*              buzz patterns mirroring PagerHaptics.swift (placeholder hardware)
  ui/ui.*                  LVGL screens — pager + on-device role picker
```

Structure follows the sibling [`plotiphar-esp32`](../../../plotiphar-esp32)
project (same board family, different product/protocol) — `net/`, `storage/`,
`ui/` split the same way; `cue/` and `hw/` are new to this project's own
protocol and hardware surface.

## Protocol

Speaks a point-to-point TCP protocol — see [`CuePacket.swift`](../../Sources/Shared/Models/CuePacket.swift)
and friends for the canonical schema and [`LANUnicastChannel.swift`](../../Sources/Shared/Services/LANUnicastChannel.swift)
for the Swift side's implementation. Discovery is via mDNS (`_13years._tcp`
service type), with a manually-configured static IP as a fallback for networks
where mDNS is filtered (see `storage/nvs_store.h`'s `getProducerHost()` and the
`producer <ip>|auto` Serial command). This device is always a *client*: it never
acts as the hub (that's whichever app has `isMasterServer = true`), so it never
replies to another peer's `PING` and never broadcasts `CUE_UPDATE` — it
sends exactly one `PING` after connecting, requesting the hub's catch-up
burst (mirrors `CueEngine.swift`'s `requestCatchUp()`).

Self-filtering (dropping this device's own broadcasts) works the same way
the Swift apps' does: a `senderId` generated once from the ESP32's MAC
address, persisted in NVS, compared on every inbound packet.

## WiFi configuration

The normal path is the Producer app over USB — see "Flashing from the
Producer app" above, and it is what the device's own screen tells you to do
when it has no credentials or cannot join the network it has.

Everything below is the manual route. It is fully supported and is what the
app drives underneath, but it is deliberately **not** mentioned on the
device's screen: a serial command needs a terminal, a baud rate and exact
syntax, which is the wrong instruction to give someone holding a 240x320
panel in a building before a service. Reach for it when you are already at a
terminal, debugging, or working without the app.

No captive-portal AP mode in this version — deliberately kept simple for
v1. Configure over USB serial (115200 baud):

```
wifi <ssid> <password>
wifi "Example Network" example-password      # quote an SSID containing spaces
```

Credentials are saved to NVS and connected immediately; they persist across
reboots and reflashes. Other Serial commands (send `help` for the full
list):

```
provision <json>    set ssid/pass/role/producer in one shot — see below
rotate 180|normal   turn the display 180 degrees for upside-down mounting (touch turns with it)
role <id>          assign this pager's role (host, keys, speaker, lead_vocal, producer, ...)
status              device id / role / WiFi+LAN state / active cue+timer/note/message
testpacket <json>   inject a raw CuePacket JSON string directly into the engine — debug aid,
                    bypasses WiFi/network entirely
producer <ip>|auto  override Producer host: <ip> for static IP fallback, or 'auto' to use mDNS discovery
reset               wipe all stored config (WiFi, device id, role, Producer host) and restart
```

## Flashing from the Producer app

The Mac Producer flashes and provisions these boards itself — File ▸ Flash a
Pager (⇧⌘F). It drives the chip's ROM bootloader over USB, writes the merged
image, verifies it by asking the chip for an MD5 of what actually landed in
flash, restarts the board and then hands it Wi-Fi credentials and a role over
the same cable using `provision` below. About 45 seconds end to end.

There is no file picker: **the firmware ships inside the app**, at
`Sources/ProducerMac/Resources/13years-pager-merged.bin`. That is what makes
firmware/protocol compatibility structural rather than remembered — the app
cannot flash a firmware that disagrees with its own `CuePacket` schema,
because the two are one artifact that versions together. It is the same
concern as the Swift/firmware parity rule, enforced by construction instead of
by discipline.

**After changing anything under `src/`, regenerate the bundled image:**

```
Hardware/esp32/tools/build-firmware.py --out Sources/ProducerMac/Resources/13years-pager-merged.bin
```

and commit it alongside the firmware change. CI fails if the firmware sources
move ahead of the committed image, so a stale bundle cannot ship silently.

### `provision` — the machine path

`wifi` and `role` are for a human at a serial monitor. `provision` is for the
Producer app, which drives this port over USB immediately after flashing so a
pager goes from blank to on-network without anyone typing anything:

```
provision {"ssid":"Example Network","pass":"example-password","role":"host","producer":"auto","rotate180":true}
```

`rotate180` is a JSON boolean, not a string — see "Display orientation" below.

Only `ssid` is required. `pass` may be omitted for an open network, and `role`,
`producer` and `rotate180` left out to keep whatever is already stored. Left
out is not the same as `false`: a pager already mounted upside-down must not be
righted by a provision that never mentioned orientation. `producer` takes an IP
or the literal `auto` (mDNS discovery), same as the `producer` command.

It replies with exactly one line, and that line is a contract — everything
else this firmware prints is prose for a human, but these two are meant to be
parsed:

```
[ok] provision {"deviceId":"a4cf1290ab34","ssid":"Example Network","role":"host","producer":"auto"}
[err] provision bad-ssid-length
```

The ok payload is JSON rather than `key=value` pairs for the same reason the
request is: an SSID may contain spaces, so `ssid=Example Network role=host` cannot
be split on whitespace without guessing. Error reasons are single tokens, so
those stay plain.

The error reasons are fixed strings: `malformed-json`, `expected-json-object`,
`missing-ssid`, `bad-ssid-length`, `bad-password-length`, `bad-role`,
`bad-producer-ip`, `bad-rotate180`. Every field is validated before anything is written, so a
rejected `provision` changes nothing rather than leaving the unit on a new
network under an old role. The `deviceId` in the ok line is there so the app
can tell which physical unit it just provisioned without a second round trip —
useful when several are plugged in at once.

JSON rather than positional arguments for a reason the `wifi` command learned
the hard way: SSIDs and passwords contain spaces, quotes and colons. Before
the quoting fix above, `wifi Example Network example-password` silently set the SSID to
`Example` with the password `Network example-password`, and the only symptom was a device
that never joined.

WiFi reconnect uses the same backoff cadence as
[`LANUnicastChannel.swift`](../../Sources/Shared/Services/LANUnicastChannel.swift)'s
connection-retry logic: a quick burst of close-together attempts, then
indefinite slow retries in the background — it never permanently gives up.

### Display orientation

Some units end up mounted with the cable needing to exit the other way — a
stand, a shelf lip, a cable run that only reaches from one side — and a
physically upside-down panel is not something the person mounting it can fix
otherwise. `rotate 180` (or `"rotate180": true` in a `provision`, or the
"Rotate screen 180°" toggle in the Producer's flashing window) turns the
display and touch input together.

Both halves matter. Rotating the display alone would leave the touch
controller reporting taps in the panel's native orientation, so every tap
lands diagonally opposite the finger and the role picker becomes unusable —
a failure that looks like broken touch hardware rather than a mismatched
setting. A 180-degree turn keeps the panel's dimensions, so it takes effect
immediately rather than needing a reboot, and it is stored in NVS so a unit
comes up correctly from its first frame rather than visibly righting itself
partway through boot.

### What the device shows when Wi-Fi is down

Two different screens, because "never configured" and "configured but not
joining" are the same remedy but not the same problem — and the failing case
can name the network, which is usually the whole diagnosis (a typo, the wrong
band, or a pager carried out of range).

| State | Screen |
|---|---|
| No credentials stored | **Not set up yet** — connect to a Mac by USB and open 13 Years Producer, File ▸ Flash a Pager |
| Credentials stored, not joining | **Can't join Wi-Fi**, the SSID it is trying, and a note that it is still retrying |

Neither mentions serial. The firmware never stops retrying in the background
(see `wifi_manager.cpp`), so "still trying" is literally true and is there to
stop anyone power-cycling a device that is already doing the right thing.

## Role selection

`cue::Engine::begin()` seeds the role list with `RoleCue.defaultRoles`'
ids/names (`src/cue/default_roles.h`, mirroring
`Sources/Shared/Models/RoleCue.swift`) at boot, before WiFi/LAN connection
is established — so the pager screen shows a real display name ("Service Host")
from the very first frame, not the bare role id ("host"), and doesn't
have to wait for a `CUE_UPDATE` to arrive (which can be a
while — it only fires on an actual cue-state change, not on a schedule).
The very first real `CUE_UPDATE` replaces this placeholder data with the
Producer's actual role list, same as always.

Tap the "Role: &lt;name&gt;" pill, top-left on the pager screen, to open an
on-device role picker listing whichever role list is currently known
(the seeded defaults, or the Producer's real list once one's arrived).
Selection is persisted to NVS and immediately re-syncs the RGB LED too
(not just the on-screen pill/background, which already refreshes every
frame regardless — see `ui.cpp`'s `onRoleRowClicked`). Also settable via
the `role <id>` Serial command, which does the same LED resync.

**The picker opens automatically every boot**, regardless of whether a
role was chosen on a previous boot — every reboot is a chance the
physical device has been moved to a different role. Cancelling it falls
through to whichever role was already persisted.

## Touch — found on a separate SPI bus, working

Confirmed via Elegoo's own official pinout for this exact product
(E32R28T — wiki.elegoo.com/oshw-parts-&-accessories/esp32-dispaly-introduction):
the resistive touch controller (XPT2046) is wired to its **own SPI bus**,
completely separate from the display's:

| Signal | GPIO |
|---|---|
| SCLK | 25 |
| MOSI | 32 |
| MISO | 39 |
| CS | 33 (active-low) |
| IRQ | 36 (not currently read — polling instead) |

`TFT_eSPI`'s built-in touch support (`tft.getTouch()`) only knows how to
share the display's own SPI bus with a separate CS pin — true on some
board variants, not this one. Using it here was harmless but useless: it
silently toggled the display's clock/data pins, which the real touch
controller was never listening on, so every reading came back a flat,
unchanging zero regardless of touch. Confirmed properly, not guessed at —
a `touchraw` Serial diagnostic (bypassing calibration and the pressure
threshold entirely) showed the flat zero with a human actively touching
the screen during the test, at two different `TOUCH_CS` guesses (33, then
27) before the real, separate-bus explanation was found.

`src/hw/touch_xpt2046.*` drives the real bus directly (the ESP32's second
hardware SPI peripheral, HSPI — the display already owns the other one,
VSPI, via `TFT_eSPI`), reimplementing the standard XPT2046 SPI command
protocol (not something specific to `TFT_eSPI`). **Confirmed working
live**: real varying pressure and coordinates as a finger moved across
the panel, and a real tap on the on-device role picker correctly
registered and changed the selected role.

Raw-to-pixel calibration is currently four fixed constants
(`kRawXMin`/`Max`, `kRawYMin`/`Max` in `touch_xpt2046.cpp`) plus
`SWAP_XY`/`INVERT_X`/`INVERT_Y` flags — not yet a proper interactive
per-unit calibration (unlike the old `TFT_eSPI`-based flow this replaced,
which was interactive but on the wrong bus entirely, so being interactive
didn't help). These are reasonable starting values for this touch panel
class, not yet fine-tuned against exact corner taps. Use `touchraw [ms]`
(default 5000ms) to watch live raw-vs-mapped coordinates while tuning
them if touches land off-target.

## RGB LED

Onboard LED mirrors the on-screen cue color, plus real-time animation, so
the cue is visible from across a room even when the screen isn't:
**Off → LED off. Standby → a slow yellow pulse (red+green mixed,
alternating on/off roughly every 0.9s), held until the state changes
again. Go → green, flashing quickly (roughly every 0.2s) for 5 seconds,
then settling to solid green.** `src/hw/rgb_led.cpp`'s `led::loop()` (a
non-blocking millis()-step scheduler, same idea as `buzzer.cpp`'s pattern
scheduler) drives the animation; `led::setForCueState()` starts it.

### Pins — corrected against Elegoo's official documentation

**Red = GPIO22, Green = GPIO16, Blue = GPIO17, active-LOW** ("common
anode... low level on, high level off" — Elegoo's own wording), per their
official pinout for this exact product (E32R28T,
wiki.elegoo.com/oshw-parts-&-accessories/esp32-dispaly-introduction). A
real 3-channel RGB LED, confirmed by the same source.

This corrects an earlier empirically-derived mapping (GPIO4=green,
GPIO16=blue, no working red channel — found by cycling GPIOs one at a
time with a human watching the physical LED) that was live on a different
physical unit before the official pinout was found. The two don't agree
on which GPIO drives green, or on whether a red channel exists at all —
most likely explained by that earlier unit having a genuine hardware
fault: both of its empirically-found channels later stopped lighting up
entirely, mid-session, with the firmware-side behavior confirmed unchanged
throughout (`status` and the `[led]`/`[ledpin]` Serial logs showed every
command executing exactly as intended) — consistent with a marginal or
lifted solder joint on that unit's small SMD LED package, not a wrong
assumption about the board's design. Standby's color mapping is back to
the original red+green (amber) intent now that a real red channel is
confirmed, rather than the blue-substitute used while red was believed
unavailable.

`led <red|green|blue|rg|rb|gb|all|off>` and `ledpin <gpio> <lo|hi|off>`
(raw single-pin control, `help` lists both) are the fastest way to
re-verify on a given physical unit.

## Buzzer — pin chosen, not yet wired/confirmed by ear

`src/hw/buzzer.*` is fully wired up against `BUZZER_PIN` (currently
`GPIO26`) so the whole call chain — cue transition or message arrival →
pattern selection → non-blocking pin toggling — is real, tested code, not
a stub.

`GPIO26` is this board's dedicated **speaker port**, per Elegoo's own
official pinout (same source as the RGB LED and touch corrections above):
"Audio signal DAC output signal" for a built-in amp behind a real 2-pin
speaker header. That table also revealed something the original
empirical approach had no way to find: **`GPIO4` is a separate amp
*enable* line** ("Audio enable signal, low level enable, high level
disable") — without holding it LOW, the amp is disabled and `BUZZER_PIN`'s
signal never reaches anything, which plausibly explains why early
`tonepin 26` tests produced no sound even before the buzzer-vs-vibration-
motor mixup (see below) was sorted out. `buzzer::init()` now holds
`AUDIO_ENABLE_PIN` (GPIO4) LOW at boot.

`GPIO27`, used here originally before the official pinout was found,
turned out to already be claimed: it's part of this board's general SPI
peripheral header (shared with the MicroSD slot), not a free GPIO.

**A real physical component was tested against this and turned out to be
the wrong kind of part**: what was on hand is a coin *vibration motor*
(DIYables 1030), not an audible buzzer or speaker — it's meant to be
felt, not heard, which is why no `tonepin`/`led`-style test produced any
sound. It also likely draws more current than a GPIO can safely source
directly, so it needs a small transistor between the GPIO and the motor,
not a direct connection — paused pending that. Once either a real speaker
(for the GPIO4/GPIO26 speaker port above) or a transistor-driven motor is
available, use `tonepin <gpio> <freq_hz>` (`help` lists it) to confirm
audibly/by feel — same empirical approach the RGB LED pins were confirmed
with, just heard/felt instead of seen.

| Trigger | Pattern | Matches |
|---|---|---|
| Cue → Standby | one ~2s buzz | `PagerHaptics.playCueTransition` |
| Cue → Go! | 6 pulses, 0.5s on / 0.1s gap | `PagerHaptics.playCueTransition` |
| Message while Standby/Off | 3 pulses, ~0.45s on / 0.2s gap | `PagerHaptics.playMessageReceived` |
| Message while Go! | 5 pulses, 50ms on / 100ms gap (~0.15s apart) | `PagerHaptics.playMessageReceived` |

Every call also logs exactly what pattern *would* play over Serial — this
was used to verify all four patterns fire at the right moments with the
right timings. Once the buzzer is wired up, re-verify
it's audible/felt as expected; no code change should be needed unless the
part turns out to need `tone()` (passive piezo) instead of the current
`digitalWrite` on/off drive (active buzzer assumption).

## Display orientation

Portrait, 240×320 (`tft.setRotation(0)` in `src/ui/ui.cpp`) — the pager's
content (role pill, big state text, item/timer card, note, message banner)
is stacked vertically. **Confirmed right-side-up against a photo of the
real physical unit**.

## Colors — two deliberate deviations from the iPhone app

Both found and fixed against real hardware photos, not guessed at:

- **Off/Clear background and Boot/WiFi-prompt/Connecting/role-picker
  screens are pure black (`0x000000`)**, not `CueState.swift`'s exact
  `0x141A26` ("Ink 900"). Requested for this panel over pixel-matching the
  iPhone app exactly.
- **Standby's dark text (used on the yellow background) is pure black
  (`0x000000`)**, not `CueState.swift`'s `0x1A1A1A` — that near-black value
  read as visibly blue-tinted on the real panel, not neutral dark gray.

Both live in `src/cue/cue_state.h`'s `cueStateBgColor()`/`cueStateTextColor()`
— Standby and Go's colors are still pixel-matched to `CueState.swift`.

## Build / flash

```bash
nix shell nixpkgs#platformio --command pio run -t upload --upload-port /dev/cu.usbserial-110
```

(`nix search nixpkgs platformio` if that attribute path has moved.)
`platformio.ini`'s `upload_port`/`monitor_port` default to
`/dev/cu.usbserial-110` (this machine's CH340 device node) — override with
`--upload-port <path>` on another machine. **`upload_speed` is set to
`115200`, not the usual 921600**: this specific CH340/board/cable
combination reliably failed `esptool`'s post-baud-change verification at
921600 ("Invalid head of packet... possible serial noise") but flashed
cleanly every time at 115200. If a different setup handles the higher
speed fine, bump it back up — this wasn't a firmware bug, just this cable's
behavior.

```bash
nix shell nixpkgs#platformio --command pio device monitor --port /dev/cu.usbserial-110 --baud 115200
```

## Regenerating fonts and icons

`tools/generate_fonts.py` (Inter, via `lv_font_conv`) and `tools/generate_icons.py` (Lucide SVGs in `tools/icons`, rasterized with macOS's built-in SVG support, so macOS only) write `src/ui/fonts/*.c` and `src/ui/icons/icons.c`.

`lv_font_conv` puts a header comment in every generated font file containing the absolute path of the temp font and of the output file on your machine. Do not commit it. After regenerating fonts, strip that leading comment block:

```bash
perl -0pi -e 's{\A/\*.*?\*/\s*}{}s' Hardware/esp32/src/ui/fonts/inter_*.c
```

Then rebuild and commit the bundled firmware image as described under "Flashing from the Producer app".

The icons are [Lucide](https://lucide.dev) (ISC license, `tools/icons/LUCIDE-LICENSE.txt`). To change one, drop its SVG into `tools/icons`, edit `ICONS` in `generate_icons.py`, and rerun it.

## Known limitations / v2

- **No on-device reply to messages.** The message banner is
  indicator-only; replying would need a touch keyboard, which is a stretch goal
  given the small resistive touchscreen, not implemented here.
- **No "next item" note.** `HostPagerView`'s `nextNote` reads
  `engine.planItems[activeItemIndex + 1]` — the Producer's full local plan
  — but `CuePacket` only ever puts the single *active* `timerItem` on the
  wire, never the next one. This device shows `currentNote()` only; adding
  `nextNote` would need a protocol change on the Swift side, out of scope
  here.
- **No captive-portal WiFi setup.** Configuration is Serial-only for now
  (see "WiFi configuration"); a touch-driven WiFi picker screen (like
  `plotiphar-esp32`'s SoftAP + captive portal) is a reasonable v2 if a
  screen with no accessible USB port at re-provision time turns out to be
  a real deployment scenario.
