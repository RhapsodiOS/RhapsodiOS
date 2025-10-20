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
 * PCMCIA Resource Driver Implementation
 */

#import "PCMCIAResourceDriver.h"

@implementation PCMCIAResourceDriver

/*
 * Class method to probe and create resource driver
 */
+ (BOOL)probe:deviceDesc
{
    id instance;
    int result;

    /* Allocate and initialize resource driver */
    instance = [[PCMCIAResourceDriver alloc] initFromDeviceDescription:deviceDesc];

    /* Call registerDevice */
    result = [instance registerDevice];

    if (result == 0) {
        return NO;
    }
    return YES;
}

/*
 * Initialize from device description
 */
- initFromDeviceDescription:deviceDesc
{
    id result;

    /* Call superclass initializer */
    result = [super initFromDeviceDescription:deviceDesc];

    if (result != nil) {
        /* Set device name */
        [self setName:"PCMCIA0"];

        /* Set device kind */
        [self setDeviceKind:"Bus"];

        /* Register the device */
        [self registerDevice];
    }

    return result;
}

/*
 * Get character values for parameter
 */
- (int)getCharValues:(unsigned char *)values
        forParameter:(const char *)parameterName
               count:(unsigned int *)count
{
    char *parseResult;
    int offset;
    unsigned int instance;
    int result;
    char *idBuffer;
    int *bufferLength;
    extern char *_parsePrefix(const char *prefix, const char *str);
    extern unsigned int _parsenum(char **strPtr);
    extern int _LookForPCMCIAID(unsigned int instance, char *idBuffer, char *output, unsigned int *count);

    /* ID buffer is at offset 0x128 (296), size 0x200 (512 bytes) */
    idBuffer = (char *)self + 0x128;
    /* Buffer length counter at offset 0x328 (808) */
    bufferLength = (int *)((char *)self + 0x328);

    /* Try "IDs" prefix */
    parseResult = _parsePrefix("IDs", parameterName);
    if (parseResult != NULL) {
        /* Clear ID buffer and reset counter */
        bzero(idBuffer, 0x200);
        *bufferLength = 0;

        /* Look for "PCMCIA)" after "IDs" */
        parseResult = _parsePrefix("PCMCIA)", parseResult);
        if (parseResult != NULL) {
            /* Copy ID string from parameter to buffer */
            offset = parseResult - parameterName;
            while (offset < 0x40 &&
                   parameterName[offset] != '\0' &&
                   *bufferLength < 0x1ff) {
                idBuffer[*bufferLength] = parameterName[offset];
                (*bufferLength)++;
                offset++;
            }

            /* Copy buffer to output */
            strncpy((char *)values, idBuffer, *count);
            return 0;  /* Success */
        }
        return 0xfffffd27;  /* Error - no PCMCIA) prefix */
    }

    /* Try "...IDs" prefix (append to existing IDs) */
    parseResult = _parsePrefix("...IDs", parameterName);
    if (parseResult != NULL) {
        /* Check if buffer has existing data */
        if (idBuffer[0] != '\0') {
            /* Append to buffer */
            offset = parseResult - parameterName;
            while (offset < 0x40 &&
                   parameterName[offset] != '\0' &&
                   *bufferLength < 0x1ff) {
                idBuffer[*bufferLength] = parameterName[offset];
                (*bufferLength)++;
                offset++;
            }

            /* Null-terminate */
            idBuffer[*bufferLength] = '\0';

            /* Copy buffer to output */
            strncpy((char *)values, idBuffer, *count);
            return 0;  /* Success */
        }
        return 0xfffffd27;  /* Error - no existing IDs */
    }

    /* Try "LocationForInstance" prefix */
    parseResult = _parsePrefix("LocationForInstance", parameterName);
    if (parseResult != NULL) {
        /* Check minimum buffer size (0x50 = 80 bytes) */
        if (*count < 0x50) {
            return 0xfffffd3e;  /* Error - buffer too small */
        }

        /* Check if ID buffer has data */
        if (idBuffer[0] != '\0') {
            /* Parse instance number */
            instance = _parsenum(&parseResult);

            /* Look up PCMCIA ID for this instance */
            result = _LookForPCMCIAID(instance, idBuffer, (char *)values, count);
            return result;
        }
        return 0xfffffd27;  /* Error - no IDs to search */
    }

    /* Not a PCMCIA parameter - delegate to superclass */
    return [super getCharValues:values forParameter:parameterName count:count];
}

@end
