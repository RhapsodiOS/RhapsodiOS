from copy import deepcopy

import pytest

from binrecon.normalize import NormalizationError, normalize_analysis


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
    assert relocation == {"index": 0, "field_offset": 1, "width": 4,
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


def test_supports_two_distinct_relocated_operands_and_rejects_ambiguous_owner():
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
    with pytest.raises(NormalizationError, match="operand"):
        normalize_analysis(document)


@pytest.mark.parametrize("analyzer,kind,extension", [
    ("IDA", "ida-off32-32-relative", {}),
    ("Ghidra", "4", {"ghidra": {"fallback_relocations": [
        {"address": 0x1001, "kind": "4", "target": "callee", "addend": -4,
         "width": 4, "pc_relative": True}]}}),
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
                                  "width": 4, "pc_relative": True}],
        "reference_metadata": [{"index": 0, "operand_indexes": [1]}],
        "instruction_reference_indexes": [
            {"address": 0x1000, "reference_indexes": [0]}]}}
    result = normalize_analysis(document)["functions"][0]["instructions"][0]
    assert result["operands"][0]["relocations"] == []
    assert len(result["operands"][1]["relocations"]) == 1


def test_target_name_must_match_an_operand_token_not_a_substring():
    document = analysis()
    instruction = document["functions"][0]["instructions"][0]
    instruction.update(bytes="B878563412", mnemonic="mov",
                       operands="eax, callee_suffix",
                       normalized_operands="eax, callee_suffix")
    with pytest.raises(NormalizationError, match="operand"):
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
