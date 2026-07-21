"""IDAPython analysis exporter; safe to import in a non-IDA Python process."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile


class ExportError(RuntimeError):
    """Raised when mandatory IDA data cannot be collected safely."""


def _arguments(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--size", type=int, required=True)
    parser.add_argument("--sha256", required=True)
    return parser.parse_args(argv)


def _ida_modules():
    try:
        import ida_auto
        import ida_bytes
        import ida_funcs
        import ida_gdl
        import ida_ida
        import ida_kernwin
        import ida_loader
        import ida_name
        import ida_nalt
        import ida_segment
        import idaapi
        import idautils
        import idc
    except ImportError as error:
        raise ExportError(f"mandatory IDAPython API unavailable: {error}") from error
    return {
        "ida_auto": ida_auto,
        "ida_bytes": ida_bytes,
        "ida_funcs": ida_funcs,
        "ida_gdl": ida_gdl,
        "ida_ida": ida_ida,
        "ida_kernwin": ida_kernwin,
        "ida_loader": ida_loader,
        "ida_name": ida_name,
        "ida_nalt": ida_nalt,
        "ida_segment": ida_segment,
        "idaapi": idaapi,
        "idautils": idautils,
        "idc": idc,
    }


def _file_identity(path):
    data = path.read_bytes()
    return len(data), hashlib.sha256(data).hexdigest().upper()


def _permissions(segment, ida_segment):
    return "".join(
        letter
        for flag, letter in (
            (ida_segment.SEGPERM_READ, "r"),
            (ida_segment.SEGPERM_WRITE, "w"),
            (ida_segment.SEGPERM_EXEC, "x"),
        )
        if segment.perm & flag
    )


def collect_analysis(input_path, expected_size, expected_sha256, modules=None):
    """Collect an analysis-v1 document from the current IDA database."""
    modules = modules or _ida_modules()
    size, digest = _file_identity(input_path)
    if size != expected_size or digest != expected_sha256.upper():
        raise ExportError("input identity does not match host request")
    if not modules["ida_auto"].auto_wait():
        raise ExportError("IDA auto-analysis did not complete")
    ida_segment = modules["ida_segment"]
    ida_bytes = modules["ida_bytes"]
    ida_funcs = modules["ida_funcs"]
    ida_gdl = modules["ida_gdl"]
    ida_loader = modules["ida_loader"]
    idautils = modules["idautils"]
    idc = modules["idc"]

    sections = []
    for start in idautils.Segments():
        segment = ida_segment.getseg(start)
        if segment is None:
            raise ExportError(f"could not read segment at {start:#x}")
        contents = ida_bytes.get_bytes(segment.start_ea, segment.end_ea - segment.start_ea)
        if contents is None:
            raise ExportError(f"could not read segment bytes at {segment.start_ea:#x}")
        file_offset = int(ida_loader.get_fileregion_offset(segment.start_ea))
        if file_offset < 0:
            raise ExportError(f"segment at {segment.start_ea:#x} has no file offset")
        sections.append({
            "name": ida_segment.get_segm_name(segment),
            "address": segment.start_ea,
            "offset": file_offset,
            "size": segment.end_ea - segment.start_ea,
            "permissions": _permissions(segment, ida_segment),
            "sha256": hashlib.sha256(contents).hexdigest().upper(),
        })

    symbols = []
    for address, name in idautils.Names():
        segment = ida_segment.getseg(address)
        symbols.append({
            "name": name,
            "address": address,
            "binding": "global" if modules["ida_name"].is_public_name(address) else "local",
            "section": ida_segment.get_segm_name(segment) if segment else None,
        })

    references = []
    for source in idautils.Heads():
        for target in idautils.CodeRefsFrom(source, False):
            references.append({"address": source, "target": target, "kind": "code"})
        for target in idautils.DataRefsFrom(source):
            references.append({"address": source, "target": target, "kind": "data"})

    functions = []
    for address in idautils.Functions():
        function = ida_funcs.get_func(address)
        if function is None:
            raise ExportError(f"could not read function at {address:#x}")
        blocks = []
        for block in ida_gdl.FlowChart(function):
            successors = [
                {"target": successor.start_ea, "kind": "flow"}
                for successor in block.succs()
            ]
            blocks.append({
                "address": block.start_ea,
                "size": block.end_ea - block.start_ea,
                "successors": sorted(successors, key=lambda item: (item["target"], item["kind"])),
            })
        instructions = []
        calls = []
        for item in idautils.FuncItems(address):
            raw = ida_bytes.get_bytes(item, ida_bytes.get_item_size(item))
            if not raw:
                raise ExportError(f"could not read instruction bytes at {item:#x}")
            mnemonic = idc.print_insn_mnem(item) or ""
            operand_values = []
            for operand_index in range(8):
                operand = idc.print_operand(item, operand_index) or ""
                if not operand:
                    break
                operand_values.append(operand)
            operands = ", ".join(operand_values)
            instructions.append({
                "address": item,
                "bytes": raw.hex().upper(),
                "mnemonic": mnemonic,
                "operands": operands,
                "normalized_operands": operands,
                "relocations": [],
            })
            if mnemonic.lower().startswith("call"):
                targets = sorted(idautils.CodeRefsFrom(item, False))
                target = targets[0] if len(targets) == 1 else None
                calls.append({
                    "address": item,
                    "target": target,
                    "name": modules["ida_name"].get_name(target) if target is not None else None,
                })
        names = sorted({name for ea, name in idautils.Names() if ea == address})
        functions.append({
            "address": function.start_ea,
            "size": function.end_ea - function.start_ea,
            "names": names,
            "blocks": sorted(blocks, key=lambda item: item["address"]),
            "instructions": sorted(instructions, key=lambda item: item["address"]),
            "calls": sorted(calls, key=lambda item: (item["address"], item["target"] or -1)),
            "confidence": 1.0,
        })

    strings = [
        {"address": int(item.ea), "value": str(item), "encoding": str(item.strtype)}
        for item in idautils.Strings()
    ]
    imports = []
    ida_nalt = modules["ida_nalt"]
    for module_index in range(ida_nalt.get_import_module_qty()):
        module_name = ida_nalt.get_import_module_name(module_index) or ""

        def add_import(address, name, ordinal, module_name=module_name):
            stable_name = name if name else f"ordinal-{ordinal}"
            qualified = f"{module_name}:{stable_name}" if module_name else stable_name
            imports.append({"name": qualified, "address": address})
            return True

        if ida_nalt.enum_import_names(module_index, add_import) <= 0:
            raise ExportError(f"could not enumerate imports for module {module_index}")
    selector_names = sorted({
        name
        for _, name in idautils.Names()
        if ":" in name or name.lower().startswith(("sel_", "selref_"))
    })
    version = str(modules["ida_kernwin"].get_kernel_version())
    return {
        "schema_version": "analysis-v1",
        "input": {
            "path": str(input_path.resolve()), "size": size, "sha256": digest,
            "architecture": "i386", "endianness": "little",
        },
        "analyzer": {"name": "IDA", "version": version, "invocation": "IDAPython export_analysis.py"},
        "sections": sorted(sections, key=lambda item: (item["address"], item["name"])),
        "symbols": sorted(symbols, key=lambda item: (item["address"], item["name"])),
        "relocations": [],
        "functions": sorted(functions, key=lambda item: item["address"]),
        "references": sorted(references, key=lambda item: (item["address"], item["target"], item["kind"])),
        "imports": sorted(imports, key=lambda item: (item["address"] if item["address"] is not None else -1, item["name"])),
        "strings": sorted(strings, key=lambda item: (item["address"], item["value"], item["encoding"])),
        "extensions": {"ida": {"selectors": selector_names}},
    }


def _atomic_write(path, document):
    descriptor, name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".write", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(document, stream, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
            stream.write("\n")
        os.replace(name, path)
    except BaseException:
        try:
            os.unlink(name)
        except FileNotFoundError:
            pass
        raise


def main(argv=None):
    arguments = _arguments(sys.argv[1:] if argv is None else argv)
    try:
        document = collect_analysis(
            arguments.input.resolve(strict=True), arguments.size, arguments.sha256
        )
        _atomic_write(arguments.output.resolve(strict=False), document)
        return 0
    except Exception as error:
        print(f"IDA export failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    exit_code = main()
    try:
        import ida_pro
        ida_pro.qexit(exit_code)
    except ImportError:
        raise SystemExit(exit_code)
