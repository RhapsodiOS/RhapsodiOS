from dataclasses import dataclass
from pathlib import Path
from types import MappingProxyType
from typing import Mapping

from binrecon.identity import InputIdentity, identify, verify_expected
from binrecon.schema import load_json, validate_document


_ARTIFACT_VARIABLES = ("BINRECON_REFERENCE", "BINRECON_REBUILT")


@dataclass(frozen=True)
class ArtifactSpec:
    path: Path
    expected_size: int | None
    expected_sha256: str | None


@dataclass(frozen=True)
class Profile:
    source_path: Path
    name: str
    architecture: str
    reference: ArtifactSpec
    rebuilt: ArtifactSpec
    output_dir: Path
    document: Mapping[str, object]
    reference_identity: InputIdentity
    rebuilt_identity: InputIdentity


class ProfileError(ValueError):
    """Raised when profile path handling is unsafe or incomplete."""


def load_profile(path: Path, environ: Mapping[str, str]) -> Profile:
    source_path = path.resolve(strict=True)
    document = load_json(source_path)
    validate_document("profile-v1", document)
    base_dir = source_path.parent

    reference, reference_identity = _load_artifact(
        document["reference"], base_dir, environ
    )
    rebuilt, rebuilt_identity = _load_artifact(
        document["rebuilt"], base_dir, environ
    )
    output_dir = _resolve_from(base_dir, Path(document["output_dir"]), strict=False)

    return Profile(
        source_path=source_path,
        name=document["name"],
        architecture=document["architecture"],
        reference=reference,
        rebuilt=rebuilt,
        output_dir=output_dir,
        document=_deep_freeze(document),
        reference_identity=reference_identity,
        rebuilt_identity=rebuilt_identity,
    )


def _load_artifact(
    document: dict, base_dir: Path, environ: Mapping[str, str]
) -> tuple[ArtifactSpec, InputIdentity]:
    artifact_path = _expand_artifact_path(document["path"], environ)
    resolved = _resolve_from(base_dir, artifact_path, strict=True)
    expected_hash = document.get("expected_sha256")
    if expected_hash is not None:
        expected_hash = expected_hash.upper()
    spec = ArtifactSpec(resolved, document.get("expected_size"), expected_hash)
    identity = identify(resolved)
    verify_expected(identity, spec.expected_size, spec.expected_sha256)
    return spec, identity


def _expand_artifact_path(value: str, environ: Mapping[str, str]) -> Path:
    for variable in _ARTIFACT_VARIABLES:
        token = f"${{{variable}}}"
        if value == token or value.startswith(token + "/") or value.startswith(token + "\\"):
            try:
                root = environ[variable]
            except KeyError as error:
                raise ProfileError(f"artifact variable {variable} is not set") from error
            if not root:
                raise ProfileError(f"artifact variable {variable} is not set")
            suffix = value[len(token) :].lstrip("/\\")
            return Path(root) / suffix if suffix else Path(root)

    if "$" in value or "%" in value or "~" in value:
        raise ProfileError(f"unsupported artifact path expansion: {value}")
    return Path(value)


def _resolve_from(base_dir: Path, path: Path, *, strict: bool) -> Path:
    if not path.is_absolute():
        path = base_dir / path
    return path.resolve(strict=strict)


def _deep_freeze(value):
    if isinstance(value, dict):
        return MappingProxyType({key: _deep_freeze(item) for key, item in value.items()})
    if isinstance(value, list):
        return tuple(_deep_freeze(item) for item in value)
    return value
