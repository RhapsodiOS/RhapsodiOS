import os
import struct
import unittest
from unittest import mock

import rhap_image
import ufs_extract

HERE = os.path.dirname(os.path.abspath(__file__))
ISO = os.path.join(HERE, "install", "rhapsody_dr2_x86.iso")
FLOPPY = os.path.join(HERE, "install", "rhapsody_dr2_x86_InstallationFloppy.img")


def _present(*paths):
    return all(os.path.exists(p) for p in paths)


class TestInodeOwnership(unittest.TestCase):
    @unittest.skipUnless(_present(ISO), "install media not present")
    def test_di_spare_is_zero_across_the_tree(self):
        """Offsets 120..127 are di_spare[2]; if they are always zero, uid/gid
        are at 112/116 and not shifted by four."""
        with rhap_image.Image(ISO) as img:
            seen = 0
            stack = ["/"]
            while stack and seen < 400:
                path = stack.pop()
                for name, ino, dtype in img.listdir(path):
                    if name in (".", ".."):
                        continue
                    frag, entry = rhap_image._inode_location(img, ino)
                    blk = img.read_frag(frag, img.bsize)
                    raw = blk[entry:entry + rhap_image.DINODE_SIZE]
                    self.assertEqual(raw[120:128], b"\0" * 8,
                                     "di_spare nonzero for inode %d" % ino)
                    seen += 1
                    if dtype == 4 and len(stack) < 20:
                        stack.append(path.rstrip("/") + "/" + name)
            self.assertGreater(seen, 100)

    @unittest.skipUnless(_present(ISO), "install media not present")
    def test_root_is_owned_by_root(self):
        with rhap_image.Image(ISO) as img:
            root = img.inode(2)
            self.assertEqual((root.uid, root.gid), (0, 0))

    @unittest.skipUnless(_present(ISO), "install media not present")
    def test_readlink_returns_a_target(self):
        with rhap_image.Image(ISO) as img:
            self.assertTrue(img.readlink(img.resolve("/etc")).endswith("private/etc"))


class TestExtract(unittest.TestCase):
    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_installation_floppy_shape(self):
        nodes = ufs_extract.extract(FLOPPY)
        self.assertEqual(nodes[0].path, "/")
        self.assertEqual(nodes[0].kind, "dir")
        by_path = {n.path: n for n in nodes}
        self.assertEqual(len(nodes), 21)   # root plus the 20 objects
        self.assertEqual(by_path["/mach_kernel.rcz"].kind, "reg")
        self.assertEqual(len(by_path["/mach_kernel.rcz"].data), 1052315)
        self.assertEqual(by_path["/usr/standalone/i386/sarld"].kind, "reg")
        self.assertNotIn("lnk", {n.kind for n in nodes})

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_parents_precede_children(self):
        seen = set()
        for node in ufs_extract.extract(FLOPPY):
            if node.path != "/":
                parent = node.path.rsplit("/", 1)[0] or "/"
                self.assertIn(parent, seen, "%s came before %s" % (node.path, parent))
            seen.add(node.path)

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_driver_disk_has_no_links(self):
        disk = os.path.join(HERE, "install", "rhapsody_dr2_x86_DriverDisk.img")
        nodes = ufs_extract.extract(disk)
        self.assertEqual(len(nodes), 111)
        self.assertEqual({n.kind for n in nodes}, {"dir", "reg"})

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_installation_floppy_has_no_hard_links(self):
        nodes = ufs_extract.extract(FLOPPY)   # must not raise
        self.assertEqual(len(nodes), 21)

    def test_repeated_inode_raises_unsupported_node(self):
        """Two directory entries pointing at the same inode is a hard link;
        extract() must refuse rather than emit duplicated content."""

        class _FakeInode(object):
            mode = 0o644
            uid = 0
            gid = 0
            mtime = 0

        class _FakeImage(object):
            def __init__(self, path):
                pass

            def __enter__(self):
                return self

            def __exit__(self, *exc_info):
                return False

            def inode(self, ino):
                return _FakeInode()

            def read_file(self, inode):
                return b""

            def listdir(self, path):
                if path == "/":
                    return [("a", 5, 8), ("b", 6, 4)]
                if path.rstrip("/") == "/b":
                    return [("a", 5, 8)]   # same inode 5 as /a
                return []

        with mock.patch("rhap_image.Image", _FakeImage):
            with self.assertRaises(ufs_extract.UnsupportedNode) as ctx:
                ufs_extract.extract("fake-image")
        message = str(ctx.exception)
        self.assertIn("inode 5", message)
        self.assertIn("/a", message)
        self.assertIn("/b/a", message)


if __name__ == "__main__":
    unittest.main()
