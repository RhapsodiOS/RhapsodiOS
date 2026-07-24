import argparse
import json
import os
from pathlib import Path
import stat
import sys
import tempfile

from jsonschema import ValidationError

from binrecon.profile import load_profile
from binrecon.compare import ComparisonError, compare_artifacts, format_text_report
from binrecon.consensus import ConsensusError, build_consensus
from binrecon.normalize import preflight_json
from binrecon.schema import validate_analysis_semantics, validate_document
from binrecon.ledger import LedgerError, LedgerLock, load_ledger, transition, write_ledger
from binrecon.runner import RunnerError, run_analysis


COMMANDS = ("validate", "analyze", "consensus", "compare", "ledger")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="binrecon")
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate = subparsers.add_parser("validate")
    validate.add_argument("--profile", required=True)
    analyze = subparsers.add_parser("analyze")
    analyze.add_argument("--profile", required=True)
    analyze.add_argument("--ledger")
    analyze.add_argument("--output")
    ledger = subparsers.add_parser("ledger")
    ledger.add_argument("--profile", required=True)
    ledger.add_argument("--ledger", required=True)
    ledger.add_argument("--address", type=lambda value: int(value, 0))
    ledger.add_argument("--status", choices=("unexamined", "signature-confirmed",
        "control-flow-confirmed", "assembly-matched", "intentional-mismatch"))
    ledger.add_argument("--reason")
    ledger.add_argument("--reviewer")
    ledger.add_argument("--source-path")
    ledger.add_argument("--source-line", type=int)
    compare = subparsers.add_parser("compare")
    compare.add_argument("--profile", required=True)
    compare.add_argument("--reference-analysis", required=True)
    compare.add_argument("--rebuilt-analysis", required=True)
    compare.add_argument("--output", required=True)
    compare.add_argument("--text-output")
    compare.add_argument("--require", choices=("exact-image", "exact-sections", "normalized-functions"))
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

    if args.command == "analyze":
        try:
            profile = load_profile(Path(args.profile), os.environ)
            output = Path(args.output) if args.output else profile.output_dir / "run-summary.json"
            ledger_path = None if args.ledger is None else Path(args.ledger)
            report = run_analysis(profile, output_path=output, ledger_path=ledger_path)
            acceptance = report["acceptance"]
            print(f"analysis {'complete' if report['complete'] else 'incomplete'}; "
                  f"analyzers={len(report['analyzers'])} comparisons={len(report['comparisons'])} "
                  f"{acceptance['requirement']}={'PASS' if acceptance['passed'] else 'FAIL'}")
            return 0 if report["complete"] and acceptance["passed"] else 1
        except (OSError, ValueError, ValidationError, RunnerError) as error:
            print(f"binrecon: {error}", file=sys.stderr)
            return 1

    if args.command == "ledger":
        try:
            profile = load_profile(Path(args.profile), os.environ)
            transition_requested = any(value is not None for value in
                (args.address, args.status, args.reason, args.reviewer,
                 args.source_path, args.source_line))
            if (args.address is None) != (args.status is None):
                raise LedgerError("--address and --status must be supplied together")
            if transition_requested and (args.address is None or args.status is None):
                raise LedgerError("--address and --status are required for transition fields")
            if (args.source_path is None) != (args.source_line is None):
                raise LedgerError("--source-path and --source-line must be supplied together")
            path = Path(args.ledger)
            with LedgerLock(path):
                document, snapshot = load_ledger(
                    path, profile.reference_identity, profile.rebuilt_identity
                )
                if transition_requested:
                    document = transition(document, args.address, args.status,
                        profile.reference_identity, profile.rebuilt_identity,
                        reason=args.reason, reviewer=args.reviewer,
                        source_path=args.source_path, source_line=args.source_line)
                    write_ledger(path, document, profile.reference_identity,
                        profile.rebuilt_identity, expected_snapshot=snapshot,
                        protected=[profile.source_path])
            counts = {}
            for item in document["entries"]:
                counts[item["status"]] = counts.get(item["status"], 0) + 1
            statuses = " ".join(f"{key}={counts[key]}" for key in sorted(counts))
            print(f"ledger {path.resolve(strict=False)} entries={len(document['entries'])}"
                  + (f" {statuses}" if statuses else ""))
            return 0
        except (OSError, ValueError, ValidationError, LedgerError) as error:
            print(f"binrecon: {error}", file=sys.stderr)
            return 1

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

    if args.command == "compare":
        try:
            profile = load_profile(Path(args.profile), os.environ)
            analysis_paths = [Path(args.reference_analysis), Path(args.rebuilt_analysis)]
            protected = [profile.source_path, profile.reference.path, profile.rebuilt.path,
                         *analysis_paths]
            output = None if args.output == "-" else Path(args.output)
            text_output = (None if args.text_output in (None, "-") else Path(args.text_output))
            if args.output == "-" and args.text_output == "-":
                raise ValueError("JSON and text outputs cannot both use stdout")
            for destination in (output, text_output):
                if destination is not None: _reject_output_alias(destination, protected)
            if output is not None and text_output is not None:
                _reject_output_alias(text_output, [output])
            documents = [_read_json_snapshot(path) for path in analysis_paths]
            for document in documents:
                preflight_json(document); validate_document("analysis-v1", document)
                validate_analysis_semantics(document)
            requirement = args.require or profile.document["comparison"]["acceptance"]
            report = compare_artifacts(profile.reference.path, profile.rebuilt.path,
                                       documents[0], documents[1], requirement,
                                       profile.document["comparison"]["ignore_metadata"])
            json_text = json.dumps(report, sort_keys=True, separators=(",", ":"),
                                   allow_nan=False) + "\n"
            plain_text = format_text_report(report)
            if output is None: sys.stdout.write(json_text)
            else: _atomic_text(output, json_text, protected)
            if args.text_output == "-": sys.stdout.write(plain_text)
            elif text_output is not None: _atomic_text(text_output, plain_text, protected + ([output] if output else []))
        except (OSError, ValueError, ValidationError, ComparisonError) as error:
            print(f"binrecon: {error}", file=sys.stderr); return 1
        return 0 if report["selected"]["passed"] else 1

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
    if output.is_symlink(): raise ValueError("output is a symlink")
    resolved = output.resolve(strict=False)
    for source in inputs:
        if resolved == source.resolve(strict=False): raise ValueError("output aliases an input")
        if output.exists() and source.exists() and os.path.samefile(output, source):
            raise ValueError("output aliases an input")


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
