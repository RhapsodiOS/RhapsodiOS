/* BIOS-layer backend for boot-2's disk.c, over EFI_BLOCK_IO_PROTOCOL.
 * disk.c is compiled unmodified; this file supplies only the symbols its
 * Biosread() and devopen()/read_label() call out to: ebiosread, biosread,
 * uses_ebios, get_diskinfo, turnOffFloppy.  devopen, devread, devflush and
 * read_label all come from disk.c as-is.
 */
#include "efi.h"

#define BPS             512
#define MAX_DISKS       8
#define FIRST_BIOSDEV   0x80

/* Sector number of the NeXT disk label (matches disk.c's own DISKLABEL).
 * Mirrors src/boot-2/i386/libsaio/disk.c's DISKLABEL; keep in sync. */
#define DISKLABEL       15

static EFI_GUID gBlockIoGuid = EFI_BLOCK_IO_PROTOCOL_GUID;
static EFI_BLOCK_IO_PROTOCOL *disks[MAX_DISKS];
static int ndisks;

/* disk.c indexes this by (biosdev - 0x80) to choose the LBA path. */
unsigned char uses_ebios[MAX_DISKS] = {1, 1, 1, 1, 1, 1, 1, 1};

/* The two-disk layout puts the Rhapsody image and an ESP-only disk on
 * whole-disk EFI_BLOCK_IO handles, in an order EFI does not guarantee
 * matches qemu's -drive order.  disk.c's open("hd(0,a)/...") always means
 * biosdev 0x80, i.e. disks[0], so we must identify the Rhapsody disk
 * ourselves and place it there rather than trust enumeration order.
 *
 * The probe reads the NeXT disk label sector (LBA 15) directly and checks
 * the raw on-disk bytes of dl_version for DL_V3 ("dlV3", big-endian
 * regardless of payload endianness: confirmed against golden.img in Task 4,
 * raw bytes 64 6c 56 33).  This mirrors disk.c's own read_label() just
 * enough to tell "a Rhapsody disk label is here" from "this is FAT32/ESP",
 * without touching disk.c and without pulling in the full disk_label_t
 * layout (whole-disk media here, so part_offset is always 0).
 */
static int looks_like_rhapsody(EFI_BLOCK_IO_PROTOCOL *bio)
{
    unsigned char label[BPS];

    if (bio->Media->BlockSize != BPS)
        return 0;
    if (EFI_ERROR(bio->ReadBlocks(bio, bio->Media->MediaId, DISKLABEL,
                                  sizeof(label), label)))
        return 0;
    /* DL_V3 ("dlV3"), raw big-endian bytes -- mirrors the pattern checked
     * against dl_version in src/boot-2/i386/libsaio/disk.c; keep in sync. */
    return label[0] == 0x64 && label[1] == 0x6c &&
           label[2] == 0x56 && label[3] == 0x33;
}

/* Enumerate whole-disk BLOCK_IO handles, skipping partition handles, and
 * arrange disks[] so the Rhapsody disk (if identified) is disks[0]. */
int efi_disk_init(void)
{
    EFI_HANDLE *handles = 0;
    UINTN size = 0, i;
    EFI_STATUS st;
    EFI_BLOCK_IO_PROTOCOL *cand[MAX_DISKS];
    int ncand, rhapsody_idx = -1, nmatches = 0;

    st = gBS->LocateHandle(ByProtocol, &gBlockIoGuid, 0, &size, 0);
    if (st != EFI_BUFFER_TOO_SMALL)
        return 0;
    if (EFI_ERROR(gBS->AllocatePool(EfiLoaderData, size, (void **)&handles)))
        return 0;
    if (EFI_ERROR(gBS->LocateHandle(ByProtocol, &gBlockIoGuid, 0, &size,
                                    handles))) {
        gBS->FreePool(handles);
        return 0;
    }

    ncand = 0;
    for (i = 0; i < size / sizeof(EFI_HANDLE) && ncand < MAX_DISKS; i++) {
        EFI_BLOCK_IO_PROTOCOL *bio = 0;
        if (EFI_ERROR(gBS->HandleProtocol(handles[i], &gBlockIoGuid,
                                          (void **)&bio)))
            continue;
        if (!bio->Media->MediaPresent || bio->Media->LogicalPartition)
            continue;
        if (looks_like_rhapsody(bio)) {
            if (rhapsody_idx < 0)
                rhapsody_idx = ncand;
            nmatches++;
        }
        cand[ncand++] = bio;
    }
    gBS->FreePool(handles);

    if (rhapsody_idx >= 0) {
        printf("rhapsody disk: handle %d selected for biosdev 0x80\n",
               rhapsody_idx);
        if (nmatches > 1)
            printf("warning: %d handles matched the Rhapsody disk label; "
                   "using the first\n", nmatches);
    } else {
        printf("rhapsody disk: no handle matched the disk label; "
               "falling back to enumeration order\n");
    }

    ndisks = 0;
    if (rhapsody_idx >= 0)
        disks[ndisks++] = cand[rhapsody_idx];
    for (i = 0; i < (UINTN)ncand; i++) {
        if ((int)i == rhapsody_idx)
            continue;
        disks[ndisks++] = cand[i];
    }
    return ndisks;
}

int efi_disk_count(void) { return ndisks; }

/* disk.c's Biosread() calls this for every LBA read, having already
 * pointed biosbuf at intbuf (BIOS_ADDR, redirected to 0x20000 by
 * bootefi_memory_override.h) before the call. */
int ebiosread(int biosdev, int secno, int nsecs)
{
    extern char *biosbuf;
    EFI_BLOCK_IO_PROTOCOL *bio;
    int idx = biosdev - FIRST_BIOSDEV;
    UINT64 lba;
    UINTN bytes = (UINTN)nsecs * BPS;

    if (idx < 0 || idx >= ndisks)
        return -1;
    bio = disks[idx];
    if (bio->Media->BlockSize != BPS)
        return -1;                      /* 4Kn media is out of scope */
    lba = (UINT64)secno;
    if (EFI_ERROR(bio->ReadBlocks(bio, bio->Media->MediaId, lba, bytes,
                                  biosbuf)))
        return -1;
    return 0;
}

/* Unreachable: uses_ebios is always set. */
int biosread(int dev, int cyl, int head, int sec, int nsecs)
{
    return -1;
}

/* devopen() only checks this for non-zero. */
long get_diskinfo(int biosdev)
{
    return 0x3F | (0x0F << 8);
}

void turnOffFloppy(void) { }
