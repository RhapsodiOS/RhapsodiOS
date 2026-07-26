import hashlib
import json

from macho_fixture import build_macho_fixture
from seed_ledger import main, seed_entries


SOURCE_MAP = {
    "schema_version": "source-map-v1",
    "reference_sha256": "0" * 64,
    "mapped": [
        {"address": 16, "size": 20, "reference_names": ["+[C m]"],
         "source_path": "src/a.m", "source_line": 7},
    ],
    "unmapped": [
        {"address": 36, "size": 40, "reference_names": ["_absent"]},
    ],
    "duplicate_candidates": [],
    "boundary_disputed": [],
}


def test_seeds_one_entry_per_accounted_function():
    entries = seed_entries(SOURCE_MAP)

    assert [entry["address"] for entry in entries] == [16, 36]
    assert entries[0]["source_path"] == "src/a.m"
    assert entries[0]["source_line"] == 7
    assert entries[1]["source_path"] is None
    assert entries[1]["source_line"] is None
    assert {entry["status"] for entry in entries} == {"unexamined"}
    assert entries[0]["names"] == ["+[C m]"]


def test_entries_are_sorted_by_address():
    unsorted_map = dict(SOURCE_MAP, mapped=[
        {"address": 500, "size": 4, "reference_names": ["_late"],
         "source_path": "src/a.m", "source_line": 1},
        {"address": 8, "size": 4, "reference_names": ["_early"],
         "source_path": "src/a.m", "source_line": 2},
    ], unmapped=[])

    assert [entry["address"] for entry in seed_entries(unsorted_map)] == [8, 500]


def test_every_entry_satisfies_the_ledger_schema_fields():
    required = {"address", "size", "names", "source_path", "source_line", "status",
                "analyzer_agreement", "artifacts", "reason", "reviewer"}

    for entry in seed_entries(SOURCE_MAP):
        assert set(entry) == required


def test_cli_writes_a_valid_ledger(tmp_path):
    binary = tmp_path / "reference"
    binary.write_bytes(build_macho_fixture(architecture="ppc", relocations=b""))
    digest = hashlib.sha256(binary.read_bytes()).hexdigest().upper()
    map_path = tmp_path / "source-map.json"
    map_path.write_text(json.dumps(dict(SOURCE_MAP, reference_sha256=digest)))
    output = tmp_path / "ledger.json"

    assert main([str(map_path), str(binary), str(output)]) == 0

    document = json.loads(output.read_text())
    assert document["schema_version"] == "ledger-v1"
    assert document["reference_sha256"] == digest
    assert document["rebuilt_sha256"] is None
    assert len(document["entries"]) == 2


def test_cli_rejects_a_map_for_a_different_binary(tmp_path):
    binary = tmp_path / "reference"
    binary.write_bytes(build_macho_fixture(architecture="ppc", relocations=b""))
    map_path = tmp_path / "source-map.json"
    map_path.write_text(json.dumps(SOURCE_MAP))

    assert main([str(map_path), str(binary), str(tmp_path / "out.json")]) == 1


def test_cli_reports_usage_error(tmp_path):
    assert main(["only-one-argument"]) == 2


def test_cli_fails_cleanly_when_boundary_disputed_overlaps_mapped(tmp_path):
    binary = tmp_path / "reference"
    binary.write_bytes(build_macho_fixture(architecture="ppc", relocations=b""))
    digest = hashlib.sha256(binary.read_bytes()).hexdigest().upper()
    map_path = tmp_path / "source-map.json"
    # Mapped entry at 16..35, boundary_disputed entry at 20..27 (overlaps)
    overlapping_map = {
        "schema_version": "source-map-v1",
        "reference_sha256": digest,
        "mapped": [
            {"address": 16, "size": 20, "reference_names": ["+[C m]"],
             "source_path": "src/a.m", "source_line": 7},
        ],
        "unmapped": [],
        "duplicate_candidates": [],
        "boundary_disputed": [
            {"address": 20, "size": 8, "reference_names": ["_overlap"]},
        ],
    }
    map_path.write_text(json.dumps(overlapping_map))
    output = tmp_path / "ledger.json"

    # Should return 1 instead of raising LedgerError
    assert main([str(map_path), str(binary), str(output)]) == 1
