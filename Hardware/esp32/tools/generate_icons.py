#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Triston Yoder


import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

OUT_DIR = Path(__file__).resolve().parent.parent / "src/ui/icons"

SRC_DIR = Path(__file__).resolve().parent / "icons"
SUPERSAMPLE = 4

ICONS = [
    ("chevron-down.svg", 14, "chevron_down"),
    ("message-square-text.svg", 18, "message_square_text"),
]

RENDER_SWIFT = """
import AppKit

let args = CommandLine.arguments
let svgPath = args[1], pixels = Int(args[2])!, outPath = args[3]

guard let image = NSImage(contentsOf: URL(fileURLWithPath: svgPath)) else {
    FileHandle.standardError.write("FAILED to load \\(svgPath)\\n".data(using: .utf8)!)
    exit(1)
}
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
rep.size = NSSize(width: pixels, height: pixels)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
"""

def render_svg(svg_path: Path, pixels: int, out_path: Path) -> None:
    with tempfile.NamedTemporaryFile(suffix=".swift", mode="w", delete=False) as f:
        f.write(RENDER_SWIFT)
        script_path = f.name
    try:
        subprocess.run(["swift", script_path, str(svg_path), str(pixels * SUPERSAMPLE), str(out_path)], check=True)
    finally:
        Path(script_path).unlink()
    big = Image.open(out_path).convert("RGBA")
    big.resize((pixels, pixels), Image.LANCZOS).save(out_path)

def emit_c_array(png_path: Path, identifier: str) -> str:
    img = Image.open(png_path).convert("RGBA")
    w, h = img.size
    alpha_bytes = bytes(img.getpixel((x, y))[3] for y in range(h) for x in range(w))

    lines = [
        f"static const uint8_t {identifier}_map[] = {{",
    ]
    for i in range(0, len(alpha_bytes), 16):
        chunk = alpha_bytes[i:i + 16]
        lines.append("  " + ", ".join(str(b) for b in chunk) + ",")
    lines.append("};")
    lines.append("")
    lines.append(f"const lv_img_dsc_t {identifier} = {{")
    lines.append(f"  .header.cf = LV_IMG_CF_ALPHA_8BIT,")
    lines.append(f"  .header.always_zero = 0,")
    lines.append(f"  .header.w = {w},")
    lines.append(f"  .header.h = {h},")
    lines.append(f"  .data_size = {w * h},")
    lines.append(f"  .data = {identifier}_map,")
    lines.append("};")
    return "\n".join(lines)

def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        blocks = []
        header_externs = []
        for svg_name, pixels, identifier in ICONS:
            png_path = tmp_path / f"{identifier}.png"
            render_svg(SRC_DIR / svg_name, pixels, png_path)
            blocks.append(emit_c_array(png_path, identifier))
            header_externs.append(f"extern const lv_img_dsc_t {identifier};")

        c_path = OUT_DIR / "icons.c"
        c_path.write_text(
            '#include "icons.h"\n\n' + "\n\n".join(blocks) + "\n"
        )
        print(f"wrote {c_path}")

        h_path = OUT_DIR / "icons.h"
        h_path.write_text(
                        "#pragma once\n"
            "#include <lvgl.h>\n\n"
            + "\n".join(header_externs) + "\n"
        )
        print(f"wrote {h_path}")

if __name__ == "__main__":
    sys.exit(main())
