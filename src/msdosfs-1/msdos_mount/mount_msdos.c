/*	$NetBSD: mount_msdos.c,v 1.18 1997/09/16 12:24:18 lukem Exp $	*/

/*
 * Copyright (c) 1994 Christopher G. Demetriou
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *    must display the following acknowledgement:
 *      This product includes software developed by Christopher G. Demetriou.
 * 4. The name of the author may not be used to endorse or promote products
 *    derived from this software without specific prior written permission
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#ifndef lint
static const char rcsid[] =
  "$FreeBSD$";
#endif /* not lint */

#include <sys/param.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include "msdosfs_mount.h"

#include <ctype.h>
#include <err.h>
#include <grp.h>
#include <locale.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define PROCESS_OPTIONS 0
#if PROCESS_OPTIONS
#include "mntopts.h"

static struct mntopt mopts[] = {
	MOPT_STDOPTS,
	MOPT_FORCE,
	MOPT_SYNC,
	MOPT_UPDATE,
	{ "shortnames", 0, MSDOSFSMNT_SHORTNAME, 1 },
	{ "longnames", 0, MSDOSFSMNT_LONGNAME, 1 },
	{ "nowin95", 0, MSDOSFSMNT_NOWIN95, 1 },
	{ NULL }
};
#endif

#define DEFAULT_ROOTUID	-2

static gid_t	a_gid __P((char *));
static uid_t	a_uid __P((char *));
static mode_t	a_mask __P((char *));
static void	usage __P((void));
static void     load_u2wtable __P((struct msdosfs_args *, char *));
static void     load_ultable __P((struct msdosfs_args *, char *));

int
main(argc, argv)
	int argc;
	char **argv;
{
	struct msdosfs_args args;
	struct stat sb;
	int c, mntflags, set_gid, set_uid, set_mask, set_dirmask;
	char *dev, *dir;
	char optstr[32];

	mntflags = set_gid = set_uid = set_mask = set_dirmask = 0;
	(void)memset(&args, '\0', sizeof(args));
	args.magic = MSDOSFS_ARGSMAGIC;

	/*
	 * Build getopt string: always support shortname/longname/nowin95
	 * and ownership masks; -o only if PROCESS_OPTIONS is enabled.
	 */
	strcpy(optstr, "sl9u:g:m:M:L:W:");
#if PROCESS_OPTIONS
	strcat(optstr, "o:");
#endif

	while ((c = getopt(argc, argv, optstr)) != EOF) {
		switch (c) {
		case 's':
			args.flags |= MSDOSFSMNT_SHORTNAME;
			break;
		case 'l':
			args.flags |= MSDOSFSMNT_LONGNAME;
			break;
		case '9':
			args.flags |= MSDOSFSMNT_NOWIN95;
			break;
		case 'u':
			args.uid = a_uid(optarg);
			set_uid = 1;
			break;
		case 'g':
			args.gid = a_gid(optarg);
			set_gid = 1;
			break;
		case 'm':
			args.mask = a_mask(optarg);
			set_mask = 1;
			break;
		case 'M':
			args.dirmask = a_mask(optarg);
			set_dirmask = 1;
			break;
		case 'L':
			load_ultable(&args, optarg);
			args.flags |= MSDOSFSMNT_ULTABLE;
			break;
		case 'W':
			load_u2wtable(&args, optarg);
			args.flags |= MSDOSFSMNT_U2WTABLE;
			break;
#if PROCESS_OPTIONS
		case 'o':
			getmntopts(optarg, mopts, &mntflags, &args.flags);
			break;
#endif
		case '?':
		default:
			usage();
			break;
		}
	}

	if (optind + 2 != argc)
		usage();
	
	if (set_mask && !set_dirmask) {
		args.dirmask = args.mask;
		set_dirmask = 1;
	}
	else if (set_dirmask && !set_mask) {
		args.mask = args.dirmask;
		set_mask = 1;
	}
	
	dev = argv[optind];
	dir = argv[optind + 1];

	args.fspec = dev;
	args.export.ex_root = DEFAULT_ROOTUID;
	if (mntflags & MNT_RDONLY)
		args.export.ex_flags = MNT_EXRDONLY;
	else
		args.export.ex_flags = 0;
	if (!set_gid || !set_uid || !set_mask) {
		if (stat(dir, &sb) == -1)
			err(1, "stat %s", dir);

		if (!set_uid)
			args.uid = sb.st_uid;
		if (!set_gid)
			args.gid = sb.st_gid;
		if (!set_mask)
			args.mask = args.dirmask = 
				sb.st_mode & (S_IRWXU | S_IRWXG | S_IRWXO);
	}

	if (mount("msdos", dir, mntflags, &args) < 0)
		err(1, "%s", dev);

	exit(0);
}

gid_t
a_gid(s)
	char *s;
{
	struct group *gr;
	char *gname;
	gid_t gid;

	if ((gr = getgrnam(s)) != NULL)
		gid = gr->gr_gid;
	else {
		for (gname = s; *s && isdigit(*s); ++s);
		if (!*s)
			gid = atoi(gname);
		else
			errx(1, "unknown group id: %s", gname);
	}
	return (gid);
}

uid_t
a_uid(s)
	char *s;
{
	struct passwd *pw;
	char *uname;
	uid_t uid;

	if ((pw = getpwnam(s)) != NULL)
		uid = pw->pw_uid;
	else {
		for (uname = s; *s && isdigit(*s); ++s);
		if (!*s)
			uid = atoi(uname);
		else
			errx(1, "unknown user id: %s", uname);
	}
	return (uid);
}

mode_t
a_mask(s)
	char *s;
{
	int done, rv;
	char *ep;

	done = 0;
	rv = -1;
	if (*s >= '0' && *s <= '7') {
		done = 1;
		rv = strtol(s, &ep, 8);
	}
	if (!done || rv < 0 || *ep)
		errx(1, "invalid file mode: %s", s);
	return (rv);
}

void
usage()
{
	fprintf(stderr, "%s\n%s\n", 
	"usage: mount_msdos [-u user] [-g group] [-m mask] [-M mask]",
	"                   [-s] [-l] [-9] [-L locale] [-W table] bdev dir");
	exit(1);
}

/*
 * Load Unicode/DOS conversion tables.  Absolute paths and relative paths
 * that exist locally are accepted; otherwise try /usr/libdata/msdosfs/<name>.
 * Uses fgets (no FreeBSD libutil fparseln). Blank lines and '#' comments skip.
 */
static char *
next_table_line(f, buf, buflen)
	FILE *f;
	char *buf;
	size_t buflen;
{
	char *s;

	while (fgets(buf, buflen, f) != NULL) {
		s = buf;
		while (isspace((unsigned char)*s))
			s++;
		if (*s == '\0' || *s == '#')
			continue;
		return (s);
	}
	return (NULL);
}

void
load_u2wtable(pargs, name)
	struct msdosfs_args *pargs;
	char *name;
{
	FILE *f;
	int i, j, code[8];
	char buf[256];
	char path[MAXPATHLEN];
	char *fn, *s;

	if (*name == '/')
		fn = name;
	else if ((f = fopen(name, "r")) != NULL) {
		fclose(f);
		fn = name;
	} else {
		snprintf(path, sizeof(path), "/usr/libdata/msdosfs/%s", name);
		fn = path;
	}
	if ((f = fopen(fn, "r")) == NULL)
		err(1, "%s", fn);

	for (i = 0; i < 16; i++) {
		if ((s = next_table_line(f, buf, sizeof(buf))) == NULL)
			errx(1, "can't read u2w table row %d from %s", i, fn);
		if (sscanf(s, "%i%i%i%i%i%i%i%i",
		    code, code + 1, code + 2, code + 3,
		    code + 4, code + 5, code + 6, code + 7) != 8)
			errx(1, "u2w table: missing item(s) in row %d", i);
		for (j = 0; j < 8; j++)
			pargs->u2w[i * 8 + j] = code[j];
	}
	for (i = 0; i < 16; i++) {
		if ((s = next_table_line(f, buf, sizeof(buf))) == NULL)
			errx(1, "can't read d2u table row %d from %s", i, fn);
		if (sscanf(s, "%i%i%i%i%i%i%i%i",
		    code, code + 1, code + 2, code + 3,
		    code + 4, code + 5, code + 6, code + 7) != 8)
			errx(1, "d2u table: missing item(s) in row %d", i);
		for (j = 0; j < 8; j++)
			pargs->d2u[i * 8 + j] = code[j];
	}
	for (i = 0; i < 16; i++) {
		if ((s = next_table_line(f, buf, sizeof(buf))) == NULL)
			errx(1, "can't read u2d table row %d from %s", i, fn);
		if (sscanf(s, "%i%i%i%i%i%i%i%i",
		    code, code + 1, code + 2, code + 3,
		    code + 4, code + 5, code + 6, code + 7) != 8)
			errx(1, "u2d table: missing item(s) in row %d", i);
		for (j = 0; j < 8; j++)
			pargs->u2d[i * 8 + j] = code[j];
	}
	fclose(f);
}

void
load_ultable(pargs, name)
	struct msdosfs_args *pargs;
	char *name;
{
	int i;

	if (setlocale(LC_CTYPE, name) == NULL)
		err(1, "%s", name);
	for (i = 0; i < 128; i++) {
		pargs->ul[i] = tolower(i | 0x80);
		pargs->lu[i] = toupper(i | 0x80);
	}
}
