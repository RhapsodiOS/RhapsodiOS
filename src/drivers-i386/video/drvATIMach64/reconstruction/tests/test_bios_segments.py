from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LKS = ROOT.parent / "ATIMach64DisplayDriver.drvproj/ATIMach64DisplayDriver.lksproj"


def test_bios_wrapper_matches_register_buffer_boundary_and_symbol_contract():
    source = (LKS / "ATIbios16.c").read_text(encoding="utf-8")
    assert "int ATIbios16(ATIBIOSRegisters *registers)" in source
    assert "kernDataSel = 0x10;" in source
    assert "registers->entryOffset > 0xffffU" in source
    assert "ATI_Bios_Offset = (unsigned short)registers->entryOffset;" in source
    assert "ATI_Bios_Selector = registers->codeSelector;" in source
    assert "registers->codeSelector = 0x90;" in source
    assert "registers->entryOffset = 0;" in source
    assert "_ATIbios32(registers);" in source
    assert "return -1;" in source and "return 0;" in source


def test_segment_implementation_preserves_reference_boundaries_and_restore_order():
    source = (LKS / "ATI_BIOS.m").read_text(encoding="utf-8")
    assert "memcpy(privateBytes, gdtEntry(0x80), 8);" in source
    assert "memcpy(privateBytes + 8, gdtEntry(0x90), 8);" in source
    assert "memcpy(privateBytes + 24, gdtEntry(0x98), 8);" in source
    assert "IOMalloc(0x800)" in source
    assert "ATI_Bios_StackOffset = 0x800;" in source
    assert "ATI_Bios_StackSelector = 0x98;" in source
    assert "if (size > 0x10000)" in source
    assert "limit = size - 1;" in source
    assert "memcpy(privateBytes + 16, gdtEntry(0x88), 8);" in source
    do_bios = source.split("- (int)doBios:", 1)[1].split("- (int)loadCRTC_comm:", 1)[0]
    assert do_bios.index("[self restoreCodeSegments]") < do_bios.index("[self restoreDataSegment]")


def test_protected_transfers_keep_exact_symbols_and_far_operand_labels():
    source = (LKS / "ATIbios.s").read_text(encoding="utf-8")
    for token in (
        ".globl __bios16", ".globl __ATIbios32", "bios16_far_jump:",
        "bios32_far_call:", ".byte\t0xea", ".byte\t0x9a",
        ".byte\t0x66, 0x1f", "_kernDataSel", "_ATI_Bios_Offset",
        "_ATI_Bios_Selector", "_ATI_Bios_StackOffset",
        "_ATI_Bios_StackSelector", "pushal", "pushfl", "popfl", "cli",
    ):
        assert token in source
    assert "lock" not in source.lower()


def test_native_bios_fixture_never_links_or_executes_privileged_assembly():
    source = (LKS / "tests/test_bios_segments.m").read_text(encoding="utf-8")
    makefile = (LKS / "tests/Makefile").read_text(encoding="utf-8")
    assert "void _ATIbios32(ATIBIOSRegisters *registers)" in source
    assert "ATIbios16(&registers) == -1" in source
    assert "size:0x10001U] == 3" in source
    assert "$(LKS)/ATIbios.s" not in makefile


def test_assembly_verifier_checks_symbols_relocations_and_patched_operands():
    source = (ROOT / "verify_assembly.py").read_text(encoding="utf-8")
    for token in (
        '"__bios16": (0x26E0, 117, "bios16_end", 0xEA)',
        '"__ATIbios32": (0x27B8, 203, "bios32_end", 0x9A)',
        "_canonical_code(", "_relocation_width(",
        "runtime-patched far operand has a relocation",
        "symbolic relocation targets differ",
    ):
        assert token in source
