import unittest

from instmedia import ufs_geometry as ug
from instmedia.space import NoSpace, Space

# 64 MB, 512-byte sectors: 9 groups, cssize one fragment, so group 0's data
# starts one fragment past a block boundary.
G = ug.geometry(fssize=131072, secsize=512, nsect=63, ntrak=16, rpm=3600)


class TestSpace(unittest.TestCase):
    def test_initial_free_regions_match_initcg(self):
        s = Space(G)
        first = G.csaddr + ug.howmany(G.cssize, G.fsize)
        self.assertEqual(s.free[first - 1], 0)
        self.assertEqual(s.free[first], 1)
        # Group 1: free before its superblock copy, used through dmin.
        self.assertEqual(s.free[ug.cgbase(G, 1)], 1)
        self.assertEqual(s.free[ug.cgsblock(G, 1) - 1], 1)
        self.assertEqual(s.free[ug.cgsblock(G, 1)], 0)
        self.assertEqual(s.free[ug.cgdmin(G, 1) - 1], 0)
        self.assertEqual(s.free[ug.cgdmin(G, 1)], 1)
        self.assertEqual(sum(s.free), G.dsize)

    def test_blocks_are_aligned_and_ascending(self):
        s = Space(G)
        a, b = s.block(), s.block()
        self.assertEqual(a % G.frag, 0)
        self.assertEqual(b, a + G.frag)
        self.assertEqual(a, ug.roundup(G.csaddr + 1, G.frag))

    def test_tails_pack_into_one_block(self):
        s = Space(G)
        t1 = s.frags(3)
        t2 = s.frags(5)
        self.assertEqual(t2, t1 + 3)
        t3 = s.frags(1)                     # block is full: a new one
        self.assertEqual(t3 % G.frag, 0)
        self.assertNotEqual(t3 // G.frag, t1 // G.frag)

    def test_blocks_skip_group_metadata(self):
        s = Space(G)
        got = [s.block() for _ in range(G.dsize // G.frag - 8)]
        for c in range(1, G.ncg):
            meta = range(ug.cgsblock(G, c), ug.cgdmin(G, c))
            self.assertFalse(any(b in meta for b in got))

    def test_full(self):
        s = Space(G)
        with self.assertRaises(NoSpace):
            for _ in range(G.dsize):
                s.block()

    def test_blksfree_bit_order(self):
        s = Space(G)
        bits = s.blksfree(1)
        self.assertEqual(bits[0] & 1, 1)                # cgbase(1) is free
        i = ug.cgsblock(G, 1) - ug.cgbase(G, 1)
        self.assertEqual((bits[i >> 3] >> (i & 7)) & 1, 0)


if __name__ == "__main__":
    unittest.main()
