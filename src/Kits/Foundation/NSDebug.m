/*	NSDebug.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSDebug.h>

/*  NSDebug.h declares the (NSAutoreleasePoolDebugging) category on
    NSAutoreleasePool, which is why the stub generator originally placed
    an @implementation here.  The reference binary's own __OBJC,
    __module_info places these 11 methods in the SAME module as the rest
    of NSAutoreleasePool's class methods, not in a module of their own
    (confirmed by stage 2a's committed abi/NSAutoreleasePool.json, which
    lists all 15 class methods -- including these 11 -- directly under
    the class, with no separate category entry) -- so the real
    implementation belongs, and now lives, in NSAutoreleasePool.m, not
    here.  Removed to avoid two translation units defining the same
    @implementation NSAutoreleasePool selectors (this file's stub bodies
    were a real duplicate-definition hazard once NSAutoreleasePool.m
    implemented them for real; see divergences.md).  */
