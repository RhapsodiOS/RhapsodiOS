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
 * subnetDescr.m
 * - object for dealing with subnet descriptions
 * - purpose:
 *   1) manage/allocate available ip addresses by subnet
 *   2) locating dhcp options/bootp extensions suitable 
 *      for a particular host
 */

/*
 * Modification History:
 * 
 * January 12, 1998	Dieter Siegmund (dieter@apple.com)
 * - initial revision
 */

#import <ctype.h>
#import <pwd.h>
#import	<netdb.h>
#import <string.h>
#import <syslog.h>
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
#import	<mach/boolean.h>
#import <netinet/in.h>
#import <netinfo/ni.h>
#import <netinfo/ni_util.h>
#import <machine/endian.h>
#import "subnetDescr.h"
#import "util.h"
#import "netinfo.h"
#import "gen_dhcp_tags.h"

#define NIDOMAIN_SELF	"."
#define NIDOMAIN_PARENT	".."

#define NIDIR_MACHINES		"/machines"

#ifdef TESTING
#define DEBUG
#endif TESTING

static __inline__ boolean_t
S_nltoip(ni_namelist * nl_p, struct in_addr * ip)
{
    u_long		val;

    if (nl_p->ninl_len != 1 
	|| (val = inet_addr(nl_p->ninl_val[0])) == -1)
	return (FALSE);
    ip->s_addr = val;
    return (TRUE);
}

static __inline__ boolean_t
S_nltoiprange(ni_namelist * nl_p, ip_range_t * r)
{
    if (nl_p->ninl_len != 2 
	|| (r->start.s_addr = inet_addr(nl_p->ninl_val[0])) == -1 
	|| (r->end.s_addr = inet_addr(nl_p->ninl_val[1])) == -1 
	|| iptohl(r->end) < iptohl(r->start) 
	|| inet_netof(r->start) != inet_netof(r->end)) {
	return (FALSE);
    }
    return (TRUE);
}

#ifdef DEBUG
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
#endif DEBUG

static __inline__ void
S_strcpy(u_char * dest, const u_char * src)
{
    if (dest)
	strcpy(dest, src);
}

static __inline__ void
S_strcat(u_char * dest, const u_char * src)
{
    if (dest)
	strcat(dest, src);
}

@implementation subnetEntry

- init
{
    [super init];
    supernet = NULL;
    client_list = [[clientTypes alloc] init];
    return self;
}

- free
{
    if (client_list != nil) {
	[client_list free];
	client_list = nil;
    }
    return [super free];
}

- (void) print
{
    printf("\taddress %s\n", inet_ntoa(net_address));
    printf("\tmask %s\n", inet_ntoa(net_mask));
    printf("\trange %s..", inet_ntoa(ip_range.start));
    printf("%s\n", inet_ntoa(ip_range.end));
    printf("\tclient types:");
    [client_list print];
}

- (u_char *)supernet
{
    return supernet;
}

- (boolean_t) sameSupernet:entry
{
    if (supernet != NULL && [entry supernet] != NULL
	&& strcmp(supernet, [entry supernet]) == 0)
	return (TRUE);
    return (FALSE);
}

- (boolean_t) ipSameSubnet:(struct in_addr)addr
{
    return (in_subnet(net_address, net_mask, addr));
}

- (boolean_t) ipWithinIpRange:(struct in_addr)ipaddr
{
    u_long l;

    if ([self ipSameSubnet:ipaddr] == FALSE)
	return (FALSE);

    l = iptohl(ipaddr);

    if (l < iptohl(ip_range.start) || l > iptohl(ip_range.end))
	return (FALSE);
    return (TRUE);
    
}

- (ip_range_t) ipRange
{
    return (ip_range);
}

- (struct in_addr) mask
{
    return (net_mask);
}

- (int) compareIpRangeWith:b Overlap:(boolean_t *)overlap
{
    return (ipRangeCmp(&ip_range, &(((subnetEntry *)b)->ip_range), overlap));
}

- (boolean_t) includesClientType:(const u_char *)type
{
    if ([client_list includesType:type] == FALSE)
	return (FALSE);
    return (TRUE);
}

- (boolean_t) acquireIp:(struct in_addr *)ipaddr 
 ClientType:(const u_char *)type  Func:(ipInUseFunc_t *)func Arg:(void *)arg
{
    u_long end = iptohl(ip_range.end);
    u_long i;

    if ([client_list includesType:type] == FALSE)
	return (FALSE);

    i = iptohl(nextip);

    if (i == (end + 1)) { /* previously exhausted ip range */
	struct timeval now;

	gettimeofday(&now, 0);
	if ((now.tv_sec - exhaust_time.tv_sec) < IPRANGE_RESCAN_SECS) {
#if 0
	    syslog(LOG_INFO, "acquireIp: %ld seconds < %d",
		   now.tv_sec - exhaust_time.tv_sec, IPRANGE_RESCAN_SECS);
#endif 0
	    return (FALSE);
	}

#if 0
	syslog(LOG_INFO, "acquireIp: %ld seconds >= %d",
	       now.tv_sec - exhaust_time.tv_sec, IPRANGE_RESCAN_SECS);
#endif 0
	i = iptohl(ip_range.start);
    }
    for (; i <= end; i++) {
	if ((*func)(arg, hltoip(i)) == FALSE) {
	    *ipaddr = hltoip(i);
	    nextip = hltoip(i);
	    return (TRUE);
	}
    }
    nextip = hltoip(end + 1);
    gettimeofday(&exhaust_time, 0);
#if 0
    syslog(LOG_INFO, "ip pool exhausted");
#endif 0
    return (FALSE);
}

@end /* subnetEntry */

@implementation subnetList
- init
{
    [super init];

    list = [[List alloc] init];
    return (self);
}

/*
 * Method: acquireIp
 *
 * Purpose:
 *   Get a new ip address on the same subnet as *addr.  The new ip
 *   address is returned in addr.
 */
- (boolean_t) acquireIp:(struct in_addr *) addr ClientType:(const u_char *)type
 Func:(ipInUseFunc_t *)func Arg:(void *)arg

{
    boolean_t	found = FALSE;
    int 	i;

    for (i = 0; i < [list count]; i++) {
	id 	subnet = [list objectAt:i];

	if ([subnet ipSameSubnet:*addr] == FALSE)
	    continue;

	if ([subnet acquireIp:addr ClientType:type Func:func Arg:arg]) {
	    found = TRUE;
	    break;
	}
    }
    return (found);
}

/*
 * Method: acquireIpSupernet
 *
 * Purpose:
 *   Get a new ip address on the same "supernet" as *addr.  The new ip
 *   address is returned in addr.
 */
- (boolean_t) acquireIpSupernet:(struct in_addr *) addr 
 ClientType:(const u_char *)type
 Func:(ipInUseFunc_t *)func Arg:(void *)arg

{
    struct in_addr	subnet_address = *addr;
    id			entry;
    boolean_t		found = FALSE;
    int 		i;

    entry = [self entrySameSubnet:subnet_address];
    for (i = 0; i < [list count]; i++) {
	id 	subnet = [list objectAt:i];

	if ([subnet ipSameSubnet:subnet_address] == FALSE
	    || [subnet sameSupernet:entry] == FALSE)
	    continue;

	if ([subnet acquireIp:addr ClientType:type Func:func Arg:arg]) {
	    found = TRUE;
	    break;
	}
    }
    return (found);
}

- entry:(struct in_addr)addr
{
    int i;

    for (i = 0; i < [list count]; i++) {
	id 	subnet = [list objectAt:i];
	
	if ([subnet ipSameSubnet:addr] == FALSE) 
	    continue;

	if ([subnet ipWithinIpRange:addr])
	    return subnet;
    }
    return nil;
}

- entrySameSubnet:(struct in_addr)addr
{
    int i;

    for (i = 0; i < [list count]; i++) {
	id 	subnet = [list objectAt:i];
	
	if ([subnet ipSameSubnet:addr])
	    return subnet;
    }
    return nil;
}

- (boolean_t) ip:(struct in_addr)ipaddr1 SameSupernet:(struct in_addr)ipaddr2
{
    id		entry1 = [self entrySameSubnet:ipaddr1];
    id 		entry2 = [self entrySameSubnet:ipaddr2];

    return [entry1 sameSupernet:entry2];
}

- (boolean_t) addSubnet:subnet Err:(u_char *)errString
{
    int 	i;

    for (i = 0; i < [list count]; i++) {
	int 		c;
	id 		obj = [list objectAt:i];
	boolean_t 	overlap;

	c = [obj compareIpRangeWith:subnet Overlap:&overlap];
	if (overlap) {
	    u_char	buf[128];
	
	    S_strcpy(errString, "overlapping entries: ");
	    S_strcat(errString, [obj name:buf]);
	    S_strcat(errString, ", ");
	    S_strcat(errString, [subnet name:buf]);
	    return (FALSE);
	}
	if (c < 0) {
	    [list insertObject:subnet at:i];
	    return (TRUE);
	}
    }

    /* append to end */
    [list insertObject:subnet at:[list count]];
    return (TRUE);
}

- list
{
    return (list);
}

@end /* subnetList */

@implementation subnetEntryNI

+ (ni_proplist) proplistFromRange:(ip_range_t)range Mask:(struct in_addr)mask
 ClientTypes:(const u_char * *)types Number:(int)ntypes
{
    struct in_addr 	addr;
    ni_proplist	 	props;
    u_char		tmp[128];
    u_char *		arr[2];

    addr.s_addr = htonl(iptohl(range.start) & iptohl(mask));

    NI_INIT(&props);
    ni_proplist_addprop(&props, NIPROP_NAME, inet_nettoa(addr, mask));
    ni_proplist_addprop(&props, NIPROP_NET_ADDRESS, inet_ntoa(addr));
    ni_proplist_addprop(&props, NIPROP_NET_MASK, inet_ntoa(mask));
    strcpy(tmp, inet_ntoa(range.start));
    arr[0] = tmp;
    arr[1] = inet_ntoa(range.end);
    ni_proplist_addprops(&props, NIPROP_NET_RANGE, (ni_name *)arr, 2);
    ni_proplist_addprops(&props, NIPROP_CLIENT_TYPES, (ni_name *)types, 
			 ntypes);
    return (props);
}

- (boolean_t) read
{
    ni_status status;

    ni_proplist_free(&pl);

    status = ni_read(domain, &dir, &pl);
    if (status != NI_OK)
	return (FALSE);
    return (TRUE);
}

- (boolean_t) write
{
    ni_status status;

    if (dir_valid)
	return (FALSE);  /* don't write unless it's not already there */

    ni_self(domain, &parent_dir);
    status = ni_create(domain, &parent_dir, pl, &dir, NI_INDEX_NULL);
    if (status != NI_OK) {
	printf("%s\n", ni_error(status));
	return (FALSE);
    }

    dir_valid = TRUE;
    return (TRUE);
}

- (boolean_t) destroy
{
    if (dir_valid == FALSE)
	return (TRUE); /* it doesn't exist, so destroying it is a NOP */
    
    if (ni_self(domain, &parent_dir) != NI_OK)
	return (FALSE);

    if (ni_self(domain, &dir) != NI_OK)
	return (FALSE);

    if (ni_destroy(domain, &parent_dir, dir) == NI_OK) {
	dir_valid = FALSE;
	return (TRUE);
    }
    return (FALSE);
    
}

- (ni_namelist *) lookup:(u_char *) propname
{
    int i;

    for (i = 0; i < pl.nipl_len; i++) {
	ni_property * p = &(pl.nipl_val[i]);
	if (strcmp(propname, p->nip_name) == 0) {
	    return (&p->nip_val);
	}
    }
    return (NULL);
}

- (u_char *) name:(u_char *)buf
{
    if (name == NULL)
	sprintf(buf, "(dir: %ld)", dir.nii_object);
    else
	strcpy(buf, name);
    return (buf);
}

- (boolean_t) initVariables:(u_char *)errString
{
    u_char		buf[256];
    boolean_t 		errors = FALSE;
    ni_namelist *	nl_p;

    /* get the name */
    name = NULL;
    if ((nl_p = [self lookup:NIPROP_NAME]) && nl_p->ninl_len > 0)
	name = nl_p->ninl_val[0];

    /* get the supernet */
    supernet = NULL;
    if ((nl_p = [self lookup:NIPROP_SUPERNET]) && nl_p->ninl_len > 0)
	supernet = nl_p->ninl_val[0];

    S_strcpy(errString, "bad subnet entry ");
    S_strcat(errString, [self name:buf]);
    S_strcat(errString, ": ");

    /* get the net address */
    nl_p = [self lookup:NIPROP_NET_ADDRESS];
    if (nl_p == NULL
	|| S_nltoip(nl_p, &net_address) == FALSE) {
	if (errors)
	    S_strcat(errString, ", ");
	S_strcat(errString, NIPROP_NET_ADDRESS);
	errors = TRUE;
    }

    /* get the subnet mask */
    nl_p = [self lookup:NIPROP_NET_MASK];
    if (nl_p == NULL
	|| S_nltoip(nl_p, &net_mask) == FALSE) {
	if (errors)
	    S_strcat(errString, ", ");
	S_strcat(errString, NIPROP_NET_MASK);
	errors = TRUE;
    }
    /* get the ip range */
    nl_p = [self lookup:NIPROP_NET_RANGE];
    if (nl_p == NULL
	|| S_nltoiprange(nl_p, &ip_range) == FALSE) {
	if (errors)
	    S_strcat(errString, ", ");
	S_strcat(errString, NIPROP_NET_RANGE);
	errors = TRUE;
    }

    /* verify that the range lies within the subnet */
    if (errors == FALSE) {
	if (in_subnet(net_address, net_mask, ip_range.start) == FALSE
	    || in_subnet(net_address, net_mask, ip_range.end) == FALSE) {
	    S_strcat(errString, "ip range not within subnet");
	    errors = TRUE;
	}
    }

#if 0
    { /* make sure the domain is OK */
	u_char * 	domain_name;
	ni_status 	status;

	machines_domain = NULL;
	nl_p = [self lookup:NIPROP_MACHINES_DOMAIN];
	if (nl_p && nl_p->ninl_len >= 1)
	    domain_name = nl_p->ninl_val[0];
	else
	    domain_name = ".."; /* default to parent domain */

	status = [niDomain open:domain_name Handle:&machines_domain];
	if (status != NI_OK) {
	    S_strcat(errString, "couldn't open domain ");
	    S_strcat(errString, nl_p->ninl_val[0]);
	    errors = TRUE;
	}
	else if (ni_pathsearch(machines_domain, &machines_dir, 
			       NIDIR_MACHINES) != NI_OK) {
	    S_strcat(errString, "couldn't open /machines dir on domain ");
	    S_strcat(errString, nl_p->ninl_val[0]);
	    errors = TRUE;
	}
    }
#endif

    /* get the client types */
    nl_p = [self lookup:NIPROP_CLIENT_TYPES];
    if (nl_p && nl_p->ninl_len > 0) {
	[client_list addTypes:(const u_char * *)nl_p->ninl_val
         Count:nl_p->ninl_len];
    }
    if (!errors)
	nextip = ip_range.start;

    return (!errors);
}

- init:(u_char *)errString Domain:(void *)d ParentDir:(ni_id)p Dir:(u_long)id 
{
    [super init];
    domain = d;
    parent_dir = p;
    dir_valid = TRUE;
    dir.nii_object = id;
    dir.nii_instance = 0;

    NI_INIT(&pl);
    if ([self read] == FALSE)
	return [self free];
    
    if ([self initVariables:errString] == FALSE)
	return [self free];
    return self;
}

- init:(u_char *)errString Domain:(void *)dom ParentDir:(ni_id)p 
 Proplist:(ni_proplist)props
{
    [super init];
    dir_valid = FALSE;
    domain = dom;
    parent_dir = p;
    pl = ni_proplist_dup(props);
    if ([self initVariables:errString] == FALSE)
	return ([self free]);
    return self;
}


- free
{
    ni_proplist_free(&pl);
    return [super free];
}

@end /* subnetEntryNI */

@implementation subnetListNI
+ (void *) searchFor:(const u_char *)dirname Dir:(ni_id *)dir_p
 Err:(u_char *)errString 
{
    void *	d;
    ni_status	status;

    status = ni_open(NULL, NIDOMAIN_SELF, &d);
    if (status != NI_OK) {
	S_strcpy(errString, ni_error(status));
	return (NULL);
    }
    
    /* search domain hierarchy for subnets dir */
    do {
	void * 	old_domain;

	if (ni_pathsearch(d, dir_p, dirname) == NI_OK)
	    break; /* found */

	old_domain = d;
	status = ni_open(old_domain, NIDOMAIN_PARENT, &d);
	ni_free(old_domain);
    } while (status == NI_OK);
    
    if (status != NI_OK) {
	S_strcpy(errString, ni_error(status));
	return (NULL);
    }
    return (d);
}

+ (boolean_t) createDirectoryPath:(u_char *)dirname
{
    void * 	d;
    boolean_t	ret;
    ni_status 	status;

    if (dirname == NULL)
	dirname = SUBNETS_NIDIR;
    status = ni_open(NULL, NIDOMAIN_SELF, &d);
    if (status != NI_OK)
	return (FALSE);
    ret = ni_create_path(d, dirname);
    ni_free(d);
    return (ret);
}

/*
 * Class Variables: _subnetsDomain, _subnetsDir
 *
 * Purpose:
 *   These are used to maintain a connection across initializations.
 */
static void * 	_subnetsDomain = NULL;
static ni_id 	_subnetsDir;

+ (void) disconnect
{
    if (_subnetsDomain != NULL)
	ni_free(_subnetsDomain);
    _subnetsDomain = NULL;
    return;
}

+ (boolean_t) connect:(u_char *)errString ToDir:(const u_char *)dirname
{
    if (_subnetsDomain)
	[self disconnect];
    _subnetsDomain = [self searchFor:dirname Dir:&_subnetsDir
		      Err:errString];
    if (_subnetsDomain == NULL)
	return (FALSE);
    return (TRUE);
}

- init:(u_char *)errString
{
    [super init];

    if (_subnetsDomain == NULL) {
	if ([[self class] connect:errString ToDir:SUBNETS_NIDIR] == FALSE)
	    return [self free];
    }
    domain = _subnetsDomain;
    dir = _subnetsDir;
    return [self read:errString];
}

- read:(u_char *)errString
{
    int			i;
    ni_entrylist 	el;
    boolean_t 		error = FALSE;
    ni_status 		status;

    [list freeObjects]; /* free previous list members */

    status = ni_list(domain, &dir, NIPROP_NET_RANGE, &el);
    if (status != NI_OK) {
	S_strcpy(errString, ni_error(status));
	return [self free];
    }

    /* re-build the subnet list */
    for (i = 0; i < el.niel_len; i++) {
	ni_entry *	entry = &el.niel_val[i];
	
	if (entry->names) {
	    subnetEntry *		subnet;

	    subnet = [[subnetEntryNI alloc] init:errString Domain:domain
		      ParentDir:dir Dir:entry->id];
	    if (subnet == nil) {
		error = TRUE;
		break;
	    }
	    if ([self addSubnet:subnet Err:errString] == FALSE) {
		error = TRUE;
		break;
	    }
	}
    }

    ni_entrylist_free(&el);
    if (error)
	return [self free];

    return (self);
}

- free
{

    if (list != nil) {
	[list freeObjects];
	[list free];
	list = nil;
    }
    return [super free];
}

- (void *)domain
{
    return (domain);
}

- (ni_id)dir
{
    return (dir);
}

- (void) print
{
    int i;

    printf("%d entries:\n", [list count]);
    for (i = 0; i < [list count]; i++) {
	u_char buf[128];
	id obj = [list objectAt:i];
	printf("Entry %d: %s\n", i, [obj name:buf]);
	[obj print];
    }
    return;
}

@end /* subnetListNI */

#ifdef TESTING
int
main()
{
    u_char errorString[256];
    subnetListNI * subnets;

//    sethostent(1);
    S_timestamp("before init");
    subnets = [[subnetListNI alloc] init:errorString];
    S_timestamp("after init");
    if (subnets == nil) {
	printf("error: %s\n", errorString);
    }
    else {
	struct in_addr ip;

	ip.s_addr = inet_addr("17.202.40.1");
	
	S_timestamp("acquireIp: start");
	if ([subnets acquireIp:&ip ClientType:"macNC"]) {
	    printf("allocated a new ip address %s\n", inet_ntoa(ip));
	}
	else
	    printf("couldn't allocate an ip address\n");
	S_timestamp("acquireIp: end");
	[subnets print];
	[subnets free];
    }
    S_timestamp("before init");
    subnets = [[subnetListNI alloc] init:errorString];
    S_timestamp("after init");
    if (subnets == nil) {
	printf("error: %s\n", errorString);
    }
    else {
	[subnets print];
	[subnets free];
    }

    exit(0);
}

#endif
