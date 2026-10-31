"""Review-round caller effects and evidence integrity, independently produced."""

import json
import copy
from pathlib import Path
import pytest
import task13_fix1_checks as checks
import task13_fix1_identity as identity
import task13_fix1_runtime as runtime
import task13_fix1_audit as audit
from binrecon.macho import load_image

TESTS=Path(__file__).resolve().parent
OUT=TESTS.parents[6]/"tools/binrecon/out/adaptecu2scsi-ppc"


def actual():
    cases=json.loads((TESTS/"task13-cases.json").read_text())["cases"]
    results=json.loads((OUT/"objects/task13/native-results.json").read_text())["results"]
    additional=OUT/"objects/task13-fix1/native-results.json"
    if additional.exists():
        cases+=json.loads((TESTS/"task13-fix1-cases.json").read_text())["cases"]
        results+=json.loads(additional.read_text())["results"]
    return cases,results


def test_verify_adapter_public_success_and_postmap_paths():
    checks.require_paths("I1",*actual())


def test_public_normal_queue_ownership_and_completion_redispatch():
    checks.require_paths("I2",*actual())


def test_backend_active_real_handler_dispatch_and_restoration():
    checks.require_paths("I3",*actual())


@pytest.fixture(scope="module")
def corpus():
    cases=json.loads((TESTS/"task13-fix1-cases.json").read_text())["cases"]
    record=json.loads((OUT/"objects/task13-fix1/native-results.json").read_text())
    return cases,record


def test_all_caller_effects(corpus):
    cases,record=corpus
    checks.complete_cases(cases,record["results"])
    for case,result in zip(cases,record["results"]):checks.effects(case,result)


@pytest.mark.parametrize("damage",["omit","duplicate","root","producer","old-input","new-input"])
def test_independent_producer_rejects_damage(corpus,damage):
    cases,original=corpus;record=copy.deepcopy(original);cases=copy.deepcopy(cases)
    if damage=="omit":record["results"].pop()
    elif damage=="duplicate":record["results"][-1]=record["results"][0]
    elif damage=="root":cases[0]["entry"]="SCSIRGetConfiguration"
    elif damage=="producer":record["execution_revision"]=identity.EXECUTION
    elif damage=="old-input":record["legacy"]["execution_inputs"][next(iter(record["legacy"]["execution_inputs"]))]["git_blob_sha256"]="0"*64
    else:record["execution_inputs"][next(iter(record["execution_inputs"]))]["working_sha256"]="0"*64
    with pytest.raises(ValueError):
        audit.producer(record,cases,original["execution_inputs"],original["legacy"],original["execution_revision"],original["binary_sha256"],original["cases_sha256"],original["contracts_sha256"])


@pytest.mark.parametrize("tag,damage",[("verify-3","direct-callee"),("verify-0","publication"),
    ("verify-product-reject","partial-state"),("submit-host-exhausted","ownership"),
    ("submit-immediate","barrier"),("complete-host-handoff","ownership"),
    ("complete-thaw-redispatch","direct-callee"),("complete-finish-queue-full","completion"),
    ("reset-precedence","handler"),("ioerror-precedence","handler"),("scsi-selection","completion"),
    ("seq-sentinel-fallback","sentinel"),("break","restore")])
def test_caller_effects_reject_substitution(corpus,tag,damage):
    cases,record=corpus;index=next(i for i,c in enumerate(cases) if c["id"]=="task13-fix1-"+tag)
    case=cases[index];result=copy.deepcopy(record["results"][index]);root=case["entry"]
    calls=[c for c in result["api_calls"] if c["owner"]==root]
    if damage=="direct-callee":calls[-1]["callee"]="SCSIrDeviceQueueAppend"
    elif damage=="publication":result["publications"]=[p for p in result["publications"] if not(root==p["owner"] and p["offset"]==31)]
    elif damage in ("partial-state","ownership"):result["observations"]["memory"]={}
    elif damage=="barrier":result["observations"]["trace"].pop()
    elif damage=="handler":next(c for c in calls if c["callee"]==checks.HANDLERS[tag])["callee"]="SCSIhIntFree"
    elif damage=="completion":calls.append(copy.deepcopy(calls[-1]));result["api_calls"].append(calls[-1])
    elif damage=="sentinel":next(c for c in calls if c["callee"]==checks.HANDLERS[tag])["arguments"][1]=0
    else:next(c for c in calls if c["callee"]=="SCSIhWriteHCNTRL")["arguments"][1]=0
    with pytest.raises(ValueError):checks.effects(case,result)


@pytest.mark.parametrize("damage",["baseline","new-permission","omission","duplicate","evidence"])
def test_isolated_snapshot_rejects_damage(corpus,damage):
    cases,_=corpus;current=runtime.contracts();baseline=json.loads((TESTS/"task13-contracts.json").read_text())
    rows=current["mmio"]["task13-fix1"]
    if damage=="baseline":current["reference_sha256"]="0"*64
    elif damage=="new-permission":rows[0]["offset"]=0x1234
    elif damage=="omission":rows.pop()
    elif damage=="duplicate":rows.append(copy.deepcopy(rows[0]))
    else:rows[0]["evidence"]="reconstruction/task13.json#/mmio_operations/forged"
    with pytest.raises(ValueError):audit.snapshot(cases,current,baseline)


@pytest.fixture(scope="module")
def alias_inputs(corpus):
    cases,_=corpus;case=next(c for c in cases if c["id"]=="task13-fix1-ioerror-precedence")
    raw,image=load_image(OUT/"objects/task13/native-arena.macho");ref,parsed=load_image(OUT/"reference/image.bin")
    return raw,image,case,ref,parsed,json.loads((TESTS/"task13-fix1-alias.json").read_text())


def test_exact_retained_data_alias(alias_inputs):
    actual=runtime.event_alias(*alias_inputs)
    assert actual["input"]==alias_inputs[1]["input"]
    assert actual["symbols"][:-1]==alias_inputs[1]["symbols"]
    assert actual["symbols"][-1]["metadata_alias"] is True


@pytest.mark.parametrize("damage",["case","entry","image","address","extent","data","section","conflict"])
def test_retained_data_alias_rejects_damage(alias_inputs,damage):
    raw,image,case,ref,parsed,record=alias_inputs;image=copy.deepcopy(image);case=copy.deepcopy(case);record=copy.deepcopy(record)
    if damage=="case":case["id"]="task13-fix1-reset-precedence"
    elif damage=="entry":case["entry"]="SCSIhIntIOError"
    elif damage=="image":image["input"]["sha256"]="0"*64
    elif damage=="address":record["address"]+=4
    elif damage=="extent":record["size"]=60
    elif damage=="data":record["reference_bytes"]="ff"+record["reference_bytes"][2:]
    elif damage=="section":next(s for s in image["sections"] if s["name"]=="__TEXT,__const")["size"]-=4
    else:image["symbols"].append({"name":"AU2_event_names","address":0x230ca0,"section":"__TEXT,__const"})
    with pytest.raises(ValueError):runtime.event_alias(raw,image,case,ref,parsed,record)


def test_inventory_scope_preserves_consumed_marker():
    path=identity.old.DRIVER/"reconstruction/inventory.md";raw=(OUT.parents[3]/path).read_bytes()
    canonical=identity.old.canonical(raw,path)
    assert canonical==identity.old.canonical(raw+b"\nUnconsumed completion prose.\n",path)
    changed=raw.replace(b"<!-- functions:start -->",b"<!-- functions:start -->\nchanged",1)
    assert canonical!=identity.old.canonical(changed,path)
    assert identity.old.sha(canonical)=="319101C8CC2305FBF33B3E51BDDE233865D802961981155134DD713E2EF77F3D"


@pytest.fixture(scope="module")
def evidence():
    return audit.api.module("verify").authenticate_reference(OUT/"reference",TESTS.parents[6])


@pytest.mark.parametrize("damage",["instruction","direct-callee","owner","handler-entry"])
def test_genuine_callsite_rejects_damage(corpus,evidence,damage):
    cases,record=corpus;tag="scsi-selection" if damage=="handler-entry" else "verify-3"
    index=next(i for i,c in enumerate(cases) if c["id"]=="task13-fix1-"+tag)
    case=cases[index];result=copy.deepcopy(record["results"][index])
    if damage=="instruction":result["api_calls"][0]["bytes"]="48000001"
    elif damage=="direct-callee":result["api_calls"][0]["callee"]="SCSIRGetConfiguration"
    elif damage=="owner":result["api_calls"][0]["owner_address"]+=4
    else:next(e for e in result["entries"] if e["entry"]=="SCSIhIntSelto")["address"]+=4
    raw,image=load_image(OUT/"objects/task13/native-arena.macho");manifest=json.loads((OUT/"objects/task13/arena.json").read_text())
    with pytest.raises(ValueError):audit.calls(case,result,raw,image,evidence["frozen"],manifest)


@pytest.mark.parametrize("damage",["owner","caller","omitted-operation","instruction","primitive"])
def test_actual_mmio_attribution_rejects_damage(corpus,evidence,damage):
    cases,record=corpus;index=next(i for i,c in enumerate(cases) if c["id"]=="task13-fix1-verify-4")
    result=copy.deepcopy(record["results"][index]);operation=result["mmio_operations"][0]
    accepted={int(a):p for a,p in json.loads((TESTS.parent/"reconstruction/task13.json").read_text())["operation_owner_proofs"].items()}
    manifest=json.loads((OUT/"objects/task13/arena.json").read_text());contracts=runtime.contracts()
    if damage=="owner":operation["owner"]="SCSIQueueIOB"
    elif damage=="caller":operation["api_caller"]["name"]="SCSIQueueIOB"
    elif damage=="omitted-operation":result["mmio_operations"].pop()
    elif damage=="instruction":operation["callsite_bytes"]="48000001"
    else:operation["primitive_bytes"]="60000000"
    with pytest.raises(ValueError):
        audit.api.mmio_index([("damage",result)],{"mmio":{"task13-api":contracts["mmio"]["task13-fix1"]}},evidence["frozen"],accepted)
        audit.api.module("task12_audit").validate_operations(OUT/"objects/task13",manifest,[("damage",result)],evidence["frozen"])


def test_complete_actual_proof(evidence):
    audit.audit(evidence,TESTS.parents[6])


def test_fix1_canonical_proof_and_runtime_identity():
    repo=TESTS.parents[6];path=identity.old.DRIVER/"reconstruction/task13-fix1.json"
    raw=identity.old.git(repo,"HEAD",path);proof=json.loads(raw)
    assert identity.old.canonical((repo/path).read_bytes(),path)==raw
    assert proof["execution_inputs"]==identity.closure(repo,proof["execution_revision"])
    assert proof["legacy"]==identity.legacy(repo)
