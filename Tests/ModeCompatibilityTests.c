#include "../DisplayCore/DisplayModeCompatibility.h"
#include <assert.h>

int main(void) {
    // Captured with the built-in display disabled: native 1x mode vs 2x mode.
    assert(HDModeAttributesCompatible(0x02000007, 8, 0x00200001, 8));
    assert(HDModeAttributesCompatible(0x00200001, 8, 0x02000007, 8));
    // The same policy must continue to reject incompatible mode attributes.
    assert(!HDModeAttributesCompatible(0x02000007, 8, 0x00200001, 10));
    assert(!HDModeAttributesCompatible(0x02000007, 8,
                                       0x00200001 | kDisplayModeInterlacedFlag, 8));
    assert(!HDModeAttributesCompatible(0x02000007, 8, 0x40000001, 8));
    assert(!HDModeAttributesCompatible(0x02000007, 8, 0x00200000, 8));
    return 0;
}
