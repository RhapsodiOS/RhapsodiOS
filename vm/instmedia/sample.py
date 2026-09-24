"""The two images phase 3 is checked with, holding a tree of every node kind.

    python -m instmedia.sample OUTDIR

writes OUTDIR/fdisk512.img, a disk with an MBR whose one 0xA7 partition
starts at LBA 2048 and holds a label with secsize 512 (what disk -i writes
on an fdisk disk), and OUTDIR/cd2048.img, a whole-medium label with secsize
2048 and fsize 2048, laid out like the DR2 CD.  Both filesystems have
several cylinder groups, and the tree is sized from the geometry so that
its inodes spill out of group 0 and one file needs double indirect blocks
and crosses a group boundary.
"""
import os
import struct
import sys

from ufs_extract import Node
from instmedia import label, ufs, ufs_geometry

NOW = 946684800             # 2000-01-01; nothing depends on the host clock
FRONT_BYTES = 160 * 1024    # front porch, the size golden.img's has
FDISK_RELSECT = 2048


def tree(g):
    """The sample tree for a filesystem of geometry g."""
    t = NOW - 86400
    big_blocks = max(ufs_geometry.NDADDR + g.nindir + 1,
                     g.fpg // g.frag + 1)
    big = b"".join(struct.pack("<I", i) * (g.bsize // 4)
                   for i in range(big_blocks)) + b"tail" * 25
    nodes = [
        Node("/", "dir", 0o755, 0, 0, t, None),
        Node("/bin", "dir", 0o755, 0, 0, t + 1, None),
        Node("/bin/sh", "reg", 0o555, 0, 0, t + 2,
             bytes(range(256)) * 11 + b"end"),
        Node("/bin/sh-again", "hlink", 0, 0, 0, 0, "/bin/sh"),
        Node("/etc", "dir", 0o755, 0, 0, t + 3, None),
        Node("/etc/motd", "reg", 0o644, 501, 20, t + 4,
             b"Welcome to RhapsodiOS.\n"),
        Node("/etc/empty", "reg", 0o600, 0, 0, t + 5, b""),
        Node("/etc/fast-link", "lnk", 0o755, 0, 0, t + 6, "../bin/sh"),
        Node("/etc/slow-link", "lnk", 0o755, 0, 0, t + 7,
             "/" + "/".join(["a-long-directory-name"] * 4)),
        Node("/dev", "dir", 0o755, 0, 0, t + 8, None),
        Node("/dev/rhd1a", "chr", 0o640, 0, 5, t + 9, (15, 8)),
        Node("/dev/hd1a", "blk", 0o640, 0, 5, t + 10, (3, 8)),
        Node("/dev/hd1a-again", "hlink", 0, 0, 0, 0, "/dev/hd1a"),
        Node("/big", "reg", 0o644, 0, 0, t + 11, big),
        Node("/many", "dir", 0o755, 0, 0, t + 12, None),
    ]
    nodes += [Node("/many/f%05d" % i, "reg", 0o644, 0, 0, t + 13, b"")
              for i in range(g.ipg)]
    return nodes


def fdisk_disk(path, now=NOW):
    """64 MB of UFS in an 0xA7 partition; returns (geometry, nodes)."""
    g = ufs_geometry.geometry(fssize=131072, secsize=512, nsect=63,
                              ntrak=16, rpm=3600)
    nodes = tree(g)
    front = FRONT_BYTES // 512
    nsect = front + g.fssize
    total = FDISK_RELSECT + nsect
    lbl = label.for_filesystem(g, front=front, p_base=FDISK_RELSECT,
                               ncylinders=total // g.spc,
                               name="instmedia sample", d_type="fixed_rw_ide")
    # The kernel and rhap_image read only an entry's type and start.
    mbr = bytearray(512)
    struct.pack_into("<B3sB3sII", mbr, 446, 0, b"", 0xA7, b"",
                     FDISK_RELSECT, nsect)
    mbr[510:512] = b"\x55\xaa"
    with open(path, "wb") as f:
        f.truncate(total * 512)
        f.write(mbr)
        label.place(f, lbl, label.DISK_COPIES, FDISK_RELSECT)
        ufs.write(f, (FDISK_RELSECT + front) * 512, g, nodes, now)
    return g, nodes


def cd_volume(path, now=NOW):
    """256 MB of UFS with fsize 2048 under a CD-style label."""
    g = ufs_geometry.geometry(fssize=131072, secsize=2048, nsect=64,
                              ntrak=32, rpm=300, fsize=2048)
    nodes = tree(g)
    front = FRONT_BYTES // 2048
    total = front + g.fssize
    lbl = label.for_filesystem(g, front=front, p_base=0,
                               ncylinders=ufs_geometry.howmany(total, g.spc),
                               name="instmedia sample",
                               d_type="removable_rw_scsi")
    with open(path, "wb") as f:
        f.truncate(total * 2048)
        label.place(f, lbl, label.CD_COPIES)
        ufs.write(f, front * 2048, g, nodes, now)
    return g, nodes


def main(argv):
    if len(argv) != 2:
        print("usage: python -m instmedia.sample OUTDIR")
        return 2
    os.makedirs(argv[1], exist_ok=True)
    for name, build in (("fdisk512.img", fdisk_disk),
                        ("cd2048.img", cd_volume)):
        path = os.path.join(argv[1], name)
        build(path)
        print("wrote %s" % path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
