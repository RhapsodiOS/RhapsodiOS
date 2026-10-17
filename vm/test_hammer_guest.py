"""HAMMER test volumes: NeXT wrapping, header fixtures and CRC32C."""
import importlib.util
import struct

import pytest

_spec = importlib.util.find_spec('hammer_guest')
hg = None if _spec is None else __import__('hammer_guest')

VOL_CRC = 156
UNDO_MAP = 264 + 3 * 40
HEADER = 1928


@pytest.fixture(autouse=True)
def implementation_exists():
    assert hg is not None, 'hammer guest harness is not implemented'


@pytest.fixture
def label(tmp_path, monkeypatch):
    # Four real-format NeXT label copies, 16 KiB front, 1024-byte sectors.
    import ext2_guest
    raw = bytearray(16384)
    for off in (0, 4096, 8192, 12288):
        raw[off:off+4] = b'dlV3'
        struct.pack_into('>i', raw, off+92, 1024)
        struct.pack_into('>h', raw, off+112, 16)
        struct.pack_into('>i', raw, off+190, 0)
        struct.pack_into('>i', raw, off+194, 32)
    path = tmp_path/'label.img'
    path.write_bytes(raw + bytes(32768))
    monkeypatch.setattr(ext2_guest, 'TEMPLATE', str(path))
    return path


def volume(tmp_path, size=64 * 1024 * 1024):
    """A sparse volume with a sealed v7 header and a recognisable tail."""
    path = tmp_path/'vol.img'
    with path.open('wb') as f:
        f.truncate(size)
    hdr = bytearray(HEADER)
    struct.pack_into('<Q', hdr, 0, 0xC8414D4DC5523031)
    struct.pack_into('<q', hdr, 24, 1 << 20)                     # vol_buf_beg
    struct.pack_into('<q', hdr, 32, size)                        # vol_buf_end
    hdr[80:84] = b'TEST'                                         # vol_label
    struct.pack_into('<iiI', hdr, 144, 0, 1, 7)                  # no, count, version
    struct.pack_into('<QQ', hdr, UNDO_MAP + 8, 3 << 60, 3 << 60)  # undo first, next
    hg.seal_volume_header(hdr)
    with path.open('r+b') as f:
        f.write(hdr)
        f.seek(size - 4)
        f.write(b'TAIL')
    return path


def test_crc32c_vector():
    assert hg.crc32c(b'123456789') == 0xE3069283


def test_seal_matches_layout():
    hdr = bytearray(HEADER)
    struct.pack_into('<I', hdr, 152, 7)
    hg.seal_volume_header(hdr)
    crc = hg.crc32c(bytes(hdr[:VOL_CRC])) ^ hg.crc32c(bytes(hdr[VOL_CRC+4:HEADER]))
    assert struct.unpack_from('<I', hdr, VOL_CRC)[0] == crc


def test_wrap_roundtrip(tmp_path, label):
    vol = volume(tmp_path)
    wrapped, back = tmp_path/'w.img', tmp_path/'b.img'
    hg.wrap_volume_file(vol, wrapped)
    raw = wrapped.read_bytes()
    part = struct.unpack_from('>h', raw, 112)[0] * 512
    assert struct.unpack_from('>i', raw, 92)[0] == 512
    assert struct.unpack_from('>i', raw, 194)[0] == vol.stat().st_size // 512
    assert raw[part:part+8] == vol.read_bytes()[:8]
    assert len(raw) % (512 * 16 * 63) == 0
    hg.unwrap_volume_file(wrapped, back)
    assert back.read_bytes() == vol.read_bytes()


def test_wrap_refuses_existing_output(tmp_path, label):
    vol = volume(tmp_path)
    out = tmp_path/'w.img'
    out.write_bytes(b'keep')
    with pytest.raises(FileExistsError):
        hg.wrap_volume_file(vol, out)
    assert out.read_bytes() == b'keep'


@pytest.mark.parametrize('kind,offset,check', [
    ('badsig', 0, lambda h: struct.unpack_from('<Q', h, 0)[0] == 0x313052C54D4D41C8),
    ('v6', 152, lambda h: struct.unpack_from('<I', h, 152)[0] == 6),
    ('twovol', 148, lambda h: struct.unpack_from('<i', h, 148)[0] == 2),
    ('needs-recovery', UNDO_MAP + 16,
     lambda h: struct.unpack_from('<Q', h, UNDO_MAP + 16)[0] == (3 << 60) + 512),
])
def test_fixture_changes_one_rule(tmp_path, kind, offset, check):
    vol = volume(tmp_path)
    out = tmp_path/(kind + '.img')
    hg.make_fixture(kind, vol, out)
    old, new = vol.read_bytes(), out.read_bytes()
    assert len(old) == len(new)
    assert check(new)
    assert hg.volume_header_sealed(new[:HEADER])
    changed = [i for i in range(len(old)) if old[i] != new[i]]
    allowed = set(range(offset, offset + 8)) | set(range(VOL_CRC, VOL_CRC + 4)) | \
        set(range(UNDO_MAP + 36, UNDO_MAP + 40))
    assert set(changed) <= allowed


def test_badcrc_breaks_only_the_crc(tmp_path):
    vol = volume(tmp_path)
    out = tmp_path/'badcrc.img'
    hg.make_fixture('badcrc', vol, out)
    new = out.read_bytes()
    assert not hg.volume_header_sealed(new[:HEADER])
    assert new[80:84] != b'TEST'
    assert new[HEADER:] == vol.read_bytes()[HEADER:]


def test_fixture_refuses_unknown_kind(tmp_path):
    with pytest.raises(ValueError):
        hg.make_fixture('nonsense', volume(tmp_path), tmp_path/'x.img')
