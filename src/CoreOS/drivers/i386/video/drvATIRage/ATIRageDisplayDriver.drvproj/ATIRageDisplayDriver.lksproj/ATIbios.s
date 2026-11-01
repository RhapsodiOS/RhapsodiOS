.text
.align 2, 0x90

.globl __ATIbios32
__ATIbios32:
    enter $0, $0
    pushal
    pushl %es
    pushl %fs
    pushl %gs
    pushfl

    movl 8(%ebp), %edx
    movw 0x20(%edx), %ax
    movw %ax, bios32_far_selector
    movl 0x2c(%edx), %eax
    movl %eax, bios32_far_offset

    movl 0x08(%edx), %ebx
    movl 0x0c(%edx), %ecx
    movl 0x14(%edx), %edi
    movl 0x18(%edx), %esi
    movl 0x1c(%edx), %ebp
    movl %edx, __ati_bios32_registers
    movl 0x04(%edx), %eax
    movl %eax, __ati_bios32_saved_eax
    movl 0x10(%edx), %eax
    movl %eax, __ati_bios32_saved_edx

    movw 0x22(%edx), %ax
    pushw %ax
    movl __ati_bios32_saved_eax, %eax
    movl __ati_bios32_saved_edx, %edx
    .byte 0x66, 0x1f
    cli
    .byte 0x9a
bios32_far_offset:
    .long 0
bios32_far_selector:
    .word 0

    pushfl
    pushw %ax
    movw _kernDataSel, %ax
    movw %ax, %ds
    popw %ax
    movl %eax, __ati_bios32_result_eax
    popl %eax
    movw %ax, __ati_bios32_result_flags
    movw %es, %ax
    movw %ax, __ati_bios32_result_es
    movl %edx, __ati_bios32_saved_edx

    movl __ati_bios32_registers, %edx
    movl __ati_bios32_saved_edx, %eax
    movl %eax, 0x10(%edx)
    movl __ati_bios32_result_eax, %eax
    movl %eax, 0x04(%edx)
    movw __ati_bios32_result_es, %ax
    movw %ax, 0x24(%edx)
    movw __ati_bios32_result_flags, %ax
    movw %ax, 0x28(%edx)
    movl %ebx, 0x08(%edx)
    movl %ecx, 0x0c(%edx)
    movl %edi, 0x14(%edx)
    movl %esi, 0x18(%edx)
    movl %ebp, 0x1c(%edx)

    popfl
    popl %gs
    popl %fs
    popl %es
    popal
    leave
    ret

.data
.align 2
.globl __ati_bios32_registers
__ati_bios32_registers:
    .long 0
.globl __ati_bios32_saved_eax
__ati_bios32_saved_eax:
    .long 0
.globl __ati_bios32_saved_edx
__ati_bios32_saved_edx:
    .long 0
.globl __ati_bios32_result_eax
__ati_bios32_result_eax:
    .long 0
.globl __ati_bios32_result_flags
__ati_bios32_result_flags:
    .word 0
.globl __ati_bios32_result_es
__ati_bios32_result_es:
    .word 0
.text
