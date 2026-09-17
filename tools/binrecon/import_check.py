"""Compare a rebuilt driver's kernel imports against the reference's.

A reference import our build never calls means we reached for a different kernel
API than Apple did, which neither string nor symbol parity detects.

Extras on our side are normally noise — an unstripped build pulls in far more
than it uses — but an *undefined* extra is not noise. A driver that imports a
symbol the kernel does not export has a relocation that can never bind, and the
loader rejects it. Because `missing_imports` is a one-way difference it cannot
see that case at all: pass KERNEL to also report unresolvable imports, which is
the check that catches a source name carrying a spurious leading underscore.
"""

import sys
from pathlib import Path

from binrecon.macho import read_macho


def imports(path):
    """Undefined external symbols — the driver's unresolved references.

    An unstripped build also carries thousands of section-less STABS debugging
    entries, all with local binding; only external ones are real imports.
    """
    document = read_macho(path)
    return {symbol["name"] for symbol in document["symbols"]
            if symbol["section"] is None and symbol["binding"] == "external"}


def exports(path):
    document = read_macho(path)
    return {symbol["name"] for symbol in document["symbols"]
            if symbol["section"] is not None}


def main(argv):
    if len(argv) not in (3, 4):
        print("usage: import_check.py REFERENCE REBUILT [KERNEL]", file=sys.stderr)
        return 2

    reference = imports(Path(argv[1]))
    rebuilt = imports(Path(argv[2]))
    missing = sorted(reference - rebuilt)

    print("reference imports: %d" % len(reference))
    print("rebuilt imports:   %d" % len(rebuilt))
    print("\nmissing_imports (%d):" % len(missing))
    for name in missing:
        print("    %s" % name)

    unresolvable = []
    if len(argv) == 4:
        available = exports(Path(argv[3])) | reference
        unresolvable = sorted(name for name in rebuilt - available
                              if not name.startswith("."))
        print("\nunresolvable_imports (%d):" % len(unresolvable))
        for name in unresolvable:
            print("    %s" % name)

    return 0 if not missing and not unresolvable else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
