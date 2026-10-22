#ifndef DISPLAY_MODE_BRIDGE_H
#define DISPLAY_MODE_BRIDGE_H

#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    CGDirectDisplayID displayID;
    uint32_t currentModeID;
    uint32_t lowDPIModeID;
    uint32_t highDPIModeID;
    uint32_t logicalWidth;
    uint32_t logicalHeight;
    uint32_t pixelWidth;
    uint32_t pixelHeight;
    double refreshRateHz;
    bool isBuiltin;
    bool isHiDPI;
    bool canToggle;
} HDDisplayState;

typedef enum {
    HDResultOK = 0,
    HDResultNoDisplays = 1,
    HDResultDisplayNotFound = 2,
    HDResultModeUnavailable = 3,
    HDResultBeginFailed = 4,
    HDResultConfigureFailed = 5,
    HDResultCommitFailed = 6,
    HDResultVerificationFailed = 7
} HDResult;

// Returns the number of online displays. Writes at most capacity entries.
uint32_t HDReadDisplays(HDDisplayState *states, uint32_t capacity);
// Resolves the target again before switching, then verifies the resulting mode and geometry.
HDResult HDSetHiDPI(CGDirectDisplayID displayID, bool enabled, HDDisplayState *resultingState);

#ifdef __cplusplus
}
#endif
#endif
