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
#import <driverkit/i386/IOEISADeviceDescription.h>
#import <driverkit/i386/directDevice.h>

#import <driverkit/EventDriver.h>
#import <driverkit/IOConfigTable.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IODisplayPrivate.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

#import <machdep/i386/kernBootStruct.h>

#import <stdio.h>
#import <stdlib.h>
#import <string.h>

/*
 * Two things this file reaches out of the kernel for, neither of which any
 * driver header declares.
 *
 * kmId is the console device, defined by bsd/dev/i386/km.m; its
 * registerDisplay: is declared in bsd/dev/i386/kmDevice.h, which is not a
 * driver header, so the selector is declared here instead.  The category is
 * interface-only and emits no __OBJC,__category record.
 *
 * VGAAllocateConsole lives in bsd/dev/i386/VGAConsole.c and is what makes
 * the five console globals and the six select/convert functions below
 * external rather than static.
 */
extern id	kmId;

@interface Object (IOVGADisplayKM)
- (void)registerDisplay:newDisplay;
@end

extern IOConsoleInfo	*VGAAllocateConsole(IODisplayInfo *display);

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
 *
 * svga_bios_mode is a char, not an int: every one of the eight accesses to
 * it in the reference is byte-sized (`movb $1,_svga_bios_mode',
 * `cmpb $1,_svga_bios_mode'), which no compiler emits for an int.  It still
 * lands at __data 24576 with vesaMode at 24580, because the int that
 * follows it is 4-byte aligned.
 */
static char	svga_bios_mode = 0;
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

/*
 * Finding 1.  Ask the event driver for the shared region, check that it is
 * no larger than the VGAShmem_t this driver was compiled against, zero it,
 * and start the cursor hidden at depth 1.
 *
 * shmem_size is an int -- the protocol declares size:(int *) -- but the
 * comparison against sizeof(VGAShmem_t) is unsigned, because sizeof is
 * unsigned and the usual arithmetic conversions promote the int.  That is
 * the reference's `ja', with no cast written anywhere.  The literal it
 * compares against is 0x1448 = 5192, which is exactly what the checked-in
 * IOVGAShared.h computes.
 *
 * A region *smaller* than sizeof(VGAShmem_t) is accepted; only the memset
 * and the two stores below assume it is large enough for the bm12 arm the
 * driver actually uses.
 */
- (IOReturn)_registerWithED
{
    Bounds	 bounds;
    int		 shmem_size;
    int		 token;
    VGAShmem_t	*shmem;

    token = [[EventDriver instance] registerScreen:self bounds:&bounds
					     shmem:&priv size:&shmem_size];
    shmem = priv;

    if (token == -1)
	return IO_R_INVALID_ARG;

    if (shmem_size > sizeof(VGAShmem_t)) {
	IOLog("%s: shmem_size > sizeof (VGAShmem_t)(%d<>%d)\n",
	      [self name], shmem_size, sizeof(VGAShmem_t));
	[[EventDriver instance] unregisterScreen:token];
	return IO_R_INVALID_ARG;
    }

    memset(shmem, 0, shmem_size);
    shmem->cursorShow = 1;
    shmem->screenBounds = bounds;
    [self setToken:token];
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
select_read_segment(seg)
    char	seg;
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
select_write_segment(seg)
    char	seg;
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
select_read_plane(plane)
    char	plane;
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
select_write_plane(plane)
    char	plane;
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

/*
 * Finding 9.  Draw the cursor, saving the pixels it covers into
 * cursor.bw.save.  The Window Server's counterpart is VGADisplayCursorBlit
 * in VGAPSDriver.c and the two inner loops are the same code; the three
 * differences are all kernel-side needs.  This half saves and restores the
 * sequencer map mask and the plane and segment shadows around the loop, it
 * pushes the bank through select_write_segment / select_read_segment at
 * every 64K boundary, and it addresses the frame buffer as a literal
 * ET4000_PHYS_BASE where the bundle asks get_addr_range.
 *
 * Two quirks of Apple's, reproduced rather than corrected.
 *
 * The write registers are restored from the *read* shadows: this function
 * reads curr_read_segment and curr_read_plane into two locals each and
 * hands one copy to the read select and the other to the write select.
 * curr_write_segment and curr_write_plane are stored by the two write
 * selects and read nowhere in the binary.
 *
 * The bank divisor is 0x10000 / (width >> 4), a signed divide of the 64K
 * window by the row length in sixteen-pixel *words*, so 1638 at 640 wide.
 * The Window Server divides by the row length in bytes and gets 819, which
 * is the arithmetically right answer.  Both then step the same 80 byte row.
 * Because y never reaches 480 the bank is always 0 and the two selects in
 * the loop are dead at every geometry this driver supports, so the defect
 * is latent; see divergences.md findings 9 and 25.
 *
 * The cursor is sixteen pixels wide but lands at an arbitrary column, so
 * the blit snaps left to a sixteen pixel boundary and covers two 32 bit
 * words per scan line.  When the cursor happens to be aligned the second
 * word is untouched, but save still advances over it, which is why this
 * loop steps 32 words -- 128 bytes -- over a save[16] of 64.  The excess
 * runs past the end of the shared region.  The Window Server half does the
 * same, symmetrically, so the two stay in step.
 */
void
VGADisplayCursor(IODisplayInfo *di, VGAShmem_t *shmem)
{
    static unsigned int	 vramBuf[2];		/* _vramBuf.125 */

    Bounds		 scr;
    Bounds		 c;
    unsigned int	*img, *save, *msk;
    int			 leftOK, rightOK;
    unsigned int	 shift, rshift;
    unsigned short	*p;
    int			 words;
    unsigned int	 lines;
    int			 saveReadSegment, saveWriteSegment;
    int			 saveReadPlane, saveWritePlane;
    char		 mapMask;
    int			 rows, col, row, bank;
    unsigned int	 v;

    saveWriteSegment = curr_read_segment;
    saveReadSegment = curr_read_segment;
    saveWritePlane = curr_read_plane;
    saveReadPlane = curr_read_plane;
    vga_reg__in (COLR_SEQ, SEQ_AT_MPK, mapMask)

    c = shmem->cursorRect;
    scr = shmem->screenBounds;

    if (c.miny < scr.miny)
	c.miny = scr.miny;
    if (c.maxy > scr.maxy)
	c.maxy = scr.maxy;

    c.minx = scr.minx + ((shmem->cursorRect.minx - scr.minx) & ~15);
    c.maxx = c.minx + 2 * CURSORWIDTH;
    shmem->saveRect = c;

    shift = (shmem->cursorRect.minx & 15) * 2;	/* 2 bits per pixel */
    rshift = 32 - shift;

    img = shmem->cursor.bw.image[shmem->frame];
    msk = shmem->cursor.bw.mask[shmem->frame];
    save = shmem->cursor.bw.save;

    /* Skip the scan lines the vertical clip took off the top. */
    rows = c.miny - shmem->cursorRect.miny;
    img += rows;
    msk += rows;

    leftOK = c.minx >= scr.minx;
    rightOK = c.maxx <= scr.maxx;

    col = (c.minx - scr.minx) >> 4;
    words = di->width >> 4;			/* 16 pixel words per line */
    lines = 0x10000 / words;			/* lines per 64K window	   */

    row = c.miny - scr.miny;
    bank = row / lines;
    p = (unsigned short *)ET4000_PHYS_BASE;
    p += (row % lines) * words + col;
    select_write_segment(bank);
    select_read_segment(bank);

    for (; row < c.maxy - scr.miny; row++) {
	if (row % lines == 0) {
	    bank = row / lines;
	    select_write_segment(bank);
	    select_read_segment(bank);
	}
	if (leftOK) {
	    vga_read_bpp4planar_to_bpp2packed32(p, &vramBuf[0]);
	    v = vramBuf[0];
	    *save++ = v;
	    v = (v & ~(*msk << shift)) | (*img << shift);
	    vramBuf[0] = v;
	    vga_write_bpp2packed32_to_bpp4planar(&vramBuf[0], p);
	}
	if (rightOK) {
	    if (shift == 0)
		save++;				/* nothing spills over */
	    else {
		vga_read_bpp4planar_to_bpp2packed32(p + 1, &vramBuf[1]);
		v = vramBuf[1];
		*save++ = v;
		v = (v & ~(*msk >> rshift)) | (*img >> rshift);
		vramBuf[1] = v;
		vga_write_bpp2packed32_to_bpp4planar(&vramBuf[1], p + 1);
	    }
	}
	p += words;
	img++;
	msk++;
    }

    select_read_segment(saveReadSegment);
    select_write_segment(saveWriteSegment);
    select_read_plane(saveReadPlane);
    select_write_plane(saveWritePlane);
    vga_reg_out (COLR_SEQ, SEQ_AT_MPK, mapMask)
}

/*
 * Finding 10.  Erase the cursor, restoring from cursor.bw.save.
 *
 * saveRect says which two columns the draw pass covered and oldCursorRect
 * says where inside them the cursor actually was, so the two edge masks
 * restore exactly the pixels that were painted and leave the rest of the
 * word alone.  This blitter reads save and never writes it, so its stride
 * past the end of the array is an over-read where finding 9's is an
 * over-write.  Same save and restore discipline, same latent bank divisor.
 */
void
VGARemoveCursor(IODisplayInfo *di, VGAShmem_t *shmem)
{
    /*
     * _mask_array.128, 17 entries of 4 bytes at __data 24604:
     * mask_array[i] == (unsigned int)(0xFFFFFFFF << 2*i), terminating at
     * 0 for i == 16.  Two bits per pixel, which is why the index is a
     * pixel count and the shift is 2*i.  The 92 bytes of __data that
     * follow are emu486.s's state block, not part of this array.
     *
     * The Window Server carries a byte-identical copy as leftMask in its
     * own __TEXT,__const and subscripts it with the same two expressions.
     */
    static unsigned int	 mask_array[17] = {	/* _mask_array.128 */
	0xFFFFFFFF, 0xFFFFFFFC, 0xFFFFFFF0, 0xFFFFFFC0,
	0xFFFFFF00, 0xFFFFFC00, 0xFFFFF000, 0xFFFFC000,
	0xFFFF0000, 0xFFFC0000, 0xFFF00000, 0xFFC00000,
	0xFF000000, 0xFC000000, 0xF0000000, 0xC0000000,
	0x00000000
    };
    static unsigned int	 vramBuf[2];		/* _vramBuf.129 */

    int			 leftOK, rightOK;
    unsigned int	 maskL = 0, maskR = 0;
    Bounds		 scr;
    Bounds		 s;
    unsigned short	*p;
    int			 words;
    unsigned int	 lines;
    unsigned int	 shift;
    int			 saveReadSegment, saveWriteSegment;
    int			 saveReadPlane, saveWritePlane;
    char		 mapMask;
    unsigned int	*save;
    int			 col, row, bank;

    scr = shmem->screenBounds;
    s = shmem->saveRect;

    saveWriteSegment = curr_read_segment;
    saveReadSegment = curr_read_segment;
    saveWritePlane = curr_read_plane;
    saveReadPlane = curr_read_plane;
    vga_reg__in (COLR_SEQ, SEQ_AT_MPK, mapMask)

    col = (s.minx - scr.minx) >> 4;
    words = di->width >> 4;
    lines = 0x10000 / words;

    p = (unsigned short *)ET4000_PHYS_BASE;
    p += ((s.miny - scr.miny) % lines) * words + col;
    bank = (s.miny - scr.miny) / lines;
    select_write_segment(bank);
    select_read_segment(bank);

    shift = (shmem->cursorRect.minx & 15) * 2;
    save = shmem->cursor.bw.save;

    leftOK = s.minx >= scr.minx;
    if (leftOK)
	maskL = mask_array[shmem->oldCursorRect.minx - s.minx];
    rightOK = s.maxx <= scr.maxx;
    if (rightOK)
	maskR = ~mask_array[CURSORWIDTH -
			    (s.maxx - shmem->oldCursorRect.maxx)];

    for (row = s.miny - scr.miny; row < s.maxy - scr.miny; row++) {
	if (row % lines == 0) {
	    bank = row / lines;
	    select_write_segment(bank);
	    select_read_segment(bank);
	}
	if (leftOK) {
	    vga_read_bpp4planar_to_bpp2packed32(p, &vramBuf[0]);
	    vramBuf[0] = (vramBuf[0] & ~maskL) | (maskL & *save++);
	    vga_write_bpp2packed32_to_bpp4planar(&vramBuf[0], p);
	}
	if (rightOK) {
	    if (shift == 0)
		save++;
	    else {
		vga_read_bpp4planar_to_bpp2packed32(p + 1, &vramBuf[1]);
		vramBuf[1] = (vramBuf[1] & ~maskR) | (maskR & *save++);
		vga_write_bpp2packed32_to_bpp4planar(&vramBuf[1], p + 1);
	    }
	}
	p += words;
    }

    select_read_segment(saveReadSegment);
    select_write_segment(saveWriteSegment);
    select_read_plane(saveReadPlane);
    select_write_plane(saveWritePlane);
    vga_reg_out (COLR_SEQ, SEQ_AT_MPK, mapMask)
}

/*
 * Finding 11.  cursorShow is a hide depth, not a boolean, and the counter
 * moves whether or not the blit happens.
 *
 * This side takes ev_try_lock and, when the Window Server holds the
 * semaphore, returns self having done nothing at all: the kernel never
 * blocks on the Window Server and never queues the update.  ev_lock is not
 * imported by this binary, and the bundle's seven public cursor entries
 * take ev_lock and never ev_try_lock.  That asymmetry is the driver's
 * contention policy; do not substitute a blocking lock.
 *
 * token is accepted and never read, here and in the two below.
 */
- hideCursor:(int)token
{
    VGAShmem_t		*shmem;
    IODisplayInfo	*di;

    if (!ev_try_lock(&((VGAShmem_t *)priv)->cursorSema))
	return self;

    di = [self displayInfo];
    shmem = priv;
    if (shmem->cursorShow++ == 0)
	VGARemoveCursor(di, shmem);

    ev_unlock(&((VGAShmem_t *)priv)->cursorSema);
    return self;
}

/*
 * Finding 12.  The Window Server splits this into VGASysHideCursor,
 * VGACheckShield and VGASysShowCursor behind a locked entry point; the
 * kernel has the same three inlined into one method.  VGACheckShield's own
 * call to VGASysShowCursor is the reason the show tail appears twice --
 * once for the shield going away and once for the move itself -- and both
 * copies run in sequence, which is what the bundle does too.
 *
 * Moving the pointer reveals an obscured cursor, and the kernel does that
 * without asking the Window Server.  The shield test recomputes the cursor
 * rectangle into locals and deliberately does not write cursorRect; the
 * four comparisons are strict on the max side, so an edge-touching
 * intersection is a miss.  cursorRect is written only by the show tail,
 * and oldCursorRect is taken from it after the blit because that is what
 * the erase pass restores from.
 */
- moveCursor:(Point *)cursorLoc frame:(int)frame token:(int)t
{
    VGAShmem_t		*shmem = priv;
    IODisplayInfo	*di;

    if (!ev_try_lock(&shmem->cursorSema))
	return self;

    shmem->frame = frame;
    shmem->cursorLoc = *cursorLoc;

    if (shmem->cursorShow++ == 0)
	VGARemoveCursor([self displayInfo], shmem);

    if (shmem->cursorObscured) {
	shmem->cursorObscured = 0;
	if (shmem->cursorShow)
	    shmem->cursorShow--;
    }

    if (shmem->shieldFlag) {
	Point	hot;
	Bounds	c;
	int	hit;

	di = [self displayInfo];

	hot = shmem->hotSpot[shmem->frame];
	c.minx = shmem->cursorLoc.x - hot.x;
	c.maxx = c.minx + CURSORWIDTH;
	c.miny = shmem->cursorLoc.y - hot.y;
	c.maxy = c.miny + CURSORHEIGHT;

	hit = 0;
	if (shmem->shieldRect.maxx > c.minx &&
	    shmem->shieldRect.minx < c.maxx &&
	    shmem->shieldRect.maxy > c.miny &&
	    shmem->shieldRect.miny < c.maxy)
	    hit++;

	if (hit != shmem->shielded) {
	    shmem->shielded = hit;
	    if (shmem->shielded) {
		if (shmem->cursorShow++ == 0)
		    VGARemoveCursor(di, shmem);
	    } else if (shmem->cursorShow && --shmem->cursorShow == 0) {
		Point	hot;

		hot = shmem->hotSpot[shmem->frame];
		shmem->cursorRect.minx = shmem->cursorLoc.x - hot.x;
		shmem->cursorRect.maxx = shmem->cursorRect.minx + CURSORWIDTH;
		shmem->cursorRect.miny = shmem->cursorLoc.y - hot.y;
		shmem->cursorRect.maxy = shmem->cursorRect.miny + CURSORHEIGHT;
		VGADisplayCursor(di, shmem);
		shmem->oldCursorRect = shmem->cursorRect;
	    }
	}
    }

    if (shmem->cursorShow && --shmem->cursorShow == 0) {
	Point	hot;

	di = [self displayInfo];
	hot = shmem->hotSpot[shmem->frame];
	shmem->cursorRect.minx = shmem->cursorLoc.x - hot.x;
	shmem->cursorRect.maxx = shmem->cursorRect.minx + CURSORWIDTH;
	shmem->cursorRect.miny = shmem->cursorLoc.y - hot.y;
	shmem->cursorRect.maxy = shmem->cursorRect.miny + CURSORHEIGHT;
	VGADisplayCursor(di, shmem);
	shmem->oldCursorRect = shmem->cursorRect;
    }

    ev_unlock(&shmem->cursorSema);
    return self;
}

/*
 * Finding 13.  Finding 12 without the leading hide and without the
 * un-obscure step, and with the last displayInfo taken before the depth
 * test rather than inside it.
 */
- showCursor:(Point *)cursorLoc frame:(int)frame token:(int)t
{
    VGAShmem_t		*shmem = priv;
    IODisplayInfo	*di;

    if (!ev_try_lock(&shmem->cursorSema))
	return self;

    shmem->frame = frame;
    shmem->cursorLoc = *cursorLoc;

    if (shmem->shieldFlag) {
	Point	hot;
	Bounds	c;
	int	hit;

	di = [self displayInfo];

	hot = shmem->hotSpot[shmem->frame];
	c.minx = shmem->cursorLoc.x - hot.x;
	c.maxx = c.minx + CURSORWIDTH;
	c.miny = shmem->cursorLoc.y - hot.y;
	c.maxy = c.miny + CURSORHEIGHT;

	hit = 0;
	if (shmem->shieldRect.maxx > c.minx &&
	    shmem->shieldRect.minx < c.maxx &&
	    shmem->shieldRect.maxy > c.miny &&
	    shmem->shieldRect.miny < c.maxy)
	    hit++;

	if (hit != shmem->shielded) {
	    shmem->shielded = hit;
	    if (shmem->shielded) {
		if (shmem->cursorShow++ == 0)
		    VGARemoveCursor(di, shmem);
	    } else if (shmem->cursorShow && --shmem->cursorShow == 0) {
		Point	hot;

		hot = shmem->hotSpot[shmem->frame];
		shmem->cursorRect.minx = shmem->cursorLoc.x - hot.x;
		shmem->cursorRect.maxx = shmem->cursorRect.minx + CURSORWIDTH;
		shmem->cursorRect.miny = shmem->cursorLoc.y - hot.y;
		shmem->cursorRect.maxy = shmem->cursorRect.miny + CURSORHEIGHT;
		VGADisplayCursor(di, shmem);
		shmem->oldCursorRect = shmem->cursorRect;
	    }
	}
    }

    di = [self displayInfo];
    if (shmem->cursorShow && --shmem->cursorShow == 0) {
	Point	hot;

	hot = shmem->hotSpot[shmem->frame];
	shmem->cursorRect.minx = shmem->cursorLoc.x - hot.x;
	shmem->cursorRect.maxx = shmem->cursorRect.minx + CURSORWIDTH;
	shmem->cursorRect.miny = shmem->cursorLoc.y - hot.y;
	shmem->cursorRect.maxy = shmem->cursorRect.miny + CURSORHEIGHT;
	VGADisplayCursor(di, shmem);
	shmem->oldCursorRect = shmem->cursorRect;
    }

    ev_unlock(&shmem->cursorSema);
    return self;
}

/*
 * Finding 14.  "VGADisplay%d" into the twenty-byte nameBuf, which is what
 * the Window Server bundle later looks up as "VGADisplay0".  The unit is
 * written through the caller's pointer and then read back out of it for
 * the sprintf, which is what the reference does.
 */
- (char *)generateNameAndUnit:(unsigned int *)unit
{
    *unit = nextVGAUnit++;
    sprintf(nameBuf, "VGADisplay%d", *unit);
    return nameBuf;
}

/*
 * Finding 15.  A stub in the reference too: the frame buffer is not
 * mapped through this path.  It exists so that the IO_Framebuffer_Map
 * parameter has something to call.
 */
- (vm_offset_t)map
{
    return 0;
}

/*
 * Finding 16.  The loop counter and the limit are unsigned, so a device
 * with no port ranges releases nothing.
 */
- (void)unmap
{
    unsigned int	i, n;

    n = [[self deviceDescription] numPortRanges];
    for (i = 0; i < n; i++)
	[self releasePortRange:i];
}

/*
 * Finding 17.  Apple's defect, reproduced rather than fixed: this returns
 * YES unconditionally and never looks at what initFromDeviceDescription:
 * gave back.  If the allocation or the init fails, the four messages below
 * go to nil and the probe still reports success.
 */
+ (BOOL)probe:deviceDescription
{
    unsigned int	 unit;
    id			 display;
    char		*name;

    display = [[self alloc] initFromDeviceDescription:deviceDescription];
    name = [display generateNameAndUnit:&unit];
    [display setUnit:unit];
    [display setName:name];
    [display setDeviceKind:"frame buffer"];
    [display registerDevice];
    return YES;
}

/*
 * Finding 18.  Nothing else: neither the shared region nor the vidBIOS
 * instance is released.
 */
- free
{
    return [super free];
}

/*
 * Finding 19.  Pick the mode, then say so on the console.
 *
 * The "Yes" test is a strcmp, not a strncmp: gcc turns strcmp against a
 * literal into an inline four-byte repe cmpsb, which is the reference's
 * `mov ecx,4' at 4744, whereas the strncmp in -didBootWithDefaultConfig is
 * a real call.  Comparing four bytes means the terminator is compared too,
 * so "Yesterday" does not match.
 *
 * -didBootWithDefaultConfig is NOT dead here.  The store that sets
 * svga_bios_mode to 1 jumps *past* the else-branch's store and into the
 * call, so the call runs on both paths and its YES answer clears the flag
 * the "Yes" branch just set.  Booting with `config=Default' really does
 * suppress SVGA mode.  See the report for the reading of the reference's
 * branch at 4763 that settles this.
 */
- initFromDeviceDescription:deviceDescription
{
    const char	*s;

    if ([super initFromDeviceDescription:deviceDescription] == nil)
	return nil;

    s = [[deviceDescription configTable] valueForStringKey:"SVGA Mode"];
    if (s != NULL && strcmp(s, "Yes") == 0)
	svga_bios_mode = 1;
    else
	svga_bios_mode = 0;

    if ([self didBootWithDefaultConfig] == YES)
	svga_bios_mode = 0;

    if (svga_bios_mode == 1) {
	bios = [[vidBIOS alloc] init];
	if (bios == nil) {
	    IOLog("VGADisplay: vidBIOS failed\n");
	    svga_bios_mode = 0;
	}
    }

    if (svga_bios_mode == 0)
	IOLog("VGADisplay: Mode Selected: 640 x 480 @ 60 Hz (BW:2)\n");
    else {
	IOLog("VGADisplay: Mode Selected: 800 x 600 @ 60 Hz (BW:2)\n");
	s = [[deviceDescription configTable]
		valueForStringKey:"SVGA VESA BIOS Mode"];
	if (s != NULL) {
	    vesaMode = strtol(s, NULL, 16);
	    IOLog("VGADisplay: VESA mode selected: 0x%x\n", vesaMode);
	}
    }

    return self;
}

/*
 * Finding 20.  Apple's second defect here: the range check logs and does
 * not guard.  Both paths fall into SetET4000Brightness.  The comparison is
 * unsigned -- the reference's `cmp ebx,0x40 / jbe' -- so a negative level
 * is out of range too and then still reaches the DAC.  token is unread.
 */
- setBrightness:(int)level token:(int)t
{
    if ((unsigned int)level > 64)
	IOLog("%s: Invalid arg to setBrightness:%d\n", [self name], level);

    SetET4000Brightness(level);
    return self;
}

/*
 * Finding 21.  Four parameters, matched by strcmp in this order, with
 * anything unrecognised going to the superclass.  gcc compiles each strcmp
 * against a literal into an inline repe cmpsb of strlen+1 bytes, which is
 * why the reference's counts are 19, 26, 17 and 24 and why a name that
 * merely shares a prefix does not match.
 *
 * IO_Framebuffer_Map and IO_Framebuffer_Dimensions are implemented here but
 * sent by nobody in this driver pair; the Window Server bundle sends only
 * IOGetDisplayInfo and IO_Framebuffer_Register on this side.  They exist
 * for the event driver and the console.
 *
 * IOGetDisplayInfo answers a hardcoded triple rather than displayInfo's,
 * and it is that answer that determines every geometry global on the
 * Window Server side.
 */
- (IOReturn)getIntValues	: (unsigned *)parameterArray
		   forParameter	: (IOParameterName)parameterName
			  count	: (unsigned *)count
{
    unsigned int	numInts = *count;

    if (strcmp(parameterName, "IO_Framebuffer_Map") == 0) {
	parameterArray[0] = (unsigned int)[self map];
	*count = 1;
	return IO_R_SUCCESS;
    }

    if (strcmp(parameterName, "IO_Framebuffer_Dimensions") == 0) {
	unsigned int	 values[3];
	IODisplayInfo	*di;
	int		 i;

	di = [self displayInfo];
	values[0] = di->width;
	values[1] = di->height;
	values[2] = di->rowBytes;

	*count = 0;
	for (i = 0; i < 3; i++) {
	    if (*count == numInts)
		break;
	    parameterArray[i] = values[i];
	    (*count)++;
	}
	return IO_R_SUCCESS;
    }

    if (strcmp(parameterName, "IOGetDisplayInfo") == 0) {
	if (*count != 3)
	    return IO_R_INVALID_ARG;

	if (svga_bios_mode) {
	    parameterArray[0] = 800;
	    parameterArray[1] = 600;
	    parameterArray[2] = 200;
	} else {
	    parameterArray[0] = 640;
	    parameterArray[1] = 480;
	    parameterArray[2] = 160;
	}
	return IO_R_SUCCESS;
    }

    if (strcmp(parameterName, "IO_Framebuffer_Register") == 0) {
	IOReturn	rtn;

	rtn = [self _registerWithED];
	[kmId registerDisplay:self];

	*count = 0;
	if (numInts != 0) {
	    *count = 1;
	    parameterArray[0] = [self token];
	}
	return rtn;
    }

    return [super getIntValues:parameterArray forParameter:parameterName
			 count:count];
}

/*
 * Finding 22.  The same shape on the set side, with four more parameters
 * of which the bundle sends only IO_Framebuffer_SetDimensions and
 * Set VGA VESA Mode.
 *
 * SetDimensions never inspects count -- three ints are always read -- and
 * it is what pushes IO_VGA into bitsPerPixel.  Set VGA VESA Mode reads
 * parameterArray[0] not at all: it enters the mode the driver's own
 * vesaMode global names.
 */
- (IOReturn)setIntValues	: (unsigned *)parameterArray
		   forParameter	: (IOParameterName)parameterName
			  count	: (unsigned)count
{
    if (strcmp(parameterName, "IO_Framebuffer_Unmap") == 0) {
	[self unmap];
	return IO_R_SUCCESS;
    }

    if (strcmp(parameterName, "IO_Framebuffer_SetDimensions") == 0) {
	IODisplayInfo	*di;

	di = [self displayInfo];
	di->width = parameterArray[0];
	di->height = parameterArray[1];
	di->rowBytes = parameterArray[2];
	di->bitsPerPixel = IO_VGA;
	return IO_R_SUCCESS;
    }

    if (strcmp(parameterName, "IO_Framebuffer_Unregister") == 0) {
	if (count != 1)
	    return IO_R_INVALID_ARG;

	[[EventDriver instance] unregisterScreen:parameterArray[0]];
	return IO_R_SUCCESS;
    }

    if (strcmp(parameterName, "Set VGA VESA Mode") == 0) {
	if (count != 1)
	    return IO_R_INVALID_ARG;

	[self enterSVGAMode:vesaMode];
	return IO_R_SUCCESS;
    }

    return [super setIntValues:parameterArray forParameter:parameterName
			 count:count];
}

/*
 * Finding 23.  A tail call into the kernel's own VGAConsole.c.  This is the
 * reason the five console globals and the six select/convert functions
 * above are exported rather than static.
 */
- (IOConsoleInfo *)allocateConsoleInfo
{
    return VGAAllocateConsole([self displayInfo]);
}

@end

@implementation IOVGADisplay (VESAMode)

/*
 * Finding 24.  VESA BIOS function 4F02, set SuperVGA video mode.  The
 * five-second sleep is on the failure path only, and is there so that the
 * operator can read the message before the console is repainted.
 */
- (void)enterSVGAMode:(unsigned int)mode
{
    emu486regs_t	regs;

    memset(&regs, 0, sizeof regs);
    regs.eax = 0x4F02;
    regs.ebx = mode;

    [self int10:&regs];

    if ((unsigned short)regs.eax != 0x004F) {
	IOLog("%s: BIOS mode change returned %04x\n", [self name],
	      (unsigned short)regs.eax);
	IOSleep(5000);
    }
}

/*
 * Finding 25.  The entry into vidBIOS, and the reason -enterSVGAMode: can
 * read its result out of the block it filled in: the same register block is
 * passed as both inregs and outregs.
 *
 * The permit vector is built on the stack, one entry longer than the
 * device's own port range list, with the wide-open range first -- so the
 * device's ranges are additive and, given range 0, redundant.  The plumbing
 * is there so that a narrower ports would work.
 */
- (int)int10:(emu486regs_t *)regs
{
    /*
     * _ports.168 at __TEXT,__const 18920 is {start = 0, size = 0x10000}:
     * every I/O port permitted, prepended to the device's own port
     * ranges.  const-qualified, which is what puts it in __const.
     */
    static const IORange ports = { 0, 0x10000 };

    id			 dd;
    unsigned int	 numRanges;

    dd = [self deviceDescription];
    numRanges = [dd numPortRanges];

    {
	IORange	ranges[numRanges + 1];

	ranges[0] = ports;
	memcpy(&ranges[1], [dd portRangeList], numRanges * sizeof(IORange));

	return [bios int10:regs outregs:regs iorange:ranges
		      ionum:numRanges + 1];
    }
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
 * Finding 27.  Answer whether the machine was booted with `config=Default'.
 *
 * The two literal addresses the reference folds -- 0x110A4 for the cookie
 * and 0x11002 for the string -- are exactly KERNSTRUCT_ADDR's magicCookie
 * and bootString from machdep/i386/kernBootStruct.h, so the header needs no
 * change.  The blank test compiles as (unsigned char)(c - 9) <= 1 plus a
 * separate compare against 0x20, so the accepted set is tab, newline and
 * space.
 *
 * Contrary to finding 19's prose, this answer is used: see the comment on
 * -initFromDeviceDescription: above.
 */
- (BOOL)didBootWithDefaultConfig
{
    KERNBOOTSTRUCT	*kbs = KERNSTRUCT_ADDR;
    char		*p;

    if (kbs->magicCookie != KERNBOOTMAGIC)
	return NO;

    p = find_parameter("config", kbs->bootString);
    if (p == 0)
	return NO;

    while (*p != 0 && (*p == ' ' || *p == '\t' || *p == '\n'))
	p++;
    if (p == 0 || *p != '=')
	return NO;

    p++;
    while (*p != 0 && (*p == ' ' || *p == '\t' || *p == '\n'))
	p++;

    if (strncmp(p, "Default", 7) != 0)
	return NO;

    p += 7;
    if (*p == 0 || *p == ' ' || *p == '\t' || *p == '\n')
	return YES;
    return NO;
}

@end
