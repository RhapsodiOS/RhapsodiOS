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
 * HAMMER buffer I/O for Rhapsody.
 *
 * Upstream hammer_io.c drives DragonFly's buffer cache with 16 KB and
 * 64 KB buffers and dependency callbacks.  Rhapsody's MAXBSIZE is 8 KB, so
 * each hammer_io here owns io->bytes of kernel memory (io->data), filled
 * from the device in MAXBSIZE pieces (hammer_dev_read).  A clean io drops
 * its memory when HAMMER releases it; repeated reads are served by the
 * device's own buffer cache.
 *
 * A modified io keeps its memory, and stays on its mod_root list, until
 * hammer_io_flush() writes it.  Upstream let the kernel write dirty data
 * and UNDO buffers at any time; here only the flusher writes, so dirty
 * ios of every type count against hammer_limit_dirtybufspace.
 * hammer_io_flush() writes synchronously (hammer_io_write_sync), so the
 * flusher's stage order is the on-disk order and no write is ever left
 * running.
 */
#include "hammer.h"

static void hammer_io_modify(hammer_io_t io, int count);
static void hammer_io_set_modlist(hammer_io_t io);

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
 * Wait for any physical IO to complete.  Writes are synchronous, so this
 * only waits when another thread slept in the middle of one.
 */
void
hammer_io_wait(hammer_io_t io)
{
	while (io->running) {
		io->waiting = 1;
		tsleep(io, 0, "hmrflw", hz);
	}
}

/*
 * Wait for all currently queued HAMMER-initiated I/Os to complete.
 */
void
hammer_io_wait_all(hammer_mount_t hmp, const char *ident, int doflush)
{
	while (!TAILQ_EMPTY(&hmp->iorun_list))
		tsleep(&hmp->iorun_list, 0, ident, hz);
	if (doflush)
		hammer_io_flush_sync(hmp);
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

/* Upstream's swapcache hint; there is no swapcache here. */
void
hammer_io_notmeta(hammer_buffer_t buffer)
{
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

/*
 * Like hammer_io_read() but supplies a zeroed buffer instead, and marks
 * the io modified (without a modify_refs count).  Must be called with the
 * io exclusively locked.
 */
int
hammer_io_new(struct vnode *devvp, hammer_io_t io)
{
	if (io->data == NULL)
		io->data = kmalloc(io->bytes, M_HAMMER, M_WAITOK | M_ZERO);
	else
		bzero(io->data, io->bytes);
	io->released = 0;
	hammer_io_modify(io, 0);
	return(0);
}

void
hammer_io_advance(hammer_io_t io)
{
}

/*
 * Nothing caches a device buffer HAMMER does not own, and every device
 * access uses the same 8 KB blocks, so there is never a stale alias to
 * invalidate.
 */
int
hammer_io_inval(hammer_volume_t volume, hammer_off_t zone2_offset)
{
	return(0);
}

/*
 * Called on the last reference to a hammer structure.  A clean io drops
 * its data; a modified one keeps it for the flusher (flush asks for the
 * write now).  The return value is the buffer upstream handed back for
 * brelse(); there is none here.
 */
struct buf *
hammer_io_release(hammer_io_t io, int flush)
{
	if (io->data == NULL)
		return(NULL);
	if (io->modified && flush)
		hammer_io_flush(io, 0);
	if (io->modified || io->running) {
		io->released = 1;
		return(NULL);
	}
	kfree(io->data, M_HAMMER);
	io->data = NULL;
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

/*
 * Write a modified io to the device and wait for it.  Called with a
 * locked io or an io reference, only when HAMMER believes the write is
 * safe.  The modified bit is cleared and delayed B-Tree CRCs finalized
 * before the write, as upstream does before bawrite().
 */
void
hammer_io_flush(hammer_io_t io, int reclaim)
{
	hammer_mount_t hmp;
	int error;

	if (io->modified == 0)
		return;

	KKASSERT(io->data);
	KKASSERT(io->modify_refs <= 0);
	hmp = io->hmp;
	if (reclaim)
		io->reclaim = 1;

	hammer_ref(&io->lock);
	hammer_io_clear_modify(io, 0);
	hammer_rel(&io->lock);

	if (hammer_debug_io & 0x0002)
		hdkprintf("%016jx\n", (intmax_t)io->offset);

	io->running = 1;
	hmp->io_running_space += io->bytes;
	hammer_count_io_running_write += io->bytes;
	TAILQ_INSERT_TAIL(&hmp->iorun_list, io, iorun_entry);

	error = hammer_io_write_sync(io->volume->devvp, io->offset,
				     io->data, io->bytes);

	/*
	 * Completion (upstream's hammer_io_complete).  Once a critical
	 * error is flagged the UNDO FIFO is not updated again, so crash
	 * recovery still finds a consistent filesystem.  A failed UNDO
	 * buffer can be thrown away; a failed meta-data or data buffer is
	 * kept referenced so it is not reused.
	 */
	if (error) {
		hammer_critical_error(hmp, NULL, error,
				      "while flushing meta-data");
		if (io->type != HAMMER_IOTYPE_UNDO_BUFFER &&
		    io->ioerror == 0) {
			io->ioerror = 1;
			hammer_ref(&io->lock);
		}
	}
	hammer_stats_disk_write += io->bytes;
	hammer_count_io_running_write -= io->bytes;
	hmp->io_running_space -= io->bytes;
	KKASSERT(hmp->io_running_space >= 0);
	io->running = 0;
	TAILQ_REMOVE(&hmp->iorun_list, io, iorun_entry);
	if (TAILQ_EMPTY(&hmp->iorun_list))
		wakeup(&hmp->iorun_list);
	if (io->waiting) {
		io->waiting = 0;
		wakeup(io);
	}
	io->volume->vol_flags |= HAMMER_VOLF_NEEDFLUSH;
}

/************************************************************************
 *				BUFFER DIRTYING				*
 ************************************************************************
 *
 * The caller must call hammer_modify_*() on a referenced HAMMER structure
 * prior to modifying its on-disk data.
 */

/*
 * Mark a HAMMER structure as undergoing modification.  It stays in
 * memory until the flusher writes it.  The referenced io prevents races.
 */
static void
hammer_io_modify(hammer_io_t io, int count)
{
	/*
	 * io->modify_refs must be >= 0
	 */
	while (io->modify_refs < 0) {
		io->waitmod = 1;
		tsleep(io, 0, "hmrmod", 0);
	}

	KKASSERT(hammer_isactive(&io->lock) && io->data != NULL);
	io->modify_refs += count;
	if (io->modified && io->released == 0)
		return;

	hammer_lock_ex(&io->lock);
	io->released = 0;
	if (io->modified == 0) {
		hammer_io_set_modlist(io);
		io->modified = 1;
	}
	hammer_unlock(&io->lock);
}

static __inline
void
hammer_io_modify_done(hammer_io_t io)
{
	KKASSERT(io->modify_refs > 0);
	--io->modify_refs;
	if (io->modify_refs == 0 && io->waitmod) {
		io->waitmod = 0;
		wakeup(io);
	}
}

/*
 * The write interlock blocks other threads trying to modify a buffer
 * (they block in hammer_io_modify()) after us, or blocks us while other
 * threads are in the middle of modifying a buffer.
 */
void
hammer_io_write_interlock(hammer_io_t io)
{
	while (io->modify_refs != 0) {
		io->waitmod = 1;
		tsleep(io, 0, "hmrmod", 0);
	}
	io->modify_refs = -1;
}

void
hammer_io_done_interlock(hammer_io_t io)
{
	KKASSERT(io->modify_refs == -1);
	io->modify_refs = 0;
	if (io->waitmod) {
		io->waitmod = 0;
		wakeup(io);
	}
}

/*
 * Caller intends to modify a volume's ondisk structure.
 *
 * This is only allowed if we are the flusher or we have a ref on the
 * sync_lock.
 */
void
hammer_modify_volume(hammer_transaction_t trans, hammer_volume_t volume,
		     void *base, int len)
{
	KKASSERT (trans == NULL || trans->sync_lock_refs > 0);

	hammer_io_modify(&volume->io, 1);
	if (len) {
		intptr_t rel_offset = (intptr_t)base - (intptr_t)volume->ondisk;
		KKASSERT((rel_offset & ~(intptr_t)HAMMER_BUFMASK) == 0);
		hammer_generate_undo(trans,
			 HAMMER_ENCODE_RAW_VOLUME(volume->vol_no, rel_offset),
			 base, len);
	}
}

/*
 * Caller intends to modify a buffer's ondisk structure.
 *
 * This is only allowed if we are the flusher or we have a ref on the
 * sync_lock.
 */
void
hammer_modify_buffer(hammer_transaction_t trans, hammer_buffer_t buffer,
		     void *base, int len)
{
	KKASSERT (trans == NULL || trans->sync_lock_refs > 0);

	hammer_io_modify(&buffer->io, 1);
	if (len) {
		intptr_t rel_offset = (intptr_t)base - (intptr_t)buffer->ondisk;
		KKASSERT((rel_offset & ~(intptr_t)HAMMER_BUFMASK) == 0);
		hammer_generate_undo(trans,
				     buffer->zone2_offset + rel_offset,
				     base, len);
	}
}

void
hammer_modify_volume_done(hammer_volume_t volume)
{
	hammer_io_modify_done(&volume->io);
}

void
hammer_modify_buffer_done(hammer_buffer_t buffer)
{
	hammer_io_modify_done(&buffer->io);
}

/*
 * Mark an entity as not being dirty any more and finalize any
 * delayed adjustments to the buffer.
 *
 * Delayed adjustments are an important performance enhancement, allowing
 * us to avoid recalculating B-Tree node CRCs over and over again when
 * making bulk-modifications to the B-Tree.
 *
 * If inval is non-zero delayed adjustments are ignored.
 *
 * This routine may dereference related btree nodes and cause the
 * buffer to be dereferenced.  The caller must own a reference on io.
 */
void
hammer_io_clear_modify(hammer_io_t io, int inval)
{
	hammer_mount_t hmp;

	if (io->modified == 0)
		return;
	hmp = io->hmp;

	/*
	 * Take us off the mod-list and clear the modified bit.
	 */
	KKASSERT(io->mod_root != NULL);
	hmp->locked_dirty_space -= io->bytes;
	hammer_count_dirtybufspace -= io->bytes;
	RB_REMOVE(hammer_mod_rb_tree, io->mod_root, io);
	io->mod_root = NULL;
	io->modified = 0;

	/*
	 * If this bit is not set there are no delayed adjustments.
	 */
	if (io->gencrc == 0)
		return;
	io->gencrc = 0;

	/*
	 * Finalize requested CRCs.  The NEEDSCRC flag also holds a reference
	 * on the node (& underlying buffer).  Release the node after clearing
	 * the flag.
	 */
	if (io->type == HAMMER_IOTYPE_META_BUFFER) {
		hammer_buffer_t buffer = HAMMER_ITOB(io);
		hammer_node_t node;

restart:
		TAILQ_FOREACH(node, &buffer->node_list, entry) {
			if ((node->flags & HAMMER_NODE_NEEDSCRC) == 0)
				continue;
			node->flags &= ~HAMMER_NODE_NEEDSCRC;
			KKASSERT(node->ondisk);
			if (inval == 0)
				hammer_crc_set_btree(hmp->version, node->ondisk);
			hammer_rel_node(node);
			goto restart;
		}
	}
	/* caller must still have ref on io */
	KKASSERT(hammer_isactive(&io->lock));
}

/*
 * Clear the IO's modify list.  Even though the IO is no longer modified
 * it may still be on the lose_root.  This routine is called just before
 * the governing hammer_buffer is destroyed.
 */
void
hammer_io_clear_modlist(hammer_io_t io)
{
	KKASSERT(io->modified == 0);
	if (io->mod_root) {
		KKASSERT(io->mod_root == &io->hmp->lose_root);
		RB_REMOVE(hammer_mod_rb_tree, io->mod_root, io);
		io->mod_root = NULL;
	}
}

static void
hammer_io_set_modlist(hammer_io_t io)
{
	hammer_mount_t hmp = io->hmp;

	KKASSERT(io->mod_root == NULL);

	switch(io->type) {
	case HAMMER_IOTYPE_VOLUME:
		io->mod_root = &hmp->volu_root;
		break;
	case HAMMER_IOTYPE_META_BUFFER:
		io->mod_root = &hmp->meta_root;
		break;
	case HAMMER_IOTYPE_UNDO_BUFFER:
		io->mod_root = &hmp->undo_root;
		break;
	case HAMMER_IOTYPE_DATA_BUFFER:
		io->mod_root = &hmp->data_root;
		break;
	case HAMMER_IOTYPE_DUMMY:
		hpanic("bad io type");
		break; /* NOT REACHED */
	}
	hmp->locked_dirty_space += io->bytes;
	hammer_count_dirtybufspace += io->bytes;
	if (RB_INSERT(hammer_mod_rb_tree, io->mod_root, io)) {
		hpanic("duplicate entry @ %d:%015jx",
			io->volume->vol_no, (intmax_t)io->offset);
		/* NOT REACHED */
	}
}

/*
 * Store a bulk data record's bytes (DATA, data_len of them, from
 * hammer_ip_add_bulk) at its reserved offset and add the record to its
 * inode.  Upstream wrote large records straight to the device from the
 * vnode's buffer; here every size goes through a HAMMER buffer, which the
 * flusher writes with the other dirty data.  A record that fills a whole
 * large-data buffer does not read the old contents first.  On error the
 * record is thrown away.
 */
int
hammer_io_direct_write(hammer_mount_t hmp, hammer_record_t record,
		       const void *data)
{
	hammer_buffer_t buffer = NULL;
	hammer_off_t off = hget64(record->leaf.data_offset);
	int bytes = (int)hget32(record->leaf.data_len);
	void *ptr;
	int error;

	KKASSERT(hammer_is_zone_record(off));
	if ((off & HAMMER_XBUFMASK64) == 0 && bytes == HAMMER_XBUFSIZE)
		ptr = hammer_bnew_ext(hmp, off, bytes, &error, &buffer);
	else
		ptr = hammer_bread_ext(hmp, off, bytes, &error, &buffer);
	if (error == 0) {
		hammer_io_modify(&buffer->io, 1);
		bcopy(data, ptr, bytes);
		hammer_io_modify_done(&buffer->io);
		hammer_ip_replace_bulk(hmp, record);
	} else {
		hdkprintf("failed @ %016jx\n", (intmax_t)off);
		record->flags |= HAMMER_RECF_DELETED_FE;
		hammer_rel_mem_record(record);
	}
	if (buffer)
		hammer_rel_buffer(buffer, 0);
	return(error);
}

/*
 * File data goes through HAMMER buffers (hammer_io_direct_write above),
 * so a record never has a direct write to wait for.  Upstream also
 * removed buffer aliases of the record's data here; that is kept.
 */
void
hammer_io_direct_wait(hammer_record_t record)
{
	hammer_mount_t hmp = record->ip->hmp;

	KKASSERT((record->gflags & HAMMER_RECG_DIRECT_IO) == 0);
	if (record->gflags & HAMMER_RECG_DIRECT_INVAL) {
		KKASSERT(hget64(record->leaf.data_offset));
		hammer_del_buffers(hmp, hget64(record->leaf.data_offset),
				   record->zone2_offset,
				   hget32(record->leaf.data_len), 1);
		record->gflags &= ~HAMMER_RECG_DIRECT_INVAL;
	}
}

/*
 * Upstream issues a device cache flush here.  Rhapsody's disk drivers
 * offer none; a synchronous write completes when the device has it.
 */
void
hammer_io_flush_sync(hammer_mount_t hmp)
{
	hammer_volume_t volume;

	RB_FOREACH(volume, hammer_vol_rb_tree, &hmp->rb_vols_root)
		volume->vol_flags &= ~HAMMER_VOLF_NEEDFLUSH;
}

/* Writes are synchronous, so no backlog builds up. */
void
hammer_io_limit_backlog(hammer_mount_t hmp)
{
}
