import os
import struct
import unittest

import rhap_image
import ufs_build

HERE = os.path.dirname(os.path.abspath(__file__))
FLOPPY = os.path.join(HERE, "install", "rhapsody_dr2_x86_InstallationFloppy.img")
DRIVERS = os.path.join(HERE, "install", "rhapsody_dr2_x86_DriverDisk.img")


def _present(p):
    return os.path.exists(p)


def _read_cg(path):
    """Return (Geometry, cg block bytes, free-fragment bitmap) from a volume."""
    g = ufs_build.read_geometry(path)
    with rhap_image.Image(path) as img:
        cg = img.read_frag(g.cblkno, g.bsize)
    freeoff = struct.unpack_from("<i", cg, 96)[0]
    blksfree = cg[freeoff:freeoff + (g.fpg + 7) // 8]
    return g, cg, blksfree


class TestGeometry(unittest.TestCase):
    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_reads_known_floppy_geometry(self):
        g = ufs_build.read_geometry(FLOPPY)
        self.assertEqual(g.magic, 0x011954)
        self.assertEqual((g.ncg, g.bsize, g.fsize, g.frag), (1, 8192, 1024, 8))
        self.assertEqual((g.size, g.dsize, g.ipg, g.fpg), (1344, 1263, 384, 2304))
        self.assertEqual((g.nsect, g.spc, g.nrpos, g.cpg), (9, 18, 8, 128))


class TestCgTables(unittest.TestCase):
    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_reproduces_installation_floppy_tables(self):
        g, cg, blksfree = _read_cg(FLOPPY)
        t = ufs_build.recompute_cg_tables(g, blksfree)

        btotoff, boff = struct.unpack_from("<2i", cg, 84)
        stored_blktot = list(struct.unpack_from("<%di" % g.cpg, cg, btotoff))
        stored_blks = list(struct.unpack_from("<%dh" % (g.cpg * g.nrpos), cg, boff))
        stored_frsum = list(struct.unpack_from("<%di" % g.frag, cg, 52))
        _ndir, stored_nbfree, _nifree, stored_nffree = struct.unpack_from("<4i", cg, 24)

        self.assertEqual(t.blktot, stored_blktot)
        self.assertEqual(t.blks, stored_blks)
        self.assertEqual(t.frsum, stored_frsum)
        self.assertEqual(t.nbfree, stored_nbfree)
        self.assertEqual(t.nffree, stored_nffree)

    @unittest.skipUnless(_present(DRIVERS), "install media not present")
    def test_reproduces_driver_disk_tables(self):
        g, cg, blksfree = _read_cg(DRIVERS)
        t = ufs_build.recompute_cg_tables(g, blksfree)
        _ndir, stored_nbfree, _nifree, stored_nffree = struct.unpack_from("<4i", cg, 24)
        self.assertEqual((t.nbfree, t.nffree), (stored_nbfree, stored_nffree))


import tempfile

import ufs_extract


def _to_temp(image):
    fd, out = tempfile.mkstemp(suffix=".img")
    os.close(fd)
    with open(out, "wb") as f:
        f.write(image)
    return out


def _rebuild_to_temp(path):
    nodes = ufs_extract.extract(path)
    return _to_temp(ufs_build.build(path, nodes))


def _resize_to_temp(path, total_frags=2304, medium_sectors=2880):
    nodes = ufs_extract.extract(path)
    return _to_temp(ufs_build.build(path, nodes, total_frags=total_frags,
                                    medium_sectors=medium_sectors))


def _label_copies(path):
    """[(offset, p_size, stored checksum, recomputed checksum)] for the image.

    The recomputation is deliberately independent of ufs_build: checksum16
    (label_subr.c:71-86) over the first 560 bytes as big-endian u16s, with
    dl_label_blkno and the checksum field read as zero.
    """
    with open(path, "rb") as f:
        data = f.read()
    out = []
    for off in range(0, len(data) - 1023, 512):
        if data[off:off + 4] != b"dlV3":
            continue
        lab = bytearray(data[off:off + 560])
        struct.pack_into(">i", lab, 4, 0)
        struct.pack_into(">H", lab, 0x22e, 0)
        total = sum(struct.unpack_from(">H", lab, i * 2)[0] for i in range(280))
        total = ((total & 0xffff0000) >> 16) + (total & 0xffff)
        if total > 65535:
            total -= 65535
        out.append((off, struct.unpack_from(">i", data, off + 194)[0],
                    struct.unpack_from(">H", data, off + 0x22e)[0], total))
    return out


class TestIdentityRoundTrip(unittest.TestCase):
    def _assert_same_tree(self, original, rebuilt):
        a = ufs_extract.extract(original)
        b = ufs_extract.extract(rebuilt)
        self.assertEqual([n.path for n in a], [n.path for n in b])
        for x, y in zip(a, b):
            self.assertEqual((x.path, x.kind, x.mode, x.uid, x.gid),
                             (y.path, y.kind, y.mode, y.uid, y.gid))
            self.assertEqual(x.data, y.data, "contents differ for %s" % x.path)

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_installation_floppy_rebuilds_identically(self):
        out = _rebuild_to_temp(FLOPPY)
        try:
            self.assertEqual(os.path.getsize(out), os.path.getsize(FLOPPY))
            self._assert_same_tree(FLOPPY, out)
        finally:
            os.unlink(out)

    @unittest.skipUnless(_present(DRIVERS), "install media not present")
    def test_driver_disk_rebuilds_identically(self):
        out = _rebuild_to_temp(DRIVERS)
        try:
            self._assert_same_tree(DRIVERS, out)
        finally:
            os.unlink(out)

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_rebuilt_summaries_are_self_consistent(self):
        out = _rebuild_to_temp(FLOPPY)
        try:
            g, cg, blksfree = _read_cg(out)
            t = ufs_build.recompute_cg_tables(g, blksfree)
            _ndir, nbfree, _nifree, nffree = struct.unpack_from("<4i", cg, 24)
            self.assertEqual((t.nbfree, t.nffree), (nbfree, nffree))
        finally:
            os.unlink(out)


def _inode_meta(path):
    """{path: (di_size, di_nlink, di_blocks)} for every node in a volume."""
    out = {}
    with rhap_image.Image(path) as img:
        for node in ufs_extract.extract(path):
            n = img.inode(img.resolve(node.path))
            out[node.path] = (n.size, n.nlink, n.blocks)
    return out


def _inode_runs(img, inode):
    """Fragment runs an inode owns, as (start, nfrags, is_whole_block).

    Mirrors blksize (fs.h:498): every logical block is fs_frag fragments long
    except a short tail at a direct block.  The indirect block, when present,
    is a whole block too.
    """
    nblocks = (inode.size + img.bsize - 1) // img.bsize
    ptrs = list(inode.db)
    if nblocks > rhap_image.NDADDR:
        ind = img.read_frag(inode.ib[0], img.bsize)
        ptrs += list(struct.unpack_from("<%di" % img.nindir, ind, 0))
    runs = []
    for lbn in range(nblocks):
        remaining = inode.size - lbn * img.bsize
        if lbn == nblocks - 1 and lbn < rhap_image.NDADDR and remaining < img.bsize:
            nfrags = (remaining + img.fsize - 1) // img.fsize
            runs.append((ptrs[lbn], nfrags, False))
        else:
            runs.append((ptrs[lbn], img.frag, True))
    if nblocks > rhap_image.NDADDR:
        runs.append((inode.ib[0], img.frag, True))
    return runs


def _all_runs(path):
    """(Geometry, blksfree, {frag: path}, [(path, start, nfrags, whole)])."""
    g, _cg, blksfree = _read_cg(path)
    owner = {}
    runs = []
    with rhap_image.Image(path) as img:
        for node in ufs_extract.extract(path):
            n = img.inode(img.resolve(node.path))
            for start, nfrags, whole in _inode_runs(img, n):
                runs.append((node.path, start, nfrags, whole))
                for f in range(start, start + nfrags):
                    if f in owner:
                        raise AssertionError(
                            "fragment %d claimed by both %s and %s"
                            % (f, owner[f], node.path))
                    owner[f] = node.path
    return g, blksfree, owner, runs


class TestOnDiskInvariants(unittest.TestCase):
    def _assert_same_inode_meta(self, original, rebuilt):
        a = _inode_meta(original)
        b = _inode_meta(rebuilt)
        self.assertEqual(sorted(a), sorted(b))
        for p in a:
            self.assertEqual(a[p], b[p],
                             "di_size/di_nlink/di_blocks differ for %s" % p)

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_installation_floppy_inode_metadata_identical(self):
        out = _rebuild_to_temp(FLOPPY)
        try:
            self._assert_same_inode_meta(FLOPPY, out)
            meta = _inode_meta(out)
            self.assertEqual(meta["/usr/standalone/i386/sarld"][2], 160)
            self.assertEqual(meta["/mach_kernel.rcz"][2], 1040)
            self.assertEqual(meta["/"][0], ufs_build.DIRBLKSIZ)
        finally:
            os.unlink(out)

    @unittest.skipUnless(_present(DRIVERS), "install media not present")
    def test_driver_disk_inode_metadata_identical(self):
        out = _rebuild_to_temp(DRIVERS)
        try:
            self._assert_same_inode_meta(DRIVERS, out)
        finally:
            os.unlink(out)

    def _assert_allocation_audit(self, out):
        g, blksfree, owner, _runs = _all_runs(out)
        first_data = g.csaddr + -(-g.cssize // g.fsize)
        for f, path in owner.items():
            self.assertLess(f, g.size,
                            "%s claims fragment %d past fs_size" % (path, f))
            self.assertFalse(ufs_build.bit_is_set(blksfree, f),
                             "%s claims fragment %d but it is marked free"
                             % (path, f))
        for f in range(g.csaddr, g.size):
            if ufs_build.bit_is_set(blksfree, f):
                continue
            if f < first_data:
                continue  # the cylinder summary
            self.assertIn(f, owner,
                          "fragment %d is marked used but nothing owns it" % f)

    def _assert_alignment_invariants(self, out):
        g, _blksfree, _owner, runs = _all_runs(out)
        for path, start, nfrags, whole in runs:
            if whole:
                self.assertEqual(start % g.frag, 0,
                                 "%s: whole block at %d is not block-aligned"
                                 % (path, start))
            self.assertEqual(start // g.frag, (start + nfrags - 1) // g.frag,
                             "%s: run of %d at %d straddles a block boundary"
                             % (path, nfrags, start))

    def _assert_cluster_maps_match_blksfree(self, out):
        g, cg, blksfree = _read_cg(out)
        self.assertGreater(g.contigsumsize, 0)
        sumoff, clusteroff, nclusterblks = struct.unpack_from("<3i", cg, 104)
        # The map has to span the whole volume, not just the template's.
        self.assertEqual(nclusterblks, g.size // g.frag)
        free, summary = ufs_build.recompute_cluster_maps(
            g, blksfree, nclusterblks)

        stored_free = cg[clusteroff:clusteroff + len(free)]
        for b in range(nclusterblks):
            whole = all(ufs_build.bit_is_set(blksfree, b * g.frag + i)
                        for i in range(g.frag))
            self.assertEqual(bool(ufs_build.bit_is_set(stored_free, b)), whole,
                             "cluster bit %d disagrees with cg_blksfree" % b)
        self.assertEqual(stored_free, free)
        self.assertEqual(
            list(struct.unpack_from("<%di" % len(summary), cg, sumoff)),
            summary)

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_allocation_audit(self):
        out = _rebuild_to_temp(FLOPPY)
        try:
            self._assert_allocation_audit(out)
        finally:
            os.unlink(out)

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_alignment_invariants(self):
        out = _rebuild_to_temp(FLOPPY)
        try:
            self._assert_alignment_invariants(out)
        finally:
            os.unlink(out)

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_cluster_maps_match_blksfree(self):
        out = _rebuild_to_temp(FLOPPY)
        try:
            self._assert_cluster_maps_match_blksfree(out)
        finally:
            os.unlink(out)

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_resized_volume_holds_the_same_invariants(self):
        """The identity path alone let a stale cg_nclusterblks through."""
        out = _resize_to_temp(FLOPPY)
        try:
            self._assert_allocation_audit(out)
            self._assert_alignment_invariants(out)
            self._assert_cluster_maps_match_blksfree(out)
        finally:
            os.unlink(out)


class TestRefusals(unittest.TestCase):
    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_refuses_symlink(self):
        nodes = ufs_extract.extract(FLOPPY)
        nodes.append(ufs_extract.Node("/link", "lnk", 0o120755, 0, 0, 0, "target"))
        with self.assertRaises(ufs_build.BuildError):
            ufs_build.build(FLOPPY, nodes)

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_refuses_oversized_tree(self):
        nodes = ufs_extract.extract(FLOPPY)
        nodes = [n._replace(data=b"\0" * 900000) if n.path == "/mach_kernel.rcz" else n
                 for n in nodes]
        nodes.append(ufs_extract.Node("/big", "reg", 0o100644, 0, 0, 0, b"\0" * 900000))
        with self.assertRaises(ufs_build.BuildError):
            ufs_build.build(FLOPPY, nodes)


class TestResize(unittest.TestCase):
    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_builds_a_2880k_volume(self):
        nodes = ufs_extract.extract(FLOPPY)
        image = ufs_build.build(FLOPPY, nodes, total_frags=2304,
                                medium_sectors=2880)
        self.assertEqual(len(image), 2880 * 1024)
        fd, out = tempfile.mkstemp(suffix=".img")
        os.close(fd)
        try:
            with open(out, "wb") as f:
                f.write(image)
            self.assertEqual([n.path for n in ufs_extract.extract(out)],
                             [n.path for n in nodes])
            g = ufs_build.read_geometry(out)
            self.assertEqual((g.size, g.dsize, g.fpg, g.ncyl),
                             (2304, 2223, 2304, 128))
            with rhap_image.Image(out) as img:
                self.assertEqual(img.label["p_size"], 2304)
        finally:
            os.unlink(out)

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_every_label_copy_is_resized_and_checksummed(self):
        """-readLabel: takes the first copy that passes check_label, so a stale
        copy would clamp the volume straight back to 1344 sectors."""
        self.assertTrue(all(stored == computed
                            for _off, _p, stored, computed in _label_copies(FLOPPY)),
                        "the checksum recomputation does not match the masters")
        out = _resize_to_temp(FLOPPY)
        try:
            copies = _label_copies(out)
            self.assertGreater(len(copies), 1, "expected several label copies")
            for off, p_size, stored, computed in copies:
                self.assertEqual(p_size, 2304,
                                 "label copy at %d still says %d" % (off, p_size))
                self.assertEqual(stored, computed,
                                 "label copy at %d has a bad checksum" % off)
        finally:
            os.unlink(out)

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_cylinder_group_sizes_follow_the_new_fs_size(self):
        out = _resize_to_temp(FLOPPY)
        try:
            _g, cg, _blksfree = _read_cg(out)
            self.assertEqual(struct.unpack_from("<i", cg, 20)[0], 2304)   # cg_ndblk
            self.assertEqual(struct.unpack_from("<i", cg, 112)[0], 288)   # nclusterblks
            self.assertEqual(struct.unpack_from("<h", cg, 16)[0], 0)      # cg_ncyl
        finally:
            os.unlink(out)

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_refuses_a_medium_smaller_than_the_filesystem(self):
        nodes = ufs_extract.extract(FLOPPY)
        with self.assertRaises(ufs_build.BuildError):
            ufs_build.build(FLOPPY, nodes, total_frags=2304,
                            medium_sectors=2304)

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_refuses_to_outgrow_the_cylinder_group_bitmap(self):
        """fs_fpg is 2304 and the cg free bitmap is sized for exactly that many
        fragments; a larger filesystem would overrun it into the cluster maps."""
        nodes = ufs_extract.extract(FLOPPY)
        with self.assertRaises(ufs_build.BuildError):
            ufs_build.build(FLOPPY, nodes, total_frags=2784,
                            medium_sectors=2880)


class TestTailAllocation(unittest.TestCase):
    """di_blocks for every shape of the per-logical-block tail rule.

    Only a tail that is the last block, mapped by a direct pointer, and short
    of a whole block may be fragmented; everything else costs fs_frag.  The
    shipped trees exercise only two of these shapes, so build a synthetic one.
    """

    SIZES = {
        "/one_block": (8192, 8),             # exactly one block
        "/short": (1, 1),                    # smaller than one block
        "/ndaddr": (12 * 8192, 96),          # exactly NDADDR blocks, no indirect
        "/ndaddr_tail": (12 * 8192 + 100, 112),  # tail at lbn 12: a WHOLE block
        "/thirteen": (13 * 8192, 112),       # 13*8 + 8 for the indirect block
        "/fragroundup": (8191, 8),           # fragroundup(8191) == bsize
    }

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_di_blocks_for_every_tail_shape(self):
        nodes = [ufs_extract.Node("/", "dir", 0o040755, 0, 0, 0, None)]
        for path, (size, _blocks) in sorted(self.SIZES.items()):
            nodes.append(ufs_extract.Node(path, "reg", 0o100644, 0, 0, 0,
                                          b"\xa5" * size))

        image = ufs_build.build(FLOPPY, nodes)
        fd, out = tempfile.mkstemp(suffix=".img")
        os.close(fd)
        try:
            with open(out, "wb") as f:
                f.write(image)
            with rhap_image.Image(out) as img:
                for path, (size, blocks) in sorted(self.SIZES.items()):
                    n = img.inode(img.resolve(path))
                    self.assertEqual(n.size, size, "di_size wrong for %s" % path)
                    self.assertEqual(n.blocks, blocks,
                                     "di_blocks wrong for %s" % path)
                    self.assertEqual(bool(n.ib[0]), size > 12 * 8192,
                                     "indirect block presence wrong for %s" % path)
            for node in ufs_extract.extract(out)[1:]:
                self.assertEqual(node.data, b"\xa5" * self.SIZES[node.path][0],
                                 "contents differ for %s" % node.path)
        finally:
            os.unlink(out)


if __name__ == "__main__":
    unittest.main()
