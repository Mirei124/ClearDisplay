#!/bin/zsh
set -euo pipefail

app_root="${0:A:h:h}"
mkdir -p "${app_root}/build/IconModuleCache"
CLANG_MODULE_CACHE_PATH="${app_root}/build/IconModuleCache" \
  swift "${app_root}/tools/make-dmg-icon.swift"
