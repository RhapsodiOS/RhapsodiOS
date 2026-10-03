from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LKS = ROOT.parent / "ATIMach64DisplayDriver.drvproj/ATIMach64DisplayDriver.lksproj"


def test_init_retains_failure_cleanup_and_configuration_order():
    source = (LKS / "ATIMach64DisplayDriver.m").read_text(encoding="utf-8")
    init = source.split("- initFromDeviceDescription:", 1)[1].split("- free", 1)[0]
    assert init.index("[super initFromDeviceDescription:") < init.index("ATIPresent:")
    assert init.index("ATIPresent:") < init.index("[[ATI_BIOS alloc] init]")
    assert init.index("[self getQueryData]") < init.index("[self updateModeList]")
    assert init.index('valueForStringKey:"Display Mode"') < init.index("[self parseModeString:value]")
    assert "return [super free];" in init
    assert "return [self free];" in init
    assert 'valueForStringKey:"Frame Buffer Mapping"' in init
    assert 'valueForStringKey:"RAMDAC Style"' in init
    assert 'valueForStringKey:"Bus Type"' in init


def test_mapping_preference_fallback_and_aperture_verification_are_explicit():
    source = (LKS / "ATIMach64DisplayDriver.m").read_text(encoding="utf-8")
    init = source.split("- initFromDeviceDescription:", 1)[1].split("- free", 1)[0]
    assert 'strcmp(value, "BIOS") == 0' in init
    assert 'strcmp(value, "Table") == 0' in init
    assert 'strcmp(value, "Sparse") == 0' in init
    assert 'strcmp(value, "Dense") == 0' in init
    assert "0x08000000 - vramBytes" in init
    assert "0x07800000" in init
    assert init.index("changeTableMapping:candidateAddress") < init.index("changeHardwareMapping:candidateTableAddress")
    assert "mapFrameBufferAtPhysicalAddress:candidateAddress" in init
    assert "[self verifyMemoryMap]" in init


def test_lifecycle_mode_calls_and_cleanup_match_recovered_state_paths():
    source = (LKS / "ATIMach64DisplayDriver.m").read_text(encoding="utf-8")
    free = source.split("- free", 1)[1].split("- (void)enterLinearMode", 1)[0]
    enter = source.split("- (void)enterLinearMode", 1)[1].split("- (void)revertToVGAMode", 1)[0]
    revert = source.split("- (void)revertToVGAMode", 1)[1].split("- (unsigned int)displayModeCount", 1)[0]
    assert "IOFree(queryData, queryDataSize)" in free
    assert "IOFree(redTransferTable, 3 * transferTableCount)" in free
    assert "loadCRTCSetMode:colorDepth" in enter
    assert "memset(vram, 0, vramBytes);" in enter
    assert "currentState = 1;" in enter and "[self setGammaTable];" in enter
    assert "setVGAMode:1 gamma:0" in revert
    assert "currentState = 2;" in revert


def test_pending_mode_keeps_upper_bound_and_reference_delegation():
    source = (LKS / "ATIMach64DisplayDriver.m").read_text(encoding="utf-8")
    pending = source.split("- (char)setPendingDisplayMode:", 1)[1].split("@end", 1)[0]
    assert "AtiModeListCount <= mode" in pending
    assert "[self isModeValid:mode] == 0" in pending
    assert "modeNumber = mode;" in pending
    assert "return [super setPendingDisplayMode:mode];" in pending
    assert "mode < 0" not in pending
