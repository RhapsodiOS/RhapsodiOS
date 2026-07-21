import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import stat
from types import MappingProxyType, SimpleNamespace

import pytest

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
        })})}
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

    def runner(argv, **kwargs):
        calls.append((argv, kwargs))
        arguments = _script_args(argv)
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
    expected = _analysis(identity)
    monkeypatch.setitem(sys.modules, "idc", SimpleNamespace(ARGV=[
        str(script), "--output", str(output), "--input", str(input_path),
        "--size", str(identity.size), "--sha256", identity.sha256,
    ]))
    monkeypatch.setattr(sys, "argv", [str(script)])
    monkeypatch.setattr(module, "collect_analysis", lambda *args: expected)

    assert module.main() == 0
    assert json.loads(output.read_text(encoding="utf-8")) == expected

    explicit_output = tmp_path / "explicit.json"
    sys.modules["idc"].ARGV = None
    assert module.main([
        "--output", str(explicit_output), "--input", str(input_path),
        "--size", str(identity.size), "--sha256", identity.sha256,
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

    class Block:
        start_ea = 0x1000
        end_ea = 0x1002

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
        ea = 0x3000
        strtype = 0

        def __str__(self):
            return "metadataOnly"

    class ObjcSegment:
        pass

    def enum_import_names(index, callback):
        callback(0x2000, "_printf", 1)
        return True

    class Fixup:
        def __init__(self, type_=4, off=0, displacement=0, external=False):
            self._type = type_
            self.off = off
            self.displacement = displacement
            self._external = external

        def get_type(self):
            return self._type

        def is_extdef(self):
            return self._external

        def has_base(self):
            return False

        def get_value(self, address):
            return 7 + address - 0x1000

    fixups = {
        0x1000: Fixup(off=0x2000, external=True),
        0x1001: Fixup(off=0x1000),
    }

    class EmptyFixup:
        pass

    def get_fixup(target, address):
        source = fixups[address]
        target.__dict__.update(source.__dict__)
        target.__class__ = Fixup
        return True

    modules = {
        "ida_auto": SimpleNamespace(auto_wait=lambda: True),
        "ida_bytes": SimpleNamespace(
            get_bytes=lambda address, size: b"\x90\xC3" if size == 2 else bytes([0x90 if address == 0x1000 else 0xC3]),
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
        "ida_gdl": SimpleNamespace(FlowChart=lambda function: [Block()]),
        "ida_ida": SimpleNamespace(
            inf_get_procname=lambda: "metapc",
            inf_is_32bit_exactly=lambda: True,
            inf_is_be=lambda: False,
        ),
        "ida_kernwin": SimpleNamespace(get_kernel_version=lambda: "9.1"),
        "ida_loader": SimpleNamespace(get_fileregion_offset=lambda address: address - 0x1000),
        "ida_name": SimpleNamespace(
            is_public_name=lambda address: address == 0x1000,
            get_name=lambda address: (
                "_printf" if address == 0x2000 else
                "callee" if address == 0x1001 else "start"
            ),
        ),
        "ida_nalt": SimpleNamespace(
            get_import_module_qty=lambda: 1,
            get_import_module_name=lambda index: "libSystem",
            enum_import_names=enum_import_names,
            retrieve_input_file_size=lambda: identity.size,
            retrieve_input_file_sha256=lambda: bytes.fromhex(identity.sha256),
        ),
        "ida_segment": SimpleNamespace(
            SEGPERM_READ=1, SEGPERM_WRITE=2, SEGPERM_EXEC=4,
            SEG_BSS=2,
            getseg=lambda address: (
                Segment() if 0x1000 <= address < 0x1002 else
                ObjcSegment() if address == 0x3000 else None
            ),
            get_segm_name=lambda segment: (
                "__objc_methname" if isinstance(segment, ObjcSegment) else "__text"
            ),
            get_segm_class=lambda segment: "BSS" if segment.type == 2 else "CODE",
        ),
        "idaapi": SimpleNamespace(BADADDR=0xFFFFFFFFFFFFFFFF),
        "ida_ua": SimpleNamespace(
            insn_t=type("Instruction", (), {}),
            decode_insn=lambda instruction, address: 1,
        ),
        "idautils": SimpleNamespace(
            Segments=lambda: [0x1000],
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
            Functions=lambda: [0x1000],
            FuncItems=lambda address: [0x1001, 0x1000],
            Strings=lambda: [String(), ObjcString()],
        ),
        "idc": SimpleNamespace(
            print_insn_mnem=lambda address: "call" if address == 0x1000 else "ret",
            print_operand=lambda address, index: "callee" if address == 0x1000 and index == 0 else "",
            generate_disasm_line=lambda address, flags: "unused disassembly",
        ),
    }

    first = module.collect_analysis(input_path, identity.size, identity.sha256, modules)
    second = module.collect_analysis(input_path, identity.size, identity.sha256, modules)

    validate_document("analysis-v1", first)
    validate_analysis_semantics(first)
    assert json.dumps(first, sort_keys=True) == json.dumps(second, sort_keys=True)
    assert [item["address"] for item in first["symbols"]] == [
        0x1000, 0x1000, 0x1001, 0x1001, 0x1001, 0x1001
    ]
    assert first["imports"] == [{"name": "libSystem:_printf", "address": 0x2000}]
    assert first["relocations"] == [
        {"address": 0x1000, "kind": "ida-off32-32", "target": "_printf", "addend": 7},
        {"address": 0x1001, "kind": "ida-off32-32", "target": "start", "addend": 8},
    ]
    assert first["functions"][0]["instructions"][0]["operands"] == "callee"
    assert first["functions"][0]["instructions"][0]["relocations"] == [0]
    assert first["functions"][0]["instructions"][1]["relocations"] == [1]
    assert first["functions"][0]["calls"][0]["target"] == 0x1001
    assert first["extensions"]["ida"]["selectors"] == [
        "doThing",
        "init",
        "metadataOnly",
        "play:volume:",
    ]

    fixups[0x1000]._type = modules["ida_fixup"].FIXUP_CUSTOM
    with pytest.raises(module.ExportError, match="unsupported fixup"):
        module.collect_analysis(input_path, identity.size, identity.sha256, modules)
    fixups[0x1000]._type = modules["ida_fixup"].FIXUP_OFF32

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
    modules["ida_bytes"].get_bytes = lambda address, size: (
        b"\x90\xC3" if address == 0x1000 and size == 2 else b"\x90"
    )
    with pytest.raises(module.ExportError, match="instruction bytes"):
        module.collect_analysis(input_path, identity.size, identity.sha256, modules)
    modules["idautils"].FuncItems = lambda address: [0x1001, 0x1000]
    modules["ida_bytes"].get_flags = lambda address: 1
    modules["ida_bytes"].get_item_size = lambda address: 1
    modules["ida_bytes"].get_bytes = lambda address, size: (
        b"\x90\xC3" if size == 2 else bytes([0x90 if address == 0x1000 else 0xC3])
    )

    logical_size = 64 * 1024 * 1024 + 3
    Segment.end_ea = Segment.start_ea + logical_size
    modules["ida_loader"].get_fileregion_offset = lambda address: -1
    byte_reads = []

    def instruction_bytes_only(address, size):
        byte_reads.append(size)
        assert size <= 2
        return bytes([0x90 if address == 0x1000 else 0xC3]) * size

    modules["ida_bytes"].get_bytes = instruction_bytes_only
    zero_fill = module.collect_analysis(input_path, identity.size, identity.sha256, modules)
    digest = hashlib.sha256()
    remaining = logical_size
    chunk = b"\0" * (1024 * 1024)
    while remaining:
        amount = min(remaining, len(chunk))
        digest.update(chunk[:amount])
        remaining -= amount
    assert zero_fill["sections"][0]["offset"] == 0
    assert zero_fill["sections"][0]["sha256"] == digest.hexdigest().upper()
    assert zero_fill["extensions"]["ida"]["zero_fill_sections"] == [
        {"address": 0x1000, "name": "__text", "size": logical_size}
    ]
    assert max(byte_reads) <= 2
    Segment.end_ea = 0x1002
    modules["ida_loader"].get_fileregion_offset = lambda address: address - 0x1000
    modules["ida_bytes"].get_bytes = lambda address, size: (
        b"\x90\xC3" if size == 2 else bytes([0x90 if address == 0x1000 else 0xC3])
    )

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
