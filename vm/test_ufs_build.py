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
