# Contributing

Thanks for helping with 13 Years.

## Contributor License Agreement

Before a pull request can be merged, you need to agree to the [CLA](CLA.md). A bot comments on your first pull request. Reply with the sentence it asks for and the check turns green. You only sign once.

The CLA lets the maintainer distribute the project under terms other than the AGPL where needed, for example in an app store. You keep the copyright in your work.

## Development

- Build setup is in the [README](README.md). The Xcode project is generated from `project.yml`; do not commit the generated project.
- Source files carry two header lines (`SPDX-License-Identifier: AGPL-3.0-only` and the copyright line). Keep them on new hand-written source files.
- The code base does not use comments. Put design notes in the pull request description instead.
- Run `cd Server && npm test` for relay changes. Changes under `Hardware/esp32/src` need the bundled firmware image rebuilt; see `Hardware/esp32/README.md`.

## Screenshots

Every pull request that adds or changes something a person can see adds a screenshot step for it in the same pull request. That includes a feature, screen, sheet, popover, alert, confirmation dialog, menu item, or pager layout or state. The screenshots are versioned per build and feed the documentation, so a surface without a step is missing from the docs.

- Step lists: `Sources/ProducerMac/ScreenshotTour/ScreenshotTourSteps.swift` for the Producer for Mac, and `Sources/ScreenshotTour/Pager/PagerScreenshotTourSteps.swift` for every pager (Mac, iPhone, iPad, Apple TV).
- Give the step a new dotted id that names the surface, for example `runsheet.waypoint-editor`. Never rename or reuse an existing id. Add new steps after the existing ones.
- If a view holds the sheet or popover in private `@State`, add a one-line `.onScreenshotTourSignal("<id>")` hook to that view and post the signal from the step.
- Close what the step opens. Dialogs that delete or clear something are only photographed, then cancelled.
- If the surface can't be reached (it needs a real touch, the network, a sign-in or another device), add the step anyway and throw `TourUIError.skipped("<short reason>")`.
- Check it with `scripts/capture-screenshots.sh --app <app> --only <id>` and look at the image. Apps: `producer-mac`, `pager-mac`, `pager-ios`, `pager-ipad`, `pager-tv`. The Mac apps need Screen Recording permission and an unlocked screen. iPad simulators need Full Screen Apps mode.

Every release captures the full set with `scripts/capture-screenshots.sh --app all`, light and then `--appearance dark`.
