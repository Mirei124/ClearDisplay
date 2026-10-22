#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdint.h>
typedef struct {
  uint32_t modeNumber, flags, width, height, depth, dc2[42];
  uint16_t dc3, freq;
  uint32_t dc4[4];
  float density;
} PrivateMode;
extern CGError CGSGetNumberOfDisplayModes(CGDirectDisplayID, int *);
extern CGError CGSGetDisplayModeDescriptionOfLength(CGDirectDisplayID, int, PrivateMode *, int);
int main(void) {
  uint32_t count = 0;
  if (CGGetOnlineDisplayList(0, NULL, &count) != kCGErrorSuccess || !count) return 1;
  CGDirectDisplayID ids[count];
  if (CGGetOnlineDisplayList(count, ids, &count) != kCGErrorSuccess) return 1;
  for (uint32_t i = 0; i < count; ++i) {
    if (CGDisplayIsBuiltin(ids[i])) continue;
    CGDisplayModeRef active = CGDisplayCopyDisplayMode(ids[i]);
    if (!active) continue;
    int n = 0;
    CGSGetNumberOfDisplayModes(ids[i], &n);
    printf("display %u active CGS ID %d; modes %d\n", ids[i],
           CGDisplayModeGetIODisplayModeID(active), n);
    for (int j = 0; j < n; ++j) {
      PrivateMode m = {0};
      if (CGSGetDisplayModeDescriptionOfLength(ids[i], j, &m, sizeof(m)) != kCGErrorSuccess) continue;
      if (m.width != CGDisplayModeGetWidth(active) || m.height != CGDisplayModeGetHeight(active) ||
          m.freq != 60) continue;
      printf("id=%u flags=%08x depth=%u density=%.2f dc2[0..5]=%u,%u,%u,%u,%u,%u\n",
             m.modeNumber, m.flags, m.depth, m.density,
             m.dc2[0],m.dc2[1],m.dc2[2],m.dc2[3],m.dc2[4],m.dc2[5]);
    }
    CFRelease(active);
  }
  return 0;
}
