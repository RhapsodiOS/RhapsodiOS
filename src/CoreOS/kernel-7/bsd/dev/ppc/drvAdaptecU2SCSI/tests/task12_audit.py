"""Authenticate HIM source, native products, actual execution and precise MMIO attribution."""

import collections
import importlib.util
import json
import tempfile
from pathlib import Path

from binrecon.macho import load_image
from binrecon.source_map import source_sites


def module(name):
    spec=importlib.util.spec_from_file_location("au2_him_audit_"+name,Path(__file__).with_name(name+".py"))
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value


identity=module("task12_identity")
sha,load,DRIVER=identity.sha,identity.load,identity.DRIVER


def snapshot(repo,proof):
    tests=repo/DRIVER/"tests";base=load(tests/"task11-contracts.json");current=load(tests/"task12-contracts.json")
    rows=current["mmio"].pop("task12-hardware",None)
    if (sha(identity.canonical((tests/"task11-contracts.json").read_bytes(),tests/"task11-contracts.json")) != proof["baseline_contracts_sha256"] or
            current != base or rows != proof["contract_delta"]):
        raise ValueError("HIM accepted baseline/snapshot delta differs")
    wanted=collections.defaultdict(set)
    for filename in ("task12-cases.json","task12-context-cases.json"):
        for c in load(tests/filename)["cases"]:
            for o in c["external_outcomes"]:
                if "register" in o:wanted[o["offset"],o["size"]].add(o["access"])
    actual={(r["offset"],r["size"]):set(r["access"]) for r in rows}
    if len(actual)!=len(rows) or actual!=wanted:
        raise ValueError("HIM unused/missing/speculative register permission")
    for r in rows:
        key=str(r["offset"])+":"+str(r["size"])+":"+"+".join(sorted(r["access"]))
        if r["evidence"]!="reconstruction/task12.json#/mmio_operations/"+key or not proof["mmio_operations"].get(key):
            raise ValueError("HIM register permission lacks exact attribution")


def native_inputs(repo,objects,proof):
    manifest=load(objects/"objects.json");inputs=load(objects/"native-inputs.json")
    if (manifest["source_revision"]!=proof["native_actual_base_revision"] or inputs["source_revision"]!=manifest["source_revision"] or
            inputs.get("work_in_progress") is not True or manifest["configuration"]!="RELEASE_PPC" or
            len(manifest["objects"])!=1 or set(inputs["inputs"])!=set(identity.NATIVE_INPUTS)):
        raise ValueError("HIM actual native producer differs")
    if set(proof["canonical_inputs"])!=set(identity.NATIVE_INPUTS):raise ValueError("HIM canonical compiled input closure incomplete")
    for name in identity.NATIVE_INPUTS:
        path=DRIVER/name;blob=identity.git(repo,proof["canonical_input_revision"],path)
        if (sha(blob)!=proof["canonical_inputs"][name] or sha(identity.canonical((repo/path).read_bytes(),path))!=sha(blob) or
                inputs["inputs"][name]["staged_sha256"]!=sha(blob)):
            raise ValueError("HIM all-seven compiled/canonical input differs: "+name)
    for relative,digest in proof["native_artifacts"].items():
        if sha((repo/relative).read_bytes())!=digest:raise ValueError("HIM preserved native artifact changed: "+relative)
    copies=proof["native_build_provenance_copies"]
    if {Path(p).name for p in copies}!={"native.py","native.ps1","build-batch4.sh","batch4-inputs.json"}:
        raise ValueError("HIM historical compiler launcher/input copies incomplete")
    for relative,record in copies.items():
        path=Path(relative);blob=identity.git(repo,proof["canonical_input_revision"],path)
        if (sha((repo/record["original"]).read_bytes())!=record["working_sha256"] or
                sha(blob)!=record["git_blob_sha256"] or
                identity.canonical((repo/path).read_bytes(),path)!=blob):
            raise ValueError("HIM historical compiler launcher/input identity differs")
    for filename,names in (("source-inputs.sha256",identity.NATIVE_INPUTS),("header-inputs.sha256",identity.NATIVE_INPUTS[1:])):
        actual={}
        for line in (objects/filename).read_text().splitlines():
            digest,name=line.split(maxsplit=1)
            if not name.startswith("bsd/dev/ppc/drvAdaptecU2SCSI/") or Path(name).name in actual:
                raise ValueError("HIM compiled source manifest malformed")
            actual[Path(name).name]=digest.upper()
        if actual!={n:proof["canonical_inputs"][n] for n in names}:raise ValueError("HIM compiled source manifest differs")
    import tarfile
    with tarfile.open(repo/proof["native_input_archive"]) as stream:
        members=[m for m in stream.getmembers() if m.isfile()]
        if {m.name for m in members}!=set(identity.NATIVE_INPUTS):raise ValueError("HIM input archive closure differs")
        for m in members:
            if sha(stream.extractfile(m).read())!=proof["canonical_inputs"][m.name]:raise ValueError("HIM compiled archive bytes differ")
    with tarfile.open(repo/proof["native_product_archive"]) as stream:
        for m in stream.getmembers():
            if m.isfile() and stream.extractfile(m).read()!=(objects/Path(m.name).name).read_bytes():
                raise ValueError("HIM actual product archive differs")
    item=manifest["objects"][0]
    if (item["source"]!="bsd/dev/ppc/drvAdaptecU2SCSI/AdaptecU2CHIMHIM.c" or item["cpu_type"]!=18 or
            item["path"]!="1-AdaptecU2CHIMHIM.c.o" or sha((objects/item["path"]).read_bytes())!=item["sha256"] or
            item["source_sha256"]!=proof["canonical_inputs"]["AdaptecU2CHIMHIM.c"] or
            (objects/"1.command").read_text().strip()!=item["command"] or (objects/"1.log").read_bytes()):
        raise ValueError("HIM actual native object/command/diagnostics differs")
    return objects/item["path"]


def actual_public(cases,contracts,result,proof,runner):
    if (result["binary_sha256"]!=proof["reference_sha256"] or result["source_revision"]!=proof["execution_revision"] or
            result["cases_sha256"]!=runner.digest(cases) or result["contracts_sha256"]!=runner.digest(contracts) or
            result["runner_version"]!=proof["runner_version"] or
            result["selected_case_ids"]!=[c["id"] for c in cases["cases"]] or len(result["results"])!=135):
        raise ValueError("HIM public execution identity/scope differs")
    for c,r in zip(cases["cases"],result["results"]):
        if (c.get("ack_exhaustion") or c.get("machine_inputs") or r["executed_case_id"]!=c["id"] or
                not r["returned_to_sentinel"] or r["unknown_calls"] or r["observations"]!=c["expected"] or
                not 0<r["instructions"]<=c["instruction_limit"]<=4000000):
            raise ValueError("HIM public actual observation differs: "+c["id"])


def mmio_index(results,contracts,owners,accepted):
    records=collections.defaultdict(dict)
    for case_id,result in results:
        counts=collections.Counter()
        for op in result["mmio_operations"]:
            address=op["owner_address"]
            if address not in owners or owners[address]["name"]!=op["owner"]:
                raise ValueError("HIM MMIO actual operation owner differs")
            proof="task12.json" if op["owner"].startswith("SCSIH") else accepted.get(address)
            if proof is None:raise ValueError("HIM MMIO callee lacks accepted proof")
            counts[op["offset"],op["size"],op["direction"]]+=op["count"]
            row=next((r for r in contracts["mmio"]["task12-hardware"] if r["offset"]==op["offset"] and
                      r["size"]==op["size"] and op["direction"] in r["access"]),None)
            if row is None:raise ValueError("HIM observed register lacks frozen permission")
            key=str(row["offset"])+":"+str(row["size"])+":"+"+".join(sorted(row["access"]))
            record={k:v for k,v in op.items() if k!="count"};record["accepted_owner_proof"]=proof
            signature=json.dumps(record,sort_keys=True)
            if signature not in records[key]:records[key][signature]={**record,"case_ids":[]}
            if case_id not in records[key][signature]["case_ids"]:records[key][signature]["case_ids"].append(case_id)
        trace=collections.Counter((int(x["target"].split("+")[1]),x["size"],x["access"]) for x in result["observations"]["trace"]
                                  if x.get("target","").startswith("registers+"))
        if counts!=trace:raise ValueError("HIM actual MMIO attribution does not account for every observation")
    return {key:sorted(value.values(),key=lambda r:json.dumps(r,sort_keys=True)) for key,value in sorted(records.items())}


def audit(evidence,repo,objects):
    driver=repo/DRIVER;proof_path=driver/"reconstruction/task12.json"
    if objects is None or not proof_path.is_file():raise ValueError("missing HIM native/source proof")
    proof=load(proof_path);runner=module("ppc_cases");native=module("task12_native")
    cases=load(driver/"tests/task12-cases.json");contexts=load(driver/"tests/task12-context-cases.json")
    contracts=load(driver/"tests/task12-contracts.json")
    binary=native_inputs(repo,objects,proof);raw,image=load_image(binary)
    snapshot(repo,proof)
    if (proof["reference_sha256"]!=sha(evidence["payload"]) or
            set(proof["accepted_owner_proofs"])!={"task"+str(i)+".json" for i in range(5,12)}):
        raise ValueError("HIM reference/dependency closure differs")
    for name,digest in proof["accepted_owner_proofs"].items():
        if sha(identity.canonical((driver/"reconstruction"/name).read_bytes(),Path(name)))!=digest:
            raise ValueError("HIM accepted dependency proof changed")
    for relative,record in proof["dependencies"].items():
        path=Path(relative)
        raw=(repo/path).read_bytes()
        if sha(identity.canonical(raw,path) if record["canonical"] else raw)!=record["sha256"]:
            raise ValueError("HIM accepted dependency source/native changed")
    used={x["entry"] for document in (cases,contexts) for c in document["cases"] for x in c["internal"]}
    if set(proof["reference_callees"])!=used:raise ValueError("HIM real reference callee scope differs")
    frozen={f["names"][0].removeprefix("_"):f for f in evidence["frozen"].values()}
    for name,record in proof["reference_callees"].items():
        f=frozen[name];s=next(s for s in evidence["macho"]["sections"] if s["address"]<=f["address"]<s["address"]+s["size"])
        offset=s["offset"]+f["address"]-s["address"]
        if (record["address"]!=f["address"] or record["size"]!=f["size"] or
                record["sha256"]!=sha(evidence["payload"][offset:offset+f["size"]])):
            raise ValueError("HIM actual pinned reference callee changed: "+name)
    expected=set(evidence["document"]["owners"]["AdaptecU2CHIMHIM.c"])
    bodies={b["address"]:b for b in proof["bodies"]}
    if set(bodies)!=expected or len(bodies)!=31:raise ValueError("HIM exact31/interleaved body closure differs")
    sites=source_sites(repo,driver);ledger={e["address"]:e for e in load(driver/"reconstruction/ledger.json")["entries"]}
    leaf=module("task11_native")
    native_names={s["name"] for s in image["symbols"] if s["binding"]=="external" and s["section"]=="__TEXT,__text"}
    if native_names!={b["name"] for b in bodies.values()}:raise ValueError("HIM31 native symbol closure differs")
    for address,b in bodies.items():
        start,code,_=leaf.body(binary,b["name"].removeprefix("_"));location=(DRIVER.as_posix()+"/AdaptecU2CHIMHIM.c",b["source_line"])
        rel=[r for r in image["extensions"]["macho"]["relocations"] if r["section"]=="__TEXT,__text" and start<=r["address"]<start+len(code)]
        if (b["name"] not in evidence["frozen"][address]["names"] or b["reference_size"]!=evidence["frozen"][address]["size"] or
                (start,len(code),sha(code),rel)!=(b["native_address"],b["native_size"],b["native_sha256"],b["native_relocations"]) or
                sites.get(b["name"])!=[location] or len(b["control_flow"])<35 or not b["cases"] or
                (ledger[address]["source_path"],ledger[address]["source_line"])!=location or ledger[address]["status"]!="control-flow-confirmed" or
                not any(a["path"]==proof_path.relative_to(repo).as_posix() and a["sha256"]==sha(identity.canonical(proof_path.read_bytes(),proof_path)) for a in ledger[address]["artifacts"])):
            raise ValueError("HIM source/native/ledger/control-flow binding differs: "+b["name"])
    public=load(objects/"reference-results.json")
    supplement=load(objects/"native-results.json");manifest=load(objects/"arena.json")
    if (set(public)!={"reference"} or sha((objects/"reference-results.json").read_bytes())!=proof["public_results_sha256"] or
            sha((objects/"native-results.json").read_bytes())!=proof["native_results_sha256"] or supplement["preflight"] or
            supplement["execution_revision"]!=proof["execution_revision"] or supplement["reference_sha256"]!=proof["reference_sha256"] or
            supplement["cases_sha256"]!=runner.digest(cases) or supplement["contexts_sha256"]!=runner.digest(contexts) or
            supplement["contracts_sha256"]!=runner.digest(contracts) or len(supplement["results"])!=135):
        raise ValueError("HIM actual raw execution archive/producer differs")
    actual_public(cases,contracts,public["reference"],proof,runner)
    execution_inputs(repo,supplement,proof)
    if set(proof["execution_artifacts"])!={"tools/binrecon/out/adaptecu2scsi-ppc/reference/reference.json"}:
        raise ValueError("HIM public reference metadata input is unpinned")
    for path,digest in proof["execution_artifacts"].items():
        if sha((repo/path).read_bytes())!=digest:raise ValueError("HIM public reference metadata input changed")
    # Reconstruct from the actual relocation tables, never trust an arena manifest alone.
    linker=module("task12_link")
    with tempfile.TemporaryDirectory() as temporary:
        actual_manifest=linker.link(objects.parent.parent/"reference/image.bin",
                                   [Path(path) for path in manifest["objects"]],Path(temporary)/"arena.macho")
    if (actual_manifest!=manifest or supplement["arena_sha256"]!=manifest["sha256"] or
            sha((objects/"native-arena.macho").read_bytes())!=manifest["sha256"] or
            supplement["arena_manifest_sha256"]!=sha((objects/"arena.json").read_bytes())):
        raise ValueError("HIM genuine native arena relocations differ")
    if supplement["switch"]!=native.switch_graph(binary):raise ValueError("HIM assigned native switch closure differs")
    data=next(o for o in load(driver/"reconstruction/data.json")["objects"] if o["name"]=="switch_230ed4")
    if data["status"]!="recovered" or data.get("owner_evidence")!="reconstruction/task12.json":
        raise ValueError("HIM assigned switch is pending or unbound")
    for c,r in zip(cases["cases"],supplement["results"]):
        adapted=native.adapt(c,manifest)
        if (r["executed_case_id"]!=c["id"] or r["observations"]!=adapted["expected"] or not r["returned_to_sentinel"] or r["unknown_calls"] or
                set(map(int,r["nonvolatile_preserved"]))!=set(range(14,32))):
            raise ValueError("HIM compiled actual observation/ABI differs: "+c["id"])
    if len(supplement["contexts"])!=2 or {c["initial_r28"] for c in contexts["cases"]}!={0x12345635,0x89abcda6}:
        raise ValueError("HIM two architectural entry contexts differ")
    for c,pair in zip(contexts["cases"],supplement["contexts"]):
        if pair["id"]!=c["id"] or pair["initial_r28"]!=c["initial_r28"]:raise ValueError("HIM caller context case differs")
        for label in ("reference","native"):
            r=pair[label]
            if (r["observations"]!=c["expected"] or not r["returned_to_sentinel"] or r["unknown_calls"] or
                    r["nonvolatile_preserved"]["28"]!=c["initial_r28"] or
                    {e["entry"] for e in r["entries"]}!={"SCSIRInitialize","SCSIHInitialize","SCSIhInitializeHardware"} or
                    any(e["r28"]!=c["initial_r28"] for e in r["entries"]) or
                    not any(t.get("target")=="registers+255" and t.get("value")==c["initial_r28"]&255 for t in r["observations"]["trace"])):
                raise ValueError("HIM actual incoming-r28 caller/MMIO/return proof differs")
    if [c["id"] for c in supplement["leaves"]]!=["task12-native-freeunit-unit","task12-native-freeunit-hhcb"]:
        raise ValueError("HIM mixed FreeUnit scope differs")
    for pair in supplement["leaves"]:
        if pair["reference"]["writes"] or pair["native"]["writes"] or pair["reference"]["memory"]!=pair["native"]["memory"]:
            raise ValueError("HIM FreeUnit no-op differs")
    owners={a:{"name":f["names"][0].removeprefix("_"),"size":f["size"]} for a,f in evidence["frozen"].items()}
    accepted={b["address"]:name for name in proof["accepted_owner_proofs"] for b in load(driver/"reconstruction"/name).get("bodies",[])}
    results=[(r["executed_case_id"],r) for r in supplement["results"]]
    results += [(p["id"]+"/"+label,p[label]) for p in supplement["contexts"] for label in ("reference","native")]
    if mmio_index(results,contracts,owners,accepted)!=proof["mmio_operations"]:
        raise ValueError("HIM exact operation/callsite/case attribution differs")
    validate_operations(objects,manifest,results,owners)
    publication_checks(cases,supplement["results"])
    for b in bodies.values():
        observed={r["executed_case_id"] for r in supplement["results"] if any(e["entry"]==b["name"].removeprefix("_") for e in r["entries"])}
        if b["name"]=="_SCSIHFreeUnitHandle":observed={p["id"] for p in supplement["leaves"]}
        if set(b["cases"])!=observed:raise ValueError("HIM body coverage is only an unexecuted range: "+b["name"])
        callees=collections.defaultdict(list)
        for r in supplement["results"]:
            for c in r["him_calls"]:
                if c["owner"]==b["name"].removeprefix("_") and r["executed_case_id"] not in callees[c["callee"]]:
                    callees[c["callee"]].append(r["executed_case_id"])
        if dict(callees)!=b["actual_callees"]:raise ValueError("HIM actual forwarding target/caller coverage differs")
    return proof,public["reference"],supplement


def execution_inputs(repo,result,proof):
    current=identity.closure(repo,proof["execution_revision"])
    if set(result["execution_inputs"])!={p.as_posix() for p in identity.EXECUTION_INPUTS}:
        raise ValueError("HIM execution import/input closure incomplete")
    for path,record in result["execution_inputs"].items():
        if current[path]["git_blob_sha256"]!=record["git_blob_sha256"]:raise ValueError("HIM executed canonical input changed: "+path)
    if result["execution_inputs"]!=proof["execution_inputs"]:raise ValueError("HIM historical raw input manifest differs")


def publication_checks(cases,results):
    for c,r in zip(cases["cases"],results):
        name=c["entry"];writes=[p for p in r["publications"] if p["owner"]==name]
        footprint=[(p["offset"],p["size"]) for p in writes]
        if name=="SCSIHGetMemoryTable":
            wanted=[(o,1) for o in (14,0,12,2,26,50,24,48,1,25,49,3,13,27,51,15)]
            wanted += [(o,2) for o in (4,28,6,16,30,18,54)]
            if collections.Counter(footprint)!=collections.Counter(wanted):raise ValueError("HIM exact byte/halfword table publication differs")
        if name=="SCSIHSetUnitHandle" and footprint!=[(0,4),(4,1),(5,1),(8,4)]:
            raise ValueError("HIM unit pointer/byte publication differs")
        if name=="SCSIHApplyMemoryTable" and (footprint[:3]!=[(196,4),(1336,4),(208,4)] or footprint[3:] not in ([],[(7,1)])):
            raise ValueError("HIM memory pointers-before-failure/count width differs")
        if name=="SCSIHPutHWInformation":
            hhcb=next(m for m in c["memory"] if m["name"]=="adapter")
            mode=bytes.fromhex(hhcb["bytes"])[c["arguments"][1]["offset"]+19]
            fifo=[p["value"] for p in writes if p["offset"]==41]
            if len(fifo)!=(2 if mode==1 else 1) or any(p["size"]!=1 for p in writes if p["offset"]==41):
                raise ValueError("HIM historical double byte FIFO publication differs")
            if any(p["size"]!=4 for p in writes if p["offset"]==36):raise ValueError("HIM profile flag word publication differs")


def validate_operations(objects,manifest,results,owners):
    raw,image=load_image(objects/"native-arena.macho")
    def word(address):
        s=next((s for s in image["sections"] if s["address"]<=address and address+4<=s["address"]+s["size"]),None)
        if s is None:raise ValueError("HIM operation instruction exceeds mapped image")
        offset=s["offset"]+address-s["address"]
        return raw[offset:offset+4]
    for _,r in results:
        for o in r["mmio_operations"]:
            owner=owners[o["owner_address"]];native=manifest["definitions"].get("_"+o["owner"])
            bounds=[(o["owner_address"],owner["size"])]
            if native:bounds.append((native["arena_address"],native["size"]))
            if not any(s==o["owner_code_address"] and s<=o["callsite"]<s+n for s,n in bounds):
                raise ValueError("HIM MMIO callsite exceeds actual owner")
            code=word(o["callsite"]);w=int.from_bytes(code,"big")
            if code.hex()!=o["callsite_bytes"] or not w&1:raise ValueError("HIM MMIO genuine linking instruction differs")
            if w>>26==18 and not w&2:
                d=w&0x3fffffc;target=o["callsite"]+d-(0x4000000 if d&0x2000000 else 0)
                if target!=o["primitive_address"]:raise ValueError("HIM MMIO genuine linked target differs")
            elif w not in (0x4e800021,0x4e800421):raise ValueError("HIM MMIO unapproved link/veneer form")
            primitive=next((s for s in image["symbols"] if s["name"]=="_"+o["primitive"]),None)
            if (primitive is None or primitive["address"]!=o["primitive_address"] or
                    not primitive["address"]<=o["primitive_instruction"]<primitive["address"]+owners[primitive["address"]]["size"] or
                    word(o["primitive_instruction"]).hex()!=o["primitive_bytes"] or o["count"]<=0):
                raise ValueError("HIM exact Task5 primitive instruction differs")


def family(repo,out,name):
    verify=module("verify")
    proof,public,native=audit(verify.authenticate_reference(out/"reference",repo),repo,out/"objects/task12")
    cases=load(repo/DRIVER/"tests/task12-cases.json")["cases"]
    selected=[c for c in cases if c["family"]==name]
    if len(selected)!={"memory":54,"queue":56,"profile":25}[name]:raise ValueError("HIM named family scope differs")
    by_id={r["executed_case_id"]:r for r in public["results"]}
    if any(by_id[c["id"]]["observations"]!=c["expected"] for c in selected):raise ValueError("HIM named family actual observations missing/stale")
    return proof
