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
