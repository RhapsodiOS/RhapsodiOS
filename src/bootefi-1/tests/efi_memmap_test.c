/* Host test for converting the EFI memory map to E820 ranges.  Pure C: no
 * firmware, no boot-2 libraries. */
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "efi.h"
#include "kernBootStruct.h"
#include "efi_memmap.h"

static unsigned char buf[8192];
static UINTN used;

static void reset(void)
{
    memset(buf, 0, sizeof buf);
    used = 0;
}

static void add(UINTN dsize, UINT32 type, UINT64 start, UINT64 end)
{
    EFI_MEMORY_DESCRIPTOR *d = (EFI_MEMORY_DESCRIPTOR *)(buf + used);

    d->Type = type;
    d->PhysicalStart = start;
    d->NumberOfPages = (end - start) / 4096;
    used += dsize;
}

int main(void)
{
    boot_mem_range_t out[BOOT_MEMMAP_MAX];
    int n, i, usable;

    /* QEMU-like map: the 1 MB..0x7fe0000 run is split across three types
     * that all map to E820 type 1, and the last range crosses the cap. */
    reset();
    add(48, EfiConventionalMemory, 0, 0xa0000);
    add(48, EfiBootServicesData, 0x100000, 0x200000);
    add(48, EfiConventionalMemory, 0x200000, 0x7000000);
    add(48, EfiLoaderData, 0x7000000, 0x7fe0000);
    add(48, EfiACPIReclaimMemory, 0x7fe0000, 0x7ff0000);
    add(48, EfiACPIMemoryNVS, 0x7ff0000, 0x8000000);
    add(48, EfiMemoryMappedIO, 0xffe00000ULL, 0x100000000ULL);
    n = efi_to_e820(buf, used, 48, out, BOOT_MEMMAP_MAX);
    assert(n == 5);
    assert(out[0].base == 0 && out[0].end == 0xa0000 && out[0].type == 1);
    assert(out[1].base == 0x100000 && out[1].end == 0x7fe0000 && out[1].type == 1);
    assert(out[2].type == 3 && out[3].type == 4);
    assert(out[4].base == 0xffe00000 && out[4].end == 0xfffff000 && out[4].type == 2);

    /* Wholly above 4 GB is dropped. */
    reset();
    add(48, EfiConventionalMemory, 0x100000, 0x200000);
    add(48, EfiConventionalMemory, 0x100000000ULL, 0x200000000ULL);
    n = efi_to_e820(buf, used, 48, out, BOOT_MEMMAP_MAX);
    assert(n == 1 && out[0].base == 0x100000 && out[0].end == 0x200000);

    /* Unsorted input comes out sorted. */
    reset();
    add(48, EfiACPIMemoryNVS, 0x7ff0000, 0x8000000);
    add(48, EfiConventionalMemory, 0x100000, 0x7ff0000);
    add(48, EfiConventionalMemory, 0, 0xa0000);
    n = efi_to_e820(buf, used, 48, out, BOOT_MEMMAP_MAX);
    assert(n == 3);
    assert(out[0].base == 0 && out[1].base == 0x100000 && out[2].base == 0x7ff0000);
    assert(out[2].type == 4);

    /* A stride of exactly sizeof(EFI_MEMORY_DESCRIPTOR) also works. */
    reset();
    add(sizeof(EFI_MEMORY_DESCRIPTOR), EfiConventionalMemory, 0x100000, 0x200000);
    add(sizeof(EFI_MEMORY_DESCRIPTOR), EfiReservedMemoryType, 0x300000, 0x400000);
    n = efi_to_e820(buf, used, sizeof(EFI_MEMORY_DESCRIPTOR), out, BOOT_MEMMAP_MAX);
    assert(n == 2 && out[0].type == 1 && out[1].type == 2);
    assert(out[1].base == 0x300000 && out[1].end == 0x400000);

    /* 40 alternating usable/reserved ranges, max 32: all 20 usable kept,
     * then the first 12 reserved in address order. */
    reset();
    for (i = 0; i < 40; i++)
        add(48, (i & 1) ? EfiReservedMemoryType : EfiConventionalMemory,
            0x100000 + (UINT64)i * 0x10000, 0x110000 + (UINT64)i * 0x10000);
    n = efi_to_e820(buf, used, 48, out, BOOT_MEMMAP_MAX);
    assert(n == 32);
    usable = 0;
    for (i = 0; i < n; i++) {
        if (out[i].type == 1)
            usable++;
        if (i)
            assert(out[i].base > out[i - 1].base);
    }
    assert(usable == 20);
    for (i = 0; i < n; i++)
        if (out[i].type == 2)
            assert(out[i].base <= 0x100000 + 23 * 0x10000);

    /* 40 non-adjacent usable ranges, max 32: gives up. */
    reset();
    for (i = 0; i < 40; i++)
        add(48, EfiConventionalMemory,
            0x100000 + (UINT64)i * 0x20000, 0x110000 + (UINT64)i * 0x20000);
    assert(efi_to_e820(buf, used, 48, out, BOOT_MEMMAP_MAX) == 0);

    printf("efi_memmap_test: ok\n");
    return 0;
}
