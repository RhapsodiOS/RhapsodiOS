"""Read-only reader for the Rhapsody DR2 disk image.

The disk is mixed-endian: the NeXT disk label is big-endian, the UFS
filesystem inside it is little-endian.  Offsets here were measured against
vm/rhapsody.vmdk, cross-validated by p_size == fs_size.

Label layout follows src/kernel-7/bsd/dev/disk_label.h and
src/kernel-7/bsd/sys/disktab.h; the partition-start formula is what the boot
loader computes at src/boot-2/i386/libsaio/disk.c:381.
"""

import struct

LABEL_OFFSETS = (7680, 15360, 23040, 30720)
LABEL_MAGIC = b"dlV3"

FS_MAGIC = 0x011954
SBOFF = 8192
MAGIC_OFF = 1372
DINODE_SIZE = 128


def _cstr(buf):
    return buf.split(b"\0", 1)[0].decode("ascii", "replace")


class Image(object):
    def __init__(self, path, writable=False):
        self.path = path
        self._f = open(path, "r+b" if writable else "rb")
        self.label = self._read_label()
        self.part_start = (self.label["front"] + self.label["p_base"]) * self.label[
            "secsize"
        ]
        self._read_superblock()

    def close(self):
        self._f.close()

    def _read_at(self, offset, n):
        self._f.seek(offset)
        return self._f.read(n)

    def _read_label(self):
        for off in LABEL_OFFSETS:
            buf = self._read_at(off, 1024)
            if buf[:4] == LABEL_MAGIC:
                self.label_offset = off
                return {
                    "blkno": struct.unpack_from(">i", buf, 4)[0],
                    "secsize": struct.unpack_from(">i", buf, 92)[0],
                    "front": struct.unpack_from(">h", buf, 112)[0],
                    "bootfile": _cstr(buf[132:156]),
                    "rootpartition": chr(buf[188]),
                    "p_base": struct.unpack_from(">i", buf, 190)[0],
                    "p_size": struct.unpack_from(">i", buf, 194)[0],
                }
        raise ValueError("no NeXT disk label found in %s" % self.path)

    def _read_superblock(self):
        sb = self._read_at(self.part_start + SBOFF, SBOFF)
        magic = struct.unpack_from("<i", sb, MAGIC_OFF)[0]
        if magic != FS_MAGIC:
            raise ValueError("bad UFS magic 0x%x at %d" % (magic, self.part_start + SBOFF))
        g = lambda o: struct.unpack_from("<i", sb, o)[0]
        self.iblkno = g(16)
        self.cgoffset = g(24)
        self.cgmask = g(28)
        self.fs_size = g(36)
        self.ncg = g(44)
        self.bsize = g(48)
        self.fsize = g(52)
        self.frag = g(56)
        self.nindir = g(116)
        self.inopb = g(120)
        self.ipg = g(184)
        self.fpg = g(188)
        self.fsmnt = _cstr(sb[212:212 + 512])

    def frag_offset(self, frag_no):
        """Byte offset of a fragment.  fs_fsbtodb is 0 on this filesystem."""
        return self.part_start + frag_no * self.fsize

    def read_frag(self, frag_no, nbytes):
        return self._read_at(self.frag_offset(frag_no), nbytes)
