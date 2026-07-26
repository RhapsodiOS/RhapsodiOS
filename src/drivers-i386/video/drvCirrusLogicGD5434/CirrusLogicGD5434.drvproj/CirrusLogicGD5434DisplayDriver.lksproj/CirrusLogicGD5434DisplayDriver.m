/*
 * CirrusLogicGD5434DisplayDriver.m
 * Cirrus Logic GD5434 Display Driver
 *
 * Based on Default.table configuration
 */

#import "CirrusLogicGD5434DisplayDriver.h"
#import <driverkit/i386/IOVGAShared.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <objc/List.h>
#import <mach/mach_interface.h>
#import <string.h>

@implementation CirrusLogicGD5434DisplayDriver

+ (BOOL)probe:(IOPCIDeviceDescription *)devDesc
{
    unsigned short vendorID, deviceID;

    if ([devDesc numMemoryRanges] < 1)
        return NO;

    vendorID = [devDesc vendorID];
    deviceID = [devDesc deviceID];

    // Cirrus Logic vendor ID: 0x1013
    // GD5434 device ID: 0x00A8
    if (vendorID == CIRRUS_VENDOR_ID && deviceID == GD5434_DEVICE_ID) {
        IOLog("CirrusLogicGD5434DisplayDriver: Found Cirrus Logic GD5434\n");
        return YES;
    }

    return NO;
}

- (BOOL)initFromDeviceDescription:(IOPCIDeviceDescription *)devDesc
{
    if (![super initFromDeviceDescription:devDesc])
        return NO;

    [self setDeviceKind:"CirrusLogicGD5434DisplayDriver"];
    [self setLocation:""];
    [self setName:"CirrusLogicGD5434DisplayDriver"];

    // Set up memory ranges from Default.table
    // VGA memory: 0xa0000-0xbffff (128KB)
    vgaMemRange.start = VGA_MEMORY_BASE;
    vgaMemRange.size = VGA_MEMORY_SIZE;

    // Extension memory 1: 0xc0000-0xcffff (64KB)
    extensionMemRange1.start = EXT_MEMORY_BASE;
    extensionMemRange1.size = EXT_MEMORY_SIZE;

    // Framebuffer memory: 0x00000000-0x04ffffff (80MB address space)
    extensionMemRange2.start = FRAMEBUFFER_BASE;
    extensionMemRange2.size = FRAMEBUFFER_SIZE;

    // I/O port ranges
    portRange1.start = 0x3b0;
    portRange1.size = 0x10;

    portRange2.start = 0x1b2;
    portRange2.size = 0x1;

    portRange3.start = 0x46e8;
    portRange3.size = 0x2;

    // Map memory ranges
    mappedVGAMem = [self mapMemoryRange:&vgaMemRange to:IO_CacheOff];
    if (!mappedVGAMem) {
        IOLog("CirrusLogicGD5434DisplayDriver: Failed to map VGA memory\n");
        return NO;
    }

    mappedExtMem1 = [self mapMemoryRange:&extensionMemRange1 to:IO_CacheOff];
    mappedExtMem2 = [self mapMemoryRange:&extensionMemRange2 to:IO_CacheOff];

    // Initialize current mode settings
    currentWidth = 800;
    currentHeight = 600;
    currentBPP = 8;
    currentRefresh = 60;
    framebuffer = (unsigned char *)mappedVGAMem;
    framebufferSize = currentWidth * currentHeight;

    // Initialize hardware
    [self resetDevice];
    [self initializeHardware];
    [self setupPalette];
    [self setMode:800 height:600 bpp:8 refresh:60];

    IOLog("CirrusLogicGD5434DisplayDriver: Initialized successfully\n");
    IOLog("  VGA Memory mapped at: %p\n", mappedVGAMem);
    IOLog("  Display Mode: %dx%d @ %dHz, %d-bit color\n",
          currentWidth, currentHeight, currentRefresh, currentBPP);

    return YES;
}

- free
{
    if (mappedVGAMem)
        [self unmapMemoryRange:&vgaMemRange from:mappedVGAMem];
    if (mappedExtMem1)
        [self unmapMemoryRange:&extensionMemRange1 from:mappedExtMem1];
    if (mappedExtMem2)
        [self unmapMemoryRange:&extensionMemRange2 from:mappedExtMem2];

    return [super free];
}

- (IOReturn)getIntValues:(unsigned *)paramArray
             forParameter:(IOParameterName)parameterName
                    count:(unsigned *)count
{
    return [super getIntValues:paramArray forParameter:parameterName count:count];
}

- (IOReturn)setIntValues:(unsigned *)paramArray
             forParameter:(IOParameterName)parameterName
                    count:(unsigned)count
{
    return [super setIntValues:paramArray forParameter:parameterName count:count];
}

// Hardware register access methods

- (void)writeRegister:(unsigned short)reg value:(unsigned char)val
{
    outb(reg, val);
}

- (unsigned char)readRegister:(unsigned short)reg
{
    return inb(reg);
}

- (void)writeCRTC:(unsigned char)index value:(unsigned char)val
{
    outb(CRT_INDEX_PORT, index);
    outb(CRT_DATA_PORT, val);
}

- (unsigned char)readCRTC:(unsigned char)index
{
    outb(CRT_INDEX_PORT, index);
    return inb(CRT_DATA_PORT);
}

- (void)writeSequencer:(unsigned char)index value:(unsigned char)val
{
    outb(SEQ_INDEX_PORT, index);
    outb(SEQ_DATA_PORT, val);
}

- (unsigned char)readSequencer:(unsigned char)index
{
    outb(SEQ_INDEX_PORT, index);
    return inb(SEQ_DATA_PORT);
}

- (void)writeGraphics:(unsigned char)index value:(unsigned char)val
{
    outb(GFX_INDEX_PORT, index);
    outb(GFX_DATA_PORT, val);
}

- (unsigned char)readGraphics:(unsigned char)index
{
    outb(GFX_INDEX_PORT, index);
    return inb(GFX_DATA_PORT);
}

- (void)writeAttribute:(unsigned char)index value:(unsigned char)val
{
    inb(INPUT_STATUS_PORT); // Reset attribute flip-flop
    outb(ATTR_INDEX_PORT, index);
    outb(ATTR_INDEX_PORT, val);
}

- (unsigned char)readAttribute:(unsigned char)index
{
    inb(INPUT_STATUS_PORT); // Reset attribute flip-flop
    outb(ATTR_INDEX_PORT, index);
    return inb(ATTR_DATA_PORT);
}

// Initialization methods

- (void)resetDevice
{
    // Perform soft reset
    [self writeSequencer:SEQ_RESET value:0x01];
    IOSleep(10);
    [self writeSequencer:SEQ_RESET value:0x03];
    IOSleep(10);
}

- (void)initializeHardware
{
    // Unlock extended registers
    [self writeCRTC:0x11 value:[self readCRTC:0x11] & 0x7F];

    // Set up sequencer
    [self writeSequencer:SEQ_CLOCKING_MODE value:0x01];
    [self writeSequencer:SEQ_MAP_MASK value:0x0F];
    [self writeSequencer:SEQ_CHAR_MAP_SEL value:0x00];
    [self writeSequencer:SEQ_MEMORY_MODE value:0x0E];
    [self writeSequencer:SEQ_EXT_MODE value:0x00];

    // Set up graphics controller
    [self writeGraphics:GFX_SET_RESET value:0x00];
    [self writeGraphics:GFX_ENABLE_SET_RST value:0x00];
    [self writeGraphics:GFX_COLOR_COMPARE value:0x00];
    [self writeGraphics:GFX_DATA_ROTATE value:0x00];
    [self writeGraphics:GFX_READ_MAP_SEL value:0x00];
    [self writeGraphics:GFX_MODE value:0x40];
    [self writeGraphics:GFX_MISC value:0x05];
    [self writeGraphics:GFX_COLOR_DONT_CARE value:0x0F];
    [self writeGraphics:GFX_BIT_MASK value:0xFF];

    // Set up attribute controller
    int i;
    for (i = 0; i < 16; i++) {
        [self writeAttribute:i value:i];
    }
    [self writeAttribute:ATTR_MODE_CTRL value:0x41];
    [self writeAttribute:ATTR_OVERSCAN value:0x00];
    [self writeAttribute:ATTR_COLOR_PLANE_EN value:0x0F];
    [self writeAttribute:ATTR_HORIZ_PEL_PAN value:0x00];
    [self writeAttribute:ATTR_COLOR_SELECT value:0x00];

    // Enable video output
    inb(INPUT_STATUS_PORT);
    outb(ATTR_INDEX_PORT, 0x20);
}

- (void)setupPalette
{
    int i;

    // Set up default 256-color palette
    // Colors 0-15: Standard VGA colors
    unsigned char vgaPalette[16][3] = {
        {0x00, 0x00, 0x00}, // Black
        {0x00, 0x00, 0xAA}, // Blue
        {0x00, 0xAA, 0x00}, // Green
        {0x00, 0xAA, 0xAA}, // Cyan
        {0xAA, 0x00, 0x00}, // Red
        {0xAA, 0x00, 0xAA}, // Magenta
        {0xAA, 0x55, 0x00}, // Brown
        {0xAA, 0xAA, 0xAA}, // Light Gray
        {0x55, 0x55, 0x55}, // Dark Gray
        {0x55, 0x55, 0xFF}, // Light Blue
        {0x55, 0xFF, 0x55}, // Light Green
        {0x55, 0xFF, 0xFF}, // Light Cyan
        {0xFF, 0x55, 0x55}, // Light Red
        {0xFF, 0x55, 0xFF}, // Light Magenta
        {0xFF, 0xFF, 0x55}, // Yellow
        {0xFF, 0xFF, 0xFF}  // White
    };

    outb(DAC_WRITE_PORT, 0);
    for (i = 0; i < 16; i++) {
        outb(DAC_DATA_PORT, vgaPalette[i][0] >> 2);
        outb(DAC_DATA_PORT, vgaPalette[i][1] >> 2);
        outb(DAC_DATA_PORT, vgaPalette[i][2] >> 2);
    }

    // Colors 16-255: Grayscale and color ramp
    for (i = 16; i < 256; i++) {
        unsigned char r = (i * 263) >> 8;
        unsigned char g = (i * 263) >> 8;
        unsigned char b = (i * 263) >> 8;
        outb(DAC_DATA_PORT, r >> 2);
        outb(DAC_DATA_PORT, g >> 2);
        outb(DAC_DATA_PORT, b >> 2);
    }
}

// Display mode methods

- (void)enterLinearMode
{
    // Enable linear addressing mode
    [self writeCRTC:CRTC_EXT_DISP value:0x22]; // Extended Display Control
    [self writeSequencer:SEQ_EXT_MODE value:0x01]; // Extended Sequencer Mode
}

- (void)revertToVGAMode
{
    // Revert to standard VGA mode
    [self writeCRTC:CRTC_EXT_DISP value:0x02];
    [self writeSequencer:SEQ_EXT_MODE value:0x00];
}

- (void)setMode:(int)width height:(int)height bpp:(int)bpp refresh:(int)refresh
{
    // Currently only 800x600@60Hz 8bpp is supported
    if (width != 800 || height != 600 || bpp != 8) {
        IOLog("CirrusLogicGD5434DisplayDriver: Unsupported mode %dx%dx%d\n",
              width, height, bpp);
        return;
    }

    currentWidth = width;
    currentHeight = height;
    currentBPP = bpp;
    currentRefresh = refresh;
    framebufferSize = width * height;

    // Reset sequencer
    [self writeSequencer:SEQ_RESET value:0x01];

    // Set misc output register
    outb(MISC_OUTPUT_PORT, 0xE3);

    // Unlock CRTC registers
    [self writeCRTC:0x11 value:[self readCRTC:0x11] & 0x7F];

    // 800x600 @ 60Hz timing
    [self writeCRTC:CRTC_HTOTAL value:0x7F];        // Horizontal total
    [self writeCRTC:CRTC_HDISP_END value:0x63];     // Horizontal display end
    [self writeCRTC:CRTC_HBLANK_START value:0x64];  // Horizontal blank start
    [self writeCRTC:CRTC_HBLANK_END value:0x82];    // Horizontal blank end
    [self writeCRTC:CRTC_HSYNC_START value:0x6B];   // Horizontal sync start
    [self writeCRTC:CRTC_HSYNC_END value:0x1B];     // Horizontal sync end
    [self writeCRTC:CRTC_VTOTAL value:0x72];        // Vertical total
    [self writeCRTC:CRTC_OVERFLOW value:0xF0];      // Overflow
    [self writeCRTC:CRTC_PRESET_ROW value:0x00];    // Preset row scan
    [self writeCRTC:CRTC_MAX_SCAN value:0x60];      // Maximum scan line
    [self writeCRTC:CRTC_VDISP_END value:0x58];     // Vertical display end
    [self writeCRTC:CRTC_OFFSET value:0x64];        // Offset (pitch/2)
    [self writeCRTC:CRTC_VBLANK_START value:0x58];  // Vertical blank start
    [self writeCRTC:CRTC_VBLANK_END value:0x8C];    // Vertical blank end
    [self writeCRTC:CRTC_MODE_CTRL value:0xE3];     // Mode control
    [self writeCRTC:CRTC_LINE_COMPARE value:0xFF];  // Line compare

    // Set extended CRTC offset
    [self writeCRTC:CRTC_EXT_OFFSET value:0x00];

    // Set up sequencer for 8bpp mode
    [self writeSequencer:SEQ_CLOCKING_MODE value:0x01];
    [self writeSequencer:SEQ_MAP_MASK value:0xFF];
    [self writeSequencer:SEQ_MEMORY_MODE value:0x0E];

    // Set up graphics controller for linear mode
    [self writeGraphics:GFX_MODE value:0x40];
    [self writeGraphics:GFX_MISC value:0x05];

    // Set up attribute controller
    [self writeAttribute:ATTR_MODE_CTRL value:0x41];
    [self writeAttribute:ATTR_COLOR_PLANE_EN value:0x0F];

    // Enable linear mode
    [self enterLinearMode];

    // Restart sequencer
    [self writeSequencer:SEQ_RESET value:0x03];

    // Clear screen
    [self clearScreen];

    IOLog("CirrusLogicGD5434DisplayDriver: Mode set to %dx%d @ %dHz, %dbpp\n",
          width, height, refresh, bpp);
}

- (void)clearScreen
{
    if (framebuffer && framebufferSize > 0) {
        bzero(framebuffer, framebufferSize);
    }
}

- (void)displayModes
{
    IOLog("CirrusLogicGD5434DisplayDriver: Available display modes:\n");
    IOLog("  800x600 @ 60Hz, 256 colors (8-bit RGB)\n");
}

// Framebuffer operations

- (void)fillRect:(int)x y:(int)y width:(int)w height:(int)h color:(unsigned char)color
{
    int i, j;

    if (!framebuffer || x < 0 || y < 0 ||
        x + w > currentWidth || y + h > currentHeight)
        return;

    for (j = y; j < y + h; j++) {
        unsigned char *line = framebuffer + (j * currentWidth) + x;
        for (i = 0; i < w; i++) {
            line[i] = color;
        }
    }
}

- (void)drawPixel:(int)x y:(int)y color:(unsigned char)color
{
    if (!framebuffer || x < 0 || y < 0 ||
        x >= currentWidth || y >= currentHeight)
        return;

    framebuffer[y * currentWidth + x] = color;
}

- (unsigned char)getPixel:(int)x y:(int)y
{
    if (!framebuffer || x < 0 || y < 0 ||
        x >= currentWidth || y >= currentHeight)
        return 0;

    return framebuffer[y * currentWidth + x];
}

- (void)copyRect:(int)srcX srcY:(int)srcY destX:(int)destX destY:(int)destY
           width:(int)w height:(int)h
{
    int j;

    if (!framebuffer || srcX < 0 || srcY < 0 || destX < 0 || destY < 0 ||
        srcX + w > currentWidth || srcY + h > currentHeight ||
        destX + w > currentWidth || destY + h > currentHeight)
        return;

    // Handle overlapping regions by copying in the right direction
    if (destY > srcY || (destY == srcY && destX > srcX)) {
        // Copy from bottom to top
        for (j = h - 1; j >= 0; j--) {
            unsigned char *srcLine = framebuffer + ((srcY + j) * currentWidth) + srcX;
            unsigned char *destLine = framebuffer + ((destY + j) * currentWidth) + destX;
            memmove(destLine, srcLine, w);
        }
    } else {
        // Copy from top to bottom
        for (j = 0; j < h; j++) {
            unsigned char *srcLine = framebuffer + ((srcY + j) * currentWidth) + srcX;
            unsigned char *destLine = framebuffer + ((destY + j) * currentWidth) + destX;
            memmove(destLine, srcLine, w);
        }
    }
}

@end
