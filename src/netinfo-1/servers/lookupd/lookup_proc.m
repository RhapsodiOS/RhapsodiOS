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
 * MIG server procedure implementation
 * Copyright (C) 1989 by NeXT, Inc.
 */
 
#import <mach/mach.h>
#import <mach/message.h>
#import <rpc/types.h>
#import <rpc/xdr.h>
#import <netinfo/lookup_types.h>
#include "MachRPC.h"
#include "Syslog.h"
#include "LUPrivate.h"

extern port_t server_port;
extern port_t server_port_unprivileged;
extern port_t server_port_privileged;

typedef struct lookup_node {
	char *name;
	int returns_list;
} lookup_node;

static lookup_node _lookup_links[] = { 
	{ "getpwent", 1 },
	{ "getpwent_A", 1 },

	{ "getpwuid", 0 },
	{ "getpwuid_A", 0 },

	{ "getpwnam", 0 },
	{ "getpwnam_A", 0 },

	{ "setpwent", 1 },

	{ "getgrent", 1 },
	{ "getgrgid", 0 },
	{ "getgrnam", 0 },
	{ "initgroups", 0 },

	{ "gethostent", 1 },
	{ "gethostbyname", 0 },
	{ "gethostbyaddr", 0 },

	{ "getnetent", 1 },
	{ "getnetbyname", 0 },
	{ "getnetbyaddr", 0 },

	{ "getservent", 1 },
	{ "getservbyname", 0 },
	{ "getservbyport", 0 },

	{ "getprotoent", 1 },
	{ "getprotobyname", 0 },
	{ "getprotobynumber", 0 },

	{ "getrpcent", 1 },
	{ "getrpcbyname", 0 },
	{ "getrpcbynumber", 0 },

	{ "getfsent", 1 },
	{ "getfsbyname", 0 },

	{ "prdb_get", 1 },
	{ "prdb_getbyname", 0 },

	{ "bootparams_getent", 1 },
	{ "bootparams_getbyname", 0 },

	{ "bootp_getbyip", 0 },
	{ "bootp_getbyether", 0 },

	{ "alias_getbyname", 0 },
	{ "alias_getent", 1 },
	{ "alias_setent", 1 },

	{ "innetgr", 0 },
	{ "getnetgrent", 1 },

	{ "checksecurityopt", 0 },
	{ "checknetwareenbl", 0 },
	{ "setloginuser", 0 },
	{ "_getstatistics", 0 },
	{ "_invalidatecache", 0 },
	{ "_suspend", 0 }
};

#define LOOKUP_NPROCS  (sizeof(_lookup_links)/sizeof(_lookup_links[0]))

char *proc_name(int procno)
{
	if (procno < 0 || procno >= LOOKUP_NPROCS) {
		return "";
	}
	return _lookup_links[procno].name;
}

kern_return_t __lookup_link
(
	port_t server,
	lookup_name name,
	int *procno
)
{
	int i;
	char str[256];

	for (i = 0; i < LOOKUP_NPROCS; i++) {
		if (!strcmp(name, _lookup_links[i].name)) {
			*procno = i;
#ifdef DEBUG
			sprintf(str, "_lookup_links[%s] = %d", name, i);
			[lookupLog syslogDebug:str];
#endif
			return KERN_SUCCESS;
		}
	}
	sprintf(str, "_lookup_links[%s] failed", name);
	[lookupLog syslogNotice:str];
	return KERN_FAILURE;
}

kern_return_t __lookup_all
(
	port_t server,
	int procno,
	inline_data indata,
	unsigned inlen,
	ooline_data *outdata,
	unsigned *outlen
)
{
	BOOL status;
#ifdef DEBUG
	char str[256];

	sprintf(str, "_lookup_all[%d]", procno);
	[lookupLog syslogDebug:str];
#endif

	if (procno < 0 || procno >= LOOKUP_NPROCS) {
		return KERN_FAILURE;
	}

	if (!_lookup_links[procno].returns_list) {
		return KERN_FAILURE;
	}

	inlen *= BYTES_PER_XDR_UNIT;

	status = [machRPC process:procno
		inData:(char *)indata
		inLength:inlen
		outData:(char **)outdata
		outLength:outlen
		privileged:(server == server_port_privileged)];

	if (!status) {
		[lookupLog syslogNotice:"_lookup_all failed"];
		return KERN_FAILURE;
	}

	*outlen /= BYTES_PER_XDR_UNIT;
	return KERN_SUCCESS;
}

kern_return_t __lookup_one
(
	port_t server,
	int procno,
	inline_data indata,
	unsigned inlen,
	inline_data outdata,
	unsigned *outlen
)
{
	BOOL status;
#ifdef DEBUG
	char str[256];

	sprintf(str, "_lookup_one[%d]", procno);
	[lookupLog syslogDebug:str];
#endif

	if (procno < 0 || procno >= LOOKUP_NPROCS) {
		return KERN_FAILURE;
	}

	if (_lookup_links[procno].returns_list) {
		return KERN_FAILURE;
	}

	inlen *= BYTES_PER_XDR_UNIT;

	status = [machRPC process:procno
		inData:(char *)indata
		inLength:inlen
		outData:(char **)&outdata
		outLength:outlen
		privileged:(server == server_port_privileged)];

	if (!status) {
		[lookupLog syslogNotice:"_lookup_one failed"];
		return KERN_FAILURE;
	}

	*outlen /= BYTES_PER_XDR_UNIT;
	return KERN_SUCCESS;
}

void dealloc
(
	ooline_data data,
	unsigned len
)
{
	(void)vm_deallocate(task_self(), (vm_address_t)data, len * UNIT_SIZE);
}

kern_return_t __lookup_ooall
(
	port_t server,
	int procno,
	ooline_data indata,
	unsigned inlen,
	ooline_data *outdata,
	unsigned *outlen
)
{
	BOOL status;
#ifdef DEBUG
	char str[256];

	sprintf(str, "_lookup_ooall[%d]", procno);
	[lookupLog syslogDebug:str];
#endif

	if (procno < 0 || procno >= LOOKUP_NPROCS) {
		dealloc(indata, inlen);
		return KERN_FAILURE;
	}

	if (!_lookup_links[procno].returns_list) {
		dealloc(indata, inlen);
		return KERN_FAILURE;
	}

	inlen *= BYTES_PER_XDR_UNIT;

	status = [machRPC process:procno
		inData:(char *)indata
		inLength:inlen
		outData:(char **)&outdata
		outLength:outlen
		privileged:(server == server_port_privileged)];

	if (!status) {
		[lookupLog syslogNotice:"_lookup_ooall failed"];
		return KERN_FAILURE;
	}

	*outlen /= BYTES_PER_XDR_UNIT;
	return KERN_SUCCESS;
}
