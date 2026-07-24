import json
from copy import deepcopy
from pathlib import Path

import binrecon.schema as schema
import jsonschema
import pytest


validate_document = schema.validate_document
ANALYSIS_FIXTURE = Path(__file__).parent / "fixtures" / "minimal-analysis.json"


def minimal_source_map():
    return {
        "schema_version": "source-map-v1",
        "reference_sha256": "A" * 64,
        "mapped": [
            {
                "address": 16,
                "size": 4,
                "reference_names": ["entry"],
                "source_path": "src/entry.c",
                "source_line": 3,
            }
        ],
        "unmapped": [],
        "duplicate_candidates": [],
        "boundary_disputed": [],
    }


def reference_analysis(functions=None, sha256="A" * 64):
    document = schema.load_json(ANALYSIS_FIXTURE)
    template = document["functions"][0]
    functions = functions or [{"address": 16, "size": 4, "names": ["entry"]}]
    document["input"]["sha256"] = sha256
    document["functions"] = []
    for expected in functions:
        function = deepcopy(template)
        function["address"] = expected["address"]
        function["size"] = expected["size"]
        function["names"] = expected["names"]
        function["blocks"][0]["address"] = expected["address"]
        function["instructions"][0]["address"] = expected["address"]
        document["functions"].append(function)
    return document


def test_source_map_schema_is_registered():
    validate_document("source-map-v1", minimal_source_map())
    validate_document("source-map-v1.json", minimal_source_map())


def test_source_map_semantic_loader_api_is_available():
    assert callable(getattr(schema, "load_source_map", None))
    assert callable(getattr(schema, "validate_source_map_semantics", None))


@pytest.mark.parametrize(
    "mutation",
    [
        lambda document: document.update({"surprise": True}),
        lambda document: document["mapped"][0].update({"surprise": True}),
        lambda document: document.update({"reference_sha256": "a" * 64}),
        lambda document: document["mapped"][0].update({"size": 0}),
        lambda document: document["mapped"][0].update({"reference_names": []}),
    ],
)
def test_source_map_schema_is_closed_and_strict(mutation):
    document = minimal_source_map()
    mutation(document)

    with pytest.raises(jsonschema.ValidationError):
        validate_document("source-map-v1", document)


def test_unmapped_entry_forbids_source_fields():
    document = minimal_source_map()
    document["unmapped"] = [
        {
            "address": 32,
            "size": 4,
            "reference_names": ["unknown"],
            "source_path": "src/unknown.c",
            "source_line": 1,
        }
    ]

    with pytest.raises(jsonschema.ValidationError):
        validate_document("source-map-v1", document)


def test_duplicate_entry_requires_multiple_candidates_and_reasons():
    document = minimal_source_map()
    document["duplicate_candidates"] = [
        {
            "address": 32,
            "size": 4,
            "reference_names": ["duplicate"],
            "candidates": [{"source_path": "src/a.c", "source_line": 1}],
            "reasons": [],
        }
    ]

    with pytest.raises(jsonschema.ValidationError):
        validate_document("source-map-v1", document)


def test_boundary_entry_requires_nonempty_reasons():
    document = minimal_source_map()
    document["boundary_disputed"] = [
        {
            "address": 32,
            "size": 4,
            "reference_names": ["boundary"],
            "reasons": [],
        }
    ]

    with pytest.raises(jsonschema.ValidationError):
        validate_document("source-map-v1", document)


@pytest.mark.parametrize(
    ("field", "values", "message"),
    [
        ("reference_names", ["z", "a"], "reference_names.*sorted"),
        ("reference_names", ["a", "a"], "reference_names.*unique"),
    ],
)
def test_source_map_semantics_requires_sorted_unique_names(field, values, message):
    document = minimal_source_map()
    document["mapped"][0][field] = values

    with pytest.raises(schema.SemanticValidationError, match=message):
        schema.validate_source_map_semantics(document)


def test_source_map_semantics_requires_sorted_unique_reasons():
    document = minimal_source_map()
    document["boundary_disputed"] = [
        {
            "address": 32,
            "size": 4,
            "reference_names": ["boundary"],
            "reasons": ["z reason", "a reason"],
        }
    ]

    with pytest.raises(schema.SemanticValidationError, match="reasons.*sorted"):
        schema.validate_source_map_semantics(document)


def test_source_map_semantics_requires_canonical_entry_order():
    document = minimal_source_map()
    document["mapped"].insert(
        0,
        {
            "address": 32,
            "size": 4,
            "reference_names": ["later"],
            "source_path": "src/later.c",
            "source_line": 1,
        },
    )

    with pytest.raises(schema.SemanticValidationError, match="mapped.*canonical order"):
        schema.validate_source_map_semantics(document)


def test_source_map_semantics_rejects_duplicate_starts_across_categories():
    document = minimal_source_map()
    document["unmapped"] = [
        {"address": 16, "size": 4, "reference_names": ["entry"]}
    ]

    with pytest.raises(schema.SemanticValidationError, match="duplicate function start.*16"):
        schema.validate_source_map_semantics(document)


def test_source_map_semantics_allows_overlap_only_for_boundary_evidence():
    document = minimal_source_map()
    document["boundary_disputed"] = [
        {
            "address": 18,
            "size": 2,
            "reference_names": ["nested"],
            "reasons": ["incompatible boundaries"],
        }
    ]

    with pytest.raises(schema.SemanticValidationError, match="overlap.*boundary_disputed"):
        schema.validate_source_map_semantics(document)

    document["boundary_disputed"].insert(
        0,
        {
            "address": 16,
            "size": 4,
            "reference_names": ["entry"],
            "reasons": ["incompatible boundaries"],
        },
    )
    document["mapped"] = []
    schema.validate_source_map_semantics(document)


def test_source_map_context_checks_partition_identity_and_source_lines(tmp_path):
    source = tmp_path / "src" / "entry.c"
    source.parent.mkdir()
    source.write_text("one\ntwo\nthree\n", encoding="utf-8")
    document = minimal_source_map()
    analysis = reference_analysis()

    schema.validate_source_map_semantics(
        document, reference_analysis=analysis, repo_root=tmp_path
    )

    document["mapped"][0]["source_line"] = 4
    with pytest.raises(schema.SemanticValidationError, match="source_line.*outside"):
        schema.validate_source_map_semantics(
            document, reference_analysis=analysis, repo_root=tmp_path
        )


@pytest.mark.parametrize(
    ("field", "value", "message"),
    [
        ("address", 17, "partition"),
        ("size", 5, "size.*expected 4"),
        ("reference_names", ["other"], "names.*expected"),
    ],
)
def test_source_map_context_requires_exact_reference_function_identity(
    field, value, message
):
    document = minimal_source_map()
    document["mapped"][0][field] = value
    analysis = reference_analysis()

    with pytest.raises(schema.SemanticValidationError, match=message):
        schema.validate_source_map_semantics(document, reference_analysis=analysis)


def test_source_map_context_rejects_prior_truncated_boundary_range():
    document = minimal_source_map()
    document["mapped"] = []
    document["boundary_disputed"] = [
        {
            "address": 28652,
            "size": 56,
            "reference_names": ["__PnPEntry"],
            "reasons": ["incompatible boundaries"],
        },
        {
            "address": 28708,
            "size": 6,
            "reference_names": ["push_arg"],
            "reasons": ["incompatible boundaries"],
        },
    ]
    expected = [
        {"address": 28652, "size": 103, "names": ["__PnPEntry"]},
        {"address": 28708, "size": 6, "names": ["push_arg"]},
    ]
    analysis = reference_analysis(expected)

    with pytest.raises(schema.SemanticValidationError, match="28652.*size 56.*expected 103"):
        schema.validate_source_map_semantics(document, reference_analysis=analysis)


def test_source_map_context_rejects_mutated_map_identity():
    document = minimal_source_map()
    document["reference_sha256"] = "0" * 64

    with pytest.raises(schema.SemanticValidationError, match="source map reference_sha256.*analysis input"):
        schema.validate_source_map_semantics(
            document, reference_analysis=reference_analysis()
        )


def test_source_map_context_rejects_wrong_analysis_identity():
    document = minimal_source_map()

    with pytest.raises(schema.SemanticValidationError, match="source map reference_sha256.*analysis input"):
        schema.validate_source_map_semantics(
            document, reference_analysis=reference_analysis(sha256="B" * 64)
        )


def test_source_map_context_rejects_malformed_analysis():
    document = minimal_source_map()
    analysis = reference_analysis()
    del analysis["input"]["architecture"]

    with pytest.raises(jsonschema.ValidationError):
        schema.validate_source_map_semantics(document, reference_analysis=analysis)


def test_expected_functions_alone_cannot_certify_source_map_identity():
    with pytest.raises(TypeError, match="expected_functions"):
        schema.validate_source_map_semantics(
            minimal_source_map(),
            expected_functions=[{"address": 16, "size": 4, "names": ["entry"]}],
        )


@pytest.mark.parametrize("source_path", ["/src/entry.c", "../src/entry.c", "src\\entry.c"])
def test_source_map_semantics_rejects_noncanonical_source_paths(source_path):
    document = minimal_source_map()
    document["mapped"][0]["source_path"] = source_path

    with pytest.raises(schema.SemanticValidationError, match="repo-relative"):
        schema.validate_source_map_semantics(document)


def test_loader_validates_the_committed_eisabus_source_map_schema_and_semantics():
    repo_root = Path(__file__).parents[3]
    source_map = repo_root / "src/drivers/x86/bus/drvEISABus/reconstruction/source-map.json"

    document = schema.load_source_map(source_map)

    assert document["reference_sha256"] == "8F252AF66CD49A8E03B51E57E90CB613D0B9DC1602263F4B7B6393E483977B23"
