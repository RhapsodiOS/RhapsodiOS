"""Build MBR disks for the UEFI loader.

build() writes the single-disk layout: boot0 and the fdisk table, a FAT32
EFI System Partition holding the loader, then a whole-disk Rhapsody image as
the active 0xA7 partition.  build_esp() writes an ESP-only disk for the
older two-disk layout, where the Rhapsody image is attached whole as a
second disk.

MBR rather than GPT, because boot0, boot1, boot2 and the kernel all find
the Rhapsody partition by its 0xA7 system id.
"""

import os
import shutil
import struct
import sys

import fat32
import rhap_image
import ufs_build

SECTOR = 512
MBR_PART_OFFSET = 446
DISK_BOOTSZ = 446               # boot0's code, ahead of the fdisk table
FDISK_NEXTNAME = 0xA7
EFI_SYSTEM = 0xEF
ESP_LBA = 2048  # 1 MB in, the conventional alignment
ESP_BOOT_PATH = "EFI/BOOT/BOOTIA32.EFI"
BOOT0_PATH = "/usr/standalone/i386/boot0"
LABEL_MAGIC = b"dlV3"
LABEL_SCAN_SECTORS = 64         # the copies sit at sectors 15, 30 and 45
# Offsets into the big-endian, m68k-packed disk_label_t the kernel reads
# (src/kernel-7/bsd/dev/disk_label.h, bsd/sys/disktab.h).
DL_LABEL_BLKNO = 4
DL_SECSIZE = 92
DL_BOOT0_BLKNO = 124            # int[NBOOTS]
DL_PARTITIONS = 190             # partition_t[NPART], p_base first
PARTITION_SIZE = 46
NPART = 8
NBOOTS = 2


def lba_assist_geometry(total_sectors):
    """(heads, sectors per track) as SeaBIOS's TRANSLATION_LBA picks them
    (src/block.c): the LBA-assisted translation most BIOSes use above
    504 MB.  boot0 reads the active partition's boot sector by the CHS
    fields in its fdisk entry, so those fields must use this geometry."""
    spt = 63
    if total_sectors > 63 * 255 * 1024:
        return 255, spt
    heads = (total_sectors // spt) // 1024
    for limit, chosen in ((128, 255), (64, 128), (32, 64), (16, 32)):
        if heads > limit:
            return chosen, spt
    return 16, spt


def chs(lba, heads, spt):
    """The 3-byte CHS field for lba, or 1023/254/63 past cylinder 1023."""
    cyl = lba // (heads * spt)
    if cyl > 1023:
        return b"\xfe\xff\xff"
    head = (lba // spt) % heads
    sec = lba % spt + 1
    return bytes([head, ((cyl >> 2) & 0xC0) | sec, cyl & 0xFF])


def _part_entry(systid, lba_start, nsectors, geometry, active=False):
    heads, spt = geometry
    return (bytes([0x80 if active else 0x00]) + chs(lba_start, heads, spt)
            + bytes([systid]) + chs(lba_start + nsectors - 1, heads, spt)
            + struct.pack("<II", lba_start, nsectors))


def _esp_image(efi_app, esp_sectors):
    """A FAT32 volume of esp_sectors holding the EFI app at the removable-
    media path OVMF boots from."""
    with open(efi_app, "rb") as f:
        app = f.read()
    return fat32.build(esp_sectors, {ESP_BOOT_PATH: app}, label="RHAPEFI",
                       hidden_sectors=ESP_LBA)


def rebase_labels(head, relsect):
    """Rewrite every NeXT label copy in head, the first sectors of a
    whole-disk Rhapsody image, for a partition that starts at LBA relsect.
    Returns how many copies were rewritten.

    Inside an fdisk partition a label holds absolute addresses: disk -i -b
    adds the partition base to p_base and d_boot0_blkno
    (diskdev_cmds/disk.tproj/hd.c), boot1 loads boot2 from the absolute
    d_boot0_blkno, and IODiskPartition uses p_base as-is.  check_label also
    rejects a copy whose dl_label_blkno isn't the physical block it came
    from.  A whole-disk image has none of that, so copied verbatim into a
    partition it cannot boot or mount.
    """
    found = 0
    for sector in range(len(head) // SECTOR):
        off = sector * SECTOR
        if head[off:off + len(LABEL_MAGIC)] != LABEL_MAGIC:
            continue
        secsize = struct.unpack_from(">i", head, off + DL_SECSIZE)[0]
        if (secsize < SECTOR or secsize % SECTOR
                or relsect % (secsize // SECTOR)):
            raise RuntimeError(
                "label at sector %d has secsize %d, which cannot express a "
                "partition at LBA %d" % (sector, secsize, relsect))
        delta = relsect // (secsize // SECTOR)
        struct.pack_into(">i", head, off + DL_LABEL_BLKNO, relsect + sector)
        for i in range(NBOOTS):
            field = off + DL_BOOT0_BLKNO + 4 * i
            blkno = struct.unpack_from(">i", head, field)[0]
            if blkno >= 0:
                struct.pack_into(">i", head, field, blkno + delta)
        for i in range(NPART):
            field = off + DL_PARTITIONS + PARTITION_SIZE * i
            base = struct.unpack_from(">i", head, field)[0]
            if base >= 0:
                struct.pack_into(">i", head, field, base + delta)
        struct.pack_into(
            ">H", head, off + ufs_build.LABEL_CHECKSUM,
            ufs_build.label_checksum(
                head[off:off + ufs_build.LABEL_SUM_SHORTS * 2]))
        found += 1
    if not found:
        raise RuntimeError("no NeXT disk label in the first %d sectors"
                           % (len(head) // SECTOR))
    return found


def _require_whole_disk(head, path):
    if head[510:512] != b"\x55\xaa":
        return
    for n in range(4):
        if head[MBR_PART_OFFSET + 16 * n + 4] == FDISK_NEXTNAME:
            raise RuntimeError("%s already has an fdisk table with a 0xA7 "
                               "partition; build() needs a whole-disk image"
                               % path)


def _boot0_from(image_path):
    try:
        with rhap_image.Image(image_path) as img:
            ino = img.resolve(BOOT0_PATH)
            if ino is not None:
                return img.read_file(ino)
            problem = "it has no %s" % BOOT0_PATH
    except (ValueError, struct.error, IndexError) as e:
        problem = str(e)
    raise RuntimeError("cannot read boot0 from %s (%s); pass --boot0"
                       % (image_path, problem))


def build(rhapsody_image, efi_app, out_path, esp_mb=64, boot0=None):
    """Write the single-disk layout to out_path.

    rhapsody_image must be a whole-disk image (no 0xA7 fdisk entry of its
    own).  boot0 is the MBR code; by default it is read from the image's
    own /usr/standalone/i386/boot0."""
    for path in (rhapsody_image, efi_app):
        if not os.path.exists(path):
            raise RuntimeError("no such file: %s" % path)
    rhapsody_bytes = os.path.getsize(rhapsody_image)
    if rhapsody_bytes % SECTOR:
        raise RuntimeError("%s is not a whole number of %d-byte sectors"
                           % (rhapsody_image, SECTOR))
    with open(rhapsody_image, "rb") as src:
        head = bytearray(src.read(LABEL_SCAN_SECTORS * SECTOR))
    _require_whole_disk(head, rhapsody_image)

    esp_sectors = esp_mb * 1024 * 1024 // SECTOR
    rhapsody_sectors = rhapsody_bytes // SECTOR
    rhapsody_lba = ESP_LBA + esp_sectors
    total_sectors = rhapsody_lba + rhapsody_sectors
    geometry = lba_assist_geometry(total_sectors)
    rebase_labels(head, rhapsody_lba)
    if boot0 is None:
        boot0 = _boot0_from(rhapsody_image)
    if len(boot0) < DISK_BOOTSZ:
        raise RuntimeError("boot0 is %d bytes; need at least %d"
                           % (len(boot0), DISK_BOOTSZ))

    with open(out_path, "wb") as out:
        out.truncate(total_sectors * SECTOR)

        mbr = bytearray(SECTOR)
        mbr[:DISK_BOOTSZ] = boot0[:DISK_BOOTSZ]
        entries = (_part_entry(EFI_SYSTEM, ESP_LBA, esp_sectors, geometry)
                   + _part_entry(FDISK_NEXTNAME, rhapsody_lba,
                                 rhapsody_sectors, geometry, active=True))
        mbr[MBR_PART_OFFSET:MBR_PART_OFFSET + len(entries)] = entries
        mbr[510:512] = b"\x55\xaa"
        out.seek(0)
        out.write(mbr)

        out.seek(ESP_LBA * SECTOR)
        out.write(_esp_image(efi_app, esp_sectors))

        out.seek(rhapsody_lba * SECTOR)
        out.write(head)
        with open(rhapsody_image, "rb") as src:
            src.seek(len(head))
            shutil.copyfileobj(src, out, length=1024 * 1024)


def build_esp(efi_app, out_path, esp_mb=64):
    """Write an ESP-only MBR disk to out_path: a single 0xEF/FAT32 partition
    at ESP_LBA containing the EFI app, no second partition.

    This is the loader's disk in the two-disk layout, where the Rhapsody
    image is attached whole as the other disk; the loader falls back to the
    first labelled disk when the disk it was read from has no label.
    """
    if not os.path.exists(efi_app):
        raise RuntimeError("no such file: %s" % efi_app)

    esp_sectors = esp_mb * 1024 * 1024 // SECTOR
    total_sectors = ESP_LBA + esp_sectors
    geometry = lba_assist_geometry(total_sectors)

    with open(out_path, "wb") as out:
        out.truncate(total_sectors * SECTOR)

        mbr = bytearray(SECTOR)
        entries = _part_entry(EFI_SYSTEM, ESP_LBA, esp_sectors, geometry)
        mbr[MBR_PART_OFFSET:MBR_PART_OFFSET + len(entries)] = entries
        mbr[510:512] = b"\x55\xaa"
        out.seek(0)
        out.write(mbr)

        out.seek(ESP_LBA * SECTOR)
        out.write(_esp_image(efi_app, esp_sectors))


def main(argv):
    # A 16 MiB FAT32 volume has too few clusters to be structurally valid;
    # EDK2's FAT driver silently declines to mount it (no error, it just
    # never binds), and BDS reports "unable to boot". 64 MiB is comfortably
    # above the FAT32 minimum. (Task 3 finding.)
    argv = list(argv)
    boot0 = None
    if "--boot0" in argv:
        i = argv.index("--boot0")
        with open(argv[i + 1], "rb") as f:
            boot0 = f.read()
        del argv[i:i + 2]

    if len(argv) >= 2 and argv[1] == "--esp-only":
        rest = argv[2:]
        if len(rest) not in (2, 3):
            sys.stderr.write(
                "usage: %s --esp-only EFI_APP OUT_PATH [ESP_MB]\n" % argv[0])
            return 2
        esp_mb = int(rest[2]) if len(rest) == 3 else 64
        build_esp(rest[0], rest[1], esp_mb=esp_mb)
        return 0

    if len(argv) not in (4, 5):
        sys.stderr.write(
            "usage: %s [--boot0 FILE] RHAPSODY_IMAGE EFI_APP OUT_PATH [ESP_MB]\n"
            "       %s --esp-only EFI_APP OUT_PATH [ESP_MB]\n"
            % (argv[0], argv[0]))
        return 2
    esp_mb = int(argv[4]) if len(argv) == 5 else 64
    build(argv[1], argv[2], argv[3], esp_mb=esp_mb, boot0=boot0)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
