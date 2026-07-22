from copy import deepcopy
import json
import random

import pytest

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


def test_edges_use_shared_numeric_endpoint_order_not_repr_lexical_order():
    document = analysis()
    successors = document["functions"][0]["blocks"][0]["successors"]
    successors[:] = [{"target": 0x1009, "kind": "a"},
                     {"target": 0x1008, "kind": "z"}]
    edges = normalize_analysis(document)["functions"][0]["edges"]
    assert [(edge["target"]["offset"], edge["kind"]) for edge in edges] == [
        (8, "z"), (9, "a")]


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
    document = analysis(); document["extensions"]["bad"] = {"value": float("nan")}
    with pytest.raises(NormalizationError, match="finite"):
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
