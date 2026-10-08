#!/usr/bin/env python3
"""Re-export the rebuilt driver after restoring BIOS assembly boundaries in IDA."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

REPO_ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(REPO_ROOT / "tools/binrecon"))

from binrecon.adapters.ida import _mapping_manifest
from binrecon.identity import assert_identity
from binrecon.macho import read_macho
from binrecon.profile import load_profile
from binrecon.schema import validate_analysis_semantics, validate_document


REBUILT_IDA_DATA_ALIAS_NAME = "ATI_BIOS_class_ext"


def _rebuilt_data_aliases(macho, image):
    class_name_sections = [
        section for section in macho["sections"]
        if section["name"] == "__OBJC,__class_names"
    ]
    if len(class_name_sections) != 1:
        raise ValueError("rebuilt image must have one __OBJC,__class_names section")
    section = class_name_sections[0]
    class_sections = [
        item for item in macho["sections"] if item["name"] == "__OBJC,__class"
    ]
    if len(class_sections) != 1:
        raise ValueError("rebuilt image must have one __OBJC,__class section")
    class_section = class_sections[0]
    section_data = image[section["offset"]:section["offset"] + section["size"]]

    def string_offset(value):
        needle = value.encode("ascii") + b"\0"
        matches = []
        cursor = 0
        while True:
            offset = section_data.find(needle, cursor)
            if offset < 0:
                break
            if offset == 0 or section_data[offset - 1] == 0:
                matches.append(offset)
            cursor = offset + 1
        if len(matches) != 1:
            raise ValueError(f"rebuilt class-name section must contain one {value} string")
        return matches[0]

    object_offset = string_offset("Object")
    bios_offset = string_offset("ATI_BIOS")
    name_relocations = {
        item["address"]: item["addend"]
        for item in macho["relocations"]
        if item["target"] == section["name"]
    }
    pairs = [
        address for address, addend in name_relocations.items()
        if (class_section["address"] <= address <
                class_section["address"] + class_section["size"] and
                addend == object_offset and name_relocations.get(address + 4) == bios_offset)
    ]
    if len(pairs) != 1:
        raise ValueError("rebuilt image must have a unique Object/ATI_BIOS relocation pair")
    return {pairs[0]: REBUILT_IDA_DATA_ALIAS_NAME}


def _ida_script(output, input_path, size, sha256, mapping_path, mapping_sha256,
                data_aliases):
    args = [str(output), str(input_path), str(size), sha256,
            str(mapping_path), mapping_sha256, data_aliases]
    return f'''import hashlib, json, sys
import ida_auto, ida_bytes, ida_funcs, ida_idaapi, ida_name, ida_pro, ida_ua, idautils
from pathlib import Path
args = {args!r}
output, input_path, size, sha256, mapping_path, mapping_sha256, data_aliases = args
sys.path.insert(0, {str(REPO_ROOT / "tools/binrecon/adapters/ida")!r})
import export_analysis
if not ida_auto.auto_wait():
    raise RuntimeError("IDA auto-analysis did not complete")

def symbol(name):
    ea = ida_name.get_name_ea(ida_idaapi.BADADDR, name)
    if ea == ida_idaapi.BADADDR:
        raise RuntimeError("required rebuilt symbol is missing: " + name)
    return ea

start16 = symbol("__bios16")
end16 = ida_name.get_name_ea(ida_idaapi.BADADDR, "bios16_end")
if end16 == ida_idaapi.BADADDR:
    # IDA may keep only the adjacent entry alias at this shared boundary.
    end16 = symbol("__ATIbios32")
start32 = end16
end32 = symbol("bios32_end")
ranges = [(start16, end16, "__bios16", 117),
          (start32, end32, "__ATIbios32", 203)]
if end16 != start32:
    raise RuntimeError("BIOS entry symbols are not contiguous")
for start, end, name, expected_size in ranges:
    if end - start != expected_size:
        raise RuntimeError("unexpected rebuilt range for %s: 0x%x bytes" %
                           (name, end - start))

# IDA may split BIOS entries at the far-transfer tails. Remove those fragments
# and decode the complete source ranges.
for function_start in list(idautils.Functions()):
    function = ida_funcs.get_func(function_start)
    if function is None:
        continue
    if any(function_start < end and function.end_ea > start
           for start, end, _, _ in ranges):
        ida_funcs.del_func(function_start)

far_transfers = [(start16 + 93, 7), (start32 + 89, 7)]
for address, far_size in far_transfers:
    ida_bytes.del_items(address, ida_bytes.DELIT_SIMPLE, far_size)
    if ida_ua.create_insn(address) != far_size:
        raise RuntimeError("could not decode far transfer at 0x%x" % address)

for start, end, name, _ in ranges:
    spans = [(address, address + far_size) for address, far_size in far_transfers
             if start <= address < end]
    cursor = start
    for span_start, span_end in spans:
        if cursor < span_start:
            ida_bytes.del_items(cursor, ida_bytes.DELIT_SIMPLE, span_start - cursor)
        cursor = span_end
    if cursor < end:
        ida_bytes.del_items(cursor, ida_bytes.DELIT_SIMPLE, end - cursor)
    ea = start
    while ea < end:
        if any(ea == address for address, _ in far_transfers):
            ea += next(far_size for address, far_size in far_transfers if address == ea)
            continue
        decoded = ida_ua.create_insn(ea)
        if decoded <= 0 or ea + decoded > end:
            raise RuntimeError("failed to decode %s at 0x%x" % (name, ea))
        ea += decoded
    if ea != end:
        raise RuntimeError("instruction boundary does not end at %s" % name)
    if not ida_funcs.add_func(start, end):
        function = ida_funcs.get_func(start)
        if function is None or function.end_ea != end:
            raise RuntimeError("could not establish complete range for %s" % name)
    function = ida_funcs.get_func(start)
    if function is None or function.end_ea != end:
        if function is not None:
            ida_funcs.set_func_end(start, end)
            function = ida_funcs.get_func(start)
        if function is None or function.end_ea != end:
            raise RuntimeError("IDA function boundary differs for %s" % name)
    ida_name.set_name(start, name, ida_name.SN_FORCE)

for address, name in data_aliases.items():
    superclass_name = ida_bytes.get_dword(address)
    class_name = ida_bytes.get_dword(address + 4)
    def read_c_string(ea):
        value = ida_bytes.get_bytes(ea, 64)
        if value is None or b"\\x00" not in value:
            return None
        try:
            return value.split(b"\\x00", 1)[0].decode("ascii")
        except UnicodeDecodeError:
            return None
    if (name != "ATI_BIOS_class_ext" or
            read_c_string(superclass_name) != "Object" or
            read_c_string(class_name) != "ATI_BIOS"):
        raise RuntimeError("verified class data alias failed identity check: " + name)

if not ida_auto.auto_wait():
    raise RuntimeError("IDA did not finish after BIOS boundary repair")
mapping = export_analysis._load_mapping(Path(mapping_path), mapping_sha256)
if Path(input_path).stat().st_size != int(size):
    raise RuntimeError("rebuilt input file size is %d, expected %s" %
                       (Path(input_path).stat().st_size, size))
document = export_analysis.collect_analysis(Path(input_path), int(size), sha256,
                                            mapping=mapping)
for address, name in data_aliases.items():
    if any(symbol["name"] == name for symbol in document["symbols"]):
        raise RuntimeError("verified class data alias already exists: " + name)
    document["symbols"].append({{"name": name, "address": address,
                                "binding": "local", "section": "__class"}})
if len(document["functions"]) != 54:
    raise RuntimeError("corrected rebuilt export has %d functions; expected 54" %
                       len(document["functions"]))
export_analysis._atomic_write(Path(output), document)
ida_pro.qexit(0)
'''


def export(profile_path, output_dir, *, runner=subprocess.run):
    profile_path = Path(profile_path).resolve(strict=True)
    profile = load_profile(profile_path, os.environ)
    identity = profile.rebuilt_identity
    if identity is None:
        raise ValueError("profile does not declare a rebuilt artifact")
    assert_identity(identity)
    macho = read_macho(identity.path)
    aliases = _rebuilt_data_aliases(macho, identity.path.read_bytes())
    symbols = {symbol["name"]: symbol["address"] for symbol in macho["symbols"]}
    if symbols.get("__ATIbios32") != symbols.get("bios16_end"):
        raise ValueError("rebuilt __ATIbios32 does not alias the bios16_end boundary")
    if symbols.get("bios32_end", 0) - symbols.get("__ATIbios32", 0) != 203:
        raise ValueError("rebuilt __ATIbios32 symbol range is not 203 bytes")
    ida = profile.document["analyzers"]["ida"]
    executable = Path(ida["executable"]).resolve(strict=True)
    output_dir = Path(output_dir).resolve(strict=False)
    output_dir.mkdir(parents=True, exist_ok=True)
    mapping = _mapping_manifest(profile, identity, "rebuilt")
    mapping_bytes = (json.dumps(mapping, sort_keys=True, separators=(",", ":")) + "\n").encode()
    mapping_path = output_dir / "rebuilt-mapping.json"
    mapping_path.write_bytes(mapping_bytes)
    mapping_sha = hashlib.sha256(mapping_bytes).hexdigest().upper()
    analysis_path = output_dir / "rebuilt-ida.json"
    script_path = output_dir / "ida-export-runtime.py"
    database_path = output_dir / "rebuilt-corrected.i64"
    log_path = output_dir / "rebuilt-corrected.ida.log"
    script_path.write_text(_ida_script(analysis_path, identity.path, identity.size,
                                       identity.sha256, mapping_path, mapping_sha,
                                       aliases),
                           encoding="utf-8")
    script_command = subprocess.list2cmdline([
        str(script_path), str(analysis_path), str(identity.path), str(identity.size),
        identity.sha256, str(mapping_path), mapping_sha,
    ])
    command = [str(executable), "-c", "-A", "-pmetapc", f"-o{database_path}",
               f"-L{log_path}", "-S" + script_command, str(identity.path)]
    completed = runner(command, capture_output=True, text=True,
                       timeout=ida["timeout_seconds"], shell=False, check=False)
    if completed.returncode != 0 or not analysis_path.is_file():
        raise RuntimeError(f"IDA corrected export failed ({completed.returncode}); see {log_path}")
    document = json.loads(analysis_path.read_text(encoding="utf-8"))
    validate_document("analysis-v1", document)
    validate_analysis_semantics(document)
    assert_identity(identity)
    corrected_entries = []
    for expected_name in ("__bios16", "__ATIbios32"):
        matches = [function for function in document["functions"]
                   if expected_name in function["names"]]
        if len(matches) != 1:
            raise RuntimeError("corrected export does not contain one " + expected_name)
        function = matches[0]
        corrected_entries.append({
            "symbol": expected_name,
            "start": function["address"],
            "end_exclusive": function["address"] + function["size"],
            "size": function["size"],
        })
    metadata = {
        "rebuilt_sha256": identity.sha256,
        "ida_version": ida["version"],
        "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest().upper(),
        "database_sha256": hashlib.sha256(database_path.read_bytes()).hexdigest().upper(),
        "analysis_sha256": hashlib.sha256(analysis_path.read_bytes()).hexdigest().upper(),
        "function_count": len(document["functions"]),
        "verified_data_aliases": [
            {"address": address, "name": name}
            for address, name in aliases.items()
        ],
        "corrected_entries": corrected_entries,
    }
    (output_dir / "rebuilt-ida-metadata.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return metadata


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args(argv)
    try:
        result = export(args.profile, args.output_dir)
    except Exception as error:
        print(f"IDA corrected rebuilt export failed: {error}", file=sys.stderr)
        return 1
    print(f"IDA corrected rebuilt export complete: {result['function_count']} routines; "
          f"metadata={Path(args.output_dir) / 'rebuilt-ida-metadata.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
