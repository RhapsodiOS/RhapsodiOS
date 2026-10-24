"""Independent fix1 producer, with immutable legacy execution kept separate."""

from pathlib import Path
import task13_identity as old

BASE="4373a1cdbeb006200d50a8b1971b0f8fbe8e6680"
EXECUTION="5d3b106789f600dc0897003efd0d9bf8d197c020"
PROOF="AC0332414CB305C3BA675D7194936BE44D062A10C2EC6BDA164AB30522DD6629"
BASE_CONTRACTS="F9D68196022781308DD6EF81A8346B4601A88379B4CAB712266BCB852EFD55D2"
INVENTORY_BASE_RAW="734F31B379D7F8C8E0F350CBC46C211E5ED4EBC0423465FC934F8B1F7A3F672A"
OLD_ARTIFACTS={"reference-results.json":"8682A7165634C97B0FE6459984937A1BA25B42660F76C4B3F274C73942727672",
               "native-results.json":"E022F0C4B2B670AFA9E982670D9B6A70D326C07B8A342002F5345C5C259EF816",
               "native-arena.macho":"086BABB343B04F36889D56FF799DEBF65F372A357D5636B7E1C320AFA064DFAE",
               "arena.json":"90847A7D7F4658D8C1A64C2625AEDF222F60287B9E9A030E0A77E41DBD8A689D"}
NEW_INPUTS=[old.DRIVER/"tests"/name for name in ("task13_fix1_execute.py","task13_fix1_identity.py",
            "task13_fix1_runtime.py","task13_fix1_checks.py","task13-fix1-cases.json","task13-fix1-contracts.json","task13-fix1-alias.json")]
INPUTS=old.EXECUTION_INPUTS+NEW_INPUTS


def inventory_segment(raw):
    return raw.split(b"<!-- functions:start -->")[1].split(b"<!-- functions:end -->")[0]


def legacy_record(record,cases):
    if (record["execution_revision"]!=EXECUTION or record["preflight"] or len(record["execution_inputs"])!=32 or
            record["selected_case_ids"]!=[c["id"] for c in cases["cases"]] or len(record["results"])!=787 or
            len(record["contexts"])!=2 or len(record["private_stack_contexts"])!=2):
        raise ValueError("fix1 legacy producer/corpus/context scope differs")


def legacy(repo):
    tests=repo/old.DRIVER/"tests";objects=repo/"tools/binrecon/out/adaptecu2scsi-ppc/objects/task13"
    proof_path=old.DRIVER/"reconstruction/task13.json"
    if old.sha(old.canonical((repo/proof_path).read_bytes(),proof_path))!=PROOF:raise ValueError("fix1 original Task13 proof changed")
    proof=old.load(repo/proof_path)
    for name,digest in OLD_ARTIFACTS.items():
        if old.sha((objects/name).read_bytes())!=digest:raise ValueError("fix1 preserved actual legacy artifact differs: "+name)
    result=old.load(objects/"native-results.json");legacy_record(result,old.load(tests/"task13-cases.json"))
    if result["execution_inputs"]!=proof["execution_inputs"]:raise ValueError("fix1 original actual input record changed")
    current=old.closure(repo,EXECUTION)
    inventory=old.DRIVER/"reconstruction/inventory.md"
    for path in old.EXECUTION_INPUTS:
        key=path.as_posix();record=result["execution_inputs"][key]
        if current[key]["git_blob_sha256"]!=record["git_blob_sha256"]:raise ValueError("fix1 old consumed canonical input differs: "+key)
        if path!=inventory and current[key]["working_sha256"]!=record["working_sha256"]:raise ValueError("fix1 old31 whole working input differs: "+key)
    original=old.git(repo,EXECUTION,inventory)
    actual=(repo/inventory).read_bytes();baseline=old.git(repo,BASE,inventory)
    if (inventory_segment(actual)!=inventory_segment(baseline.replace(b"\n",b"\r\n")) or old.canonical(actual,inventory)!=old.canonical(original,inventory) or
            actual.replace(b"\r\n",b"\n")!=baseline or old.sha(actual)!=INVENTORY_BASE_RAW):
        raise ValueError("fix1 consumed inventory or pre-fix whole inventory differs")
    for path,digest in old.load(objects/"arena.json")["objects"].items():
        if old.sha(Path(path).read_bytes())!=digest:raise ValueError("fix1 genuine selected native object changed")
    baseline_contracts=(tests/"task13-contracts.json").read_bytes()
    if old.sha(old.canonical(baseline_contracts,Path("task13-contracts.json")))!=BASE_CONTRACTS:raise ValueError("fix1 immutable Task13 snapshot changed")
    return {"execution_revision":EXECUTION,"proof_sha256":PROOF,"artifacts":OLD_ARTIFACTS,
            "execution_inputs":result["execution_inputs"],"whole_working_files_equal":31,
            "inventory":{"old_whole_working_sha256":result["execution_inputs"][inventory.as_posix()]["working_sha256"],"base_revision":BASE,
                         "base_git_blob_sha256":old.sha(baseline),"base_whole_working_sha256":old.sha(actual),
                         "consumed_normalized_section_sha256":old.sha(old.canonical(actual,inventory)),
                         "base_exact_raw_section_sha256":old.sha(inventory_segment(actual))}}


def closure(repo,revision):
    records={}
    for path in INPUTS:
        raw=(repo/path).read_bytes();canonical=old.canonical(raw,path)
        if canonical!=old.canonical(old.git(repo,revision,path),path):raise ValueError("uncommitted fix1 consumed input: "+path.as_posix())
        records[path.as_posix()]={"git_blob_sha256":old.sha(canonical),"working_sha256":old.sha(raw)}
    return records
