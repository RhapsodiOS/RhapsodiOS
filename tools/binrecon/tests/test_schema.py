from copy import deepcopy
from pathlib import Path

import jsonschema
import pytest

from binrecon.schema import (
    SemanticValidationError,
    load_json,
    validate_analysis_semantics,
    validate_document,
)


FIXTURE = Path(__file__).parent / "fixtures" / "minimal-analysis.json"


def test_minimal_analysis_passes_schema_and_semantic_validation():
    document = load_json(FIXTURE)

    validate_document("analysis-v1", document)
    validate_analysis_semantics(document)


def test_analysis_requires_input_sha256():
    document = load_json(FIXTURE)
    del document["input"]["sha256"]

    with pytest.raises(jsonschema.ValidationError):
        validate_document("analysis-v1", document)


def test_call_target_accepts_any_integer_or_null():
    document = load_json(FIXTURE)
    document["functions"][0]["calls"].append(
        {"address": 4096, "target": -1, "name": None}
    )

    validate_document("analysis-v1", document)


def test_analysis_rejects_duplicate_function_start_addresses():
    document = load_json(FIXTURE)
    document["functions"].append(deepcopy(document["functions"][0]))

    with pytest.raises(SemanticValidationError, match="duplicate function.*4096"):
        validate_analysis_semantics(document)


def test_ledger_rejects_unknown_status():
    document = {
        "schema_version": "ledger-v1",
        "reference_sha256": "0" * 64,
        "rebuilt_sha256": None,
        "entries": [
            {
                "address": 4096,
                "size": 4,
                "names": ["entry"],
                "source_path": None,
                "source_line": None,
                "status": "guessed",
                "analyzer_agreement": 1.0,
                "artifacts": [],
                "reason": None,
                "reviewer": None,
            }
        ],
    }

    with pytest.raises(jsonschema.ValidationError):
        validate_document("ledger-v1", document)


def test_profile_accepts_relative_paths():
    document = minimal_profile()

    validate_document("profile-v1", document)


@pytest.mark.parametrize("nested", [False, True])
def test_profile_rejects_unknown_keys(nested):
    document = minimal_profile()
    if nested:
        document["reference"]["surprise"] = True
    else:
        document["surprise"] = True

    with pytest.raises(jsonschema.ValidationError):
        validate_document("profile-v1", document)


def test_analysis_semantics_rejects_overlapping_nonempty_sections():
    document = load_json(FIXTURE)
    document["sections"].append(
        {
            "name": ".overlap",
            "address": 4098,
            "offset": 2,
            "size": 2,
            "permissions": "r",
            "sha256": "0" * 64,
        }
    )

    with pytest.raises(SemanticValidationError, match="section.*4098.*overlaps"):
        validate_analysis_semantics(document)


def test_analysis_semantics_allows_zero_size_overlapping_section():
    document = load_json(FIXTURE)
    document["sections"].append(
        {
            "name": ".marker",
            "address": 4098,
            "offset": 2,
            "size": 0,
            "permissions": "",
            "sha256": "0" * 64,
        }
    )

    validate_analysis_semantics(document)


def test_analysis_semantics_rejects_block_at_function_end():
    document = load_json(FIXTURE)
    document["functions"][0]["blocks"] = [
        {"address": 4100, "size": 0, "successors": []}
    ]
    document["functions"][0]["instructions"] = []

    with pytest.raises(SemanticValidationError, match="block.*4100.*outside function.*4096"):
        validate_analysis_semantics(document)


def test_analysis_semantics_rejects_duplicate_block_starts():
    document = load_json(FIXTURE)
    block = document["functions"][0]["blocks"][0]
    document["functions"][0]["blocks"].append(deepcopy(block))

    with pytest.raises(SemanticValidationError, match="duplicate block.*4096"):
        validate_analysis_semantics(document)


def test_analysis_semantics_rejects_instruction_outside_blocks():
    document = load_json(FIXTURE)
    document["functions"][0]["instructions"][0]["address"] = 4100

    with pytest.raises(SemanticValidationError, match="instruction.*4100.*outside every block"):
        validate_analysis_semantics(document)


@pytest.mark.parametrize(
    ("entity", "bad_hash"),
    [("input", "0" * 63), ("section", "g" * 64)],
)
def test_analysis_semantics_rejects_invalid_sha256(entity, bad_hash):
    document = load_json(FIXTURE)
    if entity == "input":
        document["input"]["sha256"] = bad_hash
    else:
        document["sections"][0]["sha256"] = bad_hash

    with pytest.raises(SemanticValidationError, match=f"{entity}.*sha256"):
        validate_analysis_semantics(document)


def minimal_profile():
    return {
        "schema_version": "profile-v1",
        "name": "minimal",
        "architecture": "powerpc",
        "reference": {"path": "artifacts/reference.bin"},
        "rebuilt": {"path": "build/rebuilt.bin"},
        "analyzers": {
            "ida": {"enabled": False},
            "ghidra": {"enabled": True, "timeout_seconds": 60},
            "angr": {"enabled": False},
        },
        "comparison": {
            "acceptance": "normalized-functions",
            "ignore_metadata": [],
            "entry_points": ["entry"],
        },
        "output_dir": "out/binrecon",
    }
