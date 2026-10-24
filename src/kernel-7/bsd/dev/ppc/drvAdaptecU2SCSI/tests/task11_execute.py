"""Reproduce supplementary resource evidence from committed explicit inputs."""

import argparse
import hashlib
import importlib.util
import json
import subprocess
from pathlib import Path


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ("reference","objects"):
        parser.add_argument("--"+name,type=Path,required=True)
    args=parser.parse_args();tests=Path(__file__).resolve().parent;repo=tests.parents[6]
    def module(name):
        spec=importlib.util.spec_from_file_location("au2_resource_producer_"+name,tests/(name+".py"))
        value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
    def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest().upper()
    revision=subprocess.check_output(["git","rev-parse","HEAD"],cwd=repo,text=True).strip()
    runner=module("ppc_cases");native=module("task11_native");sequence=module("task11_sequence")
    cases=json.loads((tests/"task11-cases.json").read_text())
    contracts=json.loads((tests/"task11-contracts.json").read_text())
    document=json.loads((tests/"task11-sequences.json").read_text())
    binary=args.objects/"1-AdaptecU2CHIMResource.c.o"
    names=[tests/name for name in ("task11_execute.py","task11_native.py","task11_sequence.py",
           "task10_sequence.py","task11-sequences.json","task11-cases.json","task11-contracts.json",
           "ppc_cases.py","reference.py")]
    names += [tests.parent/"reconstruction/inventory.md",repo/"tools/binrecon/source_paths.py"]
    names += [repo/"tools/binrecon/binrecon"/(name+".py") for name in
              ("__init__","identity","macho","objc_abi","source_map","schema","arch")]
    inputs={}
    for path in names:
        relative=path.relative_to(repo).as_posix();raw=path.read_bytes();canonical=raw.replace(b"\r\n",b"\n")
        blob=subprocess.check_output(["git","show",revision+":"+relative],cwd=repo)
        if path.name=="inventory.md":
            canonical,blob=[v.split(b"<!-- functions:start -->")[1].split(b"<!-- functions:end -->")[0] for v in (canonical,blob)]
        if canonical!=blob:raise ValueError("uncommitted resource execution input: "+relative)
        inputs[relative]={"git_blob_sha256":hashlib.sha256(blob).hexdigest().upper(),
                          "working_sha256":hashlib.sha256(raw).hexdigest().upper()}
    if not sha(args.reference/"image.bin")==cases["reference_sha256"]==contracts["reference_sha256"]:
        raise ValueError("resource supplementary reference identity differs")
    provenance={"execution_revision":revision,"reference_sha256":sha(args.reference/"image.bin"),
                "cases_sha256":runner.digest(cases),"contracts_sha256":runner.digest(contracts),
                "producer_sha256":sha(tests/"task11_execute.py"),"execution_inputs":inputs}
    result={**provenance,"native_object_sha256":sha(binary),"helper_sha256":sha(tests/"task11_native.py"),
            "leaves":native.compare(args.reference/"image.bin",binary,cases),
            "switches":native.switch_graph(binary),"publications":native.publication_widths(binary)}
    (args.objects/"native-results.json").write_text(json.dumps(result,indent=2)+"\n")
    print("PASS actual29 native/reference leaves,2switches,2publication footprints",flush=True)
    actual=sequence.execute(args.reference/"image.bin",cases,contracts,document)
    boundary={**provenance,"sequences_sha256":runner.digest(document),
              "helper_sha256":sha(tests/"task11_sequence.py"),"capture_sha256":sha(tests/"task10_sequence.py"),"actual":actual}
    (args.objects/"boundary-results.json").write_text(json.dumps(boundary,indent=2)+"\n")
    if revision!=subprocess.check_output(["git","rev-parse","HEAD"],cwd=repo,text=True).strip():
        raise ValueError("resource supplementary producer HEAD changed during execution")
    print("PASS actual3 resource boundary calls; HEAD held "+revision,flush=True)


if __name__=="__main__":main()
