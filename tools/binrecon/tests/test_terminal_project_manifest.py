import re
from pathlib import Path


TERMINAL_ROOT = (
    Path(__file__).resolve().parents[3]
    / "src/Applications/Administration/Terminal"
)


def _manifest_entries(text, variable, *, project_builder):
    if project_builder:
        match = re.search(rf"{variable}\s*=\s*\(([^)]*)\)", text)
        assert match is not None
        return set(match.group(1).replace(",", " ").split())

    match = re.search(rf"^{variable}\s*=\s*(.+)$", text, re.MULTILINE)
    assert match is not None
    return set(match.group(1).split())


def test_terminal_project_and_makefile_manifests_match_existing_sources():
    project = (TERMINAL_ROOT / "PB.project").read_text(encoding="utf-8")
    makefile = (TERMINAL_ROOT / "Makefile").read_text(encoding="utf-8")

    for project_variable, make_variable in (
        ("MFILES", "MFILES"),
        ("H_FILES", "HFILES"),
    ):
        project_files = _manifest_entries(
            project, project_variable, project_builder=True
        )
        make_files = _manifest_entries(
            makefile, make_variable, project_builder=False
        )

        assert project_files == make_files
        assert all((TERMINAL_ROOT / path).is_file() for path in project_files)
