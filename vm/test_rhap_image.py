import os
import unittest

import rhap_image

IMAGE = os.path.join(os.path.dirname(__file__), "golden.img")


@unittest.skipUnless(os.path.exists(IMAGE), "golden.img not built yet")
class TestLabel(unittest.TestCase):
    def setUp(self):
        self.img = rhap_image.Image(IMAGE)

    def tearDown(self):
        self.img.close()

    def test_label_is_big_endian_and_sane(self):
        lab = self.img.label
        self.assertEqual(lab["blkno"], 15)
        self.assertEqual(lab["secsize"], 1024)
        self.assertEqual(lab["front"], 160)
        self.assertEqual(lab["bootfile"], "mach_kernel")
        self.assertEqual(lab["rootpartition"], "a")

    def test_partition_a_offsets(self):
        lab = self.img.label
        self.assertEqual(lab["p_base"], 0)
        self.assertEqual(lab["p_size"], 8217087)

    def test_partition_start(self):
        self.assertEqual(self.img.part_start, 163840)


@unittest.skipUnless(os.path.exists(IMAGE), "golden.img not built yet")
class TestSuperblock(unittest.TestCase):
    def setUp(self):
        self.img = rhap_image.Image(IMAGE)

    def tearDown(self):
        self.img.close()

    def test_geometry(self):
        self.assertEqual(self.img.bsize, 8192)
        self.assertEqual(self.img.fsize, 1024)
        self.assertEqual(self.img.frag, 8)
        self.assertEqual(self.img.ipg, 3904)
        self.assertEqual(self.img.fpg, 16128)
        self.assertEqual(self.img.ncg, 510)
        self.assertEqual(self.img.inopb, 64)
        self.assertEqual(self.img.nindir, 2048)

    def test_label_and_superblock_agree(self):
        # p_size is in d_secsize units, fs_size in frags; both are 1024 bytes.
        self.assertEqual(self.img.fs_size, self.img.label["p_size"])

    def test_is_root_filesystem(self):
        self.assertEqual(self.img.fsmnt, "/")


@unittest.skipUnless(os.path.exists(IMAGE), "golden.img not built yet")
class TestInodes(unittest.TestCase):
    def setUp(self):
        self.img = rhap_image.Image(IMAGE)

    def tearDown(self):
        self.img.close()

    def test_root_inode(self):
        root = self.img.inode(2)
        self.assertEqual(root.mode & 0o170000, 0o040000)
        self.assertEqual(root.mode & 0o7777, 0o755)

    def test_root_listing_contains_expected_entries(self):
        names = [e[0] for e in self.img.listdir("/")]
        for expected in ("mach_kernel", "private", "usr", "System", "sbin"):
            self.assertIn(expected, names)

    def test_resolve_mach_kernel(self):
        self.assertEqual(self.img.resolve("/mach_kernel"), 1253202)

    def test_mach_kernel_metadata(self):
        ino = self.img.inode(self.img.resolve("/mach_kernel"))
        self.assertEqual(ino.size, 1459520)
        self.assertEqual(ino.blocks, 1440)

    def test_resolve_nested_driver_path(self):
        p = "/private/Drivers/i386/EIDE.config/Instance0.table"
        self.assertEqual(self.img.resolve(p), 827672)

    def test_missing_path_returns_none(self):
        self.assertIsNone(self.img.resolve("/no/such/file"))

    def test_read_instance_table(self):
        p = "/private/Drivers/i386/EIDE.config/Instance0.table"
        data = self.img.read_file(self.img.resolve(p))
        self.assertEqual(len(data), 890)
        self.assertIn(b'"Multiple Sectors" = "Yes";', data)

    def test_max_writable_is_frag_rounded_size(self):
        p = "/private/Drivers/i386/EIDE.config/Instance0.table"
        ino = self.img.resolve(p)
        # 890 bytes -> one 1024-byte fragment
        self.assertEqual(self.img.max_writable(ino), 1024)

    def test_max_writable_kernel_slack_is_small(self):
        ino = self.img.resolve("/mach_kernel")
        self.assertEqual(self.img.max_writable(ino), 1460224)
        self.assertEqual(self.img.max_writable(ino) - self.img.inode(ino).size, 704)

    def test_indirect_blocks_are_followed(self):
        # EIDE_reloc is 121056 bytes, past the 12 direct blocks (98304 bytes)
        p = "/private/Drivers/i386/EIDE.config/EIDE_reloc"
        data = self.img.read_file(self.img.resolve(p))
        self.assertEqual(len(data), 121056)
        self.assertEqual(data[:4], b"\xce\xfa\xed\xfe")  # Mach-O, little-endian
