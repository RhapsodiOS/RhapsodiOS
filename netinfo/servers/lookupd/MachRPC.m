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
	MachRPC.m

	Custom RPC on top of Mach IPC for lookupd
	libc uses this goofy idea to talk to lookupd
	
	Copyright (c) 1995, NeXT Computer Inc.
	All rights reserved.
	Written by Marc Majka
 */

#import "MachRPC.h"
#import "Syslog.h"
#import "LUGlobal.h"
#import "LUPrivate.h"
#import <mach/message.h>
#import <mach/mach_error.h>
#import <mach/mig_errors.h>
#import <mach/cthreads.h>
#import <rpc/types.h>
#import <rpc/xdr.h>
#import <netinfo/lookup_types.h>
#import "_lu_types.h"
#import <netdb.h>
#import <arpa/inet.h>
#import <strings.h>
#import "stringops.h"
#import <stdio.h>

/* 2 second timeout on sends */
#define TIMEOUT_MSECONDS (2000)
#define XDRSIZE 8192

extern kern_return_t lookup_server(lookup_msg *, lookup_msg *);
extern char *proc_name(int);
extern char *ether_ntoa(struct ether_addr *);
char *nettoa(unsigned long net);
extern BOOL shadowPasswords;

@implementation MachRPC

int thread_id()
{
	return (int)cthread_data(cthread_self());
}

- (MachRPC *)init:(id)sender
{
	[super init];

	xdr = [[XDRSerializer alloc] init];

	userSel = @selector(encodeUser:intoXdr:);
	userSel_A = @selector(encodeUser_A:intoXdr:);
	groupSel = @selector(encodeGroup:intoXdr:);
	userShadowedSel = @selector(encodeShadowedUser:intoXdr:);
	userShadowedSel_A = @selector(encodeShadowedUser_A:intoXdr:);
	groupShadowedSel = @selector(encodeShadowedGroup:intoXdr:);
	hostSel = @selector(encodeHost:intoXdr:);
	networkSel = @selector(encodeNetwork:intoXdr:);
	serviceSel = @selector(encodeService:intoXdr:);
	protocolSel = @selector(encodeProtocol:intoXdr:);
	rpcSel = @selector(encodeRpc:intoXdr:);
	mountSel = @selector(encodeMount:intoXdr:);
	printerSel = @selector(encodePrinter:intoXdr:);
	bootparamsSel = @selector(encodeBootparams:intoXdr:);
	bootpSel = @selector(encodeBootp:intoXdr:);
	aliasSel = @selector(encodeAlias:intoXdr:);

	return self;
}

- (void)dealloc
{
	if (xdr != nil) [xdr release];
	[super dealloc];
}

- (BOOL)process:(lookup_msg *)request
{
	kern_return_t status;
	lookup_msg reply;
	char str[128];

	reply.head.msg_local_port = request->head.msg_local_port;

	/*
	 * Use the MIG server to dispatch messages.
	 * Server functions for the MIG interface are in lookup_proc.m
	 */ 
	status = lookup_server(request, &reply);
	if (status == MIG_NO_REPLY) return NO;

	status = msg_send((msg_header_t *)&reply, 
		SEND_NOTIFY | SEND_TIMEOUT, TIMEOUT_MSECONDS);

	if (status != KERN_SUCCESS)
	{
		if (status != SEND_INVALID_PORT)
		{
			sprintf(str, "msg_send failed (%s)", mach_errormsg(status));
			[lookupLog syslogError:str];
		}
	}

	return (status == KERN_SUCCESS);
}

/*
 * Called by MIG server routines in lookup_proc.m
 */
- (BOOL)process:(int)procno
	inData:(char *)indata
	inLength:(unsigned int)inlen
	outData:(char **)outdata
	outLength:(unsigned int *)outlen
	privileged:(BOOL)privileged
{
	LUDictionary *dict;
	LUDictionary *serviceDict;
	LUArray *list;
	LUServer *server;
	int i;
	struct in_addr ip;
	struct ether_addr ether;
	char *name;
	char *proto;
	char **stuff;
	BOOL resultIsList;
	BOOL test;
	char logString[128], str[256];
	SEL aSel;

	sprintf(logString, "thread %d: %s", thread_id(), proc_name(procno));

	server = [controller checkOutServer];
	if (server == nil) return KERN_FAILURE;

	list = nil;
	dict = nil;
	resultIsList = NO;

	if (!shadowPasswords) privileged = YES;

	switch (procno)
	{
		case 0: /* getpwent */
			[lookupLog syslogDebug:logString];
			list = [server allUsers];
			aSel = privileged ? userSel : userShadowedSel;
			resultIsList = YES;
			break;
		case 1: /* getpwent_A */
			[lookupLog syslogDebug:logString];
			list = [server allUsers];
			aSel = privileged ? userSel_A : userShadowedSel_A;
			resultIsList = YES;
			break;
		case 2: /* getpwuid */
			i = [xdr intFromBuffer:indata length:inlen];
			sprintf(str,"%s %d", logString, i);
			[lookupLog syslogDebug:str];
			dict = [server userWithNumber:&i];
			aSel = privileged ? userSel : userShadowedSel;
			break;
		case 3: /* getpwuid_A */
			i = [xdr intFromBuffer:indata length:inlen];
			sprintf(str,"%s %d", logString, i);
			[lookupLog syslogDebug:str];
			dict = [server userWithNumber:&i];
			aSel = privileged ? userSel_A : userShadowedSel_A;
			break;
		case 4: /* getpwnam */
			name = [xdr stringFromBuffer:indata length:inlen];
			sprintf(str,"%s %s", logString, name);
			[lookupLog syslogDebug:str];
			dict = [server userWithName:name];
			freeString(name);
			name = NULL;
			aSel = privileged ? userSel : userShadowedSel;
			break;
		case 5: /* getpwnam_A */
			name = [xdr stringFromBuffer:indata length:inlen];
			sprintf(str,"%s %s", logString, name);
			[lookupLog syslogDebug:str];
			dict = [server userWithName:name];
			freeString(name);
			name = NULL;
			aSel = privileged ? userSel_A : userShadowedSel_A;
			break;
		case 6: /* setpwent RETURNS */
			[lookupLog syslogDebug:logString];
			*outlen = 0;
			*outdata = NULL;
			[controller checkInServer:server];
			return YES;

		case 7: /* getgrent */
			[lookupLog syslogDebug:logString];
			list = [server allGroups];
			aSel = privileged ? groupSel : groupShadowedSel;
			resultIsList = YES;
			break;
		case 8: /* getgrgid */
			i = [xdr intFromBuffer:indata length:inlen];
			sprintf(str,"%s %d", logString, i);
			[lookupLog syslogDebug:str];
			dict = [server groupWithNumber:&i];
			aSel = privileged ? groupSel : groupShadowedSel;
			break;
		case 9: /* getgrnam */
			name = [xdr stringFromBuffer:indata length:inlen];
			sprintf(str,"%s %s", logString, name);
			[lookupLog syslogDebug:str];
			dict = [server groupWithName:name];
			freeString(name);
			name = NULL;
			aSel = privileged ? groupSel : groupShadowedSel;
			break;

		case 10: /* initgroups RETURNS */
			name = [xdr stringFromBuffer:indata length:inlen];
			sprintf(str,"%s %s", logString, name);
			[lookupLog syslogDebug:str];
			list = [server allGroupsWithUser:name];
			freeString(name);
			name = NULL;
			[controller checkInServer:server];
			test = [self xdrInitgroups:list buffer:outdata length:outlen];
			[list release];
			return test;

		case 11: /* gethostent */
			[lookupLog syslogDebug:logString];
			list = [server allHosts];
			aSel = hostSel;
			resultIsList = YES;
			break;
		case 12: /* gethostbyname */
			name = [xdr stringFromBuffer:indata length:inlen];
			sprintf(str,"%s %s", logString, name);
			[lookupLog syslogDebug:str];
			dict = [server hostWithName:name];
			freeString(name);
			name = NULL;
			aSel = hostSel;
			break;
		case 13: /* gethostbyaddr */
			i = [xdr intFromBuffer:indata length:inlen];
			ip.s_addr = i;
			sprintf(str,"%s %s", logString, inet_ntoa(ip));
			[lookupLog syslogDebug:str];
			dict = [server hostWithInternetAddress:&ip];
			aSel = hostSel;
			break;

		case 14: /* getnetent */
			[lookupLog syslogDebug:logString];
			list = [server allNetworks];
			aSel = networkSel;
			resultIsList = YES;
			break;
		case 15: /* getnetbyname */
			name = [xdr stringFromBuffer:indata length:inlen];
			sprintf(str,"%s %s", logString, name);
			[lookupLog syslogDebug:str];
			dict = [server networkWithName:name];
			freeString(name);
			name = NULL;
			aSel = networkSel;
			break;
		case 16: /* getnetbyaddr */
			i = [xdr intFromBuffer:indata length:inlen];
			ip.s_addr = i;
			sprintf(str,"%s %s", logString, nettoa(i));
			[lookupLog syslogDebug:str];
			dict = [server networkWithInternetAddress:&ip];
			aSel = networkSel;
			break;

		case 17: /* getservent */
			[lookupLog syslogDebug:logString];
			list = [server allServices];
			aSel = serviceSel;
			resultIsList = YES;
			break;
		case 18: /* getservbyname */
			stuff = [xdr twoStringsFromBuffer:indata length:inlen];
			proto = stuff[1];
			sprintf(str,"%s %s %s", logString, stuff[0], proto);
			[lookupLog syslogDebug:str];
			if (proto[0] == '\0') proto = NULL;
			serviceDict = [server serviceWithName:stuff[0] protocol:proto];
			if (proto != NULL)
				[serviceDict setValue:proto forKey:"_lookup_service_protocol"];
			freeList(stuff);
			stuff = NULL;
			dict = serviceDict;
			aSel = serviceSel;
			break;
		case 19: /* getservbyport */
			stuff = [xdr intAndStringFromBuffer:indata length:inlen];
			i = atoi(stuff[0]);
			proto = stuff[1];
			sprintf(str,"%s %d %s", logString, i, proto);
			[lookupLog syslogDebug:str];
			if (proto[0] == '\0') proto = NULL;
			serviceDict = [server serviceWithNumber:&i protocol:proto];
			if (proto != NULL)
				[serviceDict setValue:proto forKey:"_lookup_service_protocol"];
			freeList(stuff);
			stuff = NULL;
			dict = serviceDict;
			aSel = serviceSel;
			break;

		case 20: /* getprotoent */
			[lookupLog syslogDebug:logString];
			list = [server allProtocols];
			aSel = protocolSel;
			resultIsList = YES;
			break;
		case 21: /* getprotobyname */
			name = [xdr stringFromBuffer:indata length:inlen];
			sprintf(str,"%s %s", logString, name);
			[lookupLog syslogDebug:str];
			dict = [server protocolWithName:name];
			freeString(name);
			name = NULL;
			aSel = protocolSel;
			break;
		case 22: /* getprotobynumber */
			i = [xdr intFromBuffer:indata length:inlen];
			sprintf(str,"%s %d", logString, i);
			[lookupLog syslogDebug:str];
			dict = [server protocolWithNumber:&i];
			aSel = protocolSel;
			break;

		case 23: /* getrpcent */
			[lookupLog syslogDebug:logString];
			list = [server allRpcs];
			aSel = rpcSel;
			resultIsList = YES;
			break;
		case 24: /* getrpcbyname */
			name = [xdr stringFromBuffer:indata length:inlen];
			sprintf(str,"%s %s", logString, name);
			[lookupLog syslogDebug:str];
			dict = [server rpcWithName:name];
			freeString(name);
			name = NULL;
			aSel = rpcSel;
			break;
		case 25: /* getrpcbynumber */
			i = [xdr intFromBuffer:indata length:inlen];
			sprintf(str,"%s %d", logString, i);
			[lookupLog syslogDebug:str];
			dict = [server rpcWithNumber:&i];
			aSel = rpcSel;
			break;

		case 26: /* getfsent */
			[lookupLog syslogDebug:logString];
			list = [server allMounts];
			aSel = mountSel;
			resultIsList = YES;
			break;
		case 27: /* getfsbyname (NEW) */
			name = [xdr stringFromBuffer:indata length:inlen];
			sprintf(str,"%s %s", logString, name);
			[lookupLog syslogDebug:str];
			dict = [server mountWithName:name];
			freeString(name);
			name = NULL;
			aSel = mountSel;
			break;

		case 28: /* prdb_get */
			[lookupLog syslogDebug:logString];
			list = [server allPrinters];
			aSel = printerSel;
			resultIsList = YES;
			break;
		case 29: /* prdb_getbyname */
			name = [xdr stringFromBuffer:indata length:inlen];
			sprintf(str,"%s %s", logString, name);
			[lookupLog syslogDebug:str];
			dict = [server printerWithName:name];
			freeString(name);
			name = NULL;
			aSel = printerSel;
			break;

		case 30: /* bootparams_getent (NEW) */
			[lookupLog syslogDebug:logString];
			list = [server allBootparams];
			aSel = bootparamsSel;
			resultIsList = YES;
			break;
		case 31: /* bootparams_getbyname */
			name = [xdr stringFromBuffer:indata length:inlen];
			sprintf(str,"%s %s", logString, name);
			[lookupLog syslogDebug:str];
			dict = [server bootparamsWithName:name];
			freeString(name);
			name = NULL;
			aSel = bootparamsSel;
			break;

		case 32: /* bootp_getbyip */
			i = [xdr intFromBuffer:indata length:inlen];
			ip.s_addr = i;
			sprintf(str,"%s %s", logString, inet_ntoa(ip));
			[lookupLog syslogDebug:str];
			dict = [server bootpWithInternetAddress:&ip];
			aSel = bootpSel;
			break;
		case 33: /* bootp_getbyether */
			ether = [xdr ethernetAddressFromBuffer:indata length:inlen];
			sprintf(str,"%s %s", logString, ether_ntoa(&ether));
			[lookupLog syslogDebug:str];
			dict = [server bootpWithEthernetAddress:&ether];
			aSel = bootpSel;
			break;

		case 34: /* alias_getbyname */
			name = [xdr stringFromBuffer:indata length:inlen];
			sprintf(str,"%s %s", logString, name);
			[lookupLog syslogDebug:str];
			dict = [server aliasWithName:name];
			freeString(name);
			name = NULL;
			aSel = aliasSel;
			break;
		case 35: /* alias_getent */
			[lookupLog syslogDebug:logString];
			list = [server allAliases];
			aSel = aliasSel;
			resultIsList = YES;
			break;
		case 36: /* alias_setent RETURNS */
			[lookupLog syslogDebug:logString];
			*outlen = 0;
			*outdata = NULL;
			[controller checkInServer:server];
			return YES;

		case 37: /* innetgr RETURNS */
			stuff = [xdr inNetgroupArgsFromBuffer:indata length:inlen];
			sprintf(str, "%s %s (%s, %s, %s)",
				logString, stuff[0], stuff[1], stuff[2], stuff[3]);
			[lookupLog syslogDebug:str];
			test = [server inNetgroup:stuff[0]
				host:((stuff[1][0] == '\0') ? NULL : stuff[1])
				user:((stuff[2][0] == '\0') ? NULL : stuff[2])
				domain:((stuff[3][0] == '\0') ? NULL : stuff[3])];
			[self xdrInt:(test ? 1 : 0) buffer:outdata length:outlen];
			freeList(stuff);
			stuff = NULL;
			[controller checkInServer:server];
			return YES;

		case 38: /* getnetgrent (really getnetgrbyname) RETURNS */
			name = [xdr stringFromBuffer:indata length:inlen];
			sprintf(str,"%s %s", logString, name);
			[lookupLog syslogDebug:str];
			dict = [server netgroupWithName:name];
			freeString(name);
			name = NULL;
			test = [self xdrNetgroup:dict buffer:outdata length:outlen server:server];
			[controller checkInServer:server];
			[dict release];
			return test;

		case 39: /* checksecurityopt RETURNS */
			name = [xdr stringFromBuffer:indata length:inlen];
			sprintf(str,"%s %s", logString, name);
			[lookupLog syslogDebug:str];
			test = [controller isSecurityEnabledForOption:name];
			freeString(name);
			name = NULL;
			[self xdrInt:(test ? 1 : 0) buffer:outdata length:outlen];
			[controller checkInServer:server];
			return YES;
		case 40: /* checknetwareenbl RETURNS */
			[lookupLog syslogDebug:logString];
			test = [controller isNetwareEnabled];
			[self xdrInt:(test ? 1 : 0) buffer:outdata length:outlen];
			[controller checkInServer:server];
			return YES;
		case 41: /* setloginuser RETURNS */
			i = [xdr intFromBuffer:indata length:inlen];
			sprintf(str,"%s %d", logString, i);
			[lookupLog syslogDebug:str];
			[controller setLoginUser:i];
			[self xdrInt:1 buffer:outdata length:outlen];
			[controller checkInServer:server];
			return YES;
		case 42: /* _getstatistics RETURNS */
			/* XXX implement MachRPC _getstatistics */
			[lookupLog syslogDebug:logString];
			[self xdrInt:0 buffer:outdata length:outlen];
			[controller checkInServer:server];
			return YES;
		case 43: /* _invalidatecache RETURNS */
			[lookupLog syslogDebug:logString];
			[controller flushCache];
			[self xdrInt:1 buffer:outdata length:outlen];
			[controller checkInServer:server];
			return YES;
		case 44: /* _suspend RETURNS */
			/* XXX implement MachRPC _suspend */
			[lookupLog syslogDebug:logString];
			[controller suspend];
			[self xdrInt:1 buffer:outdata length:outlen];
			[controller checkInServer:server];
			return YES;
		default: 
			[controller checkInServer:server];
			return NO;
	}

	[controller checkInServer:server];
	if (resultIsList)
	{
		test = [self xdrList:list method:aSel buffer:outdata length:outlen server:server];
		[list release];
		return test;
	}

	test = [self xdrItem:dict method:aSel buffer:outdata length:outlen];
	[dict release];
	return test;
}

- (void)encodeUser_A:(LUDictionary *)item intoXdr:(XDR *)xdrs
{
	[xdr encodeString:	"name"		from:item intoXdr:xdrs];
	[xdr encodeString:	"passwd"	from:item intoXdr:xdrs];
	[xdr encodeInt:		"uid"		from:item intoXdr:xdrs];
	[xdr encodeInt:		"gid"		from:item intoXdr:xdrs];
	[xdr encodeInt:		"change"	from:item intoXdr:xdrs];
	[xdr encodeString:	"class"		from:item intoXdr:xdrs];
	[xdr encodeString:	"realname"	from:item intoXdr:xdrs];
	[xdr encodeString:	"home"		from:item intoXdr:xdrs];
	[xdr encodeString:	"shell"		from:item intoXdr:xdrs];
	[xdr encodeInt:		"expire"	from:item intoXdr:xdrs];
}

- (void)encodeUser:(LUDictionary *)item intoXdr:(XDR *)xdrs
{
	[xdr encodeString:	"name"		from:item intoXdr:xdrs];
	[xdr encodeString:	"passwd"	from:item intoXdr:xdrs];
	[xdr encodeInt:		"uid"		from:item intoXdr:xdrs];
	[xdr encodeInt:		"gid"		from:item intoXdr:xdrs];
	[xdr encodeString:	"realname"	from:item intoXdr:xdrs];
	[xdr encodeString:	"home"		from:item intoXdr:xdrs];
	[xdr encodeString:	"shell"		from:item intoXdr:xdrs];
}

- (void)encodeGroup:(LUDictionary *)item intoXdr:(XDR *)xdrs
{
	[xdr encodeString:	"name"		from:item intoXdr:xdrs];
	[xdr encodeString:	"passwd"	from:item intoXdr:xdrs];
	[xdr encodeInt:		"gid"		from:item intoXdr:xdrs];
	[xdr encodeStrings:	"users"		from:item intoXdr:xdrs max:_LU_MAXGRP];
}

- (void)encodeShadowedUser_A:(LUDictionary *)item intoXdr:(XDR *)xdrs
{
	[xdr encodeString:	"name"		from:item intoXdr:xdrs];
	[xdr encodeString:	"*"		intoXdr:xdrs];
	[xdr encodeInt:		"uid"		from:item intoXdr:xdrs];
	[xdr encodeInt:		"gid"		from:item intoXdr:xdrs];
	[xdr encodeInt:		"change"	from:item intoXdr:xdrs];
	[xdr encodeString:	"class"		from:item intoXdr:xdrs];
	[xdr encodeString:	"realname"	from:item intoXdr:xdrs];
	[xdr encodeString:	"home"		from:item intoXdr:xdrs];
	[xdr encodeString:	"shell"		from:item intoXdr:xdrs];
	[xdr encodeInt:		"expire"	from:item intoXdr:xdrs];
}

- (void)encodeShadowedUser:(LUDictionary *)item intoXdr:(XDR *)xdrs
{
	[xdr encodeString:	"name"		from:item intoXdr:xdrs];
	[xdr encodeString:	"*"		intoXdr:xdrs];
	[xdr encodeInt:		"uid"		from:item intoXdr:xdrs];
	[xdr encodeInt:		"gid"		from:item intoXdr:xdrs];
	[xdr encodeString:	"realname"	from:item intoXdr:xdrs];
	[xdr encodeString:	"home"		from:item intoXdr:xdrs];
	[xdr encodeString:	"shell"		from:item intoXdr:xdrs];
}

- (void)encodeShadowedGroup:(LUDictionary *)item intoXdr:(XDR *)xdrs
{
	[xdr encodeString:	"name"		from:item intoXdr:xdrs];
	[xdr encodeString:	"*"		intoXdr:xdrs];
	[xdr encodeInt:		"gid"		from:item intoXdr:xdrs];
	[xdr encodeStrings:	"users"		from:item intoXdr:xdrs max:_LU_MAXGRP];
}

- (void)encodeHost:(LUDictionary *)item intoXdr:(XDR *)xdrs
{
	[xdr encodeStrings:	"name"			from:item intoXdr:xdrs max:_LU_MAXHNAMES];
	[xdr encodeIPAddrs:	"ip_address"	from:item intoXdr:xdrs max:_LU_MAXADDRS];
}

- (void)encodeNetwork:(LUDictionary *)item intoXdr:(XDR *)xdrs
{
	[xdr encodeStrings:	"name"		from:item intoXdr:xdrs max:_LU_MAXNNAMES];
	[xdr encodeNetAddr:	"address"	from:item intoXdr:xdrs];
}

- (void)encodeService:(LUDictionary *)item intoXdr:(XDR *)xdrs
{
	char **portList;
	int portcount;
	unsigned long p;
	char *proto;

	proto = [item valueForKey:"_lookup_service_protocol"];
	if (proto != NULL)
	{
		if (proto[0] == '\0') proto = NULL;
	}

	[xdr encodeStrings:"name" from:item intoXdr:xdrs max:_LU_MAXSNAMES];

	portList = [item valuesForKey:"port"];
	portcount = [item countForKey:"port"];
	if (portcount <= 0) p = -1;
	else p = htons(atoi(portList[0]));

	[xdr encodeInt:p intoXdr:xdrs];

	if (proto == NULL)
		[xdr encodeString:"protocol" from:item intoXdr:xdrs];
	else
		[xdr encodeString:proto intoXdr:xdrs];
}

- (void)encodeProtocol:(LUDictionary *)item intoXdr:(XDR *)xdrs
{
	[xdr encodeStrings:	"name"		from:item intoXdr:xdrs max:_LU_MAXPNAMES];
	[xdr encodeInt:		"number"	from:item intoXdr:xdrs];
}

- (void)encodeRpc:(LUDictionary *)item intoXdr:(XDR *)xdrs
{
	[xdr encodeStrings:	"name"		from:item intoXdr:xdrs max:_LU_MAXRNAMES];
	[xdr encodeInt:		"number"	from:item intoXdr:xdrs];
}

- (void)encodeMount:(LUDictionary *)item intoXdr:(XDR *)xdrs
{
	char *opts;
	char type[8];
	char **optsList;
	int i, count, len;

	[xdr encodeString:	"name"		from:item intoXdr:xdrs];
	[xdr encodeString:	"dir"		from:item intoXdr:xdrs];
	[xdr encodeString:	"vfstype"	from:item intoXdr:xdrs];

	optsList = [item valuesForKey:"opts"];
	if (optsList == NULL) count = 0;
	else count = [item countForKey:"opts"];
	if (count < 0) count = 0;

	len = 0;
	for (i = 0; i < count; i++)
	{
		len += strlen(optsList[i]);
		if (i < (count - 1)) len++;
	}

	opts = malloc(len + 1);

	strcpy(type, "rw");

	opts[0] = '\0';
	for (i = 0; i < count; i++)
	{
		strcat(opts, optsList[i]);
		if (i < (count - 1)) strcat(opts, ",");
	
		if ((!strcmp(optsList[i], "rw")) ||
			(!strcmp(optsList[i], "rq")) ||
			(!strcmp(optsList[i], "ro")) ||
			(!strcmp(optsList[i], "sw")) ||
			(!strcmp(optsList[i], "xx")))
		{
			strcpy(type, optsList[i]);
		}
	}

	[xdr encodeString:	opts 	intoXdr:xdrs];
	[xdr encodeString:	type 	intoXdr:xdrs];
	[xdr encodeInt:		"freq"		from:item intoXdr:xdrs];
	[xdr encodeInt:		"passno"	from:item intoXdr:xdrs];
	free(opts);
}

- (void)encodePrinter:(LUDictionary *)item intoXdr:(XDR *)xdrs
{
	char *key;
	int i, count;
	char **l = NULL;
	char str[128];

	[xdr encodeStrings:"name" from:item intoXdr:xdrs max:_LU_MAXPRNAMES];

	count = 0;
	for (i = 0; NULL != (key = [item keyAtIndex:i]); i++)
	{
		if (!strncmp(key, "_lookup_", 8)) continue;
		if (!strcmp(key, "name")) continue;
		count++;
		l = appendString(key, l);
	}

	if (count > _LU_MAXPRPROPS)
	{
		sprintf(str, "truncating at %d values", _LU_MAXPRPROPS);
		[lookupLog syslogError:str];
		count = _LU_MAXPRPROPS;
	}

	[xdr encodeInt:count intoXdr:xdrs];
	for (i = 0; i < count; i++)
	{
		[xdr encodeString:l[i] intoXdr:xdrs];
		[xdr encodeString:l[i] from:item intoXdr:xdrs];
	}
	freeList(l);
	l = NULL;
}

- (void)encodeBootparams:(LUDictionary *)item intoXdr:(XDR *)xdrs
{
	[xdr encodeString:	"name"			from:item intoXdr:xdrs];
	[xdr encodeStrings:	"bootparams"	from:item intoXdr:xdrs max:_LU_MAX_BOOTPARAMS_KV];
}

- (void)encodeBootp:(LUDictionary *)item intoXdr:(XDR *)xdrs
{
	[xdr encodeString:	"name"			from:item intoXdr:xdrs];
	[xdr encodeString:	"bootfile"		from:item intoXdr:xdrs];
	[xdr encodeIPAddr:	"ip_address"	from:item intoXdr:xdrs];
	[xdr encodeENAddr:	"en_address"	from:item intoXdr:xdrs];
}

- (void)encodeAlias:(LUDictionary *)item intoXdr:(XDR *)xdrs
{
	[xdr encodeString:	"name"			from:item intoXdr:xdrs];
	[xdr encodeStrings:	"members"		from:item intoXdr:xdrs max:_LU_MAXALIASMEMBERS];
	[xdr encodeInt:		"alias_local"	from:item intoXdr:xdrs];
}

- (BOOL)xdrNetgroup:(LUDictionary *)item buffer:(char **)data length:(int *)len server:(LUServer *)server
{
	unsigned long i, count, size, offset;
	char **names;
	char *xdrBuffer;
	XDR outxdr;

	if (item == nil) return NO;

	xdrBuffer = malloc(XDRSIZE);

	count = 0;
	i = [item countForKey:"hosts"];
	if (i != IndexNull) count += i;
	i = [item countForKey:"users"];
	if (i != IndexNull) count += i;
	i = [item countForKey:"domains"];
	if (i != IndexNull) count += i;

	offset = 0;
	xdrmem_create(&outxdr, xdrBuffer, XDRSIZE, XDR_ENCODE);

	if (!xdr_u_long(&outxdr, &count))
	{
		xdr_destroy(&outxdr);
		free(xdrBuffer);
		return NO;
	}

	size = xdr_getpos(&outxdr);
	[server copyToOOBuffer:xdrBuffer size:size offset:offset];
	offset += size;

	/* XXX Netgroups as members of other netgroups not supported! */

	names = [item valuesForKey:"hosts"];
	count = [item countForKey:"hosts"];
	if (count == IndexNull) count = 0;
	for (i = 0; i < count; i++)
	{
		xdr_setpos(&outxdr, 0);
		[xdr encodeString:names[i] intoXdr:&outxdr];
		[xdr encodeString:"-" intoXdr:&outxdr];
		[xdr encodeString:"-" intoXdr:&outxdr];
		size = xdr_getpos(&outxdr);
		[server copyToOOBuffer:xdrBuffer size:size offset:offset];
		offset += size;
	}

	names = [item valuesForKey:"users"];
	count = [item countForKey:"users"];
	if (count == IndexNull) count = 0;
	for (i = 0; i < count; i++)
	{
		xdr_setpos(&outxdr, 0);
		[xdr encodeString:"-" intoXdr:&outxdr];
		[xdr encodeString:names[i] intoXdr:&outxdr];
		[xdr encodeString:"-" intoXdr:&outxdr];
		size = xdr_getpos(&outxdr);
		[server copyToOOBuffer:xdrBuffer size:size offset:offset];
		offset += size;
	}

	names = [item valuesForKey:"domains"];
	count = [item countForKey:"domains"];
	if (count == IndexNull) count = 0;
	for (i = 0; i < count; i++)
	{
		xdr_setpos(&outxdr, 0);
		[xdr encodeString:"-" intoXdr:&outxdr];
		[xdr encodeString:"-" intoXdr:&outxdr];
		[xdr encodeString:names[i] intoXdr:&outxdr];
		size = xdr_getpos(&outxdr);
		[server copyToOOBuffer:xdrBuffer size:size offset:offset];
		offset += size;
	}

	*len = offset;
	*data = [server ooBuffer];
	xdr_destroy(&outxdr);
	free(xdrBuffer);

	return YES;
}


- (BOOL)xdrInt:(int)i buffer:(char **)data length:(int *)len
{
	XDR outxdr;
	BOOL status;

	xdrmem_create(&outxdr, *data, MAX_INLINE_DATA, XDR_ENCODE);

	status = xdr_int(&outxdr, &i);
	if (!status)
	{
		[lookupLog syslogError:"xdr_int failed"];
		xdr_destroy(&outxdr);
		return NO;
	}

	*len = xdr_getpos(&outxdr);
	xdr_destroy(&outxdr);
	return YES;
}

- (BOOL)xdrList:(LUArray *)list
	method:(SEL)method
	buffer:(char **)data
	length:(int *)len
	server:(LUServer *)server
{
	unsigned long i, count, size, offset;
	static LUDictionary *item;
	char *xdrBuffer;
	XDR outxdr;

	if (list == nil) return NO;

	xdrBuffer = malloc(XDRSIZE);
	
	xdrmem_create(&outxdr, xdrBuffer, XDRSIZE, XDR_ENCODE);
	count = [list count];

	offset = 0;
	if (!xdr_u_long(&outxdr, &count))
	{
		xdr_destroy(&outxdr);
		free(xdrBuffer);
		return NO;
	}

	size = xdr_getpos(&outxdr);
	[server copyToOOBuffer:xdrBuffer size:size offset:offset];
	offset += size;

	for (i = 0; i < count; i++)
	{
		item = [list objectAtIndex:i];
		xdr_setpos(&outxdr, 0);

#if NS_TARGET_MAJOR == 3
		[self perform:method withObject:item withObject:(id)&outxdr];
#else
		[self performSelector:method withObject:item withObject:(id)&outxdr];
#endif

		size = xdr_getpos(&outxdr);
		[server copyToOOBuffer:xdrBuffer size:size offset:offset];
		offset += size;
	}

	*len = offset;
	*data = [server ooBuffer];
	xdr_destroy(&outxdr);
	free(xdrBuffer);

	return YES;
}

- (BOOL)xdrItem:(LUDictionary *)item
	method:(SEL)method
	buffer:(char **)data
	length:(int *)len
{
	XDR outxdr;
	BOOL realData;
	int h_errno;
	BOOL status;

	xdrmem_create(&outxdr, *data, MAX_INLINE_DATA, XDR_ENCODE);

	realData = (item != nil);
	[xdr encodeBool:realData intoXdr:&outxdr];

	if (!realData)
	{
		if (method == hostSel)
		{
			h_errno = HOST_NOT_FOUND;
			status = xdr_int(&outxdr, &h_errno);
			if (!status)
			{
				[lookupLog syslogError:"xdr_int failed"];
				xdr_destroy(&outxdr);
				return NO;
			}
		}
		*len = xdr_getpos(&outxdr);
		xdr_destroy(&outxdr);
		return YES;
	}

#if NS_TARGET_MAJOR == 3
	[self perform:method withObject:item withObject:(id)&outxdr];
#else
	[self performSelector:method withObject:item withObject:(id)&outxdr];
#endif

	if (method == hostSel)
	{
		h_errno = 0;
		status = xdr_int(&outxdr, &h_errno);
		if (!status)
		{
			[lookupLog syslogError:"xdr_int failed"];
			xdr_destroy(&outxdr);
			return NO;
		}
	}

	*len = xdr_getpos(&outxdr);
	xdr_destroy(&outxdr);
	return YES;
}

- (BOOL)xdrInitgroups:(LUArray *)list buffer:(char **)data length:(int *)len
{
	XDR outxdr;
	char **gidsSent = NULL;
	char **gids;
	LUDictionary *group;
	int j, ngids;
	int i, count;
	int n;

	if (list == nil) return NO;

	count = [list count];
	if (count == 0) return NO;

	xdrmem_create(&outxdr, *data, MAX_INLINE_DATA, XDR_ENCODE);

	for (i = 0; i < count; i++)
	{
		group = [list objectAtIndex:i];
		gids = [group valuesForKey:"gid"];
		if (gids == NULL) continue;
		ngids = [group countForKey:"gid"];
		if (ngids < 0) ngids = 0;
		for (j = 0; j < ngids; j++)
		{
			if (listIndex(gids[j], gidsSent) != IndexNull) continue;
			gidsSent = appendString(gids[j], gidsSent);
			n = atoi(gids[j]);
			[xdr encodeInt:n intoXdr:&outxdr];
		}
	}

	n = -99; /* XXX STUPID ENCODING ALERT - fix in libc someday */
	[xdr encodeInt:n intoXdr:&outxdr];

	*len = xdr_getpos(&outxdr);
	xdr_destroy(&outxdr);
	return YES;
}

@end
