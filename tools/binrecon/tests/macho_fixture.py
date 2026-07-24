import struct


MH_MAGIC = 0xFEEDFACE
CPU_TYPE_I386 = 7
MH_OBJECT = 1
MH_PRELOAD = 5
LC_SEGMENT = 1
LC_SYMTAB = 2
LC_UNIXTHREAD = 5

HEADER = struct.Struct("<7I")
SEGMENT = struct.Struct("<II16sIIIIiiII")
SECTION = struct.Struct("<16s16sIIIIIIIII")
SYMTAB = struct.Struct("<6I")
NLIST = struct.Struct("<IBBHI")
RELOCATION = struct.Struct("<iI")


def _name(value: str) -> bytes:
    return value.encode("ascii").ljust(16, b"\0")


def build_macho_fixture(*, extra_command: bytes = b"", file_type: int = MH_OBJECT,
                        base_address: int = 0x1000) -> bytes:
    # A four-byte vanilla relocation owns the complete field at offset zero.
    text = b"\0" * 4
    data = b"DATA"
    strings = b"\0_external\0"

    segment_size = SEGMENT.size + 2 * SECTION.size
    thread_payload = struct.pack("<I", 0xAABBCCDD) + b"unknown-thread-state"
    thread_command = struct.pack(
        "<II", LC_UNIXTHREAD, 8 + len(thread_payload)
    ) + thread_payload
    commands_size = segment_size + SYMTAB.size + len(thread_command) + len(extra_command)
    data_start = HEADER.size + commands_size
    text_offset = data_start
    data_offset = text_offset + len(text)
    relocation_offset = data_offset + len(data)
    symbol_offset = relocation_offset + RELOCATION.size
    string_offset = symbol_offset + NLIST.size

    segment = SEGMENT.pack(
        LC_SEGMENT,
        segment_size,
        _name(""),
        base_address,
        8,
        text_offset,
        8,
        7,
        7,
        2,
        0,
    )
    segment += SECTION.pack(
        _name("__text"),
        _name("__TEXT"),
        base_address,
        len(text),
        text_offset,
        2,
        relocation_offset,
        1,
        0,
        0,
        0,
    )
    segment += SECTION.pack(
        _name("__data"),
        _name("__DATA"),
        base_address + 4,
        len(data),
        data_offset,
        2,
        0,
        0,
        0,
        0,
        0,
    )
    symtab = SYMTAB.pack(
        LC_SYMTAB,
        SYMTAB.size,
        symbol_offset,
        1,
        string_offset,
        len(strings),
    )
    nlist = NLIST.pack(1, 0x01, 0, 0, 0)
    relocation_word = 0 | (2 << 25) | (1 << 27)
    relocation = RELOCATION.pack(0, relocation_word)
    commands = segment + symtab + thread_command + extra_command
    header = HEADER.pack(
        MH_MAGIC,
        CPU_TYPE_I386,
        3,
        file_type,
        3 + bool(extra_command),
        len(commands),
        0,
    )
    return header + commands + text + data + relocation + nlist + strings


def patch_u32(blob: bytes, offset: int, value: int) -> bytes:
    result = bytearray(blob)
    struct.pack_into("<I", result, offset, value)
    return bytes(result)
