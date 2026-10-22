# HiDPI

macOS 14+ Apple Silicon menu bar app for display controls. The display mode bridge uses private CoreGraphics Services APIs. It is intended for direct distribution, not the Mac App Store.

## Requirements

- Apple Silicon Mac running macOS 14 or later
- Xcode Command Line Tools (`xcode-select --install`)

No package manager or third party dependencies are required. The command line build is the canonical build; full Xcode is optional.

## Development

```sh
./build.sh                  # debug app in build/HiDPI.app
./format.sh                 # apply Swift formatting
./check.sh                  # strict Swift lint, C warnings, plist check, debug build
```

`swift format` ships with the installed Swift toolchain. Run `format.sh` after changing Swift files. `check.sh` compiles the app but does not change the active display mode.

For UI inspection, a Debug build can open the same menu content in a normal window:

```sh
CONFIGURATION=debug ./build.sh ./build/preview
HIDPI_UI_PREVIEW=1 ./build/preview/HiDPI.app/Contents/MacOS/HiDPI
```

The preview window is omitted from Release builds. Viewing it reads display state; using its controls changes the real display.

The `Tests/` programs are manual hardware probes. CI runs formatting, C static warnings, plist validation and a full arm64 build; it does not change display settings.

## Current hardware limits

- The external display can report 8/10/12 bpc color mode candidates, but the current hardware selection and a verified setter are still unknown. Bit-depth selection is therefore pending.
- DDC controls are enabled only when one external display and one unambiguous DDC channel are present.
- Software gamma and color temperature adjust the CoreGraphics transfer formula. The app saves a recovery snapshot and restores it on normal quit or a later launch. A custom original gamma table that cannot be represented as a formula cannot be fully restored by this path.
- HDR uses the private MonitorPanel framework. Display controls should be tested again on each macOS release and monitor model.
- Night Shift and integrated True Tone use private CoreBrightness interfaces. The True Tone switch is shown only for a supported built-in display; no external per-display setter has been verified.
- System Light/Dark appearance is read from the current user's preferences and changed through System Events. The first change may request Automation access. Automatic appearance is recognized but cannot be set by the current service; while it is active, the menu leaves the system schedule intact.

## Hardware QA before release

On the target Mac, open the menu bar panel and verify that both screens have the right names, sizes and current values; the built-in screen must not show a HiDPI switch. For each available control, record the original setting, apply one small change, confirm the displayed readback, then restore it. In particular, check mode changes, brightness, layout/primary/rotation/mirroring, disconnect/reconnect, HDR, ICC, DDC contrast and temperature, and software gamma/temperature. Check the panel again after unplugging and reconnecting the external monitor. The bit-depth selector is deferred until a reliable current-value getter and setter are found.

The app's manual smoke probes under `Tests/` cover backend behavior on one Mac with one external display. Multi-monitor DDC pairing and full menu visual behavior require additional hardware and UI QA.

## Direct distribution

```sh
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./package.sh
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' NOTARY_PROFILE='HiDPI-notary' NOTARIZE=1 ./package.sh
```

The first command signs a release app and creates `dist/HiDPI-VERSION-arm64.zip`. The second submits it for notarization, staples the ticket to the app, and recreates the zip. Configure `NOTARY_PROFILE` locally with `xcrun notarytool store-credentials`; do not store credentials in the repository. For a local, unsigned archive, use `ALLOW_UNSIGNED=1 ./package.sh`.

Update `CFBundleShortVersionString`, `CFBundleVersion`, and the final bundle identifier in `HiDPIApp/Info.plist` before distribution. Verify the signed archive on a clean Mac before release.
