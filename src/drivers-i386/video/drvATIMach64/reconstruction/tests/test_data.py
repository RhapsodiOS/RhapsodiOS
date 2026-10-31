import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT.parents[4] / "tools/binrecon/out/atimach64/evidence/reference-data.json"
LKS = ROOT.parent / "ATIMach64DisplayDriver.drvproj/ATIMach64DisplayDriver.lksproj"


def test_reference_fixture_and_source_cover_every_mode_and_timing():
    fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))
    source = (LKS / "ATIData.c").read_text(encoding="utf-8")
    assert fixture["reference_sha256"] == "AA9884B8F9F68DB733237241D88FCC1FF252A59E9B0EA1CD029695F37465EA3C"
    assert len(fixture["modes"]) == 54
    assert len(fixture["crt_hex"]) == 15
    assert len(re.findall(r"^\s*ATI_MODE\(", source, re.M)) == 54
    assert len(re.findall(r"^ATI_CRTCRecord crt_", source, re.M)) == 15

    crt_names = re.findall(r"ATI_CRTCRecord (crt_[A-Za-z0-9_]+) = \{\{ ([^}]+) \}\};", source)
    assert len(crt_names) == len(fixture["crt_hex"])
    for (_, hex_bytes), expected in zip(crt_names, fixture["crt_hex"]):
        actual = bytes(int(value, 16) for value in re.findall(r"0x([0-9a-fA-F]{2})", hex_bytes)).hex()
        assert actual == expected.lower()

    gamma16 = re.search(r"gamma16\[16\] = \{([^}]+)\}", source, re.S).group(1)
    gamma8 = re.search(r"gamma8\[256\] = \{([^}]+)\}", source, re.S).group(1)
    assert bytes(int(value, 16) for value in re.findall(r"0x([0-9a-fA-F]{2})", gamma16)).hex() == fixture["gamma16_hex"].lower()
    assert bytes(int(value, 16) for value in re.findall(r"0x([0-9a-fA-F]{2})", gamma8)).hex() == fixture["gamma8_hex"].lower()

    modes = re.findall(r'ATI_MODE\((\d+), (\d+), (\d+), (\d+), (\d+), "([^"]+)", (crt_[A-Za-z0-9_]+)\)', source)
    assert len(modes) == len(fixture["modes"])
    ordered_crt_names = [name for name, _ in crt_names]
    for actual, row in zip(modes, fixture["modes"]):
        _, width, height, _, _, refresh, bpp, color_space, encoding, _, crtc, *_ = row
        assert actual == (str(width), str(height), str(refresh), str(bpp), str(color_space), encoding,
                          ordered_crt_names[(crtc - fixture["crt_address"]) // fixture["crt_record_size"]])

    for table_name, expected_rows in fixture["value_tables"].items():
        declaration = re.search(rf"IONamedValue {table_name}\[\] = \{{(.*?)\}};", source, re.S)
        assert declaration
        actual_rows = []
        for value, name, is_null in re.findall(
            r'\{\s*(\d+)\s*,\s*(?:"([^"]*)"|(0))\s*\}', declaration.group(1)
        ):
            actual_rows.append([int(value), None if is_null else name])
        assert actual_rows == expected_rows

    assert "int Refresh_60_72_75[4] = { 60, 72, 75, 0 };" in source
    assert "int Refresh_60_70_75[4] = { 60, 70, 75, 0 };" in source
    for status, name in enumerate(("AB_Success", "AB_NotInitialized", "AB_BIOS_Error", "AB_Invalid")):
        assert f'{{ {status}, "{name}" }}' in source
    assert "{ 18, Refresh_60_72_75 }" in source
    assert "{ 106, Refresh_60_72_75 }" in source
    assert "{ 85, Refresh_60_70_75 }" in source
    assert "{ 131, Refresh_60_70_75 }" in source
    assert "{ 132, Refresh_60_72_75 }" in source


def test_gamma_and_value_name_tables_are_present():
    source = (LKS / "ATIData.c").read_text(encoding="utf-8")
    for name in (
        "gamma16", "gamma8", "bitsPerPixelValues", "colorConfigValues",
        "ATI_modeToRefreshRatesTable", "ABReturnValues", "ATI_AsicTypeValues",
        "ATI_AsicSubTypeValues", "ATI_memSizeValues", "ATI_dacTypeValues",
        "ATI_busTypeValues", "modeValidArray",
    ):
        assert name in source
    assert len(re.findall(r"^\s*ATI_MODE\(", source, re.M)) == 54


def test_memory_size_conversion_keeps_the_observed_default_and_supported_codes():
    source = (LKS / "ATIData.c").read_text(encoding="utf-8")
    body = re.search(r"memSizeToBytes\([^)]*\)\s*\{(?P<body>.*?)\n\}", source, re.S)
    assert body
    for literal in ("0x80000", "0x100000", "0x200000", "0x400000", "0x600000"):
        assert literal in body.group("body")
    assert "default:" in body.group("body")


def test_color_depth_conversion_uses_zero_initialized_result():
    source = (LKS / "ATIData.c").read_text(encoding="utf-8")
    body = re.search(r"colorDepthToColorSpace\([^)]*\)\s*\{(?P<body>.*?)\n\}", source, re.S)
    assert body
    assert "int colorSpace = 0;" in body.group("body")
    assert "colorSpace = 1;" in body.group("body")
    assert "colorSpace = 2;" in body.group("body")
    assert "colorSpace = 3;" in body.group("body")
    assert "return colorSpace;" in body.group("body")


def test_display_info_color_space_uses_shared_zero_initialized_result():
    source = (LKS / "ATIData.c").read_text(encoding="utf-8")
    body = re.search(r"displayInfoToColorSpace\([^)]*\)\s*\{(?P<body>.*?)\n\}", source, re.S)
    assert body
    assert "int colorSpace = 0;" in body.group("body")
    assert "colorSpace = 2;" in body.group("body")
    assert "colorSpace = 3;" in body.group("body")
    assert "return colorSpace;" in body.group("body")
    assert "switch (info->bitsPerPixel)" in body.group("body")
    assert body.group("body").index("case IO_8BitsPerPixel:") < body.group("body").index("case IO_15BitsPerPixel:")
    assert body.group("body").index("case IO_15BitsPerPixel:") < body.group("body").index("case IO_24BitsPerPixel:")
    assert "colorSpace = 1;" in body.group("body")
    assert "if (info->colorSpace == IO_OneIsWhiteColorSpace)" in body.group("body")


def test_display_info_color_depth_preserves_shared_zero_initialized_result():
    source = (LKS / "ATIData.c").read_text(encoding="utf-8")
    body = re.search(r"displayInfoToColorDepth\([^)]*\)\s*\{(?P<body>.*?)\n\}", source, re.S)
    assert body
    assert "int colorDepth = 0;" in body.group("body")
    assert "colorDepth = 2;" in body.group("body")
    assert "colorDepth = 3;" in body.group("body")
    assert "colorDepth = 6;" in body.group("body")
    assert "return colorDepth;" in body.group("body")
    assert "switch (info->bitsPerPixel)" in body.group("body")
    assert body.group("body").index("case IO_8BitsPerPixel:") < body.group("body").index("case IO_15BitsPerPixel:")
    assert body.group("body").index("case IO_15BitsPerPixel:") < body.group("body").index("case IO_24BitsPerPixel:")
