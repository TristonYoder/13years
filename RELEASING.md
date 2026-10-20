# Releasing

Every release follows the same shape. This is the standing norm; change it here, not ad hoc.

## Versioning

- Releases bump the **minor** version and reset the patch: `1.2.x` becomes `1.3.0`.
- One version number covers the Producer (Mac, iPad), the Pagers (Mac, iPhone, iPad, Apple TV) and the Companion module. Bump `MARKETING_VERSION` in `Config/Base.xcconfig`, raise `CURRENT_PROJECT_VERSION` there by one (every TestFlight upload needs a new build number), and run `npm run sync-version -- <version>` in the Companion module.
- The Watch app keeps its own version.

## Mac downloads

Two notarized, stapled disk images are attached to the GitHub release:

| File | Contents |
| --- | --- |
| `13-Years-Producer-<version>.dmg` | `13 Years Producer.app` and `13 Years Pager.app`, plus an Applications shortcut |
| `13-Years-<version>.dmg` | `13 Years.app` (the Pager) only, plus an Applications shortcut |

The Pager app is named `13 Years`, the same as the iPhone, iPad and Apple TV apps. Inside the Producer disk image it is renamed `13 Years Pager.app` so it reads clearly next to the Producer.

`scripts/release-mac.sh` builds both Mac apps with the hardened runtime, notarizes and staples each app, builds both disk images, signs, notarizes and staples them, and writes `SHA256SUMS`. It needs `NOTARY_KEY` (path to the App Store Connect `.p8`), `NOTARY_KEY_ID` and `NOTARY_ISSUER`.

## Steps

1. Branch work lands through a pull request into `main`; the version bump is part of that pull request.
2. Run `python3 scripts/generate-palette.py --check`; a non-zero exit means a generated color file drifted from `Design/palette.json`, so rerun the script without `--check` and commit the result. Then run the full test suites (Mac, web pager, ESP32 host test, Companion unit and contract) and build every scheme: ProducerMac, ProducerIOS, Pager, PagerTV, PagerWatch, PagerMac.
3. Regenerate the bundled pager firmware (`Hardware/esp32/tools/build-firmware.py --out Sources/ProducerMac/Resources/13years-pager-merged.bin`) if anything under `Hardware/esp32/src` changed.
4. Merge the pull request, then tag `v<version>` on the merge commit.
5. Companion module: merge its pull request and push the matching `v<version>` tag. Its release workflow builds the package and attaches the `.tgz`.
6. Run `scripts/release-mac.sh` and create the GitHub release `13 Years <version>` for the tag with both disk images attached. The release notes describe what changed and **link to the matching Companion module release**.
7. Delete the branches that fed the release, locally and on GitHub, once they are merged.
8. Share the release page.

The Pager for iPhone, iPad, Apple TV and Mac ships through TestFlight as one App Store record (`dev.7co.13years.pager`): archive each platform in Xcode and upload it from the Organizer. These builds are not attached to the GitHub release. Archives sign automatically with the 7 and Co LLC team (`DEVELOPMENT_TEAM` in `Config/Local.xcconfig`); the Organizer re-signs for distribution on upload.
