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
    img = rhap_image.Image(out_path)
    sb_off = img.part_start + rhap_image.SBOFF
    img.close()
    with open(out_path, "r+b") as f:
        f.seek(sb_off + offset)
        f.write(struct.pack(fmt, value))
