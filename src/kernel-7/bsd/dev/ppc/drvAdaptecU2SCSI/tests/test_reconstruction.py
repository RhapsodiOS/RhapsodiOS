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


def test_task6_owner_native_and_control_flow_evidence(firmware_evidence):
    audit, evidence = firmware_evidence
    audit.audit_hardware_group(evidence, REPO, OUT / "objects/task6")


@pytest.mark.parametrize("corruption", ["source", "review", "ledger", "case", "unknown_call",
                                        "switch_guard", "switch_target", "executed_cases",
                                        "executed_contracts", "executed_runner", "dependency_source",
                                        "dependency_object", "result_revision", "executed_reference",
                                        "executed_inventory", "executed_initializer", "executed_identity",
                                        "executed_macho", "executed_objc_abi", "executed_source_map",
                                        "executed_schema", "executed_arch", "executed_source_paths"])
def test_task6_owner_rejects_incomplete_evidence(tmp_path, firmware_evidence, corruption):
    audit, evidence = firmware_evidence
    repo = tmp_path / "repo"
    driver = repo / audit.ref.DRIVER
    shutil.copytree(TESTS.parent, driver, ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copytree(REPO / "tools/binrecon/binrecon", repo / "tools/binrecon/binrecon",
                    ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copyfile(REPO / "tools/binrecon/source_paths.py", repo / "tools/binrecon/source_paths.py")
    shutil.copyfile(REPO / ".git", repo / ".git")
    objects = tmp_path / "objects/task6"
    shutil.copytree(OUT / "objects/task6", objects,
                    ignore=shutil.ignore_patterns("*.id0", "*.id1", "*.nam", "*.til", "*.i64"))
    for dependency in ("task5", "firmware"):
        shutil.copytree(OUT / "objects" / dependency, objects.parent / dependency,
                        ignore=shutil.ignore_patterns("*.id0", "*.id1", "*.nam", "*.til", "*.i64"))
    shutil.copytree(OUT / "objects/layout-checks", objects.parent / "layout-checks")
    proof_path = driver / "reconstruction/task6.json"
    proof = json.loads(proof_path.read_text())
    body = next(body for body in proof["bodies"] if body["address"] == 0x1a1118)
    ledger_path = driver / "reconstruction/ledger.json"
    ledger = json.loads(ledger_path.read_text())
    if corruption == "source":
        with (driver / "AdaptecU2CHIMHardware.c").open("a") as stream:
            stream.write("\nvoid HardwareReplacement(void) {}\n")
        expected = "stale Task6 native source/object"
    elif corruption == "review":
        proof["bodies"].remove(body)
        expected = "exactly 61 hardware bodies"
    elif corruption == "ledger":
        next(entry for entry in ledger["entries"] if entry["address"] == body["address"])["status"] = "unexamined"
        expected = "reviewed body/source evidence"
    elif corruption == "case":
        body["cases"] = []
        expected = "required Task6 body fixture"
    elif corruption == "unknown_call":
        path = objects / "reference-results.json"
        result = json.loads(path.read_text())
        result["results"][0]["unknown_calls"] = ["missing_internal_CHIM"]
        path.write_text(json.dumps(result))
        expected = "invalid Task6 successful fixture"
    elif corruption == "executed_inventory":
        path = driver / "reconstruction/inventory.md"
        original = path.read_text()
        changed = original.replace("| 0x18770c |", "| 0x187708 |", 1)
        assert changed != original
        path.write_text(changed)
        expected = "stale Task6 executed input"
    elif corruption.startswith("executed_"):
        paths = {"executed_cases": driver / "tests/task6-cases.json",
                 "executed_contracts": driver / "tests/contracts.json",
                 "executed_runner": driver / "tests/ppc_cases.py",
                 "executed_reference": driver / "tests/reference.py",
                 "executed_initializer": repo / "tools/binrecon/binrecon/__init__.py",
                 "executed_source_paths": repo / "tools/binrecon/source_paths.py"}
        for module in ("identity", "macho", "objc_abi", "source_map", "schema", "arch"):
            paths["executed_" + module] = repo / ("tools/binrecon/binrecon/" + module + ".py")
        with paths[corruption].open("a") as stream:
            stream.write("\n")
        expected = "stale Task6"
    elif corruption == "dependency_source":
        with (driver / "AdaptecU2CHIMTables.c").open("a") as stream:
            stream.write("\n/* altered dependency */\n")
        expected = "stale Task6 accepted source dependency"
    elif corruption == "dependency_object":
        dependency = proof["accepted_dependencies"]["AdaptecU2CHIMTables.c"]
        path = objects.parent / dependency["group"] / dependency["object"]
        raw = bytearray(path.read_bytes())
        raw[-1] ^= 1
        path.write_bytes(raw)
        expected = "stale Task6 accepted native dependency"
    elif corruption == "result_revision":
        path = objects / "reference-results.json"
        result = json.loads(path.read_text())
        result["source_revision"] = "HEAD"
        path.write_text(json.dumps(result))
        expected = "stale Task6 execution revision"
    else:
        manifest_path = objects / "objects.json"
        manifest = json.loads(manifest_path.read_text())
        item = manifest["objects"][0]
        path = objects / item["path"]
        payload, macho = audit.load_image(path)
        payload = bytearray(payload)
        text = next(section for section in macho["sections"] if section["name"] == "__TEXT,__text")
        const = next(section for section in macho["sections"] if section["name"] == "__TEXT,__const")
        if corruption == "switch_guard":
            payload[text["offset"] + body["native_address"] + 11] ^= 1
            offset = text["offset"] + body["native_address"]
            body["native_sha256"] = audit.hashlib.sha256(payload[offset:offset+body["native_size"]]).hexdigest().upper()
            expected = "native switch normalization/guard/case outcome differs"
        else:
            payload[const["offset"]:const["offset"]+4] = payload[const["offset"]+4:const["offset"]+8]
            raw = payload[const["offset"]:const["offset"]+40]
            machine = proof["switches"]["switch_230ef4"]["machine"]
            machine["raw"] = raw.hex()
            machine["targets"] = [const["address"] + int.from_bytes(raw[i:i+4], "big", signed=True)
                                  for i in range(0, 40, 4)]
            expected = "native switch case map differs"
        # Refresh all enclosing hashes so the independent machine checks must fail.
        path.write_bytes(payload)
        item["sha256"] = audit.hashlib.sha256(payload).hexdigest().upper()
        manifest_path.write_text(json.dumps(manifest))
        proof["native_manifest_sha256"] = audit.hashlib.sha256(manifest_path.read_bytes()).hexdigest().upper()
    proof_path.write_text(json.dumps(proof))
    digest = audit.hashlib.sha256(proof_path.read_bytes()).hexdigest().upper()
    for entry in ledger["entries"]:
        for artifact in entry["artifacts"]:
            if artifact["path"].endswith("reconstruction/task6.json"):
                artifact["sha256"] = digest
    ledger_path.write_text(json.dumps(ledger))
    with pytest.raises((ValueError, FileNotFoundError), match=expected):
        audit.audit_hardware_group(evidence, repo, objects)


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
                "recovered": 24, "pending-owner-recovery": 5, "pending-owner-control-flow": 19}


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







def _task7_reference_family(family):
    assert (TESTS.parent / "AdaptecU2CHIMSCB.c").is_file(), "missing SCB queue/software-state owner bodies"
    cases = json.loads((TESTS / "task7-cases.json").read_text())
    selected = {**cases, "cases": [c for c in cases["cases"] if c["family"] == family]}
    assert selected["cases"], "missing required Task7 family fixtures"
    source = (TESTS.parent / "AdaptecU2CHIMSCB.c").read_text()
    for case in selected["cases"]:
        assert re.search(r"\b" + case["entry"] + r"\([^;]*?\)\s*\{", source), case["entry"]
    result = load_script("ppc_cases").execute(OUT / "reference/image.bin", selected,
                                           json.loads((TESTS / "contracts.json").read_text()))
    assert len(result["results"]) == len(selected["cases"])


def test_scb_queue_linkage_all_modes():
    _task7_reference_family("scb-linkage")


def test_scb_abort_search_and_bdr():
    _task7_reference_family("scb-abort")


def test_scb_exhaustion_freeze_and_reset():
    _task7_reference_family("scb-reset")


@pytest.mark.parametrize("prefix", ["basic", "busy", "queue", "reset", "search", "abort", "bdr", "freeze"])
def test_task7_reference_batch(prefix):
    cases = json.loads((TESTS / "task7-cases.json").read_text())
    selected = {**cases, "cases": [c for c in cases["cases"] if c["id"].startswith("task7-" + prefix)]}
    assert selected["cases"], "missing Task7 batch fixtures"
    source = (TESTS.parent / "AdaptecU2CHIMSCB.c").read_text()
    for case in selected["cases"]:
        assert re.search(r"\b" + case["entry"] + r"\([^;]*?\)\s*\{", source), case["entry"]
    result = load_script("ppc_cases").execute(OUT / "reference/image.bin", selected,
                                           json.loads((TESTS / "contracts.json").read_text()))
    assert len(result["results"]) == len(selected["cases"])


def test_task7_owner_native_and_control_flow_evidence(firmware_evidence):
    assert (TESTS.parent / "reconstruction/task7.json").is_file(), "missing SCB owner source/native/fixture proof"
    audit, evidence = firmware_evidence
    audit.audit_scb_group(evidence, REPO, OUT / "objects/task7")


def test_task7_long_bounded_fixture_cap_bounds(tmp_path):
    runner = load_script("ppc_cases")
    image = runner_image(tmp_path, [0x38600000, 0x4e800020])
    for limit in (0, 4000001):
        with pytest.raises(ValueError, match="instruction limit"):
            runner.run_case(image, {**smoke_case(8), "instruction_limit": limit}, {"services": {}})
    result = runner.run_case(image, {**smoke_case(8), "instruction_limit": 4000000}, {"services": {}})
    assert result["returned_to_sentinel"] is True
    assert result["instructions"] == 2


@pytest.mark.parametrize("corruption", ['source', 'native', 'native_body', 'native_relocation', 'review', 'ledger', 'case', 'unknown_call', 'executed_cases', 'executed_contracts', 'executed_runner', 'dependency_source', 'dependency_object', 'dependency_staged_hash', 'result_revision', 'executed_reference', 'executed_inventory', 'executed_initializer', 'executed_identity', 'executed_macho', 'executed_objc_abi', 'executed_source_map', 'executed_schema', 'executed_arch', 'executed_source_paths'])
def test_task7_owner_rejects_incomplete_evidence(tmp_path, firmware_evidence, corruption):
    audit, evidence = firmware_evidence
    repo = tmp_path / "repo"
    driver = repo / audit.ref.DRIVER
    shutil.copytree(TESTS.parent, driver, ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copytree(REPO / "tools/binrecon/binrecon", repo / "tools/binrecon/binrecon",
                    ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copyfile(REPO / "tools/binrecon/source_paths.py", repo / "tools/binrecon/source_paths.py")
    shutil.copyfile(REPO / ".git", repo / ".git")
    objects = tmp_path / "objects/task7"
    shutil.copytree(OUT / "objects/task7", objects,
                    ignore=shutil.ignore_patterns("*.id0", "*.id1", "*.nam", "*.til", "*.i64"))
    for dependency in ("task5", "task6", "firmware"):
        shutil.copytree(OUT / "objects" / dependency, objects.parent / dependency,
                        ignore=shutil.ignore_patterns("*.id0", "*.id1", "*.nam", "*.til", "*.i64"))
    shutil.copytree(OUT / "objects/layout-checks", objects.parent / "layout-checks")
    proof_path = driver / "reconstruction/task7.json"
    proof = json.loads(proof_path.read_text())
    body = proof["bodies"][0]
    ledger_path = driver / "reconstruction/ledger.json"
    ledger = json.loads(ledger_path.read_text())
    if corruption == "source":
        with (driver / "AdaptecU2CHIMSCB.c").open("a") as stream:
            stream.write("\nvoid HardwareReplacement(void) {}\n")
        expected = "stale Task7 native source/object"
    elif corruption == "review":
        proof["bodies"].remove(body)
        expected = "exactly 67 SCB bodies"
    elif corruption == "ledger":
        next(entry for entry in ledger["entries"] if entry["address"] == body["address"])["status"] = "unexamined"
        expected = "reviewed body/source evidence"
    elif corruption == "case":
        body["cases"] = []
        expected = "required Task7 body fixture"
    elif corruption == "unknown_call":
        path = objects / "reference-results.json"
        result = json.loads(path.read_text())
        result["results"][0]["unknown_calls"] = ["missing_internal_CHIM"]
        path.write_text(json.dumps(result))
        expected = "invalid Task7 successful fixture"
    elif corruption == "executed_inventory":
        path = driver / "reconstruction/inventory.md"
        original = path.read_text()
        changed = original.replace("| 0x18770c |", "| 0x187708 |", 1)
        assert changed != original
        path.write_text(changed)
        expected = "stale Task7 executed input"
    elif corruption.startswith("executed_"):
        paths = {"executed_cases": driver / "tests/task7-cases.json",
                 "executed_contracts": driver / "tests/contracts.json",
                 "executed_runner": driver / "tests/ppc_cases.py",
                 "executed_reference": driver / "tests/reference.py",
                 "executed_initializer": repo / "tools/binrecon/binrecon/__init__.py",
                 "executed_source_paths": repo / "tools/binrecon/source_paths.py"}
        for module in ("identity", "macho", "objc_abi", "source_map", "schema", "arch"):
            paths["executed_" + module] = repo / ("tools/binrecon/binrecon/" + module + ".py")
        with paths[corruption].open("a") as stream:
            stream.write("\n")
        expected = "stale Task7"
    elif corruption == "dependency_source":
        with (driver / "AdaptecU2CHIMTables.c").open("a") as stream:
            stream.write("\n/* altered dependency */\n")
        expected = "stale Task7 accepted source dependency"
    elif corruption == "dependency_object":
        dependency = proof["accepted_dependencies"]["AdaptecU2CHIMTables.c"]
        path = objects.parent / dependency["group"] / dependency["object"]
        raw = bytearray(path.read_bytes())
        raw[-1] ^= 1
        path.write_bytes(raw)
        expected = "stale Task7 accepted native dependency"
    elif corruption == "dependency_staged_hash":
        proof["accepted_dependencies"]["AdaptecU2CHIMFirmware.c"]["source_sha256"] = "0" * 64
        expected = "stale Task7 accepted native dependency"
    elif corruption == "result_revision":
        path = objects / "reference-results.json"
        result = json.loads(path.read_text())
        result["source_revision"] = "HEAD"
        path.write_text(json.dumps(result))
        expected = "stale Task7 execution revision"
    elif corruption == "native":
        item = json.loads((objects / "objects.json").read_text())["objects"][0]
        path = objects / item["path"]
        payload = bytearray(path.read_bytes())
        payload[-1] ^= 1
        path.write_bytes(payload)
        expected = "stale Task7 native source/object"
    elif corruption == "native_body":
        body["native_sha256"] = "0" * 64
        expected = "Task7 native body differs"
    else:
        body["native_external_relocations"] = [{"address": 0, "kind": "wrong", "target": "wrong"}]
        expected = "Task7 native call binding differs"
    proof_path.write_text(json.dumps(proof))
    digest = audit.hashlib.sha256(proof_path.read_bytes()).hexdigest().upper()
    for entry in ledger["entries"]:
        for artifact in entry["artifacts"]:
            if artifact["path"].endswith("reconstruction/task7.json"):
                artifact["sha256"] = digest
    ledger_path.write_text(json.dumps(ledger))
    with pytest.raises((ValueError, FileNotFoundError), match=expected):
        audit.audit_scb_group(evidence, repo, objects)


def test_task7_proof_artifact_survives_git_checkout():
    import hashlib
    import subprocess
    relative = (TESTS.parent / "reconstruction/task7.json").relative_to(REPO).as_posix()
    committed = subprocess.check_output(["git", "show", "HEAD:" + relative], cwd=REPO)
    expected = hashlib.sha256(committed).hexdigest().upper()
    ledger = json.loads((TESTS.parent / "reconstruction/ledger.json").read_text())
    artifacts = [artifact for entry in ledger["entries"] for artifact in entry["artifacts"]
                 if artifact["path"] == relative]
    assert len(artifacts) == 67
    assert {artifact["sha256"] for artifact in artifacts} == {expected}


@pytest.mark.parametrize("newline", [b"\n", b"\r\n"], ids=["git-lf", "checkout-crlf"])
def test_task7_owner_accepts_proof_and_dependency_checkout_endings(tmp_path, firmware_evidence, newline):
    audit, evidence = firmware_evidence
    repo = tmp_path / "repo"
    driver = repo / audit.ref.DRIVER
    shutil.copytree(TESTS.parent, driver, ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copytree(REPO / "tools/binrecon/binrecon", repo / "tools/binrecon/binrecon",
                    ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copyfile(REPO / "tools/binrecon/source_paths.py", repo / "tools/binrecon/source_paths.py")
    shutil.copyfile(REPO / ".git", repo / ".git")
    objects = tmp_path / "objects/task7"
    for group in ("task7", "task5", "task6", "firmware", "layout-checks"):
        shutil.copytree(OUT / "objects" / group, objects.parent / group,
                        ignore=shutil.ignore_patterns("*.id0", "*.id1", "*.nam", "*.til", "*.i64"))
    proof_path = driver / "reconstruction/task7.json"
    relative = proof_path.relative_to(repo).as_posix()
    import subprocess
    canonical = subprocess.check_output(["git", "show", "HEAD:" + relative], cwd=REPO)
    assert b"\r" not in canonical
    proof_path.write_bytes(canonical.replace(b"\n", newline))
    proof = json.loads(canonical)
    for name in proof["accepted_dependencies"]:
        path = driver / name
        canonical = subprocess.check_output(["git", "show", "HEAD:" + path.relative_to(repo).as_posix()], cwd=REPO)
        assert b"\r" not in canonical
        path.write_bytes(canonical.replace(b"\n", newline))
    audit.audit_scb_group(evidence, repo, objects)


def test_task7_osm_reconciliation_removes_only_two_drafts():
    import subprocess
    relative = (TESTS.parent / "OSMFunctions.m").relative_to(REPO).as_posix()
    base = subprocess.check_output(["git", "show", "1199db0bfd6eab10517bad8903fd1866b7dd72f7:" + relative], cwd=REPO)
    start = base.index(b"/*\n * Forward declarations for SCSI hardware interface functions\n")
    signature = base.index(b"void _SCSIhDeliverScb(", start)
    end = base.index(b"\n}\n", signature) + len(b"\n}\n")
    removed = base[start:end]
    assert re.findall(rb"^void (_SCSIh\w+)\([^;]*?\)\s*\{", removed, re.M) == [
        b"_SCSIhSwapping32PatchXferOpt", b"_SCSIhDeliverScb"]
    assert b"void _OSDBuildSCB(" in removed and b"void _OSMWriteSCB8Words(" in removed
    current = (TESTS.parent / "OSMFunctions.m").read_bytes().replace(b"\r\n", b"\n")
    assert current == base[:start] + base[end:], "OSM reconciliation changed unrelated BASE text"
    for name in ("_OSDBuildSCB", "_OSMWriteSCB8Words", "_SCSIhSwapping32PatchXferOpt", "_SCSIhDeliverScb"):
        assert name.encode() not in current
    owner = (TESTS.parent / "AdaptecU2CHIMSCB.c").read_text()
    for name in ("SCSIhSwapping32PatchXferOpt", "SCSIhDeliverScb"):
        assert len(re.findall(r"^void " + name + r"\([^;]*?\)\s*\{", owner, re.M)) == 1


def test_task7_osm_lifecycle_and_callback_dependencies_preserved():
    import subprocess
    source = (TESTS.parent / "OSMFunctions.m").read_text()
    for signature in ("void _EnqueueOsmIOB(void *iob, void *targetStruct)",
                      "void _PostProbe(void *iob)", "void _ProbeTarget(id adapter, void *request)",
                      "AdaptecU2OSMFunctions OSMRoutines = {"):
        assert signature in source, "missing preserved lifecycle definition: " + signature
    assert len(re.findall(r"^(?:int|void) _PostProbe\(void \*iob\)", source, re.M)) == 2
    for name in ("AdaptecU2SCSI.m", "AdaptecU2SCSIThread.m", "OSMFunctions.h"):
        path = TESTS.parent / name
        relative = path.relative_to(REPO).as_posix()
        base = subprocess.check_output(["git", "show", "1199db0bfd6eab10517bad8903fd1866b7dd72f7:" + relative], cwd=REPO)
        assert path.read_bytes().replace(b"\r\n", b"\n") == base
    assert (TESTS.parent / "AdaptecU2SCSI.m").read_text().count("&OSMRoutines") == 2
    assert "extern AdaptecU2OSMFunctions OSMRoutines;" in (TESTS.parent / "OSMFunctions.h").read_text()
    assert "_EnqueueOsmIOB(iob, targetStruct);" in (TESTS.parent / "AdaptecU2SCSIThread.m").read_text()


def _task8_reference_family(family):
    source_path = TESTS.parent / "AdaptecU2CHIMConfig.c"
    assert source_path.is_file(), "missing hardware configuration owner bodies"
    cases = json.loads((TESTS / "task8-cases.json").read_text())
    selected = {**cases, "cases": [c for c in cases["cases"] if c["family"] == family]}
    assert selected["cases"], "missing required Task8 family fixtures"
    source = source_path.read_text()
    for case in selected["cases"]:
        entry = case["entry"]
        if entry == "SCSIHInitialize":
            assert case["id"] == "task8-extra-initialize-sequencer-failure"
            entry = "SCSIhSwappingAdvSetupSequencer"
            assert any(body["entry"] == entry for body in case["internal"])
        assert re.search(r"\b" + entry + r"\([^;]*?\)\s*\{", source), entry
    result = load_script("ppc_cases").execute(OUT / "reference/image.bin", selected,
                                           json.loads((TESTS / "contracts.json").read_text()))
    assert len(result["results"]) == len(selected["cases"])


def test_chip_mode_configuration_and_sequencer_choice():
    _task8_reference_family("configuration")


def test_hardware_initialization_failure():
    _task8_reference_family("initialization")


@pytest.mark.parametrize("names", [
    ["SCSIhGetHardwareConfiguration", "SCSIhGetIDBasedConfiguration",
     "SCSIhStandard64SetupSequencer", "SCSIhSwapping32SetupSequencer",
     "SCSIhStandardAdvSetupSequencer", "SCSIhSwappingAdvSetupSequencer",
     "SCSIhStartToRunSequencer"],
    ["SCSIhInitializeHardware", "SCSIhAIC78XXProcessAutoTerm",
     "SCSIhAICBayonetProcessAutoTerm", "SCSIhAIC78XXUpdateExtTerm",
     "SCSIhAICBayonetUpdateExtTerm"],
])
def test_task8_required_configuration_batches(names):
    source = (TESTS.parent / "AdaptecU2CHIMConfig.c").read_text()
    for name in names:
        assert re.search(r"\b" + name + r"\([^;]*?\)\s*\{", source), "missing configuration body: " + name


def test_task8_machine_input_is_separate_and_strict():
    runner = load_script("ppc_cases")
    assert hasattr(runner, "machine_inputs"), "missing bounded incoming-r28 contract"
    base = {"entry": "SCSIhInitializeHardware", "evidence": {"entry_address": 0x1931e4},
            "declaration": "void SCSIhInitializeHardware(AdaptecU2HHCB *hhcb);",
            "machine_inputs": {"r28": 0x123456a5}}
    assert runner.machine_inputs(base) == {28: 0x123456a5}
    assert runner.machine_inputs({}) == {}
    for change in ({"entry": "SCSIhGetCapability"}, {"machine_inputs": {"r27": 1}},
                   {"machine_inputs": {"r28": -1}}, {"machine_inputs": {"r28": 0x100000000}},
                   {"machine_inputs": {"r28": True}}, {"machine_inputs": []},
                   {"machine_inputs": {}}, {"evidence": {"entry_address": 0}},
                   {"declaration": "void SCSIhInitializeHardware(void);"}):
        with pytest.raises(ValueError, match="machine input"):
            runner.machine_inputs({**base, **change})


def test_task8_capability_native_control_flow():
    path = TESTS / "task8_native.py"
    assert path.is_file(), "missing actual native configuration switch execution"
    native = load_script("task8_native")
    cases = json.loads((TESTS / "task8-cases.json").read_text())
    selected = [case for case in cases["cases"] if case["entry"] == "SCSIhGetCapability"]
    assert selected
    for case in selected:
        native.run_capability(OUT / "objects/task8/1-AdaptecU2CHIMConfig.c.o",
                              OUT / "objects/task5/2-AdaptecU2CHIMOSD.c.o", case)


def test_task8_owner_native_and_control_flow_evidence(firmware_evidence):
    assert (TESTS.parent / "reconstruction/task8.json").is_file(), "missing configuration owner source/native/fixture proof"
    audit, evidence = firmware_evidence
    audit.audit_config_group(evidence, REPO, OUT / "objects/task8")


@pytest.mark.parametrize("corruption", ["source", "native", "review", "case", "runner",
                                        "dependency", "switch", "closure", "result", "relocation"])
def test_task8_owner_rejects_incomplete_evidence(tmp_path, firmware_evidence, corruption):
    audit, evidence = firmware_evidence
    repo = tmp_path / "repo"
    driver = repo / audit.ref.DRIVER
    shutil.copytree(TESTS.parent, driver, ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copytree(REPO / "tools/binrecon/binrecon", repo / "tools/binrecon/binrecon",
                    ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copyfile(REPO / "tools/binrecon/source_paths.py", repo / "tools/binrecon/source_paths.py")
    shutil.copyfile(REPO / ".git", repo / ".git")
    objects = tmp_path / "objects/task8"
    for group in ("task8", "task5", "task6", "task7", "firmware"):
        shutil.copytree(OUT / "objects" / group, objects.parent / group,
                        ignore=shutil.ignore_patterns("*.id0", "*.id1", "*.nam", "*.til", "*.i64"))
    proof_path = driver / "reconstruction/task8.json"
    proof = json.loads(proof_path.read_text())
    if corruption == "source":
        with (driver / "AdaptecU2CHIMConfig.c").open("a") as stream:
            stream.write("\nvoid ConfigReplacement(void) {}\n")
    elif corruption == "native":
        path = objects / "1-AdaptecU2CHIMConfig.c.o"
        raw = bytearray(path.read_bytes()); raw[-1] ^= 1; path.write_bytes(raw)
    elif corruption == "review":
        proof["bodies"].pop()
    elif corruption == "case":
        path = driver / "tests/task8-cases.json"
        cases = json.loads(path.read_text()); cases["cases"].pop(); path.write_text(json.dumps(cases))
    elif corruption == "runner":
        with (driver / "tests/ppc_cases.py").open("a") as stream:
            stream.write("\n# changed execution input\n")
    elif corruption == "dependency":
        with (driver / "AdaptecU2CHIMSCB.c").open("a") as stream:
            stream.write("\n# changed accepted dependency\n")
    elif corruption == "switch":
        proof["switches"].pop("switch_230e90")
    elif corruption == "closure":
        proof["execution_inputs"].pop("tools/binrecon/binrecon/__init__.py")
    elif corruption == "result":
        path = objects / "reference-results.json"
        result = json.loads(path.read_text()); result["results"][0]["unknown_calls"] = ["missing"]
        path.write_text(json.dumps(result))
    elif corruption == "relocation":
        next(b for b in proof["bodies"] if b["native_external_relocations"])["native_external_relocations"].pop()
    proof_path.write_text(json.dumps(proof))
    import hashlib
    digest = hashlib.sha256(proof_path.read_bytes().replace(b"\r\n", b"\n")).hexdigest().upper()
    ledger_path = driver / "reconstruction/ledger.json"
    ledger = json.loads(ledger_path.read_text())
    for entry in ledger["entries"]:
        for artifact in entry["artifacts"]:
            if artifact["path"].endswith("reconstruction/task8.json"):
                artifact["sha256"] = digest
    ledger_path.write_text(json.dumps(ledger))
    expected = {"source": "stale Task8 native source/object", "native": "stale Task8 native source/object",
                "review": "exactly 20 configuration bodies", "case": "stale Task8 reference result",
                "runner": "stale Task8 executed input", "dependency": "stale Task8 accepted source dependency",
                "switch": "both owned switch envelopes", "closure": "execution input closure is incomplete",
                "result": "invalid Task8 successful fixture", "relocation": "native call binding differs"}
    with pytest.raises(ValueError, match=expected[corruption]):
        audit.audit_config_group(evidence, repo, objects)


@pytest.mark.parametrize("newline", [b"\n", b"\r\n"])
def test_task8_owner_accepts_canonical_checkout(tmp_path, firmware_evidence, newline):
    audit, evidence = firmware_evidence
    repo = tmp_path / "repo"
    driver = repo / audit.ref.DRIVER
    shutil.copytree(TESTS.parent, driver, ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copytree(REPO / "tools/binrecon/binrecon", repo / "tools/binrecon/binrecon",
                    ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copyfile(REPO / "tools/binrecon/source_paths.py", repo / "tools/binrecon/source_paths.py")
    shutil.copyfile(REPO / ".git", repo / ".git")
    objects = tmp_path / "objects/task8"
    for group in ("task8", "task5", "task6", "task7", "firmware"):
        shutil.copytree(OUT / "objects" / group, objects.parent / group,
                        ignore=shutil.ignore_patterns("*.id0", "*.id1", "*.nam", "*.til", "*.i64"))
    proof_path = driver / "reconstruction/task8.json"
    proof = json.loads(proof_path.read_text())
    paths = [proof_path, driver / "tests/task8_native.py"]
    paths += [driver / name for name in set(proof["native_inputs"]) | set(proof["accepted_dependencies"])]
    paths += [repo / relative for relative in proof["execution_inputs"]]
    for path in paths:
        path.write_bytes(path.read_bytes().replace(b"\r\n", b"\n").replace(b"\n", newline))
    audit.audit_config_group(evidence, repo, objects)


def test_task8_proof_digest_matches_canonical_git():
    import hashlib
    import subprocess
    path = TESTS.parent / "reconstruction/task8.json"
    blob = subprocess.check_output(["git", "show", "HEAD:" + path.relative_to(REPO).as_posix()], cwd=REPO)
    assert path.read_bytes().replace(b"\r\n", b"\n") == blob
    digest = hashlib.sha256(blob).hexdigest().upper()
    ledger = json.loads((TESTS.parent / "reconstruction/ledger.json").read_text())
    artifacts = [artifact for entry in ledger["entries"] for artifact in entry["artifacts"]
                 if artifact["path"].endswith("reconstruction/task8.json")]
    assert len(artifacts) == 20 and {artifact["sha256"] for artifact in artifacts} == {digest}


def test_task8_fresh_git_checkout_proof(tmp_path):
    import hashlib
    import subprocess
    prefix = (TESTS.parent / "reconstruction").relative_to(REPO).as_posix() + "/"
    paths = [prefix + name for name in ("task8.json", "ledger.json")]
    subprocess.check_call(["git", "checkout-index", "--prefix=" + tmp_path.as_posix() + "/", "--", *paths], cwd=REPO)
    blob = subprocess.check_output(["git", "show", "HEAD:" + paths[0]], cwd=REPO)
    assert (tmp_path / paths[0]).read_bytes().replace(b"\r\n", b"\n") == blob
    digest = hashlib.sha256(blob).hexdigest().upper()
    ledger = json.loads((tmp_path / paths[1]).read_text())
    artifacts = [a for e in ledger["entries"] for a in e["artifacts"] if a["path"].endswith("task8.json")]
    assert len(artifacts) == 20 and {a["sha256"] for a in artifacts} == {digest}


@pytest.mark.parametrize("corruption", ["channel_write", "external_target"])
def test_task8_native_switch_rejects_wrong_execution(tmp_path, corruption):
    from binrecon.macho import load_image
    source = OUT / "objects/task8/1-AdaptecU2CHIMConfig.c.o"
    raw, image = load_image(source)
    raw = bytearray(raw)
    if corruption == "channel_write":
        text = next(s for s in image["sections"] if s["name"] == "__TEXT,__text")
        start = next(s["address"] for s in image["symbols"] if s["name"] == "_SCSIhGetCapability")
        offset = raw.index(bytes.fromhex("38000001"), text["offset"] + start)
        raw[offset:offset+4] = bytes.fromhex("38000002")
        expected = "native capability differs"
    else:
        token = b"_OSDGetHostAddress\0"
        assert raw.count(token) == 1
        raw = raw.replace(token, b"_OSDGetHostAddresX\0")
        expected = "unexpected native external dependency"
    changed = tmp_path / "changed.o"
    changed.write_bytes(raw)
    case = next(c for c in json.loads((TESTS / "task8-cases.json").read_text())["cases"]
                if c["id"] == "task8-cap-7873-2")
    with pytest.raises(ValueError, match=expected):
        load_script("task8_native").run_capability(changed, OUT / "objects/task5/2-AdaptecU2CHIMOSD.c.o", case)


def test_task8_configuration_native_narrow_accesses():
    native = load_script("task8_native")
    assert hasattr(native, "configuration_access_widths"), "missing native halfword/byte access checks"
    native.configuration_access_widths(OUT / "objects/task8/1-AdaptecU2CHIMConfig.c.o")
    native.configuration_access_widths(OUT / "reference/image.bin")


def test_task8_channel_clear_set_preserve_observed():
    cases = json.loads((TESTS / "task8-cases.json").read_text())["cases"]
    direct = [case for case in cases if case["entry"] == "SCSIhGetIDBasedConfiguration"]
    assert direct and all(any(o["region"] == "adapter" and o["offset"] == 244 and o["size"] == 4
                              for o in case["observe"]) for case in direct), "channel and neighbors are unobserved"
    focused = [case for case in direct if case["id"].startswith("task8-fix1-channel-")]
    assert {case["channel_case"] for case in focused} == {"clear", "set", "preserve"}
    native = load_script("task8_native")
    for case in focused:
        native.run_channel_case(OUT / "reference/image.bin", case)
        native.run_channel_case(OUT / "objects/task8/1-AdaptecU2CHIMConfig.c.o", case)


def test_task8_native_rejects_equivalent_word_accesses():
    import hashlib
    native = load_script("task8_native")
    assert hasattr(native, "configuration_access_widths"), "missing native narrow-store rejection"
    original = OUT / "task8/fix1/base-objects/1-AdaptecU2CHIMConfig.c.o"
    assert hashlib.sha256(original.read_bytes()).hexdigest().upper() == "9277FF2AC52E1B2606ACA670115E35B55412FDBDAA9DC5A609DBC128204E7419"
    with pytest.raises(ValueError, match="PrepareConfig narrow access footprint differs"):
        native.configuration_access_widths(original)
    cases = json.loads((TESTS / "task8-cases.json").read_text())["cases"]
    for case in [c for c in cases if c.get("channel_case") in ("clear", "set")]:
        with pytest.raises(ValueError, match="channel access footprint differs"):
            native.run_channel_case(original, case)



def _task9_reference_family(family):
    import functools
    source = TESTS.parent / "AdaptecU2CHIMNegotiation.c"
    assert source.is_file(), "missing negotiation owner bodies"
    cases = json.loads((TESTS / "task9-cases.json").read_text())
    selected = {**cases, "cases": [c for c in cases["cases"] if c["family"] == family]}
    assert selected["cases"], "missing Task9 execution family"
    text = source.read_text()
    for case in selected["cases"]:
        assert re.search(r"\b" + case["entry"] + r"\([^;]*?\)\s*\{", text), case["entry"]
    runner = load_script("ppc_cases")
    runner.load_image = functools.lru_cache(maxsize=1)(runner.load_image)
    result = runner.execute(OUT / "reference/image.bin", selected,
                            json.loads((TESTS / "contracts.json").read_text()))
    assert len(result["results"]) == len(selected["cases"])


def test_wide_sync_messages_and_responses():
    _task9_reference_family("messages")


def test_transfer_rate_option_and_offset():
    _task9_reference_family("transfer")


def test_modify_data_pointer_sg():
    _task9_reference_family("data")


@pytest.mark.parametrize("name", [
    'SCSIhNegotiate',
    'SCSIhExtMsgi',
    'SCSIhInitiateWide',
    'SCSIhVerifyWideResponse',
    'SCSIhInitiateSync',
    'SCSIhVerifySyncResponse',
    'SCSIhRespondToWide',
    'SCSIhRespondToSync',
    'SCSIhSendMessage',
    'SCSIhReceiveMessage',
    'SCSIhHandleMsgOut',
    'SCSIhHandleMsgIn',
    'SCSIhAIC78XXCalcScsiRate',
    'SCSIhAICBayonetCalcScsiRate',
    'SCSIhAIC78XXGetXferPeriod',
    'SCSIhAICBayonetGetXferPeriod',
    'SCSIhStandardGetFast20Reg',
    'SCSIhStandardAdvGetFast20Reg',
    'SCSIhSwappingGetFast20Reg',
    'SCSIhSwappingAdvGetFast20Reg',
    'SCSIhStandardClearFast20Reg',
    'SCSIhSwappingClearFast20Reg',
    'SCSIhStandardLogFast20Map',
    'SCSIhSwappingLogFast20Map',
    'SCSIhSwapping32UpdateFast20HostMem',
    'SCSIhSwapping32UpdateFast20HW',
    'SCSIhCheckSyncNego',
    'SCSIhStandardXferOptAssign',
    'SCSIhHostXferOptAssign',
    'SCSIhChkCondXferAssign',
    'SCSIhSwapping32CommonXferAssign',
    'SCSIhStandardAdvCommonXferAssign',
    'SCSIhSwappingAdvCommonXferAssign',
    'SCSIhSwapping32UpdateXferOptionHostMem',
    'SCSIhStandardAdvUpdateXferOptionHostMem',
    'SCSIhSwappingAdvUpdateXferOptionHostMem',
    'SCSIhStandardGetOption',
    'SCSIhHostGetOption',
    'SCSIhStandard64ModifyDataPtr',
    'SCSIhSwapping32ModifyDataPtr',
    'SCSIhStandardAdvModifyDataPtr',
    'SCSIhSwappingAdvModifyDataPtr',
    'SCSIhAIC78XXGetWideScsiOffset',
    'SCSIhAIC78XXGetNarrowScsiOffset',
    'SCSIhAICBayonetGetScsiOffset',
    'SCSIhAIC78XXClearScsiOffset',
    'SCSIhAICBayonetClearScsiOffset',
    'SCSIhAIC78XXWasSyncXfer',
    'SCSIhAICBayonetWasSyncXfer',
    'SCSIhAIC78XXSetDataFifoThrshDefault',
    'SCSIhAIC78XXReadDataFifoThrsh',
    'SCSIhAIC78XXUpdateDataFifoThrsh',
    'SCSIhAICBayonetSetDataFifoThrshDefault',
    'SCSIhAICBayonetReadDataFifoThrsh',
    'SCSIhAICBayonetUpdateDataFifoThrsh',
    'SCSIhSwappingClearAllFast20Reg',
    'SCSIhStandard64ClearAllFast20Reg',
    'SCSIhAIC78XXIgnoreWideResCalc',
    'SCSIhAICBayonetIgnoreWideResCalc',
    'SCSIhStandardAdvUpdateSGLength',
    'SCSIhSwappingAdvUpdateSGLength',
    'SCSIhStandardAdvUpdateSGAddress',
    'SCSIhSwappingAdvUpdateSGAddress',
])
def test_task9_required_body(name):
    source = (TESTS.parent / "AdaptecU2CHIMNegotiation.c").read_text()
    assert re.search(r"\b" + name + r"\([^;]*?\)\s*\{", source), "missing negotiation body: " + name


def test_task9_owner_native_and_control_flow_evidence(firmware_evidence):
    assert (TESTS.parent / "reconstruction/task9.json").is_file(), "missing negotiation owner source/native/fixture proof"
    audit, evidence = firmware_evidence
    audit.audit_negotiation_group(evidence, REPO, OUT / "objects/task9")


def test_task9_native_access_widths():
    native = load_script("task9_native")
    assert hasattr(native, "access_widths"), "missing native negotiation access-width checks"
    native.access_widths(OUT / "objects/task9/1-AdaptecU2CHIMNegotiation.c.o")
    native.access_widths(OUT / "reference/image.bin")


@pytest.mark.parametrize("corruption", ["source", "native", "review", "case", "runner",
                                        "dependency", "switch", "closure", "result", "relocation"])
def test_task9_owner_rejects_incomplete_evidence(tmp_path, firmware_evidence, corruption):
    audit, evidence = firmware_evidence
    repo = tmp_path / "repo"
    driver = repo / audit.ref.DRIVER
    shutil.copytree(TESTS.parent, driver, ignore=shutil.ignore_patterns("__pycache__", "task5-cases.json", "task6-cases.json", "task7-cases.json", "task8-cases.json"))
    shutil.copytree(REPO / "tools/binrecon/binrecon", repo / "tools/binrecon/binrecon",
                    ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copyfile(REPO / "tools/binrecon/source_paths.py", repo / "tools/binrecon/source_paths.py")
    shutil.copyfile(REPO / ".git", repo / ".git")
    objects = tmp_path / "objects/task9"
    for group in ("task9", "task5", "task6", "task7", "task8", "firmware"):
        shutil.copytree(OUT / "objects" / group, objects.parent / group,
                        ignore=shutil.ignore_patterns("*.id0", "*.id1", "*.nam", "*.til", "*.i64"))
    proof_path = driver / "reconstruction/task9.json"
    proof = json.loads(proof_path.read_text())
    if corruption == "source":
        with (driver / "AdaptecU2CHIMNegotiation.c").open("a") as stream:
            stream.write("\nvoid NegotiationReplacement(void) {}\n")
    elif corruption == "native":
        path = objects / "1-AdaptecU2CHIMNegotiation.c.o"
        raw = bytearray(path.read_bytes()); raw[-1] ^= 1; path.write_bytes(raw)
    elif corruption == "review":
        proof["bodies"].pop()
    elif corruption == "case":
        path = driver / "tests/task9-cases.json"
        cases = json.loads(path.read_text()); cases["cases"].pop(); path.write_text(json.dumps(cases))
    elif corruption == "runner":
        with (driver / "tests/ppc_cases.py").open("a") as stream:
            stream.write("\n# changed execution input\n")
    elif corruption == "dependency":
        with (driver / "AdaptecU2CHIMSCB.c").open("a") as stream:
            stream.write("\n# changed accepted dependency\n")
    elif corruption == "switch":
        proof["switches"].pop("switch_230ec0")
    elif corruption == "closure":
        proof["execution_inputs"].pop("tools/binrecon/binrecon/__init__.py")
    elif corruption == "result":
        path = objects / "reference-results.json"
        result = json.loads(path.read_text()); result["reference"]["results"][0]["unknown_calls"] = ["missing"]
        path.write_text(json.dumps(result))
    elif corruption == "relocation":
        next(b for b in proof["bodies"] if b["native_external_relocations"])["native_external_relocations"].pop()
    proof_path.write_text(json.dumps(proof))
    import hashlib
    digest = hashlib.sha256(proof_path.read_bytes().replace(b"\r\n", b"\n")).hexdigest().upper()
    ledger_path = driver / "reconstruction/ledger.json"
    ledger = json.loads(ledger_path.read_text())
    for entry in ledger["entries"]:
        for artifact in entry["artifacts"]:
            if artifact["path"].endswith("reconstruction/task9.json"):
                artifact["sha256"] = digest
    ledger_path.write_text(json.dumps(ledger))
    expected = {"source": "stale Task9 native source/object", "native": "stale Task9 native source/object",
                "review": "exactly 63 negotiation bodies", "case": "stale Task9 reference result",
                "runner": "stale Task9 executed input", "dependency": "stale Task9 accepted source dependency",
                "switch": "its owned switch envelope", "closure": "execution input closure is incomplete",
                "result": "invalid Task9 successful fixture", "relocation": "native call binding differs"}
    with pytest.raises(ValueError, match=expected[corruption]):
        audit.audit_negotiation_group(evidence, repo, objects)


@pytest.mark.parametrize("newline", [b"\n", b"\r\n"])
def test_task9_owner_accepts_canonical_checkout(tmp_path, firmware_evidence, newline):
    audit, evidence = firmware_evidence
    repo = tmp_path / "repo"
    driver = repo / audit.ref.DRIVER
    shutil.copytree(TESTS.parent, driver, ignore=shutil.ignore_patterns("__pycache__", "task5-cases.json", "task6-cases.json", "task7-cases.json", "task8-cases.json"))
    shutil.copytree(REPO / "tools/binrecon/binrecon", repo / "tools/binrecon/binrecon",
                    ignore=shutil.ignore_patterns("__pycache__"))
    shutil.copyfile(REPO / "tools/binrecon/source_paths.py", repo / "tools/binrecon/source_paths.py")
    shutil.copyfile(REPO / ".git", repo / ".git")
    objects = tmp_path / "objects/task9"
    for group in ("task9", "task5", "task6", "task7", "task8", "firmware"):
        shutil.copytree(OUT / "objects" / group, objects.parent / group,
                        ignore=shutil.ignore_patterns("*.id0", "*.id1", "*.nam", "*.til", "*.i64"))
    proof_path = driver / "reconstruction/task9.json"
    proof = json.loads(proof_path.read_text())
    paths = [proof_path, driver / "tests/task9_native.py"]
    paths += [driver / name for name in set(proof["native_inputs"]) | set(proof["accepted_dependencies"])]
    paths += [repo / relative for relative in proof["execution_inputs"]]
    for path in paths:
        path.write_bytes(path.read_bytes().replace(b"\r\n", b"\n").replace(b"\n", newline))
    audit.audit_negotiation_group(evidence, repo, objects)


@pytest.mark.parametrize("corruption", ["wide_store", "switch_return"])
def test_task9_native_rejects_changed_behavior(tmp_path, corruption):
    native = load_script("task9_native")
    source = OUT / "objects/task9/1-AdaptecU2CHIMNegotiation.c.o"
    name = "SCSIhAIC78XXClearScsiOffset" if corruption == "wide_store" else "SCSIhAIC78XXGetXferPeriod"
    start, end, code, image = native.body(source, name)
    words = [int.from_bytes(code[i:i+4], "big") for i in range(0, len(code), 4)]
    if corruption == "wide_store":
        index = next(i for i, word in enumerate(words) if word >> 26 == 38 and word & 0xffff == 4)
        word = (words[index] & 0x03ffffff) | (36 << 26)
    else:
        index = words.index(0x3860000c)
        word = 0x3860000d
    section = next(s for s in image["sections"] if s["name"] == "__TEXT,__text")
    offset = section["offset"] + start - section["address"] + index * 4
    raw = bytearray(source.read_bytes())
    raw[offset:offset+4] = word.to_bytes(4, "big")
    changed = tmp_path / "changed.o"
    changed.write_bytes(raw)
    if corruption == "wide_store":
        with pytest.raises(ValueError, match="byte offset access differs"):
            native.access_widths(changed)
    else:
        case = next(c for c in json.loads((TESTS / "task9-cases.json").read_text())["cases"]
                    if c["id"] == "task9-b1-period-78XX-32768-0")
        with pytest.raises(ValueError, match="scalar result differs"):
            native.run_scalar(changed, case)


def test_task9_public_result_current_head_remains_strict():
    result = json.loads((OUT / "objects/task9/reference-results.json").read_text())["reference"]
    result["source_revision"] = "0" * 40
    with pytest.raises(ValueError, match="stale result: source_revision"):
        load_script("ppc_cases").validate_result(
            result, OUT / "reference/image.bin", json.loads((TESTS / "task9-cases.json").read_text()),
            json.loads((TESTS / "contracts.json").read_text()))


def test_task9_proof_digest_matches_canonical_git():
    import hashlib
    import subprocess
    path = TESTS.parent / "reconstruction/task9.json"
    blob = subprocess.check_output(["git", "show", "HEAD:" + path.relative_to(REPO).as_posix()], cwd=REPO)
    assert path.read_bytes().replace(b"\r\n", b"\n") == blob
    digest = hashlib.sha256(blob).hexdigest().upper()
    ledger = json.loads((TESTS.parent / "reconstruction/ledger.json").read_text())
    artifacts = [artifact for entry in ledger["entries"] for artifact in entry["artifacts"]
                 if artifact["path"].endswith("reconstruction/task9.json")]
    assert len(artifacts) == 63 and {artifact["sha256"] for artifact in artifacts} == {digest}


def test_task9_fresh_git_checkout_proof(tmp_path):
    import hashlib
    import subprocess
    prefix = (TESTS.parent / "reconstruction").relative_to(REPO).as_posix() + "/"
    paths = [prefix + name for name in ("task9.json", "ledger.json")]
    subprocess.check_call(["git", "checkout-index", "--prefix=" + tmp_path.as_posix() + "/", "--", *paths], cwd=REPO)
    blob = subprocess.check_output(["git", "show", "HEAD:" + paths[0]], cwd=REPO)
    assert (tmp_path / paths[0]).read_bytes().replace(b"\r\n", b"\n") == blob
    digest = hashlib.sha256(blob).hexdigest().upper()
    ledger = json.loads((tmp_path / paths[1]).read_text())
    artifacts = [a for e in ledger["entries"] for a in e["artifacts"] if a["path"].endswith("task9.json")]
    assert len(artifacts) == 63 and {a["sha256"] for a in artifacts} == {digest}


def _task10_recovery_family(family):
    assert (TESTS.parent / "AdaptecU2CHIMRecovery.c").is_file(), "missing recovery owner bodies"
    path = TESTS / "task10-cases.json"
    assert path.is_file(), "missing recovery reference fixtures"
    cases = json.loads(path.read_text())
    selected = {**cases, "cases": [c for c in cases["cases"] if c["family"] == family]}
    assert selected["cases"], "missing recovery execution family: " + family
    runner = load_script("ppc_cases")
    contracts = json.loads((TESTS / "contracts.json").read_text())
    result = runner.execute(OUT / "reference/image.bin", selected, contracts)
    assert len(result["results"]) == len(selected["cases"])


def test_selection_parity_and_bad_sequence():
    _task10_recovery_family("interrupt")


def test_autosense_residual_and_completion():
    _task10_recovery_family("completion")


def test_active_abort_vs_completion():
    _task10_recovery_family("abort")


@pytest.mark.parametrize("name", ['SCSIhIntSrst', 'SCSIhIntIOError', 'SCSIhCheckLength', 'SCSIhCdbAbort', 'SCSIhCheckCondition', 'SCSIhBadSeq', 'SCSIhAbortTarget', 'SCSIhIntSelto', 'SCSIhIntFree', 'SCSIhParityError', 'SCSIhStandard64RequestSense', 'SCSIhSwapping32RequestSense', 'SCSIhStandardAdvRequestSense', 'SCSIhSwappingAdvRequestSense', 'SCSIhTerminateCommand', 'SCSIhSetStat', 'SCSIhBreakInterrupt', 'SCSIhStandard64ActiveAbort', 'SCSIhSwapping32ActiveAbort', 'SCSIhStandardAdvActiveAbort', 'SCSIhSwappingAdvActiveAbort', 'SCSIhSwappingRemoveActiveAbort', 'SCSIhStandardRemoveActiveAbort', 'SCSIhStandard64ResidueCalc', 'SCSIhSwapping32ResidueCalc', 'SCSIhStandardAdvResidueCalc', 'SCSIhSwappingAdvResidueCalc', 'SCSIhSwappingRemoveAbortHIOBFromNewQ'])
def test_task10_required_body(name):
    source = (TESTS.parent / "AdaptecU2CHIMRecovery.c").read_text()
    assert re.search(r"\b" + name + r"\([^;]*?\)\s*\{", source), "missing recovery body: " + name


def test_task10_native_access_widths_and_order():
    native = load_script("task10_native")
    native.access_widths(OUT / "objects/task10/1-AdaptecU2CHIMRecovery.c.o")
    native.access_widths(OUT / "reference/image.bin")


def test_task10_native_order_rejects_pre_correction_object():
    native = load_script("task10_native")
    with pytest.raises(ValueError, match="publication differs"):
        native.access_widths(OUT / "objects/task10/pre-correction.o")


def test_task10_consecutive_call_boundaries():
    path = TESTS / "task10-sequences.json"
    assert path.is_file(), "missing actual recovery call-boundary sequences"
    helper = load_script("task10_sequence")
    helper.audit(json.loads(path.read_text()), json.loads((TESTS / "task10-cases.json").read_text()))


@pytest.mark.parametrize("corruption", ["byte", "pointer"])
def test_task10_consecutive_call_boundary_rejects_corruption(corruption):
    helper = load_script("task10_sequence")
    document = json.loads((TESTS / "task10-sequences.json").read_text())
    cases = json.loads((TESTS / "task10-cases.json").read_text())
    second = next(c for c in cases["cases"] if c["id"] == document["sequences"][0]["cases"][1])
    region = next(r for r in second["memory"] if r["name"] == "hiob")
    if corruption == "byte":
        raw = bytearray.fromhex(region["bytes"])
        raw[5] ^= 1
        region["bytes"] = raw.hex()
    else:
        next(p for p in region["pointers"] if p["offset"] == 0)["value"] = {"region": "unit", "offset": 4}
    with pytest.raises(ValueError, match="boundary bytes or pointer bindings differ"):
        helper.audit(document, cases)


def test_task10_poll_counter_guards():
    native = load_script("task10_native")
    assert hasattr(native, "counter_guards"), "missing recovery poll counter/native synchronization proof"
    native.counter_guards(OUT / "objects/task10/1-AdaptecU2CHIMRecovery.c.o")


def test_task10_owner_native_and_control_flow_evidence(firmware_evidence):
    assert (TESTS.parent / "reconstruction/task10.json").is_file(), "missing recovery owner source/native/fixture proof"
    audit, evidence = firmware_evidence
    audit.audit_recovery_group(evidence, REPO, OUT / "objects/task10")


def test_task10_status_native_memory_order():
    helper = load_script("task10_native")
    cases = [c for c in json.loads((TESTS / "task10-cases.json").read_text())["cases"]
             if c["entry"] == "SCSIhSetStat"]
    assert len(helper.compare_status(OUT / "reference/image.bin",
               OUT / "objects/task10/1-AdaptecU2CHIMRecovery.c.o", cases)) == 14


def test_task10_proof_digest_matches_canonical_git(tmp_path):
    import hashlib
    import subprocess
    prefix = "src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/reconstruction/"
    proof = subprocess.check_output(["git", "show", "HEAD:"+prefix+"task10.json"], cwd=REPO)
    ledger = json.loads(subprocess.check_output(["git", "show", "HEAD:"+prefix+"ledger.json"], cwd=REPO))
    path = tmp_path / "task10.json"
    path.write_bytes(proof)
    digest = hashlib.sha256(path.read_bytes()).hexdigest().upper()
    artifacts = [a for e in ledger["entries"] if 0x193bb8 <= e["address"] < 0x198100
                 for a in e["artifacts"] if a["path"].endswith("reconstruction/task10.json")]
    assert len(artifacts) == 28 and {a["sha256"] for a in artifacts} == {digest}
    assert (TESTS.parent / "reconstruction/task10.json").read_bytes().replace(b"\r\n",b"\n") == proof
