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
	Controller.h

	Controller for lookupd
	
	Copyright (c) 1995, NeXT Computer Inc.
	All rights reserved.
 */

#if NS_TARGET_MAJOR == 3
#import <foundation/NSObject.h>
#import <foundation/NSArray.h>
#import <foundation/NSLock.h>
#else
#import <Foundation/NSObject.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSLock.h>
#endif

#import <mach/mach.h>
#import <netinfo/lookup_types.h>
#import "LUDictionary.h"
#import "LUArray.h"
#import "LUGlobal.h"
#import "LUServer.h"
#import "NIAgent.h"
#import "CacheAgent.h"


typedef struct lookup_msg {
	msg_header_t head;
	msg_type_t itype;
	int i;
	msg_type_t dtype;
	inline_data data;
} lookup_msg;

@interface Controller : NSObject
{
	NSRecursiveLock *serverLock;
	NSRecursiveLock *rpcLock;
	NSMutableArray *lookupOrder[NCATEGORIES];
	LUDictionary *globalDict;
	LUDictionary *configDict[NCATEGORIES];
	NSMutableArray *serverList;
	int maxThreads;
	int maxIdleThreads;
	int maxIdleServers;
	int threadCount;
	int idleThreadCount;
	int idleServerCount;
	NIAgent *controlNIAgent;
	CacheAgent *cacheAgent;
	LUDictionary *loginUser;
	char *configDir;
	char **agentNames;
	char *portName;
	char *doServerName;
	id doServer;
	id *agents;
	int agentCount;
	LUDictionary *controlStats;
}

- (Controller *)initWithName:(const char *)name;
- (void)initCache;
- (BOOL)registerPort:(char *)name;
- (void)startServerThread;
- (LUServer *)checkOutServer;
- (void)checkInServer:(LUServer *)server;
- (BOOL)serviceRequest:(lookup_msg *)request;

- (void)setLoginUser:(int)uid;
- (void)flushCache;
- (void)suspend;
- (BOOL)isSecurityEnabledForOption:(char *)option;
- (BOOL)isNetwareEnabled;

- (LUArray *)allStatistics;

- (void)rpcLock;
- (void)rpcUnlock;

- (char *)portName;
- (char *)doServerName;

/* You should free these directories */
- (LUDictionary *)configurationForCategory:(LUCategory)cat;
- (LUDictionary *)configurationForAgent:(char *)agent category:(LUCategory)cat;
- (LUDictionary *)configurationForAgent:(char *)agent;

- (char *)config:(LUDictionary *)dict string:(char *)key default:(char *)def;
- (int)config:(LUDictionary *)dict int:(char *)key default:(int)def;
- (BOOL)config:(LUDictionary *)dict bool:(char *)key default:(BOOL)def;

@end
