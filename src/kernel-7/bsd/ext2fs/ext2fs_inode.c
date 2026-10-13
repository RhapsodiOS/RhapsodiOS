/*	$NetBSD: ext2fs_inode.c,v 1.40 2004/03/22 19:23:08 bouyer Exp $	*/

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
 *	@(#)ffs_inode.c	8.8 (Berkeley) 10/19/94
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
 *	@(#)ffs_inode.c	8.8 (Berkeley) 10/19/94
 * Modified for ext2fs by Manuel Bouyer.
 */

#include "ext2fs_extern.h"
#include <vm/vnode_pager.h>
#include <mach_nbc.h>
#if MACH_NBC
#include <kern/mapfs.h>
#endif

extern int prtactive;

static int ext2fs_indirtrunc __P((struct inode *, daddr_t, daddr_t,
				  daddr_t, int, long *));

/*
 * Last reference to an inode.  If necessary, write or delete it.
 */
int
ext2fs_inactive(v)
	void *v;
{   
	struct vop_inactive_args /* {
		struct vnode *a_vp;
		struct proc *a_p;
	} */ *ap = v;
	struct vnode *vp = ap->a_vp;
	struct inode *ip = VTOI(vp);
	struct proc *p = ap->a_p;
	int error = 0;

	/* A rejected disk inode never acquired authority to change allocations.
	 * Recycle its private vnode state without interpreting its link count. */
	if (!((struct ext2fs_node *)ip)->admitted) {
		VOP_UNLOCK(vp, 0, current_proc());
		vrecycle(vp, NULL, p);
		return 0;
	}
	
	if (prtactive && vp->v_usecount != 0)
		vprint("ext2fs_inactive: pushing active", vp);
	/* Get rid of inodes related to stale file handles. */
	if (ip->i_e2fs_mode == 0 || ext2fs_dinode(ip)->e2di_dtime != 0)
		goto out;

	error = 0;
	if (ip->i_e2fs_nlink == 0 && (vp->v_mount->mnt_flag & MNT_RDONLY) == 0) {

		if (ip->i_e2fs_size != 0) {
			error = VOP_TRUNCATE(vp, (off_t)0, 0, NOCRED, NULL);
			if (error) goto out;
		}
		ext2fs_dinode(ip)->e2di_dtime = time.tv_sec;
		ip->i_flag |= IN_CHANGE | IN_UPDATE;
		VOP_VFREE(vp, ip->i_number, ip->i_e2fs_mode);

	}
	if (ip->i_flag &
	    (IN_ACCESS | IN_CHANGE | IN_UPDATE | IN_MODIFIED)) {

		VOP_UPDATE(vp, NULL, NULL, 0);

	}
out:
	VOP_UNLOCK(vp, 0, current_proc());
	/*
	 * If we are done with the inode, reclaim it
	 * so that it can be reused immediately.
	 */
	if (ext2fs_dinode(ip)->e2di_dtime != 0)
		vrecycle(vp, NULL, p);
	return (error);
}   


/*
 * Update the access, modified, and inode change times as specified by the
 * IACCESS, IUPDATE, and ICHANGE flags respectively. The IMODIFIED flag is
 * used to specify that the inode needs to be updated but that the times have
 * already been set. The access and modified times are taken from the second
 * and third parameters; the inode change time is always taken from the current
 * time. If MNT_WAIT or UPDATE_DIROP is set, then wait for the disk
 * write of the inode to complete.
 */
int
ext2fs_update_inode(struct vnode *vp, struct timeval *access,
    struct timeval *modify, int wait)
{
    struct inode *ip = VTOI(vp);
    struct m_ext2fs *fs = ip->i_e2fs;
    struct buf *bp;
    int error;
    if (fs->e2fs_suspended) return fs->e2fs_ioerror;
    if (fs->e2fs_ronly) return 0;
    if (!(ip->i_flag & (IN_ACCESS|IN_UPDATE|IN_CHANGE|IN_MODIFIED))) return 0;
    ITIMES(ip, access ? access : &time, modify ? modify : &time);
    error = bread(ip->i_devvp, fsbtodb(fs, ino_to_fsba(fs,ip->i_number)),
        fs->e2fs_bsize, NOCRED, &bp);
    if (error || bp->b_resid) {
        if (!error) error=EIO;
        brelse(bp); return ext2fs_io_error(fs,error);
    }
    ext2fs_inode_save(ip, (struct ext2fs_dinode *)((char *)bp->b_data +
        ino_to_fsbo(fs,ip->i_number) * EXT2_DINODE_SIZE));
    error=ext2fs_io_error(fs,ext2_buf_write(bp,wait ? MNT_WAIT : MNT_NOWAIT));
    if (!error) ip->i_flag &= ~IN_MODIFIED;
    return error;
}

int
ext2fs_update(struct vop_update_args *ap)
{
    return ext2fs_update_inode(ap->a_vp,ap->a_access,ap->a_modify,ap->a_waitfor);
}

#define	SINGLE	0	/* index of single indirect block */
#define	DOUBLE	1	/* index of double indirect block */
#define	TRIPLE	2	/* index of triple indirect block */
/*
 * Truncate the inode oip to at most length size, freeing the
 * disk blocks.
 */
int
ext2fs_truncate(struct vop_truncate_args *ap)
{
	struct vnode *ovp = ap->a_vp;
	daddr_t lastblock;
	struct inode *oip;
	daddr_t bn, lastiblock[NIADDR], indir_lbn[NIADDR];
	/* XXX ondisk32 */
	int32_t oldblks[NDADDR + NIADDR], newblks[NDADDR + NIADDR];
	off_t length = ap->a_length;
	struct m_ext2fs *fs;
	int offset, size, level;
	struct buf *bp;
	daddr_t physical;
	long count, nblocks, blocksreleased = 0;
	int i;
	int error, allerror = 0;
	off_t osize;

	if (VTOI(ovp)->i_e2fs->e2fs_suspended) return VTOI(ovp)->i_e2fs->e2fs_ioerror;
	if (ovp->v_mount->mnt_flag & MNT_RDONLY) return EROFS;
	if (length > EXT2_FILESIZE_MAX) return EFBIG;
	if (length < 0)
		return (EINVAL);

	oip = VTOI(ovp);
	if (ovp->v_type == VLNK &&
		(oip->i_e2fs_size < ovp->v_mount->mnt_maxsymlinklen ||
		 (ovp->v_mount->mnt_maxsymlinklen == 0 &&
		  oip->i_e2fs_nblock == 0))) {
#ifdef DIAGNOSTIC
		if (length != 0)
			panic("ext2fs_truncate: partial truncate of symlink");
#endif
		memset((char *)&ext2fs_dinode(oip)->e2di_shortlink, 0,
			(u_int)oip->i_e2fs_size);
		oip->i_e2fs_size = 0;
		oip->i_flag |= IN_CHANGE | IN_UPDATE;
		return (VOP_UPDATE(ovp, NULL, NULL, MNT_WAIT));
	}
#if MACH_NBC
	error = ext2fs_vm_flush(ovp, ap->a_p, 1, (vm_offset_t)length);
	if (error) return error;
#endif
	if (oip->i_e2fs_size == length) {
		oip->i_flag |= IN_CHANGE | IN_UPDATE;
		return (VOP_UPDATE(ovp, NULL, NULL, 0));
	}
	fs = oip->i_e2fs;
	osize = oip->i_e2fs_size;
	/*
	 * Lengthen the file sparsely; new holes read as zero.
	 */
    if (osize < length) {
        oip->i_size=length;
#if MACH_NBC
        if (ovp->v_type == VREG && ovp->v_vm_info && !ovp->v_vm_info->mapped)
#endif
            vnode_pager_setsize(ovp,(u_long)length);
        oip->i_flag |= IN_CHANGE|IN_UPDATE;
        return VOP_UPDATE(ovp,NULL,NULL,1);
    }

	/*
	 * Shorten the size of the file. If the file is not being
	 * truncated to a block boundry, the contents of the
	 * partial block following the end of the file must be
	 * zero'ed in case it ever become accessible again because
	 * of subsequent file growth.
	 */
	/* Check unshifted inode pointers before any truncate I/O or freeing. */
	for (i = 0; i < NDADDR + NIADDR; i++)
		if (fs2h32(ext2fs_dinode(oip)->e2di_blocks[i]) >= fs->e2fs.e2fs_bcount)
			return ext2fs_io_error(fs,EIO);

	offset = blkoff(fs, length);
	if (offset != 0) {
		size = fs->e2fs_bsize;

        error=VOP_BMAP(ovp,lblkno(fs,length),NULL,&physical,NULL);
        if (error) return error;
        if (physical != -1) {
            error=bread(ovp,lblkno(fs,length),size,NOCRED,&bp);
            if (error || bp->b_resid) { if (!error) error=EIO; bp->b_flags |= B_INVAL; brelse(bp); return ext2fs_io_error(fs,error); }
            memset((char *)bp->b_data+offset,0,size-offset);
            if ((error=ext2_buf_write(bp,MNT_WAIT))) return error;
        }
	}
	oip->i_e2fs_size = length;
#if MACH_NBC
    if (ovp->v_type == VREG && ovp->v_vm_info && !ovp->v_vm_info->mapped)
#endif
        vnode_pager_setsize(ovp,(u_long)length);

	/*
	 * Calculate index into inode's block list of
	 * last direct and indirect blocks (if any)
	 * which we want to keep.  Lastblock is -1 when
	 * the file is truncated to 0.
	 */
	lastblock = lblkno(fs, length + fs->e2fs_bsize - 1) - 1;
	lastiblock[SINGLE] = lastblock - NDADDR;
	lastiblock[DOUBLE] = lastiblock[SINGLE] - NINDIR(fs);
	lastiblock[TRIPLE] = lastiblock[DOUBLE] - NINDIR(fs) * NINDIR(fs);
	nblocks = (fs->e2fs_bsize / 512);
	/*
	 * Update file and block pointers on disk before we start freeing
	 * blocks.  If we crash before free'ing blocks below, the blocks
	 * will be returned to the free list.  lastiblock values are also
	 * normalized to -1 for calls to ext2fs_indirtrunc below.
	 */
	memcpy((caddr_t)oldblks, (caddr_t)&ext2fs_dinode(oip)->e2di_blocks[0], sizeof oldblks);
	for (level = TRIPLE; level >= SINGLE; level--)
		if (lastiblock[level] < 0) {
			ext2fs_dinode(oip)->e2di_blocks[NDADDR + level] = 0;
			lastiblock[level] = -1;
		}
	for (i = NDADDR - 1; i > lastblock; i--)
		ext2fs_dinode(oip)->e2di_blocks[i] = 0;
	oip->i_flag |= IN_CHANGE | IN_UPDATE;
	error = VOP_UPDATE(ovp, NULL, NULL, MNT_WAIT);
	if (error) {
		/* The old disk inode may still reference every old block. */
		memcpy(&ext2fs_dinode(oip)->e2di_blocks[0],oldblks,sizeof oldblks);
		oip->i_e2fs_size=osize;
		oip->i_flag |= IN_CHANGE | IN_UPDATE;
#if MACH_NBC
		if (ovp->v_type == VREG && ovp->v_vm_info && !ovp->v_vm_info->mapped)
#endif
			vnode_pager_setsize(ovp,(u_long)osize);
		return error;
	}

	/*
	 * Having written the new inode to disk, save its new configuration
	 * and put back the old block pointers long enough to process them.
	 * Note that we save the new block configuration so we can check it
	 * when we are done.
	 */

	memcpy((caddr_t)newblks, (caddr_t)&ext2fs_dinode(oip)->e2di_blocks[0], sizeof newblks);
	memcpy((caddr_t)&ext2fs_dinode(oip)->e2di_blocks[0], (caddr_t)oldblks, sizeof oldblks);
	oip->i_e2fs_size = osize;
	error = vinvalbuf(ovp, (length ? V_SAVE : 0) | V_SAVEMETA,
	    ap->a_cred, ap->a_p, 0, 0);
	if (error && !allerror)
		allerror = error;

	/*
	 * Indirect blocks first.
	 */
	indir_lbn[SINGLE] = -NDADDR;
	indir_lbn[DOUBLE] = indir_lbn[SINGLE] - NINDIR(fs) -1;
	indir_lbn[TRIPLE] = indir_lbn[DOUBLE] - NINDIR(fs) * NINDIR(fs) - 1;
	for (level = TRIPLE; level >= SINGLE; level--) {
		/* XXX ondisk32 */
		bn = fs2h32(ext2fs_dinode(oip)->e2di_blocks[NDADDR + level]);
		if (bn != 0) {
			error = ext2fs_indirtrunc(oip, indir_lbn[level],
			    bn, lastiblock[level], level, &count);
			blocksreleased += count;
			if (error) {
				allerror = error;
				goto done;
			}
			if (lastiblock[level] < 0) {
				ext2fs_dinode(oip)->e2di_blocks[NDADDR + level] = 0;
				ext2fs_blkfree(oip, bn);
				blocksreleased += nblocks;
			}
		}
		if (lastiblock[level] >= 0)
			goto done;
	}

	/*
	 * All whole direct blocks or frags.
	 */
	for (i = NDADDR - 1; i > lastblock; i--) {
		/* XXX ondisk32 */
		bn = fs2h32(ext2fs_dinode(oip)->e2di_blocks[i]);
		if (bn == 0)
			continue;
		ext2fs_dinode(oip)->e2di_blocks[i] = 0;
		ext2fs_blkfree(oip, bn);
		blocksreleased += (fs->e2fs_bsize / 512);
	}

done:
	/* The committed inode no longer owns detached, possibly corrupt trees.
	 * Keep them allocated for fsck; never resurrect their old pointers. */
	if (allerror)
		memcpy(&ext2fs_dinode(oip)->e2di_blocks[0],newblks,sizeof newblks);
#ifdef DIAGNOSTIC
	for (level = SINGLE; level <= TRIPLE; level++)
		if (newblks[NDADDR + level] !=
		    ext2fs_dinode(oip)->e2di_blocks[NDADDR + level])
			panic("ext2fs_truncate1");
	for (i = 0; i < NDADDR; i++)
		if (newblks[i] != ext2fs_dinode(oip)->e2di_blocks[i])
			panic("ext2fs_truncate2");
	if (length == 0 &&
	    (ovp->v_cleanblkhd.lh_first != NULL ||
	     ovp->v_dirtyblkhd.lh_first != NULL))
		panic("ext2fs_truncate3");
#endif /* DIAGNOSTIC */
	/*
	 * Put back the real size.
	 */
	oip->i_e2fs_size = length;
	oip->i_e2fs_nblock -= blocksreleased;
	oip->i_flag |= IN_CHANGE;
	return fs->e2fs_ioerror ? fs->e2fs_ioerror : allerror;
}

/*
 * Release blocks associated with the inode ip and stored in the indirect
 * block bn.  Blocks are free'd in LIFO order up to (but not including)
 * lastbn.  If level is greater than SINGLE, the block is an indirect block
 * and recursive calls to indirtrunc must be used to cleanse other indirect
 * blocks.
 *
 * NB: triple indirect blocks are untested.
 */
static int
ext2fs_indirtrunc(ip, lbn, bn, lastbn, level, countp)
	struct inode *ip;
	daddr_t lbn, lastbn;
	daddr_t bn;
	int level;
	long *countp;
{
	int i;
	struct buf *bp;
	struct m_ext2fs *fs = ip->i_e2fs;
	int32_t *bap;	/* XXX ondisk32 */
	struct vnode *vp;
	daddr_t nb, nlbn, last;
	int32_t *copy = NULL;	/* XXX ondisk32 */
	long blkcount, factor;
	int nblocks, blocksreleased = 0;
	int error = 0, allerror = 0;

	*countp = 0;
	if (bn == 0 || (u_int32_t)bn >= fs->e2fs.e2fs_bcount)
		return ext2fs_io_error(fs,EIO);

	/*
	 * Calculate index in current block of last
	 * block to be kept.  -1 indicates the entire
	 * block so we need not calculate the index.
	 */
	factor = 1;
	for (i = SINGLE; i < level; i++)
		factor *= NINDIR(fs);
	last = lastbn;
	if (lastbn > 0)
		last /= factor;
	nblocks = (fs->e2fs_bsize / 512);
	/*
	 * Get buffer of block pointers, zero those entries corresponding
	 * to blocks to be free'd, and update on disk copy first.  Since
	 * double(triple) indirect before single(double) indirect, calls
	 * to bmap on these blocks will fail.  However, we already have
	 * the on disk address, so we have to set the b_blkno field
	 * explicitly instead of letting bread do everything for us.
	 */
	vp = ITOV(ip);
	bp = getblk(vp, lbn, (int)fs->e2fs_bsize, 0, 0);
	if (bp->b_flags & (B_DONE | B_DELWRI)) {
		/* Braces must be here in case trace evaluates to nothing. */

	} else {

		current_proc()->p_stats->p_ru.ru_inblock++;	/* pay for read */
		bp->b_flags |= B_READ;
		if (bp->b_bcount > bp->b_bufsize)
			panic("ext2fs_indirtrunc: bad buffer size");
		bp->b_blkno = fsbtodb(fs, bn);
		VOP_STRATEGY(bp);
		error = biowait(bp);
	}
	if (error || bp->b_resid) {
		if (!error) error=EIO;
		bp->b_flags |= B_INVAL;
		brelse(bp);
		*countp = 0;
		return ext2fs_io_error(fs,error);
	}

	bap = (int32_t *)bp->b_data;	/* XXX ondisk32 */
	/* Validate the whole pointer block before changing it or its children. */
	for (i = 0; i < NINDIR(fs); i++) {
		if (fs2h32(bap[i]) >= fs->e2fs.e2fs_bcount) {
			bp->b_flags |= B_INVAL;
			brelse(bp);
			return ext2fs_io_error(fs,EIO);
		}
	}
	if (lastbn >= 0) {
		/* XXX ondisk32 */
		MALLOC(copy, int32_t *, fs->e2fs_bsize, M_TEMP, M_WAITOK);
		memcpy((caddr_t)copy, (caddr_t)bap, (u_int)fs->e2fs_bsize);
		memset((caddr_t)&bap[last + 1], 0,
			(u_int)(NINDIR(fs) - (last + 1)) * sizeof (u_int32_t));
		error = ext2_buf_write(bp,MNT_WAIT);
		if (error) {
			FREE(copy,M_TEMP);
			*countp=0;
			return error;
		}
		bap = copy;
	}

	/*
	 * Recursively free totally unused blocks.
	 */
	for (i = NINDIR(fs) - 1,
		nlbn = lbn + 1 - i * factor; i > last;
		i--, nlbn += factor) {
		/* XXX ondisk32 */
		nb = fs2h32(bap[i]);
		if (nb == 0)
			continue;
		if (level > SINGLE) {
			error = ext2fs_indirtrunc(ip, nlbn, nb,
						   (daddr_t)-1, level - 1,
						   &blkcount);
			blocksreleased += blkcount;
			if (error) {
				allerror = error;
				goto release;
			}
		}
		ext2fs_blkfree(ip, nb);
		blocksreleased += nblocks;
	}

	/*
	 * Recursively free last partial block.
	 */
	if (level > SINGLE && lastbn >= 0) {
		last = lastbn % factor;
		/* XXX ondisk32 */
		nb = fs2h32(bap[i]);
		if (nb != 0) {
			error = ext2fs_indirtrunc(ip, nlbn, nb,
						   last, level - 1, &blkcount);
			blocksreleased += blkcount;
			if (error) {
				allerror = error;
				goto release;
			}
		}
	}

release:
	if (copy != NULL) {
		FREE(copy, M_TEMP);
	} else {
		bp->b_flags |= B_INVAL;
		brelse(bp);
	}

	*countp = blocksreleased;
	return (allerror);
}
