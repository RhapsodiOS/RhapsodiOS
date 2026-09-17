/* Phase 0 go/no-go: can the firmware give us boot2's fixed low addresses?
 * Build with `make spike`; this is a diagnostic, not part of the loader. */
#include "efi.h"

EFI_SYSTEM_TABLE  *gST;
EFI_BOOT_SERVICES *gBS;
EFI_HANDLE         gImageHandle;

static void puts16(CHAR16 *s)
{
    gST->ConOut->OutputString(gST->ConOut, s);
}

static void puthex(UINT64 v)
{
    CHAR16 buf[19];
    int i;

    buf[0] = L'0'; buf[1] = L'x';
    for (i = 0; i < 16; i++) {
        int nib = (int)((v >> ((15 - i) * 4)) & 0xF);
        buf[2 + i] = (CHAR16)(nib < 10 ? L'0' + nib : L'a' + nib - 10);
    }
    buf[18] = 0;
    puts16(buf);
}

struct range { UINT64 start; UINT64 end; CHAR16 *name; };

static struct range ranges[] = {
    { 0x000000, 0x003000, L"intbuf (BIOS_ADDR)" },
    { 0x011000, 0x020000, L"bootstruct" },
    { 0x030000, 0x0A0000, L"sarld" },
    { 0x100000, 0x700000, L"kernel+drivers+heaps" },
    { 0, 0, 0 }
};

static void dump_map(void)
{
    UINTN size = 0, key, dsize;
    UINT32 dver;
    EFI_MEMORY_DESCRIPTOR *map = 0;
    EFI_STATUS st;
    UINTN off;

    gBS->GetMemoryMap(&size, 0, &key, &dsize, &dver);
    size += 4 * dsize;
    if (EFI_ERROR(gBS->AllocatePool(EfiLoaderData, size, (void **)&map)))
        return;
    st = gBS->GetMemoryMap(&size, map, &key, &dsize, &dver);
    if (EFI_ERROR(st)) {
        puts16(L"GetMemoryMap failed\r\n");
        return;
    }
    for (off = 0; off < size; off += dsize) {
        EFI_MEMORY_DESCRIPTOR *d =
            (EFI_MEMORY_DESCRIPTOR *)((char *)map + off);
        if (d->PhysicalStart >= 0x800000)
            continue;               /* only the region we care about */
        puts16(L"  type "); puthex(d->Type);
        puts16(L" start "); puthex(d->PhysicalStart);
        puts16(L" pages "); puthex(d->NumberOfPages);
        puts16(L"\r\n");
    }
}

EFI_STATUS
efi_main(EFI_HANDLE image, EFI_SYSTEM_TABLE *systab)
{
    struct range *r;

    gImageHandle = image;
    gST = systab;
    gBS = systab->BootServices;

    gST->ConOut->ClearScreen(gST->ConOut);
    puts16(L"Memory map below 8M:\r\n");
    dump_map();

    puts16(L"Reservations:\r\n");
    for (r = ranges; r->name; r++) {
        EFI_PHYSICAL_ADDRESS addr = r->start;
        UINTN pages = (UINTN)((r->end - r->start) / 4096);
        EFI_STATUS st = gBS->AllocatePages(AllocateAddress, EfiLoaderData,
                                           pages, &addr);
        puts16(L"  "); puts16(r->name); puts16(L" ");
        puts16(EFI_ERROR(st) ? L"REFUSED " : L"granted ");
        puthex(st);
        puts16(L"\r\n");
    }

    for (;;)
        ;
    return EFI_SUCCESS;
}
