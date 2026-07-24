"""IDAPython analysis exporter; safe to import in a non-IDA Python process."""

from __future__ import annotations

import argparse
from bisect import bisect_right
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
_MAX_ARTIFACT_BYTES = 256 * 1024 * 1024
_MAX_MAPPING_BYTES = 1024 * 1024


def _arguments(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--size", type=int, required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--mapping", type=Path, required=True)
    parser.add_argument("--mapping-sha256", required=True)
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


def _file_snapshot(
    path,
    *,
    expected_size=None,
    opener=os.open,
    fstat=os.fstat,
    reader=os.read,
    closer=os.close,
):
    if expected_size is not None and (
        not isinstance(expected_size, int)
        or isinstance(expected_size, bool)
        or expected_size < 0
    ):
        raise ExportError("host request size is invalid")
    if expected_size is not None and expected_size > _MAX_ARTIFACT_BYTES:
        raise ExportError("host request exceeds maximum artifact size")
    flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NONBLOCK", 0)
    try:
        descriptor = opener(path, flags)
    except OSError as error:
        raise ExportError(f"could not open input for hashing: {error}") from error
    try:
        initial = fstat(descriptor)
        if not stat.S_ISREG(initial.st_mode):
            raise ExportError("input is not a regular file")
        if initial.st_size > _MAX_ARTIFACT_BYTES:
            raise ExportError("input exceeds maximum artifact size")
        if expected_size is not None and initial.st_size != expected_size:
            raise ExportError("input size does not match host request")
        digest = hashlib.sha256()
        snapshot = bytearray(initial.st_size)
        size = 0
        while size < initial.st_size:
            request = min(_HASH_CHUNK_SIZE, initial.st_size - size)
            chunk = reader(descriptor, request)
            if not chunk:
                break
            if len(chunk) > request:
                raise ExportError("input reader returned an oversized chunk")
            snapshot[size:size + len(chunk)] = chunk
            digest.update(chunk)
            size += len(chunk)
        final = fstat(descriptor)
        stable_fields = ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns")
        if size != initial.st_size or any(
            getattr(initial, field) != getattr(final, field) for field in stable_fields
        ):
            raise ExportError("input changed while hashing")
        return memoryview(snapshot).toreadonly(), digest.hexdigest().upper()
    finally:
        closer(descriptor)


def _file_identity(path, **kwargs):
    snapshot, digest = _file_snapshot(path, **kwargs)
    return len(snapshot), digest


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


def _artifact_bytes(snapshot, offset, size, context):
    if (
        not isinstance(offset, int)
        or not isinstance(size, int)
        or offset < 0
        or size < 0
        or offset > len(snapshot)
        or size > len(snapshot) - offset
    ):
        raise ExportError(f"{context} is outside artifact backing")
    return snapshot[offset:offset + size]


class _MappingRuns(list):
    def __init__(self, runs):
        super().__init__(runs)
        self.starts = tuple(run["address"] for run in runs)


def _covering_run(runs, address, size, context):
    starts = runs.starts if isinstance(runs, _MappingRuns) else tuple(
        run["address"] for run in runs)
    position = bisect_right(starts, address) - 1
    if position < 0:
        raise ExportError(f"{context} is not wholly covered by one artifact mapping run")
    run = runs[position]
    if address + size > run["address"] + run["size"]:
        raise ExportError(f"{context} is not wholly covered by one artifact mapping run")
    return run


def _mapped_artifact_bytes(snapshot, address, size, runs, context):
    run = _covering_run(runs, address, size, context)
    offset = run["offset"] + address - run["address"]
    return _artifact_bytes(snapshot, offset, size, context)


def _hash_backed_segment(start, size, snapshot, runs):
    run = _covering_run(runs, start, size, "segment backing")
    file_start = run["offset"] + start - run["address"]
    digest = hashlib.sha256()
    consumed = 0
    while consumed < size:
        amount = min(_HASH_CHUNK_SIZE, size - consumed)
        contents = _artifact_bytes(snapshot, file_start + consumed, amount,
                                   "segment backing")
        digest.update(contents)
        consumed += amount
    return digest.hexdigest().upper()


def _validate_mapping(mapping, size, digest):
    if (not isinstance(mapping, dict) or set(mapping) != {"schema_version", "input", "runs"}
            or mapping["schema_version"] != "ida-mapping-v1"):
        raise ExportError("artifact mapping manifest is malformed")
    identity = mapping["input"]
    if (not isinstance(identity, dict) or
            set(identity) != {"size", "sha256", "architecture", "endianness"} or
            identity["size"] != size or str(identity["sha256"]).upper() != digest or
            identity["architecture"] != "i386" or identity["endianness"] != "little"):
        raise ExportError("artifact mapping identity does not match analyzed input")
    runs = mapping["runs"]
    if not isinstance(runs, list) or not runs or len(runs) > 4096:
        raise ExportError("artifact mapping runs are missing or excessive")
    expected = []
    for run in runs:
        if (not isinstance(run, dict) or set(run) != {"address", "offset", "size"} or
                any(not isinstance(run.get(key), int) or isinstance(run.get(key), bool)
                    or run[key] < 0 for key in ("address", "offset", "size")) or
                run["size"] == 0 or run["offset"] > size or run["size"] > size - run["offset"]):
            raise ExportError("artifact mapping run is invalid")
        expected.append(dict(run))
    ordered = sorted(expected, key=lambda item: (item["address"], item["offset"], item["size"]))
    if expected != ordered:
        raise ExportError("artifact mapping runs are not canonical")
    for left, right in zip(ordered, ordered[1:]):
        if left["address"] + left["size"] > right["address"]:
            raise ExportError("artifact mapping virtual runs overlap")
    by_file = sorted(ordered, key=lambda item: (item["offset"], item["address"], item["size"]))
    if any(left["offset"] + left["size"] > right["offset"]
           for left, right in zip(by_file, by_file[1:])):
        raise ExportError("artifact mapping file runs overlap")
    return _MappingRuns(ordered)


def _load_mapping(path, expected_sha256, *, opener=os.open, fstat=os.fstat,
                  reader=os.read, closer=os.close):
    flags = (os.O_RDONLY | getattr(os, "O_BINARY", 0) |
             getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOFOLLOW", 0))
    try:
        descriptor = opener(path, flags)
    except OSError as error:
        raise ExportError(f"could not open artifact mapping manifest: {error}") from error
    try:
        initial = fstat(descriptor)
        reparse = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
        if (not stat.S_ISREG(initial.st_mode) or initial.st_nlink != 1 or
                getattr(initial, "st_file_attributes", 0) & reparse):
            raise ExportError("artifact mapping manifest is not a private regular file")
        if initial.st_size > _MAX_MAPPING_BYTES:
            raise ExportError("artifact mapping manifest exceeds maximum size")
        chunks, total = [], 0
        while total < initial.st_size:
            chunk = reader(descriptor, min(_HASH_CHUNK_SIZE, initial.st_size - total))
            if not chunk:
                break
            chunks.append(chunk); total += len(chunk)
        final = fstat(descriptor)
        stable = ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns", "st_nlink")
        if total != initial.st_size or any(getattr(initial, key) != getattr(final, key)
                                           for key in stable):
            raise ExportError("artifact mapping manifest changed while reading")
        raw = b"".join(chunks)
        if hashlib.sha256(raw).hexdigest().upper() != expected_sha256.upper():
            raise ExportError("artifact mapping manifest hash does not match host request")
        value = json.loads(raw.decode("utf-8"))
    except ExportError:
        raise
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ExportError(f"could not read artifact mapping manifest: {error}") from error
    finally:
        closer(descriptor)
    return value


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


def collect_analysis(input_path, expected_size, expected_sha256, modules=None, mapping=None):
    """Collect an analysis-v1 document from the current IDA database."""
    modules = modules or _ida_modules()
    snapshot, digest = _file_snapshot(input_path, expected_size=expected_size)
    size = len(snapshot)
    if size != expected_size or digest != expected_sha256.upper():
        raise ExportError("input identity does not match host request")
    mapping = mapping if mapping is not None else modules.get("artifact_mapping")
    runs = _validate_mapping(mapping, size, digest)
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
    section_backing = []
    zero_fill_sections = []
    for start in idautils.Segments():
        segment = ida_segment.getseg(start)
        if segment is None:
            raise ExportError(f"could not read segment at {start:#x}")
        segment_size = segment.end_ea - segment.start_ea
        if segment_size < 0:
            raise ExportError(f"segment at {segment.start_ea:#x} has invalid size")
        segment_class = str(ida_segment.get_segm_class(segment) or "").upper()
        zero_fill = (
            segment.type == ida_segment.SEG_BSS
            or segment.type == getattr(ida_segment, "SEG_XTRN", None)
            or segment_class in ("BSS", "COMMON", "XTRN", "EXTERN")
        )
        if zero_fill:
            contents_hash = _hash_zeros(segment_size)
            schema_offset = 0
            zero_fill_sections.append({
                "address": segment.start_ea,
                "name": ida_segment.get_segm_name(segment),
                "size": segment_size,
            })
        else:
            contents_hash = _hash_backed_segment(
                segment.start_ea, segment_size, snapshot, runs
            )
            covering = _covering_run(runs, segment.start_ea, segment_size,
                                     "segment backing")
            schema_offset = covering["offset"] + segment.start_ea - covering["address"]
        segment_name = ida_segment.get_segm_name(segment)
        sections.append({
            "name": segment_name,
            "address": segment.start_ea,
            "offset": schema_offset,
            "size": segment_size,
            "permissions": _permissions(segment, ida_segment),
            "sha256": contents_hash,
        })
        section_backing.append({
            "name": segment_name, "address": segment.start_ea,
            "offset": schema_offset, "size": segment_size,
            "zero_fill": zero_fill, "initialized": not zero_fill,
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
    seen_functions = set()
    for address in idautils.Functions():
        function = ida_funcs.get_func(address)
        if function is None:
            raise ExportError(f"could not read function at {address:#x}")
        canonical_entry = function.start_ea
        if canonical_entry in seen_functions:
            continue
        seen_functions.add(canonical_entry)
        blocks = []
        minimum_start = function.start_ea
        maximum_end = function.end_ea
        for block in ida_gdl.FlowChart(function, flags=ida_gdl.FC_NOEXT):
            minimum_start = min(minimum_start, block.start_ea)
            maximum_end = max(maximum_end, block.end_ea)
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
        for item in idautils.FuncItems(canonical_entry):
            flags = ida_bytes.get_flags(item)
            if not ida_bytes.is_code(flags):
                continue
            item_size = ida_bytes.get_item_size(item)
            if not isinstance(item_size, int) or item_size <= 0:
                raise ExportError(f"invalid instruction size at {item:#x}")
            raw = _mapped_artifact_bytes(
                snapshot, item, item_size, runs,
                "instruction backing",
            )
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
        names = sorted({name for ea, name in idautils.Names() if ea == canonical_entry})
        functions.append({
            "address": minimum_start,
            "size": maximum_end - minimum_start,
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
            "sections": sorted(
                section_backing, key=lambda item: (item["address"], item["name"])
            ),
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
            arguments.input.resolve(strict=True), arguments.size, arguments.sha256,
            mapping=_load_mapping(arguments.mapping, arguments.mapping_sha256),
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
