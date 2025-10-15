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
 * hfsvols.h
 */

/*
 * Modification History:
 *
 * May 15, 1998	Dieter Siegmund (dieter@apple)
 * - created
 */

#define HFS_NAME_SIZE	512
#define PATH_SIZE	256

typedef struct {
    dev_t	device;
    u_int32_t	volumeID;
    u_char	name[HFS_NAME_SIZE];
    u_char	mounted_on[PATH_SIZE];
    u_char	mounted_from[PATH_SIZE];
} hfsvols_entry_t;

typedef struct {
    hfsvols_entry_t *	list;
    int			count;
} hfsvols_list_t;

void			hfsvols_free(hfsvols_list_t * list);
hfsvols_list_t *	hfsvols_list();
void			hfsvols_print(hfsvols_list_t * vols);
hfsvols_entry_t *	hfsvols_lookup(hfsvols_list_t * vols, u_char * name);

/*
 * HFS filesystem routines
 */
boolean_t		hfs_get_dirID(u_int32_t volumeID, 
				      u_char * path, u_int32_t * dirID_p);
int			hfs_set_file_size(int fd, off_t size);
boolean_t		hfs_copy_finder_info(u_char * target_path,
					     u_char * source_path);

