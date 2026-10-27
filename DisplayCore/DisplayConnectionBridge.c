#include "DisplayConnectionBridge.h"

#include <dlfcn.h>
#include <stddef.h>
#include <unistd.h>

typedef CGError (*HDGetDisplayListFn)(uint32_t, CGDirectDisplayID *, uint32_t *);
typedef CGError (*HDConfigureEnabledFn)(CGDisplayConfigRef, CGDirectDisplayID, bool);

static void *HDLibrary(void) {
    static void *library;
    static bool loaded;
    if (!loaded) {
        library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL);
        loaded = true;
    }
    return library;
}

static HDGetDisplayListFn HDListFunction(void) {
    void *library = HDLibrary();
    return library ? (HDGetDisplayListFn)dlsym(library, "SLSGetDisplayList") : NULL;
}

static HDConfigureEnabledFn HDConfigureFunction(void) {
    void *library = HDLibrary();
    return library ? (HDConfigureEnabledFn)dlsym(library, "SLSConfigureDisplayEnabled") : NULL;
}

bool HDConnectionSupported(void) {
#if defined(__arm64__)
    return HDListFunction() != NULL && HDConfigureFunction() != NULL;
#else
    return false;
#endif
}

uint32_t HDAllDisplayIDs(CGDirectDisplayID *ids, uint32_t capacity) {
    HDGetDisplayListFn list = HDListFunction();
    uint32_t count = 0;
    if (list == NULL || list(capacity, ids, &count) != kCGErrorSuccess) return 0;
    return count;
}

static bool HDKnownDisplay(CGDirectDisplayID displayID) {
    uint32_t count = HDAllDisplayIDs(NULL, 0);
    if (count == 0 || count > 256) return false;
    CGDirectDisplayID ids[256] = {0};
    uint32_t actual = HDAllDisplayIDs(ids, count);
    for (uint32_t index = 0; index < actual && index < count; ++index) {
        if (ids[index] == displayID) return true;
    }
    return false;
}

bool HDDisplayIsEnabled(CGDirectDisplayID displayID) {
    return CGDisplayIsOnline(displayID) != 0 && CGDisplayIsActive(displayID) != 0;
}

bool HDGetActivePhysicalDisplayCount(uint32_t *physicalCount) {
    if (physicalCount == NULL) return false;
    *physicalCount = 0;
    uint32_t count = 0;
    if (CGGetActiveDisplayList(0, NULL, &count) != kCGErrorSuccess || count > 256) return false;
    if (count == 0) return true;
    CGDirectDisplayID ids[256] = {0};
    uint32_t actual = 0;
    if (CGGetActiveDisplayList(count, ids, &actual) != kCGErrorSuccess) return false;
    uint32_t physical = 0;
    for (uint32_t index = 0; index < actual && index < count; ++index) {
        CGDirectDisplayID id = ids[index];
        if (CGDisplayIsBuiltin(id) ||
            (CGDisplayVendorNumber(id) > 0 && CGDisplayVendorNumber(id) <= 0xFFFF &&
             CGDisplayModelNumber(id) > 0 && CGDisplayModelNumber(id) <= 0xFFFF)) physical++;
    }
    *physicalCount = physical;
    return true;
}

HDConnectionResult HDSetDisplayEnabled(CGDirectDisplayID displayID, bool enabled) {
    if (!HDConnectionSupported()) return HDConnectionUnsupported;
    if (!HDKnownDisplay(displayID)) return HDConnectionDisplayGone;
    if (HDDisplayIsEnabled(displayID) == enabled) return HDConnectionOK;
    uint32_t physicalCount = 0;
    if (!enabled && (!HDGetActivePhysicalDisplayCount(&physicalCount) || physicalCount <= 1))
        return HDConnectionLastDisplay;

    CGDisplayConfigRef config = NULL;
    if (CGBeginDisplayConfiguration(&config) != kCGErrorSuccess || config == NULL)
        return HDConnectionBeginFailed;
    HDConfigureEnabledFn configure = HDConfigureFunction();
    if (configure(config, displayID, enabled) != kCGErrorSuccess) {
        CGCancelDisplayConfiguration(config);
        return HDConnectionConfigureFailed;
    }
    if (CGCompleteDisplayConfiguration(config, kCGConfigurePermanently) != kCGErrorSuccess)
        return HDConnectionCommitFailed;
    // WindowServer may publish the new state shortly after the transaction returns.
    for (int attempt = 0; attempt < 20; ++attempt) {
        if (HDDisplayIsEnabled(displayID) == enabled) return HDConnectionOK;
        usleep(100000);
    }
    return HDConnectionVerificationFailed;
}
