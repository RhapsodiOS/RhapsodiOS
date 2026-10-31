"""Validate the Intel82556 function inventory and refresh source locations.

Run from the repository root with the BinRecon Python environment. Binary and
analyzer exports are external inputs, never checked-in reconstruction sources.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[5]
RECON = Path(__file__).resolve().parent
LKS = RECON.parent / "Intel82556.drvproj/Intel82556.lksproj"
sys.path.insert(0, str(ROOT / "tools/binrecon"))
from binrecon.macho import objc_method_index, read_macho
from binrecon.identity import identify
from binrecon.ledger import load_ledger
from binrecon.schema import load_json, load_source_map


def imports(binary):
    return {s["name"] for s in read_macho(binary)["symbols"]
            if s["section"] is None and s["binding"] == "external"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--analysis", type=Path, required=True)
    parser.add_argument("--rebuilt", type=Path)
    parser.add_argument("--ledger", type=Path)
    parser.add_argument("--refresh", action="store_true")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="intel82556-map-") as temporary:
        draft = Path(temporary) / "source-map.json"
        subprocess.run([
            sys.executable, "-m", "binrecon", "source-map",
            "--reference-analysis", str(args.analysis.resolve()),
            "--binary", str(args.reference.resolve()),
            "--source-dir", str(LKS), "--repo-root", str(ROOT),
            "--output", str(draft), "--objc-methods",
        ], cwd=ROOT, check=True)
        document = load_json(draft)
    generated = {
        0x3e68: ("+[Intel82556NetworkDriverKernelServerInstance kernelServerInstance]", 81),
        0x3e74: ("+[Intel82556NetworkDriverVersion driverKitVersionForIntel82556NetworkDriver]", 95),
    }
    assert len(document["mapped"]) == 90, "handwritten function coverage changed"
    assert len(document["unmapped"]) == 2, "unexpected missing functions"
    assert not document["duplicate_candidates"] and not document["boundary_disputed"]
    for entry in document["unmapped"]:
        name, line = generated[entry["address"]]
        assert entry["reference_names"] == [name]
        entry.update(source_path="src/driverTools-1/KernelServerProjectType/CreateKLLDInstance.sh",
                     source_line=line)
        document["mapped"].append(entry)
    document["unmapped"] = []
    document["mapped"].sort(key=lambda item: item["address"])
    target = RECON / "source-map.json"
    if args.refresh:
        target.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    assert load_json(target) == document, "source map is stale; rerun with --refresh"
    load_source_map(target, reference_analysis=load_json(args.analysis), repo_root=ROOT)
    if args.rebuilt:
        reference_names = {name for names in objc_method_index(args.reference).values() for name in names}
        rebuilt_names = {name for names in objc_method_index(args.rebuilt).values() for name in names}
        assert reference_names == rebuilt_names, "Objective-C method inventory differs"
        assert imports(args.reference) == imports(args.rebuilt), "kernel import set differs"
        print("Objective-C method inventory and kernel imports match")
    if args.ledger:
        ledger, _ = load_ledger(args.ledger, identify(args.reference),
                                identify(args.rebuilt) if args.rebuilt else None)
        assert len(ledger["entries"]) == 92
        for entry, site in zip(ledger["entries"], document["mapped"]):
            assert (entry["address"], entry["size"], entry["names"],
                    entry["source_path"], entry["source_line"]) == (
                    site["address"], site["size"], site["reference_names"],
                    site["source_path"], site["source_line"]), "ledger source site is stale"
        print("Ledger identities, partition and source locations valid")
    print("92 functions accounted for: 90 handwritten, 2 generated; source map valid")


if __name__ == "__main__":
    main()
