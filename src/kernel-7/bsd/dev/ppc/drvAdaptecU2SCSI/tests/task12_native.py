"""Actual mixed native/reference HIM execution, with bounded entry-context capture."""

import copy
import bisect
import importlib.util
from pathlib import Path


def module(name):
    spec = importlib.util.spec_from_file_location("au2_him_"+name, Path(__file__).with_name(name+".py"))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def adapt(case, manifest):
    result = copy.deepcopy(case)
    definitions = manifest["definitions"]
    if "_"+case["entry"] in definitions:
        result["size"] = definitions["_"+case["entry"]]["size"]
    result["internal"] = []
    for body in case["internal"]:
        native = definitions.get("_"+body["entry"])
        result["internal"].append({**body, "size": native["size"] if native else body["size"]})
        if native:
            result["internal"].append({"entry": "au2_reference_"+body["entry"], "size": body["size"]})
    # These entry observers are compared separately by the supplementary capture.
    # No CPU instruction, callback, MMIO outcome or memory observation changes.
    result.pop("observe_calls", None)
    result["expected"]["trace"] = [e for e in result["expected"]["trace"] if "entry" not in e]
    return result


def switch_graph(path):
    leaf = module("task11_native")
    start, code, image = leaf.body(path, "SCSIHQueueSpecialHIOB")
    raw, _ = module("ppc_cases").load_image(path)
    const = next(s for s in image["sections"] if s["name"] == "__TEXT,__const")
    rel = {r["address"]: r for r in image["extensions"]["macho"]["relocations"]
           if r["section"] == "__TEXT,__text" and r["kind"] != "ppc-pair-16-absolute" and start <= r["address"] < start+len(code)}
    tables = {r["addend"] for r in rel.values() if r["kind"] == "ppc-ha16-32-absolute" and r["target"] == "__TEXT,__const"}
    if len(tables) != 1:
        raise ValueError("HIM native switch table relocation differs")
    offset = tables.pop()
    if offset < 0 or offset+32 > const["size"]:
        raise ValueError("HIM native switch table exceeds const")
    words = {start+i: int.from_bytes(code[i:i+4],"big") for i in range(0,len(code),4)}
    if (not any(w >> 26 == 10 and w & 65535 == 7 for w in words.values()) or
            not any(w >> 26 in (12,14) and w & 65535 == 65535 for w in words.values()) or
            0x4e800420 not in words.values()):
        raise ValueError("HIM native switch normalization/guard/dispatch differs")
    table = const["address"]+offset
    targets = [table+int.from_bytes(raw[const["offset"]+offset+i*4:const["offset"]+offset+i*4+4],"big",signed=True) for i in range(8)]
    wanted = [("SCSIhAbortTask",), ("SCSIhScsiBusReset","SCSIrCompleteSpecialHIOB"),
              ("indirect",), (), (), ("SCSIrCompleteSpecialHIOB",), ("SCSIhAbortTaskSet",), ()]
    cases = []
    for index, target in enumerate(targets):
        todo, visited, calls, syncs = [target], set(), set(), set()
        while todo:
            address = todo.pop()
            if address in visited:
                continue
            if address not in words:
                raise ValueError("HIM native switch path exceeds body")
            visited.add(address); w = words[address]; op = w >> 26
            if w == 0x4e800020:
                continue
            if w == 0x7c0004ac:
                syncs.add(address)
            if address in rel and rel[address]["kind"] == "ppc-br24-24-pc-relative":
                r=rel[address]
                if not r["external"] or not w & 1:
                    raise ValueError("HIM native switch callee relocation differs")
                calls.add(r["target"].removeprefix("_"));todo.append(address+4)
            elif w in (0x4e800421,0x4e800021):
                calls.add("indirect");todo.append(address+4)
            elif op == 18:
                if w & 3:
                    raise ValueError("HIM native switch unexpected branch form")
                d=w & 0x3fffffc;todo.append(address+d-(0x4000000 if d & 0x2000000 else 0))
            elif op == 16:
                if w & 3:
                    raise ValueError("HIM native switch unexpected conditional form")
                d=w & 65532;todo.extend((address+4,address+d-(65536 if d & 32768 else 0)))
            else:
                todo.append(address+4)
        if calls != set(wanted[index]) or bool(syncs) != (index != 4):
            raise ValueError("HIM native switch path/call/sync differs: "+str(index))
        cases.append({"index":index,"raw_function":index+1,"target":target,"calls":sorted(calls),
                      "sync":sorted(syncs),"instructions":sorted(visited)})
    if targets[3] != targets[7]:
        raise ValueError("HIM native switch sync alias differs")
    # The out-of-range guard must branch to the same no-sync epilog as index4.
    guard = next(a for a,w in words.items() if w >> 26 == 10 and w & 65535 == 7)+4
    w=words[guard];d=w & 65532
    if w >> 26 != 16 or guard+d-(65536 if d & 32768 else 0) != targets[4]:
        raise ValueError("HIM native switch default alias differs")
    return {"owner":"SCSIHQueueSpecialHIOB","table":table,"cases":cases,"default_target":targets[4]}


def run(binary, case, context=None, entries=None, manifest=None):
    runner = module("ppc_cases")
    payload, image = runner.load_image(binary)
    symbols = {s["name"].removeprefix("_"): s["address"] for s in image["symbols"] if s["section"]}
    if context is not None:
        allowed_image = (image["input"]["sha256"] == "D01D748C10117FBFCEB25F99D88A63895C3BAC6C09A5110AD358E583316494BD" or
                         manifest is not None and image["input"]["sha256"] == manifest["sha256"])
        if (not allowed_image or case["entry"] != "SCSIRInitialize" or case["evidence"]["entry_address"] != 0x1a2558 or
                context not in (0x12345635, 0x89abcda6)):
            raise ValueError("unapproved HIM caller entry/context")
    bodies = []
    for function in runner.DRIVER_FUNCTIONS:
        name = function["names"][0].removeprefix("_")
        bodies.append({"name": name, "start": function["address"], "size": function["size"],
                       "reference_address": function["address"]})
    reference_names = {b["name"]: b for b in bodies}
    for name, record in (manifest or {}).get("definitions", {}).items():
        name = name.removeprefix("_")
        if name in reference_names:
            bodies.append({"name": name, "start": record["arena_address"], "size": record["size"],
                           "reference_address": reference_names[name]["start"]})
    bodies.sort(key=lambda b: b["start"])
    starts = [b["start"] for b in bodies]
    at_entry = {b["start"]: b for b in bodies}

    def owner(address):
        index = bisect.bisect_right(starts, address)-1
        if index < 0 or address >= bodies[index]["start"]+bodies[index]["size"]:
            raise ValueError("unresolved HIM operation owner bounds")
        return bodies[index]

    words = {}
    for body in bodies:
        section = next(s for s in image["sections"] if s["address"] <= body["start"] and
                       body["start"]+body["size"] <= s["address"]+s["size"])
        offset = section["offset"]+body["start"]-section["address"]
        for position in range(0, body["size"], 4):
            words[body["start"]+position] = int.from_bytes(payload[offset+position:offset+position+4], "big")
    mmio, regions, region_address = [], [], runner.REGION_BASE
    for region in case["memory"]:
        regions.append((region_address, region["size"], region["name"]))
        if "mmio" in region:
            mmio.append((region_address, region["size"], region["name"]))
        region_address += (region["size"]+4095)&~4095
    captures, instances, saved = [], [], {r: 0xa5000000+r for r in range(14, 32)}
    operations, publications, calls = {}, [], []
    if context is not None:
        saved[28] = context
    original = runner.unicorn.Uc

    def create(*args, **kwargs):
        cpu = original(*args, **kwargs)
        instances.append(cpu)
        start = cpu.emu_start

        def execute(*args, **kwargs):
            for register, value in saved.items():
                cpu.reg_write(getattr(runner.ppc, "UC_PPC_REG_"+str(register)), value)

            previous, pending, primitive = [None], [None], [None]
            frames = [{"body": owner(symbols[case["entry"]]), "return": runner.SENTINEL}]

            def observe(uc, address, size, data):
                while len(frames) > 1 and address == frames[-1]["return"]:
                    frames.pop()
                if pending[0] and pending[0][1] == address and address in at_entry:
                    frames.append({"body": at_entry[address], "return": pending[0][0]+4})
                    caller = owner(pending[0][0])
                    if caller["name"].startswith("SCSIH"):
                        calls.append({"owner": caller["name"], "owner_address": caller["reference_address"],
                                      "callsite": pending[0][0], "bytes": words[pending[0][0]].to_bytes(4,"big").hex(),
                                      "callee": at_entry[address]["name"], "callee_address": at_entry[address]["reference_address"],
                                      "arguments": [uc.reg_read(getattr(runner.ppc,"UC_PPC_REG_"+str(r))) for r in range(3,11)]})
                if address in at_entry and at_entry[address]["name"].startswith("SCSIH"):
                    captures.append({"entry": at_entry[address]["name"], "address": address,
                                     "r28": uc.reg_read(runner.ppc.UC_PPC_REG_28)})
                for name in entries or []:
                    if address == symbols[name] and not name.startswith("SCSIH"):
                        captures.append({"entry": name, "address": address,
                                         "r28": uc.reg_read(runner.ppc.UC_PPC_REG_28)})
                if address in (symbols["OSMReadUExact8"], symbols["OSMWriteUExact8"]):
                    callsite = previous[0]
                    word = words.get(callsite)
                    if word is None or bytes(uc.mem_read(callsite, 4)) != word.to_bytes(4, "big"):
                        raise ValueError("HIM MMIO linking instruction changed")
                    if pending[0] != (callsite, address) or not word & 1:
                        raise ValueError("unresolved HIM primitive tailcall/veneer")
                    if uc.reg_read(runner.ppc.UC_PPC_REG_LR) != callsite+4:
                        raise ValueError("HIM MMIO return link differs")
                    operation_owner = owner(callsite)
                    him = next((f["body"] for f in reversed(frames) if f["body"]["name"].startswith("SCSIH")), None)
                    name = "OSMReadUExact8" if address == symbols["OSMReadUExact8"] else "OSMWriteUExact8"
                    primitive[0] = {"owner": operation_owner["name"], "owner_address": operation_owner["reference_address"],
                                    "owner_code_address": operation_owner["start"], "callsite": callsite,
                                    "callsite_bytes": word.to_bytes(4, "big").hex(), "primitive": name,
                                    "primitive_address": address,
                                    "him_caller": None if him is None else {"name": him["name"], "address": him["reference_address"]}}
                word = words.get(address)
                pending[0] = None
                if word is not None and word & 1:
                    if word >> 26 == 18 and not word & 2:
                        delta = word & 0x3fffffc
                        pending[0] = (address, address+delta-(0x4000000 if delta & 0x2000000 else 0))
                    elif word == 0x4e800021:
                        pending[0] = (address, uc.reg_read(runner.ppc.UC_PPC_REG_LR))
                    elif word == 0x4e800421:
                        pending[0] = (address, uc.reg_read(runner.ppc.UC_PPC_REG_CTR))
                previous[0] = address

            def memory(uc, access, address, size, value, data):
                region = next((r for r in mmio if r[0] <= address and address+size <= r[0]+r[1]), None)
                if region is None:
                    pc = uc.reg_read(runner.ppc.UC_PPC_REG_PC)
                    if access == runner.unicorn.UC_MEM_WRITE and pc in words:
                        body = owner(pc)
                        region = next((r for r in regions if r[0] <= address and address+size <= r[0]+r[1]), None)
                        if region and body["name"].startswith("SCSIH"):
                            publications.append({"owner": body["name"], "region": region[2], "offset": address-region[0],
                                                 "size": size, "value": value, "instruction": pc,
                                                 "bytes": words[pc].to_bytes(4,"big").hex()})
                    return
                record = primitive[0]
                kind = "write" if access == runner.unicorn.UC_MEM_WRITE else "read"
                pc = uc.reg_read(runner.ppc.UC_PPC_REG_PC)
                body = owner(pc)
                if record is None or body["name"] != record["primitive"] or kind != ("read" if record["primitive"] == "OSMReadUExact8" else "write"):
                    raise ValueError("HIM MMIO access lacks its actual primitive call")
                record = {**record, "offset": address-region[0], "size": size, "direction": kind,
                          "primitive_instruction": pc, "primitive_bytes": bytes(uc.mem_read(pc, 4)).hex()}
                key = tuple(str(record[k]) for k in sorted(record))
                if key not in operations:
                    operations[key] = {**record, "count": 0}
                operations[key]["count"] += 1
                primitive[0] = None
            cpu.hook_add(runner.unicorn.UC_HOOK_CODE, observe)
            cpu.hook_add(runner.unicorn.UC_HOOK_MEM_READ | runner.unicorn.UC_HOOK_MEM_WRITE, memory)
            return start(*args, **kwargs)
        cpu.emu_start = execute
        return cpu
    runner.unicorn.Uc = create
    try:
        result = runner.run_case(binary, case, module("task12_inputs").contracts())
    finally:
        runner.unicorn.Uc = original
    if len(instances) != 1 or not result["returned_to_sentinel"] or result["unknown_calls"]:
        raise ValueError("HIM supplementary sentinel/unknown-call guard differs")
    cpu = instances[0]
    if (cpu.reg_read(runner.ppc.UC_PPC_REG_1) != runner.STACK+runner.STACK_SIZE-4096 or
            any(cpu.reg_read(getattr(runner.ppc, "UC_PPC_REG_"+str(r))) != v for r, v in saved.items())):
        raise ValueError("HIM supplementary SP/nonvolatile ABI differs")
    return {**result, "entries": captures, "nonvolatile_preserved": saved,
            "mmio_operations": list(operations.values()), "publications": publications, "him_calls": calls}
