/*
 * IOVGADisplay.h
 * VGA Display Driver Header
 *
 * Generic VGA display driver for VESA modes
 */

#import <driverkit/IOFrameBufferDisplay.h>
#import <driverkit/IODevice.h>

// Forward declarations
@class vidBIOS;

// VGA memory and I/O port definitions
#define VGA_MEMORY_BASE     0xA0000
#define VGA_MEMORY_SIZE     0x20000  // 128KB
#define VGA_IO_BASE         0x3B0
#define VGA_IO_SIZE         0x30

@interface IOVGADisplay : IOFrameBufferDisplay
{
    // Memory ranges
    IORange vgaMemRange;
    void *mappedVGAMem;

    // Display state
    unsigned int currentWidth;
    unsigned int currentHeight;
    unsigned int currentBPP;
    unsigned int currentRefresh;

    // Framebuffer
    unsigned char *framebuffer;
    unsigned int framebufferSize;

    // Console info
    void *consoleInfo;

    // Hardware cursor state
    BOOL cursorVisible;
    int cursorX;
    int cursorY;

    // BIOS emulator (for SVGA modes)
    id bios;
}

// Standard driver methods
+ (BOOL)probe:(IODeviceDescription *)devDesc;
- initFromDeviceDescription:(IODeviceDescription *)devDesc;
- free;

// Memory management
- (IOReturn)map;
- (void)unmap;

// Console support
- (void *)allocateConsoleInfo;
- (const char *)generateNameAndUnit:(unsigned int *)unit;

// Parameter access
- (IOReturn)getIntValues:(unsigned int *)values
              forParameter:(IOParameterName)parameterName
                     count:(unsigned int *)count;

- (IOReturn)setIntValues:(unsigned int *)values
              forParameter:(IOParameterName)parameterName
                     count:(unsigned int)count;

// Cursor management
- (void)hideCursor:(int)token;
- (void)showCursor:(IOGPoint *)cursorLoc
             frame:(IOGBounds *)bounds
             token:(int)token;
- (void)moveCursor:(IOGPoint *)cursorLoc
             frame:(IOGBounds *)bounds
             token:(int)token;

// Display control
- (void)setBrightness:(int)level token:(int)token;

// Internal methods
- (IOReturn)_registerWithED;

@end

// Category: VESA Mode support
@interface IOVGADisplay(VESAMode)

- (BOOL)_didBootWithDefaultConfig;
- (IOReturn)_enterSVGAMode:(unsigned int)mode;
- (int)_int10:(void *)regs;

@end

// Global variables (defined in IOVGADisplay.m)
extern char svga_bios_mode;
extern unsigned int vesaMode;
extern unsigned int colr_mode;
extern unsigned int curr_read_plane;
extern unsigned int curr_write_plane;
extern unsigned int curr_read_segment;
extern unsigned int curr_write_segment;

// C utility functions (defined in vidBIOS.m)
unsigned int _emu486(unsigned char *base_ptr, unsigned int *in_regs, unsigned int *out_regs,
                     unsigned int param4, unsigned int param5, unsigned int param6);
void _select_read_plane(unsigned char plane);
void _select_read_segment(char segment);
void _select_write_plane(unsigned char plane);
void _select_write_segment(unsigned char segment);
void _vga_read_bpp4planar_to_bpp2packed32(unsigned short *src, unsigned int *dst);
void _vga_write_bpp2packed32_to_bpp4planar(unsigned int *src, unsigned short *dst);
void _VGADisplayCursor(int *displayInfo, int *shmem);
void _VGARemoveCursor(int *displayInfo, int shmem_ptr);
void *_find_parameter(const char *paramName, const char *searchString);
void _SetET4000Brightness(int level);

// Note: EMU486 helper functions (emu486_*) are declared as static inline
// in vidBIOS.m and are not exposed in the public interface
