#ifndef _BOOTEFI_EFI_MEMMAP_H_
#define _BOOTEFI_EFI_MEMMAP_H_

#include "efi.h"

/* boot_mem_range_t comes from kernBootStruct.h, which has no include guard,
 * so callers include it themselves. */

/* Convert a UEFI memory map into sorted, merged E820 ranges.  `map` holds
 * `size` bytes of descriptors laid out `dsize` bytes apart (never
 * sizeof(EFI_MEMORY_DESCRIPTOR)).  Ranges at or above 0xFFFFF000 are
 * dropped and ones crossing it are capped there.  If more than `max`
 * ranges remain, every usable one is kept, then the others in address
 * order.  Returns the count written to `out`, or 0 if the usable ranges
 * alone exceed `max` or the map has more than 128 descriptors -- the
 * kernel treats 0 as "no map". */
int efi_to_e820(const void *map, UINTN size, UINTN dsize,
                boot_mem_range_t *out, int max);

#endif /* _BOOTEFI_EFI_MEMMAP_H_ */
