#!/usr/bin/env python3
"""Compare the reconstructed BIOS far-transfer routines with the IDA reference."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys

from binrecon.macho import MachOFormatError, read_macho


REFERENCE_FUNCTIONS = {
    "__bios16": (0x26E0, 117, "bios16_end", 0xEA),
    "__ATIbios32": (0x27B8, 203, "bios32_end", 0x9A),
}
TEXT_SECTION = "__TEXT,__text"


class VerificationError(ValueError):
    pass


def _section(document: dict, name: str) -> dict:
    matches = [item for item in document["sections"] if item["name"] == name]
    if len(matches) != 1:
        raise VerificationError(f"expected one {name} section; found {len(matches)}")
    return matches[0]


def _symbol(document: dict, name: str) -> dict:
    matches = [item for item in document["symbols"] if item["name"] == name]
    if len(matches) != 1:
        raise VerificationError(f"expected one symbol {name}; found {len(matches)}")
    return matches[0]


def _file_bytes(path: Path, document: dict, section: dict, start: int, size: int) -> bytes:
    section_start = section["address"]
    relative = start - section_start
    if relative < 0 or size < 0 or relative + size > section["size"]:
        raise VerificationError(
            f"range 0x{start:x}+0x{size:x} exceeds {section['name']}"
        )
    data = path.read_bytes()
    offset = section["offset"] + relative
    if offset + size > len(data):
        raise VerificationError(f"section range exceeds input file: {path}")
    return data[offset : offset + size]


def _relocation_width(kind: str) -> int:
    match = re.search(r"-(8|16|32|64)-", kind)
    return int(match.group(1)) // 8 if match else 4


def _canonical_code(path: Path, document: dict, section: dict,
                    start: int, size: int) -> tuple[bytes, list[tuple]]:
    raw = bytearray(_file_bytes(path, document, section, start, size))
    relocations = []
    section_start = section["address"]
    section_end = section_start + section["size"]
    for relocation in document["relocations"]:
        address = relocation["address"]
        if not (section_start <= address < section_end):
            continue
        relative = address - start
        width = _relocation_width(relocation["kind"])
        if relative < 0 or relative + width > size:
            continue
        target = relocation["target"]
        addend = relocation["addend"]
        if target == section["name"]:
            target = "internal-text"
            addend -= start
        raw[relative : relative + width] = b"\0" * width
        relocations.append((relative, width, relocation["kind"], target, addend))
    return bytes(raw), sorted(relocations)


def verify(reference_path: Path, rebuilt_path: Path) -> None:
    reference = read_macho(reference_path)
    rebuilt = read_macho(rebuilt_path)
    for label, document in (("reference", reference), ("rebuilt", rebuilt)):
        if document["input"]["architecture"] != "i386":
            raise VerificationError(f"{label} artifact is not i386")

    ref_text = _section(reference, TEXT_SECTION)
    new_text = _section(rebuilt, TEXT_SECTION)

    for name, (reference_start, expected_size, end_name, far_opcode) in REFERENCE_FUNCTIONS.items():
        reference_start_symbol = _symbol(reference, name)
        if reference_start_symbol["address"] != reference_start:
            raise VerificationError(
                f"{name} reference moved to 0x{reference_start_symbol['address']:x}"
            )
        reference_bytes, reference_relocs = _canonical_code(
            reference_path, reference, ref_text, reference_start, expected_size
        )

        start_symbol = _symbol(rebuilt, name)
        end_symbol = _symbol(rebuilt, end_name)
        if start_symbol["section"] != end_symbol["section"]:
            raise VerificationError(f"{name} and {end_name} are in different sections")
        start = start_symbol["address"]
        end = end_symbol["address"]
        if end <= start:
            raise VerificationError(f"invalid symbol range for {name}")
        size = end - start
        if size != expected_size:
            raise VerificationError(
                f"{name} spans {size} bytes; reference spans {expected_size}"
            )
        rebuilt_bytes, rebuilt_relocs = _canonical_code(
            rebuilt_path, rebuilt, new_text, start, size
        )
        if rebuilt_bytes != reference_bytes:
            first = next(i for i, pair in enumerate(zip(rebuilt_bytes, reference_bytes)) if pair[0] != pair[1])
            raise VerificationError(
                f"{name} instruction stream differs at +0x{first:x}: "
                f"rebuilt={rebuilt_bytes[first:first+8].hex()} "
                f"reference={reference_bytes[first:first+8].hex()}"
            )
        if rebuilt_relocs != reference_relocs:
            raise VerificationError(f"{name} symbolic relocation targets differ")

        rebuilt_raw = _file_bytes(rebuilt_path, rebuilt, new_text, start, size)
        far_calls = [i for i, byte in enumerate(rebuilt_raw) if byte == far_opcode]
        if len(far_calls) != 1:
            raise VerificationError(
                f"{name} must contain one far operand opcode 0x{far_opcode:02x}; "
                f"found {len(far_calls)}"
            )
        operand = far_calls[0]
        if operand + 7 > size:
            raise VerificationError(f"{name} far operand is truncated")
        for relocation in rebuilt["relocations"]:
            address = relocation["address"]
            if start + operand <= address < start + operand + 7:
                raise VerificationError(f"{name} runtime-patched far operand has a relocation")

    print("BIOS assembly symbols, ranges, bytes, relocations and far operands verified")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--rebuilt", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        verify(args.reference, args.rebuilt)
    except (OSError, MachOFormatError, VerificationError) as error:
        print(f"verify_assembly: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
