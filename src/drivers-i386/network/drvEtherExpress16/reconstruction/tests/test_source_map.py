import json
from pathlib import Path


ROOT = Path(".")
MAP = ROOT / "src/drivers-i386/network/drvEtherExpress16/reconstruction/source-map.json"


def test_ida_partition_is_completely_mapped_to_source():
    document = json.loads(MAP.read_text(encoding="utf-8"))
    entries = document["mapped"]
    assert document["reference_sha256"] == "2BF1F8563BABD7CDC4C7BA625E9963033A6B56BFE237A43308707944228AACE8"
    assert len(entries) == 68
    assert not document["unmapped"]
    assert not document["duplicate_candidates"]
    assert not document["boundary_disputed"]
    assert len({entry["address"] for entry in entries}) == len(entries)

    for entry in entries:
        source = ROOT / entry["source_path"]
        lines = source.read_text(encoding="utf-8-sig").splitlines()
        assert 1 <= entry["source_line"] <= len(lines)
        assert entry["reference_names"]
