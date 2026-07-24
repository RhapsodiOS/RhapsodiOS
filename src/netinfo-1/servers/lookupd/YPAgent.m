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
	YPAgent.m

	NIS lookup agent for lookupd

	Copyright (c) 1995, NeXT Computer Inc.
	All rights reserved.
	Written by Marc Majka
 */

#import "YPAgent.h"
#import "Syslog.h"
#import "LUGlobal.h"
#import "LUPrivate.h"
#import "Controller.h"
#import "LUArray.h"
#import "LUCachedDictionary.h"
#ifdef RPC_SUCCESS
#undef RPC_SUCCESS
#endif
#import <rpc/rpc.h>
#import <rpcsvc/yp_prot.h>
#import <rpcsvc/ypclnt.h>
#import <string.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <sys/types.h>
#import <net/if.h>
#import <netinet/if_ether.h>
#import <stdio.h>
#import <stdlib.h>
#import "stringops.h"

#if NS_TARGET_MAJOR == 3
#import <foundation/NSArray.h>
#import <foundation/NSString.h>
#else
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>
#endif

@interface FFParser (FFParserPrivate)
- (char **)tokensFromLine:(const char *)data separator:(const char *)sep;
@end

extern char *ether_ntoa(struct ether_addr *);
extern int close(int);
extern char *nettoa(unsigned long);

extern unsigned long sys_address(void);
#define BUFSIZE 8192

static YPAgent *_sharedYPAgent = nil;

@implementation YPAgent

- (char *)currentServerName
{
	struct in_addr server;
	struct sockaddr_in query;
	CLIENT *client;
	int sock = RPC_ANYSOCK;
	enum clnt_stat rpc_stat;
	struct ypbind_resp response;
	struct timeval tv = { 10, 0 };
	char *key, *buf, *dn;
	int status, buflen, len;
	char **tokens = NULL;

	query.sin_family = AF_INET;
	query.sin_port = 0;
	query.sin_addr.s_addr = sys_address();
	bzero(query.sin_zero, 8);

	[controller rpcLock];

	client = clntudp_create(&query, YPBINDPROG, YPBINDVERS, tv, &sock);
	if (client == NULL)
	{
		[controller rpcUnlock];
		return NULL;
	}

	buflen = strlen(domainName);
	dn = malloc(buflen + 1);
	bcopy(domainName, dn, buflen);
	dn[buflen] = '\0';

	rpc_stat = clnt_call(client, YPBINDPROC_DOMAIN,
	    xdr_domainname, &dn,
		xdr_ypbind_resp, &response, tv);

	free(dn);
	if (rpc_stat != RPC_SUCCESS)
	{
		[controller rpcUnlock];
		return NULL;
	}

	server = response.ypbind_respbody.ypbind_bindinfo.ypbind_binding_addr;
	clnt_destroy(client);
	close(sock);

	[controller rpcUnlock];

	key = inet_ntoa(server);
	buf = NULL;

	/* NIS client doesn't support multi-threaded access */
	[threadLock lock]; // locked {
	status = yp_match(domainName, "hosts.byaddr",
		key, strlen(key), &buf, &buflen);

	freeString(currentServerName);
	currentServerName = NULL;

	if ((status != 0) || (buflen <= 0))
	{
		currentServerName = copyString(key);
	}
	else
	{
		/* pull out the host name */
		tokens = [parser tokensFromLine:buf separator:" \t"];
		if (tokens == NULL) len = 0;
		else len = listLength(tokens);

		if (len < 2)
		{
			currentServerName = copyString(key);
		}
		else
		{
			currentServerName = copyString(tokens[1]);
		}

		freeList(tokens);
		tokens = NULL;
	}

	if (status != 0)
	{
		freeString(buf);
		buf = NULL;
	}

	[threadLock unlock]; // } unlocked

	return currentServerName;
}

- (YPAgent *)init
{
	char *dn;
	LUDictionary *config;
	BOOL globalHasAge;
	BOOL agentHasAge;
	time_t agentAge;
	time_t globalAge;

	if (didInit) return self;

	yp_get_default_domain(&dn);
	if (dn == NULL)
	{
		[self dealloc];
		return nil;
	}

	[super init];
	domainName = copyString(dn);
	stats = [[LUDictionary alloc] init];
	[stats setBanner:"YPAgent statistics"];
	[stats setValue:"Network_Information_Service"
		forKey:"information_system"];
	[stats setValue:domainName forKey:"domain_name"];

	mapValidationTable = [[NSMutableDictionary alloc] init];

	threadLock = [[NSRecursiveLock alloc] init];
	parser = [[FFParser alloc] init];
	[self currentServerName];

	agentAge = 0;
	agentHasAge = NO;
	config = [controller configurationForAgent:"YPAgent"];
	if (config != nil)
	{
		if ([config valueForKey:"ValidationLatency"] != NULL)
		{
			agentAge = [config unsignedLongForKey:"ValidationLatency"];
			agentHasAge = YES;
		}
		[config release];
	}

	globalAge = 0;
	globalHasAge = NO;
	config = [controller configurationForAgent:NULL];
	if (config != nil)
	{
		if ([config valueForKey:"ValidationLatency"] != NULL)
		{
			globalAge = [config unsignedLongForKey:"ValidationLatency"];
			globalHasAge = YES;
		}
		[config release];
	}

	validationLatency = 15;

	if (agentHasAge) validationLatency = agentAge;
	else if (globalHasAge) validationLatency = globalAge;

	return self;
}

+ (YPAgent *)alloc
{
	char str[128];

	if (_sharedYPAgent != nil)
	{
		[_sharedYPAgent retain];
		return _sharedYPAgent;
	}

	_sharedYPAgent = [super alloc];
	_sharedYPAgent = [_sharedYPAgent init];
	if (_sharedYPAgent == nil) return nil;

	sprintf(str, "Allocated YPAgent 0x%x\n", (int)_sharedYPAgent);
	[lookupLog syslogDebug:str];

	return _sharedYPAgent;
}

- (const char *)name
{
	return "Network_Information_Service";
}

- (const char *)shortName
{
	return "YPAgent";
}

- (void)dealloc
{
	char str[128];

	freeString(currentServerName);
	currentServerName = NULL;

	freeString(domainName);
	domainName = NULL;

	if (threadLock != nil) [threadLock release];
	if (stats != nil) [stats release];
	if (mapValidationTable != nil) [mapValidationTable release];
	if (parser != nil) [parser release];

	sprintf(str, "Deallocated YPAgent 0x%x\n", (int)self);
	[lookupLog syslogDebug:str];

	[super dealloc];

	_sharedYPAgent = nil;
}

- (LUDictionary *)statistics
{
	[stats setValue:[self currentServerName] forKey:"current_server"];
	return stats;
}

- (void)resetStatistics
{
	if (stats != nil) [stats release];
	stats = [[LUDictionary alloc] init];
	[stats setBanner:"YPAgent statistics"];
	[stats setValue:"Network_Information_Service"
		forKey:"information_system"];
	[stats setValue:domainName forKey:"domain_name"];
}

- (char *)orderNumberForMap:(const char *)map
{
	char *val;
	int vallen;
	int status;
	char *out;
	struct timeval now;
	time_t lastTime;
	time_t age;
	NSMutableArray *mapEntry;
	NSString *mapString;
	NSString *orderNumberString;
	NSString *timeString;
	char scratch[64];

	mapString = [[NSString alloc] initWithCString:map];
	mapEntry = [mapValidationTable objectForKey:mapString];

	if (mapEntry != nil)
	{
		sprintf(scratch, "%s", [[mapEntry objectAtIndex:1] cString]);
		sscanf(scratch, "%lu", &lastTime);
		gettimeofday(&now, (struct timezone *)NULL);
		age = now.tv_sec - lastTime;
		if (age <= validationLatency)
		{
			[mapString release];
			sprintf(scratch, "%s", [[mapEntry objectAtIndex:0] cString]);
			out = copyString(scratch);
			return out;
		}

		[mapValidationTable removeObjectForKey:mapString];
	}

	/* NIS client doesn't support multi-threaded access */
	[threadLock lock]; // locked {[
	status = yp_match(domainName, map, "YP_LAST_MODIFIED", 16, &val, &vallen);
	if ((status != 0) || (vallen <= 0))
	{
		[mapString release];
		[threadLock unlock]; // ] unlocked
		return copyString("");
	}

	out = malloc(vallen + 1);
	bcopy(val, out, vallen);
	out[vallen] = '\0';
	[threadLock unlock]; // } unlocked

	orderNumberString = [[NSString alloc] initWithCString:out];
	sprintf(scratch, "%u", now.tv_sec);
	timeString = [[NSString alloc] initWithCString:scratch];

	mapEntry = [[NSMutableArray alloc] init];
	[mapEntry addObject:orderNumberString];
	[mapEntry addObject:timeString];

	[mapValidationTable setObject:mapEntry forKey:mapString];
	[mapEntry release];
	[mapString release];

	return out;
}

- (LUDictionary *)stamp:(LUDictionary *)item
	map:(char *)map
	server:(char *)name
	order:(char *)order
{
	char *ord;

	if (item == nil) return nil;

	[item setAgent:self];
	[item setValue:"NIS" forKey:"_lookup_info_system"];
	[item setValue:domainName forKey:"_lookup_NIS_domain"];

	if (name == NULL)
		[item setValue:[self currentServerName] forKey:"_lookup_NIS_server"];
	else
		[item setValue:name forKey:"_lookup_NIS_server"];

	[item setValue:map forKey:"_lookup_NIS_map"];
	if (order == NULL)
	{
		ord = [self orderNumberForMap:map];
		[item setValue:ord forKey:"_lookup_NIS_order"];
		freeString(ord);
		ord = NULL;
	}
	else [item setValue:order forKey:"_lookup_NIS_order"];

	return item;
}

- (LUDictionary *)parse:(char *)buf
	map:(char *)map
	category:(LUCategory)cat
	server:(char *)name
	order:(char *)order
{
	LUDictionary *item;
	char scratch[256];
	
	if (buf == NULL) return nil;
	item = [parser parse:buf category:cat];
	sprintf(scratch, "YPAgent: %s %s",
		[self categoryName:cat], [item valueForKey:"name"]);
	[item setBanner:scratch];

	return [self stamp:item map:map server:name order:order];
}

- (BOOL)isValid:(LUDictionary *)item
{
	char *oldOrder;
	char *newOrder;
	char *mapName;
	BOOL ret;

	if (item == nil) return NO;

	mapName = [item valueForKey:"_lookup_NIS_map"];
	if (mapName == NULL) return NO;

	oldOrder = [item valueForKey:"_lookup_NIS_order"];
	if (oldOrder == NULL) return NO;
	if (oldOrder[0] == '\0') return NO;

	newOrder = [self orderNumberForMap:mapName];
	ret = YES;
	if (strcmp(oldOrder, newOrder)) ret = NO;
	freeString(newOrder);
	newOrder = NULL;
	return ret;
}

/*
 * These methods do NIS lookups on behalf of all calls
 */

- (LUDictionary *)itemWithName:(char *)name
	map:(char *)map
	category:(LUCategory)cat
{
	char *val = NULL;
	int vallen, keylen;
	int status;
	char scratch[4096];

	keylen = strlen(name);

	/* NIS client doesn't support multi-threaded access */
	[threadLock lock]; // locked {[
	status = yp_match(domainName, map, name, keylen, &val, &vallen);
	if ((status != 0) || (vallen <= 0))
	{
		[threadLock unlock]; // ] unlocked
		return nil;
	}

	if (cat == LUCategoryNetgroup)
	{
		bcopy(name, scratch, keylen);
		scratch[keylen] = ' ';
		bcopy(val, scratch+keylen+1, vallen);
		scratch[keylen + vallen + 1] = '\0';
	}
	else
	{
		bcopy(val, scratch, vallen);
		scratch[vallen] = '\0';
	}

	freeString(val);
	val = NULL;

	[threadLock unlock]; // } unlocked

	return [self parse:scratch 
		map:map category:cat server:NULL order:NULL];
}

- (LUArray *)allItemsInMap:(char *)map
	category:(LUCategory)cat
{
	LUArray *all;
	LUDictionary *anObject;
	LUDictionary *vstamp;
	char *key, *val, *lastkey;
	int status, keylen, vallen, lastlen;
	char scratch[4096];
	char *curr;
	char *order;

	all = [[LUArray alloc] init];
	sprintf(scratch, "YPAgent: all %s", [self categoryName:cat]);
	[all setBanner:scratch];

	curr = [self currentServerName];

	key = NULL;
	val = NULL;
	lastkey = NULL;

	/* NIS client doesn't support multi-threaded access */
	[threadLock lock]; // locked {[
	status = yp_first(domainName, map, &key, &keylen, &val, &vallen);
	if (status != 0)
	{
		[threadLock unlock]; // ] unlocked
		[all release];
		return nil;
	}

	order = [self orderNumberForMap:map];

	vstamp = [[LUDictionary alloc] init];
	[vstamp setBanner:"YPAgent validation stamp"];
	[all addValidationStamp:
		[self stamp:vstamp map:map server:curr order:order]];
	[vstamp release];

	while (status == 0)
	{
		switch (cat)
		{
			case LUCategoryNetgroup:
				bcopy(key, scratch, keylen);
				scratch[keylen] = ' ';
				bcopy(val, scratch+keylen+1, vallen);
				scratch[keylen + vallen + 1] = '\0';
				break;
			case LUCategoryAlias:
				bcopy(key, scratch, keylen);
				scratch[keylen] = ':';
				scratch[keylen + 1] = ' ';
				bcopy(val, scratch+keylen+2, vallen);
				scratch[keylen + vallen + 2] = '\0';
				break;
			default:
				bcopy(val, scratch, vallen);
				scratch[vallen] = '\0';
		}

		freeString(val);
		val = NULL;

		anObject = [self parse:scratch
			map:map category:cat server:curr order:order];
		if (anObject != nil)
		{
			[all addObject:anObject];
			[anObject release];
		}

		freeString(lastkey);
		lastkey = key;
		lastlen = keylen;

		status = yp_next(domainName, map,
		    lastkey, lastlen, &key, &keylen, &val, &vallen);
	}

	[threadLock unlock]; // } unlocked

	freeString(lastkey);
	lastkey = NULL;

	freeString(order);
	order = NULL;
	return all;
}

- (LUDictionary *)hostWithEthernetAddress:(struct ether_addr *)addr
{
	char **etherAddrs;
	LUDictionary *ether;
	int i, len;

	/* Try all possible variations on leading zeros in the address */
	etherAddrs = [self variationsOfEthernetAddress:addr];
	len = listLength(etherAddrs);
	for (i = 0; i < len; i++)
	{
		ether = [self itemWithName:etherAddrs[i]
			map:"ethers.byaddr" category:LUCategoryEthernet];

		if (ether != nil)
		{
			freeList(etherAddrs);
			etherAddrs = NULL;
			return [self hostWithName:[ether valueForKey:"name"]];
		}
	}
	freeList(etherAddrs);
	etherAddrs = NULL;
	return nil;
}

- (LUDictionary *)serviceWithName:(char *)name
	protocol:(char *)prot
{
	LUArray *all;
	LUDictionary *service;
	char **vals;
	int i, len;

	all = [self allServices];
	if (all == nil) return nil;

	len = [all count];
	for (i = 0; i < len; i++)
	{
		service = [all objectAtIndex:i];
		vals = [service valuesForKey:"name"];
		if (vals == NULL) continue;
		if (listIndex(name, vals) == IndexNull) continue;

		vals = [service valuesForKey:"protocol"];
		if (vals == NULL) continue;
		if (prot == NULL)
		{
			[service retain];
			[all release];
			return service;
		}

		if (listIndex(prot, vals) == IndexNull) continue;

		[service retain];
		[all release];
		return service;
	}

	[all release];
	return nil;
}

- (LUDictionary *)serviceWithNumber:(int *)number
	protocol:(char *)prot
{
	LUArray *all;
	LUDictionary *service;
	char **vals;
	char num[32];
	int i, len;

	all = [self allServices];
	if (all == nil) return nil;

	len = [all count];
	if (len == 0) return nil;

	sprintf(num, "%d", *number);

	for (i = 0; i < len; i++)
	{
		service = [all objectAtIndex:i];
		vals = [service valuesForKey:"port"];
		if (vals == NULL) continue;
		if (listIndex(num, vals) == IndexNull) continue;

		vals = [service valuesForKey:"protocol"];
		if (vals == NULL) continue;
		if (prot == NULL)
		{
			[service retain];
			[all release];
			return service;
		}

		if (listIndex(prot, vals) == IndexNull) continue;

		[service retain];
		[all release];
		return service;
	}

	[all release];
	return nil;
}

- (LUDictionary *)bootpWithEthernetAddress:(struct ether_addr *)addr
{
	char **etherAddrs = NULL;
	LUDictionary *bootp;
	int i, len;

	/* Try all possible variations on leading zeros in the address */
	etherAddrs = [self variationsOfEthernetAddress:addr];
	len = listLength(etherAddrs);
	for (i = 0; i < len; i++)
	{
		/* XXX there is no "bootptab.byether" map */
		bootp = [self itemWithName:etherAddrs[i]
			map:"bootptab.byether" category:LUCategoryBootp];

		if (bootp != nil)
		{
			freeList(etherAddrs);
			etherAddrs = NULL;
			return bootp;
		}
	}
	freeList(etherAddrs);
	etherAddrs = NULL;
	return nil;
}

- (LUDictionary *)aliasWithName:(char *)name
{
	LUDictionary *alias;

	alias = [self itemWithName:name map:"mail.aliases"
		category:LUCategoryAlias];
	if (alias == nil) return nil;
	[alias setValue:"0" forKey:"alias_local"];
	return alias;
}

- (LUArray *)allAliases
{
	LUArray *all;
	int i, len;

	all = [self allItemsInMap:"mail.aliases" category:LUCategoryAlias];
	if (all == nil) return nil;

	len = [all count];
	for (i = 0; i < len; i++)
	{
		[[all objectAtIndex:i] setValue:"0" forKey:"alias_local"];
	}

	return all;
}

/*
 * All methods below just call itemWithName or allItemsInMap
 */

- (LUDictionary *)userWithName:(char *)name
{
	return [self itemWithName:name
		map:"passwd.byname" category:LUCategoryUser];
}

- (LUDictionary *)userWithNumber:(int *)number
{
	char str[32];

	sprintf(str, "%d", *number);
	return [self itemWithName:str
		map:"passwd.byuid" category:LUCategoryUser];
}

- (LUArray *)allUsers
{
	return [self allItemsInMap:"passwd.byname" category:LUCategoryUser];
}

- (LUDictionary *)groupWithName:(char *)name
{
	return [self itemWithName:name
		map:"group.byname" category:LUCategoryGroup];
}

- (LUDictionary *)groupWithNumber:(int *)number
{
	char str[32];

	sprintf(str, "%d", *number);
	return [self itemWithName:str
		map:"group.bygid" category:LUCategoryGroup];
}

- (LUArray *)allGroups
{
	return [self allItemsInMap:"group.byname" category:LUCategoryGroup];
}

- (LUDictionary *)hostWithName:(char *)name
{
	return [self itemWithName:name
		map:"hosts.byname" category:LUCategoryHost];
}

- (LUDictionary *)hostWithInternetAddress:(struct in_addr *)addr
{
	char str[32];

	sprintf(str, "%s", inet_ntoa(*addr));
	return [self itemWithName:str
		map:"hosts.byaddr" category:LUCategoryHost];
}
		
- (LUArray *)allHosts
{
	return [self allItemsInMap:"hosts.byname" category:LUCategoryHost];
}

- (LUDictionary *)networkWithName:(char *)name
{
	return [self itemWithName:name
		map:"networks.byname" category:LUCategoryNetwork];
}

- (LUDictionary *)networkWithInternetAddress:(struct in_addr *)addr
{
	char str[32];

	sprintf(str, "%s", nettoa(addr->s_addr));
	return [self itemWithName:str
		map:"networks.byaddr" category:LUCategoryNetwork];
}

- (LUArray *)allNetworks
{
	return [self allItemsInMap:"networks.byname" category:LUCategoryNetwork];
}

- (LUArray *)allServices
{
	return [self allItemsInMap:"services.byname" category:LUCategoryService];
}

- (LUDictionary *)protocolWithName:(char *)name
{
	return [self itemWithName:name
		map:"protocols.byname" category:LUCategoryProtocol];
}

- (LUDictionary *)protocolWithNumber:(int *)number
{
	char str[32];

	sprintf(str, "%d", *number);
	return [self itemWithName:str
		map:"protocols.bynumber" category:LUCategoryProtocol];
}

- (LUArray *)allProtocols 
{
	return [self allItemsInMap:"protocols.byname" category:LUCategoryProtocol];
}

- (LUDictionary *)rpcWithName:(char *)name
{
	/* XXX there is no "rpc.byname" map, although we build one under Rhapsody */
	return [self itemWithName:name
		map:"rpc.byname" category:LUCategoryRpc];
}

- (LUDictionary *)rpcWithNumber:(int *)number
{
	char str[32];

	sprintf(str, "%d", *number);
	return [self itemWithName:str
		map:"rpc.bynumber" category:LUCategoryRpc];
}

- (LUArray *)allRpcs
{
	return [self allItemsInMap:"rpc.bynumber" category:LUCategoryRpc];
}

- (LUDictionary *)mountWithName:(char *)name
{
	/* XXX there is no "mounts.byname" map */
	return [self itemWithName:name
		map:"mounts.byname" category:LUCategoryMount];
}

- (LUArray *)allMounts
{
	/* XXX there is no "mounts.byname" map */
	return [self allItemsInMap:"mounts.byname" category:LUCategoryMount];
}

- (LUDictionary *)printerWithName:(char *)name
{
	/* XXX there is no "printcap.byname" map */
	return [self itemWithName:name
		map:"printcap.byname" category:LUCategoryPrinter];
}

- (LUArray *)allPrinters
{
	/* XXX there is no "printcap.byname" map */
	return [self allItemsInMap:"printcap.byname" category:LUCategoryPrinter];
}

- (LUDictionary *)bootparamsWithName:(char *)name
{
	/* XXX there is no "bootparams.byname" map */
	return [self itemWithName:name
		map:"bootparams.byname" category:LUCategoryBootparam];
}

- (LUDictionary *)bootpWithInternetAddress:(struct in_addr *)addr
{
	char str[32];

	sprintf(str, "%s", inet_ntoa(*addr));
	/* XXX there is no "bootptab.byip" map */
	return [self itemWithName:str
		map:"bootptab.byip" category:LUCategoryBootp];
}

- (LUDictionary *)netgroupWithName:(char *)name
{
	return [self itemWithName:name
		map:"netgroup" category:LUCategoryNetgroup];
}

@end
