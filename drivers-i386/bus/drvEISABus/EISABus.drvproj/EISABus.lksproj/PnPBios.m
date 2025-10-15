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
 * PnPBios.m
 * PnP BIOS Interface Implementation
 */

#import "PnPBios.h"
#import <driverkit/generalFuncs.h>

@implementation PnPBios

- init
{
    [super init];

    _biosData = NULL;
    _biosAddress = 0;

    return self;
}

- free
{
    if (_biosData != NULL) {
        IOFree(_biosData, 4096);
        _biosData = NULL;
    }
    return [super free];
}

- (BOOL)detectBios
{
    /* Search for PnP BIOS signature "$PnP" in ROM area */
    unsigned char *romAddr;
    unsigned int addr;

    for (addr = 0xF0000; addr < 0x100000; addr += 16) {
        romAddr = (unsigned char *)addr;

        if (romAddr[0] == '$' && romAddr[1] == 'P' &&
            romAddr[2] == 'n' && romAddr[3] == 'P') {

            /* Verify checksum */
            unsigned char checksum = 0;
            unsigned char length = romAddr[5];
            int i;

            for (i = 0; i < length; i++) {
                checksum += romAddr[i];
            }

            if (checksum == 0) {
                /* Valid PnP BIOS found */
                _biosAddress = addr;

                /* Allocate and copy BIOS data */
                _biosData = IOMalloc(4096);
                if (_biosData != NULL) {
                    unsigned char *data = (unsigned char *)_biosData;
                    for (i = 0; i < 4096 && addr + i < 0x100000; i++) {
                        data[i] = romAddr[i];
                    }
                }

                IOLog("PnPBios: Found PnP BIOS at 0x%08X\n", addr);
                return YES;
            }
        }
    }

    IOLog("PnPBios: No PnP BIOS detected\n");
    return NO;
}

- (void *)getBiosData
{
    return _biosData;
}

@end
