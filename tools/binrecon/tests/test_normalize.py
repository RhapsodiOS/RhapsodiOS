from copy import deepcopy

import pytest

from binrecon.normalize import NormalizationError, normalize_analysis


HASH = "A" * 64


def analysis(name="ida", base=0x1000):
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
                 "operands": "0x12345678", "normalized_operands": "0x12345678",
                 "relocations": [0]},
                {"address": base + 5, "bytes": "3D78563412", "mnemonic": "cmp",
                 "operands": "eax, 0x12345678", "normalized_operands": "eax, 0x12345678",
                 "relocations": []},
                {"address": base + 10, "bytes": "E480", "mnemonic": "in",
                 "operands": "al, 0x80", "normalized_operands": "al, 0x80",
                 "relocations": []}],
            "calls": [{"address": base, "target": base + 0x20, "name": "callee"}],
            "confidence": .75}],
        "references": [{"address": base + 1, "target": base + 0x20, "kind": "call"}],
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
    assert instructions[0]["operands"] == [{
        "kind": "relocation", "width": 4, "signed": True,
        "target": {"kind": "section", "section": result["sections"][0]["identity"],
                   "offset": 0x20}, "addend": -4}]
    assert instructions[1]["operands"] == [{"kind": "text", "value": "eax, 0x12345678"}]
    assert instructions[2]["operands"] == [{"kind": "text", "value": "al, 0x80"}]
    assert instructions[0]["bytes"] == "E878563412"
    assert instructions[0]["mnemonic"] == "call"
    assert instructions[0]["display_operands"] == "0x12345678"


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
