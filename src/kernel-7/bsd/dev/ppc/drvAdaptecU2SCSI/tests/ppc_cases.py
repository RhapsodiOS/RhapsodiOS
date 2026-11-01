"""Bounded PPC32 big-endian routine execution; never substitutes driver code."""

import argparse
import hashlib
import importlib.util
import json
import re
from pathlib import Path
import subprocess

import unicorn
from unicorn import ppc_const as ppc

from binrecon.identity import identify
from binrecon.macho import load_image, objc_methods_from_sections
from binrecon.objc_abi import method_symbol_index
from binrecon.source_map import _without_category


REPO = Path(__file__).resolve().parents[7]
STACK = 0x7ff00000
STACK_SIZE = 0x10000
SENTINEL = 0x7fff0000
REGION_BASE = 0x70000000
RUNNER_VERSION = "1/unicorn-" + unicorn.__version__ + "/" + hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
_spec = importlib.util.spec_from_file_location("au2_runner_reference", Path(__file__).with_name("reference.py"))
_reference = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_reference)
DRIVER_FUNCTIONS = tuple(_reference.frozen_functions(REPO).values())
DRIVER_SYMBOLS = {name.removeprefix("_") for function in DRIVER_FUNCTIONS for name in function["names"]}
DRIVER_SELECTORS = {name.split(" ", 1)[1][:-1] for name in DRIVER_SYMBOLS
                    if name.startswith(("-[AdaptecU2SCSI ", "+[AdaptecU2SCSI "))}


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest().upper()


def revision():
    return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip()


def declared_abi(case):
    """Bind the supported argument slots to a reviewed production declaration."""
    declaration = " ".join(case.get("declaration", "").split())
    name = case["entry"].removeprefix("_")
    driver = Path(__file__).resolve().parent.parent
    headers = " ".join(" ".join((driver / header).read_text().split()) for header in
                       ("OSMFunctions.h", "AdaptecU2CHIMPrivate.h", "AdaptecU2SCSIPrivate.h", "AdaptecU2CHIM.h"))
    match = re.fullmatch(r"(.+?)\b" + re.escape(name) + r"\((.*)\);", declaration)
    if not match or declaration not in headers:
        raise ValueError("case declaration does not bind its production entry")
    parameters = [] if match[2] == "void" else match[2].split(",")
    if parameters and parameters[-1].strip() == "...":
        parameters.pop()
    layouts = []
    for parameter in parameters:
        parameter = parameter.strip()
        if "*" in parameter:
            layouts.append(("pointer", 4))
        elif parameter.startswith("AdaptecU2IOHandle "):
            layouts.append(("aggregate", 32))
        elif parameter.startswith("AdaptecU2AdapterProfile "):
            layouts.append(("aggregate", 464))
        elif parameter.startswith("AdaptecU2PciLocation "):
            layouts.append(("aggregate", 16))
        elif parameter.startswith("unsigned char "):
            layouts.append(("scalar", 1))
        elif parameter.startswith("unsigned short "):
            layouts.append(("scalar", 2))
        elif parameter.startswith(("unsigned int ", "int ")):
            layouts.append(("scalar", 4))
        elif parameter.startswith("AdaptecU2OSMContext "):
            layouts.append(("pointer", 4))
        else:
            raise ValueError("unsupported declared argument convention")
    if len(layouts) != len(case["arguments"]):
        raise ValueError("declared argument count differs")
    kind = "void" if match[1].strip() == "void" else "pointer" if "*" in match[1] else "scalar"
    if case.get("return_kind", "scalar") != kind:
        raise ValueError("return observation differs from production declaration")
    return layouts


def machine_inputs(case):
    if "machine_inputs" not in case:
        return {}
    values = case["machine_inputs"]
    if (case.get("entry") != "SCSIhInitializeHardware" or
            case.get("evidence", {}).get("entry_address") != 0x1931e4 or
            case.get("declaration") != "void SCSIhInitializeHardware(AdaptecU2HHCB *hhcb);" or
            not isinstance(values, dict) or set(values) != {"r28"} or
            type(values["r28"]) is not int or not 0 <= values["r28"] <= 0xffffffff):
        raise ValueError("unsupported machine input; only reviewed incoming r28 is permitted")
    return {28: values["r28"]}


def run_case(binary: Path, case: dict, contracts: dict) -> dict:
    registers = machine_inputs(case)
    payload, image = load_image(binary)
    if (image["input"]["architecture"], image["input"]["endianness"]) != ("ppc", "big"):
        raise ValueError("runner requires PPC32 big-endian Mach-O")
    if image["extensions"]["macho"]["header"]["file_type"] != 2:
        raise ValueError("runner requires a linked executable")
    ack = case.get("ack_exhaustion", False)
    if "ack_exhaustion" in case:
        allowed = {"SCSIhSendMessage": (0x1990e4, 756), "SCSIhHandleMsgOut": (0x199708, 736)}
        identity = allowed.get(case["entry"])
        internals = {b["entry"]: b["size"] for b in case.get("internal", [])}
        required = {"OSMReadUExact8": 52, "OSMWriteUExact8": 60}
        if case["entry"] == "SCSIhSendMessage":
            required["SCSIhWait4Req"] = 480
        if (ack is not True or identity != (case.get("evidence", {}).get("entry_address"), case["size"]) or
                image["input"]["sha256"] != _reference.SHA256 or contracts.get("reference_sha256") != _reference.SHA256 or
                internals != required or len(internals) != len(case.get("internal", [])) or
                case.get("return_kind") != "void" or
                type(case["instruction_limit"]) is not int or not 0 < case["instruction_limit"] <= 240000000 or
                (case["entry"] == "SCSIhSendMessage" and case["arguments"][-1] != 1)):
            raise ValueError("unsupported ACK exhaustion opt-in")
    symbols = {}
    for symbol in image["symbols"]:
        if symbol["section"]:
            symbols.setdefault(symbol["name"], set()).add(symbol["address"])
    for address, names in objc_methods_from_sections(
            payload, image["sections"], endianness="big", method_names=method_symbol_index(image)).items():
        for name in names:
            symbols.setdefault(name, set()).add(address)
            category_alias = _without_category(name)
            if category_alias:
                symbols.setdefault(category_alias, set()).add(address)
    if image["input"]["sha256"] == contracts.get("reference_sha256"):
        for name, address in contracts.get("reference_aliases", {}).items():
            symbols.setdefault(name, set()).add(address)
    driver_addresses = {address for name, addresses in symbols.items()
                        if name.removeprefix("_") in DRIVER_SYMBOLS for address in addresses}
    # Reference-only unnamed bodies retain their full frozen identity even
    # when a caller supplies only a new name at an interior instruction.
    driver_bounds = [(function["address"], function["address"] + function["size"])
                     for function in DRIVER_FUNCTIONS] if image["input"]["sha256"] == _reference.SHA256 else []

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
    if not ack and (type(limit) is not int or not 0 < limit <= 4000000):
        raise ValueError("instruction limit must be in 1..4000000")
    layouts = declared_abi(case) if "declaration" in case else None
    if layouts is None and len(case["arguments"]) > 8:
        raise ValueError("only reviewed r3..r10 integer/pointer arguments are supported")
    if case.get("return_kind", "scalar") not in ("scalar", "pointer", "void"):
        raise ValueError("unsupported return observation kind")
    if case.get("return_kind") == "void" and layouts is None:
        raise ValueError("void result requires a production declaration")

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
    initial_sp = STACK + STACK_SIZE - 4096
    cpu.reg_write(ppc.UC_PPC_REG_1, initial_sp)
    cpu.reg_write(ppc.UC_PPC_REG_LR, SENTINEL)
    for register, value in registers.items():
        cpu.reg_write(getattr(ppc, f"UC_PPC_REG_{register}"), value)
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
            if set(value) == {"symbol"}:
                return resolve(value["symbol"])
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

    def cstring(address):
        data = bytearray()
        for offset in range(4096):
            byte = bytes(cpu.mem_read(address + offset, 1))
            if byte == b"\0":
                return data.decode("ascii")
            data.extend(byte)
        raise ValueError("unterminated bounded service string")

    words = []
    for index, value in enumerate(case["arguments"]):
        kind, width = layouts[index] if layouts else ("scalar", 4)
        if kind == "aggregate":
            if not isinstance(value, dict) or "bytes" not in value:
                raise ValueError("aggregate argument requires exact bytes")
            raw = bytearray.fromhex(value["bytes"])
            if len(raw) != width:
                raise ValueError("aggregate argument extent differs")
            for field in value.get("pointers", []):
                offset = field["offset"]
                if offset % 4 or not 0 <= offset <= width - 4:
                    raise ValueError("aggregate pointer field exceeds extent")
                raw[offset:offset+4] = argument(field["value"]).to_bytes(4, "big")
            words.extend(int.from_bytes(raw[i:i+4], "big") for i in range(0, width, 4))
        else:
            words.append(argument(value) & ((1 << (width * 8)) - 1))
    if len(words) * 4 + 24 > 4096:
        raise ValueError("arguments exceed bounded parameter area")
    for index, value in enumerate(words):
        if index < 8:
            cpu.reg_write(getattr(ppc, f"UC_PPC_REG_{index + 3}"), value)
        else:
            cpu.mem_write(initial_sp + 24 + 4 * index, value.to_bytes(4, "big"))
    for region in case["memory"]:
        for field in region.get("pointers", []):
            address = pointer({"region": region["name"], "offset": field["offset"]}, 4)
            cpu.mem_write(address, argument(field["value"]).to_bytes(4, "big"))
    for setting in case.get("globals", []):
        contract = contracts.get("globals", {}).get(setting["symbol"], {})
        address = resolve(setting["symbol"])
        if (setting["symbol"] not in ("_page_size", "_page_mask", "_page_shift") or
                contract.get("width") != 4 or not contract.get("evidence") or
                not any(section["address"] <= address <= section["address"] + section["size"] - 4
                        and "w" in section["permissions"] and "x" not in section["permissions"]
                        for section in image["sections"])):
            raise ValueError("unsupported kernel global initialization")
        cpu.mem_write(address, argument(setting["value"]).to_bytes(4, "big"))

    services = {}
    observed_calls = {}
    for callback in case.get("observe_calls", []):
        address = resolve(callback["entry"])
        if not any(address == start for start, end in bounds):
            raise ValueError("observed callback is not an executing reviewed body")
        try:
            callback_layouts = declared_abi(callback)
        except ValueError as error:
            raise ValueError(f"observed callback declaration differs: {error}") from error
        observed_calls[address] = (callback["entry"], callback_layouts)
    def validate_service_abi(name, contract):
        if (len(contract["arguments"]) > 8 or any(
                kind not in ("scalar", "pointer", "cstring") if isinstance(kind, str) else
                kind.get("kind") != "output" or kind.get("size") not in (4,)
                for kind in contract["arguments"]) or
                contract["return"] not in ("scalar", "pointer", "void")):
            raise ValueError(f"unsupported service calling convention: {name}")

    for name, contract in contracts["services"].items():
        validate_service_abi(name, contract)
        address = resolve(name)
        if (name.removeprefix("_") in DRIVER_SYMBOLS or address in driver_addresses or
                any(a <= address < b for a, b in bounds + driver_bounds) or
                contract["boundary"] not in ("kernel-service", "callback")):
            raise ValueError(f"service replaces an internal body or has an unsupported boundary: {name}")
        if not contract.get("evidence"):
            raise ValueError(f"service lacks boundary evidence: {name}")
        if "dispatch" in contract and name != "_objc_msgSend":
            raise ValueError("unsupported shared external dispatcher")
        services[address] = (name, contract)
    def scripted_outcomes():
        for item in case["external_outcomes"]:
            if "repeat" not in item:
                yield item
                continue
            event = item.get("outcome")
            if (not ack or set(item) != {"repeat", "outcome"} or type(item["repeat"]) is not int or
                    not 0 < item["repeat"] <= 0x800000 or event != {
                        "register": "registers", "access": "read", "offset": 3, "size": 1, "value": 1}):
                raise ValueError("unsupported repeated MMIO outcome")
            for _ in range(item["repeat"]):
                yield event

    outcomes = scripted_outcomes()
    trace, count, returned, previous_word = [], 0, False, None
    poll_reads, poll_exit, previous_address = 0, None, None
    ack_words = {}
    if ack:
        poll_start, poll_end, poll_return, poll_tail, poll_counter = (
            (0x1992d8, 0x199314, 0x199300, 0x199314, 0x19930c) if entry == 0x1990e4 else
            (0x199984, 0x1999c0, 0x1999ac, 0x1999c0, 0x1999b8))
        # These pinned-image instructions are the complete poll and real OSM
        # reader. Cache their immutable words; Unicorn still executes every one.
        for start, end in ((poll_start, poll_end), (0x189db4, 0x189de8)):
            for address in range(start, end, 4):
                ack_words[address] = int.from_bytes(cpu.mem_read(address, 4), "big")

    def memory_access(uc, access, address, size, value, region):
        nonlocal poll_reads
        base, extent = regions[region["name"]]
        offset = address - base
        if offset < 0 or offset + size > extent:
            raise ValueError(f"access exceeds fixture region: {region['name']}")
        if "mmio" not in region:
            return
        if size not in (1, 2, 4):
            raise ValueError("unsupported register access width")
        kind = "read" if access == unicorn.UC_MEM_READ else "write"
        if kind == "write":
            word = int.from_bytes(uc.mem_read(uc.reg_read(ppc.UC_PPC_REG_PC), 4), "big")
            # PPC's Unicorn hook exposes the source register for reversed
            # stores. Convert only these decoded opcodes to the bus byte order.
            if word >> 26 == 31 and (word >> 1) & 1023 in (662, 918):
                if size != (4 if (word >> 1) & 1023 == 662 else 2):
                    raise ValueError("reversed-store access width differs")
                value = int.from_bytes(value.to_bytes(size, "big"), "little")
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
            raise ValueError(f"scripted register write value differs: {case['id']} {value:#x} != {expected:#x}")
        event = {"target": f"{region['name']}+{offset}", "access": kind, "size": size, "value": expected}
        if ack and kind == "read" and uc.reg_read(ppc.UC_PPC_REG_LR) == poll_return:
            poll_reads += 1
            if poll_reads % 0x100000 == 0:
                print(f"{case['id']}: {poll_reads} actual ACK reads", flush=True)
        if ack and trace and trace[-1] == event:
            trace[-1] = {"repeat": 2, "event": event}
        elif ack and trace and trace[-1].get("event") == event:
            trace[-1]["repeat"] += 1
        else:
            trace.append(event)

    for region in case["memory"]:
        base, extent = regions[region["name"]]
        cpu.hook_add(unicorn.UC_HOOK_MEM_READ | unicorn.UC_HOOK_MEM_WRITE, memory_access,
                     user_data=region, begin=base, end=base + ((extent + 4095) & ~4095) - 1)

    def instruction(uc, address, size, _):
        nonlocal count, returned, previous_word, previous_address, poll_exit
        if address == SENTINEL:
            if previous_word != 0x4e800020 or uc.reg_read(ppc.UC_PPC_REG_LR) != SENTINEL:
                raise ValueError("return sentinel reached without return link")
            returned = True
            uc.emu_stop()
            return
        count += 1
        if count > limit:
            raise ValueError(f"instruction limit exhausted: {case['id']}")
        last_address, previous_address = previous_address, address
        if ack and address == poll_tail:
            poll_exit = "counter" if last_address == poll_counter else "ack-clear"
        if address in ack_words:
            previous_word = ack_words[address]
            return
        if address in services:
            name, contract = services[address]
            outcome = next(outcomes, None)
            if outcome is None or outcome["service"] != name:
                raise ValueError(f"unexpected scripted external call: {name}")
            if "formats" in contract:
                format_string = cstring(uc.reg_read(ppc.UC_PPC_REG_3))
                if name != "_IOLog" or format_string not in contract["formats"]:
                    raise ValueError("unreviewed kernel variadic format")
                contract = dict(contract, arguments=["cstring", *contract["formats"][format_string]])
            if "dispatch" in contract:
                selector = cstring(uc.reg_read(ppc.UC_PPC_REG_4))
                if selector in DRIVER_SELECTORS:
                    raise ValueError("external dispatcher replaces an internal driver selector")
                receiver = normalized(uc.reg_read(ppc.UC_PPC_REG_3))
                selected = [item for item in contract["dispatch"]
                            if item["receiver"] == receiver and item["selector"] == selector]
                if len(selected) != 1:
                    raise ValueError("unknown receiver/selector provider dispatch")
                contract = selected[0]
                if ((contract["provider"], selector) not in {
                        ("IODevice", "deviceDescription"),
                        ("IODevice", "stringFromReturn:"),
                        ("IOPCIDevice", "configReadLong:value:"),
                        ("IOPCIDevice", "configWriteLong:value:"),
                        ("IOPCIDevice", "getIOAperture")} or not contract.get("evidence")):
                    raise ValueError("unsupported Objective-C provider")
            validate_service_abi(name, contract)
            args = []
            outputs = {}
            for index, kind in enumerate(contract["arguments"]):
                value = uc.reg_read(getattr(ppc, f"UC_PPC_REG_{index + 3}"))
                if isinstance(kind, dict):
                    extent = kind["size"]
                    if not (STACK <= value <= STACK + STACK_SIZE - extent or
                            any(base <= value <= base + size - extent and
                                not any(r["name"] == region and "mmio" in r for r in case["memory"])
                                for region, (base, size) in regions.items())):
                        raise ValueError("output argument exceeds bounded writable memory")
                    outputs[index] = (value, extent)
                    args.append(f"output:{index}")
                else:
                    args.append(normalized(value) if kind == "pointer" else cstring(value) if kind == "cstring" else value)
            if args != outcome["arguments"]:
                raise ValueError(f"external argument mismatch: {name}")
            for write in outcome.get("writes", []):
                if "argument" in write:
                    index = write["argument"]
                    raw = (argument(write["value"]).to_bytes(4, "big") if "value" in write else
                           bytes.fromhex(write["bytes"]))
                    if index not in outputs or len(raw) != outputs[index][1]:
                        raise ValueError("service write differs from declared output extent")
                    uc.mem_write(outputs[index][0], raw)
                    continue
                if any(region["name"] == write["region"] and "mmio" in region for region in case["memory"]):
                    raise ValueError("scripted service write bypasses register contract")
                raw = bytes.fromhex(write["bytes"])
                uc.mem_write(pointer(write, len(raw)), raw)
            event = {"target": name, "arguments": args}
            if contract["return"] == "void":
                if "return" in outcome:
                    raise ValueError("void service outcome defines an undefined result")
            else:
                result = argument(outcome["return"])
                event["return"] = normalized(result) if contract["return"] == "pointer" else result
                uc.reg_write(ppc.UC_PPC_REG_3, result)
            trace.append(event)
            uc.reg_write(ppc.UC_PPC_REG_PC, uc.reg_read(ppc.UC_PPC_REG_LR))
            return
        if not any(a <= address < b for a, b in bounds):
            raise ValueError(f"unknown call/control transfer at 0x{address:x}")
        if address in observed_calls:
            name, callback_layouts = observed_calls[address]
            args = []
            sp = uc.reg_read(ppc.UC_PPC_REG_1)
            slot = 0
            for kind, width in callback_layouts:
                raw = bytearray()
                for index in range(max(1, width // 4)):
                    value = (uc.reg_read(getattr(ppc, f"UC_PPC_REG_{slot + 3}")) if slot < 8 else
                             int.from_bytes(uc.mem_read(sp + 24 + slot * 4, 4), "big"))
                    raw.extend(value.to_bytes(4, "big"))
                    slot += 1
                if kind == "aggregate":
                    pointers = {}
                    for offset in (0, 20, 24, 28) if width == 32 else ():
                        pointers[str(offset)] = normalized(int.from_bytes(raw[offset:offset+4], "big"))
                        raw[offset:offset+4] = bytes(4)
                    args.append({"bytes": raw.hex(), "pointers": pointers})
                else:
                    value = int.from_bytes(raw[-width:], "big")
                    args.append(normalized(value) if kind == "pointer" else value)
            trace.append({"entry": name, "arguments": args})
        word = int.from_bytes(uc.mem_read(address, 4), "big")
        previous_word = word
        opcode, xo = word >> 26, (word >> 1) & 1023
        if opcode == 31 and xo in (20, 150):
            raise ValueError(f"unsupported reservation operation at 0x{address:x}")
        if word in (0x7c0006ac, 0x7c0004ac):
            operation = "eieio" if word == 0x7c0006ac else "sync"
            if (operation not in case.get("operations", []) or
                    not contracts.get("operations", {}).get(operation, {}).get("evidence")):
                raise ValueError(f"unsupported privileged/cache/barrier operation at 0x{address:x}")
            trace.append({"operation": operation})
            # Keep execution in Unicorn; do not skip the instruction or advance PC.
            return
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
    observations = {"memory": memory, "trace": trace}
    if case.get("return_kind") != "void":
        observations["return"] = normalized(result) if case.get("return_kind") == "pointer" else result
    if "observe_stack" in case:
        stack = {}
        for observation in case["observe_stack"]:
            offset, size = observation["offset"], observation["size"]
            address = initial_sp + offset
            if not 0 < size <= STACK_SIZE or not STACK <= address <= STACK + STACK_SIZE - size:
                raise ValueError("stack observation exceeds bounded stack")
            if str(offset) in stack:
                raise ValueError("duplicate stack observation offset")
            stack[str(offset)] = bytes(cpu.mem_read(address, size)).hex()
        observations["stack"] = stack
        observations["stack_pointer"] = cpu.reg_read(ppc.UC_PPC_REG_1) - initial_sp
    result = {"executed_case_id": case["id"], "observations": observations,
              "unknown_calls": [], "returned_to_sentinel": returned, "instructions": count}
    if ack:
        result["ack_poll"] = {"reads": poll_reads, "exit": poll_exit}
    return result


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
        if case.get("ack_exhaustion") and (result.get("ack_poll") != case.get("expected_ack_poll") or
                                          result["instructions"] != case.get("expected_instructions")):
            raise ValueError(f"ACK poll termination differs: {case['id']}")
        if case.get("ack_exhaustion"):
            print(f"{case['id']}: returned after {result['instructions']} instructions, {result['ack_poll']}", flush=True)
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
        if case.get("ack_exhaustion") and (observed.get("ack_poll") != case.get("expected_ack_poll") or
                                          observed.get("instructions") != case.get("expected_instructions")):
            raise ValueError(f"invalid ACK poll result: {case['id']}")


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
