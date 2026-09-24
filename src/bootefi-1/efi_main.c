#include "efi.h"
#include "kernBootStruct.h"
#include <mach-o/loader.h>
#include "load.h"
#include <memory.h>	/* RLD_MEM_ADDR */
#include "sarld.h"	/* sa_rld_t */
#include "efi_bootargs.h"

EFI_SYSTEM_TABLE  *gST;
EFI_BOOT_SERVICES *gBS;
EFI_HANDLE         gImageHandle;

KERNBOOTSTRUCT *kernBootStruct = KERNSTRUCT_ADDR;

extern int efi_disk_init(void);
extern int efi_reserve_ranges(void);
extern void efi_init_bootstruct(void);
extern int efi_pci_init(void);
extern void efi_gfx_init(void);

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

/* loadStandaloneLinker(), newStringForKey(), loadOtherConfigs() and
 * loadBootDrivers() are already declared by saio_static.h / saio_internal.h,
 * both pulled in transitively via load.h -> libsaio.h above. */

/* boot2/boot.c global that drivers.c/stringTable.c references as extern.
 * boot.c itself is not part of this build (it is boot2's own main loop);
 * reproduced as plain data here since nothing sets it -- this loader has no
 * installer driver-family UI, so it stays "none configured".  PCISlotInfo
 * is not stubbed here any more: efi_pci.c defines and fills it. */
char *LoadableFamilies;

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
    efi_gfx_init();

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

    /* After efi_init_bootstruct() has zeroed kernBootStruct, and before the
     * kernel reads pciInfo out of it.  Without this the kernel's PCI bus
     * driver decides there is no PCI bus and frees itself; see efi_pci.c. */
    printf("pci devices: %d\n", efi_pci_init());

    if (load_kernel("hd(0,a)/mach_kernel") != 0)
        for (;;) ;

    printf("kaddr %x ksize %x entry %x\n",
           kernBootStruct->kaddr, kernBootStruct->ksize,
           (unsigned int)kernelEntry);
    printf("convmem %d extmem %d numIDEs %d\n",
           kernBootStruct->convmem, kernBootStruct->extmem,
           kernBootStruct->numIDEs);
    printf("first_addr0 %x\n", kernBootStruct->first_addr0);
    printf("bootString '%s' kernDev %x magicCookie %x graphicsMode %d\n",
           kernBootStruct->bootString, kernBootStruct->kernDev,
           kernBootStruct->magicCookie, kernBootStruct->graphicsMode);

    /* boot2's boot() loads the system config (System.config/Instance0.table
     * off the default device) once, before ever calling execKernel() --
     * that is where the "Boot Drivers" key loadOtherConfigs() reads below
     * comes from. This loader has no boot-arg "config=" parsing and no
     * instance selection, so it always takes loadSystemConfig()'s own
     * argument-less default path (which=0, size=0), same as an
     * unconfigured real boot. Without this call kernBootStruct->config
     * stays empty and loadOtherConfigs() finds nothing to load. */
    printf("loadSystemConfig: %d\n", loadSystemConfig(0, 0));

    /* boot2 folds the config's "Kernel Flags" into the boot string
     * (boot.c); this loader appends them after its compiled-in default so
     * the kernel's getargs(), which keeps the last rootdev= it sees, takes
     * the config's value. */
    {
        char *val;
        int size;

        if (getValueForKey("Kernel Flags", &val, &size))
            efi_append_boot_flags(kernBootStruct->bootString,
                                  BOOT_STRING_LEN, val, size);
        printf("bootString '%s'\n", kernBootStruct->bootString);
    }

    {
        char *linkerPath = newStringForKey("Linker");
        if (linkerPath == 0)
            linkerPath = "/usr/standalone/i386/sarld";
        if (loadStandaloneLinker(linkerPath,
                                  (sa_rld_t **)&kernBootStruct->rld_entry)
            == -1) {
            printf("Couldn't load standalone linker; "
                   "unable to load boot drivers.\n");
        } else {
            loadOtherConfigs(0);
            loadBootDrivers(0, 0, 0);
            printf("boot drivers linked: %d\n",
                   kernBootStruct->numBootDrivers);
        }
    }

    /* Re-derive first_addr0 from the live configEnd here, unconditionally.
     * efi_init_bootstruct() set a provisional value before any config was
     * loaded; loadOtherConfigs()/loadBootDrivers() above (mirroring
     * boot-2's stringTable.c:749 and drivers.c:759) refresh it to match
     * the config data actually read -- but only on the loadStandaloneLinker()
     * success path above. If that call failed, first_addr0 is still the
     * provisional value while loadSystemConfig(0,0) has since grown
     * kernBootStruct->config, so it would point into live config bytes
     * instead of past them. Recomputing it here from the current
     * configEnd keeps it correct on every path. */
    kernBootStruct->first_addr0 = (int)kernBootStruct->configEnd + 1024;

    removeLinkEditSegment((struct mach_header *)kernBootStruct->kaddr);
    printf("Starting Rhapsody\n");
    efi_exit_and_start((unsigned int)kernelEntry);
    /* not reached */
    return EFI_SUCCESS;
}
