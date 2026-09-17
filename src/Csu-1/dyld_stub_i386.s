/*
 * i386 MH_DYLINKER stub. Paired with dyld_stub.s (ppc) so fat crt1.o
 * and /usr/lib/dyld contain an i386 slice. ld only needs LC_ID_DYLINKER.
 */
	.text
	.align 2,0x90
	.globl _start
_start:
	ret
