from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LKS = ROOT.parent / "ATIMach64DisplayDriver.drvproj/ATIMach64DisplayDriver.lksproj"


def test_ati_class_and_ivar_sequence_match_reference_metadata():
    header = (LKS / "ATIPrivate.h").read_text(encoding="utf-8")
    assert "@interface ATI : IOFrameBufferDisplay" in header
    names = [
        "redTransferTable", "greenTransferTable", "blueTransferTable",
        "transferTableCount", "brightnessLevel", "modeNumber", "vram",
        "vramBytes", "currentState", "isPCI", "atiBios", "queryData",
        "queryDataSize", "supportsGamma", "supportsGrey256", "colorConfig",
        "fbMapStyle", "ramdacStyle",
    ]
    positions = [header.index(name) for name in names]
    assert positions == sorted(positions)
    assert "ATIMach64DisplayDriver" not in header


def test_bios_register_and_private_layouts_are_declared():
    types = (LKS / "ATIBIOSTypes.h").read_text(encoding="utf-8")
    for offset in (4, 8, 12, 16, 20, 24, 28, 32, 34, 36, 40, 44):
        assert f"ATIBIOS_OFFSET_{offset}" in types
    assert "ATIBIOSRegisterBufferSize = 48" in types
    assert "ATIBIOSPrivateSize = 36" in types


def test_bios_object_uses_reference_ivar_names():
    header = (LKS / "ATI_BIOS.h").read_text(encoding="utf-8")
    assert "@interface ATI_BIOS : Object" in header
    assert "initialized" in header and "segmentBase" in header and "_priv" in header


def test_iodisplayinfo_reference_size_is_pinned_for_i386():
    header = (LKS / "ATIData.h").read_text(encoding="utf-8")
    assert "ATI_STATIC_ASSERT(sizeof(IODisplayInfo) == 136" in header
