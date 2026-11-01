/*	$NetBSD: ext2fs_bswap.c,v 1.8 2003/10/05 17:48:49 bouyer Exp $	*/

/*
 * Copyright (c) 1997 Manuel Bouyer.
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
 *	This product includes software developed by Manuel Bouyer.
 * 4. The name of the author may not be used to endorse or promote products
 *    derived from this software without specific prior written permission.
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
 *
 */

#include <sys/types.h>
#ifdef _KERNEL
#include <sys/systm.h>
#endif
#include "ext2_fs.h"
#include "ext2fs_dinode.h"

#if !defined(_KERNEL)
#include <string.h>
#endif

/* These functions are needed on big endian; tests can exercise swaps directly. */
#if BYTE_ORDER == BIG_ENDIAN || defined(EXT2_TEST_SWAP)
void
e2fs_sb_bswap(old, new)
	struct ext2fs *old, *new;
{
	/* preserve unused fields */
	memmove(new, old, sizeof(struct ext2fs));
	new->e2fs_icount	=	ext2_bswap32(old->e2fs_icount);
	new->e2fs_bcount	=	ext2_bswap32(old->e2fs_bcount);
	new->e2fs_rbcount	=	ext2_bswap32(old->e2fs_rbcount);
	new->e2fs_fbcount	=	ext2_bswap32(old->e2fs_fbcount);
	new->e2fs_ficount	=	ext2_bswap32(old->e2fs_ficount);
	new->e2fs_first_dblock	=	ext2_bswap32(old->e2fs_first_dblock);
	new->e2fs_log_bsize	=	ext2_bswap32(old->e2fs_log_bsize);
	new->e2fs_fsize		=	ext2_bswap32(old->e2fs_fsize);
	new->e2fs_bpg		=	ext2_bswap32(old->e2fs_bpg);
	new->e2fs_fpg		=	ext2_bswap32(old->e2fs_fpg);
	new->e2fs_ipg		=	ext2_bswap32(old->e2fs_ipg);
	new->e2fs_mtime		=	ext2_bswap32(old->e2fs_mtime);
	new->e2fs_wtime		=	ext2_bswap32(old->e2fs_wtime);
	new->e2fs_mnt_count	=	ext2_bswap16(old->e2fs_mnt_count);
	new->e2fs_max_mnt_count	=	ext2_bswap16(old->e2fs_max_mnt_count);
	new->e2fs_magic		=	ext2_bswap16(old->e2fs_magic);
	new->e2fs_state		=	ext2_bswap16(old->e2fs_state);
	new->e2fs_beh		=	ext2_bswap16(old->e2fs_beh);
	new->e2fs_minrev	=	ext2_bswap16(old->e2fs_minrev);
	new->e2fs_lastfsck	=	ext2_bswap32(old->e2fs_lastfsck);
	new->e2fs_fsckintv	=	ext2_bswap32(old->e2fs_fsckintv);
	new->e2fs_creator	=	ext2_bswap32(old->e2fs_creator);
	new->e2fs_rev		=	ext2_bswap32(old->e2fs_rev);
	new->e2fs_ruid		=	ext2_bswap16(old->e2fs_ruid);
	new->e2fs_rgid		=	ext2_bswap16(old->e2fs_rgid);
	new->e2fs_first_ino	=	ext2_bswap32(old->e2fs_first_ino);
	new->e2fs_inode_size	=	ext2_bswap16(old->e2fs_inode_size);
	new->e2fs_block_group_nr =	ext2_bswap16(old->e2fs_block_group_nr);
	new->e2fs_features_compat =	ext2_bswap32(old->e2fs_features_compat);
	new->e2fs_features_incompat =	ext2_bswap32(old->e2fs_features_incompat);
	new->e2fs_features_rocompat =	ext2_bswap32(old->e2fs_features_rocompat);
	new->e2fs_algo		=	ext2_bswap32(old->e2fs_algo);
}

void e2fs_cg_bswap(old, new, size)
	struct  ext2_gd *old, *new;
	int size;
{
	int i;
	/* Preserve descriptor padding and reserved bytes, including aliasing. */
	memmove(new, old, size);
	for (i=0; i < (size / (int)sizeof(struct ext2_gd)); i++) {
		new[i].ext2bgd_b_bitmap	= ext2_bswap32(old[i].ext2bgd_b_bitmap);
		new[i].ext2bgd_i_bitmap	= ext2_bswap32(old[i].ext2bgd_i_bitmap);
		new[i].ext2bgd_i_tables	= ext2_bswap32(old[i].ext2bgd_i_tables);
		new[i].ext2bgd_nbfree	= ext2_bswap16(old[i].ext2bgd_nbfree);
		new[i].ext2bgd_nifree	= ext2_bswap16(old[i].ext2bgd_nifree);
		new[i].ext2bgd_ndirs	= ext2_bswap16(old[i].ext2bgd_ndirs);
	}
}

void e2fs_i_bswap(old, new)
	struct ext2fs_dinode *old, *new;
{
	/* Preserve Linux OS-dependent bytes and opaque block/symlink data. */
	memmove(new, old, sizeof(struct ext2fs_dinode));
	new->e2di_mode		=	ext2_bswap16(old->e2di_mode);
	new->e2di_uid		=	ext2_bswap16(old->e2di_uid);
	new->e2di_gid		=	ext2_bswap16(old->e2di_gid);
	new->e2di_nlink		=	ext2_bswap16(old->e2di_nlink);
	new->e2di_size		=	ext2_bswap32(old->e2di_size);
	new->e2di_atime		=	ext2_bswap32(old->e2di_atime);
	new->e2di_ctime		=	ext2_bswap32(old->e2di_ctime);
	new->e2di_mtime		=	ext2_bswap32(old->e2di_mtime);
	new->e2di_dtime		=	ext2_bswap32(old->e2di_dtime);
	new->e2di_nblock	=	ext2_bswap32(old->e2di_nblock);
	new->e2di_flags		=	ext2_bswap32(old->e2di_flags);
	new->e2di_gen		=	ext2_bswap32(old->e2di_gen);
	new->e2di_facl		=	ext2_bswap32(old->e2di_facl);
	new->e2di_dacl		=	ext2_bswap32(old->e2di_dacl);
	new->e2di_faddr		=	ext2_bswap32(old->e2di_faddr);
	memmove(&new->e2di_blocks[0], &old->e2di_blocks[0],
		(NDADDR+NIADDR) * sizeof(int));
}
#endif
