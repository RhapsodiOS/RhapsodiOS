/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * "Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.0 (the 'License').  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License."
 *
 * @APPLE_LICENSE_HEADER_END@
 */
/*
 * ISASerialPortChip.c - identifying, initialising and programming the UART.
 *
 * Plain C: none of these three functions references an Objective-C construct,
 * and none of them calls anything beyond the outb()/inb() inlines and the
 * compiler's 64-bit divide helpers.  They appear in the order the reference
 * links them.
 *
 * HISTORY
 */

#import "ISASerialPortInternal.h"
#import <driverkit/i386/ioPorts.h>

/*
 * Work out which part is at port->Base and return its row in Chip[].
 *
 * A ladder of register probes, no calls and no delays: the lock incl that
 * ioPorts.h's outb() emits after each out is all the settling the reference
 * ever does.  Base is re-read from the struct before every access.  Returning 0
 * means there is no UART here at all, and initFromDeviceDescription: treats
 * that as a hard failure.
 */
int identifyChip(Port *port)
{
    unsigned int probe;
    unsigned int banked;
    unsigned char mcr;

    /* Rung 1: with DLAB set, the divisor latch low byte must hold what it is
     * given.  Nothing that fails here is a UART.  */
    outb(port->Base + UART_LCR, LCR_DLAB);
    outb(port->Base + UART_DLL, 0x5A);
    if (inb(port->Base + UART_DLL) != 0x5A) {
        return CHIP_UNKNOWN;
    }
    outb(port->Base + UART_DLL, 0xA5);
    if (inb(port->Base + UART_DLL) != 0xA5) {
        return CHIP_UNKNOWN;
    }

    /* Rung 2: the scratch register at +7 arrived with the 8250A, so a part
     * that cannot hold a byte there is a plain 8250.  */
    outb(port->Base + UART_LCR, 0);
    outb(port->Base + UART_SCR, 0x5A);
    if (inb(port->Base + UART_SCR) != 0x5A) {
        return CHIP_8250;
    }
    outb(port->Base + UART_SCR, 0xA5);
    if (inb(port->Base + UART_SCR) != 0xA5) {
        return CHIP_8250;
    }

    /* Rung 3: enable the FIFO and read IIR bits 6-7 back.  Bit 6 alone is the
     * 16550AF answer, bit 7 alone is the broken FIFO, and neither set leaves a
     * part with no FIFO to find.  */
    outb(port->Base + UART_FCR, FCR_FIFO_ENABLE | FCR_RCVR_RESET | FCR_XMIT_RESET);
    probe = inb(port->Base + UART_IIR) & 0xC0;
    outb(port->Base + UART_FCR, 0);

    switch (probe) {
    case 0x40:
        return CHIP_16550AF;

    case 0x80:
        return CHIP_16550_BADFIFO;

    case 0x00:
        /* Rung 4: the 82510 is the one part that answers on the two-bit FIFO
         * mode field.  */
        outb(port->Base + UART_FCR, 0x60);
        probe = inb(port->Base + UART_IIR) & 0x60;
        outb(port->Base + UART_FCR, 0);
        if (probe == 0x60) {
            return CHIP_82510;
        }

        /* Rung 5: MCR bit 7 is writable on the 16C1450 and reads back zero on
         * a plain 16450.  */
        outb(port->Base + UART_MCR, 0x80);
        mcr = inb(port->Base + UART_MCR) & 0x80;
        outb(port->Base + UART_MCR, 0);
        if (mcr == 0x80) {
            return CHIP_16C1450;
        }
        return CHIP_16450;
    }

    /* Rung 6: on the ST16C650 the scratchpad is banked by DLAB, so the byte
     * written with DLAB clear survives a second byte written with it set.  */
    outb(port->Base + UART_LCR, 0);
    outb(port->Base + UART_SCR, 0xDE);
    outb(port->Base + UART_LCR, LCR_DLAB);
    outb(port->Base + UART_SCR, 0xA9);
    banked = inb(port->Base + UART_SCR);
    outb(port->Base + UART_LCR, 0);
    if (inb(port->Base + UART_SCR) == 0xDE && banked == 0xA9) {
        return CHIP_ST16C650;
    }

    /*
     * Rung 7: MCR bit 7 separates the 16C1550 from the 16550AF.
     *
     * Apple's own defect, reproduced deliberately.  This path reads MCR
     * without writing 0x80 to it first -- rung 5 does write it, this one does
     * not, and every reference instruction from 19172 to 19328 was checked --
     * so the decision turns on whatever MCR happened to hold.  Correcting it
     * would not match.
     */
    mcr = inb(port->Base + UART_MCR) & 0x80;
    outb(port->Base + UART_MCR, 0);
    if (mcr == 0x80) {
        return CHIP_16C1550;
    }
    return CHIP_16550AF;
}

/*
 * Put the port back to 9600 8N1 and, if a part was actually found, quiet the
 * UART and program it.  Seven fields and no more: IERmask, LCRimage, RBRmask,
 * MasterClock and every queue field belong to somebody else.
 */
void initChip(Port *port)
{
    port->CharLength = 16;              /* 8 data bits */
    port->StopBits = 2;                 /* 1 stop bit */
    port->TX_Parity = PARITY_NONE;
    port->RX_Parity = 0;
    port->BaudRate = 19200;             /* half-bits/s, so 9600 bps */
    port->DLRimage = 0;
    port->FCRimage = 0;

    if (port->Type == CHIP_UNKNOWN) {
        return;
    }

    outb(port->Base + UART_LCR, 0);
    outb(port->Base + UART_IER, 0);
    outb(port->Base + UART_MCR, 0);
    programChip(port);
}

/*
 * Push CharLength, StopBits, TX_Parity, the break bit and BaudRate into the
 * UART and pick a FIFO trigger level to go with them.
 *
 * Note the early-out: if the divisor has not moved, the frame interval, the
 * divisor writes and the whole FCR switch are all skipped, so FCRimage
 * survives a no-op reprogram.  Note also that nothing here touches IERmask.
 */
void programChip(Port *port)
{
    int lcr = 0;
    unsigned short newDivisor;
    int halfBits;
    int nsPerChar;
    int triggerLevel;
    unsigned long long ns;

    /* Data bits, in half-bit units: 10 to 16, and even. */
    if (port->CharLength < 10) {
        port->CharLength = 10;
    } else if (port->CharLength > 16) {
        port->CharLength = 16;
    }
    port->CharLength &= 0xFFFFFFFE;

    switch (port->CharLength) {
    case 10:                            /* 5 data bits */
        lcr = 0;
        port->RBRmask = 0x1F;
        break;
    case 12:                            /* 6 data bits */
        lcr = 1;
        port->RBRmask = 0x3F;
        break;
    case 14:                            /* 7 data bits */
        lcr = 2;
        port->RBRmask = 0x7F;
        break;
    case 16:                            /* 8 data bits */
        lcr = 3;
        port->RBRmask = 0xFF;
        break;
    }

    /* Stop bits.  Anything past one stop bit becomes 1.5 on a 5-bit character
     * and 2 otherwise, which is what the UART actually does.  */
    if (port->StopBits <= 2) {
        port->StopBits = 2;
    } else {
        lcr |= 0x04;
        if (port->CharLength == 10) {
            port->StopBits = 3;
        } else {
            port->StopBits = 4;
        }
    }

    switch (port->TX_Parity) {
    case PARITY_NONE:
        break;
    case PARITY_ODD:
        lcr |= 0x08;
        break;
    case PARITY_EVEN:
        lcr |= 0x18;
        break;
    case PARITY_MARK:
        lcr |= 0x28;
        break;
    case PARITY_SPACE:
        lcr |= 0x38;
        break;
    }

    /* State bit 0x800 is "send break". */
    if (port->State & 0x00000800) {
        lcr |= 0x40;
    }

    /*
     * Clamp the rate.  The 100 floor is an else, not a second test: a rate
     * that had to be pulled down to the part's ceiling is never then pushed
     * back up.  Type is not range-checked here.
     */
    if (Chip[port->Type].MaxBaud < port->BaudRate) {
        port->BaudRate = Chip[port->Type].MaxBaud;
    } else if (port->BaudRate < 100) {
        port->BaudRate = 100;
    }

    newDivisor = (unsigned short)(port->MasterClock / (port->BaudRate << 3));

    if (port->DLRimage != newDivisor) {
        /* Half-bits on the wire per character: the data, the stop bits, and
         * either the two the framing costs or, when there is a parity bit to
         * carry as well, four.  */
        halfBits = port->CharLength + port->StopBits;
        if (port->TX_Parity == PARITY_NONE) {
            halfBits += 2;
        } else {
            halfBits += 4;
        }

        nsPerChar = (1000000000 / port->BaudRate) * halfBits;
        ns = nsPerChar;
        port->FrameInterval.tv_sec = ns / 1000000000;
        port->FrameInterval.tv_nsec = ns % 1000000000;

        /* DLAB stays set across both halves of the divisor. */
        outb(port->Base + UART_LCR, lcr | LCR_DLAB);
        port->DLRimage = newDivisor;
        outb(port->Base + UART_DLL, (unsigned char)port->DLRimage);
        outb(port->Base + UART_DLM, (unsigned char)(port->DLRimage >> 8));

        switch (port->Type) {
        case CHIP_16550_BADFIFO:
            /* The FIFO is there and does not work.  Say so to the chip. */
            port->FCRimage = 0;
            break;

        case CHIP_16550AF:
        case CHIP_16C1550:
            if (port->MinLatency) {
                /* Trigger on the first byte. */
                port->FCRimage = FCR_FIFO_ENABLE;
            } else {
                /*
                 * Start from the number of characters that fit in 10 ms, less
                 * three, then walk it down until the 17 characters' worth of
                 * headroom above the trigger is at least 2 ms.  The loop only
                 * ever decrements and is allowed to run past zero.
                 */
                triggerLevel = (10000000 - 3 * nsPerChar) / nsPerChar;
                while ((17 - triggerLevel) * nsPerChar < 2000000) {
                    triggerLevel--;
                }

                if (triggerLevel <= 3) {
                    port->FCRimage = FCR_FIFO_ENABLE;
                } else if (triggerLevel <= 7) {
                    port->FCRimage = FCR_FIFO_ENABLE | FCR_TRIGGER_4;
                } else {
                    port->FCRimage = FCR_FIFO_ENABLE | FCR_TRIGGER_8;
                }
            }
            break;

        case CHIP_ST16C650:
            if (port->MinLatency) {
                /* On this part minimum latency means no FIFO at all. */
                port->FCRimage = 0;
            } else {
                triggerLevel = (10000000 - 3 * nsPerChar) / nsPerChar;
                while ((17 - triggerLevel) * nsPerChar < 2000000) {
                    triggerLevel--;
                }

                if (triggerLevel < 0 && port->BaudRate <= 0x4AFF) {
                    /* Below 9600 bps the deep FIFO costs more latency than it
                     * saves interrupts.  */
                    port->FCRimage = 0;
                } else if (triggerLevel <= 15) {
                    port->FCRimage = FCR_FIFO_ENABLE;
                } else if (triggerLevel <= 23) {
                    port->FCRimage = FCR_FIFO_ENABLE | FCR_TRIGGER_4;
                } else {
                    port->FCRimage = FCR_FIFO_ENABLE | FCR_TRIGGER_8;
                }
            }
            break;

        default:
            /* Types 0, 1, 2, 3 and 8 have no FIFO control register worth
             * writing, so the image is cleared and nothing goes out -- which
             * is why this arm skips the write below rather than sharing it. */
            port->FCRimage = 0;
            goto writeLCR;
        }

        outb(port->Base + UART_FCR, port->FCRimage);
    }

writeLCR:
    outb(port->Base + UART_LCR, lcr);
    port->LCRimage = lcr;
}
