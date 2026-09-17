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
 * macNC.c
 * - macNC boot server
 * - supports netboot clients by:
 *   + allocating IP addresses
 *   + locating/creating disk image files
 *   + creating/providing AFP login
 *   + creating sharepoints
 */

/*
 * Modification History:
 *
 * December 2, 1997	Dieter Siegmund (dieter@apple.com)
 * - created
 * February 1, 1999	Dieter Siegmund (dieter@apple.com)
 * - create sharepoints at init time (and anytime we get a SIGHUP)
 *   and ensure permissions are correct
 */

#import <unistd.h>
#import <stdlib.h>
#import <sys/types.h>
#import <sys/stat.h>
#import <sys/socket.h>
#import <sys/ioctl.h>
#import <sys/file.h>
#import	<pwd.h>
#import <net/if.h>
#import <netinet/in.h>
#import <netinet/in_systm.h>
#import <netinet/ip.h>
#import <netinet/udp.h>
#import <netinet/bootp.h>
#import <netinet/if_ether.h>
#import <stdio.h>
#import <strings.h>
#import <errno.h>
#import <fcntl.h>
#import <ctype.h>
#import <netdb.h>
#import <syslog.h>
#import <sys/param.h>
#import <sys/mount.h>
#import <arpa/inet.h>
#import <mach/boolean.h>
#import <sys/wait.h>
#import <sys/resource.h>
#import <ctype.h>

#import "dhcp.h"
#import "netinfo.h"
#import "rfc_options.h"
#import "afpuser.h"
#import "macNCOptions.h"
#import "subnetDescr.h"
#import "interfaces.h"
#import "hostlist.h"
#import "bootpd.h"
#import "macNC.h"
#import "host_identifier.h"
#import "NIHosts.h"
#ifdef ppc
#import "hfsvols.h"
#import "sharepoints.h"
#endif ppc

/* external functions */
char *  	ether_ntoa(struct ether_addr *e);

/* local defines/variables */
#define MACNC_IGNORE_TIME	(2 * 60)
#define NIPROP__CREATOR		"_creator"

#ifdef ppc
static hfsvols_list_t * S_hfsvols = NULL;
#endif ppc
static boolean_t	S_init_done = FALSE;
static OAMSessionID	S_oam_session;
static boolean_t	S_shadow_both;
static boolean_t	S_default_password = FALSE;
static boolean_t	S_check_shadow_size = TRUE;
#ifdef ppc
static boolean_t	S_use_aufs;
#else
static boolean_t	S_use_aufs = TRUE;
#endif

/* strings retrieved from the configuration directory: */
static ni_name		S_afp_group_name = NULL;
static ni_name		S_afp_user_format = NULL;
static ni_name		S_client_image_dir = NULL;
static ni_name		S_default_bootdir = NULL;
static ni_name		S_default_bootfile = NULL;
static ni_name		S_hostname_format = NULL;
static ni_name		S_image_dir = NULL;
static ni_name		S_private_image_name = NULL;
static ni_name		S_private_image_volume = NULL;
static ni_name		S_shadow_suffix = NULL;
static ni_name		S_shared_image_name = NULL;
static ni_name		S_shared_image_volume = NULL;
static ni_name		S_sharepoint_suffix = NULL;

static ni_namelist	S_volumes = { 0 };

static struct {
    ni_name *	ptr;
    u_char *	propname;
} S_cfg_strings[] = {
    { &S_afp_group_name, 	CFGPROP_AFP_GROUP_NAME },
    { &S_afp_user_format,	CFGPROP_AFP_USER_FORMAT },
    { &S_client_image_dir,	CFGPROP_CLIENT_IMAGE_DIR },
    { &S_default_bootdir,	CFGPROP_DEFAULT_BOOTDIR },
    { &S_default_bootfile,	CFGPROP_DEFAULT_BOOTFILE },
    { &S_hostname_format,	CFGPROP_HOSTNAME_FORMAT },
    { &S_image_dir,		CFGPROP_IMAGE_DIR },
    { &S_private_image_name,	CFGPROP_PRIVATE_IMAGE_NAME },
    { &S_private_image_volume,	CFGPROP_PRIVATE_IMAGE_VOLUME },
    { &S_shadow_suffix,	CFGPROP_SHADOW_SUFFIX },
    { &S_shared_image_name,	CFGPROP_SHARED_IMAGE_NAME },
    { &S_shared_image_volume,	CFGPROP_SHARED_IMAGE_VOLUME },
    { &S_sharepoint_suffix, 	CFGPROP_SHAREPOINT_SUFFIX },
    { 0, 0 } /* terminate the list */
};

static u_char	S_tags[] = { 
    dhcptag_subnet_mask_e, 
    dhcptag_router_e, 
    dhcptag_domain_name_server_e,
    dhcptag_domain_name_e,
};
static int	S_tags_num = sizeof(S_tags) / sizeof(S_tags[0]);

static ni_proplist cfgProps = { 0 };

static struct hosts *		S_ignore_hosts = NULL;

static boolean_t
S_ipinuse(void * arg, struct in_addr ip)
{
    u_char * host;
    ni_proplist pl;
    
    if (lookup_host_by_ip(ip, &host, NULL, &pl)) {
	ni_proplist_free(&pl);
	if (verbose)
	    syslog(LOG_INFO, "macNC: %s is in use %s%s\n", inet_ntoa(ip),
		   host[0] ? "by " : "",
		   host[0] ? host : (u_char *) "");
	free(host);
	return (TRUE);
    }
    return (FALSE);
}

/*
 * Function: S_cfgProps_read
 *
 * Purpose:
 *   Read the boot server's configuration directory under netinfo, 
 *   caching the copy and update only if it has been modified.
 */
static boolean_t
S_cfgProps_read()
{
    static ni_id 	prev_confdir = {0};
    ni_id		confdir;
    
    if (ni_pathsearch(ni_local, &confdir, BOOTSERV_CONFIG_NIDIR) 
	!= NI_OK) {
	syslog(LOG_INFO, "macNC: local Netinfo dir '%s' not found",
	       BOOTSERV_CONFIG_NIDIR);
	return (FALSE);

    }
    if (bcmp(&confdir, &prev_confdir, sizeof(prev_confdir))) {
	/* directory was modified - re-read */
	ni_proplist_free(&cfgProps);
	timestamp_syslog("old proplist freed");
	if (ni_read(ni_local, &confdir, &cfgProps) != NI_OK)
	    return (FALSE);
	timestamp_syslog("re-read config dir");
    }
    prev_confdir = confdir;
    return (TRUE);
}

/*
 * Function: S_cfgProps_lookup
 *
 * Purpose:
 *   Find the given property in the boot server's configuration.
 *   Return the namelist pointer associated with that property, NULL
 *   if it doesn't exist.
 */
static ni_namelist *
S_cfgProps_lookup(u_char * propname)
{
    int i;

    if (S_cfgProps_read() == FALSE)
	return (NULL);

    for (i = 0; i < cfgProps.nipl_len; i++) {
	ni_property * p = &(cfgProps.nipl_val[i]);
	if (strcmp(propname, p->nip_name) == 0) {
	    return (&p->nip_val);
	}
    }
    return (NULL);
}
/*
 * Function: S_read_config
 *
 * Purpose:
 *   Read the list of configuration-related properties from the
 *   netinfo directory.
 */

static boolean_t 
S_read_config()
{
    boolean_t 		error = FALSE;
    int			i;
    ni_namelist *	nl_p;

#ifdef ppc
    S_use_aufs = FALSE;
    if (S_cfgProps_lookup("_use_aufs")) {
	syslog(LOG_INFO, 
	       "macNC: configured to use aufs");
	S_use_aufs = TRUE;
    }
#endif ppc

    S_check_shadow_size = TRUE;
    if ((nl_p = S_cfgProps_lookup(CFGPROP_CHECK_SHADOW_SIZE)) 
	&& nl_p->ninl_len) {
	u_char ch = nl_p->ninl_val[0][0];

	if (ch == 'y' || ch == 'Y' || ch == 't' || ch == 'T')
	    ;
	else
	    S_check_shadow_size = FALSE; /* don't check shadow file size */
	syslog(LOG_INFO, "macNC: configured to %scheck shadow size",
	       S_check_shadow_size ? "" : "not ");
    }

    S_default_password = FALSE;
    if (S_cfgProps_lookup("_default_password")) {
	syslog(LOG_INFO, 
	       "macNC: configured to use default password");
	S_default_password = TRUE;
    }

    S_shadow_both = FALSE;
    if (S_cfgProps_lookup("_shadow_both")) {
	syslog(LOG_INFO, 
	       "macNC: configured to shadow both shared and private");
	S_shadow_both = TRUE;
    }

    /* if we're re-reading, free the old strings */
    for (i = 0; S_cfg_strings[i].ptr; i++) {
	ni_name_free(S_cfg_strings[i].ptr);
    }
    ni_namelist_free(&S_volumes);

    /* get the new list of strings */
    for (i = 0; S_cfg_strings[i].ptr != NULL; i++) {
	nl_p = S_cfgProps_lookup(S_cfg_strings[i].propname);
	if (nl_p == NULL || nl_p->ninl_len == 0) {
	    syslog(LOG_INFO, "macNC: %s property is missing or empty",
		   S_cfg_strings[i].propname);
	    error = TRUE;
	}
	else if (error == FALSE)
	    *(S_cfg_strings[i].ptr) = ni_name_dup(nl_p->ninl_val[0]);
    }

    /* find the list of volumes to use */
    nl_p = S_cfgProps_lookup(CFGPROP_VOLUMES);
    if (nl_p == NULL || nl_p->ninl_len == 0) {
	syslog(LOG_INFO, "macNC: property %s is missing or empty", 
	       CFGPROP_VOLUMES);
	error = TRUE;
    }
    else if (error == FALSE)
	S_volumes = ni_namelist_dup(*nl_p);
    return (error == FALSE);
}

/*
 * Function: S_get_macnc_gid
 *
 * Purpose:
 *   Retrieve the Mac NC Group gid.  We do this by
 *   reading netinfo directly, which really isn't the
 *   right way to do this.
 */
boolean_t
S_get_macnc_gid(ni_name realname, gid_t * gid)
{
    ni_id 		dir;
    ni_namelist 	nl;
    u_char		path[PATH_MAX];
    boolean_t		ret = FALSE;
    ni_status 		status;

#define NIPROP_REALNAME		"realname"
#define NIPROP_GID		"gid"

    NI_INIT(&nl);
    sprintf(path, "/groups/%s=%s", NIPROP_REALNAME, realname);
    status = ni_pathsearch(ni_local, &dir, path);
    if (status != NI_OK) {
	syslog(LOG_INFO, "macNC: netinfo dir '%s': %s", path,
	       ni_error(status));
	return (FALSE);
    }

    status = ni_lookupprop(ni_local, &dir, NIPROP_GID, &nl);
    if (status == NI_OK) {
	*gid = strtol(nl.ninl_val[0], 0, 0);
	ret = TRUE;
    }
    ni_namelist_free(&nl);
    return (ret);
}


/*
 * Function: S_create_path
 *
 * Purpose:
 *   Create the given directory hierarchy.  Return FALSE if anything
 *   went wrong.
 */
static __inline__ boolean_t
S_create_path(u_char * dirname)
{
    boolean_t	done = FALSE;
    u_char *	scan;

    if (mkdir(dirname, 0755) == 0 || errno == EEXIST) {
	return (TRUE);
    }
    if (errno != ENOENT) {
	syslog(LOG_INFO, "macNC: couldn't create directory '%s': %m", dirname);
	return (FALSE);
    }
    {
	u_char	path[PATH_MAX];
	for (path[0] = '\0', scan = dirname; done == FALSE;) {
	    u_char * 	next_sep;
	    
	    if (scan == NULL || *scan != '/')
		return (FALSE);
	    scan++;
	    next_sep = strchr(scan, '/');
	    if (next_sep == 0) {
		done = TRUE;
		next_sep = dirname + strlen(dirname);
	    }
	    strncpy(path, dirname , next_sep - dirname);
	    path[next_sep - dirname] = '\0';
	    if (mkdir(path, 0755) == 0 || errno == EEXIST)
		;
	    else {
		syslog(LOG_INFO, 
		       "macNC: couldn't create subdirectory '%s': %m", path);
		return (FALSE);
	    }
	    scan = next_sep;
	}
    }
    return (TRUE);
}

/*
 * Function: S_cfg_init
 *
 * Purpose:
 *   This function does all of the variable initialization needed by the
 *   boot server.  It can be called multiple times if necessary.
 */
static boolean_t
S_cfg_init()
{
    syslog(LOG_INFO, "macNC: re-reading configuration");
	   
    if (S_read_config() == FALSE)
	return (FALSE);

    { /* create the Mac NC group if it doesn't already exist */
	OAMStatus 		status;
	status = createOAMGroup(S_oam_session, S_afp_group_name);
	if (status != noErr && status != kOAMErrDuplicateObject) {
	    syslog(LOG_INFO, "macNC: createOAMGroup failed status %d", status);
	    return (FALSE);
	}
    }

#ifdef ppc
    /* get list of hfs volumes */
    if (S_hfsvols != NULL)
	hfsvols_free(S_hfsvols);
    S_hfsvols = hfsvols_list();
    if (S_hfsvols == NULL)
	return (FALSE);
    if (debug)
	hfsvols_print(S_hfsvols);

    if (S_use_aufs == FALSE) { 
	/* verify chosen volumes exist and create sharepoints if necessary */
	boolean_t 	error = FALSE;
	gid_t		gid;
	int 		i;
	u_char		path[PATH_MAX];
	void *		shp;
	
	/* get the group id for the mac nc group */
	if (S_get_macnc_gid(S_afp_group_name, &gid) == FALSE) {
	    syslog(LOG_INFO, "macNC: failed to lookup group id for %s",
		   S_afp_group_name);
	    return (FALSE);
	}

	/* get the list of sharepoints */
	shp = sharepoints_list();
	if (debug) {
	    if (shp)
		sharepoints_print(shp);
	    else
		printf("No sharepoints configured\n");
	}

	/* create sharepoints for each of the chosen volumes */
	for (i = 0; i < S_volumes.ninl_len; i++) {
	    u_int32_t		dirID;
	    hfsvols_entry_t *	entry;
	    ni_name		vol = S_volumes.ninl_val[i];

	    entry = hfsvols_lookup(S_hfsvols, vol);
	    if (entry == NULL) {
		syslog(LOG_INFO, "macNC: hfs volume '%s' does not exist", vol);
		error = TRUE;
		break;
	    }
	    sprintf(path, "%s/%s%s", entry->mounted_on, vol,
		    S_sharepoint_suffix);
	    /* make sure the sharepoint directory exists */
	    if (S_create_path(path) == FALSE) {
		error = TRUE;
		break;
	    }
	    /*
	     * Verify permissions/ownership
	     * We restrict write access to root only,
	     * the Mac NC Group gets read/search, and others
	     * get search only. Others need search because
	     * clients use TFTP to get the boot file that might be
	     * on this volume; tftpd runs as user nobody.
	     */
	    if (chown(path, 0, gid) < 0
		|| chmod(path, 0751) < 0) {
		syslog(LOG_INFO, "macNC: chmod/chown '%s' failed: %m", path);
		error = TRUE;
		break;
	    }

	    /* create a sharepoint if one doesn't already exist */
	    sprintf(path, "%s%s", vol, S_sharepoint_suffix);
	    if (hfs_get_dirID(entry->volumeID, path, &dirID) == FALSE) {
		syslog(LOG_INFO, 
		       "macNC: couldn't get HFS directory ID '%s': %m", path);
		error = TRUE;
		break;
	    }
	    if (shp == NULL 
		|| sharepoints_lookup(shp, entry->volumeID, dirID) == NULL) {
		if (sharepoint_create(entry->volumeID, dirID) == FALSE) {
		    syslog(LOG_INFO,
			   "macNC: failed to create sharepoint for %s:%s",
			   vol, path);
		    error = TRUE;
		    break;
		}
	    }
	}
	if (shp)
	    sharepoints_free(shp);

	if (error)
	    return (FALSE);
    }
#endif ppc

    return (TRUE);
}

/*
 * Function: NC_init
 *
 * Purpose:
 *   Initialize state for dealing with macNC's:
 * Returns:
 *   TRUE if success, FALSE if failure
 */
static boolean_t
NC_init()
{
    struct timeval 	tv;

    /* one-time initialization */
    if (S_init_done)
	return (TRUE);

    if (!ni_local) {
	syslog(LOG_INFO,
	       "macNC: local netinfo domain not in search domains - exiting");
	exit(2);
    }
    { /* initialize an OAM session */
	OAMStatus 		status;

	status = openOAMSession(&S_oam_session);
	if (status != noErr) {
	    syslog(LOG_INFO, 
		   "macNC: openOAMSession failed with status %d", status);
	    return (FALSE);
	}
    }

    /* read the configuration directory */
    if (S_cfg_init() == FALSE) {
	return (FALSE);
    }

    /* use microseconds for the random seed: password is a random number */
    gettimeofday(&tv, 0);
    srandom(tv.tv_usec);

    /* one-time initialization */
    S_init_done = TRUE;
    return (TRUE);
}

/*
 * Function: NC_cfg_init
 *
 * Purpose:
 *   Called from bootp if we received a SIGHUP.
 */
boolean_t
NC_cfg_init()
{
    if (S_init_done == TRUE)
	(void)S_cfg_init(); /* one-time initialization */
    else if (NC_init() == FALSE) { /* subsequent initialization */
	syslog(LOG_INFO, "macNC: NetBoot service turned off");
	return (FALSE);
    }
    hostlistfree(&S_ignore_hosts);
    return (TRUE);
}

/*
 * Function: S_set_uid_gid
 *
 * Purpose:
 *   Given a path to a file, make the owner of both the
 *   enclosing directory and the file itself to user/group uid/gid.
 */
static __inline__ int
S_set_uid_gid(u_char * file, uid_t uid, gid_t gid)
{
    u_char 	dir[PATH_MAX];
    u_char *	last_slash = strrchr(file, '/');

    if (file[0] != '/' || last_slash == NULL) {
	if (debug)
	    printf("path '%s' is not valid\n", file);
	return (-1);
    }

    strncpy(dir, file, last_slash - file);
    dir[last_slash - file] = '\0';
    if (chown(dir, uid, gid) == -1)
	return (-1);
    if (chown(file, uid, gid) == -1)
	return (-1);
    return (0);
}

/**
 ** AFP oam user/group access functions: S_afp*
 **/
/*
 * Function: S_afp_hostname_format
 * Purpose:
 *   Format the hostname string from the host_number.
 */
static __inline__ void
S_afp_hostname_format(unsigned char * name, int host_number)
{
    sprintf(name, S_afp_user_format, host_number);
    return;
}

/*
 * Function: S_afp_host_exists
 *
 * Purpose:
 *   Return whether host with number 'n' exists 
 */
static __inline__ boolean_t
S_afp_host_exists(u_char * name)
{
    OAMStatus 		status;

    status = isOAMUser(S_oam_session, name);
    return ((status == noErr) ? TRUE : FALSE);
}


/*
 * Function: S_afp_new_host
 *
 * Purpose:
 *   Create a new host in the oam user registry.
 * Note:
 *   Each macNC host is stored as a user in the oam registry.
 */
static __inline__ boolean_t
S_afp_new_host(u_char * name, u_char * inet_name, u_char * passwd)
{
    OAMStatus 		status;
    
    status = createOAMUser(S_oam_session, name, inet_name, passwd); 
    if (status != noErr) {
	syslog(LOG_INFO, "macNC: createOAMUser(%s) failed, status %d",
	       name, status);
    }
    return ((status == noErr) ? TRUE : FALSE);
}

/*
 * Function: S_afp_delete_host
 *
 * Purpose:
 *   Delete a host from the oam user registry.
 */
static __inline__ boolean_t
S_afp_delete_host(u_char * name)
{
    OAMStatus 		status;
    
    status = deleteOAMUser(S_oam_session, name);
    if (status != noErr) {
	if (verbose)
	    syslog(LOG_INFO, "macNC: deleteOAMUser(%s) failed, status %d",
		   name, status);
    }
    return ((status == noErr) ? TRUE : FALSE);
}

/*
 * Function: S_afp_add_group_member
 *
 * Purpose:
 *   Add a host to the "Mac NC" group in the oam registry.
 */
static __inline__ boolean_t
S_afp_add_group_member(u_char * name)
{
    OAMStatus 		status;
    
    status = addOAMGroupMember(S_oam_session, S_afp_group_name, name);
    if (status != noErr) {
	if (verbose)
	    syslog(LOG_INFO, 
		   "macNC: addOAMGroupMember(%s, %s) failed, status %d", 
		   S_afp_group_name, name, status);
    }
    return ((status == noErr) ? TRUE : FALSE);
}

/*
 * Function: S_afp_remove_group_member
 * Purpose:
 *   Remove a host from the "Mac NC" group in the oam registry.
 */
static __inline__ boolean_t
S_afp_remove_group_member(u_char * name)
{
    OAMStatus 		status;
    
    status = removeOAMGroupMember(S_oam_session, S_afp_group_name, name);
    if (status != noErr) {
	if (verbose)
	    syslog(LOG_INFO, 
		   "macNC: removeOAMGroupMember(%s, %s) failed, status %d", 
		   S_afp_group_name, name, status);
    }
    return ((status == noErr) ? TRUE : FALSE);
}

/*
 * Function: S_afp_set_password
 * Purpose:
 *   Set the password for the given host.
 */
static __inline__ boolean_t
S_afp_set_password(u_char * name, u_char * passwd)
{
    OAMStatus 		status;

    status = setOAMUserPassword(S_oam_session, name, passwd);
    return ((status == noErr) ? TRUE : FALSE);
}

/**
 ** Other local utility routines:
 **/


/*
 * Function: S_next_machine_number
 *
 * Purpose:
 *   Return the next available machine number.
 */
static __inline__ int
S_next_machine_number()
{
    ni_id		dir;
    int			i;
    u_char 		path[PATH_MAX];
    ni_status		status;

    for (i = 1; TRUE; i++) {
	sprintf(path, "%s/%s=%d", NIDIR_MACHINES, HOSTPROP_HOST_NUMBER, 
		i);
	status = ni_pathsearch(ni_local, &dir, path);
	if (status != NI_OK)
	    break;
    }
    return (i);
}

/*
 * Function: S_get_client_info
 *
 * Purpose:
 *   Retrieve the macNC client information from the given packet.
 *   First try to parse the dhcp options, then look for the client
 *   version tag and client info tag.  The client info tag will
 *   contain "Apple MacNC".
 *
 * Returns:
 *   TRUE and client_version if client version is present in packet
 *   FALSE otherwise
 */
static boolean_t
S_get_client_info(struct dhcp * pkt, int pkt_size, id options, 
		  u_int * client_version)
{ /* get the client version info - if not present, not an NC */
    void *		client_id;
    int			opt_len;
    void *		vers;

    if (options == nil
	|| (vers = [options findOptionWithTag:macNCtag_client_version_e
		    Length:&opt_len]) == NULL) {
	return (FALSE);
    }
    client_id = [options findOptionWithTag:macNCtag_client_info_e
	         Length:&opt_len];
    if (client_id == NULL)
	return (FALSE);
    if (client_id == NULL || opt_len != strlen(MACNC_CLIENT_INFO)
	|| bcmp(client_id, MACNC_CLIENT_INFO, opt_len)) {
	return (FALSE);
    }
    *client_version = ntohl(*((unsigned long *)vers));
    return (TRUE);
}


/*
 * Function: S_set_host_ip
 *
 * Purpose:
 *   Set the ip address of the given host.
 */
static boolean_t
S_set_host_ip(u_char * hostname, struct in_addr ip_addr)
{
    return (ni_sethostprop(ni_local, hostname, NIPROP_IPADDR, 
			   inet_ntoa(ip_addr)));
}

/* 
 * Function: S_make_aufs_finder_info
 *
 * Purpose:
 *   Create the aufs finder info file in the .finderinfo directory.
 * Note:
 *   This is very hacked up stuff, don't expect to make sense of it.
 *   The format of the file was determined by looking at the file
 *   aufs creates and reverse engineering it.
 */
static boolean_t
S_make_aufs_finder_info(u_char * path)
{
    int		fd;
    u_char 	finder_file[PATH_MAX];
    u_char *	file;
    struct stat sb;

    file = strrchr(path, '/') + 1;
    strncpy(finder_file, path, file - path - 1);
    finder_file[file - path - 1] = '\0';
    strcat(finder_file, "/.finderinfo");

    /* create the .finderinfo directory if necessary */
    if (stat(finder_file, &sb) == 0) {
	if (S_ISDIR(sb.st_mode) == 0) {
	    syslog(LOG_INFO, "macNC: finder directory exists as a file '%s'",
		   finder_file);
	    return (FALSE);
	}
    }
    else if (mkdir(finder_file, 0777) != 0 && errno != EEXIST) {
	syslog(LOG_INFO, "macNC: couldn't create dir '%s': %m", finder_file);
	return (FALSE);
    }

    /* create the file in the .finderinfo directory */
    strcat(finder_file, "/");
    strcat(finder_file, file);
    if (stat(finder_file, &sb) == 0) /* already exists */ {
	return (TRUE);
    }
    if ((fd = open(finder_file, O_CREAT|O_TRUNC|O_WRONLY, 0666)) < 0) {
	syslog(LOG_INFO, "macNC: couldn't open '%s': %m", finder_file);
	return (FALSE);

    }
    { /* format contents of the file CAP uses to provide type/creator */
	u_char 	find_data[286];

	bzero(find_data, sizeof(find_data));
	strcpy(find_data, "dimgddsk");
	strcpy(&find_data[51], file);
	find_data[8]  = 0x01;
	find_data[10] = 0xff;
	find_data[11] = 0xff;
	find_data[12] = 0xff;
	find_data[13] = 0xff;
	find_data[34] = 0xff;
	find_data[35] = 0x10;
	find_data[36] = 0xda;
	find_data[37] = 0x02;

	if (write(fd, find_data, sizeof(find_data)) < sizeof(find_data)) {
	    syslog(LOG_INFO, "macNC: couldn't write '%s': %m", path);
	    close(fd);
	    return (FALSE);
	}
    }
    close(fd);
    return (TRUE);
}

#ifdef ppc
static __inline__ boolean_t
S_make_finder_info(u_char * shadow_path, u_char * real_path)
{
    if (S_use_aufs)
	return (S_make_aufs_finder_info(shadow_path));
    return (hfs_copy_finder_info(shadow_path, real_path));
}
/*
 * Function: S_hfs_volume_path
 *
 * Purpose:
 *   Turn an HFS volume name into its mounted-on path name.
 */
static __inline__ u_char * 
S_hfs_volume_path(u_char * path, u_char * vol)
{
    hfsvols_entry_t * 	entry = hfsvols_lookup(S_hfsvols, vol);

    if (entry == NULL)
	return (NULL);
    sprintf(path, "%s/%s%s", entry->mounted_on, vol, S_sharepoint_suffix);
    return (path);
}

#else ppc
static __inline__ boolean_t
S_make_finder_info(u_char * shadow_path, u_char * real_path)
{
    return (S_make_aufs_finder_info(shadow_path));
}
#endif ppc

/*
 * Function: S_get_volpath
 *
 * Purpose:
 *   Format a volume pathname given a volume, directory and file name.
 */
static __inline__ void
S_get_volpath(u_char * path, u_char * vol, u_char * dir, u_char * file)
{
    if (S_use_aufs) { 
	/* if using aufs, we make sure that the volume name is the root dir */
	sprintf(path, "/%s/%s%s", vol, vol, S_sharepoint_suffix);
    }
#ifdef ppc
    else { /* turn the volume name into a path */
	u_char * volpath;

	volpath = S_hfs_volume_path(path, vol);

	if (volpath == NULL) {
	    syslog(LOG_INFO, "macNC: volume %s doesn't exist - internal error",
		   vol);
	    path[0] = 0;
	    return;
	}
    }
#endif ppc
    if (dir && *dir != '\0') {
	strcat(path, "/");
	strcat(path, dir);
    }
    if (file && *file != '\0') {
	strcat(path, "/");
	strcat(path, file);
    }
    return;
}

/*
 * Function: S_create_volume_dir
 *
 * Purpose:
 *   Create the given directory path on the given volume.
 */
static boolean_t
S_create_volume_dir(u_char * vol, u_char * dirname)
{
    u_char 		path[PATH_MAX];

    S_get_volpath(path, vol, dirname, NULL);
    if (S_create_path(path) == FALSE)
	return (FALSE);
    if (S_use_aufs) {
	(void)S_make_aufs_finder_info(path);
    }
    return (TRUE);
}

/*
 * Function: S_lookup_host
 *
 * Purpose:
 *   Lookup the host by its ethernet address in the local netinfo domain.
 *   Return all of the useful properties for this host entry.
 * Returns:
 *   TRUE: if the host exists and all properties exist and are valid
 *
 *   FALSE: host does not exist or there were errors in the properties
 *   *err will be set to FALSE if the host does not exist
 *   *err will be set to TRUE if there were errors in the properties
 */
static __inline__ boolean_t
S_lookup_host(u_char hwtype, void * hwaddr, int hwlen,
	      struct in_addr subnetaddr, struct in_addr subnetmask,
	      struct in_addr * iaddr_p,
	      u_char * * host_p, u_char * * afp_host_p, 
	      u_char * * macOS_machine_p, u_char * * bootfile_p,
	      int * host_number, boolean_t * err)
{
    ni_id		dir;
    id			domain;
    ni_proplist		pl;
    ni_name		str;

    /* make sure all string pointers are zeroed out */
    *host_p = NULL;
    *afp_host_p = NULL;
    *macOS_machine_p = NULL;
    *bootfile_p = NULL;
    NI_INIT(&pl);

    *err = FALSE;
    /* get the host entry */
    if (use_en_address && hwtype == ARPHRD_ETHER) {
	domain = [NIHosts lookupKey:NIPROP_EN_ADDRESS 
		  Value:ether_ntoa((struct ether_addr *)hwaddr)
		  DomainList:niSearchDomains
		  PropList:&pl Dir:&dir];
    }
    else {
	u_char *	idstr = NULL;

	idstr = identifierToString(hwtype, hwaddr, hwlen);
	if (idstr == NULL) {
	    *err = TRUE;
	    syslog(LOG_INFO, "macNC: identifierToString failed");
	    return (FALSE);
	}
	domain = [NIHosts lookupKey:NIPROP_IDENTIFIER Value:idstr
		  DomainList:niSearchDomains
		  PropList:&pl Dir:&dir];
	free(idstr);
    }
    if (domain == nil) /* no such entry */
	return (FALSE);

    /* ignore the host if not in the local netinfo domain */
    if ([domain handle] != ni_local) {
	*err = TRUE;
	if (verbose)
	    syslog(LOG_INFO, "macNC: host entry not in local netinfo domain");
	return (FALSE);
    }
    /* retrieve the host name */
    str = ni_valforprop(&pl, NIPROP_NAME);
    if (str == NULL) {
	if (verbose)
	    syslog(LOG_INFO, "macNC: host name missing");
	*err = TRUE;
	goto error_return;
    }
    *host_p = ni_name_dup(str);

    /* retrieve the bootfile */
    str = ni_valforprop(&pl, NIPROP_BOOTFILE);
    if (str)
	*bootfile_p = ni_name_dup(str);
    else
	; /* if it's not there, we'll just use the default */

    /* get the host number */
    str = ni_valforprop(&pl, HOSTPROP_HOST_NUMBER);
    if (str == NULL) {
	if (verbose)
	    syslog(LOG_INFO, "macNC: %s bad/missing", HOSTPROP_HOST_NUMBER);
	*err = TRUE;
	goto error_return;
    }
    *host_number = atoi(str);

    /* get the afp user/host name */
    str = ni_valforprop(&pl, HOSTPROP_AFP_USER_NAME);
    if (str == NULL) {
	if (verbose)
	    syslog(LOG_INFO, "macNC: %s bad/missing", HOSTPROP_AFP_USER_NAME);
	*err = TRUE;
	goto error_return;
    }
    *afp_host_p = ni_name_dup(str);

    /* get the macOS machine name */
    str = ni_valforprop(&pl, HOSTPROP_MACOS_MACHINE_NAME);
    if (str == NULL)
	/* not there, just use the afp host name */
	*macOS_machine_p = ni_name_dup(*afp_host_p);
    else
	*macOS_machine_p = ni_name_dup(str);

    /* retrieve the ip address */
    str = ni_valforprop(&pl, NIPROP_IP_ADDRESS);
    if (str == NULL) /* shouldn't happen, but we can work around it */
	iaddr_p->s_addr = 0;
    else
	iaddr_p->s_addr = inet_addr(str);

    if (in_subnet(subnetaddr, subnetmask, *iaddr_p) == FALSE) {
	/* allocate a new ip address */
	timestamp_syslog("client switched networks");
	*iaddr_p = subnetaddr;
	if ([subnets acquireIp:iaddr_p ClientType:MACNC_CLIENT_TYPE 
	     Func:S_ipinuse Arg:0] == FALSE) {
	    syslog(LOG_INFO, "macNC: failed to get new ip address for %s",
		   *host_p);
	    *err = TRUE;
	    goto error_return;
	}
	if (S_set_host_ip(*host_p, *iaddr_p) == FALSE) {
	    syslog(LOG_INFO, "macNC: failed to set new ip address '%s'",
		   *host_p);
	    *err = TRUE;
	    goto error_return;
	}
	timestamp_syslog("new ip address assigned");
    }
    
    ni_proplist_free(&pl);
    return (TRUE);

  error_return:
    ni_proplist_free(&pl);
    return (FALSE);
}

/*
 * Function: S_new_host
 *
 * Purpose:
 *   Create a new macNC host.
 * Parameters:
 *   In:  ea_p 		- ethernet address of host
 * 	  subnet_addr 	- receive interface's ip address
 *
 *   Out: remainder of parameters
 */
static boolean_t
S_new_host(struct in_addr subnet_addr,
	   u_char hwtype, void * hwaddr, int hwlen,
	   struct in_addr * ip_addr_p, u_char * * hostname, 
	   u_char * * afp_hostname, u_char * * macOS_machine,
	   u_char * * bootfile, int * hostnum_p)
{
    u_char buf[256];

    *ip_addr_p = subnet_addr;

    if ([subnets acquireIp:ip_addr_p ClientType:MACNC_CLIENT_TYPE
	 Func:S_ipinuse Arg:0] == FALSE) {
	timestamp_syslog("no ip addresses available");
	syslog(LOG_INFO, "macNC: no ip addresses on subnet %s",
	       inet_ntoa(subnet_addr));
	return (FALSE);
    }
    timestamp_syslog("ip address assigned");

    /* figure out the next machine number to use */
    *hostnum_p = S_next_machine_number();

    /* form the default hostname, afp_hostname strings */
    sprintf(buf, S_hostname_format, *hostnum_p);
    *hostname = ni_name_dup(buf);
    S_afp_hostname_format(buf, *hostnum_p);
    *afp_hostname = ni_name_dup(buf);
    *macOS_machine = ni_name_dup(buf); /* default to same as AFP */

    { /* clean-up an existing afp host entry if it exists */

	int tmp = verbose;
	verbose = 0; /* don't bother warning, we don't care */
	(void)S_afp_remove_group_member(*afp_hostname);
	(void)S_afp_delete_host(*afp_hostname);
	verbose = tmp;
    }

    /* create the afp machine user */
    if (S_afp_new_host(*afp_hostname, *hostname, AUFS_DEFAULT_PASSWORD) 
	== FALSE) {
	syslog(LOG_INFO, "macNC: couldn't add new afp host %s",
	       *afp_hostname);
        return (FALSE);
    }
    timestamp_syslog("afp user created");

    /* add the user to the afp group */
    if (S_afp_add_group_member(*afp_hostname) == FALSE) {
	(void)S_afp_delete_host(*afp_hostname);
	syslog(LOG_INFO, "macNC: couldn't add host %s to afp group",
	       *afp_hostname);
	return (FALSE);
    }
    timestamp_syslog("added to afp group");

    /* get the default bootfile */
    *bootfile = ni_name_dup(S_default_bootfile);

    { /* create the NC host entry in netinfo */
	u_char 		buf[32];
	ni_proplist 	pl;
	extern boolean_t use_en_address;

	/* add our NC-specific properties */
	NI_INIT(&pl);
	sprintf(buf, "%d", *hostnum_p);
	ni_proplist_addprop(&pl, HOSTPROP_HOST_NUMBER, (ni_name)buf);
	ni_proplist_addprop(&pl, HOSTPROP_AFP_USER_NAME, 
			    (ni_name)*afp_hostname);
	ni_proplist_addprop(&pl, HOSTPROP_MACOS_MACHINE_NAME, 
			    (ni_name)*macOS_machine);
	ni_proplist_addprop(&pl, NIPROP__CREATOR, MACNC_SERVER_CREATOR);
	/* create the entry */
	if (ni_createhost(ni_local, &pl, *hostname, 
			  hwtype, hwaddr, hwlen, *ip_addr_p, *bootfile,
			  use_en_address) != 0) {
	    ni_proplist_free(&pl);
	    syslog(LOG_INFO, 
		   "macNC: failed to create local Netinfo entry for '%s'",
		   ether_ntoa(hwaddr));
	    return (FALSE);
	}
	ni_proplist_free(&pl);
    }
    timestamp_syslog("netinfo host created");
    return (TRUE);
}

/*
 * Function: S_create_shadow_file
 *
 * Purpose:
 *   Create a new empty file with the same size/attributes as another file.
 */
#define SHADOW_FILE_PERMS	0700
static __inline__ boolean_t
S_create_shadow_file(u_char * shadow_path, u_char * real_path,
		     uid_t uid, gid_t gid)
{
    int 		fd;
    struct stat 	sb;

    /* get the size of the file to be shadowed */
    if (stat(real_path, &sb) != 0) {
	syslog(LOG_INFO, "macNC: couldn't stat %s:%s", real_path);
	return (FALSE);
    }

    { /* does shadow already exist with the right mode/size/user/group? */
	struct stat sb_shadow;
	errno = 0;
	if (stat(shadow_path, &sb_shadow) == 0 
	    && sb_shadow.st_uid == uid
	    && (S_check_shadow_size == FALSE
		|| sb_shadow.st_size == sb.st_size)
	    && (sb_shadow.st_mode & ACCESSPERMS) == SHADOW_FILE_PERMS) {
	    if (debug) {
		printf("%smode/user/group on shadow are OK\n",
		       S_check_shadow_size ? "size/" : "");
	    }
	    return (TRUE);
	}
	if (debug && errno == 0) {
	    printf("uid %d gid %d size %f mode %o\n",
		   sb_shadow.st_uid, sb_shadow.st_gid,
		   (float)sb_shadow.st_size,
		   sb_shadow.st_mode & ACCESSPERMS);
	    printf("should be uid %d gid %d size %f mode %o\n",
		   uid, gid, (float)sb.st_size, SHADOW_FILE_PERMS);
	}
    }

    /* remove the image file if it exists */
    S_set_uid_gid(shadow_path, 0, 0);
    (void)unlink(shadow_path); /* unlink it */

    /* create the new shadow file */
    fd = open(shadow_path, O_NO_MFS | O_CREAT | O_TRUNC | O_WRONLY, 
	      SHADOW_FILE_PERMS);
    if (fd < 0) {
	syslog(LOG_INFO, "macNC: couldn't create file '%s': %m", shadow_path);
	return (FALSE);
    }
    if (S_use_aufs) {
	if (ftruncate(fd, sb.st_size)) {
	    syslog(LOG_INFO, "macNC: ftruncate '%s' failed: %m", shadow_path);
	    goto err;
	}
    }
#ifdef ppc
    else if (hfs_set_file_size(fd, sb.st_size)) {
	syslog(LOG_INFO, "macNC: hfs_set_file_size '%s' failed: %m",
	       shadow_path);
	goto err;
    }
#endif ppc

    if (S_make_finder_info(shadow_path, real_path) == FALSE) 
	goto err;

    fchmod(fd, SHADOW_FILE_PERMS);
    close(fd);

    /* correct the owner of the path */
    if (S_set_uid_gid(shadow_path, uid, gid)) {
	syslog(LOG_INFO, "macNC: setuidgid '%s' to %ld,%ld failed: %m", 
	       shadow_path, uid, gid);
	return (FALSE);
    }
    return (TRUE);

  err:
    close(fd);
    return (FALSE);
}

static boolean_t
S_add_afppath_option(struct in_addr servip, id options, u_char * vol, 
		     u_char * dir, u_char * file, int tag)
{
    u_char		buf[255];
    int			len;
    u_char		path[PATH_MAX];
    u_char		sharepoint[PATH_MAX];

    sprintf(sharepoint, "%s%s", vol, S_sharepoint_suffix);
    if (dir && *dir)
	sprintf(path, "%s/", dir);
    else
	path[0] = '\0';
    strcat(path, file);
	
    len = sizeof(buf);
    if ([macNCOptions encodeAFPPath
	 :servip
	 :AFP_PORT_NUMBER 
	 :sharepoint
	 :AFP_DIRID_NULL
	 :AFP_PATHTYPE_LONG
	 :path
	 :'/'
         Into:(void *)buf 
         Length:&len 
         ErrorString:[options errString]] == FALSE) {
	syslog(LOG_INFO, "macNC: couldn't encode %s:%s, %s", vol, path,
	       [options errString]);
	return (FALSE);
    }
    if ([options addOption:tag Length:len Data:buf] == FALSE) {
	syslog(LOG_INFO, "macNC: couldn't add option %d failed: %s", tag,
	       [options errString]);
	return (FALSE);
    }
    return (TRUE);
}


/*
 * Function: S_stat_path_vol_file
 *
 * Purpose:
 *   Return the stat structure for the given volume/dir/file.
 */
static __inline__ int
S_stat_path_vol_file(u_char * path, u_char * vol, u_char * dir, u_char * file,
		     struct stat * sb_p)
{
    S_get_volpath(path, vol, dir, file);
    return (stat(path, sb_p));
}


static __inline__ boolean_t
S_stat_shared(u_char * shared_path, struct stat * sb_p)
{
    S_get_volpath(shared_path, S_shared_image_volume, S_image_dir,
		  S_shared_image_name);
    if (stat(shared_path, sb_p) != 0)
	return (FALSE);
    return (TRUE);
}

static __inline__ boolean_t
S_stat_private(u_char * private_path, struct stat * sb_p)
{
    S_get_volpath(private_path, S_private_image_volume, S_image_dir,
		  S_private_image_name);
    if (stat(private_path, sb_p) != 0)
	return (FALSE);
    return (TRUE);
}

/* 
 * Function: S_add_image_options
 * 
 * Purpose:
 *   Create/initialize image for client, format the paths into the
 *   response options.
 */
static boolean_t
S_add_image_options(uid_t uid, gid_t gid, struct in_addr servip, id options, 
		    int host_number, u_char * afp_hostname)
{
    int			def_vol_index;
    int			i;
    u_char		nc_images_dir[PATH_MAX];
    u_char *		nc_volume;
    u_char		path[PATH_MAX];
    struct stat		statb;
    int			vol_index;

    sprintf(nc_images_dir, "%s/%s", S_client_image_dir, afp_hostname);

    /* attempt to round-robin images across multiple volumes */
    def_vol_index = (host_number - 1) % S_volumes.ninl_len;

    /* check all volumes for a client image directory starting at default */
    nc_volume = NULL;
    for (i = 0, vol_index = def_vol_index; i < S_volumes.ninl_len; i++) {
	if (S_stat_path_vol_file(path, S_volumes.ninl_val[vol_index], 
				 nc_images_dir, NULL, &statb) == 0) {
	    nc_volume = S_volumes.ninl_val[vol_index]; /* found it */
	    break;
	}
	vol_index = (vol_index + 1) % S_volumes.ninl_len;
    }

    /* if the client has its own private copy of the image file, use it */
    if (nc_volume != NULL
	&& S_stat_path_vol_file(path, nc_volume, nc_images_dir, 
				S_shared_image_name, &statb) == 0) {
	if (S_use_aufs) {
	    if (statb.st_uid != uid || statb.st_gid != gid) {
		chown(path, uid, gid); /* fix up the user/group */
	    }
	    (void)S_make_aufs_finder_info(path);
	}
	else if (S_set_uid_gid(path, uid, gid)) {
	    syslog(LOG_INFO, "macNC: couldn't set permissions on path %s: %m",
		   path);
	    return (FALSE);
	}
#ifdef ppc
	else
	    chflags(path, 0); /* make shared image writable */
#endif ppc
	if (S_add_afppath_option(servip, options, nc_volume, nc_images_dir,
				 S_shared_image_name,
				 macNCtag_shared_system_file_e) == FALSE) {
	    return (FALSE);
	}
	/* does the client have its own Private image? */
	if (S_stat_path_vol_file(path, nc_volume, nc_images_dir,
				 S_private_image_name, &statb) == 0) {
	    /*
	     * We use macNCtag_page_file_e instead of 
	     * macNCtag_private_system_file_e as you would expect.
	     * The reason is that the client ROM software assumes
	     * that the private_system_file is read-only. It also
	     * assumes that page_file is read-write.  Since we don't
	     * use page_file for anything else, we use that instead.
	     * This is a hack/workaround.
	     */
	    if (S_add_afppath_option(servip, options, nc_volume, 
				     nc_images_dir, S_private_image_name,
				     macNCtag_page_file_e) == FALSE){
		return (FALSE);
	    }
	    if (S_use_aufs) {
		if (statb.st_uid != uid || statb.st_gid != gid) {
		    chown(path, uid, gid); /* fix up the user/group */
		}
		(void)S_make_aufs_finder_info(path);
	    }
	    else if (S_set_uid_gid(path, uid, gid)) {
		syslog(LOG_INFO, 
		       "macNC: couldn't set permissions on path %s: %m", path);
		return (FALSE);
	    }
#ifdef ppc
	    else
		chflags(path, 0); /* make private image writable */
#endif ppc
	}
    }
    else { /* client gets shadow file(s) */
	u_char		private_path[PATH_MAX];
	struct stat	sb_shared;
	struct stat	sb_private;
	boolean_t 	shadow_private = FALSE;
	u_char 		shared_path[PATH_MAX];

	/* make sure that the shared system image exists */
	if (S_stat_shared(shared_path, &sb_shared) == FALSE) {
	    syslog(LOG_INFO, "macNC: '%s' does not exist", shared_path);
	    return (FALSE);
	}
	if (nc_volume == NULL) {
	    unsigned long long	needspace;
	    struct statfs 	fsb;
	    static boolean_t	warned = FALSE;

	    needspace = sb_shared.st_size; /* space for the shared shadow */
	    if (S_shadow_both && S_stat_private(private_path, &sb_private))
		needspace += sb_private.st_size; /* shadow private as well */

	    if (debug)
		printf("need %qu bytes\n", needspace);
	    for (i = 0, vol_index = def_vol_index;
		 i < S_volumes.ninl_len; i++) {
		u_char * vol = S_volumes.ninl_val[vol_index];

		S_get_volpath(path, vol, NULL, NULL);
		if (statfs(path, &fsb) != 0)
		    syslog(LOG_INFO, "macNC: statfs on '%s' failed %m", path);
		else {
		    unsigned long long	freespace;

		    freespace = ((unsigned long long)fsb.f_bavail) 
			* ((unsigned long long)fsb.f_bsize);
		    if (debug)
			printf("%s %lu x %lu = %qu bytes\n", vol,
			       fsb.f_bavail, fsb.f_bsize, freespace);
#define SLOP_SPACE_BYTES	(20 * 1024 * 1024)

		    /* make sure there's enough space left on the volume */
		    if (freespace >= (needspace + SLOP_SPACE_BYTES)) {
			if (debug)
			    printf("selected volume %s\n", vol);
			nc_volume = vol;
			break;
		    }
		}
		vol_index = (vol_index + 1) % S_volumes.ninl_len;
	    }
	    if (nc_volume == NULL) {
		if (warned == FALSE)
		    syslog(LOG_INFO, "macNC: can't create client image: "
			   "OUT OF DISK SPACE");
		warned = TRUE; /* don't keep complaining */
		return (FALSE);
	    }
	    if (S_create_volume_dir(nc_volume, nc_images_dir) == FALSE)
		return (FALSE);
	    warned = FALSE;
	}
	if (S_use_aufs)
	    (void)S_make_aufs_finder_info(shared_path);
#ifdef ppc
	else 
	    chflags(shared_path, UF_IMMUTABLE); /* lock the share image file */

#endif ppc

	/* add the shared system image option */
	if (S_add_afppath_option(servip, options, S_shared_image_volume,
				 S_image_dir, S_shared_image_name, 
				 macNCtag_shared_system_file_e) == FALSE)
	    return (FALSE);

	/* check whether the private system image exists */
	if (S_stat_private(private_path, &sb_private)) {
	    if (S_shadow_both)
		shadow_private = TRUE;
	    if (S_add_afppath_option(servip, options, S_private_image_volume,
				     S_image_dir, S_private_image_name, 
				     macNCtag_private_system_file_e) == FALSE)
		return (FALSE);
	    if (S_use_aufs)
		(void)S_make_aufs_finder_info(private_path);
#ifdef ppc
	    else 
		chflags(private_path, UF_IMMUTABLE); /* lock the private image file */
#endif ppc
	}
	
	{ /* add the shadow file options */
	    u_char shadow_name[PATH_MAX];
	    u_char shadow_path[PATH_MAX];
	    
	    /* add the shared shadow file */
	    sprintf(shadow_name, "%s%s", S_shared_image_name,
		    S_shadow_suffix);
	    if (S_add_afppath_option(servip, options, nc_volume, 
				     nc_images_dir, shadow_name,
				     macNCtag_shared_system_shadow_file_e) 
		== FALSE)
		return (FALSE);
	    /* create the shadow */
	    S_get_volpath(shadow_path, nc_volume, nc_images_dir, shadow_name);
	    if (S_create_shadow_file(shadow_path, shared_path, uid, gid)
		== FALSE) {
		syslog(LOG_INFO, "macNC: couldn't make shadow %s of %s",
		       shadow_path, shared_path);
		return (FALSE);
	    }
	    if (shadow_private == TRUE) {
		/* add the private shadow file */
		sprintf(shadow_name, "%s%s", S_private_image_name,
			S_shadow_suffix);
		if (S_add_afppath_option(servip, options, nc_volume, 
					 nc_images_dir, shadow_name,
					 macNCtag_private_system_shadow_file_e)
		    == FALSE)
		    return (FALSE);
		/* create the shadow */
		S_get_volpath(shadow_path, nc_volume, nc_images_dir, 
			      shadow_name);
		if (S_create_shadow_file(shadow_path, private_path, uid, gid) 
		    == FALSE) {
		    syslog(LOG_INFO, "macNC: couldn't make shadow %s of %s",
			   shadow_path, private_path);
		    return (FALSE);
		}
	    }
	}
    }
    return (TRUE);
}

/* 
 * Function: NC_request
 *
 * Purpose:
 *   Handle mac NC bootp request.
 */
boolean_t
NC_request(interface_t * intface, u_char * rxpkt, int n, id options,
	   struct timeval * tv_p)
{
    u_char *		afp_hostname = NULL;
    u_char *		bootfile = NULL;
    u_int		client_version;
    struct ether_addr * ea_p;
    u_char *		hostname = NULL;
    int			host_number;
    struct hosts * 	hp;
    struct in_addr 	ip_addr = { 0 };
    boolean_t		lookup_error = FALSE;			
    u_char *		macOS_machine = NULL;
    unsigned char   	passwd[AFP_PASSWORD_LEN + 1];
    boolean_t		reply_sent = FALSE;
    struct dhcp *	rq = (struct dhcp *)rxpkt;
    struct in_addr	server_ip;
    struct in_addr	subnetaddr;
    struct in_addr	subnetmask;

    /* is this a Mac NC? */
    if (S_get_client_info(rq, n, options, &client_version) == FALSE)
	return (FALSE); /* nope */


    /* are we ignoring the client? */
    hp = hostbyaddr(S_ignore_hosts, rq->dhp_htype, rq->dhp_chaddr,
		    rq->dhp_hlen);
    if (hp) {
	if ((tv_p->tv_sec - hp->tv.tv_sec) <= MACNC_IGNORE_TIME) {
	    return (TRUE); /* yes, we're still ignoring it */
	    /* return TRUE so that regular bootp will ignore this host too */
	}
	hostfree(&S_ignore_hosts, hp);
	hp = NULL;
    }

    ea_p = (struct ether_addr *)rq->dhp_chaddr;

    /* if gateway is set, allocate host from that subnet */
    if (rq->dhp_giaddr.s_addr != 0) 
	server_ip = rq->dhp_giaddr;
    else
	server_ip = intface->addr;

    if (subnetAddressAndMask(rq->dhp_giaddr, intface, &subnetaddr, &subnetmask)
	== FALSE)
	return (FALSE);
    /* check if we have a host entry for this machine yet */
    if (S_lookup_host(rq->dhp_htype, rq->dhp_chaddr, rq->dhp_hlen, 
		      subnetaddr, subnetmask, 
		      &ip_addr, &hostname, &afp_hostname,
		      &macOS_machine, &bootfile, &host_number,
		      &lookup_error)) {
	timestamp_syslog("host known");
	if (!quiet)
	    syslog(LOG_INFO,"macNC: BOOTP request [%s]: %s ip %s h/w %s", 
		   intface->name, hostname, inet_ntoa(ip_addr), 
		   ether_ntoa(ea_p));
    }
    else if (lookup_error) {
	u_char buf[256];

	sprintf(buf, "macNC: unable to reply to h/w %s", ether_ntoa(ea_p));
	timestamp_syslog(buf);
	return (FALSE);
    }
    else { /* create a new host entry */
	timestamp_syslog("host unknown");
	if (!quiet)
	    syslog(LOG_INFO,"macNC: BOOTP request [%s]: h/w %s", intface->name,
		   ether_ntoa(ea_p));
	if (S_new_host(subnetaddr, 
		       rq->dhp_htype, rq->dhp_chaddr, rq->dhp_hlen, 
		       &ip_addr, &hostname, &afp_hostname, &macOS_machine, 
		       &bootfile, &host_number) == FALSE) {
	    goto no_reply;
	}
    }

    if (host_number < 1) {
	syslog(LOG_INFO, "macNC: hostnumber %d is invalid - internal error", 
	       host_number);
	goto no_reply;
    }

    /* set the afp password */
    if (S_use_aufs || S_default_password)
	strcpy(passwd, AUFS_DEFAULT_PASSWORD);
    else
	/* set the user's new password to a new random number */
	sprintf(passwd, "%lx", random());

    if (S_afp_set_password(afp_hostname, passwd) == FALSE) {
	if (!quiet)
	    syslog(LOG_INFO, "macNC: unable to set afp machine password");
	goto no_reply;
    }
    timestamp_syslog("new password assigned");

    { /* form a reply packet */
	u_char *	afp_user;
	static u_char   dhcp_reply[sizeof(struct dhcp)+DHCP_MIN_OPTIONS_SIZE];
	struct passwd *	ent;
	id		options = nil;
	struct dhcp * 	reply = (struct dhcp *)dhcp_reply;
	u_char *	username;
	u_long 		v = MACNC_SERVER_VERSION;

	options = [[macNCOptions alloc] 
		    initWithBuffer:reply->dhp_options + sizeof(rfc_magic) 
		    Size:DHCP_MIN_OPTIONS_SIZE - sizeof(rfc_magic)];
	if (options == nil) {
	    if (!quiet)
		syslog(LOG_INFO, "macNC: macNCOptions alloc/init failed");
	    goto err;
	}

	bcopy(rq, reply, sizeof(struct dhcp));
	reply->dhp_op = BOOTREPLY;
	reply->dhp_yiaddr = ip_addr;
	bcopy(rfc_magic, reply->dhp_options, sizeof(rfc_magic));

	/* add the bootfile */
	if (bootp_add_bootfile(rq->dhp_file, hostname, S_default_bootdir,
			       bootfile, S_default_bootfile, 
			       NULL, reply->dhp_file) == FALSE) {
	    goto err;
	}
	/* add the usual extensions/options */
	add_subnet_options(ip_addr, intface, options, S_tags, S_tags_num);

	/* server version tag */
	if ([options addOption:macNCtag_server_version_e 
	     Length:sizeof(v) Data:&v] == FALSE)
	    goto err;

	/* add the afp user name option */
	afp_user = afp_hostname;
	username = hostname;
	if (S_use_aufs == TRUE) {
	    username = afp_user = AUFS_DEFAULT_USER;
	}
	if ([options addOption:macNCtag_user_name_e
	     FromString:afp_user] == FALSE) {
	    if (!quiet)
		syslog(LOG_INFO, 
		       "macNC: failed add user name %s: '%s'", afp_user,
		       [options errString]);
	    goto err;
	}

	/* add the Mac OS machine name option */
	if ([options addOption:macNCtag_MacOS_machine_name_e 
	     FromString:macOS_machine] == FALSE) {
	    if (!quiet)
		syslog(LOG_INFO,
		       "macNC: failed add MacOS machine name %s: '%s'",
		       macOS_machine, [options errString]);
	    goto err;
	}

	/* add the afp user password option */
	if ([options addOption:macNCtag_password_e FromString:passwd]
	    == FALSE) {
	    if (!quiet)
		syslog(LOG_INFO, "macNC: failed add password: '%s'",
		       [options errString]);
	    goto err;
	}

	/* get the user/group id for the AFP user */
	ent = getpwnam(username);
	if (ent == NULL) {
	    if (!quiet)
		syslog(LOG_INFO, 
		       "macNC: getpwnam on user %s failed", username);
	    goto err;
	}
	/* add the client image information, create its image directory */
	if (S_add_image_options(ent->pw_uid, ent->pw_gid, server_ip, 
				options, host_number, afp_hostname) 
	    == FALSE) {
	    if (!quiet)
		syslog(LOG_INFO, "macNC: couldn't add image information");
	    goto err;
	}
	/* mark the end of the options */
	if ([options addOption:dhcptag_end_e Length:0 Data:0] == FALSE)
	    goto err;

	/* make sure the options parse OK */
	if (debug && [options parse] == FALSE) {
	    syslog(LOG_INFO, "macNC: couldn't parse options in reply");
	    goto err;
	}

	if (debug) {
#define MACNC_MAX_SERVICE_TIME	4 /* seconds */
	    struct timeval 	result;
	    struct timeval 	tv;
	    gettimeofday(&tv, 0);
	    timeval_subtract(&tv, tv_p, &result);

	    if (result.tv_sec >= MACNC_MAX_SERVICE_TIME) {
		if (verbose)
		    syslog(LOG_INFO, 
			   "macNC: TOO LONG: %d.%06d to generate reply",
			   result.tv_sec, result.tv_usec);
	    }
	}
	{
	    int size = sizeof(struct dhcp) + sizeof(rfc_magic) 
		+ [options bufferUsed];

	    if (sendreply(intface, (struct bootp *)reply, size, 0)) {
		if (!quiet)
		    syslog(LOG_INFO, "macNC: reply sent %s %s pktsize %d",
			   hostname, inet_ntoa(ip_addr), size);
		reply_sent = TRUE;
	    }
	}
      err:
	if (options != nil)
	    [options free];
    }
  no_reply:
    if (reply_sent == FALSE) { 
	/* we didn't reply - ignore this host for awhile */
	struct hosts * hp;
	hp = hostadd(&S_ignore_hosts, tv_p, rq->dhp_htype, 
		     rq->dhp_chaddr, rq->dhp_hlen, NULL, NULL, NULL);
	if (verbose && hp) {
	    syslog(LOG_INFO, 
		   "macNC: ignoring the following host for %d seconds",
		   MACNC_IGNORE_TIME);
	    hostprint(hp);
	}
    }
    if (afp_hostname)
	free(afp_hostname);
    if (bootfile)
	free(bootfile);
    if (hostname)
	free(hostname);
    if (macOS_machine)
	free(macOS_machine);
    return (TRUE);
}
