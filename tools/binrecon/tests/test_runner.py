import hashlib
import json
from pathlib import Path
import threading
import time
from types import MappingProxyType, SimpleNamespace

import pytest

from binrecon.identity import identify
from binrecon.runner import RunnerError, run_analysis, validate_run_summary
import binrecon.runner as runner_module


def analysis(name, identity):
    digest = hashlib.sha256(b"code").hexdigest().upper()
    return {"schema_version": "analysis-v1",
            "input": {"path": str(identity.path), "size": identity.size,
                      "sha256": identity.sha256, "architecture": "i386", "endianness": "little"},
            "analyzer": {"name": name, "version": "1", "invocation": name},
            "sections": [{"name": "__text", "address": 0, "offset": 0, "size": identity.size,
                          "permissions": "r-x", "sha256": hashlib.sha256(identity.path.read_bytes()).hexdigest()}],
            "symbols": [], "relocations": [], "functions": []}


def profile(tmp_path, enabled=("ida", "ghidra", "angr"), rebuilt=True):
    ref = tmp_path / "ref.bin"; ref.write_bytes(b"code")
    reb = tmp_path / "reb.bin"; reb.write_bytes(b"code")
    analyzers = {name: {"enabled": name in enabled, "version": "1"}
                 for name in ("ida", "ghidra", "angr")}
    return SimpleNamespace(source_path=tmp_path / "profile.json", output_dir=tmp_path / "out", architecture="i386",
        reference_identity=identify(ref), rebuilt_identity=identify(reb) if rebuilt else None,
        reference=SimpleNamespace(path=ref), rebuilt=SimpleNamespace(path=reb) if rebuilt else None,
        document=MappingProxyType({"analyzers": analyzers,
            "comparison": {"acceptance": "exact-image", "ignore_metadata": ()}}))


def adapters(calls, fail=None):
    result = {}
    for key, analyzer_name in (("ida", "IDA"), ("ghidra", "Ghidra"), ("angr", "angr")):
        def export(profile, artifact, destination, *, _key=key, _name=analyzer_name):
            calls.append((_key, artifact))
            if (_key, artifact) == fail: raise RuntimeError("adapter failed")
            document = analysis(_name, getattr(profile, artifact + "_identity"))
            Path(destination).write_text(json.dumps(document), encoding="utf-8")
            return document
        result[key] = export
    return result


def consensus_document(*, padding_chunks=0):
    extensions = {f"padding-{index}": "x" * (1024 * 1024)
                  for index in range(padding_chunks)}
    return {"schema_version": "consensus-v1",
            "input": {"size": 0, "sha256": "A" * 64,
                      "architecture": "i386", "endianness": "little"},
            "expected_analyzers": ["IDA"],
            "analyzers": [{"name": "IDA", "version": "1", "invocation": "IDA",
                           "extensions": extensions}],
            "reference_claims": [{"analyzer": "IDA", "references": []}],
            "reference_consensus": {"status": "agreed", "reasons": []},
            "groups": []}


def consensus_summary(tmp_path, raw):
    published = tmp_path / "published"; published.mkdir(parents=True)
    path = published / "consensus-reference.json"; path.write_bytes(raw)
    record = {"path": "published/consensus-reference.json",
              "sha256": hashlib.sha256(raw).hexdigest().upper()}
    return {"analyzers": [], "consensus": {"reference": record, "rebuilt": None},
            "comparisons": []}, path


def test_runner_is_sequential_deterministic_and_conservative(tmp_path):
    subject = profile(tmp_path); calls = []
    summary = run_analysis(subject, adapters=adapters(calls), output_path=tmp_path / "summary.json")
    assert calls == [("ida", "reference"), ("ida", "rebuilt"),
                     ("ghidra", "reference"), ("ghidra", "rebuilt"),
                     ("angr", "reference"), ("angr", "rebuilt")]
    assert summary["complete"] is True and summary["acceptance"]["passed"] is True
    assert [item["analyzer"] for item in summary["comparisons"]] == ["IDA", "Ghidra", "angr"]
    validate_run_summary(summary)


def test_runner_staging_path_is_compatible_with_ghidra_project_locations(tmp_path):
    subject = profile(tmp_path, enabled=("ghidra",), rebuilt=False)
    observed = []

    def exporting(profile, artifact, destination):
        destination = Path(destination)
        workspace = destination.parent / "binrecon-ghidra-work-token"
        relative_components = workspace.relative_to(subject.output_dir).parts
        observed.append(relative_components)
        document = analysis("Ghidra", getattr(profile, artifact + "_identity"))
        destination.write_text(json.dumps(document), encoding="utf-8")

    run_analysis(subject, adapters={"ghidra": exporting},
                 output_path=tmp_path / "summary.json")

    assert observed
    assert all(not component.startswith(".")
               for components in observed for component in components)


def test_required_adapter_failure_publishes_only_failure_summary(tmp_path):
    subject = profile(tmp_path); calls = []; output = tmp_path / "summary.json"
    published = subject.output_dir / "published"; published.mkdir(parents=True)
    prior = published / "comparison-ida.json"; prior.write_text("prior", encoding="utf-8")
    with pytest.raises(RunnerError, match="adapter failed"):
        run_analysis(subject, adapters=adapters(calls, ("ghidra", "reference")), output_path=output)
    summary = json.loads(output.read_text())
    assert summary["complete"] is False and summary["acceptance"]["passed"] is False
    assert prior.read_text(encoding="utf-8") == "prior"


def test_rebuilt_absent_skips_comparisons_without_claiming_pass(tmp_path):
    subject = profile(tmp_path, enabled=("ida",), rebuilt=False); calls = []
    summary = run_analysis(subject, adapters=adapters(calls), output_path=tmp_path / "summary.json")
    assert calls == [("ida", "reference")]
    assert summary["rebuilt_sha256"] is None
    assert summary["comparisons"] == []
    assert summary["complete"] is True and summary["acceptance"]["passed"] is False


def test_rerun_is_byte_deterministic(tmp_path):
    subject = profile(tmp_path, enabled=("ida",)); output = tmp_path / "summary.json"
    first = run_analysis(subject, adapters=adapters([]), output_path=output)
    first_bytes = output.read_bytes()
    second = run_analysis(subject, adapters=adapters([]), output_path=output)
    assert first == second and output.read_bytes() == first_bytes


def test_stale_or_wrong_analyzer_output_fails_closed(tmp_path):
    subject = profile(tmp_path, enabled=("ida",)); output = tmp_path / "summary.json"
    def wrong(profile, artifact, destination):
        value = analysis("Ghidra", getattr(profile, artifact + "_identity"))
        Path(destination).write_text(json.dumps(value), encoding="utf-8")
    with pytest.raises(RunnerError, match="stale or invalid"):
        run_analysis(subject, adapters={"ida": wrong}, output_path=output)
    assert json.loads(output.read_text())["complete"] is False


def test_every_required_comparison_must_pass(tmp_path):
    subject = profile(tmp_path, enabled=("ida", "ghidra")); subject.rebuilt_identity.path.write_bytes(b"diff")
    subject.rebuilt_identity = identify(subject.rebuilt_identity.path)
    summary = run_analysis(subject, adapters=adapters([]), output_path=tmp_path / "summary.json")
    assert summary["complete"] is True
    assert summary["acceptance"]["passed"] is False
    assert all(item["passed"] is False for item in summary["comparisons"])


def test_summary_hardlink_alias_to_artifact_is_rejected(tmp_path):
    subject = profile(tmp_path, enabled=("ida",)); alias = tmp_path / "summary.json"
    try: alias.hardlink_to(subject.reference_identity.path)
    except OSError: pytest.skip("hard links unavailable")
    with pytest.raises(RunnerError, match="aliases protected input"):
        run_analysis(subject, adapters=adapters([]), output_path=alias)
    assert subject.reference_identity.path.read_bytes() == b"code"


def test_summary_symlink_leaf_is_rejected_without_touching_target(tmp_path, monkeypatch):
    subject = profile(tmp_path, enabled=("ida",)); target = tmp_path / "victim.json"
    target.write_text("victim", encoding="utf-8"); link = tmp_path / "summary.json"
    try: link.symlink_to(target)
    except OSError:
        original_resolve, original_is_symlink = Path.resolve, Path.is_symlink
        monkeypatch.setattr(Path, "resolve", lambda self, *args, **kwargs:
            target if self == link else original_resolve(self, *args, **kwargs))
        monkeypatch.setattr(Path, "is_symlink", lambda self:
            self == link or original_is_symlink(self))
    with pytest.raises(RunnerError, match="symlink"):
        run_analysis(subject, adapters=adapters([]), output_path=link)
    assert target.read_text(encoding="utf-8") == "victim"


def test_published_analysis_symlink_leaf_is_rejected_without_touching_target(tmp_path, monkeypatch):
    subject = profile(tmp_path, enabled=("ida",)); directory = subject.output_dir / "published"
    directory.mkdir(parents=True); target = tmp_path / "victim.json"; target.write_text("victim", encoding="utf-8")
    link = directory / "analysis-reference-ida.json"
    try: link.symlink_to(target)
    except OSError:
        original_resolve, original_is_symlink = Path.resolve, Path.is_symlink
        monkeypatch.setattr(Path, "resolve", lambda self, *args, **kwargs:
            target if self == link else original_resolve(self, *args, **kwargs))
        monkeypatch.setattr(Path, "is_symlink", lambda self:
            self == link or original_is_symlink(self))
    with pytest.raises(RunnerError, match="symlink"):
        run_analysis(subject, adapters=adapters([]), output_path=tmp_path / "summary.json")
    assert target.read_text(encoding="utf-8") == "victim"


def test_cleanup_failure_does_not_replace_primary_failure(tmp_path, monkeypatch):
    subject = profile(tmp_path, enabled=("ida",))
    def fail_cleanup(*args, **kwargs): raise OSError("cleanup denied")
    monkeypatch.setattr("binrecon.runner.shutil.rmtree", fail_cleanup)
    with pytest.raises(RunnerError, match="adapter failed") as captured:
        run_analysis(subject, adapters=adapters([], ("ida", "reference")),
                     output_path=tmp_path / "summary.json")
    assert any("cleanup denied" in note for note in getattr(captured.value, "__notes__", []))


def test_success_path_cleanup_failure_aborts_before_complete_summary(tmp_path, monkeypatch):
    subject = profile(tmp_path, enabled=("ida",)); output = tmp_path / "summary.json"
    def fail_cleanup(*args, **kwargs): raise OSError("cleanup denied")
    monkeypatch.setattr("binrecon.runner.shutil.rmtree", fail_cleanup)
    with pytest.raises(RunnerError, match="cleanup denied"):
        run_analysis(subject, adapters=adapters([]), output_path=output)
    summary = json.loads(output.read_text(encoding="utf-8"))
    assert summary["complete"] is False and summary["acceptance"]["passed"] is False


def test_publication_uses_single_validated_snapshot_when_adapter_file_is_replaced(tmp_path, monkeypatch):
    subject = profile(tmp_path, enabled=("ida",)); destinations = []
    base = adapters([])["ida"]
    def exporting(profile, artifact, destination):
        destinations.append(Path(destination)); return base(profile, artifact, destination)
    original_consensus = runner_module.build_consensus; replaced = False
    def replacing_consensus(documents, expected_analyzers=None):
        nonlocal replaced
        if not replaced:
            destinations[0].write_bytes(b'{"stale":true}\n'); replaced = True
        return original_consensus(documents, expected_analyzers=expected_analyzers)
    monkeypatch.setattr(runner_module, "build_consensus", replacing_consensus)
    summary = run_analysis(subject, adapters={"ida": exporting}, output_path=tmp_path / "summary.json")
    published = subject.output_dir / summary["analyzers"][0]["reference"]["path"]
    expected = json.dumps(analysis("IDA", subject.reference_identity), sort_keys=True,
                          separators=(",", ":"), allow_nan=False).encode() + b"\n"
    assert published.read_bytes() == expected
    assert summary["analyzers"][0]["reference"]["sha256"] == hashlib.sha256(expected).hexdigest().upper()


def _write_analysis_source(subject, path):
    path.write_text(json.dumps(analysis("IDA", subject.reference_identity)), encoding="utf-8")


def test_analysis_snapshot_rejects_hardlink_and_oversize_sources(tmp_path):
    subject = profile(tmp_path, enabled=("ida",)); source = tmp_path / "analysis.json"
    _write_analysis_source(subject, source)
    hardlink = tmp_path / "analysis-hardlink.json"
    try: hardlink.hardlink_to(source)
    except OSError: pytest.skip("hard links unavailable")
    with pytest.raises(RunnerError, match="private file"):
        runner_module._load_analysis(hardlink, subject, "reference", "IDA")
    hardlink.unlink(); source.write_bytes(b" " * (16 * 1024 * 1024 + 1))
    with pytest.raises(RunnerError, match="bounded private"):
        runner_module._load_analysis(source, subject, "reference", "IDA")


def test_published_consensus_has_a_dedicated_64_mib_read_budget(tmp_path):
    raw = (json.dumps(consensus_document(padding_chunks=17), sort_keys=True,
                      separators=(",", ":")) + "\n").encode("utf-8")
    assert 16 * 1024 * 1024 < len(raw) < 64 * 1024 * 1024
    summary, _ = consensus_summary(tmp_path, raw)

    runner_module._verify_published_summary(tmp_path, summary)


def test_published_analysis_remains_limited_to_16_mib(tmp_path):
    published = tmp_path / "published"; published.mkdir()
    raw = b" " * (16 * 1024 * 1024 + 1)
    path = published / "analysis-reference-ida.json"; path.write_bytes(raw)
    record = {"path": "published/analysis-reference-ida.json",
              "sha256": hashlib.sha256(raw).hexdigest().upper()}
    summary = {"analyzers": [{"reference": record, "rebuilt": None}],
               "consensus": {"reference": None, "rebuilt": None}, "comparisons": []}

    with pytest.raises(RunnerError, match="analysis output is not a bounded private file"):
        runner_module._verify_published_summary(tmp_path, summary)


def test_published_consensus_over_64_mib_is_rejected_before_reading(tmp_path):
    published = tmp_path / "published"; published.mkdir()
    path = published / "consensus-reference.json"
    with path.open("wb") as stream:
        stream.truncate(64 * 1024 * 1024 + 1)
    record = {"path": "published/consensus-reference.json", "sha256": "A" * 64}
    summary = {"analyzers": [], "consensus": {"reference": record, "rebuilt": None},
               "comparisons": []}

    with pytest.raises(RunnerError, match="consensus output is not a bounded private file"):
        runner_module._verify_published_summary(tmp_path, summary)


def test_published_consensus_keeps_private_regular_file_check(tmp_path):
    raw = (json.dumps(consensus_document(), sort_keys=True, separators=(",", ":")) +
           "\n").encode("utf-8")
    summary, path = consensus_summary(tmp_path, raw)
    alias = path.with_name("consensus-hardlink.json")
    try:
        alias.hardlink_to(path)
    except OSError:
        pytest.skip("hard links unavailable")

    with pytest.raises(RunnerError, match="consensus output is not a bounded private file"):
        runner_module._verify_published_summary(tmp_path, summary)


def test_published_consensus_keeps_hash_schema_and_descriptor_toctou_checks(tmp_path,
                                                                           monkeypatch):
    raw = (json.dumps(consensus_document(), sort_keys=True, separators=(",", ":")) +
           "\n").encode("utf-8")
    summary, path = consensus_summary(tmp_path, raw)
    summary["consensus"]["reference"]["sha256"] = "B" * 64
    with pytest.raises(RunnerError, match="published consensus hash disagrees"):
        runner_module._verify_published_summary(tmp_path, summary)

    invalid = b"{}\n"; path.write_bytes(invalid)
    summary["consensus"]["reference"]["sha256"] = hashlib.sha256(invalid).hexdigest().upper()
    with pytest.raises(ValueError, match="consensus object"):
        runner_module._verify_published_summary(tmp_path, summary)

    path.write_bytes(raw)
    summary["consensus"]["reference"]["sha256"] = hashlib.sha256(raw).hexdigest().upper()
    original_read = runner_module.os.read; changed = False
    def mutating_read(descriptor, count):
        nonlocal changed
        value = original_read(descriptor, count)
        if value and not changed:
            with path.open("ab") as stream: stream.write(b" ")
            changed = True
        return value
    monkeypatch.setattr(runner_module.os, "read", mutating_read)
    with pytest.raises(RunnerError, match="consensus output changed while reading"):
        runner_module._verify_published_summary(tmp_path, summary)


def test_analysis_snapshot_detects_mutation_during_descriptor_read(tmp_path, monkeypatch):
    subject = profile(tmp_path, enabled=("ida",)); source = tmp_path / "analysis.json"
    _write_analysis_source(subject, source); original_read = runner_module.os.read; changed = False
    def mutating_read(descriptor, count):
        nonlocal changed
        value = original_read(descriptor, count)
        if value and not changed:
            with source.open("ab") as stream: stream.write(b" ")
            changed = True
        return value
    monkeypatch.setattr(runner_module.os, "read", mutating_read)
    with pytest.raises(RunnerError, match="changed while reading"):
        runner_module._load_analysis(source, subject, "reference", "IDA")


def test_analysis_source_open_is_nonblocking_for_fifo_safety(tmp_path, monkeypatch):
    observed = {}
    monkeypatch.setattr(runner_module.os, "O_NONBLOCK", 0x800, raising=False)
    def checking_open(path, flags):
        observed["flags"] = flags
        assert flags & runner_module.os.O_NONBLOCK
        raise OSError("stop")
    monkeypatch.setattr(runner_module.os, "open", checking_open)
    with pytest.raises(OSError, match="stop"):
        runner_module._read_private_json_source(
            tmp_path / "fifo", max_bytes=16 * 1024 * 1024, label="analysis output"
        )
    assert observed


def test_published_directory_reparse_point_is_rejected(tmp_path, monkeypatch):
    subject = profile(tmp_path, enabled=("ida",)); published = subject.output_dir / "published"
    published.mkdir(parents=True); original_lstat = Path.lstat
    def reparse_lstat(self):
        value = original_lstat(self)
        if self == published:
            return SimpleNamespace(st_mode=value.st_mode, st_file_attributes=0x400)
        return value
    monkeypatch.setattr(Path, "lstat", reparse_lstat)
    with pytest.raises(RunnerError, match="reparse"):
        run_analysis(subject, adapters=adapters([]), output_path=tmp_path / "summary.json")


def test_summary_detects_leaf_inserted_during_atomic_publication(tmp_path, monkeypatch):
    path = tmp_path / "summary.json"; original = runner_module._destination_state; calls = 0
    def racing_state(candidate, protected, label):
        nonlocal calls
        calls += 1
        if calls == 2: candidate.write_text("racer", encoding="utf-8")
        return original(candidate, protected, label)
    monkeypatch.setattr(runner_module, "_destination_state", racing_state)
    with pytest.raises(RunnerError, match="changed before publication"):
        runner_module._atomic_summary(path, {"safe": True}, [])
    assert path.read_text(encoding="utf-8") == "racer"


def test_summary_and_ledger_alias_is_rejected_before_adapters_or_mutation(tmp_path):
    subject = profile(tmp_path, enabled=("ida",)); path = tmp_path / "same.json"; calls = []
    with pytest.raises(RunnerError, match="summary output aliases ledger"):
        run_analysis(subject, adapters=adapters(calls), output_path=path, ledger_path=path)
    assert calls == [] and not path.exists()


def test_existing_human_ledger_is_byte_identical_when_summary_aliases_it(tmp_path):
    from binrecon.ledger import new_ledger, write_ledger
    subject = profile(tmp_path, enabled=("ida",)); ledger = tmp_path / "ledger.json"
    human = {"address": 4096, "size": 4, "names": ["human"], "source_path": "src/human.c",
             "source_line": 7, "status": "signature-confirmed", "analyzer_agreement":
             {"status": "none", "analyzers": [], "reasons": []}, "artifacts": [],
             "reason": None, "reviewer": "alice"}
    write_ledger(ledger, new_ledger(subject.reference_identity, subject.rebuilt_identity, [human]),
                 subject.reference_identity, subject.rebuilt_identity)
    before = ledger.read_bytes(); calls = []
    with pytest.raises(RunnerError, match="summary output aliases ledger"):
        run_analysis(subject, adapters=adapters(calls), output_path=ledger, ledger_path=ledger)
    assert calls == [] and ledger.read_bytes() == before


def test_output_directory_lock_serializes_complete_runs(tmp_path):
    subject = profile(tmp_path, enabled=("ida",)); first_inside = threading.Event()
    release_first = threading.Event(); second_inside = threading.Event(); errors = []
    base = adapters([])["ida"]
    def first_adapter(profile, artifact, destination):
        if artifact == "reference": first_inside.set(); assert release_first.wait(5)
        return base(profile, artifact, destination)
    def second_adapter(profile, artifact, destination):
        second_inside.set(); return base(profile, artifact, destination)
    def worker(adapter):
        try: run_analysis(subject, adapters={"ida": adapter})
        except BaseException as error: errors.append(error)
    first = threading.Thread(target=worker, args=(first_adapter,)); first.start(); assert first_inside.wait(5)
    second = threading.Thread(target=worker, args=(second_adapter,)); second.start()
    time.sleep(0.15); assert not second_inside.is_set()
    release_first.set(); first.join(10); second.join(10)
    assert not errors and second_inside.is_set()


def test_shared_custom_summary_serializes_distinct_profile_output_directories(tmp_path):
    first_root = tmp_path / "first"; second_root = tmp_path / "second"
    first_root.mkdir(); second_root.mkdir()
    first_profile = profile(first_root, enabled=("ida",)); second_profile = profile(second_root, enabled=("ida",))
    shared = tmp_path / "shared-summary.json"; first_inside = threading.Event()
    release_first = threading.Event(); second_inside = threading.Event(); errors = []
    first_base, second_base = adapters([])["ida"], adapters([])["ida"]
    def first_adapter(profile, artifact, destination):
        if artifact == "reference": first_inside.set(); assert release_first.wait(5)
        return first_base(profile, artifact, destination)
    def second_adapter(profile, artifact, destination):
        second_inside.set(); return second_base(profile, artifact, destination)
    def worker(subject, adapter):
        try: run_analysis(subject, adapters={"ida": adapter}, output_path=shared)
        except BaseException as error: errors.append(error)
    first = threading.Thread(target=worker, args=(first_profile, first_adapter)); first.start()
    assert first_inside.wait(5)
    second = threading.Thread(target=worker, args=(second_profile, second_adapter)); second.start()
    time.sleep(0.15); assert not second_inside.is_set()
    release_first.set(); first.join(10); second.join(10)
    assert not errors and second_inside.is_set()
    validate_run_summary(json.loads(shared.read_text(encoding="utf-8")))


def test_new_output_and_custom_summary_lock_parents_are_durably_synced(tmp_path, monkeypatch):
    import binrecon.ledger as ledger_module
    subject_root = tmp_path / "subject"; subject_root.mkdir()
    subject = profile(subject_root, enabled=("ida",))
    custom = tmp_path / "external" / "nested" / "summary.json"
    calls = []; original = ledger_module._fsync_directory
    monkeypatch.setattr(ledger_module, "_fsync_directory",
                        lambda path: (calls.append(Path(path)), original(path))[1])
    run_analysis(subject, adapters=adapters([]), output_path=custom)
    assert subject_root in calls
    assert tmp_path in calls
    assert tmp_path / "external" in calls


@pytest.mark.parametrize(("field", "value"), [("architecture", "powerpc"), ("endianness", "big")])
def test_runner_rejects_analysis_metadata_that_disagrees_with_profile(tmp_path, field, value):
    subject = profile(tmp_path, enabled=("ida",))
    def wrong(profile, artifact, destination):
        document = analysis("IDA", getattr(profile, artifact + "_identity"))
        document["input"][field] = value
        Path(destination).write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(RunnerError, match=field):
        run_analysis(subject, adapters={"ida": wrong}, output_path=tmp_path / "summary.json")


def test_run_summary_rejects_unsafe_paths_and_impossible_coherence(tmp_path):
    subject = profile(tmp_path, enabled=("ida",))
    valid = run_analysis(subject, adapters=adapters([]), output_path=tmp_path / "summary.json")
    mutations = []
    unsafe = json.loads(json.dumps(valid)); unsafe["analyzers"][0]["reference"]["path"] = "../escape.json"; mutations.append(unsafe)
    drive = json.loads(json.dumps(valid)); drive["analyzers"][0]["reference"]["path"] = "published/C:/escape.json"; mutations.append(drive)
    colon = json.loads(json.dumps(valid)); colon["consensus"]["reference"]["path"] = "published/bad:name.json"; mutations.append(colon)
    incomplete_pass = json.loads(json.dumps(valid)); incomplete_pass.update(complete=False, diagnostic="failed"); mutations.append(incomplete_pass)
    missing_rebuilt = json.loads(json.dumps(valid)); missing_rebuilt["rebuilt_sha256"] = None; mutations.append(missing_rebuilt)
    bad_ledger = json.loads(json.dumps(valid)); bad_ledger["ledger"] = {"path": None, "updated": True}; mutations.append(bad_ledger)
    bogus_without_rebuilt = json.loads(json.dumps(valid))
    bogus_without_rebuilt["rebuilt_sha256"] = None
    bogus_without_rebuilt["analyzers"][0]["rebuilt"] = None
    bogus_without_rebuilt["consensus"]["rebuilt"] = None
    bogus_without_rebuilt["comparisons"][0]["analyzer"] = "bogus"
    mutations.append(bogus_without_rebuilt)
    requested_but_not_updated = json.loads(json.dumps(valid))
    requested_but_not_updated["ledger"] = {"path": str(tmp_path / "ledger.json"), "updated": False}
    mutations.append(requested_but_not_updated)
    for document in mutations:
        with pytest.raises(RunnerError): validate_run_summary(document)


def test_publication_fsyncs_each_replace_batch_and_summary(tmp_path, monkeypatch):
    subject = profile(tmp_path, enabled=("ida",)); calls = []
    original = runner_module._fsync_directory
    def recording(path): calls.append(Path(path)); return original(path)
    monkeypatch.setattr(runner_module, "_fsync_directory", recording)
    run_analysis(subject, adapters=adapters([]), output_path=tmp_path / "summary.json")
    assert len(calls) >= 7


def test_post_publication_corruption_prevents_complete_summary(tmp_path, monkeypatch):
    subject = profile(tmp_path, enabled=("ida",)); output = tmp_path / "summary.json"
    original = runner_module._publish_stage
    def corrupting(*args, **kwargs):
        result = original(*args, **kwargs)
        (subject.output_dir / "published" / "analysis-reference-ida.json").write_bytes(b"corrupt")
        return result
    monkeypatch.setattr(runner_module, "_publish_stage", corrupting)
    with pytest.raises(RunnerError, match="hash disagrees"):
        run_analysis(subject, adapters=adapters([]), output_path=output)
    assert json.loads(output.read_text(encoding="utf-8"))["complete"] is False


def test_run_lock_release_failure_does_not_turn_complete_summary_into_cli_failure(tmp_path, monkeypatch):
    import binrecon.ledger as ledger_module
    subject = profile(tmp_path, enabled=("ida",)); output = tmp_path / "summary.json"
    original = ledger_module._unlock
    def failing_unlock(descriptor):
        original(descriptor); raise OSError("unlock diagnostic")
    monkeypatch.setattr(ledger_module, "_unlock", failing_unlock)
    summary = run_analysis(subject, adapters=adapters([]), output_path=output)
    assert summary["complete"] is True
    assert json.loads(output.read_text(encoding="utf-8"))["complete"] is True


def test_posix_directory_fsync_open_failure_is_not_silently_ignored(tmp_path, monkeypatch):
    monkeypatch.setattr(runner_module.os, "name", "posix")
    monkeypatch.setattr(runner_module.os, "open", lambda *args, **kwargs: (_ for _ in ()).throw(OSError("open denied")))
    with pytest.raises(OSError, match="open denied"):
        runner_module._fsync_directory(tmp_path)


def test_new_published_directory_is_fsynced_into_output_directory_first(tmp_path, monkeypatch):
    subject = profile(tmp_path, enabled=("ida",)); calls = []
    original = runner_module._fsync_directory
    def recording(path): calls.append(Path(path)); return original(path)
    monkeypatch.setattr(runner_module, "_fsync_directory", recording)
    run_analysis(subject, adapters=adapters([]), output_path=tmp_path / "summary.json")
    output_dir = subject.output_dir.resolve()
    published = output_dir / "published"
    assert output_dir in calls and published in calls
    assert calls.index(output_dir) < calls.index(published)
