"""Frozen transport/public API behavior and fail-closed owner evidence."""

import importlib.util
import copy
import subprocess
import json
from pathlib import Path
import pytest

TESTS = Path(__file__).resolve().parent
REPO = TESTS.parents[6]
OUT = REPO / "tools/binrecon/out/adaptecu2scsi-ppc"


def module(name):
    spec = importlib.util.spec_from_file_location("au2_api_test_"+name, TESTS/(name+".py"))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


@pytest.fixture(scope="module")
def public_results():
    gate = module("verify")
    for owner in ("AdaptecU2CHIMTransport.c", "AdaptecU2CHIMAPI.c"):
        gate.audit("group", OUT/"reference", REPO, OUT/"objects/task13", None, owner)
    results = json.loads((OUT/"objects/task13/reference-results.json").read_text())["reference"]
    return results


def family(name, results):
    cases = json.loads((TESTS/"task13-cases.json").read_text())
    selected = [c for c in cases["cases"] if c["family"] == name]
    assert selected
    actual = {r["executed_case_id"]: r for r in results["results"]}
    for case in selected:
        result = actual[case["id"]]
        assert result["unknown_calls"] == [] and result["returned_to_sentinel"]
        assert result["observations"] == case["expected"]
        assert 0 < result["instructions"] <= case["instruction_limit"]


def test_public_table_and_memory_contract(public_results):
    family("memory",public_results)


def test_scan_lun_profiles_and_firmware_mode(public_results):
    family("scan",public_results)


def test_front_back_isr_and_special_iob(public_results):
    family("queue",public_results)


def test_public_declaration_discovery():
    c = {"entry": "SCSIGetFunctionPointers", "declaration": "void SCSIGetFunctionPointers(AdaptecU2HIMFunctions *destination, unsigned int size);",
         "return_kind": "void", "arguments": [0, 168]}
    assert module("ppc_cases").declared_abi(c) == [("pointer", 4), ("scalar", 4)]


@pytest.mark.parametrize("damage", ["forged", "missing", "arity", "type", "return"])
def test_public_declaration_rejects_damage(damage):
    c = {"entry": "SCSIGetFunctionPointers", "declaration": "void SCSIGetFunctionPointers(AdaptecU2HIMFunctions *destination, unsigned int size);",
         "return_kind": "void", "arguments": [0, 168]}
    if damage == "forged": c["declaration"] = c["declaration"].replace("size", "forged")
    elif damage == "missing": c.pop("declaration")
    elif damage == "arity": c["arguments"].pop()
    elif damage == "type": c["declaration"] = c["declaration"].replace("unsigned int", "unsigned short")
    else: c["return_kind"] = "scalar"
    with pytest.raises(ValueError): module("ppc_cases").declared_abi(c)


def test_public_pci_location_aggregate():
    c = {"entry": "SCSICreateAdapterTSCB", "declaration": "AdaptecU2AdapterTSCB *SCSICreateAdapterTSCB( AdaptecU2InitializationTSCB *initialization, AdaptecU2AdapterTSCB *storage, AdaptecU2OSMContext context, AdaptecU2PciLocation location, unsigned int productID);",
         "return_kind": "pointer", "arguments": [0, 0, 0, {"bytes": "01020304112233445566778889abcdef"}, 0x12349005]}
    assert module("ppc_cases").declared_abi(c) == [("pointer", 4), ("pointer", 4), ("pointer", 4), ("aggregate", 16), ("scalar", 4)]


@pytest.mark.parametrize("damage", ["width", "arity", "unknown_alias"])
def test_public_pci_location_rejects_damage(damage):
    case = copy.deepcopy(next(c for c in json.loads((TESTS/"task13-cases.json").read_text())["cases"]
                              if c["entry"] == "SCSICreateAdapterTSCB"))
    if damage == "width": case["arguments"][3]["bytes"] = "00"*12
    elif damage == "arity": case["arguments"].pop()
    else: case["declaration"] = case["declaration"].replace("AdaptecU2PciLocation", "UnknownLocation")
    with pytest.raises(ValueError):
        if damage == "width":
            module("ppc_cases").run_case(OUT/"reference/image.bin", case,
                                        json.loads((TESTS/"task13-contracts.json").read_text()))
        else: module("ppc_cases").declared_abi(case)


@pytest.mark.parametrize("damage", ["identity", "source", "count", "extent", "table", "relocation"])
def test_getter_copy_rejects_damage(damage, monkeypatch):
    native = module("task13_native")
    arena = OUT/"objects/task13/native-arena.macho"
    manifest = json.loads(arena.with_name("arena.json").read_text())
    case = copy.deepcopy(next(c for c in json.loads((TESTS/"task13-cases.json").read_text())["cases"]
                              if c["id"] == "task13-SCSIGetFunctionPointers-168"))
    if damage == "identity": case["id"] += "-forged"
    elif damage == "source": case["external_outcomes"][0]["arguments"][0] = "SCSIConfiguration"
    elif damage == "count": case["external_outcomes"][0]["arguments"][2] = 172
    elif damage == "extent": case["memory"][0]["size"] = 164
    else:
        runner = native.module("ppc_cases")
        load = runner.load_image
        def damaged(path):
            raw, image = load(path)
            if Path(path) == arena and damage == "table":
                record = manifest["definitions"]["_SCSIFuncPtrs"]
                section = next(s for s in image["sections"] if s["address"] <= record["arena_address"] < s["address"]+s["size"])
                offset = section["offset"]+record["arena_address"]-section["address"]
                changed = bytearray(raw); changed[offset+4] ^= 1
                raw = bytes(changed)
                manifest["sha256"] = native.hashlib.sha256(raw).hexdigest().upper()
            elif Path(path).name == "2-AdaptecU2CHIMTables.c.o" and damage == "relocation":
                image = copy.deepcopy(image)
                target = manifest["definitions"]["_SCSIFuncPtrs"]["source_address"]+4
                next(r for r in image["extensions"]["macho"]["relocations"] if r["address"] == target)["target"] = "_SCSIInitialize"
            return raw, image
        monkeypatch.setattr(runner, "load_image", damaged)
        monkeypatch.setattr(native, "module", lambda name: runner)
    with pytest.raises(ValueError): native.getter_copy(case, arena, manifest)


@pytest.mark.parametrize("count", [61, 476])
@pytest.mark.parametrize("damage", ["append_tail", "delete_tail", "duplicate_tail", "wrong_address"])
def test_exact_address_scope_rejects_damage(count, damage):
    rows=[{"address":i} for i in range(count)]
    if damage == "append_tail": rows.append({"address":count})
    elif damage == "delete_tail": rows.pop()
    elif damage == "duplicate_tail": rows[-1]=copy.deepcopy(rows[0])
    else: rows[-1]["address"] = count
    with pytest.raises(ValueError): module("task13_audit").exact_rows(rows,set(range(count)),"fixture")


@pytest.mark.parametrize("damage", ["baseline", "delta", "permission", "duplicate", "attribution"])
def test_snapshot_rejects_damage(damage, monkeypatch):
    gate=module("task13_audit"); contracts=json.loads((TESTS/"task13-contracts.json").read_text())
    rows=contracts["mmio"]["task13-api"]
    key=lambda r:str(r["offset"])+":"+str(r["size"])+":"+"+".join(sorted(r["access"]))
    proof={"contract_delta":copy.deepcopy(rows),"mmio_operations":{key(r):["fixture"] for r in rows}}
    gate.snapshot(REPO,proof)
    if damage == "baseline": monkeypatch.setattr(gate,"BASE_CONTRACTS","0"*64)
    elif damage == "delta": proof["contract_delta"].pop()
    elif damage == "attribution": proof["mmio_operations"].pop(key(rows[0]))
    else:
        row=copy.deepcopy(rows[0])
        if damage == "permission": row["offset"] = 256
        rows.append(row);proof["contract_delta"]=copy.deepcopy(rows)
        load=gate.load
        monkeypatch.setattr(gate,"load",lambda path:copy.deepcopy(contracts) if Path(path).name=="task13-contracts.json" else load(path))
    with pytest.raises(ValueError): gate.snapshot(REPO,proof)


@pytest.mark.parametrize("damage", ["entry", "address", "seed"])
def test_api_context_rejects_damage(damage):
    case={"entry":"SCSIInitialize","evidence":{"entry_address":0x1a4644}}
    seed=0x12345635
    if damage == "entry": case["entry"] = "SCSIRInitialize"
    elif damage == "address": case["evidence"]["entry_address"] += 4
    else: seed=0x12345678
    with pytest.raises(ValueError): module("task13_native").run(OUT/"reference/image.bin",case,seed)


def test_public_machine_input_scope_remains_hardware_only():
    case={"entry":"SCSIhInitializeHardware","evidence":{"entry_address":0x1931e4},
          "declaration":"void SCSIhInitializeHardware(AdaptecU2HHCB *hhcb);","machine_inputs":{"r28":0x12345635}}
    runner=module("ppc_cases");assert runner.machine_inputs(case)=={28:0x12345635}
    case["entry"]="SCSIInitialize";case["evidence"]["entry_address"]=0x1a4644
    with pytest.raises(ValueError): runner.machine_inputs(case)


@pytest.mark.parametrize("damage", ["seed", "machine_input", "entry", "frame", "slot", "load"])
def test_private_byte_scope_rejects_damage(damage,monkeypatch):
    stack=module("task13_stack");case=copy.deepcopy(json.loads((TESTS/"task13-stack-cases.json").read_text())["cases"][0])
    if damage=="seed":case["initial_private_byte"]=128
    elif damage=="machine_input":case["machine_inputs"]={"r27":127}
    elif damage=="entry":case["entry"]="SCSIQueueIOB"
    else:
        mapping=json.loads((TESTS/"task13-stack-mapping.json").read_text())
        if damage=="frame":mapping["reference"]["frame_size"]+=16
        elif damage=="slot":mapping["reference"]["byte_offset"]+=1
        else:mapping["reference"]["loads"][0]["bytes"]="80010038"
        read=Path.read_text
        monkeypatch.setattr(Path,"read_text",lambda path,*a,**k:json.dumps(mapping) if path.name=="task13-stack-mapping.json" else read(path,*a,**k))
    with pytest.raises(ValueError):stack.run(OUT/"reference/image.bin",case)


@pytest.mark.parametrize("damage",["extra_row","missing_row","extra_switch","missing_switch"])
def test_task12_historical_range_rejects_wrong_delta(monkeypatch,damage):
    test=module("test_task12");original=subprocess.check_output
    accepted="92691668a38e846d1ba853f7b969eff25bb28dde";base="608e9f524deeaaa79910e484ee9c5008be3f863c"
    prefix="src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/reconstruction/"
    proof=json.loads((TESTS.parent/"reconstruction/task12.json").read_text());own={b["address"] for b in proof["bodies"]}
    filename="ledger.json" if damage.endswith("row") else "data.json"
    before=json.loads(original(["git","show",base+":"+prefix+filename],cwd=REPO))
    after=json.loads(original(["git","show",accepted+":"+prefix+filename],cwd=REPO))
    if damage=="extra_row":next(e for e in after["entries"] if e["address"] not in own)["reason"]="extra mutation"
    elif damage=="missing_row":
        index=next(i for i,e in enumerate(after["entries"]) if e["address"] in own);after["entries"][index]=before["entries"][index]
    elif damage=="extra_switch":next(o for o in after["objects"] if o["name"]=="switch_230f60")["interpretation"]="extra mutation"
    else:
        index=next(i for i,o in enumerate(after["objects"]) if o["name"]=="switch_230ed4");after["objects"][index]=before["objects"][index]
    def changed(command,*args,**kwargs):
        if command==["git","show",accepted+":"+prefix+filename]:return json.dumps(after).encode()
        return original(command,*args,**kwargs)
    monkeypatch.setattr(subprocess,"check_output",changed)
    with pytest.raises(AssertionError):test.test_him_canonical_git_and_exact_owner_delta({"proof":proof})


@pytest.mark.parametrize("damage",["width","instruction","extent","owner"])
def test_publication_rejects_damage(damage):
    audit=module("task13_audit")
    proof=json.loads((TESTS.parent/"reconstruction/task13.json").read_text())
    cases=json.loads((TESTS/"task13-cases.json").read_text())["cases"]
    case=next(c for c in cases if c["entry"]=="SCSISetMemoryPointer")
    results=json.loads((OUT/"objects/task13/native-results.json").read_text())["results"]
    result=copy.deepcopy(next(r for r in results if r["executed_case_id"]==case["id"]))
    publication=result["publications"][0]
    if damage=="width":publication["size"]=1
    elif damage=="instruction":publication["bytes"]="90000000"
    elif damage=="extent":publication["offset"]=next(m["size"] for m in case["memory"] if m["name"]==publication["region"])
    else:publication["owner"]="SCSIRInitialize"
    manifest=json.loads((OUT/"objects/task13/arena.json").read_text())
    with pytest.raises(ValueError):audit.publication_checks([case],[result],manifest,{b["address"]:b for b in proof["bodies"]})


def test_task13_canonical_git_and_exact_owner_delta():
    audit=module("task13_audit");prefix=audit.DRIVER/"reconstruction"
    blob=lambda revision,name:subprocess.check_output(["git","show",revision+":"+(prefix/name).as_posix()],cwd=REPO)
    proof_raw=blob("HEAD","task13.json");proof=json.loads(proof_raw)
    assert audit.identity.canonical((TESTS.parent/"reconstruction/task13.json").read_bytes(),Path("task13.json"))==proof_raw
    own={b["address"] for b in proof["bodies"]};assert len(own)==61
    before=json.loads(blob(audit.BASE,"ledger.json"));after=json.loads(blob("HEAD","ledger.json"))
    old=audit.exact_rows(before["entries"],{e["address"] for e in before["entries"]},"before476")
    assert len(old)==476
    new=audit.exact_rows(after["entries"],old,"after476")
    assert sum(e["status"]=="control-flow-confirmed" for e in new.values())==429
    for address,record in new.items():
        if address not in own:assert record==old[address]
        else:
            assert record["status"]=="control-flow-confirmed"
            assert record["artifacts"]==[{"kind":"source-native-control-flow-and-frozen-cases","path":(prefix/"task13.json").as_posix(),"sha256":audit.sha(proof_raw)}]
    old_data=json.loads(blob(audit.BASE,"data.json"));new_data=json.loads(blob("HEAD","data.json"))
    expected=copy.deepcopy(old_data)
    assigned=[r for r in expected["objects"] if r.get("required_task")==13];assert len(assigned)==11
    for record in assigned:record.update(status="recovered",owner_evidence="reconstruction/task13.json")
    assert new_data==expected
    old_map=json.loads(blob(audit.BASE,"source-map.json"));new_map=json.loads(blob("HEAD","source-map.json"))
    assert len(new_map["mapped"])==436 and len(new_map["unmapped"])==24 and len(new_map["duplicate_candidates"])==16
    assert {e["address"] for e in old_map["unmapped"]}-{e["address"] for e in new_map["unmapped"]}==own
    assert [e for e in old_map["mapped"] if e["address"] not in own]==[e for e in new_map["mapped"] if e["address"] not in own]
