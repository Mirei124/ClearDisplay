#ifndef DISPLAY_MODE_COMPATIBILITY_H
#define DISPLAY_MODE_COMPATIBILITY_H

#include <IOKit/graphics/IOGraphicsTypes.h>
#include <stdbool.h>
#include <stdint.h>

// Safe/default describe a mode's status, not its pixel format. macOS can add
// these bits to the active native mode when it becomes the sole display.
// Preserve the existing checks for depth and all other low flag attributes.
static inline bool HDModeAttributesCompatible(uint32_t currentFlags, uint32_t currentDepth,
                                               uint32_t candidateFlags, uint32_t candidateDepth) {
    const uint32_t mask = 0x0000ffffu & ~(kDisplayModeSafeFlag | kDisplayModeDefaultFlag);
    return currentDepth == candidateDepth && !(candidateFlags & 0x40000000u) &&
        (currentFlags & mask) == (candidateFlags & mask);
}

#endif
