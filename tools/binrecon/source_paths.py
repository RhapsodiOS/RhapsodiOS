"""Resolve a source-tree argument that may name a file or a directory.

The checkers used to walk a directory and silently yield nothing when handed a
file path. A gate built on that reads green while measuring nothing, which is
exactly the failure this module removes: a path that does not exist, or a file
path of the wrong suffix, raises instead of quietly yielding nothing. A
directory containing no matching files is a legitimate empty result and is
left to the caller to handle.

File granularity matters because some drivers' sources share a directory with
other binaries' sources — `IONDRVSupport` is three files out of eleven in
`src/driverkit-3/libDriver/ppc`.
"""

from pathlib import Path


def source_files(path, suffixes, recursive=True):
    """Return the source files named by path, which may be a file or directory.

    `suffixes` is a set such as {".m", ".c"}. Raises ValueError for a missing
    path or a file of the wrong suffix, so a mis-scoped argument cannot pass
    unnoticed. A directory with no matching files returns an empty list.
    """
    root = Path(path)
    if not root.exists():
        raise ValueError(f"{root} does not exist")
    if root.is_file():
        if root.suffix not in suffixes:
            raise ValueError(
                f"{root} is not a source file; expected one of {sorted(suffixes)}"
            )
        return [root]
    walk = root.rglob("*") if recursive else root.glob("*")
    return sorted(p for p in walk if p.suffix in suffixes)
