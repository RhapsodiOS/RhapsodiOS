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


def _rebuild_to_temp(path):
    nodes = ufs_extract.extract(path)
    image = ufs_build.build(path, nodes)
    fd, out = tempfile.mkstemp(suffix=".img")
    os.close(fd)
    with open(out, "wb") as f:
        f.write(image)
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

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_allocation_audit(self):
        out = _rebuild_to_temp(FLOPPY)
        try:
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
        finally:
            os.unlink(out)

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_alignment_invariants(self):
        out = _rebuild_to_temp(FLOPPY)
        try:
            g, _blksfree, _owner, runs = _all_runs(out)
            for path, start, nfrags, whole in runs:
                if whole:
                    self.assertEqual(start % g.frag, 0,
                                     "%s: whole block at %d is not block-aligned"
                                     % (path, start))
                self.assertEqual(start // g.frag, (start + nfrags - 1) // g.frag,
                                 "%s: run of %d at %d straddles a block boundary"
                                 % (path, nfrags, start))
        finally:
            os.unlink(out)

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_cluster_maps_match_blksfree(self):
        out = _rebuild_to_temp(FLOPPY)
        try:
            g, cg, blksfree = _read_cg(out)
            self.assertGreater(g.contigsumsize, 0)
            sumoff, clusteroff, nclusterblks = struct.unpack_from("<3i", cg, 104)
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


if __name__ == "__main__":
    unittest.main()
