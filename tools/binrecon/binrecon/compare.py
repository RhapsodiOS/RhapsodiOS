"""Artifact-authoritative, relocation-aware binary comparison."""

from __future__ import annotations

from copy import deepcopy
import hashlib
from bisect import bisect_right
import json
import os
from pathlib import Path
import re
import stat

from binrecon.normalize import canonical_key, normalize_analysis, preflight_json


CATEGORIES = ("code", "relocation", "symbol-string-order", "layout", "padding", "metadata")
REQUIREMENTS = ("normalized-functions", "exact-sections", "exact-image")
MAX_EVIDENCE = 256
CHUNK_SIZE = 1024 * 1024
_STABLE_FIELDS = ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns")
_REASONS = {
    "analyzer bytes disagree with artifact", "instruction semantics differ",
    "instruction shape differs", "instruction layout differs", "instruction references differ",
    "cfg differs", "calls differ", "relocation target semantics differ",
    "relocation field bytes differ", "missing reference function", "missing rebuilt function",
    "overlapping functions", "section layout differs", "section content differs",
    "analyzer section hash disagrees with artifact", "header or load-command bytes differ",
    "bytes outside sections differ", "symbols reordered", "strings reordered",
    "imports reordered", "symbols differ", "strings differ", "imports differ",
    "relocations reordered", "relocations differ", "metadata differs",
    "function range bytes differ", "bytes within section ranges differ",
}
_FUNCTION_ORIGINS = {
    "code": {
        "analyzer bytes disagree with artifact", "instruction semantics differ",
        "instruction shape differs", "instruction layout differs", "instruction references differ",
        "cfg differs", "calls differ", "missing reference function", "missing rebuilt function",
        "overlapping functions", "function range bytes differ",
    },
    "relocation": {"relocation target semantics differ", "relocation field bytes differ"},
    "layout": {"overlapping functions"},
}
_SECTION_ORIGINS = {
    "layout": {"section layout differs"},
    "metadata": {"section content differs", "analyzer section hash disagrees with artifact"},
}
_NONRECORD_ORIGINS = {
    "code": set(),
    "relocation": {"relocations reordered", "relocations differ"},
    "symbol-string-order": {"symbols reordered", "strings reordered"},
    "layout": set(),
    "padding": {"bytes outside sections differ"},
    "metadata": {"header or load-command bytes differ", "imports reordered", "symbols differ",
                 "strings differ", "imports differ", "metadata differs",
                 "bytes within section ranges differ"},
}
_CATEGORY_REASONS = {
    category: (_FUNCTION_ORIGINS.get(category, set()) |
               _SECTION_ORIGINS.get(category, set()) |
               _NONRECORD_ORIGINS[category])
    for category in CATEGORIES
}
_ARTIFACT_BYTE_REASONS = {
    "metadata": {"header or load-command bytes differ", "bytes within section ranges differ"},
    "padding": {"bytes outside sections differ"},
}


class ComparisonError(ValueError):
    """Raised for unsafe input or incoherent comparison evidence."""


class _CategoryStore(dict):
    def __init__(self):
        super().__init__((name, []) for name in CATEGORIES)
        self.totals = {name: 0 for name in CATEGORIES}
        self.reason_totals = {name: {} for name in CATEGORIES}
        self.seen = {name: set() for name in CATEGORIES}

    def add(self, evidence):
        category = evidence["category"]; key = canonical_key(evidence)
        if key in self.seen[category]: return
        self.seen[category].add(key); self.totals[category] += 1
        reason = evidence["reason"]
        self.reason_totals[category][reason] = self.reason_totals[category].get(reason, 0) + 1
        if len(self[category]) < MAX_EVIDENCE: self[category].append(evidence)


class _Artifact:
    def __init__(self, path: Path):
        if path.is_symlink():
            raise ComparisonError(f"artifact is a symlink: {path}")
        self.path = path.resolve(strict=True)
        flags = (os.O_RDONLY | getattr(os, "O_BINARY", 0) |
                 getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOFOLLOW", 0))
        self.fd = os.open(self.path, flags)
        self.initial = os.fstat(self.fd)
        if not stat.S_ISREG(self.initial.st_mode):
            os.close(self.fd); raise ComparisonError(f"artifact is not a regular file: {path}")
        self.identity = None

    def read_at(self, offset: int, size: int) -> bytes:
        if type(offset) is not int or type(size) is not int or offset < 0 or size < 0:
            raise ComparisonError("invalid artifact read range")
        if offset + size > self.initial.st_size:
            raise ComparisonError("artifact read is outside file")
        os.lseek(self.fd, offset, os.SEEK_SET)
        chunks, remaining = [], size
        while remaining:
            chunk = os.read(self.fd, min(CHUNK_SIZE, remaining))
            if not chunk: raise ComparisonError("artifact ended during bounded read")
            chunks.append(chunk); remaining -= len(chunk)
        return b"".join(chunks)

    def hash_all(self):
        digest = hashlib.sha256(); count = 0
        os.lseek(self.fd, 0, os.SEEK_SET)
        while True:
            chunk = os.read(self.fd, CHUNK_SIZE)
            if not chunk: break
            digest.update(chunk); count += len(chunk)
        if count != self.initial.st_size:
            raise ComparisonError(f"artifact changed while comparing: {self.path}")
        self.identity = {"path": str(self.path), "size": count,
                         "sha256": digest.hexdigest().upper()}
        return self.identity

    def verify_stable(self):
        final = os.fstat(self.fd)
        if any(getattr(self.initial, field) != getattr(final, field) for field in _STABLE_FIELDS):
            raise ComparisonError(f"artifact changed while comparing: {self.path}")

    def close(self):
        os.close(self.fd)


class _ArtifactPair:
    def __init__(self, reference, rebuilt):
        self.left = _Artifact(Path(reference))
        try: self.right = _Artifact(Path(rebuilt))
        except BaseException:
            self.left.close(); raise
        if ((self.left.initial.st_dev, self.left.initial.st_ino) ==
                (self.right.initial.st_dev, self.right.initial.st_ino)):
            self.left.close(); self.right.close(); raise ComparisonError("artifacts alias each other")

    def identities_and_differences(self):
        left_identity = self.left.hash_all(); right_identity = self.right.hash_all()
        return (left_identity, right_identity), self._iter_differences(left_identity, right_identity)

    def _iter_differences(self, left_identity, right_identity):
        offset = 0
        run_start = None
        while offset < max(left_identity["size"], right_identity["size"]):
            left_size = min(CHUNK_SIZE, max(0, left_identity["size"] - offset))
            right_size = min(CHUNK_SIZE, max(0, right_identity["size"] - offset))
            a = self.left.read_at(offset, left_size); b = self.right.read_at(offset, right_size)
            index, limit = 0, max(len(a), len(b))
            while index < limit:
                av = a[index] if index < len(a) else None; bv = b[index] if index < len(b) else None
                if av != bv and run_start is None: run_start = offset + index
                if av == bv and run_start is not None:
                    yield {"start": run_start, "end": offset + index}; run_start = None
                index += 1
            offset += limit
        if run_start is not None:
            yield {"start": run_start, "end": max(left_identity["size"], right_identity["size"])}

    def close_verified(self):
        error = None
        try:
            self.left.verify_stable(); self.right.verify_stable()
        except BaseException as caught: error = caught
        finally:
            self.left.close(); self.right.close()
        if error is not None: raise error

    def close_unverified(self):
        self.left.close(); self.right.close()


def _identity_check(label, document, identity):
    value = document.get("input", {})
    if (value.get("size") != identity["size"] or
            str(value.get("sha256", "")).upper() != identity["sha256"]):
        raise ComparisonError(f"{label} analysis identity does not match artifact")


def _section_metadata_key(value):
    try: return tuple(value[key] for key in ("name", "address", "offset", "size"))
    except (KeyError, TypeError): raise ComparisonError("invalid section backing metadata") from None


def _section_backing_metadata(document):
    extensions = document.get("extensions", {})
    sources = [
        (extensions.get("macho", {}).get("sections", []), False),
        (extensions.get("ghidra", {}).get("fallback_sections", []), True),
        (extensions.get("ida", {}).get("sections", []), True),
    ]
    angr = extensions.get("angr", {})
    loader = angr.get("loader", {}) if isinstance(angr, dict) else None
    if loader is None or not isinstance(loader, dict):
        raise ComparisonError("invalid section backing metadata")
    if "sections" in loader:
        entries = loader["sections"]
        if not isinstance(entries, list) or len(entries) != len(document["sections"]):
            raise ComparisonError("invalid section backing metadata")
        core_by_structure = {}
        for section in document["sections"]:
            key = tuple(section[field] for field in ("address", "size", "permissions"))
            core_by_structure.setdefault(key, []).append(section)
        loader_by_structure = {}
        for item in entries:
            if (not isinstance(item, dict) or
                    any(type(item.get(field)) is not int or item[field] < 0
                        for field in ("address", "size")) or
                    not isinstance(item.get("permissions"), str) or
                    type(item.get("initialized")) is not bool):
                raise ComparisonError("invalid section backing metadata")
            key = tuple(item[field] for field in ("address", "size", "permissions"))
            loader_by_structure.setdefault(key, []).append(item["initialized"])
        if ({key: len(values) for key, values in core_by_structure.items()} !=
                {key: len(values) for key, values in loader_by_structure.items()}):
            raise ComparisonError("conflicting section backing metadata")
        canonical = []
        for key, sections in core_by_structure.items():
            initialized = loader_by_structure[key]
            if len(set(initialized)) != 1:
                raise ComparisonError("conflicting section backing metadata")
            for section in sections:
                canonical.append({**{field: section[field]
                                      for field in ("name", "address", "offset", "size")},
                                  "zero_fill": not initialized[0],
                                  "initialized": initialized[0]})
        sources.append((canonical, True))
    core = {_section_metadata_key(section) for section in document["sections"]}
    result = {}
    for entries, complete in sources:
        if not isinstance(entries, list):
            raise ComparisonError("invalid section backing metadata")
        for item in entries:
            if not isinstance(item, dict):
                raise ComparisonError("invalid section backing metadata")
            key = _section_metadata_key(item)
            if key not in core:
                raise ComparisonError("section backing metadata does not match a section")
            if key in result:
                raise ComparisonError("ambiguous section backing metadata")
            zero_fill, initialized = item.get("zero_fill"), item.get("initialized")
            if (complete and (type(zero_fill) is not bool or type(initialized) is not bool)):
                raise ComparisonError("invalid section backing metadata")
            if ((zero_fill is not None and type(zero_fill) is not bool) or
                    (initialized is not None and type(initialized) is not bool) or
                    (zero_fill is not None and initialized is not None and
                     zero_fill == initialized)):
                raise ComparisonError("conflicting section backing metadata")
            result[key] = item
    return result


def _alignment(metadata, section):
    value = metadata.get(_section_metadata_key(section), {}).get("alignment", 1)
    return value if type(value) is int and value > 0 else 1


def _section_infos(document, artifact):
    metadata = _section_backing_metadata(document)
    zeros = {key for key, item in metadata.items() if item.get("zero_fill") is True}
    infos = []
    name_occurrences = {}
    groups = {}
    for index, section in enumerate(document["sections"]):
        groups.setdefault(section["name"], []).append((section["offset"], section["address"], index))
    for values in groups.values():
        ordered = sorted(values)
        if any(left[:2] == right[:2] for left, right in zip(ordered, ordered[1:])):
            raise ComparisonError("ambiguous same-name section structural order")
        for occurrence, (_, _, index) in enumerate(ordered): name_occurrences[index] = occurrence
    backed_ranges = []
    for order, section in enumerate(document["sections"]):
        occurrence = name_occurrences[order]
        zero = (section["name"], section["address"], section["offset"], section["size"]) in zeros
        if zero:
            digest = hashlib.sha256()
            remaining = section["size"]; block = b"\0" * min(CHUNK_SIZE, max(1, remaining))
            while remaining:
                size = min(remaining, len(block)); digest.update(block[:size]); remaining -= size
            actual_hash = digest.hexdigest().upper()
        else:
            start, end = section["offset"], section["offset"] + section["size"]
            if start < 0 or end > artifact.initial.st_size:
                raise ComparisonError("file-backed section is outside artifact")
            if start < end: backed_ranges.append((start, end))
            digest = hashlib.sha256(); position = start
            while position < end:
                chunk = artifact.read_at(position, min(CHUNK_SIZE, end - position))
                digest.update(chunk); position += len(chunk)
            actual_hash = digest.hexdigest().upper()
        descriptor = {"name": section["name"], "name_occurrence": occurrence, "order": order,
                      "address": section["address"], "offset": section["offset"],
                      "size": section["size"], "permissions": section["permissions"],
                      "alignment": _alignment(metadata, section),
                      "backing": "zero-fill" if zero else "file", "sha256": actual_hash}
        identity_key = (section["name"], section["offset"], section["size"],
                        section["permissions"], section["sha256"].upper())
        infos.append({"raw": section, "descriptor": descriptor, "identity_key": identity_key,
                      "zero": zero, "analyzer_hash_valid": section["sha256"].upper() == actual_hash})
    backed_ranges.sort()
    for first, second in zip(backed_ranges, backed_ranges[1:]):
        if first[1] > second[0]: raise ComparisonError("file-backed sections overlap")
    return infos, backed_ranges


def _normalized_section_map(normalized, infos):
    result = {}
    grouped = {}
    for info in infos: grouped.setdefault(info["identity_key"], []).append(info)
    for values in grouped.values(): values.sort(key=lambda item: item["raw"]["address"])
    for item in normalized["sections"]:
        identity = item["identity"]
        key = (identity["name"], identity["offset"], identity["size"],
               identity["permissions"], identity["sha256"])
        try: info = grouped[key][identity["occurrence"]]
        except (KeyError, IndexError): raise ComparisonError("normalized section identity is unavailable") from None
        result[canonical_key(identity)] = info
    return result


def _section_info(section_map, identity):
    try: return section_map[canonical_key(identity)]
    except KeyError: raise ComparisonError("comparator section identity is unavailable") from None


def _section_tag(identity, section_map):
    descriptor = _section_info(section_map, identity)["descriptor"]
    return {"name": descriptor["name"], "name_occurrence": descriptor["name_occurrence"]}


def _function_key(function, section_map):
    value = function["range"]
    tag = _section_tag(value["section"], section_map)
    return (tag["name"], tag["name_occurrence"], value["start"], value["end"])


def _printable_function(key):
    return {"section": key[0], "name_occurrence": key[1], "start": key[2], "end": key[3]}


def _portable(value, section_map):
    if isinstance(value, dict):
        if value.get("kind") == "section":
            return {"kind": "section", "section": _section_tag(value["section"], section_map),
                    "offset": value["offset"]}
        if set(value) >= {"section", "start", "end"}:
            return {"section": _section_tag(value["section"], section_map), "start": value["start"], "end": value["end"]}
        return {key: _portable(item, section_map) for key, item in value.items()
                if key not in ("aliases", "confidence", "display_operands", "reference_indexes")}
    if isinstance(value, list): return [_portable(item, section_map) for item in value]
    return value


def _actual_instructions(function, section_map, artifact):
    result, inconsistencies = [], []
    key = _printable_function(_function_key(function, section_map))
    for instruction in function["instructions"]:
        if instruction["location"]["kind"] != "section":
            raise ComparisonError("instruction is not mapped to an owning section")
        identity = instruction["location"]["section"]
        try: info = section_map[canonical_key(identity)]
        except KeyError: raise ComparisonError("instruction owning section is unavailable") from None
        length = len(instruction["bytes"]) // 2
        if length <= 0: raise ComparisonError("instruction has no bytes")
        section_offset = instruction["location"]["offset"]
        if section_offset < 0 or section_offset + length > info["raw"]["size"]:
            raise ComparisonError("instruction crosses its owning section")
        if info["zero"]:
            raise ComparisonError("executable instruction in zero-fill section is unsupported")
        file_offset = info["raw"]["offset"] + section_offset
        actual = artifact.read_at(file_offset, length)
        analyzer = bytes.fromhex(instruction["bytes"])
        if analyzer != actual:
            inconsistencies.append(_instruction_evidence(
                "analyzer-inconsistency", "code", "analyzer bytes disagree with artifact",
                key, _section_tag(identity, section_map), file_offset, file_offset + length,
                analyzer.hex().upper(), actual.hex().upper()))
        result.append((instruction, actual, info))
    return result, inconsistencies


def _masked(instruction, actual, section_map):
    raw = bytearray(actual); occupied = set(); semantics = []
    for relocation in instruction["relocations"]:
        start, width = relocation["field_offset"], relocation["width"]
        if type(start) is not int or type(width) is not int or width not in (1, 2, 4):
            raise ComparisonError("relocation field width is invalid")
        indexes = set(range(start, start + width))
        if start < 0 or start + width > len(raw): raise ComparisonError("relocation field is outside instruction")
        if indexes & occupied: raise ComparisonError("relocation fields overlap")
        occupied |= indexes; raw[start:start + width] = b"\0" * width
        semantics.append(_portable(relocation, section_map))
    return bytes(raw), semantics


def _referenced(instruction, references, section_map):
    values = []
    for index in instruction["reference_indexes"]:
        if type(index) is not int or index < 0 or index >= len(references):
            raise ComparisonError("instruction reference index is invalid")
        values.append(_portable(references[index], section_map))
    return sorted(values, key=canonical_key)


def _instruction_evidence(kind, category, reason, function, section, start, end, reference, rebuilt):
    return {"kind": kind, "category": category, "scope": "instruction", "reason": reason,
            "function": function, "section": section, "start": start, "end": end,
            "reference": reference, "rebuilt": rebuilt}


def _function_evidence(category, reason, function, reference, rebuilt):
    return {"kind": "function-structure", "category": category, "scope": "function",
            "reason": reason, "function": function, "reference": reference, "rebuilt": rebuilt}


def _layout_evidence(index, reference, rebuilt):
    return {"kind": "section-layout", "category": "layout", "scope": "section",
            "reason": "section layout differs", "path": f"/sections/{index}",
            "reference": reference, "rebuilt": rebuilt}


def _section_content_evidence(index, reference, rebuilt):
    return {"kind": "section-content", "category": "metadata", "scope": "section",
            "reason": "section content differs", "path": f"/sections/{index}",
            "reference": reference, "rebuilt": rebuilt}


def _collection_summary(value):
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
    count = len(value) if isinstance(value, (list, dict)) else 1
    return f"count={count};sha256={hashlib.sha256(encoded).hexdigest().upper()}"


def _collection_evidence(category, reason, path, reference, rebuilt):
    return {"kind": "collection-difference", "category": category, "scope": "metadata",
            "reason": reason, "path": path, "reference": _collection_summary(reference),
            "rebuilt": _collection_summary(rebuilt)}


def _byte_evidence(category, reason, difference):
    kind = "section-byte-range" if reason == "bytes within section ranges differ" else "byte-range"
    return {"kind": kind, "category": category, "scope": "artifact", "reason": reason,
            "start": difference["start"], "end": difference["end"],
            "reference": difference["reference"], "rebuilt": difference["rebuilt"]}


def _emit_byte_differences(differences, left_ranges, right_ranges, pair, categories):
    ranges = sorted(left_ranges + right_ranges)
    merged = []
    for start, end in ranges:
        if merged and start <= merged[-1][1]: merged[-1] = (merged[-1][0], max(end, merged[-1][1]))
        else: merged.append((start, end))
    starts = [start for start, _ in merged]
    boundaries = sorted({point for region in ranges for point in region})
    first_section = starts[0] if starts else None
    for difference in differences:
        points = [difference["start"], *(point for point in boundaries
                  if difference["start"] < point < difference["end"]), difference["end"]]
        for start, end in zip(points, points[1:]):
            position = bisect_right(starts, start) - 1
            in_section = position >= 0 and start < merged[position][1]
            if in_section:
                category, reason = "metadata", "bytes within section ranges differ"
            elif first_section is None or start < first_section:
                category, reason = "metadata", "header or load-command bytes differ"
            else:
                category, reason = "padding", "bytes outside sections differ"
            left_size = min(32, max(0, min(end, pair.left.initial.st_size) - start))
            right_size = min(32, max(0, min(end, pair.right.initial.st_size) - start))
            piece = {"start": start, "end": end,
                     "reference": pair.left.read_at(start, left_size).hex().upper() if left_size else "",
                     "rebuilt": pair.right.read_at(start, right_size).hex().upper() if right_size else ""}
            _add(categories, _byte_evidence(category, reason, piece))


def _add(categories, evidence):
    if isinstance(categories, _CategoryStore):
        categories.add(evidence); return
    values = categories[evidence["category"]]
    if len(values) < MAX_EVIDENCE and evidence not in values: values.append(evidence)


def _reason_snapshot(categories):
    return {category: dict(categories.reason_totals[category]) for category in CATEGORIES}


def _reason_delta(before, categories):
    result = {}
    for category in CATEGORIES:
        values = {}
        for reason, count in categories.reason_totals[category].items():
            difference = count - before[category].get(reason, 0)
            if difference: values[reason] = difference
        if values: result[category] = dict(sorted(values.items()))
    return result


def _occupied_intervals(function):
    envelope = function["range"]
    section = canonical_key(envelope["section"])

    def checked(values, label):
        result = []
        for value in values:
            if canonical_key(value["section"]) != section:
                raise ComparisonError(f"function {label} crosses its owning section")
            start, end = value["start"], value["end"]
            if (start < envelope["start"] or end > envelope["end"] or start >= end):
                raise ComparisonError(f"function {label} is outside its envelope")
            result.append((start, end))
        if result != sorted(result) or any(left[1] > right[0]
                                           for left, right in zip(result, result[1:])):
            raise ComparisonError(f"function {label} intervals are noncanonical")
        return result

    blocks = checked(function["blocks"], "block")
    instruction_ranges = []
    for instruction in function["instructions"]:
        location = instruction["location"]
        if location.get("kind") != "section":
            raise ComparisonError("function instruction is not section-backed")
        length = len(instruction["bytes"]) // 2
        instruction_ranges.append({"section": location["section"],
                                   "start": location["offset"],
                                   "end": location["offset"] + length})
    instructions = checked(instruction_ranges, "instruction")
    if not blocks and not instructions:
        return None
    merged = []
    for start, end in sorted(blocks + instructions):
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return tuple(merged)


def _intervals_overlap(first, second):
    left = right = 0
    while left < len(first) and right < len(second):
        if first[left][1] <= second[right][0]:
            left += 1
        elif second[right][1] <= first[left][0]:
            right += 1
        else:
            return True
    return False


def _overlaps(functions, section_map):
    values = sorted(((_function_key(item, section_map), _occupied_intervals(item))
                     for item in functions), key=lambda value: value[0])
    result = set()
    for index, (first, first_occupied) in enumerate(values):
        for second, second_occupied in values[index + 1:]:
            if second[:2] != first[:2]: continue
            if second[2] >= first[3]: break
            if (first_occupied is None or second_occupied is None or
                    _intervals_overlap(first_occupied, second_occupied)):
                result.update((first, second))
    return result


def _function_masks(function, instructions, section_map):
    start, end = function["range"]["start"], function["range"]["end"]
    intervals, masks = [], []
    for instruction, actual, _ in instructions:
        offset = instruction["location"]["offset"]
        interval = (offset, offset + len(actual))
        if interval[0] < start or interval[1] > end or interval[0] >= interval[1]:
            raise ComparisonError("instruction is outside function range")
        intervals.append(interval)
        for relocation in instruction["relocations"]:
            field = offset - start + relocation["field_offset"]
            width = relocation["width"]
            if field < 0 or field + width > end - start:
                raise ComparisonError("relocation field is outside function range")
            semantics = {key: _portable(value, section_map) for key, value in relocation.items()
                         if key not in ("field_offset", "width")}
            masks.append((field, width, canonical_key(semantics)))
    if intervals != sorted(intervals) or any(a[1] > b[0] for a, b in zip(intervals, intervals[1:])):
        raise ComparisonError("function instruction intervals overlap or are noncanonical")
    masks.sort()
    if any(a[0] + a[1] > b[0] for a, b in zip(masks, masks[1:])):
        raise ComparisonError("function relocation fields overlap")
    return masks


def _apply_masks(chunk, chunk_start, masks):
    value = bytearray(chunk)
    for field, width, _ in masks:
        if field >= chunk_start + len(value): break
        if field + width <= chunk_start: continue
        left = max(field, chunk_start) - chunk_start
        right = min(field + width, chunk_start + len(value)) - chunk_start
        value[left:right] = b"\0" * (right - left)
    return bytes(value)


def _compare_function_range(left_function, right_function, left_instructions, right_instructions,
                            left_map, right_map, pair, printable):
    left_info = _section_info(left_map, left_function["range"]["section"])
    right_info = _section_info(right_map, right_function["range"]["section"])
    if left_info["zero"] or right_info["zero"]:
        raise ComparisonError("function range cannot be zero-fill")
    size = left_function["range"]["end"] - left_function["range"]["start"]
    if size != right_function["range"]["end"] - right_function["range"]["start"]:
        raise ComparisonError("matched function ranges have different sizes")
    left_masks = _function_masks(left_function, left_instructions, left_map)
    right_masks = _function_masks(right_function, right_instructions, right_map)
    left_by_field = {(field, width): semantics for field, width, semantics in left_masks}
    right_by_field = {(field, width): semantics for field, width, semantics in right_masks}
    compatible = sorted((field, width, semantics) for (field, width), semantics in left_by_field.items()
                        if right_by_field.get((field, width)) == semantics)
    left_offset = left_info["raw"]["offset"] + left_function["range"]["start"]
    right_offset = right_info["raw"]["offset"] + right_function["range"]["start"]
    raw_left = hashlib.sha256(); raw_right = hashlib.sha256()
    masked_left = hashlib.sha256(); masked_right = hashlib.sha256()
    raw_equal = True; masked_equal = True; first_difference = None
    position = 0
    while position < size:
        amount = min(CHUNK_SIZE, size - position)
        a = pair.left.read_at(left_offset + position, amount)
        b = pair.right.read_at(right_offset + position, amount)
        raw_left.update(a); raw_right.update(b)
        am = _apply_masks(a, position, compatible); bm = _apply_masks(b, position, compatible)
        masked_left.update(am); masked_right.update(bm)
        raw_equal &= a == b; masked_equal &= am == bm
        if first_difference is None and am != bm:
            index = next(i for i, (x, y) in enumerate(zip(am, bm)) if x != y)
            difference_end = index + 1
            while difference_end < len(am) and am[difference_end] != bm[difference_end]:
                difference_end += 1
            first_difference = _instruction_evidence(
                "function-range", "code", "function range bytes differ", printable,
                _section_tag(left_function["range"]["section"], left_map), position + index,
                position + difference_end, am[index:min(difference_end, index + 32)].hex().upper(),
                bm[index:min(difference_end, index + 32)].hex().upper())
        position += amount
    return {"raw_equal": raw_equal, "masked_equal": masked_equal,
            "reference_sha256": raw_left.hexdigest().upper(),
            "rebuilt_sha256": raw_right.hexdigest().upper(),
            "reference_masked_sha256": masked_left.hexdigest().upper(),
            "rebuilt_masked_sha256": masked_right.hexdigest().upper(),
            "evidence": first_difference}


def _compare_functions(left, right, left_map, right_map, pair, categories):
    lm = {_function_key(item, left_map): item for item in left["functions"]}
    rm = {_function_key(item, right_map): item for item in right["functions"]}
    overlaps = _overlaps(left["functions"], left_map) | _overlaps(right["functions"], right_map); records = []
    for key in sorted(set(lm) | set(rm)):
        finding_before = _reason_snapshot(categories)
        a, b = lm.get(key), rm.get(key); printable = _printable_function(key); reasons = []
        if a is None or b is None:
            reason = "missing reference function" if a is None else "missing rebuilt function"
            _add(categories, _function_evidence("code", reason, printable,
                 "absent" if a is None else "present", "absent" if b is None else "present"))
            status = "missing-reference" if a is None else "missing-rebuilt"
            range_result = {"raw_equal": False, "masked_equal": False,
                "reference_sha256": None, "rebuilt_sha256": None,
                "reference_masked_sha256": None, "rebuilt_masked_sha256": None}
            semantics_equal = cfg_equal = calls_equal = False; reasons = [reason]
        else:
            ai, ae = _actual_instructions(a, left_map, pair.left)
            bi, be = _actual_instructions(b, right_map, pair.right)
            relocation_candidates = []
            for item in ae + be: _add(categories, item)
            if ae or be: reasons.append("analyzer bytes disagree with artifact")
            if len(ai) != len(bi): reasons.append("instruction shape differs")
            else:
                for (ia, ab, info_a), (ib, bb, info_b) in zip(ai, bi):
                    if _portable(ia["location"], left_map) != _portable(ib["location"], right_map):
                        reasons.append("instruction layout differs"); continue
                    am, ar = _masked(ia, ab, left_map); bm, br = _masked(ib, bb, right_map)
                    start = info_a["raw"]["offset"] + ia["location"]["offset"]
                    if (ia["mnemonic"] != ib["mnemonic"] or
                            ia["normalized_operands"] != ib["normalized_operands"]):
                        reasons.append("instruction semantics differ")
                        _add(categories, _instruction_evidence("instruction-bytes", "code",
                             "instruction semantics differ", printable, _section_tag(ia["location"]["section"], left_map),
                             start, start + len(ab), ab.hex().upper(), bb.hex().upper()))
                    elif ab != bb and am == bm and ar == br and (ia["relocations"] or ib["relocations"]):
                        relocation_candidates.append(_instruction_evidence("relocation-bytes", "relocation",
                             "relocation field bytes differ", printable, _section_tag(ia["location"]["section"], left_map),
                             start, start + len(ab), ab.hex().upper(), bb.hex().upper()))
                    if ar != br: reasons.append("relocation target semantics differ")
                    if _referenced(ia, left["references"], left_map) != _referenced(ib, right["references"], right_map):
                        reasons.append("instruction references differ")
            cfg_equal = (_portable(a["blocks"], left_map) == _portable(b["blocks"], right_map) and
                         _portable(a["edges"], left_map) == _portable(b["edges"], right_map))
            if not cfg_equal:
                reasons.append("cfg differs")
            calls_equal = _canonical_calls(a["calls"], left_map) == _canonical_calls(b["calls"], right_map)
            if not calls_equal: reasons.append("calls differ")
            range_result = _compare_function_range(a, b, ai, bi, left_map, right_map, pair, printable)
            if range_result["masked_equal"]:
                for candidate in relocation_candidates:
                    _add(categories, candidate)
            if range_result["evidence"] is not None:
                reasons.append("function range bytes differ"); _add(categories, range_result["evidence"])
            if key in overlaps: reasons.append("overlapping functions")
            semantics_equal = not any(reason in reasons for reason in
                ("analyzer bytes disagree with artifact", "instruction shape differs",
                 "instruction layout differs", "instruction semantics differ",
                 "relocation target semantics differ", "instruction references differ"))
            for reason in sorted(set(reasons)):
                category = "relocation" if reason == "relocation target semantics differ" else "code"
                _add(categories, _function_evidence(category, reason, printable, "different", "different"))
            if key in overlaps:
                _add(categories, _function_evidence("layout", "overlapping functions", printable,
                                                    "overlap", "overlap"))
            status = "different" if reasons else "assembly-matched"
        records.append({"key": printable, "status": status,
                        "reference_aliases": [] if a is None else a["aliases"],
                        "rebuilt_aliases": [] if b is None else b["aliases"],
                        "reasons": sorted(set(reasons)), "raw_equal": range_result["raw_equal"],
                        "masked_equal": range_result["masked_equal"],
                        "semantics_equal": semantics_equal, "cfg_equal": cfg_equal,
                        "calls_equal": calls_equal,
                        "reference_sha256": range_result["reference_sha256"],
                        "rebuilt_sha256": range_result["rebuilt_sha256"],
                        "reference_masked_sha256": range_result["reference_masked_sha256"],
                        "rebuilt_masked_sha256": range_result["rebuilt_masked_sha256"],
                        "finding_counts": _reason_delta(finding_before, categories)})
    return records


def _canonical_calls(calls, section_map):
    result = []
    for call in calls:
        target = _portable(call["target"], section_map)
        concrete = target.get("kind") in ("section", "unmapped")
        result.append({"source": _portable(call["source"], section_map), "target": target,
                       "external_name": None if concrete else (target.get("name") or call["name"])})
    return sorted(result, key=canonical_key)


def _decode_pointer(path):
    if not isinstance(path, str) or not path.startswith("/") or path == "/":
        raise ComparisonError("invalid metadata ignore path")
    result = []
    for token in path[1:].split("/"):
        if re.search(r"~(?![01])", token): raise ComparisonError("invalid metadata ignore escape")
        result.append(token.replace("~1", "/").replace("~0", "~"))
    return result


def _filtered_extensions(document):
    extensions = deepcopy(document.get("extensions", {}))
    for key in ("ida", "IDA", "ghidra", "Ghidra", "angr", "macho"):
        if key == "macho" and isinstance(extensions.get(key), dict):
            extensions[key].pop("sections", None); extensions[key].pop("relocations", None)
            if not extensions[key]: extensions.pop(key, None)
        else: extensions.pop(key, None)
    return extensions


def _metadata_roots(document):
    return {"input": {"architecture": document["input"]["architecture"],
                      "endianness": document["input"]["endianness"]},
            "analyzer": {"version": document["analyzer"]["version"]},
            "extensions": _filtered_extensions(document)}


def _apply_ignores(left, right, paths):
    if len(paths) != len(set(paths)): raise ComparisonError("duplicate metadata ignore path")
    for path in paths:
        parts = _decode_pointer(path)
        if parts[0] not in ("analyzer", "extensions"):
            raise ComparisonError("metadata ignore path targets protected evidence")
        parents = []
        for root in (left, right):
            target = root
            for part in parts[:-1]:
                if not isinstance(target, dict) or part not in target:
                    raise ComparisonError("metadata ignore path does not exist")
                target = target[part]
            leaf = parts[-1]
            if not isinstance(target, dict) or leaf not in target:
                raise ComparisonError("metadata ignore path does not exist")
            if isinstance(target[leaf], (dict, list)):
                raise ComparisonError("metadata ignore path is overbroad")
            parents.append((target, leaf))
        for target, leaf in parents: del target[leaf]


def _metadata_differences(left_doc, right_doc, ignores, categories):
    collections = (("symbols", "metadata"), ("strings", "metadata"),
                   ("imports", "metadata"), ("relocations", "relocation"))
    for name, category in collections:
        a, b = left_doc.get(name, []), right_doc.get(name, [])
        if name == "relocations":
            a, b = _canonical_relocations(left_doc), _canonical_relocations(right_doc)
        if a == b: continue
        path = f"/{name}"
        if sorted(map(canonical_key, a)) == sorted(map(canonical_key, b)):
            reason = f"{name} reordered"
            order_category = ("relocation" if name == "relocations" else
                              "metadata" if name == "imports" else "symbol-string-order")
            _add(categories, _collection_evidence(order_category, reason, path, a, b))
        else:
            _add(categories, _collection_evidence(category, f"{name} differ", path, a, b))
    left, right = _metadata_roots(left_doc), _metadata_roots(right_doc)
    _apply_ignores(left, right, list(ignores))
    if left != right:
        _add(categories, _collection_evidence("metadata", "metadata differs", "/metadata", left, right))


def _canonical_relocations(document):
    groups = {}
    for index, section in enumerate(document["sections"]):
        groups.setdefault(section["name"], []).append((section["offset"], section["address"], index))
    occurrences = {}
    for values in groups.values():
        for occurrence, (_, _, index) in enumerate(sorted(values)): occurrences[index] = occurrence
    sections = [(section, occurrences[index]) for index, section in enumerate(document["sections"])]
    result = []
    for relocation in document.get("relocations", []):
        matches = [(section, occurrence) for section, occurrence in sections
                   if section["address"] <= relocation["address"] < section["address"] + section["size"]]
        if len(matches) != 1: raise ComparisonError("standalone relocation is not in one section")
        section, occurrence = matches[0]
        result.append({"section": {"name": section["name"], "name_occurrence": occurrence},
                       "offset": relocation["address"] - section["address"],
                       "kind": relocation["kind"], "target": relocation["target"],
                       "addend": relocation["addend"]})
    return result


def _validate_section_descriptor(value):
    fields = {"name", "name_occurrence", "order", "address", "offset", "size", "permissions",
              "alignment", "backing", "sha256"}
    if not isinstance(value, dict) or set(value) != fields: raise ComparisonError("invalid section descriptor")
    if (not isinstance(value["name"], str) or not isinstance(value["permissions"], str) or
            any(type(value[key]) is not int or value[key] < 0 for key in
                ("name_occurrence", "order", "address", "offset", "size")) or
            type(value["alignment"]) is not int or value["alignment"] <= 0 or
            value["backing"] not in ("file", "zero-fill") or
            re.fullmatch(r"[0-9A-F]{64}", value["sha256"]) is None):
        raise ComparisonError("invalid section descriptor")


def compare_artifacts(reference_path, rebuilt_path, reference_analysis, rebuilt_analysis,
                      requirement, ignore_metadata=()):
    if requirement not in REQUIREMENTS: raise ComparisonError("invalid acceptance requirement")
    preflight_json(reference_analysis, ComparisonError); preflight_json(rebuilt_analysis, ComparisonError)
    pair = _ArtifactPair(reference_path, rebuilt_path); complete = False
    try:
        identities, differences = pair.identities_and_differences()
        pair.left.verify_stable(); pair.right.verify_stable()
        _identity_check("reference", reference_analysis, identities[0]); _identity_check("rebuilt", rebuilt_analysis, identities[1])
        try:
            left = normalize_analysis(reference_analysis); right = normalize_analysis(rebuilt_analysis)
        except ValueError as error:
            raise ComparisonError(f"invalid normalized analysis: {error}") from error
        left_infos, left_ranges = _section_infos(reference_analysis, pair.left)
        right_infos, right_ranges = _section_infos(rebuilt_analysis, pair.right)
        left_map = _normalized_section_map(left, left_infos); right_map = _normalized_section_map(right, right_infos)
        categories = _CategoryStore()
        functions = _compare_functions(left, right, left_map, right_map, pair, categories)
        sections = []
        for index in range(max(len(left_infos), len(right_infos))):
            finding_before = _reason_snapshot(categories)
            a = left_infos[index] if index < len(left_infos) else None
            b = right_infos[index] if index < len(right_infos) else None
            ad = None if a is None else a["descriptor"]; bd = None if b is None else b["descriptor"]
            layout_equal = (a is not None and b is not None and
                {k: ad[k] for k in ad if k != "sha256"} == {k: bd[k] for k in bd if k != "sha256"})
            content_equal = a is not None and b is not None and ad["sha256"] == bd["sha256"]
            analyzer_valid = ((a is None or a["analyzer_hash_valid"]) and
                              (b is None or b["analyzer_hash_valid"]))
            section_reasons = []
            if a is None or b is None or not layout_equal:
                status = "missing-reference" if a is None else "missing-rebuilt" if b is None else "layout-different"
                section_reasons.append("section layout differs")
                _add(categories, _layout_evidence(index, ad, bd))
            elif not content_equal:
                status = "different"
            else: status = "matched"
            if a is not None and b is not None and not content_equal:
                _add(categories, _section_content_evidence(index, ad, bd))
                section_reasons.append("section content differs")
            for info, descriptor, side in ((a, ad, "reference"), (b, bd, "rebuilt")):
                if info is not None and not info["analyzer_hash_valid"]:
                    if status == "matched": status = "different"
                    section_reasons.append("analyzer section hash disagrees with artifact")
                    _add(categories, {"kind": "section-hash", "category": "metadata",
                        "scope": "section", "reason": "analyzer section hash disagrees with artifact",
                        "path": f"/sections/{index}/sha256", "reference": side,
                        "rebuilt": descriptor["sha256"]})
            sections.append({"index": index, "status": status, "reference": ad, "rebuilt": bd,
                             "reasons": sorted(set(section_reasons)), "layout_equal": layout_equal,
                             "content_equal": content_equal, "analyzer_valid": analyzer_valid,
                             "finding_counts": _reason_delta(finding_before, categories)})
        _emit_byte_differences(differences, left_ranges, right_ranges, pair, categories)
        _metadata_differences(reference_analysis, rebuilt_analysis, ignore_metadata, categories)
        for values in categories.values(): values.sort(key=canonical_key)
        function_incompatible = sum("relocation target semantics differ" in item["reasons"] for item in functions)
        standalone_different = categories.reason_totals["relocation"].get("relocations differ", 0)
        standalone_reordered = categories.reason_totals["relocation"].get("relocations reordered", 0)
        rejecting_relocations = function_incompatible + standalone_different + standalone_reordered
        relocation_summary = {"function_incompatible_count": function_incompatible,
                              "standalone_different_count": standalone_different,
                              "standalone_reordered_count": standalone_reordered,
                              "rejecting_count": rejecting_relocations,
                              "compatible": rejecting_relocations == 0}
        attributed = {category: {} for category in CATEGORIES}
        for record in functions + sections:
            for category, values in record["finding_counts"].items():
                for reason, count in values.items():
                    attributed[category][reason] = attributed[category].get(reason, 0) + count
        nonrecord = {}
        for category in CATEGORIES:
            values = {}
            for reason, count in categories.reason_totals[category].items():
                remainder = count - attributed[category].get(reason, 0)
                if remainder: values[reason] = remainder
            nonrecord[category] = dict(sorted(values.items()))
        normalized_ok = (not categories.reason_totals["code"] and
                         all(item["status"] == "assembly-matched" for item in functions) and
                         relocation_summary["compatible"])
        sections_ok = normalized_ok and all(item["status"] == "matched" for item in sections)
        image_ok = (sections_ok and identities[0]["size"] == identities[1]["size"] and
                    identities[0]["sha256"] == identities[1]["sha256"])
        acceptance = {"normalized-functions": normalized_ok, "exact-sections": sections_ok,
                      "exact-image": image_ok}
        report = {"schema_version": "comparison-v1", "reference": identities[0], "rebuilt": identities[1],
                  "acceptance": acceptance, "selected": {"requirement": requirement,
                  "passed": acceptance[requirement]}, "category_counts": dict(categories.totals),
                  "category_omitted": {name: categories.totals[name] - len(categories[name]) for name in CATEGORIES},
                  "categories": dict(categories), "reason_totals":
                  {name: dict(sorted(categories.reason_totals[name].items())) for name in CATEGORIES},
                  "nonrecord_reason_totals": nonrecord,
                  "relocation_summary": relocation_summary,
                  "functions": functions, "sections": sections}
        pair.left.verify_stable(); pair.right.verify_stable()
        validate_comparison_report(report); complete = True
    finally:
        if complete: pair.close_verified()
        else: pair.close_unverified()
    return report


def _validate_identity(value):
    if (not isinstance(value, dict) or set(value) != {"path", "size", "sha256"} or
            not isinstance(value["path"], str) or not value["path"] or
            type(value["size"]) is not int or value["size"] < 0 or
            not isinstance(value["sha256"], str) or re.fullmatch(r"[0-9A-F]{64}", value["sha256"]) is None):
        raise ComparisonError("invalid identity")


def _validate_function_key(value):
    if (not isinstance(value, dict) or set(value) != {"section", "name_occurrence", "start", "end"} or
            not isinstance(value["section"], str) or
            any(type(value[key]) is not int for key in ("name_occurrence", "start", "end")) or
            value["name_occurrence"] < 0 or value["start"] < 0 or value["start"] > value["end"]):
        raise ComparisonError("invalid function key")


def _validate_finding_counts(value):
    if not isinstance(value, dict) or any(category not in CATEGORIES for category in value):
        raise ComparisonError("invalid finding count categories")
    for category, reasons in value.items():
        if (not isinstance(reasons, dict) or not reasons or list(reasons) != sorted(reasons) or
                any(not isinstance(reason, str) or reason not in _REASONS or
                    type(count) is not int or count <= 0 for reason, count in reasons.items())):
            raise ComparisonError("invalid finding counts")


def _validate_artifact_byte_evidence(item, reference_size, rebuilt_size):
    maximum = max(reference_size, rebuilt_size)
    start, end = item["start"], item["end"]
    if end > maximum:
        raise ComparisonError("artifact byte evidence exceeds identities")
    expected_reference = min(32, max(0, min(end, reference_size) - start))
    expected_rebuilt = min(32, max(0, min(end, rebuilt_size) - start))
    if (len(item["reference"]) // 2 != expected_reference or
            len(item["rebuilt"]) // 2 != expected_rebuilt):
        raise ComparisonError("artifact byte sample contradicts identities")
    if item["reference"] == item["rebuilt"]:
        raise ComparisonError("artifact byte sample does not differ")


def _validate_evidence(item, category):
    common = {"kind", "category", "scope", "reason", "reference", "rebuilt"}
    if (not isinstance(item, dict) or item.get("category") != category or
            not isinstance(item.get("reason"), str) or item["reason"] not in _REASONS or
            not isinstance(item.get("kind"), str) or not isinstance(item.get("scope"), str)):
        raise ComparisonError("invalid evidence scalar")
    kind = item.get("kind")
    if kind in ("instruction-bytes", "relocation-bytes", "analyzer-inconsistency", "function-range"):
        if set(item) != common | {"function", "section", "start", "end"} or item["scope"] != "instruction":
            raise ComparisonError("invalid instruction evidence")
        _validate_function_key(item["function"])
        if (not isinstance(item["section"], dict) or set(item["section"]) != {"name", "name_occurrence"} or
                not isinstance(item["section"]["name"], str) or
                type(item["section"]["name_occurrence"]) is not int or item["section"]["name_occurrence"] < 0):
            raise ComparisonError("invalid instruction section")
        if (type(item["start"]) is not int or type(item["end"]) is not int or
                item["start"] < 0 or item["start"] >= item["end"] or
                any(not isinstance(item[key], str) or re.fullmatch(r"(?:[0-9A-F]{2})*", item[key]) is None
                    for key in ("reference", "rebuilt"))):
            raise ComparisonError("invalid instruction byte evidence")
    elif kind == "function-structure":
        if set(item) != common | {"function"} or item["scope"] != "function": raise ComparisonError("invalid function evidence")
        _validate_function_key(item["function"])
        if item["reference"] not in ("present", "absent", "different", "overlap") or item["rebuilt"] not in ("present", "absent", "different", "overlap"):
            raise ComparisonError("invalid function evidence summaries")
    elif kind in ("section-layout", "section-content"):
        if set(item) != common | {"path"} or item["scope"] != "section": raise ComparisonError("invalid layout evidence")
        for value in (item["reference"], item["rebuilt"]):
            if value is not None: _validate_section_descriptor(value)
    elif kind == "section-hash":
        if set(item) != common | {"path"} or item["scope"] != "section": raise ComparisonError("invalid section hash evidence")
        if (not isinstance(item["reference"], str) or item["reference"] not in ("reference", "rebuilt") or
                not isinstance(item["rebuilt"], str) or re.fullmatch(r"[0-9A-F]{64}", item["rebuilt"]) is None):
            raise ComparisonError("invalid section hash summary")
    elif kind == "collection-difference":
        if set(item) != common | {"path"} or item["scope"] != "metadata": raise ComparisonError("invalid collection evidence")
        pattern = r"count=[0-9]+;sha256=[0-9A-F]{64}"
        if (not isinstance(item["reference"], str) or not isinstance(item["rebuilt"], str) or
                re.fullmatch(pattern, item["reference"]) is None or re.fullmatch(pattern, item["rebuilt"]) is None):
            raise ComparisonError("invalid collection summary")
    elif kind in ("byte-range", "section-byte-range"):
        if set(item) != common | {"start", "end"} or item["scope"] != "artifact": raise ComparisonError("invalid byte evidence")
        if (type(item["start"]) is not int or type(item["end"]) is not int or item["start"] < 0 or
                item["start"] >= item["end"] or any(not isinstance(item[key], str) or
                re.fullmatch(r"(?:[0-9A-F]{2})*", item[key]) is None
                for key in ("reference", "rebuilt"))): raise ComparisonError("invalid byte range")
    else: raise ComparisonError("unknown evidence kind")
    if kind == "instruction-bytes" and (category, item["reason"]) != ("code", "instruction semantics differ"):
        raise ComparisonError("incoherent instruction evidence")
    if kind == "relocation-bytes" and (category, item["reason"]) != ("relocation", "relocation field bytes differ"):
        raise ComparisonError("incoherent relocation evidence")
    if kind == "analyzer-inconsistency" and (category, item["reason"]) != ("code", "analyzer bytes disagree with artifact"):
        raise ComparisonError("incoherent analyzer evidence")
    if kind == "function-range" and (category, item["reason"]) != ("code", "function range bytes differ"):
        raise ComparisonError("incoherent function range evidence")
    if kind == "function-structure":
        allowed = ({"relocation"} if item["reason"] == "relocation target semantics differ" else
                   {"code", "layout"} if item["reason"] == "overlapping functions" else {"code"})
        if category not in allowed: raise ComparisonError("incoherent function evidence")
    if kind == "section-layout" and (category, item["reason"]) != ("layout", "section layout differs"):
        raise ComparisonError("incoherent layout evidence")
    if kind == "section-content" and (category, item["reason"]) != ("metadata", "section content differs"):
        raise ComparisonError("incoherent section evidence")
    if kind == "section-hash" and (category, item["reason"]) != ("metadata", "analyzer section hash disagrees with artifact"):
        raise ComparisonError("incoherent section hash evidence")
    if kind == "collection-difference":
        expected = ("relocation" if item["reason"] in ("relocations differ", "relocations reordered") else
                    "symbol-string-order" if item["reason"] in ("symbols reordered", "strings reordered") else
                    "metadata")
        if category != expected: raise ComparisonError("incoherent collection evidence")
    if kind == "section-byte-range" and (category, item["reason"]) != (
            "metadata", "bytes within section ranges differ"):
        raise ComparisonError("incoherent section byte evidence")
    if kind == "byte-range" and (category, item["reason"]) not in {
            ("metadata", "header or load-command bytes differ"),
            ("padding", "bytes outside sections differ")}:
        raise ComparisonError("incoherent byte evidence")
    if "path" in item and (not isinstance(item["path"], str) or not item["path"].startswith("/")):
        raise ComparisonError("invalid evidence path")
    if "path" in item: _decode_pointer(item["path"])


def validate_comparison_report(report):
    try:
        _validate_comparison_report(report)
    except ComparisonError:
        raise
    except Exception as error:
        raise ComparisonError(f"malformed comparison report: {error}") from error


def _validate_comparison_report(report):
    preflight_json(report, ComparisonError)
    fields = {"schema_version", "reference", "rebuilt", "acceptance", "selected",
              "category_counts", "category_omitted", "categories", "reason_totals",
              "nonrecord_reason_totals", "relocation_summary",
              "functions", "sections"}
    if not isinstance(report, dict) or set(report) != fields or report["schema_version"] != "comparison-v1":
        raise ComparisonError("invalid report fields")
    _validate_identity(report["reference"]); _validate_identity(report["rebuilt"])
    image_identity_equal = (report["reference"]["size"] == report["rebuilt"]["size"] and
                            report["reference"]["sha256"] == report["rebuilt"]["sha256"])
    if (not isinstance(report["categories"], dict) or not isinstance(report["category_counts"], dict) or
            not isinstance(report["category_omitted"], dict) or not isinstance(report["reason_totals"], dict) or
            not isinstance(report["nonrecord_reason_totals"], dict) or
            set(report["categories"]) != set(CATEGORIES) or
            set(report["category_counts"]) != set(CATEGORIES) or
            set(report["category_omitted"]) != set(CATEGORIES) or set(report["reason_totals"]) != set(CATEGORIES) or
            set(report["nonrecord_reason_totals"]) != set(CATEGORIES)):
        raise ComparisonError("invalid category fields")
    for category in CATEGORIES:
        values = report["categories"][category]
        reasons = report["reason_totals"][category]
        if (not isinstance(reasons, dict) or any(not isinstance(reason, str) or reason not in _REASONS or
                reason not in _CATEGORY_REASONS[category] or
                type(count) is not int or count <= 0 for reason, count in reasons.items()) or
                list(reasons) != sorted(reasons)):
            raise ComparisonError("invalid reason totals")
        if (not isinstance(values, list) or len(values) > MAX_EVIDENCE or
                values != sorted(values, key=canonical_key) or len(values) != len({canonical_key(v) for v in values}) or
                type(report["category_counts"][category]) is not int or
                type(report["category_omitted"][category]) is not int or
                report["category_counts"][category] < 0 or report["category_omitted"][category] < 0 or
                report["category_counts"][category] != len(values) + report["category_omitted"][category] or
                report["category_counts"][category] != sum(reasons.values())):
            raise ComparisonError("invalid category evidence order/count")
        retained_reasons = {}
        for item in values:
            _validate_evidence(item, category)
            if item["kind"] in ("byte-range", "section-byte-range"):
                _validate_artifact_byte_evidence(
                    item, report["reference"]["size"], report["rebuilt"]["size"])
            retained_reasons[item["reason"]] = retained_reasons.get(item["reason"], 0) + 1
        if any(count > reasons.get(reason, 0) for reason, count in retained_reasons.items()):
            raise ComparisonError("evidence exceeds reason total")
    artifact_byte_total = sum(
        report["reason_totals"][category].get(reason, 0)
        for category, reasons in _ARTIFACT_BYTE_REASONS.items() for reason in reasons)
    if (artifact_byte_total == 0) != image_identity_equal:
        raise ComparisonError("artifact byte totals contradict identities")
    summary = report["relocation_summary"]
    summary_fields = {"function_incompatible_count", "standalone_different_count",
                      "standalone_reordered_count", "rejecting_count", "compatible"}
    if (not isinstance(summary, dict) or set(summary) != summary_fields or
            any(type(summary[name]) is not int or summary[name] < 0 for name in summary_fields - {"compatible"}) or
            type(summary["compatible"]) is not bool or
            summary["compatible"] != (summary["rejecting_count"] == 0)):
        raise ComparisonError("invalid relocation summary")
    expected_standalone_different = report["reason_totals"]["relocation"].get("relocations differ", 0)
    expected_standalone_reordered = report["reason_totals"]["relocation"].get("relocations reordered", 0)
    expected_function_incompatible = report["reason_totals"]["relocation"].get(
        "relocation target semantics differ", 0)
    expected_rejecting = sum(count for reason, count in report["reason_totals"]["relocation"].items()
                             if reason != "relocation field bytes differ")
    if (summary["function_incompatible_count"] != expected_function_incompatible or
            summary["standalone_different_count"] != expected_standalone_different or
            summary["standalone_reordered_count"] != expected_standalone_reordered or
            summary["rejecting_count"] != expected_rejecting):
        raise ComparisonError("relocation summary contradicts reasons")
    if not isinstance(report["functions"], list): raise ComparisonError("invalid functions")
    function_keys = []
    for item in report["functions"]:
        function_fields = {"key", "status", "reference_aliases", "rebuilt_aliases", "reasons",
            "raw_equal", "masked_equal", "semantics_equal", "cfg_equal", "calls_equal",
            "reference_sha256", "rebuilt_sha256", "reference_masked_sha256", "rebuilt_masked_sha256",
            "finding_counts"}
        if not isinstance(item, dict) or set(item) != function_fields:
            raise ComparisonError("invalid function record")
        _validate_function_key(item["key"]); function_keys.append((item["key"]["section"],
            item["key"]["name_occurrence"], item["key"]["start"], item["key"]["end"]))
        if not isinstance(item["status"], str) or item["status"] not in ("assembly-matched", "different", "missing-reference", "missing-rebuilt"):
            raise ComparisonError("invalid function status")
        for name in ("reference_aliases", "rebuilt_aliases"):
            if (not isinstance(item[name], list) or any(not isinstance(v, str) for v in item[name]) or
                        item[name] != sorted(set(item[name]), key=canonical_key)):
                    raise ComparisonError("invalid aliases")
        if (not isinstance(item["reasons"], list) or any(not isinstance(value, str) or value not in _REASONS for value in item["reasons"]) or
                item["reasons"] != sorted(set(item["reasons"]))): raise ComparisonError("invalid function reasons")
        if any(type(item[name]) is not bool for name in
               ("raw_equal", "masked_equal", "semantics_equal", "cfg_equal", "calls_equal")):
            raise ComparisonError("invalid function booleans")
        for name in ("reference_sha256", "rebuilt_sha256", "reference_masked_sha256", "rebuilt_masked_sha256"):
            if item[name] is not None and (not isinstance(item[name], str) or re.fullmatch(r"[0-9A-F]{64}", item[name]) is None):
                raise ComparisonError("invalid function hash")
        missing = item["status"].startswith("missing-")
        hashes = [item[name] for name in ("reference_sha256", "rebuilt_sha256",
                  "reference_masked_sha256", "rebuilt_masked_sha256")]
        if missing and any(value is not None for value in hashes): raise ComparisonError("missing function has hashes")
        if not missing and any(value is None for value in hashes): raise ComparisonError("matched function lacks hashes")
        _validate_finding_counts(item["finding_counts"])
        for category, values in item["finding_counts"].items():
            for reason in values:
                if (reason not in _FUNCTION_ORIGINS.get(category, set()) or
                        (reason != "relocation field bytes differ" and reason not in item["reasons"])):
                    raise ComparisonError("function finding has invalid provenance")
        for reason in item["reasons"]:
            expected_categories = [category for category, values in _FUNCTION_ORIGINS.items()
                                   if reason in values]
            if not expected_categories or any(
                    item["finding_counts"].get(category, {}).get(reason, 0) == 0
                    for category in expected_categories):
                raise ComparisonError("function reason lacks findings")
        relocation_fields = item["finding_counts"].get("relocation", {}).get(
            "relocation field bytes differ", 0)
        if relocation_fields and (item["raw_equal"] or not item["masked_equal"]):
            raise ComparisonError("function relocation findings contradict bytes")
        if missing:
            expected_missing_reason = ("missing reference function" if item["status"] == "missing-reference"
                                       else "missing rebuilt function")
            if item["reasons"] != [expected_missing_reason] or any(item[name] for name in
                    ("raw_equal", "masked_equal", "semantics_equal", "cfg_equal", "calls_equal")):
                raise ComparisonError("incoherent missing function")
        else:
            if item["raw_equal"] != (hashes[0] == hashes[1]): raise ComparisonError("incoherent raw function hash")
            if item["masked_equal"] != (hashes[2] == hashes[3]): raise ComparisonError("incoherent masked function hash")
            semantic_reasons = {"analyzer bytes disagree with artifact", "instruction shape differs",
                "instruction layout differs", "instruction semantics differ",
                "relocation target semantics differ", "instruction references differ"}
            if item["semantics_equal"] != (not bool(semantic_reasons.intersection(item["reasons"]))):
                raise ComparisonError("function semantics contradict reasons")
            if item["cfg_equal"] != ("cfg differs" not in item["reasons"]):
                raise ComparisonError("function cfg contradicts reasons")
            if item["calls_equal"] != ("calls differ" not in item["reasons"]):
                raise ComparisonError("function calls contradict reasons")
            if item["masked_equal"] != ("function range bytes differ" not in item["reasons"]):
                raise ComparisonError("function masked bytes contradict reasons")
        expected_status = ("missing-reference" if "missing reference function" in item["reasons"] else
                           "missing-rebuilt" if "missing rebuilt function" in item["reasons"] else
                           "assembly-matched" if (item["masked_equal"] and item["semantics_equal"] and
                           item["cfg_equal"] and item["calls_equal"] and not item["reasons"]) else "different")
        if item["status"] != expected_status: raise ComparisonError("forged function status")
    if function_keys != sorted(set(function_keys)): raise ComparisonError("noncanonical functions")
    function_by_key = {canonical_key(item["key"]): item for item in report["functions"]}
    expected_function_incompatible = sum("relocation target semantics differ" in item["reasons"]
                                         for item in report["functions"])
    if summary["function_incompatible_count"] != expected_function_incompatible:
        raise ComparisonError("relocation function summary contradicts records")
    for category in ("code", "relocation", "layout"):
        for evidence in report["categories"][category]:
            if "function" not in evidence: continue
            record = function_by_key.get(canonical_key(evidence["function"]))
            if record is None: raise ComparisonError("evidence references missing function")
            if evidence["reason"] == "relocation field bytes differ":
                if record["raw_equal"] or not record["masked_equal"]:
                    raise ComparisonError("relocation evidence contradicts function bytes")
            elif evidence["reason"] not in record["reasons"]:
                raise ComparisonError("function evidence contradicts record")
    if not isinstance(report["sections"], list): raise ComparisonError("invalid sections")
    for index, item in enumerate(report["sections"]):
        if (not isinstance(item, dict) or set(item) != {"index", "status", "reference", "rebuilt",
                "reasons", "layout_equal", "content_equal", "analyzer_valid", "finding_counts"} or
                item["index"] != index or item["status"] not in
                ("matched", "different", "layout-different", "missing-reference", "missing-rebuilt")):
            raise ComparisonError("invalid section record")
        if (any(type(item[name]) is not bool for name in ("layout_equal", "content_equal", "analyzer_valid")) or
                not isinstance(item["reasons"], list) or
                any(not isinstance(reason, str) or reason not in _REASONS for reason in item["reasons"]) or
                item["reasons"] != sorted(set(item["reasons"]))): raise ComparisonError("invalid section summary")
        for descriptor in (item["reference"], item["rebuilt"]):
            if descriptor is not None: _validate_section_descriptor(descriptor)
        _validate_finding_counts(item["finding_counts"])
        for category, values in item["finding_counts"].items():
            if any(reason not in _SECTION_ORIGINS.get(category, set()) or
                   reason not in item["reasons"] for reason in values):
                raise ComparisonError("section finding has invalid provenance")
        for reason in item["reasons"]:
            expected_categories = [category for category, values in _SECTION_ORIGINS.items()
                                   if reason in values]
            if not expected_categories or any(
                    item["finding_counts"].get(category, {}).get(reason, 0) == 0
                    for category in expected_categories):
                raise ComparisonError("section reason lacks findings")
        a, b = item["reference"], item["rebuilt"]
        computed_layout = (a is not None and b is not None and
            {key: a[key] for key in a if key != "sha256"} ==
            {key: b[key] for key in b if key != "sha256"})
        computed_content = a is not None and b is not None and a["sha256"] == b["sha256"]
        computed_analyzer = "analyzer section hash disagrees with artifact" not in item["reasons"]
        if (item["layout_equal"] != computed_layout or item["content_equal"] != computed_content or
                item["analyzer_valid"] != computed_analyzer):
            raise ComparisonError("section facts contradict descriptors")
        expected_reasons = []
        if not computed_layout:
            expected_reasons.append("section layout differs")
        if a is not None and b is not None and not computed_content:
            expected_reasons.append("section content differs")
        if not computed_analyzer:
            expected_reasons.append("analyzer section hash disagrees with artifact")
        if item["reasons"] != sorted(expected_reasons):
            raise ComparisonError("section reasons contradict descriptors")
        expected_status = ("missing-reference" if a is None else "missing-rebuilt" if b is None else
                           "layout-different" if not item["layout_equal"] else
                           "different" if not item["content_equal"] or not item["analyzer_valid"] else "matched")
        if item["status"] != expected_status: raise ComparisonError("forged section status")
    for category in ("layout", "metadata"):
        for evidence in report["categories"][category]:
            if evidence.get("scope") != "section" or "path" not in evidence: continue
            match = re.fullmatch(r"/sections/([0-9]+)(?:/sha256)?", evidence["path"])
            if match is None or int(match.group(1)) >= len(report["sections"]):
                raise ComparisonError("section evidence path is invalid")
            if evidence["reason"] not in report["sections"][int(match.group(1))]["reasons"]:
                raise ComparisonError("section evidence contradicts record")
    attributed = {category: {} for category in CATEGORIES}
    for record in report["functions"] + report["sections"]:
        for category, values in record["finding_counts"].items():
            for reason, count in values.items():
                attributed[category][reason] = attributed[category].get(reason, 0) + count
    for category in CATEGORIES:
        nonrecord = report["nonrecord_reason_totals"][category]
        if (not isinstance(nonrecord, dict) or list(nonrecord) != sorted(nonrecord) or
                any(not isinstance(reason, str) or reason not in _REASONS or
                    reason not in _NONRECORD_ORIGINS[category] or
                    type(count) is not int or count <= 0 for reason, count in nonrecord.items())):
            raise ComparisonError("invalid nonrecord reason totals")
        combined = dict(attributed[category])
        for reason, count in nonrecord.items(): combined[reason] = combined.get(reason, 0) + count
        if combined != report["reason_totals"][category]:
            raise ComparisonError("reason totals contradict records and summary")
    expected_normalized = (not report["reason_totals"]["code"] and
                           all(item["status"] == "assembly-matched" for item in report["functions"]) and
                           summary["compatible"])
    expected_sections = expected_normalized and all(item["status"] == "matched" for item in report["sections"])
    expected_image = expected_sections and image_identity_equal
    expected = {"normalized-functions": expected_normalized, "exact-sections": expected_sections,
                "exact-image": expected_image}
    if report["acceptance"] != expected: raise ComparisonError("forged acceptance")
    if (not isinstance(report["selected"], dict) or set(report["selected"]) != {"requirement", "passed"} or
            report["selected"]["requirement"] not in REQUIREMENTS or
            type(report["selected"]["passed"]) is not bool or
            report["selected"]["passed"] != expected[report["selected"]["requirement"]]):
        raise ComparisonError("invalid selected acceptance")


def format_text_report(report):
    counts = " ".join(f"{name}={report['category_counts'][name]}" for name in CATEGORIES)
    return f"{report['selected']['requirement']}: {'PASS' if report['selected']['passed'] else 'FAIL'} {counts}\n"
