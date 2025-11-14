/*
 * bios_asm.s
 * Assembly implementations of BIOS call functions
 *
 * NOTE: __bios32PnP uses self-modifying code and
 * MUST be linked into a Read-Write-Execute (RWX) segment.
 *
 * This version is for legacy gcc 2.7-era 'as'.
 */

/* Global variables for BIOS call state (declared in C or .bss) */
.globl _verbose
.globl _readPort
.globl _save_es
.globl _save_eax
.globl _save_ecx
.globl _save_edx
.globl _save_flag
.globl _new_eax
.globl _new_edx
.globl _PnPEntry_argStackBase
.globl _PnPEntry_numArgs
.globl _PnPEntry_biosCodeOffset
.globl _PnPEntry_biosCodeSelector
.globl _kernDataSel
.globl _PnPEntry_pmStackSel
.globl _PnPEntry_pmStackOff

.data
.align 2 /* 2^2 = 4-byte alignment */

_pnp_addr:
    .long 0x00000000 /* Far jump offset (4 bytes) */
_pnp_seg:
    .word 0x0000 /* Far jump segment (2 bytes) */

.globl _bios32_call_addr
.globl _bios32_call_seg
_bios32_call_addr:
    .long 0x00000000 /* Far call offset (4 bytes) */
_bios32_call_seg:
    .word 0x0000 /* Far call segment (2 bytes) */

.align 2 /* 2^2 = 4-byte alignment */

/* Storage for real return address */
_real_return_addr:
    .long 0x00000000 /* 32-bit return address */

/* Storage for saving kernel stack */
_save_ss:
    .word 0x0000
_save_esp:
    .long 0x00000000
/* Global variables for new 16-bit stack */
_PnPEntry_pmStackSel:
    .word 0x0000
_PnPEntry_pmStackOff:
    .long 0x00000000

.text

/*
 * __bios32PnP - Low-level PnP BIOS call entry point.
 *
 * This version has been modified to write its far-call target
 * to the .data segment (_bios32_call_seg/_bios32_call_addr)
 * instead of self-modifying its own code in the .text segment.
 */
.globl __bios32PnP
__bios32PnP:
    enter   $0, $0
    pushal
    push    %es
    push    %fs
    push    %gs
    pushfl
    movl    8(%ebp), %edx

    /* Get segment/offset from biosCallData struct and write to .data */
    movw    0x20(%edx), %ax         /* Get far call segment */
    movw    %ax, _bios32_call_seg   /* Store in writable .data variable */
    movl    0x2c(%edx), %eax        /* Get far call offset */
    movl    %eax, _bios32_call_addr /* Store in writable .data variable */

    movl    0x08(%edx), %ebx        /* Snapshot caller EBX (in/out) */
    movl    0x0c(%edx), %ecx        /* Snapshot caller ECX (in/out) */
    movl    0x14(%edx), %edi        /* Snapshot caller EDI (in/out) */
    movl    0x18(%edx), %esi        /* Snapshot caller ESI (in/out) */
    movl    %edx, _save_edx         /* Remember biosCallData pointer */
    movl    0x04(%edx), %eax        /* Stash input EAX for call */
    movl    %eax, _new_eax
    movl    0x10(%edx), %eax        /* Stash input EDX for call */
    movl    %eax, _new_edx
    movw    0x22(%edx), %ax         /* Incoming DS segment value */
    pushw   %ax
    movl    _new_eax, %eax          /* Restore caller-provided EAX/EDX */
    movl    _new_edx, %edx
    popw    %ds                     /* Switch to caller DS */
    cli                             /* BIOS expects interrupts disabled */

    /* Perform an indirect far call using the 6-byte pointer in .data */
    lcall   _bios32_call_addr

    .align 2

    pushfl                          /* Preserve EFLAGS returned by BIOS */
    pushw   %ax                     /* Save AX so we can borrow it */
    movw    _kernDataSel, %ax       /* Switch DS back to kernel data selector */
    movw    %ax, %ds
    popw    %ax                     /* Restore AX from before DS switch */
    movl    %eax, _save_eax         /* Capture EAX as returned by BIOS */
    popl    %eax                    /* Restore original EAX pushed by PUSHAD */
    movw    %ax, _save_flag         /* Save the EFLAGS value popped earlier */
    movw    %es, %ax                /* Save ES (set by BIOS to data segment) */
    movw    %ax, _save_es
    movl    %edx, _new_edx          /* Preserve updated EDX */
    movl    _save_edx, %edx         /* Reload biosCallData pointer */
    movl    _new_edx, %eax          /* Write updated registers back to struct */
    movl    %eax, 0x10(%edx)        /* Store EDX result */
    movl    _save_eax, %eax
    movl    %eax, 0x04(%edx)        /* Store EAX result */
    movw    _save_es, %ax
    movw    %ax, 0x24(%edx)         /* Store ES result */
    movw    _save_flag, %ax
    movw    %ax, 0x28(%edx)         /* Store FLAGS result */
    movl    %ebx, 0x08(%edx)        /* Store general-purpose register outputs */
    movl    %ecx, 0x0c(%edx)
    movl    %edi, 0x14(%edx)
    movl    %esi, 0x18(%edx)
    movl    %ebp, 0x1c(%edx)
    popfl                           /* Restore original EFLAGS */
    pop     %gs                     /* Restore segment registers */
    pop     %fs
    pop     %es
    popal                           /* Restore general-purpose registers */

    leave
    ret

/*
 * _PnPEntry - Low-level trampoline into the 16-bit PnP BIOS entry point
 *
 * This routine expects its three arguments in EAX, EDX, and ECX (regparm(3)).
 * It preserves those registers, pushes the argument stack prepared by
 * PnPArgStack, and then performs a far jump into the BIOS.
 *
 * On return from the 16-bit BIOS (via RETF), control resumes at bios_rtn,
 * the argument stack is unwound, and a far return is performed to the caller.
 */
.globl _PnPEntry
.globl __PnPEntry
_PnPEntry:
__PnPEntry:
    movl    %eax, _save_eax        /* Preserve regparm arguments */
    movl    %ecx, _save_ecx
    movl    %edx, _save_edx

    /*
     * Save 32-bit kernel stack
     */
    movw    %ss, _save_ss
    movl    %esp, _save_esp
    
    /* Load 16-bit PnP stack */
    movw    _PnPEntry_pmStackSel, %ax
    movw    %ax, %ss
    movl    _PnPEntry_pmStackOff, %esp    

    movl    _PnPEntry_biosCodeOffset, %eax
    movl    %eax, _pnp_addr        /* Patch writable far pointer offset */
    movw    _PnPEntry_biosCodeSelector, %ax
    movw    %ax, _pnp_seg          /* Patch writable far pointer segment */

    movl    _PnPEntry_argStackBase, %ecx
    movl    _PnPEntry_numArgs, %edx
    jmp     check_args             /* Arguments pushed in reverse order */

push_arg:
    movw    (%ecx,%edx,2), %ax
    pushw   %ax                    /* Push one 16-bit argument */

check_args:
    decl    %edx
    jns     push_arg               /* Loop until all args consumed */

    movw    %cs, %ax
    pushw   %ax                    /* Push return segment */

    movl    $bios_rtn, %eax
    subl    $_PnPEntry, %eax
    pushw   %ax                    /* Push return offset within this segment */

    movl    _save_eax, %eax        /* Restore caller argument registers */
    movl    _save_ecx, %ecx
    movl    _save_edx, %edx

bios_rtn:
    movl    %eax, _save_eax        /* Capture AX result for caller */
    movl    _PnPEntry_numArgs, %eax
    addl    %eax, %eax             /* Multiply %eax by 2 by adding it to itself */
    addl    %eax, %esp             /* Pop (numArgs * 2) bytes */

    /*
     * Restore 32-bit kernel stack
     */
    movl    _save_esp, %esp
    movw    _save_ss, %ax
    movw    %ax, %ss

    movl    _save_eax, %eax        /* Restore EAX with BIOS return value */
    lret                           /* Far return to original caller */
