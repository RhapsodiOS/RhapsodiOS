"""Exact pre-entry private-byte witness for the authenticated PostBusScan body."""

import hashlib
import json
from pathlib import Path
import task13_native as native


def run(binary,case,manifest=None):
    seed=case.get("initial_private_byte")
    if (type(seed) is not int or seed not in (0x7f,0x35) or case["id"]!="task13-postscan-private-"+str(seed) or
            case["entry"]!="SCSIxPostBusScan" or case["evidence"]["entry_address"]!=0x1a8180 or "machine_inputs" in case):
        raise ValueError("unapproved PostBusScan private byte context")
    mapping=json.loads(Path(__file__).with_name("task13-stack-mapping.json").read_text())
    module=native.module;runner=module("ppc_cases");raw,image=runner.load_image(binary)
    digest=hashlib.sha256(raw).hexdigest().upper()
    if digest==mapping["reference"]["image_sha256"]:
        selected=mapping["reference"];entry=selected["entry_address"]
    elif manifest is not None and digest==manifest["sha256"]:
        selected=mapping["native"];definition=manifest["definitions"]["_SCSIxPostBusScan"]
        object_path=Path(definition["object"]);start,code,_=module("task11_native").body(object_path,"SCSIxPostBusScan")
        if (hashlib.sha256(object_path.read_bytes()).hexdigest().upper()!=selected["object_sha256"] or
                start!=selected["entry_address"] or len(code)!=selected["size"] or
                hashlib.sha256(code).hexdigest().upper()!=selected["body_sha256"]):
            raise ValueError("PostBusScan actual native private-byte body differs")
        entry=definition["arena_address"]
        if definition["size"]!=selected["size"]:raise ValueError("PostBusScan genuine native bounds differ")
    else:raise ValueError("unapproved PostBusScan private-byte image")
    section=next(s for s in image["sections"] if s["address"]<=entry and entry+selected["size"]<=s["address"]+s["size"])
    base=section["offset"]+entry-section["address"]
    code=raw[base:base+selected["size"]]
    callback=entry+selected["callback_offset"]
    instruction=int.from_bytes(code[selected["callback_offset"]:selected["callback_offset"]+4],"big")
    expected_callee=(manifest["definitions"]["_SCSIxQueueSpecialIOB"]["arena_address"] if manifest else
                     next(s["address"] for s in image["symbols"] if s["name"]=="_SCSIxQueueSpecialIOB" and s["section"]))
    displacement=instruction&0x3fffffc
    if instruction>>26!=18 or instruction&3!=1 or callback+displacement-(0x4000000 if displacement&0x2000000 else 0)!=expected_callee:
        raise ValueError("PostBusScan genuine queue-special callsite differs")
    if selected is mapping["reference"] and hashlib.sha256(code).hexdigest().upper()!=selected["body_sha256"]:
        raise ValueError("PostBusScan pinned reference body differs")
    for record in [selected["frame_instruction"],*selected["stores"],*selected["loads"],*selected["use_instructions"]]:
        offset=record["offset"]
        if offset%4 or not 0<=offset<=len(code)-4 or code[offset:offset+4].hex()!=record["bytes"]:
            raise ValueError("PostBusScan private-byte frame/load/use mapping differs")
    frame,slot=selected["frame_size"],selected["byte_offset"]
    adjustment=int.from_bytes(bytes.fromhex(selected["frame_instruction"]["bytes"]),"big")
    if (adjustment&0xffff0000!=0x94210000 or 65536-(adjustment&65535)!=frame or frame!=96 or slot!=56 or
            any(int.from_bytes(bytes.fromhex(r["bytes"]),"big")&0xfc1fffff!=0x88010038 for r in selected["loads"]) or
            any(int.from_bytes(bytes.fromhex(r["bytes"]),"big")&0xfc1fffff!=0x98010038 for r in selected["stores"])):
        raise ValueError("PostBusScan exact private byte storage width/frame differs")
    addresses={};position=runner.REGION_BASE
    for region in case["memory"]:
        addresses[region["name"]]=position;position+=(region["size"]+4095)&~4095
    original=runner.unicorn.Uc;instances=[];state={"initial_private_byte":seed,"loads":[],"stores":[],"uses":[],"callback_entries":0}
    late=entry+selected["late_load_offset"];use={entry+r["offset"] for r in selected["use_instructions"]}
    def create(*args,**kwargs):
        cpu=original(*args,**kwargs);instances.append(cpu);start=cpu.emu_start
        def execute(*args,**kwargs):
            initial_sp=cpu.reg_read(runner.ppc.UC_PPC_REG_1);address=initial_sp-frame+slot
            if initial_sp!=runner.STACK+runner.STACK_SIZE-4096 or not runner.STACK<=address<runner.STACK+runner.STACK_SIZE:
                raise ValueError("PostBusScan private-byte pre-entry stack bounds differ")
            # The sole architectural context write occurs before the first PPC instruction.
            cpu.mem_write(address,bytes([seed]));state.update({"initial_sp":initial_sp,"address":address,"seeded_before_entry":True})
            def observe(cpu,pc,size,data):
                if pc==entry+selected["callback_offset"]:state["callback_entries"]+=1
                if pc==late:
                    sp=cpu.reg_read(runner.ppc.UC_PPC_REG_1)
                    state["loads"].append({"instruction":pc,"bytes":bytes(cpu.mem_read(pc,4)).hex(),"sp":sp,
                        "address":sp+slot,"value":bytes(cpu.mem_read(sp+slot,1))[0],
                        "iob_status":int.from_bytes(cpu.mem_read(addresses["scan-iob"]+44,4),"big")})
                if pc in use:state["uses"].append({"instruction":pc,"bytes":bytes(cpu.mem_read(pc,4)).hex(),"r0":cpu.reg_read(runner.ppc.UC_PPC_REG_0)})
            def write(cpu,access,address,size,value,data):
                if address<=state["address"]<address+size:state["stores"].append({"instruction":cpu.reg_read(runner.ppc.UC_PPC_REG_PC),"address":address,"size":size,"value":value})
            cpu.hook_add(runner.unicorn.UC_HOOK_CODE,observe);cpu.hook_add(runner.unicorn.UC_HOOK_MEM_WRITE,write)
            return start(*args,**kwargs)
        cpu.emu_start=execute;return cpu
    runner.unicorn.Uc=create;native.module=lambda name:runner if name=="ppc_cases" else module(name)
    try:result=native.run(binary,case,manifest=manifest)
    finally:native.module=module;runner.unicorn.Uc=original
    if (len(instances)!=1 or state["callback_entries"]!=1 or len(state["loads"])!=1 or state["stores"] or
            state["loads"][0]["address"]!=state["address"] or state["loads"][0]["value"]!=seed or state["loads"][0]["iob_status"]!=1 or
            state["loads"][0]["sp"]!=state["initial_sp"]-frame or not state["uses"] or state["uses"][0]["r0"]!=seed):
        raise ValueError("PostBusScan actual private byte/callback/load/use differs")
    state["final_iob_status"]=int.from_bytes(instances[0].mem_read(addresses["scan-iob"]+44,4),"big")
    state["final_origin_status"]=int.from_bytes(instances[0].mem_read(addresses["origin"]+44,4),"big")
    if state["final_iob_status"]!=1 or state["final_origin_status"]!=(37 if seed==127 else 32):raise ValueError("PostBusScan private-byte downstream effect differs")
    return {**result,"private_byte_context":state}
