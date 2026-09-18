#include "efi.h"
#include "kernBootStruct.h"
#include <mach-o/loader.h>
#include "load.h"
#include <memory.h>	/* RLD_MEM_ADDR */

EFI_SYSTEM_TABLE  *gST;
EFI_BOOT_SERVICES *gBS;
EFI_HANDLE         gImageHandle;

KERNBOOTSTRUCT *kernBootStruct = KERNSTRUCT_ADDR;

extern int efi_disk_init(void);
extern int efi_reserve_ranges(void);
extern void efi_init_bootstruct(void);

/* Defined in sys.c; declared here rather than pulling in saio.h's full
 * BSD/UFS header chain for this translation unit, which needs none of it. */
extern int open(char *str, int how);
extern int close(int fdesc);

/* loadprog() is boot-2's Mach-O loader (libsaio/load.c), reused as-is. */
extern int loadprog(int dev, int fd, struct mach_header *headOut,
                     entry_t *entry, char **addr, int *size);
extern int bzero(char *b, int length);

/* libsaio/load.c; declared in saio_internal.h, which pulls in the full BSD
 * header chain this translation unit otherwise avoids -- redeclared here
 * instead, same as loadprog() above. */
extern void removeLinkEditSegment(struct mach_header *mhp);

/* handoff.c: retries ExitBootServices, then jumps via handoff.S.  Never
 * returns. */
extern void efi_exit_and_start(unsigned int entry);

/* Set the first time ebiosread() runs, to prove the BIOS_ADDR override in
 * bootefi_memory_override.h actually reached disk.c's translation unit
 * (intbuf == biosbuf at that point, before any sector data is copied in). */
extern unsigned long gFirstBiosbuf;

static entry_t kernelEntry;

/* Reproduces execKernel()'s load call and bookkeeping (src/boot-2/i386/
 * boot2/boot.c), omitting the graphics, prompt and EISA branches this
 * loader has no equivalent for. Does not jump to the kernel -- that is a
 * later task. */
static int load_kernel(const char *spec)
{
    static struct mach_header head;
    int fd, ret;

    fd = open((char *)spec, 0);
    if (fd < 0) {
        printf("Can't find %s\n", spec);
        return -1;
    }
    strncpy(kernBootStruct->boot_file, spec,
            sizeof(kernBootStruct->boot_file) - 1);

    kernBootStruct->kaddr = kernBootStruct->ksize = 0;
    ret = loadprog(kernBootStruct->kernDev, fd, &head, &kernelEntry,
                   (char **)&kernBootStruct->kaddr, &kernBootStruct->ksize);
    close(fd);
    if (ret != 0) {
        printf("loadprog failed: %d\n", ret);
        return -1;
    }

    /* boot2 zeroes the gap so sarld's driver BSS starts clean; the
     * standalone linker does not zero memory that later becomes BSS. */
    bzero((char *)(kernBootStruct->kaddr + kernBootStruct->ksize),
          RLD_MEM_ADDR - (kernBootStruct->kaddr + kernBootStruct->ksize));
    return 0;
}

EFI_STATUS
efi_main(EFI_HANDLE image, EFI_SYSTEM_TABLE *systab)
{
    gImageHandle = image;
    gST = systab;
    gBS = systab->BootServices;
    gST->ConOut->ClearScreen(gST->ConOut);

    if (efi_reserve_ranges() != 0) {
        printf("fixed-address reservation failed\n");
        for (;;) ;
    }

    printf("RhapsodiOS UEFI loader\n");
    printf("block devices: %d\n", efi_disk_init());

    /* Zeroes kernBootStruct and sets convmem/extmem/numIDEs/bootString;
     * numIDEs must be non-zero before the first hd() open() below, or
     * sys.c rejects it. */
    efi_init_bootstruct();

    if (load_kernel("hd(0,a)/mach_kernel") != 0)
        for (;;) ;

    /* gFirstBiosbuf is only set once disk.c's Biosread() actually runs a
     * cache miss, which load_kernel()'s open()/loadprog() above just did. */
    printf("intbuf address: %x\n", gFirstBiosbuf);
    printf("kaddr %x ksize %x entry %x\n",
           kernBootStruct->kaddr, kernBootStruct->ksize,
           (unsigned int)kernelEntry);
    printf("convmem %d extmem %d numIDEs %d\n",
           kernBootStruct->convmem, kernBootStruct->extmem,
           kernBootStruct->numIDEs);
    printf("bootString '%s' kernDev %x magicCookie %x graphicsMode %d\n",
           kernBootStruct->bootString, kernBootStruct->kernDev,
           kernBootStruct->magicCookie, kernBootStruct->graphicsMode);

    removeLinkEditSegment((struct mach_header *)kernBootStruct->kaddr);
    printf("Starting Rhapsody\n");
    efi_exit_and_start((unsigned int)kernelEntry);
    /* not reached */
    return EFI_SUCCESS;
}
