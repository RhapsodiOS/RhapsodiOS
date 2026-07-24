import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import stat
from types import MappingProxyType, SimpleNamespace

import pytest

import binrecon.adapters.ida as ida_host
from binrecon.adapters.ida import IdaAdapterError, export_with_ida
from binrecon.identity import identify
from binrecon.schema import validate_document, validate_analysis_semantics


def _script_args(argv):
    command = next(arg for arg in argv if arg.startswith("-S"))[2:]
    # The adapter deliberately uses Python's Windows command-line quoting for
    # IDA's embedded script command. The expected vector gives tests a stable
    # way to recover its nonce-bearing output path without invoking a shell.
    marker = " --output "
    script, remainder = command.split(marker, 1)
    if remainder.startswith('"'):
        output, remainder = remainder[1:].split('"', 1)
        remainder = remainder.lstrip()
    else:
        output, remainder = remainder.split(" ", 1)
    assert remainder.startswith("--input ")
    input_part = remainder[len("--input "):]
    if input_part.startswith('"'):
        input_value, remainder = input_part[1:].split('"', 1)
        remainder = remainder.lstrip()
    else:
        input_value, remainder = input_part.split(" ", 1)
    mapping_marker = " --mapping "
    if mapping_marker in remainder:
        remainder, mapping_part = remainder.split(mapping_marker, 1)
        if mapping_part.startswith('"'):
            mapping_value, mapping_remainder = mapping_part[1:].split('"', 1)
        else:
            split = mapping_part.split(" ", 1)
            mapping_value = split[0]
            mapping_remainder = split[1] if len(split) == 2 else ""
        parts = [*remainder.split(), "--mapping", mapping_value,
                 *mapping_remainder.split()]
    else:
        parts = remainder.split()
    return [script.strip('"'), "--output", output, "--input", input_value, *parts]


def _analysis(identity, *, sha256=None):
    return {
        "schema_version": "analysis-v1",
        "input": {
            "path": str(identity.path),
            "size": identity.size,
            "sha256": sha256 or identity.sha256,
            "architecture": "i386",
            "endianness": "little",
        },
        "analyzer": {"name": "IDA", "version": "9.0", "invocation": "IDAPython"},
        "sections": [],
        "symbols": [],
        "relocations": [],
        "functions": [],
        "references": [],
        "imports": [],
        "strings": [],
    }


def _profile(tmp_path, input_path, *, executable=True, timeout=17):
    ida = tmp_path / "IDA Pro" / "idat.exe"
    ida.parent.mkdir()
    if executable:
        ida.write_bytes(b"fake")
    document = MappingProxyType(
        {"analyzers": MappingProxyType({"ida": MappingProxyType({
            "enabled": True,
            "executable": str(ida),
            "timeout_seconds": timeout,
            "version": "9.0",
        })}), "regions": ({
            "name": "image", "address": 0, "offset": 0,
            "size": input_path.stat().st_size, "permissions": "rx",
        },)}
    )
    return SimpleNamespace(
        document=document,
        reference_identity=identify(input_path),
        rebuilt_identity=identify(input_path),
    ), ida


def test_host_uses_argument_vector_temp_output_and_atomic_publication(tmp_path):
    input_path = tmp_path / "input image.i64"
    input_path.write_bytes(b"sample")
    profile, executable = _profile(tmp_path, input_path)
    destination = tmp_path / "published analysis.json"
    calls = []
    mappings = []

    def runner(argv, **kwargs):
        calls.append((argv, kwargs))
        arguments = _script_args(argv)
        mapping_path = Path(arguments[arguments.index("--mapping") + 1])
        mappings.append(json.loads(mapping_path.read_text(encoding="utf-8")))
        Path(arguments[arguments.index("--output") + 1]).write_text(
            json.dumps(_analysis(profile.reference_identity)), encoding="utf-8"
        )
        return SimpleNamespace(returncode=0, stdout="ida log\n", stderr="")

    result = export_with_ida(profile, "reference", destination, runner=runner)

    validate_document("analysis-v1", result)
    validate_analysis_semantics(result)
    assert destination.read_text(encoding="utf-8").endswith("\n")
    argv, options = calls[0]
    assert argv[0] == str(executable.resolve())
    assert argv[1:3] == ["-c", "-A"]
    assert argv[-1] == str(input_path.resolve())
    assert isinstance(argv, list)
    script_args = _script_args(argv)
    assert script_args[0].endswith("export_analysis.py")
    assert script_args[script_args.index("--input") + 1] == str(input_path.resolve())
    assert script_args[script_args.index("--sha256") + 1] == profile.reference_identity.sha256
    assert mappings == [{
        "schema_version": "ida-mapping-v1",
        "input": {"size": 6, "sha256": profile.reference_identity.sha256,
                  "architecture": "i386", "endianness": "little"},
        "runs": [{"address": 0, "offset": 0, "size": 6}],
    }]
    expected_script = subprocess.list2cmdline(script_args)
    assert argv == [
        str(executable.resolve()),
        "-c",
        "-A",
        next(arg for arg in argv if arg.startswith("-o")),
        next(arg for arg in argv if arg.startswith("-L")),
        "-S" + expected_script,
        str(input_path.resolve()),
    ]
    database = Path(next(arg for arg in argv if arg.startswith("-o"))[2:])
    native_log = Path(next(arg for arg in argv if arg.startswith("-L"))[2:])
    assert database.parent == native_log.parent
    assert not database.parent.exists()
    assert options["timeout"] == 17
    assert options["shell"] is False


def test_stale_temp_cannot_be_used_when_ida_does_not_write(tmp_path):
    input_path = tmp_path / "input.i64"
    input_path.write_bytes(b"sample")
    profile, _ = _profile(tmp_path, input_path)
    destination = tmp_path / "analysis.json"
    destination.write_text("known-good", encoding="utf-8")

    def runner(argv, **kwargs):
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    with pytest.raises(IdaAdapterError, match="did not produce"):
        export_with_ida(profile, "reference", destination, runner=runner)

    assert destination.read_text(encoding="utf-8") == "known-good"


def test_rejects_export_for_different_input_without_replacing_final(tmp_path):
    input_path = tmp_path / "input.i64"
    input_path.write_bytes(b"sample")
    profile, _ = _profile(tmp_path, input_path)
    destination = tmp_path / "analysis.json"
    destination.write_text("known-good", encoding="utf-8")

    def runner(argv, **kwargs):
        script_args = _script_args(argv)
        output = Path(script_args[script_args.index("--output") + 1])
        output.write_text(json.dumps(_analysis(profile.reference_identity, sha256="0" * 64)))
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    with pytest.raises(IdaAdapterError, match="identity"):
        export_with_ida(profile, "reference", destination, runner=runner)
    assert destination.read_text(encoding="utf-8") == "known-good"


@pytest.mark.parametrize("configuration", [None, "missing"])
def test_requires_configured_existing_executable(tmp_path, configuration):
    input_path = tmp_path / "input.i64"
    input_path.write_bytes(b"sample")
    profile, executable = _profile(tmp_path, input_path, executable=False)
    if configuration is None:
        profile.document = {
            "analyzers": {"ida": {"enabled": True, "timeout_seconds": 17}}
        }

    with pytest.raises(IdaAdapterError, match="executable"):
        export_with_ida(profile, "reference", tmp_path / "out.json")


def test_subprocess_failure_preserves_log_and_final(tmp_path):
    input_path = tmp_path / "input.i64"
    input_path.write_bytes(b"sample")
    profile, _ = _profile(tmp_path, input_path)
    destination = tmp_path / "analysis.json"
    destination.write_text("known-good", encoding="utf-8")

    def runner(argv, **kwargs):
        native_log = Path(next(arg for arg in argv if arg.startswith("-L"))[2:])
        native_log.write_bytes(b"native ida diagnostic\n")
        return SimpleNamespace(returncode=12, stdout="diagnostic", stderr="failure")

    with pytest.raises(IdaAdapterError, match="exit code 12"):
        export_with_ida(profile, "reference", destination, runner=runner)
    assert destination.read_text(encoding="utf-8") == "known-good"
    log = destination.with_suffix(destination.suffix + ".ida.log").read_text()
    assert "native ida diagnostic" in log
    assert "diagnostic" in log


def test_each_host_run_uses_unique_database_workspace_and_cleans_it(tmp_path):
    input_path = tmp_path / "input.i64"
    input_path.write_bytes(b"sample")
    profile, _ = _profile(tmp_path, input_path)
    workspaces = []

    def runner(argv, **kwargs):
        database = Path(next(arg for arg in argv if arg.startswith("-o"))[2:])
        native_log = Path(next(arg for arg in argv if arg.startswith("-L"))[2:])
        workspaces.append(database.parent)
        native_log.write_text("native", encoding="utf-8")
        arguments = _script_args(argv)
        Path(arguments[arguments.index("--output") + 1]).write_text(
            json.dumps(_analysis(profile.reference_identity)), encoding="utf-8"
        )
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    export_with_ida(profile, "reference", tmp_path / "one.json", runner=runner)
    export_with_ida(profile, "reference", tmp_path / "two.json", runner=runner)

    assert len(set(workspaces)) == 2
    assert all(not workspace.exists() for workspace in workspaces)


def test_workspace_cleanup_failure_does_not_replace_valid_destination(
    tmp_path, monkeypatch
):
    import binrecon.adapters.ida as ida_adapter

    input_path = tmp_path / "input.i64"
    input_path.write_bytes(b"sample")
    profile, _ = _profile(tmp_path, input_path)
    destination = tmp_path / "analysis.json"
    destination.write_text("known-good", encoding="utf-8")
    real_rmtree = ida_adapter.shutil.rmtree
    attempts = 0

    def fail_once(path):
        nonlocal attempts
        attempts += 1
        if attempts == 1:
            raise OSError("cleanup failed")
        real_rmtree(path)

    monkeypatch.setattr(ida_adapter.shutil, "rmtree", fail_once)

    def runner(argv, **kwargs):
        arguments = _script_args(argv)
        Path(arguments[arguments.index("--output") + 1]).write_text(
            json.dumps(_analysis(profile.reference_identity)), encoding="utf-8"
        )
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    with pytest.raises(OSError, match="cleanup failed"):
        export_with_ida(profile, "reference", destination, runner=runner)
    assert destination.read_text(encoding="utf-8") == "known-good"


def test_primary_ida_failure_survives_workspace_cleanup_failure(
    tmp_path, monkeypatch
):
    import binrecon.adapters.ida as ida_adapter

    input_path = tmp_path / "input.i64"
    input_path.write_bytes(b"sample")
    profile, _ = _profile(tmp_path, input_path)
    destination = tmp_path / "analysis.json"
    destination.write_text("known-good", encoding="utf-8")
    real_rmtree = ida_adapter.shutil.rmtree
    attempts = 0
    workspace = None

    def fail_once(path):
        nonlocal attempts
        attempts += 1
        if attempts == 1:
            raise OSError("cleanup collided")
        real_rmtree(path)

    monkeypatch.setattr(ida_adapter.shutil, "rmtree", fail_once)

    def runner(argv, **kwargs):
        nonlocal workspace
        workspace = Path(next(arg for arg in argv if arg.startswith("-o"))[2:]).parent
        return SimpleNamespace(returncode=23, stdout="primary failure", stderr="")

    with pytest.raises(IdaAdapterError, match="exit code 23") as captured:
        export_with_ida(profile, "reference", destination, runner=runner)
    assert any("cleanup collided" in note for note in captured.value.__notes__)
    assert "cleanup collided" in destination.with_suffix(".json.ida.log").read_text()
    assert destination.read_text(encoding="utf-8") == "known-good"
    assert workspace is not None and not workspace.exists()


def test_timeout_preserves_diagnostics_and_final(tmp_path):
    input_path = tmp_path / "input.i64"
    input_path.write_bytes(b"sample")
    profile, _ = _profile(tmp_path, input_path)
    destination = tmp_path / "analysis.json"
    destination.write_text("known-good", encoding="utf-8")

    def runner(argv, **kwargs):
        native_log = Path(next(arg for arg in argv if arg.startswith("-L"))[2:])
        native_log.write_bytes(b"native timeout\n")
        raise subprocess.TimeoutExpired(
            argv, kwargs["timeout"], output=b"partial", stderr=b"late"
        )

    with pytest.raises(IdaAdapterError, match="timed out"):
        export_with_ida(profile, "reference", destination, runner=runner)
    assert destination.read_text(encoding="utf-8") == "known-good"
    log = destination.with_suffix(".json.ida.log").read_text()
    assert "native timeout" in log
    assert "partial" in log
    assert "late" in log


@pytest.mark.parametrize(
    "payload",
    ["not json", json.dumps({"schema_version": "analysis-v1"})],
)
def test_malformed_or_schema_invalid_output_is_not_published(tmp_path, payload):
    input_path = tmp_path / "input.i64"
    input_path.write_bytes(b"sample")
    profile, _ = _profile(tmp_path, input_path)
    destination = tmp_path / "analysis.json"

    def runner(argv, **kwargs):
        arguments = _script_args(argv)
        Path(arguments[arguments.index("--output") + 1]).write_text(payload)
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    with pytest.raises(IdaAdapterError, match="output is invalid"):
        export_with_ida(profile, "reference", destination, runner=runner)
    assert not destination.exists()


def test_descriptor_snapshot_rejects_mutation():
    from binrecon.adapters.ida import _read_analysis_snapshot

    initial = SimpleNamespace(
        st_mode=stat.S_IFREG, st_nlink=1, st_size=2, st_dev=1, st_ino=2,
        st_mtime_ns=3, st_ctime_ns=4, st_file_attributes=0,
    )
    final = SimpleNamespace(**{**initial.__dict__, "st_mtime_ns": 5})
    stats = iter([initial, final])
    reads = iter([b"{}", b""])

    with pytest.raises(IdaAdapterError, match="changed while reading"):
        _read_analysis_snapshot(
            Path("ignored"), opener=lambda path, flags: 9,
            fstat=lambda descriptor: next(stats),
            reader=lambda descriptor, size: next(reads), closer=lambda descriptor: None,
        )


def test_hardlinked_analyzer_output_is_rejected(tmp_path):
    input_path = tmp_path / "input.i64"
    input_path.write_bytes(b"sample")
    profile, _ = _profile(tmp_path, input_path)
    destination = tmp_path / "analysis.json"

    def runner(argv, **kwargs):
        arguments = _script_args(argv)
        output = Path(arguments[arguments.index("--output") + 1])
        source = tmp_path / "attacker.json"
        source.write_text(json.dumps(_analysis(profile.reference_identity)))
        try:
            os.link(source, output)
        except OSError as error:
            pytest.skip(f"hard links unavailable: {error}")
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    with pytest.raises(IdaAdapterError, match="single-link"):
        export_with_ida(profile, "reference", destination, runner=runner)
    assert not destination.exists()


def test_oversize_analyzer_output_is_rejected(tmp_path, monkeypatch):
    import binrecon.adapters.ida as ida_adapter

    input_path = tmp_path / "input.i64"
    input_path.write_bytes(b"sample")
    profile, _ = _profile(tmp_path, input_path)
    destination = tmp_path / "analysis.json"
    monkeypatch.setattr(ida_adapter, "_MAX_ANALYSIS_BYTES", 128)

    def runner(argv, **kwargs):
        arguments = _script_args(argv)
        Path(arguments[arguments.index("--output") + 1]).write_bytes(b"x" * 129)
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    with pytest.raises(IdaAdapterError, match="maximum JSON size"):
        export_with_ida(profile, "reference", destination, runner=runner)
    assert not destination.exists()


def test_symlinked_analyzer_output_is_rejected(tmp_path):
    input_path = tmp_path / "input.i64"
    input_path.write_bytes(b"sample")
    profile, _ = _profile(tmp_path, input_path)
    destination = tmp_path / "analysis.json"

    def runner(argv, **kwargs):
        arguments = _script_args(argv)
        output = Path(arguments[arguments.index("--output") + 1])
        target = tmp_path / "attacker.json"
        target.write_text(json.dumps(_analysis(profile.reference_identity)))
        try:
            output.symlink_to(target)
        except OSError as error:
            pytest.skip(f"symlinks unavailable: {error}")
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    with pytest.raises(IdaAdapterError, match="safely|reparse|symlink"):
        export_with_ida(profile, "reference", destination, runner=runner)
    assert not destination.exists()


@pytest.mark.parametrize("alias", ["destination", "log"])
def test_output_paths_cannot_alias_analyzed_input(tmp_path, alias):
    if alias == "destination":
        input_path = tmp_path / "analysis.json"
        destination = input_path
    else:
        input_path = tmp_path / "analysis.json.ida.log"
        destination = tmp_path / "analysis.json"
    input_path.write_bytes(b"sample")
    profile, _ = _profile(tmp_path, input_path)

    with pytest.raises(IdaAdapterError, match="aliases analyzed input"):
        export_with_ida(profile, "reference", destination)
    assert input_path.read_bytes() == b"sample"


def test_exporter_module_is_import_safe_without_ida():
    import importlib.util

    script = Path(__file__).parents[1] / "adapters" / "ida" / "export_analysis.py"
    spec = importlib.util.spec_from_file_location("binrecon_test_ida_exporter", script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(module.main)


def test_exporter_uses_idc_argv_not_process_argv(tmp_path, monkeypatch):
    import importlib.util

    script = Path(__file__).parents[1] / "adapters" / "ida" / "export_analysis.py"
    spec = importlib.util.spec_from_file_location("binrecon_test_ida_exporter_argv", script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    input_path = tmp_path / "input with spaces.i64"
    input_path.write_bytes(b"sample")
    identity = identify(input_path)
    output = tmp_path / "output with spaces.json"
    mapping = tmp_path / "mapping with spaces.json"
    mapping.write_text("{}", encoding="utf-8")
    mapping_sha256 = hashlib.sha256(mapping.read_bytes()).hexdigest().upper()
    expected = _analysis(identity)
    monkeypatch.setitem(sys.modules, "idc", SimpleNamespace(ARGV=[
        str(script), "--output", str(output), "--input", str(input_path),
        "--size", str(identity.size), "--sha256", identity.sha256,
        "--mapping", str(mapping),
        "--mapping-sha256", mapping_sha256,
    ]))
    monkeypatch.setattr(sys, "argv", [str(script)])
    monkeypatch.setattr(module, "collect_analysis", lambda *args, **kwargs: expected)

    assert module.main() == 0
    assert json.loads(output.read_text(encoding="utf-8")) == expected

    explicit_output = tmp_path / "explicit.json"
    sys.modules["idc"].ARGV = None
    assert module.main([
        "--output", str(explicit_output), "--input", str(input_path),
        "--size", str(identity.size), "--sha256", identity.sha256,
        "--mapping", str(mapping),
        "--mapping-sha256", mapping_sha256,
    ]) == 0
    assert json.loads(explicit_output.read_text(encoding="utf-8")) == expected


def test_exporter_argument_failure_quits_ida_nonzero(monkeypatch):
    import importlib.util

    script = Path(__file__).parents[1] / "adapters" / "ida" / "export_analysis.py"
    spec = importlib.util.spec_from_file_location("binrecon_test_ida_exporter_exit", script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    exits = []
    monkeypatch.setitem(sys.modules, "idc", SimpleNamespace(ARGV=[str(script), "--bad-option"]))
    monkeypatch.setitem(sys.modules, "ida_pro", SimpleNamespace(qexit=exits.append))

    result = module.ida_entrypoint()

    assert result != 0
    assert exits == [result]


def test_exporter_collects_and_sorts_ida_metadata(tmp_path):
    import importlib.util

    script = Path(__file__).parents[1] / "adapters" / "ida" / "export_analysis.py"
    spec = importlib.util.spec_from_file_location("binrecon_test_ida_exporter_collect", script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    input_path = tmp_path / "fixture.i64"
    input_path.write_bytes(b"\x90\xC3")
    identity = identify(input_path)

    class Segment:
        start_ea = 0x1000
        end_ea = 0x1002
        perm = 5
        type = 2

    class BssSegment:
        start_ea = 0x2000
        end_ea = 0x2004
        perm = 3
        type = 9

    class ExternalSegment:
        start_ea = 0x3000
        end_ea = 0x3003
        perm = 1
        type = 1

    class Block:
        start_ea = 0x1000
        end_ea = 0x1002

        def succs(self):
            return []

    class ExternalBlock:
        start_ea = 0x1002
        end_ea = 0x1002

        def succs(self):
            return []

    class TailBlock:
        start_ea = 0x1003
        end_ea = 0x1005

        def succs(self):
            return []

    class LowerTailBlock:
        start_ea = 0x0FFD
        end_ea = 0x0FFF

        def succs(self):
            return []

    class Function:
        start_ea = 0x1000
        end_ea = 0x1002

    class String:
        ea = 0x1001
        strtype = 0

        def __str__(self):
            return "hello"

    class ObjcString:
        strtype = 0

        def __init__(self, address, value):
            self.ea = address
            self.value = value

        def __str__(self):
            return self.value

    class ObjcSegment:
        pass

    string_configuration = []

    class ConfiguredStrings:
        def __init__(self, default_setup=True):
            string_configuration.append(("constructor", default_setup))

        def setup(self, **options):
            string_configuration.append(("setup", options))

        def __iter__(self):
            return iter([
                String(),
                ObjcString(0x4000, "plugAndPlaySwitch"),
                ObjcString(0x4001, "init"),
                ObjcString(0x4002, "free"),
                ObjcString(0x4003, "coldBootToggled:"),
            ])

    def enum_import_names(index, callback):
        callback(0x2000, "_printf", 1)
        return True

    class Fixup:
        def __init__(
            self, type_=4, base=0, off=0, displacement=0,
            external=False, relative=False,
        ):
            self._type = type_
            self._base = base
            self.off = off
            self.displacement = displacement
            self._external = external
            self._relative = relative

        def get_type(self):
            return self._type

        def is_extdef(self):
            return self._external

        def has_base(self):
            return self._relative

        def get_base(self):
            return self._base

        def get_value(self, address):
            return 7 + address - 0x1000

    fixups = {
        0x1000: Fixup(base=0x1000, off=0x1000, external=True),
        0x1001: Fixup(base=0x800, off=0x800, relative=True),
    }

    class EmptyFixup:
        pass

    def get_fixup(target, address):
        source = fixups[address]
        target.__dict__.update(source.__dict__)
        target.__class__ = Fixup
        return True

    flowchart_flags = []
    mapping_calls = []

    def flowchart(function, flags=0):
        flowchart_flags.append(flags)
        blocks = [LowerTailBlock(), Block(), TailBlock()]
        return blocks if flags & 2 else blocks + [ExternalBlock()]

    modules = {
        "artifact_mapping": {
            "schema_version": "ida-mapping-v1",
            "input": {"size": identity.size, "sha256": identity.sha256,
                      "architecture": "i386", "endianness": "little"},
            "runs": [{"address": 0x1000, "offset": 0, "size": 2}],
        },
        "ida_auto": SimpleNamespace(auto_wait=lambda: True),
        "ida_bytes": SimpleNamespace(
            get_bytes=lambda address, size: b"\xCC" * size,
            get_item_size=lambda address: 1,
            get_flags=lambda address: 1,
            is_code=lambda flags: flags == 1,
        ),
        "ida_funcs": SimpleNamespace(get_func=lambda address: Function()),
        "ida_fixup": SimpleNamespace(
            FIXUP_OFF8=13, FIXUP_OFF16=1, FIXUP_SEG16=2, FIXUP_PTR16=3,
            FIXUP_OFF32=4, FIXUP_PTR32=5, FIXUP_HI8=6, FIXUP_HI16=7,
            FIXUP_LOW8=8, FIXUP_LOW16=9, FIXUP_OFF64=12,
            FIXUP_OFF8S=14, FIXUP_OFF16S=15, FIXUP_OFF32S=16,
            FIXUP_CUSTOM=0x8000,
            fixup_data_t=EmptyFixup,
            get_first_fixup_ea=lambda: min(fixups),
            get_next_fixup_ea=lambda address: next(
                (item for item in sorted(fixups) if item > address), 0xFFFFFFFFFFFFFFFF
            ),
            get_fixup=get_fixup,
            calc_fixup_size=lambda type_: 4,
        ),
        "ida_gdl": SimpleNamespace(FC_NOEXT=2, FlowChart=flowchart),
        "ida_ida": SimpleNamespace(
            inf_get_procname=lambda: "metapc",
            inf_is_32bit_exactly=lambda: True,
            inf_is_be=lambda: False,
        ),
        "ida_kernwin": SimpleNamespace(get_kernel_version=lambda: "9.1"),
        "ida_loader": SimpleNamespace(get_fileregion_offset=lambda address:
            mapping_calls.append(address) or -1),
        "ida_name": SimpleNamespace(
            is_public_name=lambda address: address == 0x1000,
            get_name=lambda address: (
                "_printf" if address == 0x2000 else
                "callee" if address == 0x1001 else "start"
            ),
        ),
        "ida_nalt": SimpleNamespace(
            STRTYPE_C=0,
            get_import_module_qty=lambda: 1,
            get_import_module_name=lambda index: "libSystem",
            enum_import_names=enum_import_names,
            retrieve_input_file_size=lambda: identity.size,
            retrieve_input_file_sha256=lambda: bytes.fromhex(identity.sha256),
        ),
        "ida_segment": SimpleNamespace(
            SEGPERM_READ=1, SEGPERM_WRITE=2, SEGPERM_EXEC=4,
            SEG_BSS=9, SEG_XTRN=1,
            getseg=lambda address: (
                Segment() if 0x1000 <= address < 0x1002 else
                BssSegment() if 0x2000 <= address < 0x2004 else
                ExternalSegment() if 0x3000 <= address < 0x3003 else
                ObjcSegment() if 0x4000 <= address <= 0x4003 else None
            ),
            get_segm_name=lambda segment: (
                "__meth_var_names" if isinstance(segment, ObjcSegment) else
                "__bss" if isinstance(segment, BssSegment) else
                "UNDEF" if isinstance(segment, ExternalSegment) else "__text"
            ),
            get_segm_class=lambda segment: (
                "BSS" if isinstance(segment, BssSegment) else
                "XTRN" if isinstance(segment, ExternalSegment) else "CODE"
            ),
        ),
        "idaapi": SimpleNamespace(BADADDR=0xFFFFFFFFFFFFFFFF),
        "ida_ua": SimpleNamespace(
            insn_t=type("Instruction", (), {}),
            decode_insn=lambda instruction, address: 1,
        ),
        "idautils": SimpleNamespace(
            Segments=lambda: [0x1000, 0x2000, 0x3000],
            Names=lambda: [
                (0x1001, "z_alias"),
                (0x1000, "start"),
                (0x1000, "_objc_msg:arg:"),
                (0x1001, "selRef_doThing"),
                (0x1001, "-[Card init]"),
                (0x1001, "+[Card play:volume:]"),
            ],
            Heads=lambda: [0x1001, 0x1000],
            CodeRefsFrom=lambda address, flow: [0x1001] if address == 0x1000 else [],
            DataRefsFrom=lambda address: [0x2000] if address == 0x1001 else [],
            Functions=lambda: [0x1000, 0x2000],
            FuncItems=lambda address: [0x1001, 0x1000],
            Strings=ConfiguredStrings,
        ),
        "idc": SimpleNamespace(
            print_insn_mnem=lambda address: "call" if address == 0x1000 else "ret",
            print_operand=lambda address, index: (
                "callee" if address == 0x1000 and index == 0 else ""
            ),
            generate_disasm_line=lambda address, flags: "unused disassembly",
        ),
    }

    first = module.collect_analysis(input_path, identity.size, identity.sha256, modules)
    second = module.collect_analysis(input_path, identity.size, identity.sha256, modules)

    assert len(first["functions"]) == 1
    assert flowchart_flags == [modules["ida_gdl"].FC_NOEXT] * 2
    assert mapping_calls == []
    assert first["functions"][0]["address"] == 0x0FFD
    assert first["functions"][0]["size"] == 8
    assert "start" in first["functions"][0]["names"]
    assert first["sections"][0]["sha256"] == identity.sha256
    assert [item["bytes"] for item in first["functions"][0]["instructions"]] == [
        "90", "C3",
    ]
    assert first["extensions"]["ida"]["sections"] == [
        {"name": "__text", "address": 0x1000, "offset": 0, "size": 2,
         "zero_fill": False, "initialized": True},
        {"name": "__bss", "address": 0x2000, "offset": 0, "size": 4,
         "zero_fill": True, "initialized": False},
        {"name": "UNDEF", "address": 0x3000, "offset": 0, "size": 3,
         "zero_fill": True, "initialized": False},
    ]
    validate_document("analysis-v1", first)
    validate_analysis_semantics(first)
    assert json.dumps(first, sort_keys=True) == json.dumps(second, sort_keys=True)
    assert [item["address"] for item in first["symbols"]] == [
        0x1000, 0x1000, 0x1001, 0x1001, 0x1001, 0x1001
    ]
    assert first["imports"] == [{"name": "libSystem:_printf", "address": 0x2000}]
    assert first["relocations"] == [
        {"address": 0x1000, "kind": "ida-off32-32", "target": "_printf", "addend": 7},
        {
            "address": 0x1001, "kind": "ida-off32-32-relative",
            "target": "start", "addend": 8,
        },
    ]
    assert first["functions"][0]["instructions"][0]["operands"] == "callee"
    assert first["functions"][0]["instructions"][0]["relocations"] == [0]
    assert first["functions"][0]["instructions"][1]["relocations"] == [1]
    assert first["functions"][0]["calls"][0]["target"] == 0x1001
    assert first["extensions"]["ida"]["selectors"] == [
        "coldBootToggled:",
        "doThing",
        "free",
        "init",
        "play:volume:",
        "plugAndPlaySwitch",
    ]
    assert string_configuration[:2] == [
        ("constructor", False),
        ("setup", {
            "strtypes": [0], "minlen": 1, "only_7bit": True,
            "ignore_instructions": True,
            "display_only_existing_strings": False,
        }),
    ]

    fixups[0x1000]._type = modules["ida_fixup"].FIXUP_CUSTOM
    with pytest.raises(module.ExportError, match="unsupported fixup"):
        module.collect_analysis(input_path, identity.size, identity.sha256, modules)
    fixups[0x1000]._type = modules["ida_fixup"].FIXUP_OFF32
    saved_get_base = Fixup.get_base
    Fixup.get_base = lambda self: (_ for _ in ()).throw(RuntimeError("no base"))
    with pytest.raises(module.ExportError, match="interpret fixup"):
        module.collect_analysis(input_path, identity.size, identity.sha256, modules)
    Fixup.get_base = saved_get_base

    modules["idautils"].FuncItems = lambda address: [0x1000, 0x1002, 0x1001]
    modules["ida_bytes"].get_flags = lambda address: 0 if address == 0x1002 else 1
    data_filtered = module.collect_analysis(input_path, identity.size, identity.sha256, modules)
    assert [item["address"] for item in data_filtered["functions"][0]["instructions"]] == [
        0x1000, 0x1001
    ]
    modules["ida_ua"].decode_insn = lambda instruction, address: 0 if address == 0x1001 else 1
    with pytest.raises(module.ExportError, match="decode instruction"):
        module.collect_analysis(input_path, identity.size, identity.sha256, modules)
    modules["ida_ua"].decode_insn = lambda instruction, address: 1
    modules["ida_bytes"].get_item_size = lambda address: 0 if address == 0x1001 else 1
    with pytest.raises(module.ExportError, match="instruction size"):
        module.collect_analysis(input_path, identity.size, identity.sha256, modules)
    modules["ida_bytes"].get_item_size = lambda address: 2 if address == 0x1001 else 1
    with pytest.raises(module.ExportError, match="instruction backing.*one artifact mapping run"):
        module.collect_analysis(input_path, identity.size, identity.sha256, modules)
    modules["idautils"].FuncItems = lambda address: [0x1001, 0x1000]
    modules["ida_bytes"].get_flags = lambda address: 1
    modules["ida_bytes"].get_item_size = lambda address: 1
    Segment.end_ea = 0x1003
    with pytest.raises(module.ExportError, match="segment backing.*one artifact mapping run"):
        module.collect_analysis(input_path, identity.size, identity.sha256, modules)
    Segment.end_ea = 0x1002

    modules["ida_nalt"].enum_import_names = lambda index, callback: -1
    with pytest.raises(module.ExportError, match="enumerate imports"):
        module.collect_analysis(input_path, identity.size, identity.sha256, modules)

    modules["ida_nalt"].enum_import_names = enum_import_names
    modules["ida_auto"].auto_wait = lambda: False
    with pytest.raises(module.ExportError, match="auto-analysis"):
        module.collect_analysis(input_path, identity.size, identity.sha256, modules)

    modules["ida_auto"].auto_wait = lambda: True
    modules["ida_nalt"].retrieve_input_file_size = lambda: identity.size + 1
    with pytest.raises(module.ExportError, match="database input size"):
        module.collect_analysis(input_path, identity.size, identity.sha256, modules)
    modules["ida_nalt"].retrieve_input_file_size = lambda: identity.size
    modules["ida_nalt"].retrieve_input_file_sha256 = lambda: b"\0" * 32
    with pytest.raises(module.ExportError, match="database input sha256"):
        module.collect_analysis(input_path, identity.size, identity.sha256, modules)
    modules["ida_nalt"].retrieve_input_file_sha256 = lambda: bytes.fromhex(identity.sha256)
    modules["ida_ida"].inf_get_procname = lambda: "arm"
    with pytest.raises(module.ExportError, match="processor"):
        module.collect_analysis(input_path, identity.size, identity.sha256, modules)
    modules["ida_ida"].inf_get_procname = lambda: "metapc"
    modules["ida_ida"].inf_is_32bit_exactly = lambda: False
    with pytest.raises(module.ExportError, match="32-bit"):
        module.collect_analysis(input_path, identity.size, identity.sha256, modules)
    modules["ida_ida"].inf_is_32bit_exactly = lambda: True
    modules["ida_ida"].inf_is_be = lambda: True
    with pytest.raises(module.ExportError, match="little-endian"):
        module.collect_analysis(input_path, identity.size, identity.sha256, modules)
    modules["ida_ida"].inf_is_be = lambda: False
    modules["ida_kernwin"].get_kernel_version = lambda: None
    with pytest.raises(module.ExportError, match="kernel version"):
        module.collect_analysis(input_path, identity.size, identity.sha256, modules)


@pytest.mark.parametrize(
    ("field", "value", "message"),
    [("name", "Ghidra", "analyzer name"), ("version", "9.1", "analyzer version")],
)
def test_rejects_wrong_analyzer_identity(tmp_path, field, value, message):
    input_path = tmp_path / "input.i64"
    input_path.write_bytes(b"sample")
    profile, _ = _profile(tmp_path, input_path)
    destination = tmp_path / "analysis.json"
    destination.write_text("known-good", encoding="utf-8")

    def runner(argv, **kwargs):
        arguments = _script_args(argv)
        document = _analysis(profile.reference_identity)
        document["analyzer"][field] = value
        Path(arguments[arguments.index("--output") + 1]).write_text(json.dumps(document))
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    with pytest.raises(IdaAdapterError, match=message):
        export_with_ida(profile, "reference", destination, runner=runner)
    assert destination.read_text(encoding="utf-8") == "known-good"


def test_exporter_hashes_external_input_in_stable_bounded_chunks():
    import importlib.util

    script = Path(__file__).parents[1] / "adapters" / "ida" / "export_analysis.py"
    spec = importlib.util.spec_from_file_location("binrecon_test_ida_hash", script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    size = 3 * 1024 * 1024 + 7
    initial = SimpleNamespace(
        st_mode=stat.S_IFREG, st_nlink=1, st_size=size, st_dev=1, st_ino=2,
        st_mtime_ns=3, st_ctime_ns=4,
    )
    stats = iter([initial, initial])
    remaining = size
    requests = []

    def reader(descriptor, amount):
        nonlocal remaining
        requests.append(amount)
        amount = min(amount, remaining)
        remaining -= amount
        return b"Z" * amount

    actual_size, actual_digest = module._file_identity(
        Path("ignored"), opener=lambda path, flags: 5,
        fstat=lambda descriptor: next(stats), reader=reader,
        closer=lambda descriptor: None,
    )
    digest = hashlib.sha256()
    digest.update(b"Z" * (1024 * 1024))
    digest.update(b"Z" * (1024 * 1024))
    digest.update(b"Z" * (1024 * 1024))
    digest.update(b"Z" * 7)
    assert (actual_size, actual_digest) == (size, digest.hexdigest().upper())
    assert max(requests) <= 1024 * 1024

    snapshot_stats = iter([initial, initial])
    snapshot_remaining = size

    def snapshot_reader(descriptor, amount):
        nonlocal snapshot_remaining
        amount = min(amount, snapshot_remaining)
        snapshot_remaining -= amount
        return b"Z" * amount

    snapshot, snapshot_digest = module._file_snapshot(
        Path("ignored"), expected_size=size, opener=lambda path, flags: 5,
        fstat=lambda descriptor: next(snapshot_stats), reader=snapshot_reader,
        closer=lambda descriptor: None,
    )
    assert isinstance(snapshot, memoryview) and snapshot.readonly
    assert len(snapshot) == size
    assert snapshot_digest == actual_digest

    pre_read_requests = []
    mismatch_stats = iter([initial])
    with pytest.raises(module.ExportError, match="size.*host request"):
        module._file_snapshot(
            Path("ignored"), expected_size=size + 1,
            opener=lambda path, flags: 5,
            fstat=lambda descriptor: next(mismatch_stats),
            reader=lambda descriptor, amount: pre_read_requests.append(amount) or b"",
            closer=lambda descriptor: None,
        )
    assert pre_read_requests == []

    opened = []
    with pytest.raises(module.ExportError, match="maximum artifact size"):
        module._file_snapshot(
            Path("ignored"), expected_size=module._MAX_ARTIFACT_BYTES + 1,
            opener=lambda path, flags: opened.append(path) or 5,
        )
    assert opened == []

    changed = SimpleNamespace(**{**initial.__dict__, "st_ctime_ns": 9})
    changed_stats = iter([initial, changed])
    with pytest.raises(module.ExportError, match="changed while hashing"):
        module._file_identity(
            Path("ignored"), opener=lambda path, flags: 5,
            fstat=lambda descriptor: next(changed_stats),
            reader=lambda descriptor, amount: b"",
            closer=lambda descriptor: None,
        )


def test_exporter_rejects_interior_artifact_mapping_discontinuity():
    import importlib.util

    script = Path(__file__).parents[1] / "adapters" / "ida" / "export_analysis.py"
    spec = importlib.util.spec_from_file_location("binrecon_test_ida_mapping", script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    discontinuous = [
        {"address": 0, "offset": 0, "size": 5},
        {"address": 5, "offset": 99, "size": 1},
        {"address": 6, "offset": 6, "size": 4},
    ]
    with pytest.raises(module.ExportError, match="one artifact mapping run"):
        module._hash_backed_segment(
            0, 10, memoryview(b"0123456789"), discontinuous,
        )

    digest = module._hash_backed_segment(
        0, 10_000, memoryview(b"Z" * 10_000),
        [{"address": 0, "offset": 0, "size": 10_000}],
    )
    assert digest == hashlib.sha256(b"Z" * 10_000).hexdigest().upper()


@pytest.mark.parametrize(
    ("mutation", "message"),
    [
        ("identity", "identity"),
        ("unsorted", "not canonical"),
        ("virtual-overlap", "virtual runs overlap"),
        ("file-overlap", "file runs overlap"),
        ("unknown-field", "malformed"),
    ],
)
def test_exporter_mapping_manifest_fails_closed(mutation, message):
    import importlib.util

    script = Path(__file__).parents[1] / "adapters" / "ida" / "export_analysis.py"
    spec = importlib.util.spec_from_file_location("binrecon_test_ida_manifest", script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    digest = hashlib.sha256(b"0123456789").hexdigest().upper()
    manifest = {"schema_version": "ida-mapping-v1",
                "input": {"size": 10, "sha256": digest,
                          "architecture": "i386", "endianness": "little"},
                "runs": [{"address": 0, "offset": 0, "size": 5},
                         {"address": 5, "offset": 5, "size": 5}]}
    if mutation == "identity": manifest["input"]["sha256"] = "0" * 64
    elif mutation == "unsorted": manifest["runs"].reverse()
    elif mutation == "virtual-overlap": manifest["runs"][1]["address"] = 4
    elif mutation == "file-overlap": manifest["runs"][1]["offset"] = 4
    else: manifest["extra"] = True

    with pytest.raises(module.ExportError, match=message):
        module._validate_mapping(manifest, 10, digest)


def test_exporter_mapping_manifest_rejects_gap_and_cross_run_evidence():
    import importlib.util

    script = Path(__file__).parents[1] / "adapters" / "ida" / "export_analysis.py"
    spec = importlib.util.spec_from_file_location("binrecon_test_ida_manifest_gap", script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    snapshot = memoryview(b"0123456789")
    runs = [{"address": 0, "offset": 0, "size": 4},
            {"address": 6, "offset": 6, "size": 4}]
    for address, size in ((4, 1), (3, 4)):
        with pytest.raises(module.ExportError, match="one artifact mapping run"):
            module._mapped_artifact_bytes(snapshot, address, size, runs, "instruction backing")


@pytest.mark.parametrize("failure", ["manifest", "write"])
def test_host_cleans_workspace_when_mapping_setup_fails(tmp_path, monkeypatch, failure):
    input_path = tmp_path / "input.i64"
    input_path.write_bytes(b"sample")
    profile, _ = _profile(tmp_path, input_path)
    if failure == "manifest":
        monkeypatch.setattr(ida_host, "_mapping_manifest",
                            lambda *args: (_ for _ in ()).throw(ValueError("bad mapping")))
    else:
        monkeypatch.setattr(ida_host, "_atomic_text",
                            lambda *args: (_ for _ in ()).throw(OSError("write failed")))
    with pytest.raises((ValueError, OSError)):
        export_with_ida(profile, "reference", tmp_path / "analysis.json")
    assert not list(tmp_path.glob(".analysis.json.ida-work-*"))


def test_exporter_mapping_reader_binds_private_file_and_host_hash(tmp_path):
    import importlib.util
    script = Path(__file__).parents[1] / "adapters" / "ida" / "export_analysis.py"
    spec = importlib.util.spec_from_file_location("binrecon_test_ida_secure_mapping", script)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    path = tmp_path / "mapping.json"; path.write_bytes(b"{}")
    with pytest.raises(module.ExportError, match="hash"):
        module._load_mapping(path, "0" * 64)
    alias = tmp_path / "alias.json"; os.link(path, alias)
    digest = hashlib.sha256(path.read_bytes()).hexdigest().upper()
    with pytest.raises(module.ExportError, match="private regular"):
        module._load_mapping(path, digest)
    link = tmp_path / "link.json"
    try:
        link.symlink_to(alias)
    except OSError as error:
        pytest.skip(f"symlinks unavailable: {error}")
    with pytest.raises(module.ExportError, match="open|private regular"):
        module._load_mapping(link, digest)


def test_exporter_mapping_reader_rejects_descriptor_mutation():
    import importlib.util
    script = Path(__file__).parents[1] / "adapters" / "ida" / "export_analysis.py"
    spec = importlib.util.spec_from_file_location("binrecon_test_ida_mapping_mutation", script)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    fields = dict(st_mode=stat.S_IFREG, st_nlink=1, st_dev=1, st_ino=2,
                  st_size=2, st_mtime_ns=3, st_ctime_ns=4, st_file_attributes=0)
    snapshots = iter([SimpleNamespace(**fields),
                      SimpleNamespace(**{**fields, "st_mtime_ns": 5})])
    with pytest.raises(module.ExportError, match="changed while reading"):
        module._load_mapping(Path("ignored"), hashlib.sha256(b"{}").hexdigest(),
                             opener=lambda *args: 7, fstat=lambda fd: next(snapshots),
                             reader=lambda fd, size: b"{}", closer=lambda fd: None)


def test_exporter_mapping_index_scales_and_cross_run_segment_fails():
    import importlib.util
    script = Path(__file__).parents[1] / "adapters" / "ida" / "export_analysis.py"
    spec = importlib.util.spec_from_file_location("binrecon_test_ida_mapping_index", script)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    raw = b"Z" * 4096
    digest = hashlib.sha256(raw).hexdigest().upper()
    manifest = {"schema_version": "ida-mapping-v1",
                "input": {"size": len(raw), "sha256": digest,
                          "architecture": "i386", "endianness": "little"},
                "runs": [{"address": i * 2, "offset": i, "size": 1}
                         for i in range(len(raw))]}
    runs = module._validate_mapping(manifest, len(raw), digest)
    assert len(runs.starts) == 4096
    for i in range(4096):
        assert bytes(module._mapped_artifact_bytes(memoryview(raw), i * 2, 1,
                                                   runs, "instruction")) == b"Z"
    split = module._MappingRuns([
        {"address": 0, "offset": 0, "size": module._HASH_CHUNK_SIZE},
        {"address": module._HASH_CHUNK_SIZE, "offset": module._HASH_CHUNK_SIZE,
         "size": 1},
    ])
    with pytest.raises(module.ExportError, match="one artifact mapping run"):
        module._hash_backed_segment(0, module._HASH_CHUNK_SIZE + 1,
                                    memoryview(b"Z" * (module._HASH_CHUNK_SIZE + 1)), split)
