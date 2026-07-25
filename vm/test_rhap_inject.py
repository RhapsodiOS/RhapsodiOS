import hashlib
import os
import tempfile
import unittest

import rhap_image
import rhap_inject

HERE = os.path.dirname(__file__)
GOLDEN = os.path.join(HERE, "golden.img")
VMDK = os.path.join(HERE, "rhapsody.vmdk")
WORK = os.path.join(HERE, "work", "test.img")
TABLE = "/private/Drivers/i386/EIDE.config/Instance0.table"
MULTI_FRAG_FILE = "/private/Drivers/i386/EIDE.config/EIDE_reloc"


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

    def test_refuses_rhapsody_vmdk(self):
        with self.assertRaises(rhap_inject.SafetyError):
            rhap_inject.check_target(VMDK)

    def test_refuses_unrelated_directory_with_matching_suffix(self):
        # Same "work/test.img" tail, but rooted somewhere that isn't vm/.
        decoy = os.path.join(tempfile.gettempdir(), "rhap_inject_decoy", "work", "test.img")
        with self.assertRaises(rhap_inject.SafetyError):
            rhap_inject.check_target(decoy)

    def test_accepts_equivalent_differently_spelled_path(self):
        redundant = os.path.join(HERE, "work", "..", "work", ".", "test.img")
        rhap_inject.check_target(redundant)  # must not raise

        mixed_separators = HERE + "/work/test.img"
        rhap_inject.check_target(mixed_separators)  # must not raise

    def test_refused_write_leaves_image_unchanged(self):
        img = rhap_image.Image(WORK, writable=True)
        try:
            before = hashlib.sha256(img.read_file(img.resolve(TABLE))).digest()
            oversized = b"x" * (img.max_writable(img.resolve(TABLE)) + 1)
            with self.assertRaises(rhap_inject.SafetyError):
                rhap_inject.write_file(img, TABLE, oversized)
            after = hashlib.sha256(img.read_file(img.resolve(TABLE))).digest()
        finally:
            img.close()
        self.assertEqual(before, after)

    def test_max_writable_kernel_bound_is_conservative(self):
        img = rhap_image.Image(GOLDEN)
        try:
            limit = img.max_writable(img.resolve("/mach_kernel"))
            di_blocks = img.inode(img.resolve("/mach_kernel")).blocks
        finally:
            img.close()
        self.assertEqual(limit, 1460224)
        self.assertEqual(di_blocks * 1024, 1474560)
        self.assertLess(limit, di_blocks * 1024)

    def test_refuses_write_that_changes_fragment_count(self):
        img = rhap_image.Image(WORK, writable=True)
        try:
            inode = img.inode(img.resolve(MULTI_FRAG_FILE))
            current_frags = (inode.size + img.fsize - 1) // img.fsize
            self.assertGreater(current_frags, 1)  # meaningful only if multi-fragment

            shrunk = b"x" * ((current_frags - 1) * img.fsize)
            self.assertLessEqual(len(shrunk), img.max_writable(inode))  # old bound allows it
            with self.assertRaises(rhap_inject.SafetyError):
                rhap_inject.write_file(img, MULTI_FRAG_FILE, shrunk)
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
