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
 * subnetDescr.h
 * - description of subnets
 */

/*
 * Modification History:
 * 
 * January 12, 1998	Dieter Siegmund (dieter@apple.com)
 * - initial revision
 */

#import <objc/Object.h>
#import <objc/List.h>

#import "clientTypes.h"
#import "util.h"

#define SUBNETS_NIDIR		"/config/dhcp/subnets"

#define NIPROP_NAME		"name"
#define NIPROP_NET_ADDRESS	"net_address"
#define NIPROP_NET_MASK		"net_mask"
#define NIPROP_NET_RANGE	"net_range"
#define NIPROP_MACHINES_DOMAIN	"machines_domain"
#define NIPROP_IP_ADDRESS	"ip_address"
#define NIPROP_CLIENT_TYPES	"client_types"
#define NIPROP_SUPERNET		"supernet"

/*
 * Constant: IPRANGE_RESCAN_SECS
 *
 * Purpose:
 *   Once the ip range is exhausted, this is the number of seconds
 *   to wait before re-scanning the ip range.
 */
#define IPRANGE_RESCAN_SECS	120

typedef boolean_t ipInUseFunc_t(void * private, struct in_addr ip);

@interface subnetEntry : Object
{
    struct in_addr	net_address;
    struct in_addr	net_mask;
    ip_range_t		ip_range;
    struct in_addr	nextip; 	/* for allocation */
    struct timeval	exhaust_time;	/* time that ip pool was exhausted */
    id			client_list;
    u_char *		supernet;	/* name of supernet entry belongs to
					 * NULL means none
					 */
}

- init;
- (ip_range_t) ipRange;
- (struct in_addr) mask;
- (boolean_t) includesClientType:(const u_char *)type;
- (int) compareIpRangeWith:b Overlap:(boolean_t *)result;
- (boolean_t) ipSameSubnet:(struct in_addr)ipaddr;
- (boolean_t) ipWithinIpRange:(struct in_addr)ipaddr;
- (boolean_t) acquireIp:(struct in_addr *)addr ClientType:(const u_char *)type
 Func:(ipInUseFunc_t *)func Arg:(void *) arg;
@end

@interface subnetList : Object
{
    id			list;
}
- (boolean_t) acquireIp:(struct in_addr *)addr ClientType:(const u_char *)t
 Func:(ipInUseFunc_t *)func Arg:(void *)arg;
- (boolean_t) addSubnet:subnet Err:(u_char *)errString;
- entry:(struct in_addr)addr;
- (boolean_t) ip:(struct in_addr) addr1 SameSupernet:(struct in_addr)addr2;
- entrySameSubnet:(struct in_addr)addr;
- list;
@end

@interface subnetEntryNI : subnetEntry
{
    void *		domain;
    ni_id		dir;
    ni_id		parent_dir;
    ni_proplist		pl;
    u_char *		name;
    boolean_t		dir_valid;
#if 0
    void *		machines_domain;
    ni_id		machines_dir;
#endif 0
}
+ (ni_proplist) proplistFromRange:(ip_range_t)range Mask:(struct in_addr)mask
 ClientTypes:(const u_char * *)types Number:(int)ntypes;
- (u_char *) name:(u_char *)name;
- init:(u_char *)errString Domain:(void *)dom ParentDir:(ni_id)p 
 Proplist:(ni_proplist)props;
- free;
- (boolean_t)write;
- (boolean_t)destroy;
- init:(u_char *)errString Domain:(void *)d ParentDir:(ni_id)p Dir:(u_long)id;
- (ni_namelist *) lookup:(u_char *) propname;
@end

@interface subnetListNI : subnetList
{
    void *		domain;
    ni_id		dir;
}
- free;
- (void *)domain;
- (ni_id)dir;
- init:(u_char *)errString;
- read:(u_char *)errString;
+ (boolean_t) createDirectoryPath:(u_char *)dirname;
@end

