.text
.align 4

/* -----------------------------------------------------------------------
 * __bios32PnP
 * ----------------------------------------------------------------------- */
.globl __bios32PnP
__bios32PnP:
    pushl   %ebp
    movl    %esp, %ebp
    
    pusha
    push    %es
    push    %fs
    push    %gs
    pushf

    movl    8(%ebp), %edx

    /* 1. PREPARE STACK FOR INDIRECT CALL 
     * We push the target CS and Offset to the stack so we can 'lcall' it.
     */
    movzwl  0x20(%edx), %eax
    pushl   %eax              /* Push CS */
    pushl   0x2C(%edx)        /* Push Offset */
    
    /* Load Registers */
    movl    0x08(%edx), %ebx
    movl    0x0C(%edx), %ecx
    movl    0x14(%edx), %edi
    movl    0x18(%edx), %esi

    pushl   %edx    /* Save struct pointer */

    movl    0x04(%edx), %eax
    movl    0x10(%edx), %edx 

    /* Load DS */
    movl    4(%esp), %ebp
    movw    0x22(%ebp), %bp 
    
    push    %bp 
    pop     %ds     /* DS is now 16 (Kernel Data) */

    cli

    /* 2. EXECUTE FAR CALL
     * Manual encoding for "lcall *4(%esp)" 
     * This calls the pointer we constructed on the stack.
     */
    .byte   0xFF, 0x5C, 0x24, 0x04

    /* --- RETURN POINT --- */

    /* 3. RESTORE DS (LINKER SAFE)
     * We load the address of _kernDataSel into EBP first.
     */
    movl    $_kernDataSel, %ebp
    movw    (%ebp), %bp
    movw    %bp, %ds
    
    sti

    popl    %edx
    addl    $8, %esp

    /* Save Results */
    movl    %eax, 0x04(%edx)
    pushf
    popl    %eax
    movw    %ax, 0x28(%edx)
    movl    %ebx, 0x08(%edx)
    movl    %ecx, 0x0C(%edx)
    movl    %esi, 0x18(%edx)
    movl    %edi, 0x14(%edx)
    movw    %es, %ax
    movw    %ax, 0x24(%edx)

    popf
    pop     %gs
    pop     %fs
    pop     %es
    popa
    leave
    ret

/* -----------------------------------------------------------------------
 * __PnPEntry
 * ----------------------------------------------------------------------- */
.globl __PnPEntry
__PnPEntry:
    movl    %eax, save_eax_entry
    movl    %ecx, save_ecx
    movl    %edx, save_edx_entry

    /* 1. SAVE KERNEL STACK (LINKER SAFE) */
    movl    %esp, save_k_esp
    
    /* Load address of save_k_ss into EAX, then write SS */
    movl    $save_k_ss, %eax
    movw    %ss, %dx
    movw    %dx, (%eax)

    /* 2. SWITCH TO 16-BIT STACK (GDT 17 = 0x88) */
    movw    $0x88, %ax
    movw    %ax, %ss
    movl    $0xFFFE, %esp

    /* 3. PUSH ARGUMENTS (LINKER SAFE) */
    /* Load address of globals into registers first */
    movl    $_PnPEntry_argStackBase, %eax
    movl    (%eax), %ecx        /* ECX = argStackBase */
    
    movl    $_PnPEntry_numArgs, %eax
    movl    (%eax), %edx        /* EDX = numArgs */
    
    jmp     check_done

push_arg:
    /* Strict 16-bit push */
    movw    (%ecx,%edx,2), %ax
    pushw   %ax

check_done:
    decl    %edx
    jns     push_arg

args_done:
    /* 4. PREPARE 16-BIT RETURN STACK */
    
    /* A. Push Return Address (CS:IP of bios_rtn) */
    movw    %cs, %ax
    pushw   %ax             /* Return CS */
    
    movl    $bios_rtn, %eax
    subl    $__PnPEntry, %eax
    pushw   %ax             /* Return IP (16-bit) */

    /* B. Push Target Address (CS:IP of BIOS) (LINKER SAFE) */
    
    /* Load Target CS */
    movl    $__PnPEntry_biosCodeSelector, %edx
    movw    (%edx), %ax
    pushw   %ax             /* Push Target CS */
    
    /* Load Target IP */
    movl    $__PnPEntry_biosCodeOffset, %edx
    movl    (%edx), %eax
    pushw   %ax             /* Push Target IP (Truncated to 16-bit) */

    /* 5. RESTORE REGS */
    movl    save_eax_entry, %eax
    movl    save_ecx, %ecx
    movl    save_edx_entry, %edx

    /* 6. SWITCH SEGMENTS TO BIOS CONTEXT (0x90) */
    movw    $0x90, %bx
    movw    %bx, %ds
    movw    %bx, %es 

    /* 7. EXECUTE 16-BIT FAR RETURN (0x66 prefix) */
    /* This pops IP and CS from the stack and jumps */
    .byte   0x66, 0xCB

/* -----------------------------------------------------------------------
 * bios_rtn
 * ----------------------------------------------------------------------- */
.align 4
bios_rtn:
    /* We are back! */
    movl    %eax, save_eax_entry

    /* 1. RESTORE KERNEL SEGMENTS (LINKER SAFE) */
    movl    $_kernDataSel, %ebx
    movw    (%ebx), %bx
    movw    %bx, %ds
    movw    %bx, %es

    /* 2. RESTORE KERNEL STACK (LINKER SAFE) */
    movl    $save_k_ss, %edx
    movw    (%edx), %dx
    movw    %dx, %ss
    
    movl    save_k_esp, %esp

    movl    save_eax_entry, %eax
    lret

/* -----------------------------------------------------------------------
 * Data Section
 * ----------------------------------------------------------------------- */
.data
.align 4

save_eax_entry: .long 0
save_ecx:       .long 0
save_edx_entry: .long 0
save_k_esp:     .long 0
save_k_ss:      .word 0

.globl __PnPEntry_biosCodeOffset
__PnPEntry_biosCodeOffset:
    .long   0
.globl __PnPEntry_biosCodeSelector
__PnPEntry_biosCodeSelector:
    .word   0