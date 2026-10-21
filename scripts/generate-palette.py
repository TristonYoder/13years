#!/usr/bin/env python3
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PALETTE = os.path.join(ROOT, "Design", "palette.json")
SWIFT_OUT = "Packages/13YearsClockKit/Sources/ThirteenYearsClockKit/Models/AppPalette.generated.swift"
WEB_PAGER = "Packages/13YearsClockKit/Sources/ThirteenYearsClockKit/Resources/WebPager/pager.html"
ESP_OUT = "Hardware/esp32/src/ui/palette.h"
COMPANION_DIR = os.environ.get("COMPANION_DIR", os.path.join(os.path.dirname(ROOT), "companion-module-13YearsProducer"))
COMPANION_OUT = "src/palette.ts"
TARGETS = {"swift", "web", "esp32", "companion", "assets"}
HEX = re.compile(r"^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$")


def load():
    with open(PALETTE) as f:
        data = json.load(f)
    tokens = {}
    for name, spec in data["tokens"].items():
        if not re.fullmatch(r"[a-z][A-Za-z0-9]*", name):
            sys.exit("bad token name: %s" % name)
        for key in ("light", "dark"):
            if not HEX.match(spec.get(key, "")):
                sys.exit("%s.%s must be #RRGGBB or #RRGGBBAA" % (name, key))
        bad = set(spec.get("targets", [])) - TARGETS
        if bad or not spec.get("targets"):
            sys.exit("%s has bad targets %s" % (name, sorted(bad)))
        if "assets" in spec["targets"] and not spec.get("asset"):
            sys.exit("%s targets assets but has no asset name" % name)
        tokens[name] = {
            "light": rgba(spec["light"]),
            "dark": rgba(spec["dark"]),
            "targets": spec["targets"],
            "asset": spec.get("asset"),
        }
    return data.get("catalogs", []), tokens


def rgba(text):
    h = text.lstrip("#")
    if len(h) == 6:
        h += "FF"
    return tuple(int(h[i:i + 2], 16) for i in range(0, 8, 2))


def hex8(c):
    return "0x%02X%02X%02X%02X" % c


def hex6(c):
    return "0x%02X%02X%02X" % c[:3]


def alpha_text(a):
    return ("%.2f" % (a / 255)).rstrip("0").rstrip(".")


def css_value(c):
    if c[3] == 255:
        return "#%02x%02x%02x" % c[:3]
    return "rgba(%d, %d, %d, %s)" % (c[0], c[1], c[2], alpha_text(c[3]))


def kebab(name):
    return re.sub(r"([A-Z])", lambda m: "-" + m.group(1).lower(), name)


def pascal(name):
    return name[0].upper() + name[1:]


def gen_swift(tokens):
    out = [
        "// SPDX-License-Identifier: AGPL-3.0-only",
        "// Copyright (C) 2026 Triston Yoder",
        "",
        "#if canImport(SwiftUI)",
        "import SwiftUI",
        "#if os(macOS)",
        "import AppKit",
        "#elseif canImport(UIKit)",
        "import UIKit",
        "#endif",
        "",
        "public enum AppPalette {",
    ]
    for name, t in tokens.items():
        if "swift" not in t["targets"]:
            continue
        if t["light"] == t["dark"]:
            out.append("    public static let %s = fixed(%s)" % (name, hex8(t["light"])))
        else:
            out.append("    public static let %s = adaptive(light: %s, dark: %s)" % (name, hex8(t["light"]), hex8(t["dark"])))
    out += [
        "}",
        "",
        "private extension AppPalette {",
        "    static func fixed(_ value: UInt32) -> Color {",
        "        Color(.sRGB,",
        "              red: Double((value >> 24) & 0xFF) / 255,",
        "              green: Double((value >> 16) & 0xFF) / 255,",
        "              blue: Double((value >> 8) & 0xFF) / 255,",
        "              opacity: Double(value & 0xFF) / 255)",
        "    }",
        "",
        "    static func adaptive(light: UInt32, dark: UInt32) -> Color {",
        "        #if os(watchOS)",
        "        return fixed(dark)",
        "        #elseif os(macOS)",
        "        return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in",
        "            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua",
        "            return component(isDark ? dark : light)",
        "        }))",
        "        #else",
        "        return Color(uiColor: UIColor(dynamicProvider: { traits in",
        "            component(traits.userInterfaceStyle == .dark ? dark : light)",
        "        }))",
        "        #endif",
        "    }",
        "",
        "    #if os(macOS)",
        "    static func component(_ value: UInt32) -> NSColor {",
        "        NSColor(srgbRed: CGFloat((value >> 24) & 0xFF) / 255,",
        "                green: CGFloat((value >> 16) & 0xFF) / 255,",
        "                blue: CGFloat((value >> 8) & 0xFF) / 255,",
        "                alpha: CGFloat(value & 0xFF) / 255)",
        "    }",
        "    #elseif canImport(UIKit) && !os(watchOS)",
        "    static func component(_ value: UInt32) -> UIColor {",
        "        UIColor(red: CGFloat((value >> 24) & 0xFF) / 255,",
        "                green: CGFloat((value >> 16) & 0xFF) / 255,",
        "                blue: CGFloat((value >> 8) & 0xFF) / 255,",
        "                alpha: CGFloat(value & 0xFF) / 255)",
        "    }",
        "    #endif",
        "}",
        "#endif",
        "",
    ]
    return "\n".join(out)


def gen_esp(tokens):
    out = ["#pragma once", "", "#include <stdint.h>", ""]
    for name, t in tokens.items():
        if "esp32" in t["targets"]:
            out.append("constexpr uint32_t k%sHex = %s;" % (pascal(name), hex6(t["dark"])))
    out.append("")
    return "\n".join(out)


def gen_companion(tokens):
    out = ["export type RGB = [number, number, number]", ""]
    for name, t in tokens.items():
        if "companion" in t["targets"]:
            r, g, b = t["dark"][:3]
            out.append("export const %s: RGB = [%d, %d, %d]" % (name, r, g, b))
    out.append("")
    return "\n".join(out)


def gen_web_block(tokens):
    out = ['<style id="palette">', ":root {"]
    for name, t in tokens.items():
        if "web" in t["targets"]:
            out.append("  --pal-%s: %s;" % (kebab(name), css_value(t["dark"])))
    out += ["}", "</style>"]
    return "\n".join(out)


def gen_web(tokens, source):
    block = gen_web_block(tokens)
    pattern = re.compile(r'<style id="palette">.*?</style>', re.S)
    if pattern.search(source):
        source = pattern.sub(lambda m: block, source, count=1)
    else:
        source = source.replace("<style>", block + "\n<style>", 1)
    theme = css_value(tokens["cueOff"]["dark"])
    source = re.sub(r'(<meta name="theme-color" content=")[^"]*(")', lambda m: m.group(1) + theme + m.group(2), source, count=1)
    return source


def gen_colorset(t):
    def entry(c, dark):
        item = {
            "color": {
                "color-space": "srgb",
                "components": {
                    "alpha": "%.3f" % (c[3] / 255),
                    "blue": "0x%02X" % c[2],
                    "green": "0x%02X" % c[1],
                    "red": "0x%02X" % c[0],
                },
            },
            "idiom": "universal",
        }
        if dark:
            item["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
        return item

    colors = [entry(t["light"], False)]
    if t["dark"] != t["light"]:
        colors.append(entry(t["dark"], True))
    lines = ["{", '  "colors" : [']
    for i, item in enumerate(colors):
        comp = item["color"]["components"]
        parts = []
        if "appearances" in item:
            parts.append('      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],')
        comps = ", ".join('"%s" : "%s"' % (k, comp[k]) for k in ("alpha", "blue", "green", "red"))
        parts.append('      "color" : { "color-space" : "srgb", "components" : { %s } },' % comps)
        parts.append('      "idiom" : "universal"')
        lines.append("    {")
        lines += parts
        lines.append("    }" + ("," if i < len(colors) - 1 else ""))
    lines += ["  ],", '  "info" : { "author" : "xcode", "version" : 1 }', "}", ""]
    return "\n".join(lines)


def outputs():
    catalogs, tokens = load()
    files = {}
    files[SWIFT_OUT] = gen_swift(tokens)
    files[ESP_OUT] = gen_esp(tokens)
    with open(os.path.join(ROOT, WEB_PAGER)) as f:
        files[WEB_PAGER] = gen_web(tokens, f.read())
    for catalog in catalogs:
        for name, t in tokens.items():
            if "assets" in t["targets"]:
                files["%s/%s.colorset/Contents.json" % (catalog, t["asset"])] = gen_colorset(t)
    result = {os.path.join(ROOT, k): v for k, v in files.items()}
    if os.path.isdir(os.path.join(COMPANION_DIR, "src")):
        result[os.path.join(COMPANION_DIR, COMPANION_OUT)] = gen_companion(tokens)
    return result


def read(path):
    try:
        with open(path) as f:
            return f.read()
    except FileNotFoundError:
        return None


def main():
    files = outputs()
    if "--check" in sys.argv[1:]:
        stale = [p for p, c in files.items() if read(p) != c]
        if stale:
            print("generated palette files are out of date (run scripts/generate-palette.py):")
            for p in stale:
                print("  " + os.path.relpath(p, ROOT))
            sys.exit(1)
        return
    for path, content in files.items():
        if read(path) != content:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as f:
                f.write(content)
            print("wrote " + os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
