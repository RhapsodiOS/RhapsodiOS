#!/usr/bin/env python3
"""Validate the pinned IDA function partition and its source map."""

import argparse
from pathlib import Path
import sys

from binrecon.schema import (
    load_json,
    load_source_map,
    validate_analysis_semantics,
    validate_document,
)


REFERENCE_SHA256 = "2BF1F8563BABD7CDC4C7BA625E9963033A6B56BFE237A43308707944228AACE8"
REFERENCE_SIZE = 52800
FUNCTION_COUNT = 68


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
    if set(mapped) != set(functions):
        raise ValueError("source map does not cover the complete IDA function partition")
    if source_map["unmapped"] or source_map["duplicate_candidates"] or source_map["boundary_disputed"]:
        raise ValueError("source map contains unresolved entries")
    return f"PASS: {FUNCTION_COUNT} IDA functions mapped to source; reference identity verified"


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
