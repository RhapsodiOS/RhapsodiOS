"""Execute only the independently frozen review corpus on both real images."""

import json
import subprocess
from pathlib import Path
import task13_fix1_identity as identity
import task13_fix1_runtime as runtime
import task13_fix1_checks as checks
import task13_native as native


def main():
    repo=Path(__file__).resolve().parents[7];tests=Path(__file__).parent
    out=repo/"tools/binrecon/out/adaptecu2scsi-ppc";target=out/"objects/task13-fix1"
    revision=subprocess.check_output(["git","rev-parse","HEAD"],cwd=repo,text=True).strip()
    inputs=identity.closure(repo,revision);legacy=identity.legacy(repo)
    cases=identity.old.load(tests/"task13-fix1-cases.json");contracts=runtime.contracts()
    manifest=identity.old.load(out/"objects/task13/arena.json");runner=native.module("ppc_cases")
    target.mkdir(exist_ok=True,parents=True)
    for label,binary,mapping in (("reference",out/"reference/image.bin",None),
                                  ("native",out/"objects/task13/native-arena.macho",manifest)):
        results=[]
        for case in cases["cases"]:
            adapted=case if mapping is None else native.adapt(case,mapping)
            result=runtime.run(binary,adapted,mapping)
            if result["observations"]!=adapted["expected"]:raise ValueError("fix1 actual observation differs: "+label+"/"+case["id"])
            checks.effects(case,result)
            result.update(canonical_case_sha256=runner.digest(case),adapted_case_sha256=runner.digest(adapted))
            results.append(result)
            (target/(label+"-"+case["id"]+".json")).write_bytes(json.dumps(result,separators=(",",":")).encode())
            print("PASS",label,case["id"],result["instructions"],flush=True)
        checks.complete_cases(cases["cases"],results)
        for finding in ("I1","I2","I3"):checks.require_paths(finding,cases["cases"],results)
        if (identity.closure(repo,revision)!=inputs or identity.legacy(repo)!=legacy or
                subprocess.check_output(["git","rev-parse","HEAD"],cwd=repo,text=True).strip()!=revision):
            raise ValueError("fix1 held producer or inputs changed during execution")
        record={"execution_revision":revision,"preflight":False,"execution_inputs":inputs,"legacy":legacy,
                "binary_sha256":identity.old.sha(binary.read_bytes()),"cases_sha256":runner.digest(cases),
                "contracts_sha256":runner.digest(contracts),"selected_case_ids":[c["id"] for c in cases["cases"]],"results":results}
        (target/(label+"-results.json")).write_bytes((json.dumps(record,separators=(",",":"))+"\n").encode())
        print("PASS",label,len(results),"committed review cases; HEAD",revision,flush=True)


if __name__=="__main__":main()
