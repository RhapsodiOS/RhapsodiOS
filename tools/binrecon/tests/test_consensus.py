from copy import deepcopy
import json
import random

import pytest

from binrecon.consensus import ConsensusError, build_consensus, validate_consensus
from test_normalize import analysis


def analyses():
    return [analysis("IDA"), analysis("Ghidra"), analysis("angr")]


def test_exact_three_way_agreement_is_deterministic_and_retains_claims():
    documents = analyses()
    result = build_consensus(list(reversed(documents)))
    assert result == build_consensus(documents)
    validate_consensus(result)
    group = result["groups"][0]
    assert group["status"] == "agreed"
    assert [claim["analyzer"] for claim in group["claims"]] == ["Ghidra", "IDA", "angr"]
    assert {claim["confidence"] for claim in group["claims"]} == {.75}
    assert group["aliases"] == ["alias", "f"]


def test_split_boundaries_are_disputed_without_majority_vote():
    documents = analyses()
    split = documents[2]
    original = split["functions"].pop()
    for address, size, name in ((0x1000, 5, "left"), (0x1005, 7, "right")):
        part = deepcopy(original)
        part.update(address=address, size=size, names=[name])
        part["blocks"] = [{"address": address, "size": size, "successors": []}]
        part["instructions"] = [i for i in original["instructions"]
                                if address <= i["address"] < address + size]
        part["calls"] = [c for c in original["calls"] if address <= c["address"] < address + size]
        split["functions"].append(part)
    group = build_consensus(documents)["groups"][0]
    assert group["status"] == "disputed"
    assert "incompatible boundaries" in group["reasons"]
    assert len([c for c in group["claims"] if c["analyzer"] == "angr"]) == 2


def test_missing_edge_or_analyzer_is_partial_with_explicit_reason():
    documents = analyses()
    documents[1]["functions"][0]["blocks"][0]["successors"] = []
    group = build_consensus(documents, expected_analyzers=["IDA", "Ghidra", "angr", "radare"])["groups"][0]
    assert group["status"] == "partial"
    assert "missing analyzer: radare" in group["reasons"]
    assert "incomplete CFG evidence" in group["reasons"]


def test_code_data_disagreement_is_disputed():
    documents = analyses()
    documents[2]["functions"][0]["extensions"] = {"ignored": True}  # schema-invalid on purpose
    documents[2]["functions"] = []
    documents[2]["extensions"]["angr"]["data_ranges"] = [{"address": 0x1000, "size": 12}]
    group = build_consensus(documents)["groups"][0]
    assert group["status"] == "disputed"
    assert "code/data disagreement" in group["reasons"]


def test_rejects_duplicate_analyzers_and_different_artifacts():
    duplicate = analyses()
    duplicate[1]["analyzer"]["name"] = "IDA"
    with pytest.raises(ConsensusError, match="duplicate analyzer"):
        build_consensus(duplicate)
    mismatch = analyses()
    mismatch[2]["input"]["sha256"] = "B" * 64
    with pytest.raises(ConsensusError, match="input identity"):
        build_consensus(mismatch)


def test_rejects_inconsistent_input_architecture_and_closed_contract_extensions():
    mismatch = analyses()
    mismatch[2]["input"]["architecture"] = "powerpc"
    with pytest.raises(ConsensusError, match="input metadata"):
        build_consensus(mismatch)
    result = build_consensus(analyses())
    result["groups"][0]["claims"][0]["surprise"] = True
    with pytest.raises(ConsensusError, match="claim fields"):
        validate_consensus(result)


def test_sections_with_same_name_but_different_identity_do_not_agree():
    documents = analyses()
    documents[2]["sections"][0]["sha256"] = "C" * 64
    groups = build_consensus(documents)["groups"]
    assert len(groups) == 2
    assert all(group["status"] == "partial" for group in groups)


def test_zero_length_function_boundaries_agree_without_becoming_a_byte_claim():
    documents = analyses()
    for document in documents:
        function = document["functions"][0]
        function.update(size=0, blocks=[], instructions=[], calls=[])
    group = build_consensus(documents)["groups"][0]
    assert group["start"] == group["end"] == 0
    assert group["status"] == "agreed"


def test_default_expected_analyzers_make_two_inputs_partial_and_override_can_agree():
    documents = analyses()[:2]
    partial = build_consensus(documents)["groups"][0]
    assert partial["status"] == "partial"
    assert partial["reasons"] == ["missing analyzer: angr"]
    agreed = build_consensus(documents, expected_analyzers=["IDA", "Ghidra"])["groups"][0]
    assert agreed["status"] == "agreed"
    with pytest.raises(ConsensusError, match="duplicate expected"):
        build_consensus(documents, expected_analyzers=["IDA", "IDA", "Ghidra"])
    with pytest.raises(ConsensusError, match="nonempty"):
        build_consensus(documents, expected_analyzers=["IDA", ""])
    with pytest.raises(ConsensusError, match="omit supplied"):
        build_consensus(documents, expected_analyzers=["IDA", "angr"])


def test_reference_consensus_exact_missing_conflicting_external_and_load_base():
    documents = analyses()
    exact = build_consensus(documents)
    assert exact["reference_claims"][0]["references"]
    assert exact["groups"][0]["status"] == "agreed"

    missing = analyses()
    missing[1]["references"] = []
    group = build_consensus(missing)["groups"][0]
    assert group["status"] == "partial"
    assert "incomplete reference evidence" in group["reasons"]

    conflicting = analyses()
    conflicting[1]["references"][0].update(target=0x1024, kind="data")
    group = build_consensus(conflicting)["groups"][0]
    assert group["status"] == "disputed"
    assert "conflicting reference evidence" in group["reasons"]

    external = analyses()
    for document in external:
        document["references"][0]["target"] = None
    reference = build_consensus(external)["reference_claims"][0]["references"][0]
    assert reference["target"] == {"kind": "external", "name": None}

    rebased = analysis("IDA", base=0x5000)
    assert (build_consensus([analysis("IDA")], expected_analyzers=["IDA"])
            ["reference_claims"][0]["references"] ==
            build_consensus([rebased], expected_analyzers=["IDA"])
            ["reference_claims"][0]["references"])


def test_reference_consensus_reports_evidence_outside_functions():
    documents = analyses()
    for document in documents:
        document["references"].append(
            {"address": 0x1020, "target": 0x1024, "kind": "data"})
    assert build_consensus(documents)["reference_consensus"] == {
        "status": "agreed", "reasons": []}
    documents[1]["references"].pop()
    assert build_consensus(documents)["reference_consensus"] == {
        "status": "partial", "reasons": ["incomplete reference evidence"]}


@pytest.mark.parametrize("path,value", [
    (("groups", 0, "claims", 0, "edges", 0), {"source": {}, "target": {}, "kind": 7}),
    (("groups", 0, "claims", 0, "calls", 0), {"source": {}, "target": {}}),
    (("reference_claims", 0, "references", 0), {"source": {}, "target": {}, "kind": "call", "x": 1}),
    (("groups", 0, "claims", 0, "instructions", 0, "operands", 0), {"text": 7, "relocations": []}),
    (("groups", 0, "claims", 0, "instructions", 0), {"unknown": True}),
])
def test_recursive_consensus_contract_rejects_nested_garbage(path, value):
    result = build_consensus(analyses())
    parent = result
    for key in path[:-1]:
        parent = parent[key]
    parent[path[-1]] = value
    with pytest.raises(ConsensusError):
        validate_consensus(result)


def test_recursive_contract_rejects_bool_addresses_and_unsorted_duplicate_evidence():
    result = build_consensus(analyses())
    result["groups"][0]["claims"][0]["range"]["start"] = True
    with pytest.raises(ConsensusError, match="range"):
        validate_consensus(result)
    result = build_consensus(analyses())
    refs = result["reference_claims"][0]["references"]
    refs.append(deepcopy(refs[0]))
    with pytest.raises(ConsensusError, match="references"):
        validate_consensus(result)


@pytest.mark.parametrize("mutation", ["reason", "alias", "reference-index", "group-bool",
                                      "block-range", "relocation-field"])
def test_recursive_contract_rejects_invalid_reasons_aliases_indexes_and_group_ranges(mutation):
    result = build_consensus(analyses())
    group = result["groups"][0]
    if mutation == "reason": group["reasons"] = ["invented"]
    elif mutation == "alias": group["aliases"] = [7]
    elif mutation == "reference-index":
        group["claims"][0]["instructions"][0]["reference_indexes"] = [99]
    elif mutation == "group-bool": group["start"] = True
    elif mutation == "block-range":
        group["claims"][0]["blocks"][0]["end"] = 63
    else:
        group["claims"][0]["instructions"][0]["operands"][0]["relocations"][0]["field_offset"] = 99
    with pytest.raises(ConsensusError):
        validate_consensus(result)


def test_section_groups_use_shared_semantic_order_despite_lexical_conflicts():
    documents = analyses()
    for document in documents:
        document["sections"].append({"name": ".data", "address": 0x2000,
            "offset": 64, "size": 2, "permissions": "a", "sha256": "B" * 64})
        document["functions"].append({"address": 0x2000, "size": 1, "names": ["data_like"],
            "blocks": [], "instructions": [], "calls": [], "confidence": .5})
        document["sections"].reverse()
        document["functions"].reverse()
    groups = build_consensus(documents)["groups"]
    assert [(group["section"]["offset"], group["section"]["permissions"])
            for group in groups] == [(0, "rx"), (64, "a")]


def test_random_consensus_input_and_nested_permutations_are_byte_stable_and_valid():
    documents = analyses()
    documents[0]["functions"][0]["blocks"][0]["successors"] = [
        {"target": 0x1009, "kind": "a"}, {"target": 0x1008, "kind": "z"}]
    for document in documents[1:]:
        document["functions"][0]["blocks"][0]["successors"] = deepcopy(
            documents[0]["functions"][0]["blocks"][0]["successors"])
    expected = None
    for seed in range(12):
        candidate = deepcopy(documents)
        rng = random.Random(seed); rng.shuffle(candidate)
        for document in candidate:
            rng.shuffle(document["functions"][0]["instructions"])
            rng.shuffle(document["functions"][0]["blocks"][0]["successors"])
            rng.shuffle(document["references"])
        result = build_consensus(candidate); validate_consensus(result)
        encoded = json.dumps(result, sort_keys=True, separators=(",", ":"))
        expected = encoded if expected is None else expected
        assert encoded == expected
