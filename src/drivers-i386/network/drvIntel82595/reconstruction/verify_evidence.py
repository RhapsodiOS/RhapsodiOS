#!/usr/bin/env python3
"""Validate the driver-specific function partition and its Binrecon evidence."""

import argparse
import hashlib
from pathlib import Path
import sys

from binrecon.identity import identify
from binrecon.ledger import validate_ledger
from binrecon.schema import (
    load_json,
    load_source_map,
    validate_analysis_semantics,
    validate_document,
)


GENERATED = {
    0x4AF8: "+[Intel82595NetworkDriverKernelServerInstance kernelServerInstance]",
    0x4B04: "+[Intel82595NetworkDriverVersion driverKitVersionForIntel82595NetworkDriver]",
}


def verify(analysis_path: Path, source_map_path: Path, ledger_path: Path,
           repo_root: Path, *, final: bool = False, rebuilt_path: Path | None = None) -> str:
    analysis = load_json(analysis_path)
    validate_document("analysis-v1", analysis)
    validate_analysis_semantics(analysis)
    if analysis["input"]["size"] != 64816:
        raise ValueError(f"reference size mismatch: {analysis['input']['size']}")
    if analysis["input"]["sha256"].upper() != "B40292EBBF8CF29922C079487A31F530633B0FC3DC04BB25BF1B9E8887E44684":
        raise ValueError("reference SHA-256 mismatch")

    functions = {item["address"]: item for item in analysis["functions"]}
    if len(functions) != len(analysis["functions"]):
        raise ValueError("duplicate reference function address")
    if len(functions) != 59:
        raise ValueError(f"expected 59 reference functions, found {len(functions)}")
    for address, name in GENERATED.items():
        if address not in functions:
            raise ValueError(f"missing reference function at 0x{address:x}")
        if name not in functions[address]["names"]:
            raise ValueError(f"generated exception identity mismatch at 0x{address:x}")

    source_map = load_source_map(source_map_path, reference_analysis=analysis,
                                 repo_root=repo_root)
    mapped_by_address = {entry["address"]: entry for entry in source_map["mapped"]}
    map_addresses = set(mapped_by_address)
    map_addresses.update(entry["address"] for entry in source_map["unmapped"])
    map_addresses.update(entry["address"] for entry in source_map["duplicate_candidates"])
    map_addresses.update(entry["address"] for entry in source_map["boundary_disputed"])
    missing_map = sorted(set(functions) - map_addresses)
    if missing_map:
        raise ValueError(f"source map missing reference function at 0x{missing_map[0]:x}")
    extra_map = sorted(map_addresses - set(functions))
    if extra_map:
        raise ValueError(f"source map has unknown function at 0x{extra_map[0]:x}")
    if source_map["duplicate_candidates"]:
        raise ValueError("source map has duplicate candidates")
    if source_map["boundary_disputed"]:
        raise ValueError("source map has boundary disputes")
    if any(entry.get("source_path") and not entry.get("source_line")
           for entry in source_map["mapped"]):
        raise ValueError("mapped source location has no line")

    ledger = load_json(ledger_path)
    entries = ledger.get("entries", [])
    ledger_addresses = [entry.get("address") for entry in entries]
    if len(ledger_addresses) != len(set(ledger_addresses)):
        raise ValueError("duplicate ledger address")
    if set(ledger_addresses) != set(functions):
        missing = sorted(set(functions) - set(ledger_addresses))
        if missing:
            raise ValueError(f"ledger missing reference function at 0x{missing[0]:x}")
        extra = sorted(set(ledger_addresses) - set(functions))
        raise ValueError(f"ledger has unknown function at 0x{extra[0]:x}")
    reference = identify(Path(analysis["input"]["path"]))
    rebuilt = identify(rebuilt_path) if rebuilt_path else None
    # Generated accessors have reviewed control flow but no handwritten definition.
    for address, name in GENERATED.items():
        entry = next(item for item in entries if item["address"] == address)
        if entry["status"] != "control-flow-confirmed" or not entry.get("reason"):
            raise ValueError(f"generated exception at 0x{address:x} lacks its reason")
        if entry["names"] != [name]:
            raise ValueError(f"generated exception identity mismatch at 0x{address:x}")
    validate_ledger(ledger, reference, rebuilt)
    for artifact in {item["path"]: item for entry in entries
                     for item in entry["artifacts"]}.values():
        path = analysis_path.parent.parent / artifact["path"]
        digest = hashlib.sha256(path.read_bytes()).hexdigest().upper()
        if digest != artifact["sha256"]:
            raise ValueError(f"evidence hash mismatch: {path}")
    for address, function in functions.items():
        entry = next(item for item in entries if item["address"] == address)
        if entry["size"] != function["size"]:
            raise ValueError(f"ledger size mismatch at 0x{address:x}")
        if set(entry["names"]) != set(function["names"]):
            if address in GENERATED:
                raise ValueError(f"generated exception identity mismatch at 0x{address:x}")
            raise ValueError(f"ledger name mismatch at 0x{address:x}")

    handwritten = set(functions) - set(GENERATED)
    if {entry["address"] for entry in source_map["unmapped"]} != set(GENERATED):
        raise ValueError("only the two generated accessors may be unmapped")
    for address, entry in mapped_by_address.items():
        reviewed = next(item for item in entries if item["address"] == address)
        if (reviewed["source_path"], reviewed["source_line"]) != (
                entry["source_path"], entry["source_line"]):
            raise ValueError(f"stale ledger source location at 0x{address:x}")
    if final:
        if rebuilt_path is None:
            raise ValueError("--final requires --rebuilt")
        if len(mapped_by_address) != len(handwritten):
            raise ValueError(f"final source map must map 57 handwritten functions, found {len(mapped_by_address)}")
        if set(mapped_by_address) != handwritten:
            raise ValueError("final source map must map every handwritten function and no generated method")
        for address in sorted(handwritten):
            entry = next(item for item in entries if item["address"] == address)
            if entry["status"] not in ("control-flow-confirmed", "assembly-matched"):
                raise ValueError(f"function at 0x{address:x} is not control-flow-confirmed")
            if not entry.get("reviewer") or not entry.get("artifacts"):
                raise ValueError(f"function at 0x{address:x} lacks reviewer/evidence")
        actual = identify(rebuilt_path)
        return (f"PASS: 59 reference functions ({len(handwritten)} handwritten, "
                f"{len(GENERATED)} generated), rebuilt SHA-256 {actual.sha256}")

    return f"PASS: {len(functions)} reference functions; source map has {len(mapped_by_address)} mapped definitions"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--analysis", type=Path, required=True)
    parser.add_argument("--source-map", type=Path, required=True)
    parser.add_argument("--ledger", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--final", action="store_true")
    parser.add_argument("--rebuilt", type=Path)
    args = parser.parse_args(argv)
    try:
        print(verify(args.analysis, args.source_map, args.ledger, args.repo_root,
                     final=args.final, rebuilt_path=args.rebuilt))
    except Exception as error:
        print(f"binrecon evidence: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
