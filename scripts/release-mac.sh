#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Triston Yoder

set -euo pipefail

op_item="${NOTARY_OP_ITEM:-App Store Connect API (13 Years notarization)}"

from_1password() {
  command -v op >/dev/null 2>&1 || { echo "Set NOTARY_KEY, NOTARY_KEY_ID and NOTARY_ISSUER, or install and sign in to the 1Password CLI (op)."; exit 1; }
  op item get "$op_item" --fields "$1" 2>/dev/null || { echo "Could not read '$1' from the 1Password item '$op_item'. Is op signed in?"; exit 1; }
}

if [ -z "${NOTARY_KEY:-}" ]; then
  key_file="$(from_1password key_file)"
  NOTARY_KEY="${key_file/#\~/$HOME}"
fi
[ -n "${NOTARY_KEY_ID:-}" ] || NOTARY_KEY_ID="$(from_1password key_id)"
[ -n "${NOTARY_ISSUER:-}" ] || NOTARY_ISSUER="$(from_1password issuer_id)"
[ -f "$NOTARY_KEY" ] || { echo "The App Store Connect key file is missing: $NOTARY_KEY"; exit 1; }
export NOTARY_KEY NOTARY_KEY_ID NOTARY_ISSUER

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

version="$(sed -n 's/^MARKETING_VERSION *= *//p' Config/Base.xcconfig)"
[ -n "$version" ] || { echo "MARKETING_VERSION missing from Config/Base.xcconfig"; exit 1; }

out="${RELEASE_DIR:-$root/build/release-$version}"
derived="$out/DerivedData"
rm -rf "$out"
mkdir -p "$out/stage-producer" "$out/stage-pager"

xcodegen generate

team="${DEVELOPMENT_TEAM:-$(sed -n 's/^ *DEVELOPMENT_TEAM *= *//p' Config/Local.xcconfig 2>/dev/null | head -1)}"
[ -n "$team" ] || { echo "DEVELOPMENT_TEAM missing (set it or add it to Config/Local.xcconfig)"; exit 1; }

build() {
  xcodebuild -scheme "$1" -configuration Release -destination 'platform=macOS' \
    -derivedDataPath "$derived" -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM="$team" \
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
(cd "$out" && shasum -a 256 *.dmg | tee SHA256SUMS)
echo "release artifacts in $out"
