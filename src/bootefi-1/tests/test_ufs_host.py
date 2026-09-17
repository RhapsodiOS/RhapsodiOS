"""The reused boot2 UFS reader must extract the same bytes as rhap_image.py."""
import hashlib
import os
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(REPO, "vm"))

BINARY = os.path.join(HERE, "BUILD", "ufs_host_test")
IMAGE = os.environ.get("RHAPSODY_IMAGE",
                       os.path.join(REPO, "vm", "work", "rhapsody.img"))


def _ready():
    return os.path.exists(BINARY) and os.path.exists(IMAGE)


class TestHostUfsReader(unittest.TestCase):
    @unittest.skipUnless(_ready(), "build the binary and supply RHAPSODY_IMAGE")
    def test_mach_kernel_matches_rhap_image(self):
        import rhap_image

        with rhap_image.Image(IMAGE) as img:
            ino = img.resolve("/mach_kernel")
            self.assertIsNotNone(ino, "/mach_kernel missing from the image")
            expected = img.read_file(ino)

        got = subprocess.check_output(
            [BINARY, IMAGE, "hd(0,a)", "/mach_kernel"])

        self.assertEqual(hashlib.sha256(got).hexdigest(),
                         hashlib.sha256(expected).hexdigest())
        self.assertEqual(len(got), len(expected))

    @unittest.skipUnless(_ready(), "build the binary and supply RHAPSODY_IMAGE")
    def test_missing_file_is_an_error(self):
        proc = subprocess.run([BINARY, IMAGE, "hd(0,a)", "/no/such/file"],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertNotEqual(proc.returncode, 0)


if __name__ == "__main__":
    unittest.main()
