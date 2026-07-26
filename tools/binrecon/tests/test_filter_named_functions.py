import json
from pathlib import Path

import filter_named_functions


def _document():
    return {
        "schema_version": "analysis-v1",
        "input": {"path": "VGA_reloc", "size": 6, "sha256": "AB" * 32,
                   "architecture": "i386", "endianness": "little"},
        "analyzer": {"name": "IDA", "version": "9.2", "invocation": "IDAPython"},
        "sections": [{"name": "__TEXT,__text", "address": 0, "offset": 0, "size": 100,
                      "permissions": "r-x", "sha256": "CD" * 32}],
        "symbols": [],
        "relocations": [],
        "functions": [
            {"address": 0, "size": 4, "names": ["_named"], "blocks": [], "instructions": [],
             "calls": [], "confidence": 1.0},
            {"address": 4, "size": 2, "names": [], "blocks": [], "instructions": [],
             "calls": [], "confidence": 1.0},
        ],
    }


def test_filter_named_functions_drops_functions_with_no_names():
    filtered = filter_named_functions.filter_named_functions(_document())

    addresses = [function["address"] for function in filtered["functions"]]
    assert addresses == [0]


def test_filter_named_functions_preserves_every_other_field_verbatim():
    document = _document()

    filtered = filter_named_functions.filter_named_functions(document)

    assert filtered["schema_version"] == document["schema_version"]
    assert filtered["input"] == document["input"]
    assert filtered["input"]["sha256"] == document["input"]["sha256"]
    assert filtered["analyzer"] == document["analyzer"]
    assert filtered["sections"] == document["sections"]
    assert filtered["symbols"] == document["symbols"]
    assert filtered["relocations"] == document["relocations"]
    assert filtered["functions"][0] == document["functions"][0]


def test_main_writes_filtered_document(tmp_path):
    document = _document()
    input_path = tmp_path / "analysis.json"
    output_path = tmp_path / "filtered.json"
    input_path.write_text(json.dumps(document), encoding="utf-8")

    exit_code = filter_named_functions.main(
        ["filter_named_functions.py", str(input_path), str(output_path)]
    )

    assert exit_code == 0
    written = json.loads(output_path.read_text(encoding="utf-8"))
    assert [function["address"] for function in written["functions"]] == [0]
    assert written["input"]["sha256"] == document["input"]["sha256"]
