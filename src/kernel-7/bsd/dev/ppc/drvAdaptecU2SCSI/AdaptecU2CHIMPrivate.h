#ifndef _ADAPTECU2_CHIM_PRIVATE_H_
#define _ADAPTECU2_CHIM_PRIVATE_H_

#include "AdaptecU2CHIM.h"
#include "OSMFunctions.h"

unsigned int OSDGetBusAddress(AdaptecU2HHCB *hhcb, unsigned char category,
                              const unsigned char *virtualAddress);
void OSDAdjustBusAddress(AdaptecU2HHCB *hhcb, unsigned int *busAddress,
                          unsigned int offset);
unsigned int OSDReadPciConfiguration(AdaptecU2HHCB *hhcb,
                                     unsigned char offset);
void OSDWritePciConfiguration(AdaptecU2HHCB *hhcb, unsigned char offset,
                               unsigned int value);
AdaptecU2BufferDescriptor *OSDGetSGList(AdaptecU2HIOB *hiob);
AdaptecU2PciLocation *OSDGetHostAddress(AdaptecU2HHCB *hhcb);
void OSDBuildSCB(AdaptecU2HIOB *hiob);
void OSDCompleteHIOB(AdaptecU2HIOB *hiob);
void OSDStandard64BuildSCB(AdaptecU2HIOB *hiob, AdaptecU2IOB *iob,
                           AdaptecU2TargetTSCB *target,
                           AdaptecU2AdapterTSCB *adapter);
void OSDSwapping32BuildSCB(AdaptecU2HIOB *hiob, AdaptecU2IOB *iob,
                           AdaptecU2TargetTSCB *target,
                           AdaptecU2AdapterTSCB *adapter);
void OSDStandardAdvBuildSCB(AdaptecU2HIOB *hiob, AdaptecU2IOB *iob,
                            AdaptecU2TargetTSCB *target,
                            AdaptecU2AdapterTSCB *adapter);
void OSDSwappingAdvBuildSCB(AdaptecU2HIOB *hiob, AdaptecU2IOB *iob,
                            AdaptecU2TargetTSCB *target,
                            AdaptecU2AdapterTSCB *adapter);
void OSDCompleteSpecialHIOB(AdaptecU2HIOB *hiob);
void OSDAsyncEvent(AdaptecU2HHCB *hhcb, unsigned int event, ...);

unsigned short SCSIhReadE2Register(unsigned int address,
                                   const AdaptecU2IOHandle *handle,
                                   unsigned char extendedAddress);
void SCSIhWriteE2Register(unsigned int address, unsigned short value,
                           const AdaptecU2IOHandle *handle,
                           unsigned char extendedAddress);
void SCSIhSendE2Address(unsigned int address, int bitCount,
                         const AdaptecU2IOHandle *handle);
void SCSIhWait2usec(unsigned char value, const AdaptecU2IOHandle *handle);
void SCSIHDisableIRQ(AdaptecU2HHCB *hhcb);
void SCSIHEnableIRQ(AdaptecU2HHCB *hhcb);
unsigned char SCSIHPollIRQ(AdaptecU2HHCB *hhcb);
unsigned int SCSIHPowerManagement(AdaptecU2HHCB *hhcb,
                                   unsigned int unusedEventWord);
void SCSIHSetUnitHandle(AdaptecU2HHCB *hhcb, AdaptecU2UnitControl *unit,
                          unsigned char target, unsigned char lun);
void SCSIHFreeUnitHandle(AdaptecU2UnitHandleArgument unusedHandle);
void SCSIHQueueHIOB(AdaptecU2HIOB *hiob);
void SCSIHQueueSpecialHIOB(AdaptecU2HIOB *hiob);
unsigned int SCSIHCheckHostIdle(AdaptecU2HHCB *hhcb);
unsigned int SCSIHCheckDeviceIdle(AdaptecU2HHCB *hhcb,
                                  unsigned char target);
void SCSIhAbortTask(AdaptecU2HIOB *hiob);
void SCSIhAbortTaskSet(AdaptecU2HIOB *hiob);
void SCSIHEnableExpStatus(AdaptecU2HHCB *hhcb);
void SCSIHDisableExpStatus(AdaptecU2HHCB *hhcb);
void SCSIhPauseAndWait(AdaptecU2HHCB *hhcb);
void SCSIhUnPause(AdaptecU2HHCB *hhcb);
unsigned int SCSIHEnableExtScbRam(AdaptecU2HHCB *hhcb);
unsigned int SCSIHDisableExtScbRam(AdaptecU2HHCB *hhcb);
unsigned int SCSIHExtScbRAMAvail(AdaptecU2HHCB *hhcb);
void SCSIhDelayCount500us(AdaptecU2HHCB *hhcb, unsigned int count);
void SCSIHReadScratchRam(AdaptecU2HHCB *hhcb, unsigned char *destination,
                           int offset, int count);
void SCSIHWriteScratchRam(AdaptecU2HHCB *hhcb, int offset, int count,
                            const unsigned char *source);
void SCSIhWriteHCNTRL(AdaptecU2HHCB *hhcb, unsigned char value);
void SCSIhWWWriteHCNTRL(const AdaptecU2IOHandle *handle, unsigned char value);
unsigned char SCSIhReadINTSTAT(AdaptecU2HHCB *hhcb);
unsigned char SCSIhWWReadINTSTAT(const AdaptecU2IOHandle *handle);
unsigned int SCSIhGetAddressScbBA32(AdaptecU2HHCB *hhcb,
                                    unsigned char offset);
unsigned int SCSIhGetEntity32FromScb(AdaptecU2HHCB *hhcb,
                                     unsigned char offset);
unsigned int SCSIhCompareBusAddress(unsigned int left, unsigned int right);
void SCSIhAIC78XXLoadScsiRate(AdaptecU2HHCB *hhcb, unsigned short rate);
void SCSIhAICBayonetLoadScsiRate(AdaptecU2HHCB *hhcb, unsigned short rate);
void SCSIhAIC78XXResetDFifo(AdaptecU2HHCB *hhcb);
void SCSIhAICBayonetResetDFifo(AdaptecU2HHCB *hhcb);
unsigned int SCSIhAICBayonetGetScbRamCtrls(AdaptecU2HHCB *hhcb);
unsigned int SCSIhAIC78XXGetScbRamCtrls(AdaptecU2HHCB *hhcb);
void SCSIhAICBayonetPutScbRamCtrls(AdaptecU2HHCB *hhcb, unsigned int value);
void SCSIhAIC78XXPutScbRamCtrls(AdaptecU2HHCB *hhcb, unsigned int value);
unsigned char SCSIhAIC78XXGetWideScsiOffset(AdaptecU2HIOB *hiob);
unsigned char SCSIhAIC78XXGetNarrowScsiOffset(AdaptecU2HIOB *hiob);
unsigned char SCSIhAICBayonetGetScsiOffset(AdaptecU2HIOB *hiob);
void SCSIhAIC78XXClearScsiOffset(AdaptecU2HIOB *hiob);
void SCSIhAICBayonetClearScsiOffset(AdaptecU2HIOB *hiob);
unsigned int SCSIhAIC78XXWasSyncXfer(unsigned char offset);
unsigned int SCSIhAICBayonetWasSyncXfer(unsigned char offset);
void SCSIhAIC78XXEnableIOErr(AdaptecU2HHCB *hhcb);
void SCSIhAICBayonetEnableIOErr(AdaptecU2HHCB *hhcb);
unsigned char SCSIhAIC78XXSetDataFifoThrshDefault(AdaptecU2HHCB *hhcb);
unsigned char SCSIhAICBayonetSetDataFifoThrshDefault(AdaptecU2HHCB *hhcb);
unsigned char SCSIhAIC78XXReadDataFifoThrsh(AdaptecU2HHCB *hhcb);
unsigned char SCSIhAICBayonetReadDataFifoThrsh(AdaptecU2HHCB *hhcb);
void SCSIhAIC78XXUpdateDataFifoThrsh(AdaptecU2HHCB *hhcb);
void SCSIhAICBayonetUpdateDataFifoThrsh(AdaptecU2HHCB *hhcb);
unsigned char SCSIhAIC78XXGetCacheThEn(AdaptecU2HHCB *hhcb);
unsigned char SCSIhAICBayonetGetCacheThEn(AdaptecU2HHCB *hhcb);
void SCSIhAIC78XXUpdateCacheThEn(AdaptecU2HHCB *hhcb);
void SCSIhAICBayonetUpdateCacheThEn(AdaptecU2HHCB *hhcb);
void SCSIhAIC78XXCheckExtArbAckEnBit(AdaptecU2HHCB *hhcb);
void SCSIhAICBayonetCheckExtArbAckEnBit(AdaptecU2HHCB *hhcb);
unsigned char SCSIhAIC78XXGetQNewTail(AdaptecU2HHCB *hhcb);
unsigned char SCSIhAICBayonetGetQNewTail(AdaptecU2HHCB *hhcb);
void SCSIhAICBayonetWaitForBusStable(AdaptecU2HHCB *hhcb);
void SCSIhAICBayonetSeqStretchWorkaround(AdaptecU2HHCB *hhcb);
unsigned char SCSIhAIC78XXGetXferPeriod(AdaptecU2HHCB *hhcb,
                                        AdaptecU2HIOB *hiob);
unsigned char SCSIhAICBayonetGetXferPeriod(AdaptecU2HHCB *hhcb,
                                          AdaptecU2HIOB *hiob);
unsigned short SCSIhAIC78XXCalcScsiRate(AdaptecU2HHCB *hhcb,
                                        unsigned char period,
                                        unsigned char offset);
unsigned short SCSIhAICBayonetCalcScsiRate(AdaptecU2HHCB *hhcb,
                                          unsigned char period,
                                          unsigned char offset);
unsigned short SCSIhAIC78XXGetSpeed(unsigned short rate,
                                     unsigned char fastMode);
unsigned short SCSIhAICBayonetGetSpeed(unsigned short rate,
                                       unsigned int unusedModeWord);
unsigned short SCSIhAIC78XXCalcScsiOption(unsigned short speed,
                                          unsigned char offset,
                                          unsigned char width);
unsigned short SCSIhAICBayonetCalcScsiOption(unsigned short speed,
                                            unsigned char offset,
                                            unsigned char width);
void SCSIhAIC78XXProcessAutoTerm(AdaptecU2HHCB *hhcb);
void SCSIhAICBayonetProcessAutoTerm(AdaptecU2HHCB *hhcb);
void SCSIhAIC78XXUpdateExtTerm(AdaptecU2HHCB *hhcb);
void SCSIhAICBayonetUpdateExtTerm(AdaptecU2HHCB *hhcb);
void SCSIhAIC78XXGetProfileParameters(AdaptecU2HWInformation *information,
                                      AdaptecU2HHCB *hhcb);
void SCSIhAICBayonetGetProfileParameters(AdaptecU2HWInformation *information,
                                        AdaptecU2HHCB *hhcb);
void SCSIhAIC78XXPutProfileParameters(const AdaptecU2HWInformation *information,
                                      AdaptecU2HHCB *hhcb);
void SCSIhAICBayonetPutProfileParameters(const AdaptecU2HWInformation *information,
                                        AdaptecU2HHCB *hhcb);
void SCSIHGetHWInformation(AdaptecU2HWInformation *information,
                            AdaptecU2HHCB *hhcb);
void SCSIHPutHWInformation(const AdaptecU2HWInformation *information,
                            AdaptecU2HHCB *hhcb);
void SCSIRGetHWInformation(AdaptecU2HWInformation *information,
                            AdaptecU2HHCB *hhcb);
void SCSIRPutHWInformation(const AdaptecU2HWInformation *information,
                            AdaptecU2HHCB *hhcb);
void SCSIhAIC78XXIgnoreWideResCalc(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob,
                                    unsigned char residual);
void SCSIhAICBayonetIgnoreWideResCalc(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob,
                                      unsigned char residual);
unsigned int SCSIRGetConfiguration(AdaptecU2HHCB *hhcb);
unsigned int SCSIHGetConfiguration(AdaptecU2HHCB *hhcb);
void SCSIRGetMemoryTable(unsigned char firmwareMode, unsigned char scbCount,
                          AdaptecU2MemoryDescriptor *table);
void SCSIHGetMemoryTable(unsigned char firmwareMode, unsigned char scbCount,
                          AdaptecU2MemoryDescriptor *table);
unsigned int SCSIRApplyMemoryTable(AdaptecU2HHCB *hhcb,
                                    const AdaptecU2MemoryDescriptor *table);
unsigned int SCSIHApplyMemoryTable(AdaptecU2HHCB *hhcb,
                                    const AdaptecU2MemoryDescriptor *table);
int SCSIRInitialize(AdaptecU2HHCB *hhcb);
int SCSIHInitialize(AdaptecU2HHCB *hhcb);
void SCSIrReset(AdaptecU2HHCB *hhcb);
void SCSIrStandardRemoveScbs(AdaptecU2HHCB *hhcb);
void SCSIRSetUnitHandle(AdaptecU2HHCB *hhcb, AdaptecU2UnitControl *unit,
                          unsigned char target, unsigned char lun);
void SCSIRFreeUnitHandle(AdaptecU2UnitHandleArgument unusedHandle);
void SCSIRQueueSpecialHIOB(AdaptecU2HIOB *hiob);
unsigned int SCSIRCheckHostIdle(AdaptecU2HHCB *hhcb);
unsigned int SCSIRCheckDeviceIdle(AdaptecU2HHCB *hhcb,
                                  unsigned char target);
void SCSIrCompleteHIOB(AdaptecU2HIOB *hiob);
void SCSIrCompleteSpecialHIOB(AdaptecU2HIOB *hiob);
void SCSIrAsyncEvent(AdaptecU2HHCB *hhcb, unsigned int event, ...);
void SCSIrScsiBusReset(AdaptecU2HIOB *hiob);
void SCSIrBusDeviceReset(AdaptecU2HIOB *hiob);

unsigned int SCSIRPowerManagement(AdaptecU2HHCB *hhcb,
                                   unsigned int unusedEventWord);
void SCSIrAbortTask(AdaptecU2HIOB *hiob);
void SCSIrAbortTaskSet(AdaptecU2HIOB *hiob);
AdaptecU2SCBDescriptor *SCSIRGetFreeHead(AdaptecU2HHCB *hhcb);
void SCSIrAsyncEventCommand(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob,
                              unsigned int event, ...);
void SCSIrAllocateScb(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
unsigned char SCSIrGetScb(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIrReturnScb(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);

void SCSIrDeviceQueueAppend(AdaptecU2ResourceControl *resource,
                              AdaptecU2HIOB *hiob);
AdaptecU2HIOB *SCSIrDeviceQueueRemove(AdaptecU2ResourceControl *resource);
unsigned char SCSIrAbortHIOBInDevQ(AdaptecU2HIOB *hiob,
                                    unsigned char status);
void SCSIrClearDeviceQueue(AdaptecU2ResourceControl *resource,
                             unsigned char status);
void SCSIrClearAllDeviceQueues(AdaptecU2HHCB *hhcb, unsigned char status);
void SCSIrHostQueueAppend(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
AdaptecU2HIOB *SCSIrHostQueueRemove(AdaptecU2HHCB *hhcb,
                                    unsigned char unusedScbNumber);
unsigned char SCSIrAbortHIOBInHostQ(AdaptecU2HIOB *hiob,
                                     unsigned char status);

void SCSIrFindAndAbortHIOB(AdaptecU2HHCB *hhcb, AdaptecU2UnitControl *unit,
                            unsigned char status);
void SCSIrClearHostQueue(AdaptecU2HHCB *hhcb, unsigned char status);
void SCSIrFreeScb(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIrFreeCriteria(AdaptecU2HIOB *hiob);
void SCSIrPostAbortedHIOB(AdaptecU2HIOB *hiob, unsigned char status);
void SCSIrPostDoneQueue(AdaptecU2HHCB *hhcb);
void SCSIrAdjustQueue(AdaptecU2HIOB **head, AdaptecU2HIOB **tail,
                        AdaptecU2HIOB *const *previous, AdaptecU2HIOB *hiob);
void SCSIrFinishQueueFull(AdaptecU2HIOB *hiob);

void SCSIrFreezeAllDeviceQueues(AdaptecU2HHCB *hhcb);
void SCSIrUnFreezeAllDeviceQueues(AdaptecU2HHCB *hhcb);
void SCSIrFreezeDeviceQueue(AdaptecU2ResourceControl *resource,
                             unsigned int mask);
void SCSIrUnFreezeDeviceQueue(AdaptecU2ResourceControl *resource,
                               unsigned int mask);
void SCSIrDispatchQueuedHIOB(AdaptecU2HIOB *hiob);

void SCSIHSetupHardware(AdaptecU2HHCB *hhcb);
unsigned int SCSIHSizeSEEPROM(AdaptecU2HHCB *hhcb);
unsigned int SCSIHReadSEEPROM(AdaptecU2HHCB *hhcb, unsigned short *destination,
                               unsigned int wordOffset, int wordCount);
unsigned int SCSIHWriteSEEPROM(AdaptecU2HHCB *hhcb, unsigned int wordOffset,
                                int wordCount, const unsigned short *source);
void SCSIHSuppressNegotiation(AdaptecU2UnitControl *unit);
void SCSIHForceNegotiation(AdaptecU2UnitControl *unit);
void SCSIHReadHADDR(AdaptecU2HHCB *hhcb, unsigned char *destination);

void SCSIxMaximizeMemory(AdaptecU2MemoryDescriptor *destination,
                           const AdaptecU2MemoryDescriptor *source);
unsigned int SCSIxNonScamValidateLun(AdaptecU2TargetTSCB *target);
unsigned int SCSIxApplyNVData(AdaptecU2AdapterTSCB *adapter);
unsigned int SCSIxBiosExist(AdaptecU2AdapterTSCB *adapter);
unsigned int SCSIxOptimaExist(AdaptecU2AdapterTSCB *adapter);
unsigned int SCSIxChkLunExist(const unsigned char *bitmap,
                               unsigned int target, unsigned int lun);
void SCSIxSetLunExist(unsigned char *bitmap, unsigned int target,
                        unsigned int lun);
void SCSIxClearLunExist(unsigned char *bitmap, unsigned int target,
                          unsigned int lun);

void SCSIxTranslateError(AdaptecU2IOB *iob, const AdaptecU2HIOB *hiob);
void SCSIxSetupBusScan(AdaptecU2AdapterTSCB *adapter);
void SCSIxSetupLunProbe(AdaptecU2AdapterTSCB *adapter, unsigned char target,
                         unsigned char lun);
void SCSIxQueueBusScan(AdaptecU2AdapterTSCB *adapter);
void SCSIxQueueSpecialIOB(AdaptecU2AdapterTSCB *adapter,
                           unsigned int function);
unsigned int SCSIxPostQueueSpecialIOB(AdaptecU2IOB *iob);
unsigned int SCSIxGetSpeed(unsigned short rate, unsigned char fastMode);
unsigned int SCSIxCalcScsiOption(unsigned int speed, unsigned int offset,
                                  unsigned int width);

unsigned int SCSIxPostBusScan(AdaptecU2IOB *iob);
unsigned char SCSIxDetermineFirmwareMode(AdaptecU2AdapterTSCB *adapter);
unsigned int SCSIxGetNextSubSystemSubVendorID(unsigned int index,
                                              unsigned int *mask);

unsigned int SCSIhStandardConfigureScbRam(AdaptecU2HHCB *hhcb);
void SCSIhSetupEnvironment(AdaptecU2HHCB *hhcb);
void SCSIhPrepareConfig(AdaptecU2HHCB *hhcb);
void SCSIhGetCapability(AdaptecU2HHCB *hhcb);
void SCSIhStandardGetConfig(AdaptecU2HHCB *hhcb);
unsigned char SCSIhGetMaxHardwareScbs(AdaptecU2HHCB *hhcb);
void SCSIhNonStandardGetConfig(AdaptecU2HHCB *hhcb);
void SCSIhGetCommonConfig(AdaptecU2HHCB *hhcb);

void SCSIhGetHardwareConfiguration(AdaptecU2HHCB *hhcb);
void SCSIhGetIDBasedConfiguration(AdaptecU2HHCB *hhcb);
int SCSIhStandard64SetupSequencer(AdaptecU2HHCB *hhcb);
int SCSIhSwapping32SetupSequencer(AdaptecU2HHCB *hhcb);
int SCSIhStandardAdvSetupSequencer(AdaptecU2HHCB *hhcb);
int SCSIhSwappingAdvSetupSequencer(AdaptecU2HHCB *hhcb);
void SCSIhInitializeHardware(AdaptecU2HHCB *hhcb);
void SCSIhStartToRunSequencer(AdaptecU2HHCB *hhcb);

int SCSIhLoadSequencer(const AdaptecU2IOHandle *handle,
                         const unsigned char *program, int byteCount);
unsigned char SCSIhWait4Req(AdaptecU2HHCB *hhcb);
void SCSIhSetupAssignScbBuffer(AdaptecU2HHCB *hhcb);
unsigned char SCSIhAIC78XXAutoTermCable(AdaptecU2HHCB *hhcb);
unsigned char SCSIhCableSense(AdaptecU2HHCB *hhcb);
void SCSIhSetAddressScbBA32(AdaptecU2HHCB *hhcb, unsigned char offset,
                             const unsigned char *virtualAddress);
void SCSIhStandardResetCCCtl(AdaptecU2HHCB *hhcb);
void SCSIhStandardInitCCHHAddr(AdaptecU2HHCB *hhcb);

void SCSIhSwapping32SetBreakPoint(AdaptecU2HHCB *hhcb, unsigned char mask);
void SCSIhSwappingAdvSetBreakPoint(AdaptecU2HHCB *hhcb, unsigned char mask);
void SCSIhStandard64SetBreakPoint(AdaptecU2HHCB *hhcb, unsigned char mask);
void SCSIhStandardAdvSetBreakPoint(AdaptecU2HHCB *hhcb, unsigned char mask);
void SCSIhSwapping32ClearBreakPoint(AdaptecU2HHCB *hhcb, unsigned char mask);
void SCSIhSwappingAdvClearBreakPoint(AdaptecU2HHCB *hhcb, unsigned char mask);
void SCSIhStandard64ClearBreakPoint(AdaptecU2HHCB *hhcb, unsigned char mask);
void SCSIhStandardAdvClearBreakPoint(AdaptecU2HHCB *hhcb, unsigned char mask);

void SCSIhDeliverScb(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhSwapping32PatchXferOpt(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhStandardAdvPatchXferOpt(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhSwappingAdvPatchXferOpt(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhStandard64QHead(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhSwapping32QHead(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhSwappingAdvQHead(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhStandardAdvQHead(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);

unsigned char SCSIhStandardRetrieveScb(AdaptecU2HHCB *hhcb);
unsigned char SCSIhStandardQoutcnt(const AdaptecU2HHCB *hhcb);
void SCSIhStandard64QHeadBDR(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhSwapping32QHeadBDR(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhStandardAdvQHeadBDR(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhSwappingAdvQHeadBDR(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhResetChannelHardware(AdaptecU2HHCB *hhcb);
void SCSIhAbortChannel(AdaptecU2HHCB *hhcb, unsigned char status);

void SCSIhStandard64ResetSoftware(AdaptecU2HHCB *hhcb);
void SCSIhSwappingResetSoftware(AdaptecU2HHCB *hhcb);
void SCSIhStandardAdvResetSoftware(AdaptecU2HHCB *hhcb);
void SCSIhSwappingAdvResetSoftware(AdaptecU2HHCB *hhcb);
void SCSIhCommonResetSoftware(AdaptecU2HHCB *hhcb);
void SCSIhSetAddressScratchBA32(AdaptecU2HHCB *hhcb, unsigned char offset,
                                 const unsigned char *virtualAddress);
void SCSIhStandardResetBTA(AdaptecU2HHCB *hhcb);
void SCSIhSwappingResetBTA(AdaptecU2HHCB *hhcb);

void SCSIhStandardTargetClearBusy(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhSwappingTargetClearBusy(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhStandardIndexClearBusy(AdaptecU2HHCB *hhcb, unsigned char index);
void SCSIhSwappingIndexClearBusy(AdaptecU2HHCB *hhcb, unsigned char index);
void SCSIhResetScsi(AdaptecU2HHCB *hhcb);
void SCSIhScsiBusReset(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhBusDeviceReset(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhStandard64AbortHIOB(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status);

void SCSIhStandardAdvAbortHIOB(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status);
void SCSIhSwappingAbortHIOB(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status);
void SCSIhSwappingAdvAbortHIOB(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status);
unsigned char SCSIhStandardSearchSeqDoneQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char terminate);
unsigned char SCSIhStandardAdvSearchSeqDoneQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char terminate);
unsigned char SCSIhStandardSearchDoneQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
unsigned char SCSIhStandard64SearchNewQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status);
unsigned char SCSIhStandardAdvSearchNewQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status);

unsigned char SCSIhSwappingSearchNewQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status);
unsigned char SCSIhStandard64ObtainNextScbNum(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob);
unsigned char SCSIhSwapping32ObtainNextScbNum(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob);
unsigned char SCSIhStandardAdvObtainNextScbNum(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob);
unsigned char SCSIhSwappingAdvObtainNextScbNum(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob);
void SCSIhStandard64UpdateNextScbNum(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char number);
void SCSIhSwapping32UpdateNextScbNum(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char number);
void SCSIhStandardAdvUpdateNextScbNum(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char number);

void SCSIhSwappingAdvUpdateNextScbNum(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char number);
unsigned int SCSIhStandard64ObtainNextScbAddress(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob);
unsigned int SCSIhStandardAdvObtainNextScbAddress(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob);
void SCSIhStandard64UpdateNextScbAddress(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned int busAddress);
void SCSIhStandardAdvUpdateNextScbAddress(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned int busAddress);
unsigned char SCSIhStandard64SearchExeQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status, unsigned char terminate);
unsigned char SCSIhStandardAdvSearchExeQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status, unsigned char terminate);
void SCSIhStandard64UpdateAbortBitHostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);

void SCSIhStandardAdvUpdateAbortBitHostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhSwapping32UpdateAbortBitHostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhSwappingAdvUpdateAbortBitHostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhStandard64SetupBDR(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhSwapping32SetupBDR(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhStandardAdvSetupBDR(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhSwappingAdvSetupBDR(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhStandard64StackBugFix(AdaptecU2HHCB *hhcb);

void SCSIhSwapping32FreezeHWQueue(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhSwappingAdvFreezeHWQueue(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhIntSrst(AdaptecU2HHCB *hhcb);
void SCSIhIntIOError(AdaptecU2HHCB *hhcb);
void SCSIhCheckLength(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhCdbAbort(AdaptecU2HHCB *hhcb);
void SCSIhCheckCondition(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhBadSeq(AdaptecU2HHCB *hhcb);

void SCSIhAbortTarget(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhIntSelto(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhIntFree(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhParityError(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhStandard64RequestSense(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhSwapping32RequestSense(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhStandardAdvRequestSense(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhSwappingAdvRequestSense(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);

void SCSIhTerminateCommand(AdaptecU2HIOB *hiob);
void SCSIhSetStat(AdaptecU2HIOB *hiob);
void SCSIhBreakInterrupt(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhStandard64ActiveAbort(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhSwapping32ActiveAbort(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhStandardAdvActiveAbort(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhSwappingAdvActiveAbort(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhSwappingRemoveActiveAbort(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);

void SCSIhStandardRemoveActiveAbort(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
unsigned int SCSIhStandard64ResidueCalc(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
unsigned int SCSIhSwapping32ResidueCalc(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
unsigned int SCSIhStandardAdvResidueCalc(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
unsigned int SCSIhSwappingAdvResidueCalc(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
unsigned char SCSIhSwappingRemoveAbortHIOBFromNewQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status);

void SCSIhNegotiate(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhExtMsgi(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhInitiateWide(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhVerifyWideResponse(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhInitiateSync(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char offset);
void SCSIhVerifySyncResponse(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhRespondToWide(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhRespondToSync(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);

void SCSIhSendMessage(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, int count);
int SCSIhReceiveMessage(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, int count);
void SCSIhHandleMsgOut(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhHandleMsgIn(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
unsigned char SCSIhStandardGetFast20Reg(AdaptecU2HHCB *hhcb, unsigned char target);
unsigned char SCSIhStandardAdvGetFast20Reg(AdaptecU2HHCB *hhcb, unsigned char target);
unsigned char SCSIhSwappingGetFast20Reg(AdaptecU2HHCB *hhcb, unsigned char target);
unsigned char SCSIhSwappingAdvGetFast20Reg(AdaptecU2HHCB *hhcb, unsigned char target);

void SCSIhStandardClearFast20Reg(AdaptecU2HHCB *hhcb, unsigned char target);
void SCSIhSwappingClearFast20Reg(AdaptecU2HHCB *hhcb, unsigned char target);
void SCSIhStandardLogFast20Map(AdaptecU2HHCB *hhcb, unsigned char target, unsigned char period);
void SCSIhSwappingLogFast20Map(AdaptecU2HHCB *hhcb, unsigned char target, unsigned char period);
void SCSIhSwapping32UpdateFast20HostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char enabled);
void SCSIhSwapping32UpdateFast20HW(AdaptecU2HHCB *hhcb, unsigned char enabled);
void SCSIhCheckSyncNego(AdaptecU2HHCB *hhcb);
void SCSIhStandardXferOptAssign(AdaptecU2HHCB *hhcb, unsigned char target, unsigned short option);

void SCSIhHostXferOptAssign(AdaptecU2HHCB *hhcb, unsigned char target, unsigned short option);
void SCSIhChkCondXferAssign(AdaptecU2HHCB *hhcb, unsigned char target, unsigned short option);
void SCSIhSwapping32CommonXferAssign(AdaptecU2HHCB *hhcb, unsigned char target, unsigned short option);
void SCSIhStandardAdvCommonXferAssign(AdaptecU2HHCB *hhcb, unsigned char target, unsigned short option);
void SCSIhSwappingAdvCommonXferAssign(AdaptecU2HHCB *hhcb, unsigned char target, unsigned short option);
void SCSIhSwapping32UpdateXferOptionHostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned short option);
void SCSIhStandardAdvUpdateXferOptionHostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned short option);
void SCSIhSwappingAdvUpdateXferOptionHostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned short option);

unsigned short SCSIhStandardGetOption(AdaptecU2HHCB *hhcb, unsigned char target);
unsigned short SCSIhHostGetOption(AdaptecU2HHCB *hhcb, unsigned char target);
void SCSIhStandard64ModifyDataPtr(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhSwapping32ModifyDataPtr(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhStandardAdvModifyDataPtr(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhSwappingAdvModifyDataPtr(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
void SCSIhSwappingClearAllFast20Reg(AdaptecU2HHCB *hhcb);
void SCSIhStandard64ClearAllFast20Reg(AdaptecU2HHCB *hhcb);

void SCSIhStandardAdvUpdateSGLength(AdaptecU2HHCB *hhcb, unsigned int length);
void SCSIhSwappingAdvUpdateSGLength(AdaptecU2HHCB *hhcb, unsigned int length);
void SCSIhStandardAdvUpdateSGAddress(AdaptecU2HHCB *hhcb, unsigned int busAddress);
void SCSIhSwappingAdvUpdateSGAddress(AdaptecU2HHCB *hhcb, unsigned int busAddress);

/* The three unreferenced, input-erased return-zero bodies. The exact
 * exception set, byte proof, and limitations are in interfaces.md. */
unsigned int SCSIhSwappingSearchExeQ();
unsigned int SCSIhScamSupportCheck();
unsigned int SCSIHApplyDeviceTable();

/* Adapter allocation is exactly2600 bytes. The HHCB view covers its
 * accessed prefix; the following BIOS/state storage belongs to the adapter. */
struct AdaptecU2AdapterTSCB {
    unsigned int type;
    unsigned int productID;
    AdaptecU2PciLocation location;
    AdaptecU2HHCB hhcb;
    unsigned int nvTargetMask;
    unsigned int biosFlags;
    unsigned int biosDriveBase;
    unsigned int word588;
    unsigned int biosDriveCount;
    struct { unsigned int target; unsigned int word04; } biosDrives[8];
    AdaptecU2MemoryDescriptor memoryTable[6];
    AdaptecU2OSMFunctions osm;
    AdaptecU2OSMContext osmContext;
    AdaptecU2IOHandle ioHandle;
    unsigned char (*readRegister)(AdaptecU2IOHandle, unsigned int);
    void (*writeRegister)(AdaptecU2IOHandle, unsigned int, unsigned char);
    unsigned int word6c0;
    unsigned int memoryMapped;
    void (*buildSCB)(AdaptecU2HIOB *, AdaptecU2IOB *,
                     AdaptecU2TargetTSCB *, AdaptecU2AdapterTSCB *);
    unsigned char lunCounts[16];
    unsigned char currentLuns[128];
    unsigned char previousLuns[128];
    unsigned short word7dc;
    unsigned short taggedTargets;
    unsigned char reserved7e0[512];
    unsigned char *scanBuffer;
    AdaptecU2IOB *scanIOB;
    AdaptecU2TargetTSCB scanTarget;
    AdaptecU2IOB *scanOrigin;
    unsigned int scanRetry;
    unsigned int scbSize;
    unsigned int lastTarget;
    unsigned int lastLun;
    unsigned int flags;
};

#endif
