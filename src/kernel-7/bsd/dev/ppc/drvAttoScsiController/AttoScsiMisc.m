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

/* AttoScsiMisc.m created by russb2 on Sat 30-May-1998 */

#import "AttoScsiController.h"

@implementation AttoScsiController
@end

/*
 * Miscellaneous IO worker routines
 */

u_int32_t AttoScsiReadRegs( volatile u_int8_t *chipRegs, u_int32_t regOffset, u_int32_t regSize )
{
    if ( regSize == 1 )
    {
        return chipRegs[regOffset];
    }
    if ( regSize == 2 )
    {
        return EndianSwap16( *(volatile u_int16_t *)&chipRegs[regOffset] );
    }
    else if (regSize == 4 )
    {
        return EndianSwap32( *(volatile u_int32_t *)&chipRegs[regOffset] );
    }
    else
    {
        kprintf("SCSI(SymBios875): AttoScsiReadRegs incorrect regSize\n\r" );
        return 0;
    } 
}

void AttoScsiWriteRegs( volatile u_int8_t *chipRegs, u_int32_t regOffset, u_int32_t regSize, u_int32_t regValue )
{
    if ( regSize == 1 )
    {
        chipRegs[regOffset] = regValue;
    }
    else if ( regSize == 2 )
    {
        volatile u_int16_t *p = (volatile u_int16_t *)&chipRegs[regOffset];
        *p = EndianSwap16( regValue );
    }
    else if ( regSize == 4 )
    {
        volatile u_int32_t *p = (volatile u_int32_t *)&chipRegs[regOffset];
        *p = EndianSwap32( regValue );
    }
    else
    {
        kprintf("SCSI(SymBios875): AttoScsiWriteRegs incorrect regSize\n\r" );
    }
    eieio();
}

void AttoScsiClearRegBits( volatile u_int8_t *chipRegs, u_int32_t regOffset, u_int32_t regSize, u_int32_t regBits )
{
    if ( regSize == 1 )
    {
        chipRegs[regOffset] &= ~regBits;
    }
    else if ( regSize == 2 )
    {
        volatile u_int16_t *p = (volatile u_int16_t *)&chipRegs[regOffset];
        *p &= EndianSwap16( ~regBits );
    }
    else if ( regSize == 4 )
    {
        volatile u_int32_t *p = (volatile u_int32_t *)&chipRegs[regOffset];
        *p &= EndianSwap32( ~regBits );
    }
    else
    {
        kprintf("SCSI(SymBios875): AttoScsiWriteRegs incorrect regSize\n\r" );
    }
    eieio();
}

void AttoScsiModRegBits( volatile u_int8_t *chipRegs, u_int32_t regOffset, u_int32_t regSize, u_int32_t regMask, u_int32_t regBits )
{
    if ( regSize == 1 )
    {
        chipRegs[regOffset] = (chipRegs[regOffset] & regMask) | regBits;
    }
    else if ( regSize == 2 )
    {
        volatile u_int16_t *p = (volatile u_int16_t *)&chipRegs[regOffset];
        *p = (*p & EndianSwap16( regMask )) | EndianSwap16( regBits );
    }
    else if ( regSize == 4 )
    {
        volatile u_int32_t *p = (volatile u_int32_t *)&chipRegs[regOffset];
        *p = (*p & EndianSwap32( regMask )) | EndianSwap32( regBits );
    }
    else
    {
        kprintf("SCSI(SymBios875): AttoScsiWriteRegs incorrect regSize\n\r" );
    }
    eieio();
}

/*
 * Synchronous transfer settings by SDTR period (transfer period / 4), for an
 * 80Mhz (doubled) and a 160Mhz (quadrupled) SCSI clock. 0xff ends a table.
 */
static PeriodEntry periodTable80MHz[] =
{
    { 0x0c, 0x95, 0x00 }, { 0x0f, 0x95, 0x20 }, { 0x12, 0xa5, 0x00 }, { 0x15, 0x95, 0x60 },
    { 0x19, 0x35, 0x00 }, { 0x1f, 0x35, 0x20 }, { 0x25, 0x45, 0x00 }, { 0x2b, 0x35, 0x60 },
    { 0x32, 0x55, 0x00 }, { 0x3e, 0x55, 0x20 }, { 0x4b, 0x55, 0x40 }, { 0x57, 0x55, 0x60 },
    { 0x64, 0x55, 0x80 }, { 0x70, 0x55, 0xa0 }, { 0x7d, 0x55, 0xc0 }, { 0x89, 0x55, 0xe0 },
    { 0xff, 0x55, 0xe0 }
};

static PeriodEntry periodTable160MHz[] =
{
    { 0x0a, 0x97, 0x00 }, { 0x0b, 0x97, 0x20 }, { 0x0c, 0xb7, 0x00 }, { 0x0f, 0xb7, 0x20 },
    { 0x12, 0xc7, 0x00 }, { 0x15, 0xb7, 0x60 }, { 0x19, 0x57, 0x00 }, { 0x1f, 0x57, 0x20 },
    { 0x25, 0x57, 0x40 }, { 0x2b, 0x57, 0x60 }, { 0x32, 0x77, 0x00 }, { 0x3e, 0x77, 0x20 },
    { 0x4b, 0x77, 0x40 }, { 0x57, 0x77, 0x60 }, { 0x64, 0x77, 0x80 }, { 0x70, 0x77, 0xa0 },
    { 0x7d, 0x77, 0xc0 }, { 0x89, 0x77, 0xe0 }, { 0xff, 0x77, 0xe0 }
};

PeriodEntry *GetPeriodEntry( u_int8_t period, u_int16_t flags )
{
    PeriodEntry		*entry;

    entry = (flags & kAttoFlagQuadClock) ? periodTable160MHz : periodTable80MHz;

    while ( entry->period < period )
    {
        entry++;
    }
    return entry;
}
