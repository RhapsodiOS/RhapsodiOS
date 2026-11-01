/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */

/* 
 * Copyright (c) 1990 NeXT, Inc.
 *
 *  History:
 *
 *	6-Aug-90: Brian Pinkerton at NeXT
 *		created
 */
 

#import <mach_xp.h>

#import <sys/types.h>
#import <sys/param.h>

#import <mach/vm_param.h>
#import <vm/vm_object.h>
#import <vm/vm_map.h>
#import <vm/vm_page.h>
#import <mach/vm_statistics.h>

#import <mach/boolean.h>
#import <mach/kern_return.h>
#import <kern/task.h>
#import <kern/kalloc.h>

#import <mach/mach_types.h>	/* to get vm_address_t */

#import <sys/proc.h>
#import <sys/vnode.h>
#import <vm/vnode_pager.h>


static kern_return_t map_push_range(vm_map_t map, vm_offset_t start, vm_offset_t end);
	
static kern_return_t object_push(vm_object_t object, vm_offset_t object_start, vm_offset_t object_end);
	
enum pageout_outcome { PAGEOUT_SUCCESS, PAGEOUT_ERROR, PAGEOUT_RERUN };

/*
 * Push all pages to disk.
 */
kern_return_t
vm_synchronize(
	vm_map_t	task_map,
	vm_address_t	vmaddr,
	vm_size_t	vmsize)
{
	kern_return_t	result;

	if (!task_map)
		return KERN_FAILURE;

	if (vmsize == 0)
		vmsize = task_map->max_offset - task_map->min_offset;

	if (vmaddr == 0)
		vmaddr = task_map->min_offset;

	result = map_push_range(task_map, vmaddr, vmaddr+vmsize);
	
	return result;
}


/*
 * Push a range of pages in a map.
 */
static kern_return_t
map_push_range(
	vm_map_t	map,
	vm_offset_t	start,
	vm_offset_t	end)
{
	vm_map_entry_t	entry;
	vm_object_t	object;
	vm_offset_t	tstart, tend;
	int		offset;
	kern_return_t	rtn, realRtn = KERN_SUCCESS;
	vm_pager_t	pager;
	struct vnode	*vp;
	struct proc	*p = current_proc();

	vm_map_lock_read(map);
	/*
	 * Push all the pages in this map.
	 */
	for (  entry = vm_map_first_entry(map)
	     ; entry != vm_map_to_entry(map)
	     ; entry = entry->vme_next)
	{
		if (entry->vme_start >= end || entry->vme_end <= start)
			continue;

		tstart = (entry->vme_start > start) ? entry->vme_start : start;
		tend = (entry->vme_end > end) ? end : entry->vme_end;
		offset = entry->offset + tstart - entry->vme_start;
		if (entry->is_a_map || entry->is_sub_map) {
			/*
			 * Recurse over this sub-map, at the addresses the
			 * range has inside it.
			 */
			rtn = map_push_range(entry->object.sub_map,
					offset, offset + tend - tstart);
		} else {
			/*
			 * Push the pages we can see in this object chain.
			 */
			object = entry->object.vm_object;
			if (object != VM_OBJECT_NULL &&
			    (pager = object->pager) != vm_pager_null &&
			    !pager->is_device &&
			    !((vnode_pager_t) pager)->vs_swapfile) {
				/*
				 * A file's object: hold its vnode lock across
				 * the push, so vnode_pageout's no-wait lock
				 * recurses instead of failing against a writer.
				 * Take it before the map lock and before any
				 * page is busy, as a writer does; our object
				 * reference keeps the pager's vnode.
				 */
				vp = ((vnode_pager_t) pager)->vs_vp;
				vm_object_reference(object);
				vm_map_unlock_read(map);
				vn_lock(vp, LK_EXCLUSIVE | LK_RETRY |
				    LK_CANRECURSE, p);
				rtn = object_push(object, offset,
				    offset + tend - tstart);
				VOP_UNLOCK(vp, 0, p);
				vm_object_deallocate(object);
				vm_map_lock_read(map);
				/* the map may have changed: go on after tend */
				(void) vm_map_lookup_entry(map, tend - 1, &entry);
			} else
				rtn = object_push(object, offset,
				    offset + tend - tstart);
		}
		if (rtn != KERN_SUCCESS)
			realRtn = KERN_FAILURE;
	}
	vm_map_unlock(map);

	return realRtn;
}


/*
 *  Page out a page belonging to the given object.  The object must be locked.
 */
static enum pageout_outcome
vm_pageout_page(vm_object_t object, vm_page_t m)
{
	enum pageout_outcome pageout_succeeded;
	vm_pager_t pager = object->pager;
	
	vm_page_lock_queues();
	if (m->clean && !pmap_is_modified(VM_PAGE_TO_PHYS(m))) {
		vm_page_unlock_queues();
		return PAGEOUT_SUCCESS;
	}

	/*
	 *  A page being paged in has nothing to push, and its pagein may be
	 *  waiting for the vnode lock our caller holds.
	 */
	if (m->nfspagereq) {
		vm_page_unlock_queues();
		return PAGEOUT_SUCCESS;
	}

	/*
	 *  If the page is already busy, sleep on it...
	 */
	while (m->busy) {
		vm_page_unlock_queues();
		PAGE_ASSERT_WAIT(m, FALSE);
		vm_object_unlock(object);
		thread_block();
		vm_object_lock(object);
		return PAGEOUT_RERUN;
	}
	
	/*
	 *  Memory no pager has taken yet (fresh anonymous or copied pages)
	 *  has nowhere to go; leave it as it is.
	 */
	if (pager == vm_pager_null) {
		vm_page_unlock_queues();
		return PAGEOUT_SUCCESS;
	}

	vm_object_paging_begin(object);
	
	m->busy = TRUE;
	if (m->inactive)
		vm_page_activate(m);
	vm_page_deactivate(m);
	
	pmap_remove_all(VM_PAGE_TO_PHYS(m));
	vm_stat.pageouts++;

	vm_page_unlock_queues();
	vm_object_unlock(object);
	
	pageout_succeeded = PAGEOUT_ERROR;
	if (vm_pager_put(pager, m) == PAGER_SUCCESS) {
		pageout_succeeded = PAGEOUT_SUCCESS;
	}

	vm_object_lock(object);
	vm_page_lock_queues();
	m->busy = FALSE;
	PAGE_WAKEUP(m);
	
	vm_object_paging_end(object);
	vm_page_unlock_queues();
	
	return pageout_succeeded;
}


/*
 *  Count resident pages in this object and all shadow objects over the
 *  specified address range.
 *
 *  If we encounter an error, we'll attempt to push the rest of the pages,
 *  and return an error for the whole object.
 *
 *  If we encounter a locked page, then we'll restart
 */
static kern_return_t
object_push(vm_object_t object, vm_offset_t object_start, vm_offset_t object_end)
{
	vm_object_t	shadow;
	vm_page_t	page;
	vm_size_t	object_size;
	int		flags;
	int		allPageoutsSucceeded = TRUE;
	kern_return_t	rtn = FALSE;

	if (object == VM_OBJECT_NULL)
		return KERN_SUCCESS;

	vm_object_lock(object);

retry:
	for (  page = (vm_page_t) queue_first(&object->memq)
	     ; !queue_end(&object->memq, (queue_entry_t) page)
	     ; page = (vm_page_t) queue_next(&page->listq))
	{
		/*
		 * If this page isn't actually referenced from this
		 * entry, then forget it.
		 */
		if (page->offset < object_start || page->offset >= object_end)
			continue;

		/*
		 *  Push this page.  If we fail, retry on the whole object.
		 */
		switch (vm_pageout_page(object, page)) {
			case PAGEOUT_RERUN:
				goto retry;
			case PAGEOUT_ERROR:
				allPageoutsSucceeded = FALSE;
			case PAGEOUT_SUCCESS:
			default:
				break;
		}
	}

	/*
	 * Recurse over shadow objects.
	 */
	object_size = object_end - object_start;
	if (object->size && object_end - object_start > object->size)
		object_size = object->size;
	object_start += object->shadow_offset;
	object_end = object_start + object_size;

	if (object_push(object->shadow, object_start, object_end) != KERN_SUCCESS)
		rtn = KERN_FAILURE;
	
	vm_object_unlock(object);

	if (rtn == KERN_FAILURE || !allPageoutsSucceeded)
	    	return KERN_FAILURE;
	else
		return KERN_SUCCESS;
}

