/* Copyright (c) 1996-1998 by NeXT Software, Inc. as an unpublished work.
 * All rights reserved.
 *
 * vidBIOS.m -- the real-mode video BIOS call class.
 *
 * vidBIOS wraps emu486 (emu486.s), the hand-written real-mode interpreter
 * that runs int 10h BIOS calls on its behalf. It maps the low megabyte,
 * allocates a BIOS stack inside it, builds the page and I/O permission
 * arrays the emulator polices, and reads the live interrupt vector 10h
 * out of the mapped IVT to find the ROM's entry point.
 *
 * This translation unit contributes no __data, no __const and no
 * file-static counters of its own. It does include
 * driverkit/i386/ioPorts.h so gcc emits the unused _xxx.8 / .11 / .14
 * triple at __bss 26596/26600/26604; VGA's vidBIOS.m does not include
 * that header.
 */

#import "IBMThinkPad760ED.h"

#import <driverkit/i386/kernelDriver.h>
#import <driverkit/i386/ioPorts.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

#import <string.h>

/*
 * The kernel's page size.  No driver header declares it; drvPCFloppy's
 * FloppyArch.m spells it the same way.
 */
extern unsigned int	page_size;

@implementation vidBIOS

/* Every failure path returns [self free], which is nil; the compiler
 * cross-jumps the four of them into one tail, which is why there is no
 * shared `fail' label here -- writing one costs a stack adjustment the
 * reference does not have.
 */
- init
{
    biosStackVirtual = IOMallocLow(page_size);
    if (biosStackVirtual == NULL) {
	IOLog("%s: can't allocate low memory region\n", [self name]);
	return [self free];
    }
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)biosStackVirtual,
			      &biosStackPhysical)) {
	IOLog("%s: failed to wire down low memory region\n", [self name]);
	biosStackPhysical = 0;
	return [self free];
    }
    if (biosStackPhysical & 0xFFF00000) {
	IOLog("%s: can't allocate memory region in the lower 1MB\n",
	      [self name]);
	return [self free];
    }
    if (IOMapPhysicalIntoIOTask(0, 0x100000, &lowMem)) {
	IOLog("%s: can't map lower 1MB\n", [self name]);
	lowMem = 0;
	return [self free];
    }
    return [super init];
}

/* Idempotent, which is what lets init call it on any failure path. */
- free
{
    if (biosStackVirtual) {
	IOFreeLow(biosStackVirtual, page_size);
	biosStackVirtual = NULL;
    }
    if (lowMem) {
	IOUnmapPhysicalFromIOTask(lowMem, 0x100000);
	lowMem = 0;
    }
    return [super free];
}

/* The five-argument BIOS call; everything else forwards here.
 *
 * inregs and outregs are routinely the same block, so the incoming
 * registers are copied into a local before emu486 is allowed to write
 * anything back.
 */
- (int)int10	: (const emu486regs_t *)inregs
	outregs	: (emu486regs_t *)outregs
	iorange	: (const IORange *)ranges
	  ionum	: (int)nranges
	smmport	: (unsigned int)smmport
{
    emu486regs_t	r;
    char		pagePerm[256];
    char	       *ioPerm;
    int			i, port, end, err;

    /*
     * One byte per 4 KB page of the low megabyte.  The guest may touch the
     * IVT/BDA page, the 384 KB of video RAM and BIOS ROM, and its own
     * stack, and nothing else.
     */
    memset(pagePerm, 0, 256);
    pagePerm[0] = 1;
    for (i = 0xA0; i <= 0xFF; i++)
	pagePerm[i] = 1;
    for (i = biosStackPhysical >> 12;
	 i < (biosStackPhysical + page_size) >> 12; i++)
	pagePerm[i] = 1;

    /* One bit per I/O port; no range list at all means all of them. */
    ioPerm = IOMalloc(0x2000);
    if (ranges != NULL) {
	memset(ioPerm, 0, 0x2000);
	while (nranges--) {
	    end = ranges->start + ranges->size;
	    for (port = ranges->start; port < end; port++) {
		/* The reference's port-range compares are signed and this
		 * one is not, so the cast is real, not decoration.
		 */
		if ((unsigned int)port > 0xFFFF)
		    continue;
		ioPerm[port / 8] |= 1 << (port & 7);
	    }
	    ranges++;
	}
    } else
	memset(ioPerm, 0xFF, 0x2000);

    r = *inregs;

    /* Real-mode interrupt vector 0x10, out of the live IVT. */
    r.eip = *(unsigned short *)(lowMem + 0x40);
    r.cs = *(unsigned short *)(lowMem + 0x42);

    /*
     * The two zeroes at the top of the BIOS stack are the fake far return
     * address 0000:0000 that emu486 uses as its termination condition.
     */
    *(unsigned int *)(lowMem + biosStackPhysical + page_size - 4) = 0;
    *(unsigned int *)(lowMem + biosStackPhysical + page_size - 8) = 0;
    r.ss = biosStackPhysical >> 4;
    r.esp = page_size - 8;

    err = emu486((void *)lowMem, &r, outregs, pagePerm, ioPerm, smmport);
    if (err) {
	IOLog("%s: emu486 error %08x before %04x:%04x\n", [self name],
	      err, outregs->cs, outregs->eip);
	IOLog("%s: eax=%08x ebx=%08x ecx=%08x edx=%08x\n", [self name],
	      outregs->eax, outregs->ebx, outregs->ecx, outregs->edx);
	IOLog("%s: esi=%08x edi=%08x ebp=%08x esp=%08x\n", [self name],
	      outregs->esi, outregs->edi, outregs->ebp, outregs->esp);
	IOLog("%s: ds=%04x es=%04x fs=%04x gs=%04x ss=%04x\n", [self name],
	      outregs->ds, outregs->es, outregs->fs, outregs->gs,
	      outregs->ss);
    }
    IOFree(ioPerm, 0x2000);
    return err;
}

/* 0x10000 is one past the top of the 16-bit port space and means "no
 * SMM port".
 */
- (int)int10	: (const emu486regs_t *)inregs
	outregs	: (emu486regs_t *)outregs
	iorange	: (const IORange *)ranges
	  ionum	: (int)nranges
{
    return [self int10:inregs outregs:outregs iorange:ranges ionum:nranges
		smmport:0x10000];
}

- (unsigned int)scratchSegment
{
    return biosStackPhysical >> 4;
}

- (void *)realToVirtual:(unsigned int)segment :(unsigned int)offset
{
    return (void *)((segment << 4) + lowMem + offset);
}

@end
