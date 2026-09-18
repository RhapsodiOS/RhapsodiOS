/* malloc/free for boot-2's reused sources, and the fixed-address memory
 * reservations the loader depends on (moved here from the Task 3 spike).
 */
#include "efi.h"
#include "kernBootStruct.h"

extern int efi_disk_count(void);

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

/* Not called by any boot-2 source directly under Task 5's build, but
 * load.c's LC_SEGMENT handling and this task's own kernel-load bookkeeping
 * both call bzero(). libsa/memset.c (the usual provider) is excluded from
 * this build -- see the Task 5 report -- so, as with memmove() above,
 * supply a plain C implementation here rather than pull in the
 * non-compiling original. */
int bzero(char *b, int length)
{
    while (length-- > 0)
        *b++ = 0;
    return 0;
}

/* load.c's openfile() falls back to these for a ".rcz"-compressed kernel
 * when a plain open() fails. This loader never calls openfile() -- load_
 * kernel() in efi_main.c opens mach_kernel directly, which is never
 * compressed -- but openfile() is compiled into the same object file as
 * loadprog(), so the linker still needs these symbols resolved. Stubs
 * only; the real rcz decompressor (src/boot-2/i386/rcz) is not part of
 * this build. */
int rcz_file_size(int in_fd)
{
    return -1;
}

int rcz_decompress_file(int in_fd, unsigned char *out)
{
    return -1;
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

/* Memory we reserved ourselves counts as usable: the kernel owns it next. */
static int efi_usable(UINT32 type)
{
    return type == EfiConventionalMemory
        || type == EfiBootServicesCode
        || type == EfiBootServicesData
        || type == EfiLoaderCode
        || type == EfiLoaderData;
}

static const char *efi_type_name(UINT32 type)
{
    switch (type) {
    case EfiReservedMemoryType:      return "Reserved";
    case EfiLoaderCode:              return "LoaderCode";
    case EfiLoaderData:              return "LoaderData";
    case EfiBootServicesCode:        return "BootServicesCode";
    case EfiBootServicesData:        return "BootServicesData";
    case EfiRuntimeServicesCode:     return "RuntimeServicesCode";
    case EfiRuntimeServicesData:     return "RuntimeServicesData";
    case EfiConventionalMemory:      return "Conventional";
    case EfiUnusableMemory:          return "Unusable";
    case EfiACPIReclaimMemory:       return "ACPIReclaim";
    case EfiACPIMemoryNVS:           return "ACPIMemoryNVS";
    case EfiMemoryMappedIO:          return "MMIO";
    case EfiMemoryMappedIOPortSpace: return "MMIOPortSpace";
    case EfiPalCode:                 return "PalCode";
    case EfiPersistentMemory:        return "Persistent";
    default:                         return "?";
    }
}

/* Diagnostic only: dump every descriptor in the live map, not just the
 * sub-8MB slice spike_memmap.c looked at. */
static void efi_dump_map(EFI_MEMORY_DESCRIPTOR *map, UINTN size, UINTN dsize)
{
    UINTN off;

    printf("EFI memory map:\n");
    for (off = 0; off < size; off += dsize) {
        EFI_MEMORY_DESCRIPTOR *d =
            (EFI_MEMORY_DESCRIPTOR *)((char *)map + off);
        UINT64 start = d->PhysicalStart;
        UINT64 end = start + d->NumberOfPages * 4096;
        printf("  type %d (%s) start %x pages %x end %x\n",
               (int)d->Type, efi_type_name(d->Type), (unsigned)start,
               (unsigned)d->NumberOfPages, (unsigned)end);
    }
}

/* Find the descriptor covering physical address addr, if any. The map is
 * not guaranteed sorted by PhysicalStart, so this scans the whole thing. */
static EFI_MEMORY_DESCRIPTOR *efi_desc_at(EFI_MEMORY_DESCRIPTOR *map,
                                           UINTN size, UINTN dsize,
                                           UINT64 addr)
{
    UINTN off;

    for (off = 0; off < size; off += dsize) {
        EFI_MEMORY_DESCRIPTOR *d =
            (EFI_MEMORY_DESCRIPTOR *)((char *)map + off);
        UINT64 start = d->PhysicalStart;
        UINT64 end = start + d->NumberOfPages * 4096;
        if (addr >= start && addr < end)
            return d;
    }
    return 0;
}

/* KERNBOOTSTRUCT wants two scalars, not a map: conventional memory below
 * 640K, and the length (in KB) of the CONTIGUOUS run of usable memory
 * starting at 1M.
 *
 * This must be a contiguous span, not a sum: size_memory() in
 * src/kernel-7/machdep/i386/i386_init.c takes extmem and builds
 * [first_addr, trunc_page(KB(extmem))) as ONE region for the bump
 * allocator (vm/vm_mem_region.c), handing out physical pages linearly
 * across it with no reference to any memory map. Summing usable bytes
 * across a fragmented UEFI map (as an earlier version of this function
 * did, to mirror boot-2's E820 sizememory()) can report a total that
 * includes memory the kernel never actually gets to walk contiguously,
 * so the allocator can walk into an ACPI-reclaim or reserved hole. */
void efi_sizemem(int *convmem_kb, int *extmem_kb)
{
    UINTN size = 0, key, dsize;
    UINT32 dver;
    EFI_MEMORY_DESCRIPTOR *map = 0;
    UINTN off;
    UINT64 conv_top = 0;
    UINT64 ext_sum = 0;
    UINT64 span_end;
    EFI_MEMORY_DESCRIPTOR *stop_desc;
    int tries;

    /* AllocatePool() for the map buffer itself perturbs the live memory
     * map (it can split/retype the descriptor it allocates from), so the
     * size GetMemoryMap first reports can be stale by the time we come
     * back to fill the buffer. Retry with the freshly reported size
     * (plus slack) instead of trusting a single guess. */
    gBS->GetMemoryMap(&size, 0, &key, &dsize, &dver);
    for (tries = 0; ; tries++) {
        EFI_STATUS st;

        size += 8 * dsize;
        if (map)
            gBS->FreePool(map);
        if (EFI_ERROR(gBS->AllocatePool(EfiLoaderData, size, (void **)&map))) {
            *convmem_kb = 640;
            *extmem_kb = 0;
            return;
        }
        st = gBS->GetMemoryMap(&size, map, &key, &dsize, &dver);
        if (!EFI_ERROR(st))
            break;
        if (st != EFI_BUFFER_TOO_SMALL || tries >= 4) {
            gBS->FreePool(map);
            *convmem_kb = 640;
            *extmem_kb = 0;
            return;
        }
    }

    efi_dump_map(map, size, dsize);

    /* Conventional top below 640K (that range is reliably one contiguous
     * descriptor in practice). Also total usable bytes above 1M purely
     * for the diagnostic print below -- ext_sum is NOT what gets reported
     * as extmem_kb; see the function comment. */
    for (off = 0; off < size; off += dsize) {
        EFI_MEMORY_DESCRIPTOR *d =
            (EFI_MEMORY_DESCRIPTOR *)((char *)map + off);
        UINT64 start = d->PhysicalStart;
        UINT64 end = start + d->NumberOfPages * 4096;
        if (!efi_usable(d->Type))
            continue;
        if (start < 0xA0000 && end > conv_top)
            conv_top = end > 0xA0000 ? 0xA0000 : end;
        if (end > 0x100000) {
            UINT64 lo = start > 0x100000 ? start : 0x100000;
            ext_sum += end - lo;
        }
    }

    /* Walk the CONTIGUOUS usable run starting at 1M. The map is not
     * guaranteed sorted, so rather than assume ascending PhysicalStart,
     * repeatedly look up whatever descriptor covers the current frontier
     * address and extend the frontier by that descriptor's extent. Stop
     * at the first descriptor that isn't usable, or at the first address
     * no descriptor covers at all (a true gap in the map). */
    span_end = 0x100000;
    stop_desc = 0;
    for (;;) {
        EFI_MEMORY_DESCRIPTOR *d = efi_desc_at(map, size, dsize, span_end);
        if (!d)
            break;
        if (!efi_usable(d->Type)) {
            stop_desc = d;
            break;
        }
        span_end = d->PhysicalStart + d->NumberOfPages * 4096;
    }

    if (stop_desc) {
        printf("contiguous span stopped: type %d (%s) start %x\n",
               (int)stop_desc->Type, efi_type_name(stop_desc->Type),
               (unsigned)stop_desc->PhysicalStart);
    } else {
        printf("contiguous span stopped: no descriptor covers %x "
               "(gap in map)\n", (unsigned)span_end);
    }
    printf("contiguous extmem_kb %d, sum-of-usable would have been %d\n",
           (int)((span_end - 0x100000) / 1024), (int)(ext_sum / 1024));

    gBS->FreePool(map);
    *convmem_kb = (int)(conv_top / 1024);
    *extmem_kb = (int)((span_end - 0x100000) / 1024);
}

/* Mirrors getKernBootStruct() in src/boot-2/i386/libsaio/bootstruct.c, with
 * EFI sources where the BIOS ones are gone. */
void efi_init_bootstruct(void)
{
    int conv, ext;

    bzero((char *)kernBootStruct, sizeof(*kernBootStruct));

    efi_sizemem(&conv, &ext);
    kernBootStruct->convmem = conv;
    kernBootStruct->extmem = ext;

    /* Must be non-zero: sys.c rejects hd() opens when this is 0. */
    kernBootStruct->numIDEs = efi_disk_count();

    kernBootStruct->magicCookie = KERNBOOTMAGIC;
    kernBootStruct->configEnd = kernBootStruct->config;
    kernBootStruct->graphicsMode = TEXT_MODE;
    kernBootStruct->first_addr0 = 0;

    /* The kernel's setconf() reads rootdev from here, and -v turns on the
     * verbose output later tasks check for. kernDev is NOT set here: sys.c's
     * device parser writes it as a side effect of the first successful
     * open(), which happens in load_kernel(). */
    strncpy(kernBootStruct->bootString, "rootdev=hd0a -v",
            BOOT_STRING_LEN - 1);
    /* diskInfo, video, pciInfo, eisaSlotInfo and apm_config stay zeroed:
     * they are BIOS-derived and have no EFI equivalent. */
}
