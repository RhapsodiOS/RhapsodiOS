from dataclasses import dataclass
import hashlib
import os
from pathlib import Path
import stat


_CHUNK_SIZE = 1024 * 1024


@dataclass(frozen=True)
class InputIdentity:
    path: Path
    size: int
    sha256: str


class IdentityMismatchError(ValueError):
    """Raised when an artifact no longer has its expected identity."""


def identify(path: Path) -> InputIdentity:
    resolved = path.resolve(strict=True)
    flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NONBLOCK", 0)
    try:
        descriptor = os.open(resolved, flags)
    except PermissionError:
        if resolved.is_dir():
            raise ValueError(f"artifact is not a regular file: {resolved}") from None
        raise
    try:
        initial = os.fstat(descriptor)
        if not stat.S_ISREG(initial.st_mode):
            raise ValueError(f"artifact is not a regular file: {resolved}")

        digest = hashlib.sha256()
        size = 0
        while True:
            chunk = os.read(descriptor, _CHUNK_SIZE)
            if not chunk:
                break
            digest.update(chunk)
            size += len(chunk)

        final = os.fstat(descriptor)
        stable_fields = ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns")
        if size != final.st_size or any(
            getattr(initial, field) != getattr(final, field) for field in stable_fields
        ):
            raise IdentityMismatchError(f"file changed during hashing: {resolved}")

        return InputIdentity(resolved, size, digest.hexdigest().upper())
    finally:
        os.close(descriptor)


def assert_identity(expected: InputIdentity) -> None:
    actual = identify(expected.path)
    verify_expected(actual, expected.size, expected.sha256)


def verify_expected(
    actual: InputIdentity,
    expected_size: int | None,
    expected_sha256: str | None,
) -> None:
    if expected_size is not None and actual.size != expected_size:
        raise IdentityMismatchError(
            f"identity mismatch for {actual.path}: size expected {expected_size}, "
            f"actual {actual.size}"
        )

    if expected_sha256 is not None:
        normalized_hash = expected_sha256.upper()
        if actual.sha256 != normalized_hash:
            raise IdentityMismatchError(
                f"identity mismatch for {actual.path}: sha256 expected "
                f"{normalized_hash}, actual {actual.sha256}"
            )
