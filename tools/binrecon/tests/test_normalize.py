from copy import deepcopy
import json
import random

import pytest

import binrecon.normalize as normalize_module
from binrecon.normalize import MAX_FUNCTIONS, NormalizationError, normalize_analysis


HASH = "A" * 64


def analysis(name="IDA", base=0x1000):
    return {
        "schema_version": "analysis-v1",
        "input": {"path": "x", "size": 64, "sha256": HASH,
                  "architecture": "i386", "endianness": "little"},
        "analyzer": {"name": name, "version": "1", "invocation": name},
        "sections": [{"name": ".text", "address": base, "offset": 0,
                      "size": 64, "permissions": "rx", "sha256": HASH}],
        "symbols": [{"name": "callee", "address": base + 0x20,
                     "binding": "global", "section": ".text"}],
        "relocations": [{"address": base + 1, "kind": "i386-vanilla-32-pc-relative",
                         "target": "callee", "addend": -4}],
        "functions": [{
            "address": base, "size": 12, "names": ["f", "alias"],
            "blocks": [{"address": base, "size": 12,
                        "successors": [{"target": base + 8, "kind": "fallthrough"}]}],
            "instructions": [
                {"address": base, "bytes": "E878563412", "mnemonic": "call",
                 "operands": "callee", "normalized_operands": "callee",
                 "relocations": [0]},
                {"address": base + 5, "bytes": "3D78563412", "mnemonic": "cmp",
                 "operands": "eax, 0x12345678", "normalized_operands": "eax, 0x12345678",
                 "relocations": []},
                {"address": base + 10, "bytes": "E480", "mnemonic": "in",
                 "operands": "al, 0x80", "normalized_operands": "al, 0x80",
                 "relocations": []}],
            "calls": [{"address": base, "target": base + 0x20, "name": "callee"}],
            "confidence": .75}],
        "references": [{"address": base, "target": base + 0x20, "kind": "call"}],
        "extensions": {"macho": {"relocations": [
            {"address": base + 1, "target": "callee", "width": 4}]},
                       name: {"confidence_source": "native"}},
    }


def test_normalizes_only_the_exact_relocated_operand_and_preserves_semantics():
    source = analysis()
    before = deepcopy(source)
    result = normalize_analysis(source)
    instructions = result["functions"][0]["instructions"]

    assert source == before
    relocation = instructions[0]["operands"][0]["relocations"][0]
    assert instructions[0]["operands"][0]["text"] == "callee"
    assert relocation == {"field_offset": 1, "width": 4,
                          "signed": True, "kind": "i386-vanilla-32-pc-relative",
                          "target": {"kind": "section",
                                     "section": result["sections"][0]["identity"],
                                     "offset": 0x20}, "addend": -4}
    assert instructions[1]["operands"] == [
        {"text": "eax", "relocations": []},
        {"text": "0x12345678", "relocations": []}]
    assert instructions[2]["operands"] == [
        {"text": "al", "relocations": []}, {"text": "0x80", "relocations": []}]
    assert instructions[0]["bytes"] == "E878563412"
    assert instructions[0]["mnemonic"] == "call"
    assert instructions[0]["display_operands"] == "callee"
    assert instructions[0]["reference_indexes"] == [0]


def test_relocation_annotates_only_owning_operand_for_immediate_and_memory():
    document = analysis()
    instruction = document["functions"][0]["instructions"][0]
    instruction.update(bytes="B878563412", mnemonic="mov",
                       operands="eax, callee", normalized_operands="eax, callee")
    immediate = normalize_analysis(document)["functions"][0]["instructions"][0]
    assert [item["text"] for item in immediate["operands"]] == ["eax", "callee"]
    assert immediate["operands"][0]["relocations"] == []
    assert len(immediate["operands"][1]["relocations"]) == 1

    document = analysis()
    instruction = document["functions"][0]["instructions"][0]
    instruction.update(bytes="8B8078563412", mnemonic="mov",
                       operands="eax, [ebx + callee]",
                       normalized_operands="eax, [ebx + callee]")
    document["relocations"][0]["address"] = 0x1002
    document["extensions"]["macho"]["relocations"][0]["address"] = 0x1002
    memory = normalize_analysis(document)["functions"][0]["instructions"][0]
    assert [item["text"] for item in memory["operands"]] == ["eax", "[ebx + callee]"]
    assert len(memory["operands"][1]["relocations"]) == 1


def test_supports_two_distinct_or_shared_relocated_operands():
    document = analysis()
    document["symbols"].append({"name": "other", "address": 0x1024,
                                "binding": "global", "section": ".text"})
    document["relocations"].append({"address": 0x1005,
                                     "kind": "ida-off32-32-relative",
                                     "target": "other", "addend": 0})
    document["extensions"]["macho"]["relocations"].append(
        {"address": 0x1005, "target": "other", "width": 4})
    instruction = document["functions"][0]["instructions"][0]
    instruction.update(bytes="907856341278563412", mnemonic="pair",
                       operands="callee, other", normalized_operands="callee, other",
                       relocations=[0, 1])
    result = normalize_analysis(document)["functions"][0]["instructions"][0]
    assert [len(item["relocations"]) for item in result["operands"]] == [1, 1]

    document["relocations"][1]["target"] = "callee"
    document["extensions"]["macho"]["relocations"][1]["target"] = "callee"
    shared = normalize_analysis(document)["functions"][0]["instructions"][0]
    assert [len(item["relocations"]) for item in shared["operands"]] == [2, 0]


@pytest.mark.parametrize("analyzer,kind,extension", [
    ("IDA", "ida-off32-32-relative", {}),
    ("Ghidra", "4", {"ghidra": {"fallback_relocations": [
        {"address": 0x1001, "kind": "4", "target": "callee", "addend": -4,
         "width": 4, "pc_relative": True, "type": 0,
         "original_bytes": "78563412", "external": False,
         "target_section_ordinal": 1}], "fallback_relocation_status": [{
             "index": 0, "address": 0x1001, "status": "APPLIED", "type": 0,
             "values": [-4], "reference_source": 0x1000,
             "original_bytes": "78563412", "width": 4,
             "reference_targets": [0x1020], "external_symbols": [],
             "external_libraries": []}]}}),
    ("angr", "i386-vanilla-32-pcrel", {"macho": {"relocations": [
        {"address": 0x1001, "target": "callee", "width": 4,
         "pc_relative": True}]}}),
])
def test_extracts_real_adapter_relocation_width_and_signedness(analyzer, kind, extension):
    document = analysis(analyzer)
    document["relocations"][0]["kind"] = kind
    document["extensions"] = extension
    result = normalize_analysis(document)
    relocation = result["functions"][0]["instructions"][0]["operands"][0]["relocations"][0]
    assert relocation["width"] == 4
    assert relocation["signed"] is True


def test_ghidra_structured_operand_index_owns_numeric_relocation_operand():
    document = analysis("Ghidra")
    instruction = document["functions"][0]["instructions"][0]
    instruction.update(bytes="B878563412", mnemonic="mov",
                       operands="eax, 0x1020", normalized_operands="eax, 0x1020")
    document["extensions"] = {"ghidra": {
        "fallback_relocations": [{"address": 0x1001, "target": "callee",
                                  "width": 4, "pc_relative": True, "type": 0,
                                  "original_bytes": "78563412", "external": False,
                                  "target_section_ordinal": 1}],
        "fallback_relocation_status": [{"index": 0, "address": 0x1001,
            "status": "APPLIED", "type": 0, "values": [-4],
            "reference_source": 0x1000, "original_bytes": "78563412", "width": 4,
            "reference_targets": [0x1020], "external_symbols": [],
            "external_libraries": []}],
        "reference_metadata": [{"index": 0, "operand_indexes": [1]}],
        "instruction_reference_indexes": [
            {"address": 0x1000, "reference_indexes": [0]}]}}
    result = normalize_analysis(document)["functions"][0]["instructions"][0]
    assert result["operands"][0]["relocations"] == []
    assert len(result["operands"][1]["relocations"]) == 1


def _section_targeted_ghidra_analysis(
        target="__OBJC,__message_refs", section_address=0xA108, addend=0):
    document = analysis("Ghidra")
    document["sections"].append({"name": target, "address": section_address,
                                 "offset": 64, "size": 0x200, "permissions": "rw-",
                                 "sha256": HASH})
    resolved = section_address + addend
    encoded = resolved.to_bytes(4, "little").hex().upper()
    instruction = document["functions"][0]["instructions"][0]
    instruction.update(bytes="8B15" + encoded, mnemonic="MOV",
                       operands=f"EDX, dword ptr [0x{resolved:08x}]",
                       normalized_operands=f"EDX, dword ptr [0x{resolved:08x}]")
    document["relocations"][0].update(
        address=0x1002, kind="i386-vanilla-32-absolute",
        target=target, addend=addend)
    document["extensions"]["macho"]["relocations"][0].update(
        address=0x1002, target=target, width=4, target_section_ordinal=11)
    document["references"] = [
        {"address": 0x1000, "target": resolved, "kind": "READ"}]
    document["extensions"]["ghidra"] = {
        "reference_metadata": [{"index": 0, "operand_indexes": [1]}],
        "instruction_reference_indexes": [
            {"address": 0x1000, "reference_indexes": [0]}]}
    return document


@pytest.mark.parametrize("target,address,addend", [
    ("__OBJC,__message_refs", 0xA108, 0),
    ("__OBJC,__class", 0xA354, 124),
])
def test_ghidra_section_target_plus_addend_owns_numeric_operand(target, address, addend):
    document = _section_targeted_ghidra_analysis(target, address, addend)

    instruction = normalize_analysis(document)["functions"][0]["instructions"][0]

    assert instruction["operands"][0]["relocations"] == []
    assert len(instruction["operands"][1]["relocations"]) == 1


@pytest.mark.parametrize("access_kind", ["READ", "WRITE", "READ_WRITE"])
def test_ghidra_semantic_reference_disambiguates_duplicate_data_reference(access_kind):
    document = _section_targeted_ghidra_analysis()
    document["references"][0]["kind"] = access_kind
    document["references"].insert(
        0, {"address": 0x1000, "target": 0xA108, "kind": "DATA"})
    ghidra = document["extensions"]["ghidra"]
    ghidra["reference_metadata"] = [
        {"index": 0, "operand_indexes": [0]},
        {"index": 1, "operand_indexes": [1]}]
    ghidra["instruction_reference_indexes"][0]["reference_indexes"] = [0, 1]

    instruction = normalize_analysis(document)["functions"][0]["instructions"][0]

    assert instruction["operands"][0]["relocations"] == []
    assert len(instruction["operands"][1]["relocations"]) == 1


@pytest.mark.parametrize("addend", [-1, 0x200, 1 << 80])
def test_ghidra_section_target_rejects_out_of_bounds_addend_before_base_fallback(addend):
    document = _section_targeted_ghidra_analysis()
    document["relocations"][0]["addend"] = addend
    document["references"][0].update(target=0xA108, kind="DATA")

    with pytest.raises(NormalizationError, match="outside target section"):
        normalize_analysis(document)


@pytest.mark.parametrize("section_address,addend,reference_target,original_bytes", [
    (0x8000, -444, 0x7E44, "447E0000"),
    (0, 3221254124, 0, "EC6F00C0"),
])
def test_ghidra_evidence_backed_scattered_addend_may_use_section_base_fallback(
        section_address, addend, reference_target, original_bytes):
    document = _section_targeted_ghidra_analysis(
        target="__DATA,__scatter", section_address=section_address, addend=addend)
    document["relocations"][0]["kind"] = "i386-scattered-vanilla-32-absolute"
    document["references"][0].update(target=reference_target, kind="DATA")
    document["extensions"]["macho"]["relocations"][0].update(
        kind="i386-scattered-vanilla-32-absolute", pc_relative=False,
        original_bytes=original_bytes)

    instruction = normalize_analysis(document)["functions"][0]["instructions"][0]

    assert len(instruction["operands"][1]["relocations"]) == 1


def test_ghidra_scattered_addend_requires_consistent_field_evidence():
    document = _section_targeted_ghidra_analysis(
        target="__DATA,__scatter", section_address=0x8000, addend=-444)
    document["relocations"][0]["kind"] = "i386-scattered-vanilla-32-absolute"
    document["references"][0].update(target=0x8000, kind="DATA")
    document["extensions"]["macho"]["relocations"][0].update(
        kind="i386-scattered-vanilla-32-absolute", pc_relative=False,
        original_bytes="457E0000")

    with pytest.raises(NormalizationError, match="scattered relocation evidence"):
        normalize_analysis(document)


@pytest.mark.parametrize("endianness,original_bytes,valid", [
    ("little", "447E0000", True),
    ("big", "00007E44", True),
    ("big", "447E0000", False),
])
def test_ghidra_scattered_field_proof_uses_analysis_endianness(
        endianness, original_bytes, valid):
    document = _section_targeted_ghidra_analysis(
        target="__DATA,__scatter", section_address=0x8000, addend=-444)
    document["input"]["endianness"] = endianness
    document["relocations"][0]["kind"] = "i386-scattered-vanilla-32-absolute"
    document["references"][0].update(target=0x7E44, kind="DATA")
    document["extensions"]["macho"]["relocations"][0].update(
        kind="i386-scattered-vanilla-32-absolute", pc_relative=False,
        original_bytes=original_bytes)

    if valid:
        instruction = normalize_analysis(document)["functions"][0]["instructions"][0]
        assert len(instruction["operands"][1]["relocations"]) == 1
    else:
        with pytest.raises(NormalizationError, match="scattered relocation evidence"):
            normalize_analysis(document)


def test_ghidra_scattered_field_proof_rejects_unsupported_endianness():
    document = _section_targeted_ghidra_analysis(
        target="__DATA,__scatter", section_address=0x8000, addend=-444)
    document["input"]["endianness"] = "middle"
    document["relocations"][0]["kind"] = "i386-scattered-vanilla-32-absolute"
    document["extensions"]["macho"]["relocations"][0].update(
        kind="i386-scattered-vanilla-32-absolute", pc_relative=False,
        original_bytes="447E0000")

    with pytest.raises(NormalizationError, match="unsupported analysis endianness"):
        normalize_analysis(document)


@pytest.mark.parametrize("metadata", [None, [], "relocation"])
def test_ghidra_rejects_non_object_aligned_relocation_extension_metadata(metadata):
    document = _section_targeted_ghidra_analysis()
    document["extensions"]["macho"]["relocations"][0] = metadata

    with pytest.raises(NormalizationError, match="relocation extension metadata"):
        normalize_analysis(document)


@pytest.mark.parametrize("ordinal", [[], {}, "11", True, 0, -1])
def test_ghidra_rejects_invalid_target_section_ordinal(ordinal):
    document = _section_targeted_ghidra_analysis()
    document["extensions"]["macho"]["relocations"][0][
        "target_section_ordinal"] = ordinal

    with pytest.raises(NormalizationError, match="target section ordinal"):
        normalize_analysis(document)


def test_ghidra_explicit_section_target_is_not_overridden_by_same_named_symbol():
    document = _section_targeted_ghidra_analysis(addend=4)
    document["symbols"].append({
        "name": "__OBJC,__message_refs", "address": 0xA200,
        "binding": "global", "section": "__OBJC,__message_refs"})
    document["references"].insert(
        0, {"address": 0x1000, "target": 0xA200, "kind": "DATA"})
    ghidra = document["extensions"]["ghidra"]
    ghidra["reference_metadata"] = [
        {"index": 0, "operand_indexes": [0]},
        {"index": 1, "operand_indexes": [1]}]
    ghidra["instruction_reference_indexes"][0]["reference_indexes"] = [0, 1]

    instruction = normalize_analysis(document)["functions"][0]["instructions"][0]

    assert instruction["operands"][0]["relocations"] == []
    assert len(instruction["operands"][1]["relocations"]) == 1


@pytest.mark.parametrize("mutation", ["out-of-bounds", "duplicate-section"])
def test_ghidra_section_target_resolution_rejects_nonunique_or_out_of_bounds_targets(mutation):
    document = _section_targeted_ghidra_analysis()
    if mutation == "out-of-bounds":
        document["relocations"][0]["addend"] = 0x200
        document["references"][0]["target"] = 0xA308
    else:
        document["sections"].append({
            "name": "__OBJC,__message_refs", "address": 0xB000, "offset": 0x264,
            "size": 0x200, "permissions": "rw-", "sha256": HASH})
        document["references"][0]["target"] = None

    with pytest.raises(NormalizationError, match="Ghidra relocation"):
        normalize_analysis(document)


def test_ghidra_two_semantic_reference_owners_remain_ambiguous():
    document = _section_targeted_ghidra_analysis()
    document["references"].append(
        {"address": 0x1000, "target": 0xA108, "kind": "WRITE"})
    ghidra = document["extensions"]["ghidra"]
    ghidra["reference_metadata"].append({"index": 1, "operand_indexes": [0]})
    ghidra["instruction_reference_indexes"][0]["reference_indexes"] = [0, 1]

    with pytest.raises(NormalizationError, match="metadata is ambiguous"):
        normalize_analysis(document)


def test_ghidra_flow_reference_cannot_break_data_owner_tie():
    document = _section_targeted_ghidra_analysis()
    document["references"][0]["kind"] = "DATA"
    document["references"].append(
        {"address": 0x1000, "target": 0xA108, "kind": "UNCONDITIONAL_CALL"})
    ghidra = document["extensions"]["ghidra"]
    ghidra["reference_metadata"].append({"index": 1, "operand_indexes": [0]})
    ghidra["instruction_reference_indexes"][0]["reference_indexes"] = [0, 1]

    with pytest.raises(NormalizationError, match="metadata is ambiguous"):
        normalize_analysis(document)


def test_ghidra_identical_duplicate_reference_metadata_is_deduplicated():
    document = _section_targeted_ghidra_analysis()
    document["extensions"]["ghidra"]["reference_metadata"].append(
        {"index": 0, "operand_indexes": [1]})

    instruction = normalize_analysis(document)["functions"][0]["instructions"][0]

    assert len(instruction["operands"][1]["relocations"]) == 1


def test_ghidra_conflicting_duplicate_reference_metadata_is_rejected():
    document = _section_targeted_ghidra_analysis()
    document["extensions"]["ghidra"]["reference_metadata"].append(
        {"index": 0, "operand_indexes": [0]})

    with pytest.raises(NormalizationError, match="reference metadata is ambiguous"):
        normalize_analysis(document)


def _section_targeted_angr_analysis(addend=0, operand_kind="memory",
                                    resolved_address=0xA108):
    document = _section_targeted_ghidra_analysis(addend=addend)
    document["analyzer"].update(name="angr", invocation="angr")
    document["extensions"].pop("ghidra")
    document["extensions"].pop("Ghidra", None)
    document["extensions"]["angr"] = {"cfg": {
        "instruction_operand_metadata": [{"address": 0x1000, "operands": [
            {"index": 0, "kind": "register"},
            {"index": 1, "kind": operand_kind,
             ("encoded_address" if operand_kind == "memory" else
              "resolved_address"): resolved_address,
             "field_offset": 2, "field_width": 4}]}]}}
    return document


@pytest.mark.parametrize("kind", ["memory", "immediate"])
def test_angr_structured_operand_owns_section_targeted_relocation(kind):
    document = _section_targeted_angr_analysis(operand_kind=kind)
    if kind == "immediate":
        document["functions"][0]["instructions"][0].update(
            bytes="B808A10000", operands="EAX, 0x0000a108",
            normalized_operands="EAX, 0x0000a108")
        document["relocations"][0]["address"] = 0x1001
        document["extensions"]["macho"]["relocations"][0]["address"] = 0x1001
        document["extensions"]["angr"]["cfg"]["instruction_operand_metadata"][0][
            "operands"][1]["field_offset"] = 1

    instruction = normalize_analysis(document)["functions"][0]["instructions"][0]

    assert instruction["operands"][0]["relocations"] == []
    assert len(instruction["operands"][1]["relocations"]) == 1


def test_angr_pc_relative_operand_matches_resolved_target_after_field_width():
    document = _section_targeted_angr_analysis(
        addend=0x20, operand_kind="immediate", resolved_address=0xA12C)
    instruction = document["functions"][0]["instructions"][0]
    instruction.update(bytes="E827000000", mnemonic="CALL", operands="0xA12C",
                       normalized_operands="0xA12C")
    document["relocations"][0].update(
        address=0x1001, kind="i386-vanilla-32-pc-relative")
    document["extensions"]["macho"]["relocations"][0].update(
        address=0x1001, kind="i386-vanilla-32-pc-relative", pc_relative=True)
    document["extensions"]["angr"]["cfg"]["instruction_operand_metadata"][0][
        "operands"] = [{"index": 0, "kind": "immediate",
                         "resolved_address": 0xA12C,
                         "field_offset": 1, "field_width": 4}]

    normalized = normalize_analysis(document)["functions"][0]["instructions"][0]

    assert len(normalized["operands"][0]["relocations"]) == 1


def test_angr_pc_relative_external_operand_uses_field_location():
    document = analysis("angr")
    document["symbols"][0].update(
        name="_objc_msgSendSuper", address=0, binding="external", section=None)
    instruction = document["functions"][0]["instructions"][0]
    instruction.update(bytes="E8CAFFFFFF", mnemonic="CALL", operands="0",
                       normalized_operands="0")
    document["relocations"][0].update(
        address=0x1001, kind="i386-vanilla-32-pc-relative",
        target="_objc_msgSendSuper", addend=-0x1005)
    document["extensions"]["macho"]["relocations"][0].update(
        address=0x1001, target="_objc_msgSendSuper", pc_relative=True)
    document["extensions"]["angr"] = {"cfg": {
        "instruction_operand_metadata": [{"address": 0x1000, "operands": [
            {"index": 0, "kind": "immediate", "resolved_address": 0,
             "field_offset": 1, "field_width": 4}]}]}}

    normalized = normalize_analysis(document)["functions"][0]["instructions"][0]

    assert len(normalized["operands"][0]["relocations"]) == 1


@pytest.mark.parametrize("mutation", ["no-match", "multiple-match"])
def test_angr_structured_operand_evidence_fails_closed(mutation):
    document = _section_targeted_angr_analysis()
    operands = document["extensions"]["angr"]["cfg"][
        "instruction_operand_metadata"][0]["operands"]
    if mutation == "no-match":
        operands[1]["encoded_address"] = 0xA10C
    else:
        operands[0].update(kind="immediate", resolved_address=0xA108,
                           field_offset=2, field_width=4)

    with pytest.raises(NormalizationError, match="angr relocation operand"):
        normalize_analysis(document)


@pytest.mark.parametrize("mutation", ["duplicate-section", "out-of-bounds"])
def test_angr_section_target_resolution_fails_closed(mutation):
    document = _section_targeted_angr_analysis()
    if mutation == "duplicate-section":
        document["sections"].append({
            "name": "__OBJC,__message_refs", "address": 0xB000, "offset": 0x264,
            "size": 0x200, "permissions": "rw-", "sha256": HASH})
    else:
        document["relocations"][0]["addend"] = 0x200

    with pytest.raises(NormalizationError, match="angr relocation"):
        normalize_analysis(document)


def test_angr_validated_scattered_relocation_matches_encoded_field_address():
    document = _section_targeted_angr_analysis(
        addend=-444, resolved_address=0x7E44)
    section = next(item for item in document["sections"]
                   if item["name"] == "__OBJC,__message_refs")
    section["address"] = 0x8000
    document["relocations"][0]["kind"] = "i386-scattered-vanilla-32-absolute"
    relocation_metadata = document["extensions"].pop("macho")["relocations"][0]
    relocation_metadata.update(
        kind="i386-scattered-vanilla-32-absolute", pc_relative=False,
        original_bytes="447E0000")
    document["extensions"]["angr"]["relocations"] = [relocation_metadata]

    instruction = normalize_analysis(document)["functions"][0]["instructions"][0]

    assert len(instruction["operands"][1]["relocations"]) == 1


@pytest.mark.parametrize("conflicting", [False, True])
def test_angr_duplicate_unused_instruction_metadata_fails_closed(conflicting):
    document = _section_targeted_angr_analysis()
    duplicate = {"address": 0x2000, "operands": [
        {"index": 0, "kind": "register"}]}
    entries = document["extensions"]["angr"]["cfg"]["instruction_operand_metadata"]
    entries.extend([duplicate, deepcopy(duplicate)])
    if conflicting:
        entries[-1]["operands"][0]["kind"] = "other"

    with pytest.raises(NormalizationError, match="angr instruction operand metadata is ambiguous"):
        normalize_analysis(document)


def test_angr_operand_owner_uses_preindexed_local_lookup_without_rescanning():
    document = _section_targeted_angr_analysis()
    instruction = document["functions"][0]["instructions"][0]
    relocation = document["relocations"][0]
    entry = document["extensions"]["angr"]["cfg"]["instruction_operand_metadata"][0]

    class NoIteration(list):
        def __iter__(self):
            raise AssertionError("operand metadata was rescanned")

    document["extensions"]["angr"]["cfg"]["instruction_operand_metadata"] = NoIteration()
    operand_index = {instruction["address"]: entry}
    for _ in range(1000):
        assert normalize_module._angr_operand_owner(
            document, instruction, relocation, 0, 4, False, operand_index) == 1


def test_angr_index_accepts_explicit_signed_immediate_metadata():
    document = _section_targeted_angr_analysis()
    document["extensions"]["angr"]["cfg"]["instruction_operand_metadata"].append({
        "address": 0x2000, "operands": [{
            "index": 0, "kind": "immediate", "resolved_address": -3,
            "field_offset": 1, "field_width": 1}]})

    normalize_analysis(document)


def test_target_name_must_match_an_operand_token_not_a_substring():
    document = analysis()
    instruction = document["functions"][0]["instructions"][0]
    instruction.update(bytes="B878563412", mnemonic="mov",
                       operands="eax, callee_suffix",
                       normalized_operands="eax, callee_suffix")
    with pytest.raises(NormalizationError, match="operand"):
        normalize_analysis(document)


def test_edges_use_shared_numeric_endpoint_order_not_repr_lexical_order():
    document = analysis()
    successors = document["functions"][0]["blocks"][0]["successors"]
    successors[:] = [{"target": 0x1009, "kind": "a"},
                     {"target": 0x1008, "kind": "z"}]
    edges = normalize_analysis(document)["functions"][0]["edges"]
    assert [(edge["target"]["offset"], edge["kind"]) for edge in edges] == [
        (8, "z"), (9, "a")]


def test_identical_successor_edges_are_deduplicated_without_losing_distinct_evidence():
    document = analysis()
    document["functions"][0]["blocks"] = [
        {"address": 0x1000, "size": 10, "successors": [
            {"target": 0x1008, "kind": "flow"},
            {"target": 0x1008, "kind": "flow"},
            {"target": 0x1008, "kind": "branch"},
            {"target": 0x1009, "kind": "flow"},
        ]},
        {"address": 0x100A, "size": 2, "successors": [
            {"target": 0x1008, "kind": "flow"},
        ]},
    ]
    document["functions"][0]["calls"].append(
        {"address": 0x1005, "target": 0x1020, "name": "callee"}
    )

    function = normalize_analysis(document)["functions"][0]

    assert [(edge["source"]["offset"], edge["target"]["offset"], edge["kind"])
            for edge in function["edges"]] == [
        (0, 8, "branch"),
        (0, 8, "flow"),
        (0, 9, "flow"),
        (10, 8, "flow"),
    ]
    assert [call["source"]["offset"] for call in function["calls"]] == [0, 5]


def test_malformed_successor_is_rejected_before_edge_deduplication():
    document = analysis()
    del document["functions"][0]["blocks"][0]["successors"][0]["kind"]

    with pytest.raises(NormalizationError, match="invalid analysis"):
        normalize_analysis(document)


def test_random_nested_input_permutations_produce_identical_canonical_json():
    baseline = analysis()
    baseline["functions"][0]["blocks"][0]["successors"] = [
        {"target": 0x1009, "kind": "a"}, {"target": 0x1008, "kind": "z"}]
    baseline["references"].append({"address": 0x1005, "target": 0x1024, "kind": "data"})
    expected = json.dumps(normalize_analysis(baseline), sort_keys=True, separators=(",", ":"))
    for seed in range(12):
        candidate = deepcopy(baseline)
        rng = random.Random(seed)
        rng.shuffle(candidate["functions"][0]["instructions"])
        rng.shuffle(candidate["functions"][0]["blocks"][0]["successors"])
        rng.shuffle(candidate["references"])
        actual = json.dumps(normalize_analysis(candidate), sort_keys=True, separators=(",", ":"))
        assert actual == expected


def test_section_identity_requires_name_and_uses_core_occurrence_not_adapter_ordinal():
    first = analysis(); second = analysis()
    second["sections"][0]["name"] = ".other"
    assert (normalize_analysis(first)["sections"][0]["identity"] !=
            normalize_analysis(second)["sections"][0]["identity"])
    for document, ordinal in ((first, 1), (second, 2)):
        document["extensions"] = {"macho": {"sections": [{
            "name": document["sections"][0]["name"], "address": 0x1000,
            "offset": 0, "size": 64, "ordinal": ordinal}], "relocations": [
                {"address": 0x1001, "target": "callee", "width": 4}]}}
    assert normalize_analysis(first)["sections"][0]["identity"]["occurrence"] == 0
    assert normalize_analysis(second)["sections"][0]["identity"]["occurrence"] == 0
    assert "ordinal" not in normalize_analysis(first)["sections"][0]["identity"]


def test_duplicate_section_occurrences_align_across_adapter_metadata_and_rebase():
    documents = [analysis("IDA", 0x1000), analysis("Ghidra", 0x5000), analysis("angr", 0x9000)]
    for document in documents:
        base = document["sections"][0]["address"]
        duplicate = deepcopy(document["sections"][0]); duplicate["address"] = base + 0x100
        document["sections"].append(duplicate)
    documents[1]["extensions"]["ghidra"] = {"fallback_sections": [
        {**documents[1]["sections"][1], "ordinal": 9},
        {**documents[1]["sections"][0], "ordinal": 3}]}
    identities = [[item["identity"] for item in normalize_analysis(document)["sections"]]
                  for document in documents]
    assert identities[0] == identities[1] == identities[2]
    assert [item["occurrence"] for item in identities[0]] == [0, 1]


def test_two_nonoverlapping_relocations_may_share_one_unique_operand_and_reorder_stably():
    document = analysis()
    document["relocations"].append({"address": 0x1005,
        "kind": "ida-off32-32-relative", "target": "callee", "addend": 1})
    document["extensions"]["macho"]["relocations"].append(
        {"address": 0x1005, "target": "callee", "width": 4})
    instruction = document["functions"][0]["instructions"][0]
    instruction.update(bytes="907856341278563412", mnemonic="pair",
                       operands="[callee + callee]", normalized_operands="[callee + callee]",
                       relocations=[0, 1])
    first = normalize_analysis(document)
    relocations = first["functions"][0]["instructions"][0]["operands"][0]["relocations"]
    assert [item["field_offset"] for item in relocations] == [1, 5]
    reordered = deepcopy(document)
    reordered["relocations"].reverse()
    reordered["extensions"]["macho"]["relocations"].reverse()
    assert normalize_analysis(reordered)["functions"] == first["functions"]


def test_preflight_rejects_function_limit_and_nonfinite_extension():
    document = analysis()
    document["functions"] = [deepcopy(document["functions"][0]) for _ in range(MAX_FUNCTIONS + 1)]
    with pytest.raises(NormalizationError, match="function limit"):
        normalize_analysis(document)


def test_extension_mapping_keys_canonicalize_but_ordered_lists_are_preserved():
    first = analysis(); first["extensions"]["trace"] = {"z": 1, "ops": ["add", "sub"]}
    second = analysis(); second["extensions"]["trace"] = {"ops": ["sub", "add"], "z": 1}
    normalized = normalize_analysis(first)
    assert normalized["extensions"]["trace"]["ops"] == ["add", "sub"]
    assert normalize_analysis(first) == normalized
    assert normalize_analysis(second)["extensions"]["trace"]["ops"] == ["sub", "add"]


def _ghidra_status(index=0, address=0x1001, width=4):
    return {"index": index, "address": address, "status": "APPLIED", "type": 0,
            "values": [-4], "reference_source": 0x1000,
            "original_bytes": "78563412", "width": width,
            "reference_targets": [0x1020], "external_symbols": [],
            "external_libraries": []}


def test_validates_real_shaped_ghidra_relocation_status_table():
    document = analysis("Ghidra")
    document["extensions"].setdefault("ghidra", {}).update({
        "fallback_relocations": [{"address": 0x1001, "target": "callee",
                                  "width": 4, "pc_relative": True, "type": 0,
                                  "original_bytes": "78563412", "external": False,
                                  "target_section_ordinal": 1}],
        "fallback_relocation_status": [_ghidra_status()]})
    normalized = normalize_analysis(document)
    assert normalized["extensions"]["ghidra"]["fallback_relocation_status"][0]["index"] == 0


@pytest.mark.parametrize("mutation", ["duplicate", "missing", "trailing", "address",
                                      "width", "type", "bool-index", "unknown", "without"])
def test_rejects_malformed_ghidra_relocation_status_tables(mutation):
    document = analysis("Ghidra")
    ghidra = document["extensions"].setdefault("ghidra", {})
    ghidra["fallback_relocations"] = [
        {"address": 0x1001, "target": "callee", "width": 4,
         "pc_relative": True, "type": 0, "original_bytes": "78563412",
         "external": False, "target_section_ordinal": 1}]
    ghidra["fallback_relocation_status"] = [_ghidra_status()]
    if mutation == "duplicate": ghidra["fallback_relocation_status"] *= 2
    elif mutation == "missing": ghidra["fallback_relocation_status"] = []
    elif mutation == "trailing": ghidra["fallback_relocation_status"].append(_ghidra_status(1))
    elif mutation == "address": ghidra["fallback_relocation_status"][0]["address"] += 1
    elif mutation == "width": ghidra["fallback_relocation_status"][0]["width"] = 2
    elif mutation == "type": ghidra["fallback_relocation_status"][0]["type"] = 7
    elif mutation == "bool-index": ghidra["fallback_relocation_status"][0]["index"] = True
    elif mutation == "unknown": ghidra["fallback_relocation_status"][0]["extra"] = 1
    else:
        document["relocations"] = []; ghidra["fallback_relocations"] = []
    with pytest.raises(NormalizationError, match="status"):
        normalize_analysis(document)


@pytest.mark.parametrize("mutation", ["fallback-only", "status-only", "enum",
                                      "applied-empty", "bytes"])
def test_rejects_ghidra_status_annotation_integrity_gaps(mutation):
    document = analysis("Ghidra"); ghidra = document["extensions"].setdefault("ghidra", {})
    fallback = {"address": 0x1001, "target": "callee", "width": 4,
                "pc_relative": True, "type": 0, "original_bytes": "78563412",
                "external": False, "target_section_ordinal": 1}
    ghidra.update(fallback_relocations=[fallback],
                  fallback_relocation_status=[_ghidra_status()])
    if mutation == "fallback-only": del ghidra["fallback_relocation_status"]
    elif mutation == "status-only": del ghidra["fallback_relocations"]
    elif mutation == "enum": ghidra["fallback_relocation_status"][0]["status"] = "MADE_UP"
    elif mutation == "applied-empty": ghidra["fallback_relocation_status"][0]["reference_targets"] = []
    else: ghidra["fallback_relocation_status"][0]["original_bytes"] = "00000000"
    with pytest.raises(NormalizationError, match="status"):
        normalize_analysis(document)


@pytest.mark.parametrize("status", ["APPLIED", "APPLIED_OTHER", "SKIPPED",
                                    "UNSUPPORTED", "FAILURE", "PARTIAL"])
def test_accepts_exact_ghidra_status_enum_boundaries(status):
    document = analysis("Ghidra"); ghidra = document["extensions"].setdefault("ghidra", {})
    ghidra["fallback_relocations"] = [{"address": 0x1001, "target": "callee",
        "width": 4, "pc_relative": True, "type": 0, "original_bytes": "78563412",
        "external": False, "target_section_ordinal": 1}]
    entry = _ghidra_status(); entry["status"] = status
    if status not in ("APPLIED", "APPLIED_OTHER"): entry["reference_targets"] = []
    ghidra["fallback_relocation_status"] = [entry]
    normalize_analysis(document)


def test_accepts_empty_present_status_tables_and_valid_unresolved_external_shape():
    empty = analysis("Ghidra"); empty["relocations"] = []
    empty["functions"][0]["instructions"][0]["relocations"] = []
    empty["extensions"] = {"ghidra": {"fallback_relocations": [],
                                       "fallback_relocation_status": []}}
    normalize_analysis(empty)

    document = analysis("Ghidra"); document["symbols"] = []
    document["relocations"][0]["target"] = "_external"
    document["extensions"]["macho"]["relocations"][0]["target"] = "_external"
    document["references"][0]["target"] = None
    ghidra = document["extensions"].setdefault("ghidra", {})
    ghidra["fallback_relocations"] = [{"address": 0x1001, "target": "_external",
        "width": 4, "pc_relative": True, "type": 0, "original_bytes": "78563412",
        "external": True, "target_section_ordinal": None}]
    entry = _ghidra_status(); entry["external_symbols"] = ["_external"]
    entry["external_libraries"] = ["libSystem"]
    ghidra["fallback_relocation_status"] = [entry]
    normalize_analysis(document)
    document = analysis(); document["extensions"]["bad"] = {"value": float("nan")}
    with pytest.raises(NormalizationError, match="finite"):
        normalize_analysis(document)


@pytest.mark.parametrize("status", ["SKIPPED", "PARTIAL", "FAILURE"])
def test_nonapplied_ghidra_status_may_retain_instruction_reference_evidence(status):
    document = analysis("Ghidra"); ghidra = document["extensions"].setdefault("ghidra", {})
    ghidra["fallback_relocations"] = [{"address": 0x1001, "target": "callee",
        "width": 4, "pc_relative": True, "type": 0, "original_bytes": "78563412",
        "external": False, "target_section_ordinal": 1}]
    entry = _ghidra_status(); entry["status"] = status
    ghidra["fallback_relocation_status"] = [entry]
    normalize_analysis(document)


def test_mixed_internal_external_siblings_share_instruction_scoped_evidence():
    document = analysis("Ghidra"); document["symbols"] = []
    document["relocations"].append({"address": 0x1005, "kind": "ida-off32-32-relative",
        "target": "_external", "addend": 0})
    instruction = document["functions"][0]["instructions"][0]
    instruction.update(bytes="907856341278563412", operands="callee, _external",
                       normalized_operands="callee, _external", relocations=[0, 1])
    document["references"] = [{"address": 0x1000, "target": None, "kind": "call"}]
    document["extensions"] = {"ghidra": {"fallback_relocations": [
        {"address": 0x1001, "target": "callee", "width": 4, "pc_relative": True,
         "type": 0, "original_bytes": "78563412", "external": False,
         "target_section_ordinal": 1},
        {"address": 0x1005, "target": "_external", "width": 4, "pc_relative": True,
         "type": 0, "original_bytes": "78563412", "external": True,
         "target_section_ordinal": None}], "fallback_relocation_status": []}}
    evidence = {"reference_targets": [0x1020], "external_symbols": ["_external"],
                "external_libraries": ["libSystem"]}
    for index, address in enumerate((0x1001, 0x1005)):
        entry = _ghidra_status(index, address); entry.update(evidence)
        document["extensions"]["ghidra"]["fallback_relocation_status"].append(entry)
    normalize_analysis(document)
    contradictory = deepcopy(document)
    contradictory["extensions"]["ghidra"]["fallback_relocation_status"][1][
        "reference_targets"] = [0x1024]
    with pytest.raises(NormalizationError, match="status"):
        normalize_analysis(contradictory)


@pytest.mark.parametrize(("symbols", "libraries"), [
    (["_external", "_other"], ["libSystem"]),
    (["_external"], ["libA", "libSystem"]),
])
def test_accepts_independent_ghidra_external_sets(symbols, libraries):
    document = analysis("Ghidra"); document["symbols"] = []
    document["relocations"][0]["target"] = "_external"
    document["extensions"]["macho"]["relocations"][0]["target"] = "_external"
    document["references"][0]["target"] = None
    ghidra = document["extensions"].setdefault("ghidra", {})
    ghidra["fallback_relocations"] = [{"address": 0x1001, "target": "_external",
        "width": 4, "pc_relative": True, "type": 0, "original_bytes": "78563412",
        "external": True, "target_section_ordinal": None}]
    entry = _ghidra_status(); entry["external_symbols"] = symbols
    entry["external_libraries"] = libraries
    ghidra["fallback_relocation_status"] = [entry]
    normalize_analysis(document)


@pytest.mark.parametrize("mutation", ["duplicate-reference", "unstable-reference",
                                      "duplicate-symbol", "unstable-symbol",
                                      "duplicate-library", "unstable-library",
                                      "nonstring-symbol", "nonstring-library",
                                      "empty-symbol", "empty-library", "missing-target"])
def test_rejects_noncanonical_ghidra_instruction_evidence(mutation):
    document = analysis("Ghidra"); document["symbols"] = []
    document["relocations"][0]["target"] = "_external"
    document["extensions"]["macho"]["relocations"][0]["target"] = "_external"
    document["references"][0]["target"] = None
    ghidra = document["extensions"].setdefault("ghidra", {})
    ghidra["fallback_relocations"] = [{"address": 0x1001, "target": "_external",
        "width": 4, "pc_relative": True, "type": 0, "original_bytes": "78563412",
        "external": True, "target_section_ordinal": None}]
    entry = _ghidra_status(); entry["external_symbols"] = ["_external"]
    entry["external_libraries"] = ["libSystem"]
    if mutation == "duplicate-reference": entry["reference_targets"] = [0x1020, 0x1020]
    elif mutation == "unstable-reference": entry["reference_targets"] = [0x1024, 0x1020]
    elif mutation == "duplicate-symbol": entry["external_symbols"] = ["_external"] * 2
    elif mutation == "unstable-symbol": entry["external_symbols"] = ["_z", "_external"]
    elif mutation == "duplicate-library": entry["external_libraries"] = ["libSystem"] * 2
    elif mutation == "unstable-library": entry["external_libraries"] = ["libZ", "libA"]
    elif mutation == "nonstring-symbol": entry["external_symbols"] = [1]
    elif mutation == "nonstring-library": entry["external_libraries"] = [1]
    elif mutation == "empty-symbol": entry["external_symbols"] = ["", "_external"]
    elif mutation == "empty-library": entry["external_libraries"] = [""]
    else: entry["external_symbols"] = ["_other"]
    ghidra["fallback_relocation_status"] = [entry]
    with pytest.raises(NormalizationError, match="status"):
        normalize_analysis(document)


def test_load_base_changes_do_not_change_section_relative_function_identity():
    first = normalize_analysis(analysis(base=0x1000))
    second = normalize_analysis(analysis(base=0x5000))
    assert first["functions"][0]["range"] == second["functions"][0]["range"]
    assert first["functions"][0]["edges"] == second["functions"][0]["edges"]


@pytest.mark.parametrize("mutation", ["undeclared", "overlap", "outside"])
def test_rejects_ambiguous_or_malformed_relocation_associations(mutation):
    document = analysis()
    if mutation == "undeclared":
        document["functions"][0]["instructions"][0]["relocations"] = []
    elif mutation == "overlap":
        document["relocations"].append(dict(document["relocations"][0]))
        document["functions"][0]["instructions"][0]["relocations"] = [0, 1]
    else:
        document["relocations"][0]["address"] = 0x2000
    with pytest.raises(NormalizationError, match="relocation"):
        normalize_analysis(document)
