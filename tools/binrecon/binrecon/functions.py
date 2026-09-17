"""Per-function queries over already-published binrecon output.

`binrecon analyze` publishes each analyzer's full instruction listing per
function.  Everything here reads those files, so any function can be examined
without re-running an analyzer -- which is what makes examining a few hundred
functions practical.
"""

from __future__ import annotations

import difflib
import json
from pathlib import Path


class FunctionQueryError(ValueError):
    """Raised when published output cannot be read or a function is unknown."""


def _read(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise FunctionQueryError(f"published file is missing: {path}") from error
    except (OSError, ValueError) as error:
        raise FunctionQueryError(f"published file is unreadable: {path}: {error}") from error


def load_published(output_dir: Path, analyzer: str) -> tuple[dict, dict, dict]:
    published = Path(output_dir) / "published"
    if not published.is_dir():
        raise FunctionQueryError(f"no published output directory: {published}")
    return (_read(published / f"analysis-reference-{analyzer}.json"),
            _read(published / f"analysis-rebuilt-{analyzer}.json"),
            _read(published / f"comparison-{analyzer}.json"))


def function_index(analysis: dict) -> dict[str, dict]:
    index: dict[str, dict] = {}
    for function in analysis.get("functions") or []:
        for name in function.get("names") or []:
            index.setdefault(name, function)
    return index


def instruction_pairs(function: dict) -> list[tuple[str, str]]:
    return [(item["mnemonic"], item.get("normalized_operands") or "")
            for item in function.get("instructions") or []]


def differing_count(reference_function: dict | None,
                    rebuilt_function: dict | None) -> int | None:
    if reference_function is None or rebuilt_function is None:
        return None
    left = [str(item) for item in instruction_pairs(reference_function)]
    right = [str(item) for item in instruction_pairs(rebuilt_function)]
    matcher = difflib.SequenceMatcher(a=left, b=right, autojunk=False)
    return sum(max(i2 - i1, j2 - j1)
               for tag, i1, i2, j1, j2 in matcher.get_opcodes() if tag != "equal")


def _row_name(record: dict) -> str:
    for key in ("reference_aliases", "rebuilt_aliases"):
        names = record.get(key) or []
        if names:
            return names[0]
    return "?"


def worklist(reference: dict, rebuilt: dict, comparison: dict) -> list[dict]:
    reference_index = function_index(reference)
    rebuilt_index = function_index(rebuilt)
    rows = []
    for record in comparison.get("functions") or []:
        name = _row_name(record)
        reference_function = next(
            (reference_index[alias] for alias in record.get("reference_aliases") or []
             if alias in reference_index), None)
        rebuilt_function = next(
            (rebuilt_index[alias] for alias in record.get("rebuilt_aliases") or []
             if alias in rebuilt_index), None)
        rows.append({
            "name": name,
            "status": record.get("status"),
            "raw_equal": record.get("raw_equal"),
            "masked_equal": record.get("masked_equal"),
            "differing": differing_count(reference_function, rebuilt_function),
            "reference_instructions":
                len(instruction_pairs(reference_function)) if reference_function else None,
            "rebuilt_instructions":
                len(instruction_pairs(rebuilt_function)) if rebuilt_function else None,
            "reasons": record.get("reasons") or [],
        })
    rows.sort(key=lambda row: (row["differing"] is None,
                               row["differing"] if row["differing"] is not None else 0,
                               row["name"]))
    return rows


def render_worklist(rows: list[dict]) -> str:
    lines = [f"{'diff':>6}  {'ref':>5}  {'new':>5}  {'flags':<10}  name", ""]
    for row in rows:
        differing = "-" if row["differing"] is None else str(row["differing"])
        reference = "-" if row["reference_instructions"] is None else str(row["reference_instructions"])
        rebuilt = "-" if row["rebuilt_instructions"] is None else str(row["rebuilt_instructions"])
        if row["raw_equal"]:
            flags = "identical"
        elif row["masked_equal"]:
            flags = "masked-eq"
        elif row["status"] != "different":
            flags = row["status"]
        else:
            flags = ""
        lines.append(f"{differing:>6}  {reference:>5}  {rebuilt:>5}  {flags:<10}  {row['name']}")
    identical = sum(1 for row in rows if row["raw_equal"])
    unpaired = sum(1 for row in rows if row["differing"] is None)
    lines += ["", f"{len(rows)} functions: {identical} byte-identical, "
                  f"{len(rows) - identical - unpaired} differing, {unpaired} unpaired"]
    return "\n".join(lines)


def render_function(name: str, reference_function: dict | None,
                    rebuilt_function: dict | None, record: dict | None) -> str:
    if reference_function is None and rebuilt_function is None:
        raise FunctionQueryError(f"no function named {name!r} in the published output")
    left = instruction_pairs(reference_function) if reference_function else []
    right = instruction_pairs(rebuilt_function) if rebuilt_function else []
    header = [name]
    if record is not None:
        header.append(f"  status={record.get('status')} "
                      f"raw_equal={record.get('raw_equal')} "
                      f"masked_equal={record.get('masked_equal')}")
        for reason in record.get("reasons") or []:
            header.append(f"  reason: {reason}")
    if reference_function is None:
        header.append("  reference side is missing")
    if rebuilt_function is None:
        header.append("  rebuilt side is missing")
    header.append("")
    header.append(f"  {'reference':<38}  {'rebuilt':<38}")

    def text(pair):
        return f"{pair[0]} {pair[1]}".strip() if pair else ""

    lines = []
    matcher = difflib.SequenceMatcher(a=[str(item) for item in left],
                                      b=[str(item) for item in right],
                                      autojunk=False)
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        width = max(i2 - i1, j2 - j1)
        for offset in range(width):
            source = left[i1 + offset] if i1 + offset < i2 else None
            target = right[j1 + offset] if j1 + offset < j2 else None
            marker = " " if tag == "equal" else "*"
            lines.append(f"{marker} {text(source):<38}  {text(target):<38}".rstrip())
    return "\n".join(header + lines)
