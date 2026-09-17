/* Copyright (c) 1996-1998 by NeXT Software, Inc. as an unpublished work.
 * All rights reserved.
 *
 * smapi.s -- the SMAPI trap for the IBM ThinkPad 760ED display driver.
 *
 * The ThinkPad system management API is entered by writing the function
 * code in AL to the model-specific SMAPI port, whose number the driver
 * reads out of CMOS 0x7E/0x7F, and then to the fixed port 0x4F. The SMM
 * handler reads its arguments out of the 16-bit registers and writes its
 * results back into the same ones, so the whole register file has to be
 * loaded before the trap and stored after it.
 *
 * The register block is the driver's `reg' instance variable:
 *
 *	struct smapiReg {
 *	    union {
 *		unsigned int e;
 *		unsigned short x;
 *		struct { unsigned char l, h; } b;
 *	    } ax, bx, cx, dx, si, di;
 *	};
 *
 *	extern void smapi_asm(struct smapiReg *r);
 *
 * `dx' carries the SMAPI port in and the handler's DX out. Nothing is
 * returned in EAX; every caller reads its results out of the block.
 */

	.text
	.align	2
	.globl	_smapi_asm
_smapi_asm:
	pushl	%ebp
	movl	%esp, %ebp
	pushl	%edi
	pushl	%esi
	pushl	%ebx

	movl	8(%ebp), %eax		/* struct smapiReg *r		*/
	movw	(%eax), %bx		/* r->ax.x, but bx is wanted	*/
	pushw	%bx			/*   for r->bx.x, so stash it	*/
	movw	4(%eax), %bx
	movw	8(%eax), %cx
	movw	12(%eax), %dx		/* the SMAPI port		*/
	movw	16(%eax), %si
	movw	20(%eax), %di
	popw	%ax

	outb	%al, %dx		/* enter SMM			*/
	outb	%al, $0x4f

	pushw	%ax			/* eax is about to be reloaded	*/
	movl	8(%ebp), %eax
	movw	%bx, 4(%eax)
	movw	%cx, 8(%eax)
	movw	%dx, 12(%eax)
	movw	%si, 16(%eax)
	movw	%di, 20(%eax)
	movl	%eax, %ebx
	popw	%ax
	movw	%ax, (%ebx)		/* r->ax.x last			*/

	jmp	Lreturn
	.align	2, 0x90
Lreturn:
	leal	-12(%ebp), %esp
	popl	%ebx
	popl	%esi
	popl	%edi
	movl	%ebp, %esp
	popl	%ebp
	ret
