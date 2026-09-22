"""Build small UFS images and corrupt one superblock field, for kernel
mount-refusal testing. Writes only to caller-named paths; never touches
golden.img or vm/work/test.img."""

import os
import struct

import rhap_image
import ufs_build
import ufs_extract

TEMPLATE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "install", "rhapsody_dr2_x86_InstallationFloppy.img")

# offset, struct format
FIELDS = {
    "fs_fsize": (52, "<i"),
    "fs_clean": (209, "<b"),
    "fs_magic": (1372, "<I"),
}


def build_good(out_path):
    """Write a minimal single-cylinder-group UFS image with a clean superblock."""
    nodes = [ufs_extract.Node("/", "dir", 0o040755, 0, 0, 0, None)]
    data = ufs_build.build(TEMPLATE, nodes)
    with open(out_path, "wb") as f:
        f.write(data)
    _poke(out_path, "fs_clean", 1)


def corrupt(out_path, field, value):
    """Overwrite one superblock field in an existing image."""
    if field not in FIELDS:
        raise ValueError("unknown field %r; known: %s"
                         % (field, ", ".join(sorted(FIELDS))))
    _poke(out_path, field, value)


def _poke(out_path, field, value):
    offset, fmt = FIELDS[field]
    # Compute partition offset by parsing disk label directly.
    # rhap_image.Image() validates the superblock magic, which is the very
    # thing corrupt() is allowed to destroy; we need independent offset math
    # to work after the magic has been corrupted.
    sb_off = _read_partition_start(out_path) + rhap_image.SBOFF
    with open(out_path, "r+b") as f:
        f.seek(sb_off + offset)
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
