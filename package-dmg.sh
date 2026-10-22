#!/bin/zsh
set -euo pipefail

app_root="${0:A:h}"
dist_root="${DIST_DIR:-${app_root}/dist}"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "${app_root}/HiDPIApp/Info.plist")"
app_path="${app_root}/build/release/ClearDisplay.app"
image="${dist_root}/ClearDisplay-${version}-arm64.dmg"

if [[ "${NOTARIZE:-0}" == "1" && ( -z "${SIGN_IDENTITY:-}" || -z "${NOTARY_PROFILE:-}" ) ]]; then
  print -u2 "Notarization requires SIGN_IDENTITY and NOTARY_PROFILE."
  exit 2
fi
if [[ -z "${SIGN_IDENTITY:-}" && "${ALLOW_UNSIGNED:-0}" != "1" ]]; then
  print -u2 "Set SIGN_IDENTITY to a Developer ID Application identity, or ALLOW_UNSIGNED=1 for local packaging."
  exit 2
fi

mkdir -p "${dist_root}"
CONFIGURATION=release "${app_root}/build.sh" "${app_root}/build/release"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --timestamp \
    --sign "${SIGN_IDENTITY}" "${app_path}"
  codesign --verify --deep --strict --verbose=2 "${app_path}"
fi

staging="$(mktemp -d "${TMPDIR:-/tmp}/cleardisplay-dmg.XXXXXX")"
trap 'rm -rf -- "${staging}"' EXIT
ditto "${app_path}" "${staging}/ClearDisplay.app"
ln -s /Applications "${staging}/Applications"
hdiutil create -volname "ClearDisplay ${version}" \
  -srcfolder "${staging}" -format UDZO -ov "${image}"
hdiutil verify -quiet "${image}"

if [[ "${NOTARIZE:-0}" == "1" ]]; then
  xcrun notarytool submit "${image}" --keychain-profile "${NOTARY_PROFILE}" --wait
  xcrun stapler staple "${image}"
fi
print "Packaged ${image}"
