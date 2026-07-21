import hashlib
import os
from pathlib import Path
from types import SimpleNamespace

import pytest

import binrecon.identity as identity_module
from binrecon.identity import (
    IdentityMismatchError,
    assert_identity,
    identify,
    verify_expected,
)


def test_identify_hashes_in_one_mib_chunks_and_reports_size(tmp_path, monkeypatch):
    artifact = tmp_path / "artifact.bin"
    payload = b"A" * (2 * 1024 * 1024 + 17)
    artifact.write_bytes(payload)
    read_sizes = []
    original_read = os.read

    def recording_read(fd, size):
        read_sizes.append(size)
        return original_read(fd, size)

    monkeypatch.setattr(identity_module.os, "read", recording_read)

    identity = identify(artifact)

    assert identity.path == artifact.resolve()
    assert identity.size == len(payload)
    assert identity.sha256 == hashlib.sha256(payload).hexdigest().upper()
    assert read_sizes == [1024 * 1024] * 4


def test_identify_rejects_nonregular_opened_descriptor_and_closes_it(
    tmp_path, monkeypatch
):
    artifact = tmp_path / "artifact.bin"
    artifact.write_bytes(b"regular pathname")
    read_fd, write_fd = os.pipe()
    monkeypatch.setattr(identity_module.os, "open", lambda *_args: read_fd)

    try:
        with pytest.raises(ValueError, match="regular file"):
            identify(artifact)
        with pytest.raises(OSError):
            os.fstat(read_fd)
    finally:
        for fd in (read_fd, write_fd):
            try:
                os.close(fd)
            except OSError:
                pass


@pytest.mark.skipif(not hasattr(os, "mkfifo"), reason="FIFO creation is unavailable")
def test_identify_rejects_fifo_without_blocking(tmp_path):
    fifo = tmp_path / "artifact.fifo"
    os.mkfifo(fifo)

    with pytest.raises(ValueError, match="regular file"):
        identify(fifo)


@pytest.mark.parametrize(
    "field", ["st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns"]
)
def test_identify_detects_descriptor_metadata_change_during_hashing(
    tmp_path, monkeypatch, field
):
    artifact = tmp_path / "artifact.bin"
    artifact.write_bytes(b"snapshot")
    original_fstat = os.fstat
    calls = 0

    def changing_fstat(fd):
        nonlocal calls
        calls += 1
        snapshot = original_fstat(fd)
        if calls == 1:
            return snapshot
        values = {
            name: getattr(snapshot, name)
            for name in (
                "st_mode",
                "st_dev",
                "st_ino",
                "st_size",
                "st_mtime_ns",
                "st_ctime_ns",
            )
        }
        values[field] += 1
        return SimpleNamespace(**values)

    monkeypatch.setattr(identity_module.os, "fstat", changing_fstat)

    with pytest.raises(IdentityMismatchError, match="changed during hashing"):
        identify(artifact)


def test_identify_detects_content_mutation_during_hashing(tmp_path, monkeypatch):
    artifact = tmp_path / "artifact.bin"
    artifact.write_bytes(b"A" * 32)
    original_read = os.read
    original_mtime = artifact.stat().st_mtime_ns
    mutated = False

    def mutating_read(fd, size):
        nonlocal mutated
        chunk = original_read(fd, size)
        if chunk and not mutated:
            mutated = True
            artifact.write_bytes(b"B" * 32)
            os.utime(
                artifact,
                ns=(artifact.stat().st_atime_ns, original_mtime + 1_000_000_000),
            )
        return chunk

    monkeypatch.setattr(identity_module.os, "read", mutating_read)

    with pytest.raises(IdentityMismatchError, match="changed during hashing"):
        identify(artifact)


def test_identify_rejects_nonexistent_path(tmp_path):
    with pytest.raises(FileNotFoundError):
        identify(tmp_path / "missing.bin")


def test_identify_rejects_directory(tmp_path):
    with pytest.raises(ValueError, match="regular file"):
        identify(tmp_path)


def test_identify_does_not_mask_permission_error_for_regular_path(
    tmp_path, monkeypatch
):
    artifact = tmp_path / "artifact.bin"
    artifact.write_bytes(b"artifact")

    def denied(*_args):
        raise PermissionError("access denied")

    monkeypatch.setattr(identity_module.os, "open", denied)

    with pytest.raises(PermissionError, match="access denied"):
        identify(artifact)


def test_verify_expected_accepts_exact_size_and_case_insensitive_hash(tmp_path):
    artifact = tmp_path / "artifact.bin"
    artifact.write_bytes(b"binary")
    actual = identify(artifact)

    verify_expected(actual, actual.size, actual.sha256.lower())


@pytest.mark.parametrize("field", ["size", "sha256"])
def test_verify_expected_reports_path_and_expected_and_actual(tmp_path, field):
    artifact = tmp_path / "artifact.bin"
    artifact.write_bytes(b"binary")
    actual = identify(artifact)
    expected_size = actual.size + 1 if field == "size" else actual.size
    expected_hash = "0" * 64 if field == "sha256" else actual.sha256

    with pytest.raises(IdentityMismatchError) as captured:
        verify_expected(actual, expected_size, expected_hash)

    message = str(captured.value)
    assert str(actual.path) in message
    assert "expected" in message
    assert "actual" in message


def test_assert_identity_detects_content_change_after_capture(tmp_path):
    artifact = tmp_path / "artifact.bin"
    artifact.write_bytes(b"before")
    captured = identify(artifact)
    artifact.write_bytes(b"after!")

    with pytest.raises(IdentityMismatchError, match="expected.*actual"):
        assert_identity(captured)
