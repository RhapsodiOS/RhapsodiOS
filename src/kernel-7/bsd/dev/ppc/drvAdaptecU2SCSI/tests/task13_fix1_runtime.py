"""Separate review corpus using the unchanged strict Task13 execution engine."""

import json
import copy
import hashlib
from pathlib import Path
import task13_native as native


def contracts():
    return json.loads(Path(__file__).with_name("task13-fix1-contracts.json").read_text())


def event_alias(raw,image,case,reference_raw,reference_image,record):
    """Expose only the authenticated retained reference constant, without changing bytes."""
    sha=lambda value:hashlib.sha256(value).hexdigest().upper()
    if (case["id"]!="task13-fix1-ioerror-precedence" or case["entry"]!="SCSIBackEndISR" or
            record["case"]!=case["id"] or record["entry"]!=case["entry"] or
            record["name"]!="AU2_event_names" or record["address"]!=0x230ca0 or record["size"]!=64 or
            record["sha256"]!="649CBFB64173BA94D583B02057444AF7EB9A222BD0D62A38F94BE064FCB361AE" or
            record["arena_sha256"]!="086BABB343B04F36889D56FF799DEBF65F372A357D5636B7E1C320AFA064DFAE" or
            record["reference_sha256"]!="D01D748C10117FBFCEB25F99D88A63895C3BAC6C09A5110AD358E583316494BD" or
            sha(raw)!=record["arena_sha256"] or image["input"]["sha256"]!=sha(raw) or
            sha(reference_raw)!=record["reference_sha256"] or reference_image["input"]["sha256"]!=sha(reference_raw)):
        raise ValueError("fix1 event-name alias case/image/address/extent identity differs")
    baseline=Path(__file__).with_name("task13-contracts.json").read_bytes()
    if (sha(baseline.replace(b"\r\n",b"\n"))!="F9D68196022781308DD6EF81A8346B4601A88379B4CAB712266BCB852EFD55D2" or
            json.loads(baseline)["reference_aliases"].get(record["name"])!=record["address"]):
        raise ValueError("fix1 accepted event-name alias differs")
    for payload,parsed in ((raw,image),(reference_raw,reference_image)):
        sections=[s for s in parsed["sections"] if s["name"]=="__TEXT,__const" and s["address"]==0x22d78c and s["size"]==27844]
        if len(sections)!=1:raise ValueError("fix1 event-name section bounds differ")
        section=sections[0];offset=section["offset"]+record["address"]-section["address"]
        if not section["address"]<=record["address"]<record["address"]+64<=section["address"]+section["size"]:
            raise ValueError("fix1 event-name data bounds differ")
        data=payload[offset:offset+64]
        if len(data)!=64 or sha(data)!=record["sha256"] or data.hex()!=record["reference_bytes"]:
            raise ValueError("fix1 event-name actual data differs")
    if any(s["name"].removeprefix("_")==record["name"] for s in image["symbols"]):
        raise ValueError("fix1 alias conflicts with genuine image symbol")
    result=copy.deepcopy(image)
    result["symbols"].append({"name":record["name"],"address":record["address"],"section":"__TEXT,__const",
                              "metadata_alias":True})
    return result


def run(binary,case,manifest=None):
    if (not case["id"].startswith("task13-fix1-") or
            case["entry"] not in ("SCSIVerifyAdapter","SCSIQueueIOB","SCSIBackEndISR")):
        raise ValueError("unapproved Task13 fix1 public caller")
    original=native.module
    class Inputs:
        contracts=staticmethod(contracts)
    alias=[]
    def modules(name):
        if name=="task13_inputs":return Inputs
        value=original(name)
        if name=="ppc_cases" and manifest is not None and case["id"]=="task13-fix1-ioerror-precedence":
            load=value.load_image
            def mapped(path):
                raw,image=load(path)
                reference=Path(__file__).resolve().parents[7]/"tools/binrecon/out/adaptecu2scsi-ppc/reference/image.bin"
                reference_raw,reference_image=load(reference)
                record=json.loads(Path(__file__).with_name("task13-fix1-alias.json").read_text())
                image=event_alias(raw,image,case,reference_raw,reference_image,record)
                alias[:]=[record]
                return raw,image
            value.load_image=mapped
        return value
    native.module=modules
    try:
        result=native.run(binary,case,entries=["SCSIhIntSrst","SCSIhIntIOError","SCSIhCheckLength",
                          "SCSIhAbortTarget","SCSIhIntSelto","SCSIhIntFree","SCSIhParityError","SCSIhBreakInterrupt"],manifest=manifest)
        return {**result,"metadata_aliases":alias}
    finally:
        native.module=original
