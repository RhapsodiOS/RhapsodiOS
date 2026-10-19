"""Focused fail-closed HIM evidence checks; no duplicate CPU corpus."""

import copy
import importlib.util
import json
import shutil
import subprocess
from pathlib import Path

import pytest

TESTS=Path(__file__).resolve().parent
REPO=TESTS.parents[6]
OUT=REPO/"tools/binrecon/out/adaptecu2scsi-ppc"


def module(name):
    spec=importlib.util.spec_from_file_location("au2_him_test_"+name,TESTS/(name+".py"))
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value


@pytest.fixture(scope="module")
def archives():
    load=lambda p:json.loads(p.read_text())
    return {"proof":load(TESTS.parent/"reconstruction/task12.json"),"cases":load(TESTS/"task12-cases.json"),
            "contexts":load(TESTS/"task12-context-cases.json"),"contracts":load(TESTS/"task12-contracts.json"),
            "public":load(OUT/"objects/task12/reference-results.json")["reference"],
            "native":load(OUT/"objects/task12/native-results.json"),"manifest":load(OUT/"objects/task12/arena.json")}


@pytest.mark.parametrize("damage",["missing","stale","observation","unknown","sentinel"])
def test_him_public_actual_rejects_damage(archives,damage):
    a=module("task12_audit");r=copy.deepcopy(archives["public"])
    if damage=="missing":r["results"].pop()
    elif damage=="stale":r["cases_sha256"]="0"*64
    elif damage=="observation":r["results"][0]["observations"]["return"]=99
    elif damage=="unknown":r["results"][0]["unknown_calls"]=[1]
    else:r["results"][0]["returned_to_sentinel"]=False
    with pytest.raises(ValueError,match="HIM public"):
        a.actual_public(archives["cases"],archives["contracts"],r,archives["proof"],module("ppc_cases"))


@pytest.mark.parametrize("damage",["baseline","unrelated","permission","unused","unresolved"])
def test_him_snapshot_rejects_damage(tmp_path,archives,damage):
    a=module("task12_audit");target=tmp_path/a.DRIVER/"tests";target.mkdir(parents=True)
    for n in ("task11-contracts.json","task12-contracts.json","task12-cases.json","task12-context-cases.json"):
        shutil.copyfile(TESTS/n,target/n)
    proof=copy.deepcopy(archives["proof"])
    path=target/("task11-contracts.json" if damage=="baseline" else "task12-contracts.json")
    d=json.loads(path.read_text())
    if damage in ("baseline","unrelated"):d["reference_sha256"]="0"*64
    elif damage=="permission":next(r for r in d["mmio"]["task12-hardware"] if len(r["access"])==1)["access"]=["read","write"]
    elif damage=="unused":d["mmio"]["task12-hardware"].append({"offset":256,"size":1,"access":["read"],"evidence":"unused"})
    else:d["mmio"]["task12-hardware"][0]["evidence"]="owned body"
    if damage not in ("baseline","unrelated"):proof["contract_delta"]=d["mmio"]["task12-hardware"]
    path.write_text(json.dumps(d))
    with pytest.raises(ValueError,match="HIM accepted|HIM unused|HIM register"):
        a.snapshot(tmp_path,proof)


@pytest.mark.parametrize("damage",["entry","image","context"])
def test_him_entry_context_rejects_damage(tmp_path,archives,damage):
    c=copy.deepcopy(archives["contexts"]["cases"][0]);binary=OUT/"reference/image.bin";seed=c["initial_r28"]
    if damage=="entry":c["entry"]="SCSIHInitialize"
    elif damage=="image":
        altered=tmp_path/"image.bin";altered.write_bytes(binary.read_bytes()+b"\0");binary=altered
    else:seed=0x12345636
    with pytest.raises(ValueError,match="unapproved HIM caller entry/context"):
        module("task12_native").run(binary,c,seed)


def test_him_public_machine_input_guard_unchanged(archives):
    c=copy.deepcopy(archives["contexts"]["cases"][0]);c["machine_inputs"]={"r28":c["initial_r28"]}
    with pytest.raises(ValueError,match="only reviewed incoming r28"):
        module("ppc_cases").machine_inputs(c)


@pytest.mark.parametrize("name",["task12_execute.py","task12_native.py","task12_link.py","task12_inputs.py"])
def test_him_launcher_import_closure_rejects_missing(archives,name):
    a=module("task12_audit");r=copy.deepcopy(archives["native"])
    del r["execution_inputs"][(a.DRIVER/"tests"/name).as_posix()]
    with pytest.raises(ValueError,match="closure incomplete"):a.execution_inputs(REPO,r,archives["proof"])


def test_him_current_lf_crlf_preserves_historical_raw_identity(archives,monkeypatch):
    a=module("task12_audit");read=Path.read_bytes;target=TESTS/"task12_native.py"
    def crlf(path):
        raw=read(path)
        return raw.replace(b"\r\n",b"\n").replace(b"\n",b"\r\n") if path==target else raw
    monkeypatch.setattr(Path,"read_bytes",crlf)
    a.execution_inputs(REPO,archives["native"],archives["proof"])


@pytest.mark.parametrize("name",["AdaptecU2CHIMHIM.c","AdaptecU2CHIMTypes.h","AdaptecU2CHIM.h",
                                 "AdaptecU2CHIMPrivate.h","OSMFunctions.h","AdaptecU2SCSI.h","AdaptecU2SCSIPrivate.h"])
def test_him_all_compiled_inputs_bound(archives,name):
    a=module("task12_audit");proof=copy.deepcopy(archives["proof"]);proof["canonical_inputs"][name]="0"*64
    with pytest.raises(ValueError,match="all-seven compiled/canonical input"):
        a.native_inputs(REPO,OUT/"objects/task12",proof)


@pytest.mark.parametrize("damage",["bytes","callsite","target","bounds"])
def test_him_mmio_genuine_link_rejects_damage(archives,damage):
    a=module("task12_audit");r=copy.deepcopy(next(r for r in archives["native"]["results"] if r["mmio_operations"]))
    o=r["mmio_operations"][0]
    if damage=="bytes":o["callsite_bytes"]="60000000"
    elif damage=="callsite":o["callsite"]+=4
    elif damage=="target":o["primitive_address"]+=4
    else:o["owner_code_address"]+=4
    frozen=module("reference").frozen_functions(REPO)
    owners={a:{"name":f["names"][0].removeprefix("_"),"size":f["size"]} for a,f in frozen.items()}
    with pytest.raises(ValueError,match="HIM MMIO"):
        a.validate_operations(OUT/"objects/task12",archives["manifest"],[(r["executed_case_id"],r)],owners)


def test_him_publication_guards_reject_widened_table(archives):
    a=module("task12_audit");results=copy.deepcopy(archives["native"]["results"])
    r=next(r for r in results if any(p["owner"]=="SCSIHGetMemoryTable" for p in r["publications"]))
    r["publications"][0]["size"]=4
    with pytest.raises(ValueError,match="byte/halfword table publication"):
        a.publication_checks(archives["cases"],results)


def test_him_canonical_git_and_exact_owner_delta(archives):
    a=module("task12_audit");prefix=a.DRIVER/"reconstruction"
    blob=lambda rev,name:subprocess.check_output(["git","show",rev+":"+(prefix/name).as_posix()],cwd=REPO)
    proof=blob("HEAD","task12.json");after=json.loads(blob("HEAD","ledger.json"));before=json.loads(blob("608e9f524deeaaa79910e484ee9c5008be3f863c","ledger.json"))
    own={b["address"] for b in archives["proof"]["bodies"]};assert len(own)==31
    for x,y in zip(before["entries"],after["entries"]):
        if x["address"] not in own:assert x==y
        else:assert y["status"]=="control-flow-confirmed" and y["artifacts"]==[{"kind":"source-native-control-flow-and-frozen-cases","path":(prefix/"task12.json").as_posix(),"sha256":a.sha(proof)}]
    assert (TESTS.parent/"reconstruction/task12.json").read_bytes().replace(b"\r\n",b"\n")==proof
    old=json.loads(blob("608e9f524deeaaa79910e484ee9c5008be3f863c","data.json"));new=json.loads(blob("HEAD","data.json"))
    assert [o for o in old["objects"] if o["name"]!="switch_230ed4"]==[o for o in new["objects"] if o["name"]!="switch_230ed4"]
    old=json.loads(blob("608e9f524deeaaa79910e484ee9c5008be3f863c","source-map.json"));new=json.loads(blob("HEAD","source-map.json"))
    assert len(new["mapped"])==len(old["mapped"])+31
    assert {e["address"] for e in old["unmapped"]}-{e["address"] for e in new["unmapped"]}==own
    assert [e for e in old["mapped"] if e["address"] not in own]==[e for e in new["mapped"] if e["address"] not in own]
    assert old["duplicate_candidates"]==new["duplicate_candidates"] and old["boundary_disputed"]==new["boundary_disputed"]


@pytest.mark.parametrize("damage",["extra_row","missing_row","extra_switch","missing_switch"])
def test_him_task11_historical_range_still_rejects_wrong_delta(monkeypatch,damage):
    test=module("test_reconstruction");original=subprocess.check_output
    accepted="608e9f524deeaaa79910e484ee9c5008be3f863c";base="773b8d68abf5917aaa7e95871fec394d571619b2"
    prefix="src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/reconstruction/"
    proof=json.loads((TESTS.parent/"reconstruction/task11.json").read_text())
    own={b["address"] for b in proof["bodies"]}
    filename="ledger.json" if damage.endswith("row") else "data.json"
    before=json.loads(original(["git","show",base+":"+prefix+filename],cwd=REPO))
    after=json.loads(original(["git","show",accepted+":"+prefix+filename],cwd=REPO))
    if damage=="extra_row":next(e for e in after["entries"] if e["address"] not in own)["reason"]="extra mutation"
    elif damage=="missing_row":
        index=next(i for i,e in enumerate(after["entries"]) if e["address"] in own);after["entries"][index]=before["entries"][index]
    elif damage=="extra_switch":next(o for o in after["objects"] if o["name"]=="switch_230ed4")["interpretation"]="extra mutation"
    else:
        index=next(i for i,o in enumerate(after["objects"]) if o["name"]=="switch_230f1c");after["objects"][index]=before["objects"][index]
    def changed(command,*args,**kwargs):
        if command==["git","show",accepted+":"+prefix+filename]:return json.dumps(after).encode()
        return original(command,*args,**kwargs)
    monkeypatch.setattr(subprocess,"check_output",changed)
    with pytest.raises(AssertionError):test.test_task11_canonical_git_closure_and_scoped_delta({"proof":proof})
