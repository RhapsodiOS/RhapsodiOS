#ifndef _ADAPTECU2_CHIM_H_
#define _ADAPTECU2_CHIM_H_

#include "AdaptecU2CHIMTypes.h"

/* Reviewed declarations are indexed by address in interfaces.md.
 * This header is incomplete until the full layouts audit succeeds. */
void SCSIGetFunctionPointers(AdaptecU2HIMFunctions *destination,
                             unsigned int size);
unsigned int SCSIGetNextHostDeviceType(unsigned int index,
                                      unsigned int *busType,
                                      unsigned int *mask);
AdaptecU2InitializationTSCB *SCSICreateInitializationTSCB(
    AdaptecU2InitializationTSCB *storage);
void SCSIGetConfiguration(AdaptecU2InitializationTSCB *initialization,
                         AdaptecU2Configuration *configuration,
                         unsigned int productID);
unsigned int SCSISetConfiguration(AdaptecU2InitializationTSCB *initialization,
                                  AdaptecU2Configuration *configuration,
                                  unsigned int productID);
unsigned int SCSISizeAdapterTSCB(AdaptecU2InitializationTSCB *initialization,
                                unsigned int productID);
unsigned int SCSISizeTargetTSCB(AdaptecU2AdapterTSCB *adapter);
unsigned int SCSISetupAdapterTSCB(AdaptecU2AdapterTSCB *adapter,
                                 const AdaptecU2OSMFunctions *services,
                                 unsigned int size);
AdaptecU2AdapterTSCB *SCSICreateAdapterTSCB(
    AdaptecU2InitializationTSCB *initialization, AdaptecU2AdapterTSCB *storage,
    AdaptecU2OSMContext context, AdaptecU2PciLocation location,
    unsigned int productID);
unsigned int SCSICheckMemoryNeeded(
    AdaptecU2InitializationTSCB *initialization, AdaptecU2AdapterTSCB *adapter,
    unsigned int productID, unsigned int index, unsigned int *category,
    unsigned int *minimumSize, unsigned int *granularity,
    unsigned int *alignmentMask);
unsigned int SCSISetMemoryPointer(AdaptecU2AdapterTSCB *adapter,
                                  unsigned int index, unsigned int category,
                                  unsigned char *address, unsigned int size);
unsigned int SCSIVerifyAdapter(AdaptecU2AdapterTSCB *adapter);
unsigned int SCSIInitialize(AdaptecU2AdapterTSCB *adapter);
unsigned int SCSICheckTargetTSCBNeeded(AdaptecU2AdapterTSCB *adapter,
                                      unsigned int index);
AdaptecU2TargetTSCB *SCSICreateTargetTSCB(AdaptecU2AdapterTSCB *adapter,
                                      unsigned int index,
                                      AdaptecU2TargetTSCB *storage);
unsigned int SCSIClearTargetTSH(AdaptecU2TargetTSCB *target);

void SCSIDisableIRQ(AdaptecU2AdapterTSCB *adapter);
void SCSIEnableIRQ(AdaptecU2AdapterTSCB *adapter);
unsigned int SCSIPollIRQ(AdaptecU2AdapterTSCB *adapter);
/* Forwarded r4 bits: original semantic type is not recoverable. */
unsigned int SCSIPowerEvent(AdaptecU2AdapterTSCB *adapter, unsigned int eventWord);
unsigned int SCSIValidateTargetTSH(AdaptecU2TargetTSCB *target);
unsigned int SCSIProfileAdapter(AdaptecU2AdapterTSCB *adapter,
                                AdaptecU2AdapterProfile *profile);
unsigned int SCSIReportAdjustableAdapterProfile(AdaptecU2AdapterTSCB *adapter,
                                                AdaptecU2AdapterProfile *profile);
unsigned int SCSIAdjustAdapterProfile(AdaptecU2AdapterTSCB *adapter,
                                       const AdaptecU2AdapterProfile *profile);
unsigned int SCSIFrontEndISR(AdaptecU2AdapterTSCB *adapter);
void SCSIBackEndISR(AdaptecU2AdapterTSCB *adapter);
void SCSIQueueIOB(AdaptecU2IOB *iob);
unsigned int SCSIProfileTarget(AdaptecU2TargetTSCB *target,
                               AdaptecU2TargetProfile *profile);
/* The incoming r3 word is discarded; its original source type is unknown. */
unsigned int SCSIReportAdjustableTargetProfile(unsigned int unusedWord,
                                               AdaptecU2TargetProfile *profile);
unsigned int SCSIAdjustTargetProfile(AdaptecU2TargetTSCB *target,
                                      const AdaptecU2TargetProfile *profile);
unsigned int SCSIGetNVSize(AdaptecU2AdapterTSCB *adapter);
unsigned int SCSIGetNVOSMSegment(AdaptecU2AdapterTSCB *adapter,
                                 unsigned int *offset, unsigned int *size);
unsigned int SCSIPutNVData(AdaptecU2AdapterTSCB *adapter,
                           unsigned int byteOffset, const unsigned short *data,
                           unsigned int byteCount);
unsigned int SCSIGetNVData(AdaptecU2AdapterTSCB *adapter, unsigned short *data,
                           unsigned int byteOffset, unsigned int byteCount);

/* Input-erased ABI entries: intentionally unspecified arguments. These
 * declarations expose observed r3 bits, not recovered original C types. */
unsigned int SCSISaveState();
unsigned int SCSIRestoreState();
unsigned int SCSIProfileNexus();
unsigned int SCSIClearNexusTSH();
unsigned int SCSIProfileNode();
unsigned int SCSIReportAdjustableNodeProfile();
unsigned int SCSIAdjustNodeProfile();
unsigned int SCSISetOSMNodeContext();

/* Version is data; only the following 41 words are callbacks. */
struct AdaptecU2HIMFunctions {
    unsigned int versionNumber;
    unsigned int (*HIMGetNextHostDeviceType)(unsigned int index, unsigned int *busType, unsigned int *mask);
    AdaptecU2InitializationTSCB * (*HIMCreateInitializationTSCB)(AdaptecU2InitializationTSCB *storage);
    void (*HIMGetConfiguration)(AdaptecU2InitializationTSCB *initialization, AdaptecU2Configuration *configuration, unsigned int productID);
    unsigned int (*HIMSetConfiguration)(AdaptecU2InitializationTSCB *initialization, AdaptecU2Configuration *configuration, unsigned int productID);
    unsigned int (*HIMSizeAdapterTSCB)(AdaptecU2InitializationTSCB *initialization, unsigned int productID);
    AdaptecU2AdapterTSCB * (*HIMCreateAdapterTSCB)(AdaptecU2InitializationTSCB *initialization, AdaptecU2AdapterTSCB *storage, AdaptecU2OSMContext context, AdaptecU2PciLocation location, unsigned int productID);
    unsigned int (*HIMSetupAdapterTSCB)(AdaptecU2AdapterTSCB *adapter, const AdaptecU2OSMFunctions *services, unsigned int size);
    unsigned int (*HIMCheckMemoryNeeded)(AdaptecU2InitializationTSCB *initialization, AdaptecU2AdapterTSCB *adapter, unsigned int productID, unsigned int index, unsigned int *category, unsigned int *minimumSize, unsigned int *granularity, unsigned int *alignmentMask);
    unsigned int (*HIMSetMemoryPointer)(AdaptecU2AdapterTSCB *adapter, unsigned int index, unsigned int category, unsigned char *address, unsigned int size);
    unsigned int (*HIMVerifyAdapter)(AdaptecU2AdapterTSCB *adapter);
    unsigned int (*HIMInitialize)(AdaptecU2AdapterTSCB *adapter);
    unsigned int (*HIMSizeTargetTSCB)(AdaptecU2AdapterTSCB *adapter);
    unsigned int (*HIMCheckTargetTSCBNeeded)(AdaptecU2AdapterTSCB *adapter, unsigned int index);
    AdaptecU2TargetTSCB * (*HIMCreateTargetTSCB)(AdaptecU2AdapterTSCB *adapter, unsigned int index, AdaptecU2TargetTSCB *storage);
    void (*HIMDisableIRQ)(AdaptecU2AdapterTSCB *adapter);
    void (*HIMEnableIRQ)(AdaptecU2AdapterTSCB *adapter);
    unsigned int (*HIMPollIRQ)(AdaptecU2AdapterTSCB *adapter);
    unsigned int (*HIMFrontEndISR)(AdaptecU2AdapterTSCB *adapter);
    void (*HIMBackEndISR)(AdaptecU2AdapterTSCB *adapter);
    void (*HIMQueueIOB)(AdaptecU2IOB *iob);
    unsigned int (*HIMPowerEvent)(AdaptecU2AdapterTSCB *adapter, unsigned int eventWord);
    unsigned int (*HIMValidateTargetTSH)(AdaptecU2TargetTSCB *target);
    unsigned int (*HIMClearTargetTSH)(AdaptecU2TargetTSCB *target);
    unsigned int (*HIMSaveState)();
    unsigned int (*HIMRestoreState)();
    unsigned int (*HIMProfileAdapter)(AdaptecU2AdapterTSCB *adapter, AdaptecU2AdapterProfile *profile);
    unsigned int (*HIMReportAdjustableAdapterProfile)(AdaptecU2AdapterTSCB *adapter, AdaptecU2AdapterProfile *profile);
    unsigned int (*HIMAdjustAdapterProfile)(AdaptecU2AdapterTSCB *adapter, const AdaptecU2AdapterProfile *profile);
    unsigned int (*HIMProfileTarget)(AdaptecU2TargetTSCB *target, AdaptecU2TargetProfile *profile);
    unsigned int (*HIMReportAdjustableTargetProfile)(unsigned int unusedWord, AdaptecU2TargetProfile *profile);
    unsigned int (*HIMAdjustTargetProfile)(AdaptecU2TargetTSCB *target, const AdaptecU2TargetProfile *profile);
    unsigned int (*HIMGetNVSize)(AdaptecU2AdapterTSCB *adapter);
    unsigned int (*HIMGetNVOSMSegment)(AdaptecU2AdapterTSCB *adapter, unsigned int *offset, unsigned int *size);
    unsigned int (*HIMPutNVData)(AdaptecU2AdapterTSCB *adapter, unsigned int byteOffset, const unsigned short *data, unsigned int byteCount);
    unsigned int (*HIMGetNVData)(AdaptecU2AdapterTSCB *adapter, unsigned short *data, unsigned int byteOffset, unsigned int byteCount);
    unsigned int (*HIMProfileNexus)();
    unsigned int (*HIMClearNexusTSH)();
    unsigned int (*HIMProfileNode)();
    unsigned int (*HIMReportAdjustableNodeProfile)();
    unsigned int (*HIMAdjustNodeProfile)();
    unsigned int (*HIMSetOSMNodeContext)();
};

extern AdaptecU2HIMFunctions SCSIFuncPtrs;

#endif
