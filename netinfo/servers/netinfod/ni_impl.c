/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * "Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.0 (the 'License').  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License."
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
/*
 * NetInfo object caching implementation
 * Copyright (C) 1989 by NeXT, Inc.
 *
 * This layer is intended to perform caching for NetInfo objects.
 * Objects are cached here so that they do not have to be reread from
 * the file layer. When an object is cached, it is "bunched", i.e. it
 * is stored as a single block of memory, versus being scattered everywhere
 * if we had used malloc. Bunching allows for good virtual memory behavior.
 *
 */
#include <stdio.h>
#include <string.h>
#include <netinfo/ni.h>
#include "ni_impl.h"
#include "ni_serial.h"
#include "ni_file.h"
#include "system.h"
#include "mm.h"
#include "strstore.h"
#include "ni_globals.h"

#if ENABLE_CACHE
static void align(char **);
static void prop_dup(char **, ni_property *, ni_property *);
static long obj_size(ni_object *);
static ni_object *obj_bunch(ni_object *);
static void obj_bunchfree(ni_object *);
static ni_object *obj_unbunch(ni_object *);
#endif


/*
 * What's inside the opaque handle we pass to clients of this layer
 */
typedef struct obj_handle {
#if ENABLE_CACHE
	ni_object **obj_cache;	/* array of NetInfo objects, indexed by ID */
	ni_object **obj_cache_remote;	/* modified shadow versions (if any) will */
	ni_object **obj_cache_unprivileged; /* be stored in these auxiliary arrays */
	unsigned obj_cachesize; /* size of this cache */
	unsigned *obj_refcount; /* 1-bit reference count array of objects */
#endif
	void *file_handle;	/* hook into NetInfo file layer */
} obj_handle;
#define OH(hdl) ((struct obj_handle *)(hdl))
#define FH(hdl) (OH(hdl)->file_handle)

#if ENABLE_CACHE
static void refcount_array_free(obj_handle *);
static void refcount_array_grow(obj_handle *);
static void refcount_ref(obj_handle *, ni_index);
static void refcount_unref(obj_handle *, ni_index);
static int refcount_isrefed(obj_handle *, ni_index);
#endif

/*
 * Initializes this module
 */
ni_status
obj_init(
	 char *rootdir,
	 void **hndl
	 )
{
	obj_handle *handle;
	void *fh;
	ni_status status;

	status = file_init(rootdir, &fh);
	if (status != NI_OK) {
		return (status);
	}
	MM_ALLOC(handle);
#if ENABLE_CACHE
	handle->obj_cache = NULL;
	handle->obj_cache_remote = NULL;
	handle->obj_cache_unprivileged = NULL;
	handle->obj_cachesize = 0;
	handle->obj_refcount = NULL;
#endif
	handle->file_handle = fh;
	*hndl = handle;
	return (NI_OK);
}

/*
 * Uninitializes this module
 */
void
obj_free(
	 void *hdl
	 )
{
#if ENABLE_CACHE
	int i;

	for (i = 0; i < OH(hdl)->obj_cachesize; i++) {
		if (OH(hdl)->obj_cache[i] != NULL) {
			obj_bunchfree(OH(hdl)->obj_cache[i]);
		}
		if (OH(hdl)->obj_cache_remote[i] != NULL) {
			obj_bunchfree(OH(hdl)->obj_cache_remote[i]);
		}
		if (OH(hdl)->obj_cache_unprivileged[i] != NULL) {
			obj_bunchfree(OH(hdl)->obj_cache_unprivileged[i]);
		}
	}
	MM_FREE_ARRAY(OH(hdl)->obj_cache, OH(hdl)->obj_cachesize);
	refcount_array_free(OH(hdl));
#endif
	file_free(FH(hdl));
	MM_FREE(OH(hdl));
}

unsigned
obj_getchecksum(
		void *hdl
		)
{
	return (file_getchecksum(FH(hdl)));
}

void
obj_shutdown(
	     void *hdl,
	     unsigned checksum
	     )
{
	file_shutdown(FH(hdl), checksum);
}

/* 
 * Returns TRUE if the db file stream in the already initialized handle 
 *    has been re-openned, FALSE otherwise.
 * Used in readall child process.
 */
bool_t
obj_db_reopen(
	      void *hdl
	     )
{
	return (file_db_reopen(FH(hdl)));
}

/*
 * Returns the name of the directory where these items are stored
 */
char *
obj_dirname(
	    void *hdl
	    )
{
	return (file_dirname(FH(hdl)));
}

/*
 * Renames the directory
 */
void
obj_renamedir(
	      void *hdl,
	      char *name
	      )
{
	file_renamedir(FH(hdl), name);
}

/*
 * Returns the highest object id allocated
 */
ni_index 
obj_highestid(
	      void *hdl
	      )
{
	return (file_highestid(FH(hdl)));
}

/*
 * Allocates a new root object
 */
ni_status
obj_alloc_root(
	       void *hdl,
	       ni_object **objp
	       )
{
	ni_object *obj;
	ni_status status;

	MM_ALLOC(obj);
	MM_ZERO(obj);
	status = file_rootid(FH(hdl), &obj->nio_id);
	if (status != NI_OK) {
		MM_FREE(obj);
		return (status);
	}
	*objp = obj;
	return (NI_OK);
}

/*
 * Allocates a new object, returned ID is arbitrary
 */
ni_status
obj_alloc(
	  void *hdl,
	  ni_object **objp
	  )
{
	ni_object *obj;
	ni_status status;

	MM_ALLOC(obj);
	MM_ZERO(obj);
	status = file_idalloc(FH(hdl), &obj->nio_id);
	if (status != NI_OK) {
		MM_FREE(obj);
		return (status);
	}
	*objp = obj;
	return (NI_OK);
}

/*
 * Allocates a new object, trying to reuse the given ID
 */
ni_status
obj_regenerate(
	       void *hdl,
	       ni_object **objp,
	       ni_id *id
	       )
{
	ni_status status;

	MM_ALLOC(*objp);
	MM_ZERO(*objp);
	(*objp)->nio_id = *id;
	status = file_regenerate(FH(hdl), id);
	if (status != NI_OK) {
		MM_FREE(*objp);
	}
	return (status);
}

/*
 * Deletes an item from the cache, probably because changes were
 * made which should be invalidated.
 */
void
obj_uncache(
	    void *hdl,
	    ni_object *obj
	    )
{
	/*
	 * Since write must have been specified for this to be called,
	 * we can just serial free it (it's not really in the cache).
	 */
	(void)ser_free(obj);
}

/*
 * Destroys an object
 */
void
obj_unalloc(
	    void *hdl,
	    ni_object *obj
	    )
{
	file_idunalloc(FH(hdl), obj->nio_id);
	obj_uncache(hdl, obj);
}

#if ENABLE_CACHE
static int 
ni_name_match_prefix(
		     ni_name_const prefix,
		     ni_name_const name
		     )
{
	const char *a, *b;

	for (a = prefix, b = name; *a && *b; a++, b++) {
		if (*a != *b) return 0;
	}
	return !*a;
}

static int
obj_match(
	  ni_object *obj,
	  int (*comp)(),
	  ni_name_const pattern1,
	  ni_name_const pattern2
	  )
{
	ni_index i;
	int retval = 0;

	for (i = 0; !retval && i < obj->nio_props.nipl_len; i++) {
		retval = ((pattern1 && (*comp)(pattern1, obj->nio_props.nipl_val[i].nip_name)) ||
			  (pattern2 && (*comp)(pattern2, obj->nio_props.nipl_val[i].nip_name)));
	}
	return retval;
}

/*
 * Returns a completely shadowed version of the object.
 */
static ni_object *
obj_shadow(
	    ni_object *obj
	    )
{
	ni_object *new;

	MM_ALLOC(new);
	MM_ZERO(new);
	new->nio_id = obj->nio_id;
	new->nio_parent = obj->nio_parent;
	
	return (new);
}

/*
 * Convert a property to a shadowed version in place.
 */
static void
prop_shadow(
	 ni_property *prop
	 )
{
	ni_index i;

	if (prop->nip_val.ninl_len == 0) return;

	for (i = 0; i < prop->nip_val.ninl_len; i++) {
		ss_unalloc(prop->nip_val.ninl_val[i]);
	}

	prop->nip_val.ninl_len = 1;
	prop->nip_val.ninl_val[0] = (char *)ss_alloc(VALUE_SHADOW);
}

/*
 * Returns a modified version of an object, 
 * appropriately shadowed for distribution to 
 * remote privileged processes, or NULL if no
 * modifications are necessary.
 */
static ni_object *
obj_remote(
	   ni_object *obj
	   )
{   
	ni_index i, j;
	char *mem;
	ni_object *new;
	ni_name key;

	if (obj_match(obj, ni_name_match, SECURE_DIR_KEY, NULL)) return obj_shadow(obj);
	if (!obj_match(obj, ni_name_match_prefix, SECURE_NAME_PREFIX, NULL)) return NULL;

	MM_ALLOC_ARRAY(mem, obj_size(obj));
	
	new = (ni_object *)mem;
	mem += sizeof(*new);
	
	*new = *obj;

	align(&mem);
	new->nio_children.niil_val = (ni_index *)mem;
	mem += new->nio_children.niil_len * sizeof(ni_index);
	for (i = 0; i < new->nio_children.niil_len; i++) {
		(new->nio_children.niil_val[i] =
		 obj->nio_children.niil_val[i]);
	}

	align(&mem);
	new->nio_props.nipl_val = (ni_property *)mem;
	mem += new->nio_props.nipl_len * sizeof(ni_property);
	for (i = 0; i < obj->nio_props.nipl_len; i++) {
		prop_dup(&mem, &obj->nio_props.nipl_val[i],
			 &new->nio_props.nipl_val[i]);
	}

	for (i = 0; i < new->nio_props.nipl_len; i++) {
		if (ni_name_match_prefix(SECURE_NAME_PREFIX, new->nio_props.nipl_val[i].nip_name)) {
			key = strchr(new->nio_props.nipl_val[i].nip_name+1, '_')+1;
			for (j = 0; j < new->nio_props.nipl_len; j++) {
				if (ni_name_match(key, new->nio_props.nipl_val[j].nip_name)) {
					prop_shadow(&(new->nio_props.nipl_val[j]));
				}
			}
		}
	}

	return (new);
}

/*
 * Returns a modified version of an object, 
 * appropriately shadowed for distribution to 
 * unprivileged processes, or NULL if no
 * modifications are necessary.
 */
static ni_object *
obj_unprivileged(
		 ni_object *obj
		 )
{   
	ni_index i, j;
	char *mem;
	ni_object *new;
	ni_name key;

	if (obj_match(obj, ni_name_match, SHADOW_DIR_KEY, SECURE_DIR_KEY)) return obj_shadow(obj);
	if (!obj_match(obj, ni_name_match_prefix, SHADOW_NAME_PREFIX, SECURE_NAME_PREFIX)) return NULL;

	MM_ALLOC_ARRAY(mem, obj_size(obj));
	
	new = (ni_object *)mem;
	mem += sizeof(*new);
	
	*new = *obj;

	align(&mem);
	new->nio_children.niil_val = (ni_index *)mem;
	mem += new->nio_children.niil_len * sizeof(ni_index);
	for (i = 0; i < new->nio_children.niil_len; i++) {
		(new->nio_children.niil_val[i] =
		 obj->nio_children.niil_val[i]);
	}

	align(&mem);
	new->nio_props.nipl_val = (ni_property *)mem;
	mem += new->nio_props.nipl_len * sizeof(ni_property);
	for (i = 0; i < obj->nio_props.nipl_len; i++) {
		prop_dup(&mem, &obj->nio_props.nipl_val[i],
			 &new->nio_props.nipl_val[i]);
	}

	for (i = 0; i < new->nio_props.nipl_len; i++) {
		if (ni_name_match_prefix(SHADOW_NAME_PREFIX, new->nio_props.nipl_val[i].nip_name) ||
		    ni_name_match_prefix(SECURE_NAME_PREFIX, new->nio_props.nipl_val[i].nip_name)) {
			key = strchr(new->nio_props.nipl_val[i].nip_name+1, '_')+1;
			for (j = 0; j < new->nio_props.nipl_len; j++) {
				if (ni_name_match(key, new->nio_props.nipl_val[j].nip_name)) {
					prop_shadow(&(new->nio_props.nipl_val[j]));
				}
			}
		}
	}

	return (new);
}

static void
obj_cachify(
	    void *hdl,
	    ni_object **objp
	    )
{
	ni_object *obj = *objp;
	
	while (obj->nio_id.nii_object >= OH(hdl)->obj_cachesize) {
		MM_GROW_ARRAY(OH(hdl)->obj_cache, OH(hdl)->obj_cachesize);
		MM_GROW_ARRAY(OH(hdl)->obj_cache_remote, OH(hdl)->obj_cachesize);
		MM_GROW_ARRAY(OH(hdl)->obj_cache_unprivileged, OH(hdl)->obj_cachesize);
		refcount_array_grow(OH(hdl));
		OH(hdl)->obj_cache[OH(hdl)->obj_cachesize] = NULL;
		OH(hdl)->obj_cache_remote[OH(hdl)->obj_cachesize] = NULL;
		OH(hdl)->obj_cache_unprivileged[OH(hdl)->obj_cachesize] = NULL;
		OH(hdl)->obj_cachesize++;
	}
	*objp = obj_bunch(obj);
	OH(hdl)->obj_cache[(*objp)->nio_id.nii_object] = *objp;
	if (obj_match(*objp, ni_name_match_prefix, SHADOW_DIR_KEY, SECURE_DIR_KEY)) {	/* calculate shadowed versions only if necessary */
		OH(hdl)->obj_cache_remote[(*objp)->nio_id.nii_object] = obj_remote(*objp);
		OH(hdl)->obj_cache_unprivileged[(*objp)->nio_id.nii_object] = obj_unprivileged(*objp);
	}
}
#endif


/*
 * Lookup an object. If lookup for read, return cached entry. If lookup
 * for write, return unbunched cached entry and remove entry from cache.
 */
ni_status
obj_lookup(
	   void *hdl,
	   ni_id *idp, 
	   ni_op op, 
	   ni_object **objp
	   )
{
	ni_status status;
	ni_id id;
	
#if ENABLE_CACHE
	if (idp->nii_object != NI_INDEX_NULL &&
	    idp->nii_object < OH(hdl)->obj_cachesize && 
	    OH(hdl)->obj_cache[idp->nii_object] != NULL) {
		*objp = OH(hdl)->obj_cache[idp->nii_object];
		if (op == NIOP_WRITE) {
			*objp = obj_unbunch(*objp);
			OH(hdl)->obj_cache[idp->nii_object] = NULL;
			if (OH(hdl)->obj_cache_remote[idp->nii_object] != NULL) {
				obj_bunchfree(OH(hdl)->obj_cache_remote[idp->nii_object]);
				OH(hdl)->obj_cache_remote[idp->nii_object] = NULL;
			}
			if (OH(hdl)->obj_cache_unprivileged[idp->nii_object] != NULL) {
				obj_bunchfree(OH(hdl)->obj_cache_unprivileged[idp->nii_object]);
				OH(hdl)->obj_cache_unprivileged[idp->nii_object] = NULL;
			}
			refcount_unref(OH(hdl), idp->nii_object);
		} else {
			refcount_ref(OH(hdl), idp->nii_object);
		}
		if (op == NIOP_READ_REMOTE && 
		    OH(hdl)->obj_cache_remote[idp->nii_object] != NULL) {
			*objp = OH(hdl)->obj_cache_remote[idp->nii_object];
		}
		if (op == NIOP_READ_UNPRIVILEGED && 
		    OH(hdl)->obj_cache_unprivileged[idp->nii_object] != NULL) {
			*objp = OH(hdl)->obj_cache_unprivileged[idp->nii_object];
		}
		id = (*objp)->nio_id;
	} else 
#endif
	{

		id = *idp;
		status = file_read(FH(hdl), &id, objp);
		if (status != NI_OK) {
			return (status);
		}
#if ENABLE_CACHE
		if (op != NIOP_WRITE) {
			obj_cachify(hdl, objp);
		}
#endif
	}
	if (op == NIOP_WRITE && id.nii_instance != idp->nii_instance) {
		obj_unlookup(hdl, *objp);
		return (NI_STALE);
	}
	*idp = id;
	return (NI_OK);
}



/*
 * Lookup the root object
 */
ni_status
obj_lookup_root(
		void *hdl,
		ni_op op, 
		ni_object **objp
		)
{
	ni_status status;
	ni_id rootid;

	rootid.nii_object = 0;
	rootid.nii_instance = 0;

	status = file_rootid(FH(hdl), &rootid);
	if (status != NI_OK) {
		return (status);
	}
#if ENABLE_CACHE
	if (rootid.nii_object < OH(hdl)->obj_cachesize && 
	    OH(hdl)->obj_cache[rootid.nii_object] != NULL) {
		*objp = OH(hdl)->obj_cache[rootid.nii_object];
		refcount_ref(OH(hdl), rootid.nii_object);
		if (op == NIOP_READ_REMOTE && 
		    OH(hdl)->obj_cache_remote[rootid.nii_object] != NULL) {
			*objp = OH(hdl)->obj_cache_remote[rootid.nii_object];
		}
		if (op == NIOP_READ_UNPRIVILEGED && 
		    OH(hdl)->obj_cache_unprivileged[rootid.nii_object] != NULL) {
			*objp = OH(hdl)->obj_cache_unprivileged[rootid.nii_object];
		}
	} else 
#endif
	{
		status = file_read(FH(hdl), &rootid, objp);
		if (status != NI_OK) {
			return (status);
		}
#if ENABLE_CACHE
		obj_cachify(hdl, objp);
#endif
	}
	return (NI_OK);
}


/*
 * Unlookup an object: mark that we are done using it
 */
void
obj_unlookup(
	     void *hdl,
	     ni_object *obj
	     )
{
#if ENABLE_CACHE
	if (obj->nio_id.nii_object >= OH(hdl)->obj_cachesize ||
	    OH(hdl)->obj_cache[obj->nio_id.nii_object] == NULL) {
		(void)ser_free(obj);
	}
#else
	(void)ser_free(obj);
#endif
}

/*
 * Forget everything we know
 */
void
obj_forget(
	   void *hdl
	   )
{
#if ENABLE_CACHE
	/*
	 * It is too painful to uncache all entries. Need to come up with
	 * a better scheme.
	 */
	ni_index i;

	for (i = 0; i < OH(hdl)->obj_cachesize; i++) {
		if (OH(hdl)->obj_cache[i] != NULL &&
		    refcount_isrefed(OH(hdl), i)) {
			obj_bunchfree(OH(hdl)->obj_cache[i]);
			OH(hdl)->obj_cache[i] = NULL;
			if (OH(hdl)->obj_cache_remote[i] != NULL) {
			    obj_bunchfree(OH(hdl)->obj_cache_remote[i]);
			    OH(hdl)->obj_cache_remote[i] = NULL;
			}
			if (OH(hdl)->obj_cache_unprivileged[i] != NULL) {
			    obj_bunchfree(OH(hdl)->obj_cache_unprivileged[i]);
			    OH(hdl)->obj_cache_unprivileged[i] = NULL;
			}
			refcount_unref(OH(hdl), i);
		}
	}
#endif
}

/*
 * Commit a change to an object
 */
ni_status
obj_commit(
	   void *hdl,
	   ni_object *obj
	   )
{
	obj->nio_id.nii_instance++;
	return (file_write(FH(hdl), obj));
}

#if ENABLE_CACHE
/*
 * Align a piece of memory on a long boundary
 */
static void
align(char **mem)
{
	int size = (int)*mem;

	size = (((size + (sizeof(long) - 1)) / sizeof(long)) * sizeof(long));
	*mem = (char *)size;
}

/*
 * Duplicate a property, but use the given piece of memory instead of
 * malloc().
 */
static void
prop_dup(
	 char **mem,
	 ni_property *orig,
	 ni_property *new
	 )
{
	ni_index i;

	new->nip_val.ninl_len = orig->nip_val.ninl_len;

	align(mem);
	new->nip_val.ninl_val = (ni_name *)*mem;
	*mem += new->nip_val.ninl_len * sizeof(ni_name);

	new->nip_name = (char *)ss_alloc(orig->nip_name);
	
	for (i = 0; i < orig->nip_val.ninl_len; i++) {
		(new->nip_val.ninl_val[i] = 
		 (char *)ss_alloc(orig->nip_val.ninl_val[i]));
	}
}

/*
 * Mark all of the strings in the property as no longer in use
 */
static void
prop_untouch(
	     ni_property *prop
	     )
{
	ni_index i;

	ss_unalloc(prop->nip_name);
	
	for (i = 0; i < prop->nip_val.ninl_len; i++) {
		ss_unalloc(prop->nip_val.ninl_val[i]);
	}
}

/*
 * Determine the size of a NetInfo object
 */
static long
obj_size(
	 ni_object *obj
	 )
{
	ni_index i;
	ni_property *pp;
	char *mem;

	mem = 0;
	mem += sizeof(*obj);

	align(&mem);
	mem += obj->nio_children.niil_len * sizeof(ni_index);

	align(&mem);
	mem += obj->nio_props.nipl_len * sizeof(ni_property);
	
	for (i = 0; i < obj->nio_props.nipl_len; i++) {
		pp = &obj->nio_props.nipl_val[i];

		align(&mem);
		mem += pp->nip_val.ninl_len * sizeof(ni_name);
		
	}
	return ((long)mem);
}

/*
 * Return a bunched copy of the given unbunched (malloced) NetInfo object.
 * Frees the argument.
 */
static ni_object *
obj_bunch(
	  ni_object *obj
	  )
{
	ni_index i;
	char *mem;
	ni_object *new;


	MM_ALLOC_ARRAY(mem, obj_size(obj));
	
	new = (ni_object *)mem;
	mem += sizeof(*new);
	
	*new = *obj;

	align(&mem);
	new->nio_children.niil_val = (ni_index *)mem;
	mem += new->nio_children.niil_len * sizeof(ni_index);
	for (i = 0; i < new->nio_children.niil_len; i++) {
		(new->nio_children.niil_val[i] =
		 obj->nio_children.niil_val[i]);
	}

	align(&mem);
	new->nio_props.nipl_val = (ni_property *)mem;
	mem += new->nio_props.nipl_len * sizeof(ni_property);
	for (i = 0; i < obj->nio_props.nipl_len; i++) {
		prop_dup(&mem, &obj->nio_props.nipl_val[i],
			 &new->nio_props.nipl_val[i]);
	}
	(void)ser_free(obj);
	return (new);
}

/*
 * Free a bunched object
 */
static void
obj_bunchfree(
	      ni_object *obj
	      )
{
	ni_index i;

	for (i = 0; i < obj->nio_props.nipl_len; i++) {
		prop_untouch(&obj->nio_props.nipl_val[i]);
	}
	MM_FREE(obj);
}


/*
 * Returns an unbunched (malloced) copy of the bunched argument. 
 * Frees the argument.
 */
static ni_object *
obj_unbunch(
	    ni_object *obj
	    )
{
	ni_object *new;

	MM_ALLOC(new);
	new->nio_id = obj->nio_id;
	new->nio_parent = obj->nio_parent;
	new->nio_children = ni_idlist_dup(obj->nio_children);
	new->nio_props = ni_proplist_dup(obj->nio_props);
	
	obj_bunchfree(obj);

	return (new);
}
#endif


#if ENABLE_CACHE

#define REFUNITSIZE (sizeof(unsigned) * NBBY)

static inline unsigned
ni_roundup(
	unsigned x, 
	unsigned y
	)
{
	return (((x + y - 1) / y) * y);
}

static void
refcount_array_free(
		    obj_handle *hdl
		    )
{
	MM_FREE(hdl->obj_refcount);
}

static void
refcount_array_grow(
		    obj_handle *hdl
		    )
{
	unsigned usize;

	if ((hdl->obj_cachesize % REFUNITSIZE) == 0) {
		usize = ni_roundup(hdl->obj_cachesize, REFUNITSIZE);
		MM_GROW_ARRAY(hdl->obj_refcount, usize);
		hdl->obj_refcount[usize] = 0;
	}
}

static void
refcount_ref(
	     obj_handle *hdl,
	     ni_index id
	     )
{
	hdl->obj_refcount[id/REFUNITSIZE] |= (1 << (id % REFUNITSIZE));
}


static void
refcount_unref(
	     obj_handle *hdl,
	     ni_index id
	     )
{
	hdl->obj_refcount[id/REFUNITSIZE] &= ~(1 << (id % REFUNITSIZE));
}

static int
refcount_isrefed(
	     obj_handle *hdl,
	     ni_index id
	     )
{
	return (hdl->obj_refcount[id/REFUNITSIZE] & (1 << (id % REFUNITSIZE)));
}

#endif
