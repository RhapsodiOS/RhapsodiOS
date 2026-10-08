/*	$NetBSD: ext2fs_balloc.c,v 1.22 2004/03/22 19:23:08 bouyer Exp $	*/

/*
 * Copyright (c) 1982, 1986, 1989, 1993
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
 *
 *	@(#)ffs_balloc.c	8.4 (Berkeley) 9/23/93
 * Modified for ext2fs by Manuel Bouyer.
 */

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
 *	@(#)ffs_balloc.c	8.4 (Berkeley) 9/23/93
 * Modified for ext2fs by Manuel Bouyer.
 */

#include "ext2fs_extern.h"

/*
 * Balloc defines the structure of file system storage
 * by allocating the physical blocks on a device given
 * the inode and the logical block number in a file.
 */
int
ext2fs_balloc(ip, bn, size, cred, bpp, flags)
	struct inode *ip;
	daddr_t bn;
	int size;
	struct ucred *cred;
	struct buf **bpp;
	int flags;
{
	struct m_ext2fs *fs;
	daddr_t nb;
	struct buf *bp, *nbp;
	struct vnode *vp = ITOV(ip);
	struct indir indirs[NIADDR + 2];
	daddr_t newb, lbn, pref;
	int32_t *bap;	/* XXX ondisk32 */
	int num, i, error;
	u_int deallocated;
	daddr_t *blkp, *allocblk, allociblk[NIADDR + 1];
	int32_t *allocib;	/* XXX ondisk32 */
	int unwindidx = -1;



	if (bpp != NULL) {
		*bpp = NULL;
	}
	if (ip->i_e2fs->e2fs_suspended) return ip->i_e2fs->e2fs_ioerror;
	if (ip->i_e2fs->e2fs_ronly) return EROFS;
	if (bn < 0 || (u_int64_t)bn * ip->i_e2fs->e2fs_bsize > EXT2_FILESIZE_MAX)
		return (EFBIG);
	fs = ip->i_e2fs;
	lbn = bn;

	/*
	 * The first NDADDR blocks are direct blocks
	 */
	if (bn < NDADDR) {
		/* XXX ondisk32 */
		nb = fs2h32(ext2fs_dinode(ip)->e2di_blocks[bn]);
		if (nb != 0) {

			/*
			 * the block is already allocated, just read it.
			 */

			if (bpp != NULL) {
				error = bread(vp, bn, fs->e2fs_bsize, NOCRED,
					      &bp);
				if (error || bp->b_resid) {
					if (!error) error = EIO;
					ext2fs_io_error(fs,error);
					brelse(bp);
					return (error);
				}
				*bpp = bp;
			}
			return (0);
		}

		/*
		 * allocate a new direct block.
		 */

		error = ext2fs_alloc(ip, bn,
		    ext2fs_blkpref(ip, bn, bn, &ext2fs_dinode(ip)->e2di_blocks[0]),
		    cred, &newb);
		if (error)
			return (error);
		((struct ext2fs_node *)ip)->last_lblk = lbn;
		((struct ext2fs_node *)ip)->last_blk = newb;
		/* XXX ondisk32 */
		ext2fs_dinode(ip)->e2di_blocks[bn] = h2fs32((int32_t)newb);
		ip->i_flag |= IN_CHANGE | IN_UPDATE;
		if (bpp != NULL) {
			bp = getblk(vp, bn, fs->e2fs_bsize, 0, 0);
			bp->b_blkno = fsbtodb(fs, newb);
			if (flags & B_CLRBUF)
				clrbuf(bp);
			*bpp = bp;
		}
		return (0);
	}
	/*
	 * Determine the number of levels of indirection.
	 */
	pref = 0;
	if ((error = ufs_getlbns(vp, bn, indirs, &num)) != 0)
		return(error);
#ifdef DIAGNOSTIC
	if (num < 1)
		panic ("ext2fs_balloc: ufs_getlbns returned indirect block\n");
#endif
	/*
	 * Fetch the first indirect block allocating if necessary.
	 */
	--num;
	/* XXX ondisk32 */
	nb = fs2h32(ext2fs_dinode(ip)->e2di_blocks[NDADDR + indirs[0].in_off]);
	allocib = NULL;
	allocblk = allociblk;
	if (nb == 0) {
		pref = ext2fs_blkpref(ip, lbn, 0, (int32_t *)0);
		error = ext2fs_alloc(ip, lbn, pref, cred, &newb);
		if (error)
			return (error);
		nb = newb;
		*allocblk++ = nb;
		((struct ext2fs_node *)ip)->last_blk = newb;
		bp = getblk(vp, indirs[1].in_lbn, fs->e2fs_bsize, 0, 0);
		bp->b_blkno = fsbtodb(fs, newb);
		clrbuf(bp);
		/*
		 * Write synchronously so that indirect blocks
		 * never point at garbage.
		 */
		if ((error = ext2_buf_write(bp,MNT_WAIT)) != 0)
			goto fail;
		unwindidx = 0;
		allocib = &ext2fs_dinode(ip)->e2di_blocks[NDADDR + indirs[0].in_off];
		/* XXX ondisk32 */
		*allocib = h2fs32((int32_t)newb);
		ip->i_flag |= IN_CHANGE | IN_UPDATE;
	}
	/*
	 * Fetch through the indirect blocks, allocating as necessary.
	 */
	for (i = 1;;) {
		error = bread(vp,
		    indirs[i].in_lbn, (int)fs->e2fs_bsize, NOCRED, &bp);
		if (error || bp->b_resid) {
			if (!error) error = EIO;
			ext2fs_io_error(fs,error);
			brelse(bp);
			goto fail;
		}
		bap = (int32_t *)bp->b_data;	/* XXX ondisk32 */
		nb = fs2h32(bap[indirs[i].in_off]);
		if ((u_int32_t)nb >= fs->e2fs.e2fs_bcount) {
			error = EIO;
			brelse(bp);
			goto fail;
		}
		if (i == num)
			break;
		i++;
		if (nb != 0) {
			brelse(bp);
			continue;
		}
		pref = ext2fs_blkpref(ip, lbn, 0, (int32_t *)0);
		error = ext2fs_alloc(ip, lbn, pref, cred, &newb);
		if (error) {
			brelse(bp);
			goto fail;
		}
		nb = newb;
		*allocblk++ = nb;
		((struct ext2fs_node *)ip)->last_blk = newb;
		nbp = getblk(vp, indirs[i].in_lbn, fs->e2fs_bsize, 0, 0);
		nbp->b_blkno = fsbtodb(fs, nb);
		clrbuf(nbp);
		/*
		 * Write synchronously so that indirect blocks
		 * never point at garbage.
		 */
		if ((error = ext2_buf_write(nbp,MNT_WAIT)) != 0) {
			brelse(bp);
			goto fail;
		}
		if (unwindidx < 0)
			unwindidx = i - 1;
		/* XXX ondisk32 */
		bap[indirs[i - 1].in_off] = h2fs32((int32_t)nb);
		/*
		 * Publish the reference synchronously before returning the allocation.
		 */
		if ((error=ext2_buf_write(bp,MNT_WAIT)) != 0)
			goto fail;
	}
	/*
	 * Get the data block, allocating if necessary.
	 */
	if (nb == 0) {
		pref = ext2fs_blkpref(ip, lbn, indirs[num].in_off, &bap[0]);
		error = ext2fs_alloc(ip, lbn, pref, cred, &newb);
		if (error) {
			brelse(bp);
			goto fail;
		}
		nb = newb;
		*allocblk++ = nb;
		((struct ext2fs_node *)ip)->last_lblk = lbn;
		((struct ext2fs_node *)ip)->last_blk = newb;
		/* XXX ondisk32 */
		if (unwindidx < 0) unwindidx=num;
		bap[indirs[num].in_off] = h2fs32((int32_t)nb);
		/*
		 * Publish the reference synchronously before returning the allocation.
		 */
		if ((error=ext2_buf_write(bp,MNT_WAIT)) != 0)
			goto fail;
		if (bpp != NULL) {
			nbp = getblk(vp, lbn, fs->e2fs_bsize, 0, 0);
			nbp->b_blkno = fsbtodb(fs, nb);
			if (flags & B_CLRBUF)
				clrbuf(nbp);
			*bpp = nbp;
		}
		return (0);
	}
	brelse(bp);
	if (bpp != NULL) {
		if (flags & B_CLRBUF) {
			error = bread(vp, lbn, (int)fs->e2fs_bsize, NOCRED,
				      &nbp);
			if (error || nbp->b_resid) {
				if (!error) error = EIO;
				ext2fs_io_error(fs,error);
				brelse(nbp);
				goto fail;
			}
		} else {
			nbp = getblk(vp, lbn, fs->e2fs_bsize, 0, 0);
			nbp->b_blkno = fsbtodb(fs, nb);
		}
		*bpp = nbp;
	}
	return (0);
fail:
	/* Persist removal of the first published reference before freeing its
	 * allocations. On cleanup I/O failure, retain blocks for offline repair. */
	if (unwindidx >= 0) {
		if (unwindidx == 0) {
			/* This new inode root has not yet been published on disk. */
			*allocib = 0;
		} else {
			int r;
			r = bread(vp,indirs[unwindidx].in_lbn,fs->e2fs_bsize,NOCRED,&bp);
			if (r || bp->b_resid) {
				if (!r) r=EIO;
				bp->b_flags |= B_INVAL;
				brelse(bp);
				ext2fs_io_error(fs,r);
				return error;
			}
			bap=(int32_t *)bp->b_data;
			bap[indirs[unwindidx].in_off]=0;
			if (ext2_buf_write(bp,MNT_WAIT)) return error;
		}
		for (i=unwindidx+1;i<=num;i++) {
			bp=getblk(vp,indirs[i].in_lbn,fs->e2fs_bsize,0,0);
			bp->b_flags |= B_INVAL;
			brelse(bp);
		}
	}
	for (deallocated=0,blkp=allociblk;blkp<allocblk;blkp++) {
		ext2fs_blkfree(ip,*blkp);
		deallocated+=fs->e2fs_bsize;
	}
	if (deallocated) {
		ip->i_e2fs_nblock -= (deallocated / 512);
		ip->i_flag |= IN_CHANGE | IN_UPDATE;
	}
	return error;
}

/* NetBSD UVM range helper retained; native pager uses VOP_WRITE. */
#if 0
int
ext2fs_gop_alloc(struct vnode *vp, off_t off, off_t len, int flags,
    struct ucred *cred)
{
	struct inode *ip = VTOI(vp);
	struct m_ext2fs *fs = ip->i_e2fs;
	int error, delta, bshift, bsize;
	UVMHIST_FUNC("ext2fs_gop_alloc"); UVMHIST_CALLED(ubchist);

	bshift = fs->e2fs_bshift;
	bsize = 1 << bshift;

	delta = off & (bsize - 1);
	off -= delta;
	len += delta;

	while (len > 0) {
		bsize = min(bsize, len);
		UVMHIST_LOG(ubchist, "off 0x%x len 0x%x bsize 0x%x",
			    off, len, bsize, 0);

		error = ext2fs_balloc(ip, lblkno(fs, off), bsize, cred,
		    NULL, flags);
		if (error) {
			UVMHIST_LOG(ubchist, "error %d", error, 0,0,0);
			return error;
		}

		/*
		 * increase file size now, VOP_BALLOC() requires that
		 * EOF be up-to-date before each call.
		 */

		if (ip->i_e2fs_size < off + bsize) {
			UVMHIST_LOG(ubchist, "old 0x%x new 0x%x",
				    ip->i_e2fs_size, off + bsize,0,0);
			ip->i_e2fs_size = off + bsize;
		}

		off += bsize;
		len -= bsize;
	}
	return 0;
}

#endif
