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
 * macNC.h
 * - definitions for Rhapsody Mac NC Boot Server
 */

/*
 * Modification History:
 *
 * December 2, 1997	Dieter Siegmund (dieter@apple)
 * - created
 */

#import <mach/boolean.h>

/**
 ** Defines:
 **/

#include "afp.h"

/*
 * HOSTPROP_
 * - these identify properties that are used for host entries
 *   that are specific to mac NCs
 */
#define HOSTPROP_HOST_NUMBER		"macNC_host_number"
#define HOSTPROP_AFP_USER_NAME		"macNC_afp_user_name"
#define HOSTPROP_MACOS_MACHINE_NAME	"macNC_MacOS_machine_name"

/*
 * BOOTSERV_CONFIG_NIDIR
 * - where all of the mac NC Boot Server property variables are stored
 *   in netinfo
 */
#define BOOTSERV_CONFIG_NIDIR		"/config/NetBootServer"

/*
 * CFGPROP_
 * - these identify properties that are stored in the
 *   BOOTSERV_CONFIG_NIDIR netinto directory
 */
#define CFGPROP_AFP_GROUP_NAME		"afp_group_name"
#define CFGPROP_AFP_USER_FORMAT		"afp_user_format"
#define CFGPROP_CHECK_SHADOW_SIZE	"check_shadow_size"
#define CFGPROP_CLIENT_IMAGE_DIR	"client_image_directory"
#define CFGPROP_DEFAULT_BOOTDIR 	"default_bootdir"
#define CFGPROP_DEFAULT_BOOTFILE	"default_bootfile"
#define CFGPROP_HOSTNAME_FORMAT		"hostname_format"
#define CFGPROP_IMAGE_DIR		"image_directory"
#define CFGPROP_PRIVATE_IMAGE_VOLUME	"private_image_volume"
#define CFGPROP_PRIVATE_IMAGE_NAME	"private_image_name"
#define CFGPROP_SHADOW_SUFFIX		"shadow_suffix"
#define CFGPROP_SHARED_IMAGE_VOLUME	"shared_image_volume"
#define CFGPROP_SHARED_IMAGE_NAME	"shared_image_name"
#define CFGPROP_SHAREPOINT_SUFFIX	"sharepoint_suffix"
#define CFGPROP_VOLUMES			"volumes"


/*
 * MACNC_SERVER_VERSION
 * - the value we pass back to the client in the BOOTP reply
 */
#define MACNC_SERVER_VERSION		0

/*
 * MACNC_SERVER_CREATOR
 * - the _creator value in the host entry
 */
#define MACNC_SERVER_CREATOR		"bootpd"

/*
 * MACNC_CLIENT_TYPE
 * - the value stored in the "client_types" property in a subnet description 
 *   for the NC (see subnetDescr.[hm]) in bootplib
 */
#define MACNC_CLIENT_TYPE	"macNC"

/*
 * AUFS_DEFAULT_USER
 * - we use a single login account for all NCs when using aufs
 *   to keep things simple
 */
#define	AUFS_DEFAULT_USER	"macnc000"

/*
 * AUFS_DEFAULT_PASSWORD
 * - default password for AFP login over aufs
 */
#define AUFS_DEFAULT_PASSWORD	"testing2"

/**
 ** Types:
 **/
typedef int (*funcptr_t)(void * arg);

/**
 ** Prototypes:
 **/
boolean_t	NC_cfg_init();
boolean_t	NC_request(interface_t * intface, u_char * pkt, int size,
			   id options, struct timeval * tv_p);

