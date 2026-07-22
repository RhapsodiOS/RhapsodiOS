import argparse
import json
import os
from pathlib import Path
import stat
import sys
import tempfile

from jsonschema import ValidationError

from binrecon.profile import load_profile
from binrecon.consensus import ConsensusError, build_consensus
from binrecon.normalize import preflight_json
from binrecon.schema import validate_analysis_semantics, validate_document


COMMANDS = ("validate", "analyze", "consensus", "compare", "ledger")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="binrecon")
    subparsers = parser.add_subparsers(dest="command", required=True)

    for command in ("validate", "analyze", "compare", "ledger"):
        command_parser = subparsers.add_parser(command)
        command_parser.add_argument("--profile", required=True)
    consensus = subparsers.add_parser("consensus")
    consensus.add_argument("--input", action="append", required=True, dest="inputs")
    consensus.add_argument("--expected-analyzer", action="append",
                           dest="expected_analyzers")
    consensus.add_argument("--output", required=True)

    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "validate":
        try:
            profile = load_profile(Path(args.profile), os.environ)
        except (OSError, ValueError, ValidationError) as error:
            print(f"binrecon: {error}", file=sys.stderr)
            return 1

        for label, identity in (
            ("reference", profile.reference_identity),
            ("rebuilt", profile.rebuilt_identity),
        ):
            print(
                f"{label} {identity.path} size={identity.size} "
                f"sha256={identity.sha256}"
            )
        return 0

    if args.command == "consensus":
        try:
            inputs = [Path(value) for value in args.inputs]
            output = None if args.output == "-" else Path(args.output)
            if output is not None:
                _reject_output_alias(output, inputs)
            documents = [_read_json_snapshot(path) for path in inputs]
            for document in documents:
                preflight_json(document)
                validate_document("analysis-v1", document)
                validate_analysis_semantics(document)
            report = build_consensus(documents, expected_analyzers=args.expected_analyzers)
            text = json.dumps(report, sort_keys=True, separators=(",", ":"),
                              allow_nan=False) + "\n"
            if output is None:
                sys.stdout.write(text)
            else:
                _atomic_text(output, text, inputs)
        except (OSError, ValueError, ValidationError, ConsensusError) as error:
            print(f"binrecon: {error}", file=sys.stderr)
            return 1
        return 0

    print(f"binrecon: command not implemented: {args.command}")
    return 2


_MAX_JSON = 16 * 1024 * 1024


def _read_json_snapshot(path: Path) -> dict:
    if path.is_symlink():
        raise ValueError(f"input {path} is a symlink")
    flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags)
    try:
        initial = os.fstat(descriptor)
        reparse = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
        if (not stat.S_ISREG(initial.st_mode) or initial.st_nlink != 1 or
                getattr(initial, "st_file_attributes", 0) & reparse):
            raise ValueError(f"input {path} is not a private regular file")
        if initial.st_size > _MAX_JSON:
            raise ValueError(f"input {path} exceeds maximum JSON size")
        chunks, total = [], 0
        while True:
            chunk = os.read(descriptor, min(1024 * 1024, _MAX_JSON + 1 - total))
            if not chunk: break
            chunks.append(chunk); total += len(chunk)
            if total > _MAX_JSON: raise ValueError(f"input {path} exceeds maximum JSON size")
        final = os.fstat(descriptor)
        fields = ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns", "st_nlink")
        if total != initial.st_size or any(getattr(initial, key) != getattr(final, key) for key in fields):
            raise ValueError(f"input {path} changed while reading")
    finally:
        os.close(descriptor)
    try:
        value = json.loads(b"".join(chunks).decode("utf-8"),
                           parse_constant=lambda token: (_ for _ in ()).throw(
                               ValueError(f"non-finite JSON constant {token}")))
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError, RecursionError) as error:
        raise ValueError(f"input {path} is malformed JSON: {error}") from error
    if not isinstance(value, dict): raise ValueError(f"input {path} JSON root must be an object")
    return value


def _reject_output_alias(output: Path, inputs: list[Path]) -> None:
    if output.is_symlink(): raise ValueError("consensus output is a symlink")
    resolved = output.resolve(strict=False)
    for source in inputs:
        if resolved == source.resolve(strict=False): raise ValueError("consensus output aliases an input")
        if output.exists() and source.exists() and os.path.samefile(output, source):
            raise ValueError("consensus output aliases an input")


def _atomic_text(path: Path, value: str, inputs: list[Path]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".write", dir=path.parent)
    owned = descriptor
    try:
        stream = os.fdopen(descriptor, "w", encoding="utf-8", newline="\n"); owned = None
        with stream:
            stream.write(value); stream.flush(); os.fsync(stream.fileno())
        _reject_output_alias(path, inputs)
        os.replace(temporary, path)
    except BaseException:
        if owned is not None: os.close(owned)
        try: os.unlink(temporary)
        except FileNotFoundError: pass
        raise
