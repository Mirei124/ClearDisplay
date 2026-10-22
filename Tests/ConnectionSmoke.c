#include "../DisplayCore/DisplayConnectionBridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 1 && argc != 3) {
        fprintf(stderr, "Usage: %s [display-id on|off]\n", argv[0]);
        return 2;
    }
    printf("supported=%d\n", HDConnectionSupported());
    uint32_t count = HDAllDisplayIDs(NULL, 0);
    if (!count || count > 256) {
        fputs("No displays in SkyLight list\n", stderr);
        return 1;
    }
    CGDirectDisplayID ids[256] = {0};
    count = HDAllDisplayIDs(ids, count);
    for (uint32_t i = 0; i < count && i < 256; ++i) {
        printf("display %u enabled=%d builtin=%d\n", ids[i], HDDisplayIsEnabled(ids[i]),
               CGDisplayIsBuiltin(ids[i]));
    }
    if (argc == 3) {
        CGDirectDisplayID id = (CGDirectDisplayID)strtoul(argv[1], NULL, 10);
        bool enabled = strcmp(argv[2], "on") == 0;
        if (!enabled && strcmp(argv[2], "off") != 0) return 2;
        HDConnectionResult result = HDSetDisplayEnabled(id, enabled);
        printf("result=%d\n", result);
        return result == HDConnectionOK ? 0 : 1;
    }
    return 0;
}
