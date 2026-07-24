import pytest

from binrecon.consensus import ConsensusError, validate_consensus
from binrecon.schema import preflight_json


def _consensus_shaped_edges(count):
    edge = {
        "source": {"kind": "unresolved"},
        "target": {"kind": "unresolved"},
        "kind": "flow",
    }
    return {
        "schema_version": "consensus-v1",
        "groups": [{"claims": [{"edges": [edge] * count}]}],
    }


def test_consensus_preflight_accepts_realistic_aggregate_above_generic_node_limit():
    # Each edge contributes six JSON values.  This represents 1,000,009
    # serialized nodes without retaining 166,667 separately allocated copies.
    document = _consensus_shaped_edges(166_667)

    with pytest.raises(ConsensusError, match="invalid consensus object fields"):
        validate_consensus(document)

    with pytest.raises(ConsensusError, match="JSON node limit exceeded"):
        preflight_json(document, ConsensusError)


def test_consensus_preflight_rejects_document_over_aggregate_node_budget():
    document = _consensus_shaped_edges(416_667)

    with pytest.raises(ConsensusError, match="JSON node limit exceeded"):
        validate_consensus(document)


def test_consensus_preflight_retains_generic_depth_and_string_limits():
    too_deep = None
    for _ in range(65):
        too_deep = [too_deep]

    with pytest.raises(ConsensusError, match="JSON nesting depth limit exceeded"):
        preflight_json(too_deep, ConsensusError, max_nodes=2_500_000)
    with pytest.raises(ConsensusError, match="JSON string length limit exceeded"):
        preflight_json("x" * 1_048_577, ConsensusError, max_nodes=2_500_000)
    with pytest.raises(ConsensusError, match="JSON collection length limit exceeded"):
        preflight_json([None] * 500_001, ConsensusError, max_nodes=2_500_000)
