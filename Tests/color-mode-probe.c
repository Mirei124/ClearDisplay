#include "../DisplayCore/DisplayColorModeBridge.h"
#include <stdio.h>

int main(void) {
  uint32_t count = 0;
  if (CGGetOnlineDisplayList(0, NULL, &count) != kCGErrorSuccess || !count) return 1;
  CGDirectDisplayID ids[count];
  if (CGGetOnlineDisplayList(count, ids, &count) != kCGErrorSuccess) return 1;
  for (uint32_t i = 0; i < count; ++i) {
    uint32_t available = HDEnumerateColorElements(ids[i], NULL, 0);
    printf("display=%u vendor=%u model=%u elements=%u\n", ids[i],
           CGDisplayVendorNumber(ids[i]), CGDisplayModelNumber(ids[i]), available);
    if (!available) continue;
    HDColorElement options[available];
    uint32_t actual = HDEnumerateColorElements(ids[i], options, available);
    for (uint32_t j = 0; j < actual && j < available; ++j) {
      printf("  id=%u bpc=%u encoding=%u range=%u eotf=%u\n",
             options[j].elementID, options[j].bitsPerComponent,
             options[j].pixelEncodingRaw, options[j].dynamicRangeRaw, options[j].eotfRaw);
    }
  }
  return 0;
}
