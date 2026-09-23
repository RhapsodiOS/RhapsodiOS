import contextlib
import hashlib
import io
import os
import subprocess
import tempfile
import unittest
import unittest.mock as mock

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


class TestPerSessionImageOverride(unittest.TestCase):
    def test_override_cannot_authorise_a_golden_img_elsewhere(self):
        # e.g. the main checkout's golden.img, seen from a git worktree
        with tempfile.TemporaryDirectory() as d:
            elsewhere = os.path.join(d, "golden.img")
            with mock.patch.dict(os.environ, {"RHAP_TEST_IMAGE": elsewhere}):
                with self.assertRaises(rhap_inject.SafetyError):
                    rhap_inject.check_target(elsewhere)

    def test_override_cannot_authorise_a_vmdk_elsewhere(self):
        with tempfile.TemporaryDirectory() as d:
            elsewhere = os.path.join(d, "rhapsody.vmdk")
            with mock.patch.dict(os.environ, {"RHAP_TEST_IMAGE": elsewhere}):
                with self.assertRaises(rhap_inject.SafetyError):
                    rhap_inject.check_target(elsewhere)

    def test_override_accepts_the_named_image(self):
        with tempfile.TemporaryDirectory() as d:
            alt = os.path.join(d, "ufs-backport.img")
            with mock.patch.dict(os.environ, {"RHAP_TEST_IMAGE": alt}):
                rhap_inject.check_target(alt)  # must not raise

    def test_override_still_accepts_the_default_target(self):
        with tempfile.TemporaryDirectory() as d:
            alt = os.path.join(d, "ufs-backport.img")
            with mock.patch.dict(os.environ, {"RHAP_TEST_IMAGE": alt}):
                rhap_inject.check_target(WORK)  # must not raise

    def test_override_cannot_authorise_golden(self):
        with mock.patch.dict(os.environ, {"RHAP_TEST_IMAGE": GOLDEN}):
            with self.assertRaises(rhap_inject.SafetyError):
                rhap_inject.check_target(GOLDEN)

    def test_override_cannot_authorise_the_vmdk(self):
        with mock.patch.dict(os.environ, {"RHAP_TEST_IMAGE": VMDK}):
            with self.assertRaises(rhap_inject.SafetyError):
                rhap_inject.check_target(VMDK)

    def test_unset_override_refuses_an_arbitrary_path(self):
        with tempfile.TemporaryDirectory() as d:
            alt = os.path.join(d, "ufs-backport.img")
            env = {k: v for k, v in os.environ.items() if k != "RHAP_TEST_IMAGE"}
            with mock.patch.dict(os.environ, env, clear=True):
                with self.assertRaises(rhap_inject.SafetyError):
                    rhap_inject.check_target(alt)


class TestReplaceTableKeyParsing(unittest.TestCase):
    """Exercises the pure parse/replace helper against in-memory byte
    strings, so the malformed-input cases don't need to touch any image."""

    def test_duplicated_key_refused(self):
        text = b'"Multiple Sectors" = "Yes";\n"Multiple Sectors" = "Yes";\n'
        with self.assertRaises(rhap_inject.SafetyError):
            rhap_inject._replace_table_key(text, "Multiple Sectors", "No")

    def test_escaped_quote_value_refused(self):
        text = b'"Debug" = "va\\"lue";\n'
        with self.assertRaises(rhap_inject.SafetyError):
            rhap_inject._replace_table_key(text, "Debug", "Yes")

    def test_missing_key_refused(self):
        text = b'"Other" = "Yes";\n'
        with self.assertRaises(rhap_inject.SafetyError):
            rhap_inject._replace_table_key(text, "Multiple Sectors", "No")

    def test_unterminated_entry_refused(self):
        text = b'"Multiple Sectors" = "Yes"\n'  # no trailing ; after the quote
        with self.assertRaises(rhap_inject.SafetyError):
            rhap_inject._replace_table_key(text, "Multiple Sectors", "No")

    def test_replacement_value_with_double_quote_refused(self):
        # Injecting a quote could terminate the entry early and open a new,
        # unrelated table key - e.g. smuggling in an extra entry.
        text = b'"Multiple Sectors" = "Yes";\n'
        with self.assertRaises(rhap_inject.SafetyError):
            rhap_inject._replace_table_key(
                text, "Multiple Sectors", 'No"; "Other" = "Pwned'
            )

    def test_replacement_value_with_semicolon_refused(self):
        text = b'"Multiple Sectors" = "Yes";\n'
        with self.assertRaises(rhap_inject.SafetyError):
            rhap_inject._replace_table_key(text, "Multiple Sectors", "No;Extra")

    def test_replacement_value_with_newline_refused(self):
        text = b'"Multiple Sectors" = "Yes";\n'
        with self.assertRaises(rhap_inject.SafetyError):
            rhap_inject._replace_table_key(text, "Multiple Sectors", "No\nExtra")

    def test_normal_key_rewritten_with_shorter_value(self):
        text = b'"Multiple Sectors" = "Yes";\n'
        old, updated = rhap_inject._replace_table_key(text, "Multiple Sectors", "No")
        self.assertEqual(old, "Yes")
        self.assertEqual(updated, b'"Multiple Sectors" = "No";\n')

    def test_normal_key_rewritten_with_longer_value(self):
        text = b'"Debug" = "No";\n'
        old, updated = rhap_inject._replace_table_key(text, "Debug", "AbsolutelyYes")
        self.assertEqual(old, "No")
        self.assertEqual(updated, b'"Debug" = "AbsolutelyYes";\n')


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


DONOR = ("/System/Documentation/Developer/YellowBox/TasksAndConcepts"
         "/PB/ProjectBuilder.pdf")
DONOR2 = "/private/Drivers/i386/EIDE.config/EIDE_reloc"

RESET_CMD = os.path.join(HERE, "reset-image.cmd")


def _reset_work_image():
    """Recreate work/test.img from golden.img via reset-image.cmd."""
    subprocess.run(["cmd.exe", "/c", RESET_CMD], check=True,
                    capture_output=True, text=True)


# NOTE: TestGraft mutates work/test.img (it grafts over /mach_kernel and
# other names). It sorts alphabetically ahead of the other test classes in
# this module, so it runs first and would otherwise leave the working image
# modified for the remainder of the run. setUpClass/tearDownClass reset the
# image via reset-image.cmd before and after this class runs; run
# reset-image.cmd manually if a test in this class is interrupted.
@unittest.skipUnless(os.path.exists(WORK), "work/test.img not built yet")
class TestGraft(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        _reset_work_image()

    @classmethod
    def tearDownClass(cls):
        _reset_work_image()

    def test_donor_is_large_and_hole_free(self):
        img = rhap_image.Image(WORK)
        try:
            ino = img.resolve(DONOR)
            self.assertIsNotNone(ino)
            n = img.inode(ino)
            self.assertGreater(img.max_writable(n), 8 * 1024 * 1024)
            self.assertTrue(all(f for f in img.frags(n)))
        finally:
            img.close()

    def test_graft_repoints_name_and_content(self):
        payload = b"GRAFTED" + b"\0" * (2 * 1024 * 1024 - 7)
        img = rhap_image.Image(WORK, writable=True)
        try:
            donor_ino = img.resolve(DONOR)
            rhap_inject.graft_file(img, "/mach_kernel", DONOR, payload)
        finally:
            img.close()

        img = rhap_image.Image(WORK)
        try:
            self.assertEqual(img.resolve("/mach_kernel"), donor_ino)
            got = img.read_file(img.resolve("/mach_kernel"))
            self.assertEqual(len(got), len(payload))
            self.assertEqual(got[:7], b"GRAFTED")
            self.assertGreaterEqual(img.inode(donor_ino).nlink, 2)
        finally:
            img.close()

    def test_graft_refuses_donor_too_small(self):
        img = rhap_image.Image(WORK, writable=True)
        try:
            with self.assertRaises(rhap_inject.SafetyError):
                rhap_inject.graft_file(
                    img, "/mach_kernel", TABLE, b"x" * 100000
                )
        finally:
            img.close()

    def test_graft_refuses_donor_not_regular_file(self):
        img = rhap_image.Image(WORK, writable=True)
        try:
            with self.assertRaises(rhap_inject.SafetyError):
                rhap_inject.graft_file(
                    img, "/mach_kernel",
                    "/private/Drivers/i386/EIDE.config", b"x" * 100
                )
        finally:
            img.close()

    def test_graft_refuses_donor_with_nlink_greater_than_one(self):
        # /mach_kernel itself has nlink 2 (/private/tftpboot/mach_kernel is a
        # second hard link to the same inode); it makes a convenient real
        # already-linked donor. Use it only as a donor here, never as target.
        img = rhap_image.Image(WORK, writable=True)
        try:
            donor_ino = img.resolve("/mach_kernel")
            self.assertEqual(img.inode(donor_ino).nlink, 2)
            with self.assertRaises(rhap_inject.SafetyError):
                rhap_inject.graft_file(img, TABLE, "/mach_kernel", b"x" * 100)
        finally:
            img.close()

    def test_graft_refuses_target_that_is_not_a_regular_file(self):
        # A mistyped target could repoint a directory's name at a regular
        # file's inode; the existing target inode must be a regular file.
        img = rhap_image.Image(WORK, writable=True)
        try:
            with self.assertRaises(rhap_inject.SafetyError):
                rhap_inject.graft_file(
                    img, "/private/Drivers/i386/EIDE.config", DONOR2, b"x" * 100
                )
        finally:
            img.close()

    def test_graft_shrunk_donor_refusal_message_is_honest(self):
        # After a first graft, the donor's addressable size drops to that
        # payload's size. A later, larger payload must be refused with a
        # message that names the current limit and points at the recovery
        # path, not one that reads as "donor too small" in general.
        # Reset first so this test does not depend on donor/nlink state left
        # by other TestGraft methods running earlier in alphabetical order.
        _reset_work_image()
        first = b"x" * 50000
        img = rhap_image.Image(WORK, writable=True)
        try:
            donor_ino = img.resolve(DONOR2)
            rhap_inject.graft_file(img, "/mach_kernel", DONOR2, first)
            limit = img.max_writable(img.inode(donor_ino))
        finally:
            img.close()

        img = rhap_image.Image(WORK, writable=True)
        try:
            with self.assertRaises(rhap_inject.SafetyError) as ctx:
                rhap_inject.graft_file(
                    img, "/mach_kernel", DONOR2, b"y" * (limit + 1)
                )
        finally:
            img.close()
        msg = str(ctx.exception)
        self.assertIn(str(limit), msg)
        self.assertIn("reset-image.cmd", msg)

    def test_graft_refuses_target_that_does_not_exist(self):
        img = rhap_image.Image(WORK, writable=True)
        try:
            with self.assertRaises(rhap_inject.SafetyError):
                rhap_inject.graft_file(
                    img, "/no_such_target_xyz", DONOR, b"x" * 100
                )
        finally:
            img.close()

    def test_graft_regrafts_same_target_idempotently(self):
        payload1 = b"FIRST" + b"\0" * (50000 - 5)
        payload2 = b"SECOND" + b"\1" * (50000 - 6)
        self.assertNotEqual(payload1, payload2)

        img = rhap_image.Image(WORK, writable=True)
        try:
            donor_ino = img.resolve(DONOR2)
            rhap_inject.graft_file(img, "/mach_kernel", DONOR2, payload1)
        finally:
            img.close()

        img = rhap_image.Image(WORK)
        try:
            self.assertEqual(img.resolve("/mach_kernel"), donor_ino)
            self.assertEqual(img.read_file(donor_ino), payload1)
            nlink_after_first = img.inode(donor_ino).nlink
        finally:
            img.close()

        img = rhap_image.Image(WORK, writable=True)
        try:
            rhap_inject.graft_file(img, "/mach_kernel", DONOR2, payload2)
        finally:
            img.close()

        img = rhap_image.Image(WORK)
        try:
            self.assertEqual(img.resolve("/mach_kernel"), donor_ino)
            self.assertEqual(img.read_file(donor_ino), payload2)
            self.assertEqual(img.inode(donor_ino).nlink, nlink_after_first)
        finally:
            img.close()


def _run_main(args):
    """Invoke rhap_inject.main() directly, capturing stdout/stderr text
    without spawning a subprocess."""
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        rc = rhap_inject.main(args)
    return rc, out.getvalue(), err.getvalue()


class TestMainCLI(unittest.TestCase):
    """Mirrors rhap_image.py's reader-CLI hardening: a refused image,
    missing arguments, and a nonexistent image must all return non-zero
    without raising, and the image must never be opened for write before
    check_target has approved it."""

    def test_missing_all_arguments_returns_nonzero_without_raising(self):
        rc, out, err = _run_main(["rhap_inject.py"])
        self.assertNotEqual(rc, 0)

    def test_missing_set_key_value_returns_nonzero_without_raising(self):
        rc, out, err = _run_main(
            ["rhap_inject.py", WORK, "set-key", TABLE, "Multiple Sectors"]
        )
        self.assertNotEqual(rc, 0)

    def test_missing_put_local_file_returns_nonzero_without_raising(self):
        rc, out, err = _run_main(["rhap_inject.py", WORK, "put", TABLE])
        self.assertNotEqual(rc, 0)

    def test_refused_image_returns_nonzero_without_raising(self):
        # GOLDEN is a real image but not vm/work/test.img, so check_target
        # must refuse it before rhap_image.Image() ever opens it for write.
        rc, out, err = _run_main(
            ["rhap_inject.py", GOLDEN, "set-key", TABLE, "Multiple Sectors", "No"]
        )
        self.assertNotEqual(rc, 0)

    def test_nonexistent_image_returns_nonzero_without_raising(self):
        # Bypass check_target (which validates the path, not existence) so
        # this exercises rhap_image.Image()'s FileNotFoundError being caught
        # instead of propagating as a raw traceback.
        with mock.patch.object(rhap_inject, "check_target", return_value=True):
            rc, out, err = _run_main(
                ["rhap_inject.py", "/no/such/image.img", "set-key", "/x", "k", "v"]
            )
        self.assertNotEqual(rc, 0)
