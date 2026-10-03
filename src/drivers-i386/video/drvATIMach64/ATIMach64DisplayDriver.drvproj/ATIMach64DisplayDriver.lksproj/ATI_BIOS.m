#define KERNEL_PRIVATE 1
#define DRIVER_PRIVATE 1

#import "ATI_BIOS.h"
#import <driverkit/generalFuncs.h>
#import <machdep/i386/gdt.h>
#import <machdep/i386/pmap.h>
#import <mach/i386/vm_param.h>
#import <strings.h>
#import <string.h>

extern unsigned char _bios16[];

static unsigned char *gdtEntry(unsigned int selector)
{
    return (unsigned char *)gdt + selector;
}

static void setDescriptorBase(unsigned char *descriptor,
                              unsigned int baseLowSource,
                              unsigned int translatedBase)
{
    *(unsigned short *)(descriptor + 2) = (unsigned short)baseLowSource;
    descriptor[4] = (unsigned char)(translatedBase >> 16);
    descriptor[7] = (unsigned char)(translatedBase >> 24);
}

@implementation ATI_BIOS

- initAtSegmentAddress:(unsigned int)segmentAddress
{
    segmentBase = segmentAddress;
    _priv = IOMalloc(ATIBIOSPrivateSize);
    initialized = 1;
    return [super init];
}

- free
{
    if (initialized != 0)
        IOFree(_priv, ATIBIOSPrivateSize);
    return [super free];
}

@end

@implementation ATI_BIOS (Private)

- (int)initBIOSBuf:(ATIBIOSRegisters *)registers function:(char)function
{
    [self setupCodeSegments];
    bzero(registers, ATIBIOSRegisterBufferSize);
    registers->eax = (unsigned char)function;
    registers->codeSelector = 0x80;
    registers->dataSelector = 0x10;
    registers->entryOffset = 100;
    registers->ebp = (unsigned short)ATI_Bios_StackOffset >> 1;
    return (int)registers->ebp;
}

- (void)setupCodeSegments
{
    unsigned char *descriptor;
    unsigned char *privateBytes;
    unsigned int translatedBase;
    unsigned int stackAddress;

    privateBytes = (unsigned char *)_priv;
    memcpy(privateBytes, gdtEntry(0x80), 8);
    memcpy(privateBytes + 8, gdtEntry(0x90), 8);
    memcpy(privateBytes + 24, gdtEntry(0x98), 8);

    descriptor = gdtEntry(0x80);
    translatedBase = segmentBase - VM_MAX_KERNEL_ADDRESS;
    setDescriptorBase(descriptor, segmentBase, translatedBase);
    *(unsigned short *)descriptor = 0xffff;
    descriptor[5] = 0x9a;
    descriptor[6] = (descriptor[6] & 0x30) & (unsigned char)~0xc0;

    descriptor = gdtEntry(0x90);
    translatedBase = (unsigned int)_bios16 + KERNEL_LINEAR_BASE;
    setDescriptorBase(descriptor, (unsigned int)_bios16, translatedBase);
    *(unsigned short *)descriptor = 0xffff;
    descriptor[5] = 0x9a;
    descriptor[6] = (descriptor[6] & 0x30) | 0x40;

    stackAddress = (unsigned int)IOMalloc(0x800);
    *((unsigned int *)(privateBytes + 32)) = stackAddress;
    bzero((void *)stackAddress, 0x800);
    descriptor = gdtEntry(0x98);
    translatedBase = stackAddress - VM_MAX_KERNEL_ADDRESS;
    setDescriptorBase(descriptor, stackAddress, translatedBase);
    *(unsigned short *)descriptor = 0x07ff;
    descriptor[5] = 0x92;
    descriptor[6] = (descriptor[6] & 0x30) | 0x40;
    descriptor[6] &= (unsigned char)~0x40;

    ATI_Bios_StackOffset = 0x800;
    ATI_Bios_StackSelector = 0x98;
}

- (void)restoreCodeSegments
{
    unsigned char *privateBytes;

    privateBytes = (unsigned char *)_priv;
    memcpy(gdtEntry(0x80), privateBytes, 8);
    memcpy(gdtEntry(0x90), privateBytes + 8, 8);
    memcpy(gdtEntry(0x98), privateBytes + 24, 8);
    IOFree(*(void **)(privateBytes + 32), 0x800);
}

- (int)createDataSegment:(unsigned int)address size:(unsigned int)size
{
    unsigned char *descriptor;
    unsigned char *privateBytes;
    unsigned int limit;
    unsigned int encodedLimit;
    unsigned int translatedBase;
    unsigned char granularity;

    if (size > 0x10000) {
        IOLog("ATI_BIOS: Data Segment size exceeded (0x%x)\n", size);
        return ATIBIOSStatusInvalid;
    }

    privateBytes = (unsigned char *)_priv;
    memcpy(privateBytes + 16, gdtEntry(0x88), 8);
    descriptor = gdtEntry(0x88);
    translatedBase = address - VM_MAX_KERNEL_ADDRESS;
    setDescriptorBase(descriptor, address, translatedBase);
    descriptor[5] = 0x92;

    limit = size - 1;
    granularity = (limit > 0xfffff) ? 0x80 : 0;
    if (granularity != 0) {
        encodedLimit = (((size + 0xfff) & 0xfffff000) - 0x1000) >> 12;
        limit = encodedLimit;
        encodedLimit = (((size + 0xfff) & 0xfffff000) - 0x1000) >> 28;
    } else {
        encodedLimit = (limit >> 16) & 0x0f;
    }
    *(unsigned short *)descriptor = (unsigned short)limit;
    descriptor[6] = (descriptor[6] & 0x30) | 0x40 | granularity |
                    (unsigned char)encodedLimit;
    return ATIBIOSStatusSuccess;
}

- (void)restoreDataSegment
{
    memcpy(gdtEntry(0x88), (unsigned char *)_priv + 16, 8);
}

- (int)doBios:(void *)registers dataSeg:(char)dataSegment
{
    int result;

    result = ATIbios16((ATIBIOSRegisters *)registers);
    [self restoreCodeSegments];
    if (dataSegment != 0)
        [self restoreDataSegment];
    return result;
}

- (int)loadCRTC_comm:(unsigned int)mode gamma:(char)gamma
           pitchSize:(unsigned int)pitchSize resolution:(unsigned int)resolution
            crtTable:(ATI_CRTCRecord *)crtTable function:(unsigned char)function
                name:(const char *)name
{
    ATIBIOSRegisters registers;
    char dataSegment = 0;
    int result;
    unsigned char colorMode;

    if (initialized == 0)
        return ATIBIOSStatusNotInitialized;
    if (resolution == 0x80)
        return ATIBIOSStatusInvalid;

    [self initBIOSBuf:&registers function:(char)function];
    colorMode = (unsigned char)(pitchSize << 6);
    if (gamma != 0)
        colorMode |= 0x10;
    registers.codeSelector = (unsigned short)(colorMode | mode |
                                              ((resolution & 0xff) << 8));
    if (resolution == 0x81) {
        result = [self createDataSegment:(unsigned int)crtTable size:30];
        if (result != ATIBIOSStatusSuccess)
            return result;
        registers.es = 0x88;
        registers.ebx = 0;
        dataSegment = 1;
    }

    result = [self doBios:&registers dataSeg:dataSegment];
    if (result != ATIBIOSStatusSuccess) {
        IOLog("ATI_BIOS %s: ATIbios32() returned %d\n", name, result);
        return ATIBIOSStatusError;
    }
    if (((registers.eax >> 8) & 0xff) == 0)
        return ATIBIOSStatusSuccess;
    IOLog("ATI_BIOS %s: ah = 0x%x on return from ATIbios32()\n",
          name, (registers.eax >> 8) & 0xff);
    return ATIBIOSStatusError;
}

@end
