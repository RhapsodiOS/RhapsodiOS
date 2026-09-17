import json
from pathlib import Path

import filter_contained_fragments


def _document():
    return {
        "schema_version": "analysis-v1",
        "input": {"path": "VGA_psdrvr", "size": 6, "sha256": "AB" * 32,
                   "architecture": "i386", "endianness": "little"},
        "analyzer": {"name": "IDA", "version": "9.2", "invocation": "IDAPython"},
        "sections": [{"name": "__TEXT,__text", "address": 0, "offset": 0, "size": 100,
                      "permissions": "r-x", "sha256": "CD" * 32}],
        "symbols": [],
        "relocations": [],
        "functions": [
            # Named outer function, covers [0, 20).
            {"address": 0, "size": 20, "names": ["_named"], "blocks": [], "instructions": [],
             "calls": [], "confidence": 1.0},
            # Unnamed fragment wholly inside _named -- a basic block, dropped.
            {"address": 4, "size": 2, "names": [], "blocks": [], "instructions": [],
             "calls": [], "confidence": 1.0},
            # Unnamed function standing on its own -- kept and synthesized.
            {"address": 32, "size": 4, "names": [], "blocks": [], "instructions": [],
             "calls": [], "confidence": 1.0},
            # Already-named function standing on its own -- name left alone.
            {"address": 40, "size": 4, "names": ["_other"], "blocks": [], "instructions": [],
             "calls": [], "confidence": 1.0},
        ],
    }


def test_filter_contained_fragments_drops_a_contained_fragment():
    filtered = filter_contained_fragments.filter_contained_fragments(_document())

    addresses = [function["address"] for function in filtered["functions"]]
    assert 4 not in addresses


def test_filter_contained_fragments_keeps_and_names_a_standalone_unnamed_function():
    filtered = filter_contained_fragments.filter_contained_fragments(_document())

    by_address = {function["address"]: function for function in filtered["functions"]}
    assert by_address[32]["names"] == ["sub_00000020"]


def test_filter_contained_fragments_leaves_an_already_named_function_alone():
    filtered = filter_contained_fragments.filter_contained_fragments(_document())

    by_address = {function["address"]: function for function in filtered["functions"]}
    assert by_address[40]["names"] == ["_other"]


def test_filter_contained_fragments_preserves_input_sha256():
    document = _document()

    filtered = filter_contained_fragments.filter_contained_fragments(document)

    assert filtered["input"] == document["input"]
    assert filtered["input"]["sha256"] == document["input"]["sha256"]


def test_filter_contained_fragments_preserves_every_other_field_verbatim():
    document = _document()

    filtered = filter_contained_fragments.filter_contained_fragments(document)

    assert filtered["schema_version"] == document["schema_version"]
    assert filtered["analyzer"] == document["analyzer"]
    assert filtered["sections"] == document["sections"]
    assert filtered["symbols"] == document["symbols"]
    assert filtered["relocations"] == document["relocations"]
    assert filtered["functions"][0] == document["functions"][0]


def test_a_function_does_not_contain_itself():
    document = {
        "schema_version": "analysis-v1",
        "input": {"path": "x", "size": 6, "sha256": "AB" * 32,
                   "architecture": "i386", "endianness": "little"},
        "analyzer": {"name": "IDA", "version": "9.2", "invocation": "IDAPython"},
        "sections": [],
        "symbols": [],
        "relocations": [],
        "functions": [
            {"address": 0, "size": 4, "names": [], "blocks": [], "instructions": [],
             "calls": [], "confidence": 1.0},
        ],
    }

    filtered = filter_contained_fragments.filter_contained_fragments(document)

    addresses = [function["address"] for function in filtered["functions"]]
    assert addresses == [0]
    assert filtered["functions"][0]["names"] == ["sub_00000000"]


def test_main_writes_filtered_document(tmp_path):
    document = _document()
    input_path = tmp_path / "analysis.json"
    output_path = tmp_path / "filtered.json"
    input_path.write_text(json.dumps(document), encoding="utf-8")

    exit_code = filter_contained_fragments.main(
        ["filter_contained_fragments.py", str(input_path), str(output_path)]
    )

    assert exit_code == 0
    written = json.loads(output_path.read_text(encoding="utf-8"))
    addresses = [function["address"] for function in written["functions"]]
    assert 4 not in addresses
    assert written["input"]["sha256"] == document["input"]["sha256"]
