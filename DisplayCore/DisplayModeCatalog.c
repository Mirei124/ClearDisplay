#include "DisplayModeCatalog.h"
#include <math.h>
#include <string.h>
#include <unistd.h>

typedef struct {
    uint32_t modeNumber, flags, width, height, depth, dc2[42];
    uint16_t dc3, freq;
    uint32_t dc4[4];
    float density;
} HDPrivateMode;

extern CGError CGSGetNumberOfDisplayModes(CGDirectDisplayID display, int *count);
extern CGError CGSGetDisplayModeDescriptionOfLength(CGDirectDisplayID display, int index,
                                                   HDPrivateMode *mode, int length);
extern CGError CGSConfigureDisplayMode(CGDisplayConfigRef config, CGDirectDisplayID display,
                                      int32_t modeNumber);

static bool online(CGDirectDisplayID wanted) {
    uint32_t count = 0;
    if (CGGetOnlineDisplayList(0, NULL, &count) != kCGErrorSuccess || !count) return false;
    CGDirectDisplayID ids[count];
    if (CGGetOnlineDisplayList(count, ids, &count) != kCGErrorSuccess) return false;
    for (uint32_t i = 0; i < count; ++i) if (ids[i] == wanted) return true;
    return false;
}

static bool private_mode(CGDirectDisplayID display, int index, HDPrivateMode *mode) {
    memset(mode, 0, sizeof(*mode));
    return CGSGetDisplayModeDescriptionOfLength(display, index, mode, sizeof(*mode)) == kCGErrorSuccess;
}

static uint32_t mode_count(CGDirectDisplayID display) {
    int count = 0;
    if (CGSGetNumberOfDisplayModes(display, &count) != kCGErrorSuccess || count <= 0) return 0;
    return (uint32_t)count;
}

static bool current_private_mode(CGDirectDisplayID display, uint32_t currentID, HDPrivateMode *current) {
    uint32_t count = mode_count(display);
    for (uint32_t i = 0; i < count; ++i) {
        if (private_mode(display, (int)i, current) && current->modeNumber == currentID) return true;
    }
    return false;
}

static void native_size(CGDirectDisplayID display, uint32_t *width, uint32_t *height) {
    *width = 0;
    *height = 0;
    CFArrayRef publicModes = CGDisplayCopyAllDisplayModes(display, NULL);
    if (!publicModes) return;
    for (CFIndex i = 0; i < CFArrayGetCount(publicModes); ++i) {
        CGDisplayModeRef mode = (CGDisplayModeRef)CFArrayGetValueAtIndex(publicModes, i);
        size_t logicalWidth = CGDisplayModeGetWidth(mode);
        size_t logicalHeight = CGDisplayModeGetHeight(mode);
        size_t pixelWidth = CGDisplayModeGetPixelWidth(mode);
        size_t pixelHeight = CGDisplayModeGetPixelHeight(mode);
        if (logicalWidth != pixelWidth || logicalHeight != pixelHeight) continue;
        if ((uint64_t)pixelWidth * pixelHeight > (uint64_t)*width * *height) {
            *width = (uint32_t)pixelWidth;
            *height = (uint32_t)pixelHeight;
        }
    }
    CFRelease(publicModes);
}

uint32_t HDEnumerateModes(CGDirectDisplayID display, HDModeOption *options, uint32_t capacity) {
    if (!online(display)) return 0;
    CGDisplayModeRef current = CGDisplayCopyDisplayMode(display);
    if (!current) return 0;
    uint32_t currentID = (uint32_t)CGDisplayModeGetIODisplayModeID(current);
    HDPrivateMode currentPrivate = {0};
    bool hasCurrentPrivate = current_private_mode(display, currentID, &currentPrivate);
    uint32_t nativeWidth = 0, nativeHeight = 0;
    native_size(display, &nativeWidth, &nativeHeight);
    uint32_t count = mode_count(display);
    uint32_t written = 0;
    for (uint32_t i = 0; i < count; ++i) {
        HDPrivateMode mode;
        if (!private_mode(display, (int)i, &mode) || !mode.width || !mode.height ||
            !mode.modeNumber || (mode.flags & 0x40000000u)) continue;
        // The CGS structure exposes logical dimensions and density; the latter
        // yields the backing pixel dimensions even for modes hidden from CG.
        float density = mode.density > 0 ? mode.density : 1.0f;
        HDModeOption option = {0};
        option.modeID = mode.modeNumber;
        option.logicalWidth = mode.width;
        option.logicalHeight = mode.height;
        option.pixelWidth = (uint32_t)lroundf(mode.width * density);
        option.pixelHeight = (uint32_t)lroundf(mode.height * density);
        option.refreshMilliHz = (uint32_t)mode.freq * 1000;
        option.depth = mode.depth;
        option.isHiDPI = density >= 1.5f;
        option.isCurrent = mode.modeNumber == currentID;
        option.isNative = nativeWidth && option.pixelWidth == nativeWidth && option.pixelHeight == nativeHeight;
        // Mode IDs and undocumented flag bits vary by device. Only offer a
        // candidate that matches the active color depth and flag family.
        option.isSelectable = hasCurrentPrivate && mode.depth == currentPrivate.depth &&
            (mode.flags & 0x0000ffffu) == (currentPrivate.flags & 0x0000ffffu);
        if (options && written < capacity) options[written] = option;
        ++written;
    }
    CFRelease(current);
    return written;
}

HDModeApplyResult HDApplyMode(CGDirectDisplayID display, uint32_t modeID) {
    if (!online(display)) return HDModeApplyDisplayGone;
    CGDisplayModeRef current = CGDisplayCopyDisplayMode(display);
    if (!current) return HDModeApplyDisplayGone;
    uint32_t currentID = (uint32_t)CGDisplayModeGetIODisplayModeID(current);
    CFRelease(current);
    HDPrivateMode currentPrivate = {0};
    if (!current_private_mode(display, currentID, &currentPrivate)) return HDModeApplyUnsafeColorChange;
    HDPrivateMode candidate = {0};
    bool found = false;
    uint32_t count = mode_count(display);
    for (uint32_t i = 0; i < count; ++i) {
        HDPrivateMode mode;
        if (private_mode(display, (int)i, &mode) && mode.modeNumber == modeID &&
            mode.width && mode.height && !(mode.flags & 0x40000000u)) {
            candidate = mode;
            found = true;
            break;
        }
    }
    if (!found) return HDModeApplyModeGone;
    if (candidate.depth != currentPrivate.depth ||
        (candidate.flags & 0x0000ffffu) != (currentPrivate.flags & 0x0000ffffu))
        return HDModeApplyUnsafeColorChange;
    if (modeID == currentID) return HDModeApplyOK;
    CGDisplayConfigRef config = NULL;
    if (CGBeginDisplayConfiguration(&config) != kCGErrorSuccess || !config) return HDModeApplyBeginFailed;
    if (CGSConfigureDisplayMode(config, display, (int32_t)modeID) != kCGErrorSuccess) {
        CGCancelDisplayConfiguration(config);
        return HDModeApplyConfigureFailed;
    }
    if (CGCompleteDisplayConfiguration(config, kCGConfigureForSession) != kCGErrorSuccess)
        return HDModeApplyCommitFailed;
    for (int attempt = 0; attempt < 20; ++attempt) {
        CGDisplayModeRef after = CGDisplayCopyDisplayMode(display);
        if (after) {
            bool success = (uint32_t)CGDisplayModeGetIODisplayModeID(after) == modeID;
            CFRelease(after);
            if (success) return HDModeApplyOK;
        }
        usleep(100000);
    }
    return HDModeApplyReadbackFailed;
}
