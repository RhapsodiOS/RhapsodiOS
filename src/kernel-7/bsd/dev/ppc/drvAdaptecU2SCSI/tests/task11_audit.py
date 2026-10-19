"""Resource owner evidence, with separate actual and canonical producers."""

import hashlib
import importlib.util
import json
import re
import subprocess
import tarfile
from pathlib import Path

from binrecon.macho import load_image
from binrecon.source_map import source_sites


DRIVER=Path("src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI")
NATIVE_INPUTS=("AdaptecU2CHIMResource.c","AdaptecU2CHIMTypes.h","AdaptecU2CHIM.h",
               "AdaptecU2CHIMPrivate.h","OSMFunctions.h","AdaptecU2SCSI.h","AdaptecU2SCSIPrivate.h")
EXECUTION_INPUTS=[DRIVER/name for name in ("tests/task11-cases.json","tests/task11-contracts.json",
                  "tests/ppc_cases.py","tests/reference.py","reconstruction/inventory.md")]
EXECUTION_INPUTS += [Path("tools/binrecon/binrecon")/(name+".py") for name in
                    ("__init__","identity","macho","objc_abi","source_map","schema","arch")]
EXECUTION_INPUTS += [Path("tools/binrecon/source_paths.py")]


def sha(raw):return hashlib.sha256(raw).hexdigest().upper()
def canonical(path):return path.read_bytes().replace(b"\r\n",b"\n")
def load(path):return json.loads(path.read_text())


def git(repo,revision,path):
    try:return subprocess.check_output(["git","show",revision+":"+path.as_posix()],cwd=repo,stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as error:raise ValueError("resource canonical input revision differs") from error


def module(driver,name):
    spec=importlib.util.spec_from_file_location("au2_resource_"+name,driver/"tests"/(name+".py"))
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value


def audit_native_inputs(repo,objects,proof):
    manifest=load(objects/"objects.json");inputs=load(objects/"native-inputs.json")
    if (sha((objects/"objects.json").read_bytes())!=proof["native_manifest_sha256"] or
            sha((objects/"native-inputs.json").read_bytes())!=proof["native_inputs_sha256"] or
            inputs.get("work_in_progress") is not True or set(inputs["inputs"])!=set(NATIVE_INPUTS) or
            manifest["source_revision"]!=proof["native_actual_base_revision"] or
            inputs["source_revision"]!=manifest["source_revision"] or
            manifest["configuration"]!="RELEASE_PPC" or len(manifest["objects"])!=1):
        raise ValueError("resource actual native producer differs")
    if set(proof["canonical_inputs"])!=set(NATIVE_INPUTS):raise ValueError("resource compiled input closure incomplete")
    for name in NATIVE_INPUTS:
        blob=git(repo,proof["canonical_input_revision"],DRIVER/name)
        expected=proof["canonical_inputs"][name]
        if (sha(blob)!=expected or sha(canonical(repo/DRIVER/name))!=expected or
                inputs["inputs"][name]["staged_sha256"]!=expected):
            raise ValueError("resource compiled/canonical input differs: "+name)
    expected={n:inputs["inputs"][n]["staged_sha256"] for n in NATIVE_INPUTS}
    for filename,names in (("source-inputs.sha256",NATIVE_INPUTS),("header-inputs.sha256",NATIVE_INPUTS[1:])):
        actual={}
        for line in (objects/filename).read_text().splitlines():
            digest,path=line.split(maxsplit=1);name=Path(path).name
            if name in actual or path!="bsd/dev/ppc/drvAdaptecU2SCSI/"+name:
                raise ValueError("resource compiled input manifest differs")
            actual[name]=digest.upper()
        if actual!={n:expected[n] for n in names}:raise ValueError("resource compiled input manifest differs")
    item=manifest["objects"][0]
    if (item["source"]!="bsd/dev/ppc/drvAdaptecU2SCSI/AdaptecU2CHIMResource.c" or
            item["path"]!="1-AdaptecU2CHIMResource.c.o" or item["cpu_type"]!=18 or
            item["source_sha256"]!=expected[NATIVE_INPUTS[0]] or
            sha((objects/item["path"]).read_bytes())!=item["sha256"]):
        raise ValueError("resource native source/object differs")
    if sha((objects/item["log"]).read_bytes())!=proof["native_diagnostics_sha256"]:
        raise ValueError("resource native diagnostics changed")
    if (objects/"1.command").read_text().strip()!=item["command"]:
        raise ValueError("resource native compiler command differs")
    for relative,digest in proof["native_artifacts"].items():
        if sha((repo/relative).read_bytes())!=digest:raise ValueError("resource raw native artifact changed")
    archive=repo/proof["native_input_archive"]
    with tarfile.open(archive) as stream:
        members={member.name:member for member in stream.getmembers() if member.isfile()}
        if set(members)!=set(NATIVE_INPUTS):raise ValueError("resource archived input closure incomplete")
        for name,member in members.items():
            if sha(stream.extractfile(member).read())!=expected[name]:raise ValueError("resource archived input differs")
    with tarfile.open(repo/proof["native_product_archive"]) as stream:
        for member in stream.getmembers():
            if member.isfile() and stream.extractfile(member).read()!=(objects/Path(member.name).name).read_bytes():
                raise ValueError("resource archived native product differs")
    return manifest,item


def audit_snapshot(driver,proof):
    baseline=load(driver/"tests/contracts.json");snapshot=load(driver/"tests/task11-contracts.json")
    if sha(canonical(driver/"tests/contracts.json"))!=proof["accepted_contracts_sha256"]:
        raise ValueError("resource accepted contract baseline changed")
    expected=json.loads(json.dumps(snapshot));rows=expected["mmio"].pop("task11-hardware",None)
    if expected!=baseline or rows!=proof["contract_delta"] or not rows:
        raise ValueError("resource contract snapshot delta differs")


def audit(evidence,repo,objects):
    driver=repo/DRIVER;path=driver/"reconstruction/task11.json"
    if not path.is_file():raise ValueError("missing resource owner source/native proof")
    proof=load(path);addresses=set(evidence["document"]["owners"]["AdaptecU2CHIMResource.c"])
    bodies={b["address"]:b for b in proof["bodies"]}
    if (len(proof["bodies"])!=47 or set(bodies)!=addresses or
            proof["reference_sha256"]!=sha(evidence["payload"])):raise ValueError("resource proof must cover exactly47 bodies")
    if objects is None:raise ValueError("resource owner requires actual native objects")
    manifest,item=audit_native_inputs(repo,objects,proof)
    raw,image=load_image(objects/item["path"])
    if ((image["input"]["architecture"],image["input"]["endianness"])!=("ppc","big") or
            image["extensions"]["macho"]["header"]["file_type"]!=1):
        raise ValueError("resource native image requires PPC big-endian object")
    symbols=sorted((s for s in image["symbols"] if s["binding"]=="external" and s["section"]=="__TEXT,__text"),key=lambda s:s["address"])
    if {s["name"] for s in symbols}!={b["name"] for b in bodies.values()}:raise ValueError("resource native47 symbol closure differs")
    text=next(s for s in image["sections"] if s["name"]=="__TEXT,__text")
    sites=source_sites(repo,driver);ledger=load(driver/"reconstruction/ledger.json");entries={e["address"]:e for e in ledger["entries"]}
    for index,symbol in enumerate(symbols):
        body=next(b for b in bodies.values() if b["name"]==symbol["name"])
        end=symbols[index+1]["address"] if index+1<len(symbols) else text["address"]+text["size"]
        offset=text["offset"]+symbol["address"]-text["address"];code=raw[offset:offset+end-symbol["address"]]
        location=(DRIVER.as_posix()+"/AdaptecU2CHIMResource.c",body["source_line"])
        entry=entries[body["address"]];rel=[r for r in image["extensions"]["macho"]["relocations"]
                                         if r["section"]=="__TEXT,__text" and symbol["address"]<=r["address"]<end]
        if (body["reference_size"]!=evidence["frozen"][body["address"]]["size"] or
                body["native_sha256"]!=sha(code) or body["native_address"]!=symbol["address"] or
                body["native_size"]!=len(code) or body["native_relocations"]!=rel or
                len(body["control_flow"])<30 or sites.get(symbol["name"])!=[location] or
                (entry["source_path"],entry["source_line"])!=location or entry["status"]!="control-flow-confirmed" or
                not any(a["path"]==path.relative_to(repo).as_posix() and a["sha256"]==sha(canonical(path)) for a in entry["artifacts"])):
            raise ValueError("resource source/native/control-flow binding differs: "+symbol["name"])
    cases=load(driver/"tests/task11-cases.json");contracts=load(driver/"tests/task11-contracts.json")
    audit_snapshot(driver,proof);runner=module(driver,"ppc_cases")
    envelope=load(objects/"reference-results.json")
    if set(envelope)!={"reference"} or sha((objects/"reference-results.json").read_bytes())!=proof["reference_results_sha256"]:
        raise ValueError("resource actual public result archive differs")
    result=envelope["reference"]
    audit_public(cases,contracts,result,proof,runner)
    if set(proof["execution_inputs"])!={p.as_posix() for p in EXECUTION_INPUTS}:raise ValueError("resource execution input closure incomplete")
    for relative in EXECUTION_INPUTS:
        blob=git(repo,result["source_revision"],relative);current=canonical(repo/relative)
        if relative.name=="inventory.md":
            blob,current=[v.split(b"<!-- functions:start -->")[1].split(b"<!-- functions:end -->")[0] for v in (blob,current)]
        if blob!=current or sha(blob)!=proof["execution_inputs"][relative.as_posix()]["git_blob_sha256"]:
            raise ValueError("resource executed input changed: "+relative.as_posix())
    if result["runner_version"]!="1/unicorn-2.1.4/"+proof["execution_inputs"][(DRIVER/"tests/ppc_cases.py").as_posix()]["working_sha256"].lower():
        raise ValueError("resource actual runner bytes differ")
    by_id={c["id"]:c for c in cases["cases"]}
    for body in bodies.values():
        if body["name"]=="_SCSIRFreeUnitHandle":
            if body["cases"]!=["task11-native-freeunit-unit","task11-native-freeunit-hhcb"]:raise ValueError("resource alias native scope differs")
        elif not body["cases"] or any(by_id[c]["entry"]!=body["name"].removeprefix("_") for c in body["cases"]):
            raise ValueError("resource body actual entry coverage differs")
    expected_proofs={"task5.json","task6.json","task7.json","task8.json","task9.json","task10.json"}
    if set(proof["accepted_owner_proofs"])!=expected_proofs:raise ValueError("resource dependency proof closure incomplete")
    for name,digest in proof["accepted_owner_proofs"].items():
        if sha(canonical(driver/"reconstruction"/name))!=digest:raise ValueError("resource accepted dependency proof changed")
    expected_dependencies={"AdaptecU2OSMServices.m","AdaptecU2CHIMOSD.c","AdaptecU2CHIMHardware.c",
                           "AdaptecU2CHIMSCB.c","AdaptecU2CHIMConfig.c","AdaptecU2CHIMNegotiation.c",
                           "AdaptecU2CHIMRecovery.c","AdaptecU2CHIMTables.c","AdaptecU2CHIMFirmware.c"}
    if set(proof["accepted_dependencies"])!=expected_dependencies:raise ValueError("resource dependency closure incomplete")
    for name,dep in proof["accepted_dependencies"].items():
        root=objects.parent/dep["group"]
        if (sha(canonical(driver/name))!=dep["git_blob_sha256"] or sha((root/dep["object"]).read_bytes())!=dep["object_sha256"] or
                sha((root/"objects.json").read_bytes())!=dep["manifest_sha256"] or load(root/"objects.json")["source_revision"]!=dep["source_revision"]):
            raise ValueError("resource accepted source/native dependency changed: "+name)
    frozen={n.removeprefix("_"):f for f in evidence["frozen"].values() for n in f["names"]}
    used={d["entry"] for c in cases["cases"] for d in c["internal"]}
    owners={a:o for o,values in evidence["document"]["owners"].items() for a in values}
    files=set(subprocess.check_output(["git","ls-tree","-r","--name-only",proof["canonical_input_revision"],"--",DRIVER.as_posix()],cwd=repo,text=True).splitlines())
    pending={n for n in used if (DRIVER/owners[frozen[n]["address"]]).as_posix() not in files}
    if pending!=set(proof["reference_helpers"]):raise ValueError("resource pinned helper scope differs")
    if set(proof["supplementary_reference_helpers"])!={"SCSIHFreeUnitHandle"}:
        raise ValueError("resource supplementary reference callee scope differs")
    for name,record in (proof["reference_helpers"]|proof["supplementary_reference_helpers"]).items():
        f=frozen[name];section=next(s for s in evidence["macho"]["sections"] if s["address"]<=f["address"]<s["address"]+s["size"])
        offset=section["offset"]+f["address"]-section["address"]
        if (record["address"]!=f["address"] or record["size"]!=f["size"] or
                record["sha256"]!=sha(evidence["payload"][offset:offset+f["size"]]) or not record["contract_review"]):
            raise ValueError("resource pinned helper differs: "+name)
    native=module(driver,"task11_native");native_result=load(objects/"native-results.json")
    if (sha((objects/"native-results.json").read_bytes())!=proof["native_results_sha256"] or
            native_result["native_object_sha256"]!=item["sha256"] or native_result["execution_revision"]!=proof["supplementary_revision"] or
            native_result["cases_sha256"]!=runner.digest(cases) or len(native_result["leaves"])!=29 or
            native.switch_graph(objects/item["path"])!=native_result["switches"] or
            native.publication_widths(objects/item["path"])!={k:[tuple(x) for x in v] for k,v in native_result["publications"].items()}):
        raise ValueError("resource native actual result differs")
    boundary=load(objects/"boundary-results.json");sequence=module(driver,"task11_sequence");document=load(driver/"tests/task11-sequences.json")
    if (sha((objects/"boundary-results.json").read_bytes())!=proof["boundary_results_sha256"] or
            boundary["execution_revision"]!=proof["supplementary_revision"] or boundary["cases_sha256"]!=runner.digest(cases) or
            boundary["contracts_sha256"]!=runner.digest(contracts) or boundary["sequences_sha256"]!=runner.digest(document)):
        raise ValueError("resource actual boundary producer differs")
    audit_supplementary(repo,proof,native_result,boundary)
    sequence.audit(document,cases,boundary["actual"])


def audit_supplementary(repo,proof,native_result,boundary):
    paths=set(EXECUTION_INPUTS)|{DRIVER/"tests"/name for name in
          ("task11_execute.py","task11_native.py","task11_sequence.py","task10_sequence.py","task11-sequences.json")}
    expected={path.as_posix() for path in paths}
    if set(proof["supplementary_inputs"])!=expected:raise ValueError("resource supplementary input closure incomplete")
    for result in (native_result,boundary):
        if (result["execution_inputs"]!=proof["supplementary_inputs"] or
                result["execution_revision"]!=proof["supplementary_revision"] or
                result["reference_sha256"]!=proof["reference_sha256"]):
            raise ValueError("resource supplementary actual input manifest differs")
    for path in paths:
        raw=(repo/path).read_bytes();current=raw.replace(b"\r\n",b"\n")
        blob=git(repo,proof["supplementary_revision"],path)
        if path.name=="inventory.md":
            blob,current=[v.split(b"<!-- functions:start -->")[1].split(b"<!-- functions:end -->")[0] for v in (blob,current)]
        record=proof["supplementary_inputs"][path.as_posix()]
        # Preserve actual raw producing bytes in the result manifest, while
        # checking current checkout identity through canonical Git blobs.
        if current!=blob or sha(blob)!=record["git_blob_sha256"]:
            raise ValueError("resource supplementary execution input changed: "+path.as_posix())
    for result,helper in ((native_result,"task11_native.py"),(boundary,"task11_sequence.py")):
        if (result["producer_sha256"]!=sha((repo/DRIVER/"tests/task11_execute.py").read_bytes()) or
                result["helper_sha256"]!=sha((repo/DRIVER/"tests"/helper).read_bytes())):
            raise ValueError("resource supplementary helper/producer changed")
    if boundary["capture_sha256"]!=sha((repo/DRIVER/"tests/task10_sequence.py").read_bytes()):
        raise ValueError("resource supplementary capture changed")


def audit_public(cases,contracts,result,proof,runner):
    if (result["binary_sha256"]!=proof["reference_sha256"] or result["cases_sha256"]!=runner.digest(cases) or
            result["contracts_sha256"]!=runner.digest(contracts) or result["runner_version"]!=proof["reference_runner_version"] or
            result["source_revision"]!=proof["execution_revision"] or
            result["selected_case_ids"]!=[c["id"] for c in cases["cases"]] or len(result["results"])!=len(cases["cases"])):
        raise ValueError("resource public execution scope/identity differs")
    for case,actual in zip(cases["cases"],result["results"]):
        if (case.get("ack_exhaustion") or case.get("machine_inputs") or
                actual["executed_case_id"]!=case["id"] or actual["unknown_calls"]!=[] or
                actual["returned_to_sentinel"] is not True or actual["observations"]!=case["expected"] or
                not 0<actual["instructions"]<=case["instruction_limit"]<=4000000):
            raise ValueError("invalid actual resource fixture: "+case["id"])
