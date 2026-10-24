"""Execute genuine native transport/API objects with explicit accepted dependencies."""

import argparse
import json
import subprocess
from pathlib import Path

import task13_identity as identity
import task13_link as arena
import task13_native as native
import task13_stack as stack


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", required=True, type=Path)
    parser.add_argument("--objects", required=True, type=Path)
    parser.add_argument("--native", action="append", required=True, type=Path)
    parser.add_argument("--preflight", action="store_true")
    parser.add_argument("--case", action="append")
    parser.add_argument("--contexts-only", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[7]
    tests = Path(__file__).parent
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    inputs = identity.closure(repo, revision, args.preflight)
    cases = identity.load(tests/"task13-cases.json")
    contexts = identity.load(tests/"task13-context-cases.json")
    contracts = identity.load(tests/"task13-contracts.json")
    stack_cases = identity.load(tests/"task13-stack-cases.json")
    runner = native.module("ppc_cases")
    args.objects.mkdir(parents=True, exist_ok=True)
    binary = args.objects/"native-arena.macho"
    manifest = arena.link(args.reference/"image.bin", args.native, binary)
    (args.objects/"arena.json").write_text(json.dumps(manifest, indent=2)+"\n")
    selected = [] if args.contexts_only else [c for c in cases["cases"] if not args.case or c["entry"] in args.case]
    actual = []
    for case in selected:
        adapted = native.adapt(case, manifest)
        adapted = native.getter_copy(adapted, binary, manifest)
        result = native.run(binary, adapted, manifest=manifest)
        if result["observations"] != adapted["expected"]:
            (args.objects/"mismatch.json").write_text(json.dumps({"case": case, "adapted": adapted, "actual": result}, indent=2))
            raise ValueError("API native observations differ: "+case["id"])
        actual.append({**result, "canonical_case_sha256": runner.digest(case),
                       "adapted_case_sha256": runner.digest(adapted)})
        print("native "+case["id"]+" "+str(result["instructions"]), flush=True)
    caller = []
    if not args.case:
        for case in contexts["cases"]:
            pair = {}
            for label, path, adapted, mapping in (
                ("reference", args.reference/"image.bin", case, None),
                ("native", binary, native.adapt(case, manifest), manifest)):
                pair[label] = native.run(path, adapted, case["initial_r28"],
                    ["SCSIInitialize", "SCSIRInitialize", "SCSIHInitialize", "SCSIhInitializeHardware"], mapping)
                wanted = ["SCSIInitialize", "SCSIRInitialize", "SCSIHInitialize", "SCSIhInitializeHardware"]
                entries = [e for e in pair[label]["entries"] if e["entry"] in wanted]
                if (pair[label]["observations"] != adapted["expected"] or
                        [e["entry"] for e in entries] != wanted or
                        any(e["r28"] != case["initial_r28"] for e in entries)):
                    raise ValueError("API authentic caller context differs: "+label+"/"+case["id"])
            caller.append({"id": case["id"], "initial_r28": case["initial_r28"], **pair})
            print("context "+case["id"], flush=True)
    private = []
    if not args.case:
        for case in stack_cases["cases"]:
            pair = {"id": case["id"], "initial_private_byte": case["initial_private_byte"]}
            for label,path,adapted,mapping in (
                ("reference",args.reference/"image.bin",case,None),
                ("native",binary,native.adapt(case,manifest),manifest)):
                pair[label] = stack.run(path,adapted,mapping)
                if pair[label]["observations"] != adapted["expected"]:
                    raise ValueError("API PostBusScan private byte observation differs: "+label+"/"+case["id"])
            private.append(pair)
            print("private byte "+case["id"],flush=True)
    if (identity.closure(repo, revision, args.preflight) != inputs or
            subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip() != revision):
        raise ValueError("API producer HEAD/input closure changed during execution")
    result = {"execution_revision": revision, "preflight": args.preflight, "execution_inputs": inputs,
              "reference_sha256": identity.sha((args.reference/"image.bin").read_bytes()),
              "cases_sha256": runner.digest(cases), "contexts_sha256": runner.digest(contexts),
              "contracts_sha256": runner.digest(contracts), "arena_sha256": manifest["sha256"],
              "arena_manifest_sha256": identity.sha((args.objects/"arena.json").read_bytes()),
              "selected_case_ids": [c["id"] for c in selected], "results": actual, "contexts": caller,
              "private_stack_cases_sha256": runner.digest(stack_cases), "private_stack_contexts": private}
    (args.objects/"native-results.json").write_text(json.dumps(result, separators=(",", ":"))+"\n")
    print("PASS "+str(len(actual))+" genuine native cases, "+str(len(caller))+" API caller context pairs, "+str(len(private))+" private-byte pairs; HEAD "+revision, flush=True)


if __name__ == "__main__":
    main()
