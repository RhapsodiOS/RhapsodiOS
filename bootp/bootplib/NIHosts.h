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
 * NIHosts.h
 * - lookup host entries within a set of netinfo domains
 */

/*
 * Modification History:
 * 
 * May 20, 1998	Dieter Siegmund (dieter@apple.com)
 * - initial revision
 */

#import <objc/Object.h>
#import	<mach/boolean.h>
#import <netinet/if_ether.h>
#import <netinet/in.h>
#import <netinfo/ni.h>
#import "NIDomain.h"

typedef boolean_t NIHostMatchFunc_t(void * arg, ni_proplist * proplist);

@interface NIHosts : Object
{
#if 0
    id		domainList;
#endif 0
}
+ (NIDomain *)lookupKey:(ni_name)key Value:(ni_name)value 
 DomainList:(List *)domainList IDList:(ni_idlist *)idlist;
+ (NIDomain *)lookupKey:(ni_name)key Value:(ni_name)value 
 DomainList:(List *)domainList 
 PropList:(ni_proplist *)proplist Dir:(ni_id *)dir;
+ (NIDomain *)lookupKey:(ni_name)key Value:(ni_name)value 
 Func:(NIHostMatchFunc_t *)func Arg:(void *)arg
 DomainList:(List *)list 
 KeyMatches:(int *)key_matches
 Matches:(int *)matches
 PropList:(ni_proplist *)proplist Dir:(ni_id *)dir;
#if 0
+ (NIDomain *)lookupKey:(ni_name)key Value:(ni_name)value 
 SubKey:(ni_name)subkey SubValue:(ni_name)subvalue 
 DomainList:(List *)domainList 
 KeyMatches:(int *)key_matches
 SubKeyMatches:(int *)subkey_matches
 PropList:(ni_proplist *)proplist Dir:(ni_id *)dir;
+ (NIDomain *)lookupKey:(ni_name)key Value:(ni_name)value 
 Subnet:(struct in_addr)net Mask:(struct in_addr)mask
 DomainList:(List *)list 
 PropList:(ni_proplist *)proplist Dir:(ni_id *)dir;
- (NIDomain *)lookupKey:(ni_name)key Value:(ni_name)value 
 IDList:(ni_idlist *)idlist;
- (NIDomain *)lookupKey:(ni_name)key Value:(ni_name)value 
 SubKey:(ni_name)subkey SubValue:(ni_name)subvalue 
 KeyMatches:(int *)key_matches
 SubKeyMatches:(int *)subkey_matches
 PropList:(ni_proplist *)proplist Dir:(ni_id *)dir;
- initWithDomainList:list;
- free;
#endif 0

@end

#define NIDIR_MACHINES		"/machines"
#define NIPROP_IDENTIFIER	"identifier"
#define NIPROP_NAME		"name"
#define NIPROP_IP_ADDRESS	"ip_address"
#define NIPROP_BOOTFILE		"bootfile"
#define NIPROP_EN_ADDRESS	"en_address"
#define NIPROP__CREATOR		"_creator"
