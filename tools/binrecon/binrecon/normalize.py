"""Canonical, load-base-independent representations of analyzer output."""

from __future__ import annotations

from copy import deepcopy
import re

from binrecon.schema import validate_analysis_semantics, validate_document


class NormalizationError(ValueError):
    """Raised when analyzer evidence cannot be normalized unambiguously."""


_WIDTH = re.compile(r"(?:^|[^0-9])(8|16|32)(?:[^0-9]|$)")


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


def _relocation_metadata(document: dict, index: int, relocation: dict) -> tuple[int, bool]:
    widths, relatives = [], []
    extensions = document.get("extensions", {})
    sources = [extensions.get("macho", {}).get("relocations", []),
               extensions.get("ghidra", {}).get("fallback_relocations", [])]
    for source in sources:
        if index >= len(source) or not isinstance(source[index], dict):
            continue
        metadata = source[index]
        for key in ("address", "target"):
            if key in metadata and metadata[key] != relocation[key]:
                raise NormalizationError(f"relocation {index} metadata {key} conflicts")
        if "width" in metadata:
            widths.append(metadata["width"])
        for key in ("pc_relative", "pcrel", "relative"):
            if key in metadata:
                if not isinstance(metadata[key], bool):
                    raise NormalizationError(f"relocation {index} has invalid {key}")
                relatives.append(metadata[key])
    match = _WIDTH.search(relocation["kind"])
    if match:
        widths.append(int(match.group(1)) // 8)
    if (not widths or any(isinstance(value, bool) or not isinstance(value, int) or
                          value not in (1, 2, 4) for value in widths) or
            len(set(widths)) != 1):
        raise NormalizationError(f"relocation {index} has missing or conflicting width")
    tokens = [token for token in re.split(r"[^a-z0-9]+", relocation["kind"].lower())
              if token]
    kind_relative = ("relative" in tokens or "pcrel" in tokens or
                     "pcrelative" in tokens or
                     any(left == "pc" and right == "relative"
                         for left, right in zip(tokens, tokens[1:])))
    if relatives and len(set(relatives)) != 1:
        raise NormalizationError(f"relocation {index} has conflicting relative metadata")
    if relatives and kind_relative != relatives[0] and any(
            token in tokens for token in ("relative", "pcrel", "pcrelative")):
        raise NormalizationError(f"relocation {index} relative metadata conflicts with kind")
    return widths[0], (relatives[0] if relatives else kind_relative)


def _split_operands(value: str) -> list[str]:
    if not value.strip():
        return []
    result, start, stack, quote, escaped = [], 0, [], None, False
    pairs = {")": "(", "]": "[", "}": "{"}
    for index, character in enumerate(value):
        if quote is not None:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == quote:
                quote = None
            continue
        if character in "'\"":
            quote = character
        elif character in "([{":
            stack.append(character)
        elif character in ")]}":
            if not stack or stack.pop() != pairs[character]:
                raise NormalizationError("malformed operand nesting")
        elif character == "," and not stack:
            result.append(value[start:index].strip()); start = index + 1
    if quote is not None or stack:
        raise NormalizationError("malformed operand nesting")
    result.append(value[start:].strip())
    if any(not item for item in result):
        raise NormalizationError("empty operand")
    return result


def _ghidra_operand_owner(document: dict, instruction: dict, relocation: dict) -> int | None:
    ghidra = document.get("extensions", {}).get("ghidra", {})
    entries = [item for item in ghidra.get("instruction_reference_indexes", [])
               if item.get("address") == instruction["address"]]
    if not entries:
        return None
    if len(entries) != 1:
        raise NormalizationError("Ghidra instruction reference metadata is ambiguous")
    target_addresses = {symbol["address"] for symbol in document["symbols"]
                        if symbol["name"] == relocation["target"]}
    reference_indexes = []
    for index in entries[0].get("reference_indexes", []):
        if (type(index) is not int or index < 0 or
                index >= len(document.get("references", []))):
            raise NormalizationError("Ghidra instruction reference index is invalid")
        reference = document["references"][index]
        if reference["target"] in target_addresses or (
                reference["target"] is None and not target_addresses):
            reference_indexes.append(index)
    metadata_by_index = {item.get("index"): item
                         for item in ghidra.get("reference_metadata", [])}
    owners = {operand for index in reference_indexes
              for operand in metadata_by_index.get(index, {}).get("operand_indexes", [])
              if type(operand) is int and operand >= 0}
    if len(owners) > 1:
        raise NormalizationError("Ghidra relocation operand metadata is ambiguous")
    return next(iter(owners)) if owners else None


def _operand_owner(relocation: dict, operands: list[str], assigned: set[int],
                   structured_owner: int | None = None) -> int:
    if len(operands) == 1:
        candidates = [0]
    elif relocation["target"]:
        target = relocation["target"].lower()
        pattern = re.compile(rf"(?<![a-z0-9_$]){re.escape(target)}(?![a-z0-9_$])")
        candidates = [index for index, operand in enumerate(operands)
                      if pattern.search(operand.lower()) is not None]
    else:
        candidates = []
    if structured_owner is not None:
        if structured_owner >= len(operands):
            raise NormalizationError("structured relocation operand index is out of range")
        if candidates and structured_owner not in candidates:
            raise NormalizationError("structured and textual relocation operands conflict")
        candidates = [structured_owner]
    candidates = [index for index in candidates if index not in assigned]
    if len(candidates) != 1:
        raise NormalizationError("relocation operand ownership is ambiguous")
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
                           ownership: dict[int, int], original_references: list[dict]) -> dict:
    address = instruction["address"]
    length = len(instruction["bytes"]) // 2
    fields = []
    for index in instruction["relocations"]:
        if index >= len(document["relocations"]):
            raise NormalizationError(f"relocation index {index} is out of range")
        relocation = document["relocations"][index]
        width, relative = _relocation_metadata(document, index, relocation)
        start = relocation["address"]
        end = start + width
        if not (address <= start and end <= address + length):
            raise NormalizationError(f"relocation {index} is outside its instruction")
        if index in ownership:
            raise NormalizationError(f"relocation {index} has multiple instruction owners")
        ownership[index] = address
        fields.append((start, end, index, width, relative, relocation))
    fields.sort()
    if any(right[0] < left[1] for left, right in zip(fields, fields[1:])):
        raise NormalizationError("relocation fields overlap")
    display_operands = _split_operands(instruction["operands"])
    normalized_operands = _split_operands(instruction["normalized_operands"])
    if len(display_operands) != len(normalized_operands):
        raise NormalizationError("display and normalized operand counts differ")
    operands = [{"text": text, "relocations": []} for text in display_operands]
    assigned = set()
    for start, _, index, width, relative, relocation in fields:
        owner = _operand_owner(relocation, normalized_operands, assigned,
                               _ghidra_operand_owner(document, instruction, relocation))
        assigned.add(owner)
        operands[owner]["relocations"].append({
            "index": index, "field_offset": start - address, "width": width,
            "signed": relative, "kind": relocation["kind"],
            "target": _target(document, relocation["target"], sections),
            "addend": relocation["addend"]})
    reference_indexes = [index for index, original in enumerate(original_references)
                         if address <= original["address"] < address + length]
    return {"location": _location(address, sections),
            "bytes": instruction["bytes"].upper(),
            "mnemonic": instruction["mnemonic"].lower(), "operands": operands,
            "display_operands": instruction["operands"],
            "normalized_operands": instruction["normalized_operands"],
            "relocations": list(instruction["relocations"]),
            "reference_indexes": reference_indexes}


def normalize_analysis(document: dict) -> dict:
    """Return a deterministic normalized copy of an ``analysis-v1`` document."""
    try:
        validate_document("analysis-v1", document)
        validate_analysis_semantics(document)
    except Exception as error:
        raise NormalizationError(f"invalid analysis: {error}") from error
    source = deepcopy(document)
    sections = source["sections"]
    original_references = source.get("references", [])
    normalized_references = [{"source": _location(item["address"], sections),
                              "target": (_location(item["target"], sections)
                                         if item["target"] is not None else
                                         {"kind": "external", "name": None}),
                              "kind": item["kind"]} for item in original_references]
    indexed_references = sorted(enumerate(normalized_references), key=lambda item: repr(item[1]))
    old_to_new = {old: new for new, (old, _) in enumerate(indexed_references)}
    normalized_references = [item for _, item in indexed_references]
    ownership: dict[int, int] = {}
    functions = []
    for function in source["functions"]:
        instructions = [_normalize_instruction(source, item, sections, ownership,
                                                original_references)
                        for item in function["instructions"]]
        for instruction in instructions:
            instruction["reference_indexes"] = sorted(
                old_to_new[index] for index in instruction["reference_indexes"])
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
        width, _ = _relocation_metadata(source, index, relocation)
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
            "references": normalized_references,
            "extensions": deepcopy(source.get("extensions", {}))}
