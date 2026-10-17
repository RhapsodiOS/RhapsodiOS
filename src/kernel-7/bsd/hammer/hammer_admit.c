/*
 * Copyright (c) 2026 RhapsodiOS.  All rights reserved.
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
 * 3. Neither the name of the copyright holder nor the names of its
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
#include <sys/errno.h>
#include "hammer_disk.h"
#include "hammer_crc.h"
#include "hammer_admit.h"

#define REFUSE(err, msg)	do { *why = (msg); return (err); } while (0)

const char hammer_admit_needs_recovery[] = "volume needs UNDO recovery";

int
hammer_admit_volume(const void *hdr, size_t len, uint64_t device_bytes,
		    const char **why)
{
	const struct hammer_volume_ondisk *v = hdr;
	struct hammer_blockmap *undo;
	uint64_t sig, beg, end;
	uint32_t version;

	*why = NULL;
	if (hdr == NULL || len < sizeof(*v))
		REFUSE(EINVAL, "short volume header");
	if (device_bytes == 0)
		REFUSE(EINVAL, "unknown device size");

	sig = hget64(v->vol_signature);
	if (sig == HAMMER_FSBUF_VOLUME_REV)
		REFUSE(EINVAL, "byte-swapped volume header");
	if (sig != HAMMER_FSBUF_VOLUME)
		REFUSE(EINVAL, "not a HAMMER volume");

	version = hget32(v->vol_version);
	if (version != HAMMER_VOL_VERSION_SEVEN)
		REFUSE(EOPNOTSUPP, "only HAMMER version 7 is supported");
	/*
	 * Upstream newfs_hammer leaves vol_crc 0; the kernel sets it on its
	 * first flush and never checks it.  Treat 0 as "not yet set".
	 */
	if (hget32(v->vol_crc) != 0 &&
	    !hammer_crc_test_volume(version, (hammer_volume_ondisk_t)v))
		REFUSE(EINVAL, "volume header CRC mismatch");

	if (hget32(v->vol_count) != 1 || hget32(v->vol_rootvol) != 0)
		REFUSE(EOPNOTSUPP, "single-volume HAMMER only");
	if ((int32_t)hget32(v->vol_no) != HAMMER_ROOT_VOLNO)
		REFUSE(EOPNOTSUPP, "not the root volume");

	beg = hget64(v->vol_buf_beg);
	end = hget64(v->vol_buf_end);
	if ((beg & HAMMER_BUFMASK64) || (end & HAMMER_BUFMASK64) ||
	    beg < HAMMER_MIN_VOL_JUNK || beg >= end ||
	    (int64_t)beg < 0 || (int64_t)end < 0)
		REFUSE(EINVAL, "bad volume geometry");
	if (end > device_bytes)
		REFUSE(EINVAL, "volume is larger than its device");

	undo = (struct hammer_blockmap *)&v->vol0_blockmap[HAMMER_ZONE_UNDO_INDEX];
	if (hget64(undo->first_offset) != hget64(undo->next_offset))
		REFUSE(EOPNOTSUPP, hammer_admit_needs_recovery);
	return (0);
}
