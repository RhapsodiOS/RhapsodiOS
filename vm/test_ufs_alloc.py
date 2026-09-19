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
            limit = a.max_file_bytes()
            with self.assertRaises(ufs_alloc.SafetyError) as cm:
                a.write_new_file(b"\0" * (limit + 1))
            self.assertIn("16", str(cm.exception))
        after = hashlib.sha256(open(self.img, "rb").read(1 << 20)).hexdigest()
        self.assertEqual(digest, after, "image was modified despite refusal")

    def test_growing_a_file_with_a_hole_does_not_free_fragment_zero(self):
        # Simulate a pre-existing sparse file: create a 3-block file, then
        # release the middle block and poke a 0 (a hole) into its db entry,
        # the way a file NOT laid out by this module's own convention could
        # look.  grow_file must not mistake that hole for a real block
        # starting at fragment 0 -- the boot block / superblock area.
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            bsize = a.g.bsize
            frag = a.g.frag
            ino = a.write_new_file(b"X" * (3 * bsize))
            a.flush()

        with ufs_alloc.Allocator(self.img, writable=True) as a:
            mode, nlink, size, db, ib = a._read_dinode(ino)
            hole_start = db[1]
            self.assertNotEqual(hole_start, 0)
            a.free_frags([hole_start + k for k in range(frag)])
            db[1] = 0
            a.write_inode(ino, mode=mode, size=size, db=db, ib=ib,
                          nlink=nlink, mtime=1234567890)
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])

        with ufs_alloc.Allocator(self.img, writable=True) as a:
            grown = b"Y" * (5 * a.g.bsize)
            a.grow_file(ino, grown)
            a.flush()

        with ufs_alloc.Allocator(self.img) as a:
            self.assertFalse(
                a.frag_is_free(0),
                "grow_file freed fragment 0 while reconstructing a sparse "
                "file's old fragments")
        self.assertEqual(ufs_check.check(self.img), [])
        with rhap_image.Image(self.img) as img:
            self.assertEqual(img.read_file(ino), grown)

    def test_growing_an_indirect_file_twice_without_flushing(self):
        # Two grow_file calls in one session, with no flush() between them,
        # must not have the second one read a stale/garbage indirect block
        # straight off disk while the first call's indirect block still
        # only exists in the pending data cache.
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            ino = a.write_new_file(b"S" * 1000)
            a.flush()

        first = b"F" * (150 * 1024)    # over 96 KB: needs an indirect block
        second = b"G" * (250 * 1024)   # also needs one, and is bigger
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            a.grow_file(ino, first)
            # first's indirect block only exists in _data_cache right now
            # (nothing has been flushed).  The second grow_file must see
            # those pending pointers, not whatever stale bytes are still on
            # disk at that fragment -- which, read raw, decode as a run of
            # zero/garbage pointers and cause old blocks (including
            # fragment 0) to be freed by mistake.
            a.grow_file(ino, second)
            a.flush()

        with ufs_alloc.Allocator(self.img) as a:
            self.assertFalse(
                a.frag_is_free(0),
                "grow_file freed fragment 0 after reading a stale "
                "indirect block straight off disk")
        self.assertEqual(ufs_check.check(self.img), [])
        with rhap_image.Image(self.img) as img:
            self.assertEqual(img.read_file(ino), second)


class TestDirectoryOperations(unittest.TestCase):
    def setUp(self):
        if not _present(GOLDEN):
            self.skipTest("golden.img not present")
        self.tmp = tempfile.mkdtemp(prefix="ufsalloc-", dir=os.path.join(HERE, "work"))
        self.addCleanup(shutil.rmtree, self.tmp)
        self.img = os.path.join(self.tmp, "test.img")
        clone(GOLDEN, self.img)

    def test_created_directory_and_file_are_visible_to_the_reader(self):
        import rhap_image
        payload = b"hello rhapsody" * 100
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            a.mkdir("/private/Drivers/i386/TEST.config")
            a.create_file("/private/Drivers/i386/TEST.config/TEST_reloc", payload)
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])
        with rhap_image.Image(self.img) as img:
            ino = img.resolve("/private/Drivers/i386/TEST.config/TEST_reloc")
            self.assertIsNotNone(ino)
            self.assertEqual(img.read_file(ino), payload)
            names = [e[0] for e in img.listdir("/private/Drivers/i386/TEST.config")]
            self.assertIn(".", names)
            self.assertIn("..", names)

    def test_create_then_remove_restores_the_free_counts(self):
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            before = a.fs_cstotal()
            a.flush()
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            a.mkdir("/private/Drivers/i386/TEST.config")
            a.create_file("/private/Drivers/i386/TEST.config/TEST_reloc", b"x" * 9000)
            a.flush()
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            a.unlink("/private/Drivers/i386/TEST.config/TEST_reloc")
            a.rmdir("/private/Drivers/i386/TEST.config")
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])
        with ufs_alloc.Allocator(self.img) as a:
            self.assertEqual(a.fs_cstotal(), before)

    def test_rmdir_refuses_a_non_empty_directory(self):
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            a.mkdir("/private/Drivers/i386/TEST.config")
            a.create_file("/private/Drivers/i386/TEST.config/f", b"x")
            a.flush()
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            with self.assertRaises(ufs_alloc.SafetyError):
                a.rmdir("/private/Drivers/i386/TEST.config")

    def test_di_nlink_follows_all_four_rules(self):
        # di_nlink isn't checked by ufs_check at all, so this is the only
        # thing that would ever catch a regression here.  Read every value
        # back through the independent reader (rhap_image), not the
        # allocator's own accessors.
        parent = "/private/Drivers/i386"
        with rhap_image.Image(self.img) as img:
            parent_nlink_before = img.inode(img.resolve(parent)).nlink

        with ufs_alloc.Allocator(self.img, writable=True) as a:
            dir_ino = a.mkdir(parent + "/TEST.config")
            file_ino = a.create_file(parent + "/TEST.config/f", b"x")
            nested_ino = a.mkdir(parent + "/TEST.config/NESTED.config")
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])

        with rhap_image.Image(self.img) as img:
            # A newly created regular file: nlink == 1.
            self.assertEqual(img.inode(file_ino).nlink, 1)
            # A newly created directory: nlink == 2 (its name in the
            # parent, plus its own ".").
            self.assertEqual(img.inode(nested_ino).nlink, 2)
            # Nesting: TEST.config started at 2, then gained a child
            # directory (NESTED.config), whose ".." is a second link back
            # to it -- so TEST.config must now read 3, not 2 (no
            # double-counting) and not 4 (not missed).
            self.assertEqual(img.inode(dir_ino).nlink, 3)
            # mkdir increments the parent's nlink by exactly 1.
            self.assertEqual(img.inode(img.resolve(parent)).nlink,
                              parent_nlink_before + 1)

        with ufs_alloc.Allocator(self.img, writable=True) as a:
            a.rmdir(parent + "/TEST.config/NESTED.config")
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])
        with rhap_image.Image(self.img) as img:
            # Removing the nested directory must bring TEST.config back to
            # 2, on the nose.
            self.assertEqual(img.inode(dir_ino).nlink, 2)

        with ufs_alloc.Allocator(self.img, writable=True) as a:
            a.unlink(parent + "/TEST.config/f")
            a.rmdir(parent + "/TEST.config")
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])
        with rhap_image.Image(self.img) as img:
            # rmdir decrements the parent's nlink back to its original
            # value.
            self.assertEqual(img.inode(img.resolve(parent)).nlink,
                              parent_nlink_before)

    def test_add_dirent_growth_path_extends_the_tail_in_place(self):
        # /private/Drivers/i386 is a long-established, foreign (not
        # allocated by this module) directory with many entries -- the
        # scenario the next task exercises for real.  add_dirent's growth
        # path (nothing fits in any existing record's slack) must extend
        # or append only the one block that's actually growing; it must
        # never relocate a block the directory already had.
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            a.mkdir("/private/Drivers/i386/TEST.config")
            dir_ino = a._resolve("/private/Drivers/i386/TEST.config")
            _, _, size_before, db_before, _ = a._read_dinode(dir_ino)
            tail_block_before = db_before[0]

            created = []
            i = 0
            while True:
                name = "f%d" % i
                payload = ("payload-%d" % i).encode("ascii")
                a.create_file(
                    "/private/Drivers/i386/TEST.config/%s" % name, payload)
                created.append((name, payload))
                i += 1
                size_now = a._read_dinode(dir_ino)[2]
                if size_now > size_before:
                    break
                self.assertLess(
                    i, 300, "growth path never triggered "
                    "(directory slack never got exhausted)")

            _, _, _, db_after, _ = a._read_dinode(dir_ino)
            self.assertEqual(
                db_after[0], tail_block_before,
                "add_dirent's growth path relocated the directory's "
                "existing (pre-growth) block instead of extending or "
                "appending in place")
            a.flush()

        self.assertEqual(ufs_check.check(self.img), [])
        with rhap_image.Image(self.img) as img:
            names = [e[0] for e in
                     img.listdir("/private/Drivers/i386/TEST.config")]
            self.assertIn(".", names)
            self.assertIn("..", names)
            # Every entry added before (and at) the growth is still
            # intact, with its own data unharmed.
            for name, payload in created:
                ino = img.resolve(
                    "/private/Drivers/i386/TEST.config/%s" % name)
                self.assertIsNotNone(ino, "%s went missing" % name)
                self.assertEqual(img.read_file(ino), payload)


if __name__ == "__main__":
    unittest.main()
