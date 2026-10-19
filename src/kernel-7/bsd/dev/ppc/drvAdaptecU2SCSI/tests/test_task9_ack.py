"""Actual ACK polling, compact boundary accounting, and narrow resource opt-in."""

import copy
import functools
import importlib.util
import json
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
