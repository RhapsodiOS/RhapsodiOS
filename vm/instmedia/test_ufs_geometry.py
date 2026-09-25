import os
import struct
import unittest

import rhap_image
from instmedia import ufs_geometry

HERE = os.path.dirname(os.path.abspath(__file__))
VM = os.path.dirname(HERE)
MEDIA = os.environ.get("RHAPSODY_MEDIA_DIR", VM)

REFERENCES = [
    ("golden.img",
     dict(fssize=8217087, secsize=1024, nsect=63, ntrak=16, rpm=3600)),
    (os.path.join("install", "rhapsody_dr2_x86_InstallationFloppy.img"),
     dict(fssize=1344, secsize=1024, nsect=9, ntrak=2, rpm=300, cpg=128)),
    (os.path.join("install", "rhapsody_dr2_x86.iso"),
     dict(fssize=300000, secsize=2048, nsect=64, ntrak=32, rpm=300,
          fsize=2048)),
]


def _superblock(path):
    with rhap_image.Image(path) as img:
        return img._read_at(img.part_start + rhap_image.SBOFF,
                            rhap_image.SBOFF)


class TestAgainstAppleNewfs(unittest.TestCase):
    """Every geometry field must equal what Apple's newfs wrote."""

    def _check(self, name, params):
        path = os.path.join(MEDIA, name)
        if not os.path.exists(path):
            self.skipTest("%s not present (set RHAPSODY_MEDIA_DIR)" % path)
        sb = _superblock(path)
        g = ufs_geometry.geometry(**params)
        for field, off in ufs_geometry.SB_OFFSETS.items():
            self.assertEqual(getattr(g, field),
                             struct.unpack_from("<i", sb, off)[0], field)
        for field, off in ufs_geometry.SB_QUAD_OFFSETS.items():
            self.assertEqual(getattr(g, field),
                             struct.unpack_from("<q", sb, off)[0], field)
        if g.cpc:
            n = g.cpc * g.nrpos
            self.assertEqual(
                g.postbl, struct.unpack_from("<%dh" % n, sb, g.postbloff))
            self.assertEqual(
                bytes(v & 0xff for v in g.rotbl),
                sb[g.rotbloff:g.rotbloff + len(g.rotbl)])

    def test_golden(self):
        self._check(*REFERENCES[0])

    def test_install_floppy(self):
        self._check(*REFERENCES[1])

    def test_dr2_cd(self):
        self._check(*REFERENCES[2])


class TestProjectGeometries(unittest.TestCase):
    """Pinned results for the two shapes this project writes."""

    def test_fdisk_disk_512(self):
        # 64 MB partition, QEMU IDE geometry, 512-byte label sectors.
        g = ufs_geometry.geometry(fssize=131072, secsize=512, nsect=63,
                                  ntrak=16, rpm=3600)
        self.assertEqual((g.nspf, g.fsbtodb, g.sblkno, g.cblkno, g.iblkno),
                         (2, 1, 16, 24, 32))
        self.assertEqual((g.cpg, g.fpg, g.ipg, g.ncg, g.size, g.dblkno),
                         EXPECTED_512)

    def test_cd_2048(self):
        # 256 MB volume, the DR2 CD's geometry.
        g = ufs_geometry.geometry(fssize=131072, secsize=2048, nsect=64,
                                  ntrak=32, rpm=300, fsize=2048)
        self.assertEqual((g.nspf, g.fsbtodb, g.sblkno, g.cblkno, g.iblkno),
                         (1, 0, 8, 12, 16))
        self.assertEqual((g.cpg, g.fpg, g.ipg, g.ncg, g.size, g.dblkno),
                         EXPECTED_2048)

    def test_cg_helpers(self):
        g = ufs_geometry.geometry(fssize=131072, secsize=512, nsect=63,
                                  ntrak=16, rpm=3600)
        self.assertEqual(ufs_geometry.cgstart(g, 0), 0)
        self.assertEqual(ufs_geometry.cgsblock(g, 0), g.sblkno)
        self.assertEqual(ufs_geometry.cgdmin(g, 1),
                         g.fpg + g.cgoffset * (1 & ~g.cgmask) + g.dblkno)
        self.assertEqual(ufs_geometry.cg_data_end(g, g.ncg - 1), g.size)


class TestRefusals(unittest.TestCase):
    def test_fragment_smaller_than_sector(self):
        with self.assertRaises(ufs_geometry.GeometryError):
            ufs_geometry.geometry(fssize=131072, secsize=2048, nsect=64,
                                  ntrak=32, rpm=300, fsize=1024)

    def test_block_larger_than_maxbsize(self):
        with self.assertRaises(ufs_geometry.GeometryError):
            ufs_geometry.geometry(fssize=131072, secsize=512, nsect=63,
                                  ntrak=16, rpm=3600, bsize=16384,
                                  fsize=2048)

    def test_too_small(self):
        with self.assertRaises(ufs_geometry.GeometryError):
            ufs_geometry.geometry(fssize=64, secsize=512, nsect=63,
                                  ntrak=16, rpm=3600)


# (cpg, fpg, ipg, ncg, size, dblkno), from this port once it matched all
# three reference media.
EXPECTED_512 = (16, 8064, 1792, 9, 65536, 256)
EXPECTED_2048 = (16, 32768, 8064, 4, 131072, 520)

if __name__ == "__main__":
    unittest.main()
