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
 * nigrep: regular expression NetInfo search
 * Written by Marc Majka
 *
 * Copyright 1994, NeXT Computer Inc.
 */
#include <stdio.h>
#include <objc/objc.h>
#include <netinfo/ni.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <sys/types.h>
#include <errno.h>
#include <ctype.h>
#include <c.h>
#include <strings.h>
#include <pwd.h>
#include <unistd.h>
#include <regex.h>
#include "nilib2.h"

/* Reflect return value in exit status... */
/*   0     == success
 * 101-198 == ni_status (n <  NI_FAILED)
 *     199 == ni_status (n == NI_FAILED)
 * 200     == ni_connect() error
 * 201-2xx == ni_parse_status (+ 100)
 */
void _EXIT_(int err)
{
	if (err == 0)
		/* if no error */
		exit(0);
	else if (err < NI_FAILED)
		/* if NetInfo error */
		exit(err + 100);
	else if (err == NI_FAILED)
		/* if NetInfo error && ni_status==NI_FAILED */
		exit(199);
	else if (err == NI_FAILED+1)
		/* if error returned by ni_connect() */
		exit(200);
	else
		/* if error parsing NetInfo tag */
		exit(err + 200);
}

void errexit(char *s, ni_status status)
{
	fprintf(stderr, "%s: %s\n", s, ni_error(status));
	_EXIT_(status);
}

void usage()
{
	fprintf(stderr,"usage: nigrep [-T timeout] exp [-t] domain [dir ...]\n");
	exit(1);
}

int main(int argc, char *argv[])
{
	int i, ep, firstdir, dp, timeout;
	void *dom;
	void grepdomain();
	regex_t cexp;
	BOOL bytag, timeoutset;
	char *slash, *myname;

	slash = rindex(argv[0], '/');
	if (slash == NULL) myname = argv[0];
	else myname = slash+1;

	if (argc < 3) usage();

	timeoutset = NO;
	bytag = NO;
	ep = 0;
	dp = 0;
	firstdir = 0;

	for (i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "-t")) {
			if (bytag) usage();
			bytag = YES;
			i++;
			if (i >= argc) usage();
			if (dp != 0) usage();
			dp = i;
		}
		else if (!strcmp(argv[i], "-T")) {
			if (timeoutset) usage();
			timeoutset = YES;
			i++;
			if (i >= argc) usage();
			if (sscanf(argv[i], "%d", &timeout) < 1) usage();
			if (timeout < 0) {
				fprintf(stderr, "can't use negative timeout value.\n");
				exit(1);
			}
		}
		else if (ep == 0) ep = i;
		else if (dp == 0) dp = i;
		else if (firstdir == 0) firstdir = i;
	}

	if (!timeoutset) timeout = 30;

	if (ep == 0) usage();
	i = regcomp(&cexp, argv[ep], REG_EXTENDED);
	if (i != 0)
	{
		fprintf(stderr, "Bad expression: %s\n", argv[ep]);
		usage();
	}

	if (dp == 0) usage();
	if (do_open(myname, argv[dp], &dom, bytag, timeout, NULL, NULL)) usage();

	if (firstdir == 0) {
		grepdomain(&cexp, "/", dom);
	}
	else {
		for (i = firstdir; i < argc; i++) 
			grepdomain(&cexp, argv[i], dom);
	}

	ni_free(dom);

	exit(0);
}

void grepdomain(regex_t *cexp, char *dname, void *dom)
{
	ni_id dir;
	ni_status status;
	void greprecursive();

	/* open directory */
	status = ni_pathsearch(dom, &dir, dname);
	if (status != NI_OK) errexit("ni_pathsearch", status);

	greprecursive(cexp, dname, dom, &dir);
}

void greprecursive(regex_t *cexp, char *dname, void *dom, ni_id *dir)
{
	int i;
	ni_entrylist el;
	ni_status status;
	void grepnidir();
	ni_id d;
	char newname[8192];

	grepnidir(cexp, dname, dom, dir);

	/* get subdirectory list */
	status = ni_list(dom, dir, "name", &el);
	if (status != NI_OK) errexit("ni_list", status);

	for (i = 0; i < el.ni_entrylist_len; i++) {
		if (el.ni_entrylist_val[i].names == NULL) {
			/* subdir has no name */
			if (!strcmp(dname, "/"))
				sprintf(newname, "/dir: %lu", el.ni_entrylist_val[i].id);
			else
				sprintf(newname, "%s/dir: %lu", dname, el.ni_entrylist_val[i].id);
		}

		else if (el.ni_entrylist_val[i].names->ni_namelist_val[0] == NULL) {
			/* no value for name */
			if (!strcmp(dname, "/"))
				sprintf(newname, "/dir: %lu", el.ni_entrylist_val[i].id);
			else
				sprintf(newname, "%s/dir: %lu", dname, el.ni_entrylist_val[i].id);
		}

		else {
			if (!strcmp(dname, "/"))
				sprintf(newname, "/%s", el.ni_entrylist_val[i].names->ni_namelist_val[0]);
			else 
				sprintf(newname, "%s/%s", dname, el.ni_entrylist_val[i].names->ni_namelist_val[0]);
		}

		d.nii_object = el.ni_entrylist_val[i].id;
		greprecursive(cexp, newname, dom, &d);
	}
}

void grepnidir(regex_t *cexp, char *dname, void *dom, ni_id *dir)
{
	int i, j;
	int found;
	ni_status status;
	ni_proplist pl;
	ni_namelist *nl;

	/* get  properties */
	NI_INIT(&pl);
	status = ni_read(dom, dir, &pl);
	if (status) errexit("ni_read", status);

	for (i = 0; i < pl.ni_proplist_len; i++)
	{
		found = 0;

		/* look for string in property key */
		if (regexec(cexp, pl.ni_proplist_val[i].nip_name, 0, NULL, 0) == 0)
			found = 1;

		/* look for string in property values */
		nl = &(pl.ni_proplist_val[i].nip_val);
		for (j = 0; j < nl->ni_namelist_len && found == 0; j++)
		{
			if (regexec(cexp, nl->ni_namelist_val[j], 0, NULL, 0) == 0)
				found = 1;
		}

		if (found == 1)
		{
			printf("%lu %s:  %s",
				dir->nii_object, dname, pl.ni_proplist_val[i].nip_name);
				
			for (j = 0; j < nl->ni_namelist_len; j++)
				printf(" %s", nl->ni_namelist_val[j]);
			printf("\n");
		}
	}

	ni_proplist_free(&pl);
}
