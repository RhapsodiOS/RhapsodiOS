import os, struct, tempfile
import pytest
import make_badfs, rhap_image, ufs_check

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

def test_pad_appends_zeros_after_a_valid_filesystem():
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "padded.img")
        make_badfs.build_good(out, pad=65536)
        assert os.path.getsize(out) == 1474560 + 65536
        assert _sb(out, 1372, "<i") == 0x00011954
        assert _sb(out, 209, "<b") == 1
        with open(out, "rb") as f:
            f.seek(1474560)
            assert f.read() == bytes(65536)

def test_field_offset_and_read_field():
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "good.img")
        make_badfs.build_good(out)
        part_start = make_badfs._read_partition_start(out)
        assert make_badfs.field_offset(out, "fs_clean") == part_start + 8192 + 209
        assert make_badfs.read_field(out, "fs_clean") == 1
        assert make_badfs.read_field(out, "fs_magic") == 0x00011954
        # well past 4 GiB, so the kernel's 4 GB clamp is not a no-op here
        assert make_badfs.read_field(out, "fs_maxfilesize") > 1 << 32
        with pytest.raises(ValueError):
            make_badfs.field_offset(out, "fs_nonsense")

def test_reload_sectors_point_at_what_ffs_reload_reads():
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "good.img")
        make_badfs.build_good(out)
        s = make_badfs.reload_sectors(out)
        assert len(set(s.values())) == 3
        with open(out, "rb") as f:
            def sector(n, length=512):
                f.seek(n * 512)
                return f.read(length)
            sb = sector(s["superblock"], 8192)
            # the superblock: its magic
            assert struct.unpack_from("<i", sb, 1372)[0] == 0x00011954
            # the summary area: one cylinder group, so its only struct csum
            # equals the superblock's fs_cstotal, at byte 192
            assert sector(s["csum"])[:16] == sb[192:208]
            # the block holding inode 2, 128 bytes per dinode: the root
            # directory
            mode = struct.unpack_from("<H", sector(s["inode2"], 8192), 2 * 128)[0]
            assert mode & 0o170000 == 0o040000

def test_build_good_with_nfiles_gives_a_valid_image_with_files():
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "files.img")
        make_badfs.build_good(out, nfiles=70)
        assert ufs_check.check(out) == []
        with rhap_image.Image(out) as img:
            assert img.resolve("/f00") is not None
            assert img.resolve("/f69") is not None

def test_inode_block_sector_matches_reload_sectors_inode2():
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "good.img")
        make_badfs.build_good(out)
        assert (make_badfs.inode_block_sector(out, 2)
                == make_badfs.reload_sectors(out)["inode2"])

def test_inode_block_sector_for_f69_differs_and_is_a_regular_file():
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "files.img")
        make_badfs.build_good(out, nfiles=70)
        with rhap_image.Image(out) as img:
            ino = img.resolve("/f69")
            _, byte_off = rhap_image._inode_location(img, ino)
        sector2 = make_badfs.inode_block_sector(out, 2)
        sector69 = make_badfs.inode_block_sector(out, ino)
        assert sector69 != sector2
        # Read the raw bytes directly, independently of the code under test.
        with open(out, "rb") as f:
            f.seek(sector69 * 512)
            blk = f.read(8192)
        mode = struct.unpack_from("<H", blk, byte_off)[0]
        assert mode & 0o170000 == 0o100000
