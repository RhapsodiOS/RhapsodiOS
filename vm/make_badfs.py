"""Build small UFS images and corrupt one superblock field, for kernel
mount-refusal testing. Writes only to caller-named paths; never touches
golden.img or vm/work/test.img."""

import os
import struct

import rhap_image
import ufs_build
import ufs_cg
import ufs_extract

TEMPLATE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "install", "rhapsody_dr2_x86_InstallationFloppy.img")

# offset within the superblock, struct format
FIELDS = {
    "fs_clean": (209, "<b"),
    "fs_magic": (1372, "<I"),
    "fs_maxfilesize": (1328, "<Q"),
}


def build_good(out_path, pad=0):
    """Write a minimal single-cylinder-group UFS image with a clean
    superblock.  pad appends that many zero bytes past the filesystem: room
    a host can write without touching it."""
    nodes = [ufs_extract.Node("/", "dir", 0o040755, 0, 0, 0, None)]
    data = ufs_build.build(TEMPLATE, nodes)
    with open(out_path, "wb") as f:
        f.write(data)
        f.write(bytes(pad))
    _poke(out_path, "fs_clean", 1)


def corrupt(out_path, field, value):
    """Overwrite one superblock field in an existing image."""
    _check_field(field)
    _poke(out_path, field, value)


def field_offset(path, field):
    """Absolute byte offset of a superblock field in an image."""
    _check_field(field)
    return _read_partition_start(path) + rhap_image.SBOFF + FIELDS[field][0]


def read_field(path, field):
    """The value of a superblock field."""
    fmt = FIELDS[field][1]
    with open(path, "rb") as f:
        f.seek(field_offset(path, field))
        return struct.unpack(fmt, f.read(struct.calcsize(fmt)))[0]


def reload_sectors(path):
    """First 512-byte sector, counted from the start of the image, of each
    disk read ffs_reload makes: the superblock (its Step 2), the
    cylinder-group summary (Step 3) and the inode block holding the root
    inode (Step 6).  blkdebug's sector= option takes exactly this unit."""
    g = ufs_cg.read_geometry(path)
    base = _read_partition_start(path) // 512
    per_frag = g.fsize // 512
    # ino_to_fsba(fs, 2) is cgimin(fs, 0) + (2 % ipg) / inopb blocks;
    # cgstart(fs, 0) is 0 and inopb exceeds 2, so that is fs_iblkno
    return {
        "superblock": base + rhap_image.SBOFF // 512,
        "csum": base + g.csaddr * per_frag,
        "inode2": base + g.iblkno * per_frag,
    }


def _check_field(field):
    if field not in FIELDS:
        raise ValueError("unknown field %r; known: %s"
                         % (field, ", ".join(sorted(FIELDS))))


def _poke(out_path, field, value):
    fmt = FIELDS[field][1]
    offset = field_offset(out_path, field)
    with open(out_path, "r+b") as f:
        f.seek(offset)
        f.write(struct.pack(fmt, value))


def _read_partition_start(out_path):
    """Read partition start offset by parsing the disk label directly.

    This mirrors the logic from rhap_image.Image._read_label() and computes
    the offset without validating the superblock magic. Used by corrupt()
    which may be invoked after the magic has been intentionally corrupted.
    """
    with open(out_path, "rb") as f:
        for label_off in rhap_image.LABEL_OFFSETS:
            f.seek(label_off)
            if f.read(4) == rhap_image.LABEL_MAGIC:
                f.seek(label_off + 92)
                secsize = struct.unpack(">i", f.read(4))[0]
                f.seek(label_off + 112)
                front = struct.unpack(">h", f.read(2))[0]
                f.seek(label_off + 190)
                p_base = struct.unpack(">i", f.read(4))[0]
                return (front + p_base) * secsize
    raise ValueError("no NeXT disk label found in %s" % out_path)
