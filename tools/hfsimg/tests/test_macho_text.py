import struct

import macho_text


def macho(text=b"\x38\x60\x00\x01\x4e\x80\x00\x20", data=b"\x00\x00\x00\x07",
          reloc=b"\x00\x00\x00\x04\x00\x00\x00\x01"):
    """A minimal big-endian MH_OBJECT: one LC_SEGMENT holding __TEXT,__text
    (with one relocation) and __DATA,__data."""
    ncmds, cmdsize = 1, 56 + 2 * 68
    text_off = 28 + cmdsize
    data_off = text_off + len(text)
    reloff = data_off + len(data)
    hdr = struct.pack(">7I", 0xfeedface, 18, 0, 1, ncmds, cmdsize, 0)
    seg = struct.pack(">II16s8I", 1, cmdsize, b"", 0, len(text) + len(data),
                      text_off, len(text) + len(data), 7, 7, 2, 0)
    s1 = struct.pack(">16s16s9I", b"__text", b"__TEXT", 0, len(text), text_off,
                     2, reloff, 1, 0x80000400, 0, 0)
    s2 = struct.pack(">16s16s9I", b"__data", b"__DATA", len(text), len(data),
                     data_off, 2, 0, 0, 0, 0, 0)
    return hdr + seg + s1 + s2 + text + data + reloc


def write(tmp_path, name, blob):
    p = tmp_path / name
    p.write_bytes(blob)
    return str(p)


def test_reads_only_text_sections(tmp_path):
    secs = macho_text.text_sections(write(tmp_path, "a.o", macho()))
    assert list(secs) == ["__text"]
    assert secs["__text"][0] == b"\x38\x60\x00\x01\x4e\x80\x00\x20"


def test_identical_and_data_only_changes_pass(tmp_path):
    a = write(tmp_path, "a.o", macho())
    b = write(tmp_path, "b.o", macho(data=b"\x00\x00\x00\x08"))
    assert macho_text.compare(a, b) == []


def test_code_and_relocation_changes_fail(tmp_path):
    a = write(tmp_path, "a.o", macho())
    b = write(tmp_path, "b.o", macho(text=b"\x38\x60\x00\x02\x4e\x80\x00\x20"))
    c = write(tmp_path, "c.o", macho(reloc=b"\x00\x00\x00\x00\x00\x00\x00\x01"))
    assert macho_text.compare(a, b) == ["section __text bytes differ"]
    assert macho_text.compare(a, c) == ["section __text relocations differ"]


def test_directories(tmp_path):
    before, after = tmp_path / "before", tmp_path / "after"
    before.mkdir()
    after.mkdir()
    (before / "x.o").write_bytes(macho())
    (after / "x.o").write_bytes(macho())
    (after / "hfs_endian.o").write_bytes(macho())
    assert macho_text.compare_dirs(str(before), str(after), ["hfs_endian.o"]) == []
    assert macho_text.compare_dirs(str(before), str(after)) == \
        ["hfs_endian.o: new object not expected"]
