# ClearDisplay app icon

The approved source is `ClearDisplay-icon-glass-gray.png`: a white monitor with a light-gray screen on a pale-blue glass background. The image was made with the built-in image generator; `prompt-glass-gray.txt` records the final edit prompt.

Run `./tools/build-app-icon.sh` from the repository root after replacing the source image. It uses macOS `sips` and `iconutil` to create `assets/ClearDisplay.icns`, with standard 1× and 2× representations from 16 to 1024 pixels.

Commit the source and generated ICNS together. `build.sh` copies the ICNS into `Contents/Resources`, and `CFBundleIconFile` selects it for the application. Both Debug and Release builds use this resource. The menu bar continues to use the monochrome `display` system symbol.
