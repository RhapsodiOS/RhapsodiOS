import os
import shutil
import struct
import tempfile
import unittest

import build_uefi_image
import fat32
import rhap_image
import ufs_build

HERE = os.path.dirname(os.path.abspath(__file__))
FLOPPY = os.environ.get(
    "RHAPSODY_FLOPPY",
    os.path.join(HERE, "install", "rhapsody_dr2_x86_InstallationFloppy.img"))

SECTOR = 512
MBR_PART_OFFSET = 446
FDISK_NEXTNAME = 0xA7
EFI_SYSTEM = 0xEF
EFI_APP = b"MZ" + b"\0" * 1022
BOOT0 = b"\xfa\x33\xc0" + bytes(range(256)) + b"\x90" * 253
SOURCE_SECTORS = 4 * 1024 * 1024 // SECTOR
ESP_SECTORS = 64 * 1024 * 1024 // SECTOR


def _part(mbr, n):
    """MBR entry n as (bootid, start_chs, systid, lba_start, nsectors)."""
    off = MBR_PART_OFFSET + n * 16
    e = mbr[off:off + 16]
    lba, count = struct.unpack("<II", e[8:16])
    return e[0], bytes(e[1:4]), e[4], lba, count


def _label(sector, secsize=1024, front=160):
    """A whole-disk NeXT label copy, two sectors long, as disk -i writes one
    on a disk with no fdisk table."""
    lab = bytearray(2 * SECTOR)
    lab[0:4] = b"dlV3"
    struct.pack_into(">i", lab, 4, sector)
    struct.pack_into(">i", lab, 92, secsize)
    struct.pack_into(">h", lab, 112, front)
    struct.pack_into(">ii", lab, 124, 32 * 1024 // secsize,
                     96 * 1024 // secsize)
    struct.pack_into(">ii", lab, 190, 0, 4096)
    for i in range(1, 8):
        struct.pack_into(">i", lab, 190 + 46 * i, -1)
    struct.pack_into(">H", lab, ufs_build.LABEL_CHECKSUM,
                     ufs_build.label_checksum(
                         lab[:ufs_build.LABEL_SUM_SHORTS * 2]))
    return lab


def _whole_disk(path, secsize=1024):
    """A 4 MB stand-in whole-disk image: boot1 in sector 0, label copies at
    sectors 15, 30 and 45, recognisable filler everywhere else."""
    image = bytearray(b"RHAP" * (SOURCE_SECTORS * SECTOR // 4))
    image[0:SECTOR] = b"BOOT1" + b"\0" * (SECTOR - 7) + b"\x55\xaa"
    for s in (15, 30, 45):
        image[s * SECTOR:(s + 2) * SECTOR] = _label(s, secsize)
    with open(path, "wb") as f:
        f.write(image)
    return bytes(image)


def _write(path, data):
    with open(path, "wb") as f:
        f.write(data)


class TestHybrid(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="uefi-image-test-")
        cls.rhapsody = os.path.join(cls.tmp, "rhapsody.img")
        cls.source = _whole_disk(cls.rhapsody)
        cls.efi = os.path.join(cls.tmp, "BOOTIA32.EFI")
        _write(cls.efi, EFI_APP)
        cls.out = os.path.join(cls.tmp, "hybrid.img")
        build_uefi_image.build(cls.rhapsody, cls.efi, cls.out, esp_mb=64,
                               boot0=BOOT0)
        with open(cls.out, "rb") as f:
            cls.mbr = f.read(SECTOR)
        cls.lba = _part(cls.mbr, 1)[3]

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def _partition(self, sector, count=1):
        with open(self.out, "rb") as f:
            f.seek((self.lba + sector) * SECTOR)
            return f.read(count * SECTOR)

    def test_mbr_carries_boot0_code_and_signature(self):
        self.assertEqual(self.mbr[:446], BOOT0[:446])
        self.assertEqual(self.mbr[510:512], b"\x55\xaa")

    def test_esp_is_first_and_inactive(self):
        bootid, _, systid, lba, count = _part(self.mbr, 0)
        self.assertEqual((bootid, systid, lba, count),
                         (0x00, EFI_SYSTEM, 2048, ESP_SECTORS))

    def test_rhapsody_partition_is_active_after_the_esp(self):
        bootid, _, systid, lba, count = _part(self.mbr, 1)
        self.assertEqual((bootid, systid, lba, count),
                         (0x80, FDISK_NEXTNAME, 2048 + ESP_SECTORS,
                          SOURCE_SECTORS))

    def test_start_chs_uses_lba_assisted_geometry(self):
        heads, spt = build_uefi_image.lba_assist_geometry(
            self.lba + SOURCE_SECTORS)
        self.assertEqual(_part(self.mbr, 1)[1],
                         build_uefi_image.chs(self.lba, heads, spt))

    def test_every_label_copy_is_rebased(self):
        delta = self.lba // 2                    # secsize 1024
        for s in (15, 30, 45):
            lab = self._partition(s, 2)
            self.assertEqual(struct.unpack_from(">i", lab, 4)[0],
                             self.lba + s)
            self.assertEqual(struct.unpack_from(">i", lab, 190)[0], delta)
            self.assertEqual(struct.unpack_from(">ii", lab, 124),
                             (32 + delta, 96 + delta))
            self.assertEqual(struct.unpack_from(">i", lab, 190 + 46)[0], -1)
            self.assertEqual(struct.unpack_from(">h", lab, 112)[0], 160)
            self.assertEqual(
                struct.unpack_from(">H", lab, ufs_build.LABEL_CHECKSUM)[0],
                ufs_build.label_checksum(
                    lab[:ufs_build.LABEL_SUM_SHORTS * 2]))

    def test_boot1_and_data_are_copied_verbatim(self):
        self.assertEqual(self._partition(0), self.source[:SECTOR])
        self.assertEqual(self._partition(100),
                         self.source[100 * SECTOR:101 * SECTOR])

    def test_esp_holds_the_loader(self):
        with open(self.out, "rb") as f:
            f.seek(2048 * SECTOR)
            esp = f.read(ESP_SECTORS * SECTOR)
        self.assertEqual(fat32.read_file(esp, "EFI/BOOT/BOOTIA32.EFI"),
                         EFI_APP)


class TestBuildRefusals(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="uefi-image-test-")
        self.addCleanup(shutil.rmtree, self.tmp)
        self.efi = os.path.join(self.tmp, "BOOTIA32.EFI")
        _write(self.efi, EFI_APP)
        self.out = os.path.join(self.tmp, "hybrid.img")

    def test_missing_rhapsody_image_raises(self):
        with self.assertRaises(RuntimeError):
            build_uefi_image.build(os.path.join(self.tmp, "nope.img"),
                                   self.efi, self.out, boot0=BOOT0)

    def test_unlabelled_source_raises(self):
        src = os.path.join(self.tmp, "plain.img")
        _write(src, b"RHAP" * (SOURCE_SECTORS * SECTOR // 4))
        with self.assertRaises(RuntimeError):
            build_uefi_image.build(src, self.efi, self.out, boot0=BOOT0)

    def test_already_partitioned_source_raises(self):
        src = os.path.join(self.tmp, "parted.img")
        image = bytearray(_whole_disk(src))
        image[MBR_PART_OFFSET + 4] = FDISK_NEXTNAME
        _write(src, image)
        with self.assertRaises(RuntimeError):
            build_uefi_image.build(src, self.efi, self.out, boot0=BOOT0)

    def test_source_without_readable_boot0_asks_for_the_option(self):
        src = os.path.join(self.tmp, "whole.img")
        _whole_disk(src)
        with self.assertRaises(RuntimeError):
            build_uefi_image.build(src, self.efi, self.out)

    def test_rebase_refuses_an_unrepresentable_offset(self):
        head = bytearray(64 * SECTOR)
        head[15 * SECTOR:17 * SECTOR] = _label(15, secsize=1024)
        with self.assertRaises(RuntimeError):
            build_uefi_image.rebase_labels(head, 133121)


class TestGeometry(unittest.TestCase):
    def test_large_disk_gets_255_heads(self):
        self.assertEqual(build_uefi_image.lba_assist_geometry(16910336),
                         (255, 63))

    def test_one_gigabyte_disk_gets_32_heads(self):
        self.assertEqual(build_uefi_image.lba_assist_geometry(2097152),
                         (32, 63))

    def test_small_disk_gets_16_heads(self):
        self.assertEqual(build_uefi_image.lba_assist_geometry(204800),
                         (16, 63))

    def test_chs_of_sector_zero(self):
        self.assertEqual(build_uefi_image.chs(0, 255, 63), b"\x00\x01\x00")

    def test_chs_of_the_hybrid_partition_start(self):
        # 133120 = cylinder 8 (8 * 16065 = 128520), head 73, sector 2
        self.assertEqual(build_uefi_image.chs(133120, 255, 63),
                         bytes([73, 2, 8]))

    def test_chs_past_cylinder_1023(self):
        self.assertEqual(build_uefi_image.chs(1024 * 255 * 63, 255, 63),
                         b"\xfe\xff\xff")


@unittest.skipUnless(os.path.exists(FLOPPY),
                     "set RHAPSODY_FLOPPY to the DR2 installation floppy")
class TestRealMedia(unittest.TestCase):
    def test_rhap_image_reads_a_file_back_out_of_the_partition(self):
        tmp = tempfile.mkdtemp(prefix="uefi-image-test-")
        self.addCleanup(shutil.rmtree, tmp)
        efi = os.path.join(tmp, "BOOTIA32.EFI")
        _write(efi, EFI_APP)
        out = os.path.join(tmp, "hybrid.img")
        build_uefi_image.build(FLOPPY, efi, out, esp_mb=64, boot0=BOOT0)
        with rhap_image.Image(FLOPPY) as img:
            want = img.read_file(img.resolve("/mach_kernel.rcz"))
        with rhap_image.Image(out) as img:
            got = img.read_file(img.resolve("/mach_kernel.rcz"))
            self.assertEqual(img.part_start,
                             (2048 + ESP_SECTORS) * SECTOR
                             + img.label["front"] * img.label["secsize"])
        self.assertEqual(got, want)


class TestBuildEspOnly(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="uefi-esp-test-")
        self.addCleanup(shutil.rmtree, self.tmp)
        self.efi = os.path.join(self.tmp, "BOOTIA32.EFI")
        _write(self.efi, EFI_APP)
        self.out = os.path.join(self.tmp, "esp.img")
        build_uefi_image.build_esp(self.efi, self.out, esp_mb=64)
        with open(self.out, "rb") as f:
            self.mbr = f.read(SECTOR)

    def test_partition_1_is_esp_at_lba_2048(self):
        self.assertEqual(self.mbr[510:512], b"\x55\xaa")
        _, _, systid, lba, count = _part(self.mbr, 0)
        self.assertEqual((systid, lba, count), (EFI_SYSTEM, 2048, ESP_SECTORS))

    def test_no_second_partition(self):
        self.assertEqual(_part(self.mbr, 1), (0, b"\0\0\0", 0, 0, 0))

    def test_efi_app_present_at_boot_path(self):
        with open(self.out, "rb") as f:
            f.seek(2048 * SECTOR)
            esp = f.read(ESP_SECTORS * SECTOR)
        self.assertEqual(fat32.read_file(esp, "EFI/BOOT/BOOTIA32.EFI"),
                         EFI_APP)

    def test_missing_efi_app_raises(self):
        with self.assertRaises(RuntimeError):
            build_uefi_image.build_esp(os.path.join(self.tmp, "nope.efi"),
                                       self.out, esp_mb=64)


if __name__ == "__main__":
    unittest.main()
