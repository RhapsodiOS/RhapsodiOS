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


class TestBootImage(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.path = os.path.join(cls.tmp.name, "boot.img")
        cls.g, cls.total = hdimage.boot_image(cls.path, 16384, BOOT0, BOOT1,
                                              BOOT2, NODES, NOW)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def read(self, lba, n=1):
        with open(self.path, "rb") as f:
            f.seek(lba * 512)
            return f.read(n * 512)

    def test_boot_image_layout(self):
        mbr = self.read(0)
        self.assertEqual(mbr[:446], BOOT0)
        self.assertEqual(mbr[462:510], bytes(48))
        self.assertEqual(mbr[510:], b"\x55\xaa")
        active, systid, start, size = (mbr[446], mbr[450],
                                       *struct.unpack_from("<II", mbr, 454))
        self.assertEqual((active, systid, start), (0x80, 0xA7, 63))
        self.assertEqual(self.read(63), BOOT1)
        for rel in (64, 192):
            self.assertEqual(self.read(63 + rel, 80), BOOT2)
        copy = self.read(63 + 15, 2)
        self.assertEqual(copy[:4], b"dlV3")
        with rhap_image.Image(self.path) as img:
            self.assertEqual(img.label["p_base"], 63)
            self.assertEqual(img.part_start, (63 + 320) * 512)
        self.assertEqual(readback.diff(self.path, NODES), [])
        self.assertEqual(ufs_check.check(self.path), [])

    def test_boot_image_is_16_mb(self):
        self.assertEqual(self.total, hdimage.BOOT_IMAGE_SECTORS)
        self.assertEqual(os.path.getsize(self.path), 16 * 1024 * 1024)

    def test_boot_image_ends_on_a_cylinder(self):
        heads, spt = bui.lba_assist_geometry(32768)
        mbr = self.read(0)
        start, size = struct.unpack_from("<II", mbr, 454)
        self.assertEqual((start + size) % (heads * spt), 0)
        self.assertGreater(start + size, 32768 - heads * spt)
        self.assertEqual(mbr[446:462], bui._part_entry(
            0xA7, start, size, (heads, spt), active=True))

    def test_boot_image_refuses_too_much(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(hdimage.ImageError):
                hdimage.boot_image(os.path.join(tmp, "b.img"), 40000, BOOT0,
                                   BOOT1, BOOT2, NODES, NOW)
            big = NODES + [Node("/big", "reg", 0o644, 0, 0, NOW,
                                bytes(20 * 1024 * 1024))]
            with self.assertRaises(hdimage.ImageError):
                hdimage.boot_image(os.path.join(tmp, "b.img"), 16384, BOOT0,
                                   BOOT1, BOOT2, big, NOW)


if __name__ == "__main__":
    unittest.main()
