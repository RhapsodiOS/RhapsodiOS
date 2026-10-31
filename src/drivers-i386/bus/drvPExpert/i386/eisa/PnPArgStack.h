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
 * PnPArgStack.h
 * Argument marshalling for PnP BIOS calls
 */

#ifndef _PNPARGSTACK_H_
#define _PNPARGSTACK_H_

#import <objc/Object.h>

/*
 * Capacity of the argument stack, in 16-bit words.
 */
#define PNPARGSTACK_DEPTH   20

/*
 * PnPArgStack - builds the 16-bit argument frame for one PnP BIOS call.
 *
 * The PnP BIOS calling convention (PnP BIOS Specification v1.0a) is the
 * ordinary "push the last parameter first" C convention over 16-bit words:
 * BiosSelector goes deepest, the function number goes on top, immediately
 * below the far return address.  Different functions take different numbers
 * of words, so the frame is built here one word at a time rather than
 * being a fixed shape.
 *
 * Words are stored into a fixed 20-word array from the top down.  After
 * every push the two globals the assembler thunk reads,
 * PnPEntry_argStackBase and PnPEntry_numArgs, are updated so they always
 * describe the current contents; _PnPEntry replays exactly those words onto
 * the real stack, and bios_rtn pops exactly that many afterwards.
 */
@interface PnPArgStack : Object
{
@private
    unsigned short  _args[PNPARGSTACK_DEPTH];   /* the frame, filled top down */
    int             _remaining;                 /* free slots; also the index
                                                   of the last word pushed   */
    void           *_dataBase;                  /* base of the buffer that
                                                   pushFarPtr: offsets are
                                                   measured against          */
    unsigned short  _selector;                  /* segment half of every far
                                                   pointer pushed            */
}

- initWithData:(void *)data Selector:(unsigned short)selector;

/*
 * Discard the frame and start a new one.
 */
- reset;

/*
 * Push one 16-bit word.  Overflow is logged and the word dropped.
 */
- push:(unsigned short)value;

/*
 * Push a far pointer into the data buffer as two words: the stored
 * selector, then the pointer's 16-bit offset from the data base.  A
 * pointer more than 64K past the base, or a frame with fewer than two
 * free slots, is logged and dropped.
 */
- pushFarPtr:(void *)pointer;

@end

#endif /* _PNPARGSTACK_H_ */
