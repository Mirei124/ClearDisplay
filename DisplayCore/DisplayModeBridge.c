#include "DisplayModeBridge.h"
#include "DisplayModeCompatibility.h"
#include <math.h>
#include <string.h>
#include <unistd.h>

typedef struct {
    uint32_t modeNumber, flags, width, height, depth, dc2[42];
    uint16_t dc3, freq;
    uint32_t dc4[4];
    float density;
} CGSDisplayModeDescription;

extern CGError CGSGetNumberOfDisplayModes(CGDirectDisplayID display, int *count);
extern CGError CGSGetDisplayModeDescriptionOfLength(CGDirectDisplayID display, int index,
                                                    CGSDisplayModeDescription *mode, int length);
extern CGError CGSConfigureDisplayMode(CGDisplayConfigRef config, CGDirectDisplayID display,
                                       int32_t modeNumber);

static bool is_online(CGDirectDisplayID wanted) {
    uint32_t count = 0;
    if (CGGetOnlineDisplayList(0, NULL, &count) != kCGErrorSuccess || count == 0) return false;
    CGDirectDisplayID ids[count];
    if (CGGetOnlineDisplayList(count, ids, &count) != kCGErrorSuccess) return false;
    for (uint32_t i = 0; i < count; ++i) if (ids[i] == wanted) return true;
    return false;
}

static bool read_one(CGDirectDisplayID id, HDDisplayState *state) {
    CGDisplayModeRef current = CGDisplayCopyDisplayMode(id);
    if (!current) return false;
    memset(state, 0, sizeof(*state));
    state->displayID = id;
    state->currentModeID = (uint32_t)CGDisplayModeGetIODisplayModeID(current);
    state->logicalWidth = (uint32_t)CGDisplayModeGetWidth(current);
    state->logicalHeight = (uint32_t)CGDisplayModeGetHeight(current);
    state->pixelWidth = (uint32_t)CGDisplayModeGetPixelWidth(current);
    state->pixelHeight = (uint32_t)CGDisplayModeGetPixelHeight(current);
    state->refreshRateHz = CGDisplayModeGetRefreshRate(current);
    state->isBuiltin = CGDisplayIsBuiltin(id);
    state->isHiDPI = state->logicalWidth > 0 &&
        state->pixelWidth >= state->logicalWidth * 3 / 2;
    CFRelease(current);

    int count = 0;
    if (CGSGetNumberOfDisplayModes(id, &count) != kCGErrorSuccess || count <= 0) return true;
    CGSDisplayModeDescription currentDescription = {0};
    bool foundCurrent = false;
    for (int i = 0; i < count; ++i) {
        CGSDisplayModeDescription mode = {0};
        if (CGSGetDisplayModeDescriptionOfLength(id, i, &mode, sizeof(mode)) == kCGErrorSuccess &&
            mode.modeNumber == state->currentModeID) {
            currentDescription = mode;
            foundCurrent = true;
            if (state->refreshRateHz <= 0) state->refreshRateHz = mode.freq;
            break;
        }
    }
    // If the active mode is absent from CGS, its color attributes cannot be
    // preserved reliably. Leave the switch unavailable rather than guessing.
    if (!foundCurrent || !currentDescription.freq) return true;
    bool ambiguousLow = false, ambiguousHigh = false;
    for (int i = 0; i < count; ++i) {
        CGSDisplayModeDescription mode = {0};
        if (CGSGetDisplayModeDescriptionOfLength(id, i, &mode, sizeof(mode)) != kCGErrorSuccess) continue;
        if (mode.width != state->logicalWidth || mode.height != state->logicalHeight ||
            mode.freq != currentDescription.freq ||
            !HDModeAttributesCompatible(currentDescription.flags, currentDescription.depth,
                                        mode.flags, mode.depth)) continue;
        bool hiDPI = mode.density >= 1.5f;
        uint32_t *candidate = hiDPI ? &state->highDPIModeID : &state->lowDPIModeID;
        bool *ambiguous = hiDPI ? &ambiguousHigh : &ambiguousLow;
        if (*candidate && *candidate != mode.modeNumber) *ambiguous = true;
        else *candidate = mode.modeNumber;
    }
    state->canToggle = !ambiguousLow && !ambiguousHigh &&
        state->lowDPIModeID != 0 && state->highDPIModeID != 0;
    return true;
}

uint32_t HDReadDisplays(HDDisplayState *states, uint32_t capacity) {
    uint32_t count = 0;
    if (CGGetOnlineDisplayList(0, NULL, &count) != kCGErrorSuccess || count == 0) return 0;
    CGDirectDisplayID ids[count];
    if (CGGetOnlineDisplayList(count, ids, &count) != kCGErrorSuccess) return 0;
    if (states) {
        uint32_t limit = count < capacity ? count : capacity;
        for (uint32_t i = 0; i < limit; ++i) {
            if (!read_one(ids[i], &states[i])) memset(&states[i], 0, sizeof(states[i]));
        }
    }
    return count;
}

HDResult HDSetHiDPI(CGDirectDisplayID displayID, bool enabled, HDDisplayState *resultingState) {
    if (!is_online(displayID)) return HDResultDisplayNotFound;
    HDDisplayState before;
    if (!read_one(displayID, &before)) return HDResultDisplayNotFound;
    if (!before.canToggle) return HDResultModeUnavailable;
    uint32_t target = enabled ? before.highDPIModeID : before.lowDPIModeID;
    if (target != before.currentModeID) {
        CGDisplayConfigRef config = NULL;
        if (CGBeginDisplayConfiguration(&config) != kCGErrorSuccess || !config) return HDResultBeginFailed;
        if (CGSConfigureDisplayMode(config, displayID, (int32_t)target) != kCGErrorSuccess) {
            CGCancelDisplayConfiguration(config);
            return HDResultConfigureFailed;
        }
        if (CGCompleteDisplayConfiguration(config, kCGConfigureForSession) != kCGErrorSuccess)
            return HDResultCommitFailed;
    }
    for (int attempt = 0; attempt < 20; ++attempt) {
        HDDisplayState after;
        if (read_one(displayID, &after) && after.currentModeID == target &&
            after.logicalWidth == before.logicalWidth && after.logicalHeight == before.logicalHeight &&
            fabs(after.refreshRateHz - before.refreshRateHz) < 0.5 && after.isHiDPI == enabled) {
            if (resultingState) *resultingState = after;
            return HDResultOK;
        }
        usleep(100000);
    }
    return HDResultVerificationFailed;
}
