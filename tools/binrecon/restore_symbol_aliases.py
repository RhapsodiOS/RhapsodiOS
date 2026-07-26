"""Restore symbol-table aliases an analyzer's one-name-per-address model dropped.

Some analyzers permit only one name per address, so when a Mach-O binary's
symbol table records two names for the same routine, the analyzer silently
keeps one and drops the other. This utility restores the missing names by
comparing an analysis-v1 document's function names against the real
__TEXT,__text symbol table of the binary it describes (read fresh via
binrecon.macho.read_macho, not from the document's own "symbols" field,
which an analyzer populates from its own one-name-per-address view and so
can be missing the same aliases). It produces a copy of the document with
every symbol-table alias present, names in each function sorted for a
stable order, and every other field -- including input.sha256 -- left
exactly as it was.
"""

import json
import sys
from pathlib import Path

from binrecon.macho import read_macho

TEXT_SECTION = "__TEXT,__text"


def _text_aliases(macho_document: dict) -> dict:
    """Map each __TEXT,__text address to the names its symbol table records."""
    index: dict[int, set] = {}
    for symbol in macho_document["symbols"]:
        if symbol["section"] == TEXT_SECTION:
            index.setdefault(symbol["address"], set()).add(symbol["name"])
    return index


def restore_symbol_aliases(document: dict, macho_document: dict) -> dict:
    """Return a copy of an analysis-v1 document with symbol-table aliases restored."""
    aliases = _text_aliases(macho_document)
    restored = dict(document)
    restored["functions"] = [
        {
            **function,
            "names": sorted(set(function["names"]) | aliases.get(function["address"], set())),
        }
        for function in document["functions"]
    ]
    return restored


def main(argv):
    if len(argv) != 4:
        print("usage: restore_symbol_aliases.py ANALYSIS BINARY OUTPUT", file=sys.stderr)
        return 2
    document = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
    macho_document = read_macho(Path(argv[2]))
    restored = restore_symbol_aliases(document, macho_document)
    Path(argv[3]).write_text(
        json.dumps(restored, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
