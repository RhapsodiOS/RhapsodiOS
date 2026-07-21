import json
from pathlib import Path
import subprocess
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
    assert argv[1] == "-A"
    assert argv[-1] == str(input_path.resolve())
    assert isinstance(argv, list)
    script_args = _script_args(argv)
    assert script_args[0].endswith("export_analysis.py")
    assert script_args[script_args.index("--input") + 1] == str(input_path.resolve())
    assert script_args[script_args.index("--sha256") + 1] == profile.reference_identity.sha256
    expected_script = subprocess.list2cmdline(script_args)
    assert argv == [
        str(executable.resolve()),
        "-A",
        "-S" + expected_script,
        str(input_path.resolve()),
    ]
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
        return SimpleNamespace(returncode=12, stdout="diagnostic", stderr="failure")

    with pytest.raises(IdaAdapterError, match="exit code 12"):
        export_with_ida(profile, "reference", destination, runner=runner)
    assert destination.read_text(encoding="utf-8") == "known-good"
    assert "diagnostic" in destination.with_suffix(destination.suffix + ".ida.log").read_text()


def test_timeout_preserves_diagnostics_and_final(tmp_path):
    input_path = tmp_path / "input.i64"
    input_path.write_bytes(b"sample")
    profile, _ = _profile(tmp_path, input_path)
    destination = tmp_path / "analysis.json"
    destination.write_text("known-good", encoding="utf-8")

    def runner(argv, **kwargs):
        raise subprocess.TimeoutExpired(
            argv, kwargs["timeout"], output=b"partial", stderr=b"late"
        )

    with pytest.raises(IdaAdapterError, match="timed out"):
        export_with_ida(profile, "reference", destination, runner=runner)
    assert destination.read_text(encoding="utf-8") == "known-good"
    assert destination.with_suffix(".json.ida.log").read_text() == "partiallate"


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


def test_exporter_module_is_import_safe_without_ida():
    import importlib.util

    script = Path(__file__).parents[1] / "adapters" / "ida" / "export_analysis.py"
    spec = importlib.util.spec_from_file_location("binrecon_test_ida_exporter", script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(module.main)


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

    def enum_import_names(index, callback):
        callback(0x2000, "_printf", 1)
        return True

    modules = {
        "ida_auto": SimpleNamespace(auto_wait=lambda: True),
        "ida_bytes": SimpleNamespace(
            get_bytes=lambda address, size: b"\x90\xC3" if size == 2 else bytes([0x90 if address == 0x1000 else 0xC3]),
            get_item_size=lambda address: 1,
        ),
        "ida_funcs": SimpleNamespace(get_func=lambda address: Function()),
        "ida_gdl": SimpleNamespace(FlowChart=lambda function: [Block()]),
        "ida_ida": SimpleNamespace(),
        "ida_kernwin": SimpleNamespace(get_kernel_version=lambda: "9.1"),
        "ida_loader": SimpleNamespace(get_fileregion_offset=lambda address: 0),
        "ida_name": SimpleNamespace(
            is_public_name=lambda address: address == 0x1000,
            get_name=lambda address: "callee" if address == 0x1001 else "start",
        ),
        "ida_nalt": SimpleNamespace(
            get_import_module_qty=lambda: 1,
            get_import_module_name=lambda index: "libSystem",
            enum_import_names=enum_import_names,
        ),
        "ida_segment": SimpleNamespace(
            SEGPERM_READ=1, SEGPERM_WRITE=2, SEGPERM_EXEC=4,
            getseg=lambda address: Segment() if 0x1000 <= address < 0x1002 else None,
            get_segm_name=lambda segment: "__text",
        ),
        "idaapi": SimpleNamespace(),
        "idautils": SimpleNamespace(
            Segments=lambda: [0x1000],
            Names=lambda: [
                (0x1001, "z_alias"),
                (0x1000, "start"),
                (0x1000, "_objc_msg:arg:"),
                (0x1001, "selRef_doThing"),
            ],
            Heads=lambda: [0x1001, 0x1000],
            CodeRefsFrom=lambda address, flow: [0x1001] if address == 0x1000 else [],
            DataRefsFrom=lambda address: [0x2000] if address == 0x1001 else [],
            Functions=lambda: [0x1000],
            FuncItems=lambda address: [0x1001, 0x1000],
            Strings=lambda: [String()],
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
    assert [item["address"] for item in first["symbols"]] == [0x1000, 0x1000, 0x1001, 0x1001]
    assert first["imports"] == [{"name": "libSystem:_printf", "address": 0x2000}]
    assert first["functions"][0]["instructions"][0]["operands"] == "callee"
    assert first["functions"][0]["calls"][0]["target"] == 0x1001
    assert first["extensions"]["ida"]["selectors"] == [
        "_objc_msg:arg:",
        "selRef_doThing",
    ]

    modules["ida_nalt"].enum_import_names = lambda index, callback: -1
    with pytest.raises(module.ExportError, match="enumerate imports"):
        module.collect_analysis(input_path, identity.size, identity.sha256, modules)

    modules["ida_nalt"].enum_import_names = enum_import_names
    modules["ida_auto"].auto_wait = lambda: False
    with pytest.raises(module.ExportError, match="auto-analysis"):
        module.collect_analysis(input_path, identity.size, identity.sha256, modules)
