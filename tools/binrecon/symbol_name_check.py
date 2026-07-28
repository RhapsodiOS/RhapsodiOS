"""Check that every hand-written C symbol has a source definition site.

Under the Mach-O ABI the compiler prepends exactly one underscore, so a source
function `changeState` becomes the symbol `_changeState`. A source function
written as `_changeState` becomes `__changeState` and silently fails to match
the reference binary. This checker compares a reference binary's hand-written C
symbols against the definition sites in a source tree.

Presence is established by a definition site, never by an occurrence count.
"""

import argparse
import re
import sys
from pathlib import Path

from binrecon.macho import read_macho

# libgcc helpers linked into the driver rather than written by hand.
COMPILER_RUNTIME = {"__udivdi3", "__umoddi3", "__divdi3", "__moddi3"}

_DEFINITION = re.compile(r"^(?:static\s+)?[A-Za-z_][\w \t\*]*?([A-Za-z_]\w*)\s*\(")


def source_definitions(source_dir):
    """Return the C function names defined in .m and .c files under source_dir."""
    names = set()
    for path in sorted(Path(source_dir).rglob("*")):
        if path.suffix not in (".m", ".c"):
            continue
        lines = path.read_text(encoding="utf-8", errors="replace").split("\n")
        for index, line in enumerate(lines):
            match = _DEFINITION.match(line)
            if not match or ";" in line:
                continue
            if "{" in "".join(lines[index:index + 4]):
                names.add(match.group(1))
    return names


def hand_written_c_symbols(document):
    """Return reference __text symbols that are hand-written C."""
    return [
        symbol["name"]
        for symbol in document["symbols"]
        if symbol.get("section") == "__TEXT,__text"
        and not symbol["name"].startswith(("-[", "+["))
        and symbol["name"] not in COMPILER_RUNTIME
    ]


def missing_definitions(symbols, definitions):
    """Return symbols with no definition site named symbol-minus-one-underscore."""
    missing = []
    for symbol in symbols:
        if symbol in COMPILER_RUNTIME or symbol.startswith(("-[", "+[")):
            continue
        if symbol[1:] not in definitions:
            missing.append(symbol)
    return missing


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True)
    parser.add_argument("--source-dir", required=True, action="append")
    arguments = parser.parse_args(argv)

    definitions = set()
    for source_dir in arguments.source_dir:
        definitions |= source_definitions(source_dir)

    symbols = hand_written_c_symbols(read_macho(Path(arguments.binary)))
    missing = missing_definitions(symbols, definitions)

    print(f"hand-written C symbols: {len(symbols)}")
    print(f"missing definitions   : {len(missing)}")
    for name in missing:
        print(f"  {name}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
