"""Consensus clustering for normalized analyzer claims."""

from __future__ import annotations

from copy import deepcopy
import re

from binrecon.normalize import (
    NormalizationError, _range, call_key, canonical_key, edge_key, endpoint_key,
    instruction_key, integer_key, normalize_analysis, range_key, reference_key,
    relocation_key, section_key,
)


class ConsensusError(ValueError):
    """Raised when analyses cannot form a trustworthy consensus report."""


_DEFAULT_ANALYZERS = ("IDA", "Ghidra", "angr")


def _claim_key(value: dict) -> tuple:
    return (canonical_key(value["analyzer"]), range_key(value["range"]),
            canonical_key(value["kind"]), canonical_key(value))


def _group_key(value: dict) -> tuple:
    return (section_key(value["section"]), value["start"], value["end"])


def _reference_in_range(reference: dict, function_range: dict) -> bool:
    source = reference["source"]
    return (source.get("kind") == "section" and
            source.get("section") == function_range["section"] and
            function_range["start"] <= source["offset"] < function_range["end"])


def _claim(analyzer: str, function: dict, references: list[dict]) -> dict:
    return {"analyzer": analyzer, "range": deepcopy(function["range"]),
            "aliases": list(function["aliases"]), "confidence": function["confidence"],
            "kind": "code", "blocks": deepcopy(function["blocks"]),
            "instructions": deepcopy(function["instructions"]),
            "edges": deepcopy(function["edges"]), "calls": deepcopy(function["calls"]),
            "references": [deepcopy(item) for item in references
                           if _reference_in_range(item, function["range"])]}


def _content(claim: dict, *, omit_edges=False):
    instructions = [{key: instruction[key] for key in
                     ("location", "bytes", "mnemonic", "operands")}
                    for instruction in claim["instructions"]]
    calls = [{"source": call["source"], "target": call["target"]}
             for call in claim["calls"]]
    value = {"blocks": claim["blocks"], "instructions": instructions, "calls": calls}
    if not omit_edges:
        value["edges"] = claim["edges"]
    return canonical_key(value)


def _reference_differences(normalized: list[dict], expected: list[str]) -> list[str]:
    reasons = [f"missing analyzer: {name}" for name in expected
               if name not in {item["analyzer"]["name"] for item in normalized}]
    reference_sets = [{canonical_key(reference) for reference in item["references"]}
                      for item in normalized]
    if len({frozenset(items) for items in reference_sets}) > 1:
        by_source = {}
        for item in normalized:
            for reference in item["references"]:
                by_source.setdefault(canonical_key(reference["source"]), set()).add(
                    (canonical_key(reference["target"]), reference["kind"]))
        reasons.append("conflicting reference evidence" if any(
            len(values) > 1 for values in by_source.values()) else
            "incomplete reference evidence")
    return sorted(reasons, key=canonical_key)


def build_consensus(documents: list[dict], expected_analyzers=None) -> dict:
    if not documents:
        raise ConsensusError("at least one analysis is required")
    names = [document.get("analyzer", {}).get("name") for document in documents]
    if len(set(names)) != len(names):
        raise ConsensusError("duplicate analyzer names")
    identities = {(document.get("input", {}).get("size"),
                   str(document.get("input", {}).get("sha256", "")).upper())
                  for document in documents}
    if len(identities) != 1:
        raise ConsensusError("input identity mismatch")
    metadata = {(document.get("input", {}).get("architecture"),
                 document.get("input", {}).get("endianness")) for document in documents}
    if len(metadata) != 1:
        raise ConsensusError("input metadata mismatch")
    try:
        normalized = [normalize_analysis(document) for document in documents]
    except NormalizationError as error:
        raise ConsensusError(str(error)) from error
    requested = list(_DEFAULT_ANALYZERS if expected_analyzers is None else expected_analyzers)
    if any(not isinstance(name, str) or not name for name in requested):
        raise ConsensusError("expected analyzer names must be nonempty strings")
    if len(set(requested)) != len(requested):
        raise ConsensusError("duplicate expected analyzer names")
    expected = sorted(requested, key=canonical_key)
    if not set(names) <= set(expected):
        raise ConsensusError("expected analyzers omit supplied analysis")
    claims = []
    for source, original in zip(normalized, documents):
        analyzer = source["analyzer"]["name"]
        claims.extend(_claim(analyzer, function, source["references"])
                      for function in source["functions"])
        sections = original["sections"]
        for extension in original.get("extensions", {}).values():
            if not isinstance(extension, dict):
                continue
            for data in extension.get("data_ranges", []):
                try:
                    claim_range = _range(data["address"], data["size"], sections)
                except (KeyError, TypeError, NormalizationError) as error:
                    raise ConsensusError(f"invalid data range: {error}") from error
                claims.append({"analyzer": analyzer, "range": claim_range, "aliases": [],
                               "confidence": data.get("confidence", 1.0), "kind": "data",
                               "blocks": [], "instructions": [], "edges": [], "calls": [],
                               "references": []})
    # Connected overlap components, but only within an exact canonical section identity.
    pending = sorted(claims, key=lambda c: (section_key(c["range"]["section"]),
                                            c["range"]["start"], c["range"]["end"],
                                            c["analyzer"], c["kind"]))
    components = []
    for claim in pending:
        matches = [component for component in components
                   if component[0]["range"]["section"] == claim["range"]["section"] and
                   ((claim["range"]["start"], claim["range"]["end"]) in
                    {(c["range"]["start"], c["range"]["end"]) for c in component} or
                    (max(c["range"]["end"] for c in component) > claim["range"]["start"] and
                     claim["range"]["end"] > min(c["range"]["start"] for c in component)))]
        if not matches:
            components.append([claim])
        else:
            primary = matches[0]
            primary.append(claim)
            for extra in matches[1:]:
                primary.extend(extra); components.remove(extra)
    groups = []
    for component in components:
        component.sort(key=_claim_key)
        present = {claim["analyzer"] for claim in component}
        reasons = []
        kinds = {claim["kind"] for claim in component}
        ranges = {(claim["range"]["start"], claim["range"]["end"]) for claim in component}
        repeated = len(present) != len(component)
        if kinds == {"code", "data"}: reasons.append("code/data disagreement")
        if len(ranges) != 1 or repeated: reasons.append("incompatible boundaries")
        for missing in sorted(set(expected) - present, key=canonical_key):
            reasons.append(f"missing analyzer: {missing}")
        code = [claim for claim in component if claim["kind"] == "code"]
        if code and len(ranges) == 1 and not repeated and kinds == {"code"}:
            without_edges = {_content(claim, omit_edges=True) for claim in code}
            all_content = {_content(claim) for claim in code}
            if len(without_edges) > 1:
                reasons.append("incompatible code evidence")
            elif len(all_content) > 1:
                reasons.append("incomplete CFG evidence")
            reference_sets = [{canonical_key(item) for item in claim["references"]} for claim in code]
            if len({frozenset(items) for items in reference_sets}) > 1:
                by_source = {}
                for claim in code:
                    for reference in claim["references"]:
                        by_source.setdefault(canonical_key(reference["source"]), set()).add(
                            (canonical_key(reference["target"]), reference["kind"]))
                if any(len(values) > 1 for values in by_source.values()):
                    reasons.append("conflicting reference evidence")
                else:
                    reasons.append("incomplete reference evidence")
        disputed = any(reason in reasons for reason in (
            "code/data disagreement", "incompatible boundaries", "incompatible code evidence",
            "conflicting reference evidence"))
        status = "disputed" if disputed else ("partial" if reasons else "agreed")
        reasons.sort(key=canonical_key)
        aliases = sorted({alias for claim in component for alias in claim["aliases"]},
                         key=canonical_key)
        start = min(claim["range"]["start"] for claim in component)
        end = max(claim["range"]["end"] for claim in component)
        groups.append({"section": deepcopy(component[0]["range"]["section"]),
                       "start": start, "end": end, "status": status,
                       "reasons": reasons, "aliases": aliases, "claims": component})
    first = normalized[0]["input"]
    reference_reasons = _reference_differences(normalized, expected)
    reference_status = ("disputed" if "conflicting reference evidence" in reference_reasons
                        else "partial" if reference_reasons else "agreed")
    result = {"schema_version": "consensus-v1",
              "input": {"size": first["size"], "sha256": first["sha256"],
                        "architecture": first["architecture"],
                        "endianness": first["endianness"]},
              "expected_analyzers": expected,
              "analyzers": sorted(({"name": item["analyzer"]["name"],
                                     "version": item["analyzer"]["version"],
                                     "invocation": item["analyzer"]["invocation"],
                                     "extensions": deepcopy(item.get("extensions", {}))}
                                    for item in normalized),
                                  key=lambda item: canonical_key(item["name"])),
              "reference_claims": sorted(({
                  "analyzer": item["analyzer"]["name"],
                  "references": deepcopy(item["references"])} for item in normalized),
                  key=lambda item: canonical_key(item["analyzer"])),
              "reference_consensus": {"status": reference_status,
                                      "reasons": reference_reasons},
              "groups": sorted(groups, key=_group_key)}
    validate_consensus(result)
    return result


def validate_consensus(document: dict) -> None:
    """Validate the closed, versioned consensus-v1 in-process contract."""
    _exact(document, {"schema_version", "input", "expected_analyzers", "analyzers",
                      "reference_claims", "reference_consensus", "groups"},
           "consensus object")
    if document["schema_version"] != "consensus-v1":
        raise ConsensusError("unsupported consensus version")
    _exact(document["input"], {"size", "sha256", "architecture", "endianness"},
           "consensus input")
    identity = document["input"]
    if (not _integer(identity["size"]) or identity["size"] < 0 or
            not isinstance(identity["sha256"], str) or len(identity["sha256"]) != 64 or
            any(character not in "0123456789ABCDEF" for character in identity["sha256"]) or
            not isinstance(identity["architecture"], str) or
            not isinstance(identity["endianness"], str)):
        raise ConsensusError("invalid consensus input identity")
    if (not isinstance(document["expected_analyzers"], list) or
            any(not isinstance(name, str) or not name
                for name in document["expected_analyzers"]) or
            document["expected_analyzers"] != sorted(set(document["expected_analyzers"]),
                                                     key=canonical_key)):
        raise ConsensusError("invalid expected analyzers")
    if not isinstance(document["analyzers"], list) or not isinstance(document["groups"], list):
        raise ConsensusError("invalid consensus collections")
    for analyzer in document["analyzers"]:
        if not isinstance(analyzer, dict):
            raise ConsensusError("invalid analyzer")
        if set(analyzer) != {"name", "version", "invocation", "extensions"}:
            raise ConsensusError("invalid analyzer fields")
        if any(not isinstance(analyzer[key], str) for key in ("name", "version", "invocation")):
            raise ConsensusError("invalid analyzer identity")
        if (not analyzer["name"] or not isinstance(analyzer["extensions"], dict) or
                any(not isinstance(name, str) or not name
                    for name in analyzer["extensions"])):
            raise ConsensusError("invalid analyzer extensions")
    analyzer_names = [item["name"] for item in document["analyzers"]]
    if analyzer_names != sorted(set(analyzer_names), key=canonical_key):
        raise ConsensusError("duplicate analyzer names")
    if not set(analyzer_names) <= set(document["expected_analyzers"]):
        raise ConsensusError("expected analyzers omit supplied analysis")
    reference_claims = document["reference_claims"]
    if not isinstance(reference_claims, list):
        raise ConsensusError("invalid reference claims")
    if [item.get("analyzer") for item in reference_claims] != analyzer_names:
        raise ConsensusError("invalid reference claim analyzers")
    references_by_analyzer = {}
    for reference_claim in reference_claims:
        _exact(reference_claim, {"analyzer", "references"}, "reference claim")
        references = reference_claim["references"]
        _evidence(references, _reference, "references", key=reference_key)
        references_by_analyzer[reference_claim["analyzer"]] = references
    _exact(document["reference_consensus"], {"status", "reasons"},
           "reference consensus")
    expected_reference_reasons = _reference_differences(
        [{"analyzer": {"name": item["analyzer"]}, "references": item["references"]}
         for item in reference_claims], document["expected_analyzers"])
    if document["reference_consensus"]["reasons"] != expected_reference_reasons:
        raise ConsensusError("reference consensus does not match claims")
    _status_reasons(document["reference_consensus"]["status"],
                    document["reference_consensus"]["reasons"],
                    set(document["expected_analyzers"]) - set(analyzer_names))
    for group in document["groups"]:
        if set(group) != {"section", "start", "end", "status", "reasons", "aliases", "claims"}:
            raise ConsensusError("invalid consensus group fields")
        if group["status"] not in ("agreed", "partial", "disputed"):
            raise ConsensusError("invalid consensus status")
        if (not _integer(group["start"]) or not _integer(group["end"]) or
                group["start"] < 0 or group["start"] > group["end"] or
                group["end"] > group["section"]["size"]):
            raise ConsensusError("invalid consensus range")
        _section(group["section"])
        group_analyzers = {claim.get("analyzer") for claim in group["claims"]
                           if isinstance(claim, dict)}
        _status_reasons(group["status"], group["reasons"],
                        set(document["expected_analyzers"]) - group_analyzers)
        if (not isinstance(group["aliases"], list) or
                any(not isinstance(alias, str) for alias in group["aliases"]) or
                group["aliases"] != sorted(set(group["aliases"]), key=canonical_key) or
                not isinstance(group["claims"], list) or not group["claims"]):
            raise ConsensusError("invalid consensus group collections")
        for claim in group["claims"]:
            _exact(claim, {"analyzer", "range", "aliases", "confidence", "kind",
                           "blocks", "instructions", "edges", "calls", "references"},
                   "consensus claim")
            if claim["analyzer"] not in analyzer_names or claim["kind"] not in ("code", "data"):
                raise ConsensusError("invalid consensus claim identity")
            if (isinstance(claim["confidence"], bool) or
                    not isinstance(claim["confidence"], (int, float)) or
                    not 0 <= claim["confidence"] <= 1):
                raise ConsensusError("invalid consensus claim confidence")
            claim_range = claim["range"]
            try:
                _range_contract(claim_range)
            except ConsensusError as error:
                raise ConsensusError(f"invalid consensus claim range: {error}") from error
            if claim_range["section"] != group["section"]:
                raise ConsensusError("invalid consensus claim range")
            if (not isinstance(claim["aliases"], list) or
                    any(not isinstance(alias, str) for alias in claim["aliases"]) or
                    claim["aliases"] != sorted(set(claim["aliases"]), key=canonical_key)):
                raise ConsensusError("invalid consensus claim aliases")
            _evidence(claim["blocks"], _range_contract, "blocks", key=range_key)
            _evidence(claim["instructions"], _instruction, "instructions",
                      key=instruction_key)
            _evidence(claim["edges"], _edge, "edges", key=edge_key)
            _evidence(claim["calls"], _call, "calls", key=call_key)
            _evidence(claim["references"], _reference, "references", key=reference_key)
            for block in claim["blocks"]:
                if (block["section"] != claim_range["section"] or
                        block["start"] < claim_range["start"] or
                        block["end"] > claim_range["end"]):
                    raise ConsensusError("block is outside claim range")
            block_starts = {block["start"] for block in claim["blocks"]}
            for instruction in claim["instructions"]:
                if not _endpoint_in_range(instruction["location"], claim_range):
                    raise ConsensusError("instruction is outside claim range")
            for edge in claim["edges"]:
                if (not _endpoint_in_range(edge["source"], claim_range) or
                        edge["source"]["offset"] not in block_starts):
                    raise ConsensusError("edge source is not a claim block")
            for item in claim["calls"] + claim["references"]:
                if not _endpoint_in_range(item["source"], claim_range):
                    raise ConsensusError("claim evidence source is outside claim range")
            if claim["kind"] == "data" and any(claim[key] for key in
                    ("blocks", "instructions", "edges", "calls", "references")):
                raise ConsensusError("data claim contains code evidence")
            global_references = references_by_analyzer[claim["analyzer"]]
            if any(reference not in global_references for reference in claim["references"]):
                raise ConsensusError("claim references are not in analyzer reference claim")
            for instruction in claim["instructions"]:
                if any(index >= len(global_references)
                       for index in instruction["reference_indexes"]):
                    raise ConsensusError("invalid instruction reference index")
        if (group["start"] != min(claim["range"]["start"] for claim in group["claims"]) or
                group["end"] != max(claim["range"]["end"] for claim in group["claims"]) or
                group["aliases"] != sorted({alias for claim in group["claims"]
                                            for alias in claim["aliases"]},
                                           key=canonical_key)):
            raise ConsensusError("group summary does not match claims")
        claim_keys = [_claim_key(claim) for claim in group["claims"]]
        if claim_keys != sorted(set(claim_keys)):
            raise ConsensusError("unsorted or duplicate claims")
    group_keys = [_group_key(group) for group in document["groups"]]
    if group_keys != sorted(set(group_keys)):
        raise ConsensusError("unsorted or duplicate groups")


def _status_reasons(status, reasons, missing_analyzers=()) -> None:
    allowed = {"code/data disagreement", "incompatible boundaries",
               "incompatible code evidence", "incomplete CFG evidence",
               "incomplete reference evidence", "conflicting reference evidence"}
    if status not in ("agreed", "partial", "disputed"):
        raise ConsensusError("invalid consensus status")
    missing_reasons = {f"missing analyzer: {name}" for name in missing_analyzers}
    if (not isinstance(reasons, list) or len(reasons) != len(set(reasons)) or
            any(not isinstance(reason, str) or
                (reason not in allowed and reason not in missing_reasons)
                for reason in reasons)):
        raise ConsensusError("invalid consensus reasons")
    if reasons != sorted(reasons, key=canonical_key):
        raise ConsensusError("unsorted consensus reasons")
    if {reason for reason in reasons if reason.startswith("missing analyzer: ")} != missing_reasons:
        raise ConsensusError("missing analyzer reasons do not match claims")
    disputed = any(reason in {"code/data disagreement", "incompatible boundaries",
                              "incompatible code evidence", "conflicting reference evidence"}
                   for reason in reasons)
    expected = "disputed" if disputed else "partial" if reasons else "agreed"
    if status != expected:
        raise ConsensusError("consensus status does not match reasons")


def _endpoint_in_range(endpoint: dict, value_range: dict) -> bool:
    return (endpoint["kind"] == "section" and
            endpoint["section"] == value_range["section"] and
            value_range["start"] <= endpoint["offset"] < value_range["end"])


def _integer(value) -> bool:
    return type(value) is int


def _exact(value, fields: set[str], where: str) -> None:
    if not isinstance(value, dict) or set(value) != fields:
        raise ConsensusError(f"invalid {where} fields")


def _section(value: dict) -> None:
    _exact(value, {"offset", "size", "permissions", "sha256"}, "section identity")
    if (not _integer(value["offset"]) or value["offset"] < 0 or
            not _integer(value["size"]) or value["size"] < 0 or
            not isinstance(value["permissions"], str) or
            not isinstance(value["sha256"], str) or
            re.fullmatch(r"[0-9A-F]{64}", value["sha256"]) is None):
        raise ConsensusError("invalid section identity")


def _endpoint(value: dict) -> None:
    if not isinstance(value, dict) or "kind" not in value:
        raise ConsensusError("invalid endpoint")
    kind = value["kind"]
    if kind == "section":
        _exact(value, {"kind", "section", "offset"}, "section endpoint")
        _section(value["section"])
        if (not _integer(value["offset"]) or value["offset"] < 0 or
                value["offset"] >= value["section"]["size"]):
            raise ConsensusError("invalid section endpoint offset")
    elif kind == "unmapped":
        _exact(value, {"kind", "address"}, "unmapped endpoint")
        if not _integer(value["address"]) or value["address"] < 0:
            raise ConsensusError("invalid unmapped endpoint address")
    elif kind == "external":
        _exact(value, {"kind", "name"}, "external endpoint")
        if value["name"] is not None and not isinstance(value["name"], str):
            raise ConsensusError("invalid external endpoint name")
    elif kind == "unresolved":
        _exact(value, {"kind"}, "unresolved endpoint")
    else:
        raise ConsensusError("invalid endpoint kind")


def _range_contract(value: dict) -> None:
    _exact(value, {"section", "start", "end"}, "range")
    _section(value["section"])
    if (not _integer(value["start"]) or not _integer(value["end"]) or
            value["start"] < 0 or value["start"] > value["end"] or
            value["end"] > value["section"]["size"]):
        raise ConsensusError("invalid range")


def _relocation(value: dict) -> None:
    _exact(value, {"index", "field_offset", "width", "signed", "kind", "target", "addend"},
           "relocation")
    if (not _integer(value["index"]) or value["index"] < 0 or
            not _integer(value["field_offset"]) or value["field_offset"] < 0 or
            value["width"] not in (1, 2, 4) or type(value["signed"]) is not bool or
            not isinstance(value["kind"], str) or not _integer(value["addend"])):
        raise ConsensusError("invalid relocation")
    _endpoint(value["target"])


def _operand(value: dict) -> None:
    _exact(value, {"text", "relocations"}, "operand")
    if not isinstance(value["text"], str):
        raise ConsensusError("invalid operand text")
    _evidence(value["relocations"], _relocation, "operand relocations",
              key=relocation_key)


def _instruction(value: dict) -> None:
    _exact(value, {"location", "bytes", "mnemonic", "operands", "display_operands",
                   "normalized_operands", "relocations", "reference_indexes"}, "instruction")
    _endpoint(value["location"])
    if (not isinstance(value["bytes"], str) or
            re.fullmatch(r"(?:[0-9A-F]{2})+", value["bytes"]) is None or
            not isinstance(value["mnemonic"], str) or
            not isinstance(value["display_operands"], str) or
            not isinstance(value["normalized_operands"], str)):
        raise ConsensusError("invalid instruction scalar")
    if not isinstance(value["operands"], list):
        raise ConsensusError("invalid instruction operands")
    for operand in value["operands"]:
        _operand(operand)
    for name in ("relocations", "reference_indexes"):
        indexes = value[name]
        if (not isinstance(indexes, list) or any(not _integer(item) or item < 0 for item in indexes)
                or indexes != sorted(set(indexes), key=integer_key)):
            raise ConsensusError(f"invalid instruction {name}")
    operand_indexes = sorted((item["index"] for operand in value["operands"]
                              for item in operand["relocations"]), key=integer_key)
    if operand_indexes != value["relocations"]:
        raise ConsensusError("instruction relocation indexes disagree with operands")
    byte_length = len(value["bytes"]) // 2
    if any(relocation["field_offset"] + relocation["width"] > byte_length
           for operand in value["operands"] for relocation in operand["relocations"]):
        raise ConsensusError("relocation field is outside instruction")


def _edge(value: dict) -> None:
    _exact(value, {"source", "target", "kind"}, "edge")
    _endpoint(value["source"]); _endpoint(value["target"])
    if not isinstance(value["kind"], str): raise ConsensusError("invalid edge kind")


def _call(value: dict) -> None:
    _exact(value, {"source", "target", "name"}, "call")
    _endpoint(value["source"]); _endpoint(value["target"])
    if value["name"] is not None and not isinstance(value["name"], str):
        raise ConsensusError("invalid call name")


def _reference(value: dict) -> None:
    _exact(value, {"source", "target", "kind"}, "reference")
    _endpoint(value["source"]); _endpoint(value["target"])
    if not isinstance(value["kind"], str): raise ConsensusError("invalid reference kind")


def _evidence(values, validator, where: str, key=None) -> None:
    if not isinstance(values, list):
        raise ConsensusError(f"invalid {where}")
    for value in values:
        validator(value)
    sort_key = key or canonical_key
    keys = [sort_key(item) for item in values]
    if keys != sorted(set(keys)):
        raise ConsensusError(f"unsorted or duplicate {where}")
