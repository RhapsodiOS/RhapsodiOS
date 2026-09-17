"""Drop analysis-v1 functions wholly contained within another function.

Some analyzers split a routine into internal chunks that get their own
idautils.Functions() entry but lie entirely inside a larger entry -- for
example VGA_reloc's _emu486, whose per-opcode handlers are basic blocks of
the interpreter rather than independent functions. Filtering on "named vs.
unnamed" alone gets this wrong: VGA_psdrvr's 16 unnamed entries are ordinary
static C functions that stand on their own, not fragments of a named
routine, and dropping them loses 40% of that binary's __text.

The right rule is containment: a function is dropped only if another
function's extent fully covers it. A surviving function that IDA left
unnamed is given a synthesized sub_<ADDRESS> name, since source-map-v1
requires every function to have at least one name. Everything else in the
document is left exactly as it was, including input.sha256.
"""

import json
import sys
from pathlib import Path


def _contains(outer: dict, inner: dict) -> bool:
    """Return whether outer's extent fully covers inner's."""
    return (
        outer["address"] <= inner["address"]
        and inner["address"] + inner["size"] <= outer["address"] + outer["size"]
    )


def _is_contained_in_another(function: dict, functions: list) -> bool:
    for other in functions:
        if other is function:
            continue
        if _contains(other, function):
            return True
    return False


def filter_contained_fragments(document: dict) -> dict:
    """Return a copy of an analysis-v1 document with contained functions dropped.

    Surviving functions with no name are given a synthesized sub_<ADDRESS>
    name, address formatted as uppercase hexadecimal.
    """
    functions = document["functions"]
    survivors = [
        function for function in functions
        if not _is_contained_in_another(function, functions)
    ]

    named_survivors = []
    for function in survivors:
        if function["names"]:
            named_survivors.append(function)
        else:
            named_survivors.append(
                {**function, "names": [f"sub_{function['address']:08X}"]}
            )

    filtered = dict(document)
    filtered["functions"] = named_survivors
    return filtered


def main(argv):
    if len(argv) != 3:
        print("usage: filter_contained_fragments.py INPUT OUTPUT", file=sys.stderr)
        return 2
    document = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
    filtered = filter_contained_fragments(document)
    Path(argv[2]).write_text(
        json.dumps(filtered, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
