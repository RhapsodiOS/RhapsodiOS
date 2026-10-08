"""Private ext2 guest preparation: test real labels and refusal side effects."""
import importlib.util
from pathlib import Path
import struct
import socket
from types import SimpleNamespace
import pytest

_spec = importlib.util.find_spec('ext2_guest')
eg = None if _spec is None else __import__('ext2_guest')

@pytest.fixture(autouse=True)
def implementation_exists():
    assert eg is not None, 'ext2 guest harness is not implemented'

@pytest.fixture
def label(tmp_path, monkeypatch):
    # Four real-format NeXT label copies, 16 KiB front, 1024-byte sectors.
    import ufs_build
    raw = bytearray(16384)
    for off in (0, 4096, 8192, 12288):
        raw[off:off+4] = b'dlV3'
        struct.pack_into('>i', raw, off+92, 1024)
        struct.pack_into('>h', raw, off+112, 16)
        struct.pack_into('>i', raw, off+190, 0)
        struct.pack_into('>i', raw, off+194, 32)
    path = tmp_path/'label.img'
    path.write_bytes(raw + bytes(32768))
    monkeypatch.setattr(eg, 'TEMPLATE', str(path))
    return path

def test_partition_payload_identity_and_all_label_bounds(label):
    payload = bytes(range(256))*128
    wrapped = eg.wrap_volume(payload)
    assert wrapped[16384:49152] == payload
    assert len(wrapped) >= 49152
    for off in (0,4096,8192,12288):
        assert struct.unpack_from('>i', wrapped, off+92)[0] == 512
        assert struct.unpack_from('>h', wrapped, off+112)[0] == 32
        assert struct.unpack_from('>i', wrapped, off+194)[0] == 64

def test_invalid_sector_length_refused(label):
    with pytest.raises(ValueError): eg.wrap_volume(bytes(513))

def test_truncated_label_refused(label):
    label.write_bytes(label.read_bytes()[:100])
    with pytest.raises(ValueError): eg.wrap_volume(bytes(512))

def test_wrap_preserves_source_and_refuses_existing_output(label,tmp_path):
    volume = tmp_path/'volume.img'; volume.write_bytes(bytes(32768))
    output = tmp_path/'output.img'; output.write_bytes(b'untouched')
    with pytest.raises((ValueError,FileExistsError)):
        eg.wrap_file(volume,output)
    assert output.read_bytes() == b'untouched'
    assert volume.read_bytes() == bytes(32768)

def test_protected_master_refused_before_write(label,tmp_path):
    volume = tmp_path/'volume.img'; volume.write_bytes(bytes(32768))
    for name in ('golden.img','rhapsody.vmdk'):
        target = tmp_path/name
        with pytest.raises(ValueError): eg.wrap_file(volume,target)
        assert not target.exists()

def test_run_directory_is_never_reused(tmp_path):
    output = tmp_path/'run'; output.mkdir(); (output/'keep').write_bytes(b'base')
    with pytest.raises((ValueError,FileExistsError)):
        eg.prepare_run(output,tmp_path/'absent',tmp_path/'absent-root')
    assert list(output.iterdir()) == [output/'keep']
    assert (output/'keep').read_bytes() == b'base'

def test_prepare_run_copies_root_and_data(tmp_path):
    root = tmp_path/'base.img'; root.write_bytes(b'root')
    data = tmp_path/'data.img'; data.write_bytes(b'data')
    out = tmp_path/'run'
    private_root,private_data = eg.prepare_run(out,data,root)
    Path(private_root).write_bytes(b'changed'); Path(private_data).write_bytes(b'changed')
    assert root.read_bytes() == b'root' and data.read_bytes() == b'data'

@pytest.mark.parametrize('status,stdout',[(1,'EXT2_OK readonly\n'),(0,''),(0,'EXT2_OK write\n'),(0,'prefix EXT2_OK readonly\n'),(0,'EXT2_OK readonly extra\n')])
def test_missing_or_failed_case_marker(status,stdout):
    assert eg.verify_result('readonly',status,stdout)

def test_exact_success_marker():
    assert eg.verify_result('readonly',0,'listing\nEXT2_OK readonly\n') == []

def test_front_area_larger_than_64k_is_preserved(label):
    prefix = bytearray(label.read_bytes()[:16384])
    for off in (0,4096,8192,12288):
        struct.pack_into('>h',prefix,off+112,160)
    prefix.extend(bytes(163840-len(prefix)))
    label.write_bytes(prefix+bytes(512))
    wrapped = eg.wrap_volume(bytes(1024))
    assert len(wrapped) >= 164864
    assert wrapped[163840:164864] == bytes(1024)

def test_partition_end_survives_legacy_ide_chs_rounding(label):
    payload = bytes(16*1024*1024)
    wrapped = eg.wrap_volume(payload)
    cylinder = 512*16*63
    visible_bytes = len(wrapped)//cylinder*cylinder
    assert 16384+len(payload) <= visible_bytes
    assert len(wrapped) % cylinder == 0
    assert wrapped[16384:16384+len(payload)] == payload
    assert not any(wrapped[16384+len(payload):])

def test_occupied_qmp_port_is_refused():
    with socket.socket() as listener:
        listener.bind(('127.0.0.1',0))
        listener.listen()
        with pytest.raises(OSError,match='QMP port is already in use'):
            eg.check_qmp_port(listener.getsockname()[1])

@pytest.mark.parametrize('exit_status,reported_name',[(1,'ours'),(None,'another-guest')])
def test_wrong_or_exited_guest_is_refused(exit_status,reported_name):
    guest = SimpleNamespace(proc=SimpleNamespace(poll=lambda:exit_status),
                            cmd=lambda command:{'return':{'name':reported_name}})
    with pytest.raises(OSError): eg.check_guest(guest,'ours')

def test_partial_guest_constructor_closes_only_its_child():
    closed = []
    class FailedGuest:
        def __init__(self):
            self.proc = object()
            raise OSError('no QMP connection')
        def close(self): closed.append(self.proc)
    with pytest.raises(OSError,match='no QMP connection'):
        eg.start_guest(FailedGuest)
    assert len(closed) == 1

def test_run_command_uses_supported_console_keys():
    spec = importlib.util.spec_from_file_location('ext2_test_console',eg.HERE/'guest-console.py')
    console = importlib.util.module_from_spec(spec); spec.loader.exec_module(console)
    allowed = set(console.PLAIN_MAP) | set(console.SHIFT_MAP)
    unsupported = [ch for ch in eg.RUN_COMMAND if ch not in allowed and not ch.isalnum()]
    assert not unsupported

@pytest.mark.parametrize('sector',[512,1024])
def test_capacity_fixture_has_exact_and_invalid_logical_sizes(label,sector):
    raw = eg.capacity_fixture(sector)
    for off in (0,4096,8192,12288):
        assert struct.unpack_from('>i',raw,off+92)[0] == sector
        assert struct.unpack_from('>h',raw,off+112)[0]*sector == 16384
        assert struct.unpack_from('>i',raw,off+194)[0]*sector == 16*1024*1024
        assert struct.unpack_from('>i',raw,off+194+46)[0]*sector == len(raw)
        assert struct.unpack_from('>i',raw,off+194+92)[0]*sector > len(raw)
        assert struct.unpack_from('>i',raw,off+194+6*46)[0] == 0
        assert struct.unpack_from('>H',raw,off+558)[0] == eg.ufs_build.label_checksum(raw[off:off+560])

def test_tiny_fixture_declares_one_through_four_sectors(label):
    raw = eg.tiny_fixture()
    for off in (0,4096,8192,12288):
        assert struct.unpack_from('>i',raw,off+92)[0] == 512
        assert [struct.unpack_from('>i',raw,off+194+46*i)[0] for i in range(4)] == [1,2,3,4]
        assert struct.unpack_from('>H',raw,off+558)[0] == eg.ufs_build.label_checksum(raw[off:off+560])
    assert raw[16384:16384+2048] == bytes(2048)

def test_suite_partitions_are_disjoint_bounded_and_preserve_payloads(label):
    payloads=[b'a'*1024,b'b'*1536]
    raw=eg.wrap_volumes(payloads)
    for off in (0,4096,8192,12288):
        front=struct.unpack_from('>h',raw,off+112)[0]*512
        assert front == 16384
        assert struct.unpack_from('>ii',raw,off+190) == (0,2)
        assert struct.unpack_from('>ii',raw,off+236) == (2,3)
        assert struct.unpack_from('>H',raw,off+558)[0] == eg.ufs_build.label_checksum(raw[off:off+560])
    assert raw[16384:17408] == payloads[0]
    assert raw[17408:18944] == payloads[1]

def test_suite_refuses_live_slot_and_unaligned_payloads(label):
    for payloads in ([bytes(512)]*8,[],[bytes(513)]):
        with pytest.raises(ValueError): eg.wrap_volumes(payloads)

@pytest.mark.parametrize('partition',[0,1])
def test_suite_preserves_label_magic_inside_payload(label,partition):
    payloads=[bytearray(b'a'*2048),bytearray(b'b'*2048)]
    payloads[partition][512:516]=b'dlV3'
    raw=eg.wrap_volumes(payloads)
    assert raw[16384:18432] == payloads[0]
    assert raw[18432:20480] == payloads[1]
