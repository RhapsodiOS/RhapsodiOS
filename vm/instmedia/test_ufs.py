import os
import struct
import unittest

import rhap_image
from ufs_extract import Node
from instmedia import ufs, ufs_geometry as ug
from instmedia.test_ufs_geometry import MEDIA, REFERENCES

# The superblock fields the kernel rewrites at mount time -- fs_fsmnt,
# fs_cgrotor, fs_csp and fs_maxcluster -- which fsck's alternate-superblock
# check also skips.
MOUNT_FIELDS = slice(212, 856)
G512 = ug.geometry(fssize=131072, secsize=512, nsect=63, ntrak=16, rpm=3600)


def _open(name):
    path = os.path.join(MEDIA, name)
    if not os.path.exists(path):
        raise unittest.SkipTest("%s not present (set RHAPSODY_MEDIA_DIR)"
                                % path)
    return rhap_image.Image(path)


class TestLayoutAgainstNewfs(unittest.TestCase):
    """The metadata newfs wrote, reproduced from the geometry alone."""

    def _superblock(self, name, params):
        g = ug.geometry(**params)
        with _open(name) as img:
            ref = bytearray(img._read_at(img.part_start + ufs.SBOFF,
                                         g.sbsize))
        mine = bytearray(ufs.superblock(
            g, struct.unpack_from("<i", ref, 32)[0],
            struct.unpack_from("<4i", ref, 192)))
        self.assertEqual(bytes(mine[MOUNT_FIELDS]), bytes(856 - 212))
        ref[MOUNT_FIELDS] = bytes(856 - 212)
        self.assertEqual(mine, ref)

    def _cg_headers(self, name, params):
        g = ug.geometry(**params)
        with _open(name) as img:
            for c in (0, g.ncg - 1):
                ref = img._read_at(
                    img.part_start + ug.cgtod(g, c) * g.fsize, g.bsize)
                ndblk = ug.cg_data_end(g, c) - ug.cgbase(g, c)
                ncyl = g.ncyl % g.cpg if c == g.ncg - 1 else g.cpg
                self.assertEqual(struct.unpack_from("<iihhi", ref, 4)[0],
                                 ufs.CG_MAGIC)
                self.assertEqual(struct.unpack_from("<ihhi", ref, 12),
                                 (c, ncyl, g.ipg, ndblk))
                self.assertEqual(struct.unpack_from("<7i", ref, 84),
                                 ufs.cg_offsets(g))
                self.assertEqual(struct.unpack_from("<i", ref, 112)[0],
                                 ndblk // g.frag)

    def test_golden(self):
        self._superblock(*REFERENCES[0])
        self._cg_headers(*REFERENCES[0])

    def test_install_floppy(self):
        self._superblock(*REFERENCES[1])
        self._cg_headers(*REFERENCES[1])

    def test_dr2_cd(self):
        self._superblock(*REFERENCES[2])
        self._cg_headers(*REFERENCES[2])


def _n(path, kind, data=None):
    return Node(path, kind, 0o755, 0, 0, 0, data)


class TestTreeChecks(unittest.TestCase):
    def _refuse(self, nodes):
        with self.assertRaises(ufs.TreeError):
            ufs._index(G512, nodes)

    def test_root_first(self):
        self._refuse([_n("/etc", "dir"), _n("/", "dir")])

    def test_duplicate(self):
        self._refuse([_n("/", "dir"), _n("/a", "reg", b""),
                      _n("/a", "reg", b"")])

    def test_orphan(self):
        self._refuse([_n("/", "dir"), _n("/no/such", "reg", b"")])

    def test_parent_is_a_file(self):
        self._refuse([_n("/", "dir"), _n("/a", "reg", b""),
                      _n("/a/b", "reg", b"")])

    def test_hard_link_to_directory(self):
        self._refuse([_n("/", "dir"), _n("/d", "dir"),
                      _n("/l", "hlink", "/d")])

    def test_unnormalised_path(self):
        self._refuse([_n("/", "dir"), _n("/a/", "dir")])

    def test_too_many_inodes(self):
        self._refuse([_n("/", "dir")]
                     + [_n("/f%d" % i, "reg", b"")
                        for i in range(G512.ncg * G512.ipg)])

    def test_link_counts(self):
        ino_of, _, _, nlink = ufs._index(G512, [
            _n("/", "dir"), _n("/d", "dir"), _n("/d/e", "dir"),
            _n("/f", "reg", b""), _n("/g", "hlink", "/f")])
        self.assertEqual(nlink[ino_of["/"]], 3)
        self.assertEqual(nlink[ino_of["/d"]], 3)
        self.assertEqual(nlink[ino_of["/d/e"]], 2)
        self.assertEqual(nlink[ino_of["/f"]], 2)
        self.assertEqual(ino_of["/g"], ino_of["/f"])


class TestDirData(unittest.TestCase):
    def test_entries_never_cross_a_chunk(self):
        entries = [(3 + i, b"name-%03d" % i, 8) for i in range(100)]
        data = ufs._dir_data(entries)
        self.assertEqual(len(data) % ufs.DIRBLKSIZ, 0)
        seen = []
        for chunk in range(0, len(data), ufs.DIRBLKSIZ):
            p = chunk
            while p < chunk + ufs.DIRBLKSIZ:
                ino, reclen, dtype, namlen = struct.unpack_from(
                    "<IHBB", data, p)
                self.assertEqual(reclen % 4, 0)
                seen.append(data[p + 8:p + 8 + namlen])
                p += reclen
            self.assertEqual(p, chunk + ufs.DIRBLKSIZ)
        self.assertEqual(seen, [name for _, name, _ in entries])


if __name__ == "__main__":
    unittest.main()
