import os
import shutil
import struct
import subprocess
import tempfile
import unittest

import build_uefi_image

HERE = os.path.dirname(os.path.abspath(__file__))

SECTOR = 512
MBR_PART_OFFSET = 446
FDISK_NEXTNAME = 0xA7
EFI_SYSTEM = 0xEF


def _have_mtools():
    return all(shutil.which(t) for t in ("mformat", "mmd", "mcopy"))


def _part(mbr, n):
    """Unpack MBR partition entry n as (systid, lba_start, nsectors)."""
    off = MBR_PART_OFFSET + n * 16
    entry = mbr[off:off + 16]
    systid = entry[4]
    lba, count = struct.unpack("<II", entry[8:16])
    return systid, lba, count


class TestBuildUefiImage(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="uefi-image-test-")
        self.addCleanup(shutil.rmtree, self.tmp)
        # A stand-in Rhapsody partition: 4 MB of recognisable bytes.
        self.rhapsody = os.path.join(self.tmp, "rhapsody.img")
        with open(self.rhapsody, "wb") as f:
            f.write(b"RHAP" * (4 * 1024 * 1024 // 4))
        self.efi = os.path.join(self.tmp, "BOOTIA32.EFI")
        with open(self.efi, "wb") as f:
            f.write(b"MZ" + b"\0" * 1022)
        self.out = os.path.join(self.tmp, "hybrid.img")

    @unittest.skipUnless(_have_mtools(), "mtools not installed")
    def test_mbr_has_esp_and_rhapsody_partitions(self):
        build_uefi_image.build(self.rhapsody, self.efi, self.out, esp_mb=16)
        with open(self.out, "rb") as f:
            mbr = f.read(SECTOR)
        self.assertEqual(mbr[510:512], b"\x55\xaa")
        self.assertEqual(_part(mbr, 0)[0], EFI_SYSTEM)
        self.assertEqual(_part(mbr, 1)[0], FDISK_NEXTNAME)

    @unittest.skipUnless(_have_mtools(), "mtools not installed")
    def test_rhapsody_partition_is_copied_verbatim_at_its_lba(self):
        build_uefi_image.build(self.rhapsody, self.efi, self.out, esp_mb=16)
        with open(self.out, "rb") as f:
            mbr = f.read(SECTOR)
            _, lba, count = _part(mbr, 1)
            f.seek(lba * SECTOR)
            head = f.read(16)
        self.assertEqual(head, b"RHAP" * 4)
        self.assertEqual(count, 4 * 1024 * 1024 // SECTOR)

    @unittest.skipUnless(_have_mtools(), "mtools not installed")
    def test_esp_contains_the_efi_app_at_the_removable_media_path(self):
        build_uefi_image.build(self.rhapsody, self.efi, self.out, esp_mb=16)
        with open(self.out, "rb") as f:
            mbr = f.read(SECTOR)
        _, lba, _ = _part(mbr, 0)
        listing = subprocess.check_output(
            ["mdir", "-i", "%s@@%d" % (self.out, lba * SECTOR), "::/EFI/BOOT"],
            stderr=subprocess.STDOUT).decode()
        self.assertIn("BOOTIA32", listing)

    def test_missing_rhapsody_image_raises(self):
        with self.assertRaises(RuntimeError):
            build_uefi_image.build(os.path.join(self.tmp, "nope.img"),
                                   self.efi, self.out, esp_mb=16)


if __name__ == "__main__":
    unittest.main()
