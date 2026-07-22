from copy import deepcopy

import pytest

from binrecon.consensus import ConsensusError, build_consensus, validate_consensus
from test_normalize import analysis


def analyses():
    return [analysis("ida"), analysis("ghidra"), analysis("angr")]


def test_exact_three_way_agreement_is_deterministic_and_retains_claims():
    documents = analyses()
    result = build_consensus(list(reversed(documents)), expected_analyzers=["ida", "ghidra", "angr"])
    assert result == build_consensus(documents, expected_analyzers=["angr", "ida", "ghidra"])
    validate_consensus(result)
    group = result["groups"][0]
    assert group["status"] == "agreed"
    assert [claim["analyzer"] for claim in group["claims"]] == ["angr", "ghidra", "ida"]
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
    group = build_consensus(documents, expected_analyzers=["ida", "ghidra", "angr", "radare"])["groups"][0]
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
    duplicate[1]["analyzer"]["name"] = "ida"
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
