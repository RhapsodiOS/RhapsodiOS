"""Fail closed on incomplete or stale Ultra2 reconstruction evidence."""

import argparse
import importlib.util
from pathlib import Path

from binrecon.identity import identify, verify_expected
from binrecon.ledger import load_ledger
from binrecon.macho import load_image
from binrecon.schema import load_json, load_source_map, validate_analysis_semantics, validate_document
from binrecon.source_map import build_source_map, source_sites
from binrecon.macho import objc_method_index


_spec = importlib.util.spec_from_file_location("au2_reference", Path(__file__).with_name("reference.py"))
ref = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ref)


def audit(stage: str, reference: Path, repo_root: Path, objects: Path | None,
          builds: Path | None, group: str | None) -> None:
    if stage != "inventory":
        raise ValueError(f"{stage}: reconstruction stage is not implemented")
    document = load_json(reference / "reference.json")
    identity = document["identity"]
    if (identity["sha256"], identity["size"], identity["architecture"], identity["endianness"]) != (ref.SHA256, ref.SIZE, "ppc", "big"):
        raise ValueError("inventory reference identity differs from pinned kernel")
    image_identity = identify(reference / "image.bin")
    verify_expected(image_identity, ref.SIZE, ref.SHA256)
    analysis_path = reference / "analysis.json"
    if identify(analysis_path).sha256 != document["analysis_sha256"]:
        raise ValueError("inventory saved analysis identity differs")
    analysis = load_json(analysis_path)
    validate_document("analysis-v1", analysis)
    validate_analysis_semantics(analysis)
    if analysis["input"] != identity or analysis["analyzer"] != document["analyzer"]:
        raise ValueError("inventory analysis identity differs")
    frozen = ref.frozen_functions(repo_root)
    ref.validate_partition(document["functions"], frozen)
    if document["functions"] != analysis["functions"]:
        raise ValueError("inventory functions differ from saved analysis")
    if document["ranges"] != ref.RANGES or document["boundary_disputes"]:
        raise ValueError("inventory ranges are incomplete or disputed")
    payload, macho = load_image(reference / "image.bin")
    modules, methods = ref.targeted_metadata(payload, macho)
    if document["methods"] != methods or len(methods) != 25 or sum(bool(m["category"]) for m in methods) != 4:
        raise ValueError("inventory metadata methods/category aliases differ")
    abi = load_json(reference / "abi.json")
    if abi != {"identity": identity, "modules": modules}:
        raise ValueError("inventory targeted ABI identity or metadata differs")
    if document["unnamed_helpers"] != ref.UNNAMED:
        raise ValueError("inventory unnamed helper accounting differs")
    owners = {}
    for function in document["functions"]:
        owner = ref.owner_of(function, methods)
        if frozen[function["address"]]["owner"] != owner:
            raise ValueError(f"inventory owner differs at 0x{function['address']:x}")
        owners.setdefault(owner, []).append(function["address"])
    if owners != document["owners"]:
        raise ValueError("inventory owner lists do not partition all functions")
    for owner, count in ref.OWNER_COUNTS.items():
        if len(owners[owner]) != count:
            raise ValueError(f"inventory {owner} count differs: {len(owners[owner])}")
    dependencies = ref.external_dependencies(analysis)
    if document["external_dependencies"] != dependencies or len(dependencies) != 29:
        raise ValueError("inventory external dependency accounting differs")
    for dependency in dependencies:
        if not (repo_root / dependency["provider"]).is_file():
            raise ValueError(f"external provider absent: {dependency['name']}")
    reader = ref.ObjcReader(payload, macho["sections"], "big")
    expected_data = {name: (a, b-a, owner) for name, a, b, owner in ref.PUBLIC_DATA}
    for address, size in ref.SWITCHES:
        caller = next(r["address"] for r in analysis["references"] if r["kind"] == "data" and r["target"] == address)
        function = next(f for f in analysis["functions"] if f["address"] <= caller < f["address"]+f["size"])
        expected_data[f"switch_{address:x}"] = (address, size, ref.owner_of(function, methods))
    if len(document["data"]) != len(expected_data) or {d["name"] for d in document["data"]} != set(expected_data):
        raise ValueError("inventory data objects missing or duplicated")
    for data in document["data"]:
        if (data["address"], data["size"], data["owner"]) != expected_data[data["name"]]:
            raise ValueError(f"inventory data extent/owner differs: {data['name']}")
        path = reference / "data" / (data["name"] + ".bin")
        if data["path"] != path.relative_to(reference).as_posix():
            raise ValueError(f"inventory data path differs: {data['name']}")
        verify_expected(identify(path), data["size"], data["sha256"])
        offset = reader.offset_of(data["address"])
        if path.read_bytes() != payload[offset:offset+data["size"]]:
            raise ValueError(f"inventory data bytes differ: {data['name']}")
    recon = repo_root / ref.DRIVER / "reconstruction"
    source_map = load_source_map(recon / "source-map.json", reference_analysis=analysis, repo_root=repo_root)
    if source_map["boundary_disputed"]:
        raise ValueError("inventory source map contains disputed function boundaries")
    current = build_source_map(analysis, macho, source_sites(repo_root, repo_root / ref.DRIVER),
                               extra_names=objc_method_index(reference / "image.bin"))
    if source_map != current:
        raise ValueError("inventory source map is stale against current source sites")
    ledger, _ = load_ledger(recon / "ledger.json", image_identity, None)
    entries = ledger["entries"]
    if len(entries) != 476 or {e["address"] for e in entries} != set(frozen):
        raise ValueError("inventory ledger does not account for all 476 bodies")
    for entry in entries:
        expected = frozen[entry["address"]]
        if entry["size"] != expected["size"] or entry["names"] != expected["names"]:
            raise ValueError(f"inventory ledger differs at 0x{entry['address']:x}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("inventory", "layouts", "firmware", "group", "final"))
    parser.add_argument("--reference", required=True, type=Path)
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--objects", type=Path)
    parser.add_argument("--builds", type=Path)
    parser.add_argument("--group")
    args = parser.parse_args()
    if args.stage == "group" and not args.group:
        parser.error("group stage requires --group OWNER_BASENAME")
    try:
        audit(args.stage, args.reference, args.repo_root, args.objects, args.builds, args.group)
    except (ValueError, OSError) as error:
        parser.exit(1, str(error) + "\n")
    print(f"{args.stage}: reference identity, partition and evidence verified")


if __name__ == "__main__":
    main()
