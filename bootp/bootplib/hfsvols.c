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
#ifdef ppc
/*
 * hfsvols.c
 * - implements a table of hfs volume entries with creation/lookup functions
 * - the volume entry maps between the hfs volume name and its mount point
 */

/*
 * Modification History:
 *
 * May 15, 1998	Dieter Siegmund (dieter@apple)
 * - created
 */
#import <stdio.h>
#import <unistd.h>
#import <stdlib.h>
#import <fcntl.h>
#import <sys/param.h>
#import <sys/ucred.h>
#import <sys/mount.h>
#import <mach/boolean.h>
#import <string.h>
#import <vol.h>

#import "hfsvols.h"
#import "afp.h"

static __inline__ void
print_fsstat_list(struct statfs * stat_p, int number)
{
    int i;

    for (i = 0; i < number; i++) {
	struct statfs * p = stat_p + i;
	printf("%s (%x %x) on %s from %s\n", p->f_fstypename, 
	       p->f_fsid.val[0], p->f_fsid.val[1], p->f_mntonname, 
	       p->f_mntfromname);
    }
}

static __inline__ struct statfs *
get_fsstat_list(int * number)
{
    int n;
    struct statfs * stat_p;

    n = getfsstat(NULL, 0, MNT_NOWAIT);
    if (n <= 0)
	return (NULL);

    stat_p = (struct statfs *)malloc(n * sizeof(*stat_p));
    if (stat_p == NULL)
	return (NULL);

    if (getfsstat(stat_p, n * sizeof(*stat_p), MNT_NOWAIT) <= 0) {
	free(stat_p);
	return (NULL);
    }
    *number = n;
    return (stat_p);
}

static __inline__ struct statfs *
fsstat_lookup(struct statfs * list_p, int n, dev_t dev)
{
    struct statfs * scan;
    int i;

    for (i = 0, scan = list_p; i < n; i++, scan++) {
	if (scan->f_fsid.val[0] == dev)
	    return (scan);
    }
    return (NULL);
}

void
hfsvols_print(hfsvols_list_t * vols)
{
    int i;

//    printf("There are %d hfs volume(s) on this computer\n", vols->count);
    for (i = 0; i < vols->count; i++) {
	printf("%s: mounted on %s from %s, dev_t %x\n",
	       vols->list[i].name,
	       vols->list[i].mounted_on,
	       vols->list[i].mounted_from,
	       vols->list[i].device);
    }
    return;
}

typedef struct {
    u_long		len;
    u_long		finderInfo[8];
} finderInfo_t;

static __inline__ void
S_print_finderInfo(finderInfo_t * finder)
{
    int i;

    char * cptr = (u_char *)finder->finderInfo;

    printf("we got %ld bytes back\n", finder->len);
    for (i = 0; i < 32; i++) 
	printf(" %c", cptr[i]);
    printf("\n");
    return;
}


void
hfsvols_free(hfsvols_list_t * list)
{
    if (list->list)
	free(list->list);
    list->list = NULL;
    free(list);
    return;
}

hfsvols_entry_t *
hfsvols_lookup(hfsvols_list_t * vols, u_char * name)
{
    int i;
    for (i = 0; i < vols->count; i++) {
	if (strcmp(vols->list[i].name, name) == 0)
	    return (vols->list + i);
    }
    return (NULL);
}

hfsvols_list_t *
hfsvols_list()
{
    struct CatalogAttributeInfo	catInfo;
    int				cursize = 1;
    hfsvols_entry_t *		list_p = NULL;
    long			n_vols;
    struct statfs * 		stat_p;
    int				stat_number;
    VolumeAttributeInfo 	volInfo;
    long			vol_index;

    stat_p = get_fsstat_list(&stat_number);
    if (stat_p == NULL || stat_number == 0)
	goto err;

    for (n_vols = 0, vol_index = 1; TRUE; vol_index++) {
	struct statfs * entry;

	if (GetVolumeInfo_VDI(vol_index, 0, NULL, 0, 0, 0, &volInfo) != 0) {
	    break;
	}
	if (GetCatalogInfo_VDI(volInfo.volumeID, AFP_DIRID_ROOT, ".", 0,
			       volInfo.nameEncoding, 0, &catInfo,
			       kMacOSHFSFormat, NULL, 0) != 0) {
	    goto err;
	}
	entry = fsstat_lookup(stat_p, stat_number, catInfo.c.device);

	if (entry == NULL) 
	    continue;
	if (list_p == NULL) {
	    list_p = (hfsvols_entry_t *)malloc(cursize * sizeof(*list_p));
	    if (list_p == NULL)
		goto err;
	}
	if (n_vols == cursize) {
	    cursize *= 2;
	    list_p = (hfsvols_entry_t *)realloc(list_p, 
					       cursize * sizeof(*list_p));
	    if (list_p == NULL)
		goto err;
	}
	{ /* set the values for the entry */
	    hfsvols_entry_t * vol_p = list_p + n_vols;

	    vol_p->volumeID = volInfo.volumeID;
	    strcpy(vol_p->name, volInfo.name);
	    strcpy(vol_p->mounted_on, entry->f_mntonname);
	    strcpy(vol_p->mounted_from, entry->f_mntfromname);
	    vol_p->device = catInfo.c.device;
	}
	n_vols++;
    }
    free(stat_p);

    { /* return the list */
	hfsvols_list_t * vols = (hfsvols_list_t *)malloc(sizeof(*vols));

	if (vols == NULL)
	    goto err;
	vols->count = n_vols;
	vols->list = list_p;
	return (vols);
    }

  err:
    if (list_p)
	free(list_p);
    if (stat_p)
	free(stat_p);
    return (NULL);
}

boolean_t
hfs_get_dirID(u_int32_t volumeID, u_char * path, u_int32_t * dirID_p)
{
    long			err = 0;
    CatalogAttributeInfo 	info;
    
    err = GetCatalogInfo_VDI(volumeID, AFP_DIRID_ROOT, path, 0, 0, 0, &info,
			     kMacOSHFSFormat, NULL, 0);
    if (err)
	return (FALSE);
    *dirID_p = info.c.objectID;
    return (TRUE);
}

/*
 * Function: hfs_set_file_size
 * 
 * Purpose:
 *   Set a file to be a certain length.
 */
int
hfs_set_file_size(int fd, off_t size)
{
#ifdef F_SETSIZE
    fcntl(fd, F_SETSIZE, &size);
#endif F_SETSIZE
    return (ftruncate(fd, size));
}

/*
 * Function: hfs_copy_finder_info
 *
 * Purpose:
 *   Copy the finder information of one file to another file.
 */
boolean_t
hfs_copy_finder_info(u_char * target_path, u_char * source_path)
{
    struct attrlist 	attrspec;
    finderInfo_t	finder;

    bzero(&finder, sizeof(finder));
    attrspec.bitmapcount	= ATTR_BIT_MAP_COUNT;
    attrspec.reserved		= 0;
    attrspec.commonattr		= ATTR_CMN_FNDRINFO;
    attrspec.volattr 		= 0;
    attrspec.dirattr 		= 0;
    attrspec.fileattr 		= 0;
    attrspec.forkattr 		= 0;

    /* if no source path, target is source */
    if (source_path == NULL) 
	source_path = target_path;

    if (getattrlist(source_path, &attrspec, &finder, sizeof(finder)))
	return (FALSE);

    if (setattrlist(target_path, &attrspec, finder.finderInfo,
		    sizeof(finder.finderInfo)))
	return (FALSE);
    return (TRUE);
}

#ifdef TESTING
#define syslog fprintf
#define LOG_INFO stderr
#import <sys/types.h>
#import <sys/stat.h>
#import <errno.h>

int
main(int argc, u_char * argv[])
{
    int number;
    hfsvols_list_t * vlist;
    int ret;

    vlist = hfsvols_list();
    if (vlist == 0 || vlist->count == 0) {
	printf("get volume list failed\n");
	exit(1);
    }
    hfsvols_print(vlist);
    hfsvols_free(vlist);
    exit(0);
}
#endif TESTING
#endif ppc
