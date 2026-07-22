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
import threading
import time
from typing import Callable

from binrecon.identity import InputIdentity, assert_identity
from binrecon.macho import MachOFormatError, read_macho
from binrecon.schema import validate_analysis_semantics, validate_document


class AngrAdapterError(RuntimeError):
    """Raised when angr cannot produce a trustworthy analysis snapshot."""


_MAX_OUTPUT = 16 * 1024 * 1024
_MAX_LOG = 4 * 1024 * 1024
_CHUNK = 1024 * 1024
_TRUNCATION_MARKER = b"\n[truncated]\n"
_DRAIN_GRACE_SECONDS = 0.25
_DRAIN_POLL_SECONDS = 0.01
_DRAIN_JOIN_SECONDS = 2


class _BoundedPipeCapture:
    """Continuously drain a child pipe while retaining only a bounded prefix."""

    def __init__(self):
        read_descriptor, write_descriptor = os.pipe()
        try:
            os.set_blocking(read_descriptor, False)
            self._read_descriptor = read_descriptor
            self.stdout = os.fdopen(write_descriptor, "wb", buffering=0)
            write_descriptor = None
            self._buffer = bytearray()
            self._truncated = False
            self._error = None
            self._stop = threading.Event()
            self._stop_deadline = None
            self._thread = threading.Thread(target=self._drain,
                name="binrecon-angr-log-drain", daemon=False)
            self._thread.start()
        except BaseException:
            try: os.close(read_descriptor)
            except OSError: pass
            if write_descriptor is not None:
                try: os.close(write_descriptor)
                except OSError: pass
            else:
                try: self.stdout.close()
                except BaseException: pass
            raise

    def _drain(self):
        try:
            while True:
                if (self._stop.is_set() and self._stop_deadline is not None
                        and time.monotonic() >= self._stop_deadline):
                    break
                try:
                    chunk = os.read(self._read_descriptor, _CHUNK)
                except BlockingIOError:
                    if self._stop.is_set(): time.sleep(_DRAIN_POLL_SECONDS)
                    else: self._stop.wait(_DRAIN_POLL_SECONDS)
                    continue
                if not chunk: break
                remaining = _MAX_LOG - len(self._buffer)
                if remaining > 0: self._buffer.extend(chunk[:remaining])
                if len(chunk) > remaining: self._truncated = True
        except BaseException as error:
            self._error = error
        finally:
            try: os.close(self._read_descriptor)
            except OSError: pass

    def close_writer(self):
        if not self.stdout.closed:
            self.stdout.close()

    def stop(self):
        if not self._stop.is_set():
            self._stop_deadline = time.monotonic() + _DRAIN_GRACE_SECONDS
            self._stop.set()

    def finish(self) -> bytes:
        self.stop()
        self._thread.join(_DRAIN_JOIN_SECONDS)
        if self._thread.is_alive():
            raise AngrAdapterError("angr diagnostic drain thread did not terminate")
        if self._error is not None:
            raise AngrAdapterError(f"angr diagnostic drain failed: {self._error}") from self._error
        value = bytes(self._buffer)
        return value + _TRUNCATION_MARKER if self._truncated else value

    def cleanup(self):
        error = None
        try: self.close_writer()
        except BaseException as caught: error = caught
        self.stop()
        self._thread.join(_DRAIN_JOIN_SECONDS)
        if self._thread.is_alive() and error is None:
            error = AngrAdapterError("angr diagnostic drain thread did not terminate")
        if error is not None: raise error


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


def _publish_log(path: Path, captured: bytes) -> None:
    _atomic_text(path, captured.decode("utf-8", errors="replace"))


def _preserve_primary_log(path: Path, captured: bytes, primary: BaseException) -> None:
    try: _publish_log(path, captured)
    except BaseException as error: primary.add_note(f"could not publish angr log: {error}")


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
    peer_artifact = "rebuilt" if artifact == "reference" else "reference"
    peer_identity = _identity(profile, peer_artifact)
    try: assert_identity(peer_identity)
    except (OSError, ValueError) as error:
        raise AngrAdapterError(f"peer input identity is no longer stable: {error}") from error
    _reject_alias(destination, identity.path, "destination"); _reject_alias(log_path, identity.path, "log path")
    _reject_alias(destination, peer_identity.path, "destination (peer artifact)")
    _reject_alias(log_path, peer_identity.path, "log path (peer artifact)")
    _reject_peer_alias(destination, log_path)
    workspace = Path(tempfile.mkdtemp(prefix=f".{destination.name}.angr-work-", dir=destination.parent))
    try:
        output = workspace / "analysis.json"; config_path = workspace / "config.json"
        layout_path = workspace / "layout.json"
        for temporary, label in ((output, "output temporary"), (config_path, "config temporary"),
                                 (layout_path, "layout temporary")):
            _reject_alias(temporary, identity.path, label)
            _reject_alias(temporary, peer_identity.path, label + " (peer artifact)")
        script = Path(__file__).parents[2] / "adapters" / "angr" / "export_analysis.py"
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
                "--size", str(identity.size), "--sha256", identity.sha256]
        capture = _BoundedPipeCapture()
        primary = None
        cause = None
        try:
            completed = runner(argv, stdout=capture.stdout, stderr=subprocess.STDOUT,
                               timeout=timeout, shell=False, check=False)
            if completed.returncode != 0:
                primary = AngrAdapterError(f"angr failed with exit code {completed.returncode}")
        except subprocess.TimeoutExpired as error:
            primary = AngrAdapterError(f"angr timed out after {timeout} seconds"); cause = error
        except OSError as error:
            primary = AngrAdapterError(f"could not start angr: {error}"); cause = error
        except BaseException as error:
            primary = error
        finally:
            try: capture.close_writer()
            except BaseException as close_error:
                if primary is None: primary = close_error
                else: primary.add_note(f"angr diagnostic pipe close failed: {close_error}")
            capture.stop()
        drain_error = None
        try:
            captured = capture.finish()
        except BaseException as error:
            drain_error = error
            captured = b""
        cleanup_error = None
        try: capture.cleanup()
        except BaseException as error: cleanup_error = error
        if primary is not None:
            if drain_error is not None: primary.add_note(f"angr diagnostic drain failed: {drain_error}")
            if cleanup_error is not None: primary.add_note(f"angr diagnostic cleanup failed: {cleanup_error}")
            _preserve_primary_log(log_path, captured, primary)
            if cause is not None: raise primary from cause
            raise primary
        if drain_error is not None: raise drain_error
        if cleanup_error is not None: raise cleanup_error
        _publish_log(log_path, captured)
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
        shutil.rmtree(workspace); workspace = None
        try: assert_identity(identity)
        except (OSError, ValueError) as error: raise AngrAdapterError(f"input identity changed during angr analysis: {error}") from error
        try: assert_identity(peer_identity)
        except (OSError, ValueError) as error: raise AngrAdapterError(f"peer input identity changed during angr analysis: {error}") from error
        _reject_alias(destination, identity.path, "destination")
        _reject_alias(log_path, identity.path, "log path")
        _reject_alias(destination, peer_identity.path, "destination (peer artifact)")
        _reject_alias(log_path, peer_identity.path, "log path (peer artifact)")
        _reject_peer_alias(destination, log_path)
        _atomic_text(destination, json.dumps(document, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n")
        return document
    finally:
        if workspace is not None:
            primary = sys.exc_info()[1]
            try: shutil.rmtree(workspace)
            except OSError as error:
                if primary is None: raise
                primary.add_note(f"workspace cleanup failed: {error}")
