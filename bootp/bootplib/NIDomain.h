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
 * NIDomain.h
 * - simple object representing a netinfo domain
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
#import <netinfo/ni_util.h>

#define NI_DOMAIN_LOCAL		"."
#define NI_DOMAIN_PARENT	".."

@interface NIDomain : Object
{
    void *		handle;
    char *		name; 		/* path or host/tag */
    struct sockaddr_in	sockaddr;
    ni_name		tag;
}
- initWithDomain:(ni_name) domain_name; /* path or host/tag */
- initParentDomain:domain;		/* open parent of given domain */
- (boolean_t)openPath:(ni_name) domain_name; /* path */
- (boolean_t)openHost:(ni_name)host Tag:(ni_name)tag; /* host/tag */
- (void *) handle;
- (ni_name)domain_name;
- (ni_name)tag;
- (struct in_addr)ip;
- free;
@end

