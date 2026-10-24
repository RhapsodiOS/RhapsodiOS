"""HAMMER test volumes: NeXT-labelled wrapping, header fixtures, guest runs.

Usage: hammer_guest.py run CASE OUTDIR WRAPPED_VOLUME TOOLS_DIR
       hammer_guest.py wrap VOLUME OUT
       hammer_guest.py unwrap WRAPPED OUT
       hammer_guest.py fixture KIND VOLUME OUT
       hammer_guest.py fixture-overlay KIND WRAPPED_VOLUME OUT.qcow2
       hammer_guest.py dfly-check RAW_VOLUME OUTDIR
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


HEADER_KINDS = ('badsig', 'v6', 'twovol', 'badcrc', 'needs-recovery')
FIXTURE_KINDS = HEADER_KINDS + ('longname', 'baddata', 'badcount', 'badlen',
                                'badoff', 'dotdot', 'dirhash', 'pfs')


def make_fixture(kind: str, volume: Path, out: Path) -> None:
    """Copy VOLUME to OUT and break exactly one rule (see _fixture_patches)."""
    if kind not in FIXTURE_KINDS:
        raise ValueError('unknown fixture kind %r' % kind)
    out = ext2_guest._new_target(out)
    with Path(volume).open('rb') as f:
        patches = _fixture_patches(kind, _reader(f, 0))
    shutil.copyfile(volume, out)
    with out.open('r+b') as f:
        for off, data in patches:
            f.seek(off)
            f.write(data)


def _reader(f, base):
    def read(off, n):
        f.seek(base + off)
        return f.read(n)
    return read


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


VOL_BUF_BEG = 24
VOL0_BTREE_ROOT = 240
NODE_SIZE = 4096        # struct hammer_node_ondisk
BUFSIZE = 16384         # HAMMER_BUFSIZE: records never cross one
RECTYPE_INODE = 0x0001
RECTYPE_DATA = 0x0010
RECTYPE_DIRENTRY = 0x0011
ENTRY_NAME_OFF = 16
ELM_LOCALIZATION = 36   # in struct hammer_base_elm
OBJID_ROOT = 1
INODE_SIZE = 128        # struct hammer_inode_data
INODE_PARENT = 24
INODE_CAP_FLAGS = 65
INODE_CRCSIZE = 112     # HAMMER_INODE_CRCSIZE: mtime and atime are not CRCd


def _leaves(read):
    """Every B-tree leaf element, as dicts with physical node/data offsets."""
    hdr = read(0, HEADER)
    beg = struct.unpack_from('<q', hdr, VOL_BUF_BEG)[0]

    def phys(zoff):
        return beg + (zoff & 0x000FFFFFFFFFFFFF)
    stack = [struct.unpack_from('<Q', hdr, VOL0_BTREE_ROOT)[0]]
    while stack:
        noff = phys(stack.pop())
        node = read(noff, NODE_SIZE)
        count, ntype = struct.unpack_from('<IB', node, 16)
        for i in range(count):
            e = 64 + i * 64
            if ntype == ord('I'):
                stack.append(struct.unpack_from('<Q', node, e + 48)[0])
            elif ntype == ord('L'):
                obj_id, _, _, delete_tid, rec_type = \
                    struct.unpack_from('<QQQQH', node, e)
                doff, dlen = struct.unpack_from('<QI', node, e + 48)
                yield dict(node=noff, elm=e, obj_id=obj_id, delete_tid=delete_tid,
                           rec_type=rec_type, data=phys(doff), data_len=dlen)


def _current(leaves, obj_id, rec_type):
    return [l for l in leaves if l['obj_id'] == obj_id and
            l['rec_type'] == rec_type and l['delete_tid'] == 0]


def _entry(read, leaves, name):
    """The current root-directory entry for NAME."""
    for l in _current(leaves, OBJID_ROOT, RECTYPE_DIRENTRY):
        if l['data_len'] == ENTRY_NAME_OFF + len(name) and \
           read(l['data'] + ENTRY_NAME_OFF, len(name)) == name:
            return l
    raise ValueError('no root entry %r' % name)


def _fixture_patches(kind, read):
    """(volume offset, bytes) patches that make fixture KIND.

    longname: root entry 'a' claims a 256-byte name (past NAME_MAX); its
    data CRC and node CRC are resealed so only the length check can catch it.
    baddata: one byte inside the first data record of root file
    'size1048577' is flipped, so that record's data CRC fails.
    pfs: the B-Tree's last element moves to PFS 1 (localization
    0x00010002); keys sort by localization first, so the tree stays ordered.
    """
    if kind in HEADER_KINDS:
        sectors = bytearray(read(0, HEADER + (-HEADER) % 512))
        _break_header(kind, sectors)
        return [(0, bytes(sectors))]
    if kind == 'pfs':
        hdr = read(0, HEADER)
        beg = struct.unpack_from('<q', hdr, VOL_BUF_BEG)[0]
        zoff = struct.unpack_from('<Q', hdr, VOL0_BTREE_ROOT)[0]
        while True:
            noff = beg + (zoff & 0x000FFFFFFFFFFFFF)
            node = bytearray(read(noff, NODE_SIZE))
            count, ntype = struct.unpack_from('<IB', node, 16)
            last = 64 + (count - 1) * 64
            if ntype == ord('L'):
                break
            zoff = struct.unpack_from('<Q', node, last + 48)[0]
        struct.pack_into('<I', node, last + ELM_LOCALIZATION, 0x00010002)
        struct.pack_into('<I', node, 0, crc32c(bytes(node[4:])))
        return [(noff, bytes(node))]
    leaves = list(_leaves(read))
    if kind in ('badcount', 'badlen', 'badoff'):
        l = _entry(read, leaves, b'a')
        node = bytearray(read(l['node'], NODE_SIZE))
        if kind == 'badcount':
            struct.pack_into('<I', node, 16, 200)           # 63 is the most
        elif kind == 'badlen':
            struct.pack_into('<I', node, l['elm'] + 56, 70000)
        else:
            struct.pack_into('<Q', node, l['elm'] + 48, 0)
        struct.pack_into('<I', node, 0, crc32c(bytes(node[4:])))
        return [(l['node'], bytes(node))]
    if kind in ('dotdot', 'dirhash'):
        if kind == 'dotdot':
            obj_id = struct.unpack('<Q', read(_entry(read, leaves, b'd1777')['data'], 8))[0]
        else:
            obj_id = OBJID_ROOT
        l = _current(leaves, obj_id, RECTYPE_INODE)[0]
        ino = bytearray(read(l['data'], INODE_SIZE))
        if kind == 'dotdot':
            struct.pack_into('<Q', ino, INODE_PARENT, obj_id)
        else:
            ino[INODE_CAP_FLAGS] = (ino[INODE_CAP_FLAGS] & ~0x03) | 0x02  # DIRHASH_ALG2
        node = bytearray(read(l['node'], NODE_SIZE))
        struct.pack_into('<I', node, l['elm'] + 60, crc32c(bytes(ino[:INODE_CRCSIZE])))
        struct.pack_into('<I', node, 0, crc32c(bytes(node[4:])))
        return [(l['data'], bytes(ino)), (l['node'], bytes(node))]
    if kind == 'baddata':
        obj_id = struct.unpack('<Q', read(_entry(read, leaves, b'size1048577')['data'], 8))[0]
        rec = min(_current(leaves, obj_id, RECTYPE_DATA), key=lambda l: l['data'])
        spot = rec['data'] + rec['data_len'] // 2
        return [(spot, bytes([read(spot, 1)[0] ^ 0xFF]))]
    l = _entry(read, leaves, b'a')
    n = ENTRY_NAME_OFF + 256
    if l['data'] % BUFSIZE + n > BUFSIZE:
        raise ValueError('entry too close to its buffer end to stretch')
    node = bytearray(read(l['node'], NODE_SIZE))
    struct.pack_into('<II', node, l['elm'] + 56, n, crc32c(read(l['data'], n)))
    struct.pack_into('<I', node, 0, crc32c(bytes(node[4:])))
    return [(l['node'], bytes(node))]


def make_fixture_overlay(kind: str, wrapped: Path, out: Path) -> None:
    """make_fixture on a wrapped volume, as a qcow2 overlay of WRAPPED that
    holds only the changed sectors (dense copies need too much disk)."""
    if kind not in FIXTURE_KINDS:
        raise ValueError('unknown fixture kind %r' % kind)
    out = ext2_guest._new_target(out)
    with Path(wrapped).open('rb') as f:
        head = f.read(65536)
        off = next(o for o in range(0, len(head), 512) if head[o:o + 4] == b'dlV3')
        part = struct.unpack_from('>h', head, off + 112)[0] * \
            struct.unpack_from('>i', head, off + 92)[0]
        read = _reader(f, part)
        patches = []
        for poff, data in _fixture_patches(kind, read):
            lo, hi = poff - poff % 512, poff + len(data)
            hi += (-hi) % 512
            sectors = bytearray(read(lo, hi - lo))
            sectors[poff - lo:poff - lo + len(data)] = data
            patches.append((part + lo, bytes(sectors)))
    _overlay(wrapped, out)
    src = out.with_suffix('.hdr')
    try:
        for poff, sectors in patches:
            src.write_bytes(sectors)
            # qemu-io write -s reads its source in text mode on Windows; convert does not.
            subprocess.run([QEMU_IMG, 'convert', '-n', '-S', '0', '-f', 'raw', str(src),
                            '--target-image-opts',
                            'driver=raw,offset=%d,size=%d,file.driver=qcow2,'
                            'file.file.filename=%s' % (poff, len(sectors), out)],
                           check=True)
    finally:
        if src.exists():
            src.unlink()


def walk_differences(got, want, ignore_crc=True, ignore_mtime=False,
                     loose_crc=()):
    """hammer_walk output against a reference manifest.  With ignore_crc
    (hammer_walk -n) the content CRC column, field 9, is not compared;
    with ignore_mtime (trees made by a workload, not copied) field 8 is
    not either; paths in loose_crc have their CRC ignored.  Returns
    problem lines."""
    def norm(text):
        rows = []
        for line in text.splitlines():
            f = line.split('\t')
            if (ignore_crc or f[0] in loose_crc) and len(f) > 8:
                f[8] = '-'
            if ignore_mtime and len(f) > 7:
                f[7] = '-'
            rows.append('\t'.join(f))
        return rows
    g, w = norm(got), norm(want)
    problems = ['-' + r for r in sorted(set(w) - set(g))] + \
               ['+' + r for r in sorted(set(g) - set(w))]
    if not problems and len(g) != len(w):
        problems.append('line counts differ: %d vs %d' % (len(g), len(w)))
    return problems


CASES = ('refuse-badsig', 'refuse-v6', 'refuse-twovol', 'refuse-badcrc',
         'refuse-needs-recovery', 'rw-empty', 'ns-ops', 'data-ops', 'unlinked',
         'fsync-crash', 'fsync-check', 'refuse-rw-recovery',
         'refuse-rw-pfs', 'admit', 'namespace',
         'readdir-small', 'times', 'erofs', 'crafted-name', 'data', 'holes',
         'mmap', 'dedup', 'crafted-data', 'cycle', 'negread', 'crafted-count',
         'crafted-len', 'crafted-off', 'crafted-dotdot', 'crafted-dirhash')
# Cases that write the data volume: no unchanged check; the result is
# exported and checked on DragonFly instead (HAMMER_NO_DFLY=1 skips that).
WRITE_CASES = ('rw-empty', 'ns-ops', 'data-ops', 'unlinked', 'fsync-crash')
# Write cases that end without an unmount: nothing to check on the host
# (the next case, fsync-check, mounts what they left).
CRASH_CASES = ('fsync-crash',)
# Walks compared with a reference beside the base volume.  Workload cases
# name their reference (made by the same workload on DragonFly) and ignore
# mtimes; the others use <base volume>.walk.
WALK_CASES = ('namespace', 'data', 'dedup', 'ns-ops', 'data-ops')
WORKLOAD_WALKS = {'ns-ops': 'ns-ops.walk', 'data-ops': 'data-ops.walk'}
# A file written through MAP_SHARED: Rhapsody's VM need not have written
# those pages back by the remount (data_ops.c, verify-remount).
LOOSE_CRC = {'data-ops': ('./map',)}
# Files ending in a hole: hammer recover sizes them by their data.
RECOVER_SKIP = {'data-ops': ('trunc',)}
# Tools each case ships beside hammer_io.
CASE_TOOLS = {'ns-ops': ('ns_ops',), 'data-ops': ('data_ops',),
              'unlinked': ('data_ops',), 'fsync-crash': ('data_ops',),
              'fsync-check': ('data_ops', 'hammer')}
DFLY_ISO = os.environ.get(
    'DFLY_ISO', r'D:\RhapsodiOS\vm\work\dfly\iso\dfly-x86_64-6.4.2_REL.iso')
UNDO_FIRST = UNDO_MAP + 8
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


def header_problems(hdr: bytes):
    """A volume header our kernel left behind: sealed, UNDO FIFO empty."""
    problems = []
    if struct.unpack_from('<I', hdr, VOL_CRC)[0] and not volume_header_sealed(hdr):
        problems.append('volume header CRC does not verify')
    first, nxt = struct.unpack_from('<QQ', hdr, UNDO_FIRST)
    if first != nxt:
        problems.append('UNDO FIFO not empty: first %016x next %016x' % (first, nxt))
    return problems


def export_volume(data_ov: Path, outdir: Path) -> Path:
    """The case's data overlay as a raw HAMMER volume, OUTDIR/export.img."""
    wrapped = Path(outdir)/'export.wrapped'
    subprocess.run([QEMU_IMG, 'convert', '-q', '-f', 'qcow2', '-O', 'raw',
                    str(data_ov), str(wrapped)], check=True)
    raw = Path(outdir)/'export.img'
    try:
        unwrap_volume_file(wrapped, raw)
    finally:
        wrapped.unlink()
    return raw


def recover_differences(tree: str, rec: str, skip=()):
    """Regular files 'hammer recover' rebuilt, against the mounted tree.

    recover names files its own way and rebuilds a hard-linked file once,
    so files are compared as (size, content CRC) pairs.  It rebuilds only
    data below 1 MiB (HAMMER_XDEMARC) and sizes a file by its data, so
    larger files, and the names in SKIP (files ending in a hole), are not
    compared; the same holds on volumes DragonFly wrote itself.  Every
    other tree file must come back intact."""
    def files(text, limit):
        out = set()
        for line in text.splitlines():
            f = line.split('	')
            if len(f) > 8 and f[1] == 'f' and                (limit is None or (int(f[6]) < limit and
                                  f[0].rsplit('/', 1)[-1] not in skip)):
                out.add((f[6], f[8]))
        return out
    missing = files(tree, 1 << 20) - files(rec, None)
    if not missing:
        return []
    return ['recover: %d files under 1 MiB not rebuilt intact' % len(missing)]


def dfly_check(raw: Path, outdir: Path, recover_skip=()):
    """vm/dfly-check.sh on DragonFly against RAW; findings (empty = clean)."""
    import dfly_guest
    import fat32
    status, text = dfly_guest.run_script(
        DFLY_ISO, str(raw), (HERE/'dfly-check.sh').read_text(), Path(outdir),
        {'walk.c': (HERE.parent/'src/hammer-1/tests/hammer_walk.c').read_bytes()})
    if status != 0 or 'CHECK_OK' not in text:
        return ['DragonFly check failed (status %s)' % status] + \
            ['dfly: ' + l for l in text.splitlines()[-10:]]
    xfer = (Path(outdir)/'xfer.img').read_bytes()
    tree = fat32.read_file(xfer, 'TREE.WLK').decode('latin-1')
    rec = fat32.read_file(xfer, 'REC.WLK').decode('latin-1')
    (Path(outdir)/'tree.walk').write_text(tree)
    return recover_differences(tree, rec, recover_skip)


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
    writes = case in WRITE_CASES
    if case in ('namespace', 'data', 'dedup', 'cycle') or writes:
        nodes.append(N('/hammer_walk', 'reg', 0o100755, 0, 0, 0,
                       (Path(tools_dir)/'hammer_walk').read_bytes()))
    if writes:
        nodes.append(N('/hammer', 'reg', 0o100755, 0, 0, 0,
                       (Path(tools_dir)/'hammer').read_bytes()))
    for tool in CASE_TOOLS.get(case, ()):
        if tool == 'hammer' and writes:
            continue
        nodes.append(N('/' + tool, 'reg', 0o100755, 0, 0, 0,
                       (Path(tools_dir)/tool).read_bytes()))
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
        deadline = time.monotonic() + (14400 if case == 'cycle' else 1800)
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
                             writes or _unchanged(data_ov, volume))
    if writes and code == 0 and case not in CRASH_CASES:
        raw = export_volume(data_ov, outdir)
        try:
            with raw.open('rb') as f:
                problems += header_problems(f.read(HEADER))
            if not problems and os.environ.get('HAMMER_NO_DFLY') != '1':
                problems += dfly_check(raw, outdir/'dfly',
                                       RECOVER_SKIP.get(case, ()))
        finally:
            raw.unlink()
    if case in WALK_CASES and code == 0:
        # The reference manifest sits beside the base volume (ref-main.walk).
        import gzip
        import rhap_image
        with rhap_image.Image(str(results)) as disk:
            walk = gzip.decompress(disk.read_file(disk.inode(disk.resolve('/walk.gz'))))
        (outdir/'walk.txt').write_bytes(walk)
        base = Path(volume)
        while base.suffix in ('.qcow2', '.wrapped'):
            base = base.with_suffix('')
        ref = base.parent/WORKLOAD_WALKS[case] if case in WORKLOAD_WALKS \
            else base.with_suffix('.walk')
        diff = walk_differences(walk.decode('utf-8', 'replace'), ref.read_text(),
                                ignore_crc=(case in ('namespace', 'ns-ops')),
                                ignore_mtime=case in WORKLOAD_WALKS,
                                loose_crc=LOOSE_CRC.get(case, ()))
        problems += ['walk: ' + d for d in diff[:20]]
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
    if len(argv) == 4 and argv[1] == 'dfly-check':
        problems = dfly_check(Path(argv[2]), Path(argv[3]))
        for problem in problems:
            print(problem)
        return int(bool(problems))
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
