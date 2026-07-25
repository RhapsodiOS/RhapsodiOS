/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

/*
 * bios.c
 * BIOS Call Utilities Implementation
 */

#include "bios.h"
#include <driverkit/generalFuncs.h>

/* Global PnP read port - set during initialization */
extern unsigned short pnpReadPort;

/*
 * Global variables for BIOS operations
 */
char verbose = 0;                      /* Verbose logging flag */
unsigned short readPort = 0;           /* PnP read port */

/*
 * Globals shared with the assembler thunk below, with PnPArgStack (which
 * publishes the marshalled argument words through the first two) and with
 * -[PnPBios setupSegments] (which programs the last three).
 */
unsigned short *PnPEntry_argStackBase = 0;
unsigned int    PnPEntry_numArgs = 0;
unsigned int    PnPEntry_biosCodeOffset = 0;
unsigned short  PnPEntry_biosCodeSelector = 0;
unsigned short  kernDataSel = 0;

/*
 * =====================================================================
 * The PnP BIOS real-mode/PM16 calling apparatus
 * =====================================================================
 *
 * Three routines, reconstructed instruction-for-instruction from the
 * reference disassembly (see reconstruction/divergences.md, "Central
 * finding: the PnP BIOS real-mode/PM16 calling apparatus").  Expressed as
 * a single file-scope __asm__ block rather than a separate .s file because
 * this project's pb_makefiles Makefile has no SFILES/OTHERLINKEDOFILES
 * wiring and no .s file exists anywhere under src/drivers-i386 to copy;
 * a file-scope __asm__ block is the mechanism already proven to build in
 * this project.
 *
 * Control flow for one BIOS call:
 *
 *   call_bios(bb)                     C, below
 *     -> _bios32PnP(bb)               PUSHAD/PUSHFD, CLI, patch the far
 *                                     call target out of bb, load DS,
 *                                     far-call into _PnPEntry
 *          -> _PnPEntry               replay PnPEntry_numArgs 16-bit words
 *                                     from PnPEntry_argStackBase onto the
 *                                     stack, push a 16-bit CS:offset return
 *                                     address, far-jump into the PM16 BIOS
 *               -> PM16 BIOS ROM      runs, returns AX, 16-bit far return
 *          <- bios_rtn                pop exactly 2*PnPEntry_numArgs bytes,
 *                                     32-bit far return to _bios32PnP
 *     <- _bios32PnP                   restore DS, write the register block
 *                                     back into bb, POPFD (which re-enables
 *                                     interrupts), POPAD
 *
 * INTERRUPTS: the CLI in _bios32PnP and the matching POPFD after the call
 * bracket the entire mode transition.  This is the reference's own
 * mechanism and it replaces the splhigh()/splx() pair that commit 516034d5
 * added to the now-deleted call_pnp_bios purely to stand in for this CLI
 * (commit 516344d5)
 * (reconstruction/divergences.md Finding 3).  Do not add a second bracket.
 *
 * SELF-MODIFYING CODE: both far transfers have their target operands
 * patched in place at run time; the operand slots are the labels save_addr/
 * save_seg (inside the far call in _bios32PnP) and targ_addr/targ_sel
 * (inside the far jump in _PnPEntry).  Both live in __text, exactly as in
 * the reference.  This requires the driver's text to be mapped writable.
 *
 * STACK: no stack switch is performed.  _PnPEntry and the BIOS run on the
 * caller's ordinary 32-bit kernel stack; the 16-bit BIOS addresses it
 * through ESP because SS keeps D/B=1.  This is why the reference needs
 * neither a dedicated 16-bit stack buffer nor a GDT slot to describe one.
 *
 * THE ONE DELIBERATE DIVERGENCE FROM THE REFERENCE - save_bb
 * ---------------------------------------------------------
 * The reference stashes its `bb` argument in save_edx across the call:
 *
 *   __bios32PnP  0x6f50   mov [0x80dc], edx      ; save_edx = bb
 *   __PnPEntry   0x6ff7   mov ds:save_edx, edx   ; save_edx = bb->edx  (!)
 *   __PnPEntry   0x704d   mov edx, ds:save_edx
 *   __bios32PnP  0x6faa   mov edx, [0x80dc]      ; expects bb, gets bb->edx
 *
 * Both slots are address 0x80dc; IDA and Ghidra agree on all four
 * instructions.  _PnPEntry therefore destroys the stashed `bb` pointer
 * before the BIOS is even entered, and on return __bios32PnP writes the
 * whole output register block through whatever bb->edx happened to be.
 * bb->edx is zero on every call this driver makes (setupSegments zeroes
 * the block and nothing sets edx), so the reference writes to addresses
 * 0x04..0x28 - a null-page store.
 *
 * save_edx is the only one of the seven scratch slots with this overlap;
 * save_eax, save_ecx, save_es, save_flag, new_eax and new_edx are each
 * used entirely before or entirely after the transition.  Rather than
 * reproduce a guaranteed panic, __bios32PnP below stashes bb in its own
 * slot, save_bb, and _PnPEntry keeps save_edx exactly as the reference
 * has it.  All fourteen reference symbol names are still emitted; save_bb
 * is one additional local.
 */

__asm__(
    ".text\n"
    ".align 2, 0x90\n"

    /* -----------------------------------------------------------------
     * __bios32PnP - 32-bit side of the call.  cdecl, one argument.
     * Reference: 0x6f24, 200 bytes (Ghidra; IDA has no function object).
     * ----------------------------------------------------------------- */
    ".globl __bios32PnP\n"
    "__bios32PnP:\n"
    "    enter $0, $0\n"
    "    pushal\n"
    "    pushl %es\n"
    "    pushl %fs\n"
    "    pushl %gs\n"
    "    pushfl\n"

    "    movl  8(%ebp), %edx\n"          /* edx = bb                       */
    "    movw  0x20(%edx), %ax\n"        /* bb->entrySel  ...              */
    "    movw  %ax, save_seg\n"          /* ... patched into the far call  */
    "    movl  0x2c(%edx), %eax\n"       /* bb->entryOffset ...            */
    "    movl  %eax, save_addr\n"        /* ... patched into the far call  */

    "    movl  0x08(%edx), %ebx\n"       /* bb->ebx                        */
    "    movl  0x0c(%edx), %ecx\n"       /* bb->ecx                        */
    "    movl  0x14(%edx), %edi\n"       /* bb->edi                        */
    "    movl  0x18(%edx), %esi\n"       /* bb->esi                        */
    "    movl  %edx, save_bb\n"          /* stash bb itself - see note     */
    "    movl  0x04(%edx), %eax\n"
    "    movl  %eax, new_eax\n"          /* bb->eax staged                 */
    "    movl  0x10(%edx), %eax\n"
    "    movl  %eax, new_edx\n"          /* bb->edx staged                 */

    "    movw  0x22(%edx), %ax\n"        /* bb->dataSel                    */
    "    pushw %ax\n"
    "    movl  new_eax, %eax\n"          /* load EAX/EDX last: EDX was bb  */
    "    movl  new_edx, %edx\n"
    "    .byte 0x66, 0x1f\n"             /* popw %ds - encoded literally   */
                                         /* so the pop is 2 bytes wide and */
                                         /* balances the pushw above       */
    "    cli\n"

    /*
     * Far call to save_seg:save_addr, i.e. into _PnPEntry through the
     * 32-bit code alias in GDT[19].  The operand bytes are the two labels.
     */
    "    .byte 0x9a\n"
    "save_addr:\n"
    "    .byte 0, 0, 0, 0\n"
    "save_seg:\n"
    "    .byte 0, 0\n"

    /* ---- the BIOS call has completed and bios_rtn has returned here ---- */

    "    pushfl\n"
    "    pushw %ax\n"
    "    movw  _kernDataSel, %ax\n"      /* the BIOS may have clobbered DS */
    "    movw  %ax, %ds\n"
    "    popw  %ax\n"
    "    movl  %eax, save_eax\n"         /* full EAX: AX is the status     */
    "    popl  %eax\n"                   /* the pushfl value               */
    "    movw  %ax, save_flag\n"
    "    movw  %es, %ax\n"
    "    movw  %ax, save_es\n"

    "    movl  %edx, new_edx\n"
    "    movl  save_bb, %edx\n"          /* recover bb - see note          */
    "    movl  new_edx, %eax\n"
    "    movl  %eax, 0x10(%edx)\n"       /* bb->edx                        */
    "    movl  save_eax, %eax\n"
    "    movl  %eax, 0x04(%edx)\n"       /* bb->eax = status               */
    "    movw  save_es, %ax\n"
    "    movw  %ax, 0x24(%edx)\n"        /* bb->es                         */
    "    movw  save_flag, %ax\n"
    "    movw  %ax, 0x28(%edx)\n"        /* bb->flags                      */
    "    movl  %ebx, 0x08(%edx)\n"
    "    movl  %ecx, 0x0c(%edx)\n"
    "    movl  %edi, 0x14(%edx)\n"
    "    movl  %esi, 0x18(%edx)\n"
    "    movl  %ebp, 0x1c(%edx)\n"

    "    popfl\n"                        /* re-enables interrupts          */
    "    popl %gs\n"
    "    popl %fs\n"
    "    popl %es\n"
    "    popal\n"
    "    leave\n"
    "    ret\n"

    /* -----------------------------------------------------------------
     * __PnPEntry - runs through GDT[19], whose base is _PnPEntry itself,
     * so _PnPEntry sits at offset 0 of that segment and a 16-bit far
     * return into bios_rtn stays inside 64K.
     * Reference: 0x6fec, 103 bytes, plus the unbound 7-byte far jump.
     * ----------------------------------------------------------------- */
    ".globl __PnPEntry\n"
    "__PnPEntry:\n"
    "    movl %eax, save_eax\n"
    "    movl %ecx, save_ecx\n"
    "    movl %edx, save_edx\n"
    "    movl _PnPEntry_biosCodeOffset, %eax\n"
    "    movl %eax, targ_addr\n"          /* patch the far jump operand    */
    "    movw _PnPEntry_biosCodeSelector, %ax\n"
    "    movw %ax, targ_sel\n"
    "    movl _PnPEntry_argStackBase, %ecx\n"
    "    movl _PnPEntry_numArgs, %edx\n"
    "    jmp  check_done\n"               /* test at bottom                */
    "push_arg:\n"
    "    movw (%ecx,%edx,2), %ax\n"
    "    pushw %ax\n"
    "check_done:\n"
    "    decl %edx\n"
    "    jns  push_arg\n"

    /*
     * Build the 16-bit far return address the BIOS will use: our own CS
     * (the GDT[19] alias) and the CS-relative offset of bios_rtn.
     */
    "    movw %cs, %ax\n"
    "    pushw %ax\n"
    "    movl $bios_rtn, %eax\n"
    "    subl $__PnPEntry, %eax\n"
    "    pushw %ax\n"

    "    movl save_eax, %eax\n"
    "    movl save_ecx, %ecx\n"
    "    movl save_edx, %edx\n"

    /* Far jump into the PM16 BIOS entry point; operands patched above. */
    "    .byte 0xea\n"
    "targ_addr:\n"
    "    .byte 0, 0, 0, 0\n"
    "targ_sel:\n"
    "    .byte 0, 0\n"

    /* -----------------------------------------------------------------
     * bios_rtn - where the BIOS's 16-bit far return lands.
     * Reference: 0x705a, 20 bytes.
     * ----------------------------------------------------------------- */
    "bios_rtn:\n"
    "    movl %eax, save_eax\n"           /* AX holds the BIOS status      */
    "    movl _PnPEntry_numArgs, %eax\n"
    "    addl %eax, %esp\n"
    "    addl %eax, %esp\n"               /* esp += 2 * numArgs            */
    "    movl save_eax, %eax\n"
    "    lret\n"                          /* 32-bit far return to _bios32PnP */

    /* -----------------------------------------------------------------
     * Thunk-private scratch storage.  Laid out to match the reference's
     * __data addresses 0x80d0..0x80eb, including its two padding words.
     * ----------------------------------------------------------------- */
    ".data\n"
    ".align 2\n"
    "save_es:\n"
    "    .word 0\n"
    "    .word 0\n"                       /* pad, as in the reference      */
    "save_eax:\n"
    "    .long 0\n"
    "save_ecx:\n"
    "    .long 0\n"
    "save_edx:\n"
    "    .long 0\n"
    "save_flag:\n"
    "    .word 0\n"
    "    .word 0\n"                       /* pad, as in the reference      */
    "new_eax:\n"
    "    .long 0\n"
    "new_edx:\n"
    "    .long 0\n"
    "save_bb:\n"
    "    .long 0\n"                       /* not in the reference - see note */
    ".text\n"
);

/*
 * call_bios - C entry point for one PnP BIOS call.
 * Reference: _call_bios at 0x3880, 71 bytes.
 */
int call_bios(struct pnp_bios_regs *bb)
{
    if (verbose == 1) {
        IOLog("PnPBios: calling BIOS\n");
    }

    _bios32PnP(bb);

    if (verbose == 1) {
        IOLog("PnPBios: BIOS returned 0x%x\n", bb->eax);
    }

    return (int)bb->eax;
}

/*
 * clearPnPConfigRegisters - Clear all PnP configuration registers
 *
 * Writes zero to all PnP configuration registers via I/O ports:
 * - 0x279: PnP address port
 * - 0xa79: PnP write data port
 *
 * This clears registers in ranges:
 * - 0x70-0x73: Memory descriptors
 * - 0x74-0x75: Special registers (write 4)
 * - 0x60-0x6f: I/O descriptors
 * - 0x40-0x5c: DMA/IRQ descriptors
 * - 0x76-0x7f, 0x80-0x89, 0x90-0x99, 0xa0-0xa9: Extended descriptors
 */
void clearPnPConfigRegisters(void)
{
    int i, j;
    unsigned char addr;

    /* Clear registers 0x70-0x73 (Memory descriptors) */
    for (i = 0; i < 2; i++) {
        for (j = 0; j < 2; j++) {
            addr = 0x70 + (i * 2) + j;
            __asm__ volatile("outb %b0,%w1" : : "a"(addr), "d"(0x279));
            __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0), "d"(0xa79));
        }
    }

    /* Clear registers 0x74-0x75 (Special - write 4) */
    for (i = 0; i < 2; i++) {
        for (j = 0; j < 1; j++) {
            addr = 0x74 + i + j;
            __asm__ volatile("outb %b0,%w1" : : "a"(addr), "d"(0x279));
            __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)4), "d"(0xa79));
        }
    }

    /* Clear registers 0x60-0x6f (I/O descriptors) */
    for (i = 0; i < 8; i++) {
        for (j = 0; j < 2; j++) {
            addr = 0x60 + (i * 2) + j;
            __asm__ volatile("outb %b0,%w1" : : "a"(addr), "d"(0x279));
            __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0), "d"(0xa79));
        }
    }

    /* Clear registers 0x40-0x5c (DMA/IRQ descriptors) */
    for (i = 0; i < 4; i++) {
        for (j = 0; j < 5; j++) {
            addr = 0x40 + (i * 8) + j;
            __asm__ volatile("outb %b0,%w1" : : "a"(addr), "d"(0x279));
            __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0), "d"(0xa79));
        }
    }

    /* Clear extended registers (varies by i) */
    for (i = 0; i < 4; i++) {
        unsigned char baseAddr;

        /* Determine base address based on i */
        switch (i) {
        case 0:
            baseAddr = 0x76;
            break;
        case 1:
            baseAddr = 0x80;
            break;
        case 2:
            baseAddr = 0x90;
            break;
        case 3:
            baseAddr = 0xa0;
            break;
        default:
            baseAddr = 0x76;
            break;
        }

        for (j = 0; j < 9; j++) {
            addr = baseAddr + j;
            __asm__ volatile("outb %b0,%w1" : : "a"(addr), "d"(0x279));
            __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0), "d"(0xa79));
        }
    }
}

/*
 * Read one bit from the ISA PnP isolation protocol
 *
 * The isolation protocol reads each bit by reading from the read port twice.
 * For a '1' bit: first read = 0x55, second read = 0xAA
 * For a '0' bit: different pattern
 * Returns 1 if bit is set, 0 if clear.
 */
static unsigned char readIsolationBit(void)
{
    unsigned char bit1, bit2;

    /* Read first byte from PnP read port */
    __asm__ volatile("inb %w1,%b0" : "=a"(bit1) : "d"(pnpReadPort));

    /* Read second byte from PnP read port */
    __asm__ volatile("inb %w1,%b0" : "=a"(bit2) : "d"(pnpReadPort));

    /* Check if this is a '1' bit: first = 0x55 ('U') AND second = 0xAA (-0x56) */
    return (bit2 == 0xAA && bit1 == 0x55);
}

/*
 * Set a bit in a byte array
 *
 * Sets bit number 'bitNum' in the byte array pointed to by 'bytes'.
 * bitNum 0-7 sets bits in bytes[0], 8-15 in bytes[1], etc.
 */
static void setBit(unsigned char *bytes, int bitNum, int value)
{
    unsigned char *bytePtr;
    int adjustedBitNum;
    unsigned char bitPosition;
    unsigned char mask;

    /* Adjust for negative bit numbers (handle division properly) */
    adjustedBitNum = bitNum;
    if (bitNum < 0) {
        adjustedBitNum = bitNum + 7;
    }

    /* Get bit position within byte (bitNum % 8) */
    bitPosition = (unsigned char)(bitNum % 8);

    /* Calculate pointer to the byte containing this bit (bytes + bitNum/8) */
    bytePtr = bytes + (adjustedBitNum >> 3);

    if (value == 0) {
        /* Clear the bit */
        /* Mask bit position to 5 bits */
        bitPosition = bitPosition & 0x1f;

        /* Create mask with 0 at bitPosition and 1s everywhere else */
        /* This is: ~(1 << bitPosition) */
        mask = ((unsigned char)(-2 << bitPosition)) |
               ((unsigned char)(0xfffffffe >> (0x20 - bitPosition)));

        *bytePtr = *bytePtr & mask;
    } else {
        /* Set the bit */
        /* Mask bit position to 5 bits */
        bitPosition = bitPosition & 0x1f;

        /* Set bit at bitPosition */
        *bytePtr = *bytePtr | (unsigned char)(1 << bitPosition);
    }
}

/*
 * Compute ISA PnP checksum using LFSR
 *
 * The checksum is computed by running an LFSR starting with seed 0x6A.
 * Each data bit is XORed into the LFSR.
 *
 * Returns the updated checksum value.
 */
static unsigned char computeChecksum(unsigned char checksum, unsigned char bit)
{
    /* LFSR computation:
     * - Shift checksum right by 1
     * - Compute new bit 7 as: (checksum bit 0) XOR (checksum bit 1) XOR (input bit)
     * - OR the new bit into position 7
     */
    return (checksum >> 1) | (((checksum & 1) ^ ((checksum & 2) >> 1) ^ (bit & 1)) << 7);
}

/*
 * ISA PnP card isolation protocol
 *
 * This function implements the ISA Plug and Play card isolation protocol.
 * It reads 64 bits of card identifier plus 8 bits of checksum from the card,
 * verifies the checksum, and if valid assigns the card the specified CSN.
 *
 * The isolation protocol allows detecting multiple ISA PnP cards on the bus
 * by reading unique card identifiers one bit at a time.
 *
 * Returns 1 if a card was successfully isolated (checksum matched), 0 otherwise.
 */
int isolateCard(unsigned char csn)
{
    unsigned char checksum;
    unsigned char receivedChecksum;
    unsigned char cardData[8];  /* 64 bits of card identifier */
    unsigned char bit;
    int i;

    /* Wake CSN 0 (all unconfigured cards) - register 0x03 */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)3), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0), "d"(0xa79));

    /* Set Read Data Port - register 0x01 - currently in isolation mode */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)1), "d"(0x279));

    /* Sleep 1ms to allow cards to respond */
    IOSleep(1);

    /* Initialize checksum with seed value */
    checksum = 0x6a;

    /* Clear card data buffer */
    for (i = 0; i < 8; i++) {
        cardData[i] = 0;
    }

    /* Read 64 bits (8 bytes) of card identifier data */
    for (i = 0; i < 64; i++) {
        /* Read one isolation bit */
        bit = readIsolationBit();

        /* Store bit in card data array */
        setBit(cardData, i, bit);

        /* Update checksum with this bit */
        checksum = computeChecksum(checksum, bit);

        /* Delay 250 microseconds between bits */
        IODelay(250);
    }

    /* Read 8 checksum bits from the card */
    receivedChecksum = 0;
    for (i = 0; i < 8; i++) {
        /* Read one isolation bit */
        bit = readIsolationBit();

        /* Store bit in checksum byte */
        setBit(&receivedChecksum, i, bit);

        /* Delay 250 microseconds between bits */
        IODelay(250);
    }

    /* Check if received checksum matches computed checksum */
    if (receivedChecksum == checksum) {
        /* Checksum matches - assign this card the CSN */
        /* Card Select Number register (0x06) */
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)6), "d"(0x279));
        __asm__ volatile("outb %b0,%w1" : : "a"(csn), "d"(0xa79));

        return 1;  /* Success */
    }

    /* Checksum mismatch - no card isolated */
    return 0;
}
