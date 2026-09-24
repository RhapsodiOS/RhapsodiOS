import io
import os
import struct
import unittest

import ufs_build
from instmedia import label, ufs_geometry

HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.environ.get("RHAPSODY_MEDIA_DIR", os.path.dirname(HERE))

GOLDEN = dict(
    secsize=1024, ntracks=16, nsectors=63, ncylinders=16383, rpm=3600,
    front=160, p_base=0, p_size=8217087, bsize=8192, fsize=1024, cpg=16,
    density=4096, minfree=10, name="Disk", d_name="Type 255-512",
    d_type="fixed_rw_ide", boot0=(32, 96), tag=0xac86a6f8)
FLOPPY = dict(
    secsize=1024, ntracks=2, nsectors=9, ncylinders=80, rpm=300,
    front=96, p_base=0, p_size=1344, bsize=8192, fsize=1024, cpg=32,
    density=2048, minfree=0, name="RhapsodyInstall",
    d_name="Floppy Drive-512", d_type="removable_rw_floppy",
    boot0=(32, -1), tag=0xf16809dc)
CD = dict(
    secsize=2048, ntracks=32, nsectors=64, ncylinders=1024, rpm=300,
    front=160, p_base=160, p_size=300000, bsize=8192, fsize=2048, cpg=16,
    density=4096, minfree=10, name="RhapsodyDR2", d_name="RhapsodyDR2",
    d_type="removable_rw_scsi", boot0=(32, 96), tag=0xe662b8f6)


def _reference(name, blk):
    path = os.path.join(MEDIA, name)
    if not os.path.exists(path):
        raise unittest.SkipTest("%s not present (set RHAPSODY_MEDIA_DIR)"
                                % path)
    with open(path, "rb") as f:
        f.seek(blk * 512)
        return f.read(label.LABEL_SIZE)


def _placed(lbl, blk):
    f = io.BytesIO()
    label.place(f, lbl, (blk,))
    return f.getvalue()[blk * 512:blk * 512 + label.LABEL_SIZE]


class TestAgainstDiskI(unittest.TestCase):
    """The encoder must reproduce labels disk -i wrote."""

    def test_golden(self):
        self.assertEqual(_placed(label.label(**GOLDEN), 15),
                         _reference("golden.img", 15))

    def test_install_floppy(self):
        self.assertEqual(
            _placed(label.label(**FLOPPY), 15),
            _reference(os.path.join(
                "install", "rhapsody_dr2_x86_InstallationFloppy.img"), 15))

    def test_dr2_cd_header_and_partition_a(self):
        # The CD's unused entries carry p_cpg 0 where disk -i writes -1, so
        # compare everything up to the end of partition a.
        ref = _reference(os.path.join("install", "rhapsody_dr2_x86.iso"), 0)
        self.assertEqual(_placed(label.label(**CD), 0)[:236], ref[:236])


class TestPlace(unittest.TestCase):
    def test_fdisk_copies_are_absolute_and_checksummed(self):
        lbl = label.label(**GOLDEN)
        f = io.BytesIO()
        label.place(f, lbl, label.DISK_COPIES, relsect=2048)
        raw = f.getvalue()
        for blk in label.DISK_COPIES:
            copy = raw[(2048 + blk) * 512:(2048 + blk) * 512 + 1024]
            self.assertEqual(copy[:4], b"dlV3")
            self.assertEqual(struct.unpack_from(">i", copy, 4)[0], 2048 + blk)
            self.assertEqual(
                struct.unpack_from(">H", copy, ufs_build.LABEL_CHECKSUM)[0],
                ufs_build.label_checksum(copy))

    def test_cd_copies_include_block_zero(self):
        f = io.BytesIO()
        label.place(f, label.label(**CD), label.CD_COPIES)
        raw = f.getvalue()
        self.assertEqual([struct.unpack_from(">i", raw, b * 512 + 4)[0]
                          for b in label.CD_COPIES], [0, 15, 30, 45])


class TestForFilesystem(unittest.TestCase):
    def test_fills_partition_a_from_the_geometry(self):
        g = ufs_geometry.geometry(fssize=8217087, secsize=1024, nsect=63,
                                  ntrak=16, rpm=3600)
        self.assertEqual(
            label.for_filesystem(g, front=160, p_base=0, ncylinders=16383,
                                 name="Disk", d_type="fixed_rw_ide"),
            label.label(**dict(GOLDEN, minfree=5, d_name="Disk",
                               boot0=(-1, -1), tag=0)))


class TestRefusals(unittest.TestCase):
    def test_name_too_long(self):
        with self.assertRaises(label.LabelError):
            label.label(**dict(GOLDEN, name="x" * 24))


if __name__ == "__main__":
    unittest.main()
