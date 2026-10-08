/* Direct swap characterization on a little-endian host, not PPC evidence. */
#include <stdio.h>
#include <string.h>
#include "ext2_fs.h"
#include "ext2fs_dinode.h"
void e2fs_cg_bswap(struct ext2_gd *, struct ext2_gd *, int);
void e2fs_i_bswap(struct ext2fs_dinode *, struct ext2fs_dinode *);
void e2fs_sb_bswap(struct ext2fs *, struct ext2fs *);
#define CHECK(x) do { if (!(x)) { printf("FAIL: %s\n", #x); return 1; } } while (0)
int main(void)
{
    struct ext2_gd a[2], b[2]; struct ext2fs_dinode i, j;
    struct ext2fs s, t;
    CHECK(ext2_bswap64(0x0102030405060708ULL) == 0x0807060504030201ULL);
    memset(a, 0xa5, sizeof(a)); memset(b, 0x5a, sizeof(b));
    a[0].ext2bgd_b_bitmap = 0x12345678; a[1].ext2bgd_ndirs = 0x1234;
    e2fs_cg_bswap(a, b, sizeof(a));
    CHECK(b[0].ext2bgd_b_bitmap == 0x78563412);
    CHECK(b[1].ext2bgd_ndirs == 0x3412);
    CHECK(memcmp(&a[0].reserved, &b[0].reserved, 14) == 0);
    CHECK(memcmp(&a[1].reserved, &b[1].reserved, 14) == 0);
    e2fs_cg_bswap(b, b, sizeof(b)); CHECK(memcmp(a, b, sizeof(a)) == 0);
    memset(&i, 0xa5, sizeof(i)); memset(&j, 0x5a, sizeof(j));
    i.e2di_mode = 0x81a4; i.e2di_size = 0x12345678;
    e2fs_i_bswap(&i, &j);
    CHECK(j.e2di_mode == 0xa481 && j.e2di_size == 0x78563412);
    CHECK(memcmp(&i.e2di_linux_reserved1, &j.e2di_linux_reserved1, 4) == 0);
    CHECK(memcmp(i.e2di_blocks, j.e2di_blocks, 60) == 0);
    CHECK(memcmp(&i.e2di_nfrag, &j.e2di_nfrag, 12) == 0);
    e2fs_i_bswap(&j, &j); CHECK(memcmp(&i, &j, sizeof(i)) == 0);
    memset(&s, 0xa5, sizeof(s)); memset(&t, 0x5a, sizeof(t));
    s.e2fs_magic = 0xef53; s.e2fs_bcount = 0x12345678;
    e2fs_sb_bswap(&s, &t);
    CHECK(t.e2fs_magic == 0x53ef && t.e2fs_bcount == 0x78563412);
    CHECK(memcmp(s.e2fs_uuid, t.e2fs_uuid, 16) == 0);
    CHECK(memcmp(s.e2fs_vname, t.e2fs_vname, 16) == 0);
    CHECK(memcmp(&s.pad1, &t.pad1, 818) == 0);
    e2fs_sb_bswap(&t, &t); CHECK(memcmp(&s, &t, sizeof(s)) == 0);
    puts("direct swap preservation: PASS"); return 0;
}
