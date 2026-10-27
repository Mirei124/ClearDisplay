#ifndef DISPLAY_CONNECTION_BRIDGE_H
#define DISPLAY_CONNECTION_BRIDGE_H

#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stdint.h>

typedef enum {
    HDConnectionOK = 0,
    HDConnectionUnsupported,
    HDConnectionDisplayGone,
    HDConnectionLastDisplay,
    HDConnectionBeginFailed,
    HDConnectionConfigureFailed,
    HDConnectionCommitFailed,
    HDConnectionVerificationFailed
} HDConnectionResult;

// SkyLight includes displays disabled by this process, unlike CGGetOnlineDisplayList.
uint32_t HDAllDisplayIDs(CGDirectDisplayID *ids, uint32_t capacity);
bool HDConnectionSupported(void);
bool HDDisplayIsEnabled(CGDirectDisplayID displayID);
// Returns false on enumeration failure, distinct from a successful zero count.
bool HDGetActivePhysicalDisplayCount(uint32_t *count);
HDConnectionResult HDSetDisplayEnabled(CGDirectDisplayID displayID, bool enabled);

#endif
