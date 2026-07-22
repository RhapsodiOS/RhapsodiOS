import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

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


def _subprocess_environment():
    environment = os.environ.copy()
    package_root = str(Path(__file__).resolve().parents[1])
    existing = environment.get("PYTHONPATH")
    environment["PYTHONPATH"] = (
        package_root if not existing else package_root + os.pathsep + existing
    )
    return environment


def test_validate_module_entrypoint_succeeds_outside_repository_cwd(tmp_path):
    profile_path, reference, rebuilt = _write_profile(tmp_path)
    working_dir = tmp_path / "working"
    working_dir.mkdir()

    completed = subprocess.run(
        [sys.executable, "-m", "binrecon", "validate", "--profile", str(profile_path)],
        cwd=working_dir,
        env=_subprocess_environment(),
        capture_output=True,
        text=True,
        check=False,
    )

    assert completed.returncode == 0
    assert completed.stderr == ""
    assert completed.stdout.splitlines() == [
        f"reference {reference.resolve()} size=9 sha256={hashlib.sha256(b'reference').hexdigest().upper()}",
        f"rebuilt {rebuilt.resolve()} size=7 sha256={hashlib.sha256(b'rebuilt').hexdigest().upper()}",
    ]


def test_validate_module_entrypoint_reports_invalid_profile_without_traceback(tmp_path):
    profile_path, _, _ = _write_profile(tmp_path)
    document = json.loads(profile_path.read_text(encoding="utf-8"))
    del document["architecture"]
    profile_path.write_text(json.dumps(document), encoding="utf-8")
    working_dir = tmp_path / "working"
    working_dir.mkdir()

    completed = subprocess.run(
        [sys.executable, "-m", "binrecon", "validate", "--profile", str(profile_path)],
        cwd=working_dir,
        env=_subprocess_environment(),
        capture_output=True,
        text=True,
        check=False,
    )

    assert completed.returncode == 1
    assert completed.stdout == ""
    assert completed.stderr.startswith("binrecon: ")
    assert "architecture" in completed.stderr
    assert "Traceback" not in completed.stderr


@pytest.mark.parametrize("command", ["analyze", "compare", "ledger"])
def test_non_validate_commands_remain_not_implemented(command, capsys):
    result = main([command, "--profile", "unused.json"])

    captured = capsys.readouterr()
    assert result == 2
    assert captured.out == f"binrecon: command not implemented: {command}\n"
    assert captured.err == ""


def test_consensus_module_entrypoint_writes_deterministic_json(tmp_path):
    from test_normalize import analysis
    inputs = []
    for name in ("IDA", "Ghidra", "angr"):
        path = tmp_path / f"{name}.json"
        path.write_text(json.dumps(analysis(name)), encoding="utf-8")
        inputs.append(path)
    output = tmp_path / "consensus.json"
    completed = subprocess.run(
        [sys.executable, "-m", "binrecon", "consensus",
         *(part for path in reversed(inputs) for part in ("--input", str(path))),
         "--output", str(output)], cwd=tmp_path, env=_subprocess_environment(),
        capture_output=True, text=True, check=False)
    assert completed.returncode == 0
    assert completed.stdout == ""
    document = json.loads(output.read_text(encoding="utf-8"))
    assert document["schema_version"] == "consensus-v1"
    assert document["groups"][0]["status"] == "agreed"
    first_bytes = output.read_bytes()
    second_output = tmp_path / "consensus-reordered.json"
    reordered = subprocess.run(
        [sys.executable, "-m", "binrecon", "consensus",
         *(part for path in inputs for part in ("--input", str(path))),
         "--output", str(second_output)], cwd=tmp_path, env=_subprocess_environment(),
        capture_output=True, text=True, check=False)
    assert reordered.returncode == 0
    assert second_output.read_bytes() == first_bytes


@pytest.mark.parametrize("mode", ["malformed", "schema", "identity", "alias"])
def test_consensus_entrypoint_rejects_unsafe_or_invalid_inputs_without_partial_output(tmp_path, mode):
    from test_normalize import analysis
    first = tmp_path / "one.json"
    second = tmp_path / "two.json"
    first.write_text(json.dumps(analysis("IDA")), encoding="utf-8")
    other = analysis("Ghidra")
    if mode == "malformed":
        second.write_text("{", encoding="utf-8")
    else:
        if mode == "schema": del other["input"]["architecture"]
        if mode == "identity": other["input"]["size"] += 1
        second.write_text(json.dumps(other), encoding="utf-8")
    output = first if mode == "alias" else tmp_path / "out.json"
    completed = subprocess.run(
        [sys.executable, "-m", "binrecon", "consensus", "--input", str(first),
         "--input", str(second), "--output", str(output)], cwd=tmp_path,
        env=_subprocess_environment(), capture_output=True, text=True, check=False)
    assert completed.returncode == 1
    assert completed.stdout == ""
    assert completed.stderr.startswith("binrecon: ")
    if mode != "alias": assert not output.exists()


def test_consensus_cli_expected_analyzer_override_allows_two_way_agreement(tmp_path):
    from test_normalize import analysis
    inputs = []
    for name in ("IDA", "Ghidra"):
        path = tmp_path / f"{name}.json"
        path.write_text(json.dumps(analysis(name)), encoding="utf-8")
        inputs.append(path)
    output = tmp_path / "out.json"
    completed = subprocess.run(
        [sys.executable, "-m", "binrecon", "consensus",
         *(part for path in inputs for part in ("--input", str(path))),
         "--expected-analyzer", "IDA", "--expected-analyzer", "Ghidra",
         "--output", str(output)], cwd=tmp_path, env=_subprocess_environment(),
        capture_output=True, text=True, check=False)
    assert completed.returncode == 0
    assert json.loads(output.read_text())["groups"][0]["status"] == "agreed"


def test_consensus_cli_rejects_nonfinite_json_constant(tmp_path):
    source = tmp_path / "bad.json"; source.write_text('{"value":NaN}', encoding="utf-8")
    completed = subprocess.run([sys.executable, "-m", "binrecon", "consensus",
        "--input", str(source), "--output", str(tmp_path / "out.json")], cwd=tmp_path,
        env=_subprocess_environment(), capture_output=True, text=True, check=False)
    assert completed.returncode == 1
    assert "non-finite" in completed.stderr
