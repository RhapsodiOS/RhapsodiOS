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
 * Low-level NetInfo file handling definitions
 * Copyright (C) 1989 by NeXT, Inc.
 *
 * The implementation is quite simple-minded. All information is stored
 * in various files in a directory. The file "collection" is the main
 * source of information. It consists of fixed-size blocks, one for each
 * directory ID. Block X corresponds to directory ID X. The directories
 * are stored in XDR format in the file (an easy way to serialize data).
 *
 * If a directory encodes to a value greater than the fixed quantum, then it
 * is stored in an auxilliary file called "extension_XXX", where XXX
 * is the directory ID. 
 *
 * Freed directories are marked with an encoded directory id of -1 (all ones).
 *
 * Much care is taken to implement transactions correctly. A crash can
 * occur at any point, and the system will be able to put the database
 * back into a consistent state on recovery. See the function transact()
 * for more information about how transactions are implemented.
 *
 * TODO: truncate collection file as necessary - doesn't work unless entire
 * database is checked, which we are avoiding these days. Not very useful
 * at present.
 */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <netinfo/ni.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/mount.h>
#include "ni_file.h"
#include "ni_serial.h"
#include "ni_globals.h"
#include "system.h"
#include "mm.h"
#include "safe_stdio.h"

#define NI_UNCHECKED ((ni_index)-2)

#define PARANOID	/* force extra checking */

#define DB_ROOTID 0		/* ID of root directory */
#define DB_FREE -1		/* ID of freed directory */
#define OLD_BLOCKSIZE 256	/* Old standard block size (for collection) */
#define DFL_BLOCKSIZE 512	/* Default block size (for bigcollection) */
#define TRANSACTION_SLOP 48	/* Size of extra junk in transactions */
#define MIN_FRAGSIZE 256	/* Least #bytes that can be synced at once */

extern void socket_lock();
extern void socket_unlock();

/*
 * Strings constants
 */
static const char TRANSACT_MAIN[] = "collection"; 	
static const char TRANSACT_MAIN_BIG[] = "Collection"; 	
static const char TRANSACT_CHECKSUM[] = "checksum";
static const char TRANSACT_CHECKSUM_INPROGRESS[] = "checksum_inprogress";
static const char TRANSACT_TEMP[] = "temporary_";	
static const char TRANSACT_INPROGRESS[] = "Transaction";
static const char TRANSACT_INPROGRESS_OLD[] = "transaction_";
static const char TRANSACT_FINAL[] = "extension_";

/*
 * What the header of a database item looks like
 */
typedef	union bufhead {
	char bytes[BYTES_PER_XDR_UNIT * 2];	/* as raw bytes */
	struct {				/* or structured */
		ni_index object;		
		ni_index instance;
	} ints;
} bufhead;

/*
 * The contents of the opaque pointer we pass to clients of this layer.
 * A word on the instance array: if a directory with ID=X is allocated, 
 * its instance is kept up to date in instances[X]. If the directory is
 * free, then instance[X] = NI_INDEX_NULL.
 *
 * If the directory has not been checked, then instance[X] == NI_UNCHECKED.
 */
typedef struct file_handle {
	char *transact_dir;	/* name of database directory */
	ni_index highest_id;	/* highest ID in the database */
	ni_index *instances;	/* array of instances, indexed by ID */
	FILE *db;		/* pointer to open file */
	FILE *transaction;	/* transaction file */
	long transact_bsize;	/* filesystem frag size */
	char *buf;		/* buffer used by stdio */
	unsigned checksum;	/* checksum to be saved/restored */
	unsigned blocksize;	/* size of native blocks in this domain */
} file_handle;
#define FH(hdl) ((file_handle *)(hdl))

static ni_status file_generate(void *, ni_id *);

static ni_status transact(file_handle *, long, void *, long);
static void transact_cleanup(file_handle *);
static char *db_mkname(file_handle *, const char *, long);
static int id_is_free(file_handle *, ni_index);

static long fsize(FILE *);


/*
 * Returns the directory name of the database
 */
char *
file_dirname(void *hdl)
{
	return (FH(hdl)->transact_dir);
}

/*
 * Opens the collection file associated with an already initialized file 
 *    handle. Resets the file stream pointer to the newly openned stream
      in the given handle.
 * Returns "TRUE" if successful, false otherwise.
 * Used in 'readall' child process. 
 */
bool_t
file_db_reopen(void *hdl)
{
	char *name;

	if ( FH(hdl)->blocksize == DFL_BLOCKSIZE ) {	/* Are we macho? */
		name = db_mkname(FH(hdl), TRANSACT_MAIN_BIG, -1);
	} else {					/* or wimpy? */
		name = db_mkname(FH(hdl), TRANSACT_MAIN, -1);
	}
	/*
	 * We're *NOT* using any socket locking here.  This must
	 * be called ONLY from a readall proxy, which we know will
	 * have ONLY one thread.
	 */
	FH(hdl)->db = freopen(name, "r", FH(hdl)->db);
	MM_FREE(name);
	return( FH(hdl)->db != NULL );
}

/* 
 * Returns the root ID of the database.
 * Allocates a new root if none exists already.
 */
ni_status
file_rootid(void *hdl, ni_id *idp)
{
	if (DB_ROOTID < FH(hdl)->highest_id && !id_is_free(FH(hdl), 0)) {
		idp->nii_object = DB_ROOTID;
		idp->nii_instance = FH(hdl)->instances[0];
		return (NI_OK);
	}
	return (file_idalloc(hdl, idp));
}

/*
 * Reads only the ID and instance from the database
 */
static ni_status
file_objectid(void *hdl, ni_id *idp)
{
	bufhead buf;
	char *fname;
	FILE *f;

	fname = db_mkname(FH(hdl), TRANSACT_FINAL, idp->nii_object);
	f = safe_fopen(fname, "r");
	MM_FREE(fname);
	if (f == NULL) {
		/*
		 * No extension file, seek into collection file
		 */
		f = FH(hdl)->db;
		if (fseek(f, idp->nii_object * FH(hdl)->blocksize,  0) != 0) {
			return (NI_SYSTEMERR);
		}
	}
	if (fread(&buf, sizeof(buf), 1, f) != 1) {
		if (f != FH(hdl)->db) {
			safe_fclose(f);
		}
		return (NI_SYSTEMERR);
	}
	idp->nii_object = htonl(buf.ints.object);
	idp->nii_instance = htonl(buf.ints.instance);
	if (f != FH(hdl)->db) {
		safe_fclose(f);
	}
	return (NI_OK);
}

/*
 * Finds the instance for the given ID
 */
static ni_status
file_instance(void *hdl, ni_id *idp)
{
	bufhead buf;
	char *fname;
	FILE *f;

	fname = db_mkname(FH(hdl), TRANSACT_FINAL, idp->nii_object);
	f = safe_fopen(fname, "r");
	MM_FREE(fname);
	if (f == NULL) {
		/*
		 * No extension file, seek into collection file
		 */
		f = FH(hdl)->db;
		if (fseek(f, idp->nii_object * FH(hdl)->blocksize,  0) != 0) {
			return (NI_SYSTEMERR);
		}
	}
	if (fread(&buf, sizeof(buf), 1, f) != 1) {
		if (f != FH(hdl)->db) {
			safe_fclose(f);
		}
		return (NI_SYSTEMERR);
	}
	idp->nii_instance = htonl(buf.ints.instance);
	FH(hdl)->instances[idp->nii_object] = idp->nii_instance;
	if (f != FH(hdl)->db) {
		safe_fclose(f);
	}
	return (NI_OK);
}


/*
 * Allocates a new directory. Tries to find a freed directory, otherwise
 * grows the database.
 */
ni_status
file_idalloc(void *hdl, ni_id *idp)
{
	ni_index i;

	for (i = DB_ROOTID; i < FH(hdl)->highest_id; i++) {
		if (id_is_free(FH(hdl), i)) {
			idp->nii_object = i;
			return (file_instance(hdl, idp));
		}
	}
	return (file_generate(hdl, idp));
}

/*
 * Grow the database to generate a new directory 
 */
static ni_status
file_generate(void *hdl, ni_id *idp)
{
	ni_id id;
	ni_object obj;
	long size;
	ni_status status;
	char c;
	void *mem;

	MM_ZERO(&obj);
	obj.nio_id.nii_object = DB_FREE;
	obj.nio_id.nii_instance = idp->nii_instance;
		
	id.nii_instance = idp->nii_instance;
	id.nii_object = FH(hdl)->highest_id;

	status = ser_memencode(&obj, &mem, &size);
	if (status != NI_OK) {
		return (status);
	}
	if (fseek(FH(hdl)->db, ((FH(hdl)->highest_id + 1) * 
		FH(hdl)->blocksize) - 1, 0) != 0) 
	{
		sys_msg(debug, LOG_ALERT, "cannot seek transaction file");
	}
	c = -1;
	if (fwrite(&c, 1, 1, FH(hdl)->db) != 1) {
		if (ftruncate(fileno(FH(hdl)->db),
			      id.nii_object * FH(hdl)->blocksize) < 0) {
			sys_msg(debug, LOG_ERR, "cannot truncate db file");
		}
		free(mem);
		return (NI_NOSPACE);
	}
	status = transact(FH(hdl), id.nii_object, mem, size);
	free(mem);
	if (status != NI_OK) {
		if (ftruncate(fileno(FH(hdl)->db),
			      id.nii_object * FH(hdl)->blocksize) < 0) {
			sys_msg(debug, LOG_ERR, "cannot truncate db file");
		}
		return (status);
	}
	MM_GROW_ARRAY(FH(hdl)->instances, FH(hdl)->highest_id);
	FH(hdl)->instances[FH(hdl)->highest_id] = id.nii_object;
	FH(hdl)->highest_id++;
	*idp = id;
	return (NI_OK);
}

/*
 * Allocate a new directory with a specific directory ID. Used by
 * clone servers when getting a CREATE update from the master (they
 * have to be sure they get the same new child ID as the master).
 */
ni_status
file_regenerate(void *hdl, ni_id *idp)
{
	ni_id id;
	ni_index i;
	ni_status status;

	if (idp->nii_object >= FH(hdl)->highest_id) {
		for (i = FH(hdl)->highest_id; i < idp->nii_object; i++) {
			id.nii_object = i;
			id.nii_instance = 0;
			status = file_generate(hdl, &id);
			if (status != NI_OK) {
				return (status);
			}
			FH(hdl)->instances[id.nii_object] = NI_INDEX_NULL;
		}
		return (file_generate(hdl, idp));
	} else {
		if (!id_is_free(FH(hdl), idp->nii_object)) {
			return (NI_ALIVE);
		}
		return (file_instance(hdl, idp));
	}
}

/*
 * Deallocate a directory
 */
ni_status
file_idunalloc(void *hdl, ni_id id)
{
	ni_object tmp;
	long size;
	ni_status status;
	void *mem;

	MM_ZERO(&tmp);
	tmp.nio_id.nii_instance = id.nii_instance;
	tmp.nio_id.nii_object = DB_FREE;
	status = ser_memencode(&tmp, &mem, &size);
	if (status != NI_OK) {
		return (status);
	}
	status = transact(FH(hdl), id.nii_object, mem, size);
	free(mem);
	if (status != NI_OK) {
		return (status);
	}
	FH(hdl)->instances[id.nii_object] = NI_INDEX_NULL;
	return (NI_OK);
}

/*
 * Read the NetInfo object associated with the given id.
 */
ni_status
file_read(void *hdl, ni_id *id, ni_object **obj)
{
	char *fname;
	FILE *f;
	ni_status status;

	if (id->nii_object >= FH(hdl)->highest_id) return (NI_BADID);
	
	fname = db_mkname(FH(hdl), TRANSACT_FINAL, id->nii_object);
	f = safe_fopen(fname, "r");
	MM_FREE(fname);
	if (f == NULL) {
		status = ser_decode(FH(hdl)->db, id->nii_object * FH(hdl)->blocksize, obj);
	} else {
		status = ser_decode(f, 0, obj);
		safe_fclose(f);
	}
	if (status != NI_OK) {
		return (NI_BADID);
	}
	id->nii_instance = (*obj)->nio_id.nii_instance;
	if ((*obj)->nio_id.nii_object == DB_FREE) {
		ser_free(*obj);
		FH(hdl)->instances[id->nii_object] = NI_INDEX_NULL;
		return (NI_BADID);
	}
#ifdef PARANOID
	if ((*obj)->nio_id.nii_object != id->nii_object) {
		ser_free(*obj);
		FH(hdl)->instances[id->nii_object] = NI_INDEX_NULL;
		sys_msg(debug, LOG_ERR, "corrupted database entry: id = %d\n",
			   id->nii_object);
		return (NI_SYSTEMERR);
	}
#endif
	FH(hdl)->instances[id->nii_object] = id->nii_instance;
	return (NI_OK);
}

/*
 * Write out the given NetInfo object
 */
ni_status
file_write(void *hdl, ni_object *obj)
{
	long size;
	ni_status status;
	void *mem;
	
	status = ser_memencode(obj, &mem, &size);
	if (status != NI_OK) {
		return (status);
	}
	status = transact(FH(hdl), obj->nio_id.nii_object, mem, size);
	free(mem);
	if (status != NI_OK) {
		return (status);
	}
	FH(hdl)->instances[obj->nio_id.nii_object] = obj->nio_id.nii_instance;
	return (NI_OK);
}

/*
 * Grow the file (needed by forced writes)
 */
static int
file_grow(void *hdl, ni_index toindex)
{
	ni_index i;
	union {
		ni_id id;
		char buf[DFL_BLOCKSIZE];
	} buf;
	
	MM_ZERO(&buf);
	buf.id.nii_object = DB_FREE;
	for (i = FH(hdl)->highest_id; i <= toindex; i++) {
		if (fseek(FH(hdl)->db, i * FH(hdl)->blocksize, 0) < 0) {
			return (0);
		}
		if (fwrite(buf.buf, FH(hdl)->blocksize, 1, FH(hdl)->db) == 0) {
			return (0);
		}
		MM_GROW_ARRAY(FH(hdl)->instances, FH(hdl)->highest_id);
		FH(hdl)->instances[FH(hdl)->highest_id] = NI_INDEX_NULL;
		FH(hdl)->highest_id++;
	}
	return (1);
}

/*
 * Returns the highest ID of the database
 */
ni_index
file_highestid(void *hdl)
{
	return (FH(hdl)->highest_id);
}

/*
 * Forced NetInfo writes. Used by clone servers receiving entire databases.
 * To improve performance, the transaction stuff is omitted since the
 * entire database transfer is the transaction, not each individual write.
 */
ni_status
file_forcewrite(void *hdl, ni_object *obj, ni_index maxid)
{
	char *fname;
	FILE *f;
	long size;
	ni_status status;
	
	status = ser_size(obj, &size);
	if (status != NI_OK) {
		return (status);
	}
	if (obj->nio_id.nii_object >= FH(hdl)->highest_id) {
		if (obj->nio_id.nii_object > maxid) {
			return (NI_NOSPACE);
		}

		if (file_grow(hdl, obj->nio_id.nii_object) < 0) {
			return (NI_NOSPACE);
		}
	}
	if (size <= FH(hdl)->blocksize) {
		if (fseek(FH(hdl)->db, obj->nio_id.nii_object * 
			FH(hdl)->blocksize, 0) < 0) {
			return (NI_SERIAL);
		}
		status = ser_fastencode(FH(hdl)->db, obj);
		if (status != NI_OK) {
			return (status);
		}
	} else {
		fname = db_mkname(FH(hdl), TRANSACT_FINAL, 
				  obj->nio_id.nii_object);
		f = safe_fopen(fname, "w");
		MM_FREE(fname);
		if (f == NULL) {
			return (NI_NOSPACE);
		}
		status = ser_fastencode(f, obj);
		fsync(fileno(f));
		safe_fclose(f);
		if (status != NI_OK) {
			return (status);
		}
	}

	FH(hdl)->instances[obj->nio_id.nii_object] = obj->nio_id.nii_instance;
	return (NI_OK);
}

/*
 * Useful tool for generating a database file name
 * prefix == prefix of file name
 * where == suffix, less than 0 if not to be used
 */
static char *
db_mkname(file_handle *handle, const char *prefix, long where)
{
	char buf[256];

	if (where < 0) {
		sprintf(buf, "%s/%s", handle->transact_dir, prefix);
	} else {
		sprintf(buf, "%s/%s%lu", handle->transact_dir, prefix, where);
	}
	return (ni_name_dup(buf));
}

/*
 * Rename this database
 */
void
file_renamedir(void *hndl, char *newname)
{
	ni_name_free(&FH(hndl)->transact_dir);
	FH(hndl)->transact_dir = ni_name_dup(newname);
}

/*
 * Recursively reads the database to initialize instance array
 * and to warn of any problems in the database.
 */
static ni_status
readit(void *hdl, ni_index which)
{
	ni_id id;
	ni_index i;
	ni_object *obj;
	ni_status status;

	id.nii_object = which;
	
	status = file_read(hdl, &id, &obj);
	if (status != NI_OK) {
		sys_msg(debug, LOG_ERR, "cannot read ID=%d: %s\n", 
			id.nii_object, ni_error(status));
		return (status);
	}
	for (i = 0; i < obj->nio_children.niil_len; i++) {
		status = readit(hdl, obj->nio_children.niil_val[i]);
		/*
		 * Ignore status for now
		 */
	}
	ser_free(obj);
	return (NI_OK);
}

static int
id_is_free(file_handle *handle, ni_index dir)
{
	ni_status status;
	ni_id id;
	ni_object *obj;

	if (handle->instances[dir] != NI_UNCHECKED) {
		return (handle->instances[dir] == NI_INDEX_NULL);
	}
	id.nii_object = dir;
	status = file_objectid(handle, &id);
	if (status != NI_OK) {
		sys_msg(debug, LOG_ALERT, "cannot read object ID");
	}
	if (id.nii_object != DB_FREE) {
		/*
		 * It appears to be allocated, let's see
		 * if we can read it.
		 */
		status = file_read(handle, &id, &obj);
		if (status != NI_OK) {
			sys_msg(debug, LOG_ALERT, "cannot read object, deleting");
			
			/*
			 * We had a problem reading this object.
			 * Be sure it is deleted so it won't cause
			 * problems in the future.
			 */
			status = file_idunalloc(handle, id);
			/*
			 * XXX: TODO - update parent's children list
			 */
			if (status != NI_OK) {
				sys_msg(debug, LOG_ALERT, "cannot delete object");
			}
			handle->instances[dir] = NI_INDEX_NULL;
		} else {
			/*
			 * file_read() has already set the
			 * instance for us
			 */
			ser_free(obj);
		}
	} else {
		/*
		 * It is free, mark it as such
		 */
		handle->instances[dir] = NI_INDEX_NULL;
	}
	return (handle->instances[dir] == NI_INDEX_NULL);
}

static int
quick_startup(file_handle *handle)
{
	ni_name name;
	FILE *f;
	unsigned checksum;
	ni_index i;

	handle->checksum = NI_INDEX_NULL;
	name = db_mkname(handle, TRANSACT_CHECKSUM, -1);
	f = safe_fopen(name, "r+");
	unlink(name);
	ni_name_free(&name);
	if (f == NULL) {
		return (0);
	}
	if (fread(&checksum, sizeof(checksum), 1, f) != 1) {
		safe_fclose(f);
		return (0);
	}
	safe_fclose(f);
	handle->checksum = ntohl(checksum);
	for (i = DB_ROOTID; i < handle->highest_id; i++) {
		handle->instances[i] = NI_UNCHECKED;
	}
	return (1);
}

/*
 * Don't be fooled. This doesn't get executed unless the database
 * needs checking, which is rare. 
 */
static void
truncate_as_necessary(file_handle *handle, ni_index where)
{
	if (ftruncate(fileno(FH(handle)->db),
		      (where + 1) * handle->blocksize) < 0) {
		sys_msg(debug, LOG_ERR, "cannot truncate db file");
	} else {
		handle->highest_id = where + 1;
	}
}

static ni_status
checkdb(file_handle *handle)
{
	ni_index i;
	ni_status status;
	ni_id id;
	ni_index highest_alloced;

	sys_msg(debug, LOG_ERR, "checking NetInfo database %s", handle->transact_dir);

	status = readit(handle, DB_ROOTID);
	if (status != NI_OK) {
		sys_msg(debug, LOG_ERR, "database check failed: %s",
			ni_error(status));
		return (status);
	}
	highest_alloced = NI_INDEX_NULL;
	for (i = DB_ROOTID; i < handle->highest_id; i++) {
		if (handle->instances[i] == NI_INDEX_NULL) {
			id.nii_object = i;
			status = file_objectid(handle, &id);
			if (status != NI_OK) {
				sys_msg(debug, LOG_ERR,
					"database check failed: %s", ni_error(status));
				return (status);
			}
			if (id.nii_object != DB_FREE) {
				/*
				 * We had a problem reading this object.
				 * Be sure it is deleted so it won't cause
				 * problems in the future.
				 */
				status = file_idunalloc(handle, id);
				if (status != NI_OK) {
					sys_msg(debug, LOG_ERR,
						"database check failed: %s", ni_error(status));
					return (status);
				}
			}
			handle->instances[i] = NI_INDEX_NULL;
		}
		if (handle->instances[i] != NI_INDEX_NULL) {
			highest_alloced = i;
		}
	}
	if (highest_alloced != NI_INDEX_NULL) {
		truncate_as_necessary(handle, highest_alloced);
	}
	sys_msg(debug, LOG_NOTICE, "NetInfo database %s OK", handle->transact_dir);
	return (NI_OK);
}

/*
 * Initializes this layer
 */
ni_status
file_init(char *rootdir, void **hndl)
{
	ni_index i;
	
	char *name;
	file_handle *handle;
	ni_status status;
	struct statfs sfs;

	/*
	** GRS 2/27/92 - Look for an old collection file (256-byte blocks),
	** and if not found, then look for a 512-byte block Collection, or
	** create the DB as a 512-byte block domain.
	*/
	
	MM_ALLOC(handle);
	handle->transact_dir = ni_name_dup(rootdir);
	/* Open the transaction file */
	name = db_mkname(handle, TRANSACT_INPROGRESS, -1);
	if (!(handle->transaction = safe_fopen(name, "r+")) &&
		!(handle->transaction = safe_fopen(name, "w+"))) 
	{
		sys_msg(debug, LOG_ERR, "cannot open file %s: %m", name);
		MM_FREE(name);
		MM_FREE(handle);
		return (NI_SYSTEMERR);
	}
	if (!statfs(name, &sfs) && (sfs.f_bsize > 0)) {
		handle->transact_bsize = sfs.f_bsize;
	} else {
		handle->transact_bsize = MIN_FRAGSIZE;
	}
	MM_FREE(name);
	name = db_mkname(handle, TRANSACT_MAIN, -1);
	handle->db = safe_fopen(name, "r+");
	if (handle->db == NULL) {
		MM_FREE(name);
		name = db_mkname(handle, TRANSACT_MAIN_BIG, -1);
		handle->db = safe_fopen(name, "r+");
		if (handle->db == NULL) {
			handle->db = safe_fopen(name, "w+");
			if (handle->db == NULL) {
				sys_msg(debug, LOG_ERR, "cannot open file %s: %m", name);
				MM_FREE(name);
				MM_FREE(handle->transact_dir);
				MM_FREE(handle);
				return (NI_SYSTEMERR);
			}
		}
		handle->blocksize = DFL_BLOCKSIZE;
	} else {
		handle->blocksize = OLD_BLOCKSIZE;
	}

#ifdef _NETINFO_FLOCK_
	if (flock(fileno(handle->db), LOCK_EX|LOCK_NB) < 0) {
		sys_msg(debug, LOG_ERR, "cannot flock file %s: %m", name);
		MM_FREE(handle->transact_dir);
		MM_FREE(handle);
		safe_fclose(handle->db);
		MM_FREE(name);
		return (NI_SYSTEMERR);
	}
#endif _NETINFO_FLOCK_

	MM_FREE(name);
	MM_ALLOC_ARRAY(handle->buf, handle->blocksize);
	setbuffer(handle->db, handle->buf, handle->blocksize);
	handle->highest_id = (fsize(handle->db) + handle->blocksize - 1) / handle->blocksize;
	MM_ALLOC_ARRAY(handle->instances, handle->highest_id);
	for (i = DB_ROOTID; i < handle->highest_id; i++) {
		handle->instances[i] = NI_INDEX_NULL;
	}
	transact_cleanup(handle);

	if (handle->highest_id == 0) {
		/*
		 * Newly created database
		 */
		*hndl = handle;
		return (NI_OK);
	}
	if (!quick_startup(handle)) {
		status = checkdb(handle);
		if (status != NI_OK) {
			return (status);
		}
	}
	*hndl = handle;
	return (NI_OK);
}

unsigned
file_getchecksum(void *handle)
{
	return (FH(handle)->checksum);
}
		 

static void
save_checksum(file_handle *handle, unsigned checksum)
{
	ni_name fname;
	ni_name fname2;
	FILE *f;

	checksum = htonl(checksum);

	fname = db_mkname(handle, TRANSACT_CHECKSUM_INPROGRESS, -1);
	f = safe_fopen(fname, "w");
	if (f == NULL) {
		sys_msg(debug, LOG_ERR, "cannot save checksum");
		MM_FREE(fname);
		return;
	}
	if (fwrite(&checksum, sizeof(checksum), 1, f) == 0) {
		sys_msg(debug, LOG_ERR, "cannot save checksum");
		safe_fclose(f);
		(void)unlink(fname);
		MM_FREE(fname);
		return;
	}
	fsync(fileno(f));
	safe_fclose(f);

	fname2 = db_mkname(handle, TRANSACT_CHECKSUM, -1);
	if (rename(fname, fname2) < 0) {
		/*
		 * paranoid
		 */
		(void)unlink(fname);
		(void)unlink(fname2);
	}
	MM_FREE(fname);
	MM_FREE(fname2);
	safe_fclose(f);
}	


/*
 * Uninitilize this layer
 */
void
file_free(void *hdl)
{
	MM_FREE(FH(hdl)->transact_dir);
	MM_FREE(FH(hdl)->buf);
	MM_FREE(FH(hdl)->instances);
	fflush(FH(hdl)->db);
	fsync(fileno(FH(hdl)->db)); /* sync just in case */
	safe_fclose(FH(hdl)->db);
	safe_fclose(FH(hdl)->transaction);
	MM_FREE(FH(hdl));
}

void
file_shutdown(void *handle, unsigned checksum)
{
	save_checksum(FH(handle), checksum);
	fflush(FH(handle)->db);
	fsync(fileno(FH(handle)->db)); /* sync just in case */
	safe_fclose(FH(handle)->db);
	sync(); 	/* more paranoia */
}

/*
 * How transactions work
 * 1. The data starts out in a range of memory.
 *    The data is not committed to the database at this point.
 * 2. If the data size is greater than a std block, then the data is written
 *    to a file and this file is then renamed to "extension_ID" and the
 *    transaction is complete.
 * 3. Else, the transaction file is seeked to the beginning and a random
 *    transaction code is written out, along with the directory ID and size.
 *    Then the data is written to the transaction file, the file is 
 *    fsync'ed, and the transaction code is written and fsync'ed.  Then
 *    the data is trasnferred to database record ID.  The transaction
 *    file is then seeked to the beginning and a zero transaction code 
 *    is written.
 *    
 *    Whenever two matching transaction codes are present in the
 *    transaction file, there is a valid transaction that should be
 *    executed.
 */

static ni_status
transact(file_handle *handle, long id, void *mem, long size)
{
	ni_status status;
	char *final_name;
	union {
		long id;
		char buf[DFL_BLOCKSIZE];
	} buf;
	XDR xdr;
	long trans_code;
	FILE *extension;
	long zero = 0;

	final_name = db_mkname(handle, TRANSACT_FINAL, id);

	status = NI_OK;
	/* Write transaction file */
	if (fseek(handle->transaction, 0, SEEK_SET)) {
	    sys_msg(debug, LOG_ALERT, "cannot seek transaction file: %m");
	}
	while (!(trans_code = random())) {
	    /* Do nothing */
	}
	xdrstdio_create(&xdr, handle->transaction, XDR_ENCODE);
	if (!xdr_long(&xdr, &trans_code) || !xdr_long(&xdr, &size) ||
	    !xdr_long(&xdr, &id) || !xdr_opaque(&xdr, mem, size))
	{
	    xdr_destroy(&xdr);
	    sys_msg(debug, LOG_ALERT, "cannot write transaction file: %m");
	}
	if ((size + TRANSACTION_SLOP) > handle->transact_bsize) {
	    fflush(handle->transaction);
	    fsync(fileno(handle->transaction));
	}
	xdr_long(&xdr, &trans_code);
	fflush(handle->transaction);
	fsync(fileno(handle->transaction));
	xdr_setpos(&xdr, 0);
	if (size <= handle->blocksize) {
		MM_ZERO(&buf); /* so identical db's will compare */
		bcopy(mem, buf.buf, size);
		if (fseek(handle->db, id * handle->blocksize, 0) != 0) {
			/*
			 * Do not commit this data on reboot
			 */
			if (!xdr_long(&xdr, &zero)) {
			    sys_msg(debug, LOG_ALERT, "cannot seek transaction record: %m");
			}
			xdr_destroy(&xdr);
			fsync(fileno(handle->transaction));
			status = NI_SYSTEMERR;
			goto done;
		}
#ifdef PARANOID
		/*
		 * Buf will be a serialized netinfo object
		 * (i.e. in network order!)
		 */
		if (buf.id != htonl(DB_FREE) && buf.id != htonl(id)) {
			/* Can only happen via bug */
			abort();
		}
#endif
		/*
		 * The data will be committed after this - there is
		 * no recovery after this point - we must panic!
		 */
		if (fwrite(buf.buf, handle->blocksize, 1, handle->db) != 1) {
			sys_msg(debug, LOG_ALERT, "cannot write transaction record: %m");
		}
		fflush(handle->db);
		fsync(fileno(handle->db));
		/*
		 * In case the data has shrunk, be sure and remove
		 * the old extension file, if it's there
		 */
		(void) unlink(final_name);
	} else {
		if (!(extension = safe_fopen(final_name, "w+")) ||
		    !fwrite(mem, size, 1, extension)) 
		{
		    sys_msg(debug, LOG_ALERT, "cannot write temporary file: %m");
		}
		(void) safe_fclose(extension);
	}
	(void) xdr_long(&xdr, &zero);
	xdr_destroy(&xdr);
done:
	MM_FREE(final_name);
	return (status);
}

/*
 * Returns the size of a file
 */
static long
fsize(FILE *f)
{
	long pos;
	long end;

	pos = ftell(f);
	fseek(f, 0, 2);
	end = ftell(f);
	fseek(f, pos, 0);
	return (end);
}


#include <sys/dir.h>
#define strmatch(s1, s2) (strncmp(s1, s2, strlen(s2)) == 0)

/*
 * Transaction cleanup, performed at startup
 */
static void
transact_cleanup(file_handle *handle)
{
 	DIR *dp;
	struct direct *d;
	long id, size, trans_code, trans_code_2;
	char *fname;
	union {
		long id;
		char buf[DFL_BLOCKSIZE];
	} buf;
	XDR xdr;
	FILE *wonk;
	void *mem;

	/* Remove old cruft */
	socket_lock();
	dp = opendir(handle->transact_dir);
	socket_unlock();
	if (dp == NULL) {
		sys_msg(debug, LOG_ALERT, "cannot read transaction directory");
	}
	while (d = readdir(dp)) {
		fname = db_mkname(handle, d->d_name, -1);
		if (strmatch(d->d_name, TRANSACT_INPROGRESS_OLD)) {
			/* Leftover from old transaction system, nuke it. */
			(void) unlink(fname);
		} else if (strmatch(d->d_name, TRANSACT_TEMP)) {
			/* Transaction never started, just nuke it. */
			(void) unlink(fname);
		}
		MM_FREE(fname);
	}
	socket_lock();
	closedir(dp);
	socket_unlock();

	/* Check if there's a transaction pending. */
	(void) fseek(handle->transaction, 0, SEEK_SET);
	xdrstdio_create(&xdr, handle->transaction, XDR_DECODE);
	if (xdr_long(&xdr, &trans_code) && trans_code && 
	    xdr_long(&xdr, &size) && xdr_long(&xdr, &id))
	{
	    mem = malloc(size);
	    if (xdr_opaque(&xdr, mem, size)&&xdr_long(&xdr, &trans_code_2)
		&& (trans_code == trans_code_2))
	    {
		fname = db_mkname(handle, TRANSACT_FINAL, id);
		/* Sanity check */
		if (size > handle->blocksize) {
		    if (!(wonk = safe_fopen(fname, "w+"))) {
			sys_msg(debug, LOG_ALERT, "cannot open file %s: %m", fname);
		    }
		    if (!fwrite(mem, size, 1, wonk)) {
			sys_msg(debug, LOG_ALERT, "cannot write file %s: %m", fname);
		    }
		    fflush(wonk);
		    fsync(fileno(wonk));
		    safe_fclose(wonk);
		} else {
		  MM_ZERO(&buf);
		  bcopy(mem, buf.buf, size);
		  if ((buf.id == htonl(DB_FREE)) || (buf.id == htonl(id))) {
		      if (fseek(handle->db, id * handle->blocksize, 0) != 0) {
			  sys_msg(debug, LOG_ALERT, "cannot seek transaction record: %m");
		      }
		      if (fwrite(buf.buf,handle->blocksize,1,handle->db)!=1) {
			  sys_msg(debug, LOG_ALERT, "cannot write transaction record: %m");
		    }
		      fflush(handle->db);
		      fsync(fileno(handle->db));
		      (void) unlink(fname);
		  }
		}
		MM_FREE(fname);
	    }
	    free(mem);
	}
	xdr_destroy(&xdr);
	fseek(handle->transaction, 0, SEEK_SET);
	ftruncate(fileno(handle->transaction), 0);
	fsync(fileno(handle->transaction));
	
	/*
	 * Remove any checksum transaction
	 */
	fname = db_mkname(handle, TRANSACT_CHECKSUM_INPROGRESS, -1);
	(void)unlink(fname);
	MM_FREE(fname);
}
