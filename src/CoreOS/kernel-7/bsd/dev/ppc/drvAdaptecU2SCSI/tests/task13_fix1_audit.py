"""Authenticate the independent review corpus without relabeling legacy runs."""

import collections
from pathlib import Path
import task13_fix1_identity as identity
import task13_fix1_checks as checks
import task13_fix1_runtime as runtime
import task13_native as native
import task13_audit as api
from binrecon.macho import load_image


def snapshot(cases,current,baseline):
    isolated=current.copy();isolated["mmio"]=current["mmio"].copy()
    rows=isolated["mmio"].pop("task13-fix1",None)
    if isolated!=baseline or rows is None:raise ValueError("fix1 immutable snapshot baseline differs")
    wanted=collections.defaultdict(set);allowed=collections.defaultdict(set)
    for group in baseline["mmio"].values():
        for row in group:allowed[row["offset"],row["size"]].update(row["access"])
    for case in cases:
        if any(m["mmio"]!="task13-fix1" for m in case["memory"] if "mmio" in m):raise ValueError("fix1 case snapshot differs")
        for outcome in case["external_outcomes"]:
            if "register" in outcome:wanted[outcome["offset"],outcome["size"]].add(outcome["access"])
    actual={(r["offset"],r["size"]):set(r["access"]) for r in rows}
    if len(actual)!=len(rows) or actual!=wanted or any(v-allowed[k] for k,v in actual.items()):
        raise ValueError("fix1 speculative/duplicate/missing/new permission")
    for row in rows:
        key=str(row["offset"])+":"+str(row["size"])+":"+"+".join(sorted(row["access"]))
        if row["evidence"]!="reconstruction/task13-fix1.json#/mmio_operations/"+key:raise ValueError("fix1 MMIO evidence key differs")
    return rows


def producer(record,cases,inputs,legacy,revision,binary_sha,case_sha,contract_sha):
    checks.complete_cases(cases,record["results"])
    if (record["preflight"] or record["execution_revision"]!=revision or record["execution_inputs"]!=inputs or
            record["legacy"]!=legacy or record["binary_sha256"]!=binary_sha or record["cases_sha256"]!=case_sha or
            record["contracts_sha256"]!=contract_sha or record["selected_case_ids"]!=[c["id"] for c in cases]):
        raise ValueError("fix1 actual independent producer/input/corpus identity differs")


def calls(case,result,raw,image,frozen,manifest):
    def code(pc):
        sections=[s for s in image["sections"] if s["address"]<=pc and pc+4<=s["address"]+s["size"]]
        if len(sections)!=1:raise ValueError("fix1 actual call instruction outside image")
        section=sections[0];offset=section["offset"]+pc-section["address"]
        return raw[offset:offset+4]
    by_name={f["names"][0].removeprefix("_"):f for f in frozen.values()}
    for call in result["api_calls"]:
        owner=by_name.get(call["owner"]);callee=by_name.get(call["callee"])
        if owner is None or callee is None or owner["address"]!=call["owner_address"] or callee["address"]!=call["callee_address"]:
            raise ValueError("fix1 caller/callee actual owner differs")
        bounds=[(owner["address"],owner["size"])];targets={callee["address"]}
        definition=manifest["definitions"].get("_"+call["owner"])
        if definition:bounds.append((definition["arena_address"],definition["size"]))
        definition=manifest["definitions"].get("_"+call["callee"])
        if definition:targets.add(definition["arena_address"])
        pc=call["callsite"];actual=code(pc);word=int.from_bytes(actual,"big")
        if (actual.hex()!=call["bytes"] or not any(start<=pc<start+size for start,size in bounds) or
                not word&1 or len(call["arguments"])!=8):raise ValueError("fix1 genuine public linking callsite differs")
        if word>>26==18 and not word&2:
            displacement=word&0x3fffffc;target=pc+displacement-(0x4000000 if displacement&0x2000000 else 0)
            if target not in targets:raise ValueError("fix1 actual direct callee target differs")
        elif word not in (0x4e800021,0x4e800421):raise ValueError("fix1 unapproved public link form")
    handler=checks.HANDLERS.get(case["id"].removeprefix("task13-fix1-"))
    if handler:
        expected=manifest["definitions"].get("_"+handler,{}).get("arena_address",by_name[handler]["address"])
        found=[e for e in result["entries"] if e["entry"]==handler]
        if len(found)!=1 or found[0]["address"]!=expected:raise ValueError("fix1 genuine handler entry differs")


def measure(evidence,repo):
    tests=repo/identity.old.DRIVER/"tests";out=repo/"tools/binrecon/out/adaptecu2scsi-ppc";objects=out/"objects/task13"
    target=out/"objects/task13-fix1";load,sha=identity.old.load,identity.old.sha
    legacy=identity.legacy(repo);original=load(repo/identity.old.DRIVER/"reconstruction/task13.json")
    reference=load(target/"reference-results.json");supplement=load(target/"native-results.json")
    revision=reference["execution_revision"];inputs=identity.closure(repo,revision)
    cases=load(tests/"task13-fix1-cases.json");contracts=load(tests/"task13-fix1-contracts.json")
    baseline=load(tests/"task13-contracts.json");manifest=load(objects/"arena.json");runner=native.module("ppc_cases")
    delta=snapshot(cases["cases"],contracts,baseline)
    for record,digest in ((reference,original["reference_sha256"]),(supplement,manifest["sha256"])):
        producer(record,cases["cases"],inputs,legacy,revision,digest,runner.digest(cases),runner.digest(contracts))
    bodies={b["address"]:b for b in original["bodies"]};all_results=[]
    payload,image=load_image(objects/"native-arena.macho")
    frozen=evidence["frozen"];by_name={f["names"][0].removeprefix("_"):f for f in frozen.values()}
    callees={};accepted={int(a):p for a,p in original["operation_owner_proofs"].items()}
    for case in cases["cases"]:
        internal={b["entry"]:b["size"] for b in case["internal"]}
        if len(internal)!=len(case["internal"]):raise ValueError("fix1 duplicate internal body")
        for name,size in {case["entry"]:case["size"],**internal}.items():
            f=by_name[name]
            if size!=f["size"] or f["address"] not in accepted:raise ValueError("fix1 unaccepted real internal body")
            section=next(s for s in evidence["macho"]["sections"] if s["address"]<=f["address"] and f["address"]+size<=s["address"]+s["size"])
            offset=section["offset"]+f["address"]-section["address"]
            callees[name]={"address":f["address"],"size":size,"sha256":sha(evidence["payload"][offset:offset+size]),"owner_proof":accepted[f["address"]]}
        if {o.get("service","").removeprefix("_") for o in case["external_outcomes"]}&set(by_name):
            raise ValueError("fix1 external script substitutes real internal body")
    alias=load(tests/"task13-fix1-alias.json")
    for label,record in (("reference",reference),("native",supplement)):
        records=record["results"]
        for case,result in zip(cases["cases"],records):
            adapted=case if label=="reference" else native.adapt(case,manifest)
            if (result["observations"]!=adapted["expected"] or result["unknown_calls"] or not result["returned_to_sentinel"] or
                    result["canonical_case_sha256"]!=runner.digest(case) or result["adapted_case_sha256"]!=runner.digest(adapted) or
                    not 0<result["instructions"]<=case["instruction_limit"]<=4000000 or
                    result["stack_pointer"]!=runner.STACK+runner.STACK_SIZE-4096 or
                    result["nonvolatile_preserved"]!={str(r):0xa5000000+r for r in range(14,32)}):
                raise ValueError("fix1 paired actual observations/SP/nonvolatile/sentinel differ: "+case["id"])
            wanted=[alias] if label=="native" and case["id"]==alias["case"] else []
            if result["metadata_aliases"]!=wanted:raise ValueError("fix1 metadata alias escaped exact case/image")
            root=manifest["definitions"]["_"+case["entry"]]["arena_address"] if label=="native" else by_name[case["entry"]]["address"]
            if not any(e["entry"]==case["entry"] and e["address"]==root for e in result["entries"]):raise ValueError("fix1 genuine public root missing")
            checks.effects(case,result)
            calls(case,result,payload if label=="native" else evidence["payload"],image if label=="native" else evidence["macho"],frozen,manifest if label=="native" else {"definitions":{}})
            all_results.append((label+"/"+case["id"],result))
        for finding in ("I1","I2","I3"):checks.require_paths(finding,cases["cases"],records)
        api.publication_checks(cases["cases"],records,manifest,bodies)
    runtime.event_alias(payload,image,next(c for c in cases["cases"] if c["id"]==alias["case"]),evidence["payload"],evidence["macho"],alias)
    operations=api.mmio_index(all_results,{"mmio":{"task13-api":delta}},frozen,accepted)
    if set(operations)!={r["evidence"].rsplit("/",1)[1] for r in delta}:raise ValueError("fix1 delta has no actual attribution")
    api.module("task12_audit").validate_operations(objects,manifest,all_results,frozen)
    proofs={p:sha(identity.old.canonical((repo/identity.old.DRIVER/"reconstruction"/p).read_bytes(),Path(p))) for p in set(accepted.values())}
    return {"kind":"separate actual Task13 review corpus; legacy producer unchanged","execution_revision":revision,
            "execution_inputs":inputs,"legacy":legacy,"reference_results_sha256":sha((target/"reference-results.json").read_bytes()),
            "native_results_sha256":sha((target/"native-results.json").read_bytes()),"cases_sha256":runner.digest(cases),
            "contracts_sha256":runner.digest(contracts),"required_case_ids":list(checks.REQUIRED),"contract_delta":delta,
            "mmio_operations":operations,"real_callees":callees,"accepted_owner_proofs":proofs,"metadata_alias":alias,
            "findings":{"I1":list(checks.VERIFY),"I2":list(checks.SUBMIT+checks.COMPLETE),"I3":list(checks.HANDLERS)}}


def audit(evidence,repo):
    actual=measure(evidence,repo)
    if actual!=identity.old.load(repo/identity.old.DRIVER/"reconstruction/task13-fix1.json"):
        raise ValueError("fix1 actual evidence differs from canonical proof")
    return actual
