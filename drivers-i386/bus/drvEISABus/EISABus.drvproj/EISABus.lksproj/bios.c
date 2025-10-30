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
 * Global variables - ordered to match decompiled binary memory layout
 * Starting at 0x80CC
 */

/* 0x80CC */ char verbose = 0;                              /* Verbose logging flag */
/* 0x80CE */ unsigned short readPort = 0;                   /* PnP read port */
/* 0x80D0 */ unsigned short save_es = 0;                    /* Temp ES storage */
/* 0x80D4 */ unsigned int save_eax = 0;                     /* Temp EAX storage */
/* 0x80D8 */ unsigned int save_ecx = 0;                     /* Temp ECX storage */
/* 0x80DC */ unsigned int save_edx = 0;                     /* Saves biosCallData pointer */
/* 0x80E0 */ unsigned short save_flag = 0;                  /* Temp EFLAGS storage */
/* 0x80E4 */ unsigned int new_eax = 0;                      /* Input EAX value */
/* 0x80E8 */ unsigned int new_edx = 0;                      /* Input/output EDX value */
/* 0x80EC */ unsigned short *PnPEntry_argStackBase = NULL;  /* Argument stack base */
/* 0x80F0 */ int PnPEntry_numArgs = 0;                      /* Number of arguments */
/* 0x80F4 */ unsigned int PnPEntry_biosCodeOffset = 0;      /* BIOS code offset */
/* 0x80F8 */ unsigned short PnPEntry_biosCodeSelector = 0;  /* BIOS code selector */
/* 0x80FC */ unsigned short kernDataSel = 0x10;             /* Kernel data selector */

/* Far pointer structures defined in bios_asm.s (.data section) */
/* save_addr, save_seg, pnp_addr, pnp_seg are in writable memory */
/* Used by indirect far call/jump instructions */
/* Declarations are in bios.h */

/*
 * Call PnP BIOS with the given parameters structure
 */
int call_bios(void *biosCallData)
{
    int result;

    /* Optional verbose logging */
    if (verbose == 1) {
        IOLog("PnPBios: calling BIOS\n");
    }

    IOLog("PnPBios: Calling 16-bit BIOS at 0x%X:%0xX\n",
              ((BiosCallData *)biosCallData)->far_seg,
              ((BiosCallData *)biosCallData)->far_offset);

    /* Call low-level BIOS interface */
    _bios32PnP(biosCallData);

    /* Get the result from the eax register */
    result = ((BiosCallData *)biosCallData)->eax;

    /* Optional verbose logging of result */
    if (verbose == 1) {
        IOLog("PnPBios: BIOS returned 0x%x\n", result);
    }

    return result;
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
