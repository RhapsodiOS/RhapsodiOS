/*
 * Copyright (c) 2017 The DragonFly Project.  All rights reserved.
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

#include "hammer_util.h"

/*
 * Rhapsody has no uuid(3).  These work directly on the on-disk
 * (little-endian) hammer_uuid_t.  Only the HAMMER filesystem-type name is
 * known to uuid_name_lookup.
 */
static const char Hammer_FSType_String[] = "61dc63ac-6e38-11dc-8513-01301bb8a9f5";

void hammer_uuid_create(hammer_uuid_t *uuid)
{
	static int seeded;
	unsigned char b[16];
	int fd, i;

	fd = open("/dev/random", O_RDONLY);
	if (fd < 0 || read(fd, b, sizeof(b)) != sizeof(b)) {
		if (!seeded) {
			srandom((unsigned)time(NULL) ^ ((unsigned)getpid() << 16));
			seeded = 1;
		}
		for (i = 0; i < 16; ++i)
			b[i] = random() & 0xff;
	}
	if (fd >= 0)
		close(fd);
	uuid->time_low = hmk32(b[0] | b[1] << 8 | b[2] << 16 | (uint32_t)b[3] << 24);
	uuid->time_mid = hmk16(b[4] | b[5] << 8);
	uuid->time_hi_and_version = hmk16(((b[6] | b[7] << 8) & 0x0fff) | 0x4000);
	uuid->clock_seq_hi_and_reserved = (b[8] & 0x3f) | 0x80;
	uuid->clock_seq_low = b[9];
	bcopy(b + 10, uuid->node, 6);
}

int hammer_uuid_from_string(const char *str, hammer_uuid_t *uuid)
{
	unsigned int tl, tm, th, ch, cl, n[6];
	int i;

	if (str == NULL || strlen(str) != 36 ||
	    sscanf(str, "%8x-%4x-%4x-%2x%2x-%2x%2x%2x%2x%2x%2x",
		   &tl, &tm, &th, &ch, &cl,
		   &n[0], &n[1], &n[2], &n[3], &n[4], &n[5]) != 11)
		return(-1);
	uuid->time_low = hmk32(tl);
	uuid->time_mid = hmk16(tm);
	uuid->time_hi_and_version = hmk16(th);
	uuid->clock_seq_hi_and_reserved = ch;
	uuid->clock_seq_low = cl;
	for (i = 0; i < 6; ++i)
		uuid->node[i] = n[i];
	return(0);
}

int hammer_uuid_to_string(const hammer_uuid_t *uuid, char **str)
{
	*str = malloc(37);
	if (*str == NULL)
		return(-1);
	snprintf(*str, 37, "%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",
		 (unsigned)hget32(uuid->time_low), hget16(uuid->time_mid),
		 hget16(uuid->time_hi_and_version),
		 uuid->clock_seq_hi_and_reserved, uuid->clock_seq_low,
		 uuid->node[0], uuid->node[1], uuid->node[2],
		 uuid->node[3], uuid->node[4], uuid->node[5]);
	return(0);
}

int hammer_uuid_name_lookup(hammer_uuid_t *uuid, const char *str)
{
	if (strcmp(str, HAMMER_FSTYPE_STRING) != 0)
		return(-1);
	return(hammer_uuid_from_string(Hammer_FSType_String, uuid));
}

int hammer_uuid_compare(const hammer_uuid_t *uuid1, const hammer_uuid_t *uuid2)
{
	return(bcmp(uuid1, uuid2, sizeof(*uuid1)) != 0);
}
