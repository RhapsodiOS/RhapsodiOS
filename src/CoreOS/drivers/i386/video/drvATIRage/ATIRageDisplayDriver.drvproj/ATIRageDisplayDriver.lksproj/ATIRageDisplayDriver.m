/*
 * Copyright (c) 1998 Apple Computer, Inc. All rights reserved.
 *
 * ATIRageDisplayDriver.m - ATI Rage display driver.
 */

#define KERNEL_PRIVATE 1
#define DRIVER_PRIVATE 1

#import "ATIRageDisplayDriver.h"
#import "ATIRageRegs.h"
#import <driverkit/KernBus.h>
#import <driverkit/KernBusMemory.h>
#import <driverkit/IODisplayPrivate.h>
#import <driverkit/IODirectDevicePrivate.h>
#import <driverkit/IOConfigTable.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/driverTypes.h>
#import <driverkit/i386/ioPorts.h>
#import <driverkit/displayDefs.h>
#import <string.h>
#import <stdlib.h>

static unsigned int start_base_address = 0x60000000;
static unsigned int register_base_address = 0;
extern const char waitForIdleTimeoutMessage[];
__asm__(
    ".section __TEXT,__cstring,cstring_literals\n"
    ".globl _waitForIdleTimeoutMessage\n"
    "_waitForIdleTimeoutMessage:\n"
    ".asciz \"ATIRage: waitForIdle timeout.\\n\"\n"
    ".text\n");

extern unsigned int waitForFIFO(unsigned int count);
extern int waitForIdle(void);
extern int doBlit(unsigned int sourceX, unsigned int sourceY,
                  unsigned int width, unsigned int height,
                  unsigned int destinationX, unsigned int destinationY);
extern int doFill(unsigned int left, unsigned int top,
                  unsigned int right, unsigned int bottom,
                  unsigned int color);
extern unsigned char isATI68880RevC(unsigned short base);
extern void SetGammaValue(unsigned short base, int red, int green,
                          int blue, int brightness);

static int resetEngineWriteCounter;
static __inline__ void writeResetEnginePort(IOEISAPortAddress port,
                                             unsigned int value)
{
    __asm__ volatile(
        "outl %0, %w1\n\t"
        "lock; incl %2"
        :
        : "a"(value), "d"(port), "m"(resetEngineWriteCounter)
        : "memory");
}
static int setGammaValueWriteCounter;

static __inline__ void writeGammaDACByte(IOEISAPortAddress port,
                                          unsigned char value)
{
    __asm__ volatile(
        "outb %b0, %w1\n\t"
        "lock; incl %2"
        :
        : "a"(value), "d"(port), "m"(setGammaValueWriteCounter)
        : "memory");
}

/* The generated data follows the two leading address words in __data. */
#import "ATIRageModes.h"

@interface ATI (PrivateReturnString)
- (const char *)stringFromReturn:(IOReturn)result;
@end

@implementation ATI

- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription
{
    register ATI *driver __asm__("ebx") = self;
    IOPCIDeviceDescription *pciDescription;
    IORange *memoryRanges;
    unsigned int biosBase;
    unsigned int port;
    unsigned int originalPortValue;
    unsigned int testValue;
    unsigned int registerValue;
    unsigned char *queryData;
    IOConfigTable *configTable;
    const char *text;
    const char *asicName;
    const char *memoryName;
    const char *gammaName;
    unsigned int colorName;
    char asicDescription[32];

    driver->engineStarted = 0;
    pciDescription = (IOPCIDeviceDescription *)deviceDescription;
    if ([pciDescription getPCIdevice:NULL function:NULL bus:NULL] != 0) {
        IOLog("ATIRage: ATIRage adapter not found\n", [driver name]);
        return [super free];
    }
    if ([ATI_BIOS ATIPresent:&biosBase] == 0) {
        IOLog("%s: ATI BIOS not found\n", [driver name]);
        return [super free];
    }
    if ([driver fixDeviceDescriptionForPCI:deviceDescription] == 0) {
        IOLog("%s: Configuration error. Aborting...\n", [driver name]);
        return [super free];
    }
    if ([super initFromDeviceDescription:deviceDescription] == nil)
        return [super free];
    driver->atiBios = [[ATI_BIOS alloc] initAtSegmentAddress:biosBase];
    if (driver->atiBios == nil)
        return [super free];

    driver->queryDataSize = 0;
    [driver->atiBios getIOBaseAddress:&driver->baseAddress relocatable:&driver->relocatableIO];
    if (driver->relocatableIO != 0)
        port = driver->baseAddress + 132;
    else
        port = driver->baseAddress + 17408;
    originalPortValue = inl((IOEISAPortAddress)port);
    writeResetEnginePort((IOEISAPortAddress)port, 0x55555555);
    testValue = inl((IOEISAPortAddress)port);
    if (testValue != 0x55555555) {
        IOLog("%s: Rage/Rage II/Rage Pro BIOS not found.\n", [driver name]);
        return [driver free];
    }
    writeResetEnginePort((IOEISAPortAddress)port, 0xAAAAAAAA);
    testValue = inl((IOEISAPortAddress)port);
    if (testValue != 0xAAAAAAAA) {
        IOLog("%s: Mach64/Rage failed second regsiter test.\n", [driver name]);
        return [driver free];
    }
    writeResetEnginePort((IOEISAPortAddress)port, originalPortValue);

    if ([driver getQueryData] != 0)
        return [super free];
    queryData = (unsigned char *)driver->queryData;
    driver->supportsGamma = (queryData[20] & 0x40) != 0;
    driver->supportsGrey256 = (queryData[20] & 0x20) != 0;
    driver->vramBytes = [driver displayMemorySize];
    asicName = IOFindNameForValue(queryData[9],
                                  ATI_AsicTypeValues);
    strcpy(asicDescription, asicName);
    if (queryData[9] == 0xD7) {
        text = IOFindNameForValue(queryData[8],
                                  ATI_AsicSubTypeValues);
        strcat(asicDescription, text);
    }
    IOLog("%s: ATI Rage/Rage II/Rage Pro Found!\n", [driver name]);
    memoryName = IOFindNameForValue(queryData[11],
                                    ATI_memSizeValues);
    gammaName = driver->supportsGamma ? "YES" : "NO";
    IOLog("%s: Type %s.  Gamma: %s.  Memory: %s.\n", [driver name],
          asicDescription, gammaName, memoryName);

    configTable = [deviceDescription configTable];
    driver->ramdacStyle = 0;
    text = [configTable valueForStringKey:"RAMDAC Style"];
    if (text != NULL) {
        if (strcmp(text, "Sparse") == 0)
            driver->ramdacStyle = 1;
        else if (strcmp(text, "Dense") == 0)
            driver->ramdacStyle = 2;
        if (driver->ramdacStyle != 0)
            IOLog("%s: ramdacStyle from table = %s\n", [driver name], text);
        [configTable freeString:text];
    }
    text = [configTable valueForStringKey:"Display Mode"];
    if (text == NULL) {
        IOLog("%s: No Display Mode found; aborting\n", [driver name]);
    } else if ([driver parseModeString:text] == 0) {
        if (AtiModeList[driver->modeNumber].bitsPerPixel == IO_24BitsPerPixel) {
            colorName = driver->colorConfig;
            text = IOFindNameForValue(colorName, colorConfigValues);
            IOLog("%s: 24 Bit Color Configuration = %s\n", [driver name], text);
        }
        if ([driver->atiBios setApertureEnable:1 VGAAperture:0 apertureAdrs:0] == 0) {
            memoryRanges = [deviceDescription memoryRangeList];
            driver->vram = (void *)[driver mapFrameBufferAtPhysicalAddress:
                memoryRanges[0].start length:ATI_FRAMEBUFFER_SIZE];
            if (driver->vram != NULL) {
                if (driver->relocatableIO != 0)
                    port = driver->baseAddress + 160;
                else
                    port = driver->baseAddress + 24576;
                registerValue = inl((IOEISAPortAddress)port);
                writeResetEnginePort((IOEISAPortAddress)port, registerValue & 0xFFFFFFEF);
                register_base_address = (unsigned int)driver->vram +
                                        ATI_REGISTER_WINDOW_OFFSET;
                [driver updateModeList];
                register IODisplayInfo *displayInfo __asm__("edi") =
                    [super displayInfo];
                register IODisplayInfo *modeInfo __asm__("esi") =
                    &AtiModeList[driver->modeNumber];
                register unsigned int modeInfoWords __asm__("ecx") = 0x22;
                __asm__ __volatile__(
                    "cld\n\t"
                    "rep movsl"
                    : "+D" (displayInfo), "+S" (modeInfo), "+c" (modeInfoWords)
                    :
                    : "memory", "cc");
                if ([driver verifyMemoryMap] != 0) {
                    driver->currentState = 0;
                    driver->blueTransferTable = NULL;
                    driver->greenTransferTable = NULL;
                    driver->redTransferTable = NULL;
                    driver->transferTableCount = 0;
                    driver->brightnessLevel = 64;
                    return driver;
                }
                IOLog("%s: VRAM test failure, aborting\n", [driver name]);
                return [driver free];
            } else {
                IOLog("%s: Unable to map frame buffer\n", [driver name]);
                return [driver free];
            }
            return [driver free];
        }
    }
    return [driver free];

}

- (char)fixDeviceDescriptionForPCI:(IOPCIDeviceDescription *)deviceDescription
{
    Class directDeviceClass;
    IORange memoryRanges[8];
    IORange portRanges[9];
    unsigned int barRegisters[18];
    int reg;
    int mask;
    int probed;
    unsigned int size;
    unsigned int start;
    unsigned int count;
    int memoryCount;
    int portCount;
    int memoryRangeCount;
    int portRangeCount;
    unsigned int candidate;
    int index;
    unsigned int memoryRetryIndex;
    unsigned int candidateRangeIndex;
    unsigned int memoryBARIndex;
    unsigned int currentPCIRegister;
    char override;
    const char *text;
    IOConfigTable *configTable;
    volatile char success;
    IOReturn result;

    portCount = 0;
    success = 1;
    directDeviceClass = [self class];
    memoryCount = portCount;
    for (reg = 16; reg <= 39; reg += 4) {
        [directDeviceClass getPCIConfigData:(unsigned long *)&barRegisters[0]
            atRegister:(unsigned char)reg withDeviceDescription:deviceDescription];
        mask = (barRegisters[0] & 1) ? -4 : -16;
        [directDeviceClass setPCIConfigData:barRegisters[0] | mask
            atRegister:(unsigned char)reg withDeviceDescription:deviceDescription];
        [directDeviceClass getPCIConfigData:(unsigned long *)&probed
            atRegister:(unsigned char)reg withDeviceDescription:deviceDescription];
        [directDeviceClass setPCIConfigData:barRegisters[0] atRegister:(unsigned char)reg
            withDeviceDescription:deviceDescription];
        size = probed & mask;
        if (size != 0) {
            if ((barRegisters[0] & 1) != 0) {
                portRanges[portCount].start = barRegisters[0] & mask;
                portRanges[portCount].size = 0U - size;
                barRegisters[1 + portCount] = reg;
                ++portCount;
            } else {
                memoryRanges[memoryCount].start = barRegisters[0] & mask;
                memoryRanges[memoryCount].size = 0U - size;
                barRegisters[10 + memoryCount] = reg;
                ++memoryCount;
            }
        }
    }

    override = 1;
    for (index = 0; index < memoryCount; ++index)
        if (memoryRanges[index].start <= 0x003FFFFF)
            override = 0;
    for (index = 0; index < portCount; ++index)
        if (portRanges[index].start <= 0xFF)
            override = 0;

    if (override == 0) {
        start = [deviceDescription memoryRangeList][0].start;
        for (index = 0; index < memoryCount; ++index) {
            size = memoryRanges[index].size;
            start = (size + start - 1) & (0U - size);
            memoryRanges[index].start = start;
            [directDeviceClass setPCIConfigData:start
                atRegister:(unsigned char)barRegisters[10 + index]
                withDeviceDescription:deviceDescription];
            start += size;
        }
        start = [deviceDescription portRangeList][0].start;
        for (index = 0; index < portCount; ++index) {
            size = portRanges[index].size;
            start = (size + start - 1) & (0U - size);
            portRanges[index].start = start;
            [directDeviceClass setPCIConfigData:start
                atRegister:(unsigned char)barRegisters[1 + index]
                withDeviceDescription:deviceDescription];
            start += size;
        }
    }

    memoryRangeCount = memoryCount + 2;
    memoryRanges[memoryCount].start = 0x000A0000;
    memoryRanges[memoryCount].size = 0x00020000;
    memoryRanges[memoryCount + 1].start = 0x000C0000;
    memoryRanges[memoryCount + 1].size = 0x00010000;
    portRangeCount = portCount + 3;
    portRanges[portCount].start = 944;
    portRanges[portCount].size = 48;
    portRanges[portCount + 1].start = 258;
    portRanges[portCount + 1].size = 1;
    portRanges[portCount + 2].start = 18152;
    portRanges[portCount + 2].size = 1;

    [deviceDescription setMemoryRangeList:NULL num:0];
    result = [deviceDescription setMemoryRangeList:memoryRanges num:memoryRangeCount];
    if (result != 0) {
        start = start_base_address;
        count = memoryRangeCount - 2;
        self->overrideStartBaseAddress = 0;
        configTable = [deviceDescription configTable];
        if (configTable != NULL) {
            text = [configTable valueForStringKey:"FB Address"];
            if (text != NULL && *text != '\0') {
                candidate = (unsigned int)strtol(text, NULL, 16) & 0x7F000000;
                if (candidate > 0x03FFFFFF) {
                    start = candidate;
                    self->overrideStartBaseAddress = 1;
                }
            }
        }
        if (memoryRangeCount != 2) {
            for (memoryRetryIndex = 0; memoryRetryIndex < count; ++memoryRetryIndex) {
                candidate = start;
                if (candidate <= 0xFEFFFFFF) {
                    candidateRangeIndex = memoryRetryIndex;
                    do {
                        memoryRanges[candidateRangeIndex].start = candidate;
                        [deviceDescription setMemoryRangeList:NULL num:0];
                        if ([deviceDescription setMemoryRangeList:
                             memoryRanges num:memoryRetryIndex] == 0)
                            break;
                        candidate += memoryRanges[candidateRangeIndex].size;
                    } while (candidate <= 0xFEFFFFFF);
                }
            }
        }
        [deviceDescription setMemoryRangeList:NULL num:0];
        result = [deviceDescription setMemoryRangeList:memoryRanges num:memoryRangeCount];
        if (result != 0) {
            IOLog("%s: Error in setMemoryRangeList (%s)\n", [self name],
                  [self stringFromReturn:result]);
            return 0;
        }
        if (memoryRangeCount != 2) {
            memoryBARIndex = 0;
            currentPCIRegister = 16;
            do {
                if (currentPCIRegister > 39)
                    break;
                [directDeviceClass setPCIConfigData:memoryRanges[memoryBARIndex++].start
                    atRegister:(unsigned char)currentPCIRegister
                    withDeviceDescription:deviceDescription];
                currentPCIRegister += 4;
            } while (count > memoryBARIndex);
        }
    }

    [deviceDescription setPortRangeList:NULL num:0];
    result = [deviceDescription setPortRangeList:portRanges num:portRangeCount];
    if (result != 0) {
        IOLog("%s: Error in setPortRangeList (%s)\n", [self name],
              [self stringFromReturn:result]);
        return 0;
    }
    return success;
}

- (int)getQueryData
{
    unsigned int size;
    unsigned short *temporary;
    unsigned int result;
    const char *name;

    size = 0;
    if (self->queryDataSize != 0) {
        IOFree(self->queryData, self->queryDataSize);
        self->queryDataSize = 0;
    }
    result = [self->atiBios querySize:0 size:&size];
    if (result != 0) {
        name = IOFindNameForValue(result, ABReturnValues);
        IOLog("%s: querySize returned %s\n", [self name], name);
    } else {
        temporary = (unsigned short *)IOMalloc(size);
        result = [self->atiBios deviceQuery:0 bufferSize:size buffer:temporary];
        if (result == 0) {
            self->queryDataSize = temporary[0];
            self->queryData = IOMalloc(self->queryDataSize);
            bcopy(temporary, self->queryData, self->queryDataSize);
            IOFree(temporary, size);
            return 0;
        }
        name = IOFindNameForValue(result, ABReturnValues);
        IOLog("%s: deviceQuery returned %s\n", [self name], name);
        if (size != 0)
            IOFree(temporary, size);
    }
    return 1;
}

- (int)parseModeString:(const char *)modeString
{
    int selected;
    unsigned int error;

    selected = [self selectMode:AtiModeList count:AtiModeListCount];
    self->modeNumber = selected;
    if (selected >= 0)
        goto selectedMode;
    IOLog("%s: selectMode problem; aborting\n", [self name]);
    goto invalidMode;
selectedMode:
    error = [self isModeValid:self->modeNumber];
    if (error == 0)
        return 0;
    IOLog("%s: Requested Mode not supported (0x%x); aborting\n",
          [self name], error);
invalidMode:
    return -1;
}

- (void)updateModeList
{
    IOConfigTable *configTable;
    const char *text;
    const char *pixelEncoding;
    unsigned int i;
    unsigned int colorConfig;

    configTable = [[self deviceDescription] configTable];
    self->colorConfig = 0;
    text = [configTable valueForStringKey:"24-bit Configuration"];
    if (text != NULL) {
        if (strcmp(text, "RGBx") == 0)
            self->colorConfig = 1;
        else if (strcmp(text, "BGRx") == 0)
            self->colorConfig = 2;
        else if (strcmp(text, "xRGB") == 0)
            self->colorConfig = 3;
        else if (strcmp(text, "xBGR") == 0)
            self->colorConfig = 4;
        if (self->colorConfig != 0)
            IOLog("%s: colorConfig from table = %s\n", [self name], text);
        [configTable freeString:text];
    }
    colorConfig = self->colorConfig;
    switch (colorConfig) {
    case 3:
    default:
        pixelEncoding = "--------RRRRRRRRGGGGGGGGBBBBBBBB";
        break;
    case 4:
        pixelEncoding = "--------BBBBBBBBGGGGGGGGRRRRRRRR";
        break;
    case 1:
        pixelEncoding = "RRRRRRRRGGGGGGGGBBBBBBBB--------";
        break;
    case 2:
        pixelEncoding = "BBBBBBBBGGGGGGGGRRRRRRRR--------";
        break;
    }

    for (i = 0; i < AtiModeListCount; ++i) {
        AtiModeList[i].frameBuffer = self->vram;
        if (self->supportsGamma == 0 && AtiModeList[i].bitsPerPixel != IO_8BitsPerPixel) {
            AtiModeList[i].flags &= ~0x10;
            AtiModeList[i].flags |= 2;
        }
        if (AtiModeList[i].bitsPerPixel == IO_24BitsPerPixel)
            strcpy(AtiModeList[i].pixelEncoding, pixelEncoding);
        AtiModeList[i].modeUnavailableFlag = 0;
        if ((unsigned int)AtiModeList[i].memorySize > self->vramBytes)
            AtiModeList[i].modeUnavailableFlag = IO_DISPLAY_MODE_NEEDS_MORE_MEMORY;
    }
}

- (unsigned int)isModeValid:(int)mode
{
    IODisplayInfo *info;
    unsigned char *queryData;
    unsigned int bitsPerPixel;

    if (mode >= (int)AtiModeListCount)
        return 16;
    info = &AtiModeList[mode];
    queryData = (unsigned char *)self->queryData;
    bitsPerPixel = info->bitsPerPixel;
    if (bitsPerPixel == IO_15BitsPerPixel)
        goto check15BitMode;
    if (bitsPerPixel == IO_24BitsPerPixel && self->colorConfig == 5)
        return 64;
    goto checkMemory;
check15BitMode:
    if ((queryData[19] & 2) != 0)
        goto checkMemory;
    return 64;
checkMemory:
    if ((unsigned int)(info->rowBytes * info->height) >
        memSizeToBytes(queryData[11]))
        return 2;
    return 0;
}

- (char)verifyMemoryMap
{
    register ATI *driver __asm__("esi") = self;
    register unsigned int *vram __asm__("ebx") =
        (unsigned int *)driver->vram;
    unsigned int saved[16];
    unsigned int i;

    bcopy(vram, saved, 0x40);
    for (i = 0; i <= 15; ++i)
        vram[i] = i;
    for (i = 0; i <= 15; ++i)
        if (vram[i] != i)
            return 0;
    bcopy(saved, driver->vram, 0x40);
    return 1;
}

- free
{
    if (self->queryDataSize != 0)
        IOFree(self->queryData, self->queryDataSize);
    if (self->atiBios != nil)
        [self->atiBios free];
    if (self->redTransferTable != NULL)
        IOFree(self->redTransferTable, 3 * self->transferTableCount);
    return [super free];
}

- (void)enterLinearMode
{
    IODisplayInfo *info;
    unsigned int depth;
    char gamma;
    unsigned int pitch;
    unsigned int result;
    ATI_CRTCRecord *crtc;
    const char *name;

    info = [self displayInfo];
    crtc = (ATI_CRTCRecord *)info->parameters;
    if (self->currentState != 1 &&
        [self->atiBios setApertureEnable:1 VGAAperture:0 apertureAdrs:0] == 0) {
        depth = displayInfoToColorDepth(info);
        displayInfoToColorSpace(info);
        gamma = depth == 2 ? self->supportsGrey256 : self->supportsGamma;
        pitch = 2;
        if (info->width == 1024)
            pitch = 0;
        result = [self->atiBios loadCRTCSetMode:depth gamma:gamma
            pitchSize:pitch resolution:129 crtTable:crtc];
        if (result != 0) {
            name = IOFindNameForValue(result, ABReturnValues);
            IOLog("%s: Error setting CRTC Paramters (%s)\n", [self name], name);
        } else {
            [self initEngine];
            self->engineStarted = 1;
            bzero(self->vram, self->vramBytes);
            self->currentState = 1;
            [self setGammaTable];
        }
    }
}

- (void)revertToVGAMode
{
    ATI_CRTCRecord crtc;
    unsigned int result;
    const char *name;

    __builtin_memcpy(&crtc, AtiVgaCRTC, 30);
    result = [self->atiBios loadCRTCSetMode:1 gamma:0 pitchSize:2
        resolution:129 crtTable:&crtc];
    if (result != 0) {
        name = IOFindNameForValue(result, ABReturnValues);
        IOLog("%s: Error setting CRTC (%s)\n", [self name], name);
    }
    result = [self->atiBios setVGAMode:1 gamma:0];
    if (result != 0) {
        name = IOFindNameForValue(result, ABReturnValues);
        IOLog("%s: Error setting VGA (%s)\n", [self name], name);
    } else {
        if (self->redTransferTable != NULL) {
            IOFree(self->redTransferTable, 3 * self->transferTableCount);
            self->redTransferTable = NULL;
        }
        self->currentState = 2;
        self->engineStarted = 0;
    }
}

unsigned int waitForFIFO(unsigned int count)
{
    unsigned int threshold;

    __asm__ __volatile__(
        "movl _register_base_address, %%edx\n\t"
        "movl $0x8000, %%eax\n\t"
        "shrl %%cl, %%eax\n\t"
        "cmpl %%eax, 0x310(%%edx)\n\t"
        "jbe 1f\n"
        "movl _register_base_address, %%edx\n\t"
        "movl $0x8000, %%eax\n\t"
        "shrl %%cl, %%eax\n\t"
        "2:\n\t"
        "cmpl %%eax, 0x310(%%edx)\n\t"
        "ja 2b\n"
        "1:"
        : "=a" (threshold)
        : "c" (count)
        : "edx", "memory", "cc");
    return threshold;
}

int waitForIdle(void)
{
    int result;

    __asm__ __volatile__(
        "xorl %%ebx, %%ebx\n\t"
        "pushl $16\n\t"
        "call _waitForFIFO\n\t"
        "addl $4, %%esp\n\t"
        "jmp 2f\n"
        ".align 2\n\t"
        "1:\n\t"
        "pushl $1\n\t"
        "call _IODelay\n\t"
        "addl $4, %%esp\n\t"
        "movl %%ebx, %%eax\n\t"
        "incl %%ebx\n\t"
        "cmpl $500000, %%eax\n\t"
        "jbe 2f\n\t"
        "pushl $_waitForIdleTimeoutMessage\n\t"
        "call _IOLog\n\t"
        "jmp 3f\n"
        "2:\n\t"
        "movl _register_base_address, %%eax\n\t"
        "testb $1, 0x338(%%eax)\n\t"
        "jnz 1b\n"
        "3:\n"
        : "=a" (result)
        :
        : "ebx", "ecx", "edx", "cc", "memory");
    return result;
}

int doBlit(unsigned int sourceX, unsigned int sourceY, unsigned int width,
           unsigned int height, unsigned int destinationX,
           unsigned int destinationY)
{
    register unsigned int sourceXReg __asm__("eax") = sourceX;
    register unsigned int destinationXReg __asm__("ecx") = destinationX;
    unsigned int overlapXDistance;
    unsigned int overlapYDistance;
    unsigned int destinationYStart;
    int direction;
    unsigned int sourceYStart;
    unsigned int destinationXStart;
    unsigned int sourceXStart;
    int savedRegister304;
    int savedRegister436;
    int savedRegister728;
    unsigned int blitSize;
    volatile unsigned int *registers;

    overlapXDistance = destinationXReg - sourceXReg;
    if ((int)overlapXDistance < 0)
        overlapXDistance = 0U - overlapXDistance;
    if (width > overlapXDistance) {
        overlapYDistance = destinationY - sourceY;
        if ((int)overlapYDistance < 0)
            overlapYDistance = 0U - overlapYDistance;
        if (height > overlapYDistance) {
            direction = 0;
            if (sourceXReg < destinationXReg) {
                sourceXStart = width + sourceXReg - 1;
                destinationXReg = width + destinationXReg - 1;
            } else {
                *(unsigned char *)&direction = 1;
                sourceXStart = sourceXReg;
            }
            destinationXStart = destinationXReg;
            if (destinationY <= sourceY) {
                *(unsigned char *)&direction |= 2;
                sourceYStart = sourceY;
                goto set_source_y;
            }
            sourceYStart = height + sourceY - 1;
            destinationYStart = height + destinationY - 1;
            goto start_blit;
        }
    }
    direction = 3;
    sourceXStart = sourceXReg;
    sourceYStart = sourceY;
    destinationXStart = destinationXReg;
set_source_y:
    destinationYStart = destinationY;
start_blit:
    waitForIdle();
    waitForFIFO(10);
    registers = (volatile unsigned int *)register_base_address;
    savedRegister728 = ATI_INREG32(register_base_address, 728);
    savedRegister436 = ATI_INREG32(register_base_address, 436);
    savedRegister304 = ATI_INREG32(register_base_address, 304);
    ATI_OUTREG32(register_base_address, 728, 768);
    registers[109] = 0;
    registers[76] = (savedRegister304 & 0x80) | direction | 0x18;
    registers[99] = sourceYStart | (sourceXStart << 16);
    blitSize = height | (width << 16);
    registers[102] = blitSize;
    registers[67] = destinationYStart | (destinationXStart << 16);
    registers[70] = blitSize;
    waitForFIFO(3);
    ATI_OUTREG32(register_base_address, 728, savedRegister728);
    ATI_OUTREG32(register_base_address, 436, savedRegister436);
    ATI_OUTREG32(register_base_address, 304, savedRegister304);
    return (int)register_base_address;
}

- showCursor:(Point *)cursorLoc frame:(int)frame token:(int)token
{
    waitForIdle();
    return [super showCursor:cursorLoc frame:frame token:token];
}

- moveCursor:(Point *)cursorLoc frame:(int)frame token:(int)token
{
    waitForIdle();
    return [super moveCursor:cursorLoc frame:frame token:token];
}

- hideCursor:(int)token
{
    waitForIdle();
    return [super hideCursor:token];
}

int doFill(unsigned int left, unsigned int top, unsigned int right,
           unsigned int bottom, unsigned int color)
{
    register volatile unsigned int *registers __asm__("eax");
    register unsigned int saved728 __asm__("edi");
    register unsigned int saved436 __asm__("esi");
    register unsigned int saved304 __asm__("ebx");
    unsigned int stackReserve[2];

    __asm__ __volatile__("" : "=m" (stackReserve) : : "memory");

    waitForIdle();
    waitForFIFO(7);
    registers = (volatile unsigned int *)register_base_address;
    saved728 = ATI_INREG32(register_base_address, 728);
    saved436 = ATI_INREG32(register_base_address, 436);
    saved304 = ATI_INREG32(register_base_address, 304);
    __asm__ __volatile__(
        "movl %0, %%edx\n\t"
        "movl %%edx, 0x2c4(%%eax)\n\t"
        "movl $0x100, 0x2d8(%%eax)\n\t"
        "movl %1, %%edx\n\t"
        "shll $16, %%edx\n\t"
        "orl %2, %%edx\n\t"
        "movl %%edx, 0x10c(%%eax)\n\t"
        "movl %3, %%edx\n\t"
        "shll $16, %%edx\n\t"
        "orl %4, %%edx\n\t"
        "movl %%edx, 0x118(%%eax)"
        :
        : "m" (color), "m" (left), "m" (top),
          "m" (right), "m" (bottom)
        : "edx", "memory");
    waitForFIFO(3);
    ATI_OUTREG32(register_base_address, 728, saved728);
    ATI_OUTREG32(register_base_address, 436, saved436);
    ATI_OUTREG32(register_base_address, 304, saved304);
    return (int)register_base_address;
}

- (void)initEngine
{
    register ATI *driver __asm__("edi") = self;
    register IODisplayInfo *info __asm__("esi");
    register unsigned int width __asm__("ebx");
    register unsigned int pitch __asm__("edx");
    register volatile unsigned int *registers __asm__("eax");
    const char *name;

    info = [driver displayInfo];
    [driver resetEngine];
    width = info->width;
    waitForFIFO(14);
    registers = (volatile unsigned int *)register_base_address;
    registers[200] = 0xFFFFFFFF;
    pitch = (width >> 3) << 22;
    registers[64] = pitch;
    registers[67] = 0;
    registers[69] = 0;
    registers[73] = 0;
    registers[74] = 0;
    registers[75] = 0;
    registers[76] = 35;
    registers[96] = pitch;
    registers[99] = 0;
    registers[102] = 0;
    registers[105] = 0;
    registers[108] = 0;
    registers[109] = 16;
    waitForFIFO(13);
    registers = (volatile unsigned int *)register_base_address;
    registers[144] = 0;
    registers[160] = 0;
    registers[161] = 0;
    registers[162] = 0;
    registers[168] = 0;
    registers[171] = 0;
    __asm__ __volatile__(
        "movl (%%esi), %%ecx\n\t"
        "decl %%ecx\n\t"
        "movl %%ecx, 0x2b0(%%eax)"
        :
        : "a" (registers), "S" (info)
        : "ecx", "memory");
    registers[169] = width - 1;
    registers[176] = 0;
    registers[177] = 0xFFFFFFFF;
    registers[178] = 0xFFFFFFFF;
    registers[181] = 458755;
    registers[182] = 256;
    waitForFIFO(3);
    registers = (volatile unsigned int *)register_base_address;
    registers[192] = 0;
    registers[193] = 0xFFFFFFFF;
    registers[194] = 0;
    switch (info->bitsPerPixel) {
    case 1:
        waitForFIFO(2);
        registers = (volatile unsigned int *)register_base_address;
        registers[180] = 16908802;
        registers[179] = 32896;
        break;
    case 3:
        waitForFIFO(2);
        registers = (volatile unsigned int *)register_base_address;
        registers[180] = 16974595;
        registers[179] = 16912;
        break;
    case 4:
        waitForFIFO(2);
        registers = (volatile unsigned int *)register_base_address;
        registers[180] = 17171974;
        registers[179] = 32896;
        break;
    case 0:
    case 2:
    case 5:
    default:
        name = [driver name];
        IOLog("%s: Pixel depth not supported,\n", name);
        break;
    }
    waitForIdle();
}

- (void)resetEngine
{
    __asm__ volatile(
        "subl $4, %%esp\n\t"
        "pushl %%ebx\n\t"
        "movl 8(%%ebp), %%eax\n\t"
        "movw 0x260(%%eax), %%cx\n\t"
        "addw $0xd0, %%cx\n\t"
        "movl %%ecx, %%edx\n\t"
        "inl %%dx, %%eax\n\t"
        "movl %%eax, %%ebx\n\t"
        "andb $0xfe, %%bh\n\t"
        "movl %%ebx, %%eax\n\t"
        "outl %%eax, %%dx\n\t"
        "lock; incl %0\n\t"
        "movl 8(%%ebp), %%edx\n\t"
        "movw 0x260(%%edx), %%cx\n\t"
        "addw $0xd0, %%cx\n\t"
        "movl %%ecx, %%edx\n\t"
        "inl %%dx, %%eax\n\t"
        "movl %%eax, %%ebx\n\t"
        "orb $1, %%bh\n\t"
        "movl %%ebx, %%eax\n\t"
        "outl %%eax, %%dx\n\t"
        "lock; incl %0\n\t"
        "movl 8(%%ebp), %%edx\n\t"
        "movw 0x260(%%edx), %%bx\n\t"
        "addw $0xa0, %%bx\n\t"
        "movl %%ebx, %%edx\n\t"
        "inl %%dx, %%eax\n\t"
        "movl %%eax, %%ecx\n\t"
        "andl $0xff00ffff, %%ecx\n\t"
        "orl $0x00ae0000, %%ecx\n\t"
        "movl %%ecx, %%eax\n\t"
        "outl %%eax, %%dx\n\t"
        "lock; incl %0\n\t"
        "movl -8(%%ebp), %%ebx"
        :
        : "m"(resetEngineWriteCounter)
        : "eax", "ecx", "edx", "cc", "memory");
}

- (unsigned int)displayModeCount
{
    return AtiModeListCount;
}

- (IODisplayInfo *)displayModes
{
    return (IODisplayInfo *)&AtiModeList;
}

- (unsigned int)displayMemorySize
{
    return memSizeToBytes(((unsigned char *)self->queryData)[11]);
}

- (char)setPendingDisplayMode:(int)mode
{
    if ((int)AtiModeListCount <= mode) {
        IOLog("%s: setPendingDisplayMode: bogus displayMode (%d)\n",
              [self name], mode);
    } else if ([self isModeValid:mode] == 0) {
        AtiModeList[mode].frameBuffer = self->vram;
        if ([super setPendingDisplayMode:mode] != 0) {
            self->modeNumber = mode;
            return 1;
        }
    }
    return 0;
}

- (int)setIntValues:(unsigned int *)values forParameter:(IOParameterName)name
              count:(unsigned int)count
{
    if (strcmp(name, "IODisplayDoBlit") == 0 && count == 6) {
        doBlit(values[0], values[1], values[2], values[3], values[4], values[5]);
    } else if (strcmp(name, "IODisplayDoFill") == 0 && count == 5) {
        doFill(values[0], values[1], values[2], values[3], values[4]);
    } else if (strcmp(name, "IOGetDisplaySynced") == 0 && count == 1) {
        waitForIdle();
    } else {
        return [super setIntValues:values forParameter:name count:count];
    }
    return 0;
}

@end

unsigned char isATI68880RevC(unsigned short base)
{
    if (inb((IOEISAPortAddress)(base + 195)) == 0xD0)
        return 1;
    return 0;
}

void SetGammaValue(unsigned short base, int red, int green, int blue,
                   int brightness)
{
    __asm__ volatile(
        "subl $4, %%esp\n\t"
        "pushl %%esi\n\t"
        "pushl %%ebx\n\t"
        "movl 20(%%ebp), %%ebx\n\t"
        "movl 24(%%ebp), %%ecx\n\t"
        "movw 8(%%ebp), %%dx\n\t"
        "addw $0xc1, %%dx\n\t"
        "movl 12(%%ebp), %%eax\n\t"
        "imull %%ecx, %%eax\n\t"
        "shrl $6, %%eax\n\t"
        "outb %%al, %%dx\n\t"
        "lock; incl %0\n\t"
        "movl 16(%%ebp), %%esi\n\t"
        "imull %%ecx, %%esi\n\t"
        "movl %%esi, %%eax\n\t"
        "shrl $6, %%eax\n\t"
        "outb %%al, %%dx\n\t"
        "lock; incl %0\n\t"
        "imull %%ecx, %%ebx\n\t"
        "movl %%ebx, %%eax\n\t"
        "shrl $6, %%eax\n\t"
        "outb %%al, %%dx\n\t"
        "lock; incl %0\n\t"
        "lea -12(%%ebp), %%esp\n\t"
        "popl %%ebx\n\t"
        "popl %%esi"
        : "=m"(setGammaValueWriteCounter)
        :
        : "eax", "ecx", "edx", "cc", "memory");
}

@implementation ATI (ProgramDAC)

- setGammaTable
{
    unsigned short port;
    unsigned char value;
    unsigned int depth;
    register unsigned int j __asm__("ebx");
    register unsigned int i __asm__("esi");
    unsigned int k;
    unsigned int m;
    unsigned int n;

    port = (unsigned short)self->baseAddress + 196;
    value = inb((IOEISAPortAddress)port);
    writeGammaDACByte((IOEISAPortAddress)port, (value & 0xFC) | 2);
    writeGammaDACByte((IOEISAPortAddress)((unsigned short)self->baseAddress + 194), 0xFF);
    writeGammaDACByte((IOEISAPortAddress)((unsigned short)self->baseAddress + 192), 0);
    if (self->redTransferTable != NULL) {
        for (i = 0; self->transferTableCount > i; ++i) {
            for (j = 0; j < 256 / self->transferTableCount; ++j)
                SetGammaValue((unsigned short)self->baseAddress,
                    (unsigned char)self->redTransferTable[i],
                    (unsigned char)self->greenTransferTable[i],
                    (unsigned char)self->blueTransferTable[i],
                    self->brightnessLevel);
        }
    } else {
        {
            SEL displayInfoSelector = @selector(displayInfo);
            id displayInfoReceiver = self;
            id displayInfo;
            SEL selectorAfterCall;
            __asm__ volatile(
                "pushl %%eax\n\t"
                "pushl %2\n\t"
                "call _objc_msgSend\n\t"
                "movl %%eax, %%edx\n\t"
                "addl $8, %%esp"
                : "=d" (displayInfo), "=a" (selectorAfterCall)
                : "D" (displayInfoReceiver), "1" (displayInfoSelector)
                : "ecx", "memory", "cc");
            depth = ((unsigned int *)displayInfo)[6];
        }
        switch (depth) {
        case 1:
            for (k = 0; k <= 255; ++k)
                SetGammaValue((unsigned short)self->baseAddress,
                    gamma8[k], gamma8[k], gamma8[k], self->brightnessLevel);
            break;
        case 3:
        case 4:
            for (m = 0; m <= 31; ++m)
                for (n = 0; n <= 7; ++n)
                    SetGammaValue((unsigned short)self->baseAddress,
                        gamma16[m >> 1], gamma16[m >> 1], gamma16[m >> 1],
                        self->brightnessLevel);
            break;
        default:
            break;
        }
    }
    return self;
}

- setBrightness:(int)level token:(int)token
{
    if ((unsigned int)level > 0x40) {
        IOLog("Display: Invalid arg to setBrightness: %d\n", level);
        return nil;
    }
    self->brightnessLevel = level;
    [self setGammaTable];
    return self;
}

- setTransferTable:(const unsigned int *)table count:(int)count
{
    unsigned char *queryData;
    char shift;
    char selectedShift;
    unsigned char dacType;
    register int ramdacStyle __asm__("eax");
    register int asicType __asm__("edx");
    register unsigned short revCBaseAddress __asm__("eax");
    int i;
    int colorSpace;
    register unsigned int value __asm__("eax");
    char *red;
    char *green;
    register char *blue __asm__("edx");

    queryData = (unsigned char *)self->queryData;
    __asm__ volatile ("movb 9(%1), %b0" : "=d" (asicType) : "a" (queryData));
    dacType = queryData[12];
    revCBaseAddress = (unsigned short)self->baseAddress;
    shift = 2;
    if (self->supportsGrey256 != 0)
        shift = 0;
    asicType &= 0xff;
    if (asicType != 67 && asicType != 69) {
        asicType = (unsigned char)dacType;
        if (asicType == 5) {
            goto use_full_table;
        }
        if (asicType <= 5) {
            if (asicType == 2)
                goto use_full_table;
            goto apply_ramdac_style;
        }
        if (asicType == 21 &&
            isATI68880RevC(revCBaseAddress))
            goto use_full_table;
    }
    goto apply_ramdac_style;
use_full_table:
    shift = 0;
apply_ramdac_style:
    selectedShift = shift;
    ramdacStyle = self->ramdacStyle;
    if (ramdacStyle == 1) {
        selectedShift = 0;
    } else if (ramdacStyle == 2) {
        selectedShift = 2;
    }
    if (self->redTransferTable != NULL)
        IOFree(self->redTransferTable, 3 * self->transferTableCount);
    self->transferTableCount = count;
    self->redTransferTable = IOMalloc(3 * count);
    self->greenTransferTable = self->redTransferTable + count;
    self->blueTransferTable = self->greenTransferTable + count;
    [self displayInfo];
    colorSpace = ((unsigned int *)[self displayInfo])[7];
    switch (colorSpace) {
    case 1:
        for (i = 0; i < count; ++i) {
            red = self->redTransferTable;
            green = self->greenTransferTable;
            blue = self->blueTransferTable;
            __asm__ volatile("" ::: "memory");
            value = (unsigned int)((unsigned char *)&table[i])[0] >> selectedShift;
            blue[i] = value;
            green[i] = value;
            red[i] = value;
        }
        break;
    case 2:
        for (i = 0; i < count; ++i) {
            self->redTransferTable[i] = (unsigned int)((unsigned char *)&table[i])[3] >> selectedShift;
            self->greenTransferTable[i] = (unsigned int)((unsigned char *)&table[i])[2] >> selectedShift;
            self->blueTransferTable[i] = (unsigned int)((unsigned char *)&table[i])[1] >> selectedShift;
        }
        break;
    default:
        IOFree(self->redTransferTable, 3 * count);
        self->redTransferTable = NULL;
        break;
    }
    [self setGammaTable];
    return self;
}

@end

int displayInfoToColorSpace(const IODisplayInfo *info)
{
    unsigned int bitsPerPixel;
    int colorSpace;

    colorSpace = 0;
    bitsPerPixel = info->bitsPerPixel;
    switch (bitsPerPixel) {
    case 1:
        colorSpace = 1;
        if (info->colorSpace == 1)
            colorSpace = 0;
        break;
    case 3:
        colorSpace = 2;
        break;
    case 4:
        colorSpace = 3;
        break;
    default:
        IOLog("ATIMach64: displayInfoToColorSpace problem (%d)\n",
            info->bitsPerPixel);
        IOPanic("ATIMach64 displayInfoToColorSpace");
        break;
    }
    return colorSpace;
}

int colorDepthToColorSpace(int depth)
{
    int colorSpace;

    colorSpace = 0;
    switch (depth) {
    case 2:
        colorSpace = 1;
        break;
    case 3:
    case 4:
        colorSpace = 2;
        break;
    case 5:
    case 6:
        colorSpace = 3;
        break;
    default:
        break;
    }
    return colorSpace;
}

int displayInfoToColorDepth(const IODisplayInfo *info)
{
    const IODisplayInfo *displayInfo;
    unsigned int bitsPerPixel;
    int colorDepth;

    displayInfo = info;
    colorDepth = 0;
    bitsPerPixel = displayInfo->bitsPerPixel;
    switch (bitsPerPixel) {
    case 1:
        colorDepth = 2;
        break;
    case 3:
        colorDepth = 3;
        break;
    case 4:
        colorDepth = 6;
        break;
    default:
        IOPanic("ATIMach64: displayInfoToColorDepth problem");
        break;
    }
    return colorDepth;
}

int memSizeToBytes(unsigned char memorySize)
{
    switch (memorySize) {
    case 0: return 0x80000;
    case 1: return 0x100000;
    case 2: return 0x200000;
    case 3: return 0x400000;
    case 4: return 6291456;
    case 5: return 8386560;
    default: return 0x200000;
    }
}

static void *ValidModeList __attribute__((used)) = 0;
