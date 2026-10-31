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


def test_services_remain_on_primary_class_in_reference_metadata():
    source = (LKS / "ATI_BIOS.m").read_text(encoding="utf-8")
    assert "@implementation ATI_BIOS (Services)" not in source
    assert source.count("@implementation ATI_BIOS\n") == 1


def test_dpms_and_apm_getters_access_only_ecx_low_byte():
    source = (LKS / "ATI_BIOS.m").read_text(encoding="utf-8")
    for selector, output, mask in (
        ("getDPMSMode:", "mode", 3),
        ("getAPMState:", "state", 3),
        ("getIOBaseAddress:", "relocatable", 1),
    ):
        method = source.split("- (int)" + selector, 1)[1].split("\n- (", 1)[0]
        assert "ATIBIOSRegisters *registerBuffer = &registers;" in method
        assert "initBIOSBuf:registerBuffer" in method
        assert "doBios:registerBuffer" in method
        assert "*((unsigned char *)&registerBuffer->ecx) = 0;" in method
        assert "*%s = *((unsigned char *)&registerBuffer->ecx) & %d;" % (output, mask) in method
        if selector == "getIOBaseAddress:":
            assert "*address = registerBuffer->edx;" in method


def test_dpms_and_apm_setters_pack_ecx_as_a_byte():
    source = (LKS / "ATI_BIOS.m").read_text(encoding="utf-8")
    for selector, input_name, function_number in (
        ("setDPMSMode:", "mode", 12),
        ("setAPMState:", "state", 14),
    ):
        method = source.split("- (int)" + selector, 1)[1].split("\n- (", 1)[0]
        assert "ATIBIOSRegisters *registerBuffer = &registers;" in method
        assert "initBIOSBuf:registerBuffer function:%d" % function_number in method
        assert "*((unsigned char *)&registerBuffer->ecx) = %s & 3;" % input_name in method
        assert "doBios:registerBuffer dataSeg:0" in method


def test_refresh_rate_bios_register_stores_match_reference_widths():
    source = (LKS / "ATI_BIOS.m").read_text(encoding="utf-8")
    method = source.split("- (int)getRefreshRate:", 1)[1].split("\n- (", 1)[0]
    assert "ATIBIOSRegisters *registerBuffer = &registers;" in method
    assert "initBIOSBuf:registerBuffer function:21" in method
    assert "*((unsigned char *)&registerBuffer->ebx) = 0;" in method
    assert "*((unsigned short *)&registerBuffer->edx) = 0x88;" in method
    assert "*((unsigned short *)&registerBuffer->ebx) = 0;" in method
    assert "if (*((unsigned char *)&registerBuffer->eax + 1) != 0)" in method
    assert "*((unsigned char *)&registerBuffer->eax + 1));" in method


def test_set_vga_mode_keeps_register_buffer_live_and_reads_ah_as_byte():
    source = (LKS / "ATI_BIOS.m").read_text(encoding="utf-8")
    method = source.split("- (int)setVGAMode:", 1)[1].split("\n- (", 1)[0]
    assert "ATIBIOSRegisters *registerBuffer = &registers;" in method
    assert "initBIOSBuf:registerBuffer function:1" in method
    assert "*((unsigned char *)&registerBuffer->ecx) =" in method
    assert "modeFlag = (mode == 0);" in method
    assert "gammaFlag = (gamma != 0) ? 0x80 : 0;" in method
    assert "*((unsigned char *)&registerBuffer->ecx) = modeFlag | gammaFlag;" in method
    assert "doBios:registerBuffer dataSeg:0" in method
    assert "if (result != ATIBIOSStatusSuccess)" in method
    assert 'IOLog("ATI_BIOS setDisplayMode: ATIbios32() returned %d\\n", result);' in method
    assert "*((unsigned char *)&registerBuffer->eax + 1) != 0" in method
    assert 'IOLog("ATI_BIOS setDisplayMode: ah = 0x%x on return from ATIbios32()\\n",' in method
    assert method.count("IOLog(") == 2


def test_set_aperture_enable_packs_flags_into_ecx_low_byte():
    source = (LKS / "ATI_BIOS.m").read_text(encoding="utf-8")
    method = source.split("- (int)setApertureEnable:", 1)[1].split("\n- (", 1)[0]
    assert "initBIOSBuf:&registers function:5" in method
    assert "*((unsigned char *)&registers.ecx) = flags;" in method
    assert "registers.ecx = flags;" not in method
    assert "registers.ebx = address >> 20;" in method


def test_short_query_checks_and_reports_ah_as_a_byte():
    source = (LKS / "ATI_BIOS.m").read_text(encoding="utf-8")
    method = source.split("- (int)shortQuery:", 1)[1].split("\n- (", 1)[0]
    assert "*((unsigned char *)&registers.eax + 1) != 0" in method
    assert "*((unsigned char *)&registers.eax + 1));" in method
    assert "(registers.eax >> 8) & 0xff" not in method


def test_device_query_uses_reference_register_widths_and_order():
    source = (LKS / "ATI_BIOS.m").read_text(encoding="utf-8")
    method = source.split("- (int)deviceQuery:", 1)[1].split("\n- (", 1)[0]
    flag_write = "*((unsigned char *)&registers.ecx) = (query == 0);"
    data_segment = "result = [self createDataSegment:(unsigned int)buffer size:bufferSize];"
    ebx_write = "*((unsigned short *)&registers.ebx) = 0;"
    edx_write = "*((unsigned short *)&registers.edx) = 0x88;"
    assert flag_write in method
    assert ebx_write in method
    assert edx_write in method
    assert method.index(flag_write) < method.index(data_segment)
    assert method.index(data_segment) < method.index(ebx_write) < method.index(edx_write)
    assert "if (*((unsigned char *)&registers.eax + 1) == 0)" in method
    assert "*((unsigned char *)&registers.eax + 1));" in method


def test_common_crtc_mode_fields_are_truncated_to_reference_bytes():
    source = (LKS / "ATI_BIOS.m").read_text(encoding="utf-8")
    method = source.split("- (int)loadCRTC_comm:", 1)[1].split("\n- (", 1)[0]
    assert "*((unsigned char *)&registers.ecx) = (unsigned char)(colorMode | mode);" in method
    assert "*((unsigned char *)&registers.ecx + 1) = (unsigned char)resolution;" in method
    assert "registers.ecx = (unsigned int)(colorMode | mode |" not in method
    fixture = (LKS / "tests/test_bios_segments.m").read_text(encoding="utf-8")
    assert "loadCRTC_comm:0x120003 gamma:1 pitchSize:1 resolution:0x81" in fixture
    assert "ATI_mockLastBIOSRegisters()->ecx == 0x8153U" in fixture


def test_service_tests_cover_scan_boundaries_register_packing_and_statuses():
    source = (LKS / "tests/test_bios_segments.m").read_text(encoding="utf-8")
    for token in (
        "testROMPresenceAndInitScan", "0xef000", "segmentAddress == 0xf0000",
        "testBIOSServicePackingAndBounds", "apertureAdrs:0x12345",
        "setDPMSMode:5", "setAPMState:4", "testBIOSQueryOutputPacking",
        "address == 0x5000", "query == 0xfeedbeef",
    ):
        assert token in source


def test_rom_pointer_translation_is_test_only():
    source = (LKS / "ATI_BIOS.m").read_text(encoding="utf-8")
    assert "#if defined(ATI_BIOS_TEST)" in source
    assert "#define ATI_BIOS_ROM_ADDRESS(address) ATI_mockROMAddress(address)" in source
    assert "#define ATI_BIOS_ROM_ADDRESS(address) ((const unsigned char *)(address))" in source
    makefile = (LKS / "tests/Makefile").read_text(encoding="utf-8")
    assert "-DATI_BIOS_TEST" in makefile
