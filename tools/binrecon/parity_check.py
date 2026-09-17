"""Compare a rebuilt driver's strings and text symbols against the reference.

Our guest builds are unstripped, so extras on our side are reported separately
and are not findings by themselves. A reference string or symbol our build
lacks is a finding.
"""

import sys
from pathlib import Path

from binrecon.macho import read_macho

CSTRING_SECTION = "__TEXT,__cstring"
TEXT_SECTION = "__TEXT,__text"


def _cstrings(path):
    document = read_macho(path)
    payload = path.read_bytes()
    for section in document["sections"]:
        if section["name"] == CSTRING_SECTION:
            start = section["offset"]
            raw = payload[start:start + section["size"]]
            return {chunk.decode("latin1") for chunk in raw.split(b"\0") if chunk}
    return set()


def _text_symbols(path):
    document = read_macho(path)
    return {
        symbol["name"]
        for symbol in document["symbols"]
        if symbol["section"] == TEXT_SECTION
    }


def compare(reference, rebuilt):
    reference_strings, rebuilt_strings = _cstrings(reference), _cstrings(rebuilt)
    reference_symbols, rebuilt_symbols = _text_symbols(reference), _text_symbols(rebuilt)
    return {
        "missing_strings": sorted(reference_strings - rebuilt_strings),
        "extra_strings": sorted(rebuilt_strings - reference_strings),
        "missing_symbols": sorted(reference_symbols - rebuilt_symbols),
        "extra_symbols": sorted(rebuilt_symbols - reference_symbols),
    }


def main(argv):
    if len(argv) != 3:
        print("usage: parity_check.py REFERENCE REBUILT", file=sys.stderr)
        return 2
    result = compare(Path(argv[1]), Path(argv[2]))
    for key in ("missing_strings", "missing_symbols", "extra_strings", "extra_symbols"):
        print(f"{key} ({len(result[key])}):")
        for item in result[key]:
            print(f"    {item!r}")
    return 1 if result["missing_strings"] or result["missing_symbols"] else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
