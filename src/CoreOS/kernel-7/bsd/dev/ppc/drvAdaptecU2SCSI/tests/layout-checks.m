/* This translation unit is compiled separately and never enters a kernel. */
#include "../AdaptecU2CHIM.h"
#include "../AdaptecU2CHIMPrivate.h"
#include "../OSMFunctions.h"
#import "../AdaptecU2SCSIPrivate.h"

#ifndef ppc
#error Layout evidence requires the historical PPC target compiler.
#endif

#define AU2_OFFSET(type, member) ((unsigned int)&((type *)0)->member)
#define AU2_ASSERT(name, expression) typedef char name[(expression) ? 1 : -1]

AU2_ASSERT(au2_word_size, sizeof(unsigned int) == 4);

extern void au2_event_sink(AdaptecU2HHCB *, unsigned int);
void au2_event_varargs_check(AdaptecU2HHCB *hhcb, unsigned int event, ...)
{
    au2_event_sink(hhcb, event);
}

void au2_event_onefixed_check(AdaptecU2HHCB *hhcb, ...)
{
}

void au2_event_twofixed_check(AdaptecU2HHCB *hhcb, unsigned int event, ...)
{
}

void au2_event_threefixed_check(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob,
                                  unsigned int event, ...)
{
}
AU2_ASSERT(au2_configuration_size, sizeof(AdaptecU2Configuration) == 0x44);
AU2_ASSERT(au2_configuration_version, AU2_OFFSET(AdaptecU2Configuration, versionNumber) == 0);
AU2_ASSERT(au2_configuration_initiator, AU2_OFFSET(AdaptecU2Configuration, initiatorMode) == 0x20);
AU2_ASSERT(au2_configuration_reserve, AU2_OFFSET(AdaptecU2Configuration, iobReserveSize) == 0x28);
AU2_ASSERT(au2_configuration_address, AU2_OFFSET(AdaptecU2Configuration, allocBusAddressSize) == 0x40);
AU2_ASSERT(au2_memory_descriptor_size, sizeof(AdaptecU2MemoryDescriptor) == 12);
AU2_ASSERT(au2_memory_descriptor_address, AU2_OFFSET(AdaptecU2MemoryDescriptor, address) == 8);
AU2_ASSERT(au2_initialization_size, sizeof(AdaptecU2InitializationTSCB) == 0x1b0);
AU2_ASSERT(au2_initialization_configuration, AU2_OFFSET(AdaptecU2InitializationTSCB, configuration) == 0x16c);
AU2_ASSERT(au2_pci_location_size, sizeof(AdaptecU2PciLocation) == 16);
AU2_ASSERT(au2_io_handle_size, sizeof(AdaptecU2IOHandle) == 32);
const unsigned int au2_io_handle_layout[] = {
    sizeof(AdaptecU2IOHandle),
    AU2_OFFSET(AdaptecU2IOHandle, base),
    AU2_OFFSET(AdaptecU2IOHandle, accessMode),
    AU2_OFFSET(AdaptecU2IOHandle, length),
    AU2_OFFSET(AdaptecU2IOHandle, offset),
    AU2_OFFSET(AdaptecU2IOHandle, mapped),
    AU2_OFFSET(AdaptecU2IOHandle, mappingBase),
    AU2_OFFSET(AdaptecU2IOHandle, next),
    AU2_OFFSET(AdaptecU2IOHandle, prev)
};

void au2_homing_argument_check(AdaptecU2IOHandle handle)
{
}

void au2_write_arguments_check(const AdaptecU2IOHandle *handle,
                               unsigned int offset, unsigned char byte,
                               unsigned short halfword)
{
    OSMWriteUExact8(*handle, offset, byte);
    OSMWriteUExact16(*handle, offset, halfword);
}

unsigned int au2_release_argument_check(AdaptecU2OSMContext context,
                                         const AdaptecU2IOHandle *handle)
{
    return OSMReleaseIOHandle(context, *handle);
}

/* Read these bytes from the target object; do not evaluate host C layouts. */
const unsigned int au2_configuration_layout[] = {
    sizeof(AdaptecU2Configuration),
    AU2_OFFSET(AdaptecU2Configuration, versionNumber),
    AU2_OFFSET(AdaptecU2Configuration, maxInternalIOBlocks),
    AU2_OFFSET(AdaptecU2Configuration, maxTargets),
    AU2_OFFSET(AdaptecU2Configuration, maxSGDescriptors),
    AU2_OFFSET(AdaptecU2Configuration, maxTransferSize),
    AU2_OFFSET(AdaptecU2Configuration, memoryMapped),
    AU2_OFFSET(AdaptecU2Configuration, targetNumNexusTaskSetHandles),
    AU2_OFFSET(AdaptecU2Configuration, targetNumNodeTaskSetHandles),
    AU2_OFFSET(AdaptecU2Configuration, initiatorMode),
    AU2_OFFSET(AdaptecU2Configuration, targetMode),
    AU2_OFFSET(AdaptecU2Configuration, iobReserveSize),
    AU2_OFFSET(AdaptecU2Configuration, stateSize),
    AU2_OFFSET(AdaptecU2Configuration, maxIOHandles),
    AU2_OFFSET(AdaptecU2Configuration, virtualDataAccess),
    AU2_OFFSET(AdaptecU2Configuration, needPhysicalAddr),
    AU2_OFFSET(AdaptecU2Configuration, busMaster),
    AU2_OFFSET(AdaptecU2Configuration, allocBusAddressSize)
};

const unsigned int au2_initialization_layout[] = {
    sizeof(AdaptecU2MemoryDescriptor),
    AU2_OFFSET(AdaptecU2MemoryDescriptor, address),
    sizeof(AdaptecU2InitializationTSCB),
    AU2_OFFSET(AdaptecU2InitializationTSCB, configuration),
    sizeof(AdaptecU2PciLocation)
};

AdaptecU2AdapterTSCB *au2_create_adapter_argument_check(
    AdaptecU2InitializationTSCB *initialization, AdaptecU2AdapterTSCB *adapter,
    AdaptecU2OSMContext context, const AdaptecU2PciLocation *location,
    unsigned int productID)
{
    return SCSICreateAdapterTSCB(initialization, adapter, context,
                                 *location, productID);
}

AU2_ASSERT(au2_adapter_profile_size, sizeof(AdaptecU2AdapterProfile) == 0x1d0);
AU2_ASSERT(au2_adapter_profile_union, AU2_OFFSET(AdaptecU2AdapterProfile, himu) == 0xf4);
AU2_ASSERT(au2_target_profile_size, sizeof(AdaptecU2TargetProfile) == 0x7c);
const unsigned int au2_target_profile_layout[] = {
    sizeof(AdaptecU2TargetProfile),
    AU2_OFFSET(AdaptecU2TargetProfile, words[30])
};
const unsigned int au2_adapter_profile_layout[] = {
    sizeof(AdaptecU2AdapterProfile),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_Version),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_Transport),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_WorldWideID),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_WWIDLength),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_NumBuses),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_VirtualDataAccess),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_NeedPhysicalAddr),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_BusMaster),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_AlignmentMask),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_AddressableRange),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_GroupNum),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_AutoConfigTimeout),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_MaxIOHandles),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_TargetMode),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_InitiatorMode),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_CleanSG),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_Graphing),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_CannotCross4G),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_BiosActive),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_CacheLineStreaming),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_ExtendedTrans),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_MemoryMapped),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_MaxTargets),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_MaxInternalIOBlocks),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_MaxSGDescriptors),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_MaxTransferSize),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_StateSize),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_IOBReserveSize),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_FIFOSeparateRWThreshold),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_FIFOSeparateRWThresholdEnable),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_FIFOWriteThreshold),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_FIFOReadThreshold),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_FIFOThreshold),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_ResetDelay),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_HIMVersion),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_HardwareVersion),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_HardwareVariant),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_LowestScanTarget),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_AllocBusAddressSize),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_indexWithinGroup),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_TargetNumNexusTaskSetHandles),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_TargetNumNodeTaskSetHandles),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_TargetDisconnectAllowed),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_TargetTagEnable),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_OutOfOrderTransfers),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_NexusHandleThreshold),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_EC_IOBThreshold),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_TargetAvailableEC_IOBCount),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_TargetAvailableNexusCount),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_SCSITargetOptTmFunctions.AP_SCSITargetAbortTask),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_SCSITargetOptTmFunctions.AP_SCSITargetClearTaskSet),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_SCSITargetOptTmFunctions.AP_SCSITargetTerminateTask),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_SCSITargetOptTmFunctions.AP_SCSI3TargetClearACA),
    AU2_OFFSET(AdaptecU2AdapterProfile, AP_SCSITargetOptTmFunctions.AP_SCSI3TargetLogicalUnitReset),
    AU2_OFFSET(AdaptecU2AdapterProfile, himu)
};

unsigned int au2_power_event_argument_check(AdaptecU2AdapterTSCB *adapter,
                                            unsigned int eventWord)
{
    return SCSIPowerEvent(adapter, eventWord);
}

AU2_ASSERT(au2_him_table_size, sizeof(AdaptecU2HIMFunctions) == 0xa8);
const unsigned int au2_him_table_layout[] = {
    sizeof(AdaptecU2HIMFunctions),
    AU2_OFFSET(AdaptecU2HIMFunctions, versionNumber),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMGetNextHostDeviceType),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMCreateInitializationTSCB),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMGetConfiguration),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMSetConfiguration),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMSizeAdapterTSCB),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMCreateAdapterTSCB),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMSetupAdapterTSCB),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMCheckMemoryNeeded),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMSetMemoryPointer),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMVerifyAdapter),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMInitialize),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMSizeTargetTSCB),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMCheckTargetTSCBNeeded),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMCreateTargetTSCB),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMDisableIRQ),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMEnableIRQ),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMPollIRQ),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMFrontEndISR),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMBackEndISR),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMQueueIOB),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMPowerEvent),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMValidateTargetTSH),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMClearTargetTSH),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMSaveState),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMRestoreState),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMProfileAdapter),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMReportAdjustableAdapterProfile),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMAdjustAdapterProfile),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMProfileTarget),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMReportAdjustableTargetProfile),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMAdjustTargetProfile),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMGetNVSize),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMGetNVOSMSegment),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMPutNVData),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMGetNVData),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMProfileNexus),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMClearNexusTSH),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMProfileNode),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMReportAdjustableNodeProfile),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMAdjustNodeProfile),
    AU2_OFFSET(AdaptecU2HIMFunctions, HIMSetOSMNodeContext),
};

AU2_ASSERT(au2_osm_table_size, sizeof(AdaptecU2OSMFunctions) == 0x7c);
const unsigned int au2_osm_table_layout[] = {
    sizeof(AdaptecU2OSMFunctions),
    AU2_OFFSET(AdaptecU2OSMFunctions, versionNumber),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMMapIOHandle),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMReleaseIOHandle),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMEvent),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMGetBusAddress),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMAdjustBusAddress),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMGetNVSize),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMPutNVData),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMGetNVData),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMReadUExact8),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMReadUExact16),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMReadUExact32),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMReadStringUExact8),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMReadStringUExact16),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMReadStringUExact32),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMWriteUExact8),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMWriteUExact16),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMWriteUExact32),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMWriteStringUExact8),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMWriteStringUExact16),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMWriteStringUExact32),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMSynchronizeRange),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMWatchdog),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMSaveInterruptState),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMSetInterruptState),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMReadPCIConfigurationDword),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMReadPCIConfigurationWord),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMReadPCIConfigurationByte),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMWritePCIConfigurationDword),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMWritePCIConfigurationWord),
    AU2_OFFSET(AdaptecU2OSMFunctions, OSMWritePCIConfigurationByte),
};

AU2_ASSERT(au2_hardware_size, sizeof(AdaptecU2HardwareDescriptor) == 120);
const unsigned int au2_hardware_layout[] = {
    sizeof(AdaptecU2HardwareDescriptor),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, loadScsiRate),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, resetDFifo),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, enableIOErr),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, getWideScsiOffset),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, getNarrowScsiOffset),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, getXferPeriod),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, calcScsiRate),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, clearScsiOffset),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, wasSyncXfer),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, processAutoTerm),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, updateExtTerm),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, getScbRamCtrls),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, putScbRamCtrls),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, setDataFifoThrshDefault),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, readDataFifoThrsh),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, updateDataFifoThrsh),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, getCacheThEn),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, updateCacheThEn),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, getProfileParameters),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, putProfileParameters),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, checkExtArbAckEnBit),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, getQNewTail),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, waitForBusStable),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, seqStretchWorkaround),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, ignoreWideResCalc),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, ramAvailableMask),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, ramDisableMask),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, word6c),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, byte70),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, byte71),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, defaultCacheThresholdEnable),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, configurationRegister),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, periodLimit),
    AU2_OFFSET(AdaptecU2HardwareDescriptor, delayCount),
};

AU2_ASSERT(au2_buffer_descriptor_size, sizeof(AdaptecU2BufferDescriptor) == 12);
const unsigned int au2_buffer_descriptor_layout[] = {
    sizeof(AdaptecU2BufferDescriptor),
    AU2_OFFSET(AdaptecU2BufferDescriptor, busAddress),
    AU2_OFFSET(AdaptecU2BufferDescriptor, size),
    AU2_OFFSET(AdaptecU2BufferDescriptor, virtualAddress),
};


AU2_ASSERT(au2_scb_descriptor_size, sizeof(AdaptecU2SCBDescriptor) == 20);
const unsigned int au2_scb_descriptor_layout[] = {
    sizeof(AdaptecU2SCBDescriptor),
    AU2_OFFSET(AdaptecU2SCBDescriptor, number),
    AU2_OFFSET(AdaptecU2SCBDescriptor, busAddress),
    AU2_OFFSET(AdaptecU2SCBDescriptor, size),
    AU2_OFFSET(AdaptecU2SCBDescriptor, virtualAddress),
    AU2_OFFSET(AdaptecU2SCBDescriptor, next),
};

AU2_ASSERT(au2_resource_size, sizeof(AdaptecU2ResourceControl) == 68);
const unsigned int au2_resource_layout[] = {
    sizeof(AdaptecU2ResourceControl),
    AU2_OFFSET(AdaptecU2ResourceControl, head),
    AU2_OFFSET(AdaptecU2ResourceControl, tail),
    AU2_OFFSET(AdaptecU2ResourceControl, nonTaggedLimit),
    AU2_OFFSET(AdaptecU2ResourceControl, taggedLimit),
    AU2_OFFSET(AdaptecU2ResourceControl, activeCount),
    AU2_OFFSET(AdaptecU2ResourceControl, savedNonTaggedLimit),
    AU2_OFFSET(AdaptecU2ResourceControl, savedTaggedLimit),
    AU2_OFFSET(AdaptecU2ResourceControl, savedActiveCount),
    AU2_OFFSET(AdaptecU2ResourceControl, resetCount),
    AU2_OFFSET(AdaptecU2ResourceControl, abortSetCount),
    AU2_OFFSET(AdaptecU2ResourceControl, freezeMask),
    AU2_OFFSET(AdaptecU2ResourceControl, word2c),
    AU2_OFFSET(AdaptecU2ResourceControl, savedTail),
    AU2_OFFSET(AdaptecU2ResourceControl, frozenHead),
    AU2_OFFSET(AdaptecU2ResourceControl, frozenTail),
    AU2_OFFSET(AdaptecU2ResourceControl, recoveryCount),
    AU2_OFFSET(AdaptecU2ResourceControl, queuedCount),
};

AU2_ASSERT(au2_unit_size, sizeof(AdaptecU2UnitControl) == 16);
const unsigned int au2_unit_layout[] = {
    sizeof(AdaptecU2UnitControl),
    AU2_OFFSET(AdaptecU2UnitControl, hhcb),
    AU2_OFFSET(AdaptecU2UnitControl, target),
    AU2_OFFSET(AdaptecU2UnitControl, lun),
    AU2_OFFSET(AdaptecU2UnitControl, device),
    AU2_OFFSET(AdaptecU2UnitControl, resource),
};

AU2_ASSERT(au2_AdaptecU2DeviceTable_layout_size, sizeof(AdaptecU2DeviceTable) == 10);
const unsigned int au2_AdaptecU2DeviceTable_layout[] = {
    sizeof(AdaptecU2DeviceTable),
    AU2_OFFSET(AdaptecU2DeviceTable, flags),
    AU2_OFFSET(AdaptecU2DeviceTable, option),
    AU2_OFFSET(AdaptecU2DeviceTable, rate),
    AU2_OFFSET(AdaptecU2DeviceTable, period),
    AU2_OFFSET(AdaptecU2DeviceTable, offset),
    AU2_OFFSET(AdaptecU2DeviceTable, byte07),
    AU2_OFFSET(AdaptecU2DeviceTable, byte08),
    AU2_OFFSET(AdaptecU2DeviceTable, byte09),
};

AU2_ASSERT(au2_AdaptecU2HHCB_layout_size, sizeof(AdaptecU2HHCB) == 1380);
const unsigned int au2_AdaptecU2HHCB_layout[] = {
    sizeof(AdaptecU2HHCB),
    AU2_OFFSET(AdaptecU2HHCB, deviceID),
    AU2_OFFSET(AdaptecU2HHCB, bytes02),
    AU2_OFFSET(AdaptecU2HHCB, numberScbs),
    AU2_OFFSET(AdaptecU2HHCB, ioHandle),
    AU2_OFFSET(AdaptecU2HHCB, flags),
    AU2_OFFSET(AdaptecU2HHCB, configurationRegister),
    AU2_OFFSET(AdaptecU2HHCB, fifoThreshold),
    AU2_OFFSET(AdaptecU2HHCB, firmwareMode),
    AU2_OFFSET(AdaptecU2HHCB, hardwareMode),
    AU2_OFFSET(AdaptecU2HHCB, bytes14),
    AU2_OFFSET(AdaptecU2HHCB, nonTaggedLimit),
    AU2_OFFSET(AdaptecU2HHCB, taggedLimit),
    AU2_OFFSET(AdaptecU2HHCB, bytes1a),
    AU2_OFFSET(AdaptecU2HHCB, maxDevices),
    AU2_OFFSET(AdaptecU2HHCB, byte1d),
    AU2_OFFSET(AdaptecU2HHCB, hostID),
    AU2_OFFSET(AdaptecU2HHCB, byte1f),
    AU2_OFFSET(AdaptecU2HHCB, devices),
    AU2_OFFSET(AdaptecU2HHCB, wordc0),
    AU2_OFFSET(AdaptecU2HHCB, qout),
    AU2_OFFSET(AdaptecU2HHCB, scbBusAddress),
    AU2_OFFSET(AdaptecU2HHCB, scbBufferSize),
    AU2_OFFSET(AdaptecU2HHCB, scbBuffers),
    AU2_OFFSET(AdaptecU2HHCB, hardwareFlags),
    AU2_OFFSET(AdaptecU2HHCB, qnewHead),
    AU2_OFFSET(AdaptecU2HHCB, qdoneElement),
    AU2_OFFSET(AdaptecU2HHCB, qdonePass),
    AU2_OFFSET(AdaptecU2HHCB, bytedb),
    AU2_OFFSET(AdaptecU2HHCB, worddc),
    AU2_OFFSET(AdaptecU2HHCB, worde0),
    AU2_OFFSET(AdaptecU2HHCB, worde4),
    AU2_OFFSET(AdaptecU2HHCB, worde8),
    AU2_OFFSET(AdaptecU2HHCB, wordec),
    AU2_OFFSET(AdaptecU2HHCB, firmware),
    AU2_OFFSET(AdaptecU2HHCB, hardware),
    AU2_OFFSET(AdaptecU2HHCB, resources),
    AU2_OFFSET(AdaptecU2HHCB, activeHiobs),
    AU2_OFFSET(AdaptecU2HHCB, scbDescriptors),
    AU2_OFFSET(AdaptecU2HHCB, doneHiobs),
    AU2_OFFSET(AdaptecU2HHCB, doneHead),
    AU2_OFFSET(AdaptecU2HHCB, doneTail),
    AU2_OFFSET(AdaptecU2HHCB, bytes546),
    AU2_OFFSET(AdaptecU2HHCB, freeScbs),
    AU2_OFFSET(AdaptecU2HHCB, bytes549),
    AU2_OFFSET(AdaptecU2HHCB, freeHead),
    AU2_OFFSET(AdaptecU2HHCB, freeTail),
    AU2_OFFSET(AdaptecU2HHCB, hostHead),
    AU2_OFFSET(AdaptecU2HHCB, hostTail),
    AU2_OFFSET(AdaptecU2HHCB, osmContext),
    AU2_OFFSET(AdaptecU2HHCB, idConfiguration),
};

AU2_ASSERT(au2_AdaptecU2TargetTSCB_layout_size, sizeof(AdaptecU2TargetTSCB) == 40);
const unsigned int au2_AdaptecU2TargetTSCB_layout[] = {
    sizeof(AdaptecU2TargetTSCB),
    AU2_OFFSET(AdaptecU2TargetTSCB, type),
    AU2_OFFSET(AdaptecU2TargetTSCB, adapter),
    AU2_OFFSET(AdaptecU2TargetTSCB, target),
    AU2_OFFSET(AdaptecU2TargetTSCB, lun),
    AU2_OFFSET(AdaptecU2TargetTSCB, flags),
    AU2_OFFSET(AdaptecU2TargetTSCB, unit),
    AU2_OFFSET(AdaptecU2TargetTSCB, reserved24),
};

AU2_ASSERT(au2_AdaptecU2HIOB_layout_size, sizeof(AdaptecU2HIOB) == 56);
const unsigned int au2_AdaptecU2HIOB_layout[] = {
    sizeof(AdaptecU2HIOB),
    AU2_OFFSET(AdaptecU2HIOB, context),
    AU2_OFFSET(AdaptecU2HIOB, function),
    AU2_OFFSET(AdaptecU2HIOB, status),
    AU2_OFFSET(AdaptecU2HIOB, hostStatus),
    AU2_OFFSET(AdaptecU2HIOB, targetStatus),
    AU2_OFFSET(AdaptecU2HIOB, control),
    AU2_OFFSET(AdaptecU2HIOB, control.bytes.scbNumber),
    AU2_OFFSET(AdaptecU2HIOB, auxiliary),
    AU2_OFFSET(AdaptecU2HIOB, senseLength),
    AU2_OFFSET(AdaptecU2HIOB, residualSense),
    AU2_OFFSET(AdaptecU2HIOB, bytes12),
    AU2_OFFSET(AdaptecU2HIOB, residualLength),
    AU2_OFFSET(AdaptecU2HIOB, scb),
    AU2_OFFSET(AdaptecU2HIOB, next),
    AU2_OFFSET(AdaptecU2HIOB, managerStatus),
    AU2_OFFSET(AdaptecU2HIOB, negotiationState),
    AU2_OFFSET(AdaptecU2HIOB, acknowledgeLastMessage),
    AU2_OFFSET(AdaptecU2HIOB, message),
    AU2_OFFSET(AdaptecU2HIOB, bytes28),
    AU2_OFFSET(AdaptecU2HIOB, priority),
    AU2_OFFSET(AdaptecU2HIOB, iob),
};

AU2_ASSERT(au2_AdaptecU2TransportSpecific_layout_size, sizeof(AdaptecU2TransportSpecific) == 20);
const unsigned int au2_AdaptecU2TransportSpecific_layout[] = {
    sizeof(AdaptecU2TransportSpecific),
    AU2_OFFSET(AdaptecU2TransportSpecific, scsiOption),
    AU2_OFFSET(AdaptecU2TransportSpecific, word04),
    AU2_OFFSET(AdaptecU2TransportSpecific, word08),
    AU2_OFFSET(AdaptecU2TransportSpecific, word0c),
    AU2_OFFSET(AdaptecU2TransportSpecific, target),
    AU2_OFFSET(AdaptecU2TransportSpecific, bus),
    AU2_OFFSET(AdaptecU2TransportSpecific, lun),
    AU2_OFFSET(AdaptecU2TransportSpecific, byte13),
};

AU2_ASSERT(au2_AdaptecU2IOB_layout_size, sizeof(AdaptecU2IOB) == 108);
const unsigned int au2_AdaptecU2IOB_layout[] = {
    sizeof(AdaptecU2IOB),
    AU2_OFFSET(AdaptecU2IOB, reserve),
    AU2_OFFSET(AdaptecU2IOB, function),
    AU2_OFFSET(AdaptecU2IOB, priority),
    AU2_OFFSET(AdaptecU2IOB, flags),
    AU2_OFFSET(AdaptecU2IOB, word18),
    AU2_OFFSET(AdaptecU2IOB, transportSpecific),
    AU2_OFFSET(AdaptecU2IOB, command),
    AU2_OFFSET(AdaptecU2IOB, related),
    AU2_OFFSET(AdaptecU2IOB, taskSet),
    AU2_OFFSET(AdaptecU2IOB, status),
    AU2_OFFSET(AdaptecU2IOB, word30),
    AU2_OFFSET(AdaptecU2IOB, post),
    AU2_OFFSET(AdaptecU2IOB, cdb),
    AU2_OFFSET(AdaptecU2IOB, cdbLength),
    AU2_OFFSET(AdaptecU2IOB, word40),
    AU2_OFFSET(AdaptecU2IOB, data),
    AU2_OFFSET(AdaptecU2IOB, transferLength),
    AU2_OFFSET(AdaptecU2IOB, word54),
    AU2_OFFSET(AdaptecU2IOB, sense),
    AU2_OFFSET(AdaptecU2IOB, senseLength),
    AU2_OFFSET(AdaptecU2IOB, residualLength),
    AU2_OFFSET(AdaptecU2IOB, residualSense),
    AU2_OFFSET(AdaptecU2IOB, taskAttribute),
};

AU2_ASSERT(au2_AdaptecU2IOBReserve_layout_size, sizeof(AdaptecU2IOBReserve) == 88);
const unsigned int au2_AdaptecU2IOBReserve_layout[] = {
    sizeof(AdaptecU2IOBReserve),
    AU2_OFFSET(AdaptecU2IOBReserve, cdb),
    AU2_OFFSET(AdaptecU2IOBReserve, hiob),
};

AU2_ASSERT(au2_AdaptecU2HWInformation_layout_size, sizeof(AdaptecU2HWInformation) == 428);
const unsigned int au2_AdaptecU2HWInformation_layout[] = {
    sizeof(AdaptecU2HWInformation),
    AU2_OFFSET(AdaptecU2HWInformation, identification),
    AU2_OFFSET(AdaptecU2HWInformation, hostID),
    AU2_OFFSET(AdaptecU2HWInformation, fifoThreshold),
    AU2_OFFSET(AdaptecU2HWInformation, readThreshold),
    AU2_OFFSET(AdaptecU2HWInformation, writeThreshold),
    AU2_OFFSET(AdaptecU2HWInformation, flags),
    AU2_OFFSET(AdaptecU2HWInformation, targets),
    AU2_OFFSET(AdaptecU2HWInformation, targets[0].queueDepth),
    AU2_OFFSET(AdaptecU2HWInformation, targets[0].option),
    AU2_OFFSET(AdaptecU2HWInformation, targets[0].flags),
    AU2_OFFSET(AdaptecU2HWInformation, targets[0].maximumSpeed),
    AU2_OFFSET(AdaptecU2HWInformation, targets[0].currentSpeed),
    AU2_OFFSET(AdaptecU2HWInformation, targets[0].requestedSpeed),
    AU2_OFFSET(AdaptecU2HWInformation, targets[0].maximumOffset),
    AU2_OFFSET(AdaptecU2HWInformation, targets[0].currentOffset),
    AU2_OFFSET(AdaptecU2HWInformation, targets[0].requestedOffset),
    AU2_OFFSET(AdaptecU2HWInformation, targets[0].maximumWidth),
    AU2_OFFSET(AdaptecU2HWInformation, targets[0].currentWidth),
    AU2_OFFSET(AdaptecU2HWInformation, targets[0].requestedWidth),
    AU2_OFFSET(AdaptecU2HWInformation, targets[0].changed),
    AU2_OFFSET(AdaptecU2HWInformation, targets[1]),
    AU2_OFFSET(AdaptecU2HWInformation, minimumSpeed),
};

AU2_ASSERT(au2_AdaptecU2AdapterTSCB_layout_size, sizeof(AdaptecU2AdapterTSCB) == 2600);
const unsigned int au2_AdaptecU2AdapterTSCB_layout[] = {
    sizeof(AdaptecU2AdapterTSCB),
    AU2_OFFSET(AdaptecU2AdapterTSCB, type),
    AU2_OFFSET(AdaptecU2AdapterTSCB, productID),
    AU2_OFFSET(AdaptecU2AdapterTSCB, location),
    AU2_OFFSET(AdaptecU2AdapterTSCB, hhcb),
    AU2_OFFSET(AdaptecU2AdapterTSCB, nvTargetMask),
    AU2_OFFSET(AdaptecU2AdapterTSCB, biosFlags),
    AU2_OFFSET(AdaptecU2AdapterTSCB, biosDriveBase),
    AU2_OFFSET(AdaptecU2AdapterTSCB, word588),
    AU2_OFFSET(AdaptecU2AdapterTSCB, biosDriveCount),
    AU2_OFFSET(AdaptecU2AdapterTSCB, biosDrives),
    AU2_OFFSET(AdaptecU2AdapterTSCB, memoryTable),
    AU2_OFFSET(AdaptecU2AdapterTSCB, osm),
    AU2_OFFSET(AdaptecU2AdapterTSCB, osmContext),
    AU2_OFFSET(AdaptecU2AdapterTSCB, ioHandle),
    AU2_OFFSET(AdaptecU2AdapterTSCB, readRegister),
    AU2_OFFSET(AdaptecU2AdapterTSCB, writeRegister),
    AU2_OFFSET(AdaptecU2AdapterTSCB, word6c0),
    AU2_OFFSET(AdaptecU2AdapterTSCB, memoryMapped),
    AU2_OFFSET(AdaptecU2AdapterTSCB, buildSCB),
    AU2_OFFSET(AdaptecU2AdapterTSCB, lunCounts),
    AU2_OFFSET(AdaptecU2AdapterTSCB, currentLuns),
    AU2_OFFSET(AdaptecU2AdapterTSCB, previousLuns),
    AU2_OFFSET(AdaptecU2AdapterTSCB, word7dc),
    AU2_OFFSET(AdaptecU2AdapterTSCB, taggedTargets),
    AU2_OFFSET(AdaptecU2AdapterTSCB, reserved7e0),
    AU2_OFFSET(AdaptecU2AdapterTSCB, scanBuffer),
    AU2_OFFSET(AdaptecU2AdapterTSCB, scanIOB),
    AU2_OFFSET(AdaptecU2AdapterTSCB, scanTarget),
    AU2_OFFSET(AdaptecU2AdapterTSCB, scanOrigin),
    AU2_OFFSET(AdaptecU2AdapterTSCB, scanRetry),
    AU2_OFFSET(AdaptecU2AdapterTSCB, scbSize),
    AU2_OFFSET(AdaptecU2AdapterTSCB, lastTarget),
    AU2_OFFSET(AdaptecU2AdapterTSCB, lastLun),
    AU2_OFFSET(AdaptecU2AdapterTSCB, flags),
};

AU2_ASSERT(au2_AdaptecU2Command_layout_size, sizeof(AdaptecU2Command) == 44);
const unsigned int au2_AdaptecU2Command_layout[] = {
    sizeof(AdaptecU2Command),
    AU2_OFFSET(AdaptecU2Command, operation),
    AU2_OFFSET(AdaptecU2Command, cdbLength),
    AU2_OFFSET(AdaptecU2Command, word08),
    AU2_OFFSET(AdaptecU2Command, word0c),
    AU2_OFFSET(AdaptecU2Command, request),
    AU2_OFFSET(AdaptecU2Command, completionLock),
    AU2_OFFSET(AdaptecU2Command, result),
    AU2_OFFSET(AdaptecU2Command, buffer),
    AU2_OFFSET(AdaptecU2Command, client),
    AU2_OFFSET(AdaptecU2Command, link),
};

AU2_ASSERT(au2_AdaptecU2AttachedTarget_layout_size, sizeof(AdaptecU2AttachedTarget) == 156);
const unsigned int au2_AdaptecU2AttachedTarget_layout[] = {
    sizeof(AdaptecU2AttachedTarget),
    AU2_OFFSET(AdaptecU2AttachedTarget, controller),
    AU2_OFFSET(AdaptecU2AttachedTarget, targetTSH),
    AU2_OFFSET(AdaptecU2AttachedTarget, storage),
    AU2_OFFSET(AdaptecU2AttachedTarget, size),
    AU2_OFFSET(AdaptecU2AttachedTarget, profile),
    AU2_OFFSET(AdaptecU2AttachedTarget, waiting),
    AU2_OFFSET(AdaptecU2AttachedTarget, active),
};

AU2_ASSERT(au2_AdaptecU2OSMIOB_layout_size, sizeof(AdaptecU2OSMIOB) == 200);
const unsigned int au2_AdaptecU2OSMIOB_layout[] = {
    sizeof(AdaptecU2OSMIOB),
    AU2_OFFSET(AdaptecU2OSMIOB, iob),
    AU2_OFFSET(AdaptecU2OSMIOB, reserveAllocation),
    AU2_OFFSET(AdaptecU2OSMIOB, owner),
    AU2_OFFSET(AdaptecU2OSMIOB, sgAllocation),
    AU2_OFFSET(AdaptecU2OSMIOB, retryCount),
    AU2_OFFSET(AdaptecU2OSMIOB, timestamp),
    AU2_OFFSET(AdaptecU2OSMIOB, interruptPort),
    AU2_OFFSET(AdaptecU2OSMIOB, transport),
    AU2_OFFSET(AdaptecU2OSMIOB, transportReserved),
    AU2_OFFSET(AdaptecU2OSMIOB, sense),
    AU2_OFFSET(AdaptecU2OSMIOB, link),
};

AU2_ASSERT(au2_AdaptecU2AdapterQueueEntry_layout_size, sizeof(AdaptecU2AdapterQueueEntry) == 12);
const unsigned int au2_AdaptecU2AdapterQueueEntry_layout[] = {
    sizeof(AdaptecU2AdapterQueueEntry),
    AU2_OFFSET(AdaptecU2AdapterQueueEntry, controller),
    AU2_OFFSET(AdaptecU2AdapterQueueEntry, link),
};

AU2_ASSERT(au2_AdaptecU2SGElement_layout_size, sizeof(AdaptecU2SGElement) == 8);
const unsigned int au2_AdaptecU2SGElement_layout[] = {
    sizeof(AdaptecU2SGElement),
};

AU2_ASSERT(au2_AdaptecU2Standard64SCB_layout_size, sizeof(AdaptecU2Standard64SCB) == 64);
const unsigned int au2_AdaptecU2Standard64SCB_layout[] = {
    sizeof(AdaptecU2Standard64SCB),
};

AU2_ASSERT(au2_AdaptecU2Swapping32SCB_layout_size, sizeof(AdaptecU2Swapping32SCB) == 32);
const unsigned int au2_AdaptecU2Swapping32SCB_layout[] = {
    sizeof(AdaptecU2Swapping32SCB),
};

AU2_ASSERT(au2_AdaptecU2StandardAdvSCB_layout_size, sizeof(AdaptecU2StandardAdvSCB) == 64);
const unsigned int au2_AdaptecU2StandardAdvSCB_layout[] = {
    sizeof(AdaptecU2StandardAdvSCB),
};

AU2_ASSERT(au2_AdaptecU2SwappingAdvSCB_layout_size, sizeof(AdaptecU2SwappingAdvSCB) == 64);
const unsigned int au2_AdaptecU2SwappingAdvSCB_layout[] = {
    sizeof(AdaptecU2SwappingAdvSCB),
};

AU2_ASSERT(au2_AdaptecU2FirmwareDescriptor_layout_size, sizeof(AdaptecU2FirmwareDescriptor) == 296);
const unsigned int au2_AdaptecU2FirmwareDescriptor_layout[] = {
    sizeof(AdaptecU2FirmwareDescriptor),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, word00),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, word04),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, word08),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, word0c),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, word10),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, word14),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, word18),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, word1c),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, word20),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, word24),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, word28),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, word2c),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, word30),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, word34),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, registers),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, setupSequencer),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, resetSoftware),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, deliverScb),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, patchXferOpt),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, qHeadBDR),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, retrieveScb),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, qoutcnt),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, targetClearBusy),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, requestSense),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, resetBTA),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, getConfig),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, configureScbRam),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, setupAssignScbBuffer),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, reserved88),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, chkCondXferAssign),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, xferOptAssign),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, commonXferAssign),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, updateXferOptionHostMem),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, getOption),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, getFast20Reg),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, clearFast20Reg),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, logFast20Map),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, updateFast20HostMem),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, updateFast20HW),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, clearAllFast20Reg),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, modifyDataPtr),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, activeAbort),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, abortHIOB),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, searchSeqDoneQ),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, searchDoneQ),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, searchNewQ),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, searchExeQ),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, updateAbortBitHostMem),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, obtainNextScbNum),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, updateNextScbNum),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, obtainNextScbAddress),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, updateNextScbAddress),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, resetCCCtl),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, initCCHHAddr),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, removeActiveAbort),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, stackBugFix),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, setupBDR),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, residueCalc),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, setBreakPoint),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, clearBreakPoint),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, updateSGLength),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, updateSGAddress),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, freezeHWQueue),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, reserved114),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, getScb),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, returnScb),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, hostQueueRemove),
    AU2_OFFSET(AdaptecU2FirmwareDescriptor, removeScbs),
};

AU2_ASSERT(au2_controller_size, sizeof(AdaptecU2SCSI) == 0x5d0);
const unsigned int au2_controller_layout[] = {
    sizeof(AdaptecU2SCSI), sizeof(IOSCSIController),
    AU2_OFFSET(AdaptecU2SCSI, configuration),
    AU2_OFFSET(AdaptecU2SCSI, profile),
    AU2_OFFSET(AdaptecU2SCSI, HIMFunc),
    AU2_OFFSET(AdaptecU2SCSI, iobQ),
    AU2_OFFSET(AdaptecU2SCSI, handleQ),
    AU2_OFFSET(AdaptecU2SCSI, commandQ), sizeof(adapterQ)
};

AdaptecU2OSMIOB *au2_allocate_profile_check(const AdaptecU2AdapterProfile *profile)
{
    return _allocOSMIOB(*profile);
}
void au2_free_profile_check(AdaptecU2OSMIOB *iob,
                           const AdaptecU2AdapterProfile *profile)
{
    _freeOSMIOB(iob, *profile);
}
unsigned int au2_profile_parameter_check(AdaptecU2AdapterProfile profile)
{
    return profile.AP_AlignmentMask + profile.AP_IOBReserveSize;
}
unsigned int au2_free_profile_parameter_check(AdaptecU2OSMIOB *iob,
                                             AdaptecU2AdapterProfile profile)
{
    return profile.AP_AlignmentMask + profile.AP_IOBReserveSize;
}

/* Metadata-only implementations: no product implementation is linked. */
@implementation AdaptecU2SCSI
+ initialize { return 0; }
+ (BOOL)probe:deviceDescription { return 0; }
- initFromDeviceDescription:deviceDescription { return 0; }
- free { return 0; }
- (void)registerHandlerForIRQ:(int)irq {  }
- (BOOL)getWorkingMemoryForCHIM { return 0; }
- (BOOL)findAdapter { return 0; }
- (BOOL)initAdapter { return 0; }
- (BOOL)allocateAdapterMemory { return 0; }
- (void)createOSMIOBPool {  }
- (BOOL)scanAdapter { return 0; }
- (sc_status_t)executeRequest:(AdaptecU2Command *)command { return 0; }
- (sc_status_t)executeRequest:(IOSCSIRequest *)request
                       buffer:(void *)buffer client:(vm_task_t)client { return 0; }
- (sc_status_t)executeRequest:(IOSCSIRequest *)request
           ioMemoryDescriptor:(IOMemoryDescriptor *)descriptor { return 0; }
- (sc_status_t)resetSCSIBus { return 0; }
- (int)numberOfTargets { return 0; }
- (unsigned int)maxTransfer { return 0; }
- (unsigned int)numQueueSamples { return 0; }
- (unsigned int)sumQueueLengths { return 0; }
- (unsigned int)maxQueueLength { return 0; }
- (void)resetStats {  }
@end
@implementation AdaptecU2SCSI (AdaptecU2SCSIThread)
- (void)timeoutOccurred {  }
- (void)threadResetSCSIBus:(AdaptecU2Command *)command {  }
- (void)threadExecuteRequest:(AdaptecU2Command *)command {  }
- (void)commandRequestOccurred {  }
@end

const AdaptecU2HardwareDescriptor au2_check_SCSIHardwareAIC78XX = {
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
    0, 0, 0, 0, 0, 0, 0, 0, 0
};

const AdaptecU2HardwareDescriptor au2_check_SCSIHardwareAICBayonet = {
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
    0, 0, 0, 0, 0, 0, 0, 0, 0
};

const AdaptecU2FirmwareDescriptor au2_check_SCSIFirmwareStandard64 = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, {0},
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

const AdaptecU2FirmwareDescriptor au2_check_SCSIFirmwareSwapping32 = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, {0},
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

const AdaptecU2FirmwareDescriptor au2_check_SCSIFirmwareStandardAdv = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, {0},
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

const AdaptecU2FirmwareDescriptor au2_check_SCSIFirmwareSwappingAdv = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, {0},
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

const AdaptecU2HIMFunctions au2_him_type_check = {
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

const AdaptecU2OSMFunctions au2_osm_type_check = {
    0,
    OSMMapIOHandle,
    OSMReleaseIOHandle,
    OSMEvent,
    OSMGetBusAddress,
    OSMAdjustBusAddress,
    OSMGetNVSize,
    OSMPutNVData,
    OSMGetNVData,
    OSMReadUExact8,
    OSMReadUExact16,
    OSMReadUExact32,
    OSMReadStringUExact8,
    OSMReadStringUExact16,
    OSMReadStringUExact32,
    OSMWriteUExact8,
    OSMWriteUExact16,
    OSMWriteUExact32,
    OSMWriteStringUExact8,
    OSMWriteStringUExact16,
    OSMWriteStringUExact32,
    OSMSynchronizeRange,
    OSMWatchdog,
    OSMSaveInterruptState,
    OSMSetInterruptState,
    OSMReadPCIConfigurationDword,
    OSMReadPCIConfigurationWord,
    OSMReadPCIConfigurationByte,
    OSMWritePCIConfigurationDword,
    OSMWritePCIConfigurationWord,
    OSMWritePCIConfigurationByte,
};
