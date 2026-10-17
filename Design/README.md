# Design tokens

`palette.json` is the only place a color is defined. `scripts/generate-palette.py` writes every target from it; never edit the generated outputs by hand.

```
python3 scripts/generate-palette.py          # regenerate
python3 scripts/generate-palette.py --check  # exit 1 and list files that drifted
```

## Schema

```json
{
  "catalogs": ["Sources/ProducerIOS/Assets.xcassets"],
  "tokens": {
    "name": { "light": "#RRGGBB[AA]", "dark": "#RRGGBB[AA]", "targets": ["swift"], "asset": "ColorsetName" }
  }
}
```

- `name` is camelCase and becomes the Swift member (`AppPalette.name`), the CSS variable (`--pal-kebab-name`), the firmware constant (`kNameHex`) and the Companion export (`name`).
- `light` / `dark` are sRGB hex with an optional alpha byte. Colors that never change with appearance (cue colors, pager and display colors) repeat the same value in both.
- `targets` picks the outputs: `swift`, `web`, `esp32`, `companion`, `assets`.
- `asset` names the colorset written to each directory in `catalogs` (required with the `assets` target).

## Outputs

| Target | File | Value used |
| --- | --- | --- |
| swift | `Packages/13YearsClockKit/.../Models/AppPalette.generated.swift` | light and dark (dynamic; watchOS uses dark) |
| assets | `<catalog>/<asset>.colorset/Contents.json` | light and dark appearances |
| web | `<style id="palette">` and the `theme-color` meta in `WebPager/pager.html` | dark |
| esp32 | `Hardware/esp32/src/ui/palette.h` | dark, alpha dropped |
| companion | `src/palette.ts` in `companion-module-13YearsProducer` (skipped when the repo is absent) | dark, alpha dropped |

The pager, firmware and Companion are dark displays, so they always take the dark value.

## System colors

Tokens that used to be Apple system colors (`positive`, `warning`, `negative`, `info`, `favorite`, `remote`) carry explicit hex values equal to systemGreen, systemOrange, systemRed, systemBlue, systemYellow and systemPurple in light and dark. Swift no longer calls `Color.green` and friends. One value per token means the apps, the web pager, the firmware and Companion show the same color, and a change is made once. The cost is that these colors no longer follow future OS tweaks or the increased-contrast variants.
