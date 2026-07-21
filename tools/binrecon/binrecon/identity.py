from dataclasses import dataclass
import hashlib
from pathlib import Path


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
    if not resolved.is_file():
        raise ValueError(f"artifact is not a regular file: {resolved}")

    digest = hashlib.sha256()
    size = 0
    with resolved.open("rb") as stream:
        while True:
            chunk = stream.read(_CHUNK_SIZE)
            if not chunk:
                break
            digest.update(chunk)
            size += len(chunk)

    return InputIdentity(resolved, size, digest.hexdigest().upper())


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
