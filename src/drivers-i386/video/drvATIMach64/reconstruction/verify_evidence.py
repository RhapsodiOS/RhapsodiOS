#!/usr/bin/env python3
"""Fail-closed identity, inventory, source-map and ledger checks for drvATIMach64."""

import argparse
import json
from pathlib import Path
import sys

REPO_ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(REPO_ROOT / "tools/binrecon"))

from binrecon.identity import identify
from binrecon.schema import load_json, load_source_map, validate_analysis_semantics, validate_document


REFERENCE_SHA256 = "AA9884B8F9F68DB733237241D88FCC1FF252A59E9B0EA1CD029695F37465EA3C"
REFERENCE_SIZE = 62632
GENERATED = {
    (0x19EC, "+[ATIMach64DisplayDriverKernelServerInstance kernelServerInstance]"),
    (0x19F8, "+[ATIMach64DisplayDriverVersion driverKitVersionForATIMach64DisplayDriver]"),
}
ASSEMBLY = {(0x26E0, "__bios16"), (0x27B8, "__ATIbios32")}


class EvidenceError(ValueError):
    pass


def corrected_assembly_ranges():
    """Return IDA function bounds, with exclusive end addresses."""
    return [(0x26E0, 0x2755, "__bios16"), (0x27B8, 0x2883, "__ATIbios32")]


def validate_reference_identity(identity, expected_sha256=REFERENCE_SHA256,
                                expected_size=REFERENCE_SIZE):
    if (not isinstance(identity, dict) or identity.get("sha256", "").upper() != expected_sha256
            or identity.get("size") != expected_size):
        raise EvidenceError("reference identity does not match the approved binary")


def validate_inventory(records):
    if not isinstance(records, list):
        raise EvidenceError("routine inventory is not a list")
    addresses = [item.get("address") for item in records]
    if len(addresses) != len(set(addresses)):
        raise EvidenceError("duplicate routine address")
    pairs = {(item.get("address"), item.get("name")) for item in records}
    if not any(address == 0 and name == "-[ATI initFromDeviceDescription:]"
               for address, name in pairs):
        raise EvidenceError("initializer at address zero is missing")
    if not ASSEMBLY.issubset(pairs):
        raise EvidenceError("assembly entries are missing")
    generated = {(item.get("address"), item.get("name")) for item in records
                 if item.get("kind") == "generated"}
    if generated != GENERATED:
        raise EvidenceError("generated exceptions do not match the two exact runtime methods")
    if len(records) != 54:
        raise EvidenceError(f"routine inventory has {len(records)} entries; expected 54")
    if sum(item.get("kind") == "handwritten" for item in records) != 52:
        raise EvidenceError("handwritten routine count is not 52")


def validate_source_location(path, line, repo_root):
    if not isinstance(path, str) or Path(path).is_absolute() or ".." in Path(path).parts:
        raise EvidenceError("source path is not repository-relative")
    source = Path(repo_root) / path
    if not source.is_file():
        raise EvidenceError(f"source path does not exist: {path}")
    if type(line) is not int or line < 1 or line > len(source.read_text(encoding="utf-8").splitlines()):
        raise EvidenceError(f"source line is out of bounds: {path}:{line}")


def validate_final_evidence(records, source_map, ledger, rebuilt_sha256,
                            rebuilt_analysis_sha256, repo_root):
    """Require a complete, current review and a source location for every handwritten routine."""
    validate_inventory(records)
    rebuilt_sha256 = rebuilt_sha256.upper()
    if rebuilt_analysis_sha256.upper() != rebuilt_sha256:
        raise EvidenceError("rebuilt analysis identity is stale")
    if ledger.get("rebuilt_sha256", "").upper() != rebuilt_sha256:
        raise EvidenceError("ledger rebuilt identity is stale")
    if ledger.get("reference_sha256", "").upper() != REFERENCE_SHA256:
        raise EvidenceError("ledger reference identity is stale")
    if source_map.get("reference_sha256", "").upper() != REFERENCE_SHA256:
        raise EvidenceError("source map reference identity is stale")

    expected_generated = GENERATED
    expected_keys = {(item["address"], item["name"]) for item in records}
    ledger_keys = [(entry["address"], name) for entry in ledger["entries"]
                   for name in entry["names"]]
    if len(ledger_keys) != len(set(ledger_keys)) or set(ledger_keys) != expected_keys:
        raise EvidenceError("final ledger does not cover the exact 54-routine inventory")
    if len(ledger["entries"]) != 54:
        raise EvidenceError("final ledger does not cover all 54 routines")
    for entry in ledger["entries"]:
        keyset = {(entry["address"], name) for name in entry["names"]}
        if entry["status"] == "unexamined" and not keyset.issubset(expected_generated):
            raise EvidenceError("final ledger contains an unexamined handwritten entry")

    mapped = source_map["mapped"]
    unmapped = source_map["unmapped"]
    mapped_keys = [(entry["address"], name) for entry in mapped
                   for name in entry["reference_names"]]
    unmapped_keys = {(entry["address"], name) for entry in unmapped
                     for name in entry["reference_names"]}
    expected_handwritten = expected_keys - expected_generated
    if len(mapped) != 52 or len(mapped_keys) != len(set(mapped_keys)) or \
            set(mapped_keys) != expected_handwritten:
        raise EvidenceError("source map does not map exactly 52 handwritten routines")
    if unmapped_keys != expected_generated or len(unmapped) != 2:
        raise EvidenceError("source map generated exceptions do not match the two exact runtime methods")
    if source_map["duplicate_candidates"] or source_map["boundary_disputed"]:
        raise EvidenceError("final source map has duplicate or disputed routine mappings")

    ledger_by_key = {(entry["address"], name): entry for entry in ledger["entries"]
                     for name in entry["names"]}
    source_by_key = {(entry["address"], name): entry for entry in mapped
                     for name in entry["reference_names"]}
    for key, source in source_by_key.items():
        validate_source_location(source["source_path"], source["source_line"], repo_root)
    for address, name in ASSEMBLY:
        source = source_by_key[(address, name)]
        if not source["source_path"].endswith("/ATIbios.s"):
            raise EvidenceError(f"assembly source label is missing for {name}")
        lines = (Path(repo_root) / source["source_path"]).read_text(
            encoding="utf-8", errors="replace").splitlines()
        if source["source_line"] > len(lines) or \
                lines[source["source_line"] - 1].strip() != f"{name}:":
            raise EvidenceError(f"assembly source label is missing for {name}")

    for key, source in source_by_key.items():
        ledger_entry = ledger_by_key[key]
        if (ledger_entry["source_path"], ledger_entry["source_line"]) != \
                (source["source_path"], source["source_line"]):
            raise EvidenceError("ledger source location does not match the final source map")

    for address, name in expected_generated:
        entry = ledger_by_key[(address, name)]
        if entry["source_path"] is not None or entry["source_line"] is not None:
            raise EvidenceError("generated exceptions must remain source-less")


def _analysis_inventory(analysis):
    output = []
    for function in analysis.get("functions", []):
        for name in function.get("names", []):
            kind = "generated" if (function["address"], name) in GENERATED else "handwritten"
            output.append({"address": function["address"], "name": name, "kind": kind,
                           "size": function["size"]})
    return output


def verify(args):
    repo_root = Path(args.repo_root).resolve(strict=True)
    binary = Path(args.binary).resolve(strict=True)
    identity = identify(binary)
    identity_doc = {"sha256": identity.sha256, "size": identity.size}
    validate_reference_identity(identity_doc)
    analysis = load_json(Path(args.analysis))
    validate_document("analysis-v1", analysis)
    validate_analysis_semantics(analysis)
    validate_reference_identity(analysis["input"])
    records = _analysis_inventory(analysis)
    if args.phase == "baseline":
        validate_inventory(records)
    source_map = load_source_map(Path(args.source_map), reference_analysis=analysis,
                                 repo_root=repo_root)
    ledger = load_json(Path(args.ledger))
    validate_document("ledger-v1", ledger)
    if ledger["reference_sha256"] != REFERENCE_SHA256:
        raise EvidenceError("ledger reference identity is stale")
    if args.phase == "final":
        if not args.rebuilt_analysis or not args.rebuilt:
            raise EvidenceError("final phase requires rebuilt analysis and binary")
        rebuilt = identify(Path(args.rebuilt).resolve(strict=True))
        rebuilt_analysis = load_json(Path(args.rebuilt_analysis))
        validate_document("analysis-v1", rebuilt_analysis)
        validate_analysis_semantics(rebuilt_analysis)
        if rebuilt_analysis["input"]["sha256"].upper() != rebuilt.sha256:
            raise EvidenceError("rebuilt analysis identity is stale")
        validate_final_evidence(
            records, source_map, ledger, rebuilt.sha256,
            rebuilt_analysis["input"]["sha256"], repo_root
        )
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=("baseline", "final"), required=True)
    parser.add_argument("--analysis", required=True)
    parser.add_argument("--binary", required=True)
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--source-map", required=True)
    parser.add_argument("--ledger", required=True)
    parser.add_argument("--rebuilt-analysis")
    parser.add_argument("--rebuilt")
    args = parser.parse_args(argv)
    try:
        verify(args)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"evidence verification failed: {error}", file=sys.stderr)
        return 1
    print(f"drvATIMach64 evidence verified ({args.phase})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
