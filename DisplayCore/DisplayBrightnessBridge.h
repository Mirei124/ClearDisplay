#ifndef DISPLAY_BRIGHTNESS_BRIDGE_H
#define DISPLAY_BRIGHTNESS_BRIDGE_H

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <stdint.h>

// Private Apple Silicon DDC channel API. Availability is checked by readback.
typedef void * IOAVServiceRef;
extern IOAVServiceRef IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
extern IOReturn IOAVServiceReadI2C(IOAVServiceRef service, uint32_t chipAddress,
                                  uint32_t offset, void *outputBuffer, uint32_t outputBufferSize);
extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef service, uint32_t chipAddress,
                                   uint32_t dataAddress, void *inputBuffer, uint32_t inputBufferSize);

#endif
