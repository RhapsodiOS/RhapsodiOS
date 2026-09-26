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
#import <driverkit/KernBus.h>

/* Forward declaration for a private PCMCIAKernBus method used by LookForPCMCIAID */
@interface Object(PCMCIAKernBusTestIDsMethod)
- (BOOL)testIDs:idList ForAdapter:adapter andSocket:socket;
@end

/*
 * Check whether str begins with prefix followed immediately by '('
 * Returns a pointer just past the '(' on a match, NULL otherwise
 */
char *parsePrefix(const char *prefix, const char *str)
{
    unsigned int length;

    if (prefix == NULL || str == NULL) {
        return NULL;
    }

    length = strlen(prefix);

    if (strncmp(prefix, str, length) != 0) {
        return NULL;
    }

    if (str[length] != '(') {
        return NULL;
    }

    return (char *)(str + length + 1);
}

/*
 * Parse a leading run of decimal digits from *strPtr, advancing *strPtr
 * past the digits consumed. Returns the accumulated value (0 if none).
 */
unsigned int parsenum(char **strPtr)
{
    char *p;
    unsigned int value;

    value = 0;
    p = *strPtr;

    if (*p != '\0') {
        do {
            if ((unsigned char)(*p - '0') > 9) {
                break;
            }
            value = value * 10 + (*p - '0');
            (*strPtr)++;
            p = *strPtr;
        } while (*p != '\0');
    }

    return value;
}

/*
 * Find the instance-th PCMCIA socket (0-3) whose card ID matches idBuffer,
 * and format its socket number as "Socket %d" into output. On success,
 * *count is set to the formatted string's length (including the null
 * terminator) and 0 is returned. On failure, *count is set to 0 and
 * IO_R_NOT_ATTACHED (0xfffffd27) is returned.
 */
int LookForPCMCIAID(unsigned int instance, char *idBuffer, char *output, unsigned int *count)
{
    id busInstance;
    unsigned int socketNum;
    unsigned int matchCount;
    BOOL matched;

    busInstance = [KernBus lookupBusInstanceWithName:"PCMCIA" busId:0];

    matchCount = 0;
    for (socketNum = 0; socketNum <= 3; socketNum++) {
        matched = [busInstance testIDs:idBuffer ForAdapter:0 andSocket:socketNum];
        if (matched) {
            if (instance == matchCount) {
                sprintf(output, "Socket %d", socketNum);
                *count = strlen(output) + 1;
                return 0;
            }
            matchCount++;
        }
    }

    *count = 0;
    return 0xfffffd27;  /* IO_R_NOT_ATTACHED */
}

@implementation PCMCIAResourceDriver

/*
 * Class method to probe and create resource driver
 */
+ (BOOL)probe:deviceDesc
{
    id instance;

    /* Allocate and initialize resource driver.  The reference registers the
     * device from initFromDeviceDescription:, not from here; sending
     * registerDevice again at this point registers PCMCIA0 a second time.
     */
    instance = [[PCMCIAResourceDriver alloc] initFromDeviceDescription:deviceDesc];

    if (instance == nil) {
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
    extern char *parsePrefix(const char *prefix, const char *str);
    extern unsigned int parsenum(char **strPtr);
    extern int LookForPCMCIAID(unsigned int instance, char *idBuffer, char *output, unsigned int *count);

    idBuffer = autoDetectIDs;
    bufferLength = &autoDetectIDindex;

    /* Try "IDs" prefix */
    parseResult = parsePrefix("IDs", parameterName);
    if (parseResult != NULL) {
        /* Clear ID buffer and reset counter */
        bzero(idBuffer, 0x200);
        *bufferLength = 0;

        /* Look for "PCMCIA)" after "IDs" */
        parseResult = parsePrefix("PCMCIA)", parseResult);
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
    parseResult = parsePrefix("...IDs", parameterName);
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
    parseResult = parsePrefix("LocationForInstance", parameterName);
    if (parseResult != NULL) {
        /* Check minimum buffer size (0x50 = 80 bytes) */
        if (*count < 0x50) {
            return 0xfffffd3e;  /* Error - buffer too small */
        }

        /* Check if ID buffer has data */
        if (idBuffer[0] != '\0') {
            /* Parse instance number */
            instance = parsenum(&parseResult);

            /* Look up PCMCIA ID for this instance */
            result = LookForPCMCIAID(instance, idBuffer, (char *)values, count);
            return result;
        }
        return 0xfffffd27;  /* Error - no IDs to search */
    }

    /* Not a PCMCIA parameter - delegate to superclass */
    return [super getCharValues:values forParameter:parameterName count:count];
}

@end
