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

/*
 * Writable far pointer structures for ___PnPEntry
 * This function uses the "indirect" method, so its
 * pointers belong in a writable .data section.
 */
.data
.align 2  /* 2^2 = 4-byte alignment */

_pnp_addr:
    .long   0x00000000          /* Far jump offset (4 bytes) */
_pnp_seg:
    .word   0x0000              /* Far jump segment (2 bytes) */

.align 2  /* 2^2 = 4-byte alignment */

/* Storage for real return address (beyond what BIOS can reach with 16-bit offset) */
_real_return_addr:
    .long   0x00000000          /* 32-bit return address */

.globl _pnp_addr
.globl _pnp_seg
.globl _real_return_addr


.text
/*
 * .code 32 directive removed. The -m32 flag to gcc
 * should be sufficient to put 'as' in 32-bit mode.
 */

/*
 * _bios32PnP - Low-level PnP BIOS call entry point
 *
 * C prototype: void _bios32PnP(void *biosCallData);
 * Parameter: biosCallData pointer at 8(%ebp)
 */
.globl __bios32PnP
__bios32PnP:
    enter   $0, $0              /* 0x6F24: ENTER 0x0,0x0 */

    /* Save all registers */
    pushal                      /* 0x6F28: PUSHAD */
    push    %es                 /* 0x6F29: PUSH ES */
    push    %fs                 /* 0x6F2A: PUSH FS */
    push    %gs                 /* 0x6F2C: PUSH GS */
    pushfl                      /* 0x6F2E: PUSHFD */

    /* Get biosCallData pointer from parameter */
    movl    8(%ebp), %edx       /* 0x6F2F: MOV EDX,dword ptr [EBP + param_1] */

    /* Extract far call segment and offset */
    /* Write to writable data section (not instruction bytes) */
    movw    0x20(%edx), %ax     /* 0x6F32: MOV AX,word ptr [EDX + 0x20] - load far_seg */
    movw    %ax, _save_seg      /* 0x6F36: MOV [save_seg],AX - store segment */
    movl    0x2c(%edx), %eax    /* 0x6F3C: MOV EAX,dword ptr [EDX + 0x2c] - load far_offset */
    movl    %eax, _save_addr    /* 0x6F3F: MOV [save_addr],EAX - store offset */

    /* Load input registers from biosCallData structure */
    movl    0x08(%edx), %ebx    /* 0x6F44: MOV EBX,dword ptr [EDX + 0x8] */
    movl    0x0c(%edx), %ecx    /* 0x6F47: MOV ECX,dword ptr [EDX + 0xc] */
    movl    0x14(%edx), %edi    /* 0x6F4A: MOV EDI,dword ptr [EDX + 0x14] */
    movl    0x18(%edx), %esi    /* 0x6F4D: MOV ESI,dword ptr [EDX + 0x18] */

    /* Save biosCallData pointer for later */
    movl    %edx, _save_edx     /* 0x6F50: MOV dword ptr [save_edx],EDX */

    /* Save EAX and EDX inputs to temporaries */
    movl    0x04(%edx), %eax    /* 0x6F56: MOV EAX,dword ptr [EDX + 0x4] */
    movl    %eax, _new_eax      /* 0x6F59: MOV [new_eax],EAX */
    movl    0x10(%edx), %eax    /* 0x6F5E: MOV EAX,dword ptr [EDX + 0x10] */
    movl    %eax, _new_edx      /* 0x6F61: MOV [new_edx],EAX */

    /* Load DS segment and prepare for switch */
    movw    0x22(%edx), %ax     /* 0x6F66: MOV AX,word ptr [EDX + 0x22] */
    pushw   %ax                 /* 0x6F6A: PUSH AX */

    /* Restore EAX and EDX from temporaries */
    movl    _new_eax, %eax      /* 0x6F6C: MOV EAX,[new_eax] */
    movl    _new_edx, %edx      /* 0x6F71: MOV EDX,dword ptr [new_edx] */

    /* Switch DS segment and disable interrupts */
    popw    %ds                 /* 0x6F77: POP DS */
    cli                         /* 0x6F79: CLI */

    /* Force 1-byte alignment, critical for self-modifying code */
    /* .align 0 means 2^0 = 1-byte alignment */
    .align 0

    /* Make these labels global so the 'mov' instructions can find them */
    .globl _save_addr
    .globl _save_seg

    .byte 0x9A              /* 0x6F7A: CALLF direct */
_save_addr:
    .long 0x00000000        /* 0x6F7B: 32-bit offset (patched) */
_save_seg:
    .word 0x0000            /* 0x6F7F: 16-bit segment (patched) */

    /* Resume default alignment for subsequent code */
    /* .align 2 means 2^2 = 4-byte alignment */
    .align 2

    /* 0x6F81: BIOS returns here
     * Save EFLAGS from BIOS call
     */
    pushfl                      /* 0x6F81: PUSHFD */

    /* Temporarily save AX and restore kernel DS */
    pushw   %ax                 /* 0x6F82: PUSH AX */
    movw    _kernDataSel, %ax   /* 0x6F84: MOV AX,[_kernDataSel] */
    movw    %ax, %ds            /* 0x6F8A: MOV DS,AX */
    popw    %ax                 /* 0x6F8D: POP AX */

    /* Save output registers to temporaries */
    movl    %eax, _save_eax     /* 0x6F8F: MOV [save_eax],EAX */
    popl    %eax                /* 0x6F94: POP EAX */
    movw    %ax, _save_flag     /* 0x6F95: MOV [save_flag],AX */
    movw    %es, %ax            /* 0x6F9B: MOV AX,ES */
    movw    %ax, _save_es       /* 0x6F9E: MOV [save_es],AX */
    movl    %edx, _new_edx      /* 0x6FA4: MOV dword ptr [new_edx],EDX */

    /* Get biosCallData pointer back */
    movl    _save_edx, %edx     /* 0x6FAA: MOV EDX,dword ptr [save_edx] */

    /* Store all output registers back to biosCallData */
    movl    _new_edx, %eax      /* 0x6FB0: MOV EAX,[new_edx] */
    movl    %eax, 0x10(%edx)    /* 0x6FB5: MOV dword ptr [EDX + 0x10],EAX */
    movl    _save_eax, %eax     /* 0x6FB8: MOV EAX,[save_eax] */
    movl    %eax, 0x04(%edx)    /* 0x6FBD: MOV dword ptr [EDX + 0x4],EAX */
    movw    _save_es, %ax       /* 0x6FC0: MOV AX,[save_es] */
    movw    %ax, 0x24(%edx)     /* 0x6FC6: MOV word ptr [EDX + 0x24],AX */
    movw    _save_flag, %ax     /* 0x6FCA: MOV AX,[save_flag] */
    movw    %ax, 0x28(%edx)     /* 0x6FD0: MOV word ptr [EDX + 0x28],AX */
    movl    %ebx, 0x08(%edx)    /* 0x6FD4: MOV dword ptr [EDX + 0x8],EBX */
    movl    %ecx, 0x0c(%edx)    /* 0x6FD7: MOV dword ptr [EDX + 0xc],ECX */
    movl    %edi, 0x14(%edx)    /* 0x6FDA: MOV dword ptr [EDX + 0x14],EDI */
    movl    %esi, 0x18(%edx)    /* 0x6FDD: MOV dword ptr [EDX + 0x18],ESI */
    movl    %ebp, 0x1c(%edx)    /* 0x6FE0: MOV dword ptr [EDX + 0x1c],EBP */

    /* Restore saved registers */
    popfl                       /* 0x6FE3: POPFD */
    pop     %gs                 /* 0x6FE4: POP GS */
    pop     %fs                 /* 0x6FE6: POP FS */
    pop     %es                 /* 0x6FE8: POP ES */
    popal                       /* 0x6FE9: POPAD */

    /* Restore stack frame and return */
    leave                       /* 0x6FEA: LEAVE */
