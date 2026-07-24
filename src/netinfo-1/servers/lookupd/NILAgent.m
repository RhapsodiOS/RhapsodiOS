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
	NILAgent.m

	DNS lookup agent for lookupd

	Copyright (c) 1996, NeXT Software Inc.
	All rights reserved.
	Written by Marc Majka
 */

#import "NILAgent.h"
#import "LUPrivate.h"
#import "Syslog.h"
#import "Controller.h"
#import <time.h>
#import <arpa/inet.h>

#define DefaultTimeToLive 60

extern char *nettoa(unsigned long);

static NILAgent *_sharedNILAgent = nil;

@implementation NILAgent

- (NILAgent *)init
{
	LUDictionary *config;

	if (didInit) return self;

	[super init];

	timeToLive = DefaultTimeToLive;
	config = [controller configurationForAgent:"NILAgent"];
	if (config != nil)
	{
		if ([config valueForKey:"TimeToLive"] != NULL)
			timeToLive = [config unsignedLongForKey:"TimeToLive"];
			[config release];
	}

	stats = [[LUDictionary alloc] init];
	[stats setBanner:"NILAgent statistics"];
	[stats setValue:"Negative_Records" forKey:"information_system"];

	return self;
}

+ (NILAgent *)alloc
{
	char str[128];

	if (_sharedNILAgent != nil)
	{
		[_sharedNILAgent retain];
		return _sharedNILAgent;
	}

	_sharedNILAgent = [super alloc];
	_sharedNILAgent = [_sharedNILAgent init];
	if (_sharedNILAgent == nil) return nil;

	sprintf(str, "Allocated NILAgent 0x%x\n", (int)_sharedNILAgent);
	[lookupLog syslogDebug:str];

	return _sharedNILAgent;
}

- (const char *)name
{
	return "Negative_Records";
}

- (const char *)shortName
{
	return "NILAgent";
}

- (void)dealloc
{
	char str[128];

	if (stats != nil) [stats release];

	sprintf(str, "Deallocated NILAgent 0x%x\n", (int)self);
	[lookupLog syslogDebug:str];

	[super dealloc];

	_sharedNILAgent = nil;
}

- (LUDictionary *)statistics
{
	return stats;
}

- (void)resetStatistics
{
	if (stats != nil) [stats release];
	stats = [[LUDictionary alloc] init];
	[stats setBanner:"NILAgent statistics"];
	[stats setValue:"Negative_Records" forKey:"information_system"];
}

- (BOOL)isValid:(LUDictionary *)item
{
	time_t now, ttl;
	time_t bestBefore;

	if (item == nil) return NO;

	bestBefore = [item unsignedLongForKey:"_lookup_NIL_timestamp"];
	ttl = [item unsignedLongForKey:"_lookup_NIL_time_to_live"];
	bestBefore += ttl;

	now = time(0);
	if (now > bestBefore) return NO;
	return YES;
}

- (LUDictionary *)stamp:(LUDictionary *)item
{
	time_t now;
	char scratch[32];

	[item setNegative:YES];

	now = time(0);
	sprintf(scratch, "%lu", now);
	[item setValue:scratch forKey:"_lookup_NIL_timestamp"];

	[item setValue:"60" forKey:"_lookup_NIL_time_to_live"];

	[item setAgent:self];
	[item setValue:"NIL" forKey:"_lookup_info_system"];
	return item;
}

- (LUDictionary *)itemWithKey:(char *)key value:(char *)val
{
	LUDictionary *item;

	item = [[LUDictionary alloc] init];
	[item setValue:val forKey:key];
	return [self stamp:item];
}

- (LUDictionary *)itemWithKey:(char *)key intValue:(int)val
{
	LUDictionary *item;
	char str[64];

	sprintf(str, "%d", val);
	item = [[LUDictionary alloc] init];
	[item setValue:str forKey:key];
	return [self stamp:item];
}

- (LUDictionary *)itemWithInternetNetworkAddress:(struct in_addr *)addr
{
	char str[32];

	sprintf(str, "%s", nettoa(addr->s_addr));
	return [self itemWithKey:"address" value:str];
}

- (LUDictionary *)itemWithInternetAddress:(struct in_addr *)addr
{
	char str[32];

	sprintf(str, "%s", inet_ntoa(*addr));
	return [self itemWithKey:"ip_address" value:str];
}

/* LUAgent API Starts here */

- (LUDictionary *)userWithName:(char *)name
{
	return [self itemWithKey:"name" value:name];
}

- (LUDictionary *)userWithNumber:(int *)number
{
	return [self itemWithKey:"uid" intValue:*number];
}

- (LUArray *)allUsers
{
	return nil;
}

- (LUDictionary *)groupWithName:(char *)name
{
	return [self itemWithKey:"name" value:name];
}

- (LUDictionary *)groupWithNumber:(int *)number
{
	return [self itemWithKey:"gid" intValue:*number];
}

- (LUArray *)allGroups
{
	return nil;
}

- (LUArray *)allGroupsWithUser:(char *)name
{
	return nil;
}

- (LUDictionary *)hostWithName:(char *)name
{
	return [self itemWithKey:"name" value:name];
}

- (LUDictionary *)hostWithInternetAddress:(struct in_addr *)addr
{
	return [self itemWithInternetAddress:addr];
}

- (LUDictionary *)hostWithEthernetAddress:(struct ether_addr *)addr
{
	return [self itemWithKey:"en_address"
		value:[self canonicalEthernetAddress:addr]];
}

- (LUArray *)allHosts
{
	return nil;
}

- (LUDictionary *)networkWithName:(char *)name
{
	return [self itemWithKey:"name" value:name];
}

- (LUDictionary *)networkWithInternetAddress:(struct in_addr *)addr
{
	return [self itemWithInternetNetworkAddress:addr];
}

- (LUArray *)allNetworks
{
	return nil;
}

- (LUDictionary *)serviceWithName:(char *)name
	protocol:(char *)prot
{
	LUDictionary *service;

	service = [self itemWithKey:"name" value:name];
	if (prot != NULL) [service setValue:prot forKey:"protocol"];
	return service;
}

- (LUDictionary *)serviceWithNumber:(int *)number
	protocol:(char *)prot
{
	LUDictionary *service;

	service = [self itemWithKey:"name" intValue:*number];
	if (prot != NULL) [service setValue:prot forKey:"protocol"];
	return service;
}

- (LUArray *)allServices
{
	return nil;
}

- (LUDictionary *)protocolWithName:(char *)name
{
	return [self itemWithKey:"name" value:name];
}

- (LUDictionary *)protocolWithNumber:(int *)number
{
	return [self itemWithKey:"number" intValue:*number];
}

- (LUArray *)allProtocols 
{
	return nil;
}

- (LUDictionary *)rpcWithName:(char *)name
{
	return [self itemWithKey:"name" value:name];
}

- (LUDictionary *)rpcWithNumber:(int *)number
{
	return [self itemWithKey:"number" intValue:*number];
}

- (LUArray *)allRpcs
{
	return nil;
}

- (LUDictionary *)mountWithName:(char *)name
{
	return [self itemWithKey:"name" value:name];
}

- (LUArray *)allMounts
{
	return nil;
}

- (LUDictionary *)printerWithName:(char *)name
{
	return [self itemWithKey:"name" value:name];
}

- (LUArray *)allPrinters
{
	return nil;
}

- (LUDictionary *)bootparamsWithName:(char *)name
{
	return [self itemWithKey:"name" value:name];
}

- (LUArray *)allBootparams
{
	return nil;
}

- (LUDictionary *)bootpWithInternetAddress:(struct in_addr *)addr
{
	return [self itemWithInternetAddress:addr];
}

- (LUDictionary *)bootpWithEthernetAddress:(struct ether_addr *)addr
{
	return [self itemWithKey:"en_address"
		value:[self canonicalEthernetAddress:addr]];
}

- (LUDictionary *)aliasWithName:(char *)name
{
	LUDictionary *alias;

	alias = [self itemWithKey:"name" value:name];
	[alias setValue:"1" forKey:"alias_local"];
	return alias;
}

- (LUArray *)allAliases
{
	return nil;
}

- (LUDictionary *)netgroupWithName:(char *)name
{
	return [self itemWithKey:"name" value:name];
}

- (LUArray *)allNetgroups
{
	return nil;
}

- (BOOL)inNetgroup:(char *)group
	host:(char *)host
	user:(char *)user
	domain:(char *)domain
{
	return NO;
}

@end
