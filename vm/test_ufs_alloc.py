"""Allocation must leave the filesystem consistent by fsck's definition.

The checks here are the cheap tier: they recompute invariants from the raw
bitmaps.  The acceptance gate is the guest's own /sbin/fsck (see the plan).
"""
import os
import shutil
import subprocess
import tempfile
import unittest

import ufs_alloc
import ufs_check

HERE = os.path.dirname(os.path.abspath(__file__))
GOLDEN = os.path.join(HERE, "golden.img")


def _present(*paths):
    return all(os.path.exists(p) for p in paths)


def clone(src, dst):
    """APFS clonefile: instant, near-zero space until written."""
    subprocess.check_call(["cp", "-c", src, dst])


class TestCylinderGroupAccess(unittest.TestCase):
    @unittest.skipUnless(_present(GOLDEN), "golden.img not present")
    def test_summed_group_summaries_equal_fs_cstotal(self):
        # This is the precondition the allocator refuses to write without.
        # If it fails, our model of the on-disk format is wrong.
        with ufs_alloc.Allocator(GOLDEN) as a:
            self.assertEqual(a.cg_count, 510)
            a.validate()

    @unittest.skipUnless(_present(GOLDEN), "golden.img not present")
    def test_untouched_image_is_reported_clean(self):
        self.assertEqual(ufs_check.check(GOLDEN), [])

    @unittest.skipUnless(_present(GOLDEN), "golden.img not present")
    def test_refuses_to_open_the_master_for_writing(self):
        with self.assertRaises(ufs_alloc.SafetyError):
            ufs_alloc.Allocator(GOLDEN, writable=True)


class TestFragmentAllocation(unittest.TestCase):
    def setUp(self):
        if not _present(GOLDEN):
            self.skipTest("golden.img not present")
        self.tmp = tempfile.mkdtemp(prefix="ufsalloc-", dir=os.path.join(HERE, "work"))
        self.addCleanup(shutil.rmtree, self.tmp)
        self.img = os.path.join(self.tmp, "test.img")
        clone(GOLDEN, self.img)

    def test_allocation_then_release_restores_every_count(self):
        before = None
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            a.validate()
            before = a.fs_cstotal()
            frags = a.alloc_frags(9)       # one whole block plus a tail
            self.assertEqual(len(frags), 9)
            self.assertEqual(len(set(frags)), 9)
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])

        with ufs_alloc.Allocator(self.img, writable=True) as a:
            after_alloc = a.fs_cstotal()
            self.assertNotEqual(after_alloc, before)
            a.free_frags(frags)
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])

        with ufs_alloc.Allocator(self.img) as a:
            self.assertEqual(a.fs_cstotal(), before)

    def test_allocated_fragments_are_marked_used(self):
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            frags = a.alloc_frags(8)
            for f in frags:
                self.assertFalse(a.frag_is_free(f),
                                 "fragment %d still marked free" % f)
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])


if __name__ == "__main__":
    unittest.main()
