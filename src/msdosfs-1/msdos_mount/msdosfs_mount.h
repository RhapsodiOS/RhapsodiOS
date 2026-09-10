/*-
 * Copyright (C) 1994, 1995, 1997 Wolfgang Solfrank.
 * Copyright (C) 1994, 1995, 1997 TooLs GmbH.
 * All rights reserved.
 * Original code by Paul Popelka (paulp@uts.amdahl.com).
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
 *	This product includes software developed by TooLs GmbH.
 * 4. The name of TooLs GmbH may not be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY TOOLS GMBH ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL TOOLS GMBH BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
 * OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
 * OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * Userland mount arguments for msdosfs. Must stay identical to the
 * non-_KERNEL section of <msdosfs/msdosfsmount.h> in the kernel.
 */

#ifndef _MSDOSFS_MOUNT_H_
#define	_MSDOSFS_MOUNT_H_

/*
 *  Arguments to mount MSDOS filesystems.
 */
struct msdosfs_args {
	char	*fspec;		/* blocks special holding the fs to mount */
	struct	export_args export;	/* network export information */
	uid_t	uid;		/* uid that owns msdosfs files */
	gid_t	gid;		/* gid that owns msdosfs files */
	mode_t	mask;		/* file mask to be applied for msdosfs perms */
	mode_t	dirmask;	/* dir  mask to be applied for msdosfs perms */
	int	flags;		/* see below */
	int magic;		/* version number */
	u_int16_t u2w[128];     /* Local->Unicode table */
	u_int8_t  ul[128];      /* Local upper->lower table */
	u_int8_t  lu[128];      /* Local lower->upper table */
	u_int8_t  d2u[128];     /* DOS->local table */
	u_int8_t  u2d[128];     /* Local->DOS table */
};

/*
 * Msdosfs mount options:
 */
#define	MSDOSFSMNT_SHORTNAME	1	/* Force old DOS short names only */
#define	MSDOSFSMNT_LONGNAME	2	/* Force Win'95 long names */
#define	MSDOSFSMNT_NOWIN95	4	/* Completely ignore Win95 entries */
#define MSDOSFSMNT_U2WTABLE     0x10    /* Local->Unicode and local<->DOS   */
					/* tables loaded                    */
#define MSDOSFSMNT_ULTABLE      0x20    /* Local upper<->lower table loaded */
/* All flags above: */
#define	MSDOSFSMNT_MNTOPT \
	(MSDOSFSMNT_SHORTNAME|MSDOSFSMNT_LONGNAME|MSDOSFSMNT_NOWIN95 \
	 |MSDOSFSMNT_U2WTABLE|MSDOSFSMNT_ULTABLE)
#define	MSDOSFSMNT_RONLY	0x80000000	/* mounted read-only	*/
#define	MSDOSFSMNT_WAITONFAT	0x40000000	/* mounted synchronous	*/
#define	MSDOSFS_FATMIRROR	0x20000000	/* FAT is mirrored */

#define MSDOSFS_ARGSMAGIC	0xe4eff300

#endif /* !_MSDOSFS_MOUNT_H_ */
