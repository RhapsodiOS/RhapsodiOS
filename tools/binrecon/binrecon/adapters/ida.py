"""Host-side orchestration for deterministic IDA exports."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
from typing import Callable

from binrecon.identity import InputIdentity, assert_identity
from binrecon.schema import (
    validate_analysis_semantics,
    validate_document,
)


class IdaAdapterError(RuntimeError):
    """Raised when IDA cannot produce a trustworthy analysis snapshot."""


_MAX_ANALYSIS_BYTES = 16 * 1024 * 1024
_READ_CHUNK_SIZE = 1024 * 1024


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


def _write_log(path: Path, native_log: Path, stdout, stderr) -> None:
    native = ""
    try:
        with native_log.open("rb") as stream:
            native = stream.read(4 * 1024 * 1024 + 1)
        if len(native) > 4 * 1024 * 1024:
            native = native[: 4 * 1024 * 1024] + b"\n[native log truncated]\n"
    except FileNotFoundError:
        pass
    text = (
        "=== IDA native log ===\n"
        + _diagnostic_text(native)
        + "\n=== stdout ===\n"
        + _diagnostic_text(stdout)
        + "\n=== stderr ===\n"
        + _diagnostic_text(stderr)
    )
    _atomic_text(path, text)


def _atomic_text(path: Path, value: str) -> None:
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".write", dir=path.parent
    )
    owned_descriptor = descriptor
    try:
        stream = os.fdopen(descriptor, "w", encoding="utf-8", newline="\n")
        owned_descriptor = None
        with stream:
            stream.write(value)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_name, path)
    except BaseException:
        if owned_descriptor is not None:
            os.close(owned_descriptor)
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def _diagnostic_text(value) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return str(value)


def _read_analysis_snapshot(
    path: Path,
    *,
    opener=os.open,
    fstat=os.fstat,
    reader=os.read,
    closer=os.close,
) -> dict:
    if path.is_symlink():
        raise IdaAdapterError("IDA output is a symlink")
    flags = (
        os.O_RDONLY
        | getattr(os, "O_BINARY", 0)
        | getattr(os, "O_NONBLOCK", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    try:
        descriptor = opener(path, flags)
    except OSError as error:
        raise IdaAdapterError(f"could not open IDA output safely: {error}") from error
    try:
        initial = fstat(descriptor)
        if not stat.S_ISREG(initial.st_mode):
            raise IdaAdapterError("IDA output is not a regular file")
        if initial.st_nlink != 1:
            raise IdaAdapterError("IDA output must be a single-link file")
        reparse_flag = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
        if getattr(initial, "st_file_attributes", 0) & reparse_flag:
            raise IdaAdapterError("IDA output is a reparse point")
        if initial.st_size > _MAX_ANALYSIS_BYTES:
            raise IdaAdapterError("IDA output exceeds maximum JSON size")
        chunks = []
        total = 0
        while True:
            chunk = reader(descriptor, min(_READ_CHUNK_SIZE, _MAX_ANALYSIS_BYTES + 1 - total))
            if not chunk:
                break
            chunks.append(chunk)
            total += len(chunk)
            if total > _MAX_ANALYSIS_BYTES:
                raise IdaAdapterError("IDA output exceeds maximum JSON size")
        final = fstat(descriptor)
        stable_fields = (
            "st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns", "st_nlink"
        )
        if total != initial.st_size or any(
            getattr(initial, field) != getattr(final, field) for field in stable_fields
        ):
            raise IdaAdapterError("IDA output changed while reading")
    finally:
        closer(descriptor)
    try:
        document = json.loads(b"".join(chunks).decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise IdaAdapterError(f"IDA output is malformed JSON: {error}") from error
    if not isinstance(document, dict):
        raise IdaAdapterError("IDA output JSON root must be an object")
    return document


def _reject_input_alias(path: Path, input_path: Path, label: str) -> None:
    resolved = path.resolve(strict=False)
    if resolved == input_path:
        raise IdaAdapterError(f"{label} aliases analyzed input")
    try:
        if path.exists() and os.path.samefile(path, input_path):
            raise IdaAdapterError(f"{label} aliases analyzed input")
    except OSError as error:
        raise IdaAdapterError(f"could not validate {label} path: {error}") from error


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
    _reject_input_alias(destination, identity.path, "destination")
    _reject_input_alias(log_path, identity.path, "log path")
    script = Path(__file__).parents[2] / "adapters" / "ida" / "export_analysis.py"
    workspace = Path(tempfile.mkdtemp(
        prefix=f".{destination.name}.ida-work-", dir=destination.parent
    ))
    temporary = workspace / "analysis.tmp.json"
    database = workspace / "analysis.i64"
    native_log = workspace / "ida-native.log"
    argv = [
        str(executable),
        "-c",
        "-A",
        f"-o{database}",
        f"-L{native_log}",
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
            _write_log(log_path, native_log, error.stdout, error.stderr)
            raise IdaAdapterError(f"IDA timed out after {timeout} seconds") from error
        except OSError as error:
            _write_log(log_path, native_log, "", str(error) + "\n")
            raise IdaAdapterError(f"could not start IDA: {error}") from error

        _write_log(log_path, native_log, completed.stdout, completed.stderr)
        if completed.returncode != 0:
            raise IdaAdapterError(f"IDA failed with exit code {completed.returncode}")
        if not temporary.is_file():
            raise IdaAdapterError("IDA did not produce a fresh analysis output")
        try:
            document = _read_analysis_snapshot(temporary)
            validate_document("analysis-v1", document)
            validate_analysis_semantics(document)
        except Exception as error:
            raise IdaAdapterError(f"IDA output is invalid: {error}") from error

        analyzer = document["analyzer"]
        if analyzer["name"] != "IDA":
            raise IdaAdapterError("IDA output analyzer name must be exactly 'IDA'")
        configured_version = configuration.get("version")
        if configured_version is not None and analyzer["version"] != configured_version:
            raise IdaAdapterError(
                f"IDA output analyzer version {analyzer['version']!r} does not match "
                f"configured version {configured_version!r}"
            )
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
            raise IdaAdapterError(
                f"input identity changed during IDA analysis: {error}"
            ) from error

        shutil.rmtree(workspace)
        workspace = None
        publication = json.dumps(
            document, sort_keys=True, separators=(",", ":"), ensure_ascii=False
        ) + "\n"
        _atomic_text(destination, publication)
        return document
    finally:
        if workspace is not None:
            shutil.rmtree(workspace)
