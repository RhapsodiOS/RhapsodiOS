"""Bounded native negotiation leaves; unexpected transfers fail closed."""

import functools
import hashlib

import unicorn
from unicorn import ppc_const as ppc

from binrecon.macho import load_image


@functools.lru_cache(maxsize=2)
def _object(path):
    return load_image(path)


def body(binary, name, allow_linked=False):
    raw, image = _object(binary)
    if ((image["input"]["architecture"], image["input"]["endianness"]) != ("ppc", "big") or
            image["extensions"]["macho"]["header"]["file_type"] not in ((1, 2) if allow_linked else (1,))):
        raise ValueError("native negotiation requires PPC big-endian MH_OBJECT")
    symbols = sorted((s for s in image["symbols"] if s["binding"] == "external" and
                      s["section"] == "__TEXT,__text"), key=lambda s: s["address"])
    section = next(s for s in image["sections"] if s["name"] == "__TEXT,__text")
    index = next(i for i, symbol in enumerate(symbols) if symbol["name"] == "_" + name)
    start = symbols[index]["address"]
    end = symbols[index + 1]["address"] if index + 1 < len(symbols) else section["address"] + section["size"]
    offset = section["offset"] + start - section["address"]
    return start, end, raw[offset:offset + end - start], image


def access_widths(binary):
    result = {}
    names = ["SCSIhAIC78XXClearScsiOffset", "SCSIhAICBayonetClearScsiOffset",
             "SCSIhSwapping32UpdateFast20HostMem", "SCSIhSwapping32UpdateXferOptionHostMem",
             "SCSIhStandardAdvUpdateXferOptionHostMem", "SCSIhSwappingAdvUpdateXferOptionHostMem",
             "SCSIhAIC78XXIgnoreWideResCalc", "SCSIhAICBayonetIgnoreWideResCalc",
             "SCSIhNegotiate", "SCSIhExtMsgi", "SCSIhInitiateWide", "SCSIhVerifyWideResponse",
             "SCSIhInitiateSync", "SCSIhVerifySyncResponse", "SCSIhRespondToWide", "SCSIhRespondToSync"]
    for name in names:
        _, _, code, _ = body(binary, name, allow_linked=True)
        words = [int.from_bytes(code[i:i+4], "big") for i in range(0, len(code), 4)]
        memory = []
        for index, word in enumerate(words):
            op = word >> 26
            if op not in (32, 34, 36, 38, 40, 44):
                continue
            offset = (word & 0xffff) - (0x10000 if word & 0x8000 else 0)
            memory.append({"instruction_offset": index * 4, "base": (word >> 16) & 31,
                           "offset": offset, "size": {32: 4, 34: 1, 36: 4, 38: 1, 40: 2, 44: 2}[op],
                           "access": "write" if op in (36, 38, 44) else "read"})
        if name.endswith("ClearScsiOffset"):
            offsets = (4, 6) if "Bayonet" in name else (4,)
            accesses = [a for a in memory if a["base"] != 1 and a["offset"] in offsets]
            if ([(a["access"], a["offset"], a["size"]) for a in accesses] !=
                    [("read", offset, 1) for offset in offsets] + [("write", offset, 1) for offset in offsets]):
                raise ValueError("negotiation byte offset access differs: " + name)
        elif name.endswith("HostMem"):
            reverse = [w for w in words if w >> 26 == 31 and (w >> 1) & 1023 == 918]
            length = 32 if "Swapping32" in name else 64
            if (0x38800000 | length) not in words:
                raise ValueError("negotiation cache extent differs: " + name)
            if length == 64:
                if len(reverse) != 1:
                    raise ValueError("negotiation reversed halfword store differs: " + name)
                accesses = [{"instruction_offset": words.index(reverse[0]) * 4, "size": 2,
                             "access": "write", "reversed": True}]
            else:
                offset = 1 if "Fast20" in name else 29
                accesses = [a for a in memory if a["base"] != 1 and a["access"] == "write" and a["offset"] == offset]
                if len(accesses) != 1 or accesses[0]["size"] != 1:
                    raise ValueError("negotiation host byte store differs: " + name)
        else:
            saved = next(((w >> 16) & 31 for w in words if w >> 26 == 31 and
                          (w >> 1) & 1023 == 444 and (w >> 21) & 31 == 4 and
                          (w >> 11) & 31 == 4), 4)
            if name.endswith("IgnoreWideResCalc"):
                accesses = [a for a in memory if a["base"] == saved and a["offset"] == 20]
                if [(a["access"], a["size"]) for a in accesses] != [("read", 4), ("write", 4), ("write", 4)]:
                    raise ValueError("negotiation residue publication differs: " + name)
            else:
                accesses = [a for a in memory if a["base"] == saved and a["access"] == "write" and
                            a["offset"] < 40 and a["offset"] + a["size"] > 33]
                if not accesses or any(a["size"] != 1 for a in accesses):
                    raise ValueError("negotiation message byte store differs: " + name)
        result[name] = accesses
    return result


def run_scalar(binary, case):
    start, end, code, image = body(binary, case["entry"])
    if any(start <= r["address"] < end and r["section"] == "__TEXT,__text"
           for r in image["extensions"]["macho"]["relocations"]):
        raise ValueError("scalar negotiation leaf has a native relocation")
    if case["observe"] or case["expected"]["trace"] or case["return_kind"] != "scalar":
        raise ValueError("scalar negotiation leaf observation differs")
    base, stack, sentinel = 0x10000000, 0x20000000, 0x40000000
    cpu = unicorn.Uc(unicorn.UC_ARCH_PPC, unicorn.UC_MODE_32 | unicorn.UC_MODE_BIG_ENDIAN)
    cpu.ctl_set_cpu_model(ppc.UC_CPU_PPC32_604)
    for address, size in ((base, 4096), (stack, 0x10000), (sentinel, 4096)):
        cpu.mem_map(address, size)
    if len(code) > 4096:
        raise ValueError("scalar negotiation leaf exceeds bounded code extent")
    cpu.mem_write(base, code)
    regions = {}
    for index, region in enumerate(case["memory"]):
        address = 0x30000000 + index * 0x10000
        if region["size"] > 4096:
            raise ValueError("scalar negotiation leaf exceeds bounded memory extent")
        regions[region["name"]] = (address, region["size"])
        cpu.mem_map(address, 4096)
        cpu.mem_write(address, bytes.fromhex(region["bytes"]))

    def argument(value):
        if not isinstance(value, dict):
            return value & 0xffffffff
        address, extent = regions[value["region"]]
        if not 0 <= value["offset"] <= extent:
            raise ValueError("native leaf pointer exceeds region")
        return address + value["offset"]

    for region in case["memory"]:
        for field in region.get("pointers", []):
            cpu.mem_write(regions[region["name"]][0] + field["offset"],
                          argument(field["value"]).to_bytes(4, "big"))
    for index, value in enumerate(case["arguments"]):
        cpu.reg_write(getattr(ppc, "UC_PPC_REG_" + str(index + 3)), argument(value))
    cpu.reg_write(ppc.UC_PPC_REG_1, stack + 0xf000)
    cpu.reg_write(ppc.UC_PPC_REG_LR, sentinel)
    saved = {r: 0x11220000 + r for r in range(13, 32)}
    for register, value in saved.items():
        cpu.reg_write(getattr(ppc, "UC_PPC_REG_" + str(register)), value)
    returned, count = False, 0

    def instruction(uc, address, size, data):
        nonlocal returned, count
        count += 1
        if address == sentinel:
            returned = True
            uc.emu_stop()
        elif count > 2000 or not base <= address < base + len(code):
            raise ValueError("unknown or exhausted native negotiation control flow")

    cpu.hook_add(unicorn.UC_HOOK_CODE, instruction)
    cpu.emu_start(base, 0, count=2002)
    if (not returned or cpu.reg_read(ppc.UC_PPC_REG_1) != stack + 0xf000 or
            any(cpu.reg_read(getattr(ppc, "UC_PPC_REG_" + str(register))) != value
                for register, value in saved.items())):
        raise ValueError("native negotiation return/callee-saved ABI differs")
    value = cpu.reg_read(ppc.UC_PPC_REG_3)
    if value != case["expected"]["return"]:
        raise ValueError("native negotiation scalar result differs")
    return {"executed_case_id": case["id"], "return": value, "instructions": count,
            "body_sha256": hashlib.sha256(code).hexdigest().upper()}
