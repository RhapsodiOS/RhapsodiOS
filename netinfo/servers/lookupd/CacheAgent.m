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
	CacheAgent.m

	Cache server for lookupd

	Copyright (c) 1995, NeXT Computer Inc.
	All rights reserved.
	Written by Marc Majka
 */

#import "CacheAgent.h"
#import "LUPrivate.h"
#import "LUCachedDictionary.h"
#import "Syslog.h"
#import <arpa/inet.h>
#import <stdio.h>
#import "stringops.h"
#import <mach/cthreads.h>
#import <mach/message.h>

#define CUserName			 0
#define CUserNumber			 1
#define CGroupName 			 2
#define CGroupNumber 		 3
#define CHostName 			 4
#define CHostIPAddress		 5
#define CHostENAddress		 6
#define CNetworkName		 7
#define CNetworkIPAddress	 8
#define CServiceName		 9
#define CServiceNumber		10
#define CProtocolName		11
#define CProtocolNumber		12
#define CRpcName			13
#define CRpcNumber			14
#define CMountName			15
#define CPrinterName		16
#define CBootparamName		17
#define CBootpName			18
#define CBootpIPAddress		19
#define CBootpENAddress		20
#define CAliasName			21
#define CNetgroupName		22

#define forever for(;;)

extern struct ether_addr *ether_aton(char *);

static CacheAgent *_sharedCacheAgent = nil;

@implementation CacheAgent

- (LUCategory)categoryForCache:(int)n
{
	switch (n)
	{
		case  0:
		case  1: return LUCategoryUser;
		case  2:
		case  3: return LUCategoryGroup;
		case  4:
		case  5:
		case  6: return LUCategoryHost;
		case  7:
		case  8: return LUCategoryNetwork;
		case  9:
		case 10: return LUCategoryService;
		case 11:
		case 12: return LUCategoryProtocol;
		case 13:
		case 14: return LUCategoryRpc;
		case 15: return LUCategoryMount;
		case 16: return LUCategoryPrinter;
		case 17: return LUCategoryBootparam;
		case 18:
		case 19:
		case 20: return LUCategoryBootp;
		case 21: return LUCategoryAlias;
		case 22: return LUCategoryNetgroup;
	}
	return LUCategoryNull;
}
		
- (const char *)nameForCache:(int)n
{
	switch (n)
	{
		case  0: return "user (by name)";
		case  1: return "user (by uid)";
		case  2: return "group (by name)";
		case  3: return "group (by gid)";
		case  4: return "host (by name)";
		case  5: return "host (by Internet address)";
		case  6: return "host (by Ethernet address)";
		case  7: return "network (by name)";
		case  8: return "network (by Internet address)";
		case  9: return "service (by name)";
		case 10: return "service (by number)";
		case 11: return "protocol (by name)";
		case 12: return "protocol (by number)";
		case 13: return "rpc (by name)";
		case 14: return "protocol (by number)";
		case 15: return "mount";
		case 16: return "printer";
		case 17: return "bootparam (by name)";
		case 18: return "bootparam (by Internet address)";
		case 19: return "bootparam (by Ethernet address)";
		case 20: return "bootp";
		case 21: return "alias";
		case 22: return "netgroup";
	}
	return "unknown";
}

- (void)ageCache:(unsigned int)n
{
	int i, len;
	int expired, expireAll, expireInitGroups, expireRootInitgroups;
	time_t age;
	time_t ttl;
	LUDictionary *item;
	LUArray *all;
	LUCategory cat;
	char str[128];
	LUCache *cache;

	cat = [self categoryForCache:n];
	if (cat >= NCATEGORIES) return;
 
	cache = cacheStore[n].cache;

	expired = 0;
	expireAll = 0;
	expireInitGroups = 0;
	expireRootInitgroups = 0;

	if (cat == LUCategoryGroup)
	{
		[allStore[LUCategoryInitgroups].lock lock];
		[rootInitGroups.lock lock];
	}
	[allStore[cat].lock lock];
	
	len = [cache count];
	for (i = len - 1; i >= 0; i--)
	{
		item = [cache objectAtIndex:i];
		if (item == nil) continue;

		ttl = [item timeToLive];
		age = [item age];

		if (age > ttl)
		{
			[cache removeObject:item];
			expired++;
		}
	}

	if (cat == LUCategoryGroup)
	{
		all = allStore[LUCategoryInitgroups].all;
		if (all != nil)
		{
			if (expired > 0)
				expireInitGroups++;
			else if ([all validationStampCount] == 0)
				expireInitGroups++;
			else
			{
				item = [all validationStampAtIndex:0];
				ttl = [item timeToLive];
				age = [item age];

				if (age > ttl) expireInitGroups++;
			}
		}

		all = rootInitGroups.all;
		if (all != nil)
		{
			if (expired > 0)
				expireRootInitgroups++;
			else if ([all validationStampCount] == 0)
				expireRootInitgroups++;
			else
			{
				item = [all validationStampAtIndex:0];
				ttl = [item timeToLive];
				age = [item age];

				if (age > ttl) expireRootInitgroups++;
			}
		}
	}

	if (expireInitGroups)
	{
		[allStore[LUCategoryInitgroups].all release];
		allStore[LUCategoryInitgroups].all = nil;
		if (initgroupsUserName != NULL) freeString(initgroupsUserName);
		initgroupsUserName = NULL;
	}

	if (expireRootInitgroups)
	{
		[rootInitGroups.all release];
		rootInitGroups.all = nil;
	}

	if (allStore[cat].all != nil)
	{
		if (expired > 0)
			expireAll++;
		else if ([allStore[cat].all validationStampCount] == 0)
			expireAll++;
		else
		{
			item = [allStore[cat].all validationStampAtIndex:0];
			ttl = [item timeToLive];
			age = [item age];

			if (age > ttl) expireAll++;
		}
	}

	if (expireAll)
	{
		[allStore[cat].all release];
		allStore[cat].all = nil;
	}

	[allStore[cat].lock unlock];
	if (cat == LUCategoryGroup)
	{
		[allStore[LUCategoryInitgroups].lock unlock];
		[rootInitGroups.lock unlock];
	}
	
	if (expired > 0)
	{
		sprintf(str, "expired %d object%s in %s cache",
			expired, (expired == 1) ? "" : "s", [self nameForCache:n]);
		[lookupLog syslogDebug:str];
	}

	if (expireAll > 0)
	{
		sprintf(str, "expired all %s cache", [self categoryName:cat]);
		[lookupLog syslogDebug:str];
	}

	if (expireInitGroups > 0)
	{
		sprintf(str, "expired all groups for user cache");
		[lookupLog syslogDebug:str];
	}

	if (expireRootInitgroups > 0)
	{
		sprintf(str, "expired all groups for root cache");
		[lookupLog syslogDebug:str];
	}
}

- (time_t)minTimeToLive
{
	int i;
	time_t min;
 
	min = cacheStore[0].ttl;
	for (i = 1; i < NCACHE; i++)
		if (cacheStore[i].ttl < min) min = cacheStore[i].ttl;
	return min;
}

/*
 * Maintainence thread runs this loop
 */
void sweep(id agent)
{
	int i;
	msg_timeout_t snooze;
	struct no_msg {
		msg_header_t head;
	} no_msg;

	port_allocate(task_self(), &no_msg.head.msg_local_port);
	no_msg.head.msg_size = sizeof(no_msg);

	/* 60 seconds sleep at startup time */
	snooze = 60 * 1000; 
	(void)msg_receive((msg_header_t *)&no_msg, RCV_TIMEOUT, snooze);

	/*
	 * set snooze time to shortest TimeToLive
	 * but not less than 60 seconds.
	 */
	snooze = [agent minTimeToLive];
	if (snooze < 60) snooze = 60;
	snooze *= 1000;
	(void)msg_receive((msg_header_t *)&no_msg, RCV_TIMEOUT, snooze);
	
	forever
	{
		for (i = 0; i < NCACHE; i++) [agent ageCache:i];
		(void)msg_receive((msg_header_t *)&no_msg, RCV_TIMEOUT, snooze);
	}
}

/*
 * Object creation, initilizations, and general stuff
 */

- (CacheAgent *)init
{
	int i;

	if (didInit) return self;

	[super init];

	for (i = 0; i < NCACHE; i++)
	{
		cacheStore[i].cache = [[LUCache alloc] init];
		cacheStore[i].capacity = (unsigned int)-1;
		cacheStore[i].ttl = 43200;
		cacheStore[i].delta = 0;
		cacheStore[i].freq = 0;
		cacheStore[i].validate = YES;
		cacheStore[i].enabled = NO;
	}

	for (i = 0; i < NCATEGORIES; i++)
	{
		allStore[i].all = nil;
		allStore[i].validate = YES;
		allStore[i].enabled = NO;
		allStore[i].lock = [[NSRecursiveLock alloc] init];
	}

	rootInitGroups.all = nil;
	rootInitGroups.lock = [[NSRecursiveLock alloc] init];

	initgroupsUserName = NULL;

	stats = [[LUDictionary alloc] init];
	[stats setBanner:"CacheAgent statistics"];
	[stats setValue:"Cache" forKey:"information_system"];

	cthread_detach(cthread_fork((cthread_fn_t)sweep, (any_t)self));

	return self;
}

+ (CacheAgent *)alloc
{
	char str[128];

	if (_sharedCacheAgent != nil)
	{
		[_sharedCacheAgent retain];
		return _sharedCacheAgent;
	}

	_sharedCacheAgent = [super alloc];
	_sharedCacheAgent = [_sharedCacheAgent init];
	if (_sharedCacheAgent == nil) return nil;

	sprintf(str, "Allocated CacheAgent 0x%x\n", (int)_sharedCacheAgent);
	[lookupLog syslogDebug:str];

	return _sharedCacheAgent;
}

- (void)dealloc
{
	int i;
	char str[128];

	for (i = 0; i < NCACHE; i++)
	{
		if (cacheStore[i].cache != nil) [cacheStore[i].cache release];
	}

	for (i = 0; i < NCATEGORIES; i++)
	{
		if (allStore[i].all != nil) [allStore[i].all release];
		if (allStore[i].lock != nil) [allStore[i].lock release];
	}

	[rootInitGroups.all release];
	if (rootInitGroups.lock != nil) [rootInitGroups.lock release];

	if (initgroupsUserName != NULL) freeString(initgroupsUserName);
	initgroupsUserName = NULL;

	sprintf(str, "Deallocated CacheAgent 0x%x\n", (int)self);
	[lookupLog syslogDebug:str];

	[super dealloc];

	_sharedCacheAgent = nil;
}

- (const char *)name
{
	return "Cache";
}

- (const char *)shortName
{
	return "CacheAgent";
}

- (LUDictionary *)statistics
{
	int i;
	char key[256], str[256];

	for (i = 0; i < NCACHE; i++)
	{
		sprintf(key, "%s size", [self nameForCache:i]);
		sprintf(str, "%d", [cacheStore[i].cache count]);
		[stats setValue:str forKey:key];
	}

	return stats;
}

- (void)resetStatistics
{
	[stats release];

	stats = [[LUDictionary alloc] init];
	[stats setBanner:"CacheAgent statistics"];
	[stats setValue:"Cache" forKey:"information_system"];
}
		
/*
 * Fetch objects from cache
 */

- (LUDictionary *)postProcess:(LUDictionary *)item
	cache:(unsigned int)n
	key:(char *)key
{
	id agent;

	time_t age, ttl, newttl;
	unsigned int hits;

	if (item == nil) return nil;
	ttl = [item timeToLive];

	if (cacheStore[n].validate)
	{
		agent = [item agent];
		if (agent == nil)
		{
			[cacheStore[n].cache removeObject:item];
			return nil;
		}

		if (![agent isValid:item])
		{
			[cacheStore[n].cache removeObject:item];
			return nil;
		}
	}

	age = [item age];
	if (age > ttl)
	{
		[self removeObject:item];
		return nil;
	}

	hits = [item cacheHit];
	[item resetAge];

	if ((cacheStore[n].freq > 0) &&
		((hits % cacheStore[n].freq) == 0))
	{
		newttl = ttl + cacheStore[n].delta;

		/* check for wrap-around */
		if (newttl < ttl) newttl = (time_t)-1;
		[item setTimeToLive:newttl];
	}

	/* Retain the object here.  Caller must release. */
	[item retain];
	return item;
}

- (BOOL)isArrayValid:(LUArray *)array
{
	unsigned int i, len;
	time_t age;
	LUDictionary *stamp;
	LUAgent *agent;

	if (array == nil) return NO;
	len = [array validationStampCount];
	if (len == 0) return NO;

	for (i = 0; i < len; i++)
	{
		stamp = [array validationStampAtIndex:i];
		if (stamp == nil) return NO;
		age = [stamp age];
		if (age > [stamp timeToLive]) return NO;

		agent = [stamp agent];
		if (agent == nil) return NO;
		if (![agent isValid:stamp]) return NO;
	}
	return YES;
}

- (LUArray *)allItemsForCategory:(LUCategory)cat
{
	LUArray *all;

	if (cat > NCATEGORIES) return nil;

	[allStore[(unsigned int)cat].lock lock]; // locked ((((

	all = allStore[(unsigned int)cat].all;
	if (all == nil)
	{
		[allStore[(unsigned int)cat].lock unlock]; // ) unlocked
		return nil;
	}

	/* Retain the array here.  Caller must release */
	if (!allStore[(unsigned int)cat].validate)
	{
		[all retain];
		[allStore[(unsigned int)cat].lock unlock]; // ) unlocked
		return all;
	}

	if ([self isArrayValid:all])
	{
		[all retain];
		[allStore[(unsigned int)cat].lock unlock]; // ) unlocked
		return all;
	}

	[all release];
	allStore[(unsigned int)cat].all = nil;
	[allStore[(unsigned int)cat].lock unlock]; // ) unlocked
	return nil;
}

- (void)setTimeToLive:(time_t)ttl forArray:(LUArray *)array
{
	LUDictionary *stamp;
	int i, len;

	if (array == nil) return;

	len = [array validationStampCount];
	for (i = 0; i < len; i++)
	{
		stamp = [array validationStampAtIndex:i];
		if (stamp != nil) [stamp setTimeToLive:ttl];
	}
}

- (void)addArray:(LUArray *)array
{
	LUDictionary *stamp;
	LUCategory cat;
	time_t ttl;

	if (array == nil) return;

	stamp = [array validationStampAtIndex:0];
	if (stamp == nil) return;
	cat = [stamp category];
	if (cat >= NCATEGORIES) return;

	/* initgroups arrays are handled by setInitgroupsForUser: */
	if (cat == LUCategoryInitgroups) return;

	ttl = [self timeToLiveForCategory:cat];
	[self setTimeToLive:ttl forArray:array];

	[allStore[cat].lock lock];
	if (allStore[cat].all != nil) [allStore[cat].all release];
	allStore[cat].all = [array retain];
	[allStore[cat].lock unlock];
}

- (LUArray *)initgroupsForUser:(char *)name
{
	LUArray *all;
	
	if (!strcmp(name, "root"))
	{
		[rootInitGroups.lock lock]; // locked ((((
		if (rootInitGroups.all == nil)
		{
			[rootInitGroups.lock unlock]; // ) unlocked
			return nil;
		}

		if (!allStore[(unsigned int)LUCategoryInitgroups].validate)
		{
			[rootInitGroups.all retain];
			[rootInitGroups.lock unlock]; // ) unlocked
			return rootInitGroups.all;
		}

		if ([self isArrayValid:rootInitGroups.all])
		{
			[rootInitGroups.all retain];
			[rootInitGroups.lock unlock]; // ) unlocked
			return rootInitGroups.all;
		}

		[rootInitGroups.all release];
		rootInitGroups.all = nil;
		[rootInitGroups.lock unlock]; // ) unlocked
		return nil;
	}

	[allStore[(unsigned int)LUCategoryInitgroups].lock lock]; // locked (((
	if (initgroupsUserName == NULL)
	{
		[allStore[(unsigned int)LUCategoryInitgroups].lock unlock]; // unlocked )
		return nil;
	}

	if (strcmp(name, initgroupsUserName))
	{
		[allStore[(unsigned int)LUCategoryInitgroups].lock unlock]; // unlocked )
		return nil;
	}

	all = [self allItemsForCategory:LUCategoryInitgroups];
	[allStore[(unsigned int)LUCategoryInitgroups].lock unlock]; // unlocked )

	return all;
}

- (void)setInitgroups:(LUArray *)groups forUser:(char *)name
{
	time_t ttl;

	if (name == NULL) return;

	ttl = [self timeToLiveForCategory:LUCategoryGroup];
	[self setTimeToLive:ttl forArray:groups];

	if (!strcmp(name, "root"))
	{
		[rootInitGroups.lock lock];
		if (rootInitGroups.all != nil) [rootInitGroups.all release];
		rootInitGroups.all = [groups retain];
		[rootInitGroups.lock unlock];
		return;
	}

	[allStore[(unsigned int)LUCategoryInitgroups].lock lock];

	if (initgroupsUserName != NULL) freeString(initgroupsUserName);
	initgroupsUserName = copyString(name);

	if (allStore[(unsigned int)LUCategoryInitgroups].all != nil)
	{
		[allStore[(unsigned int)LUCategoryInitgroups].all release];
	}
	allStore[(unsigned int)LUCategoryInitgroups].all = [groups retain];

	[allStore[(unsigned int)LUCategoryInitgroups].lock unlock];
}

- (LUDictionary *)cache:(unsigned int)n itemWithKey:(char *)key
{
	LUDictionary *item;
	LUCategory cat;

	cat = [self categoryForCache:n];
	if (cat >= NCATEGORIES) return nil;
 
	[allStore[(unsigned int)cat].lock lock];
	item = [cacheStore[n].cache objectForKey:key];
	item = [self postProcess:item cache:n key:key];
	[allStore[(unsigned int)cat].lock unlock];

	return item;
}

- (LUDictionary *)userWithName:(char *)name
{
	return [self cache:CUserName itemWithKey:name];
}

- (LUDictionary *)userWithNumber:(int *)number
{
	char key[64];

	sprintf(key, "%d", *number);
	return [self cache:CUserNumber itemWithKey:key];
}
	
- (LUDictionary *)groupWithName:(char *)name
{
	return [self cache:CGroupName itemWithKey:name];
}

- (LUDictionary *)groupWithNumber:(int *)number
{
	char key[64];

	sprintf(key, "%d", *number);
	return [self cache:CGroupNumber itemWithKey:key];
}

- (LUDictionary *)hostWithName:(char *)name
{
	return [self cache:CHostName itemWithKey:name];
}

- (LUDictionary *)hostWithInternetAddress:(struct in_addr *)addr
{
	return [self cache:CHostIPAddress itemWithKey:inet_ntoa(*addr)];
}

- (LUDictionary *)hostWithEthernetAddress:(struct ether_addr *)addr
{
	return [self cache:CHostENAddress
		itemWithKey:[self canonicalEthernetAddress:addr]];
}

- (LUDictionary *)networkWithName:(char *)name
{
	return [self cache:CNetworkName itemWithKey:name];
}

- (LUDictionary *)networkWithInternetAddress:(struct in_addr *)addr
{
	return [self cache:CNetworkIPAddress itemWithKey:inet_ntoa(*addr)];
}

- (LUDictionary *)serviceWithName:(char *)name protocol:(char *)prot
{
	char key[64];

	if (prot == NULL)
		return [self cache:CServiceName itemWithKey:name];

	sprintf(key, "%s/%s", name, prot);
	return [self cache:CServiceName itemWithKey:key];
}

- (LUDictionary *)serviceWithNumber:(int *)number protocol:(char *)prot
{
	char key[64];

	sprintf(key, "%d", *number);
	if (prot == NULL)
		return [self cache:CServiceNumber itemWithKey:key];

	sprintf(key, "%d/%s", *number, prot);
	return [self cache:CServiceNumber itemWithKey:key];
}

- (LUDictionary *)protocolWithName:(char *)name
{
	return [self cache:CProtocolName itemWithKey:name];
}

- (LUDictionary *)protocolWithNumber:(int *)number
{
	char key[32];

	sprintf(key, "%d", *number);
	return [self cache:CProtocolNumber itemWithKey:key];
}

- (LUDictionary *)rpcWithName:(char *)name
{
	return [self cache:CRpcName itemWithKey:name];
}

- (LUDictionary *)rpcWithNumber:(int *)number
{
	char key[64];

	sprintf(key, "%d", *number);
	return [self cache:CRpcNumber itemWithKey:key];
}

- (LUDictionary *)mountWithName:(char *)name
{
	return [self cache:CMountName itemWithKey:name];
}

- (LUDictionary *)printerWithName:(char *)name
{
	return [self cache:CPrinterName itemWithKey:name];
}

- (LUDictionary *)bootparamsWithName:(char *)name
{
	return [self cache:CBootparamName itemWithKey:name];
}

- (LUDictionary *)bootpWithInternetAddress:(struct in_addr *)addr
{
	return [self cache:CBootpIPAddress itemWithKey:inet_ntoa(*addr)];
}

- (LUDictionary *)bootpWithEthernetAddress:(struct ether_addr *)addr
{
	return [self cache:CBootpENAddress
		itemWithKey:[self canonicalEthernetAddress:addr]];
}

- (LUDictionary *)aliasWithName:(char *)name
{
	return [self cache:CAliasName itemWithKey:name];
}

- (LUDictionary *)netgroupWithName:(char *)name
{
	return [self cache:CNetgroupName itemWithKey:name];
}

/*
 * Utilities
 */

- (BOOL)cacheNumber:(int)n isCategory:(LUCategory)cat
{
	if (n < 0 || n > NCACHE) return NO;

	switch (cat)
	{
		case LUCategoryUser:
			return ((n  ==  CUserName) || (n  ==  CUserNumber));
		case LUCategoryGroup:
			return ((n  ==  CGroupName) || (n  ==  CGroupNumber));
		case LUCategoryHost:
			return ((n  ==  CHostName) || (n  ==  CHostIPAddress)
				|| (n  ==  CHostENAddress));
		case LUCategoryNetwork:
			return ((n  ==  CNetworkName) || (n  ==  CNetworkIPAddress));
		case LUCategoryService:
			return ((n  ==  CServiceName) || (n  ==  CServiceNumber));
		case LUCategoryProtocol:
			return ((n  ==  CProtocolName) || (n  ==  CProtocolNumber));
		case LUCategoryRpc:
			return ((n  ==  CRpcName) || (n  ==  CRpcNumber));
		case LUCategoryMount:
			return (n  ==  CMountName);
		case LUCategoryPrinter:
			return (n  ==  CPrinterName);
		case LUCategoryBootparam:
			return (n  ==  CBootparamName);
		case LUCategoryBootp:
			return ((n  ==  CBootpName) || (n  ==  CBootpIPAddress)
				|| (n  ==  CBootpENAddress));
		case LUCategoryAlias:
			return (n  ==  CAliasName);
		case LUCategoryNetgroup:
			return (n  ==  CNetgroupName);
		default: return NO;
	}
	return NO;
}

- (int)indexCategory:(LUCategory)cat
{
	switch (cat)
	{
		case LUCategoryUser: return CUserName;
		case LUCategoryGroup: return CGroupName;
		case LUCategoryHost: return CHostName;
		case LUCategoryNetwork: return CNetworkName;
		case LUCategoryService: return CServiceName;
		case LUCategoryProtocol: return CProtocolName;
		case LUCategoryRpc: return CRpcName;
		case LUCategoryMount: return CMountName;
		case LUCategoryPrinter: return CPrinterName;
		case LUCategoryBootparam: return CBootparamName;
		case LUCategoryBootp: return CBootpName;
		case LUCategoryAlias: return CAliasName;
		case LUCategoryNetgroup: return CNetgroupName;
		default: return -1;
	}
}

- (void)freeSpace:(unsigned int)n inCache:(unsigned int)cacheNum
{
	unsigned int i, size, avail;

	size = [cacheStore[cacheNum].cache count];
	avail = cacheStore[cacheNum].capacity - size;

	for (i = avail; i < n; i++)
		[cacheStore[cacheNum].cache removeOldestObject];
}

/*
 * Add objects to cache 
 */

- (void)addObject:(LUDictionary *)item
	category:(LUCategory)cat
	toCache:(unsigned int)cacheNum
	key:(char *)keyName
{
	char **values;

	if (item == nil) return;
	if (cacheNum >= NCACHE) return;
	if (!cacheStore[cacheNum].enabled) return;
	if (keyName == NULL) return;

	values = [item valuesForKey:keyName];
	if (values == NULL) return;

	[allStore[(unsigned int)cat].lock lock];
	[self freeSpace:1 inCache:cacheNum];
	[item setTimeToLive:cacheStore[cacheNum].ttl];
	[item setCacheHits:0];
	[cacheStore[cacheNum].cache setObject:item forKeys:values];
	[allStore[(unsigned int)cat].lock unlock];
}

- (void)addEthernetObject:(LUDictionary *)item
	category:(LUCategory)cat
	toCache:(unsigned int)cacheNum
{
	char **values;
	struct ether_addr *ether;
	int i, len;

	if (item == nil) return;
	if (!(cacheNum == CHostENAddress || cacheNum == CBootpENAddress)) return;
	if (!cacheStore[cacheNum].enabled) return;

	values = [item valuesForKey:"en_address"];
	if (values == NULL) return;

	[allStore[(unsigned int)cat].lock lock];
	[self freeSpace:1 inCache:cacheNum];
	[item setTimeToLive:cacheStore[cacheNum].ttl];
	[item setCacheHits:0];

	len = [item countForKey:"en_address"];
	if (len < 0) len = 0;
	for (i = 0; i < len; i++)
	{
		ether = ether_aton(values[i]);
		if (ether != NULL)
			[cacheStore[cacheNum].cache setObject:item
				forKey:[self canonicalEthernetAddress:ether]];
	}
	[allStore[(unsigned int)cat].lock unlock];
}

- (void)addService:(LUDictionary *)item
{
	char **names;
	char **numbers;
	char **protocols;
	int j, nnames, nnumbers;
	int i, nprotocols;
	LUCache *nameCache;
	LUCache *numberCache;
	char str[256];

	if (item == nil) return;
	if (!cacheStore[CServiceName].enabled) return;

	names = [item valuesForKey:"name"];
	numbers = [item valuesForKey:"number"];
	protocols = [item valuesForKey:"protocol"];

	if (protocols == NULL) return;

	nameCache = cacheStore[CServiceName].cache;
	if (nameCache == nil) return;

	numberCache = cacheStore[CServiceNumber].cache;
	if (numberCache == nil) return;

	[allStore[LUCategoryService].lock lock];

	[self freeSpace:1 inCache:CServiceName];
	[self freeSpace:1 inCache:CServiceNumber];

	if (names == NULL) nnames = 0;
	else nnames = [item countForKey:"name"];
	if (nnames < 0) nnames = 0;

	if (numbers == NULL) nnumbers = 0;
	nnumbers = [item countForKey:"number"];
	if (nnumbers < 0) nnumbers = 0;

	nprotocols = [item countForKey:"protocol"];
	if (nprotocols < 0) nprotocols = 0;

	[item setTimeToLive:cacheStore[CServiceName].ttl];
	[item setCacheHits:0];
	[nameCache setObject:item forKeys:names];

	for (i = 0; i < nprotocols; i++)
	{
		for (j = 0; j < nnames; j++)
		{
			sprintf(str, "%s/%s", names[j], protocols[i]);
			[nameCache setObject:item forKey:str];
		}

		for (j = 0; j < nnumbers; j++)
		{
			sprintf(str, "%s/%s", numbers[j], protocols[i]);
			[numberCache setObject:item forKey:str];
		}
	}

	[allStore[LUCategoryService].lock unlock];
}

- (void)addObject:(LUDictionary *)item
{
	LUCategory cat;

	if (item == nil) return;

	cat = [item category];
	switch (cat)
	{
		case LUCategoryUser:
			[self addObject:item category:cat toCache:CUserName key:"name"];
			[self addObject:item category:cat toCache:CUserNumber key:"uid"];
			break;
		case LUCategoryGroup:
			[self addObject:item category:cat toCache:CGroupName key:"name"];
			[self addObject:item category:cat toCache:CGroupNumber key:"gid"];
			break;
		case LUCategoryHost:
			[self addObject:item category:cat toCache:CHostName key:"name"];
			[self addObject:item category:cat toCache:CHostIPAddress key:"ip_address"];
			[self addEthernetObject:item category:cat toCache:CHostENAddress];
			break;
		case LUCategoryNetwork:
			[self addObject:item category:cat toCache:CNetworkName key:"name"];
			[self addObject:item category:cat toCache:CNetworkIPAddress key:"address"];
			break;
		case LUCategoryService:
			[self addService:item];
			break;
		case LUCategoryProtocol:
			[self addObject:item category:cat toCache:CProtocolName key:"name"];
			[self addObject:item category:cat toCache:CProtocolNumber key:"number"];
			break;
		case LUCategoryRpc:
			[self addObject:item category:cat toCache:CRpcName key:"name"];
			[self addObject:item category:cat toCache:CRpcNumber key:"number"];
			break;
		case LUCategoryMount:
			[self addObject:item category:cat toCache:CMountName key:"name"];
			break;
		case LUCategoryPrinter:
			[self addObject:item category:cat toCache:CPrinterName key:"name"];
			break;
		case LUCategoryBootparam:
			[self addObject:item category:cat toCache:CBootparamName key:"name"];
			break;
		case LUCategoryBootp:
			[self addObject:item category:cat toCache:CBootpName key:"name"];
			[self addObject:item category:cat toCache:CBootpIPAddress key:"ip_address"];
			[self addEthernetObject:item category:cat toCache:CBootpENAddress];
			break;
		case LUCategoryAlias:
			[self addObject:item category:cat toCache:CAliasName key:"name"];
			break;
		case LUCategoryNetgroup:
			[self addObject:item category:cat toCache:CNetgroupName key:"name"];
			break;
//		case LUCategoryHostServices:
//			[self addHostService:name];
//			break;	
		default: break;
	}
}

/*
 * Remove objects from cache
 */

- (void)removeObject:(LUDictionary *)item
{
	LUCategory cat;

	if (item == nil) return;

	cat = [item category];
	[allStore[(unsigned int)cat].lock lock];
	switch (cat)
	{
		case LUCategoryUser:
			[cacheStore	[CUserName].cache removeObject:item];
			[cacheStore	[CUserNumber].cache removeObject:item];
			break;
		case LUCategoryGroup:
			[cacheStore	[CGroupName].cache removeObject:item];
			[cacheStore	[CGroupNumber].cache removeObject:item];
			break;
		case LUCategoryHost:
			[cacheStore	[CHostName].cache removeObject:item];
			[cacheStore	[CHostIPAddress].cache removeObject:item];
			[cacheStore	[CHostENAddress].cache removeObject:item];
			break;
		case LUCategoryNetwork:
			[cacheStore	[CNetworkName].cache removeObject:item];
			[cacheStore	[CNetworkIPAddress].cache removeObject:item];
			break;
		case LUCategoryService:
			[cacheStore	[CServiceName].cache removeObject:item];
			[cacheStore	[CServiceNumber].cache removeObject:item];
			break;
		case LUCategoryProtocol:
			[cacheStore	[CProtocolName].cache removeObject:item];
			[cacheStore	[CProtocolNumber].cache removeObject:item];
			break;
		case LUCategoryRpc:
			[cacheStore	[CRpcName].cache removeObject:item];
			[cacheStore	[CRpcNumber].cache removeObject:item];
			break;
		case LUCategoryMount:
			[cacheStore	[CMountName].cache removeObject:item];
			break;
		case LUCategoryPrinter:
			[cacheStore	[CPrinterName].cache removeObject:item];
			break;
		case LUCategoryBootparam:
			[cacheStore	[CBootparamName].cache removeObject:item];
			break;
		case LUCategoryBootp:
			[cacheStore	[CBootpName].cache removeObject:item];
			[cacheStore	[CBootpIPAddress].cache removeObject:item];
			[cacheStore	[CBootpENAddress].cache removeObject:item];
			break;
		case LUCategoryAlias:
			[cacheStore	[CAliasName].cache removeObject:item];
			break;
		case LUCategoryNetgroup:
			[cacheStore	[CNetgroupName].cache removeObject:item];
			break;
		default: break;
	}

	[allStore[(unsigned int)cat].lock unlock];
}

- (void)flushCache
{
	int i;

	for (i = 0; i < NCATEGORIES; i++) [allStore[i].lock lock];

	for (i = 0; i < NCACHE; i++)
	{
		[cacheStore[i].cache empty];
	}

	for (i = 0; i < NCATEGORIES; i++)
	{
		[allStore[i].all release];
		allStore[i].all = nil;

		if (i == LUCategoryInitgroups)
		{
			if (initgroupsUserName != NULL) freeString(initgroupsUserName);
			initgroupsUserName = NULL;
		}
		[allStore[i].lock unlock];
	}

	[rootInitGroups.lock lock];
	if (rootInitGroups.all != nil) [rootInitGroups.all release];
	rootInitGroups.all = nil;
	[rootInitGroups.lock unlock];
}

- (void)flushCacheForCategory:(LUCategory)cat
{
	unsigned int i;

	[allStore[(unsigned int)cat].lock lock];

	for (i = 0; i < NCACHE; i++)
	{
		if ([self cacheNumber:i isCategory:cat]) [cacheStore[i].cache empty];
	}

	i = (unsigned int)cat;
	if (allStore[i].all != nil)
	{
		[allStore[i].all release];
		allStore[i].all = nil;
	}

	[allStore[(unsigned int)cat].lock unlock];

	if (cat == LUCategoryInitgroups)
	{
		[rootInitGroups.lock lock];
		if (rootInitGroups.all != nil) [rootInitGroups.all release];
		rootInitGroups.all = nil;
		[rootInitGroups.lock unlock];
	}
}

/*
 * Cache management
 */

- (void)setCapacity:(unsigned int)max forCategory:(LUCategory)cat
{
	int i;

	for (i = 0; i < NCACHE; i++)
	{
		if ([self cacheNumber:i isCategory:cat])
			cacheStore[i].capacity = max;
	}
}

- (unsigned int)capacityForCategory:(LUCategory)cat
{
	int n;

	n = [self indexCategory:cat];
	if (n < 0) return 0;
	return cacheStore[n].capacity;
}

- (void)setTimeToLive:(time_t)timeout forCategory:(LUCategory)cat
{
	int i;

	for (i = 0; i < NCACHE; i++)
	{
		if ([self cacheNumber:i isCategory:cat])
			cacheStore[i].ttl = timeout;
	}
}

- (time_t)timeToLiveForCategory:(LUCategory)cat
{
	int n;

	n = [self indexCategory:cat];
	if (n < 0) return 0;
	return cacheStore[n].ttl;
}

- (void)setCacheIsValidated:(BOOL)validate forCategory:(LUCategory)cat
{
	int i;

	for (i = 0; i < NCACHE; i++)
	{
		if ([self cacheNumber:i isCategory:cat])
			cacheStore[i].validate = validate;
	}

	allStore[(unsigned int)cat].validate = validate;
}

- (BOOL)cacheIsValidatedForCategory:(LUCategory)cat
{
	if (cat > NCATEGORIES) return NO;
	return allStore[(unsigned int)cat].validate;
}

- (void)setCacheIsEnabled:(BOOL)enabled forCategory:(LUCategory)cat
{
	int i;

	for (i = 0; i < NCACHE; i++)
	{
		if ([self cacheNumber:i isCategory:cat])
			cacheStore[i].enabled = enabled;
	}

	allStore[(unsigned int)cat].enabled = enabled;
}

- (BOOL)cacheIsEnabledForCategory:(LUCategory)cat
{
	if (cat > NCATEGORIES) return NO;
	return allStore[(unsigned int)cat].enabled;
}

- (void)addTimeToLive:(time_t)delta
	afterCacheHits:(unsigned int)freq
	forCategory:(LUCategory)cat
{
	int i;

	for (i = 0; i < NCACHE; i++)
	{
		if ([self cacheNumber:i isCategory:cat])
		{
			cacheStore[i].delta = delta;
			cacheStore[i].freq = freq;
		}
	}
}

- (time_t)cacheTimeToLiveDeltaForCategory:(LUCategory)cat
{
	int n;

	n = [self indexCategory:cat];
	if (n < 0) return 0;
	return cacheStore[n].delta;
}

- (unsigned int)cacheTimeToLiveFrequencyForCategory:(LUCategory)cat
{
	int n;

	n = [self indexCategory:cat];
	if (n < 0) return 0;
	return cacheStore[n].freq;
}

- (BOOL)containsObject:(id)obj
{
	int i;
 
	if ([obj isMemberOfClass:[LUArray class]])
	{
		for (i = 0; i < NCATEGORIES; i++)
		if (obj == allStore[i].all) return YES;
		if (obj == rootInitGroups.all) return YES;
		return NO;
	}

	for (i = 0; i < NCACHE; i++)
		if ([cacheStore[i].cache containsObject:obj]) return YES;

	return NO;
}

@end
