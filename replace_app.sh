#!/bin/bash

set -euo pipefail

osascript -e 'quit app "ClearDisplay"'
rm -rf /Applications/ClearDisplay.app
CONFIGURATION=release ./build.sh
cp -r ./build/ClearDisplay.app /Applications/
open /Applications/ClearDisplay.app
