"""Actual PPC resource leaves; the public runner's ABI remains unchanged."""

import copy
import hashlib
from binrecon.macho import load_image
import unicorn
from unicorn import ppc_const as ppc


def body(path, name):
    raw, image = load_image(path)
    if (image["input"]["architecture"], image["input"]["endianness"]) != ("ppc", "big"):
        raise ValueError("resource leaf requires PPC big-endian")
    symbols = sorted((s for s in image["symbols"] if s["binding"] == "external" and
                      s["section"] == "__TEXT,__text"), key=lambda s: s["address"])
    text = next(s for s in image["sections"] if s["name"] == "__TEXT,__text")
    index = next(i for i, s in enumerate(symbols) if s["name"] == "_" + name)
    start = symbols[index]["address"]
    end = symbols[index+1]["address"] if index+1 < len(symbols) else text["address"]+text["size"]
    offset = text["offset"] + start - text["address"]
    return start, raw[offset:offset+end-start], image


def run(path, case, reference):
    start, code, image = body(path, case["entry"])
    code = bytearray(code)
    relocations = [r for r in image["extensions"]["macho"]["relocations"]
                   if r["section"] == "__TEXT,__text" and start <= r["address"] < start+len(code)]
    base, stack, sentinel, callee = 0x10000000, 0x20000000, 0x40000000, 0x10010000
    extra = b""
    if case["entry"] == "SCSIRFreeUnitHandle":
        # Both wrapper and actual no-op HIM callee execute. The only object
        # relocation is bound by its Mach-O symbol and exact branch encoding.
        _, extra, _ = body(reference, "SCSIHFreeUnitHandle")
        if image["extensions"]["macho"]["header"]["file_type"] == 1:
            if len(relocations) != 1:
                raise ValueError("resource FreeUnit relocation count differs")
            r = relocations[0]
            if (r["target"] != "_SCSIHFreeUnitHandle" or not r["external"] or
                    r["kind"] != "ppc-br24-24-pc-relative" or r["addend"]):
                raise ValueError("resource FreeUnit callee binding differs")
            offset = r["address"]-start
        else:
            branches = [i for i in range(0,len(code),4) if int.from_bytes(code[i:i+4],"big") >> 26 == 18]
            if len(branches) != 1:
                raise ValueError("reference FreeUnit call count differs")
            offset = branches[0]
            word = int.from_bytes(code[offset:offset+4],"big")
            delta = (word & 0x3fffffc) - (0x4000000 if word & 0x2000000 else 0)
            if start+offset+delta != body(reference,"SCSIHFreeUnitHandle")[0]:
                raise ValueError("reference FreeUnit callee differs")
        code[offset:offset+4] = (0x48000001 | ((callee-base-offset)&0x3fffffc)).to_bytes(4,"big")
    elif relocations:
        raise ValueError("resource leaf has unexpected relocation")
    cpu = unicorn.Uc(unicorn.UC_ARCH_PPC, unicorn.UC_MODE_32 | unicorn.UC_MODE_BIG_ENDIAN)
    cpu.ctl_set_cpu_model(ppc.UC_CPU_PPC32_604)
    for address,size in ((base,0x20000),(stack,0x10000),(sentinel,4096)):
        cpu.mem_map(address,size)
    cpu.mem_write(base,bytes(code))
    if extra:cpu.mem_write(callee,extra)
    regions = {m["name"]:(0x30000000+i*0x10000,m["size"]) for i,m in enumerate(case["memory"])}
    def argument(value):
        if isinstance(value,int):return value & 0xffffffff
        if "symbol" in value:
            return next(s["address"] for s in image["symbols"] if s["name"] in (value["symbol"],"_"+value["symbol"]))
        address,size = regions[value["region"]]
        if not 0 <= value["offset"] <= size:raise ValueError("leaf argument exceeds region")
        return address+value["offset"]
    for m in case["memory"]:
        address,size = regions[m["name"]]
        cpu.mem_map(address,(size+4095)&~4095)
        cpu.mem_write(address,bytes.fromhex(m["bytes"]))
        for pointer in m.get("pointers",[]):
            value = pointer["value"]
            # These uncalled descriptor callbacks are outside the leaf graph.
            if isinstance(value,dict) and "symbol" in value:continue
            cpu.mem_write(address+pointer["offset"],argument(value).to_bytes(4,"big"))
    cpu.reg_write(ppc.UC_PPC_REG_1,stack+61440)
    cpu.reg_write(ppc.UC_PPC_REG_LR,sentinel)
    saved = {r:0xa5000000+r for r in range(14,32)}
    for r,v in saved.items():cpu.reg_write(getattr(ppc,"UC_PPC_REG_"+str(r)),v)
    for i,value in enumerate(case["arguments"]):cpu.reg_write(getattr(ppc,"UC_PPC_REG_"+str(3+i)),argument(value))
    returned, count, writes = [False], [0], []
    def instruction(uc,address,size,data):
        count[0] += 1
        if address == sentinel:returned[0]=True;uc.emu_stop()
        elif not (base <= address < base+len(code) or extra and callee <= address < callee+len(extra)):
            raise ValueError("resource leaf unexpected transfer")
    def memory(uc,access,address,size,value,data):
        if stack <= address and address+size <= stack+65536:return
        for name,(first,length) in regions.items():
            if first <= address and address+size <= first+length:
                if access==unicorn.UC_MEM_WRITE:writes.append([name,address-first,size,value])
                return
        raise ValueError("resource leaf access exceeds fixture")
    cpu.hook_add(unicorn.UC_HOOK_CODE,instruction)
    cpu.hook_add(unicorn.UC_HOOK_MEM_READ | unicorn.UC_HOOK_MEM_WRITE,memory)
    cpu.emu_start(base,0,count=10000)
    if (not returned[0] or cpu.reg_read(ppc.UC_PPC_REG_1)!=stack+61440 or
            any(cpu.reg_read(getattr(ppc,"UC_PPC_REG_"+str(r)))!=v for r,v in saved.items())):
        raise ValueError("resource leaf sentinel/SP/nonvolatile ABI differs")
    return {"memory":{n:bytes(cpu.mem_read(a,s)).hex() for n,(a,s) in regions.items()},
            "writes":writes,"return":cpu.reg_read(ppc.UC_PPC_REG_3),"instructions":count[0]}


def compare(reference, native, document):
    cases = [copy.deepcopy(c) for c in document["cases"] if c["id"].startswith("task11-b1-") or
             c["entry"] in ("SCSIrStandardRemoveScbs","SCSIRGetFreeHead")]
    empty = next(c for c in cases if c["entry"]=="SCSIrDeviceQueueRemove")
    for entry in ("SCSIrDeviceQueueRemove","SCSIrHostQueueRemove"):
        c = copy.deepcopy(next(c for c in cases if c["entry"]==entry))
        c["id"] = "task11-native-empty-"+entry
        q = next(m for m in c["memory"] if m["name"]=="queue")
        q["pointers"] = []
        b=bytearray.fromhex(q["bytes"]);offset=0 if entry=="SCSIrDeviceQueueRemove" else 1364
        b[offset:offset+8]=b"\xff"*8;q["bytes"]=b.hex();cases.append(c)
    for argument in ("unit","hhcb"):
        cases.append({"id":"task11-native-freeunit-"+argument,"entry":"SCSIRFreeUnitHandle",
                      "return_kind":"void","arguments":[{"region":argument,"offset":0}],
                      "memory":[{"name":argument,"size":16 if argument=="unit" else 1380,
                                 "bytes":"a5"*(16 if argument=="unit" else 1380)}]})
    results=[]
    for case in cases:
        actual = {"reference":run(reference,case,reference),"native":run(native,case,reference)}
        if actual["reference"]["memory"]!=actual["native"]["memory"]:
            raise ValueError("resource native memory differs: "+case["id"])
        if case["return_kind"]!="void" and actual["reference"]["return"]!=actual["native"]["return"]:
            raise ValueError("resource native return differs: "+case["id"])
        if [(w[0],w[1],w[2]) for w in actual["reference"]["writes"]] != [(w[0],w[1],w[2]) for w in actual["native"]["writes"]]:
            raise ValueError("resource native publication order differs: "+case["id"]+repr(actual))
        results.append({"id":case["id"],**actual})
    return results


def switch_graph(path):
    raw,image=load_image(path)
    const=next(s for s in image["sections"] if s["name"]=="__TEXT,__const")
    symbols={s["address"]:s["name"].removeprefix("_") for s in image["symbols"]
             if s["binding"]=="external" and s["section"]=="__TEXT,__text"}
    expected={"SCSIrAsyncEvent":[("SCSIrClearHostQueue",7),("OSDAsyncEvent",None),
              ("SCSIrClearHostQueue",20),("OSDAsyncEvent",None),("SCSIrClearHostQueue",5),
              ("SCSIrFreezeAllDeviceQueues",None),("SCSIrUnFreezeAllDeviceQueues",None),("SCSIrClearHostQueue",9)],
              "SCSIRQueueSpecialHIOB":[("SCSIrAbortTask",None),("SCSIrScsiBusReset",None),
              ("SCSIrBusDeviceReset",None),("SCSIrCompleteSpecialHIOB",None),(None,None),
              ("SCSIHQueueSpecialHIOB",None),("SCSIrAbortTaskSet",None),
              ("SCSIrCompleteSpecialHIOB",None),("SCSIrUnFreezeDeviceQueue",4)]}
    result={}
    for name,wanted in expected.items():
        start,code,_=body(path,name);end=start+len(code)
        rel=[r for r in image["extensions"]["macho"]["relocations"] if r["section"]=="__TEXT,__text" and start<=r["address"]<end]
        table_offsets={r["addend"] for r in rel if r["kind"]=="ppc-ha16-32-absolute" and r["target"]=="__TEXT,__const"}
        if len(table_offsets)!=1:raise ValueError("resource native switch table binding differs: "+name)
        offset=table_offsets.pop();table=const["address"]+offset
        if offset<0 or offset+4*len(wanted)>const["size"]:raise ValueError("resource native switch exceeds const")
        words=[int.from_bytes(code[i:i+4],"big") for i in range(0,len(code),4)]
        if (not any(w>>26==10 and w&65535==len(wanted)-1 for w in words) or
                not any(w>>26 in (12,14) and w&65535==65535 for w in words) or 0x4e800420 not in words):
            raise ValueError("resource native switch index/guard/dispatch differs: "+name)
        targets=[table+int.from_bytes(raw[const["offset"]+offset+i*4:const["offset"]+offset+i*4+4],"big",signed=True) for i in range(len(wanted))]
        actual=[]
        for target,(callee,reason) in zip(targets,wanted):
            if not start<=target<end or target%4:raise ValueError("resource native switch target outside owner")
            calls=sorted((r for r in rel if r["address"]>=target and r["kind"]=="ppc-br24-24-pc-relative"),key=lambda r:r["address"])
            call=calls[0] if calls else None
            bound=(call["target"].removeprefix("_") if call["external"] else symbols.get(call["addend"])) if call else None
            if bound!=callee:raise ValueError("resource native switch callee differs: "+name)
            if reason is not None:
                before=[int.from_bytes(code[i:i+4],"big") for i in range(target-start,call["address"]-start,4)]
                if not any(w>>26==14 and (w>>21)&31==4 and (w>>16)&31==0 and w&65535==reason for w in before):
                    raise ValueError("resource native switch reason differs: "+name)
            actual.append({"target":target,"first_call":bound,"reason":reason})
        if name=="SCSIrAsyncEvent" and targets[1]!=targets[3] or name=="SCSIRQueueSpecialHIOB" and targets[3]!=targets[7]:
            raise ValueError("resource native switch alias differs")
        result[name]={"table_offset":offset,"count":len(wanted),"cases":actual}
    return result


def publication_widths(path):
    result={}
    for name,parameter,expected in (
            ("SCSIRQueueSpecialHIOB",3,[(5,1),(6,1),(7,1),(32,1),(33,1)]),
            ("SCSIRGetMemoryTable",5,[(62,1),(60,1),(61,1),(64,2),(66,2),(63,1),
                                       (38,1),(36,1),(37,1),(40,2),(42,2),(39,1)])):
        _,code,_=body(path,name);registers={parameter};stores=[]
        for i in range(0,len(code),4):
            w=int.from_bytes(code[i:i+4],"big");op=w>>26;rt=(w>>21)&31;ra=(w>>16)&31;rb=(w>>11)&31
            if op==31 and (w>>1)&1023==444 and rt==rb:
                if rt in registers:registers.add(ra)
                else:registers.discard(ra)
            elif op in (36,38,44) and ra in registers:
                stores.append((w&65535,{36:4,38:1,44:2}[op]))
            elif op in (14,15,32,34,40):registers.discard(rt)
        selected=stores[:len(expected)]
        if selected!=expected:raise ValueError("resource native narrow publication differs: "+name+repr(stores))
        result[name]=selected
    return result
