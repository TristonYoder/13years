#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Triston Yoder

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCUMENT="${SCREENSHOT_DOCUMENT:-$HOME/Documents/campusClock.13years}"
APPEARANCE="${SCREENSHOT_APPEARANCE:-light}"
ONLY="${SCREENSHOT_ONLY:-}"
APPS="${SCREENSHOT_APP:-producer-mac}"
SIM_DEVICE="${SCREENSHOT_DEVICE:-}"
DERIVED="$ROOT/build/screenshots-dd"
WORK_ROOT="$ROOT/build/screenshots-work"
SKIP_BUILD="${SCREENSHOT_SKIP_BUILD:-0}"

usage() {
    echo "usage: $0 [--app producer-mac|pager-mac|pager-ios|pager-ipad|pager-tv|all] [--device name|udid] [--document path] [--appearance light|dark] [--only id,id] [--skip-build]" >&2
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app) APPS="$2"; shift 2 ;;
        --device) SIM_DEVICE="$2"; shift 2 ;;
        --document) DOCUMENT="$2"; shift 2 ;;
        --appearance) APPEARANCE="$2"; shift 2 ;;
        --only) ONLY="$2"; shift 2 ;;
        --skip-build) SKIP_BUILD=1; shift ;;
        *) usage ;;
    esac
done

case "$APPS" in
    all) APPS="producer-mac pager-mac pager-ios pager-ipad pager-tv" ;;
    producer-mac|pager-mac|pager-ios|pager-ipad|pager-tv) ;;
    *) usage ;;
esac
[[ "$APPEARANCE" == "light" || "$APPEARANCE" == "dark" ]] || usage
[[ -f "$DOCUMENT" ]] || { echo "document not found: $DOCUMENT" >&2; exit 1; }

setting() { sed -n "s/^$1 *= *//p" "$ROOT/Config/Base.xcconfig" | head -1 | tr -d '[:space:]'; }
VERSION="$(setting MARKETING_VERSION)"
BUILD="$(setting CURRENT_PROJECT_VERSION)"
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [[ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]]; then COMMIT="$COMMIT-dirty"; fi
OUT_ROOT="$ROOT/Screenshots/$VERSION-$BUILD"

echo "==> 13 Years $VERSION ($BUILD) at $COMMIT"

GENERATED=0
generate_project() {
    if [[ "$GENERATED" == "0" ]]; then
        command -v xcodegen >/dev/null && (cd "$ROOT" && xcodegen generate >/dev/null)
        GENERATED=1
    fi
}

DRIVER="$DERIVED/screenshot-driver"
compile_driver() {
    mkdir -p "$DERIVED"
    if [[ ! -x "$DRIVER" || "$ROOT/scripts/screenshot-driver.swift" -nt "$DRIVER" ]]; then
        echo "==> Compiling the capture driver"
        swiftc -O "$ROOT/scripts/screenshot-driver.swift" -o "$DRIVER"
    fi
}

output_dir() {
    if [[ -n "$ONLY" ]]; then echo "$OUT_ROOT/$1-partial"; else echo "$OUT_ROOT/$1"; fi
}

finish_app() {
    local app="$1" status="$2" out="$3"
    if [[ $status -eq 0 && -z "$ONLY" ]]; then
        rm -rf "$OUT_ROOT/$app-partial"
        ln -sfn "$VERSION-$BUILD" "$ROOT/Screenshots/latest"
    fi
    [[ $status -eq 0 ]] && echo "==> Wrote $out"
    return 0
}

APP_PID=""
SIM_UDID=""
SIM_BUNDLE=""
SIM_APPEARANCE=""
cleanup() {
    if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null || true
        sleep 1
        kill -9 "$APP_PID" 2>/dev/null || true
    fi
    APP_PID=""
    if [[ -n "$SIM_UDID" ]]; then
        xcrun simctl terminate "$SIM_UDID" "$SIM_BUNDLE" >/dev/null 2>&1 || true
        xcrun simctl uninstall "$SIM_UDID" "$SIM_BUNDLE" >/dev/null 2>&1 || true
        xcrun simctl status_bar "$SIM_UDID" clear >/dev/null 2>&1 || true
        [[ -n "$SIM_APPEARANCE" ]] && xcrun simctl ui "$SIM_UDID" appearance "$SIM_APPEARANCE" >/dev/null 2>&1 || true
        SIM_UDID=""
    fi
}
trap cleanup EXIT

run_mac_app() {
    local app="$1" scheme product bundle_id
    local -a extra_args=()
    case "$app" in
        producer-mac)
            scheme=ProducerMac
            product="13 Years Producer"
            bundle_id="app.13years.producer.screenshots"
            extra_args=(-isControlAPIEnabled NO -isPCOLiveSyncEnabled NO)
            ;;
        pager-mac)
            scheme=PagerMac
            product="13 Years"
            bundle_id="app.13years.pager.screenshots"
            extra_args=(-ScreenshotRole Lighting)
            ;;
    esac
    local out work
    out="$(output_dir "$app")"
    work="$WORK_ROOT/$app"

    if [[ "$SKIP_BUILD" != "1" ]]; then
        echo "==> Building $scheme for screenshots"
        generate_project
        xcodebuild build \
            -project "$ROOT/ThirteenYears.xcodeproj" \
            -scheme "$scheme" \
            -configuration Debug \
            -destination platform=macOS \
            -derivedDataPath "$DERIVED" \
            PRODUCT_BUNDLE_IDENTIFIER="$bundle_id" \
            ENABLE_APP_SANDBOX=NO \
            CODE_SIGN_ENTITLEMENTS= \
            CODE_SIGN_IDENTITY=- \
            CODE_SIGN_STYLE=Manual \
            DEVELOPMENT_TEAM= \
            -quiet || return 1
    fi

    local bundle="$DERIVED/Build/Products/Debug/$product.app"
    local binary="$bundle/Contents/MacOS/$product"
    [[ -x "$binary" ]] || { echo "missing build at $bundle" >&2; return 1; }
    [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$bundle/Contents/Info.plist")" == "$bundle_id" ]] || { echo "$bundle is not the screenshot build; run without --skip-build" >&2; return 1; }
    compile_driver || return 1

    rm -rf "$work"
    mkdir -p "$work/out" "$work/document"
    cp "$DOCUMENT" "$work/document/" || return 1
    local doc_copy="$work/document/$(basename "$DOCUMENT")"

    defaults delete "$bundle_id" >/dev/null 2>&1 || true
    if [[ "$app" == "producer-mac" ]]; then
        defaults write "$bundle_id" isControlAPIEnabled -bool NO
        defaults write "$bundle_id" isPCOLiveSyncEnabled -bool NO
        defaults write "$bundle_id" hasLaunchedBefore -bool YES
    fi

    local -a args=(-ScreenshotTour "$work/out" -ScreenshotDocument "$doc_copy" -ScreenshotAppearance "$APPEARANCE"
                   ${extra_args[@]+"${extra_args[@]}"} -ApplePersistenceIgnoreState YES -NSQuitAlwaysKeepsWindows NO)
    [[ -n "$ONLY" ]] && args+=(-ScreenshotTourOnly "$ONLY")

    echo "==> Running the $app tour"
    pkill -f "^$binary" 2>/dev/null || true
    open -n -a "$bundle" --env THIRTEEN_EPHEMERAL_KEYCHAIN=1 --stdout "$work/app.log" --stderr "$work/app.log" --args "${args[@]}"

    APP_PID=""
    for _ in $(seq 1 100); do
        APP_PID="$(pgrep -f "^$binary" | head -1 || true)"
        [[ -n "$APP_PID" ]] && break
        sleep 0.2
    done
    [[ -n "$APP_PID" ]] || { echo "the app did not start" >&2; return 1; }

    local status=0
    caffeinate -dimsu "$DRIVER" --work "$work/out" --out "$out" --pid "$APP_PID" --app "$app" \
        --device "Mac (macOS $(sw_vers -productVersion))" \
        --version "$VERSION" --build "$BUILD" --commit "$COMMIT" --appearance "$APPEARANCE" --timeout 900 || status=$?

    for _ in $(seq 1 50); do
        kill -0 "$APP_PID" 2>/dev/null || break
        sleep 0.2
    done
    cleanup
    finish_app "$app" "$status" "$out"
    return $status
}

simulator_field() {
    xcrun simctl list devices -j | python3 -c '
import json, sys
wanted, field = sys.argv[1], sys.argv[2]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for device in devices:
        if wanted in (device["udid"], device["name"]) and device.get("isAvailable", True):
            if field == "runtime":
                print(runtime.rsplit(".", 1)[-1].replace("-", " ", 1).replace("-", "."))
            else:
                print(device[field])
            sys.exit(0)
sys.exit(1)
' "$1" "$2"
}

run_simulator_app() {
    local app="$1" scheme=Pager product="13 Years" bundle_id="app.13years.pager.screenshots"
    local device platform=iphonesimulator status_bar=1
    local -a extra_args=()
    case "$app" in
        pager-ios) device="C9291001-B2B1-4622-BAA1-5E8A0B5DD87C" ;;
        pager-ipad)
            device="3078FD60-80AD-4D55-81FC-961C52086F64"
            extra_args=(-ScreenshotRole Lighting)
            ;;
        pager-tv)
            device="F67A6346-D782-49CF-A389-09468AF5B2EB"
            scheme=PagerTV
            product="13 Years TV"
            platform=appletvsimulator
            status_bar=0
            extra_args=(-ScreenshotRole Lighting)
            ;;
    esac
    device="${SIM_DEVICE:-$device}"
    local out udid name runtime state
    out="$(output_dir "$app")"
    udid="$(simulator_field "$device" udid)" || { echo "no available simulator named $device" >&2; return 1; }
    name="$(simulator_field "$device" name)"
    runtime="$(simulator_field "$device" runtime)"
    state="$(simulator_field "$device" state)"
    echo "==> Simulator $name ($runtime) $udid"
    if [[ "$state" != "Booted" ]]; then
        xcrun simctl boot "$udid" || return 1
        xcrun simctl bootstatus "$udid" >/dev/null || return 1
    fi

    if [[ "$SKIP_BUILD" != "1" ]]; then
        echo "==> Building $scheme for the simulator"
        generate_project
        xcodebuild build \
            -project "$ROOT/ThirteenYears.xcodeproj" \
            -scheme "$scheme" \
            -configuration Debug \
            -destination "id=$udid" \
            -derivedDataPath "$DERIVED" \
            PRODUCT_BUNDLE_IDENTIFIER="$bundle_id" \
            CODE_SIGNING_ALLOWED=NO \
            -quiet || return 1
    fi

    local bundle="$DERIVED/Build/Products/Debug-$platform/$product.app"
    [[ -d "$bundle" ]] || { echo "missing build at $bundle" >&2; return 1; }
    [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$bundle/Info.plist")" == "$bundle_id" ]] || { echo "$bundle is not the screenshot build; run without --skip-build" >&2; return 1; }
    compile_driver || return 1

    SIM_UDID="$udid"
    SIM_BUNDLE="$bundle_id"
    SIM_APPEARANCE="$(xcrun simctl ui "$udid" appearance 2>/dev/null || true)"
    [[ "$SIM_APPEARANCE" == "light" || "$SIM_APPEARANCE" == "dark" ]] || SIM_APPEARANCE=""

    xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
    xcrun simctl uninstall "$udid" "$bundle_id" >/dev/null 2>&1 || true
    xcrun simctl install "$udid" "$bundle" || return 1
    local data work
    data="$(xcrun simctl get_app_container "$udid" "$bundle_id" data)" || return 1
    work="$data/tmp/screenshot-tour"
    mkdir -p "$work/out" "$work/document"
    cp "$DOCUMENT" "$work/document/" || return 1
    local doc_copy="$work/document/$(basename "$DOCUMENT")"

    xcrun simctl ui "$udid" appearance "$APPEARANCE" >/dev/null 2>&1 || echo "    (the simulator does not support an appearance override)"
    if [[ "$status_bar" == "1" ]]; then
        xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
            --cellularMode active --cellularBars 4 --operatorName "" --batteryState charged --batteryLevel 100
    fi

    local -a args=(-ScreenshotTour "$work/out" -ScreenshotDocument "$doc_copy" -ScreenshotAppearance "$APPEARANCE"
                   ${extra_args[@]+"${extra_args[@]}"})
    [[ -n "$ONLY" ]] && args+=(-ScreenshotTourOnly "$ONLY")

    echo "==> Running the $app tour"
    local launched
    launched="$(SIMCTL_CHILD_THIRTEEN_EPHEMERAL_KEYCHAIN=1 xcrun simctl launch --terminate-running-process "$udid" "$bundle_id" "${args[@]}")"
    APP_PID="${launched##*: }"
    [[ "$APP_PID" =~ ^[0-9]+$ ]] || { echo "the app did not start: $launched" >&2; return 1; }

    local status=0
    caffeinate -dimsu "$DRIVER" --work "$work/out" --out "$out" --pid "$APP_PID" --app "$app" \
        --simulator "$udid" --device "$name ($runtime)" \
        --version "$VERSION" --build "$BUILD" --commit "$COMMIT" --appearance "$APPEARANCE" --timeout 900 || status=$?

    for _ in $(seq 1 50); do
        kill -0 "$APP_PID" 2>/dev/null || break
        sleep 0.2
    done
    cleanup
    finish_app "$app" "$status" "$out"
    return $status
}

STATUS=0
for app in $APPS; do
    case "$app" in
        pager-ios|pager-ipad|pager-tv) run_simulator_app "$app" || STATUS=$? ;;
        *) run_mac_app "$app" || STATUS=$? ;;
    esac
done
exit $STATUS
