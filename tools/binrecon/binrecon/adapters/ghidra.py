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
_MAX_DIAGNOSTIC = 1024 * 1024
_CHUNK = 1024 * 1024
_LANGUAGE = "x86:LE:32:default"
_NATIVE_LOADER_REJECTION = re.compile(
    r"^.*\bERROR\s+No load spec found for import file \(ProgramLoader\)\s*$"
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


def _bounded_diagnostic(value) -> str:
    encoded = _diagnostic(value).encode("utf-8", errors="replace")
    if len(encoded) > _MAX_DIAGNOSTIC:
        encoded = encoded[:_MAX_DIAGNOSTIC] + b"\n[truncated]\n"
    return encoded.decode("utf-8", errors="replace")


def _read_diagnostic(path: Path) -> tuple[str, bool]:
    """Read a bounded private regular diagnostic without following filesystem aliases."""
    if path.is_symlink():
        return "[unsafe diagnostic omitted]", False
    flags = (os.O_RDONLY | getattr(os, "O_BINARY", 0) |
             getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOFOLLOW", 0))
    try:
        descriptor = os.open(path, flags)
    except FileNotFoundError:
        return "", True
    except OSError:
        return "[unsafe diagnostic omitted]", False
    try:
        initial = os.fstat(descriptor)
        reparse = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
        if (not stat.S_ISREG(initial.st_mode) or initial.st_nlink != 1 or
                getattr(initial, "st_file_attributes", 0) & reparse):
            return "[unsafe diagnostic omitted]", False
        chunks = []
        total = 0
        while total <= _MAX_DIAGNOSTIC:
            chunk = os.read(descriptor, min(_CHUNK, _MAX_DIAGNOSTIC + 1 - total))
            if not chunk:
                break
            chunks.append(chunk)
            total += len(chunk)
        final = os.fstat(descriptor)
        fields = ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns", "st_nlink")
        if any(getattr(initial, field) != getattr(final, field) for field in fields):
            return "[unsafe diagnostic omitted]", False
        value = b"".join(chunks)
        if len(value) > _MAX_DIAGNOSTIC:
            value = value[:_MAX_DIAGNOSTIC] + b"\n[truncated]\n"
        return value.decode("utf-8", errors="replace"), True
    except OSError:
        return "[unsafe diagnostic omitted]", False
    finally:
        os.close(descriptor)


def _log_entry(heading: str, stdout, stderr, native: Path, script_log: Path) -> tuple[str, str]:
    native_text, native_safe = _read_diagnostic(native)
    script_text, _ = _read_diagnostic(script_log)
    entry = (f"=== {heading}: native ===\n{native_text}\n"
        f"=== {heading}: script ===\n{script_text}\n"
        f"=== {heading}: stdout ===\n{_bounded_diagnostic(stdout)}\n"
        f"=== {heading}: stderr ===\n{_bounded_diagnostic(stderr)}\n")
    return entry, native_text if native_safe else ""


def _publish_log(path: Path, entries: list[str]) -> None:
    _atomic_text(path, "".join(entries))


def _is_native_loader_rejection(native_diagnostic: str) -> bool:
    return any(_NATIVE_LOADER_REJECTION.fullmatch(line) is not None
               for line in native_diagnostic.splitlines())


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
    extension = macho.get("extensions", {}).get("macho", {})
    section_metadata = list(extension.get("sections", ()))
    ordinals = [item.get("ordinal") for item in section_metadata]
    if (any(not isinstance(value, int) or isinstance(value, bool) or value < 1
            for value in ordinals) or len(set(ordinals)) != len(ordinals)):
        raise GhidraAdapterError("fallback sections have missing or duplicate ordinals")
    identity_fields = ("name", "address", "offset", "size")
    core_by_identity = {}
    for section in macho["sections"]:
        key = tuple(section[field] for field in identity_fields)
        core_by_identity.setdefault(key, []).append(section)
    configured_regions = profile.document.get("regions", ())
    regions = []
    selected = []
    if configured_regions:
        selected_ordinals = set()
        for source in configured_regions:
            identity_key = tuple(source[field] for field in identity_fields)
            matches = [item for item in section_metadata
                       if tuple(item[field] for field in identity_fields) == identity_key]
            if len(matches) != 1:
                raise GhidraAdapterError(
                    f"fallback section metadata is missing or ambiguous: {source['name']!r}"
                )
            if matches[0]["ordinal"] in selected_ordinals:
                raise GhidraAdapterError(
                    f"fallback section metadata is ambiguous: {source['name']!r}"
                )
            selected_ordinals.add(matches[0]["ordinal"])
            selected.append((source, matches[0]))
    else:
        for metadata in sorted(section_metadata, key=lambda item: item["ordinal"]):
            identity_key = tuple(metadata[field] for field in identity_fields)
            matches = core_by_identity.get(identity_key, [])
            if not matches:
                raise GhidraAdapterError(
                    f"fallback section lacks canonical Mach-O identity: {metadata['name']!r}"
                )
            selected.append((matches.pop(0), metadata))
        if any(matches for matches in core_by_identity.values()):
            raise GhidraAdapterError("fallback section metadata is missing for a canonical section")
    for source, metadata in selected:
        region = {key: metadata[key] for key in ("ordinal", "name", "address", "offset", "size")}
        region["permissions"] = source["permissions"]
        if "sha256" in source:
            region["sha256"] = source["sha256"]
        region.update({key: metadata[key] for key in (
            "alignment_exponent", "alignment", "flags", "type", "zero_fill", "initialized"
        )})
        regions.append(region)
    symbols = [dict(item) for item in macho["symbols"] if item["name"]]
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
        "sections": sorted(regions, key=lambda item: (
            item["address"], item["offset"], item["name"], item["size"],
            item["ordinal"], item["permissions"], item["alignment_exponent"], item["alignment"],
            item["flags"], item["type"], item["zero_fill"], item["initialized"],
        )),
        "symbols": sorted(symbols, key=lambda item: (
            item["address"], item["name"], item["binding"], item["section"] or "",
        )),
        "relocations": sorted(
            [dict(item) for item in extension.get("relocations", ())],
            key=lambda item: (
                item["address"], item["kind"], item["target"] or "", item["addend"],
                item["type"], item["section"], item["section_ordinal"], item["external"],
                -1 if item["target_section_ordinal"] is None else item["target_section_ordinal"],
                item["pc_relative"], item["width"], item["original_bytes"],
            ),
        ),
        "entry_points": sorted(entries, key=lambda item: (item["address"], item["name"])),
    }


def _validate_output(document: dict, configuration: dict, identity: InputIdentity,
                     layout: dict | None = None) -> None:
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
    if layout is not None:
        for name in ("sections", "symbols", "relocations"):
            if extension.get(f"fallback_{name}") != layout[name]:
                raise GhidraAdapterError(f"Ghidra output did not preserve fallback {name}")
        section_fields = ("name", "address", "offset", "size", "permissions")
        expected_sections = sorted(
            [{key: item[key] for key in section_fields} for item in layout["sections"]],
            key=lambda item: (item["address"], item["name"], item["offset"], item["size"],
                              item["permissions"]),
        )
        actual_sections = sorted(
            [{key: item[key] for key in section_fields} for item in document["sections"]],
            key=lambda item: (item["address"], item["name"], item["offset"], item["size"],
                              item["permissions"]),
        )
        if actual_sections != expected_sections:
            raise GhidraAdapterError("Ghidra output fallback sections do not match layout")
        if document["symbols"] != layout["symbols"]:
            raise GhidraAdapterError("Ghidra output fallback symbols do not match layout")
        expected_relocations = [
            {key: item[key] for key in ("address", "kind", "target", "addend")}
            for item in layout["relocations"]
        ]
        if document["relocations"] != expected_relocations:
            raise GhidraAdapterError("Ghidra output fallback relocations do not match layout")
        backing = extension.get("fallback_backing")
        if not isinstance(backing, list) or len(backing) != len(layout["sections"]):
            raise GhidraAdapterError("Ghidra output fallback backing metadata is missing")
        by_ordinal = {item.get("ordinal"): item for item in backing if isinstance(item, dict)}
        if len(by_ordinal) != len(backing):
            raise GhidraAdapterError("Ghidra output fallback backing ordinals are invalid")
        for section in layout["sections"]:
            actual = by_ordinal.get(section["ordinal"])
            expected_offset = section["offset"] if section["initialized"] and section["size"] else None
            if (actual is None or actual.get("initialized") != section["initialized"] or
                    actual.get("source_offset") != expected_offset):
                raise GhidraAdapterError("Ghidra output fallback backing does not match layout")
        statuses = extension.get("fallback_relocation_status")
        if not isinstance(statuses, list) or len(statuses) != len(layout["relocations"]):
            raise GhidraAdapterError("Ghidra output fallback relocation status is missing")
        for index, (expected, actual) in enumerate(zip(layout["relocations"], statuses)):
            if (actual.get("index") != index or actual.get("address") != expected["address"] or
                    actual.get("type") != expected["type"] or
                    actual.get("width") != expected["width"] or
                    actual.get("original_bytes") != expected["original_bytes"] or
                    actual.get("status") not in {
                        "APPLIED", "APPLIED_OTHER", "SKIPPED", "UNSUPPORTED", "FAILURE", "PARTIAL"
                    }):
                raise GhidraAdapterError("Ghidra output fallback relocation status is invalid")
            if actual["status"] in {"APPLIED", "APPLIED_OTHER"} and not actual.get("reference_targets"):
                raise GhidraAdapterError("applied fallback relocation has no analysis reference")
            instructions = [instruction for function in document["functions"]
                            for instruction in function["instructions"]
                            if instruction["address"] == expected["address"]]
            if instructions and any(index not in instruction["relocations"]
                                    for instruction in instructions):
                raise GhidraAdapterError("fallback instruction relocation index is missing")


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
    workspace = Path(tempfile.mkdtemp(prefix="binrecon-ghidra-work-",
                                      dir=destination.parent))
    try:
        workspace.chmod(0o700)
    except OSError:
        pass
    run_token = "".join(character for character in workspace.name if character.isalnum())[-16:]
    output = workspace / "analysis.tmp.json"
    native_log = workspace / "ghidra-native.log"
    script_log = workspace / "ghidra-script.log"
    layout_path = workspace / "layout.json"
    script = (Path(__file__).parents[2] / "adapters" / "ghidra" / "ExportAnalysis.java").resolve()
    log_entries = []
    layout_document = None
    try:
        command = _command(executable, workspace, f"native-{run_token}", identity, script, output,
                           native_log, script_log, None)
        try:
            completed = runner(command, capture_output=True, text=True, timeout=timeout,
                               shell=False, check=False)
        except subprocess.TimeoutExpired as error:
            entry, _ = _log_entry("native", error.stdout, error.stderr, native_log, script_log)
            log_entries.append(entry); _publish_log(log_path, log_entries)
            raise GhidraAdapterError(f"Ghidra timed out after {timeout} seconds") from error
        except OSError as error:
            entry, _ = _log_entry("native", "", str(error), native_log, script_log)
            log_entries.append(entry); _publish_log(log_path, log_entries)
            raise GhidraAdapterError(f"could not start Ghidra: {error}") from error
        entry, native_diagnostic = _log_entry(
            "native", completed.stdout, completed.stderr, native_log, script_log
        )
        log_entries.append(entry); _publish_log(log_path, log_entries)
        native_needs_fallback = _is_native_loader_rejection(native_diagnostic)
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
                entry, _ = _log_entry("fallback", error.stdout, error.stderr, native_log, script_log)
                log_entries.append(entry); _publish_log(log_path, log_entries)
                raise GhidraAdapterError(f"Ghidra fallback timed out after {timeout} seconds") from error
            except OSError as error:
                entry, _ = _log_entry("fallback", "", str(error), native_log, script_log)
                log_entries.append(entry); _publish_log(log_path, log_entries)
                raise GhidraAdapterError(f"could not start Ghidra fallback: {error}") from error
            entry, _ = _log_entry("fallback", completed.stdout, completed.stderr,
                                  native_log, script_log)
            log_entries.append(entry); _publish_log(log_path, log_entries)
            if completed.returncode != 0:
                raise GhidraAdapterError(f"Ghidra fallback failed with exit code {completed.returncode}")
        if not output.is_file():
            raise GhidraAdapterError("Ghidra did not produce a fresh analysis output")
        try:
            document = _read_snapshot(output)
            _validate_output(document, configuration, identity, layout_document)
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
                    log_entries.append(f"=== cleanup ===\n{_bounded_diagnostic(error)}\n")
                    _publish_log(log_path, log_entries)
                except OSError:
                    pass
