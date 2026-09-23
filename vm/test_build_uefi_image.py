import os
import shutil
import struct
import tempfile
import unittest

import build_uefi_image
import fat32

SECTOR = 512
MBR_PART_OFFSET = 446
FDISK_NEXTNAME = 0xA7
EFI_SYSTEM = 0xEF
EFI_APP = b"MZ" + b"\0" * 1022


def _part(mbr, n):
    """Unpack MBR partition entry n as (systid, lba_start, nsectors)."""
    off = MBR_PART_OFFSET + n * 16
    entry = mbr[off:off + 16]
    systid = entry[4]
    lba, count = struct.unpack("<II", entry[8:16])
    return systid, lba, count


def _esp_volume(path, lba, count):
    with open(path, "rb") as f:
        f.seek(lba * SECTOR)
        return f.read(count * SECTOR)


class TestBuildUefiImage(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="uefi-image-test-")
        self.addCleanup(shutil.rmtree, self.tmp)
        self.rhapsody = os.path.join(self.tmp, "rhapsody.img")
        with open(self.rhapsody, "wb") as f:
            f.write(b"RHAP" * (4 * 1024 * 1024 // 4))
        self.efi = os.path.join(self.tmp, "BOOTIA32.EFI")
        with open(self.efi, "wb") as f:
            f.write(EFI_APP)
        self.out = os.path.join(self.tmp, "hybrid.img")

    def test_mbr_has_esp_and_rhapsody_partitions(self):
        build_uefi_image.build(self.rhapsody, self.efi, self.out, esp_mb=64)
        with open(self.out, "rb") as f:
            mbr = f.read(SECTOR)
        self.assertEqual(mbr[510:512], b"\x55\xaa")
        self.assertEqual(_part(mbr, 0)[0], EFI_SYSTEM)
        self.assertEqual(_part(mbr, 1)[0], FDISK_NEXTNAME)

    def test_esp_contains_the_efi_app_at_the_removable_media_path(self):
        build_uefi_image.build(self.rhapsody, self.efi, self.out, esp_mb=64)
        with open(self.out, "rb") as f:
            mbr = f.read(SECTOR)
        _, lba, count = _part(mbr, 0)
        esp = _esp_volume(self.out, lba, count)
        self.assertEqual(fat32.read_file(esp, "EFI/BOOT/BOOTIA32.EFI"), EFI_APP)

    def test_missing_rhapsody_image_raises(self):
        with self.assertRaises(RuntimeError):
            build_uefi_image.build(os.path.join(self.tmp, "nope.img"),
                                   self.efi, self.out, esp_mb=64)


class TestBuildEspOnly(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="uefi-esp-test-")
        self.addCleanup(shutil.rmtree, self.tmp)
        self.efi = os.path.join(self.tmp, "BOOTIA32.EFI")
        with open(self.efi, "wb") as f:
            f.write(EFI_APP)
        self.out = os.path.join(self.tmp, "esp.img")

    def test_partition_1_is_esp_at_lba_2048(self):
        build_uefi_image.build_esp(self.efi, self.out, esp_mb=64)
        with open(self.out, "rb") as f:
            mbr = f.read(SECTOR)
        self.assertEqual(mbr[510:512], b"\x55\xaa")
        self.assertEqual(_part(mbr, 0),
                         (EFI_SYSTEM, 2048, 64 * 1024 * 1024 // SECTOR))

    def test_no_second_partition(self):
        build_uefi_image.build_esp(self.efi, self.out, esp_mb=64)
        with open(self.out, "rb") as f:
            mbr = f.read(SECTOR)
        self.assertEqual(_part(mbr, 1), (0, 0, 0))

    def test_efi_app_present_at_boot_path(self):
        build_uefi_image.build_esp(self.efi, self.out, esp_mb=64)
        with open(self.out, "rb") as f:
            mbr = f.read(SECTOR)
        _, lba, count = _part(mbr, 0)
        esp = _esp_volume(self.out, lba, count)
        self.assertEqual(fat32.read_file(esp, "EFI/BOOT/BOOTIA32.EFI"), EFI_APP)

    def test_missing_efi_app_raises(self):
        with self.assertRaises(RuntimeError):
            build_uefi_image.build_esp(os.path.join(self.tmp, "nope.efi"),
                                       self.out, esp_mb=64)


if __name__ == "__main__":
    unittest.main()
