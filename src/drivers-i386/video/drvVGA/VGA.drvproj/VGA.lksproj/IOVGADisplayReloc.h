/* Copyright (c) 1992 by NeXT Computer, Inc.
 * All rights reserved.
 *
 * IOVGADisplayReloc.h -- private declarations shared by IOVGADisplay.m
 * and vidBIOS.m.
 *
 * Not to be confused with driverkit/IOVGADisplayPrivate.h (checked in,
 * NeXT's own header), which carries the ET4000 register macros and
 * palette constants the reference was compiled against -- this file pulls
 * that header in, alongside the public class header and IOVGAShared.h,
 * and adds the two things the two translation units have to agree on:
 * the emulator's register block and the vidBIOS interface.
 *
 * driverkit/i386/ioPorts.h is deliberately NOT imported here.  Its outb(),
 * outw() and outl() each carry a `static int xxx', so every translation
 * unit that includes it emits its own _xxx.N triple.  The reference has
 * exactly one such triple, so exactly one file may include that header,
 * and that file is IOVGADisplay.m.
 */

#ifndef IOVGADISPLAYRELOC_H__
#define IOVGADISPLAYRELOC_H__

#import <objc/Object.h>

#import <driverkit/driverTypes.h>
#import <driverkit/IOVGADisplay.h>
#import <driverkit/IOVGADisplayPrivate.h>
#import <driverkit/IOVGAShared.h>

/*
 * The sixteen-register block emu486 exchanges with its caller.  Untagged
 * on purpose: the reference's method type encodings are
 * `{?=IIIIIIIIIIIIIIII}'.  The order is plain modrm register numbering
 * followed by eip, eflags and the six segment registers, fixed by the
 * emulator's own 8-bit register pointer table and by the four IOLog
 * argument lists on the failure path of the five-argument int10:.
 */
typedef struct {
    unsigned int	eax, ecx, edx, ebx;
    unsigned int	esp, ebp, esi, edi;
    unsigned int	eip, eflags;
    unsigned int	es, cs, ss, ds, fs, gs;
} emu486regs_t;

/*
 * The real-mode interpreter itself, in emu486.s.  lowMemBase is the
 * caller's virtual mapping of guest physical 0; pagePerm is one byte per
 * 4 KB page of the low megabyte; ioPerm is one bit per I/O port; smmport
 * is a single port the emulator treats specially, or 0x10000 for none.
 * Returns 0 on a clean return to 0000:0000, otherwise a tagged error.
 */
extern int	emu486(void *lowMemBase, const emu486regs_t *inregs,
		       emu486regs_t *outregs, const char *pagePerm,
		       const char *ioPerm, unsigned int smmport);

@interface vidBIOS : Object
{
    void	       *biosStackVirtual;
    unsigned int	biosStackPhysical;
    unsigned int	lowMem;
}
- init;
- free;
- (int)int10	: (const emu486regs_t *)inregs
	outregs	: (emu486regs_t *)outregs
	iorange	: (const IORange *)ranges
	  ionum	: (int)nranges;
- (int)int10	: (const emu486regs_t *)inregs
	outregs	: (emu486regs_t *)outregs
	iorange	: (const IORange *)ranges
	  ionum	: (int)nranges
	smmport	: (unsigned int)smmport;
- (unsigned int)scratchSegment;
- (void *)realToVirtual:(unsigned int)segment :(unsigned int)offset;
@end

/*
 * Methods of IOVGADisplay itself that no framework header declares.
 * This is an interface-only category: it produces no __OBJC,__category
 * record, and both methods are implemented in @implementation
 * IOVGADisplay, which is where the reference's thirteen instance methods
 * all live.
 */
@interface IOVGADisplay (Private)
- (IOReturn)_registerWithED;
/* char *, not const char *: the reference's type encoding is
 * `*12@8:12^I16', with no leading `r'.
 */
- (char *)generateNameAndUnit:(unsigned int *)unit;
@end

/* The (VESAMode) category, one translation unit with the class. */
@interface IOVGADisplay (VESAMode)
- (void)enterSVGAMode:(unsigned int)mode;
- (int)int10:(emu486regs_t *)regs;
- (BOOL)didBootWithDefaultConfig;
@end

/*
 * The console interface.  -[IOVGADisplay allocateConsoleInfo] hands the
 * kernel's VGAConsole.c a vector of entry points that reach back into
 * this driver, which is why these five variables and these six functions
 * are exported rather than static.  colr_mode is also what
 * IOVGADisplayPrivate.h's vga_acr_out / vga_acr__in macros test.
 */
extern int	colr_mode;
extern int	curr_read_plane;
extern int	curr_write_plane;
extern int	curr_read_segment;
extern int	curr_write_segment;

/*
 * The four selects take a char and are declared and defined without a
 * prototype, which is not tidiness lost but a requirement of the reference:
 * with a prototype in scope gcc converts each argument to char and back,
 * and the two cursor blitters would carry a movsbl before every one of
 * their eight calls.  The reference has none -- it pushes the int straight
 * -- so the callers see only the default argument promotions.  The bodies
 * are unaffected either way; they read the low byte of the incoming word.
 */
extern void	select_read_segment();
extern void	select_write_segment();
extern void	select_read_plane();
extern void	select_write_plane();
extern void	vga_read_bpp4planar_to_bpp2packed32(unsigned short *fb,
						    unsigned int *dst);
extern void	vga_write_bpp2packed32_to_bpp4planar(unsigned int *src,
						     unsigned short *fb);

extern void	VGADisplayCursor(IODisplayInfo *di, VGAShmem_t *shmem);
extern void	VGARemoveCursor(IODisplayInfo *di, VGAShmem_t *shmem);

#endif	/* IOVGADISPLAYRELOC_H__ */
