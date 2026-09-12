"""drvDPT2000 binrecon profile is reference-only i386."""
import json
from pathlib import Path

import pytest

from binrecon.profile import load_profile

PROFILE = Path("tools/binrecon/profiles/dpt2000.json")
REF = Path(
    r"C:\Users\raynorpat\Downloads\test\Drivers\i386\DPTSCSIDriver.config\DPTSCSIDriver_reloc"
)
REFSHA = "5AE7A361F645EC693444A8AFC829DB477F34DE2576AFC0EB2A0D4128D3BD68A6"


def test_dpt2000_profile_document_has_no_rebuilt_key():
    document = json.loads(PROFILE.read_text(encoding="utf-8"))
    assert "rebuilt" not in document
    assert document["schema_version"] == "profile-v1"
    assert document["architecture"] == "i386"
    assert document["endianness"] == "little"
    assert document["output_dir"] == "../out/dpt2000"
    assert document["reference"]["path"] == "${BINRECON_REFERENCE}"
    assert document["comparison"]["acceptance"] == "normalized-functions"


def test_dpt2000_profile_loads_reference_only(monkeypatch):
    if not REF.is_file():
        pytest.skip("DPTSCSIDriver_reloc not on this host")
    monkeypatch.setenv("BINRECON_REFERENCE", str(REF))
    profile = load_profile(PROFILE, {"BINRECON_REFERENCE": str(REF)})
    assert profile.rebuilt is None
    assert profile.architecture == "i386"
    assert profile.reference_identity.sha256 == REFSHA
    assert profile.reference_identity.size == 53952
    assert profile.output_dir.name == "dpt2000"
