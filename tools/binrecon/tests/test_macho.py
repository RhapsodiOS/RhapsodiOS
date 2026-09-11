import hashlib
import struct

import pytest

from binrecon.macho import MachOFormatError, read_macho
from binrecon.schema import validate_document
from macho_fixture import (
    CPU_TYPE_I386,
    CPU_TYPE_POWERPC,
    HEADER,
    LC_UNIXTHREAD,
    MH_MAGIC,
    MH_OBJECT,
    MH_PRELOAD,
    MH_BUNDLE,
    PPC_RELOC_BR24,
    PPC_RELOC_HA16,
    PPC_RELOC_HI16,
    PPC_RELOC_JBSR,
    PPC_RELOC_LO16,
    PPC_RELOC_PAIR,
    PPC_RELOC_SECTDIFF,
    PPC_RELOC_VANILLA,
    SECTION,
    SEGMENT,
    SYMTAB,
    build_macho_fixture,
    patch_u32,
    ppc_pair,
    ppc_relocation,
    ppc_scattered,
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
        b"\0" * 4
    ).hexdigest().upper()
    assert analysis["symbols"] == [
        {"name": "_external", "address": 0, "binding": "external", "section": None}
    ]
    assert analysis["relocations"] == [
        {
            "address": 0x1000,
            "kind": "i386-vanilla-32-absolute",
            "target": "_external",
            "addend": 0,
        }
    ]
    assert analysis["extensions"]["macho"]["sections"] == [
        {"ordinal": 1, "segment_ordinal": 1, "name": "__TEXT,__text", "address": 0x1000, "offset": 0x114,
         "size": 4, "alignment_exponent": 2,
         "alignment": 4, "flags": 0, "type": 0, "zero_fill": False,
         "initialized": True},
        {"ordinal": 2, "segment_ordinal": 1, "name": "__DATA,__data", "address": 0x1004, "offset": 0x118,
         "size": 4, "alignment_exponent": 2,
         "alignment": 4, "flags": 0, "type": 0, "zero_fill": False,
         "initialized": True},
    ]
    assert analysis["extensions"]["macho"]["segments"] == [
        {"ordinal": 1, "name": "", "address": 0x1000, "offset": 0x114,
         "size": 8, "file_size": 8, "permissions": "rwx", "flags": 0}
    ]
    assert analysis["extensions"]["macho"]["relocations"] == [
        {"address": 0x1000, "kind": "i386-vanilla-32-absolute", "type": 0,
         "target": "_external", "addend": 0, "pc_relative": False,
         "width": 4, "external": True, "section": "__TEXT,__text",
         "section_ordinal": 1, "target_section_ordinal": None,
         "original_bytes": "00000000"}
    ]


def test_reads_preloaded_i386_image_with_zero_based_section_addresses(tmp_path):
    path = write_fixture(
        tmp_path, build_macho_fixture(file_type=MH_PRELOAD, base_address=0)
    )

    analysis = read_macho(path)

    validate_document("analysis-v1", analysis)
    assert [(section["name"], section["address"]) for section in analysis["sections"]] == [
        ("__TEXT,__text", 0),
        ("__DATA,__data", 4),
    ]


def test_reads_bundle_file_type(tmp_path):
    path = write_fixture(tmp_path, build_macho_fixture(file_type=MH_BUNDLE))

    analysis = read_macho(path)

    validate_document("analysis-v1", analysis)
    assert analysis["extensions"]["macho"]["header"]["file_type"] == MH_BUNDLE
    assert [section["name"] for section in analysis["sections"]] == [
        "__TEXT,__text",
        "__DATA,__data",
    ]


def test_file_backed_section_at_offset_zero_is_not_guessed_as_zero_fill(tmp_path):
    blob = bytearray(build_macho_fixture())
    first_section_offset = HEADER.size + SEGMENT.size
    struct.pack_into("<I", blob, first_section_offset + 40, 0)

    analysis = read_macho(write_fixture(tmp_path, bytes(blob)))

    metadata = analysis["extensions"]["macho"]["sections"][0]
    assert metadata["type"] == 0
    assert metadata["zero_fill"] is False
    assert metadata["initialized"] is True


def test_rejects_section_alignment_exponent_outside_i386_address_width(tmp_path):
    blob = bytearray(build_macho_fixture())
    first_section_offset = HEADER.size + SEGMENT.size
    struct.pack_into("<I", blob, first_section_offset + 44, 32)

    with pytest.raises(MachOFormatError, match="alignment exponent"):
        read_macho(write_fixture(tmp_path, bytes(blob)))


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
        (12, MH_BUNDLE + 1, "file type"),
    ],
)
def test_rejects_unsupported_header_identity(tmp_path, header_offset, value, message):
    path = write_fixture(tmp_path, patch_u32(build_macho_fixture(), header_offset, value))

    with pytest.raises(MachOFormatError, match=message):
        read_macho(path)


def test_rejects_64_bit_magic(tmp_path):
    path = write_fixture(tmp_path, patch_u32(build_macho_fixture(), 0, 0xFEEDFACF))

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

    with pytest.raises(
        MachOFormatError,
        match=(
            rf"load command 1 symbol 0.*file offset 0x{symbol_offset:x}"
            r".*string offset"
        ),
    ):
        read_macho(write_fixture(tmp_path, bytes(blob)))


def test_reads_scattered_vanilla_relocation_with_section_relative_addend(tmp_path):
    blob = bytearray(build_macho_fixture())
    first_section_offset = HEADER.size + SEGMENT.size
    relocation_offset = struct.unpack_from("<I", blob, first_section_offset + 48)[0]
    text_offset = struct.unpack_from("<I", blob, first_section_offset + 40)[0]
    struct.pack_into("<I", blob, text_offset, 0x1006)
    struct.pack_into("<II", blob, relocation_offset, 0xA0000000, 0x1004)

    relocation = read_macho(write_fixture(tmp_path, bytes(blob)))["extensions"]["macho"][
        "relocations"
    ][0]

    assert relocation == {
        "address": 0x1000,
        "kind": "i386-scattered-vanilla-32-absolute",
        "target": "__DATA,__data",
        "addend": 2,
        "type": 0,
        "pc_relative": False,
        "width": 4,
        "external": False,
        "section": "__TEXT,__text",
        "section_ordinal": 1,
        "target_section_ordinal": 2,
        "original_bytes": "06100000",
    }


def test_scattered_pc_relative_addend_reapplies_original_displacement(tmp_path):
    blob = bytearray(build_macho_fixture())
    first_section_offset = HEADER.size + SEGMENT.size
    relocation_offset = struct.unpack_from("<I", blob, first_section_offset + 48)[0]
    text_offset = struct.unpack_from("<I", blob, first_section_offset + 40)[0]
    struct.pack_into("<i", blob, text_offset, -4)
    struct.pack_into("<II", blob, relocation_offset, 0xE0000000, 0x1004)

    analysis = read_macho(write_fixture(tmp_path, bytes(blob)))
    relocation = analysis["extensions"]["macho"]["relocations"][0]

    assert relocation["kind"] == "i386-scattered-vanilla-32-pc-relative"
    assert relocation["addend"] == -8
    target = analysis["sections"][1]["address"]
    assert target + relocation["addend"] - relocation["address"] == -4


def test_scattered_target_accepts_unique_one_past_section_boundary(tmp_path):
    blob = bytearray(build_macho_fixture())
    first_section_offset = HEADER.size + SEGMENT.size
    relocation_offset = struct.unpack_from("<I", blob, first_section_offset + 48)[0]
    text_offset = struct.unpack_from("<I", blob, first_section_offset + 40)[0]
    struct.pack_into("<I", blob, text_offset, 0x100A)
    struct.pack_into("<II", blob, relocation_offset, 0xA0000000, 0x1008)

    relocation = read_macho(write_fixture(tmp_path, bytes(blob)))["extensions"]["macho"][
        "relocations"
    ][0]

    assert relocation["target"] == "__DATA,__data"
    assert relocation["target_section_ordinal"] == 2
    assert relocation["addend"] == 6


def test_rejects_unsupported_scattered_relocation_type(tmp_path):
    blob = bytearray(build_macho_fixture())
    first_section_offset = HEADER.size + SEGMENT.size
    relocation_offset = struct.unpack_from("<I", blob, first_section_offset + 48)[0]
    struct.pack_into("<II", blob, relocation_offset, 0xA3000000, 0x1004)

    with pytest.raises(MachOFormatError, match=r"scattered relocation type 3"):
        read_macho(write_fixture(tmp_path, bytes(blob)))


@pytest.mark.parametrize(
    ("address", "length"),
    [(3, 0), (2, 1), (0, 2)],
)
def test_accepts_relocation_ending_exactly_at_section_end(tmp_path, address, length):
    blob, relocation_offset, _ = relocation_fixture_parts()
    word = (length << 25) | (1 << 27)
    struct.pack_into("<iI", blob, relocation_offset, address, word)

    relocation = read_macho(write_fixture(tmp_path, bytes(blob)))["relocations"][0]

    assert relocation["address"] == 0x1000 + address


@pytest.mark.parametrize(
    ("address", "length"),
    [(4, 0), (3, 1), (1, 2)],
)
def test_rejects_relocation_field_crossing_section_end(tmp_path, address, length):
    blob, relocation_offset, _ = relocation_fixture_parts()
    word = (length << 25) | (1 << 27)
    struct.pack_into("<iI", blob, relocation_offset, address, word)

    with pytest.raises(MachOFormatError, match=r"relocation 0.*field.*section"):
        read_macho(write_fixture(tmp_path, bytes(blob)))


def test_rejects_eight_byte_relocation_length_for_legacy_i386(tmp_path):
    blob, relocation_offset, _ = relocation_fixture_parts()
    first_section_offset = HEADER.size + SEGMENT.size
    struct.pack_into("<I", blob, first_section_offset + 36, 8)
    struct.pack_into("<iI", blob, relocation_offset, 0, (3 << 25) | (1 << 27))

    with pytest.raises(
        MachOFormatError,
        match=(
            r"load command 0 section 0.*global 0.*relocation 0"
            rf".*file offset 0x{relocation_offset:x}.*length code 3.*i386"
        ),
    ):
        read_macho(write_fixture(tmp_path, bytes(blob)))


def test_local_absolute_relocation_uses_null_target(tmp_path):
    blob, relocation_offset, _ = relocation_fixture_parts()
    struct.pack_into("<iI", blob, relocation_offset, 0, 2 << 25)

    analysis = read_macho(write_fixture(tmp_path, bytes(blob)))

    validate_document("analysis-v1", analysis)
    assert analysis["relocations"][0]["target"] is None


def test_local_section_ordinal_resolves_to_section_name(tmp_path):
    blob, relocation_offset, _ = relocation_fixture_parts()
    struct.pack_into("<iI", blob, relocation_offset, 0, 2 | (2 << 25))

    relocation = read_macho(write_fixture(tmp_path, bytes(blob)))["relocations"][0]

    assert relocation["target"] == "__DATA,__data"


def test_absolute_addend_is_unsigned_little_endian_field_value(tmp_path):
    blob, _, text_offset = relocation_fixture_parts()
    blob[text_offset : text_offset + 4] = b"\xFE\xFF\xFF\xFF"

    relocation = read_macho(write_fixture(tmp_path, bytes(blob)))["relocations"][0]

    assert relocation["addend"] == 0xFFFFFFFE


def test_pc_relative_addend_is_signed_little_endian_displacement(tmp_path):
    blob, relocation_offset, text_offset = relocation_fixture_parts()
    blob[text_offset : text_offset + 4] = b"\xFC\xFF\xFF\xFF"
    word = (1 << 24) | (2 << 25) | (1 << 27)
    struct.pack_into("<iI", blob, relocation_offset, 0, word)

    relocation = read_macho(write_fixture(tmp_path, bytes(blob)))["relocations"][0]

    assert relocation["addend"] == -4
    metadata = read_macho(write_fixture(tmp_path, bytes(blob)))["extensions"]["macho"]["relocations"][0]
    assert metadata["pc_relative"] is True
    assert metadata["width"] == 4


@pytest.mark.parametrize("section_type", [0x1, 0xC, 0x12])
def test_zero_fill_sections_hash_logical_zeros_without_file_backing(
    tmp_path, section_type
):
    blob = bytearray(build_macho_fixture())
    first_section_offset = HEADER.size + SEGMENT.size
    logical_size = 16 * 1024 * 1024 + 3
    struct.pack_into("<I", blob, HEADER.size + 28, logical_size + 4)
    struct.pack_into("<I", blob, first_section_offset + 36, logical_size)
    struct.pack_into("<I", blob, first_section_offset + 40, 0xFFFFFFF0)
    struct.pack_into("<I", blob, first_section_offset + 56, section_type)
    second_section_offset = first_section_offset + SECTION.size
    struct.pack_into("<I", blob, second_section_offset + 32, 0x1000 + logical_size)

    analysis = read_macho(write_fixture(tmp_path, bytes(blob)))
    section = analysis["sections"][0]

    validate_document("analysis-v1", analysis)
    digest = hashlib.sha256()
    remaining = logical_size
    zeros = b"\0" * (1024 * 1024)
    while remaining:
        chunk_size = min(remaining, len(zeros))
        digest.update(zeros[:chunk_size])
        remaining -= chunk_size
    assert section["size"] == logical_size
    assert section["offset"] == 0xFFFFFFF0
    metadata = analysis["extensions"]["macho"]["sections"][0]
    assert metadata["ordinal"] == 1
    assert metadata["size"] == logical_size
    assert section["sha256"] == digest.hexdigest().upper()
    metadata = analysis["extensions"]["macho"]["sections"][0]
    assert metadata["flags"] == section_type
    assert metadata["type"] == section_type
    assert metadata["zero_fill"] is True
    assert metadata["initialized"] is False


def test_rejects_load_command_range_larger_than_declared_table(tmp_path):
    blob = patch_u32(build_macho_fixture(), 20, 8)

    with pytest.raises(MachOFormatError, match=r"command 0.*declared load-command table"):
        read_macho(write_fixture(tmp_path, blob))


def test_fixture_has_expected_header_for_test_sanity():
    values = HEADER.unpack_from(build_macho_fixture())
    magic, cpu, _, filetype, ncmds, sizeofcmds, _ = values
    assert (magic, cpu, filetype, ncmds) == (MH_MAGIC, CPU_TYPE_I386, MH_OBJECT, 3)
    assert sizeofcmds > SYMTAB.size


def relocation_fixture_parts():
    blob = bytearray(build_macho_fixture())
    first_section_offset = HEADER.size + SEGMENT.size
    text_offset = struct.unpack_from("<I", blob, first_section_offset + 40)[0]
    relocation_offset = struct.unpack_from("<I", blob, first_section_offset + 48)[0]
    return blob, relocation_offset, text_offset


def test_read_macho_accepts_a_linked_executable(tmp_path):
    path = write_fixture(tmp_path, build_macho_fixture(file_type=2))

    document = read_macho(path)

    assert document["input"]["architecture"] == "i386"
    assert any(section["name"] == "__TEXT,__text" for section in document["sections"])


def test_reads_big_endian_ppc_preload_image(tmp_path):
    blob = build_macho_fixture(
        architecture="ppc", file_type=MH_PRELOAD, base_address=0,
        text=b"\0" * 16, relocations=b"",
    )
    path = tmp_path / "ppc.o"
    path.write_bytes(blob)

    document = read_macho(path)

    assert document["input"]["architecture"] == "ppc"
    assert document["input"]["endianness"] == "big"
    assert [section["name"] for section in document["sections"]] == [
        "__TEXT,__text", "__DATA,__data",
    ]
    assert [section["size"] for section in document["sections"]] == [16, 4]
    assert document["symbols"] == [
        {"name": "_external", "address": 0, "binding": "external", "section": None}
    ]
    assert document["relocations"] == []
    assert document["extensions"]["macho"]["header"]["cpu_type"] == CPU_TYPE_POWERPC
    validate_document("analysis-v1", document)


def test_ppc_and_i386_documents_differ_only_in_identity_fields(tmp_path):
    def read(architecture):
        path = tmp_path / f"{architecture}.o"
        path.write_bytes(build_macho_fixture(architecture=architecture, relocations=b""))
        document = read_macho(path)
        document["input"].pop("path")
        document["input"].pop("sha256")
        return document

    little = read("i386")
    big = read("ppc")

    assert little["input"] == {"size": big["input"]["size"], "architecture": "i386",
                               "endianness": "little"}
    assert big["input"]["architecture"] == "ppc"
    assert little["sections"] == big["sections"]
    assert little["symbols"] == big["symbols"]


def test_rejects_swapped_header_by_naming_the_cpu_type(tmp_path):
    # Bytes FE ED FA CE read big-endian are a valid magic, so the CPU type is
    # what exposes a little-endian image mislabelled as big-endian.
    blob = patch_u32(build_macho_fixture(), 0, 0xCEFAEDFE)
    path = tmp_path / "swapped.o"
    path.write_bytes(blob)

    with pytest.raises(MachOFormatError, match="CPU type"):
        read_macho(path)


def write_ppc(tmp_path, text, relocations, name="ppc.o"):
    path = tmp_path / name
    path.write_bytes(build_macho_fixture(
        architecture="ppc", text=text, relocations=relocations,
    ))
    return path


def semantic(document):
    return {entry["address"]: entry for entry in document["relocations"]}


def test_ppc_ha16_pair_applies_the_signed_low_half(tmp_path):
    # lis r3,2 ; addi r3,r3,-1 -> external symbol value 0x0001FFFF
    text = struct.pack(">II", 0x3C600002, 0x3863FFFF)
    relocations = (
        ppc_relocation(0, 0, kind=PPC_RELOC_HA16, extern=1) + ppc_pair(0xFFFF)
    )

    document = read_macho(write_ppc(tmp_path, text, relocations))

    assert semantic(document)[0x1000] == {
        "address": 0x1000, "kind": "ppc-ha16-32-absolute",
        "target": "_external", "addend": 0x1FFFF,
    }


def test_ppc_hi16_pair_concatenates_without_the_ha16_adjustment(tmp_path):
    text = struct.pack(">II", 0x3C600002, 0x3863FFFF)
    relocations = (
        ppc_relocation(0, 0, kind=PPC_RELOC_HI16, extern=1) + ppc_pair(0xFFFF)
    )

    document = read_macho(write_ppc(tmp_path, text, relocations))

    assert semantic(document)[0x1000]["addend"] == 0x2FFFF
    assert semantic(document)[0x1000]["kind"] == "ppc-hi16-32-absolute"


def test_ppc_lo16_pair_takes_the_high_half_from_the_pair(tmp_path):
    # __data sits at 0x1008 when __text is eight bytes long.
    text = struct.pack(">II", 0x38601008, 0x60000000)
    relocations = ppc_relocation(0, 2, kind=PPC_RELOC_LO16) + ppc_pair(0x0001)

    document = read_macho(write_ppc(tmp_path, text, relocations))

    assert semantic(document)[0x1000] == {
        "address": 0x1000, "kind": "ppc-lo16-32-absolute",
        "target": "__DATA,__data", "addend": 0x10000,
    }


def test_ppc_vanilla_pointer_is_section_relative(tmp_path):
    text = struct.pack(">II", 0x00001004, 0x00000000)
    relocations = ppc_relocation(0, 1, kind=PPC_RELOC_VANILLA)

    document = read_macho(write_ppc(tmp_path, text, relocations))

    assert semantic(document)[0x1000] == {
        "address": 0x1000, "kind": "ppc-vanilla-32-absolute",
        "target": "__TEXT,__text", "addend": 4,
    }


def test_ppc_jbsr_names_the_symbol_and_records_the_island(tmp_path):
    # bl +8 into the island at 0x1008, whose real target is the symbol.
    text = struct.pack(">III", 0x48000009, 0x60000000, 0x4E800020)
    relocations = ppc_relocation(0, 0, kind=PPC_RELOC_JBSR, extern=1) + ppc_pair(0x1004)

    document = read_macho(write_ppc(tmp_path, text, relocations))

    assert semantic(document)[0x1000] == {
        "address": 0x1000, "kind": "ppc-jbsr-24-pc-relative",
        "target": "_external", "addend": 0x1004,
    }
    raw = document["extensions"]["macho"]["relocations"]
    assert [entry["kind"] for entry in raw] == [
        "ppc-jbsr-24-pc-relative", "ppc-pair-16-absolute",
    ]
    assert raw[0]["original_bytes"] == "48000009"


def test_ppc_br24_resolves_against_the_relocation_address(tmp_path):
    text = struct.pack(">II", 0x48000009, 0x60000000)
    relocations = ppc_relocation(0, 1, kind=PPC_RELOC_BR24, pcrel=1)

    document = read_macho(write_ppc(tmp_path, text, relocations))

    assert semantic(document)[0x1000] == {
        "address": 0x1000, "kind": "ppc-br24-24-pc-relative",
        "target": "__TEXT,__text", "addend": 8,
    }


def test_ppc_raw_relocations_keep_every_file_entry(tmp_path):
    text = struct.pack(">II", 0x3C600002, 0x3863FFFF)
    relocations = (
        ppc_relocation(0, 0, kind=PPC_RELOC_HA16, extern=1) + ppc_pair(0xFFFF)
    )

    document = read_macho(write_ppc(tmp_path, text, relocations))

    raw = document["extensions"]["macho"]["relocations"]
    assert len(raw) == 2
    assert len(document["relocations"]) == 1
    assert [entry["scattered"] for entry in raw] == [False, False]


def test_ppc_pair_raw_reports_the_pair_bits_not_principal_bits(tmp_path):
    # HA16 has an external principal, but the pair's r_extern is 0.
    # The raw PAIR record should report external=False from the pair itself.
    text = struct.pack(">II", 0x3C600002, 0x3863FFFF)
    relocations = (
        ppc_relocation(0, 0, kind=PPC_RELOC_HA16, extern=1) + ppc_pair(0xFFFF)
    )

    document = read_macho(write_ppc(tmp_path, text, relocations))

    raw = document["extensions"]["macho"]["relocations"]
    assert len(raw) == 2
    assert raw[0]["external"] is True
    assert raw[0]["kind"] == "ppc-ha16-32-absolute"
    assert raw[1]["external"] is False
    assert raw[1]["kind"] == "ppc-pair-16-absolute"


def test_ppc_principal_without_its_pair_is_rejected(tmp_path):
    text = struct.pack(">II", 0x3C600002, 0x60000000)
    relocations = (
        ppc_relocation(0, 0, kind=PPC_RELOC_HA16, extern=1)
        + ppc_relocation(4, 1, kind=PPC_RELOC_VANILLA)
    )

    with pytest.raises(MachOFormatError, match="requires a PAIR"):
        read_macho(write_ppc(tmp_path, text, relocations))


def test_ppc_orphan_pair_is_rejected(tmp_path):
    text = struct.pack(">II", 0x60000000, 0x60000000)
    relocations = ppc_pair(0x1234)

    with pytest.raises(MachOFormatError, match="unexpected PAIR"):
        read_macho(write_ppc(tmp_path, text, relocations))


def test_ppc_unsupported_relocation_type_names_type_and_offset(tmp_path):
    text = struct.pack(">II", 0x60000000, 0x60000000)
    relocations = ppc_relocation(0, 1, kind=9)

    with pytest.raises(MachOFormatError, match=r"relocation type 9.*file offset 0x"):
        read_macho(write_ppc(tmp_path, text, relocations))


def test_ppc_scattered_lo16_resolves_through_the_scattered_value(tmp_path):
    # __data sits at 0x1008; the field names 0x100C, four bytes into it.
    text = struct.pack(">II", 0x3860100C, 0x60000000)
    relocations = (
        ppc_scattered(0, 0x1008, kind=PPC_RELOC_LO16) + ppc_pair(0x0000)
    )

    document = read_macho(write_ppc(tmp_path, text, relocations))

    assert semantic(document)[0x1000] == {
        "address": 0x1000, "kind": "ppc-scattered-lo16-32-absolute",
        "target": "__DATA,__data", "addend": 4,
    }


def test_ppc_scattered_ha16_applies_the_signed_low_half(tmp_path):
    text = struct.pack(">II", 0x3C600002, 0x60000000)
    relocations = (
        ppc_scattered(0, 0x1000, kind=PPC_RELOC_HA16) + ppc_pair(0xFFFF)
    )

    document = read_macho(write_ppc(tmp_path, text, relocations))

    assert semantic(document)[0x1000] == {
        "address": 0x1000, "kind": "ppc-scattered-ha16-32-absolute",
        "target": "__TEXT,__text", "addend": 0x1EFFF,
    }


def test_ppc_sectdiff_reports_the_difference_and_its_addend(tmp_path):
    # field = (__data - __text) + 8 = 0x1008 - 0x1000 + 8 = 0x10
    text = struct.pack(">II", 0x00000010, 0x60000000)
    relocations = (
        ppc_scattered(0, 0x1008, kind=PPC_RELOC_SECTDIFF)
        + ppc_scattered(0, 0x1000, kind=PPC_RELOC_PAIR)
    )

    document = read_macho(write_ppc(tmp_path, text, relocations))

    assert semantic(document)[0x1000] == {
        "address": 0x1000, "kind": "ppc-sectdiff-32-absolute",
        "target": "__DATA,__data", "addend": 8,
    }


def test_ppc_scattered_value_outside_every_section_is_rejected(tmp_path):
    text = struct.pack(">II", 0x3860100C, 0x60000000)
    relocations = (
        ppc_scattered(0, 0x9000, kind=PPC_RELOC_LO16) + ppc_pair(0x0000)
    )

    with pytest.raises(MachOFormatError, match="scattered relocation target"):
        read_macho(write_ppc(tmp_path, text, relocations))


def test_ppc_non_four_byte_relocation_length_is_rejected(tmp_path):
    # Every relocation in the reference binaries has r_length == 2 (spec
    # §3.2); a one-byte field (length 0) must be refused rather than decoded
    # as if it were the whole four-byte instruction word.
    text = struct.pack(">II", 0x3C620F3A, 0x60000000)
    relocations = ppc_relocation(0, 1, kind=PPC_RELOC_VANILLA, length=0)

    with pytest.raises(MachOFormatError, match="relocation length code 0"):
        read_macho(write_ppc(tmp_path, text, relocations))


def test_ppc_pair_with_non_four_byte_length_is_rejected(tmp_path):
    text = struct.pack(">II", 0x3C600002, 0x3863FFFF)
    relocations = (
        ppc_relocation(0, 0, kind=PPC_RELOC_HA16, extern=1) + ppc_pair(0xFFFF, length=1)
    )

    with pytest.raises(MachOFormatError, match="relocation length code 1"):
        read_macho(write_ppc(tmp_path, text, relocations))


def test_ppc_sectdiff_requires_a_scattered_pair(tmp_path):
    text = struct.pack(">II", 0x00000010, 0x60000000)
    relocations = (
        ppc_scattered(0, 0x1008, kind=PPC_RELOC_SECTDIFF) + ppc_pair(0x0000)
    )

    with pytest.raises(MachOFormatError, match="SECTDIFF requires a scattered PAIR"):
        read_macho(write_ppc(tmp_path, text, relocations))
