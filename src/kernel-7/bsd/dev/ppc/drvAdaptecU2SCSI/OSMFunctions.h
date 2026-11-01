#ifndef _DRVADAPTECU2SCSI_OSMFUNCTIONS_H_
#define _DRVADAPTECU2SCSI_OSMFUNCTIONS_H_

#import <mach/boolean.h>
#import <kern/thread_call.h>
#import <mach/mach_types.h>
#include "AdaptecU2CHIMTypes.h"

#ifdef __cplusplus
extern "C" {
#endif

unsigned int OSMMapIOHandle(AdaptecU2OSMContext context,
                            unsigned int barIndex, unsigned int offset,
                            unsigned int length, unsigned int unusedWord,
                            unsigned int accessMode, AdaptecU2IOHandle *handle);
unsigned int OSMReleaseIOHandle(AdaptecU2OSMContext context,
                                AdaptecU2IOHandle handle);
void OSMEvent(AdaptecU2OSMContext context, unsigned int event,
              unsigned int unusedWord, ...);
unsigned int OSMGetBusAddress(AdaptecU2OSMContext context,
                              unsigned int categoryWord,
                              const unsigned char *virtualAddress);
void OSMAdjustBusAddress(unsigned int *busAddress, unsigned int offset);
unsigned int OSMGetNVSize(AdaptecU2OSMContext context);
unsigned int OSMPutNVData(AdaptecU2OSMContext context,
                           unsigned int byteOffset, const unsigned short *data,
                           unsigned int byteCount);
unsigned int OSMGetNVData(AdaptecU2OSMContext context, unsigned short *data,
                           unsigned int byteOffset, unsigned int byteCount);
unsigned char OSMReadUExact8(AdaptecU2IOHandle handle, unsigned int offset);
unsigned short OSMReadUExact16(AdaptecU2IOHandle handle, unsigned int offset);
unsigned int OSMReadUExact32(AdaptecU2IOHandle handle, unsigned int offset);
void OSMReadStringUExact8(AdaptecU2IOHandle handle, unsigned int offset,
                         unsigned char *data, unsigned int count,
                         unsigned int strideWords);
void OSMReadStringUExact16(AdaptecU2IOHandle handle, unsigned int offset,
                          unsigned short *data, unsigned int count,
                          unsigned int strideWords);
void OSMReadStringUExact32(AdaptecU2IOHandle handle, unsigned int offset,
                          unsigned int *data, unsigned int count,
                          unsigned int strideWords);
void OSMWriteUExact8(AdaptecU2IOHandle handle, unsigned int offset,
                     unsigned char value);
void OSMWriteUExact16(AdaptecU2IOHandle handle, unsigned int offset,
                      unsigned short value);
void OSMWriteUExact32(AdaptecU2IOHandle handle, unsigned int offset,
                      unsigned int value);
void OSMWriteStringUExact8(AdaptecU2IOHandle handle, unsigned int offset,
                          const unsigned char *data, unsigned int count,
                          unsigned int strideWords);
void OSMWriteStringUExact16(AdaptecU2IOHandle handle, unsigned int offset,
                           const unsigned short *data, unsigned int count,
                           unsigned int strideWords);
void OSMWriteStringUExact32(AdaptecU2IOHandle handle, unsigned int offset,
                           const unsigned int *data, unsigned int count,
                           unsigned int strideWords);
void OSMWatchdog(AdaptecU2OSMContext context,
                  void (*routine)(AdaptecU2AdapterTSCB *),
                  unsigned int microseconds);
/* Exact OSM formal-erasure set: observed r3 machine words only. The range
 * service also homes r3..r10; its complete stack writes remain required. */
unsigned int OSMSynchronizeRange();
unsigned int OSMSaveInterruptState();
unsigned int OSMSetInterruptState();
unsigned int OSMReadPCIConfigurationDword(AdaptecU2OSMContext context,
                                         unsigned int offset);
unsigned short OSMReadPCIConfigurationWord(AdaptecU2OSMContext context,
                                           unsigned char offset);
unsigned char OSMReadPCIConfigurationByte(AdaptecU2OSMContext context,
                                          unsigned char offset);
void OSMWritePCIConfigurationDword(AdaptecU2OSMContext context,
                                   unsigned char offset, unsigned int value);
void OSMWritePCIConfigurationWord(AdaptecU2OSMContext context,
                                  unsigned char offset, unsigned short value);
void OSMWritePCIConfigurationByte(AdaptecU2OSMContext context,
                                  unsigned char offset, unsigned char value);

void *AdptMallocContiguous(unsigned int size);
void AdptFreeContiguous(void *addr, unsigned int size);

void AU2Handler(int interruptType, void *state, void *context);

/* Version is data; only the following 30 words are callbacks. */
struct AdaptecU2OSMFunctions {
    unsigned int versionNumber;
    unsigned int (*OSMMapIOHandle)(AdaptecU2OSMContext context, unsigned int barIndex, unsigned int offset, unsigned int length, unsigned int unusedWord, unsigned int accessMode, AdaptecU2IOHandle *handle);
    unsigned int (*OSMReleaseIOHandle)(AdaptecU2OSMContext context, AdaptecU2IOHandle handle);
    void (*OSMEvent)(AdaptecU2OSMContext context, unsigned int event, unsigned int unusedWord, ...);
    unsigned int (*OSMGetBusAddress)(AdaptecU2OSMContext context, unsigned int categoryWord, const unsigned char *virtualAddress);
    void (*OSMAdjustBusAddress)(unsigned int *busAddress, unsigned int offset);
    unsigned int (*OSMGetNVSize)(AdaptecU2OSMContext context);
    unsigned int (*OSMPutNVData)(AdaptecU2OSMContext context, unsigned int byteOffset, const unsigned short *data, unsigned int byteCount);
    unsigned int (*OSMGetNVData)(AdaptecU2OSMContext context, unsigned short *data, unsigned int byteOffset, unsigned int byteCount);
    unsigned char (*OSMReadUExact8)(AdaptecU2IOHandle handle, unsigned int offset);
    unsigned short (*OSMReadUExact16)(AdaptecU2IOHandle handle, unsigned int offset);
    unsigned int (*OSMReadUExact32)(AdaptecU2IOHandle handle, unsigned int offset);
    void (*OSMReadStringUExact8)(AdaptecU2IOHandle handle, unsigned int offset, unsigned char *data, unsigned int count, unsigned int strideWords);
    void (*OSMReadStringUExact16)(AdaptecU2IOHandle handle, unsigned int offset, unsigned short *data, unsigned int count, unsigned int strideWords);
    void (*OSMReadStringUExact32)(AdaptecU2IOHandle handle, unsigned int offset, unsigned int *data, unsigned int count, unsigned int strideWords);
    void (*OSMWriteUExact8)(AdaptecU2IOHandle handle, unsigned int offset, unsigned char value);
    void (*OSMWriteUExact16)(AdaptecU2IOHandle handle, unsigned int offset, unsigned short value);
    void (*OSMWriteUExact32)(AdaptecU2IOHandle handle, unsigned int offset, unsigned int value);
    void (*OSMWriteStringUExact8)(AdaptecU2IOHandle handle, unsigned int offset, const unsigned char *data, unsigned int count, unsigned int strideWords);
    void (*OSMWriteStringUExact16)(AdaptecU2IOHandle handle, unsigned int offset, const unsigned short *data, unsigned int count, unsigned int strideWords);
    void (*OSMWriteStringUExact32)(AdaptecU2IOHandle handle, unsigned int offset, const unsigned int *data, unsigned int count, unsigned int strideWords);
    unsigned int (*OSMSynchronizeRange)();
    void (*OSMWatchdog)(AdaptecU2OSMContext context, void (*routine)(AdaptecU2AdapterTSCB *), unsigned int microseconds);
    unsigned int (*OSMSaveInterruptState)();
    unsigned int (*OSMSetInterruptState)();
    unsigned int (*OSMReadPCIConfigurationDword)(AdaptecU2OSMContext context, unsigned int offset);
    unsigned short (*OSMReadPCIConfigurationWord)(AdaptecU2OSMContext context, unsigned char offset);
    unsigned char (*OSMReadPCIConfigurationByte)(AdaptecU2OSMContext context, unsigned char offset);
    void (*OSMWritePCIConfigurationDword)(AdaptecU2OSMContext context, unsigned char offset, unsigned int value);
    void (*OSMWritePCIConfigurationWord)(AdaptecU2OSMContext context, unsigned char offset, unsigned short value);
    void (*OSMWritePCIConfigurationByte)(AdaptecU2OSMContext context, unsigned char offset, unsigned char value);
};

extern AdaptecU2OSMFunctions OSMRoutines;

#ifdef __cplusplus
}
#endif

#endif /* _DRVADAPTECU2SCSI_OSMFUNCTIONS_H_ */

