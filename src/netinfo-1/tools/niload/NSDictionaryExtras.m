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
#import "NSDictionaryExtras.h"
#if NS_TARGET_MAJOR == 3
#import <foundation/NSString.h>
#import <foundation/NSArray.h>
#import <foundation/NSUtilities.h>
#else
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSUtilities.h>
#endif

#import <stdlib.h>
#import "nilib2.h"

@implementation NSDictionary (NSDictionaryExtras)

- (ni_proplist *)niProplist
{
	id keyEnum;
	id valEnum;
	NSString *propKey;
	NSArray *props;
	int i, len;
	ni_proplist *pl;
	char *key;

	pl = (ni_proplist *)malloc(sizeof(ni_proplist));
	NI_INIT(pl);

	keyEnum = [self keyEnumerator];
	valEnum = [self objectEnumerator];
	while ((propKey = [keyEnum nextObject])) {
		props = [valEnum nextObject];
		key = (char *)[propKey cString];
		nipl_createprop(pl, key);

		len = [props count];
		for (i = 0; i < len; i++) {
			nipl_appendprop(pl, key,
				(char *)[[props objectAtIndex:i] cString]);
		}
	}

	return pl;
}

@end
