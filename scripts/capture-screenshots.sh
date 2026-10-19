#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Triston Yoder

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCUMENT="${SCREENSHOT_DOCUMENT:-$HOME/Documents/campusClock.13years}"
APPEARANCE="${SCREENSHOT_APPEARANCE:-light}"
ONLY="${SCREENSHOT_ONLY:-}"
BUNDLE_ID="dev.7co.13years.producer.screenshots"
DERIVED="$ROOT/build/screenshots-dd"
WORK="$ROOT/build/screenshots-work"
SKIP_BUILD="${SCREENSHOT_SKIP_BUILD:-0}"

usage() {
    echo "usage: $0 [--document path] [--appearance light|dark] [--only id,id] [--skip-build]" >&2
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --document) DOCUMENT="$2"; shift 2 ;;
        --appearance) APPEARANCE="$2"; shift 2 ;;
        --only) ONLY="$2"; shift 2 ;;
        --skip-build) SKIP_BUILD=1; shift ;;
        *) usage ;;
    esac
done

[[ -f "$DOCUMENT" ]] || { echo "document not found: $DOCUMENT" >&2; exit 1; }

setting() { sed -n "s/^$1 *= *//p" "$ROOT/Config/Base.xcconfig" | head -1 | tr -d '[:space:]'; }
VERSION="$(setting MARKETING_VERSION)"
BUILD="$(setting CURRENT_PROJECT_VERSION)"
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [[ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]]; then COMMIT="$COMMIT-dirty"; fi
OUT_ROOT="$ROOT/Screenshots/$VERSION-$BUILD"
OUT="$OUT_ROOT/producer-mac"

echo "==> 13 Years Producer $VERSION ($BUILD) at $COMMIT"

if [[ "$SKIP_BUILD" != "1" ]]; then
    echo "==> Building the screenshot build"
    command -v xcodegen >/dev/null && (cd "$ROOT" && xcodegen generate >/dev/null)
    xcodebuild build \
        -project "$ROOT/ThirteenYears.xcodeproj" \
        -scheme ProducerMac \
        -configuration Debug \
        -destination platform=macOS \
        -derivedDataPath "$DERIVED" \
        PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
        ENABLE_APP_SANDBOX=NO \
        CODE_SIGN_ENTITLEMENTS= \
        CODE_SIGN_IDENTITY=- \
        CODE_SIGN_STYLE=Manual \
        DEVELOPMENT_TEAM= \
        -quiet
fi

APP="$DERIVED/Build/Products/Debug/13 Years Producer.app"
BINARY="$APP/Contents/MacOS/13 Years Producer"
[[ -x "$BINARY" ]] || { echo "missing build at $APP" >&2; exit 1; }

DRIVER="$DERIVED/screenshot-driver"
if [[ ! -x "$DRIVER" || "$ROOT/scripts/screenshot-driver.swift" -nt "$DRIVER" ]]; then
    echo "==> Compiling the capture driver"
    swiftc -O "$ROOT/scripts/screenshot-driver.swift" -o "$DRIVER"
fi

rm -rf "$WORK"
mkdir -p "$WORK/out" "$WORK/document"
cp "$DOCUMENT" "$WORK/document/"
DOC_COPY="$WORK/document/$(basename "$DOCUMENT")"

defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
defaults write "$BUNDLE_ID" isControlAPIEnabled -bool NO
defaults write "$BUNDLE_ID" isPCOLiveSyncEnabled -bool NO
defaults write "$BUNDLE_ID" hasLaunchedBefore -bool YES

ARGS=(-ScreenshotTour "$WORK/out" -ScreenshotDocument "$DOC_COPY" -ScreenshotAppearance "$APPEARANCE"
      -isControlAPIEnabled NO -isPCOLiveSyncEnabled NO -ApplePersistenceIgnoreState YES -NSQuitAlwaysKeepsWindows NO)
if [[ -n "$ONLY" ]]; then
    ARGS+=(-ScreenshotTourOnly "$ONLY")
    OUT="$OUT_ROOT/producer-mac-partial"
fi

echo "==> Running the tour"
pkill -f "^$BINARY" 2>/dev/null || true
open -n -a "$APP" --env THIRTEEN_EPHEMERAL_KEYCHAIN=1 --stdout "$WORK/app.log" --stderr "$WORK/app.log" --args "${ARGS[@]}"

APP_PID=""
for _ in $(seq 1 100); do
    APP_PID="$(pgrep -f "^$BINARY" | head -1 || true)"
    [[ -n "$APP_PID" ]] && break
    sleep 0.2
done
[[ -n "$APP_PID" ]] || { echo "the app did not start" >&2; exit 1; }

cleanup() {
    if kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null || true
        sleep 1
        kill -9 "$APP_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

STATUS=0
caffeinate -dimsu "$DRIVER" --work "$WORK/out" --out "$OUT" --pid "$APP_PID" \
    --version "$VERSION" --build "$BUILD" --commit "$COMMIT" --appearance "$APPEARANCE" --timeout 900 || STATUS=$?

for _ in $(seq 1 50); do
    kill -0 "$APP_PID" 2>/dev/null || break
    sleep 0.2
done

if [[ $STATUS -eq 0 && -z "$ONLY" ]]; then
    rm -rf "$OUT_ROOT/producer-mac-partial"
    ln -sfn "$VERSION-$BUILD" "$ROOT/Screenshots/latest"
fi
[[ $STATUS -eq 0 ]] && echo "==> Wrote $OUT"
exit $STATUS
