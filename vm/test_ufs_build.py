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


if __name__ == "__main__":
    unittest.main()
