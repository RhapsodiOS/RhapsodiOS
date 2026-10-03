	.code32
	.text
	.globl __bios16
__bios16:
	movl	%eax, bios16_saved_eax
	movw	$0, %ax
	movw	%ax, %fs
	movw	%ax, %gs
	movl	_ATI_Bios_Offset, %eax
	movl	%eax, bios16_far_jump+1
	movw	_ATI_Bios_Selector, %ax
	movw	%ax, bios16_far_jump+5
	movl	%esp, bios16_saved_esp
	movw	%ss, %ax
	movw	%ax, bios16_saved_ss
	movw	_ATI_Bios_StackOffset, %ax
	movw	%ax, %sp
	movw	_ATI_Bios_StackSelector, %ax
	movw	%ax, %ss
	movw	%cs, %ax
	pushw	%ax
	movl	$bios16_return, %eax
	subl	$__bios16, %eax
	pushw	%ax
	movl	bios16_saved_eax, %eax
bios16_far_jump:
	.byte	0xea
	.long	0
	.word	0
bios16_return:
	movw	%ax, %ss
	lret
	.globl bios16_end
bios16_end:

	.globl __ATIbios32
__ATIbios32:
	enter	$0, $0
	pushal
	push	%es
	push	%fs
	push	%gs
	pushfl
	movl	8(%ebp), %edx
	movw	0x20(%edx), %ax
	movw	%ax, bios32_far_call+5
	movl	0x2c(%edx), %eax
	movl	%eax, bios32_far_call+1
	movl	0x08(%edx), %ebx
	movl	0x0c(%edx), %ecx
	movl	0x14(%edx), %edi
	movl	0x18(%edx), %esi
	movl	0x1c(%edx), %ebp
	movl	%edx, bios32_saved_buffer
	movl	0x04(%edx), %eax
	movl	%eax, bios32_saved_eax
	movl	0x10(%edx), %eax
	movl	%eax, bios32_saved_edx
	movw	0x22(%edx), %ax
	.byte	0x66, 0x50
	movl	bios32_saved_eax, %eax
	movl	bios32_saved_edx, %edx
	.byte	0x66, 0x1f
	cli
bios32_far_call:
	.byte	0x9a
	.long	0
	.word	0
	pushfl
	.byte	0x66, 0x50
	movw	_kernDataSel, %ax
	movw	%ax, %ds
	.byte	0x66, 0x58
	movl	%eax, bios32_result_eax
	popl	%eax
	movw	%ax, bios32_result_flags
	movw	%es, %ax
	movw	%ax, bios32_result_es
	movl	%edx, bios32_saved_edx
	movl	bios32_saved_buffer, %edx
	movl	bios32_saved_edx, %eax
	movl	%eax, 0x10(%edx)
	movl	bios32_result_eax, %eax
	movl	%eax, 0x04(%edx)
	movw	bios32_result_es, %ax
	movw	%ax, 0x24(%edx)
	movw	bios32_result_flags, %ax
	movw	%ax, 0x28(%edx)
	movl	%ebx, 0x08(%edx)
	movl	%ecx, 0x0c(%edx)
	movl	%edi, 0x14(%edx)
	movl	%esi, 0x18(%edx)
	movl	%ebp, 0x1c(%edx)
	popfl
	pop	%gs
	pop	%fs
	pop	%es
	popal
	leave
	ret
	.globl bios32_end
bios32_end:

	.data
	.align	4
bios16_saved_eax:
	.long	0
bios16_saved_esp:
	.long	0
bios16_saved_ss:
	.word	0
	.align	4
bios32_result_es:
	.word	0
bios32_result_eax:
	.long	0
bios32_saved_buffer:
	.long	0
bios32_result_flags:
	.word	0
	.align	4
bios32_saved_eax:
	.long	0
bios32_saved_edx:
	.long	0
