#include "DisplayColorModeBridge.h"
#include <IOKit/IOKitLib.h>
#include <stdbool.h>

static CFTypeRef field(CFDictionaryRef dict, CFStringRef key) {
  return dict ? CFDictionaryGetValue(dict, key) : NULL;
}

static bool uint_field(CFDictionaryRef dict, CFStringRef key, uint32_t *out) {
  CFTypeRef value = field(dict, key);
  return value && CFGetTypeID(value) == CFNumberGetTypeID() &&
      CFNumberGetValue((CFNumberRef)value, kCFNumberSInt32Type, out);
}

uint32_t HDEnumerateColorElements(CGDirectDisplayID display, HDColorElement *items, uint32_t capacity) {
  CFMutableDictionaryRef match = IOServiceMatching("IOMobileFramebuffer");
  if (!match) return 0;
  io_iterator_t iterator = IO_OBJECT_NULL;
  if (IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) != KERN_SUCCESS) return 0;
  uint32_t result = 0;
  io_service_t service;
  while ((service = IOIteratorNext(iterator))) {
    CFMutableDictionaryRef properties = NULL;
    if (IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) != KERN_SUCCESS) {
      IOObjectRelease(service);
      continue;
    }
    CFTypeRef attrs = field(properties, CFSTR("DisplayAttributes"));
    CFTypeRef product = attrs && CFGetTypeID(attrs) == CFDictionaryGetTypeID()
        ? field((CFDictionaryRef)attrs, CFSTR("ProductAttributes")) : NULL;
    uint32_t vendor = 0, model = 0, timingID = 0, serial = 0;
    uint32_t displaySerial = CGDisplaySerialNumber(display);
    bool matches = product && CFGetTypeID(product) == CFDictionaryGetTypeID() &&
        uint_field((CFDictionaryRef)product, CFSTR("LegacyManufacturerID"), &vendor) &&
        uint_field((CFDictionaryRef)product, CFSTR("ProductID"), &model) &&
        vendor == CGDisplayVendorNumber(display) && model == CGDisplayModelNumber(display) &&
        (displaySerial == 0 ||
         (uint_field((CFDictionaryRef)product, CFSTR("SerialNumber"), &serial) && serial == displaySerial)) &&
        uint_field(properties, CFSTR("DPTimingModeId"), &timingID);
    if (matches) {
      CFTypeRef timings = field(properties, CFSTR("TimingElements"));
      if (timings && CFGetTypeID(timings) == CFArrayGetTypeID()) {
        for (CFIndex i = 0; i < CFArrayGetCount((CFArrayRef)timings); ++i) {
          CFTypeRef timing = CFArrayGetValueAtIndex((CFArrayRef)timings, i);
          uint32_t id = 0;
          if (CFGetTypeID(timing) != CFDictionaryGetTypeID() ||
              !uint_field((CFDictionaryRef)timing, CFSTR("ID"), &id) || id != timingID) continue;
          CFTypeRef colors = field((CFDictionaryRef)timing, CFSTR("ColorModes"));
          if (!colors || CFGetTypeID(colors) != CFArrayGetTypeID()) break;
          for (CFIndex j = 0; j < CFArrayGetCount((CFArrayRef)colors); ++j) {
            CFTypeRef color = CFArrayGetValueAtIndex((CFArrayRef)colors, j);
            if (CFGetTypeID(color) != CFDictionaryGetTypeID()) continue;
            HDColorElement item = {0};
            if (!uint_field((CFDictionaryRef)color, CFSTR("ID"), &item.elementID) ||
                !uint_field((CFDictionaryRef)color, CFSTR("Depth"), &item.bitsPerComponent)) continue;
            uint_field((CFDictionaryRef)color, CFSTR("PixelEncoding"), &item.pixelEncodingRaw);
            uint_field((CFDictionaryRef)color, CFSTR("DynamicRange"), &item.dynamicRangeRaw);
            uint_field((CFDictionaryRef)color, CFSTR("EOTF"), &item.eotfRaw);
            if (items && result < capacity) items[result] = item;
            ++result;
          }
          break;
        }
      }
    }
    CFRelease(properties);
    IOObjectRelease(service);
    if (matches) break;
  }
  IOObjectRelease(iterator);
  return result;
}
