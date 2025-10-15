/*
 * Copyright (c) 1998 Apple Computer, Inc. All rights reserved.
 *
 * ATIMach64DisplayDriver.m - ATI Mach64 Display Driver Implementation
 *
 * HISTORY
 * 28 Mar 98    Created.
 */

#define KERNEL_PRIVATE 1
#define DRIVER_PRIVATE 1

#import "ATIMach64DisplayDriver.h"
#import "ATIMach64Regs.h"
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
static const IODisplayInfo _ATIMach64Modes[] = {
    {
        768,                            // height
        1024,                           // width
        1024,                           // totalWidth
        1024,                           // rowBytes
        60,                             // refreshRate
        IO_8BitsPerPixel,               // bitsPerPixel
        IO_RGBColorSpace,               // colorSpace
        "PPPPPPPPPPPPPPPP",             // pixelEncoding
        0,                              // flags
        0                               // reserved
    }
};

#define NUM_ATI_MODES (sizeof(_ATIMach64Modes) / sizeof(IODisplayInfo))

@implementation ATIMach64DisplayDriver

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

    /* Check for various ATI Mach64 device IDs */
    switch (deviceID) {
        case 0x0268:  // ATI Rage XC
        case 0x0300:  // ATI Rage 128
        case 0x036e:  // ATI Rage 1
        case 0x04ee:  // ATI Rage 2
        case 0x0eec:  // ATI Mach64 GX
        case 0x12ec:  // ATI Mach64 GT
        case 0x16ec:  // ATI Mach64 VT
        case 0x1aec:  // ATI Mach64 VT4
        case 0x1eec:  // ATI Mach64 GT-B
        case 0x42ec:  // ATI Mach64 CT
        case 0x46ec:  // ATI Mach64 ET
        case 0x4aec:  // ATI Mach64 VT-B
        case 0x4eec:  // ATI Mach64 GT-C
        case 0x62ec:  // ATI Mach64 VT-C
        case 0x66ec:  // ATI Mach64 GT-D
        case 0x6aec:  // ATI Mach64 VT-D
        case 0x6eec:  // ATI Mach64 GT-E
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

    /* Map the framebuffer memory */
    mode = (IODisplayInfo *)&_ATIMach64Modes[0];

    ret = [self selectMode:_ATIMach64Modes count:NUM_ATI_MODES];
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
    unsigned int configStat0, memType;
    const char *memTypeName[] = {
        "DRAM", "EDO DRAM", "Pseudo-EDO", "SDRAM",
        "SGRAM", "WRAM", "SDRAM32", "Unknown"
    };

    if (_mmioBase) {
        /* Read CONFIG_STAT0 to determine memory type and size */
        configStat0 = INREG(_mmioBase, CONFIG_STAT0);
        memType = configStat0 & CFG_MEM_TYPE_T;

        /* Memory size detection for Mach64 */
        /* The actual size must be probed or read from BIOS */
        /* Common sizes: 2MB, 4MB, 8MB */

        /* For now, default to 4MB for Mach64 */
        _memorySize = 4 * 1024 * 1024;

        IOLog("%s: Memory type: %s, Size: %d MB\n",
              [self name],
              memTypeName[memType < 7 ? memType : 7],
              _memorySize / (1024 * 1024));
    } else {
        /* Default to 4MB if we can't detect */
        _memorySize = 4 * 1024 * 1024;
    }

    /* Set RAMDAC speed - Mach64 typical speeds */
    _ramdacSpeed = 135000000;  // 135 MHz for most Mach64
}

- (void)setupRegisters
{
    unsigned int temp;

    if (!_mmioBase) return;

    /* Enable linear addressing mode via CRTC_EXT_CNTL */
    temp = INREG(_mmioBase, CRTC_EXT_CNTL);
    temp |= VGA_ATI_LINEAR;
    OUTREG(_mmioBase, CRTC_EXT_CNTL, temp);

    /* Enable CRTC - enable display and extended display */
    temp = INREG(_mmioBase, CRTC_GEN_CNTL);
    temp &= ~CRTC_HSYNC_DIS;
    temp &= ~CRTC_VSYNC_DIS;
    temp &= ~CRTC_DISPLAY_DIS;
    temp |= CRTC_EN;
    temp |= CRTC_EXT_DISP_EN;
    OUTREG(_mmioBase, CRTC_GEN_CNTL, temp);

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

/* ATI-specific BIOS and DAC functions */

- (void)ATI_ProgramDAC
{
    unsigned int dacCntl;
    int i;

    if (!_mmioBase) return;

    /* Program the DAC (Digital-to-Analog Converter) registers */
    /* Based on Mach64 driver DAC initialization */
    dacCntl = INREG(_mmioBase, DAC_CNTL);

    /* Clear bits we're going to set */
    dacCntl &= ~(DAC1_CLK_SEL | DAC_PALETTE_ACCESS_CNTL | DAC_8BIT_EN);

    /* Enable 8-bit DAC mode for 256 colors */
    dacCntl |= DAC_8BIT_EN;

    /* Write DAC control register */
    OUTREG(_mmioBase, DAC_CNTL, dacCntl);

    /* Initialize palette to identity mapping for 8-bit mode */
    /* Use VGA DAC registers for palette access */
    for (i = 0; i < 256; i++) {
        OUTREG8(_mmioBase, DAC_W_INDEX, i);  /* Set palette write index */
        OUTREG8(_mmioBase, DAC_DATA, i);     /* Red */
        OUTREG8(_mmioBase, DAC_DATA, i);     /* Green */
        OUTREG8(_mmioBase, DAC_DATA, i);     /* Blue (R=G=B for grayscale) */
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
            case 0x0268:  // Rage XC
            case 0x0300:  // Rage 128
                _ATI_ASIC_TYPE = 1;
                break;
            case 0x0eec:  // Mach64 GX
            case 0x12ec:  // Mach64 GT
                _ATI_ASIC_TYPE = 2;
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
    return 0xC0000;  // Standard VGA BIOS location
}

- (void)ATI_BIOS_StackLength
{
    /* Set BIOS stack length */
}

- (void)ATI_ReadConfigM
{
    /* Read configuration memory */
    if (_mmioBase) {
        unsigned int configStat0 = INREG(_mmioBase, CONFIG_STAT0);
        unsigned int configChipID = INREG(_mmioBase, CONFIG_CHIP_ID);

        /* Store chip configuration information */
        _ATI_ASIC_ID = configChipID & 0xFFFF;

        IOLog("%s: CONFIG_STAT0=0x%08x, CHIP_ID=0x%04x\n",
              [self name], configStat0, _ATI_ASIC_ID);
    }
}

- (unsigned int)ATI_memSizeValues
{
    /* Return memory size values */
    return _memorySize;
}

- (void)ATI_modeUseRefreshRate
{
    /* Configure mode to use refresh rate */
}

- (unsigned int)ATI_modeListCount
{
    /* Return mode list count */
    return NUM_ATI_MODES;
}

@end
