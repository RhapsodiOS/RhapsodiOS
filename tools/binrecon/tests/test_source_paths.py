import pytest

from source_paths import source_files


def test_a_directory_yields_its_source_files(tmp_path):
    (tmp_path / "a.m").write_text("")
    (tmp_path / "b.c").write_text("")
    (tmp_path / "notes.txt").write_text("")
    found = source_files(tmp_path, {".m", ".c"})
    assert [p.name for p in found] == ["a.m", "b.c"]


def test_a_file_yields_just_that_file(tmp_path):
    (tmp_path / "a.m").write_text("")
    (tmp_path / "b.m").write_text("")
    found = source_files(tmp_path / "a.m", {".m", ".c"})
    assert [p.name for p in found] == ["a.m"]


def test_a_file_of_the_wrong_suffix_raises(tmp_path):
    (tmp_path / "notes.txt").write_text("")
    with pytest.raises(ValueError, match="not a source file"):
        source_files(tmp_path / "notes.txt", {".m", ".c"})


def test_a_directory_with_no_source_files_raises(tmp_path):
    (tmp_path / "notes.txt").write_text("")
    with pytest.raises(ValueError, match="no source files"):
        source_files(tmp_path, {".m", ".c"})


def test_a_missing_path_raises(tmp_path):
    with pytest.raises(ValueError, match="does not exist"):
        source_files(tmp_path / "absent", {".m", ".c"})


def test_recursive_finds_a_nested_file(tmp_path):
    (tmp_path / "sub").mkdir()
    (tmp_path / "sub" / "a.m").write_text("")
    assert [p.name for p in source_files(tmp_path, {".m"})] == ["a.m"]


def test_non_recursive_skips_a_nested_file(tmp_path):
    (tmp_path / "top.m").write_text("")
    (tmp_path / "sub").mkdir()
    (tmp_path / "sub" / "nested.m").write_text("")
    found = source_files(tmp_path, {".m"}, recursive=False)
    assert [p.name for p in found] == ["top.m"]
