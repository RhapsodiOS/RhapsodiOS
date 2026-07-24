"""Fail-closed sequential orchestration for a binrecon analysis run."""

from __future__ import annotations

from dataclasses import dataclass
from contextlib import ExitStack
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import sys
import tempfile

from binrecon.adapters.angr import export_with_angr
from binrecon.adapters.ghidra import export_with_ghidra
from binrecon.adapters.ida import export_with_ida
from binrecon.compare import compare_artifacts, validate_comparison_report
from binrecon.consensus import build_consensus, validate_consensus
from binrecon.identity import assert_identity
from binrecon.ledger import LedgerLock, merge_evidence, update_ledger
from binrecon.normalize import preflight_json
from binrecon.schema import validate_analysis_semantics, validate_document


class RunnerError(RuntimeError):
    pass


@dataclass(frozen=True)
class AnalysisSnapshot:
    document: dict
    publication: bytes
    sha256: str


_ADAPTER_ORDER = (("ida", "IDA"), ("ghidra", "Ghidra"), ("angr", "angr"))
_MAX_ANALYSIS_JSON = 16 * 1024 * 1024
# The measured EISABus consensus is 37,959,802 bytes. 64 MiB leaves 76%
# growth headroom while keeping publication verification explicitly bounded.
_MAX_CONSENSUS_JSON = 64 * 1024 * 1024


def run_analysis(profile, *, adapters=None, output_path=None, ledger_path=None,
                 lock_timeout=10.0) -> dict:
    """Serialize a run; lock order is output directory first, then ledger."""
    output_dir = Path(profile.output_dir).resolve(strict=False)
    raw_output = Path(output_path or output_dir / "run-summary.json")
    raw_ledger = None if ledger_path is None else Path(ledger_path)
    if raw_ledger is not None and _paths_alias(raw_output, raw_ledger):
        raise RunnerError("summary output aliases ledger")
    protected = [profile.source_path, profile.reference_identity.path]
    if getattr(profile, "rebuilt_identity", None) is not None:
        protected.append(profile.rebuilt_identity.path)
    if any(_paths_alias(raw_output, path) for path in protected):
        raise RunnerError("summary output aliases protected input")
    summary_lock = raw_output.parent / f".{raw_output.name}.binrecon-summary.lock"
    lock_paths = {str((output_dir / ".binrecon-run.lock").resolve(strict=False)).casefold():
                      output_dir / ".binrecon-run.lock",
                  str(summary_lock.resolve(strict=False)).casefold(): summary_lock}
    try:
        with ExitStack() as locks:
            for lock_path in (lock_paths[key] for key in sorted(lock_paths)):
                locks.enter_context(LedgerLock(lock_path, timeout=lock_timeout,
                    lock_path=lock_path, release_errors_nonfatal=True))
            return _run_analysis_locked(profile, adapters=adapters, output_path=raw_output,
                                        ledger_path=raw_ledger)
    except ValueError as error:
        if isinstance(error, RunnerError): raise
        raise RunnerError(str(error)) from error


def _run_analysis_locked(profile, *, adapters=None, output_path=None, ledger_path=None) -> dict:
    """Run enabled adapters sequentially and publish evidence only after every stage validates."""
    adapters = dict(adapters or {"ida": export_with_ida, "ghidra": export_with_ghidra,
                                "angr": export_with_angr})
    output_dir = Path(profile.output_dir).resolve(strict=False)
    raw_output = Path(output_path or output_dir / "run-summary.json")
    raw_ledger = None if ledger_path is None else Path(ledger_path)
    if raw_ledger is not None and _paths_alias(raw_output, raw_ledger):
        raise RunnerError("summary output aliases ledger")
    early_protected = [profile.source_path, profile.reference_identity.path]
    if getattr(profile, "rebuilt_identity", None) is not None:
        early_protected.append(profile.rebuilt_identity.path)
    if any(_paths_alias(raw_output, path) for path in early_protected):
        raise RunnerError("summary output aliases protected input")
    raw_output.parent.mkdir(parents=True, exist_ok=True)
    output_path = raw_output.parent.resolve(strict=True) / raw_output.name
    enabled = [(key, display) for key, display in _ADAPTER_ORDER
               if profile.document["analyzers"].get(key, {}).get("enabled", False)]
    rebuilt = getattr(profile, "rebuilt_identity", None)
    reference = profile.reference_identity
    protected_summary = [profile.source_path, reference.path]
    if rebuilt is not None: protected_summary.append(rebuilt.path)
    if raw_ledger is not None: protected_summary.append(raw_ledger)
    base_summary = {"schema_version": "run-summary-v1", "reference_sha256": reference.sha256,
                    "rebuilt_sha256": None if rebuilt is None else rebuilt.sha256,
                    "analyzers": [], "consensus": {"reference": None, "rebuilt": None},
                    "comparisons": [], "ledger": {"path": None if ledger_path is None else str(Path(ledger_path).resolve(strict=False)),
                                                   "updated": False},
                    "acceptance": {"requirement": profile.document["comparison"]["acceptance"], "passed": False},
                    "complete": False, "diagnostic": None}
    stage = None
    try:
        assert_identity(reference)
        if rebuilt is not None: assert_identity(rebuilt)
        if not enabled: raise RunnerError("no analyzers are enabled")
        output_dir.mkdir(parents=True, exist_ok=True)
        stage = Path(tempfile.mkdtemp(prefix="binrecon-run-", dir=output_dir))
        analyses = {"reference": {}, "rebuilt": {}}
        publications = {}
        artifact_names = ("reference",) if rebuilt is None else ("reference", "rebuilt")
        for key, display in enabled:
            if key not in adapters: raise RunnerError(f"required adapter {key} is unavailable")
            analyzer_record = {"name": display, "version": None, "reference": None, "rebuilt": None}
            for artifact in artifact_names:
                destination = stage / f"analysis-{artifact}-{key}.json"
                try: adapters[key](profile, artifact, destination)
                except Exception as error: raise RunnerError(f"{key} {artifact} adapter failed: {error}") from error
                snapshot = _load_analysis(destination, profile, artifact, display)
                document = snapshot.document
                analyses[artifact][key] = document
                analysis_name = f"analysis-{artifact}-{key}.json"
                publications[analysis_name] = snapshot.publication
                analyzer_record[artifact] = {"path": f"published/{analysis_name}", "sha256": snapshot.sha256}
                version = document["analyzer"]["version"]
                configured = profile.document["analyzers"][key].get("version")
                if configured is not None and version != configured:
                    raise RunnerError(f"{key} output version does not match configured version")
                if analyzer_record["version"] not in (None, version):
                    raise RunnerError(f"{key} analyzer version changed between artifacts")
                analyzer_record["version"] = version
            base_summary["analyzers"].append(analyzer_record)

        expected = [display for _, display in enabled]
        consensus_documents = {}
        for artifact in artifact_names:
            report = build_consensus([analyses[artifact][key] for key, _ in enabled],
                                     expected_analyzers=expected)
            validate_consensus(report)
            name = f"consensus-{artifact}.json"; publication = _canonical_bytes(report)
            publications[name] = publication
            consensus_documents[artifact] = report
            base_summary["consensus"][artifact] = {"path": f"published/{name}",
                "sha256": _bytes_hash(publication)}

        if rebuilt is not None:
            for key, display in enabled:
                report = compare_artifacts(reference.path, rebuilt.path,
                    analyses["reference"][key], analyses["rebuilt"][key],
                    profile.document["comparison"]["acceptance"],
                    profile.document["comparison"]["ignore_metadata"])
                validate_comparison_report(report)
                name = f"comparison-{key}.json"; publication = _canonical_bytes(report)
                publications[name] = publication
                base_summary["comparisons"].append({"analyzer": display, "path": f"published/{name}",
                    "sha256": _bytes_hash(publication), "passed": report["selected"]["passed"]})
            base_summary["acceptance"]["passed"] = all(item["passed"] for item in base_summary["comparisons"])

        assert_identity(reference)
        if rebuilt is not None: assert_identity(rebuilt)
        published = output_dir / "published"
        _publish_stage(publications, published, output_path, reference.path,
                       None if rebuilt is None else rebuilt.path,
                       extra_protected=[profile.source_path] + ([] if raw_ledger is None else [raw_ledger]))
        if ledger_path is not None:
            ledger_path = Path(ledger_path)
            section_bases = _section_bases(analyses["reference"][enabled[0][0]])
            artifacts = []
            for kind, record in (("consensus-reference", base_summary["consensus"]["reference"]),):
                artifacts.append({"kind": kind, "path": record["path"], "sha256": record["sha256"]})
            artifacts.extend({"kind": "comparison", "path": item["path"], "sha256": item["sha256"]}
                             for item in base_summary["comparisons"])
            def update_evidence(document):
                return merge_evidence(document, reference, rebuilt,
                    consensus_documents["reference"], artifacts,
                    section_bases=section_bases)
            update_ledger(ledger_path, reference, rebuilt, update_evidence,
                          protected=[output_path, profile.source_path])
            base_summary["ledger"]["updated"] = True
        if stage is not None:
            try: shutil.rmtree(stage)
            except OSError as error:
                raise RunnerError(f"run staging cleanup failed: {error}") from error
            stage = None
        base_summary["complete"] = True
        validate_run_summary(base_summary)
        _verify_published_summary(output_dir, base_summary)
        _atomic_summary(output_path, base_summary, protected_summary)
        return base_summary
    except Exception as error:
        failure = base_summary
        failure["complete"] = False; failure["acceptance"]["passed"] = False
        failure["diagnostic"] = _bounded(str(error))
        try:
            validate_run_summary(failure)
            _atomic_summary(output_path, failure, protected_summary)
        except Exception as publication_error:
            if hasattr(error, "add_note"): error.add_note(f"run summary publication failed: {publication_error}")
        if isinstance(error, RunnerError): raise
        raise RunnerError(str(error)) from error
    finally:
        if stage is not None:
            primary = sys.exc_info()[1]
            try: shutil.rmtree(stage)
            except OSError as cleanup_error:
                if primary is None: raise
                primary.add_note(f"run staging cleanup failed: {cleanup_error}")


def validate_run_summary(value):
    preflight_json(value, RunnerError)
    fields = {"schema_version", "reference_sha256", "rebuilt_sha256", "analyzers", "consensus",
              "comparisons", "ledger", "acceptance", "complete", "diagnostic"}
    if not isinstance(value, dict) or set(value) != fields or value["schema_version"] != "run-summary-v1":
        raise RunnerError("invalid run summary fields")
    _hash(value["reference_sha256"])
    if value["rebuilt_sha256"] is not None: _hash(value["rebuilt_sha256"])
    if type(value["complete"]) is not bool: raise RunnerError("invalid run completion")
    if value["diagnostic"] is not None and (not isinstance(value["diagnostic"], str) or not value["diagnostic"]):
        raise RunnerError("invalid run diagnostic")
    if value["complete"] == (value["diagnostic"] is not None): raise RunnerError("incoherent run diagnostic")
    if not isinstance(value["analyzers"], list): raise RunnerError("invalid analyzers")
    names=[]
    for item in value["analyzers"]:
        if not isinstance(item, dict) or set(item) != {"name","version","reference","rebuilt"}: raise RunnerError("invalid analyzer record")
        if not all(isinstance(item[k], str) and item[k] for k in ("name","version")): raise RunnerError("invalid analyzer identity")
        names.append(item["name"])
        _path_hash(item["reference"])
        if item["rebuilt"] is not None: _path_hash(item["rebuilt"])
    if len(names) != len(set(names)): raise RunnerError("duplicate analyzer record")
    canonical_order = [display for _, display in _ADAPTER_ORDER if display in names]
    if names != canonical_order: raise RunnerError("analyzer records are not in configured order")
    if not isinstance(value["consensus"], dict) or set(value["consensus"]) != {"reference","rebuilt"}: raise RunnerError("invalid consensus record")
    for record in value["consensus"].values():
        if record is not None: _path_hash(record)
    if not isinstance(value["comparisons"], list): raise RunnerError("invalid comparisons")
    comparison_names=[]
    for item in value["comparisons"]:
        if not isinstance(item,dict) or set(item)!={"analyzer","path","sha256","passed"}: raise RunnerError("invalid comparison record")
        if not isinstance(item["analyzer"],str) or type(item["passed"]) is not bool: raise RunnerError("invalid comparison record")
        _path_hash({"path":item["path"],"sha256":item["sha256"]}); comparison_names.append(item["analyzer"])
    if any(name not in names for name in comparison_names):
        raise RunnerError("comparison references an unknown analyzer")
    if comparison_names != names and value["rebuilt_sha256"] is not None and value["complete"]:
        raise RunnerError("comparison analyzer set is incomplete")
    ledger=value["ledger"]
    if not isinstance(ledger,dict) or set(ledger)!={"path","updated"} or type(ledger["updated"]) is not bool or (ledger["path"] is not None and not isinstance(ledger["path"],str)):
        raise RunnerError("invalid ledger record")
    if ledger["updated"] and ledger["path"] is None: raise RunnerError("updated ledger requires a path")
    if value["complete"] and ledger["path"] is not None and not ledger["updated"]:
        raise RunnerError("complete requested ledger was not updated")
    acceptance=value["acceptance"]
    if (not isinstance(acceptance,dict) or set(acceptance)!={"requirement","passed"} or
            acceptance["requirement"] not in ("exact-image","exact-sections","normalized-functions") or type(acceptance["passed"]) is not bool):
        raise RunnerError("invalid acceptance")
    expected_pass = bool(value["comparisons"]) and all(item["passed"] for item in value["comparisons"])
    if not value["complete"] and acceptance["passed"]:
        raise RunnerError("incomplete run cannot pass acceptance")
    if value["complete"] and acceptance["passed"] != expected_pass:
        raise RunnerError("non-conservative acceptance")
    if value["complete"]:
        rebuilt_present = value["rebuilt_sha256"] is not None
        if not names or any(item["reference"] is None for item in value["analyzers"]):
            raise RunnerError("complete run requires every reference analysis")
        if any((item["rebuilt"] is not None) != rebuilt_present for item in value["analyzers"]):
            raise RunnerError("rebuilt analysis presence is incoherent")
        if value["consensus"]["reference"] is None:
            raise RunnerError("complete run requires reference consensus")
        if (value["consensus"]["rebuilt"] is not None) != rebuilt_present:
            raise RunnerError("rebuilt consensus presence is incoherent")
        if rebuilt_present:
            if comparison_names != names: raise RunnerError("comparison analyzer set is incomplete")
        elif comparison_names:
            raise RunnerError("comparisons require a rebuilt artifact")


def _load_analysis(path, profile, artifact, expected_name):
    raw = _read_private_json_source(
        path, max_bytes=_MAX_ANALYSIS_JSON, label="analysis output"
    )
    try:
        document=json.loads(raw.decode("utf-8"),parse_constant=lambda t: (_ for _ in ()).throw(RunnerError(f"non-finite JSON {t}")))
    except (UnicodeDecodeError,json.JSONDecodeError,RecursionError) as error:
        raise RunnerError(f"invalid analysis JSON: {error}") from error
    if not isinstance(document,dict): raise RunnerError("analysis JSON root is not an object")
    preflight_json(document); validate_document("analysis-v1", document); validate_analysis_semantics(document)
    identity=getattr(profile, artifact + "_identity")
    source=document["input"]
    architecture = getattr(profile, "architecture", profile.document.get("architecture"))
    configured_endianness = profile.document.get("endianness")
    if configured_endianness is None:
        if str(architecture).lower() in ("i386", "x86"): configured_endianness = "little"
        elif str(architecture).lower() in ("powerpc", "ppc"): configured_endianness = "big"
        else: raise RunnerError("profile endianness must be configured for this architecture")
    if source["architecture"] != architecture:
        raise RunnerError(f"{expected_name} {artifact} output architecture disagrees with profile")
    if source["endianness"] != configured_endianness:
        raise RunnerError(f"{expected_name} {artifact} output endianness disagrees with profile")
    if (document["analyzer"]["name"] != expected_name or source["sha256"].upper()!=identity.sha256 or
            source["size"]!=identity.size or Path(source["path"]).resolve(strict=False)!=identity.path):
        raise RunnerError(f"{expected_name} {artifact} output identity is stale or invalid")
    assert_identity(identity)
    publication = _canonical_bytes(document)
    return AnalysisSnapshot(document, publication, _bytes_hash(publication))


def _read_private_json_source(path, *, max_bytes, label):
    if path.is_symlink(): raise RunnerError(f"{label} is a symlink")
    descriptor=os.open(path, os.O_RDONLY|getattr(os,"O_BINARY",0)|getattr(os,"O_NOFOLLOW",0)|getattr(os,"O_NONBLOCK",0))
    try:
        first=os.fstat(descriptor)
        reparse = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
        if (not stat.S_ISREG(first.st_mode) or first.st_nlink != 1 or
                getattr(first, "st_file_attributes", 0) & reparse or
                first.st_size > max_bytes):
            raise RunnerError(f"{label} is not a bounded private file")
        chunks=[]; total=0
        while True:
            part=os.read(descriptor, min(1024*1024,max_bytes+1-total))
            if not part: break
            chunks.append(part); total += len(part)
            if total > max_bytes: raise RunnerError(f"{label} exceeds limit")
        last=os.fstat(descriptor)
        if total!=first.st_size or any(getattr(first,k)!=getattr(last,k) for k in ("st_dev","st_ino","st_size","st_mtime_ns","st_ctime_ns")): raise RunnerError(f"{label} changed while reading")
    finally: os.close(descriptor)
    return b"".join(chunks)


def _publish_stage(publications, destination, summary_path, reference_path, rebuilt_path,
                   *, extra_protected=()):
    if destination.is_symlink(): raise RunnerError("published output directory is a symlink")
    destination_existed = destination.exists()
    destination.mkdir(parents=True, exist_ok=True)
    directory_info = destination.lstat()
    reparse = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
    if not stat.S_ISDIR(directory_info.st_mode):
        raise RunnerError("published output destination is not a directory")
    if getattr(directory_info, "st_file_attributes", 0) & reparse:
        raise RunnerError("published output directory is a reparse point")
    if not destination_existed:
        _fsync_directory(destination.parent)
    protected=[reference_path] + ([] if rebuilt_path is None else [rebuilt_path]) + [summary_path] + list(extra_protected)
    for name, content in sorted(publications.items()):
        target=destination/name
        initial_state = _destination_state(target, protected, "published output")
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{name}.", suffix=".publish", dir=destination
        )
        temporary = Path(temporary_name)
        try:
            stream = os.fdopen(descriptor, "wb"); descriptor = None
            with stream:
                stream.write(content); stream.flush(); os.fsync(stream.fileno())
            if _destination_state(target, protected, "published output") != initial_state:
                raise RunnerError("published output changed before publication")
            os.replace(temporary,target)
            _fsync_directory(destination)
        finally:
            if descriptor is not None: os.close(descriptor)
            try: temporary.unlink()
            except FileNotFoundError: pass
    _fsync_directory(destination)


def _canonical_bytes(value):
    return (json.dumps(value,sort_keys=True,separators=(",",":"),allow_nan=False)+"\n").encode("utf-8")
def _bytes_hash(value): return hashlib.sha256(value).hexdigest().upper()
def _hash(value):
    if not isinstance(value,str) or not __import__("re").fullmatch(r"[0-9A-F]{64}",value): raise RunnerError("invalid SHA-256")
def _path_hash(value):
    if not isinstance(value,dict) or set(value)!={"path","sha256"} or not isinstance(value["path"],str) or not value["path"]: raise RunnerError("invalid path/hash record")
    _safe_publication_path(value["path"])
    _hash(value["sha256"])
def _safe_publication_path(value):
    if (not isinstance(value, str) or not value or "\\" in value or
            any(ord(character) < 32 or ord(character) == 127 for character in value)):
        raise RunnerError("unsafe publication path")
    candidate = PurePosixPath(value)
    if (candidate.is_absolute() or candidate.parts[0] != "published" or
            len(candidate.parts) < 2 or any(part in ("", ".", "..") for part in candidate.parts) or
            any(":" in part or re.match(r"^[A-Za-z]:", part) for part in candidate.parts)):
        raise RunnerError("unsafe publication path")
def _bounded(value): return value.encode("utf-8",errors="replace")[:4096].decode("utf-8",errors="ignore") or "unknown error"
def _section_bases(document):
    occurrences={}; result={}
    for section in document["sections"]:
        occurrence=occurrences.get(section["name"],0); occurrences[section["name"]]=occurrence+1
        result[(section["name"],occurrence)]=section["address"]
    return result
def _atomic_summary(path,value,protected):
    path.parent.mkdir(parents=True,exist_ok=True)
    initial_state = _destination_state(path, protected, "summary output")
    descriptor,temporary=tempfile.mkstemp(prefix=f".{path.name}.",suffix=".write",dir=path.parent); owned=descriptor
    try:
        stream=os.fdopen(descriptor,"w",encoding="utf-8",newline="\n"); owned=None
        with stream: json.dump(value,stream,sort_keys=True,separators=(",",":"),allow_nan=False); stream.write("\n"); stream.flush(); os.fsync(stream.fileno())
        if _destination_state(path, protected, "summary output") != initial_state:
            raise RunnerError("summary output changed before publication")
        os.replace(temporary,path)
        _fsync_directory(path.parent)
    except BaseException:
        if owned is not None: os.close(owned)
        try: os.unlink(temporary)
        except FileNotFoundError: pass
        raise


def _destination_state(path, protected, label):
    if path.is_symlink(): raise RunnerError(f"{label} is a symlink")
    resolved = path.resolve(strict=False)
    for item in protected:
        source = Path(item)
        if resolved == source.resolve(strict=False): raise RunnerError(f"{label} aliases protected input")
        if path.exists() and source.exists() and os.path.samefile(path, source):
            raise RunnerError(f"{label} aliases protected input")
    try: info = path.lstat()
    except FileNotFoundError: info = None
    if info is not None:
        reparse = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
        if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or
                getattr(info, "st_file_attributes", 0) & reparse):
            raise RunnerError(f"{label} is not a private regular file")
    if info is None: return None
    return tuple(getattr(info, field) for field in
                 ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns", "st_nlink"))


def _paths_alias(first, second):
    first, second = Path(first), Path(second)
    if first.absolute() == second.absolute(): return True
    if first.resolve(strict=False) == second.resolve(strict=False): return True
    return first.exists() and second.exists() and os.path.samefile(first, second)


def _verify_published_summary(output_dir, summary):
    records = []
    for analyzer in summary["analyzers"]:
        records.append(("analysis", analyzer["reference"]))
        if analyzer["rebuilt"] is not None: records.append(("analysis", analyzer["rebuilt"]))
    for value in summary["consensus"].values():
        if value is not None: records.append(("consensus", value))
    records.extend(("comparison", value) for value in summary["comparisons"])
    seen = set()
    for kind, record in records:
        relative = record["path"]; _safe_publication_path(relative)
        if relative in seen: raise RunnerError("duplicate publication path in summary")
        seen.add(relative)
        path = Path(output_dir).joinpath(*PurePosixPath(relative).parts)
        max_bytes = _MAX_CONSENSUS_JSON if kind == "consensus" else _MAX_ANALYSIS_JSON
        raw = _read_private_json_source(path, max_bytes=max_bytes,
                                        label=f"{kind} output")
        if _bytes_hash(raw) != record["sha256"]:
            raise RunnerError(f"published {kind} hash disagrees with run summary")
        try:
            document = json.loads(raw.decode("utf-8"), parse_constant=lambda token:
                (_ for _ in ()).throw(RunnerError(f"non-finite JSON {token}")))
        except (UnicodeDecodeError, json.JSONDecodeError, RecursionError) as error:
            raise RunnerError(f"published {kind} is invalid JSON: {error}") from error
        if kind == "analysis":
            validate_document("analysis-v1", document); validate_analysis_semantics(document)
        elif kind == "consensus": validate_consensus(document)
        else: validate_comparison_report(document)


def _fsync_directory(path):
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    try: descriptor = os.open(path, flags)
    except OSError:
        if os.name == "nt": return
        raise
    try:
        try: os.fsync(descriptor)
        except OSError:
            if os.name != "nt": raise
    finally: os.close(descriptor)
