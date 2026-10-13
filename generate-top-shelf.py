#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Triston Yoder

import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
BRAND = ROOT / "Sources" / "PagerTV" / "Assets.xcassets" / "AppIcon.brandassets"
MARK = ROOT / "stoplight-13-mark-dark.png"
FONT = ROOT / "Sources" / "Shared" / "Resources" / "Fonts" / "Inter-Bold.ttf"
BACKGROUND = (20, 20, 22)
TEXT = (245, 245, 243)

SETS = [
    ("Top Shelf Image", "top-shelf-image", "topshelf", 1920, 720),
    ("Top Shelf Image Wide", "top-shelf-image-wide", "topshelf-wide", 2320, 720),
]

def render(width, height):
    canvas = Image.new("RGB", (width, height), BACKGROUND)
    mark = Image.open(MARK).convert("RGBA")
    mark_h = int(height * 0.46)
    mark = mark.resize((round(mark.width * mark_h / mark.height), mark_h), Image.LANCZOS)
    font = ImageFont.truetype(str(FONT), int(height * 0.075))
    label = "13 Years"
    draw = ImageDraw.Draw(canvas)
    text_w = draw.textlength(label, font=font)
    gap = int(height * 0.06)
    block_h = mark_h + gap + font.size
    top = (height - block_h) // 2
    x = (width - mark.width) // 2
    canvas.paste(mark, (x, top), mark)
    draw.text(((width - text_w) / 2, top + mark_h + gap), label, font=font, fill=TEXT)
    return canvas

def main():
    for name, role, stem, w, h in SETS:
        folder = BRAND / f"{name}.imageset"
        folder.mkdir(parents=True, exist_ok=True)
        images = []
        for scale in (1, 2):
            fname = f"{stem}@{scale}x.png"
            render(w * scale, h * scale).save(folder / fname)
            images.append({"idiom": "tv", "filename": fname, "scale": f"{scale}x"})
        (folder / "Contents.json").write_text(json.dumps(
            {"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")

    path = BRAND / "Contents.json"
    data = json.loads(path.read_text())
    data["assets"] = [a for a in data["assets"] if a.get("role") not in {s[1] for s in SETS}]
    for name, role, stem, w, h in SETS:
        data["assets"].append({"size": f"{w}x{h}", "idiom": "tv", "filename": f"{name}.imageset", "role": role})
    path.write_text(json.dumps(data, indent=2) + "\n")

if __name__ == "__main__":
    main()
