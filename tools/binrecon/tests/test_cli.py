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


def _example_profile_path():
    return Path(__file__).resolve().parents[1] / "profiles" / "example.json"


def test_readme_uses_venv_interpreter_without_activation_and_generic_artifact_paths():
    readme = (_example_profile_path().parents[1] / "README.md").read_text(
        encoding="utf-8"
    )

    assert "$binreconPython = '.\\.venv-binrecon\\Scripts\\python.exe'" in readme
    assert "Activate.ps1" not in readme
    assert "\npython -m" not in readme
    assert "C:\\Users\\raynorpat" not in readme


def test_module_help_lists_every_command():
    completed = subprocess.run(
        [sys.executable, "-m", "binrecon", "--help"],
        env=_subprocess_environment(),
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )

    assert completed.returncode == 0
    assert completed.stderr == ""
    for command in ("validate", "analyze", "consensus", "compare", "ledger"):
        assert command in completed.stdout


def test_example_profile_reports_unset_artifact_environment(tmp_path):
    environment = _subprocess_environment()
    environment.pop("BINRECON_REFERENCE", None)
    environment.pop("BINRECON_REBUILT", None)

    completed = subprocess.run(
        [sys.executable, "-m", "binrecon", "validate", "--profile",
         str(_example_profile_path())],
        cwd=tmp_path,
        env=environment,
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )

    assert completed.returncode == 1
    assert completed.stdout == ""
    assert completed.stderr == (
        "binrecon: reference artifact: artifact variable BINRECON_REFERENCE is not set\n"
    )


def test_example_profile_validates_with_external_artifacts(tmp_path):
    reference = tmp_path / "EISABus.config"
    rebuilt = tmp_path / "EISABus.rebuilt"
    reference.write_bytes(b"reference")
    rebuilt.write_bytes(b"rebuilt")
    environment = _subprocess_environment()
    environment["BINRECON_REFERENCE"] = str(reference)
    environment["BINRECON_REBUILT"] = str(rebuilt)

    completed = subprocess.run(
        [sys.executable, "-m", "binrecon", "validate", "--profile",
         str(_example_profile_path())],
        cwd=tmp_path,
        env=environment,
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )

    assert completed.returncode == 0
    assert completed.stderr == ""
    assert str(reference.resolve()) in completed.stdout
    assert str(rebuilt.resolve()) in completed.stdout


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


def test_analyze_calls_runner_and_returns_acceptance(monkeypatch, tmp_path, capsys):
    profile_path, _, _ = _write_profile(tmp_path)
    captured_call = {}
    def fake(profile, *, output_path, ledger_path):
        captured_call.update(output=output_path, ledger=ledger_path)
        return {"complete": True, "acceptance": {"requirement": "normalized-functions", "passed": False},
                "analyzers": [], "comparisons": []}
    monkeypatch.setattr("binrecon.cli.run_analysis", fake)
    result = main(["analyze", "--profile", str(profile_path), "--ledger", str(tmp_path / "ledger.json"),
                   "--output", str(tmp_path / "summary.json")])
    assert result == 1
    assert captured_call == {"output": tmp_path / "summary.json", "ledger": tmp_path / "ledger.json"}
    assert capsys.readouterr().out == "analysis complete; analyzers=0 comparisons=0 normalized-functions=FAIL\n"


def test_ledger_cli_validates_and_transitions(tmp_path, capsys):
    from binrecon.ledger import new_ledger, write_ledger
    from binrecon.profile import load_profile
    profile_path, _, _ = _write_profile(tmp_path)
    loaded = load_profile(profile_path, os.environ); path = tmp_path / "ledger.json"
    value = {"address": 4096, "size": 4, "names": ["probe"], "source_path": None,
             "source_line": None, "status": "unexamined",
             "analyzer_agreement": {"status": "none", "analyzers": [], "reasons": []},
             "artifacts": [], "reason": None, "reviewer": None}
    write_ledger(path, new_ledger(loaded.reference_identity, loaded.rebuilt_identity, [value]),
                 loaded.reference_identity, loaded.rebuilt_identity)
    result = main(["ledger", "--profile", str(profile_path), "--ledger", str(path),
                   "--address", "0x1000", "--status", "signature-confirmed",
                   "--source-path", "src/probe.c", "--source-line", "7"])
    assert result == 0
    assert json.loads(path.read_text())["entries"][0]["status"] == "signature-confirmed"
    assert "entries=1" in capsys.readouterr().out


def test_ledger_cli_rejects_incoherent_transition_flags(tmp_path, capsys):
    profile_path, _, _ = _write_profile(tmp_path)
    result = main(["ledger", "--profile", str(profile_path), "--ledger", str(tmp_path / "x.json"),
                   "--address", "0x1000"])
    assert result == 1 and "--address and --status" in capsys.readouterr().err


def test_ledger_module_entrypoint_validates_outside_repository_cwd(tmp_path):
    from binrecon.ledger import new_ledger, write_ledger
    from binrecon.profile import load_profile
    profile_path, _, _ = _write_profile(tmp_path)
    profile = load_profile(profile_path, os.environ); ledger_path = tmp_path / "ledger.json"
    write_ledger(ledger_path, new_ledger(profile.reference_identity, profile.rebuilt_identity),
                 profile.reference_identity, profile.rebuilt_identity)
    working = tmp_path / "working"; working.mkdir()
    completed = subprocess.run([sys.executable, "-m", "binrecon", "ledger",
        "--profile", str(profile_path), "--ledger", str(ledger_path)], cwd=working,
        env=_subprocess_environment(), capture_output=True, text=True, check=False)
    assert completed.returncode == 0 and completed.stderr == ""
    assert completed.stdout.strip().endswith("entries=0")


def _write_real_angr_profile(tmp_path, *, mismatch=False):
    pytest.importorskip("angr", reason="pinned angr 9.3 is unavailable")
    code = b"\x55\x89\xe5\x31\xc0\x5d\xc3"
    reference = tmp_path / "reference.bin"; reference.write_bytes(code)
    rebuilt = tmp_path / "rebuilt.bin"; rebuilt.write_bytes(code if not mismatch else code[:-2] + b"\x40\xc3")
    document = {"schema_version": "profile-v1", "name": "real angr CLI", "architecture": "i386",
        "endianness": "little", "image_base": 4096,
        "reference": {"path": reference.name}, "rebuilt": {"path": rebuilt.name},
        "regions": [{"name": ".text", "address": 4096, "offset": 0, "size": len(code),
                     "permissions": "rx"}],
        "analyzers": {"angr": {"enabled": True, "executable": sys.executable,
                                  "timeout_seconds": 60, "version": "9.3.0"}},
        "comparison": {"acceptance": "exact-image", "ignore_metadata": [], "entry_points": []},
        "output_dir": "out"}
    path = tmp_path / "profile-angr.json"; path.write_text(json.dumps(document), encoding="utf-8")
    return path


def test_analyze_module_entrypoint_runs_real_angr_pipeline_and_is_deterministic(tmp_path):
    from binrecon.runner import validate_run_summary
    profile = _write_real_angr_profile(tmp_path); ledger = tmp_path / "ledger.json"
    working = tmp_path / "working"; working.mkdir()
    command = [sys.executable, "-m", "binrecon", "analyze", "--profile", str(profile),
               "--ledger", str(ledger)]
    first = subprocess.run(command, cwd=working, env=_subprocess_environment(),
                           capture_output=True, text=True, timeout=120, check=False)
    assert first.returncode == 0, first.stderr
    summary_path = tmp_path / "out" / "run-summary.json"; first_bytes = summary_path.read_bytes()
    summary = json.loads(first_bytes); validate_run_summary(summary)
    assert summary["complete"] is True and summary["acceptance"]["passed"] is True
    for record in [summary["analyzers"][0]["reference"], summary["analyzers"][0]["rebuilt"],
                   summary["consensus"]["reference"], summary["consensus"]["rebuilt"],
                   summary["comparisons"][0]]:
        assert (tmp_path / "out" / record["path"]).is_file()
    ledger_document = json.loads(ledger.read_text(encoding="utf-8"))
    assert ledger_document["entries"] and {entry["status"] for entry in ledger_document["entries"]} == {"unexamined"}
    second = subprocess.run(command, cwd=working, env=_subprocess_environment(),
                            capture_output=True, text=True, timeout=120, check=False)
    assert second.returncode == 0, second.stderr
    assert summary_path.read_bytes() == first_bytes


def test_analyze_module_entrypoint_real_angr_mismatch_returns_one_with_evidence(tmp_path):
    profile = _write_real_angr_profile(tmp_path, mismatch=True)
    completed = subprocess.run([sys.executable, "-m", "binrecon", "analyze", "--profile", str(profile)],
        cwd=tmp_path, env=_subprocess_environment(), capture_output=True, text=True, timeout=120, check=False)
    assert completed.returncode == 1
    summary = json.loads((tmp_path / "out" / "run-summary.json").read_text(encoding="utf-8"))
    assert summary["complete"] is True and summary["acceptance"]["passed"] is False
    assert summary["comparisons"][0]["passed"] is False


def _write_compare_case(tmp_path, *, different=False):
    from test_normalize import analysis
    profile, reference, rebuilt = _write_profile(tmp_path)
    reference.write_bytes(b"\xe8\x78\x56\x34\x12\x3d\x78\x56\x34\x12\xe4\x80" + b"\0" * 52)
    rebuilt.write_bytes(reference.read_bytes())
    documents = []
    for name, artifact in (("IDA", reference), ("Ghidra", rebuilt)):
        document = analysis(name)
        data = artifact.read_bytes(); digest = hashlib.sha256(data).hexdigest()
        document["input"].update(path=str(artifact), size=len(data), sha256=digest)
        document["sections"][0].update(size=len(data), sha256=digest)
        documents.append(document)
    if different:
        documents[1]["functions"][0]["instructions"][1]["bytes"] = "3C78563412"
    paths = tmp_path / "ref.json", tmp_path / "reb.json"
    for path, document in zip(paths, documents): path.write_text(json.dumps(document), encoding="utf-8")
    return profile, paths


def test_compare_cli_publishes_json_and_text_and_returns_selected_status(tmp_path, capsys):
    profile, (reference_analysis, rebuilt_analysis) = _write_compare_case(tmp_path)
    output = tmp_path / "report.json"
    result = main(["compare", "--profile", str(profile),
                   "--reference-analysis", str(reference_analysis),
                   "--rebuilt-analysis", str(rebuilt_analysis),
                   "--output", str(output), "--text-output", "-", "--require", "exact-image"])
    captured = capsys.readouterr(); report = json.loads(output.read_text())
    assert result == 0 and captured.err == ""
    assert captured.out.startswith("exact-image: PASS ")
    assert report["selected"] == {"requirement": "exact-image", "passed": True}


def test_compare_cli_returns_one_but_still_publishes_ordinary_mismatch(tmp_path):
    profile, paths = _write_compare_case(tmp_path, different=True)
    output = tmp_path / "report.json"
    result = main(["compare", "--profile", str(profile), "--reference-analysis", str(paths[0]),
                   "--rebuilt-analysis", str(paths[1]), "--output", str(output),
                   "--require", "normalized-functions"])
    assert result == 1
    assert json.loads(output.read_text())["categories"]["code"]


def test_compare_cli_rejects_output_alias_without_overwriting_input(tmp_path):
    profile, paths = _write_compare_case(tmp_path)
    before = paths[0].read_bytes()
    result = main(["compare", "--profile", str(profile), "--reference-analysis", str(paths[0]),
                   "--rebuilt-analysis", str(paths[1]), "--output", str(paths[0])])
    assert result == 1 and paths[0].read_bytes() == before


def test_compare_module_entrypoint_runs_from_outside_repository(tmp_path):
    profile, paths = _write_compare_case(tmp_path)
    output = tmp_path / "report.json"
    working = tmp_path / "working"; working.mkdir()
    completed = subprocess.run(
        [sys.executable, "-m", "binrecon", "compare", "--profile", str(profile),
         "--reference-analysis", str(paths[0]), "--rebuilt-analysis", str(paths[1]),
         "--output", str(output), "--text-output", "-", "--require", "exact-image"],
        cwd=working, env=_subprocess_environment(), capture_output=True, text=True, check=False)
    assert completed.returncode == 0 and completed.stderr == ""
    assert completed.stdout.startswith("exact-image: PASS ")
    assert json.loads(output.read_text())["acceptance"]["exact-image"] is True


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
