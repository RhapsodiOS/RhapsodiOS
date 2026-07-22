"""Consensus clustering for normalized analyzer claims."""

from __future__ import annotations

from copy import deepcopy

from binrecon.normalize import NormalizationError, _location, _range, normalize_analysis


class ConsensusError(ValueError):
    """Raised when analyses cannot form a trustworthy consensus report."""


def _claim(analyzer: str, function: dict) -> dict:
    return {"analyzer": analyzer, "range": deepcopy(function["range"]),
            "aliases": list(function["aliases"]), "confidence": function["confidence"],
            "kind": "code", "blocks": deepcopy(function["blocks"]),
            "instructions": deepcopy(function["instructions"]),
            "edges": deepcopy(function["edges"]), "calls": deepcopy(function["calls"])}


def _content(claim: dict, *, omit_edges=False):
    instructions = [{key: instruction[key] for key in
                     ("location", "bytes", "mnemonic", "operands")}
                    for instruction in claim["instructions"]]
    calls = [{"source": call["source"], "target": call["target"]}
             for call in claim["calls"]]
    value = {"blocks": claim["blocks"], "instructions": instructions, "calls": calls}
    if not omit_edges:
        value["edges"] = claim["edges"]
    return repr(value)


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
    expected = sorted(set(expected_analyzers if expected_analyzers is not None else names))
    if not set(names) <= set(expected):
        raise ConsensusError("expected analyzers omit supplied analysis")
    claims = []
    for source, original in zip(normalized, documents):
        analyzer = source["analyzer"]["name"]
        claims.extend(_claim(analyzer, function) for function in source["functions"])
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
                               "blocks": [], "instructions": [], "edges": [], "calls": []})
    # Connected overlap components, but only within an exact canonical section identity.
    pending = sorted(claims, key=lambda c: (repr(c["range"]["section"]),
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
        component.sort(key=lambda c: (c["analyzer"], c["range"]["start"],
                                      c["range"]["end"], c["kind"]))
        present = {claim["analyzer"] for claim in component}
        reasons = []
        kinds = {claim["kind"] for claim in component}
        ranges = {(claim["range"]["start"], claim["range"]["end"]) for claim in component}
        repeated = len(present) != len(component)
        if kinds == {"code", "data"}: reasons.append("code/data disagreement")
        if len(ranges) != 1 or repeated: reasons.append("incompatible boundaries")
        for missing in sorted(set(expected) - present): reasons.append(f"missing analyzer: {missing}")
        code = [claim for claim in component if claim["kind"] == "code"]
        if code and len(ranges) == 1 and not repeated and kinds == {"code"}:
            without_edges = {_content(claim, omit_edges=True) for claim in code}
            all_content = {_content(claim) for claim in code}
            if len(without_edges) > 1:
                reasons.append("incompatible code evidence")
            elif len(all_content) > 1:
                reasons.append("incomplete CFG evidence")
        disputed = any(reason in reasons for reason in (
            "code/data disagreement", "incompatible boundaries", "incompatible code evidence"))
        status = "disputed" if disputed else ("partial" if reasons else "agreed")
        aliases = sorted({alias for claim in component for alias in claim["aliases"]})
        start = min(claim["range"]["start"] for claim in component)
        end = max(claim["range"]["end"] for claim in component)
        groups.append({"section": deepcopy(component[0]["range"]["section"]),
                       "start": start, "end": end, "status": status,
                       "reasons": reasons, "aliases": aliases, "claims": component})
    first = normalized[0]["input"]
    result = {"schema_version": "consensus-v1",
              "input": {"size": first["size"], "sha256": first["sha256"],
                        "architecture": first["architecture"],
                        "endianness": first["endianness"]},
              "expected_analyzers": expected,
              "analyzers": sorted(({"name": item["analyzer"]["name"],
                                     "version": item["analyzer"]["version"],
                                     "invocation": item["analyzer"]["invocation"],
                                     "extensions": deepcopy(item.get("extensions", {}))}
                                    for item in normalized), key=lambda item: item["name"]),
              "groups": sorted(groups, key=lambda g: (repr(g["section"]), g["start"], g["end"]))}
    validate_consensus(result)
    return result


def validate_consensus(document: dict) -> None:
    """Validate the closed, versioned consensus-v1 in-process contract."""
    if not isinstance(document, dict) or set(document) != {
            "schema_version", "input", "expected_analyzers", "analyzers", "groups"}:
        raise ConsensusError("invalid consensus object fields")
    if document["schema_version"] != "consensus-v1":
        raise ConsensusError("unsupported consensus version")
    if set(document["input"]) != {"size", "sha256", "architecture", "endianness"}:
        raise ConsensusError("invalid consensus input fields")
    identity = document["input"]
    if (not isinstance(identity["size"], int) or identity["size"] < 0 or
            not isinstance(identity["sha256"], str) or len(identity["sha256"]) != 64 or
            any(character not in "0123456789ABCDEF" for character in identity["sha256"]) or
            not isinstance(identity["architecture"], str) or
            not isinstance(identity["endianness"], str)):
        raise ConsensusError("invalid consensus input identity")
    if (not isinstance(document["expected_analyzers"], list) or
            document["expected_analyzers"] != sorted(set(document["expected_analyzers"]))):
        raise ConsensusError("invalid expected analyzers")
    if not isinstance(document["analyzers"], list) or not isinstance(document["groups"], list):
        raise ConsensusError("invalid consensus collections")
    analyzer_names = [item.get("name") for item in document["analyzers"]]
    if len(analyzer_names) != len(set(analyzer_names)):
        raise ConsensusError("duplicate analyzer names")
    for analyzer in document["analyzers"]:
        if set(analyzer) != {"name", "version", "invocation", "extensions"}:
            raise ConsensusError("invalid analyzer fields")
        if any(not isinstance(analyzer[key], str) for key in ("name", "version", "invocation")):
            raise ConsensusError("invalid analyzer identity")
        if not isinstance(analyzer["extensions"], dict):
            raise ConsensusError("invalid analyzer extensions")
    for group in document["groups"]:
        if set(group) != {"section", "start", "end", "status", "reasons", "aliases", "claims"}:
            raise ConsensusError("invalid consensus group fields")
        if group["status"] not in ("agreed", "partial", "disputed"):
            raise ConsensusError("invalid consensus status")
        if not isinstance(group["start"], int) or not isinstance(group["end"], int) or group["start"] > group["end"]:
            raise ConsensusError("invalid consensus range")
        if set(group["section"]) != {"offset", "size", "permissions", "sha256"}:
            raise ConsensusError("invalid section identity fields")
        if (not isinstance(group["reasons"], list) or
                any(not isinstance(reason, str) for reason in group["reasons"]) or
                not isinstance(group["aliases"], list) or
                group["aliases"] != sorted(set(group["aliases"])) or
                not isinstance(group["claims"], list) or not group["claims"]):
            raise ConsensusError("invalid consensus group collections")
        for claim in group["claims"]:
            if set(claim) != {"analyzer", "range", "aliases", "confidence", "kind",
                             "blocks", "instructions", "edges", "calls"}:
                raise ConsensusError("invalid consensus claim fields")
            if claim["analyzer"] not in analyzer_names or claim["kind"] not in ("code", "data"):
                raise ConsensusError("invalid consensus claim identity")
            if (not isinstance(claim["confidence"], (int, float)) or
                    not 0 <= claim["confidence"] <= 1):
                raise ConsensusError("invalid consensus claim confidence")
            claim_range = claim["range"]
            if (set(claim_range) != {"section", "start", "end"} or
                    claim_range["section"] != group["section"] or
                    not isinstance(claim_range["start"], int) or
                    not isinstance(claim_range["end"], int) or
                    claim_range["start"] > claim_range["end"]):
                raise ConsensusError("invalid consensus claim range")
            if claim["aliases"] != sorted(set(claim["aliases"])):
                raise ConsensusError("invalid consensus claim aliases")
            for key in ("blocks", "instructions", "edges", "calls"):
                if not isinstance(claim[key], list):
                    raise ConsensusError(f"invalid consensus claim {key}")
