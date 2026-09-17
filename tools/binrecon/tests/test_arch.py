import dataclasses

import pytest

from binrecon.arch import (
    I386,
    PPC,
    Architecture,
    ArchitectureError,
    architecture_for_cpu_type,
    architecture_for_name,
)


def test_descriptors_carry_the_per_architecture_facts():
    assert (I386.name, I386.endianness, I386.struct_prefix) == ("i386", "little", "<")
    assert (I386.cpu_type, I386.ida_processor, I386.relocation_decoder) == (7, "metapc", "i386")
    assert (PPC.name, PPC.endianness, PPC.struct_prefix) == ("ppc", "big", ">")
    assert (PPC.cpu_type, PPC.ida_processor, PPC.relocation_decoder) == (18, "ppc", "ppc")


def test_layouts_agree_in_size_and_differ_in_byte_order():
    for field in dataclasses.fields(I386.layouts):
        left = getattr(I386.layouts, field.name)
        right = getattr(PPC.layouts, field.name)
        assert left.size == right.size
        assert left.format.startswith("<") and right.format.startswith(">")
    assert I386.layouts.header.size == 28
    assert I386.layouts.section.size == 68
    assert I386.layouts.nlist.size == 12
    assert I386.layouts.relocation_info.size == 8


def test_lookup_by_name():
    assert architecture_for_name("i386") is I386
    assert architecture_for_name("ppc") is PPC


def test_unknown_name_names_the_supported_set():
    with pytest.raises(ArchitectureError, match="i386, ppc"):
        architecture_for_name("mips")


def test_lookup_by_cpu_type_requires_matching_byte_order():
    assert architecture_for_cpu_type(7, "little") is I386
    assert architecture_for_cpu_type(18, "big") is PPC
    with pytest.raises(ArchitectureError, match="read as big-endian"):
        architecture_for_cpu_type(7, "big")
    with pytest.raises(ArchitectureError, match="CPU type 12"):
        architecture_for_cpu_type(12, "big")


def test_descriptors_are_immutable():
    with pytest.raises(dataclasses.FrozenInstanceError):
        PPC.name = "other"
    assert isinstance(PPC, Architecture)
