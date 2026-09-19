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
 * sharepoints.c
 * - AFP sharepoint get/create routines
 */

/*
 * Modification History:
 *
 * Jan 29, 1999	Dieter Siegmund (dieter@apple)
 * - created
 */
#import <stdio.h>
#import <stdarg.h>
#import <stdlib.h>
#import <unistd.h>
#import <errno.h>
#import <sys/time.h>
#import <sys/types.h>

#import <sys/attr.h>
#import <vol.h>
#import <oamshim/AppleShareRegistry.h>
#import <ServerControl/ServerControlAPI.h>
#import <string.h>

#import "afp.h"
#import "sharepoints.h"

/* 
 * Types:
 */
typedef struct {
    SharePointSpec *	list;
    int			count;
} sharepoints_t;


void
sharepoints_print(void * s)
{
    sharepoints_t * shp = (sharepoints_t *)s;
    int i;

    printf("There are %d sharepoints:\n", shp->count);
    for (i = 0; i < shp->count; i++) {
	if (i > 0)
	    printf("\n");
	printf("SharePoint   : %s\n", shp->list[i].filename);
	printf("Volume ID    : %ld\n", shp->list[i].volumeID);
	printf("Directory ID : %ld\n", shp->list[i].dirID);
    }
    return;
}

/*
 * Function: sharepoint_create
 *
 * Purpose:
 *   Create a sharepoint for the given volume and path.
 *   The path must exist before calling this routine.
 * Returns:
 *   TRUE if successful, FALSE otherwise.
 */
boolean_t
sharepoint_create(u_int32_t volumeID, u_int32_t dirID)
{
    long			err = 0;
    SharePointSpec 		spInfo;

    spInfo.volumeID = volumeID;
    spInfo.dirID = dirID;
    err = AddSharePoint(kAFPServer, &spInfo);
    if (err)
	return (FALSE);
    return (TRUE);
}

/*
 * Function: sharepoints_lookup
 *
 * Purpose:
 *   Find a sharepoint with the given volume and directory ID.
 */
void *
sharepoints_lookup(void * s, u_int32_t volumeID, u_int32_t dirID)
{
    int 		i;
    sharepoints_t * 	shp = (sharepoints_t *)s;

    for (i = 0; i < shp->count; i++) {
	if (shp->list[i].volumeID == volumeID && shp->list[i].dirID == dirID)
	    return ((void *)shp->list + i);
    }
    return (FALSE);
}

/*
 * Function: sharepoints_list
 *
 * Purpose:
 *   Create a list of sharepoints in the system in a dynamically
 *   allocated structure.
 */
void *
sharepoints_list()
{
    int			cursize = 4;
    SharePointSpec *	list_p = NULL;
    int			n_shp;
    SharePointIterRef 	spIterRef;
    
    if (CreateSharePointIter(kAFPServer, kSCSharePointRec, &spIterRef))
	return (NULL);
    for (n_shp = 0; TRUE; n_shp++) {
	int 		attribSize;
	SharePointSpec 	spInfo;
	SharePointRef 	spRef;
	
	if (GetNextSharePoint(spIterRef, &spRef)
	    || GetSharePointAttribute(spRef, kSharePointName,  
				      sizeof(SharePointInfo), 
				      &attribSize, &spInfo)) {
	    break;
	}
	if (list_p == NULL) {
	    list_p = (SharePointSpec *)malloc(cursize * sizeof(*list_p));
	    if (list_p == NULL)
		goto err;
	}
	if (n_shp == cursize) {
	    cursize *= 2;
	    list_p = (SharePointSpec *)
		realloc(list_p, cursize * sizeof(*list_p));
	    if (list_p == NULL)
		goto err;
	}
	list_p[n_shp] = spInfo;
    }

    DeleteSharePointIter(spIterRef);

    { /* return the list */
	sharepoints_t * share_points;

	share_points = (sharepoints_t *)malloc(sizeof(*share_points));

	if (share_points == NULL)
	    goto err;
	share_points->count = n_shp;
	share_points->list = list_p;
	return ((void *)share_points);
    }

  err:
    if (list_p)
	free(list_p);
    return (NULL);
}

/*
 * Function: sharepoints_free
 *
 * Purpose:
 *   Free the resources allocated in a sharepoint list.
 */
void
sharepoints_free(void * s)
{
    sharepoints_t * shp = (sharepoints_t *)s;

    if (shp == 0)
	return;

    if (shp->list)
	free(shp->list);
    shp->list = NULL;
    shp->count = 0;
    free(shp);
}

#ifdef TESTING
int
main(int argc, char * argv[])
{
    if (argc > 2) {
	OSErr err = 0;
	VolumeAttributeInfo volInfo;
	int i;
	char vn[512] = { 0 };

	strcpy(vn, argv[1]);
	for (i = 1; i < 100; i++) {
	    err = GetVolumeInfo_VDI(i, 0, NULL, 0, 0, 0, &volInfo);
	    if (err)
		break;
	    if (strcmp(vn, argv[1]) == 0)
		break;
	}
	if (err) {
	    printf("GetVolumeInfo returned error %d : %s\n", errno, (char *)strerror(errno));
	    exit(1);
	}
	if (create_sharepoint(volInfo.volumeID, argv[2]) == FALSE)
	    printf("Create %s:%s failed\n", argv[1], argv[2]);
    }
    {
	void * shp = get_sharepoints();
	
	if (shp == NULL) {
	    printf("failed to get list of sharepoints\n");
	}
	else
	    print_sharepoints(shp);
    }

    exit (0);
    return (0);
}
#endif TESTING

#endif ppc
