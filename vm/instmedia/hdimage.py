"""The hard-disk form of the install media.

    LBA 0       boot0 and the fdisk table: entry 1 is the ESP (0xEF) at
                2048 for 131072 sectors, entry 2 the active 0xA7 partition
                from 133120 to the last sector
    LBA 2048    the ESP: FAT32, 64 MB, holding only /EFI/BOOT/BOOTIA32.EFI
    LBA 133120  the 0xA7 partition as `disk -i -b` lays it out on an fdisk
                disk: boot1 in its first sector, label copies at +15/30/45
                with secsize 512 and absolute p_base and d_boot0_blkno,
                boot2 at +64 and +192, and the UFS from +320 (dl_front)

The disk ends on a cylinder boundary of the LBA-assisted geometry the BIOS
will pick for it, so the 0xA7 entry's end CHS is exact (see the CHS
translation risk in the install-media design).
"""
import build_uefi_image as bui
import fat32
from instmedia import label, space, ufs, ufs_geometry

SECTOR = 512
ESP_LBA = bui.ESP_LBA               # 2048
# 64 MB: EDK2's FAT driver ignores a FAT32 volume with too few clusters.
ESP_SECTORS = 131072
A7_LBA = ESP_LBA + ESP_SECTORS      # 133120
# diskdev_cmds/disk.tproj/hd.c: a 160 KB front porch, and the two boot2
# copies at 32 KB and 96 KB into the partition, in secsize-512 sectors.
FRONT = 160 * 1024 // SECTOR
BOOT2_BLKNOS = (32 * 1024 // SECTOR, 96 * 1024 // SECTOR)
# disk.c refuses a boot2 copy that runs past dl_front.
BOOT2_MAX_SECTORS = FRONT - BOOT2_BLKNOS[1]
NSECT, NTRAK, RPM = 63, 16, 3600
# The BIOS boot image: 16 MB, its one 0xA7 partition starting at the
# conventional first-track-after-MBR LBA.
BOOT_IMAGE_SECTORS = 32768
BOOT_A7_LBA = 63


class ImageError(Exception):
    pass


def esp_image(efi):
    """The ESP's bytes: FAT32 holding the loader at the removable-media path
    UEFI firmware boots from."""
    return fat32.build(ESP_SECTORS, {bui.ESP_BOOT_PATH: efi},
                       label="RHAPEFI", hidden_sectors=ESP_LBA)


def disk_sectors(fs_sectors):
    """Total sectors for at least fs_sectors of UFS, rounded up to a whole
    cylinder of the disk's own LBA-assisted geometry."""
    total = A7_LBA + FRONT + fs_sectors
    while True:
        heads, spt = bui.lba_assist_geometry(total)
        rounded = -(-total // (heads * spt)) * (heads * spt)
        if bui.lba_assist_geometry(rounded) == (heads, spt):
            return rounded
        total = rounded


def _check_booters(boot1, boot2):
    if len(boot1) > SECTOR:
        raise ImageError("boot1 is %d bytes; it must fit in one sector"
                         % len(boot1))
    if len(boot2) > BOOT2_MAX_SECTORS * SECTOR:
        raise ImageError("boot2 is %d bytes; at most %d fit between its "
                         "second copy and dl_front"
                         % (len(boot2), BOOT2_MAX_SECTORS * SECTOR))


def _write_a7(f, a7_lba, total, boot1, boot2, nodes, now, name):
    """Lay out the 0xA7 partition at a7_lba of a disk of total sectors, as
    `disk -i -b` does, and the UFS in it; returns the ufs geometry."""
    g = ufs_geometry.geometry(fssize=total - a7_lba - FRONT,
                              secsize=SECTOR, nsect=NSECT, ntrak=NTRAK,
                              rpm=RPM)
    lbl = label.for_filesystem(
        g, front=FRONT, p_base=a7_lba, ncylinders=total // g.spc,
        name=name, d_type="fixed_rw_ide",
        boot0=(a7_lba + BOOT2_BLKNOS[0], a7_lba + BOOT2_BLKNOS[1]))
    f.seek(a7_lba * SECTOR)
    f.write(boot1)
    label.place(f, lbl, label.DISK_COPIES, a7_lba)
    for blk in BOOT2_BLKNOS:
        f.seek((a7_lba + blk) * SECTOR)
        f.write(boot2)
    ufs.write(f, (a7_lba + FRONT) * SECTOR, g, nodes, now)
    return g


def write(path, fs_sectors, boot0, boot1, boot2, esp, nodes, now,
          name="RhapsodiOS"):
    """Write the disk image to path; returns (ufs geometry, total sectors).

    boot0, boot1 and boot2 are the booters from the boot apk
    (/usr/standalone/i386/boot0, boot1 and boot), esp is esp_image()'s
    result, and nodes and now go to ufs.write.
    """
    _check_booters(boot1, boot2)
    if len(esp) != ESP_SECTORS * SECTOR:
        raise ImageError("the ESP image is %d bytes, not %d"
                         % (len(esp), ESP_SECTORS * SECTOR))
    total = disk_sectors(fs_sectors)
    geo = bui.lba_assist_geometry(total)
    mbr = bytearray(SECTOR)
    mbr[:bui.DISK_BOOTSZ] = boot0[:bui.DISK_BOOTSZ]
    mbr[446:462] = bui._part_entry(bui.EFI_SYSTEM, ESP_LBA, ESP_SECTORS, geo)
    mbr[462:478] = bui._part_entry(bui.FDISK_NEXTNAME, A7_LBA,
                                   total - A7_LBA, geo, active=True)
    mbr[510:512] = b"\x55\xaa"
    with open(path, "wb") as f:
        f.truncate(total * SECTOR)
        f.write(mbr)
        f.seek(ESP_LBA * SECTOR)
        f.write(esp)
        g = _write_a7(f, A7_LBA, total, boot1, boot2, nodes, now, name)
    return g, total


def boot_image(path, fs_sectors, boot0, boot1, boot2, nodes, now,
               name="RhapsodiOS"):
    """Write the small disk the CD's BIOS boot hands to El Torito hard-disk
    emulation; returns (ufs geometry, total sectors).

    One active 0xA7 entry from BOOT_A7_LBA to the last whole cylinder of the
    LBA-assisted geometry of a BOOT_IMAGE_SECTORS disk (so SeaBIOS derives
    the emulated disk's geometry from an exact end CHS), then padding to
    exactly BOOT_IMAGE_SECTORS.  The 0xA7 interior is write()'s.
    """
    _check_booters(boot1, boot2)
    heads, spt = bui.lba_assist_geometry(BOOT_IMAGE_SECTORS)
    end = BOOT_IMAGE_SECTORS // (heads * spt) * (heads * spt)
    if fs_sectors > end - BOOT_A7_LBA - FRONT:
        raise ImageError("%d sectors of UFS do not fit in the %d-sector "
                         "boot image" % (fs_sectors, BOOT_IMAGE_SECTORS))
    mbr = bytearray(SECTOR)
    mbr[:bui.DISK_BOOTSZ] = boot0[:bui.DISK_BOOTSZ]
    mbr[446:462] = bui._part_entry(bui.FDISK_NEXTNAME, BOOT_A7_LBA,
                                   end - BOOT_A7_LBA, (heads, spt),
                                   active=True)
    mbr[510:512] = b"\x55\xaa"
    with open(path, "wb") as f:
        f.truncate(BOOT_IMAGE_SECTORS * SECTOR)
        f.write(mbr)
        try:
            g = _write_a7(f, BOOT_A7_LBA, end, boot1, boot2, nodes, now,
                          name)
        except (ufs.TreeError, space.NoSpace) as e:
            raise ImageError("the boot image's filesystem: %s" % e)
    return g, BOOT_IMAGE_SECTORS
