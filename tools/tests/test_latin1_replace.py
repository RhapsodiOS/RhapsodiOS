import os
import subprocess
import sys

import latin1_replace

TOOL = os.path.join(os.path.dirname(__file__), "..", "latin1_replace.py")


def run(path, patch, *extra):
    return subprocess.run([sys.executable, TOOL, path] + list(extra),
                          input=patch.encode("utf-8"), capture_output=True)


def test_preserves_mac_roman_bytes_and_crlf(tmp_path):
    p = tmp_path / "f.c"
    p.write_bytes(b"/* \xa5 bullet */\r\n\tfreeWord\t= *pos;\r\nend\r\n")
    r = run(str(p), "freeWord = *pos;\n=====\nfreeWord = SWAP_BE16 (*pos);\n")
    assert r.returncode == 0, r.stderr
    assert p.read_bytes() == b"/* \xa5 bullet */\r\n\tfreeWord = SWAP_BE16 (*pos);\r\nend\r\n"


def test_multi_line_new_text_takes_the_files_line_endings(tmp_path):
    p = tmp_path / "f.c"
    p.write_bytes(b"a;\r\nb;\r\n")
    r = run(str(p), "a;\n=====\nx;\ny;\n")
    assert r.returncode == 0, r.stderr
    assert p.read_bytes() == b"x;\r\ny;\r\nb;\r\n"


def test_count_mismatch_changes_nothing(tmp_path):
    p = tmp_path / "f.c"
    before = b"x = *buffer;\nx = *buffer;\n"
    p.write_bytes(before)
    r = run(str(p), "x = *buffer;\n=====\ny;\n")
    assert r.returncode == 1
    assert b"matches 2 times" in r.stderr
    assert p.read_bytes() == before
    r = run(str(p), "x = *buffer;\n=====\ny;\n", "--count", "2")
    assert r.returncode == 0
    assert p.read_bytes() == b"y;\ny;\n"


def test_whitespace_between_words_is_still_required():
    assert latin1_replace.pattern("int a").search("inta") is None
    assert latin1_replace.pattern("int a").search("int\t a")
    assert latin1_replace.pattern("f (x)").search("f(x)")


def test_patch_needs_a_separator():
    try:
        latin1_replace.split_patch("no separator here\n")
    except ValueError:
        return
    raise AssertionError("expected ValueError")
