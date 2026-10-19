/*
 * Copyright (c) 2007 The DragonFly Project.  All rights reserved.
 *
 * This code is derived from software contributed to The DragonFly Project
 * by Matthew Dillon <dillon@backplane.com>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in
 *    the documentation and/or other materials provided with the
 *    distribution.
 * 3. Neither the name of The DragonFly Project nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific, prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE
 * COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
 * AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
 * OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

/*
 * Rhapsody port: one volume, no PFS, no history or master-id options.
 * The kernel admits read-only mounts only in this release.
 */
#include <sys/param.h>
#include <sys/mount.h>
#include "hammer_mount.h"

#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void usage(void);

static void
options(char *text, int *flags)
{
	char *opt;

	while ((opt = strsep(&text, ",")) != NULL) {
		if (!strcmp(opt, "ro"))
			*flags |= MNT_RDONLY;
		else if (!strcmp(opt, "rw"))
			*flags &= ~MNT_RDONLY;
		else if (!strcmp(opt, "noexec"))
			*flags |= MNT_NOEXEC;
		else if (!strcmp(opt, "exec"))
			*flags &= ~MNT_NOEXEC;
		else if (!strcmp(opt, "nosuid"))
			*flags |= MNT_NOSUID;
		else if (!strcmp(opt, "suid"))
			*flags &= ~MNT_NOSUID;
		else if (!strcmp(opt, "nodev"))
			*flags |= MNT_NODEV;
		else if (!strcmp(opt, "dev"))
			*flags &= ~MNT_NODEV;
		else
			errx(1, "unsupported mount option: %s", opt);
	}
}

int
main(int ac, char **av)
{
	struct hammer_args args;
	int ch, flags = 0;

	while ((ch = getopt(ac, av, "o:")) != -1) {
		if (ch != 'o')
			usage();
		options(optarg, &flags);
	}
	ac -= optind;
	av += optind;
	if (ac != 2)
		usage();
	args.fspec = av[0];
	if (mount("hammer", av[1], flags, &args) < 0)
		err(1, "%s on %s", args.fspec, av[1]);
	return 0;
}

static void
usage(void)
{
	fprintf(stderr, "usage: mount_hammer [-o options] special node\n");
	exit(1);
}
