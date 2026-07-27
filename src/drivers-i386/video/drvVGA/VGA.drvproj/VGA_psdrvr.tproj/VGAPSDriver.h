/* Copyright (c) 1993 by NeXT Computer, Inc.
 * All rights reserved.
 *
 * VGAPSDriver.h -- the VGA display bundle the Window Server loads.
 *
 * This declares everything the bundle exports and nothing else: nineteen
 * function symbols over eighteen bodies, and the seven frame buffer
 * globals the Window Server reads directly.  Every other body in
 * VGAPSDriver.c is static and is reached only through the driver vector.
 */

#ifndef VGAPSDRIVER_H__
#define VGAPSDRIVER_H__

#import <mach/mach_types.h>
#import <driverkit/IOVGAShared.h>

/*
 * The Window Server's own records.  No header for any of them exists in
 * this tree and their layouts are the Window Server's, not this driver's,
 * so they stay opaque here; the driver only ever holds pointers.
 *
 *   NXScreen     the screen descriptor VGAStart fills in
 *   NXScreenDev  the screen device record every vector entry receives
 *   bitmap       an imaging machine's bitmap
 */
typedef struct NXScreen		NXScreen;
typedef struct NXScreenDev	NXScreenDev;
typedef struct bitmap		bitmap;

/*
 * Frame buffer geometry, filled in by VGAStart, plus the screen bounds
 * that the vector's initialize entry publishes.  All seven are tentative
 * definitions in VGAPSDriver.c so that they land in __DATA,__common.
 */
extern int		vga_width;	/* pixels across			*/
extern int		vga_height;	/* scan lines			*/
extern int		vga_rowbytes;	/* bytes per line of the 2 bpp shadow */
extern int		vga_bpl;	/* bytes per line of one VGA plane */
extern Bounds		vgaBounds;	/* the screen's bounds; zero until
					   the vector's initialize entry runs */
extern vm_address_t	vgaAddress;	/* 128K device mapping of 0xA0000 */
extern void	       *vgaVirtualAddress; /* the malloc'd 2 bpp shadow	*/

/*
 * The entry point.  The Window Server resolves the fixed name Start;
 * VGAStart is the same body under its descriptive name, not a wrapper.
 */
int	VGAStart(NXScreen *screen);
int	Start(NXScreen *screen);

/*
 * The seven public cursor entries, reached through the driver vector.
 * Each takes cursorSema for the duration and blocks if it is held.
 */
void	VGASetCursor(NXScreenDev *dev, bitmap *src, Point hot, int frame,
		     int *flagp);
void	VGAHideCursor(NXScreenDev *dev);
void	VGAShowCursor(NXScreenDev *dev);
void	VGAObscureCursor(NXScreenDev *dev);
void	VGARevealCursor(NXScreenDev *dev);
void	VGAShieldCursor(NXScreenDev *dev, Bounds *r);
void	VGAUnshieldCursor(NXScreenDev *dev);

/*
 * The cursor primitives.  These do not touch the lock; every caller
 * already holds it.  Exported only because everything in this file is.
 */
void	VGASysHideCursor(NXScreenDev *dev);
void	VGASysShowCursor(NXScreenDev *dev);
void	VGACheckShield(NXScreenDev *dev);

/*
 * The VGA hardware layer.
 */
int	VGASetStdRegs(int mode);
void	set_colormap(void);
void	get_addr_range(void **addr);
void	fill_64K_plane(short value);
void	vga_at_mode12_bpp2_to_bpp4(Bounds *r);
unsigned int read_bpp4planar_to_bpp2packed(const void *addr);
void	write_bpp2packed_to_bpp4planar(unsigned int v, void *addr);

#endif /* VGAPSDRIVER_H__ */
