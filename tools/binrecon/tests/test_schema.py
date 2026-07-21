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


def test_call_target_accepts_null():
    document = load_json(FIXTURE)
    document["functions"][0]["calls"].append(
        {"address": 4096, "target": None, "name": None}
    )

    validate_document("analysis-v1", document)


def test_call_target_rejects_negative_address():
    document = load_json(FIXTURE)
    document["functions"][0]["calls"].append(
        {"address": 4096, "target": -1, "name": None}
    )

    with pytest.raises(jsonschema.ValidationError):
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


def test_analysis_rejects_empty_instruction_bytes():
    document = load_json(FIXTURE)
    document["functions"][0]["instructions"][0]["bytes"] = ""

    with pytest.raises(jsonschema.ValidationError):
        validate_document("analysis-v1", document)


def test_analysis_rejects_zero_size_block():
    document = load_json(FIXTURE)
    document["functions"][0]["blocks"][0]["size"] = 0

    with pytest.raises(jsonschema.ValidationError):
        validate_document("analysis-v1", document)


def test_analysis_extensions_accept_namespaced_analyzer_data():
    document = load_json(FIXTURE)
    document["extensions"] = {
        "ida": {"decompiler": "return;"},
        "angr": {"errors": []},
    }

    validate_document("analysis-v1", document)


def test_analysis_extensions_reject_empty_namespace():
    document = load_json(FIXTURE)
    document["extensions"] = {"": {"data": True}}

    with pytest.raises(jsonschema.ValidationError):
        validate_document("analysis-v1", document)


def test_analysis_accepts_stable_core_collections():
    document = load_json(FIXTURE)
    document["references"] = [{"address": 4096, "target": None, "kind": "data"}]
    document["imports"] = [{"name": "puts", "address": None}]
    document["strings"] = [
        {"address": 8192, "value": "hello", "encoding": "utf-8"}
    ]

    validate_document("analysis-v1", document)


def test_profile_accepts_raw_loader_and_symbolic_check_configuration():
    document = minimal_profile()
    document.update(
        {
            "endianness": "big",
            "image_base": 4096,
            "regions": [
                {
                    "name": ".text",
                    "address": 4096,
                    "offset": 0,
                    "size": 4,
                    "permissions": "rx",
                }
            ],
            "aliases": {"_entry": ["entry"]},
            "symbolic_checks": [
                {
                    "name": "entry returns",
                    "function": "entry",
                    "max_active_states": 8,
                    "max_steps": 100,
                    "input_bytes": 4,
                    "registers": {"r3": 1, "analyzer_specific_register": 2},
                    "memory": [{"address": 8192, "bytes": "00ff"}],
                    "hooks": [
                        {
                            "address": 4096,
                            "handler": "return_constant",
                            "returns": 0,
                        }
                    ],
                    "assertions": [
                        {"kind": "return-equals", "value": 0},
                        {
                            "kind": "memory-equals",
                            "address": 8192,
                            "bytes": "00ff",
                        },
                        {"kind": "return-equivalent", "artifact": "reference"},
                    ],
                }
            ],
            "extensions": {"angr": {"solver": "z3"}},
        }
    )

    validate_document("profile-v1", document)


@pytest.mark.parametrize("bad_bytes", ["", "0", "xyz0"])
def test_profile_symbolic_check_rejects_bad_memory_hex(bad_bytes):
    document = symbolic_profile()
    document["symbolic_checks"][0]["memory"] = [
        {"address": 8192, "bytes": bad_bytes}
    ]

    with pytest.raises(jsonschema.ValidationError):
        validate_document("profile-v1", document)


@pytest.mark.parametrize(
    "assertion",
    [
        {"kind": "unknown", "value": 0},
        {"kind": "return-equals", "value": 0, "surprise": True},
    ],
)
def test_profile_symbolic_check_rejects_invalid_assertion(assertion):
    document = symbolic_profile()
    document["symbolic_checks"][0]["assertions"] = [assertion]

    with pytest.raises(jsonschema.ValidationError):
        validate_document("profile-v1", document)


def test_profile_symbolic_check_rejects_integer_hook():
    document = symbolic_profile()
    document["symbolic_checks"][0]["hooks"] = [4096]

    with pytest.raises(jsonschema.ValidationError):
        validate_document("profile-v1", document)


def test_profile_symbolic_check_rejects_empty_register_name():
    document = symbolic_profile()
    document["symbolic_checks"][0]["registers"] = {"": 0}

    with pytest.raises(jsonschema.ValidationError):
        validate_document("profile-v1", document)


@pytest.mark.parametrize("container", ["regions", "symbolic_checks"])
def test_profile_rejects_unknown_raw_configuration_keys(container):
    document = minimal_profile()
    if container == "regions":
        document[container] = [
            {
                "name": ".text",
                "address": 4096,
                "offset": 0,
                "size": 4,
                "permissions": "rx",
                "surprise": True,
            }
        ]
    else:
        document[container] = [
            {
                "name": "entry returns",
                "function": "entry",
                "max_active_states": 8,
                "max_steps": 100,
                "surprise": True,
            }
        ]

    with pytest.raises(jsonschema.ValidationError):
        validate_document("profile-v1", document)


@pytest.mark.parametrize(
    ("schema_name", "document_factory"),
    [
        ("analysis-v1.json", lambda: load_json(FIXTURE)),
        ("profile-v1.json", lambda: minimal_profile()),
        ("ledger-v1.json", lambda: minimal_ledger()),
    ],
)
def test_validate_document_accepts_schema_filename(schema_name, document_factory):
    validate_document(schema_name, document_factory())


@pytest.mark.parametrize("schema_name", ["../analysis-v1.json", "schema/analysis-v1.json"])
def test_validate_document_rejects_schema_paths(schema_name):
    with pytest.raises(ValueError, match="unknown schema name"):
        validate_document(schema_name, load_json(FIXTURE))


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

    validate_document("analysis-v1", document)
    validate_analysis_semantics(document)


def test_analysis_allows_zero_size_function_without_contents():
    document = load_json(FIXTURE)
    function = document["functions"][0]
    function["size"] = 0
    function["blocks"] = []
    function["instructions"] = []

    validate_document("analysis-v1", document)
    validate_analysis_semantics(document)


def test_analysis_zero_size_function_rejects_blocks():
    document = load_json(FIXTURE)
    document["functions"][0]["size"] = 0

    with pytest.raises(SemanticValidationError, match="block.*4096.*outside function.*4096"):
        validate_analysis_semantics(document)


def test_analysis_zero_size_function_rejects_instructions():
    document = load_json(FIXTURE)
    function = document["functions"][0]
    function["size"] = 0
    function["blocks"] = []

    with pytest.raises(SemanticValidationError, match="instruction.*4096.*outside every block"):
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


def test_analysis_semantics_rejects_instruction_crossing_block_end():
    document = load_json(FIXTURE)
    instruction = document["functions"][0]["instructions"][0]
    instruction["address"] = 4099
    instruction["bytes"] = "00000000"

    with pytest.raises(SemanticValidationError, match="instruction.*4099.*outside every block"):
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


def minimal_ledger():
    return {
        "schema_version": "ledger-v1",
        "reference_sha256": "0" * 64,
        "rebuilt_sha256": None,
        "entries": [],
    }


def symbolic_profile():
    document = minimal_profile()
    document["symbolic_checks"] = [
        {
            "name": "entry returns",
            "function": "entry",
            "max_active_states": 8,
            "max_steps": 100,
            "registers": {"r3": 0},
            "memory": [{"address": 8192, "bytes": "00"}],
            "hooks": [{"address": 4096, "handler": "return_zero"}],
            "assertions": [{"kind": "return-equals", "value": 0}],
        }
    ]
    return document
