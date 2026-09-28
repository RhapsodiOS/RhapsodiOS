"""Host-side tests for hfs_guest.py; nothing here boots a guest."""

import os
import struct

import pytest

import hfs_guest as hg

if not os.path.exists(hg.TEMPLATE):
    pytest.skip("installation floppy template is not present", allow_module_level=True)

import content      # noqa: E402  (from tools/hfsimg, put on sys.path by hfs_guest)
import rhap_image   # noqa: E402
import scenario     # noqa: E402


@pytest.fixture
def hfsplus(tmp_path):
    path = str(tmp_path / "hfsplus.img")
    hg.build_image("hfsplus", path)
    return path


def test_every_label_copy_says_512_byte_sectors(hfsplus):
    with open(hfsplus, "rb") as f:
        img = f.read(hg.label_front())
    copies = [off for off in rhap_image.LABEL_OFFSETS if img[off:off + 4] == b"dlV3"]
    assert copies
    for off in copies:
        secsize, = struct.unpack_from(">i", img, off + hg.LABEL_SECSIZE)
        front, = struct.unpack_from(">h", img, off + hg.LABEL_FRONT)
        p_size, = struct.unpack_from(">i", img, off + 194)
        assert (secsize, front * 512, p_size) == (512, hg.label_front(), hg.VOLUME_SIZE // 512)


def test_labelled_volume_opens_and_checks(hfsplus):
    assert hg.main(["x", "check", hfsplus]) == 0


def test_results_disk_round_trip(tmp_path):
    binary = tmp_path / "mount_hfs"
    binary.write_bytes(b"\xce\xfa\xed\xfe" + b"\0" * 4000)
    disk = str(tmp_path / "results.img")
    hg.results_disk(disk, "echo hi\n", str(binary))
    assert hg.read_results(disk) == {"out.txt": None, "list.txt": None, "sums.txt": None}
    with rhap_image.Image(disk) as img:
        assert img.read_file(img.inode(img.resolve("/run.sh"))) == b"echo hi\n"
        assert img.read_file(img.inode(img.resolve("/mount_hfs")))[:4] == b"\xce\xfa\xed\xfe"


def _simulated_guest(path):
    """What a correct guest would report for a read of `path`."""
    with hg.open_volume(path) as v:
        walk = v.walk()
        listing = "\n".join(sorted(["."] + ["." + p for p, e in walk]))
        sums = "\n".join("%d %d .%s" % (content.cksum(v.read_file(e)), e.data.logical_size, p)
                         for p, e in sorted(walk) if not e.is_dir)
    return {"out.txt": "BEGIN\nmount rc=0\nreport done\numount rc=0\nEND\n",
            "list.txt": listing, "sums.txt": sums}


def test_verify_accepts_a_correct_read(hfsplus, tmp_path):
    assert hg.verify("read", str(tmp_path), hfsplus, _simulated_guest(hfsplus)) == []


def test_verify_rejects_wrong_output(hfsplus, tmp_path):
    good = _simulated_guest(hfsplus)
    bad_sum = dict(good, **{"sums.txt": good["sums.txt"].replace("top.txt", "top.txx")})
    assert any("checksums differ" in p for p in hg.verify("read", str(tmp_path), hfsplus, bad_sum))
    no_end = dict(good, **{"out.txt": "BEGIN\nmount rc=0\n"})
    assert any("'END'" in p for p in hg.verify("read", str(tmp_path), hfsplus, no_end))
    (tmp_path / "serial.log").write_text("panic: hfs_swap\n")
    assert any("serial" in p for p in hg.verify("read", str(tmp_path), hfsplus, good))


def _poke_sector(path, off):
    with open(path, "r+b") as f:
        f.seek(off + 64)
        b = f.read(1)
        f.seek(off + 64)
        f.write(bytes([b[0] ^ 0xff]))


def test_verify_ignores_a_plain_volumes_own_header(hfsplus, tmp_path):
    before = str(tmp_path / "before.img")
    with open(hfsplus, "rb") as a, open(before, "wb") as b:
        b.write(a.read())
    # the kernel rewrites a plain volume's header; check() covers it, not the wrapper test
    good = _simulated_guest(hfsplus)
    _poke_sector(hfsplus, hg.label_front() + 1024)
    assert not any("wrapper" in p for p in hg.verify("read", str(tmp_path), hfsplus, good, before))


def test_verify_rejects_a_changed_wrapper(tmp_path):
    wrapped = str(tmp_path / "wrapped.img")
    hg.build_image("wrapped", wrapped)
    before = str(tmp_path / "before.img")
    with open(wrapped, "rb") as a, open(before, "wb") as b:
        b.write(a.read())
    good = _simulated_guest(wrapped)
    _poke_sector(wrapped, hg.label_front() + 1024)
    assert "wrapper MDB changed" in hg.verify("read", str(tmp_path), wrapped, good, before)
