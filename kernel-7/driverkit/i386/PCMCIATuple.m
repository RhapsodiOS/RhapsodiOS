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
 * PCMCIA Tuple Implementation
 */

#import <mach/mach_types.h>
#import <driverkit/i386/PCMCIATuple.h>
#import <libkern/libkern.h>

@implementation PCMCIATuple

- initWithCode:(unsigned char)code
          link:(unsigned char)link
          data:(unsigned char *)data
        length:(unsigned int)length
{
    [super init];

    _code = code;
    _link = link;
    _length = length;

    if (length > 0 && data != NULL) {
        _data = (unsigned char *)IOMalloc(length);
        if (_data) {
            bcopy(data, _data, length);
        }
    } else {
        _data = NULL;
    }

    return self;
}

- free
{
    if (_data) {
        IOFree(_data, _length);
        _data = NULL;
    }
    return [super free];
}

- (unsigned char)code
{
    return _code;
}

- (unsigned char)link
{
    return _link;
}

- (unsigned char *)data
{
    return _data;
}

- (unsigned int)length
{
    return _length;
}

/*
 * Parse CISTPL_MANFID tuple (manufacturer ID)
 * Format: 2 bytes manufacturer ID, 2 bytes card ID
 */
- (BOOL)parseManufacturerID:(unsigned short *)manfid
                     cardID:(unsigned short *)cardid
{
    if (_code != CISTPL_MANFID || _length < 4 || _data == NULL) {
        return NO;
    }

    if (manfid) {
        *manfid = (_data[1] << 8) | _data[0];
    }

    if (cardid) {
        *cardid = (_data[3] << 8) | _data[2];
    }

    return YES;
}

/*
 * Parse CISTPL_FUNCID tuple (function ID)
 * Format: 1 byte function code
 */
- (BOOL)parseFunctionID:(unsigned char *)funcid
{
    if (_code != CISTPL_FUNCID || _length < 1 || _data == NULL) {
        return NO;
    }

    if (funcid) {
        *funcid = _data[0];
    }

    return YES;
}

/*
 * Parse CISTPL_VERS_1 tuple (version/product information)
 * Format: major version, minor version, null-terminated strings
 */
- (BOOL)parseVersionString:(char *)product
                    vendor:(char *)vendor
                   version:(char *)version
{
    unsigned int i, str_index;
    char *strings[4] = { vendor, product, version, NULL };
    unsigned int str_count = 0;

    if (_code != CISTPL_VERS_1 || _length < 2 || _data == NULL) {
        return NO;
    }

    /* Skip major/minor version bytes */
    i = 2;
    str_index = 0;

    /* Parse up to 3 null-terminated strings */
    while (i < _length && str_count < 3) {
        if (_data[i] == 0xFF) {
            break;  /* End of strings */
        }

        if (_data[i] == 0x00) {
            /* Null terminator, move to next string */
            str_count++;
            i++;
            str_index = 0;
            continue;
        }

        /* Copy character to appropriate string buffer */
        if (strings[str_count] && str_index < 63) {
            strings[str_count][str_index++] = _data[i];
        }
        i++;
    }

    /* Null-terminate all strings */
    if (vendor) vendor[str_index] = '\0';
    if (product && str_count > 0) {
        /* Find the last character written to product */
        for (i = 0; i < 63 && product[i] != '\0'; i++);
        product[i] = '\0';
    }
    if (version && str_count > 1) {
        for (i = 0; i < 63 && version[i] != '\0'; i++);
        version[i] = '\0';
    }

    return YES;
}

@end
