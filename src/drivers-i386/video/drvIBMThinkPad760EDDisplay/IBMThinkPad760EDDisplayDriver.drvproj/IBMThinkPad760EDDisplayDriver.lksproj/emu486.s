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
 * This file is a transcription of __text 7708..18204 of Apple's
 * IBMThinkPad760EDDisplayDriver_reloc.  The slice is 10496 bytes; `_emu486'
 * is the only exported symbol.  Unnamed bodies at 15796 and 15877 stay in
 * this file as `L3db4' and `L3e05', not `.globl'.  Labels are named for the
 * reference address they sit at, so `L1ebc' is the shared dispatch point at
 * reference __text 0x1EBC.  They are all `L'-prefixed, which the assembler
 * keeps out of the symbol table, exactly as in the reference.
 *
 * Apple's VGA_reloc carries a second copy of the same source 156 bytes
 * lower (__text 7552..18048).  After masking 32-bit relocs, that copy's
 * instruction stream matches this dump; reloc addends differ (text targets
 * +156, data targets +1808).  This dump wins.  Data labels stay symbolic
 * (`Lstate' and friends); do not copy VGA `__data' addresses.
 *
 * Entry contract, from -[vidBIOS int10:outregs:iorange:ionum:smmport:]:
 *
 *	int emu486(void *lowMemBase, const emu486regs_t *inregs,
 *		   emu486regs_t *outregs, const char *pagePerm,
 *		   const char *ioPerm, unsigned int smmport);
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
 *   1. Ltab_46dc slot 11 points at a `setno' stub where the condition order
 *      calls for `setnp', so guest JNP/JPO, SETNP/SETPO and LOOPNP evaluate
 *      as "not overflow".  All fifteen other slots are correct.
 *   2. The 32-bit CMPS handler's repeat-prefix test at L2b1d branches to
 *      L2b73 -- the middle of the 32-bit TEST handler -- instead of to the
 *      "is it 0xF3" test at L2b2a, so CMPSD and REPE CMPSD are mishandled.
 *      The 16-bit path immediately above it is correct.
 *   3. The 32-bit SCAS handler's repeat-prefix test at L2da2 branches to
 *      L2ee4, the 32-bit ROL handler, instead of to L2db3, so SCASD and
 *      REPE SCASD are mishandled.  This is the only 32-bit displacement in
 *      the whole function that carries no relocation, i.e. the only branch
 *      whose operand the reference's assembler resolved as a constant.
 *
 * The blocks at L2b2a and L2db3 are unreachable because of defects 2 and 3;
 * they are kept so the byte stream matches.
 *
 * Two encodings are written out by hand.  cmpxchg is emitted as the i486
 * A-step 0F A6 / 0F A7 opcodes, which is what the reference contains, and
 * every branch to one of the shared tails is emitted in the long form,
 * which is what the reference contains even where a short displacement
 * would reach.  Both are pinned so the assembler cannot choose otherwise.
 *
 * Apple's /usr/libexec/i386/as rejects a prefix and a string opcode on the
 * same line (`rep movsl') and rejects `aam $0xa' / `aad $0xa'.  `rep; movsl'
 * and bare `aam'/`aad' are the same encodings (F3 A5, D4 0A, D5 0A).
 *
 * Not named through CLASSES or OTHERLINKED (OTHERLINKED would place this
 * object before `_instance.o').  Task 7 wires it after instance via
 * LOADABLES in Makefile.postamble.
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
 * the interpreter loop.  L1ebc re-saves the guest flags, L1ec4 is
 * re-entered by handlers that saved them already, and L1edc fetches the
 * next opcode byte and dispatches on it
 */
	nop
L1ebc:
	pushfl
	popl	%eax
	movl	%eax,Leflags
	nop
L1ec4:
	cmpl	%esi,Lstate
	.byte	0x0f,0x84		/* je L1ef2, long form as in the reference */
	.long	L1ef2-.-4
	movl	$0x80c,Ldesc
	movb	$2,%bl
L1edc:
	xorl	%edx,%edx
	movb	(%esi),%dl
	incl	%esi
	jmp	*Ltab_3e2c(,%edx,4)

/*
 * the exit path.  L1ee8 is the invalid-opcode return, L1ef2 the normal
 * one; L1ef4 undoes the segment conversion, copies the register block
 * out to outregs and returns eax
 */
L1ee8:
	movl	$0x1000000,%eax
	.byte	0xe9			/* jmp L1ef4, long form */
	.long	L1ef4-.-4
L1ef2:
	xorl	%eax,%eax
L1ef4:
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
 * the per-opcode handlers, reached through Ltab_3e2c and the group
 * tables.  They are not uniform: most end by jumping back to L1ebc, the
 * rest to one of the other shared tails, and a few simply return
 */
L1f68:
	call	L392f
	call	L3958
	movb	(%eax),%cl
L1f74:
	andb	$0x38,%dl
	jmp	*Ltab_444c(%edx)
L1f7d:
	addb	%cl,(%edi)
	jmp	L1ebc
L1f84:
	orb	%cl,(%edi)
	jmp	L1ebc
L1f8b:
	movb	Leflags,%ah
	sahf
	adcb	%cl,(%edi)
	jmp	L1ebc
L1f99:
	movb	Leflags,%ah
	sahf
	sbbb	%cl,(%edi)
	jmp	L1ebc
L1fa7:
	andb	%cl,(%edi)
	jmp	L1ebc
L1fae:
	subb	%cl,(%edi)
	jmp	L1ebc
L1fb5:
	xorb	%cl,(%edi)
	jmp	L1ebc
L1fbc:
	cmpb	%cl,(%edi)
	jmp	L1ebc
L1fc3:
	call	L393d
	call	L3970
	movl	(%eax),%ecx
L1fcf:
	andb	$0x38,%dl
	jmp	*Ltab_444c+4(%edx)
L1fd8:
	cmpb	$4,%bl
	je	L1fde
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L1fde:
	addl	%ecx,(%edi)
	jmp	L1ebc
L1fe5:
	cmpb	$4,%bl
	je	L1feb
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L1feb:
	orl	%ecx,(%edi)
	jmp	L1ebc
L1ff2:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L2006
	sahf
	adcw	%cx,(%edi)
	jmp	L1ebc
L2006:
	sahf
	adcl	%ecx,(%edi)
	jmp	L1ebc
L200e:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L2022
	sahf
	sbbw	%cx,(%edi)
	jmp	L1ebc
L2022:
	sahf
	sbbl	%ecx,(%edi)
	jmp	L1ebc
L202a:
	cmpb	$4,%bl
	je	L2030
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L2030:
	andl	%ecx,(%edi)
	jmp	L1ebc
L2037:
	cmpb	$4,%bl
	je	L203d
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L203d:
	subl	%ecx,(%edi)
	jmp	L1ebc
L2044:
	cmpb	$4,%bl
	je	L204a
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L204a:
	xorl	%ecx,(%edi)
	jmp	L1ebc
L2051:
	cmpb	$4,%bl
	je	L2057
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L2057:
	cmpl	%ecx,(%edi)
	jmp	L1ebc
L205e:
	call	L392f
	call	L3958
	movb	(%edi),%cl
	movl	%eax,%edi
	jmp	L1f74
L2071:
	call	L393d
	call	L3970
	movl	(%edi),%ecx
	movl	%eax,%edi
	jmp	L1fcf
L2084:
	movb	(%esi),%cl
	incl	%esi
	movl	$Lregs,%edi
	jmp	L1f74
L2091:
	movl	(%esi),%ecx
	addl	%ebx,%esi
	movl	$Lregs,%edi
	jmp	L1fcf
L209f:
	movl	Lsregs,%eax
L20a4:
	subl	Lstate,%eax
	shrl	$4,%eax
	jmp	L221c
L20b2:
	movl	$Lsregs,%ecx
L20b7:
	movl	Lregs+16,%edi
	addl	$2,%edi
	movl	%edi,Lregs+16
	addl	Lsregs+8,%edi
	movzwl	-2(%edi),%eax
	shll	$4,%eax
	addl	Lstate,%eax
	movl	%eax,(%ecx)
	jmp	L1ec4
L20e0:
	movl	Lsregs+4,%eax
	.byte	0xe9			/* jmp L20a4, long form */
	.long	L20a4-.-4
L20ea:
	movb	(%esi),%dl
	incl	%esi
	cmpb	$0x80,%dl
	jb	L1ee8
	cmpb	$0xd0,%dl
	jae	L1ee8
	jmp	*Ltab_458c-0x200(,%edx,4)
L2106:
	movl	Lsregs+8,%eax
	.byte	0xe9			/* jmp L20a4, long form */
	.long	L20a4-.-4
L2110:
	movl	$Lsregs+8,%ecx
	.byte	0xe9			/* jmp L20b7, long form */
	.long	L20b7-.-4
L211a:
	movl	Lsregs+12,%eax
	.byte	0xe9			/* jmp L20a4, long form */
	.long	L20a4-.-4
L2124:
	movl	$Lsregs+12,%ecx
	.byte	0xe9			/* jmp L20b7, long form */
	.long	L20b7-.-4
L212e:
	movw	$0,Ldesc
	jmp	L1edc
L213c:
	movb	Leflags,%ah
	sahf
	.byte	0x8a,0x05		/* movb	Lregs,%al */
	.long	Lregs
	daa
	.byte	0x88,0x05		/* movb	%al,Lregs */
	.long	Lregs
	jmp	L1ebc
L2155:
	movw	$0x404,Ldesc
	jmp	L1edc
L2163:
	movb	Leflags,%ah
	sahf
	.byte	0x8a,0x05		/* movb	Lregs,%al */
	.long	Lregs
	das
	.byte	0x88,0x05		/* movb	%al,Lregs */
	.long	Lregs
	jmp	L1ebc
L217c:
	movw	$0x808,Ldesc
	jmp	L1edc
L218a:
	movb	Leflags,%ah
	sahf
	movl	Lregs,%eax
	aaa
	movl	%eax,Lregs
	jmp	L1ebc
L21a1:
	movw	$0xc0c,Ldesc
	jmp	L1edc
L21af:
	movb	Leflags,%ah
	sahf
	movl	Lregs,%eax
	aas
	movl	%eax,Lregs
	jmp	L1ebc
L21c6:
	andb	$7,%dl
	leal	Lregs(,%edx,4),%edi
L21d0:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L21e4
	sahf
	incw	(%edi)
	jmp	L1ebc
L21e4:
	sahf
	incl	(%edi)
	jmp	L1ebc
L21ec:
	andb	$7,%dl
	leal	Lregs(,%edx,4),%edi
L21f6:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L220a
	sahf
	decw	(%edi)
	jmp	L1ebc
L220a:
	sahf
	decl	(%edi)
	jmp	L1ebc
L2212:
	andb	$7,%dl
	movl	Lregs(,%edx,4),%eax
L221c:
	cmpb	$4,%bl
	je	L223e
	movl	Lregs+16,%edi
	subl	$2,%edi
	movl	%edi,Lregs+16
	addl	Lsregs+8,%edi
	movw	%ax,(%edi)
	jmp	L1ec4
L223e:
	movl	Lregs+16,%edi
	subl	$4,%edi
	movl	%edi,Lregs+16
	addl	Lsregs+8,%edi
	movl	%eax,(%edi)
	jmp	L1ec4
L225a:
	andb	$7,%dl
	leal	Lregs(,%edx,4),%edi
L2264:
	cmpb	$4,%bl
	je	L228a
	movl	Lregs+16,%ecx
	addl	$2,%ecx
	movl	%ecx,Lregs+16
	addl	Lsregs+8,%ecx
	movw	-2(%ecx),%ax
	movw	%ax,(%edi)
	jmp	L1ec4
L228a:
	movl	Lregs+16,%ecx
	addl	$4,%ecx
	movl	%ecx,Lregs+16
	addl	Lsregs+8,%ecx
	movl	-4(%ecx),%eax
	movl	%eax,(%edi)
	jmp	L1ec4
L22a9:
	cmpb	$4,%bl
	je	L2308
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
	jmp	L1ec4
L2308:
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
	jmp	L1ec4
L235e:
	cmpb	$4,%bl
	je	L23bc
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
	jmp	L1ec4
L23bc:
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
	jmp	L1ec4
L240e:
	jmp	L1ee8
L2413:
	jmp	L1ee8
L2418:
	movw	$0x1010,Ldesc
	jmp	L1edc
L2426:
	movw	$0x1414,Ldesc
	jmp	L1edc
L2434:
	movb	$4,%bl
	jmp	L1edc
L243b:
	movb	$0x80,Ldesc+3
	jmp	L1edc
L2447:
	movl	(%esi),%eax
	addl	%ebx,%esi
	jmp	L221c
L2450:
	call	L393d
	call	L3970
	movl	(%esi),%ecx
	addl	%ebx,%esi
L245e:
	cmpb	$4,%bl
	je	L246f
	imulw	(%edi),%cx
	movw	%cx,(%eax)
	jmp	L1ebc
L246f:
	imull	(%edi),%ecx
	movl	%ecx,(%eax)
	jmp	L1ebc
L2479:
	movsbl	(%esi),%eax
	incl	%esi
	jmp	L221c
L2482:
	call	L393d
	call	L3970
	movsbl	(%esi),%ecx
	incl	%esi
	.byte	0xe9			/* jmp L245e, long form */
	.long	L245e-.-4
L2495:
	movl	Lhostfl,%eax
	andl	$0x400,%eax
	orl	Leflags,%eax
	pushl	%eax
	popfl
	movzwl	Lregs+28,%edi
	addl	Lsregs,%edi
	movl	Lregs+8,%edx
	call	L3e05
	movzwl	Lregs+4,%ecx
	cmpb	$2,Ldesc+2
	jne	L24d0
	.byte	0xf3
L24d0:
	insb
	movw	%cx,Lregs+4
	subl	Lsregs,%edi
	movw	%di,Lregs+28
	cld
	jmp	L1ec4
L24eb:
	movl	Lhostfl,%eax
	andl	$0x400,%eax
	orl	Leflags,%eax
	pushl	%eax
	popfl
	movzwl	Lregs+28,%edi
	addl	Lsregs,%edi
	movl	Lregs+8,%edx
	call	L3e05
	movzwl	Lregs+4,%ecx
	cmpb	$4,%bl
	je	L252f
	cmpb	$2,Ldesc+2
	jne	L252b
	.byte	0xf3
L252b:
	insw
	jmp	L253a
L252f:
	cmpb	$2,Ldesc+2
	jne	L2539
	.byte	0xf3
L2539:
	insl
L253a:
	movw	%cx,Lregs+4
	subl	Lsregs,%edi
	movw	%di,Lregs+28
	cld
	jmp	L1ec4
L2554:
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
	call	L3e05
	movzwl	Lregs+4,%ecx
	cmpb	$2,Ldesc+2
	jne	L2598
	.byte	0xf3
L2598:
	outsb
	movw	%cx,Lregs+4
	subl	%edi,%esi
	movw	%si,Lregs+24
	popl	%esi
	cld
	jmp	L1ec4
L25b0:
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
	call	L3e05
	movzwl	Lregs+4,%ecx
	cmpb	$4,%bl
	je	L25fd
	cmpb	$2,Ldesc+2
	jne	L25f9
	.byte	0xf3
L25f9:
	outsw
	jmp	L2608
L25fd:
	cmpb	$2,Ldesc+2
	jne	L2607
	.byte	0xf3
L2607:
	outsl
L2608:
	movw	%cx,Lregs+4
	subl	%edi,%esi
	movw	%si,Lregs+24
	popl	%esi
	cld
	jmp	L1ec4
L261f:
	call	L3db4
	testb	%al,%al
	jne	L3399
	incl	%esi
	jmp	L1ec4
L2632:
	movb	(%esi),%dl
	call	L3958
	movb	(%esi),%cl
	incl	%esi
	jmp	L1f74
L2641:
	movb	(%esi),%dl
	call	L3970
	movl	(%esi),%ecx
	addl	%ebx,%esi
	jmp	L1fcf
L2651:
	movb	(%esi),%dl
	call	L3970
	movsbl	(%esi),%ecx
	incl	%esi
	jmp	L1fcf
L2661:
	call	L392f
	call	L3958
	movb	(%eax),%cl
	testb	%cl,(%edi)
	jmp	L1ebc
L2674:
	call	L393d
	call	L3970
	movl	(%eax),%ecx
	cmpb	$4,%bl
	je	L2686
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L2686:
	testl	%ecx,(%edi)
	jmp	L1ebc
L268d:
	call	L392f
	call	L3958
	movb	(%eax),%cl
	xchgb	%cl,(%edi)
	movb	%cl,(%eax)
	jmp	L1ec4
L26a2:
	call	L393d
	call	L3970
	cmpb	$4,%bl
	je	L26bf
	movw	(%eax),%cx
	xchgw	%cx,(%edi)
	movw	%cx,(%eax)
	jmp	L1ec4
L26bf:
	movl	(%eax),%ecx
	xchgl	%ecx,(%edi)
	movl	%ecx,(%eax)
	jmp	L1ec4
L26ca:
	call	L392f
	call	L3958
	movb	(%eax),%cl
	movb	%cl,(%edi)
	jmp	L1ec4
L26dd:
	call	L393d
	call	L3970
	movl	(%eax),%ecx
	movl	%edi,%eax
	.byte	0xe9			/* jmp L270f, long form */
	.long	L270f-.-4
L26f0:
	call	L392f
	call	L3958
	movb	(%edi),%cl
	movb	%cl,(%eax)
	jmp	L1ec4
L2703:
	call	L393d
	call	L3970
	movl	(%edi),%ecx
L270f:
	cmpb	$4,%bl
	je	L2715
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L2715:
	movl	%ecx,(%eax)
	jmp	L1ec4
L271c:
	call	L394a
	call	L3970
	movl	(%eax),%ecx
	subl	Lstate,%ecx
	shrl	$4,%ecx
	movw	%cx,(%edi)
	jmp	L1ec4
L2739:
	movw	$0x1818,Ldesc
	call	L393d
	call	L3970
	movl	%edi,%ecx
	.byte	0xe9			/* jmp L270f, long form */
	.long	L270f-.-4
L2753:
	call	L394a
	call	L3970
	movzwl	(%edi),%ecx
	shll	$4,%ecx
	addl	Lstate,%ecx
	movl	%ecx,(%eax)
	jmp	L1ec4
L2770:
	call	L3970
	jmp	L2264
L277a:
	andb	$7,%dl
	leal	Lregs(,%edx,4),%edi
	movl	Lregs,%eax
	movl	(%edi),%ecx
	cmpb	$4,%bl
	je	L279f
	movw	%ax,(%edi)
	movw	%cx,Lregs
	jmp	L1ec4
L279f:
	movl	%eax,(%edi)
	movl	%ecx,Lregs
	jmp	L1ec4
L27ac:
	movl	Lregs,%eax
	cmpb	$4,%bl
	je	L27b7
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L27b7:
	cwtl
	movl	%eax,Lregs
	jmp	L1ec4
L27c2:
	movl	Lregs,%eax
	movl	Lregs+8,%edx
	cmpb	$4,%bl
	je	L27d3
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L27d3:
	cltd
	movl	%edx,Lregs+8
	jmp	L1ec4
L27df:
	movl	%esi,%edi
	addl	$4,%esi
L27e4:
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
	jmp	L1ec4
L282c:
	movl	Leflags,%eax
	andl	$0x8ff,%eax
	orl	Lhostfl,%eax
	jmp	L221c
L2841:
	cmpb	$4,%bl
	je	L2867
	movl	Lregs+16,%ecx
	addl	$2,%ecx
	movl	%ecx,Lregs+16
	addl	Lsregs+8,%ecx
	movl	Leflags,%edx
	movw	-2(%ecx),%dx
	jmp	L287f
L2867:
	movl	Lregs+16,%ecx
	addl	$4,%ecx
	movl	%ecx,Lregs+16
	addl	Lsregs+8,%ecx
	movl	-4(%ecx),%edx
L287f:
	movl	%edx,%eax
	andl	$0xfffff700,%eax
	movl	%eax,Lhostfl
	andl	$0xfffff700,Leflags
	andl	$0x8ff,%edx
	orl	%edx,Leflags
	jmp	L1ec4
L28a6:
	.byte	0x8a,0x05		/* movb	Lregs+1,%al */
	.long	Lregs+1
	.byte	0x88,0x05		/* movb	%al,Leflags */
	.long	Leflags
	jmp	L1ec4
L28b7:
	.byte	0x8a,0x05		/* movb	Leflags,%al */
	.long	Leflags
	.byte	0x88,0x05		/* movb	%al,Lregs+1 */
	.long	Lregs+1
	jmp	L1ec4
L28c8:
	movzwl	(%esi),%edi
	addl	$2,%esi
	movb	Ldesc,%dl
	addl	Lsregs(%edx),%edi
	call	L39b3
	movb	(%edi),%al
	.byte	0x88,0x05		/* movb	%al,Lregs */
	.long	Lregs
	jmp	L1ec4
L28ec:
	movzwl	(%esi),%edi
	addl	$2,%esi
	movb	Ldesc,%dl
	addl	Lsregs(%edx),%edi
	call	L39b3
	movl	(%edi),%eax
	cmpb	$4,%bl
	je	L290b
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L290b:
	movl	%eax,Lregs
	jmp	L1ec4
L2915:
	movzwl	(%esi),%edi
	addl	$2,%esi
	movb	Ldesc,%dl
	addl	Lsregs(%edx),%edi
	call	L39b3
	.byte	0x8a,0x05		/* movb	Lregs,%al */
	.long	Lregs
	movb	%al,(%edi)
	jmp	L1ec4
L2939:
	movzwl	(%esi),%edi
	addl	$2,%esi
	movb	Ldesc,%dl
	addl	Lsregs(%edx),%edi
	call	L39b3
	movl	%edi,%eax
	movl	Lregs,%ecx
	jmp	L270f
L295d:
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
	jne	L29a3
	.byte	0xf3
L29a3:
	movsb
	movw	%cx,Lregs+4
	subl	%edx,%esi
	movw	%si,Lregs+24
	subl	Lsregs,%edi
	movw	%di,Lregs+28
	popl	%esi
	cld
	jmp	L1ec4
L29c8:
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
	je	L2a17
	cmpb	$2,Ldesc+2
	jne	L2a13
	.byte	0xf3
L2a13:
	movsw
	jmp	L2a22
L2a17:
	cmpb	$2,Ldesc+2
	jne	L2a21
	.byte	0xf3
L2a21:
	movsl
L2a22:
	movw	%cx,Lregs+4
	subl	%edx,%esi
	movw	%si,Lregs+24
	subl	Lsregs,%edi
	movw	%di,Lregs+28
	popl	%esi
	cld
	jmp	L1ec4
L2a46:
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
	jne	L2a8f
	repne; cmpsb
	jmp	L2a9a
L2a8f:
	cmpb	$2,Ldesc+2
	jne	L2a99
	.byte	0xf3
L2a99:
	cmpsb
L2a9a:
	pushfl
	movw	%cx,Lregs+4
	subl	%edx,%esi
	movw	%si,Lregs+24
	subl	Lsregs,%edi
	movw	%di,Lregs+28
	popfl
	popl	%esi
	cld
	jmp	L1ebc
L2ac0:
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
	je	L2b1d
	cmpb	$1,Ldesc+2
	jne	L2b0f
	repne; cmpsw
	jmp	L2b35
L2b0f:
	cmpb	$2,Ldesc+2
	jne	L2b19
	.byte	0xf3
L2b19:
	cmpsw
	jmp	L2b35

/* The 32-bit CMPS repeat dispatch.  The jne below should reach the
   "is it 0xF3" test at L2b2a, four bytes further on, the way the
   16-bit path at L2b01 reaches L2b0f.  It reaches L2b73 instead --
   the middle of the 32-bit TEST handler -- so CMPSD and REPE CMPSD
   are mishandled.  Transcribed as the reference has it. */
L2b1d:
	cmpb	$1,Ldesc+2
	jne	L2b73
	repne; cmpsl
	jmp	L2b35

/* Unreachable because of the branch above, and kept so the byte
   stream matches. */
L2b2a:
	cmpb	$2,Ldesc+2
	jne	L2b34
	.byte	0xf3
L2b34:
	cmpsl
L2b35:
	pushfl
	movw	%cx,Lregs+4
	subl	%edx,%esi
	movw	%si,Lregs+24
	subl	Lsregs,%edi
	movw	%di,Lregs+28
	popfl
	popl	%esi
	cld
	jmp	L1ebc
L2b5b:
	movb	(%esi),%al
	incl	%esi
	testb	%al,Lregs
	jmp	L1ebc
L2b69:
	movl	(%esi),%eax
	addl	%ebx,%esi
	cmpb	$4,%bl
	je	L2b73
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L2b73:
	testl	%eax,Lregs
	jmp	L1ebc
L2b7e:
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
	jne	L2bb3
	.byte	0xf3
L2bb3:
	stosb
	movw	%cx,Lregs+4
	subl	Lsregs,%edi
	movw	%di,Lregs+28
	cld
	jmp	L1ec4
L2bce:
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
	je	L2c0c
	cmpb	$2,Ldesc+2
	jne	L2c08
	.byte	0xf3
L2c08:
	stosw
	jmp	L2c17
L2c0c:
	cmpb	$2,Ldesc+2
	jne	L2c16
	.byte	0xf3
L2c16:
	stosl
L2c17:
	movw	%cx,Lregs+4
	subl	Lsregs,%edi
	movw	%di,Lregs+28
	cld
	jmp	L1ec4
L2c31:
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
	jne	L2c6a
	.byte	0xf3
L2c6a:
	lodsb
	movw	%cx,Lregs+4
	.byte	0x88,0x05		/* movb	%al,Lregs */
	.long	Lregs
	subl	%edx,%esi
	movw	%si,Lregs+24
	popl	%esi
	cld
	jmp	L1ec4
L2c88:
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
	je	L2cd0
	cmpb	$2,Ldesc+2
	jne	L2cc6
	.byte	0xf3
L2cc6:
	lodsw
	movw	%ax,Lregs
	jmp	L2ce0
L2cd0:
	cmpb	$2,Ldesc+2
	jne	L2cda
	.byte	0xf3
L2cda:
	lodsl
	movl	%eax,Lregs
L2ce0:
	movw	%cx,Lregs+4
	subl	%edx,%esi
	movw	%si,Lregs+24
	popl	%esi
	cld
	jmp	L1ec4
L2cf7:
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
	jne	L2d2f
	repne; scasb
	jmp	L2d3a
L2d2f:
	cmpb	$2,Ldesc+2
	jne	L2d39
	.byte	0xf3
L2d39:
	scasb
L2d3a:
	pushfl
	movw	%cx,Lregs+4
	subl	Lsregs,%edi
	movw	%di,Lregs+28
	popfl
	cld
	jmp	L1ebc
L2d56:
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
	je	L2da2
	cmpb	$1,Ldesc+2
	jne	L2d94
	repne; scasw
	jmp	L2dbe
L2d94:
	cmpb	$2,Ldesc+2
	jne	L2d9e
	.byte	0xf3
L2d9e:
	scasw
	jmp	L2dbe

/* The 32-bit SCAS repeat dispatch, with the same defect: the jne
   should reach L2db3 and reaches L2ee4, the 32-bit ROL handler.
   It is the only 32-bit branch displacement in the function that
   the reference stores without a relocation, i.e. the only one its
   assembler resolved as a constant rather than as a label. */
L2da2:
	cmpb	$1,Ldesc+2
	jne	L2ee4
	repne; scasl
	jmp	L2dbe

/* Unreachable because of the branch above, and kept so the byte
   stream matches. */
L2db3:
	cmpb	$2,Ldesc+2
	jne	L2dbd
	.byte	0xf3
L2dbd:
	scasl
L2dbe:
	pushfl
	movw	%cx,Lregs+4
	subl	Lsregs,%edi
	movw	%di,Lregs+28
	popfl
	cld
	jmp	L1ebc
L2dda:
	movb	(%esi),%al
	incl	%esi
	.byte	0x88,0x05		/* movb	%al,Lregs */
	.long	Lregs
	jmp	L1ec4
L2de8:
	movb	(%esi),%al
	incl	%esi
	.byte	0x88,0x05		/* movb	%al,Lregs+4 */
	.long	Lregs+4
	jmp	L1ec4
L2df6:
	movb	(%esi),%al
	incl	%esi
	.byte	0x88,0x05		/* movb	%al,Lregs+8 */
	.long	Lregs+8
	jmp	L1ec4
L2e04:
	movb	(%esi),%al
	incl	%esi
	.byte	0x88,0x05		/* movb	%al,Lregs+12 */
	.long	Lregs+12
	jmp	L1ec4
L2e12:
	movb	(%esi),%al
	incl	%esi
	.byte	0x88,0x05		/* movb	%al,Lregs+1 */
	.long	Lregs+1
	jmp	L1ec4
L2e20:
	movb	(%esi),%al
	incl	%esi
	.byte	0x88,0x05		/* movb	%al,Lregs+5 */
	.long	Lregs+5
	jmp	L1ec4
L2e2e:
	movb	(%esi),%al
	incl	%esi
	.byte	0x88,0x05		/* movb	%al,Lregs+9 */
	.long	Lregs+9
	jmp	L1ec4
L2e3c:
	movb	(%esi),%al
	incl	%esi
	.byte	0x88,0x05		/* movb	%al,Lregs+13 */
	.long	Lregs+13
	jmp	L1ec4
L2e4a:
	andb	$7,%dl
	leal	Lregs(,%edx,4),%eax
	movl	(%esi),%ecx
	addl	%ebx,%esi
	jmp	L270f
L2e5d:
	movb	(%esi),%dl
	call	L3958
	movb	(%esi),%cl
	incl	%esi
L2e67:
	andb	$0x38,%dl
	jmp	*Ltab_448c(%edx)
L2e70:
	movb	Leflags,%ah
	sahf
	rolb	%cl,(%edi)
	jmp	L1ebc
L2e7e:
	movb	Leflags,%ah
	sahf
	rorb	%cl,(%edi)
	jmp	L1ebc
L2e8c:
	movb	Leflags,%ah
	sahf
	rclb	%cl,(%edi)
	jmp	L1ebc
L2e9a:
	movb	Leflags,%ah
	sahf
	rcrb	%cl,(%edi)
	jmp	L1ebc
L2ea8:
	shlb	%cl,(%edi)
	jmp	L1ebc
L2eaf:
	shrb	%cl,(%edi)
	jmp	L1ebc
L2eb6:
	sarb	%cl,(%edi)
	jmp	L1ebc
L2ebd:
	movb	(%esi),%dl
	call	L3970
	movb	(%esi),%cl
	incl	%esi
L2ec7:
	andb	$0x38,%dl
	jmp	*Ltab_448c+4(%edx)
L2ed0:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L2ee4
	sahf
	rolw	%cl,(%edi)
	jmp	L1ebc
L2ee4:
	sahf
	roll	%cl,(%edi)
	jmp	L1ebc
L2eec:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L2f00
	sahf
	rorw	%cl,(%edi)
	jmp	L1ebc
L2f00:
	sahf
	rorl	%cl,(%edi)
	jmp	L1ebc
L2f08:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L2f1c
	sahf
	rclw	%cl,(%edi)
	jmp	L1ebc
L2f1c:
	sahf
	rcll	%cl,(%edi)
	jmp	L1ebc
L2f24:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L2f38
	sahf
	rcrw	%cl,(%edi)
	jmp	L1ebc
L2f38:
	sahf
	rcrl	%cl,(%edi)
	jmp	L1ebc
L2f40:
	cmpb	$4,%bl
	je	L2f46
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L2f46:
	shll	%cl,(%edi)
	jmp	L1ebc
L2f4d:
	cmpb	$4,%bl
	je	L2f53
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L2f53:
	shrl	%cl,(%edi)
	jmp	L1ebc
L2f5a:
	cmpb	$4,%bl
	je	L2f60
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L2f60:
	sarl	%cl,(%edi)
	jmp	L1ebc
L2f67:
	movzwl	(%esi),%eax
L2f6a:
	movl	Lregs+16,%edi
	leal	2(%edi,%eax),%eax
	movl	%eax,Lregs+16
	addl	Lsregs+8,%edi
	movzwl	(%edi),%esi
	addl	Lsregs+4,%esi
	jmp	L1ec4
L2f8d:
	xorl	%eax,%eax
	.byte	0xe9			/* jmp L2f6a, long form */
	.long	L2f6a-.-4
L2f94:
	movl	$Lsregs,%edx
L2f99:
	call	L393d
	call	L3970
	movzwl	(%edi,%ebx),%ecx
	shll	$4,%ecx
	addl	Lstate,%ecx
	movl	%ecx,(%edx)
	movl	(%edi),%ecx
	jmp	L270f
L2fb9:
	movl	$Lsregs+12,%edx
	.byte	0xe9			/* jmp L2f99, long form */
	.long	L2f99-.-4
L2fc3:
	call	L3958
	movb	(%esi),%al
	incl	%esi
	movb	%al,(%edi)
	jmp	L1ec4
L2fd2:
	call	L3970
	movl	(%esi),%ecx
	addl	%ebx,%esi
	movl	%edi,%eax
	jmp	L270f
L2fe2:
	movzwl	Lregs+20,%ecx
	movl	Lregs+16,%edi
	subl	$2,%edi
	movw	%di,Lregs+20
	addl	Lsregs+8,%edi
	movw	%cx,(%edi)
	movb	2(%esi),%dl
	andb	$0x1f,%dl
	je	L302d
	addl	Lsregs+8,%ecx
L3010:
	decb	%dl
	je	L3022
	subl	$2,%ecx
	movw	(%ecx),%ax
	subl	$2,%edi
	movw	%ax,(%edi)
	jmp	L3010
L3022:
	movl	Lregs+20,%eax
	subl	$2,%edi
	movw	%ax,(%edi)
L302d:
	subl	Lsregs+8,%edi
	movl	(%esi),%eax
	subw	%ax,%di
	movw	%di,Lregs+16
	addl	$3,%esi
	jmp	L1ec4
L3047:
	movl	Lregs+20,%eax
	movw	%ax,Lregs+16
	movl	Lregs+16,%edi
	addl	$2,%edi
	movl	%edi,Lregs+16
	addl	Lsregs+8,%edi
	movw	-2(%edi),%ax
	movw	%ax,Lregs+20
	jmp	L1ec4
L3076:
	movzwl	(%esi),%eax
L3079:
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
	jmp	L1ec4
L30ab:
	xorl	%eax,%eax
	.byte	0xe9			/* jmp L3079, long form */
	.long	L3079-.-4
L30b2:
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
	jmp	L27e4
L30eb:
	jmp	L1ee8
L30f0:
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
	jmp	L3079
L3132:
	movb	(%esi),%dl
	call	L3958
	andb	$0x38,%dl
	jmp	*Ltab_44cc(%edx)
L3142:
	movb	Leflags,%ah
	sahf
	rolb	(%edi)
	jmp	L1ebc
L3150:
	movb	Leflags,%ah
	sahf
	rorb	(%edi)
	jmp	L1ebc
L315e:
	movb	Leflags,%ah
	sahf
	rclb	(%edi)
	jmp	L1ebc
L316c:
	movb	Leflags,%ah
	sahf
	rcrb	$1,(%edi)
	jmp	L1ebc
L317a:
	shlb	(%edi)
	jmp	L1ebc
L3181:
	shrb	(%edi)
	jmp	L1ebc
L3188:
	sarb	(%edi)
	jmp	L1ebc
L318f:
	movb	(%esi),%dl
	call	L3970
	andb	$0x38,%dl
	jmp	*Ltab_44cc+4(%edx)
L319f:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L31b3
	sahf
	rolw	(%edi)
	jmp	L1ebc
L31b3:
	sahf
	roll	(%edi)
	jmp	L1ebc
L31bb:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L31cf
	sahf
	rorw	(%edi)
	jmp	L1ebc
L31cf:
	sahf
	rorl	(%edi)
	jmp	L1ebc
L31d7:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L31eb
	sahf
	rclw	(%edi)
	jmp	L1ebc
L31eb:
	sahf
	rcll	(%edi)
	jmp	L1ebc
L31f3:
	movb	Leflags,%ah
	cmpb	$4,%bl
	je	L3207
	sahf
	rcrw	$1,(%edi)
	jmp	L1ebc
L3207:
	sahf
	rcrl	$1,(%edi)
	jmp	L1ebc
L320f:
	cmpb	$4,%bl
	je	L3215
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L3215:
	shll	(%edi)
	jmp	L1ebc
L321c:
	cmpb	$4,%bl
	je	L3222
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L3222:
	shrl	(%edi)
	jmp	L1ebc
L3229:
	cmpb	$4,%bl
	je	L322f
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L322f:
	sarl	(%edi)
	jmp	L1ebc
L3236:
	movb	(%esi),%dl
	call	L3958
	movb	Lregs+4,%cl
	jmp	L2e67
L3248:
	movb	(%esi),%dl
	call	L3970
	movb	Lregs+4,%cl
	jmp	L2ec7
L325a:
	incl	%esi
	movl	Lregs,%eax
	aam
	movl	%eax,Lregs
	jmp	L1ebc
L326c:
	incl	%esi
	movl	Lregs,%eax
	aad
	movl	%eax,Lregs
	jmp	L1ebc
L327e:
	movb	Ldesc,%dl
	movl	Lsregs(%edx),%edi
	xorl	%eax,%eax
	.byte	0x8a,0x05		/* movb	Lregs,%al */
	.long	Lregs
	addl	%eax,%edi
	movw	Lregs+12,%ax
	addl	%eax,%edi
	call	L39b3
	movb	(%edi),%al
	.byte	0x88,0x05		/* movb	%al,Lregs */
	.long	Lregs
	jmp	L1ec4
L32ae:
	jmp	L1ee8
L32b3:
	incl	%esi
	decw	Lregs+4
	je	L1ec4
	testb	$0x40,Leflags
	jne	L1ec4
	decl	%esi
	jmp	L3399
L32d4:
	incl	%esi
	decw	Lregs+4
	je	L1ec4
	testb	$0x40,Leflags
	je	L1ec4
	decl	%esi
	jmp	L3399
L32f5:
	decw	Lregs+4
	jne	L3399
	incl	%esi
	jmp	L1ec4
L3308:
	cmpw	$0,Lregs+4
	je	L3399
	incl	%esi
	jmp	L1ec4
L331c:
	xorl	%edx,%edx
	movb	(%esi),%dl
	incl	%esi
	jmp	L33b7
L3326:
	xorl	%edx,%edx
	movb	(%esi),%dl
	incl	%esi
	jmp	L33ce
L3330:
	xorl	%edx,%edx
	movb	(%esi),%dl
	incl	%esi
	jmp	L33ef
L333a:
	xorl	%edx,%edx
	movb	(%esi),%dl
	incl	%esi
	jmp	L3463
L3344:
	movl	(%esi),%ecx
	addl	$2,%esi
	subl	Lsregs+4,%esi
	movl	%esi,%eax
	addw	%cx,%si
	addl	Lsregs+4,%esi
	jmp	L221c
L335f:
	movl	(%esi),%eax
	addl	$2,%esi
	subl	Lsregs+4,%esi
	addw	%ax,%si
	addl	Lsregs+4,%esi
	jmp	L1ec4
L3378:
	movl	%esi,%edi
	addl	$4,%esi
L337d:
	movzwl	2(%edi),%eax
	shll	$4,%eax
	addl	Lstate,%eax
	movl	%eax,Lsregs+4
	movzwl	(%edi),%esi
	addl	%eax,%esi
	jmp	L1ec4
L3399:
	movsbl	(%esi),%eax
	incl	%esi
	subl	Lsregs+4,%esi
	addw	%ax,%si
	addl	Lsregs+4,%esi
	jmp	L1ec4
L33b1:
	movl	Lregs+8,%edx
L33b7:
	call	L3e05
	inb	%dx,%al
	.byte	0x88,0x05		/* movb	%al,Lregs */
	.long	Lregs
	jmp	L1ec4
L33c8:
	movl	Lregs+8,%edx
L33ce:
	call	L3e05
	movl	Lregs,%eax
	cmpb	$4,%bl
	je	L33de
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L33de:
	inl	%dx,%eax
	movl	%eax,Lregs
	jmp	L1ec4
L33e9:
	movl	Lregs+8,%edx
L33ef:
	andl	$0xffff,%edx
	cmpl	Lsmmport,%edx
	.byte	0x0f,0x84		/* je L3411, long form as in the reference */
	.long	L3411-.-4
	call	L3e05
	movl	Lregs,%eax
	outb	%al,%dx
	jmp	L1ec4
L3411:
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
	jmp	L1ec4
L345d:
	movl	Lregs+8,%edx
L3463:
	call	L3e05
	movl	Lregs,%eax
	cmpb	$4,%bl
	je	L3473
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L3473:
	outl	%eax,%dx
	jmp	L1ec4
L3479:
	movb	$1,Ldesc+2
	jmp	L1edc
L3485:
	movb	$2,Ldesc+2
	jmp	L1edc
L3491:
	xorb	$1,Leflags
	jmp	L1ec4
L349d:
	movb	(%esi),%dl
	call	L3958
	andb	$0x38,%dl
	jmp	*Ltab_450c(%edx)
L34ad:
	movb	(%esi),%cl
	incl	%esi
	testb	%cl,(%edi)
	jmp	L1ebc
L34b7:
	notb	(%edi)
	jmp	L1ec4
L34be:
	negb	(%edi)
	jmp	L1ebc
L34c5:
	movl	Lregs,%eax
	mulb	(%edi)
	movl	%eax,Lregs
	jmp	L1ebc
L34d6:
	movl	Lregs,%eax
	imulb	(%edi)
	movl	%eax,Lregs
	jmp	L1ebc
L34e7:
	movl	Lregs,%eax
	divb	(%edi)
	movl	%eax,Lregs
	jmp	L1ebc
L34f8:
	movl	Lregs,%eax
	idivb	(%edi)
	movl	%eax,Lregs
	jmp	L1ebc
L3509:
	movb	(%esi),%dl
	call	L3970
	andb	$0x38,%dl
	jmp	*Ltab_450c+4(%edx)
L3519:
	movl	(%esi),%ecx
	addl	%ebx,%esi
	cmpb	$4,%bl
	je	L3523
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L3523:
	testl	%ecx,(%edi)
	jmp	L1ebc
L352a:
	cmpb	$4,%bl
	je	L3530
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L3530:
	notl	(%edi)
	jmp	L1ec4
L3537:
	cmpb	$4,%bl
	je	L353d
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L353d:
	negl	(%edi)
	jmp	L1ebc
L3544:
	movl	Lregs,%eax
	movl	Lregs+8,%edx
	cmpb	$4,%bl
	je	L3555
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L3555:
	mull	(%edi)
	movl	%eax,Lregs
	movl	%edx,Lregs+8
	jmp	L1ebc
L3567:
	movl	Lregs,%eax
	movl	Lregs+8,%edx
	cmpb	$4,%bl
	je	L3578
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L3578:
	imull	(%edi)
	movl	%eax,Lregs
	movl	%edx,Lregs+8
	jmp	L1ebc
L358a:
	movl	Lregs,%eax
	movl	Lregs+8,%edx
	cmpb	$4,%bl
	je	L359b
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L359b:
	divl	(%edi)
	movl	%eax,Lregs
	movl	%edx,Lregs+8
	jmp	L1ebc
L35ad:
	movl	Lregs,%eax
	movl	Lregs+8,%edx
	cmpb	$4,%bl
	je	L35be
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L35be:
	idivl	(%edi)
	movl	%eax,Lregs
	movl	%edx,Lregs+8
	jmp	L1ebc
L35d0:
	andb	$0xfe,Leflags
	jmp	L1ec4
L35dc:
	orb	$1,Leflags
	jmp	L1ec4
L35e8:
	andl	$0xfffffdff,Lhostfl
	jmp	L1ec4
L35f7:
	orl	$0x200,Lhostfl
	jmp	L1ec4
L3606:
	andl	$0xfffffbff,Lhostfl
	jmp	L1ec4
L3615:
	orl	$0x400,Lhostfl
	jmp	L1ec4
L3624:
	movb	(%esi),%dl
	call	L3958
	andb	$0x38,%dl
	jmp	*Ltab_454c(%edx)
L3634:
	movb	Leflags,%ah
	sahf
	incb	(%edi)
	jmp	L1ebc
L3642:
	movb	Leflags,%ah
	sahf
	decb	(%edi)
	jmp	L1ebc
L3650:
	movb	(%esi),%dl
	call	L3970
	andb	$0x38,%dl
	jmp	*Ltab_454c+4(%edx)
L3660:
	subl	Lsregs+4,%esi
	movl	%esi,%eax
	movw	(%edi),%si
	addl	Lsregs+4,%esi
	jmp	L221c
L3676:
	movzwl	(%edi),%esi
	addl	Lsregs+4,%esi
	jmp	L1ec4
L3684:
	movl	(%edi),%eax
	jmp	L221c
L368b:
	call	L3db4
	testb	%al,%al
	jne	L335f
	addl	$2,%esi
	jmp	L1ec4
L36a0:
	call	L3958
	call	L3db4
	movb	%al,(%edi)
	jmp	L1ec4
L36b1:
	movl	Lsregs+16,%eax
	jmp	L20a4
L36bb:
	movl	$Lsregs+16,%ecx
	jmp	L20b7
L36c5:
	call	L393d
	call	L3970
	movl	(%eax),%ecx
L36d1:
	cmpb	$4,%bl
	je	L36d7
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L36d7:
	btl	%ecx,(%edi)
	jmp	L1ebc
L36df:
	call	L393d
	call	L3970
	movb	(%esi),%cl
	incl	%esi
L36ec:
	andb	$0x1f,%cl
	je	L1ec4
	movl	(%eax),%eax
	cmpb	$4,%bl
	je	L36fd
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L36fd:
	shldl	%cl,%eax,(%edi)
	jmp	L1ebc
L3705:
	call	L393d
	call	L3970
	movb	Lregs+4,%cl
	.byte	0xe9			/* jmp L36ec, long form */
	.long	L36ec-.-4
L371a:
	movl	Lsregs+20,%eax
	jmp	L20a4
L3724:
	movl	$Lsregs+20,%ecx
	jmp	L20b7
L372e:
	call	L393d
	call	L3970
	movl	(%eax),%ecx
L373a:
	cmpb	$4,%bl
	je	L3740
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L3740:
	btsl	%ecx,(%edi)
	jmp	L1ebc
L3748:
	call	L393d
	call	L3970
	movb	(%esi),%cl
	incl	%esi
L3755:
	andb	$0x1f,%cl
	je	L1ec4
	movl	(%eax),%eax
	cmpb	$4,%bl
	je	L3766
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L3766:
	shrdl	%cl,%eax,(%edi)
	jmp	L1ebc
L376e:
	call	L393d
	call	L3970
	movb	Lregs+4,%cl
	.byte	0xe9			/* jmp L3755, long form */
	.long	L3755-.-4
L3783:
	call	L393d
	call	L3970
	movl	(%eax),%ecx
	jmp	L245e
L3794:
	call	L392f
	call	L3958
	movb	(%eax),%cl
	.byte	0x8a,0x05		/* movb	Lregs,%al */
	.long	Lregs
	.byte	0x0f,0xa6,0x0f	/* cmpxchg %cl,(%edi), i486 A-step encoding */
	.byte	0x88,0x05		/* movb	%al,Lregs */
	.long	Lregs
	jmp	L1ebc
L37b4:
	call	L393d
	call	L3970
	movl	(%eax),%ecx
	movl	Lregs,%eax
	cmpb	$4,%bl
	je	L37cb
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L37cb:
	.byte	0x0f,0xa7,0x0f	/* cmpxchg %ecx,(%edi), i486 A-step encoding */
	movl	%eax,Lregs
	jmp	L1ebc
L37d8:
	movl	$Lsregs+8,%edx
	jmp	L2f99
L37e2:
	call	L393d
	call	L3970
	movl	(%eax),%ecx
L37ee:
	cmpb	$4,%bl
	je	L37f4
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L37f4:
	btrl	%ecx,(%edi)
	jmp	L1ebc
L37fc:
	movl	$Lsregs+16,%edx
	jmp	L2f99
L3806:
	movl	$Lsregs+20,%edx
	jmp	L2f99
L3810:
	call	L393d
	call	L3958
	movzbl	(%edi),%ecx
	jmp	L270f
L3822:
	call	L393d
	call	L3970
	movzwl	(%edi),%ecx
	jmp	L270f
L3834:
	movb	(%esi),%dl
	call	L3970
	movb	(%esi),%cl
	incl	%esi
	andb	$0x38,%dl
	subb	$0x20,%dl
	jb	L1ee8
	shrl	$1,%edx
	jmp	*Ltab_46cc(%edx)
L3852:
	call	L393d
	call	L3970
	movl	(%eax),%ecx
L385e:
	cmpb	$4,%bl
	je	L3864
	.byte	0x66 /* operand-size prefix, skipped by the branch above */
L3864:
	btcl	%ecx,(%edi)
	jmp	L1ebc
L386c:
	call	L393d
	call	L3970
	cmpb	$4,%bl
	je	L3887
	bsfw	(%edi),%cx
	movw	%cx,(%eax)
	jmp	L1ebc
L3887:
	bsfl	(%edi),%ecx
	movl	%ecx,(%eax)
	jmp	L1ebc
L3891:
	call	L393d
	call	L3970
	cmpb	$4,%bl
	je	L38ac
	bsrw	(%edi),%cx
	movw	%cx,(%eax)
	jmp	L1ebc
L38ac:
	bsrl	(%edi),%ecx
	movl	%ecx,(%eax)
	jmp	L1ebc
L38b6:
	call	L393d
	call	L3958
	movsbl	(%edi),%ecx
	jmp	L270f
L38c8:
	call	L393d
	call	L3970
	movswl	(%edi),%ecx
	jmp	L270f
L38da:
	call	L392f
	call	L3958
	movb	(%eax),%cl
	xaddb	%cl,(%edi)
	movb	%cl,(%eax)
	jmp	L1ebc
L38f0:
	call	L393d
	call	L3970
	movl	(%eax),%ecx
	cmpb	$4,%bl
	je	L390d
	xaddw	%cx,(%edi)
	movw	%cx,(%eax)
	jmp	L1ebc
L390d:
	xaddl	%ecx,(%edi)
	movl	%ecx,(%eax)
	jmp	L1ebc
L3917:
	andb	$7,%dl
	movl	Lregs(,%edx,4),%eax
	bswapl	%eax
	movl	%eax,Lregs(,%edx,4)
	jmp	L1ec4

/*
 * internal helpers: the modrm decoders and the effective-address
 * computations.  They take their arguments in registers, and the two
 * refusals at L39d2 and L39e5 pop their own return address to
 * long-jump to the error exit, so no C calling convention applies
 */
L392f:
	movb	(%esi),%al
	andl	$0x38,%eax
	shrl	$1,%eax
	movl	Ltab_442c(%eax),%eax
	ret
L393d:
	movb	(%esi),%al
	andl	$0x38,%eax
	shrl	$1,%eax
	.byte	0x05			/* addl	$Lregs,%eax */
	.long	Lregs
	ret
L394a:
	movb	(%esi),%al
	andl	$0x38,%eax
	shrl	$1,%eax
	.byte	0x05			/* addl	$Lsregs,%eax */
	.long	Lsregs
	ret
	.align	2,0x00
L3958:
	movb	(%esi),%cl
	incl	%esi
	rolb	$4,%cl
	andl	$0x7c,%ecx
	orb	Ldesc+3,%cl
	jmp	*Ltab_422c(%ecx)
	.align	2,0x00
L3970:
	movb	(%esi),%cl
	incl	%esi
	rolb	$4,%cl
	andl	$0x7c,%ecx
	orb	Ldesc+3,%cl
	jmp	*Ltab_432c(%ecx)
	.align	2,0x00
L3988:
	movl	Lregs+12,%edi
	addl	Lregs+24,%edi
L3994:
	andl	$0xffff,%edi
L399a:
	movb	Ldesc,%cl
L39a0:
	cmpb	$0x18,%cl
	je	L39d1
	cmpl	$0x10000,%edi
	jae	L39e5
	addl	Lsregs(%ecx),%edi
L39b3:
	movl	%edi,%ecx
	subl	Lstate,%ecx
	cmpl	$0x100000,%ecx
	jae	L39d2
	shrl	$0xc,%ecx
	addl	Lpageperm,%ecx
	cmpb	$0,(%ecx)
	je	L39d2
L39d1:
	ret
L39d2:
	popl	%ecx
	movl	%edi,%eax
	subl	Lstate,%eax
	orl	$0x2000000,%eax
	jmp	L1ef4
L39e5:
	popl	%ecx
	movl	$0x4000000,%eax
	jmp	L1ef4
L39f0:
	movl	Lregs+12,%edi
	addl	Lregs+28,%edi
	.byte	0xe9			/* jmp L3994, long form */
	.long	L3994-.-4
	.align	2,0x00
L3a04:
	movl	Lregs+20,%edi
	addl	Lregs+24,%edi
	jmp	L3ae2
	.align	2,0x00
L3a18:
	movl	Lregs+20,%edi
	addl	Lregs+28,%edi
	jmp	L3ae2
	.align	2,0x00
L3a2c:
	movl	Lregs+24,%edi
	jmp	L3994
	.align	2,0x00
L3a38:
	movl	Lregs+28,%edi
	jmp	L3994
	.align	2,0x00
L3a44:
	movl	(%esi),%edi
	addl	$2,%esi
	jmp	L3994
	.align	2,0x00
L3a50:
	movl	Lregs+12,%edi
	jmp	L3994
L3a5b:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+12,%edi
	addl	Lregs+24,%edi
	jmp	L3994
L3a70:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+12,%edi
	addl	Lregs+28,%edi
	jmp	L3994
	.align	2,0x00
L3a88:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+20,%edi
	addl	Lregs+24,%edi
	.byte	0xe9			/* jmp L3ae2, long form */
	.long	L3ae2-.-4
	.align	2,0x00
L3aa0:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+20,%edi
	addl	Lregs+28,%edi
	.byte	0xe9			/* jmp L3ae2, long form */
	.long	L3ae2-.-4
	.align	2,0x00
L3ab8:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+24,%edi
	jmp	L3994
	.align	2,0x00
L3ac8:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+28,%edi
	jmp	L3994
	.align	2,0x00
L3ad8:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+20,%edi
L3ae2:
	andl	$0xffff,%edi
L3ae8:
	movb	Ldesc+1,%cl
	jmp	L39a0
	.align	2,0x00
L3af4:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+12,%edi
	jmp	L3994
L3b03:
	movl	(%esi),%edi
	addl	$2,%esi
	addl	Lregs+12,%edi
	addl	Lregs+24,%edi
	jmp	L3994
	.align	2,0x00
L3b1c:
	movl	(%esi),%edi
	addl	$2,%esi
	addl	Lregs+12,%edi
	addl	Lregs+28,%edi
	jmp	L3994
	.align	2,0x00
L3b34:
	movl	(%esi),%edi
	addl	$2,%esi
	addl	Lregs+20,%edi
	addl	Lregs+24,%edi
	.byte	0xe9			/* jmp L3ae2, long form */
	.long	L3ae2-.-4
	.align	2,0x00
L3b4c:
	movl	(%esi),%edi
	addl	$2,%esi
	addl	Lregs+20,%edi
	addl	Lregs+28,%edi
	.byte	0xe9			/* jmp L3ae2, long form */
	.long	L3ae2-.-4
	.align	2,0x00
L3b64:
	movl	(%esi),%edi
	addl	$2,%esi
	addl	Lregs+24,%edi
	jmp	L3994
L3b74:
	movl	(%esi),%edi
	addl	$2,%esi
	addl	Lregs+28,%edi
	jmp	L3994
L3b84:
	movl	(%esi),%edi
	addl	$2,%esi
	addl	Lregs+20,%edi
	jmp	L3ae2
L3b94:
	movl	(%esi),%edi
	addl	$2,%esi
	addl	Lregs+12,%edi
	jmp	L3994
L3ba4:
	movl	$Lregs,%edi
	ret
	.align	2,0x00
L3bac:
	movl	$Lregs+4,%edi
	ret
	.align	2,0x00
L3bb4:
	movl	$Lregs+8,%edi
	ret
	.align	2,0x00
L3bbc:
	movl	$Lregs+12,%edi
	ret
	.align	2,0x00
L3bc4:
	movl	$Lregs+16,%edi
	ret
	.align	2,0x00
L3bcc:
	movl	$Lregs+20,%edi
	ret
	.align	2,0x00
L3bd4:
	movl	$Lregs+24,%edi
	ret
	.align	2,0x00
L3bdc:
	movl	$Lregs+28,%edi
	ret
	.align	2,0x00
L3be4:
	movl	$Lregs+1,%edi
	ret
	.align	2,0x00
L3bec:
	movl	$Lregs+5,%edi
	ret
	.align	2,0x00
L3bf4:
	movl	$Lregs+9,%edi
	ret
	.align	2,0x00
L3bfc:
	movl	$Lregs+13,%edi
	ret
	.align	2,0x00
L3c04:
	movl	Lregs,%edi
	jmp	L399a
	.align	2,0x00
L3c10:
	movl	Lregs+4,%edi
	jmp	L399a
	.align	2,0x00
L3c1c:
	movl	Lregs+8,%edi
	jmp	L399a
	.align	2,0x00
L3c28:
	movl	Lregs+12,%edi
	jmp	L399a
	.align	2,0x00
L3c34:
	movl	(%esi),%edi
	addl	$4,%esi
	jmp	L399a
	.align	2,0x00
L3c40:
	movl	Lregs+24,%edi
	jmp	L399a
	.align	2,0x00
L3c4c:
	movl	Lregs+28,%edi
	jmp	L399a
	.align	2,0x00
L3c58:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs,%edi
	jmp	L399a
	.align	2,0x00
L3c68:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+4,%edi
	jmp	L399a
	.align	2,0x00
L3c78:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+8,%edi
	jmp	L399a
	.align	2,0x00
L3c88:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+12,%edi
	jmp	L399a
	.align	2,0x00
L3c98:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+20,%edi
	jmp	L3ae8
	.align	2,0x00
L3ca8:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+24,%edi
	jmp	L399a
	.align	2,0x00
L3cb8:
	movsbl	(%esi),%edi
	incl	%esi
	addl	Lregs+28,%edi
	jmp	L399a
	.align	2,0x00
L3cc8:
	movl	(%esi),%edi
	addl	$4,%esi
	addl	Lregs,%edi
	jmp	L399a
L3cd8:
	movl	(%esi),%edi
	addl	$4,%esi
	addl	Lregs+4,%edi
	jmp	L399a
L3ce8:
	movl	(%esi),%edi
	addl	$4,%esi
	addl	Lregs+8,%edi
	jmp	L399a
L3cf8:
	movl	(%esi),%edi
	addl	$4,%esi
	addl	Lregs+12,%edi
	jmp	L399a
L3d08:
	movl	(%esi),%edi
	addl	$4,%esi
	addl	Lregs+20,%edi
	jmp	L3ae8
L3d18:
	movl	(%esi),%edi
	addl	$4,%esi
	addl	Lregs+24,%edi
	jmp	L399a
L3d28:
	movl	(%esi),%edi
	addl	$4,%esi
	addl	Lregs+28,%edi
	jmp	L399a
L3d38:
	movb	(%esi),%cl
	incl	%esi
	xorb	$5,%cl
	testb	$7,%cl
	je	L3d4d
	xorb	$5,%cl
	xorl	%edi,%edi
	.byte	0xe9			/* jmp L3d74, long form */
	.long	L3d74-.-4
L3d4d:
	movl	(%esi),%edi
	addl	$4,%esi
	andb	$0xf8,%cl
	.byte	0xe9			/* jmp L3d80, long form */
	.long	L3d80-.-4
	.align	2,0x00
L3d5c:
	movb	(%esi),%cl
	movsbl	1(%esi),%edi
	addl	$2,%esi
	.byte	0xe9			/* jmp L3d74, long form */
	.long	L3d74-.-4
	.align	2,0x00
L3d6c:
	movb	(%esi),%cl
	movl	1(%esi),%edi
	addl	$5,%esi
L3d74:
	pushl	%ecx
	andb	$7,%cl
	addl	Lregs(,%ecx,4),%edi
	popl	%ecx
L3d80:
	pushl	%edi
	pushl	%ecx
	shrl	$1,%ecx
	andb	$0x1c,%cl
	xorl	%edi,%edi
	cmpb	$0x10,%cl
	je	L3d9c
	movl	Lregs(%ecx),%edi
	movl	(%esp),%ecx
	shrb	$6,%cl
	shll	%cl,%edi
L3d9c:
	popl	%ecx
	addl	(%esp),%edi
	addl	$4,%esp
	andb	$6,%cl
	cmpb	$4,%cl
	jne	L399a
	jmp	L3ae8

/*
 * the condition-code evaluator.  dl carries the tttn field, the guest
 * flags are loaded into the host, and one of sixteen setcc stubs runs
 */
L3db4:
	andb	$0xf,%dl
	movl	Leflags,%eax
	pushl	%eax
	popfl
	jmp	*Ltab_46dc(,%edx,4)
L3dc5:
	seto	%al
	ret
L3dc9:
	setno	%al
	ret
L3dcd:
	setb	%al
	ret
L3dd1:
	setae	%al
	ret
L3dd5:
	sete	%al
	ret
L3dd9:
	setne	%al
	ret
L3ddd:
	setbe	%al
	ret
L3de1:
	seta	%al
	ret
L3de5:
	sets	%al
	ret
L3de9:
	setns	%al
	ret
L3ded:
	setp	%al
	ret

/* Slot 11 of Ltab_46dc.  The condition order calls for setnp here;
   the reference has setno, the same encoding as slot 1, so guest
   JNP/JPO, SETNP/SETPO and LOOPNP evaluate as "not overflow".
   Transcribed as written. */
L3df1:
	setno	%al
	ret
L3df5:
	setl	%al
	ret
L3df9:
	setge	%al
	ret
L3dfd:
	setle	%al
	ret
L3e01:
	setg	%al
	ret

/*
 * the I/O permission check.  On denial it discards its own return
 * address and long-jumps to the exit path, so the caller never resumes
 */
L3e05:
	movzwl	%dx,%ecx
	shrl	$3,%ecx
	andb	$0xfc,%cl
	addl	Lioperm,%ecx
	movl	(%ecx),%ecx
	btl	%edx,%ecx
	jae	L3e1c
	ret
L3e1c:
	popl	%ecx
	movzwl	%dx,%eax
	orl	$0x3000000,%eax
	jmp	L1ef4

/*
 * Dispatch tables.  Everything from here to the end of __text is data.
 */
	.align	2,0x00

/* Ltab_3e2c -- primary dispatch, one entry per opcode byte */
Ltab_3e2c:
	.long	L1f68		/* 00 */
	.long	L1fc3		/* 01 */
	.long	L205e		/* 02 */
	.long	L2071		/* 03 */
	.long	L2084		/* 04 */
	.long	L2091		/* 05 */
	.long	L209f		/* 06 */
	.long	L20b2		/* 07 */
	.long	L1f68		/* 08 */
	.long	L1fc3		/* 09 */
	.long	L205e		/* 0a */
	.long	L2071		/* 0b */
	.long	L2084		/* 0c */
	.long	L2091		/* 0d */
	.long	L20e0		/* 0e */
	.long	L20ea		/* 0f */
	.long	L1f68		/* 10 */
	.long	L1fc3		/* 11 */
	.long	L205e		/* 12 */
	.long	L2071		/* 13 */
	.long	L2084		/* 14 */
	.long	L2091		/* 15 */
	.long	L2106		/* 16 */
	.long	L2110		/* 17 */
	.long	L1f68		/* 18 */
	.long	L1fc3		/* 19 */
	.long	L205e		/* 1a */
	.long	L2071		/* 1b */
	.long	L2084		/* 1c */
	.long	L2091		/* 1d */
	.long	L211a		/* 1e */
	.long	L2124		/* 1f */
	.long	L1f68		/* 20 */
	.long	L1fc3		/* 21 */
	.long	L205e		/* 22 */
	.long	L2071		/* 23 */
	.long	L2084		/* 24 */
	.long	L2091		/* 25 */
	.long	L212e		/* 26 */
	.long	L213c		/* 27 */
	.long	L1f68		/* 28 */
	.long	L1fc3		/* 29 */
	.long	L205e		/* 2a */
	.long	L2071		/* 2b */
	.long	L2084		/* 2c */
	.long	L2091		/* 2d */
	.long	L2155		/* 2e */
	.long	L2163		/* 2f */
	.long	L1f68		/* 30 */
	.long	L1fc3		/* 31 */
	.long	L205e		/* 32 */
	.long	L2071		/* 33 */
	.long	L2084		/* 34 */
	.long	L2091		/* 35 */
	.long	L217c		/* 36 */
	.long	L218a		/* 37 */
	.long	L1f68		/* 38 */
	.long	L1fc3		/* 39 */
	.long	L205e		/* 3a */
	.long	L2071		/* 3b */
	.long	L2084		/* 3c */
	.long	L2091		/* 3d */
	.long	L21a1		/* 3e */
	.long	L21af		/* 3f */
	.long	L21c6		/* 40 */
	.long	L21c6		/* 41 */
	.long	L21c6		/* 42 */
	.long	L21c6		/* 43 */
	.long	L21c6		/* 44 */
	.long	L21c6		/* 45 */
	.long	L21c6		/* 46 */
	.long	L21c6		/* 47 */
	.long	L21ec		/* 48 */
	.long	L21ec		/* 49 */
	.long	L21ec		/* 4a */
	.long	L21ec		/* 4b */
	.long	L21ec		/* 4c */
	.long	L21ec		/* 4d */
	.long	L21ec		/* 4e */
	.long	L21ec		/* 4f */
	.long	L2212		/* 50 */
	.long	L2212		/* 51 */
	.long	L2212		/* 52 */
	.long	L2212		/* 53 */
	.long	L2212		/* 54 */
	.long	L2212		/* 55 */
	.long	L2212		/* 56 */
	.long	L2212		/* 57 */
	.long	L225a		/* 58 */
	.long	L225a		/* 59 */
	.long	L225a		/* 5a */
	.long	L225a		/* 5b */
	.long	L225a		/* 5c */
	.long	L225a		/* 5d */
	.long	L225a		/* 5e */
	.long	L225a		/* 5f */
	.long	L22a9		/* 60 */
	.long	L235e		/* 61 */
	.long	L240e		/* 62 */
	.long	L2413		/* 63 */
	.long	L2418		/* 64 */
	.long	L2426		/* 65 */
	.long	L2434		/* 66 */
	.long	L243b		/* 67 */
	.long	L2447		/* 68 */
	.long	L2450		/* 69 */
	.long	L2479		/* 6a */
	.long	L2482		/* 6b */
	.long	L2495		/* 6c */
	.long	L24eb		/* 6d */
	.long	L2554		/* 6e */
	.long	L25b0		/* 6f */
	.long	L261f		/* 70 */
	.long	L261f		/* 71 */
	.long	L261f		/* 72 */
	.long	L261f		/* 73 */
	.long	L261f		/* 74 */
	.long	L261f		/* 75 */
	.long	L261f		/* 76 */
	.long	L261f		/* 77 */
	.long	L261f		/* 78 */
	.long	L261f		/* 79 */
	.long	L261f		/* 7a */
	.long	L261f		/* 7b */
	.long	L261f		/* 7c */
	.long	L261f		/* 7d */
	.long	L261f		/* 7e */
	.long	L261f		/* 7f */
	.long	L2632		/* 80 */
	.long	L2641		/* 81 */
	.long	L2632		/* 82 */
	.long	L2651		/* 83 */
	.long	L2661		/* 84 */
	.long	L2674		/* 85 */
	.long	L268d		/* 86 */
	.long	L26a2		/* 87 */
	.long	L26ca		/* 88 */
	.long	L26dd		/* 89 */
	.long	L26f0		/* 8a */
	.long	L2703		/* 8b */
	.long	L271c		/* 8c */
	.long	L2739		/* 8d */
	.long	L2753		/* 8e */
	.long	L2770		/* 8f */
	.long	L1ec4		/* 90 */
	.long	L277a		/* 91 */
	.long	L277a		/* 92 */
	.long	L277a		/* 93 */
	.long	L277a		/* 94 */
	.long	L277a		/* 95 */
	.long	L277a		/* 96 */
	.long	L277a		/* 97 */
	.long	L27ac		/* 98 */
	.long	L27c2		/* 99 */
	.long	L27df		/* 9a */
	.long	L1ec4		/* 9b */
	.long	L282c		/* 9c */
	.long	L2841		/* 9d */
	.long	L28a6		/* 9e */
	.long	L28b7		/* 9f */
	.long	L28c8		/* a0 */
	.long	L28ec		/* a1 */
	.long	L2915		/* a2 */
	.long	L2939		/* a3 */
	.long	L295d		/* a4 */
	.long	L29c8		/* a5 */
	.long	L2a46		/* a6 */
	.long	L2ac0		/* a7 */
	.long	L2b5b		/* a8 */
	.long	L2b69		/* a9 */
	.long	L2b7e		/* aa */
	.long	L2bce		/* ab */
	.long	L2c31		/* ac */
	.long	L2c88		/* ad */
	.long	L2cf7		/* ae */
	.long	L2d56		/* af */
	.long	L2dda		/* b0 */
	.long	L2de8		/* b1 */
	.long	L2df6		/* b2 */
	.long	L2e04		/* b3 */
	.long	L2e12		/* b4 */
	.long	L2e20		/* b5 */
	.long	L2e2e		/* b6 */
	.long	L2e3c		/* b7 */
	.long	L2e4a		/* b8 */
	.long	L2e4a		/* b9 */
	.long	L2e4a		/* ba */
	.long	L2e4a		/* bb */
	.long	L2e4a		/* bc */
	.long	L2e4a		/* bd */
	.long	L2e4a		/* be */
	.long	L2e4a		/* bf */
	.long	L2e5d		/* c0 */
	.long	L2ebd		/* c1 */
	.long	L2f67		/* c2 */
	.long	L2f8d		/* c3 */
	.long	L2f94		/* c4 */
	.long	L2fb9		/* c5 */
	.long	L2fc3		/* c6 */
	.long	L2fd2		/* c7 */
	.long	L2fe2		/* c8 */
	.long	L3047		/* c9 */
	.long	L3076		/* ca */
	.long	L30ab		/* cb */
	.long	L1ee8		/* cc */
	.long	L30b2		/* cd */
	.long	L30eb		/* ce */
	.long	L30f0		/* cf */
	.long	L3132		/* d0 */
	.long	L318f		/* d1 */
	.long	L3236		/* d2 */
	.long	L3248		/* d3 */
	.long	L325a		/* d4 */
	.long	L326c		/* d5 */
	.long	L1ee8		/* d6 */
	.long	L327e		/* d7 */
	.long	L32ae		/* d8 */
	.long	L32ae		/* d9 */
	.long	L32ae		/* da */
	.long	L32ae		/* db */
	.long	L32ae		/* dc */
	.long	L32ae		/* dd */
	.long	L32ae		/* de */
	.long	L32ae		/* df */
	.long	L32b3		/* e0 */
	.long	L32d4		/* e1 */
	.long	L32f5		/* e2 */
	.long	L3308		/* e3 */
	.long	L331c		/* e4 */
	.long	L3326		/* e5 */
	.long	L3330		/* e6 */
	.long	L333a		/* e7 */
	.long	L3344		/* e8 */
	.long	L335f		/* e9 */
	.long	L3378		/* ea */
	.long	L3399		/* eb */
	.long	L33b1		/* ec */
	.long	L33c8		/* ed */
	.long	L33e9		/* ee */
	.long	L345d		/* ef */
	.long	L1edc		/* f0 */
	.long	L1ee8		/* f1 */
	.long	L3479		/* f2 */
	.long	L3485		/* f3 */
	.long	L1ee8		/* f4 */
	.long	L3491		/* f5 */
	.long	L349d		/* f6 */
	.long	L3509		/* f7 */
	.long	L35d0		/* f8 */
	.long	L35dc		/* f9 */
	.long	L35e8		/* fa */
	.long	L35f7		/* fb */
	.long	L3606		/* fc */
	.long	L3615		/* fd */
	.long	L3624		/* fe */
	.long	L3650		/* ff */

/* Ltab_422c -- 16-bit effective address: (mod,rm) x 4, indexed by the rotated modrm */
Ltab_422c:
	.long	L3988		/* 00 */
	.long	L3a5b		/* 01 */
	.long	L3b03		/* 02 */
	.long	L3ba4		/* 03 */
	.long	L39f0		/* 04 */
	.long	L3a70		/* 05 */
	.long	L3b1c		/* 06 */
	.long	L3bac		/* 07 */
	.long	L3a04		/* 08 */
	.long	L3a88		/* 09 */
	.long	L3b34		/* 0a */
	.long	L3bb4		/* 0b */
	.long	L3a18		/* 0c */
	.long	L3aa0		/* 0d */
	.long	L3b4c		/* 0e */
	.long	L3bbc		/* 0f */
	.long	L3a2c		/* 10 */
	.long	L3ab8		/* 11 */
	.long	L3b64		/* 12 */
	.long	L3be4		/* 13 */
	.long	L3a38		/* 14 */
	.long	L3ac8		/* 15 */
	.long	L3b74		/* 16 */
	.long	L3bec		/* 17 */
	.long	L3a44		/* 18 */
	.long	L3ad8		/* 19 */
	.long	L3b84		/* 1a */
	.long	L3bf4		/* 1b */
	.long	L3a50		/* 1c */
	.long	L3af4		/* 1d */
	.long	L3b94		/* 1e */
	.long	L3bfc		/* 1f */
	.long	L3c04		/* 20 */
	.long	L3c58		/* 21 */
	.long	L3cc8		/* 22 */
	.long	L3ba4		/* 23 */
	.long	L3c10		/* 24 */
	.long	L3c68		/* 25 */
	.long	L3cd8		/* 26 */
	.long	L3bac		/* 27 */
	.long	L3c1c		/* 28 */
	.long	L3c78		/* 29 */
	.long	L3ce8		/* 2a */
	.long	L3bb4		/* 2b */
	.long	L3c28		/* 2c */
	.long	L3c88		/* 2d */
	.long	L3cf8		/* 2e */
	.long	L3bbc		/* 2f */
	.long	L3d38		/* 30 */
	.long	L3d5c		/* 31 */
	.long	L3d6c		/* 32 */
	.long	L3be4		/* 33 */
	.long	L3c34		/* 34 */
	.long	L3c98		/* 35 */
	.long	L3d08		/* 36 */
	.long	L3bec		/* 37 */
	.long	L3c40		/* 38 */
	.long	L3ca8		/* 39 */
	.long	L3d18		/* 3a */
	.long	L3bf4		/* 3b */
	.long	L3c4c		/* 3c */
	.long	L3cb8		/* 3d */
	.long	L3d28		/* 3e */
	.long	L3bfc		/* 3f */

/* Ltab_432c -- 32-bit effective address: the same index over the 0x67 forms */
Ltab_432c:
	.long	L3988		/* 00 */
	.long	L3a5b		/* 01 */
	.long	L3b03		/* 02 */
	.long	L3ba4		/* 03 */
	.long	L39f0		/* 04 */
	.long	L3a70		/* 05 */
	.long	L3b1c		/* 06 */
	.long	L3bac		/* 07 */
	.long	L3a04		/* 08 */
	.long	L3a88		/* 09 */
	.long	L3b34		/* 0a */
	.long	L3bb4		/* 0b */
	.long	L3a18		/* 0c */
	.long	L3aa0		/* 0d */
	.long	L3b4c		/* 0e */
	.long	L3bbc		/* 0f */
	.long	L3a2c		/* 10 */
	.long	L3ab8		/* 11 */
	.long	L3b64		/* 12 */
	.long	L3bc4		/* 13 */
	.long	L3a38		/* 14 */
	.long	L3ac8		/* 15 */
	.long	L3b74		/* 16 */
	.long	L3bcc		/* 17 */
	.long	L3a44		/* 18 */
	.long	L3ad8		/* 19 */
	.long	L3b84		/* 1a */
	.long	L3bd4		/* 1b */
	.long	L3a50		/* 1c */
	.long	L3af4		/* 1d */
	.long	L3b94		/* 1e */
	.long	L3bdc		/* 1f */
	.long	L3c04		/* 20 */
	.long	L3c58		/* 21 */
	.long	L3cc8		/* 22 */
	.long	L3ba4		/* 23 */
	.long	L3c10		/* 24 */
	.long	L3c68		/* 25 */
	.long	L3cd8		/* 26 */
	.long	L3bac		/* 27 */
	.long	L3c1c		/* 28 */
	.long	L3c78		/* 29 */
	.long	L3ce8		/* 2a */
	.long	L3bb4		/* 2b */
	.long	L3c28		/* 2c */
	.long	L3c88		/* 2d */
	.long	L3cf8		/* 2e */
	.long	L3bbc		/* 2f */
	.long	L3d38		/* 30 */
	.long	L3d5c		/* 31 */
	.long	L3d6c		/* 32 */
	.long	L3bc4		/* 33 */
	.long	L3c34		/* 34 */
	.long	L3c98		/* 35 */
	.long	L3d08		/* 36 */
	.long	L3bcc		/* 37 */
	.long	L3c40		/* 38 */
	.long	L3ca8		/* 39 */
	.long	L3d18		/* 3a */
	.long	L3bd4		/* 3b */
	.long	L3c4c		/* 3c */
	.long	L3cb8		/* 3d */
	.long	L3d28		/* 3e */
	.long	L3bdc		/* 3f */

/* Ltab_442c -- 8-bit register operands: al cl dl bl ah ch dh bh */
Ltab_442c:
	.long	Lregs		/* 00 */
	.long	Lregs+4		/* 01 */
	.long	Lregs+8		/* 02 */
	.long	Lregs+12		/* 03 */
	.long	Lregs+1		/* 04 */
	.long	Lregs+5		/* 05 */
	.long	Lregs+9		/* 06 */
	.long	Lregs+13		/* 07 */

/* Ltab_444c -- group table for the 0x80/0x81/0x83 and 0x0F 0xBA forms */
Ltab_444c:
	.long	L1f7d		/* 00 */
	.long	L1fd8		/* 01 */
	.long	L1f84		/* 02 */
	.long	L1fe5		/* 03 */
	.long	L1f8b		/* 04 */
	.long	L1ff2		/* 05 */
	.long	L1f99		/* 06 */
	.long	L200e		/* 07 */
	.long	L1fa7		/* 08 */
	.long	L202a		/* 09 */
	.long	L1fae		/* 0a */
	.long	L2037		/* 0b */
	.long	L1fb5		/* 0c */
	.long	L2044		/* 0d */
	.long	L1fbc		/* 0e */
	.long	L2051		/* 0f */

/* Ltab_448c -- group table */
Ltab_448c:
	.long	L2e70		/* 00 */
	.long	L2ed0		/* 01 */
	.long	L2e7e		/* 02 */
	.long	L2eec		/* 03 */
	.long	L2e8c		/* 04 */
	.long	L2f08		/* 05 */
	.long	L2e9a		/* 06 */
	.long	L2f24		/* 07 */
	.long	L2ea8		/* 08 */
	.long	L2f40		/* 09 */
	.long	L2eaf		/* 0a */
	.long	L2f4d		/* 0b */
	.long	L2ea8		/* 0c */
	.long	L2f40		/* 0d */
	.long	L2eb6		/* 0e */
	.long	L2f5a		/* 0f */

/* Ltab_44cc -- group table */
Ltab_44cc:
	.long	L3142		/* 00 */
	.long	L319f		/* 01 */
	.long	L3150		/* 02 */
	.long	L31bb		/* 03 */
	.long	L315e		/* 04 */
	.long	L31d7		/* 05 */
	.long	L316c		/* 06 */
	.long	L31f3		/* 07 */
	.long	L317a		/* 08 */
	.long	L320f		/* 09 */
	.long	L3181		/* 0a */
	.long	L321c		/* 0b */
	.long	L317a		/* 0c */
	.long	L320f		/* 0d */
	.long	L3188		/* 0e */
	.long	L3229		/* 0f */

/* Ltab_450c -- group table */
Ltab_450c:
	.long	L34ad		/* 00 */
	.long	L3519		/* 01 */
	.long	L34ad		/* 02 */
	.long	L3519		/* 03 */
	.long	L34b7		/* 04 */
	.long	L352a		/* 05 */
	.long	L34be		/* 06 */
	.long	L3537		/* 07 */
	.long	L34c5		/* 08 */
	.long	L3544		/* 09 */
	.long	L34d6		/* 0a */
	.long	L3567		/* 0b */
	.long	L34e7		/* 0c */
	.long	L358a		/* 0d */
	.long	L34f8		/* 0e */
	.long	L35ad		/* 0f */

/* Ltab_454c -- group table */
Ltab_454c:
	.long	L3634		/* 00 */
	.long	L21d0		/* 01 */
	.long	L3642		/* 02 */
	.long	L21f6		/* 03 */
	.long	L1ee8		/* 04 */
	.long	L3660		/* 05 */
	.long	L1ee8		/* 06 */
	.long	L27e4		/* 07 */
	.long	L1ee8		/* 08 */
	.long	L3676		/* 09 */
	.long	L1ee8		/* 0a */
	.long	L337d		/* 0b */
	.long	L1ee8		/* 0c */
	.long	L3684		/* 0d */
	.long	L1ee8		/* 0e */
	.long	L1ee8		/* 0f */

/* Ltab_458c -- modrm-indexed table reached as Ltab_458c-0x200(,%edx,4) */
Ltab_458c:
	.long	L368b		/* 00 */
	.long	L368b		/* 01 */
	.long	L368b		/* 02 */
	.long	L368b		/* 03 */
	.long	L368b		/* 04 */
	.long	L368b		/* 05 */
	.long	L368b		/* 06 */
	.long	L368b		/* 07 */
	.long	L368b		/* 08 */
	.long	L368b		/* 09 */
	.long	L368b		/* 0a */
	.long	L368b		/* 0b */
	.long	L368b		/* 0c */
	.long	L368b		/* 0d */
	.long	L368b		/* 0e */
	.long	L368b		/* 0f */
	.long	L36a0		/* 10 */
	.long	L36a0		/* 11 */
	.long	L36a0		/* 12 */
	.long	L36a0		/* 13 */
	.long	L36a0		/* 14 */
	.long	L36a0		/* 15 */
	.long	L36a0		/* 16 */
	.long	L36a0		/* 17 */
	.long	L36a0		/* 18 */
	.long	L36a0		/* 19 */
	.long	L36a0		/* 1a */
	.long	L36a0		/* 1b */
	.long	L36a0		/* 1c */
	.long	L36a0		/* 1d */
	.long	L36a0		/* 1e */
	.long	L36a0		/* 1f */
	.long	L36b1		/* 20 */
	.long	L36bb		/* 21 */
	.long	L1ee8		/* 22 */
	.long	L36c5		/* 23 */
	.long	L36df		/* 24 */
	.long	L3705		/* 25 */
	.long	L1ee8		/* 26 */
	.long	L1ee8		/* 27 */
	.long	L371a		/* 28 */
	.long	L3724		/* 29 */
	.long	L1ee8		/* 2a */
	.long	L372e		/* 2b */
	.long	L3748		/* 2c */
	.long	L376e		/* 2d */
	.long	L1ee8		/* 2e */
	.long	L3783		/* 2f */
	.long	L3794		/* 30 */
	.long	L37b4		/* 31 */
	.long	L37d8		/* 32 */
	.long	L37e2		/* 33 */
	.long	L37fc		/* 34 */
	.long	L3806		/* 35 */
	.long	L3810		/* 36 */
	.long	L3822		/* 37 */
	.long	L1ee8		/* 38 */
	.long	L1ee8		/* 39 */
	.long	L3834		/* 3a */
	.long	L3852		/* 3b */
	.long	L386c		/* 3c */
	.long	L3891		/* 3d */
	.long	L38b6		/* 3e */
	.long	L38c8		/* 3f */
	.long	L38da		/* 40 */
	.long	L38f0		/* 41 */
	.long	L1ee8		/* 42 */
	.long	L1ee8		/* 43 */
	.long	L1ee8		/* 44 */
	.long	L1ee8		/* 45 */
	.long	L1ee8		/* 46 */
	.long	L1ee8		/* 47 */
	.long	L3917		/* 48 */
	.long	L3917		/* 49 */
	.long	L3917		/* 4a */
	.long	L3917		/* 4b */
	.long	L3917		/* 4c */
	.long	L3917		/* 4d */
	.long	L3917		/* 4e */
	.long	L3917		/* 4f */

/* Ltab_46cc -- group table */
Ltab_46cc:
	.long	L36d1		/* 00 */
	.long	L373a		/* 01 */
	.long	L37ee		/* 02 */
	.long	L385e		/* 03 */

/* Ltab_46dc -- condition-code stubs, in tttn order */
Ltab_46dc:
	.long	L3dc5		/* 00 */
	.long	L3dc9		/* 01 */
	.long	L3dcd		/* 02 */
	.long	L3dd1		/* 03 */
	.long	L3dd5		/* 04 */
	.long	L3dd9		/* 05 */
	.long	L3ddd		/* 06 */
	.long	L3de1		/* 07 */
	.long	L3de5		/* 08 */
	.long	L3de9		/* 09 */
	.long	L3ded		/* 0a */
	.long	L3df1		/* 0b */
	.long	L3df5		/* 0c */
	.long	L3df9		/* 0d */
	.long	L3dfd		/* 0e */
	.long	L3e01		/* 0f */

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
