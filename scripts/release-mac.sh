#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Triston Yoder

set -euo pipefail

: "${NOTARY_KEY:?path to the App Store Connect .p8 key}"
: "${NOTARY_KEY_ID:?App Store Connect key id}"
: "${NOTARY_ISSUER:?App Store Connect issuer id}"

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

version="$(sed -n 's/^MARKETING_VERSION *= *//p' Config/Base.xcconfig)"
[ -n "$version" ] || { echo "MARKETING_VERSION missing from Config/Base.xcconfig"; exit 1; }

out="${RELEASE_DIR:-$root/build/release-$version}"
derived="$out/DerivedData"
rm -rf "$out"
mkdir -p "$out/stage-producer" "$out/stage-pager"

xcodegen generate

build() {
  xcodebuild -scheme "$1" -configuration Release -destination 'platform=macOS' \
    -derivedDataPath "$derived" -allowProvisioningUpdates \
    ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    OTHER_CODE_SIGN_FLAGS="--timestamp" build
}

notarize() {
  xcrun notarytool submit "$1" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
}

build ProducerMac
build PagerMac

products="$derived/Build/Products/Release"
producer_app="$products/13 Years Producer.app"
pager_app="$products/13 Years.app"

for app in "$producer_app" "$pager_app"; do
  ditto -c -k --keepParent "$app" "$out/$(basename "$app").zip"
  notarize "$out/$(basename "$app").zip"
  xcrun stapler staple "$app"
done

ditto "$producer_app" "$out/stage-producer/13 Years Producer.app"
ditto "$pager_app" "$out/stage-producer/13 Years Pager.app"
ln -s /Applications "$out/stage-producer/Applications"
ditto "$pager_app" "$out/stage-pager/13 Years.app"
ln -s /Applications "$out/stage-pager/Applications"

identity="Developer ID Application"

make_dmg() {
  local volume="$1" stage="$2" dmg="$3"
  hdiutil create -volname "$volume" -srcfolder "$stage" -ov -format UDZO "$dmg"
  codesign --sign "$identity" --timestamp "$dmg"
  notarize "$dmg"
  xcrun stapler staple "$dmg"
}

make_dmg "13 Years Producer $version" "$out/stage-producer" "$out/13-Years-Producer-$version.dmg"
make_dmg "13 Years $version" "$out/stage-pager" "$out/13-Years-$version.dmg"

rm -rf "$out/stage-producer" "$out/stage-pager" "$out"/*.zip
shasum -a 256 "$out"/*.dmg | tee "$out/SHA256SUMS"
echo "release artifacts in $out"
