import hashlib
from pathlib import Path
import struct
from typing import Any

from . import __version__
from .identity import identify


MH_MAGIC = 0xFEEDFACE
CPU_TYPE_I386 = 7
MH_OBJECT = 1
MH_PRELOAD = 5
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

_MACH_HEADER = struct.Struct("<7I")
_LOAD_COMMAND = struct.Struct("<2I")
_SEGMENT_COMMAND = struct.Struct("<II16sIIIIiiII")
_SECTION = struct.Struct("<16s16sIIIIIIIII")
_SYMTAB_COMMAND = struct.Struct("<6I")
_NLIST = struct.Struct("<IBBHI")
_RELOCATION_INFO = struct.Struct("<iI")


class MachOFormatError(ValueError):
    """Raised when an input is not a supported, well-formed Mach-O object."""


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

    (
        magic,
        cpu_type,
        cpu_subtype,
        file_type,
        command_count,
        commands_size,
        flags,
    ) = _unpack(_MACH_HEADER, data, 0, "Mach-O header")
    if magic != MH_MAGIC:
        raise MachOFormatError(
            f"unsupported Mach-O magic 0x{magic:08x}; expected 32-bit little-endian"
        )
    if cpu_type != CPU_TYPE_I386:
        raise MachOFormatError(f"unsupported Mach-O CPU type {cpu_type}; expected i386")
    if file_type not in (MH_OBJECT, MH_PRELOAD):
        raise MachOFormatError(
            f"unsupported Mach-O file type {file_type}; expected MH_OBJECT or MH_PRELOAD"
        )

    command_start = _MACH_HEADER.size
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
            _LOAD_COMMAND, data, cursor, context, limit=command_end
        )
        if command_size < _LOAD_COMMAND.size:
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
                _SEGMENT_COMMAND, data, cursor, context, limit=cursor + command_size
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
            section_table_offset = cursor + _SEGMENT_COMMAND.size
            available = command_size - _SEGMENT_COMMAND.size
            if section_count > available // _SECTION.size:
                raise MachOFormatError(
                    f"{context}: section table does not fit command at file offset "
                    f"0x{cursor:x}"
                )
            expected_size = _SEGMENT_COMMAND.size + section_count * _SECTION.size
            if expected_size != command_size:
                raise MachOFormatError(
                    f"{context}: segment size does not match section count at file "
                    f"offset 0x{cursor:x}"
                )
            for section_in_segment in range(section_count):
                section_offset = section_table_offset + section_in_segment * _SECTION.size
                section_context = f"{context} section {section_in_segment}"
                section_values = _unpack(
                    _SECTION,
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
                        f"{section_context}: alignment exponent exceeds i386 address width "
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
            if command_size != _SYMTAB_COMMAND.size:
                raise MachOFormatError(
                    f"{context}: invalid symtab command size at file offset 0x{cursor:x}"
                )
            if symtab is not None:
                raise MachOFormatError(
                    f"{context}: duplicate symbol table at file offset 0x{cursor:x}"
                )
            _, _, symbol_offset, symbol_count, string_offset, string_size = _unpack(
                _SYMTAB_COMMAND, data, cursor, context, limit=cursor + command_size
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

    symbols, symbol_names = _read_symbols(data, symtab, raw_sections)
    raw_relocations = _read_relocations(data, raw_sections, symbol_names)
    relocation_fields = ("address", "kind", "target", "addend")
    relocations = [
        {key: relocation[key] for key in relocation_fields}
        for relocation in raw_relocations
    ]
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
            "architecture": "i386",
            "endianness": "little",
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
                    [
                        {
                            key: relocation[key]
                            for key in (
                                "address", "kind", "target", "addend",
                                "type", "pc_relative", "width", "external", "section",
                                "section_ordinal", "target_section_ordinal", "original_bytes",
                            )
                        }
                        for relocation in raw_relocations
                    ],
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


def _read_symbols(
    data: bytes,
    symtab: tuple[int, int, int, int, int] | None,
    sections: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[str]]:
    if symtab is None:
        return [], []
    command_index, symbol_offset, symbol_count, string_offset, string_size = symtab
    context = f"load command {command_index} symbol table"
    if symbol_count > len(data) // _NLIST.size:
        raise MachOFormatError(
            f"{context}: symbol count is too large at file offset 0x{symbol_offset:x}"
        )
    _checked_slice(data, symbol_offset, symbol_count * _NLIST.size, context)
    string_table = _checked_slice(data, string_offset, string_size, f"{context} strings")
    result: list[dict[str, Any]] = []
    names: list[str] = []
    for symbol_index in range(symbol_count):
        entry_offset = symbol_offset + symbol_index * _NLIST.size
        entry_context = (
            f"load command {command_index} symbol {symbol_index} at file offset "
            f"0x{entry_offset:x}"
        )
        string_index, symbol_type, section_number, _description, value = _unpack(
            _NLIST, data, entry_offset, entry_context
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


def _read_relocations(
    data: bytes,
    sections: list[dict[str, Any]],
    symbol_names: list[str],
) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for section_index, section in enumerate(sections):
        count = section["relocation_count"]
        context = (
            f"load command {section['command_index']} section "
            f"{section['section_in_segment']} (global {section_index}) relocations"
        )
        if count > len(data) // _RELOCATION_INFO.size:
            raise MachOFormatError(
                f"{context}: relocation count is too large at file offset "
                f"0x{section['relocation_offset']:x}"
            )
        table_size = count * _RELOCATION_INFO.size
        _checked_slice(data, section["relocation_offset"], table_size, context)
        for relocation_index in range(count):
            entry_offset = (
                section["relocation_offset"]
                + relocation_index * _RELOCATION_INFO.size
            )
            entry_context = (
                f"load command {section['command_index']} section "
                f"{section['section_in_segment']} (global {section_index}) relocation "
                f"{relocation_index} at file offset 0x{entry_offset:x}"
            )
            address, word = _unpack(
                _RELOCATION_INFO,
                data,
                entry_offset,
                entry_context,
            )
            raw_address = address & 0xFFFFFFFF
            scattered = bool(raw_address & 0x80000000)
            target_section_ordinal = None
            if scattered:
                address = raw_address & 0x00FFFFFF
                relocation_type = (raw_address >> 24) & 0xF
                length = (raw_address >> 28) & 0x3
                pc_relative = bool(raw_address & (1 << 30))
                if relocation_type != 0:
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
                    f"{entry_context}: relocation length code 3 is invalid for i386"
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
            field_value = int.from_bytes(field, "little", signed=pc_relative)
            relocation_address = section["address"] + address
            addend = (field_value + (relocation_address if pc_relative else 0)
                      - target_section["address"]
                      if target_section_ordinal is not None else field_value)
            result.append(
                {
                    "address": relocation_address,
                    "kind": f"i386-{type_name}-{width * 8}-{relative}",
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
    return result
