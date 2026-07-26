import json
from pathlib import Path

import restore_symbol_aliases


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
            {"address": 0, "size": 4, "names": ["_VGAStart"], "blocks": [], "instructions": [],
             "calls": [], "confidence": 1.0},
            {"address": 4, "size": 2, "names": ["_other"], "blocks": [], "instructions": [],
             "calls": [], "confidence": 1.0},
        ],
    }


def _macho_document():
    return {
        "symbols": [
            {"name": "_VGAStart", "address": 0, "binding": "external", "section": "__TEXT,__text"},
            {"name": "_Start", "address": 0, "binding": "external", "section": "__TEXT,__text"},
            {"name": "_other", "address": 4, "binding": "external", "section": "__TEXT,__text"},
            {"name": "_data", "address": 8, "binding": "external", "section": "__DATA,__data"},
        ],
    }


def test_restore_symbol_aliases_adds_a_missing_alias():
    restored = restore_symbol_aliases.restore_symbol_aliases(_document(), _macho_document())

    by_address = {function["address"]: function for function in restored["functions"]}
    assert by_address[0]["names"] == ["_Start", "_VGAStart"]
    assert by_address[4]["names"] == ["_other"]


def test_restore_symbol_aliases_preserves_every_other_field_verbatim():
    document = _document()

    restored = restore_symbol_aliases.restore_symbol_aliases(document, _macho_document())

    assert restored["schema_version"] == document["schema_version"]
    assert restored["input"] == document["input"]
    assert restored["input"]["sha256"] == document["input"]["sha256"]
    assert restored["analyzer"] == document["analyzer"]
    assert restored["sections"] == document["sections"]
    assert restored["symbols"] == document["symbols"]
    assert restored["relocations"] == document["relocations"]

    restored_by_address = {f["address"]: f for f in restored["functions"]}
    original_by_address = {f["address"]: f for f in document["functions"]}
    for field in ("size", "blocks", "instructions", "calls", "confidence"):
        assert restored_by_address[4][field] == original_by_address[4][field]


def test_restore_symbol_aliases_is_idempotent_once_every_name_is_present():
    document = _document()
    document["functions"][0]["names"] = ["_Start", "_VGAStart"]

    restored = restore_symbol_aliases.restore_symbol_aliases(document, _macho_document())

    assert restored["functions"] == document["functions"]


def test_main_writes_restored_document(tmp_path, monkeypatch):
    document = _document()
    input_path = tmp_path / "analysis.json"
    binary_path = tmp_path / "VGA_psdrvr"
    output_path = tmp_path / "restored.json"
    input_path.write_text(json.dumps(document), encoding="utf-8")
    binary_path.write_bytes(b"")
    monkeypatch.setattr(
        "restore_symbol_aliases.read_macho",
        lambda path: _macho_document() if path == binary_path else {},
    )

    exit_code = restore_symbol_aliases.main(
        ["restore_symbol_aliases.py", str(input_path), str(binary_path), str(output_path)]
    )

    assert exit_code == 0
    written = json.loads(output_path.read_text(encoding="utf-8"))
    by_address = {function["address"]: function for function in written["functions"]}
    assert by_address[0]["names"] == ["_Start", "_VGAStart"]
    assert written["input"]["sha256"] == document["input"]["sha256"]
