#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Triston Yoder


import subprocess
import sys
from pathlib import Path

from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[3]
FONTS_SRC = ROOT / "Sources/Shared/Resources/Fonts"
OUT_DIR = Path(__file__).resolve().parent.parent / "src/ui/fonts"

FONTS = [
    ("Inter-Regular.ttf", "inter_regular_14", 14),
    ("Inter-Regular.ttf", "inter_regular_18", 18),
    ("Inter-Bold.ttf", "inter_bold_14", 14),
    ("Inter-Bold.ttf", "inter_bold_18", 18),
    ("Inter-Black.ttf", "inter_black_32", 32),
]

def patch_slashed_zero(src_path: Path, out_path: Path) -> None:
    font = TTFont(str(src_path))
    patched = 0
    for table in font["cmap"].tables:
        cmap = table.cmap
        if cmap.get(0x30) == "zero":
            cmap[0x30] = "zero.slash"
            patched += 1
    if patched == 0:
        raise RuntimeError(
            f"{src_path.name}: no cmap subtable mapped U+0030 to glyph "
            "'zero' as expected — Inter's glyph names may have changed; "
            "re-check via `f['GSUB'].table` before continuing blind."
        )
    font.save(str(out_path))

def main() -> None:
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        patched_paths: dict[str, Path] = {}
        for weight_file, _, _ in FONTS:
            if weight_file not in patched_paths:
                out = tmp_path / f"{weight_file.removesuffix('.ttf')}-SlashedZero.ttf"
                patch_slashed_zero(FONTS_SRC / weight_file, out)
                patched_paths[weight_file] = out

        for weight_file, lv_name, size in FONTS:
            out_c = OUT_DIR / f"{lv_name}.c"
            subprocess.run(
                [
                    "npx", "--yes", "lv_font_conv@1.5.3",
                    "--font", str(patched_paths[weight_file]),
                    "-r", "0x20-0x7E",
                    "--size", str(size),
                    "--bpp", "4",
                    "--format", "lvgl",
                    "--lv-font-name", lv_name,
                    "--no-compress",
                    "--no-prefilter",
                    "-o", str(out_c),
                ],
                check=True,
            )
            print(f"wrote {out_c}")

if __name__ == "__main__":
    sys.exit(main())
