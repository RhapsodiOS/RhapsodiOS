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
 * Computes a checksum for a netinfo database
 * Copyright (C) 1989 by NeXT, Inc.
 *
 * The checksum is simply the following 32-bit sum:
 *
 * Sum for all directories k in the database:
 *    Sigma: (ObjectID(k) + 1) * InstanceID(k)
 */
#include "ni_server.h"
#include "checksum.h"
#include <string.h>

/*
 * Recursive routine to compute checksum
 */
static void 
compute_it(
	   unsigned *checksum_p,
	   void *ni,
	   ni_id *id
	   )
{
	ni_idlist children;
	ni_index i;
	unsigned checksum;
	ni_id node;

	if (ni_self(ni, id) != NI_OK) {
		return;
	}
	
	checksum = *checksum_p;
	checksum += (id->nii_object + 1) * id->nii_instance;
	NI_INIT(&children);
	if (ni_children(ni, id, &children) != NI_OK) {
		return;
	}
	for (i = 0; i < children.niil_len; i++) {
		node.nii_object = children.niil_val[i];
		compute_it(&checksum, ni, &node);
	}
	ni_idlist_free(&children);
	*checksum_p = checksum;
}

/*
 * Comute a checksum for the given NetInfo handle
 */
void
checksum_compute(
		 unsigned *checksum,
		 void *ni
		 )
{
	ni_id root;
	unsigned res;

	res = ni_getchecksum(ni);
	if (res != NI_INDEX_NULL) {
		*checksum = res;
		return;
	}
	if (ni_root(ni, &root) != NI_OK) {
		return;
	}
	compute_it(checksum, ni, &root);
}

/*
 * A directory was modified - increment the checksum accordingly
 */
void
checksum_inc(
	     unsigned *checksum,
	     ni_id id
	     )
{
	*checksum += (id.nii_object + 1);
}

/*
 * A new directory was created - fix the checksum accordingly
 */
void
checksum_add(
	     unsigned *checksum,
	     ni_id id
	     )
{
	*checksum += (id.nii_object + 1) * id.nii_instance;
}

/*
 * A directory was removed - fix the checksum accordingly
 */
void
checksum_rem(
	     unsigned *checksum,
	     ni_id id
	     )
{
	*checksum -= (id.nii_object + 1) * id.nii_instance;
}
