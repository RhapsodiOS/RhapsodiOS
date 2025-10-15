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
 * NetInfo serialization routines
 * Copyright (C) 1989 by NeXT, Inc.
 */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <netinfo/ni.h>
#include <errno.h>
#include "ni_globals.h"
#include "ni_serial.h"
#include "mm.h"
#include "system.h"
#include "safe_stdio.h"

#define MALLOC_SLOP	64

/*
 * Decode a NetInfo object from the given file pointer, allocating
 * memory as necessary.
 */
ni_status
ser_decode(
	   FILE *f,
	   long offset,
	   ni_object **obj
	   )
{
	XDR xdr;
	ni_status status;

	xdrstdio_create(&xdr, f, XDR_DECODE);
	if (!xdr_setpos(&xdr, offset)) {
		status = NI_SERIAL;
		goto done;
	}
	MM_ALLOC(*obj);
	MM_ZERO(*obj);
	if (!xdr_ni_object(&xdr, *obj)) {
		MM_FREE(*obj);
		status = NI_SERIAL;
	} else {
		status = NI_OK;
	}
done:
	xdr_destroy(&xdr);
	return (status);
}

/*
 * Encode the given NetInfo object into a file with the given name. 
 * Returns the size and a FILE pointer to the newly created file
 */
ni_status
ser_encode(
	   ni_object *obj,
	   char *fname,
	   long *size,
	   FILE **f
	   )
{
	XDR xdr;

	
	*f = safe_fopen(fname, "w+");
	if (*f == NULL) {
		return (NI_SERIAL);
	}
	xdrstdio_create(&xdr, *f, XDR_ENCODE);
	if (!xdr_ni_object(&xdr, obj)) {
		sys_msg(debug, LOG_ERR, "cannot serialize file: %m");
		xdr_destroy(&xdr);
		safe_fclose(*f);
		unlink(fname);
		return (errno == ENOSPC ? NI_NOSPACE : NI_SERIAL);
	}
	*size = xdr_getpos(&xdr);
	xdr_destroy(&xdr);
	fseek(*f, 0, 0);
	return (NI_OK);
}

/*
** Encode the given NetInfo object into memory.  This routine allocates
** the memory; the caller responsible for freeing it.  Memory address is
** returned in mem and the allocated/data size in size.
** 
** GRS - 12/17/92
*/

ni_status
ser_memencode(
	   ni_object *obj,
	   void **mem,
	   long *size
	   )
{
	XDR xdr;
	ni_status ret;
	
	if ((ret = ser_size(obj, size)) != NI_OK) {
	    return ret;
	}
	*mem = malloc(*size + MALLOC_SLOP);
	xdrmem_create(&xdr, *mem, (u_int) *size, XDR_ENCODE);
	if (!xdr_ni_object(&xdr, obj)) {
		sys_msg(debug, LOG_ERR, "cannot serialize file: %m");
		xdr_destroy(&xdr);
		return NI_SERIAL;
	}
	*size = xdr_getpos(&xdr);
	xdr_destroy(&xdr);
	return NI_OK;
}

/*
 * Compute the byte-size of a property.
 * This is tricky code!
 */
static long
prop_size(
	  ni_property *prop
	  )
{
	long size;
	long len;
	ni_index i;

	/*
	 * sizeof(prop->nip_name)
	 */
	len = strlen(prop->nip_name);
	size = BYTES_PER_XDR_UNIT + RNDUP(len);

	/*
	 * sizeof(prop->nip_val.ninl_len)
	 */
	size += BYTES_PER_XDR_UNIT;

	for (i = 0; i < prop->nip_val.ninl_len; i++) {
		/*
		 * sizeof(prop->nip_val.ninl_val[i])
		 */
		len = strlen(prop->nip_val.ninl_val[i]);
		size += BYTES_PER_XDR_UNIT + RNDUP(len);
	}

	/*
	 * equals the total storage used by the property
	 */
	return (size);
}

/*
 * Compute the byte-size of a NetInfo object
 * This is tricky code too! 
 */
ni_status
ser_size(
	 ni_object *obj,
	 long *size
	 )
{
	ni_index i;

	/*
	 * sizeof(obj->nio_id.nii_object) +
	 * sizeof(obj->nio_id.nii_instance) +
	 * sizeof(obj->nio_parent)
	 */
	*size = 3 * BYTES_PER_XDR_UNIT;

	/*
	 * sizeof(obj->nio_props.nipl_len)
	 */
	*size += BYTES_PER_XDR_UNIT;
	for (i = 0; i < obj->nio_props.nipl_len; i++) {
		/*
		 * sizeof(obj->nio_props.nipl_val[i])
		 */
		*size += prop_size(&obj->nio_props.nipl_val[i]);
	}

	/*
	 * sizeof(obj->nio_children.niil_len)
	 */
	*size += BYTES_PER_XDR_UNIT;

	/*
	 * sizeof(obj->nio_children.niil_val)
	 */
	*size += (BYTES_PER_XDR_UNIT * obj->nio_children.niil_len);

	/*
	 * equals the total size of the object
	 */
	return (NI_OK); /* returns a status for historical reasons */
}

/*
 * Fast-encoding does not worry about crash-recovery, it just serializes
 * directly into the file (no temp file).  Only used for database tranfers.
 */
ni_status
ser_fastencode(
	       FILE *f,
	       ni_object *obj
	       )
{
	XDR xdr;
	ni_status status;

	xdrstdio_create(&xdr, f, XDR_ENCODE);
	if (!xdr_ni_object(&xdr, obj)) {
		status = NI_NOSPACE;
	} else {
		status = NI_OK;
	}
	xdr_destroy(&xdr);
	return (status);
}

/*
 * Free a NetInfo object
 */
ni_status
ser_free(
	 ni_object *obj
	 )
{
	xdr_free(xdr_ni_object, (void *)obj);
	MM_FREE(obj);
	return (NI_OK);
}


