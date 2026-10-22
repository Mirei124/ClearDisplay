#!/bin/zsh
set -euo pipefail
app_root="${0:A:h}"
dist_root="${DIST_DIR:-${app_root}/dist}"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "${app_root}/HiDPIApp/Info.plist")"
app_path="${app_root}/build/release/ClearDisplay.app"
archive="${dist_root}/ClearDisplay-${version}-arm64.zip"
mkdir -p "${dist_root}"
CONFIGURATION=release "${app_root}/build.sh" "${app_root}/build/release"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --timestamp \
    --sign "${SIGN_IDENTITY}" "${app_path}"
  codesign --verify --deep --strict --verbose=2 "${app_path}"
elif [[ "${ALLOW_UNSIGNED:-0}" != "1" ]]; then
  print -u2 "Set SIGN_IDENTITY to a Developer ID Application identity, or ALLOW_UNSIGNED=1 for local packaging."
  exit 2
fi
if [[ "${NOTARIZE:-0}" == "1" ]]; then
  if [[ -z "${SIGN_IDENTITY:-}" || -z "${NOTARY_PROFILE:-}" ]]; then
    print -u2 "Notarization requires SIGN_IDENTITY and NOTARY_PROFILE."
    exit 2
  fi
  ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${archive}"
  xcrun notarytool submit "${archive}" --keychain-profile "${NOTARY_PROFILE}" --wait
  xcrun stapler staple "${app_path}"
fi
ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${archive}"
print "Packaged ${archive}"
