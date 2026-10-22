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

The `Tests/` programs are manual hardware probes. CI runs formatting, C static warnings, plist validation and a full arm64 build; it does not change display settings.

## Current hardware limits

- The external display can report 8/10/12 bpc color mode candidates, but the current hardware selection and a verified setter are still unknown. Bit-depth selection is therefore pending.
- DDC controls are enabled only when one external display and one unambiguous DDC channel are present.
- Software gamma and color temperature adjust the CoreGraphics transfer formula. The app saves a recovery snapshot and restores it on normal quit or a later launch. A custom original gamma table that cannot be represented as a formula cannot be fully restored by this path.
- HDR uses the private MonitorPanel framework. Display controls should be tested again on each macOS release and monitor model.

## Direct distribution

```sh
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./package.sh
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' NOTARY_PROFILE='HiDPI-notary' NOTARIZE=1 ./package.sh
```

The first command signs a release app and creates `dist/HiDPI-VERSION-arm64.zip`. The second submits it for notarization, staples the ticket to the app, and recreates the zip. Configure `NOTARY_PROFILE` locally with `xcrun notarytool store-credentials`; do not store credentials in the repository. For a local, unsigned archive, use `ALLOW_UNSIGNED=1 ./package.sh`.

Update `CFBundleShortVersionString`, `CFBundleVersion`, and the final bundle identifier in `HiDPIApp/Info.plist` before distribution. Verify the signed archive on a clean Mac before release.
