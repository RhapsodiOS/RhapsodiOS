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
 * bscfg.h
 * - NC boot server configuration API
 */

#import <sys/types.h>
#import <netinet/in.h>

#ifndef BSCFG_INTERNAL
typedef struct {
	struct in_addr	start;
	struct in_addr	end;
} ip_range_t;
#endif BSCFG_INTERNAL

typedef void *		bscfgRef_t;

#define BSCFG_SUCCESS			0
#define BSCFG_IF_ERROR			1
#define BSCFG_IF_NOT_FOUND		2
#define BSCFG_RANGE_SPANS_MULTIPLE	3
#define BSCFG_RANGES_OVERLAP		4
#define BSCFG_WRITE_ERROR		5
#define BSCFG_DESTROY_ERROR		6
#define BSCFG_RANGE_INVALID		7
#define BSCFG_ALLOC_ERROR		8
#define BSCFG_SUBNET_INIT_ERROR		9

int
bscfgOpen(bscfgRef_t * ref_p);

void
bscfgClose(bscfgRef_t ref);

int
bscfgGetIPRanges(bscfgRef_t ref, ip_range_t * * list_p, int * count_p);

int
bscfgSetIPRanges(bscfgRef_t ref, ip_range_t * list, int count);

void
bscfgFreeIPRanges(ip_range_t * * list_p);

const u_char *
bscfgErrorString(int status);
