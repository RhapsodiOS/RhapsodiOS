/*
 * Minimal MH_DYLINKER body for -r merge into crt1.o when the host
 * /usr/lib/dyld cannot be linked (broken indirect symbol table).
 * ld only needs LC_ID_DYLINKER from this file.
 */
	.text
	.align 2
	.globl _start
_start:
	blr
