import hashlib
import json
from pathlib import Path
from types import MappingProxyType, SimpleNamespace
import subprocess

import pytest

from binrecon.identity import identify
from binrecon.adapters.ghidra import GhidraAdapterError, _layout, export_with_ghidra


def _analysis(identity, version="12.1"):
    return {
        "schema_version": "analysis-v1",
        "input": {
            "path": str(identity.path),
            "size": identity.size,
            "sha256": identity.sha256,
            "architecture": "i386",
            "endianness": "little",
        },
        "analyzer": {"name": "Ghidra", "version": version, "invocation": "headless"},
        "sections": [], "symbols": [], "relocations": [], "functions": [],
        "references": [], "imports": [], "strings": [],
        "extensions": {"ghidra": {"language": "x86:LE:32:default"}},
    }


@pytest.fixture
def configured(tmp_path, monkeypatch):
    binary = tmp_path / "input with spaces.o"
    binary.write_bytes(b"legacy-mach-o")
    executable = tmp_path / "Ghidra 12.1" / "analyzeHeadless.bat"
    executable.parent.mkdir()
    executable.write_text("stub", encoding="ascii")
    java = tmp_path / "Java 21" / "bin" / "java.exe"
    java.parent.mkdir(parents=True)
    java.write_text("stub", encoding="ascii")
    monkeypatch.setenv("JAVA_HOME", str(java.parents[1]))
    identity = identify(binary)
    profile = SimpleNamespace(
        reference_identity=identity,
        rebuilt_identity=identity,
        document=MappingProxyType({
            "analyzers": MappingProxyType({"ghidra": MappingProxyType({
                "enabled": True, "executable": str(executable),
                "timeout_seconds": 17, "version": "12.1",
            })}),
            "image_base": 4096,
            "comparison": MappingProxyType({"entry_points": ("entry",)}),
            "regions": (),
        }),
    )
    return profile, identity, executable, java


def _successful_runner(identity, calls):
    def run(argv, **kwargs):
        calls.append((list(argv), dict(kwargs)))
        if Path(argv[0]).name.lower().startswith("java"):
            return subprocess.CompletedProcess(argv, 0, "", 'openjdk version "21.0.4"')
        output = Path(argv[argv.index("--output") + 1])
        output.write_text(json.dumps(_analysis(identity)), encoding="utf-8")
        return subprocess.CompletedProcess(argv, 0, "ok", "")
    return run


def test_builds_shell_free_native_command_and_publishes_canonical_json(configured, tmp_path):
    profile, identity, executable, _ = configured
    destination = tmp_path / "out" / "ghidra.json"
    calls = []
    document = export_with_ghidra(profile, "reference", destination,
                                  runner=_successful_runner(identity, calls))
    argv, options = calls[-1]
    assert argv[0] == str(executable.resolve())
    assert argv[3:7] == ["-import", str(identity.path), "-processor", "x86:LE:32:default"]
    assert "-postScript" in argv and "ExportAnalysis.java" in argv
    assert Path(argv[argv.index("-scriptPath") + 1]).name == "ghidra"
    assert argv[-1] == "-deleteProject"
    assert options == {"capture_output": True, "text": True, "timeout": 17,
                       "shell": False, "check": False}
    assert document == _analysis(identity)
    assert destination.read_text(encoding="utf-8") == json.dumps(
        document, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ) + "\n"
    assert not any(destination.parent.glob(".*ghidra-work-*"))


def test_deterministic_reruns_use_different_projects_but_identical_output(configured, tmp_path):
    profile, identity, _, _ = configured
    calls = []
    destination = tmp_path / "same.json"
    runner = _successful_runner(identity, calls)
    export_with_ghidra(profile, "reference", destination, runner=runner)
    first = destination.read_bytes()
    export_with_ghidra(profile, "reference", destination, runner=runner)
    assert destination.read_bytes() == first
    ghidra_calls = [argv for argv, _ in calls if not Path(argv[0]).name.lower().startswith("java")]
    assert ghidra_calls[0][1:3] != ghidra_calls[1][1:3]


def test_workspace_and_project_components_are_legal_and_not_destination_derived(configured, tmp_path):
    profile, identity, _, _ = configured
    destination = tmp_path / ".unsafe destination name.json"
    calls = []
    export_with_ghidra(profile, "reference", destination,
                       runner=_successful_runner(identity, calls))
    argv = calls[-1][0]
    workspace = Path(argv[1])
    assert workspace.name.startswith("binrecon-ghidra-work-")
    assert not workspace.name.startswith(".")
    assert "unsafe" not in workspace.name
    assert argv[2].startswith("native-")
    assert all(character.isalnum() or character == "-" for character in argv[2])


@pytest.mark.parametrize("bad_version", [None, "12.0", "12.1.1"])
def test_requires_exact_configured_ghidra_version(configured, tmp_path, bad_version):
    profile, _, _, _ = configured
    profile.document = {**profile.document, "analyzers": {"ghidra": {
        **profile.document["analyzers"]["ghidra"], "version": bad_version}}}
    with pytest.raises(GhidraAdapterError, match="Ghidra 12.1"):
        export_with_ghidra(profile, "reference", tmp_path / "result.json")


def test_rejects_java_other_than_21(configured, tmp_path):
    profile, _, _, _ = configured
    def runner(argv, **kwargs):
        return subprocess.CompletedProcess(argv, 0, "", 'openjdk version "17.0.1"')
    with pytest.raises(GhidraAdapterError, match="Java 21"):
        export_with_ghidra(profile, "reference", tmp_path / "result.json", runner=runner)


def test_missing_ghidra_and_java_fail_explicitly(configured, tmp_path, monkeypatch):
    profile, _, executable, _ = configured
    executable.unlink()
    with pytest.raises(GhidraAdapterError, match="does not exist"):
        export_with_ghidra(profile, "reference", tmp_path / "no-ghidra.json")
    executable.write_text("stub", encoding="ascii")
    monkeypatch.delenv("JAVA_HOME")
    monkeypatch.setattr("binrecon.adapters.ghidra.shutil.which", lambda name: None)
    with pytest.raises(GhidraAdapterError, match="Java 21 executable is missing"):
        export_with_ghidra(profile, "reference", tmp_path / "no-java.json")


def test_timeout_keeps_log_and_does_not_replace_destination(configured, tmp_path):
    profile, _, _, _ = configured
    destination = tmp_path / "result.json"
    destination.write_text("old", encoding="ascii")
    def runner(argv, **kwargs):
        if Path(argv[0]).name.lower().startswith("java"):
            return subprocess.CompletedProcess(argv, 0, "", 'openjdk version "21"')
        raise subprocess.TimeoutExpired(argv, 17, output="partial", stderr="stuck")
    with pytest.raises(GhidraAdapterError, match="timed out"):
        export_with_ghidra(profile, "reference", destination, runner=runner)
    assert destination.read_text(encoding="ascii") == "old"
    assert "partial" in destination.with_suffix(".json.ghidra.log").read_text(encoding="utf-8")


def test_process_start_error_keeps_diagnostic(configured, tmp_path):
    profile, _, _, _ = configured
    destination = tmp_path / "result.json"
    def runner(argv, **kwargs):
        if Path(argv[0]).name.lower().startswith("java"):
            return subprocess.CompletedProcess(argv, 0, "", 'openjdk version "21"')
        raise OSError("launch denied")
    with pytest.raises(GhidraAdapterError, match="could not start"):
        export_with_ghidra(profile, "reference", destination, runner=runner)
    assert "launch denied" in destination.with_suffix(".json.ghidra.log").read_text(encoding="utf-8")


def test_published_log_is_replaced_and_native_hardlink_is_not_followed(configured, tmp_path):
    profile, identity, _, _ = configured
    destination = tmp_path / "result.json"
    log = destination.with_suffix(".json.ghidra.log")
    log.write_text("PRIOR-SECRET\n" + "x" * (2 * 1024 * 1024), encoding="utf-8")
    attacker = tmp_path / "attacker.log"
    attacker.write_text("NATIVE-SECRET", encoding="utf-8")
    def runner(argv, **kwargs):
        if Path(argv[0]).name.lower().startswith("java"):
            return subprocess.CompletedProcess(argv, 0, "", 'openjdk version "21"')
        native = Path(argv[argv.index("-log") + 1])
        native.hardlink_to(attacker)
        output = Path(argv[argv.index("--output") + 1])
        output.write_text(json.dumps(_analysis(identity)), encoding="utf-8")
        return subprocess.CompletedProcess(argv, 0, "ok", "")
    export_with_ghidra(profile, "reference", destination, runner=runner)
    published = log.read_text(encoding="utf-8")
    assert "PRIOR-SECRET" not in published
    assert "NATIVE-SECRET" not in published
    assert "unsafe diagnostic omitted" in published


def test_native_loader_log_exact_rejection_retries_but_exporter_text_does_not(configured, tmp_path, monkeypatch):
    profile, identity, _, _ = configured
    monkeypatch.setattr("binrecon.adapters.ghidra._layout", lambda profile, identity: {
        "schema_version": "ghidra-layout-v1", "language": "x86:LE:32:default",
        "input": {"path": str(identity.path), "size": identity.size, "sha256": identity.sha256},
        "image_base": 0, "sections": [], "symbols": [], "relocations": [], "entry_points": [],
    })
    calls = 0
    def runner(argv, **kwargs):
        nonlocal calls
        if Path(argv[0]).name.lower().startswith("java"):
            return subprocess.CompletedProcess(argv, 0, "", 'openjdk version "21"')
        calls += 1
        native = Path(argv[argv.index("-log") + 1])
        if calls == 1:
            native.write_text("2026-01-01 00:00:00 ERROR No load spec found for import file (ProgramLoader)\n", encoding="utf-8")
            return subprocess.CompletedProcess(argv, 1, "", "")
        document = _analysis(identity)
        document["extensions"]["ghidra"].update({
            "fallback_sections": [], "fallback_symbols": [], "fallback_relocations": [],
            "fallback_backing": [], "fallback_relocation_status": [],
        })
        Path(argv[argv.index("--output") + 1]).write_text(json.dumps(document), encoding="utf-8")
        return subprocess.CompletedProcess(argv, 0, "", "")
    export_with_ghidra(profile, "reference", tmp_path / "retry.json", runner=runner)
    assert calls == 2

    calls = 0
    def exporter_failure(argv, **kwargs):
        nonlocal calls
        if Path(argv[0]).name.lower().startswith("java"):
            return subprocess.CompletedProcess(argv, 0, "", 'openjdk version "21"')
        calls += 1
        return subprocess.CompletedProcess(argv, 1, "", "REPORT SCRIPT ERROR: Mach-O unsupported (HeadlessAnalyzer)")
    with pytest.raises(GhidraAdapterError, match="exit code"):
        export_with_ghidra(profile, "reference", tmp_path / "no-retry.json", runner=exporter_failure)
    assert calls == 1


def test_missing_stale_malformed_and_wrong_identity_outputs_fail(configured, tmp_path):
    profile, identity, _, _ = configured
    for mode, match in (("missing", "fresh"), ("malformed", "malformed"),
                        ("identity", "identity"), ("version", "version")):
        destination = tmp_path / f"{mode}.json"
        def runner(argv, **kwargs):
            if Path(argv[0]).name.lower().startswith("java"):
                return subprocess.CompletedProcess(argv, 0, "", 'openjdk version "21"')
            output = Path(argv[argv.index("--output") + 1])
            if mode == "malformed": output.write_text("{", encoding="ascii")
            elif mode == "identity":
                doc = _analysis(identity); doc["input"]["sha256"] = "0" * 64
                output.write_text(json.dumps(doc), encoding="utf-8")
            elif mode == "version": output.write_text(json.dumps(_analysis(identity, "12.2")), encoding="utf-8")
            return subprocess.CompletedProcess(argv, 0, "", "")
        with pytest.raises(GhidraAdapterError, match=match):
            export_with_ghidra(profile, "reference", destination, runner=runner)
        assert not destination.exists()


def test_schema_invalid_and_hardlinked_outputs_are_untrusted(configured, tmp_path):
    profile, identity, _, _ = configured
    for mode, match in (("schema", "invalid"), ("hardlink", "private regular")):
        destination = tmp_path / f"{mode}.json"
        def runner(argv, **kwargs):
            if Path(argv[0]).name.lower().startswith("java"):
                return subprocess.CompletedProcess(argv, 0, "", 'openjdk version "21"')
            output = Path(argv[argv.index("--output") + 1])
            if mode == "schema":
                document = _analysis(identity); del document["sections"]
                output.write_text(json.dumps(document), encoding="utf-8")
            else:
                source = tmp_path / "attacker.json"
                source.write_text(json.dumps(_analysis(identity)), encoding="utf-8")
                output.hardlink_to(source)
            return subprocess.CompletedProcess(argv, 0, "", "")
        with pytest.raises(GhidraAdapterError, match=match):
            export_with_ghidra(profile, "reference", destination, runner=runner)


def test_retries_only_specific_unsupported_macho_failure(configured, tmp_path, monkeypatch):
    profile, identity, _, _ = configured
    macho = {
        "sections": [
            {"name": "__TEXT,__text", "address": 4096, "offset": 0,
             "size": 4, "permissions": "rx", "sha256": "0" * 64},
            {"name": "__DATA,__bss", "address": 8192, "offset": 1234,
             "size": 8, "permissions": "rw", "sha256": "0" * 64},
        ],
        "symbols": [
            {"name": "entry", "address": 4096, "binding": "external", "section": "__TEXT,__text"},
            {"name": "local_data", "address": 8192, "binding": "local", "section": "__DATA,__bss"},
        ],
        "relocations": [
            {"address": 4096, "kind": "i386-vanilla-32-pc-relative",
             "target": "entry", "addend": -4},
            {"address": 4100, "kind": "i386-vanilla-16-absolute",
             "target": "__DATA,__bss", "addend": 2},
        ],
        "extensions": {"macho": {
            "sections": [
            {"name": "__TEXT,__text", "address": 4096, "alignment_exponent": 2,
                 "ordinal": 1, "offset": 0, "size": 4, "alignment": 4, "flags": 0,
                 "type": 0, "zero_fill": False, "initialized": True},
                {"name": "__DATA,__bss", "address": 8192, "alignment_exponent": 3,
                 "ordinal": 2, "offset": 1234, "size": 8, "alignment": 8, "flags": 1,
                 "type": 1, "zero_fill": True, "initialized": False},
            ],
            "relocations": [
                {"address": 4096, "kind": "i386-vanilla-32-pc-relative", "target": "entry",
                 "addend": -4, "type": 0, "pc_relative": True, "width": 4,
                 "external": True, "section": "__TEXT,__text", "section_ordinal": 1,
                 "target_section_ordinal": None, "original_bytes": "FCFFFFFF"},
                {"address": 4100, "kind": "i386-vanilla-16-absolute", "target": "__DATA,__bss",
                 "addend": 2, "type": 0, "pc_relative": False, "width": 2,
                 "external": False, "section": "__TEXT,__text", "section_ordinal": 1,
                 "target_section_ordinal": 2, "original_bytes": "0200"},
            ],
        }},
    }
    monkeypatch.setattr("binrecon.adapters.ghidra.read_macho", lambda path: macho)
    commands = []
    def runner(argv, **kwargs):
        if Path(argv[0]).name.lower().startswith("java"):
            return subprocess.CompletedProcess(argv, 0, "", 'openjdk version "21"')
        commands.append(list(argv))
        if len(commands) == 1:
            Path(argv[argv.index("-log") + 1]).write_text(
                "ERROR No load spec found for import file (ProgramLoader)\n", encoding="utf-8"
            )
            return subprocess.CompletedProcess(argv, 1, "", "")
        layout = Path(argv[argv.index("--layout") + 1])
        layout_doc = json.loads(layout.read_text(encoding="utf-8"))
        assert layout_doc["sections"][0]["initialized"] is True
        assert layout_doc["sections"][1]["initialized"] is False
        assert layout_doc["sections"][1]["offset"] == 1234
        assert layout_doc["sections"][1]["flags"] == 1
        assert layout_doc["symbols"][1]["binding"] == "local"
        assert layout_doc["symbols"][1]["section"] == "__DATA,__bss"
        assert layout_doc["relocations"][0]["pc_relative"] is True
        assert layout_doc["relocations"][1]["external"] is False
        document = _analysis(identity)
        document["sections"] = macho["sections"]
        document["symbols"] = layout_doc["symbols"]
        document["relocations"] = [
            {key: item[key] for key in ("address", "kind", "target", "addend")}
            for item in layout_doc["relocations"]
        ]
        document["extensions"]["ghidra"].update({
            "fallback_sections": layout_doc["sections"],
            "fallback_symbols": layout_doc["symbols"],
            "fallback_relocations": layout_doc["relocations"],
            "fallback_backing": [
                {"ordinal": item["ordinal"], "initialized": item["initialized"],
                 "source_offset": item["offset"] if item["initialized"] and item["size"] else None}
                for item in layout_doc["sections"]
            ],
            "fallback_relocation_status": [
                {"index": index, "address": item["address"], "status": "SKIPPED",
                 "type": item["type"], "values": [item["addend"]],
                 "original_bytes": item["original_bytes"], "width": item["width"],
                 "reference_targets": []}
                for index, item in enumerate(layout_doc["relocations"])
            ],
        })
        Path(argv[argv.index("--output") + 1]).write_text(
            json.dumps(document), encoding="utf-8"
        )
        return subprocess.CompletedProcess(argv, 0, "", "")
    export_with_ghidra(profile, "reference", tmp_path / "fallback.json", runner=runner)
    assert len(commands) == 2
    fallback = commands[1]
    assert fallback.count("-import") == 1
    assert fallback[fallback.index("-loader") + 1] == "BinaryLoader"
    assert fallback.index("-preScript") < fallback.index("-postScript")
    assert fallback[fallback.index("-preScript") + 2] == "prepare"
    prepare_arguments = fallback[fallback.index("-preScript") + 2:fallback.index("-postScript")]
    assert "--layout" in prepare_arguments
    assert "--output" not in prepare_arguments


def test_layout_uses_ordinals_for_duplicate_names_addresses_and_zero_size(configured, monkeypatch):
    profile, identity, _, _ = configured
    profile.document = {**profile.document, "comparison": {"entry_points": ()}}
    core = [
        {"name": "duplicate", "address": 4096, "offset": 10, "size": 0,
         "permissions": "r", "sha256": hashlib.sha256(b"").hexdigest().upper()},
        {"name": "duplicate", "address": 4096, "offset": 20, "size": 4,
         "permissions": "rw", "sha256": "0" * 64},
    ]
    metadata = [
        {"ordinal": 1, "name": "duplicate", "address": 4096, "offset": 10, "size": 0,
         "alignment_exponent": 0, "alignment": 1, "flags": 0, "type": 0,
         "zero_fill": False, "initialized": True},
        {"ordinal": 2, "name": "duplicate", "address": 4096, "offset": 20, "size": 4,
         "alignment_exponent": 2, "alignment": 4, "flags": 1, "type": 1,
         "zero_fill": True, "initialized": False},
    ]
    monkeypatch.setattr("binrecon.adapters.ghidra.read_macho", lambda path: {
        "sections": core, "symbols": [], "extensions": {"macho": {
            "sections": metadata, "relocations": [],
        }},
    })
    layout = _layout(profile, identity)
    assert [(item["ordinal"], item["offset"], item["size"])
            for item in layout["sections"]] == [(1, 10, 0), (2, 20, 4)]

    profile.document = {**profile.document, "regions": (core[0], core[0])}
    with pytest.raises(GhidraAdapterError, match="ambiguous"):
        _layout(profile, identity)


@pytest.mark.parametrize("message", ["Decompiler failed", "schema output invalid", "random failure",
                                     "Mach-O loader failed parsing load command table"])
def test_does_not_retry_unrelated_errors(configured, tmp_path, message):
    profile, _, _, _ = configured
    calls = 0
    def runner(argv, **kwargs):
        nonlocal calls
        if Path(argv[0]).name.lower().startswith("java"):
            return subprocess.CompletedProcess(argv, 0, "", 'openjdk version "21"')
        calls += 1
        return subprocess.CompletedProcess(argv, 1, "", message)
    with pytest.raises(GhidraAdapterError, match="exit code"):
        export_with_ghidra(profile, "reference", tmp_path / "result.json", runner=runner)
    assert calls == 1


def test_rejects_destination_or_log_aliasing_input(configured):
    profile, identity, _, _ = configured
    with pytest.raises(GhidraAdapterError, match="aliases"):
        export_with_ghidra(profile, "reference", identity.path)
    log_destination = identity.path.with_suffix("")
    alias = log_destination.with_suffix(log_destination.suffix + ".ghidra.log")
    alias.hardlink_to(identity.path)
    with pytest.raises(GhidraAdapterError, match="aliases"):
        export_with_ghidra(profile, "reference", log_destination)


def test_rejects_destination_and_log_that_alias_each_other(configured, tmp_path):
    profile, _, _, _ = configured
    destination = tmp_path / "result.json"
    destination.write_text("old", encoding="ascii")
    destination.with_suffix(".json.ghidra.log").hardlink_to(destination)
    with pytest.raises(GhidraAdapterError, match="destination and log"):
        export_with_ghidra(profile, "reference", destination)


def test_java_exporter_has_deterministic_safe_contract():
    source = (Path(__file__).parents[1] / "adapters" / "ghidra" / "ExportAnalysis.java").read_text(encoding="utf-8")
    for required in ("Application.getApplicationVersion()", "MessageDigest.getInstance(\"SHA-256\")",
                     "DecompInterface", "PcodeOp", "BasicBlockModel", "ReferenceManager",
                     "MemoryBlock", "Collections.sort", "Files.move", "ATOMIC_MOVE",
                     "Double.isFinite", "\\\\b", "\\\\f", "\\\\u%04X",
                     "x86:LE:32:default", "prepare", "export"):
        assert required in source
    assert "String.format(Locale.ROOT" in source
    assert "import ghidra.program.database.mem.FileBytes;" in source


def test_java_exporter_traverses_program_wide_references_and_indexes_instructions():
    source = (Path(__file__).parents[1] / "adapters" / "ghidra" / "ExportAnalysis.java").read_text(encoding="utf-8")
    assert "getReferenceSourceIterator(currentProgram.getMemory(), true)" in source
    assert "referenceManager.getReferencesFrom(source)" in source
    assert "ReferenceExport" in source
    assert 'root.put("references", referenceExport.normalized)' in source
    assert 'ghidra.put("reference_metadata", referenceExport.metadata)' in source
    assert 'ghidra.put("instruction_reference_indexes"' in source
    for metadata in ("getOperandIndex()", "isPrimary()", "isExternalReference()",
                     "getSource().toString()", "target_space"):
        assert metadata in source
    assert "TreeMap<ReferenceKey" in source


def test_java_exporter_serializes_recovered_c_and_pcode():
    source = (Path(__file__).parents[1] / "adapters" / "ghidra" / "ExportAnalysis.java").read_text(encoding="utf-8")
    assert "result.getDecompiledFunction()" in source
    assert ".getC()" in source
    assert 'summary.put("c",' in source
    assert 'summary.put("pcode_operations",counts)' in source
    assert 'replace("\\r\\n", "\\n").replace("\\r", "\\n")' in source
    assert "result.isTimedOut()" in source
    assert "result.getErrorMessage()" in source
    assert "decompiler.dispose()" in source


def test_java_exporter_keeps_per_function_decompile_failures_and_fallback_metadata():
    source = (Path(__file__).parents[1] / "adapters" / "ghidra" / "ExportAnalysis.java").read_text(encoding="utf-8")
    assert 'summary.put("status","timeout")' in source
    assert 'summary.put("status","failed")' in source
    assert 'summary.put("status","missing-c")' in source
    assert "decompile failed at" not in source
    assert "MAX_DECOMPILED_C" in source and "MAX_DECOMPILE_MESSAGE" in source
    for field in ("fallback_sections", "fallback_symbols", "fallback_relocations"):
        assert field in source
    assert "SourceType.ANALYSIS" in source
    assert "getRelocationTable().add" in source
    assert "addMemoryReference" in source
    assert "fallback_relocation_status" in source


def test_java_argument_parser_is_explicit_and_closed():
    source = (Path(__file__).parents[1] / "adapters" / "ghidra" / "ExportAnalysis.java").read_text(encoding="utf-8")
    for required in ("PREPARE_OPTIONS", "EXPORT_OPTIONS", "unknown option",
                     "mode-incompatible option", "duplicate option", "missing value",
                     "invalid mode", "invalid --size", "invalid --sha256",
                     "boolean options are unsupported"):
        assert required in source
    assert "Set.of(" in source
