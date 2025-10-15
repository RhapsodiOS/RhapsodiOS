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
	NIAgent.m

	NetInfo lookup agent for lookupd

	Copyright (c) 1995, NeXT Computer Inc.
	All rights reserved.
	Written by Marc Majka
 */

#import "NIAgent.h"
#import "Controller.h"
#import "LUPrivate.h"
#import "Syslog.h"
#import "stringops.h"
#import <stdlib.h>
#import <stdio.h>

static NIAgent *_sharedNIAgent = nil;
static NSMutableArray *_domainStore = nil;
static char **_domainNames;

@implementation NIAgent

/* Domain cache is maintained by the class */
+(void)initialize
{
	if (_domainStore == nil)
	{
		_domainStore = [[NSMutableArray alloc] init];
		_domainNames = NULL;
	}
	return;
}

+ (LUNIDomain *)domainWithName:(char *)domainName
{
	LUNIDomain *d;
	int i, len;

	len = listLength(_domainNames);
	for (i = 0; i < len; i++)
	{
		if (!strcmp(domainName, _domainNames[i]))
			return [_domainStore objectAtIndex:i];
	}

	d = [[LUNIDomain alloc] initWithDomainNamed:domainName];
	[_domainStore addObject:d];
	_domainNames = appendString(domainName, _domainNames);

	return d;
}

+ (void)releaseDomainStore
{
	[_domainStore release];
	_domainStore = nil;
	freeList(_domainNames);
	_domainNames = NULL;
}

- (void)_setupChain:(NSMutableArray *)c fromConfig:(LUDictionary *)config
{
	char **order;
	LUNIDomain *d;
	int i, len;

	/* Set up DomainOrder */
	if (config == nil)
	{
		order = NULL;
		len = 0;
	}
	else
	{
		order = [config valuesForKey:"DomainOrder"];
		if (order == NULL) len = 0;
		else len = listLength(order);
	}

	if (len == 0)
	{
		/* Only default to standard lookup for global config */
		if (c != globalChain) return;

		/* use plain local->root order */
		d = [NIAgent domainWithName:"."];

		while (d != nil)
		{
			[_domainStore addObject:d];
			_domainNames = appendString((char *)[d name], _domainNames);
			[c addObject:d];
			d = [d parent];
		}

	}
	else
	{
		for (i = 0; i < len; i++)
		{
			d = [NIAgent domainWithName:order[i]];
			if (d != nil) [c addObject:d];
		}
	}
}

- (NIAgent *)init
{
	int i;
	LUDictionary *config;

	if (didInit) return self;

	[super init];
	stats = [[LUDictionary alloc] init];
	[stats setBanner:"NIAgent statistics"];
	[stats setValue:"NetInfo" forKey:"information_system"];
	threadLock = [[NSRecursiveLock alloc] init];

	/* Get global DomainOrder */
	config = [controller configurationForAgent:"NIAgent"];
	globalChain = [[NSMutableArray alloc] init];
	[self _setupChain:globalChain fromConfig:config];

	for (i = 0; i < NCATEGORIES; i++)
	{
		config = [controller configurationForAgent:"NIAgent"
			category:(LUCategory)i];
		chain[i] = [[NSMutableArray alloc] init];
		[self _setupChain:chain[i] fromConfig:config];
	}

	return self;
}

+ (NIAgent *)alloc
{
	char str[128];

	if (_sharedNIAgent != nil)
	{
		[_sharedNIAgent retain];
		return _sharedNIAgent;
	}

	_sharedNIAgent = [super alloc];
	_sharedNIAgent = [_sharedNIAgent init];
	if (_sharedNIAgent == nil) return nil;

	sprintf(str, "Allocated NIAgent 0x%x\n", (int)_sharedNIAgent);
	[lookupLog syslogDebug:str];

	return _sharedNIAgent;
}

- (void)dealloc
{
	int i;
	char str[128];

	for (i = 0; i < NCATEGORIES; i++)
		if (chain[i] != nil) [chain[i] release];
	if (globalChain != nil) [globalChain release];
	if (stats != nil) [stats release];
	if (threadLock != nil) [threadLock release];

	sprintf(str, "Deallocated NIAgent 0x%x\n", (int)self);
	[lookupLog syslogDebug:str];

	[super dealloc];

	_sharedNIAgent = nil;
}

/*
 * +reallyAlloc and -initWithLocalHierarchy
 * are special hacks for the controller.
 */

+ (NIAgent *)reallyAlloc
{
	id na;
	char str[128];

	na = [super alloc];

	sprintf(str, "Allocated NIAgent 0x%x\n", (int)na);
	[lookupLog syslogDebug:str];

	return na;
}

- (NIAgent *)initWithLocalHierarchy
{
	LUNIDomain *d;
	int i;

	[super init];

	globalChain = [[NSMutableArray alloc] init];
	for (i = 0; i < NCATEGORIES; i++)
	{
		chain[i] = [[NSMutableArray alloc] init];
	}

	d = [NIAgent domainWithName:"."];
	while (d != nil)
	{
		[globalChain addObject:d];
		d = [d parent];
	}

	stats = [[LUDictionary alloc] init];
	[stats setBanner:"Control NIAgent statistics"];
	[stats setValue:"NetInfo" forKey:"information_system"];
	threadLock = [[NSRecursiveLock alloc] init];
	return self;
}

- (const char *)name
{
	return "NetInfo";
}

- (const char *)shortName
{
	return "NIAgent";
}

- (void)setMaxChecksumAge:(time_t)age
{
	int i, j, len;

	for (j = 0; j < NCATEGORIES; j++)
	{
		len = [chain[j] count];
		for (i = 0; i < len; i++)
			[[chain[j] objectAtIndex:i] setMaxChecksumAge:age];
	}
}


- (unsigned int)indexOfDomain:(LUNIDomain *)domain
{
	unsigned int i, len;

	if (domain == nil) return IndexNull;

	len = [_domainStore count];
	for (i = 0; i < len; i++)
	{
		if (domain == [_domainStore objectAtIndex:i]) return i;
	}

	return IndexNull;
}

- (LUNIDomain *)domainAtIndex:(unsigned int)where
{
	if (where >= listLength(_domainNames)) return nil;
	return [_domainStore objectAtIndex:where];
}
	
- (LUDictionary *)statistics
{
	LUNIDomain *d;
	int i, len;
	char key[256];

	[threadLock lock]; // locked {
	len = listLength(_domainNames);
	for (i = 0; i < len; i++)
	{
		d = [_domainStore objectAtIndex:i];
		sprintf(key, "%d_domain", i);
		[stats setValue:(char *)_domainNames[i] forKey:key];
		sprintf(key, "%d_server", i);
		[stats setValue:[d currentServer] forKey:key];
	}

	[threadLock unlock]; // } unlocked
	return stats;
}

- (void)resetStatistics
{
	if (stats != nil) [stats release];
	stats = [[LUDictionary alloc] init];
	[stats setBanner:"NIAgent statistics"];
	[stats setValue:"NetInfo" forKey:"information_system"];
}

- (LUDictionary *)stamp:(LUDictionary *)item
	domain:(LUNIDomain *)d
{
	char str[32];

	[item setAgent:self];
	[item setValue:"NetInfo" forKey:"_lookup_info_system"];
	[item setValue:(char *)[d name] forKey:"_lookup_NI_domain"];
	[item setValue:[d currentServer] forKey:"_lookup_NI_server"];
	sprintf(str, "%u", [self indexOfDomain:d]);
	[item setValue:str forKey:"_lookup_NI_index"];
	sprintf(str, "%lu", [d currentChecksum]);
	[item setValue:str forKey:"_lookup_NI_checksum"];
	return item;
}

- (void)allStamp:(LUArray *)all
	domain:(LUNIDomain *)d
	addToList:(LUArray *)list
{
	int i, len;
	char *dname;
	char *sname;
	char index[32], csum[32];
	LUDictionary * item;

	if (all == nil) return;

	dname = copyString((char *)[d name]);
	sname = copyString([d currentServer]);
	sprintf(index, "%u", [self indexOfDomain:d]);
	sprintf(csum, "%lu", [d currentChecksum]);

	len = [all count];
	for (i = 0; i < len; i++)
	{
		item = [all objectAtIndex:i];
		[item setAgent:self];
		[item setValue:"NetInfo" forKey:"_lookup_info_system"];
		[item setValue:dname forKey:"_lookup_NI_domain"];
		[item setValue:sname forKey:"_lookup_NI_server"];
		[item setValue:index forKey:"_lookup_NI_index"];
		[item setValue:csum forKey:"_lookup_NI_checksum"];

		[list addObject:item];
	}
	freeString(dname);
	dname = NULL;
	freeString(sname);
	sname = NULL;
}

- (BOOL)isValid:(LUDictionary *)item
{
	unsigned long oldsum, newsum;
	char *c;
	LUNIDomain *d;

	if (item == nil) return NO;
	c = [item valueForKey:"_lookup_NI_checksum"];
	if (c == NULL) return NO;
	sscanf(c, "%lu", &oldsum);

	c = [item valueForKey:"_lookup_NI_index"];
	if (c == NULL) return NO;
	d = [self domainAtIndex:atoi(c)];
	if (d == nil) return NO;

	[threadLock lock]; // locked {
	newsum = [d checksum];
	[threadLock unlock]; // } unlocked
	if (oldsum != newsum) return NO;
	return YES;
}

/*
 * These methods do NetInfo lookups on behalf of all calls
 */

- (LUDictionary *)item:(void *)ident method:(SEL)sel category:(LUCategory)cat
{
	LUDictionary *item = nil;
	LUNIDomain *d;
	unsigned int i, len;
	NSArray *lookupChain;

	[threadLock lock];
	len = [chain[(int)cat] count];
	if (len > 0)
	{
		lookupChain = chain[(int)cat];
	}
	else
	{
		lookupChain = globalChain;
		len = [lookupChain count];
	}

	for (i = 0; i < len; i++)
	{
		d = [lookupChain objectAtIndex:i];

#if NS_TARGET_MAJOR == 3
		item = [d perform:sel withObject:(id)ident];
#else
		item = [d performSelector:sel withObject:(id)ident];
#endif

		if (item != nil)
		{
			[self stamp:item domain:d];
			[threadLock unlock];
			return item;
		}
	}

	[threadLock unlock];
	return nil;
}

- (LUArray *)all:(SEL)sel category:(LUCategory)cat
{
	LUArray *all;
	LUArray *allInDomain;
	LUNIDomain *d;
	LUDictionary *vstamp;
	unsigned int i, len;
	char scratch[256];
	NSArray *lookupChain;

	all = [[LUArray alloc] init];
	sprintf(scratch, "NIAgent: all %s", [self categoryName:cat]);
	[all setBanner:scratch];

	[threadLock lock];
	len = [chain[(int)cat] count];
	if (len > 0)
	{
		lookupChain = chain[(int)cat];
	}
	else
	{
		lookupChain = globalChain;
		len = [lookupChain count];
	}

	for (i = 0; i < len; i++)
	{
		d = [lookupChain objectAtIndex:i];

		vstamp = [[LUDictionary alloc] init];
		[vstamp setBanner:"NIAgent validation stamp"];
		[all addValidationStamp:[self stamp:vstamp domain:d]];
		[vstamp release];

#if NS_TARGET_MAJOR == 3
		allInDomain = [d perform:sel];
#else
		allInDomain = [d performSelector:sel];
#endif

		[self allStamp:allInDomain domain:d addToList:all];
		if (allInDomain != nil) [allInDomain release];
	}
	[threadLock unlock];
	return all;
}

- (LUArray *)allGroupsWithUser:(char *)name
{
	LUArray *all;
	LUArray *allInDomain;
	LUNIDomain *d;
	LUDictionary *vstamp;
	unsigned int i, len;
	unsigned int j, jlen;
	NSArray *lookupChain;

	all = [[LUArray alloc] init];
	[threadLock lock];
	len = [chain[(int)LUCategoryInitgroups] count];
	if (len > 0)
	{
		lookupChain = chain[(int)LUCategoryInitgroups];
	}
	else
	{
		lookupChain = globalChain;
		len = [lookupChain count];
	}

	for (i = 0; i < len; i++)
	{
		d = [lookupChain objectAtIndex:i];

		vstamp = [[LUDictionary alloc] init];
		[vstamp setBanner:"NIAgent validation stamp"];
		[all addValidationStamp:[self stamp:vstamp domain:d]];
		[vstamp release];

		allInDomain = [d allGroupsWithUser:name];
		jlen = 0;
		if (allInDomain != nil) jlen = [allInDomain count];
		for (j = 0; j < jlen; j++)
		{
			[all addObject:
				[self stamp:[allInDomain objectAtIndex:j] domain:d]];
		}
		if (allInDomain != nil) [allInDomain release];
	}
	[threadLock unlock];
	return all;
}

- (LUDictionary *)serviceWithName:(char *)name
	protocol:(char *)prot
{
	LUDictionary *item = nil;
	LUNIDomain *d;
	unsigned int i, len;
	NSArray *lookupChain;

	[threadLock lock];
	len = [chain[(int)LUCategoryService] count];
	if (len > 0)
	{
		lookupChain = chain[(int)LUCategoryService];
	}
	else
	{
		lookupChain = globalChain;
		len = [lookupChain count];
	}

	for (i = 0; i < len; i++)
	{
		d = [lookupChain objectAtIndex:i];
		item = [d serviceWithName:name protocol:prot];
		if (item != nil)
		{
			[self stamp:item domain:d];
			[threadLock unlock];
			return item;
		}
	}

	[threadLock unlock];
	return nil;
}

- (LUDictionary *)serviceWithNumber:(int *)number
	protocol:(char *)prot
{
	LUDictionary *item = nil;
	LUNIDomain *d;
	unsigned int i, len;
	NSArray *lookupChain;

	[threadLock lock];
	len = [chain[(int)LUCategoryService] count];
	if (len > 0)
	{
		lookupChain = chain[(int)LUCategoryService];
	}
	else
	{
		lookupChain = globalChain;
		len = [lookupChain count];
	}

	for (i = 0; i < len; i++)
	{
		d = [lookupChain objectAtIndex:i];
		item = [d serviceWithNumber:number protocol:prot];
		if (item != nil)
		{
			[self stamp:item domain:d];
			[threadLock unlock];
			return item;
		}
	}

	[threadLock unlock];
	return nil;
}

/*
 * Custom lookups 
 */
- (BOOL)isSecurityEnabledForOption:(char *)option
{
	LUNIDomain *d;
	unsigned int i, len;

	[threadLock lock];
	len = [globalChain count];
	for (i = 0; i < len; i++)
	{
		d = [globalChain objectAtIndex:i];
		if ([d isSecurityEnabledForOption:option])
		{
			[threadLock unlock];
			return YES;
		}
	}

	[threadLock	unlock];
	return NO;
}

- (BOOL)isNetwareEnabled
{
	LUNIDomain *d;
	unsigned int i, len;

	[threadLock lock];
	len = [globalChain count];
	for (i = 0; i < len; i++)
	{
		d = [globalChain objectAtIndex:i];
		if ([d checkNetwareEnabled])
		{
			[threadLock unlock];
			return YES;
		}
	}

	[threadLock	unlock];
	return NO;
}

/*
 * All methods below just call the lookup methods above
 */

- (LUDictionary *)userWithName:(char *)name
{
	return [self item:name
		method:@selector(userWithName:) category:LUCategoryUser];
}

- (LUDictionary *)userWithNumber:(int *)number
{
	return [self item:number
		method:@selector(userWithNumber:) category:LUCategoryUser];
}

- (LUArray *)allUsers
{
	return [self all:@selector(allUsers) category:LUCategoryUser];
}

- (LUDictionary *)groupWithName:(char *)name
{
	return [self item:name 
		method:@selector(groupWithName:) category:LUCategoryGroup];
}

- (LUDictionary *)groupWithNumber:(int *)number
{
	return [self item:number
		method:@selector(groupWithNumber:) category:LUCategoryGroup];
}

- (LUArray *)allGroups
{
	return [self all:@selector(allGroups) category:LUCategoryGroup];
}

- (LUDictionary *)hostWithName:(char *)name
{
	return [self item:name
		method:@selector(hostWithName:) category:LUCategoryHost];
}

- (LUDictionary *)hostWithInternetAddress:(struct in_addr *)addr
{
	return [self item:addr
		method:@selector(hostWithInternetAddress:) category:LUCategoryHost];
}

- (LUDictionary *)hostWithEthernetAddress:(struct ether_addr *)addr
{
	return [self item:addr
		method:@selector(hostWithEthernetAddress:) category:LUCategoryHost];
}

- (LUArray *)allHosts
{
	return [self all:@selector(allHosts) category:LUCategoryHost];
}

- (LUDictionary *)networkWithName:(char *)name
{
	return [self item:name
		method:@selector(networkWithName:) category:LUCategoryNetwork];
}

- (LUDictionary *)networkWithInternetAddress:(struct in_addr *)addr
{
	return [self item:addr method:@selector(networkWithInternetAddress:)
		category:LUCategoryNetwork];
}

- (LUArray *)allNetworks
{
	return [self all:@selector(allNetworks) category:LUCategoryNetwork];
}

- (LUArray *)allServices
{
	return [self all:@selector(allServices) category:LUCategoryService];
}

- (LUDictionary *)protocolWithName:(char *)name
{
	return [self item:name
		method:@selector(protocolWithName:) category:LUCategoryProtocol];
}

- (LUDictionary *)protocolWithNumber:(int *)number
{
	return [self item:number
		method:@selector(protocolWithNumber:) category:LUCategoryProtocol];
}

- (LUArray *)allProtocols 
{
	return [self all:@selector(allProtocols) category:LUCategoryProtocol];
}

- (LUDictionary *)rpcWithName:(char *)name
{
	return [self item:name
		method:@selector(rpcWithName:) category:LUCategoryRpc];
}

- (LUDictionary *)rpcWithNumber:(int *)number
{
	return [self item:number
		method:@selector(rpcWithNumber:) category:LUCategoryRpc];
}

- (LUArray *)allRpcs
{
	return [self all:@selector(allRpcs) category:LUCategoryRpc];
}

- (LUDictionary *)mountWithName:(char *)name
{
	return [self item:name
		method:@selector(mountWithName:) category:LUCategoryMount];
}

- (LUArray *)allMounts
{
	return [self all:@selector(allMounts) category:LUCategoryMount];
}

- (LUDictionary *)printerWithName:(char *)name
{
	return [self item:name
		method:@selector(printerWithName:) category:LUCategoryPrinter];
}

- (LUArray *)allPrinters
{
	return [self all:@selector(allPrinters) category:LUCategoryPrinter];
}

- (LUDictionary *)bootparamsWithName:(char *)name
{
	return [self item:name
		method:@selector(bootparamsWithName:) category:LUCategoryBootparam];
}

- (LUArray *)allBootparams
{
	return [self all:@selector(allBootparams) category:LUCategoryBootparam];
}

- (LUDictionary *)bootpWithInternetAddress:(struct in_addr *)addr
{
	return [self item:addr
		method:@selector(bootpWithInternetAddress:) category:LUCategoryBootp];
}

- (LUDictionary *)bootpWithEthernetAddress:(struct ether_addr *)addr
{
	return [self item:addr method:@selector(bootpWithEthernetAddress:)
		 category:LUCategoryBootp];
}

- (LUDictionary *)aliasWithName:(char *)name
{
	return [self item:name
		method:@selector(aliasWithName:) category:LUCategoryAlias];
}

- (LUArray *)allAliases
{
	return [self all:@selector(allAliases) category:LUCategoryAlias];
}

- (LUDictionary *)netgroupWithName:(char *)name
{
	LUDictionary *item;
	LUDictionary *itemInDomain;
	LUNIDomain *d;
	BOOL found;
	unsigned int i, len;
	NSArray *lookupChain;

	found = NO;
	item = [[LUDictionary alloc] init];

	[threadLock lock];
	len = [chain[(int)LUCategoryNetgroup] count];
	if (len > 0)
	{
		lookupChain = chain[(int)LUCategoryNetgroup];
	}
	else
	{
		lookupChain = globalChain;
		len = [lookupChain count];
	}

	for (i = 0; i < len; i++)
	{
		d = [lookupChain objectAtIndex:i];
		itemInDomain = [d netgroupWithName:name];
		if (itemInDomain != nil)
		{
			found = YES;
			[self mergeNetgroup:itemInDomain into:item];
			[itemInDomain release];
		}
	}

	[threadLock unlock];

	if (found) return item;
	[item release];
	return nil;
}


@end
