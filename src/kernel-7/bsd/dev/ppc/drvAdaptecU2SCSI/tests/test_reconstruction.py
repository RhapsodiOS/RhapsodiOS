"""Reference inventory checks; reconstruction acceptance is added by stage."""

import copy
import importlib.util
import json
import os
from pathlib import Path

import pytest


TESTS = Path(__file__).resolve().parent
REPO = TESTS.parents[6]
OUT = REPO / "tools/binrecon/out/adaptecu2scsi-ppc"
BINARY = Path(os.environ.get(
    "BINRECON_REFERENCE", "C:/Users/raynorpat/Downloads/test/MOSXS12v3/mach_kernel"
))
ANALYSIS = OUT / "baseline/published/analysis-reference-ida.json"
OWNER_COUNTS = {
    "AdaptecU2CHIMSCB.c": 67, "AdaptecU2CHIMConfig.c": 20,
    "AdaptecU2CHIMRecovery.c": 28, "AdaptecU2CHIMNegotiation.c": 63,
    "AdaptecU2CHIMHardware.c": 61, "AdaptecU2CHIMHIM.c": 31,
    "AdaptecU2CHIMResource.c": 47, "AdaptecU2CHIMTransport.c": 19,
    "AdaptecU2CHIMOSD.c": 14, "AdaptecU2CHIMAPI.c": 42,
}


def load_script(name):
    path = TESTS / (name + ".py")
    assert path.is_file(), f"missing inventory deliverable: {path}"
    spec = importlib.util.spec_from_file_location("au2_" + name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def reference(tmp_path):
    extractor = load_script("reference")
    result = extractor.extract_reference(BINARY, ANALYSIS, tmp_path)
    return result, tmp_path


def test_inventory_reference_identity_and_partition(reference):
    document, output = reference
    identity = document["identity"]
    assert identity["sha256"] == "D01D748C10117FBFCEB25F99D88A63895C3BAC6C09A5110AD358E583316494BD"
    assert identity["size"] == 2983828
    assert identity["architecture"] == "ppc"
    assert identity["endianness"] == "big"
    assert document["ranges"] == [[0x18770c, 0x18b754], [0x18b754, 0x1a8adc]]
    functions = document["functions"]
    assert len(functions) == 476
    assert len({f["address"] for f in functions}) == 476
    osm = [f for f in functions if f["address"] < 0x18b754]
    chim = [f for f in functions if f["address"] >= 0x18b754]
    assert (len(osm), sum(f["size"] for f in osm)) == (84, 16456)
    assert (len(chim), sum(f["size"] for f in chim)) == (392, 119688)
    assert len(document["methods"]) == 25
    assert sum("(" in m["name"] for m in document["methods"]) == 4
    addresses = []
    for owner, count in OWNER_COUNTS.items():
        assert len(document["owners"][owner]) == count
        addresses.extend(document["owners"][owner])
    assert len(set(addresses)) == len(addresses) == 392
    assert set(addresses) == {f["address"] for f in chim}
    assert len(document["unnamed_helpers"]) == 7
    assert 0x18b2a8 in document["unnamed_helpers"]
    assert document["boundary_disputes"] == []
    load_script("verify").audit("inventory", output, REPO, None, None, None)


def test_inventory_changed_reference_and_omitted_helper_fail(reference):
    document, output = reference
    verifier = load_script("verify")
    changed = copy.deepcopy(document)
    changed["identity"]["sha256"] = "0" * 64
    (output / "reference.json").write_text(json.dumps(changed), encoding="utf-8")
    with pytest.raises(ValueError, match="identity"):
        verifier.audit("inventory", output, REPO, None, None, None)
    omitted = copy.deepcopy(document)
    omitted["functions"] = [f for f in omitted["functions"] if f["address"] != 0x18b2a8]
    (output / "reference.json").write_text(json.dumps(omitted), encoding="utf-8")
    with pytest.raises(ValueError, match="18b2a8"):
        verifier.audit("inventory", output, REPO, None, None, None)
