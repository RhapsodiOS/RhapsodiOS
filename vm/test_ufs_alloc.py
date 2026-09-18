"""Allocation must leave the filesystem consistent by fsck's definition.

The checks here are the cheap tier: they recompute invariants from the raw
bitmaps.  The acceptance gate is the guest's own /sbin/fsck (see the plan).
"""
import os
import shutil
import subprocess
import tempfile
import unittest

import rhap_image
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


class TestInodeAllocation(unittest.TestCase):
    def setUp(self):
        if not _present(GOLDEN):
            self.skipTest("golden.img not present")
        self.tmp = tempfile.mkdtemp(prefix="ufsalloc-", dir=os.path.join(HERE, "work"))
        self.addCleanup(shutil.rmtree, self.tmp)
        self.img = os.path.join(self.tmp, "test.img")
        clone(GOLDEN, self.img)

    def test_inode_allocation_then_release_restores_counts(self):
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            before = a.fs_cstotal()
            ino = a.alloc_inode()
            self.assertGreater(ino, 2)
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])

        with ufs_alloc.Allocator(self.img, writable=True) as a:
            a.free_inode(ino)
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])
        with ufs_alloc.Allocator(self.img) as a:
            self.assertEqual(a.fs_cstotal(), before)

    def test_directory_inode_bumps_ndir(self):
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            ndir_before = a.fs_cstotal()[0]
            a.alloc_inode(is_dir=True)
            a.flush()
        with ufs_alloc.Allocator(self.img) as a:
            self.assertEqual(a.fs_cstotal()[0], ndir_before + 1)
        self.assertEqual(ufs_check.check(self.img), [])

    def test_write_inode_round_trips_and_sets_blocks(self):
        db = [0] * 12
        ib = [0, 0, 0]
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            ino = a.alloc_inode()
            a.write_inode(ino, mode=0o100644, size=1024, db=db, ib=ib,
                          nlink=1, mtime=1234567890)
            a.set_inode_blocks(ino, 2)
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])
        with rhap_image.Image(self.img) as img:
            n = img.inode(ino)
            self.assertEqual(n.mode, 0o100644)
            self.assertEqual(n.nlink, 1)
            self.assertEqual(n.size, 1024)
            self.assertEqual(n.mtime, 1234567890)
            self.assertEqual(n.db, db)
            self.assertEqual(n.ib, ib)
            self.assertEqual(n.blocks, 2)
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            a.free_inode(ino)
            a.flush()


class TestFileCreation(unittest.TestCase):
    def setUp(self):
        if not _present(GOLDEN):
            self.skipTest("golden.img not present")
        self.tmp = tempfile.mkdtemp(prefix="ufsalloc-", dir=os.path.join(HERE, "work"))
        self.addCleanup(shutil.rmtree, self.tmp)
        self.img = os.path.join(self.tmp, "test.img")
        clone(GOLDEN, self.img)

    def _roundtrip(self, payload):
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            ino = a.write_new_file(payload)
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])
        import rhap_image
        with rhap_image.Image(self.img) as img:
            self.assertEqual(img.read_file(ino), payload)

    def test_small_file_uses_direct_blocks(self):
        self._roundtrip(b"A" * 5000)

    def test_file_spanning_every_direct_block(self):
        self._roundtrip(bytes(range(256)) * 384)      # 96 KB exactly

    def test_file_needing_an_indirect_block(self):
        self._roundtrip(b"Z" * (200 * 1024))          # past 96 KB

    def test_large_file_spans_multiple_cylinder_groups(self):
        # fs_fpg is 16128 fragments = 15.8 MB per group, while
        # MAX_FILE_BYTES is ~16.09 MB -- a file this size cannot fit in a
        # single cylinder group even if that group were entirely empty, so
        # this exercises alloc_frags being called repeatedly across groups.
        block = os.urandom(65536)
        size = ufs_alloc.MAX_FILE_BYTES - 8192
        payload = (block * (size // len(block) + 1))[:size]
        self._roundtrip(payload)

    def test_growing_a_file_past_its_allocation(self):
        # The case rhap_inject refuses: /mach_kernel has 704 bytes of slack,
        # so growing it at all requires real allocation.
        import rhap_image
        big = b"G" * 300000
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            ino = a.write_new_file(b"small")
            a.flush()
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            a.grow_file(ino, big)
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])
        with rhap_image.Image(self.img) as img:
            self.assertEqual(img.read_file(ino), big)

    def test_shrinking_a_file_releases_its_surplus(self):
        import rhap_image
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            before = a.fs_cstotal()
            ino = a.write_new_file(b"B" * 200000)
            a.flush()
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            a.grow_file(ino, b"tiny")
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])
        with rhap_image.Image(self.img) as img:
            self.assertEqual(img.read_file(ino), b"tiny")

    def test_oversized_file_is_refused_before_writing(self):
        import hashlib
        digest = hashlib.sha256(open(self.img, "rb").read(1 << 20)).hexdigest()
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            with self.assertRaises(ufs_alloc.SafetyError) as cm:
                a.write_new_file(b"\0" * (ufs_alloc.MAX_FILE_BYTES + 1))
            self.assertIn("16", str(cm.exception))
        after = hashlib.sha256(open(self.img, "rb").read(1 << 20)).hexdigest()
        self.assertEqual(digest, after, "image was modified despite refusal")


if __name__ == "__main__":
    unittest.main()
