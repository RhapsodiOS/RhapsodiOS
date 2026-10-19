"""Actual ACK polling, compact boundary accounting, and narrow resource opt-in."""

import copy
import functools
import importlib.util
import json
import hashlib
import shutil
import subprocess
from pathlib import Path

import pytest


TESTS = Path(__file__).resolve().parent
REPO = TESTS.parents[6]
OUT = REPO / "tools/binrecon/out/adaptecu2scsi-ppc"


@functools.lru_cache(maxsize=1)
def runner():
    spec = importlib.util.spec_from_file_location("ack_runner", TESTS / "ppc_cases.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.load_image = functools.lru_cache(maxsize=1)(module.load_image)
    return module


def short_case(entry="SCSIhSendMessage", polls=3, compact=True):
    name = "task9-b7-send-1-None" if entry == "SCSIhSendMessage" else "task9-b7-msgout-0-0-0-0"
    case = copy.deepcopy(next(c for c in json.loads((TESTS / "task9-cases.json").read_text())["cases"]
                              if c["id"] == name))
    case["ack_exhaustion"] = True
    case["instruction_limit"] = 4000001
    if entry == "SCSIhHandleMsgOut":
        case["internal"] = [b for b in case["internal"] if b["entry"].startswith("OSM")]
        index, old = 3, 1
    else:
        index, old = 9, 2
    poll = {"register": "registers", "access": "read", "offset": 3, "size": 1, "value": 1}
    clear = dict(poll, value=0)
    case["external_outcomes"][index:index + old] = ([{"repeat": polls, "outcome": poll}] if compact else
                                                  [copy.deepcopy(poll) for _ in range(polls)]) + [clear]
    return case


def run(case):
    return runner().run_case(OUT / "reference/image.bin", case, json.loads((TESTS / "contracts.json").read_text()))


def expanded(trace):
    return [event for item in trace for event in ([item["event"]] * item["repeat"] if "repeat" in item else [item])]


@pytest.mark.parametrize("entry", ["SCSIhSendMessage", "SCSIhHandleMsgOut"])
def test_ack_compact_matches_actual_short_path(entry):
    compact = run(short_case(entry))
    flat = short_case(entry, compact=False)
    del flat["ack_exhaustion"]
    flat["instruction_limit"] = 1000000
    ordinary = run(flat)
    assert expanded(compact["observations"]["trace"]) == ordinary["observations"]["trace"]
    assert compact["observations"]["memory"] == ordinary["observations"]["memory"]
    assert compact["instructions"] == ordinary["instructions"] == (487 if entry == "SCSIhSendMessage" else 214)
    assert compact["ack_poll"] == {"reads": 4, "exit": "ack-clear"}


@pytest.mark.parametrize("change, message", [
    ("entry", "ACK exhaustion opt-in"),
    ("limit", "ACK exhaustion opt-in"),
    ("bool_limit", "ACK exhaustion opt-in"),
    ("internal", "ACK exhaustion opt-in"),
    ("count", "ACK exhaustion opt-in"),
    ("repeat_zero", "repeated MMIO"),
    ("repeat_over", "repeated MMIO"),
    ("repeat_bool", "repeated MMIO"),
    ("repeat_write", "repeated MMIO"),
    ("repeat_wrong_register", "repeated MMIO"),
    ("repeat_wrong_width", "repeated MMIO"),
])
def test_ack_rejects_unreviewed_allowance_and_repeat(change, message):
    case = short_case()
    if change == "entry":
        case["entry"] = "SCSIhReceiveMessage"
    elif change == "limit":
        case["instruction_limit"] = 240000001
    elif change == "bool_limit":
        case["instruction_limit"] = True
    elif change == "internal":
        case["internal"].append({"entry": "SCSIhBadSeq", "size": 4})
    elif change == "count":
        case["arguments"][-1] = 4
    elif change.startswith("repeat_"):
        item = case["external_outcomes"][9]
        if change in ("repeat_zero", "repeat_over", "repeat_bool"):
            item["repeat"] = {"repeat_zero": 0, "repeat_over": 8388609, "repeat_bool": True}[change]
        elif change == "repeat_write":
            item["outcome"]["access"] = "write"
        elif change == "repeat_wrong_register":
            item["outcome"]["offset"] = 6
        else:
            item["outcome"]["size"] = 2
    with pytest.raises(ValueError, match=message):
        run(case)


def test_ack_repeat_requires_opt_in_and_exact_consumption():
    case = short_case()
    del case["ack_exhaustion"]
    case["instruction_limit"] = 1000000
    with pytest.raises(ValueError, match="repeated MMIO"):
        run(case)
    case = short_case()
    case["external_outcomes"].append(copy.deepcopy(case["external_outcomes"][9]))
    with pytest.raises(ValueError, match="unused scripted external outcome"):
        run(case)


def test_ack_ordinary_instruction_cap_remains_fatal():
    case = short_case(compact=False)
    del case["ack_exhaustion"]
    with pytest.raises(ValueError, match="instruction limit must be in 1..4000000"):
        run(case)
    case["instruction_limit"] = 20
    with pytest.raises(ValueError, match="instruction limit exhausted"):
        run(case)


def test_ack_cached_instructions_retain_fatal_budget():
    case = short_case(polls=100)
    case["instruction_limit"] = 1000
    with pytest.raises(ValueError, match="instruction limit exhausted"):
        run(case)


def test_ack_compact_keeps_mmio_and_barrier_guards():
    case = short_case()
    case["external_outcomes"][8]["value"] = 99
    with pytest.raises(ValueError, match="scripted register write value differs"):
        run(case)
    case = short_case()
    case["operations"] = []
    with pytest.raises(ValueError, match="unsupported privileged/cache/barrier operation"):
        run(case)


def test_ack_allowance_rejects_unpinned_reader_before_execution(tmp_path):
    raw, image = runner().load_image(OUT / "reference/image.bin")
    section = next(s for s in image["sections"] if s["address"] <= 0x189ddc < s["address"] + s["size"])
    offset = section["offset"] + 0x189ddc - section["address"]
    changed = bytearray(raw)
    changed[offset + 2] ^= 1
    path = tmp_path / "unreviewed-reader.bin"
    path.write_bytes(changed)
    with pytest.raises(ValueError, match="unsupported ACK exhaustion opt-in"):
        runner().run_case(path, short_case(), json.loads((TESTS / "contracts.json").read_text()))


def test_ack_owner_requires_actual_exhaustion_evidence():
    spec = importlib.util.spec_from_file_location("ack_verify", TESTS / "verify.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "audit_negotiation_ack"), "missing executed ACK exhaustion owner gate"
    module.audit_negotiation_ack(TESTS.parent, REPO, OUT / "objects/task9")


@pytest.mark.parametrize("corruption", ["count", "exit", "restoration", "return", "instructions", "closure", "producer"])
def test_ack_owner_rejects_false_boundary_evidence(tmp_path, corruption):
    spec = importlib.util.spec_from_file_location("ack_verify_negative", TESTS / "verify.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    repo = tmp_path / "repo"
    driver = repo / "src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI"
    proof_path = driver / "reconstruction/task9-ack.json"
    proof = json.loads((TESTS.parent / "reconstruction/task9-ack.json").read_text())
    paths = list(proof["execution_inputs"]) + [
        "src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/AdaptecU2CHIMNegotiation.c"]
    for relative in paths:
        target = repo / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(REPO / relative, target)
    shutil.copyfile(REPO / ".git", repo / ".git")
    objects = tmp_path / "objects"
    objects.mkdir()
    for name in ("objects.json", "1-AdaptecU2CHIMNegotiation.c.o", "ack-reference-results.json"):
        shutil.copyfile(OUT / "objects/task9" / name, objects / name)
    path = objects / "ack-reference-results.json"
    document = json.loads(path.read_text())
    observed = document["reference"]["results"][0]
    expected = "invalid Task9 ACK counter/trace/return"
    if corruption == "count":
        next(e for e in observed["observations"]["trace"] if "repeat" in e)["repeat"] -= 1
    elif corruption == "exit":
        observed["ack_poll"]["exit"] = "ack-clear"
    elif corruption == "restoration":
        trace = observed["observations"]["trace"]
        trace[-6:-2] = trace[-4:-2] + trace[-6:-4]
    elif corruption == "return":
        observed["returned_to_sentinel"] = False
    elif corruption == "instructions":
        observed["instructions"] -= 1
    elif corruption == "closure":
        proof["execution_inputs"].pop("tools/binrecon/binrecon/__init__.py")
        expected = "Task9 ACK execution input closure is incomplete"
    elif corruption == "producer":
        document["reference"]["source_revision"] = "0" * 40
        expected = "Task9 ACK actual producer differs"
    path.write_text(json.dumps(document))
    proof["results_sha256"] = hashlib.sha256(path.read_bytes()).hexdigest().upper()
    proof_path.write_text(json.dumps(proof))
    with pytest.raises(ValueError, match=expected):
        module.audit_negotiation_ack(driver, repo, objects)


def test_ack_proof_and_two_ledger_sites_survive_git_checkout(tmp_path):
    prefix = "src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/reconstruction/"
    path = prefix + "task9-ack.json"
    blob = subprocess.check_output(["git", "show", "HEAD:" + path], cwd=REPO)
    assert (REPO / path).read_bytes().replace(b"\r\n", b"\n") == blob
    subprocess.check_call(["git", "checkout-index", "--prefix=" + tmp_path.as_posix() + "/", "--",
                           path, prefix + "ledger.json"], cwd=REPO)
    assert (tmp_path / path).read_bytes().replace(b"\r\n", b"\n") == blob
    ledger = json.loads((tmp_path / (prefix + "ledger.json")).read_text())
    sites = [(entry["address"], artifact["sha256"]) for entry in ledger["entries"] for artifact in entry["artifacts"]
             if artifact["path"] == path]
    digest = hashlib.sha256(blob).hexdigest().upper()
    assert sites == [(0x1990e4, digest), (0x199708, digest)]
