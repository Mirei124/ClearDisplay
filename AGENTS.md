# ClearDisplay contributor instructions

Read [docs/lessons-learned.md](docs/lessons-learned.md) before changing display controls or the menu UI. It records confirmed regressions, hardware limits, and rules that must survive refactors.

## Project boundaries

- This repository contains ClearDisplay. Do not edit the sibling Crisp or BetterDisplay sources or bundles as part of a ClearDisplay change.
- Target Apple Silicon and macOS 14 or later. Keep `HiDPIApp/Info.plist`, build scripts, README, and release tags consistent.
- Keep hardware access in `DisplayCore`. SwiftUI views should call the controller rather than private display APIs directly.

## Before finishing a change

- Run `./format.sh`, `./check.sh`, and `git diff --check`.
- Verify menu layout changes in the Debug preview, then check resizing and interaction in the actual menu bar popup when the change involves window height or click targets. The preview uses a different window host.
- Display mutations need a captured original value, a readback after the change, and restoration. Never use a manual hardware probe as an automatic CI test.
- Update README screenshots when a layout change makes them materially inaccurate. Screenshots in `docs/screenshots/` must come from a running build and must not show a changed display setting as a verified result unless it was read back.

## Release

- `package.sh` builds the Release app itself. Do not require a separate `build.sh` step.
- Tag a committed release as `v<CFBundleShortVersionString>` after checking that the bundle version, README, docs, and worktree are ready. Do not move an existing release tag without explicit authorization.
