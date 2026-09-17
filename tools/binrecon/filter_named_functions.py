"""Drop unnamed functions from an analysis-v1 document.

IDA's function-boundary heuristics can split a single named routine into
internal chunks it never assigns a name to -- for example VGA_reloc's
_emu486, whose per-opcode handlers each get their own idautils.Functions()
entry but no idautils.Names() entry. The source-map tooling requires every
function in a reference analysis to be named, so this utility produces a
copy of the document with the unnamed entries removed and every other field
left exactly as it was, including input.sha256.
"""

import json
import sys
from pathlib import Path


def filter_named_functions(document: dict) -> dict:
    """Return a copy of an analysis-v1 document keeping only named functions."""
    filtered = dict(document)
    filtered["functions"] = [
        function for function in document["functions"] if function["names"]
    ]
    return filtered


def main(argv):
    if len(argv) != 3:
        print("usage: filter_named_functions.py INPUT OUTPUT", file=sys.stderr)
        return 2
    document = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
    filtered = filter_named_functions(document)
    Path(argv[2]).write_text(
        json.dumps(filtered, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
