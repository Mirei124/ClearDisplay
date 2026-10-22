#!/bin/zsh
set -euo pipefail
app_root="${0:A:h}"
swift format format --in-place --recursive "${app_root}/HiDPIApp" "${app_root}/DisplayCore" "${app_root}/Tests"
