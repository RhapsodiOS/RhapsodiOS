/* boot-2's disk.c asks for 512-byte sectors; on a CD the media blocks are
 * 2048 bytes, so ebiosread reads the blocks covering the request into a
 * bounce buffer and copies the sectors out from *skip_bytes. */
#include "efi_sector.h"

#define BPS             512
#define DISKLABEL       15      /* matches disk.c's DISKLABEL */

void efi_sector_span(UINT32 block_size, UINT64 secno, UINT32 nsecs,
                     UINT64 *first_block, UINT32 *nblocks, UINT32 *skip_bytes)
{
    UINT32 shift = 0;
    UINT64 last = secno + nsecs - 1;

    /* Shifts, not 64-bit division: the IA32 build has no __aulldiv. */
    while ((BPS << shift) < block_size)
        shift++;
    *first_block = secno >> shift;
    *nblocks = (UINT32)((last >> shift) - *first_block + 1);
    *skip_bytes = (UINT32)(secno & ((1 << shift) - 1)) * BPS;
}

/* A CD label sits at byte 7680 like a whole-disk label, and there is no
 * fdisk table to walk on 2048-byte media, so this is DISKLABEL for both. */
UINT64 efi_cd_label_sector(UINT32 block_size)
{
    return DISKLABEL;
}
