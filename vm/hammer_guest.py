"""HAMMER test volumes: NeXT-labelled wrapping, header fixtures, guest runs.

Usage: hammer_guest.py run CASE OUTDIR WRAPPED_VOLUME TOOLS_DIR
       hammer_guest.py wrap VOLUME OUT
       hammer_guest.py unwrap WRAPPED OUT
       hammer_guest.py fixture KIND VOLUME OUT
       hammer_guest.py fixture-overlay KIND WRAPPED_VOLUME OUT.qcow2
Volumes are raw HAMMER images (what DragonFly's newfs_hammer writes to a
whole disk).  Rhapsody sees them as partition a of a NeXT-labelled disk.
"""
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys

import ext2_guest
import ufs_build

HERE = Path(__file__).resolve().parent

HEADER = 1928           # sizeof(struct hammer_volume_ondisk)
VOL_LABEL = 80
VOL_COUNT = 148
VOL_VERSION = 152
VOL_CRC = 156
BLOCKMAP = 264          # vol0_blockmap[16], 40 bytes each
UNDO_MAP = BLOCKMAP + 3 * 40
BLOCKMAP_CRCSIZE = 36   # offsetof(struct hammer_blockmap, entry_crc)
UNDO_NEXT = UNDO_MAP + 16
FSBUF_VOLUME_REV = 0x313052C54D4D41C8
CYLINDER = 512 * 16 * 63
CHUNK = 1 << 20

_CRC32C = []
for _i in range(256):
    _c = _i
    for _ in range(8):
        _c = (_c >> 1) ^ 0x82F63B78 if _c & 1 else _c >> 1
    _CRC32C.append(_c)


def crc32c(data: bytes) -> int:
    """iscsi_crc32: CRC-32C, the CRC of HAMMER version 7 structures."""
    crc = 0xFFFFFFFF
    for b in data:
        crc = _CRC32C[(crc ^ b) & 0xFF] ^ (crc >> 8)
    return crc ^ 0xFFFFFFFF


def _datacrc(version, data):
    if version >= 7:
        return crc32c(data)
    import zlib
    return zlib.crc32(data) & 0xFFFFFFFF


def _volume_crc(hdr):
    version = struct.unpack_from('<I', hdr, VOL_VERSION)[0]
    return _datacrc(version, bytes(hdr[:VOL_CRC])) ^ \
        _datacrc(version, bytes(hdr[VOL_CRC + 4:HEADER]))


def seal_volume_header(hdr: bytearray) -> None:
    """hammer_crc_set_volume() for the header's own vol_version."""
    struct.pack_into('<I', hdr, VOL_CRC, _volume_crc(hdr))


def volume_header_sealed(hdr: bytes) -> bool:
    return struct.unpack_from('<I', hdr, VOL_CRC)[0] == _volume_crc(hdr)


def _seal_undo_blockmap(hdr):
    version = struct.unpack_from('<I', hdr, VOL_VERSION)[0]
    crc = _datacrc(version, bytes(hdr[UNDO_MAP:UNDO_MAP + BLOCKMAP_CRCSIZE]))
    struct.pack_into('<I', hdr, UNDO_MAP + BLOCKMAP_CRCSIZE, crc)


def _label_prefix(nsectors):
    """The template's NeXT label area, with partition a sized to nsectors."""
    probe = ext2_guest.wrap_volume(bytes(512))
    copies = [off for off in range(0, min(len(probe), 65536), 512)
              if probe[off:off + 4] == b'dlV3']
    part = struct.unpack_from('>h', probe, copies[0] + 112)[0] * 512
    prefix = bytearray(probe[:part])
    ufs_build.patch_labels(prefix, part, nsectors)
    return bytes(prefix)


def wrap_volume_file(volume: Path, out: Path) -> None:
    """Stream VOLUME behind the NeXT label as partition a of OUT."""
    out = ext2_guest._new_target(out)
    volume = Path(volume)
    size = volume.stat().st_size
    if not size or size % 512 or size // 512 > 0x7fffffff:
        raise ValueError('volume must have a bounded whole number of 512-byte sectors')
    prefix = _label_prefix(size // 512)
    with out.open('xb') as dst, volume.open('rb') as src:
        dst.write(prefix)
        shutil.copyfileobj(src, dst, CHUNK)
        total = len(prefix) + size
        dst.truncate(total + (-total) % CYLINDER)


def unwrap_volume_file(wrapped: Path, out: Path) -> None:
    """Copy partition a of a NeXT-labelled disk back out to a raw volume."""
    out = ext2_guest._new_target(out)
    with Path(wrapped).open('rb') as src:
        head = src.read(65536)
        off = next(o for o in range(0, len(head), 512) if head[o:o + 4] == b'dlV3')
        sector = struct.unpack_from('>i', head, off + 92)[0]
        part = struct.unpack_from('>h', head, off + 112)[0] * sector
        size = struct.unpack_from('>i', head, off + 194)[0] * sector
        src.seek(part)
        with out.open('xb') as dst:
            left = size
            while left:
                buf = src.read(min(CHUNK, left))
                if not buf:
                    raise ValueError('wrapped disk shorter than its partition')
                dst.write(buf)
                left -= len(buf)


def make_fixture(kind: str, volume: Path, out: Path) -> None:
    """Copy VOLUME to OUT and break exactly one admission rule."""
    if kind not in ('badsig', 'v6', 'twovol', 'badcrc', 'needs-recovery'):
        raise ValueError('unknown fixture kind %r' % kind)
    out = ext2_guest._new_target(out)
    shutil.copyfile(volume, out)
    with out.open('r+b') as f:
        hdr = bytearray(f.read(HEADER))
        _break_header(kind, hdr)
        f.seek(0)
        f.write(hdr)


def _break_header(kind, hdr):
    if kind == 'badcrc':
        hdr[VOL_LABEL] ^= 0xFF
        return
    if kind == 'badsig':
        struct.pack_into('<Q', hdr, 0, FSBUF_VOLUME_REV)
    elif kind == 'v6':
        struct.pack_into('<I', hdr, VOL_VERSION, 6)
    elif kind == 'twovol':
        struct.pack_into('<i', hdr, VOL_COUNT, 2)
    elif kind == 'needs-recovery':
        nxt = struct.unpack_from('<Q', hdr, UNDO_NEXT)[0]
        struct.pack_into('<Q', hdr, UNDO_NEXT, nxt + 512)
        _seal_undo_blockmap(hdr)
    seal_volume_header(hdr)


def make_fixture_overlay(kind: str, wrapped: Path, out: Path) -> None:
    """make_fixture on a wrapped volume, as a qcow2 overlay of WRAPPED that
    holds only the changed header sectors (dense copies need too much disk)."""
    if kind not in ('badsig', 'v6', 'twovol', 'badcrc', 'needs-recovery'):
        raise ValueError('unknown fixture kind %r' % kind)
    out = ext2_guest._new_target(out)
    with Path(wrapped).open('rb') as f:
        head = f.read(65536)
        off = next(o for o in range(0, len(head), 512) if head[o:o + 4] == b'dlV3')
        part = struct.unpack_from('>h', head, off + 112)[0] * \
            struct.unpack_from('>i', head, off + 92)[0]
        f.seek(part)
        sectors = bytearray(f.read(HEADER + (-HEADER) % 512))
    _break_header(kind, sectors)
    _overlay(wrapped, out)
    src = out.with_suffix('.hdr')
    src.write_bytes(sectors)
    try:
        # qemu-io write -s reads its source in text mode on Windows; convert does not.
        subprocess.run([QEMU_IMG, 'convert', '-n', '-S', '0', '-f', 'raw', str(src),
                        '--target-image-opts',
                        'driver=raw,offset=%d,size=%d,file.driver=qcow2,'
                        'file.file.filename=%s' % (part, len(sectors), out)],
                       check=True)
    finally:
        src.unlink()


CASES = ('refuse-badsig', 'refuse-v6', 'refuse-twovol', 'refuse-badcrc',
         'refuse-needs-recovery', 'refuse-rw', 'admit')
ADMIT_MESSAGE = 'v7 single volume ok'
QEMU_IMG = r'C:\Program Files\qemu\qemu-img.exe'


def verify_result(case, status, stdout, serial, unchanged):
    problems = []
    if status != 0:
        problems.append('case exited with status %s' % status)
    if 'HAMMER_OK ' + case not in stdout.splitlines():
        problems.append('missing exact case marker')
    if 'panic:' in serial:
        problems.append('kernel panic in serial log')
    if 'hammer: leaked' in serial:
        problems.append('hammer: leak reported in serial log')
    if not unchanged:
        problems.append('data volume changed (qemu-img compare)')
    if case == 'admit' and ADMIT_MESSAGE not in serial:
        problems.append('no admission message on the console')
    return problems


def _fmt(path):
    return 'qcow2' if Path(path).suffix == '.qcow2' else 'raw'


def _overlay(base, out):
    subprocess.run([QEMU_IMG, 'create', '-q', '-f', 'qcow2', '-F', _fmt(base),
                    '-b', str(Path(base).resolve()), str(out)], check=True)


def _unchanged(overlay, base):
    r = subprocess.run([QEMU_IMG, 'compare', '-f', 'qcow2', '-F', _fmt(base),
                        str(overlay), str(Path(base).resolve())],
                       capture_output=True, text=True)
    return r.returncode == 0 and 'Images are identical' in r.stdout


def run(case, outdir, volume, tools_dir):
    """Boot a private Rhapsody guest and run one HAMMER kernel case.

    The root (RHAP_TEST_IMAGE, which must carry a HAMMER kernel) and the
    wrapped data VOLUME are both behind fresh qcow2 overlays, so neither
    base is ever written; the data overlay is compared with its base after
    the run.  The guest is stopped through QMP after query-name.
    """
    if case not in CASES:
        raise ValueError('unsupported case %r' % case)
    import importlib.util
    import time
    import uuid
    import ufs_extract
    root = os.environ.get('RHAP_TEST_IMAGE')
    if not root:
        raise ValueError('set RHAP_TEST_IMAGE to a root image with a HAMMER kernel')
    port = int(os.environ.get('RHAP_HAMMER_QMP_PORT', '5313'))
    ext2_guest.check_qmp_port(port)
    outdir = ext2_guest._new_target(outdir)
    outdir.mkdir()
    root_ov, data_ov = outdir/'root.qcow2', outdir/'data.qcow2'
    _overlay(root, root_ov)
    _overlay(volume, data_ov)
    script = ('sh run-native.sh %s /mnt/h >out.txt 2>&1\necho $? >status.txt\nsync\n'
              % case).encode('ascii')
    tests = HERE.parent/'src/hammer-1/tests'
    N = ufs_extract.Node
    nodes = [N('/', 'dir', 0o40755, 0, 0, 0, None),
             N('/h', 'dir', 0o40755, 0, 0, 0, None),
             N('/run-case.sh', 'reg', 0o100755, 0, 0, 0, script),
             N('/run-native.sh', 'reg', 0o100755, 0, 0, 0,
               (tests/'run-native.sh').read_bytes()),
             N('/hammer_io', 'reg', 0o100755, 0, 0, 0,
               (Path(tools_dir)/'hammer_io').read_bytes())]
    results = outdir/'results.img'
    results.write_bytes(ufs_build.build(ext2_guest.TEMPLATE, nodes))
    spec = importlib.util.spec_from_file_location('hammer_console', HERE/'guest-console.py')
    gc = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gc)
    name = 'hammer-' + uuid.uuid4().hex
    data = 'file=%s,format=qcow2,if=ide,index=1,media=disk,snapshot=off' % data_ov
    res = 'file=%s,format=raw,if=ide,index=2,media=disk,snapshot=off' % results
    guest = ext2_guest.start_guest(gc.Guest, str(outdir), image=str(root_ov), port=port,
                                   extra=('-name', name, '-drive', data, '-drive', res))
    serial = outdir/'serial.log'
    try:
        time.sleep(6)
        ext2_guest.check_guest(guest, name)
        guest.line('-s'); time.sleep(135)
        guest.line('mount -uw /'); time.sleep(5)
        guest.line('mknod /dev/hd2a b 3 16'); time.sleep(3)
        guest.line('mount /dev/hd2a /mnt'); time.sleep(5)
        guest.line('cd /mnt; sh run-case.sh')
        deadline = time.monotonic() + 1800
        while time.monotonic() < deadline:
            time.sleep(15)
            if 'panic:' in serial.read_text(errors='replace'):
                break
            try:
                status, stdout = ext2_guest._read_result(results)
                if status is not None:
                    break
            except (OSError, ValueError):
                pass
        guest.shot('end')
    finally:
        reply = guest.cmd('query-name')
        if reply and reply.get('return', {}).get('name') == name:
            guest.cmd('quit')
        try:
            guest.proc.wait(timeout=30)
        except subprocess.TimeoutExpired:
            pass
    status, stdout = ext2_guest._read_result(results)
    (outdir/'out.txt').write_text(stdout or '')
    (outdir/'status.txt').write_text(status or 'missing')
    code = int(status.strip()) if status and status.strip().isdigit() else -1
    problems = verify_result(case, code, stdout or '',
                             serial.read_text(errors='replace'),
                             _unchanged(data_ov, volume))
    for problem in problems:
        print(problem)
    return int(bool(problems))


def main(argv):
    if len(argv) == 6 and argv[1] == 'run':
        return run(*argv[2:])
    if len(argv) == 4 and argv[1] == 'wrap':
        wrap_volume_file(argv[2], argv[3])
        return 0
    if len(argv) == 4 and argv[1] == 'unwrap':
        unwrap_volume_file(argv[2], argv[3])
        return 0
    if len(argv) == 5 and argv[1] == 'fixture':
        make_fixture(argv[2], argv[3], argv[4])
        return 0
    if len(argv) == 5 and argv[1] == 'fixture-overlay':
        make_fixture_overlay(argv[2], argv[3], argv[4])
        return 0
    raise ValueError(__doc__)


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv))
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
