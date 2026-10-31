.text
.align 2, 0x90

.globl __bios16
__bios16:
    movl %eax, __ati_bios16_saved_eax
    movw $0, %ax
    movw %ax, %fs
    movw %ax, %gs
    movl _ATI_Bios_Offset, %eax
    movl %eax, bios16_far_offset
    movw _ATI_Bios_Selector, %ax
    movw %ax, bios16_far_selector
    movl %esp, %eax
    movl %eax, __ati_bios16_saved_esp
    movw %ss, %ax
    movw %ax, __ati_bios16_saved_ss
    movw _ATI_Bios_StackOffset, %ax
    movw %ax, %sp
    movw _ATI_Bios_StackSelector, %ax
    movw %ax, %ss
    movw %cs, %ax
    pushw %ax
    movl $1f, %eax
    subl $__bios16, %eax
    pushw %ax
    movl __ati_bios16_saved_eax, %eax
    .byte 0xea
bios16_far_offset:
    .long 0
bios16_far_selector:
    .word 0

1:
    movl __ati_bios16_saved_esp, %eax
    movl %eax, %esp
    movw __ati_bios16_saved_ss, %ax
    movw %ax, %ss
    lret

.data
.align 2
.globl __ati_bios16_saved_eax
__ati_bios16_saved_eax:
    .long 0
.globl __ati_bios16_saved_esp
__ati_bios16_saved_esp:
    .long 0
.globl __ati_bios16_saved_ss
__ati_bios16_saved_ss:
    .word 0
.text
