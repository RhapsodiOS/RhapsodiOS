"""The shared CG math must behave identically wherever it is imported from.

ufs_build and ufs_alloc both derive allocation summaries.  If they ever
disagreed the result would be an image that looks correct until fsck says
otherwise, so they share one implementation and this pins it.
"""
import os
import unittest

import rhap_image
import ufs_build
import ufs_cg

HERE = os.path.dirname(os.path.abspath(__file__))
GOLDEN = os.path.join(HERE, "golden.img")


def _present(*paths):
    return all(os.path.exists(p) for p in paths)


class TestSharedMath(unittest.TestCase):
    def test_ufs_build_reexports_the_shared_names(self):
        self.assertIs(ufs_build.recompute_cg_tables, ufs_cg.recompute_cg_tables)
        self.assertIs(ufs_build.bit_is_set, ufs_cg.bit_is_set)
        self.assertIs(ufs_build.CgTables, ufs_cg.CgTables)
        self.assertIs(ufs_build.BuildError, ufs_cg.UfsError)

    def test_bit_is_set_reads_little_endian_bit_order(self):
        # A set bit means the fragment is FREE.  Bit i lives in byte i//8 at
        # position i%8, which is the order the kernel's bitmaps use.
        self.assertEqual(ufs_cg.bit_is_set(bytearray(b"\x01"), 0), 1)
        self.assertEqual(ufs_cg.bit_is_set(bytearray(b"\x01"), 1), 0)
        self.assertEqual(ufs_cg.bit_is_set(bytearray(b"\x80"), 7), 1)

    @unittest.skipUnless(_present(GOLDEN), "golden.img not present")
    def test_reads_multi_group_geometry_that_ufs_build_refuses(self):
        # ufs_cg has no single-group restriction; ufs_build keeps one.
        g = ufs_cg.read_geometry(GOLDEN)
        self.assertEqual(g.ncg, 510)
        self.assertEqual(g.bsize, 8192)
        self.assertEqual(g.fsize, 1024)
        self.assertEqual(g.frag, 8)
        with self.assertRaises(ufs_build.BuildError):
            ufs_build.read_geometry(GOLDEN)


if __name__ == "__main__":
    unittest.main()
