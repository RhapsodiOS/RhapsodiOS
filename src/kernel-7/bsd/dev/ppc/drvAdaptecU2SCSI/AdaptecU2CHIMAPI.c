#include "AdaptecU2CHIMPrivate.h"

extern void fast_bcopy(const void *, void *, unsigned int);
extern void *memset(void *, int, unsigned int);

void SCSIGetFunctionPointers(AdaptecU2HIMFunctions *destination,
                             unsigned int size)
{
    fast_bcopy(&SCSIFuncPtrs, destination, size);
}

unsigned int SCSIGetNextHostDeviceType(unsigned int index,
                                      unsigned int *busType,
                                      unsigned int *mask)
{
    if (index <= 39 && SCSIHostType[index][0]) {
        *busType = 0;
        *mask = SCSIHostType[index][1];
        return SCSIHostType[index][0];
    }
    return 0;
}

AdaptecU2InitializationTSCB *SCSICreateInitializationTSCB(
    AdaptecU2InitializationTSCB *storage)
{
    storage->type = 0;
    fast_bcopy(&SCSIConfiguration, &storage->configuration, 68);
    SCSIRGetMemoryTable(3, 255, storage->memoryTables[0]);
    SCSIRGetMemoryTable(0, 255, storage->memoryTables[1]);
    SCSIxMaximizeMemory(storage->memoryTables[1], storage->memoryTables[0]);
    memset(storage->memoryTables[2], 0, 72);
    SCSIxMaximizeMemory(storage->memoryTables[1], storage->memoryTables[2]);
    SCSIRGetMemoryTable(4, 255, storage->memoryTables[3]);
    SCSIRGetMemoryTable(5, 255, storage->memoryTables[4]);
    SCSIxMaximizeMemory(storage->memoryTables[3], storage->memoryTables[4]);
    return storage;
}

void SCSIGetConfiguration(AdaptecU2InitializationTSCB *initialization,
                         AdaptecU2Configuration *configuration,
                         unsigned int productID)
{
    fast_bcopy(&initialization->configuration, configuration, 68);
}

unsigned int SCSISetConfiguration(AdaptecU2InitializationTSCB *initialization,
                                  AdaptecU2Configuration *configuration,
                                  unsigned int productID)
{
    unsigned int count;
    if (configuration->maxInternalIOBlocks - 4 > 251 ||
        configuration->iobReserveSize != SCSIConfiguration.iobReserveSize ||
        configuration->memoryMapped > 2) return 7;
    if (configuration->maxInternalIOBlocks != initialization->configuration.maxInternalIOBlocks) {
        SCSIRGetMemoryTable(3, (unsigned char)configuration->maxInternalIOBlocks,
            initialization->memoryTables[0]);
        SCSIRGetMemoryTable(0, (unsigned char)configuration->maxInternalIOBlocks,
            initialization->memoryTables[1]);
        SCSIxMaximizeMemory(initialization->memoryTables[1], initialization->memoryTables[0]);
        memset(initialization->memoryTables[2], 0, 72);
        SCSIxMaximizeMemory(initialization->memoryTables[1], initialization->memoryTables[2]);
        count = configuration->maxInternalIOBlocks + 1;
        while (count) {
            configuration->maxInternalIOBlocks = count - 1;
            count &= count - 1;
        }
        SCSIRGetMemoryTable(4, (unsigned char)configuration->maxInternalIOBlocks,
            initialization->memoryTables[3]);
        count = configuration->maxInternalIOBlocks + 1;
        while (count) {
            configuration->maxInternalIOBlocks = count - 1;
            count &= count - 1;
        }
        SCSIRGetMemoryTable(5, (unsigned char)configuration->maxInternalIOBlocks,
            initialization->memoryTables[4]);
        SCSIxMaximizeMemory(initialization->memoryTables[3], initialization->memoryTables[4]);
    }
    fast_bcopy(configuration, &initialization->configuration, 68);
    return 0;
}

unsigned int SCSISizeAdapterTSCB(AdaptecU2InitializationTSCB *initialization,
                                unsigned int productID)
{
    return 2600;
}

AdaptecU2AdapterTSCB *SCSICreateAdapterTSCB(
    AdaptecU2InitializationTSCB *initialization, AdaptecU2AdapterTSCB *storage,
    AdaptecU2OSMContext context, AdaptecU2PciLocation location,
    unsigned int productID)
{
    const AdaptecU2MemoryDescriptor *table;
    storage->type = 1;
    storage->hhcb.numberScbs = (unsigned char)initialization->configuration.maxInternalIOBlocks;
    storage->osmContext = context;
    storage->hhcb.hardwareMode = 0;
    storage->memoryMapped = initialization->configuration.memoryMapped;
    if ((productID & 0xfff0ffff) == 0x78909004) {
        storage->hhcb.firmwareMode = 0;
        table = initialization->memoryTables[1];
    } else if ((productID & 0xff80ffff) == 0x9005) {
        storage->hhcb.hardwareMode = 1;
        storage->hhcb.firmwareMode = 4;
        table = initialization->memoryTables[3];
    } else {
        storage->hhcb.firmwareMode = 3;
        table = initialization->memoryTables[0];
    }
    fast_bcopy(table, storage->memoryTable, 72);
    storage->productID = productID;
    storage->location = location;
    return storage;
}

unsigned int SCSISetupAdapterTSCB(AdaptecU2AdapterTSCB *adapter,
                                 const AdaptecU2OSMFunctions *services,
                                 unsigned int size)
{
    fast_bcopy(services, &adapter->osm, size);
    return 0;
}

unsigned int SCSISaveState()
{
    register unsigned int machineR3 __asm__("r3");
    __asm__ volatile ("" : "=r" (machineR3));
    return machineR3;
}

unsigned int SCSIRestoreState()
{
    register unsigned int machineR3 __asm__("r3");
    __asm__ volatile ("" : "=r" (machineR3));
    return machineR3;
}

unsigned int SCSIProfileNexus()
{
    return 1;
}

unsigned int SCSIClearNexusTSH()
{
    return 1;
}

unsigned int SCSIProfileNode()
{
    return 1;
}

unsigned int SCSIReportAdjustableNodeProfile()
{
    return 1;
}

unsigned int SCSIAdjustNodeProfile()
{
    return 1;
}

unsigned int SCSISetOSMNodeContext()
{
    return 1;
}

unsigned int SCSISizeTargetTSCB(AdaptecU2AdapterTSCB *adapter)
{
    return 40;
}

void SCSIDisableIRQ(AdaptecU2AdapterTSCB *adapter)
{
    SCSIHDisableIRQ(&adapter->hhcb);
}

void SCSIEnableIRQ(AdaptecU2AdapterTSCB *adapter)
{
    SCSIHEnableIRQ(&adapter->hhcb);
}

unsigned int SCSIPollIRQ(AdaptecU2AdapterTSCB *adapter)
{
    return SCSIHPollIRQ(&adapter->hhcb) != 0;
}

unsigned int SCSIPowerEvent(AdaptecU2AdapterTSCB *adapter, unsigned int eventWord)
{
    return SCSIRPowerManagement(&adapter->hhcb, eventWord);
}

unsigned int SCSIValidateTargetTSH(AdaptecU2TargetTSCB *target)
{
    return SCSIxNonScamValidateLun(target);
}

unsigned int SCSIClearTargetTSH(AdaptecU2TargetTSCB *target)
{
    AdaptecU2AdapterTSCB *adapter = target->adapter;
    if (!SCSIRCheckDeviceIdle(&adapter->hhcb, (unsigned char)target->target))
        return 6;
    SCSIxClearLunExist(adapter->currentLuns, target->target, target->lun);
    SCSIxClearLunExist(adapter->previousLuns, target->target, target->lun);
    SCSIRFreeUnitHandle(&adapter->hhcb);
    return 0;
}

unsigned int SCSIReportAdjustableTargetProfile(unsigned int unusedWord,
                                               AdaptecU2TargetProfile *profile)
{
    fast_bcopy(&SCSIAdjustableTargetProfile, profile, 124);
    return 0;
}

unsigned int SCSICheckMemoryNeeded(
    AdaptecU2InitializationTSCB *initialization, AdaptecU2AdapterTSCB *adapter,
    unsigned int productID, unsigned int index, unsigned int *category,
    unsigned int *minimumSize, unsigned int *granularity,
    unsigned int *alignmentMask)
{
    AdaptecU2MemoryDescriptor *table;
    if (adapter) {
        table = adapter->memoryTable;
        if (!index) {
            unsigned char mode = adapter->hhcb.firmwareMode;
            memset(table, 0, 72);
            SCSIRGetMemoryTable(mode == 3 || mode == 4 || mode == 5 ? mode : 0,
                adapter->hhcb.numberScbs, table);
        }
    } else if ((productID & 0xfff0ffff) == 0x78909004)
        table = initialization->memoryTables[1];
    else if ((productID & 0xff80ffff) == 0x9005)
        table = initialization->memoryTables[3];
    else table = initialization->memoryTables[0];
    if (index <= 5) {
        *category = table[index].category;
        *granularity = table[index].granularity;
        if (table[index].size) {
            *minimumSize = table[index].minimumSize;
            *alignmentMask = table[index].alignmentMask;
            return table[index].size;
        }
        *alignmentMask = 0;
        *minimumSize = 0;
        return 4;
    }
    if (index == 6 || index == 7) {
        unsigned int size = index == 6 ? 160 : 114;
        *category = index == 6 ? 1 : 0;
        *granularity = 0;
        *minimumSize = size;
        *alignmentMask = 7;
        return size;
    }
    return 0;
}

unsigned int SCSISetMemoryPointer(AdaptecU2AdapterTSCB *adapter,
                                  unsigned int index, unsigned int category,
                                  unsigned char *address, unsigned int size)
{
    if (index <= 5) {
        adapter->memoryTable[index].address = address;
        adapter->memoryTable[index].size = (unsigned short)size;
    } else if (index == 6) adapter->scanBuffer = address;
    else if (index == 7) adapter->scanIOB = (AdaptecU2IOB *)address;
    else return 1;
    return 0;
}

unsigned int SCSIVerifyAdapter(AdaptecU2AdapterTSCB *adapter)
{
    unsigned int command, bar, product, subsystem, mask, allowed, index, count;
    command = adapter->osm.OSMReadPCIConfigurationDword(adapter->osmContext, 4);
    if (adapter->memoryMapped) {
        if (!(command & 2)) return 1;
        bar = 1;
    } else {
        if (!(command & 1)) return 1;
        bar = 0;
    }
    if (!(command & 4))
        adapter->osm.OSMWritePCIConfigurationDword(adapter->osmContext, 4, command | 4);
    if (adapter->osm.OSMMapIOHandle(adapter->osmContext, bar, 0, 256, 0, 2,
            &adapter->ioHandle)) return 5;
    adapter->word6c0 = 0;
    adapter->readRegister = adapter->osm.OSMReadUExact8;
    adapter->writeRegister = adapter->osm.OSMWriteUExact8;
    product = adapter->osm.OSMReadPCIConfigurationDword(adapter->osmContext, 0);
    subsystem = adapter->osm.OSMReadPCIConfigurationDword(adapter->osmContext, 44);
    if ((product == 0x78959004 && adapter->hhcb.bytes02[2] <= 4) ||
        product == 0x78609004 || product == 0x38609004) {
        index = 0;
        do {
            allowed = SCSIxGetNextSubSystemSubVendorID(index, &mask);
            if (!allowed) return 1;
            ++index;
        } while ((mask & subsystem) != allowed);
    }
    if (adapter->productID != product) return 5;
    adapter->hhcb.ioHandle = &adapter->ioHandle;
    switch (SCSIxDetermineFirmwareMode(adapter)) {
    case 0:
        adapter->hhcb.firmwareMode = 0;
        adapter->buildSCB = OSDStandard64BuildSCB;
        adapter->scbSize = 64;
        break;
    case 4:
        adapter->hhcb.firmwareMode = 4;
        adapter->buildSCB = OSDStandardAdvBuildSCB;
        adapter->scbSize = 64;
        break;
    case 5:
        adapter->hhcb.firmwareMode = 5;
        adapter->buildSCB = OSDSwappingAdvBuildSCB;
        adapter->scbSize = 64;
        break;
    default:
        adapter->hhcb.firmwareMode = 3;
        adapter->buildSCB = OSDSwapping32BuildSCB;
        adapter->scbSize = 32;
        break;
    }
    for (index = 0; index <= 15; ++index) adapter->lunCounts[index] = 64;
    adapter->hhcb.osmContext = adapter->osmContext;
    count = adapter->hhcb.numberScbs;
    SCSIRGetConfiguration(&adapter->hhcb);
    if (adapter->hhcb.numberScbs > count) adapter->hhcb.numberScbs = count;
    return 0;
}

unsigned int SCSIInitialize(AdaptecU2AdapterTSCB *adapter)
{
    unsigned char rates[16], disconnect[4], ultra[4], offsets[24];
    unsigned int i;
    if (SCSIRApplyMemoryTable(&adapter->hhcb, adapter->memoryTable)) return 1;
    SCSIxApplyNVData(adapter);
    if (SCSIxBiosExist(adapter) || SCSIxOptimaExist(adapter)) {
        SCSIHReadScratchRam(&adapter->hhcb, rates, 0, 16);
        SCSIHReadScratchRam(&adapter->hhcb, disconnect, 18, 2);
        SCSIHReadScratchRam(&adapter->hhcb, ultra, 16, 2);
        if (adapter->hhcb.hardwareMode == 1)
            SCSIHReadScratchRam(&adapter->hhcb, offsets, 64, 16);
        for (i = 0; i <= 15; ++i) {
            AdaptecU2DeviceTable *device = &adapter->hhcb.devices[i];
            if (adapter->hhcb.hardwareMode) {
                device->rate = rates[i] & 0x80;
                device->period = rates[i];
                device->offset = offsets[i];
                if (offsets[i] & 0x7f) {
                    device->rate |= 1;
                    device->flags |= 0x40;
                }
            } else {
                device->rate = rates[i] & 0xf0;
                if (rates[i] & 15) {
                    device->rate |= 1;
                    device->flags |= 0x40;
                }
            }
            device->flags &= ~0x20;
            device->flags = (device->flags & ~0x4000) |
                ((((disconnect[i >> 3] >> (i & 7)) ^ 1) << 14) & 0x4000);
            device->flags = (device->flags & ~0x8000) |
                ((ultra[i >> 3] >> (i & 7)) << 15);
        }
        adapter->hhcb.flags = (adapter->hhcb.flags & 0xbfefffff) | 0x100000;
        for (i = 0; i <= 15; ++i) adapter->hhcb.devices[i].flags &= ~4;
    } else {
        adapter->hhcb.flags |= 0x40000000;
        for (i = 0; i <= 15; ++i) adapter->hhcb.devices[i].flags |= 4;
    }
    adapter->flags |= 0x80000000;
    if (adapter->hhcb.hardwareMode == 1)
        OSDWritePciConfiguration(&adapter->hhcb, 64,
            OSDReadPciConfiguration(&adapter->hhcb, 64) & 0xffffffbf);
    if (!adapter->hhcb.hardwareMode &&
        !(OSDReadPciConfiguration(&adapter->hhcb, 64) & 0x1000))
        for (i = 0; i <= 15; ++i) adapter->hhcb.devices[i].flags &= ~0x8000;
    for (i = 0; i <= 15; ++i)
        if (!(adapter->hhcb.devices[i].rate & 1)) adapter->hhcb.devices[i].flags &= ~0x400;
    return SCSIRInitialize(&adapter->hhcb) != 0;
}

unsigned int SCSICheckTargetTSCBNeeded(AdaptecU2AdapterTSCB *adapter,
                                      unsigned int index)
{
    unsigned int target, lun, current;
    if (index == 0xffff) {
        current = SCSIxChkLunExist(adapter->currentLuns, adapter->lastTarget, adapter->lastLun);
        return current != SCSIxChkLunExist(adapter->previousLuns, adapter->lastTarget, adapter->lastLun);
    }
    for (target = 0; target <= 15; ++target)
        for (lun = 0; lun < adapter->lunCounts[target]; ++lun) {
            current = SCSIxChkLunExist(adapter->currentLuns, target, lun);
            if (current != SCSIxChkLunExist(adapter->previousLuns, target, lun)) return 1;
        }
    return 0;
}

AdaptecU2TargetTSCB *SCSICreateTargetTSCB(AdaptecU2AdapterTSCB *adapter,
                                      unsigned int index,
                                      AdaptecU2TargetTSCB *storage)
{
    unsigned char target, lun;
    unsigned int current;
    if (index == 0xffff) {
        target = (unsigned char)adapter->lastTarget;
        lun = (unsigned char)adapter->lastLun;
        current = SCSIxChkLunExist(adapter->currentLuns, target, lun);
        if (current == SCSIxChkLunExist(adapter->previousLuns, target, lun)) return 0;
    } else {
        for (target = 0; target <= 15; ++target)
            for (lun = 0; lun < adapter->lunCounts[target]; ++lun) {
                current = SCSIxChkLunExist(adapter->currentLuns, target, lun);
                if (current != SCSIxChkLunExist(adapter->previousLuns, target, lun)) goto found;
            }
        return 0;
    }
found:
    SCSIxSetLunExist(adapter->previousLuns, target, lun);
    storage->target = target;
    storage->lun = lun;
    storage->adapter = adapter;
    storage->type = 2;
    storage->flags = (-(unsigned int)((((adapter->hhcb.devices[target].flags & 0x4000) != 0)
        << target) & adapter->taggedTargets) & 0x80000000) | (storage->flags & 0x7fffffff);
    SCSIRSetUnitHandle(&adapter->hhcb, &storage->unit, target, lun);
    return storage;
}

unsigned int SCSIGetNVSize(AdaptecU2AdapterTSCB *adapter)
{
    unsigned int size = adapter->osm.OSMGetNVSize(adapter->osmContext);
    if (size) return size;
    size = SCSIHSizeSEEPROM(&adapter->hhcb);
    switch ((adapter->hhcb.idConfiguration >> 26) & 3) {
    case 0: return size * 2;
    case 1: return size;
    case 2: return 2 * size / 3;
    case 3: return size / 2;
    }
    return size;
}

unsigned int SCSIGetNVOSMSegment(AdaptecU2AdapterTSCB *adapter,
                                 unsigned int *offset, unsigned int *size)
{
    unsigned short words[34];
    unsigned int start = 0, length, mode;
    if (adapter->osm.OSMGetNVSize(adapter->osmContext)) return 2;
    mode = (adapter->hhcb.idConfiguration >> 26) & 3;
    if (mode == 2) {
        switch (adapter->location.words[2]) {
        case 2: case 8: start = 32; break;
        case 3: case 12: start = 64; break;
        }
    } else if (mode == 3) start = 32 * (adapter->location.words[2] - 4);
    else if (mode == 1 && !((adapter->hhcb.idConfiguration & 0x10000000) ?
        adapter->location.words[3] == 0 : adapter->location.words[2] == 4)) start = 32;
    if (SCSIHReadSEEPROM(&adapter->hhcb, words, start, 32)) return 2;
    length = SCSIHSizeSEEPROM(&adapter->hhcb);
    switch ((adapter->hhcb.idConfiguration >> 26) & 3) {
    case 0: *offset = 2 * start; *size = 2 * length; return 0;
    case 1: *offset = 2 * start; *size = length; return 0;
    case 2: *offset = 2 * start + 2 * start / 3; *size = 2 * length / 3; return 0;
    case 3: *offset = 2 * start; *size = length / 2; return 0;
    }
    *offset = 0;
    *size = 0;
    return 2;
}

unsigned int SCSIPutNVData(AdaptecU2AdapterTSCB *adapter,
                           unsigned int byteOffset, const unsigned short *data,
                           unsigned int byteCount)
{
    unsigned int status = adapter->osm.OSMPutNVData(adapter->osmContext,
        byteOffset, data, byteCount);
    if (status == 3)
        return SCSIHWriteSEEPROM(&adapter->hhcb, byteOffset >> 1,
            byteCount >> 1, data) != 0;
    return status;
}

unsigned int SCSIGetNVData(AdaptecU2AdapterTSCB *adapter, unsigned short *data,
                           unsigned int byteOffset, unsigned int byteCount)
{
    return adapter->osm.OSMGetNVData(adapter->osmContext, data, byteOffset,
        byteCount) != 0 && SCSIHReadSEEPROM(&adapter->hhcb, data,
            byteOffset >> 1, byteCount >> 1) != 0;
}

unsigned int SCSIProfileAdapter(AdaptecU2AdapterTSCB *adapter,
                                AdaptecU2AdapterProfile *profile)
{
    AdaptecU2HWInformation information;
    unsigned int i, *words = (unsigned int *)profile;
    SCSIRGetHWInformation(&information, &adapter->hhcb);
    fast_bcopy(&SCSIDefaultAdapterProfile, profile, 464);
    for (i = 0; i < profile->AP_WWIDLength; ++i)
        profile->AP_WorldWideID[i] = information.identification[i];
    profile->AP_BiosActive = adapter->biosFlags >> 31;
    profile->AP_ExtendedTrans = (adapter->biosFlags & 0x20000000) != 0;
    profile->AP_MaxTargets = adapter->hhcb.maxDevices;
    profile->AP_FIFOSeparateRWThreshold = (information.flags & 0x4000000) != 0;
    profile->AP_FIFOSeparateRWThresholdEnable = (information.flags & 0x8000000) != 0;
    if (!adapter->hhcb.hardwareMode) {
        switch (information.fifoThreshold) {
        case 0: profile->AP_FIFOThreshold = 13; break;
        case 1: profile->AP_FIFOThreshold = 50; break;
        case 2: profile->AP_FIFOThreshold = 75; break;
        case 3: profile->AP_FIFOThreshold = 100; break;
        }
    } else if (adapter->hhcb.hardwareMode == 1) {
        if (!(information.flags & 0x8000000)) {
            switch (information.fifoThreshold) {
            case 0: profile->AP_FIFOThreshold = 16; break;
            case 1: profile->AP_FIFOThreshold = 25; break;
            case 2: profile->AP_FIFOThreshold = 50; break;
            case 3: profile->AP_FIFOThreshold = 62; break;
            case 4: profile->AP_FIFOThreshold = 75; break;
            case 5: profile->AP_FIFOThreshold = 85; break;
            case 6: profile->AP_FIFOThreshold = 90; break;
            case 7: profile->AP_FIFOThreshold = 100; break;
            }
        } else {
            switch (information.readThreshold) {
            case 0: profile->AP_FIFOWriteThreshold = 16; break;
            case 16: profile->AP_FIFOWriteThreshold = 25; break;
            case 32: profile->AP_FIFOWriteThreshold = 50; break;
            case 48: profile->AP_FIFOWriteThreshold = 62; break;
            case 64: profile->AP_FIFOWriteThreshold = 75; break;
            case 80: profile->AP_FIFOWriteThreshold = 85; break;
            case 96: profile->AP_FIFOWriteThreshold = 90; break;
            case 112: profile->AP_FIFOWriteThreshold = 100; break;
            }
            switch (information.writeThreshold) {
            case 0: profile->AP_FIFOReadThreshold = 16; break;
            case 1: profile->AP_FIFOReadThreshold = 25; break;
            case 2: profile->AP_FIFOReadThreshold = 50; break;
            case 3: profile->AP_FIFOReadThreshold = 62; break;
            case 4: profile->AP_FIFOReadThreshold = 75; break;
            case 5: profile->AP_FIFOReadThreshold = 85; break;
            case 6: profile->AP_FIFOReadThreshold = 90; break;
            case 7: profile->AP_FIFOReadThreshold = 100; break;
            }
        }
    }
    profile->AP_LowestScanTarget = adapter->biosFlags & 0x80000000 ? adapter->biosDriveBase : 0xffff;
    profile->AP_AllocBusAddressSize = adapter->scbSize;
    words[65] = information.hostID;
    words[66] = 1;
    for (i = 0; i <= 15; ++i)
        if (adapter->hhcb.hardwareMode != 1 && (adapter->hhcb.devices[i].flags & 0x8000)) words[66] = 2;
    words[67] = information.flags & 0x80000000 ? 16 : 8;
    for (i = 0; i <= 15; ++i) words[68+i] = adapter->lunCounts[i];
    profile->AP_CacheLineStreaming = adapter->hhcb.hardware->getCacheThEn(&adapter->hhcb) != 0;
    profile->AP_MemoryMapped = adapter->memoryMapped;
    words[100] = (information.flags & 0x40000000) == 0;
    words[101] = 256 >> ((information.flags >> 28) & 3);
    words[46] = adapter->hhcb.bytes14[3];
    return 0;
}

unsigned int SCSIReportAdjustableAdapterProfile(AdaptecU2AdapterTSCB *adapter,
                                                AdaptecU2AdapterProfile *profile)
{
    fast_bcopy(&SCSIAdjustableAdapterProfile, profile, 464);
    if (!adapter->hhcb.hardwareMode) {
        profile->AP_FIFOSeparateRWThresholdEnable = 0;
        profile->AP_FIFOWriteThreshold = 0;
        profile->AP_FIFOReadThreshold = 0;
    }
    return 0;
}

unsigned int SCSIAdjustAdapterProfile(AdaptecU2AdapterTSCB *adapter,
                                       const AdaptecU2AdapterProfile *profile)
{
    AdaptecU2HWInformation information;
    const unsigned int *words = (const unsigned int *)profile;
    unsigned int i, value, code;
    if ((adapter->flags & 0x80000000) && !SCSIRCheckHostIdle(&adapter->hhcb)) return 2;
    SCSIRGetHWInformation(&information, &adapter->hhcb);
    if (((adapter->flags & 0x80000000) && information.hostID != (unsigned char)words[65]) ||
        (!profile->AP_FIFOSeparateRWThreshold && profile->AP_FIFOSeparateRWThresholdEnable == 1)) return 7;
    for (i = 0; i <= 15; ++i) adapter->lunCounts[i] = (unsigned char)words[68+i];
    if (!adapter->hhcb.hardwareMode) {
        value = profile->AP_FIFOThreshold;
        information.fifoThreshold = value <= 31 ? 0 : value <= 62 ? 1 : value <= 87 ? 2 : 3;
    } else if (adapter->hhcb.hardwareMode == 1) {
        if (profile->AP_FIFOSeparateRWThresholdEnable == 1) {
            information.flags |= 0x8000000;
            value = profile->AP_FIFOWriteThreshold;
            information.readThreshold = value <= 19 ? 0 : value <= 36 ? 1 : value <= 55 ? 2 :
                value <= 68 ? 3 : value <= 79 ? 4 : value <= 87 ? 5 : value <= 94 ? 6 : 7;
            value = profile->AP_FIFOReadThreshold;
            information.writeThreshold = value <= 19 ? 0 : value <= 36 ? 1 : value <= 55 ? 2 :
                value <= 68 ? 3 : value <= 79 ? 4 : value <= 87 ? 5 : value <= 94 ? 6 : 7;
        } else {
            information.flags &= ~0x8000000;
            value = profile->AP_FIFOThreshold;
            information.fifoThreshold = value <= 19 ? 0 : value <= 36 ? 1 : value <= 55 ? 2 :
                value <= 68 ? 3 : value <= 79 ? 4 : value <= 87 ? 5 : value <= 94 ? 6 : 7;
        }
    }
    information.hostID = (unsigned char)words[65];
    information.flags = (information.flags & 0xbfffffff) | ((words[100] != 1) << 30);
    value = words[101];
    code = value <= 48 ? 3 : value <= 96 ? 2 : value <= 192 ? 1 : 0;
    information.flags = (information.flags & 0xcfffffff) | (code << 28);
    SCSIRPutHWInformation(&information, &adapter->hhcb);
    return 0;
}

unsigned int SCSIProfileTarget(AdaptecU2TargetTSCB *target,
                               AdaptecU2TargetProfile *profile)
{
    AdaptecU2AdapterTSCB *adapter = target->adapter;
    AdaptecU2HWInformation information;
    unsigned int id = (unsigned char)target->target, i;
    SCSIRGetHWInformation(&information, &adapter->hhcb);
    fast_bcopy(&SCSIDefaultTargetProfile, profile, 124);
    profile->words[20] = 255;
    profile->words[12] = 0xffff;
    if (adapter->biosFlags & 0x80000000)
        for (i = 0; i < adapter->biosDriveCount; ++i)
            if (adapter->biosDrives[i].target == id) profile->words[12] = i + adapter->biosDriveBase;
    profile->words[15] = information.targets[id].queueDepth;
    profile->words[18] = id;
    profile->words[17] = (adapter->taggedTargets >> id) & 1;
    profile->words[19] = target->lun;
    profile->words[21] = information.targets[id].maximumSpeed;
    profile->words[22] = information.targets[id].requestedSpeed;
    profile->words[23] = information.targets[id].currentSpeed;
    profile->words[25] = information.targets[id].requestedOffset;
    profile->words[26] = information.targets[id].currentOffset;
    profile->words[24] = information.targets[id].maximumOffset;
    profile->words[27] = information.targets[id].maximumWidth;
    profile->words[28] = information.targets[id].requestedWidth;
    profile->words[29] = information.targets[id].currentWidth;
    if (information.targets[id].option == 143) {
        profile->words[23] = 0xffff;
        profile->words[26] = 255;
        profile->words[29] = 255;
        profile->words[24] = 15;
    }
    profile->words[30] = (adapter->hhcb.devices[id].flags & 0x4000) != 0;
    return 0;
}

unsigned int SCSIAdjustTargetProfile(AdaptecU2TargetTSCB *target,
                                      const AdaptecU2TargetProfile *profile)
{
    AdaptecU2AdapterTSCB *adapter = target->adapter;
    unsigned int id = (unsigned char)target->target;
    AdaptecU2DeviceTable *device = &adapter->hhcb.devices[id];
    AdaptecU2HWInformation information;
    unsigned int offset, width, speed, changed = 0;
    unsigned char scratch[16], selector;
    if (!SCSIRCheckDeviceIdle(&adapter->hhcb, id)) return 6;
    SCSIRGetHWInformation(&information, &adapter->hhcb);
    offset = information.targets[id].requestedOffset;
    width = information.targets[id].requestedWidth;
    speed = information.targets[id].requestedSpeed;
    if ((device->flags & 0x80) && profile->words[28] != width) {
        changed = 1;
        if (profile->words[28] <= 15) {
            device->flags &= ~0x200;
            width = 8;
            if (information.targets[id].option & 0x80) width = 16;
        } else {
            device->flags |= 0x200;
            width = 16;
        }
    }
    if ((device->flags & 0x100) &&
        (profile->words[22] != speed || profile->words[25] != offset)) {
        offset = profile->words[25];
        speed = profile->words[22];
        changed = 1;
        if (offset && speed >= information.minimumSpeed) device->flags |= 0x400;
        else {
            device->flags &= ~0x400;
            offset = information.targets[id].currentOffset;
        }
    }
    if (changed) {
        information.targets[id].changed = 1;
        information.targets[id].requestedSpeed = speed;
        information.targets[id].requestedOffset = offset;
        information.targets[id].requestedWidth = width;
    }
    device->flags = (device->flags & 0xbfff) | ((profile->words[30] == 1) << 14);
    if (profile->words[17] == 1)
        target->flags = (-(unsigned int)((((device->flags & 0x4000) != 0) << id) &
            adapter->taggedTargets) & 0x80000000) | (target->flags & 0x7fffffff);
    else target->flags &= 0x7fffffff;
    selector = adapter->hhcb.firmware->registers[6];
    if (selector != 255) {
        unsigned int shift = id > 7 ? id - 8 : id;
        unsigned int address = selector - (id > 7 ? 31 : 32);
        SCSIHReadScratchRam(&adapter->hhcb, scratch, address, 1);
        scratch[0] |= 1 << shift;
        scratch[0] &= ~(((device->flags & 0x4000) != 0) << shift);
        selector = adapter->hhcb.firmware->registers[6];
        SCSIHWriteScratchRam(&adapter->hhcb, selector - (id > 7 ? 31 : 32), 1, scratch);
    }
    information.targets[id].queueDepth = (unsigned char)profile->words[15];
    SCSIRPutHWInformation(&information, &adapter->hhcb);
    return 0;
}

void SCSIQueueIOB(AdaptecU2IOB *iob)
{
    AdaptecU2HIOB *hiob = &((AdaptecU2IOBReserve *)iob->reserve.virtualAddress)->hiob;
    AdaptecU2TransportSpecific *transport = iob->transportSpecific;
    AdaptecU2TargetTSCB *target = iob->taskSet.target;
    AdaptecU2HHCB *hhcb;
    AdaptecU2ResourceControl *resource;
    unsigned int tagged, limit;
    hiob->iob = iob;
    if (!iob->function) {
        hiob->context.unit = &target->unit;
        hiob->function = 0;
        hiob->control.flags &= ~0x8000;
        tagged = (target->flags & 0x80000000) && (!transport ||
            (!transport->word04 && !transport->word08)) && iob->taskAttribute != 3;
        if (transport) {
            hiob->control.flags = (hiob->control.flags & ~0x4000) | (tagged << 14);
            hiob->control.flags = (hiob->control.flags & ~0x2000) |
                ((transport->word08 == 1) << 13);
        } else hiob->control.flags = (hiob->control.flags & ~0x6000) | (tagged << 14);
        hiob->control.flags = (hiob->control.flags & ~0x1000) | ((iob->flags >> 19) & 0x1000);
        hiob->control.flags = (hiob->control.flags & ~0x800) | (((iob->flags & 0x4000000) != 0) << 11);
        hiob->priority = iob->priority;
        hiob->auxiliary.sense = iob->sense;
        hiob->senseLength = iob->senseLength > 255 ? 255 : iob->senseLength;
        hhcb = hiob->context.unit->hhcb;
        hiob->status = 0;
        hiob->hostStatus = 0;
        hiob->targetStatus = 0;
        hiob->managerStatus = 0;
        hiob->negotiationState = 0;
        resource = hiob->context.unit->resource;
        limit = hiob->control.flags & 0x4000 ? resource->taggedLimit : resource->nonTaggedLimit;
        if (++resource->activeCount > limit) {
            if (resource->freezeMask && hiob->priority > 127) {
                ++resource->recoveryCount;
                resource->freezeMask |= 0x20;
                SCSIrAllocateScb(hhcb, hiob);
            } else SCSIrDeviceQueueAppend(resource, hiob);
        } else if (hhcb->freeScbs <= 1) SCSIrHostQueueAppend(hhcb, hiob);
        else {
            --hhcb->freeScbs;
            hiob->scb = hhcb->freeHead;
            hhcb->freeHead = hhcb->freeHead->next;
            hiob->control.bytes.scbNumber = hiob->scb->number;
            hhcb->activeHiobs[hiob->control.bytes.scbNumber] = hiob;
            OSDBuildSCB(hiob);
            if (hhcb->firmware->patchXferOpt) hhcb->firmware->patchXferOpt(hhcb, hiob);
            OSMWriteUExact8(*hhcb->ioHandle, hhcb->firmware->registers[8], ++hhcb->qnewHead);
            __asm__ volatile ("sync" : : : "memory");
        }
        return;
    }
    switch (iob->function) {
    case 1: case 10:
        hiob->function = 1;
        hiob->context.related = &((AdaptecU2IOBReserve *)iob->related->reserve.virtualAddress)->hiob;
        break;
    case 2: hiob->function = 7; hiob->context.unit = &target->unit; break;
    case 3: iob->status = 17; iob->post(iob); return;
    case 4:
        if (target->type == 2) { hiob->function = 3; hiob->context.unit = &target->unit; }
        else if (target->type == 1) {
            hiob->function = 2;
            hiob->context.hhcb = &iob->taskSet.adapter->hhcb;
        } else { iob->status = 18; iob->post(iob); return; }
        break;
    case 5: hiob->function = 4; hiob->context.hhcb = &iob->taskSet.adapter->hhcb; break;
    case 6: hiob->function = 6; hiob->context.hhcb = &iob->taskSet.adapter->hhcb; break;
    case 7: iob->status = 1; iob->post(iob); return;
    case 8: case 9:
        iob->status = SCSIRCheckHostIdle(&iob->taskSet.adapter->hhcb) ? 1 : 20;
        iob->post(iob); return;
    case 11: hiob->function = 9; hiob->context.unit = &target->unit; break;
    case 19:
        if (transport->target == iob->taskSet.adapter->hhcb.hostID || !transport || transport->bus)
            break;
        iob->taskSet.adapter->scanOrigin = iob;
        SCSIxSetupLunProbe(iob->taskSet.adapter, transport->target, transport->lun);
        SCSIxQueueBusScan(iob->taskSet.adapter);
        iob->taskSet.adapter->lastTarget = transport->target;
        iob->taskSet.adapter->lastLun = transport->lun;
        return;
    default: break;
    }
    if (iob->function == 19 || (iob->function > 11 && iob->function != 19)) {
        iob->status = 16;
        iob->post(iob);
        return;
    }
    SCSIRQueueSpecialHIOB(hiob);
}

unsigned int SCSIFrontEndISR(AdaptecU2AdapterTSCB *adapter)
{
    AdaptecU2HHCB *hhcb = &adapter->hhcb;
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char *state = (unsigned char *)&hhcb->worddc;
    unsigned char pass, element, count, *entry, interrupt;
    unsigned int retry = 0, disposition;
    for (;;) {
        pass = hhcb->qdonePass;
        element = hhcb->qdoneElement;
        count = 0;
        entry = hhcb->qout + 8 * element;
        while (entry[7] == pass) {
            ++element;
            ++count;
            if (element == (unsigned char)(hhcb->numberScbs + 1)) {
                entry = hhcb->qout;
                ++pass;
                element = 0;
            } else entry += 8;
        }
        if (state[2] != count) {
            state[2] = count;
            state[0] |= 2;
            disposition = 2;
            OSMWriteUExact8(*handle, 146, 2);
            goto finish;
        }
        interrupt = SCSIhReadINTSTAT(hhcb);
        if (interrupt == 255) {
            state[0] = 0;
            disposition = 0;
            goto finish;
        }
        if (!(interrupt & 2)) break;
        if (retry) { OSMWriteUExact8(*handle, 146, 2); break; }
        retry = 1;
    }
    if (interrupt & 13) {
        if (interrupt & 1) state[0] |= interrupt & 0xf0;
        state[0] |= interrupt & 15;
        state[1] = OSMReadUExact8(*handle, 135);
        SCSIhWriteHCNTRL(hhcb, 4);
        if (hhcb->hardware->seqStretchWorkaround)
            hhcb->hardware->seqStretchWorkaround(hhcb);
    }
    disposition = interrupt & 15;
finish:
    __asm__ volatile ("sync" : : : "memory");
    return disposition > 0;
}

void SCSIBackEndISR(AdaptecU2AdapterTSCB *adapter)
{
    AdaptecU2HHCB *hhcb = &adapter->hhcb;
    AdaptecU2IOHandle *handle = hhcb->ioHandle;
    unsigned char *state = (unsigned char *)&hhcb->worddc;
    unsigned char interrupt = state[0], scb, sstat, current, clear, control;
    AdaptecU2HIOB *hiob, *queued;
    AdaptecU2ResourceControl *resource;
    AdaptecU2UnitControl *unit;
    AdaptecU2IOB *iob;
    unsigned int limit, goodTarget, active, status;
    state[0] = 0;
    if (interrupt & 2) {
        for (;;) {
            unsigned char *entry = hhcb->qout + 8 * hhcb->qdoneElement;
            if (entry[7] != hhcb->qdonePass) break;
            scb = entry[0];
            if (++hhcb->qdoneElement == (unsigned char)(hhcb->numberScbs + 1)) {
                hhcb->qdoneElement = 0;
                ++hhcb->qdonePass;
            }
            hiob = hhcb->activeHiobs[scb];
            if (hiob->managerStatus != 5) {
                unit = hiob->context.unit;
                hhcb->activeHiobs[hiob->control.bytes.scbNumber] = (AdaptecU2HIOB *)-1;
                goodTarget = hiob->targetStatus == 0 || hiob->targetStatus == 4 ||
                    hiob->targetStatus == 16 || hiob->targetStatus == 20;
                if (hiob->hostStatus || !goodTarget) {
                    if (hiob->status == 2) {
                        if (hiob->hostStatus == 4 || hiob->hostStatus == 8) {
                            if (goodTarget) goto complete;
                            hiob->hostStatus = 0;
                        }
                        hiob->status = 3;
                    } else if ((hiob->hostStatus == 4 || hiob->hostStatus == 8) && goodTarget)
                        hiob->status = 1;
                    else hiob->status = 3;
                } else hiob->status = 1;
complete:
                if (hiob->function) {
                    if (hiob->function == 3) {
                        control = OSMReadUExact8(*handle, 135);
                        if (!(control & 4)) SCSIhPauseAndWait(hhcb);
                        hhcb->firmware->xferOptAssign(hhcb, unit->target,
                            unit->device->byte07 & 0x81 ? 143 : 0);
                        if (!(control & 4)) SCSIhWriteHCNTRL(hhcb, control);
                    }
                    SCSIrCompleteSpecialHIOB(hiob);
                } else {
                    if (hhcb->hostHead == (AdaptecU2HIOB *)-1) {
                        ++hhcb->freeScbs;
                        hhcb->freeTail->next = hiob->scb;
                        hhcb->freeTail = hiob->scb;
                    } else {
                        queued = hhcb->firmware->hostQueueRemove(hhcb, hiob->control.bytes.scbNumber);
                        hhcb->firmware->returnScb(hhcb, hiob);
                        queued->control.bytes.scbNumber = hhcb->firmware->getScb(hhcb, queued);
                        if (queued->function) SCSIHQueueSpecialHIOB(queued);
                        else SCSIHQueueHIOB(queued);
                    }
                    unit = hiob->context.unit;
                    resource = unit->resource;
                    limit = hiob->control.flags & 0x4000 ? resource->taggedLimit : resource->nonTaggedLimit;
                    if (resource->freezeMask) {
                        --resource->activeCount;
                        if (SCSIHCheckDeviceIdle(hhcb, unit->target) && (resource->freezeMask & 1))
                            SCSIrFinishQueueFull(hiob);
                        if (resource->freezeMask && hiob->priority > 127 && !--resource->recoveryCount) {
                            SCSIrUnFreezeDeviceQueue(hiob->context.unit->resource, 32);
                            SCSIrDispatchQueuedHIOB(hiob);
                        }
                    } else {
                        active = --resource->activeCount;
                        if (active >= limit && resource->head != (AdaptecU2HIOB *)-1) {
                            queued = resource->head;
                            limit = queued->control.flags & 0x4000 ? resource->taggedLimit : resource->nonTaggedLimit;
                            if (limit > resource->activeCount - resource->queuedCount) {
                                if (resource->head == resource->tail) {
                                    resource->tail = (AdaptecU2HIOB *)-1;
                                    resource->head = (AdaptecU2HIOB *)-1;
                                } else resource->head = resource->head->next;
                                --resource->queuedCount;
                                SCSIrAllocateScb(unit->hhcb, queued);
                            }
                        }
                    }
                    current = hhcb->doneHead++;
                    hhcb->doneHiobs[current] = hiob;
                    if (hhcb->doneHead == hhcb->numberScbs) hhcb->doneHead = 0;
                }
            }
            if (!--state[2]) break;
        }
        if (state[2]) {
            handle = hhcb->ioHandle;
            OSMWriteUExact8(*handle, 146, 2);
            state[2] = 0;
        }
    }
    if (interrupt & 13) {
        for (;;) {
            interrupt = SCSIhReadINTSTAT(hhcb);
            if (!(interrupt & 13) || interrupt == 255) break;
            if (hhcb->hardware->seqStretchWorkaround)
                hhcb->hardware->seqStretchWorkaround(hhcb);
            sstat = OSMReadUExact8(*handle, 12);
            if (sstat & 0x20) { SCSIhIntSrst(hhcb); continue; }
            if (OSMReadUExact8(*handle, 11) & 8) { SCSIhIntIOError(hhcb); continue; }
            scb = OSMReadUExact8(*handle, hhcb->firmware->registers[sstat & 0x80 ? 4 : 3]);
            hiob = scb == 255 ? (AdaptecU2HIOB *)-1 : hhcb->activeHiobs[scb];
            if (interrupt & 1) {
                status = interrupt & 0xf0;
                if (scb == 255 && status != 0xa0) status = 0x80;
                switch (status) {
                case 0: SCSIhNegotiate(hhcb, hiob); break;
                case 0x10: SCSIhCdbAbort(hhcb); break;
                case 0x20: SCSIhHandleMsgOut(hhcb, hiob); break;
                case 0x30: SCSIhCheckLength(hhcb, hiob); break;
                case 0x40: SCSIhHandleMsgIn(hhcb, hiob); break;
                case 0x50: SCSIhCheckCondition(hhcb, hiob); break;
                case 0x60: SCSIhBadSeq(hhcb); break;
                case 0x70: SCSIhExtMsgi(hhcb, hiob); break;
                case 0x80: case 0x90: SCSIhAbortTarget(hhcb, hiob); break;
                case 0xa0: case 0xb0: SCSIhBreakInterrupt(hhcb, hiob); break;
                }
                clear = 1;
            } else if (interrupt & 4) {
                if (sstat & 0x80) SCSIhIntSelto(hhcb, hiob);
                else if (sstat & 8) SCSIhIntFree(hhcb, hiob);
                else if (sstat & 4) SCSIhParityError(hhcb, hiob);
                clear = 4;
            } else if (interrupt & 8) {
                SCSIhBreakInterrupt(hhcb, hiob);
                clear = 8;
            } else goto restore;
            OSMWriteUExact8(*handle, 146, clear);
restore:
            SCSIhWriteHCNTRL(hhcb, state[1] & 2);
        }
    }
    __asm__ volatile ("sync" : : : "memory");
    while (hhcb->doneHead != hhcb->doneTail) {
        current = hhcb->doneTail++;
        if (hhcb->doneTail == hhcb->numberScbs) hhcb->doneTail = 0;
        hiob = hhcb->doneHiobs[current];
        iob = hiob->iob;
        if (hiob->status == 1) status = 1;
        else if (hiob->status == 2) {
            switch (hiob->hostStatus) {
            case 4: status = 64; break;
            case 5: status = 66; break;
            case 6: status = 65; break;
            case 7: status = 67; break;
            case 8: status = 69; break;
            case 9: status = 75; break;
            case 0x14: case 0x20: status = 80; break;
            default: goto post;
            }
        } else if (hiob->status == 3) {
            switch (hiob->hostStatus) {
            case 0: case 0x12:
                switch (hiob->targetStatus) {
                case 0: case 4: case 0x10: case 0x14:
                    if (hiob->hostStatus != 0x12) { status = 1; break; }
                    iob->status = 36;
                    iob->residualLength = hiob->residualLength;
                    goto post;
                case 2:
                    if (!(iob->flags & 0x80000000)) iob->status = 3;
                    else {
                        iob->status = 2;
                        iob->residualSense = hiob->residualSense;
                        if (iob->senseLength > 255)
                            iob->residualSense = hiob->residualSense - 255 + iob->senseLength;
                    }
                    if (hiob->hostStatus == 0x12) iob->residualLength = hiob->residualLength;
                    goto post;
                case 8: status = 48; break;
                case 0x18: status = 50; break;
                case 0x28: status = 49; break;
                default: status = 96; break;
                }
                break;
            case 0x11: status = 32; break;
            case 0x13: status = 34; break;
            case 0x14: case 0x20: status = 80; break;
            case 0x1b: status = 5; break;
            case 0x24: status = 72; break;
            case 0x26: status = 74; break;
            case 0x48: status = 35; break;
            default: goto post;
            }
        } else if (hiob->status == 0 && hiob->hostStatus == 0x25) status = 73;
        else goto post;
        iob->status = status;
post:
        iob->post(iob);
    }
}
