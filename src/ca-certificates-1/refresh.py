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
