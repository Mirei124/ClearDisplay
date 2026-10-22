#!/bin/zsh
set -euo pipefail
app_root="${0:A:h}"
swift format lint --strict --recursive "${app_root}/HiDPIApp" "${app_root}/DisplayCore" "${app_root}/Tests" "${app_root}/tools"
for source in "${app_root}"/{DisplayCore,Tests}/*.c(N); do
  clang -arch arm64 -mmacosx-version-min=14.0 -Wall -Wextra -Werror -fsyntax-only "${source}"
done
plutil -lint "${app_root}/HiDPIApp/Info.plist"
CONFIGURATION=debug "${app_root}/build.sh" "${app_root}/build/check"
