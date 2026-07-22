import hashlib
import importlib.util
import json
from pathlib import Path
from types import MappingProxyType, SimpleNamespace
import subprocess
import sys

import pytest

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
        output = Path(argv[argv.index("--output") + 1])
        output.write_text(json.dumps(_analysis(identity)), encoding="utf-8")
        return subprocess.CompletedProcess(argv, 0, "stdout", "stderr")

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
    assert options == {"capture_output": True, "text": True, "timeout": 19,
                       "shell": False, "check": False}
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
        raise subprocess.TimeoutExpired(argv, 19, output="partial", stderr="late")
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
