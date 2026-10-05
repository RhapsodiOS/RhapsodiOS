/* Portable ext2 codecs and the RhapsodiOS supported-volume contract. */
#ifdef _KERNEL
#include <sys/param.h>
#include <sys/systm.h>
#include <sys/errno.h>
#else
#include <errno.h>
#include <string.h>
#endif
#include "ext2_disk.h"

typedef char ext2_super_size_check[(sizeof(struct ext2fs) == 1024) ? 1 : -1];
typedef char ext2_inode_size_check[(sizeof(struct ext2fs_dinode) == 128) ? 1 : -1];
typedef char ext2_group_size_check[(sizeof(struct ext2_gd) == 32) ? 1 : -1];

int
ext2_super_decode(const void *raw, size_t len, struct ext2fs *out)
{
    struct ext2fs disk;
    if (raw == NULL || out == NULL || len < SBSIZE)
        return EINVAL;
    memcpy(&disk, raw, sizeof(disk));
    e2fs_sbload(&disk, out);
    return 0;
}

void
ext2_super_encode(const struct ext2fs *in, void *raw)
{
    struct ext2fs host, disk;
    memcpy(&host, in, sizeof(host));
    e2fs_sbsave(&host, &disk);
    memcpy(raw, &disk, sizeof(disk));
}

u_int16_t
ext2_get_le16(const void *p)
{
    const u_char *b = p;
    return (u_int16_t)((u_int16_t)b[0] | ((u_int16_t)b[1] << 8));
}

u_int32_t
ext2_get_le32(const void *p)
{
    const u_char *b = p;
    return (u_int32_t)b[0] | ((u_int32_t)b[1] << 8) |
        ((u_int32_t)b[2] << 16) | ((u_int32_t)b[3] << 24);
}

void
ext2_put_le16(void *p, u_int16_t v)
{
    u_char *b = p;
    b[0] = (u_char)v; b[1] = (u_char)(v >> 8);
}

void
ext2_put_le32(void *p, u_int32_t v)
{
    u_char *b = p;
    b[0] = (u_char)v; b[1] = (u_char)(v >> 8);
    b[2] = (u_char)(v >> 16); b[3] = (u_char)(v >> 24);
}

int
ext2_validate_super(const struct ext2fs *es, u_int64_t device_bytes,
    int writable)
{
    u_int32_t bsize, sectors, groups, ngdb, ipb, itpg, last, overhead;
    u_int32_t n, factor;
    int backup;
    u_int64_t volume_bytes;

    if (es == NULL || device_bytes == 0 || es->e2fs_magic != E2FS_MAGIC)
        return EINVAL;
    if (es->e2fs_rev > E2FS_REV1 ||
        (es->e2fs_features_compat & ~EXT2F_COMPAT_SUPP) != 0 ||
        (es->e2fs_features_incompat & ~EXT2F_INCOMPAT_SUPP) != 0 ||
        (es->e2fs_features_rocompat & ~EXT2F_ROCOMPAT_SUPP) != 0)
        return EINVAL;
    if (es->e2fs_rev == E2FS_REV1 &&
        (es->e2fs_inode_size != 128 || es->e2fs_first_ino != 11))
        return EINVAL;
    if (writable && es->e2fs_state != E2FS_ISCLEAN)
        return EROFS;

    /* Bound exponents before shifting; ext2 fragments must equal blocks. */
    if (es->e2fs_log_bsize > 2 || es->e2fs_fsize != es->e2fs_log_bsize)
        return EINVAL;
    bsize = 1024U << es->e2fs_log_bsize;
    sectors = bsize / 512;
    if (es->e2fs_first_dblock != (bsize == 1024 ? 1U : 0U) ||
        es->e2fs_bcount <= es->e2fs_first_dblock)
        return EINVAL;
    /* daddr_t is signed 32-bit on both targets, including block end sectors. */
    if (es->e2fs_bcount > 0x80000000U / sectors)
        return EINVAL;
    volume_bytes = (u_int64_t)es->e2fs_bcount * bsize;
    if (volume_bytes > device_bytes)
        return EINVAL;
    if (es->e2fs_bpg == 0 || es->e2fs_bpg > bsize * 8 ||
        es->e2fs_fpg != es->e2fs_bpg || es->e2fs_ipg == 0 ||
        es->e2fs_ipg > bsize * 8 || es->e2fs_icount < 11 ||
        es->e2fs_fbcount > es->e2fs_bcount ||
        es->e2fs_rbcount > es->e2fs_bcount ||
        es->e2fs_ficount > es->e2fs_icount)
        return EINVAL;
    ipb = bsize / 128; /* revision 0 ignores its unused dynamic inode fields */
    if (es->e2fs_ipg % ipb != 0)
        return EINVAL;
    itpg = es->e2fs_ipg / ipb;
    groups = (es->e2fs_bcount - es->e2fs_first_dblock - 1) / es->e2fs_bpg + 1;
    if (groups > 0x7fffffffU || groups > 0xffffffffU / es->e2fs_ipg)
        return EINVAL;
    if (es->e2fs_icount != groups * es->e2fs_ipg)
        return EINVAL;
    ngdb = (groups - 1) / (bsize / sizeof(struct ext2_gd)) + 1;
    if (ngdb > 0x7fffffffU / bsize)
        return EINVAL; /* descriptor buffer allocation uses signed target ints */
    overhead = 2 + itpg;
    if (ngdb > es->e2fs_bpg || overhead >= es->e2fs_bpg ||
        1 + ngdb > es->e2fs_bpg - overhead)
        return EINVAL;
    last = (es->e2fs_bcount - es->e2fs_first_dblock - 1) % es->e2fs_bpg + 1;
    backup = groups <= 2 ||
        (es->e2fs_features_rocompat & EXT2F_ROCOMPAT_SPARSESUPER) == 0;
    /* Recognize a sparse backup without overflowing the upstream power loop. */
    for (factor = 3; !backup && factor <= 7; factor += 2) {
        n = groups - 1;
        while (n != 0 && n % factor == 0)
            n /= factor;
        if (n == 1)
            backup = 1;
    }
    if (backup)
        overhead += 1 + ngdb;
    if (last < overhead)
        return EINVAL;
    return 0;
}
