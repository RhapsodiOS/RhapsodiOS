"""Seed a ledger-v1 document from a reference source map.

`binrecon analyze --ledger` builds its entries from the analyzer's raw function
list, which for a PowerPC driver includes every build-generated jump island under
an IDA `sub_XXXX` name -- 206 entries for SCSIServer, 138 of them glue. A
reconstruction ledger should carry one entry per function the source map accounts
for, so this seeds from the map instead: mapped entries keep their source path
and line, every other bucket carries nulls, and every entry starts unexamined.
"""

import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent))

from binrecon.identity import identify
from binrecon.ledger import new_ledger, LedgerError

_BUCKETS = ("mapped", "unmapped", "duplicate_candidates", "boundary_disputed")
# Only IDA supports PowerPC; the Ghidra and angr adapters reject a ppc profile.
_AGREEMENT = {
    "analyzers": ["IDA"],
    "status": "agreed",
    "reasons": ["IDA is the only analyzer that supports PowerPC"],
}


def seed_entries(source_map: dict) -> list[dict]:
    """Return sorted ledger entries for every function the map accounts for."""
    entries = []
    for bucket in _BUCKETS:
        for item in source_map.get(bucket, ()):
            entries.append({
                "address": item["address"],
                "size": item["size"],
                "names": list(item["reference_names"]),
                "source_path": item.get("source_path"),
                "source_line": item.get("source_line"),
                "status": "unexamined",
                "analyzer_agreement": dict(_AGREEMENT),
                "artifacts": [],
                "reason": None,
                "reviewer": None,
            })
    entries.sort(key=lambda entry: (entry["address"], entry["size"]))
    return entries


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if len(argv) != 3:
        print("usage: seed_ledger.py SOURCE_MAP REFERENCE_BINARY OUTPUT", file=sys.stderr)
        return 2
    source_map = json.loads(Path(argv[0]).read_text(encoding="utf-8"))
    reference = identify(Path(argv[1]))
    if str(source_map["reference_sha256"]).upper() != reference.sha256:
        print("source map reference_sha256 does not match the binary", file=sys.stderr)
        return 1
    try:
        document = new_ledger(reference, None, seed_entries(source_map))
    except LedgerError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    Path(argv[2]).write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"{len(document['entries'])} entries")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
