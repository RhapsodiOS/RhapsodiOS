#import "AdaptecU2SCSIPrivate.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/IODevice.h>
#import <driverkit/ppc/IOPCIDevice.h>
#import <kernserv/kalloc.h>
#import <kernserv/ns_timer.h>
#import <mach/vm_param.h>
#import <machdep/ppc/pmap.h>
#import <machdep/ppc/proc_reg.h>

void *AdptMallocContiguous(unsigned int size)
{
    unsigned int allocation, address;

    if (size == 0 || size > page_size)
        return 0;
    allocation = (unsigned int)kalloc(size * 2 + 4);
    if (allocation == 0)
        return 0;
    address = allocation + 4;
    if ((address >> page_shift) != ((address + size - 1) >> page_shift))
        address = (address + page_mask) & ~page_mask;
    *(unsigned int *)(address - 4) = allocation;
    return (void *)address;
}

void AdptFreeContiguous(void *address, unsigned int size)
{
    kfree(*(vm_offset_t *)((unsigned char *)address - 4), size * 2 + 4);
}

unsigned short sub_189120(unsigned short value)
{
    unsigned short result;
    __asm__ ("lhbrx %0,0,%1" : "=r" (result) : "r" (&value));
    return result;
}

unsigned int sub_18914C(unsigned int value)
{
    unsigned int result;
    __asm__ ("lwbrx %0,0,%1" : "=r" (result) : "r" (&value));
    return result;
}

unsigned short sub_189174(unsigned short value)
{
    return value;
}

unsigned int sub_18918C(unsigned int value)
{
    return value;
}

unsigned short sub_1891A0(unsigned short value)
{
    return value;
}

unsigned int sub_1891B0(unsigned int value)
{
    return value;
}

unsigned char OSMReadUExact8(AdaptecU2IOHandle handle, unsigned int offset)
{
    return handle.base[offset];
}

unsigned short OSMReadUExact16(AdaptecU2IOHandle handle, unsigned int offset)
{
    unsigned short value;
    volatile unsigned char *address = handle.base + offset;
    if (handle.accessMode & 2)
        __asm__ volatile ("lhbrx %0,0,%1" : "=r" (value) : "r" (address) : "memory");
    else
        value = *(volatile unsigned short *)address;
    return value;
}

unsigned int OSMReadUExact32(AdaptecU2IOHandle handle, unsigned int offset)
{
    unsigned int value;
    volatile unsigned char *address = handle.base + offset;
    if (handle.accessMode & 2)
        __asm__ volatile ("lwbrx %0,0,%1" : "=r" (value) : "r" (address) : "memory");
    else
        value = *(volatile unsigned int *)address;
    return value;
}

void OSMReadStringUExact8(AdaptecU2IOHandle handle, unsigned int offset,
                         unsigned char *data, unsigned int count,
                         unsigned int strideWords)
{
    unsigned int index, displacement = 0;
    for (index = 0; index < count; ++index) {
        data[index] = handle.base[offset + 4 * displacement];
        displacement += strideWords;
    }
}

void OSMReadStringUExact16(AdaptecU2IOHandle handle, unsigned int offset,
                          unsigned short *data, unsigned int count,
                          unsigned int strideWords)
{
    unsigned short (*convert)(unsigned short) = sub_1891A0;
    unsigned int index, displacement = 0;
    if (handle.accessMode & 2)
        convert = sub_189120;
    else if (handle.accessMode & 1)
        convert = sub_189174;
    for (index = 0; index < count; ++index) {
        data[index] = convert(*(volatile unsigned short *)(handle.base + offset + 4 * displacement));
        displacement += strideWords;
    }
}

void OSMReadStringUExact32(AdaptecU2IOHandle handle, unsigned int offset,
                          unsigned int *data, unsigned int count,
                          unsigned int strideWords)
{
    unsigned int (*convert)(unsigned int) = sub_1891B0;
    unsigned int index, displacement = 0;
    if (handle.accessMode & 2)
        convert = sub_18914C;
    else if (handle.accessMode & 1)
        convert = sub_18918C;
    for (index = 0; index < count; ++index) {
        data[index] = convert(*(volatile unsigned int *)(handle.base + offset + 4 * displacement));
        displacement += strideWords;
    }
}

void OSMWriteUExact8(AdaptecU2IOHandle handle, unsigned int offset,
                     unsigned char value)
{
    handle.base[offset] = value;
    eieio();
}

void OSMWriteUExact16(AdaptecU2IOHandle handle, unsigned int offset,
                      unsigned short value)
{
    volatile unsigned char *address = handle.base + offset;
    if (handle.accessMode & 2)
        __asm__ volatile ("sthbrx %0,0,%1" : : "r" (value), "r" (address) : "memory");
    else
        *(volatile unsigned short *)address = value;
    eieio();
}

void OSMWriteUExact32(AdaptecU2IOHandle handle, unsigned int offset,
                      unsigned int value)
{
    volatile unsigned char *address = handle.base + offset;
    if (handle.accessMode & 2)
        __asm__ volatile ("stwbrx %0,0,%1" : : "r" (value), "r" (address) : "memory");
    else
        *(volatile unsigned int *)address = value;
    eieio();
}

void OSMWriteStringUExact8(AdaptecU2IOHandle handle, unsigned int offset,
                          const unsigned char *data, unsigned int count,
                          unsigned int strideWords)
{
    unsigned int index, displacement = 0;
    for (index = 0; index < count; ++index) {
        handle.base[offset + 4 * displacement] = data[index];
        eieio();
        displacement += strideWords;
    }
}

void OSMWriteStringUExact16(AdaptecU2IOHandle handle, unsigned int offset,
                           const unsigned short *data, unsigned int count,
                           unsigned int strideWords)
{
    unsigned short (*convert)(unsigned short) = sub_1891A0;
    unsigned int index, displacement = 0;
    if (handle.accessMode & 2)
        convert = sub_189120;
    else if (handle.accessMode & 1)
        convert = sub_189174;
    for (index = 0; index < count; ++index) {
        *(volatile unsigned short *)(handle.base + offset + 4 * displacement) = convert(data[index]);
        eieio();
        displacement += strideWords;
    }
}

void OSMWriteStringUExact32(AdaptecU2IOHandle handle, unsigned int offset,
                           const unsigned int *data, unsigned int count,
                           unsigned int strideWords)
{
    unsigned int (*convert)(unsigned int) = sub_1891B0;
    unsigned int index, displacement = 0;
    if (handle.accessMode & 2)
        convert = sub_18914C;
    else if (handle.accessMode & 1)
        convert = sub_18918C;
    for (index = 0; index < count; ++index) {
        *(volatile unsigned int *)(handle.base + offset + 4 * displacement) = convert(data[index]);
        eieio();
        displacement += strideWords;
    }
}

unsigned int OSMGetBusAddress(AdaptecU2OSMContext context,
                              unsigned int categoryWord,
                              const unsigned char *virtualAddress)
{
    unsigned int physical;
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)virtualAddress, &physical) == 0)
        return physical;
    IOLog("Cannot get physical address for virtual 0x%x\n", (unsigned int)virtualAddress);
    return 0;
}

void OSMAdjustBusAddress(unsigned int *busAddress, unsigned int offset)
{
    *busAddress += offset;
}

unsigned int OSMGetNVSize(AdaptecU2OSMContext context)
{
    return 0;
}

unsigned int OSMPutNVData(AdaptecU2OSMContext context, unsigned int byteOffset,
                           const unsigned short *data, unsigned int byteCount)
{
    return 3;
}

unsigned int OSMGetNVData(AdaptecU2OSMContext context, unsigned short *data,
                           unsigned int byteOffset, unsigned int byteCount)
{
    return 1;
}

void OSMWatchdog(AdaptecU2OSMContext context,
                  void (*routine)(AdaptecU2AdapterTSCB *),
                  unsigned int microseconds)
{
    ns_timeout((func)routine, ((AdaptecU2SCSI *)context)->adapterTSH,
               (unsigned long long)microseconds * 1000, 4);
}

unsigned int OSMReadPCIConfigurationDword(AdaptecU2OSMContext context,
                                         unsigned int offset)
{
    UInt32 value;
    unsigned int aligned = offset & ~3;
    IOReturn result = [[(id)context deviceDescription] configReadLong:aligned value:&value];
    if (result == 0)
        return value;
    IOLog("OSMReadPCIConfigurationDWord failed.\n");
    IOLog("Error: %s\n", [IODevice stringFromReturn:result]);
    IOLog("Register: 0x%lx\n", (unsigned long)aligned);
    IOLog("Context: 0x%x\n", (unsigned int)context);
    return 0;
}

unsigned short OSMReadPCIConfigurationWord(AdaptecU2OSMContext context,
                                           unsigned char offset)
{
    UInt32 value;
    unsigned int aligned = offset & 0xfc;
    IOReturn result = [[(id)context deviceDescription] configReadLong:aligned value:&value];
    if (result == 0)
        return value >> (8 * (offset & 3));
    IOLog("OSMReadPCIConfigurationWord failed.\n");
    IOLog("Error: %s\n", [IODevice stringFromReturn:result]);
    IOLog("Register: 0x%x\n", aligned);
    IOLog("Context: 0x%x\n", (unsigned int)context);
    return 0;
}

unsigned char OSMReadPCIConfigurationByte(AdaptecU2OSMContext context,
                                          unsigned char offset)
{
    UInt32 value;
    unsigned int aligned = offset & 0xfc;
    IOReturn result = [[(id)context deviceDescription] configReadLong:aligned value:&value];
    if (result == 0)
        return value >> (8 * (offset & 3));
    IOLog("OSMReadPCIConfigurationByte failed.\n");
    IOLog("Error: %s\n", [IODevice stringFromReturn:result]);
    IOLog("Register: 0x%x\n", aligned);
    IOLog("Context: 0x%x\n", (unsigned int)context);
    return 0;
}

void OSMWritePCIConfigurationDword(AdaptecU2OSMContext context,
                                   unsigned char offset, unsigned int value)
{
    unsigned int aligned = offset & 0xfc;
    IOReturn result = [[(id)context deviceDescription] configWriteLong:aligned value:value];
    if (result != 0) {
        IOLog("OSMWritePCIConfigurationDword.\n");
        IOLog("setPCIConfigData Error: %s\n", [IODevice stringFromReturn:result]);
        IOLog("Register: 0x%x\n", aligned);
        IOLog("Value: 0x%x\n", value);
        IOLog("Context: 0x%x\n", (unsigned int)context);
    }
}

void OSMWritePCIConfigurationWord(AdaptecU2OSMContext context,
                                  unsigned char offset, unsigned short value)
{
    UInt32 current;
    unsigned int shift = 8 * (offset & 3), aligned = offset & 0xfc;
    IOReturn result = [[(id)context deviceDescription] configReadLong:aligned value:&current];
    if (result != 0) {
        IOLog("OSMWritePCIConfigurationWord.\n");
        IOLog("getPCIConfigData Error: %s\n", [IODevice stringFromReturn:result]);
        IOLog("Register: 0x%x\n", aligned);
        IOLog("Context: 0x%x\n", (unsigned int)context);
    }
    current = (current & ~(0xffffU << shift)) | ((unsigned int)value << shift);
    result = [[(id)context deviceDescription] configWriteLong:aligned value:current];
    if (result != 0) {
        IOLog("OSMWritePCIConfigurationWord.\n");
        IOLog("setPCIConfigData Error: %s\n", [IODevice stringFromReturn:result]);
        IOLog("Register: 0x%x\n", aligned);
        IOLog("Value: 0x%x\n", value);
        IOLog("Context: 0x%x\n", (unsigned int)context);
    }
}

void OSMWritePCIConfigurationByte(AdaptecU2OSMContext context,
                                  unsigned char offset, unsigned char value)
{
    UInt32 current;
    unsigned int shift = 8 * (offset & 3), aligned = offset & 0xfc;
    IOReturn result = [[(id)context deviceDescription] configReadLong:aligned value:&current];
    if (result != 0) {
        IOLog("OSMWritePCIConfigurationByte.\n");
        IOLog("getPCIConfigData Error: %s\n", [IODevice stringFromReturn:result]);
        IOLog("Register: 0x%x\n", aligned);
        IOLog("Context: 0x%x\n", (unsigned int)context);
    }
    current = (current & ~(0xffU << shift)) | ((unsigned int)value << shift);
    result = [[(id)context deviceDescription] configWriteLong:aligned value:current];
    if (result != 0) {
        IOLog("OSMWritePCIConfigurationByte failed.\n");
        IOLog("setPCIConfigData Error: %s\n", [IODevice stringFromReturn:result]);
        IOLog("Register: 0x%x\n", aligned);
        IOLog("Value: 0x%x\n", value);
        IOLog("Context: 0x%x\n", (unsigned int)context);
    }
}

unsigned int OSMMapIOHandle(AdaptecU2OSMContext context,
                            unsigned int barIndex, unsigned int offset,
                            unsigned int length, unsigned int unusedWord,
                            unsigned int accessMode, AdaptecU2IOHandle *output)
{
    AdaptecU2SCSI *controller = (AdaptecU2SCSI *)context;
    AdaptecU2IOHandle *node = IOMalloc(32), *tail;
    UInt32 bar;
    unsigned int physical, reg = barIndex * 4 + 16;
    vm_address_t mapping;

    if ([[(id)context deviceDescription] configReadLong:reg value:&bar] != 0) {
        IOLog("AdaptecU2SCSI: Cannot aquire PCI config data in reg: 0x%x.\n", reg);
        return 1;
    }
    if (bar & 1) {
        mapping = (vm_address_t)[[(id)context deviceDescription] getIOAperture] + (bar & ~3);
        node->mapped = 1;
        node->base = (unsigned char *)(mapping + offset);
        node->mappingBase = (unsigned char *)mapping;
    } else {
        physical = bar & ~15;
        if (pmap_add_physical_memory(physical, physical + offset + length, 0, 7) != 0) {
            IOLog("AdaptecU2SCSI: pmap_add_physical_memory() failed\n");
            return 1;
        }
        if (IOMapPhysicalIntoIOTask(physical & ~page_mask,
                                    (offset + length + page_mask) & ~page_mask,
                                    &mapping) != 0) {
            IOLog("AdaptecU2SCSI: IOMapPhysicalIntoIOTask failed for 0x%x\n", physical);
            return 1;
        }
        node->mappingBase = (unsigned char *)mapping;
        node->mapped = 1;
        node->base = (unsigned char *)(mapping + physical - physical / page_size * page_size + offset);
    }
    node->accessMode = accessMode;
    node->length = length;
    node->offset = offset;
    tail = (AdaptecU2IOHandle *)controller->handleQ.prev;
    if ((void *)tail == &controller->handleQ)
        controller->handleQ.next = (queue_entry_t)node;
    else
        tail->next = node;
    node->prev = tail;
    node->next = (AdaptecU2IOHandle *)&controller->handleQ;
    controller->handleQ.prev = (queue_entry_t)node;
    *output = *node;
    return 0;
}

unsigned int OSMReleaseIOHandle(AdaptecU2OSMContext context, AdaptecU2IOHandle handle)
{
    AdaptecU2SCSI *controller = (AdaptecU2SCSI *)context;
    AdaptecU2IOHandle *node, *next;
    if (handle.mapped == 1)
        IOUnmapPhysicalFromIOTask((unsigned int)handle.mappingBase & ~page_mask,
                                  (handle.length + handle.offset + page_mask) & ~page_mask);
    node = (AdaptecU2IOHandle *)controller->handleQ.next;
    while ((void *)node != &controller->handleQ) {
        next = node->next;
        if (next == handle.next) {
            if ((void *)next == &controller->handleQ)
                controller->handleQ.prev = (queue_entry_t)handle.prev;
            else
                next->prev = handle.prev;
            if ((void *)handle.prev == &controller->handleQ)
                controller->handleQ.next = (queue_entry_t)next;
            else
                handle.prev->next = next;
            IOFree(node, 32);
            break;
        }
        node = next;
    }
    return 0;
}

/* This aggregate is an implementation carrier for eight machine words.
 * It does not identify the erased source formals or give them handle meaning. */
unsigned int OSMSynchronizeRange(AdaptecU2IOHandle machineWords)
{
    return (unsigned int)machineWords.base;
}

unsigned int OSMSaveInterruptState()
{
    return 0;
}

unsigned int OSMSetInterruptState()
{
    register unsigned int machineR3 __asm__("r3");
    __asm__ volatile ("" : "=r" (machineR3));
    return machineR3;
}
