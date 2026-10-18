"""Reference inventory checks; reconstruction acceptance is added by stage."""

import copy
import importlib.util
import json
import os
import re
import shutil
import struct
from pathlib import Path

import pytest


TESTS = Path(__file__).resolve().parent
REPO = TESTS.parents[6]
OUT = REPO / "tools/binrecon/out/adaptecu2scsi-ppc"
BINARY = Path(os.environ.get(
    "BINRECON_REFERENCE", "C:/Users/raynorpat/Downloads/test/MOSXS12v3/mach_kernel"
))
ANALYSIS = OUT / "baseline/published/analysis-reference-ida.json"
OWNER_COUNTS = {
    "AdaptecU2CHIMSCB.c": 67, "AdaptecU2CHIMConfig.c": 20,
    "AdaptecU2CHIMRecovery.c": 28, "AdaptecU2CHIMNegotiation.c": 63,
    "AdaptecU2CHIMHardware.c": 61, "AdaptecU2CHIMHIM.c": 31,
    "AdaptecU2CHIMResource.c": 47, "AdaptecU2CHIMTransport.c": 19,
    "AdaptecU2CHIMOSD.c": 14, "AdaptecU2CHIMAPI.c": 42,
}


def load_script(name):
    path = TESTS / (name + ".py")
    assert path.is_file(), f"missing inventory deliverable: {path}"
    spec = importlib.util.spec_from_file_location("au2_" + name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_target_layout_and_method_contracts(reference):
    # The audit reads the PPC object's constants and Objective-C metadata;
    # a host compiler's layout or comments in a header cannot satisfy it.
    layout_source = TESTS / "layout-checks.m"
    assert layout_source.is_file(), "missing target layout and method contract checks"
    load_script("verify").audit("layouts", reference[1], REPO,
                                OUT / "objects/layout-checks", None, None)


def test_dispatch_headers_are_not_callbacks():
    header = TESTS.parent / "AdaptecU2CHIM.h"
    assert header.is_file(), "missing typed HIM (4+41) and OSM (0+30) dispatch contracts"
    load_script("verify").audit_dispatch_headers(TESTS.parent,
                                                OUT / "reference")


def test_layout_rejects_changed_header(tmp_path):
    audit = load_script("verify")
    driver = tmp_path / "driver"
    (driver / "tests").mkdir(parents=True)
    for name in (*audit.LAYOUT_HEADERS, "tests/layout-checks.m"):
        (driver / name).write_bytes((TESTS.parent / name).read_bytes())
    objects = OUT / "objects/layout-checks"
    audit.audit_target_inputs(driver, objects)
    header = driver / "AdaptecU2CHIMTypes.h"
    header.write_text(header.read_text() + "\n/* changed after target build */\n")
    with pytest.raises(ValueError, match="stale target header: AdaptecU2CHIMTypes.h"):
        audit.audit_target_inputs(driver, objects)


@pytest.mark.parametrize("corruption", [
    "abi_identity", "abi_metadata", "manifest_identity", "function_extent",
    "owner_duplicate", "image_bytes",
])
def test_dispatch_reference_authentication(tmp_path, corruption):
    reference = tmp_path / "reference"
    shutil.copytree(OUT / "reference", reference)
    if corruption == "image_bytes":
        path = reference / "image.bin"
        raw = bytearray(path.read_bytes())
        raw[-1] ^= 1
        path.write_bytes(raw)
    else:
        path = reference / ("abi.json" if corruption.startswith("abi_") else "reference.json")
        data = json.loads(path.read_text())
        if corruption in ("abi_identity", "manifest_identity"):
            data["identity"]["sha256"] = "0" * 64
        elif corruption == "abi_metadata":
            # Dispatch previously read only HIMFunc, accepting other mixed metadata.
            data["modules"]["AdaptecU2SCSI.m"]["classes"][0]["instance_size"] += 4
        elif corruption == "function_extent":
            data["functions"][0]["size"] += 4
        else:
            owner = "AdaptecU2CHIMSCB.c"
            data["owners"][owner].append(data["owners"][owner][0])
        path.write_text(json.dumps(data))
    reason = {
        "abi_identity": "targeted ABI identity or metadata",
        "abi_metadata": "targeted ABI identity or metadata",
        "manifest_identity": "reference identity",
        "function_extent": "boundary/name",
        "owner_duplicate": "owner lists",
        "image_bytes": "identity mismatch",
    }[corruption]
    with pytest.raises(ValueError, match=reason):
        load_script("verify").audit_dispatch_headers(TESTS.parent, reference)


@pytest.mark.parametrize("corruption", [
    "abi_identity", "table_hash", "table_missing_record", "table_extent",
    "hardware_bytes", "firmware_bytes",
])
def test_layout_reference_authentication(tmp_path, corruption):
    reference = tmp_path / "reference"
    shutil.copytree(OUT / "reference", reference)
    if corruption == "abi_identity":
        path = reference / "abi.json"
        abi = json.loads(path.read_text())
        abi["identity"]["sha256"] = "0" * 64
        path.write_text(json.dumps(abi))
    else:
        import hashlib
        path = reference / "reference.json"
        manifest = json.loads(path.read_text())
        name = {"hardware_bytes": "SCSIHardwareAIC78XX",
                "firmware_bytes": "SCSIFirmwareStandard64"}.get(corruption, "OSMRoutines")
        record = next(item for item in manifest["data"] if item["name"] == name)
        table = reference / record["path"]
        raw = bytearray(table.read_bytes())
        if corruption == "table_hash":
            record["sha256"] = "0" * 64
        elif corruption == "table_missing_record":
            manifest["data"].remove(record)
        else:
            if corruption == "table_extent":
                raw += bytes(4)
                record["size"] += 4
            else:
                # Outside the old callback-only comparison windows. Also forge
                # the manifest hash so the pinned image must settle integrity.
                raw[100 if corruption == "hardware_bytes" else 0] ^= 1
            table.write_bytes(raw)
            record["sha256"] = hashlib.sha256(raw).hexdigest().upper()
        path.write_text(json.dumps(manifest))
    reason = {
        "abi_identity": "targeted ABI identity or metadata",
        "table_hash": "identity mismatch",
        "table_missing_record": "data objects missing",
        "table_extent": "data extent/owner",
        "hardware_bytes": "data bytes differ",
        "firmware_bytes": "data bytes differ",
    }[corruption]
    with pytest.raises(ValueError, match=reason):
        load_script("verify").audit("layouts", reference, REPO,
                                     OUT / "objects/layout-checks", None, None)


def test_input_erased_register_contracts():
    runner = load_script("ppc_cases")
    cases = json.loads((TESTS / "reference-cases.json").read_text())
    contracts = json.loads((TESTS / "contracts.json").read_text())
    erased = contracts.get("input_erased", {})
    assert len(erased) == 11, "missing exact eleven-entry input-erased ABI exception set"
    assert {name: item["address"] for name, item in erased.items()} == {
        "SCSISaveState": 0x1a4d78, "SCSIRestoreState": 0x1a4d84,
        "SCSIProfileNexus": 0x1a5e00, "SCSIClearNexusTSH": 0x1a5e10,
        "SCSIProfileNode": 0x1a5e20, "SCSIReportAdjustableNodeProfile": 0x1a5e30,
        "SCSIAdjustNodeProfile": 0x1a5e40, "SCSISetOSMNodeContext": 0x1a5e50,
        "SCSIhSwappingSearchExeQ": 0x1908dc, "SCSIhScamSupportCheck": 0x19cb3c,
        "SCSIHApplyDeviceTable": 0x19db7c,
    }
    declarations = "\n".join(path.read_text() for path in TESTS.parent.glob("AdaptecU2CHIM*.h"))
    unspecified = set(re.findall(r"\b(SCSI\w+)\s*\(\s*\)\s*;", declarations))
    assert unspecified == set(erased), "unspecified arguments require an exact input-erased exception"
    payload, macho = runner.load_image(OUT / "reference/image.bin")
    reader = load_script("reference").ObjcReader(payload, macho["sections"], "big")
    for item in erased.values():
        offset = reader.offset_of(item["address"])
        assert payload[offset:offset + item["size"]].hex() == item["reference_bytes"]
    selected = [case for case in cases["cases"] if case["id"].startswith("abi-erased-")]
    assert len(selected) == 22
    assert {case["entry"] for case in selected} == set(erased)
    for case in selected:
        assert len(case["arguments"]) == 8
        assert runner.run_case(OUT / "reference/image.bin", case, contracts)["observations"] == case["expected"]


def test_osm_erased_stack_contracts():
    runner = load_script("ppc_cases")
    cases = json.loads((TESTS / "reference-cases.json").read_text())
    contracts = json.loads((TESTS / "contracts.json").read_text())
    erased = contracts.get("osm_input_erased", {})
    assert {name: item["address"] for name, item in erased.items()} == {
        "OSMSynchronizeRange": 0x18a484,
        "OSMSaveInterruptState": 0x18a50c,
        "OSMSetInterruptState": 0x18a51c,
    }, "missing exact three-entry OSM formal-erasure set"
    header = (TESTS.parent / "OSMFunctions.h").read_text()
    assert set(re.findall(r"\b(OSM\w+)\s*\(\s*\)\s*;", header)) == set(erased)
    payload, macho = runner.load_image(OUT / "reference/image.bin")
    reader = load_script("reference").ObjcReader(payload, macho["sections"], "big")
    for item in erased.values():
        offset = reader.offset_of(item["address"])
        assert payload[offset:offset + item["size"]].hex() == item["reference_bytes"]
    selected = [case for case in cases["cases"] if case["id"].startswith("osm-erased-")]
    assert len(selected) == 6
    assert {case["entry"] for case in selected} == set(erased)
    for case in selected:
        assert len(case["arguments"]) == 8
        assert case["expected"]["stack_pointer"] == 0
        if case["entry"] == "OSMSynchronizeRange":
            assert case["observe_stack"] == [{"offset": 24, "size": 32}]
            expected_words = b"".join(value.to_bytes(4, "big") for value in case["arguments"])
            assert case["expected"]["stack"] == {"24": expected_words.hex()}
        assert runner.run_case(OUT / "reference/image.bin", case, contracts)["observations"] == case["expected"]


@pytest.fixture
def reference(tmp_path):
    extractor = load_script("reference")
    result = extractor.extract_reference(BINARY, ANALYSIS, tmp_path)
    return result, tmp_path


def test_inventory_reference_identity_and_partition(reference):
    document, output = reference
    identity = document["identity"]
    assert identity["sha256"] == "D01D748C10117FBFCEB25F99D88A63895C3BAC6C09A5110AD358E583316494BD"
    assert identity["size"] == 2983828
    assert identity["architecture"] == "ppc"
    assert identity["endianness"] == "big"
    assert document["ranges"] == [[0x18770c, 0x18b754], [0x18b754, 0x1a8adc]]
    functions = document["functions"]
    assert len(functions) == 476
    assert len({f["address"] for f in functions}) == 476
    osm = [f for f in functions if f["address"] < 0x18b754]
    chim = [f for f in functions if f["address"] >= 0x18b754]
    assert (len(osm), sum(f["size"] for f in osm)) == (84, 16456)
    assert (len(chim), sum(f["size"] for f in chim)) == (392, 119688)
    assert len(document["methods"]) == 25
    assert sum("(" in m["name"] for m in document["methods"]) == 4
    addresses = []
    for owner, count in OWNER_COUNTS.items():
        assert len(document["owners"][owner]) == count
        addresses.extend(document["owners"][owner])
    assert len(set(addresses)) == len(addresses) == 392
    assert set(addresses) == {f["address"] for f in chim}
    assert len(document["unnamed_helpers"]) == 7
    assert 0x18b2a8 in document["unnamed_helpers"]
    assert document["boundary_disputes"] == []
    load_script("verify").audit("inventory", output, REPO, None, None, None)


def test_inventory_changed_reference_and_omitted_helper_fail(reference):
    document, output = reference
    verifier = load_script("verify")
    changed = copy.deepcopy(document)
    changed["identity"]["sha256"] = "0" * 64
    (output / "reference.json").write_text(json.dumps(changed), encoding="utf-8")
    with pytest.raises(ValueError, match="identity"):
        verifier.audit("inventory", output, REPO, None, None, None)
    omitted = copy.deepcopy(document)
    omitted["functions"] = [f for f in omitted["functions"] if f["address"] != 0x18b2a8]
    (output / "reference.json").write_text(json.dumps(omitted), encoding="utf-8")
    with pytest.raises(ValueError, match="18b2a8"):
        verifier.audit("inventory", output, REPO, None, None, None)


def runner_image(tmp_path, words, base=0x1000, aliases=()):
    """Independent PPC smoke image: one linked text section and two symbols."""
    code = struct.pack(">" + "I" * len(words), *words)
    definitions = [("_smoke", 0), ("_external", 0x100)] + list(aliases)
    strings, symbols = b"\0", b""
    for name, offset in definitions:
        symbols += struct.pack(">IBBHI", len(strings), 15, 1, 0, base + offset)
        strings += name.encode("ascii") + b"\0"
    symoff = 0x1000 + len(code)
    header = struct.pack(">7I", 0xfeedface, 18, 0, 2, 2, 148, 0)
    segment = struct.pack(">2I16s8I", 1, 124, b"__TEXT", base, 0x1000,
                          0x1000, len(code), 7, 5, 1, 0)
    section = struct.pack(">16s16s9I", b"__text", b"__TEXT", base, len(code),
                          0x1000, 2, 0, 0, 0, 0, 0)
    symtab = struct.pack(">6I", 2, 24, symoff, len(definitions), symoff + len(symbols), len(strings))
    image = tmp_path / ("smoke-%x.bin" % base)
    image.write_bytes((header + segment + section + symtab).ljust(0x1000, b"\0")
                      + code + symbols + strings)
    return image


def smoke_case(size=16):
    return {"id": "independent-wrap-endian", "entry": "_smoke", "size": size,
            "arguments": [0xffffffff, {"region": "buffer", "offset": 0}],
            "memory": [{"name": "buffer", "size": 4096, "bytes": "00000000"}],
            "observe": [{"region": "buffer", "offset": 0, "size": 4}],
            "external_outcomes": [], "instruction_limit": 32,
            "evidence": {"review": "Independent addi/stw/blr PPC32 instruction semantics"},
            "expected": {"return": 0, "memory": {"buffer+0": "00000000"}, "trace": []}}


def test_task5_declared_void_ignores_undefined_r3(tmp_path):
    runner = load_script("ppc_cases")
    image = runner_image(tmp_path, [0x38601234, 0x4e800020],
                         aliases=[("_OSMAdjustBusAddress", 0)])
    case = smoke_case(8)
    case.update(entry="OSMAdjustBusAddress", return_kind="void",
                declaration="void OSMAdjustBusAddress(unsigned int *busAddress, unsigned int offset);")
    observed = runner.run_case(image, case, {"services": {}})["observations"]
    assert "return" not in observed
    assert observed["memory"] == {"buffer+0": "00000000"}
    case["declaration"] = "void OSMGetNVSize(AdaptecU2OSMContext context);"
    with pytest.raises(ValueError, match="declaration"):
        runner.run_case(image, case, {"services": {}})


def test_task5_aggregate_overflow_and_narrow_stack_arguments(tmp_path):
    runner = load_script("ppc_cases")
    # lwz r3,56(r1); lbz r4,63(r1); add r3,r3,r4; blr
    image = runner_image(tmp_path, [0x80610038, 0x8881003f, 0x7c632214, 0x4e800020],
                         aliases=[("_OSMWriteUExact8", 0)])
    case = smoke_case()
    case.update(entry="OSMWriteUExact8", return_kind="void",
                declaration="void OSMWriteUExact8(AdaptecU2IOHandle handle, unsigned int offset, unsigned char value);",
                arguments=[{"bytes": "11223344" * 8}, 0x10203040, 0xabcdef12],
                observe_stack=[{"offset": 56, "size": 8}])
    result = runner.run_case(image, case, {"services": {}})["observations"]
    assert result["stack"]["56"] == "1020304000000012"
    case["arguments"][0]["bytes"] = "11223344" * 7
    with pytest.raises(ValueError, match="aggregate"):
        runner.run_case(image, case, {"services": {}})


def test_task5_eieio_is_executed_and_traced(tmp_path):
    runner = load_script("ppc_cases")
    image = runner_image(tmp_path, [0x7c0006ac, 0x38600000, 0x4e800020])
    case = smoke_case(12)
    case["operations"] = ["eieio"]
    contracts = {"services": {}, "operations": {"eieio": {
        "evidence": "OSMWriteUExact8 reference 0x18a13c after byte store"}}}
    assert runner.run_case(image, case, contracts)["observations"]["trace"] == [{"operation": "eieio"}]
    contracts["operations"]["eieio"] = {}
    with pytest.raises(ValueError, match="operation"):
        runner.run_case(image, case, contracts)


def test_task5_reversed_store_mmio_value_matches_memory(tmp_path):
    runner = load_script("ppc_cases")
    # Unicorn's PPC write hook supplies the source value for sthbrx, before
    # the byte reversal; the register bus trace must describe stored bytes.
    sthbrx = (31 << 26) | (5 << 21) | (4 << 11) | (918 << 1)
    image = runner_image(tmp_path, [0x38a01234, sthbrx, 0x38600000, 0x4e800020])
    case = smoke_case()
    case["memory"][0]["mmio"] = "test-reversed"
    case["external_outcomes"] = [{"register": "buffer", "access": "write", "offset": 0,
                                   "size": 2, "value": 0x3412}]
    contracts = {"services": {}, "mmio": {"test-reversed": [
        {"offset": 0, "size": 2, "access": ["write"], "evidence": "independent sthbrx encoding"}]}}
    observed = runner.run_case(image, case, contracts)["observations"]
    assert observed["memory"] == {"buffer+0": "34120000"}
    assert observed["trace"][0]["value"] == 0x3412


def test_task5_void_kernel_boundary_and_symbol_pointer(tmp_path):
    runner = load_script("ppc_cases")
    image = runner_image(tmp_path, [0x7c0802a6, 0x90010008, 0x480000f9,
                                     0x80010008, 0x7c0803a6, 0x4e800020])
    case = smoke_case(24)
    case["arguments"] = [{"symbol": "_external"}]
    case["external_outcomes"] = [{"service": "_external", "arguments": ["external"]}]
    contracts = {"services": {"_external": {"boundary": "kernel-service",
        "arguments": ["pointer"], "return": "void", "evidence": "independent PPC boundary witness"}}}
    observed = runner.run_case(image, case, contracts)["observations"]
    assert observed["trace"] == [{"target": "_external", "arguments": ["external"]}]
    case["external_outcomes"][0]["return"] = 3
    with pytest.raises(ValueError, match="void"):
        runner.run_case(image, case, contracts)


def test_task5_kernel_output_parameter_is_bounded(tmp_path):
    runner = load_script("ppc_cases")
    image = runner_image(tmp_path, [0x7c0802a6, 0x90010008, 0x480000f9,
                                     0x80010008, 0x7c0803a6, 0x4e800020])
    case = smoke_case(24)
    case["arguments"] = [{"region": "buffer", "offset": 0}]
    case["external_outcomes"] = [{"service": "_external", "arguments": ["output:0"],
        "writes": [{"argument": 0, "bytes": "12345678"}], "return": 0}]
    contracts = {"services": {"_external": {"boundary": "kernel-service",
        "arguments": [{"kind": "output", "size": 4}], "return": "scalar",
        "evidence": "independent PPC caller passes four-byte output"}}}
    assert runner.run_case(image, case, contracts)["observations"]["memory"] == {"buffer+0": "12345678"}
    case["external_outcomes"][0]["writes"][0]["bytes"] += "00"
    with pytest.raises(ValueError, match="output"):
        runner.run_case(image, case, contracts)


def test_task5_internal_callback_trace_executes_body(tmp_path):
    runner = load_script("ppc_cases")
    image = runner_image(tmp_path, [0x38600027, 0x4e800020],
                         aliases=[("_OSMGetNVSize", 0)])
    case = smoke_case(8)
    case["arguments"] = [{"region": "buffer", "offset": 0}]
    case["observe_calls"] = [{"entry": "OSMGetNVSize", "size": 8,
        "arguments": [0], "declaration": "unsigned int OSMGetNVSize(AdaptecU2OSMContext context);"}]
    result = runner.run_case(image, case, {"services": {}})["observations"]
    assert result["return"] == 39
    assert result["trace"] == [{"entry": "OSMGetNVSize", "arguments": ["buffer+0"]}]
    case["observe_calls"][0]["entry"] = "_external"
    with pytest.raises(ValueError, match="callback"):
        runner.run_case(image, case, {"services": {}})


@pytest.mark.parametrize("invalid_format", ["unknown_kind", "too_many_arguments"])
def test_task5_iolog_format_selected_abi_is_validated(tmp_path, invalid_format):
    runner = load_script("ppc_cases")
    image = runner_image(tmp_path, [0x7c0802a6, 0x90010008, 0x480000f9,
                                     0x80010008, 0x7c0803a6, 0x4e800020],
                         aliases=[("_IOLog", 0x100)])
    case = smoke_case(24)
    case["memory"][0]["bytes"] = b"msg\0".hex()
    values = [0x1234, 2, 3, 4, 5, 6, 7]
    case["arguments"] = [{"region": "buffer", "offset": 0}, *values]
    case["external_outcomes"] = [{"service": "_IOLog", "arguments": ["msg", *values]}]
    contract = {"boundary": "kernel-service", "arguments": ["cstring"], "return": "void",
                "formats": {"msg": ["scalar"] * 7}, "evidence": "independent PPC IOLog caller witness"}
    contracts = {"services": {"_IOLog": contract}}
    # The selected ABI may use all eight supported argument registers.
    assert runner.run_case(image, case, contracts)["observations"]["trace"] == [
        {"target": "_IOLog", "arguments": ["msg", *values]}]
    if invalid_format == "unknown_kind":
        contract["formats"]["msg"] = ["unknown"]
        case["external_outcomes"][0]["arguments"] = ["msg", values[0]]
    else:
        # The format itself consumes r3; eight additional arguments exceed r10.
        contract["formats"]["msg"] = ["scalar"] * 8
        case["external_outcomes"][0]["arguments"] = ["msg", *values, 0]
    with pytest.raises(ValueError, match="unsupported service calling convention: _IOLog"):
        runner.run_case(image, case, contracts)


def test_task5_objc_provider_dispatch_rejects_frozen_internal_selector(tmp_path):
    runner = load_script("ppc_cases")
    image = runner_image(tmp_path, [0x7c0802a6, 0x90010008, 0x480000f9,
                                     0x80010008, 0x7c0803a6, 0x4e800020],
                         aliases=[("_objc_msgSend", 0x100)])
    case = smoke_case(24)
    case["memory"].append({"name": "selector", "size": 64, "bytes": b"deviceDescription\0".hex()})
    case["arguments"] = [{"region": "buffer", "offset": 0}, {"region": "selector", "offset": 0}]
    case["external_outcomes"] = [{"service": "_objc_msgSend", "arguments": ["buffer+0", "deviceDescription"], "return": 0}]
    dispatch = {"receiver": "buffer+0", "selector": "deviceDescription", "provider": "IODevice",
                "arguments": ["pointer", "cstring"], "return": "pointer", "evidence": "inherited kernel provider declaration"}
    contracts = {"services": {"_objc_msgSend": {"boundary": "kernel-service", "arguments": [],
        "return": "void", "dispatch": [dispatch], "evidence": "explicit provider dispatch"}}}
    assert runner.run_case(image, case, contracts)["observations"]["trace"][0]["return"] is None
    dispatch["arguments"] = ["pointer", "cstring", "unknown"]
    case["external_outcomes"][0]["arguments"].append(0)
    with pytest.raises(ValueError, match="calling convention"):
        runner.run_case(image, case, contracts)
    dispatch["arguments"] = ["pointer", "cstring"]
    case["external_outcomes"][0]["arguments"].pop()
    case["memory"][-1]["bytes"] = b"resetSCSIBus\0".hex()
    dispatch["selector"] = "resetSCSIBus"
    with pytest.raises(ValueError, match="internal.*selector"):
        runner.run_case(image, case, contracts)


def test_task5_callback_aggregate_decodes_registers_and_overflow(tmp_path):
    runner = load_script("ppc_cases")
    image = runner_image(tmp_path, [0x38600027, 0x4e800020],
                         aliases=[("_OSMReadStringUExact8", 0)])
    case = smoke_case(8)
    declaration = "void OSMReadStringUExact8(AdaptecU2IOHandle handle, unsigned int offset, unsigned char *data, unsigned int count, unsigned int strideWords);"
    handle = {"bytes": "0000000000000002" + "00" * 24,
              "pointers": [{"offset": 0, "value": {"region": "buffer", "offset": 0}}]}
    case.update(entry="OSMReadStringUExact8", declaration=declaration, return_kind="void",
                arguments=[handle, 4, {"region": "buffer", "offset": 16}, 2, 3],
                observe_calls=[{"entry": "OSMReadStringUExact8", "declaration": declaration,
                                "return_kind": "void", "arguments": [0] * 5}])
    args = runner.run_case(image, case, {"services": {}})["observations"]["trace"][0]["arguments"]
    assert args == [{"bytes": handle["bytes"], "pointers": {"0": "buffer+0", "20": None,
                                                              "24": None, "28": None}}, 4, "buffer+16", 2, 3]


def test_task5_profile_byvalue_uses_full_464_byte_extent(tmp_path):
    runner = load_script("ppc_cases")
    image = runner_image(tmp_path, [0x7c6b1b78, 0x806100a4, 0x906b0000,
                                     0x80a101e8, 0x90ab0004, 0x4e800020],
                         aliases=[("__freeOSMIOB", 0)])
    profile = bytearray(464)
    profile[136:140] = bytes.fromhex("10203040")
    profile[460:464] = bytes.fromhex("fedcba98")
    case = smoke_case(24)
    case.update(entry="__freeOSMIOB", return_kind="void",
                declaration="void _freeOSMIOB(AdaptecU2OSMIOB *iob, AdaptecU2AdapterProfile profile);",
                arguments=[{"region": "buffer", "offset": 0}, {"bytes": profile.hex()}],
                observe=[{"region": "buffer", "offset": 0, "size": 8}])
    assert runner.run_case(image, case, {"services": {}})["observations"]["memory"] == {
        "buffer+0": "10203040fedcba98"}
    case["arguments"][1]["bytes"] = profile[:-4].hex()
    with pytest.raises(ValueError, match="aggregate"):
        runner.run_case(image, case, {"services": {}})


@pytest.mark.parametrize("owner,count", [("AdaptecU2OSMServices.m", 37), ("AdaptecU2CHIMOSD.c", 14)])
def test_task5_required_owners_have_actual_bodies(owner, count):
    source = TESTS.parent / owner
    assert source.is_file(), f"missing required Task5 implementation: {owner} ({count} bodies)"
    load_script("verify").audit("group", OUT / "reference", REPO,
                                OUT / "objects/task5", None, owner)


def test_osm_access_width_endian_and_dma_boundary():
    assert (TESTS.parent / "AdaptecU2OSMServices.m").is_file(), "missing recovered OSM services"
    runner = load_script("ppc_cases")
    cases = json.loads((TESTS / "task5-cases.json").read_text())
    selected = [c for c in cases["cases"] if "-dma-" in c["id"] or "UExact" in c["entry"]]
    assert len(selected) == 78, "missing access-width/endian/allocator boundary fixtures"
    contracts = json.loads((TESTS / "contracts.json").read_text())
    for case in selected:
        assert runner.run_case(OUT / "reference/image.bin", case, contracts)["observations"] == case["expected"]


def test_osd_scb_encoding_all_modes():
    assert (TESTS.parent / "AdaptecU2CHIMOSD.c").is_file(), "missing four recovered SCB builders"
    runner = load_script("ppc_cases")
    cases = json.loads((TESTS / "task5-cases.json").read_text())
    selected = [c for c in cases["cases"] if "-scb-mode" in c["id"] or "-build-dispatch" in c["id"]]
    assert len(selected) == 36
    contracts = json.loads((TESTS / "contracts.json").read_text())
    for case in selected:
        assert runner.run_case(OUT / "reference/image.bin", case, contracts)["observations"] == case["expected"]


def test_osd_completion_status():
    assert (TESTS.parent / "AdaptecU2CHIMOSD.c").is_file(), "missing recovered normal/special completion"
    runner = load_script("ppc_cases")
    cases = json.loads((TESTS / "task5-cases.json").read_text())
    selected = [c for c in cases["cases"] if "-completion-" in c["id"] or c["id"].startswith("task5-event-")]
    assert len(selected) == 31
    contracts = json.loads((TESTS / "contracts.json").read_text())
    for case in selected:
        assert runner.run_case(OUT / "reference/image.bin", case, contracts)["observations"] == case["expected"]


def test_ppc_runner_wrap_endian_return(tmp_path):
    runner = load_script("ppc_cases")
    # addi r3,r3,1; stw r3,0(r4); li r3,0; blr
    image = runner_image(tmp_path, [0x38630001, 0x90640000, 0x38600000, 0x4e800020])
    case = smoke_case()
    result = runner.run_case(image, case, {"services": {}})
    assert result["observations"] == case["expected"]
    assert result["returned_to_sentinel"] is True
    assert result["instructions"] == 4
    case["arguments"][0] = 0x12345677
    case["expected"]["memory"]["buffer+0"] = "12345678"
    assert runner.run_case(image, case, {"services": {}})["observations"] == case["expected"]


def test_runner_unknown_call_fails(tmp_path):
    runner = load_script("ppc_cases")
    # bl _external, an uncontracted target in mapped executable memory.
    image = runner_image(tmp_path, [0x48000101, 0x4e800020])
    with pytest.raises(ValueError, match="unknown call"):
        runner.run_case(image, smoke_case(8), {"services": {}})


def test_runner_instruction_limit_fails(tmp_path):
    runner = load_script("ppc_cases")
    image = runner_image(tmp_path, [0x48000000])
    with pytest.raises(ValueError, match="instruction limit"):
        runner.run_case(image, smoke_case(4), {"services": {}})


def test_stale_result_fails(tmp_path):
    runner = load_script("ppc_cases")
    image = runner_image(tmp_path, [0x38600000, 0x4e800020])
    cases = {"cases": [smoke_case(8)]}
    contracts = {"services": {}}
    result = runner.execute(image, cases, contracts)
    runner.validate_result(result, image, cases, contracts)
    for key in ("binary_sha256", "cases_sha256", "contracts_sha256", "source_revision", "runner_version"):
        stale = copy.deepcopy(result)
        stale[key] = "stale"
        with pytest.raises(ValueError, match="stale"):
            runner.validate_result(stale, image, cases, contracts)


def test_runner_rejects_forged_sentinel(tmp_path):
    runner = load_script("ppc_cases")
    image = runner_image(tmp_path, [0x7c6903a6, 0x4e800420])  # mtctr r3; bctr
    case = smoke_case(8)
    case["arguments"] = [runner.SENTINEL]
    with pytest.raises(ValueError, match="sentinel"):
        runner.run_case(image, case, {"services": {}})


@pytest.mark.parametrize("word", [0x7c0004ac, 0x7c0006ac, 0x4c00012c, 0x7c0007ac])
def test_runner_rejects_barrier_and_cache(word, tmp_path):
    runner = load_script("ppc_cases")
    image = runner_image(tmp_path, [word, 0x4e800020])
    with pytest.raises(ValueError, match="privileged/cache/barrier"):
        runner.run_case(image, smoke_case(8), {"services": {}})


def test_runner_symbol_relocation_bss_and_scripted_service(tmp_path):
    runner = load_script("ppc_cases")
    # Save LR; call the independently relocated _external; restore LR; return.
    code = [0x7c0802a6, 0x90010008, 0x480000f9, 0x80010008, 0x7c0803a6, 0x4e800020]
    case = smoke_case(24)
    case["external_outcomes"] = [{"service": "_external", "arguments": [0xffffffff, "buffer+0"],
                                  "return": 5, "writes": [{"region": "buffer", "offset": 0, "bytes": "12345678"}]}]
    case["expected"] = {"return": 5, "memory": {"buffer+0": "12345678"},
                        "trace": [{"target": "_external", "arguments": [0xffffffff, "buffer+0"], "return": 5}]}
    contracts = {"services": {"_external": {"boundary": "kernel-service", "evidence": "independent synthetic service boundary",
                                          "arguments": ["scalar", "pointer"], "return": "scalar"}}}
    for base in (0x1000, 0x9000):
        image = runner_image(tmp_path, code, base)
        assert runner.run_case(image, case, contracts)["observations"] == case["expected"]
    image = runner_image(tmp_path, [0x80630000, 0x4e800020])  # lwz r3,0(r3); blr
    case = smoke_case(8)
    case["arguments"] = [0x1200]
    assert runner.run_case(image, case, {"services": {}})["observations"]["return"] == 0


def test_runner_reference_conversion_fixtures():
    runner = load_script("ppc_cases")
    cases = json.loads((TESTS / "reference-cases.json").read_text())
    cases["cases"] = [case for case in cases["cases"] if case["id"].endswith("-conversion")]
    contracts = json.loads((TESTS / "contracts.json").read_text())
    result = runner.execute(OUT / "reference/image.bin", cases, contracts)
    runner.validate_result(result, OUT / "reference/image.bin", cases, contracts)
    assert len(result["results"]) == 6
    assert all(item["instructions"] >= 3 for item in result["results"])


def test_runner_rejects_wrong_fixture_identity():
    runner = load_script("ppc_cases")
    cases = json.loads((TESTS / "reference-cases.json").read_text())
    contracts = json.loads((TESTS / "contracts.json").read_text())
    changed = copy.deepcopy(cases)
    changed["cases"][0]["evidence"]["reference_sha256"] = "0" * 64
    with pytest.raises(ValueError, match="fixture identity"):
        runner.execute(OUT / "reference/image.bin", changed, contracts)


def test_runner_rejects_internal_service():
    runner = load_script("ppc_cases")
    cases = json.loads((TESTS / "reference-cases.json").read_text())
    contracts = json.loads((TESTS / "contracts.json").read_text())
    contracts["services"] = {"sub_18914C": {"boundary": "kernel-service", "evidence": "invalid internal replacement",
                                          "arguments": [], "return": "scalar"}}
    with pytest.raises(ValueError, match="internal body"):
        runner.run_case(OUT / "reference/image.bin", cases["cases"][0], contracts)


@pytest.mark.parametrize("base", [0x1000, 0x9000])
@pytest.mark.parametrize("alias_source", ["reference_aliases", "image_symbols"])
def test_runner_rejects_internal_alias_outside_selected_body(tmp_path, base, alias_source):
    runner = load_script("ppc_cases")
    # Save LR, call the different internal body through its alternate name,
    # restore LR, and return. The target lies outside this selected case body.
    code = [0x7c0802a6, 0x90010008, 0x480000f9, 0x80010008, 0x7c0803a6, 0x4e800020]
    aliases = [("_sub_18914C", 0x100), ("_alternate_internal_name", 0x100)] if alias_source == "image_symbols" else []
    image = runner_image(tmp_path, code, base, aliases)
    case = smoke_case(24)
    case["external_outcomes"] = [{"service": "alternate_internal_name", "arguments": [], "return": 5}]
    contracts = {"services": {"alternate_internal_name": {
        "boundary": "kernel-service", "evidence": "synthetic forbidden internal alias",
        "arguments": [], "return": "scalar"}}}
    if alias_source == "reference_aliases":
        sha = runner.identify(image).sha256
        case["evidence"].update(reference_sha256=sha, entry_address=base)
        contracts.update(reference_sha256=sha, reference_aliases={
            "sub_18914C": base + 0x100, "alternate_internal_name": base + 0x100})
    assert "sub_18914C" in runner.DRIVER_SYMBOLS
    with pytest.raises(ValueError, match="internal body"):
        runner.run_case(image, case, contracts)


@pytest.mark.parametrize("offset", [0, 4])
def test_runner_rejects_reference_internal_alias_without_named_entry(offset):
    runner = load_script("ppc_cases")
    cases = json.loads((TESTS / "reference-cases.json").read_text())
    contracts = json.loads((TESTS / "contracts.json").read_text())
    # Remove the known unnamed helper alias. Its frozen extent still belongs
    # to the driver, including a separately named interior instruction.
    del contracts["reference_aliases"]["sub_18914C"]
    contracts["reference_aliases"]["alternate_internal_name"] = 0x18914c + offset
    contracts["services"] = {"alternate_internal_name": {
        "boundary": "kernel-service", "evidence": "synthetic forbidden reference alias",
        "arguments": [], "return": "scalar"}}
    with pytest.raises(ValueError, match="internal body"):
        runner.run_case(OUT / "reference/image.bin", cases["cases"][0], contracts)


@pytest.mark.parametrize("method_address", [0x1877c8, 0x188ab8])
def test_runner_rejects_objc_internal_alias_in_non_pinned_image(tmp_path, method_address):
    runner = load_script("ppc_cases")
    cases = json.loads((TESTS / "reference-cases.json").read_text())
    contracts = json.loads((TESTS / "contracts.json").read_text())
    # Change a valid header flag, not the code or Objective-C metadata. This
    # exercises independent class/category identities without reference bounds.
    raw = bytearray((OUT / "reference/image.bin").read_bytes())
    raw[27] ^= 1
    image = tmp_path / "non-pinned-kernel.bin"
    image.write_bytes(raw)
    sha = runner.identify(image).sha256
    assert sha != contracts["reference_sha256"]
    contracts["reference_sha256"] = sha
    cases["cases"][0]["evidence"]["reference_sha256"] = sha
    contracts["reference_aliases"]["alternate_internal_name"] = method_address
    contracts["services"] = {"alternate_internal_name": {
        "boundary": "kernel-service", "evidence": "synthetic forbidden Objective-C alias",
        "arguments": [], "return": "scalar"}}
    with pytest.raises(ValueError, match="internal body"):
        runner.run_case(image, cases["cases"][0], contracts)


@pytest.mark.parametrize("word", [0x7c602028, 0x7c60212d])
def test_runner_rejects_reservation_operations(tmp_path, word):
    runner = load_script("ppc_cases")
    image = runner_image(tmp_path, [word, 0x4e800020])
    case = smoke_case(8)
    case["arguments"] = [0, {"region": "buffer", "offset": 0}]
    with pytest.raises(ValueError, match="unsupported reservation operation"):
        runner.run_case(image, case, {"services": {}})


def test_runner_scripted_register_access_and_unknown_register(tmp_path):
    runner = load_script("ppc_cases")
    image = runner_image(tmp_path, [0x80630000, 0x4e800020])  # lwz r3,0(r3); blr
    case = smoke_case(8)
    case["arguments"] = [{"region": "registers", "offset": 0}]
    case["memory"] = [{"name": "registers", "size": 4096, "bytes": "00000000", "mmio": "synthetic-bank"}]
    case["observe"] = []
    case["external_outcomes"] = [{"register": "registers", "access": "read", "offset": 0, "size": 4, "value": 0x12345678}]
    case["expected"] = {"return": 0x12345678, "memory": {}, "trace": [
        {"target": "registers+0", "access": "read", "size": 4, "value": 0x12345678}]}
    contracts = {"services": {}, "mmio": {"synthetic-bank": [
        {"offset": 0, "size": 4, "access": ["read"], "evidence": "independent synthetic register read"}]}}
    assert runner.run_case(image, case, contracts)["observations"] == case["expected"]
    image = runner_image(tmp_path, [0x90830000, 0x38600000, 0x4e800020])  # stw r4,0(r3); li r3,0; blr
    case["size"] = 12
    case["arguments"].append(0xaabbccdd)
    case["external_outcomes"][0].update(access="write", value=0xaabbccdd)
    case["expected"]["return"] = 0
    case["expected"]["trace"][0].update(access="write", value=0xaabbccdd)
    contracts["mmio"]["synthetic-bank"][0]["access"] = ["write"]
    assert runner.run_case(image, case, contracts)["observations"] == case["expected"]
    contracts["mmio"]["synthetic-bank"][0]["offset"] = 4
    with pytest.raises(ValueError, match="unknown register"):
        runner.run_case(image, case, contracts)


def test_runner_normalizes_only_declared_pointers(tmp_path):
    runner = load_script("ppc_cases")
    image = runner_image(tmp_path, [0x90640000, 0x4e800020])  # stw r3,0(r4); blr
    case = smoke_case(8)
    case["arguments"] = [{"region": "buffer", "offset": 0}, {"region": "buffer", "offset": 0}]
    case["return_kind"] = "pointer"
    case["observe"][0]["pointer_fields"] = [0]
    result = runner.run_case(image, case, {"services": {}})
    assert result["observations"] == {"return": "buffer+0", "memory": {
        "buffer+0": {"bytes": "00000000", "pointers": {"0": "buffer+0"}}}, "trace": []}
    case["arguments"][0] = runner.REGION_BASE
    case["return_kind"] = "scalar"
    del case["observe"][0]["pointer_fields"]
    result = runner.run_case(image, case, {"services": {}})
    assert result["observations"] == {"return": runner.REGION_BASE,
                                      "memory": {"buffer+0": "70000000"}, "trace": []}
    case["return_kind"] = "pointer"
    case["observe"][0]["pointer_fields"] = [0]
    case["arguments"][0] = 0x1000
    result = runner.run_case(image, case, {"services": {}})
    assert result["observations"]["return"] == "smoke"
    assert result["observations"]["memory"]["buffer+0"]["pointers"] == {"0": "smoke"}


def test_firmware_bytes_lengths_and_selection(firmware_evidence):
    driver = TESTS.parent
    assert (driver / "AdaptecU2CHIMFirmware.c").is_file(), "missing four exact sequencer images"
    audit, evidence = firmware_evidence
    audit.audit_firmware_objects(evidence, REPO, OUT / "objects/firmware")


def test_hardware_pause_register_and_eeprom_trace():
    assert (TESTS.parent / "AdaptecU2CHIMHardware.c").is_file(), "missing hardware owner bodies"
    cases = json.loads((TESTS / "task6-cases.json").read_text())
    selected = {**cases, "cases": [c for c in cases["cases"] if c["family"] == "hardware"]}
    source = (TESTS.parent / "AdaptecU2CHIMHardware.c").read_text()
    for case in selected["cases"]:
        assert re.search(r"\b" + case["entry"] + r"\([^;]*?\)\s*\{", source), case["entry"]
    runner = load_script("ppc_cases")
    result = runner.execute(OUT / "reference/image.bin", selected,
                            json.loads((TESTS / "contracts.json").read_text()))
    assert result["results"]


def test_sequencer_download_patch_and_failure():
    assert (TESTS.parent / "AdaptecU2CHIMHardware.c").is_file(), "missing sequencer owner bodies"
    cases = json.loads((TESTS / "task6-cases.json").read_text())
    selected = {**cases, "cases": [c for c in cases["cases"] if c["family"] == "sequencer"]}
    source = (TESTS.parent / "AdaptecU2CHIMHardware.c").read_text()
    for case in selected["cases"]:
        assert re.search(r"\b" + case["entry"] + r"\([^;]*?\)\s*\{", source), case["entry"]
    runner = load_script("ppc_cases")
    result = runner.execute(OUT / "reference/image.bin", selected,
                            json.loads((TESTS / "contracts.json").read_text()))
    assert result["results"]


@pytest.mark.parametrize("prefix", ["reg4", "reg5", "reg6", "reg7", "reg8", "reg9"])
def test_task6_reference_batch(prefix):
    cases = json.loads((TESTS / "task6-cases.json").read_text())
    selected = {**cases, "cases": [c for c in cases["cases"] if c["id"].startswith("task6-" + prefix)]}
    source = (TESTS.parent / "AdaptecU2CHIMHardware.c").read_text()
    assert selected["cases"]
    for case in selected["cases"]:
        assert re.search(r"\b" + case["entry"] + r"\([^;]*?\)\s*\{", source), case["entry"]
    runner = load_script("ppc_cases")
    result = runner.execute(OUT / "reference/image.bin", selected,
                            json.loads((TESTS / "contracts.json").read_text()))
    assert len(result["results"]) == len(selected["cases"])


def test_descriptor_targets_and_profile_scalars(firmware_evidence):
    driver = TESTS.parent
    assert (driver / "AdaptecU2CHIMTables.c").is_file(), "missing symbolic descriptors and scalar/profile/device tables"
    audit, evidence = firmware_evidence
    audit.audit_firmware_objects(evidence, REPO, OUT / "objects/firmware")


@pytest.fixture(scope="module")
def firmware_evidence():
    audit = load_script("verify")
    return audit, audit.authenticate_reference(OUT / "reference", REPO)


@pytest.mark.parametrize("corruption", ["firmware_byte", "callback_target"])
def test_firmware_descriptor_rejects_changed_native_data(tmp_path, firmware_evidence, corruption):
    audit, evidence = firmware_evidence
    objects = tmp_path / "objects"
    source = OUT / "objects/firmware"
    assert source.is_dir(), "missing native firmware/table objects"
    shutil.copytree(source, objects)
    manifest = json.loads((objects / "objects.json").read_text())
    entry = manifest["objects"][0 if corruption == "firmware_byte" else 1]
    obj = objects / entry["path"]
    raw = bytearray(obj.read_bytes())
    if corruption == "firmware_byte":
        payload, macho = audit.load_image(obj)
        symbol = next(s for s in macho["symbols"] if s["name"] == "_Seq_s64")
        reader = audit.ObjcReader(payload, macho["sections"], "big")
        raw[reader.offset_of(symbol["address"]) + 17] ^= 1
    else:
        old = b"_SCSIhStandard64SetupSequencer\0"
        new = b"_SCSIhSwapping32SetupSequencer\0"
        assert len(old) == len(new) and raw.count(old) == 1
        raw = raw.replace(old, new)
    obj.write_bytes(raw)
    entry["sha256"] = audit.hashlib.sha256(raw).hexdigest().upper()
    (objects / "objects.json").write_text(json.dumps(manifest))
    with pytest.raises(ValueError, match="data bytes differ: Seq_s64" if corruption == "firmware_byte" else "pointer target differs: SCSIFirmwareStandard64"):
        audit.audit_firmware_objects(evidence, REPO, objects)


def test_firmware_final_rejects_pending_owner_data(firmware_evidence):
    audit, evidence = firmware_evidence
    with pytest.raises(ValueError, match="pending required data.*request_message"):
        audit.audit_data_accounting(evidence, REPO, final=True)


def test_firmware_reference_rejects_forged_loader_metadata(tmp_path):
    reference = tmp_path / "reference"
    shutil.copytree(OUT / "reference", reference)
    manifest = reference / "reference.json"
    document = json.loads(manifest.read_text())
    document["firmware"]["images"][0]["length"] += 4
    manifest.write_text(json.dumps(document))
    with pytest.raises(ValueError, match="firmware reference loader/selector metadata differs"):
        load_script("verify").audit("firmware", reference, REPO, OUT / "objects/firmware", None, None)

@pytest.mark.parametrize("corruption", [
    "normalized_lowcase", "normalized_case_count", "case_map", "default_target", "guard_start",
    "missing_normalized_lowcase", "missing_normalized_case_count", "missing_case_map",
    "missing_default_target", "missing_guard_start", "missing_slot", "duplicate_slot",
    "self_consistent_shift",
])
def test_firmware_switch_metadata_rejects_contradictions(tmp_path, firmware_evidence, corruption):
    audit, evidence = firmware_evidence
    document = json.loads((TESTS.parent / "reconstruction/data.json").read_text())
    switch = next(d for d in document["objects"] if d["name"] == "switch_230ce0")
    if corruption.startswith("missing_") and corruption != "missing_slot":
        del switch[corruption.removeprefix("missing_")]
    elif corruption == "normalized_lowcase":
        switch[corruption] = 1
    elif corruption == "normalized_case_count":
        switch[corruption] = 6
    elif corruption == "case_map":
        switch[corruption][0]["target"] = 0x189be0
    elif corruption == "default_target":
        switch[corruption] = 0x189be0
    elif corruption == "guard_start":
        switch[corruption] = 0x189ba0
    elif corruption == "missing_slot":
        switch["case_map"][2]["values"].remove(1)
    elif corruption == "duplicate_slot":
        switch["case_map"][2]["values"].append(1)
    else:
        switch["normalized_lowcase"] = 1
        for group in switch["case_map"]:
            group["values"] = [value + 1 for value in group["values"]]
    repo = tmp_path / "repo"
    contract = repo / "src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/reconstruction/data.json"
    contract.parent.mkdir(parents=True)
    contract.write_text(json.dumps(document))
    with pytest.raises(ValueError, match="switch metadata differs: switch_230ce0"):
        audit.audit_data_accounting(evidence, repo)


def test_firmware_switch_metadata_all_case_values(firmware_evidence):
    audit, evidence = firmware_evidence
    document = audit.audit_data_accounting(evidence, REPO)
    switches = [d for d in document["objects"] if d["name"].startswith("switch_")]
    assert len(switches) == 22
    assert sum(d["normalized_case_count"] for d in switches) == 592
    assert {status: sum(d["status"] == status for d in document["objects"])
            for status in ("recovered", "pending-owner-recovery", "pending-owner-control-flow")} == {
                "recovered": 23, "pending-owner-recovery": 5, "pending-owner-control-flow": 20}


@pytest.mark.parametrize("corruption", ["missing_source", "incorrect_source", "object", "review",
                                        "ledger", "body_case", "switch_guard", "switch_defaults"])
def test_task5_group_rejects_missing_or_incorrect_implementation(tmp_path, firmware_evidence, corruption):
    audit, evidence = firmware_evidence
    repo = tmp_path / "repo"
    driver = repo / audit.ref.DRIVER
    shutil.copytree(TESTS.parent, driver, ignore=shutil.ignore_patterns("__pycache__"))
    # Read the real producer commits from an isolated source copy; never mutate Git.
    shutil.copyfile(REPO / ".git", repo / ".git")
    objects = tmp_path / "objects/task5"
    shutil.copytree(OUT / "objects/task5", objects)
    shutil.copytree(OUT / "objects/layout-checks", objects.parent / "layout-checks")
    proof_path = driver / "reconstruction/task5.json"
    proof = json.loads(proof_path.read_text())
    ledger_path = driver / "reconstruction/ledger.json"
    ledger = json.loads(ledger_path.read_text())
    owner = "AdaptecU2CHIMOSD.c"
    review = next(b for b in proof["bodies"] if b["name"] == "_OSDAsyncEvent")
    expected = ""
    if corruption == "missing_source":
        (driver / owner).unlink()
        expected = owner
    elif corruption == "incorrect_source":
        with (driver / owner).open("ab") as stream:
            stream.write(b"\nvoid OSDMissingReplacement(void) {}\n")
        expected = "stale Task5 native source/object"
    elif corruption in ("object", "switch_guard"):
        manifest_path = objects / "objects.json"
        manifest = json.loads(manifest_path.read_text())
        item = next(i for i in manifest["objects"] if i["source"].endswith(owner))
        obj = objects / item["path"]
        raw, macho = audit.load_image(obj)
        text = next(s for s in macho["sections"] if s["name"] == "__TEXT,__text")
        raw = bytearray(raw)
        guard = proof["switches"]["switch_2314c0"]["machine"]["guard"]
        raw[text["offset"] + guard - text["address"] + 1] ^= 1
        obj.write_bytes(raw)
        expected = "stale Task5 native source/object"
        if corruption == "switch_guard":
            # Refresh every hash to prove the machine guard itself rejects a bad body.
            item["sha256"] = audit.hashlib.sha256(raw).hexdigest().upper()
            manifest_path.write_text(json.dumps(manifest))
            proof["native_manifest_sha256"] = audit.hashlib.sha256(manifest_path.read_bytes()).hexdigest().upper()
            offset = text["offset"] + review["native_address"] - text["address"]
            review["native_sha256"] = audit.hashlib.sha256(raw[offset:offset+review["native_size"]]).hexdigest().upper()
            expected = "native switch default guard differs"
    elif corruption == "review":
        proof["bodies"].remove(review)
        expected = "exactly 37\\+14 bodies"
    elif corruption == "ledger":
        next(e for e in ledger["entries"] if e["address"] == review["address"])["status"] = "unexamined"
        expected = "reviewed body/source evidence"
    elif corruption == "body_case":
        review["cases"] = []
        expected = "required successful body fixture"
    else:
        proof["switches"]["switch_2314c0"]["default_cases"] = ["unexecuted-default"]
        expected = "switch default fixtures"
    proof_path.write_text(json.dumps(proof))
    digest = audit.hashlib.sha256(proof_path.read_bytes()).hexdigest().upper()
    for entry in ledger["entries"]:
        for artifact in entry["artifacts"]:
            if artifact["path"].endswith("reconstruction/task5.json"):
                artifact["sha256"] = digest
    ledger_path.write_text(json.dumps(ledger))
    with pytest.raises((ValueError, FileNotFoundError), match=expected):
        audit.audit_service_group(evidence, repo, objects, owner)





