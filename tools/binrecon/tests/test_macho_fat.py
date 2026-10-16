import struct

import pytest

from binrecon.macho import (
    MH_DYLIB, MachOFormatError, extract_slice, is_fat, load_image, read_macho,
)
from macho_fixture import build_macho_fixture


def _fat(*slices):
    """Pack (cpu_type, payload) pairs into a fat container."""
    header = struct.pack(">2I", 0xCAFEBABE, len(slices))
    entries, blob, offset = b"", b"", 4096
    for cpu_type, payload in slices:
        entries += struct.pack(">5I", cpu_type, 0, offset, len(payload), 12)
        blob += payload
        offset += len(payload)
    padding = 4096 - len(header) - len(entries)
    assert padding >= 0, "fat header table does not fit before the first slice"
    return header + entries + b"\0" * padding + blob


def test_recognizes_a_fat_container():
    assert is_fat(_fat((7, build_macho_fixture(file_type=MH_DYLIB))))
    assert not is_fat(build_macho_fixture(file_type=MH_DYLIB))


def test_extracts_the_named_slice():
    i386 = build_macho_fixture(file_type=MH_DYLIB, architecture="i386")
    ppc = build_macho_fixture(file_type=MH_DYLIB, architecture="ppc")

    assert extract_slice(_fat((7, i386), (18, ppc)), "i386") == i386
    assert extract_slice(_fat((7, i386), (18, ppc)), "ppc") == ppc


def test_missing_slice_names_what_is_present():
    ppc = build_macho_fixture(file_type=MH_DYLIB, architecture="ppc")

    with pytest.raises(MachOFormatError, match="ppc"):
        extract_slice(_fat((18, ppc)), "i386")


def test_a_slice_running_past_the_file_is_an_error():
    truncated = _fat((7, build_macho_fixture(file_type=MH_DYLIB)))[:-16]

    with pytest.raises(MachOFormatError, match="past end of file"):
        extract_slice(truncated, "i386")


def test_load_image_rejects_a_fat_container(tmp_path):
    path = tmp_path / "Fat"
    path.write_bytes(_fat((7, build_macho_fixture(file_type=MH_DYLIB))))

    with pytest.raises(MachOFormatError, match="extract-slice"):
        read_macho(path)


def test_load_image_returns_the_payload_and_document(tmp_path):
    thin = build_macho_fixture(file_type=MH_DYLIB)
    path = tmp_path / "Thin"
    path.write_bytes(thin)

    payload, document = load_image(path)

    assert payload == thin
    assert document["input"]["architecture"] == "i386"
    assert document["input"]["size"] == len(thin)
