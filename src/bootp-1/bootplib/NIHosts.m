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
 * NIHosts.m
 * - object to lookup hosts from a list of netinfo domains
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
#import "netinfo.h"
#import "NIHosts.h"


@implementation NIHosts
+ (NIDomain *)lookupKey:(ni_name)key Value:(ni_name)value 
 DomainList:(List *)list IDList:(ni_idlist *)idlist
{
    id 		domain;
    int 	i;
    ni_status 	status;

    for (i = 0; i < [list count]; i++) {
	ni_id dir;

	domain = [list objectAt:i];
	status = ni_pathsearch([domain handle], &dir, NIDIR_MACHINES);
	if (status == NI_OK) {
	    status = ni_lookup([domain handle], &dir, key, value, idlist);
	    if (status == NI_OK)
		return (domain);
	}
    }
    return NULL;
}

+ (NIDomain *)lookupKey:(ni_name)key Value:(ni_name)value 
 DomainList:(List *)domainList 
 PropList:(ni_proplist *)proplist Dir:(ni_id *)dir
{
    id		domain;
    ni_idlist	il;

    NI_INIT(&il);
    domain = [self lookupKey:key Value:value DomainList:domainList IDList:&il];
    if (domain == nil)
	return (nil);
    
    dir->nii_object = il.niil_val[0];
    dir->nii_instance = 0;
    if (ni_read([domain handle], dir, proplist) != NI_OK) {
	ni_idlist_free(&il);
	return (nil);
    }
    ni_idlist_free(&il);
    return (domain);
}

+ (NIDomain *)lookupKey:(ni_name)key Value:(ni_name)value 
 Func:(NIHostMatchFunc_t *)func Arg:(void *)arg
 DomainList:(List *)list 
 KeyMatches:(int *)key_matches
 Matches:(int *)matches
 PropList:(ni_proplist *)proplist Dir:(ni_id *)dir
{
    int		d_index;
    id 		domain;
    id		found_domain = nil;
    ni_id	found_dir = {0,0};
    ni_idlist   il;

    *key_matches = 0;
    *matches = 0;
    NI_INIT(proplist);
    NI_INIT(&il);
    for (d_index = 0; d_index < [list count]; d_index++) {
	domain = [list objectAt:d_index];
	if (ni_pathsearch([domain handle], dir, NIDIR_MACHINES) == NI_OK
	    && ni_lookup([domain handle], dir, key, value, &il) == NI_OK) {
	    int		i;
	    for (i = 0; i < il.niil_len; i++) {
		ni_status 	status;
		
		dir->nii_object = il.niil_val[i];
		dir->nii_instance = 0;
		ni_proplist_free(proplist);
		status = ni_read([domain handle], dir, proplist);
		if (status != NI_OK) {
		    printf("ni_read failed %s\n", ni_error(status));
		    continue;
		}
		(*key_matches)++;
		if (found_domain == nil) { /* remember the first one */
		    found_domain = domain;
		    found_dir = *dir;
		}
		if ((*func)(arg, proplist) == TRUE) {
		    (*matches)++;
		    goto matches;
		}
	    }
	  matches:
	    ni_idlist_free(&il);
	    if (*matches) /* bail out after first "exact" match */
		break;
	} /* entry found */
    } /* scan all domains */

    if (*matches) /* matched entry */
	return (found_domain);

    if (*key_matches == 1) /* key matches an entry uniquely */
	return (found_domain);

    /* free any existing proplist that we might have read */
    ni_proplist_free(proplist);

    if (found_domain != nil) { /* key matches multiple, return first one */
	*dir = found_dir;
	if (ni_read([found_domain handle], dir, proplist) == NI_OK)
	    return (found_domain);
    }
    return (nil);
}

#if 0

typedef struct {
    u_char *	key;
    u_char *	value;	
} keyvalue_t;

static boolean_t
S_subkey_match(void * arg, ni_proplist * proplist)
{
    ni_namelist * nl_p;
    keyvalue_t * kv_p = (keyvalue_t *)arg;

    if (nl_p = ni_nlforprop(proplist, kv_p->key)) {
	int j;
	for (j = 0; j < nl_p->ninl_len; j++) {
	    if (strcmp(nl_p->ninl_val[j], kv_p->value) == 0)
		return (TRUE);
	}
    }
    return (FALSE);
}

+ (NIDomain *)lookupKey:(ni_name)key Value:(ni_name)value 
 SubKey:(ni_name)subkey SubValue:(ni_name)subvalue 
 DomainList:(List *)list 
 KeyMatches:(int *)key_matches
 SubKeyMatches:(int *)subkey_matches
 PropList:(ni_proplist *)proplist Dir:(ni_id *)dir
{
    keyvalue_t kv;

    kv.key = subkey;
    kv.value = subvalue;

    return [self lookupKey:key Value:value 
	    Func:S_subkey_match Arg:&kv
	    DomainList:list KeyMatches:key_matches
	    Matches:subkey_matches
	    PropList:proplist Dir:dir];
}

typedef struct {
    u_long		net;
    u_long		mask;
} netipmask_t;

static boolean_t
S_netipmask_match(void * arg, ni_proplist * proplist)
{
    ni_namelist * nl_p;
    netipmask_t * ip_p = (netipmask_t *)arg;

    if (nl_p = ni_nlforprop(proplist, NIPROP_IP_ADDRESS)) {
	int j;
	for (j = 0; j < nl_p->ninl_len; j++) {
	    u_long ipval = inet_addr(nl_p->ninl_val[j]);
	    if (ipval != -1) {
		ipval = ntohl(ipval);
		if ((ipval & ip_p->mask) == ip_p->net)
		    return (TRUE);
	    }
	}
    }
    return (FALSE);
}

+ (NIDomain *)lookupKey:(ni_name)key Value:(ni_name)value 
 Subnet:(struct in_addr)net Mask:(struct in_addr)mask
 DomainList:(List *)list 
 PropList:(ni_proplist *)proplist Dir:(ni_id *)dir
{
    netipmask_t ip;
    id domain;
    int key_matches, subkey_matches;

    ip.mask = ntohl(mask.s_addr);
    ip.net = mask.s_addr & ntohl(net.s_addr);

    domain = [self lookupKey:key Value:value 
	      Func:S_netipmask_match Arg:&ip
	      DomainList:list KeyMatches:&key_matches
	      SubKeyMatches:&subkey_matches
	      PropList:proplist Dir:dir];
    if (domain == nil)
	return nil;
    if (subkey_matches != 1) {
	ni_proplist_free(proplist);
	return nil;
    }
    return (domain);
}

- (NIDomain *)lookupKey:(ni_name)key Value:(ni_name)value 
 IDList:(ni_idlist *)idlist
{
    return [[self class] lookupKey:key Value:value DomainList:domainList
	    IDList:idlist];
}

- (NIDomain *)lookupKey:(ni_name)key Value:(ni_name)value 
 SubKey:(ni_name)subkey SubValue:(ni_name)subvalue 
 KeyMatches:(int *)key_matches
 SubKeyMatches:(int *)subkey_matches
 PropList:(ni_proplist *)proplist Dir:(ni_id *)dir
{
    return [[self class] lookupKey:key Value:value 
	    SubKey:subkey SubValue:subvalue
	    DomainList:domainList
	    KeyMatches:key_matches
	    SubKeyMatches:subkey_matches
	    PropList:proplist Dir:dir];
}

- initWithDomainList:list
{
    [super init];
    domainList = list;
    return self;
}

- free
{
    [[domainList freeObjects] free];
    return [super free];
}
#endif 0

@end

#ifdef TESTING
/* 
 * Function: S_timestamp
 *
 * Purpose:
 *   printf a timestamped event message
 */
static void
S_timestamp(char * msg)
{
    static struct timeval	tvp = {0,0};
    struct timeval		tv;

	gettimeofday(&tv, 0);
	if (tvp.tv_sec) {
	    int sec, usec;
#define USECS_PER_SEC	1000000
	    sec = tv.tv_sec - tvp.tv_sec;
	    usec = tv.tv_usec - tvp.tv_usec;
	    if (usec < 0) {
		usec += USECS_PER_SEC;
		sec--;
	    }
	    printf("%d.%06d (%d.%06d): %s\n", 
		   tv.tv_sec, tv.tv_usec, sec, usec, msg);
	}
	else 
	    printf("%d.%06d (%d.%06d): %s\n", 
		   tv.tv_sec, tv.tv_usec, 0, 0, msg);
	tvp = tv;
}

List *
openDomains(ni_name * domains, int count)
{
    int i;
    id list = [[List alloc] initCount:count];

    for (i = 0; i < count; i++) {
	id domain = [[NIDomain alloc] initWithDomain:domains[i]];
	
	if (domain != nil) {
	    [list addObject:domain];
	}
	else {
	    printf("couldn't open domain '%s'\n", domains[i]);
	}
    }
    return (list);
}


int
main(int argc, char * argv[])
{
    int		args;
    int		i;
    int		ndomains;
    ni_id	dir;
    id		domain;
    int		key_matches = 0;
    id		list;
    ni_proplist	pl;
    ni_name	prop;
    ni_status	status;
    int		subkey_matches = 0;
    ni_name	subprop;
    ni_name	subvalue;
    ni_name	submask = NULL;
    ni_name	value;
    
    if (argc < 6) {
	fprintf(stderr, "usage: %s prop value subnet subnet-val subnet-mask"
		" domain1 [domain2 [...]]\n", argv[0]);
	fprintf(stderr, "usage: %s prop value sub-prop sub-value"
		" domain1 [domain2 [...]]\n", argv[0]);
	exit(1);
    }
    prop = argv[1];
    value = argv[2];
    subprop = argv[3];
    subvalue = argv[4];
    args = 5;
    if (strcmp(subprop, "subnet") == 0) {
	submask = argv[5];
	args = 6;
    }
    ndomains = argc - args;
    NI_INIT(&pl);
    list = openDomains(argv + args, ndomains);
    if (list == nil || [list count] == 0) {
	printf("no domains to search, exiting\n");
	exit (1);
    }
    S_timestamp("before lookup");
    if (submask) {
	struct in_addr mask;
	struct in_addr net;

	net.s_addr = inet_addr(subvalue);
	mask.s_addr = inet_addr(submask);
	if (net.s_addr == -1 || mask.s_addr == -1) {
	    fprintf(stderr, "%s: subnet and/or mask invalid\n", argv[0]);
	    exit(1);
	}
	domain = [NIHosts lookupKey:prop Value:value 
		  Subnet:net Mask:mask DomainList:list 
		  PropList:&pl Dir:&dir];
	subkey_matches = 1;
	key_matches = 1;
    }
    else
	domain = [NIHosts lookupKey:prop Value:value 
		  SubKey:subprop SubValue:subvalue DomainList:list 
		  KeyMatches:&key_matches SubKeyMatches:&subkey_matches
		  PropList:&pl Dir:&dir];
    S_timestamp("after lookup");
    if (domain == nil) {
	ni_idlist il;
	printf("%s=%s, %s=%s not found\n", prop, value, subprop, subvalue);
    }
    else {
	if (subkey_matches)
	    printf("%s=%s, %s=%s found\n", prop, value, subprop, subvalue);
	else {
	    if (key_matches == 1) {
		printf("%s=%s matches uniquely\n", prop, value);
	    }
	    else
		printf("%s=%s matches %d entries\n", prop, value,
		       key_matches);
	}
	ni_proplist_dump(&pl);
    }
    ni_proplist_free(&pl);
    [[list freeObjects] free];
    exit(0);
    
}
#endif TESTING
