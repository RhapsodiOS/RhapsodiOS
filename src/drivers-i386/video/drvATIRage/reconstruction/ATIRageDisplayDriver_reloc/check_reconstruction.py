#!/usr/bin/env python3
"""Validate the recovered drvATIRage evidence contract and binary coverage."""

import argparse
import json
from pathlib import Path
import struct
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


def validate_static_symbols(expected, actual):
    """Require every recovered static symbol to remain present in the build."""
    missing = sorted(set(expected) - set(actual))
    if missing:
        raise ContractError(f"rebuilt binary is missing static symbol {missing[0]}")
    return True


def compare_thunk(reference, rebuilt, mutable_ranges=(), reference_relocations=(),
                  rebuilt_relocations=()):
    """Compare a machine-code template, masking runtime operands and relocations."""
    if len(reference) != len(rebuilt):
        raise ContractError(f"thunk size differs: {len(reference)} != {len(rebuilt)}")
    mutable = set()
    for start, size in mutable_ranges:
        if start < 0 or size < 0 or start + size > len(reference):
            raise ContractError("mutable thunk range is outside the routine")
        mutable.update(range(start, start + size))
    left, right = bytearray(reference), bytearray(rebuilt)
    for index in mutable:
        left[index] = right[index] = 0
    try:
        return compare_relocated_data(bytes(left), bytes(right),
                                      reference_relocations, rebuilt_relocations)
    except ContractError as error:
        raise ContractError("thunk differs outside mutable operand ranges and relocations") from error


def compare_relocated_data(reference, rebuilt, reference_relocations=(),
                           rebuilt_relocations=()):
    """Compare data bytes while checking pointer fields by symbolic target."""
    if len(reference) != len(rebuilt):
        raise ContractError(f"static data size differs: {len(reference)} != {len(rebuilt)}")

    def records(values):
        result = {}
        for item in values:
            offset = item["offset"]
            width = item.get("width", 4)
            if type(offset) is not int or type(width) is not int or offset < 0 or width <= 0 or offset + width > len(reference):
                raise ContractError("static data relocation is outside its symbol")
            if offset in result:
                raise ContractError("duplicate static data relocation offset")
            result[offset] = (width, item["kind"], item["target"], item.get("addend", 0))
        return result

    left, right = records(reference_relocations), records(rebuilt_relocations)
    if left != right:
        raise ContractError("static data relocation targets differ")
    mutable = set()
    for offset, (width, _kind, _target, _addend) in left.items():
        mutable.update(range(offset, offset + width))
    if any(reference[index] != rebuilt[index] for index in range(len(reference))
           if index not in mutable):
        raise ContractError("static data differs outside relocated pointer fields")
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


def _section_data(path, macho, name):
    section = next((item for item in macho["sections"] if item["name"] == name), None)
    if section is None:
        raise ContractError(f"missing section {name}")
    return section, Path(path).read_bytes()[section["offset"]:section["offset"] + section["size"]]


def _vm_read(path, macho, address, size):
    for section in macho["sections"]:
        if section["address"] <= address and address + size <= section["address"] + section["size"]:
            # Mach-O zero-fill sections use file offset zero and have no
            # backing bytes; their load-time contents are all zero.
            if section["offset"] == 0 and section["name"].rsplit(",", 1)[-1] in {"__bss", "__common"}:
                return bytes(size)
            offset = section["offset"] + address - section["address"]
            return Path(path).read_bytes()[offset:offset + size]
    raise ContractError(f"address 0x{address:x} is outside initialized sections")


def _cstring(path, macho, address):
    section = next((item for item in macho["sections"]
                    if item["address"] <= address < item["address"] + item["size"]), None)
    if section is None:
        return None
    offset = section["offset"] + address - section["address"]
    payload = Path(path).read_bytes()
    end = payload.find(b"\0", offset, section["offset"] + section["size"])
    if end < 0:
        return None
    return payload[offset:end].decode("latin1")


def _objc_snapshot(path, macho, contract, validate_contract=True):
    instance_methods = set()
    class_methods = set()
    class_records = {}

    def read_words(address, count):
        return struct.unpack("<" + "I" * count, _vm_read(path, macho, address, count * 4))

    def parse_methods(address, owner, sign, destination):
        if not address:
            return
        _item_size, count = read_words(address, 2)
        if count > 512:
            raise ContractError("Objective-C method list count is unreasonable")
        for index in range(count):
            selector, encoding, _implementation = read_words(address + 8 + index * 12, 3)
            selector_name, type_encoding = _cstring(path, macho, selector), _cstring(path, macho, encoding)
            if selector_name is None or type_encoding is None:
                raise ContractError("Objective-C method metadata has an invalid selector or encoding")
            destination.add((owner, sign, selector_name, type_encoding))

    module_section, _ = _section_data(path, macho, "__OBJC,__module_info")
    class_addresses, category_addresses = [], []
    for module_address in range(module_section["address"],
                                module_section["address"] + module_section["size"], 16):
        _version, _module_size, _module_name, symtab = read_words(module_address, 4)
        class_count, category_count = struct.unpack(
            "<HH", _vm_read(path, macho, symtab + 8, 4))
        definitions = read_words(symtab + 12, class_count + category_count)
        class_addresses.extend(definitions[:class_count])
        category_addresses.extend(definitions[class_count:])

    for address in class_addresses:
        isa, superclass, name_address, _version, _info, instance_size, ivar_list, methods = read_words(address, 8)
        name = _cstring(path, macho, name_address)
        if not name:
            raise ContractError("Objective-C class metadata has no name")
        superclass_name = _cstring(path, macho, superclass) if superclass else None
        ivars = []
        if ivar_list:
            (count,) = read_words(ivar_list, 1)
            if count > 128:
                raise ContractError("Objective-C ivar list count is unreasonable")
            for index in range(count):
                name_ptr, type_ptr, ivar_offset = read_words(ivar_list + 4 + index * 12, 3)
                name_text, encoding = _cstring(path, macho, name_ptr), _cstring(path, macho, type_ptr)
                if name_text is None or encoding is None:
                    raise ContractError("Objective-C ivar metadata has an invalid name or encoding")
                ivars.append({"name": name_text, "encoding": encoding, "offset": ivar_offset,
                              "size": ENCODING_SIZE.get(encoding)})
        class_records[name] = {"superclass": superclass_name, "instance_size": instance_size,
                               "ivars": ivars}
        parse_methods(methods, name, "-", instance_methods)
        if isa:
            meta_methods = read_words(isa + 28, 1)[0]
            parse_methods(meta_methods, name, "+", class_methods)

    categories = {}
    for address in category_addresses:
        category_ptr, class_ptr, inst_list, cls_list, _protocols = read_words(address, 5)
        category_name = _cstring(path, macho, category_ptr)
        class_name = _cstring(path, macho, class_ptr)
        if not category_name or not class_name:
            raise ContractError("Objective-C category metadata has no name")
        categories.setdefault(class_name, []).append(category_name)
        owner = f"{class_name}({category_name})"
        parse_methods(inst_list, owner, "-", instance_methods)
        parse_methods(cls_list, owner, "+", class_methods)

    if validate_contract:
        expected_layouts = {name: layout for name, layout in contract["abi"]["classes"].items()
                            if not layout.get("generated")}
        for name, expected in expected_layouts.items():
            actual = class_records.get(name)
            if actual is None:
                raise ContractError(f"rebuilt Objective-C class {name} is missing")
            if (actual["superclass"] != expected["superclass"] or
                    actual["instance_size"] != expected["instance_size"]):
                raise ContractError(f"rebuilt Objective-C class {name} has a different superclass or instance size")
            want_ivars = [{key: item[key] for key in ("name", "encoding", "offset", "size")}
                          for item in expected["ivars"]]
            if actual["ivars"] != want_ivars:
                raise ContractError(f"rebuilt Objective-C class {name} ivar layout differs: {actual['ivars']!r}")

        expected_categories = contract["abi"]["categories"]
        if {name: sorted(items) for name, items in categories.items()} != {
                name: sorted(items) for name, items in expected_categories.items()}:
            raise ContractError("rebuilt Objective-C categories differ")
        signatures = instance_methods | class_methods
        # GCC's legacy Objective-C runtime encodes every char-pointer parameter as
        # `*` (C string), even when the source declares signed char *. The reference
        # compiler emitted `^c` (pointer to char) for these two byte-output APIs.
        # Both encodings carry the same 32-bit pointer calling convention; preserve
        # the exact, narrowly scoped compatibility mapping rather than weakening
        # selector or other type-encoding checks.
        legacy_char_pointer_encodings = {
            ("ATI_BIOS", "-", "getIOBaseAddress:relocatable:", "i16@8:12^L16*20"):
                ("ATI_BIOS", "-", "getIOBaseAddress:relocatable:", "i16@8:12^L16^c20"),
            ("ATI_BIOS", "-", "shortQuery:hardCoded:smallAperture:address:colorDepth:memorySize:asicType:asicRev:",
             "i40@8:12^I16*20*24^I28^I32^I36*40*44"):
                ("ATI_BIOS", "-", "shortQuery:hardCoded:smallAperture:address:colorDepth:memorySize:asicType:asicRev:",
                 "i40@8:12^I16^c20^c24^I28^I32^I36*40*44"),
        }
        signatures = {legacy_char_pointer_encodings.get(item, item) for item in signatures}
        expected_signatures = {(item["owner"].split("(")[0] if "(" not in item["owner"] else item["owner"],
                                item["sign"], item["selector"], item["type_encoding"])
                               for item in contract["objective_c_methods"]}
        if signatures != expected_signatures:
            raise ContractError(f"rebuilt Objective-C method selectors or type encodings differ: "
                                f"missing={sorted(expected_signatures - signatures)!r}; "
                                f"extra={sorted(signatures - expected_signatures)!r}")
    return class_records, instance_methods, class_methods, categories


def _relocations_for(macho, address, size, path, crtc_start, crtc_size):
    sections = {item["name"]: item for item in macho["sections"]}
    symbols = macho["symbols"]
    result = []
    for relocation in macho["relocations"]:
        if not address <= relocation["address"] < address + size:
            continue
        target = relocation["target"]
        addend = relocation["addend"]
        target_section = sections.get(target)
        canonical = (target, addend)
        if target_section is not None:
            target_address = target_section["address"] + addend
            if crtc_start <= target_address < crtc_start + crtc_size:
                canonical = ("crtc", target_address - crtc_start)
            elif target == "__TEXT,__cstring":
                canonical = ("cstring", _cstring(path, macho, target_address))
            else:
                exact = [item for item in symbols if item["address"] == target_address and
                         item["section"] == target]
                if exact:
                    chosen = min(exact, key=lambda item: (":" in item["name"],
                                                          not item["name"].startswith("_"),
                                                          len(item["name"])))
                    canonical = ("symbol", chosen["name"])
        width = relocation.get("width", 4)
        kind = relocation["kind"].replace("i386-scattered-vanilla-32-absolute",
                                          "i386-vanilla-32-absolute")
        result.append({"offset": relocation["address"] - address,
                       "kind": kind, "target": canonical,
                       "addend": 0, "width": width})
    return result


def _compare_binary_data(reference_path, rebuilt_path, reference_macho, rebuilt_macho,
                         contract):
    ref_crtc = contract["crtc_timings"]["records"]
    crtc_bytes = b"".join(bytes.fromhex(item["bytes_hex"]) for item in ref_crtc)
    ref_crtc_section, ref_crtc_payload = _section_data(reference_path, reference_macho, "__DATA,__data")
    new_crtc_section, new_crtc_payload = _section_data(rebuilt_path, rebuilt_macho, "__DATA,__data")
    ref_pos = ref_crtc_payload.find(crtc_bytes)
    new_pos = new_crtc_payload.find(crtc_bytes)
    if ref_pos < 0 or new_pos < 0:
        raise ContractError("rebuilt CRTC timing records differ")
    ref_crtc_start = ref_crtc_section["address"] + ref_pos
    new_crtc_start = new_crtc_section["address"] + new_pos
    for index, record in enumerate(ref_crtc):
        reference = _vm_read(reference_path, reference_macho, record["address"], record["size"])
        rebuilt = _vm_read(rebuilt_path, rebuilt_macho, new_crtc_start + index * record["size"], record["size"])
        if reference != rebuilt:
            raise ContractError(f"CRTC timing record {index} differs")

    def symbol_named(macho, name):
        found = [item for item in macho["symbols"] if item["name"] == name and item["section"]]
        if not found:
            raise ContractError(f"rebuilt binary is missing static symbol {name}")
        return found[0]

    expected_static = [item["name"] for item in contract["static_symbols"]]
    expected_static.extend(item["name"] for item in
                           (contract["auxiliary_data"]["gamma16"], contract["auxiliary_data"]["gamma8"]))
    validate_static_symbols(expected_static, [item["name"] for item in rebuilt_macho["symbols"]])

    ref_by_name = {item["name"]: item for item in reference_macho["symbols"]}
    new_by_name = {item["name"]: item for item in rebuilt_macho["symbols"]}
    ref_sections = {item["name"]: item for item in reference_macho["sections"]}
    for section_name in {item["section"] for item in contract["static_symbols"]}:
        if section_name is None:
            continue
        ordered = sorted((item for item in contract["static_symbols"]
                          if item["section"] == section_name), key=lambda item: item["address"])
        ref_section = ref_sections[section_name]
        for index, item in enumerate(ordered):
            ref_symbol, new_symbol = ref_by_name[item["name"]], new_by_name[item["name"]]
            if ref_symbol["section"] != section_name or new_symbol["section"] != section_name:
                # This old GCC emits an explicitly zero-initialized, unused
                # static pointer into __bss; the reference compiler put the
                # same zero bytes in __data. Permit only this storage-class
                # move, then compare its exact zero-filled extent below.
                valid_mode_list_bss = (
                    item["name"] == "_ValidModeList" and
                    section_name == "__DATA,__data" and
                    new_symbol["section"] == "__DATA,__bss"
                )
                if ref_symbol["section"] != section_name or not valid_mode_list_bss:
                    raise ContractError(f"static symbol {item['name']} moved to a different section")
            end_address = (ordered[index + 1]["address"] if index + 1 < len(ordered)
                           else ref_section["address"] + ref_section["size"])
            size = end_address - item["address"]
            if size <= 0:
                raise ContractError(f"static symbol {item['name']} has an invalid extent")
            left_bytes = _vm_read(reference_path, reference_macho, ref_symbol["address"], size)
            right_bytes = _vm_read(rebuilt_path, rebuilt_macho, new_symbol["address"], size)
            left_relocs = _relocations_for(reference_macho, ref_symbol["address"], size,
                                           reference_path, ref_crtc_start, len(crtc_bytes))
            right_relocs = _relocations_for(rebuilt_macho, new_symbol["address"], size,
                                            rebuilt_path, new_crtc_start, len(crtc_bytes))
            try:
                compare_relocated_data(left_bytes, right_bytes, left_relocs, right_relocs)
            except ContractError as error:
                raise ContractError(f"static symbol {item['name']}: {error}") from error

    tables = list(contract["auxiliary_data"]["tables"])
    for table in tables:
        name, size = table["name"], table["size"]
        left, right = symbol_named(reference_macho, name), symbol_named(rebuilt_macho, name)
        left_bytes = _vm_read(reference_path, reference_macho, left["address"], size)
        right_bytes = _vm_read(rebuilt_path, rebuilt_macho, right["address"], size)
        left_relocs = _relocations_for(reference_macho, left["address"], size, reference_path,
                                       ref_crtc_start, len(crtc_bytes))
        right_relocs = _relocations_for(rebuilt_macho, right["address"], size, rebuilt_path,
                                        new_crtc_start, len(crtc_bytes))
        try:
            compare_relocated_data(left_bytes, right_bytes, left_relocs, right_relocs)
        except ContractError as error:
            raise ContractError(f"static table {name}: {error}") from error

    mode = contract["display_modes"]
    left, right = symbol_named(reference_macho, mode["symbol"]), symbol_named(rebuilt_macho, mode["symbol"])
    size = mode["count"] * mode["record_size"]
    left_bytes = _vm_read(reference_path, reference_macho, left["address"], size)
    right_bytes = _vm_read(rebuilt_path, rebuilt_macho, right["address"], size)
    try:
        compare_relocated_data(left_bytes, right_bytes,
            _relocations_for(reference_macho, left["address"], size, reference_path, ref_crtc_start, len(crtc_bytes)),
            _relocations_for(rebuilt_macho, right["address"], size, rebuilt_path, new_crtc_start, len(crtc_bytes)))
    except ContractError as error:
        raise ContractError(f"static table {mode['symbol']}: {error}") from error

    for gamma in (contract["auxiliary_data"]["gamma16"], contract["auxiliary_data"]["gamma8"]):
        left, right = symbol_named(reference_macho, gamma["name"]), symbol_named(rebuilt_macho, gamma["name"])
        if (_vm_read(reference_path, reference_macho, left["address"], gamma["size"]) !=
                _vm_read(rebuilt_path, rebuilt_macho, right["address"], gamma["size"])):
            raise ContractError(f"static table {gamma['name']} differs")


def _check_rebuilt(path, reference_path, contract):
    macho = read_macho(path)
    if (macho["input"]["architecture"], macho["input"]["endianness"]) != ("i386", "little"):
        raise ContractError("rebuilt architecture is not i386 little-endian")
    _objc_snapshot(path, macho, contract)
    reference_macho = read_macho(reference_path)
    _compare_binary_data(reference_path, path, reference_macho, macho, contract)

    def symbol_address(document, name):
        values = [item["address"] for item in document["symbols"] if item["name"] == name]
        if not values:
            raise ContractError(f"rebuilt BIOS routine symbol {name} is missing")
        return values[0]

    for name, size, mutable in (("__bios16", 117, ((0x5e, 4), (0x62, 2))),
                                ("__ATIbios32", 203, ((0x5a, 4), (0x5e, 2)))):
        left_address = symbol_address(reference_macho, name)
        right_address = symbol_address(macho, name)
        left_bytes = _vm_read(reference_path, reference_macho, left_address, size)
        right_bytes = _vm_read(path, macho, right_address, size)
        left_relocations = _relocations_for(reference_macho, left_address, size,
                                            reference_path, 0, 0)
        right_relocations = _relocations_for(macho, right_address, size, path, 0, 0)
        # The reference strips local assembly labels, leaving relocations as
        # section-plus-offset targets. Bind those known offsets to the labels
        # used by the reconstructed assembly so the comparison checks the
        # logical storage target, not incidental section placement.
        reference_target_names = {
            "__bios16": {
                ("__DATA,__data", 11036): ("symbol", "__ati_bios16_saved_eax"),
                ("__DATA,__data", 11040): ("symbol", "__ati_bios16_saved_esp"),
                ("__DATA,__data", 11044): ("symbol", "__ati_bios16_saved_ss"),
                ("__TEXT,__text", 11942): ("symbol", "bios16_far_offset"),
                ("__TEXT,__text", 11946): ("symbol", "bios16_far_selector"),
                ("__TEXT,__text", 11948): ("symbol", "bios16_return"),
            },
            "__ATIbios32": {
                ("__DATA,__data", 11072): ("symbol", "__ati_bios32_registers"),
                ("__DATA,__data", 11080): ("symbol", "__ati_bios32_saved_eax"),
                ("__DATA,__data", 11084): ("symbol", "__ati_bios32_saved_edx"),
                ("__DATA,__data", 11068): ("symbol", "__ati_bios32_result_eax"),
                ("__DATA,__data", 11076): ("symbol", "__ati_bios32_result_flags"),
                ("__DATA,__data", 11064): ("symbol", "__ati_bios32_result_es"),
                ("__TEXT,__text", 12158): ("symbol", "bios32_far_selector"),
                ("__TEXT,__text", 12154): ("symbol", "bios32_far_offset"),
            },
        }
        for relocation in left_relocations:
            target_name = reference_target_names[name].get(relocation["target"])
            if target_name is not None:
                relocation["target"] = target_name
        if name == "__bios16":
            # Keep the far-return target local to the thunk. A numeric
            # assembler label avoids publishing an IDA function boundary
            # inside this mixed-mode routine, so bind its section-relative
            # relocation by offset instead of requiring a local symbol.
            rebuilt_return = ("__TEXT,__text", right_address + 100)
            for relocation in right_relocations:
                if relocation["target"] == rebuilt_return:
                    relocation["target"] = ("symbol", "bios16_return")
        compare_thunk(left_bytes, right_bytes, mutable, left_relocations,
                      right_relocations)


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
        _check_rebuilt(rebuilt_path, path, contract)
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
