#include "AdaptecU2CHIMPrivate.h"

/* Native big-endian scalars; callback words use the reviewed ABI. */

AdaptecU2HardwareDescriptor SCSIHardwareAIC78XX = {
    SCSIhAIC78XXLoadScsiRate,
    SCSIhAIC78XXResetDFifo,
    SCSIhAIC78XXEnableIOErr,
    SCSIhAIC78XXGetWideScsiOffset,
    SCSIhAIC78XXGetNarrowScsiOffset,
    SCSIhAIC78XXGetXferPeriod,
    SCSIhAIC78XXCalcScsiRate,
    SCSIhAIC78XXClearScsiOffset,
    SCSIhAIC78XXWasSyncXfer,
    SCSIhAIC78XXProcessAutoTerm,
    SCSIhAIC78XXUpdateExtTerm,
    SCSIhAIC78XXGetScbRamCtrls,
    SCSIhAIC78XXPutScbRamCtrls,
    SCSIhAIC78XXSetDataFifoThrshDefault,
    SCSIhAIC78XXReadDataFifoThrsh,
    SCSIhAIC78XXUpdateDataFifoThrsh,
    SCSIhAIC78XXGetCacheThEn,
    SCSIhAIC78XXUpdateCacheThEn,
    SCSIhAIC78XXGetProfileParameters,
    SCSIhAIC78XXPutProfileParameters,
    SCSIhAIC78XXCheckExtArbAckEnBit,
    SCSIhAIC78XXGetQNewTail,
    0,
    0,
    SCSIhAIC78XXIgnoreWideResCalc,
    0x00000200U,
    0x00000080U,
    0x00010000U,
    0x08,
    0x00,
    0x01,
    0x05,
    0x0044,
    0x07d0,
};

AdaptecU2HardwareDescriptor SCSIHardwareAICBayonet = {
    SCSIhAICBayonetLoadScsiRate,
    SCSIhAICBayonetResetDFifo,
    SCSIhAICBayonetEnableIOErr,
    SCSIhAICBayonetGetScsiOffset,
    SCSIhAICBayonetGetScsiOffset,
    SCSIhAICBayonetGetXferPeriod,
    SCSIhAICBayonetCalcScsiRate,
    SCSIhAICBayonetClearScsiOffset,
    SCSIhAICBayonetWasSyncXfer,
    SCSIhAICBayonetProcessAutoTerm,
    SCSIhAICBayonetUpdateExtTerm,
    SCSIhAICBayonetGetScbRamCtrls,
    SCSIhAICBayonetPutScbRamCtrls,
    SCSIhAICBayonetSetDataFifoThrshDefault,
    SCSIhAICBayonetReadDataFifoThrsh,
    SCSIhAICBayonetUpdateDataFifoThrsh,
    SCSIhAICBayonetGetCacheThEn,
    SCSIhAICBayonetUpdateCacheThEn,
    SCSIhAICBayonetGetProfileParameters,
    SCSIhAICBayonetPutProfileParameters,
    SCSIhAICBayonetCheckExtArbAckEnBit,
    SCSIhAICBayonetGetQNewTail,
    SCSIhAICBayonetWaitForBusStable,
    SCSIhAICBayonetSeqStretchWorkaround,
    SCSIhAICBayonetIgnoreWideResCalc,
    0x00000004U,
    0x00000008U,
    0x00000002U,
    0x0c,
    0x00,
    0x01,
    0x0f,
    0x0032,
    0x0fa0,
};

AdaptecU2HardwareDescriptor *SCSIHardware[3] = {
    &SCSIHardwareAIC78XX,
    &SCSIHardwareAICBayonet,
    0,
};

AdaptecU2FirmwareDescriptor SCSIFirmwareStandard64 = {
    0x00000000U, /* word00 */
    0x00000040U, /* word04 */
    0x00000008U, /* word08 */
    0x00000000U, /* word0c */
    0x00000008U, /* word10 */
    0x00000010U, /* word14 */
    0x000000ffU, /* word18 */
    0x00000004U, /* word1c */
    0x00000000U, /* word20 */
    0x00000030U, /* word24 */
    0x000000ffU, /* word28 */
    0x0000000cU, /* word2c */
    0x000003f0U, /* word30 */
    0x000000ffU, /* word34 */
    { 0xdf, 0xa0, 0x33, 0x35, 0x34, 0x20, 0x30, 0x3c, 0x3a, 0x3b, 0x44, 0x4e, 0x70, 0x4c, 0x4d, 0x5e, 0x78, 0x76, 0x77, 0x79, 0xff, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00 }, /* registers */
    SCSIhStandard64SetupSequencer,
    SCSIhStandard64ResetSoftware,
    SCSIhDeliverScb,
    0,
    SCSIhStandard64QHeadBDR,
    SCSIhStandardRetrieveScb,
    SCSIhStandardQoutcnt,
    SCSIhStandardTargetClearBusy,
    SCSIhStandard64RequestSense,
    SCSIhStandardResetBTA,
    SCSIhStandardGetConfig,
    SCSIhStandardConfigureScbRam,
    SCSIhSetupAssignScbBuffer,
    0,
    SCSIhStandardXferOptAssign,
    SCSIhStandardXferOptAssign,
    0,
    0,
    SCSIhStandardGetOption,
    SCSIhStandardGetFast20Reg,
    SCSIhStandardClearFast20Reg,
    SCSIhStandardLogFast20Map,
    0,
    0,
    SCSIhStandard64ClearAllFast20Reg,
    SCSIhStandard64ModifyDataPtr,
    SCSIhStandard64ActiveAbort,
    SCSIhStandard64AbortHIOB,
    SCSIhStandardSearchSeqDoneQ,
    SCSIhStandardSearchDoneQ,
    SCSIhStandard64SearchNewQ,
    SCSIhStandard64SearchExeQ,
    SCSIhStandard64UpdateAbortBitHostMem,
    SCSIhStandard64ObtainNextScbNum,
    SCSIhStandard64UpdateNextScbNum,
    SCSIhStandard64ObtainNextScbAddress,
    SCSIhStandard64UpdateNextScbAddress,
    SCSIhStandardResetCCCtl,
    SCSIhStandardInitCCHHAddr,
    SCSIhStandardRemoveActiveAbort,
    SCSIhStandard64StackBugFix,
    SCSIhStandard64SetupBDR,
    SCSIhStandard64ResidueCalc,
    SCSIhStandard64SetBreakPoint,
    SCSIhStandard64ClearBreakPoint,
    0,
    0,
    0,
    0,
    SCSIrGetScb,
    SCSIrReturnScb,
    SCSIrHostQueueRemove,
    SCSIrStandardRemoveScbs,
};

AdaptecU2FirmwareDescriptor SCSIFirmwareSwapping32 = {
    0x00000000U, /* word00 */
    0x00000020U, /* word04 */
    0x00000008U, /* word08 */
    0x00000000U, /* word0c */
    0x00000008U, /* word10 */
    0x00000010U, /* word14 */
    0x000000ffU, /* word18 */
    0x00000004U, /* word1c */
    0x00000000U, /* word20 */
    0x000000ffU, /* word24 */
    0x000000ffU, /* word28 */
    0x0000000cU, /* word2c */
    0x00000298U, /* word30 */
    0x000000ffU, /* word34 */
    { 0x20, 0xa8, 0x55, 0x57, 0x56, 0xff, 0xff, 0x00, 0x58, 0x59, 0x40, 0x48, 0xff, 0x5a, 0x5b, 0xff, 0x5c, 0xff, 0xff, 0x5e, 0xff, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00 }, /* registers */
    SCSIhSwapping32SetupSequencer,
    SCSIhSwappingResetSoftware,
    SCSIhDeliverScb,
    SCSIhSwapping32PatchXferOpt,
    SCSIhSwapping32QHeadBDR,
    SCSIhStandardRetrieveScb,
    SCSIhStandardQoutcnt,
    SCSIhSwappingTargetClearBusy,
    SCSIhSwapping32RequestSense,
    SCSIhSwappingResetBTA,
    SCSIhNonStandardGetConfig,
    0,
    SCSIhSetupAssignScbBuffer,
    0,
    SCSIhChkCondXferAssign,
    SCSIhHostXferOptAssign,
    SCSIhSwapping32CommonXferAssign,
    SCSIhSwapping32UpdateXferOptionHostMem,
    SCSIhHostGetOption,
    SCSIhSwappingGetFast20Reg,
    SCSIhSwappingClearFast20Reg,
    SCSIhSwappingLogFast20Map,
    SCSIhSwapping32UpdateFast20HostMem,
    SCSIhSwapping32UpdateFast20HW,
    SCSIhSwappingClearAllFast20Reg,
    SCSIhSwapping32ModifyDataPtr,
    SCSIhSwapping32ActiveAbort,
    SCSIhSwappingAbortHIOB,
    0,
    SCSIhStandardSearchDoneQ,
    SCSIhSwappingSearchNewQ,
    0,
    SCSIhSwapping32UpdateAbortBitHostMem,
    SCSIhSwapping32ObtainNextScbNum,
    SCSIhSwapping32UpdateNextScbNum,
    0,
    0,
    0,
    0,
    SCSIhSwappingRemoveActiveAbort,
    0,
    SCSIhSwapping32SetupBDR,
    SCSIhSwapping32ResidueCalc,
    SCSIhSwapping32SetBreakPoint,
    SCSIhSwapping32ClearBreakPoint,
    0,
    0,
    SCSIhSwapping32FreezeHWQueue,
    0,
    SCSIrGetScb,
    SCSIrReturnScb,
    SCSIrHostQueueRemove,
    0,
};

AdaptecU2FirmwareDescriptor SCSIFirmwareStandardAdv = {
    0x00000000U, /* word00 */
    0x00000040U, /* word04 */
    0x00000008U, /* word08 */
    0x00000000U, /* word0c */
    0x00000008U, /* word10 */
    0x00000010U, /* word14 */
    0x000000ffU, /* word18 */
    0x00000004U, /* word1c */
    0x00000000U, /* word20 */
    0x00000020U, /* word24 */
    0x000000ffU, /* word28 */
    0x0000000cU, /* word2c */
    0x000000ffU, /* word30 */
    0x0000029cU, /* word34 */
    { 0xdf, 0xb0, 0x35, 0x3d, 0x3c, 0xff, 0xff, 0x20, 0xf4, 0xf6, 0x3a, 0x28, 0x38, 0xff, 0x34, 0x36, 0xfa, 0xff, 0xff, 0xff, 0x4a, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00 }, /* registers */
    SCSIhStandardAdvSetupSequencer,
    SCSIhStandardAdvResetSoftware,
    SCSIhDeliverScb,
    SCSIhStandardAdvPatchXferOpt,
    SCSIhStandardAdvQHeadBDR,
    SCSIhStandardRetrieveScb,
    SCSIhStandardQoutcnt,
    SCSIhStandardTargetClearBusy,
    SCSIhStandardAdvRequestSense,
    SCSIhStandardResetBTA,
    SCSIhStandardGetConfig,
    SCSIhStandardConfigureScbRam,
    SCSIhSetupAssignScbBuffer,
    0,
    SCSIhChkCondXferAssign,
    SCSIhHostXferOptAssign,
    SCSIhStandardAdvCommonXferAssign,
    SCSIhStandardAdvUpdateXferOptionHostMem,
    SCSIhHostGetOption,
    SCSIhStandardAdvGetFast20Reg,
    0,
    0,
    0,
    0,
    0,
    SCSIhStandardAdvModifyDataPtr,
    SCSIhStandardAdvActiveAbort,
    SCSIhStandardAdvAbortHIOB,
    SCSIhStandardAdvSearchSeqDoneQ,
    SCSIhStandardSearchDoneQ,
    SCSIhStandardAdvSearchNewQ,
    SCSIhStandardAdvSearchExeQ,
    SCSIhStandardAdvUpdateAbortBitHostMem,
    SCSIhStandardAdvObtainNextScbNum,
    SCSIhStandardAdvUpdateNextScbNum,
    SCSIhStandardAdvObtainNextScbAddress,
    SCSIhStandardAdvUpdateNextScbAddress,
    SCSIhStandardResetCCCtl,
    SCSIhStandardInitCCHHAddr,
    SCSIhStandardRemoveActiveAbort,
    0,
    SCSIhStandardAdvSetupBDR,
    SCSIhStandardAdvResidueCalc,
    SCSIhStandardAdvSetBreakPoint,
    SCSIhStandardAdvClearBreakPoint,
    SCSIhStandardAdvUpdateSGLength,
    SCSIhStandardAdvUpdateSGAddress,
    0,
    0,
    SCSIrGetScb,
    SCSIrReturnScb,
    SCSIrHostQueueRemove,
    SCSIrStandardRemoveScbs,
};

AdaptecU2FirmwareDescriptor SCSIFirmwareSwappingAdv = {
    0x00000000U, /* word00 */
    0x00000040U, /* word04 */
    0x00000008U, /* word08 */
    0x00000000U, /* word0c */
    0x00000008U, /* word10 */
    0x00000010U, /* word14 */
    0x000000ffU, /* word18 */
    0x00000004U, /* word1c */
    0x00000000U, /* word20 */
    0x00000020U, /* word24 */
    0x000000ffU, /* word28 */
    0x0000000cU, /* word2c */
    0x000000ffU, /* word30 */
    0x0000026cU, /* word34 */
    { 0x70, 0xb8, 0x38, 0x3a, 0x39, 0xff, 0xff, 0xff, 0xf4, 0xf6, 0x28, 0x29, 0xff, 0xff, 0x35, 0xff, 0xfa, 0xff, 0xff, 0xff, 0x49, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00 }, /* registers */
    SCSIhSwappingAdvSetupSequencer,
    SCSIhSwappingAdvResetSoftware,
    SCSIhDeliverScb,
    SCSIhSwappingAdvPatchXferOpt,
    SCSIhSwappingAdvQHeadBDR,
    SCSIhStandardRetrieveScb,
    SCSIhStandardQoutcnt,
    SCSIhSwappingTargetClearBusy,
    SCSIhSwappingAdvRequestSense,
    SCSIhSwappingResetBTA,
    SCSIhNonStandardGetConfig,
    0,
    SCSIhSetupAssignScbBuffer,
    0,
    SCSIhChkCondXferAssign,
    SCSIhHostXferOptAssign,
    SCSIhSwappingAdvCommonXferAssign,
    SCSIhSwappingAdvUpdateXferOptionHostMem,
    SCSIhHostGetOption,
    SCSIhSwappingAdvGetFast20Reg,
    0,
    0,
    0,
    0,
    0,
    SCSIhSwappingAdvModifyDataPtr,
    SCSIhSwappingAdvActiveAbort,
    SCSIhSwappingAdvAbortHIOB,
    0,
    SCSIhStandardSearchDoneQ,
    SCSIhSwappingSearchNewQ,
    0,
    SCSIhSwappingAdvUpdateAbortBitHostMem,
    SCSIhSwappingAdvObtainNextScbNum,
    SCSIhSwappingAdvUpdateNextScbNum,
    0,
    0,
    SCSIhStandardResetCCCtl,
    SCSIhStandardInitCCHHAddr,
    SCSIhSwappingRemoveActiveAbort,
    0,
    SCSIhSwappingAdvSetupBDR,
    SCSIhSwappingAdvResidueCalc,
    SCSIhSwappingAdvSetBreakPoint,
    SCSIhSwappingAdvClearBreakPoint,
    SCSIhSwappingAdvUpdateSGLength,
    SCSIhSwappingAdvUpdateSGAddress,
    SCSIhSwappingAdvFreezeHWQueue,
    0,
    SCSIrGetScb,
    SCSIrReturnScb,
    SCSIrHostQueueRemove,
    0,
};

AdaptecU2FirmwareDescriptor *SCSIFirmware[7] = {
    &SCSIFirmwareStandard64,
    0,
    0,
    &SCSIFirmwareSwapping32,
    &SCSIFirmwareStandardAdv,
    &SCSIFirmwareSwappingAdv,
    0,
};

unsigned int SCSIHostType[40][2] = {
    { 0x50789004U, 0xf8ffffffU },
    { 0x50759004U, 0xf8ffffffU },
    { 0x60789004U, 0xffffffffU },
    { 0x61789004U, 0xffffffffU },
    { 0x62789004U, 0xffffffffU },
    { 0x64789004U, 0xffffffffU },
    { 0x65789004U, 0xffffffffU },
    { 0x66789004U, 0xffffffffU },
    { 0x67789004U, 0xffffffffU },
    { 0x60759004U, 0xffffffffU },
    { 0x78609004U, 0xffffffffU },
    { 0x70789004U, 0xffffffffU },
    { 0x71789004U, 0xffffffffU },
    { 0x72789004U, 0xffffffffU },
    { 0x74789004U, 0xffffffffU },
    { 0x75789004U, 0xffffffffU },
    { 0x76789004U, 0xffffffffU },
    { 0x77789004U, 0xffffffffU },
    { 0x80789004U, 0xffffffffU },
    { 0x81789004U, 0xffffffffU },
    { 0x82789004U, 0xffffffffU },
    { 0x84789004U, 0xffffffffU },
    { 0x85789004U, 0xffffffffU },
    { 0x86789004U, 0xffffffffU },
    { 0x87789004U, 0xffffffffU },
    { 0x78959004U, 0xffffffffU },
    { 0x38609004U, 0xffffffffU },
    { 0x00109005U, 0xffffffffU },
    { 0x00209005U, 0xffffffffU },
    { 0x00309005U, 0xffffffffU },
    { 0x001f9005U, 0xffffffffU },
    { 0x002f9005U, 0xffffffffU },
    { 0x003f9005U, 0xffffffffU },
    { 0x00509005U, 0xffffffffU },
    { 0x00609005U, 0xffffffffU },
    { 0x00709005U, 0xffffffffU },
    { 0x005f9005U, 0xffffffffU },
    { 0x006f9005U, 0xffffffffU },
    { 0x007f9005U, 0xffffffffU },
    { 0x00000000U, 0x00000000U },
};

unsigned int SCSISubSystemSubVendorType[16][2] = {
    { 0x78609004U, 0xffffffffU },
    { 0x78619004U, 0xffffffffU },
    { 0x78629004U, 0xffffffffU },
    { 0x78649004U, 0xffffffffU },
    { 0x78659004U, 0xffffffffU },
    { 0x78669004U, 0xffffffffU },
    { 0x78679004U, 0xffffffffU },
    { 0x78909004U, 0xffffffffU },
    { 0x78919004U, 0xffffffffU },
    { 0x78929004U, 0xffffffffU },
    { 0x78949004U, 0xffffffffU },
    { 0x78959004U, 0xffffffffU },
    { 0x78969004U, 0xffffffffU },
    { 0x78979004U, 0xffffffffU },
    { 0x38689004U, 0xffffffffU },
    { 0x38699004U, 0xffffffffU },
};

AdaptecU2HIMFunctions SCSIFuncPtrs = {
4,
    SCSIGetNextHostDeviceType,
    SCSICreateInitializationTSCB,
    SCSIGetConfiguration,
    SCSISetConfiguration,
    SCSISizeAdapterTSCB,
    SCSICreateAdapterTSCB,
    SCSISetupAdapterTSCB,
    SCSICheckMemoryNeeded,
    SCSISetMemoryPointer,
    SCSIVerifyAdapter,
    SCSIInitialize,
    SCSISizeTargetTSCB,
    SCSICheckTargetTSCBNeeded,
    SCSICreateTargetTSCB,
    SCSIDisableIRQ,
    SCSIEnableIRQ,
    SCSIPollIRQ,
    SCSIFrontEndISR,
    SCSIBackEndISR,
    SCSIQueueIOB,
    SCSIPowerEvent,
    SCSIValidateTargetTSH,
    SCSIClearTargetTSH,
    SCSISaveState,
    SCSIRestoreState,
    SCSIProfileAdapter,
    SCSIReportAdjustableAdapterProfile,
    SCSIAdjustAdapterProfile,
    SCSIProfileTarget,
    SCSIReportAdjustableTargetProfile,
    SCSIAdjustTargetProfile,
    SCSIGetNVSize,
    SCSIGetNVOSMSegment,
    SCSIPutNVData,
    SCSIGetNVData,
    SCSIProfileNexus,
    SCSIClearNexusTSH,
    SCSIProfileNode,
    SCSIReportAdjustableNodeProfile,
    SCSIAdjustNodeProfile,
    SCSISetOSMNodeContext,
};

AdaptecU2Configuration SCSIConfiguration = {
    0x00000004U, /* versionNumber */
    0x000000ffU, /* maxInternalIOBlocks */
    0x00000010U, /* maxTargets */
    0xffffffffU, /* maxSGDescriptors */
    0xffffffffU, /* maxTransferSize */
    0x00000000U, /* memoryMapped */
    0x00000000U, /* targetNumNexusTaskSetHandles */
    0x00000000U, /* targetNumNodeTaskSetHandles */
    0x00000001U, /* initiatorMode */
    0x00000000U, /* targetMode */
    0x00000058U, /* iobReserveSize */
    0x00000ce8U, /* stateSize */
    0x00000002U, /* maxIOHandles */
    0x00000001U, /* virtualDataAccess */
    0x00000001U, /* needPhysicalAddr */
    0x00000001U, /* busMaster */
    0x00000020U, /* allocBusAddressSize */
};

AdaptecU2AdapterProfile SCSIDefaultAdapterProfile = {
    0x00000007U, /* AP_Version */
    0x00000001U, /* AP_Transport */
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, /* AP_WorldWideID */
    0x00000020U, /* AP_WWIDLength */
    0x00000001U, /* AP_NumBuses */
    0x00000001U, /* AP_VirtualDataAccess */
    0x00000001U, /* AP_NeedPhysicalAddr */
    0x00000001U, /* AP_BusMaster */
    0x0000003fU, /* AP_AlignmentMask */
    0x00000020U, /* AP_AddressableRange */
    0x00000000U, /* AP_GroupNum */
    0x0000000fU, /* AP_AutoConfigTimeout */
    0x00000002U, /* AP_MaxIOHandles */
    0x00000000U, /* AP_TargetMode */
    0x00000001U, /* AP_InitiatorMode */
    0x00000001U, /* AP_CleanSG */
    0x00000000U, /* AP_Graphing */
    0x00000001U, /* AP_CannotCross4G */
    0x00000000U, /* AP_BiosActive */
    0x00000000U, /* AP_CacheLineStreaming */
    0x00000001U, /* AP_ExtendedTrans */
    0x00000000U, /* AP_MemoryMapped */
    0x00000010U, /* AP_MaxTargets */
    0x000000ffU, /* AP_MaxInternalIOBlocks */
    0xffffffffU, /* AP_MaxSGDescriptors */
    0xffffffffU, /* AP_MaxTransferSize */
    0x00000ce8U, /* AP_StateSize */
    0x00000058U, /* AP_IOBReserveSize */
    0x00000001U, /* AP_FIFOSeparateRWThreshold */
    0x00000000U, /* AP_FIFOSeparateRWThresholdEnable */
    0x00000064U, /* AP_FIFOWriteThreshold */
    0x00000064U, /* AP_FIFOReadThreshold */
    0x00000064U, /* AP_FIFOThreshold */
    0x000003e8U, /* AP_ResetDelay */
    0x00000000U, /* AP_HIMVersion */
    0x00000000U, /* AP_HardwareVersion */
    0x00000000U, /* AP_HardwareVariant */
    0x00000000U, /* AP_LowestScanTarget */
    0x00000020U, /* AP_AllocBusAddressSize */
    0x00000000U, /* AP_indexWithinGroup */
    0x00000000U, /* AP_TargetNumNexusTaskSetHandles */
    0x00000000U, /* AP_TargetNumNodeTaskSetHandles */
    0x00000000U, /* AP_TargetDisconnectAllowed */
    0x00000000U, /* AP_TargetTagEnable */
    0x00000000U, /* AP_OutOfOrderTransfers */
    0x00000000U, /* AP_NexusHandleThreshold */
    0x00000000U, /* AP_EC_IOBThreshold */
    0x00000000U, /* AP_TargetAvailableEC_IOBCount */
    0x00000000U, /* AP_TargetAvailableNexusCount */
    { 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U }, /* AP_SCSITargetOptTmFunctions */
    { { 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000007U, 0x00000000U, 0x00000008U, 0x00000040U, 0x00000040U, 0x00000040U, 0x00000040U, 0x00000040U, 0x00000040U, 0x00000040U, 0x00000040U, 0x00000040U, 0x00000040U, 0x00000040U, 0x00000040U, 0x00000040U, 0x00000040U, 0x00000040U, 0x00000040U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000100U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U } }, /* himu */
};

AdaptecU2AdapterProfile SCSIAdjustableAdapterProfile = {
    0x00000000U, /* AP_Version */
    0x00000000U, /* AP_Transport */
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, /* AP_WorldWideID */
    0x00000000U, /* AP_WWIDLength */
    0x00000000U, /* AP_NumBuses */
    0x00000000U, /* AP_VirtualDataAccess */
    0x00000000U, /* AP_NeedPhysicalAddr */
    0x00000000U, /* AP_BusMaster */
    0x00000000U, /* AP_AlignmentMask */
    0x00000000U, /* AP_AddressableRange */
    0x00000000U, /* AP_GroupNum */
    0x00000000U, /* AP_AutoConfigTimeout */
    0x00000000U, /* AP_MaxIOHandles */
    0x00000001U, /* AP_TargetMode */
    0x00000001U, /* AP_InitiatorMode */
    0x00000000U, /* AP_CleanSG */
    0x00000000U, /* AP_Graphing */
    0x00000000U, /* AP_CannotCross4G */
    0x00000000U, /* AP_BiosActive */
    0x00000000U, /* AP_CacheLineStreaming */
    0x00000000U, /* AP_ExtendedTrans */
    0x00000000U, /* AP_MemoryMapped */
    0x00000000U, /* AP_MaxTargets */
    0x00000000U, /* AP_MaxInternalIOBlocks */
    0x00000000U, /* AP_MaxSGDescriptors */
    0x00000000U, /* AP_MaxTransferSize */
    0x00000000U, /* AP_StateSize */
    0x00000000U, /* AP_IOBReserveSize */
    0x00000000U, /* AP_FIFOSeparateRWThreshold */
    0x00000001U, /* AP_FIFOSeparateRWThresholdEnable */
    0x00000001U, /* AP_FIFOWriteThreshold */
    0x00000001U, /* AP_FIFOReadThreshold */
    0x00000001U, /* AP_FIFOThreshold */
    0x00000000U, /* AP_ResetDelay */
    0x00000000U, /* AP_HIMVersion */
    0x00000000U, /* AP_HardwareVersion */
    0x00000000U, /* AP_HardwareVariant */
    0x00000000U, /* AP_LowestScanTarget */
    0x00000000U, /* AP_AllocBusAddressSize */
    0x00000000U, /* AP_indexWithinGroup */
    0x00000000U, /* AP_TargetNumNexusTaskSetHandles */
    0x00000000U, /* AP_TargetNumNodeTaskSetHandles */
    0x00000000U, /* AP_TargetDisconnectAllowed */
    0x00000000U, /* AP_TargetTagEnable */
    0x00000000U, /* AP_OutOfOrderTransfers */
    0x00000000U, /* AP_NexusHandleThreshold */
    0x00000000U, /* AP_EC_IOBThreshold */
    0x00000000U, /* AP_TargetAvailableEC_IOBCount */
    0x00000000U, /* AP_TargetAvailableNexusCount */
    { 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U }, /* AP_SCSITargetOptTmFunctions */
    { { 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000001U, 0x00000000U, 0x00000000U, 0x00000001U, 0x00000001U, 0x00000001U, 0x00000001U, 0x00000001U, 0x00000001U, 0x00000001U, 0x00000001U, 0x00000001U, 0x00000001U, 0x00000001U, 0x00000001U, 0x00000001U, 0x00000001U, 0x00000001U, 0x00000001U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000001U, 0x00000001U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U } }, /* himu */
};

AdaptecU2TargetProfile SCSIDefaultTargetProfile = {
    { 0x00000005U, 0x00000001U, 0x00000001U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000020U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000002U, 0x00000001U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x000000c8U, 0x000000c8U, 0x00000000U, 0x0000000fU, 0x0000000fU, 0x00000000U, 0x00000010U, 0x00000008U, 0x00000008U, 0x00000001U }
};

AdaptecU2TargetProfile SCSIAdjustableTargetProfile = {
    { 0x00000002U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000001U, 0x00000000U, 0x00000001U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000001U, 0x00000000U, 0x00000000U, 0x00000001U, 0x00000000U, 0x00000000U, 0x00000001U, 0x00000000U, 0x00000001U }
};

unsigned char SCSIscontrol[8] = {
    0x60, 0x62, 0x61, 0x00, 0x00, 0x00, 0x00, 0x00
};
