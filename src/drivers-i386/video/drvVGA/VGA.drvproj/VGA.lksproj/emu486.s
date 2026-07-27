/*
 * emu486.s -- the 8086 emulator that runs real-mode VGA BIOS calls for
 * vidBIOS.
 *
 * Hand-written i386 assembly in the reference, not compiled C -- see
 * divergences.md, the _emu486 section, for the seven independent findings
 * that established this.  This is a scaffolding stub: Task 7 of Phase 3b
 * writes the emulator body.  Named through no pb_makefiles source variable
 * (this vintage's common.make has none for .s), so vm/build-i386-vga.sh
 * assembles this file explicitly and hands the object to the kernelserver
 * link through OPTIONAL_LDFLAGS.
 */
	.text
	.align	2,0x90
	.globl	_emu486
_emu486:
	ret
