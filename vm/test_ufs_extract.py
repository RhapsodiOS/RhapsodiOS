import os
import struct
import unittest

import rhap_image

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


if __name__ == "__main__":
    unittest.main()
