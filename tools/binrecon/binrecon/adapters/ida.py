"""Host-side orchestration for deterministic IDA exports."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
from typing import Callable

from binrecon.identity import InputIdentity, assert_identity
from binrecon.schema import (
    load_json,
    validate_analysis_semantics,
    validate_document,
)


class IdaAdapterError(RuntimeError):
    """Raised when IDA cannot produce a trustworthy analysis snapshot."""


def _configuration(profile) -> dict:
    try:
        configuration = profile.document["analyzers"]["ida"]
    except (KeyError, TypeError) as error:
        raise IdaAdapterError("IDA analyzer configuration is missing") from error
    if not configuration.get("enabled", False):
        raise IdaAdapterError("IDA analyzer is not enabled")
    return configuration


def _identity(profile, artifact: str) -> InputIdentity:
    if artifact not in ("reference", "rebuilt"):
        raise IdaAdapterError(f"unknown artifact {artifact!r}")
    return getattr(profile, f"{artifact}_identity")


def _script_command(script: Path, output: Path, identity: InputIdentity) -> str:
    return subprocess.list2cmdline(
        [
            str(script),
            "--output",
            str(output),
            "--input",
            str(identity.path),
            "--size",
            str(identity.size),
            "--sha256",
            identity.sha256,
        ]
    )


def _write_log(path: Path, completed) -> None:
    stdout = _diagnostic_text(completed.stdout)
    stderr = _diagnostic_text(completed.stderr)
    path.write_text(stdout + stderr, encoding="utf-8")


def _diagnostic_text(value) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return str(value)


def export_with_ida(
    profile,
    artifact: str,
    destination: Path,
    *,
    runner: Callable = subprocess.run,
) -> dict:
    """Run configured IDA and atomically publish a validated analysis document."""
    configuration = _configuration(profile)
    executable_value = configuration.get("executable")
    if not executable_value:
        raise IdaAdapterError("IDA executable must be configured explicitly")
    executable = Path(executable_value).resolve(strict=False)
    if not executable.is_file():
        raise IdaAdapterError(f"IDA executable does not exist: {executable}")
    timeout = configuration.get("timeout_seconds")
    if not isinstance(timeout, int) or isinstance(timeout, bool) or timeout < 1:
        raise IdaAdapterError("IDA timeout_seconds must be a positive integer")

    identity = _identity(profile, artifact)
    try:
        assert_identity(identity)
    except (OSError, ValueError) as error:
        raise IdaAdapterError(f"input identity is no longer stable: {error}") from error

    destination = Path(destination).resolve(strict=False)
    destination.parent.mkdir(parents=True, exist_ok=True)
    log_path = destination.with_suffix(destination.suffix + ".ida.log")
    script = Path(__file__).parents[2] / "adapters" / "ida" / "export_analysis.py"
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{destination.name}.", suffix=".ida.tmp.json", dir=destination.parent
    )
    os.close(descriptor)
    temporary = Path(temporary_name)
    temporary.unlink()
    argv = [
        str(executable),
        "-A",
        "-S" + _script_command(script.resolve(), temporary, identity),
        str(identity.path),
    ]
    try:
        try:
            completed = runner(
                argv,
                capture_output=True,
                text=True,
                timeout=timeout,
                shell=False,
                check=False,
            )
        except subprocess.TimeoutExpired as error:
            log_path.write_text(
                _diagnostic_text(error.stdout) + _diagnostic_text(error.stderr),
                encoding="utf-8",
            )
            raise IdaAdapterError(f"IDA timed out after {timeout} seconds") from error
        except OSError as error:
            log_path.write_text(str(error) + "\n", encoding="utf-8")
            raise IdaAdapterError(f"could not start IDA: {error}") from error

        _write_log(log_path, completed)
        if completed.returncode != 0:
            raise IdaAdapterError(f"IDA failed with exit code {completed.returncode}")
        if not temporary.is_file():
            raise IdaAdapterError("IDA did not produce a fresh analysis output")
        try:
            document = load_json(temporary)
            validate_document("analysis-v1", document)
            validate_analysis_semantics(document)
        except Exception as error:
            raise IdaAdapterError(f"IDA output is invalid: {error}") from error

        exported_input = document["input"]
        if (
            exported_input["size"] != identity.size
            or exported_input["sha256"].upper() != identity.sha256
            or Path(exported_input["path"]).resolve(strict=False) != identity.path
        ):
            raise IdaAdapterError("IDA output input identity does not match requested input")
        try:
            assert_identity(identity)
        except (OSError, ValueError) as error:
            raise IdaAdapterError(f"input identity changed during IDA analysis: {error}") from error

        publication = json.dumps(
            document, sort_keys=True, separators=(",", ":"), ensure_ascii=False
        ) + "\n"
        temporary.write_text(publication, encoding="utf-8", newline="\n")
        os.replace(temporary, destination)
        return document
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
