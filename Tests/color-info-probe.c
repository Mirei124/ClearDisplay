#include <CoreGraphics/CoreGraphics.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

typedef CFDictionaryRef (*CopyInfo)(CGDirectDisplayID);
static void inspect(const char *framework, const char *symbol, CGDirectDisplayID id) {
  void *handle = dlopen(framework, RTLD_LAZY);
  if (!handle) { printf("%s unavailable\n", symbol); return; }
  CopyInfo copy = (CopyInfo)dlsym(handle, symbol);
  if (!copy) { printf("%s missing\n", symbol); return; }
  CFDictionaryRef info = copy(id);
  if (!info) { printf("%s nil\n", symbol); return; }
  printf("%s keys=%ld\n", symbol, CFDictionaryGetCount(info));
  CFIndex count = CFDictionaryGetCount(info);
  const void *keys[count], *values[count];
  CFDictionaryGetKeysAndValues(info, keys, values);
  for (CFIndex i = 0; i < count; ++i) {
    if (CFGetTypeID(keys[i]) != CFStringGetTypeID()) continue;
    char key[256];
    if (!CFStringGetCString((CFStringRef)keys[i], key, sizeof(key), kCFStringEncodingUTF8)) continue;
    if (!strcasestr(key, "color") && !strcasestr(key, "depth") &&
        !strcasestr(key, "mode") && !strcasestr(key, "pixel") &&
        !strcasestr(key, "hdr") && !strcasestr(key, "timing")) continue;
    printf("  %s: ", key);
    CFStringRef description = CFCopyDescription(values[i]);
    if (description) {
      char value[400];
      if (CFStringGetCString(description, value, sizeof(value), kCFStringEncodingUTF8)) printf("%s", value);
      else printf("(complex value)");
      CFRelease(description);
    }
    puts("");
  }
  CFRelease(info);
}
int main(void) {
  uint32_t count = 0;
  if (CGGetOnlineDisplayList(0, NULL, &count) != kCGErrorSuccess || !count) return 1;
  CGDirectDisplayID ids[count];
  if (CGGetOnlineDisplayList(count, ids, &count) != kCGErrorSuccess) return 1;
  for (uint32_t i = 0; i < count; ++i) {
    if (CGDisplayIsBuiltin(ids[i])) continue;
    printf("display %u\n", ids[i]);
    inspect("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
            "CoreDisplay_DisplayCreateInfoDictionary", ids[i]);
    inspect("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            "SLSCopyDisplayInfoDictionary", ids[i]);
  }
  return 0;
}
