"""Authenticate complete actual resource completion/reset call boundaries."""

import hashlib
import importlib.util
import json
from pathlib import Path


def digest(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(",",":")).encode()).hexdigest().upper()


def shared():
    spec=importlib.util.spec_from_file_location("au2_resource_capture",Path(__file__).with_name("task10_sequence.py"))
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


def audit(document, cases, actual):
    by_id={c["id"]:c for c in cases["cases"]}
    if set(actual)!=set(document["cases"]):raise ValueError("resource boundary case scope differs")
    for name in document["cases"]:
        boundary=actual[name]
        result=boundary["result"]
        if (digest(boundary)!=document["boundaries"][name] or boundary["image_writes"]!=[] or
                result["observations"]!=by_id[name]["expected"] or result["unknown_calls"]!=[] or
                result["returned_to_sentinel"] is not True or not 0<result["instructions"]<=4000000):
            raise ValueError("resource actual boundary differs: "+name)
    first,second,reset=document["cases"]
    if (by_id[first]["entry"],by_id[second]["entry"],by_id[reset]["entry"])!=(
            "SCSIhTerminateCommand","SCSIrScsiBusReset","SCSIrScsiBusReset"):
        raise ValueError("resource completion/reset order differs")
    if shared().canonical_memory(by_id[second]["memory"])!=actual[first]["memory"]:
        raise ValueError("resource handoff bytes or pointer bindings differ")
    for name in (second,reset):
        final={m["name"]:m for m in actual[name]["memory"]}
        adapter=bytes.fromhex(final["adapter"]["bytes"])
        active={p["offset"]:p["value"] for p in final["active"]["pointers"]}
        done={p["offset"]:p["value"] for p in final["done"]["pointers"]}
        if (adapter[1372:1374]!=b"\x01\x01" or adapter[1376]!=3 or
                adapter[288:292]!=bytes(4) or adapter[312:316]!=bytes(4) or
                active[0]!=0xffffffff or done[0]!={"region":"normal","offset":0}):
            raise ValueError("resource final completion/reset ownership differs")
    entries=[event.get("entry") for event in actual[reset]["result"]["observations"]["trace"] if "entry" in event]
    if entries!=["SCSIrCompleteHIOB","SCSIrCompleteSpecialHIOB","OSDCompleteHIOB","OSDCompleteSpecialHIOB"]:
        raise ValueError("resource reset-induced callback ordering differs")
    if not document.get("preconditions") or not document.get("external_state"):
        raise ValueError("resource boundary state contract missing")


def execute(binary,cases,contracts,document):
    by_id={c["id"]:c for c in cases["cases"]}
    actual={name:shared().capture(binary,by_id[name],contracts,document["pointer_slots"])
            for name in document["cases"]}
    audit(document,cases,actual)
    return actual
