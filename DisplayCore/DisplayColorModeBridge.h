#ifndef DISPLAY_COLOR_MODE_BRIDGE_H
#define DISPLAY_COLOR_MODE_BRIDGE_H
#include <CoreGraphics/CoreGraphics.h>
#include <stdint.h>
typedef struct {
  uint32_t elementID, bitsPerComponent, pixelEncodingRaw, dynamicRangeRaw, eotfRaw;
} HDColorElement;
uint32_t HDEnumerateColorElements(CGDirectDisplayID display, HDColorElement *items, uint32_t capacity);
#endif
