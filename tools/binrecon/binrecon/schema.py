import json
import math
import re
from functools import lru_cache
from importlib.resources import files
from pathlib import Path, PurePosixPath

from jsonschema import Draft202012Validator


class SemanticValidationError(ValueError):
    """Raised when a document violates relationships JSON Schema cannot express."""


_SCHEMA_FILES = {
    "analysis-v1": "analysis-v1.json",
    "analysis-v1.json": "analysis-v1.json",
    "profile-v1": "profile-v1.json",
    "profile-v1.json": "profile-v1.json",
    "ledger-v1": "ledger-v1.json",
    "ledger-v1.json": "ledger-v1.json",
    "source-map-v1": "source-map-v1.json",
    "source-map-v1.json": "source-map-v1.json",
}
_SHA256_RE = re.compile(r"^[0-9a-fA-F]{64}$")

MAX_JSON_COLLECTION = 500_000
DEFAULT_MAX_JSON_NODES = 1_000_000
# The 35.4 MiB EISABus three-analyzer aggregate is 1,916,833 nodes.  This
# leaves 30% growth headroom without weakening the independent shape limits.
CONSENSUS_MAX_JSON_NODES = 2_500_000
MAX_JSON_DEPTH = 64
MAX_JSON_STRING = 1_048_576


def preflight_json(value, error_type=ValueError, *,
                   max_nodes=DEFAULT_MAX_JSON_NODES) -> None:
    """Iteratively bound JSON structure before schema or recursive processing."""
    if type(max_nodes) is not int or max_nodes <= 0:
        raise ValueError("max_nodes must be a positive integer")
    stack = [(value, 0)]; nodes = 0
    while stack:
        item, depth = stack.pop(); nodes += 1
        if nodes > max_nodes: raise error_type("JSON node limit exceeded")
        if depth > MAX_JSON_DEPTH: raise error_type("JSON nesting depth limit exceeded")
        if item is None or type(item) in (bool, int): continue
        if isinstance(item, float):
            if not math.isfinite(item): raise error_type("JSON numbers must be finite")
            continue
        if isinstance(item, str):
            if len(item) > MAX_JSON_STRING: raise error_type("JSON string length limit exceeded")
            continue
        if isinstance(item, list):
            if len(item) > MAX_JSON_COLLECTION:
                raise error_type("JSON collection length limit exceeded")
            stack.extend((child, depth + 1) for child in item)
            continue
        if isinstance(item, dict):
            if len(item) > MAX_JSON_COLLECTION:
                raise error_type("JSON collection length limit exceeded")
            for key, child in item.items():
                if not isinstance(key, str):
                    raise error_type("JSON object keys must be strings")
                if len(key) > MAX_JSON_STRING:
                    raise error_type("JSON key length limit exceeded")
                stack.append((child, depth + 1))
            continue
        raise error_type(f"unsupported JSON type: {type(item).__name__}")


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as stream:
        document = json.load(stream)
    if not isinstance(document, dict):
        raise ValueError(f"JSON root in {path} must be an object")
    return document


def validate_document(schema_name: str, document: dict) -> None:
    try:
        filename = _SCHEMA_FILES[schema_name]
    except KeyError as error:
        raise ValueError(f"unknown schema name: {schema_name}") from error

    _load_validator(filename).validate(document)


@lru_cache(maxsize=None)
def _load_validator(filename: str) -> Draft202012Validator:
    schema_text = files("binrecon").joinpath("schema", filename).read_text(
        encoding="utf-8"
    )
    schema = json.loads(schema_text)
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema)


def validate_analysis_semantics(document: dict) -> None:
    _validate_analysis_hashes(document)
    _validate_sections(document["sections"])

    function_starts: set[int] = set()
    for function in document["functions"]:
        function_address = function["address"]
        if function_address in function_starts:
            raise SemanticValidationError(
                f"duplicate function start address {function_address}"
            )
        function_starts.add(function_address)
        _validate_function(function)


def load_source_map(path: Path, *, reference_analysis=None,
                    repo_root: Path | None = None) -> dict:
    document = load_json(path)
    preflight_json(document)
    validate_document("source-map-v1", document)
    validate_source_map_semantics(
        document, reference_analysis=reference_analysis, repo_root=repo_root
    )
    return document


def validate_source_map_semantics(document: dict, *, reference_analysis=None,
                                  repo_root: Path | None = None) -> None:
    categories = (
        "mapped", "unmapped", "duplicate_candidates", "boundary_disputed"
    )
    entries: list[tuple[str, dict]] = []
    starts: dict[int, str] = {}

    for category in categories:
        category_entries = document[category]
        expected_order = sorted(
            category_entries,
            key=lambda entry: (entry["address"], tuple(entry["reference_names"])),
        )
        if category_entries != expected_order:
            raise SemanticValidationError(
                f"{category} entries are not in canonical order by address and name"
            )

        for entry in category_entries:
            _validate_sorted_unique(
                entry["reference_names"],
                f"{category} entry at address {entry['address']} reference_names",
            )
            if "reasons" in entry:
                _validate_sorted_unique(
                    entry["reasons"],
                    f"{category} entry at address {entry['address']} reasons",
                )

            address = entry["address"]
            if address in starts:
                raise SemanticValidationError(
                    f"duplicate function start address {address} in {starts[address]} "
                    f"and {category}"
                )
            starts[address] = category
            entries.append((category, entry))

            if "source_path" in entry:
                _validate_source_location(entry, repo_root)
            for candidate in entry.get("candidates", []):
                _validate_source_location(candidate, repo_root)

    _validate_source_map_overlaps(entries)
    if reference_analysis is not None:
        preflight_json(reference_analysis)
        validate_document("analysis-v1", reference_analysis)
        validate_analysis_semantics(reference_analysis)
        analysis_sha256 = reference_analysis["input"]["sha256"]
        if document["reference_sha256"] != analysis_sha256:
            raise SemanticValidationError(
                f"source map reference_sha256 {document['reference_sha256']} does not "
                f"match analysis input sha256 {analysis_sha256}"
            )
        _validate_source_map_context(entries, reference_analysis["functions"])


def _validate_sorted_unique(values: list[str], label: str) -> None:
    if len(values) != len(set(values)):
        raise SemanticValidationError(f"{label} must be unique")
    if values != sorted(values):
        raise SemanticValidationError(f"{label} must be sorted")


def _validate_source_location(location: dict, repo_root: Path | None) -> None:
    source_path = location["source_path"]
    posix_path = PurePosixPath(source_path)
    if (
        "\\" in source_path
        or posix_path.is_absolute()
        or any(part in ("", ".", "..") for part in source_path.split("/"))
        or (posix_path.parts and re.fullmatch(r"[A-Za-z]:", posix_path.parts[0]))
        or str(posix_path) != source_path
    ):
        raise SemanticValidationError(
            f"source_path {source_path!r} must be a canonical repo-relative POSIX path"
        )

    if repo_root is None:
        return

    resolved_root = Path(repo_root).resolve()
    resolved_source = (resolved_root / Path(*posix_path.parts)).resolve()
    try:
        resolved_source.relative_to(resolved_root)
    except ValueError as error:
        raise SemanticValidationError(
            f"source_path {source_path!r} escapes repo root"
        ) from error
    if not resolved_source.is_file():
        raise SemanticValidationError(f"source_path {source_path!r} is not a file")

    with resolved_source.open("r", encoding="utf-8", errors="replace") as stream:
        line_count = sum(1 for _ in stream)
    source_line = location["source_line"]
    if source_line > line_count:
        raise SemanticValidationError(
            f"source_line {source_line} for {source_path!r} is outside "
            f"the file's {line_count} lines"
        )


def _validate_source_map_overlaps(entries: list[tuple[str, dict]]) -> None:
    ordered = sorted(entries, key=lambda item: item[1]["address"])
    for index, (category, entry) in enumerate(ordered):
        end = entry["address"] + entry["size"]
        for other_category, other in ordered[index + 1:]:
            if other["address"] >= end:
                break
            if category != "boundary_disputed" or other_category != "boundary_disputed":
                raise SemanticValidationError(
                    f"function ranges at addresses {entry['address']} and "
                    f"{other['address']} overlap without both being boundary_disputed"
                )


def _validate_source_map_context(entries: list[tuple[str, dict]],
                                 expected_functions) -> None:
    expected_by_address: dict[int, dict] = {}
    for function in expected_functions:
        address = function["address"]
        if address in expected_by_address:
            raise SemanticValidationError(
                f"expected reference functions contain duplicate address {address}"
            )
        expected_by_address[address] = function

    actual_by_address = {entry["address"]: entry for _, entry in entries}
    if set(actual_by_address) != set(expected_by_address):
        missing = sorted(set(expected_by_address) - set(actual_by_address))
        unexpected = sorted(set(actual_by_address) - set(expected_by_address))
        raise SemanticValidationError(
            f"source map partition mismatch: missing={missing}, unexpected={unexpected}"
        )

    for address, entry in actual_by_address.items():
        expected = expected_by_address[address]
        if entry["size"] != expected["size"]:
            raise SemanticValidationError(
                f"function at address {address} has size {entry['size']}; "
                f"expected {expected['size']}"
            )
        expected_names = sorted(expected["names"])
        if entry["reference_names"] != expected_names:
            raise SemanticValidationError(
                f"function at address {address} has names {entry['reference_names']!r}; "
                f"expected {expected_names!r}"
            )


def _validate_analysis_hashes(document: dict) -> None:
    input_hash = document["input"]["sha256"]
    if not isinstance(input_hash, str) or _SHA256_RE.fullmatch(input_hash) is None:
        raise SemanticValidationError("input sha256 must be exactly 64 hexadecimal characters")

    for section in document["sections"]:
        section_hash = section["sha256"]
        if not isinstance(section_hash, str) or _SHA256_RE.fullmatch(section_hash) is None:
            raise SemanticValidationError(
                f"section {section['name']!r} at address {section['address']} has invalid sha256"
            )


def _validate_sections(sections: list[dict]) -> None:
    nonempty_sections = sorted(
        (section for section in sections if section["size"] != 0),
        key=lambda section: section["address"],
    )
    previous = None
    previous_end = 0
    for section in nonempty_sections:
        address = section["address"]
        if previous is not None and address < previous_end:
            raise SemanticValidationError(
                f"section {section['name']!r} at address {address} overlaps "
                f"section {previous['name']!r} at address {previous['address']}"
            )
        end = address + section["size"]
        if previous is None or end > previous_end:
            previous = section
            previous_end = end


def _validate_function(function: dict) -> None:
    function_address = function["address"]
    function_end = function_address + function["size"]
    block_starts: set[int] = set()

    for block in function["blocks"]:
        block_address = block["address"]
        if block_address in block_starts:
            raise SemanticValidationError(
                f"function at address {function_address} has duplicate block start address {block_address}"
            )
        block_starts.add(block_address)

        block_end = block_address + block["size"]
        if (
            block_address < function_address
            or block_address >= function_end
            or block_end > function_end
        ):
            raise SemanticValidationError(
                f"block at address {block_address} is outside function at address {function_address}"
            )

    for instruction in function["instructions"]:
        instruction_address = instruction["address"]
        instruction_end = instruction_address + len(instruction["bytes"]) // 2
        if not any(
            block["address"] <= instruction_address
            and instruction_end <= block["address"] + block["size"]
            for block in function["blocks"]
        ):
            raise SemanticValidationError(
                f"instruction at address {instruction_address} is outside every block "
                f"in function at address {function_address}"
            )
