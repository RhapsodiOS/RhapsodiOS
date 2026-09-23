"""The reused boot2 UFS reader must extract the same bytes as rhap_image.py.

This is the only test proving that ebiosread()/sys.c's reused UFS code reads
a real Rhapsody UFS payload correctly on this little-endian disk format. It must actually run in a fresh checkout and in CI, not just
report skips as green -- do not weaken _ready()/_require_image() to make
missing prerequisites look like success.
"""
import hashlib
import os
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(REPO, "vm"))

BINARY = os.path.join(HERE, "BUILD", "ufs_host_test")
_DEFAULT_IMAGE = os.path.join(REPO, "vm", "golden.img")
_EXPLICIT_IMAGE = os.environ.get("RHAPSODY_IMAGE")
IMAGE = _EXPLICIT_IMAGE if _EXPLICIT_IMAGE is not None else _DEFAULT_IMAGE


def _binary_ready():
    return os.path.exists(BINARY)


def _require_image():
    """An explicit RHAPSODY_IMAGE that doesn't exist is an error, not a skip:
    the caller asked for a specific image and it cannot be honoured."""
    if _EXPLICIT_IMAGE is not None and not os.path.exists(IMAGE):
        raise AssertionError(
            "RHAPSODY_IMAGE=%s does not exist" % IMAGE)


class TestHostUfsReader(unittest.TestCase):
    @unittest.skipUnless(_binary_ready(),
                         "build the binary first: "
                         "make -C src/bootefi-1/tests")
    def test_mach_kernel_matches_rhap_image(self):
        _require_image()
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

    @unittest.skipUnless(_binary_ready(),
                         "build the binary first: "
                         "make -C src/bootefi-1/tests")
    def test_missing_file_is_an_error(self):
        _require_image()
        proc = subprocess.run([BINARY, IMAGE, "hd(0,a)", "/no/such/file"],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertNotEqual(proc.returncode, 0)


if __name__ == "__main__":
    unittest.main()
