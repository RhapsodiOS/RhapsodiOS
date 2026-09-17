/* Phase 0 go/no-go: can the firmware give us boot2's fixed low addresses?
 * Build with `make spike`; this is a diagnostic, not part of the loader. */
#include "efi.h"

EFI_SYSTEM_TABLE  *gST;
EFI_BOOT_SERVICES *gBS;
EFI_HANDLE         gImageHandle;

/* Follow-up diagnostic: is the 0x100000-0x700000 refusal self-collision
 * with our own loaded image, and what alternatives exist?  Diagnostic-only
 * additions, not part of the loader. */
#define EFI_LOADED_IMAGE_PROTOCOL_GUID \
  {0x5b1b31a1,0x9562,0x11d2,{0x8e,0x3f,0x00,0xa0,0xc9,0x69,0x72,0x3b}}

typedef struct {
    UINT32      Revision;
    EFI_HANDLE  ParentHandle;
    void       *SystemTable;
    EFI_HANDLE  DeviceHandle;
    void       *FilePath;
    void       *Reserved;
    UINT32      LoadOptionsSize;
    void       *LoadOptions;
    void       *ImageBase;
    UINT64      ImageSize;
    UINT32      ImageCodeType;
    UINT32      ImageDataType;
    void       *Unload;
} EFI_LOADED_IMAGE_PROTOCOL;

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

    /* --- Follow-up diagnostic 1: where is our own image loaded? --- */
    {
        EFI_GUID guid = EFI_LOADED_IMAGE_PROTOCOL_GUID;
        EFI_LOADED_IMAGE_PROTOCOL *li = 0;
        EFI_STATUS st = gBS->HandleProtocol(gImageHandle, &guid,
                                             (void **)&li);
        puts16(L"LoadedImage: ");
        if (EFI_ERROR(st)) {
            puts16(L"HandleProtocol failed "); puthex(st); puts16(L"\r\n");
        } else {
            puts16(L"ImageBase "); puthex((UINT64)(UINTN)li->ImageBase);
            puts16(L" ImageSize "); puthex(li->ImageSize);
            puts16(L"\r\n");
        }
    }

    /* --- Follow-up diagnostic 2: 1MB sub-blocks across 0x100000-0x700000 */
    puts16(L"Sub-block reservations 0x100000-0x700000:\r\n");
    {
        EFI_PHYSICAL_ADDRESS base;
        for (base = 0x100000; base < 0x700000; base += 0x100000) {
            EFI_PHYSICAL_ADDRESS addr = base;
            EFI_STATUS st = gBS->AllocatePages(AllocateAddress, EfiLoaderData,
                                               0x100000 / 4096, &addr);
            puts16(L"  "); puthex(base); puts16(L" ");
            puts16(EFI_ERROR(st) ? L"REFUSED " : L"granted ");
            puthex(st);
            puts16(L"\r\n");
        }
    }

    /* --- Follow-up diagnostic 3: relocation candidates above the conflict */
    puts16(L"Relocation candidates:\r\n");
    {
        EFI_PHYSICAL_ADDRESS addr = 0x1000000;
        EFI_STATUS st = gBS->AllocatePages(AllocateAddress, EfiLoaderData,
                                           0x100000 / 4096, &addr);
        puts16(L"  AllocateAddress 0x1000000 (1MB) ");
        puts16(EFI_ERROR(st) ? L"REFUSED " : L"granted ");
        puthex(st);
        puts16(L"\r\n");
    }
    {
        EFI_PHYSICAL_ADDRESS addr = 0x10000000; /* max address ceiling */
        EFI_STATUS st = gBS->AllocatePages(AllocateMaxAddress, EfiLoaderData,
                                           0x100000 / 4096, &addr);
        puts16(L"  AllocateMaxAddress <=0x10000000 (1MB) ");
        puts16(EFI_ERROR(st) ? L"REFUSED " : L"granted ");
        puthex(st);
        puts16(L" got "); puthex(addr);
        puts16(L"\r\n");
    }
    {
        EFI_PHYSICAL_ADDRESS addr = 0;
        EFI_STATUS st = gBS->AllocatePages(AllocateAnyPages, EfiLoaderData,
                                           0x100000 / 4096, &addr);
        puts16(L"  AllocateAnyPages (1MB) ");
        puts16(EFI_ERROR(st) ? L"REFUSED " : L"granted ");
        puthex(st);
        puts16(L" got "); puthex(addr);
        puts16(L"\r\n");
    }

    /* --- Follow-up diagnostic 4: finer-grain null-page probe --- */
    puts16(L"Null-page fine probe:\r\n");
    {
        EFI_PHYSICAL_ADDRESS pages3[3] = { 0x0, 0x1000, 0x2000 };
        int i;
        for (i = 0; i < 3; i++) {
            EFI_PHYSICAL_ADDRESS addr = pages3[i];
            EFI_STATUS st = gBS->AllocatePages(AllocateAddress, EfiLoaderData,
                                               1, &addr);
            puts16(L"  "); puthex(pages3[i]); puts16(L" ");
            puts16(EFI_ERROR(st) ? L"REFUSED " : L"granted ");
            puthex(st);
            puts16(L"\r\n");
        }
    }

    for (;;)
        ;
    return EFI_SUCCESS;
}
