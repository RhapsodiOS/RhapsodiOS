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
from source_paths import source_files

# libgcc helpers linked into the driver rather than written by hand.
COMPILER_RUNTIME = {"__udivdi3", "__umoddi3", "__divdi3", "__moddi3"}

# A function definition's opening line. The return type is optional *as a
# whole* and, when present, must end in whitespace or a `*` — so it can never
# be satisfied by a prefix of the name itself. An earlier pattern spelled the
# type as a mandatory `[A-Za-z_]` plus a lazy remainder, which happily ate the
# name's first character when the type sat on the previous line and the name
# began at column 0 (`PCodeOpen` -> `CodeOpen`, `m64Init` -> `Init`).
_DEFINITION = re.compile(
    r"^(?P<lead>(?:static\s+)?(?:[A-Za-z_][\w \t\*]*?[\s\*])?)(?P<name>[A-Za-z_]\w*)\s*\("
)

# A line holding nothing but a return type, e.g. `OSStatus` or `static void *`.
_RETURN_TYPE_LINE = re.compile(r"^(?:static\s+)?[A-Za-z_][\w \t\*]*$")

# How far past the opening line to look for the body's `{`. The longest
# parameter list in this corpus is PEF_OpenContainer's, which spans ten lines;
# the cap only stops a runaway scan, since it is the `{`-before-`;` ordering
# below that decides whether a line is a definition at all.
_BODY_LOOKAHEAD = 16

# A data definition: optional `static`, a type, a name, an optional array
# bound, then `=` (initializer) or `;` (bare tentative definition). Neither an
# `extern` declaration nor a `typedef` ever matches, so neither is mistaken
# for a definition site.
_DATA_DEFINITION = re.compile(
    r"^(?!\s*(?:extern|typedef)\b)(?:static\s+)?[A-Za-z_][\w \t\*]*?\b([A-Za-z_]\w*)"
    r"\s*(?:\[[^\]]*\])?\s*(?:=|;)"
)

# The Kernel Server project type generates `<Name>_instance.m` at build time
# (CreateKLLDInstance.sh, wired in by kernelserver.make), and that file names
# the class whose selector appears below. It is the reference binary's own way
# of telling us <Name>.
_KERNEL_SERVER_INSTANCE = re.compile(r"^\+\[(\w+)KernelServerInstance kernelServerInstance\]$")

# gcc appends `.NN` to a function-scope static's symbol to keep it distinct
# from same-named statics elsewhere in the translation unit.
_GCC_STATIC_SUFFIX = re.compile(r"\.\d+$")


def _opens_a_body(lines, index, start):
    """Return True when the parameter list is followed by a body rather than a `;`.

    A definition's parameter list is closed by its body's `{`; a prototype's is
    closed by `;`. Whichever arrives first decides, so the scan can reach past a
    parameter list spanning many lines without ever admitting a prototype — a
    prototype's `;` is always encountered before any later definition's brace.
    """
    for offset in range(index, min(index + _BODY_LOOKAHEAD, len(lines))):
        text = lines[offset][start:] if offset == index else lines[offset]
        for character in text:
            if character in "{;":
                return character == "{"
    return False


def _has_return_type_above(lines, index):
    """Return True when the line above holds nothing but a return type.

    `name(args)` at column 0 is a definition only when its return type sits on
    the preceding line, as in `OSStatus` / `PCodeOpen( ... )`. Without one the
    line is a function-like macro invocation, not a definition site, so
    requiring the type keeps the relaxed pattern above from inventing names.
    """
    return index > 0 and bool(_RETURN_TYPE_LINE.match(lines[index - 1].strip()))


def source_definitions(source_path):
    """Return the C function names defined in .m and .c files under source_path."""
    names = set()
    for path in source_files(source_path, {".m", ".c"}):
        lines = path.read_text(encoding="utf-8", errors="replace").split("\n")
        for index, line in enumerate(lines):
            match = _DEFINITION.match(line)
            if not match:
                continue
            if not match.group("lead") and not _has_return_type_above(lines, index):
                continue
            if _opens_a_body(lines, index, match.end()):
                names.add(match.group("name"))
    return names


def data_definitions(source_path):
    """Return the C data (variable/array) names defined in .m and .c files.

    Only file-scope definitions are recognised: the pattern is anchored at
    column 0, so an indented line (a struct member, or a static inside a
    function body) is never treated as a definition site. Multi-declarator
    definitions such as `int fd_block_major, fd_raw_major;` are not recognised
    either — the comma is outside the type pattern, so neither name is found.
    """
    names = set()
    for path in source_files(source_path, {".m", ".c"}):
        lines = path.read_text(encoding="utf-8", errors="replace").split("\n")
        for line in lines:
            match = _DATA_DEFINITION.match(line)
            if match:
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


def build_generated_data_symbols(document):
    """Return the __DATA symbols this driver's build generates rather than source.

    A Kernel Server project's makefile runs CreateKLLDInstance.sh at build
    time to write `<Name>_instance.m`, whose sole data definition is
    `kern_server_t <Name>_instance;`. That same generated file defines
    `+[<Name>KernelServerInstance kernelServerInstance]`, so the reference
    binary's own symbol table supplies <Name> — no hard-coded driver list.
    Such a symbol is correctly absent from hand-written source, so reporting
    it missing would be a false positive on every Kernel Server driver.
    """
    names = set()
    for symbol in document["symbols"]:
        match = _KERNEL_SERVER_INSTANCE.match(symbol["name"])
        if match:
            names.add(f"_{match.group(1)}_instance")
    return names


def hand_written_data_symbols(document):
    """Return reference __DATA symbols that are hand-written C.

    Two kinds of symbol are excluded because no hand-written file-scope
    definition can ever match them: the build-generated `_<Name>_instance`,
    and gcc's `.NN`-suffixed function-scope statics (e.g. `_protocols.26`),
    which are defined inside a method body and carry a suffix no source
    identifier can spell.

    Objective-C metadata in __OBJC,* sections also fails the __DATA, prefix
    test, but that is incidental: no PPC reference binary in this corpus
    carries an __OBJC symbol, so the exclusion is not load-bearing.
    """
    generated = build_generated_data_symbols(document)
    return [
        symbol["name"]
        for symbol in document["symbols"]
        if (symbol.get("section") or "").startswith("__DATA,")
        and symbol["name"] not in generated
        and not _GCC_STATIC_SUFFIX.search(symbol["name"])
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
    parser.add_argument(
        "--check-data", action="store_true",
        help="also check __DATA,* symbols against data definitions",
    )
    arguments = parser.parse_args(argv)

    definitions = set()
    data_defs = set()
    for source_dir in arguments.source_dir:
        definitions |= source_definitions(source_dir)
        if arguments.check_data:
            data_defs |= data_definitions(source_dir)

    document = read_macho(Path(arguments.binary))

    symbols = hand_written_c_symbols(document)
    missing = missing_definitions(symbols, definitions)

    print(f"hand-written C symbols: {len(symbols)}")
    print(f"missing definitions   : {len(missing)}")
    for name in missing:
        print(f"  {name}")

    data_missing = []
    if arguments.check_data:
        data_symbols = hand_written_data_symbols(document)
        data_missing = missing_definitions(data_symbols, data_defs)
        print(f"hand-written data symbols: {len(data_symbols)}")
        print(f"missing data definitions : {len(data_missing)}")
        for name in data_missing:
            print(f"  {name}")

    return 1 if missing or data_missing else 0


if __name__ == "__main__":
    sys.exit(main())
