"""Canonical, load-base-independent representations of analyzer output."""

from __future__ import annotations

from copy import deepcopy
import re

from binrecon.schema import validate_analysis_semantics, validate_document


class NormalizationError(ValueError):
    """Raised when analyzer evidence cannot be normalized unambiguously."""


_WIDTH = re.compile(r"(?:^|-)(8|16|32)(?:-|$)")


def _section_identity(section: dict) -> dict:
    return {"offset": section["offset"], "size": section["size"],
            "permissions": section["permissions"], "sha256": section["sha256"].upper()}


def _location(address: int, sections: list[dict]) -> dict:
    matches = [section for section in sections
               if section["address"] <= address < section["address"] + section["size"]]
    if len(matches) > 1:
        raise NormalizationError(f"address {address:#x} maps to overlapping sections")
    if not matches:
        return {"kind": "unmapped", "address": address}
    section = matches[0]
    return {"kind": "section", "section": _section_identity(section),
            "offset": address - section["address"]}


def _range(address: int, size: int, sections: list[dict]) -> dict:
    if size < 0:
        raise NormalizationError("negative range size")
    matches = [section for section in sections if
               section["address"] <= address and
               address + size <= section["address"] + section["size"]]
    if len(matches) != 1:
        raise NormalizationError(f"range {address:#x}+{size:#x} does not map to one section")
    section = matches[0]
    start = address - section["address"]
    return {"section": _section_identity(section), "start": start, "end": start + size}


def _relocation_width(document: dict, index: int, relocation: dict) -> int:
    candidates = []
    macho = document.get("extensions", {}).get("macho", {}).get("relocations", [])
    if index < len(macho) and isinstance(macho[index], dict) and "width" in macho[index]:
        candidates.append(macho[index]["width"])
    match = _WIDTH.search(relocation["kind"])
    if match:
        candidates.append(int(match.group(1)) // 8)
    if not candidates or any(not isinstance(value, int) or value not in (1, 2, 4)
                             for value in candidates) or len(set(candidates)) != 1:
        raise NormalizationError(f"relocation {index} has missing or conflicting width")
    return candidates[0]


def _target(document: dict, target, sections: list[dict]) -> dict:
    if target is None:
        return {"kind": "unresolved"}
    symbols = [symbol for symbol in document["symbols"] if symbol["name"] == target]
    mapped = []
    for symbol in symbols:
        if symbol["section"] is not None:
            mapped.append(_location(symbol["address"], sections))
    unique = {repr(item): item for item in mapped}
    if len(unique) > 1:
        raise NormalizationError(f"relocation target {target!r} is ambiguous")
    if unique:
        return next(iter(unique.values()))
    return {"kind": "external", "name": target}


def _normalize_instruction(document: dict, instruction: dict, sections: list[dict],
                           ownership: dict[int, int]) -> dict:
    address = instruction["address"]
    length = len(instruction["bytes"]) // 2
    fields = []
    for index in instruction["relocations"]:
        if index >= len(document["relocations"]):
            raise NormalizationError(f"relocation index {index} is out of range")
        relocation = document["relocations"][index]
        width = _relocation_width(document, index, relocation)
        start = relocation["address"]
        end = start + width
        if not (address <= start and end <= address + length):
            raise NormalizationError(f"relocation {index} is outside its instruction")
        if index in ownership:
            raise NormalizationError(f"relocation {index} has multiple instruction owners")
        ownership[index] = address
        fields.append((start, end, index, width, relocation))
    fields.sort()
    if any(right[0] < left[1] for left, right in zip(fields, fields[1:])):
        raise NormalizationError("relocation fields overlap")
    operands = [{"kind": "text", "value": instruction["normalized_operands"]}]
    if fields:
        if len(fields) != 1:
            raise NormalizationError("multiple relocation operands are ambiguous")
        _, _, _, width, relocation = fields[0]
        operands = [{"kind": "relocation", "width": width,
                     "signed": "pc-relative" in relocation["kind"].lower(),
                     "target": _target(document, relocation["target"], sections),
                     "addend": relocation["addend"]}]
    return {"location": _location(address, sections),
            "bytes": instruction["bytes"].upper(),
            "mnemonic": instruction["mnemonic"].lower(), "operands": operands,
            "display_operands": instruction["operands"],
            "normalized_operands": instruction["normalized_operands"],
            "relocations": list(instruction["relocations"])}


def normalize_analysis(document: dict) -> dict:
    """Return a deterministic normalized copy of an ``analysis-v1`` document."""
    try:
        validate_document("analysis-v1", document)
        validate_analysis_semantics(document)
    except Exception as error:
        raise NormalizationError(f"invalid analysis: {error}") from error
    source = deepcopy(document)
    sections = source["sections"]
    ownership: dict[int, int] = {}
    functions = []
    for function in source["functions"]:
        instructions = [_normalize_instruction(source, item, sections, ownership)
                        for item in function["instructions"]]
        edges = [{"source": _location(block["address"], sections),
                  "target": _location(successor["target"], sections),
                  "kind": successor["kind"]}
                 for block in function["blocks"] for successor in block["successors"]]
        calls = [{"source": _location(call["address"], sections),
                  "target": (_location(call["target"], sections)
                             if call["target"] is not None else
                             {"kind": "external", "name": call["name"]}),
                  "name": call["name"]} for call in function["calls"]]
        functions.append({"range": _range(function["address"], function["size"], sections),
                          "aliases": sorted(set(function["names"])),
                          "confidence": function["confidence"],
                          "blocks": sorted((_range(b["address"], b["size"], sections)
                                            for b in function["blocks"]), key=repr),
                          "instructions": sorted(instructions, key=lambda item: (
                              repr(item["location"].get("section")),
                              item["location"].get("offset", item["location"].get("address", -1)))),
                          "edges": sorted(edges, key=repr), "calls": sorted(calls, key=repr)})
    # A relocation whose field intersects an instruction must be explicitly owned by it.
    all_instructions = [item for function in source["functions"] for item in function["instructions"]]
    for index, relocation in enumerate(source["relocations"]):
        width = _relocation_width(source, index, relocation)
        rstart, rend = relocation["address"], relocation["address"] + width
        if any(rstart < i["address"] + len(i["bytes"]) // 2 and i["address"] < rend
               for i in all_instructions) and index not in ownership:
            raise NormalizationError(f"relocation {index} overlaps an instruction but is undeclared")
    normalized_sections = [{"identity": _section_identity(section), "name": section["name"]}
                           for section in sections]
    return {"schema_version": "normalized-analysis-v1",
            "input": {**source["input"], "sha256": source["input"]["sha256"].upper()},
            "analyzer": deepcopy(source["analyzer"]),
            "sections": sorted(normalized_sections, key=repr),
            "functions": sorted(functions, key=lambda item: repr(item["range"])),
            "references": sorted(({
                "source": _location(item["address"], sections),
                "target": (_location(item["target"], sections) if item["target"] is not None
                           else {"kind": "unresolved"}), "kind": item["kind"]}
                for item in source.get("references", [])), key=repr),
            "extensions": deepcopy(source.get("extensions", {}))}
