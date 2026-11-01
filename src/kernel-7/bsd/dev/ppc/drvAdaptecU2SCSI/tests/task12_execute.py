"""Execute compiled HIM/Config/Resource and real reference callees without hooks that change behavior."""

import argparse
import json
import subprocess
from pathlib import Path

import task12_identity as identity
import task12_link as arena
import task12_native as native


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("reference", "objects", "him", "config", "resource"):
        parser.add_argument("--"+name, required=True, type=Path)
    parser.add_argument("--preflight", action="store_true")
    args=parser.parse_args();repo=Path(__file__).resolve().parents[7];tests=Path(__file__).parent
    revision=subprocess.check_output(["git","rev-parse","HEAD"],cwd=repo,text=True).strip()
    inputs=identity.closure(repo,revision,args.preflight)
    cases=identity.load(tests/"task12-cases.json");contexts=identity.load(tests/"task12-context-cases.json")
    contracts=identity.load(tests/"task12-contracts.json");runner=native.module("ppc_cases")
    args.objects.mkdir(parents=True,exist_ok=True)
    binary=args.objects/"native-arena.macho"
    manifest=arena.link(args.reference/"image.bin",[args.him,args.config,args.resource],binary)
    (args.objects/"arena.json").write_text(json.dumps(manifest,indent=2)+"\n")
    actual=[]
    for c in cases["cases"]:
        n=native.adapt(c,manifest)
        result=native.run(binary,n,manifest=manifest)
        if result["observations"] != n["expected"]:
            (args.objects/"mismatch.json").write_text(json.dumps({"case":c["id"],"actual":result,"expected":n["expected"]},indent=2))
            raise ValueError("HIM compiled observations differ: "+c["id"])
        actual.append(result)
        print("native "+c["id"]+" "+str(result["instructions"]),flush=True)
    caller=[]
    for c in contexts["cases"]:
        pair={}
        for label,path,adapted,mapping in (("reference",args.reference/"image.bin",c,None),
                                            ("native",binary,native.adapt(c,manifest),manifest)):
            pair[label]=native.run(path,adapted,c["initial_r28"],["SCSIRInitialize","SCSIhInitializeHardware"],mapping)
            if pair[label]["observations"] != adapted["expected"]:
                raise ValueError("HIM real caller context differs: "+label+"/"+c["id"])
            if ({e["entry"] for e in pair[label]["entries"]} !=
                    {"SCSIRInitialize","SCSIHInitialize","SCSIhInitializeHardware"} or
                    any(e["r28"] != c["initial_r28"] for e in pair[label]["entries"])):
                raise ValueError("HIM real caller r28 dataflow differs")
        caller.append({"id":c["id"],"initial_r28":c["initial_r28"],**pair})
        print("context "+c["id"],flush=True)
    leaf=native.module("task11_native");leaves=[]
    for argument,size in (("unit",16),("hhcb",1380)):
        c={"id":"task12-native-freeunit-"+argument,"entry":"SCSIHFreeUnitHandle","return_kind":"void",
           "arguments":[{"region":argument,"offset":0}],"memory":[{"name":argument,"size":size,"bytes":"a5"*size}]}
        pair={name:leaf.run(path,c,args.reference/"image.bin") for name,path in
              (("reference",args.reference/"image.bin"),("native",args.him))}
        if pair["reference"]["memory"] != pair["native"]["memory"] or pair["reference"]["writes"] or pair["native"]["writes"]:
            raise ValueError("HIM FreeUnit actual no-op differs")
        leaves.append({"id":c["id"],"case":c,**pair})
    result={"execution_revision":revision,"preflight":args.preflight,"execution_inputs":inputs,
            "reference_sha256":identity.sha((args.reference/"image.bin").read_bytes()),
            "cases_sha256":runner.digest(cases),"contexts_sha256":runner.digest(contexts),
            "contracts_sha256":runner.digest(contracts),"arena_sha256":manifest["sha256"],
            "arena_manifest_sha256":identity.sha((args.objects/"arena.json").read_bytes()),
            "results":actual,"contexts":caller,"leaves":leaves,"switch":native.switch_graph(args.him)}
    if (identity.closure(repo,revision,args.preflight) != inputs or
            subprocess.check_output(["git","rev-parse","HEAD"],cwd=repo,text=True).strip() != revision):
        raise ValueError("HIM producer HEAD/input closure changed during execution")
    (args.objects/"native-results.json").write_text(json.dumps(result,separators=(",",":"))+"\n")
    print("PASS135 compiled cases,2 real caller context pairs,2 FreeUnit pairs,8 switch paths; HEAD "+revision,flush=True)


if __name__ == "__main__":
    main()
