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

/*
 * HAMMER VFS operations for Rhapsody's 4.4BSD VFS.
 *
 * The mount, unmount, statfs and sync entry points are rewritten for
 * Rhapsody's vfsops vector and its namei/mount conventions.  Phase 1
 * mounts are read-only and single-volume; there is no flusher, export,
 * file handle or sysctl support yet.  The global statistics and the mount
 * structure set-up follow upstream.
 */
#include <sys/param.h>
#include <sys/systm.h>
#include <sys/namei.h>
#include <sys/mount.h>
#include <sys/vnode.h>
#include <sys/proc.h>
#include <sys/conf.h>
#include "hammer.h"

/*
 * NOTE!  Global statistics may not be MPSAFE so HAMMER never uses them
 *	  in conditionals.
 */
int hammer_supported_version = HAMMER_VOL_VERSION_DEFAULT;
int hammer_debug_io;
int hammer_debug_general;
int hammer_debug_inode;
int hammer_debug_locks;
int hammer_debug_btree;
int hammer_debug_tid;
int hammer_debug_recover;		/* -1 will disable, +1 will force */
int hammer_debug_critical;		/* non-zero enter debugger on error */
int hammer_cluster_enable = 0;		/* no cluster_read on Rhapsody */
int hammer_tdmux_ticks;
int hammer_count_fsyncs;
int hammer_count_inodes;
int hammer_count_iqueued;
int hammer_count_reclaims;
int hammer_count_records;
int hammer_count_record_datas;
int hammer_count_volumes;
int hammer_count_buffers;
int hammer_count_nodes;
int64_t hammer_stats_btree_lookups;
int64_t hammer_stats_btree_searches;
int64_t hammer_stats_btree_inserts;
int64_t hammer_stats_btree_deletes;
int64_t hammer_stats_btree_elements;
int64_t hammer_stats_btree_splits;
int64_t hammer_stats_btree_iterations;
int64_t hammer_stats_btree_root_iterations;
int64_t hammer_stats_record_iterations;

int64_t hammer_stats_file_read;
int64_t hammer_stats_file_write;
int64_t hammer_stats_disk_read;
int64_t hammer_stats_disk_write;
int64_t hammer_stats_inode_flushes;
int64_t hammer_stats_commits;
int64_t hammer_stats_undo;
int64_t hammer_stats_redo;

long hammer_count_dirtybufspace;	/* global */
int hammer_count_refedbufs;		/* global */
int hammer_count_reservations;
long hammer_count_io_running_read;
long hammer_count_io_running_write;
int hammer_count_io_locked;
long hammer_limit_dirtybufspace;	/* per-mount */
int hammer_limit_recs;			/* as a whole XXX */
int hammer_limit_inode_recs = 2048;	/* per inode */
int hammer_limit_reclaims;
int hammer_live_dedup_cache_size = 4096;
int hammer_limit_redo = 4096 * 1024;	/* per inode */
int hammer_autoflush = 500;		/* auto flush (typ on reclaim) */
int hammer_verify_zone;
int hammer_verify_data = 1;
int hammer_double_buffer;
int hammer_btree_full_undo = 1;
int hammer_yield_check = 16;
int hammer_fsync_mode = 3;
int64_t hammer_contention_count;

int hammer_noatime = 1;

static int hammer_mounts;		/* live HAMMER mounts */

static int	hammer_vfs_mount(struct mount *mp, char *path, caddr_t data,
				 struct nameidata *ndp, struct proc *p);
static int	hammer_vfs_start(struct mount *mp, int flags, struct proc *p);
static int	hammer_vfs_unmount(struct mount *mp, int mntflags,
				   struct proc *p);
static int	hammer_vfs_root(struct mount *mp, struct vnode **vpp);
static int	hammer_vfs_quotactl(struct mount *mp, int cmds, uid_t uid,
				    caddr_t arg, struct proc *p);
static int	hammer_vfs_statfs(struct mount *mp, struct statfs *sbp,
				  struct proc *p);
static int	hammer_vfs_sync(struct mount *mp, int waitfor,
				struct ucred *cred, struct proc *p);
static int	hammer_vfs_vget(struct mount *mp, void *ino,
				struct vnode **vpp);
static int	hammer_vfs_fhtovp(struct mount *mp, struct fid *fhp,
				  struct mbuf *nam, struct vnode **vpp,
				  int *exflagsp, struct ucred **credanonp);
static int	hammer_vfs_vptofh(struct vnode *vp, struct fid *fhp);
static int	hammer_vfs_init(struct vfsconf *conf);
static int	hammer_vfs_sysctl(int *name, u_int namelen, void *oldp,
				  size_t *oldlenp, void *newp, size_t newlen,
				  struct proc *p);
static void	hammer_free_hmp(struct mount *mp);

struct vfsops hammer_vfsops = {
	hammer_vfs_mount,
	hammer_vfs_start,
	hammer_vfs_unmount,
	hammer_vfs_root,
	hammer_vfs_quotactl,
	hammer_vfs_statfs,
	hammer_vfs_sync,
	hammer_vfs_vget,
	hammer_vfs_fhtovp,
	hammer_vfs_vptofh,
	hammer_vfs_init,
	hammer_vfs_sysctl
};

static int
hammer_vfs_init(struct vfsconf *conf)
{
	/*
	 * Wait up to this long for an exclusive deadlock to clear
	 * before acquiring a new shared lock on the ip.
	 */
	if (hammer_tdmux_ticks == 0)
		hammer_tdmux_ticks = hz / 5;
	if (hammer_limit_recs == 0)
		hammer_limit_recs = 64 * 1024;
	if (hammer_limit_reclaims == 0)
		hammer_limit_reclaims = desiredvnodes / 10;
	if (hammer_limit_reclaims > HAMMER_LIMIT_RECLAIMS)
		hammer_limit_reclaims = HAMMER_LIMIT_RECLAIMS;
	return(0);
}

/*
 * Mount a HAMMER volume read-only.  args.fspec names the block device of
 * the single volume; mount(2)'s flags must include MNT_RDONLY.
 */
static int
hammer_vfs_mount(struct mount *mp, char *path, caddr_t data,
		 struct nameidata *ndp, struct proc *p)
{
	struct hammer_args args;
	hammer_mount_t hmp;
	struct vnode *devvp;
	char from[MNAMELEN];
	char on[MNAMELEN];
	size_t done;
	int error;

	if (mp->mnt_flag & (MNT_UPDATE | MNT_RELOAD | MNT_EXPORTED))
		return(EOPNOTSUPP);
	if ((mp->mnt_flag & MNT_RDONLY) == 0) {
		printf("hammer: read-only in this release\n");
		return(EROFS);
	}
	if ((error = copyin(data, (caddr_t)&args, sizeof(args))) != 0)
		return(error);
	if ((error = copyinstr(args.fspec, from, sizeof(from), &done)) != 0)
		return(error);
	if ((error = copyinstr(path, on, sizeof(on), &done)) != 0)
		return(error);

	/*
	 * Resolve the device, as the other block-device filesystems do.
	 */
	NDINIT(ndp, LOOKUP, FOLLOW, UIO_SYSSPACE, from, p);
	if ((error = namei(ndp)) != 0)
		return(error);
	devvp = ndp->ni_vp;
	if (devvp->v_type != VBLK) {
		vrele(devvp);
		return(ENOTBLK);
	}
	if (major(devvp->v_rdev) >= nblkdev) {
		vrele(devvp);
		return(ENXIO);
	}
	if (p->p_ucred->cr_uid != 0) {
		vn_lock(devvp, LK_EXCLUSIVE | LK_RETRY, p);
		error = VOP_ACCESS(devvp, VREAD, p->p_ucred, p);
		VOP_UNLOCK(devvp, 0, p);
		if (error) {
			vrele(devvp);
			return(error);
		}
	}

	/*
	 * Internal mount data structure (upstream set-up, read-only).
	 */
	hmp = kmalloc(sizeof(*hmp), M_HAMMER, M_WAITOK | M_ZERO);
	mp->mnt_data = (qaddr_t)hmp;
	hmp->mp = mp;
	kmalloc_create(&hmp->m_misc, "HAMMER-others");
	kmalloc_create(&hmp->m_inodes, "HAMMER-inodes");

	hmp->root_btree_beg.localization = hmk32(HAMMER_MIN_ONDISK_LOCALIZATION);
	hmp->root_btree_beg.obj_id = hmk64(HAMMER_MIN_OBJID);
	hmp->root_btree_beg.key = hmk64(HAMMER_MIN_KEY);
	hmp->root_btree_beg.create_tid = hmk64(1);
	hmp->root_btree_beg.delete_tid = hmk64(1);
	hmp->root_btree_beg.rec_type = hmk16(HAMMER_MIN_RECTYPE);
	hmp->root_btree_beg.obj_type = 0;
	hmp->root_btree_beg.btype = HAMMER_BTREE_TYPE_NONE;

	hmp->root_btree_end.localization = hmk32(HAMMER_MAX_ONDISK_LOCALIZATION);
	hmp->root_btree_end.obj_id = hmk64(HAMMER_MAX_OBJID);
	hmp->root_btree_end.key = hmk64(HAMMER_MAX_KEY);
	hmp->root_btree_end.create_tid = hmk64(HAMMER_MAX_TID);
	hmp->root_btree_end.delete_tid = hmk64(0);   /* special case */
	hmp->root_btree_end.rec_type = hmk16(HAMMER_MAX_RECTYPE);
	hmp->root_btree_end.obj_type = 0;
	hmp->root_btree_end.btype = HAMMER_BTREE_TYPE_NONE;

	hmp->krate.freq = 1;	/* maximum reporting rate (hz) */
	hmp->krate.count = -16;	/* initial burst */
	hmp->kdiag.freq = 1;	/* maximum reporting rate (hz) */
	hmp->kdiag.count = -16;	/* initial burst */

	hmp->sync_lock.refs = 1;
	hmp->undo_lock.refs = 1;
	hmp->blkmap_lock.refs = 1;
	hmp->snapshot_lock.refs = 1;
	hmp->volume_lock.refs = 1;

	TAILQ_INIT(&hmp->delay_list);
	TAILQ_INIT(&hmp->flush_group_list);
	TAILQ_INIT(&hmp->objid_cache_list);
	TAILQ_INIT(&hmp->undo_lru_list);
	TAILQ_INIT(&hmp->reclaim_list);

	hmp->master_id = 0;
	hmp->asof = HAMMER_MAX_TID;
	hmp->volume_to_remove = -1;

	RB_INIT(&hmp->rb_vols_root);
	RB_INIT(&hmp->rb_inos_root);
	RB_INIT(&hmp->rb_redo_root);
	RB_INIT(&hmp->rb_nods_root);
	RB_INIT(&hmp->rb_undo_root);
	RB_INIT(&hmp->rb_resv_root);
	RB_INIT(&hmp->rb_bufs_root);
	RB_INIT(&hmp->rb_pfsm_root);
	RB_INIT(&hmp->volu_root);
	RB_INIT(&hmp->undo_root);
	RB_INIT(&hmp->data_root);
	RB_INIT(&hmp->meta_root);
	RB_INIT(&hmp->lose_root);
	TAILQ_INIT(&hmp->iorun_list);
	hmp->ronly = 1;
	++hammer_mounts;

	/*
	 * Admit and install the volume (consumes the devvp reference).
	 */
	error = hammer_install_volume(hmp, from, devvp, NULL);
	if (error) {
		hammer_free_hmp(mp);
		return(error);
	}
	mp->mnt_flag |= MNT_LOCAL;
	mp->mnt_maxsymlinklen = 255;
	vfs_getnewfsid(mp);

	{
		hammer_volume_t rootvol;

		rootvol = hammer_get_root_volume(hmp, &error);
		if (error) {
			hammer_free_hmp(mp);
			return(error);
		}
		hmp->version = hget32(rootvol->ondisk->vol_version);
		bcopy(rootvol->ondisk->vol0_blockmap, hmp->blockmap,
		      sizeof(hmp->blockmap));
		hmp->next_tid = hget64(rootvol->ondisk->vol0_next_tid);
		hmp->flush_tid1 = hmp->next_tid;
		hmp->flush_tid2 = hmp->next_tid;
		hmp->copy_stat_freebigblocks =
			hget64(rootvol->ondisk->vol0_stat_freebigblocks);
		hammer_rel_volume(rootvol, 0);
	}

	/*
	 * Locate the root directory (obj_id 1).
	 */
	{
		struct vnode *rootvp;

		error = hammer_vfs_root(mp, &rootvp);
		if (error) {
			vflush(mp, NULLVP, 0);
			hammer_free_hmp(mp);
			return(error);
		}
		vput(rootvp);
	}

	bzero(mp->mnt_stat.f_mntonname, MNAMELEN);
	bzero(mp->mnt_stat.f_mntfromname, MNAMELEN);
	strcpy(mp->mnt_stat.f_mntonname, on);
	strcpy(mp->mnt_stat.f_mntfromname, from);
	return(hammer_vfs_statfs(mp, &mp->mnt_stat, p));
}

static int
hammer_vfs_start(struct mount *mp, int flags, struct proc *p)
{
	return(0);
}

static int
hammer_vfs_unmount(struct mount *mp, int mntflags, struct proc *p)
{
	int flags = 0;
	int error;

	if (mntflags & MNT_FORCE)
		flags |= FORCECLOSE;
	error = vflush(mp, NULLVP, flags);
	if (error == 0)
		hammer_free_hmp(mp);
	return(error);
}

/*
 * Tear down the internal mount structure.  Read-only mounts have no
 * flusher and nothing dirty: unload the buffers, then the volumes.  When
 * the last HAMMER mount goes, anything still counted has leaked.
 */
static void
hammer_free_hmp(struct mount *mp)
{
	hammer_mount_t hmp = (void *)mp->mnt_data;

	KKASSERT(RB_EMPTY(&hmp->rb_inos_root));
	RB_SCAN(hammer_buf_rb_tree, &hmp->rb_bufs_root, NULL,
		hammer_unload_buffer, NULL);
	RB_SCAN(hammer_vol_rb_tree, &hmp->rb_vols_root, NULL,
		hammer_unload_volume, NULL);

	mp->mnt_data = NULL;
	mp->mnt_flag &= ~MNT_LOCAL;
	hmp->mp = NULL;
	kmalloc_destroy(&hmp->m_misc);
	kmalloc_destroy(&hmp->m_inodes);
	kfree(hmp, M_HAMMER);

	if (--hammer_mounts == 0) {
		if (hammer_count_inodes)
			printf("hammer: leaked inodes=%d\n", hammer_count_inodes);
		if (hammer_count_buffers)
			printf("hammer: leaked buffers=%d\n", hammer_count_buffers);
		if (hammer_count_nodes)
			printf("hammer: leaked nodes=%d\n", hammer_count_nodes);
		if (hammer_count_volumes)
			printf("hammer: leaked volumes=%d\n", hammer_count_volumes);
		if (hammer_count_refedbufs)
			printf("hammer: leaked refedbufs=%d\n",
			       hammer_count_refedbufs);
	}
}

/*
 * Report critical errors.  ip may be NULL.
 */
void
hammer_critical_error(hammer_mount_t hmp, hammer_inode_t ip,
		      int error, const char *msg)
{
	hmp->flags |= HAMMER_MOUNT_CRITICAL_ERROR;
	hmkrateprintf(&hmp->krate, hmp,
		    "Critical error inode=%jd error=%d %s\n",
		    (intmax_t)(ip ? ip->obj_id : -1),
		    error, msg);
	hmp->error = error;
}

/*
 * The root vnode needs the B-Tree and inode code (Task 6).
 */
static int
hammer_vfs_root(struct mount *mp, struct vnode **vpp)
{
	hammer_mount_t hmp = (void *)mp->mnt_data;

	return(hammer_vget_obj(hmp, HAMMER_OBJID_ROOT, HAMMER_DEF_LOCALIZATION,
			       vpp));
}

static int
hammer_vfs_vget(struct mount *mp, void *ino, struct vnode **vpp)
{
	return(EOPNOTSUPP);
}

static int
hammer_vfs_statfs(struct mount *mp, struct statfs *sbp, struct proc *p)
{
	hammer_mount_t hmp = (void *)mp->mnt_data;
	hammer_volume_t volume;
	hammer_volume_ondisk_t ondisk;
	int error;

	volume = hammer_get_root_volume(hmp, &error);
	if (error)
		return(error);
	ondisk = volume->ondisk;
	sbp->f_type = 19;
	sbp->f_bsize = HAMMER_BUFSIZE;
	sbp->f_iosize = HAMMER_BUFSIZE;
	sbp->f_blocks = hget64(ondisk->vol0_stat_bigblocks) *
			HAMMER_BUFFERS_PER_BIGBLOCK;
	sbp->f_bfree = hget64(ondisk->vol0_stat_freebigblocks) *
		       HAMMER_BUFFERS_PER_BIGBLOCK;
	sbp->f_bavail = sbp->f_bfree;
	sbp->f_files = hget64(ondisk->vol0_stat_inodes);
	sbp->f_ffree = 0;
	hammer_rel_volume(volume, 0);
	sbp->f_fsid = mp->mnt_stat.f_fsid;
	strcpy(sbp->f_fstypename, "hammer");
	if (sbp != &mp->mnt_stat) {
		bcopy(mp->mnt_stat.f_mntonname, sbp->f_mntonname, MNAMELEN);
		bcopy(mp->mnt_stat.f_mntfromname, sbp->f_mntfromname, MNAMELEN);
	}
	return(0);
}

static int
hammer_vfs_sync(struct mount *mp, int waitfor, struct ucred *cred,
		struct proc *p)
{
	return(0);	/* read-only: nothing to write */
}

static int
hammer_vfs_quotactl(struct mount *mp, int cmds, uid_t uid, caddr_t arg,
		    struct proc *p)
{
	return(EOPNOTSUPP);
}

static int
hammer_vfs_fhtovp(struct mount *mp, struct fid *fhp, struct mbuf *nam,
		  struct vnode **vpp, int *exflagsp, struct ucred **credanonp)
{
	return(EOPNOTSUPP);
}

static int
hammer_vfs_vptofh(struct vnode *vp, struct fid *fhp)
{
	return(EOPNOTSUPP);
}

static int
hammer_vfs_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp,
		  void *newp, size_t newlen, struct proc *p)
{
	return(EOPNOTSUPP);
}
