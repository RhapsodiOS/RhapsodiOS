/* gunzip.c - Alpine Package Keeper (APK)
 *
 * Copyright (C) 2008 Timo Teräs <timo.teras@iki.fi>
 * All rights reserved.
 *
 * This program is free software; you can redistribute it and/or modify it 
 * under the terms of the GNU General Public License version 2 as published
 * by the Free Software Foundation. See http://www.gnu.org/ for details.
 */

#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <zlib.h>

#include "apk_defines.h"
#include "apk_io.h"

struct apk_gzip_istream {
	struct apk_istream is;
	struct apk_bstream *bs;
	z_stream zs;
	int z_err;
	int autoclose;
};

static size_t gz_read(void *stream, void *ptr, size_t size)
{
	struct apk_gzip_istream *gis =
		container_of(stream, struct apk_gzip_istream, is);

	if (gis->z_err == Z_DATA_ERROR || gis->z_err == Z_ERRNO)
		return -1;
	if (gis->z_err == Z_STREAM_END)
		return 0;

	if (ptr == NULL)
		return apk_istream_skip(&gis->is, size);

	gis->zs.avail_out = size;
	gis->zs.next_out  = ptr;

	while (gis->zs.avail_out != 0 && gis->z_err == Z_OK) {
		if (gis->zs.avail_in == 0) {
			gis->zs.avail_in = gis->bs->read(gis->bs, (void **) &gis->zs.next_in);
			if (gis->zs.avail_in < 0) {
				gis->z_err = Z_DATA_ERROR;
				return size - gis->zs.avail_out;
			}
		}

		gis->z_err = inflate(&gis->zs, Z_NO_FLUSH);
	}

	if (gis->z_err != Z_OK && gis->z_err != Z_STREAM_END)
		return -1;

	return size - gis->zs.avail_out;
}

static void gz_close(void *stream)
{
	struct apk_gzip_istream *gis =
		container_of(stream, struct apk_gzip_istream, is);

	inflateEnd(&gis->zs);
	if (gis->autoclose)
		gis->bs->close(gis->bs, NULL, NULL);
	free(gis);
}

/* zlib 1.1.3 (Rhapsody's) cannot unwrap gzip itself: inflateInit2's +16/+32
 * window-bits modes arrived in 1.2.0.  So read past the RFC 1952 header here
 * and inflate the raw deflate data after it.  The trailer is left unread; a
 * bstream closed with a checksum reads the rest of the file itself. */
static int gz_next_byte(struct apk_gzip_istream *gis)
{
	if (gis->zs.avail_in == 0) {
		gis->zs.avail_in = gis->bs->read(gis->bs, (void **) &gis->zs.next_in);
		if ((int) gis->zs.avail_in <= 0) {
			gis->zs.avail_in = 0;
			return -1;
		}
	}
	gis->zs.avail_in--;
	return *gis->zs.next_in++;
}

static int gz_skip_header(struct apk_gzip_istream *gis)
{
	int flags, len, c, i;

	if (gz_next_byte(gis) != 0x1f || gz_next_byte(gis) != 0x8b ||
	    gz_next_byte(gis) != Z_DEFLATED)
		return -1;
	flags = gz_next_byte(gis);
	if (flags < 0 || (flags & 0xe0))
		return -1;
	for (i = 0; i < 6; i++)			/* mtime, xfl, os */
		if (gz_next_byte(gis) < 0)
			return -1;
	if (flags & 0x04) {			/* FEXTRA */
		len = gz_next_byte(gis);
		c = gz_next_byte(gis);
		if (len < 0 || c < 0)
			return -1;
		for (len |= c << 8; len > 0; len--)
			if (gz_next_byte(gis) < 0)
				return -1;
	}
	if (flags & 0x08)			/* FNAME */
		while ((c = gz_next_byte(gis)) != 0)
			if (c < 0)
				return -1;
	if (flags & 0x10)			/* FCOMMENT */
		while ((c = gz_next_byte(gis)) != 0)
			if (c < 0)
				return -1;
	if (flags & 0x02)			/* FHCRC */
		for (i = 0; i < 2; i++)
			if (gz_next_byte(gis) < 0)
				return -1;
	return 0;
}

struct apk_istream *apk_bstream_gunzip(struct apk_bstream *bs, int autoclose)
{
	struct apk_gzip_istream *gis;

	if (bs == NULL)
		return NULL;

	gis = malloc(sizeof(struct apk_gzip_istream));
	if (gis == NULL)
		return NULL;

	*gis = (struct apk_gzip_istream) {
		is: { read: gz_read, close: gz_close },
		bs: bs,
		z_err: 0,
		autoclose: autoclose,
	};

	if (inflateInit2(&gis->zs, -MAX_WBITS) != Z_OK) {
		free(gis);
		return NULL;
	}
	if (gz_skip_header(gis) != 0) {
		inflateEnd(&gis->zs);
		free(gis);
		return NULL;
	}

	return &gis->is;
}

