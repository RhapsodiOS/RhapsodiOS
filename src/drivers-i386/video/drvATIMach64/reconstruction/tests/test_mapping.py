from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LKS = ROOT.parent / "ATIMach64DisplayDriver.drvproj/ATIMach64DisplayDriver.lksproj"


def _method(source: str, signature: str, following: str) -> str:
    return source.split(signature, 1)[1].split(following, 1)[0]


def test_mode_selection_and_validation_keep_reference_decisions():
    source = (LKS / "ATIPrivate.m").read_text(encoding="utf-8")
    parse = _method(source, "- (int)parseModeString:", "- (void)updateModeList")
    valid = _method(source, "- (unsigned int)isModeValid:", "- (char)verifyMemoryMap")
    assert "selectMode:AtiModeList count:AtiModeListCount" in parse
    assert "valid:(const BOOL *)modeValidArray" in parse
    assert "modeNumber = selected;" in parse
    assert "if (AtiModeListCount <= modeIndex)" in valid
    assert "IO_15BitsPerPixel" in valid and "(queryData[19] & 2) == 0" in valid
    assert "IO_24BitsPerPixel && colorConfig == 5" in valid
    assert "required > memSizeToBytes(queryData[11])" in valid
    assert "modeIndex < 0" not in valid


def test_mode_list_refreshes_pixel_layout_and_derived_fields():
    source = (LKS / "ATIPrivate.m").read_text(encoding="utf-8")
    update = _method(source, "- (void)updateModeList", "- (unsigned int)isModeValid:")
    assert "modeValidArray = 0;" in update
    assert "queryData[19] & 0x20" in update
    assert "BBBBBBBBGGGGGGGGRRRRRRRR--------" in update
    assert "--------RRRRRRRRGGGGGGGGBBBBBBBB" in update
    assert "--------BBBBBBBBGGGGGGGGRRRRRRRR" in update
    assert "mode->totalWidth = mode->width;" in update
    assert "mode->rowBytes = mode->totalWidth * (strlen(mode->pixelEncoding) >> 3);" in update
    assert "mode->frameBuffer = vram;" in update
    assert "mode->modeUnavailableFlag = [self isModeValid:(int)index];" in update
    assert "mode->memorySize = mode->height * mode->rowBytes;" in update


def test_query_replacement_and_hardware_mapping_preserve_ownership_order():
    source = (LKS / "ATIPrivate.m").read_text(encoding="utf-8")
    query = _method(source, "- (int)getQueryData", "- (int)parseModeString:")
    mapping = _method(source, "- (int)changeHardwareMapping:", "- (int)changeTableMapping:")
    assert query.index("IOFree(queryData, queryDataSize)") < query.index("[atiBios querySize:0")
    assert query.index("[atiBios deviceQuery:0") < query.index("queryDataSize = *queryBuffer;")
    assert query.index("bcopy(queryBuffer, queryData, queryDataSize)") < query.index("IOFree(queryBuffer, querySize)")
    assert mapping.index("setApertureEnable:1") < mapping.index("setPCIConfigData:")
    assert mapping.index("getPCIConfigData:") < mapping.index("[self getQueryData]")
    assert "*((unsigned short *)queryData + 8)" in mapping


def test_table_mapping_keeps_three_ranges_and_rolls_back_first_address():
    source = (LKS / "ATIPrivate.m").read_text(encoding="utf-8")
    mapping = source.split("- (int)changeTableMapping:", 1)[1]
    assert "[description numMemoryRanges] != 3" in mapping
    assert "return -701;" in mapping
    assert "replacement[index] = ranges[index];" in mapping
    assert "replacement[0].start = address;" in mapping
    first_set = mapping.index("[description setMemoryRangeList:replacement num:0];")
    replace = mapping.index("result = [description setMemoryRangeList:replacement num:3];")
    rollback = mapping.index("replacement[0].start = oldAddress;")
    restore = mapping.index("restoreResult = [description setMemoryRangeList:replacement num:3];")
    assert first_set < replace < rollback < restore


def test_vram_probe_preserves_failure_without_restore():
    source = (LKS / "ATIPrivate.m").read_text(encoding="utf-8")
    probe = source.split("- (char)verifyMemoryMap", 1)[1].split("- (int)changeHardwareMapping:", 1)[0]
    assert "bcopy(vram, saved, sizeof(saved));" in probe
    assert "((unsigned int *)vram)[index] = index;" in probe
    failure = probe.index("return 0;")
    restore = probe.index("bcopy(saved, vram, sizeof(saved));")
    assert failure < restore
