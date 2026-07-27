import ppc_package_check as ppc


def test_identical_trees_report_no_divergence(tmp_path):
    origin = tmp_path / "origin"
    package = tmp_path / "package"
    origin.mkdir()
    package.mkdir()
    (origin / "foo.h").write_text("same content")
    (package / "foo.h").write_text("same content")

    differing, missing_from_package, missing_from_origin = ppc.diff_trees(
        ppc.hash_files(origin), ppc.hash_files(package)
    )

    assert differing == []
    assert missing_from_package == []
    assert missing_from_origin == []


def test_differing_content_is_named(tmp_path):
    origin = tmp_path / "origin"
    package = tmp_path / "package"
    origin.mkdir()
    package.mkdir()
    (origin / "foo.h").write_text("original")
    (package / "foo.h").write_text("changed")

    differing, missing_from_package, missing_from_origin = ppc.diff_trees(
        ppc.hash_files(origin), ppc.hash_files(package)
    )

    assert differing == ["foo.h"]
    assert missing_from_package == []
    assert missing_from_origin == []


def test_file_missing_from_one_side_is_named_with_direction(tmp_path):
    origin = tmp_path / "origin"
    package = tmp_path / "package"
    origin.mkdir()
    package.mkdir()
    (origin / "shared.h").write_text("x")
    (package / "shared.h").write_text("x")
    (origin / "only_in_origin.h").write_text("y")
    (package / "only_in_package.h").write_text("z")

    differing, missing_from_package, missing_from_origin = ppc.diff_trees(
        ppc.hash_files(origin), ppc.hash_files(package)
    )

    assert differing == []
    assert missing_from_package == ["only_in_origin.h"]
    assert missing_from_origin == ["only_in_package.h"]
