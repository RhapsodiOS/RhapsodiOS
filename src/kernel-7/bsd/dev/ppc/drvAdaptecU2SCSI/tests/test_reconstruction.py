"""Reference inventory checks; reconstruction acceptance is added by stage."""

import copy
import importlib.util
import json
import os
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
