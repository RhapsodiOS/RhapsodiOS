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

#if defined(ATI_BIOS_TEST)
extern const unsigned char *ATI_mockROMAddress(unsigned int address);
#define ATI_BIOS_ROM_ADDRESS(address) ATI_mockROMAddress(address)
#else
#define ATI_BIOS_ROM_ADDRESS(address) ((const unsigned char *)(address))
#endif

static __inline__ unsigned char *gdtEntry(unsigned int selector)
{
    return (unsigned char *)gdt + selector;
}

static __inline__ void setDescriptorBase(unsigned char *descriptor,
                                         unsigned int baseLowSource,
                                         unsigned int translatedBase)
{
    *(unsigned short *)(descriptor + 2) = (unsigned short)baseLowSource;
    descriptor[4] = (unsigned char)(translatedBase >> 16);
    descriptor[7] = (unsigned char)(translatedBase >> 24);
}

@implementation ATI_BIOS

- init
{
    char signature[12];
    unsigned int base;
    unsigned int offset;

    strcpy(signature, "761295520");
    for (base = 0xc0000; base <= 0xeffff; base += 0x1000) {
        for (offset = 0; offset < 129 - (strlen(signature) + 1); ++offset) {
            if (strncmp(signature, ATI_BIOS_ROM_ADDRESS(base + offset), 9) == 0)
                return [self initAtSegmentAddress:base];
        }
    }
    return nil;
}

+ (char)ATIPresent:(unsigned int *)segmentAddress
{
    char signature[12];
    unsigned int offset;

    strcpy(signature, "761295520");
    *segmentAddress = 0xc0000;
    do {
        for (offset = 0; offset < 129 - (strlen(signature) + 1); ++offset) {
            if (strncmp(signature,
                        ATI_BIOS_ROM_ADDRESS(*segmentAddress + offset), 9) == 0)
                return 1;
        }
        *segmentAddress += 0x1000;
    } while (*segmentAddress <= 0xeffff);
    return 0;
}

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

- (int)loadCRTC:(unsigned int)mode gamma:(char)gamma
      pitchSize:(unsigned int)pitchSize resolution:(unsigned int)resolution
       crtTable:(ATI_CRTCRecord *)crtTable
{
    return [self loadCRTC_comm:mode gamma:gamma pitchSize:pitchSize
                    resolution:resolution crtTable:crtTable function:0
                          name:"loadCRTC"];
}

- (int)setVGAMode:(char)mode gamma:(char)gamma
{
    ATIBIOSRegisters registers;
    ATIBIOSRegisters *registerBuffer = &registers;
    int result;
    unsigned char modeFlag;
    unsigned char gammaFlag;

    if (initialized == 0)
        return ATIBIOSStatusNotInitialized;
    [self initBIOSBuf:registerBuffer function:1];
    modeFlag = (mode == 0);
    gammaFlag = (gamma != 0) ? 0x80 : 0;
    *((unsigned char *)&registerBuffer->ecx) = modeFlag | gammaFlag;
    result = [self doBios:registerBuffer dataSeg:0];
    if (result != ATIBIOSStatusSuccess) {
        IOLog("ATI_BIOS setDisplayMode: ATIbios32() returned %d\n", result);
        return ATIBIOSStatusError;
    }
    if (*((unsigned char *)&registerBuffer->eax + 1) != 0) {
        IOLog("ATI_BIOS setDisplayMode: ah = 0x%x on return from ATIbios32()\n",
              *((unsigned char *)&registerBuffer->eax + 1));
        return ATIBIOSStatusError;
    }
    return ATIBIOSStatusSuccess;
}

- (int)loadCRTCSetMode:(unsigned int)mode gamma:(char)gamma
             pitchSize:(unsigned int)pitchSize resolution:(unsigned int)resolution
              crtTable:(ATI_CRTCRecord *)crtTable
{
    return [self loadCRTC_comm:mode gamma:gamma pitchSize:pitchSize
                    resolution:resolution crtTable:crtTable function:2
                          name:"loadCRTCSetMode"];
}

- (int)setApertureEnable:(char)enabled VGAAperture:(char)vgaAperture
            apertureAdrs:(unsigned int)address
{
    ATIBIOSRegisters registers;
    unsigned char flags;
    int result;

    if (initialized == 0)
        return ATIBIOSStatusNotInitialized;
    [self initBIOSBuf:&registers function:5];
    flags = enabled != 0;
    if (vgaAperture != 0)
        flags |= 4;
    if (address != 0) {
        if ((address & 0xfffff) != 0) {
            IOLog("ATI BIOS setApertureEnable: apertureAdrs misalignment (0x%x)\n",
                  address);
            return ATIBIOSStatusInvalid;
        }
        flags |= 0x80;
        registers.ebx = address >> 20;
    }
    *((unsigned char *)&registers.ecx) = flags;
    result = [self doBios:&registers dataSeg:0];
    if (result != ATIBIOSStatusSuccess) {
        IOLog("ATI_BIOS setApertureEnable: ATIbios32() returned %d\n", result);
        return ATIBIOSStatusError;
    }
    if (((registers.eax >> 8) & 0xff) == 0)
        return ATIBIOSStatusSuccess;
    IOLog("ATI_BIOS setApertureEnable: ah = 0x%x on return from ATIbios32()\n",
          (registers.eax >> 8) & 0xff);
    return ATIBIOSStatusError;
}

- (int)shortQuery:(unsigned int *)query hardCoded:(char *)hardCoded
    smallAperture:(char *)smallAperture address:(unsigned int *)address
       colorDepth:(unsigned int *)colorDepth memorySize:(unsigned int *)memorySize
         asicType:(char *)asicType asicRev:(char *)asicRevision
{
    ATIBIOSRegisters registers;
    int result;

    if (initialized == 0)
        return ATIBIOSStatusNotInitialized;
    [self initBIOSBuf:&registers function:6];
    result = [self doBios:&registers dataSeg:0];
    if (result != ATIBIOSStatusSuccess) {
        IOLog("ATI_BIOS shortQuery: ATIbios32() returned %d\n", result);
        return ATIBIOSStatusError;
    }
    if (*((unsigned char *)&registers.eax + 1) != 0) {
    IOLog("ATI_BIOS shortQuery: ah = 0x%x on return from ATIbios32()\n",
          *((unsigned char *)&registers.eax + 1));
        return ATIBIOSStatusError;
    }
    *query = registers.eax & 0x3f;
    *hardCoded = (registers.eax & 0x40) != 0;
    *smallAperture = (registers.eax & 0x80) != 0;
    *address = *((unsigned short *)&registers.ebx);
    *colorDepth = (registers.ecx >> 8) & 0xff;
    *memorySize = registers.ecx & 0xff;
    *asicType = (registers.edx >> 8) & 0xff;
    *asicRevision = registers.edx & 0xff;
    return ATIBIOSStatusSuccess;
}

- (int)querySize:(char)query size:(unsigned int *)size
{
    *size = 4096;
    return ATIBIOSStatusSuccess;
}

- (int)deviceQuery:(char)query bufferSize:(unsigned int)bufferSize buffer:(void *)buffer
{
    ATIBIOSRegisters registers;
    int result;

    if (initialized == 0)
        return ATIBIOSStatusNotInitialized;
    bzero(buffer, bufferSize);
    [self initBIOSBuf:&registers function:9];
    *((unsigned char *)&registers.ecx) = (query == 0);
    result = [self createDataSegment:(unsigned int)buffer size:bufferSize];
    if (result != ATIBIOSStatusSuccess)
        return result;
    *((unsigned short *)&registers.ebx) = 0;
    *((unsigned short *)&registers.edx) = 0x88;
    result = [self doBios:&registers dataSeg:1];
    if (result != ATIBIOSStatusSuccess) {
        IOLog("ATI_BIOS deviceQuery: ATIbios32() returned %d\n", result);
        return ATIBIOSStatusError;
    }
    if (*((unsigned char *)&registers.eax + 1) == 0)
        return ATIBIOSStatusSuccess;
    IOLog("ATI_BIOS deviceQuery: ah = 0x%x on return from ATIbios32()\n",
          *((unsigned char *)&registers.eax + 1));
    return ATIBIOSStatusError;
}

- (int)setDPMSMode:(unsigned int)mode
{
    ATIBIOSRegisters registers;
    ATIBIOSRegisters *registerBuffer = &registers;
    int result;

    if (initialized == 0)
        return ATIBIOSStatusNotInitialized;
    if (mode > 4) {
        IOLog("ATI_BIOS set DPMS mode: %x not valid mode\n", mode);
        return ATIBIOSStatusInvalid;
    }
    [self initBIOSBuf:registerBuffer function:12];
    *((unsigned char *)&registerBuffer->ecx) = mode & 3;
    result = [self doBios:registerBuffer dataSeg:0];
    if (result != ATIBIOSStatusSuccess) {
        IOLog("ATI_BIOS Set DPMS Mode: ATIbios32() returned %d\n", result);
        return ATIBIOSStatusError;
    }
    return ATIBIOSStatusSuccess;
}

- (int)getDPMSMode:(unsigned int *)mode
{
    ATIBIOSRegisters registers;
    ATIBIOSRegisters *registerBuffer = &registers;
    int result;

    if (initialized == 0)
        return ATIBIOSStatusNotInitialized;
    [self initBIOSBuf:registerBuffer function:13];
    *((unsigned char *)&registerBuffer->ecx) = 0;
    result = [self doBios:registerBuffer dataSeg:0];
    if (result != ATIBIOSStatusSuccess) {
        IOLog("ATI_BIOS Get DPMS Mode: ATIbios32() returned %d\n", result);
        return ATIBIOSStatusError;
    }
    *mode = *((unsigned char *)&registerBuffer->ecx) & 3;
    return ATIBIOSStatusSuccess;
}

- (int)setAPMState:(unsigned int)state
{
    ATIBIOSRegisters registers;
    ATIBIOSRegisters *registerBuffer = &registers;
    int result;

    if (initialized == 0)
        return ATIBIOSStatusNotInitialized;
    if (state > 3) {
        IOLog("ATI_BIOS set APM state: %x not valid mode\n", state);
        return ATIBIOSStatusInvalid;
    }
    [self initBIOSBuf:registerBuffer function:14];
    *((unsigned char *)&registerBuffer->ecx) = state & 3;
    result = [self doBios:registerBuffer dataSeg:0];
    if (result != ATIBIOSStatusSuccess) {
        IOLog("ATI_BIOS Set APM State: ATIbios32() returned %d\n", result);
        return ATIBIOSStatusError;
    }
    return ATIBIOSStatusSuccess;
}

- (int)getAPMState:(unsigned int *)state
{
    ATIBIOSRegisters registers;
    ATIBIOSRegisters *registerBuffer = &registers;
    int result;

    if (initialized == 0)
        return ATIBIOSStatusNotInitialized;
    [self initBIOSBuf:registerBuffer function:15];
    *((unsigned char *)&registerBuffer->ecx) = 0;
    result = [self doBios:registerBuffer dataSeg:0];
    if (result != ATIBIOSStatusSuccess) {
        IOLog("ATI_BIOS Get APM State: ATIbios32() returned %d\n", result);
        return ATIBIOSStatusError;
    }
    *state = *((unsigned char *)&registerBuffer->ecx) & 3;
    return ATIBIOSStatusSuccess;
}

- (int)getIOBaseAddress:(unsigned int *)address relocatable:(char *)relocatable
{
    ATIBIOSRegisters registers;
    ATIBIOSRegisters *registerBuffer = &registers;
    int result;

    if (initialized == 0)
        return ATIBIOSStatusNotInitialized;
    [self initBIOSBuf:registerBuffer function:18];
    *((unsigned char *)&registerBuffer->ecx) = 0;
    result = [self doBios:registerBuffer dataSeg:0];
    if (result != ATIBIOSStatusSuccess) {
        IOLog("ATI_BIOS Short Query 2: ATIbios32() returned %d\n", result);
        return ATIBIOSStatusError;
    }
    *relocatable = *((unsigned char *)&registerBuffer->ecx) & 1;
    *address = registerBuffer->edx;
    return ATIBIOSStatusSuccess;
}

- (int)getRefreshRate:(char *)refreshRate
{
    ATIBIOSRegisters registers;
    ATIBIOSRegisters *registerBuffer = &registers;
    int result;

    if (initialized == 0)
        return ATIBIOSStatusNotInitialized;
    [self initBIOSBuf:registerBuffer function:21];
    *((unsigned char *)&registerBuffer->ebx) = 0;
    result = [self createDataSegment:(unsigned int)refreshRate size:20];
    if (result != ATIBIOSStatusSuccess)
        return result;
    *((unsigned short *)&registerBuffer->edx) = 0x88;
    *((unsigned short *)&registerBuffer->ebx) = 0;
    result = [self doBios:registerBuffer dataSeg:1];
    if (result != ATIBIOSStatusSuccess) {
        IOLog("ATI_BIOS getRefreshRate: ATIbios32() returned %d\n", result);
        return ATIBIOSStatusError;
    }
    if (*((unsigned char *)&registerBuffer->eax + 1) != 0) {
        IOLog("ATI_BIOS getRefreshRate: ah = 0x%x on return from ATIbios32()\n",
              *((unsigned char *)&registerBuffer->eax + 1));
        return ATIBIOSStatusError;
    }
    return ATIBIOSStatusSuccess;
}

- (int)changeRefreshRate:(char *)refreshRate
{
    return ATIBIOSStatusInvalid;
}

@end

@implementation ATI_BIOS (Private)

- (int)initBIOSBuf:(ATIBIOSRegisters *)registers function:(char)function
{
    ATIBIOSRegisters *registerBuffer = registers;
    volatile unsigned char functionByte = function;

    [self setupCodeSegments];
    bzero(registerBuffer, ATIBIOSRegisterBufferSize);
    *((unsigned char *)&registerBuffer->eax) = functionByte;
    registerBuffer->codeSelector = 0x80;
    registerBuffer->dataSelector = 0x10;
    registerBuffer->entryOffset = 100;
    registerBuffer->ebp = (unsigned short)ATI_Bios_StackOffset >> 1;
    return (int)registerBuffer->ebp;
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
    *((unsigned char *)&registers.ecx) = (unsigned char)(colorMode | mode);
    *((unsigned char *)&registers.ecx + 1) = (unsigned char)resolution;
    if (resolution == 0x81) {
        result = [self createDataSegment:(unsigned int)crtTable size:30];
        if (result != ATIBIOSStatusSuccess)
            return result;
        registers.edx = 0x88;
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
