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
 * netinfo.c - Routines for dealing with the NetInfo database.
 *
 **********************************************************************
 * HISTORY
 * 10-Jun-89  Peter King
 *	Created.
 * 23-Feb-98  Dieter Siegmund (dieter@apple.com)
 *      Removed all of the promiscous-related stuff,
 *	left with routines to do host creation/lookup.
 **********************************************************************
 */

/*
 * Include Files
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
#import "host_identifier.h"
#import	"netinfo.h"

/*
 * External Routines
 */
char *  	ether_ntoa(struct ether_addr *e);


/*
 * Exported routines
 */

/*
 * Routine: ni_createhost
 * Function:
 *	Create a new host entry in the specified domain.
 * Returns:
 *	0	- Success
 *	-1	- Failure
 */
int
ni_createhost(void * domain, ni_proplist * custom_pl_p, u_char * hostname,
	      u_char hwtype, void * hwaddr, int hwlen,
	      struct in_addr inaddr, u_char * bootfile,
	      boolean_t use_en_address)
{
	ni_id		id = {0};
	ni_id		hostid = {0};
	ni_proplist	proplist;
	ni_status	status;
	int		hasupper = 0;
	char		*cp;
	char		lowerhost[128];

	/* Get the machines directory */
	if ((status = ni_pathsearch(domain, &id, NIDIR_MACHINES)) != NI_OK) {
		syslog(LOG_ERR,
		       "NetInfo error finding /machines directory: %s",
		       ni_error(status));
		return (-1);
	}
	
	/* Build a property list for this new entry */
	NI_INIT(&proplist);
	strncpy(lowerhost, hostname, sizeof (lowerhost) - 1);
	for (cp = lowerhost; *cp; cp++) {
		if (isupper(*cp)) {
			hasupper++;
			*cp = tolower(*cp);
		}
	}
	ni_proplist_addprop(&proplist, NIPROP_NAME,
			    (ni_name)lowerhost);
	ni_proplist_addprop(&proplist, NIPROP_IPADDR,
			    (ni_name) inet_ntoa(inaddr));
	if (use_en_address  && hwtype == ARPHRD_ETHER) { /* backwards compat */
	    ni_proplist_addprop(&proplist, NIPROP_ENADDR, (ni_name) 
				ether_ntoa((struct ether_addr *)hwaddr));
	}
	else {
	    void * idstr = identifierToString(hwtype, hwaddr, hwlen);
	    if (idstr == NULL) {
		syslog(LOG_ERR, "identifierToString failed");
		return (-1);
	    }
	    ni_proplist_addprop(&proplist, NIPROP_IDENTIFIER, (ni_name)idstr);
	    free(idstr);
	}
	ni_proplist_addprop(&proplist, NIPROP_BOOTFILE, (ni_name) bootfile);
	/* append the "custom" properties */
	if (custom_pl_p != NULL)
	    ni_proplist_append(&proplist, custom_pl_p);

	/* And create the entry */
	if ((status = ni_create(domain, &id, proplist, &hostid,
				NI_INDEX_NULL)) != NI_OK) {
		syslog(LOG_ERR, "NetInfo error creating host entry: %s",
		       ni_error(status));
		ni_proplist_free(&proplist);
		return (-1);
	}

	/* success */
	ni_proplist_free(&proplist);
	return (0);
}

/*
 * Function: ni_lookuphost
 * Purpose:
 *   Return a handle to the directory containing the specified machine.
 * Returns:
 *	TRUE	- Success
 *	FALSE	- Failure
 */
boolean_t
ni_lookuphost(void * domain, u_char * host, ni_id * dir_p)
{
    ni_status		status;
    u_char		dirname[128];
    
    strcpy(dirname, NIDIR_MACHINES);
    strcat(dirname, "/");
    strcat(dirname, host);
    if ((status = ni_pathsearch(domain, dir_p, dirname)) != NI_OK) {
	return (FALSE);
    }
    return (TRUE);
}

static __inline__ boolean_t
indexofprop(void * domain, ni_id * dir_p, u_char * propname, ni_index * i)
{
    ni_namelist			nl;
    ni_status			status;

    *i = NI_INDEX_NULL;

    if ((status = ni_listprops(domain, dir_p, &nl)) != NI_OK) {
	return (FALSE);
    }
    *i = ni_namelist_match(nl, propname);
    ni_namelist_free(&nl);
    return (TRUE);
}

boolean_t 
ni_setpropbyname(void * domain, ni_id * dir_p, u_char * propname, 
		 ni_namelist nl)
{
    int				j;
    ni_status			status;
    ni_index			which;

    j = 0;
    do {
	if (indexofprop(domain, dir_p, propname, &which) == FALSE) {
	    syslog(LOG_ERR, "Netinfo failure searching for prop %s",
		   propname);
	    return (FALSE);
	}
	if (which == NI_INDEX_NULL) { 
	    /* add it */
	    ni_property	prop;
	    
	    NI_INIT(&prop);
	    prop.nip_name = ni_name_dup(propname);
	    if ((status = ni_createprop(domain, dir_p, prop, 
					NI_INDEX_NULL))	!= NI_OK) {
		syslog(LOG_ERR, "NetInfo failure creating %s property: %s",
		       propname, ni_error(status));
		ni_prop_free(&prop);
		return (FALSE);
	    }
	    ni_prop_free(&prop);
	}
	j++;
    } while (which == NI_INDEX_NULL && j != 2);

    if (which == NI_INDEX_NULL)
	return (FALSE);

    if ((status = ni_writeprop(domain, dir_p, which, nl)) != NI_OK) {
	syslog(LOG_ERR, "NetInfo failure writing %s property: %s",
	       propname, ni_error(status));
	return (FALSE);
    }
    return (TRUE);
}

#if 0
/*
 * Function: ni_hostbyether
 *
 * Purpose:
 *   Get the host information we're interested in for the given host,
 *   and return the entire proplist to the caller so they can get
 *   anything else they might need.
 * Returns:
 *   TRUE: if the host exists and all properties exist and are valid
 *
 *   FALSE: host does not exist or there were errors in the properties
 *   *err will be set to FALSE if the host does not exist
 *   *err will be set to TRUE if there were errors in the properties
 */
boolean_t
ni_hostbyether(void * domain, ni_proplist * pl_p, struct ether_addr * ea_p, 
	       u_char * host_p, struct in_addr * iaddr_p, u_char * bootfile_p,
	       boolean_t * err)
{
    ni_id		dir;
    u_char		dirname[128];
    boolean_t		error = FALSE;
    ni_namelist *	nl_p;
    ni_status		status;
    
    strcpy(dirname, NIDIR_MACHINES);
    strcat(dirname, "/");
    strcat(dirname, NIPROP_ENADDR);
    strcat(dirname, "=");
    strcat(dirname, ether_ntoa(ea_p));
    *err = FALSE;
    if (ni_pathsearch(domain, &dir, dirname) != NI_OK) {
	return (FALSE);
    }
    status = ni_read(domain, &dir, pl_p);
    if (status != NI_OK)
	return (FALSE);

    /* get the ip address */
    nl_p = ni_nlforprop(pl_p, NIPROP_IPADDR);
    if (nl_p == NULL 
	|| nl_p->ninl_len == 0
	|| (iaddr_p->s_addr = inet_addr(nl_p->ninl_val[0])) == -1) {
	syslog(LOG_ERR, "%s bad/missing", NIPROP_IPADDR);
	error = TRUE;
    }

    /* get the host name */
    nl_p = ni_nlforprop(pl_p, NIPROP_NAME);
    if (nl_p == NULL 
	|| nl_p->ninl_len == 0) {
	error = TRUE;
	syslog(LOG_ERR, "%s bad/missing", NIPROP_NAME);
    }
    else 
	strcpy(host_p, nl_p->ninl_val[0]);

    /* get the boot file */
    nl_p = ni_nlforprop(pl_p, NIPROP_BOOTFILE);
    if (nl_p == 0 
	|| nl_p->ninl_len == 0) {
	syslog(LOG_ERR, "%s bad/missing", NIPROP_BOOTFILE);
	error = TRUE;
    }
    else
	strcpy(bootfile_p, nl_p->ninl_val[0]);

    if (error) {
	*err = error;
	syslog(LOG_INFO, "local host entry '%s' invalid",
	       dirname);
	return (FALSE);
    }
    return (TRUE);
}

#endif 0

boolean_t
ni_sethostprop(void * domain, u_char * hostname, u_char * propname, 
	       u_char * propval)
{
    ni_namelist 	nl;
    ni_id 		dir_id;
	
    if (ni_lookuphost(domain, hostname, &dir_id) == FALSE) {
	/* should not happen */
	syslog(LOG_ERR, "'%s' has no Netinfo entry - internal error",  
	       hostname);
	return (FALSE);
    }
    NI_INIT(&nl);
    ni_namelist_insert(&nl, propval, NI_INDEX_NULL);
    if (ni_setpropbyname(domain, &dir_id, propname, nl) == FALSE) {
	syslog(LOG_ERR, "host %s set property %s to %s failed", 
	       hostname, propname, propval);
	ni_namelist_free(&nl);
	return (FALSE);
    }
    ni_namelist_free(&nl);
    return (TRUE);
}

void
ni_proplist_dump(ni_proplist * pl)
{
    int i, j;

    for (i = 0; i < pl->nipl_len; i++) {
	ni_property * prop = &(pl->nipl_val[i]);
	ni_namelist * nl_p = &prop->nip_val;
	if (nl_p->ninl_len == 0) {
	    printf("\"%s\"\n", prop->nip_name);
	}
	else {
	    printf("\"%s\" = ", prop->nip_name);
	    for (j = 0; j < nl_p->ninl_len; j++)
		printf("%s\"%s\"", (j == 0) ? "" : ", ", nl_p->ninl_val[j]);
	    printf("\n");
	}
    }
}
