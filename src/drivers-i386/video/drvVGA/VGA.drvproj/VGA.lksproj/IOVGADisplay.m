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

#import <string.h>

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

/*
 * Finding 2.  The four grey levels of the console's black-and-white ramp,
 * scaled by level/64 and written straight at the DAC write-address and
 * data ports rather than through the vga_reg_out macros.  level is
 * unsigned: the reference divides by 64 with a plain `shr', which a signed
 * int would not permit, and -setBrightness:token: reaches this with an
 * unsigned `cmp ... 0x40 / jbe'.
 *
 * Each entry is written three times, once per DAC component.  The scaled
 * value is computed before the index is written -- that ordering is
 * visible in the reference, which even materialises the black entry's zero
 * into the value register separately from the zero it writes as the index.
 * gcc computes level*63 as (level<<6)-level and shares level*3 between the
 * 48/64 and the 30/64 entries; both fall out of the constants below.
 */
static void
SetET4000Brightness(unsigned int level)
{
    unsigned char	v;

    v = level * WHITE_PALETTE_VALUE / 64;
    outb(WRIT_COLR_PEL_WADR, WHITE_INDEX);
    outb(WRIT_COLR_PEL_DATA, v);
    outb(WRIT_COLR_PEL_DATA, v);
    outb(WRIT_COLR_PEL_DATA, v);

    v = level * LIGHT_GRAY_PALETTE_VALUE / 64;
    outb(WRIT_COLR_PEL_WADR, LIGHT_GRAY_INDEX);
    outb(WRIT_COLR_PEL_DATA, v);
    outb(WRIT_COLR_PEL_DATA, v);
    outb(WRIT_COLR_PEL_DATA, v);

    v = level * DARK_GRAY_PALETTE_VALUE / 64;
    outb(WRIT_COLR_PEL_WADR, DARK_GRAY_INDEX);
    outb(WRIT_COLR_PEL_DATA, v);
    outb(WRIT_COLR_PEL_DATA, v);
    outb(WRIT_COLR_PEL_DATA, v);

    v = level * BLACK_PALETTE_VALUE / 64;
    outb(WRIT_COLR_PEL_WADR, BLACK_INDEX);
    outb(WRIT_COLR_PEL_DATA, v);
    outb(WRIT_COLR_PEL_DATA, v);
    outb(WRIT_COLR_PEL_DATA, v);
}

/*
 * Finding 3.  The ET4000's Segment Select register carries the read
 * segment in its high nibble and the write segment in its low one, but
 * Video System Configuration 1 can lock both out, so that bit is tested
 * first.  CRT index reads go through the colour or the mono address port
 * depending on colr_mode; both read their data from 0x3D5, which is what
 * the checked-in header says and is why the compiler merges the two
 * branches after the index write.
 */
void
select_read_segment(char seg)
{
    char	tmp;

    if (colr_mode)
	vga_reg__in (COLR_CRT, CRT_TS_VS1, tmp)
    else
	vga_reg__in (MONO_CRT, CRT_TS_VS1, tmp)

    if (tmp & CRT_TS_SGL)
	return;

    tmp = inb(READ_COLR_GCR_SEGS);
    tmp &= GCR_TS_GWR;
    tmp |= seg << 4;
    outb(WRIT_COLR_GCR_SEGS, tmp);
    curr_read_segment = seg;
}

/*
 * Finding 4.  The same, on the other nibble.  Note the asymmetry the
 * reference has and we keep: the read side shifts seg without masking it,
 * the write side masks it without shifting.
 */
void
select_write_segment(char seg)
{
    char	tmp;

    if (colr_mode)
	vga_reg__in (COLR_CRT, CRT_TS_VS1, tmp)
    else
	vga_reg__in (MONO_CRT, CRT_TS_VS1, tmp)

    if (tmp & CRT_TS_SGL)
	return;

    tmp = inb(READ_COLR_GCR_SEGS);
    tmp &= GCR_TS_GRD;
    tmp |= seg & GCR_TS_GWR;
    outb(WRIT_COLR_GCR_SEGS, tmp);
    curr_write_segment = seg;
}

/*
 * Finding 5.  Graphics Controller index 4, Read Map Select: which plane
 * CPU reads come from, as a plane *number*.  Each macro re-reads and
 * re-writes the index register, which is why 0x3CE is touched twice.
 */
void
select_read_plane(char plane)
{
    char	tmp;

    vga_reg__in (COLR_GCR, GCR_AT_READ_MAPS, tmp)
    tmp &= ~GCR_AT_RMS;
    tmp |= plane & GCR_AT_RMS;
    vga_reg_out (COLR_GCR, GCR_AT_READ_MAPS, tmp)
    curr_read_plane = plane;
}

/*
 * Finding 6.  Sequencer index 2, Map Mask: which planes CPU writes reach,
 * as a one-hot *mask*.  The argument is still a plane number, so unlike
 * select_read_plane this one converts.  0xF0 is ~(EM3|EM2|EM1|EM0).
 */
void
select_write_plane(char plane)
{
    char	tmp, val;

    val = 1 << (plane & 3);
    vga_reg__in (COLR_SEQ, SEQ_AT_MPK, tmp)
    tmp &= 0xF0;
    tmp |= val;
    vga_reg_out (COLR_SEQ, SEQ_AT_MPK, tmp)
    curr_write_plane = plane;
}

/*
 * Finding 7.  Sixteen pixels of planes 1 and 0, complemented and
 * interleaved into one word of sixteen two-bit pixels, plane 0 supplying
 * the low bit of each pair.  A plane byte carries its leftmost pixel in
 * its high bit and the packed word carries pixel zero in its low pair, so
 * each byte's bits come out reversed; the complement is VGA's 1-is-set
 * convention against the NeXT two-bit grey ramp.
 *
 * The Window Server's read_bpp4planar_to_bpp2packed is the same transform
 * with the same shift table, returned rather than stored.
 */
void
vga_read_bpp4planar_to_bpp2packed32(unsigned short *fb, unsigned int *dst)
{
    unsigned int	c, hi, lo;

    select_read_plane(1);
    c = (unsigned short)~*fb;
    hi = ((c & 0x8000) <<  2) | ((c & 0x4000) <<  5) |
	 ((c & 0x2000) <<  8) | ((c & 0x1000) << 11) |
	 ((c & 0x0800) << 14) | ((c & 0x0400) << 17) |
	 ((c & 0x0200) << 20) | ((c & 0x0100) << 23) |
	 ((c & 0x0080) >>  6) | ((c & 0x0040) >>  3) |
	  (c & 0x0020)        | ((c & 0x0010) <<  3) |
	 ((c & 0x0008) <<  6) | ((c & 0x0004) <<  9) |
	 ((c & 0x0002) << 12) | ((c & 0x0001) << 15);

    select_read_plane(0);
    c = (unsigned short)~*fb;
    lo = ((c & 0x8000) <<  1) | ((c & 0x4000) <<  4) |
	 ((c & 0x2000) <<  7) | ((c & 0x1000) << 10) |
	 ((c & 0x0800) << 13) | ((c & 0x0400) << 16) |
	 ((c & 0x0200) << 19) | ((c & 0x0100) << 22) |
	 ((c & 0x0080) >>  7) | ((c & 0x0040) >>  4) |
	 ((c & 0x0020) >>  1) | ((c & 0x0010) <<  2) |
	 ((c & 0x0008) <<  5) | ((c & 0x0004) <<  8) |
	 ((c & 0x0002) << 11) | ((c & 0x0001) << 14);

    *dst = hi | lo;
}

/*
 * Finding 8.  The inverse of finding 7, gathering each sixteen-bit half of
 * the packed word into one plane byte.  The Window Server does this job
 * through its two 64K lookup tables; the kernel half spells the same eight
 * terms out inline, and the two are not to be harmonized.
 *
 * Note the frame buffer is the first argument of the reader and the second
 * of the writer -- read(fb, &packed) against write(&packed, fb).  The
 * cursor blitters depend on that; do not tidy it into a consistent order.
 */
void
vga_write_bpp2packed32_to_bpp4planar(unsigned int *src, unsigned short *fb)
{
    unsigned int	v, c;
    unsigned char	hi, lo;

    select_write_plane(1);
    v = *src;
    c = v & 0xAAAA;
    lo = ~(((c & 0x8000) >> 15) | ((c & 0x2000) >> 12) |
	   ((c & 0x0800) >>  9) | ((c & 0x0200) >>  6) |
	   ((c & 0x0080) >>  3) |  (c & 0x0020)        |
	   ((c & 0x0008) <<  3) | ((c & 0x0002) <<  6));
    c = (v >> 16) & 0xAAAA;
    hi = ~(((c & 0x8000) >> 15) | ((c & 0x2000) >> 12) |
	   ((c & 0x0800) >>  9) | ((c & 0x0200) >>  6) |
	   ((c & 0x0080) >>  3) |  (c & 0x0020)        |
	   ((c & 0x0008) <<  3) | ((c & 0x0002) <<  6));
    *fb = (hi << 8) | lo;

    select_write_plane(0);
    v = *src;
    c = v & 0x5555;
    lo = ~(((c & 0x4000) >> 14) | ((c & 0x1000) >> 11) |
	   ((c & 0x0400) >>  8) | ((c & 0x0100) >>  5) |
	   ((c & 0x0040) >>  2) | ((c & 0x0010) <<  1) |
	   ((c & 0x0004) <<  4) | ((c & 0x0001) <<  7));
    c = (v >> 16) & 0x5555;
    hi = ~(((c & 0x4000) >> 14) | ((c & 0x1000) >> 11) |
	   ((c & 0x0400) >>  8) | ((c & 0x0100) >>  5) |
	   ((c & 0x0040) >>  2) | ((c & 0x0010) <<  1) |
	   ((c & 0x0004) <<  4) | ((c & 0x0001) <<  7));
    *fb = (hi << 8) | lo;
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

/*
 * Finding 26.  Scan a boot string for a key and answer the first non-blank
 * character after it, which for a boot string is the `='.  strlen is the
 * inline repne scasb form -- there is no _strlen in the reference's symbol
 * table -- while strncmp is a real call.
 */
static char *
find_parameter(const char *key, char *s)
{
    int		len = strlen(key);
    int		c;

    while (*s) {
	if (strncmp(s, key, len) == 0) {
	    s += len;
	    while ((c = *s) != 0 && (c == ' ' || c == '\t'))
		s++;
	    return c ? s : 0;
	}
	s++;
    }
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
