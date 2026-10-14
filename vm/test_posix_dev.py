"""Host-side tests for posix_dev.py; nothing here boots a guest."""

import io
import os
import tarfile

import pytest

import posix_dev


def test_tar_source_layout():
    t = tarfile.open(fileobj=io.BytesIO(posix_dev.tar_source()))
    names = t.getnames()
    assert "posix-src/README" in names
    member = "posix-src/posixtestsuite/include/posixtest.h"
    assert member in names
    with open(os.path.join(posix_dev.SRC, "posixtestsuite", "include",
                           "posixtest.h"), "rb") as f:
        assert t.extractfile(member).read() == f.read()
    # Upstream CRLF files travel untouched.
    crlf = "posix-src/posixtestsuite/conformance/interfaces/fork/testfrmw.h"
    assert b"\r\n" in t.extractfile(crlf).read()


def test_hex_to_bytes_roundtrip():
    assert posix_dev.hex_to_bytes(" 1f 8b 08\n 00 ff\n") == b"\x1f\x8b\x08\x00\xff"


def test_main_rejects_bad_usage():
    with pytest.raises(SystemExit):
        posix_dev.main(["x", "bogus"])
