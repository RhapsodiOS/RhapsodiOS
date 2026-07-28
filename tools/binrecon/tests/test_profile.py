import hashlib
import json
from pathlib import Path
from types import SimpleNamespace

import jsonschema
import pytest

from binrecon.identity import IdentityMismatchError
from binrecon.profile import ProfileError, analysis_scope, load_profile


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


@pytest.mark.parametrize(
    "suffix", ["/dir/file", "\\dir\\file", "/dir\\file"]
)
def test_load_profile_normalizes_artifact_suffix_separators(tmp_path, suffix):
    artifact_root = tmp_path / "artifact-root"
    target = artifact_root / "dir" / "file"
    target.parent.mkdir(parents=True)
    target.write_bytes(b"artifact")
    document = _profile_document(reference=f"${{BINRECON_REFERENCE}}{suffix}")

    profile = load_profile(
        _write_profile(tmp_path, document),
        {"BINRECON_REFERENCE": str(artifact_root)},
    )

    assert profile.reference.path == target.resolve()


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
    "suffix",
    [
        "/D:/outside.bin",
        "//server/share/file",
        "\\\\server\\share\\file",
        "/../outside.bin",
        "/./reference.bin",
        "/dir//file",
    ],
)
def test_load_profile_rejects_unsafe_allowlisted_suffix_components(tmp_path, suffix):
    document = _profile_document(reference=f"${{BINRECON_REFERENCE}}{suffix}")

    with pytest.raises(ProfileError, match="unsafe|escape|rooted|drive"):
        load_profile(
            _write_profile(tmp_path, document),
            {"BINRECON_REFERENCE": str(tmp_path)},
        )


def test_load_profile_rejects_symlink_escape_from_artifact_root(tmp_path):
    artifact_root = tmp_path / "artifact-root"
    artifact_root.mkdir()
    outside = tmp_path / "outside.bin"
    outside.write_bytes(b"outside")
    link = artifact_root / "link.bin"
    try:
        link.symlink_to(outside)
    except OSError as error:
        if isinstance(error, PermissionError) or getattr(error, "winerror", None) == 1314:
            pytest.skip(f"symlink privilege unavailable: {error}")
        raise
    document = _profile_document(reference="${BINRECON_REFERENCE}/link.bin")

    with pytest.raises(ProfileError, match="escapes.*root"):
        load_profile(
            _write_profile(tmp_path, document),
            {"BINRECON_REFERENCE": str(artifact_root)},
        )


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

    with pytest.raises(ProfileError, match="rebuilt.*resolve"):
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


def test_load_profile_allows_missing_rebuilt(tmp_path):
    document = _profile_document()
    del document["rebuilt"]
    profile_path = _write_profile(tmp_path, document)

    profile = load_profile(profile_path, {})

    assert profile.rebuilt is None
    assert profile.rebuilt_identity is None
    assert profile.reference.path == (tmp_path / "reference.bin").resolve()


def test_load_profile_still_loads_rebuilt_when_present(tmp_path):
    profile = load_profile(_write_profile(tmp_path), {})

    assert profile.rebuilt is not None
    assert profile.rebuilt.path == (tmp_path / "rebuilt.bin").resolve()
    assert profile.rebuilt_identity is not None


def test_analysis_scope_is_empty_when_absent():
    profile = SimpleNamespace(document={})

    assert analysis_scope(profile) == ()


def test_analysis_scope_returns_sorted_pairs():
    profile = SimpleNamespace(document={
        "analysis_scope": [{"start": 0x2000, "end": 0x3000},
                           {"start": 0x1000, "end": 0x1500}]
    })

    assert analysis_scope(profile) == ((0x1000, 0x1500), (0x2000, 0x3000))


def test_analysis_scope_rejects_an_inverted_range():
    profile = SimpleNamespace(document={
        "analysis_scope": [{"start": 0x3000, "end": 0x2000}]
    })

    with pytest.raises(ProfileError):
        analysis_scope(profile)


def test_analysis_scope_rejects_an_empty_range():
    profile = SimpleNamespace(document={
        "analysis_scope": [{"start": 0x2000, "end": 0x2000}]
    })

    with pytest.raises(ProfileError):
        analysis_scope(profile)


def test_analysis_scope_rejects_overlapping_ranges():
    profile = SimpleNamespace(document={
        "analysis_scope": [{"start": 0x1000, "end": 0x2000},
                           {"start": 0x1800, "end": 0x2400}]
    })

    with pytest.raises(ProfileError):
        analysis_scope(profile)


def test_rebuilt_scope_uses_the_rebuilt_ranges_when_declared():
    profile = SimpleNamespace(document={
        "analysis_scope": [{"start": 0x1000, "end": 0x1500}],
        "rebuilt_analysis_scope": [{"start": 0x4000, "end": 0x4200},
                                   {"start": 0x3000, "end": 0x3100}],
    })

    assert analysis_scope(profile, "rebuilt") == ((0x3000, 0x3100), (0x4000, 0x4200))


def test_rebuilt_scope_falls_back_to_the_shared_ranges():
    profile = SimpleNamespace(document={
        "analysis_scope": [{"start": 0x1000, "end": 0x1500}]
    })

    assert analysis_scope(profile, "rebuilt") == ((0x1000, 0x1500),)


def test_reference_scope_ignores_the_rebuilt_ranges():
    profile = SimpleNamespace(document={
        "analysis_scope": [{"start": 0x1000, "end": 0x1500}],
        "rebuilt_analysis_scope": [{"start": 0x4000, "end": 0x4200}],
    })

    assert analysis_scope(profile, "reference") == ((0x1000, 0x1500),)
    assert analysis_scope(profile) == ((0x1000, 0x1500),)


def test_analysis_scope_rejects_an_unknown_artifact():
    profile = SimpleNamespace(document={
        "analysis_scope": [{"start": 0x1000, "end": 0x1500}]
    })

    with pytest.raises(ProfileError):
        analysis_scope(profile, "peer")


def test_rebuilt_scope_rejects_an_inverted_range():
    profile = SimpleNamespace(document={
        "analysis_scope": [{"start": 0x1000, "end": 0x1500}],
        "rebuilt_analysis_scope": [{"start": 0x4200, "end": 0x4000}],
    })

    with pytest.raises(ProfileError):
        analysis_scope(profile, "rebuilt")


def test_rebuilt_scope_rejects_overlapping_ranges():
    profile = SimpleNamespace(document={
        "analysis_scope": [{"start": 0x1000, "end": 0x1500}],
        "rebuilt_analysis_scope": [{"start": 0x4000, "end": 0x4200},
                                   {"start": 0x4100, "end": 0x4300}],
    })

    with pytest.raises(ProfileError):
        analysis_scope(profile, "rebuilt")


PPC_PROFILES = sorted(
    (Path(__file__).parents[1] / "profiles").glob("*-ppc.json")
)


def test_ppc_profile_inventory():
    assert [path.name for path in PPC_PROFILES] == [
        "53c96-bundle-ppc.json", "53c96-ppc.json",
        "applepcibus-bundle-ppc.json", "applepcibus-ppc.json",
        "ata-bundle-ppc.json", "ata-ppc.json",
        "awacs-bundle-ppc.json", "awacs-ppc.json",
        "bmac-bundle-ppc.json", "bmac-ppc.json",
        "burgundy-bundle-ppc.json", "burgundy-ppc.json",
        "cuda-bundle-ppc.json", "cuda-ppc.json",
        "dec21040-bundle-ppc.json", "dec21040-ppc.json",
        "gem-bundle-ppc.json", "gem-ppc.json",
        "gnic-bundle-ppc.json", "gnic-ppc.json",
        "ioadbdevice-ppc.json",
        "iodisplay-bundle-ppc.json", "iodisplay-ppc.json",
        "mace-bundle-ppc.json", "mace-ppc.json",
        "mesh-bundle-ppc.json", "mesh-ppc.json",
        "ohare-bundle-ppc.json", "ohare-ppc.json",
        "pmu-bundle-ppc.json", "pmu-ppc.json",
        "ppcserialport-bundle-ppc.json", "ppcserialport-ppc.json",
        "scsiserver-bundle-ppc.json", "scsiserver-ppc.json",
        "scsitape-bundle-ppc.json", "scsitape-postload-ppc.json",
        "scsitape-ppc.json", "scsitape-preload-ppc.json",
        "stblocksize-ppc.json", "sym8xx-bundle-ppc.json",
        "sym8xx-ppc.json",
    ]


@pytest.mark.parametrize("path", PPC_PROFILES, ids=lambda path: path.name)
def test_ppc_profiles_are_reference_only_ida_runs(path):
    document = json.loads(path.read_text(encoding="utf-8"))

    assert document["schema_version"] == "profile-v1"
    assert document["architecture"] == "ppc"
    assert document["endianness"] == "big"
    assert document["reference"] == {"path": "${BINRECON_REFERENCE}"}
    assert "rebuilt" not in document
    assert document["analyzers"]["ida"]["enabled"] is True
    assert document["analyzers"]["ghidra"]["enabled"] is False
    assert document["analyzers"]["angr"]["enabled"] is False
    assert document["output_dir"] == f"../out/{path.stem}"
