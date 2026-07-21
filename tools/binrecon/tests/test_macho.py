import hashlib
import struct

import pytest

from binrecon.macho import MachOFormatError, read_macho
from binrecon.schema import validate_document
from macho_fixture import (
    CPU_TYPE_I386,
    HEADER,
    LC_UNIXTHREAD,
    MH_MAGIC,
    MH_OBJECT,
    SECTION,
    SEGMENT,
    SYMTAB,
    build_macho_fixture,
    patch_u32,
)


def write_fixture(tmp_path, blob=None):
    path = tmp_path / "fixture.o"
    path.write_bytes(build_macho_fixture() if blob is None else blob)
    return path


def test_reads_legacy_i386_object_metadata_without_guessing_functions(tmp_path):
    path = write_fixture(tmp_path)

    analysis = read_macho(path)

    validate_document("analysis-v1", analysis)
    assert analysis["input"] == {
        "path": str(path.resolve()),
        "size": path.stat().st_size,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest().upper(),
        "architecture": "i386",
        "endianness": "little",
    }
    assert analysis["functions"] == []
    section_summaries = [
        (section["name"], section["address"], section["size"])
        for section in analysis["sections"]
    ]
    assert section_summaries == [
        ("__TEXT,__text", 0x1000, 4),
        ("__DATA,__data", 0x1004, 4),
    ]
    assert analysis["sections"][0]["permissions"] == "rwx"
    assert analysis["sections"][0]["sha256"] == hashlib.sha256(
        b"\x90\x90\x90\xC3"
    ).hexdigest().upper()
    assert analysis["symbols"] == [
        {"name": "_external", "address": 0, "binding": "external", "section": None}
    ]
    assert analysis["relocations"] == [
        {
            "address": 0x1001,
            "kind": "i386-vanilla-32-absolute",
            "target": "_external",
            "addend": 0,
        }
    ]


def test_unknown_thread_flavor_is_preserved_and_next_command_is_found(tmp_path):
    unknown = struct.pack("<III", 0x7777, 12, 0x12345678)
    path = write_fixture(tmp_path, build_macho_fixture(extra_command=unknown))
    analysis = read_macho(path)

    commands = analysis["extensions"]["macho"]["unparsed_load_commands"]
    assert [command["command"] for command in commands] == [LC_UNIXTHREAD, 0x7777]
    assert commands[0]["reason"] == "unknown-thread-flavor"
    assert commands[1]["reason"] == "unknown-load-command"
    blob = path.read_bytes()
    for command in commands:
        start = command["offset"]
        end = start + command["size"]
        assert command["bytes"] == blob[start:end].hex().upper()


@pytest.mark.parametrize(
    ("header_offset", "value", "message"),
    [
        (0, 0, "magic"),
        (4, CPU_TYPE_I386 + 1, "CPU"),
        (12, MH_OBJECT + 1, "file type"),
    ],
)
def test_rejects_unsupported_header_identity(tmp_path, header_offset, value, message):
    path = write_fixture(tmp_path, patch_u32(build_macho_fixture(), header_offset, value))

    with pytest.raises(MachOFormatError, match=message):
        read_macho(path)


def test_rejects_64_bit_and_big_endian_magic(tmp_path):
    for magic in (0xFEEDFACF, 0xCEFAEDFE):
        path = write_fixture(tmp_path, patch_u32(build_macho_fixture(), 0, magic))
        with pytest.raises(MachOFormatError, match="magic"):
            read_macho(path)


def test_rejects_truncated_load_command_with_index_and_offset(tmp_path):
    blob = build_macho_fixture()[: HEADER.size + 4]

    with pytest.raises(MachOFormatError, match=r"command 0.*offset 0x1c"):
        read_macho(write_fixture(tmp_path, blob))


def test_rejects_command_smaller_than_load_command_header(tmp_path):
    blob = patch_u32(build_macho_fixture(), HEADER.size + 4, 4)

    with pytest.raises(MachOFormatError, match=r"command 0.*size.*offset 0x1c"):
        read_macho(write_fixture(tmp_path, blob))


def test_rejects_count_derived_section_table_outside_command(tmp_path):
    nsects_offset = HEADER.size + 48
    blob = patch_u32(build_macho_fixture(), nsects_offset, 0xFFFFFFFF)

    with pytest.raises(MachOFormatError, match=r"command 0.*section.*offset 0x1c"):
        read_macho(write_fixture(tmp_path, blob))


def test_rejects_section_bytes_outside_file(tmp_path):
    first_section_offset = HEADER.size + SEGMENT.size
    section_file_offset = first_section_offset + 40
    blob = patch_u32(build_macho_fixture(), section_file_offset, 0xFFFFFFF0)

    with pytest.raises(MachOFormatError, match=r"command 0.*section 0.*offset"):
        read_macho(write_fixture(tmp_path, blob))


def test_rejects_invalid_symbol_string_offset(tmp_path):
    blob = bytearray(build_macho_fixture())
    symtab_command_offset = HEADER.size + SEGMENT.size + 2 * SECTION.size
    symbol_offset = struct.unpack_from("<I", blob, symtab_command_offset + 8)[0]
    struct.pack_into("<I", blob, symbol_offset, 0xFFFFFFFF)

    with pytest.raises(MachOFormatError, match=r"symbol 0.*string offset"):
        read_macho(write_fixture(tmp_path, bytes(blob)))


def test_rejects_scattered_relocation(tmp_path):
    blob = bytearray(build_macho_fixture())
    first_section_offset = HEADER.size + SEGMENT.size
    relocation_offset = struct.unpack_from("<I", blob, first_section_offset + 48)[0]
    struct.pack_into("<I", blob, relocation_offset, 0x80000001)

    with pytest.raises(MachOFormatError, match=r"section 0 relocation 0.*scattered"):
        read_macho(write_fixture(tmp_path, bytes(blob)))


def test_rejects_load_command_range_larger_than_declared_table(tmp_path):
    blob = patch_u32(build_macho_fixture(), 20, 8)

    with pytest.raises(MachOFormatError, match=r"command 0.*declared load-command table"):
        read_macho(write_fixture(tmp_path, blob))


def test_fixture_has_expected_header_for_test_sanity():
    values = HEADER.unpack_from(build_macho_fixture())
    magic, cpu, _, filetype, ncmds, sizeofcmds, _ = values
    assert (magic, cpu, filetype, ncmds) == (MH_MAGIC, CPU_TYPE_I386, MH_OBJECT, 3)
    assert sizeofcmds > SYMTAB.size
