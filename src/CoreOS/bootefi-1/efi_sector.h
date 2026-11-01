/* Pure arithmetic for reading boot-2's 512-byte sectors from media whose
 * blocks are larger (a CD's 2048).  No EFI calls, so
 * tests/efi_sector_test.c exercises it on the host. */
#ifndef _BOOTEFI_EFI_SECTOR_H_
#define _BOOTEFI_EFI_SECTOR_H_

#include "efi.h"

/* Which media blocks cover 512-byte sectors [secno, secno+nsecs): read
 * *nblocks blocks from *first_block, then sector secno starts *skip_bytes
 * into what was read.  block_size is a power-of-two multiple of 512. */
void efi_sector_span(UINT32 block_size, UINT64 secno, UINT32 nsecs,
                     UINT64 *first_block, UINT32 *nblocks, UINT32 *skip_bytes);

/* 512-byte sector number of the label probe on this disk: 15 for 512-byte
 * media (whole disk), 15 (byte 7680) for 2048-byte media read through
 * efi_sector_span. */
UINT64 efi_cd_label_sector(UINT32 block_size);

#endif /* _BOOTEFI_EFI_SECTOR_H_ */
