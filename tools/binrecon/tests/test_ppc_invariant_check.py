import struct

from macho_fixture import (
    PPC_RELOC_HA16,
    PPC_RELOC_JBSR,
    PPC_RELOC_LO16,
    PPC_RELOC_VANILLA,
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


def test_scattered_ha16_and_lo16_pair_agreeing_is_not_reported(tmp_path):
    # HA16 at offset 0, LO16 at offset 4 (the real "lis"/"addi" spacing seen
    # in SCSIServer_reloc). Both halves reconstruct 0x12345678: HA16's own
    # low 16 bits (0x1234) are its high half, paired with 0x5678 from its
    # PAIR; LO16's own low 16 bits (0x5678) are its low half, paired with
    # 0x1234 from its PAIR.
    text = struct.pack(">II", 0x00001234, 0x00005678)
    relocations = (
        ppc_scattered(0, 0x1008, kind=PPC_RELOC_HA16) + ppc_pair(0x5678)
        + ppc_scattered(4, 0x1008, kind=PPC_RELOC_LO16) + ppc_pair(0x1234)
    )

    assert check_document(_document(tmp_path, text, relocations)) == []


def test_scattered_ha16_and_lo16_pair_disagreeing_is_reported(tmp_path):
    # Same as above, but LO16's PAIR names 0x1235 instead of 0x1234, so
    # LO16 reconstructs 0x12355678 -- 0x10000 away from HA16's 0x12345678.
    # This is the shape a dropped HA16 sign extension produces: only one
    # half of a real pair moves.
    text = struct.pack(">II", 0x00001234, 0x00005678)
    relocations = (
        ppc_scattered(0, 0x1008, kind=PPC_RELOC_HA16) + ppc_pair(0x5678)
        + ppc_scattered(4, 0x1008, kind=PPC_RELOC_LO16) + ppc_pair(0x1235)
    )

    violations = check_document(_document(tmp_path, text, relocations))

    assert len(violations) == 1
    assert "reconstruct different values" in violations[0]


def test_ha16_pairs_with_matching_register_not_nearest_lo16(tmp_path):
    # Mirrors drvPPCMesh_reloc's Site 1 (0x120-0x128): the nearest LO16 by
    # address (0x816B0000, base r11) is an unrelated address computation.
    # The true partner sits one instruction further out, uses r9 -- the
    # register the addis actually wrote -- and agrees with the HA16 once
    # paired correctly (both reconstruct 0x12345678).
    text = struct.pack(
        ">III",
        0x3D201234,  # addis r9,r0,0x1234    <- HA16 (writes r9)
        0x816B0000,  # lwz   r11,r11,0x0000  <- nearer LO16, wrong base (r11)
        0x81295678,  # lwz   r9,r9,0x5678    <- true partner LO16 (base r9)
    )
    relocations = (
        ppc_scattered(0, 0x100C, kind=PPC_RELOC_HA16) + ppc_pair(0x5678)
        + ppc_scattered(4, 0x100C, kind=PPC_RELOC_LO16) + ppc_pair(0x0000)
        + ppc_scattered(8, 0x100C, kind=PPC_RELOC_LO16) + ppc_pair(0x1234)
    )

    assert check_document(_document(tmp_path, text, relocations)) == []


def test_second_ha16_not_paired_with_preceding_lo16(tmp_path):
    # Mirrors drvPPCMesh_reloc's Site 2 (0x2b24-0x2b30): two consecutive
    # HA16/LO16 pairs, both through r9, so the register alone can't tell
    # them apart. The second HA16 sits exactly as far from the first pair's
    # LO16 as from its own -- nearest-by-address alone picks the preceding,
    # wrong one; only preferring the following LO16 gets it right.
    text = struct.pack(
        ">IIII",
        0x3D201234,  # addis r9,r0,0x1234   <- HA16 #1 (writes r9)
        0x83295678,  # addi  r25,r9,0x5678  <- LO16 #1, true partner of #1
        0x3D202222,  # addis r9,r0,0x2222   <- HA16 #2 (writes r9)
        0x83493333,  # addi  r26,r9,0x3333  <- LO16 #2, true partner of #2
    )
    relocations = (
        ppc_scattered(0, 0x1010, kind=PPC_RELOC_HA16) + ppc_pair(0x5678)
        + ppc_scattered(4, 0x1010, kind=PPC_RELOC_LO16) + ppc_pair(0x1234)
        + ppc_scattered(8, 0x1010, kind=PPC_RELOC_HA16) + ppc_pair(0x3333)
        + ppc_scattered(12, 0x1010, kind=PPC_RELOC_LO16) + ppc_pair(0x2222)
    )

    assert check_document(_document(tmp_path, text, relocations)) == []


def test_ppc_jbsr_island_inside_text_is_not_reported(tmp_path):
    # bl +8 into the island at 0x1008, which sits inside __TEXT,__text.
    text = struct.pack(">III", 0x48000009, 0x60000000, 0x4E800020)
    relocations = ppc_relocation(0, 0, kind=PPC_RELOC_JBSR, extern=1) + ppc_pair(0x1004)

    assert check_document(_document(tmp_path, text, relocations)) == []


def test_ppc_jbsr_island_outside_text_is_reported(tmp_path):
    # A branch field of 0x02000000 has its sign bit set, so the displacement
    # is -0x02000000 -- far before every section, so the island can't be
    # __TEXT,__text.
    text = struct.pack(">II", 0x02000000, 0x60000000)
    relocations = ppc_relocation(0, 0, kind=PPC_RELOC_JBSR, extern=1) + ppc_pair(0x0000)

    violations = check_document(_document(tmp_path, text, relocations))

    assert len(violations) == 1
    assert "outside __TEXT,__text" in violations[0]


def _objc_document(tmp_path, *, section, target, extra_sections=()):
    text = struct.pack(">II", 0x00000000, 0x60000000)
    relocations = ppc_relocation(0, 1, kind=PPC_RELOC_VANILLA)
    document = _document(tmp_path, text, relocations)
    document["sections"] = document["sections"] + list(extra_sections)

    # addend 0: the reconstructed pointer lands exactly at target's base,
    # so the ordinary address-form invariant (checked earlier in
    # check_document) is trivially satisfied and only the __OBJC branch
    # under test decides the outcome.
    document["relocations"][0]["target"] = target
    document["relocations"][0]["addend"] = 0
    raw = document["extensions"]["macho"]["relocations"][0]
    raw["section"] = section
    raw["target"] = target
    raw["addend"] = 0
    return document


def test_objc_vanilla_pointing_outside_objc_or_text_is_reported(tmp_path):
    document = _objc_document(
        tmp_path, section="__OBJC,__message_refs", target="__DATA,__data",
    )

    violations = check_document(document)

    assert len(violations) == 1
    assert "points into __DATA,__data" in violations[0]


def test_objc_vanilla_pointing_into_objc_is_not_reported(tmp_path):
    objc_section = {
        "name": "__OBJC,__message_refs", "address": 0x2000,
        "offset": 0, "size": 16, "permissions": 3, "sha256": "",
    }
    document = _objc_document(
        tmp_path, section="__OBJC,__cls_meth", target="__OBJC,__message_refs",
        extra_sections=[objc_section],
    )

    assert check_document(document) == []


def test_objc_method_list_vanilla_pointing_into_text_is_not_reported(tmp_path):
    # __cls_meth/__inst_meth/__cat_inst_meth are objc_method structs whose
    # third field (IMP imp) is a real code pointer -- the authorized
    # allowance from Finding 3.
    document = _objc_document(
        tmp_path, section="__OBJC,__cls_meth", target="__TEXT,__text",
    )

    assert check_document(document) == []


def test_objc_category_class_method_list_pointing_into_text_is_not_reported(tmp_path):
    # __cat_cls_meth holds the objc_method structs for class methods declared
    # in a category -- the same IMP-field justification as __cat_inst_meth.
    # drvPPCSym8xx is the first measured driver to carry one
    # (+[Sym8xxController(Init) probe:]), and it was reported as a violation
    # because the allowance listed only three of the four method-list sections.
    document = _objc_document(
        tmp_path, section="__OBJC,__cat_cls_meth", target="__TEXT,__text",
    )

    assert check_document(document) == []


def test_objc_non_method_list_vanilla_pointing_into_text_is_reported(tmp_path):
    # Same destination as above, but from a section that isn't a method
    # list -- the IMP-field justification doesn't apply here, so the
    # allowance must not cover it.
    document = _objc_document(
        tmp_path, section="__OBJC,__message_refs", target="__TEXT,__text",
    )

    violations = check_document(document)

    assert len(violations) == 1
    assert "points into __TEXT,__text" in violations[0]
