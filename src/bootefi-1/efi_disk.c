/* BIOS-layer backend for boot-2's disk.c, over EFI_BLOCK_IO_PROTOCOL.
 * disk.c is compiled unmodified; this file supplies only the symbols its
 * Biosread() and devopen()/read_label() call out to: ebiosread, biosread,
 * uses_ebios, get_diskinfo, turnOffFloppy.  devopen, devread, devflush and
 * read_label all come from disk.c as-is.
 */
#include "efi.h"
#include "efi_disk_select.h"

#define BPS             512
#define MAX_DISKS       8
#define FIRST_BIOSDEV   0x80

static EFI_GUID gBlockIoGuid = EFI_BLOCK_IO_PROTOCOL_GUID;
static EFI_BLOCK_IO_PROTOCOL *disks[MAX_DISKS];
static int ndisks;

/* disk.c indexes this by (biosdev - 0x80) to choose the LBA path. */
unsigned char uses_ebios[MAX_DISKS] = {1, 1, 1, 1, 1, 1, 1, 1};

/* disk.c's open("hd(0,a)/...") always means biosdev 0x80, i.e. disks[0],
 * and EFI does not enumerate block devices in qemu's -drive order, so the
 * loader picks the Rhapsody disk itself and puts it first.
 *
 * A disk counts as Rhapsody if its first NeXT label copy carries DL_V3 --
 * the raw bytes 64 6c 56 33 ("dlV3"), big-endian whatever the payload's
 * byte order, which golden.img confirms.  efi_label_lba() finds that copy:
 * 15 sectors into the first 0xA7 fdisk partition, or LBA 15 on a
 * whole-disk label.
 */
static int looks_like_rhapsody(EFI_BLOCK_IO_PROTOCOL *bio)
{
    unsigned char sector[BPS];

    if (bio->Media->BlockSize != BPS)
        return 0;
    if (EFI_ERROR(bio->ReadBlocks(bio, bio->Media->MediaId, 0,
                                  sizeof(sector), sector)))
        return 0;
    if (EFI_ERROR(bio->ReadBlocks(bio, bio->Media->MediaId,
                                  efi_label_lba(sector), sizeof(sector),
                                  sector)))
        return 0;
    return sector[0] == 0x64 && sector[1] == 0x6c &&
           sector[2] == 0x56 && sector[3] == 0x33;
}

static EFI_GUID gLoadedImageGuid = EFI_LOADED_IMAGE_PROTOCOL_GUID;
static EFI_GUID gDevicePathGuid = EFI_DEVICE_PATH_PROTOCOL_GUID;

/* Device path of the partition this loader was read from, or 0. */
static const unsigned char *loaded_from_path(void)
{
    EFI_LOADED_IMAGE_PROTOCOL *li = 0;
    void *dp = 0;

    if (EFI_ERROR(gBS->HandleProtocol(gImageHandle, &gLoadedImageGuid,
                                      (void **)&li)))
        return 0;
    if (EFI_ERROR(gBS->HandleProtocol(li->DeviceHandle, &gDevicePathGuid,
                                      &dp)))
        return 0;
    return (const unsigned char *)dp;
}

/* Enumerate whole-disk BLOCK_IO handles, skipping partition handles, and
 * make the Rhapsody disk disks[0]: the disk this loader was read from if it
 * is one, otherwise the first labelled disk.  The fallback is what the
 * two-disk layout relies on, where the loader sits on an ESP-only disk. */
int efi_disk_init(void)
{
    EFI_HANDLE *handles = 0;
    UINTN size = 0, i;
    EFI_STATUS st;
    EFI_BLOCK_IO_PROTOCOL *cand[MAX_DISKS];
    const unsigned char *boot_path = loaded_from_path();
    int ncand, first_idx = -1, boot_idx = -1, rhapsody_idx, nmatches = 0;

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
        void *dp = 0;

        if (EFI_ERROR(gBS->HandleProtocol(handles[i], &gBlockIoGuid,
                                          (void **)&bio)))
            continue;
        if (!bio->Media->MediaPresent || bio->Media->LogicalPartition)
            continue;
        if (looks_like_rhapsody(bio)) {
            if (first_idx < 0)
                first_idx = ncand;
            if (boot_idx < 0 && boot_path != 0 &&
                !EFI_ERROR(gBS->HandleProtocol(handles[i], &gDevicePathGuid,
                                               &dp)) &&
                efi_dp_is_parent((const unsigned char *)dp, boot_path))
                boot_idx = ncand;
            nmatches++;
        }
        cand[ncand++] = bio;
    }
    gBS->FreePool(handles);

    rhapsody_idx = boot_idx >= 0 ? boot_idx : first_idx;
    if (boot_idx >= 0) {
        printf("rhapsody disk: handle %d selected for biosdev 0x80 "
               "(the disk this loader was read from)\n", boot_idx);
    } else if (first_idx >= 0) {
        printf("rhapsody disk: handle %d selected for biosdev 0x80 "
               "(first labelled disk)\n", first_idx);
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
