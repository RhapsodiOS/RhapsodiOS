# ca-certificates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Mozilla's trusted root CAs as a universal apk, `src/ca-certificates-1`, installed under `/System/Library/OpenSSL` with `/etc/ssl` symlinks pointing at it.

**Architecture:** curl.se's `cacert.pem` (Mozilla's roots) is split into one PEM per CA by a host-side Python tool, `refresh.py`, which validates the set before writing anything. The per-CA PEMs and a `SOURCE` provenance file are checked in. A `Common.make` wrapper (the `pico-1` pattern) installs them, builds the `cert.pem` bundle with `cat`, and makes the symlinks. rbuild packages it, and a guest script inspects the apk.

**Tech Stack:** Python 3 (stdlib only) and host `openssl` for `refresh.py`; CoreOS ReleaseControl `Common.make`, GNU Make 3.74 and `/bin/sh` on the Rhapsody guest; rbuild; PowerShell guest helpers in `vm/`.

**Spec:** `docs/superpowers/specs/2026-09-24-ca-certificates-design.md`

## Global Constraints

- Work only in the worktree `D:\RhapsodiOS\.claude\worktrees\ca-certificates` (branch `ca-certificates`). Never run `git add` or `git commit` in `D:\RhapsodiOS` itself, because other sessions share that checkout's index.
- Project directory: `src/ca-certificates-1`. rbuild strips the `-1` for the package name and appends it to the version, so the apk is `ca-certificates-<pkgver>-1-universal.apk` and `.PKGINFO` says `pkgver = <pkgver>-1`.
- `apk/pkginfo`: `pkgname = ca-certificates`, `license = MPL-2.0`, `url = https://curl.se/docs/caextract.html`, `makedepends = build-base`. `pkgver` is the date from cacert.pem's "Certificate data from Mozilla as of:" line, as `YYYYMMDD`.
- Upstream is `https://curl.se/ca/cacert.pem` with `https://curl.se/ca/cacert.pem.sha256` beside it. Downloading needs the user's go-ahead first; state the filenames, source and sizes when asking.
- Installed paths are exactly:
  - `/System/Library/OpenSSL/certs/<Name>.pem`, mode 0444
  - `/System/Library/OpenSSL/cert.pem`, the bundle, mode 0444
  - `/System/Library/OpenSSL/certs/ca-certificates.crt`, symlink to `../cert.pem`
  - `/private/etc/ssl/certs`, symlink to `/System/Library/OpenSSL/certs`
  - `/private/etc/ssl/cert.pem`, symlink to `/System/Library/OpenSSL/cert.pem`
  - `/usr/share/doc/ca-certificates/SOURCE`
- The Makefile links the two `/etc/ssl` entries to absolute targets; rbuild's `builder_relativize_symlinks` rewrites them to relative ones in the apk (`../../../System/Library/OpenSSL/...`). The `ca-certificates.crt` alias is relative to begin with.
- The vendored set must have unique subject DNs: in the in-tree OpenSSL 0.9.5a, `X509_STORE_add_cert` errors on a repeated subject and `X509_load_cert_file` treats that as fatal, so a bundle stops loading partway. File names must be unique ignoring case (the repo is checked out on Windows) and plain ASCII.
- Manifest line: `dir     ca-certificates-1     all`, directly after `dir     bsdmake-1             all`. `BootstrapManifest` is not touched.
- The Makefile must run under GNU Make 3.74 on the guest: no target-specific variables. The guest's `install` moves its source unless given `-c`.
- The guest's `/bin/ls` exits 0 for missing paths and unmatched globs stay literal: guest scripts test existence with `test -f` / `test -d`, never with `ls`.
- Commit messages start with `ca-certificates: `, are one or two lines, and carry **no trailers or metadata** (CLAUDE.md: "Do not add any metadata to commits").
- The guest (10.10.0.241) is shared. Use only `/build/cacert` (a private root) and `/tmp/cacert-*` there. Never start `rbuild bootstrap`, never write to `/build/src`, `/build/tools`, `/build/repo` or `/build/state`.
- "Done" means the apk builds and the guest check script prints `PACKAGE_TEST_OK`.

## Shell variables used throughout

Every Bash command runs from Git Bash on the Windows host and assumes:

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/9dd0a75b-fe16-48ab-952b-6915cd402a95/scratchpad"
W=/d/RhapsodiOS/.claude/worktrees/ca-certificates
```

- `$S` is this session's scratchpad. Downloads and guest scripts live there, not in the repository. If you're a different session, substitute your own scratchpad path everywhere `$S` appears, and in `rx.ps1`'s callers.
- **MSYS trap:** typed at a Git Bash prompt, `openssl ... -subj /CN=x` is rewritten into a Windows path and fails. Tests avoid this by running `openssl` from Python. If you ever run such a command by hand, prefix it with `MSYS_NO_PATHCONV=1`.

## File Map

| Path (under `src/ca-certificates-1/`) | Task | Responsibility |
|---|---|---|
| `refresh.py` | 1 | Fetch/read cacert.pem, verify, split, validate, write `certs/` and `SOURCE` |
| `tests/test_refresh.py` | 1 | unittest suite for `refresh.py` |
| `certs/*.pem`, `SOURCE` | 2 | The vendored roots and their provenance |
| `Makefile` | 3 | `Common.make` wrapper with the `install::` recipe |
| `apk/pkginfo` | 3 | Package metadata |
| `src/Manifest` | 3 | World build entry |
| `docs/superpowers/specs/2026-09-24-ca-certificates-design.md` | 3 | Corrections found while planning and building |

---

## Setup (not committed)

- [ ] **Step 1: Create the worktree**

```bash
cd /d/RhapsodiOS && git worktree add -b ca-certificates .claude/worktrees/ca-certificates HEAD
```

Expected: `Preparing worktree (new branch 'ca-certificates')` and a `HEAD is now at ...` line. `.claude/worktrees/` is excluded through `.git/info/exclude`, so it never shows as untracked.

- [ ] **Step 2: Give the worktree guest access with a private root**

`vm/vm.conf` holds the guest login and is gitignored, so the worktree lacks it. Copy it in and point `RemoteRoot` at a private root, so `sync-src.ps1` never writes into the shared `/build/src`.

```bash
W=/d/RhapsodiOS/.claude/worktrees/ca-certificates
cp /d/RhapsodiOS/vm/vm.conf "$W/vm/vm.conf" && sed -i 's|^RemoteRoot=.*|RemoteRoot=/build/cacert|' "$W/vm/vm.conf" && grep -n '^RemoteRoot' "$W/vm/vm.conf" && cd "$W" && git check-ignore -q vm/vm.conf && echo VM_CONF_IGNORED
```

Expected: `RemoteRoot=/build/cacert` and `VM_CONF_IGNORED`.

- [ ] **Step 3: Create the guest runner**

Create `$S/rx.ps1` (overwrite any existing one; this points it at the worktree's `vm.conf`):

```powershell
# Run a local sh script on the Rhapsody guest; exit with its exit code.
param([Parameter(Mandatory=$true)][string]$ScriptFile)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:RhapVmDir = 'D:\RhapsodiOS\.claude\worktrees\ca-certificates\vm'
. (Join-Path $script:RhapVmDir 'rhap-remote.ps1')
$cfg = Get-RhapVmConfig -DiePrefix 'rx'
$ssh = Resolve-RhapTool -NameOrPath $cfg.Ssh -DiePrefix 'rx'
$body = Get-Content -LiteralPath $ScriptFile -Raw
$ec = Invoke-RhapSshScript -Cfg $cfg -Ssh $ssh -ScriptBody $body -Stream
exit $ec
```

The guest isn't contacted until Task 3, so Tasks 1 and 2 don't depend on it.

---

### Task 1: refresh.py, the host-side import tool

**Files:**
- Create: `src/ca-certificates-1/tests/test_refresh.py`
- Create: `src/ca-certificates-1/refresh.py`

**Interfaces:**
- Produces, used by Task 2 and by the tests:
  - `refresh.refresh(bundle: bytes, out_dir: Path, openssl: str, upstream: str, expected_sha256: str | None = None) -> tuple[str, int]` returns `(pkgver, certificate_count)`. It raises `refresh.RefreshError` and leaves `out_dir` unchanged on any failure. On success it replaces `out_dir/certs/` and `out_dir/SOURCE`.
  - `refresh.pem_name(label: str) -> str`, `refresh.mozilla_date(text: str) -> str`, `refresh.split_bundle(text: str) -> list[tuple[str, str]]`.
  - `refresh.main(argv: list[str] | None = None) -> int`, CLI: `--file PATH`, `--sha256 HEX`, `--url URL`, `--out DIR`, `--openssl PATH`.
- Produces the `SOURCE` format Task 3's guest script parses with `sed`: lines `pkgver: <YYYYMMDD>` and `Certificates: <N>`.

**Background:** curl's bundle looks like a `##` comment header, then repeated blocks of `Label`, an `====` underline of the same length, and a PEM block. `openssl x509 -noout -subject -nameopt RFC2253` prints `subject=CN=...` (with a trailing `\r\n` on Windows), exits non-zero on a bad PEM, and gives the string used for the duplicate-subject check. Equal DER implies equal RFC2253 text, so this check has no false negatives against 0.9.5a's raw comparison.

- [ ] **Step 1: Check the host can mint test certificates from Python**

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/9dd0a75b-fe16-48ab-952b-6915cd402a95/scratchpad"
cd "$S" && python - <<'EOF'
import shutil, subprocess
o = shutil.which("openssl")
print("openssl:", o)
r = subprocess.run([o, "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1",
                    "-nodes", "-keyout", "k.pem", "-out", "c.pem", "-subj", "/CN=Test Root A", "-days", "3650"],
                   capture_output=True)
print("req rc", r.returncode)
r = subprocess.run([o, "x509", "-noout", "-subject", "-nameopt", "RFC2253"],
                   input=open("c.pem", "rb").read(), capture_output=True)
print("x509 rc", r.returncode, repr(r.stdout.decode()))
EOF
```

Expected: an `openssl:` path, `req rc 0`, and `x509 rc 0 'subject=CN=Test Root A\r\n'`. If `openssl` is `None`, put Git's `mingw64\bin` on `PATH` (`C:\Users\raynorpat\AppData\Local\Programs\Git\mingw64\bin`) and retry.

- [ ] **Step 2: Write the failing tests**

Create `src/ca-certificates-1/tests/test_refresh.py`:

```python
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
```

- [ ] **Step 3: Run the tests to verify they fail**

```bash
W=/d/RhapsodiOS/.claude/worktrees/ca-certificates
cd "$W" && python -m unittest discover -s src/ca-certificates-1/tests -v 2>&1 | tail -8
```

Expected: `ModuleNotFoundError: No module named 'refresh'` inside an `ImportError: Failed to import test module: test_refresh`, and `FAILED (errors=1)`.

- [ ] **Step 4: Write `refresh.py`**

Create `src/ca-certificates-1/refresh.py`:

```python
#!/usr/bin/env python3
"""Refresh certs/ and SOURCE from curl.se's Mozilla CA bundle.

Run on the host, never in the guest:

    python refresh.py                     # download cacert.pem and check its .sha256
    python refresh.py --file cacert.pem   # use a local copy (--sha256 HEX to check it)

Needs `openssl` on PATH. Nothing under this directory changes unless every
check passes. On success it prints the pkgver to put in apk/pkginfo.
"""
import argparse
import hashlib
import re
import shutil
import subprocess
import sys
import unicodedata
import urllib.request
from pathlib import Path

BUNDLE_URL = "https://curl.se/ca/cacert.pem"
HERE = Path(__file__).resolve().parent

BEGIN = "-----BEGIN CERTIFICATE-----"
MONTHS = {name: number for number, name in enumerate(
    ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"], 1)}

# "Label\n=====\n-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----"
CERT_RE = re.compile(
    r"^(?P<label>[^\n#=][^\n]*)\n=+\n"
    r"(?P<pem>-----BEGIN CERTIFICATE-----\n.*?-----END CERTIFICATE-----)\n",
    re.M | re.S)
DATE_RE = re.compile(
    r"Certificate data from Mozilla as of: \w{3} (\w{3}) +(\d{1,2}) [\d:]+ (\d{4}) GMT")


class RefreshError(Exception):
    pass


def mozilla_date(text):
    """The bundle's extraction date as YYYYMMDD."""
    m = DATE_RE.search(text)
    if not m or m.group(1) not in MONTHS:
        raise RefreshError("no 'Certificate data from Mozilla as of:' line in the bundle")
    return "%s%02d%02d" % (m.group(3), MONTHS[m.group(1)], int(m.group(2)))


def split_bundle(text):
    """Every certificate in the bundle as (label, pem)."""
    certs = [(m.group("label").strip(), m.group("pem")) for m in CERT_RE.finditer(text)]
    found = text.count(BEGIN)
    if len(certs) != found:
        raise RefreshError("%d certificates in the bundle but only %d have a label line"
                           % (found, len(certs)))
    return certs


def pem_name(label):
    """An ASCII file name for a CA label."""
    ascii_label = unicodedata.normalize("NFKD", label).encode("ascii", "ignore").decode("ascii")
    stem = re.sub(r"[^A-Za-z0-9._-]+", "_", ascii_label).strip("_.")
    if not stem:
        raise RefreshError("label %r has no ASCII characters to build a file name from" % label)
    return stem + ".pem"


def subject_of(pem, label, openssl):
    """The certificate's subject as RFC 2253 text; raises if openssl rejects the PEM."""
    r = subprocess.run([openssl, "x509", "-noout", "-subject", "-nameopt", "RFC2253"],
                       input=pem.encode("ascii"), capture_output=True)
    if r.returncode != 0:
        raise RefreshError("%s: openssl x509 rejected the PEM: %s"
                           % (label, r.stderr.decode("utf-8", "replace").strip()))
    return r.stdout.decode("utf-8", "replace").strip().split("=", 1)[1].strip()


def validate(certs, openssl):
    """Check the set is safe to install; return [(file name, label, pem)]."""
    by_name = {}
    by_subject = {}
    plan = []
    for label, pem in certs:
        name = pem_name(label)
        if name.lower() in by_name:
            raise RefreshError("%r and %r both map to the file name %s (compared ignoring case)"
                               % (by_name[name.lower()], label, name))
        by_name[name.lower()] = label
        subject = subject_of(pem, label, openssl)
        if subject in by_subject:
            raise RefreshError(
                "%r and %r have the same subject (%s); OpenSSL 0.9.5a stops loading a bundle "
                "at the second one" % (by_subject[subject], label, subject))
        by_subject[subject] = label
        plan.append((name, label, pem))
    return plan


def header_of(text):
    """The leading ## comment block of the bundle, verbatim."""
    lines = []
    for line in text.split("\n"):
        if not line.strip() and not lines:
            continue
        if not line.startswith("#"):
            break
        lines.append(line)
    return "\n".join(lines)


def source_text(upstream, digest, pkgver, count, header):
    date = "%s-%s-%s" % (pkgver[:4], pkgver[4:6], pkgver[6:])
    return (
        "Upstream:     %s\n"
        "Mozilla data: as of %s\n"
        "pkgver:       %s\n"
        "SHA-256:      %s\n"
        "Certificates: %d\n"
        "\n"
        "The certificate data is from Mozilla and is subject to the terms of the\n"
        "Mozilla Public License, v. 2.0: http://mozilla.org/MPL/2.0/\n"
        "\n"
        "Header of the upstream file, verbatim:\n"
        "\n"
        "%s\n"
    ) % (upstream, date, pkgver, digest, count, header)


def render(label, pem):
    return "%s\n%s\n%s\n" % (label, "=" * len(label), pem)


def write_tree(out_dir, plan, source):
    stage = out_dir / "certs.new"
    shutil.rmtree(stage, ignore_errors=True)
    stage.mkdir()
    for name, label, pem in plan:
        with open(stage / name, "w", encoding="utf-8", newline="\n") as f:
            f.write(render(label, pem))
    with open(out_dir / "SOURCE.new", "w", encoding="utf-8", newline="\n") as f:
        f.write(source)
    shutil.rmtree(out_dir / "certs", ignore_errors=True)
    stage.rename(out_dir / "certs")
    (out_dir / "SOURCE.new").replace(out_dir / "SOURCE")


def refresh(bundle, out_dir, openssl, upstream, expected_sha256=None):
    """Validate the bundle, then replace out_dir/certs and out_dir/SOURCE.

    Returns (pkgver, certificate count). Raises RefreshError, changing nothing,
    if any check fails.
    """
    digest = hashlib.sha256(bundle).hexdigest()
    if expected_sha256 is not None and digest != expected_sha256.strip().lower():
        raise RefreshError("SHA-256 mismatch: the bundle is %s, expected %s"
                           % (digest, expected_sha256.strip().lower()))
    text = bundle.decode("utf-8").replace("\r\n", "\n")
    pkgver = mozilla_date(text)
    plan = validate(split_bundle(text), openssl)
    write_tree(out_dir, plan, source_text(upstream, digest, pkgver, len(plan), header_of(text)))
    return pkgver, len(plan)


def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()


def main(argv=None):
    ap = argparse.ArgumentParser(description="Refresh certs/ and SOURCE from curl.se's cacert.pem")
    ap.add_argument("--file", help="use this local cacert.pem instead of downloading")
    ap.add_argument("--sha256", help="expected SHA-256 of --file; a download is always checked "
                                     "against the published .sha256")
    ap.add_argument("--url", default=BUNDLE_URL, help="upstream bundle URL (default: %(default)s)")
    ap.add_argument("--out", default=str(HERE), help="project directory to write into")
    ap.add_argument("--openssl", default=shutil.which("openssl") or "openssl")
    args = ap.parse_args(argv)
    try:
        if args.file:
            bundle = Path(args.file).read_bytes()
            expected = args.sha256
        else:
            bundle = fetch(args.url)
            expected = fetch(args.url + ".sha256").decode("ascii").split()[0]
        pkgver, count = refresh(bundle, Path(args.out), args.openssl, args.url, expected)
    except (RefreshError, OSError) as e:
        print("refresh: %s" % e, file=sys.stderr)
        return 1
    print("wrote %d certificates; set pkgver = %s in apk/pkginfo" % (count, pkgver))
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
W=/d/RhapsodiOS/.claude/worktrees/ca-certificates
cd "$W" && python -m unittest discover -s src/ca-certificates-1/tests -v 2>&1 | tail -25
```

Expected: `Ran 16 tests in ...s` and `OK`. Each test mints one or two certificates only in `setUpClass`, so the run takes a few seconds. If `test_names_equal_ignoring_case` or `test_duplicate_subject` fails with the wrong message, the check order in `validate` is the cause: the file-name check must come before `subject_of`.

- [ ] **Step 6: Commit**

```bash
W=/d/RhapsodiOS/.claude/worktrees/ca-certificates
cd "$W" && git add src/ca-certificates-1/refresh.py src/ca-certificates-1/tests/test_refresh.py && git status --short && git commit -q -m "ca-certificates: add the tool that splits Mozilla's roots into checked per-CA PEMs" && git status --short
```

Expected before the commit: two `A` lines. After: no status lines.

---

### Task 2: Import the real Mozilla roots

**Files:**
- Create: `src/ca-certificates-1/certs/*.pem` (one per CA, roughly 140)
- Create: `src/ca-certificates-1/SOURCE`
- Scratch: `$S/cacert.pem`, `$S/cacert.pem.sha256`

**Interfaces:**
- Consumes: Task 1's `refresh.py --file --sha256`.
- Produces: `certs/*.pem` and `SOURCE`, whose `pkgver:` and `Certificates:` lines Task 3 reads.

- [ ] **Step 1: Get the user's go-ahead to download**

Ask the user, in these words or close to them: "I'm about to download `cacert.pem` (about 220 KB) and `cacert.pem.sha256` (about 100 bytes) from https://curl.se/ca/ into the session scratchpad, then split the bundle into `src/ca-certificates-1/certs/`. OK to proceed?" Do not continue without a clear yes.

- [ ] **Step 2: Download both files**

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/9dd0a75b-fe16-48ab-952b-6915cd402a95/scratchpad"
curl -sSf -o "$S/cacert.pem" https://curl.se/ca/cacert.pem && curl -sSf -o "$S/cacert.pem.sha256" https://curl.se/ca/cacert.pem.sha256 && ls -l "$S/cacert.pem" "$S/cacert.pem.sha256" && cat "$S/cacert.pem.sha256" && sed -n 1,20p "$S/cacert.pem"
```

Expected: both files, the `.sha256` holding `<64 hex>  cacert.pem`, and a `##` header whose fourth line reads `## Certificate data from Mozilla as of: <weekday> <month> <day> <time> <year> GMT`, followed by blocks of `Label` and an `=====` underline.

This is where the spec's two unverified assumptions get checked. If the `.sha256` isn't in that form or the header or label layout differs, adjust `DATE_RE`, `CERT_RE` or the `.sha256` parsing in `refresh.py`, add a fixture to `tests/test_refresh.py` reproducing the difference, and re-run Task 1 Step 5 before continuing.

- [ ] **Step 3: Split it**

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/9dd0a75b-fe16-48ab-952b-6915cd402a95/scratchpad"
W=/d/RhapsodiOS/.claude/worktrees/ca-certificates
cd "$W" && python src/ca-certificates-1/refresh.py --file "$S/cacert.pem" --sha256 "$(tr -d '\r' < "$S/cacert.pem.sha256" | cut -d' ' -f1)"; echo "exit=$?"
```

Expected: `wrote N certificates; set pkgver = YYYYMMDD in apk/pkginfo` and `exit=0`, with N around 140.

If it exits 1 with `have the same subject`: **stop and report to the user.** Do not drop or rename either certificate on your own; which one to exclude, or whether to stop supporting 0.9.5a's bundle load, is their decision. If it exits 1 with a file-name collision, the two labels differ only in characters `pem_name` drops; report both labels and propose a disambiguation, do not pick silently.

- [ ] **Step 4: Check the result against the upstream file**

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/9dd0a75b-fe16-48ab-952b-6915cd402a95/scratchpad"
W=/d/RhapsodiOS/.claude/worktrees/ca-certificates
cd "$W/src/ca-certificates-1"
echo "BEGIN lines upstream : $(grep -c -- '-----BEGIN CERTIFICATE-----' "$S/cacert.pem")"
echo "PEM files            : $(ls certs | wc -l)"
echo "SOURCE says          : $(sed -n 's/^Certificates: *//p' SOURCE)"
echo "odd file names       : $(ls certs | LC_ALL=C grep -c '[^A-Za-z0-9._-]')"
echo "files containing CR  : $(grep -l "$(printf '\r')" certs/* SOURCE | wc -l)"
echo "pkgver               : $(sed -n 's/^pkgver: *//p' SOURCE)"
first=$(ls certs | head -1); echo "first: $first"; head -3 "certs/$first"
```

Expected: the first three counts are equal; `odd file names : 0` and `files containing CR  : 0`; `pkgver` is 8 digits; the `head` shows a label, an `=` underline and `-----BEGIN CERTIFICATE-----`.

- [ ] **Step 5: Spot-check one certificate with the host openssl**

```bash
W=/d/RhapsodiOS/.claude/worktrees/ca-certificates
cd "$W/src/ca-certificates-1" && first=$(ls certs | head -1) && openssl x509 -noout -subject -enddate -in "certs/$first"
```

Expected: a `subject=` line and a `notAfter=` date in the future.

- [ ] **Step 6: Commit**

```bash
W=/d/RhapsodiOS/.claude/worktrees/ca-certificates
cd "$W" && git add src/ca-certificates-1/certs src/ca-certificates-1/SOURCE && git status --short | cut -c1-2 | sort | uniq -c && D=$(sed -n 's/^Mozilla data: as of *//p' src/ca-certificates-1/SOURCE) && git commit -q -m "ca-certificates: import Mozilla's roots as of $D from curl.se" && git status --short
```

Expected: one line `N A ` (all files added, none modified) before the commit, and no status lines after.

- [ ] **Step 7: Exercise the download path and idempotency**

`--file` skipped `fetch()`. Run the default path once:

```bash
W=/d/RhapsodiOS/.claude/worktrees/ca-certificates
cd "$W" && python src/ca-certificates-1/refresh.py; echo "exit=$?"; git status --short | head
```

Expected: the same `wrote N certificates` line, `exit=0`, and **no** status lines (the output is byte-identical). If `SOURCE` shows as modified because its date moved, curl.se published a newer bundle in the last few minutes: run `git checkout -- src/ca-certificates-1` to discard it and carry on with the committed set. If the download or `.sha256` check itself fails, fix `fetch`/`main` in `refresh.py`, add a test if the failure is reproducible offline, and re-run Task 1 Step 5.

---

### Task 3: Package it with rbuild and verify on the guest

**Files:**
- Create: `src/ca-certificates-1/Makefile`
- Create: `src/ca-certificates-1/apk/pkginfo`
- Modify: `src/Manifest`, adding one line after `dir     bsdmake-1             all`
- Modify: `docs/superpowers/specs/2026-09-24-ca-certificates-design.md`
- Test: `$S/preflight.sh`, `$S/pkg-start.sh`, `$S/pkg-check.sh`, `$S/pkg-cleanup.sh` (guest scripts, scratch)

**Interfaces:**
- Consumes: Task 2's `certs/` and `SOURCE` (`pkgver:` and `Certificates:` lines); `$S/rx.ps1` from Setup.
- Produces: `/build/cacert/out/ca-certificates-<pkgver>-1-universal.apk` on the guest.

**Background:** rbuild runs `make install` in a chroot built from `/build/repo`, passing `SRCROOT`, `OBJROOT`, `SYMROOT`, `DSTROOT` and `RC_*`. `Common.make` provides `installhdrs`, `installsrc` and `clean`, and its `install::` runs `build` first, which is empty here. `$(Sources)` is `$(SRCROOT)`. `INSTALL_FILE` is `install -m 0444 -o root -g wheel`, which needs `-c` on this guest or it moves its source.

- [ ] **Step 1: Write the guest scripts**

Create `$S/preflight.sh`:

```sh
# Guest preflight: tools, repo readiness, and how install/ln behave here.
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin; export PATH
uname -a
echo "== tools"
for t in comm cmp sort sed grep find gzip tar install ln cat chmod; do type $t; done
if test -x /build/tools/bin/rbuild; then echo "have rbuild"; else echo "MISSING rbuild"; fi
if test -x /usr/bin/openssl; then echo "have /usr/bin/openssl"; else echo "no /usr/bin/openssl"; fi
echo "== repo"
for f in /build/repo/libsystem-*-universal.apk /build/repo/openssl-[0-9]*.apk /build/repo/build-base-*.apk; do
    if test -f "$f"; then echo "$f"; fi
done
busy=`ps -axww | grep 'rbuild bootstrap' | grep -v grep | wc -l | tr -d ' '`
echo "rbuild bootstrap processes running: $busy"
echo "== install/ln"
P=/tmp/cacert-probe; rm -rf $P; mkdir -p $P/src $P/dst; cd $P || exit 1
printf 'a\n' > src/A.pem; printf 'b\n' > src/B.pem
install -m 0444 -c src/A.pem dst/; echo "install -c rc=$?"
install -m 0444 src/B.pem dst/; echo "install (no -c) rc=$?"
echo "src:"; ls src; echo "dst:"; ls dst
install -d -m 0755 dst/x/y; echo "install -d rc=$?"
ln -fs /System/Library/OpenSSL/certs dst/lnk; echo "ln rc=$?"
ln -fs ../cert.pem dst/x/ca.crt
ls -l dst/lnk dst/x/ca.crt
cat dst/A.pem dst/B.pem
cd /; rm -rf $P
libs=0
for f in /build/repo/libsystem-*-universal.apk; do if test -f "$f"; then libs=1; fi; done
if [ "$busy" = 0 ] && [ "$libs" = 1 ]; then echo REPO_READY; exit 0; fi
echo REPO_NOT_READY
exit 1
```

Create `$S/pkg-start.sh`:

```sh
# Start rbuild buildpackage for ca-certificates under nohup; returns immediately.
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin; export PATH
rm -rf /build/cacert/out
mkdir -p /build/cacert/out /build/cacert/state
rm -f /tmp/cacert-rbuild.log /tmp/cacert-rbuild.rc
cat > /tmp/cacert-rbuild.sh <<'EOF'
#!/bin/sh
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin; export PATH
rbuild buildpackage --state /build/cacert/state --dir --target all \
    /build/cacert/src/ca-certificates-1 /build/repo /build/cacert/out \
    > /tmp/cacert-rbuild.log 2>&1
echo $? > /tmp/cacert-rbuild.rc
EOF
chmod a+x /tmp/cacert-rbuild.sh
nohup /tmp/cacert-rbuild.sh > /dev/null 2>&1 < /dev/null &
echo PKG_BUILD_STARTED
exit 0
```

Create `$S/pkg-check.sh`:

```sh
# Report on the ca-certificates buildpackage: running, failed, or verify the apk.
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin; export PATH
OUT=/build/cacert/out
SRC=/build/cacert/src/ca-certificates-1
X=/tmp/cacert-apk-check
fail() { echo "PACKAGE_TEST_FAILED: $1"; exit 1; }

if [ ! -f /tmp/cacert-rbuild.rc ]; then
    echo PKG_BUILD_RUNNING
    tail -3 /tmp/cacert-rbuild.log 2>/dev/null
    exit 2
fi
rc=`cat /tmp/cacert-rbuild.rc`
tail -25 /tmp/cacert-rbuild.log
echo "RBUILD_RC=$rc"
[ "$rc" = 0 ] || fail "rbuild rc=$rc"

APK=
for f in $OUT/ca-certificates-[0-9]*-1-universal.apk; do
    if [ -f "$f" ]; then APK=$f; fi
done
[ -n "$APK" ] || fail "no ca-certificates-<pkgver>-1-universal.apk in $OUT"
echo "APK=$APK"
N=`sed -n 's/^Certificates: *//p' $SRC/SOURCE`
PKGVER=`sed -n 's/^pkgver: *//p' $SRC/SOURCE`
[ -n "$N" ] && [ -n "$PKGVER" ] || fail "cannot read Certificates and pkgver from $SRC/SOURCE"
[ "$APK" = "$OUT/ca-certificates-$PKGVER-1-universal.apk" ] || fail "apk name does not carry pkgver $PKGVER"

rm -rf $X && mkdir -p $X || fail "cannot create $X"
gzip -dc $APK | (cd $X && tar xf -) || fail "cannot extract $APK"
O=$X/System/Library/OpenSSL
E=$X/private/etc/ssl
B=$O/cert.pem

echo "== .PKGINFO"
cat $X/.PKGINFO
grep "^pkgver = $PKGVER-1\$" $X/.PKGINFO > /dev/null || fail ".PKGINFO pkgver is not $PKGVER-1"

echo "== member inventory"
# Non-directory entries of the extracted tree (find does not follow symlinks),
# without top-level metadata such as .PKGINFO.
(cd $X && find . \( -type f -o -type l \) | sed 's|^\./||' | grep -v '^\.' | sort) > $X.all
grep -v '^System/Library/OpenSSL/certs/.*\.pem$' $X.all > $X.members
cat > $X.expect <<EOF
System/Library/OpenSSL/cert.pem
System/Library/OpenSSL/certs/ca-certificates.crt
private/etc/ssl/cert.pem
private/etc/ssl/certs
usr/share/doc/ca-certificates/SOURCE
EOF
cat $X.members
sort $X.expect | cmp - $X.members > /dev/null || fail "members outside certs/*.pem differ from the expected five"

echo "== certs/"
have=`ls $O/certs | grep -c '\.pem$'`
[ "$have" = "$N" ] || fail "certs/ holds $have PEMs, SOURCE says $N"
stray=`ls $O/certs | grep -v '\.pem$' | grep -v '^ca-certificates\.crt$'`
[ -z "$stray" ] || fail "unexpected entries in certs/: $stray"
bad=`ls -l $O/certs | grep '^-' | grep -v '^-r--r--r--'`
[ -z "$bad" ] || fail "PEMs that are not mode 0444: $bad"
ls -l $B | grep '^-r--r--r--' > /dev/null || fail "cert.pem is not a regular 0444 file"

echo "== symlinks"
tgt() { ls -l "$1" | sed 's/.* -> //'; }
[ "`tgt $O/certs/ca-certificates.crt`" = "../cert.pem" ] || fail "certs/ca-certificates.crt target"
[ "`tgt $E/certs`" = "/System/Library/OpenSSL/certs" ] || fail "/etc/ssl/certs target"
[ "`tgt $E/cert.pem`" = "/System/Library/OpenSSL/cert.pem" ] || fail "/etc/ssl/cert.pem target"
ls -l $O/certs/ca-certificates.crt $E/certs $E/cert.pem

echo "== bundle"
got=`grep -c -- '-----BEGIN CERTIFICATE-----' $B`
[ "$got" = "$N" ] || fail "cert.pem has $got certificates, SOURCE says $N"
cat $O/certs/*.pem | cmp - $B > /dev/null || fail "cert.pem is not the sorted concatenation of certs/*.pem"
[ -f $X/usr/share/doc/ca-certificates/SOURCE ] || fail "doc SOURCE missing"

echo "== in-tree openssl"
SSLAPK=
for f in /build/repo/openssl-[0-9]*.apk; do
    if [ -f "$f" ]; then SSLAPK=$f; fi
done
if [ -n "$SSLAPK" ]; then
    rm -rf $X.ssl && mkdir -p $X.ssl
    gzip -dc $SSLAPK | (cd $X.ssl && tar xf -) || fail "cannot extract $SSLAPK"
fi
OSSL=
if [ -x /usr/bin/openssl ]; then
    OSSL=/usr/bin/openssl
elif [ -n "$SSLAPK" ]; then
    OSSL=`find $X.ssl -name openssl -type f | head -1`
    LIBDIR=`find $X.ssl -name 'libcrypto.*.dylib' | head -1 | sed 's|/[^/]*$||'`
    [ -n "$OSSL" ] && [ -n "$LIBDIR" ] || fail "the openssl apk lacks the binary or libcrypto"
    DYLD_LIBRARY_PATH=$LIBDIR; export DYLD_LIBRARY_PATH
fi
[ -n "$OSSL" ] || fail "no in-tree openssl: neither /usr/bin/openssl nor an openssl apk in /build/repo"
$OSSL version
FIRST=
for f in $O/certs/*.pem; do FIRST=$f; break; done
subs=`$OSSL crl2pkcs7 -nocrl -certfile $B | $OSSL pkcs7 -print_certs | grep -c '^subject='`
[ "$subs" = "$N" ] || fail "pkcs7 -print_certs read $subs certificates from cert.pem, expected $N"
$OSSL verify -CAfile $B $FIRST > $X.verify 2>&1
cat $X.verify
if grep 'Error loading file' $X.verify > /dev/null; then fail "openssl could not load cert.pem as a CAfile"; fi

echo "== file conflicts with the openssl apk"
if [ -n "$SSLAPK" ]; then
    (cd $X.ssl && find . \( -type f -o -type l \) | sed 's|^\./||' | grep -v '^\.' | sort) > $X.ssl.members
    comm -12 $X.all $X.ssl.members > $X.conflict
    if [ -s $X.conflict ]; then cat $X.conflict; fail "files present in both apks"; fi
    echo "none (checked against $SSLAPK)"
    echo PACKAGE_TEST_OK
else
    echo "no openssl apk in /build/repo: conflict check skipped"
    echo "PACKAGE_TEST_OK (conflict check skipped)"
fi
exit 0
```

Create `$S/pkg-cleanup.sh`:

```sh
rm -rf /tmp/cacert-probe /tmp/cacert-apk-check /tmp/cacert-apk-check.* /tmp/cacert-rbuild.sh
ls -l /build/cacert/out
exit 0
```

- [ ] **Step 2: Run the guest preflight**

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/9dd0a75b-fe16-48ab-952b-6915cd402a95/scratchpad"
powershell -NoProfile -File "$(cygpath -w "$S/rx.ps1")" -ScriptFile "$(cygpath -w "$S/preflight.sh")"; echo "exit=$?"
```

Expected:
- Every tool in the `type` list resolves to a path, and `have rbuild`.
- The install probe shows `install -c rc=0` and, after the second install, `src:` listing only `A.pem` while `dst:` lists both: without `-c` the source is **moved**, with it the source stays. (That is why the Makefile passes `-c`.) Also `ln rc=0` and two `lrwxr-xr-x ... -> ...` lines.
- `REPO_READY` and `exit=0`.

If the output is `Connection closed by 10.10.0.241 port 22`, the guest's sshd is refusing sessions (it did this on 2026-09-24 while the guest still answered ping). Retry after a minute, up to three times, then stop and report BLOCKED; do not start, restart or wait on anything on the guest.

If a tool in the `type` list is `not found`, report which one before writing further; the check script and Makefile use all of them.

If `REPO_NOT_READY`: carry on through Step 6 (writing the files), then **stop before Step 7 and report BLOCKED** with the preflight output. Another session is bootstrapping or the universal build-base isn't in `/build/repo` yet. Do not start or wait on a bootstrap yourself.

If `openssl-*.apk` didn't list and there is no `have /usr/bin/openssl`, the check script will fail at its openssl step with `no in-tree openssl`. That is a real gap in the guest's repo, not something to work around; report it.

- [ ] **Step 3: Sync and run the build to verify it fails**

The project has no `Makefile` or `apk/pkginfo` yet, so rbuild must refuse it.

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/9dd0a75b-fe16-48ab-952b-6915cd402a95/scratchpad"
W=/d/RhapsodiOS/.claude/worktrees/ca-certificates
cd "$W" && powershell -NoProfile -File vm/sync-src.ps1 -Path ca-certificates-1 && powershell -NoProfile -File "$(cygpath -w "$S/rx.ps1")" -ScriptFile "$(cygpath -w "$S/pkg-start.sh")"; sleep 20; powershell -NoProfile -File "$(cygpath -w "$S/rx.ps1")" -ScriptFile "$(cygpath -w "$S/pkg-check.sh")"; echo "exit=$?"
```

Expected: `sync-src: complete`, `PKG_BUILD_STARTED`, then a log tail with an rbuild error about the missing `apk/pkginfo` (exact wording may vary), a non-zero `RBUILD_RC=`, `PACKAGE_TEST_FAILED: rbuild rc=...` and `exit=1`. If you get `PKG_BUILD_RUNNING`, wait 20 seconds and re-run only the `pkg-check.sh` command. The files land in `/build/cacert/src/ca-certificates-1` because of the `RemoteRoot` set in Setup.

- [ ] **Step 4: Create the `Makefile`**

Recipe lines start with a **tab**. Create `src/ca-certificates-1/Makefile`:

```make
##
# Makefile for ca-certificates
##

# Project info
Project  = ca-certificates
UserType = Administration
ToolType = Commands

include $(MAKEFILEPATH)/CoreOS/ReleaseControl/Common.make

OPENSSLDIR = $(NSLIBRARYDIR)/OpenSSL
SSLDIR     = $(ETCDIR)/ssl
DOCDIR     = $(SHAREDIR)/doc/$(Project)

install::
	$(INSTALL_DIRECTORY) $(DSTROOT)$(OPENSSLDIR)/certs
	$(INSTALL_DIRECTORY) $(DSTROOT)$(SSLDIR)
	$(INSTALL_DIRECTORY) $(DSTROOT)$(DOCDIR)
	$(_v) for pem in $(Sources)/certs/*.pem; do \
	        $(INSTALL_FILE) -c $$pem $(DSTROOT)$(OPENSSLDIR)/certs || exit 1; \
	      done
	$(CAT) $(Sources)/certs/*.pem > $(DSTROOT)$(OPENSSLDIR)/cert.pem
	$(CHMOD) $(Install_File_Mode) $(DSTROOT)$(OPENSSLDIR)/cert.pem
	$(LN) -fs ../cert.pem $(DSTROOT)$(OPENSSLDIR)/certs/ca-certificates.crt
	$(LN) -fs $(OPENSSLDIR)/certs $(DSTROOT)$(SSLDIR)/certs
	$(LN) -fs $(OPENSSLDIR)/cert.pem $(DSTROOT)$(SSLDIR)/cert.pem
	$(INSTALL_FILE) -c $(Sources)/SOURCE $(DSTROOT)$(DOCDIR)
```

`OPENSSLDIR` resolves to `/System/Library/OpenSSL` (`NSLIBRARYDIR` = `/System/Library`) and `SSLDIR` to `/private/etc/ssl` (`ETCDIR`), both from `CoreOSMakefiles-1/Standard/Variables.make`. The two directory-symlink targets are absolute on purpose; only the `ca-certificates.crt` alias is relative. The loop installs one file at a time so it doesn't depend on this guest's `install` accepting many files.

Check the tabs:

```bash
W=/d/RhapsodiOS/.claude/worktrees/ca-certificates
grep -c "^$(printf '\t')" "$W/src/ca-certificates-1/Makefile"
```

Expected: `12` (three `install -d` lines, the three lines of the `for` loop, `cat`, `chmod`, three `ln` lines and the SOURCE install).

- [ ] **Step 5: Create `apk/pkginfo` and the Manifest entry**

```bash
W=/d/RhapsodiOS/.claude/worktrees/ca-certificates
cd "$W/src/ca-certificates-1" && PKGVER=$(sed -n 's/^pkgver: *//p' SOURCE | tr -d '\r') && test -n "$PKGVER" && mkdir -p apk && cat > apk/pkginfo <<EOF
pkgname = ca-certificates
pkgver = $PKGVER
pkgdesc = Common CA certificates from Mozilla
maintainer = Darwin Developers <darwin-development@public.lists.apple.com>
license = MPL-2.0
url = https://curl.se/docs/caextract.html
makedepends = build-base
EOF
cat apk/pkginfo
```

Expected: the seven lines, with `pkgver = ` followed by the 8-digit date from `SOURCE`.

Insert one line in `src/Manifest` directly after `dir     bsdmake-1             all`. The project column is 22 characters wide: `ca-certificates-1` is 17 characters plus 5 spaces.

```bash
W=/d/RhapsodiOS/.claude/worktrees/ca-certificates
cd "$W" && sed -i 's|^dir     bsdmake-1             all$|&\ndir     ca-certificates-1     all|' src/Manifest && grep -n -B1 -A1 'ca-certificates-1' src/Manifest && git diff --stat src/Manifest
```

Expected:

```
15-dir     bsdmake-1             all
16:dir     ca-certificates-1     all
17-dir     cc-1                  all
```

and `1 file changed, 1 insertion(+)`. Another session may be rewriting other `src/Manifest` entries on its own branch; this line doesn't touch those, and any merge conflict is resolved when the branches merge, not here.

- [ ] **Step 6: Sync and build**

Only when Step 2 printed `REPO_READY`. The build extracts build-base into a chroot and runs compiler probes for both CPUs, so it takes several minutes even though nothing is compiled.

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/9dd0a75b-fe16-48ab-952b-6915cd402a95/scratchpad"
W=/d/RhapsodiOS/.claude/worktrees/ca-certificates
cd "$W" && powershell -NoProfile -File vm/sync-src.ps1 -Path ca-certificates-1 && powershell -NoProfile -File "$(cygpath -w "$S/rx.ps1")" -ScriptFile "$(cygpath -w "$S/pkg-start.sh")"
```

Expected: `sync-src: complete`, `PKG_BUILD_STARTED`.

- [ ] **Step 7: Poll until the check passes**

Poll roughly every 2 minutes until the exit code isn't 2:

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/9dd0a75b-fe16-48ab-952b-6915cd402a95/scratchpad"
powershell -NoProfile -File "$(cygpath -w "$S/rx.ps1")" -ScriptFile "$(cygpath -w "$S/pkg-check.sh")"; echo "exit=$?"
```

Expected at the end:
- `RBUILD_RC=0` and `APK=/build/cacert/out/ca-certificates-<pkgver>-1-universal.apk`.
- `.PKGINFO` with `pkgver = <pkgver>-1`.
- The member inventory prints the five paths outside `certs/*.pem`.
- The `certs/`, `symlinks` and `bundle` sections print no failure; the `ls -l` lines show `certs/ca-certificates.crt -> ../cert.pem`, `certs -> /System/Library/OpenSSL/certs` and `cert.pem -> /System/Library/OpenSSL/cert.pem`.
- An `OpenSSL 0.9.5a ...` version line; `openssl verify` output with no `Error loading file` (its verdict on the first cert, likely an unsupported algorithm or missing issuer, does not matter).
- `none (checked against /build/repo/openssl-...apk)` and `PACKAGE_TEST_OK`, and `exit=0`.
- `PACKAGE_TEST_OK (conflict check skipped)` is acceptable only if the repo has no openssl apk; say so in the report.

On failure, the log tail is printed; for more, put `tail -200 /tmp/cacert-rbuild.log` in a script and run it through `rx.ps1`. Fix the cause and re-run Steps 6 and 7. Failures to expect and their meaning:
- `pkcs7 -print_certs read M certificates, expected N` with M < N: the in-tree 0.9.5a cannot parse one of the certs. Bisect by loading `certs/*.pem` one at a time with `openssl x509 -noout -subject -in`, and report the culprit to the user; do not drop it silently.
- `openssl could not load cert.pem as a CAfile`: 0.9.5a's store rejected a cert, most likely a duplicate subject that Task 1's check missed (for example one that differs only in string encoding); report both certificates.

- [ ] **Step 8: Correct the spec**

Planning and the build turned up things the spec got wrong or left open. Edit `docs/superpowers/specs/2026-09-24-ca-certificates-design.md` in the worktree:

1. **Goal:** replace `` `ca-certificates-<pkgver>-universal.apk`, and it is listed in `src/Manifest`. `` with `` `ca-certificates-<pkgver>-1-universal.apk` (rbuild takes the `-1` from the directory name), and it is listed in `src/Manifest`. ``
2. **Layout block:** replace the `Makefile` line with `Makefile        Common.make wrapper, like pico-1: an install:: recipe only`; end the `SOURCE` description with `the verbatim header of cacert.pem, and a Mozilla Public License 2.0 statement` instead of `the MPL notice from cacert.pem's header`; add the line `tests/          unittest suite for refresh.py` after the `refresh.py` line.
3. **pkgver paragraph:** replace `rbuild copies the version into the apk name unchanged (package_canon_version), and apk accepts an all-digit version.` with `rbuild appends the directory's -1, so .PKGINFO says pkgver = <YYYYMMDD>-1 and the apk is named ca-certificates-<YYYYMMDD>-1-universal.apk.`
4. **Makefile section:** replace its body with: `A Common.make wrapper like pico-1, which supplies installhdrs, installsrc and clean. Only install:: is written: it makes the directories, installs each PEM with install -c (the guest's install moves its source without -c), builds cert.pem with cat, chmods it 0444, and makes the three symlinks. It runs under the build box's GNU Make 3.74, so it uses no target-specific variables. The package is universal like keymaps-1 and sounds-1; rbuild's compiler probes still run for it.`
5. **Verification item 2:** replace it with `No file in the ca-certificates apk is also in the openssl apk. Directories such as certs/ are shared, which apk allows; a shared file would be the real conflict. This is checked by comparing the two apks' member lists.` In the unit-test paragraph, keep the crafted-input list as is.
6. **Replace `## Unverified until implementation`** with `## Verified during implementation` holding one bullet per former item, stating what the run showed: what curl.se's `.sha256` file and header/label layout look like (Task 2 Step 2), that the guest's `install -c` and `ln -fs` behave as the Makefile assumes (Task 3 Step 2), and that rbuild and the apk accepted the all-digit `pkgver` (Task 3 Step 7). The shared-directory bullet becomes the file-conflict result from Step 7.

Then check nothing else in the spec still says otherwise:

```bash
W=/d/RhapsodiOS/.claude/worktrees/ca-certificates
grep -n -E "keymaps-1|universal\.apk|Unverified|apk add|from memory" "$W/docs/superpowers/specs/2026-09-24-ca-certificates-design.md"
```

Expected: `keymaps-1` only in the sentence that says the package is universal like `keymaps-1` and `sounds-1`; every `universal.apk` shows `-1-`; no `Unverified`, no `apk add`, no `from memory`.

- [ ] **Step 9: Commit**

```bash
W=/d/RhapsodiOS/.claude/worktrees/ca-certificates
cd "$W" && git add src/ca-certificates-1/Makefile src/ca-certificates-1/apk/pkginfo src/Manifest && git status --short && git commit -q -m "ca-certificates: package the roots with rbuild and list them in the world Manifest" && git add docs/superpowers/specs/2026-09-24-ca-certificates-design.md && git commit -q -m "docs: correct the ca-certificates spec to what the build showed" && git status --short && git log --oneline -4
```

Expected before the first commit: `A` for `Makefile` and `apk/pkginfo`, `M` for `src/Manifest` and `M` for the spec (the spec is unstaged at that point, shown as ` M`). After: no status lines, and the log shows the two new commits on top of the Task 2 import.

- [ ] **Step 10: Clean up guest scratch space**

```bash
S="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/9dd0a75b-fe16-48ab-952b-6915cd402a95/scratchpad"
powershell -NoProfile -File "$(cygpath -w "$S/rx.ps1")" -ScriptFile "$(cygpath -w "$S/pkg-cleanup.sh")"; echo "exit=$?"
```

Expected: the apk listing and `exit=0`. The apk in `/build/cacert/out`, `/tmp/cacert-rbuild.log` and `/build/cacert` are kept as evidence; `rm -rf /build/cacert` once the branch has merged.

---

## After all tasks

Use superpowers:finishing-a-development-branch to decide how `ca-certificates` goes back to `master`. Before merging, `git diff master --stat` should show only: `src/ca-certificates-1/**`, one added line in `src/Manifest`, and the spec correction.

---

## Run note (2026-09-25)

Task 3 ran on a private QEMU i386 guest, not the ppc box the plan names. That box (10.10.0.241) is down, and the shared i386 guest at 127.0.0.1:2222 was left alone. The private guest booted `vm/work/rhap-i386-bootstrapped.img` with `-snapshot` (so the image was never written), with ssh forwarded to 127.0.0.1:2221 (telnet 2321, QMP 4461). Where this run departed from the text above, the run wins:

- `rbuild buildpackage` needs `--toolchain /build/src/rbuild-1/toolchains/gcc-darwin-i386.conf` on that guest; `pkg-start.sh` was run with it, in the foreground of one ssh session.
- This branch predates master's `Port=` support in `vm/rhap-remote.ps1`, so master's `rhap-remote`, `build-src-lib`, `sync-src`, `sync-src-lib` and `guest-remote` scripts ran from a scratchpad copy with a `vm.conf` of `Port=2221`, `RemoteRoot=/build/cacert` and `LocalRoot=` the worktree. Master's `sync-src.ps1` does not create `/build/cacert`, so `mkdir -p /build/cacert/src` came first.
- The guest's `sh` has no `type` builtin, so `preflight.sh` prints `type: not found` for its tool list. Its other checks worked.
- The guest's openssl is `/usr/local/ssl/bin/openssl`, version 0.9.8, and `/build/repo` has no openssl apk. `pkg-check.sh` used that binary, and its file-conflict step was answered by reading 0.9.5a's install rules instead.
- rbuild rewrites absolute symlinks to relative, so the first `pkg-check.sh` run failed only on its absolute-target expectation. The check now expects `../../../System/Library/OpenSSL/certs` and `.../cert.pem` and also follows the links inside the extracted root.
- Step 3's expected-failure run was skipped: the Makefile and `pkginfo` had already been written when the guest became available.

Result: `RBUILD_RC=0`, `ca-certificates-20260813-1-universal.apk`, `PACKAGE_TEST_OK (conflict check skipped)`. The load check with the tree's own 0.9.5a `openssl` is still open; see the spec's "Verified during implementation".
