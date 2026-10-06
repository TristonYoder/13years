#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Triston Yoder


import json
import shutil
import subprocess
import sys
from pathlib import Path
from struct import unpack

ROOT = Path(__file__).resolve().parent

MASTER = ROOT / "Sources" / "ProducerIOS" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"

IPAD = [(20, 1), (20, 2), (29, 1), (29, 2), (40, 1), (40, 2), (76, 2), (83.5, 2)]
IPHONE = [(20, 2), (20, 3), (29, 2), (29, 3), (40, 2), (40, 3), (60, 2), (60, 3)]

TARGETS = {
    "ProducerIOS": {"idioms": [("ipad", IPAD)]},
    "PagerIOS": {"idioms": [("iphone", IPHONE), ("ipad", IPAD)]},
}

def px(size, scale):
    return int(round(size * scale))

def png_size(path):
    with open(path, "rb") as fh:
        header = fh.read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")
    return unpack(">II", header[16:24])

def resize(src, out, size):
    subprocess.run(
        ["sips", "-z", str(size), str(size), str(src), "--out", str(out)],
        check=True, capture_output=True,
    )

def build(target, idioms, master):
    catalog = ROOT / "Sources" / target / "Assets.xcassets" / "AppIcon.appiconset"
    if not catalog.is_dir():
        print(f"error: {catalog} does not exist", file=sys.stderr)
        return False

    slots = [(idiom, size, scale) for idiom, entries in idioms for size, scale in entries]
    needed = sorted({px(size, scale) for _, size, scale in slots} | {1024})

    for size in needed:
        dest = catalog / f"icon-{size}.png"
        if dest.exists() and dest.samefile(master):
            continue
        if size == 1024:
            shutil.copy2(master, dest)
        else:
            resize(master, dest, size)

    images = [
        {
            "filename": f"icon-{px(size, scale)}.png",
            "idiom": idiom,
            "scale": f"{scale}x",
            "size": f"{size}x{size}",
        }
        for idiom, size, scale in slots
    ]
    images.append({"filename": "icon-1024.png", "idiom": "ios-marketing",
                   "scale": "1x", "size": "1024x1024"})

    (catalog / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )

    problems = []
    used = {i["filename"] for i in images}
    for image in images:
        path = catalog / image["filename"]
        if not path.exists():
            problems.append(f"{image['filename']} referenced but not generated")
            continue
        w, h = png_size(path)
        want = px(float(image["size"].split("x")[0]), int(image["scale"][0]))
        if (w, h) != (want, want):
            problems.append(f"{image['filename']} is {w}x{h}, slot declares {want}x{want}")
    for orphan in sorted(p for p in catalog.iterdir()
                         if p.suffix == ".png" and p.name not in used):
        problems.append(f"{orphan.name} is unreferenced (actool warns per orphan)")
        orphan.unlink()

    print(f"{target}: {len(images)} slots, {len(needed)} sizes")
    for p in problems:
        print(f"  ! {p}", file=sys.stderr)
    return not problems

def main():
    if not MASTER.exists():
        print(f"error: master icon not found: {MASTER}", file=sys.stderr)
        return 1

    ok = all(build(target, cfg["idioms"], MASTER)
             for target, cfg in TARGETS.items())

    print("done" if ok else "done, with problems (see above)")
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
