import hashlib
from pathlib import Path
import struct
from typing import Any

from . import __version__
from .arch import Architecture, ArchitectureError, architecture_for_cpu_type
from .identity import identify


MH_MAGIC = 0xFEEDFACE
MH_OBJECT = 1
MH_EXECUTE = 2
MH_PRELOAD = 5
MH_BUNDLE = 8
LC_SEGMENT = 1
LC_SYMTAB = 2
LC_UNIXTHREAD = 5
S_ZEROFILL = 0x1
S_GB_ZEROFILL = 0xC
S_THREAD_LOCAL_ZEROFILL = 0x12

_ZERO_FILL_TYPES = frozenset(
    (S_ZEROFILL, S_GB_ZEROFILL, S_THREAD_LOCAL_ZEROFILL)
)
_HASH_CHUNK_SIZE = 1024 * 1024


class MachOFormatError(ValueError):
    """Raised when an input is not a supported, well-formed Mach-O object."""


def _select_architecture(data: bytes) -> Architecture:
    """Identify the image's architecture from its magic and CPU type."""
    if len(data) < 8:
        raise MachOFormatError("input is shorter than a Mach-O header identity")
    for endianness, prefix in (("big", ">"), ("little", "<")):
        magic, cpu_type = struct.unpack_from(f"{prefix}2I", data, 0)
        if magic == MH_MAGIC:
            try:
                return architecture_for_cpu_type(cpu_type, endianness)
            except ArchitectureError as error:
                raise MachOFormatError(str(error)) from error
    (raw,) = struct.unpack_from(">I", data, 0)
    raise MachOFormatError(
        f"unsupported Mach-O magic 0x{raw:08x}; expected 32-bit i386 or ppc"
    )


def _checked_slice(
    data: bytes,
    offset: int,
    size: int,
    context: str,
    *,
    limit: int | None = None,
) -> bytes:
    boundary = len(data) if limit is None else limit
    if offset < 0 or size < 0 or boundary < 0 or boundary > len(data):
        raise MachOFormatError(
            f"{context}: invalid range at file offset 0x{max(offset, 0):x}"
        )
    if offset > boundary or size > boundary - offset:
        raise MachOFormatError(
            f"{context}: range at file offset 0x{offset:x} extends beyond "
            f"0x{boundary:x}"
        )
    return data[offset : offset + size]


def _unpack(
    layout: struct.Struct,
    data: bytes,
    offset: int,
    context: str,
    *,
    limit: int | None = None,
) -> tuple[Any, ...]:
    return layout.unpack(_checked_slice(data, offset, layout.size, context, limit=limit))


def _decode_fixed_name(raw: bytes, context: str) -> str:
    value = raw.split(b"\0", 1)[0]
    try:
        return value.decode("ascii")
    except UnicodeDecodeError as error:
        raise MachOFormatError(f"{context}: name is not ASCII") from error


def _permissions(protection: int) -> str:
    return "".join(
        letter for bit, letter in ((1, "r"), (2, "w"), (4, "x")) if protection & bit
    )


def _hash_zeros(size: int) -> str:
    """Hash logical zero-fill contents in bounded-memory chunks."""
    digest = hashlib.sha256()
    zeros = b"\0" * min(size, _HASH_CHUNK_SIZE)
    remaining = size
    while remaining:
        chunk_size = min(remaining, len(zeros))
        digest.update(zeros[:chunk_size])
        remaining -= chunk_size
    return digest.hexdigest().upper()


def _command_record(
    command: int, offset: int, raw_command: bytes, reason: str
) -> dict[str, Any]:
    return {
        "command": command,
        "offset": offset,
        "size": len(raw_command),
        "bytes": raw_command.hex().upper(),
        "reason": reason,
    }


def read_macho(path: Path) -> dict[str, Any]:
    identity = identify(Path(path))
    data = identity.path.read_bytes()
    digest = hashlib.sha256(data).hexdigest().upper()
    if len(data) != identity.size or digest != identity.sha256:
        raise MachOFormatError(f"input changed while reading: {identity.path}")

    architecture = _select_architecture(data)
    layouts = architecture.layouts
    (
        magic,
        cpu_type,
        cpu_subtype,
        file_type,
        command_count,
        commands_size,
        flags,
    ) = _unpack(layouts.header, data, 0, "Mach-O header")
    if file_type not in (MH_OBJECT, MH_PRELOAD, MH_BUNDLE, MH_EXECUTE):
        raise MachOFormatError(
            f"unsupported Mach-O file type {file_type}; "
            "expected MH_OBJECT, MH_PRELOAD, MH_BUNDLE or MH_EXECUTE"
        )

    command_start = layouts.header.size
    table_context = (
        "load command 0 declared load-command table"
        if command_count
        else "declared load-command table"
    )
    _checked_slice(data, command_start, commands_size, table_context)
    command_end = command_start + commands_size
    cursor = command_start
    raw_segments: list[dict[str, Any]] = []
    raw_sections: list[dict[str, Any]] = []
    symtab: tuple[int, int, int, int, int] | None = None
    unparsed: list[dict[str, Any]] = []

    for command_index in range(command_count):
        context = f"load command {command_index}"
        command, command_size = _unpack(
            layouts.load_command, data, cursor, context, limit=command_end
        )
        if command_size < layouts.load_command.size:
            raise MachOFormatError(
                f"{context}: invalid size {command_size} at file offset 0x{cursor:x}"
            )
        raw_command = _checked_slice(
            data,
            cursor,
            command_size,
            f"{context} in declared load-command table",
            limit=command_end,
        )

        if command == LC_SEGMENT:
            values = _unpack(
                layouts.segment_command, data, cursor, context, limit=cursor + command_size
            )
            (_, _, segment_name_raw, segment_address, segment_size,
             segment_offset, segment_file_size, _maximum_protection,
             initial_protection, section_count, segment_flags) = values
            segment_ordinal = len(raw_segments) + 1
            raw_segments.append({
                "ordinal": segment_ordinal,
                "name": _decode_fixed_name(segment_name_raw, context),
                "address": segment_address,
                "offset": segment_offset,
                "size": segment_size,
                "file_size": segment_file_size,
                "permissions": _permissions(initial_protection),
                "flags": segment_flags,
            })
            section_table_offset = cursor + layouts.segment_command.size
            available = command_size - layouts.segment_command.size
            if section_count > available // layouts.section.size:
                raise MachOFormatError(
                    f"{context}: section table does not fit command at file offset "
                    f"0x{cursor:x}"
                )
            expected_size = layouts.segment_command.size + section_count * layouts.section.size
            if expected_size != command_size:
                raise MachOFormatError(
                    f"{context}: segment size does not match section count at file "
                    f"offset 0x{cursor:x}"
                )
            for section_in_segment in range(section_count):
                section_offset = section_table_offset + section_in_segment * layouts.section.size
                section_context = f"{context} section {section_in_segment}"
                section_values = _unpack(
                    layouts.section,
                    data,
                    section_offset,
                    section_context,
                    limit=cursor + command_size,
                )
                (
                    section_name_raw,
                    segment_name_raw,
                    address,
                    size,
                    file_offset,
                    alignment_exponent,
                    relocation_offset,
                    relocation_count,
                    section_flags,
                    _reserved1,
                    _reserved2,
                ) = section_values
                if alignment_exponent > 31:
                    raise MachOFormatError(
                        f"{section_context}: alignment exponent exceeds 32-bit address width "
                        f"at file offset 0x{section_offset:x}"
                    )
                if size > 0x1_0000_0000 - address:
                    raise MachOFormatError(
                        f"{section_context}: virtual range wraps 32-bit address space "
                        f"at file offset 0x{section_offset:x}"
                    )
                zero_fill = section_flags & 0xFF in _ZERO_FILL_TYPES
                if zero_fill:
                    contents_hash = _hash_zeros(size)
                else:
                    contents = _checked_slice(
                        data, file_offset, size, f"{section_context} contents"
                    )
                    contents_hash = hashlib.sha256(contents).hexdigest().upper()
                raw_sections.append(
                    {
                        "ordinal": len(raw_sections) + 1,
                        "segment_ordinal": segment_ordinal,
                        "name": (
                            f"{_decode_fixed_name(segment_name_raw, section_context)},"
                            f"{_decode_fixed_name(section_name_raw, section_context)}"
                        ),
                        "address": address,
                        "offset": file_offset,
                        "size": size,
                        "permissions": _permissions(initial_protection),
                        "sha256": contents_hash,
                        "relocation_offset": relocation_offset,
                        "relocation_count": relocation_count,
                        "flags": section_flags,
                        "alignment_exponent": alignment_exponent,
                        "zero_fill": zero_fill,
                        "command_index": command_index,
                        "section_in_segment": section_in_segment,
                    }
                )
        elif command == LC_SYMTAB:
            if command_size != layouts.symtab_command.size:
                raise MachOFormatError(
                    f"{context}: invalid symtab command size at file offset 0x{cursor:x}"
                )
            if symtab is not None:
                raise MachOFormatError(
                    f"{context}: duplicate symbol table at file offset 0x{cursor:x}"
                )
            _, _, symbol_offset, symbol_count, string_offset, string_size = _unpack(
                layouts.symtab_command, data, cursor, context, limit=cursor + command_size
            )
            symtab = (
                command_index,
                symbol_offset,
                symbol_count,
                string_offset,
                string_size,
            )
        elif command == LC_UNIXTHREAD:
            if command_size < 16:
                raise MachOFormatError(
                    f"{context}: truncated thread flavor at file offset 0x{cursor:x}"
                )
            unparsed.append(
                _command_record(command, cursor, raw_command, "unknown-thread-flavor")
            )
        else:
            unparsed.append(
                _command_record(command, cursor, raw_command, "unknown-load-command")
            )
        cursor += command_size

    if cursor != command_end:
        raise MachOFormatError(
            f"load commands consume 0x{cursor - command_start:x} bytes, but declared "
            f"load-command table has 0x{commands_size:x} bytes at file offset "
            f"0x{command_start:x}"
        )

    symbols, symbol_names = _read_symbols(data, symtab, raw_sections, layouts)
    relocations, raw_relocations = _read_relocations(
        data, raw_sections, symbol_names, architecture
    )
    section_fields = ("name", "address", "offset", "size", "permissions", "sha256")
    sections = [
        {key: section[key] for key in section_fields} for section in raw_sections
    ]
    return {
        "schema_version": "analysis-v1",
        "input": {
            "path": str(identity.path),
            "size": identity.size,
            "sha256": identity.sha256,
            "architecture": architecture.name,
            "endianness": architecture.endianness,
        },
        "analyzer": {
            "name": "binrecon-macho",
            "version": __version__,
            "invocation": "binrecon.macho.read_macho",
        },
        "sections": sorted(
            sections,
            key=lambda item: (
                item["address"], item["offset"], item["name"], item["size"],
                item["permissions"], item["sha256"],
            ),
        ),
        "symbols": sorted(
            symbols,
            key=lambda item: (
                item["address"], item["name"], item["binding"], item["section"] or "",
            ),
        ),
        "relocations": sorted(
            relocations,
            key=lambda item: (
                item["address"],
                item["kind"],
                item["target"] or "",
                item["addend"],
            ),
        ),
        "functions": [],
        "extensions": {
            "macho": {
                "header": {
                    "magic": magic,
                    "cpu_type": cpu_type,
                    "cpu_subtype": cpu_subtype,
                    "file_type": file_type,
                    "flags": flags,
                },
                "unparsed_load_commands": unparsed,
                "segments": sorted(
                    raw_segments,
                    key=lambda item: (
                        item["address"], item["offset"], item["name"], item["size"],
                        item["ordinal"], item["file_size"], item["permissions"],
                        item["flags"],
                    ),
                ),
                "sections": sorted(
                    [
                        {
                            "name": section["name"],
                            "ordinal": section["ordinal"],
                            "segment_ordinal": section["segment_ordinal"],
                            "address": section["address"],
                            "offset": section["offset"],
                            "size": section["size"],
                            "alignment_exponent": section["alignment_exponent"],
                            "alignment": 1 << section["alignment_exponent"],
                            "flags": section["flags"],
                            "type": section["flags"] & 0xFF,
                            "zero_fill": section["zero_fill"],
                            "initialized": not section["zero_fill"],
                        }
                        for section in raw_sections
                    ],
                    key=lambda item: (
                        item["address"], item["name"], item["alignment_exponent"],
                        item["ordinal"], item["offset"], item["size"], item["alignment"],
                        item["flags"], item["type"],
                        item["zero_fill"], item["initialized"],
                    ),
                ),
                "relocations": sorted(
                    raw_relocations,
                    key=lambda item: (
                        item["address"], item["kind"], item["target"] or "",
                        item["addend"], item["type"], item["section"],
                        item["section_ordinal"], item["external"],
                        -1 if item["target_section_ordinal"] is None else item["target_section_ordinal"],
                        item["pc_relative"], item["width"], item["original_bytes"],
                    ),
                ),
            }
        },
    }


_MODULE_INFO_SECTION = "__OBJC,__module_info"
_OBJC_STRUCTS = {
    "little": {"module": struct.Struct("<4I"), "klass": struct.Struct("<8I"),
               "category": struct.Struct("<4I"), "counts": struct.Struct("<HH"),
               "list_header": struct.Struct("<2I"), "method": struct.Struct("<3I")},
    "big": {"module": struct.Struct(">4I"), "klass": struct.Struct(">8I"),
            "category": struct.Struct(">4I"), "counts": struct.Struct(">HH"),
            "list_header": struct.Struct(">2I"), "method": struct.Struct(">3I")},
}


def objc_methods_from_sections(payload, sections, endianness="little"):
    """Map each Objective-C method implementation address to its names.

    A linked executable names no methods in its symbol table, so the runtime
    metadata is the only source of address-to-name for them.
    """
    layout = _OBJC_STRUCTS[endianness]
    spans = [s for s in sections if s.get("size")]

    def offset_of(address):
        for span in spans:
            start = span["address"]
            if start <= address < start + span["size"]:
                return span["offset"] + (address - start)
        return None

    def read(structure, address):
        offset = offset_of(address)
        if offset is None or offset + structure.size > len(payload):
            return None
        return structure.unpack_from(payload, offset)

    def text(address):
        offset = offset_of(address)
        if offset is None:
            return None
        end = payload.find(b"\0", offset)
        if end < 0:
            return None
        return payload[offset:end].decode("latin1")

    index = {}

    def collect(list_address, owner, sign):
        if not list_address:
            return
        offset = offset_of(list_address)
        if offset is None or offset + 8 > len(payload):
            return
        _, count = layout["list_header"].unpack_from(payload, offset)
        for entry in range(count):
            base = offset + 8 + entry * 12
            if base + 12 > len(payload):
                return
            selector_address, _types, imp = layout["method"].unpack_from(payload, base)
            selector = text(selector_address)
            if not selector or not imp:
                continue
            index.setdefault(imp, set()).add(f"{sign}[{owner} {selector}]")

    module_section = next(
        (s for s in sections if s["name"] == _MODULE_INFO_SECTION), None
    )
    if module_section is None:
        return {}

    for ordinal in range(module_section["size"] // layout["module"].size):
        module_offset = module_section["offset"] + ordinal * layout["module"].size
        if module_offset + layout["module"].size > len(payload):
            break
        _version, _size, _name, symtab = layout["module"].unpack_from(payload, module_offset)
        symtab_offset = offset_of(symtab) if symtab else None
        if symtab_offset is None:
            continue
        if symtab_offset + 12 > len(payload):
            continue
        class_count, category_count = layout["counts"].unpack_from(payload, symtab_offset + 8)
        total = class_count + category_count
        if symtab_offset + 12 + total * 4 > len(payload):
            continue
        definitions = struct.unpack_from(
            f"{'>' if endianness == 'big' else '<'}{total}I", payload, symtab_offset + 12
        ) if total else ()

        for position, definition in enumerate(definitions):
            if position < class_count:
                fields = read(layout["klass"], definition)
                if fields is None:
                    continue
                isa, _super, name_address = fields[0], fields[1], fields[2]
                owner = text(name_address)
                if not owner:
                    continue
                collect(fields[7], owner, "-")
                metaclass = read(layout["klass"], isa) if isa else None
                if metaclass is not None:
                    collect(metaclass[7], owner, "+")
            else:
                fields = read(layout["category"], definition)
                if fields is None:
                    continue
                category_name, class_name, instance_methods, class_methods = fields
                owner_class = text(class_name)
                owner_category = text(category_name)
                if not owner_class or not owner_category:
                    continue
                owner = f"{owner_class}({owner_category})"
                collect(instance_methods, owner, "-")
                collect(class_methods, owner, "+")

    return {address: sorted(names) for address, names in index.items()}


def objc_method_index(path):
    """Map each Objective-C method implementation address to its names."""
    document = read_macho(path)
    return objc_methods_from_sections(
        Path(path).read_bytes(), document["sections"],
        endianness=document["input"]["endianness"],
    )


def _read_symbols(
    data: bytes,
    symtab: tuple[int, int, int, int, int] | None,
    sections: list[dict[str, Any]],
    layouts,
) -> tuple[list[dict[str, Any]], list[str]]:
    if symtab is None:
        return [], []
    command_index, symbol_offset, symbol_count, string_offset, string_size = symtab
    context = f"load command {command_index} symbol table"
    if symbol_count > len(data) // layouts.nlist.size:
        raise MachOFormatError(
            f"{context}: symbol count is too large at file offset 0x{symbol_offset:x}"
        )
    _checked_slice(data, symbol_offset, symbol_count * layouts.nlist.size, context)
    string_table = _checked_slice(data, string_offset, string_size, f"{context} strings")
    result: list[dict[str, Any]] = []
    names: list[str] = []
    for symbol_index in range(symbol_count):
        entry_offset = symbol_offset + symbol_index * layouts.nlist.size
        entry_context = (
            f"load command {command_index} symbol {symbol_index} at file offset "
            f"0x{entry_offset:x}"
        )
        string_index, symbol_type, section_number, _description, value = _unpack(
            layouts.nlist, data, entry_offset, entry_context
        )
        if string_index >= len(string_table):
            raise MachOFormatError(
                f"{entry_context}: string offset 0x{string_index:x} is outside table"
            )
        terminator = string_table.find(b"\0", string_index)
        if terminator < 0:
            raise MachOFormatError(f"{entry_context}: string is not terminated")
        try:
            name = string_table[string_index:terminator].decode("utf-8")
        except UnicodeDecodeError as error:
            raise MachOFormatError(f"{entry_context}: name is not UTF-8") from error
        if section_number > len(sections):
            raise MachOFormatError(
                f"{entry_context}: invalid section index {section_number}"
            )
        names.append(name)
        result.append(
            {
                "name": name,
                "address": value,
                "binding": "external" if symbol_type & 0x01 else "local",
                "section": sections[section_number - 1]["name"] if section_number else None,
            }
        )
    return result, names


_RELOCATION_FIELDS = ("address", "kind", "target", "addend")


def _read_relocations(
    data: bytes,
    sections: list[dict[str, Any]],
    symbol_names: list[str],
    architecture,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Return (semantic, raw) relocation records for one image."""
    if architecture.relocation_decoder == "ppc":
        return _decode_ppc_relocations(data, sections, symbol_names, architecture)
    return _decode_i386_relocations(data, sections, symbol_names, architecture)


def _decode_i386_relocations(
    data: bytes,
    sections: list[dict[str, Any]],
    symbol_names: list[str],
    architecture,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    result: list[dict[str, Any]] = []
    for section_index, section in enumerate(sections):
        count = section["relocation_count"]
        context = (
            f"load command {section['command_index']} section "
            f"{section['section_in_segment']} (global {section_index}) relocations"
        )
        if count > len(data) // architecture.layouts.relocation_info.size:
            raise MachOFormatError(
                f"{context}: relocation count is too large at file offset "
                f"0x{section['relocation_offset']:x}"
            )
        table_size = count * architecture.layouts.relocation_info.size
        _checked_slice(data, section["relocation_offset"], table_size, context)
        skip_next = False
        for relocation_index in range(count):
            if skip_next:
                skip_next = False
                continue
            entry_offset = (
                section["relocation_offset"]
                + relocation_index * architecture.layouts.relocation_info.size
            )
            entry_context = (
                f"load command {section['command_index']} section "
                f"{section['section_in_segment']} (global {section_index}) relocation "
                f"{relocation_index} at file offset 0x{entry_offset:x}"
            )
            address, word = _unpack(
                architecture.layouts.relocation_info,
                data,
                entry_offset,
                entry_context,
            )
            raw_address = address & 0xFFFFFFFF
            scattered = bool(raw_address & 0x80000000)
            target_section_ordinal = None
            sectdiff_pair_value = None
            if scattered:
                address = raw_address & 0x00FFFFFF
                relocation_type = (raw_address >> 24) & 0xF
                length = (raw_address >> 28) & 0x3
                pc_relative = bool(raw_address & (1 << 30))
                # GENERIC_RELOC_VANILLA=0, PAIR=1, SECTDIFF=2, LOCAL_SECTDIFF=4.
                if relocation_type == 1:
                    raise MachOFormatError(
                        f"{entry_context}: unexpected scattered PAIR without a "
                        "SECTDIFF principal"
                    )
                if relocation_type in (2, 4):
                    if relocation_index + 1 >= count:
                        raise MachOFormatError(
                            f"{entry_context}: SECTDIFF requires a scattered PAIR"
                        )
                    pair_offset = (
                        section["relocation_offset"]
                        + (relocation_index + 1)
                        * architecture.layouts.relocation_info.size
                    )
                    pair_context = (
                        f"load command {section['command_index']} section "
                        f"{section['section_in_segment']} (global {section_index}) "
                        f"relocation {relocation_index + 1} at file offset "
                        f"0x{pair_offset:x}"
                    )
                    pair_address, pair_word = _unpack(
                        architecture.layouts.relocation_info,
                        data,
                        pair_offset,
                        pair_context,
                    )
                    pair_raw = pair_address & 0xFFFFFFFF
                    pair_scattered = bool(pair_raw & 0x80000000)
                    pair_type = (pair_raw >> 24) & 0xF
                    if not pair_scattered or pair_type != 1:
                        raise MachOFormatError(
                            f"{entry_context}: SECTDIFF requires a scattered PAIR"
                        )
                    sectdiff_pair_value = pair_word
                    skip_next = True
                elif relocation_type != 0:
                    raise MachOFormatError(
                        f"{entry_context}: unsupported scattered relocation type "
                        f"{relocation_type}"
                    )
                matches = [
                    candidate for candidate in sections
                    if candidate["size"] and
                    candidate["address"] <= word < candidate["address"] + candidate["size"]
                ]
                if not matches:
                    matches = [
                        candidate for candidate in sections
                        if word == candidate["address"] + candidate["size"]
                    ]
                if len(matches) != 1:
                    raise MachOFormatError(
                        f"{entry_context}: scattered relocation target 0x{word:x} "
                        "is outside or ambiguous"
                    )
                target_section = matches[0]
                target = target_section["name"]
                target_section_ordinal = target_section["ordinal"]
                external = False
            else:
                length = (word >> 25) & 0x3
                pc_relative = bool(word & (1 << 24))
                external = bool(word & (1 << 27))
                relocation_type = (word >> 28) & 0xF
            if length == 3:
                raise MachOFormatError(
                    f"{entry_context}: relocation length code 3 is invalid for "
                    f"{architecture.name}"
                )
            width = 1 << length
            section_size = section["size"]
            if section_size < width or address > section_size - width:
                raise MachOFormatError(
                    f"{entry_context}: relocation field crosses owning section"
                )
            if not scattered:
                symbol_number = word & 0x00FFFFFF
                if external:
                    if symbol_number >= len(symbol_names):
                        raise MachOFormatError(
                            f"{entry_context}: invalid symbol index {symbol_number}"
                        )
                    target = symbol_names[symbol_number]
                else:
                    if symbol_number == 0:
                        # Mach-O's R_ABS pseudo-section means no relocation target.
                        target = None
                    elif symbol_number > len(sections):
                        raise MachOFormatError(
                            f"{entry_context}: invalid section ordinal {symbol_number}"
                        )
                    else:
                        target_section = sections[symbol_number - 1]
                        target = target_section["name"]
                        target_section_ordinal = symbol_number
            if scattered and relocation_type in (2, 4):
                type_name = "sectdiff" if relocation_type == 2 else "local-sectdiff"
            else:
                type_name = ("scattered-vanilla" if scattered else
                             ("vanilla" if relocation_type == 0 else f"type-{relocation_type}"))
            relative = "pc-relative" if pc_relative else "absolute"
            if section["zero_fill"]:
                field = b"\0" * width
            else:
                field_offset = section["offset"] + address
                field = _checked_slice(data, field_offset, width, entry_context)
            # Absolute fields model unsigned addresses. PC-relative fields model
            # signed displacements; preserving that distinction gives downstream
            # comparison a stable semantic addend without changing stored bits.
            field_value = int.from_bytes(field, architecture.endianness, signed=pc_relative)
            relocation_address = section["address"] + address
            if sectdiff_pair_value is not None:
                addend = field_value - (word - sectdiff_pair_value)
            else:
                addend = (field_value + (relocation_address if pc_relative else 0)
                          - target_section["address"]
                          if target_section_ordinal is not None else field_value)
            result.append(
                {
                    "address": relocation_address,
                    "kind": f"{architecture.name}-{type_name}-{width * 8}-{relative}",
                    "target": target,
                    "addend": addend,
                    "type": relocation_type,
                    "pc_relative": pc_relative,
                    "width": width,
                    "external": external,
                    "section": section["name"],
                    "section_ordinal": section["ordinal"],
                    "target_section_ordinal": target_section_ordinal,
                    "original_bytes": field.hex().upper(),
                }
            )
    semantic = [
        {key: relocation[key] for key in _RELOCATION_FIELDS}
        for relocation in result
    ]
    return semantic, result


PPC_RELOC_VANILLA = 0
PPC_RELOC_PAIR = 1
PPC_RELOC_BR14 = 2
PPC_RELOC_BR24 = 3
PPC_RELOC_HI16 = 4
PPC_RELOC_LO16 = 5
PPC_RELOC_HA16 = 6
PPC_RELOC_SECTDIFF = 8
PPC_RELOC_JBSR = 13

_PPC_TYPE_NAMES = {
    PPC_RELOC_VANILLA: "vanilla",
    PPC_RELOC_PAIR: "pair",
    PPC_RELOC_BR14: "br14",
    PPC_RELOC_BR24: "br24",
    PPC_RELOC_HI16: "hi16",
    PPC_RELOC_LO16: "lo16",
    PPC_RELOC_HA16: "ha16",
    PPC_RELOC_SECTDIFF: "sectdiff",
    PPC_RELOC_JBSR: "jbsr",
}
# Kind-name width: the reconstructed value's width for paired kinds (they
# stand for a 32-bit address split across two fields), the field's own width
# for kinds that carry a complete value themselves.
_PPC_FIELD_BITS = {
    PPC_RELOC_VANILLA: 32, PPC_RELOC_PAIR: 16, PPC_RELOC_BR14: 14,
    PPC_RELOC_BR24: 24, PPC_RELOC_HI16: 32, PPC_RELOC_LO16: 32,
    PPC_RELOC_HA16: 32, PPC_RELOC_SECTDIFF: 32, PPC_RELOC_JBSR: 24,
}
_PPC_PAIRED = frozenset(
    (PPC_RELOC_HI16, PPC_RELOC_LO16, PPC_RELOC_HA16, PPC_RELOC_JBSR,
     PPC_RELOC_SECTDIFF)
)


def _sign_extend(value: int, bits: int) -> int:
    sign = 1 << (bits - 1)
    return (value & (sign - 1)) - (value & sign)


def _ppc_entries(data, section, section_index, architecture):
    """Read one section's relocation table into decoded field dictionaries."""
    layout = architecture.layouts.relocation_info
    count = section["relocation_count"]
    context = (
        f"load command {section['command_index']} section "
        f"{section['section_in_segment']} (global {section_index}) relocations"
    )
    if count > len(data) // layout.size:
        raise MachOFormatError(
            f"{context}: relocation count is too large at file offset "
            f"0x{section['relocation_offset']:x}"
        )
    _checked_slice(data, section["relocation_offset"], count * layout.size, context)
    entries = []
    for index in range(count):
        offset = section["relocation_offset"] + index * layout.size
        first, second = _unpack(layout, data, offset, context)
        raw_first = first & 0xFFFFFFFF
        if raw_first & 0x80000000:
            entries.append({
                "offset": offset, "scattered": True,
                "address": raw_first & 0xFFFFFF,
                "pc_relative": bool(raw_first & (1 << 30)),
                "length": (raw_first >> 28) & 0x3,
                "type": (raw_first >> 24) & 0xF,
                "value": second, "symbolnum": None, "external": False,
            })
        else:
            entries.append({
                "offset": offset, "scattered": False, "address": raw_first,
                "pc_relative": bool((second >> 7) & 1),
                "length": (second >> 5) & 0x3,
                "external": bool((second >> 4) & 1),
                "type": second & 0xF,
                "symbolnum": (second >> 8) & 0xFFFFFF, "value": None,
            })
    return entries, context


def _require_ppc_length(entry, section, where):
    """Reject any relocation whose field is not the four-byte width every
    entry in the reference binaries uses (spec §3.2); decoding anything else
    would read a fraction of an instruction as if it were the full field."""
    if entry["length"] != 2:
        raise MachOFormatError(
            f"{where}: relocation length code {entry['length']} is invalid for "
            f"ppc in section {section['name']!r}"
        )


def _ppc_instruction(data, section, entry, context):
    """Return the four-byte word the relocation patches."""
    if section["zero_fill"]:
        return 0, b"\0\0\0\0"
    field = _checked_slice(data, section["offset"] + entry["address"], 4, context)
    return int.from_bytes(field, "big"), field


def _ppc_section_of(sections, value):
    """Return the section whose [address, address + size) contains value."""
    for section in sections:
        if section["size"] and section["address"] <= value < section["address"] + section["size"]:
            return section
    return None


def _decode_ppc_relocations(data, sections, symbol_names, architecture):
    semantic: list[dict[str, Any]] = []
    raw: list[dict[str, Any]] = []
    for section_index, section in enumerate(sections):
        entries, context = _ppc_entries(data, section, section_index, architecture)
        index = 0
        while index < len(entries):
            entry = entries[index]
            where = f"{context} at file offset 0x{entry['offset']:x}"
            kind = entry["type"]
            if kind == PPC_RELOC_PAIR:
                raise MachOFormatError(f"{where}: unexpected PAIR without a principal")
            if kind not in _PPC_TYPE_NAMES:
                raise MachOFormatError(
                    f"{context}: unsupported relocation type {kind} at file offset "
                    f"0x{entry['offset']:x}"
                )
            _require_ppc_length(entry, section, where)
            pair = None
            if kind in _PPC_PAIRED:
                pair = entries[index + 1] if index + 1 < len(entries) else None
                if pair is None or pair["type"] != PPC_RELOC_PAIR:
                    raise MachOFormatError(
                        f"{where}: {_PPC_TYPE_NAMES[kind]} requires a PAIR entry"
                    )
                _require_ppc_length(
                    pair, section, f"{context} at file offset 0x{pair['offset']:x}"
                )
            if entry["address"] > section["size"] - 4 or section["size"] < 4:
                raise MachOFormatError(f"{where}: relocation field crosses owning section")

            word, field = _ppc_instruction(data, section, entry, where)
            low = word & 0xFFFF

            if entry["scattered"]:
                target_section = _ppc_section_of(sections, entry["value"])
                if target_section is None:
                    raise MachOFormatError(
                        f"{where}: scattered relocation target 0x{entry['value']:x} "
                        "is outside every section"
                    )
                if kind == PPC_RELOC_SECTDIFF:
                    if pair is None or not pair["scattered"]:
                        raise MachOFormatError(
                            f"{where}: SECTDIFF requires a scattered PAIR entry"
                        )
                    difference = entry["value"] - pair["value"]
                    addend = _sign_extend(word, 32) - difference
                    name = "ppc-sectdiff-32-absolute"
                elif kind == PPC_RELOC_HI16:
                    addend = ((low << 16) | (pair["address"] & 0xFFFF)) - target_section["address"]
                    name = "ppc-scattered-hi16-32-absolute"
                elif kind == PPC_RELOC_HA16:
                    addend = ((low << 16) + _sign_extend(pair["address"] & 0xFFFF, 16)
                              - target_section["address"])
                    name = "ppc-scattered-ha16-32-absolute"
                elif kind == PPC_RELOC_LO16:
                    addend = (((pair["address"] & 0xFFFF) << 16) | low) - target_section["address"]
                    name = "ppc-scattered-lo16-32-absolute"
                else:
                    raise MachOFormatError(
                        f"{where}: unsupported scattered relocation type {kind}"
                    )
                semantic.append({"address": section["address"] + entry["address"],
                                 "kind": name, "target": target_section["name"],
                                 "addend": addend})
                raw.append(_ppc_raw(section, entry, name, target_section["name"],
                                    addend, field))
                raw[-1]["target_section_ordinal"] = target_section["ordinal"]
                if pair is not None:
                    raw.append(_ppc_pair_raw(section, entry, pair))
                    index += 1
                index += 1
                continue

            if kind == PPC_RELOC_VANILLA:
                value = word
            elif kind == PPC_RELOC_HI16:
                value = (low << 16) | (pair["address"] & 0xFFFF)
            elif kind == PPC_RELOC_HA16:
                value = (low << 16) + _sign_extend(pair["address"] & 0xFFFF, 16)
            elif kind == PPC_RELOC_LO16:
                value = ((pair["address"] & 0xFFFF) << 16) | low
            elif kind == PPC_RELOC_JBSR:
                value = pair["address"]
            elif kind == PPC_RELOC_BR24:
                value = (_sign_extend(word & 0x03FFFFFC, 26)
                         + section["address"] + entry["address"])
            elif kind == PPC_RELOC_BR14:
                value = (_sign_extend(word & 0xFFFC, 16)
                         + section["address"] + entry["address"])
            else:  # PPC_RELOC_SECTDIFF, only ever scattered
                raise MachOFormatError(
                    f"{where}: SECTDIFF is only supported as a scattered relocation"
                )

            target, target_section = _ppc_target(
                entry, sections, symbol_names, where
            )
            addend = value - target_section["address"] if target_section else value
            relative = "pc-relative" if kind in (PPC_RELOC_BR14, PPC_RELOC_BR24,
                                                 PPC_RELOC_JBSR) else "absolute"
            name = f"ppc-{_PPC_TYPE_NAMES[kind]}-{_PPC_FIELD_BITS[kind]}-{relative}"
            semantic.append({"address": section["address"] + entry["address"],
                             "kind": name, "target": target, "addend": addend})
            raw.append(_ppc_raw(section, entry, name, target, addend, field))
            if target_section is not None:
                raw[-1]["target_section_ordinal"] = target_section["ordinal"]
            if pair is not None:
                # A PAIR's r_address is the other half of the value, not an
                # offset, so the record is addressed at its principal and its
                # bytes are that half.
                raw.append(_ppc_pair_raw(section, entry, pair))
                index += 1
            index += 1
    return semantic, raw


def _ppc_pair_raw(section, principal, pair):
    record = _ppc_raw(section, principal, "ppc-pair-16-absolute", None,
                      pair["address"],
                      (pair["address"] & 0xFFFF).to_bytes(2, "big"))
    record["type"] = pair["type"]
    record["scattered"] = pair["scattered"]
    record["width"] = 2
    record["pc_relative"] = pair["pc_relative"]
    record["external"] = pair["external"]
    return record


def _ppc_target(entry, sections, symbol_names, where):
    """Resolve a non-scattered entry's target name and owning section."""
    if entry["external"]:
        if entry["symbolnum"] >= len(symbol_names):
            raise MachOFormatError(
                f"{where}: invalid symbol index {entry['symbolnum']}"
            )
        return symbol_names[entry["symbolnum"]], None
    if entry["symbolnum"] == 0:
        # Mach-O's R_ABS pseudo-section means no relocation target.
        return None, None
    if entry["symbolnum"] > len(sections):
        raise MachOFormatError(
            f"{where}: invalid section ordinal {entry['symbolnum']}"
        )
    section = sections[entry["symbolnum"] - 1]
    return section["name"], section


def _ppc_raw(section, entry, kind, target, addend, field):
    return {
        "address": section["address"] + entry["address"],
        "kind": kind,
        "target": target,
        "addend": addend,
        "type": entry["type"],
        "pc_relative": entry["pc_relative"],
        "width": 4,
        "external": entry["external"],
        "section": section["name"],
        "section_ordinal": section["ordinal"],
        "target_section_ordinal": None,
        "original_bytes": field.hex().upper(),
        "scattered": entry["scattered"],
    }
