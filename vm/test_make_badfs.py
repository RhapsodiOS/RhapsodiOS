import os, struct, tempfile
import pytest
import make_badfs, rhap_image

pytestmark = pytest.mark.skipif(not os.path.exists(make_badfs.TEMPLATE),
                                reason="install floppy template not present")

def _sb(path, off, fmt):
    # Manually compute partition offset by reading the disk label,
    # to handle images with corrupted superblocks.
    with open(path, 'rb') as f:
        for label_off in rhap_image.LABEL_OFFSETS:
            f.seek(label_off)
            if f.read(4) == rhap_image.LABEL_MAGIC:
                f.seek(label_off + 92)
                secsize = struct.unpack('>i', f.read(4))[0]
                f.seek(label_off + 112)
                front = struct.unpack('>h', f.read(2))[0]
                f.seek(label_off + 190)
                p_base = struct.unpack('>i', f.read(4))[0]
                part_start = (front + p_base) * secsize
                f.seek(part_start + rhap_image.SBOFF)
                buf = f.read(1536)
                return struct.unpack_from(fmt, buf, off)[0]
        raise ValueError("no NeXT disk label found")

def test_build_good_is_a_valid_ufs_image():
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "good.img")
        make_badfs.build_good(out)
        assert os.path.getsize(out) == 1474560
        assert _sb(out, 1372, "<i") == 0x00011954
        assert _sb(out, 209, "<b") == 1

def test_corrupt_fs_clean_clears_only_that_byte():
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "dirty.img")
        make_badfs.build_good(out)
        make_badfs.corrupt(out, "fs_clean", 0)
        assert _sb(out, 209, "<b") == 0
        assert _sb(out, 1372, "<i") == 0x00011954

def test_corrupt_fs_magic():
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "bad.img")
        make_badfs.build_good(out)
        make_badfs.corrupt(out, "fs_magic", 0xDEADBEEF)
        assert _sb(out, 1372, "<I") == 0xDEADBEEF

def test_corrupt_rejects_unknown_field():
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "x.img")
        make_badfs.build_good(out)
        try:
            make_badfs.corrupt(out, "fs_nonsense", 1)
        except ValueError:
            return
        raise AssertionError("expected ValueError")

def test_corrupt_is_composable_after_bad_magic():
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "compose.img")
        make_badfs.build_good(out)
        make_badfs.corrupt(out, "fs_magic", 0xDEADBEEF)
        make_badfs.corrupt(out, "fs_clean", 0)
        assert _sb(out, 209, "<b") == 0
        assert _sb(out, 1372, "<I") == 0xDEADBEEF
