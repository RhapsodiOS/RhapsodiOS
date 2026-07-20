#!/usr/bin/env python3
"""Mass-migrate */dpkg/control → */apk/PKGINFO, then remove dpkg/control."""
from __future__ import print_function
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRCROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "src"))


def field(text, key):
    m = re.search(r"^%s:\s*(.*)$" % re.escape(key), text, re.M)
    if not m:
        return ""
    return m.group(1).strip().replace("\r", "")


def description(text):
    m = re.search(r"^Description:\s*(.*)$", text, re.M)
    if not m:
        return ""
    return m.group(1).strip().replace("\r", "")


def normalize_deps(val):
    if not val:
        return ""
    val = re.sub(r"\([^)]*\)", "", val)
    val = val.replace(",", " ")
    val = re.sub(r"\s+", " ", val).strip()
    return val


def control_to_pkginfo(ctl_path):
    with open(ctl_path, "rb") as f:
        raw = f.read()
    text = raw.decode("latin-1")
    pkgname = field(text, "Package")
    pkgver = field(text, "Version")
    if not pkgname or not pkgver:
        raise ValueError("Package and Version required in %s" % ctl_path)
    url = field(text, "URL") or field(text, "Homepage")
    arch = field(text, "Architecture")
    pkgdesc = description(text)
    builddepend = normalize_deps(field(text, "Build-Depends"))
    depend = normalize_deps(field(text, "Depends"))
    lines = [
        "pkgname = %s" % pkgname,
        "pkgver = %s" % pkgver,
        "pkgdesc = %s" % pkgdesc,
        "url = %s" % url,
        "license = unknown",
        "builddepend = %s" % builddepend,
        "depend = %s" % depend,
    ]
    if arch:
        lines.append("arch = %s" % arch)
    return "\n".join(lines) + "\n"


def main():
    converted = skipped = failed = 0
    controls = []
    for dirpath, _dirnames, filenames in os.walk(SRCROOT):
        if os.path.basename(dirpath) == "dpkg" and "control" in filenames:
            controls.append(os.path.join(dirpath, "control"))
    controls.sort()

    for ctl in controls:
        proj = os.path.dirname(os.path.dirname(ctl))
        apkdir = os.path.join(proj, "apk")
        pkginfo = os.path.join(apkdir, "PKGINFO")
        rel = os.path.relpath(proj, SRCROOT)
        try:
            if os.path.isfile(pkginfo):
                print("skip (PKGINFO exists): %s" % rel)
                skipped += 1
            else:
                body = control_to_pkginfo(ctl)
                if "pkgname = " not in body:
                    raise ValueError("empty pkgname")
                if not os.path.isdir(apkdir):
                    os.makedirs(apkdir)
                with open(pkginfo, "wb") as f:
                    f.write(body.encode("utf-8"))
                print("ok: %s" % rel)
                converted += 1
            os.remove(ctl)
            dpkgdir = os.path.dirname(ctl)
            try:
                os.rmdir(dpkgdir)
            except OSError:
                pass
        except Exception as e:
            print("FAIL: %s: %s" % (ctl, e), file=sys.stderr)
            failed += 1

    left = 0
    for dirpath, _dirnames, filenames in os.walk(SRCROOT):
        if os.path.basename(dirpath) == "dpkg" and "control" in filenames:
            left += 1

    print("---")
    print("converted=%d skipped=%d failed=%d" % (converted, skipped, failed))
    print("remaining_dpkg_control=%d" % left)
    if failed or left:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
