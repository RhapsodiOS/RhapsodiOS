"""Validate that a reconstruction ledger accounts for the exact IDA reference."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys


_STATUS_ORDER = {
    "unexamined": 0,
    "signature-confirmed": 1,
    "control-flow-confirmed": 2,
    "assembly-matched": 3,
}
_GENERATED = {0x7780: "+[BusLogicFPSCSIKernelServerInstance kernelServerInstance]",
              0x778C: "+[BusLogicFPSCSIVersion driverKitVersionForBusLogicFPSCSI]"}


def _load_json(path: Path):
    with path.open("r", encoding="utf-8-sig") as stream:
        return json.load(stream)


def validate_bundle(analysis_path, source_map_path, ledger_path, repo_root,
                    *, final=False, rebuilt_path=None):
    """Validate identities, full partition coverage, and (in final mode) evidence."""
    analysis_path = Path(analysis_path).resolve(strict=True)
    source_map_path = Path(source_map_path).resolve(strict=True)
    ledger_path = Path(ledger_path).resolve(strict=True)
    repo_root = Path(repo_root).resolve(strict=True)
    sys.path.insert(0, str(repo_root / "tools/binrecon"))

    from binrecon.identity import InputIdentity, identify
    from binrecon.ledger import load_ledger
    from binrecon.schema import (load_source_map, validate_analysis_semantics,
                                 validate_document)

    analysis = _load_json(analysis_path)
    validate_document("analysis-v1", analysis)
    validate_analysis_semantics(analysis)
    ref = analysis["input"]
    reference = InputIdentity(analysis_path, ref["size"], ref["sha256"])
    source_map = load_source_map(source_map_path, reference_analysis=analysis,
                                 repo_root=repo_root)
    rebuilt = identify(Path(rebuilt_path)) if rebuilt_path is not None else None
    ledger, _ = load_ledger(ledger_path, reference, rebuilt)

    expected = {}
    for function in analysis["functions"]:
        key = (function["address"], function["size"])
        expected[key] = tuple(function["names"])
    mapped = {}
    for bucket in ("mapped", "unmapped", "duplicate_candidates", "boundary_disputed"):
        for item in source_map[bucket]:
            key = (item["address"], item["size"])
            if key in mapped:
                raise ValueError(f"duplicate source-map function at 0x{key[0]:x}")
            mapped[key] = tuple(item["reference_names"])
    if mapped != expected:
        raise ValueError("source map does not partition the IDA function inventory")

    entries = {}
    for entry in ledger["entries"]:
        key = (entry["address"], entry["size"])
        if key in entries:
            raise ValueError(f"duplicate ledger function at 0x{key[0]:x}")
        entries[key] = entry
    if entries.keys() != expected.keys():
        missing = expected.keys() - entries.keys()
        extra = entries.keys() - expected.keys()
        raise ValueError(f"ledger partition mismatch: {len(missing)} missing, {len(extra)} extra")
    for key, names in expected.items():
        if tuple(entries[key]["names"]) != names:
            raise ValueError(f"ledger names differ from IDA at 0x{key[0]:x}")

    result = {"functions": len(entries), "reference_sha256": ref["sha256"],
              "mapped": len(source_map["mapped"]),
              "unmapped": len(source_map["unmapped"]), "final": bool(final)}
    if not final:
        return result
    if rebuilt is None:
        raise ValueError("final validation requires --rebuilt")
    if len(entries) != 123 or len(_GENERATED) != 2:
        raise ValueError("final validation requires the 123-function reference partition")
    sites = set()
    nongenerated = 0
    for (address, _size), entry in entries.items():
        is_generated = entry["analyzer_agreement"].get("generated") is True
        if address in _GENERATED:
            if not is_generated:
                raise ValueError(f"generated exception at 0x{address:x} is not marked")
            continue
        if is_generated:
            raise ValueError(f"unexpected generated exception at 0x{address:x}")
        nongenerated += 1
        if entry["source_path"] is None or entry["source_line"] is None:
            raise ValueError(f"function at 0x{address:x} has no source site")
        if entry["status"] not in _STATUS_ORDER or _STATUS_ORDER[entry["status"]] < 2:
            raise ValueError(f"function at 0x{address:x} lacks control-flow evidence")
        site = (entry["source_path"], entry["source_line"])
        if site in sites:
            raise ValueError(f"duplicate source site {site[0]}:{site[1]}")
        sites.add(site)
        source = (repo_root / site[0]).resolve(strict=True)
        if repo_root not in source.parents:
            raise ValueError(f"source site escapes repository: {site[0]}")
        lines = source.read_text(encoding="utf-8-sig", errors="replace").splitlines()
        if site[1] > len(lines) or not lines[site[1] - 1].strip():
            raise ValueError(f"source site is missing or blank: {site[0]}:{site[1]}")
        if not entry["artifacts"]:
            raise ValueError(f"function at 0x{address:x} has no binary evidence artifact")
        for artifact in entry["artifacts"]:
            artifact_path = (repo_root / artifact["path"]).resolve(strict=True)
            if repo_root not in artifact_path.parents:
                raise ValueError(f"evidence artifact escapes repository: {artifact['path']}")
            digest = hashlib.sha256(artifact_path.read_bytes()).hexdigest().upper()
            if digest != artifact["sha256"]:
                raise ValueError(f"evidence hash mismatch: {artifact['path']}")
    if nongenerated != 121:
        raise ValueError(f"expected 121 reconstructed functions, found {nongenerated}")
    result["reviewed_source_sites"] = len(sites)
    result["rebuilt_sha256"] = rebuilt.sha256
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--analysis", required=True)
    parser.add_argument("--source-map", required=True)
    parser.add_argument("--ledger", required=True)
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--final", action="store_true")
    parser.add_argument("--rebuilt")
    args = parser.parse_args(argv)
    try:
        result = validate_bundle(args.analysis, args.source_map, args.ledger,
                                 args.repo_root, final=args.final,
                                 rebuilt_path=args.rebuilt)
    except Exception as error:
        print(f"evidence validation failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())



