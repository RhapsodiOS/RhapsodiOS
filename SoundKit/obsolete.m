/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * "Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.0 (the 'License').  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License."
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
/*
    obsolete.m

    Pieces of code that we keep for compatibility, but will be obsolete in 4.0.
    
    Shamelessly lifted from obsolete.m in AppKit's DPSClient.subproj, with
    names changed as appropriate.

    Copyright (c) 1994-1996, NeXT Software, Inc.
    All rights reserved.
*/

#ifdef SHLIB
#import "shlib.h"
#endif SHLIB

#import "obsolete.h"
// #import "NSDPSContext.h"
// #import "NSDPSContextPrivate.h"
#import <stdarg.h>
#import <stdio.h>
#import <string.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSPort.h>
#import <Foundation/NSDate.h>
#import <AppKit/NSApplication.h>


/* private class used in implementing _NSSKAddPort */
@interface _NSSKPortDelegate : NSObject {
@public		/* ivars are public for dirt simple use */
    _NSSKPortProc handler;
    void *userData;
    int priority;
}
@end
@implementation _NSSKPortDelegate
- (void)handleMachMessage:(void *)msg {
    (handler)(msg, userData);
}
@end

void _NSSKAddPort(port_t newPort, _NSSKPortProc handler, int maxSize, void *userData, int priority) {
    NSPort *port = [[NSPort portWithMachPort:newPort] retain];
    _NSSKPortDelegate *portDel = [[_NSSKPortDelegate alloc] init];

    portDel->handler = handler;
    portDel->userData = userData;
    portDel->priority = priority;
    [port setDelegate:portDel];
    [[NSRunLoop currentRunLoop] addPort:port forMode:NSDefaultRunLoopMode];
    if (priority >= 5) {
	[[NSRunLoop currentRunLoop] addPort:port
	    forMode:NSModalPanelRunLoopMode];
	if (priority >= 10) {
	    [[NSRunLoop currentRunLoop] addPort:port forMode:NSEventTrackingRunLoopMode];
	}
    }
}

void _NSSKRemovePort(port_t machPort) {
  /* gives us the same object we got when port was added */
    NSPort *port = [NSPort portWithMachPort:machPort];
    _NSSKPortDelegate *portDel = [port delegate];
    int priority = portDel->priority;
    [port setDelegate:nil];
    [portDel release];
    [[NSRunLoop currentRunLoop] removePort:port forMode:NSDefaultRunLoopMode];
    if (priority >= 5) {
	[[NSRunLoop currentRunLoop] removePort:port
	    forMode:NSModalPanelRunLoopMode];
	if (priority >= 10) {
	    [[NSRunLoop currentRunLoop] removePort:port forMode:NSEventTrackingRunLoopMode];
	}
    }

/* The port object can NOT be released because this would dealloc the port we are passed.  There wasn't a good way to add a sensible port method to fix this. */
/*    [port release];	matches the release in AddPort */
}



/* private class used in implementing _NSSKAddTimedEntry */
@interface _NSSKTEDelegate : NSObject {
@public		/* ivars are public for dirt simple use */
    _NSSKTimedEntryProc handler;
    void *userData;
    int priority;
    NSTimer *timer;
}
@end
@implementation _NSSKTEDelegate
- (void)fire:(NSTimer *)t {
    (handler)((_NSSKTimedEntry)self, [NSDate timeIntervalSinceReferenceDate], userData);
}
@end

_NSSKTimedEntry _NSSKAddTimedEntry(double period, _NSSKTimedEntryProc handler, void *userData, int priority) {
    _NSSKTEDelegate *timerDel = [[_NSSKTEDelegate alloc] init];
    NSTimer *timer = [NSTimer timerWithTimeInterval:period target:timerDel selector:@selector(fire:) userInfo:nil repeats:YES];

    timerDel->handler = handler;
    timerDel->userData = userData;
    timerDel->priority = priority;
    timerDel->timer = [timer retain];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
    if (priority >= 5) {
	[[NSRunLoop currentRunLoop] addTimer:timer
	    forMode:NSModalPanelRunLoopMode];
	if (priority >= 10) {
	    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSEventTrackingRunLoopMode];
	}
    }
    return (_NSSKTimedEntry)timerDel;
}

void _NSSKRemoveTimedEntry(_NSSKTimedEntry te) {
    _NSSKTEDelegate *timerDel = (_NSSKTEDelegate *)te;
    [timerDel->timer invalidate];
    [timerDel->timer release];
    [timerDel release];
}

