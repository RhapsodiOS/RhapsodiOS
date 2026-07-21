"""IDAPython analysis exporter; safe to import in a non-IDA Python process."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile


class ExportError(RuntimeError):
    """Raised when mandatory IDA data cannot be collected safely."""


_HASH_CHUNK_SIZE = 1024 * 1024


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
        import ida_fixup
        import ida_funcs
        import ida_gdl
        import ida_ida
        import ida_kernwin
        import ida_loader
        import ida_name
        import ida_nalt
        import ida_segment
        import ida_ua
        import idaapi
        import idautils
        import idc
    except ImportError as error:
        raise ExportError(f"mandatory IDAPython API unavailable: {error}") from error
    return {
        "ida_auto": ida_auto,
        "ida_bytes": ida_bytes,
        "ida_fixup": ida_fixup,
        "ida_funcs": ida_funcs,
        "ida_gdl": ida_gdl,
        "ida_ida": ida_ida,
        "ida_kernwin": ida_kernwin,
        "ida_loader": ida_loader,
        "ida_name": ida_name,
        "ida_nalt": ida_nalt,
        "ida_segment": ida_segment,
        "ida_ua": ida_ua,
        "idaapi": idaapi,
        "idautils": idautils,
        "idc": idc,
    }


def _file_identity(
    path,
    *,
    opener=os.open,
    fstat=os.fstat,
    reader=os.read,
    closer=os.close,
):
    flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NONBLOCK", 0)
    try:
        descriptor = opener(path, flags)
    except OSError as error:
        raise ExportError(f"could not open input for hashing: {error}") from error
    try:
        initial = fstat(descriptor)
        if not stat.S_ISREG(initial.st_mode):
            raise ExportError("input is not a regular file")
        digest = hashlib.sha256()
        size = 0
        while True:
            chunk = reader(descriptor, _HASH_CHUNK_SIZE)
            if not chunk:
                break
            if len(chunk) > _HASH_CHUNK_SIZE:
                raise ExportError("input reader returned an oversized chunk")
            digest.update(chunk)
            size += len(chunk)
        final = fstat(descriptor)
        stable_fields = ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns")
        if size != initial.st_size or any(
            getattr(initial, field) != getattr(final, field) for field in stable_fields
        ):
            raise ExportError("input changed while hashing")
        return size, digest.hexdigest().upper()
    finally:
        closer(descriptor)


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


def _hash_zeros(size):
    digest = hashlib.sha256()
    block = b"\0" * min(size, _HASH_CHUNK_SIZE)
    remaining = size
    while remaining:
        amount = min(remaining, len(block))
        digest.update(block[:amount])
        remaining -= amount
    return digest.hexdigest().upper()


def _hash_backed_segment(start, size, file_offset, ida_bytes, ida_loader):
    digest = hashlib.sha256()
    consumed = 0
    while consumed < size:
        amount = min(_HASH_CHUNK_SIZE, size - consumed)
        address = start + consumed
        if ida_loader.get_fileregion_offset(address) != file_offset + consumed:
            raise ExportError(f"discontiguous segment backing at {address:#x}")
        if (
            ida_loader.get_fileregion_offset(address + amount - 1)
            != file_offset + consumed + amount - 1
        ):
            raise ExportError(f"partially backed segment chunk at {address:#x}")
        contents = ida_bytes.get_bytes(address, amount)
        if contents is None or len(contents) != amount:
            raise ExportError(f"could not read exact segment bytes at {address:#x}")
        digest.update(contents)
        consumed += amount
    return digest.hexdigest().upper()


def _collect_relocations(modules):
    ida_fixup = modules["ida_fixup"]
    ida_name = modules["ida_name"]
    bad_address = modules["idaapi"].BADADDR
    type_names = {
        getattr(ida_fixup, constant): constant.removeprefix("FIXUP_").lower()
        for constant in (
            "FIXUP_OFF8", "FIXUP_OFF16", "FIXUP_SEG16", "FIXUP_PTR16",
            "FIXUP_OFF32", "FIXUP_PTR32", "FIXUP_HI8", "FIXUP_HI16",
            "FIXUP_LOW8", "FIXUP_LOW16", "FIXUP_OFF64", "FIXUP_OFF8S",
            "FIXUP_OFF16S", "FIXUP_OFF32S",
        )
    }
    result = []
    address = ida_fixup.get_first_fixup_ea()
    previous = None
    while address != bad_address:
        if (
            not isinstance(address, int)
            or address < 0
            or (previous is not None and address <= previous)
        ):
            raise ExportError("malformed IDA fixup enumeration")
        data = ida_fixup.fixup_data_t()
        if not ida_fixup.get_fixup(data, address):
            raise ExportError(f"could not read fixup at {address:#x}")
        type_ = data.get_type()
        if (
            not isinstance(type_, int)
            or type_ >= ida_fixup.FIXUP_CUSTOM
            or type_ not in type_names
        ):
            raise ExportError(f"unsupported fixup type {type_} at {address:#x}")
        size = ida_fixup.calc_fixup_size(type_)
        if not isinstance(size, int) or size <= 0:
            raise ExportError(f"malformed fixup size at {address:#x}")
        try:
            addend = data.get_value(address)
            base = data.get_base()
            offset = data.off
            relative = data.has_base()
            external = data.is_extdef()
        except Exception as error:
            raise ExportError(f"could not interpret fixup at {address:#x}: {error}") from error
        if (
            not isinstance(base, int)
            or not isinstance(offset, int)
            or base < 0
            or offset < 0
            or base == bad_address
            or offset == bad_address
            or base > 0xFFFFFFFF
            or offset > 0xFFFFFFFF - base
        ):
            raise ExportError(f"malformed fixup target at {address:#x}")
        target_address = base + offset
        if (
            not isinstance(addend, int)
            or not isinstance(target_address, int)
            or target_address < 0
        ):
            raise ExportError(f"malformed fixup fields at {address:#x}")
        target_name = ida_name.get_name(target_address) or ""
        if external:
            target = target_name or f"external:{target_address:08X}"
        else:
            target = target_name or f"address:{target_address:08X}"
        kind = f"ida-{type_names[type_]}-{size * 8}"
        if relative:
            kind += "-relative"
        result.append({
            "address": address,
            "kind": kind,
            "target": target,
            "addend": addend,
        })
        previous = address
        address = ida_fixup.get_next_fixup_ea(address)
    return sorted(result, key=lambda item: (item["address"], item["kind"], item["target"]))


def collect_analysis(input_path, expected_size, expected_sha256, modules=None):
    """Collect an analysis-v1 document from the current IDA database."""
    modules = modules or _ida_modules()
    size, digest = _file_identity(input_path)
    if size != expected_size or digest != expected_sha256.upper():
        raise ExportError("input identity does not match host request")
    try:
        database_size = modules["ida_nalt"].retrieve_input_file_size()
        database_sha = modules["ida_nalt"].retrieve_input_file_sha256()
        processor = modules["ida_ida"].inf_get_procname()
        exactly_32 = modules["ida_ida"].inf_is_32bit_exactly()
        big_endian = modules["ida_ida"].inf_is_be()
    except Exception as error:
        raise ExportError(f"could not validate IDA database identity: {error}") from error
    if database_size != expected_size:
        raise ExportError("IDA database input size does not match host request")
    if not isinstance(database_sha, bytes) or database_sha.hex().upper() != digest:
        raise ExportError("IDA database input sha256 does not match host request")
    if not isinstance(processor, str) or processor.lower() != "metapc":
        raise ExportError(f"IDA processor is not metapc: {processor!r}")
    if exactly_32 is not True:
        raise ExportError("IDA database is not exactly 32-bit")
    if big_endian is not False:
        raise ExportError("IDA database is not little-endian")
    if not modules["ida_auto"].auto_wait():
        raise ExportError("IDA auto-analysis did not complete")
    ida_segment = modules["ida_segment"]
    ida_bytes = modules["ida_bytes"]
    ida_funcs = modules["ida_funcs"]
    ida_gdl = modules["ida_gdl"]
    ida_loader = modules["ida_loader"]
    ida_ua = modules["ida_ua"]
    idautils = modules["idautils"]
    idc = modules["idc"]

    sections = []
    zero_fill_sections = []
    for start in idautils.Segments():
        segment = ida_segment.getseg(start)
        if segment is None:
            raise ExportError(f"could not read segment at {start:#x}")
        segment_size = segment.end_ea - segment.start_ea
        if segment_size < 0:
            raise ExportError(f"segment at {segment.start_ea:#x} has invalid size")
        file_offset = int(ida_loader.get_fileregion_offset(segment.start_ea))
        if file_offset < 0:
            segment_class = ida_segment.get_segm_class(segment).upper()
            if segment.type != ida_segment.SEG_BSS and segment_class not in ("BSS", "COMMON"):
                raise ExportError(f"unbacked non-zero-fill segment at {segment.start_ea:#x}")
            contents_hash = _hash_zeros(segment_size)
            schema_offset = 0
            zero_fill_sections.append({
                "address": segment.start_ea,
                "name": ida_segment.get_segm_name(segment),
                "size": segment_size,
            })
        else:
            contents_hash = _hash_backed_segment(
                segment.start_ea, segment_size, file_offset, ida_bytes, ida_loader
            )
            schema_offset = file_offset
        sections.append({
            "name": ida_segment.get_segm_name(segment),
            "address": segment.start_ea,
            "offset": schema_offset,
            "size": segment_size,
            "permissions": _permissions(segment, ida_segment),
            "sha256": contents_hash,
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

    relocations = _collect_relocations(modules)

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
            flags = ida_bytes.get_flags(item)
            if not ida_bytes.is_code(flags):
                continue
            item_size = ida_bytes.get_item_size(item)
            if not isinstance(item_size, int) or item_size <= 0:
                raise ExportError(f"invalid instruction size at {item:#x}")
            raw = ida_bytes.get_bytes(item, item_size)
            if raw is None or len(raw) != item_size:
                raise ExportError(f"could not read exact instruction bytes at {item:#x}")
            instruction = ida_ua.insn_t()
            if ida_ua.decode_insn(instruction, item) != item_size:
                raise ExportError(f"could not decode instruction at {item:#x}")
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
                "relocations": [
                    index
                    for index, relocation in enumerate(relocations)
                    if item <= relocation["address"] < item + len(raw)
                ],
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

    ida_nalt = modules["ida_nalt"]
    string_list = idautils.Strings(default_setup=False)
    string_list.setup(
        strtypes=[ida_nalt.STRTYPE_C],
        minlen=1,
        only_7bit=True,
        ignore_instructions=True,
        display_only_existing_strings=False,
    )
    strings = [
        {"address": int(item.ea), "value": str(item), "encoding": str(item.strtype)}
        for item in string_list
    ]
    imports = []
    for module_index in range(ida_nalt.get_import_module_qty()):
        module_name = ida_nalt.get_import_module_name(module_index) or ""

        def add_import(address, name, ordinal, module_name=module_name):
            stable_name = name if name else f"ordinal-{ordinal}"
            qualified = f"{module_name}:{stable_name}" if module_name else stable_name
            imports.append({"name": qualified, "address": address})
            return True

        if ida_nalt.enum_import_names(module_index, add_import) <= 0:
            raise ExportError(f"could not enumerate imports for module {module_index}")
    selector_names = []
    for _, name in idautils.Names():
        lowered = name.lower()
        selector = None
        for prefix in (
            "selref_", "sel_", "_objc_selector_references_",
            "objc_selector_references_",
        ):
            if lowered.startswith(prefix):
                selector = name[len(prefix):] or None
                break
        if selector is None:
            method = re.fullmatch(r"[+-]\[[^\s\]]+\s+([^\]]+)\]", name)
            selector = method.group(1) if method else None
        if selector:
            selector_names.append(selector)
    for string in strings:
        segment = ida_segment.getseg(string["address"])
        if segment is not None:
            section_name = ida_segment.get_segm_name(segment).lower().split(",")[-1]
            if section_name in ("__objc_methname", "__meth_var_names"):
                selector_names.append(string["value"])
    selector_names = sorted(set(selector_names))
    version = modules["ida_kernwin"].get_kernel_version()
    if not isinstance(version, str) or not version:
        raise ExportError("could not read IDA kernel version")
    return {
        "schema_version": "analysis-v1",
        "input": {
            "path": str(input_path.resolve()), "size": size, "sha256": digest,
            "architecture": "i386", "endianness": "little",
        },
        "analyzer": {
            "name": "IDA", "version": version,
            "invocation": "IDAPython export_analysis.py",
        },
        "sections": sorted(sections, key=lambda item: (item["address"], item["name"])),
        "symbols": sorted(symbols, key=lambda item: (item["address"], item["name"])),
        "relocations": relocations,
        "functions": sorted(functions, key=lambda item: item["address"]),
        "references": sorted(
            references,
            key=lambda item: (item["address"], item["target"], item["kind"]),
        ),
        "imports": sorted(
            imports,
            key=lambda item: (
                item["address"] if item["address"] is not None else -1,
                item["name"],
            ),
        ),
        "strings": sorted(
            strings,
            key=lambda item: (item["address"], item["value"], item["encoding"]),
        ),
        "extensions": {"ida": {
            "selectors": selector_names,
            "zero_fill_sections": sorted(
                zero_fill_sections, key=lambda item: (item["address"], item["name"])
            ),
        }},
    }


def _atomic_write(path, document):
    descriptor, name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".write", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(document, stream, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    except BaseException:
        try:
            os.unlink(name)
        except FileNotFoundError:
            pass
        raise


def main(argv=None):
    try:
        if argv is None:
            import idc

            runtime_argv = getattr(idc, "ARGV", None)
            if not isinstance(runtime_argv, (list, tuple)) or not runtime_argv:
                raise ExportError("idc.ARGV is unavailable or malformed")
            argv = list(runtime_argv[1:])
        arguments = _arguments(argv)
        document = collect_analysis(
            arguments.input.resolve(strict=True), arguments.size, arguments.sha256
        )
        _atomic_write(arguments.output.resolve(strict=False), document)
        return 0
    except SystemExit as error:
        return int(error.code) if isinstance(error.code, int) else 2
    except Exception as error:
        print(f"IDA export failed: {error}", file=sys.stderr)
        return 1


def ida_entrypoint():
    result = main()
    import ida_pro

    ida_pro.qexit(result)
    return result


if __name__ == "__main__":
    ida_entrypoint()
