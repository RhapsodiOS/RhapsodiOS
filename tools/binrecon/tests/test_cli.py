import hashlib
import json

import pytest

from binrecon.cli import build_parser, main


def test_help_lists_all_commands():
    help_text = build_parser().format_help()

    for command in ("validate", "analyze", "consensus", "compare", "ledger"):
        assert command in help_text


def _write_profile(tmp_path, *, expected_size=None):
    reference = tmp_path / "reference.bin"
    rebuilt = tmp_path / "rebuilt.bin"
    reference.write_bytes(b"reference")
    rebuilt.write_bytes(b"rebuilt")
    reference_spec = {"path": reference.name}
    if expected_size is not None:
        reference_spec["expected_size"] = expected_size
    document = {
        "schema_version": "profile-v1",
        "name": "cli fixture",
        "architecture": "powerpc",
        "reference": reference_spec,
        "rebuilt": {"path": rebuilt.name},
        "analyzers": {},
        "comparison": {
            "acceptance": "normalized-functions",
            "ignore_metadata": [],
            "entry_points": [],
        },
        "output_dir": "out",
    }
    path = tmp_path / "profile.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    return path, reference, rebuilt


def test_validate_prints_absolute_identities_and_returns_zero(tmp_path, capsys):
    profile_path, reference, rebuilt = _write_profile(tmp_path)

    result = main(["validate", "--profile", str(profile_path)])

    captured = capsys.readouterr()
    assert result == 0
    assert captured.err == ""
    assert captured.out.splitlines() == [
        f"reference {reference.resolve()} size=9 sha256={hashlib.sha256(b'reference').hexdigest().upper()}",
        f"rebuilt {rebuilt.resolve()} size=7 sha256={hashlib.sha256(b'rebuilt').hexdigest().upper()}",
    ]


def test_validate_reports_mismatch_without_traceback(tmp_path, capsys):
    profile_path, reference, _ = _write_profile(tmp_path, expected_size=999)

    result = main(["validate", "--profile", str(profile_path)])

    captured = capsys.readouterr()
    assert result == 1
    assert captured.out == ""
    assert captured.err.startswith("binrecon: ")
    assert str(reference.resolve()) in captured.err
    assert "expected" in captured.err and "actual" in captured.err
    assert "Traceback" not in captured.err


@pytest.mark.parametrize("command", ["analyze", "consensus", "compare", "ledger"])
def test_non_validate_commands_remain_not_implemented(command, capsys):
    result = main([command, "--profile", "unused.json"])

    captured = capsys.readouterr()
    assert result == 2
    assert captured.out == f"binrecon: command not implemented: {command}\n"
    assert captured.err == ""
