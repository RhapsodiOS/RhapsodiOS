import hashlib
import json
from pathlib import Path
import threading
import time

import pytest

from binrecon.identity import identify
from binrecon.ledger import (
    LedgerError, LedgerLock, load_ledger, merge_evidence, new_ledger, transition,
    update_ledger, write_ledger,
)


def identities(tmp_path):
    reference = tmp_path / "reference.bin"; reference.write_bytes(b"reference")
    rebuilt = tmp_path / "rebuilt.bin"; rebuilt.write_bytes(b"rebuilt")
    return identify(reference), identify(rebuilt)


def entry(status="unexamined"):
    return {"address": 0x1000, "size": 12, "names": ["_probe"],
            "source_path": None, "source_line": None, "status": status,
            "analyzer_agreement": {"status": "agreed", "analyzers": ["IDA"], "reasons": []},
            "artifacts": [], "reason": None, "reviewer": None}


def test_transition_matrix_and_human_exception(tmp_path):
    reference, rebuilt = identities(tmp_path)
    document = new_ledger(reference, rebuilt, [entry()])
    for status in ("signature-confirmed", "control-flow-confirmed", "assembly-matched"):
        document = transition(document, 0x1000, status, reference, rebuilt)
        assert document["entries"][0]["status"] == status
    with pytest.raises(LedgerError, match="backward"):
        transition(document, 0x1000, "signature-confirmed", reference, rebuilt)
    reviewed = new_ledger(reference, rebuilt, [entry("signature-confirmed")])
    intentional = transition(reviewed, 0x1000, "intentional-mismatch", reference, rebuilt,
                             reason="hardware quirk", reviewer="pat")
    assert intentional["entries"][0]["reason"] == "hardware quirk"
    with pytest.raises(LedgerError, match="reason and reviewer"):
        transition(reviewed, 0x1000, "intentional-mismatch", reference, rebuilt)
    with pytest.raises(LedgerError, match="terminal"):
        transition(intentional, 0x1000, "assembly-matched", reference, rebuilt)


def test_semantics_reject_overlap_bool_and_source_incoherence(tmp_path):
    reference, rebuilt = identities(tmp_path)
    with pytest.raises(LedgerError, match="overlap"):
        new_ledger(reference, rebuilt, [entry(), {**entry(), "address": 0x1005}])
    for field in ("address", "size"):
        invalid = entry(); invalid[field] = True
        with pytest.raises(LedgerError, match=field): new_ledger(reference, rebuilt, [invalid])
    invalid = entry(); invalid["source_line"] = 3
    with pytest.raises(LedgerError, match="source"):
        new_ledger(reference, rebuilt, [invalid])


def test_load_binds_current_artifacts_and_atomic_write_detects_lost_update(tmp_path):
    reference, rebuilt = identities(tmp_path); path = tmp_path / "ledger.json"
    document = new_ledger(reference, rebuilt, [entry()])
    write_ledger(path, document, reference, rebuilt)
    loaded, snapshot = load_ledger(path, reference, rebuilt)
    path.write_text(json.dumps({**loaded, "entries": []}), encoding="utf-8")
    with pytest.raises(LedgerError, match="changed"):
        write_ledger(path, loaded, reference, rebuilt, expected_snapshot=snapshot)
    path.write_text(json.dumps(document), encoding="utf-8")
    wrong = tmp_path / "wrong.bin"; wrong.write_bytes(b"wrong")
    with pytest.raises(LedgerError, match="reference identity"):
        load_ledger(path, identify(wrong), rebuilt)


def test_merge_evidence_preserves_review_and_never_advances(tmp_path):
    reference, rebuilt = identities(tmp_path)
    reviewed = entry("control-flow-confirmed")
    reviewed.update(source_path="src/probe.c", source_line=41, reason=None, reviewer="pat")
    document = new_ledger(reference, rebuilt, [reviewed])
    consensus = {"input": {"sha256": reference.sha256}, "groups": [{
        "section": {"name": "__text", "occurrence": 0, "sha256": "A" * 64},
        "start": 0, "end": 12, "status": "agreed", "reasons": [],
        "aliases": ["probe", "_probe"], "claims": [{"analyzer": "IDA"}, {"analyzer": "angr"}],
    }]}
    artifacts = [{"kind": "consensus-reference", "path": "consensus/reference.json",
                  "sha256": hashlib.sha256(b"x").hexdigest().upper()}]
    merged = merge_evidence(document, reference, rebuilt, consensus, artifacts,
                            section_bases={("__text", 0): 0x1000})
    value = merged["entries"][0]
    assert value["status"] == "control-flow-confirmed"
    assert (value["source_path"], value["source_line"], value["reviewer"]) == ("src/probe.c", 41, "pat")
    assert value["names"] == ["_probe", "probe"]
    assert value["artifacts"] == artifacts


def test_rebuilt_change_rejects_reviewed_parity_evidence(tmp_path):
    reference, rebuilt = identities(tmp_path)
    document = new_ledger(reference, rebuilt, [entry("assembly-matched")])
    changed = tmp_path / "changed.bin"; changed.write_bytes(b"changed")
    with pytest.raises(LedgerError, match="rebuilt identity"):
        transition(document, 0x1000, "assembly-matched", reference, identify(changed))


def test_private_file_and_output_alias_defenses(tmp_path):
    reference, rebuilt = identities(tmp_path); document = new_ledger(reference, rebuilt, [entry()])
    path = tmp_path / "ledger.json"; write_ledger(path, document, reference, rebuilt)
    link = tmp_path / "hardlink.json"
    try: link.hardlink_to(path)
    except OSError: pytest.skip("hard links unavailable")
    with pytest.raises(LedgerError, match="private regular"):
        load_ledger(path, reference, rebuilt)
    with pytest.raises(LedgerError, match="protected input"):
        write_ledger(reference.path, document, reference, rebuilt)


def test_ledger_destination_symlink_leaf_is_rejected_without_touching_target(tmp_path, monkeypatch):
    reference, rebuilt = identities(tmp_path); document = new_ledger(reference, rebuilt, [entry()])
    target = tmp_path / "victim.json"; target.write_text("victim", encoding="utf-8")
    link = tmp_path / "ledger.json"
    try: link.symlink_to(target)
    except OSError:
        original_resolve, original_is_symlink = Path.resolve, Path.is_symlink
        monkeypatch.setattr(Path, "resolve", lambda self, *args, **kwargs:
            target if self == link else original_resolve(self, *args, **kwargs))
        monkeypatch.setattr(Path, "is_symlink", lambda self:
            self == link or original_is_symlink(self))
    with pytest.raises(LedgerError, match="symlink"):
        write_ledger(link, document, reference, rebuilt)
    assert target.read_text(encoding="utf-8") == "victim"


def disputed_consensus(reference, *, status="disputed"):
    section = {"name": "__text", "occurrence": 0, "sha256": "A" * 64}
    return {"input": {"sha256": reference.sha256}, "groups": [{
        "section": section, "start": 0, "end": 12, "status": status,
        "reasons": ["incompatible boundaries"], "aliases": ["left", "right"],
        "claims": [
            {"analyzer": "IDA", "range": {"section": section, "start": 0, "end": 12},
             "aliases": ["whole"], "kind": "code"},
            {"analyzer": "Ghidra", "range": {"section": section, "start": 0, "end": 5},
             "aliases": ["left"], "kind": "code"},
            {"analyzer": "Ghidra", "range": {"section": section, "start": 5, "end": 12},
             "aliases": ["right"], "kind": "code"},
        ],
    }]}


def test_disputed_consensus_creates_explicit_review_cluster_without_function_name(tmp_path):
    reference, rebuilt = identities(tmp_path); document = new_ledger(reference, rebuilt)
    merged = merge_evidence(document, reference, rebuilt, disputed_consensus(reference), [],
                            section_bases={("__text", 0): 4096})
    assert len(merged["entries"]) == 1
    cluster = merged["entries"][0]
    assert (cluster["address"], cluster["size"], cluster["names"], cluster["status"]) == (4096, 12, [], "unexamined")
    assert cluster["analyzer_agreement"]["kind"] == "disputed-cluster"
    assert [(claim["analyzer"], claim["start"], claim["end"], claim["aliases"])
            for claim in cluster["analyzer_agreement"]["claims"]] == [
        ("Ghidra", 0, 5, ["left"]), ("Ghidra", 5, 12, ["right"]),
        ("IDA", 0, 12, ["whole"])]
    assert merge_evidence(merged, reference, rebuilt, disputed_consensus(reference), [],
                          section_bases={("__text", 0): 4096}) == merged


def test_disputed_consensus_updates_every_overlap_without_erasing_human_review(tmp_path):
    reference, rebuilt = identities(tmp_path)
    first = entry("control-flow-confirmed")
    first.update(address=4096, size=5, names=["left"], source_path="src/pnp.c",
                 source_line=10, reviewer="pat")
    second = entry("intentional-mismatch")
    second.update(address=4101, size=7, names=["right"], source_path="src/pnp.c",
                  source_line=20, reason="hardware quirk", reviewer="pat")
    document = new_ledger(reference, rebuilt, [first, second])
    merged = merge_evidence(document, reference, rebuilt, disputed_consensus(reference), [],
                            section_bases={("__text", 0): 4096})
    assert len(merged["entries"]) == 2
    for before, after in zip(document["entries"], merged["entries"]):
        for field in ("status", "source_path", "source_line", "reason", "reviewer", "names"):
            assert after[field] == before[field]
        assert after["analyzer_agreement"]["status"] == "disputed"
        assert after["analyzer_agreement"]["kind"] == "function-overlap"
        assert len(after["analyzer_agreement"]["claims"]) == 3


def test_agreed_split_replaces_prior_disputed_cluster_safely(tmp_path):
    reference, rebuilt = identities(tmp_path); bases = {("__text", 0): 4096}
    clustered = merge_evidence(new_ledger(reference, rebuilt), reference, rebuilt,
        disputed_consensus(reference), [], section_bases=bases)
    section = disputed_consensus(reference)["groups"][0]["section"]
    groups = []
    for start, end, alias in ((0, 5, "left"), (5, 12, "right")):
        groups.append({"section": section, "start": start, "end": end, "status": "agreed",
            "reasons": [], "aliases": [alias], "claims": [{"analyzer": "IDA"}]})
    consensus = {"input": {"sha256": reference.sha256}, "groups": groups}
    replaced = merge_evidence(clustered, reference, rebuilt, consensus, [], section_bases=bases)
    assert [(item["address"], item["size"], item["names"], item["analyzer_agreement"]["status"])
            for item in replaced["entries"]] == [
        (4096, 5, ["left"], "agreed"), (4101, 7, ["right"], "agreed")]


def test_agreed_split_never_discards_human_review_of_disputed_cluster(tmp_path):
    reference, rebuilt = identities(tmp_path); bases = {("__text", 0): 4096}
    clustered = merge_evidence(new_ledger(reference, rebuilt), reference, rebuilt,
        disputed_consensus(reference), [], section_bases=bases)
    reviewed = transition(clustered, 4096, "signature-confirmed", reference, rebuilt,
                          reviewer="pat")
    section = disputed_consensus(reference)["groups"][0]["section"]
    agreed = {"input": {"sha256": reference.sha256}, "groups": [{
        "section": section, "start": 0, "end": 5, "status": "agreed", "reasons": [],
        "aliases": ["left"], "claims": [{"analyzer": "IDA"}]}]}
    with pytest.raises(LedgerError, match="conflicts"):
        merge_evidence(reviewed, reference, rebuilt, agreed, [], section_bases=bases)
    assert reviewed["entries"][0]["status"] == "signature-confirmed"


def test_ledger_update_serializes_two_writers_without_losing_reviewer(tmp_path):
    reference, rebuilt = identities(tmp_path); path = tmp_path / "ledger.json"
    write_ledger(path, new_ledger(reference, rebuilt, [entry()]), reference, rebuilt)
    first_inside = threading.Event(); release_first = threading.Event(); second_inside = threading.Event()
    errors = []
    def first_update(document):
        first_inside.set(); assert release_first.wait(5)
        return transition(document, 4096, "signature-confirmed", reference, rebuilt, reviewer="alice")
    def second_update(document):
        second_inside.set()
        return transition(document, 4096, "control-flow-confirmed", reference, rebuilt)
    def worker(callback):
        try: update_ledger(path, reference, rebuilt, callback, timeout=5)
        except BaseException as error: errors.append(error)
    first = threading.Thread(target=worker, args=(first_update,)); first.start()
    assert first_inside.wait(5)
    second = threading.Thread(target=worker, args=(second_update,)); second.start()
    time.sleep(0.15); assert not second_inside.is_set()
    release_first.set(); first.join(5); second.join(5)
    assert not errors and second_inside.is_set()
    final, _ = load_ledger(path, reference, rebuilt)
    assert final["entries"][0]["status"] == "control-flow-confirmed"
    assert final["entries"][0]["reviewer"] == "alice"


def test_ledger_lock_timeout_and_release_after_exception(tmp_path):
    path = tmp_path / "ledger.json"
    with LedgerLock(path, timeout=1):
        with pytest.raises(LedgerError, match="timed out"):
            with LedgerLock(path, timeout=0.05): pass
    with pytest.raises(RuntimeError, match="boom"):
        with LedgerLock(path, timeout=1): raise RuntimeError("boom")
    with LedgerLock(path, timeout=1): pass


def test_ledger_lock_durably_creates_each_missing_parent(tmp_path, monkeypatch):
    import binrecon.ledger as ledger_module
    calls = []; original = ledger_module._fsync_directory
    monkeypatch.setattr(ledger_module, "_fsync_directory",
                        lambda path: (calls.append(Path(path)), original(path))[1])
    parent = tmp_path / "first" / "second"
    with LedgerLock(parent / "owner.json", lock_path=parent / ".owner.lock"): pass
    assert calls[:2] == [tmp_path, tmp_path / "first"]


def test_ledger_lock_parent_fsync_failure_aborts_before_lock_file(tmp_path, monkeypatch):
    import binrecon.ledger as ledger_module
    parent = tmp_path / "new-parent"; lock = parent / ".owner.lock"
    monkeypatch.setattr(ledger_module, "_fsync_directory",
                        lambda path: (_ for _ in ()).throw(OSError("fsync denied")))
    with pytest.raises(OSError, match="fsync denied"):
        LedgerLock(parent / "owner.json", lock_path=lock)
    assert not lock.exists()


def test_ledger_lock_retry_replays_failed_parent_durability_barrier(tmp_path, monkeypatch):
    import binrecon.ledger as ledger_module
    parent = tmp_path / "retry-parent"; lock = parent / ".owner.lock"
    original = ledger_module._fsync_directory; calls = []; fail_once = True
    def flaky(path):
        nonlocal fail_once
        calls.append(Path(path))
        if fail_once:
            fail_once = False
            raise OSError("first barrier failed")
        return original(path)
    monkeypatch.setattr(ledger_module, "_fsync_directory", flaky)
    with pytest.raises(OSError, match="first barrier failed"):
        LedgerLock(parent / "owner.json", lock_path=lock)
    assert parent.is_dir() and not lock.exists()
    calls.clear()
    with LedgerLock(parent / "owner.json", lock_path=lock): pass
    assert calls and calls[0] == tmp_path


def test_fresh_state_resyncs_already_present_lock_directory_entry(tmp_path, monkeypatch):
    import binrecon.ledger as ledger_module
    parent = tmp_path / "survived-crash"; parent.mkdir()
    ledger_module._PENDING_DIRECTORY_BARRIERS.clear()
    calls = []; original = ledger_module._fsync_directory
    monkeypatch.setattr(ledger_module, "_fsync_directory",
                        lambda path: (calls.append(Path(path)), original(path))[1])
    with LedgerLock(parent / "owner.json", lock_path=parent / ".owner.lock"): pass
    assert calls and calls[0] == tmp_path


def test_merge_reconciles_missing_and_shifted_evidence_without_stale_artifacts(tmp_path):
    reference, rebuilt = identities(tmp_path); bases = {("__text", 0): 4096}
    section = disputed_consensus(reference)["groups"][0]["section"]
    agreed = {"input": {"sha256": reference.sha256}, "groups": [{
        "section": section, "start": 0, "end": 5, "status": "agreed", "reasons": [],
        "aliases": ["auto"], "claims": [{"analyzer": "IDA"}]}]}
    artifact = [{"kind": "consensus-reference", "path": "published/consensus-reference.json",
                 "sha256": "A" * 64}]
    generated = merge_evidence(new_ledger(reference, rebuilt), reference, rebuilt,
                               agreed, artifact, section_bases=bases)
    assert generated["entries"][0]["analyzer_agreement"]["generated"] is True
    empty = {"input": {"sha256": reference.sha256}, "groups": []}
    assert merge_evidence(generated, reference, rebuilt, empty, artifact,
                          section_bases=bases)["entries"] == []

    human = entry("control-flow-confirmed")
    human.update(address=4096, size=5, names=["human"], source_path="src/human.c",
                 source_line=9, reviewer="alice", artifacts=artifact)
    preserved = merge_evidence(new_ledger(reference, rebuilt, [human]), reference, rebuilt,
                               empty, artifact, section_bases=bases)["entries"][0]
    for field in ("address", "size", "names", "source_path", "source_line", "status", "reviewer"):
        assert preserved[field] == human[field]
    assert preserved["analyzer_agreement"] == {"status": "none", "analyzers": [],
                                                "reasons": ["no current evidence"],
                                                "kind": "no-current-evidence"}
    assert preserved["artifacts"] == []


def test_generated_agreed_entry_remains_generated_through_dispute_and_is_later_removed(tmp_path):
    reference, rebuilt = identities(tmp_path); bases = {("__text", 0): 4096}
    section = disputed_consensus(reference)["groups"][0]["section"]
    agreed = {"input": {"sha256": reference.sha256}, "groups": [{
        "section": section, "start": 0, "end": 5, "status": "agreed", "reasons": [],
        "aliases": ["auto"], "claims": [{"analyzer": "IDA"}]}]}
    generated = merge_evidence(new_ledger(reference, rebuilt), reference, rebuilt,
                               agreed, [], section_bases=bases)
    disputed = disputed_consensus(reference)
    disputed["groups"][0].update(start=0, end=5)
    disputed["groups"][0]["claims"] = [
        {**claim, "range": {**claim["range"], "end": min(claim["range"]["end"], 5)}}
        for claim in disputed["groups"][0]["claims"] if claim["range"]["start"] < 5]
    overlapped = merge_evidence(generated, reference, rebuilt, disputed, [], section_bases=bases)
    assert overlapped["entries"][0]["analyzer_agreement"]["generated"] is True
    empty = {"input": {"sha256": reference.sha256}, "groups": []}
    assert merge_evidence(overlapped, reference, rebuilt, empty, [], section_bases=bases)["entries"] == []
