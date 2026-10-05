/* Tests of the exported production disk contract, with independent LE bytes. */
#include <sys/types.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include "ext2_disk.h"
#include "ext2_bitmap.h"

#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #x); exit(1); \
} } while (0)

/* Fixture writers intentionally do not call production codecs. */
static void fixture16(unsigned char *p, unsigned v)
{ p[0] = v & 255; p[1] = (v >> 8) & 255; }
static void fixture32(unsigned char *p, u_int32_t v)
{ p[0] = v & 255; p[1] = (v >> 8) & 255;
  p[2] = (v >> 16) & 255; p[3] = (v >> 24) & 255; }
static void super_fixture(unsigned char *p, unsigned shift)
{
    unsigned i;
    memset(p, 0, 1024);
    fixture32(p + 0, 128); fixture32(p + 4, 1024);
    fixture32(p + 12, 512); fixture32(p + 16, 100);
    fixture32(p + 20, shift == 0 ? 1 : 0);
    fixture32(p + 24, shift); fixture32(p + 28, shift);
    fixture32(p + 32, 1024); fixture32(p + 36, 1024);
    fixture32(p + 40, 128);
    fixture32(p + 44, 0x12345678); fixture32(p + 48, 0x10203040);
    fixture16(p + 52, 0x1234); fixture16(p + 54, 0x2345);
    fixture16(p + 60, 2); fixture16(p + 62, 0x3456);
    fixture32(p + 64, 0x23456789); fixture32(p + 68, 0x3456789a);
    fixture32(p + 72, 0x456789ab); fixture16(p + 80, 0x4567);
    fixture16(p + 82, 0x5678); fixture16(p + 90, 0x6789);
    fixture32(p + 200, 0x56789abc);
    fixture16(p + 56, 0xef53); fixture16(p + 58, 1);
    fixture32(p + 76, 1); fixture32(p + 84, 11);
    fixture16(p + 88, 128); fixture32(p + 96, 2);
    fixture32(p + 100, 1);
    for (i = 104; i < 200; i++) p[i] = (unsigned char)(i ^ 0x5a);
    for (i = 204; i < 1024; i++) p[i] = (unsigned char)(i ^ 0xa5);
}

/* Catches profile widening, wrong endianness, or destruction of opaque bytes. */
static void test_super_profile(void)
{
    unsigned char unaligned[1025], encoded[1024];
    struct ext2fs es;
    unsigned shift;
    for (shift = 0; shift < 3; shift++) {
        super_fixture(unaligned + 1, shift);
        CHECK(ext2_super_decode(unaligned + 1, 1024, &es) == 0);
        CHECK(es.e2fs_magic == 0xef53);
        CHECK(es.e2fs_mtime == 0x12345678 && es.e2fs_wtime == 0x10203040);
        CHECK(es.e2fs_mnt_count == 0x1234 && es.e2fs_max_mnt_count == 0x2345);
        CHECK(es.e2fs_beh == 2 && es.e2fs_minrev == 0x3456);
        CHECK(es.e2fs_lastfsck == 0x23456789 && es.e2fs_fsckintv == 0x3456789a);
        CHECK(es.e2fs_creator == 0x456789ab && es.e2fs_ruid == 0x4567);
        CHECK(es.e2fs_rgid == 0x5678 && es.e2fs_block_group_nr == 0x6789);
        CHECK(es.e2fs_algo == 0x56789abc);
        CHECK(es.e2fs_features_compat == 0);
        CHECK(es.e2fs_features_incompat == 2);
        CHECK(es.e2fs_features_rocompat == 1);
        CHECK(es.e2fs_inode_size == 128 && es.e2fs_first_ino == 11);
        CHECK(ext2_validate_super(&es, (u_int64_t)1024 * (1024U << shift), 1) == 0);
        ext2_super_encode(&es, encoded);
        CHECK(memcmp(encoded, unaligned + 1, 1024) == 0);
        ext2_super_encode(&es, &es);
        CHECK(memcmp(&es, unaligned + 1, 1024) == 0);
        CHECK(ext2_super_decode(&es, 1024, &es) == 0);
        CHECK(es.e2fs_magic == 0xef53 && es.e2fs_bcount == 1024);
    }
    super_fixture(encoded, 0);
    CHECK(ext2_super_decode(encoded, 1024, &es) == 0);
    es.e2fs_rev = 0; es.e2fs_inode_size = 256; es.e2fs_first_ino = 99;
    CHECK(ext2_validate_super(&es, 1048576, 1) == 0);
    es.e2fs_rev = 1; es.e2fs_inode_size = 256;
    CHECK(ext2_validate_super(&es, 1048576, 0) != 0);
    es.e2fs_inode_size = 128;
    CHECK(ext2_validate_super(&es, 1048576, 0) != 0);
    es.e2fs_first_ino = 11; es.e2fs_rev = 2;
    CHECK(ext2_validate_super(&es, 1048576, 0) != 0);
    es.e2fs_rev = 1; es.e2fs_features_compat = 4;
    CHECK(ext2_validate_super(&es, 1048576, 0) != 0);
    es.e2fs_features_compat = 0; es.e2fs_features_incompat = 4;
    CHECK(ext2_validate_super(&es, 1048576, 0) != 0);
    es.e2fs_features_incompat = 2; es.e2fs_features_rocompat = 2;
    CHECK(ext2_validate_super(&es, 1048576, 0) != 0);
    es.e2fs_features_rocompat = 1; es.e2fs_state = 0;
    CHECK(ext2_validate_super(&es, 1048576, 1) != 0);
    CHECK(ext2_validate_super(&es, 1048576, 0) == 0);
    es.e2fs_state = 3;
    CHECK(ext2_validate_super(&es, 1048576, 1) != 0);
    puts("test_super_profile: PASS");
}

/* Catches reading a short or unaligned external superblock without bounds. */
static void test_short_super(void)
{
    unsigned char raw[1024]; struct ext2fs es;
    super_fixture(raw, 0);
    CHECK(ext2_super_decode(raw, 1023, &es) == EINVAL);
    CHECK(ext2_super_decode(raw, 0, &es) == EINVAL);
    CHECK(ext2_super_decode(NULL, 1024, &es) == EINVAL);
    CHECK(ext2_super_decode(raw, 1024, NULL) == EINVAL);
    puts("test_short_super: PASS");
}

/* Catches shift/sector overflow, impossible tables, and incomplete bounds. */
static void test_bad_geometry(void)
{
    unsigned char raw[1024]; struct ext2fs base, es;
    super_fixture(raw, 0);
    CHECK(ext2_super_decode(raw, 1024, &base) == 0);
    CHECK(ext2_validate_super(&base, 0, 0) != 0);
    CHECK(ext2_validate_super(&base, 1048575, 0) != 0);
#define BAD(field, value) do { es = base; es.field = (value); \
    CHECK(ext2_validate_super(&es, (u_int64_t)0xffffffffffffffffULL, 0) != 0); } while (0)
    BAD(e2fs_magic, 0); BAD(e2fs_log_bsize, 31); BAD(e2fs_log_bsize, 3);
    BAD(e2fs_bcount, 0); BAD(e2fs_bcount, 0xffffffffU);
    BAD(e2fs_bpg, 0); BAD(e2fs_bpg, 8193); BAD(e2fs_bpg, 1);
    BAD(e2fs_fsize, 1); BAD(e2fs_fpg, 512);
    BAD(e2fs_ipg, 0); BAD(e2fs_ipg, 8193); BAD(e2fs_ipg, 129);
    BAD(e2fs_icount, 0); BAD(e2fs_icount, 129); BAD(e2fs_icount, 10);
    BAD(e2fs_first_dblock, 0); BAD(e2fs_fbcount, 1025);
    BAD(e2fs_ficount, 129); BAD(e2fs_rbcount, 1025);
#undef BAD
    /* Second group cannot contain its inode table. */
    es = base; es.e2fs_bcount = 1026; es.e2fs_icount = 256;
    CHECK(ext2_validate_super(&es, 1050624, 0) != 0);
    puts("test_bad_geometry: PASS");
}

/* Catches scalar swap loss, double pointer swaps, and incorrect directory bytes. */
static void test_metadata_byte_order(void)
{
    unsigned char raw[128], encoded[128], bytes[9];
    struct ext2fs_dinode disk, host;
    struct ext2_gd gd_disk, gd_host;
    u_int32_t ptr;
    unsigned i;
    for (i = 0; i < 128; i++) raw[i] = (unsigned char)(i ^ 0xa5);
    fixture16(raw, 0x81a4); fixture16(raw + 2, 0x1234);
    fixture32(raw + 4, 0x12345678); fixture16(raw + 24, 0x4321);
    fixture32(raw + 8, 0x10203040); fixture32(raw + 12, 0x20304050);
    fixture32(raw + 16, 0x30405060); fixture32(raw + 20, 0x40506070);
    fixture32(raw + 32, 0x50607080); fixture32(raw + 100, 0x60708090);
    fixture32(raw + 104, 0x708090a0); fixture32(raw + 108, 0x8090a0b0);
    fixture32(raw + 112, 0x90a0b0c0);
    fixture16(raw + 26, 3); fixture32(raw + 28, 0x10203040);
    memcpy(&disk, raw, 128); memset(&host, 0x55, 128);
    e2fs_iload(&disk, &host);
    CHECK(host.e2di_mode == 0x81a4 && host.e2di_uid == 0x1234);
    CHECK(host.e2di_size == 0x12345678 && host.e2di_gid == 0x4321);
    CHECK(host.e2di_nlink == 3 && host.e2di_nblock == 0x10203040);
    CHECK(host.e2di_atime == 0x10203040 && host.e2di_ctime == 0x20304050);
    CHECK(host.e2di_mtime == 0x30405060 && host.e2di_dtime == 0x40506070);
    CHECK(host.e2di_flags == 0x50607080 && host.e2di_gen == 0x60708090);
    CHECK(host.e2di_facl == 0x708090a0 && host.e2di_dacl == 0x8090a0b0);
    CHECK(host.e2di_faddr == 0x90a0b0c0);
    CHECK(memcmp(host.e2di_blocks, raw + 40, 60) == 0);
    CHECK(memcmp(&host.e2di_linux_reserved1, raw + 36, 4) == 0);
    CHECK(memcmp(&host.e2di_nfrag, raw + 116, 12) == 0);
    e2fs_isave(&host, &disk); memcpy(encoded, &disk, 128);
    CHECK(memcmp(raw, encoded, 128) == 0);
    e2fs_iload(&disk, &disk); e2fs_isave(&disk, &disk);
    CHECK(memcmp(raw, &disk, 128) == 0);
    /* Inline symlink data is an opaque byte string, including NUL. */
    memcpy(raw + 40, "a/b/c\0sentinel", 14); fixture16(raw, 0xa1ff);
    memcpy(&disk, raw, 128); e2fs_iload(&disk, &host);
    CHECK(memcmp(host.e2di_blocks, raw + 40, 60) == 0);
    e2fs_isave(&host, &disk); CHECK(memcmp(&disk, raw, 128) == 0);
    for (i = 0; i < 32; i++) raw[i] = (unsigned char)(i ^ 0x69);
    fixture32(raw, 0x12345678); fixture32(raw + 4, 0x10203040);
    fixture32(raw + 8, 0x50607080); fixture16(raw + 12, 321);
    fixture16(raw + 14, 123); fixture16(raw + 16, 45);
    memcpy(&gd_disk, raw, 32); memset(&gd_host, 0x55, 32);
    e2fs_cgload(&gd_disk, &gd_host, 32);
    CHECK(gd_host.ext2bgd_b_bitmap == 0x12345678);
    CHECK(gd_host.ext2bgd_i_bitmap == 0x10203040);
    CHECK(gd_host.ext2bgd_i_tables == 0x50607080);
    CHECK(gd_host.ext2bgd_nbfree == 321 && gd_host.ext2bgd_nifree == 123);
    CHECK(gd_host.ext2bgd_ndirs == 45);
    CHECK(memcmp(&gd_host.reserved, raw + 18, 14) == 0);
    e2fs_cgsave(&gd_host, &gd_disk, 32); CHECK(memcmp(&gd_disk, raw, 32) == 0);
    e2fs_cgload(&gd_disk, &gd_disk, 32); e2fs_cgsave(&gd_disk, &gd_disk, 32);
    CHECK(memcmp(&gd_disk, raw, 32) == 0);
    memset(bytes, 0xcc, sizeof(bytes));
    ext2_put_le32(bytes + 1, 0x12345678); ext2_put_le16(bytes + 5, 0x1200);
    CHECK(bytes[0] == 0xcc && bytes[1] == 0x78 && bytes[2] == 0x56);
    CHECK(bytes[3] == 0x34 && bytes[4] == 0x12);
    CHECK(bytes[5] == 0 && bytes[6] == 0x12 && bytes[7] == 0xcc);
    CHECK(ext2_get_le32(bytes + 1) == 0x12345678);
    CHECK(ext2_get_le16(bytes + 5) == 0x1200);
    /* Directory header fields use production unaligned accessors. */
    ext2_put_le32(bytes + 1, 11); ext2_put_le16(bytes + 5, 12);
    bytes[7] = 1; bytes[8] = 2;
    CHECK(memcmp(bytes + 1, "\x0b\0\0\0\x0c\0\1\2", 8) == 0);
    CHECK(ext2_get_le32(bytes + 1) == 11 && ext2_get_le16(bytes + 5) == 12);
    /* Indirect pointers retain disk order until their point of use. */
    memcpy(&ptr, "\x78\x56\x34\x12", 4); CHECK(fs2h32(ptr) == 0x12345678);
    ptr = h2fs32(0x10203040); memcpy(bytes + 1, &ptr, 4);
    CHECK(memcmp(bytes + 1, "\x40\x30\x20\x10", 4) == 0);
    puts("test_metadata_byte_order: PASS");
}

/* Catches word-endian bitmap operations and neighboring-byte corruption. */
static void test_bitmap_boundaries(void)
{
    unsigned bits[] = {0, 7, 8, 31, 32, 8191};
    unsigned char map[1026], before[1026]; unsigned i, bit;
    for (i = 0; i < sizeof(bits) / sizeof(bits[0]); i++) {
        memset(map, 0x5a, sizeof(map)); memset(map + 1, 0, 1024);
        memcpy(before, map, sizeof(map)); bit = bits[i];
        CHECK(ext2_test_bit(bit, map + 1) == 0);
        CHECK(ext2_set_bit(bit, map + 1) == 0);
        CHECK(ext2_test_bit(bit, map + 1) == 1);
        CHECK(ext2_set_bit(bit, map + 1) == 1);
        before[1 + bit / 8] = (unsigned char)(1U << (bit % 8));
        CHECK(memcmp(before, map, sizeof(map)) == 0);
        CHECK(ext2_clear_bit(bit, map + 1) == 1);
        CHECK(ext2_clear_bit(bit, map + 1) == 0);
        before[1 + bit / 8] = 0;
        CHECK(memcmp(before, map, sizeof(map)) == 0);
    }
    puts("test_bitmap_boundaries: PASS");
}

int main(void)
{
    test_super_profile(); test_short_super(); test_bad_geometry();
    test_metadata_byte_order(); test_bitmap_boundaries();
    puts("disk contract: PASS"); return 0;
}
