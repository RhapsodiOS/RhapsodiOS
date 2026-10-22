/*
 * Copyright (c) 2007-2008 The DragonFly Project.  All rights reserved.
 * Copyright (c) 2026 RhapsodiOS.  All rights reserved.
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
 * HAMMER buffer I/O for Rhapsody, read-only (Phase 1).
 *
 * Upstream hammer_io.c drives DragonFly's buffer cache with 16 KB and
 * 64 KB buffers and dependency callbacks.  Rhapsody's MAXBSIZE is 8 KB, so
 * each hammer_io here owns io->bytes of kernel memory and fills it from
 * the device in MAXBSIZE pieces (hammer_dev_read).  The memory lives while
 * the hammer_io holds data and is freed when HAMMER releases it; repeated
 * reads are served by the device's own buffer cache.
 *
 * Nothing may be modified in Phase 1: every write-side entry point panics.
 * The upstream implementation is in git history for the Phase 2 write path.
 */
#include "hammer.h"

static int
hammer_mod_rb_compare(hammer_io_t io1, hammer_io_t io2)
{
	hammer_off_t io1_offset;
	hammer_off_t io2_offset;

	io1_offset = HAMMER_ENCODE(0, io1->volume->vol_no, io1->offset);
	io2_offset = HAMMER_ENCODE(0, io2->volume->vol_no, io2->offset);

	if (io1_offset < io2_offset)
		return(-1);
	if (io1_offset > io2_offset)
		return(1);
	return(0);
}

RB_GENERATE(hammer_mod_rb_tree, hammer_io, rb_node, hammer_mod_rb_compare);

void
hammer_io_init(hammer_io_t io, hammer_volume_t volume, hammer_io_type_t type)
{
	io->volume = volume;
	io->hmp = volume->io.hmp;
	io->type = type;
}

hammer_io_type_t
hammer_zone_to_iotype(int zone)
{
	switch(zone) {
	case HAMMER_ZONE_RAW_VOLUME_INDEX:
		return(HAMMER_IOTYPE_VOLUME);
	case HAMMER_ZONE_RAW_BUFFER_INDEX:
	case HAMMER_ZONE_FREEMAP_INDEX:
	case HAMMER_ZONE_BTREE_INDEX:
	case HAMMER_ZONE_META_INDEX:
		return(HAMMER_IOTYPE_META_BUFFER);
	case HAMMER_ZONE_UNDO_INDEX:
		return(HAMMER_IOTYPE_UNDO_BUFFER);
	case HAMMER_ZONE_LARGE_DATA_INDEX:
	case HAMMER_ZONE_SMALL_DATA_INDEX:
		return(HAMMER_IOTYPE_DATA_BUFFER);
	default:
		return(HAMMER_IOTYPE_DUMMY);
	}
}

/*
 * Load io->data.  The io must be exclusively locked by the caller.
 * limit (an upstream clustering hint) is ignored.
 */
int
hammer_io_read(struct vnode *devvp, hammer_io_t io, int limit)
{
	int error;

	if (io->data)
		return(0);
	io->data = kmalloc(io->bytes, M_HAMMER, M_WAITOK);
	error = hammer_dev_read(devvp, io->offset, io->data, io->bytes);
	hammer_stats_disk_read += io->bytes;
	if (error) {
		kfree(io->data, M_HAMMER);
		io->data = NULL;
	}
	KKASSERT(io->modified == 0);
	io->released = 0;
	return(error);
}

int
hammer_io_new(struct vnode *devvp, hammer_io_t io)
{
	hpanic("hammer_io_new: read-only in this release");
	return(EROFS);
}

void
hammer_io_advance(hammer_io_t io)
{
}

/*
 * Called on the last reference to a hammer structure: drop its data.
 * Nothing is ever modified, so nothing needs writing.  The return value
 * is the buffer upstream handed back for brelse(); there is none here.
 */
struct buf *
hammer_io_release(hammer_io_t io, int flush)
{
	KKASSERT(io->modified == 0);
	if (io->data) {
		kfree(io->data, M_HAMMER);
		io->data = NULL;
	}
	switch(io->type) {
	case HAMMER_IOTYPE_VOLUME:
		HAMMER_ITOV(io)->ondisk = NULL;
		break;
	case HAMMER_IOTYPE_META_BUFFER:
	case HAMMER_IOTYPE_UNDO_BUFFER:
	case HAMMER_IOTYPE_DATA_BUFFER:
		HAMMER_ITOB(io)->ondisk = NULL;
		break;
	case HAMMER_IOTYPE_DUMMY:
		break;
	}
	io->released = 1;
	io->reclaim = 0;
	return(NULL);
}

void
hammer_io_flush(hammer_io_t io, int reclaim)
{
	KKASSERT(io->modified == 0);
}

void
hammer_io_wait(hammer_io_t io)
{
	KKASSERT(io->running == 0);
}

void
hammer_io_waitdep(hammer_io_t io)
{
}

void
hammer_io_wait_all(hammer_mount_t hmp, const char *ident, int doflush)
{
}

void
hammer_io_flush_sync(hammer_mount_t hmp)
{
}

void
hammer_io_clear_error(hammer_io_t io)
{
	if (io->ioerror) {
		io->ioerror = 0;
		hammer_rel(&io->lock);
		KKASSERT(hammer_isactive(&io->lock));
	}
}

void
hammer_io_clear_error_noassert(hammer_io_t io)
{
	if (io->ioerror) {
		io->ioerror = 0;
		hammer_rel(&io->lock);
	}
}

void
hammer_io_clear_modify(hammer_io_t io, int inval)
{
	KKASSERT(io->modified == 0);
}

void
hammer_io_clear_modlist(hammer_io_t io)
{
	KKASSERT(io->mod_root == NULL);
}

void
hammer_io_notmeta(hammer_buffer_t buffer)
{
}

void
hammer_io_limit_backlog(hammer_mount_t hmp)
{
}

/*
 * The B-tree scan calls this on every step; a read-only mount has no
 * loose (written-back) buffers to clean.  The real one is in
 * hammer_flusher.c (Phase 2).
 */
void
hammer_flusher_clean_loose_ios(hammer_mount_t hmp)
{
}

/*
 * Nothing caches a device buffer HAMMER does not own, so there is never a
 * stale alias to invalidate.
 */
int
hammer_io_inval(hammer_volume_t volume, hammer_off_t zone2_offset)
{
	return(0);
}

void
hammer_io_write_interlock(hammer_io_t io)
{
	hpanic("hammer_io_write_interlock: read-only in this release");
}

void
hammer_io_done_interlock(hammer_io_t io)
{
	hpanic("hammer_io_done_interlock: read-only in this release");
}

void
hammer_modify_volume(hammer_transaction_t trans, hammer_volume_t volume,
		     void *base, int len)
{
	hpanic("hammer_modify_volume: read-only in this release");
}

void
hammer_modify_buffer(hammer_transaction_t trans, hammer_buffer_t buffer,
		     void *base, int len)
{
	hpanic("hammer_modify_buffer: read-only in this release");
}

void
hammer_modify_volume_done(hammer_volume_t volume)
{
	hpanic("hammer_modify_volume_done: read-only in this release");
}

void
hammer_modify_buffer_done(hammer_buffer_t buffer)
{
	hpanic("hammer_modify_buffer_done: read-only in this release");
}
