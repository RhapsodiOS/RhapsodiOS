/*
 * Volume-header admission rules for the single-volume, v7-only port.
 */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include "hammer_disk.h"
#include "hammer_crc.h"
#include "hammer_admit.h"

#define CHECK(x) do { if (!(x)) { printf("FAIL line %d: %s\n", __LINE__, #x); return 1; } } while (0)

static union {
	u_int64_t align;
	char bytes[HAMMER_BUFSIZE];
} buf;

#define DEV_BYTES	(2048ULL * 1024 * 1024)

static struct hammer_volume_ondisk *
good(void)
{
	struct hammer_volume_ondisk *v = (struct hammer_volume_ondisk *)buf.bytes;

	memset(&buf, 0, sizeof(buf));
	v->vol_signature = hmk64(HAMMER_FSBUF_VOLUME);
	v->vol_bot_beg = hmk64(HAMMER_MIN_VOL_JUNK);
	v->vol_mem_beg = hmk64(HAMMER_MIN_VOL_JUNK + HAMMER_BOOT_MINBYTES);
	v->vol_buf_beg = hmk64(HAMMER_MIN_VOL_JUNK + HAMMER_BOOT_MINBYTES + HAMMER_MEM_MINBYTES);
	v->vol_buf_end = hmk64(DEV_BYTES & ~HAMMER_BUFMASK64);
	v->vol_no = hmk32(0);
	v->vol_count = hmk32(1);
	v->vol_version = hmk32(HAMMER_VOL_VERSION_SEVEN);
	v->vol_rootvol = hmk32(0);
	v->vol0_blockmap[HAMMER_ZONE_UNDO_INDEX].first_offset = hmk64(HAMMER_ZONE_UNDO);
	v->vol0_blockmap[HAMMER_ZONE_UNDO_INDEX].next_offset = hmk64(HAMMER_ZONE_UNDO);
	return v;
}

static void
seal(struct hammer_volume_ondisk *v)
{
	hammer_crc_set_volume(hget32(v->vol_version), v);
}

static int
admit(u_int64_t dev, size_t len, int want)
{
	const char *why = NULL;
	int error = hammer_admit_volume(buf.bytes, len, dev, &why);

	if (error != want) {
		printf("  got %d want %d (%s)\n", error, want, why ? why : "-");
		return 0;
	}
	return want == 0 || why != NULL;
}

int
main(void)
{
	struct hammer_volume_ondisk *v;

	v = good(); seal(v);
	CHECK(admit(DEV_BYTES, sizeof(buf), 0));

	v = good(); v->vol_signature = hmk64(HAMMER_FSBUF_VOLUME_REV); seal(v);
	CHECK(admit(DEV_BYTES, sizeof(buf), EINVAL));

	v = good(); v->vol_version = hmk32(6); seal(v);
	CHECK(admit(DEV_BYTES, sizeof(buf), EOPNOTSUPP));

	v = good(); v->vol_count = hmk32(2); seal(v);
	CHECK(admit(DEV_BYTES, sizeof(buf), EOPNOTSUPP));

	v = good(); v->vol_no = hmk32(1); seal(v);
	CHECK(admit(DEV_BYTES, sizeof(buf), EOPNOTSUPP));

	v = good(); seal(v); buf.bytes[100] ^= 1;	/* inside vol_label */
	CHECK(admit(DEV_BYTES, sizeof(buf), EINVAL));

	v = good(); seal(v);
	CHECK(admit(DEV_BYTES - HAMMER_BUFSIZE, sizeof(buf), EINVAL));

	v = good(); seal(v);
	CHECK(admit(DEV_BYTES, 512, EINVAL));

	v = good(); seal(v);
	CHECK(admit(0, sizeof(buf), EINVAL));

	v = good();
	v->vol0_blockmap[HAMMER_ZONE_UNDO_INDEX].next_offset =
	    hmk64(HAMMER_ZONE_UNDO + HAMMER_UNDO_ALIGN);
	seal(v);
	CHECK(admit(DEV_BYTES, sizeof(buf), EOPNOTSUPP));

	puts("admit_test: PASS");
	return 0;
}
