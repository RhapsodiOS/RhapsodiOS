"""Recovery SCB publication widths and ordering in actual PPC objects."""

from binrecon.macho import load_image


def body(binary, name):
    raw, image = load_image(binary)
    if (image["input"]["architecture"], image["input"]["endianness"]) != ("ppc", "big"):
        raise ValueError("recovery native image requires PPC big-endian")
    symbols = sorted((s for s in image["symbols"] if s["binding"] == "external" and
                      s["section"] == "__TEXT,__text"), key=lambda s: s["address"])
    section = next(s for s in image["sections"] if s["name"] == "__TEXT,__text")
    index = next(i for i, symbol in enumerate(symbols) if symbol["name"] == "_" + name)
    start = symbols[index]["address"]
    end = symbols[index + 1]["address"] if index + 1 < len(symbols) else section["address"] + section["size"]
    offset = section["offset"] + start - section["address"]
    return start, raw[offset:offset + end - start], image


def access_widths(binary):
    result = {}
    for mode in ("Swapping32", "SwappingAdv"):
        for suffix in ("RequestSense", "ActiveAbort"):
            name = "SCSIh" + mode + suffix
            _, code, _ = body(binary, name)
            words = [int.from_bytes(code[i:i+4], "big") for i in range(0, len(code), 4)]
            # Follow only the proved HIOB->SCB descriptor->virtual-address chain.
            regs = {4: "hiob"}
            accesses = []
            for index, word in enumerate(words):
                op, rt, ra, rb = word >> 26, (word >> 21) & 31, (word >> 16) & 31, (word >> 11) & 31
                offset = (word & 0xffff) - (0x10000 if word & 0x8000 else 0)
                if op == 31 and (word >> 1) & 1023 == 444 and rt == rb:
                    regs[ra] = regs.get(rt)
                elif op == 32:
                    regs[rt] = "descriptor" if regs.get(ra) == "hiob" and offset == 24 else (
                        "scb" if regs.get(ra) == "descriptor" and offset == 12 else None)
                elif op in (34, 38, 40, 44, 36) and regs.get(ra) == "scb":
                    accesses.append({"instruction_offset": index * 4, "offset": offset,
                                     "size": {34: 1, 38: 1, 40: 2, 44: 2, 36: 4}[op],
                                     "access": "write" if op in (38, 44, 36) else "read"})
            stores = [(a["offset"], a["size"]) for a in accesses if a["access"] == "write"]
            if suffix == "RequestSense":
                expected = ([(3,1),(8,1),(10,1),(11,1),(9,1),(13,1),(1,1),(12,1),(26,1)]
                            if mode == "Swapping32" else
                            [(12,1),(14,1),(15,1),(24,1),(26,1),(27,1),(25,1),(29,1),(28,1),(13,1),(38,1),(6,1)])
                if stores != expected:
                    raise ValueError("recovery sense byte publication differs: " + name + repr(stores))
                for xo in (662, 918):
                    if sum(w >> 26 == 31 and (w >> 1) & 1023 == xo for w in words) != 1:
                        raise ValueError("recovery sense reversed word/halfword store differs: " + name)
            elif mode == "SwappingAdv":
                if stores != [(38,1),(38,1),(16,1),(17,1)]:
                    raise ValueError("recovery abort dual byte publication differs: " + name + repr(stores))
            elif stores != [(0,1),(1,1),(4,1),(5,1)]:
                raise ValueError("recovery abort byte publication differs: " + name + repr(stores))
            footprint = [(a["access"], a["offset"], a["size"]) for a in accesses]
            if suffix == "RequestSense":
                if mode == "Swapping32":
                    expected_accesses = [("write", offset, width) for offset, width in expected]
                else:
                    expected_accesses = [("read",12,1),("write",12,1)] + [
                        ("write",o,1) for o in (14,15,24,26,27,25)] + [("read",13,1)] + [
                        ("write",o,1) for o in (29,28,13,38,6)]
            elif mode == "Swapping32":
                expected_accesses = [("read",0,1),("read",1,1)] + [("write",o,1) for o in (0,1,4,5)]
            else:
                expected_accesses = [("read",38,1)] + [("write",o,1) for o in (38,38,16,17)]
            if footprint != expected_accesses:
                raise ValueError("recovery ordinary SCB access ordering differs: " + name + repr(footprint))
            result[name] = accesses
    return result


def counter_guards(binary):
    result = {}
    for name, immediate in (("SCSIhCheckLength", 0x8000), ("SCSIhIntSrst", 0x80),
                            ("SCSIhCheckCondition", 0x80)):
        _, code, _ = body(binary, name)
        words = [int.from_bytes(code[i:i+4], "big") for i in range(0, len(code), 4)]
        init = next((i for i,w in enumerate(words) if w >> 26 == 15 and
                     (w >> 16) & 31 == 0 and w & 0xffff == immediate), None)
        if init is None:
            raise ValueError("recovery counter initialization differs: " + name)
        register = (words[init] >> 21) & 31
        decrement = next((i for i,w in enumerate(words) if w >> 26 == 14 and
                          (w >> 21) & 31 == register and (w >> 16) & 31 == register and
                          w & 0xffff == 0xffff), None)
        compare = next((i for i,w in enumerate(words) if w >> 26 == 11 and
                        (w >> 16) & 31 == register and w & 0xffff == 0), None)
        backedge = next((i for i,w in enumerate(words) if i > max(decrement or 0, compare or 0) and
                         w >> 26 == 16 and w & 0x8000), None)
        if (decrement is None or compare is None or backedge is None or init >= decrement or
                (name == "SCSIhCheckLength" and compare <= decrement) or
                (name != "SCSIhCheckLength" and compare >= decrement)):
            raise ValueError("recovery counter decrement/comparison/backedge differs: " + name)
        result[name] = {"initial_immediate": immediate, "register": register,
                        "initialize": init * 4, "decrement": decrement * 4,
                        "compare": compare * 4, "backedge": backedge * 4}
    for name in ("SCSIhIntSrst", "SCSIhIntIOError", "SCSIhBadSeq"):
        _, code, _ = body(binary, name)
        words = [int.from_bytes(code[i:i+4], "big") for i in range(0, len(code), 4)]
        if words.count(0x7c0004ac) != 1:
            raise ValueError("recovery synchronization differs: " + name)
        if name != "SCSIhBadSeq" and not any(w >> 26 == 10 and w & 0xffff == 3999 for w in words):
            raise ValueError("recovery finite4000 settle guard differs: " + name)
        result.setdefault(name, {})["sync"] = words.index(0x7c0004ac) * 4
    return result


def compare_status(reference, binary, cases):
    import unicorn
    from unicorn import ppc_const as ppc
    result = []
    for case in cases:
        observations = []
        for path in (reference, binary):
            start, code, image = body(path, "SCSIhSetStat")
            if any(start <= r["address"] < start + len(code) and r["section"] == "__TEXT,__text"
                   for r in image["extensions"]["macho"]["relocations"]):
                raise ValueError("status leaf has a relocation")
            base, stack, hiob, sentinel = 0x10000000, 0x20000000, 0x30000000, 0x40000000
            cpu = unicorn.Uc(unicorn.UC_ARCH_PPC, unicorn.UC_MODE_32 | unicorn.UC_MODE_BIG_ENDIAN)
            cpu.ctl_set_cpu_model(ppc.UC_CPU_PPC32_604)
            for address, size in ((base,4096),(stack,65536),(hiob,4096),(sentinel,4096)):
                cpu.mem_map(address,size)
            cpu.mem_write(base,code)
            raw = bytes.fromhex(case["memory"][0]["bytes"])
            cpu.mem_write(hiob,raw)
            cpu.reg_write(ppc.UC_PPC_REG_1,stack+61440)
            cpu.reg_write(ppc.UC_PPC_REG_3,hiob)
            cpu.reg_write(ppc.UC_PPC_REG_LR,sentinel)
            saved = {r: 0xa5000000+r for r in range(14,32)}
            for register,value in saved.items():
                cpu.reg_write(getattr(ppc,"UC_PPC_REG_"+str(register)),value)
            trace, returned, count = [], [False], [0]
            def instruction(uc,address,size,data):
                count[0] += 1
                if address == sentinel:
                    returned[0] = True
                    uc.emu_stop()
                elif not base <= address < base+len(code):
                    raise ValueError("status leaf unexpected transfer")
            def memory(uc,access,address,size,value,data):
                if hiob <= address < hiob+56:
                    if address+size > hiob+56:
                        raise ValueError("status access exceeds HIOB")
                    trace.append(("read" if access==unicorn.UC_MEM_READ else "write",address-hiob,size))
                elif not stack <= address < stack+65536:
                    raise ValueError("status leaf unexpected memory access")
            cpu.hook_add(unicorn.UC_HOOK_CODE,instruction)
            cpu.hook_add(unicorn.UC_HOOK_MEM_READ | unicorn.UC_HOOK_MEM_WRITE,memory)
            cpu.emu_start(base,0,count=10000)
            if (not returned[0] or cpu.reg_read(ppc.UC_PPC_REG_1)!=stack+61440 or
                    any(cpu.reg_read(getattr(ppc,"UC_PPC_REG_"+str(r)))!=v for r,v in saved.items())):
                raise ValueError("status leaf return/callee-saved ABI differs")
            final = bytes(cpu.mem_read(hiob,56)).hex()
            if final != case["expected"]["memory"]["hiob+0"]:
                raise ValueError("status native/reference memory differs")
            observations.append({"memory":final,"trace":trace,"instructions":count[0]})
        if observations[0]["trace"] != observations[1]["trace"]:
            raise ValueError("status ordinary access ordering differs: "+case["id"])
        result.append({"id":case["id"],"reference":observations[0],"native":observations[1]})
    return result
