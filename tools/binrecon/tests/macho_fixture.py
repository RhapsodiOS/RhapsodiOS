import struct


MH_MAGIC = 0xFEEDFACE
CPU_TYPE_I386 = 7
CPU_TYPE_POWERPC = 18
MH_OBJECT = 1
MH_PRELOAD = 5
MH_BUNDLE = 8
LC_SEGMENT = 1
LC_SYMTAB = 2
LC_UNIXTHREAD = 5

HEADER = struct.Struct("<7I")
SEGMENT = struct.Struct("<II16sIIIIiiII")
SECTION = struct.Struct("<16s16sIIIIIIIII")
SYMTAB = struct.Struct("<6I")
NLIST = struct.Struct("<IBBHI")
RELOCATION = struct.Struct("<iI")

_PREFIXES = {"i386": "<", "ppc": ">"}
_CPU_TYPES = {"i386": CPU_TYPE_I386, "ppc": CPU_TYPE_POWERPC}


def _structs(architecture):
    prefix = _PREFIXES[architecture]
    return {
        "header": struct.Struct(f"{prefix}7I"),
        "segment": struct.Struct(f"{prefix}II16sIIIIiiII"),
        "section": struct.Struct(f"{prefix}16s16sIIIIIIIII"),
        "symtab": struct.Struct(f"{prefix}6I"),
        "nlist": struct.Struct(f"{prefix}IBBHI"),
        "relocation": struct.Struct(f"{prefix}iI"),
        "word": struct.Struct(f"{prefix}I"),
        "pair": struct.Struct(f"{prefix}II"),
    }


def _name(value: str) -> bytes:
    return value.encode("ascii").ljust(16, b"\0")


def build_macho_fixture(*, extra_command: bytes = b"", file_type: int = MH_OBJECT,
                        base_address: int = 0x1000, architecture: str = "i386",
                        text: bytes | None = None,
                        relocations: bytes | None = None) -> bytes:
    layout = _structs(architecture)
    # A four-byte vanilla relocation owns the complete field at offset zero.
    text = b"\0" * 4 if text is None else text
    data = b"DATA"
    strings = b"\0_external\0"
    if relocations is None:
        relocation_word = 0 | (2 << 25) | (1 << 27)
        relocations = layout["relocation"].pack(0, relocation_word)
    relocation_count = len(relocations) // layout["relocation"].size

    segment_size = layout["segment"].size + 2 * layout["section"].size
    thread_payload = layout["word"].pack(0xAABBCCDD) + b"unknown-thread-state"
    thread_command = layout["pair"].pack(
        LC_UNIXTHREAD, 8 + len(thread_payload)
    ) + thread_payload
    commands_size = (segment_size + layout["symtab"].size + len(thread_command)
                     + len(extra_command))
    data_start = layout["header"].size + commands_size
    text_offset = data_start
    data_offset = text_offset + len(text)
    relocation_offset = data_offset + len(data)
    symbol_offset = relocation_offset + len(relocations)
    string_offset = symbol_offset + layout["nlist"].size

    segment = layout["segment"].pack(
        LC_SEGMENT,
        segment_size,
        _name(""),
        base_address,
        len(text) + len(data),
        text_offset,
        len(text) + len(data),
        7,
        7,
        2,
        0,
    )
    segment += layout["section"].pack(
        _name("__text"),
        _name("__TEXT"),
        base_address,
        len(text),
        text_offset,
        2,
        relocation_offset,
        relocation_count,
        0,
        0,
        0,
    )
    segment += layout["section"].pack(
        _name("__data"),
        _name("__DATA"),
        base_address + len(text),
        len(data),
        data_offset,
        2,
        0,
        0,
        0,
        0,
        0,
    )
    symtab = layout["symtab"].pack(
        LC_SYMTAB,
        layout["symtab"].size,
        symbol_offset,
        1,
        string_offset,
        len(strings),
    )
    nlist = layout["nlist"].pack(1, 0x01, 0, 0, 0)
    commands = segment + symtab + thread_command + extra_command
    header = layout["header"].pack(
        MH_MAGIC,
        _CPU_TYPES[architecture],
        3,
        file_type,
        3 + bool(extra_command),
        len(commands),
        0,
    )
    return header + commands + text + data + relocations + nlist + strings


PPC_RELOC_VANILLA = 0
PPC_RELOC_PAIR = 1
PPC_RELOC_BR24 = 3
PPC_RELOC_HI16 = 4
PPC_RELOC_LO16 = 5
PPC_RELOC_HA16 = 6
PPC_RELOC_SECTDIFF = 8
PPC_RELOC_JBSR = 13


def ppc_relocation(address, symbolnum, *, kind, length=2, pcrel=0, extern=0):
    """One non-scattered big-endian relocation_info entry."""
    word = (((symbolnum & 0xFFFFFF) << 8) | ((pcrel & 1) << 7)
            | ((length & 3) << 5) | ((extern & 1) << 4) | (kind & 0xF))
    return struct.pack(">iI", address, word)


def ppc_pair(other_half, *, kind=PPC_RELOC_PAIR, length=2):
    """A PAIR entry, whose r_address field carries the other half."""
    return ppc_relocation(other_half, 0xFFFFFF, kind=kind, length=length)


def ppc_scattered(address, value, *, kind, length=2, pcrel=0):
    """One scattered big-endian relocation entry."""
    word = (0x80000000 | ((pcrel & 1) << 30) | ((length & 3) << 28)
            | ((kind & 0xF) << 24) | (address & 0xFFFFFF))
    return struct.pack(">II", word, value)


def patch_u32(blob: bytes, offset: int, value: int) -> bytes:
    result = bytearray(blob)
    struct.pack_into("<I", result, offset, value)
    return bytes(result)
