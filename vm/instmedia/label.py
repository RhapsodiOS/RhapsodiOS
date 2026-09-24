"""NeXT dlV3 disk labels, as `disk -i` writes them.

Layout from src/kernel-7/bsd/dev/disk_label.h and sys/disktab.h, big-endian
and packed the way the m68k compiler packed it (no padding before an int).
Only partition a is used; the other seven entries hold the pattern disk -i
leaves in them.  Checked byte for byte against golden.img's label and the DR2
install floppy's.
"""
import struct

import ufs_build

LABEL_SIZE = 1024       # bytes per copy; only the first 560 are ever non-zero
DISK_COPIES = (15, 30, 45)
# A CD needs the copy at 0 too: the kernel reads it in 2048-byte blocks, and
# the others are not on a 2048-byte boundary.
CD_COPIES = (0, 15, 30, 45)

_PART_OFF = 190
_PART_SIZE = 46
_NPART = 8
_UNUSED_PART = b"\xff" * 12 + b"\0\0" + b"\xff" * 5 + b"\0" * 27


class LabelError(Exception):
    pass


def _cstr(text, size):
    raw = text.encode("ascii")
    if len(raw) >= size:
        raise LabelError("%r does not fit in %d bytes with its NUL"
                         % (text, size))
    return raw.ljust(size, b"\0")


def label(secsize, ntracks, nsectors, ncylinders, rpm, front, p_base, p_size,
          bsize, fsize, cpg, density, minfree, name, d_name, d_type,
          boot0=(-1, -1), tag=0):
    """One label copy, checksummed, with dl_label_blkno still 0.

    p_base and front are in secsize sectors, and on an fdisk disk p_base is
    absolute (it includes the 0xA7 partition's start), as disk -i -b writes
    it.  boot0 is d_boot0_blkno; (-1, -1) says there are no boot blocks.
    """
    buf = bytearray(LABEL_SIZE)
    struct.pack_into(">4sii24sII", buf, 0, b"dlV3", 0, 0, _cstr(name, 24),
                     0, tag)
    struct.pack_into(">24s24s5i6h2i24s32scc", buf, 44,
                     _cstr(d_name, 24), _cstr(d_type, 24),
                     secsize, ntracks, nsectors, ncylinders, rpm,
                     front, 0, 0, 0, 0, 0, boot0[0], boot0[1],
                     _cstr("mach_kernel", 24), _cstr("localhost", 32),
                     b"a", b"b")
    struct.pack_into(">iihhcxhhbb16sb8sx", buf, _PART_OFF,
                     p_base, p_size, bsize, fsize, b"t", cpg, density,
                     minfree, 1, b"", 1, _cstr("4.4BSD", 8))
    for n in range(1, _NPART):
        off = _PART_OFF + n * _PART_SIZE
        buf[off:off + _PART_SIZE] = _UNUSED_PART
    struct.pack_into(">H", buf, ufs_build.LABEL_CHECKSUM,
                     ufs_build.label_checksum(buf))
    return bytes(buf)


def for_filesystem(g, front, p_base, ncylinders, name, d_type):
    """The label for a filesystem of ufs_geometry g, as disk -i would write
    it after newfs: partition a covers g.fssize sectors from p_base, and
    carries g's block, fragment and cylinder-group sizes, newfs's default
    density and g's minfree.  No boot blocks."""
    return label(secsize=g.secsize, ntracks=g.ntrak, nsectors=g.nsect,
                 ncylinders=ncylinders, rpm=g.rpm, front=front,
                 p_base=p_base, p_size=g.fssize, bsize=g.bsize,
                 fsize=g.fsize, cpg=g.cpg, density=4 * g.fsize,
                 minfree=g.minfree, name=name, d_name=name, d_type=d_type)


def place(f, lbl, copies, relsect=0):
    """Write lbl at each copy's 512-byte block, counted from relsect.

    check_label only accepts a copy whose dl_label_blkno is the physical
    block it was read from, so each copy gets its own; the checksum does not
    cover that field.
    """
    for blk in copies:
        buf = bytearray(lbl)
        struct.pack_into(">i", buf, 4, relsect + blk)
        f.seek((relsect + blk) * 512)
        f.write(buf)
