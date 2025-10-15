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
	LookupDaemon.m

	Distributed Objects interface for lookupd

	Copyright (c) 1995, NeXT Computer Inc.
	All rights reserved.
	Written by Marc Majka
 */

#import "LookupDaemon.h"
#import "Interpreter.h"
#import "LUServer.h"
#import "LUPrivate.h"
#import "Controller.h"
#import "LUGlobal.h"
#import "stringops.h"
#import <stdlib.h>
#import <stdio.h>

#if NS_TARGET_MAJOR == 3
#import <foundation/NSThread.h>
#import <remote/NXConnection.h>
#else
#import <Foundation/NSThread.h>
#import <Foundation/NSConnection.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSRunLoop.h>
#endif

@implementation LookupDaemon

- server:(id)sender
{
#if NS_TARGET_MAJOR == 3
	NXConnection *connection;

	connection = [NXConnection registerRoot:self withName:doServerName];
	[connection run];
#else
	NSConnection *connection;
	/* XXX Bug in NSThread - I shouldn't need to make my own pool */
	NSAutoreleasePool *sewer;

	sewer = [[NSAutoreleasePool alloc] init];
	connection = [NSConnection defaultConnection];
	[connection setRootObject:self];
	[connection registerName:[NSString stringWithCString:doServerName]];
	[[NSRunLoop currentRunLoop] run];
	[sewer release];
#endif
	return self;
}

- (id)initWithName:(const char *)name
{
	[super init];

	interpreter = [[Interpreter alloc] init];

	if (name == NULL)
	{
		doServerName = malloc(strlen(DefaultName) + strlen(DOSuffix));
		sprintf(doServerName, "%s%s", DefaultName, DOSuffix);
	}
	else doServerName = copyString((char *)name);

	[NSThread detachNewThreadSelector:@selector(server:) toTarget:self
		withObject:self];
	return self;
}

- (void)dealloc
{
	if (doServerName != NULL) freeString(doServerName);
	doServerName = NULL;
	if (interpreter != nil) [interpreter release];
	[super dealloc];
}

- (id)lookup:(NSString *)query with:(NSArray *)args
{
	return [interpreter lookup:query with:args];
}

- (void)flushCache
{
	[controller flushCache];
}

- (NSArray *)lookupStatistics
{
	LUArray *all;
	NSArray *res;

	all = [controller allStatistics];
	res = [interpreter convertArray:all];
	[all release];
	return res;
}

- (id)ping
{
	return self;
}

@end
