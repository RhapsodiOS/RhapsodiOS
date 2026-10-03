import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[6]
sys.path.insert(0, str(REPO_ROOT / "src/drivers-i386/video/drvATIMach64/reconstruction"))

import verify_evidence


def inventory():
    records = [
        {"address": 0, "name": "-[ATI initFromDeviceDescription:]", "kind": "handwritten"},
        {"address": 0x26E0, "name": "__bios16", "kind": "handwritten"},
        {"address": 0x27B8, "name": "__ATIbios32", "kind": "handwritten"},
        {"address": 0x19EC, "name": "+[ATIMach64DisplayDriverKernelServerInstance kernelServerInstance]", "kind": "generated"},
        {"address": 0x19F8, "name": "+[ATIMach64DisplayDriverVersion driverKitVersionForATIMach64DisplayDriver]", "kind": "generated"},
    ]
    records.extend(
        {"address": 0x3000 + index * 16, "name": f"handwritten_{index}", "kind": "handwritten"}
        for index in range(49)
    )
    return records


def test_zero_initializer_required():
    records = inventory()
    records = [item for item in records if item["address"] != 0]
    with pytest.raises(verify_evidence.EvidenceError, match="initializer at address zero"):
        verify_evidence.validate_inventory(records)


def test_both_assembly_entries_required():
    records = [item for item in inventory() if item["address"] != 0x26E0]
    with pytest.raises(verify_evidence.EvidenceError, match="assembly entries"):
        verify_evidence.validate_inventory(records)


def test_wrong_input_hash_rejected():
    with pytest.raises(verify_evidence.EvidenceError, match="reference identity"):
        verify_evidence.validate_reference_identity(
            {"sha256": "0" * 64, "size": 62632},
            "AA9884B8F9F68DB733237241D88FCC1FF252A59E9B0EA1CD029695F37465EA3C",
            62632,
        )


def test_duplicate_address_rejected():
    records = inventory()
    records[-1]["address"] = records[1]["address"]
    with pytest.raises(verify_evidence.EvidenceError, match="duplicate routine address"):
        verify_evidence.validate_inventory(records)


def test_source_line_out_of_bounds_rejected(tmp_path):
    source = tmp_path / "ATI.m"
    source.write_text("line one\nline two\n", encoding="utf-8")
    with pytest.raises(verify_evidence.EvidenceError, match="source line"):
        verify_evidence.validate_source_location("ATI.m", 3, tmp_path)


def test_generated_exception_identity_required():
    records = inventory()
    next(item for item in records if item["address"] == 0x19EC)["name"] = "-[ATI fakeGeneratedMethod]"
    with pytest.raises(verify_evidence.EvidenceError, match="generated exceptions"):
        verify_evidence.validate_inventory(records)


def test_ida_corrected_assembly_ranges_are_exact():
    assert verify_evidence.corrected_assembly_ranges() == [
        (0x26E0, 0x2755, "__bios16"),
        (0x27B8, 0x2883, "__ATIbios32"),
    ]
