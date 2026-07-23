/*
 * RivaFB.m -- NVIDIA Riva framebuffer display driver
 * Based on XFree86 nv driver and VMWareFB driver
 */

#import "RivaFB.h"
#import "riva_timing.h"
#include <stdio.h>

#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>

/* Mode table - all modes use 32bpp RGB:888/32 */
static const IODisplayInfo modeTable[] = {
    { 640, 480, 640, 2560, 60, 0, IO_24BitsPerPixel, IO_RGBColorSpace,
      "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, 0 },
    { 800, 600, 800, 3200, 60, 0, IO_24BitsPerPixel, IO_RGBColorSpace,
      "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, 0 },
    { 1024, 768, 1024, 4096, 60, 0, IO_24BitsPerPixel, IO_RGBColorSpace,
      "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, 0 },
    { 1152, 864, 1152, 4608, 60, 0, IO_24BitsPerPixel, IO_RGBColorSpace,
      "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, 0 },
    { 1280, 1024, 1280, 5120, 60, 0, IO_24BitsPerPixel, IO_RGBColorSpace,
      "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, 0 },
    { 1600, 1200, 1600, 6400, 60, 0, IO_24BitsPerPixel, IO_RGBColorSpace,
      "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, 0 }
};

#define modeTableCount (sizeof(modeTable) / sizeof(IODisplayInfo))
#define defaultMode 2  /* 1024x768 */

@implementation RivaFB

/*
 * Probe for NVIDIA Riva hardware
 */
+ (BOOL)probe: deviceDescription
{
    IOPCIConfigSpace pciConfig;
    CARD32 physicalMemoryBase;
    CARD32 physicalMemorySize;
    CARD32 physicalRegBase;
    CARD32 physicalRegSize;
    int numRanges;
    IORange *oldRange, newRange[3];
    RivaFB *newDriver;
    CARD32 *tempRegBase;
    RivaChipType chipType;
    CARD32 boot0;

    RivaLog("RivaFB: Probing for NVIDIA Riva hardware\n");

    /* Get PCI configuration */
    if ([deviceDescription getPCIConfigSpace: &pciConfig] != IO_R_SUCCESS) {
        RivaLog("RivaFB: Failed to get PCI config space\n");
        return NO;
    }

    /* Verify vendor and device ID */
    if (pciConfig.VendorID != PCI_VENDOR_ID_NVIDIA) {
        RivaLog("RivaFB: Not an NVIDIA device (vendor 0x%04x)\n",
                pciConfig.VendorID);
        return NO;
    }

    RivaLog("RivaFB: Found NVIDIA device 0x%04x:0x%04x\n",
            pciConfig.VendorID, pciConfig.DeviceID);

    /* Get framebuffer base from BAR0 */
    physicalMemoryBase = pciConfig.BaseAddress[0] & 0xFFFFFFF0;
    /* Framebuffer size - we'll determine actual size from registers */
    physicalMemorySize = 32 * 1024 * 1024;  /* Default to 32MB, will adjust */

    /* Get register base from BAR1 */
    physicalRegBase = pciConfig.BaseAddress[1] & 0xFFFFFFF0;
    physicalRegSize = 16 * 1024 * 1024;  /* 16MB register space */

    RivaLog("RivaFB: Framebuffer at 0x%08x\n", physicalMemoryBase);
    RivaLog("RivaFB: Registers at 0x%08x\n", physicalRegBase);

    /* Map registers temporarily to detect chip and memory size */
    if (IOMapPhysicalIntoIOTask(physicalRegBase, physicalRegSize,
                                 (vm_address_t *)&tempRegBase) != IO_R_SUCCESS) {
        RivaLog("RivaFB: Failed to map registers for detection\n");
        return NO;
    }

    /* Detect chip type */
    chipType = rivaGetChipType(tempRegBase);
    RivaLog("RivaFB: Detected chip type: %d\n", chipType);

    /* Get actual memory size */
    physicalMemorySize = rivaGetMemorySize(tempRegBase, chipType);
    RivaLog("RivaFB: Detected %d MB of video memory\n",
            physicalMemorySize / (1024 * 1024));

    /* Unmap temporary register mapping */
    IOUnmapPhysicalFromIOTask((vm_address_t)tempRegBase, physicalRegSize);

    /* Set up memory ranges in device description */
    oldRange = [deviceDescription memoryRangeList];
    numRanges = [deviceDescription numMemoryRanges];

    if (numRanges < 3) {
        RivaLog("RivaFB: Insufficient memory ranges: %d\n", numRanges);
        return NO;
    }

    /* Copy existing ranges */
    for (int i = 0; i < numRanges; i++) {
        newRange[i] = oldRange[i];
    }

    /* Set framebuffer range */
    newRange[FB_MEMRANGE].start = physicalMemoryBase;
    newRange[FB_MEMRANGE].size = physicalMemorySize;

    /* Set register range */
    newRange[REG_MEMRANGE].start = physicalRegBase;
    newRange[REG_MEMRANGE].size = physicalRegSize;

    if ([deviceDescription setMemoryRangeList:newRange num:numRanges] != 0) {
        RivaLog("RivaFB: Failed to set memory ranges\n");
        return NO;
    }

    /* Create and initialize driver instance */
    newDriver = [[self alloc] initFromDeviceDescription: deviceDescription];

    if (newDriver == nil) {
        RivaLog("RivaFB: Failed to initialize driver instance\n");
        return NO;
    }

    [newDriver setDeviceKind: "Linear Framebuffer"];
    [newDriver registerDevice];

    RivaLog("RivaFB: Probe successful, display ready\n");
    return YES;
}

/*
 * Initialize driver instance
 */
- initFromDeviceDescription: deviceDescription
{
    IODisplayInfo *displayInfo;
    const IORange *range;
    BOOL validModes[modeTableCount];
    int loop;
    CARD32 boot0;

    RivaLog("RivaFB: Initializing from device description\n");

    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return [super free];
    }

    /* Get memory ranges */
    range = [deviceDescription memoryRangeList];

    /* Map register space */
    if ([self mapMemoryRange: REG_MEMRANGE
                          to: (vm_address_t *)&regBase
                   findSpace: YES
                       cache: IO_CacheOff] != IO_R_SUCCESS) {
        RivaLog("RivaFB: Failed to map register space\n");
        return [super free];
    }

    /* Initialize hardware state structure */
    rivaHW.regBase = regBase;
    rivaHW.chipType = rivaGetChipType(regBase);
    rivaHW.fbSize = rivaGetMemorySize(regBase, rivaHW.chipType);

    /* Get chip revision */
    boot0 = [self readReg: NV_PMC_OFFSET + NV_PMC_BOOT_0];
    rivaHW.chipRevision = (boot0 & NV_BOOT0_CHIP_REV_MASK) >> 16;
    rivaHW.architecture = rivaHW.chipType;

    RivaLog("RivaFB: Chip type: %d, revision: 0x%02x\n",
            rivaHW.chipType, rivaHW.chipRevision);
    RivaLog("RivaFB: Video memory: %d MB\n", rivaHW.fbSize / (1024 * 1024));

    /* Validate modes based on available memory */
    for (loop = 0; loop < modeTableCount; loop++) {
        int requiredMemory = modeTable[loop].height * modeTable[loop].rowBytes;
        if (requiredMemory <= rivaHW.fbSize) {
            validModes[loop] = YES;
        } else {
            validModes[loop] = NO;
            RivaLog("RivaFB: Mode %dx%d requires %d bytes, only %d available\n",
                    modeTable[loop].width, modeTable[loop].height,
                    requiredMemory, rivaHW.fbSize);
        }
    }

    /* Select display mode */
    selectedMode = [self selectMode:modeTable count:modeTableCount valid:validModes];

    if (selectedMode < 0) {
        RivaLog("RivaFB: No suitable display mode found, using default\n");
        selectedMode = defaultMode;
        if (!validModes[selectedMode]) {
            RivaLog("RivaFB: Even default mode not available!\n");
            return [super free];
        }
    }

    RivaLog("RivaFB: Selected mode: %dx%d\n",
            modeTable[selectedMode].width, modeTable[selectedMode].height);

    /* Get display info structure */
    displayInfo = [self displayInfo];
    *displayInfo = modeTable[selectedMode];

    /* Map framebuffer */
    if ([self mapMemoryRange: FB_MEMRANGE
                          to: (vm_address_t *)&(displayInfo->frameBuffer)
                   findSpace: YES
                       cache: IO_DISPLAY_CACHE_WRITETHROUGH] != IO_R_SUCCESS) {
        RivaLog("RivaFB: Failed to map framebuffer\n");
        return [super free];
    }

    if (displayInfo->frameBuffer == 0) {
        RivaLog("RivaFB: Framebuffer mapping returned NULL\n");
        return [super free];
    }

    rivaHW.fbBase = (CARD32 *)displayInfo->frameBuffer;

    RivaLog("RivaFB: Framebuffer mapped at %p\n", displayInfo->frameBuffer);
    [self logInfo];

    /* Initialize hardware cursor */
    [self initCursor];

    return self;
}

/*
 * Enter linear framebuffer mode
 */
- (void)enterLinearMode
{
    IODisplayInfo *displayInfo = [self displayInfo];
    int width = displayInfo->width;
    int height = displayInfo->height;
    int bpp = 32;  /* Always 32bpp */
    int pitch = displayInfo->rowBytes;
    RivaModeTimingRec timing;

    RivaLog("RivaFB: Entering linear mode %dx%d @ %dbpp\n", width, height, bpp);

    /* Calculate proper CRTC timings for this mode */
    rivaCalculateTimings(width, height, 60, &timing);

    /* Unlock extended registers */
    rivaLockUnlockExtended(0);

    /* Disable display while we configure */
    [self writeVGA: VGA_CRTC_INDEX value: 0x11];
    [self writeVGA: VGA_CRTC_DATA value: 0x00];

    /* Set misc output register for color mode */
    [self writeVGA: VGA_MISC_WRITE value: 0x23];

    /* Program sequencer */
    [self writeVGA: VGA_SEQ_INDEX value: 0x00];
    [self writeVGA: VGA_SEQ_DATA value: 0x03];  /* Synchronous reset */
    [self writeVGA: VGA_SEQ_INDEX value: 0x01];
    [self writeVGA: VGA_SEQ_DATA value: 0x01];  /* Clocking mode */
    [self writeVGA: VGA_SEQ_INDEX value: 0x02];
    [self writeVGA: VGA_SEQ_DATA value: 0x0F];  /* Map mask */
    [self writeVGA: VGA_SEQ_INDEX value: 0x03];
    [self writeVGA: VGA_SEQ_DATA value: 0x00];  /* Character map select */
    [self writeVGA: VGA_SEQ_INDEX value: 0x04];
    [self writeVGA: VGA_SEQ_DATA value: 0x0E];  /* Memory mode */
    [self writeVGA: VGA_SEQ_INDEX value: 0x00];
    [self writeVGA: VGA_SEQ_DATA value: 0x03];  /* Clear reset */

    /* Program PLL for pixel clock */
    rivaProgramVPLL(regBase, timing.pixelClock, rivaHW.chipType);

    /* Program CRTC with calculated timings */
    rivaProgramCRTC(regBase, &timing, pitch, bpp);

    /* Program graphics controller */
    [self writeVGA: VGA_GFX_INDEX value: 0x05];
    [self writeVGA: VGA_GFX_DATA value: 0x40];   /* Graphics mode */
    [self writeVGA: VGA_GFX_INDEX value: 0x06];
    [self writeVGA: VGA_GFX_DATA value: 0x05];   /* Memory map select */

    /* Program attribute controller */
    (void)[self readVGA: VGA_IS1_RC];  /* Reset flip-flop */
    [self writeVGA: VGA_ATTR_INDEX value: 0x10];
    [self writeVGA: VGA_ATTR_DATA_W value: 0x01];  /* Graphics mode */
    [self writeVGA: VGA_ATTR_INDEX value: 0x20];   /* Enable display */

    /* Program PRAMDAC for direct color mode */
    CARD32 general = [self readReg: NV_PRAMDAC_OFFSET + NV_PRAMDAC_GENERAL_CONTROL];
    general &= ~NV_PRAMDAC_GENERAL_CONTROL_VGA_STATE;
    general |= NV_PRAMDAC_GENERAL_CONTROL_PIXMIX_ON;
    [self writeReg: NV_PRAMDAC_OFFSET + NV_PRAMDAC_GENERAL_CONTROL value: general];

    /* Set framebuffer start address to 0 */
    [self writeReg: NV_PCRTC_OFFSET + NV_PCRTC_START value: 0];

    /* Clear framebuffer */
    int fbWords = (height * pitch) / 4;
    for (int i = 0; i < fbWords; i++) {
        rivaHW.fbBase[i] = 0;
    }

    RivaLog("RivaFB: Linear mode enabled with proper VESA timings\n");
}

/*
 * Revert to VGA text mode
 */
- (void)revertToVGAMode
{
    RivaLog("RivaFB: Reverting to VGA mode\n");

    /* Restore VGA state */
    CARD32 general = [self readReg: NV_PRAMDAC_OFFSET + NV_PRAMDAC_GENERAL_CONTROL];
    general |= NV_PRAMDAC_GENERAL_CONTROL_VGA_STATE;
    [self writeReg: NV_PRAMDAC_OFFSET + NV_PRAMDAC_GENERAL_CONTROL value: general];

    /* Lock extended registers */
    rivaLockUnlockExtended(1);

    [super revertToVGAMode];
}

@end
