"""Fail closed on transport/API source, native products and actual execution."""

import collections
import importlib.util
import json
import tarfile
import tempfile
from pathlib import Path
from binrecon.macho import load_image
from binrecon.source_map import source_sites


def module(name):
    spec=importlib.util.spec_from_file_location("au2_api_audit_"+name,Path(__file__).with_name(name+".py"))
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value


identity=module("task13_identity")
sha,load,DRIVER=identity.sha,identity.load,identity.DRIVER
SOURCES=("AdaptecU2CHIMTransport.c","AdaptecU2CHIMAPI.c")
BASE="92691668a38e846d1ba853f7b969eff25bb28dde"
BASE_CONTRACTS="4A5113A88B7D24AF5093A8E6FAC794717B936F154A4C38C864AC5F4E03B3E0C0"
OWNER_PROOFS={"AdaptecU2OSMServices.m":"task5.json","AdaptecU2CHIMOSD.c":"task5.json",
              "AdaptecU2CHIMHardware.c":"task6.json","AdaptecU2CHIMSCB.c":"task7.json",
              "AdaptecU2CHIMConfig.c":"task8.json","AdaptecU2CHIMNegotiation.c":"task9.json",
              "AdaptecU2CHIMRecovery.c":"task10.json","AdaptecU2CHIMResource.c":"task11.json",
              "AdaptecU2CHIMHIM.c":"task12.json",SOURCES[0]:"task13.json",SOURCES[1]:"task13.json"}


def exact_rows(rows,expected,label):
    result={r["address"]:r for r in rows}
    if len(rows)!=len(expected) or len(result)!=len(rows) or set(result)!=set(expected):
        raise ValueError("API "+label+" address cardinality differs")
    return result


def snapshot(repo,proof):
    tests=repo/DRIVER/"tests";baseline=(tests/"task12-contracts.json").read_bytes()
    current=load(tests/"task13-contracts.json");rows=current["mmio"].pop("task13-api",None)
    if sha(identity.canonical(baseline,Path("task12-contracts.json")))!=BASE_CONTRACTS or current!=json.loads(baseline) or rows!=proof["contract_delta"]:
        raise ValueError("API immutable baseline/snapshot delta differs")
    wanted=collections.defaultdict(set)
    for name in ("task13-cases.json","task13-context-cases.json","task13-stack-cases.json"):
        for c in load(tests/name)["cases"]:
            if any(m.get("mmio")!="task13-api" for m in c["memory"] if "mmio" in m):
                raise ValueError("API fixture register snapshot differs")
            for o in c["external_outcomes"]:
                if "register" in o:wanted[o["offset"],o["size"]].add(o["access"])
    actual={(r["offset"],r["size"]):set(r["access"]) for r in rows}
    baseline_rows={(r["offset"],r["size"]):set(r["access"]) for r in current["mmio"]["task12-hardware"]}
    if len(rows)!=86 or sum(map(len,actual.values()))!=107 or len(actual)!=len(rows) or actual!=wanted or any(v-baseline_rows.get(k,set()) for k,v in actual.items()):
        raise ValueError("API snapshot speculative/missing/duplicate permission")
    for r in rows:
        key=str(r["offset"])+":"+str(r["size"])+":"+"+".join(sorted(r["access"]))
        if r["evidence"]!="reconstruction/task13.json#/mmio_operations/"+key or not proof["mmio_operations"].get(key):
            raise ValueError("API register permission lacks exact operation attribution")


def native_inputs(repo,objects,proof):
    if (proof["native_actual_base_revision"]!=BASE or set(proof["canonical_inputs"])!=set(identity.NATIVE_INPUTS) or
            set(proof["native_producers"])!=set(SOURCES)):
        raise ValueError("API true native producer/input closure differs")
    for name in identity.NATIVE_INPUTS:
        path=DRIVER/name;blob=identity.git(repo,proof["canonical_input_revision"],path)
        if (sha(blob)!=proof["canonical_inputs"][name] or b"\r" in blob or
                identity.canonical((repo/path).read_bytes(),path)!=blob):
            raise ValueError("API eight actual LF inputs differ from canonical source: "+name)
    for path,digest in proof["native_artifacts"].items():
        if sha((repo/path).read_bytes())!=digest:raise ValueError("API preserved native artifact changed: "+path)
    for path,record in proof["native_build_provenance_copies"].items():
        blob=identity.git(repo,proof["canonical_input_revision"],Path(path))
        if (sha(blob)!=record["git_blob_sha256"] or identity.canonical((repo/path).read_bytes(),Path(path))!=blob or
                sha((repo/record["original"]).read_bytes())!=record["working_sha256"]):
            raise ValueError("API actual compiler launcher/input provenance differs")
    if {Path(p).name for p in proof["native_build_provenance_copies"]}!={"build.py","build.ps1","build-b9.sh","b9-inputs.json","build-transport.py","build-transport.ps1","build-b10.sh","b10-inputs.json"}:
        raise ValueError("API compiler provenance copy closure incomplete")
    selected=load(objects/"objects.json");selected_inputs=load(objects/"native-inputs.json")
    if (selected.get("kind")!="selected-original-translation-units" or selected.get("source_revision")!=BASE or
            selected.get("canonical_input_revision")!=proof["canonical_input_revision"] or selected.get("configuration")!="RELEASE_PPC" or
            selected_inputs.get("kind")!="selected-original-input-union" or selected_inputs.get("source_revision")!=BASE or
            selected_inputs.get("canonical_input_revision")!=proof["canonical_input_revision"] or selected_inputs.get("work_in_progress") is not True or
            len(selected["objects"])!=2 or set(selected_inputs["translation_units"])!=set(SOURCES) or set(selected_inputs["inputs"])!=set(identity.NATIVE_INPUTS)):
        raise ValueError("API selected original translation-unit index differs")
    binaries={}
    for index,source in enumerate(SOURCES,1):
        producer=proof["native_producers"][source];directory=repo/producer["objects_root"]
        manifest=load(repo/producer["manifest"]);inputs=load(repo/producer["inputs"])
        staged=(source,*identity.NATIVE_INPUTS[2:]) if source==SOURCES[0] else identity.NATIVE_INPUTS
        compiled=(source,*identity.NATIVE_INPUTS[2:])
        if (manifest["source_revision"]!=BASE or inputs["source_revision"]!=BASE or inputs.get("work_in_progress") is not True or
                manifest["configuration"]!="RELEASE_PPC" or set(inputs["inputs"])!=set(staged) or
                {Path(r["source"]).name for r in manifest["objects"]}!=({SOURCES[0]} if index==1 else set(SOURCES)) or
                producer["compiled_inputs"]!=list(compiled)):
            raise ValueError("API distinct b10 Transport/b9 API actual producers differ")
        for name in compiled:
            if inputs["inputs"][name]["staged_sha256"]!=proof["canonical_inputs"][name]:raise ValueError("API actual translation-unit input differs from canonical source")
        with tarfile.open(repo/producer["input_archive"]) as stream:
            members=[m for m in stream.getmembers() if m.isfile()]
            if len(members)!=len(staged) or {m.name for m in members}!=set(staged):raise ValueError("API actual staged archive closure differs")
            for m in members:
                if sha(stream.extractfile(m).read())!=inputs["inputs"][m.name]["staged_sha256"]:raise ValueError("API original staged input archive differs")
        with tarfile.open(repo/producer["product_archive"]) as stream:
            for m in stream.getmembers():
                if m.isfile() and stream.extractfile(m).read()!=(directory/Path(m.name).name).read_bytes():raise ValueError("API actual product archive differs")
        for filename,names in (("source-inputs.sha256",staged),("header-inputs.sha256",identity.NATIVE_INPUTS[2:])):
            actual={}
            for line in (directory/filename).read_text().splitlines():
                digest,name=line.split(maxsplit=1)
                if not name.startswith("bsd/dev/ppc/drvAdaptecU2SCSI/") or Path(name).name in actual:raise ValueError("API compiled input manifest malformed")
                actual[Path(name).name]=digest.upper()
            if actual!={n:inputs["inputs"][n]["staged_sha256"] for n in names}:raise ValueError("API original source/header manifests differ")
        item=next(r for r in manifest["objects"] if Path(r["source"]).name==source)
        selected_item={**item,"producer_manifest":producer["manifest"],"producer_inputs":producer["inputs"]}
        selected_unit={"producer_manifest":producer["manifest"],"producer_inputs":producer["inputs"],"compiled_inputs":list(compiled)}
        if (selected["objects"][index-1]!=selected_item or selected_inputs["translation_units"][source]!=selected_unit or
                any(selected_inputs["inputs"][n]!=inputs["inputs"][n] for n in compiled)):
            raise ValueError("API selected index relabels an original producer")
        original_index=manifest["objects"].index(item)+1;path=str(index)+"-"+source+".o"
        if (item["source"]!="bsd/dev/ppc/drvAdaptecU2SCSI/"+source or item["path"]!=path or item["cpu_type"]!=18 or
                item["sha256"]!=sha((objects/path).read_bytes()) or item["source_sha256"]!=proof["canonical_inputs"][source] or
                (objects/path).read_bytes()!=(directory/item["path"]).read_bytes() or
                (directory/(str(original_index)+".command")).read_text().strip()!=item["command"] or (directory/(str(original_index)+".log")).read_bytes() or
                (objects/(str(index)+".command")).read_text().strip()!=item["command"] or (objects/(str(index)+".log")).read_bytes()):
            raise ValueError("API actual native object/command/diagnostics differs")
        binaries[source]=objects/path
    expected_manifest="".join(proof["canonical_inputs"][n].lower()+"  bsd/dev/ppc/drvAdaptecU2SCSI/"+n+"\n" for n in identity.NATIVE_INPUTS)
    if (objects/"source-inputs.sha256").read_text()!=expected_manifest:
        raise ValueError("API selected source manifest differs")
    return binaries


def scopes(evidence,repo,objects,proof,binaries):
    expected={a for source in SOURCES for a in evidence["document"]["owners"][source]}
    bodies={b["address"]:b for b in proof["bodies"]}
    if len(proof["bodies"])!=61 or len(bodies)!=61 or set(bodies)!=expected:raise ValueError("API exact61 owner body closure differs")
    ledger=load(repo/DRIVER/"reconstruction/ledger.json")["entries"]
    by_address=exact_rows(ledger,evidence["frozen"],"ledger476")
    baseline=json.loads(identity.git(repo,BASE,DRIVER/"reconstruction/ledger.json"))["entries"]
    if {e["address"]:e for e in baseline if e["address"] not in expected}!={a:e for a,e in by_address.items() if a not in expected}:
        raise ValueError("API ledger changed another owner's rows")
    sites=source_sites(repo,repo/DRIVER);leaf=module("task11_native")
    proof_path=DRIVER/"reconstruction/task13.json";proof_hash=sha(identity.canonical((repo/proof_path).read_bytes(),proof_path))
    for source,path in binaries.items():
        _,image=load_image(path)
        wanted={b["name"] for b in bodies.values() if b["source"]==source}
        actual={s["name"] for s in image["symbols"] if s["binding"]=="external" and s["section"]=="__TEXT,__text"}
        if actual!=wanted or len(actual)!=(19 if source==SOURCES[0] else 42):raise ValueError("API native19/42 symbol closure differs")
    functions={f["address"]:f for f in evidence["document"]["functions"]}
    for address,b in bodies.items():
        f=functions[address];start,code,image=leaf.body(binaries[b["source"]],b["name"].removeprefix("_"))
        rel=[r for r in image["extensions"]["macho"]["relocations"] if r["section"]=="__TEXT,__text" and start<=r["address"]<start+len(code)]
        site=((DRIVER/b["source"]).as_posix(),b["source_line"])
        entry=by_address[address]
        section=next(s for s in evidence["macho"]["sections"] if s["address"]<=address and address+f["size"]<=s["address"]+s["size"])
        offset=section["offset"]+address-section["address"];reference_code=evidence["payload"][offset:offset+f["size"]]
        accesses=module("task13_graph").memory_accesses
        if (b["name"] not in f["names"] or b["reference_size"]!=f["size"] or b["reference_blocks"]!=f["blocks"] or b["reference_calls"]!=f["calls"] or
                b["reference_sha256"]!=sha(reference_code) or b["reference_memory_instructions"]!=accesses(address,reference_code) or b["native_memory_instructions"]!=accesses(start,code) or
                (start,len(code),sha(code),rel)!=(b["native_address"],b["native_size"],b["native_sha256"],b["native_relocations"]) or
                sites.get(b["name"])!=[site] or len(b["control_flow"])<35 or not b["cases"] or
                (entry["source_path"],entry["source_line"])!=site or entry["status"]!="control-flow-confirmed" or
                not any(a["path"]==proof_path.as_posix() and a["sha256"]==proof_hash for a in entry["artifacts"])):
            raise ValueError("API source/native/control-flow/ledger differs: "+b["name"])
    return bodies


def mmio_index(results,contracts,owners,accepted):
    records=collections.defaultdict(dict)
    for case_id,result in results:
        counts=collections.Counter()
        for op in result["mmio_operations"]:
            address=op["owner_address"]
            if address not in owners or owners[address]["names"][0].removeprefix("_")!=op["owner"]:raise ValueError("API exact MMIO owner differs")
            proof=accepted.get(address)
            caller=op.get("api_caller")
            if proof is None or caller is None or accepted.get(caller["address"])!="task13.json" or owners[caller["address"]]["names"][0].removeprefix("_")!=caller["name"]:
                raise ValueError("API MMIO callee/caller lacks exact owner proof")
            counts[op["offset"],op["size"],op["direction"]]+=op["count"]
            row=next((r for r in contracts["mmio"]["task13-api"] if (r["offset"],r["size"])==(op["offset"],op["size"]) and op["direction"] in r["access"]),None)
            if row is None:raise ValueError("API observed register lacks exact frozen permission")
            key=str(row["offset"])+":"+str(row["size"])+":"+"+".join(sorted(row["access"]))
            record={k:v for k,v in op.items() if k!="count"};record["accepted_owner_proof"]=proof
            signature=json.dumps(record,sort_keys=True)
            if signature not in records[key]:records[key][signature]={**record,"case_ids":[]}
            if case_id not in records[key][signature]["case_ids"]:records[key][signature]["case_ids"].append(case_id)
        trace=collections.Counter((int(e["target"].split("+")[1]),e["size"],e["access"]) for e in result["observations"]["trace"] if e.get("target","").startswith("registers+"))
        if counts!=trace:raise ValueError("API exact MMIO attribution misses actual observations")
    return {key:sorted(rows.values(),key=lambda r:json.dumps(r,sort_keys=True)) for key,rows in sorted(records.items())}


def publication_checks(cases,results,manifest,bodies):
    accesses=module("task13_graph").memory_accesses
    by_name={b["name"].removeprefix("_"):b for b in bodies.values()}
    widths={"SCSICreateAdapterTSCB":{31:1,42:1,43:1,0:4,4:4,8:4,12:4,16:4,20:4},
            "SCSISetMemoryPointer":{1492:2,1496:4}}
    for c,r in zip(cases,results):
        regions={m["name"]:m["size"] for m in c["memory"]}
        for p in r["publications"]:
            b=by_name.get(p["owner"])
            if b is None:raise ValueError("API publication owner differs")
            native=manifest["definitions"]["_"+p["owner"]]
            address=p["instruction"]
            if native["arena_address"]<=address<native["arena_address"]+native["size"]:
                start=native["arena_address"];offset=b["native_address"]-start;records=b["native_memory_instructions"]
            else:
                start=b["address"];offset=0;records=b["reference_memory_instructions"]
                if not start<=address<start+b["reference_size"]:raise ValueError("API publication exceeds actual owner")
            record=next((a for a in records if a["address"]==address+offset),None)
            decoded=accesses(address,bytes.fromhex(p["bytes"]))
            if (record is None or record["bytes"]!=p["bytes"] or len(decoded)!=1 or decoded[0]["direction"]!="write" or
                    p["size"]!=decoded[0]["width"] or p["region"] not in regions or
                    not 0<=p["offset"]<=regions[p["region"]]-p["size"]):
                raise ValueError("API actual publication instruction/width/extent differs")
            if p["region"]=="adapter" and p["offset"] in widths.get(p["owner"],{}) and p["size"]!=widths[p["owner"]][p["offset"]]:
                raise ValueError("API adapter byte/halfword/word publication differs")


def audit(evidence,repo,objects):
    if objects is None:raise ValueError("missing API native products")
    driver=repo/DRIVER;proof=load(driver/"reconstruction/task13.json");runner=module("ppc_cases");native=module("task13_native")
    cases=load(driver/"tests/task13-cases.json");contexts=load(driver/"tests/task13-context-cases.json");contracts=load(driver/"tests/task13-contracts.json")
    private_cases=load(driver/"tests/task13-stack-cases.json");private_mapping=load(driver/"tests/task13-stack-mapping.json")
    if proof["reference_sha256"]!=sha(evidence["payload"]) or len(cases["cases"])!=787 or len({c["id"] for c in cases["cases"]})!=787:
        raise ValueError("API pinned reference/787 case closure differs")
    binaries=native_inputs(repo,objects,proof);bodies=scopes(evidence,repo,objects,proof,binaries);snapshot(repo,proof)
    if set(proof["accepted_owner_proofs"])!={"task"+str(i)+".json" for i in range(5,13)}:raise ValueError("API accepted proof closure incomplete")
    for name,digest in proof["accepted_owner_proofs"].items():
        if sha(identity.canonical((driver/"reconstruction"/name).read_bytes(),Path(name)))!=digest:raise ValueError("API accepted owner proof changed")
    for path,record in proof["dependencies"].items():
        raw=(repo/path).read_bytes()
        if sha(identity.canonical(raw,Path(path)) if record["canonical"] else raw)!=record["sha256"]:raise ValueError("API dependency source/native changed: "+path)
    used={x["entry"] for doc in (cases,contexts,private_cases) for c in doc["cases"] for x in c["internal"]}
    frozen={f["names"][0].removeprefix("_"):f for f in evidence["frozen"].values()}
    if set(proof["reference_callees"])!=used:raise ValueError("API real reference callee scope differs")
    for name,r in proof["reference_callees"].items():
        f=frozen[name];s=next(s for s in evidence["macho"]["sections"] if s["address"]<=f["address"]<s["address"]+s["size"]);offset=s["offset"]+f["address"]-s["address"]
        if r!={"address":f["address"],"size":f["size"],"sha256":sha(evidence["payload"][offset:offset+f["size"]])}:raise ValueError("API pinned real callee bytes differ")
    public=load(objects/"reference-results.json");supplement=load(objects/"native-results.json");manifest=load(objects/"arena.json")
    if set(public)!={"reference"}:raise ValueError("API public result wrapper differs")
    public=public["reference"]
    if (public["binary_sha256"]!=proof["reference_sha256"] or public["source_revision"]!=proof["execution_revision"] or
            public["runner_version"]!=runner.RUNNER_VERSION or public["cases_sha256"]!=runner.digest(cases) or public["contracts_sha256"]!=runner.digest(contracts) or
            public["selected_case_ids"]!=[c["id"] for c in cases["cases"]] or len(public["results"])!=787 or
            supplement["preflight"] or supplement["execution_revision"]!=proof["execution_revision"] or supplement["reference_sha256"]!=proof["reference_sha256"] or
            supplement["cases_sha256"]!=runner.digest(cases) or supplement["contexts_sha256"]!=runner.digest(contexts) or supplement["contracts_sha256"]!=runner.digest(contracts) or
            supplement["selected_case_ids"]!=public["selected_case_ids"] or len(supplement["results"])!=787 or supplement["private_stack_cases_sha256"]!=runner.digest(private_cases) or
            sha((objects/"reference-results.json").read_bytes())!=proof["public_results_sha256"] or sha((objects/"native-results.json").read_bytes())!=proof["native_results_sha256"]):
        raise ValueError("API actual raw public/native execution identity/scope differs")
    current=identity.closure(repo,proof["execution_revision"])
    if set(supplement["execution_inputs"])!={p.as_posix() for p in identity.EXECUTION_INPUTS} or supplement["execution_inputs"]!=proof["execution_inputs"]:
        raise ValueError("API committed raw runtime/import closure differs")
    if any(current[p]["git_blob_sha256"]!=r["git_blob_sha256"] for p,r in supplement["execution_inputs"].items()):raise ValueError("API current canonical runtime differs from actual execution")
    for path,digest in proof["execution_artifacts"].items():
        if sha((repo/path).read_bytes())!=digest:raise ValueError("API external reference metadata input changed")
    with tempfile.TemporaryDirectory() as temporary:
        actual=module("task13_link").link(objects.parent.parent/"reference/image.bin",[Path(p) for p in manifest["objects"]],Path(temporary)/"arena.macho")
    if actual!=manifest or supplement["arena_sha256"]!=manifest["sha256"] or sha((objects/"native-arena.macho").read_bytes())!=manifest["sha256"] or supplement["arena_manifest_sha256"]!=sha((objects/"arena.json").read_bytes()):
        raise ValueError("API genuine arena relocation/input binding differs")
    graphs=[g for source,path in binaries.items() for g in module("task13_graph").graph(path,source)]
    if graphs!=proof["native_switches"]:raise ValueError("API eleven assigned native switch graphs differ")
    data=load(driver/"reconstruction/data.json")["objects"]
    switches=[r for r in data if r.get("required_task")==13]
    if len(switches)!=11 or {r["name"] for r in switches}!={g["reference_table"] for g in graphs} or any(r["status"]!="recovered" or r.get("owner_evidence")!="reconstruction/task13.json" for r in switches):
        raise ValueError("API eleven reference switches pending/missing/extra")
    getter=load(driver/"tests/task13-getter.json");record=next(r for r in data if r["name"]=="SCSIFuncPtrs")
    if getter!={k:record[k] for k in getter}:raise ValueError("API dispatch reference identities/version/table bounds differ")
    module("verify")._audit_dispatch_headers(driver,evidence)
    results=[];coverage=collections.defaultdict(set);reference_owned=collections.defaultdict(set)
    for c,p,n in zip(cases["cases"],public["results"],supplement["results"]):
        adapted=native.getter_copy(native.adapt(c,manifest),objects/"native-arena.macho",manifest)
        if (p["executed_case_id"]!=c["id"] or p["observations"]!=c["expected"] or p["unknown_calls"] or not p["returned_to_sentinel"] or
                n["executed_case_id"]!=c["id"] or n["observations"]!=adapted["expected"] or n["unknown_calls"] or not n["returned_to_sentinel"] or
                n["canonical_case_sha256"]!=runner.digest(c) or n["adapted_case_sha256"]!=runner.digest(adapted) or
                not 0<p["instructions"]<=c["instruction_limit"]<=4000000 or not 0<n["instructions"]<=c["instruction_limit"] or
                n["stack_pointer"]!=runner.STACK+runner.STACK_SIZE-4096 or n["nonvolatile_preserved"]!={str(r):0xa5000000+r for r in range(14,32)} or
                not any(e["entry"]==c["entry"] and e["address"]==manifest["definitions"]["_"+c["entry"]]["arena_address"] for e in n["entries"])):
            raise ValueError("API actual paired observation/ABI differs: "+c["id"])
        for name,addresses in n["owned_instructions"].items():
            d=manifest["definitions"]["_"+name];f=frozen[name]
            if not addresses:raise ValueError("API actual coverage is empty")
            for address in addresses:
                if address%4:raise ValueError("API actual instruction coverage is unaligned")
                if d["arena_address"]<=address<d["arena_address"]+d["size"]:coverage[name].add(address)
                elif f["address"]<=address<f["address"]+f["size"]:reference_owned[name].add(address)
                else:raise ValueError("API actual coverage exceeds genuine native/reference owner")
        results.append((c["id"],n))
    if set(coverage)!=set(native.OWNED):raise ValueError("API actual native coverage omits owned bodies")
    publication_checks(cases["cases"],supplement["results"],manifest,bodies)
    if {name:sorted(points) for name,points in sorted(reference_owned.items())}!=proof["mixed_owned_reference_coverage"]:
        raise ValueError("API mixed reference callee limitation differs from actual execution")
    by_id={r["executed_case_id"]:r for r in supplement["results"]}
    for selector in range(2,14):
        result=by_id["task13-SCSIGetNVOSMSegment-2-"+str(selector)+"-0"]
        calls=[c for c in result["api_calls"] if c["owner"]=="SCSIGetNVOSMSegment" and c["callee"]=="SCSIHReadSEEPROM"]
        expected_offset=32 if selector in (2,8) else 64 if selector in (3,12) else 0
        if len(calls)!=1 or calls[0]["arguments"][2:4]!=[expected_offset,32]:
            raise ValueError("API actual twelve NV conditional selectors differ")
    for g in graphs:
        if "targets" in g:
            source=next(b["source"] for b in bodies.values() if b["name"]=="_"+g["owner"]);delta=manifest["definitions"]["_"+g["owner"]]["arena_address"]-next(b["native_address"] for b in bodies.values() if b["name"]=="_"+g["owner"])
            if any(t+delta not in coverage[g["owner"]] for t in g["targets"]):raise ValueError("API assigned native switch target lacks actual execution")
    if len(supplement["contexts"])!=2 or [c["initial_r28"] for c in contexts["cases"]]!=[0x12345635,0x89abcda6]:raise ValueError("API caller context seed scope differs")
    for c,pair in zip(contexts["cases"],supplement["contexts"]):
        if pair["id"]!=c["id"] or pair["initial_r28"]!=c["initial_r28"]:raise ValueError("API caller context identity differs")
        for label in ("reference","native"):
            r=pair[label];adapted=c if label=="reference" else native.adapt(c,manifest)
            wanted=["SCSIInitialize","SCSIRInitialize","SCSIHInitialize","SCSIhInitializeHardware"]
            entries=[e for e in r["entries"] if e["entry"] in wanted]
            if (r["observations"]!=adapted["expected"] or not r["returned_to_sentinel"] or r["unknown_calls"] or
                    [e["entry"] for e in entries]!=wanted or any(e["r28"]!=c["initial_r28"] for e in entries) or
                    r["stack_pointer"]!=runner.STACK+runner.STACK_SIZE-4096 or
                    r["nonvolatile_preserved"]!={str(i):(c["initial_r28"] if i==28 else 0xa5000000+i) for i in range(14,32)} or
                    not any(e.get("target")=="registers+255" and e.get("access")=="write" and e.get("value")==c["initial_r28"]&255 for e in r["observations"]["trace"])):
                raise ValueError("API authentic real caller r28/SP/nonvolatile witness differs")
            for e,name in zip(entries,wanted):
                address=frozen[name]["address"] if label=="reference" else manifest["definitions"]["_"+name]["arena_address"]
                if e["address"]!=address:raise ValueError("API caller witness entry is not genuine source/native")
            calls=[x for x in r["api_calls"] if x["owner"]=="SCSIInitialize" and x["callee"]=="SCSIRInitialize"]
            if len(calls)!=1:raise ValueError("API genuine Resource caller identity/count differs")
            call=calls[0];payload,image=(evidence["payload"],evidence["macho"]) if label=="reference" else load_image(objects/"native-arena.macho")
            body=frozen["SCSIInitialize"] if label=="reference" else manifest["definitions"]["_SCSIInitialize"]
            body_address=body["address"] if label=="reference" else body["arena_address"]
            pc=call["callsite"];section=next(s for s in image["sections"] if s["address"]<=pc and pc+4<=s["address"]+s["size"])
            offset=section["offset"]+pc-section["address"];code=payload[offset:offset+4];word=int.from_bytes(code,"big");displacement=word&0x3fffffc
            target=pc+displacement-(0x4000000 if displacement&0x2000000 else 0)
            expected_target=frozen["SCSIRInitialize"]["address"] if label=="reference" else manifest["definitions"]["_SCSIRInitialize"]["arena_address"]
            address=runner.REGION_BASE
            for region in c["memory"]:
                if region["name"]=="adapter":break
                address+=(region["size"]+4095)&~4095
            if (not body_address<=pc<body_address+body["size"] or code.hex()!=call["bytes"] or word>>26!=18 or word&3!=1 or target!=expected_target or
                    call["owner_address"]!=0x1a4644 or call["callee_address"]!=0x1a2558 or call["arguments"][0]!=address+24):
                raise ValueError("API actual Resource linking callsite/argument differs")
            if label=="native":
                api=next(b for b in bodies.values() if b["name"]=="_SCSIInitialize")
                location=pc-body_address+body["source_address"]
                relocations=[x for x in api["native_relocations"] if x["address"]==location and x["kind"]=="ppc-br24-24-pc-relative"]
                if len(relocations)!=1 or relocations[0]["target"]!="_SCSIRInitialize" or not relocations[0]["external"]:
                    raise ValueError("API genuine native Resource relocation differs")
            results.append((label+"/"+c["id"],r))
    if len(supplement["private_stack_contexts"])!=2 or [c["initial_private_byte"] for c in private_cases["cases"]]!=[127,53]:
        raise ValueError("API PostBusScan private-byte seed scope differs")
    for c,pair in zip(private_cases["cases"],supplement["private_stack_contexts"]):
        if pair["id"]!=c["id"] or pair["initial_private_byte"]!=c["initial_private_byte"]:raise ValueError("API private-byte context identity differs")
        for label in ("reference","native"):
            result=pair[label];state=result["private_byte_context"];seed=c["initial_private_byte"];mapping=private_mapping[label]
            adapted=c if label=="reference" else native.adapt(c,manifest)
            entry=mapping["entry_address"] if label=="reference" else manifest["definitions"]["_SCSIxPostBusScan"]["arena_address"]
            expected_address=runner.STACK+runner.STACK_SIZE-4096-mapping["frame_size"]+mapping["byte_offset"]
            if (result["observations"]!=adapted["expected"] or result["unknown_calls"] or not result["returned_to_sentinel"] or
                    result["nonvolatile_preserved"]!={str(i):0xa5000000+i for i in range(14,32)} or result["stack_pointer"]!=runner.STACK+runner.STACK_SIZE-4096 or
                    state["initial_private_byte"]!=seed or state["address"]!=expected_address or state["seeded_before_entry"] is not True or
                    len(state["loads"])!=1 or state["stores"] or state["callback_entries"]!=1 or
                    state["loads"][0]!={"instruction":entry+mapping["late_load_offset"],"bytes":"88010038","sp":state["initial_sp"]-mapping["frame_size"],"address":expected_address,"value":seed,"iob_status":1} or
                    not state["uses"] or state["uses"][0]["r0"]!=seed or state["uses"][0]["instruction"]!=entry+mapping["use_instructions"][0]["offset"] or
                    state["final_iob_status"]!=1 or state["final_origin_status"]!=(37 if seed==127 else 32) or
                    len([e for e in result["entries"] if e["entry"]=="SCSIxQueueSpecialIOB"])!=1):
                raise ValueError("API genuine private-byte storage/load/callback/downstream witness differs")
            results.append((label+"/"+c["id"],result))
    accepted={int(a):p for a,p in proof["operation_owner_proofs"].items()}
    if accepted!={a:OWNER_PROOFS[f["owner"]] for a,f in evidence["frozen"].items() if f["owner"] in OWNER_PROOFS}:
        raise ValueError("API operation owner proof attribution is not the exact accepted partition")
    if mmio_index(results,contracts,evidence["frozen"],accepted)!=proof["mmio_operations"]:raise ValueError("API exact owner/callee/callsite MMIO attribution differs")
    module("task12_audit").validate_operations(objects,manifest,results,evidence["frozen"])
    module("task13_fix1_audit").audit(evidence,repo)
    return proof,public,supplement
