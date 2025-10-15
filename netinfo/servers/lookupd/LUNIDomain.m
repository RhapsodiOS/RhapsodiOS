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
	LUNIDomain.m

	NetInfo client for lookupd
	Copyright (c) 1995, NeXT Computer Inc.
	All rights reserved.
	Written by Marc Majka
 */

#import "LUNIDomain.h"
#import "LUGlobal.h"
#import "LUPrivate.h"
#import "LUCachedDictionary.h"
#import "Controller.h"
#import "Syslog.h"
#import "stringops.h"
#ifdef RPC_SUCCESS
#undef RPC_SUCCESS
#endif
#import <netinfo/ni.h>
#import <stdio.h>
#import <sys/param.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <sys/types.h>
#import <net/if.h>
#import <netinet/if_ether.h>
#import <string.h>
#import <unistd.h>
#import <stdlib.h>

extern char *nettoa(unsigned long);
extern unsigned long sys_address(void);

#define IAmLocal 0
#define IAmNotLocal 1
#define IDontKnow 2

@implementation LUNIDomain

- (void)initKeys
{
	userKeys = NULL;
	userKeys = appendString("name", userKeys);
	userKeys = appendString("passwd", userKeys);
	userKeys = appendString("uid", userKeys);
	userKeys = appendString("gid", userKeys);
	userKeys = appendString("class", userKeys);
	userKeys = appendString("change", userKeys);
	userKeys = appendString("expire", userKeys);
	userKeys = appendString("realname", userKeys);
	userKeys = appendString("home", userKeys);
	userKeys = appendString("shell", userKeys);

	groupKeys = NULL;
	groupKeys = appendString("name", groupKeys);
	groupKeys = appendString("passwd", groupKeys);
	groupKeys = appendString("gid", groupKeys);
	groupKeys = appendString("users", groupKeys);

	hostKeys = NULL;
	hostKeys = appendString("name", hostKeys);
	hostKeys = appendString("ip_address", hostKeys);
	hostKeys = appendString("en_address", hostKeys);
	hostKeys = appendString("bootfile", hostKeys);
	hostKeys = appendString("bootparams", hostKeys);

	bootparamKeys = NULL;
	bootparamKeys = appendString("name", bootparamKeys);
	bootparamKeys = appendString("bootparams", bootparamKeys);

	networkKeys = NULL;
	networkKeys = appendString("name", networkKeys);
	networkKeys = appendString("address", networkKeys);

	serviceKeys = NULL;
	serviceKeys = appendString("name", serviceKeys);
	serviceKeys = appendString("port", serviceKeys);
	serviceKeys = appendString("protocol", serviceKeys);

	protocolKeys = NULL;
	protocolKeys = appendString("name", protocolKeys);
	protocolKeys = appendString("number", protocolKeys);

	rpcKeys = NULL;
	rpcKeys = appendString("name", rpcKeys);
	rpcKeys = appendString("number", rpcKeys);

	mountKeys = NULL;
	mountKeys = appendString("name", mountKeys);
	mountKeys = appendString("dir", mountKeys);
	mountKeys = appendString("vfstype", mountKeys);
	mountKeys = appendString("opts", mountKeys);
	mountKeys = appendString("freq", mountKeys);
	mountKeys = appendString("passno", mountKeys);

	aliasKeys = NULL;
	aliasKeys = appendString("name", aliasKeys);
	aliasKeys = appendString("members", aliasKeys);
}

- (void)freeKeys
{
	freeList(userKeys);
	userKeys = NULL;
	freeList(groupKeys);
	groupKeys = NULL;
	freeList(hostKeys);
	hostKeys = NULL;
	freeList(networkKeys);
	networkKeys = NULL;
	freeList(serviceKeys);
	serviceKeys = NULL;
	freeList(protocolKeys);
	protocolKeys = NULL;
	freeList(rpcKeys);
	rpcKeys = NULL;
	freeList(mountKeys);
	mountKeys = NULL;
	freeList(bootparamKeys);
	bootparamKeys = NULL;
	freeList(aliasKeys);
	aliasKeys = NULL;
}

- (void *)handleForName:(char *)name
{
	void *domain, *d0, *d1;
	char *p, *address;
	struct sockaddr_in server;
	char *lead, str[256];
	int i;
	ni_status status;
	char **path;

	if (name == NULL) return NULL;

	/*
	 * names may be of the following formats:
	 * path -> domain with given pathname
	 * niserver:tag -> connect by tag, localhost
	 * niserver:tag@address -> connect by tag
	 * nidomain:path -> domain with given pathname
	 * nidomain:path@address -> path relative to local domain at host
	 */

	p = strchr(name, ':');
	if (p == NULL)
	{
		[controller rpcLock];
		status = ni_open(NULL, name, &domain);
		[controller rpcUnlock];
		if (status != NI_OK)
		{
			sprintf(str, "NetInfo open failed for domain %s", name);
			[lookupLog syslogAlert:str];
			return NULL;
		}
		return domain;
	}

	p++;

	address = strchr(p, '@');
	if (address == NULL)
	{
		server.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	}
	else
	{
		address++;
		server.sin_addr.s_addr = inet_addr(address);
		if (server.sin_addr.s_addr == -1)
		{
			sprintf(str, "NetInfo open failed for %s (bad address %s)",
				name, address);
			[lookupLog syslogAlert:str];
			return NULL;
		}
	}

	for (i = 0; (p[i] != '@') && (p[i] != '\0'); i++);
	if (i == 0)
	{
		sprintf(str,
			"NetInfo open failed for %s (no tag or domain name)", name);
		[lookupLog syslogAlert:str];
		return NULL;
	}

	lead = malloc(i + 1);
	strncpy(lead, p, i);
	lead[i] = '\0';

	if (!strncmp(name, "nidomain:", 9))
	{
		if (lead[0] != '/')
		{
			sprintf(str, "NetInfo domain %s is not an absolute domain name",
				lead);
			[lookupLog syslogAlert:str];
			free(lead);
			return NULL;
		}

		d0 = ni_connect(&server, "local");
		if (d0 == NULL)
		{
			sprintf(str,
				"NetInfo open failed at host %s", address);
			[lookupLog syslogAlert:str];
			free(lead);
			return NULL;
		}

		status = NI_OK;
		while (status == NI_OK)
		{
			status = ni_open(d0, "..", &d1);
			if (status == NI_OK)
			{
				ni_free(d0);
				d0 = d1;
			}
		}

		if (!strcmp(lead, "/"))
		{
			free(lead);
			return d0;
		}

		path = explode(lead+1, '/');

		for (i = 0; path[i] != NULL; i++)
		{
			status = ni_open(d0, path[i], &d1);
			if (status != NI_OK)
			{
				sprintf(str,
					"NetInfo open failed for domain %s at host %s (%s)",
					path[i], address, ni_error(status));
				[lookupLog syslogAlert:str];
				free(lead);
				freeList(path);
				return NULL;
			}
			ni_free(d0);
			d0 = d1;
		}

		free(lead);
		freeList(path);
		return d0;
	}
		
	if (!strncmp(name, "niserver:", 9))
	{
		d0 = ni_connect(&server, lead);
		if (d0 == NULL)
		{
			sprintf(str,
				"NetInfo open failed at host %s tag %s", address, lead);
			[lookupLog syslogAlert:str];
			free(lead);
			return NULL;
		}
		free(lead);
		return d0;
	}

	return NULL;
}

/*
 * Initialize a client for a domain given an open handle
 */
- (LUNIDomain *)initWithHandle:(void *)handle
{
	[super init];

	parent = nil;
	iAmRoot = NO;
	mustSetChecksumPassword = YES;
	isLocal = IDontKnow;
	masterHostName = NULL;
	masterTag = NULL;
	currentServerHostName = NULL;
	currentServerAddress = NULL;
	currentServerTag = NULL;
	mustSetMaxChecksumAge = YES;
	lastChecksum = (unsigned int)-1;
	lastChecksumFetch.tv_sec = 0;
	lastChecksumFetch.tv_usec = 0;
	maxChecksumAge = 15;
	[self initKeys];
	ni = handle;
	return self;
}

/*
 * Initialize a client for a domain by name
 */
- (LUNIDomain *)initWithDomainNamed:(char *)domainName
{
	void *d;

	d = [self handleForName:domainName];
	if (d == NULL) return nil;

	return [self initWithHandle:d];
}

- (void)dealloc
{
	freeString(myDomainName);
	myDomainName = NULL;
	freeString(masterHostName);
	masterHostName = NULL;
	freeString(masterTag);
	masterTag = NULL;
	freeString(currentServer);
	currentServer = NULL;
	freeString(currentServerHostName);
	currentServerHostName = NULL;
	freeString(currentServerAddress);
	currentServerAddress = NULL;
	freeString(currentServerTag);
	currentServerTag = NULL;
	[self freeKeys];
	ni_free(ni);
	[super dealloc];
}

- (void)setMaxChecksumAge:(time_t)age
{
	maxChecksumAge = age;
}

/*
 * Create a client for a domain's parent domain.
 * Returns nil if the domain is root.
 */
- (LUNIDomain *)parent
{
	ni_status status;
	void *handle;

	if (iAmRoot) return nil;
	if (parent != nil) return parent;

	[controller rpcLock];
	status = ni_open(ni, "..", &handle);
	[controller rpcUnlock];
	if (status != NI_OK)
	{
		iAmRoot = YES;
		return nil;
	}

	parent = [[LUNIDomain alloc] initWithHandle:handle];
	return parent;
}

/*
 * Is this domain the root domain?
 */
- (BOOL)isRootDomain
{
	return ([self parent] == nil);
}

/*
 * Is this a "local" domain?
 */
- (BOOL)isLocalDomain
{
	if (isLocal == IDontKnow)
	{
		if (strcmp([self masterTag], "local") == 0)
			isLocal = IAmLocal;
		else
			isLocal = IAmNotLocal;
	}
	if (isLocal == IAmLocal) return YES;
	return NO;
}

/*
 * Get a child's domain's name relative to this domain.
 */
- (char *)nameForChild:(LUNIDomain *)child
{
	char mtag[1024], str[64], *name, *p;
	ni_status status;
	ni_id dir;
	ni_namelist nl;
	int i, len;
	BOOL searching;

	if (child == nil) return NULL;

	sprintf(mtag, "%s", [child masterTag]);
	if (strcmp(mtag, "local") == 0)
	{
		/* look for child's ip_address */
		sprintf(str, "/machines/ip_address=%s", [child currentServerAddress]);
	}
	else
	{
		/* look for the child's master */
		sprintf(str, "/machines/%s", [child masterHostName]);
	}
	[controller rpcLock];
	status = ni_pathsearch(ni, &dir, str);
	[controller rpcUnlock];
	if (status != NI_OK) return NULL;

	/* get the "serves" property namelist */
	NI_INIT(&nl);
	[controller rpcLock];
	status = ni_lookupprop(ni, &dir, "serves", &nl);
	[controller rpcUnlock];
	if (status != NI_OK || nl.ni_namelist_len == 0) return NULL;

	/* walk through the serves property values */
	/* looking for <name>/<tag> */
	searching = YES;
	p = NULL;
	len = nl.ni_namelist_len;
	for (i = 0; i < len && searching; i++)
	{
		p = index(nl.ni_namelist_val[i], '/');

		if (strcmp(mtag, p+1) == 0)
		{
			/* BINGO - found the child domain */
			searching = NO;
		}
	}

	/* return nil if not found */
	if (searching)
	{
		ni_namelist_free(&nl);
		return NULL;
	}

	/* copy out the domain name */
	p[0] = '\0';
	i--; /* we went around the loop one extra time */

	name = copyString(nl.ni_namelist_val[i]);
	ni_namelist_free(&nl);
	return name;
}

/*
 * Domain name
 */
- (const char *)name
{
	char *myName;
	const char *parentName;

	if (myDomainName != NULL) return myDomainName;

	if ([self isRootDomain])
	{
		myDomainName = copyString("/");
		return myDomainName;
	}

	myName = [parent nameForChild:self];
	if (myName == NULL)
	{
		myDomainName = copyString("<?>");
		return myDomainName;
	}

	if ([parent isRootDomain])
	{
		myDomainName = malloc(strlen(myName) + 2);
		sprintf(myDomainName, "/%s", myName);	
		freeString(myName);
		return myDomainName;
	}

	parentName = [parent name];
	if (parentName == NULL)
	{
		myDomainName = malloc(strlen(myName) + 5);
		sprintf(myDomainName, "<?>/%s", myName);
		freeString(myName);
		return myDomainName;
	}

	myDomainName = malloc(strlen(parentName) + strlen(myName) + 2);
	sprintf(myDomainName, "%s/%s", parentName, myName);	
	freeString(myName);
	return myDomainName;
}

- (char *)currentServerAddress
{
	if (currentServerAddress == NULL) [self currentServer];
	return currentServerAddress;
}

/*
 * Look up the master's hostname from the master property
 */
- (char *)masterHostName
{
	ni_id dir;
	ni_namelist val;
	ni_status status;
	char *p;

	if (masterHostName != NULL) return masterHostName;
	dir.nii_object = 0;
	NI_INIT(&val);
	[controller rpcLock];
	status = ni_lookupprop(ni, &dir, "master", &val);
	[controller rpcUnlock];
	if (status != NI_OK)
	{
		[lookupLog syslogAlert:"Domain <?>: can't get master property"];
		return NULL;
	}
	if (val.ni_namelist_len == 0)
	{
		[lookupLog syslogAlert:"Domain <?>: master property has no value"];
		return NULL;
	}

	p = (char *)val.ni_namelist_val[0];
	while ((p[0] != '/') && (p[0] != '\0')) p++;
	if (p[0] != '/')
	{
		[lookupLog syslogAlert:"Domain <?>: malformend master property"];
		ni_namelist_free(&val);
		return NULL;
	}

	p[0] = '\0';
	p++;

	freeString(masterHostName);
	masterHostName = copyString(val.ni_namelist_val[0]);

	freeString(masterTag);
	masterTag = copyString(p);

	ni_namelist_free(&val);
	return masterHostName;
}

/*
 * Get up the master's tag
 * The real work is done in -masterHostName
 */
- (char *)masterTag
{
	if (masterTag == NULL)
	{
		[self masterHostName];
	}

	return masterTag;
}

/*
 * Get the current server's address, tag, and host name.
 */
- (char *)currentServer
{
	struct sockaddr_in addr;
	ni_name tag;
	ni_status status;
	LUDictionary *host;
	char *hName;
	char str[MAXHOSTNAMELEN];

	[controller rpcLock];
	status = ni_addrtag(ni, &addr, &tag);
	[controller rpcUnlock];
	if (status != NI_OK)
	{
		sprintf(str, "Domain %s: can't get address and tag of current server",
				[self name]);
		[lookupLog syslogAlert:str];
		ni_name_free(&tag);
		return NULL;
	}

	if ((addr.sin_addr.s_addr == currentServerIPAddr) &&
		(!strcmp(tag, currentServerTag)))
	{
		ni_name_free(&tag);
		return currentServer;
	}

	if (addr.sin_addr.s_addr == htonl(INADDR_LOOPBACK))
		addr.sin_addr.s_addr = sys_address();

	freeString(currentServer);
	currentServer = NULL;

	freeString(currentServerTag);
	currentServerTag = copyString(tag);
	ni_name_free(&tag);

	freeString(currentServerAddress);
	currentServerAddress = copyString(inet_ntoa(addr.sin_addr));

	freeString(currentServerHostName);
	currentServerHostName = NULL;

	currentServerIPAddr = addr.sin_addr.s_addr;

	host = [self entityForCategory:LUCategoryHost
		key:"ip_address" value:currentServerAddress selectedKeys:NULL];

	if (host != nil)
	{
		hName = [host valueForKey:"name"];
		if (hName != NULL) currentServerHostName = copyString(hName);
	}
	else
	{
		if (gethostname(str, MAXHOSTNAMELEN) >= 0)
			currentServerHostName = copyString(str);
	}

	if (currentServerHostName != NULL)
	{
		currentServer = malloc(strlen(currentServerHostName) + 
			strlen(currentServerTag) + 2);
		sprintf(currentServer, "%s/%s",
			currentServerHostName, currentServerTag);
	}
	else
	{
		currentServer = malloc(strlen(currentServerAddress) + 
			strlen(currentServerTag) + 2);
		sprintf(currentServer, "%s/%s",
			currentServerAddress, currentServerTag);
	}

	[host release];
	return currentServer;
}

/*
 * Get the current server's host name.
 */
- (char *)currentServerHostName
{

	if (currentServerAddress == NULL)
	{
		[self currentServerAddress];
	}

	return currentServerHostName;
}

/*
 * Get the current server's tag.
 */
- (char *)currentServerTag
{
	if (currentServerAddress == NULL)
	{
		[self currentServerAddress];
	}
	return currentServerTag;
}

/*
 * Get the server's checksum (can lag real checksum)
 */
- (unsigned long)checksum
{
	struct timeval now;
	time_t age;
	LUDictionary *config;
	BOOL globalHasAge;
	BOOL agentHasAge;
	time_t agentAge;
	time_t globalAge;

	if (mustSetMaxChecksumAge)
	{
		agentAge = 0;
		agentHasAge = NO;
		config = [controller configurationForAgent:"NIAgent"];
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

		if (agentHasAge) maxChecksumAge = agentAge;
		else if (globalHasAge) maxChecksumAge = globalAge;

		mustSetMaxChecksumAge = NO;
	}

	if ((maxChecksumAge == 0) || (lastChecksumFetch.tv_sec == 0))
		return [self currentChecksum];

	gettimeofday(&now, (struct timezone *)NULL);
	age = now.tv_sec - lastChecksumFetch.tv_sec;
	if (age > maxChecksumAge) return [self currentChecksum];

	return lastChecksum;
}

/*
 * Get the current server's checksum.
 */
- (unsigned long)currentChecksum
{
	ni_status status;
	ni_proplist pl;
	unsigned long sum;
	ni_index where;
	char str[256];

	if (mustSetChecksumPassword)
	{
		/* Special hack to only lookup the checksum */
		ni_setpassword(ni, "checksum");
		mustSetChecksumPassword = NO;
	}

	NI_INIT(&pl);
	[controller rpcLock];
	status = ni_statistics(ni, &pl);
	[controller rpcUnlock];

	/* checksum should be first (and only!) property */
	where = NI_INDEX_NULL;
	if (pl.ni_proplist_len > 0)
	{
		if (strcmp(pl.ni_proplist_val[0].nip_name, "checksum"))
			where = 0;
		else
			where = ni_proplist_match(pl, "checksum", NULL);
	}

	if (where == NI_INDEX_NULL)
	{
		sprintf(str, "Domain %s: can't get checksum", [self name]);
		[lookupLog syslogError: str];				
		ni_proplist_free(&pl);
		return (unsigned long)-1;
	}

	sscanf(pl.ni_proplist_val[where].nip_val.ni_namelist_val[0], "%lu", &sum);
	ni_proplist_free(&pl);

	lastChecksum = sum;
	gettimeofday(&lastChecksumFetch, (struct timezone *)NULL);

	return sum;
}

/*
 * Read a directory and turn it into a dictionary.
 * Coalesce duplicate keys.
 */
- (LUDictionary *)readDirectory:(unsigned long)d
	selectedKeys:(char **)keyList
{
	ni_id dir;
	ni_proplist pl;
	ni_status status;
	ni_property *p;
	int i, len;
	LUDictionary *dict;

	NI_INIT(&pl);
	dir.nii_object = d;
	[controller rpcLock];
	status = ni_read(ni, &dir, &pl);
	[controller rpcUnlock];
	if (status != NI_OK) return nil;

	dict = [[LUDictionary alloc] init];
	len = pl.ni_proplist_len;

	/* split this way to take the test out of the loop */
	if (keyList == NULL)
	{
		for (i = 0; i < len; i++)
		{
			p = &(pl.ni_proplist_val[i]);
			[dict addValues:p->nip_val.ni_namelist_val
				forKey:p->nip_name count:p->nip_val.ni_namelist_len];
		}
	}
	else
	{
		for (i = 0; i < len; i++)
		{
			p = &(pl.ni_proplist_val[i]);
			if (listIndex(p->nip_name, keyList) == IndexNull) continue;
			[dict addValues:p->nip_val.ni_namelist_val
				forKey:p->nip_name count:p->nip_val.ni_namelist_len];

		}
	}
	ni_proplist_free(&pl);
	return dict;
}

- (LUDictionary *)readDirectoryName:(char *)name
	selectedKeys:(char **)keyList
{
	ni_id root;
	ni_id dir;
	ni_status status;

	root.nii_object = 0;
	[controller rpcLock];
	status = ni_pathsearch(ni, &dir, name);
	[controller rpcUnlock];
	if (status != NI_OK) return nil;
	return [self readDirectory:dir.nii_object selectedKeys:keyList];
}

/*
 * Look up a directory given a key and a value, within a 
 * given category of objects (users, hosts, etc).
 *
 * Searches for the first directory with key=value.
 * Returns a dictionary, with all the directory's keys as
 * dictionary keys.  Values are always arrays, which may be
 * empty for keys with no values.  If the directory has 
 * duplicate keys, all values are coalesced in the array.
 */
- (LUDictionary *)entityForCategory:(LUCategory)cat
	key:(char *)aKey
	value:(char *)aVal
{
	return [self entityForCategory:cat key:aKey value:aVal selectedKeys:NULL];
}

/*
 * Look up a directory given a key and a value, within a 
 * given category of objects (users, hosts, etc).
 *
 * Searches for the first directory with key=value.
 * Returns a dictionary, with the directory's keys as
 * dictionary keys.  Only those keys in keyList are
 * included.  nil means that all keys are included in the
 * output.  Values are always arrays, which may be
 * empty for keys with no values.  If the directory has 
 * duplicate keys, all values are coalesced in the array.
 */
- (LUDictionary *)entityForCategory:(LUCategory)cat
	key:(char *)aKey
	value:(char *)aVal
	selectedKeys:(char **)keyList
{
	ni_id parent_dir;
	ni_status status;
	LUDictionary *dict;
	ni_idlist idl;
	char str[256];

	[controller rpcLock];
	switch (cat)
	{
		case LUCategoryUser:
			status = ni_pathsearch(ni, &parent_dir, "/users");
			break;
		case LUCategoryGroup:
			status = ni_pathsearch(ni, &parent_dir, "/groups");
			break;
		case LUCategoryHost:
			status = ni_pathsearch(ni, &parent_dir, "/machines");
			break;
		case LUCategoryNetwork:
			status = ni_pathsearch(ni, &parent_dir, "/networks");
			break;
		case LUCategoryService:
			status = ni_pathsearch(ni, &parent_dir, "/services");
			break;
		case LUCategoryProtocol:
			status = ni_pathsearch(ni, &parent_dir, "/protocols");
			break;
		case LUCategoryRpc:
			status = ni_pathsearch(ni, &parent_dir, "/rpcs");
			break;
		case LUCategoryMount:
			status = ni_pathsearch(ni, &parent_dir, "/mounts");
			break;
		case LUCategoryPrinter:
			status = ni_pathsearch(ni, &parent_dir, "/printers");
			break;
		case LUCategoryAlias:
			status = ni_pathsearch(ni, &parent_dir, "/aliases");
			break;
		case LUCategoryBootparam:
			status = ni_pathsearch(ni, &parent_dir, "/machines");
			break;
		case LUCategoryBootp:
			status = ni_pathsearch(ni, &parent_dir, "/machines");
			break;
		case LUCategoryNetDomain:
			status = ni_pathsearch(ni, &parent_dir, "/netdomains");
			break;
		default:
			sprintf(str, "Domain %s: unknown lookup category %d",
				[self name], cat);
			[lookupLog syslogError:str];
			[controller rpcUnlock];
			return nil;
	}

	[controller rpcUnlock];

	if (status != NI_OK)
	{
		/* No match */
		return nil;
	}

	NI_INIT(&idl);
	[controller rpcLock];
	status = ni_lookup(ni, &parent_dir, aKey, aVal, &idl);
	[controller rpcUnlock];
	if (status != NI_OK)
	{
		/* No match */
		return nil;
	}

	if (idl.ni_idlist_len == 0)
	{
		/* No match */
		return nil;
	}

	dict = [self readDirectory:idl.ni_idlist_val[0] selectedKeys:keyList];
	sprintf(str, "NIAgent: %s %s", [self categoryName:cat], aVal);
	[dict setBanner:str];

	ni_idlist_free(&idl);
	return dict;
}

/*
 * Look up all directory within a given category of objects
 * (users, hosts, etc).
 *
 * Returns an array of dictionaries.  Dictionaries are the same
 * as those returned by -entityForCategory:key:value:
 */
- (LUArray *)allEntitiesForCategory:(LUCategory)cat
{
	return [self allEntitiesForCategory:cat selectedKeys:NULL];
}

/*
 * Look up all directory within a given category of objects
 * (users, hosts, etc).
 *
 * Returns an array of dictionaries.  Dictionaries are the same
 * as those returned by -entityForCategory:key:value:selectedKeys:
 */
- (LUArray *)allEntitiesForCategory:(LUCategory)cat
	selectedKeys:(char **)keyList
{
	return [self allEntitiesForCategory:cat 
		key:NULL value:NULL selectedKeys:keyList];
}

- (LUArray *)allEntitiesForCategory:(LUCategory)cat
	key:(char *)aKey
	value:(char *)aVal
	selectedKeys:(char **)keyList
{
	ni_id parent_dir;
	ni_entrylist all;
	ni_idlist kids;
	ni_status status;
	LUDictionary *dict;
	LUArray *list;
	int i, j, len, nkeys;
	char str[256];

	[controller rpcLock];
	switch (cat)
	{
		case LUCategoryUser:
			status = ni_pathsearch(ni, &parent_dir, "/users");
			break;
		case LUCategoryGroup:
			status = ni_pathsearch(ni, &parent_dir, "/groups");
			break;
		case LUCategoryHost:
			status = ni_pathsearch(ni, &parent_dir, "/machines");
			break;
		case LUCategoryNetwork:
			status = ni_pathsearch(ni, &parent_dir, "/networks");
			break;
		case LUCategoryService:
			status = ni_pathsearch(ni, &parent_dir, "/services");
			break;
		case LUCategoryProtocol:
			status = ni_pathsearch(ni, &parent_dir, "/protocols");
			break;
		case LUCategoryRpc:
			status = ni_pathsearch(ni, &parent_dir, "/rpcs");
			break;
		case LUCategoryMount:
			status = ni_pathsearch(ni, &parent_dir, "/mounts");
			break;
		case LUCategoryPrinter:
			status = ni_pathsearch(ni, &parent_dir, "/printers");
			break;
		case LUCategoryAlias:
			status = ni_pathsearch(ni, &parent_dir, "/aliases");
			break;
		case LUCategoryBootparam:
			status = ni_pathsearch(ni, &parent_dir, "/machines");
			break;
		case LUCategoryBootp:
			status = ni_pathsearch(ni, &parent_dir, "/machines");
			break;
		case LUCategoryNetDomain:
			status = ni_pathsearch(ni, &parent_dir, "/netdomains");
			break;
		default:
			sprintf(str, "Domain %s: unknown lookup category %d",
				[self name], cat);
			[lookupLog syslogError:str];
			[controller rpcUnlock];
			return nil;
	}

	[controller rpcUnlock];

	if (status != NI_OK)
	{
		/* No match */
		return nil;
	}

	/*
	 * If the keyList is NULL, we interate through all directories.
	 * We need to do this for printers, where keys are variable.
	 * We also use this code to when given keys and values, since
	 * ni_lookup can be used to find just those directories.
	 */
	if ((keyList == NULL) || (aKey != NULL) || (aVal != NULL))
	{
		NI_INIT(&kids);

		[controller rpcLock];
		if ((aKey == NULL) || (aVal == NULL))
			status = ni_children(ni, &parent_dir, &kids);
		else
			status = ni_lookup(ni, &parent_dir, aKey, aVal, &kids);
		[controller rpcUnlock];

		if (status != NI_OK) return nil;

		list = [[LUArray alloc] init];

		for (i = 0; i < kids.ni_idlist_len; i++)
		{
			dict = [self readDirectory:kids.ni_idlist_val[i]
				selectedKeys:keyList];
			if (dict != nil)
			{
				[list addObject:dict];
				[dict release];
			}
		}
		ni_idlist_free(&kids);
		return list;
	}

	[controller rpcLock];

	nkeys = listLength(keyList);
	if (nkeys == 0) return nil;

	/* get all directories */
	len = 0;
	list = [[LUArray alloc] init];

	for (i = 0; i < nkeys; i++)
	{
		NI_INIT(&all);
		status = ni_list(ni, &parent_dir, keyList[i], &all);

		if (status != NI_OK)
		{
			[controller rpcUnlock];
			[list release];
			return nil;
		}

		len = all.ni_entrylist_len;
		for (j = 0; j < len; j++)
		{
			if (i == 0)
			{
				/*
				 * Must check if ids in the list we just got
				 * match existing ids.  Need to store id in dict
				 * quick hack: set cacheHits = id 
				 */

				dict = [[LUDictionary alloc] init];
				[dict setCacheHits:all.ni_entrylist_val[j].id];
				[list addObject:dict];
				[dict release];
			}
			else
			{
				dict = [list objectAtIndex:j];
				if ([dict cacheHits] != all.ni_entrylist_val[j].id)
				{
					/*
					 * Yikes! Someone added or deleted directories!
					 * Try again, but just iterate through the
					 * child dirs.  This is slower, but safer.
					 */
					ni_entrylist_free(&all);
					[list releaseObjects];
					[controller rpcUnlock];

					NI_INIT(&kids);
					[controller rpcLock];
					status = ni_children(ni, &parent_dir, &kids);
					[controller rpcUnlock];
					if (status != NI_OK) 
					{
						[list release];
						return nil;
					}
					for (i = 0; i < kids.ni_idlist_len; i++)
					{
						dict = [self readDirectory:kids.ni_idlist_val[i]
							selectedKeys:keyList];
						if (dict != nil)
						{
							[list addObject:dict];
							[dict release];
						}
					}
					ni_idlist_free(&kids);
					return list;
				}
			}
			if (all.ni_entrylist_val[j].names != NULL)
			{
				if (all.ni_entrylist_val[j].names->ni_namelist_len > 0)
					[dict
						setValues:
							all.ni_entrylist_val[j].names->ni_namelist_val
						forKey:
							keyList[i]
						count:
							all.ni_entrylist_val[j].names->ni_namelist_len];
			}
		}

		ni_entrylist_free(&all);
	}

	if (len > 0)
	{
		/* clean up from cacheHits hack */
		len = [list count];
		for (j = 0; j < len; j++) [[list objectAtIndex:j] setCacheHits:0];
	}

	[controller rpcUnlock];
	return list;
}

/*
 * Look up a directory with two key/value pairs.
 * This is primarily an optimization for getServiceWithXXX
 */
- (LUDictionary *)entityForCategory:(LUCategory)cat
	key:(char *)key1
	value:(char *)val1
	key:(char *)key2
	value:(char *)val2
	selectedKeys:(char **)keyList
{
	ni_id parent_dir;
	ni_status status;
	LUDictionary *dict;
	ni_idlist idl1;
	ni_idlist idl2;
	char str[256];
	int i, len1, j, len2;
	BOOL searching;
	unsigned long id1;

	[controller rpcLock];
	switch (cat)
	{
		case LUCategoryUser:
			status = ni_pathsearch(ni, &parent_dir, "/users");
			break;
		case LUCategoryGroup:
			status = ni_pathsearch(ni, &parent_dir, "/groups");
			break;
		case LUCategoryHost:
			status = ni_pathsearch(ni, &parent_dir, "/machines");
			break;
		case LUCategoryNetwork:
			status = ni_pathsearch(ni, &parent_dir, "/networks");
			break;
		case LUCategoryService:
			status = ni_pathsearch(ni, &parent_dir, "/services");
			break;
		case LUCategoryProtocol:
			status = ni_pathsearch(ni, &parent_dir, "/protocols");
			break;
		case LUCategoryRpc:
			status = ni_pathsearch(ni, &parent_dir, "/rpcs");
			break;
		case LUCategoryMount:
			status = ni_pathsearch(ni, &parent_dir, "/mounts");
			break;
		case LUCategoryPrinter:
			status = ni_pathsearch(ni, &parent_dir, "/printers");
			break;
		case LUCategoryAlias:
			status = ni_pathsearch(ni, &parent_dir, "/aliases");
			break;
		case LUCategoryBootparam:
			status = ni_pathsearch(ni, &parent_dir, "/machines");
			break;
		case LUCategoryBootp:
			status = ni_pathsearch(ni, &parent_dir, "/machines");
			break;
		case LUCategoryNetDomain:
			status = ni_pathsearch(ni, &parent_dir, "/netdomains");
			break;
		default:
			sprintf(str, "Domain %s: unknown lookup category %d",
				[self name], cat);
			[lookupLog syslogError:str];
			[controller rpcUnlock];
			return nil;
	}

	[controller rpcUnlock];

	if (status != NI_OK)
	{
		/* No match */
		return nil;
	}

	NI_INIT(&idl1);
	NI_INIT(&idl2);
	[controller rpcLock];
	status = ni_lookup(ni, &parent_dir, key1, val1, &idl1);
	if (status == NI_OK)
		status = ni_lookup(ni, &parent_dir, key2, val2, &idl2);
	[controller rpcUnlock];

	if (status != NI_OK)
	{
		/* No match */
		return nil;
	}

	len1 = idl1.ni_idlist_len;
	len2 = idl2.ni_idlist_len;

	if ((len1 == 0) || (len2 == 0))
	{
		/* No match */
		return nil;
	}

	/*
	 * Look for a directory that's in both lists
	 */
	searching = YES;
	id1 = idl1.ni_idlist_val[0];
	for (i = 0; (i < len1) && searching; i++)
	{
		id1 = idl1.ni_idlist_val[i];
		for (j = 0; (j < len2) && searching; j++)
		{
			searching = !(id1 == idl2.ni_idlist_val[j]);
		}
	}

	if (searching)
	{
		dict = nil;
	}
	else
	{
		dict = [self readDirectory:id1 selectedKeys:keyList];
	}

	ni_idlist_free(&idl1);
	ni_idlist_free(&idl2);
	return dict;
}

/************************* LOOKUP ROUTINES *************************/

- (LUDictionary *)userWithName:(char *)name
{
	return [self entityForCategory:LUCategoryUser
		key:"name" value:name selectedKeys:NULL];
}

- (LUDictionary *)userWithNumber:(int *)number
{
	char str[32];

	sprintf(str, "%d", *number);
	return [self entityForCategory:LUCategoryUser key:"uid"
		value:str selectedKeys:NULL];
}

- (LUArray *)allUsers
{
	return [self allEntitiesForCategory:LUCategoryUser
		key:NULL value:NULL selectedKeys:userKeys];
}

- (LUDictionary *)groupWithName:(char *)name
{
	return [self entityForCategory:LUCategoryGroup
		key:"name" value:name selectedKeys:NULL];
}

- (LUDictionary *)groupWithNumber:(int *)number
{
	char str[32];

	sprintf(str, "%d", *number);
	return [self entityForCategory:LUCategoryGroup key:"gid"
		value:str selectedKeys:NULL];
}

- (LUArray *)allGroups
{
	return [self allEntitiesForCategory:LUCategoryGroup
		key:NULL value:NULL selectedKeys:groupKeys];
}

- (LUDictionary *)hostWithName:(char *)name
{
	return [self entityForCategory:LUCategoryHost
		key:"name" value:name selectedKeys:NULL];
}

- (LUDictionary *)hostWithInternetAddress:(struct in_addr *)addr
{
	char str[32];

	sprintf(str, "%s", inet_ntoa(*addr));
	return [self entityForCategory:LUCategoryHost key:"ip_address"
		value:str selectedKeys:NULL];
}
		
- (LUDictionary *)hostWithEthernetAddress:(struct ether_addr *)addr
{
	char **etherAddrs;
	LUDictionary *host;
	int i, len;

	/* Try all possible variations on leading zeros in the address */
	etherAddrs = [self variationsOfEthernetAddress:addr];
	len = listLength(etherAddrs);
	for (i = 0; i < len; i++)
	{
		host = [self entityForCategory:LUCategoryHost
			key:"en_address"
			value:etherAddrs[i]
			selectedKeys:NULL];

		if (host != nil)
		{
			freeList(etherAddrs);
			etherAddrs = NULL;
			return host;
		}
	}
	freeList(etherAddrs);
	etherAddrs = NULL;
	return nil;
}

- (LUArray *)allHosts
{
	return [self allEntitiesForCategory:LUCategoryHost
		key:NULL value:NULL selectedKeys:hostKeys];
}

- (LUDictionary *)networkWithName:(char *)name
{
	return [self entityForCategory:LUCategoryNetwork
		key:"name" value:name selectedKeys:NULL];
}

- (LUDictionary *)networkWithInternetAddress:(struct in_addr *)addr
{
	char str[32];

	sprintf(str, "%s", nettoa(addr->s_addr));
	return [self entityForCategory:LUCategoryNetwork key:"address"
		value:str selectedKeys:NULL];
}

- (LUArray *)allNetworks
{
	return [self allEntitiesForCategory:LUCategoryNetwork
		key:NULL value:NULL selectedKeys:networkKeys];
}

- (LUDictionary *)serviceWithName:(char *)name
	protocol:(char *)prot
{
	if (prot == NULL)
	{
		return [self entityForCategory:LUCategoryService
			key:"name" value:name selectedKeys:serviceKeys];
	}

	return [self entityForCategory:LUCategoryService
		key:"name" value:name key:"protocol" value:prot selectedKeys:NULL];
}

- (LUDictionary *)serviceWithNumber:(int *)number
	protocol:(char *)prot
{
	char str[32];

	sprintf(str, "%d", *number);

	if (prot == NULL)
	{
		return [self entityForCategory:LUCategoryService
			key:"port" value:str selectedKeys:serviceKeys];
	}

	return [self entityForCategory:LUCategoryService
		key:"port" value:str key:"protocol" value:prot selectedKeys:NULL];
}

- (LUArray *)allServices
{
	return [self allEntitiesForCategory:LUCategoryService
		key:NULL value:NULL selectedKeys:serviceKeys];
}

- (LUDictionary *)protocolWithName:(char *)name
{
	return [self entityForCategory:LUCategoryProtocol
		key:"name" value:name selectedKeys:NULL];
}

- (LUDictionary *)protocolWithNumber:(int *)number
{
	char str[32];

	sprintf(str, "%d", *number);
	return [self entityForCategory:LUCategoryProtocol key:"number"
		value:str selectedKeys:NULL];
}

- (LUArray *)allProtocols
{
	return [self allEntitiesForCategory:LUCategoryProtocol
		key:NULL value:NULL selectedKeys:protocolKeys];
}

- (LUDictionary *)rpcWithName:(char *)name
{
	return [self entityForCategory:LUCategoryRpc
		key:"name" value:name selectedKeys:NULL];
}

- (LUDictionary *)rpcWithNumber:(int *)number
{
	char str[32];

	sprintf(str, "%d", *number);
	return [self entityForCategory:LUCategoryRpc key:"number"
		value:str selectedKeys:NULL];
}

- (LUArray *)allRpcs
{
	return [self allEntitiesForCategory:LUCategoryRpc
		key:NULL value:NULL selectedKeys:rpcKeys];
}

- (LUDictionary *)mountWithName:(char *)name
{
	return [self entityForCategory:LUCategoryMount
		key:"name" value:name selectedKeys:NULL];
}

- (LUArray *)allMounts
{
	return [self allEntitiesForCategory:LUCategoryMount
		key:NULL value:NULL selectedKeys:mountKeys];
}

- (LUDictionary *)printerWithName:(char *)name
{
	return [self entityForCategory:LUCategoryPrinter
		key:"name" value:name selectedKeys:NULL];
}

- (LUArray *)allPrinters
{
	return [self allEntitiesForCategory:LUCategoryPrinter];
}

- (LUDictionary *)bootparamsWithName:(char *)name
{
	LUDictionary *boot;

	boot = [self entityForCategory:LUCategoryBootparam
		key:"name" value:name selectedKeys:bootparamKeys];

	return boot;
}

- (LUArray *)allBootparams
{
	return [self allEntitiesForCategory:LUCategoryBootparam
		key:NULL value:NULL selectedKeys:bootparamKeys];
}

- (void)preferBootpAddress:(char *)addr
	key:(char *)key
	target:(char *)tkey
	dict:(LUDictionary *)dict
{
	char **kVals, **tVals;
	char *t;
	int i, target, kLen, tLen, tLast;

	kVals = [dict valuesForKey:key];
	tVals = [dict valuesForKey:tkey];

	tLen = listLength(tVals);
	if (tLen == 0) return;

	kLen = listLength(kVals);
	if (kLen == 0) return;

	tLast = tLen - 1;
	target = 0;

	for (i = 0; i < kLen; i++)
	{
		if (i == tLast) break;

		if (!strcmp(addr, kVals[i]))
		{
			target = i;
			break;
		}
	}

	[dict removeKey:key];
	[dict setValue:addr forKey:key];

	t = copyString(tVals[target]);
	[dict removeKey:tkey];
	[dict setValue:t forKey:tkey];
	freeString(t);
}

- (LUDictionary *)bootpWithInternetAddress:(struct in_addr *)addr
{
	LUDictionary *bootp;
	char **en;
	char str[32];
	int n;

	sprintf(str, "%s", inet_ntoa(*addr));
	
	bootp = [self entityForCategory:LUCategoryBootp
		key:"ip_address" value:str selectedKeys:hostKeys];

	if (bootp == nil) return nil;

	/* only return a directory if there is an en_address */
	en = [bootp valuesForKey:"en_address"];
	if (en == NULL)
	{
		[bootp release];
		return nil;
	}

	n = [bootp countForKey:"en_address"];
	if (n <= 0) 
	{
		[bootp release];
		return nil;
	}

	[self preferBootpAddress:str
		key:"ip_address" target:"en_address" dict:bootp];

	return bootp;
}

- (LUDictionary *)bootpWithEthernetAddress:(struct ether_addr *)addr
{
	char **etherAddrs;
	LUDictionary *bootp;
	int i, len;
	
	/* Try all possible variations on leading zeros in the address */
	etherAddrs = [self variationsOfEthernetAddress:addr];
	len = listLength(etherAddrs);
	for (i = 0; i < len; i++)
	{
		bootp = [self entityForCategory:LUCategoryBootp
			key:"en_address" value:etherAddrs[i] selectedKeys:hostKeys];

		if (bootp != nil)
		{
			[self preferBootpAddress:etherAddrs[i]
				key:"en_address" target:"ip_address" dict:bootp];
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

	alias = [self entityForCategory:LUCategoryAlias key:"name" value:name
		selectedKeys:NULL];
	if (alias == nil) return nil;

	if ([self isLocalDomain])
	{
		[alias addValue:"1" forKey:"alias_local"];
	}
	else
	{
		[alias addValue:"0" forKey:"alias_local"];
	}
	return alias;
}

- (LUArray *)allAliases
{
	LUArray *all;
	int i, len;
	char str[4];

	all = [self allEntitiesForCategory:LUCategoryAlias
		key:NULL value:NULL selectedKeys:aliasKeys];
	if (all == nil) return nil;

	if ([self isLocalDomain]) str[0] = '1';
	else str[0] = '0';
	str[1] = '\0';

	len = [all count];
	for (i = 0; i < len; i++)
	{
		[[all objectAtIndex:i] addValue:str forKey:"alias_local"];
	}

	return all;
}

- (LUDictionary *)netgroupWithName:(char *)name
{
	LUDictionary *item;
	LUDictionary *group;
	LUArray *them;
	int i, tlen;
	int nlen;
	char **keys = NULL;
	BOOL found;

	keys = appendString("name", keys);
	found = NO;

	/* search /users, /machines, and /netdomains for this netgroup */
	group = [[LUDictionary alloc] init];
	[group setValue:name forKey:"name"];

	/* Get hosts with this netgroup */
	them = [self allEntitiesForCategory:LUCategoryHost key:"netgroups"
		value:name selectedKeys:keys];
	tlen = [them count];
	for (i = 0; i < tlen; i++)
	{
		item = [them objectAtIndex:i];
		nlen = [item countForKey:"name"];
		if (nlen > 0)
		{
			found = YES;
			[group addValues:[item valuesForKey:"name"] forKey:"hosts"];	
		}
	}
	[them release];

	/* Get users with this netgroup */
	them = [self allEntitiesForCategory:LUCategoryUser key:"netgroups"
		value:name selectedKeys:keys];
	tlen = [them count];
	for (i = 0; i < tlen; i++)
	{
		item = [them objectAtIndex:i];
		nlen = [item countForKey:"name"];
		if (nlen > 0)
		{
			found = YES;
			[group addValues:[item valuesForKey:"name"] forKey:"users"];	
		}
	}
	[them release];

	/* Get domains with this netgroup */
	them = [self allEntitiesForCategory:LUCategoryNetDomain key:"netgroups"
		value:name selectedKeys:keys];
	tlen = [them count];
	for (i = 0; i < tlen; i++)
	{
		item = [them objectAtIndex:i];
		nlen = [item countForKey:"name"];
		if (nlen > 0)
		{
			found = YES;
			[group addValues:[item valuesForKey:"name"] forKey:"domains"];	
		}
	}
	[them release];


	freeList(keys);
	keys = NULL;

	return group;
}

- (BOOL)inNetgroup:(char *)group
	host:(char *)hostName
	user:(char *)userName
	domain:(char *)domainName
{
	/* inNetgroup is computed by LUServer */
	return NO;
}

/*
 * Custom lookup for security options
 *
 * Special case: "all" enables all security options
 */
- (BOOL)isSecurityEnabledForOption:(char *)option
{
	LUDictionary *root;
	char **security;

	root = [self readDirectory:0 selectedKeys:NULL];
	security = [root valuesForKey:"security_options"];
	if (security == NULL)
	{
		[root release];
		return NO;
	}

	if (listIndex("all", security) != IndexNull)
	{
		[root release];
		return YES;
	}
	if (listIndex(option, security) != IndexNull)
	{
		[root release];
		return YES;
	}
	[root release];
	return NO;
}

/*
 * Custom lookup for netware
 */
- (BOOL)checkNetwareEnabled
{
	LUDictionary *nw;
	char **en;

	nw = [self readDirectoryName:"/locations/NetWare" selectedKeys:NULL];
	if (nw == nil) return NO;

	en = [nw valuesForKey:"enabled"];
	if (en == NULL)
	{
		[nw release];
		return NO;
	}

	if (listIndex("YES", en) != IndexNull)
	{
		[nw release];
		return YES;
	}
	[nw release];
	return NO;
}

/*
 * Custom lookup for initgroups()
 *
 * Returns an array of all groups containing a user
 * (including default group)
 */
- (LUArray *)allGroupsWithUser:(char *)name
{
	LUArray *allGroups;
	LUDictionary *user;
	LUDictionary *group;
	char **ga;
	char *gid;
	int i, len, j, ngrps, dgid;
	BOOL new;

	/* get all the groups for which the user is a member */
	allGroups = [self allEntitiesForCategory:LUCategoryGroup
		key:"users" value:name selectedKeys:NULL];

	if (allGroups == nil) allGroups = [[LUArray alloc] init];

	/* add in the user's default group */
	user = [self entityForCategory:LUCategoryUser key:"name" value:name
		selectedKeys:NULL];
	if (user == nil)
	{
		/* User isn't in this domain */
		return allGroups;
	}
	
	ga = [user valuesForKey:"gid"];
	if (ga == NULL)
	{
		/* user has no default group */
		[user release];
		return allGroups;
	}

	len = [user countForKey:"gid"];
	if (len < 0) len = 0;
	for (i = 0; i < len; i++)
	{
		gid = ga[i];
		dgid = atoi(gid);
		group = [self entityForCategory:LUCategoryGroup key:"gid" value:gid
			selectedKeys:NULL];
		if (group == nil) continue;

		/* is this groups already in allGroups */
		ngrps = [allGroups count];
		new = YES;
		for (j = 0; j < ngrps; j++)
		{
			if (dgid == atoi([[allGroups objectAtIndex:i] valueForKey:"gid"]))
			{
				new = NO;
				break;
			}
		}
		if (new)
		{
			[allGroups addObject:group];
			[group release];
		}
	}

	[user release];
	return allGroups;
}

@end
