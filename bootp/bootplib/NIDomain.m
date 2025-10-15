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
 * NIDomain.m
 * - simple object interface to a netinfo domain
 */

/*
 * Modification History:
 * 
 * May 20, 1998	Dieter Siegmund (dieter@apple.com)
 * - initial revision
 */

#import	<netdb.h>
#import <string.h>
#import <sys/types.h>
#import <sys/socket.h>
#import <net/if.h>
#import <netinet/in.h>
#import <netinet/if_ether.h>
#import <arpa/inet.h>
#import <string.h>
#import <unistd.h>
#import <stdlib.h>
#import <stdio.h>
#import <objc/List.h>
#import <netinfo/ni_util.h>
#import "NIDomain.h"

static __inline__ boolean_t
S_has_path_component(u_char * path, u_char * comp, u_char sep)
{
    u_char * path_comp;
    u_char * sep_ptr;
    

    if (strcmp(path, comp) == 0)
	return (TRUE);

    for (path_comp = path, sep_ptr = strchr(path, sep); sep_ptr; 
	 sep_ptr = strchr(path_comp = (sep_ptr + 1), sep)) {
	if (strncmp(path_comp, comp, sep_ptr - path_comp) == 0) {
	    return (TRUE);
	}
    }
    return (FALSE);
}

@implementation NIDomain
- initParentDomain:domain
{
    ni_status 	status;
    u_char	tmp[256];

    [super init];
    
    sprintf(tmp, "%s/%s", [domain name], NI_DOMAIN_PARENT);
    name = ni_name_dup(tmp);
    status = ni_open([domain handle], NI_DOMAIN_PARENT, &handle);
    if (status != NI_OK)
	return [self free];
    status = ni_addrtag(handle, &sockaddr, &tag);
    if (status != NI_OK)
	return [self free];
    return (self);
	
}

- initWithDomain:(ni_name) domain_name
{
    [super init];

    if (domain_name[0] == '/' 
	|| S_has_path_component(domain_name, "..", '/')
	|| S_has_path_component(domain_name, ".", '/')) { /* path */
	/* domain_name is an absolute/relative path */
	if ([self openPath:domain_name])
	    return self;
    }
    else { /* not a path */
	char * slash;
	slash = strchr(domain_name, '/');
	if (slash && slash == strrchr(domain_name, '/')) {
	    char hostname[128];
	    
	    /* connect to hostname/tag */
	    strncpy(hostname, domain_name, slash - domain_name);
	    hostname[slash - domain_name] = '\0';
	    if ([self openHost:hostname Tag:slash + 1])
		return self;
	}
    }
    return [self free];
}

- (boolean_t) openPath:(ni_name) domain_name
{
    ni_status 	status;

    name = ni_name_dup(domain_name);

    status = ni_open(NULL, name, &handle);
    if (status != NI_OK)
	return (FALSE);
    status = ni_addrtag(handle, &sockaddr, &tag);
    if (status != NI_OK)
	return (FALSE);
    return (TRUE);
}

- (boolean_t) openHost:(ni_name)host Tag:(ni_name)t
{
    struct hostent * 	h;
    char host_tag[128];

    tag = ni_name_dup(t);
    sprintf(host_tag, "%s/%s", host, tag);
    name = ni_name_dup(host_tag);

    h = gethostbyname(host);
    if (h != NULL && h->h_addrtype == AF_INET) {
	struct in_addr * * s = (struct in_addr * *)h->h_addr_list;
	while (*s) {
	    sockaddr.sin_len = sizeof(struct sockaddr_in);
	    sockaddr.sin_family = AF_INET;
	    sockaddr.sin_addr = **s;
	    handle = ni_connect(&sockaddr, tag);
	    if (handle != NULL) {
		break;
	    }
	    s++;
	}
    }
    if (handle == NULL)
	return (FALSE);
    return (TRUE);
}

- (void *) handle
{
    return handle;
}

- (ni_name)domain_name
{
    return (name);
}

- (ni_name)tag
{
    return (tag);
}

- (struct in_addr)ip
{
    return (sockaddr.sin_addr);
}

- free
{
    if (handle != NULL)
	ni_free(handle);
    if (name != NULL)
	ni_name_free(&name);
    if (tag != NULL)
	ni_name_free(&tag);
    handle = NULL;
    return [super free];
}
@end

