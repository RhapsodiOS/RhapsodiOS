"""Cross-check a PowerPC Mach-O read against properties a correct decode implies.

Fixtures prove the decoder against hand-written arithmetic. This proves it
against the reference binaries: a byte-order mistake scatters reconstructed
values outside every section, and an HA16 sign-extension mistake makes a
scattered HI16/HA16 half disagree with its LO16 partner -- both show up here.
"""

import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent))

from binrecon.macho import read_macho

_PAIRED_KINDS = ("hi16", "ha16", "lo16", "jbsr", "sectdiff")

# Objective-C 1.0 method-list sections whose objc_method struct
# (SEL name; char *types; IMP imp;) legitimately points its third field into
# __TEXT,__text -- the only __OBJC sections where that is true. Verified
# against SCSIServer_reloc and SCSITape_reloc: every __OBJC vanilla
# relocation naming __TEXT,__text lives in one of these three.
_OBJC_METHOD_LIST_SECTIONS = ("__OBJC,__cls_meth", "__OBJC,__inst_meth",
                              "__OBJC,__cat_cls_meth", "__OBJC,__cat_inst_meth")

# Scattered HI16/HA16/LO16 relocations and SECTDIFF (macho.py's
# "ppc-scattered-*-32-absolute" / "ppc-sectdiff-32-absolute" kinds) store a
# *difference* (target - anchor) in their addend, not an address -- that is
# the whole reason the scattered form exists. "base + addend lands inside
# the target section" is an address-form invariant and cannot hold for these.
_DIFFERENCE_FORM_PREFIXES = ("ppc-scattered-", "ppc-sectdiff-")


def _is_difference_form(kind):
    return kind.startswith(_DIFFERENCE_FORM_PREFIXES)


# A PowerPC PIC address load stores the same 32-bit value twice: once as the
# high half of a "lis" (HI16, unrounded, or HA16, sign-adjusted for the
# addi/lwz/stw that follows) and once as the low half of that following
# instruction (LO16). Both scattered halves carry the *same* reconstructed
# value -- that's the one thing we can cross-check for difference-form
# relocations without knowing the anchor. A byte-order or sign-extension bug
# in either half's decode shows up as a disagreement here.
_HA_HI_SCATTERED_KINDS = ("ppc-scattered-hi16-32-absolute", "ppc-scattered-ha16-32-absolute")
_LO16_SCATTERED_KIND = "ppc-scattered-lo16-32-absolute"

# The real HA16/LO16 pairs in SCSIServer_reloc and SCSITape_reloc sit exactly
# 4 bytes apart (the "lis"/"addi" instruction pair). This window is
# deliberately wider than that -- it tolerates the compiler reordering the
# two instructions or inserting one intervening instruction -- while still
# being small enough not to pair relocations that merely share a target
# section by coincidence.
_PAIR_WINDOW = 8


def _register(word, shift):
    return (word >> shift) & 0x1F


def _instruction_word(raw_by_key, relocation):
    """Return the 32-bit instruction word a relocation patches, decoded from
    its raw record's original_bytes, or None if no raw record matches."""
    original_bytes = raw_by_key.get((relocation["address"], relocation["kind"]))
    return int(original_bytes, 16) if original_bytes is not None else None


def _difference_form_pairs(relocations, raw_by_key):
    """Pair each scattered HI16/HA16 relocation with the scattered LO16
    relocation that names the same target and sits within _PAIR_WINDOW bytes
    of it. Same target and proximity alone are not enough -- two unrelated
    address computations can share both -- so, where the instruction bytes
    are available, candidates are narrowed to the one whose base register
    (bits 11-15) is the register the HI16/HA16's "lis"/"addis" wrote (bits
    6-10), and then to the one that *follows* the HI16/HA16 rather than
    precedes it, before picking the nearest by address. Either narrowing
    step is skipped if it would eliminate every candidate (e.g. the raw
    record is unavailable, or every candidate precedes the HI16/HA16 --
    the compiler can reorder the pair). Only pairs actually found are
    returned -- a half with no candidate at all is not reported as
    anything.
    """
    hi_halves = [r for r in relocations if r["kind"] in _HA_HI_SCATTERED_KINDS]
    lo_halves = [r for r in relocations if r["kind"] == _LO16_SCATTERED_KIND]
    pairs = []
    for hi in hi_halves:
        candidates = [
            lo for lo in lo_halves
            if lo["target"] == hi["target"]
            and abs(lo["address"] - hi["address"]) <= _PAIR_WINDOW
        ]
        hi_word = _instruction_word(raw_by_key, hi)
        if hi_word is not None:
            destination = _register(hi_word, 21)
            matching = []
            for lo in candidates:
                lo_word = _instruction_word(raw_by_key, lo)
                if lo_word is not None and _register(lo_word, 16) == destination:
                    matching.append(lo)
            if matching:
                candidates = matching
        following = [lo for lo in candidates if lo["address"] > hi["address"]]
        if following:
            candidates = following
        if candidates:
            pairs.append((hi, min(candidates, key=lambda lo: abs(lo["address"] - hi["address"]))))
    return pairs


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
    raw_by_key = {(entry["address"], entry["kind"]): entry["original_bytes"] for entry in raw}

    for relocation in document["relocations"]:
        target = relocation["target"]
        if _is_difference_form(relocation["kind"]):
            # The field is a difference, not an address, so it cannot be
            # checked against the target section's bounds. What we *can*
            # check is the thing the scattered format's redundant r_value
            # already pinned during decode (_ppc_section_of in macho.py):
            # that the target it named is a real section in this document.
            # NOTE: macho.py's own decode already raises MachOFormatError if
            # a scattered relocation's r_value falls outside every section,
            # so this branch can never fire on a document read_macho can
            # actually produce today. It stays as a guard against future
            # changes to how macho.py emits these raw records.
            if target is None or target not in section_names:
                violations.append(
                    f"{relocation['kind']} at 0x{relocation['address']:x} names "
                    f"target {target!r}, which is not a section in this document"
                )
            continue
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
            # brief's two-way rule didn't anticipate. Verified against both
            # reference binaries: every __OBJC vanilla relocation that names
            # __TEXT,__text lives in one of these three method-list
            # sections, so the allowance is scoped to them rather than to
            # every __OBJC section.
            if owner is not None and not (
                owner.startswith("__OBJC")
                or owner == "__TEXT,__cstring"
                or (owner == "__TEXT,__text"
                    and entry["section"] in _OBJC_METHOD_LIST_SECTIONS)
            ):
                violations.append(
                    f"__OBJC pointer at 0x{entry['address']:x} points into {owner}"
                )

    for hi, lo in _difference_form_pairs(document["relocations"], raw_by_key):
        if (hi["addend"] & 0xFFFFFFFF) != (lo["addend"] & 0xFFFFFFFF):
            violations.append(
                f"{hi['kind']} at 0x{hi['address']:x} and {lo['kind']} at 0x{lo['address']:x} "
                f"reconstruct different values (0x{hi['addend'] & 0xFFFFFFFF:x} vs "
                f"0x{lo['addend'] & 0xFFFFFFFF:x})"
            )

    principals = sum(1 for entry in raw
                     if any(f"ppc-{kind}" in entry["kind"] or
                            f"scattered-{kind}" in entry["kind"]
                            for kind in _PAIRED_KINDS))
    pairs = sum(1 for entry in raw if entry["kind"] == "ppc-pair-16-absolute")
    # NOTE: macho.py raises MachOFormatError itself if a paired principal's
    # PAIR entry is missing (or an orphan PAIR appears without one), so this
    # branch can never fire on a document read_macho can actually produce
    # today either. It stays as a guard against future changes to raw-record
    # emission.
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
    scattered = sum(1 for relocation in document["relocations"]
                    if _is_difference_form(relocation["kind"]))
    print(f"{scattered} scattered/difference-form relocations "
          "(target section verified, field is a difference, not an address)")
    raw = document.get("extensions", {}).get("macho", {}).get("relocations", [])
    raw_by_key = {(entry["address"], entry["kind"]): entry["original_bytes"] for entry in raw}
    pairs = _difference_form_pairs(document["relocations"], raw_by_key)
    print(f"{len(pairs)} HI16/HA16-LO16 pairs checked "
          "(reconstructed values must agree)")
    print(f"{len(document['relocations'])} fused relocations, "
          f"{len(violations)} violations")
    return 1 if violations else 0


if __name__ == "__main__":
    raise SystemExit(main())
