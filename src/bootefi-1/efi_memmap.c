#include "kernBootStruct.h"
#include "efi_memmap.h"

#define MEMMAP_SCRATCH  128
#define MEMMAP_TOP      0xFFFFF000UL

static unsigned int efi_e820_type(UINT32 type)
{
    switch (type) {
    case EfiConventionalMemory:
    case EfiBootServicesCode:
    case EfiBootServicesData:
    case EfiLoaderCode:
    case EfiLoaderData:
        return 1;
    case EfiACPIReclaimMemory:
        return 3;
    case EfiACPIMemoryNVS:
        return 4;
    default:
        return 2;
    }
}

int efi_to_e820(const void *map, UINTN size, UINTN dsize,
                boot_mem_range_t *out, int max)
{
    boot_mem_range_t r[MEMMAP_SCRATCH];
    char keep[MEMMAP_SCRATCH];
    const unsigned char *p = (const unsigned char *)map;
    UINTN off;
    int n = 0, i, j, usable = 0, room, count;

    if (dsize < sizeof(EFI_MEMORY_DESCRIPTOR))
        return 0;
    for (off = 0; off + sizeof(EFI_MEMORY_DESCRIPTOR) <= size; off += dsize) {
        const EFI_MEMORY_DESCRIPTOR *d = (const EFI_MEMORY_DESCRIPTOR *)(p + off);
        UINT64 start = d->PhysicalStart;
        UINT64 end = start + d->NumberOfPages * 4096;

        if (start >= MEMMAP_TOP || end <= start)
            continue;
        if (end > MEMMAP_TOP)
            end = MEMMAP_TOP;
        if (n == MEMMAP_SCRATCH)
            return 0;
        r[n].base = (unsigned int)start;
        r[n].end = (unsigned int)end;
        r[n].type = efi_e820_type(d->Type);
        n++;
    }

    /* Insertion sort by base. */
    for (i = 1; i < n; i++) {
        boot_mem_range_t t = r[i];

        for (j = i; j > 0 && r[j - 1].base > t.base; j--)
            r[j] = r[j - 1];
        r[j] = t;
    }

    /* Merge touching ranges of the same type. */
    for (i = 1, j = 0; i < n; i++) {
        if (r[j].end == r[i].base && r[j].type == r[i].type)
            r[j].end = r[i].end;
        else
            r[++j] = r[i];
    }
    n = n ? j + 1 : 0;

    for (i = 0; i < n; i++) {
        keep[i] = (r[i].type == BOOT_MEM_RAM);
        usable += keep[i];
    }
    if (usable > max)
        return 0;

    room = max - usable;
    for (i = 0; i < n; i++) {
        if (!keep[i] && room > 0) {
            keep[i] = 1;
            room--;
        }
    }
    for (i = 0, count = 0; i < n; i++)
        if (keep[i])
            out[count++] = r[i];
    return count;
}
