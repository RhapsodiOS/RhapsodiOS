import json
import re
from functools import lru_cache
from importlib.resources import files
from pathlib import Path

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
}
_SHA256_RE = re.compile(r"^[0-9a-fA-F]{64}$")


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
