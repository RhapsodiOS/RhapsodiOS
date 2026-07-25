import os
import shutil
import unittest

import rhap_image
import rhap_inject

HERE = os.path.dirname(__file__)
GOLDEN = os.path.join(HERE, "golden.img")
WORK = os.path.join(HERE, "work", "test.img")
TABLE = "/private/Drivers/i386/EIDE.config/Instance0.table"


@unittest.skipUnless(os.path.exists(WORK), "work/test.img not built yet")
class TestSafety(unittest.TestCase):
    def test_refuses_non_work_image(self):
        with self.assertRaises(rhap_inject.SafetyError):
            rhap_inject.check_target(GOLDEN)

    def test_accepts_work_image(self):
        rhap_inject.check_target(WORK)  # must not raise

    def test_refuses_oversized_payload(self):
        img = rhap_image.Image(WORK, writable=True)
        try:
            oversized = b"x" * (img.max_writable(img.resolve(TABLE)) + 1)
            with self.assertRaises(rhap_inject.SafetyError):
                rhap_inject.write_file(img, TABLE, oversized)
        finally:
            img.close()

    def test_refuses_missing_path(self):
        img = rhap_image.Image(WORK, writable=True)
        try:
            with self.assertRaises(rhap_inject.SafetyError):
                rhap_inject.write_file(img, "/no/such/file", b"hi")
        finally:
            img.close()


@unittest.skipUnless(os.path.exists(WORK), "work/test.img not built yet")
class TestRoundTrip(unittest.TestCase):
    def test_write_then_read_back(self):
        img = rhap_image.Image(WORK, writable=True)
        try:
            original = img.read_file(img.resolve(TABLE))
            modified = original.replace(
                b'"Multiple Sectors" = "Yes";', b'"Multiple Sectors" = "No";'
            )
            self.assertNotEqual(original, modified)
            rhap_inject.write_file(img, TABLE, modified)
        finally:
            img.close()

        img = rhap_image.Image(WORK)
        try:
            self.assertEqual(img.read_file(img.resolve(TABLE)), modified)
            self.assertEqual(img.inode(img.resolve(TABLE)).size, len(modified))
        finally:
            img.close()

        # restore
        img = rhap_image.Image(WORK, writable=True)
        try:
            rhap_inject.write_file(img, TABLE, original)
        finally:
            img.close()

    def test_shrinking_write_updates_size(self):
        img = rhap_image.Image(WORK, writable=True)
        try:
            original = img.read_file(img.resolve(TABLE))
            rhap_inject.write_file(img, TABLE, original[:100])
            self.assertEqual(img.inode(img.resolve(TABLE)).size, 100)
            rhap_inject.write_file(img, TABLE, original)
            self.assertEqual(img.inode(img.resolve(TABLE)).size, len(original))
        finally:
            img.close()
