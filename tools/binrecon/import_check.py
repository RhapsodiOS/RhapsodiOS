"""Compare a rebuilt driver's kernel imports against the reference's.

A reference import our build never calls means we reached for a different kernel
API than Apple did, which neither string nor symbol parity detects. Extras on our
side are not reported: an unstripped build pulls in far more than it uses.
"""

import sys
from pathlib import Path

from binrecon.macho import read_macho


def imports(path):
    document = read_macho(path)
    return {symbol["name"] for symbol in document["symbols"]
            if symbol["section"] is None}


def main(argv):
    if len(argv) != 3:
        print("usage: import_check.py REFERENCE REBUILT", file=sys.stderr)
        return 2

    reference = imports(Path(argv[1]))
    rebuilt = imports(Path(argv[2]))
    missing = sorted(reference - rebuilt)

    print("reference imports: %d" % len(reference))
    print("rebuilt imports:   %d" % len(rebuilt))
    print("\nmissing_imports (%d):" % len(missing))
    for name in missing:
        print("    %s" % name)
    return 0 if not missing else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
