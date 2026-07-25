import os
import struct
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


@unittest.skipUnless(os.path.exists(IMAGE), "golden.img not built yet")
class TestDoubleIndirectBlocks(unittest.TestCase):
    def setUp(self):
        self.img = rhap_image.Image(IMAGE)

    def tearDown(self):
        self.img.close()

    def test_pdf_double_indirect_frags_and_read_are_complete(self):
        # ProjectBuilder.pdf is 23,221,465 bytes, past the ~16.9 MB
        # single-indirect ceiling (12*frag + nindir*frag fragments), so
        # reading it exercises the double-indirect branch of _frags().  A
        # truncating walk would make len(frags) < need and read_file()
        # would come back short.
        p = "/System/Documentation/Developer/YellowBox/TasksAndConcepts/PB/ProjectBuilder.pdf"
        ino = self.img.resolve(p)
        self.assertIsNotNone(ino)
        inode = self.img.inode(ino)
        self.assertEqual(inode.size, 23221465)
        need = (inode.size + self.img.fsize - 1) // self.img.fsize
        frags = self.img.frags(inode)
        self.assertEqual(len(frags), need)
        data = self.img.read_file(ino)
        self.assertEqual(len(data), inode.size)


class TestFragsFirstLevelIndirectHole(unittest.TestCase):
    """A zero entry at the first double-indirect level is a hole spanning
    nindir blocks, not the end of the file.  No file in golden.img has this
    layout, so this stubs out Image.read_frag() to synthesize one.
    """

    FSIZE = 1024
    FRAG = 8
    NINDIR = 2048

    class FakeImage(object):
        """Duck-typed stand-in for Image: supplies just what _frags() reads."""

        def __init__(self, fsize, frag, nindir, blocks):
            self.fsize = fsize
            self.frag = frag
            self.nindir = nindir
            self.bsize = frag * fsize
            self._blocks = blocks  # {frag_no: raw indirect-table bytes}

        def read_frag(self, frag_no, nbytes):
            return self._blocks[frag_no]

    class FakeInode(object):
        def __init__(self, ino, size, db, ib):
            self.ino = ino
            self.size = size
            self.db = db
            self.ib = ib

    def test_hole_at_first_indirect_level_is_skipped_not_end_of_file(self):
        fsize, frag, nindir = self.FSIZE, self.FRAG, self.NINDIR

        # l1 (pointed to by ib[1]=500): entry 0 is a hole, entry 1 points at l2.
        l1 = struct.pack("<%di" % nindir, *([0, 600] + [0] * (nindir - 2)))
        # l2 (pointed to by l1[1]=600): two real blocks, 1000 and 2000.
        l2 = struct.pack("<%di" % nindir, *([1000, 2000] + [0] * (nindir - 2)))
        img = self.FakeImage(fsize, frag, nindir, {500: l1, 600: l2})

        direct_frags = rhap_image.NDADDR * frag
        # ib[0]=0: the whole single-indirect range (nindir blocks) is a hole too.
        single_indirect_hole_frags = nindir * frag
        double_indirect_hole_frags = nindir * frag
        extra_real_frags = 2 * frag  # two real blocks in l2
        need = (
            direct_frags
            + single_indirect_hole_frags
            + double_indirect_hole_frags
            + extra_real_frags
        )

        inode = self.FakeInode(
            ino=999, size=need * fsize, db=[0] * rhap_image.NDADDR, ib=[0, 500, 0]
        )

        frags = rhap_image.Image.frags(img, inode)

        self.assertEqual(len(frags), need)
        # Direct blocks, the absent single-indirect pointer, and the first l1
        # entry are all holes: none of them may truncate the walk.
        all_hole_frags = direct_frags + single_indirect_hole_frags + double_indirect_hole_frags
        self.assertEqual(frags[:all_hole_frags], [0] * all_hole_frags)
        # The second l1 entry points at real data past the hole.
        tail = frags[all_hole_frags:]
        self.assertTrue(all(tail))
        self.assertEqual(tail, list(range(1000, 1008)) + list(range(2000, 2008)))


class TestFragsFullySparseFile(unittest.TestCase):
    """A file whose size extends past the direct blocks but whose single-
    and double-indirect pointers are both zero is a legitimately sparse
    file: the kernel never allocated indirect blocks just to hold a table
    of zero pointers.  frags() must fill the whole range with holes rather
    than raising.
    """

    FSIZE = TestFragsFirstLevelIndirectHole.FSIZE
    FRAG = TestFragsFirstLevelIndirectHole.FRAG
    NINDIR = TestFragsFirstLevelIndirectHole.NINDIR

    def test_fully_sparse_file_returns_all_holes(self):
        fsize, frag, nindir = self.FSIZE, self.FRAG, self.NINDIR
        img = TestFragsFirstLevelIndirectHole.FakeImage(fsize, frag, nindir, {})

        # Past the 12 direct blocks and the whole single-indirect range, well
        # into the double-indirect range: several megabytes, fully sparse.
        direct_frags = rhap_image.NDADDR * frag
        single_indirect_frags = nindir * frag
        need = direct_frags + single_indirect_frags + 10 * frag

        inode = TestFragsFirstLevelIndirectHole.FakeInode(
            ino=998, size=need * fsize, db=[0] * rhap_image.NDADDR, ib=[0, 0, 0]
        )

        frags = rhap_image.Image.frags(img, inode)

        self.assertEqual(len(frags), need)
        self.assertEqual(frags, [0] * need)
