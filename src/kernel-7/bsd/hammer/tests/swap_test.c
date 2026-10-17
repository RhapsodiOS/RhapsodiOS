/*
 * Byte-order accessors, on-disk structure sizes and CRC vectors.
 * Built with -DHAMMER_TEST_SWAP on a little-endian host this runs the
 * swapping path; it is not ppc runtime evidence.
 */
#include <stdio.h>
#include <string.h>
#include "hammer_disk.h"
#include "hammer_crc.h"

#define CHECK(x) do { if (!(x)) { printf("FAIL: %s\n", #x); return 1; } } while (0)

int
main(void)
{
	hle16_t s;
	hle32_t w;
	hle64_t q;
	unsigned char raw[8];

	CHECK(hget16(hmk16(0x1234)) == 0x1234);
	CHECK(hget32(hmk32(0x11223344)) == 0x11223344);
	CHECK(hget64(hmk64(0x0102030405060708ULL)) == 0x0102030405060708ULL);

#ifndef HAMMER_TEST_SWAP
	/* The stored bytes are little-endian on every real CPU. */
	w = hmk32(0x11223344);
	memcpy(raw, &w, 4);
	CHECK(raw[0] == 0x44 && raw[1] == 0x33 && raw[2] == 0x22 && raw[3] == 0x11);
	q = hmk64(0x0102030405060708ULL);
	memcpy(raw, &q, 8);
	CHECK(raw[0] == 0x08 && raw[7] == 0x01);
	s = hmk16(0xC84E);
	memcpy(raw, &s, 2);
	CHECK(raw[0] == 0x4E && raw[1] == 0xC8);
#else
	/* Forced swap on a little-endian host simulates a big-endian CPU. */
	CHECK(hmk32(0x11223344).le_ == 0x44332211);
	CHECK(hmk16(0xC84E).le_ == 0x4EC8);
	CHECK(hmk64(0x0102030405060708ULL).le_ == 0x0807060504030201ULL);
	(void)s; (void)w; (void)q; (void)raw;
#endif

	/* Wrapper types must not change the on-disk layout. */
	CHECK(sizeof(union hammer_btree_elm) == 64);
	CHECK(sizeof(struct hammer_node_ondisk) == 4096);
	CHECK(sizeof(struct hammer_volume_ondisk) <= HAMMER_MIN_VOL_JUNK);
	CHECK(sizeof(struct hammer_blockmap) == 40);
	CHECK(sizeof(struct hammer_blockmap_layer1) == 32);
	CHECK(sizeof(struct hammer_blockmap_layer2) == 16);
	CHECK(sizeof(struct hammer_inode_data) == 128);
	CHECK(sizeof(hammer_uuid_t) == 16);

	CHECK(iscsi_crc32("123456789", 9) == 0xE3069283);
	CHECK(crc32("123456789", 9) == 0xCBF43926);

	puts("swap_test: PASS");
	return 0;
}
