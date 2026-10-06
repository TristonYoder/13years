#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Triston Yoder


import argparse
import hashlib
import os
import shutil
import struct
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent
ENV = "cyd"
BUILD_DIR = PROJECT / ".pio" / "build" / ENV

BOOTLOADER_OFFSET = 0x1000
PARTITIONS_OFFSET = 0x8000
BOOT_APP0_OFFSET = 0xE000
MERGED_NAME = "13years-pager-merged.bin"

def fail(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)

def find_pio():
    candidates = [
        os.environ.get("PLATFORMIO"),
        shutil.which("pio"),
        shutil.which("platformio"),
        str(Path.home() / ".platformio" / "penv" / "bin" / "pio"),
    ]
    for c in candidates:
        if c and Path(c).exists():
            return c
    fail("could not find the `pio` executable (set $PLATFORMIO to override)")

def find_esptool():

    packaged = Path.home() / ".platformio" / "packages" / "tool-esptoolpy" / "esptool.py"
    penv_python = Path.home() / ".platformio" / "penv" / "bin" / "python"
    if packaged.exists() and penv_python.exists():
        return [str(penv_python), str(packaged)]
    if shutil.which("esptool.py"):
        return ["esptool.py"]
    try:
        import esptool
        return [sys.executable, "-m", "esptool"]
    except ImportError:
        fail("could not find esptool (pip install esptool, or build once with PlatformIO)")

def find_boot_app0():
    root = Path.home() / ".platformio" / "packages" / "framework-arduinoespressif32"
    hit = root / "tools" / "partitions" / "boot_app0.bin"
    if hit.exists():
        return hit
    found = list(root.rglob("boot_app0.bin")) if root.exists() else []
    if found:
        return found[0]
    fail("could not find boot_app0.bin in the Arduino framework package")

def read_partitions(path):
    data = path.read_bytes()
    out = []
    for i in range(0, len(data), 32):
        entry = data[i:i + 32]
        if len(entry) < 32 or entry[:2] != b"\xaa\x50":
            break
        offset, size = struct.unpack("<II", entry[4:12])
        name = entry[12:28].rstrip(b"\x00").decode("utf-8", "replace")
        out.append((name, offset, size))
    if not out:
        fail(f"no partition entries found in {path}")
    return out

def human(n):
    return f"{n:,} bytes ({n / 1024:.0f}K)"

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path,
                    help="also copy the merged image to this path (e.g. the app's Resources)")
    ap.add_argument("--skip-build", action="store_true",
                    help="merge the existing build output instead of rebuilding")
    args = ap.parse_args()

    if not args.skip_build:
        pio = find_pio()
        print(f"building env:{ENV} with {pio}")
        r = subprocess.run([pio, "run", "-e", ENV], cwd=PROJECT)
        if r.returncode != 0:
            fail("PlatformIO build failed")

    firmware = BUILD_DIR / "firmware.bin"
    bootloader = BUILD_DIR / "bootloader.bin"
    partitions = BUILD_DIR / "partitions.bin"
    for p in (firmware, bootloader, partitions):
        if not p.exists():
            fail(f"missing build output: {p} (run without --skip-build)")
    boot_app0 = find_boot_app0()

    table = read_partitions(partitions)
    print("\npartition table:")
    for name, offset, size in table:
        print(f"  {name:10} offset=0x{offset:06x} size={human(size)}")

    app = next((e for e in table if e[0] in ("app0", "factory")), None)
    if app is None:
        fail("no app0/factory partition in the table — cannot size-check the firmware")
    app_name, app_offset, app_size = app
    app_bytes = firmware.stat().st_size
    used = app_bytes / app_size * 100
    print(f"\napp image: {human(app_bytes)} of {app_name}'s {human(app_size)} — {used:.1f}% used")

    if app_bytes > app_size:
        fail(f"firmware.bin ({human(app_bytes)}) does not fit in {app_name} "
             f"({human(app_size)}). A unit flashed with this will not boot, and "
             f"no OTA update could be staged. Shrink the build or repartition.")
    if used > 90:
        print(f"warning: only {human(app_size - app_bytes)} of headroom left in {app_name}",
              file=sys.stderr)

    merged = BUILD_DIR / MERGED_NAME
    cmd = find_esptool() + [
        "--chip", "esp32", "merge_bin", "-o", str(merged),
        "--flash_mode", "dio", "--flash_freq", "40m", "--flash_size", "4MB",
        hex(BOOTLOADER_OFFSET), str(bootloader),
        hex(PARTITIONS_OFFSET), str(partitions),
        hex(BOOT_APP0_OFFSET), str(boot_app0),
        hex(app_offset), str(firmware),
    ]
    print(f"\nmerging -> {merged.name}")
    r = subprocess.run(cmd, cwd=PROJECT)
    if r.returncode != 0:
        fail("esptool merge_bin failed")

    blob = merged.read_bytes()
    regions = [
        (BOOTLOADER_OFFSET, bootloader, "bootloader"),
        (PARTITIONS_OFFSET, partitions, "partitions"),
        (BOOT_APP0_OFFSET, boot_app0, "boot_app0"),
        (app_offset, firmware, "app"),
    ]
    print("\nverifying merged regions:")
    problems = []
    if any(b != 0xFF for b in blob[:BOOTLOADER_OFFSET]):
        problems.append(f"the first 0x{BOOTLOADER_OFFSET:x} bytes are not 0xFF padding")
    for offset, src_path, label in sorted(regions):
        src = src_path.read_bytes()
        ok = blob[offset:offset + len(src)] == src
        print(f"  0x{offset:06x} {label:11} {len(src):>9,}B  {'ok' if ok else 'MISMATCH'}")
        if not ok:
            problems.append(f"{label} at 0x{offset:06x} does not match {src_path.name}")
    expected_end = app_offset + firmware.stat().st_size
    if len(blob) != expected_end:
        problems.append(f"merged image is {len(blob):,}B, expected {expected_end:,}B")
    if problems:
        for p in problems:
            print(f"  {p}", file=sys.stderr)
        fail("merged image failed verification — do not flash it")

    digest = hashlib.sha256(blob).hexdigest()
    print(f"\nmerged image: {human(len(blob))}")
    print(f"sha256:       {digest}")
    print(f"flash with:   esptool.py --chip esp32 write_flash 0x0 {merged.name}")

    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(merged, args.out)
        print(f"copied to:    {args.out}")

if __name__ == "__main__":
    main()
