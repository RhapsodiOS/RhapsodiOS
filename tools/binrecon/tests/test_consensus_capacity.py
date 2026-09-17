import pytest

from binrecon.consensus import ConsensusError, validate_consensus
from binrecon.schema import (
    CONSENSUS_MAX_JSON_NODES, DEFAULT_MAX_JSON_NODES, MAX_JSON_COLLECTION, preflight_json,
)

# Each edge contributes six JSON values.  Edges are split across multiple
# claims so no single "edges" list approaches MAX_JSON_COLLECTION even when
# the total edge count is sized for a multi-million node budget.
_EDGE_NODE_COUNT = 6
_CHUNK_SIZE = MAX_JSON_COLLECTION // 2


def _consensus_shaped_edges(total_edges):
    edge = {
        "source": {"kind": "unresolved"},
        "target": {"kind": "unresolved"},
        "kind": "flow",
    }
    claims = []
    remaining = total_edges
    while remaining > 0:
        chunk = min(remaining, _CHUNK_SIZE)
        claims.append({"edges": [edge] * chunk})
        remaining -= chunk
    return {
        "schema_version": "consensus-v1",
        "groups": [{"claims": claims}],
    }


def _edges_for_node_budget(node_budget):
    # Edge count whose serialized node total safely exceeds node_budget:
    # wrapper nodes (document, groups list, group dict, claims list, plus
    # two nodes per claim dict/edges-list pair) only add to the margin.
    return node_budget // _EDGE_NODE_COUNT + 1


def test_consensus_preflight_accepts_realistic_aggregate_above_generic_node_limit():
    document = _consensus_shaped_edges(_edges_for_node_budget(DEFAULT_MAX_JSON_NODES))

    with pytest.raises(ConsensusError, match="invalid consensus object fields"):
        validate_consensus(document)

    with pytest.raises(ConsensusError, match="JSON node limit exceeded"):
        preflight_json(document, ConsensusError)


def test_consensus_preflight_rejects_document_over_aggregate_node_budget():
    document = _consensus_shaped_edges(_edges_for_node_budget(CONSENSUS_MAX_JSON_NODES))

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
