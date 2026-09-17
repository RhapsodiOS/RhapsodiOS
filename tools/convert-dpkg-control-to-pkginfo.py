#!/usr/bin/env python3
"""Convert src/**/dpkg/control trees to apk/pkginfo (one-shot bulk rewrite)."""

from __future__ import annotations

import argparse
import os
import shutil
import stat
import sys
import tempfile
import textwrap

SCRIPT_MAP = {
    "preinst": ".pre-install",
    "postinst": ".post-install",
    "prerm": ".pre-deinstall",
    "postrm": ".post-deinstall",
}

DROPPED_KEYS = frozenset(
    {
        "Vendor",
        "Section",
        "Priority",
        "Conflicts",
        "Revision",
        "Source",
    }
)

EMIT_ORDER = (
    "pkgname",
    "pkgver",
    "arch",
    "pkgdesc",
    "maintainer",
    "license",
    "url",
    "provides",
    "replaces",
    "makedepends",
)


def parse_control(text: str) -> dict[str, str]:
    """Parse Debian control format into a field dict."""
    fields: dict[str, str] = {}
    current_key: str | None = None

    for line in text.splitlines():
        if line.startswith(" ") and current_key is not None:
            fields[current_key] = fields[current_key] + " " + line.lstrip()
            continue
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        current_key = key.strip()
        fields[current_key] = value.lstrip()

    return fields


def control_to_pkginfo(fields: dict[str, str]) -> str:
    """Map parsed control fields to apk/pkginfo text."""
    mapped: dict[str, str] = {}

    if "Package" in fields:
        mapped["pkgname"] = fields["Package"]
    if "Version" in fields:
        mapped["pkgver"] = fields["Version"]
    if "Architecture" in fields:
        mapped["arch"] = fields["Architecture"]
    if "Description" in fields:
        mapped["pkgdesc"] = fields["Description"]
    if "Maintainer" in fields:
        mapped["maintainer"] = fields["Maintainer"]
    mapped["license"] = "unknown"
    if "URL" in fields:
        mapped["url"] = fields["URL"]
    if "Provides" in fields:
        mapped["provides"] = fields["Provides"]
    if "Replaces" in fields:
        mapped["replaces"] = fields["Replaces"]
    if "Build-Depends" in fields:
        mapped["makedepends"] = fields["Build-Depends"]

    lines: list[str] = []
    for key in EMIT_ORDER:
        if key in mapped:
            lines.append(f"{key} = {mapped[key]}")
    return "\n".join(lines) + "\n"


def discover_controls(src_root: str) -> list[str]:
    """Find every src/**/dpkg/control path."""
    controls: list[str] = []
    for dirpath, _dirnames, filenames in os.walk(src_root):
        if os.path.basename(dirpath) == "dpkg" and "control" in filenames:
            controls.append(os.path.join(dirpath, "control"))
    return sorted(controls)


def package_dir(control_path: str) -> str:
    return os.path.dirname(os.path.dirname(control_path))


def display_path(path: str) -> str:
    """Return a stable relative path for error messages."""
    try:
        return os.path.relpath(path)
    except ValueError:
        return path


def validate_controls(control_paths: list[str]) -> list[str]:
    """Validate all controls; return error messages (empty if ok)."""
    errors: list[str] = []

    for control_path in control_paths:
        pkg_dir = package_dir(control_path)
        pkginfo_path = os.path.join(pkg_dir, "apk", "pkginfo")

        if os.path.isfile(pkginfo_path):
            errors.append(f"collision: {display_path(pkginfo_path)} already exists")

        with open(control_path, encoding="utf-8", errors="replace") as fh:
            fields = parse_control(fh.read())

        if "Package" not in fields:
            errors.append(f"missing Package in {display_path(control_path)}")
        if "Version" not in fields:
            errors.append(f"missing Version in {display_path(control_path)}")

        for key in fields:
            if key in DROPPED_KEYS:
                continue
            if key in (
                "Package",
                "Version",
                "Architecture",
                "Description",
                "Maintainer",
                "URL",
                "Build-Depends",
                "Provides",
                "Replaces",
            ):
                continue
            if key in SCRIPT_MAP or key == "conffiles":
                continue
            # Unknown keys are dropped silently per spec.

    return errors


def copy_scripts(dpkg_dir: str, apk_dir: str) -> int:
    """Copy maintainer scripts into apk/; return count moved."""
    moved = 0
    os.makedirs(apk_dir, exist_ok=True)

    for src_name, dst_name in SCRIPT_MAP.items():
        src_path = os.path.join(dpkg_dir, src_name)
        if not os.path.isfile(src_path):
            continue
        dst_path = os.path.join(apk_dir, dst_name)
        shutil.copy2(src_path, dst_path)
        src_mode = os.stat(src_path).st_mode
        if src_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH):
            os.chmod(dst_path, os.stat(dst_path).st_mode | stat.S_IXUSR)
        moved += 1

    return moved


def convert_control(control_path: str) -> int:
    """Convert one control tree; return number of scripts moved."""
    pkg_dir = package_dir(control_path)
    dpkg_dir = os.path.join(pkg_dir, "dpkg")
    apk_dir = os.path.join(pkg_dir, "apk")
    pkginfo_path = os.path.join(apk_dir, "pkginfo")

    with open(control_path, encoding="utf-8", errors="replace") as fh:
        fields = parse_control(fh.read())

    os.makedirs(apk_dir, exist_ok=True)
    with open(pkginfo_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(control_to_pkginfo(fields))

    scripts_moved = copy_scripts(dpkg_dir, apk_dir)
    shutil.rmtree(dpkg_dir)
    return scripts_moved


def run_conversion(src_root: str) -> int:
    """Two-pass convert; return exit code."""
    control_paths = discover_controls(src_root)
    errors = validate_controls(control_paths)
    if errors:
        for msg in errors:
            print(msg, file=sys.stderr)
        return 2

    converted = 0
    scripts_moved = 0
    for control_path in control_paths:
        scripts_moved += convert_control(control_path)
        converted += 1

    remaining = len(discover_controls(src_root))
    print(f"converted={converted}")
    print(f"scripts moved={scripts_moved}")
    print(f"remaining dpkg/control={remaining}")
    return 0 if remaining == 0 else 1


def _assert(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def run_self_test() -> int:
    """Run built-in TDD checks in a temp directory."""
    with tempfile.TemporaryDirectory() as tmp:
        # grep-like mapping
        grep_dir = os.path.join(tmp, "grep-1")
        grep_dpkg = os.path.join(grep_dir, "dpkg")
        os.makedirs(grep_dpkg)
        grep_control = textwrap.dedent(
            """\
            Package: grep
            Maintainer: Darwin Developers <darwin-development@public.lists.apple.com>
            Vendor: GNU Project
            Version: 2.1
            URL: ftp://prep.ai.mit.edu/pub/gnu/grep-2.1.tar.gz
            Description: Get-Regular-Expression-and-Print tool
            Build-Depends: build-base
            """
        )
        with open(os.path.join(grep_dpkg, "control"), "w", encoding="utf-8") as fh:
            fh.write(grep_control)

        errors = validate_controls([os.path.join(grep_dpkg, "control")])
        _assert(errors == [], f"grep validate: {errors}")
        convert_control(os.path.join(grep_dpkg, "control"))
        with open(os.path.join(grep_dir, "apk", "pkginfo"), encoding="utf-8") as fh:
            pkginfo = fh.read()
        expected_grep = textwrap.dedent(
            """\
            pkgname = grep
            pkgver = 2.1
            pkgdesc = Get-Regular-Expression-and-Print tool
            maintainer = Darwin Developers <darwin-development@public.lists.apple.com>
            license = unknown
            url = ftp://prep.ai.mit.edu/pub/gnu/grep-2.1.tar.gz
            makedepends = build-base
            """
        )
        _assert(pkginfo == expected_grep, f"grep pkginfo mismatch:\n{pkginfo!r}")
        _assert(not os.path.isdir(grep_dpkg), "grep dpkg/ should be removed")

        # zlib-like continuation Description
        zlib_dir = os.path.join(tmp, "zlib")
        zlib_dpkg = os.path.join(zlib_dir, "dpkg")
        os.makedirs(zlib_dpkg)
        zlib_control = (
            "Package: zlib\n"
            "Version: 1.1.3\n"
            "Description: Zip library\n"
            " zlib is a general purpose data compression library.  All the\n"
            " code is thread safe.\n"
        )
        with open(os.path.join(zlib_dpkg, "control"), "w", encoding="utf-8") as fh:
            fh.write(zlib_control)
        convert_control(os.path.join(zlib_dpkg, "control"))
        with open(os.path.join(zlib_dir, "apk", "pkginfo"), encoding="utf-8") as fh:
            zlib_pkginfo = fh.read()
        _assert(
            "pkgdesc = Zip library zlib is a general purpose data compression library.  All the code is thread safe.\n"
            in zlib_pkginfo,
            f"zlib pkgdesc fold wrong:\n{zlib_pkginfo!r}",
        )

        # Architecture present vs omitted
        arch_dir = os.path.join(tmp, "drv")
        arch_dpkg = os.path.join(arch_dir, "dpkg")
        os.makedirs(arch_dpkg)
        with open(os.path.join(arch_dpkg, "control"), "w", encoding="utf-8") as fh:
            fh.write(
                "Package: drv\nVersion: 1\nArchitecture: i386\nDescription: d\n"
            )
        convert_control(os.path.join(arch_dpkg, "control"))
        with open(os.path.join(arch_dir, "apk", "pkginfo"), encoding="utf-8") as fh:
            arch_pkginfo = fh.read()
        _assert("arch = i386\n" in arch_pkginfo, arch_pkginfo)

        noarch_dir = os.path.join(tmp, "noarch")
        noarch_dpkg = os.path.join(noarch_dir, "dpkg")
        os.makedirs(noarch_dpkg)
        with open(os.path.join(noarch_dpkg, "control"), "w", encoding="utf-8") as fh:
            fh.write("Package: p\nVersion: 1\nDescription: d\n")
        convert_control(os.path.join(noarch_dpkg, "control"))
        with open(os.path.join(noarch_dir, "apk", "pkginfo"), encoding="utf-8") as fh:
            noarch_pkginfo = fh.read()
        _assert("arch =" not in noarch_pkginfo, noarch_pkginfo)

        # Vendor/Section/Priority dropped
        drop_dir = os.path.join(tmp, "drop")
        drop_dpkg = os.path.join(drop_dir, "dpkg")
        os.makedirs(drop_dpkg)
        with open(os.path.join(drop_dpkg, "control"), "w", encoding="utf-8") as fh:
            fh.write(
                "Package: x\nVersion: 1\nVendor: V\nSection: S\nPriority: optional\nDescription: d\n"
            )
        convert_control(os.path.join(drop_dpkg, "control"))
        with open(os.path.join(drop_dir, "apk", "pkginfo"), encoding="utf-8") as fh:
            drop_pkginfo = fh.read()
        _assert("Vendor" not in drop_pkginfo, drop_pkginfo)
        _assert("Section" not in drop_pkginfo, drop_pkginfo)
        _assert("Priority" not in drop_pkginfo, drop_pkginfo)

        # collision: existing pkginfo blocks conversion
        coll_dir = os.path.join(tmp, "collision")
        coll_dpkg = os.path.join(coll_dir, "dpkg")
        coll_apk = os.path.join(coll_dir, "apk")
        os.makedirs(coll_dpkg)
        os.makedirs(coll_apk)
        with open(os.path.join(coll_dpkg, "control"), "w", encoding="utf-8") as fh:
            fh.write("Package: c\nVersion: 1\n")
        with open(os.path.join(coll_apk, "pkginfo"), "w", encoding="utf-8") as fh:
            fh.write("pkgname = existing\n")
        coll_errors = validate_controls([os.path.join(coll_dpkg, "control")])
        _assert(coll_errors, "collision should produce errors")
        _assert(os.path.isdir(coll_dpkg), "collision must not delete dpkg/")

        # missing Package or Version -> exit 2, no write/delete
        miss_dir = os.path.join(tmp, "missing")
        miss_dpkg = os.path.join(miss_dir, "dpkg")
        os.makedirs(miss_dpkg)
        miss_control = os.path.join(miss_dpkg, "control")
        with open(miss_control, "w", encoding="utf-8") as fh:
            fh.write("Description: no package\n")
        miss_errors = validate_controls([miss_control])
        _assert(any("missing Package" in e for e in miss_errors), miss_errors)
        _assert(os.path.isdir(miss_dpkg), "missing Package must not delete dpkg/")

        with open(miss_control, "w", encoding="utf-8") as fh:
            fh.write("Package: p\nDescription: no version\n")
        miss_errors2 = validate_controls([miss_control])
        _assert(any("missing Version" in e for e in miss_errors2), miss_errors2)

        # scripts: preinst/postinst copied, conffiles not, dpkg/ removed
        files_dir = os.path.join(tmp, "files-5")
        files_dpkg = os.path.join(files_dir, "dpkg")
        os.makedirs(files_dpkg)
        with open(os.path.join(files_dpkg, "control"), "w", encoding="utf-8") as fh:
            fh.write("Package: files\nVersion: 1\n")
        with open(os.path.join(files_dpkg, "preinst"), "w", encoding="utf-8") as fh:
            fh.write("#!/bin/sh\necho pre\n")
        os.chmod(os.path.join(files_dpkg, "preinst"), 0o755)
        with open(os.path.join(files_dpkg, "postinst"), "w", encoding="utf-8") as fh:
            fh.write("#!/bin/sh\necho post\n")
        os.chmod(os.path.join(files_dpkg, "postinst"), 0o755)
        with open(os.path.join(files_dpkg, "conffiles"), "w", encoding="utf-8") as fh:
            fh.write("/etc/foo\n")
        scripts = convert_control(os.path.join(files_dpkg, "control"))
        _assert(scripts == 2, f"expected 2 scripts, got {scripts}")
        files_apk = os.path.join(files_dir, "apk")
        _assert(os.path.isfile(os.path.join(files_apk, ".pre-install")), "missing .pre-install")
        _assert(os.path.isfile(os.path.join(files_apk, ".post-install")), "missing .post-install")
        _assert(not os.path.isfile(os.path.join(files_apk, "conffiles")), "conffiles copied")
        _assert(not os.path.isdir(files_dpkg), "files dpkg/ should be removed")

    print("self-test: PASS")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Run built-in tests and exit",
    )
    parser.add_argument(
        "--src-root",
        default="src",
        help="Root directory to walk (default: src)",
    )
    args = parser.parse_args(argv)

    if args.self_test:
        try:
            return run_self_test()
        except AssertionError as exc:
            print(f"self-test: FAIL: {exc}", file=sys.stderr)
            return 1

    src_root = args.src_root
    if not os.path.isdir(src_root):
        print(f"error: {src_root} is not a directory", file=sys.stderr)
        return 1
    return run_conversion(src_root)


if __name__ == "__main__":
    sys.exit(main())
