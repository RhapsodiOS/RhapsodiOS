/* Copyright (c) 1992 by NeXT Computer, Inc.
 * All rights reserved.
 *
 * vidBIOS.m -- the real-mode VGA BIOS call class.
 *
 * vidBIOS wraps emu486 (emu486.s), the hand-written real-mode interpreter
 * that runs int 10h BIOS calls on its behalf.  It maps the low megabyte,
 * allocates a BIOS stack inside it, builds the page and I/O permission
 * arrays the emulator polices, and reads the live interrupt vector 10h
 * out of the mapped IVT to find the ROM's entry point.
 *
 * The reference's vidBIOS.m contributes no __data, no __bss, no __const
 * and no statics of any kind -- it holds nothing but these six methods.
 * It also does not include driverkit/i386/ioPorts.h; the binary has
 * exactly one _xxx.100 / .103 / .106 triple and it belongs to
 * IOVGADisplay.m.
 *
 * Phase 3b Task 2 laid down the class; the bodies are stubs that Task 6
 * replaces.
 */

#import "IOVGADisplayReloc.h"

#import <driverkit/i386/kernelDriver.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

@implementation vidBIOS

/* Finding 30. */
- init
{
    return [super init];
}

/* Finding 31.  Idempotent, which is what lets init call it on any
 * failure path.
 */
- free
{
    return [super free];
}

/* Finding 32.  The five-argument BIOS call; everything else forwards
 * here.
 */
- (int)int10	: (const emu486regs_t *)inregs
	outregs	: (emu486regs_t *)outregs
	iorange	: (const IORange *)ranges
	  ionum	: (int)nranges
	smmport	: (unsigned int)smmport
{
    return 0;
}

/* Finding 33.  0x10000 is one past the top of the 16-bit port space and
 * means "no SMM port".
 */
- (int)int10	: (const emu486regs_t *)inregs
	outregs	: (emu486regs_t *)outregs
	iorange	: (const IORange *)ranges
	  ionum	: (int)nranges
{
    return 0;
}

/* Finding 34.  Uncalled within this binary; part of the published
 * interface.
 */
- (unsigned int)scratchSegment
{
    return 0;
}

/* Finding 35.  Also uncalled within this binary. */
- (void *)realToVirtual:(unsigned int)segment :(unsigned int)offset
{
    return 0;
}

@end
