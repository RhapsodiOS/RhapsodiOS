import os
import unittest

import rcz
import rhap_image

HERE = os.path.dirname(os.path.abspath(__file__))
ISO = os.path.join(HERE, "install", "rhapsody_dr2_x86.iso")
FLOPPY = os.path.join(HERE, "install", "rhapsody_dr2_x86_InstallationFloppy.img")


def _media_present():
    return os.path.exists(ISO) and os.path.exists(FLOPPY)


class TestDecompress(unittest.TestCase):
    def test_rejects_short_stream(self):
        with self.assertRaises(rcz.RczError):
            rcz.decompress(b"\0\0\0")

    def test_rejects_wrong_method(self):
        with self.assertRaises(rcz.RczError):
            rcz.decompress(b"\0\0\0\1" + b"\0\0\0\0")

    def test_empty_payload(self):
        self.assertEqual(rcz.decompress(b"\0\0\x02\x9a" + b"\0\0\0\0"), b"")

    @unittest.skipUnless(_media_present(), "install media not present")
    def test_reproduces_shipped_kernel(self):
        with rhap_image.Image(FLOPPY) as f:
            stream = f.read_file(f.resolve("/mach_kernel.rcz"))
        with rhap_image.Image(ISO) as i:
            kernel = i.read_file(i.resolve("/mach_kernel"))
        self.assertEqual(rcz.decompress(stream), kernel)


if __name__ == "__main__":
    unittest.main()
