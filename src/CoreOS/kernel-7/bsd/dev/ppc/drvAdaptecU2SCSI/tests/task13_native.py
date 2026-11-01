"""Actual mixed native/reference API execution, with bounded entry-context capture."""

OWNED = ('SCSIxMaximizeMemory', 'SCSIxNonScamValidateLun', 'SCSIxTranslateError', 'SCSIxApplyNVData', 'SCSIxBiosExist', 'SCSIxOptimaExist', 'SCSIxChkLunExist', 'SCSIxSetLunExist', 'SCSIxClearLunExist', 'SCSIxSetupBusScan', 'SCSIxSetupLunProbe', 'SCSIxQueueBusScan', 'SCSIxPostBusScan', 'SCSIxQueueSpecialIOB', 'SCSIxPostQueueSpecialIOB', 'SCSIxGetSpeed', 'SCSIxCalcScsiOption', 'SCSIxDetermineFirmwareMode', 'SCSIxGetNextSubSystemSubVendorID', 'SCSIGetFunctionPointers', 'SCSIGetNextHostDeviceType', 'SCSICreateInitializationTSCB', 'SCSIGetConfiguration', 'SCSISetConfiguration', 'SCSISizeAdapterTSCB', 'SCSICreateAdapterTSCB', 'SCSISetupAdapterTSCB', 'SCSICheckMemoryNeeded', 'SCSISetMemoryPointer', 'SCSIVerifyAdapter', 'SCSIInitialize', 'SCSISizeTargetTSCB', 'SCSICheckTargetTSCBNeeded', 'SCSICreateTargetTSCB', 'SCSIDisableIRQ', 'SCSIEnableIRQ', 'SCSIPollIRQ', 'SCSIPowerEvent', 'SCSIValidateTargetTSH', 'SCSIClearTargetTSH', 'SCSISaveState', 'SCSIRestoreState', 'SCSIProfileAdapter', 'SCSIReportAdjustableAdapterProfile', 'SCSIAdjustAdapterProfile', 'SCSIProfileTarget', 'SCSIReportAdjustableTargetProfile', 'SCSIAdjustTargetProfile', 'SCSIGetNVSize', 'SCSIGetNVOSMSegment', 'SCSIPutNVData', 'SCSIGetNVData', 'SCSIProfileNexus', 'SCSIClearNexusTSH', 'SCSIProfileNode', 'SCSIReportAdjustableNodeProfile', 'SCSIAdjustNodeProfile', 'SCSISetOSMNodeContext', 'SCSIQueueIOB', 'SCSIFrontEndISR', 'SCSIBackEndISR')

import copy
import bisect
import importlib.util
import hashlib
from pathlib import Path


def module(name):
    spec = importlib.util.spec_from_file_location("au2_api_"+name, Path(__file__).with_name(name+".py"))
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


def getter_copy(case, binary, manifest):
    """Model only the kernel copy from the real, relocated dispatch table."""
    if case["entry"] != "SCSIGetFunctionPointers":
        return case
    count = case["arguments"][1]
    if (count not in (0, 4, 168, 172) or
            case["id"] != "task13-SCSIGetFunctionPointers-"+str(count) or
            case["arguments"][0] != {"region": "table", "offset": 0}):
        raise ValueError("API unapproved getter copy identity/count")
    if (len(case["memory"]) != 1 or case["memory"][0] !=
            {"name": "table", "size": 176, "bytes": "a5"*176, "pointers": []}):
        raise ValueError("API getter destination extent/canary differs")
    runner = module("ppc_cases")
    raw, image = runner.load_image(binary)
    if hashlib.sha256(raw).hexdigest().upper() != manifest["sha256"]:
        raise ValueError("API getter arena identity differs")
    definition = manifest["definitions"]["_SCSIFuncPtrs"]
    table_path = Path(definition["object"])
    table_raw, table_image = runner.load_image(table_path)
    if (hashlib.sha256(table_raw).hexdigest().upper() !=
            "67AA7E935CBBC44826838BF5D8D6943497E706722FAE93EEBB1716231F0FC062"):
        raise ValueError("API getter accepted table object differs")
    import json
    record = json.loads(Path(__file__).with_name("task13-getter.json").read_text())
    if len(record["pointers"]) != 41 or record["size"] != 168:
        raise ValueError("API getter dispatch extent differs")
    relocations = [r for r in table_image["extensions"]["macho"]["relocations"]
                   if r["section"] == "__DATA,__data" and
                   definition["source_address"] <= r["address"] < definition["source_address"]+168]
    wanted = {definition["source_address"]+int(offset): "_"+name for offset, name in record["pointers"].items()}
    if (len(relocations) != 41 or {r["address"]: r["target"] for r in relocations} != wanted or
            any(r["kind"] != "ppc-vanilla-32-absolute" or not r["external"] or r["addend"] for r in relocations)):
        raise ValueError("API getter dispatch symbolic relocation differs")
    section = next(s for s in image["sections"] if s["address"] <= definition["arena_address"] and
                   definition["arena_address"]+172 <= s["address"]+s["size"])
    offset = section["offset"]+definition["arena_address"]-section["address"]
    source = raw[offset:offset+172]
    if source[:4] != bytes.fromhex("00000004") or source[168:172] != bytes.fromhex("00000004"):
        raise ValueError("API getter version/adjacent scalar differs")
    for offset, name in record["pointers"].items():
        actual = manifest["definitions"]["_"+name]["arena_address"]
        if int.from_bytes(source[int(offset):int(offset)+4], "big") != actual:
            raise ValueError("API getter relocated dispatch pointer differs")
    result = __import__("copy").deepcopy(case)
    outcomes = result["external_outcomes"]
    frozen = bytes.fromhex(record["reference_bytes"])+bytes.fromhex("00000004")
    expected = {"service": "_fast_bcopy", "arguments": ["SCSIFuncPtrs", "table+0", count],
                "writes": [{"region": "table", "offset": 0, "bytes": frozen[:count].hex()}]}
    if outcomes != [expected]:
        raise ValueError("API getter frozen source/destination/count differs")
    outcomes[0]["writes"][0]["bytes"] = source[:count].hex()
    return result


def run(binary, case, context=None, entries=None, manifest=None):
    runner = module("ppc_cases")
    payload, image = runner.load_image(binary)
    symbols = {s["name"].removeprefix("_"): s["address"] for s in image["symbols"] if s["section"]}
    if context is not None:
        allowed_image = (image["input"]["sha256"] == "D01D748C10117FBFCEB25F99D88A63895C3BAC6C09A5110AD358E583316494BD" or
                         manifest is not None and image["input"]["sha256"] == manifest["sha256"])
        if (not allowed_image or case["entry"] != "SCSIInitialize" or case["evidence"]["entry_address"] != 0x1a4644 or
                context not in (0x12345635, 0x89abcda6)):
            raise ValueError("unapproved API caller entry/context")
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
            raise ValueError("unresolved API operation owner bounds")
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
    coverage = {}
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
                if address in words:
                    current = owner(address)
                    if current["name"] in OWNED:
                        coverage.setdefault(current["name"], set()).add(address)
                if pending[0] and pending[0][1] == address and address in at_entry:
                    frames.append({"body": at_entry[address], "return": pending[0][0]+4})
                    caller = owner(pending[0][0])
                    if caller["name"] in OWNED:
                        calls.append({"owner": caller["name"], "owner_address": caller["reference_address"],
                                      "callsite": pending[0][0], "bytes": words[pending[0][0]].to_bytes(4,"big").hex(),
                                      "callee": at_entry[address]["name"], "callee_address": at_entry[address]["reference_address"],
                                      "arguments": [uc.reg_read(getattr(runner.ppc,"UC_PPC_REG_"+str(r))) for r in range(3,11)]})
                if address in at_entry and at_entry[address]["name"] in OWNED:
                    captures.append({"entry": at_entry[address]["name"], "address": address,
                                     "r28": uc.reg_read(runner.ppc.UC_PPC_REG_28)})
                for name in entries or []:
                    if address == symbols[name] and name not in OWNED:
                        captures.append({"entry": name, "address": address,
                                         "r28": uc.reg_read(runner.ppc.UC_PPC_REG_28)})
                if address in (symbols["OSMReadUExact8"], symbols["OSMWriteUExact8"]):
                    callsite = previous[0]
                    word = words.get(callsite)
                    if word is None or bytes(uc.mem_read(callsite, 4)) != word.to_bytes(4, "big"):
                        raise ValueError("API MMIO linking instruction changed")
                    if pending[0] != (callsite, address) or not word & 1:
                        raise ValueError("unresolved API primitive tailcall/veneer")
                    if uc.reg_read(runner.ppc.UC_PPC_REG_LR) != callsite+4:
                        raise ValueError("API MMIO return link differs")
                    operation_owner = owner(callsite)
                    api = next((f["body"] for f in reversed(frames) if f["body"]["name"] in OWNED), None)
                    name = "OSMReadUExact8" if address == symbols["OSMReadUExact8"] else "OSMWriteUExact8"
                    primitive[0] = {"owner": operation_owner["name"], "owner_address": operation_owner["reference_address"],
                                    "owner_code_address": operation_owner["start"], "callsite": callsite,
                                    "callsite_bytes": word.to_bytes(4, "big").hex(), "primitive": name,
                                    "primitive_address": address,
                                    "api_caller": None if api is None else {"name": api["name"], "address": api["reference_address"]}}
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
                        if region and body["name"] in OWNED:
                            publications.append({"owner": body["name"], "region": region[2], "offset": address-region[0],
                                                 "size": size, "value": value, "instruction": pc,
                                                 "bytes": words[pc].to_bytes(4,"big").hex()})
                    return
                record = primitive[0]
                kind = "write" if access == runner.unicorn.UC_MEM_WRITE else "read"
                pc = uc.reg_read(runner.ppc.UC_PPC_REG_PC)
                body = owner(pc)
                if record is None or body["name"] != record["primitive"] or kind != ("read" if record["primitive"] == "OSMReadUExact8" else "write"):
                    raise ValueError("API MMIO access lacks its actual primitive call")
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
        result = runner.run_case(binary, case, module("task13_inputs").contracts())
    except Exception as error:
        error.add_note("API architectural entry observations: "+repr(captures))
        raise
    finally:
        runner.unicorn.Uc = original
    if len(instances) != 1 or not result["returned_to_sentinel"] or result["unknown_calls"]:
        raise ValueError("API supplementary sentinel/unknown-call guard differs")
    cpu = instances[0]
    if (cpu.reg_read(runner.ppc.UC_PPC_REG_1) != runner.STACK+runner.STACK_SIZE-4096 or
            any(cpu.reg_read(getattr(runner.ppc, "UC_PPC_REG_"+str(r))) != v for r, v in saved.items())):
        raise ValueError("API supplementary SP/nonvolatile ABI differs")
    return {**result, "entries": captures, "nonvolatile_preserved": saved,
            "stack_pointer": cpu.reg_read(runner.ppc.UC_PPC_REG_1),
            "owned_instructions": {name: sorted(addresses) for name, addresses in sorted(coverage.items())},
            "mmio_operations": list(operations.values()), "publications": publications, "api_calls": calls}
