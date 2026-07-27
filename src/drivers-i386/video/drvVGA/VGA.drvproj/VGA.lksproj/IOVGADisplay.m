/* Copyright (c) 1992 by NeXT Computer, Inc.
 * All rights reserved.
 *
 * IOVGADisplay.m -- the VGA kernel display driver class.
 *
 * This file, its (VESAMode) category and the nine C functions between them
 * are one translation unit in the reference (see divergences.md, "Where
 * Apple's translation-unit boundaries fall").  The C functions sit between
 * -_registerWithED and -hideCursor: because that is where the reference's
 * __text puts them -- C from 228 to 3227, Objective-C from 3228 -- and a
 * linker cannot produce that interleaving across object files.
 *
 * This file is also the one translation unit that includes
 * driverkit/i386/ioPorts.h, whose outb() / outw() / outl() each carry a
 * `static int xxx'.  That triple is the reference's _xxx.100 / .103 / .106,
 * and there is exactly one of it in the binary.
 *
 * Phase 3b Task 2 laid down the declarations, the statics and the constant
 * data; the bodies are stubs that Tasks 3 through 5 replace.
 */

#import "IOVGADisplayReloc.h"

#import <driverkit/i386/ioPorts.h>
#import <driverkit/i386/kernelDriver.h>

#import <driverkit/EventDriver.h>
#import <driverkit/IOConfigTable.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IODisplayPrivate.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

/*
 * File-scope state.
 *
 * The first seven have explicit initializers, which is what puts them in
 * __DATA,__data rather than __DATA,__bss (uninitialized static) or
 * __DATA,__common (uninitialized global); the reference has all seven in
 * __data at 24576 through 24603, in this order.  vesaMode's 0x6A is the
 * VESA 800x600 sixteen-colour mode, and is what the driver uses when the
 * config table names no "SVGA VESA BIOS Mode".
 *
 * The five console globals are external, not static: the kernel's
 * VGAConsole.c links against them.  colr_mode starts at 1 (colour), the
 * four plane/segment shadows at 0.
 */
static int	svga_bios_mode = 0;
static int	vesaMode = 0x6A;

int		colr_mode = 1;
int		curr_read_plane = 0;
int		curr_write_plane = 0;
int		curr_read_segment = 0;
int		curr_write_segment = 0;

/*
 * Uninitialized, so these land in __DATA,__bss.  nameBuf is 20 bytes in
 * the reference and holds "VGADisplay%d".
 */
static id		bios;
static unsigned int	nextVGAUnit;
static char		nameBuf[20];

@implementation IOVGADisplay

/* Finding 1. */
- (IOReturn)_registerWithED
{
    return IO_R_SUCCESS;
}

/*
 * The nine C functions.  SetET4000Brightness and find_parameter are
 * static; the other eight are exported for the kernel console.
 */

/* Finding 2. */
static void
SetET4000Brightness(int level)
{
}

/* Finding 3. */
void
select_read_segment(char seg)
{
}

/* Finding 4. */
void
select_write_segment(char seg)
{
}

/* Finding 5. */
void
select_read_plane(char plane)
{
}

/* Finding 6. */
void
select_write_plane(char plane)
{
}

/* Finding 7. */
void
vga_read_bpp4planar_to_bpp2packed32(unsigned short *fb, unsigned int *dst)
{
}

/*
 * Finding 8.  Note the frame buffer is the first argument of the reader
 * and the second of the writer; do not tidy that into a consistent order.
 */
void
vga_write_bpp2packed32_to_bpp4planar(unsigned int *src, unsigned short *fb)
{
}

/* Finding 9. */
void
VGADisplayCursor(IODisplayInfo *di, VGAShmem_t *shmem)
{
    static unsigned int	vramBuf[2];		/* _vramBuf.125 */
}

/* Finding 10. */
void
VGARemoveCursor(IODisplayInfo *di, VGAShmem_t *shmem)
{
    /*
     * _mask_array.128, 17 entries of 4 bytes at __data 24604:
     * mask_array[i] == (unsigned int)(0xFFFFFFFF << 2*i), terminating at
     * 0 for i == 16.  Two bits per pixel, which is why the index is a
     * pixel count and the shift is 2*i.  The 92 bytes of __data that
     * follow are emu486.s's state block, not part of this array.
     */
    static unsigned int	mask_array[17] = {	/* _mask_array.128 */
	0xFFFFFFFF, 0xFFFFFFFC, 0xFFFFFFF0, 0xFFFFFFC0,
	0xFFFFFF00, 0xFFFFFC00, 0xFFFFF000, 0xFFFFC000,
	0xFFFF0000, 0xFFFC0000, 0xFFF00000, 0xFFC00000,
	0xFF000000, 0xFC000000, 0xF0000000, 0xC0000000,
	0x00000000
    };
    static unsigned int	vramBuf[2];		/* _vramBuf.129 */
}

/* Finding 11. */
- hideCursor:(int)token
{
    return self;
}

/* Finding 12. */
- moveCursor:(Point *)cursorLoc frame:(int)frame token:(int)t
{
    return self;
}

/* Finding 13. */
- showCursor:(Point *)cursorLoc frame:(int)frame token:(int)t
{
    return self;
}

/* Finding 14. */
- (char *)generateNameAndUnit:(unsigned int *)unit
{
    return nameBuf;
}

/*
 * Finding 15.  A stub in the reference too: the frame buffer is not
 * mapped through this path.
 */
- (vm_offset_t)map
{
    return 0;
}

/* Finding 16. */
- (void)unmap
{
}

/* Finding 17.  Returns YES unconditionally in the reference. */
+ (BOOL)probe:deviceDescription
{
    return YES;
}

/* Finding 18. */
- free
{
    return [super free];
}

/* Finding 19. */
- initFromDeviceDescription:deviceDescription
{
    return self;
}

/* Finding 20. */
- setBrightness:(int)level token:(int)t
{
    return self;
}

/* Finding 21. */
- (IOReturn)getIntValues	: (unsigned *)parameterArray
		   forParameter	: (IOParameterName)parameterName
			  count	: (unsigned *)count
{
    return [super getIntValues:parameterArray forParameter:parameterName
			 count:count];
}

/* Finding 22. */
- (IOReturn)setIntValues	: (unsigned *)parameterArray
		   forParameter	: (IOParameterName)parameterName
			  count	: (unsigned)count
{
    return [super setIntValues:parameterArray forParameter:parameterName
			 count:count];
}

/* Finding 23. */
- (IOConsoleInfo *)allocateConsoleInfo
{
    return 0;
}

@end

@implementation IOVGADisplay (VESAMode)

/* Finding 24. */
- (void)enterSVGAMode:(unsigned int)mode
{
}

/* Finding 25. */
- (int)int10:(emu486regs_t *)regs
{
    /*
     * _ports.168 at __TEXT,__const 18920 is {start = 0, size = 0x10000}:
     * every I/O port permitted, prepended to the device's own port
     * ranges.  const-qualified, which is what puts it in __const.
     */
    static const IORange ports = { 0, 0x10000 };

    return 0;
}

/* Finding 26. */
static char *
find_parameter(const char *key, char *s)
{
    return 0;
}

/*
 * Finding 27.  Dead in the reference: finding 19 consults it only in the
 * branch that has just set svga_bios_mode to 0.
 */
- (BOOL)didBootWithDefaultConfig
{
    return NO;
}

@end
