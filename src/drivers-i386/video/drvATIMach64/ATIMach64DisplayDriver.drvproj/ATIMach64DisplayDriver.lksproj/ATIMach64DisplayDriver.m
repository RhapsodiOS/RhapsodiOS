#define KERNEL_PRIVATE 1
#define DRIVER_PRIVATE 1

#import "ATIPrivate.h"
#import "ATIData.h"
#import <driverkit/IOConfigTable.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <machdep/i386/pmap.h>
#import <string.h>

@implementation ATI

- initFromDeviceDescription:(id)description
{
    unsigned int biosAddress = 0;
    unsigned int tableAddress;
    unsigned int candidateAddress;
    unsigned int memoryLimit;
    unsigned int candidateTableAddress;
    unsigned int index;
    unsigned int pciAddress;
    unsigned int *queryData;
    id configTable;
    char *value;
    char typeName[32];
    char logBuffer[180];
    char useBIOS = 0;
    char useTable = 0;
    char apertureChanged = 0;
    int result;

    if ([super initFromDeviceDescription:description] == nil)
        return [super free];
    if ([ATI_BIOS ATIPresent:&biosAddress] == 0) {
        IOLog("%s: ATI BIOS not found\n", [self name]);
        return [super free];
    }
    atiBios = [[ATI_BIOS alloc] init];
    if (atiBios == nil)
        return [super free];
    queryDataSize = 0;
    if ([self getQueryData] != 0)
        return [super free];

    queryData = (unsigned int *)self->queryData;
    supportsGamma = (((unsigned char *)queryData)[20] & 0x40) != 0;
    supportsGrey256 = (((unsigned char *)queryData)[20] & 0x20) != 0;
    strcpy(typeName, IOFindNameForValue(((unsigned char *)queryData)[9], ATI_AsicTypeValues));
    if (((unsigned char *)queryData)[9] == 0xd7) {
        value = (char *)IOFindNameForValue(((unsigned char *)queryData)[8], ATI_AsicSubTypeValues);
        strcat(typeName, value);
    }
    value = (char *)IOFindNameForValue(((unsigned char *)queryData)[12], ATI_dacTypeValues);
    sprintf(logBuffer, "%s: ATI Mach64 Found; Type %s; DAC = %s\n",
            [self name], typeName, value);
    IOLog(logBuffer);
    sprintf(logBuffer, "%s: memory=%s; BIOS@%x; Gamma=%s; 256-grey=%s\n",
            [self name], IOFindNameForValue(((unsigned char *)queryData)[11], ATI_memSizeValues),
            biosAddress, supportsGamma ? "YES" : "NO",
            supportsGrey256 ? "YES" : "NO");
    IOLog(logBuffer);

    [self updateModeList];
    configTable = [description configTable];
    colorConfig = 0;
    value = (char *)[configTable valueForStringKey:"24-bit Configuration"];
    if (value != nil) {
        if (strcmp(value, "RGBx") == 0) colorConfig = 1;
        else if (strcmp(value, "BGRx") == 0) colorConfig = 2;
        else if (strcmp(value, "xRGB") == 0) colorConfig = 3;
        else if (strcmp(value, "xBGR") == 0) colorConfig = 4;
        if (colorConfig != 0)
            IOLog("%s: colorConfig from table = %s\n", [self name], value);
        [configTable freeString:value];
    }

    fbMapStyle = 0;
    value = (char *)[configTable valueForStringKey:"Frame Buffer Mapping"];
    if (value != nil) {
        if (strcmp(value, "BIOS") == 0) fbMapStyle = 1;
        else if (strcmp(value, "Table") == 0) fbMapStyle = 2;
        if (fbMapStyle != 0)
            IOLog("%s: fbMapStyle from table = %s\n", [self name], value);
        [configTable freeString:value];
    }

    ramdacStyle = 0;
    value = (char *)[configTable valueForStringKey:"RAMDAC Style"];
    if (value != nil) {
        if (strcmp(value, "Sparse") == 0) ramdacStyle = 1;
        else if (strcmp(value, "Dense") == 0) ramdacStyle = 2;
        if (ramdacStyle != 0)
            IOLog("%s: ramdacStyle from table = %s\n", [self name], value);
        [configTable freeString:value];
    }

    isPCI = 0;
    value = (char *)[configTable valueForStringKey:"Bus Type"];
    if (value != nil) {
        if (strcmp(value, "PCI") == 0) isPCI = 1;
        [configTable freeString:value];
    }
    value = (char *)[configTable valueForStringKey:"Display Mode"];
    if (value == nil) {
        IOLog("%s: No Display Mode found; aborting\n", [self name]);
        return [self free];
    }
    result = [self parseModeString:value];
    if (result != 0)
        return [self free];

    if (AtiModeList[modeNumber].bitsPerPixel == IO_24BitsPerPixel)
        IOLog("%s: 24 Bit Color Configuration = %s\n", [self name],
              IOFindNameForValue(colorConfig, colorConfigValues));
    vramBytes = memSizeToBytes(((unsigned char *)queryData)[11]);
    biosAddress = (unsigned int)(*((unsigned short *)queryData + 8)) << 20;

    {
        IORange *ranges = [description memoryRangeList];
        if (ranges == nil) {
            IOLog("%s: No memory Range specified in config table; aborting\n", [self name]);
            return [self free];
        }
        tableAddress = ranges[0].start;
    }

    candidateAddress = biosAddress;
    candidateTableAddress = tableAddress;
    if (fbMapStyle == 1) {
        useBIOS = 1;
        candidateTableAddress = biosAddress;
    } else if (fbMapStyle == 2) {
        useTable = 1;
        candidateAddress = tableAddress;
    }
    if ((((unsigned char *)queryData)[18] & 0x80) != 0 && fbMapStyle == 0) {
        memoryLimit = 0x08000000 - vramBytes;
        if (tableAddress > memoryLimit) {
            if (biosAddress > memoryLimit) {
                useTable = useBIOS = 1;
                tableAddress = biosAddress = 0x07800000;
            } else {
                useBIOS = 1;
            }
        } else if (biosAddress > memoryLimit) {
            useTable = 1;
            biosAddress = tableAddress;
        }
        candidateAddress = biosAddress;
        candidateTableAddress = tableAddress;
    }

    for (;;) {
        if (candidateTableAddress == candidateAddress && useBIOS == 0)
            goto table_mapping_done;
        result = [self changeTableMapping:candidateAddress];
        if (result == 0) {
            IOLog("%s: Changing Config Table Address to 0x%x\n",
                  [self name], candidateAddress);
            candidateTableAddress = candidateAddress;
            goto table_mapping_done;
        }
        if (useBIOS != 0) {
            if (candidateAddress == 0x07800000) {
                IOLog("%s: error setting memory map to 0x%x(%s); aborting\n",
                      [self name], 0x07800000, [self stringFromReturn:result]);
                return [self free];
            }
            IOLog("%s: memory range @ 0x%x reserved; retrying at 0x%x\n",
                  [self name], candidateAddress, 0x07800000);
            useTable = 1;
            candidateTableAddress = 0x07800000;
            candidateAddress = 0x07800000;
            tableAddress = 0x07800000;
            biosAddress = 0x07800000;
            goto retry_hardware_mapping;
        }
        useTable = 1;

table_mapping_done:
        if (useTable == 0)
            goto mapping_done;
retry_hardware_mapping:
        if ([self changeHardwareMapping:candidateTableAddress] == 0)
            break;
        if (candidateTableAddress == 0x07800000) {
            IOLog("%s: Can't set memory aperture to 0x%x; aborting\n",
                  [self name], 0x07800000);
            return [self free];
        }
        IOLog("%s: Can't set memory aperture to 0x%x; retrying at 0x%x\n",
              [self name], candidateTableAddress, 0x07800000);
        useBIOS = 1;
        candidateTableAddress = 0x07800000;
        candidateAddress = 0x07800000;
        tableAddress = 0x07800000;
        biosAddress = 0x07800000;
        goto retry_hardware_mapping;
    }
    apertureChanged = 1;
    candidateAddress = candidateTableAddress;
    IOLog("%s: Changing aperture address to 0x%x\n",
          [self name], candidateTableAddress);

mapping_done:
    if (apertureChanged != 0 ||
        [atiBios setApertureEnable:1 VGAAperture:0 apertureAdrs:0] == 0) {
        vram = [self mapFrameBufferAtPhysicalAddress:candidateAddress
                                              length:(~page_mask & (page_mask + vramBytes))];
        if (vram == nil) {
            IOLog("%s: Unable to map frame buffer\n", [self name]);
            return [self free];
        }
        IOLog("%s: frame buffer physical addrs 0x%x; mapped to 0x%x\n",
              [self name], candidateAddress, vram);
        for (index = 0; index < (unsigned int)AtiModeListCount; ++index)
            AtiModeList[index].frameBuffer = vram;
        memcpy([super displayInfo], &AtiModeList[modeNumber], sizeof(IODisplayInfo));
        if ([self verifyMemoryMap] != 0) {
            currentState = 0;
            blueTransferTable = nil;
            greenTransferTable = nil;
            redTransferTable = nil;
            transferTableCount = 0;
            brightnessLevel = 64;
            return self;
        }
        IOLog("%s: VRAM test failure, aborting\n", [self name]);
    }
    return [self free];
}

- free
{
    if (queryDataSize != 0)
        IOFree(queryData, queryDataSize);
    if (atiBios != nil)
        [atiBios free];
    if (redTransferTable != nil)
        IOFree(redTransferTable, 3 * transferTableCount);
    return [super free];
}

- (void)enterLinearMode
{
    IODisplayInfo *mode;
    int colorDepth;
    int gamma;
    int pitchSize;
    int result;

    mode = [self displayInfo];
    if (currentState != 1 &&
        [atiBios setApertureEnable:1 VGAAperture:0 apertureAdrs:0] == 0) {
        colorDepth = displayInfoToColorDepth(mode);
        (void)displayInfoToColorSpace(mode);
        gamma = colorDepth == 2 ? supportsGrey256 : supportsGamma;
        pitchSize = mode->width == 1024 ? 0 : 2;
        result = [atiBios loadCRTCSetMode:colorDepth gamma:gamma pitchSize:pitchSize
                              resolution:129 crtTable:(ATI_CRTCRecord *)mode->parameters];
        if (result != 0) {
            IOLog("%s: Error setting CRTC Paramters (%s)\n", [self name],
                  IOFindNameForValue(result, ABReturnValues));
        } else {
            memset(vram, 0, vramBytes);
            currentState = 1;
            [self setGammaTable];
        }
    }
}

- (void)revertToVGAMode
{
    int result = [atiBios setVGAMode:1 gamma:0];
    if (result != 0) {
        IOLog("%s: Error setting VGA (%s)\n", [self name],
              IOFindNameForValue(result, ABReturnValues));
    } else {
        if (redTransferTable != nil) {
            IOFree(redTransferTable, 3 * transferTableCount);
            redTransferTable = nil;
        }
        currentState = 2;
    }
}

- (unsigned int)displayModeCount
{
    return AtiModeListCount;
}

- (IODisplayInfo *)displayModes
{
    return AtiModeList;
}

- (unsigned int)displayMemorySize
{
    return memSizeToBytes(((unsigned char *)queryData)[11]);
}

- (char)setPendingDisplayMode:(int)mode
{
    if (AtiModeListCount <= mode) {
        IOLog("%s: setPendingDisplayMode: bogus displayMode (%d)\n", [self name], mode);
    } else if ([self isModeValid:mode] == 0) {
        modeNumber = mode;
        return [super setPendingDisplayMode:mode];
    }
    return 0;
}

@end
