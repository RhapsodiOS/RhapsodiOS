import struct

import pytest

from macho_fixture import (
    PPC_RELOC_HA16,
    PPC_RELOC_LO16,
    build_macho_fixture,
    ppc_pair,
    ppc_relocation,
    ppc_scattered,
)
from binrecon.macho import read_macho
from ppc_invariant_check import check_document


def _document(tmp_path, text, relocations):
    path = tmp_path / "ppc.o"
    path.write_bytes(build_macho_fixture(
        architecture="ppc", text=text, relocations=relocations,
    ))
    return read_macho(path)


def test_clean_image_reports_no_violations(tmp_path):
    text = struct.pack(">II", 0x38601008, 0x60000000)
    relocations = ppc_relocation(0, 2, kind=PPC_RELOC_LO16) + ppc_pair(0x0000)

    assert check_document(_document(tmp_path, text, relocations)) == []


def test_section_target_resolving_outside_its_section_is_reported(tmp_path):
    # Claims __DATA,__data but reconstructs 0x00050000, far outside it.
    text = struct.pack(">II", 0x38600000, 0x60000000)
    relocations = ppc_relocation(0, 2, kind=PPC_RELOC_LO16) + ppc_pair(0x0005)

    violations = check_document(_document(tmp_path, text, relocations))

    assert len(violations) == 1
    assert "__DATA,__data" in violations[0]
    assert "0x50000" in violations[0]


def test_missing_pair_records_are_reported(tmp_path):
    text = struct.pack(">II", 0x3C600002, 0x3863FFFF)
    relocations = ppc_relocation(0, 0, kind=PPC_RELOC_HA16, extern=1) + ppc_pair(0xFFFF)
    document = _document(tmp_path, text, relocations)
    document["extensions"]["macho"]["relocations"] = [
        entry for entry in document["extensions"]["macho"]["relocations"]
        if entry["kind"] != "ppc-pair-16-absolute"
    ]

    violations = check_document(document)

    assert any("PAIR" in violation for violation in violations)


def test_scattered_relocation_far_outside_target_section_is_not_a_violation(tmp_path):
    # HA16 scattered relocations store target - anchor (a difference), not
    # an address, so the reconstructed field lands far outside the target
    # section on real binaries (e.g. SCSIServer_reloc) -- that must not be
    # reported as a violation.
    text = struct.pack(">II", 0x3C600002, 0x60000000)
    relocations = ppc_scattered(0, 0x1000, kind=PPC_RELOC_HA16) + ppc_pair(0xFFFF)

    assert check_document(_document(tmp_path, text, relocations)) == []


def test_scattered_relocation_naming_no_section_is_reported(tmp_path):
    text = struct.pack(">II", 0x3C600002, 0x60000000)
    relocations = ppc_scattered(0, 0x1000, kind=PPC_RELOC_HA16) + ppc_pair(0xFFFF)
    document = _document(tmp_path, text, relocations)
    document["relocations"][0]["target"] = "__DATA,__bogus"

    violations = check_document(document)

    assert len(violations) == 1
    assert "__DATA,__bogus" in violations[0]
