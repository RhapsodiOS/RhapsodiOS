import hashlib
import importlib.util
import json
from pathlib import Path
from types import MappingProxyType, SimpleNamespace
import subprocess
import sys

import pytest

import binrecon.adapters.angr as angr_host
from binrecon.adapters.angr import AngrAdapterError, export_with_angr
from binrecon.identity import identify


def _analysis(identity, version="9.3.0"):
    return {
        "schema_version": "analysis-v1",
        "input": {"path": str(identity.path), "size": identity.size,
                  "sha256": identity.sha256, "architecture": "i386",
                  "endianness": "little"},
        "analyzer": {"name": "angr", "version": version,
                     "invocation": "binrecon-angr-export"},
        "sections": [], "symbols": [], "relocations": [], "functions": [],
        "references": [], "imports": [], "strings": [],
        "extensions": {"angr": {"cfg": {"errors": []}, "symbolic_checks": []}},
    }


@pytest.fixture
def configured(tmp_path):
    binary = tmp_path / "input with spaces.o"
    binary.write_bytes(b"legacy-mach-o")
    executable = tmp_path / "Python 3.13" / "python.exe"
    executable.parent.mkdir()
    executable.write_text("stub", encoding="ascii")
    identity = identify(binary)
    profile = SimpleNamespace(
        reference_identity=identity, rebuilt_identity=identity,
        document=MappingProxyType({
            "architecture": "i386", "endianness": "little", "image_base": 0x1000,
            "analyzers": MappingProxyType({"angr": MappingProxyType({
                "enabled": True, "executable": str(executable),
                "timeout_seconds": 19, "version": "9.3.0"})}),
            "comparison": MappingProxyType({"entry_points": ("entry",)}),
            "regions": (), "symbolic_checks": (),
        }),
    )
    return profile, identity, executable


def test_host_uses_shell_free_unique_files_and_atomically_publishes(configured, tmp_path):
    profile, identity, executable = configured
    destination = tmp_path / "analysis.json"
    calls = []

    def runner(argv, **options):
        calls.append((list(argv), options))
        options["stdout"].write(b"stdout")
        options["stdout"].flush()
        output = Path(argv[argv.index("--output") + 1])
        output.write_text(json.dumps(_analysis(identity)), encoding="utf-8")
        return subprocess.CompletedProcess(argv, 0)

    document = export_with_angr(profile, "reference", destination, runner=runner)
    argv, options = calls[0]
    assert argv[0] == str(executable.resolve())
    assert argv[1].endswith("export_analysis.py")
    assert argv[argv.index("--input") + 1] == str(identity.path)
    assert argv[argv.index("--size") + 1] == str(identity.size)
    assert argv[argv.index("--sha256") + 1] == identity.sha256
    config_path = Path(argv[argv.index("--config") + 1])
    layout_path = Path(argv[argv.index("--layout") + 1])
    assert config_path != layout_path and config_path.parent == layout_path.parent
    assert options["stderr"] == subprocess.STDOUT
    assert options["timeout"] == 19 and options["shell"] is False and options["check"] is False
    assert "capture_output" not in options and "text" not in options
    assert document == _analysis(identity)
    assert destination.read_text(encoding="utf-8") == json.dumps(
        document, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n"
    assert "stdout" in destination.with_suffix(".json.angr.log").read_text()
    assert not any(tmp_path.glob(".*angr-work-*"))


@pytest.mark.parametrize("mode,match", [
    ("missing", "fresh"), ("malformed", "malformed"),
    ("identity", "identity"), ("version", "version"), ("contract", "contract"),
])
def test_host_rejects_untrusted_or_mismatched_output(configured, tmp_path, mode, match):
    profile, identity, _ = configured
    destination = tmp_path / f"{mode}.json"
    destination.write_text("known-good", encoding="ascii")

    def runner(argv, **options):
        output = Path(argv[argv.index("--output") + 1])
        if mode == "malformed":
            output.write_text("{", encoding="ascii")
        elif mode != "missing":
            document = _analysis(identity, "9.3.1" if mode == "version" else "9.3.0")
            if mode == "identity": document["input"]["sha256"] = "0" * 64
            if mode == "contract": document["extensions"]["angr"]["symbolic_checks"] = [
                {"name": "x", "status": "maybe"}]
            output.write_text(json.dumps(document), encoding="utf-8")
        return subprocess.CompletedProcess(argv, 0, "", "")

    with pytest.raises(AngrAdapterError, match=match):
        export_with_angr(profile, "reference", destination, runner=runner)
    assert destination.read_text(encoding="ascii") == "known-good"


def test_host_preserves_primary_error_and_rejects_aliases(configured, tmp_path):
    profile, identity, _ = configured
    with pytest.raises(AngrAdapterError, match="aliases"):
        export_with_angr(profile, "reference", identity.path)
    destination = tmp_path / "result.json"
    def runner(argv, **options):
        options["stdout"].write(b"partial\nlate")
        options["stdout"].flush()
        raise subprocess.TimeoutExpired(argv, 19)
    with pytest.raises(AngrAdapterError, match="timed out"):
        export_with_angr(profile, "reference", destination, runner=runner)
    assert "partial" in destination.with_suffix(".json.angr.log").read_text()


def test_host_rejects_destination_and_log_hardlink_alias(configured, tmp_path):
    profile, _, _ = configured
    destination = tmp_path / "result.json"
    destination.write_text("old", encoding="ascii")
    destination.with_suffix(".json.angr.log").hardlink_to(destination)
    with pytest.raises(AngrAdapterError, match="destination and log"):
        export_with_angr(profile, "reference", destination)


def test_host_rejects_peer_aliases_before_launch(configured, tmp_path):
    profile, _, _ = configured
    peer = tmp_path / "peer.bin"; peer.write_bytes(b"peer")
    profile.rebuilt_identity = identify(peer)
    with pytest.raises(AngrAdapterError, match="peer"):
        export_with_angr(profile, "reference", peer)
    destination = tmp_path / "peer"
    destination.with_suffix(".angr.log").hardlink_to(peer)
    with pytest.raises(AngrAdapterError, match="peer"):
        export_with_angr(profile, "reference", destination)


def test_host_streams_and_bounds_large_child_log(configured, tmp_path):
    profile, identity, _ = configured
    def runner(argv, **options):
        options["stdout"].write(b"X" * (5 * 1024 * 1024)); options["stdout"].flush()
        Path(argv[argv.index("--output") + 1]).write_text(
            json.dumps(_analysis(identity)), encoding="utf-8")
        return subprocess.CompletedProcess(argv, 0)
    destination = tmp_path / "bounded.json"
    export_with_angr(profile, "reference", destination, runner=runner)
    log = destination.with_suffix(".json.angr.log").read_bytes()
    assert len(log) <= 4 * 1024 * 1024 + 64 and b"[truncated]" in log


def test_timeout_keeps_primary_when_log_publication_fails(configured, tmp_path, monkeypatch):
    profile, _, _ = configured
    def runner(argv, **options): raise subprocess.TimeoutExpired(argv, 19)
    monkeypatch.setattr(angr_host, "_publish_log", lambda *args: (_ for _ in ()).throw(OSError("log denied")))
    destination = tmp_path / "timeout.json"
    with pytest.raises(AngrAdapterError, match="timed out") as captured:
        export_with_angr(profile, "reference", destination, runner=runner)
    assert any("log denied" in note for note in captured.value.__notes__)
    assert not destination.exists()


def test_successful_child_log_failure_prevents_destination_replace(configured, tmp_path, monkeypatch):
    profile, identity, _ = configured
    destination = tmp_path / "result.json"; destination.write_text("known-good", encoding="ascii")
    def runner(argv, **options):
        Path(argv[argv.index("--output") + 1]).write_text(json.dumps(_analysis(identity)), encoding="utf-8")
        return subprocess.CompletedProcess(argv, 0)
    monkeypatch.setattr(angr_host, "_publish_log", lambda *args: (_ for _ in ()).throw(OSError("log denied")))
    with pytest.raises(OSError, match="log denied"):
        export_with_angr(profile, "reference", destination, runner=runner)
    assert destination.read_text(encoding="ascii") == "known-good"


def test_peer_change_or_destination_alias_race_prevents_publish(configured, tmp_path):
    profile, identity, _ = configured
    peer = tmp_path / "peer.bin"; peer.write_bytes(b"peer")
    profile.rebuilt_identity = identify(peer)
    destination = tmp_path / "race.json"; destination.write_text("known-good", encoding="ascii")
    def peer_change(argv, **options):
        Path(argv[argv.index("--output") + 1]).write_text(json.dumps(_analysis(identity)), encoding="utf-8")
        peer.write_bytes(b"changed")
        return subprocess.CompletedProcess(argv, 0)
    with pytest.raises(AngrAdapterError, match="peer input identity changed"):
        export_with_angr(profile, "reference", destination, runner=peer_change)
    assert destination.read_text(encoding="ascii") == "known-good"


def test_workspace_is_cleaned_when_config_write_fails(configured, tmp_path, monkeypatch):
    profile, _, _ = configured; workspaces = []
    original_remove = angr_host.shutil.rmtree
    def remove(path): workspaces.append(Path(path)); return original_remove(path)
    monkeypatch.setattr(angr_host.shutil, "rmtree", remove)
    monkeypatch.setattr(angr_host, "_atomic_text", lambda *args: (_ for _ in ()).throw(OSError("config denied")))
    with pytest.raises(OSError, match="config denied"):
        export_with_angr(profile, "reference", tmp_path / "fail.json")
    assert len(workspaces) == 1 and not workspaces[0].exists()


def _load_script():
    path = Path(__file__).parents[1] / "adapters" / "angr" / "export_analysis.py"
    spec = importlib.util.spec_from_file_location("binrecon_angr_export", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_exporter_is_import_safe_and_argument_parser_is_closed(tmp_path):
    module = _load_script()
    assert callable(module.main)
    with pytest.raises(SystemExit):
        module.parse_arguments(["--unknown"])
    complete = ["--input", "i", "--output", "o", "--config", "c", "--layout", "l",
                "--size", "1", "--sha256", "A" * 64]
    with pytest.raises(SystemExit):
        module.parse_arguments(complete + ["--size", "2"])
    source = Path(module.__file__).read_text(encoding="utf-8")
    assert "auto_load_libs=False" in source
    assert "CFGFast" in source and "normalize=True" in source
    assert "resolve_indirect_jumps=True" in source


def test_native_loader_is_first_and_only_genuine_cle_loader_error_falls_back(tmp_path):
    module = _load_script()
    binary = tmp_path / "input.o"; binary.write_bytes(b"raw")
    layout = {"image_base": 0x1000, "entry_points": [0x1000], "sections": [
        {"address": 0x1000, "offset": 1, "size": 2, "permissions": "rx",
         "initialized": True}
    ]}
    calls = []
    class CLEError(Exception): __module__ = "cle.errors"
    class FakeAngr:
        def Project(self, source, **options):
            calls.append((source, options))
            if len(calls) == 1: raise CLEError("Mach-O backend unsupported")
            return "fallback"
    assert module.load_project(FakeAngr(), binary, layout) == "fallback"
    assert calls[0] == (str(binary), {"auto_load_libs": False})
    assert calls[1][1]["auto_load_libs"] is False
    assert calls[1][1]["main_opts"]["backend"] == "blob"
    assert calls[1][1]["main_opts"]["arch"] == "x86"
    assert bytes(calls[1][0].getvalue()) == b"aw"

    calls.clear()
    class CFGError(Exception): pass
    class Broken:
        def Project(self, source, **options): raise CFGError("CFG failed")
    with pytest.raises(CFGError, match="CFG failed"):
        module.load_project(Broken(), binary, layout)


def test_cfg_starts_include_profile_entries_and_symbols_and_output_is_sorted():
    module = _load_script()
    starts = module.function_starts(
        {"entry_points": [0x2000, 0x1000]},
        {"symbols": [{"address": 0x3000}, {"address": 0x1000}]})
    assert starts == [0x1000, 0x2000, 0x3000]


def test_symbolic_results_never_turn_limits_errors_or_unsupported_into_passes():
    module = _load_script()
    assert module.classify_execution([], [], hit_limit=True)["status"] == "limit-reached"
    assert module.classify_execution([], ["decode failed"], hit_limit=False)["status"] == "unsupported"
    assert module.unsupported_check("x", "unknown hook")["status"] == "unsupported"


@pytest.mark.skipif(importlib.util.find_spec("angr") is None, reason="angr not installed")
def test_real_angr_checksum_like_symbolic_execution_pass_fail_and_limit(tmp_path):
    module = _load_script()
    # cdecl checksum: sum exactly 8 symbolic input bytes modulo 256.
    binary = tmp_path / "byte_checksum.bin"
    binary.write_bytes(bytes.fromhex("8B5424048B4C240831C00202424975FAC3"))
    import angr
    project = angr.Project(str(binary), main_opts={"backend": "blob", "arch": "x86",
        "base_addr": 0x4000, "entry_point": 0x4000}, auto_load_libs=False)
    common = {"name": "checksum8", "function": "0x4000", "input_bytes": 8,
              "max_active_states": 4, "max_steps": 40, "registers": {}, "memory": [],
              "hooks": []}
    passing = module.run_symbolic_check(project, {**common,
        "assertions": [{"kind": "return-equals", "value": 0}]})
    assert passing["status"] == "failed" and len(passing["counterexample"]["input_hex"]) == 16
    assert passing["counterexample"]["actual"] != 0
    limited = module.run_symbolic_check(project, {**common, "max_steps": 1,
        "assertions": [{"kind": "return-equals", "value": 0}]})
    assert limited["status"] == "limit-reached"
    unsupported = module.run_symbolic_check(project, {**common,
        "hooks": [{"address": 0x5000, "handler": "mystery", "returns": 1}],
        "assertions": [{"kind": "return-equals", "value": 0}]})
    assert unsupported["status"] == "unsupported"


@pytest.mark.skipif(importlib.util.find_spec("angr") is None, reason="angr not installed")
def test_real_angr_universal_pass_memory_hook_and_active_state_cap(tmp_path):
    module = _load_script()
    import angr
    def project_for(name, code):
        path = tmp_path / name; path.write_bytes(bytes.fromhex(code))
        return angr.Project(str(path), main_opts={"backend": "blob", "arch": "x86",
            "base_addr": 0x4000, "entry_point": 0x4000}, auto_load_libs=False)
    base = {"name": "check", "function": "0x4000", "input_bytes": 0,
            "max_active_states": 4, "max_steps": 8, "registers": {}, "memory": [],
            "hooks": []}
    constant = project_for("constant.bin", "B807000000C3")
    assert module.run_symbolic_check(constant, {**base,
        "assertions": [{"kind": "return-equals", "value": 7}]})["status"] == "passed"

    writer = project_for("writer.bin", "C705008000007F000000B807000000C3")
    assert module.run_symbolic_check(writer, {**base,
        "assertions": [{"kind": "memory-equals", "address": 0x8000,
                         "bytes": "7F000000"}]})["status"] == "passed"

    caller = project_for("caller.bin", "E8FB0F0000C3")
    hooked = module.run_symbolic_check(caller, {**base,
        "hooks": [{"address": 0x5000, "handler": "return-constant", "returns": 9}],
        "assertions": [{"kind": "return-equals", "value": 9}]})
    assert hooked["status"] == "passed"

    branch = project_for("branch.bin", "8B4424048038007506B801000000C331C0C3")
    capped = module.run_symbolic_check(branch, {**base, "input_bytes": 1,
        "max_active_states": 1,
        "assertions": [{"kind": "return-equals", "value": 0}]})
    assert capped["status"] == "limit-reached"


@pytest.mark.skipif(importlib.util.find_spec("angr") is None, reason="angr not installed")
def test_real_angr_cfg_smoke_is_schema_valid_and_deterministic(tmp_path):
    module = _load_script()
    import angr
    binary = tmp_path / "cfg.bin"; binary.write_bytes(bytes.fromhex("B807000000C3"))
    project = angr.Project(str(binary), main_opts={"backend": "blob", "arch": "x86",
        "base_addr": 0x4000, "entry_point": 0x4000}, auto_load_libs=False)
    layout = {"entry_points": [0x4000]}
    first = module.export_cfg(project, layout, {"symbols": [], "relocations": []})
    second = module.export_cfg(project, layout, {"symbols": [], "relocations": []})
    assert json.dumps(first, sort_keys=True) == json.dumps(second, sort_keys=True)
    assert first[0][0]["address"] == 0x4000


@pytest.mark.skipif(importlib.util.find_spec("angr") is None, reason="angr not installed")
def test_real_host_export_smoke_uses_pinned_angr(tmp_path):
    binary = tmp_path / "raw.bin"; binary.write_bytes(bytes.fromhex("B807000000C3"))
    identity = identify(binary)
    profile = SimpleNamespace(reference_identity=identity, rebuilt_identity=identity,
        document=MappingProxyType({"architecture": "i386", "endianness": "little",
            "image_base": 0x4000, "analyzers": MappingProxyType({"angr": MappingProxyType({
                "enabled": True, "executable": sys.executable,
                "timeout_seconds": 30, "version": "9.3.0"})}),
            "comparison": MappingProxyType({"entry_points": ()}),
            "regions": (MappingProxyType({"name": "text", "address": 0x4000,
                "offset": 0, "size": 6, "permissions": "rx"}),),
            "symbolic_checks": ()}))
    document = export_with_angr(profile, "reference", tmp_path / "analysis.json")
    assert document["analyzer"]["version"] == "9.3.0"
    assert any(function["address"] == 0x4000 for function in document["functions"])
    assert document["sections"][0]["sha256"] == hashlib.sha256(
        binary.read_bytes()).hexdigest().upper()


@pytest.mark.skipif(importlib.util.find_spec("angr") is None, reason="angr not installed")
def test_real_equivalence_uses_one_joint_symbolic_domain_and_honest_limits(tmp_path):
    module = _load_script(); import angr
    checksum = "8B5424048B4C240831C00202424975FAC3"
    different = "8B5424048B4C240831C00202424975FA40C3"
    def project(name, code):
        path = tmp_path / name; path.write_bytes(bytes.fromhex(code))
        return angr.Project(str(path), main_opts={"backend": "blob", "arch": "x86",
            "base_addr": 0x4000, "entry_point": 0x4000}, auto_load_libs=False)
    check = {"name": "checksum-equivalence", "function": "0x4000", "input_bytes": 8,
        "max_active_states": 4, "max_steps": 40, "registers": {}, "memory": [],
        "hooks": [], "assertions": [{"kind": "return-equivalent", "artifact": "rebuilt"}]}
    reference = project("reference.bin", checksum)
    assert module.run_equivalent_check(reference, project("same.bin", checksum), check)["status"] == "passed"
    first = module.run_equivalent_check(reference, project("different.bin", different), check)
    second = module.run_equivalent_check(reference, project("different2.bin", different), check)
    assert first["status"] == "failed"
    assert first["counterexample"] == second["counterexample"]
    assert first["counterexample"]["reference_return"] != first["counterexample"]["rebuilt_return"]
    assert len(first["counterexample"]["input_hex"]) == 16
    loop = project("loop.bin", "EBFE")
    assert module.run_equivalent_check(reference, loop, {**check, "max_steps": 2})["status"] == "limit-reached"
    errored = project("errored.bin", "0F0B")
    assert module.run_equivalent_check(reference, errored, check)["status"] == "unsupported"


@pytest.mark.skipif(importlib.util.find_spec("angr") is None, reason="angr not installed")
def test_real_host_runs_paired_equivalence_end_to_end(tmp_path):
    checksum = bytes.fromhex("8B5424048B4C240831C00202424975FAC3")
    reference = tmp_path / "reference.bin"; reference.write_bytes(checksum)
    rebuilt = tmp_path / "rebuilt.bin"; rebuilt.write_bytes(checksum)
    check = MappingProxyType({"name": "paired", "function": "0x4000", "input_bytes": 8,
        "max_active_states": 4, "max_steps": 40, "registers": MappingProxyType({}),
        "memory": (), "hooks": (), "assertions": (MappingProxyType({
            "kind": "return-equivalent", "artifact": "rebuilt"}),)})
    profile = SimpleNamespace(reference_identity=identify(reference), rebuilt_identity=identify(rebuilt),
        document=MappingProxyType({"architecture": "i386", "endianness": "little",
            "image_base": 0x4000, "analyzers": MappingProxyType({"angr": MappingProxyType({
                "enabled": True, "executable": sys.executable, "timeout_seconds": 30,
                "version": "9.3.0"})}), "comparison": MappingProxyType({"entry_points": ()}),
            "regions": (MappingProxyType({"name": "text", "address": 0x4000, "offset": 0,
                "size": len(checksum), "permissions": "rx"}),), "symbolic_checks": (check,)}))
    document = export_with_angr(profile, "reference", tmp_path / "paired.json")
    assert document["extensions"]["angr"]["symbolic_checks"][0]["status"] == "passed"


@pytest.mark.skipif(importlib.util.find_spec("angr") is None, reason="angr not installed")
def test_symbolic_accounting_reports_actual_steps_and_all_terminal_stashes(tmp_path):
    module = _load_script(); import angr
    def project(name, code):
        path = tmp_path / name; path.write_bytes(bytes.fromhex(code))
        return angr.Project(str(path), main_opts={"backend": "blob", "arch": "x86",
            "base_addr": 0x4000, "entry_point": 0x4000}, auto_load_libs=False)
    base = {"name": "account", "function": "0x4000", "input_bytes": 0,
        "max_active_states": 4, "max_steps": 20, "registers": {}, "memory": [], "hooks": []}
    early = module.run_symbolic_check(project("early.bin", "B807000000C3"), {**base,
        "assertions": [{"kind": "return-equals", "value": 7}]})
    assert early["status"] == "passed" and 0 < early["steps"] < 20
    multiple = project("multiple.bin", "8B4424048038007506B807000000C3B807000000C3")
    result = module.run_symbolic_check(multiple, {**base, "input_bytes": 1,
        "assertions": [{"kind": "return-equals", "value": 7}]})
    assert result["status"] == "passed" and result["terminal_states"] == 2
    unconstrained = project("unconstrained.bin", "8B442404FF20")
    result = module.run_symbolic_check(unconstrained, {**base, "input_bytes": 4,
        "assertions": [{"kind": "return-equals", "value": 0}]})
    assert result["status"] == "unsupported" and "unconstrained" in result["reason"]
    errored = module.run_symbolic_check(project("error.bin", "0F0B"), {**base,
        "assertions": [{"kind": "return-equals", "value": 0}]})
    assert errored["status"] == "unsupported" and "decode" in errored["reason"].lower()
    mixed = project("mixed.bin", "8B4424048038007506B807000000C3FF20")
    mixed_result = module.run_symbolic_check(mixed, {**base, "input_bytes": 4,
        "assertions": [{"kind": "return-equals", "value": 7}]})
    assert mixed_result["status"] == "unsupported" and "unconstrained" in mixed_result["reason"]


@pytest.mark.skipif(importlib.util.find_spec("angr") is None, reason="angr not installed")
def test_undeclared_symbolic_dependencies_never_prove(tmp_path):
    module = _load_script(); import angr
    def project(name, code):
        path = tmp_path / name; path.write_bytes(bytes.fromhex(code))
        return angr.Project(str(path), main_opts={"backend": "blob", "arch": "x86",
            "base_addr": 0x4000, "entry_point": 0x4000}, auto_load_libs=False)
    base = {"name": "declared", "function": "0x4000", "input_bytes": 0,
        "max_active_states": 4, "max_steps": 20, "registers": {}, "memory": [],
        "hooks": [], "assertions": [{"kind": "return-equals", "value": 7}]}
    missing_memory = module.run_symbolic_check(project("memory.bin", "A100900000C3"), base)
    assert missing_memory["status"] == "unsupported" and "undeclared" in missing_memory["reason"]
    explicit = module.run_symbolic_check(project("explicit.bin", "A100900000C3"),
        {**base, "memory": [{"address": 0x9000, "bytes": "07000000"}]})
    assert explicit["status"] == "passed"
    branch = module.run_symbolic_check(project("register.bin", "85C97506B807000000C3B807000000C3"), base)
    assert branch["status"] == "unsupported" and "undeclared" in branch["reason"]
    path_only = module.run_symbolic_check(project("path-only.bin", "85C97506B807000000C3B807000000C3"),
        {key: value for key, value in base.items() if key != "assertions"})
    assert path_only["status"] == "unsupported" and "undeclared" in path_only["reason"]
    constant = module.run_symbolic_check(project("constant2.bin", "B807000000C3"), base)
    assert constant["status"] == "passed"


@pytest.mark.skipif(importlib.util.find_spec("angr") is None, reason="angr not installed")
def test_hooks_replace_temporarily_restore_and_duplicates_reject(tmp_path):
    module = _load_script(); import angr
    path = tmp_path / "hook.bin"; path.write_bytes(bytes.fromhex("E8FB0F0000C3"))
    project = angr.Project(str(path), main_opts={"backend": "blob", "arch": "x86",
        "base_addr": 0x4000, "entry_point": 0x4000}, auto_load_libs=False)
    class Original(angr.SimProcedure):
        def run(self): return 3
    original = Original(); project.hook(0x5000, original)
    check = {"name": "hook", "function": "0x4000", "input_bytes": 0,
        "max_active_states": 4, "max_steps": 8, "registers": {}, "memory": [],
        "hooks": [{"address": 0x5000, "handler": "return-constant", "returns": 9}],
        "assertions": [{"kind": "return-equals", "value": 9}]}
    assert module.run_symbolic_check(project, check)["status"] == "passed"
    assert project.hooked_by(0x5000) is original
    restored = module.run_symbolic_check(project, {**check, "hooks": [],
        "assertions": [{"kind": "return-equals", "value": 3}]})
    assert restored["status"] == "passed"
    duplicate = {**check, "hooks": [check["hooks"][0], check["hooks"][0]]}
    assert module.run_symbolic_check(project, duplicate)["status"] == "unsupported"
    assert project.hooked_by(0x5000) is original
    limited = module.run_symbolic_check(project, {**check, "max_steps": 1})
    assert limited["status"] == "limit-reached" and project.hooked_by(0x5000) is original


def test_resource_limits_reject_before_allocation():
    module = _load_script()
    check = {"name": "huge", "function": "0x4000", "input_bytes": 1_000_000,
        "max_active_states": 4, "max_steps": 8, "registers": {}, "memory": [],
        "hooks": [], "assertions": [{"kind": "return-equals", "value": 0}]}
    result = module.run_symbolic_check(object(), check)
    assert result["status"] == "unsupported" and "limit" in result["reason"]
    with pytest.raises(ValueError, match="count resource limit"):
        module._validate_check_set([{"name": str(index), "input_bytes": 0,
            "max_active_states": 1, "max_steps": 1} for index in range(129)])


@pytest.mark.skipif(importlib.util.find_spec("angr") is None, reason="angr not installed")
def test_noncontiguous_fallback_maps_only_regions_and_cfg_excludes_gap(tmp_path):
    module = _load_script(); import angr
    binary = tmp_path / "regions.bin"; binary.write_bytes(b"\xC3\xC3")
    layout = {"image_base": 0x3000, "entry_points": [0x4000, 0x5000], "sections": [
        {"name": "one", "address": 0x4000, "offset": 0, "size": 1,
         "permissions": "rx", "initialized": True, "ordinal": 1},
        {"name": "two", "address": 0x5000, "offset": 1, "size": 1,
         "permissions": "rx", "initialized": True, "ordinal": 2}]}
    project = module.load_project(angr, binary, layout)
    assert project.loader.main_object.mapped_base == 0x3000
    assert 0x4000 in project.loader.memory
    assert 0x4800 not in project.loader.memory
    functions, _, _ = module.export_cfg(project, layout, {"symbols": [], "relocations": []})
    assert {item["address"] for item in functions} == {0x4000, 0x5000}


@pytest.mark.skipif(importlib.util.find_spec("angr") is None, reason="angr not installed")
def test_cfg_exports_control_and_data_references_with_instruction_indexes(tmp_path):
    module = _load_script(); import angr
    code = bytes.fromhex("E80B000000A100500000C39090909090C3")
    data = b"\x78\x56\x34\x12"
    binary = tmp_path / "refs.bin"; binary.write_bytes(code + data)
    stream, segments = module.build_region_stream(binary, {"sections": [
        {"address": 0x4000, "offset": 0, "size": len(code), "permissions": "rx", "initialized": True},
        {"address": 0x5000, "offset": len(code), "size": 4, "permissions": "r", "initialized": True}]})
    project = angr.Project(stream, main_opts={"backend": "blob", "arch": "x86",
        "base_addr": 0x4000, "entry_point": 0x4000, "segments": segments}, auto_load_libs=False)
    functions, cfg, references = module.export_cfg(project,
        {"entry_points": [0x4000], "sections": [
            {"address": 0x4000, "size": len(code), "permissions": "rx"},
            {"address": 0x5000, "size": 4, "permissions": "r"}]},
        {"symbols": [], "relocations": []})
    assert any(item["kind"] == "control-call" and item["target"] == 0x4010 for item in references)
    assert any(item["kind"] == "data-read" and item["target"] == 0x5000 for item in references)
    assert cfg["instruction_reference_indexes"]


@pytest.mark.skipif(importlib.util.find_spec("angr") is None, reason="angr not installed")
def test_callsite_uses_terminating_call_instruction_not_block_start(tmp_path):
    module = _load_script(); import angr
    # mov eax,1 at 0x4000; call 0x4010 at 0x4005
    code = bytes.fromhex("B801000000E806000000C39090909090C3")
    path = tmp_path / "callsite.bin"; path.write_bytes(code)
    project = angr.Project(str(path), main_opts={"backend": "blob", "arch": "x86",
        "base_addr": 0x4000, "entry_point": 0x4000}, auto_load_libs=False)
    functions, _, references = module.export_cfg(project,
        {"entry_points": [0x4000], "sections": [{"address": 0x4000,
            "size": len(code), "permissions": "rx"}]}, {"symbols": [], "relocations": []})
    call = next(item for item in functions[0]["calls"] if item["target"] == 0x4010)
    assert call["address"] == 0x4005
    assert not any(item["kind"] == "control-call" and item["address"] == 0x4000
                   for item in references)
