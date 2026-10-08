from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LKS = ROOT.parent / "ATIMach64DisplayDriver.drvproj/ATIMach64DisplayDriver.lksproj"


def test_gamma_and_revision_paths_use_exact_ports_and_synchronizing_io_primitive():
    source = (LKS / "ProgramDAC.m").read_text(encoding="utf-8")
    assert "ATI_INB(0x62ec)" in source
    assert "ATI_OUTB(0x62ec, control | 3);" in source
    assert "if (ATI_INB(0x5eef) == 0xd0)" in source
    assert "return 1;\n    return 0;" in source
    assert "ATI_OUTB(0x5eed" in source
    assert "ATI_OUTB(0x62ec, control & 0xfc);" in source
    ports = (ROOT.parents[3] / "driverkit-3/driverkit/i386/ioPorts.h").read_text(encoding="utf-8")
    assert '"outb %2,%1; lock; incl %0"' in ports
    assert "ATI_DAC_TEST" in source


def test_gamma_table_loops_and_brightness_bounds_keep_reference_behavior():
    source = (LKS / "ProgramDAC.m").read_text(encoding="utf-8")
    gamma = source.split("- (id)setGammaTable", 1)[1].split("- (id)setBrightness:", 1)[0]
    brightness = source.split("- (id)setBrightness:", 1)[1].split("- (id)setTransferTable:", 1)[0]
    assert "256 / transferTableCount" in gamma
    assert "for (index = 0; index <= 0xff; ++index)" in gamma
    assert "for (index = 0; index <= 0x1f; ++index)" in gamma
    assert "for (repeat = 0; repeat <= 7; ++repeat)" in gamma
    assert "if ((unsigned int)level > 0x40)" in brightness
    assert "brightnessLevel = level;" in brightness
    assert "token" not in brightness.split("{", 1)[1]


def test_transfer_table_allocation_slices_formats_and_overrides_are_present():
    source = (LKS / "ProgramDAC.m").read_text(encoding="utf-8")
    transfer = source.split("- (id)setTransferTable:", 1)[1]
    for token in (
        "IOMalloc(3 * count)", "greenTransferTable = (unsigned int *)((char *)redTransferTable + count)",
        "blueTransferTable = (unsigned int *)((char *)greenTransferTable + count)",
        "ramdacStyle == 1", "ramdacStyle == 2", "components[3] >> shift",
        "components[2] >> shift", "components[1] >> shift",
        "((unsigned char *)queryData)[9]", "((unsigned char *)queryData)[12]",
        "redTransferTable = nil;", "[self setGammaTable];",
    ):
        assert token in transfer


def test_dac_fixture_checks_ports_brightness_and_unusual_table_count():
    source = (LKS / "tests/test_dac.m").read_text(encoding="utf-8")
    assert "testGammaValueAndRevisionPortOrder" in source
    assert "testDefaultGammaAndBrightnessBounds" in source
    assert "testTransferTableChannelExtractionAndSparseCount" in source
    assert "ATI_mockPortEventCount() == 771" in source
    makefile = (LKS / "tests/Makefile").read_text(encoding="utf-8")
    assert "check-dac: $(BUILD)/test_dac" in makefile


def test_gamma_value_multiplies_each_channel_by_brightness_in_reference_order():
    source = (LKS / "ProgramDAC.m").read_text(encoding="utf-8")
    body = source.split("unsigned int SetGammaValue", 1)[1].split("@implementation", 1)[0]
    red = "red = ((unsigned int)red * (unsigned int)brightness) >> 6;"
    green = "green = ((unsigned int)green * (unsigned int)brightness) >> 6;"
    blue = "blue = ((unsigned int)blue * (unsigned int)brightness) >> 6;"
    positions = [body.index(expression) for expression in (red, green, blue)]
    assert positions == sorted(positions)


def test_gamma_value_keeps_scaled_channels_in_the_parameter_registers():
    source = (LKS / "ProgramDAC.m").read_text(encoding="utf-8")
    body = source.split("unsigned int SetGammaValue", 1)[1].split("@implementation", 1)[0]
    assert "red = ((unsigned int)red * (unsigned int)brightness) >> 6;" in body
    assert "green = ((unsigned int)green * (unsigned int)brightness) >> 6;" in body
    assert "blue = ((unsigned int)blue * (unsigned int)brightness) >> 6;" in body
    assert "return blue;" in body
