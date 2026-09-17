#!/usr/bin/env python3
"""Divergence check for the packaged PowerPC loadable-driver sources.

Compares each driver packaged under src/drivers-ppc against its
src/kernel-7/bsd/dev/ppc origin, file-for-file, by SHA-256. Prints
"no divergences" and exits 0 when every packaged source matches its
origin; otherwise reports what differs and exits non-zero.
"""
import hashlib
import pathlib
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
KERNEL_PPC = REPO_ROOT / "src" / "kernel-7" / "bsd" / "dev" / "ppc"
DRIVERS_PPC = REPO_ROOT / "src" / "drivers-ppc"

# (project dir under src/drivers-ppc, project name, origin dir under kernel-7 ppc)
PROJECTS = [
    ("input/drvPPCCuda", "PPCCuda", "drvCuda"),
    ("input/drvPPCPMU", "PPCPMU", "drvPMU"),
    ("bus/drvPPCOHare", "PPCOHare", "drvOHare"),
    ("network/drvPPCBMac", "PPCBMac", "drvBMacEnet"),
    ("network/drvPPCMace", "PPCMace", "drvMaceEnet"),
    ("network/drvPPCDec21040", "PPCDec21040", "drvDECchip21040"),
    ("scsi/drvPPC53c96", "PPC53c96", "drvApple96_SCSI"),
    ("scsi/drvPPCMesh", "PPCMesh", "drvAppleMesh_SCSI"),
    ("scsi/drvPPCSym8xx", "PPCSym8xx", "drvSymbios8xx"),
]

SOURCE_SUFFIXES = {".h", ".m", ".c", ".lis", ".ss"}


def hash_files(directory: pathlib.Path, suffixes=None) -> dict:
    """Map filename -> SHA-256 hex digest for top-level files in directory."""
    result = {}
    for f in directory.iterdir():
        if not f.is_file():
            continue
        if suffixes is not None and f.suffix not in suffixes:
            continue
        result[f.name] = hashlib.sha256(f.read_bytes()).hexdigest()
    return result


def diff_trees(origin_files: dict, package_files: dict):
    """Compare two {filename: hash} maps.

    Returns (differing, missing_from_package, missing_from_origin), each a
    sorted list of filenames.
    """
    differing = sorted(
        name
        for name in origin_files.keys() & package_files.keys()
        if origin_files[name] != package_files[name]
    )
    missing_from_package = sorted(origin_files.keys() - package_files.keys())
    missing_from_origin = sorted(package_files.keys() - origin_files.keys())
    return differing, missing_from_package, missing_from_origin


def check_project(project_dir, proj_name, origin_dir):
    """Return a list of divergence report lines for one project ([] if clean)."""
    package = DRIVERS_PPC / project_dir / f"{proj_name}.drvproj" / f"{proj_name}.lksproj"
    origin = KERNEL_PPC / origin_dir
    label = f"{project_dir} ({origin_dir})"

    if not package.is_dir():
        return [f"{label}: missing entirely (no {package})"]

    origin_files = hash_files(origin)
    package_files = hash_files(package, SOURCE_SUFFIXES)
    differing, missing_from_package, missing_from_origin = diff_trees(
        origin_files, package_files
    )

    lines = []
    if differing:
        lines.append(f"{label}: differing content: {differing}")
    if missing_from_package:
        lines.append(f"{label}: missing from package: {missing_from_package}")
    if missing_from_origin:
        lines.append(
            f"{label}: present only in package (not in origin): {missing_from_origin}"
        )
    return lines


def main():
    problems = []
    for project_dir, proj_name, origin_dir in PROJECTS:
        problems.extend(check_project(project_dir, proj_name, origin_dir))

    if problems:
        for line in problems:
            print(line)
        return 1

    print("no divergences")
    return 0


if __name__ == "__main__":
    sys.exit(main())
