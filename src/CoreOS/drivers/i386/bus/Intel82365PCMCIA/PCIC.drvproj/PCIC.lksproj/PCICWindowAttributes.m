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
 * PCICWindow Attributes Category Implementation
 */

#import "PCICWindow.h"

@implementation PCICWindow(Attributes)

/*
 * Get number of address lines decoded
 */
- (int)addressLinesDecoded
{
    return 0x10;
}

/*
 * Get base address alignment requirement
 */
- (int)baseAlignment
{
    return 0x1000;
}

/*
 * Check if 16-bit mode is supported
 */
- (char)canUse16Bit
{
    return 1;
}

/*
 * Check if 8-bit mode is supported
 */
- (char)canUse8Bit
{
    return 1;
}

/*
 * Get fastest access speed
 */
- (int)fastestSpeed
{
    return 0;
}

/*
 * Get first valid system address
 */
- (unsigned int)firstSystemAddress
{
    return 0x10000;
}

/*
 * Get last valid system address
 */
- (unsigned int)lastSystemAddress
{
    return 0xffffff;
}

/*
 * Get maximum window size
 */
- (int)maximumSize
{
    return 0x1000000;
}

/*
 * Get minimum window size
 */
- (int)minimumSize
{
    return 0x1000;
}

/*
 * Check if size must be power of two
 */
- (char)mustBePowerOfTwo
{
    return 0;
}

/*
 * Get offset alignment requirement
 */
- (int)offsetAlignment
{
    return 0x1000;
}

/*
 * Get size alignment requirement
 */
- (int)sizeAlignment
{
    return 0x1000;
}

/*
 * Get slowest access speed
 */
- (int)slowestSpeed
{
    return 0;
}

/*
 * Check if I/O windows are supported
 */
- (char)supportsIO
{
    return memoryWindow == 0;
}

/*
 * Check if memory windows are supported
 */
- (char)supportsMemory
{
    return memoryWindow;
}

/*
 * Check if write protection is supported
 */
- (char)writeProtectable
{
    return 1;
}

@end
