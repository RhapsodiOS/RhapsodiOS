from pathlib import Path

import parity_check


def _write(path: Path, payload: bytes) -> Path:
    path.write_bytes(payload)
    return path


def test_compare_reports_reference_strings_and_symbols_our_build_lacks(tmp_path, monkeypatch):
    reference = _write(tmp_path / "reference", b"alpha\x00beta\x00")
    rebuilt = _write(tmp_path / "rebuilt", b"alpha\x00gamma\x00")
    documents = {
        reference: {
            "sections": [{"name": "__TEXT,__cstring", "offset": 0, "size": 11}],
            "symbols": [
                {"name": "_socketIsValid", "section": "__TEXT,__text"},
                {"name": "_IOLog", "section": None},
            ],
        },
        rebuilt: {
            "sections": [{"name": "__TEXT,__cstring", "offset": 0, "size": 12}],
            "symbols": [{"name": "__socketIsValid", "section": "__TEXT,__text"}],
        },
    }
    monkeypatch.setattr("parity_check.read_macho", lambda path: documents[path])

    result = parity_check.compare(reference, rebuilt)

    assert result["missing_strings"] == ["beta"]
    assert result["extra_strings"] == ["gamma"]
    assert result["missing_symbols"] == ["_socketIsValid"]
    assert result["extra_symbols"] == ["__socketIsValid"]


def test_compare_ignores_absolute_and_undefined_symbols(tmp_path, monkeypatch):
    reference = _write(tmp_path / "reference", b"")
    rebuilt = _write(tmp_path / "rebuilt", b"")
    documents = {
        reference: {
            "sections": [],
            "symbols": [{"name": ".objc_class_name_PCIC", "section": None}],
        },
        rebuilt: {"sections": [], "symbols": []},
    }
    monkeypatch.setattr("parity_check.read_macho", lambda path: documents[path])

    assert parity_check.compare(reference, rebuilt) == {
        "missing_strings": [],
        "extra_strings": [],
        "missing_symbols": [],
        "extra_symbols": [],
    }
