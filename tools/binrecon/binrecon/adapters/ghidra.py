"""Host-side orchestration for deterministic Ghidra headless exports."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
from typing import Callable

from binrecon.identity import InputIdentity, assert_identity
from binrecon.macho import MachOFormatError, read_macho
from binrecon.schema import validate_analysis_semantics, validate_document


class GhidraAdapterError(RuntimeError):
    """Raised when Ghidra cannot produce a trustworthy analysis snapshot."""


_MAX_OUTPUT = 16 * 1024 * 1024
_CHUNK = 1024 * 1024
_LANGUAGE = "x86:LE:32:default"
_UNSUPPORTED_MACHO = re.compile(
    r"(?is)(?:mach-o|macho).{0,160}(?:unsupported|not supported|reject|"
    r"no (?:suitable|acceptable) loader)"
)


def _configuration(profile) -> dict:
    try:
        configuration = profile.document["analyzers"]["ghidra"]
    except (KeyError, TypeError) as error:
        raise GhidraAdapterError("Ghidra analyzer configuration is missing") from error
    if not configuration.get("enabled", False):
        raise GhidraAdapterError("Ghidra analyzer is not enabled")
    if configuration.get("version") != "12.1":
        raise GhidraAdapterError("Ghidra 12.1 must be configured exactly")
    return configuration


def _identity(profile, artifact: str) -> InputIdentity:
    if artifact not in ("reference", "rebuilt"):
        raise GhidraAdapterError(f"unknown artifact {artifact!r}")
    return getattr(profile, f"{artifact}_identity")


def _atomic_text(path: Path, value: str) -> None:
    descriptor, temporary = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".write", dir=path.parent
    )
    owned = descriptor
    try:
        stream = os.fdopen(descriptor, "w", encoding="utf-8", newline="\n")
        owned = None
        with stream:
            stream.write(value)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except BaseException:
        if owned is not None:
            os.close(owned)
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def _diagnostic(value) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return str(value)


def _append_log(path: Path, heading: str, stdout, stderr, native: Path,
                script_log: Path) -> None:
    previous = path.read_text(encoding="utf-8") if path.exists() else ""
    native_text = ""
    try:
        native_bytes = native.read_bytes()
        if len(native_bytes) > 4 * 1024 * 1024:
            native_bytes = native_bytes[: 4 * 1024 * 1024] + b"\n[truncated]\n"
        native_text = _diagnostic(native_bytes)
    except FileNotFoundError:
        pass
    script_text = ""
    try:
        script_bytes = script_log.read_bytes()
        if len(script_bytes) > 4 * 1024 * 1024:
            script_bytes = script_bytes[: 4 * 1024 * 1024] + b"\n[truncated]\n"
        script_text = _diagnostic(script_bytes)
    except FileNotFoundError:
        pass
    _atomic_text(
        path,
        previous + f"=== {heading}: native ===\n{native_text}\n"
        f"=== {heading}: script ===\n{script_text}\n"
        f"=== {heading}: stdout ===\n{_diagnostic(stdout)}\n"
        f"=== {heading}: stderr ===\n{_diagnostic(stderr)}\n",
    )


def _reject_alias(path: Path, input_path: Path, label: str) -> None:
    if path.resolve(strict=False) == input_path:
        raise GhidraAdapterError(f"{label} aliases analyzed input")
    try:
        if path.exists() and os.path.samefile(path, input_path):
            raise GhidraAdapterError(f"{label} aliases analyzed input")
    except OSError as error:
        raise GhidraAdapterError(f"could not validate {label}: {error}") from error


def _reject_peer_alias(first: Path, second: Path) -> None:
    if first == second:
        raise GhidraAdapterError("destination and log path alias each other")
    try:
        if first.exists() and second.exists() and os.path.samefile(first, second):
            raise GhidraAdapterError("destination and log path alias each other")
    except OSError as error:
        raise GhidraAdapterError(f"could not validate destination and log paths: {error}") from error


def _read_snapshot(path: Path) -> dict:
    if path.is_symlink():
        raise GhidraAdapterError("Ghidra output is a symlink")
    flags = (os.O_RDONLY | getattr(os, "O_BINARY", 0) |
             getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOFOLLOW", 0))
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise GhidraAdapterError(f"could not open Ghidra output safely: {error}") from error
    try:
        initial = os.fstat(descriptor)
        if not stat.S_ISREG(initial.st_mode) or initial.st_nlink != 1:
            raise GhidraAdapterError("Ghidra output is not a private regular file")
        reparse = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
        if getattr(initial, "st_file_attributes", 0) & reparse:
            raise GhidraAdapterError("Ghidra output is a reparse point")
        if initial.st_size > _MAX_OUTPUT:
            raise GhidraAdapterError("Ghidra output exceeds maximum JSON size")
        chunks = []
        total = 0
        while True:
            chunk = os.read(descriptor, min(_CHUNK, _MAX_OUTPUT + 1 - total))
            if not chunk:
                break
            chunks.append(chunk)
            total += len(chunk)
            if total > _MAX_OUTPUT:
                raise GhidraAdapterError("Ghidra output exceeds maximum JSON size")
        final = os.fstat(descriptor)
        fields = ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns", "st_nlink")
        if total != initial.st_size or any(
            getattr(initial, field) != getattr(final, field) for field in fields
        ):
            raise GhidraAdapterError("Ghidra output changed while reading")
    finally:
        os.close(descriptor)
    try:
        document = json.loads(b"".join(chunks).decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise GhidraAdapterError(f"Ghidra output is malformed JSON: {error}") from error
    if not isinstance(document, dict):
        raise GhidraAdapterError("Ghidra output JSON root must be an object")
    return document


def _java_executable() -> Path:
    java_home = os.environ.get("JAVA_HOME")
    candidate = (Path(java_home) / "bin" / ("java.exe" if os.name == "nt" else "java")) if java_home else None
    if candidate is None or not candidate.is_file():
        located = shutil.which("java")
        if not located:
            raise GhidraAdapterError("Java 21 executable is missing")
        candidate = Path(located)
    return candidate.resolve(strict=True)


def _verify_java21(java: Path, runner: Callable) -> None:
    try:
        completed = runner(
            [str(java), "-version"], capture_output=True, text=True, timeout=10,
            shell=False, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise GhidraAdapterError(f"could not verify Java 21: {error}") from error
    version_text = _diagnostic(completed.stdout) + "\n" + _diagnostic(completed.stderr)
    match = re.search(r'(?:version\s+)?["\']?(\d+)(?:[.\s"\']|$)', version_text)
    if completed.returncode != 0 or match is None or match.group(1) != "21":
        raise GhidraAdapterError("Ghidra requires Java 21 exactly")


def _script_arguments(mode: str, output: Path, identity: InputIdentity,
                      layout: Path | None = None) -> list[str]:
    arguments = [mode]
    if layout is not None:
        arguments += ["--layout", str(layout)]
    if mode == "export":
        arguments += ["--output", str(output)]
    arguments += ["--input", str(identity.path), "--size", str(identity.size),
                  "--sha256", identity.sha256, "--language", _LANGUAGE]
    return arguments


def _command(executable: Path, workspace: Path, project: str,
             identity: InputIdentity, script: Path, output: Path,
             native_log: Path, script_log: Path, layout: Path | None) -> list[str]:
    argv = [str(executable), str(workspace), project, "-import", str(identity.path)]
    if layout is not None:
        argv += ["-loader", "BinaryLoader", "-processor", _LANGUAGE,
                 "-preScript", script.name,
                 *_script_arguments("prepare", output, identity, layout)]
    else:
        argv += ["-processor", _LANGUAGE]
    argv += ["-scriptPath", str(script.parent), "-log", str(native_log), "-scriptlog", str(script_log),
             "-postScript", script.name,
             *_script_arguments("export", output, identity, layout), "-deleteProject"]
    return argv


def _layout(profile, identity: InputIdentity) -> dict:
    try:
        macho = read_macho(identity.path)
    except (OSError, MachOFormatError) as error:
        raise GhidraAdapterError(f"cannot construct deterministic Mach-O fallback: {error}") from error
    configured_regions = profile.document.get("regions", ())
    regions = [dict(region) for region in configured_regions] if configured_regions else [
        {key: section[key] for key in ("name", "address", "offset", "size", "permissions")}
        for section in macho["sections"]
    ]
    macho_sections = {
        (section["name"], section["address"], section["offset"], section["size"]): section
        for section in macho["sections"]
    }
    for region in regions:
        matched = macho_sections.get((region["name"], region["address"],
                                      region["offset"], region["size"]))
        zero_fill = matched is not None and region["size"] > 0 and region["offset"] == 0
        region["initialized"] = (
            region["size"] == 0 or
            (not zero_fill and region["offset"] + region["size"] <= identity.size)
        )
    symbols = [{"name": item["name"], "address": item["address"]}
               for item in macho["symbols"] if item["name"]]
    by_name = {item["name"]: item["address"] for item in symbols}
    entries = []
    for entry in profile.document["comparison"].get("entry_points", ()):
        if entry in by_name:
            entries.append({"name": entry, "address": by_name[entry]})
        else:
            try:
                entries.append({"name": entry, "address": int(entry, 0)})
            except (TypeError, ValueError) as error:
                raise GhidraAdapterError(f"fallback entry point is unknown: {entry!r}") from error
    return {
        "schema_version": "ghidra-layout-v1", "language": _LANGUAGE,
        "input": {"path": str(identity.path), "size": identity.size,
                  "sha256": identity.sha256},
        "image_base": profile.document.get("image_base", 0),
        "sections": sorted(regions, key=lambda item: (item["address"], item["offset"], item["name"])),
        "symbols": sorted(symbols, key=lambda item: (item["address"], item["name"])),
        "entry_points": sorted(entries, key=lambda item: (item["address"], item["name"])),
    }


def _validate_output(document: dict, configuration: dict, identity: InputIdentity) -> None:
    validate_document("analysis-v1", document)
    validate_analysis_semantics(document)
    analyzer = document["analyzer"]
    if analyzer["name"] != "Ghidra":
        raise GhidraAdapterError("Ghidra output analyzer name is wrong")
    if analyzer["version"] != configuration["version"]:
        raise GhidraAdapterError("Ghidra output analyzer version does not match configured version")
    exported = document["input"]
    if (exported["size"] != identity.size or exported["sha256"].upper() != identity.sha256 or
            Path(exported["path"]).resolve(strict=False) != identity.path):
        raise GhidraAdapterError("Ghidra output input identity does not match requested input")
    extension = document.get("extensions", {}).get("ghidra", {})
    if extension.get("language") != _LANGUAGE:
        raise GhidraAdapterError("Ghidra output used the wrong processor language")


def export_with_ghidra(profile, artifact: str, destination: Path, *,
                       runner: Callable = subprocess.run) -> dict:
    """Run Ghidra headlessly and atomically publish validated canonical JSON."""
    configuration = _configuration(profile)
    executable_value = configuration.get("executable")
    if not executable_value:
        raise GhidraAdapterError("Ghidra executable must be configured explicitly")
    executable = Path(executable_value).resolve(strict=False)
    if not executable.is_file():
        raise GhidraAdapterError(f"Ghidra executable does not exist: {executable}")
    timeout = configuration.get("timeout_seconds")
    if not isinstance(timeout, int) or isinstance(timeout, bool) or timeout < 1:
        raise GhidraAdapterError("Ghidra timeout_seconds must be a positive integer")
    identity = _identity(profile, artifact)
    try:
        assert_identity(identity)
    except (OSError, ValueError) as error:
        raise GhidraAdapterError(f"input identity is no longer stable: {error}") from error

    destination = Path(destination).resolve(strict=False)
    destination.parent.mkdir(parents=True, exist_ok=True)
    log_path = destination.with_suffix(destination.suffix + ".ghidra.log")
    _reject_alias(destination, identity.path, "destination")
    _reject_alias(log_path, identity.path, "log path")
    _reject_peer_alias(destination, log_path)
    _verify_java21(_java_executable(), runner)
    workspace = Path(tempfile.mkdtemp(prefix=f".{destination.name}.ghidra-work-",
                                      dir=destination.parent))
    try:
        workspace.chmod(0o700)
    except OSError:
        pass
    run_token = workspace.name.rsplit("-", 1)[-1]
    output = workspace / "analysis.tmp.json"
    native_log = workspace / "ghidra-native.log"
    script_log = workspace / "ghidra-script.log"
    layout_path = workspace / "layout.json"
    script = (Path(__file__).parents[2] / "adapters" / "ghidra" / "ExportAnalysis.java").resolve()
    try:
        command = _command(executable, workspace, f"native-{run_token}", identity, script, output,
                           native_log, script_log, None)
        try:
            completed = runner(command, capture_output=True, text=True, timeout=timeout,
                               shell=False, check=False)
        except subprocess.TimeoutExpired as error:
            _append_log(log_path, "native", error.stdout, error.stderr, native_log, script_log)
            raise GhidraAdapterError(f"Ghidra timed out after {timeout} seconds") from error
        except OSError as error:
            _append_log(log_path, "native", "", str(error), native_log, script_log)
            raise GhidraAdapterError(f"could not start Ghidra: {error}") from error
        _append_log(log_path, "native", completed.stdout, completed.stderr, native_log, script_log)
        diagnostic = _diagnostic(completed.stdout) + "\n" + _diagnostic(completed.stderr)
        native_needs_fallback = _UNSUPPORTED_MACHO.search(diagnostic) is not None
        if completed.returncode != 0 or not output.is_file():
            if not native_needs_fallback:
                if completed.returncode == 0:
                    raise GhidraAdapterError("Ghidra did not produce a fresh analysis output")
                raise GhidraAdapterError(f"Ghidra failed with exit code {completed.returncode}")
            try:
                output.unlink(missing_ok=True)
            except OSError as error:
                raise GhidraAdapterError(f"could not reset fallback output: {error}") from error
            layout_document = _layout(profile, identity)
            _atomic_text(layout_path, json.dumps(layout_document, ensure_ascii=False,
                                                  sort_keys=True, separators=(",", ":")) + "\n")
            command = _command(executable, workspace, f"fallback-{run_token}", identity, script, output,
                               native_log, script_log, layout_path)
            try:
                completed = runner(command, capture_output=True, text=True, timeout=timeout,
                                   shell=False, check=False)
            except subprocess.TimeoutExpired as error:
                _append_log(log_path, "fallback", error.stdout, error.stderr, native_log, script_log)
                raise GhidraAdapterError(f"Ghidra fallback timed out after {timeout} seconds") from error
            except OSError as error:
                _append_log(log_path, "fallback", "", str(error), native_log, script_log)
                raise GhidraAdapterError(f"could not start Ghidra fallback: {error}") from error
            _append_log(log_path, "fallback", completed.stdout, completed.stderr, native_log, script_log)
            if completed.returncode != 0:
                raise GhidraAdapterError(f"Ghidra fallback failed with exit code {completed.returncode}")
        if not output.is_file():
            raise GhidraAdapterError("Ghidra did not produce a fresh analysis output")
        try:
            document = _read_snapshot(output)
            _validate_output(document, configuration, identity)
        except GhidraAdapterError:
            raise
        except Exception as error:
            raise GhidraAdapterError(f"Ghidra output is invalid: {error}") from error
        try:
            assert_identity(identity)
        except (OSError, ValueError) as error:
            raise GhidraAdapterError(f"input identity changed during Ghidra analysis: {error}") from error
        publication = json.dumps(document, ensure_ascii=False, sort_keys=True,
                                 separators=(",", ":")) + "\n"
        shutil.rmtree(workspace)
        workspace = None
        _atomic_text(destination, publication)
        return document
    finally:
        if workspace is not None:
            try:
                shutil.rmtree(workspace)
            except OSError as error:
                try:
                    previous = log_path.read_text(encoding="utf-8") if log_path.exists() else ""
                    _atomic_text(log_path, previous + f"=== cleanup ===\n{error}\n")
                except OSError:
                    pass
