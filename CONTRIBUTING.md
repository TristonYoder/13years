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
