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
	Controller.m

	Controller for lookupd

	Copyright (c) 1995, NeXT Computer Inc.
	All rights reserved.
	Written by Marc Majka
 */

#import "Controller.h"
#import "LUPrivate.h"
#import "LUCachedDictionary.h"
#import "LookupDaemon.h"
#import "Syslog.h"
#import <syslog.h>
#import "LUGlobal.h"
#import "MachRPC.h"
#import "LUServer.h"
#import "CacheAgent.h"
#import "NIAgent.h"
#import "LUNIDomain.h"
#import "DNSAgent.h"
#import "FFAgent.h"
#import "YPAgent.h"
#import "LDAPAgent.h"
#import "NILAgent.h"
#import "stringops.h"
#import <mach/mach.h>
#import <mach/mach_traps.h>
#import <mach/cthreads.h>
#import <mach/message.h>
#import <mach/mig_errors.h>
#import <sys/types.h>
#import <sys/param.h>
#import <unistd.h>
#import <servers/netname.h>
#import <string.h>

#if NS_TARGET_MAJOR == 3
#import <foundation/NSAutoreleasePool.h>
#import <foundation/NSBundle.h>
#import <foundation/NSString.h>
#else
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSString.h>
#endif

#define forever for(;;)
#define LookupdBundlePath "/System/Library/CoreServices/lookupd"
#define LookupConfigDict "/locations"
#define LookupConfigDirPath "/etc"

extern int gethostname(char *, int);
extern port_t _lookupd_port(port_t);
extern port_t _lookupd_port1(port_t);
extern port_t server_port;
extern port_t server_port_unprivileged;
extern port_t server_port_privileged;

#if NS_TARGET_MAJOR == 3
extern const char VERS_NUM[];
#else
extern const char lookupd_VERS_NUM[];
#endif

static int _cache_initialized = 0;

@implementation Controller

- (BOOL)serviceRequest:(lookup_msg *)request
{
	BOOL kissItGoodbye;
	BOOL status;

	/*
 	 * Update idle thread counter
	 */
	[serverLock lock];
	idleThreadCount--;

	/* make sure there's at lease one thread in msg_receive */
	while ((idleThreadCount < 1) && (threadCount < maxThreads))
	{
		[self startServerThread];
	}
	[serverLock unlock];

	/*
	 * Deal with the client's request
	 */
	status = [machRPC process:request];

	/*
	 * This thread should exit if there are too many idle threads
	 */
	[serverLock lock];
	kissItGoodbye = (idleThreadCount > maxIdleThreads);
	if (!kissItGoodbye) idleThreadCount++;
	else threadCount--;	
	[serverLock unlock];

	return kissItGoodbye;
}

- (port_t)server_port
{
	return server_port;
}

/*
 * server threads: answer request messages
 */
void server_thread(Controller *controller)
{
	kern_return_t status;
	lookup_msg request;
	BOOL kissItGoodbye;
	port_t server_port;

	server_port = [controller server_port];

	forever
	{
		/* Receive and service a request */
		request.head.msg_local_port = server_port;
		request.head.msg_size = sizeof(lookup_msg);
		status = msg_receive((msg_header_t *)&request, MSG_OPTION_NONE, 0);
		if (status != KERN_SUCCESS) continue;

		kissItGoodbye = [controller serviceRequest:&request];
		if (kissItGoodbye) cthread_exit(0);
	}
}

/*
 * Cache initialization thread
 */
void cache_init_thread(Controller *controller)
{
	char hname[1024];
	LUServer *s;
	LUDictionary *item;
	CacheAgent *cacheAgent;
	/*
	 * get the shared cache agent
	 */
	cacheAgent = [[CacheAgent alloc] init];

	gethostname(hname, 1024);

	s = [controller checkOutServer];
	item = [s userWithName:"root"];
	if (item != nil)
	{
		[cacheAgent addObject:item];
		[item setTimeToLive:(time_t)-1];
		[item release];
	}

	item = [s hostWithName:"localhost"];
	if (item != nil)
	{
		[cacheAgent addObject:item];
		[item setTimeToLive:(time_t)-1];
		[item release];
	}

	item = [s hostWithName:hname];
	if (item != nil)
	{
		[cacheAgent addObject:item];
		[item setTimeToLive:(time_t)-1];
		[item release];
	}

	[controller checkInServer:s];

	_cache_initialized = 1;

	cthread_exit(0);
}

- (int)config:(LUDictionary *)dict int:(char *)key default:(int)def
{
	char *s;
	int n, i;

	if (dict == nil) return def;
	s = [dict valueForKey:key];
	if (s == NULL) return def;
	n = sscanf(s, "%d", &i);
	if (n <= 0) return def;
	return i;
}

- (char *)config:(LUDictionary *)dict string:(char *)key default:(char *)def
{
	char *s, t[256];
	int n;

	if (dict == nil) return def;
	s = [dict valueForKey:key];
	if (s == NULL) return def;
	n = sscanf(s, "%s", t);
	if (n <= 0) return def;
	return s;
}

- (BOOL)config:(LUDictionary *)dict bool:(char *)key default:(BOOL)def
{
	char *s;

	if (dict == nil) return def;
	s = [dict valueForKey:key];
	if (s == NULL) return def;
	if (s[0] == 'Y') return YES;
	if (s[0] == 'y') return YES;
	if (s[0] == 'T') return YES;
	if (s[0] == 't') return YES;
	if (!strcmp(s, "1")) return YES;
	if (s[0] == 'N') return NO;
	if (s[0] == 'n') return NO;
	if (s[0] == 'F') return NO;
	if (s[0] == 'f') return NO;
	if (!strcmp(s, "0")) return NO;

	return def;
}

- (void)newAgent:(id)agent name:(char *)name
{
	if (agentCount == 0) agents = (id *)malloc(sizeof(id));
	else agents = (id *)realloc(agents, (agentCount + 1) * sizeof(id));
	agents[agentCount] = agent;
	agentNames = appendString(name, agentNames);
	agentCount++;
}

- (id)agentNamed:(char *)name
{
	int i;
	char str[256], cname[256];
	id agentClass;
	NSAutoreleasePool *puddle;
	NSBundle *agentBundle;

	i = listIndex(name, agentNames);
	if (i != IndexNull) return agents[i];

	sprintf(cname, "%sAgent", name);
	i = listIndex(cname, agentNames);
	if (i != IndexNull) return agents[i];

	sprintf(str, "loading lookup agent %s", name);
	[lookupLog syslogDebug:str];

	puddle = [[NSAutoreleasePool alloc] init];

	agentClass = nil;
	agentBundle = [[NSBundle alloc] initWithPath:[NSString stringWithFormat:
		[NSString stringWithCString: "%s/%s.bundle"],
		LookupdBundlePath, name]];

	if (agentBundle == nil)
	{
		name = cname;
		agentBundle = [[NSBundle alloc] initWithPath:[NSString stringWithFormat:
			[NSString stringWithCString: "%s/%s.bundle"],
			LookupdBundlePath, name]];
	}

	if (agentBundle != nil)
	{
		agentClass = [agentBundle principalClass];
		[agentBundle release];
	}
	[puddle release];

	if (agentClass == nil)
	{
		sprintf(str, "Can't load lookup agent from %s/%s.bundle",
			LookupdBundlePath, name);
		[lookupLog syslogWarning:str];
		return nil;
	}

	[self newAgent:agentClass name:name];
	return agentClass;
}

- (void)initLookup:(LUCategory)cat
{
	char **order;
	int i;
	id agent;
	BOOL validation;
	unsigned int max, freq;
	time_t ttl, delta;

	if (configDict[(int)cat] == nil) return;

	order = [configDict[(int)cat] valuesForKey:"LookupOrder"];
	if (order != NULL)
	{
		[lookupOrder[(int)cat] removeAllObjects];
	
		for (i = 0; order[i] != NULL; i++)
		{
			agent = [self agentNamed:order[i]];
			if (agent == nil) continue;

			[lookupOrder[(int)cat] addObject:agent];		
		}
	}

	validation = [self config:configDict[(int)cat] bool:"ValidateCache" default:YES];
	[cacheAgent setCacheIsValidated:validation forCategory:cat];

	max = [self config:globalDict int:"CacheCapacity" default:0];
	if (max == 0) max = (unsigned int)-1;
	ttl = (time_t)[self config:globalDict int:"TimeToLive" default:43200];
	delta = (time_t)[self config:globalDict int:"TimeToLiveDelta" default:0];
	freq = [self config:globalDict int:"TimeToLiveFreq" default:0];

	[cacheAgent setCapacity:max forCategory:cat];
	[cacheAgent setTimeToLive:ttl forCategory:cat];
	[cacheAgent addTimeToLive:delta afterCacheHits:freq forCategory:cat];
}

- (void)initGlobalLookup
{
	char **order;
	int i, n, len;
	id agent;
	BOOL validation;
	char *logFileName;
	char *logFacilityName;
	unsigned int max, freq;
	time_t now, ttl, delta;
	char str[64];

	logFileName = [self config:globalDict string:"LogFile" default:NULL];
 	[lookupLog setLogFile:logFileName];

	logFacilityName = [self config:globalDict
		string:"LogFacility" default:"LOG_NETINFO"];
 	[lookupLog setLogFacility:logFacilityName];

	now = time(0);
#if NS_TARGET_MAJOR == 3
	sprintf(str, "lookupd (version %s) starting - %s",
		VERS_NUM, ctime(&now));
#else
	sprintf(str, "lookupd (version %s) starting - %s",
		lookupd_VERS_NUM, ctime(&now));
#endif

	/* remove ctime trailing newline */
	str[strlen(str) - 1] = '\0';
	[lookupLog syslogDebug:str];

	maxThreads = [self config:globalDict int:"MaxThreads" default:16];
	maxIdleThreads = [self config:globalDict int:"MaxIdleThreads" default:16];
	maxIdleServers = [self config:globalDict int:"MaxIdleServers" default:16];

	validation = [self config:globalDict bool:"ValidateCache" default:YES];
	max = [self config:globalDict int:"CacheCapacity" default:-1];
	if (max == 0) max = (unsigned int)-1;
	ttl = (time_t)[self config:globalDict int:"TimeToLive" default:43200];
	delta = (time_t)[self config:globalDict int:"TimeToLiveDelta" default:0];
	freq = [self config:globalDict int:"TimeToLiveFreq" default:0];

	for (i = 0; i < NCATEGORIES; i++)
	{
		[cacheAgent setCacheIsValidated:validation forCategory:(LUCategory)i];
		[cacheAgent setCapacity:max forCategory:(LUCategory)i];
		[cacheAgent setTimeToLive:ttl forCategory:(LUCategory)i];
		[cacheAgent addTimeToLive:delta afterCacheHits:freq forCategory:(LUCategory)i];
	}

	[self newAgent:[CacheAgent class] name:"CacheAgent"];
	[self newAgent:[NIAgent class] name:"NIAgent"];
	[self newAgent:[DNSAgent class] name:"DNSAgent"];
	[self newAgent:[FFAgent class] name:"FFAgent"];
	[self newAgent:[YPAgent class] name:"YPAgent"];
	[self newAgent:[LDAPAgent class] name:"LDAPAgent"];
	[self newAgent:[NILAgent class] name:"NILAgent"];

	order = [globalDict valuesForKey:"LookupOrder"];
	if (order == NULL) len = 0;
	else len = listLength(order);

	for (i = 0; i < len; i++)
	{
		agent = [self agentNamed:order[i]];
		if (agent == nil) continue;

		for (n = 0; n < NCATEGORIES; n++) [lookupOrder[n] addObject:agent];		
	}
	if (len == 0)
	{
		for (n = 0; n < NCATEGORIES; n++)
		{
			[lookupOrder[n] addObject:[CacheAgent class]];
			[lookupOrder[n] addObject:[NIAgent class]];
			if ((n == (int)LUCategoryHost) || (n == (int)LUCategoryNetwork))
				[lookupOrder[n] addObject:[DNSAgent class]];
		}
	}
}

- (char *)getLineFromFile:(FILE *)fp
{
	char s[1024];
	char *out;
	int len;

    s[0] = '\0';

    fgets(s, 1024, fp);
    if (s == NULL || s[0] == '\0') return NULL;

	if (s[0] == '#')
	{
		out = copyString("#");
		return out;
	}

	len = strlen(s) - 1;
	s[len] = '\0';

	out = copyString(s);
	return out;
}

- (LUDictionary *)configurationForFilePath:(char *)p
{
	LUDictionary *dict;
	char path[256];
	FILE *fp;
	char *line;
	char **tokens;
	FFParser *parser;

	sprintf(path, "%s/%s/%s", LookupConfigDirPath, portName, p);

	fp = fopen(path, "r");
	if ((fp == NULL) && (strcmp(portName, DefaultName)))
	{
		sprintf(path, "%s/%s/%s", LookupConfigDirPath, DefaultName, p);
		fp = fopen(path, "r");
	}
	if (fp == NULL) return nil;

	dict = [[LUDictionary alloc] init];
	parser = [[FFParser alloc] init];

	while (NULL != (line = [self getLineFromFile:fp]))
	{
		if (line[0] == '#') 
		{
			freeString(line);
			line = NULL;
			continue;
		}

		tokens = [parser tokensFromLine:line separator:" \t"];
		if (tokens == NULL) continue;

		[dict setValues:(tokens+1) forKey:tokens[0]];
		freeList(tokens);
		tokens = NULL;
	}

	[parser release];
	return dict;
}

- (LUDictionary *)configurationForNIPath:(char *)p
{
	LUDictionary *dict = nil;
	LUNIDomain *d;
	char path[256];

	sprintf(path, "%s/%s", LookupConfigDict, portName);
	if (p != NULL)
	{
		strcat(path, "/");
		strcat(path, p);
	}

	for (d = [controlNIAgent domainAtIndex:0]; d != nil; d = [d parent])
	{
		dict = [d readDirectoryName:path selectedKeys:NULL];
		if (dict != nil) break;
	}

	if ((dict == nil) && (strcmp(portName, DefaultName)))
	{
		sprintf(path, "%s/%s", LookupConfigDict, DefaultName);
		if (p != NULL)
		{
			strcat(path, "/");
			strcat(path, p);
		}

		for (d = [controlNIAgent domainAtIndex:0]; d != nil; d = [d parent])
		{
			dict = [d readDirectoryName:path selectedKeys:NULL];
			if (dict != nil) break;
		}
	}

	if (dict == nil) return nil;

	return dict;
}

- (LUDictionary *)configurationForCategory:(LUCategory)cat
{
	LUDictionary *dict;
	char *catPath;
	char path[256];

	catPath = (char *)[controlNIAgent categoryPathname:cat];
	dict = [self configurationForNIPath:catPath];

	if (catPath == NULL) catPath = "global";
	if (dict == nil) dict = [self configurationForFilePath:catPath];

	if (dict == nil) return nil;

	if (cat == LUCategoryNull)
		sprintf(path, "Controller global configuration");
	else
		sprintf(path, "Controller configuration for category %s",
			[controlNIAgent categoryName:cat]);
	[dict setBanner:path];

	return dict;
}

- (LUDictionary *)configurationForAgent:(char *)agent category:(LUCategory)cat
{
	LUDictionary *dict;
	char *catPath;
	char path[256];

	if (agent == NULL) return [globalDict retain];

	catPath = (char *)[controlNIAgent categoryPathname:cat];

	if (catPath == NULL)
	{
		sprintf(path, "agents/%s", agent);
		dict = [self configurationForNIPath:path];
	}
	else
	{
		sprintf(path, "agents/%s/%s", agent, catPath);
		dict = [self configurationForNIPath:path];
	}

	if (dict == nil)
	{
		if (catPath == NULL) strcat(path, "/global");
		dict = [self configurationForFilePath:path];
	}

	if (dict == nil) return nil;

	if (cat == LUCategoryNull)
		sprintf(path, "%s configuration", agent);
	else
		sprintf(path, "%s configuration for category %s", agent, catPath);
	[dict setBanner:path];

	return dict;
}

- (LUDictionary *)configurationForAgent:(char *)agent
{
	return [self configurationForAgent:agent category:LUCategoryNull];
}

- (id)init
{
	return [self initWithName:NULL];
}

- (id)initWithName:(const char *)name
{
	int i, len;
	NSAutoreleasePool *initPool;

	[super init];

	initPool = [[NSAutoreleasePool alloc] init];

	controller = self;

 	if (name == NULL) portName = copyString((char *)DefaultName);
	else portName = copyString((char *)name);

	lookupLog = [[Syslog alloc] initWithIdent:portName
		facility:LOG_NETINFO
		options:(LOG_NOWAIT | LOG_PID)
		logFile:NULL];

	len = strlen(portName) + strlen(DOSuffix) + 1;
	doServerName = malloc(len);
	bzero(doServerName, len);
	sprintf(doServerName, "%s%s", portName, DOSuffix);

	if (![self registerPort:portName])
	{
		[initPool release];
		return nil;
	}

	serverLock = [[NSRecursiveLock alloc] init];
	serverList = [[NSMutableArray alloc] init];

	rpcLock = [[NSLock alloc] init];
	controlStats = [[LUDictionary alloc] init];
	[controlStats setBanner:"Controller statistics"];

#if NS_TARGET_MAJOR == 3
	[controlStats setValue:(char *)VERS_NUM forKey:"version"];
#else
	[controlStats setValue:(char *)lookupd_VERS_NUM forKey:"version"];
#endif

	threadCount = 0;
	idleThreadCount = 0;
	idleServerCount = 0;

	for (i = 0; i < NCATEGORIES; i++)
	{
		lookupOrder[i] = [[NSMutableArray alloc] init];
	}

	controlNIAgent = [[NIAgent reallyAlloc] initWithLocalHierarchy];
	cacheAgent = [[CacheAgent alloc] init];

	globalDict = [self configurationForCategory:LUCategoryNull];

	for (i = 0; i < NCATEGORIES; i++)
		configDict[i] = [self configurationForCategory:(LUCategory)i];

	[self initGlobalLookup];
	[self initLookup:LUCategoryUser];
	[self initLookup:LUCategoryHost];
	[self initLookup:LUCategoryNetwork];
	[self initLookup:LUCategoryService];
	[self initLookup:LUCategoryProtocol];
	[self initLookup:LUCategoryRpc];
	[self initLookup:LUCategoryMount];
	[self initLookup:LUCategoryPrinter];
	[self initLookup:LUCategoryBootparam];
	[self initLookup:LUCategoryBootp];
	[self initLookup:LUCategoryAlias];
	[self initLookup:LUCategoryNetgroup];

	[self startServerThread];

	_cache_initialized = 0;
	[self initCache];
	loginUser = nil;

	machRPC = [[MachRPC alloc] init:self];

	doServer = [[LookupDaemon alloc] initWithName:doServerName];

	[initPool release];

	cthread_yield();
	while (_cache_initialized == 0)
	{
		sleep(1);
		cthread_yield();
	}

	return self;
}

- (char *)portName
{
	return portName;
}

- (char *)doServerName
{
	return doServerName;
}

- (void)initCache
{
	cthread_t t;

	t = cthread_fork((cthread_fn_t)cache_init_thread, (any_t)self);
	cthread_detach(t);
}

- (void)dealloc
{
	int i, len;
	kern_return_t status;
	LUServer *server;

	if (portName != NULL)
	{
		status = netname_check_out(name_server_port, portName, PORT_NULL);
		if (status != KERN_SUCCESS)
		{
			[lookupLog syslogError:"Can't unregister lookupd port!"];
		}
		freeString(portName);
		portName = NULL;
	}

	if (doServerName != NULL)
	{
		[doServer release];
		freeString(doServerName);
		doServerName = NULL;
	}

	if (loginUser != nil) [loginUser release];
	if (cacheAgent != nil) [cacheAgent release];
	freeString(configDir);
	configDir = NULL;
	if (serverLock != nil) [serverLock release];
	if (rpcLock != nil) [rpcLock release];
	if (globalDict != nil) [globalDict release];
	for (i = 0; i < NCATEGORIES; i++)
	{
		if (lookupOrder[i] != nil) [lookupOrder[i] release];
		if (configDict[i] != nil) [configDict[i] release];
	}
	if (serverList != nil)
	{
		len = [serverList count];
		for (i = 0; i < len; i++)
		{
			server = [serverList objectAtIndex:i];
			[serverList removeObject:server];
			[server release];
		}
		[serverList release];
	}
	if (controlNIAgent != nil) [controlNIAgent release];
	if (controlStats != nil) [controlStats release];
	freeList(agentNames);
	agentNames = NULL;
	free(agents);
	[lookupLog syslogDebug:"lookupd exiting"];
	cthread_yield();

	[lookupLog release];
	[super dealloc];
}

- (BOOL)registerPort:(char *)name
{
	kern_return_t status;
	port_t aport;

	if (!strcmp(name, DefaultName))
	{
		/*
		 * If server_port is already set, this is a restart.
		 */
		if (server_port != MACH_PORT_NULL) return YES;

		if (port_allocate(task_self(), &server_port_unprivileged) != KERN_SUCCESS ||
		    port_allocate(task_self(), &server_port_privileged) != KERN_SUCCESS ||
		    port_set_allocate(task_self(), &server_port) != KERN_SUCCESS ||
		    port_set_add(task_self(), server_port, server_port_unprivileged) != KERN_SUCCESS ||
		    port_set_add(task_self(), server_port, server_port_privileged) != KERN_SUCCESS) 
		{
			syslog(LOG_CRIT, "lookupd: Can't allocate a port!");
			return NO;
		}

		/*
		 * Set the kernel's port.
		 *
		 * The _lookupd_port() system call registers the unprivileged lookupd port.
		 * The _lookupd_port1() system call registers the privileged lookupd port.
		 * Clients get the port from the kernel with _lookup_port(0).
		 */
		if (_lookupd_port(server_port_unprivileged) != server_port_unprivileged)
		{
			syslog(LOG_CRIT, "lookupd: Can't check in lookupd port!");
			return NO;
		}

		if (_lookupd_port1(server_port_privileged) != server_port_privileged)
		{
			syslog(LOG_ERR, "lookupd: Can't check in privileged lookupd port!");
		}

		return YES;
	}

	status = netname_look_up(name_server_port, "", name, &aport);
	if (status == KERN_SUCCESS)
	{
		server_port = aport;
		return YES;
	}

	status = port_allocate(task_self(), &server_port);
	if (status != KERN_SUCCESS)
	{
		syslog(LOG_CRIT, "lookupd: Can't allocate a port!");
		return NO;
	}

	status = netname_check_in(name_server_port, name, PORT_NULL, server_port);
	if (status != KERN_SUCCESS)
	{
		syslog(LOG_CRIT, "lookupd: Can't check in lookupd port!");
		return NO;
	}

	return YES;
}

- (void)startServerThread
{
	cthread_t t;

	[serverLock lock];

	/*
	 * Create the thread
	 */
	t = cthread_fork((cthread_fn_t)server_thread, (any_t)self);
	cthread_set_data(t, (any_t)threadCount);
	cthread_detach(t);

	/*
	 * Update counters
	 */
	threadCount++;
	idleThreadCount++;

	[serverLock unlock];
}

/*
 * Get an idle server from the server list
 */
- (LUServer *)checkOutServer
{
	LUServer *server;
	int i, len;

	[serverLock lock];
	server = nil;

	len = [serverList count];
	for (i = 0; i < len; i++)
	{
		if ([[serverList objectAtIndex:i] isIdle])
		{
			server = [serverList objectAtIndex:i];
			[server setIsIdle:NO];
			idleServerCount--;
			break;
		}
	}

	if (server == nil)
	{
		/*
		 * No servers available - create a new server 
		 */
		server = [[LUServer alloc] init];
		[server setIsIdle:NO];

		for (i = 0; i < NCATEGORIES; i++)
			[server setLookupOrder:lookupOrder[i] forCategory:(LUCategory)i];

		[serverList addObject:server];
	}

	[serverLock unlock];
	return server;
}

- (void)checkInServer:(LUServer *)server
{
	[serverLock lock];

	[server setIsIdle:YES];
	idleServerCount++;
	if (idleServerCount > maxIdleServers)
	{
		[serverList removeObject:server];
		[server release];
		idleServerCount--;
	}

	[serverLock unlock];
}

- (void)setLoginUser:(int)uid
{
	LUServer *s;
	char scratch[256];

	if (loginUser != nil)
	{
		[cacheAgent removeObject:loginUser];
		[loginUser release];
		loginUser = nil;
	}

	s = [self checkOutServer];
	loginUser = [s userWithNumber:&uid];
	[self checkInServer:s];

	if (loginUser != nil)
	{
		[cacheAgent addObject:loginUser];
		[loginUser setTimeToLive:(time_t)-1];
		sprintf(scratch, "%s (console user)", [loginUser banner]);
		[loginUser setBanner:scratch];
	}
}

- (void)flushCache
{
	[cacheAgent flushCache];
}

- (void)suspend
{
	/* XXX suspend */
}

/*
 * Custom lookups 
 *
 * Data lookup done here!
 */
- (BOOL)isSecurityEnabledForOption:(char *)option
{
	if ([controlNIAgent isSecurityEnabledForOption:option]) return YES;
	return NO;
}

/*
 * Data lookup done here!
 */
- (BOOL)isNetwareEnabled
{
	if ([controlNIAgent isNetwareEnabled]) return YES;
	return NO;
}

- (LUArray *)allStatistics
{
	LUArray *allStats;
	LUArray *agentStats;
	LUDictionary *cacheStats;
	LUDictionary *memoryStats;
	LUDictionary *dict;
	LUServer *server;
	char *name;
	int i, nservers, j, nstats;

	[serverLock lock];

	cacheStats = nil;
	allStats = [[LUArray alloc] init];
	[allStats setBanner:"Controller allStatistics"];

	[allStats addObject:controlStats];
	[allStats addObject:globalDict];
	for (i = 0; i < NCATEGORIES; i++)
	{
		if (configDict[i] != nil)
			[allStats addObject:configDict[i]];
	}

	nservers = [serverList count];
	for (i = 0; i < nservers; i++)
	{
		server = [serverList objectAtIndex:i];
		[allStats addObject:[server statistics]];

		agentStats = [server agentStatistics];
		nstats = [agentStats count];
		for (j = 0; j < nstats; j++)
		{
			dict = [agentStats objectAtIndex:j];
			name = [dict valueForKey:"information_system"];
			if (name == NULL)
				[allStats addObject:dict];
			else if (strcmp(name, "Cache"))
				[allStats addObject:dict];
			else
				cacheStats = dict;
		}
		[agentStats release];
	}

	if (cacheStats != nil) [allStats addObject:cacheStats];
	memoryStats = [rover statistics];
	if (memoryStats != nil) [allStats addObject:memoryStats];

	[serverLock unlock];
	return allStats;
}

- (void)rpcLock
{
	[rpcLock lock];
}

- (void)rpcUnlock
{
	[rpcLock unlock];
}

@end
