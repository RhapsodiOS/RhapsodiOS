"""Closed parity-ledger contract and race-resistant publication."""

from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tempfile
import threading
import time

from binrecon.identity import InputIdentity, assert_identity
from binrecon.normalize import canonical_key, preflight_json
from binrecon.schema import validate_document


class LedgerError(ValueError):
    pass


@dataclass(frozen=True)
class LedgerSnapshot:
    path: Path
    sha256: str
    size: int
    device: int
    inode: int


class LedgerLock:
    """Advisory cross-process lock for a ledger or output-directory owner path."""

    def __init__(self, owner: Path, *, timeout=10.0, lock_path: Path | None = None,
                 release_errors_nonfatal=False):
        if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or timeout < 0:
            raise LedgerError("lock timeout must be nonnegative")
        owner = Path(owner)
        raw = Path(lock_path) if lock_path is not None else owner.with_name(owner.name + ".lock")
        _mkdir_durable(raw.parent)
        self.path = raw.parent.resolve(strict=True) / raw.name
        self.timeout = float(timeout); self.descriptor = None
        self.release_errors_nonfatal = bool(release_errors_nonfatal)

    def __enter__(self):
        if self.path.is_symlink(): raise LedgerError("lock file is a symlink")
        flags = (os.O_RDWR | os.O_CREAT | getattr(os, "O_BINARY", 0) |
                 getattr(os, "O_NOFOLLOW", 0))
        descriptor = os.open(self.path, flags, 0o600)
        try:
            info = os.fstat(descriptor)
            reparse = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
            if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or
                    getattr(info, "st_file_attributes", 0) & reparse):
                raise LedgerError("lock file is not a private regular file")
            leaf = self.path.lstat()
            if (leaf.st_dev, leaf.st_ino) != (info.st_dev, info.st_ino):
                raise LedgerError("lock file changed while opening")
            if info.st_size == 0:
                os.write(descriptor, b"\0"); os.fsync(descriptor)
            deadline = time.monotonic() + self.timeout
            while True:
                try:
                    _try_lock(descriptor); break
                except (BlockingIOError, OSError) as error:
                    if not _lock_busy(error): raise
                    if time.monotonic() >= deadline:
                        raise LedgerError(f"timed out acquiring lock {self.path}") from error
                    time.sleep(min(0.05, max(0.001, deadline - time.monotonic())))
            self.descriptor = descriptor
            return self
        except BaseException:
            os.close(descriptor); raise

    def __exit__(self, exc_type, exc, traceback):
        descriptor = self.descriptor; self.descriptor = None
        release_error = None
        try: _unlock(descriptor)
        except OSError as error: release_error = error
        try: os.close(descriptor)
        except OSError as error:
            if release_error is None: release_error = error
            else: release_error.add_note(f"lock close also failed: {error}")
        if release_error is not None:
            if exc is not None:
                exc.add_note(f"lock release failed: {release_error}")
                return False
            if self.release_errors_nonfatal: return False
            raise LedgerError(f"lock release failed: {release_error}") from release_error
        return False


_ORDER = ("unexamined", "signature-confirmed", "control-flow-confirmed", "assembly-matched")
_HASH = re.compile(r"^[0-9A-F]{64}$")
_MAX_LEDGER = 16 * 1024 * 1024
_MAX_ENTRIES = 100_000
_MAX_ARTIFACTS = 1_000
_PENDING_DIRECTORY_BARRIERS = set()
_PENDING_DIRECTORY_LOCK = threading.Lock()


def new_ledger(reference: InputIdentity, rebuilt: InputIdentity | None, entries=()) -> dict:
    document = {"schema_version": "ledger-v1", "reference_sha256": reference.sha256,
                "rebuilt_sha256": None if rebuilt is None else rebuilt.sha256,
                "entries": deepcopy(list(entries))}
    validate_ledger(document, reference, rebuilt)
    return _canonical(document)


def update_ledger(path, reference, rebuilt, updater, *, timeout=10.0, protected=(),
                  create=True):
    """Serialize load-update-replace so no writer can act on a stale ledger snapshot."""
    path = Path(path)
    with LedgerLock(path, timeout=timeout):
        try: document, snapshot = load_ledger(path, reference, rebuilt)
        except FileNotFoundError:
            if not create: raise
            document, snapshot = new_ledger(reference, rebuilt), None
        updated = updater(deepcopy(document))
        if not isinstance(updated, dict): raise LedgerError("ledger updater must return a ledger document")
        write_ledger(path, updated, reference, rebuilt, expected_snapshot=snapshot,
                     protected=protected)
        return updated


def validate_ledger(document: dict, reference: InputIdentity | None = None,
                    rebuilt: InputIdentity | None = None) -> None:
    try:
        preflight_json(document, LedgerError)
        validate_document("ledger-v1", document)
    except Exception as error:
        if isinstance(error, LedgerError): raise
        raise LedgerError(f"invalid ledger schema: {error}") from error
    if len(document["entries"]) > _MAX_ENTRIES: raise LedgerError("ledger entry limit exceeded")
    if document["reference_sha256"] != document["reference_sha256"].upper():
        raise LedgerError("reference identity hash is not canonical")
    rebuilt_hash = document["rebuilt_sha256"]
    if rebuilt_hash is not None and rebuilt_hash != rebuilt_hash.upper():
        raise LedgerError("rebuilt identity hash is not canonical")
    if reference is not None and document["reference_sha256"] != reference.sha256:
        raise LedgerError("ledger reference identity differs from current artifact")
    if rebuilt is None:
        if rebuilt_hash is not None:
            raise LedgerError("ledger rebuilt identity exists but current rebuilt is missing")
    elif rebuilt_hash != rebuilt.sha256:
        raise LedgerError("ledger rebuilt identity differs from current artifact")
    previous_end = None
    keys = []
    for index, entry in enumerate(document["entries"]):
        _validate_entry(entry, index)
        key = (entry["address"], entry["size"]); keys.append(key)
        if previous_end is not None and entry["address"] < previous_end:
            raise LedgerError("ledger ranges overlap")
        previous_end = max(entry["address"] + entry["size"], entry["address"] + 1)
    if keys != sorted(keys): raise LedgerError("ledger entries are not naturally sorted")


def _validate_entry(entry, index):
    where = f"entry {index}"
    for field in ("address", "size"):
        if type(entry[field]) is not int or entry[field] < 0: raise LedgerError(f"{where} {field} is invalid")
    if entry["size"] == 0: raise LedgerError(f"{where} size must be positive")
    names = entry["names"]
    if (not isinstance(names, list) or len(names) > 1024 or
            any(not isinstance(name, str) or not name.strip() or name != name.strip() or len(name) > 1024 for name in names) or
            names != sorted(set(names), key=canonical_key)):
        raise LedgerError(f"{where} names are not canonical")
    path, line = entry["source_path"], entry["source_line"]
    if (path is None) != (line is None): raise LedgerError(f"{where} source path and line must be supplied together")
    if path is not None:
        _relative_path(path, f"{where} source_path")
        if type(line) is not int or line < 1: raise LedgerError(f"{where} source_line is invalid")
    reason, reviewer, status_value = entry["reason"], entry["reviewer"], entry["status"]
    if status_value == "intentional-mismatch":
        if not _trimmed(reason) or not _trimmed(reviewer):
            raise LedgerError("intentional-mismatch requires nonempty reason and reviewer")
    elif reason is not None:
        raise LedgerError(f"{where} reason is reserved for intentional-mismatch")
    if reviewer is not None and not _trimmed(reviewer): raise LedgerError(f"{where} reviewer is invalid")
    agreement = entry["analyzer_agreement"]
    basic_fields = {"status", "analyzers", "reasons"}
    detailed_fields = basic_fields | {"kind", "claims"}
    generated_fields = basic_fields | {"generated"}
    detailed_generated_fields = detailed_fields | {"generated"}
    no_evidence_fields = basic_fields | {"kind"}
    if (not isinstance(agreement, dict) or set(agreement) not in
            (basic_fields, detailed_fields, generated_fields,
             detailed_generated_fields, no_evidence_fields)):
        raise LedgerError(f"{where} analyzer_agreement has invalid fields")
    if agreement["status"] not in ("agreed", "partial", "disputed", "none"):
        raise LedgerError(f"{where} analyzer agreement status is invalid")
    for field in ("analyzers", "reasons"):
        values = agreement[field]
        if (not isinstance(values, list) or len(values) > 64 or
                any(not _trimmed(value) for value in values) or
                values != sorted(set(values), key=canonical_key)):
            raise LedgerError(f"{where} analyzer agreement {field} is invalid")
    if set(agreement) in (generated_fields, detailed_generated_fields) and agreement["generated"] is not True:
        raise LedgerError(f"{where} generated analyzer agreement is invalid")
    if set(agreement) == no_evidence_fields:
        if (agreement["kind"] != "no-current-evidence" or agreement["status"] != "none" or
                agreement["analyzers"] or agreement["reasons"] != ["no current evidence"]):
            raise LedgerError(f"{where} no-current-evidence agreement is invalid")
    if set(agreement) in (detailed_fields, detailed_generated_fields):
        if agreement["kind"] not in ("disputed-cluster", "function-overlap"):
            raise LedgerError(f"{where} analyzer agreement kind is invalid")
        claims = agreement["claims"]
        if not isinstance(claims, list) or not claims or len(claims) > 1024:
            raise LedgerError(f"{where} analyzer agreement claims are invalid")
        claim_keys = []
        for claim in claims:
            if not isinstance(claim, dict) or set(claim) != {"analyzer", "start", "end", "aliases", "kind"}:
                raise LedgerError(f"{where} analyzer agreement claim fields are invalid")
            if (not _trimmed(claim["analyzer"]) or claim["kind"] not in ("code", "data") or
                    type(claim["start"]) is not int or type(claim["end"]) is not int or
                    claim["start"] < 0 or claim["start"] > claim["end"]):
                raise LedgerError(f"{where} analyzer agreement claim is invalid")
            aliases = claim["aliases"]
            if (not isinstance(aliases, list) or len(aliases) > 1024 or
                    any(not _trimmed(alias) for alias in aliases) or
                    aliases != sorted(set(aliases), key=canonical_key)):
                raise LedgerError(f"{where} analyzer agreement claim aliases are invalid")
            claim_keys.append(canonical_key(claim))
        if claim_keys != sorted(set(claim_keys)):
            raise LedgerError(f"{where} analyzer agreement claims are not canonical")
        if agreement["status"] != "disputed":
            raise LedgerError(f"{where} detailed analyzer agreement must be disputed")
    if not names and agreement.get("kind") != "disputed-cluster":
        raise LedgerError(f"{where} names may be empty only for a disputed cluster")
    artifacts = entry["artifacts"]
    if not isinstance(artifacts, list) or len(artifacts) > _MAX_ARTIFACTS:
        raise LedgerError(f"{where} artifacts are invalid")
    artifact_keys = []
    for artifact in artifacts:
        if not isinstance(artifact, dict) or set(artifact) != {"kind", "path", "sha256"}:
            raise LedgerError(f"{where} artifact fields are invalid")
        if not _trimmed(artifact["kind"]): raise LedgerError(f"{where} artifact kind is invalid")
        _relative_path(artifact["path"], f"{where} artifact path")
        if not isinstance(artifact["sha256"], str) or not _HASH.fullmatch(artifact["sha256"]):
            raise LedgerError(f"{where} artifact hash is invalid")
        artifact_keys.append(canonical_key(artifact))
    if artifact_keys != sorted(set(artifact_keys)):
        raise LedgerError(f"{where} artifacts are not canonical")


def transition(document, address, status_value, reference, rebuilt, *, reason=None,
               reviewer=None, source_path=None, source_line=None):
    validate_ledger(document, reference, rebuilt)
    if type(address) is not int or address < 0: raise LedgerError("address is invalid")
    result = deepcopy(document)
    matches = [item for item in result["entries"] if item["address"] == address]
    if len(matches) != 1: raise LedgerError("ledger address does not identify exactly one entry")
    item = matches[0]; old = item["status"]
    if old == "intentional-mismatch":
        if status_value != old or reason != item["reason"] or reviewer != item["reviewer"]:
            raise LedgerError("intentional-mismatch is terminal")
    elif status_value == "intentional-mismatch":
        if old == "unexamined" or not _trimmed(reason) or not _trimmed(reviewer):
            raise LedgerError("intentional-mismatch requires a reviewed state, reason and reviewer")
        item.update(status=status_value, reason=reason.strip(), reviewer=reviewer.strip())
    elif status_value not in _ORDER:
        raise LedgerError("unknown transition status")
    else:
        old_index, new_index = _ORDER.index(old), _ORDER.index(status_value)
        if new_index < old_index: raise LedgerError("backward ledger transition is forbidden")
        if new_index > old_index + 1: raise LedgerError("skipping ledger states is forbidden")
        item["status"] = status_value
        if reviewer is not None: item["reviewer"] = reviewer.strip() if _trimmed(reviewer) else reviewer
    if source_path is not None or source_line is not None:
        item.update(source_path=source_path, source_line=source_line)
    validate_ledger(result, reference, rebuilt)
    return _canonical(result)


def merge_evidence(document, reference, rebuilt, consensus, artifacts, *, section_bases):
    validate_ledger(document, reference, rebuilt)
    if not isinstance(consensus, dict) or consensus.get("input", {}).get("sha256", "").upper() != reference.sha256:
        raise LedgerError("consensus reference identity mismatch")
    result = deepcopy(document); by_range = {(e["address"], e["size"]): e for e in result["entries"]}
    touched = set()
    for group in consensus.get("groups", []):
        section = group.get("section", {}); key = (section.get("name"), section.get("occurrence", 0))
        if key not in section_bases: continue
        address = section_bases[key] + group["start"]; size = group["end"] - group["start"]
        if size <= 0: continue
        overlaps = [entry for entry in result["entries"] if address < entry["address"] + entry["size"] and entry["address"] < address + size]
        if group.get("status") == "disputed":
            claims = sorted(({"analyzer": claim["analyzer"],
                              "start": claim["range"]["start"],
                              "end": claim["range"]["end"],
                              "aliases": sorted(set(claim.get("aliases", [])), key=canonical_key),
                              "kind": claim["kind"]} for claim in group["claims"]),
                            key=canonical_key)
            analyzers = sorted({claim["analyzer"] for claim in claims}, key=canonical_key)
            reasons = sorted(set(group["reasons"]), key=canonical_key)
            if overlaps:
                for target in overlaps:
                    cluster = (target["address"] == address and target["size"] == size and
                               target["analyzer_agreement"].get("kind") == "disputed-cluster")
                    was_generated = target["analyzer_agreement"].get("generated") is True
                    target["analyzer_agreement"] = {
                        "status": "disputed", "analyzers": analyzers,
                        "reasons": reasons, "kind": "disputed-cluster" if cluster else "function-overlap",
                        "claims": claims,
                    }
                    if was_generated: target["analyzer_agreement"]["generated"] = True
                    target["artifacts"] = sorted(deepcopy(artifacts), key=canonical_key)
                    touched.add(id(target))
            else:
                target = {"address": address, "size": size, "names": [],
                          "source_path": None, "source_line": None, "status": "unexamined",
                          "analyzer_agreement": {"status": "disputed", "analyzers": analyzers,
                              "reasons": reasons, "kind": "disputed-cluster", "claims": claims},
                          "artifacts": sorted(deepcopy(artifacts), key=canonical_key),
                          "reason": None, "reviewer": None}
                result["entries"].append(target); by_range[(address, size)] = target
                touched.add(id(target))
            continue
        if overlaps and all(item["analyzer_agreement"].get("kind") == "disputed-cluster" and
                            item["status"] == "unexamined" and item["source_path"] is None and
                            item["reason"] is None and item["reviewer"] is None
                            for item in overlaps):
            for cluster in overlaps:
                result["entries"].remove(cluster)
                by_range.pop((cluster["address"], cluster["size"]), None)
            overlaps = []
        if overlaps and (address, size) not in by_range: raise LedgerError("evidence range conflicts with ledger range")
        analyzers = sorted({claim["analyzer"] for claim in group["claims"]}, key=canonical_key)
        agreement = {"status": group["status"], "analyzers": analyzers,
                     "reasons": sorted(set(group["reasons"]), key=canonical_key)}
        names = sorted(set(group.get("aliases", [])) or {f"sub_{address:X}"}, key=canonical_key)
        target = by_range.get((address, size))
        if target is None:
            target = {"address": address, "size": size, "names": names,
                      "source_path": None, "source_line": None, "status": "unexamined",
                      "analyzer_agreement": {**agreement, "generated": True},
                      "artifacts": [], "reason": None, "reviewer": None}
            result["entries"].append(target); by_range[(address, size)] = target
        else:
            target["names"] = sorted(set(target["names"]) | set(names), key=canonical_key)
            target["analyzer_agreement"] = ({**agreement, "generated": True}
                if target["analyzer_agreement"].get("generated") is True else agreement)
        target["artifacts"] = sorted(deepcopy(artifacts), key=canonical_key)
        touched.add(id(target))
    reconciled = []
    for target in result["entries"]:
        if id(target) in touched:
            reconciled.append(target); continue
        auto_generated = (target["analyzer_agreement"].get("generated") is True or
                          target["analyzer_agreement"].get("kind") == "disputed-cluster")
        unreviewed = (target["status"] == "unexamined" and target["source_path"] is None and
                      target["reason"] is None and target["reviewer"] is None)
        if auto_generated and unreviewed: continue
        target["analyzer_agreement"] = {"status": "none", "analyzers": [],
            "reasons": ["no current evidence"], "kind": "no-current-evidence"}
        target["artifacts"] = []
        reconciled.append(target)
    result["entries"] = reconciled
    result["entries"].sort(key=lambda value: (value["address"], value["size"]))
    validate_ledger(result, reference, rebuilt)
    return _canonical(result)


def load_ledger(path: Path, reference: InputIdentity, rebuilt: InputIdentity | None):
    raw, snapshot = _read_snapshot(Path(path))
    try:
        document = json.loads(raw.decode("utf-8"), parse_constant=lambda token: (_ for _ in ()).throw(LedgerError(f"non-finite JSON {token}")))
    except (UnicodeDecodeError, json.JSONDecodeError, RecursionError) as error:
        raise LedgerError(f"ledger is malformed JSON: {error}") from error
    validate_ledger(document, reference, rebuilt)
    return _canonical(document), snapshot


def write_ledger(path: Path, document: dict, reference: InputIdentity,
                 rebuilt: InputIdentity | None, *, expected_snapshot: LedgerSnapshot | None = None,
                 protected=()) -> LedgerSnapshot:
    validate_ledger(document, reference, rebuilt); assert_identity(reference)
    if rebuilt is not None: assert_identity(rebuilt)
    raw_path = Path(path); _mkdir_durable(raw_path.parent)
    path = raw_path.parent.resolve(strict=True) / raw_path.name
    protected_paths = [reference.path] + ([] if rebuilt is None else [rebuilt.path]) + list(protected)
    initial_state = _destination_state(path, protected_paths)
    text = json.dumps(_canonical(document), sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n"
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".write", dir=path.parent)
    owned = descriptor
    try:
        stream = os.fdopen(descriptor, "w", encoding="utf-8", newline="\n"); owned = None
        with stream: stream.write(text); stream.flush(); os.fsync(stream.fileno())
        if expected_snapshot is not None:
            try: _, actual = _read_snapshot(path)
            except FileNotFoundError as error: raise LedgerError("ledger changed before publication") from error
            if actual != expected_snapshot: raise LedgerError("ledger changed before publication")
        elif path.exists() or path.is_symlink():
            _read_snapshot(path)
        assert_identity(reference)
        if rebuilt is not None: assert_identity(rebuilt)
        if _destination_state(path, protected_paths) != initial_state:
            raise LedgerError("ledger destination changed before publication")
        os.replace(temporary, path)
        _fsync_directory(path.parent)
        return _read_snapshot(path)[1]
    except BaseException:
        if owned is not None: os.close(owned)
        try: os.unlink(temporary)
        except FileNotFoundError: pass
        raise


def _read_snapshot(path):
    if path.is_symlink(): raise LedgerError("ledger path is a symlink")
    flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags)
    try:
        first = os.fstat(descriptor)
        if not stat.S_ISREG(first.st_mode) or first.st_nlink != 1: raise LedgerError("ledger is not a private regular file")
        if first.st_size > _MAX_LEDGER: raise LedgerError("ledger exceeds size limit")
        chunks=[]; total=0
        while total <= _MAX_LEDGER:
            chunk=os.read(descriptor, min(1024*1024, _MAX_LEDGER+1-total))
            if not chunk: break
            chunks.append(chunk); total += len(chunk)
        second=os.fstat(descriptor)
        fields=("st_dev","st_ino","st_size","st_mtime_ns","st_ctime_ns","st_nlink")
        if total > _MAX_LEDGER or total != first.st_size or any(getattr(first,k)!=getattr(second,k) for k in fields):
            raise LedgerError("ledger changed while reading")
        raw=b"".join(chunks)
        return raw, LedgerSnapshot(path.resolve(), hashlib.sha256(raw).hexdigest().upper(), total, first.st_dev, first.st_ino)
    finally: os.close(descriptor)


def _destination_state(path, inputs):
    if path.is_symlink(): raise LedgerError("output is a symlink")
    try: info = path.lstat()
    except FileNotFoundError: info = None
    if info is not None:
        reparse = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
        if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or
                getattr(info, "st_file_attributes", 0) & reparse):
            raise LedgerError("output is not a private regular file")
    for source in inputs:
        if path.resolve(strict=False) == Path(source).resolve(strict=False): raise LedgerError("output aliases protected input")
        if path.exists() and Path(source).exists() and os.path.samefile(path, source): raise LedgerError("output aliases protected input")
    if info is None: return None
    return tuple(getattr(info, field) for field in
                 ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns", "st_nlink"))


def _relative_path(value, where):
    if not isinstance(value, str) or not value or "\\" in value or value != value.strip(): raise LedgerError(f"{where} is invalid")
    candidate=PurePosixPath(value)
    if candidate.is_absolute() or any(part in ("", ".", "..") for part in candidate.parts): raise LedgerError(f"{where} is unsafe")


def _trimmed(value): return isinstance(value, str) and bool(value.strip()) and value == value.strip() and len(value) <= 4096


def _canonical(document):
    return json.loads(json.dumps(document, sort_keys=True, separators=(",", ":"), allow_nan=False))


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


def _mkdir_durable(path):
    """Create each missing directory and immediately persist its parent entry."""
    path = Path(path)
    absolute_path = path.absolute()
    with _PENDING_DIRECTORY_LOCK:
        pending = sorted((directory for directory in _PENDING_DIRECTORY_BARRIERS
                          if absolute_path == directory or absolute_path.is_relative_to(directory)),
                         key=lambda value: len(value.parts))
    for directory in pending:
        _confirm_directory_entry(directory)
    missing = []
    current = path
    while not current.exists():
        missing.append(current)
        parent = current.parent
        if parent == current: break
        current = parent
    if current.is_symlink() or not current.is_dir():
        raise LedgerError(f"directory parent is unsafe: {current}")
    for directory in reversed(missing):
        try: os.mkdir(directory)
        except FileExistsError:
            if directory.is_symlink() or not directory.is_dir():
                raise LedgerError(f"directory path is unsafe: {directory}")
        _confirm_directory_entry(directory.absolute())
    # A fresh process cannot know whether an already-visible directory was
    # created before a failed/crashed parent barrier. Conservatively replay
    # each ancestor edge before using it for a lock or publication.
    current = absolute_path
    while current.parent != current:
        if current.exists():
            if current.is_symlink() or not current.is_dir():
                raise LedgerError(f"directory path is unsafe: {current}")
            _confirm_directory_entry(current)
        current = current.parent


def _confirm_directory_entry(directory):
    directory = Path(directory).absolute()
    with _PENDING_DIRECTORY_LOCK:
        _PENDING_DIRECTORY_BARRIERS.add(directory)
    _fsync_directory(directory.parent)
    with _PENDING_DIRECTORY_LOCK:
        _PENDING_DIRECTORY_BARRIERS.discard(directory)


if os.name == "nt":
    import msvcrt

    def _try_lock(descriptor):
        os.lseek(descriptor, 0, os.SEEK_SET)
        msvcrt.locking(descriptor, msvcrt.LK_NBLCK, 1)

    def _unlock(descriptor):
        os.lseek(descriptor, 0, os.SEEK_SET)
        msvcrt.locking(descriptor, msvcrt.LK_UNLCK, 1)

    def _lock_busy(error):
        return getattr(error, "winerror", None) in (32, 33, 36) or error.errno in (13, 36)
else:
    import errno
    import fcntl

    def _try_lock(descriptor):
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def _unlock(descriptor):
        fcntl.flock(descriptor, fcntl.LOCK_UN)

    def _lock_busy(error):
        return error.errno in (errno.EACCES, errno.EAGAIN)
