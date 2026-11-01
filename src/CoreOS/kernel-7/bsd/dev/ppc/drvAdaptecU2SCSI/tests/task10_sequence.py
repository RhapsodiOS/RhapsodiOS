"""Capture complete fixture state across approved serialized recovery calls."""

import copy
import importlib.util
from pathlib import Path


def _runner():
    spec = importlib.util.spec_from_file_location("au2_recovery_boundary", Path(__file__).with_name("ppc_cases.py"))
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    return runner


def capture(binary, case, contracts, pointer_slots):
    runner = _runner()
    payload, image = runner.load_image(binary)
    regions, address = {}, runner.REGION_BASE
    for region in case["memory"]:
        regions[region["name"]] = (address, region["size"])
        address += (region["size"] + 4095) & ~4095
    instances, global_writes = [], []
    original = runner.unicorn.Uc

    def create(*args, **kwargs):
        cpu = original(*args, **kwargs)
        instances.append(cpu)

        def written(uc, access, address, size, value, data):
            if any(s["address"] <= address < s["address"] + s["size"]
                   for s in image["extensions"]["macho"]["segments"]):
                global_writes.append((address, size))
        start = cpu.emu_start

        def execute(*args, **kwargs):
            cpu.hook_add(runner.unicorn.UC_HOOK_MEM_WRITE, written)
            return start(*args, **kwargs)
        cpu.emu_start = execute
        return cpu

    runner.unicorn.Uc = create
    try:
        result = runner.run_case(binary, case, contracts)
    finally:
        runner.unicorn.Uc = original
    if global_writes:
        raise ValueError("recovery boundary requires explicit mutable image-global transfer")
    if len(instances) != 1 or result["unknown_calls"] or not result["returned_to_sentinel"]:
        raise ValueError("invalid actual recovery call boundary")
    cpu = instances[0]
    output = copy.deepcopy(case["memory"])
    symbols = {s["address"]: s["name"].removeprefix("_") for s in image["symbols"] if s["section"]}
    for region in output:
        base, size = regions[region["name"]]
        raw = bytearray(cpu.mem_read(base, size))
        slots = set(pointer_slots.get(region["name"], [])) | {p["offset"] for p in region.get("pointers", [])}
        pointers = []
        for offset in sorted(slots):
            if not 0 <= offset <= size - 4 or offset % 4:
                raise ValueError("recovery boundary pointer slot exceeds region")
            value = int.from_bytes(raw[offset:offset+4], "big")
            binding = value if value in (0, 0xffffffff) else None
            for name, (address, extent) in regions.items():
                if address <= value < address + extent:
                    binding = {"region": name, "offset": value - address}
                    break
            if binding is None and value in symbols:
                binding = {"symbol": symbols[value]}
            if binding is None:
                raise ValueError("unresolved declared recovery boundary pointer")
            pointers.append({"offset": offset, "value": binding})
            raw[offset:offset+4] = bytes(4)
        region["bytes"], region["pointers"] = raw.hex(), pointers
    return {"result": result, "memory": output, "image_writes": []}


def canonical_memory(memory):
    output = copy.deepcopy(memory)
    for region in output:
        raw = bytearray.fromhex(region["bytes"])
        for field in region.get("pointers", []):
            offset = field["offset"]
            raw[offset:offset+4] = bytes(4)
        region["bytes"] = raw.hex()
        region["pointers"] = sorted(region.get("pointers", []), key=lambda p: p["offset"])
    return output


def audit(document, cases):
    by_id = {c["id"]: c for c in cases["cases"]}
    if len(document["sequences"]) != 8:
        raise ValueError("recovery boundary requires both orders in four modes")
    observed = set()
    for sequence in document["sequences"]:
        first, second = [by_id[name] for name in sequence["cases"]]
        observed.add((sequence["mode"], sequence["order"]))
        expected_entries = (("SCSIhBreakInterrupt", "SCSIhTerminateCommand") if sequence["order"] == "abort-complete"
                            else ("SCSIhTerminateCommand", "SCSIhBreakInterrupt"))
        if (first["entry"], second["entry"]) != expected_entries:
            raise ValueError("recovery boundary entry order differs")
        final = {r["name"]: r for r in sequence["second_boundary"]["memory"]}
        hhcb = bytes.fromhex(final["hhcb"]["bytes"])
        resource = bytes.fromhex(final["resource"]["bytes"])
        active = {p["offset"]: p["value"] for p in final["active"]["pointers"]}
        done = {p["offset"]: p["value"] for p in final["done"]["pointers"]}
        if (hhcb[1348] != 1 or hhcb[1352] != 1 or resource[16:20] != bytes(4) or
                active[0] != 0xffffffff or done[0] != {"region": "hiob", "offset": 0}):
            raise ValueError("recovery boundary completion ownership differs")
        if int.from_bytes(hhcb[212:216], "big") & 0x10000:
            raise ValueError("recovery boundary leaves pending abort breakpoint")
        for boundary in (sequence["first_boundary"], sequence["second_boundary"]):
            actual = boundary["result"]
            if any("target" in event and "access" not in event for event in actual["observations"]["trace"]):
                raise ValueError("recovery boundary has unmodeled stateful service")
            if actual["unknown_calls"] or actual["returned_to_sentinel"] is not True or not 0 < actual["instructions"] <= 4000000:
                raise ValueError("invalid actual recovery boundary execution")

        if (sequence["first_boundary"]["image_writes"] != [] or
                sequence["second_boundary"]["image_writes"] != [] or
                sequence["first_boundary"]["result"]["observations"] != first["expected"] or
                sequence["second_boundary"]["result"]["observations"] != second["expected"]):
            raise ValueError("recovery boundary actual observations differ")
        if canonical_memory(second["memory"]) != sequence["first_boundary"]["memory"]:
            raise ValueError("recovery boundary bytes or pointer bindings differ")
        if not sequence.get("preconditions") or sequence.get("external_state") != "scripted MMIO only; no stateful kernel services":
            raise ValueError("recovery boundary state contract is incomplete")
    if observed != {(mode, order) for mode in (0,3,4,5) for order in ("abort-complete","complete-abort")}:
        raise ValueError("recovery boundary orders/modes differ")
