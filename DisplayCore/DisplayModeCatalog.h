#ifndef DISPLAY_MODE_CATALOG_H
#define DISPLAY_MODE_CATALOG_H

#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint32_t modeID;
    uint32_t logicalWidth, logicalHeight;
    uint32_t pixelWidth, pixelHeight;
    uint32_t refreshMilliHz;
    uint32_t depth;
    bool isHiDPI, isCurrent, isNative, isSelectable;
} HDModeOption;

typedef enum {
    HDModeApplyOK = 0,
    HDModeApplyDisplayGone,
    HDModeApplyModeGone,
    HDModeApplyUnsafeColorChange,
    HDModeApplyBeginFailed,
    HDModeApplyConfigureFailed,
    HDModeApplyCommitFailed,
    HDModeApplyReadbackFailed
} HDModeApplyResult;

// Returns the total number of modes. Writes at most capacity entries. Re-query
// after any display reconfiguration; mode IDs are not stable across sessions.
uint32_t HDEnumerateModes(CGDirectDisplayID displayID, HDModeOption *options, uint32_t capacity);

// Re-enumerates immediately before applying and rejects color-depth changes.
// The resulting mode ID is checked after macOS commits the configuration.
HDModeApplyResult HDApplyMode(CGDirectDisplayID displayID, uint32_t modeID);

#endif
