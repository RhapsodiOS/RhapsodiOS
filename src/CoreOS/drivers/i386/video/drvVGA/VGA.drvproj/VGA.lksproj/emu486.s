/*
 * emu486.s -- the real-mode 8086/386 interpreter that runs VGA BIOS calls
 * for vidBIOS.
 *
 * Hand-written i386 assembly in the reference, not compiled C.  See
 * reconstruction/divergences.md, the `_emu486' section, for the seven
 * independent findings that established this: no frame pointer, an unnamed
 * 92-byte state block in __DATA,__data rather than __bss, daa/das/aaa/aas
 * driven by the guest's flags through sahf, pushf/popf around the loop,
 * internal subroutines that take register arguments and pop their own
 * return addresses, and table-driven computed jumps.
 *
 * This file is a transcription of __text 7552..18048 of Apple's VGA_reloc,
 * read from a linear disassembly with the jump tables decoded -- no
 * analyzer's interior function boundaries were trusted.  Labels are named
 * for the reference address they sit at, so `L1e20' is the shared dispatch
 * point at reference __text 0x1E20.  They are all `L'-prefixed, which the
 * assembler keeps out of the symbol table, exactly as in the reference:
 * `_emu486' is the only symbol this file defines.
 *
 * Entry contract, from -[vidBIOS int10:outregs:iorange:ionum:smmport:]:
 *
 *	int emu486(void *lowMemBase, const regs_t *inregs, regs_t *outregs,
 *		   const char *pagePerm, const char *ioPerm,
 *		   unsigned int smmport);
 *
 * lowMemBase is the caller's virtual mapping of guest physical 0; pagePerm
 * is one byte per 4 KB page of the low megabyte, nonzero meaning the guest
 * may touch it; ioPerm is one bit per I/O port, set meaning permitted.
 * vidBIOS passes the same register block as both inregs and outregs.
 * On entry the six segment registers are converted in place from real-mode
 * selectors to host linear addresses (shl 4, add lowMemBase) and on exit
 * the conversion is undone.  esi holds the linear instruction pointer
 * throughout and bl the current operand size in bytes, 2 or 4.
 *
 * The loop finishes when esi comes back equal to lowMemBase, i.e. when the
 * guest returns to 0000:0000, and returns 0.  Otherwise the result is a
 * tagged word: 0x01000000 for an unimplemented or invalid opcode,
 * 0x02000000|offset for a data access pagePerm does not allow,
 * 0x03000000|port for an I/O access ioPerm does not allow, and 0x04000000
 * for an effective address at or above 0x10000.
 *
 * Three defects in Apple's binary are transcribed as written rather than
 * repaired, because repairing them would change behaviour on paths the
 * shipped driver never took:
 *
 *   1. Ltab_4640 slot 11 points at a `setno' stub where the condition order
 *      calls for `setnp', so guest JNP/JPO, SETNP/SETPO and LOOPNP evaluate
 *      as "not overflow".  All fifteen other slots are correct.
 *   2. The 32-bit CMPS handler's repeat-prefix test at L2a81 branches to
 *      L2ad7 -- the middle of the 32-bit TEST handler -- instead of to the
 *      "is it 0xF3" test at L2a8e, so CMPSD and REPE CMPSD are mishandled.
 *      The 16-bit path immediately above it is correct.
 *   3. The 32-bit SCAS handler's repeat-prefix test at L2d06 branches to
 *      L2e48, the 32-bit ROL handler, instead of to L2d17, so SCASD and
 *      REPE SCASD are mishandled.  This is the only 32-bit displacement in
 *      the whole function that carries no relocation, i.e. the only branch
 *      whose operand the reference's assembler resolved as a constant.
 *
 * The blocks at L2a8e and L2d17 are unreachable because of defects 2 and 3;
 * they are kept so the byte stream matches.
 *
 * Two encodings are written out by hand.  cmpxchg is emitted as the i486
 * A-step 0F A6 / 0F A7 opcodes, which is what the reference contains, and
 * every branch to one of the shared tails is emitted in the long form,
 * which is what the reference contains even where a short displacement
 * would reach.  Both are pinned so the assembler cannot choose otherwise.
 *
 * Named through no pb_makefiles source variable (this vintage's common.make
 * has none for .s), so vm/build-i386-vga.sh assembles this file explicitly
 * and hands the object to the kernelserver link through OPTIONAL_LDFLAGS.
 */
	.text
	.align	2,0x00

/*
 * entry: stash the five arguments, copy the guest register block in,
 * convert the six real-mode segment selectors to host linear addresses,
 * save the host flags and start interpreting
 */
	.globl	_emu486
_emu486:
	pushl	%ebx
	pushl	%esi
	pushl	%edi
	movl	0x1c(%esp),%eax
	movl	%eax,Lpageperm
	movl	0x20(%esp),%eax
	movl	%eax,Lioperm
	movl	0x24(%esp),%eax
	movl	%eax,Lsmmport
	movl	0x10(%esp),%eax
	movl	%eax,Lstate
	movl	0x14(%esp),%esi
	movl	$Lregs,%edi
	movl	$0x10,%ecx
	rep; movsl
	shll	$4,Lsregs+12
	addl	%eax,Lsregs+12
	shll	$4,Lsregs
	addl	%eax,Lsregs
	shll	$4,Lsregs+4
	addl	%eax,Lsregs+4
	shll	$4,Lsregs+8
	addl	%eax,Lsregs+8
	shll	$4,Lsregs+16
	addl	%eax,Lsregs+16
	shll	$4,Lsregs+20
	addl	%eax,Lsregs+20
	movl	Leip,%esi
	addl	Lsregs+4,%esi
	pushfl
	popl	%eax
	andl	$0xfffff700,%eax
	movl	%eax,Lhostfl
	xorl	%ebx,%ebx

/*
 * the interpreter loop.  L1e20 re-saves the guest flags, L1e28 is
 * re-entered by handlers that saved them already, and L1e40 fetches the
 * next opcode byte and dispatches on it
 */
	nop
L1e20:
	pushfl
	popl	%eax
	movl	%eax,Leflags
	nop
L1e28:
	cmpl	%esi,Lstate
	.byte	0x0f,0x84		/* je L1e56, long form as in the reference */
	.long	L1e56-.-4
	movl	$0x80c,Ldesc
	movb	$2,%bl
L1e40:
	xorl	%edx,%edx
	movb	(%esi),%dl
	incl	%esi
	jmp	*Ltab_3d90(,%edx,4)

/*
 * the exit path.  L1e4c is the invalid-opcode return, L1e56 the normal
 * one; L1e58 undoes the segment conversion, copies the register block
 * out to outregs and returns eax
 */
L1e4c:
	movl	$0x1000000,%eax
	.byte	0xe9			/* jmp L1e58, long form */
	.long	L1e58-.-4
L1e56:
	xorl	%eax,%eax
L1e58:
	subl	Lsregs+4,%esi
	movl	%esi,Leip
	movl	Lstate,%ebx
	subl	%ebx,Lsregs+12
	shrl	$4,Lsregs+12
	subl	%ebx,Lsregs
	shrl	$4,Lsregs
	subl	%ebx,Lsregs+4
	shrl	$4,Lsregs+4
	subl	%ebx,Lsregs+8
	shrl	$4,Lsregs+8
	subl	%ebx,Lsregs+16
	shrl	$4,Lsregs+16
	subl	%ebx,Lsregs+20
	shrl	$4,Lsregs+20
	movl	$Lregs,%esi
	movl	0x18(%esp),%edi
	movl	$0x10,%ecx
	rep; movsl
	popl	%edi
	popl	%esi
	popl	%ebx
	ret

/*
 * the per-opcode handlers, reached through Ltab_3d90 and the group
 * tables.  They are not uniform: most end by jumping back to L1e20, the
 * rest to one of the other shared tails, and a few simply return
 */
L1ecc:
	call	L3893
	call	L38bc
	movb	(%eax),%cl
L1ed8:
	andb	$0x38,%dl
	jmp	*Ltab_43b0(%edx)
L1ee1:
	addb	%cl,(%edi)
	jmp	L1e20
L1ee8:
	orb	%cl,(%edi)
	jmp	L1e20
L1eef:
	movb	Leflags,%ah
	sahf
	adcb	%cl,(%edi)
	jmp	L1e20
L1efd:
	movb	Leflags,%ah
	sahf
	sbbb	%cl,(%edi)
	jmp	L1e20
L1f0b:
	andb	%cl,(%edi)
	jmp	L1e20
L1f12:
	subb	%cl,(%edi)
	jmp	L1e20
L1f19:
	xorb	%cl,(%edi)
	jmp	L1e20
L1f20:
	cmpb	%cl,(%edi)
	jmp	L1e20
L1f27:
	call	L38a1
	call	L38d4
	movl	(%eax),%ecx
L1f33:
	andb	$0x38,%dl
	jmp	*Ltab_43b0+4(%edx)
L1f3c:
	cmpb	$4,%bl
	je	L1f42
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L1f42:
	addl	%ecx,(%edi)
	jmp	L1e20
L1f49:
	cmpb	$4,%bl
	je	L1f4f
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L1f4f:
	orl	%ecx,(%edi)
	jmp	L1e20
L1f56:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L1f6a
	sahf
	adcw	%cx,(%edi)
	jmp	L1e20
L1f6a:
	sahf
	adcl	%ecx,(%edi)
	jmp	L1e20
L1f72:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L1f86
	sahf
	sbbw	%cx,(%edi)
	jmp	L1e20
L1f86:
	sahf
	sbbl	%ecx,(%edi)
	jmp	L1e20
L1f8e:
	cmpb	$4,%bl
	je	L1f94
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L1f94:
	andl	%ecx,(%edi)
	jmp	L1e20
L1f9b:
	cmpb	$4,%bl
	je	L1fa1
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L1fa1:
	subl	%ecx,(%edi)
	jmp	L1e20
L1fa8:
	cmpb	$4,%bl
	je	L1fae
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L1fae:
	xorl	%ecx,(%edi)
	jmp	L1e20
L1fb5:
	cmpb	$4,%bl
	je	L1fbb
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L1fbb:
	cmpl	%ecx,(%edi)
	jmp	L1e20
L1fc2:
	call	L3893
	call	L38bc
	movb	(%edi),%cl
	movl	%eax,%edi
	jmp	L1ed8
L1fd5:
	call	L38a1
	call	L38d4
	movl	(%edi),%ecx
	movl	%eax,%edi
	jmp	L1f33
L1fe8:
	movb	(%esi),%cl
	incl	%esi
	movl	$Lregs,%edi
	jmp	L1ed8
L1ff5:
	movl	(%esi),%ecx
	addl	%ebx,%esi
	movl	$Lregs,%edi
	jmp	L1f33
L2003:
	movl	Lsregs,%eax
L2008:
	subl	Lstate,%eax
	shrl	$4,%eax
	jmp	L2180
L2016:
	movl	$Lsregs,%ecx
L201b:
	movl	Lregs+16,%edi
	addl	$2,%edi
	movl	%edi,Lregs+16
	addl	Lsregs+8,%edi
	movzwl	-2(%edi),%eax
	shll	$4,%eax
	addl	Lstate,%eax
	movl	%eax,(%ecx)
	jmp	L1e28
L2044:
	movl	Lsregs+4,%eax
	.byte	0xe9			/* jmp L2008, long form */
	.long	L2008-.-4
L204e:
	movb	(%esi),%dl
	incl	%esi
	cmpb	$0x80,%dl
	jb	L1e4c
	cmpb	$0xd0,%dl
	jae	L1e4c
	jmp	*Ltab_44f0-0x200(,%edx,4)
L206a:
	movl	Lsregs+8,%eax
	.byte	0xe9			/* jmp L2008, long form */
	.long	L2008-.-4
L2074:
	movl	$Lsregs+8,%ecx
	.byte	0xe9			/* jmp L201b, long form */
	.long	L201b-.-4
L207e:
	movl	Lsregs+12,%eax
	.byte	0xe9			/* jmp L2008, long form */
	.long	L2008-.-4
L2088:
	movl	$Lsregs+12,%ecx
	.byte	0xe9			/* jmp L201b, long form */
	.long	L201b-.-4
L2092:
	movw	$0,Ldesc
	jmp	L1e40
L20a0:
	movb	Leflags,%ah
	sahf
	.byte	0x8a,0x05		/* movb	Lregs,%al */
	.long	Lregs
	daa
	.byte	0x88,0x05		/* movb	%al,Lregs */
	.long	Lregs
	jmp	L1e20
L20b9:
	movw	$0x404,Ldesc
	jmp	L1e40
L20c7:
	movb	Leflags,%ah
	sahf
	.byte	0x8a,0x05		/* movb	Lregs,%al */
	.long	Lregs
	das
	.byte	0x88,0x05		/* movb	%al,Lregs */
	.long	Lregs
	jmp	L1e20
L20e0:
	movw	$0x808,Ldesc
	jmp	L1e40
L20ee:
	movb	Leflags,%ah
	sahf
	movl	Lregs,%eax
	aaa
	movl	%eax,Lregs
	jmp	L1e20
L2105:
	movw	$0xc0c,Ldesc
	jmp	L1e40
L2113:
	movb	Leflags,%ah
	sahf
	movl	Lregs,%eax
	aas
	movl	%eax,Lregs
	jmp	L1e20
L212a:
	andb	$7,%dl
	leal	Lregs(,%edx,4),%edi
L2134:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L2148
	sahf
	incw	(%edi)
	jmp	L1e20
L2148:
	sahf
	incl	(%edi)
	jmp	L1e20
L2150:
	andb	$7,%dl
	leal	Lregs(,%edx,4),%edi
L215a:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L216e
	sahf
	decw	(%edi)
	jmp	L1e20
L216e:
	sahf
	decl	(%edi)
	jmp	L1e20
L2176:
	andb	$7,%dl
	movl	Lregs(,%edx,4),%eax
L2180:
	cmpb	$4,%bl
	je	L21a2
	movl	Lregs+16,%edi
	subl	$2,%edi
	movl	%edi,Lregs+16
	addl	Lsregs+8,%edi
	movw	%ax,(%edi)
	jmp	L1e28
L21a2:
	movl	Lregs+16,%edi
	subl	$4,%edi
	movl	%edi,Lregs+16
	addl	Lsregs+8,%edi
	movl	%eax,(%edi)
	jmp	L1e28
L21be:
	andb	$7,%dl
	leal	Lregs(,%edx,4),%edi
L21c8:
	cmpb	$4,%bl
	je	L21ee
	movl	Lregs+16,%ecx
	addl	$2,%ecx
	movl	%ecx,Lregs+16
	addl	Lsregs+8,%ecx
	movw	-2(%ecx),%ax
	movw	%ax,(%edi)
	jmp	L1e28
L21ee:
	movl	Lregs+16,%ecx
	addl	$4,%ecx
	movl	%ecx,Lregs+16
	addl	Lsregs+8,%ecx
	movl	-4(%ecx),%eax
	movl	%eax,(%edi)
	jmp	L1e28
L220d:
	cmpb	$4,%bl
	je	L226c
	movl	Lregs+16,%edi
	movl	%edi,%ecx
	subl	$0x10,%edi
	movl	%edi,Lregs+16
	addl	Lsregs+8,%edi
	movl	Lregs+28,%eax
	movl	%eax,(%edi)
	movl	Lregs+24,%eax
	movw	%ax,2(%edi)
	movl	Lregs+20,%eax
	movl	%eax,4(%edi)
	movw	%cx,6(%edi)
	movl	Lregs+12,%eax
	movl	%eax,8(%edi)
	movl	Lregs+8,%eax
	movw	%ax,0xa(%edi)
	movl	Lregs+4,%eax
	movl	%eax,0xc(%edi)
	movl	Lregs,%eax
	movw	%ax,0xe(%edi)
	jmp	L1e28
L226c:
	movl	Lregs+16,%edi
	movl	%edi,%ecx
	subl	$0x20,%edi
	movl	%edi,Lregs+16
	addl	Lsregs+8,%edi
	movl	Lregs+28,%eax
	movl	%eax,(%edi)
	movl	Lregs+24,%eax
	movl	%eax,4(%edi)
	movl	Lregs+20,%eax
	movl	%eax,8(%edi)
	movl	%ecx,0xc(%edi)
	movl	Lregs+12,%eax
	movl	%eax,0x10(%edi)
	movl	Lregs+8,%eax
	movl	%eax,0x14(%edi)
	movl	Lregs+4,%eax
	movl	%eax,0x18(%edi)
	movl	Lregs,%eax
	movl	%eax,0x1c(%edi)
	jmp	L1e28
L22c2:
	cmpb	$4,%bl
	je	L2320
	movl	Lregs+16,%edi
	addl	$0x10,%edi
	movl	%edi,Lregs+16
	addl	Lsregs+8,%edi
	movl	-0x10(%edi),%eax
	movw	%ax,Lregs+28
	shrl	$0x10,%eax
	movw	%ax,Lregs+24
	movl	-0xc(%edi),%eax
	movw	%ax,Lregs+20
	movl	-8(%edi),%eax
	movw	%ax,Lregs+12
	shrl	$0x10,%eax
	movw	%ax,Lregs+8
	movl	-4(%edi),%eax
	movw	%ax,Lregs+4
	shrl	$0x10,%eax
	movw	%ax,Lregs
	jmp	L1e28
L2320:
	movl	Lregs+16,%edi
	addl	$0x20,%edi
	movl	%edi,Lregs+16
	addl	Lsregs+8,%edi
	movl	-0x20(%edi),%eax
	movl	%eax,Lregs+28
	movl	-0x1c(%edi),%eax
	movl	%eax,Lregs+24
	movl	-0x18(%edi),%eax
	movl	%eax,Lregs+20
	movl	-0x10(%edi),%eax
	movl	%eax,Lregs+12
	movl	-0xc(%edi),%eax
	movl	%eax,Lregs+8
	movl	-8(%edi),%eax
	movl	%eax,Lregs+4
	movl	-4(%edi),%eax
	movl	%eax,Lregs
	jmp	L1e28
L2372:
	jmp	L1e4c
L2377:
	jmp	L1e4c
L237c:
	movw	$0x1010,Ldesc
	jmp	L1e40
L238a:
	movw	$0x1414,Ldesc
	jmp	L1e40
L2398:
	movb	$4,%bl
	jmp	L1e40
L239f:
	movb	$0x80,Ldesc+3
	jmp	L1e40
L23ab:
	movl	(%esi),%eax
	addl	%ebx,%esi
	jmp	L2180
L23b4:
	call	L38a1
	call	L38d4
	movl	(%esi),%ecx
	addl	%ebx,%esi
L23c2:
	cmpb	$4,%bl
	je	L23d3
	imulw	(%edi),%cx
	movw	%cx,(%eax)
	jmp	L1e20
L23d3:
	imull	(%edi),%ecx
	movl	%ecx,(%eax)
	jmp	L1e20
L23dd:
	movsbl	(%esi),%eax
	incl	%esi
	jmp	L2180
L23e6:
	call	L38a1
	call	L38d4
	movsbl	(%esi),%ecx
	incl	%esi
	.byte	0xe9			/* jmp L23c2, long form */
	.long	L23c2-.-4
L23f9:
	movl	Lhostfl,%eax
	andl	$0x400,%eax
	orl	Leflags,%eax
	pushl	%eax
	popfl
	movzwl	Lregs+28,%edi
	addl	Lsregs,%edi
	movl	Lregs+8,%edx
	call	L3d69
	movzwl	Lregs+4,%ecx
	cmpb	$2,Ldesc+2
	jne	L2434
	.byte	0xf3
L2434:
	insb
	movw	%cx,Lregs+4
	subl	Lsregs,%edi
	movw	%di,Lregs+28
	cld
	jmp	L1e28
L244f:
	movl	Lhostfl,%eax
	andl	$0x400,%eax
	orl	Leflags,%eax
	pushl	%eax
	popfl
	movzwl	Lregs+28,%edi
	addl	Lsregs,%edi
	movl	Lregs+8,%edx
	call	L3d69
	movzwl	Lregs+4,%ecx
	cmpb	$4,%bl
	je	L2493
	cmpb	$2,Ldesc+2
	jne	L248f
	.byte	0xf3
L248f:
	insw
	jmp	L249e
L2493:
	cmpb	$2,Ldesc+2
	jne	L249d
	.byte	0xf3
L249d:
	insl
L249e:
	movw	%cx,Lregs+4
	subl	Lsregs,%edi
	movw	%di,Lregs+28
	cld
	jmp	L1e28
L24b8:
	pushl	%esi
	movl	Lhostfl,%eax
	andl	$0x400,%eax
	orl	Leflags,%eax
	pushl	%eax
	popfl
	movzwl	Lregs+24,%esi
	movb	Ldesc,%dl
	movl	Lsregs(%edx),%edi
	addl	%edi,%esi
	movl	Lregs+8,%edx
	call	L3d69
	movzwl	Lregs+4,%ecx
	cmpb	$2,Ldesc+2
	jne	L24fc
	.byte	0xf3
L24fc:
	outsb
	movw	%cx,Lregs+4
	subl	%edi,%esi
	movw	%si,Lregs+24
	popl	%esi
	cld
	jmp	L1e28
L2514:
	pushl	%esi
	movl	Lhostfl,%eax
	andl	$0x400,%eax
	orl	Leflags,%eax
	pushl	%eax
	popfl
	movzwl	Lregs+24,%esi
	movb	Ldesc,%dl
	movl	Lsregs(%edx),%edi
	addl	%edi,%esi
	movl	Lregs+8,%edx
	call	L3d69
	movzwl	Lregs+4,%ecx
	cmpb	$4,%bl
	je	L2561
	cmpb	$2,Ldesc+2
	jne	L255d
	.byte	0xf3
L255d:
	outsw
	jmp	L256c
L2561:
	cmpb	$2,Ldesc+2
	jne	L256b
	.byte	0xf3
L256b:
	outsl
L256c:
	movw	%cx,Lregs+4
	subl	%edi,%esi
	movw	%si,Lregs+24
	popl	%esi
	cld
	jmp	L1e28
L2583:
	call	L3d18
	testb	%al,%al
	jne	L32fd
	incl	%esi
	jmp	L1e28
L2596:
	movb	(%esi),%dl
	call	L38bc
	movb	(%esi),%cl
	incl	%esi
	jmp	L1ed8
L25a5:
	movb	(%esi),%dl
	call	L38d4
	movl	(%esi),%ecx
	addl	%ebx,%esi
	jmp	L1f33
L25b5:
	movb	(%esi),%dl
	call	L38d4
	movsbl	(%esi),%ecx
	incl	%esi
	jmp	L1f33
L25c5:
	call	L3893
	call	L38bc
	movb	(%eax),%cl
	testb	%cl,(%edi)
	jmp	L1e20
L25d8:
	call	L38a1
	call	L38d4
	movl	(%eax),%ecx
	cmpb	$4,%bl
	je	L25ea
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L25ea:
	testl	%ecx,(%edi)
	jmp	L1e20
L25f1:
	call	L3893
	call	L38bc
	movb	(%eax),%cl
	xchgb	%cl,(%edi)
	movb	%cl,(%eax)
	jmp	L1e28
L2606:
	call	L38a1
	call	L38d4
	cmpb	$4,%bl
	je	L2623
	movw	(%eax),%cx
	xchgw	%cx,(%edi)
	movw	%cx,(%eax)
	jmp	L1e28
L2623:
	movl	(%eax),%ecx
	xchgl	%ecx,(%edi)
	movl	%ecx,(%eax)
	jmp	L1e28
L262e:
	call	L3893
	call	L38bc
	movb	(%eax),%cl
	movb	%cl,(%edi)
	jmp	L1e28
L2641:
	call	L38a1
	call	L38d4
	movl	(%eax),%ecx
	movl	%edi,%eax
	.byte	0xe9			/* jmp L2673, long form */
	.long	L2673-.-4
L2654:
	call	L3893
	call	L38bc
	movb	(%edi),%cl
	movb	%cl,(%eax)
	jmp	L1e28
L2667:
	call	L38a1
	call	L38d4
	movl	(%edi),%ecx
L2673:
	cmpb	$4,%bl
	je	L2679
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L2679:
	movl	%ecx,(%eax)
	jmp	L1e28
L2680:
	call	L38ae
	call	L38d4
	movl	(%eax),%ecx
	subl	Lstate,%ecx
	shrl	$4,%ecx
	movw	%cx,(%edi)
	jmp	L1e28
L269d:
	movw	$0x1818,Ldesc
	call	L38a1
	call	L38d4
	movl	%edi,%ecx
	.byte	0xe9			/* jmp L2673, long form */
	.long	L2673-.-4
L26b7:
	call	L38ae
	call	L38d4
	movzwl	(%edi),%ecx
	shll	$4,%ecx
	addl	Lstate,%ecx
	movl	%ecx,(%eax)
	jmp	L1e28
L26d4:
	call	L38d4
	jmp	L21c8
L26de:
	andb	$7,%dl
	leal	Lregs(,%edx,4),%edi
	movl	Lregs,%eax
	movl	(%edi),%ecx
	cmpb	$4,%bl
	je	L2703
	movw	%ax,(%edi)
	movw	%cx,Lregs
	jmp	L1e28
L2703:
	movl	%eax,(%edi)
	movl	%ecx,Lregs
	jmp	L1e28
L2710:
	movl	Lregs,%eax
	cmpb	$4,%bl
	je	L271b
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L271b:
	cwtl
	movl	%eax,Lregs
	jmp	L1e28
L2726:
	movl	Lregs,%eax
	movl	Lregs+8,%edx
	cmpb	$4,%bl
	je	L2737
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L2737:
	cltd
	movl	%edx,Lregs+8
	jmp	L1e28
L2743:
	movl	%esi,%edi
	addl	$4,%esi
L2748:
	movl	Lregs+16,%ecx
	subl	$4,%ecx
	movl	%ecx,Lregs+16
	addl	Lsregs+8,%ecx
	movl	Lsregs+4,%eax
	subl	%eax,%esi
	subl	Lstate,%eax
	shrl	$4,%eax
	movw	%ax,2(%ecx)
	movw	%si,(%ecx)
	movw	2(%edi),%ax
	shll	$4,%eax
	addl	Lstate,%eax
	movl	%eax,Lsregs+4
	movw	(%edi),%si
	addl	%eax,%esi
	jmp	L1e28
L2790:
	movl	Leflags,%eax
	andl	$0x8ff,%eax
	orl	Lhostfl,%eax
	jmp	L2180
L27a5:
	cmpb	$4,%bl
	je	L27cb
	movl	Lregs+16,%ecx
	addl	$2,%ecx
	movl	%ecx,Lregs+16
	addl	Lsregs+8,%ecx
	movl	Leflags,%edx
	movw	-2(%ecx),%dx
	jmp	L27e3
L27cb:
	movl	Lregs+16,%ecx
	addl	$4,%ecx
	movl	%ecx,Lregs+16
	addl	Lsregs+8,%ecx
	movl	-4(%ecx),%edx
L27e3:
	movl	%edx,%eax
	andl	$0xfffff700,%eax
	movl	%eax,Lhostfl
	andl	$0xfffff700,Leflags
	andl	$0x8ff,%edx
	orl	%edx,Leflags
	jmp	L1e28
L280a:
	.byte	0x8a,0x05		/* movb	Lregs+1,%al */
	.long	Lregs+1
	.byte	0x88,0x05		/* movb	%al,Leflags */
	.long	Leflags
	jmp	L1e28
L281b:
	.byte	0x8a,0x05		/* movb	Leflags,%al */
	.long	Leflags
	.byte	0x88,0x05		/* movb	%al,Lregs+1 */
	.long	Lregs+1
	jmp	L1e28
L282c:
	movzwl	(%esi),%edi
	addl	$2,%esi
	movb	Ldesc,%dl
	addl	Lsregs(%edx),%edi
	call	L3917
	movb	(%edi),%al
	.byte	0x88,0x05		/* movb	%al,Lregs */
	.long	Lregs
	jmp	L1e28
L2850:
	movzwl	(%esi),%edi
	addl	$2,%esi
	movb	Ldesc,%dl
	addl	Lsregs(%edx),%edi
	call	L3917
	movl	(%edi),%eax
	cmpb	$4,%bl
	je	L286f
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L286f:
	movl	%eax,Lregs
	jmp	L1e28
L2879:
	movzwl	(%esi),%edi
	addl	$2,%esi
	movb	Ldesc,%dl
	addl	Lsregs(%edx),%edi
	call	L3917
	.byte	0x8a,0x05		/* movb	Lregs,%al */
	.long	Lregs
	movb	%al,(%edi)
	jmp	L1e28
L289d:
	movzwl	(%esi),%edi
	addl	$2,%esi
	movb	Ldesc,%dl
	addl	Lsregs(%edx),%edi
	call	L3917
	movl	%edi,%eax
	movl	Lregs,%ecx
	jmp	L2673
L28c1:
	pushl	%esi
	movl	Lhostfl,%eax
	andl	$0x400,%eax
	orl	Leflags,%eax
	pushl	%eax
	popfl
	movzwl	Lregs+24,%esi
	movb	Ldesc,%dl
	movl	Lsregs(%edx),%edx
	addl	%edx,%esi
	movzwl	Lregs+28,%edi
	addl	Lsregs,%edi
	movzwl	Lregs+4,%ecx
	cmpb	$2,Ldesc+2
	jne	L2907
	.byte	0xf3
L2907:
	movsb
	movw	%cx,Lregs+4
	subl	%edx,%esi
	movw	%si,Lregs+24
	subl	Lsregs,%edi
	movw	%di,Lregs+28
	popl	%esi
	cld
	jmp	L1e28
L292c:
	pushl	%esi
	movl	Lhostfl,%eax
	andl	$0x400,%eax
	orl	Leflags,%eax
	pushl	%eax
	popfl
	movzwl	Lregs+24,%esi
	movb	Ldesc,%dl
	movl	Lsregs(%edx),%edx
	addl	%edx,%esi
	movzwl	Lregs+28,%edi
	addl	Lsregs,%edi
	movzwl	Lregs+4,%ecx
	cmpb	$4,%bl
	je	L297b
	cmpb	$2,Ldesc+2
	jne	L2977
	.byte	0xf3
L2977:
	movsw
	jmp	L2986
L297b:
	cmpb	$2,Ldesc+2
	jne	L2985
	.byte	0xf3
L2985:
	movsl
L2986:
	movw	%cx,Lregs+4
	subl	%edx,%esi
	movw	%si,Lregs+24
	subl	Lsregs,%edi
	movw	%di,Lregs+28
	popl	%esi
	cld
	jmp	L1e28
L29aa:
	pushl	%esi
	movl	Lhostfl,%eax
	andl	$0x400,%eax
	orl	Leflags,%eax
	pushl	%eax
	popfl
	movzwl	Lregs+24,%esi
	movb	Ldesc,%dl
	movl	Lsregs(%edx),%edx
	addl	%edx,%esi
	movzwl	Lregs+28,%edi
	addl	Lsregs,%edi
	movzwl	Lregs+4,%ecx
	cmpb	$1,Ldesc+2
	jne	L29f3
	repne; cmpsb
	jmp	L29fe
L29f3:
	cmpb	$2,Ldesc+2
	jne	L29fd
	.byte	0xf3
L29fd:
	cmpsb
L29fe:
	pushfl
	movw	%cx,Lregs+4
	subl	%edx,%esi
	movw	%si,Lregs+24
	subl	Lsregs,%edi
	movw	%di,Lregs+28
	popfl
	popl	%esi
	cld
	jmp	L1e20
L2a24:
	pushl	%esi
	movl	Lhostfl,%eax
	andl	$0x400,%eax
	orl	Leflags,%eax
	pushl	%eax
	popfl
	movzwl	Lregs+24,%esi
	movb	Ldesc,%dl
	movl	Lsregs(%edx),%edx
	addl	%edx,%esi
	movzwl	Lregs+28,%edi
	addl	Lsregs,%edi
	movzwl	Lregs+4,%ecx
	cmpb	$4,%bl
	je	L2a81
	cmpb	$1,Ldesc+2
	jne	L2a73
	repne; cmpsw
	jmp	L2a99
L2a73:
	cmpb	$2,Ldesc+2
	jne	L2a7d
	.byte	0xf3
L2a7d:
	cmpsw
	jmp	L2a99

/* The 32-bit CMPS repeat dispatch.  The jne below should reach the
   "is it 0xF3" test at L2a8e, four bytes further on, the way the
   16-bit path at L2a65 reaches L2a73.  It reaches L2ad7 instead --
   the middle of the 32-bit TEST handler -- so CMPSD and REPE CMPSD
   are mishandled.  Transcribed as the reference has it. */
L2a81:
	cmpb	$1,Ldesc+2
	jne	L2ad7
	repne; cmpsl
	jmp	L2a99

/* Unreachable because of the branch above, and kept so the byte
   stream matches. */
L2a8e:
	cmpb	$2,Ldesc+2
	jne	L2a98
	.byte	0xf3
L2a98:
	cmpsl
L2a99:
	pushfl
	movw	%cx,Lregs+4
	subl	%edx,%esi
	movw	%si,Lregs+24
	subl	Lsregs,%edi
	movw	%di,Lregs+28
	popfl
	popl	%esi
	cld
	jmp	L1e20
L2abf:
	movb	(%esi),%al
	incl	%esi
	testb	%al,Lregs
	jmp	L1e20
L2acd:
	movl	(%esi),%eax
	addl	%ebx,%esi
	cmpb	$4,%bl
	je	L2ad7
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L2ad7:
	testl	%eax,Lregs
	jmp	L1e20
L2ae2:
	movl	Lhostfl,%eax
	andl	$0x400,%eax
	orl	Leflags,%eax
	pushl	%eax
	popfl
	movzwl	Lregs+28,%edi
	addl	Lsregs,%edi
	movzwl	Lregs+4,%ecx
	movl	Lregs,%eax
	cmpb	$2,Ldesc+2
	jne	L2b17
	.byte	0xf3
L2b17:
	stosb
	movw	%cx,Lregs+4
	subl	Lsregs,%edi
	movw	%di,Lregs+28
	cld
	jmp	L1e28
L2b32:
	movl	Lhostfl,%eax
	andl	$0x400,%eax
	orl	Leflags,%eax
	pushl	%eax
	popfl
	movzwl	Lregs+28,%edi
	addl	Lsregs,%edi
	movzwl	Lregs+4,%ecx
	movl	Lregs,%eax
	cmpb	$4,%bl
	je	L2b70
	cmpb	$2,Ldesc+2
	jne	L2b6c
	.byte	0xf3
L2b6c:
	stosw
	jmp	L2b7b
L2b70:
	cmpb	$2,Ldesc+2
	jne	L2b7a
	.byte	0xf3
L2b7a:
	stosl
L2b7b:
	movw	%cx,Lregs+4
	subl	Lsregs,%edi
	movw	%di,Lregs+28
	cld
	jmp	L1e28
L2b95:
	pushl	%esi
	movl	Lhostfl,%eax
	andl	$0x400,%eax
	orl	Leflags,%eax
	pushl	%eax
	popfl
	movzwl	Lregs+24,%esi
	movb	Ldesc,%dl
	movl	Lsregs(%edx),%edx
	addl	%edx,%esi
	movzwl	Lregs+4,%ecx
	cmpb	$2,Ldesc+2
	jne	L2bce
	.byte	0xf3
L2bce:
	lodsb
	movw	%cx,Lregs+4
	.byte	0x88,0x05		/* movb	%al,Lregs */
	.long	Lregs
	subl	%edx,%esi
	movw	%si,Lregs+24
	popl	%esi
	cld
	jmp	L1e28
L2bec:
	pushl	%esi
	movl	Lhostfl,%eax
	andl	$0x400,%eax
	orl	Leflags,%eax
	pushl	%eax
	popfl
	movzwl	Lregs+24,%esi
	movb	Ldesc,%dl
	movl	Lsregs(%edx),%edx
	addl	%edx,%esi
	movzwl	Lregs+4,%ecx
	cmpb	$4,%bl
	je	L2c34
	cmpb	$2,Ldesc+2
	jne	L2c2a
	.byte	0xf3
L2c2a:
	lodsw
	movw	%ax,Lregs
	jmp	L2c44
L2c34:
	cmpb	$2,Ldesc+2
	jne	L2c3e
	.byte	0xf3
L2c3e:
	lodsl
	movl	%eax,Lregs
L2c44:
	movw	%cx,Lregs+4
	subl	%edx,%esi
	movw	%si,Lregs+24
	popl	%esi
	cld
	jmp	L1e28
L2c5b:
	movl	Lhostfl,%eax
	andl	$0x400,%eax
	orl	Leflags,%eax
	pushl	%eax
	popfl
	movzwl	Lregs+28,%edi
	addl	Lsregs,%edi
	movzwl	Lregs+4,%ecx
	movl	Lregs,%eax
	cmpb	$1,Ldesc+2
	jne	L2c93
	repne; scasb
	jmp	L2c9e
L2c93:
	cmpb	$2,Ldesc+2
	jne	L2c9d
	.byte	0xf3
L2c9d:
	scasb
L2c9e:
	pushfl
	movw	%cx,Lregs+4
	subl	Lsregs,%edi
	movw	%di,Lregs+28
	popfl
	cld
	jmp	L1e20
L2cba:
	movl	Lhostfl,%eax
	andl	$0x400,%eax
	orl	Leflags,%eax
	pushl	%eax
	popfl
	movzwl	Lregs+28,%edi
	addl	Lsregs,%edi
	movzwl	Lregs+4,%ecx
	movl	Lregs,%eax
	cmpb	$4,%bl
	je	L2d06
	cmpb	$1,Ldesc+2
	jne	L2cf8
	repne; scasw
	jmp	L2d22
L2cf8:
	cmpb	$2,Ldesc+2
	jne	L2d02
	.byte	0xf3
L2d02:
	scasw
	jmp	L2d22

/* The 32-bit SCAS repeat dispatch, with the same defect: the jne
   should reach L2d17 and reaches L2e48, the 32-bit ROL handler.
   It is the only 32-bit branch displacement in the function that
   the reference stores without a relocation, i.e. the only one its
   assembler resolved as a constant rather than as a label. */
L2d06:
	cmpb	$1,Ldesc+2
	jne	L2e48
	repne; scasl
	jmp	L2d22

/* Unreachable because of the branch above, and kept so the byte
   stream matches. */
L2d17:
	cmpb	$2,Ldesc+2
	jne	L2d21
	.byte	0xf3
L2d21:
	scasl
L2d22:
	pushfl
	movw	%cx,Lregs+4
	subl	Lsregs,%edi
	movw	%di,Lregs+28
	popfl
	cld
	jmp	L1e20
L2d3e:
	movb	(%esi),%al
	incl	%esi
	.byte	0x88,0x05		/* movb	%al,Lregs */
	.long	Lregs
	jmp	L1e28
L2d4c:
	movb	(%esi),%al
	incl	%esi
	.byte	0x88,0x05		/* movb	%al,Lregs+4 */
	.long	Lregs+4
	jmp	L1e28
L2d5a:
	movb	(%esi),%al
	incl	%esi
	.byte	0x88,0x05		/* movb	%al,Lregs+8 */
	.long	Lregs+8
	jmp	L1e28
L2d68:
	movb	(%esi),%al
	incl	%esi
	.byte	0x88,0x05		/* movb	%al,Lregs+12 */
	.long	Lregs+12
	jmp	L1e28
L2d76:
	movb	(%esi),%al
	incl	%esi
	.byte	0x88,0x05		/* movb	%al,Lregs+1 */
	.long	Lregs+1
	jmp	L1e28
L2d84:
	movb	(%esi),%al
	incl	%esi
	.byte	0x88,0x05		/* movb	%al,Lregs+5 */
	.long	Lregs+5
	jmp	L1e28
L2d92:
	movb	(%esi),%al
	incl	%esi
	.byte	0x88,0x05		/* movb	%al,Lregs+9 */
	.long	Lregs+9
	jmp	L1e28
L2da0:
	movb	(%esi),%al
	incl	%esi
	.byte	0x88,0x05		/* movb	%al,Lregs+13 */
	.long	Lregs+13
	jmp	L1e28
L2dae:
	andb	$7,%dl
	leal	Lregs(,%edx,4),%eax
	movl	(%esi),%ecx
	addl	%ebx,%esi
	jmp	L2673
L2dc1:
	movb	(%esi),%dl
	call	L38bc
	movb	(%esi),%cl
	incl	%esi
L2dcb:
	andb	$0x38,%dl
	jmp	*Ltab_43f0(%edx)
L2dd4:
	movb	Leflags,%ah
	sahf
	rolb	%cl,(%edi)
	jmp	L1e20
L2de2:
	movb	Leflags,%ah
	sahf
	rorb	%cl,(%edi)
	jmp	L1e20
L2df0:
	movb	Leflags,%ah
	sahf
	rclb	%cl,(%edi)
	jmp	L1e20
L2dfe:
	movb	Leflags,%ah
	sahf
	rcrb	%cl,(%edi)
	jmp	L1e20
L2e0c:
	shlb	%cl,(%edi)
	jmp	L1e20
L2e13:
	shrb	%cl,(%edi)
	jmp	L1e20
L2e1a:
	sarb	%cl,(%edi)
	jmp	L1e20
L2e21:
	movb	(%esi),%dl
	call	L38d4
	movb	(%esi),%cl
	incl	%esi
L2e2b:
	andb	$0x38,%dl
	jmp	*Ltab_43f0+4(%edx)
L2e34:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L2e48
	sahf
	rolw	%cl,(%edi)
	jmp	L1e20
L2e48:
	sahf
	roll	%cl,(%edi)
	jmp	L1e20
L2e50:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L2e64
	sahf
	rorw	%cl,(%edi)
	jmp	L1e20
L2e64:
	sahf
	rorl	%cl,(%edi)
	jmp	L1e20
L2e6c:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L2e80
	sahf
	rclw	%cl,(%edi)
	jmp	L1e20
L2e80:
	sahf
	rcll	%cl,(%edi)
	jmp	L1e20
L2e88:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L2e9c
	sahf
	rcrw	%cl,(%edi)
	jmp	L1e20
L2e9c:
	sahf
	rcrl	%cl,(%edi)
	jmp	L1e20
L2ea4:
	cmpb	$4,%bl
	je	L2eaa
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L2eaa:
	shll	%cl,(%edi)
	jmp	L1e20
L2eb1:
	cmpb	$4,%bl
	je	L2eb7
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L2eb7:
	shrl	%cl,(%edi)
	jmp	L1e20
L2ebe:
	cmpb	$4,%bl
	je	L2ec4
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L2ec4:
	sarl	%cl,(%edi)
	jmp	L1e20
L2ecb:
	movzwl	(%esi),%eax
L2ece:
	movl	Lregs+16,%edi
	leal	2(%edi,%eax),%eax
	movl	%eax,Lregs+16
	addl	Lsregs+8,%edi
	movzwl	(%edi),%esi
	addl	Lsregs+4,%esi
	jmp	L1e28
L2ef1:
	xorl	%eax,%eax
	.byte	0xe9			/* jmp L2ece, long form */
	.long	L2ece-.-4
L2ef8:
	movl	$Lsregs,%edx
L2efd:
	call	L38a1
	call	L38d4
	movzwl	(%edi,%ebx),%ecx
	shll	$4,%ecx
	addl	Lstate,%ecx
	movl	%ecx,(%edx)
	movl	(%edi),%ecx
	jmp	L2673
L2f1d:
	movl	$Lsregs+12,%edx
	.byte	0xe9			/* jmp L2efd, long form */
	.long	L2efd-.-4
L2f27:
	call	L38bc
	movb	(%esi),%al
	incl	%esi
	movb	%al,(%edi)
	jmp	L1e28
L2f36:
	call	L38d4
	movl	(%esi),%ecx
	addl	%ebx,%esi
	movl	%edi,%eax
	jmp	L2673
L2f46:
	movzwl	Lregs+20,%ecx
	movl	Lregs+16,%edi
	subl	$2,%edi
	movw	%di,Lregs+20
	addl	Lsregs+8,%edi
	movw	%cx,(%edi)
	movb	2(%esi),%dl
	andb	$0x1f,%dl
	je	L2f91
	addl	Lsregs+8,%ecx
L2f74:
	decb	%dl
	je	L2f86
	subl	$2,%ecx
	movw	(%ecx),%ax
	subl	$2,%edi
	movw	%ax,(%edi)
	jmp	L2f74
L2f86:
	movl	Lregs+20,%eax
	subl	$2,%edi
	movw	%ax,(%edi)
L2f91:
	subl	Lsregs+8,%edi
	movl	(%esi),%eax
	subw	%ax,%di
	movw	%di,Lregs+16
	addl	$3,%esi
	jmp	L1e28
L2fab:
	movl	Lregs+20,%eax
	movw	%ax,Lregs+16
	movl	Lregs+16,%edi
	addl	$2,%edi
	movl	%edi,Lregs+16
	addl	Lsregs+8,%edi
	movw	-2(%edi),%ax
	movw	%ax,Lregs+20
	jmp	L1e28
L2fda:
	movzwl	(%esi),%eax
L2fdd:
	movl	Lregs+16,%edi
	leal	4(%edi,%eax),%eax
	movl	%eax,Lregs+16
	addl	Lsregs+8,%edi
	movzwl	(%edi),%esi
	movzwl	2(%edi),%ecx
	shll	$4,%ecx
	addl	Lstate,%ecx
	movl	%ecx,Lsregs+4
	addl	%ecx,%esi
	jmp	L1e28
L300f:
	xorl	%eax,%eax
	.byte	0xe9			/* jmp L2fdd, long form */
	.long	L2fdd-.-4
L3016:
	movl	Lregs+16,%ecx
	subl	$2,%ecx
	movl	%ecx,Lregs+16
	addl	Lsregs+8,%ecx
	movl	Leflags,%eax
	andl	$0x8ff,%eax
	orl	Lhostfl,%eax
	movw	%ax,(%ecx)
	movb	(%esi),%dl
	incl	%esi
	movl	Lstate,%edi
	leal	(%edi,%edx,4),%edi
	jmp	L2748
L304f:
	jmp	L1e4c
L3054:
	movl	Lregs+16,%edi
	addl	Lsregs+8,%edi
	movl	Leflags,%edx
	movw	4(%edi),%dx
	movl	%edx,%eax
	andl	$0xfffff700,%eax
	movl	%eax,Lhostfl
	andl	$0xfffff700,Leflags
	andl	$0x8ff,%edx
	orl	%edx,Leflags
	movl	$2,%eax
	jmp	L2fdd
L3096:
	movb	(%esi),%dl
	call	L38bc
	andb	$0x38,%dl
	jmp	*Ltab_4430(%edx)
L30a6:
	movb	Leflags,%ah
	sahf
	rolb	(%edi)
	jmp	L1e20
L30b4:
	movb	Leflags,%ah
	sahf
	rorb	(%edi)
	jmp	L1e20
L30c2:
	movb	Leflags,%ah
	sahf
	rclb	(%edi)
	jmp	L1e20
L30d0:
	movb	Leflags,%ah
	sahf
	rcrb	$1,(%edi)
	jmp	L1e20
L30de:
	shlb	(%edi)
	jmp	L1e20
L30e5:
	shrb	(%edi)
	jmp	L1e20
L30ec:
	sarb	(%edi)
	jmp	L1e20
L30f3:
	movb	(%esi),%dl
	call	L38d4
	andb	$0x38,%dl
	jmp	*Ltab_4430+4(%edx)
L3103:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L3117
	sahf
	rolw	(%edi)
	jmp	L1e20
L3117:
	sahf
	roll	(%edi)
	jmp	L1e20
L311f:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L3133
	sahf
	rorw	(%edi)
	jmp	L1e20
L3133:
	sahf
	rorl	(%edi)
	jmp	L1e20
L313b:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L314f
	sahf
	rclw	(%edi)
	jmp	L1e20
L314f:
	sahf
	rcll	(%edi)
	jmp	L1e20
L3157:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L316b
	sahf
	rcrw	$1,(%edi)
	jmp	L1e20
L316b:
	sahf
	rcrl	$1,(%edi)
	jmp	L1e20
L3173:
	cmpb	$4,%bl
	je	L3179
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L3179:
	shll	(%edi)
	jmp	L1e20
L3180:
	cmpb	$4,%bl
	je	L3186
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L3186:
	shrl	(%edi)
	jmp	L1e20
L318d:
	cmpb	$4,%bl
	je	L3193
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L3193:
	sarl	(%edi)
	jmp	L1e20
L319a:
	movb	(%esi),%dl
	call	L38bc
	movb	Lregs+4,%cl
	jmp	L2dcb
L31ac:
	movb	(%esi),%dl
	call	L38d4
	movb	Lregs+4,%cl
	jmp	L2e2b
L31be:
	incl	%esi
	movl	Lregs,%eax
	aam
	movl	%eax,Lregs
	jmp	L1e20
L31d0:
	incl	%esi
	movl	Lregs,%eax
	aad
	movl	%eax,Lregs
	jmp	L1e20
L31e2:
	movb	Ldesc,%dl
	movl	Lsregs(%edx),%edi
	xorl	%eax,%eax
	.byte	0x8a,0x05		/* movb	Lregs,%al */
	.long	Lregs
	addl	%eax,%edi
	movw	Lregs+12,%ax
	addl	%eax,%edi
	call	L3917
	movb	(%edi),%al
	.byte	0x88,0x05		/* movb	%al,Lregs */
	.long	Lregs
	jmp	L1e28
L3212:
	jmp	L1e4c
L3217:
	incl	%esi
	decw	Lregs+4
	je	L1e28
	testb	$0x40,Leflags
	jne	L1e28
	decl	%esi
	jmp	L32fd
L3238:
	incl	%esi
	decw	Lregs+4
	je	L1e28
	testb	$0x40,Leflags
	je	L1e28
	decl	%esi
	jmp	L32fd
L3259:
	decw	Lregs+4
	jne	L32fd
	incl	%esi
	jmp	L1e28
L326c:
	cmpw	$0,Lregs+4
	je	L32fd
	incl	%esi
	jmp	L1e28
L3280:
	xorl	%edx,%edx
	movb	(%esi),%dl
	incl	%esi
	jmp	L331b
L328a:
	xorl	%edx,%edx
	movb	(%esi),%dl
	incl	%esi
	jmp	L3332
L3294:
	xorl	%edx,%edx
	movb	(%esi),%dl
	incl	%esi
	jmp	L3353
L329e:
	xorl	%edx,%edx
	movb	(%esi),%dl
	incl	%esi
	jmp	L33c7
L32a8:
	movl	(%esi),%ecx
	addl	$2,%esi
	subl	Lsregs+4,%esi
	movl	%esi,%eax
	addw	%cx,%si
	addl	Lsregs+4,%esi
	jmp	L2180
L32c3:
	movl	(%esi),%eax
	addl	$2,%esi
	subl	Lsregs+4,%esi
	addw	%ax,%si
	addl	Lsregs+4,%esi
	jmp	L1e28
L32dc:
	movl	%esi,%edi
	addl	$4,%esi
L32e1:
	movzwl	2(%edi),%eax
	shll	$4,%eax
	addl	Lstate,%eax
	movl	%eax,Lsregs+4
	movzwl	(%edi),%esi
	addl	%eax,%esi
	jmp	L1e28
L32fd:
	movsbl	(%esi),%eax
	incl	%esi
	subl	Lsregs+4,%esi
	addw	%ax,%si
	addl	Lsregs+4,%esi
	jmp	L1e28
L3315:
	movl	Lregs+8,%edx
L331b:
	call	L3d69
	inb	%dx,%al
	.byte	0x88,0x05		/* movb	%al,Lregs */
	.long	Lregs
	jmp	L1e28
L332c:
	movl	Lregs+8,%edx
L3332:
	call	L3d69
	movl	Lregs,%eax
	cmpb	$4,%bl
	je	L3342
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L3342:
	inl	%dx,%eax
	movl	%eax,Lregs
	jmp	L1e28
L334d:
	movl	Lregs+8,%edx
L3353:
	andl	$0xffff,%edx
	cmpl	Lsmmport,%edx
	.byte	0x0f,0x84		/* je L3375, long form as in the reference */
	.long	L3375-.-4
	call	L3d69
	movl	Lregs,%eax
	outb	%al,%dx
	jmp	L1e28
L3375:
	pushl	%ebx
	pushl	%esi
	movl	Lregs+12,%ebx
	movl	Lregs+4,%ecx
	movl	Lregs+24,%esi
	movl	Lregs+28,%edi
	movl	Lregs,%eax
	outb	%al,%dx
	outb	%al,$0x4f
	movl	%eax,Lregs
	movl	%ebx,Lregs+12
	movl	%ecx,Lregs+4
	movl	%edx,Lregs+8
	movl	%esi,Lregs+24
	movl	%edi,Lregs+28
	popl	%esi
	popl	%ebx
	jmp	L1e28
L33c1:
	movl	Lregs+8,%edx
L33c7:
	call	L3d69
	movl	Lregs,%eax
	cmpb	$4,%bl
	je	L33d7
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L33d7:
	outl	%eax,%dx
	jmp	L1e28
L33dd:
	movb	$1,Ldesc+2
	jmp	L1e40
L33e9:
	movb	$2,Ldesc+2
	jmp	L1e40
L33f5:
	xorb	$1,Leflags
	jmp	L1e28
L3401:
	movb	(%esi),%dl
	call	L38bc
	andb	$0x38,%dl
	jmp	*Ltab_4470(%edx)
L3411:
	movb	(%esi),%cl
	incl	%esi
	testb	%cl,(%edi)
	jmp	L1e20
L341b:
	notb	(%edi)
	jmp	L1e28
L3422:
	negb	(%edi)
	jmp	L1e20
L3429:
	movl	Lregs,%eax
	mulb	(%edi)
	movl	%eax,Lregs
	jmp	L1e20
L343a:
	movl	Lregs,%eax
	imulb	(%edi)
	movl	%eax,Lregs
	jmp	L1e20
L344b:
	movl	Lregs,%eax
	divb	(%edi)
	movl	%eax,Lregs
	jmp	L1e20
L345c:
	movl	Lregs,%eax
	idivb	(%edi)
	movl	%eax,Lregs
	jmp	L1e20
L346d:
	movb	(%esi),%dl
	call	L38d4
	andb	$0x38,%dl
	jmp	*Ltab_4470+4(%edx)
L347d:
	movl	(%esi),%ecx
	addl	%ebx,%esi
	cmpb	$4,%bl
	je	L3487
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L3487:
	testl	%ecx,(%edi)
	jmp	L1e20
L348e:
	cmpb	$4,%bl
	je	L3494
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L3494:
	notl	(%edi)
	jmp	L1e28
L349b:
	cmpb	$4,%bl
	je	L34a1
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L34a1:
	negl	(%edi)
	jmp	L1e20
L34a8:
	movl	Lregs,%eax
	movl	Lregs+8,%edx
	cmpb	$4,%bl
	je	L34b9
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L34b9:
	mull	(%edi)
	movl	%eax,Lregs
	movl	%edx,Lregs+8
	jmp	L1e20
L34cb:
	movl	Lregs,%eax
	movl	Lregs+8,%edx
	cmpb	$4,%bl
	je	L34dc
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L34dc:
	imull	(%edi)
	movl	%eax,Lregs
	movl	%edx,Lregs+8
	jmp	L1e20
L34ee:
	movl	Lregs,%eax
	movl	Lregs+8,%edx
	cmpb	$4,%bl
	je	L34ff
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L34ff:
	divl	(%edi)
	movl	%eax,Lregs
	movl	%edx,Lregs+8
	jmp	L1e20
L3511:
	movl	Lregs,%eax
	movl	Lregs+8,%edx
	cmpb	$4,%bl
	je	L3522
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L3522:
	idivl	(%edi)
	movl	%eax,Lregs
	movl	%edx,Lregs+8
	jmp	L1e20
L3534:
	andb	$0xfe,Leflags
	jmp	L1e28
L3540:
	orb	$1,Leflags
	jmp	L1e28
L354c:
	andl	$0xfffffdff,Lhostfl
	jmp	L1e28
L355b:
	orl	$0x200,Lhostfl
	jmp	L1e28
L356a:
	andl	$0xfffffbff,Lhostfl
	jmp	L1e28
L3579:
	orl	$0x400,Lhostfl
	jmp	L1e28
L3588:
	movb	(%esi),%dl
	call	L38bc
	andb	$0x38,%dl
	jmp	*Ltab_44b0(%edx)
L3598:
	movb	Leflags,%ah
	sahf
	incb	(%edi)
	jmp	L1e20
L35a6:
	movb	Leflags,%ah
	sahf
	decb	(%edi)
	jmp	L1e20
L35b4:
	movb	(%esi),%dl
	call	L38d4
	andb	$0x38,%dl
	jmp	*Ltab_44b0+4(%edx)
L35c4:
	subl	Lsregs+4,%esi
	movl	%esi,%eax
	movw	(%edi),%si
	addl	Lsregs+4,%esi
	jmp	L2180
L35da:
	movzwl	(%edi),%esi
	addl	Lsregs+4,%esi
	jmp	L1e28
L35e8:
	movl	(%edi),%eax
	jmp	L2180
L35ef:
	call	L3d18
	testb	%al,%al
	jne	L32c3
	addl	$2,%esi
	jmp	L1e28
L3604:
	call	L38bc
	call	L3d18
	movb	%al,(%edi)
	jmp	L1e28
L3615:
	movl	Lsregs+16,%eax
	jmp	L2008
L361f:
	movl	$Lsregs+16,%ecx
	jmp	L201b
L3629:
	call	L38a1
	call	L38d4
	movl	(%eax),%ecx
L3635:
	cmpb	$4,%bl
	je	L363b
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L363b:
	btl	%ecx,(%edi)
	jmp	L1e20
L3643:
	call	L38a1
	call	L38d4
	movb	(%esi),%cl
	incl	%esi
L3650:
	andb	$0x1f,%cl
	je	L1e28
	movl	(%eax),%eax
	cmpb	$4,%bl
	je	L3661
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L3661:
	shldl	%cl,%eax,(%edi)
	jmp	L1e20
L3669:
	call	L38a1
	call	L38d4
	movb	Lregs+4,%cl
	.byte	0xe9			/* jmp L3650, long form */
	.long	L3650-.-4
L367e:
	movl	Lsregs+20,%eax
	jmp	L2008
L3688:
	movl	$Lsregs+20,%ecx
	jmp	L201b
L3692:
	call	L38a1
	call	L38d4
	movl	(%eax),%ecx
L369e:
	cmpb	$4,%bl
	je	L36a4
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L36a4:
	btsl	%ecx,(%edi)
	jmp	L1e20
L36ac:
	call	L38a1
	call	L38d4
	movb	(%esi),%cl
	incl	%esi
L36b9:
	andb	$0x1f,%cl
	je	L1e28
	movl	(%eax),%eax
	cmpb	$4,%bl
	je	L36ca
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L36ca:
	shrdl	%cl,%eax,(%edi)
	jmp	L1e20
L36d2:
	call	L38a1
	call	L38d4
	movb	Lregs+4,%cl
	.byte	0xe9			/* jmp L36b9, long form */
	.long	L36b9-.-4
L36e7:
	call	L38a1
	call	L38d4
	movl	(%eax),%ecx
	jmp	L23c2
L36f8:
	call	L3893
	call	L38bc
	movb	(%eax),%cl
	.byte	0x8a,0x05		/* movb	Lregs,%al */
	.long	Lregs
	.byte	0x0f,0xa6,0x0f	/* cmpxchg %cl,(%edi), i486 A-step encoding */
	.byte	0x88,0x05		/* movb	%al,Lregs */
	.long	Lregs
	jmp	L1e20
L3718:
	call	L38a1
	call	L38d4
	movl	(%eax),%ecx
	movl	Lregs,%eax
	cmpb	$4,%bl
	je	L372f
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L372f:
	.byte	0x0f,0xa7,0x0f	/* cmpxchg %ecx,(%edi), i486 A-step encoding */
	movl	%eax,Lregs
	jmp	L1e20
L373c:
	movl	$Lsregs+8,%edx
	jmp	L2efd
L3746:
	call	L38a1
	call	L38d4
	movl	(%eax),%ecx
L3752:
	cmpb	$4,%bl
	je	L3758
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L3758:
	btrl	%ecx,(%edi)
	jmp	L1e20
L3760:
	movl	$Lsregs+16,%edx
	jmp	L2efd
L376a:
	movl	$Lsregs+20,%edx
	jmp	L2efd
L3774:
	call	L38a1
	call	L38bc
	movzbl	(%edi),%ecx
	jmp	L2673
L3786:
	call	L38a1
	call	L38d4
	movzwl	(%edi),%ecx
	jmp	L2673
L3798:
	movb	(%esi),%dl
	call	L38d4
	movb	(%esi),%cl
	incl	%esi
	andb	$0x38,%dl
	subb	$0x20,%dl
	jb	L1e4c
	shrl	$1,%edx
	jmp	*Ltab_4630(%edx)
L37b6:
	call	L38a1
	call	L38d4
	movl	(%eax),%ecx
L37c2:
	cmpb	$4,%bl
	je	L37c8
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L37c8:
	btcl	%ecx,(%edi)
	jmp	L1e20
L37d0:
	call	L38a1
	call	L38d4
	cmpb	$4,%bl
	je	L37eb
	bsfw	(%edi),%cx
	movw	%cx,(%eax)
	jmp	L1e20
L37eb:
	bsfl	(%edi),%ecx
	movl	%ecx,(%eax)
	jmp	L1e20
L37f5:
	call	L38a1
	call	L38d4
	cmpb	$4,%bl
	je	L3810
	bsrw	(%edi),%cx
	movw	%cx,(%eax)
	jmp	L1e20
L3810:
	bsrl	(%edi),%ecx
	movl	%ecx,(%eax)
	jmp	L1e20
L381a:
	call	L38a1
	call	L38bc
	movsbl	(%edi),%ecx
	jmp	L2673
L382c:
	call	L38a1
	call	L38d4
	movswl	(%edi),%ecx
	jmp	L2673
L383e:
	call	L3893
	call	L38bc
	movb	(%eax),%cl
	xaddb	%cl,(%edi)
	movb	%cl,(%eax)
	jmp	L1e20
L3854:
	call	L38a1
	call	L38d4
	movl	(%eax),%ecx
	cmpb	$4,%bl
	je	L3871
	xaddw	%cx,(%edi)
	movw	%cx,(%eax)
	jmp	L1e20
L3871:
	xaddl	%ecx,(%edi)
	movl	%ecx,(%eax)
	jmp	L1e20
L387b:
	andb	$7,%dl
	movl	Lregs(,%edx,4),%eax
	bswapl	%eax
	movl	%eax,Lregs(,%edx,4)
	jmp	L1e28

/*
 * internal helpers: the modrm decoders and the effective-address
 * computations.  They take their arguments in registers, and the two
 * refusals at L3936 and L3949 pop their own return address to
 * long-jump to the error exit, so no C calling convention applies
 */
L3893:
	movb	(%esi),%al
	andl	$0x38,%eax
	shrl	$1,%eax
	movl	Ltab_4390(%eax),%eax
	ret
L38a1:
	movb	(%esi),%al
	andl	$0x38,%eax
	shrl	$1,%eax
	.byte	0x05			/* addl	$Lregs,%eax */
	.long	Lregs
	ret
L38ae:
	movb	(%esi),%al
	andl	$0x38,%eax
	shrl	$1,%eax
	.byte	0x05			/* addl	$Lsregs,%eax */
	.long	Lsregs
	ret
	.align	2,0x00
L38bc:
	movb	(%esi),%cl
	incl	%esi
	rolb	$4,%cl
	andl	$0x7c,%ecx
	orb	Ldesc+3,%cl
	jmp	*Ltab_4190(%ecx)
	.align	2,0x00
L38d4:
	movb	(%esi),%cl
	incl	%esi
	rolb	$4,%cl
	andl	$0x7c,%ecx
	orb	Ldesc+3,%cl
	jmp	*Ltab_4290(%ecx)
	.align	2,0x00
L38ec:
	movl	Lregs+12,%edi
	addl	Lregs+24,%edi
L38f8:
	andl	$0xffff,%edi
L38fe:
	movb	Ldesc,%cl
L3904:
	cmpb	$0x18,%cl
	je	L3935
	cmpl	$0x10000,%edi
	jae	L3949
	addl	Lsregs(%ecx),%edi
L3917:
	movl	%edi,%ecx
	subl	Lstate,%ecx
	cmpl	$0x100000,%ecx
	jae	L3936
	shrl	$0xc,%ecx
	addl	Lpageperm,%ecx
	cmpb	$0,(%ecx)
	je	L3936
L3935:
	ret
L3936:
	popl	%ecx
	movl	%edi,%eax
	subl	Lstate,%eax
	orl	$0x2000000,%eax
	jmp	L1e58
L3949:
	popl	%ecx
	movl	$0x4000000,%eax
	jmp	L1e58
L3954:
	movl	Lregs+12,%edi
	addl	Lregs+28,%edi
	.byte	0xe9			/* jmp L38f8, long form */
	.long	L38f8-.-4
	.align	2,0x00
L3968:
	movl	Lregs+20,%edi
	addl	Lregs+24,%edi
	jmp	L3a46
	.align	2,0x00
L397c:
	movl	Lregs+20,%edi
	addl	Lregs+28,%edi
	jmp	L3a46
	.align	2,0x00
L3990:
	movl	Lregs+24,%edi
	jmp	L38f8
	.align	2,0x00
L399c:
	movl	Lregs+28,%edi
	jmp	L38f8
	.align	2,0x00
L39a8:
	movl	(%esi),%edi
	addl	$2,%esi
	jmp	L38f8
	.align	2,0x00
L39b4:
	movl	Lregs+12,%edi
	jmp	L38f8
L39bf:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+12,%edi
	addl	Lregs+24,%edi
	jmp	L38f8
L39d4:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+12,%edi
	addl	Lregs+28,%edi
	jmp	L38f8
	.align	2,0x00
L39ec:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+20,%edi
	addl	Lregs+24,%edi
	.byte	0xe9			/* jmp L3a46, long form */
	.long	L3a46-.-4
	.align	2,0x00
L3a04:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+20,%edi
	addl	Lregs+28,%edi
	.byte	0xe9			/* jmp L3a46, long form */
	.long	L3a46-.-4
	.align	2,0x00
L3a1c:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+24,%edi
	jmp	L38f8
	.align	2,0x00
L3a2c:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+28,%edi
	jmp	L38f8
	.align	2,0x00
L3a3c:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+20,%edi
L3a46:
	andl	$0xffff,%edi
L3a4c:
	movb	Ldesc+1,%cl
	jmp	L3904
	.align	2,0x00
L3a58:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+12,%edi
	jmp	L38f8
L3a67:
	movl	(%esi),%edi
	addl	$2,%esi
	addl	Lregs+12,%edi
	addl	Lregs+24,%edi
	jmp	L38f8
	.align	2,0x00
L3a80:
	movl	(%esi),%edi
	addl	$2,%esi
	addl	Lregs+12,%edi
	addl	Lregs+28,%edi
	jmp	L38f8
	.align	2,0x00
L3a98:
	movl	(%esi),%edi
	addl	$2,%esi
	addl	Lregs+20,%edi
	addl	Lregs+24,%edi
	.byte	0xe9			/* jmp L3a46, long form */
	.long	L3a46-.-4
	.align	2,0x00
L3ab0:
	movl	(%esi),%edi
	addl	$2,%esi
	addl	Lregs+20,%edi
	addl	Lregs+28,%edi
	.byte	0xe9			/* jmp L3a46, long form */
	.long	L3a46-.-4
	.align	2,0x00
L3ac8:
	movl	(%esi),%edi
	addl	$2,%esi
	addl	Lregs+24,%edi
	jmp	L38f8
L3ad8:
	movl	(%esi),%edi
	addl	$2,%esi
	addl	Lregs+28,%edi
	jmp	L38f8
L3ae8:
	movl	(%esi),%edi
	addl	$2,%esi
	addl	Lregs+20,%edi
	jmp	L3a46
L3af8:
	movl	(%esi),%edi
	addl	$2,%esi
	addl	Lregs+12,%edi
	jmp	L38f8
L3b08:
	movl	$Lregs,%edi
	ret
	.align	2,0x00
L3b10:
	movl	$Lregs+4,%edi
	ret
	.align	2,0x00
L3b18:
	movl	$Lregs+8,%edi
	ret
	.align	2,0x00
L3b20:
	movl	$Lregs+12,%edi
	ret
	.align	2,0x00
L3b28:
	movl	$Lregs+16,%edi
	ret
	.align	2,0x00
L3b30:
	movl	$Lregs+20,%edi
	ret
	.align	2,0x00
L3b38:
	movl	$Lregs+24,%edi
	ret
	.align	2,0x00
L3b40:
	movl	$Lregs+28,%edi
	ret
	.align	2,0x00
L3b48:
	movl	$Lregs+1,%edi
	ret
	.align	2,0x00
L3b50:
	movl	$Lregs+5,%edi
	ret
	.align	2,0x00
L3b58:
	movl	$Lregs+9,%edi
	ret
	.align	2,0x00
L3b60:
	movl	$Lregs+13,%edi
	ret
	.align	2,0x00
L3b68:
	movl	Lregs,%edi
	jmp	L38fe
	.align	2,0x00
L3b74:
	movl	Lregs+4,%edi
	jmp	L38fe
	.align	2,0x00
L3b80:
	movl	Lregs+8,%edi
	jmp	L38fe
	.align	2,0x00
L3b8c:
	movl	Lregs+12,%edi
	jmp	L38fe
	.align	2,0x00
L3b98:
	movl	(%esi),%edi
	addl	$4,%esi
	jmp	L38fe
	.align	2,0x00
L3ba4:
	movl	Lregs+24,%edi
	jmp	L38fe
	.align	2,0x00
L3bb0:
	movl	Lregs+28,%edi
	jmp	L38fe
	.align	2,0x00
L3bbc:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs,%edi
	jmp	L38fe
	.align	2,0x00
L3bcc:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+4,%edi
	jmp	L38fe
	.align	2,0x00
L3bdc:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+8,%edi
	jmp	L38fe
	.align	2,0x00
L3bec:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+12,%edi
	jmp	L38fe
	.align	2,0x00
L3bfc:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+20,%edi
	jmp	L3a4c
	.align	2,0x00
L3c0c:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+24,%edi
	jmp	L38fe
	.align	2,0x00
L3c1c:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+28,%edi
	jmp	L38fe
	.align	2,0x00
L3c2c:
	movl	(%esi),%edi
	addl	$4,%esi
	addl	Lregs,%edi
	jmp	L38fe
L3c3c:
	movl	(%esi),%edi
	addl	$4,%esi
	addl	Lregs+4,%edi
	jmp	L38fe
L3c4c:
	movl	(%esi),%edi
	addl	$4,%esi
	addl	Lregs+8,%edi
	jmp	L38fe
L3c5c:
	movl	(%esi),%edi
	addl	$4,%esi
	addl	Lregs+12,%edi
	jmp	L38fe
L3c6c:
	movl	(%esi),%edi
	addl	$4,%esi
	addl	Lregs+20,%edi
	jmp	L3a4c
L3c7c:
	movl	(%esi),%edi
	addl	$4,%esi
	addl	Lregs+24,%edi
	jmp	L38fe
L3c8c:
	movl	(%esi),%edi
	addl	$4,%esi
	addl	Lregs+28,%edi
	jmp	L38fe
L3c9c:
	movb	(%esi),%cl
	incl	%esi
	xorb	$5,%cl
	testb	$7,%cl
	je	L3cb1
	xorb	$5,%cl
	xorl	%edi,%edi
	.byte	0xe9			/* jmp L3cd8, long form */
	.long	L3cd8-.-4
L3cb1:
	movl	(%esi),%edi
	addl	$4,%esi
	andb	$0xf8,%cl
	.byte	0xe9			/* jmp L3ce4, long form */
	.long	L3ce4-.-4
	.align	2,0x00
L3cc0:
	movb	(%esi),%cl
	movsbl	1(%esi),%edi
	addl	$2,%esi
	.byte	0xe9			/* jmp L3cd8, long form */
	.long	L3cd8-.-4
	.align	2,0x00
L3cd0:
	movb	(%esi),%cl
	movl	1(%esi),%edi
	addl	$5,%esi
L3cd8:
	pushl	%ecx
	andb	$7,%cl
	addl	Lregs(,%ecx,4),%edi
	popl	%ecx
L3ce4:
	pushl	%edi
	pushl	%ecx
	shrl	$1,%ecx
	andb	$0x1c,%cl
	xorl	%edi,%edi
	cmpb	$0x10,%cl
	je	L3d00
	movl	Lregs(%ecx),%edi
	movl	(%esp),%ecx
	shrb	$6,%cl
	shll	%cl,%edi
L3d00:
	popl	%ecx
	addl	(%esp),%edi
	addl	$4,%esp
	andb	$6,%cl
	cmpb	$4,%cl
	jne	L38fe
	jmp	L3a4c

/*
 * the condition-code evaluator.  dl carries the tttn field, the guest
 * flags are loaded into the host, and one of sixteen setcc stubs runs
 */
L3d18:
	andb	$0xf,%dl
	movl	Leflags,%eax
	pushl	%eax
	popfl
	jmp	*Ltab_4640(,%edx,4)
L3d29:
	seto	%al
	ret
L3d2d:
	setno	%al
	ret
L3d31:
	setb	%al
	ret
L3d35:
	setae	%al
	ret
L3d39:
	sete	%al
	ret
L3d3d:
	setne	%al
	ret
L3d41:
	setbe	%al
	ret
L3d45:
	seta	%al
	ret
L3d49:
	sets	%al
	ret
L3d4d:
	setns	%al
	ret
L3d51:
	setp	%al
	ret

/* Slot 11 of Ltab_4640.  The condition order calls for setnp here;
   the reference has setno, the same encoding as slot 1, so guest
   JNP/JPO, SETNP/SETPO and LOOPNP evaluate as "not overflow".
   Transcribed as written. */
L3d55:
	setno	%al
	ret
L3d59:
	setl	%al
	ret
L3d5d:
	setge	%al
	ret
L3d61:
	setle	%al
	ret
L3d65:
	setg	%al
	ret

/*
 * the I/O permission check.  On denial it discards its own return
 * address and long-jumps to the exit path, so the caller never resumes
 */
L3d69:
	movzwl	%dx,%ecx
	shrl	$3,%ecx
	andb	$0xfc,%cl
	addl	Lioperm,%ecx
	movl	(%ecx),%ecx
	btl	%edx,%ecx
	jae	L3d80
	ret
L3d80:
	popl	%ecx
	movzwl	%dx,%eax
	orl	$0x3000000,%eax
	jmp	L1e58

/*
 * Dispatch tables.  Everything from here to the end of __text is data.
 */
	.align	2,0x00

/* Ltab_3d90 -- primary dispatch, one entry per opcode byte */
Ltab_3d90:
	.long	L1ecc		/* 00 */
	.long	L1f27		/* 01 */
	.long	L1fc2		/* 02 */
	.long	L1fd5		/* 03 */
	.long	L1fe8		/* 04 */
	.long	L1ff5		/* 05 */
	.long	L2003		/* 06 */
	.long	L2016		/* 07 */
	.long	L1ecc		/* 08 */
	.long	L1f27		/* 09 */
	.long	L1fc2		/* 0a */
	.long	L1fd5		/* 0b */
	.long	L1fe8		/* 0c */
	.long	L1ff5		/* 0d */
	.long	L2044		/* 0e */
	.long	L204e		/* 0f */
	.long	L1ecc		/* 10 */
	.long	L1f27		/* 11 */
	.long	L1fc2		/* 12 */
	.long	L1fd5		/* 13 */
	.long	L1fe8		/* 14 */
	.long	L1ff5		/* 15 */
	.long	L206a		/* 16 */
	.long	L2074		/* 17 */
	.long	L1ecc		/* 18 */
	.long	L1f27		/* 19 */
	.long	L1fc2		/* 1a */
	.long	L1fd5		/* 1b */
	.long	L1fe8		/* 1c */
	.long	L1ff5		/* 1d */
	.long	L207e		/* 1e */
	.long	L2088		/* 1f */
	.long	L1ecc		/* 20 */
	.long	L1f27		/* 21 */
	.long	L1fc2		/* 22 */
	.long	L1fd5		/* 23 */
	.long	L1fe8		/* 24 */
	.long	L1ff5		/* 25 */
	.long	L2092		/* 26 */
	.long	L20a0		/* 27 */
	.long	L1ecc		/* 28 */
	.long	L1f27		/* 29 */
	.long	L1fc2		/* 2a */
	.long	L1fd5		/* 2b */
	.long	L1fe8		/* 2c */
	.long	L1ff5		/* 2d */
	.long	L20b9		/* 2e */
	.long	L20c7		/* 2f */
	.long	L1ecc		/* 30 */
	.long	L1f27		/* 31 */
	.long	L1fc2		/* 32 */
	.long	L1fd5		/* 33 */
	.long	L1fe8		/* 34 */
	.long	L1ff5		/* 35 */
	.long	L20e0		/* 36 */
	.long	L20ee		/* 37 */
	.long	L1ecc		/* 38 */
	.long	L1f27		/* 39 */
	.long	L1fc2		/* 3a */
	.long	L1fd5		/* 3b */
	.long	L1fe8		/* 3c */
	.long	L1ff5		/* 3d */
	.long	L2105		/* 3e */
	.long	L2113		/* 3f */
	.long	L212a		/* 40 */
	.long	L212a		/* 41 */
	.long	L212a		/* 42 */
	.long	L212a		/* 43 */
	.long	L212a		/* 44 */
	.long	L212a		/* 45 */
	.long	L212a		/* 46 */
	.long	L212a		/* 47 */
	.long	L2150		/* 48 */
	.long	L2150		/* 49 */
	.long	L2150		/* 4a */
	.long	L2150		/* 4b */
	.long	L2150		/* 4c */
	.long	L2150		/* 4d */
	.long	L2150		/* 4e */
	.long	L2150		/* 4f */
	.long	L2176		/* 50 */
	.long	L2176		/* 51 */
	.long	L2176		/* 52 */
	.long	L2176		/* 53 */
	.long	L2176		/* 54 */
	.long	L2176		/* 55 */
	.long	L2176		/* 56 */
	.long	L2176		/* 57 */
	.long	L21be		/* 58 */
	.long	L21be		/* 59 */
	.long	L21be		/* 5a */
	.long	L21be		/* 5b */
	.long	L21be		/* 5c */
	.long	L21be		/* 5d */
	.long	L21be		/* 5e */
	.long	L21be		/* 5f */
	.long	L220d		/* 60 */
	.long	L22c2		/* 61 */
	.long	L2372		/* 62 */
	.long	L2377		/* 63 */
	.long	L237c		/* 64 */
	.long	L238a		/* 65 */
	.long	L2398		/* 66 */
	.long	L239f		/* 67 */
	.long	L23ab		/* 68 */
	.long	L23b4		/* 69 */
	.long	L23dd		/* 6a */
	.long	L23e6		/* 6b */
	.long	L23f9		/* 6c */
	.long	L244f		/* 6d */
	.long	L24b8		/* 6e */
	.long	L2514		/* 6f */
	.long	L2583		/* 70 */
	.long	L2583		/* 71 */
	.long	L2583		/* 72 */
	.long	L2583		/* 73 */
	.long	L2583		/* 74 */
	.long	L2583		/* 75 */
	.long	L2583		/* 76 */
	.long	L2583		/* 77 */
	.long	L2583		/* 78 */
	.long	L2583		/* 79 */
	.long	L2583		/* 7a */
	.long	L2583		/* 7b */
	.long	L2583		/* 7c */
	.long	L2583		/* 7d */
	.long	L2583		/* 7e */
	.long	L2583		/* 7f */
	.long	L2596		/* 80 */
	.long	L25a5		/* 81 */
	.long	L2596		/* 82 */
	.long	L25b5		/* 83 */
	.long	L25c5		/* 84 */
	.long	L25d8		/* 85 */
	.long	L25f1		/* 86 */
	.long	L2606		/* 87 */
	.long	L262e		/* 88 */
	.long	L2641		/* 89 */
	.long	L2654		/* 8a */
	.long	L2667		/* 8b */
	.long	L2680		/* 8c */
	.long	L269d		/* 8d */
	.long	L26b7		/* 8e */
	.long	L26d4		/* 8f */
	.long	L1e28		/* 90 */
	.long	L26de		/* 91 */
	.long	L26de		/* 92 */
	.long	L26de		/* 93 */
	.long	L26de		/* 94 */
	.long	L26de		/* 95 */
	.long	L26de		/* 96 */
	.long	L26de		/* 97 */
	.long	L2710		/* 98 */
	.long	L2726		/* 99 */
	.long	L2743		/* 9a */
	.long	L1e28		/* 9b */
	.long	L2790		/* 9c */
	.long	L27a5		/* 9d */
	.long	L280a		/* 9e */
	.long	L281b		/* 9f */
	.long	L282c		/* a0 */
	.long	L2850		/* a1 */
	.long	L2879		/* a2 */
	.long	L289d		/* a3 */
	.long	L28c1		/* a4 */
	.long	L292c		/* a5 */
	.long	L29aa		/* a6 */
	.long	L2a24		/* a7 */
	.long	L2abf		/* a8 */
	.long	L2acd		/* a9 */
	.long	L2ae2		/* aa */
	.long	L2b32		/* ab */
	.long	L2b95		/* ac */
	.long	L2bec		/* ad */
	.long	L2c5b		/* ae */
	.long	L2cba		/* af */
	.long	L2d3e		/* b0 */
	.long	L2d4c		/* b1 */
	.long	L2d5a		/* b2 */
	.long	L2d68		/* b3 */
	.long	L2d76		/* b4 */
	.long	L2d84		/* b5 */
	.long	L2d92		/* b6 */
	.long	L2da0		/* b7 */
	.long	L2dae		/* b8 */
	.long	L2dae		/* b9 */
	.long	L2dae		/* ba */
	.long	L2dae		/* bb */
	.long	L2dae		/* bc */
	.long	L2dae		/* bd */
	.long	L2dae		/* be */
	.long	L2dae		/* bf */
	.long	L2dc1		/* c0 */
	.long	L2e21		/* c1 */
	.long	L2ecb		/* c2 */
	.long	L2ef1		/* c3 */
	.long	L2ef8		/* c4 */
	.long	L2f1d		/* c5 */
	.long	L2f27		/* c6 */
	.long	L2f36		/* c7 */
	.long	L2f46		/* c8 */
	.long	L2fab		/* c9 */
	.long	L2fda		/* ca */
	.long	L300f		/* cb */
	.long	L1e4c		/* cc */
	.long	L3016		/* cd */
	.long	L304f		/* ce */
	.long	L3054		/* cf */
	.long	L3096		/* d0 */
	.long	L30f3		/* d1 */
	.long	L319a		/* d2 */
	.long	L31ac		/* d3 */
	.long	L31be		/* d4 */
	.long	L31d0		/* d5 */
	.long	L1e4c		/* d6 */
	.long	L31e2		/* d7 */
	.long	L3212		/* d8 */
	.long	L3212		/* d9 */
	.long	L3212		/* da */
	.long	L3212		/* db */
	.long	L3212		/* dc */
	.long	L3212		/* dd */
	.long	L3212		/* de */
	.long	L3212		/* df */
	.long	L3217		/* e0 */
	.long	L3238		/* e1 */
	.long	L3259		/* e2 */
	.long	L326c		/* e3 */
	.long	L3280		/* e4 */
	.long	L328a		/* e5 */
	.long	L3294		/* e6 */
	.long	L329e		/* e7 */
	.long	L32a8		/* e8 */
	.long	L32c3		/* e9 */
	.long	L32dc		/* ea */
	.long	L32fd		/* eb */
	.long	L3315		/* ec */
	.long	L332c		/* ed */
	.long	L334d		/* ee */
	.long	L33c1		/* ef */
	.long	L1e40		/* f0 */
	.long	L1e4c		/* f1 */
	.long	L33dd		/* f2 */
	.long	L33e9		/* f3 */
	.long	L1e4c		/* f4 */
	.long	L33f5		/* f5 */
	.long	L3401		/* f6 */
	.long	L346d		/* f7 */
	.long	L3534		/* f8 */
	.long	L3540		/* f9 */
	.long	L354c		/* fa */
	.long	L355b		/* fb */
	.long	L356a		/* fc */
	.long	L3579		/* fd */
	.long	L3588		/* fe */
	.long	L35b4		/* ff */

/* Ltab_4190 -- 16-bit effective address: (mod,rm) x 4, indexed by the rotated modrm */
Ltab_4190:
	.long	L38ec		/* 00 */
	.long	L39bf		/* 01 */
	.long	L3a67		/* 02 */
	.long	L3b08		/* 03 */
	.long	L3954		/* 04 */
	.long	L39d4		/* 05 */
	.long	L3a80		/* 06 */
	.long	L3b10		/* 07 */
	.long	L3968		/* 08 */
	.long	L39ec		/* 09 */
	.long	L3a98		/* 0a */
	.long	L3b18		/* 0b */
	.long	L397c		/* 0c */
	.long	L3a04		/* 0d */
	.long	L3ab0		/* 0e */
	.long	L3b20		/* 0f */
	.long	L3990		/* 10 */
	.long	L3a1c		/* 11 */
	.long	L3ac8		/* 12 */
	.long	L3b48		/* 13 */
	.long	L399c		/* 14 */
	.long	L3a2c		/* 15 */
	.long	L3ad8		/* 16 */
	.long	L3b50		/* 17 */
	.long	L39a8		/* 18 */
	.long	L3a3c		/* 19 */
	.long	L3ae8		/* 1a */
	.long	L3b58		/* 1b */
	.long	L39b4		/* 1c */
	.long	L3a58		/* 1d */
	.long	L3af8		/* 1e */
	.long	L3b60		/* 1f */
	.long	L3b68		/* 20 */
	.long	L3bbc		/* 21 */
	.long	L3c2c		/* 22 */
	.long	L3b08		/* 23 */
	.long	L3b74		/* 24 */
	.long	L3bcc		/* 25 */
	.long	L3c3c		/* 26 */
	.long	L3b10		/* 27 */
	.long	L3b80		/* 28 */
	.long	L3bdc		/* 29 */
	.long	L3c4c		/* 2a */
	.long	L3b18		/* 2b */
	.long	L3b8c		/* 2c */
	.long	L3bec		/* 2d */
	.long	L3c5c		/* 2e */
	.long	L3b20		/* 2f */
	.long	L3c9c		/* 30 */
	.long	L3cc0		/* 31 */
	.long	L3cd0		/* 32 */
	.long	L3b48		/* 33 */
	.long	L3b98		/* 34 */
	.long	L3bfc		/* 35 */
	.long	L3c6c		/* 36 */
	.long	L3b50		/* 37 */
	.long	L3ba4		/* 38 */
	.long	L3c0c		/* 39 */
	.long	L3c7c		/* 3a */
	.long	L3b58		/* 3b */
	.long	L3bb0		/* 3c */
	.long	L3c1c		/* 3d */
	.long	L3c8c		/* 3e */
	.long	L3b60		/* 3f */

/* Ltab_4290 -- 32-bit effective address: the same index over the 0x67 forms */
Ltab_4290:
	.long	L38ec		/* 00 */
	.long	L39bf		/* 01 */
	.long	L3a67		/* 02 */
	.long	L3b08		/* 03 */
	.long	L3954		/* 04 */
	.long	L39d4		/* 05 */
	.long	L3a80		/* 06 */
	.long	L3b10		/* 07 */
	.long	L3968		/* 08 */
	.long	L39ec		/* 09 */
	.long	L3a98		/* 0a */
	.long	L3b18		/* 0b */
	.long	L397c		/* 0c */
	.long	L3a04		/* 0d */
	.long	L3ab0		/* 0e */
	.long	L3b20		/* 0f */
	.long	L3990		/* 10 */
	.long	L3a1c		/* 11 */
	.long	L3ac8		/* 12 */
	.long	L3b28		/* 13 */
	.long	L399c		/* 14 */
	.long	L3a2c		/* 15 */
	.long	L3ad8		/* 16 */
	.long	L3b30		/* 17 */
	.long	L39a8		/* 18 */
	.long	L3a3c		/* 19 */
	.long	L3ae8		/* 1a */
	.long	L3b38		/* 1b */
	.long	L39b4		/* 1c */
	.long	L3a58		/* 1d */
	.long	L3af8		/* 1e */
	.long	L3b40		/* 1f */
	.long	L3b68		/* 20 */
	.long	L3bbc		/* 21 */
	.long	L3c2c		/* 22 */
	.long	L3b08		/* 23 */
	.long	L3b74		/* 24 */
	.long	L3bcc		/* 25 */
	.long	L3c3c		/* 26 */
	.long	L3b10		/* 27 */
	.long	L3b80		/* 28 */
	.long	L3bdc		/* 29 */
	.long	L3c4c		/* 2a */
	.long	L3b18		/* 2b */
	.long	L3b8c		/* 2c */
	.long	L3bec		/* 2d */
	.long	L3c5c		/* 2e */
	.long	L3b20		/* 2f */
	.long	L3c9c		/* 30 */
	.long	L3cc0		/* 31 */
	.long	L3cd0		/* 32 */
	.long	L3b28		/* 33 */
	.long	L3b98		/* 34 */
	.long	L3bfc		/* 35 */
	.long	L3c6c		/* 36 */
	.long	L3b30		/* 37 */
	.long	L3ba4		/* 38 */
	.long	L3c0c		/* 39 */
	.long	L3c7c		/* 3a */
	.long	L3b38		/* 3b */
	.long	L3bb0		/* 3c */
	.long	L3c1c		/* 3d */
	.long	L3c8c		/* 3e */
	.long	L3b40		/* 3f */

/* Ltab_4390 -- 8-bit register operands: al cl dl bl ah ch dh bh */
Ltab_4390:
	.long	Lregs		/* 00 */
	.long	Lregs+4		/* 01 */
	.long	Lregs+8		/* 02 */
	.long	Lregs+12		/* 03 */
	.long	Lregs+1		/* 04 */
	.long	Lregs+5		/* 05 */
	.long	Lregs+9		/* 06 */
	.long	Lregs+13		/* 07 */

/* Ltab_43b0 -- group table for the 0x80/0x81/0x83 and 0x0F 0xBA forms */
Ltab_43b0:
	.long	L1ee1		/* 00 */
	.long	L1f3c		/* 01 */
	.long	L1ee8		/* 02 */
	.long	L1f49		/* 03 */
	.long	L1eef		/* 04 */
	.long	L1f56		/* 05 */
	.long	L1efd		/* 06 */
	.long	L1f72		/* 07 */
	.long	L1f0b		/* 08 */
	.long	L1f8e		/* 09 */
	.long	L1f12		/* 0a */
	.long	L1f9b		/* 0b */
	.long	L1f19		/* 0c */
	.long	L1fa8		/* 0d */
	.long	L1f20		/* 0e */
	.long	L1fb5		/* 0f */

/* Ltab_43f0 -- group table */
Ltab_43f0:
	.long	L2dd4		/* 00 */
	.long	L2e34		/* 01 */
	.long	L2de2		/* 02 */
	.long	L2e50		/* 03 */
	.long	L2df0		/* 04 */
	.long	L2e6c		/* 05 */
	.long	L2dfe		/* 06 */
	.long	L2e88		/* 07 */
	.long	L2e0c		/* 08 */
	.long	L2ea4		/* 09 */
	.long	L2e13		/* 0a */
	.long	L2eb1		/* 0b */
	.long	L2e0c		/* 0c */
	.long	L2ea4		/* 0d */
	.long	L2e1a		/* 0e */
	.long	L2ebe		/* 0f */

/* Ltab_4430 -- group table */
Ltab_4430:
	.long	L30a6		/* 00 */
	.long	L3103		/* 01 */
	.long	L30b4		/* 02 */
	.long	L311f		/* 03 */
	.long	L30c2		/* 04 */
	.long	L313b		/* 05 */
	.long	L30d0		/* 06 */
	.long	L3157		/* 07 */
	.long	L30de		/* 08 */
	.long	L3173		/* 09 */
	.long	L30e5		/* 0a */
	.long	L3180		/* 0b */
	.long	L30de		/* 0c */
	.long	L3173		/* 0d */
	.long	L30ec		/* 0e */
	.long	L318d		/* 0f */

/* Ltab_4470 -- group table */
Ltab_4470:
	.long	L3411		/* 00 */
	.long	L347d		/* 01 */
	.long	L3411		/* 02 */
	.long	L347d		/* 03 */
	.long	L341b		/* 04 */
	.long	L348e		/* 05 */
	.long	L3422		/* 06 */
	.long	L349b		/* 07 */
	.long	L3429		/* 08 */
	.long	L34a8		/* 09 */
	.long	L343a		/* 0a */
	.long	L34cb		/* 0b */
	.long	L344b		/* 0c */
	.long	L34ee		/* 0d */
	.long	L345c		/* 0e */
	.long	L3511		/* 0f */

/* Ltab_44b0 -- group table */
Ltab_44b0:
	.long	L3598		/* 00 */
	.long	L2134		/* 01 */
	.long	L35a6		/* 02 */
	.long	L215a		/* 03 */
	.long	L1e4c		/* 04 */
	.long	L35c4		/* 05 */
	.long	L1e4c		/* 06 */
	.long	L2748		/* 07 */
	.long	L1e4c		/* 08 */
	.long	L35da		/* 09 */
	.long	L1e4c		/* 0a */
	.long	L32e1		/* 0b */
	.long	L1e4c		/* 0c */
	.long	L35e8		/* 0d */
	.long	L1e4c		/* 0e */
	.long	L1e4c		/* 0f */

/* Ltab_44f0 -- modrm-indexed table reached as Ltab_44f0-0x200(,%edx,4) */
Ltab_44f0:
	.long	L35ef		/* 00 */
	.long	L35ef		/* 01 */
	.long	L35ef		/* 02 */
	.long	L35ef		/* 03 */
	.long	L35ef		/* 04 */
	.long	L35ef		/* 05 */
	.long	L35ef		/* 06 */
	.long	L35ef		/* 07 */
	.long	L35ef		/* 08 */
	.long	L35ef		/* 09 */
	.long	L35ef		/* 0a */
	.long	L35ef		/* 0b */
	.long	L35ef		/* 0c */
	.long	L35ef		/* 0d */
	.long	L35ef		/* 0e */
	.long	L35ef		/* 0f */
	.long	L3604		/* 10 */
	.long	L3604		/* 11 */
	.long	L3604		/* 12 */
	.long	L3604		/* 13 */
	.long	L3604		/* 14 */
	.long	L3604		/* 15 */
	.long	L3604		/* 16 */
	.long	L3604		/* 17 */
	.long	L3604		/* 18 */
	.long	L3604		/* 19 */
	.long	L3604		/* 1a */
	.long	L3604		/* 1b */
	.long	L3604		/* 1c */
	.long	L3604		/* 1d */
	.long	L3604		/* 1e */
	.long	L3604		/* 1f */
	.long	L3615		/* 20 */
	.long	L361f		/* 21 */
	.long	L1e4c		/* 22 */
	.long	L3629		/* 23 */
	.long	L3643		/* 24 */
	.long	L3669		/* 25 */
	.long	L1e4c		/* 26 */
	.long	L1e4c		/* 27 */
	.long	L367e		/* 28 */
	.long	L3688		/* 29 */
	.long	L1e4c		/* 2a */
	.long	L3692		/* 2b */
	.long	L36ac		/* 2c */
	.long	L36d2		/* 2d */
	.long	L1e4c		/* 2e */
	.long	L36e7		/* 2f */
	.long	L36f8		/* 30 */
	.long	L3718		/* 31 */
	.long	L373c		/* 32 */
	.long	L3746		/* 33 */
	.long	L3760		/* 34 */
	.long	L376a		/* 35 */
	.long	L3774		/* 36 */
	.long	L3786		/* 37 */
	.long	L1e4c		/* 38 */
	.long	L1e4c		/* 39 */
	.long	L3798		/* 3a */
	.long	L37b6		/* 3b */
	.long	L37d0		/* 3c */
	.long	L37f5		/* 3d */
	.long	L381a		/* 3e */
	.long	L382c		/* 3f */
	.long	L383e		/* 40 */
	.long	L3854		/* 41 */
	.long	L1e4c		/* 42 */
	.long	L1e4c		/* 43 */
	.long	L1e4c		/* 44 */
	.long	L1e4c		/* 45 */
	.long	L1e4c		/* 46 */
	.long	L1e4c		/* 47 */
	.long	L387b		/* 48 */
	.long	L387b		/* 49 */
	.long	L387b		/* 4a */
	.long	L387b		/* 4b */
	.long	L387b		/* 4c */
	.long	L387b		/* 4d */
	.long	L387b		/* 4e */
	.long	L387b		/* 4f */

/* Ltab_4630 -- group table */
Ltab_4630:
	.long	L3635		/* 00 */
	.long	L369e		/* 01 */
	.long	L3752		/* 02 */
	.long	L37c2		/* 03 */

/* Ltab_4640 -- condition-code stubs, in tttn order */
Ltab_4640:
	.long	L3d29		/* 00 */
	.long	L3d2d		/* 01 */
	.long	L3d31		/* 02 */
	.long	L3d35		/* 03 */
	.long	L3d39		/* 04 */
	.long	L3d3d		/* 05 */
	.long	L3d41		/* 06 */
	.long	L3d45		/* 07 */
	.long	L3d49		/* 08 */
	.long	L3d4d		/* 09 */
	.long	L3d51		/* 0a */
	.long	L3d55		/* 0b */
	.long	L3d59		/* 0c */
	.long	L3d5d		/* 0d */
	.long	L3d61		/* 0e */
	.long	L3d65		/* 0f */

/*
 * The interpreter's state.  Ninety-two bytes of zeros in __DATA,__data --
 * not __bss, which is where a zero-initialised C static of any scope would
 * land -- carrying no symbol at all.  Every label here is `L'-prefixed and
 * so never reaches the symbol table, which is what the reference shows.
 */
	.data
	.align	2,0x00
Lstate:
	.space	4			/* lowMemBase, guest physical 0 */
Lpageperm:
	.space	4			/* one byte per 4 KB page */
Lioperm:
	.space	4			/* one bit per I/O port */
Lsmmport:
	.space	4
Lregs:
	.space	32			/* eax ecx edx ebx esp ebp esi edi */
Leip:
	.space	4
Leflags:
	.space	4
Lsregs:
	.space	24			/* es cs ss ds fs gs, linear once converted */
	.space	4			/* referenced by nothing */
Ldesc:
	.space	4			/* current-instruction descriptor; byte 0 is
					   the effective data segment as a byte
					   offset from es, byte 1 the segment used
					   for bp-relative addressing, byte 2 the
					   repeat prefix and byte 3 is or-ed into
					   the modrm dispatch index */
Lhostfl:
	.space	4			/* host EFLAGS at entry, masked 0xFFFFF700 */
