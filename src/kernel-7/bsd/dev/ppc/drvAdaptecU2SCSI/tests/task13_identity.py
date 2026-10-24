"""Explicit, canonical input closure for the API supplementary executor."""

import hashlib
import json
import subprocess
from pathlib import Path

DRIVER = Path("src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI")
NATIVE_INPUTS = ("AdaptecU2CHIMTransport.c", "AdaptecU2CHIMAPI.c",
                 "AdaptecU2CHIMTypes.h", "AdaptecU2CHIM.h",
                 "AdaptecU2CHIMPrivate.h", "OSMFunctions.h", "AdaptecU2SCSI.h", "AdaptecU2SCSIPrivate.h")
EXECUTION_INPUTS = [DRIVER/"tests"/name for name in (
    "task13_execute.py", "task13_identity.py", "task13_native.py", "task13_link.py", "task13_inputs.py",
    "task11_native.py", "task13_stack.py", "task13-stack-cases.json", "task13-stack-mapping.json",
    "task13-cases.json", "task13-context-cases.json", "task13-contracts.json",
    "task13-getter.json", "ppc_cases.py", "reference.py")]
EXECUTION_INPUTS += [DRIVER/name for name in NATIVE_INPUTS]
EXECUTION_INPUTS += [DRIVER/"reconstruction/inventory.md", Path("tools/binrecon/source_paths.py")]
EXECUTION_INPUTS += [Path("tools/binrecon/binrecon")/(name+".py") for name in
                    ("__init__", "identity", "macho", "objc_abi", "source_map", "schema", "arch")]


def sha(raw):
    return hashlib.sha256(raw).hexdigest().upper()


def load(path):
    return json.loads(path.read_text())


def git(repo, revision, relative):
    return subprocess.check_output(["git", "show", revision+":"+relative.as_posix()], cwd=repo)


def canonical(raw, path):
    raw = raw.replace(b"\r\n", b"\n")
    if path.name == "inventory.md":
        raw = raw.split(b"<!-- functions:start -->")[1].split(b"<!-- functions:end -->")[0]
    return raw


def closure(repo, revision, preflight=False):
    result = {}
    for path in EXECUTION_INPUTS:
        raw = (repo/path).read_bytes()
        current = canonical(raw, path)
        if not preflight:
            blob = canonical(git(repo, revision, path), path)
            if blob != current:
                raise ValueError("uncommitted API execution input: "+path.as_posix())
        result[path.as_posix()] = {"git_blob_sha256": sha(current), "working_sha256": sha(raw)}
    return result
