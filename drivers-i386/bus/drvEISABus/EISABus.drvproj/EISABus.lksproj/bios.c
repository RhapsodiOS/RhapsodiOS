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

/* Verbose logging flag */
char verbose = 0;

/* Global variables for PnP BIOS interface */
unsigned short PnPEntry_biosCodeSelector = 0;
unsigned int PnPEntry_biosCodeOffset = 0;
unsigned short *PnPEntry_argStackBase = NULL;
int PnPEntry_numArgs = 0;
unsigned short kernDataSel = 0x10;  /* Default kernel data selector */

/* Internal variables for _bios32PnP */
int save_edx = 0;
unsigned short uRam00006f7f = 0;
unsigned int uRam00006f7b = 0;

/* Internal variables for __PnPEntry */
int save_eax = 0;
int save_ecx = 0;
unsigned int *uRam00007054 = (unsigned int *)0x7054;  /* PnP entry offset location */
unsigned short *uRam00007058 = (unsigned short *)0x7058;  /* PnP entry selector location */

/*
 * Call PnP BIOS with the given parameters structure
 */
int call_bios(void *biosCallData)
{
    int result;

    /* Log if verbose mode enabled */
    if (verbose) {
        IOLog("PnPBios: calling BIOS\n");
    }

    /* Call low-level BIOS interface */
    _bios32PnP(biosCallData);

    /* Get result from offset 4 in biosCallData structure */
    result = *(int *)((char *)biosCallData + 4);

    /* Log result if verbose mode enabled */
    if (verbose) {
        IOLog("PnPBios: BIOS returned 0x%x\n", result);
    }

    return result;
}

/*
 * _bios32PnP - Low-level PnP BIOS entry point
 *
 * This function performs the actual far call to the PnP BIOS entry point.
 * It saves/restores all registers and handles segment switching for the BIOS call.
 *
 * The biosCallData structure layout (48 bytes / 0x30):
 *   +0x04: EAX (input/output)
 *   +0x08: EBX (input/output)
 *   +0x0C: ECX (input/output)
 *   +0x10: EDX (input/output)
 *   +0x14: ESI (input/output)
 *   +0x18: EDI (input/output)
 *   +0x1C: ESP (saved)
 *   +0x20: DS segment (input)
 *   +0x24: ES segment (output)
 *   +0x28: EFLAGS (output)
 */
void _bios32PnP(void *biosCallData)
{
    __asm__ __volatile__(
        /* Save all registers we're going to clobber */
        "pushal\n\t"
        "push %%ds\n\t"
        "push %%es\n\t"
        "push %%fs\n\t"
        "push %%gs\n\t"

        /* EDX = biosCallData pointer (passed in, save it) */
        "movl %%edx, _save_edx\n\t"

        /* Load input registers from biosCallData */
        "movl 0x04(%%edx), %%eax\n\t"    /* Load EAX */
        "movl 0x08(%%edx), %%ebx\n\t"    /* Load EBX */
        "movl 0x0C(%%edx), %%ecx\n\t"    /* Load ECX */
        "movl 0x10(%%edx), %%esi\n\t"    /* Load EDX (temp in ESI) */
        "movl 0x14(%%edx), %%edi\n\t"    /* Load ESI (temp in EDI) */
        "movl 0x18(%%edx), %%ebp\n\t"    /* Load EDI (temp in EBP) */

        /* Setup segments for BIOS call */
        "movw 0x20(%%edx), %%ds\n\t"     /* Load DS from biosCallData */
        "movw 0x20(%%edx), %%es\n\t"     /* Load ES (same as DS) */

        /* Save current ESP */
        "movl %%esp, 0x1C(%%edx)\n\t"

        /* Push arguments from PnP argument stack */
        "movl _PnPEntry_numArgs, %%edx\n\t"
        "testl %%edx, %%edx\n\t"
        "jz 2f\n\t"                       /* Skip if no args */
        "movl _PnPEntry_argStackBase, %%edx\n\t"
        "1:\n\t"
        "decl _PnPEntry_numArgs\n\t"
        "movl _PnPEntry_numArgs, %%esp\n\t"
        "movzwl (%%edx,%%esp,2), %%esp\n\t"
        "push %%esp\n\t"
        "movl _PnPEntry_numArgs, %%esp\n\t"
        "testl %%esp, %%esp\n\t"
        "jnz 1b\n\t"
        "2:\n\t"

        /* Move temps to final registers */
        "movl %%esi, %%edx\n\t"          /* EDX from temp */
        "movl %%edi, %%esi\n\t"          /* ESI from temp */
        "movl %%ebp, %%edi\n\t"          /* EDI from temp */

        /* Store values to special memory locations (from decompiled code) */
        "movl _save_edx, %%ebp\n\t"
        "movw 0x20(%%ebp), %%bp\n\t"
        "movw %%bp, _uRam00006f7f\n\t"
        "movl 0x2C(%%ebp), %%ebp\n\t"
        "movl %%ebp, _uRam00006f7b\n\t"

        /* Perform far call to PnP BIOS entry point */
        /* Push return address segment:offset, then jump */
        "pushl $0x10\n\t"                 /* Kernel code segment */
        "pushl $3f\n\t"                   /* Return address offset */
        "pushl _PnPEntry_biosCodeSelector\n\t"
        "pushl _PnPEntry_biosCodeOffset\n\t"
        "lret\n\t"                        /* Far return to BIOS */

        /* BIOS returns here */
        "3:\n\t"

        /* Save result registers back to biosCallData */
        "movl _save_edx, %%ebp\n\t"
        "movl %%eax, 0x04(%%ebp)\n\t"    /* Save EAX */
        "movl %%ebx, 0x08(%%ebp)\n\t"    /* Save EBX */
        "movl %%ecx, 0x0C(%%ebp)\n\t"    /* Save ECX */
        "movl %%edx, 0x10(%%ebp)\n\t"    /* Save EDX */
        "movl %%esi, 0x14(%%ebp)\n\t"    /* Save ESI */
        "movl %%edi, 0x18(%%ebp)\n\t"    /* Save EDI */

        /* Save ES segment */
        "movw %%es, %%ax\n\t"
        "movw %%ax, 0x24(%%ebp)\n\t"

        /* Save EFLAGS */
        "pushfl\n\t"
        "popl %%eax\n\t"
        "movw %%ax, 0x28(%%ebp)\n\t"

        /* Restore segments */
        "movw _kernDataSel, %%ax\n\t"
        "movw %%ax, %%ds\n\t"
        "movw %%ax, %%es\n\t"

        /* Restore saved registers */
        "pop %%gs\n\t"
        "pop %%fs\n\t"
        "pop %%es\n\t"
        "pop %%ds\n\t"
        "popal\n\t"

        : /* no outputs */
        : "d" (biosCallData)  /* EDX = biosCallData */
        : "memory", "cc"
    );
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
            __asm__ volatile("outb %0, %1" : : "a"(addr), "d"(0x279));
            __asm__ volatile("outb %0, %1" : : "a"((unsigned char)0), "d"(0xa79));
        }
    }

    /* Clear registers 0x74-0x75 (Special - write 4) */
    for (i = 0; i < 2; i++) {
        for (j = 0; j < 1; j++) {
            addr = 0x74 + i + j;
            __asm__ volatile("outb %0, %1" : : "a"(addr), "d"(0x279));
            __asm__ volatile("outb %0, %1" : : "a"((unsigned char)4), "d"(0xa79));
        }
    }

    /* Clear registers 0x60-0x6f (I/O descriptors) */
    for (i = 0; i < 8; i++) {
        for (j = 0; j < 2; j++) {
            addr = 0x60 + (i * 2) + j;
            __asm__ volatile("outb %0, %1" : : "a"(addr), "d"(0x279));
            __asm__ volatile("outb %0, %1" : : "a"((unsigned char)0), "d"(0xa79));
        }
    }

    /* Clear registers 0x40-0x5c (DMA/IRQ descriptors) */
    for (i = 0; i < 4; i++) {
        for (j = 0; j < 5; j++) {
            addr = 0x40 + (i * 8) + j;
            __asm__ volatile("outb %0, %1" : : "a"(addr), "d"(0x279));
            __asm__ volatile("outb %0, %1" : : "a"((unsigned char)0), "d"(0xa79));
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
            __asm__ volatile("outb %0, %1" : : "a"(addr), "d"(0x279));
            __asm__ volatile("outb %0, %1" : : "a"((unsigned char)0), "d"(0xa79));
        }
    }
}

/*
 * __PnPEntry - Low-level PnP BIOS entry trampoline
 *
 * This function sets up a far call to the PnP BIOS entry point through a fixed
 * memory location trampoline. It's called with __regparm3 convention:
 *   param_1 in EAX
 *   param_2 in EDX
 *   param_3 in ECX
 *
 * The function:
 * 1. Sets up the far call target address at memory location 0x7054-0x7058
 * 2. Pushes arguments from the PnP argument stack
 * 3. Saves registers for the BIOS call
 * 4. Makes an indirect far call through the trampoline
 */
void __attribute__((regparm(3))) __PnPEntry(unsigned int param_1, unsigned int param_2, unsigned int param_3)
{
    __asm__ __volatile__(
        /* Save incoming register parameters */
        "movl %%eax, _save_eax\n\t"
        "movl %%ecx, _save_ecx\n\t"
        "movl %%edx, _save_edx\n\t"

        /* Set up far call target at fixed memory location */
        /* Write PnP BIOS entry offset to 0x7054 */
        "movl _PnPEntry_biosCodeOffset, %%eax\n\t"
        "movl $0x7054, %%edx\n\t"
        "movl %%eax, (%%edx)\n\t"

        /* Write PnP BIOS entry selector to 0x7058 */
        "movzwl _PnPEntry_biosCodeSelector, %%eax\n\t"
        "movl $0x7058, %%edx\n\t"
        "movw %%ax, (%%edx)\n\t"

        /* Push arguments from PnP argument stack in reverse order */
        "movl _PnPEntry_numArgs, %%ecx\n\t"
        "testl %%ecx, %%ecx\n\t"
        "jz 2f\n\t"                           /* Skip if no arguments */

        "1:\n\t"
        "decl %%ecx\n\t"                      /* Decrement counter */
        "jl 2f\n\t"                           /* Exit if counter < 0 */

        "movl _PnPEntry_argStackBase, %%edx\n\t"
        "movzwl (%%edx,%%ecx,2), %%eax\n\t"  /* Load arg[ecx] as word */
        "pushw %%ax\n\t"                      /* Push argument */
        "jmp 1b\n\t"                          /* Loop */

        "2:\n\t"
        /* Push return address (CS:IP for far return) */
        "pushw %%cs\n\t"                      /* Push code segment */
        "pushl $0x6e\n\t"                     /* Push return offset */

        /* Restore saved parameters for BIOS call */
        "movl _save_eax, %%eax\n\t"
        "movl _save_ecx, %%ecx\n\t"
        "movl _save_edx, %%edx\n\t"

        /* Make indirect far call through trampoline at 0x7054 */
        /* This jumps to the PnP BIOS entry point */
        "lcall *(0x7054)\n\t"

        /* BIOS returns here (at offset 0x6e from the push above) */

        : /* no outputs */
        : "a" (param_1), "d" (param_2), "c" (param_3)
        : "memory", "cc"
    );
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
    __asm__ volatile("inb %1, %0" : "=a"(bit1) : "d"(pnpReadPort));

    /* Read second byte from PnP read port */
    __asm__ volatile("inb %1, %0" : "=a"(bit2) : "d"(pnpReadPort));

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
    __asm__ volatile("outb %0, %1" : : "a"((unsigned char)3), "d"(0x279));
    __asm__ volatile("outb %0, %1" : : "a"((unsigned char)0), "d"(0xa79));

    /* Set Read Data Port - register 0x01 - currently in isolation mode */
    __asm__ volatile("outb %0, %1" : : "a"((unsigned char)1), "d"(0x279));

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
        __asm__ volatile("outb %0, %1" : : "a"((unsigned char)6), "d"(0x279));
        __asm__ volatile("outb %0, %1" : : "a"(csn), "d"(0xa79));

        return 1;  /* Success */
    }

    /* Checksum mismatch - no card isolated */
    return 0;
}
