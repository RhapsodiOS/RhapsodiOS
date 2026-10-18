"""Fail closed on incomplete or stale Ultra2 reconstruction evidence."""

import argparse
import importlib.util
import hashlib
import json
import re
import subprocess
from pathlib import Path

from binrecon.identity import identify, verify_expected
from binrecon.ledger import load_ledger
from binrecon.macho import load_image
from binrecon.schema import load_json, load_source_map, validate_analysis_semantics, validate_document
from binrecon.source_map import build_source_map, source_sites
from binrecon.macho import objc_method_index
from binrecon.objc_abi import ObjcReader, read_modules


_spec = importlib.util.spec_from_file_location("au2_reference", Path(__file__).with_name("reference.py"))
ref = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ref)


def audit(stage: str, reference: Path, repo_root: Path, objects: Path | None,
          builds: Path | None, group: str | None) -> None:
    if stage in ("firmware", "final"):
        evidence = authenticate_reference(reference, repo_root)
        if stage == "final":
            audit_data_accounting(evidence, repo_root, final=True)
            raise ValueError("final: complete reconstruction stage is not implemented")
        audit_firmware_objects(evidence, repo_root, objects)
        return
    if stage == "layouts":
        audit_layouts(reference, repo_root, objects)
        return
    if stage == "group":
        evidence = authenticate_reference(reference, repo_root)
        audit_service_group(evidence, repo_root, objects, group)
        return
    if stage != "inventory":
        raise ValueError(f"{stage}: reconstruction stage is not implemented")
    evidence = authenticate_reference(reference, repo_root)
    document, analysis, macho = evidence["document"], evidence["analysis"], evidence["macho"]
    frozen, image_identity = evidence["frozen"], evidence["image_identity"]
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


def audit_service_group(evidence, repo_root, objects, group):
    owners = {"AdaptecU2OSMServices.m": 37, "AdaptecU2CHIMOSD.c": 14}
    if group not in owners:
        raise ValueError("group: owner body recovery is not implemented: " + str(group))
    driver = repo_root / ref.DRIVER
    proof_path = driver / "reconstruction/task5.json"
    if not proof_path.is_file():
        raise ValueError("missing reviewed Task5 bodies/native evidence")
    proof = load_json(proof_path)
    expected_addresses = {a for owner in owners for a in evidence["document"]["owners"][owner]}
    reviews = {item["address"]: item for item in proof["bodies"]}
    if (proof.get("reference_sha256") != ref.SHA256 or len(proof["bodies"]) != 51 or
            set(reviews) != expected_addresses):
        raise ValueError("Task5 review must cover exactly 37+14 bodies")
    if objects is None:
        raise ValueError("group requires actual target objects")
    manifest = load_json(objects / "objects.json")
    if (manifest.get("configuration") != "RELEASE_PPC" or manifest.get("hash_algorithm") != "SHA-256" or
            manifest.get("source_revision") != proof["native_revision"] or len(manifest["objects"]) != 2):
        raise ValueError("invalid Task5 target provenance")
    native = {}
    for item in manifest["objects"]:
        owner = Path(item["source"]).name
        if (owner not in owners or item["source"] != "bsd/dev/ppc/drvAdaptecU2SCSI/" + owner or
                item["path"] != Path(item["path"]).name or item["cpu_type"] != 18):
            raise ValueError("invalid Task5 PPC source/object")
        for path, digest in [(driver / owner, item["source_sha256"]),
                             (objects / item["path"], item["sha256"])]:
            if hashlib.sha256(path.read_bytes()).hexdigest().upper() != digest:
                raise ValueError("stale Task5 native source/object: " + path.name)
        payload, macho = load_image(objects / item["path"])
        symbols = sorted([s for s in macho["symbols"] if s["binding"] == "external" and
                          s["section"] == "__TEXT,__text"], key=lambda s: s["address"])
        text = next(s for s in macho["sections"] if s["name"] == "__TEXT,__text")
        bodies = {}
        for index, symbol in enumerate(symbols):
            end = symbols[index+1]["address"] if index+1 < len(symbols) else text["address"] + text["size"]
            start = text["offset"] + symbol["address"] - text["address"]
            bodies[symbol["name"]] = payload[start:start + end - symbol["address"]]
        native[owner] = bodies
    if set(native) != set(owners):
        raise ValueError("missing or duplicate Task5 native owner")
    inputs = proof["native_inputs"]
    if set(inputs) != set(owners) | set(LAYOUT_HEADERS):
        raise ValueError("Task5 native header/source closure is incomplete")
    for name, hashes in inputs.items():
        raw = (driver / name).read_bytes()
        blob = subprocess.check_output(["git", "show", proof["native_revision"] + ":" +
                                        (driver / name).relative_to(repo_root).as_posix()], cwd=repo_root)
        if (hashlib.sha256(raw).hexdigest().upper() != hashes["staged_sha256"] or
                hashlib.sha256(blob).hexdigest().upper() != hashes["git_blob_sha256"] or
                raw.replace(b"\r\n", b"\n") != blob):
            raise ValueError("stale Task5 producer input: " + name)
    header_lines = {}
    for line in (objects / "header-inputs.sha256").read_text().splitlines():
        digest, path = line.split(maxsplit=1)
        name = Path(path).name
        if name in header_lines or path != "bsd/dev/ppc/drvAdaptecU2SCSI/" + name:
            raise ValueError("invalid Task5 target header manifest")
        header_lines[name] = digest.upper()
    if header_lines != {name: inputs[name]["staged_sha256"] for name in LAYOUT_HEADERS}:
        raise ValueError("Task5 target header hashes differ")
    sites = source_sites(repo_root, driver)
    ledger, _ = load_ledger(driver / "reconstruction/ledger.json", evidence["image_identity"], None)
    ledger_entries = {entry["address"]: entry for entry in ledger["entries"]}
    proof_hash = hashlib.sha256(proof_path.read_bytes()).hexdigest().upper()
    cases = load_json(driver / "tests/task5-cases.json")
    contracts = load_json(driver / "tests/contracts.json")
    runner_spec = importlib.util.spec_from_file_location("au2_group_runner", driver / "tests/ppc_cases.py")
    runner = importlib.util.module_from_spec(runner_spec)
    runner_spec.loader.exec_module(runner)
    result = load_json(objects / "reference-results.json")
    runner.validate_result(result, evidence["reference_path"] / "image.bin", cases, contracts)
    for address in evidence["document"]["owners"][group]:
        function, review, entry = evidence["frozen"][address], reviews[address], ledger_entries[address]
        name = function["names"][0]
        symbol = name if name.startswith("_") else "_" + name
        locations = sites.get(symbol, [])
        expected_location = (ref.DRIVER.as_posix() + "/" + group, review["source_line"])
        if (review["owner"] != group or review["name"] != name or not review.get("control_flow") or
                locations.count(expected_location) != 1 or len(locations) != 1 or
                (entry["source_path"], entry["source_line"]) != expected_location or
                entry["status"] not in ("control-flow-confirmed", "assembly-matched") or
                not any(a["path"] == proof_path.relative_to(repo_root).as_posix() and
                        a["sha256"] == proof_hash for a in entry["artifacts"])):
            raise ValueError(f"missing actual reviewed body/source evidence: 0x{address:x}")
        code = native[group].get(symbol, b"")
        if len(code) < 12 or len(code) % 4 or hashlib.sha256(code).hexdigest().upper() != review["native_sha256"]:
            raise ValueError("Task5 native body differs: " + name)
        selected = [case for case in cases["cases"] if case["id"] in review["cases"]]
        if not selected or {case["id"] for case in selected} != set(review["cases"]) or any(
                case["evidence"]["entry_address"] != address for case in selected):
            raise ValueError("missing required successful body fixture: " + name)
        if name.startswith("_OSMWrite") and "PCI" not in name and bytes.fromhex("7c0006ac") not in code:
            raise ValueError("missing target eieio after MMIO write: " + name)
        if name.removeprefix("_") in contracts["osm_input_erased"]:
            expected = contracts["osm_input_erased"][name.removeprefix("_")]["reference_bytes"]
            if code.hex() != expected:
                raise ValueError("erased OSM machine contract bytes differ: " + name)
    data = audit_data_accounting(evidence, repo_root)
    if group == "AdaptecU2CHIMOSD.c":
        for name in ("switch_231258", "switch_2314c0"):
            row = next(row for row in data["objects"] if row["name"] == name)
            if row["status"] != "recovered" or row.get("production_evidence") != "reconstruction/task5.json":
                raise ValueError("pending required owner switch: " + name)
            switch = proof["switches"][name]
            if (switch["normalized_cases"] != list(range(row["normalized_case_count"])) or
                    switch["owner_function"] != row["function"] or not switch["native_control_flow"] or
                    not switch["default_cases"]):
                raise ValueError("incomplete native/source switch outcomes: " + name)


def authenticate_reference(reference, repo_root):
    """Authenticate extracted inputs once and pass the checked values to consumers."""
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
    if any(macho["input"][key] != identity[key] for key in
           ("sha256", "size", "architecture", "endianness")):
        raise ValueError("inventory loaded image identity differs")
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
    data_bytes = {}
    for data in document["data"]:
        if (data["address"], data["size"], data["owner"]) != expected_data[data["name"]]:
            raise ValueError(f"inventory data extent/owner differs: {data['name']}")
        path = reference / "data" / (data["name"] + ".bin")
        if data["path"] != path.relative_to(reference).as_posix():
            raise ValueError(f"inventory data path differs: {data['name']}")
        verify_expected(identify(path), data["size"], data["sha256"])
        offset = reader.offset_of(data["address"])
        raw = path.read_bytes()
        if raw != payload[offset:offset+data["size"]]:
            raise ValueError(f"inventory data bytes differ: {data['name']}")
        data_bytes[data["name"]] = raw
    if document.get("firmware") != ref.firmware_metadata(document["data"], data_bytes, payload, macho):
        raise ValueError("firmware reference loader/selector metadata differs")
    return {"document": document, "abi": abi, "analysis": analysis, "macho": macho,
            "frozen": frozen, "image_identity": image_identity, "data": data_bytes, "payload": payload, "reference_path": reference}


LAYOUT_HEADERS = (
    "AdaptecU2CHIMTypes.h", "AdaptecU2CHIM.h", "AdaptecU2CHIMPrivate.h",
    "OSMFunctions.h", "AdaptecU2SCSI.h", "AdaptecU2SCSIPrivate.h",
)

CHIM_ERASED = {
    "SCSISaveState": 0x1a4d78, "SCSIRestoreState": 0x1a4d84,
    "SCSIProfileNexus": 0x1a5e00, "SCSIClearNexusTSH": 0x1a5e10,
    "SCSIProfileNode": 0x1a5e20, "SCSIReportAdjustableNodeProfile": 0x1a5e30,
    "SCSIAdjustNodeProfile": 0x1a5e40, "SCSISetOSMNodeContext": 0x1a5e50,
    "SCSIhSwappingSearchExeQ": 0x1908dc, "SCSIhScamSupportCheck": 0x19cb3c,
    "SCSIHApplyDeviceTable": 0x19db7c,
}
OSM_ERASED = {
    "OSMSynchronizeRange": 0x18a484, "OSMSaveInterruptState": 0x18a50c,
    "OSMSetInterruptState": 0x18a51c,
}


def declarations(driver):
    text = "\n".join((driver / name).read_text() for name in LAYOUT_HEADERS[:3])
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    matches = re.finditer(r"^([\w *]+?)\b((?:SCSI|OSD)\w+)\s*\(([^;]*)\);", text, re.M)
    result = {}
    for match in matches:
        name = match[2]
        if name in result:
            raise ValueError(f"duplicate CHIM declaration: {name}")
        result[name] = re.sub(r"\s+", " ", match[0].strip())
    return result


def audit_dispatch_headers(driver, reference):
    evidence = authenticate_reference(reference, driver.parents[5])
    _audit_dispatch_headers(driver, evidence)


def _audit_dispatch_headers(driver, evidence):
    abi = evidence["abi"]
    klass = abi["modules"]["AdaptecU2SCSI.m"]["classes"][0]
    him = next(v["type"] for v in klass["ivars"] if v["name"] == "HIMFunc")
    expected_him = re.findall(r'"(HIM\w+)"\^\?', him)
    for filename, tag, expected in [
        ("AdaptecU2CHIM.h", "AdaptecU2HIMFunctions", expected_him),
        ("OSMFunctions.h", "AdaptecU2OSMFunctions", [
            "OSMMapIOHandle", "OSMReleaseIOHandle", "OSMEvent", "OSMGetBusAddress",
            "OSMAdjustBusAddress", "OSMGetNVSize", "OSMPutNVData", "OSMGetNVData",
            "OSMReadUExact8", "OSMReadUExact16", "OSMReadUExact32",
            "OSMReadStringUExact8", "OSMReadStringUExact16", "OSMReadStringUExact32",
            "OSMWriteUExact8", "OSMWriteUExact16", "OSMWriteUExact32",
            "OSMWriteStringUExact8", "OSMWriteStringUExact16", "OSMWriteStringUExact32",
            "OSMSynchronizeRange", "OSMWatchdog", "OSMSaveInterruptState", "OSMSetInterruptState",
            "OSMReadPCIConfigurationDword", "OSMReadPCIConfigurationWord", "OSMReadPCIConfigurationByte",
            "OSMWritePCIConfigurationDword", "OSMWritePCIConfigurationWord", "OSMWritePCIConfigurationByte"]),
    ]:
        text = (driver / filename).read_text()
        body = re.search(r"struct " + tag + r"\s*\{(.*?)\};", text, re.S)
        if not body or not body[1].strip().startswith("unsigned int versionNumber;"):
            raise ValueError(f"{tag}: version word is missing or callable")
        # Anchor at the outer member declaration, excluding nested watchdog args.
        callbacks = re.findall(r"^\s*[\w *]+\(\*(\w+)\)\(", body[1], re.M)
        if callbacks != expected:
            raise ValueError(f"{tag}: ordered callback slots differ")
    signatures = load_json(driver / "reconstruction/signatures.json")
    frozen = evidence["document"]
    functions = [f for f in frozen["functions"] if f["address"] >= 0x18b754]
    records = signatures["functions"]
    if signatures["reference_sha256"] != ref.SHA256 or len(records) != 392:
        raise ValueError("CHIM signature evidence identity/count differs")
    by_address = {r["address"]: r for r in records}
    if len(by_address) != 392 or set(by_address) != {f["address"] for f in functions}:
        raise ValueError("CHIM signature evidence does not partition392 entries")
    current = declarations(driver)
    if set(current) != {r["name"] for r in records}:
        raise ValueError("CHIM declaration set differs from evidence")
    contracts = load_json(driver / "tests/contracts.json")
    erased = contracts["input_erased"]
    if ({name: item["address"] for name, item in erased.items()} != CHIM_ERASED or
            sum(r["classification"] == "input-erased" for r in records) != 11):
        raise ValueError("input-erased exception set differs")
    osm_erased = contracts["osm_input_erased"]
    osm_header = (driver / "OSMFunctions.h").read_text()
    if ({name: item["address"] for name, item in osm_erased.items()} != OSM_ERASED or
            set(re.findall(r"\b(OSM\w+)\s*\(\s*\)\s*;", osm_header)) != set(OSM_ERASED)):
        raise ValueError("OSM input-erased exception set differs")
    evidence = (driver / "reconstruction/interfaces.md").read_text()
    for f in functions:
        record = by_address[f["address"]]
        name = record["name"]
        if "_" + name not in f["names"] or current[name] != record["declaration"]:
            raise ValueError(f"signature declaration differs: {name}")
        if f["address"] not in frozen["owners"].get(record["owner"], []):
            raise ValueError(f"signature owner differs: {name}")
        if name in erased:
            if record["classification"] != "input-erased" or current[name] != "unsigned int " + name + "();":
                raise ValueError(f"erased declaration misrepresented: {name}")
        elif (record["classification"] != "reviewed-typed" or
              not record["evidence"].startswith("| ") or record["evidence"] not in evidence or
              hex(f["address"])[2:] not in record["evidence"].lower() or
              current[name].endswith("();")):
            raise ValueError(f"missing individual typed evidence: {name}")


def audit_target_inputs(driver, objects):
    manifest = load_json(objects / "objects.json")
    if (manifest.get("configuration") != "RELEASE_PPC" or
            manifest.get("hash_algorithm") != "SHA-256" or
            not re.fullmatch(r"[0-9a-fA-F]{40}", manifest.get("source_revision", ""))):
        raise ValueError("invalid target build provenance")
    entries = manifest["objects"]
    if len(entries) != 1 or entries[0]["source"] != "bsd/dev/ppc/drvAdaptecU2SCSI/tests/layout-checks.m":
        raise ValueError("layout object source/count differs")
    entry = entries[0]
    if entry["path"] != Path(entry["path"]).name or entry["cpu_type"] != 18:
        raise ValueError("invalid PPC layout object")
    obj = objects / entry["path"]
    for path, expected in [(obj, entry["sha256"]),
                           (driver / "tests/layout-checks.m", entry["source_sha256"])]:
        if hashlib.sha256(path.read_bytes()).hexdigest().upper() != expected.upper():
            raise ValueError(f"stale target input/object: {path.name}")
    hashes = {}
    for line in (objects / "header-inputs.sha256").read_text().splitlines():
        digest, name = line.split(maxsplit=1)
        header = Path(name).name
        if name != "bsd/dev/ppc/drvAdaptecU2SCSI/" + header or header in hashes:
            raise ValueError("invalid or duplicate target header provenance")
        hashes[header] = digest.upper()
    if set(hashes) != set(LAYOUT_HEADERS):
        raise ValueError("target header closure is incomplete")
    for name, expected in hashes.items():
        if hashlib.sha256((driver / name).read_bytes()).hexdigest().upper() != expected:
            raise ValueError(f"stale target header: {name}")
    return obj


def _audit_callback_initializers(evidence, objects, macho, reader, symbols):
    frozen = evidence["document"]
    names = {f["address"]: next(n for n in f["names"] if n.startswith("_"))
             for f in frozen["functions"] if any(n.startswith("_") for n in f["names"])}
    relocations = {r["address"]: r for r in macho["relocations"]}
    tables = [("SCSIFuncPtrs", "_au2_him_type_check", 4, 168),
              ("OSMRoutines", "_au2_osm_type_check", 4, 124)]
    tables += [(name, "_au2_check_" + name, 0, 100) for name in
               ("SCSIHardwareAIC78XX", "SCSIHardwareAICBayonet")]
    tables += [(name, "_au2_check_" + name, 84, 296) for name in
               ("SCSIFirmwareStandard64", "SCSIFirmwareSwapping32",
                "SCSIFirmwareStandardAdv", "SCSIFirmwareSwappingAdv")]
    for name, symbol, first, end in tables:
        raw = evidence["data"][name]
        if symbol not in symbols:
            raise ValueError(f"missing typed callback initializer: {name}")
        base = symbols[symbol]
        if name in ("SCSIFuncPtrs", "OSMRoutines") and reader.at(base, 1)[0] != int.from_bytes(raw[:4], "big"):
            raise ValueError(f"callback version word differs: {name}")
        for offset in range(first, end, 4):
            target = int.from_bytes(raw[offset:offset+4], "big")
            relocation = relocations.get(base + offset)
            if target == 0:
                if relocation or reader.at(base + offset, 1)[0] != 0:
                    raise ValueError(f"nonzero reserved callback: {name}+{offset}")
            elif (target not in names or not relocation or relocation["target"] != names[target] or
                  relocation["kind"] != "ppc-vanilla-32-absolute" or relocation["addend"] != 0):
                raise ValueError(f"callback relocation differs: {name}+{offset}")
    # Old cc emits incompatible function-pointer initializers as warnings.
    # The two explicitly obsolete SDK headers are independently known inputs.
    log = (objects / "1.log").read_text()
    allowed = ("../../kernserv/clock_timer.h:44: warning: #warning Obsolete header file:",
               "../../kernserv/queue.h:41: warning: #warning Obsolete header file:")
    for line in log.splitlines():
        if ("warning:" in line or "error:" in line) and not line.startswith(allowed):
            raise ValueError("target callback/type diagnostic: " + line)


def audit_layouts(reference, repo_root, objects):
    if objects is None:
        raise ValueError("layouts requires --objects with the target object/manifest/header closure")
    evidence = authenticate_reference(reference, repo_root)
    driver = repo_root / ref.DRIVER
    _audit_dispatch_headers(driver, evidence)
    obj = audit_target_inputs(driver, objects)
    payload, macho = load_image(obj)
    if (macho["input"]["architecture"], macho["input"]["endianness"]) != ("ppc", "big"):
        raise ValueError("layout object is not big-endian PPC")
    reader = ObjcReader(payload, macho["sections"], "big")
    contract = load_json(driver / "tests/layout-contracts.json")
    if contract["reference_sha256"] != ref.SHA256:
        raise ValueError("layout contract reference differs")
    expected = dict(contract["constants"])
    for name, layout in contract["layouts"].items():
        if not layout["evidence"] or not layout["extent"]:
            raise ValueError(f"missing layout extent/evidence: {name}")
        expected["_au2_" + name + "_layout"] = [layout["size"], *layout["fields"].values()]
    expected["_au2_controller_layout"] = [1488,580,604,684,1228,1408,1416,1424,512]
    symbols = {s["name"]: s["address"] for s in macho["symbols"] if s["section"] is not None}
    _audit_callback_initializers(evidence, objects, macho, reader, symbols)
    for name, values in expected.items():
        if name not in symbols or list(reader.at(symbols[name], len(values))) != values:
            raise ValueError(f"target size/offset constants differ: {name}")
    modules = read_modules(obj)
    if set(modules) != {"layout-checks.m"}:
        raise ValueError("target metadata module differs")
    target = modules["layout-checks.m"]
    frozen = evidence["abi"]["modules"]
    expected_classes = frozen["AdaptecU2SCSI.m"]["classes"]
    expected_categories = frozen["AdaptecU2SCSIThread.m"]["categories"]
    def ordered(records):
        result = []
        for record in records:
            record = dict(record)
            for key in ("instance_methods", "class_methods"):
                record[key] = sorted(record[key], key=lambda m: m["selector"])
            result.append(record)
        return result
    if ordered(target["classes"]) != ordered(expected_classes):
        raise ValueError("target controller ivars, size, superclass or method encodings differ")
    if ordered(target["categories"]) != ordered(expected_categories):
        raise ValueError("target thread category/selector encodings differ")


def audit_switch_metadata(record, function, raw, evidence):
    """Decode the one PPC switch idiom shared by these 22 reference tables."""
    reader = ObjcReader(evidence["payload"], evidence["macho"]["sections"], "big")
    dispatch = record["dispatch"]

    def word(address):
        if not function["address"] <= address < function["address"] + function["size"]:
            raise ValueError("switch instruction outside owner: " + record["name"])
        return reader.at(address, 1)[0]

    def table_address(high, low):
        if high & 0xffff0000 != 0x3d200000 or low & 0xffff0000 != 0x39290000:
            raise ValueError("switch table-base instructions differ: " + record["name"])
        immediate = low & 0xffff
        return (((high & 0xffff) << 16) +
                (immediate - 0x10000 if immediate & 0x8000 else immediate)) & 0xffffffff

    scale, load = word(dispatch - 24), word(dispatch - 20)
    if (scale & ~(31 << 21) != 0x5400103a or
            load & ~(31 << 16) != 0x7c00002e or
            [word(dispatch - n) for n in (8, 4, 0)] != [0x7c004a14, 0x7c0903a6, 0x4e800420] or
            table_address(word(dispatch - 16), word(dispatch - 12)) != record["address"]):
        raise ValueError("switch scale/load/relative dispatch differs: " + record["name"])
    index_register, base_register = (scale >> 21) & 31, (load >> 16) & 31
    if base_register == 9:
        if table_address(word(dispatch - 32), word(dispatch - 28)) != record["address"]:
            raise ValueError("switch indexed-load table differs: " + record["name"])
        branch_address = dispatch - 36
    elif base_register in (30, 31):
        # The two backend switches retain their table in callee-saved registers.
        # Check the actual earlier lis/addi preload, not a recorded JSON label.
        prefix = 0x3d200000  # lis r9, table@ha
        addition = 0x38000000 | base_register << 21 | 9 << 16
        preloaded = False
        for address in range(function["address"], dispatch - 24, 4):
            high, low = word(address), word(address + 4)
            if high & 0xffff0000 == prefix and low & 0xffff0000 == addition:
                immediate = low & 0xffff
                value = (((high & 0xffff) << 16) +
                         (immediate - 0x10000 if immediate & 0x8000 else immediate)) & 0xffffffff
                preloaded |= value == record["address"]
        if not preloaded:
            raise ValueError("switch table preload missing: " + record["name"])
        branch_address = dispatch - 28
    else:
        raise ValueError("unsupported switch indexed-load register: " + record["name"])
    branch = word(branch_address)
    if branch & 0xffff0003 != 0x41850000:  # bgt cr1, relative, without link
        raise ValueError("switch unsigned default branch differs: " + record["name"])
    displacement = branch & 0xfffc
    default = (branch_address + (displacement - 0x10000 if displacement & 0x8000 else displacement)) & 0xffffffff
    guard = branch_address - 4
    while word(guard) & 0xffe00000 != 0x28800000:  # cmplwi cr1 (32-bit unsigned)
        instruction = word(guard)
        opcode = instruction >> 26
        if opcode in (36, 38):  # non-updating stw/stb preserve GPRs and CR1
            destination = None
        elif opcode in (8, 14):  # subfic/addi preserve CR1
            destination = (instruction >> 21) & 31
        elif opcode == 26:  # xori
            destination = (instruction >> 16) & 31
        elif opcode == 31 and not instruction & 1 and (instruction >> 1) & 1023 in (138, 444):
            destination = (instruction >> (21 if (instruction >> 1) & 1023 == 138 else 16)) & 31
        else:
            raise ValueError("unsupported switch guard intervening instruction: " + record["name"])
        if destination == index_register:
            raise ValueError("switch guard index overwritten: " + record["name"])
        guard -= 4
    compare = word(guard)
    if (compare >> 16) & 31 != index_register:
        raise ValueError("switch compared/scaled index differs: " + record["name"])
    count = (compare & 0xffff) + 1
    if count * 4 != len(raw) or not function["address"] <= default < function["address"] + function["size"]:
        raise ValueError("switch machine range/default differs: " + record["name"])
    groups = {}
    for value in range(count):
        target = record["address"] + int.from_bytes(raw[value*4:value*4+4], "big", signed=True)
        groups.setdefault(target, []).append(value)
    expected = {"normalized_lowcase": 0, "normalized_case_count": count,
                "guard_start": guard, "default_target": default,
                "case_map": [{"values": values, "target": target} for target, values in sorted(groups.items())]}
    for field, value in expected.items():
        if json.dumps(record.get(field), sort_keys=True) != json.dumps(value, sort_keys=True):
            raise ValueError("switch metadata differs: " + record["name"] + "." + field)
    return expected


def audit_data_accounting(evidence, repo_root, final=False):
    contract = load_json(repo_root / ref.DRIVER / "reconstruction/data.json")
    records = contract["objects"]
    frozen = {d["name"]: d for d in evidence["document"]["data"]}
    if contract["reference_sha256"] != ref.SHA256 or len(records) != 48 or {d["name"] for d in records} != set(frozen):
        raise ValueError("data accounting must cover all 48 reference envelopes")
    symbols = {s["address"]: s["name"].removeprefix("_") for s in evidence["analysis"]["symbols"]}
    symbols.update({d["address"]: d["name"] for d in frozen.values()})
    for function in evidence["document"]["functions"]:
        for name in function["names"]:
            if name.startswith("_"):
                symbols[function["address"]] = name[1:]
    for record in records:
        name = record["name"]
        raw = evidence["data"][name]
        if any(record[k] != frozen[name][k] for k in ("address", "size", "sha256", "owner")):
            raise ValueError("data accounting identity/extent differs: " + name)
        section = next(s["name"] for s in evidence["macho"]["sections"]
                       if s["address"] <= record["address"] < s["address"] + s["size"])
        if record["alignment"] != 4 or record["reference_section"] != section:
            raise ValueError("data alignment/section accounting differs: " + name)
        if not record["interpretation"] or not record["consumers"] or not record["required_gate"]:
            raise ValueError("data interpretation/consumer/gate missing: " + name)
        if record["status"] not in ("recovered", "pending-owner-recovery", "pending-owner-control-flow"):
            raise ValueError("unknown data status: " + name)
        if record["reference_bytes"] != raw.hex():
            raise ValueError("frozen data bytes differ: " + name)
        for offset, target in record.get("interior_pointers", {}).items():
            base = frozen.get(target["object"])
            if not base or not 0 <= target["offset"] < base["size"] or int.from_bytes(raw[int(offset):int(offset)+4], "big") != base["address"] + target["offset"]:
                raise ValueError("reference interior pointer differs: " + name + "+" + offset)
        if name.startswith("SCSIHardwareAIC"):
            pointer_offsets = set(range(0, 100, 4))
        elif name.startswith("SCSIFirmware") and name != "SCSIFirmware":
            pointer_offsets = set(range(84, 296, 4)) - {136, 276}
        elif name in ("SCSIFuncPtrs", "OSMRoutines"):
            pointer_offsets = set(range(4, len(raw), 4))
        elif name in ("SCSIHardware", "SCSIFirmware", "adapterQ"):
            pointer_offsets = set(range(0, len(raw), 4))
        elif name == "event_names":
            pointer_offsets = set(range(4, len(raw), 8))
        else:
            pointer_offsets = set()
        if {f["offset"] for f in record["fields"] if f["kind"] == "pointer"} != pointer_offsets:
            raise ValueError("data pointer/scalar classification differs: " + name)
        nonzero_pointers = {o for o in pointer_offsets if int.from_bytes(raw[o:o+4], "big")}
        if {int(o) for o in record["pointers"]} | {int(o) for o in record.get("interior_pointers", {})} != nonzero_pointers:
            raise ValueError("data normalized pointer set differs: " + name)
        covered = []
        for field in record["fields"]:
            offset, width = field["offset"], field["width"]
            covered.extend(range(offset, offset + width))
            if field["kind"] == "pointer" and width != 4:
                raise ValueError("invalid native pointer width: " + name)
        if sorted(covered) != list(range(len(raw))):
            raise ValueError("data fields overlap or omit bytes: " + name)
        for offset, target in record["pointers"].items():
            value = int.from_bytes(raw[int(offset):int(offset)+4], "big")
            if symbols.get(value) != target:
                raise ValueError("reference data pointer differs: " + name + "+" + offset)
        if name.startswith("switch_"):
            dispatch = record["dispatch"]
            function = next((f for f in evidence["document"]["functions"]
                             if f["address"] <= dispatch < f["address"] + f["size"]), None)
            if not function or function["address"] != record["function"]:
                raise ValueError("switch owner/control-flow differs: " + name)
            instructions = {i["address"]: i for i in function["instructions"]}
            if (not record["instructions"] or record["instructions"][-1]["address"] != dispatch or
                    instructions[dispatch]["bytes"] != "4E800420"):
                raise ValueError("switch dispatch instruction differs: " + name)
            for instruction in record["instructions"]:
                if instruction["address"] not in instructions or instruction["bytes"] != instructions[instruction["address"]]["bytes"]:
                    raise ValueError("switch guard/index bytes differ: " + name)
            targets = [record["address"] + int.from_bytes(raw[o:o+4], "big", signed=True) for o in range(0,len(raw),4)]
            jump_targets = {r["target"] for r in evidence["analysis"]["references"]
                            if r["address"] == dispatch and r["kind"] == "code"}
            if (record["encoding"] != "signed32-big-endian-table-relative" or set(targets) != jump_targets):
                raise ValueError("switch dispatch/case references differ: " + name)
            if targets != record["targets"] or any(not function["address"] <= t < function["address"] + function["size"] or t % 4 for t in targets):
                raise ValueError("switch case targets differ: " + name)
            if not any(r["kind"] == "data" and r["target"] == record["address"] and
                       function["address"] <= r["address"] < function["address"] + function["size"]
                       for r in evidence["analysis"]["references"]):
                raise ValueError("switch incoming reference missing: " + name)
            audit_switch_metadata(record, function, raw, evidence)
    if final:
        pending = [d["name"] for d in records if d["status"] != "recovered"]
        if pending:
            raise ValueError("pending required data: " + ", ".join(pending))
    return contract


def compare_firmware_data(record, raw, payload, macho, symbols):
    """Compare scalar bytes exactly and only declared pointer fields symbolically."""
    name = record["name"]
    symbol = symbols.get("_" + name)
    if not symbol or symbol["section"] != "__DATA,__data" or symbol["address"] % record["alignment"]:
        raise ValueError("missing/misplaced mutable data symbol: " + name)
    base = symbol["address"]
    section = next(s for s in macho["sections"] if s["name"] == symbol["section"])
    next_symbol = min([s["address"] for s in symbols.values() if s["section"] == symbol["section"] and s["address"] > base] + [section["address"] + section["size"]])
    if next_symbol - base != record["size"]:
        raise ValueError("data extent differs: " + name)
    reader = ObjcReader(payload, macho["sections"], "big")
    actual = bytearray(payload[reader.offset_of(base):reader.offset_of(base) + record["size"]])
    expected = bytearray(raw)
    relocs = {r["address"]: r for r in macho["relocations"] if base <= r["address"] < base + record["size"]}
    for offset, target in record["pointers"].items():
        offset = int(offset)
        relocation = relocs.pop(base + offset, None)
        if not relocation or relocation["kind"] != "ppc-vanilla-32-absolute":
            raise ValueError(f"pointer relocation differs: {name}+{offset}")
        target_symbol = symbols.get("_" + target)
        direct = relocation["target"] == "_" + target and relocation["addend"] == 0
        local = False
        if target_symbol and relocation["target"] == target_symbol["section"]:
            target_section = next(s for s in macho["sections"] if s["name"] == target_symbol["section"])
            local = relocation["addend"] == target_symbol["address"] - target_section["address"]
        if not (direct or local):
            raise ValueError(f"pointer target differs: {name}+{offset}: expected {target}")
        actual[offset:offset+4] = expected[offset:offset+4] = b"\0" * 4
    if relocs:
        raise ValueError("unexpected scalar/zero relocation: " + name)
    if actual != expected:
        first = next(i for i, (a,b) in enumerate(zip(actual,expected)) if a != b)
        raise ValueError(f"data bytes differ: {name}+{first}")


def audit_firmware_objects(evidence, repo_root, objects):
    if objects is None:
        raise ValueError("firmware requires --objects with native PPC C products")
    driver = repo_root / ref.DRIVER
    contract = audit_data_accounting(evidence, repo_root)
    manifest = load_json(objects / "objects.json")
    if (manifest.get("configuration") != "RELEASE_PPC" or manifest.get("hash_algorithm") != "SHA-256" or
            not re.fullmatch(r"[0-9a-fA-F]{40}", manifest.get("source_revision", ""))):
        raise ValueError("invalid firmware native provenance")
    expected_sources = ["bsd/dev/ppc/drvAdaptecU2SCSI/" + n for n in
                        ("AdaptecU2CHIMFirmware.c", "AdaptecU2CHIMTables.c")]
    if [e["source"] for e in manifest["objects"]] != expected_sources:
        raise ValueError("firmware requires exactly both owning production C objects")
    headers = {}
    for line in (objects / "header-inputs.sha256").read_text().splitlines():
        digest, path = line.split(maxsplit=1)
        name = Path(path).name
        if path != "bsd/dev/ppc/drvAdaptecU2SCSI/" + name or name in headers:
            raise ValueError("invalid native firmware header input")
        headers[name] = digest
    if set(headers) != {"AdaptecU2CHIMTypes.h", "AdaptecU2CHIM.h", "AdaptecU2CHIMPrivate.h", "OSMFunctions.h"}:
        raise ValueError("incomplete firmware header closure")
    for name, digest in headers.items():
        if hashlib.sha256((driver/name).read_bytes()).hexdigest().upper() != digest.upper():
            raise ValueError("stale firmware target header: " + name)
    for entry in manifest["objects"]:
        name = Path(entry["source"]).name
        if entry["path"] != Path(entry["path"]).name or entry["cpu_type"] != 18:
            raise ValueError("invalid firmware object path/CPU")
        obj = objects / entry["path"]
        for path, digest in [(obj,entry["sha256"]), (driver/name,entry["source_sha256"])]:
            if hashlib.sha256(path.read_bytes()).hexdigest().upper() != digest.upper():
                raise ValueError("stale firmware native source/object: " + path.name)
        if any("warning:" in line or "error:" in line for line in (objects/entry["log"]).read_text().splitlines()):
            raise ValueError("firmware native compilation diagnostic: " + name)
        payload, macho = load_image(obj)
        if (macho["input"]["architecture"],macho["input"]["endianness"]) != ("ppc","big"):
            raise ValueError("firmware native object must be big-endian PPC")
        symbols = {s["name"]:s for s in macho["symbols"] if s["binding"] == "external" and s["section"]}
        owned = [d for d in contract["objects"] if d["owner"] == name]
        if {s for s in symbols if not s.startswith("L")} != {"_"+d["name"] for d in owned}:
            raise ValueError("firmware native owning symbol set differs: " + name)
        for record in owned:
            compare_firmware_data(record, evidence["data"][record["name"]], payload, macho, symbols)


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
