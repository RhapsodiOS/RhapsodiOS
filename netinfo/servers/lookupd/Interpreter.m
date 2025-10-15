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
	Interpreter.m

	String-query interpreter for lookupd

	Copyright (c) 1995, NeXT Computer Inc.
	All rights reserved.
	Written by Marc Majka
 */

#import "Interpreter.h"
#import "LUPrivate.h"
#import "LUCachedDictionary.h"
#import "Controller.h"
#import "LUServer.h"
#import <arpa/inet.h>
#import <string.h>
#import <stdlib.h>
#import <stdio.h>

#if NS_TARGET_MAJOR == 3
#import <foundation/NSValue.h>
#else
#import <Foundation/NSValue.h>
#endif

extern struct ether_addr *ether_aton(char *);

@implementation Interpreter

- (NSDictionary *)convertDict:(LUDictionary *)dict
{
	NSMutableDictionary *res;
	NSMutableArray *vals;
	int i, len, j, n;
	char **p;
	char str[256];
	LUAgent *agent;
	LUCategory cat;
	char *k;

	if (dict == nil) return nil;

	len = [dict count];
	res = [NSMutableDictionary dictionaryWithCapacity:len];

	for (i = 0; i < len; i++)
	{
		n = [dict countAtIndex:i];
		vals = [NSMutableArray arrayWithCapacity:n];			
		p = [dict valuesAtIndex:i];
		k = [dict keyAtIndex:i];
		if (!strncmp(k, "_lookup_", 8))
		{
			[res setObject:[NSString stringWithCString:[dict valueAtIndex:i]]
				forKey:[NSString stringWithCString:k]];
		}
		else
		{
			for (j = 0; j < n; j++)
				[vals addObject:[NSString stringWithCString:p[j]]];
			[res setObject:vals forKey:[NSString stringWithCString:k]];
		}
	}

	cat = [dict category];
	agent = [dict agent];
	if (agent == nil)
	{
		if (cat < NCATEGORIES)
		{
			sprintf(str, "%u", (unsigned int)cat);
			[res setObject:[NSString stringWithCString:str]
				forKey:[NSString stringWithCString:"_lookup_category"]];
		}
	}
	else
	{
		if (cat < NCATEGORIES)
		{
			[res setObject:
				[NSString stringWithCString:[agent categoryName:cat]]
				forKey:[NSString stringWithCString:"_lookup_category"]];
		}
		else 
		{
			sprintf(str, "%u", (unsigned int)cat);
			[res setObject:[NSString stringWithCString:str]
				forKey:[NSString stringWithCString:"_lookup_category"]];
		}

		[res setObject:[NSNumber numberWithUnsignedInt:[dict timeToLive]]
				forKey:[NSString stringWithCString:"_lookup_time_to_live"]];

		[res setObject:[NSNumber numberWithUnsignedInt:[dict cacheHits]]
				forKey:[NSString stringWithCString:"_lookup_cache_hits"]];
	}

	return res;
}

- (NSArray *)convertArray:(LUArray *)array
{
	NSMutableArray *res;
	NSDictionary *dict;
	int i, len;

	if (array == nil) return nil;
	len = [array count];
	res = [NSMutableArray arrayWithCapacity:len];
	for (i = 0; i < len; i++)
	{
		dict = [self convertDict:[array objectAtIndex:i]];
		if (dict != nil) [res addObject:dict];
	}

	return res;
}

- (NSDictionary *)itemWithName:(NSArray *)args method:(SEL)sel
{
	LUDictionary *dict;
	NSDictionary *result;
	LUServer *s;

	if (args == nil) return nil;
	if ([args count] < 1) return nil;

	s = [controller checkOutServer];

#if NS_TARGET_MAJOR == 3
	dict = [s perform:sel withObject:(void *)[[args objectAtIndex:0] cString]];
#else
	dict = [s performSelector:sel
		withObject:(void *)[[args objectAtIndex:0] cString]];
#endif

	[controller checkInServer:s];

	result = [self convertDict:dict];
	[dict release];
	return result;
}

- (NSDictionary *)itemWithNumber:(NSArray *)args method:(SEL)sel
{
	LUDictionary *dict;
	NSDictionary *result;
	LUServer *s;
	int num;

	if (args == nil) return nil;
	if ([args count] < 1) return nil;
	num = atoi([[args objectAtIndex:0] cString]);

	s = [controller checkOutServer];

#if NS_TARGET_MAJOR == 3
	dict = [s perform:sel withObject:(void *)&num];
#else
	dict = [s performSelector:sel withObject:(void *)&num];
#endif

	[controller checkInServer:s];

	result = [self convertDict:dict];
	[dict release];
	return result;
}

- (NSDictionary *)itemWithInternetAddress:(NSArray *)args method:(SEL)sel
{
	LUDictionary *dict;
	NSDictionary *result;
	LUServer *s;
	struct in_addr ip;

	if (args == nil) return nil;
	if ([args count] < 1) return nil;
	ip.s_addr = inet_addr((char *)[[args objectAtIndex:0] cString]);

	s = [controller checkOutServer];

#if NS_TARGET_MAJOR == 3
	dict = [s perform:sel withObject:(id)&ip];
#else
	dict = [s performSelector:sel withObject:(id)&ip];
#endif

	[controller checkInServer:s];

	result = [self convertDict:dict];
	[dict release];
	return result;
}

- (NSDictionary *)itemWithNetworkAddress:(NSArray *)args method:(SEL)sel
{
	LUDictionary *dict;
	NSDictionary *result;
	LUServer *s;
	struct in_addr ip;

	if (args == nil) return nil;
	if ([args count] < 1) return nil;
	ip.s_addr = inet_network((char *)[[args objectAtIndex:0] cString]);

	s = [controller checkOutServer];

#if NS_TARGET_MAJOR == 3
	dict = [s perform:sel withObject:(id)&ip];
#else
	dict = [s performSelector:sel withObject:(id)&ip];
#endif

	[controller checkInServer:s];

	result = [self convertDict:dict];
	[dict release];
	return result;
}

- (NSDictionary *)itemWithEthernetAddress:(NSArray *)args method:(SEL)sel
{
	LUDictionary *dict;
	NSDictionary *result;
	LUServer *s;
	struct ether_addr *ep, ether;

	if (args == nil) return nil;
	if ([args count] < 1) return nil;
	ep = ether_aton((char *)[[args objectAtIndex:0] cString]);
	bcopy((char *)ep, (char *)&ether, sizeof(struct ether_addr));

	s = [controller checkOutServer];

#if NS_TARGET_MAJOR == 3
	dict = [s perform:sel withObject:(id)&ether];
#else
	dict = [s performSelector:sel withObject:(id)&ether];
#endif

	[controller checkInServer:s];

	result = [self convertDict:dict];
	[dict release];
	return result;
}

- (NSArray *)allItems:(SEL)sel
{
	LUArray *array;
	NSArray *result;
	LUServer *s;

	s = [controller checkOutServer];

#if NS_TARGET_MAJOR == 3
	array = [s perform:sel];
#else
	array = [s performSelector:sel];
#endif

	[controller checkInServer:s];

	result = [self convertArray:array];
	[array release];
	return result;
}

- (NSDictionary *)serviceWithName:(NSArray *)args
{
	LUDictionary *dict;
	NSDictionary *result;
	LUServer *s;
	char *prot = NULL;

	if (args == nil) return nil;
	if ([args count] < 1) return nil;
	if ([args count] > 1) prot = (char *)[[args objectAtIndex:1] cString];

	s = [controller checkOutServer];
	dict = [s serviceWithName:(char *)[[args objectAtIndex:0] cString]
		protocol:prot];
	[controller checkInServer:s];

	result = [self convertDict:dict];
	[dict release];
	return result;
}

- (NSDictionary *)serviceWithNumber:(NSArray *)args
{
	LUDictionary *dict;
	NSDictionary *result;
	LUServer *s;
	char *prot = NULL;
	int num;

	if (args == nil) return nil;
	if ([args count] < 1) return nil;
	if ([args count] > 1) prot = (char *)[[args objectAtIndex:1] cString];
	num = atoi([[args objectAtIndex:0] cString]);

	s = [controller checkOutServer];
	dict = [s serviceWithNumber:&num protocol:prot];
	[controller checkInServer:s];

	result = [self convertDict:dict];
	[dict release];
	return result;
}

- (NSNumber *)inNetgroup:(NSArray *)args
{
	NSNumber *result;
	BOOL yn = NO;
	LUServer *s;
	char *group;
	char *host = NULL;
	char *user = NULL;
	char *domain = NULL;

	if (args == nil) return nil;
	if ([args count] < 1) return nil;
	group = (char *)[[args objectAtIndex:0] cString];
	if ([args count] > 1)
	{
		if (strcmp([[args objectAtIndex:1] cString], "-"))
			host = (char *)[[args objectAtIndex:1] cString];
	}
	if ([args count] > 2)
	{
		if (strcmp([[args objectAtIndex:1] cString], "-"))
			user = (char *)[[args objectAtIndex:1] cString];
	}
	if ([args count] > 3)
	{
		if (strcmp([[args objectAtIndex:1] cString], "-"))
			domain = (char *)[[args objectAtIndex:1] cString];
	}

	s = [controller checkOutServer];
	yn = [s inNetgroup:group host:host user:user domain:domain];
	[controller checkInServer:s];
	result = [NSNumber numberWithBool:yn];
	return result;
}

- (NSArray *)allGroupsWithUser:(NSArray *)args
{
	LUArray *array;
	NSArray *result;
	LUServer *s;

	if (args == nil) return nil;
	if ([args count] < 1) return nil;

	s = [controller checkOutServer];
	array = [s allGroupsWithUser:(char *)[[args objectAtIndex:0] cString]];
	[controller checkInServer:s];

	result = [self convertArray:array];
	[array release];
	return result;
}

- (id)lookup:(NSString *)query with:(NSArray *)args
{
	char *qs;

	qs = (char *)[query cString];

	if (query == nil) return nil;

	else if (!strcmp(qs, "userWithName"))
		return [self itemWithName:args method:@selector(userWithName:)];

	else if (!strcmp(qs, "userWithNumber"))
		return [self itemWithNumber:args method:@selector(userWithNumber:)];

	else if (!strcmp(qs, "allUsers"))
		return [self allItems:@selector(allUsers)];

	else if (!strcmp(qs, "groupWithName"))
		return [self itemWithName:args method:@selector(groupWithName:)];

	else if (!strcmp(qs, "groupWithNumber"))
		return [self itemWithNumber:args method:@selector(groupWithName:)];

	else if (!strcmp(qs, "allGroups"))
		return [self allItems:@selector(allGroups)];

	else if (!strcmp(qs, "hostWithName"))
		return [self itemWithName:args method:@selector(hostWithName:)];

	else if (!strcmp(qs, "hostWithInternetAddress"))
		return [self itemWithInternetAddress:args
			method:@selector(hostWithInternetAddress:)];

	else if (!strcmp(qs, "hostWithEthernetAddress"))
		return [self itemWithEthernetAddress:args
			method:@selector(hostWithEthernetAddress:)];

	else if (!strcmp(qs, "allHosts"))
		return [self allItems:@selector(allHosts)];

	else if (!strcmp(qs, "networkWithName"))
		return [self itemWithName:args method:@selector(networkWithName:)];

	else if (!strcmp(qs, "networkWithInternetAddress"))
		return [self itemWithNetworkAddress:args
			method:@selector(hostWithNetworkAddress:)];

	else if (!strcmp(qs, "allNetworks"))
		return [self allItems:@selector(allNetworks)];

	else if (!strcmp(qs, "serviceWithName"))
		return [self serviceWithName:args];

	else if (!strcmp(qs, "serviceWithNumber"))
		return [self serviceWithNumber:args];

	else if (!strcmp(qs, "allServices"))
		return [self allItems:@selector(allServices)];

	else if (!strcmp(qs, "protocolWithName"))
		return [self itemWithName:args method:@selector(protocolWithName:)];

	else if (!strcmp(qs, "protocolWithNumber"))
		return [self itemWithNumber:args
			method:@selector(protocolWithNumber:)];

	else if (!strcmp(qs, "allProtocols"))
		return [self allItems:@selector(allProtocols)];

	else if (!strcmp(qs, "rpcWithName"))
		return [self itemWithName:args method:@selector(rpcWithName:)];

	else if (!strcmp(qs, "rpcWithNumber"))
		return [self itemWithNumber:args method:@selector(rpcWithNumber:)];

	else if (!strcmp(qs, "allRpcs"))
		return [self allItems:@selector(allRpcs)];

	else if (!strcmp(qs, "mountWithName"))
		return [self itemWithName:args method:@selector(mountWithName:)];

	else if (!strcmp(qs, "allMounts"))
		return [self allItems:@selector(allMounts)];

	else if (!strcmp(qs, "printerWithName"))
		return [self itemWithName:args method:@selector(printerWithName:)];

	else if (!strcmp(qs, "allPrinters"))
		return [self allItems:@selector(allPrinters)];

	else if (!strcmp(qs, "bootparamsWithName"))
		return [self itemWithName:args method:@selector(bootparamsWithName:)];

	else if (!strcmp(qs, "allBootparams"))
		return [self allItems:@selector(allBootparams)];

	else if (!strcmp(qs, "bootpWithInternetAddress"))
		return [self itemWithNetworkAddress:args
			method:@selector(bootpWithInternetAddress:)];

	else if (!strcmp(qs, "bootpWithEthernetAddress"))
		return [self itemWithEthernetAddress:args
			method:@selector(bootpWithEthernetAddress:)];

	else if (!strcmp(qs, "aliasWithName"))
		return [self itemWithName:args method:@selector(aliasWithName:)];

	else if (!strcmp(qs, "allAliases"))
		return [self allItems:@selector(allAliases)];

	else if (!strcmp(qs, "netgroupWithName"))
		return [self itemWithName:args method:@selector(netgroupWithName:)];

	else if (!strcmp(qs, "allNetgroups"))
		return [self allItems:@selector(allNetgroups)];

	else if (!strcmp(qs, "inNetgroup"))
		return [self inNetgroup:args];

	else if (!strcmp(qs, "allGroupsWithUser"))
		return [self allGroupsWithUser:args];

	return nil;
}

@end
