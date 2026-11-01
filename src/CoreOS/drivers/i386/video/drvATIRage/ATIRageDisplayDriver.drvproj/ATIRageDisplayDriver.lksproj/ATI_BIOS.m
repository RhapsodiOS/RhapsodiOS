#define KERNEL_PRIVATE 1
#define DRIVER_PRIVATE 1

#import "ATI_BIOS.h"
#import <driverkit/KernBus.h>
#import <driverkit/KernBusMemory.h>
#import <driverkit/generalFuncs.h>
#import <machdep/i386/gdt.h>
#import <string.h>

extern unsigned char _bios16[];

#define ATI_BIOS_CODE16_SELECTOR 0x80
#define ATI_BIOS_DATA16_SELECTOR 0x88
#define ATI_BIOS_THUNK_SELECTOR  0x90
#define ATI_BIOS_STACK_SELECTOR  0x98
#define ATI_KERNEL_DATA_SELECTOR 0x10
#define ATI_BIOS_STACK_BYTES     2048
#define ATI_KERNEL_LINEAR_BIAS   0x40000000U

/* Reference IONamedValue tables. Their strings and entry order are part of
 * the driver’s public diagnostic behavior. */
IONamedValue ABReturnValues[5] = {
    { 0, "AB_Success" },
    { 1, "AB_NotInitialized" },
    { 2, "AB_BIOS_Error" },
    { 3, "AB_Invalid" },
    { 0, 0 }
};

IONamedValue ATI_AsicTypeValues[9] = {
    { 215, "GX" }, { 87, "CX" }, { 67, "CT" }, { 69, "ET" },
    { 71, "GT" }, { 76, "LT" }, { 83, "ST" }, { 86, "VT" }, { 0, 0 }
};

IONamedValue ATI_AsicSubTypeValues[5] = {
    { 0, "-C" }, { 1, "-D" }, { 2, "-E" }, { 3, "-F" }, { 0, 0 }
};

IONamedValue ATI_memSizeValues[17] = {
    { 0, "512 KBytes" }, { 1, "1 MByte" }, { 2, "2 MBytes" },
    { 3, "4 MBytes" }, { 4, "6 MBytes" }, { 5, "8 MBytes" },
    { 6, "12 MBytes" }, { 7, "16 MBytes" }, { 8, "1.5 MBytes" },
    { 9, "2.5 MBytes" }, { 10, "3 MBytes" }, { 11, "3.5 MBytes" },
    { 12, "5 MBytes" }, { 13, "7 MBytes" }, { 14, "10 MBytes" },
    { 15, "14 MBytes" }, { 0, 0 }
};

IONamedValue ATI_dacTypeValues[22] = {
    { 4, "BT481" }, { 20, "ATT49x" }, { 36, "SC15026" },
    { 52, "MU9C1880" }, { 68, "IMSG174" }, { 5, "ATI68860" },
    { 21, "ATI68880" }, { 2, "ATI68875" }, { 71, "CH8398" },
    { 1, "RGB514" }, { 0, "Internal" }, { 22, "ATT498" },
    { 6, "STG1700" }, { 7, "STG1702" }, { 23, "SC15021" },
    { 39, "ATT21C498" }, { 55, "STG1703" }, { 114, "TVP3026" },
    { 3, "BT476" }, { 117, "TVP3026A" }, { 87, "ATT20C408" }, { 0, 0 }
};

IONamedValue ATI_busTypeValues[6] = {
    { 0, "ISA" }, { 1, "EISA" }, { 6, "VLB" }, { 7, "PCI" }, { 0, 0 }, { 0, 0 }
};

/* Globals consumed by ATI_BIOS16.s, ATIbios16.c and ATIbios.s. */
unsigned int ATI_Bios_Offset = 0;
unsigned short ATI_Bios_Selector = 0;
unsigned short ATI_Bios_StackOffset = 0;
unsigned short ATI_Bios_StackSelector = 0;
unsigned short kernDataSel = 0;

@implementation ATI_BIOS

+ (char)ATIPresent:(unsigned int *)biosBase
{
    unsigned int offset;
    char signature[12];

    strcpy(signature, "761295520");
    *biosBase = 0xC0000;
    do {
        for (offset = 0; offset < 129 - (strlen(signature) + 1); ++offset) {
            if (strncmp(signature, (const char *)(*biosBase + offset), 9) == 0)
                return 1;
        }
        *biosBase += 4096;
    } while (*biosBase <= 0xEFFFF);
    return 0;
}

- init
{
    unsigned int base;
    unsigned int offset;
    char signature[12];

    strcpy(signature, "761295520");
    for (base = 0xC0000; base <= 0xEFFFF; base += 4096) {
        for (offset = 0; offset < 129 - (strlen(signature) + 1); ++offset) {
            if (strncmp(signature, (const char *)(base + offset), 9) == 0)
                return [self initAtSegmentAddress:base];
        }
    }
    return nil;
}

- initAtSegmentAddress:(unsigned int)segmentAddress
{
    self->segmentBase = segmentAddress;
    self->_priv = IOMalloc(sizeof(ATI_BIOSPrivate));
    self->initialized = 1;
    return [super init];
}

- free
{
    if (self->initialized != 0)
        IOFree(self->_priv, sizeof(ATI_BIOSPrivate));
    return [super free];
}

- (int)loadCRTC:(unsigned int)mode gamma:(char)gamma pitchSize:(unsigned int)pitch
    resolution:(unsigned int)resolution crtTable:(ATI_CRTCRecord *)crtTable
{
    return [self loadCRTC_comm:mode gamma:gamma pitchSize:pitch resolution:resolution
        crtTable:crtTable function:0 name:"loadCRTC"];
}

- (int)setVGAMode:(char)mode gamma:(char)gamma
{
    ATI_BIOSRegisters registers;
    int biosResult;
    unsigned char modeFlag;
    unsigned char gammaFlag;

    if (self->initialized == 0)
        return 1;
    [self initBIOSBuf:&registers function:1];
    modeFlag = (mode == 0);
    gammaFlag = 0;
    if (gamma != 0)
        gammaFlag = 0x80;
    registers.ecx.bytes.low = modeFlag | gammaFlag;
    biosResult = [self doBios:&registers dataSeg:0];
    if (biosResult != 0) {
        IOLog("ATI_BIOS setDisplayMode: ATIbios32() returned %d\n", biosResult);
    } else if (registers.eax.bytes.high == 0) {
        return 0;
    } else {
        IOLog("ATI_BIOS setDisplayMode: ah = 0x%x on return from ATIbios32()\n",
              registers.eax.bytes.high);
    }
    return 2;
}

- (int)loadCRTCSetMode:(unsigned int)mode gamma:(char)gamma pitchSize:(unsigned int)pitch
    resolution:(unsigned int)resolution crtTable:(ATI_CRTCRecord *)crtTable
{
    return [self loadCRTC_comm:mode gamma:gamma pitchSize:pitch resolution:resolution
        crtTable:crtTable function:2 name:"loadCRTCSetMode"];
}

- (int)setApertureEnable:(char)enable VGAAperture:(char)vgaAperture
    apertureAdrs:(unsigned int)address
{
    ATI_BIOSRegisters registers;
    int biosResult;

    if (self->initialized == 0)
        return 1;
    [self initBIOSBuf:&registers function:5];
    registers.ecx.bytes.low = (enable != 0);
    if (vgaAperture != 0)
        registers.ecx.bytes.low |= 4;
    if (address != 0) {
        if ((address & 0xFFFFF) != 0) {
            IOLog("ATI BIOS setApertureEnable: apertureAdrs misalignment (0x%x)\n", address);
            return 3;
        }
        registers.ecx.bytes.low |= 0x80;
        registers.ebx.word = address >> 20;
    }
    biosResult = [self doBios:&registers dataSeg:0];
    if (biosResult != 0) {
        IOLog("ATI_BIOS setApertureEnable: ATIbios32() returned %d\n", biosResult);
    } else if (registers.eax.bytes.high == 0) {
        return 0;
    } else {
        IOLog("ATI_BIOS setApertureEnable: ah = 0x%x on return from ATIbios32()\n",
              registers.eax.bytes.high);
    }
    return 2;
}

- (int)shortQuery:(unsigned int *)hardCoded hardCoded:(ATIByte *)smallAperture
    smallAperture:(ATIByte *)address address:(unsigned int *)colorDepth
    colorDepth:(unsigned int *)memorySize memorySize:(unsigned int *)asicType
    asicType:(char *)asicRev asicRev:(char *)name
{
    ATI_BIOSRegisters registerStorage;
    register ATI_BIOSRegisters *registers __asm__("ebx");
    int biosResult;

    registers = &registerStorage;
    if (self->initialized == 0)
        return 1;
    [self initBIOSBuf:registers function:6];
    biosResult = [self doBios:registers dataSeg:0];
    if (biosResult != 0) {
        IOLog("ATI_BIOS shortQuery: ATIbios32() returned %d\n", biosResult);
    } else {
        if (registers->eax.bytes.high == 0) {
            *hardCoded = registers->eax.bytes.low & 0x3F;
            *smallAperture = (registers->eax.bytes.low & 0x40) != 0;
            *address = registers->eax.bytes.low >> 7;
            *colorDepth = registers->ebx.word;
            *memorySize = registers->ecx.bytes.high;
            *asicType = registers->ecx.bytes.low;
            *asicRev = registers->edx.bytes.high;
            *name = registers->edx.bytes.low;
            return 0;
        }
        IOLog("ATI_BIOS shortQuery: ah = 0x%x on return from ATIbios32()\n",
              registers->eax.bytes.high);
    }
    return 2;
}

- (int)querySize:(char)query size:(unsigned int *)size
{
    *size = 4096;
    return 0;
}

- (int)deviceQuery:(char)query bufferSize:(unsigned int)bufferSize buffer:(void *)buffer
{
    ATI_BIOSRegisters registers;
    int result;

    if (self->initialized == 0)
        return 1;
    bzero(buffer, bufferSize);
    [self initBIOSBuf:&registers function:9];
    registers.ecx.bytes.low = (query == 0);
    result = [self createDataSegment:(unsigned int)buffer size:bufferSize];
    if (result == 0) {
        registers.edx.word = 136;
        registers.ebx.word = 0;
        result = [self doBios:&registers dataSeg:1];
        if (result != 0) {
            IOLog("ATI_BIOS deviceQuery: ATIbios32() returned %d\n", result);
        } else if (registers.eax.bytes.high == 0) {
            return 0;
        } else {
            IOLog("ATI_BIOS deviceQuery: ah = 0x%x on return from ATIbios32()\n",
                  registers.eax.bytes.high);
        }
        return 2;
    }
    return result;
}

- (int)setDPMSMode:(unsigned int)mode
{
    ATI_BIOSRegisters registers;
    int biosResult;

    if (self->initialized == 0)
        return 1;

    if (mode > 4) {
        IOLog("ATI_BIOS set DPMS mode: %x not valid mode\n", mode);
        return 3;
    }

    [self initBIOSBuf:&registers function:12];
    registers.ecx.bytes.low = mode & 3;
    biosResult = [self doBios:&registers dataSeg:0];
    if (biosResult != 0) {
        IOLog("ATI_BIOS Set DPMS Mode: ATIbios32() returned %d\n", biosResult);
        return 2;
    }
    return 0;
}

- (int)getDPMSMode:(unsigned int *)mode
{
    ATI_BIOSRegisters registers;
    int biosResult;

    if (self->initialized == 0)
        return 1;
    [self initBIOSBuf:&registers function:13];
    registers.ecx.bytes.low = 0;
    biosResult = [self doBios:&registers dataSeg:0];
    if (biosResult != 0) {
        IOLog("ATI_BIOS Get DPMS Mode: ATIbios32() returned %d\n", biosResult);
        return 2;
    }
    *mode = registers.ecx.bytes.low & 3;
    return 0;
}

- (int)setAPMState:(unsigned int)state
{
    ATI_BIOSRegisters registers;
    int biosResult;

    if (self->initialized == 0)
        return 1;

    if (state > 3) {
        IOLog("ATI_BIOS set APM state: %x not valid mode\n", state);
        return 3;
    }

    [self initBIOSBuf:&registers function:14];
    registers.ecx.bytes.low = state & 3;
    biosResult = [self doBios:&registers dataSeg:0];
    if (biosResult != 0) {
        IOLog("ATI_BIOS Set APM State: ATIbios32() returned %d\n", biosResult);
        return 2;
    }
    return 0;
}

- (int)getAPMState:(unsigned int *)state
{
    ATI_BIOSRegisters registers;
    int biosResult;

    if (self->initialized == 0)
        return 1;
    [self initBIOSBuf:&registers function:15];
    registers.ecx.bytes.low = 0;
    biosResult = [self doBios:&registers dataSeg:0];
    if (biosResult != 0) {
        IOLog("ATI_BIOS Get APM State: ATIbios32() returned %d\n", biosResult);
        return 2;
    }
    *state = registers.ecx.bytes.low & 3;
    return 0;
}

- (int)getIOBaseAddress:(unsigned long *)address relocatable:(ATIByte *)relocatable
{
    ATI_BIOSRegisters registers;
    int biosResult;

    if (self->initialized == 0)
        return 1;
    [self initBIOSBuf:&registers function:18];
    registers.ecx.bytes.low = 0;
    biosResult = [self doBios:&registers dataSeg:0];
    if (biosResult != 0) {
        IOLog("ATI_BIOS Short Query 2: ATIbios32() returned %d\n", biosResult);
        return 2;
    }
    *relocatable = registers.ecx.bytes.low & 1;
    *address = registers.edx.dword;
    return 0;
}

- (int)getRefreshRate:(char *)refreshRate
{
    ATI_BIOSRegisters registers;
    int result;

    if (self->initialized == 0)
        return 1;
    [self initBIOSBuf:&registers function:21];
    registers.ebx.bytes.low = 0;
    result = [self createDataSegment:(unsigned int)refreshRate size:20];
    if (result == 0) {
        registers.edx.word = 136;
        registers.ebx.word = 0;
        result = [self doBios:&registers dataSeg:1];
        if (result != 0) {
            IOLog("ATI_BIOS getRefreshRate: ATIbios32() returned %d\n", result);
        } else if (registers.eax.bytes.high == 0) {
            return 0;
        } else {
            IOLog("ATI_BIOS getRefreshRate: ah = 0x%x on return from ATIbios32()\n",
                  registers.eax.bytes.high);
        }
        return 2;
    }
    return result;
}

- (int)changeRefreshRate:(char *)refreshRate
{
    return 3;
}

@end

@implementation ATI_BIOS (Private)

- (void)initBIOSBuf:(ATI_BIOSRegisters *)registers function:(unsigned int)function
{
    [self setupCodeSegments];
    bzero(registers, 0x30);
    registers->eax.bytes.low = function;
    registers->code_selector = ATI_BIOS_CODE16_SELECTOR;
    registers->data_selector = ATI_KERNEL_DATA_SELECTOR;
    registers->entry_offset = 100;
    registers->ebp.dword = (unsigned short)ATI_Bios_StackOffset >> 1;
}

- (void)setupCodeSegments
{
    ATI_BIOSPrivate *priv;
    ATI_SegmentDescriptor *code16Descriptor;
    ATI_SegmentDescriptor *code32Descriptor;
    ATI_SegmentDescriptor *stackDescriptor;
    unsigned int code16BaseAdjusted;
    unsigned int code32BaseAdjusted;
    unsigned int stackBaseAdjusted;
    void *stack;

    priv = self->_priv;
    code16Descriptor = (ATI_SegmentDescriptor *)((unsigned char *)gdt + ATI_BIOS_CODE16_SELECTOR);
    code32Descriptor = (ATI_SegmentDescriptor *)((unsigned char *)gdt + ATI_BIOS_THUNK_SELECTOR);
    stackDescriptor = (ATI_SegmentDescriptor *)((unsigned char *)gdt + ATI_BIOS_STACK_SELECTOR);
    priv->saved_code_descriptor0 = *code16Descriptor;
    priv->saved_code_descriptor1 = *code32Descriptor;
    priv->saved_stack_descriptor = *stackDescriptor;

    code16BaseAdjusted = self->segmentBase - 0x40000000;
    code16Descriptor->base_low = self->segmentBase;
    code16Descriptor->base_mid = (unsigned char)(code16BaseAdjusted >> 16);
    code16Descriptor->base_high = (unsigned char)(code16BaseAdjusted >> 24);
    code16Descriptor->access &= 0xE0;
    code16Descriptor->access |= 0x1A;
    code16Descriptor->access &= 0x9F;
    *((volatile unsigned char *)&code16Descriptor->access) =
        code16Descriptor->access;
    code16Descriptor->access |= 0x80;
    code16Descriptor->limit_flags &= (unsigned char)~0x40;
    code16Descriptor->limit_flags &= (unsigned char)~0x80;
    code16Descriptor->limit_low = 0xFFFF;
    code16Descriptor->limit_flags &= 0xF0;
    *((volatile unsigned char *)&code16Descriptor->limit_flags) =
        code16Descriptor->limit_flags;

    code32BaseAdjusted = (unsigned int)_bios16 + 0xC0000000;
    code32Descriptor->base_low = code32BaseAdjusted;
    code32Descriptor->base_mid = (unsigned char)(code32BaseAdjusted >> 16);
    code32Descriptor->base_high = (unsigned char)(code32BaseAdjusted >> 24);
    code32Descriptor->access &= 0xE0;
    code32Descriptor->access |= 0x1A;
    code32Descriptor->access &= 0x9F;
    *((volatile unsigned char *)&code32Descriptor->access) =
        code32Descriptor->access;
    code32Descriptor->access |= 0x80;
    code32Descriptor->limit_flags |= 0x40;
    code32Descriptor->limit_flags &= (unsigned char)~0x80;
    code32Descriptor->limit_low = 0xFFFF;
    code32Descriptor->limit_flags &= 0xF0;
    *((volatile unsigned char *)&code32Descriptor->limit_flags) =
        code32Descriptor->limit_flags;

    stack = IOMalloc(ATI_BIOS_STACK_BYTES);
    priv->stack_address = (unsigned int)stack;
    bzero(stack, ATI_BIOS_STACK_BYTES);
    stackBaseAdjusted = priv->stack_address - ATI_KERNEL_LINEAR_BIAS;
    stackDescriptor->base_low = (unsigned short)priv->stack_address;
    stackDescriptor->base_mid = (unsigned char)(stackBaseAdjusted >> 16);
    stackDescriptor->base_high = (unsigned char)(stackBaseAdjusted >> 24);
    stackDescriptor->access &= 0xE0;
    stackDescriptor->access |= 0x12;
    stackDescriptor->access &= 0x9F;
    *((volatile unsigned char *)&stackDescriptor->access) =
        stackDescriptor->access;
    stackDescriptor->access |= 0x80;
    stackDescriptor->limit_flags |= 0x40;
    stackDescriptor->limit_flags &= (unsigned char)~0x80;
    stackDescriptor->limit_low = ATI_BIOS_STACK_BYTES - 1;
    stackDescriptor->limit_flags &= 0xF0;
    *((volatile unsigned char *)&stackDescriptor->limit_flags) =
        stackDescriptor->limit_flags;
    stackDescriptor->limit_flags &= (unsigned char)~0x40;
    ATI_Bios_StackOffset = ATI_BIOS_STACK_BYTES;
    ATI_Bios_StackSelector = ATI_BIOS_STACK_SELECTOR;
}

- (void)restoreCodeSegments
{
    ATI_BIOSPrivate *priv;
    ATI_SegmentDescriptor *code16Descriptor;
    ATI_SegmentDescriptor *code32Descriptor;
    ATI_SegmentDescriptor *stackDescriptor;

    priv = self->_priv;
    code16Descriptor = (ATI_SegmentDescriptor *)((unsigned char *)gdt + ATI_BIOS_CODE16_SELECTOR);
    code32Descriptor = (ATI_SegmentDescriptor *)((unsigned char *)gdt + ATI_BIOS_THUNK_SELECTOR);
    stackDescriptor = (ATI_SegmentDescriptor *)((unsigned char *)gdt + ATI_BIOS_STACK_SELECTOR);
    *code16Descriptor = priv->saved_code_descriptor0;
    *code32Descriptor = priv->saved_code_descriptor1;
    *stackDescriptor = priv->saved_stack_descriptor;
    IOFree((void *)priv->stack_address, ATI_BIOS_STACK_BYTES);
}

- (int)createDataSegment:(unsigned int)address size:(unsigned int)size
{
    ATI_BIOSPrivate *priv;
    ATI_SegmentDescriptor *savedData16;
    unsigned char *data16;
    unsigned int base;
    unsigned int limit;
    register unsigned int roundedLimit __asm__("edx");
    unsigned char limitHigh;

    savedData16 = (ATI_SegmentDescriptor *)((unsigned char *)gdt + ATI_BIOS_DATA16_SELECTOR);
    priv = self->_priv;
    if (size > 0x10000) {
        IOLog("ATI_BIOS: Data Segment size exceeded (0x%x)\n", size);
        return 3;
    }
    priv->saved_data_descriptor = *savedData16;
    data16 = (unsigned char *)gdt + ATI_BIOS_DATA16_SELECTOR;
    base = address + 0xC0000000;
    *(unsigned short *)(data16 + 2) = base;
    data16[4] = (unsigned char)(base >> 16);
    data16[7] = (unsigned char)(base >> 24);
    data16[5] &= 0xE0;
    data16[5] |= 0x12;
    data16[5] &= 0x9F;
    *((volatile unsigned char *)(data16 + 5)) =
        *((volatile unsigned char *)(data16 + 5));
    data16[5] |= 0x80;
    data16[6] |= 0x40;
    limit = size - 1;
    if (limit <= 0xFFFFF) {
        roundedLimit = limit;
        data16[6] &= (unsigned char)~0x80;
        *(unsigned short *)data16 = (unsigned short)roundedLimit;
        limitHigh = (unsigned char)((limit >> 16) & 0x0F);
    } else {
        limit = (size + 4095) & 0xFFFFF000;
        roundedLimit = limit - 4096;
        data16[6] |= 0x80;
        *(unsigned short *)data16 = (unsigned short)(roundedLimit >> 12);
        limitHigh = (unsigned char)(roundedLimit >> 28);
    }
    data16[6] &= 0xF0;
    data16[6] |= limitHigh;
    return 0;
}

- (void)restoreDataSegment
{
    ATI_BIOSPrivate *priv;
    ATI_SegmentDescriptor *data16;

    data16 = (ATI_SegmentDescriptor *)((unsigned char *)gdt + ATI_BIOS_DATA16_SELECTOR);
    priv = self->_priv;
    *data16 = priv->saved_data_descriptor;
}

- (int)doBios:(ATI_BIOSRegisters *)registers dataSeg:(char)dataSegment
{
    int result;

    result = ATIbios16(registers);
    [self restoreCodeSegments];
    if (dataSegment != 0)
        [self restoreDataSegment];
    return result;
}

- (int)loadCRTC_comm:(unsigned int)mode gamma:(char)gamma pitchSize:(unsigned int)pitch
    resolution:(unsigned int)resolution crtTable:(ATI_CRTCRecord *)crtTable
    function:(unsigned char)function name:(const char *)name
{
    ATI_BIOSRegisters registers;
    int result;
    char restoreData;
    register unsigned char gammaFlag __asm__("eax");
    register unsigned char modeFlags __asm__("edx");
    register ATI_BIOS *bios __asm__("edi") = self;
    register unsigned int resolutionValue __asm__("esi") = resolution;
    register ATI_BIOSRegisters *registerBuffer __asm__("ebx") = &registers;

    restoreData = 0;
    if (bios->initialized == 0)
        return 1;
    if (resolutionValue == 128)
        return 3;
    [bios initBIOSBuf:registerBuffer function:function];
    gammaFlag = 0;
    if (gamma != 0)
        gammaFlag = 16;
    modeFlags = gammaFlag;
    modeFlags |= (unsigned char)mode;
    gammaFlag = (unsigned char)pitch;
    gammaFlag <<= 6;
    modeFlags |= gammaFlag;
    registerBuffer->ecx.bytes.low = modeFlags;
    registerBuffer->ecx.bytes.high = resolutionValue;
    if (resolutionValue == 129) {
        result = [bios createDataSegment:(unsigned int)crtTable size:30];
        if (result != 0)
            return result;
        registerBuffer->edx.word = 136;
        registerBuffer->ebx.word = 0;
        restoreData = 1;
    }
    result = [bios doBios:registerBuffer dataSeg:restoreData];
    if (result != 0) {
        IOLog("ATI_BIOS %s: ATIbios32() returned %d\n", name, result);
    } else if (registerBuffer->eax.bytes.high == 0) {
        return 0;
    } else {
        IOLog("ATI_BIOS %s: ah = 0x%x on return from ATIbios32()\n", name,
              registerBuffer->eax.bytes.high);
    }
    return 2;
}

@end
