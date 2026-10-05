#define KERNEL_PRIVATE 1
#define DRIVER_PRIVATE 1

#import "ATIPrivate.h"
#import "ATIData.h"
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IOConfigTable.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <strings.h>
#import <string.h>

@implementation ATI (Private)

- (int)getQueryData
{
    unsigned int querySize = 0;
    unsigned short *queryBuffer;
    int result;

    if (queryDataSize != 0) {
        IOFree(queryData, queryDataSize);
        queryDataSize = 0;
    }
    result = [atiBios querySize:0 size:&querySize];
    if (result != 0) {
        IOLog("%s: querySize returned %s\n", [self name],
              IOFindNameForValue(result, ABReturnValues));
    } else {
        queryBuffer = (unsigned short *)IOMalloc(querySize);
        result = [atiBios deviceQuery:0 bufferSize:querySize buffer:queryBuffer];
        if (result == 0) {
            queryDataSize = *queryBuffer;
            queryData = (unsigned char *)IOMalloc(queryDataSize);
            bcopy(queryBuffer, queryData, queryDataSize);
            IOFree(queryBuffer, querySize);
            return 0;
        }
        IOLog("%s: deviceQuery returned %s\n", [self name],
              IOFindNameForValue(result, ABReturnValues));
        if (querySize != 0)
            IOFree(queryBuffer, querySize);
    }
    return 1;
}

- (int)parseModeString:(const char *)modeString
{
    int selected;

    selected = [self selectMode:AtiModeList count:AtiModeListCount
                          valid:(const BOOL *)modeValidArray];
    modeNumber = selected;
    if (selected >= 0) {
        unsigned int invalid = [self isModeValid:modeNumber];
        if (invalid == 0)
            return 0;
        IOLog("%s: Requested Mode not supported (0x%x); aborting\n",
              [self name], invalid);
    } else {
        IOLog("%s: selectMode problem; aborting\n", [self name]);
    }
    return -1;
}

- (void)updateModeList
{
    const char *encoding;
    unsigned int index;

    modeValidArray = 0;
    if (colorConfig == 0) {
        if ((queryData[19] & 0x20) != 0)
            colorConfig = 1;
        else if ((signed char)queryData[19] >= 0) {
            if ((queryData[19] & 0x40) != 0)
                colorConfig = 2;
            else if ((queryData[19] & 0x10) != 0)
                colorConfig = 4;
            else
                colorConfig = 5;
        } else
            colorConfig = 3;
    }

    if (colorConfig == 2)
        encoding = "BBBBBBBBGGGGGGGGRRRRRRRR--------";
    else if (colorConfig == 3)
        encoding = "--------RRRRRRRRGGGGGGGGBBBBBBBB";
    else if (colorConfig == 4)
        encoding = "--------BBBBBBBBGGGGGGGGRRRRRRRR";
    else
        encoding = "RRRRRRRRGGGGGGGGBBBBBBBB--------";

    for (index = 0; index < (unsigned int)AtiModeListCount; ++index) {
        IODisplayInfo *mode = &AtiModeList[index];
        if (mode->bitsPerPixel == IO_24BitsPerPixel)
            strcpy(mode->pixelEncoding, encoding);
        mode->totalWidth = mode->width;
        mode->rowBytes = mode->totalWidth * (strlen(mode->pixelEncoding) >> 3);
        mode->frameBuffer = vram;
        if (displayInfoToColorSpace(mode) > 1 && supportsGamma != 0 ||
            mode->bitsPerPixel == IO_8BitsPerPixel)
            mode->flags = 16;
        else
            mode->flags = 2;
        mode->modeUnavailableFlag = [self isModeValid:(int)index];
        mode->memorySize = mode->height * mode->rowBytes;
    }
}

- (unsigned int)isModeValid:(int)modeIndex
{
    IODisplayInfo *mode;
    unsigned int required;

    if (AtiModeListCount <= modeIndex)
        return 16;
    mode = &AtiModeList[modeIndex];
    if (mode->bitsPerPixel == IO_15BitsPerPixel &&
        (queryData[19] & 2) == 0)
        return 64;
    if (mode->bitsPerPixel == IO_24BitsPerPixel && colorConfig == 5)
        return 64;
    required = mode->height * mode->rowBytes;
    if (required > memSizeToBytes(queryData[11]))
        return 2;
    return 0;
}

- (char)verifyMemoryMap
{
    unsigned int saved[16];
    unsigned int index;

    bcopy(vram, saved, sizeof(saved));
    for (index = 0; index <= 15; ++index)
        ((unsigned int *)vram)[index] = index;
    for (index = 0; index <= 15; ++index) {
        if (((unsigned int *)vram)[index] != index)
            return 0;
    }
    bcopy(saved, vram, sizeof(saved));
    return 1;
}

- (int)changeHardwareMapping:(unsigned int)address
{
    unsigned int pciAddress;
    unsigned int biosAddress;
    int result;

    pciAddress = 0;
    result = [atiBios setApertureEnable:1 VGAAperture:0 apertureAdrs:address];
    if (result != 0)
        return 1;
    if (isPCI != 0) {
        pciAddress = address;
        result = [self setPCIConfigData:pciAddress atRegister:16];
        if (result != 0) {
            IOLog("%s: error setting PCI config data (%s)\n", [self name],
                  [self stringFromReturn:result]);
            return 1;
        }
        pciAddress = 0;
        result = [self getPCIConfigData:&pciAddress atRegister:16];
        if (result != 0) {
            IOLog("%s: error getting PCI config data (%s)\n", [self name],
                  [self stringFromReturn:result]);
            return 1;
        }
        if (pciAddress != address) {
            IOLog("%s: Set Aperture Addrs to 0x%x;  PCI Config Register reported 0x%x\n",
                  [self name], address, pciAddress);
            return 1;
        }
    }
    if ([self getQueryData] == 0) {
        biosAddress = (unsigned int)(*((unsigned short *)queryData + 8)) << 20;
        if (biosAddress == address)
            return 0;
        IOLog("%s: Set Aperture Addrs to 0x%x;  BIOS reported 0x%x\n",
              [self name], address, biosAddress);
    }
    return 1;
}

- (int)changeTableMapping:(unsigned int)address
{
    id description;
    IORange *ranges;
    IORange replacement[3];
    unsigned int oldAddress;
    unsigned int index;
    unsigned int rangeCount;
    IOReturn result;
    IOReturn restoreResult;

    description = [self deviceDescription];
    ranges = [description memoryRangeList];
    if (ranges == nil) {
        IOLog("%s: No memory Range specified in config table\n", [self name]);
        return -701;
    }
    rangeCount = [description numMemoryRanges];
    if (rangeCount != 3) {
        IOLog("%s: Incorrect number of Memory Ranges (%d, should be 3)\n",
              [self name], rangeCount);
        return -701;
    }
    oldAddress = ranges[0].start;
    for (index = 0; index < 3; ++index)
        replacement[index] = ranges[index];
    replacement[0].start = address;
    [description setMemoryRangeList:replacement num:0];
    result = [description setMemoryRangeList:replacement num:3];
    if (result != 0) {
        replacement[0].start = oldAddress;
        [description setMemoryRangeList:replacement num:0];
        restoreResult = [description setMemoryRangeList:replacement num:3];
        if (restoreResult != 0)
            IOLog("%s: WARNING: Error (%s) restoringMemory Range to 0x%x\n",
                  [self name], [self stringFromReturn:restoreResult], oldAddress);
    }
    return result;
}

@end
