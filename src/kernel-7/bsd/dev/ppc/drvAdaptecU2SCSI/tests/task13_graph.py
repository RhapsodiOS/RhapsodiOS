"""Authenticate the ten compiled jump tables and the NV selector branch graph."""

from pathlib import Path
import importlib.util
from binrecon.macho import load_image


TABLES = {
    "AdaptecU2CHIMTransport.c": (
        (0, 29, "SCSIxTranslateError", "switch_23144c"),
        (116, 73, "SCSIxTranslateError", "switch_231284"),
        (408, 41, "SCSIxTranslateError", "switch_2313a8"),
        (572, 80, "SCSIxPostBusScan", "switch_2314e0")),
    "AdaptecU2CHIMAPI.c": (
        (0, 8, "SCSIProfileAdapter", "switch_230f60"),
        (32, 8, "SCSIProfileAdapter", "switch_230f80"),
        (64, 19, "SCSIQueueIOB", "switch_230fd0"),
        (140, 29, "SCSIBackEndISR", "switch_2311e4"),
        (256, 73, "SCSIBackEndISR", "switch_23101c"),
        (548, 41, "SCSIBackEndISR", "switch_231140"))}


def leaf():
    spec=importlib.util.spec_from_file_location("au2_api_graph_leaf",Path(__file__).with_name("task11_native.py"))
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value


def graph(path, source):
    raw,image=load_image(path);body=leaf().body
    const=next(s for s in image["sections"] if s["name"]=="__TEXT,__const")
    relocations=image["extensions"]["macho"]["relocations"]
    tables=TABLES[source]
    if const["size"]!=sum(count*4 for _,count,_,_ in tables):
        raise ValueError("API compiled switch const extent differs")
    actual={r["address"] for r in relocations if r["section"]=="__TEXT,__const" and r["kind"]=="ppc-sectdiff-32-absolute"}
    if actual!=set(range(const["address"],const["address"]+const["size"],4)):
        raise ValueError("API compiled switch relocation coverage differs")
    result=[]
    for offset,count,owner,name in tables:
        start,code,_=body(path,owner)
        words={start+i:int.from_bytes(code[i:i+4],"big") for i in range(0,len(code),4)}
        refs=[r for r in relocations if r["section"]=="__TEXT,__text" and start<=r["address"]<start+len(code)
              and r["target"]=="__TEXT,__const" and r["addend"]==offset and r["kind"]!="ppc-pair-16-absolute"]
        guards=[a for a,w in words.items() if w>>26==10 and w&65535==count-1]
        if (not refs or {r["kind"] for r in refs}!={"ppc-ha16-32-absolute","ppc-lo16-32-absolute"}
                or not guards or 0x4e800420 not in words.values()):
            raise ValueError("API compiled switch base/unsigned guard/dispatch differs")
        defaults=[]
        for guard in guards:
            field=(words[guard]>>23)&7
            branches=[a for a in range(guard+4,guard+28,4) if words.get(a,0)>>26==16 and ((words[a]>>16)&31)//4==field]
            if not branches:raise ValueError("API compiled unsigned switch guard branch differs: "+name)
            address=branches[0];branch=words[address]
            if branch&3 or any(words[a]>>26 in (10,11) and ((words[a]>>23)&7)==field for a in range(guard+4,address,4)):
                raise ValueError("API compiled switch condition overwritten before guard")
            delta=branch&65532;target=address+delta-(65536 if delta&32768 else 0)
            if target not in words:raise ValueError("API compiled switch default leaves owner")
            defaults.append(target)
        table=const["address"]+offset
        targets=[table+int.from_bytes(raw[const["offset"]+offset+i*4:const["offset"]+offset+i*4+4],"big",signed=True) for i in range(count)]
        if any(a not in words for a in targets):raise ValueError("API compiled switch target leaves owner")
        paths=[]
        rel={r["address"]:r for r in relocations if r["section"]=="__TEXT,__text" and r["kind"]=="ppc-br24-24-pc-relative"}
        for index,entry in enumerate(targets):
            todo=[entry];visited=set();calls=set()
            while todo:
                address=todo.pop()
                if address in visited:continue
                if address not in words:raise ValueError("API compiled switch path leaves owner")
                visited.add(address);w=words[address];op=w>>26
                if w==0x4e800020:continue
                if address in rel:
                    r=rel[address]
                    callee=r["target"]
                    if not r["external"]:
                        names=[s["name"] for s in image["symbols"] if s["binding"]=="external" and s["section"]=="__TEXT,__text" and s["address"]==r["addend"]]
                        d=w&0x3fffffc
                        if r["target"]!="__TEXT,__text" or len(names)!=1 or address+d-(0x4000000 if d&0x2000000 else 0)!=r["addend"]:
                            raise ValueError("API switch local callee relocation differs")
                        callee=names[0]
                    calls.add(callee)
                    if w&1:todo.append(address+4)
                elif w in (0x4e800421,0x4e800021):calls.add("indirect");todo.append(address+4)
                elif w==0x4e800420:
                    dispatch=[r for r in relocations if r["section"]=="__TEXT,__text" and r["target"]=="__TEXT,__const" and address-36<=r["address"]<address]
                    if dispatch:
                        for off,n,who,_ in tables:
                            if who==owner:
                                base=const["address"]+off
                                todo.extend(base+int.from_bytes(raw[const["offset"]+off+i*4:const["offset"]+off+i*4+4],"big",signed=True) for i in range(n))
                    else:calls.add("indirect-tail")
                elif op==18:
                    if w&3:raise ValueError("API switch unexpected direct transfer")
                    d=w&0x3fffffc;todo.append(address+d-(0x4000000 if d&0x2000000 else 0))
                elif op==16:
                    if w&3:raise ValueError("API switch unexpected conditional transfer")
                    d=w&65532;todo.extend((address+4,address+d-(65536 if d&32768 else 0)))
                else:todo.append(address+4)
            paths.append({"index":index,"target":entry,"instructions":sorted(visited),"calls":sorted(calls)})
        result.append({"reference_table":name,"owner":owner,"offset":offset,"table":table,"count":count,
                       "base_relocations":refs,"guards":guards,"defaults":defaults,"targets":targets,"paths":paths})
    if source=="AdaptecU2CHIMAPI.c":
        start,code,_=body(path,"SCSIGetNVOSMSegment")
        words={start+i:int.from_bytes(code[i:i+4],"big") for i in range(0,len(code),4)}
        calls=[r for r in relocations if r["section"]=="__TEXT,__text" and start<=r["address"]<start+len(code) and r["kind"]=="ppc-br24-24-pc-relative"]
        if (not any(r["target"]=="_SCSIHReadSEEPROM" for r in calls) or
                not any(w>>26==16 for w in words.values()) or 0x4e800420 in words.values()):
            raise ValueError("API NV selector conditional implementation differs")
        result.append({"reference_table":"switch_230fa0","owner":"SCSIGetNVOSMSegment","kind":"conditional-chain",
                       "instructions":[{"address":a,"bytes":w.to_bytes(4,"big").hex()} for a,w in words.items()],"calls":calls})
    return result
