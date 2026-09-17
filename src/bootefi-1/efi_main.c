#include "efi.h"
#include "kernBootStruct.h"

EFI_SYSTEM_TABLE  *gST;
EFI_BOOT_SERVICES *gBS;
EFI_HANDLE         gImageHandle;

KERNBOOTSTRUCT *kernBootStruct = KERNSTRUCT_ADDR;

extern int efi_disk_init(void);
extern int efi_disk_count(void);
extern int efi_reserve_ranges(void);

/* Defined in sys.c; declared here rather than pulling in saio.h's full
 * BSD/UFS header chain for this translation unit, which needs none of it. */
extern int open(char *str, int how);
extern int read(int fdesc, char *buf, int count);
extern int close(int fdesc);

/* Set the first time ebiosread() runs, to prove the BIOS_ADDR override in
 * bootefi_memory_override.h actually reached disk.c's translation unit
 * (intbuf == biosbuf at that point, before any sector data is copied in). */
extern unsigned long gFirstBiosbuf;

EFI_STATUS
efi_main(EFI_HANDLE image, EFI_SYSTEM_TABLE *systab)
{
    int fd, n;
    unsigned char hdr[28];

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

    /* numIDEs must be non-zero or sys.c rejects every hd() open. */
    kernBootStruct->numIDEs = efi_disk_count();

    fd = open("hd(0,a)/mach_kernel", 0);
    printf("intbuf address: %x\n", gFirstBiosbuf);
    if (fd < 0) {
        printf("open failed\n");
        for (;;) ;
    }
    n = read(fd, (char *)hdr, sizeof(hdr));
    printf("read %d bytes, magic %x %x %x %x\n", n,
           hdr[0], hdr[1], hdr[2], hdr[3]);
    close(fd);

    for (;;)
        ;
    return EFI_SUCCESS;
}
