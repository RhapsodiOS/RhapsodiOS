import os
import unittest

import rhap_image

IMAGE = os.path.join(os.path.dirname(__file__), "golden.img")


@unittest.skipUnless(os.path.exists(IMAGE), "golden.img not built yet")
class TestLabel(unittest.TestCase):
    def setUp(self):
        self.img = rhap_image.Image(IMAGE)

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
