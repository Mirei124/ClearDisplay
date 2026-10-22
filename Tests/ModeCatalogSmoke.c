#include "../DisplayCore/DisplayModeCatalog.h"
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc < 2 || argc > 3) {
        fprintf(stderr, "Usage: %s display-id [mode-id]\n", argv[0]);
        return 2;
    }
    CGDirectDisplayID display = (CGDirectDisplayID)strtoul(argv[1], NULL, 10);
    uint32_t count = HDEnumerateModes(display, NULL, 0);
    if (!count) {
        fputs("No modes found\n", stderr);
        return 1;
    }
    HDModeOption *modes = calloc(count, sizeof(*modes));
    if (!modes) return 1;
    uint32_t actual = HDEnumerateModes(display, modes, count);
    for (uint32_t i = 0; i < actual && i < count; ++i) {
        HDModeOption m = modes[i];
        if (m.isCurrent || (m.isSelectable && m.logicalWidth >= 1920 &&
                            m.logicalHeight >= 1080 && m.refreshMilliHz >= 60000)) {
            printf("%u %ux%u -> %ux%u %.3f Hz depth %u current=%d selectable=%d\n",
                   m.modeID, m.logicalWidth, m.logicalHeight, m.pixelWidth, m.pixelHeight,
                   m.refreshMilliHz / 1000.0, m.depth, m.isCurrent, m.isSelectable);
        }
    }
    free(modes);
    if (argc == 3) {
        uint32_t target = (uint32_t)strtoul(argv[2], NULL, 10);
        HDModeApplyResult result = HDApplyMode(display, target);
        printf("apply result=%d\n", result);
        return result == HDModeApplyOK ? 0 : 1;
    }
    return 0;
}
