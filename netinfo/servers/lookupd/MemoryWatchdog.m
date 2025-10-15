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
#import "MemoryWatchdog.h"
#import <string.h>

@implementation MemoryWatchdog

- (id)init
{
	listLock = [[NSRecursiveLock alloc] init];
	list = [[LUArray alloc] init];
	rover = self;
	cacheAgent = [[CacheAgent alloc] init];
	stats = nil;

	return self;
}

- (void)dealloc
{
	[list release];
	[listLock release];
	[super dealloc];
}

- (void)checkObjects
{
	[self checkObjects:stdout];
}

- (void)checkObjects:(FILE *)f
{
	int i, len;
	id obj;

	[listLock lock];
	len = [list count];

	fprintf(f, "%d objects in memory\n\n", len);
	for (i = 0; i < len; i++)
	{
		obj = [list objectAtIndex:i];

		fprintf(f, "%5d %d %s 0x%6x %s",
			i, [obj retainCount] - 1,
			([cacheAgent containsObject:obj] ? "*" : " "),
			(unsigned int)obj, [obj banner]);
		fprintf(f, "\n");

	}
	[listLock unlock];
}

- (void)printObject:(int)where file:(FILE *)f
{
	[listLock lock];
	if (where >= [list count])
	{
		[listLock unlock];
		return;
	}

	[[list objectAtIndex:where] print:f];
	[listLock unlock];
}

- (LUDictionary *)statistics
{
	int i, len;
	id obj;
	char key[64], str[256];

	if (stats != nil) [stats release];

	stats = [[LUDictionary  alloc] init];
	[stats setBanner:"Memory Statistics"];

	[listLock lock];
	len = [list count];

	for (i = 0; i < len; i++)
	{
		obj = [list objectAtIndex:i];

		sprintf(key, "0x%x", (unsigned int)obj);
		sprintf(str, "%d %s %s",
			[obj retainCount] - 1,
			([cacheAgent containsObject:obj] ? "*" : " "),
			[obj banner]);

		[stats setValue:str forKey:key];
	}
	[listLock unlock];

	return stats;
}

- (void)addObject:(id)anObject
{
	[listLock lock];
	[list addObject:anObject];
	[listLock unlock];
}

- (void)removeObject:(id)anObject;
{
	[listLock lock];
	[list removeObject:anObject];
	[listLock unlock];
}

@end
