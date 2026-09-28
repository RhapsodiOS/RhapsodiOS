import os
import struct
import tempfile
import unittest

import build_uefi_image as bui
import fat32
import rhap_image
import ufs_check
from ufs_extract import Node
from instmedia import hdimage, readback

NOW = 946684800
BOOT0 = bytes([0x11]) * 446
BOOT1 = bytes([0x22]) * 510 + b"\x55\xaa"
BOOT2 = bytes(range(256)) * 160          # 40960 bytes, 80 sectors
EFI = b"MZ" + b"not really a PE image" * 100
NODES = [
    Node("/", "dir", 0o755, 0, 0, NOW, None),
    Node("/mach_kernel", "reg", 0o444, 0, 0, NOW, b"kernel" * 5000),
    Node("/private", "dir", 0o755, 0, 0, NOW, None),
    Node("/private/tftpboot", "dir", 0o755, 0, 0, NOW, None),
    Node("/private/tftpboot/mach_kernel", "hlink", 0, 0, 0, 0,
         "/mach_kernel"),
    Node("/etc", "lnk", 0o755, 0, 0, NOW, "private/etc"),
]


class TestDiskSectors(unittest.TestCase):
    def test_ends_on_a_cylinder_of_its_own_geometry(self):
        for fs in (16384, 1000000, 2000000, 4194304):
            total = hdimage.disk_sectors(fs)
            heads, spt = bui.lba_assist_geometry(total)
            self.assertEqual(total % (heads * spt), 0)
            self.assertGreaterEqual(total,
                                    hdimage.A7_LBA + hdimage.FRONT + fs)
            self.assertLess(total - (hdimage.A7_LBA + hdimage.FRONT + fs),
                            heads * spt)


class TestWrite(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.path = os.path.join(cls.tmp.name, "disk.img")
        cls.esp = hdimage.esp_image(EFI)
        cls.g, cls.total = hdimage.write(cls.path, 16384, BOOT0, BOOT1,
                                         BOOT2, cls.esp, NODES, NOW)
        with open(cls.path, "rb") as f:
            cls.head = f.read((hdimage.A7_LBA + hdimage.FRONT) * 512)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def sectors(self, lba, n=1):
        return self.head[lba * 512:(lba + n) * 512]

    def test_mbr_holds_boot0_and_the_two_entries(self):
        mbr = self.sectors(0)
        geo = bui.lba_assist_geometry(self.total)
        self.assertEqual(mbr[:446], BOOT0)
        self.assertEqual(mbr[446:462], bui._part_entry(
            0xEF, 2048, 131072, geo))
        self.assertEqual(mbr[462:478], bui._part_entry(
            0xA7, 133120, self.total - 133120, geo, active=True))
        self.assertEqual(mbr[478:510], bytes(32))
        self.assertEqual(mbr[510:], b"\x55\xaa")

    def test_esp_holds_the_loader(self):
        esp = self.sectors(2048, 131072)
        self.assertEqual(esp, self.esp)
        self.assertEqual(fat32.read_file(esp, "EFI/BOOT/BOOTIA32.EFI"), EFI)

    def test_partition_interior_is_what_disk_i_b_writes(self):
        self.assertEqual(self.sectors(133120), BOOT1)
        for rel in (64, 192):
            self.assertEqual(self.sectors(133120 + rel, 80), BOOT2)
        for rel in (15, 30, 45):
            copy = self.sectors(133120 + rel, 2)
            self.assertEqual(copy[:4], b"dlV3")
            self.assertEqual(struct.unpack_from(">i", copy, 4)[0],
                             133120 + rel)
            self.assertEqual(struct.unpack_from(">ii", copy, 124),
                             (133120 + 64, 133120 + 192))
        with rhap_image.Image(self.path) as img:
            self.assertEqual(img.label["secsize"], 512)
            self.assertEqual(img.label["front"], 320)
            self.assertEqual(img.label["p_base"], 133120)
            self.assertEqual(img.label["p_size"], self.g.fssize)
            self.assertEqual(img.part_start, (133120 + 320) * 512)

    def test_filesystem_reads_back_clean(self):
        self.assertEqual(readback.diff(self.path, NODES), [])
        self.assertEqual(ufs_check.check(self.path), [])


class TestRefusals(unittest.TestCase):
    def write(self, **kw):
        args = dict(boot0=BOOT0, boot1=BOOT1, boot2=BOOT2,
                    esp=hdimage.esp_image(EFI))
        args.update(kw)
        with tempfile.TemporaryDirectory() as tmp:
            hdimage.write(os.path.join(tmp, "d.img"), 16384, args["boot0"],
                          args["boot1"], args["boot2"], args["esp"], NODES,
                          NOW)

    def test_boot1_over_a_sector(self):
        with self.assertRaises(hdimage.ImageError):
            self.write(boot1=b"x" * 513)

    def test_boot2_past_dl_front(self):
        with self.assertRaises(hdimage.ImageError):
            self.write(boot2=b"x" * (128 * 512 + 1))

    def test_esp_of_the_wrong_size(self):
        with self.assertRaises(hdimage.ImageError):
            self.write(esp=b"x" * 512)


if __name__ == "__main__":
    unittest.main()
