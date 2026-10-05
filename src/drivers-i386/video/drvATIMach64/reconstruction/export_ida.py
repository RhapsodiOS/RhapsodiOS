#!/usr/bin/env python3
"""Re-export the reference through IDA after symbol-driven BIOS thunk recovery."""

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
from binrecon.normalize import normalize_analysis
from binrecon.profile import load_profile
from binrecon.schema import validate_analysis_semantics, validate_document

from verify_evidence import corrected_assembly_ranges
from verify_assembly import REFERENCE_DATA_TARGETS


REFERENCE_IDA_DATA_ALIASES = {0x8208: "ATI_BIOS_class_ext"}


def _ida_script(output, input_path, size, sha256, mapping_path, mapping_sha256):
    args = [str(output), str(input_path), str(size), sha256,
            str(mapping_path), mapping_sha256,
            REFERENCE_DATA_TARGETS, REFERENCE_IDA_DATA_ALIASES]
    return f'''import hashlib, json, os, sys
import ida_auto, ida_bytes, ida_funcs, ida_name, ida_pro, ida_ua, idc
from pathlib import Path
args = {args!r}
output, input_path, size, sha256, mapping_path, mapping_sha256, data_aliases, ida_data_aliases = args
sys.path.insert(0, {str(REPO_ROOT / "tools/binrecon/adapters/ida")!r})
import export_analysis
if not ida_auto.auto_wait():
    raise RuntimeError("IDA auto-analysis did not complete")
mapping = export_analysis._load_mapping(Path(mapping_path), mapping_sha256)
for start, end, name in {corrected_assembly_ranges()!r}:
    for address in (0x273d, 0x2811):
        if start <= address < end:
            ida_bytes.del_items(address, ida_bytes.DELIT_SIMPLE, 7)
            if ida_ua.create_insn(address) != 7:
                raise RuntimeError("far transfer operand did not decode at 0x%x" % address)
    if not ida_funcs.add_func(start, end):
        function = ida_funcs.get_func(start)
        if function is None or function.end_ea != end:
            raise RuntimeError("could not establish function bounds for %s" % name)
    function = ida_funcs.get_func(start)
    if function is None or function.end_ea != end:
        if function is not None:
            ida_funcs.set_func_end(start, end)
            function = ida_funcs.get_func(start)
        if function is None or function.end_ea != end:
            raise RuntimeError("IDA function boundary differs for %s" % name)
    ida_name.set_name(start, name, ida_name.SN_FORCE)
for address, name in data_aliases.items():
    if not ida_name.set_name(address, name, ida_name.SN_FORCE):
        raise RuntimeError("could not apply verified data alias %s at 0x%x" %
                           (name, address))
def read_c_string(ea):
    value = ida_bytes.get_bytes(ea, 64)
    if value is None or b"\\x00" not in value:
        return None
    try:
        return value.split(b"\\x00", 1)[0].decode("ascii")
    except UnicodeDecodeError:
        return None
for address, name in ida_data_aliases.items():
    superclass_name = ida_bytes.get_dword(address)
    class_name = ida_bytes.get_dword(address + 4)
    if (name != "ATI_BIOS_class_ext" or
            read_c_string(superclass_name) != "Object" or
            read_c_string(class_name) != "ATI_BIOS"):
        raise RuntimeError("verified class data alias failed identity check: " + name)
document = export_analysis.collect_analysis(Path(input_path), int(size), sha256,
                                            mapping=mapping)
for address, name in ida_data_aliases.items():
    if any(symbol["name"] == name for symbol in document["symbols"]):
        raise RuntimeError("verified class data alias already exists: " + name)
    document["symbols"].append({{"name": name, "address": address,
                                "binding": "local", "section": "__class"}})
if len(document["functions"]) != 54:
    raise RuntimeError("corrected IDA export does not contain 54 entries")
export_analysis._atomic_write(Path(output), document)
ida_pro.qexit(0)
'''


def export(profile_path, output_dir, *, runner=subprocess.run):
    profile_path = Path(profile_path).resolve(strict=True)
    profile = load_profile(profile_path, os.environ)
    identity = profile.reference_identity
    assert_identity(identity)
    ida = profile.document["analyzers"]["ida"]
    executable = Path(ida["executable"]).resolve(strict=True)
    output_dir = Path(output_dir).resolve(strict=False)
    output_dir.mkdir(parents=True, exist_ok=True)
    mapping = _mapping_manifest(profile, identity, "reference")
    mapping_bytes = (json.dumps(mapping, sort_keys=True, separators=(",", ":")) + "\n").encode()
    mapping_path = output_dir / "reference-mapping.json"
    mapping_path.write_bytes(mapping_bytes)
    mapping_sha = hashlib.sha256(mapping_bytes).hexdigest().upper()
    analysis_path = output_dir / "reference-ida.json"
    script_path = output_dir / "ida-export-runtime.py"
    database_path = output_dir / "reference-corrected.i64"
    log_path = output_dir / "reference-corrected.ida.log"
    script_path.write_text(_ida_script(analysis_path, identity.path, identity.size,
                                       identity.sha256, mapping_path, mapping_sha),
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
    normalize_analysis(document)
    assert_identity(identity)
    metadata = {
        "reference_sha256": identity.sha256,
        "ida_version": ida["version"],
        "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest().upper(),
        "database_sha256": hashlib.sha256(database_path.read_bytes()).hexdigest().upper(),
        "analysis_sha256": hashlib.sha256(analysis_path.read_bytes()).hexdigest().upper(),
        "function_count": len(document["functions"]),
        "verified_data_aliases": [
            {"address": address, "name": name}
            for address, name in {**REFERENCE_DATA_TARGETS,
                                  **REFERENCE_IDA_DATA_ALIASES}.items()
        ],
        "corrected_entries": [
            {"start": start, "end_exclusive": end, "symbol": name}
            for start, end, name in corrected_assembly_ranges()
        ],
    }
    (output_dir / "reference-ida-metadata.json").write_text(
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
        print(f"IDA export failed: {error}", file=sys.stderr)
        return 1
    print(f"IDA export complete: {result['function_count']} routines; "
          f"metadata={Path(args.output_dir) / 'reference-ida-metadata.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
