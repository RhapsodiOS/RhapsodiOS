/*
 * smp_tramp.s
 * Where a started processor begins: real mode, at the page the start-up
 * IPI names, with CS = page >> 4 and IP = 0.
 *
 * The 16-bit part is spelled in bytes because the assembler here does
 * not take 16-bit code.  It loads a temporary GDT kept in the same page,
 * turns protection on and jumps into the 32-bit part, which loads the
 * kernel's page directory, turns paging on, switches to the kernel's own
 * GDT and IDT, takes the stack it was given and calls smp_ap_main().
 * smp.c copies the code to the page and fills in the parameter block at
 * its end; see the SMP_TRAMP_* offsets there.
 */

	.text
	.align	4
	.globl	_smp_tramp_start
	.globl	_smp_tramp_ljmp
	.globl	_smp_tramp_end

_smp_tramp_start:
	.byte	0xFA			/* cli				*/
	.byte	0x8C, 0xC8		/* movw	%cs,%ax			*/
	.byte	0x8E, 0xD8		/* movw	%ax,%ds			*/
	.byte	0x66, 0x0F, 0x01, 0x16	/* lgdtl %ds:0x0F40  (32-bit base)	*/
	.word	0x0F40
	.byte	0x0F, 0x20, 0xC0	/* movl	%cr0,%eax		*/
	.byte	0x66, 0x83, 0xC8, 0x01	/* orl	$1,%eax			*/
	.byte	0x0F, 0x22, 0xC0	/* movl	%eax,%cr0		*/
	.byte	0x66, 0xEA		/* ljmpl $0x08,$tramp32		*/
_smp_tramp_ljmp:
	.long	0			/* page + (tramp32 - start), patched */
	.word	0x08

	.align	4
tramp32:
	movw	$0x10,%ax
	movw	%ax,%ds
	movw	%ax,%es
	movw	%ax,%ss
	movw	%ax,%fs
	movw	%ax,%gs

	/* Find the page this runs from. */
	call	1f
1:	popl	%ebx
	andl	$0xFFFFF000,%ebx

	/* The kernel's page directory, then paging on. */
	movl	0x0F00(%ebx),%eax
	movl	%eax,%cr3
	movl	%cr0,%eax
	orl	$0x80000000,%eax
	movl	%eax,%cr0

	/* The kernel's descriptor tables; kernel code is also 0x08. */
	lgdt	0x0F10(%ebx)
	lidt	0x0F18(%ebx)
	ljmp	*0x0F30(%ebx)
2:	movw	$0x10,%ax
	movw	%ax,%ds
	movw	%ax,%es
	movw	%ax,%ss
	movw	%ax,%fs
	movw	%ax,%gs

	movl	0x0F20(%ebx),%esp
	pushl	0x0F24(%ebx)
	call	*0x0F28(%ebx)
3:	hlt
	jmp	3b

	.globl	_smp_tramp_entry32
_smp_tramp_entry32:
	.long	tramp32 - _smp_tramp_start
	.globl	_smp_tramp_reload
_smp_tramp_reload:
	.long	2b - _smp_tramp_start
	.align	4
_smp_tramp_end:
