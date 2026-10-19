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


@pytest.mark.skipif(not __import__('os').path.exists(
    r'C:\Program Files\qemu\qemu-img.exe'), reason='needs qemu-img')
def test_fixture_overlay_matches_dense_fixture(tmp_path, label):
    import subprocess
    vol = volume(tmp_path)
    wrapped, dense, ov = tmp_path/'w.img', tmp_path/'v6.img', tmp_path/'v6.qcow2'
    hg.wrap_volume_file(vol, wrapped)
    hg.make_fixture('v6', vol, dense)
    before = wrapped.read_bytes()
    hg.make_fixture_overlay('v6', wrapped, ov)
    assert wrapped.read_bytes() == before
    flat = tmp_path/'flat.img'
    subprocess.run([hg.QEMU_IMG, 'convert', '-O', 'raw', str(ov), str(flat)], check=True)
    back = tmp_path/'back.img'
    hg.unwrap_volume_file(flat, back)
    assert back.read_bytes() == dense.read_bytes()


def test_badcrc_breaks_only_the_crc(tmp_path):
    vol = volume(tmp_path)
    out = tmp_path/'badcrc.img'
    hg.make_fixture('badcrc', vol, out)
    new = out.read_bytes()
    assert not hg.volume_header_sealed(new[:HEADER])
    assert new[80:84] != b'TEST'
    assert new[HEADER:] == vol.read_bytes()[HEADER:]


def test_verify_result_accepts_clean_run():
    assert hg.verify_result('refuse-v6', 0, 'x\nHAMMER_OK refuse-v6\n', 'boot\n', True) == []


@pytest.mark.parametrize('status,out,serial,same,problem', [
    (1, 'HAMMER_OK refuse-v6\n', '', True, 'status'),
    (0, 'HAMMER_OK refuse-v66\n', '', True, 'marker'),
    (0, 'HAMMER_OK refuse-v6\n', 'panic: oops\n', True, 'panic'),
    (0, 'HAMMER_OK refuse-v6\n', 'hammer: leaked inodes=1\n', True, 'leak'),
    (0, 'HAMMER_OK refuse-v6\n', '', False, 'changed'),
])
def test_verify_result_reports_each_failure(status, out, serial, same, problem):
    problems = hg.verify_result('refuse-v6', status, out, serial, same)
    assert any(problem in p for p in problems)


def test_admit_needs_admission_message():
    out = 'HAMMER_OK admit\n'
    assert any('admission' in p for p in hg.verify_result('admit', 0, out, '', True))
    assert hg.verify_result('admit', 0, out,
                            'hammer: /dev/hd1a: v7 single volume ok\n', True) == []


def test_run_rejects_unknown_case(tmp_path):
    with pytest.raises(ValueError):
        hg.run('nonsense', tmp_path/'out', tmp_path/'v.img', tmp_path)


def test_fixture_refuses_unknown_kind(tmp_path):
    with pytest.raises(ValueError):
        hg.make_fixture('nonsense', volume(tmp_path), tmp_path/'x.img')


BUF_BEG = 1 << 20
NODE = 4096


def tree_volume(tmp_path):
    """A v7 volume whose B-tree is one leaf: root dir 1 holding a, old and
    future (objects 2-4), each with a current inode record."""
    size = 4 << 20
    path = tmp_path/'tree.img'
    img = bytearray(size)
    hdr = bytearray(HEADER)
    struct.pack_into('<Q', hdr, 0, 0xC8414D4DC5523031)
    struct.pack_into('<qq', hdr, 24, BUF_BEG, size)
    struct.pack_into('<iiI', hdr, 144, 0, 1, 7)
    struct.pack_into('<Q', hdr, 240, (8 << 60) | 0)          # vol0_btree_root
    hg.seal_volume_header(hdr)
    img[:HEADER] = hdr
    node = bytearray(NODE)
    elms = []
    data = BUF_BEG + 65536

    def leaf(obj_id, key, rec_type, payload, data):
        img[data:data + len(payload)] = payload
        e = bytearray(64)
        struct.pack_into('<QQQQH', e, 0, obj_id, key, 1, 0, rec_type)
        crced = payload[:112] if rec_type == 0x01 else payload   # HAMMER_INODE_CRCSIZE
        struct.pack_into('<QII', e, 48, (11 << 60) | (data - BUF_BEG),
                         len(payload), hg.crc32c(crced))
        elms.append(e)
    for n, name in enumerate((b'a', b'old', b'future')):
        leaf(1, n, 0x11, struct.pack('<QII', 2 + n, 0, 0) + name, data)
        ino = bytearray(128)
        struct.pack_into('<Q', ino, 112, 1792249285 * 1000000)
        leaf(2 + n, 0, 0x01, bytes(ino), data + 1024)
        data += 2048
    struct.pack_into('<IB', node, 16, len(elms), ord('L'))
    for i, e in enumerate(elms):
        node[64 + i * 64:128 + i * 64] = e
    struct.pack_into('<I', node, 0, hg.crc32c(bytes(node[4:])))
    img[BUF_BEG:BUF_BEG + NODE] = node
    path.write_bytes(bytes(img))
    return path


def leaf_of(raw, obj_id, rec_type):
    node = raw[BUF_BEG:BUF_BEG + NODE]
    for i in range(struct.unpack_from('<I', node, 16)[0]):
        e = 64 + i * 64
        if struct.unpack_from('<Q', node, e)[0] == obj_id and \
           struct.unpack_from('<H', node, e + 32)[0] == rec_type:
            off, n, crc = struct.unpack_from('<QII', node, e + 48)
            return BUF_BEG + (off & 0x000FFFFFFFFFFFFF), n, crc
    raise KeyError(obj_id)


def test_longname_fixture_stretches_one_entry(tmp_path):
    vol = tree_volume(tmp_path)
    out = tmp_path/'longname.img'
    hg.make_fixture('longname', vol, out)
    old, new = vol.read_bytes(), out.read_bytes()
    node = new[BUF_BEG:BUF_BEG + NODE]
    assert struct.unpack_from('<I', node, 0)[0] == hg.crc32c(node[4:])
    data, n, crc = leaf_of(new, 1, 0x11)          # first entry is 'a'
    assert n == 16 + 256
    assert crc == hg.crc32c(new[data:data + n])
    changed = {i for i in range(len(old)) if old[i] != new[i]}
    assert changed <= set(range(BUF_BEG, BUF_BEG + NODE))


def test_walk_matches_ignores_content_crc():
    want = './a\tf\t644\t0\t0\t1\t0\t5\t4294967295\n./d\td\t755\t0\t0\t1\t0\t5\t-\n'
    got = './a\tf\t644\t0\t0\t1\t0\t5\t-\n./d\td\t755\t0\t0\t1\t0\t5\t-\n'
    assert hg.walk_differences(got, want) == []
    assert hg.walk_differences(got.replace('644', '600'), want) != []
    assert hg.walk_differences(got.splitlines(True)[0], want) != []
