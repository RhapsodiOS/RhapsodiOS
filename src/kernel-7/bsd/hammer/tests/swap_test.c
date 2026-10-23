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

	/*
	 * An UNDO FIFO record laid down as hammer_generate_undo() does:
	 * DragonFly's field offsets, little-endian bytes, and a head CRC
	 * that verifies.  The inode fields the write path stores too.
	 */
	{
		union {
			unsigned char b[64];
			struct hammer_fifo_undo u;
		} rec;
		struct hammer_fifo_tail *tail;
		struct hammer_inode_data ino;
		unsigned char *ib = (unsigned char *)&ino;

		CHECK(offsetof(struct hammer_fifo_head, hdr_size) == 4);
		CHECK(offsetof(struct hammer_fifo_head, hdr_seq) == 8);
		CHECK(offsetof(struct hammer_fifo_head, hdr_crc) == 12);
		CHECK(offsetof(struct hammer_fifo_undo, undo_offset) == 16);
		CHECK(offsetof(struct hammer_fifo_undo, undo_data_bytes) == 24);
		CHECK(sizeof(struct hammer_fifo_undo) == 32);
		CHECK(sizeof(struct hammer_fifo_tail) == 8);

		memset(&rec, 0xAA, sizeof(rec));
		rec.u.head.hdr_signature = hmk16(HAMMER_HEAD_SIGNATURE);
		rec.u.head.hdr_type = hmk16(HAMMER_HEAD_TYPE_UNDO);
		rec.u.head.hdr_size = hmk32(64);
		rec.u.head.hdr_seq = hmk32(0x01020304);
		rec.u.head.hdr_crc = hmk32(0);
		rec.u.undo_offset = hmk64(0x2000000000123400ULL);
		rec.u.undo_data_bytes = hmk32(16);
		tail = (struct hammer_fifo_tail *)(rec.b + 64 - sizeof(*tail));
		tail->tail_signature = hmk16(HAMMER_TAIL_SIGNATURE);
		tail->tail_type = hmk16(HAMMER_HEAD_TYPE_UNDO);
		tail->tail_size = hmk32(64);
		hammer_crc_set_fifo_head(HAMMER_VOL_VERSION_SEVEN,
					 &rec.u.head, 64);
#ifndef HAMMER_TEST_SWAP
		CHECK(rec.b[0] == (HAMMER_HEAD_SIGNATURE & 0xFF) &&
		      rec.b[1] == (HAMMER_HEAD_SIGNATURE >> 8));
		CHECK(rec.b[8] == 0x04 && rec.b[11] == 0x01);
		CHECK(rec.b[16] == 0x00 && rec.b[17] == 0x34 &&
		      rec.b[18] == 0x12 && rec.b[23] == 0x20);
		CHECK(rec.b[24] == 16 && rec.b[25] == 0);
		CHECK(rec.b[60] == 64 && rec.b[61] == 0);
#endif
		CHECK(hammer_crc_test_fifo_head(HAMMER_VOL_VERSION_SEVEN,
						&rec.u.head, 64));
		rec.b[20] ^= 1;
		CHECK(!hammer_crc_test_fifo_head(HAMMER_VOL_VERSION_SEVEN,
						 &rec.u.head, 64));

		CHECK(offsetof(struct hammer_inode_data, parent_obj_id) == 24);
		CHECK(offsetof(struct hammer_inode_data, nlinks) == 72);
		CHECK(offsetof(struct hammer_inode_data, size) == 80);
		CHECK(offsetof(struct hammer_inode_data, mtime) == 112);
		memset(&ino, 0, sizeof(ino));
		ino.size = hmk64(0x0000000100000002ULL);
		ino.nlinks = hmk64(3);
		ino.mode = hmk16(0100644);
#ifndef HAMMER_TEST_SWAP
		CHECK(ib[80] == 2 && ib[84] == 1 && ib[72] == 3);
		CHECK(ib[2] == 0xA4 && ib[3] == 0x81);
#endif
		CHECK(hget64(ino.size) == 0x0000000100000002ULL);
		CHECK(hget16(ino.mode) == 0100644);
		(void)ib;
	}

	CHECK(iscsi_crc32("123456789", 9) == 0xE3069283);
	CHECK(crc32("123456789", 9) == 0xCBF43926);

	puts("swap_test: PASS");
	return 0;
}
