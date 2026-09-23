import struct
import unittest

import fat32

SECTORS = 131072            # 64 MB, the ESP size build_uefi_image uses
APP_PATH = "EFI/BOOT/BOOTIA32.EFI"


def _payload(n):
    return bytes((i * 131 + 7) & 0xFF for i in range(n))


class TestFat32(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = _payload(70001)
        cls.image = fat32.build(SECTORS, {APP_PATH: cls.app},
                                hidden_sectors=2048)

    def test_size_is_exact(self):
        self.assertEqual(len(self.image), SECTORS * 512)

    def test_boot_sector_describes_fat32(self):
        img = self.image
        self.assertEqual(img[510:512], b"\x55\xaa")
        self.assertEqual(img[82:90], b"FAT32   ")
        self.assertEqual(struct.unpack_from("<HBHB", img, 11), (512, 1, 32, 2))
        self.assertEqual(struct.unpack_from("<I", img, 28)[0], 2048)
        self.assertEqual(struct.unpack_from("<I", img, 32)[0], SECTORS)
        self.assertEqual(struct.unpack_from("<I", img, 44)[0], 2)

    def test_backup_boot_sector_matches(self):
        self.assertEqual(self.image[6 * 512:7 * 512], self.image[0:512])

    def test_fsinfo_signatures(self):
        fsi = self.image[512:1024]
        self.assertEqual(struct.unpack_from("<I", fsi, 0)[0], 0x41615252)
        self.assertEqual(struct.unpack_from("<I", fsi, 484)[0], 0x61417272)
        self.assertEqual(struct.unpack_from("<I", fsi, 508)[0], 0xAA550000)

    def test_cluster_count_is_in_fat32_range(self):
        fatsz = struct.unpack_from("<I", self.image, 36)[0]
        clusters = SECTORS - 32 - 2 * fatsz
        self.assertGreaterEqual(clusters, fat32.FAT32_MIN_CLUSTERS)
        self.assertGreaterEqual(fatsz * 512 // 4, clusters + 2)

    def test_both_fats_are_identical(self):
        fatsz = struct.unpack_from("<I", self.image, 36)[0]
        first = self.image[32 * 512:(32 + fatsz) * 512]
        second = self.image[(32 + fatsz) * 512:(32 + 2 * fatsz) * 512]
        self.assertEqual(first, second)

    def test_file_reads_back(self):
        self.assertEqual(fat32.read_file(self.image, APP_PATH), self.app)

    def test_build_is_deterministic(self):
        again = fat32.build(SECTORS, {APP_PATH: self.app}, hidden_sectors=2048)
        self.assertEqual(again, self.image)

    def test_missing_file_raises(self):
        with self.assertRaises(fat32.FatError):
            fat32.read_file(self.image, "EFI/BOOT/BOOTX64.EFI")


class TestFat32Refusals(unittest.TestCase):
    def test_empty_file_reads_back_empty(self):
        image = fat32.build(SECTORS, {"EMPTY.TXT": b""})
        self.assertEqual(fat32.read_file(image, "EMPTY.TXT"), b"")

    def test_lower_case_name_rejected(self):
        with self.assertRaises(fat32.FatError):
            fat32.build(SECTORS, {"EFI/BOOT/bootia32.efi": b"x"})

    def test_long_name_rejected(self):
        with self.assertRaises(fat32.FatError):
            fat32.build(SECTORS, {"EFI/BOOT/LONGFILENAME.EFI": b"x"})

    def test_too_few_clusters_rejected(self):
        with self.assertRaises(fat32.FatError):
            fat32.build(32768, {APP_PATH: b"x"})

    def test_overfull_volume_rejected(self):
        with self.assertRaises(fat32.FatError):
            fat32.build(70000, {"BIG.BIN": b"\0" * (70000 * 512)})

    def test_directory_needing_two_clusters_rejected(self):
        files = dict(("D/F%02d.BIN" % i, b"x") for i in range(20))
        with self.assertRaises(fat32.FatError):
            fat32.build(SECTORS, files)


if __name__ == "__main__":
    unittest.main()
