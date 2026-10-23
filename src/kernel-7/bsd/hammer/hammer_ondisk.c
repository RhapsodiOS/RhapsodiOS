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
 *
 * $DragonFly: src/sys/vfs/hammer/hammer_ondisk.c,v 1.76 2008/08/29 20:19:08 dillon Exp $
 */
/*
 * Manage HAMMER's on-disk structures.  These routines are primarily
 * responsible for interfacing with the kernel's I/O subsystem and for
 * managing in-memory structures.
 */

#include <bsd/dev/disk.h>

#include "hammer.h"

static void hammer_free_volume(hammer_volume_t volume);
static int hammer_load_volume(hammer_volume_t volume);
static int hammer_load_buffer(hammer_buffer_t buffer, int isnew);
static int hammer_load_node(hammer_transaction_t trans,
				hammer_node_t node, int isnew);
static void _hammer_rel_node(hammer_node_t node, int locked);

static int
hammer_vol_rb_compare(hammer_volume_t vol1, hammer_volume_t vol2)
{
	if (vol1->vol_no < vol2->vol_no)
		return(-1);
	if (vol1->vol_no > vol2->vol_no)
		return(1);
	return(0);
}

/*
 * hammer_buffer structures are indexed via their zoneX_offset, not
 * their zone2_offset.
 */
static int
hammer_buf_rb_compare(hammer_buffer_t buf1, hammer_buffer_t buf2)
{
	if (buf1->zoneX_offset < buf2->zoneX_offset)
		return(-1);
	if (buf1->zoneX_offset > buf2->zoneX_offset)
		return(1);
	return(0);
}

static int
hammer_nod_rb_compare(hammer_node_t node1, hammer_node_t node2)
{
	if (node1->node_offset < node2->node_offset)
		return(-1);
	if (node1->node_offset > node2->node_offset)
		return(1);
	return(0);
}

RB_GENERATE2(hammer_vol_rb_tree, hammer_volume, rb_node,
	     hammer_vol_rb_compare, int32_t, vol_no);
RB_GENERATE2(hammer_buf_rb_tree, hammer_buffer, rb_node,
	     hammer_buf_rb_compare, hammer_off_t, zoneX_offset);
RB_GENERATE2(hammer_nod_rb_tree, hammer_node, rb_node,
	     hammer_nod_rb_compare, hammer_off_t, node_offset);

/************************************************************************
 *				VOLUMES					*
 ************************************************************************
 *
 * Load a HAMMER volume by name.  Returns 0 on success or a positive error
 * code on failure.  Volumes must be loaded at mount time or via hammer
 * volume-add command, hammer_get_volume() will not load a new volume.
 *
 * The passed devvp is vref()'d but not locked.  This function consumes the
 * ref (typically by associating it with the volume structure).
 *
 * Calls made to hammer_load_volume() or single-threaded
 */
int
hammer_install_volume(hammer_mount_t hmp, const char *volname,
		      struct vnode *devvp, void *data)
{
	struct mount *mp = hmp->mp;
	struct proc *p = current_proc();
	int nblks, blksize;
	hammer_volume_t volume;
	hammer_volume_ondisk_t ondisk;
	const char *why = NULL;
	char *hdr = NULL;
	int error;
	int ronly = ((mp->mnt_flag & MNT_RDONLY) ? 1 : 0);
	int opened = 0;

	/*
	 * Rhapsody HAMMER is single-volume and never formats from the
	 * kernel: the caller resolved the device vnode (one reference,
	 * consumed here) and there is no volume image to install.
	 */
	KKASSERT(devvp != NULL && data == NULL);

	++hammer_count_volumes;
	volume = kmalloc(sizeof(*volume), hmp->m_misc, M_WAITOK|M_ZERO);
	volume->vol_name = kstrdup(volname, hmp->m_misc);
	volume->io.hmp = hmp;	/* bootstrap */
	hammer_io_init(&volume->io, volume, HAMMER_IOTYPE_VOLUME);
	volume->io.offset = 0LL;
	volume->io.bytes = HAMMER_BUFSIZE;
	volume->devvp = devvp;

	why = "device in use";
	error = vfs_mountedon(devvp);
	if (error == 0 && vcount(devvp) > 1)
		error = EBUSY;
	if (error == 0)
		error = vinvalbuf(devvp, V_SAVE, p->p_ucred, p, 0, 0);
	if (error == 0) {
		why = "cannot open device";
		error = VOP_OPEN(devvp, ronly ? FREAD : FREAD|FWRITE,
				 p->p_ucred, p);
		opened = (error == 0);
	}
	if (error == 0) {
		/* The IDE driver refuses DKIOCGPARTINFO (EINVAL); HFS uses these. */
		why = "cannot get partition size";
		error = VOP_IOCTL(devvp, DKIOCNUMBLKS, (caddr_t)&nblks,
				  FREAD, p->p_ucred, p);
		if (error == 0)
			error = VOP_IOCTL(devvp, DKIOCBLKSIZE, (caddr_t)&blksize,
					  FREAD, p->p_ucred, p);
	}

	/*
	 * Admit or refuse the volume from its header before anything else
	 * looks at it (hammer_admit.c).
	 */
	if (error == 0) {
		why = "cannot read volume header";
		hdr = kmalloc(HAMMER_BUFSIZE, M_HAMMER, M_WAITOK);
		error = hammer_dev_read(devvp, 0, hdr, HAMMER_BUFSIZE);
	}
	if (error == 0) {
		error = hammer_admit_volume(hdr, HAMMER_BUFSIZE,
			(uint64_t)(u_int)blksize * (u_int)nblks,
			&why);
		if (error == 0)
			printf("hammer: %s: v7 single volume ok\n", volname);
	}
	if (error) {
		printf("hammer: %s: %s (error %d)\n", volname, why, error);
		goto failed;
	}

	ondisk = (void *)hdr;
	volume->vol_no = (int32_t)hget32(ondisk->vol_no);
	volume->vol_flags = hget32(ondisk->vol_flags);
	volume->maxbuf_off = HAMMER_ENCODE_RAW_BUFFER(volume->vol_no,
				    HAMMER_VOL_BUF_SIZE(ondisk));
	hmp->fsid = ondisk->vol_fsid;
	RB_INSERT(hammer_vol_rb_tree, &hmp->rb_vols_root, volume);
	hammer_volume_number_add(hmp, volume);

	/*
	 * Admission guarantees this is the root volume (vol_no 0) of a
	 * one-volume filesystem.  We do not hold a ref on rootvol because
	 * that would prevent related I/O from being flushed.
	 */
	hmp->rootvol = volume;
	hmp->nvolumes = 1;
	mp->mnt_stat.f_blocks += hget64(ondisk->vol0_stat_bigblocks) *
				 HAMMER_BUFFERS_PER_BIGBLOCK;
	devvp->v_specflags |= SI_MOUNTEDON;
	kfree(hdr, M_HAMMER);
	return (0);

failed:
	if (hdr)
		kfree(hdr, M_HAMMER);
	if (opened)
		VOP_CLOSE(devvp, ronly ? FREAD : FREAD|FWRITE, NOCRED, p);
	hammer_free_volume(volume);
	return (error);
}

/*
 * This is called for each volume when updating the mount point from
 * read-write to read-only or vise-versa.
 */
int
hammer_adjust_volume_mode(hammer_volume_t volume, void *data __unused)
{
	/* Phase 1 mounts are read-only and never change mode. */
	return(0);
}

/*
 * Unload and free a HAMMER volume.  Must return >= 0 to continue scan
 * so returns -1 on failure.
 */
int
hammer_unload_volume(hammer_volume_t volume, void *data)
{
	hammer_mount_t hmp = volume->io.hmp;
	struct proc *p = current_proc();
	int ronly = ((hmp->mp->mnt_flag & MNT_RDONLY) ? 1 : 0);

	/* No volume-header images: volumes are never removed (data is NULL). */
	KKASSERT(data == NULL);

	/*
	 * Clean up the root volume pointer, which is held unlocked in hmp.
	 */
	if (hmp->rootvol == volume)
		hmp->rootvol = NULL;

	/*
	 * We must not flush a dirty buffer to disk on umount.  It should
	 * have already been dealt with by the flusher, or we may be in
	 * catastrophic failure.
	 */
	hammer_io_clear_modify(&volume->io, 1);
	volume->io.waitdep = 1;

	/*
	 * Clean up the persistent ref ioerror might have on the volume
	 */
	if (volume->io.ioerror)
		hammer_io_clear_error_noassert(&volume->io);

	/*
	 * This should release the bp.  Releasing the volume with flush set
	 * implies the interlock is set.
	 */
	hammer_ref_interlock_true(&volume->io.lock);
	hammer_rel_volume(volume, 1);
	KKASSERT(volume->io.data == NULL);

	/*
	 * There should be no references on the volume.
	 */
	KKASSERT(hammer_norefs(&volume->io.lock));

	volume->ondisk = NULL;
	if (volume->devvp) {
		volume->devvp->v_specflags &= ~SI_MOUNTEDON;
		vinvalbuf(volume->devvp, ronly ? 0 : V_SAVE, NOCRED, p, 0, 0);
		VOP_CLOSE(volume->devvp, ronly ? FREAD : FREAD|FWRITE,
			  NOCRED, p);
	}

	/*
	 * Destroy the structure
	 */
	RB_REMOVE(hammer_vol_rb_tree, &hmp->rb_vols_root, volume);
	hammer_volume_number_del(hmp, volume);
	hammer_free_volume(volume);
	return(0);
}

static
void
hammer_free_volume(hammer_volume_t volume)
{
	hammer_mount_t hmp = volume->io.hmp;

	if (volume->vol_name) {
		kfree(volume->vol_name, hmp->m_misc);
		volume->vol_name = NULL;
	}
	if (volume->devvp) {
		vrele(volume->devvp);
		volume->devvp = NULL;
	}
	--hammer_count_volumes;
	kfree(volume, hmp->m_misc);
}

/*
 * Get a HAMMER volume.  The volume must already exist.
 */
hammer_volume_t
hammer_get_volume(hammer_mount_t hmp, int32_t vol_no, int *errorp)
{
	hammer_volume_t volume;

	/*
	 * Locate the volume structure
	 */
	volume = RB_LOOKUP(hammer_vol_rb_tree, &hmp->rb_vols_root, vol_no);
	if (volume == NULL) {
		*errorp = ENOENT;
		return(NULL);
	}

	/*
	 * Reference the volume, load/check the data on the 0->1 transition.
	 * hammer_load_volume() will dispose of the interlock on return,
	 * and also clean up the ref count on error.
	 */
	if (hammer_ref_interlock(&volume->io.lock)) {
		*errorp = hammer_load_volume(volume);
		if (*errorp)
			volume = NULL;
	} else {
		KKASSERT(volume->ondisk);
		*errorp = 0;
	}
	return(volume);
}

int
hammer_ref_volume(hammer_volume_t volume)
{
	int error;

	/*
	 * Reference the volume and deal with the check condition used to
	 * load its ondisk info.
	 */
	if (hammer_ref_interlock(&volume->io.lock)) {
		error = hammer_load_volume(volume);
	} else {
		KKASSERT(volume->ondisk);
		error = 0;
	}
	return (error);
}

/*
 * May be called without fs_token
 */
hammer_volume_t
hammer_get_root_volume(hammer_mount_t hmp, int *errorp)
{
	hammer_volume_t volume;

	volume = hmp->rootvol;
	KKASSERT(volume != NULL);

	/*
	 * Reference the volume and deal with the check condition used to
	 * load its ondisk info.
	 */
	if (hammer_ref_interlock(&volume->io.lock)) {
		lwkt_gettoken(&volume->io.hmp->fs_token);
		*errorp = hammer_load_volume(volume);
		lwkt_reltoken(&volume->io.hmp->fs_token);
		if (*errorp)
			volume = NULL;
	} else {
		KKASSERT(volume->ondisk);
		*errorp = 0;
	}
	return (volume);
}

/*
 * Load a volume's on-disk information.  The volume must be referenced and
 * the interlock is held on call.  The interlock will be released on return.
 * The reference will also be released on return if an error occurs.
 */
static int
hammer_load_volume(hammer_volume_t volume)
{
	int error;

	if (volume->ondisk == NULL) {
		error = hammer_io_read(volume->devvp, &volume->io,
				       HAMMER_BUFSIZE);
		if (error == 0) {
			volume->ondisk = (void *)volume->io.data;
                        hammer_ref_interlock_done(&volume->io.lock);
		} else {
                        hammer_rel_volume(volume, 1);
		}
	} else {
		error = 0;
	}
	return(error);
}

/*
 * Release a previously acquired reference on the volume.
 *
 * Volumes are not unloaded from memory during normal operation.
 *
 * May be called without fs_token
 */
void
hammer_rel_volume(hammer_volume_t volume, int locked)
{
	struct buf *bp;

	if (hammer_rel_interlock(&volume->io.lock, locked)) {
		lwkt_gettoken(&volume->io.hmp->fs_token);
		volume->ondisk = NULL;
		bp = hammer_io_release(&volume->io, locked);
		lwkt_reltoken(&volume->io.hmp->fs_token);
		hammer_rel_interlock_done(&volume->io.lock, locked);
		if (bp)
			brelse(bp);
	}
}

int
hammer_mountcheck_volumes(hammer_mount_t hmp)
{
	hammer_volume_t vol;
	int i;

	HAMMER_VOLUME_NUMBER_FOREACH(hmp, i) {
		vol = RB_LOOKUP(hammer_vol_rb_tree, &hmp->rb_vols_root, i);
		if (vol == NULL)
			return(EINVAL);
	}
	return(0);
}

int
hammer_get_installed_volumes(hammer_mount_t hmp)
{
	int i, ret = 0;

	HAMMER_VOLUME_NUMBER_FOREACH(hmp, i)
		ret++;
	return(ret);
}

/************************************************************************
 *				BUFFERS					*
 ************************************************************************
 *
 * Manage buffers.  Currently most blockmap-backed zones are direct-mapped
 * to zone-2 buffer offsets, without a translation stage.  However, the
 * hammer_buffer structure is indexed by its zoneX_offset, not its
 * zone2_offset.
 *
 * The proper zone must be maintained throughout the code-base all the way
 * through to the big-block allocator, or routines like hammer_del_buffers()
 * will not be able to locate all potentially conflicting buffers.
 */

/*
 * Helper function returns whether a zone offset can be directly translated
 * to a raw buffer index or not.  Really only the volume and undo zones
 * can't be directly translated.  Volumes are special-cased and undo zones
 * shouldn't be aliased accessed in read-only mode.
 *
 * This function is ONLY used to detect aliased zones during a read-only
 * mount.
 */
static __inline int
hammer_direct_zone(hammer_off_t buf_offset)
{
	return(hammer_is_zone_direct_xlated(buf_offset));
}

hammer_buffer_t
hammer_get_buffer(hammer_mount_t hmp, hammer_off_t buf_offset,
		  int bytes, int isnew, int *errorp)
{
	hammer_buffer_t buffer;
	hammer_volume_t volume;
	hammer_off_t	zone2_offset;
	int vol_no;
	int zone;

	buf_offset &= ~HAMMER_BUFMASK64;
again:
	/*
	 * Shortcut if the buffer is already cached
	 */
	buffer = RB_LOOKUP(hammer_buf_rb_tree, &hmp->rb_bufs_root, buf_offset);
	if (buffer) {
		/*
		 * Once refed the ondisk field will not be cleared by
		 * any other action.  Shortcut the operation if the
		 * ondisk structure is valid.
		 */
found_aliased:
		if (hammer_ref_interlock(&buffer->io.lock) == 0) {
			hammer_io_advance(&buffer->io);
			KKASSERT(buffer->ondisk);
			*errorp = 0;
			return(buffer);
		}

		/*
		 * 0->1 transition or defered 0->1 transition (CHECK),
		 * interlock now held.  Shortcut if ondisk is already
		 * assigned.
		 */
		atomic_add_int(&hammer_count_refedbufs, 1);
		if (buffer->ondisk) {
			hammer_io_advance(&buffer->io);
			hammer_ref_interlock_done(&buffer->io.lock);
			*errorp = 0;
			return(buffer);
		}

		/*
		 * The buffer is no longer loose if it has a ref, and
		 * cannot become loose once it gains a ref.  Loose
		 * buffers will never be in a modified state.  This should
		 * only occur on the 0->1 transition of refs.
		 *
		 * lose_root can be modified via a biodone() interrupt
		 * so the io_token must be held.
		 */
		if (buffer->io.mod_root == &hmp->lose_root) {
			lwkt_gettoken(&hmp->io_token);
			if (buffer->io.mod_root == &hmp->lose_root) {
				RB_REMOVE(hammer_mod_rb_tree,
					  buffer->io.mod_root, &buffer->io);
				buffer->io.mod_root = NULL;
				KKASSERT(buffer->io.modified == 0);
			}
			lwkt_reltoken(&hmp->io_token);
		}
		goto found;
	} else if (hmp->ronly && hammer_direct_zone(buf_offset)) {
		/*
		 * If this is a read-only mount there could be an alias
		 * in the raw-zone.  If there is we use that buffer instead.
		 *
		 * rw mounts will not have aliases.  Also note when going
		 * from ro -> rw the recovered raw buffers are flushed and
		 * reclaimed, so again there will not be any aliases once
		 * the mount is rw.
		 */
		buffer = RB_LOOKUP(hammer_buf_rb_tree, &hmp->rb_bufs_root,
				   hammer_xlate_to_zone2(buf_offset));
		if (buffer) {
			if (hammer_debug_general & 0x0001) {
				hkrateprintf(&hmp->kdiag,
					    "recovered aliased %016jx\n",
					    (intmax_t)buf_offset);
			}
			goto found_aliased;
		}
	}

	/*
	 * Handle blockmap offset translations
	 */
	zone = HAMMER_ZONE_DECODE(buf_offset);
	if (hammer_is_index_record(zone)) {
		zone2_offset = hammer_blockmap_lookup(hmp, buf_offset, errorp);
	} else if (zone == HAMMER_ZONE_RAW_BUFFER_INDEX) {
		zone2_offset = buf_offset;
		*errorp = 0;
	} else {
		/*
		 * Zone 1, 4 or 15, or the UNDO zone (read only by recovery,
		 * Phase 2): a crafted or damaged offset, not a panic.
		 */
		hkprintf("buffer %016jx: not a readable zone\n",
			 (intmax_t)buf_offset);
		*errorp = EIO;
		return(NULL);
	}
	if (*errorp)
		return(NULL);

	/*
	 * NOTE: zone2_offset and maxbuf_off are both full zone-2 offset
	 * specifications.
	 */
	KKASSERT(hammer_is_zone_raw_buffer(zone2_offset));
	vol_no = HAMMER_VOL_DECODE(zone2_offset);
	volume = hammer_get_volume(hmp, vol_no, errorp);
	if (volume == NULL)
		return(NULL);

	if (zone2_offset >= volume->maxbuf_off) {
		hkprintf("buffer %016jx: past the end of the volume\n",
			 (intmax_t)buf_offset);
		hammer_rel_volume(volume, 0);
		*errorp = EIO;
		return(NULL);
	}

	/*
	 * Allocate a new buffer structure.  We will check for races later.
	 */
	++hammer_count_buffers;
	buffer = kmalloc(sizeof(*buffer), hmp->m_misc,
			 M_WAITOK|M_ZERO|M_USE_RESERVE);
	buffer->zone2_offset = zone2_offset;
	buffer->zoneX_offset = buf_offset;

	hammer_io_init(&buffer->io, volume, hammer_zone_to_iotype(zone));
	buffer->io.offset = hammer_xlate_to_phys(volume->ondisk, zone2_offset);
	buffer->io.bytes = bytes;
	TAILQ_INIT(&buffer->node_list);
	hammer_ref_interlock_true(&buffer->io.lock);

	/*
	 * Insert the buffer into the RB tree and handle late collisions.
	 */
	if (RB_INSERT(hammer_buf_rb_tree, &hmp->rb_bufs_root, buffer)) {
		hammer_rel_volume(volume, 0);
		buffer->io.volume = NULL;			/* safety */
		if (hammer_rel_interlock(&buffer->io.lock, 1))	/* safety */
			hammer_rel_interlock_done(&buffer->io.lock, 1);
		--hammer_count_buffers;
		kfree(buffer, hmp->m_misc);
		goto again;
	}
	atomic_add_int(&hammer_count_refedbufs, 1);
found:

	/*
	 * The buffer is referenced and interlocked.  Load the buffer
	 * if necessary.  hammer_load_buffer() deals with the interlock
	 * and, if an error is returned, also deals with the ref.
	 */
	if (buffer->ondisk == NULL) {
		*errorp = hammer_load_buffer(buffer, isnew);
		if (*errorp)
			buffer = NULL;
	} else {
		hammer_io_advance(&buffer->io);
		hammer_ref_interlock_done(&buffer->io.lock);
		*errorp = 0;
	}
	return(buffer);
}

/*
 * This is used by the direct-read code to deal with large-data buffers
 * created by the reblocker and mirror-write code.  The direct-read code
 * bypasses the HAMMER buffer subsystem and so any aliased dirty or write-
 * running hammer buffers must be fully synced to disk before we can issue
 * the direct-read.
 *
 * This code path is not considered critical as only the rebocker and
 * mirror-write code will create large-data buffers via the HAMMER buffer
 * subsystem.  They do that because they operate at the B-Tree level and
 * do not access the vnode/inode structures.
 */
void
hammer_sync_buffers(hammer_mount_t hmp, hammer_off_t base_offset, int bytes)
{
	hammer_buffer_t buffer;
	int error;

	KKASSERT(hammer_is_zone_large_data(base_offset));

	while (bytes > 0) {
		buffer = RB_LOOKUP(hammer_buf_rb_tree, &hmp->rb_bufs_root,
				   base_offset);
		if (buffer && (buffer->io.modified || buffer->io.running)) {
			error = hammer_ref_buffer(buffer);
			if (error == 0) {
				hammer_io_wait(&buffer->io);
				if (buffer->io.modified) {
					hammer_io_write_interlock(&buffer->io);
					hammer_io_flush(&buffer->io, 0);
					hammer_io_done_interlock(&buffer->io);
					hammer_io_wait(&buffer->io);
				}
				hammer_rel_buffer(buffer, 0);
			}
		}
		base_offset += HAMMER_BUFSIZE;
		bytes -= HAMMER_BUFSIZE;
	}
}

/*
 * Destroy all buffers covering the specified zoneX offset range.  This
 * is called when the related blockmap layer2 entry is freed or when
 * a direct write bypasses our buffer/buffer-cache subsystem.
 *
 * The buffers may be referenced by the caller itself.  Setting reclaim
 * will cause the buffer to be destroyed when it's ref count reaches zero.
 *
 * Return 0 on success, EAGAIN if some buffers could not be destroyed due
 * to additional references held by other threads, or some other (typically
 * fatal) error.
 */
int
hammer_del_buffers(hammer_mount_t hmp, hammer_off_t base_offset,
		   hammer_off_t zone2_offset, int bytes,
		   int report_conflicts)
{
	hammer_buffer_t buffer;
	hammer_volume_t volume;
	int vol_no;
	int error;
	int ret_error;

	vol_no = HAMMER_VOL_DECODE(zone2_offset);
	volume = hammer_get_volume(hmp, vol_no, &ret_error);
	KKASSERT(ret_error == 0);

	while (bytes > 0) {
		buffer = RB_LOOKUP(hammer_buf_rb_tree, &hmp->rb_bufs_root,
				   base_offset);
		if (buffer) {
			error = hammer_ref_buffer(buffer);
			if (hammer_debug_general & 0x20000) {
				hkprintf("delbufr %016jx rerr=%d 1ref=%d\n",
					(intmax_t)buffer->zoneX_offset,
					error,
					hammer_oneref(&buffer->io.lock));
			}
			if (error == 0 && !hammer_oneref(&buffer->io.lock)) {
				error = EAGAIN;
				hammer_rel_buffer(buffer, 0);
			}
			if (error == 0) {
				KKASSERT(buffer->zone2_offset == zone2_offset);
				hammer_io_clear_modify(&buffer->io, 1);
				buffer->io.reclaim = 1;
				buffer->io.waitdep = 1;
				KKASSERT(buffer->io.volume == volume);
				hammer_rel_buffer(buffer, 0);
			}
		} else {
			error = hammer_io_inval(volume, zone2_offset);
		}
		if (error) {
			ret_error = error;
			if (report_conflicts ||
			    (hammer_debug_general & 0x8000)) {
				krateprintf(&hmp->kdiag,
					"hammer_del_buffers: unable to "
					"invalidate %016jx buffer=%p "
					"rep=%d lkrefs=%08x\n",
					(intmax_t)base_offset,
					buffer, report_conflicts,
					(buffer ? buffer->io.lock.refs : -1));
			}
		}
		base_offset += HAMMER_BUFSIZE;
		zone2_offset += HAMMER_BUFSIZE;
		bytes -= HAMMER_BUFSIZE;
	}
	hammer_rel_volume(volume, 0);
	return (ret_error);
}

/*
 * Given a referenced and interlocked buffer load/validate the data.
 *
 * The buffer interlock will be released on return.  If an error is
 * returned the buffer reference will also be released (and the buffer
 * pointer will thus be stale).
 */
static int
hammer_load_buffer(hammer_buffer_t buffer, int isnew)
{
	hammer_volume_t volume;
	int error;

	/*
	 * Load the buffer's on-disk info
	 */
	volume = buffer->io.volume;

	if (hammer_debug_io & 0x0004) {
		hdkprintf("load_buffer %016jx %016jx isnew=%d od=%p\n",
			(intmax_t)buffer->zoneX_offset,
			(intmax_t)buffer->zone2_offset,
			isnew, buffer->ondisk);
	}

	if (buffer->ondisk == NULL) {
		/*
		 * Issue the read or generate a new buffer.  When reading
		 * the limit argument controls any read-ahead clustering
		 * hammer_io_read() is allowed to do.
		 *
		 * We cannot read-ahead in the large-data zone and we cannot
		 * cross a big-block boundary as the next big-block might
		 * use a different buffer size.
		 */
		if (isnew) {
			error = hammer_io_new(volume->devvp, &buffer->io);
		} else if (hammer_is_zone_large_data(buffer->zoneX_offset)) {
			error = hammer_io_read(volume->devvp, &buffer->io,
					       buffer->io.bytes);
		} else {
			hammer_off_t limit;

			limit = HAMMER_BIGBLOCK_DOALIGN(buffer->zone2_offset);
			limit -= buffer->zone2_offset;
			error = hammer_io_read(volume->devvp, &buffer->io,
					       limit);
		}
		if (error == 0)
			buffer->ondisk = (void *)buffer->io.data;
	} else if (isnew) {
		error = hammer_io_new(volume->devvp, &buffer->io);
	} else {
		error = 0;
	}
	if (error == 0) {
		hammer_io_advance(&buffer->io);
		hammer_ref_interlock_done(&buffer->io.lock);
	} else {
		hammer_rel_buffer(buffer, 1);
	}
	return (error);
}

/*
 * NOTE: Called from RB_SCAN, must return >= 0 for scan to continue.
 * This routine is only called during unmount or when a volume is
 * removed.
 *
 * If data != NULL, it specifies a volume whoose buffers should
 * be unloaded.
 */
int
hammer_unload_buffer(hammer_buffer_t buffer, void *data)
{
	hammer_volume_t volume = (hammer_volume_t)data;

	/*
	 * If volume != NULL we are only interested in unloading buffers
	 * associated with a particular volume.
	 */
	if (volume != NULL && volume != buffer->io.volume)
		return 0;

	/*
	 * Clean up the persistent ref ioerror might have on the buffer
	 * and acquire a ref.  Expect a 0->1 transition.
	 */
	if (buffer->io.ioerror) {
		hammer_io_clear_error_noassert(&buffer->io);
		atomic_add_int(&hammer_count_refedbufs, -1);
	}
	hammer_ref_interlock_true(&buffer->io.lock);
	atomic_add_int(&hammer_count_refedbufs, 1);

	/*
	 * We must not flush a dirty buffer to disk on umount.  It should
	 * have already been dealt with by the flusher, or we may be in
	 * catastrophic failure.
	 *
	 * We must set waitdep to ensure that a running buffer is waited
	 * on and released prior to us trying to unload the volume.
	 */
	hammer_io_clear_modify(&buffer->io, 1);
	hammer_flush_buffer_nodes(buffer);
	buffer->io.waitdep = 1;
	hammer_rel_buffer(buffer, 1);
	return(0);
}

/*
 * Reference a buffer that is either already referenced or via a specially
 * handled pointer (aka cursor->buffer).
 */
int
hammer_ref_buffer(hammer_buffer_t buffer)
{
	hammer_mount_t hmp;
	int error;
	int locked;

	/*
	 * Acquire a ref, plus the buffer will be interlocked on the
	 * 0->1 transition.
	 */
	locked = hammer_ref_interlock(&buffer->io.lock);
	hmp = buffer->io.hmp;

	/*
	 * At this point a biodone() will not touch the buffer other then
	 * incidental bits.  However, lose_root can be modified via
	 * a biodone() interrupt.
	 *
	 * No longer loose.  lose_root requires the io_token.
	 */
	if (buffer->io.mod_root == &hmp->lose_root) {
		lwkt_gettoken(&hmp->io_token);
		if (buffer->io.mod_root == &hmp->lose_root) {
			RB_REMOVE(hammer_mod_rb_tree,
				  buffer->io.mod_root, &buffer->io);
			buffer->io.mod_root = NULL;
		}
		lwkt_reltoken(&hmp->io_token);
	}

	if (locked) {
		atomic_add_int(&hammer_count_refedbufs, 1);
		error = hammer_load_buffer(buffer, 0);
		/* NOTE: on error the buffer pointer is stale */
	} else {
		error = 0;
	}
	return(error);
}

/*
 * Release a reference on the buffer.  On the 1->0 transition the
 * underlying IO will be released but the data reference is left
 * cached.
 *
 * Only destroy the structure itself if the related buffer cache buffer
 * was disassociated from it.  This ties the management of the structure
 * to the buffer cache subsystem.  buffer->ondisk determines whether the
 * embedded io is referenced or not.
 */
void
hammer_rel_buffer(hammer_buffer_t buffer, int locked)
{
	hammer_volume_t volume;
	hammer_mount_t hmp;
	struct buf *bp = NULL;
	int freeme = 0;

	hmp = buffer->io.hmp;

	if (hammer_rel_interlock(&buffer->io.lock, locked) == 0)
		return;

	/*
	 * hammer_count_refedbufs accounting.  Decrement if we are in
	 * the error path or if CHECK is clear.
	 *
	 * If we are not in the error path and CHECK is set the caller
	 * probably just did a hammer_ref() and didn't account for it,
	 * so we don't account for the loss here.
	 */
	if (locked || (buffer->io.lock.refs & HAMMER_REFS_CHECK) == 0)
		atomic_add_int(&hammer_count_refedbufs, -1);

	/*
	 * If the caller locked us or the normal released transitions
	 * from 1->0 (and acquired the lock) attempt to release the
	 * io.  If the called locked us we tell hammer_io_release()
	 * to flush (which would be the unload or failure path).
	 */
	bp = hammer_io_release(&buffer->io, locked);

	/*
	 * If the buffer has no bp association and no refs we can destroy
	 * it.
	 *
	 * NOTE: It is impossible for any associated B-Tree nodes to have
	 * refs if the buffer has no additional refs.
	 */
	if (buffer->io.data == NULL && hammer_norefs(&buffer->io.lock)) {

		RB_REMOVE(hammer_buf_rb_tree,
			  &buffer->io.hmp->rb_bufs_root,
			  buffer);
		volume = buffer->io.volume;
		buffer->io.volume = NULL; /* sanity */
		hammer_rel_volume(volume, 0);
		hammer_io_clear_modlist(&buffer->io);
		hammer_flush_buffer_nodes(buffer);
		KKASSERT(TAILQ_EMPTY(&buffer->node_list));
		freeme = 1;
	}

	/*
	 * Cleanup
	 */
	hammer_rel_interlock_done(&buffer->io.lock, locked);
	if (bp)
		brelse(bp);
	if (freeme) {
		--hammer_count_buffers;
		kfree(buffer, hmp->m_misc);
	}
}

/*
 * Access the filesystem buffer containing the specified hammer offset.
 * buf_offset is a conglomeration of the volume number and vol_buf_beg
 * relative buffer offset.  It must also have bit 55 set to be valid.
 * (see hammer_off_t in hammer_disk.h).
 *
 * Any prior buffer in *bufferp will be released and replaced by the
 * requested buffer.
 *
 * NOTE: The buffer is indexed via its zoneX_offset but we allow the
 * passed cached *bufferp to match against either zoneX or zone2.
 */
static __inline
void *
_hammer_bread(hammer_mount_t hmp, hammer_off_t buf_offset, int bytes,
	     int isnew, int *errorp, hammer_buffer_t *bufferp)
{
	hammer_buffer_t buffer;
	int32_t xoff = (int32_t)buf_offset & HAMMER_BUFMASK;

	buf_offset &= ~HAMMER_BUFMASK64;
	KKASSERT(HAMMER_ZONE(buf_offset) != 0);

	buffer = *bufferp;
	if (buffer == NULL || (buffer->zone2_offset != buf_offset &&
			       buffer->zoneX_offset != buf_offset)) {
		if (buffer)
			hammer_rel_buffer(buffer, 0);
		buffer = hammer_get_buffer(hmp, buf_offset, bytes, isnew, errorp);
		*bufferp = buffer;
	} else {
		*errorp = 0;
	}

	/*
	 * Return a pointer to the buffer data.
	 */
	if (buffer == NULL)
		return(NULL);
	else
		return((char *)buffer->ondisk + xoff);
}

void *
hammer_bread(hammer_mount_t hmp, hammer_off_t buf_offset,
	     int *errorp, hammer_buffer_t *bufferp)
{
	return(_hammer_bread(hmp, buf_offset, HAMMER_BUFSIZE, 0, errorp, bufferp));
}

void *
hammer_bread_ext(hammer_mount_t hmp, hammer_off_t buf_offset, int bytes,
	         int *errorp, hammer_buffer_t *bufferp)
{
	bytes = HAMMER_BUFSIZE_DOALIGN(bytes);
	return(_hammer_bread(hmp, buf_offset, bytes, 0, errorp, bufferp));
}

/*
 * Access the filesystem buffer containing the specified hammer offset.
 * No disk read operation occurs.  The result buffer may contain garbage.
 *
 * Any prior buffer in *bufferp will be released and replaced by the
 * requested buffer.
 *
 * This function marks the buffer dirty but does not increment its
 * modify_refs count.
 */
void *
hammer_bnew(hammer_mount_t hmp, hammer_off_t buf_offset,
	     int *errorp, hammer_buffer_t *bufferp)
{
	return(_hammer_bread(hmp, buf_offset, HAMMER_BUFSIZE, 1, errorp, bufferp));
}

void *
hammer_bnew_ext(hammer_mount_t hmp, hammer_off_t buf_offset, int bytes,
		int *errorp, hammer_buffer_t *bufferp)
{
	bytes = HAMMER_BUFSIZE_DOALIGN(bytes);
	return(_hammer_bread(hmp, buf_offset, bytes, 1, errorp, bufferp));
}

/************************************************************************
 *				NODES					*
 ************************************************************************
 *
 * Manage B-Tree nodes.  B-Tree nodes represent the primary indexing
 * method used by the HAMMER filesystem.
 *
 * Unlike other HAMMER structures, a hammer_node can be PASSIVELY
 * associated with its buffer, and will only referenced the buffer while
 * the node itself is referenced.
 *
 * A hammer_node can also be passively associated with other HAMMER
 * structures, such as inodes, while retaining 0 references.  These
 * associations can be cleared backwards using a pointer-to-pointer in
 * the hammer_node.
 *
 * This allows the HAMMER implementation to cache hammer_nodes long-term
 * and short-cut a great deal of the infrastructure's complexity.  In
 * most cases a cached node can be reacquired without having to dip into
 * the B-Tree.
 */
hammer_node_t
hammer_get_node(hammer_transaction_t trans, hammer_off_t node_offset,
		int isnew, int *errorp)
{
	hammer_mount_t hmp = trans->hmp;
	hammer_node_t node;
	int doload;

	/*
	 * A child offset comes from its parent on disk: it must be a
	 * B-Tree zone address of a whole node, or the volume is damaged.
	 */
	if (!hammer_is_zone_btree(node_offset) ||
	    (node_offset & (sizeof(struct hammer_node_ondisk) - 1))) {
		hkprintf("B-Tree node offset %016jx is invalid\n",
			 (intmax_t)node_offset);
		*errorp = EIO;
		return(NULL);
	}

	/*
	 * Locate the structure, allocating one if necessary.
	 */
again:
	node = RB_LOOKUP(hammer_nod_rb_tree, &hmp->rb_nods_root, node_offset);
	if (node == NULL) {
		++hammer_count_nodes;
		node = kmalloc(sizeof(*node), hmp->m_misc, M_WAITOK|M_ZERO|M_USE_RESERVE);
		node->node_offset = node_offset;
		node->hmp = hmp;
		TAILQ_INIT(&node->cursor_list);
		TAILQ_INIT(&node->cache_list);
		if (RB_INSERT(hammer_nod_rb_tree, &hmp->rb_nods_root, node)) {
			--hammer_count_nodes;
			kfree(node, hmp->m_misc);
			goto again;
		}
		doload = hammer_ref_interlock_true(&node->lock);
	} else {
		doload = hammer_ref_interlock(&node->lock);
	}
	if (doload) {
		*errorp = hammer_load_node(trans, node, isnew);
		if (*errorp)
			node = NULL;
	} else {
		KKASSERT(node->ondisk);
		*errorp = 0;
		hammer_io_advance(&node->buffer->io);
	}
	return(node);
}

/*
 * Reference an already-referenced node.  0->1 transitions should assert
 * so we do not have to deal with hammer_ref() setting CHECK.
 */
void
hammer_ref_node(hammer_node_t node)
{
	KKASSERT(hammer_isactive(&node->lock) && node->ondisk != NULL);
	hammer_ref(&node->lock);
}

/*
 * Load a node's on-disk data reference.  Called with the node referenced
 * and interlocked.
 *
 * On return the node interlock will be unlocked.  If a non-zero error code
 * is returned the node will also be dereferenced (and the caller's pointer
 * will be stale).
 */
static int
hammer_load_node(hammer_transaction_t trans, hammer_node_t node, int isnew)
{
	hammer_buffer_t buffer;
	hammer_off_t buf_offset;
	hammer_mount_t hmp = trans->hmp;
	int error;

	error = 0;
	if (node->ondisk == NULL) {
		/*
		 * This is a little confusing but the jist is that
		 * node->buffer determines whether the node is on
		 * the buffer's node_list and node->ondisk determines
		 * whether the buffer is referenced.
		 *
		 * We could be racing a buffer release, in which case
		 * node->buffer may become NULL while we are blocked
		 * referencing the buffer.
		 */
		if ((buffer = node->buffer) != NULL) {
			error = hammer_ref_buffer(buffer);
			if (error == 0 && node->buffer == NULL) {
				TAILQ_INSERT_TAIL(&buffer->node_list, node, entry);
				node->buffer = buffer;
			}
		} else {
			buf_offset = node->node_offset & ~HAMMER_BUFMASK64;
			buffer = hammer_get_buffer(node->hmp, buf_offset,
						   HAMMER_BUFSIZE, 0, &error);
			if (buffer) {
				KKASSERT(error == 0);
				TAILQ_INSERT_TAIL(&buffer->node_list, node, entry);
				node->buffer = buffer;
			}
		}
		if (error)
			goto failed;
		node->ondisk = (void *)((char *)buffer->ondisk +
				        (node->node_offset & HAMMER_BUFMASK));

		/*
		 * Check CRC.  NOTE: Neither flag is set and the CRC is not
		 * generated on new B-Tree nodes.
		 */
		if (isnew == 0 &&
		    (node->flags & HAMMER_NODE_CRCANY) == 0) {
			if (hammer_crc_test_btree(hmp->version, node->ondisk) == 0) {
				hdkprintf("CRC B-TREE NODE @ %016jx/%lu FAILED\n",
					(intmax_t)node->node_offset,
					sizeof(*node->ondisk));
				if (hammer_debug_critical)
					Debugger("CRC FAILED: B-TREE NODE");
				node->flags |= HAMMER_NODE_CRCBAD;
			} else {
				node->flags |= HAMMER_NODE_CRCGOOD;
			}
		}
		/*
		 * A node whose type or element count is impossible would
		 * send every B-Tree walk past elms[]; treat it like a CRC
		 * failure (EIO).
		 */
		if (isnew == 0 && (node->flags & HAMMER_NODE_CRCBAD) == 0 &&
		    !((node->ondisk->type == HAMMER_BTREE_TYPE_LEAF &&
		       hget32(node->ondisk->count) <= HAMMER_BTREE_LEAF_ELMS) ||
		      (node->ondisk->type == HAMMER_BTREE_TYPE_INTERNAL &&
		       hget32(node->ondisk->count) <= HAMMER_BTREE_INT_ELMS))) {
			hkprintf("B-Tree node %016jx: type %d, count %u\n",
				 (intmax_t)node->node_offset,
				 node->ondisk->type, hget32(node->ondisk->count));
			node->flags |= HAMMER_NODE_CRCBAD;
		}
	}
	if (node->flags & HAMMER_NODE_CRCBAD) {
		if (trans->flags & HAMMER_TRANSF_CRCDOM)
			error = EDOM;
		else
			error = EIO;
	}
failed:
	if (error) {
		_hammer_rel_node(node, 1);
	} else {
		hammer_ref_interlock_done(&node->lock);
	}
	return (error);
}

/*
 * Safely reference a node, interlock against flushes via the IO subsystem.
 */
hammer_node_t
hammer_ref_node_safe(hammer_transaction_t trans, hammer_node_cache_t cache,
		     int *errorp)
{
	hammer_node_t node;
	int doload;

	node = cache->node;
	if (node != NULL) {
		doload = hammer_ref_interlock(&node->lock);
		if (doload) {
			*errorp = hammer_load_node(trans, node, 0);
			if (*errorp)
				node = NULL;
		} else {
			KKASSERT(node->ondisk);
			if (node->flags & HAMMER_NODE_CRCBAD) {
				if (trans->flags & HAMMER_TRANSF_CRCDOM)
					*errorp = EDOM;
				else
					*errorp = EIO;
				_hammer_rel_node(node, 0);
				node = NULL;
			} else {
				*errorp = 0;
			}
		}
	} else {
		*errorp = ENOENT;
	}
	return(node);
}

/*
 * Release a hammer_node.  On the last release the node dereferences
 * its underlying buffer and may or may not be destroyed.
 *
 * If locked is non-zero the passed node has been interlocked by the
 * caller and we are in the failure/unload path, otherwise it has not and
 * we are doing a normal release.
 *
 * This function will dispose of the interlock and the reference.
 * On return the node pointer is stale.
 */
void
_hammer_rel_node(hammer_node_t node, int locked)
{
	hammer_buffer_t buffer;

	/*
	 * Deref the node.  If this isn't the 1->0 transition we're basically
	 * done.  If locked is non-zero this function will just deref the
	 * locked node and return 1, otherwise it will deref the locked
	 * node and either lock and return 1 on the 1->0 transition or
	 * not lock and return 0.
	 */
	if (hammer_rel_interlock(&node->lock, locked) == 0)
		return;

	/*
	 * Either locked was non-zero and we are interlocked, or the
	 * hammer_rel_interlock() call returned non-zero and we are
	 * interlocked.
	 *
	 * The ref-count must still be decremented if locked != 0 so
	 * the cleanup required still varies a bit.
	 *
	 * hammer_flush_node() when called with 1 or 2 will dispose of
	 * the lock and possible ref-count.
	 */
	if (node->ondisk == NULL) {
		hammer_flush_node(node, locked + 1);
		/* node is stale now */
		return;
	}

	/*
	 * Do not disassociate the node from the buffer if it represents
	 * a modified B-Tree node that still needs its crc to be generated.
	 */
	if (node->flags & HAMMER_NODE_NEEDSCRC) {
		hammer_rel_interlock_done(&node->lock, locked);
		return;
	}

	/*
	 * Do final cleanups and then either destroy the node and leave it
	 * passively cached.  The buffer reference is removed regardless.
	 */
	buffer = node->buffer;
	node->ondisk = NULL;

	if ((node->flags & HAMMER_NODE_FLUSH) == 0) {
		/*
		 * Normal release.
		 */
		hammer_rel_interlock_done(&node->lock, locked);
	} else {
		/*
		 * Destroy the node.
		 */
		hammer_flush_node(node, locked + 1);
		/* node is stale */

	}
	hammer_rel_buffer(buffer, 0);
}

void
hammer_rel_node(hammer_node_t node)
{
	_hammer_rel_node(node, 0);
}

/*
 * Free space on-media associated with a B-Tree node.
 */
void
hammer_delete_node(hammer_transaction_t trans, hammer_node_t node)
{
	KKASSERT((node->flags & HAMMER_NODE_DELETED) == 0);
	node->flags |= HAMMER_NODE_DELETED;
	hammer_blockmap_free(trans, node->node_offset, sizeof(*node->ondisk));
}

/*
 * Passively cache a referenced hammer_node.  The caller may release
 * the node on return.
 */
void
hammer_cache_node(hammer_node_cache_t cache, hammer_node_t node)
{
	/*
	 * If the node doesn't exist, or is being deleted, don't cache it!
	 *
	 * The node can only ever be NULL in the I/O failure path.
	 */
	if (node == NULL || (node->flags & HAMMER_NODE_DELETED))
		return;
	if (cache->node == node)
		return;
	while (cache->node)
		hammer_uncache_node(cache);
	if (node->flags & HAMMER_NODE_DELETED)
		return;
	cache->node = node;
	TAILQ_INSERT_TAIL(&node->cache_list, cache, entry);
}

void
hammer_uncache_node(hammer_node_cache_t cache)
{
	hammer_node_t node;

	if ((node = cache->node) != NULL) {
		TAILQ_REMOVE(&node->cache_list, cache, entry);
		cache->node = NULL;
		if (TAILQ_EMPTY(&node->cache_list))
			hammer_flush_node(node, 0);
	}
}

/*
 * Remove a node's cache references and destroy the node if it has no
 * other references or backing store.
 *
 * locked == 0	Normal unlocked operation
 * locked == 1	Call hammer_rel_interlock_done(..., 0);
 * locked == 2	Call hammer_rel_interlock_done(..., 1);
 *
 * XXX for now this isn't even close to being MPSAFE so the refs check
 *     is sufficient.
 */
void
hammer_flush_node(hammer_node_t node, int locked)
{
	hammer_node_cache_t cache;
	hammer_buffer_t buffer;
	hammer_mount_t hmp = node->hmp;
	int dofree;

	while ((cache = TAILQ_FIRST(&node->cache_list)) != NULL) {
		TAILQ_REMOVE(&node->cache_list, cache, entry);
		cache->node = NULL;
	}

	/*
	 * NOTE: refs is predisposed if another thread is blocking and
	 *	 will be larger than 0 in that case.  We aren't MPSAFE
	 *	 here.
	 */
	if (node->ondisk == NULL && hammer_norefs(&node->lock)) {
		KKASSERT((node->flags & HAMMER_NODE_NEEDSCRC) == 0);
		RB_REMOVE(hammer_nod_rb_tree, &node->hmp->rb_nods_root, node);
		if ((buffer = node->buffer) != NULL) {
			node->buffer = NULL;
			TAILQ_REMOVE(&buffer->node_list, node, entry);
			/* buffer is unreferenced because ondisk is NULL */
		}
		dofree = 1;
	} else {
		dofree = 0;
	}

	/*
	 * Deal with the interlock if locked == 1 or locked == 2.
	 */
	if (locked)
		hammer_rel_interlock_done(&node->lock, locked - 1);

	/*
	 * Destroy if requested
	 */
	if (dofree) {
		--hammer_count_nodes;
		kfree(node, hmp->m_misc);
	}
}

/*
 * Flush passively cached B-Tree nodes associated with this buffer.
 * This is only called when the buffer is about to be destroyed, so
 * none of the nodes should have any references.  The buffer is locked.
 *
 * We may be interlocked with the buffer.
 */
void
hammer_flush_buffer_nodes(hammer_buffer_t buffer)
{
	hammer_node_t node;

	while ((node = TAILQ_FIRST(&buffer->node_list)) != NULL) {
		KKASSERT(node->ondisk == NULL);
		KKASSERT((node->flags & HAMMER_NODE_NEEDSCRC) == 0);

		if (hammer_try_interlock_norefs(&node->lock)) {
			hammer_ref(&node->lock);
			node->flags |= HAMMER_NODE_FLUSH;
			_hammer_rel_node(node, 1);
		} else {
			KKASSERT(node->buffer != NULL);
			buffer = node->buffer;
			node->buffer = NULL;
			TAILQ_REMOVE(&buffer->node_list, node, entry);
			/* buffer is unreferenced because ondisk is NULL */
		}
	}
}


/************************************************************************
 *				ALLOCATORS				*
 ************************************************************************/

/*
 * Allocate a B-Tree node.
 */
hammer_node_t
hammer_alloc_btree(hammer_transaction_t trans, hammer_off_t hint, int *errorp)
{
	hammer_buffer_t buffer = NULL;
	hammer_node_t node = NULL;
	hammer_off_t node_offset;

	node_offset = hammer_blockmap_alloc(trans, HAMMER_ZONE_BTREE_INDEX,
					    sizeof(struct hammer_node_ondisk),
					    hint, errorp);
	if (*errorp == 0) {
		node = hammer_get_node(trans, node_offset, 1, errorp);
		hammer_modify_node_noundo(trans, node);
		bzero(node->ondisk, sizeof(*node->ondisk));
		hammer_modify_node_done(node);
	}
	if (buffer)
		hammer_rel_buffer(buffer, 0);
	return(node);
}

/*
 * Allocate data.  If the address of a data buffer is supplied then
 * any prior non-NULL *data_bufferp will be released and *data_bufferp
 * will be set to the related buffer.  The caller must release it when
 * finally done.  The initial *data_bufferp should be set to NULL by
 * the caller.
 *
 * The caller is responsible for making hammer_modify*() calls on the
 * *data_bufferp.
 */
void *
hammer_alloc_data(hammer_transaction_t trans, int32_t data_len,
		  uint16_t rec_type, hammer_off_t *data_offsetp,
		  hammer_buffer_t *data_bufferp,
		  hammer_off_t hint, int *errorp)
{
	void *data;
	int zone;

	/*
	 * Allocate data directly from blockmap.
	 */
	if (data_len) {
		switch(rec_type) {
		case HAMMER_RECTYPE_INODE:
		case HAMMER_RECTYPE_DIRENTRY:
		case HAMMER_RECTYPE_EXT:
		case HAMMER_RECTYPE_FIX:
		case HAMMER_RECTYPE_PFS:
		case HAMMER_RECTYPE_SNAPSHOT:
		case HAMMER_RECTYPE_CONFIG:
			zone = HAMMER_ZONE_META_INDEX;
			break;
		case HAMMER_RECTYPE_DATA:
		case HAMMER_RECTYPE_DB:
			/*
			 * Only mirror-write comes here.
			 * Regular allocation path uses blockmap reservation.
			 */
			zone = hammer_data_zone_index(data_len);
			if (zone == HAMMER_ZONE_LARGE_DATA_INDEX) {
				/* round up */
				data_len = HAMMER_BUFSIZE_DOALIGN(data_len);
			}
			break;
		default:
			hpanic("rec_type %04x unknown", rec_type);
			zone = HAMMER_ZONE_UNAVAIL_INDEX; /* NOT REACHED */
			break;
		}
		*data_offsetp = hammer_blockmap_alloc(trans, zone, data_len,
						      hint, errorp);
	} else {
		*data_offsetp = 0;
	}

	data = NULL;
	if (*errorp == 0 && data_bufferp && data_len)
		data = hammer_bread_ext(trans->hmp, *data_offsetp, data_len,
					errorp, data_bufferp);
	return(data);
}

#if 0 /* write path: sync and the flusher queue return in Phase 2 */
/*
 * Sync dirty buffers to the media and clean-up any loose ends.
 *
 * These functions do not start the flusher going, they simply
 * queue everything up to the flusher.
 */
static int hammer_sync_scan2(struct mount *mp, struct vnode *vp, void *data);

struct hammer_sync_info {
	int error;
};

int
hammer_queue_inodes_flusher(hammer_mount_t hmp, int waitfor)
{
	struct hammer_sync_info info;

	info.error = 0;
	if (waitfor == MNT_WAIT) {
		vsyncscan(hmp->mp, VMSC_GETVP | VMSC_ONEPASS,
			  hammer_sync_scan2, &info);
	} else {
		vsyncscan(hmp->mp, VMSC_GETVP | VMSC_ONEPASS | VMSC_NOWAIT,
			  hammer_sync_scan2, &info);
	}
	return(info.error);
}

/*
 * Filesystem sync.  If doing a synchronous sync make a second pass on
 * the vnodes in case any were already flushing during the first pass,
 * and activate the flusher twice (the second time brings the UNDO FIFO's
 * start position up to the end position after the first call).
 *
 * If doing a lazy sync make just one pass on the vnode list, ignoring
 * any new vnodes added to the list while the sync is in progress.
 */
int
hammer_sync_hmp(hammer_mount_t hmp, int waitfor)
{
	struct hammer_sync_info info;
	int flags;

	flags = VMSC_GETVP;
	if (waitfor & MNT_LAZY)
		flags |= VMSC_ONEPASS;

	info.error = 0;
	vsyncscan(hmp->mp, flags | VMSC_NOWAIT, hammer_sync_scan2, &info);

	if (info.error == 0 && (waitfor & MNT_WAIT)) {
		vsyncscan(hmp->mp, flags, hammer_sync_scan2, &info);
	}
        if (waitfor == MNT_WAIT) {
                hammer_flusher_sync(hmp);
                hammer_flusher_sync(hmp);
	} else {
                hammer_flusher_async(hmp, NULL);
                hammer_flusher_async(hmp, NULL);
	}
	return(info.error);
}

static int
hammer_sync_scan2(struct mount *mp, struct vnode *vp, void *data)
{
	struct hammer_sync_info *info = data;
	hammer_inode_t ip;
	int error;

	ip = VTOI(vp);
	if (ip == NULL)
		return(0);
	if (vp->v_type == VNON || vp->v_type == VBAD) {
		vclrisdirty(vp);
		return(0);
	}
	if ((ip->flags & HAMMER_INODE_MODMASK) == 0 &&
	    RB_EMPTY(&vp->v_rbdirty_tree))
	{
		vclrisdirty(vp);
		return(0);
	}
	error = VOP_FSYNC(vp, MNT_NOWAIT, 0);
	if (error)
		info->error = error;
	return(0);
}
#endif /* write path */
