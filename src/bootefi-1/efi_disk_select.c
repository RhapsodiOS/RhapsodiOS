#include "efi_disk_select.h"

#define MBR_PARTS           446
#define MBR_ENTRY           16
#define FDISK_NEXTNAME      0xA7
#define DISKLABEL           15      /* matches disk.c's DISKLABEL */

#define DP_END_TYPE         0x7F
#define DP_MEDIA_TYPE       0x04
#define DP_MEDIA_HARDDRIVE  0x01

static unsigned long le32(const unsigned char *p)
{
    return (unsigned long)p[0] | ((unsigned long)p[1] << 8) |
           ((unsigned long)p[2] << 16) | ((unsigned long)p[3] << 24);
}

unsigned long efi_label_lba(const unsigned char *mbr)
{
    int n;

    if (mbr[510] != 0x55 || mbr[511] != 0xAA)
        return DISKLABEL;
    for (n = 0; n < 4; n++) {
        const unsigned char *e = mbr + MBR_PARTS + n * MBR_ENTRY;
        if (e[4] == FDISK_NEXTNAME)
            return le32(e + 8) + DISKLABEL;
    }
    return DISKLABEL;
}

/* Bytes before the end node, or 0 for a malformed path. */
static unsigned int dp_body(const unsigned char *dp)
{
    unsigned int off = 0, len;

    while (dp[off] != DP_END_TYPE) {
        len = (unsigned int)dp[off + 2] | ((unsigned int)dp[off + 3] << 8);
        if (len < 4)
            return 0;
        off += len;
    }
    return off;
}

int efi_dp_is_parent(const unsigned char *disk, const unsigned char *part)
{
    unsigned int n = dp_body(disk), i;

    if (n == 0 || dp_body(part) <= n)
        return 0;
    for (i = 0; i < n; i++)
        if (disk[i] != part[i])
            return 0;
    return part[n] == DP_MEDIA_TYPE && part[n + 1] == DP_MEDIA_HARDDRIVE;
}
