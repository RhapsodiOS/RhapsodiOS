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
 * NetInfo object caching layer definitions
 * Copyright (C) 1989 by NeXT, Inc.
 */
typedef
enum ni_op {
	NIOP_WRITE,
	NIOP_READ,
	NIOP_READ_REMOTE,
	NIOP_READ_UNPRIVILEGED
} ni_op;

ni_status obj_init(char *, void **);
void obj_free(void *);
void obj_shutdown(void *, unsigned);
unsigned obj_getchecksum(void *);

bool_t obj_db_reopen(void *);

char *obj_dirname(void *);

ni_status obj_alloc_root(void *, ni_object **);
ni_status obj_alloc(void *, ni_object **);
ni_status obj_regenerate(void *, ni_object **, ni_id *);

void obj_unalloc(void *, ni_object *);
void obj_uncache(void *, ni_object *);

ni_status obj_lookup(void *, ni_id *, ni_op, ni_object **);
ni_status obj_lookup_root(void *, ni_op, ni_object **);

ni_status obj_commit(void *, ni_object *);
void obj_unlookup(void *, ni_object *);
ni_index obj_highestid(void *);
void obj_forget(void *);
void obj_renamedir(void *, char *);
