import hashlib
from pathlib import Path

import pytest

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
    original_open = Path.open

    class RecordingReader:
        def __init__(self, stream):
            self._stream = stream

        def __enter__(self):
            self._stream.__enter__()
            return self

        def __exit__(self, *args):
            return self._stream.__exit__(*args)

        def read(self, size=-1):
            read_sizes.append(size)
            return self._stream.read(size)

    def recording_open(path, *args, **kwargs):
        return RecordingReader(original_open(path, *args, **kwargs))

    monkeypatch.setattr(Path, "open", recording_open)

    identity = identify(artifact)

    assert identity.path == artifact.resolve()
    assert identity.size == len(payload)
    assert identity.sha256 == hashlib.sha256(payload).hexdigest().upper()
    assert read_sizes == [1024 * 1024] * 4


def test_identify_rejects_nonexistent_path(tmp_path):
    with pytest.raises(FileNotFoundError):
        identify(tmp_path / "missing.bin")


def test_identify_rejects_directory(tmp_path):
    with pytest.raises(ValueError, match="regular file"):
        identify(tmp_path)


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
