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
 * PCMCIA Card ID
 */

#ifndef _DRIVERKIT_I386_PCMCIAID_H_
#define _DRIVERKIT_I386_PCMCIAID_H_

#import <objc/Object.h>

#ifdef DRIVER_PRIVATE

@interface PCMCIAid : Object
{
@private
    char *_function;      /* PCMCIA_TPLFID_FUNCTION */
    char *_manufacturer;  /* PCMCIA_TPLMID_MANF */
    char *_product;       /* PCMCIA_TPLMID_CARD */
    char *_version1;      /* PCMCIA_TPLVERS_1 */
    char *_version2;      /* PCMCIA_TPLVERS_2 */
}

- initFromDescription:description;
- initFromIDString:(char **)idStringPtr;
- free;

/* Matching */
- (BOOL)matchesID:otherID;

/* Logging */
- (void)IOLog;

/* Class method for logging card information from device description */
+ (void)IOLogCardInformation:deviceDesc;

@end

#endif /* DRIVER_PRIVATE */

#endif /* _DRIVERKIT_I386_PCMCIAID_H_ */
