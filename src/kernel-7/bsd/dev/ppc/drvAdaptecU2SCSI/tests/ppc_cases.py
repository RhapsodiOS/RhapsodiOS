"""Bounded PPC32 big-endian routine execution; never substitutes driver code."""

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

import unicorn
from unicorn import ppc_const as ppc

from binrecon.identity import identify
from binrecon.macho import load_image


REPO = Path(__file__).resolve().parents[7]
STACK = 0x7ff00000
STACK_SIZE = 0x10000
SENTINEL = 0x7fff0000
REGION_BASE = 0x70000000
RUNNER_VERSION = "1/unicorn-" + unicorn.__version__ + "/" + hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
_spec = importlib.util.spec_from_file_location("au2_runner_reference", Path(__file__).with_name("reference.py"))
_reference = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_reference)
DRIVER_SYMBOLS = {name.removeprefix("_") for function in _reference.frozen_functions(REPO).values() for name in function["names"]}


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest().upper()


def revision():
    return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip()


def run_case(binary: Path, case: dict, contracts: dict) -> dict:
    payload, image = load_image(binary)
    if (image["input"]["architecture"], image["input"]["endianness"]) != ("ppc", "big"):
        raise ValueError("runner requires PPC32 big-endian Mach-O")
    if image["extensions"]["macho"]["header"]["file_type"] != 2:
        raise ValueError("runner requires a linked executable")
    symbols = {}
    for symbol in image["symbols"]:
        if symbol["section"]:
            symbols.setdefault(symbol["name"], set()).add(symbol["address"])
    if image["input"]["sha256"] == contracts.get("reference_sha256"):
        for name, address in contracts.get("reference_aliases", {}).items():
            symbols.setdefault(name, set()).add(address)

    def resolve(name):
        addresses = symbols.get(name, set())
        if not name.startswith("_"):
            addresses = addresses | symbols.get("_" + name, set())
        if len(addresses) != 1:
            raise ValueError(f"missing or ambiguous symbol: {name}")
        return next(iter(addresses))

    entry = resolve(case["entry"])
    if (image["input"]["sha256"] == contracts.get("reference_sha256") and
            case["evidence"]["entry_address"] != entry):
        raise ValueError(f"fixture identity address differs: {case['id']}")
    bounds = [(entry, entry + case["size"])]
    for body in case.get("internal", []):
        start = resolve(body["entry"])
        bounds.append((start, start + body["size"]))
    if any(start >= end or (end - start) % 4 for start, end in bounds):
        raise ValueError("invalid reviewed function bounds")
    limit = case["instruction_limit"]
    if not 0 < limit <= 1000000:
        raise ValueError("instruction limit must be in 1..1000000")
    if len(case["arguments"]) > 8:
        raise ValueError("only reviewed r3..r10 integer/pointer arguments are supported")
    if case.get("return_kind", "scalar") not in ("scalar", "pointer"):
        raise ValueError("unsupported return observation kind")

    cpu = unicorn.Uc(unicorn.UC_ARCH_PPC, unicorn.UC_MODE_32 | unicorn.UC_MODE_BIG_ENDIAN)
    cpu.ctl_set_cpu_model(ppc.UC_CPU_PPC32_604)
    pages = {}
    for segment in image["extensions"]["macho"]["segments"]:
        permissions = sum(bit for char, bit in (("r", 1), ("w", 2), ("x", 4)) if char in segment["permissions"])
        if segment["size"] > 0x10000000:
            raise ValueError("segment exceeds bounded image size")
        for page in range(segment["address"] & ~4095, (segment["address"] + segment["size"] + 4095) & ~4095, 4096):
            pages[page] = pages.get(page, 0) | permissions
    for page, permissions in pages.items():
        cpu.mem_map(page, 4096, permissions)
    for segment in image["extensions"]["macho"]["segments"]:
        cpu.mem_write(segment["address"], payload[segment["offset"]:segment["offset"] + segment["file_size"]])
    # Newly mapped memory is zero, including segment BSS and stack.
    cpu.mem_map(STACK, STACK_SIZE, unicorn.UC_PROT_READ | unicorn.UC_PROT_WRITE)
    cpu.mem_map(SENTINEL, 4096, unicorn.UC_PROT_READ | unicorn.UC_PROT_EXEC)
    cpu.reg_write(ppc.UC_PPC_REG_1, STACK + STACK_SIZE - 256)
    cpu.reg_write(ppc.UC_PPC_REG_LR, SENTINEL)
    regions = {}
    next_region = REGION_BASE
    for region in case["memory"]:
        size = region["size"]
        if region["name"] in regions or not 0 < size <= 0x100000:
            raise ValueError("invalid fixture region")
        mapped = (size + 4095) & ~4095
        cpu.mem_map(next_region, mapped, unicorn.UC_PROT_READ | unicorn.UC_PROT_WRITE)
        regions[region["name"]] = (next_region, size)
        initial = bytes.fromhex(region["bytes"])
        if len(initial) > size:
            raise ValueError("fixture bytes exceed region")
        cpu.mem_write(next_region, initial)
        next_region += mapped

    def pointer(value, width=0):
        base, size = regions[value["region"]]
        offset = value["offset"]
        if not 0 <= offset <= size - width:
            raise ValueError("fixture observation exceeds region")
        return base + offset

    def argument(value):
        if isinstance(value, dict):
            return pointer(value)
        return value & 0xffffffff

    def normalized(value):
        if value == 0:
            return None
        for name, (base, size) in regions.items():
            if base <= value < base + size:
                return f"{name}+{value-base}"
        names = sorted({name.removeprefix("_") for name, addresses in symbols.items() if addresses == {value}})
        if names:
            return names[0]
        raise ValueError(f"unresolved declared pointer: 0x{value:x}")

    for index, value in enumerate(case["arguments"]):
        cpu.reg_write(getattr(ppc, f"UC_PPC_REG_{index + 3}"), argument(value))
    for region in case["memory"]:
        for field in region.get("pointers", []):
            address = pointer({"region": region["name"], "offset": field["offset"]}, 4)
            cpu.mem_write(address, argument(field["value"]).to_bytes(4, "big"))

    services = {}
    for name, contract in contracts["services"].items():
        if (len(contract["arguments"]) > 8 or any(kind not in ("scalar", "pointer") for kind in contract["arguments"]) or
                contract["return"] not in ("scalar", "pointer")):
            raise ValueError(f"unsupported service calling convention: {name}")
        address = resolve(name)
        if (name.removeprefix("_") in DRIVER_SYMBOLS or any(a <= address < b for a, b in bounds) or
                contract["boundary"] not in ("kernel-service", "callback")):
            raise ValueError(f"service replaces an internal body or has an unsupported boundary: {name}")
        if not contract.get("evidence"):
            raise ValueError(f"service lacks boundary evidence: {name}")
        services[address] = (name, contract)
    outcomes = iter(case["external_outcomes"])
    trace, count, returned, previous_word = [], 0, False, None

    def memory_access(uc, access, address, size, value, region):
        base, extent = regions[region["name"]]
        offset = address - base
        if offset < 0 or offset + size > extent:
            raise ValueError(f"access exceeds fixture region: {region['name']}")
        if "mmio" not in region:
            return
        if size not in (1, 2, 4):
            raise ValueError("unsupported register access width")
        kind = "read" if access == unicorn.UC_MEM_READ else "write"
        registers = contracts.get("mmio", {}).get(region["mmio"], [])
        if not any(r["offset"] == offset and r["size"] == size and kind in r["access"] and r.get("evidence") for r in registers):
            raise ValueError(f"unknown register {kind}: {region['name']}+{offset}/{size}")
        outcome = next(outcomes, None)
        if (outcome is None or outcome.get("register") != region["name"] or outcome["access"] != kind or
                outcome["offset"] != offset or outcome["size"] != size):
            raise ValueError("unexpected scripted register access")
        expected = outcome["value"]
        if not 0 <= expected < 1 << (size * 8):
            raise ValueError("register value exceeds its declared width")
        if kind == "read":
            uc.mem_write(address, expected.to_bytes(size, "big"))
        elif value != expected:
            raise ValueError("scripted register write value differs")
        trace.append({"target": f"{region['name']}+{offset}", "access": kind, "size": size, "value": expected})

    for region in case["memory"]:
        base, extent = regions[region["name"]]
        cpu.hook_add(unicorn.UC_HOOK_MEM_READ | unicorn.UC_HOOK_MEM_WRITE, memory_access,
                     user_data=region, begin=base, end=base + ((extent + 4095) & ~4095) - 1)

    def instruction(uc, address, size, _):
        nonlocal count, returned, previous_word
        if address == SENTINEL:
            if previous_word != 0x4e800020 or uc.reg_read(ppc.UC_PPC_REG_LR) != SENTINEL:
                raise ValueError("return sentinel reached without return link")
            returned = True
            uc.emu_stop()
            return
        count += 1
        if count > limit:
            raise ValueError(f"instruction limit exhausted: {case['id']}")
        if address in services:
            name, contract = services[address]
            outcome = next(outcomes, None)
            if outcome is None or outcome["service"] != name:
                raise ValueError(f"unexpected scripted external call: {name}")
            args = []
            for index, kind in enumerate(contract["arguments"]):
                value = uc.reg_read(getattr(ppc, f"UC_PPC_REG_{index + 3}"))
                args.append(normalized(value) if kind == "pointer" else value)
            if args != outcome["arguments"]:
                raise ValueError(f"external argument mismatch: {name}")
            for write in outcome.get("writes", []):
                if any(region["name"] == write["region"] and "mmio" in region for region in case["memory"]):
                    raise ValueError("scripted service write bypasses register contract")
                raw = bytes.fromhex(write["bytes"])
                uc.mem_write(pointer(write, len(raw)), raw)
            result = argument(outcome["return"])
            trace.append({"target": name, "arguments": args,
                          "return": normalized(result) if contract["return"] == "pointer" else result})
            uc.reg_write(ppc.UC_PPC_REG_3, result)
            uc.reg_write(ppc.UC_PPC_REG_PC, uc.reg_read(ppc.UC_PPC_REG_LR))
            return
        if not any(a <= address < b for a, b in bounds):
            raise ValueError(f"unknown call/control transfer at 0x{address:x}")
        word = int.from_bytes(uc.mem_read(address, 4), "big")
        previous_word = word
        opcode, xo = word >> 26, (word >> 1) & 1023
        # Trap/system/privileged, cache, and synchronization operations require
        # separate hardware/ownership evidence; they must never become no-ops.
        if opcode in (3, 17) or (opcode == 19 and xo in (50, 150)) or (opcode == 31 and xo in
                (4, 54, 83, 86, 146, 210, 242, 246, 278, 306, 310, 370, 470, 566, 595, 598, 659, 758, 854, 982, 1014)):
            raise ValueError(f"unsupported privileged/cache/barrier operation at 0x{address:x}")
        if opcode == 31 and xo in (339, 467):
            spr = ((word >> 16) & 31) | ((word >> 6) & 992)
            if spr not in (1, 8, 9):
                raise ValueError(f"unsupported privileged special register at 0x{address:x}")

    cpu.hook_add(unicorn.UC_HOOK_CODE, instruction)
    try:
        cpu.emu_start(entry, 0, count=limit + 2)
    except unicorn.UcError as error:
        raise ValueError(f"unsupported instruction or memory access: {error}") from error
    if not returned:
        raise ValueError(f"instruction limit exhausted without return sentinel: {case['id']}")
    if next(outcomes, None) is not None:
        raise ValueError("unused scripted external outcome")
    memory = {}
    for observation in case["observe"]:
        raw = bytearray(cpu.mem_read(pointer(observation, observation["size"]), observation["size"]))
        pointers = {}
        for offset in observation.get("pointer_fields", []):
            if not 0 <= offset <= len(raw) - 4:
                raise ValueError("pointer observation exceeds bytes")
            pointers[str(offset)] = normalized(int.from_bytes(raw[offset:offset+4], "big"))
            raw[offset:offset+4] = bytes(4)
        key = f"{observation['region']}+{observation['offset']}"
        memory[key] = {"bytes": raw.hex(), "pointers": pointers} if pointers else raw.hex()
    result = cpu.reg_read(ppc.UC_PPC_REG_3)
    observations = {"return": normalized(result) if case.get("return_kind") == "pointer" else result,
                    "memory": memory, "trace": trace}
    return {"executed_case_id": case["id"], "observations": observations,
            "unknown_calls": [], "returned_to_sentinel": returned, "instructions": count}


def execute(binary, cases, contracts):
    if "reference_sha256" in contracts:
        expected = contracts["reference_sha256"]
        if cases.get("reference_sha256") != expected or any(
                case.get("evidence", {}).get("reference_sha256") != expected for case in cases["cases"]):
            raise ValueError("fixture identity differs from reference contract")
    ids = [case["id"] for case in cases["cases"]]
    if not ids or len(set(ids)) != len(ids):
        raise ValueError("missing or duplicate selected case IDs")
    results = []
    for case in cases["cases"]:
        if not case["evidence"] or "expected" not in case:
            raise ValueError(f"unreviewed fixture: {case['id']}")
        result = run_case(binary, case, contracts)
        if result["observations"] != case["expected"]:
            raise ValueError(f"frozen expected observations differ: {case['id']}: {result['observations']}")
        results.append(result)
    return {"binary_sha256": identify(binary).sha256, "cases_sha256": digest(cases),
            "contracts_sha256": digest(contracts), "source_revision": revision(),
            "runner_version": RUNNER_VERSION, "selected_case_ids": ids, "results": results}


def validate_result(result, binary, cases, contracts):
    expected = {"binary_sha256": identify(binary).sha256, "cases_sha256": digest(cases),
                "contracts_sha256": digest(contracts), "source_revision": revision(), "runner_version": RUNNER_VERSION}
    for key, value in expected.items():
        if result.get(key) != value:
            raise ValueError(f"stale result: {key}")
    ids = [case["id"] for case in cases["cases"]]
    if result.get("selected_case_ids") != ids or len(result.get("results", [])) != len(ids):
        raise ValueError("missing or skipped case results")
    for case, observed in zip(cases["cases"], result["results"]):
        if (observed.get("executed_case_id") != case["id"] or observed.get("unknown_calls") != [] or
                observed.get("returned_to_sentinel") is not True or observed.get("observations") != case["expected"]):
            raise ValueError(f"invalid case result: {case['id']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("reference", "pair"))
    for name in ("reference", "cases", "contracts", "output"):
        parser.add_argument("--" + name, required=True, type=Path)
    parser.add_argument("--rebuilt", type=Path)
    args = parser.parse_args()
    if args.mode == "pair" and args.rebuilt is None:
        parser.error("pair requires --rebuilt")
    try:
        cases = json.loads(args.cases.read_text(encoding="utf-8"))
        contracts = json.loads(args.contracts.read_text(encoding="utf-8"))
        binary = args.reference / "image.bin"
        identity = json.loads((args.reference / "reference.json").read_text(encoding="utf-8"))["identity"]
        if (identify(binary).sha256 != identity["sha256"] or identity["sha256"] != _reference.SHA256 or
                identity["sha256"] != contracts["reference_sha256"]):
            raise ValueError("reference identity differs")
        results = {"reference": execute(binary, cases, contracts)}
        if args.mode == "pair":
            results["rebuilt"] = execute(args.rebuilt, cases, contracts)
        for name, result in results.items():
            validate_result(result, binary if name == "reference" else args.rebuilt, cases, contracts)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    except (ValueError, OSError, KeyError) as error:
        parser.exit(1, str(error) + "\n")
    print(f"{args.mode}: {len(cases['cases'])} frozen cases passed")


if __name__ == "__main__":
    main()
