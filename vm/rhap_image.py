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

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()


NDADDR = 12
NIADDR = 3


class Inode(object):
    def __init__(self, ino, buf):
        self.ino = ino
        self.mode, self.nlink = struct.unpack_from("<Hh", buf, 0)
        self.size = struct.unpack_from("<Q", buf, 8)[0]
        self.mtime = struct.unpack_from("<i", buf, 24)[0]
        self.db = list(struct.unpack_from("<%di" % NDADDR, buf, 40))
        self.ib = list(struct.unpack_from("<%di" % NIADDR, buf, 88))
        self.blocks = struct.unpack_from("<i", buf, 104)[0]

    def is_dir(self):
        return (self.mode & 0o170000) == 0o040000

    def is_reg(self):
        return (self.mode & 0o170000) == 0o100000


def _cgstart(img, c):
    return img.fpg * c + img.cgoffset * (c & ~img.cgmask)


def _inode_location(img, ino):
    cg = ino // img.ipg
    off = ino % img.ipg
    frag = _cgstart(img, cg) + img.iblkno + (off // img.inopb) * img.frag
    return frag, (off % img.inopb) * DINODE_SIZE


def _inode(self, ino):
    frag, entry = _inode_location(self, ino)
    blk = self.read_frag(frag, self.bsize)
    return Inode(ino, blk[entry:entry + DINODE_SIZE])


def _frags(self, inode):
    """Fragment numbers covering the file.  Holes appear as 0."""
    need = (inode.size + self.fsize - 1) // self.fsize
    out = []

    def take(frag_of_block):
        # A block covers fs_frag fragments with consecutive numbers.
        for k in range(self.frag):
            if len(out) >= need:
                return
            out.append(frag_of_block + k if frag_of_block else 0)

    for b in inode.db:
        if len(out) >= need:
            break
        take(b)

    if len(out) < need and inode.ib[0]:
        ind = self.read_frag(inode.ib[0], self.bsize)
        for b in struct.unpack_from("<%di" % self.nindir, ind, 0):
            if len(out) >= need:
                break
            take(b)

    if len(out) < need and inode.ib[1]:
        l1 = self.read_frag(inode.ib[1], self.bsize)
        for b1 in struct.unpack_from("<%di" % self.nindir, l1, 0):
            if len(out) >= need or not b1:
                break
            l2 = self.read_frag(b1, self.bsize)
            for b in struct.unpack_from("<%di" % self.nindir, l2, 0):
                if len(out) >= need:
                    break
                take(b)

    return out[:need]


def _read_file(self, ino):
    inode = self.inode(ino) if isinstance(ino, int) else ino
    buf = bytearray()
    for f in self.frags(inode):
        buf += self.read_frag(f, self.fsize) if f else bytes(self.fsize)
    return bytes(buf[:inode.size])


def _iter_dir(self, ino):
    data = self.read_file(ino)
    p = 0
    while p < len(data):
        d_ino, d_reclen = struct.unpack_from("<IH", data, p)
        d_type = data[p + 6]
        d_namlen = data[p + 7]
        if d_reclen == 0:
            break
        if d_ino:
            name = data[p + 8:p + 8 + d_namlen].decode("ascii", "replace")
            yield name, d_ino, d_type, p
        p += d_reclen


def _listdir(self, path):
    ino = self.resolve(path)
    if ino is None:
        raise FileNotFoundError(path)
    return [(n, i, t) for n, i, t, _ in self.iter_dir(ino)]


def _lookup(self, dir_ino, name):
    for n, i, _t, _off in self.iter_dir(dir_ino):
        if n == name:
            return i
    return None


def _resolve(self, path):
    ino = 2
    for part in path.strip("/").split("/"):
        if not part:
            continue
        ino = self.lookup(ino, part)
        if ino is None:
            return None
    return ino


def _max_writable(self, ino):
    """Bytes that may be overwritten in place.

    Rounded up to a fragment because FFS packs several files' tails into one
    block: writing past this file's own fragment count would corrupt an
    unrelated file.
    """
    inode = self.inode(ino) if isinstance(ino, int) else ino
    return ((inode.size + self.fsize - 1) // self.fsize) * self.fsize


Image.inode = _inode
Image.frags = _frags
Image.read_file = _read_file
Image.iter_dir = _iter_dir
Image.listdir = _listdir
Image.lookup = _lookup
Image.resolve = _resolve
Image.max_writable = _max_writable
