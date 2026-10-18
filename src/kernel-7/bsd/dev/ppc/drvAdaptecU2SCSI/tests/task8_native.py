"""Execute the two Config switches in their actual PPC object control flow."""

import functools
import hashlib

import unicorn
from unicorn import ppc_const as ppc

from binrecon.macho import load_image


@functools.lru_cache(maxsize=2)
def _object(path):
    return load_image(path)


def _body(payload, image, name):
    symbols = sorted((s for s in image["symbols"] if s["binding"] == "external" and
                      s["section"] == "__TEXT,__text"), key=lambda s: s["address"])
    section = next(s for s in image["sections"] if s["name"] == "__TEXT,__text")
    index = next(i for i, symbol in enumerate(symbols) if symbol["name"] == name)
    start = symbols[index]["address"]
    end = symbols[index + 1]["address"] if index + 1 < len(symbols) else section["address"] + section["size"]
    offset = section["offset"] + start - section["address"]
    return start, end, payload[offset:offset + end - start]


def run_capability(config_object, osd_object, case):
    if case["entry"] != "SCSIhGetCapability" or case["arguments"] != [{"region": "adapter", "offset": 24}]:
        raise ValueError("native switch runner requires the reviewed capability entry")
    raw, image = _object(config_object)
    service_raw, service_image = _object(osd_object)
    for item in (image, service_image):
        if (item["input"]["architecture"], item["input"]["endianness"],
                item["extensions"]["macho"]["header"]["file_type"]) != ("ppc", "big", 1):
            raise ValueError("native switch runner requires PPC big-endian objects")
    start, end, body = _body(raw, image, "_SCSIhGetCapability")
    _, _, service = _body(service_raw, service_image, "_OSDGetHostAddress")
    # This is the accepted production OSD leaf, copied without replacing its body.
    if len(service) != 16:
        raise ValueError("native OSD leaf extent differs")
    base, leaf, stack, adapter, sentinel = 0x10000000, 0x10008000, 0x20000000, 0x30000000, 0x40000000
    cpu = unicorn.Uc(unicorn.UC_ARCH_PPC, unicorn.UC_MODE_32 | unicorn.UC_MODE_BIG_ENDIAN)
    cpu.ctl_set_cpu_model(ppc.UC_CPU_PPC32_604)
    for address, size in ((base, 0x10000), (stack, 0x10000), (adapter, 4096), (sentinel, 4096)):
        cpu.mem_map(address, size)
    sections = {s["name"]: s for s in image["sections"]}
    for section in sections.values():
        if section["address"] + section["size"] > 0x8000:
            raise ValueError("native owner exceeds reserved extent")
        cpu.mem_write(base + section["address"], raw[section["offset"]:section["offset"] + section["size"]])
    cpu.mem_write(leaf, service)
    calls = []
    for relocation in image["extensions"]["macho"]["relocations"]:
        address = relocation["address"]
        if relocation["section"] != "__TEXT,__text" or not start <= address < end:
            continue
        kind = relocation["kind"]
        if kind == "ppc-pair-16-absolute":
            continue
        word = int.from_bytes(cpu.mem_read(base + address, 4), "big")
        if relocation["external"]:
            if kind != "ppc-br24-24-pc-relative" or relocation["target"] != "_OSDGetHostAddress" or relocation["addend"]:
                raise ValueError("unexpected native external dependency")
            word = 0x48000001 | ((leaf - base - address) & 0x03fffffc)
            calls.append(address)
        else:
            if relocation["target"] != "__TEXT,__const":
                raise ValueError("unexpected native switch relocation")
            target = base + sections[relocation["target"]]["address"] + relocation["addend"]
            if kind == "ppc-ha16-32-absolute":
                immediate = (target + 0x8000) >> 16
            elif kind == "ppc-lo16-32-absolute":
                immediate = target
            else:
                raise ValueError("unsupported native switch relocation")
            word = (word & 0xffff0000) | (immediate & 0xffff)
        cpu.mem_write(base + address, word.to_bytes(4, "big"))
    if len(calls) != 1:
        raise ValueError("native capability must execute one actual OSD leaf")
    region = next(r for r in case["memory"] if r["name"] == "adapter")
    if region["size"] != 2600 or region.get("pointers"):
        raise ValueError("native capability fixture extent differs")
    cpu.mem_write(adapter, bytes.fromhex(region["bytes"]))
    cpu.reg_write(ppc.UC_PPC_REG_1, stack + 0xf000)
    cpu.reg_write(ppc.UC_PPC_REG_3, adapter + 24)
    cpu.reg_write(ppc.UC_PPC_REG_LR, sentinel)
    saved = {r: 0x11220000 + r for r in range(13, 32)}
    for r, value in saved.items():
        cpu.reg_write(getattr(ppc, "UC_PPC_REG_" + str(r)), value)
    returned, count = False, 0

    def instruction(uc, address, size, data):
        nonlocal returned, count
        count += 1
        if address == sentinel:
            returned = True
            uc.emu_stop()
        elif count > 2000 or not (base + start <= address < base + end or leaf <= address < leaf + len(service)):
            raise ValueError("unknown or exhausted native switch control flow")

    cpu.hook_add(unicorn.UC_HOOK_CODE, instruction)
    cpu.emu_start(base + start, 0, count=2002)
    if not returned or cpu.reg_read(ppc.UC_PPC_REG_1) != stack + 0xf000 or any(
            cpu.reg_read(getattr(ppc, "UC_PPC_REG_" + str(r))) != value for r, value in saved.items()):
        raise ValueError("native capability return/callee-saved ABI differs")
    memory = {}
    for observation in case["observe"]:
        offset, size = observation["offset"], observation["size"]
        if observation["region"] != "adapter" or observation.get("pointer_fields") or not 0 <= offset <= 2600 - size:
            raise ValueError("native capability observation differs")
        memory["adapter+" + str(offset)] = bytes(cpu.mem_read(adapter + offset, size)).hex()
    if memory != case["expected"]["memory"] or case["expected"]["trace"]:
        raise ValueError("native capability differs from frozen reference: " + case["id"])
    return {"executed_case_id": case["id"], "memory": memory, "instructions": count,
            "native_body_sha256": hashlib.sha256(body).hexdigest().upper(), "callee_saved": True}
