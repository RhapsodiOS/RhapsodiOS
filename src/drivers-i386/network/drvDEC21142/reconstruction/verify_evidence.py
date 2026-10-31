#!/usr/bin/env python3
"""Validate the pinned IDA partition and the authored source map."""

import argparse
from pathlib import Path
import sys

from binrecon.schema import (
    load_json,
    load_source_map,
    validate_analysis_semantics,
    validate_document,
)


REFERENCE_SHA256 = "B8FA440177799B9510A0AD5ED5C3C71DA3E9D146F561CE5439F84E2D65B1C7F9"
REFERENCE_SIZE = 45728
FUNCTION_COUNT = 50
GENERATED_FUNCTIONS = {
    0x2BDC: "+[DEC21142NetworkKernelServerInstance kernelServerInstance]",
    0x2BE8: "+[DEC21142NetworkVersion driverKitVersionForDEC21142Network]",
}


def verify(analysis_path: Path, source_map_path: Path, repo_root: Path) -> str:
    analysis = load_json(analysis_path)
    validate_document("analysis-v1", analysis)
    validate_analysis_semantics(analysis)
    if analysis["input"]["size"] != REFERENCE_SIZE:
        raise ValueError("reference binary size mismatch")
    if analysis["input"]["sha256"].upper() != REFERENCE_SHA256:
        raise ValueError("reference binary SHA-256 mismatch")

    functions = {item["address"]: item for item in analysis["functions"]}
    if len(functions) != FUNCTION_COUNT:
        raise ValueError(f"expected {FUNCTION_COUNT} IDA functions, found {len(functions)}")

    source_map = load_source_map(
        source_map_path, reference_analysis=analysis, repo_root=repo_root
    )
    mapped = {item["address"]: item for item in source_map["mapped"]}
    unmapped = {item["address"]: item for item in source_map["unmapped"]}
    if set(mapped) & set(unmapped) or set(mapped) | set(unmapped) != set(functions):
        raise ValueError("source map does not account for the complete IDA partition")
    if len(mapped) != FUNCTION_COUNT - len(GENERATED_FUNCTIONS):
        raise ValueError(f"expected {FUNCTION_COUNT - len(GENERATED_FUNCTIONS)} authored mappings")
    if set(unmapped) != set(GENERATED_FUNCTIONS):
        raise ValueError("unmapped entries differ from the two build-generated class methods")
    for address, name in GENERATED_FUNCTIONS.items():
        if unmapped[address]["reference_names"] != [name]:
            raise ValueError(f"unexpected generated method name at {address:#x}")
    if source_map["duplicate_candidates"] or source_map["boundary_disputed"]:
        raise ValueError("source map contains duplicate or disputed boundaries")
    return (
        f"PASS: {len(mapped)} authored functions mapped, 2 build-generated methods accounted for; "
        "reference identity verified"
    )


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--analysis", type=Path, required=True)
    parser.add_argument("--source-map", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        print(verify(args.analysis, args.source_map, args.repo_root))
    except Exception as error:
        print(f"binrecon evidence: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
