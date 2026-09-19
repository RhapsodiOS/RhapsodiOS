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
 * canonicalize.m
 * - make sure netinfo host entries have valid en_address/ip_address properties
 * - eg. turns "00:A0:02:EE:12:AB" into "0:a0:2:ee:12:ab"
 * - is careful to leave everything else intact
 *
 * options:
 * -u user
 * -p password
 * -n don't write, just inform what would have been fixed
 *
 * The default user it uses is macmod, password "".
 */

/*
 * Modification History
 * Dieter Siegmund (dieter@apple.com)	Thu Dec 17 16:03:30 PST 1998
 * - created
 */
#import <string.h>
#import <unistd.h>
#import <stdlib.h>
#import <stdio.h>
#import <sys/stat.h>
#import <sys/socket.h>
#import <sys/ioctl.h>
#import <sys/file.h>
#import <sys/time.h>
#import	<mach/boolean.h>
#import <netinet/in.h>
#import <net/if.h>
#import <netinet/in_systm.h>
#import <netinet/ip.h>
#import <netinet/udp.h>
#import <netinet/bootp.h>
#import <netinet/if_ether.h>
#import <arpa/inet.h>
#import <netinfo/ni.h>
#import <netinfo/ni_util.h>
#import "NIDomain.h"

char * user = "macmod";
char * passwd = "";

extern char *  			ether_ntoa(struct ether_addr *e);
extern struct ether_addr *	ether_aton(char *);

/*
 * Constants
 */

/* Important directories */
#define	NIDIR_MACHINES	"/machines"

/* Important properties */
#define	NIPROP_NAME		"name"
#define NIPROP_IDENTIFIER	"identifier"
#define	NIPROP_ENADDR		"en_address"
#define	NIPROP_IPADDR		"ip_address"
#define	NIPROP_BOOTFILE		"bootfile"


char *	progname;

void
die(char * m)
{
    fprintf(stderr, "%s: %s\n", progname, m);
    exit(1);
}


void
display_dir(id d, u_long di)
{
    ni_id 	dir;
    ni_index	name_i;
    ni_status 	status;
    ni_proplist	pl;

    dir.nii_object = di;
    status = ni_read([d handle], &dir, &pl);
    //ni_needwrite([d handle], TRUE);
    name_i = ni_proplist_match(pl, NIPROP_NAME, NULL);
    if (name_i != NI_INDEX_NULL) {
	ni_namelist * name_nl = &(pl.nipl_val[name_i].nip_val);
	if (name_nl->ninl_len > 0
	    && name_nl->ninl_val[0])
	    printf("%s\n", name_nl->ninl_val[0]);
	else
	    printf("dir: %ul\n", di);
    }
    else
	printf("dir: %ul\n", di);
    ni_proplist_free(&pl);
    return;
}

boolean_t
correct(void * handle, u_long di, boolean_t do_writes)
{
    boolean_t 		corrected = FALSE;
    int 		diffs = 0;
    ni_id		dir = {0, 0};
    int 		i;
    ni_namelist * 	nl_p;
    ni_property *	prop;
    ni_proplist		pl;
    ni_status 		status;
    int			where;

    dir.nii_object = di;
    if (do_writes)
	ni_needwrite(handle, TRUE);
    status = ni_read(handle, &dir, &pl);
    if (status != NI_OK) {
	fprintf(stderr, "couldn't read dir %ul: %s\n", di, ni_error(status));
	return (FALSE);
    }

    { /* print out which directory we're updating */
	ni_index		name_i;
	ni_namelist *	name_nl;
	name_i = ni_proplist_match(pl, NIPROP_NAME, NULL);
	if (name_i == NI_INDEX_NULL)
	    goto no_write;
	name_nl = &(pl.nipl_val[name_i].nip_val);
	if (name_nl->ninl_len > 0
	    && name_nl->ninl_val[0])
	    printf("correcting %s\n", name_nl->ninl_val[0]);
	else
	    printf("correcting dir: %ul\n", di);
    }

    /* correct en_address property */
    where = ni_proplist_match(pl, NIPROP_ENADDR, NULL);
    if (where == NI_INDEX_NULL)
	goto no_write;
    prop = pl.nipl_val + where;
    nl_p = &prop->nip_val;
    for (i = 0; i < nl_p->ninl_len; i++) {
	struct ether_addr * 	ea_p;
	char * 			eastr = NULL;
	ni_name 			val = nl_p->ninl_val[i];
	
	if (val == NULL)
	    continue;
	ea_p = ether_aton(val);
	if (ea_p == NULL) {
	    printf("Can't fix %s = '%s'\n", NIPROP_ENADDR, val);
	    continue;
	}
	eastr = ether_ntoa(ea_p);
	if (eastr == NULL)
	    continue;
	if (strcmp(eastr, val) == 0)
	    continue;
	diffs++;
	printf("Changing %s '%s' => '%s'\n", NIPROP_ENADDR, val, eastr);
	ni_namelist_delete(nl_p, i);
	val = ni_name_dup((const ni_name)eastr);
	ni_namelist_insert(nl_p, val, i);
    }

    /* correct ip_address property */
    where = ni_proplist_match(pl, NIPROP_IPADDR, NULL);
    if (where == NI_INDEX_NULL)
	goto no_ip;
    prop = pl.nipl_val + where;
    nl_p = &prop->nip_val;
    for (i = 0; i < nl_p->ninl_len; i++) {
	struct in_addr		iaddr;
	char * 			ipstr = NULL;
	ni_name 		val = nl_p->ninl_val[i];
	
	if (val == NULL)
	    continue;
	iaddr.s_addr = inet_addr(val);
	if (iaddr.s_addr == -1) {
	    printf("Can't fix %s = '%s'\n", NIPROP_IPADDR, val);
	    continue;
	}
	ipstr = inet_ntoa(iaddr);
	if (ipstr == NULL)
	    continue;
	if (strcmp(ipstr, val) == 0)
	    continue;
	diffs++;
	printf("Changing %s '%s' => '%s'\n", NIPROP_IPADDR, val, ipstr);
	ni_namelist_delete(nl_p, i);
	val = ni_name_dup((const ni_name)ipstr);
	ni_namelist_insert(nl_p, val, i);
    }
  no_ip:
    if (diffs == 0)
	goto no_write;
    if (!do_writes) {
	corrected = TRUE;
	goto no_write;
    }

    status = ni_write(handle, &dir, pl);
    if (status != NI_OK)
	fprintf(stderr, "couldn't write: %s\n", ni_error(status));
    else
	corrected = TRUE;

  no_write:
    ni_proplist_free(&pl);
    return (corrected);
}

void
canonicalize(char * domain, boolean_t do_writes)
{
    id 			d;
    ni_entrylist	el;
    ni_id		machines_dir;
    ni_status 		status;

    d = [[NIDomain alloc] initWithDomain:domain];
    if (d == nil)
	die("can't open domain");
    if (do_writes) {
	status = ni_setuser([d handle], user);
	if (status != NI_OK) {
	    fprintf(stderr, "ni_setuser %s failed: %s\n", user,
		    ni_error(status));
	    die("exiting");
	}
	status = ni_setpassword([d handle], passwd);
	if (status != NI_OK) {
	    fprintf(stderr, "ni_setpassword %s failed: %s\n", passwd,
		    ni_error(status));
	    die("exiting");
	}
    }
    status = ni_pathsearch([d handle], &machines_dir, NIDIR_MACHINES);
    if (status != NI_OK) {
	fprintf(stderr, "error locating %s directory %s: %s\n",
		NIDIR_MACHINES, domain, ni_error(status));
	exit(0);
    }
    NI_INIT(&el);
    status = ni_list([d handle], &machines_dir, NIPROP_ENADDR, &el);
    if (status != NI_OK) {
	fprintf(stderr, "no %s properties in subdirectories of %s\n",
		NIPROP_ENADDR, NIDIR_MACHINES);
	exit(0);
    }
    {
	int i;
	int corrected = 0;

	printf("%s: %d subdirectories\n", NIDIR_MACHINES, el.niel_len);
	for (i = 0; i < el.niel_len; i++) {
	    ni_entry * 	entry = el.niel_val + i;
	    boolean_t	needs_correction = FALSE;
	    int 	j;

	    if (entry->names == NULL)
		continue;
	    for (j = 0; j < entry->names->ninl_len; j++) {
		char * val = entry->names->ninl_val[j];
		if (val) {
		    struct ether_addr * ea_p = ether_aton(val);
		    char * 		eastr = NULL;

		    if (ea_p)
			eastr = ether_ntoa(ea_p);
		    if (eastr == NULL
			|| strcmp(val, eastr)) {
			needs_correction = TRUE;
			break;
		    }
		}
	    }
	    if (needs_correction) {
		if (correct([d handle], entry->id, do_writes)) {
		    corrected++;
		    printf("\n");
		}
	    }
	}
	if (corrected)
	    printf("corrected %d entr%s\n", corrected,
		   (corrected == 1) ? "y" : "ies");
	else
	    printf("no entries were corrected\n");
    }

    ni_entrylist_free(&el);
    return;
}

void
usage()
{
    printf("usage: %s [-u username] [-p password] domain_name\n", progname);
    exit(1);
}

int
main(int argc, char * argv[])
{
    int ch;
    boolean_t do_writes = TRUE;

    progname = argv[0];

    while ((ch = getopt(argc, argv, "nu:p:")) != EOF) {
	switch((char) ch) {
	  case 'n':
	    do_writes = FALSE;
	    break;
	  case 'u':
	    user = optarg;
	    break;
	  case 'p':
	    passwd = optarg;
	    break;
	  default:
	    usage();
	    break;
	}
    }
    if ((argc - optind) != 1)
	usage();

    canonicalize(argv[optind], do_writes);
    exit(0);
}
