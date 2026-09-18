#include "efi.h"
#include "load.h"	/* printf(), via libsaio.h */

/* boot2's GDT (src/boot-2/i386/libsaio/table.c), used verbatim: selector
 * 0x20 is flat data, 0x28 flat code.  table.c defines struct seg_desc
 * itself rather than in a shared header, so its layout is reproduced here
 * (6 entries, matching table.c's NGDTENT) purely so this translation unit
 * can take Gdt's address -- no field of it is read or written here. */
struct seg_desc {
    unsigned short  limit_15_0;
    unsigned short  base_15_0;
    unsigned char   base_23_16;
    unsigned char   bit_15_8;
    unsigned char   bit_23_16;
    unsigned char   base_31_24;
};
extern struct seg_desc Gdt[6];

extern void efi_handoff(unsigned int entry);

struct gdt_descriptor {
    unsigned short limit;
    unsigned long  base;
} __attribute__((packed));

extern struct gdt_descriptor gdt_desc;

void efi_exit_and_start(unsigned int entry)
{
    UINTN size = 0, key, dsize;
    UINT32 dver;
    EFI_MEMORY_DESCRIPTOR *map = 0;
    int tries;

    gdt_desc.base = (unsigned long)Gdt;

    gBS->SetWatchdogTimer(0, 0, 0, 0);

    /* AllocatePool() for the map buffer itself perturbs the live memory
     * map, so a single freshly-measured size is stale by the time the
     * buffer is filled; efi_memory.c's efi_sizemem() hit this exact
     * EFI_BUFFER_TOO_SMALL cycle and fixed it by growing the buffer by a
     * fixed slack on every retry rather than re-measuring a bare minimum
     * each time. Reused here for the same reason. */
    gBS->GetMemoryMap(&size, 0, &key, &dsize, &dver);
    for (tries = 0; tries < 8; tries++) {
        EFI_STATUS st;

        size += 8 * dsize;
        if (map)
            gBS->FreePool(map);
        if (EFI_ERROR(gBS->AllocatePool(EfiLoaderData, size, (void **)&map)))
            break;
        st = gBS->GetMemoryMap(&size, map, &key, &dsize, &dver);
        if (EFI_ERROR(st)) {
            if (st != EFI_BUFFER_TOO_SMALL)
                break;
            continue;
        }
        st = gBS->ExitBootServices(gImageHandle, key);
        if (!EFI_ERROR(st))
            efi_handoff(entry);     /* never returns */
        /* ExitBootServices rejected the key -- get a fresh map and retry. */
    }

    /* Only reached if ExitBootServices never succeeded. */
    printf("ExitBootServices failed\n");
    for (;;)
        ;
}
