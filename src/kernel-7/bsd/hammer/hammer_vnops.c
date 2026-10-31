/*
 * Copyright (c) 2007-2008 The DragonFly Project.  All rights reserved.
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

#include "hammer.h"
#include <vfs/vfs_support.h>
#include <sys/resourcevar.h>
#include <kern/mapfs.h>

#if 0 /* phase 2: DragonFly VOPs, kept for the write path */

/*
 * USERFS VNOPS
 */
static int hammer_vop_fsync(struct vop_fsync_args *);
static int hammer_vop_read(struct vop_read_args *);
static int hammer_vop_write(struct vop_write_args *);
static int hammer_vop_access(struct vop_access_args *);
static int hammer_vop_close(struct vop_close_args *);
static int hammer_vop_ncreate(struct vop_ncreate_args *);
static int hammer_vop_getattr(struct vop_getattr_args *);
static int hammer_vop_nresolve(struct vop_nresolve_args *);
static int hammer_vop_nlookupdotdot(struct vop_nlookupdotdot_args *);
static int hammer_vop_nlink(struct vop_nlink_args *);
static int hammer_vop_nmkdir(struct vop_nmkdir_args *);
static int hammer_vop_nmknod(struct vop_nmknod_args *);
static int hammer_vop_open(struct vop_open_args *);
static int hammer_vop_print(struct vop_print_args *);
static int hammer_vop_readdir(struct vop_readdir_args *);
static int hammer_vop_readlink(struct vop_readlink_args *);
static int hammer_vop_nremove(struct vop_nremove_args *);
static int hammer_vop_nrename(struct vop_nrename_args *);
static int hammer_vop_nrmdir(struct vop_nrmdir_args *);
static int hammer_vop_markatime(struct vop_markatime_args *);
static int hammer_vop_setattr(struct vop_setattr_args *);
static int hammer_vop_strategy(struct vop_strategy_args *);
static int hammer_vop_bmap(struct vop_bmap_args *ap);
static int hammer_vop_nsymlink(struct vop_nsymlink_args *);
static int hammer_vop_nwhiteout(struct vop_nwhiteout_args *);
static int hammer_vop_ioctl(struct vop_ioctl_args *);
static int hammer_vop_mountctl(struct vop_mountctl_args *);
static int hammer_vop_kqfilter (struct vop_kqfilter_args *);

static int hammer_vop_fifoclose (struct vop_close_args *);
static int hammer_vop_fiforead (struct vop_read_args *);
static int hammer_vop_fifowrite (struct vop_write_args *);
static int hammer_vop_fifokqfilter (struct vop_kqfilter_args *);

struct vop_ops hammer_vnode_vops = {
	.vop_default =		vop_defaultop,
	.vop_fsync =		hammer_vop_fsync,
	.vop_getpages =		vop_stdgetpages,
	.vop_putpages =		vop_stdputpages,
	.vop_read =		hammer_vop_read,
	.vop_write =		hammer_vop_write,
	.vop_access =		hammer_vop_access,
	.vop_advlock =		vop_stdadvlock,
	.vop_close =		hammer_vop_close,
	.vop_ncreate =		hammer_vop_ncreate,
	.vop_getattr =		hammer_vop_getattr,
	.vop_inactive =		hammer_vop_inactive,
	.vop_reclaim =		hammer_vop_reclaim,
	.vop_nresolve =		hammer_vop_nresolve,
	.vop_nlookupdotdot =	hammer_vop_nlookupdotdot,
	.vop_nlink =		hammer_vop_nlink,
	.vop_nmkdir =		hammer_vop_nmkdir,
	.vop_nmknod =		hammer_vop_nmknod,
	.vop_open =		hammer_vop_open,
	.vop_pathconf =		vop_stdpathconf,
	.vop_print =		hammer_vop_print,
	.vop_readdir =		hammer_vop_readdir,
	.vop_readlink =		hammer_vop_readlink,
	.vop_nremove =		hammer_vop_nremove,
	.vop_nrename =		hammer_vop_nrename,
	.vop_nrmdir =		hammer_vop_nrmdir,
	.vop_markatime =	hammer_vop_markatime,
	.vop_setattr =		hammer_vop_setattr,
	.vop_bmap =		hammer_vop_bmap,
	.vop_strategy =		hammer_vop_strategy,
	.vop_nsymlink =		hammer_vop_nsymlink,
	.vop_nwhiteout =	hammer_vop_nwhiteout,
	.vop_ioctl =		hammer_vop_ioctl,
	.vop_mountctl =		hammer_vop_mountctl,
	.vop_kqfilter =		hammer_vop_kqfilter
};

struct vop_ops hammer_spec_vops = {
	.vop_default =		vop_defaultop,
	.vop_fsync =		hammer_vop_fsync,
	.vop_read =		vop_stdnoread,
	.vop_write =		vop_stdnowrite,
	.vop_access =		hammer_vop_access,
	.vop_close =		hammer_vop_close,
	.vop_markatime =	hammer_vop_markatime,
	.vop_getattr =		hammer_vop_getattr,
	.vop_inactive =		hammer_vop_inactive,
	.vop_reclaim =		hammer_vop_reclaim,
	.vop_setattr =		hammer_vop_setattr
};

struct vop_ops hammer_fifo_vops = {
	.vop_default =		fifo_vnoperate,
	.vop_fsync =		hammer_vop_fsync,
	.vop_read =		hammer_vop_fiforead,
	.vop_write =		hammer_vop_fifowrite,
	.vop_access =		hammer_vop_access,
	.vop_close =		hammer_vop_fifoclose,
	.vop_markatime =	hammer_vop_markatime,
	.vop_getattr =		hammer_vop_getattr,
	.vop_inactive =		hammer_vop_inactive,
	.vop_reclaim =		hammer_vop_reclaim,
	.vop_setattr =		hammer_vop_setattr,
	.vop_kqfilter =		hammer_vop_fifokqfilter
};

static __inline
void
hammer_knote(struct vnode *vp, int flags)
{
	if (flags)
		KNOTE(&vp->v_pollinfo.vpi_kqinfo.ki_note, flags);
}

static int hammer_dounlink(hammer_transaction_t trans, struct nchandle *nch,
			   struct vnode *dvp, struct ucred *cred,
			   int flags, int isdir);
static int hammer_vop_strategy_read(struct vop_strategy_args *ap);
static int hammer_vop_strategy_write(struct vop_strategy_args *ap);

/*
 * hammer_vop_fsync { vp, waitfor }
 *
 * fsync() an inode to disk and wait for it to be completely committed
 * such that the information would not be undone if a crash occured after
 * return.
 *
 * NOTE: HAMMER's fsync()'s are going to remain expensive until we implement
 *	 a REDO log.  A sysctl is provided to relax HAMMER's fsync()
 *	 operation.
 *
 *	 Ultimately the combination of a REDO log and use of fast storage
 *	 to front-end cluster caches will make fsync fast, but it aint
 *	 here yet.  And, in anycase, we need real transactional
 *	 all-or-nothing features which are not restricted to a single file.
 */
static
int
hammer_vop_fsync(struct vop_fsync_args *ap)
{
	hammer_inode_t ip = VTOI(ap->a_vp);
	hammer_mount_t hmp = ip->hmp;
	int waitfor = ap->a_waitfor;
	int mode;

	lwkt_gettoken(&hmp->fs_token);

	/*
	 * Fsync rule relaxation (default is either full synchronous flush
	 * or REDO semantics with synchronous flush).
	 */
	if (ap->a_flags & VOP_FSYNC_SYSCALL) {
		switch(hammer_fsync_mode) {
		case 0:
mode0:
			/* no REDO, full synchronous flush */
			goto skip;
		case 1:
mode1:
			/* no REDO, full asynchronous flush */
			if (waitfor == MNT_WAIT)
				waitfor = MNT_NOWAIT;
			goto skip;
		case 2:
			/* REDO semantics, synchronous flush */
			if (hmp->version < HAMMER_VOL_VERSION_FOUR)
				goto mode0;
			mode = HAMMER_FLUSH_UNDOS_AUTO;
			break;
		case 3:
			/* REDO semantics, relaxed asynchronous flush */
			if (hmp->version < HAMMER_VOL_VERSION_FOUR)
				goto mode1;
			mode = HAMMER_FLUSH_UNDOS_RELAXED;
			if (waitfor == MNT_WAIT)
				waitfor = MNT_NOWAIT;
			break;
		case 4:
			/* ignore the fsync() system call */
			lwkt_reltoken(&hmp->fs_token);
			return(0);
		default:
			/* we have to do something */
			mode = HAMMER_FLUSH_UNDOS_RELAXED;
			if (waitfor == MNT_WAIT)
				waitfor = MNT_NOWAIT;
			break;
		}

		/*
		 * Fast fsync only needs to flush the UNDO/REDO fifo if
		 * HAMMER_INODE_REDO is non-zero and the only modifications
		 * made to the file are write or write-extends.
		 */
		if ((ip->flags & HAMMER_INODE_REDO) &&
		    (ip->flags & HAMMER_INODE_MODMASK_NOREDO) == 0) {
			++hammer_count_fsyncs;
			hammer_flusher_flush_undos(hmp, mode);
			ip->redo_count = 0;
			if (ip->vp && (ip->flags & HAMMER_INODE_MODMASK) == 0)
				vclrisdirty(ip->vp);
			lwkt_reltoken(&hmp->fs_token);
			return(0);
		}

		/*
		 * REDO is enabled by fsync(), the idea being we really only
		 * want to lay down REDO records when programs are using
		 * fsync() heavily.  The first fsync() on the file starts
		 * the gravy train going and later fsync()s keep it hot by
		 * resetting the redo_count.
		 *
		 * We weren't running REDOs before now so we have to fall
		 * through and do a full fsync of what we have.
		 */
		if (hmp->version >= HAMMER_VOL_VERSION_FOUR &&
		    (hmp->flags & HAMMER_MOUNT_REDO_RECOVERY_RUN) == 0) {
			ip->flags |= HAMMER_INODE_REDO;
			ip->redo_count = 0;
		}
	}
skip:

	/*
	 * Do a full flush sequence.
	 *
	 * Attempt to release the vnode while waiting for the inode to
	 * finish flushing.  This can really mess up inactive->reclaim
	 * sequences so only do it if the vnode is active.
	 *
	 * WARNING! The VX lock functions must be used.  vn_lock() will
	 *	    fail when this is part of a VOP_RECLAIM sequence.
	 */
	++hammer_count_fsyncs;
	vfsync(ap->a_vp, waitfor, 1, NULL, NULL);
	hammer_flush_inode(ip, HAMMER_FLUSH_SIGNAL);
	if (waitfor == MNT_WAIT) {
		int dorelock;

		if ((ap->a_vp->v_flag & VRECLAIMED) == 0) {
			vn_unlock(ap->a_vp);
			dorelock = 1;
		} else {
			dorelock = 0;
		}
		hammer_wait_inode(ip);
		if (dorelock)
			vn_relock(ap->a_vp, LK_EXCLUSIVE);
	}
	if (ip->vp && (ip->flags & HAMMER_INODE_MODMASK) == 0)
		vclrisdirty(ip->vp);
	lwkt_reltoken(&hmp->fs_token);
	return (ip->error);
}

/*
 * hammer_vop_read { vp, uio, ioflag, cred }
 *
 * MPSAFE (for the cache safe does not require fs_token)
 */
static
int
hammer_vop_read(struct vop_read_args *ap)
{
	struct hammer_transaction trans;
	hammer_inode_t ip;
	hammer_mount_t hmp;
	off_t offset;
	struct buf *bp;
	struct uio *uio;
	int error;
	int n;
	int seqcount;
	int ioseqcount;
	int blksize;
	int bigread;
	int got_trans;
	size_t resid;

	if (ap->a_vp->v_type == VDIR)
		return (EISDIR);
	if (ap->a_vp->v_type != VREG)
		return (EINVAL);
	ip = VTOI(ap->a_vp);
	hmp = ip->hmp;
	error = 0;
	got_trans = 0;
	uio = ap->a_uio;

	/*
	 * Attempt to shortcut directly to the VM object using lwbufs.
	 * This is much faster than instantiating buffer cache buffers.
	 */
	resid = uio->uio_resid;
	error = vop_helper_read_shortcut(ap);
	hammer_stats_file_read += resid - uio->uio_resid;
	if (error)
		return (error);
	if (uio->uio_resid == 0)
		goto finished;

	/*
	 * Allow the UIO's size to override the sequential heuristic.
	 */
	blksize = hammer_blocksize(uio->uio_offset);
	seqcount = howmany(uio->uio_resid, MAXBSIZE);
	ioseqcount = ap->a_ioflag >> IO_SEQSHIFT;
	if (seqcount < ioseqcount)
		seqcount = ioseqcount;

	/*
	 * If reading or writing a huge amount of data we have to break
	 * atomicy and allow the operation to be interrupted by a signal
	 * or it can DOS the machine.
	 */
	bigread = (uio->uio_resid > 100 * 1024 * 1024);

	/*
	 * Access the data typically in HAMMER_BUFSIZE blocks via the
	 * buffer cache, but HAMMER may use a variable block size based
	 * on the offset.
	 *
	 * XXX Temporary hack, delay the start transaction while we remain
	 *     MPSAFE.  NOTE: ino_data.size cannot change while vnode is
	 *     locked-shared.
	 */
	while (uio->uio_resid > 0 && uio->uio_offset < ip->ino_data.size) {
		int64_t base_offset;
		int64_t file_limit;

		blksize = hammer_blocksize(uio->uio_offset);
		offset = (int)uio->uio_offset & (blksize - 1);
		base_offset = uio->uio_offset - offset;

		if (bigread && (error = hammer_signal_check(ip->hmp)) != 0)
			break;

		/*
		 * MPSAFE
		 */
		bp = getblk(ap->a_vp, base_offset, blksize, 0, 0);
		if ((bp->b_flags & (B_INVAL | B_CACHE | B_RAM)) == B_CACHE) {
			bp->b_flags &= ~B_AGE;
			error = 0;
			goto skip;
		}
		if (ap->a_ioflag & IO_NRDELAY) {
			bqrelse(bp);
			return (EWOULDBLOCK);
		}

		/*
		 * MPUNSAFE
		 */
		if (got_trans == 0) {
			hammer_start_transaction(&trans, ip->hmp);
			got_trans = 1;
		}

		/*
		 * NOTE: A valid bp has already been acquired, but was not
		 *	 B_CACHE.
		 */
		if (hammer_cluster_enable) {
			/*
			 * Use file_limit to prevent cluster_read() from
			 * creating buffers of the wrong block size past
			 * the demarc.
			 */
			file_limit = ip->ino_data.size;
			if (base_offset < HAMMER_XDEMARC &&
			    file_limit > HAMMER_XDEMARC) {
				file_limit = HAMMER_XDEMARC;
			}
			error = cluster_readx(ap->a_vp,
					     file_limit, base_offset,
					     blksize, B_NOTMETA,
					     uio->uio_resid,
					     seqcount * MAXBSIZE,
					     &bp);
		} else {
			error = breadnx(ap->a_vp, base_offset,
					blksize, B_NOTMETA,
					NULL, NULL, 0, &bp);
		}
		if (error) {
			brelse(bp);
			break;
		}
skip:
		if ((hammer_debug_io & 0x0001) && (bp->b_flags & B_IOISSUED)) {
			hdkprintf("zone2_offset %016jx read file %016jx@%016jx\n",
				(intmax_t)bp->b_bio2.bio_offset,
				(intmax_t)ip->obj_id,
				(intmax_t)bp->b_loffset);
		}
		bp->b_flags &= ~B_IOISSUED;
		if (blksize == HAMMER_XBUFSIZE)
			bp->b_flags |= B_CLUSTEROK;

		n = blksize - offset;
		if (n > uio->uio_resid)
			n = uio->uio_resid;
		if (n > ip->ino_data.size - uio->uio_offset)
			n = (int)(ip->ino_data.size - uio->uio_offset);

		/*
		 * Set B_AGE, data has a lower priority than meta-data.
		 *
		 * Use a hold/unlock/drop sequence to run the uiomove
		 * with the buffer unlocked, avoiding deadlocks against
		 * read()s on mmap()'d spaces.
		 */
		bp->b_flags |= B_AGE;
		error = uiomovebp(bp, (char *)bp->b_data + offset, n, uio);
		bqrelse(bp);

		if (error)
			break;
		hammer_stats_file_read += n;
	}

finished:

	/*
	 * Try to update the atime with just the inode lock for maximum
	 * concurrency.  If we can't shortcut it we have to get the full
	 * blown transaction.
	 */
	if (got_trans == 0 && hammer_update_atime_quick(ip) < 0) {
		hammer_start_transaction(&trans, ip->hmp);
		got_trans = 1;
	}

	if (got_trans) {
		if ((ip->flags & HAMMER_INODE_RO) == 0 &&
		    (ip->hmp->mp->mnt_flag & MNT_NOATIME) == 0) {
			lwkt_gettoken(&hmp->fs_token);
			ip->ino_data.atime = trans.time;
			hammer_modify_inode(&trans, ip, HAMMER_INODE_ATIME);
			hammer_done_transaction(&trans);
			lwkt_reltoken(&hmp->fs_token);
		} else {
			hammer_done_transaction(&trans);
		}
	}
	return (error);
}

/*
 * hammer_vop_write { vp, uio, ioflag, cred }
 */
static
int
hammer_vop_write(struct vop_write_args *ap)
{
	struct hammer_transaction trans;
	hammer_inode_t ip;
	hammer_mount_t hmp;
	thread_t td;
	struct vnode *vp;
	struct uio *uio;
	int offset;
	off_t base_offset;
	int64_t cluster_eof;
	struct buf *bp;
	int kflags;
	int error;
	int n;
	int flags;
	int seqcount;
	int bigwrite;

	vp = ap->a_vp;
	if (vp->v_type != VREG)
		return (EINVAL);
	ip = VTOI(ap->a_vp);
	hmp = ip->hmp;
	error = 0;
	kflags = 0;
	seqcount = ap->a_ioflag >> IO_SEQSHIFT;

	if (ip->flags & HAMMER_INODE_RO)
		return (EROFS);

	/*
	 * Create a transaction to cover the operations we perform.
	 */
	hammer_start_transaction(&trans, hmp);
	uio = ap->a_uio;

	/*
	 * Use v_lastwrite_ts if file not open for writing
	 * (i.e. a late msync)
	 */
	if (uio->uio_segflg == UIO_NOCOPY) {
		if (vp->v_flag & VLASTWRITETS) {
			trans.time = vp->v_lastwrite_ts.tv_sec * 1000000 +
				     vp->v_lastwrite_ts.tv_nsec / 1000;
		} else {
			trans.time = ip->ino_data.mtime;
		}
	} else {
		vclrflags(vp, VLASTWRITETS);
	}

	/*
	 * Check append mode
	 */
	if (ap->a_ioflag & IO_APPEND)
		uio->uio_offset = ip->ino_data.size;

	/*
	 * Check for illegal write offsets.  Valid range is 0...2^63-1.
	 *
	 * NOTE: the base_off assignment is required to work around what
	 * I consider to be a GCC-4 optimization bug.
	 */
	if (uio->uio_offset < 0) {
		hammer_done_transaction(&trans);
		return (EFBIG);
	}
	base_offset = uio->uio_offset + uio->uio_resid;	/* work around gcc-4 */
	if (uio->uio_resid > 0 && base_offset <= uio->uio_offset) {
		hammer_done_transaction(&trans);
		return (EFBIG);
	}

	if (uio->uio_resid > 0 && (td = uio->uio_td) != NULL && td->td_proc &&
	    base_offset > td->td_proc->p_rlimit[RLIMIT_FSIZE].rlim_cur) {
		hammer_done_transaction(&trans);
		lwpsignal(td->td_proc, td->td_lwp, SIGXFSZ);
		return (EFBIG);
	}

	/*
	 * If reading or writing a huge amount of data we have to break
	 * atomicy and allow the operation to be interrupted by a signal
	 * or it can DOS the machine.
	 *
	 * Preset redo_count so we stop generating REDOs earlier if the
	 * limit is exceeded.
	 *
	 * redo_count is heuristical, SMP races are ok
	 */
	bigwrite = (uio->uio_resid > 100 * 1024 * 1024);
	if ((ip->flags & HAMMER_INODE_REDO) &&
	    ip->redo_count < hammer_limit_redo) {
		ip->redo_count += uio->uio_resid;
	}

	/*
	 * Access the data typically in HAMMER_BUFSIZE blocks via the
	 * buffer cache, but HAMMER may use a variable block size based
	 * on the offset.
	 */
	while (uio->uio_resid > 0) {
		int fixsize = 0;
		int blksize;
		int blkmask;
		int trivial;
		int endofblk;
		off_t nsize;

		if ((error = hammer_checkspace(hmp, HAMMER_CHKSPC_WRITE)) != 0)
			break;
		if (bigwrite && (error = hammer_signal_check(hmp)) != 0)
			break;

		blksize = hammer_blocksize(uio->uio_offset);

		/*
		 * Control the number of pending records associated with
		 * this inode.  If too many have accumulated start a
		 * flush.  Try to maintain a pipeline with the flusher.
		 *
		 * NOTE: It is possible for other sources to grow the
		 *	 records but not necessarily issue another flush,
		 *	 so use a timeout and ensure that a re-flush occurs.
		 */
		if (ip->rsv_recs >= hammer_limit_inode_recs) {
			lwkt_gettoken(&hmp->fs_token);
			hammer_flush_inode(ip, HAMMER_FLUSH_SIGNAL);
			while (ip->rsv_recs >= hammer_limit_inode_recs * 2) {
				ip->flags |= HAMMER_INODE_RECSW;
				tsleep(&ip->rsv_recs, 0, "hmrwww", hz);
				hammer_flush_inode(ip, HAMMER_FLUSH_SIGNAL);
			}
			lwkt_reltoken(&hmp->fs_token);
		}

		/*
		 * Do not allow HAMMER to blow out the buffer cache.  Very
		 * large UIOs can lockout other processes due to bwillwrite()
		 * mechanics.
		 *
		 * The hammer inode is not locked during these operations.
		 * The vnode is locked which can interfere with the pageout
		 * daemon for non-UIO_NOCOPY writes but should not interfere
		 * with the buffer cache.  Even so, we cannot afford to
		 * allow the pageout daemon to build up too many dirty buffer
		 * cache buffers.
		 *
		 * Only call this if we aren't being recursively called from
		 * a virtual disk device (vn), else we may deadlock.
		 */
		if ((ap->a_ioflag & IO_RECURSE) == 0)
			bwillwrite(blksize);

		/*
		 * Calculate the blocksize at the current offset and figure
		 * out how much we can actually write.
		 */
		blkmask = blksize - 1;
		offset = (int)uio->uio_offset & blkmask;
		base_offset = uio->uio_offset & ~(int64_t)blkmask;
		n = blksize - offset;
		if (n > uio->uio_resid) {
			n = uio->uio_resid;
			endofblk = 0;
		} else {
			endofblk = 1;
		}
		nsize = uio->uio_offset + n;
		if (nsize > ip->ino_data.size) {
			if (uio->uio_offset > ip->ino_data.size)
				trivial = 0;
			else
				trivial = NVEXTF_TRIVIAL;
			nvextendbuf(ap->a_vp,
				    ip->ino_data.size,
				    nsize,
				    hammer_blocksize(ip->ino_data.size),
				    hammer_blocksize(nsize),
				    hammer_blockoff(ip->ino_data.size),
				    hammer_blockoff(nsize),
				    trivial);
			fixsize = 1;
			kflags |= NOTE_EXTEND;
		}

		if (uio->uio_segflg == UIO_NOCOPY) {
			/*
			 * Issuing a write with the same data backing the
			 * buffer.  Instantiate the buffer to collect the
			 * backing vm pages, then read-in any missing bits.
			 *
			 * This case is used by vop_stdputpages().
			 */
			bp = getblk(ap->a_vp, base_offset,
				    blksize, GETBLK_BHEAVY, 0);
			if ((bp->b_flags & B_CACHE) == 0) {
				bqrelse(bp);
				error = bread(ap->a_vp, base_offset,
					      blksize, &bp);
			}
		} else if (offset == 0 && uio->uio_resid >= blksize) {
			/*
			 * Even though we are entirely overwriting the buffer
			 * we may still have to zero it out to avoid a
			 * mmap/write visibility issue.
			 */
			bp = getblk(ap->a_vp, base_offset, blksize, GETBLK_BHEAVY, 0);
			if ((bp->b_flags & B_CACHE) == 0)
				vfs_bio_clrbuf(bp);
		} else if (base_offset >= ip->ino_data.size) {
			/*
			 * If the base offset of the buffer is beyond the
			 * file EOF, we don't have to issue a read.
			 */
			bp = getblk(ap->a_vp, base_offset,
				    blksize, GETBLK_BHEAVY, 0);
			vfs_bio_clrbuf(bp);
		} else {
			/*
			 * Partial overwrite, read in any missing bits then
			 * replace the portion being written.
			 */
			error = bread(ap->a_vp, base_offset, blksize, &bp);
			if (error == 0)
				bheavy(bp);
		}
		if (error == 0)
			error = uiomovebp(bp, bp->b_data + offset, n, uio);

		lwkt_gettoken(&hmp->fs_token);

		/*
		 * Generate REDO records if enabled and redo_count will not
		 * exceeded the limit.
		 *
		 * If redo_count exceeds the limit we stop generating records
		 * and clear HAMMER_INODE_REDO.  This will cause the next
		 * fsync() to do a full meta-data sync instead of just an
		 * UNDO/REDO fifo update.
		 *
		 * When clearing HAMMER_INODE_REDO any pre-existing REDOs
		 * will still be tracked.  The tracks will be terminated
		 * when the related meta-data (including possible data
		 * modifications which are not tracked via REDO) is
		 * flushed.
		 */
		if ((ip->flags & HAMMER_INODE_REDO) && error == 0) {
			if (ip->redo_count < hammer_limit_redo) {
				bp->b_flags |= B_VFSFLAG1;
				error = hammer_generate_redo(&trans, ip,
						     base_offset + offset,
						     HAMMER_REDO_WRITE,
						     bp->b_data + offset,
						     (size_t)n);
			} else {
				ip->flags &= ~HAMMER_INODE_REDO;
			}
		}

		/*
		 * If we screwed up we have to undo any VM size changes we
		 * made.
		 */
		if (error) {
			brelse(bp);
			if (fixsize) {
				nvtruncbuf(ap->a_vp, ip->ino_data.size,
					  hammer_blocksize(ip->ino_data.size),
					  hammer_blockoff(ip->ino_data.size),
					  0);
			}
			lwkt_reltoken(&hmp->fs_token);
			break;
		}
		kflags |= NOTE_WRITE;
		hammer_stats_file_write += n;
		if (blksize == HAMMER_XBUFSIZE)
			bp->b_flags |= B_CLUSTEROK;
		if (ip->ino_data.size < uio->uio_offset) {
			ip->ino_data.size = uio->uio_offset;
			flags = HAMMER_INODE_SDIRTY;
		} else {
			flags = 0;
		}
		ip->ino_data.mtime = trans.time;
		flags |= HAMMER_INODE_MTIME | HAMMER_INODE_BUFS;
		hammer_modify_inode(&trans, ip, flags);

		/*
		 * Once we dirty the buffer any cached zone-X offset
		 * becomes invalid.  HAMMER NOTE: no-history mode cannot
		 * allow overwriting over the same data sector unless
		 * we provide UNDOs for the old data, which we don't.
		 */
		bp->b_bio2.bio_offset = NOOFFSET;

		lwkt_reltoken(&hmp->fs_token);

		/*
		 * Final buffer disposition.
		 *
		 * Because meta-data updates are deferred, HAMMER is
		 * especially sensitive to excessive bdwrite()s because
		 * the I/O stream is not broken up by disk reads.  So the
		 * buffer cache simply cannot keep up.
		 *
		 * WARNING!  blksize is variable.  cluster_write() is
		 *	     expected to not blow up if it encounters
		 *	     buffers that do not match the passed blksize.
		 *
		 * NOTE!  Hammer shouldn't need to bawrite()/cluster_write().
		 *	  The ip->rsv_recs check should burst-flush the data.
		 *	  If we queue it immediately the buf could be left
		 *	  locked on the device queue for a very long time.
		 *
		 *	  However, failing to flush a dirty buffer out when
		 *        issued from the pageout daemon can result in a low
		 *        memory deadlock against bio_page_alloc(), so we
		 *	  have to bawrite() on IO_ASYNC as well.
		 *
		 * NOTE!  To avoid degenerate stalls due to mismatched block
		 *	  sizes we only honor IO_DIRECT on the write which
		 *	  abuts the end of the buffer.  However, we must
		 *	  honor IO_SYNC in case someone is silly enough to
		 *	  configure a HAMMER file as swap, or when HAMMER
		 *	  is serving NFS (for commits).  Ick ick.
		 */
		bp->b_flags |= B_AGE;
		if (blksize == HAMMER_XBUFSIZE)
			bp->b_flags |= B_CLUSTEROK;

		if (ap->a_ioflag & IO_SYNC) {
			bwrite(bp);
		} else if ((ap->a_ioflag & IO_DIRECT) && endofblk) {
			bawrite(bp);
		} else if (ap->a_ioflag & IO_ASYNC) {
			bawrite(bp);
		} else if (hammer_cluster_enable &&
			   !(ap->a_vp->v_mount->mnt_flag & MNT_NOCLUSTERW)) {
			if (base_offset < HAMMER_XDEMARC)
				cluster_eof = hammer_blockdemarc(base_offset,
							 ip->ino_data.size);
			else
				cluster_eof = ip->ino_data.size;
			cluster_write(bp, cluster_eof, blksize, seqcount);
		} else {
			bdwrite(bp);
		}
	}
	hammer_done_transaction(&trans);
	hammer_knote(ap->a_vp, kflags);

	return (error);
}

/*
 * hammer_vop_access { vp, mode, cred }
 *
 * MPSAFE - does not require fs_token
 */
static
int
hammer_vop_access(struct vop_access_args *ap)
{
	hammer_inode_t ip = VTOI(ap->a_vp);
	uid_t uid;
	gid_t gid;
	int error;

	uid = hammer_to_unix_xid(&ip->ino_data.uid);
	gid = hammer_to_unix_xid(&ip->ino_data.gid);

	error = vop_helper_access(ap, uid, gid, ip->ino_data.mode,
				  ip->ino_data.uflags);
	return (error);
}

/*
 * hammer_vop_close { vp, fflag }
 *
 * We can only sync-on-close for normal closes.  XXX disabled for now.
 */
static
int
hammer_vop_close(struct vop_close_args *ap)
{
#if 0
	struct vnode *vp = ap->a_vp;
	hammer_inode_t ip = VTOI(vp);
	int waitfor;
	if (ip->flags & (HAMMER_INODE_CLOSESYNC|HAMMER_INODE_CLOSEASYNC)) {
		if (vn_islocked(vp) == LK_EXCLUSIVE &&
		    (vp->v_flag & (VINACTIVE|VRECLAIMED)) == 0) {
			if (ip->flags & HAMMER_INODE_CLOSESYNC)
				waitfor = MNT_WAIT;
			else
				waitfor = MNT_NOWAIT;
			ip->flags &= ~(HAMMER_INODE_CLOSESYNC |
				       HAMMER_INODE_CLOSEASYNC);
			VOP_FSYNC(vp, MNT_NOWAIT, waitfor);
		}
	}
#endif
	return (vop_stdclose(ap));
}

/*
 * hammer_vop_ncreate { nch, dvp, vpp, cred, vap }
 *
 * The operating system has already ensured that the directory entry
 * does not exist and done all appropriate namespace locking.
 */
static
int
hammer_vop_ncreate(struct vop_ncreate_args *ap)
{
	struct hammer_transaction trans;
	hammer_inode_t dip;
	hammer_inode_t nip;
	struct nchandle *nch;
	hammer_mount_t hmp;
	int error;

	nch = ap->a_nch;
	dip = VTOI(ap->a_dvp);
	hmp = dip->hmp;

	if (dip->flags & HAMMER_INODE_RO)
		return (EROFS);
	if ((error = hammer_checkspace(hmp, HAMMER_CHKSPC_CREATE)) != 0)
		return (error);

	/*
	 * Create a transaction to cover the operations we perform.
	 */
	lwkt_gettoken(&hmp->fs_token);
	hammer_start_transaction(&trans, hmp);

	/*
	 * Create a new filesystem object of the requested type.  The
	 * returned inode will be referenced and shared-locked to prevent
	 * it from being moved to the flusher.
	 */
	error = hammer_create_inode(&trans, ap->a_vap, ap->a_cred,
				    dip, nch->ncp->nc_name, nch->ncp->nc_nlen,
				    NULL, &nip);
	if (error) {
		hkprintf("hammer_create_inode error %d\n", error);
		hammer_done_transaction(&trans);
		*ap->a_vpp = NULL;
		lwkt_reltoken(&hmp->fs_token);
		return (error);
	}

	/*
	 * Add the new filesystem object to the directory.  This will also
	 * bump the inode's link count.
	 */
	error = hammer_ip_add_direntry(&trans, dip,
					nch->ncp->nc_name, nch->ncp->nc_nlen,
					nip);
	if (error)
		hkprintf("hammer_ip_add_direntry error %d\n", error);

	/*
	 * Finish up.
	 */
	if (error) {
		hammer_rel_inode(nip, 0);
		hammer_done_transaction(&trans);
		*ap->a_vpp = NULL;
	} else {
		error = hammer_get_vnode(nip, ap->a_vpp);
		hammer_done_transaction(&trans);
		hammer_rel_inode(nip, 0);
		if (error == 0) {
			cache_setunresolved(ap->a_nch);
			cache_setvp(ap->a_nch, *ap->a_vpp);
		}
		hammer_knote(ap->a_dvp, NOTE_WRITE);
	}
	lwkt_reltoken(&hmp->fs_token);
	return (error);
}

/*
 * hammer_vop_getattr { vp, vap }
 *
 * Retrieve an inode's attribute information.  When accessing inodes
 * historically we fake the atime field to ensure consistent results.
 * The atime field is stored in the B-Tree element and allowed to be
 * updated without cycling the element.
 *
 * MPSAFE - does not require fs_token
 */
static
int
hammer_vop_getattr(struct vop_getattr_args *ap)
{
	hammer_inode_t ip = VTOI(ap->a_vp);
	struct vattr *vap = ap->a_vap;

	/*
	 * We want the fsid to be different when accessing a filesystem
	 * with different as-of's so programs like diff don't think
	 * the files are the same.
	 *
	 * We also want the fsid to be the same when comparing snapshots,
	 * or when comparing mirrors (which might be backed by different
	 * physical devices).  HAMMER fsids are based on the PFS's
	 * shared_uuid field.
	 *
	 * XXX there is a chance of collision here.  The va_fsid reported
	 * by stat is different from the more involved fsid used in the
	 * mount structure.
	 */
	hammer_lock_sh(&ip->lock);
	vap->va_fsid = ip->pfsm->fsid_udev ^ (uint32_t)ip->obj_asof ^
		       (uint32_t)(ip->obj_asof >> 32);

	vap->va_fileid = ip->ino_leaf.base.obj_id;
	vap->va_mode = ip->ino_data.mode;
	vap->va_nlink = ip->ino_data.nlinks;
	vap->va_uid = hammer_to_unix_xid(&ip->ino_data.uid);
	vap->va_gid = hammer_to_unix_xid(&ip->ino_data.gid);
	vap->va_rmajor = 0;
	vap->va_rminor = 0;
	vap->va_size = ip->ino_data.size;

	/*
	 * Special case for @@PFS softlinks.  The actual size of the
	 * expanded softlink is "@@0x%016llx:%05d" == 26 bytes.
	 * or for MAX_TID is    "@@-1:%05d" == 10 bytes.
	 *
	 * Note that userspace hammer command does not allow users to
	 * create a @@PFS softlink under an existing other PFS (id!=0)
	 * so the ip localization here for @@PFS softlink is always 0.
	 */
	if (ip->ino_data.obj_type == HAMMER_OBJTYPE_SOFTLINK &&
	    ip->ino_data.size == 10 &&
	    ip->obj_asof == HAMMER_MAX_TID &&
	    ip->obj_localization == HAMMER_DEF_LOCALIZATION &&
	    strncmp(ip->ino_data.ext.symlink, "@@PFS", 5) == 0) {
		if (hammer_is_pfs_slave(&ip->pfsm->pfsd))
			vap->va_size = 26;
		else
			vap->va_size = 10;
	}

	/*
	 * We must provide a consistent atime and mtime for snapshots
	 * so people can do a 'tar cf - ... | md5' on them and get
	 * consistent results.
	 */
	if (ip->flags & HAMMER_INODE_RO) {
		hammer_time_to_timespec(ip->ino_data.ctime, &vap->va_atime);
		hammer_time_to_timespec(ip->ino_data.ctime, &vap->va_mtime);
	} else {
		hammer_time_to_timespec(ip->ino_data.atime, &vap->va_atime);
		hammer_time_to_timespec(ip->ino_data.mtime, &vap->va_mtime);
	}
	hammer_time_to_timespec(ip->ino_data.ctime, &vap->va_ctime);
	vap->va_flags = ip->ino_data.uflags;
	vap->va_gen = 1;	/* hammer inums are unique for all time */
	vap->va_blocksize = HAMMER_BUFSIZE;
	if (ip->ino_data.size >= HAMMER_XDEMARC) {
		vap->va_bytes = HAMMER_XBUFSIZE64_DOALIGN(ip->ino_data.size);
	} else if (ip->ino_data.size > HAMMER_HBUFSIZE) {
		vap->va_bytes = HAMMER_BUFSIZE64_DOALIGN(ip->ino_data.size);
	} else {
		vap->va_bytes = HAMMER_DATA_DOALIGN(ip->ino_data.size);
	}

	vap->va_type = hammer_get_vnode_type(ip->ino_data.obj_type);
	vap->va_filerev = 0;	/* XXX */
	vap->va_uid_uuid = ip->ino_data.uid;
	vap->va_gid_uuid = ip->ino_data.gid;
	vap->va_fsid_uuid = ip->hmp->fsid;
	vap->va_vaflags = VA_UID_UUID_VALID | VA_GID_UUID_VALID |
			  VA_FSID_UUID_VALID;

	switch (ip->ino_data.obj_type) {
	case HAMMER_OBJTYPE_CDEV:
	case HAMMER_OBJTYPE_BDEV:
		vap->va_rmajor = ip->ino_data.rmajor;
		vap->va_rminor = ip->ino_data.rminor;
		break;
	default:
		break;
	}
	hammer_unlock(&ip->lock);
	return(0);
}

/*
 * hammer_vop_nresolve { nch, dvp, cred }
 *
 * Locate the requested directory entry.
 */
static
int
hammer_vop_nresolve(struct vop_nresolve_args *ap)
{
	struct hammer_transaction trans;
	struct namecache *ncp;
	hammer_mount_t hmp;
	hammer_inode_t dip;
	hammer_inode_t ip;
	hammer_tid_t asof;
	struct hammer_cursor cursor;
	struct vnode *vp;
	int64_t namekey;
	int error;
	int i;
	int nlen;
	int flags;
	int ispfs;
	int64_t obj_id;
	uint32_t localization;
	uint32_t max_iterations;

	/*
	 * Misc initialization, plus handle as-of name extensions.  Look for
	 * the '@@' extension.  Note that as-of files and directories cannot
	 * be modified.
	 */
	dip = VTOI(ap->a_dvp);
	ncp = ap->a_nch->ncp;
	asof = dip->obj_asof;
	localization = dip->obj_localization;	/* for code consistency */
	nlen = ncp->nc_nlen;
	flags = dip->flags & HAMMER_INODE_RO;
	ispfs = 0;
	hmp = dip->hmp;

	lwkt_gettoken(&hmp->fs_token);
	hammer_simple_transaction(&trans, hmp);

	for (i = 0; i < nlen; ++i) {
		if (ncp->nc_name[i] == '@' && ncp->nc_name[i+1] == '@') {
			error = hammer_str_to_tid(ncp->nc_name + i + 2,
						  &ispfs, &asof, &localization);
			if (error != 0) {
				i = nlen;
				break;
			}
			if (asof != HAMMER_MAX_TID)
				flags |= HAMMER_INODE_RO;
			break;
		}
	}
	nlen = i;

	/*
	 * If this is a PFS we dive into the PFS root inode
	 */
	if (ispfs && nlen == 0) {
		ip = hammer_get_inode(&trans, dip, HAMMER_OBJID_ROOT,
				      asof, localization,
				      flags, &error);
		if (error == 0) {
			error = hammer_get_vnode(ip, &vp);
			hammer_rel_inode(ip, 0);
		} else {
			vp = NULL;
		}
		if (error == 0) {
			vn_unlock(vp);
			cache_setvp(ap->a_nch, vp);
			vrele(vp);
		}
		goto done;
	}

	/*
	 * If there is no path component the time extension is relative to dip.
	 * e.g. "fubar/@@<snapshot>"
	 *
	 * "." is handled by the kernel, but ".@@<snapshot>" is not.
	 * e.g. "fubar/.@@<snapshot>"
	 *
	 * ".." is handled by the kernel.  We do not currently handle
	 * "..@<snapshot>".
	 */
	if (nlen == 0 || (nlen == 1 && ncp->nc_name[0] == '.')) {
		ip = hammer_get_inode(&trans, dip, dip->obj_id,
				      asof, dip->obj_localization,
				      flags, &error);
		if (error == 0) {
			error = hammer_get_vnode(ip, &vp);
			hammer_rel_inode(ip, 0);
		} else {
			vp = NULL;
		}
		if (error == 0) {
			vn_unlock(vp);
			cache_setvp(ap->a_nch, vp);
			vrele(vp);
		}
		goto done;
	}

	/*
	 * Calculate the namekey and setup the key range for the scan.  This
	 * works kinda like a chained hash table where the lower 32 bits
	 * of the namekey synthesize the chain.
	 *
	 * The key range is inclusive of both key_beg and key_end.
	 */
	namekey = hammer_direntry_namekey(dip, ncp->nc_name, nlen,
					   &max_iterations);

	error = hammer_init_cursor(&trans, &cursor, &dip->cache[1], dip);
	cursor.key_beg.localization = dip->obj_localization |
				      hammer_dir_localization(dip);
        cursor.key_beg.obj_id = dip->obj_id;
	cursor.key_beg.key = namekey;
        cursor.key_beg.create_tid = 0;
        cursor.key_beg.delete_tid = 0;
        cursor.key_beg.rec_type = HAMMER_RECTYPE_DIRENTRY;
        cursor.key_beg.obj_type = 0;

	cursor.key_end = cursor.key_beg;
	cursor.key_end.key += max_iterations;
	cursor.asof = asof;
	cursor.flags |= HAMMER_CURSOR_END_INCLUSIVE | HAMMER_CURSOR_ASOF;

	/*
	 * Scan all matching records (the chain), locate the one matching
	 * the requested path component.
	 *
	 * The hammer_ip_*() functions merge in-memory records with on-disk
	 * records for the purposes of the search.
	 */
	obj_id = 0;
	localization = HAMMER_DEF_LOCALIZATION;

	if (error == 0) {
		error = hammer_ip_first(&cursor);
		while (error == 0) {
			error = hammer_ip_resolve_data(&cursor);
			if (error)
				break;
			if (nlen == cursor.leaf->data_len - HAMMER_ENTRY_NAME_OFF &&
			    bcmp(ncp->nc_name, cursor.data->entry.name, nlen) == 0) {
				obj_id = cursor.data->entry.obj_id;
				localization = cursor.data->entry.localization;
				break;
			}
			error = hammer_ip_next(&cursor);
		}
	}
	hammer_done_cursor(&cursor);

	/*
	 * Lookup the obj_id.  This should always succeed.  If it does not
	 * the filesystem may be damaged and we return a dummy inode.
	 */
	if (error == 0) {
		ip = hammer_get_inode(&trans, dip, obj_id,
				      asof, localization,
				      flags, &error);
		if (error == ENOENT) {
			hkprintf("WARNING: Missing inode for dirent \"%s\"\n"
				"\tobj_id = %016jx, asof=%016jx, lo=%08x\n",
				ncp->nc_name,
				(intmax_t)obj_id, (intmax_t)asof,
				localization);
			error = 0;
			ip = hammer_get_dummy_inode(&trans, dip, obj_id,
						    asof, localization,
						    flags, &error);
		}
		if (error == 0) {
			error = hammer_get_vnode(ip, &vp);
			hammer_rel_inode(ip, 0);
		} else {
			vp = NULL;
		}
		if (error == 0) {
			vn_unlock(vp);
			cache_setvp(ap->a_nch, vp);
			vrele(vp);
		}
	} else if (error == ENOENT) {
		cache_setvp(ap->a_nch, NULL);
	}
done:
	hammer_done_transaction(&trans);
	lwkt_reltoken(&hmp->fs_token);
	return (error);
}

/*
 * hammer_vop_nlookupdotdot { dvp, vpp, cred }
 *
 * Locate the parent directory of a directory vnode.
 *
 * dvp is referenced but not locked.  *vpp must be returned referenced and
 * locked.  A parent_obj_id of 0 indicates that we are at the root.
 *
 * NOTE: as-of sequences are not linked into the directory structure.  If
 * we are at the root with a different asof then the mount point, reload
 * the same directory with the mount point's asof.   I'm not sure what this
 * will do to NFS.  We encode ASOF stamps in NFS file handles so it might not
 * get confused, but it hasn't been tested.
 */
static
int
hammer_vop_nlookupdotdot(struct vop_nlookupdotdot_args *ap)
{
	struct hammer_transaction trans;
	hammer_inode_t dip;
	hammer_inode_t ip;
	hammer_mount_t hmp;
	int64_t parent_obj_id;
	uint32_t parent_obj_localization;
	hammer_tid_t asof;
	int error;

	dip = VTOI(ap->a_dvp);
	asof = dip->obj_asof;
	hmp = dip->hmp;

	/*
	 * Whos are parent?  This could be the root of a pseudo-filesystem
	 * whos parent is in another localization domain.
	 */
	lwkt_gettoken(&hmp->fs_token);
	parent_obj_id = dip->ino_data.parent_obj_id;
	if (dip->obj_id == HAMMER_OBJID_ROOT)
		parent_obj_localization = HAMMER_DEF_LOCALIZATION;
	else
		parent_obj_localization = dip->obj_localization;

	/*
	 * It's probably a PFS root when dip->ino_data.parent_obj_id is 0.
	 */
	if (parent_obj_id == 0) {
		if (dip->obj_id == HAMMER_OBJID_ROOT &&
		   asof != hmp->asof) {
			parent_obj_id = dip->obj_id;
			asof = hmp->asof;
			*ap->a_fakename = kmalloc(19, M_TEMP, M_WAITOK);
			ksnprintf(*ap->a_fakename, 19, "0x%016jx",
				  (intmax_t)dip->obj_asof);
		} else {
			*ap->a_vpp = NULL;
			lwkt_reltoken(&hmp->fs_token);
			return ENOENT;
		}
	}

	hammer_simple_transaction(&trans, hmp);

	ip = hammer_get_inode(&trans, dip, parent_obj_id,
			      asof, parent_obj_localization,
			      dip->flags, &error);
	if (ip) {
		error = hammer_get_vnode(ip, ap->a_vpp);
		hammer_rel_inode(ip, 0);
	} else {
		*ap->a_vpp = NULL;
	}
	hammer_done_transaction(&trans);
	lwkt_reltoken(&hmp->fs_token);
	return (error);
}

/*
 * hammer_vop_nlink { nch, dvp, vp, cred }
 */
static
int
hammer_vop_nlink(struct vop_nlink_args *ap)
{
	struct hammer_transaction trans;
	hammer_inode_t dip;
	hammer_inode_t ip;
	struct nchandle *nch;
	hammer_mount_t hmp;
	int error;

	if (ap->a_dvp->v_mount != ap->a_vp->v_mount)
		return(EXDEV);

	nch = ap->a_nch;
	dip = VTOI(ap->a_dvp);
	ip = VTOI(ap->a_vp);
	hmp = dip->hmp;

	if (dip->obj_localization != ip->obj_localization)
		return(EXDEV);

	if (dip->flags & HAMMER_INODE_RO)
		return (EROFS);
	if (ip->flags & HAMMER_INODE_RO)
		return (EROFS);
	if ((error = hammer_checkspace(hmp, HAMMER_CHKSPC_CREATE)) != 0)
		return (error);

	/*
	 * Create a transaction to cover the operations we perform.
	 */
	lwkt_gettoken(&hmp->fs_token);
	hammer_start_transaction(&trans, hmp);

	/*
	 * Add the filesystem object to the directory.  Note that neither
	 * dip nor ip are referenced or locked, but their vnodes are
	 * referenced.  This function will bump the inode's link count.
	 */
	error = hammer_ip_add_direntry(&trans, dip,
					nch->ncp->nc_name, nch->ncp->nc_nlen,
					ip);

	/*
	 * Finish up.
	 */
	if (error == 0) {
		cache_setunresolved(nch);
		cache_setvp(nch, ap->a_vp);
	}
	hammer_done_transaction(&trans);
	hammer_knote(ap->a_vp, NOTE_LINK);
	hammer_knote(ap->a_dvp, NOTE_WRITE);
	lwkt_reltoken(&hmp->fs_token);
	return (error);
}

/*
 * hammer_vop_nmkdir { nch, dvp, vpp, cred, vap }
 *
 * The operating system has already ensured that the directory entry
 * does not exist and done all appropriate namespace locking.
 */
static
int
hammer_vop_nmkdir(struct vop_nmkdir_args *ap)
{
	struct hammer_transaction trans;
	hammer_inode_t dip;
	hammer_inode_t nip;
	struct nchandle *nch;
	hammer_mount_t hmp;
	int error;

	nch = ap->a_nch;
	dip = VTOI(ap->a_dvp);
	hmp = dip->hmp;

	if (dip->flags & HAMMER_INODE_RO)
		return (EROFS);
	if ((error = hammer_checkspace(hmp, HAMMER_CHKSPC_CREATE)) != 0)
		return (error);

	/*
	 * Create a transaction to cover the operations we perform.
	 */
	lwkt_gettoken(&hmp->fs_token);
	hammer_start_transaction(&trans, hmp);

	/*
	 * Create a new filesystem object of the requested type.  The
	 * returned inode will be referenced but not locked.
	 */
	error = hammer_create_inode(&trans, ap->a_vap, ap->a_cred,
				    dip, nch->ncp->nc_name, nch->ncp->nc_nlen,
				    NULL, &nip);
	if (error) {
		hammer_done_transaction(&trans);
		*ap->a_vpp = NULL;
		lwkt_reltoken(&hmp->fs_token);
		return (error);
	}
	/*
	 * Add the new filesystem object to the directory.  This will also
	 * bump the inode's link count.
	 */
	error = hammer_ip_add_direntry(&trans, dip,
					nch->ncp->nc_name, nch->ncp->nc_nlen,
					nip);
	if (error)
		hkprintf("hammer_mkdir (add) error %d\n", error);

	/*
	 * Finish up.
	 */
	if (error) {
		hammer_rel_inode(nip, 0);
		*ap->a_vpp = NULL;
	} else {
		error = hammer_get_vnode(nip, ap->a_vpp);
		hammer_rel_inode(nip, 0);
		if (error == 0) {
			cache_setunresolved(ap->a_nch);
			cache_setvp(ap->a_nch, *ap->a_vpp);
		}
	}
	hammer_done_transaction(&trans);
	if (error == 0)
		hammer_knote(ap->a_dvp, NOTE_WRITE | NOTE_LINK);
	lwkt_reltoken(&hmp->fs_token);
	return (error);
}

/*
 * hammer_vop_nmknod { nch, dvp, vpp, cred, vap }
 *
 * The operating system has already ensured that the directory entry
 * does not exist and done all appropriate namespace locking.
 */
static
int
hammer_vop_nmknod(struct vop_nmknod_args *ap)
{
	struct hammer_transaction trans;
	hammer_inode_t dip;
	hammer_inode_t nip;
	struct nchandle *nch;
	hammer_mount_t hmp;
	int error;

	nch = ap->a_nch;
	dip = VTOI(ap->a_dvp);
	hmp = dip->hmp;

	if (dip->flags & HAMMER_INODE_RO)
		return (EROFS);
	if ((error = hammer_checkspace(hmp, HAMMER_CHKSPC_CREATE)) != 0)
		return (error);

	/*
	 * Create a transaction to cover the operations we perform.
	 */
	lwkt_gettoken(&hmp->fs_token);
	hammer_start_transaction(&trans, hmp);

	/*
	 * Create a new filesystem object of the requested type.  The
	 * returned inode will be referenced but not locked.
	 *
	 * If mknod specifies a directory a pseudo-fs is created.
	 */
	error = hammer_create_inode(&trans, ap->a_vap, ap->a_cred,
				    dip, nch->ncp->nc_name, nch->ncp->nc_nlen,
				    NULL, &nip);
	if (error) {
		hammer_done_transaction(&trans);
		*ap->a_vpp = NULL;
		lwkt_reltoken(&hmp->fs_token);
		return (error);
	}

	/*
	 * Add the new filesystem object to the directory.  This will also
	 * bump the inode's link count.
	 */
	error = hammer_ip_add_direntry(&trans, dip,
					nch->ncp->nc_name, nch->ncp->nc_nlen,
					nip);

	/*
	 * Finish up.
	 */
	if (error) {
		hammer_rel_inode(nip, 0);
		*ap->a_vpp = NULL;
	} else {
		error = hammer_get_vnode(nip, ap->a_vpp);
		hammer_rel_inode(nip, 0);
		if (error == 0) {
			cache_setunresolved(ap->a_nch);
			cache_setvp(ap->a_nch, *ap->a_vpp);
		}
	}
	hammer_done_transaction(&trans);
	if (error == 0)
		hammer_knote(ap->a_dvp, NOTE_WRITE);
	lwkt_reltoken(&hmp->fs_token);
	return (error);
}

/*
 * hammer_vop_open { vp, mode, cred, fp }
 *
 * MPSAFE (does not require fs_token)
 */
static
int
hammer_vop_open(struct vop_open_args *ap)
{
	hammer_inode_t ip;

	ip = VTOI(ap->a_vp);

	if ((ap->a_mode & FWRITE) && (ip->flags & HAMMER_INODE_RO))
		return (EROFS);
	return(vop_stdopen(ap));
}

/*
 * hammer_vop_print { vp }
 */
static
int
hammer_vop_print(struct vop_print_args *ap)
{
	return EOPNOTSUPP;
}

/*
 * hammer_vop_readdir { vp, uio, cred, *eofflag, *ncookies, off_t **cookies }
 */
static
int
hammer_vop_readdir(struct vop_readdir_args *ap)
{
	struct hammer_transaction trans;
	struct hammer_cursor cursor;
	hammer_inode_t ip;
	hammer_mount_t hmp;
	struct uio *uio;
	hammer_base_elm_t base;
	int error;
	int cookie_index;
	int ncookies;
	off_t *cookies;
	off_t saveoff;
	int r;
	int dtype;

	ip = VTOI(ap->a_vp);
	uio = ap->a_uio;
	saveoff = uio->uio_offset;
	hmp = ip->hmp;

	if (ap->a_ncookies) {
		ncookies = uio->uio_resid / 16 + 1;
		if (ncookies > 1024)
			ncookies = 1024;
		cookies = kmalloc(ncookies * sizeof(off_t), M_TEMP, M_WAITOK);
		cookie_index = 0;
	} else {
		ncookies = -1;
		cookies = NULL;
		cookie_index = 0;
	}

	lwkt_gettoken(&hmp->fs_token);
	hammer_simple_transaction(&trans, hmp);

	/*
	 * Handle artificial entries
	 *
	 * It should be noted that the minimum value for a directory
	 * hash key on-media is 0x0000000100000000, so we can use anything
	 * less then that to represent our 'special' key space.
	 */
	error = 0;
	if (saveoff == 0) {
		r = vop_write_dirent(&error, uio, ip->obj_id, DT_DIR, 1, ".");
		if (r)
			goto done;
		if (cookies)
			cookies[cookie_index] = saveoff;
		++saveoff;
		++cookie_index;
		if (cookie_index == ncookies)
			goto done;
	}
	if (saveoff == 1) {
		if (ip->ino_data.parent_obj_id) {
			r = vop_write_dirent(&error, uio,
					     ip->ino_data.parent_obj_id,
					     DT_DIR, 2, "..");
		} else {
			r = vop_write_dirent(&error, uio,
					     ip->obj_id, DT_DIR, 2, "..");
		}
		if (r)
			goto done;
		if (cookies)
			cookies[cookie_index] = saveoff;
		++saveoff;
		++cookie_index;
		if (cookie_index == ncookies)
			goto done;
	}

	/*
	 * Key range (begin and end inclusive) to scan.  Directory keys
	 * directly translate to a 64 bit 'seek' position.
	 */
	hammer_init_cursor(&trans, &cursor, &ip->cache[1], ip);
	cursor.key_beg.localization = ip->obj_localization |
				      hammer_dir_localization(ip);
	cursor.key_beg.obj_id = ip->obj_id;
	cursor.key_beg.create_tid = 0;
	cursor.key_beg.delete_tid = 0;
        cursor.key_beg.rec_type = HAMMER_RECTYPE_DIRENTRY;
	cursor.key_beg.obj_type = 0;
	cursor.key_beg.key = saveoff;

	cursor.key_end = cursor.key_beg;
	cursor.key_end.key = HAMMER_MAX_KEY;
	cursor.asof = ip->obj_asof;
	cursor.flags |= HAMMER_CURSOR_END_INCLUSIVE | HAMMER_CURSOR_ASOF;

	error = hammer_ip_first(&cursor);

	while (error == 0) {
		error = hammer_ip_resolve_data(&cursor);
		if (error)
			break;
		base = &cursor.leaf->base;
		saveoff = base->key;
		KKASSERT(cursor.leaf->data_len > HAMMER_ENTRY_NAME_OFF);

		if (base->obj_id != ip->obj_id)
			hpanic("bad record at %p", cursor.node);

		dtype = hammer_get_dtype(cursor.leaf->base.obj_type);
		r = vop_write_dirent(
			     &error, uio, cursor.data->entry.obj_id,
			     dtype,
			     cursor.leaf->data_len - HAMMER_ENTRY_NAME_OFF ,
			     (void *)cursor.data->entry.name);
		if (r)
			break;
		++saveoff;
		if (cookies)
			cookies[cookie_index] = base->key;
		++cookie_index;
		if (cookie_index == ncookies)
			break;
		error = hammer_ip_next(&cursor);
	}
	hammer_done_cursor(&cursor);

done:
	hammer_done_transaction(&trans);

	if (ap->a_eofflag)
		*ap->a_eofflag = (error == ENOENT);
	uio->uio_offset = saveoff;
	if (error && cookie_index == 0) {
		if (error == ENOENT)
			error = 0;
		if (cookies) {
			kfree(cookies, M_TEMP);
			*ap->a_ncookies = 0;
			*ap->a_cookies = NULL;
		}
	} else {
		if (error == ENOENT)
			error = 0;
		if (cookies) {
			*ap->a_ncookies = cookie_index;
			*ap->a_cookies = cookies;
		}
	}
	lwkt_reltoken(&hmp->fs_token);
	return(error);
}

/*
 * hammer_vop_readlink { vp, uio, cred }
 */
static
int
hammer_vop_readlink(struct vop_readlink_args *ap)
{
	struct hammer_transaction trans;
	struct hammer_cursor cursor;
	hammer_inode_t ip;
	hammer_mount_t hmp;
	char buf[32];
	uint32_t localization;
	hammer_pseudofs_inmem_t pfsm;
	int error;

	ip = VTOI(ap->a_vp);
	hmp = ip->hmp;

	lwkt_gettoken(&hmp->fs_token);

	/*
	 * Shortcut if the symlink data was stuffed into ino_data.
	 *
	 * Also expand special "@@PFS%05d" softlinks (expansion only
	 * occurs for non-historical (current) accesses made from the
	 * primary filesystem).
	 *
	 * Note that userspace hammer command does not allow users to
	 * create a @@PFS softlink under an existing other PFS (id!=0)
	 * so the ip localization here for @@PFS softlink is always 0.
	 */
	if (ip->ino_data.size <= HAMMER_INODE_BASESYMLEN) {
		char *ptr;
		int bytes;

		ptr = ip->ino_data.ext.symlink;
		bytes = (int)ip->ino_data.size;
		if (bytes == 10 &&
		    ip->obj_asof == HAMMER_MAX_TID &&
		    ip->obj_localization == HAMMER_DEF_LOCALIZATION &&
		    strncmp(ptr, "@@PFS", 5) == 0) {
			hammer_simple_transaction(&trans, hmp);
			bcopy(ptr + 5, buf, 5);
			buf[5] = 0;
			localization = pfs_to_lo(strtoul(buf, NULL, 10));
			pfsm = hammer_load_pseudofs(&trans, localization,
						    &error);
			if (error == 0) {
				if (hammer_is_pfs_slave(&pfsm->pfsd)) {
					/* vap->va_size == 26 */
					ksnprintf(buf, sizeof(buf),
						  "@@0x%016jx:%05d",
						  (intmax_t)pfsm->pfsd.sync_end_tid,
						  lo_to_pfs(localization));
				} else {
					/* vap->va_size == 10 */
					ksnprintf(buf, sizeof(buf),
						  "@@-1:%05d",
						  lo_to_pfs(localization));
				}
				ptr = buf;
				bytes = strlen(buf);
			}
			if (pfsm)
				hammer_rel_pseudofs(hmp, pfsm);
			hammer_done_transaction(&trans);
		}
		error = uiomove(ptr, bytes, ap->a_uio);
		lwkt_reltoken(&hmp->fs_token);
		return(error);
	}

	/*
	 * Long version
	 */
	hammer_simple_transaction(&trans, hmp);
	hammer_init_cursor(&trans, &cursor, &ip->cache[1], ip);

	/*
	 * Key range (begin and end inclusive) to scan.  Directory keys
	 * directly translate to a 64 bit 'seek' position.
	 */
	cursor.key_beg.localization = ip->obj_localization |
				      HAMMER_LOCALIZE_MISC;
	cursor.key_beg.obj_id = ip->obj_id;
	cursor.key_beg.create_tid = 0;
	cursor.key_beg.delete_tid = 0;
        cursor.key_beg.rec_type = HAMMER_RECTYPE_FIX;
	cursor.key_beg.obj_type = 0;
	cursor.key_beg.key = HAMMER_FIXKEY_SYMLINK;
	cursor.asof = ip->obj_asof;
	cursor.flags |= HAMMER_CURSOR_ASOF;

	error = hammer_ip_lookup(&cursor);
	if (error == 0) {
		error = hammer_ip_resolve_data(&cursor);
		if (error == 0) {
			KKASSERT(cursor.leaf->data_len >=
				 HAMMER_SYMLINK_NAME_OFF);
			error = uiomove(cursor.data->symlink.name,
					cursor.leaf->data_len -
						HAMMER_SYMLINK_NAME_OFF,
					ap->a_uio);
		}
	}
	hammer_done_cursor(&cursor);
	hammer_done_transaction(&trans);
	lwkt_reltoken(&hmp->fs_token);
	return(error);
}

/*
 * hammer_vop_nremove { nch, dvp, cred }
 */
static
int
hammer_vop_nremove(struct vop_nremove_args *ap)
{
	struct hammer_transaction trans;
	hammer_inode_t dip;
	hammer_mount_t hmp;
	int error;

	dip = VTOI(ap->a_dvp);
	hmp = dip->hmp;

	if (hammer_nohistory(dip) == 0 &&
	    (error = hammer_checkspace(hmp, HAMMER_CHKSPC_REMOVE)) != 0) {
		return (error);
	}

	lwkt_gettoken(&hmp->fs_token);
	hammer_start_transaction(&trans, hmp);
	error = hammer_dounlink(&trans, ap->a_nch, ap->a_dvp, ap->a_cred, 0, 0);
	hammer_done_transaction(&trans);
	if (error == 0)
		hammer_knote(ap->a_dvp, NOTE_WRITE);
	lwkt_reltoken(&hmp->fs_token);
	return (error);
}

/*
 * hammer_vop_nrename { fnch, tnch, fdvp, tdvp, cred }
 */
static
int
hammer_vop_nrename(struct vop_nrename_args *ap)
{
	struct hammer_transaction trans;
	struct namecache *fncp;
	struct namecache *tncp;
	hammer_inode_t fdip;
	hammer_inode_t tdip;
	hammer_inode_t ip;
	hammer_mount_t hmp;
	struct hammer_cursor cursor;
	int64_t namekey;
	uint32_t max_iterations;
	int nlen, error;

	if (ap->a_fdvp->v_mount != ap->a_tdvp->v_mount)
		return(EXDEV);
	if (ap->a_fdvp->v_mount != ap->a_fnch->ncp->nc_vp->v_mount)
		return(EXDEV);

	fdip = VTOI(ap->a_fdvp);
	tdip = VTOI(ap->a_tdvp);
	fncp = ap->a_fnch->ncp;
	tncp = ap->a_tnch->ncp;
	ip = VTOI(fncp->nc_vp);
	KKASSERT(ip != NULL);

	hmp = ip->hmp;

	if (fdip->obj_localization != tdip->obj_localization)
		return(EXDEV);
	if (fdip->obj_localization != ip->obj_localization)
		return(EXDEV);

	if (fdip->flags & HAMMER_INODE_RO)
		return (EROFS);
	if (tdip->flags & HAMMER_INODE_RO)
		return (EROFS);
	if (ip->flags & HAMMER_INODE_RO)
		return (EROFS);
	if ((error = hammer_checkspace(hmp, HAMMER_CHKSPC_CREATE)) != 0)
		return (error);

	lwkt_gettoken(&hmp->fs_token);
	hammer_start_transaction(&trans, hmp);

	/*
	 * Remove tncp from the target directory and then link ip as
	 * tncp. XXX pass trans to dounlink
	 *
	 * Force the inode sync-time to match the transaction so it is
	 * in-sync with the creation of the target directory entry.
	 */
	error = hammer_dounlink(&trans, ap->a_tnch, ap->a_tdvp,
				ap->a_cred, 0, -1);
	if (error == 0 || error == ENOENT) {
		error = hammer_ip_add_direntry(&trans, tdip,
						tncp->nc_name, tncp->nc_nlen,
						ip);
		if (error == 0) {
			ip->ino_data.parent_obj_id = tdip->obj_id;
			ip->ino_data.ctime = trans.time;
			hammer_modify_inode(&trans, ip, HAMMER_INODE_DDIRTY);
		}
	}
	if (error)
		goto failed; /* XXX */

	/*
	 * Locate the record in the originating directory and remove it.
	 *
	 * Calculate the namekey and setup the key range for the scan.  This
	 * works kinda like a chained hash table where the lower 32 bits
	 * of the namekey synthesize the chain.
	 *
	 * The key range is inclusive of both key_beg and key_end.
	 */
	namekey = hammer_direntry_namekey(fdip, fncp->nc_name, fncp->nc_nlen,
					   &max_iterations);
retry:
	hammer_init_cursor(&trans, &cursor, &fdip->cache[1], fdip);
	cursor.key_beg.localization = fdip->obj_localization |
				      hammer_dir_localization(fdip);
        cursor.key_beg.obj_id = fdip->obj_id;
	cursor.key_beg.key = namekey;
        cursor.key_beg.create_tid = 0;
        cursor.key_beg.delete_tid = 0;
        cursor.key_beg.rec_type = HAMMER_RECTYPE_DIRENTRY;
        cursor.key_beg.obj_type = 0;

	cursor.key_end = cursor.key_beg;
	cursor.key_end.key += max_iterations;
	cursor.asof = fdip->obj_asof;
	cursor.flags |= HAMMER_CURSOR_END_INCLUSIVE | HAMMER_CURSOR_ASOF;

	/*
	 * Scan all matching records (the chain), locate the one matching
	 * the requested path component.
	 *
	 * The hammer_ip_*() functions merge in-memory records with on-disk
	 * records for the purposes of the search.
	 */
	error = hammer_ip_first(&cursor);
	while (error == 0) {
		if (hammer_ip_resolve_data(&cursor) != 0)
			break;
		nlen = cursor.leaf->data_len - HAMMER_ENTRY_NAME_OFF;
		KKASSERT(nlen > 0);
		if (fncp->nc_nlen == nlen &&
		    bcmp(fncp->nc_name, cursor.data->entry.name, nlen) == 0) {
			break;
		}
		error = hammer_ip_next(&cursor);
	}

	/*
	 * If all is ok we have to get the inode so we can adjust nlinks.
	 *
	 * WARNING: hammer_ip_del_direntry() may have to terminate the
	 * cursor to avoid a recursion.  It's ok to call hammer_done_cursor()
	 * twice.
	 */
	if (error == 0)
		error = hammer_ip_del_direntry(&trans, &cursor, fdip, ip);

	/*
	 * XXX A deadlock here will break rename's atomicy for the purposes
	 * of crash recovery.
	 */
	if (error == EDEADLK) {
		hammer_done_cursor(&cursor);
		goto retry;
	}

	/*
	 * Cleanup and tell the kernel that the rename succeeded.
	 *
	 * NOTE: ip->vp, if non-NULL, cannot be directly referenced
	 *	 without formally acquiring the vp since the vp might
	 *	 have zero refs on it, or in the middle of a reclaim,
	 *	 etc.
	 */
        hammer_done_cursor(&cursor);
	if (error == 0) {
		cache_rename(ap->a_fnch, ap->a_tnch);
		hammer_knote(ap->a_fdvp, NOTE_WRITE);
		hammer_knote(ap->a_tdvp, NOTE_WRITE);
		while (ip->vp) {
			struct vnode *vp;

			error = hammer_get_vnode(ip, &vp);
			if (error == 0 && vp) {
				vn_unlock(vp);
				hammer_knote(ip->vp, NOTE_RENAME);
				vrele(vp);
				break;
			}
			hdkprintf("ip/vp race2 avoided\n");
		}
	}

failed:
	hammer_done_transaction(&trans);
	lwkt_reltoken(&hmp->fs_token);
	return (error);
}

/*
 * hammer_vop_nrmdir { nch, dvp, cred }
 */
static
int
hammer_vop_nrmdir(struct vop_nrmdir_args *ap)
{
	struct hammer_transaction trans;
	hammer_inode_t dip;
	hammer_mount_t hmp;
	int error;

	dip = VTOI(ap->a_dvp);
	hmp = dip->hmp;

	if (hammer_nohistory(dip) == 0 &&
	    (error = hammer_checkspace(hmp, HAMMER_CHKSPC_REMOVE)) != 0) {
		return (error);
	}

	lwkt_gettoken(&hmp->fs_token);
	hammer_start_transaction(&trans, hmp);
	error = hammer_dounlink(&trans, ap->a_nch, ap->a_dvp, ap->a_cred, 0, 1);
	hammer_done_transaction(&trans);
	if (error == 0)
		hammer_knote(ap->a_dvp, NOTE_WRITE | NOTE_LINK);
	lwkt_reltoken(&hmp->fs_token);
	return (error);
}

/*
 * hammer_vop_markatime { vp, cred }
 */
static
int
hammer_vop_markatime(struct vop_markatime_args *ap)
{
	struct hammer_transaction trans;
	hammer_inode_t ip;
	hammer_mount_t hmp;

	ip = VTOI(ap->a_vp);
	if (ap->a_vp->v_mount->mnt_flag & MNT_RDONLY)
		return (EROFS);
	if (ip->flags & HAMMER_INODE_RO)
		return (EROFS);
	hmp = ip->hmp;
	if (hmp->mp->mnt_flag & MNT_NOATIME)
		return (0);
	lwkt_gettoken(&hmp->fs_token);
	hammer_start_transaction(&trans, hmp);

	ip->ino_data.atime = trans.time;
	hammer_modify_inode(&trans, ip, HAMMER_INODE_ATIME);
	hammer_done_transaction(&trans);
	hammer_knote(ap->a_vp, NOTE_ATTRIB);
	lwkt_reltoken(&hmp->fs_token);
	return (0);
}

/*
 * hammer_vop_setattr { vp, vap, cred }
 */
static
int
hammer_vop_setattr(struct vop_setattr_args *ap)
{
	struct hammer_transaction trans;
	hammer_inode_t ip;
	struct vattr *vap;
	hammer_mount_t hmp;
	int modflags;
	int error;
	int truncating;
	int blksize;
	int kflags;
#if 0
	int64_t aligned_size;
#endif
	uint32_t flags;

	vap = ap->a_vap;
	ip = ap->a_vp->v_data;
	modflags = 0;
	kflags = 0;
	hmp = ip->hmp;

	if (ap->a_vp->v_mount->mnt_flag & MNT_RDONLY)
		return(EROFS);
	if (ip->flags & HAMMER_INODE_RO)
		return (EROFS);
	if (hammer_nohistory(ip) == 0 &&
	    (error = hammer_checkspace(hmp, HAMMER_CHKSPC_REMOVE)) != 0) {
		return (error);
	}

	lwkt_gettoken(&hmp->fs_token);
	hammer_start_transaction(&trans, hmp);
	error = 0;

	if (vap->va_flags != VNOVAL) {
		flags = ip->ino_data.uflags;
		error = vop_helper_setattr_flags(&flags, vap->va_flags,
					 hammer_to_unix_xid(&ip->ino_data.uid),
					 ap->a_cred);
		if (error == 0) {
			if (ip->ino_data.uflags != flags) {
				ip->ino_data.uflags = flags;
				ip->ino_data.ctime = trans.time;
				modflags |= HAMMER_INODE_DDIRTY;
				kflags |= NOTE_ATTRIB;
			}
			if (ip->ino_data.uflags & (IMMUTABLE | APPEND)) {
				error = 0;
				goto done;
			}
		}
		goto done;
	}
	if (ip->ino_data.uflags & (IMMUTABLE | APPEND)) {
		error = EPERM;
		goto done;
	}
	if (vap->va_uid != (uid_t)VNOVAL || vap->va_gid != (gid_t)VNOVAL) {
		mode_t cur_mode = ip->ino_data.mode;
		uid_t cur_uid = hammer_to_unix_xid(&ip->ino_data.uid);
		gid_t cur_gid = hammer_to_unix_xid(&ip->ino_data.gid);
		hammer_uuid_t uuid_uid;
		hammer_uuid_t uuid_gid;

		error = vop_helper_chown(ap->a_vp, vap->va_uid, vap->va_gid,
					 ap->a_cred,
					 &cur_uid, &cur_gid, &cur_mode);
		if (error == 0) {
			hammer_guid_to_uuid(&uuid_uid, cur_uid);
			hammer_guid_to_uuid(&uuid_gid, cur_gid);
			if (kuuid_compare(&uuid_uid, &ip->ino_data.uid) ||
			    kuuid_compare(&uuid_gid, &ip->ino_data.gid) ||
			    ip->ino_data.mode != cur_mode) {
				ip->ino_data.uid = uuid_uid;
				ip->ino_data.gid = uuid_gid;
				ip->ino_data.mode = cur_mode;
				ip->ino_data.ctime = trans.time;
				modflags |= HAMMER_INODE_DDIRTY;
			}
			kflags |= NOTE_ATTRIB;
		}
	}
	while (vap->va_size != VNOVAL && ip->ino_data.size != vap->va_size) {
		switch(ap->a_vp->v_type) {
		case VREG:
			if (vap->va_size == ip->ino_data.size)
				break;

			/*
			 * Log the operation if in fast-fsync mode or if
			 * there are unterminated redo write records present.
			 *
			 * The second check is needed so the recovery code
			 * properly truncates write redos even if nominal
			 * REDO operations is turned off due to excessive
			 * writes, because the related records might be
			 * destroyed and never lay down a TERM_WRITE.
			 */
			if ((ip->flags & HAMMER_INODE_REDO) ||
			    (ip->flags & HAMMER_INODE_RDIRTY)) {
				error = hammer_generate_redo(&trans, ip,
							     vap->va_size,
							     HAMMER_REDO_TRUNC,
							     NULL, 0);
			}
			blksize = hammer_blocksize(vap->va_size);

			/*
			 * XXX break atomicy, we can deadlock the backend
			 * if we do not release the lock.  Probably not a
			 * big deal here.
			 */
			if (vap->va_size < ip->ino_data.size) {
				nvtruncbuf(ap->a_vp, vap->va_size,
					   blksize,
					   hammer_blockoff(vap->va_size),
					   0);
				truncating = 1;
				kflags |= NOTE_WRITE;
			} else {
				nvextendbuf(ap->a_vp,
					    ip->ino_data.size,
					    vap->va_size,
					    hammer_blocksize(ip->ino_data.size),
					    hammer_blocksize(vap->va_size),
					    hammer_blockoff(ip->ino_data.size),
					    hammer_blockoff(vap->va_size),
					    0);
				truncating = 0;
				kflags |= NOTE_WRITE | NOTE_EXTEND;
			}
			ip->ino_data.size = vap->va_size;
			ip->ino_data.mtime = trans.time;
			/* XXX safe to use SDIRTY instead of DDIRTY here? */
			modflags |= HAMMER_INODE_MTIME | HAMMER_INODE_DDIRTY;
			vclrflags(ap->a_vp, VLASTWRITETS);

			/*
			 * On-media truncation is cached in the inode until
			 * the inode is synchronized.  We must immediately
			 * handle any frontend records.
			 */
			if (truncating) {
				hammer_ip_frontend_trunc(ip, vap->va_size);
				if ((ip->flags & HAMMER_INODE_TRUNCATED) == 0) {
					ip->flags |= HAMMER_INODE_TRUNCATED;
					ip->trunc_off = vap->va_size;
					hammer_inode_dirty(ip);
				} else if (ip->trunc_off > vap->va_size) {
					ip->trunc_off = vap->va_size;
				}
			}

#if 0
			/*
			 * When truncating, nvtruncbuf() may have cleaned out
			 * a portion of the last block on-disk in the buffer
			 * cache.  We must clean out any frontend records
			 * for blocks beyond the new last block.
			 */
			aligned_size = (vap->va_size + (blksize - 1)) &
				       ~(int64_t)(blksize - 1);
			if (truncating && vap->va_size < aligned_size) {
				aligned_size -= blksize;
				hammer_ip_frontend_trunc(ip, aligned_size);
			}
#endif
			break;
		case VDATABASE:
			if ((ip->flags & HAMMER_INODE_TRUNCATED) == 0) {
				ip->flags |= HAMMER_INODE_TRUNCATED;
				ip->trunc_off = vap->va_size;
				hammer_inode_dirty(ip);
			} else if (ip->trunc_off > vap->va_size) {
				ip->trunc_off = vap->va_size;
			}
			hammer_ip_frontend_trunc(ip, vap->va_size);
			ip->ino_data.size = vap->va_size;
			ip->ino_data.mtime = trans.time;
			modflags |= HAMMER_INODE_MTIME | HAMMER_INODE_DDIRTY;
			vclrflags(ap->a_vp, VLASTWRITETS);
			kflags |= NOTE_ATTRIB;
			break;
		default:
			error = EINVAL;
			goto done;
		}
		break;
	}
	if (vap->va_atime.tv_sec != VNOVAL) {
		ip->ino_data.atime = hammer_timespec_to_time(&vap->va_atime);
		modflags |= HAMMER_INODE_ATIME;
		kflags |= NOTE_ATTRIB;
	}
	if (vap->va_mtime.tv_sec != VNOVAL) {
		ip->ino_data.mtime = hammer_timespec_to_time(&vap->va_mtime);
		modflags |= HAMMER_INODE_MTIME;
		kflags |= NOTE_ATTRIB;
		vclrflags(ap->a_vp, VLASTWRITETS);
	}
	if (vap->va_mode != (mode_t)VNOVAL) {
		mode_t   cur_mode = ip->ino_data.mode;
		uid_t cur_uid = hammer_to_unix_xid(&ip->ino_data.uid);
		gid_t cur_gid = hammer_to_unix_xid(&ip->ino_data.gid);

		error = vop_helper_chmod(ap->a_vp, vap->va_mode, ap->a_cred,
					 cur_uid, cur_gid, &cur_mode);
		if (error == 0) {
			ip->ino_data.mode = cur_mode;
			ip->ino_data.ctime = trans.time;
			modflags |= HAMMER_INODE_DDIRTY;
			kflags |= NOTE_ATTRIB;
		}
	}
done:
	if (error == 0)
		hammer_modify_inode(&trans, ip, modflags);
	hammer_done_transaction(&trans);
	hammer_knote(ap->a_vp, kflags);
	lwkt_reltoken(&hmp->fs_token);
	return (error);
}

/*
 * hammer_vop_nsymlink { nch, dvp, vpp, cred, vap, target }
 */
static
int
hammer_vop_nsymlink(struct vop_nsymlink_args *ap)
{
	struct hammer_transaction trans;
	hammer_inode_t dip;
	hammer_inode_t nip;
	hammer_record_t record;
	struct nchandle *nch;
	hammer_mount_t hmp;
	int error;
	int bytes;

	ap->a_vap->va_type = VLNK;

	nch = ap->a_nch;
	dip = VTOI(ap->a_dvp);
	hmp = dip->hmp;

	if (dip->flags & HAMMER_INODE_RO)
		return (EROFS);
	if ((error = hammer_checkspace(hmp, HAMMER_CHKSPC_CREATE)) != 0)
		return (error);

	/*
	 * Create a transaction to cover the operations we perform.
	 */
	lwkt_gettoken(&hmp->fs_token);
	hammer_start_transaction(&trans, hmp);

	/*
	 * Create a new filesystem object of the requested type.  The
	 * returned inode will be referenced but not locked.
	 */

	error = hammer_create_inode(&trans, ap->a_vap, ap->a_cred,
				    dip, nch->ncp->nc_name, nch->ncp->nc_nlen,
				    NULL, &nip);
	if (error) {
		hammer_done_transaction(&trans);
		*ap->a_vpp = NULL;
		lwkt_reltoken(&hmp->fs_token);
		return (error);
	}

	/*
	 * Add a record representing the symlink.  symlink stores the link
	 * as pure data, not a string, and is no \0 terminated.
	 */
	if (error == 0) {
		bytes = strlen(ap->a_target);

		if (bytes <= HAMMER_INODE_BASESYMLEN) {
			bcopy(ap->a_target, nip->ino_data.ext.symlink, bytes);
		} else {
			record = hammer_alloc_mem_record(nip, bytes);
			record->type = HAMMER_MEM_RECORD_GENERAL;

			record->leaf.base.localization = nip->obj_localization |
							 HAMMER_LOCALIZE_MISC;
			record->leaf.base.key = HAMMER_FIXKEY_SYMLINK;
			record->leaf.base.rec_type = HAMMER_RECTYPE_FIX;
			record->leaf.data_len = bytes;
			KKASSERT(HAMMER_SYMLINK_NAME_OFF == 0);
			bcopy(ap->a_target, record->data->symlink.name, bytes);
			error = hammer_ip_add_record(&trans, record);
		}

		/*
		 * Set the file size to the length of the link.
		 */
		if (error == 0) {
			nip->ino_data.size = bytes;
			hammer_modify_inode(&trans, nip, HAMMER_INODE_DDIRTY);
		}
	}
	if (error == 0)
		error = hammer_ip_add_direntry(&trans, dip, nch->ncp->nc_name,
						nch->ncp->nc_nlen, nip);

	/*
	 * Finish up.
	 */
	if (error) {
		hammer_rel_inode(nip, 0);
		*ap->a_vpp = NULL;
	} else {
		error = hammer_get_vnode(nip, ap->a_vpp);
		hammer_rel_inode(nip, 0);
		if (error == 0) {
			cache_setunresolved(ap->a_nch);
			cache_setvp(ap->a_nch, *ap->a_vpp);
			hammer_knote(ap->a_dvp, NOTE_WRITE);
		}
	}
	hammer_done_transaction(&trans);
	lwkt_reltoken(&hmp->fs_token);
	return (error);
}

/*
 * hammer_vop_nwhiteout { nch, dvp, cred, flags }
 */
static
int
hammer_vop_nwhiteout(struct vop_nwhiteout_args *ap)
{
	struct hammer_transaction trans;
	hammer_inode_t dip;
	hammer_mount_t hmp;
	int error;

	dip = VTOI(ap->a_dvp);
	hmp = dip->hmp;

	if (hammer_nohistory(dip) == 0 &&
	    (error = hammer_checkspace(hmp, HAMMER_CHKSPC_CREATE)) != 0) {
		return (error);
	}

	lwkt_gettoken(&hmp->fs_token);
	hammer_start_transaction(&trans, hmp);
	error = hammer_dounlink(&trans, ap->a_nch, ap->a_dvp,
				ap->a_cred, ap->a_flags, -1);
	hammer_done_transaction(&trans);
	lwkt_reltoken(&hmp->fs_token);

	return (error);
}

/*
 * hammer_vop_ioctl { vp, command, data, fflag, cred }
 */
static
int
hammer_vop_ioctl(struct vop_ioctl_args *ap)
{
	hammer_inode_t ip = ap->a_vp->v_data;
	hammer_mount_t hmp = ip->hmp;
	int error;

	lwkt_gettoken(&hmp->fs_token);
	error = hammer_ioctl(ip, ap->a_command, ap->a_data,
			     ap->a_fflag, ap->a_cred);
	lwkt_reltoken(&hmp->fs_token);
	return (error);
}

static
int
hammer_vop_mountctl(struct vop_mountctl_args *ap)
{
	static const struct mountctl_opt extraopt[] = {
		{ HMNT_NOHISTORY,	"nohistory" },
		{ HMNT_MASTERID,	"master" },
		{ HMNT_NOMIRROR,	"nomirror" },
		{ 0, NULL}

	};
	hammer_mount_t hmp;
	struct mount *mp;
	int usedbytes;
	int error;

	error = 0;
	usedbytes = 0;
	mp = ap->a_head.a_ops->head.vv_mount;
	KKASSERT(mp->mnt_data != NULL);
	hmp = (hammer_mount_t)mp->mnt_data;

	lwkt_gettoken(&hmp->fs_token);

	switch(ap->a_op) {
	case MOUNTCTL_SET_EXPORT:
		if (ap->a_ctllen != sizeof(struct export_args))
			error = EINVAL;
		else
			error = hammer_vfs_export(mp, ap->a_op,
				      (const struct export_args *)ap->a_ctl);
		break;
	case MOUNTCTL_MOUNTFLAGS:
		/*
		 * Call standard mountctl VOP function
		 * so we get user mount flags.
		 */
		error = vop_stdmountctl(ap);
		if (error)
			break;

		usedbytes = *ap->a_res;

		if (usedbytes > 0 && usedbytes < ap->a_buflen) {
			usedbytes += vfs_flagstostr(hmp->hflags, extraopt,
						    ap->a_buf,
						    ap->a_buflen - usedbytes,
						    &error);
		}

		*ap->a_res += usedbytes;
		break;
	default:
		error = vop_stdmountctl(ap);
		break;
	}
	lwkt_reltoken(&hmp->fs_token);
	return(error);
}

/*
 * hammer_vop_strategy { vp, bio }
 *
 * Strategy call, used for regular file read & write only.  Note that the
 * bp may represent a cluster.
 *
 * To simplify operation and allow better optimizations in the future,
 * this code does not make any assumptions with regards to buffer alignment
 * or size.
 */
static
int
hammer_vop_strategy(struct vop_strategy_args *ap)
{
	struct buf *bp;
	int error;

	bp = ap->a_bio->bio_buf;

	switch(bp->b_cmd) {
	case BUF_CMD_READ:
		error = hammer_vop_strategy_read(ap);
		break;
	case BUF_CMD_WRITE:
		error = hammer_vop_strategy_write(ap);
		break;
	default:
		bp->b_error = error = EINVAL;
		bp->b_flags |= B_ERROR;
		biodone(ap->a_bio);
		break;
	}
	return (error);
}

/*
 * Read from a regular file.  Iterate the related records and fill in the
 * BIO/BUF.  Gaps are zero-filled.
 *
 * The support code in hammer_object.c should be used to deal with mixed
 * in-memory and on-disk records.
 *
 * NOTE: Can be called from the cluster code with an oversized buf.
 *
 * XXX atime update
 */
static
int
hammer_vop_strategy_read(struct vop_strategy_args *ap)
{
	struct hammer_transaction trans;
	hammer_inode_t ip;
	hammer_inode_t dip;
	hammer_mount_t hmp;
	struct hammer_cursor cursor;
	hammer_base_elm_t base;
	hammer_off_t disk_offset;
	struct bio *bio;
	struct bio *nbio;
	struct buf *bp;
	int64_t rec_offset;
	int64_t ran_end;
	int64_t tmp64;
	int error;
	int boff;
	int roff;
	int n;
	int isdedupable;

	bio = ap->a_bio;
	bp = bio->bio_buf;
	ip = ap->a_vp->v_data;
	hmp = ip->hmp;

	/*
	 * The zone-2 disk offset may have been set by the cluster code via
	 * a BMAP operation, or else should be NOOFFSET.
	 *
	 * Checking the high bits for a match against zone-2 should suffice.
	 *
	 * In cases where a lot of data duplication is present it may be
	 * more beneficial to drop through and doubule-buffer through the
	 * device.
	 */
	nbio = push_bio(bio);
	if (hammer_is_zone_large_data(nbio->bio_offset)) {
		if (hammer_double_buffer == 0) {
			lwkt_gettoken(&hmp->fs_token);
			error = hammer_io_direct_read(hmp, nbio, NULL);
			lwkt_reltoken(&hmp->fs_token);
			return (error);
		}

		/*
		 * Try to shortcut requests for double_buffer mode too.
		 * Since this mode runs through the device buffer cache
		 * only compatible buffer sizes (meaning those generated
		 * by normal filesystem buffers) are legal.
		 */
		if ((bp->b_flags & B_PAGING) == 0) {
			lwkt_gettoken(&hmp->fs_token);
			error = hammer_io_indirect_read(hmp, nbio, NULL);
			lwkt_reltoken(&hmp->fs_token);
			return (error);
		}
	}

	/*
	 * Well, that sucked.  Do it the hard way.  If all the stars are
	 * aligned we may still be able to issue a direct-read.
	 */
	lwkt_gettoken(&hmp->fs_token);
	hammer_simple_transaction(&trans, hmp);
	hammer_init_cursor(&trans, &cursor, &ip->cache[1], ip);

	/*
	 * Key range (begin and end inclusive) to scan.  Note that the key's
	 * stored in the actual records represent BASE+LEN, not BASE.  The
	 * first record containing bio_offset will have a key > bio_offset.
	 */
	cursor.key_beg.localization = ip->obj_localization |
				      HAMMER_LOCALIZE_MISC;
	cursor.key_beg.obj_id = ip->obj_id;
	cursor.key_beg.create_tid = 0;
	cursor.key_beg.delete_tid = 0;
	cursor.key_beg.obj_type = 0;
	cursor.key_beg.key = bio->bio_offset + 1;
	cursor.asof = ip->obj_asof;
	cursor.flags |= HAMMER_CURSOR_ASOF;

	cursor.key_end = cursor.key_beg;
	KKASSERT(ip->ino_data.obj_type == HAMMER_OBJTYPE_REGFILE);
#if 0
	if (ip->ino_data.obj_type == HAMMER_OBJTYPE_DBFILE) {
		cursor.key_beg.rec_type = HAMMER_RECTYPE_DB;
		cursor.key_end.rec_type = HAMMER_RECTYPE_DB;
		cursor.key_end.key = HAMMER_MAX_KEY;
	} else
#endif
	{
		ran_end = bio->bio_offset + bp->b_bufsize;
		cursor.key_beg.rec_type = HAMMER_RECTYPE_DATA;
		cursor.key_end.rec_type = HAMMER_RECTYPE_DATA;
		tmp64 = ran_end + MAXPHYS + 1;	/* work-around GCC-4 bug */
		if (tmp64 < ran_end)
			cursor.key_end.key = HAMMER_MAX_KEY;
		else
			cursor.key_end.key = ran_end + MAXPHYS + 1;
	}
	cursor.flags |= HAMMER_CURSOR_END_INCLUSIVE;

	/*
	 * Set NOSWAPCACHE for cursor data extraction if double buffering
	 * is disabled or (if the file is not marked cacheable via chflags
	 * and vm.swapcache_use_chflags is enabled).
	 */
	if (hammer_double_buffer == 0 ||
	    ((ap->a_vp->v_flag & VSWAPCACHE) == 0 &&
	     vm_swapcache_use_chflags)) {
		cursor.flags |= HAMMER_CURSOR_NOSWAPCACHE;
	}

	error = hammer_ip_first(&cursor);
	boff = 0;

	while (error == 0) {
		/*
		 * Get the base file offset of the record.  The key for
		 * data records is (base + bytes) rather then (base).
		 */
		base = &cursor.leaf->base;
		rec_offset = base->key - cursor.leaf->data_len;

		/*
		 * Calculate the gap, if any, and zero-fill it.
		 *
		 * n is the offset of the start of the record verses our
		 * current seek offset in the bio.
		 */
		n = (int)(rec_offset - (bio->bio_offset + boff));
		if (n > 0) {
			if (n > bp->b_bufsize - boff)
				n = bp->b_bufsize - boff;
			bzero((char *)bp->b_data + boff, n);
			boff += n;
			n = 0;
		}

		/*
		 * Calculate the data offset in the record and the number
		 * of bytes we can copy.
		 *
		 * There are two degenerate cases.  First, boff may already
		 * be at bp->b_bufsize.  Secondly, the data offset within
		 * the record may exceed the record's size.
		 */
		roff = -n;
		rec_offset += roff;
		n = cursor.leaf->data_len - roff;
		if (n <= 0) {
			hdkprintf("bad n=%d roff=%d\n", n, roff);
			n = 0;
		} else if (n > bp->b_bufsize - boff) {
			n = bp->b_bufsize - boff;
		}

		/*
		 * Deal with cached truncations.  This cool bit of code
		 * allows truncate()/ftruncate() to avoid having to sync
		 * the file.
		 *
		 * If the frontend is truncated then all backend records are
		 * subject to the frontend's truncation.
		 *
		 * If the backend is truncated then backend records on-disk
		 * (but not in-memory) are subject to the backend's
		 * truncation.  In-memory records owned by the backend
		 * represent data written after the truncation point on the
		 * backend and must not be truncated.
		 *
		 * Truncate operations deal with frontend buffer cache
		 * buffers and frontend-owned in-memory records synchronously.
		 */
		if (ip->flags & HAMMER_INODE_TRUNCATED) {
			if (hammer_cursor_ondisk(&cursor)/* ||
			    cursor.iprec->flush_state == HAMMER_FST_FLUSH*/) {
				if (ip->trunc_off <= rec_offset)
					n = 0;
				else if (ip->trunc_off < rec_offset + n)
					n = (int)(ip->trunc_off - rec_offset);
			}
		}
		if (ip->sync_flags & HAMMER_INODE_TRUNCATED) {
			if (hammer_cursor_ondisk(&cursor)) {
				if (ip->sync_trunc_off <= rec_offset)
					n = 0;
				else if (ip->sync_trunc_off < rec_offset + n)
					n = (int)(ip->sync_trunc_off - rec_offset);
			}
		}

		/*
		 * Try to issue a direct read into our bio if possible,
		 * otherwise resolve the element data into a hammer_buffer
		 * and copy.
		 *
		 * The buffer on-disk should be zerod past any real
		 * truncation point, but may not be for any synthesized
		 * truncation point from above.
		 *
		 * NOTE: disk_offset is only valid if the cursor data is
		 *	 on-disk.
		 */
		disk_offset = cursor.leaf->data_offset + roff;
		isdedupable = (boff == 0 && n == bp->b_bufsize &&
			       hammer_cursor_ondisk(&cursor) &&
			       ((int)disk_offset & HAMMER_BUFMASK) == 0);

		if (isdedupable && hammer_double_buffer == 0) {
			/*
			 * Direct read case
			 */
			KKASSERT(hammer_is_zone_large_data(disk_offset));
			nbio->bio_offset = disk_offset;
			error = hammer_io_direct_read(hmp, nbio, cursor.leaf);
			goto done;
		} else if (isdedupable) {
			/*
			 * Async I/O case for reading from backing store
			 * and copying the data to the filesystem buffer.
			 */
			KKASSERT(hammer_is_zone_large_data(disk_offset));
			nbio->bio_offset = disk_offset;
			error = hammer_io_indirect_read(hmp, nbio, cursor.leaf);
			goto done;
		} else if (n) {
			error = hammer_ip_resolve_data(&cursor);
			if (error == 0) {
				bcopy((char *)cursor.data + roff,
				      (char *)bp->b_data + boff, n);
			}
		}
		if (error)
			break;

		/*
		 * Iterate until we have filled the request.
		 */
		boff += n;
		if (boff == bp->b_bufsize)
			break;
		error = hammer_ip_next(&cursor);
	}

	/*
	 * There may have been a gap after the last record
	 */
	if (error == ENOENT)
		error = 0;
	if (error == 0 && boff != bp->b_bufsize) {
		KKASSERT(boff < bp->b_bufsize);
		bzero((char *)bp->b_data + boff, bp->b_bufsize - boff);
		/* boff = bp->b_bufsize; */
	}

	/*
	 * Disallow swapcache operation on the vnode buffer if double
	 * buffering is enabled, the swapcache will get the data via
	 * the block device buffer.
	 */
	if (hammer_double_buffer)
		bp->b_flags |= B_NOTMETA;

	/*
	 * Cleanup
	 */
	bp->b_resid = 0;
	bp->b_error = error;
	if (error)
		bp->b_flags |= B_ERROR;
	biodone(ap->a_bio);

done:
	/*
	 * Cache the b-tree node for the last data read in cache[1].
	 *
	 * If we hit the file EOF then also cache the node in the
	 * governing directory's cache[3], it will be used to initialize
	 * the new inode's cache[1] for any inodes looked up via the directory.
	 *
	 * This doesn't reduce disk accesses since the B-Tree chain is
	 * likely cached, but it does reduce cpu overhead when looking
	 * up file offsets for cpdup/tar/cpio style iterations.
	 */
	if (cursor.node)
		hammer_cache_node(&ip->cache[1], cursor.node);
	if (ran_end >= ip->ino_data.size) {
		dip = hammer_find_inode(&trans, ip->ino_data.parent_obj_id,
					ip->obj_asof, ip->obj_localization);
		if (dip) {
			hammer_cache_node(&dip->cache[3], cursor.node);
			hammer_rel_inode(dip, 0);
		}
	}
	hammer_done_cursor(&cursor);
	hammer_done_transaction(&trans);
	lwkt_reltoken(&hmp->fs_token);
	return(error);
}

/*
 * BMAP operation - used to support cluster_read() only.
 *
 * (struct vnode *vp, off_t loffset, off_t *doffsetp, int *runp, int *runb)
 *
 * This routine may return EOPNOTSUPP if the opration is not supported for
 * the specified offset.  The contents of the pointer arguments do not
 * need to be initialized in that case.
 *
 * If a disk address is available and properly aligned return 0 with
 * *doffsetp set to the zone-2 address, and *runp / *runb set appropriately
 * to the run-length relative to that offset.  Callers may assume that
 * *doffsetp is valid if 0 is returned, even if *runp is not sufficiently
 * large, so return EOPNOTSUPP if it is not sufficiently large.
 */
static
int
hammer_vop_bmap(struct vop_bmap_args *ap)
{
	struct hammer_transaction trans;
	hammer_inode_t ip;
	hammer_mount_t hmp;
	struct hammer_cursor cursor;
	hammer_base_elm_t base;
	int64_t rec_offset;
	int64_t ran_end;
	int64_t tmp64;
	int64_t base_offset;
	int64_t base_disk_offset;
	int64_t last_offset;
	hammer_off_t last_disk_offset;
	hammer_off_t disk_offset;
	int	rec_len;
	int	error;
	int	blksize;

	ip = ap->a_vp->v_data;
	hmp = ip->hmp;

	/*
	 * We can only BMAP regular files.  We can't BMAP database files,
	 * directories, etc.
	 */
	if (ip->ino_data.obj_type != HAMMER_OBJTYPE_REGFILE)
		return(EOPNOTSUPP);

	/*
	 * bmap is typically called with runp/runb both NULL when used
	 * for writing.  We do not support BMAP for writing atm.
	 */
	if (ap->a_cmd != BUF_CMD_READ)
		return(EOPNOTSUPP);

	/*
	 * Scan the B-Tree to acquire blockmap addresses, then translate
	 * to raw addresses.
	 */
	lwkt_gettoken(&hmp->fs_token);
	hammer_simple_transaction(&trans, hmp);

	hammer_init_cursor(&trans, &cursor, &ip->cache[1], ip);

	/*
	 * Key range (begin and end inclusive) to scan.  Note that the key's
	 * stored in the actual records represent BASE+LEN, not BASE.  The
	 * first record containing bio_offset will have a key > bio_offset.
	 */
	cursor.key_beg.localization = ip->obj_localization |
				      HAMMER_LOCALIZE_MISC;
	cursor.key_beg.obj_id = ip->obj_id;
	cursor.key_beg.create_tid = 0;
	cursor.key_beg.delete_tid = 0;
	cursor.key_beg.obj_type = 0;
	if (ap->a_runb)
		cursor.key_beg.key = ap->a_loffset - MAXPHYS + 1;
	else
		cursor.key_beg.key = ap->a_loffset + 1;
	if (cursor.key_beg.key < 0)
		cursor.key_beg.key = 0;
	cursor.asof = ip->obj_asof;
	cursor.flags |= HAMMER_CURSOR_ASOF;

	cursor.key_end = cursor.key_beg;
	KKASSERT(ip->ino_data.obj_type == HAMMER_OBJTYPE_REGFILE);

	ran_end = ap->a_loffset + MAXPHYS;
	cursor.key_beg.rec_type = HAMMER_RECTYPE_DATA;
	cursor.key_end.rec_type = HAMMER_RECTYPE_DATA;
	tmp64 = ran_end + MAXPHYS + 1;	/* work-around GCC-4 bug */
	if (tmp64 < ran_end)
		cursor.key_end.key = HAMMER_MAX_KEY;
	else
		cursor.key_end.key = ran_end + MAXPHYS + 1;

	cursor.flags |= HAMMER_CURSOR_END_INCLUSIVE;

	error = hammer_ip_first(&cursor);
	base_offset = last_offset = 0;
	base_disk_offset = last_disk_offset = 0;

	while (error == 0) {
		/*
		 * Get the base file offset of the record.  The key for
		 * data records is (base + bytes) rather then (base).
		 *
		 * NOTE: rec_offset + rec_len may exceed the end-of-file.
		 * The extra bytes should be zero on-disk and the BMAP op
		 * should still be ok.
		 */
		base = &cursor.leaf->base;
		rec_offset = base->key - cursor.leaf->data_len;
		rec_len    = cursor.leaf->data_len;

		/*
		 * Incorporate any cached truncation.
		 *
		 * NOTE: Modifications to rec_len based on synthesized
		 * truncation points remove the guarantee that any extended
		 * data on disk is zero (since the truncations may not have
		 * taken place on-media yet).
		 */
		if (ip->flags & HAMMER_INODE_TRUNCATED) {
			if (hammer_cursor_ondisk(&cursor) ||
			    cursor.iprec->flush_state == HAMMER_FST_FLUSH) {
				if (ip->trunc_off <= rec_offset)
					rec_len = 0;
				else if (ip->trunc_off < rec_offset + rec_len)
					rec_len = (int)(ip->trunc_off - rec_offset);
			}
		}
		if (ip->sync_flags & HAMMER_INODE_TRUNCATED) {
			if (hammer_cursor_ondisk(&cursor)) {
				if (ip->sync_trunc_off <= rec_offset)
					rec_len = 0;
				else if (ip->sync_trunc_off < rec_offset + rec_len)
					rec_len = (int)(ip->sync_trunc_off - rec_offset);
			}
		}

		/*
		 * Accumulate information.  If we have hit a discontiguous
		 * block reset base_offset unless we are already beyond the
		 * requested offset.  If we are, that's it, we stop.
		 */
		if (error)
			break;
		if (hammer_cursor_ondisk(&cursor)) {
			disk_offset = cursor.leaf->data_offset;
			if (rec_offset != last_offset ||
			    disk_offset != last_disk_offset) {
				if (rec_offset > ap->a_loffset)
					break;
				base_offset = rec_offset;
				base_disk_offset = disk_offset;
			}
			last_offset = rec_offset + rec_len;
			last_disk_offset = disk_offset + rec_len;
		}
		error = hammer_ip_next(&cursor);
	}

	if (cursor.node)
		hammer_cache_node(&ip->cache[1], cursor.node);

	hammer_done_cursor(&cursor);
	hammer_done_transaction(&trans);
	lwkt_reltoken(&hmp->fs_token);

	/*
	 * If we couldn't find any records or the records we did find were
	 * all behind the requested offset, return failure.  A forward
	 * truncation can leave a hole w/ no on-disk records.
	 */
	if (last_offset == 0 || last_offset < ap->a_loffset)
		return (EOPNOTSUPP);

	/*
	 * Figure out the block size at the requested offset and adjust
	 * our limits so the cluster_read() does not create inappropriately
	 * sized buffer cache buffers.
	 */
	blksize = hammer_blocksize(ap->a_loffset);
	if (hammer_blocksize(base_offset) != blksize) {
		base_offset = hammer_blockdemarc(base_offset, ap->a_loffset);
	}
	if (last_offset != ap->a_loffset &&
	    hammer_blocksize(last_offset - 1) != blksize) {
		last_offset = hammer_blockdemarc(ap->a_loffset,
						 last_offset - 1);
	}

	/*
	 * Returning EOPNOTSUPP simply prevents the direct-IO optimization
	 * from occuring.
	 */
	disk_offset = base_disk_offset + (ap->a_loffset - base_offset);

	if (!hammer_is_zone_large_data(disk_offset)) {
		/*
		 * Only large-data zones can be direct-IOd
		 */
		error = EOPNOTSUPP;
	} else if ((disk_offset & HAMMER_BUFMASK) ||
		   (last_offset - ap->a_loffset) < blksize) {
		/*
		 * doffsetp is not aligned or the forward run size does
		 * not cover a whole buffer, disallow the direct I/O.
		 */
		error = EOPNOTSUPP;
	} else {
		/*
		 * We're good.
		 */
		*ap->a_doffsetp = disk_offset;
		if (ap->a_runb) {
			*ap->a_runb = ap->a_loffset - base_offset;
			KKASSERT(*ap->a_runb >= 0);
		}
		if (ap->a_runp) {
			*ap->a_runp = last_offset - ap->a_loffset;
			KKASSERT(*ap->a_runp >= 0);
		}
		error = 0;
	}
	return(error);
}

/*
 * Write to a regular file.   Because this is a strategy call the OS is
 * trying to actually get data onto the media.
 */
static
int
hammer_vop_strategy_write(struct vop_strategy_args *ap)
{
	hammer_record_t record;
	hammer_mount_t hmp;
	hammer_inode_t ip;
	struct bio *bio;
	struct buf *bp;
	int blksize __debugvar;
	int bytes;
	int error;

	bio = ap->a_bio;
	bp = bio->bio_buf;
	ip = ap->a_vp->v_data;
	hmp = ip->hmp;

	blksize = hammer_blocksize(bio->bio_offset);
	KKASSERT(bp->b_bufsize == blksize);

	if (ip->flags & HAMMER_INODE_RO) {
		bp->b_error = EROFS;
		bp->b_flags |= B_ERROR;
		biodone(ap->a_bio);
		return(EROFS);
	}

	lwkt_gettoken(&hmp->fs_token);

	/*
	 * Disallow swapcache operation on the vnode buffer if double
	 * buffering is enabled, the swapcache will get the data via
	 * the block device buffer.
	 */
	if (hammer_double_buffer)
		bp->b_flags |= B_NOTMETA;

	/*
	 * Interlock with inode destruction (no in-kernel or directory
	 * topology visibility).  If we queue new IO while trying to
	 * destroy the inode we can deadlock the vtrunc call in
	 * hammer_inode_unloadable_check().
	 *
	 * Besides, there's no point flushing a bp associated with an
	 * inode that is being destroyed on-media and has no kernel
	 * references.
	 */
	if ((ip->flags | ip->sync_flags) &
	    (HAMMER_INODE_DELETING|HAMMER_INODE_DELETED)) {
		bp->b_resid = 0;
		biodone(ap->a_bio);
		lwkt_reltoken(&hmp->fs_token);
		return(0);
	}

	/*
	 * Reserve space and issue a direct-write from the front-end.
	 * NOTE: The direct_io code will hammer_bread/bcopy smaller
	 * allocations.
	 *
	 * An in-memory record will be installed to reference the storage
	 * until the flusher can get to it.
	 *
	 * Since we own the high level bio the front-end will not try to
	 * do a direct-read until the write completes.
	 *
	 * NOTE: The only time we do not reserve a full-sized buffers
	 * worth of data is if the file is small.  We do not try to
	 * allocate a fragment (from the small-data zone) at the end of
	 * an otherwise large file as this can lead to wildly separated
	 * data.
	 */
	KKASSERT((bio->bio_offset & HAMMER_BUFMASK) == 0);
	KKASSERT(bio->bio_offset < ip->ino_data.size);
	if (bio->bio_offset || ip->ino_data.size > HAMMER_HBUFSIZE)
		bytes = bp->b_bufsize;
	else
		bytes = HAMMER_DATA_DOALIGN_WITH(int, ip->ino_data.size);

	record = hammer_ip_add_bulk(ip, bio->bio_offset, bp->b_data,
				    bytes, &error);

	/*
	 * B_VFSFLAG1 indicates that a REDO_WRITE entry was generated
	 * in hammer_vop_write().  We must flag the record so the proper
	 * REDO_TERM_WRITE entry is generated during the flush.
	 */
	if (record) {
		if (bp->b_flags & B_VFSFLAG1) {
			record->flags |= HAMMER_RECF_REDO;
			bp->b_flags &= ~B_VFSFLAG1;
		}
		hammer_io_direct_write(hmp, bio, record);
		if (ip->rsv_recs > 1 && hmp->rsv_recs > hammer_limit_recs)
			hammer_flush_inode(ip, 0);
	} else {
		bp->b_bio2.bio_offset = NOOFFSET;
		bp->b_error = error;
		bp->b_flags |= B_ERROR;
		biodone(ap->a_bio);
	}
	lwkt_reltoken(&hmp->fs_token);
	return(error);
}

/*
 * dounlink - disconnect a directory entry
 *
 * XXX whiteout support not really in yet
 */
static int
hammer_dounlink(hammer_transaction_t trans, struct nchandle *nch,
		struct vnode *dvp, struct ucred *cred,
		int flags, int isdir)
{
	struct namecache *ncp;
	hammer_inode_t dip;
	hammer_inode_t ip;
	hammer_mount_t hmp;
	struct hammer_cursor cursor;
	int64_t namekey;
	uint32_t max_iterations;
	int nlen, error;

	/*
	 * Calculate the namekey and setup the key range for the scan.  This
	 * works kinda like a chained hash table where the lower 32 bits
	 * of the namekey synthesize the chain.
	 *
	 * The key range is inclusive of both key_beg and key_end.
	 */
	dip = VTOI(dvp);
	ncp = nch->ncp;
	hmp = dip->hmp;

	if (dip->flags & HAMMER_INODE_RO)
		return (EROFS);

	namekey = hammer_direntry_namekey(dip, ncp->nc_name, ncp->nc_nlen,
					   &max_iterations);
retry:
	hammer_init_cursor(trans, &cursor, &dip->cache[1], dip);
	cursor.key_beg.localization = dip->obj_localization |
				      hammer_dir_localization(dip);
        cursor.key_beg.obj_id = dip->obj_id;
	cursor.key_beg.key = namekey;
        cursor.key_beg.create_tid = 0;
        cursor.key_beg.delete_tid = 0;
        cursor.key_beg.rec_type = HAMMER_RECTYPE_DIRENTRY;
        cursor.key_beg.obj_type = 0;

	cursor.key_end = cursor.key_beg;
	cursor.key_end.key += max_iterations;
	cursor.asof = dip->obj_asof;
	cursor.flags |= HAMMER_CURSOR_END_INCLUSIVE | HAMMER_CURSOR_ASOF;

	/*
	 * Scan all matching records (the chain), locate the one matching
	 * the requested path component.  info->last_error contains the
	 * error code on search termination and could be 0, ENOENT, or
	 * something else.
	 *
	 * The hammer_ip_*() functions merge in-memory records with on-disk
	 * records for the purposes of the search.
	 */
	error = hammer_ip_first(&cursor);

	while (error == 0) {
		error = hammer_ip_resolve_data(&cursor);
		if (error)
			break;
		nlen = cursor.leaf->data_len - HAMMER_ENTRY_NAME_OFF;
		KKASSERT(nlen > 0);
		if (ncp->nc_nlen == nlen &&
		    bcmp(ncp->nc_name, cursor.data->entry.name, nlen) == 0) {
			break;
		}
		error = hammer_ip_next(&cursor);
	}

	/*
	 * If all is ok we have to get the inode so we can adjust nlinks.
	 * To avoid a deadlock with the flusher we must release the inode
	 * lock on the directory when acquiring the inode for the entry.
	 *
	 * If the target is a directory, it must be empty.
	 */
	if (error == 0) {
		hammer_unlock(&cursor.ip->lock);
		ip = hammer_get_inode(trans, dip, cursor.data->entry.obj_id,
				      hmp->asof,
				      cursor.data->entry.localization,
				      0, &error);
		hammer_lock_sh(&cursor.ip->lock);
		if (error == ENOENT) {
			hkprintf("WARNING: Removing dirent w/missing inode "
				"\"%s\"\n"
				"\tobj_id = %016jx\n",
				ncp->nc_name,
				(intmax_t)cursor.data->entry.obj_id);
			error = 0;
		}

		/*
		 * If isdir >= 0 we validate that the entry is or is not a
		 * directory.  If isdir < 0 we don't care.
		 */
		if (error == 0 && isdir >= 0 && ip) {
			if (isdir &&
			    ip->ino_data.obj_type != HAMMER_OBJTYPE_DIRECTORY) {
				error = ENOTDIR;
			} else if (isdir == 0 &&
			    ip->ino_data.obj_type == HAMMER_OBJTYPE_DIRECTORY) {
				error = EISDIR;
			}
		}

		/*
		 * If we are trying to remove a directory the directory must
		 * be empty.
		 *
		 * The check directory code can loop and deadlock/retry.  Our
		 * own cursor's node locks must be released to avoid a 3-way
		 * deadlock with the flusher if the check directory code
		 * blocks.
		 *
		 * If any changes whatsoever have been made to the cursor
		 * set EDEADLK and retry.
		 *
		 * WARNING: See warnings in hammer_unlock_cursor()
		 *	    function.
		 */
		if (error == 0 && ip && ip->ino_data.obj_type ==
				        HAMMER_OBJTYPE_DIRECTORY) {
			hammer_unlock_cursor(&cursor);
			error = hammer_ip_check_directory_empty(trans, ip);
			hammer_lock_cursor(&cursor);
			if (cursor.flags & HAMMER_CURSOR_RETEST) {
				hkprintf("Warning: avoided deadlock "
					"on rmdir '%s'\n",
					ncp->nc_name);
				error = EDEADLK;
			}
		}

		/*
		 * Delete the directory entry.
		 *
		 * WARNING: hammer_ip_del_direntry() may have to terminate
		 * the cursor to avoid a deadlock.  It is ok to call
		 * hammer_done_cursor() twice.
		 */
		if (error == 0) {
			error = hammer_ip_del_direntry(trans, &cursor,
							dip, ip);
		}
		hammer_done_cursor(&cursor);
		if (error == 0) {
			/*
			 * Tell the namecache that we are now unlinked.
			 */
			cache_unlink(nch);

			/*
			 * NOTE: ip->vp, if non-NULL, cannot be directly
			 *	 referenced without formally acquiring the
			 *	 vp since the vp might have zero refs on it,
			 *	 or in the middle of a reclaim, etc.
			 *
			 * NOTE: The cache_setunresolved() can rip the vp
			 *	 out from under us since the vp may not have
			 *	 any refs, in which case ip->vp will be NULL
			 *	 from the outset.
			 */
			while (ip && ip->vp) {
				struct vnode *vp;

				error = hammer_get_vnode(ip, &vp);
				if (error == 0 && vp) {
					vn_unlock(vp);
					hammer_knote(ip->vp, NOTE_DELETE);
#if 0
					/*
					 * Don't do this, it can deadlock
					 * on concurrent rm's of hardlinks.
					 * Shouldn't be needed any more.
					 */
					cache_inval_vp(ip->vp, CINV_DESTROY);
#endif
					vrele(vp);
					break;
				}
				hdkprintf("ip/vp race1 avoided\n");
			}
		}
		if (ip)
			hammer_rel_inode(ip, 0);
	} else {
		hammer_done_cursor(&cursor);
	}
	if (error == EDEADLK)
		goto retry;

	return (error);
}

/************************************************************************
 *			    FIFO AND SPECFS OPS				*
 ************************************************************************
 *
 */
static int
hammer_vop_fifoclose (struct vop_close_args *ap)
{
	/* XXX update itimes */
	return (VOCALL(&fifo_vnode_vops, &ap->a_head));
}

static int
hammer_vop_fiforead (struct vop_read_args *ap)
{
	int error;

	error = VOCALL(&fifo_vnode_vops, &ap->a_head);
	/* XXX update access time */
	return (error);
}

static int
hammer_vop_fifowrite (struct vop_write_args *ap)
{
	int error;

	error = VOCALL(&fifo_vnode_vops, &ap->a_head);
	/* XXX update access time */
	return (error);
}

static
int
hammer_vop_fifokqfilter(struct vop_kqfilter_args *ap)
{
	int error;

	error = VOCALL(&fifo_vnode_vops, &ap->a_head);
	if (error)
		error = hammer_vop_kqfilter(ap);
	return(error);
}

/************************************************************************
 *			    KQFILTER OPS				*
 ************************************************************************
 *
 */
static void filt_hammerdetach(struct knote *kn);
static int filt_hammerread(struct knote *kn, long hint);
static int filt_hammerwrite(struct knote *kn, long hint);
static int filt_hammervnode(struct knote *kn, long hint);

static struct filterops hammerread_filtops =
	{ FILTEROP_ISFD | FILTEROP_MPSAFE,
	  NULL, filt_hammerdetach, filt_hammerread };
static struct filterops hammerwrite_filtops =
	{ FILTEROP_ISFD | FILTEROP_MPSAFE,
	  NULL, filt_hammerdetach, filt_hammerwrite };
static struct filterops hammervnode_filtops =
	{ FILTEROP_ISFD | FILTEROP_MPSAFE,
	  NULL, filt_hammerdetach, filt_hammervnode };

static
int
hammer_vop_kqfilter(struct vop_kqfilter_args *ap)
{
	struct vnode *vp = ap->a_vp;
	struct knote *kn = ap->a_kn;

	switch (kn->kn_filter) {
	case EVFILT_READ:
		kn->kn_fop = &hammerread_filtops;
		break;
	case EVFILT_WRITE:
		kn->kn_fop = &hammerwrite_filtops;
		break;
	case EVFILT_VNODE:
		kn->kn_fop = &hammervnode_filtops;
		break;
	default:
		return (EOPNOTSUPP);
	}

	kn->kn_hook = (caddr_t)vp;

	knote_insert(&vp->v_pollinfo.vpi_kqinfo.ki_note, kn);

	return(0);
}

static void
filt_hammerdetach(struct knote *kn)
{
	struct vnode *vp = (void *)kn->kn_hook;

	knote_remove(&vp->v_pollinfo.vpi_kqinfo.ki_note, kn);
}

static int
filt_hammerread(struct knote *kn, long hint)
{
	struct vnode *vp = (void *)kn->kn_hook;
	hammer_inode_t ip = VTOI(vp);
	hammer_mount_t hmp = ip->hmp;
	off_t off;

	if (hint == NOTE_REVOKE) {
		kn->kn_flags |= (EV_EOF | EV_NODATA | EV_ONESHOT);
		return(1);
	}
	lwkt_gettoken(&hmp->fs_token);	/* XXX use per-ip-token */
	off = ip->ino_data.size - kn->kn_fp->f_offset;
	kn->kn_data = (off < INTPTR_MAX) ? off : INTPTR_MAX;
	lwkt_reltoken(&hmp->fs_token);
	if (kn->kn_sfflags & NOTE_OLDAPI)
		return(1);
	return (kn->kn_data != 0);
}

static int
filt_hammerwrite(struct knote *kn, long hint)
{
	if (hint == NOTE_REVOKE)
		kn->kn_flags |= (EV_EOF | EV_NODATA | EV_ONESHOT);
	kn->kn_data = 0;
	return (1);
}

static int
filt_hammervnode(struct knote *kn, long hint)
{
	if (kn->kn_sfflags & hint)
		kn->kn_fflags |= hint;
	if (hint == NOTE_REVOKE) {
		kn->kn_flags |= (EV_EOF | EV_NODATA);
		return (1);
	}
	return (kn->kn_fflags != 0);
}
#endif /* phase 2 */

/*
 * Rhapsody vnode operations: 4.4BSD componentname VOPs over HAMMER.
 * The namespace operations follow the 4.4BSD protocol (ufs_* is the
 * model): each releases the vnodes and name buffer it is passed, through
 * the matching nop_* helper, whether it succeeds or not.  The HAMMER work
 * inside each is upstream's hammer_vop_n*() with the namecache calls
 * replaced by cache_purge().
 */
int (**hammer_vnodeop_p)(void *);

static int hammer_lookup_name(hammer_inode_t dip, const char *name, int nlen,
			      int64_t *obj_idp, uint32_t *localizationp);
static int hammer_fsync_ip(hammer_inode_t ip, int waitfor);

/*
 * Return a locked, referenced vnode for object OBJ_ID of the mount.
 */
int
hammer_vget_obj(hammer_mount_t hmp, int64_t obj_id, uint32_t localization,
		struct vnode **vpp)
{
	struct hammer_transaction trans;
	hammer_inode_t ip;
	int error;

	hammer_simple_transaction(&trans, hmp);
	ip = hammer_get_inode(&trans, NULL, obj_id, hmp->asof, localization,
			      0, &error);
	if (ip) {
		error = hammer_get_vnode(ip, vpp);
		hammer_rel_inode(ip, 0);
	} else {
		*vpp = NULL;
	}
	hammer_done_transaction(&trans);
	return(error);
}

/*
 * A directory entry whose name length does not fit NAME_MAX or its own
 * record is damage; report it rather than trust it.
 */
static int
hammer_entry_namelen(hammer_inode_t dip, hammer_btree_leaf_elm_t leaf)
{
	int nlen = (int)hget32(leaf->data_len) - (int)HAMMER_ENTRY_NAME_OFF;

	if (nlen <= 0 || nlen > MAXNAMLEN) {
		hkprintf("directory %016jx: entry %016jx has a %d-byte name\n",
			 (intmax_t)dip->obj_id, (intmax_t)hget64(leaf->base.key),
			 nlen);
		return(-1);
	}
	return(nlen);
}

static void
hammer_dir_cursor(hammer_cursor_t cursor, hammer_inode_t dip, int64_t key)
{
	cursor->key_beg.localization = hmk32(dip->obj_localization |
					     hammer_dir_localization(dip));
	cursor->key_beg.obj_id = hmk64(dip->obj_id);
	cursor->key_beg.key = hmk64(key);
	cursor->key_beg.create_tid = hmk64(0);
	cursor->key_beg.delete_tid = hmk64(0);
	cursor->key_beg.rec_type = hmk16(HAMMER_RECTYPE_DIRENTRY);
	cursor->key_beg.obj_type = 0;
	cursor->key_end = cursor->key_beg;
	cursor->asof = dip->obj_asof;
	cursor->flags |= HAMMER_CURSOR_END_INCLUSIVE | HAMMER_CURSOR_ASOF;
}

/*
 * Position an initialized CURSOR on NAME's entry in directory DIP, by
 * scanning the name's hash chain (the hammer_ip_*() functions merge
 * in-memory records with on-disk ones).  Returns 0, ENOENT, or EIO for a
 * damaged entry on the chain.
 */
static int
hammer_find_entry(hammer_cursor_t cursor, hammer_inode_t dip,
		  const char *name, int nlen)
{
	uint32_t max_iterations;
	int64_t namekey;
	int error, elen;

	namekey = hammer_direntry_namekey(dip, name, nlen, &max_iterations);
	if (namekey < 0)
		return(EIO);
	hammer_dir_cursor(cursor, dip, namekey);
	cursor->key_end.key = hmk64(namekey + max_iterations);
	error = hammer_ip_first(cursor);
	while (error == 0) {
		error = hammer_ip_resolve_data(cursor);
		if (error)
			break;
		elen = hammer_entry_namelen(dip, cursor->leaf);
		if (elen < 0)
			return(EIO);
		if (elen == nlen &&
		    bcmp(name, cursor->data->entry.name, nlen) == 0)
			break;
		error = hammer_ip_next(cursor);
	}
	return(error);
}

/*
 * Find NAME in directory DIP.  Returns 0 with the entry's object, ENOENT,
 * or EIO for a damaged entry on the name's hash chain.
 */
static int
hammer_lookup_name(hammer_inode_t dip, const char *name, int nlen,
		   int64_t *obj_idp, uint32_t *localizationp)
{
	struct hammer_transaction trans;
	struct hammer_cursor cursor;
	int error;

	hammer_simple_transaction(&trans, dip->hmp);
	error = hammer_init_cursor(&trans, &cursor, &dip->cache[1], dip);
	if (error == 0)
		error = hammer_find_entry(&cursor, dip, name, nlen);
	if (error == 0) {
		*obj_idp = (int64_t)hget64(cursor.data->entry.obj_id);
		*localizationp = hget32(cursor.data->entry.localization);
	}
	hammer_done_cursor(&cursor);
	hammer_done_transaction(&trans);
	return(error);
}

/*
 * Deleting or renaming an entry of a sticky directory takes ownership of
 * the directory or the entry (ufs_lookup).
 */
static int
hammer_sticky_denied(hammer_inode_t dip, hammer_inode_t ip, struct ucred *cred)
{
	return((hget16(dip->ino_data.mode) & S_ISTXT) && cred->cr_uid != 0 &&
	       cred->cr_uid != hammer_to_unix_xid(&dip->ino_data.uid) &&
	       cred->cr_uid != hammer_to_unix_xid(&ip->ino_data.uid));
}

/*
 * The ufs lookup protocol (LOCKPARENT, ISDOTDOT, the name cache), as in
 * cd9660_lookup.
 */
static int
hammer_vop_lookup(struct vop_lookup_args *ap)
{
	struct vnode *vdp = ap->a_dvp;
	struct vnode **vpp = ap->a_vpp;
	struct componentname *cnp = ap->a_cnp;
	struct proc *p = cnp->cn_proc;
	int flags = cnp->cn_flags;
	int nameiop = cnp->cn_nameiop;
	int lockparent = flags & LOCKPARENT;
	struct vnode *pdp, *tdp;
	hammer_inode_t dip;
	uint32_t localization;
	int64_t obj_id;
	int error, vpid;

	*vpp = NULL;
	dip = VTOI(vdp);
	if (vdp->v_type != VDIR)
		return(ENOTDIR);
	if ((error = VOP_ACCESS(vdp, VEXEC, cnp->cn_cred, p)) != 0)
		return(error);

	if ((error = cache_lookup(vdp, vpp, cnp)) != 0) {
		if (error == ENOENT)
			return(error);
		pdp = vdp;
		vdp = *vpp;
		vpid = vdp->v_id;
		if (pdp == vdp) {
			VREF(vdp);
			error = 0;
		} else if (flags & ISDOTDOT) {
			VOP_UNLOCK(pdp, 0, p);
			error = vget(vdp, LK_EXCLUSIVE | LK_RETRY, p);
			if (!error && lockparent && (flags & ISLASTCN))
				error = VOP_LOCK(pdp, LK_EXCLUSIVE | LK_RETRY, p);
		} else {
			error = vget(vdp, LK_EXCLUSIVE | LK_RETRY, p);
			if (!lockparent || error || !(flags & ISLASTCN))
				VOP_UNLOCK(pdp, 0, p);
		}
		if (!error) {
			if (vpid == vdp->v_id)
				return(0);
			vput(vdp);
			if (lockparent && pdp != vdp && (flags & ISLASTCN))
				VOP_UNLOCK(pdp, 0, p);
		}
		if ((error = VOP_LOCK(pdp, LK_EXCLUSIVE | LK_RETRY, p)) != 0)
			return(error);
		vdp = pdp;
		*vpp = NULL;
	}

	localization = dip->obj_localization;
	if (flags & ISDOTDOT) {
		/*
		 * namei never asks for ".." of the mount root, so a
		 * directory that names itself (or no parent) is damage;
		 * looking it up would relock the directory we hold.
		 */
		obj_id = (int64_t)hget64(dip->ino_data.parent_obj_id);
		if (obj_id == 0 || obj_id == dip->obj_id) {
			hkprintf("directory %016jx: bad parent %016jx\n",
				 (intmax_t)dip->obj_id, (intmax_t)obj_id);
			return(EIO);
		}
	} else if (cnp->cn_namelen == 1 && cnp->cn_nameptr[0] == '.') {
		obj_id = dip->obj_id;
	} else {
		error = hammer_lookup_name(dip, cnp->cn_nameptr,
					   cnp->cn_namelen, &obj_id,
					   &localization);
		if (error == ENOENT) {
			/*
			 * A missing last component may be created: the
			 * caller gets EJUSTRETURN with the name saved.
			 */
			if ((nameiop == CREATE || nameiop == RENAME) &&
			    (flags & ISLASTCN)) {
				error = VOP_ACCESS(vdp, VWRITE, cnp->cn_cred, p);
				if (error)
					return(error);
				cnp->cn_flags |= SAVENAME;
				if (!lockparent)
					VOP_UNLOCK(vdp, 0, p);
				return(EJUSTRETURN);
			}
			if ((cnp->cn_flags & MAKEENTRY) && nameiop != CREATE)
				cache_enter(vdp, *vpp, cnp);
			return(ENOENT);
		}
		if (error)
			return(error);
	}

	/*
	 * Removing or renaming an existing last component needs write
	 * access to the directory; a rename keeps the name (ufs_lookup).
	 */
	if ((nameiop == DELETE || nameiop == RENAME) && (flags & ISLASTCN)) {
		if ((error = VOP_ACCESS(vdp, VWRITE, cnp->cn_cred, p)) != 0)
			return(error);
		if (nameiop == RENAME) {
			if (obj_id == dip->obj_id)
				return(EISDIR);
			cnp->cn_flags |= SAVENAME;
		}
	}

	pdp = vdp;
	if (flags & ISDOTDOT) {
		VOP_UNLOCK(pdp, 0, p);
		error = hammer_vget_obj(dip->hmp, obj_id, localization, &tdp);
		if (error) {
			VOP_LOCK(pdp, LK_EXCLUSIVE | LK_RETRY, p);
			return(error);
		}
		if (lockparent && (flags & ISLASTCN) &&
		    (error = VOP_LOCK(pdp, LK_EXCLUSIVE | LK_RETRY, p)) != 0) {
			vput(tdp);
			return(error);
		}
		*vpp = tdp;
	} else if (obj_id == dip->obj_id) {
		VREF(vdp);
		*vpp = vdp;
	} else {
		error = hammer_vget_obj(dip->hmp, obj_id, localization, &tdp);
		if (error)
			return(error);
		if ((nameiop == DELETE || nameiop == RENAME) &&
		    (flags & ISLASTCN) &&
		    hammer_sticky_denied(dip, VTOI(tdp), cnp->cn_cred)) {
			vput(tdp);
			return(EPERM);
		}
		if (!lockparent || !(flags & ISLASTCN))
			VOP_UNLOCK(pdp, 0, p);
		*vpp = tdp;
	}
	if (cnp->cn_flags & MAKEENTRY)
		cache_enter(vdp, *vpp, cnp);
	return(0);
}

/*
 * An append-only file opens for writing only to append (ufs_open).
 */
static int
hammer_vop_open(struct vop_open_args *ap)
{
	if ((hget32(VTOI(ap->a_vp)->ino_data.uflags) & APPEND) &&
	    (ap->a_mode & (FWRITE | O_APPEND)) == FWRITE)
		return(EPERM);
	return(0);
}

static int
hammer_vop_close(struct vop_close_args *ap)
{
	return(0);
}

static int
hammer_vop_access(struct vop_access_args *ap)
{
	struct vnode *vp = ap->a_vp;
	hammer_inode_t ip = VTOI(vp);
	struct ucred *cred = ap->a_cred;
	mode_t mask = 0, mode = ap->a_mode;
	mode_t imode = hget16(ip->ino_data.mode);
	uid_t uid;
	gid_t gid;
	int i;

	if ((mode & VWRITE) &&
	    ((vp->v_mount->mnt_flag & MNT_RDONLY) || ip->hmp->ronly)) {
		switch (vp->v_type) {
		case VDIR:
		case VLNK:
		case VREG:
			return(EROFS);
		default:
			break;
		}
	}
	if ((mode & VWRITE) && (hget32(ip->ino_data.uflags) & IMMUTABLE))
		return(EPERM);
	if (cred->cr_uid == 0)
		return(0);
	uid = hammer_to_unix_xid(&ip->ino_data.uid);
	gid = hammer_to_unix_xid(&ip->ino_data.gid);
	if (cred->cr_uid == uid) {
		if (mode & VEXEC)
			mask |= S_IXUSR;
		if (mode & VREAD)
			mask |= S_IRUSR;
		if (mode & VWRITE)
			mask |= S_IWUSR;
		return((imode & mask) == mask ? 0 : EACCES);
	}
	for (i = 0; i < cred->cr_ngroups; i++) {
		if (cred->cr_groups[i] == gid) {
			if (mode & VEXEC)
				mask |= S_IXGRP;
			if (mode & VREAD)
				mask |= S_IRGRP;
			if (mode & VWRITE)
				mask |= S_IWGRP;
			return((imode & mask) == mask ? 0 : EACCES);
		}
	}
	if (mode & VEXEC)
		mask |= S_IXOTH;
	if (mode & VREAD)
		mask |= S_IROTH;
	if (mode & VWRITE)
		mask |= S_IWOTH;
	return((imode & mask) == mask ? 0 : EACCES);
}

static int
hammer_vop_getattr(struct vop_getattr_args *ap)
{
	struct vnode *vp = ap->a_vp;
	hammer_inode_t ip = VTOI(vp);
	hammer_inode_data_t d = &ip->ino_data;
	struct vattr *vap = ap->a_vap;
	uint64_t size = hget64(d->size);
	uint64_t nlinks = hget64(d->nlinks);

	vap->va_type = hammer_get_vnode_type(d->obj_type);
	vap->va_mode = hget16(d->mode);
	vap->va_nlink = nlinks > 0x7fff ? 0x7fff : (short)nlinks;
	vap->va_uid = hammer_to_unix_xid(&d->uid);
	vap->va_gid = hammer_to_unix_xid(&d->gid);
	vap->va_fsid = vp->v_mount->mnt_stat.f_fsid.val[0];
	vap->va_fileid = hammer_ino32(ip->obj_id);
	vap->va_size = size;
	vap->va_blocksize = HAMMER_BUFSIZE;
	hammer_time_to_timespec(hget64(d->atime), &vap->va_atime);
	hammer_time_to_timespec(hget64(d->mtime), &vap->va_mtime);
	hammer_time_to_timespec(hget64(d->ctime), &vap->va_ctime);
	vap->va_gen = 1;	/* hammer inums are unique for all time */
	vap->va_flags = hget32(d->uflags);
	if (vap->va_type == VCHR || vap->va_type == VBLK)
		vap->va_rdev = makedev(hget32(d->rmajor), hget32(d->rminor));
	else
		vap->va_rdev = 0;
	if (size >= HAMMER_XDEMARC)
		vap->va_bytes = HAMMER_XBUFSIZE64_DOALIGN(size);
	else if (size > HAMMER_HBUFSIZE)
		vap->va_bytes = HAMMER_BUFSIZE64_DOALIGN(size);
	else
		vap->va_bytes = HAMMER_DATA_DOALIGN(size);
	vap->va_filerev = 0;
	vap->va_vaflags = 0;
	return(0);
}

/*
 * Emit one struct dirent.  Returns 1 when the caller should stop: the
 * record does not fit (nothing written) or uiomove failed (*errorp set).
 */
static int
hammer_dirent(struct uio *uio, int64_t obj_id, int type, const char *name,
	      int nlen, int *errorp)
{
	struct dirent d;
	int reclen = (offsetof(struct dirent, d_name) + nlen + 1 + 3) & ~3;

	if (uio->uio_resid < reclen)
		return(1);
	bzero(&d, reclen);
	d.d_fileno = hammer_ino32(obj_id);
	d.d_reclen = reclen;
	d.d_type = type;
	d.d_namlen = nlen;
	bcopy(name, d.d_name, nlen);
	*errorp = uiomove((caddr_t)&d, reclen, uio);
	return(*errorp != 0);
}

/*
 * uio_offset is a directory key: 0 is ".", 1 is "..", and real entries
 * resume at their own namekey (on-media keys are all >= 2^32).
 */
static int
hammer_vop_readdir(struct vop_readdir_args *ap)
{
	hammer_inode_t ip = VTOI(ap->a_vp);
	struct uio *uio = ap->a_uio;
	struct hammer_transaction trans;
	struct hammer_cursor cursor;
	hammer_btree_leaf_elm_t leaf;
	off_t saveoff = uio->uio_offset;
	int64_t parent;
	int error = 0, nlen;

	if (ap->a_ncookies) {		/* no NFS export in this release */
		*ap->a_ncookies = 0;
		*ap->a_cookies = NULL;
	}
	if (saveoff == 0) {
		if (hammer_dirent(uio, ip->obj_id, DT_DIR, ".", 1, &error))
			goto out;
		saveoff = 1;
	}
	if (saveoff == 1) {
		parent = (int64_t)hget64(ip->ino_data.parent_obj_id);
		if (hammer_dirent(uio, parent ? parent : ip->obj_id, DT_DIR,
				  "..", 2, &error))
			goto out;
		saveoff = 2;
	}

	hammer_simple_transaction(&trans, ip->hmp);
	error = hammer_init_cursor(&trans, &cursor, &ip->cache[1], ip);
	hammer_dir_cursor(&cursor, ip, saveoff);
	cursor.key_end.key = hmk64(HAMMER_MAX_KEY);
	if (error == 0)
		error = hammer_ip_first(&cursor);
	while (error == 0) {
		error = hammer_ip_resolve_data(&cursor);
		if (error)
			break;
		leaf = cursor.leaf;
		saveoff = (int64_t)hget64(leaf->base.key);
		nlen = hammer_entry_namelen(ip, leaf);
		if (nlen < 0) {
			error = EIO;
			break;
		}
		if (hammer_dirent(uio, (int64_t)hget64(cursor.data->entry.obj_id),
				  hammer_get_dtype(leaf->base.obj_type),
				  cursor.data->entry.name, nlen, &error))
			break;
		++saveoff;
		error = hammer_ip_next(&cursor);
	}
	hammer_done_cursor(&cursor);
	hammer_done_transaction(&trans);
	if (ap->a_eofflag)
		*ap->a_eofflag = (error == ENOENT);
	if (error == ENOENT)
		error = 0;
out:
	uio->uio_offset = saveoff;
	return(error);
}

static int
hammer_vop_readlink(struct vop_readlink_args *ap)
{
	hammer_inode_t ip = VTOI(ap->a_vp);
	struct hammer_transaction trans;
	struct hammer_cursor cursor;
	uint64_t size = hget64(ip->ino_data.size);
	int error, len;

	if (size <= HAMMER_INODE_BASESYMLEN)
		return(uiomove(ip->ino_data.ext.symlink, (int)size, ap->a_uio));

	hammer_simple_transaction(&trans, ip->hmp);
	error = hammer_init_cursor(&trans, &cursor, &ip->cache[1], ip);
	cursor.key_beg.localization = hmk32(ip->obj_localization |
					    HAMMER_LOCALIZE_MISC);
	cursor.key_beg.obj_id = hmk64(ip->obj_id);
	cursor.key_beg.create_tid = hmk64(0);
	cursor.key_beg.delete_tid = hmk64(0);
	cursor.key_beg.rec_type = hmk16(HAMMER_RECTYPE_FIX);
	cursor.key_beg.obj_type = 0;
	cursor.key_beg.key = hmk64(HAMMER_FIXKEY_SYMLINK);
	cursor.asof = ip->obj_asof;
	cursor.flags |= HAMMER_CURSOR_ASOF;
	if (error == 0)
		error = hammer_ip_lookup(&cursor);
	if (error == 0)
		error = hammer_ip_resolve_data(&cursor);
	if (error == 0) {
		len = (int)hget32(cursor.leaf->data_len) -
		      (int)HAMMER_SYMLINK_NAME_OFF;
		if (len < 0 || len > MAXPATHLEN) {
			hkprintf("symlink %016jx: bad %d-byte target\n",
				 (intmax_t)ip->obj_id, len);
			error = EIO;
		} else {
			error = uiomove(cursor.data->symlink.name, len,
					ap->a_uio);
		}
	}
	hammer_done_cursor(&cursor);
	hammer_done_transaction(&trans);
	return(error);
}

/*
 * The vnode lock is a lockmgr lock in the inode.  A vnode that lost its
 * inode (a reclaimed or never-attached one) has no lock to take.
 */
static int
hammer_vop_lock(struct vop_lock_args *ap)
{
	struct vnode *vp = ap->a_vp;

	if (VTOI(vp) == NULL) {
		if (ap->a_flags & LK_INTERLOCK)
			simple_unlock(&vp->v_interlock);
		return(0);
	}
	return(lockmgr(&VTOI(vp)->vnlock, ap->a_flags, &vp->v_interlock,
		       ap->a_p));
}

static int
hammer_vop_unlock(struct vop_unlock_args *ap)
{
	struct vnode *vp = ap->a_vp;

	if (VTOI(vp) == NULL) {
		if (ap->a_flags & LK_INTERLOCK)
			simple_unlock(&vp->v_interlock);
		return(0);
	}
	return(lockmgr(&VTOI(vp)->vnlock, ap->a_flags | LK_RELEASE,
		       &vp->v_interlock, ap->a_p));
}

static int
hammer_vop_islocked(struct vop_islocked_args *ap)
{
	if (VTOI(ap->a_vp) == NULL)
		return(0);
	return(lockstatus(&VTOI(ap->a_vp)->vnlock));
}

/*
 * The last use of the vnode is gone.  An inode with no links left is
 * queued for deletion and its vnode recycled at once (upstream's
 * hammer_vop_inactive); vnodes that never got an inode are dropped.
 */
int
hammer_vop_inactive(struct vop_inactive_args *ap)
{
	struct vnode *vp = ap->a_vp;
	hammer_inode_t ip = VTOI(vp);

	VOP_UNLOCK(vp, 0, ap->a_p);
	if (ip == NULL) {
		vgone(vp);
		return(0);
	}
	if (hget64(ip->ino_data.nlinks) == 0 && ip->hmp->ronly == 0) {
		hammer_inode_unloadable_check(ip, 0);
		if (ip->flags & HAMMER_INODE_MODMASK)
			hammer_flush_inode(ip, 0);
		vrecycle(vp, (struct slock *)0, ap->a_p);
	}
	return(0);
}

/*
 * Release the vnode's inode reference; the last one unloads the inode,
 * after a final flush if it is dirty (upstream's hammer_vop_reclaim).
 */
int
hammer_vop_reclaim(struct vop_reclaim_args *ap)
{
	struct vnode *vp = ap->a_vp;
	hammer_inode_t ip = VTOI(vp);
	hammer_mount_t hmp;

	cache_purge(vp);
	if (ip != NULL) {
		hmp = ip->hmp;
		hammer_lock_ex(&ip->lock);
		vp->v_data = NULL;
		ip->vp = NULL;
		if ((ip->flags & HAMMER_INODE_RECLAIM) == 0) {
			++hammer_count_reclaims;
			++hmp->count_reclaims;
			ip->flags |= HAMMER_INODE_RECLAIM;
		}
		hammer_unlock(&ip->lock);
		hammer_rel_inode(ip, 1);
	}
	return(0);
}

static int
hammer_vop_print(struct vop_print_args *ap)
{
	hammer_inode_t ip = VTOI(ap->a_vp);

	if (ip)
		hkprintf("obj_id %016jx, asof %016jx\n",
			 (intmax_t)ip->obj_id, (intmax_t)ip->obj_asof);
	return(0);
}

static int
hammer_vop_pathconf(struct vop_pathconf_args *ap)
{
	switch (ap->a_name) {
	case _PC_LINK_MAX:
		*ap->a_retval = LINK_MAX;
		return(0);
	case _PC_NAME_MAX:
		*ap->a_retval = NAME_MAX;
		return(0);
	case _PC_PATH_MAX:
		*ap->a_retval = PATH_MAX;
		return(0);
	case _PC_PIPE_BUF:
		*ap->a_retval = PIPE_BUF;
		return(0);
	case _PC_CHOWN_RESTRICTED:
	case _PC_NO_TRUNC:
		*ap->a_retval = 1;
		return(0);
	default:
		return(EINVAL);
	}
}

/*
 * HAMMER ioctls on any file of the mount (hammer_ioctl.c says which).
 */
static int
hammer_vop_ioctl(struct vop_ioctl_args *ap)
{
	return(hammer_ioctl(VTOI(ap->a_vp), ap->a_command, ap->a_data,
			    ap->a_fflag, ap->a_cred));
}

/*
 * Make a new object named by CNP in directory DVP: a file, a directory,
 * or (TARGET non-NULL) a symlink.  Upstream's hammer_vop_ncreate,
 * nmkdir and nsymlink.  Returns the new vnode locked in *vpp.
 */
static int
hammer_newobj(struct vnode *dvp, struct vnode **vpp,
	      struct componentname *cnp, struct vattr *vap, char *target)
{
	struct hammer_transaction trans;
	hammer_inode_t dip = VTOI(dvp);
	hammer_inode_t nip;
	hammer_mount_t hmp = dip->hmp;
	hammer_record_t record;
	int error, bytes;

	*vpp = NULL;
	if (hmp->ronly || (dip->flags & HAMMER_INODE_RO))
		return(EROFS);
	if ((error = hammer_checkspace(hmp, HAMMER_CHKSPC_CREATE)) != 0)
		return(error);

	hammer_start_transaction(&trans, hmp);
	error = hammer_create_inode(&trans, vap, cnp->cn_cred, dip,
				    cnp->cn_nameptr, cnp->cn_namelen,
				    NULL, &nip);
	if (error) {
		hammer_done_transaction(&trans);
		return(error);
	}

	/*
	 * A symlink stores its target as pure data, not a string: in the
	 * inode when it fits, else in a record of its own.
	 */
	if (target) {
		bytes = strlen(target);
		if (bytes <= HAMMER_INODE_BASESYMLEN) {
			bcopy(target, nip->ino_data.ext.symlink, bytes);
		} else {
			record = hammer_alloc_mem_record(nip, bytes);
			record->type = HAMMER_MEM_RECORD_GENERAL;
			record->leaf.base.localization =
				hmk32(nip->obj_localization |
				      HAMMER_LOCALIZE_MISC);
			record->leaf.base.key = hmk64(HAMMER_FIXKEY_SYMLINK);
			record->leaf.base.rec_type = hmk16(HAMMER_RECTYPE_FIX);
			record->leaf.data_len = hmk32(bytes);
			KKASSERT(HAMMER_SYMLINK_NAME_OFF == 0);
			bcopy(target, record->data->symlink.name, bytes);
			error = hammer_ip_add_record(&trans, record);
		}
		if (error == 0) {
			nip->ino_data.size = hmk64(bytes);
			hammer_modify_inode(&trans, nip, HAMMER_INODE_DDIRTY);
		}
	}

	/*
	 * Add the new object to the directory, which also bumps its link
	 * count.
	 */
	if (error == 0)
		error = hammer_ip_add_direntry(&trans, dip, cnp->cn_nameptr,
					       cnp->cn_namelen, nip);
	if (error == 0)
		error = hammer_get_vnode(nip, vpp);
	hammer_rel_inode(nip, 0);
	hammer_done_transaction(&trans);
	return(error);
}

static int
hammer_vop_create(struct vop_create_args *ap)
{
	int error;

	error = hammer_newobj(ap->a_dvp, ap->a_vpp, ap->a_cnp, ap->a_vap, NULL);
	(void)nop_create(ap);
	return(error);
}

/*
 * shortcut: device and FIFO nodes cannot be opened yet (they would need
 * the spec and fifo op tables); refuse to make them.
 */
static int
hammer_vop_mknod(struct vop_mknod_args *ap)
{
	(void)nop_mknod(ap);
	return(EOPNOTSUPP);
}

static int
hammer_vop_mkdir(struct vop_mkdir_args *ap)
{
	int error;

	error = hammer_newobj(ap->a_dvp, ap->a_vpp, ap->a_cnp, ap->a_vap, NULL);
	(void)nop_mkdir(ap);
	return(error);
}

/*
 * The symlink's vnode is not returned (ufs_symlink drops it too).
 */
static int
hammer_vop_symlink(struct vop_symlink_args *ap)
{
	int error;

	ap->a_vap->va_type = VLNK;
	error = hammer_newobj(ap->a_dvp, ap->a_vpp, ap->a_cnp, ap->a_vap,
			      ap->a_target);
	if (error == 0)
		vput(*ap->a_vpp);
	(void)nop_symlink(ap);
	return(error);
}

/*
 * Remove NAME from directory DIP (upstream's hammer_dounlink).  ISDIR
 * says what the entry must be: 1 a directory (which must be empty), 0
 * anything else, -1 either.  The inode's link count drops; the inode
 * itself goes when nothing uses it any more.
 */
static int
hammer_dounlink(hammer_transaction_t trans, hammer_inode_t dip,
		const char *name, int nlen, int isdir)
{
	struct hammer_cursor cursor;
	hammer_mount_t hmp = dip->hmp;
	hammer_inode_t ip;
	int error;

	if (dip->flags & HAMMER_INODE_RO)
		return(EROFS);
retry:
	ip = NULL;
	error = hammer_init_cursor(trans, &cursor, &dip->cache[1], dip);
	if (error == 0)
		error = hammer_find_entry(&cursor, dip, name, nlen);

	/*
	 * Get the entry's inode to adjust its link count.  To avoid a
	 * deadlock with the flusher the directory's inode lock is dropped
	 * while acquiring it.
	 */
	if (error == 0) {
		hammer_unlock(&cursor.ip->lock);
		ip = hammer_get_inode(trans, dip,
				      hget64(cursor.data->entry.obj_id),
				      hmp->asof,
				      hget32(cursor.data->entry.localization),
				      0, &error);
		hammer_lock_sh(&cursor.ip->lock);
		if (error == ENOENT) {
			hkprintf("removing entry \"%.*s\" with no inode "
				 "%016jx\n", nlen, name,
				 (intmax_t)hget64(cursor.data->entry.obj_id));
			error = 0;
		}
	}
	if (error == 0 && isdir >= 0 && ip) {
		if (isdir &&
		    ip->ino_data.obj_type != HAMMER_OBJTYPE_DIRECTORY)
			error = ENOTDIR;
		else if (isdir == 0 &&
		    ip->ino_data.obj_type == HAMMER_OBJTYPE_DIRECTORY)
			error = EISDIR;
	}
	if (error == 0 &&
	    ((hget32(dip->ino_data.uflags) & APPEND) ||
	     (ip && (hget32(ip->ino_data.uflags) & (IMMUTABLE | APPEND)))))
		error = EPERM;		/* ufs_remove, ufs_rmdir */

	/*
	 * A directory must be empty.  The check can block, so our own
	 * cursor's node locks are released around it; any change to the
	 * cursor meanwhile means a retry.
	 */
	if (error == 0 && ip &&
	    ip->ino_data.obj_type == HAMMER_OBJTYPE_DIRECTORY) {
		hammer_unlock_cursor(&cursor);
		error = hammer_ip_check_directory_empty(trans, ip);
		hammer_lock_cursor(&cursor);
		if (error == 0 && (cursor.flags & HAMMER_CURSOR_RETEST))
			error = EDEADLK;
	}

	/*
	 * hammer_ip_del_direntry() may terminate the cursor; terminating
	 * it twice is fine.
	 */
	if (error == 0)
		error = hammer_ip_del_direntry(trans, &cursor, dip, ip);
	hammer_done_cursor(&cursor);
	if (ip)
		hammer_rel_inode(ip, 0);
	if (error == EDEADLK)
		goto retry;
	return(error);
}

static int
hammer_unlink_cnp(struct vnode *dvp, struct componentname *cnp, int isdir)
{
	struct hammer_transaction trans;
	hammer_inode_t dip = VTOI(dvp);
	hammer_mount_t hmp = dip->hmp;
	int error;

	if (hmp->ronly)
		return(EROFS);
	if (hammer_nohistory(dip) == 0 &&
	    (error = hammer_checkspace(hmp, HAMMER_CHKSPC_REMOVE)) != 0)
		return(error);
	hammer_start_transaction(&trans, hmp);
	error = hammer_dounlink(&trans, dip, cnp->cn_nameptr, cnp->cn_namelen,
				isdir);
	hammer_done_transaction(&trans);
	return(error);
}

static int
hammer_vop_remove(struct vop_remove_args *ap)
{
	int error;

	error = hammer_unlink_cnp(ap->a_dvp, ap->a_cnp, 0);
	if (error == 0)
		cache_purge(ap->a_vp);
	(void)nop_remove(ap);
	return(error);
}

static int
hammer_vop_rmdir(struct vop_rmdir_args *ap)
{
	int error;

	error = hammer_unlink_cnp(ap->a_dvp, ap->a_cnp, 1);
	if (error == 0) {
		cache_purge(ap->a_dvp);
		cache_purge(ap->a_vp);
	}
	(void)nop_rmdir(ap);
	return(error);
}

/*
 * VP is referenced but not locked; TDVP is locked.
 */
static int
hammer_vop_link(struct vop_link_args *ap)
{
	struct hammer_transaction trans;
	hammer_inode_t dip = VTOI(ap->a_tdvp);
	hammer_inode_t ip = VTOI(ap->a_vp);
	hammer_mount_t hmp = dip->hmp;
	int error;

	if (ap->a_tdvp->v_mount != ap->a_vp->v_mount ||
	    dip->obj_localization != ip->obj_localization)
		error = EXDEV;
	else if (hmp->ronly || ((dip->flags | ip->flags) & HAMMER_INODE_RO))
		error = EROFS;
	else if (ap->a_vp->v_type == VDIR ||
	    (hget32(ip->ino_data.uflags) & (IMMUTABLE | APPEND)))
		error = EPERM;
	else if (hget64(ip->ino_data.nlinks) >= LINK_MAX)
		error = EMLINK;
	else
		error = hammer_checkspace(hmp, HAMMER_CHKSPC_CREATE);
	if (error == 0) {
		hammer_start_transaction(&trans, hmp);
		error = hammer_ip_add_direntry(&trans, dip,
					       ap->a_cnp->cn_nameptr,
					       ap->a_cnp->cn_namelen, ip);
		hammer_done_transaction(&trans);
	}
	(void)nop_link(ap);
	return(error);
}

/*
 * Moving directory IP under TDIP must not make IP its own ancestor:
 * walk TDIP's parents up to the root (ufs_checkpath).
 */
static int
hammer_checkpath(hammer_inode_t ip, hammer_inode_t tdip)
{
	struct hammer_transaction trans;
	hammer_inode_t pip;
	int64_t obj_id = tdip->obj_id, child;
	int error = 0;

	hammer_simple_transaction(&trans, ip->hmp);
	while (obj_id != HAMMER_OBJID_ROOT) {
		if (obj_id == ip->obj_id) {
			error = EINVAL;
			break;
		}
		pip = hammer_get_inode(&trans, NULL, obj_id, ip->hmp->asof,
				       ip->obj_localization, 0, &error);
		if (pip == NULL)
			break;
		child = obj_id;
		obj_id = (int64_t)hget64(pip->ino_data.parent_obj_id);
		hammer_rel_inode(pip, 0);
		if (obj_id == 0 || obj_id == child) {
			hkprintf("directory %016jx: bad parent %016jx\n",
				 (intmax_t)child, (intmax_t)obj_id);
			error = EIO;
			break;
		}
	}
	hammer_done_transaction(&trans);
	return(error);
}

/*
 * Rename (upstream's hammer_vop_nrename): drop any existing target
 * entry, enter the object under the new name, then remove the old name.
 * rename(2) has already refused mismatched types, a source that is the
 * target directory, and turned a rename onto the same object into a
 * no-op.  TDVP and TVP are locked; FDVP and FVP only referenced.
 */
static int
hammer_vop_rename(struct vop_rename_args *ap)
{
	struct vnode *fvp = ap->a_fvp, *tvp = ap->a_tvp;
	struct componentname *fcnp = ap->a_fcnp, *tcnp = ap->a_tcnp;
	struct hammer_transaction trans;
	struct hammer_cursor cursor;
	hammer_inode_t fdip, tdip, ip;
	hammer_mount_t hmp;
	int64_t obj_id;
	uint32_t localization;
	int error;

	if (fvp->v_mount != ap->a_tdvp->v_mount ||
	    (tvp && fvp->v_mount != tvp->v_mount)) {
		error = EXDEV;
		goto done;
	}
	fdip = VTOI(ap->a_fdvp);
	tdip = VTOI(ap->a_tdvp);
	ip = VTOI(fvp);
	hmp = ip->hmp;
	error = 0;
	if (fvp == tvp)
		goto done;
	if (fdip->obj_localization != tdip->obj_localization ||
	    fdip->obj_localization != ip->obj_localization) {
		error = EXDEV;
		goto done;
	}
	if (hmp->ronly ||
	    ((fdip->flags | tdip->flags | ip->flags) & HAMMER_INODE_RO)) {
		error = EROFS;
		goto done;
	}
	if ((hget32(ip->ino_data.uflags) & (IMMUTABLE | APPEND)) ||
	    (hget32(fdip->ino_data.uflags) & APPEND)) {
		error = EPERM;		/* ufs_rename */
		goto done;
	}
	if (fvp->v_type == VDIR) {
		if ((fcnp->cn_namelen == 1 && fcnp->cn_nameptr[0] == '.') ||
		    fdip == ip || ((fcnp->cn_flags | tcnp->cn_flags) & ISDOTDOT)) {
			error = EINVAL;
			goto done;
		}
		if (fdip != tdip && (error = hammer_checkpath(ip, tdip)) != 0)
			goto done;
	}
	if ((error = hammer_checkspace(hmp, HAMMER_CHKSPC_CREATE)) != 0)
		goto done;


	/*
	 * FDVP and FVP have been unlocked since the source was looked up, so
	 * the name may now be another object's (ufs_rename looks it up
	 * again).
	 */
	error = hammer_lookup_name(fdip, fcnp->cn_nameptr, fcnp->cn_namelen,
				   &obj_id, &localization);
	if (error == 0 && obj_id != ip->obj_id)
		error = ENOENT;
	if (error)
		goto done;

	hammer_start_transaction(&trans, hmp);
	if (tvp)
		error = hammer_dounlink(&trans, tdip, tcnp->cn_nameptr,
					tcnp->cn_namelen, -1);
	if (error == 0) {
		error = hammer_ip_add_direntry(&trans, tdip, tcnp->cn_nameptr,
					       tcnp->cn_namelen, ip);
		if (error == 0) {
			ip->ino_data.parent_obj_id = hmk64(tdip->obj_id);
			ip->ino_data.ctime = hmk64(trans.time);
			hammer_modify_inode(&trans, ip, HAMMER_INODE_DDIRTY);
		}
	}

	/*
	 * Remove the old name.  A deadlock here retries.  If the name went
	 * away, or now names another object, while we slept, the object
	 * already has only its new name.
	 */
	while (error == 0) {
		error = hammer_init_cursor(&trans, &cursor, &fdip->cache[1],
					   fdip);
		if (error == 0)
			error = hammer_find_entry(&cursor, fdip,
						  fcnp->cn_nameptr,
						  fcnp->cn_namelen);
		if (error == 0 &&
		    (int64_t)hget64(cursor.data->entry.obj_id) != ip->obj_id)
			error = ENOENT;
		if (error == 0)
			error = hammer_ip_del_direntry(&trans, &cursor, fdip,
						       ip);
		hammer_done_cursor(&cursor);
		if (error == ENOENT)
			error = 0;
		if (error != EDEADLK)
			break;
		error = 0;
	}
	hammer_done_transaction(&trans);
	if (error == 0) {
		cache_purge(fvp);
		if (tvp)
			cache_purge(tvp);
	}
done:
	(void)nop_rename(ap);
	return(error);
}


/*
 * File data goes through the buffer cache in 8 KB logical blocks
 * (MAXBSIZE); strategy fills each block from the data records covering it.
 */
#define HAMMER_LBLKSIZE	8192

/*
 * How many of the N bytes at file offset AT lie below truncation point
 * TRUNC.
 */
static int
hammer_clip(int64_t at, int n, int64_t trunc)
{
	if (trunc <= at)
		return(0);
	if (trunc < at + n)
		return((int)(trunc - at));
	return(n);
}

/*
 * Copy file bytes [offset, offset + len) into dst: the ported "hard way"
 * of upstream hammer_vop_strategy_read().  A data record's key is its end
 * offset, so the first record touching offset has key > offset.  Holes and
 * the tail past the last record read as zeros.  A data CRC failure makes
 * hammer_ip_resolve_data() log it and return EIO.
 */
static int
hammer_read_range(hammer_inode_t ip, int64_t offset, char *dst, int len)
{
	struct hammer_transaction trans;
	struct hammer_cursor cursor;
	int64_t rec_offset, ran_end;
	int error, boff = 0, roff, n, dlen;

	hammer_simple_transaction(&trans, ip->hmp);
	error = hammer_init_cursor(&trans, &cursor, &ip->cache[1], ip);
	cursor.key_beg.localization = hmk32(ip->obj_localization |
					    HAMMER_LOCALIZE_MISC);
	cursor.key_beg.obj_id = hmk64(ip->obj_id);
	cursor.key_beg.create_tid = hmk64(0);
	cursor.key_beg.delete_tid = hmk64(0);
	cursor.key_beg.obj_type = 0;
	cursor.key_beg.key = hmk64(offset + 1);
	cursor.key_beg.rec_type = hmk16(HAMMER_RECTYPE_DATA);
	cursor.asof = ip->obj_asof;
	cursor.flags |= HAMMER_CURSOR_ASOF | HAMMER_CURSOR_END_INCLUSIVE;
	cursor.key_end = cursor.key_beg;
	ran_end = offset + len;
	cursor.key_end.key = hmk64(ran_end + MAXPHYS + 1);

	if (error == 0)
		error = hammer_ip_first(&cursor);
	while (error == 0) {
		dlen = (int)hget32(cursor.leaf->data_len);
		rec_offset = (int64_t)hget64(cursor.leaf->base.key) - dlen;
		n = (int)(rec_offset - (offset + boff));
		if (n > 0) {
			if (n > len - boff)
				n = len - boff;
			bzero(dst + boff, n);
			boff += n;
			n = 0;
		}
		roff = -n;
		n = dlen - roff;
		if (n <= 0)
			n = 0;
		else if (n > len - boff)
			n = len - boff;

		/*
		 * On-media records past a truncation the backend has not
		 * finished are already gone (upstream's strategy read clip);
		 * in-memory records were written after it.
		 */
		if (n && hammer_cursor_ondisk(&cursor)) {
			if (ip->flags & HAMMER_INODE_TRUNCATED)
				n = hammer_clip(rec_offset + roff, n, ip->trunc_off);
			if (ip->sync_flags & HAMMER_INODE_TRUNCATED)
				n = hammer_clip(rec_offset + roff, n,
						ip->sync_trunc_off);
		}
		if (n) {
			error = hammer_ip_resolve_data(&cursor);
			if (error)
				break;
			bcopy((char *)cursor.data + roff, dst + boff, n);
		}
		boff += n;
		if (boff == len)
			break;
		error = hammer_ip_next(&cursor);
	}
	if (error == ENOENT)
		error = 0;
	if (error == 0 && boff < len)
		bzero(dst + boff, len - boff);
	hammer_done_cursor(&cursor);
	hammer_done_transaction(&trans);
	if (error)
		hkprintf("file %016jx: read at %016jx failed, error %d\n",
			 (intmax_t)ip->obj_id, (intmax_t)offset, error);
	return(error);
}

static int
hammer_vop_read(struct vop_read_args *ap)
{
	struct vnode *vp = ap->a_vp;
	hammer_inode_t ip = VTOI(vp);
	struct uio *uio = ap->a_uio;
	int64_t size = (int64_t)hget64(ip->ino_data.size);
	struct buf *bp;
	daddr_t lbn;
	int64_t left;
	int error = 0, boff, n;

	if (vp->v_type != VREG)
		return(vp->v_type == VDIR ? EISDIR : EINVAL);
	/* lseek accepts negative offsets; ffs_read refuses them too. */
	if (uio->uio_offset < 0)
		return(EINVAL);
	while (uio->uio_resid > 0 && uio->uio_offset < size) {
		lbn = (daddr_t)(uio->uio_offset / HAMMER_LBLKSIZE);
		boff = (int)(uio->uio_offset % HAMMER_LBLKSIZE);
		n = HAMMER_LBLKSIZE - boff;
		if (n > uio->uio_resid)
			n = uio->uio_resid;
		left = size - uio->uio_offset;
		if (n > left)
			n = (int)left;
		error = bread(vp, lbn, HAMMER_LBLKSIZE, NOCRED, &bp);
		if (error) {
			brelse(bp);
			break;
		}
		error = uiomove((char *)bp->b_data + boff, n, uio);
		brelse(bp);
		if (error)
			break;
	}
	return(error);
}

/*
 * Writes never dirty these buffers (hammer_vop_write stores whole HAMMER
 * blocks itself), so a write here is a bug, not data to keep.
 */
static int
hammer_vop_strategy(struct vop_strategy_args *ap)
{
	struct buf *bp = ap->a_bp;
	hammer_inode_t ip = VTOI(bp->b_vp);
	int error;

	if ((bp->b_flags & B_READ) == 0) {
		hkprintf("file %016jx: unexpected buffer write at block %d\n",
			 (intmax_t)ip->obj_id, (int)bp->b_lblkno);
		error = EIO;
	} else {
		error = hammer_read_range(ip,
				(int64_t)bp->b_lblkno * HAMMER_LBLKSIZE,
				bp->b_data, bp->b_bcount);
	}
	if (error) {
		bp->b_error = error;
		bp->b_flags |= B_ERROR;
	}
	bp->b_resid = 0;
	biodone(bp);
	return(error);
}

/*
 * Bring the file's cached 8 KB blocks inside the HAMMER block at BASE
 * (BSIZE bytes, now BLK) up to date; blocks not cached are left alone.
 */
static void
hammer_update_bufs(struct vnode *vp, int64_t base, int bsize, char *blk)
{
	struct buf *bp;
	daddr_t lbn;
	int off;

	for (off = 0; off < bsize; off += HAMMER_LBLKSIZE) {
		lbn = (daddr_t)((base + off) / HAMMER_LBLKSIZE);
		if (incore(vp, lbn) == NULL)
			continue;
		bp = getblk(vp, lbn, HAMMER_LBLKSIZE, 0, 0);
		if ((bp->b_flags & B_DONE) && bp->b_bcount == HAMMER_LBLKSIZE)
			bcopy(blk + off, bp->b_data, HAMMER_LBLKSIZE);
		else
			bp->b_flags |= B_INVAL;
		brelse(bp);
	}
}

/*
 * Drop the file's cached blocks from logical block LBN on, so bytes past
 * a new EOF cannot come back if the file grows again.  The file never
 * has dirty blocks (hammer_vop_strategy), only clean ones.
 */
static void
hammer_drop_bufs(struct vnode *vp, daddr_t lbn)
{
	struct buf *bp;
	int s;

	s = splbio();
restart:
	for (bp = vp->v_cleanblkhd.lh_first; bp; bp = bp->b_vnbufs.le_next) {
		if (bp->b_lblkno < lbn)
			continue;
		if (bp->b_flags & B_BUSY) {
			bp->b_flags |= B_WANTED;
			tsleep((caddr_t)bp, 0, "hmrdrop", 0);
		} else {
			bremfree(bp);
			bp->b_flags |= B_BUSY | B_INVAL;
			brelse(bp);
		}
		goto restart;
	}
	splx(s);
}

/*
 * Store the HAMMER block at BASE, BSIZE bytes of BLK, as one bulk record
 * replacing any older record of the block.  A file that is one block no
 * bigger than HAMMER_HBUFSIZE gets a record cut to its SIZE, as
 * upstream's strategy write does.
 */
static int
hammer_write_block(hammer_inode_t ip, int64_t base, int bsize, int64_t size,
		   char *blk)
{
	hammer_record_t record;
	int bytes, error;

	if (base == 0 && size <= HAMMER_HBUFSIZE)
		bytes = HAMMER_DATA_DOALIGN_WITH(int, size);
	else
		bytes = bsize;
	if (bytes == 0)
		return(0);
	record = hammer_ip_add_bulk(ip, base, blk, bytes, &error);
	if (record == NULL)
		return(error);
	return(hammer_io_direct_write(ip->hmp, record, blk));
}

/*
 * Write file data a HAMMER block at a time (16 KB below 1 MB, 64 KB
 * above): each block touched is assembled from its old contents and the
 * new bytes and stored as one bulk record, as upstream's strategy write
 * stores a whole buffer.  Upstream's overwrite and truncation code
 * relies on data records being whole blocks, which 8 KB vnode buffers
 * (MAXBSIZE) cannot give, so those only cache reads and are kept up to
 * date here.
 * shortcut: a write of part of a block rewrites the whole block; keep a
 * pending block per inode if small writes are too slow.
 */
static int
hammer_vop_write(struct vop_write_args *ap)
{
	struct vnode *vp = ap->a_vp;
	struct uio *uio = ap->a_uio;
	struct proc *p = uio->uio_procp;
	hammer_inode_t ip = VTOI(vp);
	hammer_mount_t hmp = ip->hmp;
	struct hammer_transaction trans;
	int64_t size, base, end;
	int resid = uio->uio_resid;
	int bsize, boff, n, flags, error = 0;
	mode_t mode;
	char *blk;

	if (vp->v_type != VREG)
		return(EINVAL);
	if (hmp->ronly || (ip->flags & HAMMER_INODE_RO))
		return(EROFS);
	if (ap->a_ioflag & IO_APPEND)
		uio->uio_offset = (int64_t)hget64(ip->ino_data.size);
	if (uio->uio_offset < 0 ||
	    uio->uio_offset + uio->uio_resid < uio->uio_offset)
		return(EFBIG);
	if (uio->uio_resid == 0)
		return(0);
	if (p && uio->uio_offset + uio->uio_resid >
	    p->p_rlimit[RLIMIT_FSIZE].rlim_cur) {
		psignal(p, SIGXFSZ);
		return(EFBIG);
	}

	blk = kmalloc(HAMMER_XBUFSIZE, M_HAMMER, M_WAITOK);
	hammer_start_transaction(&trans, hmp);
	while (uio->uio_resid > 0) {
		if ((error = hammer_checkspace(hmp, HAMMER_CHKSPC_WRITE)) != 0)
			break;

		/*
		 * Keep a pipeline with the flusher (upstream's rsv_recs
		 * check), and keep the dirty buffers, which live in kernel
		 * memory until flushed, under hammer_limit_dirtybufspace.
		 */
		if (ip->rsv_recs >= hammer_limit_inode_recs ||
		    hammer_flusher_meta_limit(hmp)) {
			hammer_flush_inode(ip, HAMMER_FLUSH_SIGNAL);
			hammer_flusher_sync(hmp);
		}

		size = (int64_t)hget64(ip->ino_data.size);
		bsize = hammer_blocksize(uio->uio_offset);
		base = uio->uio_offset & ~(int64_t)(bsize - 1);
		boff = (int)(uio->uio_offset - base);
		n = bsize - boff;
		if (n > uio->uio_resid)
			n = uio->uio_resid;

		/*
		 * The block's old contents, zeros past EOF.
		 */
		if ((boff != 0 || n != bsize) && base < size) {
			error = hammer_read_range(ip, base, blk, bsize);
			if (error)
				break;
			if (size < base + bsize)
				bzero(blk + (int)(size - base),
				      (int)(base + bsize - size));
		} else {
			bzero(blk, bsize);
		}
		if ((error = uiomove(blk + boff, n, uio)) != 0)
			break;
		end = base + boff + n;
		if (end < size)
			end = size;
		if ((error = hammer_write_block(ip, base, bsize, end, blk)) != 0)
			break;

		flags = HAMMER_INODE_MTIME;
		if (end > size) {
			ip->ino_data.size = hmk64(end);
			flags |= HAMMER_INODE_SDIRTY;
			if (vp->v_vm_info && !vp->v_vm_info->mapped)
				vnode_pager_setsize(vp, (u_long)end);
		}
		ip->ino_data.mtime = hmk64(trans.time);
		hammer_modify_inode(&trans, ip, flags);
		hammer_update_bufs(vp, base, bsize, blk);
		hammer_stats_file_write += n;
	}

	/*
	 * A write by someone other than root clears setuid and setgid, as
	 * ffs_write does.
	 */
	mode = hget16(ip->ino_data.mode);
	if (resid > uio->uio_resid && ap->a_cred && ap->a_cred->cr_uid != 0 &&
	    (mode & (S_ISUID | S_ISGID))) {
		ip->ino_data.mode = hmk16(mode & ~(S_ISUID | S_ISGID));
		hammer_modify_inode(&trans, ip, HAMMER_INODE_DDIRTY);
	}
	hammer_done_transaction(&trans);
	kfree(blk, M_HAMMER);
	if (error == 0 && (ap->a_ioflag & IO_SYNC))
		error = hammer_fsync_ip(ip, MNT_WAIT);
	return(error);
}

/*
 * Change the size of regular file IP to SIZE (upstream's setattr size
 * case).  Shrinking drops frontend records past SIZE, leaves the backend
 * a truncation point to delete whole on-media blocks from, and rewrites
 * the HAMMER block holding the new EOF with zeros past it (DragonFly does
 * that through nvtruncbuf).  Growing only changes the size: the new
 * range is a hole and reads as zeros.
 */
static int
hammer_setsize(hammer_inode_t ip, struct vnode *vp, int64_t size)
{
	int64_t osize = (int64_t)hget64(ip->ino_data.size);
	int64_t base;
	int bsize, error = 0;
	char *blk;

#if MACH_NBC
	if ((error = mapfs_trunc(vp, (vm_offset_t)size)) != 0)
		return(error);
#endif
	if (size < osize) {
		hammer_ip_frontend_trunc(ip, size);
		if ((ip->flags & HAMMER_INODE_TRUNCATED) == 0) {
			ip->flags |= HAMMER_INODE_TRUNCATED;
			ip->trunc_off = size;
		} else if (ip->trunc_off > size) {
			ip->trunc_off = size;
		}
		bsize = hammer_blocksize(size);
		base = size & ~(int64_t)(bsize - 1);
		if (size > base) {
			blk = kmalloc(bsize, M_HAMMER, M_WAITOK);
			error = hammer_read_range(ip, base, blk, bsize);
			if (error == 0) {
				bzero(blk + (int)(size - base),
				      bsize - (int)(size - base));
				error = hammer_write_block(ip, base, bsize, size,
							   blk);
			}
			if (error == 0)
				hammer_update_bufs(vp, base, bsize, blk);
			kfree(blk, M_HAMMER);
			base += bsize;
		}
		hammer_drop_bufs(vp, (daddr_t)(base / HAMMER_LBLKSIZE));
	}
	if (error == 0) {
		ip->ino_data.size = hmk64(size);
		if (vp->v_vm_info && !vp->v_vm_info->mapped)
			vnode_pager_setsize(vp, (u_long)size);
	}
	return(error);
}

/*
 * Attribute changes, with ufs_setattr's rules (ufs_chmod, ufs_chown) and
 * upstream's HAMMER updates.  Changes made before a refusal are kept and
 * flushed, as ufs_setattr keeps them.
 */
static int
hammer_vop_setattr(struct vop_setattr_args *ap)
{
	struct vnode *vp = ap->a_vp;
	struct vattr *vap = ap->a_vap;
	struct ucred *cred = ap->a_cred;
	struct proc *p = ap->a_p;
	struct hammer_transaction trans;
	hammer_inode_t ip = VTOI(vp);
	hammer_mount_t hmp = ip->hmp;
	uint32_t uflags = hget32(ip->ino_data.uflags);
	mode_t mode = hget16(ip->ino_data.mode);
	uid_t uid = hammer_to_unix_xid(&ip->ino_data.uid), nuid;
	gid_t gid = hammer_to_unix_xid(&ip->ino_data.gid), ngid;
	int modflags = 0, error = 0;

	if (vap->va_type != VNON || vap->va_nlink != VNOVAL ||
	    vap->va_fsid != VNOVAL || vap->va_fileid != VNOVAL ||
	    vap->va_blocksize != VNOVAL || vap->va_rdev != VNOVAL ||
	    (int)vap->va_bytes != VNOVAL || vap->va_gen != VNOVAL)
		return(EINVAL);
	if ((vp->v_mount->mnt_flag & MNT_RDONLY) || hmp->ronly ||
	    (ip->flags & HAMMER_INODE_RO))
		return(EROFS);
	if (hammer_nohistory(ip) == 0 &&
	    (error = hammer_checkspace(hmp, HAMMER_CHKSPC_REMOVE)) != 0)
		return(error);

	hammer_start_transaction(&trans, hmp);
	if (vap->va_flags != VNOVAL) {
		if (cred->cr_uid != uid &&
		    (error = suser(cred, &p->p_acflag)) != 0)
			goto done;
		if (cred->cr_uid == 0) {
			if ((uflags & (SF_IMMUTABLE | SF_APPEND)) &&
			    securelevel > 0) {
				error = EPERM;
				goto done;
			}
			uflags = vap->va_flags;
		} else {
			if ((uflags & (SF_IMMUTABLE | SF_APPEND)) ||
			    (vap->va_flags & UF_SETTABLE) != vap->va_flags) {
				error = EPERM;
				goto done;
			}
			uflags = (uflags & SF_SETTABLE) |
				 (vap->va_flags & UF_SETTABLE);
		}
		ip->ino_data.uflags = hmk32(uflags);
		ip->ino_data.ctime = hmk64(trans.time);
		modflags |= HAMMER_INODE_DDIRTY;
		if (vap->va_flags & (IMMUTABLE | APPEND))
			goto done;
	}
	if (uflags & (IMMUTABLE | APPEND)) {
		error = EPERM;
		goto done;
	}
	if (vap->va_uid != (uid_t)VNOVAL || vap->va_gid != (gid_t)VNOVAL) {
		nuid = vap->va_uid == (uid_t)VNOVAL ? uid : vap->va_uid;
		ngid = vap->va_gid == (gid_t)VNOVAL ? gid : vap->va_gid;
		if ((cred->cr_uid != uid || nuid != uid ||
		     (ngid != gid && !groupmember(ngid, cred))) &&
		    (error = suser(cred, &p->p_acflag)) != 0)
			goto done;
		if (nuid != uid && cred->cr_uid != 0)
			mode &= ~S_ISUID;
		if (ngid != gid && cred->cr_uid != 0)
			mode &= ~S_ISGID;
		hammer_guid_to_uuid(&ip->ino_data.uid, nuid);
		hammer_guid_to_uuid(&ip->ino_data.gid, ngid);
		ip->ino_data.mode = hmk16(mode);
		ip->ino_data.ctime = hmk64(trans.time);
		modflags |= HAMMER_INODE_DDIRTY;
		uid = nuid;
		gid = ngid;
	}
	if (vap->va_size != VNOVAL) {
		if (vp->v_type == VDIR) {
			error = EISDIR;
			goto done;
		}
		if (vp->v_type != VREG) {
			error = EINVAL;
			goto done;
		}
		if (vap->va_size != hget64(ip->ino_data.size)) {
			error = hammer_setsize(ip, vp, vap->va_size);
			if (error)
				goto done;
			ip->ino_data.mtime = hmk64(trans.time);
			modflags |= HAMMER_INODE_MTIME | HAMMER_INODE_DDIRTY;
		}
	}
	if (vap->va_atime.tv_sec != VNOVAL || vap->va_mtime.tv_sec != VNOVAL) {
		if (cred->cr_uid != uid &&
		    (error = suser(cred, &p->p_acflag)) != 0 &&
		    ((vap->va_vaflags & VA_UTIMES_NULL) == 0 ||
		     (error = VOP_ACCESS(vp, VWRITE, cred, p)) != 0))
			goto done;
		error = 0;
		if (vap->va_atime.tv_sec != VNOVAL) {
			ip->ino_data.atime =
				hmk64(hammer_timespec_to_time(&vap->va_atime));
			modflags |= HAMMER_INODE_ATIME;
		}
		if (vap->va_mtime.tv_sec != VNOVAL) {
			ip->ino_data.mtime =
				hmk64(hammer_timespec_to_time(&vap->va_mtime));
			modflags |= HAMMER_INODE_MTIME;
		}
	}
	if (vap->va_mode != (mode_t)VNOVAL) {
		if (cred->cr_uid != uid &&
		    (error = suser(cred, &p->p_acflag)) != 0)
			goto done;
		if (cred->cr_uid) {
			if (vp->v_type != VDIR && (vap->va_mode & S_ISTXT)) {
				error = EFTYPE;
				goto done;
			}
			if (!groupmember(gid, cred) && (vap->va_mode & S_ISGID)) {
				error = EPERM;
				goto done;
			}
		}
		mode = (mode & ~ALLPERMS) | (vap->va_mode & ALLPERMS);
		ip->ino_data.mode = hmk16(mode);
		ip->ino_data.ctime = hmk64(trans.time);
		modflags |= HAMMER_INODE_DDIRTY;
	}
done:
	if (modflags)
		hammer_modify_inode(&trans, ip, modflags);
	hammer_done_transaction(&trans);
	return(error);
}

/*
 * A full flush of the inode (there is no REDO), waited for with
 * MNT_WAIT, then, if the volume header's UNDO start still lags the last
 * flush, one more flusher cycle: until it catches up a crash would undo
 * that flush.  A clean, idle inode costs nothing, which matters because
 * vnode reclaim calls VOP_FSYNC on every vnode.
 */
static int
hammer_fsync_ip(hammer_inode_t ip, int waitfor)
{
	hammer_mount_t hmp = ip->hmp;

	if ((ip->flags & HAMMER_INODE_MODMASK) ||
	    ip->flush_state != HAMMER_FST_IDLE) {
		++hammer_count_fsyncs;
		hammer_flush_inode(ip, HAMMER_FLUSH_SIGNAL);
		if (waitfor == MNT_WAIT)
			hammer_wait_inode(ip);
	}
	if (waitfor == MNT_WAIT && (hmp->hflags & HMNT_UNDO_DIRTY))
		hammer_flusher_sync(hmp);
	return(ip->error);
}

static int
hammer_vop_fsync(struct vop_fsync_args *ap)
{
	hammer_inode_t ip = VTOI(ap->a_vp);

	if (ip == NULL || ip->hmp->ronly)
		return(0);
	return(hammer_fsync_ip(ip, ap->a_waitfor));
}

/* Logical blocks are not device blocks: identity mapping, no clustering. */
static int
hammer_vop_bmap(struct vop_bmap_args *ap)
{
	if (ap->a_vpp)
		*ap->a_vpp = ap->a_vp;
	if (ap->a_bnp)
		*ap->a_bnp = ap->a_bn;
	if (ap->a_runp)
		*ap->a_runp = 0;
	return(0);
}

/*
 * Generic 4.4BSD ops that never look at the inode; ufs_pageout writes
 * through VOP_WRITE.
 */
extern int ufs_seek(), ufs_select(), ufs_mmap(), ufs_pagein(), ufs_pageout();

struct vnodeopv_entry_desc hammer_vnodeop_entries[] = {
	{ &vop_default_desc, (int (*)())vn_default_error },
	{ &vop_lookup_desc, (int (*)())hammer_vop_lookup },
	{ &vop_create_desc, (int (*)())hammer_vop_create },
	{ &vop_mknod_desc, (int (*)())hammer_vop_mknod },
	{ &vop_open_desc, (int (*)())hammer_vop_open },
	{ &vop_close_desc, (int (*)())hammer_vop_close },
	{ &vop_access_desc, (int (*)())hammer_vop_access },
	{ &vop_getattr_desc, (int (*)())hammer_vop_getattr },
	{ &vop_setattr_desc, (int (*)())hammer_vop_setattr },
	{ &vop_read_desc, (int (*)())hammer_vop_read },
	{ &vop_write_desc, (int (*)())hammer_vop_write },
	{ &vop_strategy_desc, (int (*)())hammer_vop_strategy },
	{ &vop_bmap_desc, (int (*)())hammer_vop_bmap },
	{ &vop_fsync_desc, (int (*)())hammer_vop_fsync },
	{ &vop_seek_desc, (int (*)())ufs_seek },
	{ &vop_select_desc, (int (*)())ufs_select },
	{ &vop_mmap_desc, (int (*)())ufs_mmap },
	{ &vop_pagein_desc, (int (*)())ufs_pagein },
	{ &vop_pageout_desc, (int (*)())ufs_pageout },
	{ &vop_lease_desc, (int (*)())nop_lease },
	{ &vop_remove_desc, (int (*)())hammer_vop_remove },
	{ &vop_link_desc, (int (*)())hammer_vop_link },
	{ &vop_rename_desc, (int (*)())hammer_vop_rename },
	{ &vop_mkdir_desc, (int (*)())hammer_vop_mkdir },
	{ &vop_rmdir_desc, (int (*)())hammer_vop_rmdir },
	{ &vop_symlink_desc, (int (*)())hammer_vop_symlink },
	{ &vop_readdir_desc, (int (*)())hammer_vop_readdir },
	{ &vop_readlink_desc, (int (*)())hammer_vop_readlink },
	{ &vop_abortop_desc, (int (*)())nop_abortop },
	{ &vop_inactive_desc, (int (*)())hammer_vop_inactive },
	{ &vop_reclaim_desc, (int (*)())hammer_vop_reclaim },
	{ &vop_lock_desc, (int (*)())hammer_vop_lock },
	{ &vop_unlock_desc, (int (*)())hammer_vop_unlock },
	{ &vop_islocked_desc, (int (*)())hammer_vop_islocked },
	{ &vop_print_desc, (int (*)())hammer_vop_print },
	{ &vop_pathconf_desc, (int (*)())hammer_vop_pathconf },
	{ &vop_ioctl_desc, (int (*)())hammer_vop_ioctl },
	{ NULL, NULL }
};
struct vnodeopv_desc hammer_vnodeop_opv_desc =
	{ &hammer_vnodeop_p, hammer_vnodeop_entries };
