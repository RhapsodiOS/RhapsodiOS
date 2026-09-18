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

/* efi_vga.c: resets the VGA card to standard text mode 3 (register
 * programming + font reload + buffer clear) so the kernel's own VGA
 * console setup lands on hardware left in a known-good state, matching
 * what SeaBIOS/boot1 leave behind on the legacy path. Direct port/memory
 * I/O only -- safe to call after ExitBootServices. */
extern void efi_vga_reset_text_mode(void);

struct gdt_descriptor {
    unsigned short limit;
    unsigned long  base;
} __attribute__((packed));

extern struct gdt_descriptor gdt_desc;

void efi_exit_and_start(unsigned int entry)
{
    UINTN size = 0, key, dsize = sizeof(EFI_MEMORY_DESCRIPTOR);
    UINT32 dver;
    EFI_MEMORY_DESCRIPTOR *map = 0;
    int tries;
    EFI_STATUS sizing_st;

    gdt_desc.base = (unsigned long)Gdt;

    gBS->SetWatchdogTimer(0, 0, 0, 0);

    /* AllocatePool() for the map buffer itself perturbs the live memory
     * map, so a single freshly-measured size is stale by the time the
     * buffer is filled; efi_memory.c's efi_sizemem() hit this exact
     * EFI_BUFFER_TOO_SMALL cycle and fixed it by growing the buffer by a
     * fixed slack on every retry rather than re-measuring a bare minimum
     * each time. Reused here for the same reason.
     *
     * dsize is pre-initialized above and the return checked below: this
     * call's only job is to size the buffer, and it is expected to come
     * back EFI_BUFFER_TOO_SMALL. If it returns anything else, dsize may
     * never have been written, and size += 8 * dsize would scale off
     * garbage -- with no diagnostics available on this side of the boot
     * to catch it later. */
    sizing_st = gBS->GetMemoryMap(&size, 0, &key, &dsize, &dver);
    if (sizing_st != EFI_BUFFER_TOO_SMALL) {
        printf("GetMemoryMap sizing call failed: %x\n", (unsigned)sizing_st);
        for (;;)
            ;
    }
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
        if (!EFI_ERROR(st)) {
            /* Boot services -- and the firmware's own interrupt handlers
             * -- are gone as of the line above, but IF and the firmware's
             * IDT are both still live until efi_handoff's own `cli`. That
             * `cli` runs only after efi_vga_reset_text_mode()'s several
             * hundred VGA port writes and 8K text-buffer clear, so an
             * interrupt landing in that window would vector into a
             * handler whose owning code is no longer guaranteed to be
             * mapped or valid. Disable interrupts here, immediately after
             * ExitBootServices succeeds and before any of that runs;
             * efi_handoff's own `cli` stays too, as a harmless no-op on
             * this path and the sole guard on any other. */
            __asm__ volatile("cli");
            efi_vga_reset_text_mode();
            efi_handoff(entry);     /* never returns */
        }
        /* ExitBootServices rejected the key -- get a fresh map and retry. */
    }

    /* Only reached if ExitBootServices never succeeded. */
    printf("ExitBootServices failed\n");
    for (;;)
        ;
}
