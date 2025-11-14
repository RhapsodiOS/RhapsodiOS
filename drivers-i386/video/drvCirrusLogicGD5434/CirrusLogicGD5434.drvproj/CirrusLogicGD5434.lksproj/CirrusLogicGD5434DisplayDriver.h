/*
 * CirrusLogicGD5434DisplayDriver.h
 * Cirrus Logic GD5434 Display Driver
 */

#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/IODevice.h>

// GD5434 PCI IDs
#define CIRRUS_VENDOR_ID    0x1013
#define GD5434_DEVICE_ID    0x00A8

// Memory ranges
#define VGA_MEMORY_BASE     0xa0000
#define VGA_MEMORY_SIZE     0x20000
#define EXT_MEMORY_BASE     0xc0000
#define EXT_MEMORY_SIZE     0x10000
#define FRAMEBUFFER_BASE    0x00000000
#define FRAMEBUFFER_SIZE    0x05000000

// I/O Ports
#define CRT_INDEX_PORT      0x3D4
#define CRT_DATA_PORT       0x3D5
#define SEQ_INDEX_PORT      0x3C4
#define SEQ_DATA_PORT       0x3C5
#define GFX_INDEX_PORT      0x3CE
#define GFX_DATA_PORT       0x3CF
#define ATTR_INDEX_PORT     0x3C0
#define ATTR_DATA_PORT      0x3C1
#define INPUT_STATUS_PORT   0x3DA
#define MISC_OUTPUT_PORT    0x3C2
#define DAC_WRITE_PORT      0x3C8
#define DAC_DATA_PORT       0x3C9

// CRTC Registers
#define CRTC_HTOTAL         0x00
#define CRTC_HDISP_END      0x01
#define CRTC_HBLANK_START   0x02
#define CRTC_HBLANK_END     0x03
#define CRTC_HSYNC_START    0x04
#define CRTC_HSYNC_END      0x05
#define CRTC_VTOTAL         0x06
#define CRTC_OVERFLOW       0x07
#define CRTC_PRESET_ROW     0x08
#define CRTC_MAX_SCAN       0x09
#define CRTC_VDISP_END      0x12
#define CRTC_OFFSET         0x13
#define CRTC_VBLANK_START   0x15
#define CRTC_VBLANK_END     0x16
#define CRTC_MODE_CTRL      0x17
#define CRTC_LINE_COMPARE   0x18

// Extended CRTC Registers (Cirrus specific)
#define CRTC_EXT_DISP       0x1B
#define CRTC_EXT_OFFSET     0x1D

// Sequencer Registers
#define SEQ_RESET           0x00
#define SEQ_CLOCKING_MODE   0x01
#define SEQ_MAP_MASK        0x02
#define SEQ_CHAR_MAP_SEL    0x03
#define SEQ_MEMORY_MODE     0x04
#define SEQ_EXT_MODE        0x07

// Graphics Registers
#define GFX_SET_RESET       0x00
#define GFX_ENABLE_SET_RST  0x01
#define GFX_COLOR_COMPARE   0x02
#define GFX_DATA_ROTATE     0x03
#define GFX_READ_MAP_SEL    0x04
#define GFX_MODE            0x05
#define GFX_MISC            0x06
#define GFX_COLOR_DONT_CARE 0x07
#define GFX_BIT_MASK        0x08

// Attribute Registers
#define ATTR_PALETTE_BASE   0x00
#define ATTR_MODE_CTRL      0x10
#define ATTR_OVERSCAN       0x11
#define ATTR_COLOR_PLANE_EN 0x12
#define ATTR_HORIZ_PEL_PAN  0x13
#define ATTR_COLOR_SELECT   0x14

// Display modes
typedef struct {
    int width;
    int height;
    int bitsPerPixel;
    int refreshRate;
    const char *name;
} DisplayMode;

@interface CirrusLogicGD5434DisplayDriver : IOPCIDirectDevice
{
    IORange vgaMemRange;
    IORange extensionMemRange1;
    IORange extensionMemRange2;
    IORange portRange1;
    IORange portRange2;
    IORange portRange3;
    void *mappedVGAMem;
    void *mappedExtMem1;
    void *mappedExtMem2;

    int currentWidth;
    int currentHeight;
    int currentBPP;
    int currentRefresh;
    unsigned char *framebuffer;
    unsigned int framebufferSize;
}

// Class methods
+ (BOOL)probe:(IOPCIDeviceDescription *)devDesc;

// Instance methods
- (BOOL)initFromDeviceDescription:(IOPCIDeviceDescription *)devDesc;
- free;
- (IOReturn)getIntValues:(unsigned *)paramArray
             forParameter:(IOParameterName)parameterName
                    count:(unsigned *)count;
- (IOReturn)setIntValues:(unsigned *)paramArray
             forParameter:(IOParameterName)parameterName
                    count:(unsigned)count;

// Initialization
- (void)resetDevice;
- (void)initializeHardware;
- (void)setupPalette;

// VGA/SVGA methods
- (void)enterLinearMode;
- (void)revertToVGAMode;
- (void)setMode:(int)width height:(int)height bpp:(int)bpp refresh:(int)refresh;
- (void)clearScreen;
- (void)displayModes;

// Hardware access methods
- (void)writeRegister:(unsigned short)reg value:(unsigned char)val;
- (unsigned char)readRegister:(unsigned short)reg;
- (void)writeCRTC:(unsigned char)index value:(unsigned char)val;
- (unsigned char)readCRTC:(unsigned char)index;
- (void)writeSequencer:(unsigned char)index value:(unsigned char)val;
- (unsigned char)readSequencer:(unsigned char)index;
- (void)writeGraphics:(unsigned char)index value:(unsigned char)val;
- (unsigned char)readGraphics:(unsigned char)index;
- (void)writeAttribute:(unsigned char)index value:(unsigned char)val;
- (unsigned char)readAttribute:(unsigned char)index;

// Framebuffer operations
- (void)fillRect:(int)x y:(int)y width:(int)w height:(int)h color:(unsigned char)color;
- (void)drawPixel:(int)x y:(int)y color:(unsigned char)color;
- (unsigned char)getPixel:(int)x y:(int)y;
- (void)copyRect:(int)srcX srcY:(int)srcY destX:(int)destX destY:(int)destY
           width:(int)w height:(int)h;

@end
