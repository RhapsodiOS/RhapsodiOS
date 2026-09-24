import os
import shutil
import tempfile
import unittest

import rhap_image
import ufs_check
from instmedia import readback, sample


class _RoundTrip(object):
    """Build one sample image and read it back every way we can."""

    build = None

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.path = os.path.join(cls.tmp, "sample.img")
        cls.g, cls.nodes = cls.build(cls.path)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def test_tree_reads_back(self):
        self.assertEqual(readback.diff(self.path, self.nodes), [])

    def test_allocation_accounting(self):
        self.assertEqual(ufs_check.check(self.path), [])

    def test_label_secsize(self):
        with rhap_image.Image(self.path) as img:
            self.assertEqual(img.label["secsize"], self.g.secsize)

    def test_covers_what_phase_3_requires(self):
        self.assertGreater(self.g.ncg, 1)
        with rhap_image.Image(self.path) as img:
            big = img.inode(img.resolve("/big"))
            self.assertNotEqual(big.ib[1], 0)       # double indirect
            groups = {f // self.g.fpg for f in img.frags(big)}
            self.assertGreater(len(groups), 1)
            last = img.resolve("/many/f%05d" % (self.g.ipg - 1))
            self.assertGreaterEqual(last // self.g.ipg, 1)

    def test_diff_notices_corruption(self):
        bad = os.path.join(self.tmp, "bad.img")
        shutil.copyfile(self.path, bad)
        with rhap_image.Image(bad) as img:
            frag = img.frags(img.inode(img.resolve("/etc/motd")))[0]
            where = img.frag_offset(frag)
        with open(bad, "r+b") as f:
            f.seek(where)
            f.write(b"w")
        self.assertEqual(readback.diff(bad, self.nodes),
                         ["/etc/motd: contents differ"])


class TestFdiskDisk512(_RoundTrip, unittest.TestCase):
    build = staticmethod(sample.fdisk_disk)


class TestCdVolume2048(_RoundTrip, unittest.TestCase):
    build = staticmethod(sample.cd_volume)


class TestMain(unittest.TestCase):
    def test_writes_both_images(self):
        tmp = tempfile.mkdtemp()
        try:
            self.assertEqual(sample.main(["sample", tmp]), 0)
            self.assertEqual(sorted(os.listdir(tmp)),
                             ["cd2048.img", "fdisk512.img"])
        finally:
            shutil.rmtree(tmp)


if __name__ == "__main__":
    unittest.main()
