import contextlib
import hashlib
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import refresh  # noqa: E402

OPENSSL = shutil.which("openssl")
UPSTREAM = "https://example.test/cacert.pem"

HEADER = (
    "##\n"
    "## Bundle of CA Root Certificates\n"
    "##\n"
    "## Certificate data from Mozilla as of: Tue Sep  9 03:12:06 2025 GMT\n"
    "##\n"
    "## test fixture\n"
    "##\n"
    "\n\n"
)


def make_cert(cn, workdir):
    """Return a self-signed PEM certificate whose subject is /CN=<cn>."""
    key = os.path.join(workdir, "k.pem")
    out = os.path.join(workdir, "c.pem")
    subprocess.run(
        [OPENSSL, "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1",
         "-nodes", "-keyout", key, "-out", out, "-subj", "/CN=" + cn, "-days", "3650"],
        check=True, capture_output=True)
    with open(out, encoding="ascii") as f:
        return f.read().strip()


def bundle_text(entries):
    """A curl-style bundle from [(label, pem)]."""
    blocks = ["%s\n%s\n%s" % (label, "=" * len(label), pem) for label, pem in entries]
    return HEADER + "\n\n".join(blocks) + "\n"


class RefreshTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not OPENSSL:
            raise RuntimeError("openssl is not on PATH; the tests need it to mint certificates")
        cls.tmp = tempfile.mkdtemp()
        cls.a = make_cert("Test Root A", cls.tmp)
        cls.b = make_cert("Test Root B", cls.tmp)
        cls.b2 = make_cert("Test Root B", cls.tmp)  # same subject as b, different key
        cls.c = make_cert("Test Root C", cls.tmp)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def setUp(self):
        self.out = Path(tempfile.mkdtemp())
        (self.out / "certs").mkdir()
        (self.out / "certs" / "keep.pem").write_text("old\n")
        (self.out / "SOURCE").write_text("old source\n")

    def tearDown(self):
        shutil.rmtree(self.out, ignore_errors=True)

    def run_refresh(self, text, **kw):
        return refresh.refresh(text.encode("utf-8"), self.out, OPENSSL, UPSTREAM, **kw)

    def assert_untouched(self):
        self.assertEqual(sorted(p.name for p in (self.out / "certs").iterdir()), ["keep.pem"])
        self.assertEqual((self.out / "SOURCE").read_text(), "old source\n")

    # --- small pieces -------------------------------------------------

    def test_pem_name_keeps_hyphens_and_transliterates(self):
        self.assertEqual(refresh.pem_name("GlobalSign Root CA - R3"), "GlobalSign_Root_CA_-_R3.pem")
        self.assertEqual(refresh.pem_name("T\u00e9st R\u00f6ot C"), "Test_Root_C.pem")

    def test_pem_name_rejects_a_label_with_nothing_usable(self):
        with self.assertRaises(refresh.RefreshError):
            refresh.pem_name("\u5b89\u5168")

    def test_mozilla_date(self):
        self.assertEqual(refresh.mozilla_date(HEADER), "20250909")
        line = "## Certificate data from Mozilla as of: Wed Dec 31 23:59:59 2025 GMT\n"
        self.assertEqual(refresh.mozilla_date(line), "20251231")

    def test_mozilla_date_missing(self):
        with self.assertRaisesRegex(refresh.RefreshError, "as of"):
            refresh.mozilla_date("## no date here\n")

    # --- the happy path -----------------------------------------------

    def test_writes_one_pem_per_ca(self):
        pkgver, count = self.run_refresh(
            bundle_text([("Test Root A", self.a), ("T\u00e9st R\u00f6ot C", self.c)]))
        self.assertEqual((pkgver, count), ("20250909", 2))
        self.assertEqual(sorted(p.name for p in (self.out / "certs").iterdir()),
                         ["Test_Root_A.pem", "Test_Root_C.pem"])
        raw = (self.out / "certs" / "Test_Root_A.pem").read_bytes()
        self.assertNotIn(b"\r", raw)
        self.assertTrue(raw.startswith(b"Test Root A\n===========\n-----BEGIN CERTIFICATE-----\n"))
        self.assertTrue(raw.endswith(b"-----END CERTIFICATE-----\n"))
        keeps_label = (self.out / "certs" / "Test_Root_C.pem").read_text(encoding="utf-8")
        self.assertTrue(keeps_label.startswith("T\u00e9st R\u00f6ot C\n"))

    def test_crlf_input_is_normalised(self):
        text = bundle_text([("Test Root A", self.a)]).replace("\n", "\r\n")
        self.assertEqual(self.run_refresh(text), ("20250909", 1))
        self.assertNotIn(b"\r", (self.out / "certs" / "Test_Root_A.pem").read_bytes())
        self.assertNotIn(b"\r", (self.out / "SOURCE").read_bytes())

    def test_source_records_provenance(self):
        text = bundle_text([("Test Root A", self.a), ("Test Root C", self.c)])
        self.run_refresh(text)
        source = (self.out / "SOURCE").read_text(encoding="utf-8")
        self.assertRegex(source, r"(?m)^Upstream: +" + re.escape(UPSTREAM) + "$")
        self.assertRegex(source, r"(?m)^pkgver: +20250909$")
        self.assertRegex(source, r"(?m)^Certificates: +2$")
        self.assertRegex(source, r"(?m)^SHA-256: +" + hashlib.sha256(text.encode()).hexdigest() + "$")
        self.assertIn("Mozilla Public License, v. 2.0", source)
        self.assertIn("## test fixture", source)

    def test_matching_sha256_is_accepted(self):
        text = bundle_text([("Test Root A", self.a)])
        self.run_refresh(text, expected_sha256=hashlib.sha256(text.encode()).hexdigest().upper())

    # --- failures leave the tree alone --------------------------------

    def test_sha256_mismatch(self):
        with self.assertRaisesRegex(refresh.RefreshError, "SHA-256"):
            self.run_refresh(bundle_text([("Test Root A", self.a)]), expected_sha256="0" * 64)
        self.assert_untouched()

    def test_duplicate_subject(self):
        text = bundle_text([("Test Root B", self.b), ("Test Root B old", self.b2)])
        with self.assertRaisesRegex(refresh.RefreshError, "same subject"):
            self.run_refresh(text)
        self.assert_untouched()

    def test_names_equal_ignoring_case(self):
        text = bundle_text([("Test Root A", self.a), ("TEST ROOT A", self.c)])
        with self.assertRaisesRegex(refresh.RefreshError, "file name"):
            self.run_refresh(text)
        self.assert_untouched()

    def test_corrupt_pem(self):
        first_line = self.a.splitlines()[1]
        bad = self.a.replace(first_line[:8], "AAAAAAAA", 1)
        with self.assertRaisesRegex(refresh.RefreshError, "openssl x509 rejected"):
            self.run_refresh(bundle_text([("Test Root A", bad)]))
        self.assert_untouched()

    def test_unlabelled_certificate(self):
        text = bundle_text([("Test Root A", self.a)]) + "\n\n" + self.c + "\n"
        with self.assertRaisesRegex(refresh.RefreshError, "label"):
            self.run_refresh(text)
        self.assert_untouched()

    def test_missing_date_line(self):
        text = bundle_text([("Test Root A", self.a)]).replace("as of:", "on:")
        with self.assertRaisesRegex(refresh.RefreshError, "as of"):
            self.run_refresh(text)
        self.assert_untouched()

    # --- command line -------------------------------------------------

    def test_main_prints_the_pkgver(self):
        path = self.out / "in.pem"
        path.write_bytes(bundle_text([("Test Root A", self.a)]).encode("utf-8"))
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = refresh.main(["--file", str(path), "--out", str(self.out), "--openssl", OPENSSL])
        self.assertEqual(rc, 0)
        self.assertIn("pkgver = 20250909", buf.getvalue())
        self.assertTrue((self.out / "certs" / "Test_Root_A.pem").exists())

    def test_main_failure_returns_1(self):
        path = self.out / "in.pem"
        path.write_bytes(bundle_text([("Test Root A", self.a)]).encode("utf-8"))
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            rc = refresh.main(["--file", str(path), "--sha256", "0" * 64,
                               "--out", str(self.out), "--openssl", OPENSSL])
        self.assertEqual(rc, 1)
        self.assertIn("SHA-256", err.getvalue())
        self.assert_untouched()


if __name__ == "__main__":
    unittest.main()
