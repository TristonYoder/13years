# Third-party material

| Component | Where | License |
| --- | --- | --- |
| Inter typeface | `Sources/Shared/Resources/Fonts/Inter-*.ttf`; subsets compiled into `Hardware/esp32/src/ui/fonts` | SIL Open Font License 1.1. See `Sources/Shared/Resources/Fonts/Inter-LICENSE.txt`. |
| Space Grotesk typeface | `Sources/Shared/Resources/Fonts/SpaceGrotesk-*.ttf` | SIL Open Font License 1.1. See `Sources/Shared/Resources/Fonts/SpaceGrotesk-LICENSE.txt`. |
| Lucide icons | `Hardware/esp32/tools/icons/*.svg`, rasterized into `Hardware/esp32/src/ui/icons` | ISC. See `Hardware/esp32/tools/icons/LUCIDE-LICENSE.txt`. |
| LVGL | Firmware dependency (`lvgl/lvgl`), fetched by PlatformIO; configured by `Hardware/esp32/include/lv_conf.h` | MIT |
| TFT_eSPI | Firmware dependency (`bodmer/TFT_eSPI`) | Mixed BSD-style; see upstream |
| ArduinoJson | Firmware dependency (`bblanchon/ArduinoJson`) | MIT |
| Arduino core for ESP32 | Linked into `Sources/ProducerMac/Resources/13years-pager-merged.bin` | LGPL-2.1 and others; see upstream |
| `ws` and other npm packages | `Server/package-lock.json` | Per package |

The prebuilt firmware image `Sources/ProducerMac/Resources/13years-pager-merged.bin` is built from `Hardware/esp32` by `Hardware/esp32/tools/build-firmware.py` (also run in CI).
