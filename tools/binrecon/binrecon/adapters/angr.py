"""Host-side orchestration for deterministic angr exports."""

from __future__ import annotations

import json
import hashlib
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
from typing import Callable

from binrecon.identity import InputIdentity, assert_identity
from binrecon.macho import MachOFormatError, read_macho
from binrecon.schema import validate_analysis_semantics, validate_document


class AngrAdapterError(RuntimeError):
    """Raised when angr cannot produce a trustworthy analysis snapshot."""


_MAX_OUTPUT = 16 * 1024 * 1024
_MAX_LOG = 4 * 1024 * 1024
_CHUNK = 1024 * 1024


def _configuration(profile) -> dict:
    try:
        value = profile.document["analyzers"]["angr"]
    except (KeyError, TypeError) as error:
        raise AngrAdapterError("angr analyzer configuration is missing") from error
    if not value.get("enabled", False):
        raise AngrAdapterError("angr analyzer is not enabled")
    if value.get("version") != "9.3.0":
        raise AngrAdapterError("angr 9.3.0 must be configured exactly")
    return value


def _identity(profile, artifact: str) -> InputIdentity:
    if artifact not in ("reference", "rebuilt"):
        raise AngrAdapterError(f"unknown artifact {artifact!r}")
    return getattr(profile, f"{artifact}_identity")


def _thaw(value):
    if hasattr(value, "items"):
        return {key: _thaw(item) for key, item in value.items()}
    if isinstance(value, (tuple, list)):
        return [_thaw(item) for item in value]
    return value


def _layout(profile, identity: InputIdentity) -> dict:
    try:
        canonical = read_macho(identity.path)
        metadata = canonical["extensions"]["macho"]["sections"]
        by_ordinal = {item["ordinal"]: item for item in metadata}
        sections = []
        for ordinal, section in enumerate(canonical["sections"], 1):
            detail = by_ordinal[ordinal]
            sections.append({**section, "ordinal": ordinal,
                             "initialized": detail["initialized"]})
        symbols = canonical["symbols"]
        relocations = canonical["relocations"]
    except (MachOFormatError, KeyError, ValueError):
        sections = []
        source = identity.path.read_bytes()
        for ordinal, region in enumerate(profile.document.get("regions", ()), 1):
            item = _thaw(region)
            offset, size = item["offset"], item["size"]
            if offset > len(source) or size > len(source) - offset:
                raise AngrAdapterError(f"profile region {item['name']!r} exceeds analyzed input")
            item.update({"ordinal": ordinal, "initialized": True,
                         "sha256": hashlib.sha256(source[offset:offset + size]).hexdigest().upper()})
            sections.append(item)
        symbols, relocations = [], []
    names = set(profile.document.get("comparison", {}).get("entry_points", ()))
    entry_points = sorted({item["address"] for item in symbols if item["name"] in names})
    if not entry_points and sections:
        entry_points = [int(profile.document.get("image_base", sections[0]["address"]))]
    return {"image_base": int(profile.document.get("image_base", 0)),
            "entry_points": entry_points, "sections": sections,
            "symbols": symbols, "relocations": relocations}


def _atomic_text(path: Path, text: str) -> None:
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".write",
                                             dir=path.parent)
    owned = descriptor
    try:
        stream = os.fdopen(descriptor, "w", encoding="utf-8", newline="\n")
        owned = None
        with stream:
            stream.write(text); stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, path)
    except BaseException:
        if owned is not None: os.close(owned)
        try: os.unlink(temporary)
        except FileNotFoundError: pass
        raise


def _bounded(value) -> str:
    if value is None: return ""
    if isinstance(value, bytes): value = value.decode("utf-8", errors="replace")
    data = str(value).encode("utf-8", errors="replace")
    if len(data) > _MAX_LOG: data = data[:_MAX_LOG] + b"\n[truncated]\n"
    return data.decode("utf-8", errors="replace")


def _publish_log(path: Path, stdout, stderr) -> None:
    _atomic_text(path, f"=== stdout ===\n{_bounded(stdout)}\n=== stderr ===\n{_bounded(stderr)}\n")


def _reject_alias(path: Path, input_path: Path, label: str) -> None:
    if path.resolve(strict=False) == input_path:
        raise AngrAdapterError(f"{label} aliases analyzed input")
    try:
        if path.exists() and os.path.samefile(path, input_path):
            raise AngrAdapterError(f"{label} aliases analyzed input")
    except OSError as error:
        raise AngrAdapterError(f"could not validate {label}: {error}") from error


def _reject_peer_alias(first: Path, second: Path) -> None:
    if first == second:
        raise AngrAdapterError("destination and log path alias each other")
    try:
        if first.exists() and second.exists() and os.path.samefile(first, second):
            raise AngrAdapterError("destination and log path alias each other")
    except OSError as error:
        raise AngrAdapterError(f"could not validate destination and log paths: {error}") from error


def _read_snapshot(path: Path) -> dict:
    if path.is_symlink(): raise AngrAdapterError("angr output is a symlink")
    flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOFOLLOW", 0)
    try: descriptor = os.open(path, flags)
    except OSError as error: raise AngrAdapterError(f"could not open angr output safely: {error}") from error
    try:
        initial = os.fstat(descriptor)
        reparse = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
        if not stat.S_ISREG(initial.st_mode) or initial.st_nlink != 1 or getattr(initial, "st_file_attributes", 0) & reparse:
            raise AngrAdapterError("angr output is not a private regular file")
        if initial.st_size > _MAX_OUTPUT: raise AngrAdapterError("angr output exceeds maximum JSON size")
        chunks, total = [], 0
        while True:
            chunk = os.read(descriptor, min(_CHUNK, _MAX_OUTPUT + 1 - total))
            if not chunk: break
            chunks.append(chunk); total += len(chunk)
            if total > _MAX_OUTPUT: raise AngrAdapterError("angr output exceeds maximum JSON size")
        final = os.fstat(descriptor)
        fields = ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns", "st_nlink")
        if total != initial.st_size or any(getattr(initial, f) != getattr(final, f) for f in fields):
            raise AngrAdapterError("angr output changed while reading")
    finally: os.close(descriptor)
    try: document = json.loads(b"".join(chunks).decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise AngrAdapterError(f"angr output is malformed JSON: {error}") from error
    if not isinstance(document, dict): raise AngrAdapterError("angr output JSON root must be an object")
    return document


def _validate_angr_contract(document: dict) -> None:
    try:
        extension = document["extensions"]["angr"]
        errors = extension["cfg"]["errors"]
        checks = extension["symbolic_checks"]
    except (KeyError, TypeError) as error:
        raise AngrAdapterError("angr output contract is incomplete") from error
    if not isinstance(errors, list) or not all(isinstance(item, str) for item in errors):
        raise AngrAdapterError("angr output contract cfg.errors must be strings")
    allowed = {"passed", "failed", "unsupported", "limit-reached"}
    names = set()
    if not isinstance(checks, list):
        raise AngrAdapterError("angr output contract symbolic_checks must be an array")
    for check in checks:
        if (not isinstance(check, dict) or not isinstance(check.get("name"), str)
                or check.get("status") not in allowed or check["name"] in names):
            raise AngrAdapterError("angr output contract has an invalid symbolic check")
        names.add(check["name"])


def export_with_angr(profile, artifact: str, destination: Path, *,
                     runner: Callable = subprocess.run) -> dict:
    configuration = _configuration(profile)
    executable = Path(configuration.get("executable", "")).resolve(strict=False)
    if not executable.is_file(): raise AngrAdapterError(f"angr Python executable does not exist: {executable}")
    timeout = configuration.get("timeout_seconds")
    if not isinstance(timeout, int) or isinstance(timeout, bool) or timeout < 1:
        raise AngrAdapterError("angr timeout_seconds must be a positive integer")
    identity = _identity(profile, artifact)
    try: assert_identity(identity)
    except (OSError, ValueError) as error: raise AngrAdapterError(f"input identity is no longer stable: {error}") from error
    destination = Path(destination).resolve(strict=False); destination.parent.mkdir(parents=True, exist_ok=True)
    log_path = destination.with_suffix(destination.suffix + ".angr.log")
    _reject_alias(destination, identity.path, "destination"); _reject_alias(log_path, identity.path, "log path")
    _reject_peer_alias(destination, log_path)
    workspace = Path(tempfile.mkdtemp(prefix=f".{destination.name}.angr-work-", dir=destination.parent))
    output = workspace / "analysis.json"; config_path = workspace / "config.json"
    layout_path = workspace / "layout.json"
    script = Path(__file__).parents[2] / "adapters" / "angr" / "export_analysis.py"
    peer_artifact = "rebuilt" if artifact == "reference" else "reference"
    peer_identity = _identity(profile, peer_artifact)
    try: assert_identity(peer_identity)
    except (OSError, ValueError) as error:
        raise AngrAdapterError(f"peer input identity is no longer stable: {error}") from error
    config = {"profile": _thaw(profile.document), "artifact": artifact,
              "peer_artifact": peer_artifact,
              "peer_input": {"path": str(peer_identity.path), "size": peer_identity.size,
                             "sha256": peer_identity.sha256},
              "peer_layout": _layout(profile, peer_identity)}
    _atomic_text(config_path, json.dumps(config, sort_keys=True, separators=(",", ":")) + "\n")
    _atomic_text(layout_path, json.dumps(_layout(profile, identity), sort_keys=True,
                                        separators=(",", ":")) + "\n")
    argv = [str(executable), str(script.resolve()), "--input", str(identity.path),
            "--output", str(output), "--config", str(config_path), "--layout", str(layout_path),
            "--size", str(identity.size),
            "--sha256", identity.sha256]
    try:
        try:
            completed = runner(argv, capture_output=True, text=True, timeout=timeout,
                               shell=False, check=False)
        except subprocess.TimeoutExpired as error:
            _publish_log(log_path, error.stdout, error.stderr)
            raise AngrAdapterError(f"angr timed out after {timeout} seconds") from error
        except OSError as error:
            _publish_log(log_path, "", str(error))
            raise AngrAdapterError(f"could not start angr: {error}") from error
        _publish_log(log_path, completed.stdout, completed.stderr)
        if completed.returncode != 0: raise AngrAdapterError(f"angr failed with exit code {completed.returncode}")
        if not output.is_file(): raise AngrAdapterError("angr did not produce a fresh analysis output")
        try:
            document = _read_snapshot(output); validate_document("analysis-v1", document); validate_analysis_semantics(document)
            _validate_angr_contract(document)
        except Exception as error: raise AngrAdapterError(f"angr output is invalid: {error}") from error
        analyzer = document["analyzer"]
        if analyzer["name"] != "angr": raise AngrAdapterError("angr output analyzer name must be exactly 'angr'")
        if analyzer["version"] != configuration["version"]: raise AngrAdapterError("angr output analyzer version does not match configured version")
        exported = document["input"]
        if exported["size"] != identity.size or exported["sha256"].upper() != identity.sha256 or Path(exported["path"]).resolve(strict=False) != identity.path:
            raise AngrAdapterError("angr output input identity does not match requested input")
        try: assert_identity(identity)
        except (OSError, ValueError) as error: raise AngrAdapterError(f"input identity changed during angr analysis: {error}") from error
        try: assert_identity(peer_identity)
        except (OSError, ValueError) as error: raise AngrAdapterError(f"peer input identity changed during angr analysis: {error}") from error
        shutil.rmtree(workspace); workspace = None
        _atomic_text(destination, json.dumps(document, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n")
        return document
    finally:
        if workspace is not None:
            primary = sys.exc_info()[1]
            try: shutil.rmtree(workspace)
            except OSError as error:
                if primary is None: raise
                primary.add_note(f"workspace cleanup failed: {error}")
