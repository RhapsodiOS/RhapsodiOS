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
	LUServer.m

	Lookup server for lookupd

	Copyright (c) 1995, NeXT Computer Inc.
	All rights reserved.
	Written by Marc Majka
 */

#import "LUServer.h"
#import "LUCachedDictionary.h"
#import "Controller.h"
#import "Syslog.h"
#import "stringops.h"
#import <string.h>
#import <stdlib.h>
#import <stdio.h>

#if NS_TARGET_MAJOR == 3
#import <foundation/NSString.h>
#import <foundation/NSAutoreleasePool.h>
#else
#import <Foundation/NSString.h>
#import <Foundation/NSAutoreleasePool.h>
#endif

#define MaxNetgroupRecursion 5
#define XDRSIZE 8192

@implementation LUServer

+ (LUServer *)alloc
{
	id s;
	char str[128];

	s = [super alloc];

	sprintf(str, "Allocated LUServer 0x%x\n", (int)s);
	[lookupLog syslogDebug:str];

	return s;
}


- (LUServer *)init
{
	int i;
	char str[128];

	[super init];
	stats = [[LUDictionary alloc] init];
	[stats setBanner:"LUServer statistics"];

	agentClassList = [[NSMutableArray alloc] init];
	agentList = [[NSMutableArray alloc] init];
	statsLock = [[NSLock alloc] init];

	for (i = 0; i < NCATEGORIES; i++) order[i] = [[NSMutableArray alloc] init];

	cacheAgent = [[CacheAgent alloc] init];
	[agentClassList addObject:[CacheAgent class]];
	[agentList addObject:cacheAgent];

	sprintf(str, "LUServer 0x%x added agent 0x%x (%s) retain count = %d",
		(int)self, (int)cacheAgent, [cacheAgent shortName],
		[cacheAgent retainCount]);
	[lookupLog syslogDebug:str];

	ooBufferSize = 0;
	ooBuffer = NULL;

	idle = YES;

	return self;
}

- (BOOL)isIdle
{
	return idle;
}

/*
 * Called on check out / check in.
 */
- (void)setIsIdle:(BOOL)yn
{
	idle = yn;

	if (idle)
	{
		if (ooBufferSize > 0)
		{
			free(ooBuffer);
			ooBuffer = NULL;
			ooBufferSize = 0;
		}
	}
}

- (LUAgent *)agentForSystem:(id)systemClass
{
	int i, len;
	LUAgent *agent;
	char str[256];
	NSAutoreleasePool *puddle;
	len = [agentClassList count];
	for (i = 0; i < len; i++)
	{
		if ([agentClassList objectAtIndex:i] == systemClass)
		{
			return [agentList objectAtIndex:i];
		}
	}

	agent = [[systemClass alloc] init];
	if (agent == nil)
	{
		puddle = [[NSAutoreleasePool alloc] init];
		sprintf(str, "LUServer: can't initialize server of class %s",
			[[systemClass description] cString]);
		[lookupLog syslogAlert:str];
		[puddle release];
		return nil;
	}

	[agentClassList addObject:systemClass];
	[agentList addObject:agent];

	sprintf(str, "LUServer 0x%x added agent 0x%x (%s) retain count = %d",
		(int)self, (int)agent, [agent shortName], [agent retainCount]);
	[lookupLog syslogDebug:str];

	return agent;
}

/*
 * luOrder must be an array of Class objects
 */
- (void)setLookupOrder:(NSArray *)luOrder
{
	int i, j, len;
	LUAgent *agent;
	BOOL enabled;

	for (i = 0; i < NCATEGORIES; i++) [order[i] removeAllObjects];

	if (luOrder == nil)
	{
		for (i = 0; i < NCATEGORIES; i++)
			[cacheAgent setCacheIsEnabled:NO forCategory:(LUCategory)i];
		return;
	}

	len = [luOrder count];
	enabled = NO;
	for (i = 0; i < len; i++)
	{
		agent = [self agentForSystem:[luOrder objectAtIndex:i]];
		if (agent != nil)
		{
			for (j = 0; j < NCATEGORIES; j++) [order[j] addObject:agent];
			if ([agent isMemberOfClass:[CacheAgent class]]) enabled = YES;
		}
	}

	for (i = 0; i < NCATEGORIES; i++)
		[cacheAgent setCacheIsEnabled:enabled forCategory:(LUCategory)i];
}

- (void)setLookupOrder:(NSArray *)luOrder forCategory:(LUCategory)cat
{
	int i, len, n;
	LUAgent *agent;
	BOOL enabled;

	n = (unsigned int)cat;
	[order[n] removeAllObjects];

	if (luOrder == nil)
	{
		[cacheAgent setCacheIsEnabled:NO forCategory:cat];
		return;
	}

	len = [luOrder count];
	enabled = NO;
	for (i = 0; i < len; i++)
	{
		agent = [self agentForSystem:[luOrder objectAtIndex:i]];
		if (agent != nil)
		{
			[order[n] addObject:agent];
			if ([agent isMemberOfClass:[CacheAgent class]]) enabled = YES;
		}
	}

	[cacheAgent setCacheIsEnabled:enabled forCategory:cat];
}

- (void)copyToOOBuffer:(char *)src
	size:(unsigned long)src_size
	offset:(unsigned long)offset
{
	unsigned long avail, delta;

	if (ooBufferSize == 0)
	{
		ooBufferSize = XDRSIZE * ((src_size / XDRSIZE) + 1);
		ooBuffer = malloc(ooBufferSize);
	}
	else
	{
		avail = ooBufferSize - offset;

		if (src_size > avail) 
		{
			delta = XDRSIZE * (((src_size - avail) / XDRSIZE) + 1);
			ooBufferSize += delta;
			ooBuffer = realloc(ooBuffer, ooBufferSize);
		}
	}
	
	memmove(ooBuffer + offset, src, src_size);
}

- (char *)ooBuffer
{
	return ooBuffer;
}

- (void)dealloc
{
	char str[128];
	int i, len;
	LUAgent *agent;

	if (stats != nil) [stats release];
	for (i = 0; i < NCATEGORIES; i++)
	{
		if (order[i] != nil) [order[i] release];
	}

	if (agentClassList != nil) [agentClassList release];

	if (agentList != nil)
	{
		len = [agentList count];
		for (i = len - 1; i >= 0; i--)
		{
			agent = [agentList objectAtIndex:i];
			sprintf(str, "%d: server 0x%x releasing agent 0x%x (%s) with retain count = %d", i, (int)self, (int)agent, [agent shortName], [agent retainCount]);
			[lookupLog syslogDebug:str];
			[agentList removeObject:agent];
			[agent release];
		}

		[agentList release];
	}

	free(ooBuffer);

	if (cacheAgent != nil) [cacheAgent release];
	if (statsLock != nil) [statsLock release];

	sprintf(str, "Deallocated LUServer 0x%x\n", (int)self);
	[lookupLog syslogDebug:str];

	[super dealloc];
}

- (void)add:(unsigned long)i toDict:(LUDictionary *)dict forKey:(char *)key
{
	unsigned long n;
	char str[256];

	if (dict == nil) return;
	if (key == NULL) return;

	n = i + [dict intForKey:key];
	sprintf(str, "%lu", n);
	[dict setValue:str forKey:key];
}

- (void)recordCall:(char *)method
	time:(unsigned int)time
{
	char key[256];

	[statsLock lock];

	/* total of all calls */
	[self add:1 toDict:stats forKey:"total_calls"];

	/* total time for all calls */
	[self add:time toDict:stats forKey:"total_time"];

	/* total calls of this lookup method */
	sprintf(key, "%s_calls", method);
	[self add:1 toDict:stats forKey:key];

	/* total time in this lookup method */
	sprintf(key, "%s_time", method);
	[self add:time toDict:stats forKey:key];

	[statsLock unlock];
}

- (void)recordSearch:(char *)method
	infoSystem:(const char *)info
	time:(unsigned int)time
{
	char key[256];

	[statsLock lock];

	/* total searches in this info system */
	sprintf(key, "%s_searches", info);
	[self add:1 toDict:stats forKey:key];

	/* total time in this info system */
	sprintf(key, "%s_time", info);
	[self add:time toDict:stats forKey:key];

	/* total searches using this method in this info system */
	sprintf(key, "%s_%s_searches", info, method);
	[self add:1 toDict:stats forKey:key];
	
	/* total time in this method in this info system */
	sprintf(key, "%s_%s_time", info, method);
	[self add:time toDict:stats forKey:key];

	[statsLock unlock];
}


- (LUDictionary *)stamp:(LUDictionary *)item
	agent:(LUAgent *)agent
 	category:(LUCategory)cat
{
	BOOL cacheEnabled;
	char scratch[256];

	if (item == nil) return nil;

	cacheEnabled = [cacheAgent cacheIsEnabledForCategory:cat];
	[item setCategory:cat];

	if (strcmp([agent name], "Cache"))
	{
		if (cat == LUCategoryBootp)
		{
			sprintf(scratch, "%s: %s %s (%s / %s)",
				[agent shortName],
				[self categoryName:cat],
				[item valueForKey:"name"],
				[item valueForKey:"en_address"],
				[item valueForKey:"ip_address"]);
		}
		else
		{
			sprintf(scratch, "%s: %s %s",
				[agent shortName],
				[self categoryName:cat],
				[item valueForKey:"name"]);
		}
		[item setBanner:scratch];
	}

	if (cacheEnabled && (strcmp([agent name], "Cache")))
	{
		[cacheAgent addObject:item];
	}

	if ([item isNegative])
	{
		[item release];
		return nil;
	}

	return item;
}

- (LUDictionary *)statistics
{
	return stats;
}

- (LUArray *)agentStatistics
{
	LUArray *allStats;
	LUAgent *agent;
	int i, len;

	allStats = [[LUArray alloc] init];
	[allStats setBanner:"LUServer agent statistics"];

	len = [agentList count];
	for (i = 0; i < len; i++)
	{
		agent = [agentList objectAtIndex:i];
		[allStats addObject:[agent statistics]];
	}
	return allStats;
}

- (void)resetStatistics
{
	[statsLock lock];
	[stats release];
	stats = [[LUDictionary alloc] init];
	[stats setBanner:"LUServer statistics"];
	[statsLock unlock];
}


/*
 * Data lookup done here!
 */
- (LUDictionary *)itemWithIdentifier:(void *)ident
	category:(LUCategory)cat
	method:(SEL)sel
	calledFrom:(char *)caller;
{
	NSMutableArray *lookupOrder;
	LUDictionary *item;
	LUAgent *agent;
	int i, len;
	struct timeval allStart;
	struct timeval sysStart;
	struct timeval end;
	unsigned int sysTime;
	unsigned int allTime;

	if (ident == NULL)
	{
		[self recordSearch:caller infoSystem:"Failed" time:0];
		[self recordCall:caller time:0];
		return nil;
	}

	lookupOrder = order[(unsigned int)cat];
	item = nil;
	len = [lookupOrder count];

	gettimeofday(&allStart, (struct timezone *)NULL);

	for (i = 0; i < len; i++)
	{
		agent = [lookupOrder objectAtIndex:i];

		gettimeofday(&sysStart, (struct timezone *)NULL);

#if NS_TARGET_MAJOR == 3
		item = [agent perform:sel withObject:ident];
#else
		item = [agent performSelector:sel withObject:ident];
#endif
		gettimeofday(&end, (struct timezone *)NULL);
		sysTime = (end.tv_sec - sysStart.tv_sec) * 1000 +
			(end.tv_usec - sysStart.tv_usec) / 1000;
		[self recordSearch:caller infoSystem:[agent name] time:sysTime];

		if (item != nil)
		{
			allTime = (end.tv_sec - allStart.tv_sec) * 1000 +
				(end.tv_usec - allStart.tv_usec) / 1000;
			[self recordCall:caller time:allTime];
			return [self stamp:item agent:agent category:cat];
		}
	}

	allTime = (end.tv_sec - allStart.tv_sec) * 1000 +
		(end.tv_usec - allStart.tv_usec) / 1000;
	[self recordSearch:caller infoSystem:"Failed" time:allTime];
	[self recordCall:caller time:allTime];

	return nil;
}

/*
 * Data lookup done here!
 */
- (LUArray *)allItemsUsingMethod:(SEL)sel
		category:(LUCategory)cat
		calledFrom:(char *)caller
{
	NSMutableArray *lookupOrder;
	LUArray *all;
	LUArray *sub;
	LUAgent *agent;
	LUDictionary *stamp;
	LUDictionary *item;
	int i, len;
	int j, sublen;
	BOOL cacheEnabled;
	char scratch[256];
	struct timeval allStart;
	struct timeval sysStart;
	struct timeval end;
	unsigned int sysTime;
	unsigned int allTime;

	gettimeofday(&allStart, (struct timezone *)NULL);

	cacheEnabled = [cacheAgent cacheIsEnabledForCategory:cat];
	if (cacheEnabled)
	{
		gettimeofday(&sysStart, (struct timezone *)NULL);
		all = [cacheAgent allItemsForCategory:cat];
		gettimeofday(&end, (struct timezone *)NULL);
		sysTime = (end.tv_sec - sysStart.tv_sec) * 1000 +
			(end.tv_usec - sysStart.tv_usec) / 1000;
		[self recordSearch:caller infoSystem:"Cache" time:sysTime];

		if (all != nil)
		{
			gettimeofday(&end, (struct timezone *)NULL);
			allTime = (end.tv_sec - allStart.tv_sec) * 1000 +
				(end.tv_usec - allStart.tv_usec) / 1000;
			[self recordCall:caller time:allTime];
			return all;
		}
	}

	all = [[LUArray alloc] init];

	lookupOrder = order[(unsigned int)cat];
	len = [lookupOrder count];
	agent = nil;
	for (i = 0; i < len; i++)
	{
		agent = [lookupOrder objectAtIndex:i];
		if (!strcmp([agent name], "Cache")) continue;

		gettimeofday(&sysStart, (struct timezone *)NULL);

#if NS_TARGET_MAJOR == 3
		sub = [agent perform:sel];
#else
		sub = [agent performSelector:sel];
#endif

		gettimeofday(&end, (struct timezone *)NULL);
		sysTime = (end.tv_sec - sysStart.tv_sec) * 1000 +
			(end.tv_usec - sysStart.tv_usec) / 1000;
		[self recordSearch:caller infoSystem:[agent name] time:sysTime];

		if (sub != nil)
		{
			/* Merge validation info from this agent into "all" array */
			sublen = [sub validationStampCount];
			for (j = 0; j < sublen; j++)
			{
				stamp = [sub validationStampAtIndex:j];
				[stamp setCategory:cat];
				[all addValidationStamp:stamp];
			}

			sublen = [sub count];
			for (j = 0; j < sublen; j++)
			{
				item = [sub objectAtIndex:j];
				[item setCategory:cat];
				[all addObject:item];
			}

			[sub release];
		}
	}

	gettimeofday(&end, (struct timezone *)NULL);
	allTime = (end.tv_sec - allStart.tv_sec) * 1000 +
		(end.tv_usec - allStart.tv_usec) / 1000;
	[self recordCall:caller time:allTime];

	if ([all count] == 0)
	{
		[all release];
		return nil;
	}

	sprintf(scratch, "LUServer: all %s", [self categoryName:cat]);
	[all setBanner:scratch];

	if (cacheEnabled) [cacheAgent addArray:all];
	return all;
}

/*
 * Data lookup done here!
 */
- (LUArray *)allGroupsWithUser:(char *)name
{
	NSMutableArray *lookupOrder;
	LUArray *all;
	LUArray *sub;
	LUAgent *agent;
	LUDictionary *stamp;
	int i, len;
	int j, sublen;
	BOOL cacheEnabled;
	char scratch[256];
	struct timeval allStart;
	struct timeval sysStart;
	struct timeval end;
	unsigned int sysTime;
	unsigned int allTime;

	if (name == NULL)
	{
		[self recordSearch:"allGroupsWithUser" infoSystem:"Failed" time:0];
		[self recordCall:"allGroupsWithUser" time:0];
		return nil;
	}

	gettimeofday(&allStart, (struct timezone *)NULL);

	cacheEnabled = [cacheAgent cacheIsEnabledForCategory:LUCategoryInitgroups];
	if (cacheEnabled)
	{
		gettimeofday(&sysStart, (struct timezone *)NULL);
		all = [cacheAgent initgroupsForUser:name];
		gettimeofday(&end, (struct timezone *)NULL);
		sysTime = (end.tv_sec - sysStart.tv_sec) * 1000 +
			(end.tv_usec - sysStart.tv_usec) / 1000;
		[self recordSearch:"allGroupsWithUser" infoSystem:"Cache"
			time:sysTime];

		if (all != nil)
		{
			gettimeofday(&end, (struct timezone *)NULL);
			allTime = (end.tv_sec - allStart.tv_sec) * 1000 +
				(end.tv_usec - allStart.tv_usec) / 1000;
			[self recordCall:"allGroupsWithUser" time:allTime];
			return all;
		}
	}

	all = [[LUArray alloc] init];

	lookupOrder = order[(unsigned int)LUCategoryUser];
	len = [lookupOrder count];
	agent = nil;
	for (i = 0; i < len; i++)
	{
		agent = [lookupOrder objectAtIndex:i];
		if (!strcmp([agent name], "Cache")) continue;

		gettimeofday(&sysStart, (struct timezone *)NULL);
		sub = [agent allGroupsWithUser:name];
		gettimeofday(&end, (struct timezone *)NULL);
		sysTime = (end.tv_sec - sysStart.tv_sec) * 1000 +
			(end.tv_usec - sysStart.tv_usec) / 1000;
		[self recordSearch:"allGroupsWithUser" infoSystem:[agent name]
			time:sysTime];

		if (sub != nil)
		{
			/* Merge validation info from this agent into "all" array */
			sublen = [sub validationStampCount];
			for (j = 0; j < sublen; j++)
			{
				stamp = [sub validationStampAtIndex:j];
				[stamp setCategory:LUCategoryInitgroups];
				[all addValidationStamp:stamp];
			}

			sublen = [sub count];
			for (j = 0; j < sublen; j++)
			{
				[all addObject:[sub objectAtIndex:j]];
			}

			[sub release];
		}
	}

	gettimeofday(&end, (struct timezone *)NULL);
	allTime = (end.tv_sec - allStart.tv_sec) * 1000 +
		(end.tv_usec - allStart.tv_usec) / 1000;
	[self recordCall:"allGroupsWithUser" time:allTime];

	if ([all count] == 0)
	{
		[all release];
		return nil;
	}

	sprintf(scratch, "LUServer: all groups with user %s", name);
	[all setBanner:scratch];

	if (cacheEnabled) [cacheAgent setInitgroups:all forUser:name];
	return all;
}

/*
 ****************  Lookup routines (API) start here  ****************
 */

- (BOOL)inNetgroup:(char *)group
	host:(char *)host
	user:(char *)user
	domain:(char *)domain
	level:(int)level
{
	LUDictionary *g;
	int i, len;
	char **members;
	char *name;
	char str[256];

	if (level > MaxNetgroupRecursion)
	{
		sprintf(str, "netgroups nested more than %d levels",
			MaxNetgroupRecursion);
		[lookupLog syslogError:str];
		return NO;
	}

	if (group == NULL) return NO;
	g = [self netgroupWithName:group];
	if (g == nil) return NO;

	if (host != NULL)
	{
		name = host;
		members = [g valuesForKey:"hosts"];
	}
	else if (user != NULL)
	{
		name = user;
		members = [g valuesForKey:"users"];
	}
	else if (domain != NULL)
	{
		name = domain;
		members = [g valuesForKey:"domains"];
	}
	else
	{
		[g release];
		return NO;
	}

	if ((listIndex("*", members) != IndexNull) ||
		(listIndex(name, members) != IndexNull))
	{
		[g release];
		return YES;
	}
	
	members = [g valuesForKey:"netgroups"];
	len = [g countForKey:"netgroups"];
	for (i = 0; i < len; i++)
	{
		if ([self inNetgroup:members[i] host:host user:user domain:domain
			level:level+1])
		{
			[g release];
			return YES;
		}
	}

	[g release];
	return NO;
}

- (BOOL)inNetgroup:(char *)group
	host:(char *)host
	user:(char *)user
	domain:(char *)domain
{
	return [self inNetgroup:group host:host user:user domain:domain level:0];
}

- (LUDictionary *)userWithName:(char *)name
{
	return [self itemWithIdentifier:name
		category:(LUCategory)LUCategoryUser
		method:@selector(userWithName:)
		calledFrom:"userWithName"];
}

- (LUDictionary *)userWithNumber:(int *)number
{
	return [self itemWithIdentifier:number
		category:(LUCategory)LUCategoryUser
		method:@selector(userWithNumber:)
		calledFrom:"userWithNumber"];
}

- (LUArray *)allUsers
{
	return [self allItemsUsingMethod:@selector(allUsers)
		category:(LUCategory)LUCategoryUser
		calledFrom:"allUsers"];
}

- (LUDictionary *)groupWithName:(char *)name
{
	return [self itemWithIdentifier:name
		category:(LUCategory)LUCategoryGroup
		method:@selector(groupWithName:)
		calledFrom:"groupWithName"];
}

- (LUDictionary *)groupWithNumber:(int *)number
{
	return [self itemWithIdentifier:number
		category:(LUCategory)LUCategoryGroup
		method:@selector(groupWithNumber:)
		calledFrom:"groupWithNumber"];
}

- (LUArray *)allGroups
{
	return [self allItemsUsingMethod:@selector(allGroups)
		category:(LUCategory)LUCategoryGroup
		calledFrom:"allGroups"];
}

- (LUDictionary *)hostWithName:(char *)name
{
	return [self itemWithIdentifier:name
		category:(LUCategory)LUCategoryHost
		method:@selector(hostWithName:)
		calledFrom:"hostWithName"];
}

- (LUDictionary *)hostWithInternetAddress:(struct in_addr *)addr
{
	return [self itemWithIdentifier:addr
		category:(LUCategory)LUCategoryHost
		method:@selector(hostWithInternetAddress:)
		calledFrom:"hostWithInternetAddress"];
}

- (LUDictionary *)hostWithEthernetAddress:(struct ether_addr *)addr
{
	return [self itemWithIdentifier:addr
		category:(LUCategory)LUCategoryHost
		method:@selector(hostWithEthernetAddress:)
		calledFrom:"hostWithEthernetAddress"];
}

- (LUArray *)allHosts
{
	return [self allItemsUsingMethod:@selector(allHosts)
		category:(LUCategory)LUCategoryHost
		calledFrom:"allHosts"];
}

- (LUDictionary *)networkWithName:(char *)name
{
	return [self itemWithIdentifier:name
		category:(LUCategory)LUCategoryNetwork
		method:@selector(networkWithName:)
		calledFrom:"networkWithName"];
}

- (LUDictionary *)networkWithInternetAddress:(struct in_addr *)addr
{
	return [self itemWithIdentifier:addr
		category:(LUCategory)LUCategoryNetwork
		method:@selector(networkWithInternetAddress:)
		calledFrom:"networkWithInternetAddress"];
}

- (LUArray *)allNetworks
{
	return [self allItemsUsingMethod:@selector(allNetworks)
		category:(LUCategory)LUCategoryNetwork
		calledFrom:"allNetworks"];
}

/*
 * Data lookup done here!
 */
- (LUDictionary *)serviceWithName:(char *)name
	protocol:(char *)prot
{
	NSMutableArray *lookupOrder;
	LUDictionary *item;
	LUAgent *agent;
	int i, len;
	struct timeval allStart;
	struct timeval sysStart;
	struct timeval end;
	unsigned int sysTime;
	unsigned int allTime;

	if (name == NULL)
	{
		[self recordSearch:"serviceWithName" infoSystem:"Failed" time:0];
		[self recordCall:"serviceWithName" time:0];
		return nil;
	}

	gettimeofday(&allStart, (struct timezone *)NULL);
	lookupOrder = order[(unsigned int)LUCategoryService];
	item = nil;
	len = [lookupOrder count];
	for (i = 0; i < len; i++)
	{
		agent = [lookupOrder objectAtIndex:i];
		gettimeofday(&sysStart, (struct timezone *)NULL);
		item = [agent serviceWithName:name protocol:prot];
		gettimeofday(&end, (struct timezone *)NULL);
		sysTime = (end.tv_sec - sysStart.tv_sec) * 1000 +
			(end.tv_usec - sysStart.tv_usec) / 1000;
		[self recordSearch:"serviceWithName" infoSystem:[agent name]
			time:sysTime];

		if (item != nil)
		{
			gettimeofday(&end, (struct timezone *)NULL);
			allTime = (end.tv_sec - allStart.tv_sec) * 1000 +
				(end.tv_usec - allStart.tv_usec) / 1000;
			[self recordCall:"serviceWithName" time:allTime];
			return [self stamp:item agent:agent category:LUCategoryService];
		}
	}
	gettimeofday(&end, (struct timezone *)NULL);
	allTime = (end.tv_sec - allStart.tv_sec) * 1000 +
		(end.tv_usec - allStart.tv_usec) / 1000;
	[self recordSearch:"serviceWithName" infoSystem:"Failed" time:allTime];
	[self recordCall:"serviceWithName" time:allTime];
	return nil;
}

/*
 * Data lookup done here!
 */
- (LUDictionary *)serviceWithNumber:(int *)number
	protocol:(char *)prot
{
	NSMutableArray *lookupOrder;
	LUDictionary *item;
	LUAgent *agent;
	int i, len;
	struct timeval allStart;
	struct timeval sysStart;
	struct timeval end;
	unsigned int sysTime;
	unsigned int allTime;

	if (number == NULL)
	{
		[self recordSearch:"serviceWithNumber" infoSystem:"Failed" time:0];
		[self recordCall:"serviceWithNumber" time:0];
		return nil;
	}

	gettimeofday(&allStart, (struct timezone *)NULL);
	lookupOrder = order[(unsigned int)LUCategoryService];
	item = nil;
	len = [lookupOrder count];
	for (i = 0; i < len; i++)
	{
		agent = [lookupOrder objectAtIndex:i];
		gettimeofday(&sysStart, (struct timezone *)NULL);
		item = [agent serviceWithNumber:number protocol:prot];
		gettimeofday(&end, (struct timezone *)NULL);
		sysTime = (end.tv_sec - sysStart.tv_sec) * 1000 +
			(end.tv_usec - sysStart.tv_usec) / 1000;
		[self recordSearch:"serviceWithNumber" infoSystem:[agent name]
			time:sysTime];

		if (item != nil)
		{
			gettimeofday(&end, (struct timezone *)NULL);
			allTime = (end.tv_sec - allStart.tv_sec) * 1000 +
				(end.tv_usec - allStart.tv_usec) / 1000;
			[self recordCall:"serviceWithNumber" time:allTime];
			return [self stamp:item agent:agent category:LUCategoryService];
		}
	}
	gettimeofday(&end, (struct timezone *)NULL);
	allTime = (end.tv_sec - allStart.tv_sec) * 1000 +
		(end.tv_usec - allStart.tv_usec) / 1000;
	[self recordSearch:"serviceWithNumber" infoSystem:"Failed" time:allTime];
	[self recordCall:"serviceWithNumber" time:allTime];
	return nil;
}

- (LUArray *)allServices
{
	return [self allItemsUsingMethod:@selector(allServices)
		category:(LUCategory)LUCategoryService
		calledFrom:"allServices"];
}

- (LUDictionary *)protocolWithName:(char *)name
{
	return [self itemWithIdentifier:name
		category:(LUCategory)LUCategoryProtocol
		method:@selector(protocolWithName:)
		calledFrom:"protocolWithName"];
}

- (LUDictionary *)protocolWithNumber:(int *)number
{
	return [self itemWithIdentifier:number
		category:(LUCategory)LUCategoryProtocol
		method:@selector(protocolWithNumber:)
		calledFrom:"protocolWithNumber"];
}

- (LUArray *)allProtocols 
{
	return [self allItemsUsingMethod:@selector(allProtocols)
		category:(LUCategory)LUCategoryProtocol
		calledFrom:"allProtocols"];
}

- (LUDictionary *)rpcWithName:(char *)name
{
	return [self itemWithIdentifier:name
		category:(LUCategory)LUCategoryRpc
		method:@selector(rpcWithName:)
		calledFrom:"rpcWithName"];
}

- (LUDictionary *)rpcWithNumber:(int *)number
{
	return [self itemWithIdentifier:number
		category:(LUCategory)LUCategoryRpc
		method:@selector(rpcWithNumber:)
		calledFrom:"rpcWithNumber"];
}

- (LUArray *)allRpcs
{
	return [self allItemsUsingMethod:@selector(allRpcs)
		category:(LUCategory)LUCategoryRpc
		calledFrom:"allRpcs"];
}

- (LUDictionary *)mountWithName:(char *)name
{
	return [self itemWithIdentifier:name
		category:(LUCategory)LUCategoryMount
		method:@selector(mountWithName:)
		calledFrom:"mountWithName"];
}

- (LUArray *)allMounts
{
	return [self allItemsUsingMethod:@selector(allMounts)
		category:(LUCategory)LUCategoryMount
		calledFrom:"allMounts"];
}

- (LUDictionary *)printerWithName:(char *)name
{
	return [self itemWithIdentifier:name
		category:(LUCategory)LUCategoryPrinter
		method:@selector(printerWithName:)
		calledFrom:"printerWithName"];
}

- (LUArray *)allPrinters
{
	return [self allItemsUsingMethod:@selector(allPrinters)
		category:(LUCategory)LUCategoryPrinter
		calledFrom:"allPrinters"];
}

- (LUDictionary *)bootparamsWithName:(char *)name
{
	return [self itemWithIdentifier:name
		category:(LUCategory)LUCategoryBootparam
		method:@selector(bootparamsWithName:)
		calledFrom:"bootparamsWithName"];
}

- (LUArray *)allBootparams
{
	return [self allItemsUsingMethod:@selector(allBootparams)
		category:(LUCategory)LUCategoryBootparam
		calledFrom:"allBootparams"];
}

- (LUDictionary *)bootpWithInternetAddress:(struct in_addr *)addr
{
	return [self itemWithIdentifier:addr
		category:(LUCategory)LUCategoryBootp
		method:@selector(bootpWithInternetAddress:)
		calledFrom:"bootpWithInternetAddress"];
}

- (LUDictionary *)bootpWithEthernetAddress:(struct ether_addr *)addr
{
	return [self itemWithIdentifier:addr
		category:(LUCategory)LUCategoryBootp
		method:@selector(bootpWithEthernetAddress:)
		calledFrom:"bootpWithEthernetAddress"];
}

- (LUDictionary *)aliasWithName:(char *)name
{
	return [self itemWithIdentifier:name
		category:(LUCategory)LUCategoryAlias
		method:@selector(aliasWithName:)
		calledFrom:"aliasWithName"];
}

- (LUArray *)allAliases
{
	return [self allItemsUsingMethod:@selector(allAliases)
		category:(LUCategory)LUCategoryAlias
		calledFrom:"allAliases"];
}

/*
 * Data lookup done here!
 */
- (LUArray *)allNetgroupsWithName:(char *)name
{
	LUArray *all;
	NSMutableArray *lookupOrder;
	LUDictionary *item;
	LUAgent *agent;
	int i, len;
	char scratch[256];
	struct timeval allStart;
	struct timeval sysStart;
	struct timeval end;
	unsigned int sysTime;
	unsigned int allTime;

	if (name == NULL)
	{
		[self recordSearch:"netgroupWithName" infoSystem:"Failed" time:0];
		[self recordCall:"netgroupWithName" time:0];
		return nil;
	}

	lookupOrder = order[(unsigned int)LUCategoryNetgroup];
	len = [lookupOrder count];
	if (len == 0) return nil;

	all = [[LUArray alloc] init];

	gettimeofday(&allStart, (struct timezone *)NULL);

	for (i = 0; i < len; i++)
	{
		agent = [lookupOrder objectAtIndex:i];
		gettimeofday(&sysStart, (struct timezone *)NULL);
		item = [agent netgroupWithName:name];
		gettimeofday(&end, (struct timezone *)NULL);
		sysTime = (end.tv_sec - sysStart.tv_sec) * 1000 +
			(end.tv_usec - sysStart.tv_usec) / 1000;
		[self recordSearch:"netgroupWithName" infoSystem:[agent name]
			time:sysTime];

		if (item != nil)
		{
			[all addObject:item];
			[item release];
		}
	}

	gettimeofday(&end, (struct timezone *)NULL);
	allTime = (end.tv_sec - allStart.tv_sec) * 1000 +
		(end.tv_usec - allStart.tv_usec) / 1000;
	[self recordCall:"netgroupWithName" time:allTime];

	if ([all count] == 0)
	{
		[all release];
		return nil;
	}

	sprintf(scratch, "LUServer: all netgroups %s", name);
	[all setBanner:scratch];

	return all;
}

- (LUDictionary *)netgroupWithName:(char *)name
{
	LUArray *all;
	LUDictionary *group;
	int i, len;
	char scratch[256];

	if (name == NULL) return nil;

	all = [self allNetgroupsWithName:name];
	if (all == nil) return nil;

	group = [[LUDictionary alloc] init];
	sprintf(scratch, "LUServer: netgroup %s", name);
	[group setBanner:scratch];

	[group setValue:name forKey:"name"];

	len = [all count];
	for (i = 0; i < len; i++)
		[self mergeNetgroup:[all objectAtIndex:i] into:group];

	[all release];

	return group;
}

#ifdef DNS_SRV
- (LUDictionary *)hostsWithService:(char *)name
	protocol:(char *)prot
{
	NSMutableArray *lookupOrder;
	LUDictionary *item;
	LUAgent *agent;
	int i, len;
	struct timeval allStart;
	struct timeval sysStart;
	struct timeval end;
	unsigned int sysTime;
	unsigned int allTime;

	if (name == NULL)
	{
		[self recordSearch:"hostsWithService" infoSystem:"Failed" time:0];
		[self recordCall:"hostsWithService" time:0];
		return nil;
	}

	gettimeofday(&allStart, (struct timezone *)NULL);
	lookupOrder = order[(unsigned int)LUCategoryHostServices];
	item = nil;
	len = [lookupOrder count];
	for (i = 0; i < len; i++)
	{
		agent = [lookupOrder objectAtIndex:i];
		gettimeofday(&sysStart, (struct timezone *)NULL);
		item = [agent hostsWithService:name protocol:prot];
		gettimeofday(&end, (struct timezone *)NULL);
		sysTime = (end.tv_sec - sysStart.tv_sec) * 1000 +
			(end.tv_usec - sysStart.tv_usec) / 1000;
		[self recordSearch:"hostsWithService" infoSystem:[agent name]
			time:sysTime];

		if (item != nil)
		{
			gettimeofday(&end, (struct timezone *)NULL);
			allTime = (end.tv_sec - allStart.tv_sec) * 1000 +
				(end.tv_usec - allStart.tv_usec) / 1000;
			[self recordCall:"hostsWithService" time:allTime];
			return [self stamp:item agent:agent category:LUCategoryHostServices];
		}
	}
	gettimeofday(&end, (struct timezone *)NULL);
	allTime = (end.tv_sec - allStart.tv_sec) * 1000 +
		(end.tv_usec - allStart.tv_usec) / 1000;
	[self recordSearch:"hostsWithService" infoSystem:"Failed" time:allTime];
	[self recordCall:"hostsWithService" time:allTime];
	return nil;
}
#endif /* DNS_SRV */

@end
