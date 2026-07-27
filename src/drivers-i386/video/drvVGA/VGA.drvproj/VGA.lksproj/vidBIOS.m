/* Copyright (c) 1992 by NeXT Computer, Inc.
 * All rights reserved.
 *
 * vidBIOS.m -- the real-mode VGA BIOS call class.
 *
 * vidBIOS wraps _emu486 (emu486.s), the hand-written 8086 emulator that
 * runs int10 BIOS calls on its behalf.  This is a scaffolding stub: Task 6
 * of Phase 3b adds the instance data and method bodies.
 */

#import <objc/Object.h>
#import "IOVGADisplayPrivate.h"

@interface vidBIOS : Object
@end

@implementation vidBIOS
@end
