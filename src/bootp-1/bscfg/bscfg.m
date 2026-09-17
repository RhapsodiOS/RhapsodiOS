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
 * bscfg.m - boot server configuration interface
 * - used by Fred to administer the ip ranges
 * - this code provides a simple interface to the subnet description
 *   objects
 * - requires that all network interfaces be up and configured
 * - automatically determines the necessary information
 *   + ip ranges must be reachable via one of the configured interfaces
 *   + subnet mask is derived from the configuration
 */

#import <netinfo/ni.h>
#import <netinfo/ni_util.h>
#import <objc/List.h>
#import "subnetDescr.h"

#define BSCFG_INTERNAL
#import "bscfg.h"
#import "interfaces.h"
#import "netinfo.h"

struct bscfg_s {
    id			subnets;
    interface_list_t *	iflist;
};

int
bscfgOpen(bscfgRef_t * r)
{
    u_char 		err[256];
    struct bscfg_s *	ref;
    int			error = BSCFG_SUCCESS;

    ref = (struct bscfg_s *)malloc(sizeof(*ref));
    if (ref == NULL) {
	error = BSCFG_ALLOC_ERROR;
	goto err;
    }
    ref->iflist = if_init();
    if (ref->iflist == NULL) {
	error = BSCFG_IF_ERROR;
	goto err;
    }

    err[0] = 0;
    ref->subnets = [[subnetListNI alloc] init:err];
    if (ref->subnets == nil) {
	/* create the directory, and try again */
	if ([subnetListNI createDirectoryPath:NULL] == FALSE) {
	    printf("%s\n", err);
	    error = BSCFG_SUBNET_INIT_ERROR;
	    goto err;
	}
	ref->subnets = [[subnetListNI alloc] init:err];
	if (ref->subnets == nil) {
	    printf("%s\n", err);
	    error = BSCFG_SUBNET_INIT_ERROR;
	    goto err;
	}
    }
    
    *r = ref;
    return (BSCFG_SUCCESS);
  err:
    if (ref) {
	if (ref->subnets != nil)
	    [ref->subnets free];
	ref->subnets = nil;
	if (ref->iflist)
	    if_free(&ref->iflist);
	free(ref);
    }
    return (error);
}

void
bscfgClose(bscfgRef_t r)
{
    struct bscfg_s *  ref = (struct bscfg_s *)r;

    /* kill -1 bootpd or whatever */
    /* XXX */

    /* free dynamically allocated structures */
    if (ref->subnets != nil) {
	[ref->subnets free];
    }
    if (ref->iflist != NULL)
	if_free(&ref->iflist);
    ref->subnets = nil;
    ref->iflist = NULL;
    free(ref);

    return;
}

int
bscfgGetIPRanges(bscfgRef_t r, ip_range_t * * list_p, int * count_p)
{
    int			count;
    struct bscfg_s * 	ref = (struct bscfg_s *)r;
    subnetListNI *	subnets = (subnetListNI *)(ref->subnets);

    count = [[subnets list] count];
    if (count == 0) {
	*list_p = 0;
	*count_p = 0;
    }
    else {
	int i;
	int actualCount = 0;

	*list_p = (ip_range_t *)malloc(sizeof(ip_range_t) * count);
	if (*list_p == NULL)
	    return (BSCFG_ALLOC_ERROR);
	for (i = 0; i < count; i++) {
	    subnetEntry * obj = [[subnets list] objectAt:i];

	    if ([obj includesClientType:"macNC"])
		(*list_p)[actualCount++] = [obj ipRange];
	}
	*count_p = actualCount;
    }
    return (BSCFG_SUCCESS);
}

static const u_char * client_types[1] = { "macNC" };

int
bscfgSetIPRanges(bscfgRef_t r, ip_range_t * ranges, int range_count)
{
    id			additions = nil;
    id			deletions = nil;
    int			error = BSCFG_SUCCESS;
    u_char 		err[256];
    int			i;
    ni_proplist		pl;
    struct bscfg_s *	ref = (struct bscfg_s *)r;
    subnetListNI *	subnets = (subnetListNI *)(ref->subnets);
    
    /*
     * verify that all the ranges are directly reachable via one of the
     * interfaces, this is the only way we can determine what the netmask
     * should be
     */
    for (i = 0; i < range_count; i++) {
	interface_t *	if_p;
	id 		subnet;
	
	if_p = if_lookupbysubnet(ref->iflist, ranges[i].start);
	if (if_p == NULL) {
	    error = BSCFG_IF_NOT_FOUND;
	    goto err;
	}
	if (if_p != if_lookupbysubnet(ref->iflist, ranges[i].end)) {
	    error = BSCFG_RANGE_SPANS_MULTIPLE;
	    goto err;
	}
	if (additions == nil)
	    additions = [[List alloc] init];
	pl = [subnetEntryNI proplistFromRange:ranges[i] 
	      Mask:if_p->mask ClientTypes:client_types Number:1];
	ni_proplist_addprop(&pl, "_creator", "libbscfg");
	err[0] = '\0';
	subnet = [[subnetEntryNI alloc] init:err Domain:[subnets domain]
		  ParentDir:[subnets dir] Proplist:pl];
	ni_proplist_free(&pl);
	if (subnet == nil) {
	    printf("couldn't allocate subnet entry: %s\n", err);
	    error = BSCFG_RANGE_INVALID;
	    goto err;
	}
	[additions addObject:subnet];
    }

    /* find any existing entries with a macNC clientType */
    for (i = 0; i < [[subnets list] count]; i++) {
	subnetEntry * obj = [[subnets list] objectAt:i];
	
	if ([obj includesClientType:"macNC"]) {
	    if (deletions == nil) {
		deletions = [[List alloc] init];
	    }
	    [deletions addObject:obj];
	}
    }
    
    /* remove them from the subnet list */
    for (i = 0; i < [deletions count]; i++) {
	id obj = [deletions objectAt:i];
	[[subnets list] removeObject:obj];
    }

    /* add the new entries to the new list */
    for (i = 0; i < [additions count]; i++) {
	id obj = [additions objectAt:i];
	if ([subnets addSubnet:obj Err:err] == FALSE) {
	    error = BSCFG_RANGES_OVERLAP;
	    goto err;
	}
    }
    /* write the new entries to netinfo */
    for (i = 0; i < [additions count]; i++) {
	id obj = [additions objectAt:i];
	if ([obj write] == FALSE) {
	    error = BSCFG_WRITE_ERROR;
	    goto err;
	}
    }

    /* remove the deleted entries from netinfo */
    for (i = 0; i < [deletions count]; i++) {
	id obj = [deletions objectAt:i];
	if ([obj destroy] == FALSE) {
	    error = BSCFG_DESTROY_ERROR;
	    goto err;
	}
    }

    if (additions != nil) {
	[additions free];	 /* part of new subnet list */
    }
    if (deletions != nil) {
	[deletions freeObjects]; /* no longer part of subnet list */
	[deletions free];
    }
    return (BSCFG_SUCCESS);
  err:
    /* attempt to put things back the way they were */
    if (additions != nil) {
	for (i = 0; i < [additions count]; i++) {
	    id obj = [additions objectAt:i];
	    [obj destroy];
	    [[subnets list] removeObject:obj];
	}
	[additions freeObjects];/* free the new entries */
	[additions free];	/* and the list itself */
    }
    if (deletions != nil) {
	for (i = 0; i < [deletions count]; i++) {
	    id obj = [deletions objectAt:i];

	    err[0] = '\0';
	    if ([subnets addSubnet:obj Err:err] == FALSE)
		printf("couldn't restore subnet %s:%s\n", [obj name], err);
	    [obj write]; /* re-write it, just in case */
	}
	[deletions free];
    }
    return (error);
}

void
bscfgFreeIPRanges(ip_range_t * * ranges)
{
    free(*ranges);
    *ranges = 0;
    return;
}

const u_char *
bscfgErrorString(int status)
{
    switch (status) {
      case BSCFG_SUCCESS:
	return ("success");
      case BSCFG_IF_ERROR:
	return ("couldn't get interface list");
      case BSCFG_IF_NOT_FOUND:
	return ("ranges not reachable");
      case BSCFG_RANGE_SPANS_MULTIPLE:
	return ("range spans multiple subnets");
      case BSCFG_RANGES_OVERLAP:
	return ("ranges overlap");
      case BSCFG_WRITE_ERROR:
	return ("write error occurred");
      case BSCFG_DESTROY_ERROR:
	return ("error occurred during remove");
      case BSCFG_RANGE_INVALID:
	return ("range invalid");
      case BSCFG_ALLOC_ERROR:
	return ("error allocating memory");
      case BSCFG_SUBNET_INIT_ERROR:
	return ("couldn't initialize subnet handle");
      default:
	return ("unknown error");
    }
}

