"""HAMMER test volumes: NeXT-labelled wrapping, header fixtures, guest runs.

Usage: hammer_guest.py wrap VOLUME OUT
       hammer_guest.py unwrap WRAPPED OUT
       hammer_guest.py fixture KIND VOLUME OUT
Volumes are raw HAMMER images (what DragonFly's newfs_hammer writes to a
whole disk).  Rhapsody sees them as partition a of a NeXT-labelled disk.
"""
from pathlib import Path
import shutil
import struct
import sys

import ext2_guest
import ufs_build

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
        if kind == 'badcrc':
            hdr[VOL_LABEL] ^= 0xFF
        else:
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
        f.seek(0)
        f.write(hdr)


def main(argv):
    if len(argv) == 4 and argv[1] == 'wrap':
        wrap_volume_file(argv[2], argv[3])
        return 0
    if len(argv) == 4 and argv[1] == 'unwrap':
        unwrap_volume_file(argv[2], argv[3])
        return 0
    if len(argv) == 5 and argv[1] == 'fixture':
        make_fixture(argv[2], argv[3], argv[4])
        return 0
    raise ValueError(__doc__)


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv))
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
