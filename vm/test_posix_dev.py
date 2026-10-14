"""Host-side tests for posix_dev.py; nothing here boots a guest."""

import binascii
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


def test_uu_to_bytes_roundtrip():
    data = bytes(range(256)) * 3
    lines = [binascii.b2a_uu(data[i:i + 45]).decode("ascii")
             for i in range(0, len(data), 45)]
    text = "Warning: noise\nbegin 644 x\n" + "".join(lines) + "`\nend\n"
    assert posix_dev.uu_to_bytes(text) == data


def test_main_rejects_bad_usage():
    with pytest.raises(SystemExit):
        posix_dev.main(["x", "bogus"])
