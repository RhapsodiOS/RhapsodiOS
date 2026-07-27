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

/*
 * IO port access.
 *
 * The dummy "=m" operand is an automatic, not a static, so the compiler
 * emits `lock incl -4(%ebp)' rather than a reference to a file-scope
 * integer.  Do not reach for <driverkit/i386/ioPorts.h> here: its outb
 * declares `static int xxx' and its inb has no dummy at all.
 */
static __inline__ unsigned char
inb(unsigned short port)
{
    unsigned char	data;
    int			xxx;

    asm volatile(
	"inb %2,%0; lock; incl %1"

	: "=a" (data), "=m" (xxx)
	: "d" (port), "1" (xxx)
	: "cc");

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

/*
 * The Window Server's four imaging machine class objects, one per pixel
 * format.  These are imported data, not code: the driver takes their
 * addresses for the class table below and dereferences only _bm12.  The
 * other three exist so the Window Server can ask for an offscreen bitmap
 * at a depth this screen does not use.
 */
typedef struct bmClass	bmClass;

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

/* Caller holds cursorSema. */
void
VGASysHideCursor(NXScreenDev *dev)
{
}

/* Caller holds cursorSema. */
void
VGASysShowCursor(NXScreenDev *dev)
{
}

/* Caller holds cursorSema. */
void
VGACheckShield(NXScreenDev *dev)
{
}

void
VGASetCursor(NXScreenDev *dev, bitmap *src, Point hot, int frame, int *flagp)
{
}

void
VGAHideCursor(NXScreenDev *dev)
{
}

void
VGAShowCursor(NXScreenDev *dev)
{
}

void
VGAObscureCursor(NXScreenDev *dev)
{
}

void
VGARevealCursor(NXScreenDev *dev)
{
}

void
VGAShieldCursor(NXScreenDev *dev, Bounds *r)
{
}

void
VGAUnshieldCursor(NXScreenDev *dev)
{
}

/* Draw the cursor, saving what it covers into cursor.bw.save. */
static void
VGADisplayCursorBlit(NXScreenDev *dev)
{
}

/* Erase the cursor, restoring from cursor.bw.save. */
static void
VGARemoveCursorBlit(NXScreenDev *dev)
{
}

void
set_colormap(void)
{
}

/* Graphics Controller index 4: which plane reads come from. */
static void
select_read_plane(int plane)
{
}

/* Sequencer index 2: a one hot mask, so only one plane is written. */
static void
select_write_plane(int plane)
{
}

void
get_addr_range(void **addr)
{
}

void
fill_64K_plane(short value)
{
}

/* The flush.  Every drawing operation ends here. */
void
vga_at_mode12_bpp2_to_bpp4(Bounds *r)
{
}

unsigned int
read_bpp4planar_to_bpp2packed(const void *addr)
{
    return (0);
}

void
write_bpp2packed_to_bpp4planar(unsigned int v, void *addr)
{
}

/* Fill evenTable and oddTable, once. */
static void
build_tables(void)
{
}

int
VGASetStdRegs(int mode)
{
    return (0);
}
