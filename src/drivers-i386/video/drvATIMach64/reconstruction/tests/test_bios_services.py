from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LKS = ROOT.parent / "ATIMach64DisplayDriver.drvproj/ATIMach64DisplayDriver.lksproj"


def test_public_service_selectors_and_function_numbers_are_implemented():
    source = (LKS / "ATI_BIOS.m").read_text(encoding="utf-8")
    for token in (
        "- init", "+ (char)ATIPresent:", "function:0", "function:2",
        "function:1", "function:5", "function:6", "function:9",
        "function:12", "function:13", "function:14", "function:15",
        "function:18", "function:21", "return ATIBIOSStatusInvalid;",
    ):
        assert token in source


def test_service_tests_cover_scan_boundaries_register_packing_and_statuses():
    source = (LKS / "tests/test_bios_segments.m").read_text(encoding="utf-8")
    for token in (
        "testROMPresenceAndInitScan", "0xef000", "segmentAddress == 0xf0000",
        "testBIOSServicePackingAndBounds", "apertureAdrs:0x12345",
        "setDPMSMode:5", "setAPMState:4", "testBIOSQueryOutputPacking",
        "address == 0x12345000", "query == 0xfeedbeef",
    ):
        assert token in source


def test_rom_pointer_translation_is_test_only():
    source = (LKS / "ATI_BIOS.m").read_text(encoding="utf-8")
    assert "#if defined(ATI_BIOS_TEST)" in source
    assert "#define ATI_BIOS_ROM_ADDRESS(address) ATI_mockROMAddress(address)" in source
    assert "#define ATI_BIOS_ROM_ADDRESS(address) ((const unsigned char *)(address))" in source
    makefile = (LKS / "tests/Makefile").read_text(encoding="utf-8")
    assert "-DATI_BIOS_TEST" in makefile
