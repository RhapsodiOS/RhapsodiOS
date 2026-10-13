/*	$NetBSD: mount_ext2fs.c,v 1.11 2003/08/07 10:04:27 agc Exp $	*/

/*-
 * Copyright (c) 1993, 1994
 *	The Regents of the University of California.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include <sys/param.h>
#include <sys/mount.h>
#include <ext2fs/ext2_mount.h>
#include <err.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void ext2fs_usage(void);
static void
options(char *text,int *flags)
{
    char *option;
    while ((option=strsep(&text,",")) != NULL) {
        if (!strcmp(option,"ro")) *flags |= MNT_RDONLY;
        else if (!strcmp(option,"rw")) *flags &= ~MNT_RDONLY;
        else if (!strcmp(option,"sync")) { *flags |= MNT_SYNCHRONOUS; *flags &= ~MNT_ASYNC; }
        else if (!strcmp(option,"async")) { *flags |= MNT_ASYNC; *flags &= ~MNT_SYNCHRONOUS; }
        else if (!strcmp(option,"noexec")) *flags |= MNT_NOEXEC;
        else if (!strcmp(option,"exec")) *flags &= ~MNT_NOEXEC;
        else if (!strcmp(option,"nosuid")) *flags |= MNT_NOSUID;
        else if (!strcmp(option,"suid")) *flags &= ~MNT_NOSUID;
        else if (!strcmp(option,"nodev")) *flags |= MNT_NODEV;
        else if (!strcmp(option,"dev")) *flags &= ~MNT_NODEV;
        else if (!strcmp(option,"update")) *flags |= MNT_UPDATE;
        else if (!strcmp(option,"force")) *flags |= MNT_FORCE;
        else errx(1,"unsupported mount option: %s",option);
    }
}

int
main(int argc,char **argv)
{
    struct ext2fs_args args;
    int ch,mntflags=0;
    while ((ch=getopt(argc,argv,"o:")) != -1) {
        if (ch != 'o') ext2fs_usage();
        options(optarg,&mntflags);
    }
    argc-=optind; argv+=optind;
    if (argc != 2) ext2fs_usage();
    args.fspec=argv[0];
    if (mount("ext2fs",argv[1],mntflags,&args) < 0)
        err(1,"%s on %s",args.fspec,argv[1]);
    return 0;
}
static void
ext2fs_usage(void)
{
    fprintf(stderr,"usage: mount_ext2fs [-o options] special node\n");
    exit(1);
}
