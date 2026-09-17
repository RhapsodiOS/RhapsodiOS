/* malloc/free for boot-2's reused sources, and the fixed-address memory
 * reservations the loader depends on (moved here from the Task 3 spike).
 */
#include "efi.h"

void *malloc(int size)
{
    void *p = 0;

    if (size <= 0)
        return 0;
    if (EFI_ERROR(gBS->AllocatePool(EfiLoaderData, (UINTN)size, &p)))
        return 0;
    return p;
}

void free(char *p)
{
    if (p)
        gBS->FreePool(p);
}

/* Not called by any boot-2 source directly; clang can lower a large
 * struct/array assignment to a call to memmove() (seen from sys.c), and
 * nothing in this freestanding build provides one. */
void *memmove(void *dst, const void *src, unsigned long len)
{
    char *d = (char *)dst;
    const char *s = (const char *)src;

    if (d == s || len == 0)
        return dst;
    if (d < s) {
        while (len--)
            *d++ = *s++;
    } else {
        d += len;
        s += len;
        while (len--)
            *--d = *--s;
    }
    return dst;
}

struct fixed_range { EFI_PHYSICAL_ADDRESS start; EFI_PHYSICAL_ADDRESS end; };

/* Both ranges were proven grantable by the Task 3 memory spike against this
 * OVMF/qemu combination. The first covers BOOTSTRUCT_ADDR (0x11000, where
 * kernBootStruct lives) through the EISA_CONFIG/intbuf region (0x20000) and
 * on to just under VIDEO_ADDR; the second covers the kernel load range. */
static struct fixed_range ranges[] = {
    { 0x011000, 0x0A0000 },
    { 0x100000, 0x700000 },
};

int efi_reserve_ranges(void)
{
    unsigned i;

    for (i = 0; i < sizeof(ranges) / sizeof(ranges[0]); i++) {
        EFI_PHYSICAL_ADDRESS addr = ranges[i].start;
        UINTN pages = (UINTN)((ranges[i].end - ranges[i].start) / 4096);
        EFI_STATUS st = gBS->AllocatePages(AllocateAddress, EfiLoaderData,
                                           pages, &addr);
        if (EFI_ERROR(st))
            return -1;
    }
    return 0;
}
