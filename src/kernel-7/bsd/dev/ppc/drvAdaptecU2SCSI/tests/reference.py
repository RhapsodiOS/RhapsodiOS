"""Extract the pinned Ultra2 reference without parsing unrelated ObjC modules."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

from binrecon.identity import identify, verify_expected
from binrecon.macho import load_image
from binrecon.objc_abi import ObjcReader, method_symbol_index, read_categories, read_classes
from binrecon.schema import load_json, validate_analysis_semantics, validate_document


SHA256 = "D01D748C10117FBFCEB25F99D88A63895C3BAC6C09A5110AD358E583316494BD"
SIZE = 2983828
RANGES = [[0x18770c, 0x18b754], [0x18b754, 0x1a8adc]]
DRIVER = Path("src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI")
OWNER_COUNTS = dict(zip((
    "AdaptecU2CHIMSCB.c", "AdaptecU2CHIMConfig.c", "AdaptecU2CHIMRecovery.c",
    "AdaptecU2CHIMNegotiation.c", "AdaptecU2CHIMHardware.c", "AdaptecU2CHIMHIM.c",
    "AdaptecU2CHIMResource.c", "AdaptecU2CHIMTransport.c", "AdaptecU2CHIMOSD.c",
    "AdaptecU2CHIMAPI.c",
), (67, 20, 28, 63, 61, 31, 47, 19, 14, 42)))
UNNAMED = [0x189120, 0x18914c, 0x189174, 0x18918c, 0x1891a0, 0x1891b0, 0x18b2a8]
EXTERNAL_PROVIDERS = {
    "_bzero": "src/kernel-7/machdep/ppc/bcopy.s",
    "_memset": "src/kernel-7/machdep/ppc/bcopy.s",
    "_memcpy": "src/kernel-7/machdep/ppc/bcopy.s",
    "_fast_bcopy": "src/kernel-7/machdep/ppc/bcopy.s",
    "_flush_cache": "src/kernel-7/machdep/ppc/cache.s",
    "_kalloc": "src/kernel-7/kern/kalloc.c",
    "_kfree": "src/kernel-7/kern/kalloc.c",
    "_ns_timeout": "src/kernel-7/kern/ns_timer.c",
    "_thread_call_func": "src/kernel-7/kern/thread_call.c",
    "_msg_send_from_kernel": "src/kernel-7/kern/ipc_mig.c",
    "_task_self": "src/kernel-7/kern/ipc_tt.c",
    "_port_set_backlog_EXTERNAL": "src/kernel-7/ipc/mach_port.c",
    "_pmap_add_physical_memory": "src/kernel-7/machdep/ppc/pmap.c",
    "_objc_msgSend": "src/objc-1/objc-msg-ppc.s",
    "_objc_msgSendSuper": "src/objc-1/objc-msg-ppc.s",
}
for _name in ("IOMalloc", "IOFree", "IOScheduleFunc", "IOUnscheduleFunc",
              "IOGetTimestamp", "IOLog", "IOPanic", "IOFindNameForValue"):
    EXTERNAL_PROVIDERS["_" + _name] = "src/driverkit-3/libDriver/Kernel/generalFuncs.m"
for _name in ("IOExitThread", "IOVmTaskSelf", "IOConvertPort", "IOPhysicalFromVirtual",
              "IOMapPhysicalIntoIOTask", "IOUnmapPhysicalFromIOTask"):
    EXTERNAL_PROVIDERS["_" + _name] = "src/driverkit-3/libDriver/Kernel/generalFuncsPrivate.m"
PUBLIC_DATA = [
    ("request_message", 0x27803c, 0x278054, "AdaptecU2SCSI.m"),
    ("OSMRoutines", 0x278054, 0x2780d0, "OSMFunctions.m"),
    ("adapterQ", 0x2780d0, 0x2782d0, "AdaptecU2SCSI.m"),
    ("diagnostic_strings", 0x2782d0, 0x278c7c, "OSMFunctions.m"),
    ("SCSIHardwareAIC78XX", 0x278c7c, 0x278cf4, "AdaptecU2CHIMTables.c"),
    ("SCSIHardwareAICBayonet", 0x278cf4, 0x278d6c, "AdaptecU2CHIMTables.c"),
    ("SCSIHardware", 0x278d6c, 0x278d78, "AdaptecU2CHIMTables.c"),
    ("Seq_s64", 0x278d78, 0x279548, "AdaptecU2CHIMFirmware.c"),
    ("Seq_w32", 0x279548, 0x279c34, "AdaptecU2CHIMFirmware.c"),
    ("Seq_sAdv", 0x279c34, 0x27a44c, "AdaptecU2CHIMFirmware.c"),
    ("Seq_wAdv", 0x27a44c, 0x27ad1c, "AdaptecU2CHIMFirmware.c"),
    ("SCSIFirmwareStandard64", 0x27ad1c, 0x27ae44, "AdaptecU2CHIMTables.c"),
    ("SCSIFirmwareSwapping32", 0x27ae44, 0x27af6c, "AdaptecU2CHIMTables.c"),
    ("SCSIFirmwareStandardAdv", 0x27af6c, 0x27b094, "AdaptecU2CHIMTables.c"),
    ("SCSIFirmwareSwappingAdv", 0x27b094, 0x27b1bc, "AdaptecU2CHIMTables.c"),
    ("SCSIFirmware", 0x27b1bc, 0x27b1d8, "AdaptecU2CHIMTables.c"),
    ("SCSIHostType", 0x27b1d8, 0x27b318, "AdaptecU2CHIMTables.c"),
    ("SCSISubSystemSubVendorType", 0x27b318, 0x27b398, "AdaptecU2CHIMTables.c"),
    ("SCSIFuncPtrs", 0x27b398, 0x27b440, "AdaptecU2CHIMTables.c"),
    ("SCSIConfiguration", 0x27b440, 0x27b484, "AdaptecU2CHIMTables.c"),
    ("SCSIDefaultAdapterProfile", 0x27b484, 0x27b654, "AdaptecU2CHIMTables.c"),
    ("SCSIAdjustableAdapterProfile", 0x27b654, 0x27b824, "AdaptecU2CHIMTables.c"),
    ("SCSIDefaultTargetProfile", 0x27b824, 0x27b8a0, "AdaptecU2CHIMTables.c"),
    ("SCSIAdjustableTargetProfile", 0x27b8a0, 0x27b91c, "AdaptecU2CHIMTables.c"),
    ("SCSIscontrol", 0x27b91c, 0x27b924, "AdaptecU2CHIMTables.c"),
    ("event_names", 0x230ca0, 0x230ce0, "OSMFunctions.m"),
]
SWITCHES = [
    (0x230ce0, 28), (0x230cfc, 320), (0x230e3c, 84), (0x230e90, 48),
    (0x230ec0, 20), (0x230ed4, 32), (0x230ef4, 40), (0x230f1c, 36),
    (0x230f40, 32), (0x230f60, 32), (0x230f80, 32), (0x230fa0, 48),
    (0x230fd0, 76), (0x23101c, 292), (0x231140, 164), (0x2311e4, 116),
    (0x231258, 44), (0x231284, 292), (0x2313a8, 164), (0x23144c, 116),
    (0x2314c0, 32), (0x2314e0, 320),
]


def frozen_functions(repo_root):
    text = (repo_root / DRIVER / "reconstruction/inventory.md").read_text(encoding="utf-8")
    block = text.split("<!-- functions:start -->")[1].split("<!-- functions:end -->")[0]
    rows = re.findall(r"^\| (0x[0-9a-f]+) \| (0x[0-9a-f]+) \| `([^`]+)` \| `([^`]+)` \|$", block, re.M)
    return {int(a, 16): {"address": int(a, 16), "size": int(b, 16)-int(a, 16),
                            "names": [name], "owner": owner} for a, b, name, owner in rows}


def owner_of(function, methods):
    address = function["address"]
    name = function["names"][0].removeprefix("_")
    if address < 0x18b754:
        method = next((m for m in methods if m["address"] == address), None)
        if method:
            return "AdaptecU2SCSIThread.m" if method["category"] else "AdaptecU2SCSI.m"
        if address in UNNAMED[:6] or name.startswith("Adpt") or (name.startswith("OSM") and name != "OSMEvent"):
            return "AdaptecU2OSMServices.m"
        return "OSMFunctions.m"
    if name.startswith("SCSIh"):
        for end, owner in zip((0x1922a8, 0x193bb8, 0x198100, 0x19cb3c, 0x1a245c), list(OWNER_COUNTS)[:5]):
            if address < end:
                return owner
    for prefix, owner in (("SCSIH", "HIM"), ("SCSIr", "Resource"),
                          ("SCSIx", "Transport"), ("OSD", "OSD")):
        if name.startswith(prefix):
            return "AdaptecU2CHIM" + owner + ".c"
    if re.match(r"SCSIR[A-Z]", name):
        return "AdaptecU2CHIMResource.c"
    if name.startswith("SCSI"):
        return "AdaptecU2CHIMAPI.c"
    raise ValueError(f"unknown owner at 0x{address:x}: {name}")


def targeted_metadata(payload, macho):
    reader = ObjcReader(payload, macho["sections"], "big", method_symbol_index(macho))
    info = next(s for s in macho["sections"] if s["name"] == "__OBJC,__module_info")
    modules, methods = {}, []
    for address in range(info["address"], info["address"] + info["size"], 16):
        _, _, name, symtab = reader.at(address, 4)
        module = reader.cstring(name)
        if module not in ("AdaptecU2SCSI.m", "AdaptecU2SCSIThread.m", "OSMFunctions.m"):
            continue
        modules[module] = {"classes": read_classes(reader, symtab), "categories": read_categories(reader, symtab)}
        cc, nc = reader.halves(symtab + 8, 2)
        for index, pointer in enumerate(reader.at(symtab + 12, cc + nc)):
            if index < cc:
                klass = reader.at(pointer, 8)
                owner, category = reader.cstring(klass[2]), None
                lists = [("-", klass[7]), ("+", reader.at(klass[0], 8)[7])]
            else:
                cat, klass, instance, class_methods = reader.at(pointer, 4)
                category = reader.cstring(cat)
                owner = f"{reader.cstring(klass)}({category})"
                lists = [("-", instance), ("+", class_methods)]
            for sign, method_list in lists:
                if not method_list:
                    continue
                _, count = reader.at(method_list, 2)
                for i in range(count):
                    selector, types, imp = reader.at(method_list + 8 + i * 12, 3)
                    methods.append({"address": imp, "name": f"{sign}[{owner} {reader.selector(selector, imp)}]",
                                    "types": reader.cstring(types), "category": category, "module": module})
    return modules, sorted(methods, key=lambda m: m["address"])


def validate_partition(functions, frozen):
    actual = {f["address"]: f for f in functions}
    if set(actual) != set(frozen):
        missing, extra = sorted(set(frozen)-set(actual)), sorted(set(actual)-set(frozen))
        raise ValueError(f"inventory partition missing {[hex(a) for a in missing]}, unexpected {[hex(a) for a in extra]}")
    if len(actual) != len(functions) or len(actual) != 476:
        raise ValueError("inventory partition has duplicate or incorrect body count")
    for address, expected in frozen.items():
        found = actual[address]
        if found["size"] != expected["size"] or found["names"] != expected["names"]:
            raise ValueError(f"inventory boundary/name differs at 0x{address:x}")
    for start, end in RANGES:
        bodies = sorted((f for f in functions if start <= f["address"] < end), key=lambda f: f["address"])
        cursor = start
        for body in bodies:
            if body["address"] != cursor or body["size"] <= 0 or body["size"] % 4:
                raise ValueError(f"inventory disputed boundary at 0x{body['address']:x}")
            cursor += body["size"]
        if cursor != end:
            raise ValueError(f"inventory range end differs at 0x{cursor:x}")


def external_dependencies(analysis):
    symbols = {s["address"]: s["name"] for s in analysis["symbols"]}
    sites = {}
    for ref in analysis["references"]:
        target = ref["target"]
        if ref["kind"] == "code" and target is not None and not 0x18770c <= target < 0x1a8adc:
            sites.setdefault(target, []).append(ref["address"])
    result = []
    for target, callers in sorted(sites.items()):
        name = symbols.get(target)
        if name not in EXTERNAL_PROVIDERS:
            raise ValueError(f"external provider missing for {name} at 0x{target:x}")
        result.append({"address": target, "name": name, "provider": EXTERNAL_PROVIDERS[name],
                       "call_sites": sorted(callers)})
    return result


def extract_reference(binary: Path, analysis: Path, output: Path) -> dict:
    identity = identify(binary)
    verify_expected(identity, SIZE, SHA256)
    payload, macho = load_image(binary)
    if (macho["input"]["architecture"], macho["input"]["endianness"]) != ("ppc", "big"):
        raise ValueError("reference identity is not PPC/big-endian")
    document = load_json(analysis)
    validate_document("analysis-v1", document)
    validate_analysis_semantics(document)
    if document["input"] != macho["input"] or document["analyzer"]["name"] != "IDA":
        raise ValueError("analysis identity does not match reference")
    functions = document["functions"]
    repo_root = Path(__file__).resolve().parents[7]
    frozen = frozen_functions(repo_root)
    validate_partition(functions, frozen)
    modules, methods = targeted_metadata(payload, macho)
    owners = {}
    for function in functions:
        owner = owner_of(function, methods)
        if frozen[function["address"]]["owner"] != owner:
            raise ValueError(f"inventory owner differs at 0x{function['address']:x}")
        owners.setdefault(owner, []).append(function["address"])
    reader = ObjcReader(payload, macho["sections"], "big")
    data = list(PUBLIC_DATA)
    for address, size in SWITCHES:
        caller = next(r["address"] for r in document["references"]
                      if r["kind"] == "data" and r["target"] == address)
        containing = next(f for f in functions if f["address"] <= caller < f["address"]+f["size"])
        data.append((f"switch_{address:x}", address, address+size, owner_of(containing, methods)))
    output.mkdir(parents=True, exist_ok=True)
    (output / "data").mkdir(exist_ok=True)
    records = []
    for name, start, end, owner in data:
        offset = reader.offset_of(start)
        if offset is None or reader.offset_of(end-1) != offset+end-start-1:
            raise ValueError(f"unbacked data object {name} at 0x{start:x}")
        raw = payload[offset:offset+end-start]
        path = "data/" + name + ".bin"
        (output / path).write_bytes(raw)
        records.append({"name": name, "address": start, "size": len(raw), "owner": owner,
                        "path": path, "sha256": hashlib.sha256(raw).hexdigest().upper()})
    result = {"identity": macho["input"], "analyzer": document["analyzer"], "ranges": RANGES,
              "analysis_sha256": identify(analysis).sha256, "functions": functions, "owners": owners,
              "methods": methods, "unnamed_helpers": UNNAMED, "boundary_disputes": [], "data": records,
              "external_dependencies": external_dependencies(document)}
    shutil.copyfile(binary, output / "image.bin")
    shutil.copyfile(analysis, output / "analysis.json")
    for name, value in (("reference.json", result), ("abi.json", {"identity": macho["input"], "modules": modules})):
        (output / name).write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True, type=Path)
    parser.add_argument("--analysis", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = extract_reference(args.binary, args.analysis, args.output)
    print(f"extracted {len(result['functions'])} bodies, {len(result['methods'])} methods, {len(result['data'])} data objects")


if __name__ == "__main__":
    main()
