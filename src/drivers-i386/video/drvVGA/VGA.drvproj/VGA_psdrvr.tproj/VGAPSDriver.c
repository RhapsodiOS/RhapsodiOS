/* Copyright (c) 1993 by NeXT Computer, Inc.
 * All rights reserved.
 *
 * VGAPSDriver.c -- the VGA display bundle the Window Server loads.
 *
 * The Window Server never draws into VGA memory.  It draws into a packed
 * two-bit-per-pixel shadow with the stock bm12 imaging machine, and this
 * driver converts dirty rectangles from that shadow into the four-plane
 * frame buffer afterwards.  Only planes 0 and 1 are ever written, which is
 * why the palette paints every other index bright red.
 *
 * This is one translation unit on purpose: the driver vector, the cursor
 * layer and the VGA hardware layer share file-scope state and the vector
 * table's initializer names the statics it points at.
 */

#import "VGAPSDriver.h"

#import <driverkit/driverTypes.h>
#import <string.h>

/*
 * IO port access.
 *
 * outb carries a dummy "=m" operand and inb does not, which is why every
 * `out' in the reference is followed by a `lock incl' and no `in' is.
 * The dummy is an automatic, not a static, so the compiler emits
 * `lock incl -4(%ebp)' rather than a reference to a file-scope integer.
 * Do not reach for <driverkit/i386/ioPorts.h> here: its outb declares
 * `static int xxx', which would put the counter in __DATA,__data and add
 * a relocation the reference does not have.
 */
static __inline__ unsigned char
inb(unsigned short port)
{
    unsigned char	data;

    asm volatile(
	"inb %1,%0"

	: "=a" (data)
	: "d" (port));

    return (data);
}

static __inline__ void
outb(unsigned short port, unsigned char data)
{
    int			xxx;

    asm volatile(
	"outb %2,%1; lock; incl %0"

	: "=m" (xxx)
	: "d" (port), "a" (data), "0" (xxx)
	: "cc");
}

/*
 * The seven exported globals.  Tentative definitions -- no initializer
 * and no static -- so that they land in __DATA,__common where the Window
 * Server expects to find them.
 */
int		vga_width;
int		vga_height;
int		vga_rowbytes;
int		vga_bpl;
Bounds		vgaBounds;
vm_address_t	vgaAddress;
void	       *vgaVirtualAddress;

typedef struct bmClass	bmClass;

/*
 * The Window Server's records, as much of them as this file touches.  The
 * layouts belong to the Window Server, so only the fields the reference
 * actually addresses are named and everything between them is reserved.
 */
struct NXScreenDev {
    char		reserved0[0x10];
    Bounds		bounds;			/* +0x10 */
    char		reserved18[0x10];
    VGAShmem_t	       *shmem;			/* +0x28 */
};

struct bitmap {
    bmClass	       *isa;			/* +0x00 */
    void	       *f4;			/* +0x04 */
    void	       *f8;			/* +0x08 */
    short		format;			/* +0x0c */
    short		refcount;		/* +0x0e */
    char		reserved10[0x10];
    void	       *plane0;			/* +0x20 */
    void	       *plane1;			/* +0x24 */
};

struct bmClass {
    char		reserved0[0x10];
    void	      (*free)(bitmap *bm);	/* +0x10 */
    char		reserved14[0x28];
    bitmap	     *(*newBitmap)(bmClass *self, const Bounds *r,
				   void *image, void *mask, int rowbytes,
				   int depth, int a, int b); /* +0x3c */
};

/*
 * The three cursor converters, one per source pixel format.  Each takes two
 * Bounds by value; the second is always the zero rectangle below.
 */
extern void	BM12Convert8to2(bitmap *dst, bitmap *src, Bounds sr,
				void *f4, void *f8, Bounds dr);
extern void	BM12Convert16to2(bitmap *dst, bitmap *src, Bounds sr,
				 void *f4, void *f8, Bounds dr);
extern void	BM12Convert32to2(bitmap *dst, bitmap *src, Bounds sr,
				 void *f4, void *f8, Bounds dr);

/*
 * The Window Server's four imaging machine class objects, one per pixel
 * format.  These are imported data, not code: the driver takes their
 * addresses for the class table below and dereferences only _bm12.  The
 * other three exist so the Window Server can ask for an offscreen bitmap
 * at a depth this screen does not use.
 */
extern bmClass	_bm12;			/* 2 bits/pixel, the screen's own */
extern bmClass	_bm18;			/* 8 bit gray			 */
extern bmClass	_bm34;			/* 16 bit RGB			 */
extern bmClass	_bm38;			/* 32 bit RGB			 */

/*
 * The eighteen driver vector entries.  Eleven are static and are named
 * nowhere but in the vector table's initializer; the other seven are the
 * public cursor entries declared in VGAPSDriver.h.
 */
static void	VGAInitScreen(NXScreenDev *dev);
static void	VGARegisterScreen(void);
static void	VGANullOp(void);
static void	VGAComposite(void *op, Bounds *dirty);
static void	VGAFreeOffscreen(NXScreenDev *dev);
static void	VGAFillRect(NXScreenDev *dev, int which, int arg, Bounds *r,
			    int arg2);
static void	VGASetOffscreenOrigin(NXScreenDev *dev, short x, short y);
static void	VGAOffscreenOp18(NXScreenDev *dev);
static void	VGANewOffscreen(NXScreenDev *dev, void *a, int which,
				int depth, void *b);
static void	VGAConvertOffscreen(NXScreenDev *dev, int index, void *a,
				    int flag);
static int	VGAGetOffscreenParams(NXScreenDev *dev);

/*
 * The cursor blitters and the VGA plane primitives, none of which is
 * reachable from outside this file.
 */
static void	VGADisplayCursorBlit(NXScreenDev *dev);
static void	VGARemoveCursorBlit(NXScreenDev *dev);
static void	select_read_plane(int plane);
static void	select_write_plane(int plane);
static void	build_tables(void);

/*
 * __TEXT,__const.  The cursor layer's two objects first, then the five
 * VGA register tables, in the order their users appear below.
 */

/* The cursor is always 16 by 16. */
static const Bounds cursorBounds = { 0, CURSORWIDTH, 0, CURSORHEIGHT };

/*
 * The destination rectangle VGASetCursor hands the three converters.  It is
 * always empty and it is a second const object, not padding: the reference
 * loads both of its words from __const, eight bytes above leftMask.
 */
static const Bounds zeroBounds = { 0, 0, 0, 0 };

/* leftMask[k] is ~0 << 2k: the pixels at or right of column k, 2 bpp. */
static const unsigned int leftMask[17] = {
    0xffffffff, 0xfffffffc, 0xfffffff0, 0xffffffc0,
    0xffffff00, 0xfffffc00, 0xfffff000, 0xffffc000,
    0xffff0000, 0xfffc0000, 0xfff00000, 0xffc00000,
    0xff000000, 0xfc000000, 0xf0000000, 0xc0000000,
    0x00000000
};

/*
 * Register values for the six modes VGASetStdRegs knows.  Mode 5 is
 * 640x480x16, BIOS mode 0x12, and it is the only one VGAStart ever asks
 * for; mode 4 is the 80x25 text mode.
 */

/* Miscellaneous Output, port 0x3C2. */
static const unsigned char miscTable[6] = {
    0xeb, 0xeb, 0xeb, 0x2f, 0x67, 0xe3
};

/* Sequencer, index 0 through 4, ports 0x3C4/0x3C5. */
static const unsigned char seqTable[6][5] = {
    { 0x03, 0x01, 0x0f, 0x00, 0x0e },
    { 0x03, 0x01, 0x0f, 0x00, 0x0e },
    { 0x03, 0x01, 0x0f, 0x00, 0x0e },
    { 0x01, 0x01, 0x0f, 0x00, 0x0e },
    { 0x01, 0x00, 0x03, 0x00, 0x02 },
    { 0x03, 0x01, 0x0f, 0x00, 0x06 }
};

/* CRT Controller, index 0 through 0x18, ports 0x3D4/0x3D5. */
static const unsigned char crtcTable[6][25] = {
    { 0xc3, 0x9f, 0xa2, 0x84, 0xa6, 0x00, 0x0b, 0x3e,
      0x00, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0xea, 0x8c, 0xdf, 0x50, 0x00, 0xe7, 0x04, 0xe3,
      0xff },
    { 0xf5, 0xc7, 0xc9, 0x98, 0xd8, 0x87, 0x70, 0xf0,
      0x00, 0x60, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x58, 0x8c, 0x57, 0x64, 0x00, 0x58, 0x70, 0xe3,
      0xff },
    { 0x91, 0x77, 0xd8, 0x82, 0x7e, 0x02, 0x0b, 0x3e,
      0x00, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0xea, 0x8c, 0xdf, 0x50, 0x00, 0xe7, 0x04, 0xe3,
      0xff },
    { 0xa2, 0x7f, 0x80, 0x85, 0x89, 0x82, 0x28, 0xfd,
      0x00, 0x60, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x02, 0x8a, 0xff, 0x80, 0x00, 0x04, 0x25, 0xe3,
      0xff },
    { 0x5f, 0x4f, 0x50, 0x82, 0x55, 0x81, 0xbf, 0x1f,
      0x00, 0x4f, 0x0d, 0x0e, 0x00, 0x00, 0x00, 0x00,
      0x9c, 0x8e, 0x8f, 0x28, 0x1f, 0x96, 0xb9, 0xa3,
      0xff },
    { 0x5f, 0x4f, 0x50, 0x82, 0x54, 0x80, 0x0b, 0x3e,
      0x00, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x59,
      0xea, 0x8c, 0xdf, 0x28, 0x00, 0xe7, 0x04, 0xe3,
      0xff }
};

/* Attribute Controller, index 0 through 0x13, port 0x3C0. */
static const unsigned char acTable[6][20] = {
    { 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
      0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
      0x01, 0x00, 0xff, 0x00 },
    { 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
      0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
      0x01, 0x00, 0xff, 0x00 },
    { 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
      0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
      0x01, 0x00, 0xff, 0x00 },
    { 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
      0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
      0x01, 0x00, 0x0f, 0x00 },
    { 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x14, 0x07,
      0x38, 0x39, 0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f,
      0x0c, 0x00, 0x0f, 0x08 },
    { 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x14, 0x07,
      0x38, 0x39, 0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f,
      0x01, 0x00, 0x0f, 0x00 }
};

/* Graphics Controller, index 0 through 8, ports 0x3CE/0x3CF. */
static const unsigned char gcTable[6][9] = {
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05, 0x0f, 0xff },
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05, 0x0f, 0xff },
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05, 0x0f, 0xff },
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05, 0x0f, 0xff },
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x0e, 0x00, 0xff },
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05, 0x0f, 0xff }
};

/*
 * __DATA,__data.  The class table is indexed by a depth: index 0 and
 * index 1 both give the two-bit machine, so a request for either of the
 * lowest two depths gets bm12.
 */
static bmClass *bmClasses[5] = {
    &_bm12, &_bm12, &_bm18, &_bm34, &_bm38
};

/*
 * The driver vector.  VGAStart stores its address in the screen
 * descriptor and the Window Server calls the driver through it.  Three of
 * the twenty-one slots are genuinely not implemented.
 */
static void (*vgaDriverVector[21])() = {
    (void (*)())VGAComposite,			/* +0x00 */
    (void (*)())VGAFreeOffscreen,		/* +0x04 */
    0,						/* +0x08 */
    (void (*)())VGAInitScreen,			/* +0x0c */
    (void (*)())VGAFillRect,			/* +0x10 */
    (void (*)())VGASetOffscreenOrigin,		/* +0x14 */
    (void (*)())VGAOffscreenOp18,		/* +0x18 */
    (void (*)())VGANewOffscreen,		/* +0x1c */
    0,						/* +0x20 */
    (void (*)())VGAConvertOffscreen,		/* +0x24 */
    (void (*)())VGARegisterScreen,		/* +0x28 */
    (void (*)())VGAGetOffscreenParams,		/* +0x2c */
    (void (*)())VGASetCursor,			/* +0x30 */
    (void (*)())VGAHideCursor,			/* +0x34 */
    (void (*)())VGAShowCursor,			/* +0x38 */
    (void (*)())VGAObscureCursor,		/* +0x3c */
    (void (*)())VGARevealCursor,		/* +0x40 */
    (void (*)())VGAShieldCursor,		/* +0x44 */
    (void (*)())VGAUnshieldCursor,		/* +0x48 */
    0,						/* +0x4c */
    (void (*)())VGANullOp			/* +0x50 */
};

/*
 * __DATA,__bss.  The device master port and the display's object number
 * are cached by VGAStart and reused by the vector's register entry.
 */
static port_t		master;
static IOObjectNumber	object;

/*
 * The two conversion tables, built once at the first flush.  Each maps a
 * sixteen bit half of a 2 bpp word to the eight plane bits it produces,
 * complemented, because index 3 is white on this screen and index 0 is
 * black -- the inverse of NeXT's two-bit gray.
 */
static unsigned char	evenTable[65536];
static unsigned char	oddTable[65536];

/*
 * The guard for the two tables above.  It is incremented rather than set,
 * and the only test is against zero.
 */
static int		tablesBuilt = 0;

/*
 * ---------------------------------------------------------------------
 * The thirty-four compiled bodies, in the order the reference emits them.
 * Every one is a stub; the three tasks that follow fill them in a layer
 * at a time.
 * ---------------------------------------------------------------------
 */

/* Vector slot +0x0c.  The only writer of vgaBounds. */
static void
VGAInitScreen(NXScreenDev *dev)
{
}

/* Vector slot +0x28.  Sends IO_Framebuffer_Register, after VGAStart. */
static void
VGARegisterScreen(void)
{
}

/* Vector slot +0x50.  Empty in the reference too. */
static void
VGANullOp(void)
{
}

/* Vector slot +0x00.  Composite, then flush the dirty rectangle. */
static void
VGAComposite(void *op, Bounds *dirty)
{
}

/* Vector slot +0x04. */
static void
VGAFreeOffscreen(NXScreenDev *dev)
{
}

/* Vector slot +0x10. */
static void
VGAFillRect(NXScreenDev *dev, int which, int arg, Bounds *r, int arg2)
{
}

/* Vector slot +0x14. */
static void
VGASetOffscreenOrigin(NXScreenDev *dev, short x, short y)
{
}

/* Vector slot +0x18. */
static void
VGAOffscreenOp18(NXScreenDev *dev)
{
}

/* Vector slot +0x1c.  Clamps its depth to 0..4 before indexing bmClasses. */
static void
VGANewOffscreen(NXScreenDev *dev, void *a, int which, int depth, void *b)
{
}

/* Vector slot +0x24.  Does not clamp its index, unlike the slot above. */
static void
VGAConvertOffscreen(NXScreenDev *dev, int index, void *a, int flag)
{
}

/* Vector slot +0x2c. */
static int
VGAGetOffscreenParams(NXScreenDev *dev)
{
    return (0);
}

/*
 * The entry point.  Also exported as Start, which is the fixed name the
 * Window Server resolves in every display bundle.
 */
int
VGAStart(NXScreen *screen)
{
    return (-1);
}

asm(".globl _Start");
asm(".set _Start, _VGAStart");

/*
 * cursorShow is a hide depth, not a boolean, and the counter moves whether or
 * not the blit happens: the reference increments it unconditionally and lets
 * the value it had decide.  Caller holds cursorSema.
 */
void
VGASysHideCursor(NXScreenDev *dev)
{
    if (dev->shmem->cursorShow++ == 0)
	VGARemoveCursorBlit(dev);
}

/*
 * The other half of the counter.  The cursor rectangle is recomputed here and
 * nowhere else, and oldCursorRect is taken from it after the blit, because
 * that is what the erase pass restores from.  Caller holds cursorSema.
 */
void
VGASysShowCursor(NXScreenDev *dev)
{
    Point		hot;

    if (dev->shmem->cursorShow == 0)
	return;
    if (--dev->shmem->cursorShow != 0)
	return;

    hot = dev->shmem->hotSpot[dev->shmem->frame];
    dev->shmem->cursorRect.minx = dev->shmem->cursorLoc.x - hot.x;
    dev->shmem->cursorRect.maxx = dev->shmem->cursorRect.minx + CURSORWIDTH;
    dev->shmem->cursorRect.miny = dev->shmem->cursorLoc.y - hot.y;
    dev->shmem->cursorRect.maxy = dev->shmem->cursorRect.miny + CURSORHEIGHT;

    VGADisplayCursorBlit(dev);
    dev->shmem->oldCursorRect = dev->shmem->cursorRect;
}

/*
 * Hide the cursor while it is under the shield rectangle and show it again
 * when it comes out.  The rectangle is recomputed into locals and is
 * deliberately not written back to cursorRect.  The four comparisons are
 * strict on the max side, so an edge-touching intersection is a miss, and
 * shielded is read as a signed char because that is how the reference reads
 * it.  Caller holds cursorSema.
 */
void
VGACheckShield(NXScreenDev *dev)
{
    Bounds		c;
    Point		hot;
    int			hit;

    hot = dev->shmem->hotSpot[dev->shmem->frame];
    c.minx = dev->shmem->cursorLoc.x - hot.x;
    c.maxx = c.minx + CURSORWIDTH;
    c.miny = dev->shmem->cursorLoc.y - hot.y;
    c.maxy = c.miny + CURSORHEIGHT;

    hit = 0;
    if (dev->shmem->shieldRect.maxx > c.minx &&
	dev->shmem->shieldRect.minx < c.maxx &&
	dev->shmem->shieldRect.maxy > c.miny &&
	dev->shmem->shieldRect.miny < c.maxy)
	hit = 1;

    if (hit != (signed char)dev->shmem->shielded) {
	if (hit)
	    VGASysHideCursor(dev);
	else
	    VGASysShowCursor(dev);
	dev->shmem->shielded = hit;
    }
}

/*
 * The only writer of cursor.bw.image and cursor.bw.mask.  A scratch bm12
 * bitmap over two 64 byte stack buffers receives the conversion, and those
 * buffers are what gets copied into shared memory -- except for format 1,
 * where the caller's own planes are used and the scratch bitmap is built and
 * thrown away untouched.
 *
 * A format outside 1 through 4 converts nothing and leaves image and mask
 * pointing at the uninitialized buffers, so it copies 128 bytes of stack into
 * the shared cursor.  That is the reference's, and it is reachable only from
 * the Window Server.
 */
void
VGASetCursor(NXScreenDev *dev, bitmap *src, Point hot, int frame, int *flagp)
{
    unsigned int	 imageBuf[CURSORHEIGHT];
    unsigned int	 maskBuf[CURSORHEIGHT];
    void		*image = imageBuf;
    void		*mask = maskBuf;
    unsigned int	*dstImage = dev->shmem->cursor.bw.image[frame];
    unsigned int	*dstMask = dev->shmem->cursor.bw.mask[frame];
    bitmap		*tmp;
    int			 hide;

    tmp = _bm12.newBitmap(&_bm12, &cursorBounds, imageBuf, maskBuf,
			  sizeof imageBuf, 4, 0, 0);

    switch (src->format) {
    case 1:
	image = src->plane0;
	mask = src->plane1;
	break;
    case 2:
	BM12Convert8to2(tmp, src, cursorBounds, src->f4, src->f8, zeroBounds);
	break;
    case 3:
	BM12Convert16to2(tmp, src, cursorBounds, src->f4, src->f8, zeroBounds);
	break;
    case 4:
	BM12Convert32to2(tmp, src, cursorBounds, src->f4, src->f8, zeroBounds);
	break;
    }

    ev_lock(&dev->shmem->cursorSema);
    hide = (*flagp == 0);
    if (hide)
	VGASysHideCursor(dev);
    dev->shmem->hotSpot[frame] = hot;
    bcopy(image, dstImage, sizeof imageBuf);
    bcopy(mask, dstMask, sizeof maskBuf);
    if (hide)
	VGASysShowCursor(dev);
    ev_unlock(&dev->shmem->cursorSema);

    if (--tmp->refcount == 0)
	tmp->isa->free(tmp);
}

/*
 * The seven public entries below take the blocking lock.  The kernel half
 * takes ev_try_lock and drops the update when it fails; this half waits.  The
 * asymmetry is the driver's contention policy, so ev_try_lock must not appear
 * in this file.
 */
void
VGAHideCursor(NXScreenDev *dev)
{
    ev_lock(&dev->shmem->cursorSema);
    VGASysHideCursor(dev);
    ev_unlock(&dev->shmem->cursorSema);
}

void
VGAShowCursor(NXScreenDev *dev)
{
    ev_lock(&dev->shmem->cursorSema);
    VGASysShowCursor(dev);
    ev_unlock(&dev->shmem->cursorSema);
}

/* Hide first, then raise the flag. */
void
VGAObscureCursor(NXScreenDev *dev)
{
    ev_lock(&dev->shmem->cursorSema);
    if (!dev->shmem->cursorObscured) {
	VGASysHideCursor(dev);
	dev->shmem->cursorObscured = 1;
    }
    ev_unlock(&dev->shmem->cursorSema);
}

/* Clear the flag first, then show: the reverse of the order above. */
void
VGARevealCursor(NXScreenDev *dev)
{
    ev_lock(&dev->shmem->cursorSema);
    if (dev->shmem->cursorObscured) {
	dev->shmem->cursorObscured = 0;
	VGASysShowCursor(dev);
    }
    ev_unlock(&dev->shmem->cursorSema);
}

/*
 * shielded is cleared before VGACheckShield runs, so re-shielding an already
 * shielded cursor with a rectangle that misses it leaves VGACheckShield
 * seeing hit == shielded == 0 and doing nothing: the cursor stays hidden at
 * depth one with shielded reading 0.  VGAUnshieldCursor does not recover it.
 * Nothing in the shield path does.  Reproduced as written.
 */
void
VGAShieldCursor(NXScreenDev *dev, Bounds *r)
{
    ev_lock(&dev->shmem->cursorSema);
    dev->shmem->shieldFlag = 1;
    dev->shmem->shielded = 0;
    dev->shmem->shieldRect = *r;
    VGACheckShield(dev);
    ev_unlock(&dev->shmem->cursorSema);
}

void
VGAUnshieldCursor(NXScreenDev *dev)
{
    ev_lock(&dev->shmem->cursorSema);
    if (dev->shmem->shielded)
	VGASysShowCursor(dev);
    dev->shmem->shielded = 0;
    dev->shmem->shieldFlag = 0;
    ev_unlock(&dev->shmem->cursorSema);
}

/*
 * Draw the cursor, saving what it covers into cursor.bw.save.
 *
 * The cursor is 16 pixels wide but lands at an arbitrary column, so the blit
 * snaps left to a 16 pixel boundary and covers two 32 bit words per scan
 * line, shifting the image and mask across the seam.  When the cursor happens
 * to be aligned the second word is untouched -- but the save pointer still
 * advances over it, which is why both blitters step 32 words, 128 bytes, over
 * a save[16] of 64.  The excess runs from +0x288 to +0x2C8, past the end of
 * the 648 byte region VGAInitScreen asks for.  The kernel's VGADisplayCursor
 * does the same, so the two halves stay in step; reproduced as written.
 */
static void
VGADisplayCursorBlit(NXScreenDev *dev)
{
    Bounds		 c;
    Bounds		 scr;
    unsigned int	*img, *msk, *save;
    unsigned int	 shift, rshift;
    unsigned int	 words, lines;
    unsigned short	*p;
    unsigned int	 v;
    int			 rows, col, row, last;
    int			 leftOK, rightOK;

    c = dev->shmem->cursorRect;
    scr = dev->bounds;

    if (scr.miny > c.miny)
	c.miny = scr.miny;
    if (scr.maxy < c.maxy)
	c.maxy = scr.maxy;

    c.minx = scr.minx + ((dev->shmem->cursorRect.minx - scr.minx) & ~15);
    c.maxx = c.minx + 2 * CURSORWIDTH;
    dev->shmem->saveRect = c;

    shift = (dev->shmem->cursorRect.minx & 15) * 2;	/* 2 bits per pixel */
    rshift = 32 - shift;

    /* Skip the scan lines the vertical clip took off the top. */
    rows = c.miny - dev->shmem->cursorRect.miny;
    img = &dev->shmem->cursor.bw.image[dev->shmem->frame][rows];
    msk = &dev->shmem->cursor.bw.mask[dev->shmem->frame][rows];
    save = &dev->shmem->cursor.bw.save[0];

    leftOK = scr.minx <= c.minx;
    rightOK = c.maxx <= scr.maxx;

    col = (c.minx - scr.minx) >> 4;
    words = (unsigned int)vga_bpl >> 1;		/* 16 pixel words per line */
    lines = 0x10000 / (unsigned int)vga_bpl;	/* lines per 64K window	   */
    get_addr_range((void **)&p);

    row = c.miny - scr.miny;
    p += (row % lines) * words + col;
    last = c.maxy - scr.miny;

    for (; row < last; row++) {
	if (leftOK) {
	    v = read_bpp4planar_to_bpp2packed(p);
	    *save++ = v;
	    v = (v & ~(*msk << shift)) | (*img << shift);
	    write_bpp2packed_to_bpp4planar(v, p);
	}
	if (rightOK) {
	    if (shift == 0)
		save++;				/* nothing spills over */
	    else {
		v = read_bpp4planar_to_bpp2packed(p + 1);
		*save++ = v;
		v = (v & ~(*msk >> rshift)) | (*img >> rshift);
		write_bpp2packed_to_bpp4planar(v, p + 1);
	    }
	}
	p += words;
	img++;
	msk++;
    }
}

/*
 * Erase the cursor, restoring from cursor.bw.save.
 *
 * saveRect says which two columns the draw pass covered and oldCursorRect
 * says where inside them the cursor actually was, so the two edge masks
 * restore exactly the pixels that were painted and leave the rest of the
 * word alone.  This blitter reads save[] and never writes it, so its stride
 * past the end of the array is an over-read where the draw pass's is an
 * over-write.
 */
static void
VGARemoveCursorBlit(NXScreenDev *dev)
{
    Bounds		 scr;
    Bounds		 s;
    unsigned int	*save;
    unsigned int	 maskL = 0, maskR = 0;
    unsigned int	 shift, words, lines;
    unsigned short	*p;
    unsigned int	 v;
    int			 col, row, last;
    int			 leftOK, rightOK;

    scr = dev->bounds;
    s = dev->shmem->saveRect;

    col = (s.minx - scr.minx) >> 4;
    words = (unsigned int)vga_bpl >> 1;
    lines = 0x10000 / (unsigned int)vga_bpl;
    get_addr_range((void **)&p);
    p += ((s.miny - scr.miny) % lines) * words + col;

    shift = (dev->shmem->cursorRect.minx & 15) * 2;
    save = &dev->shmem->cursor.bw.save[0];

    leftOK = s.minx >= scr.minx;
    rightOK = scr.maxx >= s.maxx;
    if (leftOK)
	maskL = leftMask[dev->shmem->oldCursorRect.minx - s.minx];
    if (rightOK)
	maskR = ~leftMask[CURSORWIDTH -
			  (s.maxx - dev->shmem->oldCursorRect.maxx)];

    last = s.maxy - scr.miny;
    for (row = s.miny - scr.miny; row < last; row++) {
	if (leftOK) {
	    v = read_bpp4planar_to_bpp2packed(p);
	    v = (v & ~maskL) | (maskL & *save++);
	    write_bpp2packed_to_bpp4planar(v, p);
	}
	if (rightOK) {
	    if (shift == 0)
		save++;
	    else {
		v = read_bpp4planar_to_bpp2packed(p + 1);
		v = (v & ~maskR) | (maskR & *save++);
		write_bpp2packed_to_bpp4planar(v, p + 1);
	    }
	}
	p += words;
    }
}

/*
 * Only four of the sixteen mode 0x12 pixel values are ever produced by
 * this driver, so entries 4 through 255 are painted bright red as a tell:
 * anything red on the screen came from a plane nothing here writes.  The
 * four grays are the palette values of IOVGADisplayPrivate.h, and index 3
 * is white where index 0 is black -- the inverse of NeXT's two bit gray,
 * which is why the two conversion tables complement every byte.
 */
void
set_colormap(void)
{
    int			i;

    for (i = 0; i <= 255; i++) {
	outb(0x3c8, i);
	outb(0x3c9, 0x3f);
	outb(0x3c9, 0);
	outb(0x3c9, 0);
    }
    outb(0x3c8, 3);				/* white		*/
    outb(0x3c9, 0x3f);
    outb(0x3c9, 0x3f);
    outb(0x3c9, 0x3f);
    outb(0x3c8, 2);				/* light gray		*/
    outb(0x3c9, 0x30);
    outb(0x3c9, 0x30);
    outb(0x3c9, 0x30);
    outb(0x3c8, 1);				/* dark gray		*/
    outb(0x3c9, 0x1e);
    outb(0x3c9, 0x1e);
    outb(0x3c9, 0x1e);
    outb(0x3c8, 0);				/* black		*/
    outb(0x3c9, 0);
    outb(0x3c9, 0);
    outb(0x3c9, 0);
}

/* Graphics Controller index 4: which plane reads come from. */
static void
select_read_plane(int plane)
{
    unsigned char	v;

    outb(0x3ce, 4);
    v = (inb(0x3cf) & 0xfc) | (plane & 3);
    outb(0x3ce, 4);
    outb(0x3cf, v);
}

/*
 * Sequencer index 2: a one hot mask, so only one plane is written.  Note
 * the asymmetry with the read selector above, which takes a plane number.
 */
static void
select_write_plane(int plane)
{
    unsigned char	v;

    outb(0x3c4, 2);
    v = (inb(0x3c5) & 0xf0) | (1 << (plane & 3));
    outb(0x3c4, 2);
    outb(0x3c5, v);
}

/*
 * Where the aperture is right now.  This is the whole of the bundle's
 * banking: it has a 128K mapping of 0xA0000 and never switches segments,
 * so it only has to read back what the Graphics Controller was left at.
 * Map select 3 is 0xB8000 on real hardware and this answers 0xB0000, a
 * 32K error, but mode 0x12 uses select 1 and the path is dead.
 */
void
get_addr_range(void **addr)
{
    outb(0x3ce, 6);
    switch ((inb(0x3cf) & 0x0c) >> 2) {
    case 0:
    case 1:
	*addr = (void *)vgaAddress;
	break;
    case 2:
    case 3:
	*addr = (void *)(vgaAddress + 0x10000);
	break;
    }
}

/*
 * Save the map mask, fill, restore the map mask -- and never set it in
 * between, so the fill lands in whatever planes are enabled.  VGAStart
 * calls this straight after VGASetStdRegs(5) leaves SEQ[2] at 0x0f, so it
 * clears all four, and that is the only time planes 2 and 3 are written.
 * 320 * 200 shorts is 128000 bytes, not the 64K of the name; the mapping
 * is 0x20000 bytes long, so the overrun stays inside it and the excess
 * spills into the 0xB0000 half of the aperture instead of faulting.
 */
void
fill_64K_plane(short value)
{
    unsigned char	saved;
    short	       *p;
    unsigned int	row, col;

    outb(0x3c4, 2);
    saved = inb(0x3c5);

    get_addr_range((void **)&p);
    for (row = 0; row <= 0xc7; row++)
	for (col = 0; col <= 0x13f; col++)
	    *p++ = value;

    outb(0x3c4, 2);
    outb(0x3c5, saved);
}

/*
 * The flush.  Every drawing operation ends here.
 *
 * The source stride is vga_width >> 4 32 bit words, which is vga_rowbytes
 * bytes and is the bm12 shadow's pitch; the destination stride is the same
 * count of 16 bit words, which is vga_bpl bytes.  Only planes 0 and 1 are
 * ever written -- that is what makes this screen two bits deep on four
 * plane hardware, and what set_colormap's red entries guard.
 */
void
vga_at_mode12_bpp2_to_bpp4(Bounds *r)
{
    int			 x0, x1, y0, y1;
    int			 first;
    unsigned int	 n, i, words, y, v;
    unsigned int	*src, *sp;
    unsigned short	*dst, *dp;
    unsigned char	 saved;
    void		*p;

    if (tablesBuilt == 0)
	build_tables();

    x0 = vgaBounds.minx > r->minx ? vgaBounds.minx : r->minx;
    y0 = vgaBounds.miny > r->miny ? vgaBounds.miny : r->miny;
    x1 = vgaBounds.maxx < r->maxx ? vgaBounds.maxx : r->maxx;
    y1 = vgaBounds.maxy < r->maxy ? vgaBounds.maxy : r->maxy;
    if (x1 < x0 || y0 > y1)
	return;

    x0 -= vgaBounds.minx;
    y0 -= vgaBounds.miny;
    x1 -= vgaBounds.minx;
    y1 -= vgaBounds.miny;

    /* The 16 pixel words this rectangle touches, and where they start. */
    first = x0 >> 4;
    n = x1 >> 4;
    if (x1 % 16 > 0)
	n++;
    n -= first;

    words = (unsigned int)vga_width >> 4;

    outb(0x3c4, 2);
    saved = inb(0x3c5);

    src = (unsigned int *)vgaVirtualAddress + y0 * words + first;
    get_addr_range(&p);
    dst = (unsigned short *)p + y0 * words + first;

    select_write_plane(0);
    for (y = y0; y <= (unsigned int)y1; y++) {
	sp = src;
	dp = dst;
	for (i = 0; i < n; i++) {
	    v = *sp++;
	    *dp++ = (evenTable[(v >> 16) & 0x5555] << 8) |
		    evenTable[v & 0x5555];
	}
	select_write_plane(1);
	sp = src;
	dp = dst;
	for (i = 0; i < n; i++) {
	    v = *sp++;
	    *dp++ = (oddTable[(v >> 16) & 0xaaaa] << 8) |
		    oddTable[v & 0xaaaa];
	}
	select_write_plane(0);
	src += words;
	dst += words;
    }
    select_write_plane(0);

    outb(0x3c4, 2);
    outb(0x3c5, saved);
}

/*
 * Sixteen pixels of planes 1 and 0, complemented and interleaved into one
 * word of sixteen two bit pixels, plane 0 supplying the low bit of each
 * pair.  A plane byte carries its leftmost pixel in its high bit and the
 * packed word carries pixel zero in its low pair, so each byte's bits come
 * out reversed; the complement is the gray-to-index inversion.
 */
unsigned int
read_bpp4planar_to_bpp2packed(const void *addr)
{
    unsigned int	c, hi, lo;

    select_read_plane(1);
    c = (unsigned short)~*(const unsigned short *)addr;
    hi = ((c & 0x8000) <<  2) | ((c & 0x4000) <<  5) |
	 ((c & 0x2000) <<  8) | ((c & 0x1000) << 11) |
	 ((c & 0x0800) << 14) | ((c & 0x0400) << 17) |
	 ((c & 0x0200) << 20) | ((c & 0x0100) << 23) |
	 ((c & 0x0080) >>  6) | ((c & 0x0040) >>  3) |
	  (c & 0x0020)        | ((c & 0x0010) <<  3) |
	 ((c & 0x0008) <<  6) | ((c & 0x0004) <<  9) |
	 ((c & 0x0002) << 12) | ((c & 0x0001) << 15);

    select_read_plane(0);
    c = (unsigned short)~*(const unsigned short *)addr;
    lo = ((c & 0x8000) <<  1) | ((c & 0x4000) <<  4) |
	 ((c & 0x2000) <<  7) | ((c & 0x1000) << 10) |
	 ((c & 0x0800) << 13) | ((c & 0x0400) << 16) |
	 ((c & 0x0200) << 19) | ((c & 0x0100) << 22) |
	 ((c & 0x0080) >>  7) | ((c & 0x0040) >>  4) |
	 ((c & 0x0020) >>  1) | ((c & 0x0010) <<  2) |
	 ((c & 0x0008) <<  5) | ((c & 0x0004) <<  8) |
	 ((c & 0x0002) << 11) | ((c & 0x0001) << 14);

    return (hi | lo);
}

/*
 * The inverse, through the two tables rather than through unrolled
 * shifts.  The kernel half does this job with the shifts and no tables;
 * the trade is deliberate and the two halves are not to be harmonized.
 */
void
write_bpp2packed_to_bpp4planar(unsigned int v, void *addr)
{
    select_write_plane(1);
    *(unsigned short *)addr = (oddTable[(v >> 16) & 0xaaaa] << 8) |
			       oddTable[v & 0xaaaa];
    select_write_plane(0);
    *(unsigned short *)addr = (evenTable[(v >> 16) & 0x5555] << 8) |
			       evenTable[v & 0x5555];
}

/*
 * Fill evenTable and oddTable, once.  Each gathers the eight even or odd
 * bits of a 16 bit half of a packed word into the eight plane bits it
 * produces, most significant pixel first, and complements the result.
 * The guard is incremented rather than set, so a second call would leave
 * it at two; the only test is against zero and there is one caller.
 */
static void
build_tables(void)
{
    unsigned int	c, v;

    for (c = 0; c <= 0xffff; c++) {
	v = ((c & 0x4000) >> 14) | ((c & 0x1000) >> 11) |
	    ((c & 0x0400) >>  8) | ((c & 0x0100) >>  5) |
	    ((c & 0x0040) >>  2) | ((c & 0x0010) <<  1) |
	    ((c & 0x0004) <<  4) | ((c & 0x0001) <<  7);
	evenTable[c] = ~v;

	v = ((c & 0x8000) >> 15) | ((c & 0x2000) >> 12) |
	    ((c & 0x0800) >>  9) | ((c & 0x0200) >>  6) |
	    ((c & 0x0080) >>  3) |  (c & 0x0020)        |
	    ((c & 0x0008) <<  3) | ((c & 0x0002) <<  6);
	oddTable[c] = ~v;
    }
    tablesBuilt++;
}

/*
 * Program the six standard register sets.  Mode 5 is 640x480x16, BIOS
 * mode 0x12, and the only one VGAStart ever asks for.  A negative mode is
 * not checked and would read before the tables; only mode > 5 is refused,
 * and the refusal value is 1, not an IOReturn.
 */
int
VGASetStdRegs(int mode)
{
    unsigned int	i;

    if (mode > 5)
	return (1);

    inb(0x3da);					/* reset the AC flip flop */
    outb(0x3c0, 0);				/* and blank the screen	  */

    outb(0x3c2, miscTable[mode]);

    for (i = 0; i <= 4; i++) {
	outb(0x3c4, i);
	outb(0x3c5, seqTable[mode][i]);
    }
    outb(0x3c4, 0);				/* release sequencer reset */
    outb(0x3c5, 3);

    outb(0x3d4, 0x11);				/* unprotect CRTC 0 to 7   */
    outb(0x3d5, 0);
    for (i = 0; i <= 0x18; i++) {
	outb(0x3d4, i);
	outb(0x3d5, crtcTable[mode][i]);
    }

    inb(0x3da);
    for (i = 0; i <= 0x13; i++) {
	outb(0x3c0, i);
	outb(0x3c0, acTable[mode][i]);
    }

    for (i = 0; i <= 8; i++) {
	outb(0x3ce, i);
	outb(0x3cf, gcTable[mode][i]);
    }

    inb(0x3da);
    outb(0x3c0, 0x20);				/* unblank		   */
    return (0);
}
