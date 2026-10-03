#!/usr/bin/env python3
"""Validate the recovered drvATIRage evidence contract and binary coverage."""

import argparse
import json
from pathlib import Path
import sys

from binrecon.identity import identify
from binrecon.macho import MachOFormatError, read_macho
from binrecon.schema import load_json, load_source_map, validate_analysis_semantics, validate_document


class ContractError(ValueError):
    """The reference or reconstruction violates its evidence contract."""


ENCODING_SIZE = {"c": 1, "i": 4, "I": 4, "L": 4, "@": 4, "*": 4,
                 "^v": 4, "^I": 4, "^c": 4}


def validate_text_partition(ranges, gaps, text_size):
    """Require routines and classified gaps to account for each text byte once."""
    if type(text_size) is not int or text_size <= 0:
        raise ContractError("text size must be a positive integer")
    entries = [(item["address"], item["size"], item.get("name", item.get("kind", "range")))
               for item in list(ranges) + list(gaps)]
    entries.sort()
    cursor = 0
    for address, size, label in entries:
        if type(address) is not int or type(size) is not int or size <= 0:
            raise ContractError(f"invalid text range {label}")
        if address < cursor:
            raise ContractError(f"overlapping text range at 0x{address:x}: {label}")
        if address > cursor:
            raise ContractError(f"uncovered text at 0x{cursor:x}..0x{address:x}")
        cursor = address + size
        if cursor > text_size:
            raise ContractError(f"text range {label} ends beyond 0x{text_size:x}")
    if cursor < text_size:
        raise ContractError(f"uncovered text at 0x{cursor:x}..0x{text_size:x}")
    return True


def validate_abi(layout):
    """Check aligned ivar extents against the inherited and instance sizes."""
    inherited = layout["superclass_size"]
    if type(inherited) is not int or inherited < 0:
        raise ContractError("invalid superclass size")
    cursor = inherited
    seen = set()
    for ivar in layout["ivars"]:
        name, encoding = ivar["name"], ivar["encoding"]
        size = ivar.get("size", ENCODING_SIZE.get(encoding))
        if name in seen:
            raise ContractError(f"duplicate ivar {name}")
        seen.add(name)
        if type(size) is not int or size != ENCODING_SIZE.get(encoding):
            raise ContractError(f"ivar {name} has unsupported encoding/size")
        alignment = min(size, 4)
        expected_offset = (cursor + alignment - 1) & ~(alignment - 1)
        if ivar["offset"] != expected_offset:
            raise ContractError(f"ivar {name} offset 0x{ivar['offset']:x} does not follow 0x{expected_offset:x}")
        cursor = ivar["offset"] + size
    if cursor != layout["instance_size"]:
        raise ContractError(f"instance size {layout['instance_size']} does not end at 0x{cursor:x}")
    return True


def validate_modes(modes, expected_count, record_size):
    """Require every fixed-size mode record to be present in index order."""
    if len(modes) != expected_count:
        raise ContractError(f"expected {expected_count} modes, found {len(modes)}")
    for index, mode in enumerate(modes):
        if mode.get("index") != index or mode.get("size", mode.get("bytes")) != record_size:
            raise ContractError(f"mode {index} has an invalid index or record size")
    return True


def compare_thunk(reference, rebuilt, mutable_ranges=()):
    """Compare a machine-code template, ignoring only explicitly mutable fields."""
    if len(reference) != len(rebuilt):
        raise ContractError(f"thunk size differs: {len(reference)} != {len(rebuilt)}")
    mutable = set()
    for start, size in mutable_ranges:
        if start < 0 or size < 0 or start + size > len(reference):
            raise ContractError("mutable thunk range is outside the routine")
        mutable.update(range(start, start + size))
    if any(reference[index] != rebuilt[index] for index in range(len(reference))
           if index not in mutable):
        raise ContractError("thunk differs outside mutable operand ranges")
    return True


def _load_contract(path):
    contract = load_json(path)
    if contract.get("schema_version") != "drvATIRage-reference-contract-v1":
        raise ContractError("unsupported reconstruction contract schema")
    partition = contract["text_partition"]
    routines = contract["routines"]
    validate_text_partition(routines, partition["gaps"], partition["size"])
    for layout in contract["abi"]["classes"].values():
        if "superclass_size" in layout:
            validate_abi(layout)
    register_block = contract["abi"]["bios_register_block"]
    cursor = 0
    for field in register_block["fields"]:
        if field["offset"] != cursor or field["size"] <= 0:
            raise ContractError(f"BIOS register field {field['name']} has an invalid offset or size")
        cursor += field["size"]
    if cursor != register_block["size"]:
        raise ContractError(f"BIOS register block ends at {cursor}, expected {register_block['size']}")
    methods = contract["objective_c_methods"]
    if len(methods) != 50 or any(not item.get("type_encoding") for item in methods):
        raise ContractError("raw Objective-C method encodings are incomplete")
    if len({item["address"] for item in methods}) != len(methods):
        raise ContractError("Objective-C method implementation addresses are duplicated")
    modes = contract["display_modes"]
    validate_modes(modes["records"], modes["count"], modes["record_size"])
    addresses = [item["address"] for item in routines]
    if len(addresses) != len(set(addresses)):
        raise ContractError("routine entry addresses are not unique")
    return contract


def _check_reference(path, analysis_path, contract, source_map_path=None,
                     repo_root=None, rebuilt_path=None):
    identity = identify(path)
    expected = contract["reference"]
    if identity.size != expected["size"] or identity.sha256 != expected["sha256"]:
        raise ContractError("reference artifact identity differs from the contract")
    macho = read_macho(path)
    if (macho["input"]["architecture"], macho["input"]["endianness"]) != ("i386", "little"):
        raise ContractError("reference architecture is not i386 little-endian")
    text = next((section for section in macho["sections"]
                 if section["name"] == "__TEXT,__text"), None)
    if text is None or text["size"] != contract["text_partition"]["size"]:
        raise ContractError("reference __TEXT,__text size differs from contract")
    symbols = {(item["address"], item["name"]) for item in macho["symbols"]
               if item["section"] is not None}
    for routine in contract["routines"]:
        if routine["kind"] in ("transition", "thunk") and not any(
                address == routine["address"] and name == routine["name"]
                for address, name in symbols):
            raise ContractError(f"reference is missing symbol {routine['name']}")

    analysis = load_json(analysis_path)
    validate_document("analysis-v1", analysis)
    validate_analysis_semantics(analysis)
    if analysis["input"]["sha256"].upper() != expected["sha256"]:
        raise ContractError("IDA analysis belongs to another reference binary")
    expected_ida = {item["address"]: (item["size"], item["names"])
                    for item in contract["ida_functions"]}
    actual_ida = {item["address"]: (item["size"], item["names"])
                  for item in analysis["functions"]}
    if actual_ida != expected_ida:
        raise ContractError("IDA function inventory differs from the saved contract")
    if source_map_path is not None:
        load_source_map(Path(source_map_path), reference_analysis=analysis,
                        repo_root=Path(repo_root) if repo_root else None)
    if rebuilt_path is not None:
        raise ContractError("rebuilt-binary gates have not been implemented")
    return True


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", required=True, type=Path)
    parser.add_argument("--reference-analysis", required=True, type=Path)
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--source-map", type=Path)
    parser.add_argument("--rebuilt", type=Path)
    parser.add_argument("--contract", type=Path)
    args = parser.parse_args(argv)
    contract_path = args.contract or Path(__file__).with_name("reference-contract.json")
    try:
        contract = _load_contract(contract_path)
        _check_reference(args.reference, args.reference_analysis, contract,
                         args.source_map, args.repo_root, args.rebuilt)
    except (OSError, ValueError, KeyError, MachOFormatError) as error:
        print(f"reconstruction check failed: {error}", file=sys.stderr)
        return 1
    print(f"reference contract valid: {len(contract['routines'])} code entries; "
          f"{contract['text_partition']['size']} text bytes accounted for")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
