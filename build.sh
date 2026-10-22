#!/bin/zsh
set -euo pipefail
app_root="${0:A:h}"
build_root="${1:-${app_root}/build}"
app_bundle="${build_root}/ClearDisplay.app"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
configuration="${CONFIGURATION:-debug}"
case "${configuration}" in
  debug) swift_flags=(-g -Onone -D DEBUG); clang_flags=(-g -O0) ;;
  release) swift_flags=(-O -whole-module-optimization); clang_flags=(-O2) ;;
  *) print -u2 "CONFIGURATION must be debug or release"; exit 2 ;;
esac
swift_sources=("${app_root}"/{HiDPIApp,DisplayCore}/*.swift(N))
c_sources=("${app_root}"/DisplayCore/*.c(N))
if (( ${#swift_sources} == 0 )); then
  print -u2 "No Swift sources found"
  exit 1
fi
mkdir -p "${app_bundle}/Contents/MacOS" "${app_bundle}/Contents/Resources" "${build_root}/ModuleCache"
export CLANG_MODULE_CACHE_PATH="${build_root}/ModuleCache"
objects=()
for source in "${c_sources[@]}"; do
  object="${build_root}/${source:t:r}.o"
  clang -arch arm64 -isysroot "${sdk_path}" -mmacosx-version-min=14.0 \
    -Wall -Wextra -Werror "${clang_flags[@]}" -c "${source}" -o "${object}"
  objects+=("${object}")
done
swiftc -parse-as-library -target arm64-apple-macos14.0 -sdk "${sdk_path}" \
  -module-cache-path "${build_root}/ModuleCache" \
  -import-objc-header "${app_root}/HiDPIApp/HiDPIApp-Bridging-Header.h" \
  "${swift_flags[@]}" "${swift_sources[@]}" "${objects[@]}" \
  -framework AppKit -framework CoreGraphics -framework IOKit -framework SwiftUI \
  -o "${app_bundle}/Contents/MacOS/ClearDisplay"
cp "${app_root}/HiDPIApp/Info.plist" "${app_bundle}/Contents/Info.plist"
plutil -lint "${app_bundle}/Contents/Info.plist"
print "Built ${app_bundle} (${configuration})"
