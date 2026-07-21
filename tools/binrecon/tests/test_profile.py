import hashlib
import json
from pathlib import Path

import jsonschema
import pytest

from binrecon.identity import IdentityMismatchError
from binrecon.profile import ProfileError, load_profile


def _profile_document(reference="reference.bin", rebuilt="rebuilt.bin"):
    return {
        "schema_version": "profile-v1",
        "name": "fixture",
        "architecture": "powerpc",
        "reference": {"path": reference},
        "rebuilt": {"path": rebuilt},
        "analyzers": {},
        "comparison": {
            "acceptance": "normalized-functions",
            "ignore_metadata": [],
            "entry_points": [],
        },
        "output_dir": "results/output",
    }


def _write_profile(tmp_path, document=None):
    (tmp_path / "reference.bin").write_bytes(b"reference")
    (tmp_path / "rebuilt.bin").write_bytes(b"rebuilt")
    profile_path = tmp_path / "profile.json"
    profile_path.write_text(json.dumps(document or _profile_document()), encoding="utf-8")
    return profile_path


def test_load_profile_validates_schema(tmp_path):
    document = _profile_document()
    del document["architecture"]
    profile_path = _write_profile(tmp_path, document)

    with pytest.raises(jsonschema.ValidationError):
        load_profile(profile_path, {})


def test_load_profile_resolves_relative_paths_and_nonexistent_output(tmp_path):
    profile = load_profile(_write_profile(tmp_path), {})

    assert profile.source_path == (tmp_path / "profile.json").resolve()
    assert profile.reference.path == (tmp_path / "reference.bin").resolve()
    assert profile.rebuilt.path == (tmp_path / "rebuilt.bin").resolve()
    assert profile.output_dir == (tmp_path / "results/output").resolve()
    assert not profile.output_dir.exists()


@pytest.mark.parametrize(
    ("key", "token", "filename"),
    [
        ("BINRECON_REFERENCE", "${BINRECON_REFERENCE}", "reference.bin"),
        ("BINRECON_REBUILT", "${BINRECON_REBUILT}", "rebuilt.bin"),
    ],
)
def test_load_profile_expands_allowlisted_artifact_tokens_with_suffix(
    tmp_path, key, token, filename
):
    artifact_root = tmp_path / "artifact-root"
    artifact_root.mkdir()
    (artifact_root / filename).write_bytes(filename.encode())
    document = _profile_document()
    document["reference" if "REFERENCE" in key else "rebuilt"]["path"] = (
        f"{token}/{filename}"
    )

    profile = load_profile(
        _write_profile(tmp_path, document), {key: str(artifact_root)}
    )

    spec = profile.reference if "REFERENCE" in key else profile.rebuilt
    assert spec.path == (artifact_root / filename).resolve()


def test_load_profile_rejects_unset_allowlisted_variable(tmp_path):
    document = _profile_document(reference="${BINRECON_REFERENCE}/reference.bin")

    with pytest.raises(ProfileError, match="BINRECON_REFERENCE.*not set"):
        load_profile(_write_profile(tmp_path, document), {})


@pytest.mark.parametrize(
    ("artifact", "variable"),
    [
        ("reference", "BINRECON_REFERENCE"),
        ("rebuilt", "BINRECON_REBUILT"),
    ],
)
@pytest.mark.parametrize(
    "suffix",
    ["$HOME/file", "%HOME%/file", "~/file", "${UNSUPPORTED}/file"],
)
def test_load_profile_rejects_nested_expansion_in_allowlisted_suffix(
    tmp_path, artifact, variable, suffix
):
    document = _profile_document()
    document[artifact]["path"] = f"${{{variable}}}/{suffix}"

    with pytest.raises(ProfileError, match="unsupported"):
        load_profile(_write_profile(tmp_path, document), {variable: str(tmp_path)})


@pytest.mark.parametrize(
    "bad_path",
    [
        "${HOME}/reference.bin",
        "prefix/${BINRECON_REFERENCE}",
        "$HOME/file",
        "%HOME%/file",
        "~/file",
        "directory~/file",
    ],
)
def test_load_profile_rejects_other_expansion_syntax(tmp_path, bad_path):
    document = _profile_document(reference=bad_path)

    with pytest.raises(ProfileError, match="unsupported"):
        load_profile(_write_profile(tmp_path, document), {"HOME": str(tmp_path)})


def test_load_profile_rejects_missing_artifact(tmp_path):
    profile_path = _write_profile(tmp_path)
    (tmp_path / "rebuilt.bin").unlink()

    with pytest.raises(FileNotFoundError):
        load_profile(profile_path, {})


def test_load_profile_captures_and_verifies_expected_identities(tmp_path):
    document = _profile_document()
    reference = b"reference"
    rebuilt = b"rebuilt"
    document["reference"].update(
        expected_size=len(reference),
        expected_sha256=hashlib.sha256(reference).hexdigest().lower(),
    )
    document["rebuilt"].update(
        expected_size=len(rebuilt),
        expected_sha256=hashlib.sha256(rebuilt).hexdigest().upper(),
    )

    profile = load_profile(_write_profile(tmp_path, document), {})

    assert profile.reference.expected_sha256 == hashlib.sha256(reference).hexdigest().upper()
    assert profile.reference_identity.size == len(reference)
    assert profile.rebuilt_identity.sha256 == hashlib.sha256(rebuilt).hexdigest().upper()


def test_load_profile_rejects_expected_identity_mismatch(tmp_path):
    document = _profile_document()
    document["reference"]["expected_size"] = 999

    with pytest.raises(IdentityMismatchError, match="expected.*999.*actual"):
        load_profile(_write_profile(tmp_path, document), {})


def test_loaded_profile_document_is_deeply_immutable(tmp_path):
    profile = load_profile(_write_profile(tmp_path), {})

    with pytest.raises(TypeError):
        profile.document["reference"]["path"] = "changed.bin"
    with pytest.raises(AttributeError):
        profile.document["comparison"]["entry_points"].append("entry")
