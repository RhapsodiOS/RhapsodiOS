/*
 * Copyright (c) 1998 Apple Computer, Inc. All rights reserved.
 *
 * ATIRageDisplayDriver.m - ATI Rage Display Driver Implementation
 *
 * HISTORY
 * 28 Mar 98    Created.
 */

#define KERNEL_PRIVATE 1
#define DRIVER_PRIVATE 1

#import "ATIRageDisplayDriver.h"
#import "ATIRageRegs.h"
#import <driverkit/KernBus.h>
#import <driverkit/KernBusMemory.h>
#import <driverkit/IODisplayPrivate.h>
#import <driverkit/IOFrameBufferShared.h>
#import <driverkit/IODirectDevicePrivate.h>
#import <driverkit/displayDefs.h>
#import <driverkit/i386/directDevice.h>
#import <driverkit/i386/driverTypes.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <string.h>
#import <stdlib.h>

/* Display modes supported */
static const IODisplayInfo _ATIRageModes[] = {
    {
        480,                            // height
        640,                            // width
        640,                            // totalWidth
        640,                            // rowBytes
        60,                             // refreshRate
        IO_8BitsPerPixel,               // bitsPerPixel
        IO_RGBColorSpace,               // colorSpace
        "PPPPPPPP",                     // pixelEncoding
        0,                              // flags
        0                               // reserved
    },
    {
        600,                            // height
        800,                            // width
        800,                            // totalWidth
        800,                            // rowBytes
        60,                             // refreshRate
        IO_8BitsPerPixel,               // bitsPerPixel
        IO_RGBColorSpace,               // colorSpace
        "PPPPPPPP",                     // pixelEncoding
        0,                              // flags
        0                               // reserved
    },
    {
        768,                            // height
        1024,                           // width
        1024,                           // totalWidth
        1024,                           // rowBytes
        60,                             // refreshRate
        IO_8BitsPerPixel,               // bitsPerPixel
        IO_RGBColorSpace,               // colorSpace
        "PPPPPPPP",                     // pixelEncoding
        0,                              // flags
        0                               // reserved
    }
};

#define NUM_ATI_RAGE_MODES (sizeof(_ATIRageModes) / sizeof(IODisplayInfo))

@implementation ATIRageDisplayDriver

+ (BOOL)probe:deviceDescription
{
    IOPCIDeviceDescription *pciDesc;
    unsigned int vendorID, deviceID;

    if ([super probe:deviceDescription] == NO)
        return NO;

    if (![deviceDescription isKindOf:[IOPCIDeviceDescription class]])
        return NO;

    pciDesc = (IOPCIDeviceDescription *)deviceDescription;
    vendorID = [pciDesc vendorID];
    deviceID = [pciDesc deviceID];

    /* Check for ATI vendor ID */
    if (vendorID != 0x1002)
        return NO;

    /* Check for various ATI Rage device IDs from Auto Detect IDs */
    switch (deviceID) {
        case 0x4354:  // ATI Rage
        case 0x4754:  // ATI Rage II
        case 0x4755:  // ATI Rage II+
        case 0x4756:  // ATI Rage IIC
        case 0x4C47:  // ATI Rage LT
        case 0x5C55:  // ATI Rage Mobility
            return YES;
        default:
            return NO;
    }
}

- initFromDeviceDescription:deviceDescription
{
    IOPCIDeviceDescription *pciDesc;
    IODisplayInfo *mode;
    IOReturn ret;

    [super initFromDeviceDescription:deviceDescription];

    pciDesc = (IOPCIDeviceDescription *)deviceDescription;
    _pciDevice = [pciDesc pciDevice];

    /* Initialize default values */
    _ATI_modeListCount = 0;
    _ATI_modeList = NULL;
    _ATI_modeUseRefreshRate = 0;

    /* Map the framebuffer memory */
    mode = (IODisplayInfo *)&_ATIRageModes[0];

    ret = [self selectMode:_ATIRageModes count:NUM_ATI_RAGE_MODES];
    if (ret < 0) {
        IOLog("%s: Failed to select display mode\n", [self name]);
        [self free];
        return nil;
    }

    /* Initialize hardware */
    if (![self initializeHardware]) {
        IOLog("%s: Failed to initialize hardware\n", [self name]);
        [self free];
        return nil;
    }

    /* Parse modes string from config */
    [self parseModesString];

    return self;
}

- free
{
    if (_mmioBase) {
        IOUnmapPhysicalMemory((vm_address_t)_mmioBase, 0x4000);
        _mmioBase = 0;
    }

    if (_biosBase) {
        IOUnmapPhysicalMemory((vm_address_t)_biosBase, 0x10000);
        _biosBase = 0;
    }

    if (_ATI_modeList) {
        IOFree(_ATI_modeList, _ATI_modeListCount * sizeof(IODisplayInfo));
        _ATI_modeList = NULL;
    }

    return [super free];
}

- (BOOL)initializeHardware
{
    unsigned int memBase;

    /* Map MMIO registers */
    memBase = 0xa0000;  // VGA memory region
    _mmioBase = (vm_address_t)IOMapPhysicalMemory(memBase, 0x4000, IO_CacheOff);
    if (!_mmioBase) {
        IOLog("%s: Failed to map MMIO registers\n", [self name]);
        return NO;
    }

    /* Detect memory size */
    [self detectMemorySize];

    /* Setup registers */
    [self setupRegisters];

    return YES;
}

- (void)detectMemorySize
{
    unsigned int memSize, memCntl;

    if (_mmioBase) {
        /* Read memory size from CONFIG_MEMSIZE register */
        memSize = INREG(_mmioBase + R128_CONFIG_MEMSIZE);
        _memorySize = memSize;  /* Size is already in bytes */

        /* If embedded memory size is available */
        if (memSize == 0) {
            memSize = INREG(_mmioBase + R128_CONFIG_MEMSIZE_EMBEDDED);
            _memorySize = memSize;
        }

        /* Validate memory size - common sizes are 2MB, 4MB, 8MB, 16MB */
        if (_memorySize < (2 * 1024 * 1024)) {
            _memorySize = 2 * 1024 * 1024;
        }

        /* Read memory controller to determine type */
        memCntl = INREG(_mmioBase + R128_MEM_CNTL);

        IOLog("%s: Detected %d MB video memory (MemCntl: 0x%08x)\n",
              [self name], _memorySize / (1024 * 1024), memCntl);
    } else {
        /* Default to 2MB if we can't detect */
        _memorySize = 2 * 1024 * 1024;
    }

    /* Set default RAMDAC speed based on memory size and type */
    if (_memorySize >= 8 * 1024 * 1024) {
        _ramdacSpeed = 135000000;  // 135 MHz for 8MB+ Rage
    } else {
        _ramdacSpeed = 100000000;  // 100 MHz for smaller configs
    }

    /* Initialize memory size values for different bit depths */
    _ATI_memSize60BitsPerPixel = _memorySize;
    _ATI_memSize12BitsPerPixel = _memorySize;
    _ATI_memSize15BitsPerPixel = _memorySize / 2;  // Half for 15-bit
    _ATI_memSize24BitsPerPixel = _memorySize / 3;  // Third for 24-bit
    _ATI_memSizeValues = _memorySize;
}

- (void)setupRegisters
{
    unsigned int temp;

    if (!_mmioBase) return;

    /* Enable linear addressing mode */
    temp = INREG(_mmioBase + R128_CRTC_EXT_CNTL);
    temp |= R128_VGA_ATI_LINEAR;
    temp &= ~R128_CRTC_HSYNC_DIS;
    temp &= ~R128_CRTC_VSYNC_DIS;
    temp &= ~R128_CRTC_DISPLAY_DIS;
    OUTREG(_mmioBase + R128_CRTC_EXT_CNTL, temp);

    /* Enable CRTC */
    temp = INREG(_mmioBase + R128_CRTC_GEN_CNTL);
    temp |= R128_CRTC_EN;
    temp |= R128_CRTC_EXT_DISP_EN;
    OUTREG(_mmioBase + R128_CRTC_GEN_CNTL, temp);

    /* Program DAC */
    [self ATI_ProgramDAC];
}

- (void)enterLinearMode
{
    IODisplayInfo *mode;
    vm_address_t fbAddr;

    mode = [self displayInfo];

    /* Map framebuffer at 0xa0000 for VGA compatibility */
    fbAddr = [self mapFrameBufferAtPhysicalAddress:0xa0000
                                            length:mode->totalWidth * mode->height *
                                                   (mode->bitsPerPixel / 8)];

    if (!fbAddr) {
        IOLog("%s: Failed to map framebuffer\n", [self name]);
        return;
    }

    mode->frameBuffer = fbAddr;

    [self setupRegisters];
}

- (void)revertToVGAMode
{
    /* Reset to VGA text mode */
}

- (unsigned int)displayMemorySize
{
    return _memorySize;
}

- (unsigned int)ramdacSpeed
{
    return _ramdacSpeed;
}

- (void)parseModesString
{
    /* Parse the display modes from configuration table */
    /* This would extract and configure available display modes */
}

- (void)updateBiosMode
{
    /* Update BIOS mode settings */
}

- (BOOL)isNodeValid
{
    /* Verify that the device node is valid */
    return YES;
}

- (void)verifyMemoryMap
{
    /* Verify the memory mapping is correct */
}

- (int)interruptOccurred
{
    /* Handle hardware interrupts */
    return 0;
}

- (void)moveCursor:(void *)token
{
    /* Move hardware cursor to new position */
}

- (void)resetCursor:(void *)token
{
    /* Reset hardware cursor */
}

- (void)waitForRefresh:(unsigned long long)param
{
    /* Wait for vertical refresh */
}

- (void)setTransferTable:(unsigned int *)count refresh:(unsigned long long)param1
                   crtc:(unsigned long long)param2
{
    /* Set color transfer table */
}

- (unsigned int)programAC
{
    /* Program attribute controller */
    return 0;
}

- (unsigned int)setTransferTable_count
{
    /* Return transfer table count */
    return 256;
}

/* ATI-specific BIOS and DAC functions */

- (void)ATI_ProgramDAC
{
    unsigned int dacCntl;

    if (!_mmioBase) return;

    /* Program the DAC (Digital-to-Analog Converter) registers */
    /* Based on r128 driver DAC initialization */
    dacCntl = R128_DAC_MASK_ALL |        /* Enable all color components */
              R128_DAC_VGA_ADR_EN |      /* Enable VGA addressing */
              R128_DAC_8BIT_EN;          /* Enable 8-bit DAC mode */

    /* Disable blanking */
    dacCntl &= ~R128_DAC_BLANKING;

    /* Write DAC control register */
    OUTREG(_mmioBase + R128_DAC_CNTL, dacCntl);

    /* Initialize palette to identity mapping for 8-bit mode */
    for (int i = 0; i < 256; i++) {
        OUTREG(_mmioBase + R128_PALETTE_INDEX, i);
        OUTREG(_mmioBase + R128_PALETTE_DATA,
               (i << 16) | (i << 8) | i);  /* R=G=B for grayscale */
    }
}

- (unsigned int)ATI_BIOS_ABReturnValues
{
    /* Return BIOS AB return values structure */
    return _ATI_ASIC_ID;
}

- (void)ATI_ASICSetupValues
{
    /* Setup ASIC-specific values */
    _ATI_ASIC_ID = 0;
    _ATI_ASIC_TYPE = 0;
    _ATI_Bios_Offset = 0xC0000;
    _ATI_Bios_StackLength = 0;
}

- (void)ATI_ASICTypeValues
{
    /* Read and store ASIC type values from PCI config */
    if (_pciDevice) {
        IOPCIConfigSpace configSpace;
        [_pciDevice getConfigSpace:&configSpace];
        _ATI_ASIC_ID = configSpace.DeviceID;

        /* Determine ASIC type based on device ID */
        switch (_ATI_ASIC_ID) {
            case 0x4354:  // ATI Rage
            case 0x4754:  // ATI Rage II
            case 0x4755:  // ATI Rage II+
            case 0x4756:  // ATI Rage IIC
                _ATI_ASIC_TYPE = 3;  // Rage Pro family
                break;
            case 0x4C47:  // ATI Rage LT
            case 0x5C55:  // ATI Rage Mobility
                _ATI_ASIC_TYPE = 4;  // Mobile Rage
                break;
            default:
                _ATI_ASIC_TYPE = 0;
                break;
        }

        IOLog("%s: ASIC ID: 0x%04x, Type: %d\n",
              [self name], _ATI_ASIC_ID, _ATI_ASIC_TYPE);
    }
}

- (unsigned int)ATI_BIOS_Offset
{
    /* Return BIOS offset */
    return _ATI_Bios_Offset;
}

- (void)ATI_BIOS_StackLength
{
    /* Set BIOS stack length */
    _ATI_Bios_StackLength = 0x1000;  // 4KB stack
}

- (void)ATI_ReadConfigM
{
    /* Read configuration memory */
    if (_mmioBase) {
        volatile unsigned int *configStat = (volatile unsigned int *)(_mmioBase + ATI_CONFIG_STAT0);
        unsigned int stat = *configStat;
        /* Process configuration status */
    }
}

- (unsigned int)ATI_memSizeValues
{
    /* Return memory size values */
    return _ATI_memSizeValues;
}

- (void)ATI_modeUseRefreshRate
{
    /* Configure mode to use refresh rate */
    _ATI_modeUseRefreshRate = 1;
}

- (unsigned int)ATI_modeListCount_export
{
    /* Return mode list count */
    return _ATI_modeListCount;
}

@end
