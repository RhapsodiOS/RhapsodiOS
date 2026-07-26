"""Cross-check a PowerPC Mach-O read against properties a correct decode implies.

Fixtures prove the decoder against hand-written arithmetic. This proves it
against the reference binaries: a byte-order or HA16 mistake scatters
reconstructed values outside every section, which shows up here.
"""

import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent))

from binrecon.macho import read_macho

_PAIRED_KINDS = ("hi16", "ha16", "lo16", "jbsr", "sectdiff")


def _sections(document):
    return [section for section in document["sections"] if section["size"]]


def _resolves(sections, name, address):
    for section in sections:
        if section["name"] == name:
            return section["address"] <= address <= section["address"] + section["size"]
    return False


def _section_of(sections, address):
    for section in sections:
        if section["address"] <= address < section["address"] + section["size"]:
            return section["name"]
    return None


def check_document(document):
    """Return a list of violation messages; empty means the decode is consistent."""
    violations = []
    sections = _sections(document)
    section_names = {section["name"] for section in sections}
    raw = document.get("extensions", {}).get("macho", {}).get("relocations", [])

    for relocation in document["relocations"]:
        target = relocation["target"]
        if target is None or target not in section_names:
            continue
        base = next(section["address"] for section in sections
                    if section["name"] == target)
        value = base + relocation["addend"]
        if not _resolves(sections, target, value):
            violations.append(
                f"{relocation['kind']} at 0x{relocation['address']:x} claims {target} "
                f"but reconstructs 0x{value:x}"
            )

    for entry in raw:
        if entry["kind"].startswith("ppc-jbsr"):
            island = entry["address"] + _island_displacement(entry)
            if _section_of(sections, island) != "__TEXT,__text":
                violations.append(
                    f"jbsr at 0x{entry['address']:x} branches to 0x{island:x}, "
                    "which is outside __TEXT,__text"
                )
        if entry["kind"].startswith("ppc-vanilla") and entry["section"].startswith("__OBJC"):
            owner = _section_of(sections, entry["addend"] + _base(sections, entry["target"]))
            # Method lists (__cls_meth, __inst_meth, __cat_*_meth) carry an IMP
            # field alongside the selector/types pointers, and IMP addresses
            # code in __TEXT,__text -- a legitimate third destination the
            # brief's two-way rule didn't anticipate.
            if owner is not None and not (owner.startswith("__OBJC")
                                          or owner in ("__TEXT,__cstring", "__TEXT,__text")):
                violations.append(
                    f"__OBJC pointer at 0x{entry['address']:x} points into {owner}"
                )

    principals = sum(1 for entry in raw
                     if any(f"ppc-{kind}" in entry["kind"] or
                            f"scattered-{kind}" in entry["kind"]
                            for kind in _PAIRED_KINDS))
    pairs = sum(1 for entry in raw if entry["kind"] == "ppc-pair-16-absolute")
    if principals != pairs:
        violations.append(
            f"{principals} paired principals but {pairs} PAIR records"
        )
    return violations


def _base(sections, name):
    for section in sections:
        if section["name"] == name:
            return section["address"]
    return 0


def _island_displacement(entry):
    word = int(entry["original_bytes"], 16)
    field = word & 0x03FFFFFC
    return field - 0x04000000 if field & 0x02000000 else field


def check_functions(document, analysis):
    """Report __text symbols that are not function starts in an IDA analysis."""
    starts = {function["address"] for function in analysis["functions"]}
    return [
        f"symbol {symbol['name']} at 0x{symbol['address']:x} is not a function start"
        for symbol in document["symbols"]
        if symbol["section"] == "__TEXT,__text" and symbol["address"] not in starts
    ]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True)
    parser.add_argument("--analysis")
    arguments = parser.parse_args(argv)

    document = read_macho(Path(arguments.binary))
    violations = check_document(document)
    if arguments.analysis:
        analysis = json.loads(Path(arguments.analysis).read_text(encoding="utf-8"))
        violations += check_functions(document, analysis)

    for violation in violations:
        print(violation)
    print(f"{len(document['relocations'])} fused relocations, "
          f"{len(violations)} violations")
    return 1 if violations else 0


if __name__ == "__main__":
    raise SystemExit(main())
