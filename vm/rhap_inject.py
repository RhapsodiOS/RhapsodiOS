"""In-place writer for the Rhapsody disk image.

Never allocates.  Only the contents of already-mapped fragments, di_size,
di_mtime, d_ino and di_nlink are ever modified.  Every refusal raises
SafetyError rather than writing something questionable.
"""

import os
import struct

import rhap_image


class SafetyError(Exception):
    pass


def check_target(image_path):
    """Refuse to write anything but vm/work/test.img."""
    norm = os.path.normpath(os.path.abspath(image_path)).replace("\\", "/")
    if not norm.endswith("/work/test.img"):
        raise SafetyError(
            "refusing to write %s; only vm/work/test.img may be modified" % image_path
        )
    return True


def _write_inode_fields(img, ino, size=None, mtime=None, nlink=None):
    frag, entry = rhap_image._inode_location(img, ino)
    off = img.frag_offset(frag) + entry
    img._f.seek(off)
    buf = bytearray(img._f.read(rhap_image.DINODE_SIZE))
    if size is not None:
        struct.pack_into("<Q", buf, 8, size)
    if mtime is not None:
        struct.pack_into("<i", buf, 24, mtime)
    if nlink is not None:
        struct.pack_into("<h", buf, 2, nlink)
    img._f.seek(off)
    img._f.write(bytes(buf))
    img._f.flush()


def write_file(img, path, data, mtime=None):
    """Overwrite an existing file in place.

    Refuses if the path does not exist, if the payload exceeds the file's
    already-allocated fragments, or if the file has holes.
    """
    check_target(img.path)

    ino = img.resolve(path)
    if ino is None:
        raise SafetyError("%s does not exist; this writer cannot create files" % path)

    inode = img.inode(ino)
    if not inode.is_reg():
        raise SafetyError("%s is not a regular file" % path)

    limit = img.max_writable(inode)
    if len(data) > limit:
        raise SafetyError(
            "%s: payload %d bytes exceeds allocated %d bytes (slack %d)"
            % (path, len(data), limit, limit - inode.size)
        )

    frags = img.frags(inode)
    if any(f == 0 for f in frags):
        raise SafetyError("%s has holes; refusing in-place write" % path)

    # The new content may need fewer fragments than the old; only write what
    # we have, then shrink di_size.
    payload = bytearray(data)
    need = (len(payload) + img.fsize - 1) // img.fsize
    payload += bytes(need * img.fsize - len(payload))

    for i in range(need):
        img._f.seek(img.frag_offset(frags[i]))
        img._f.write(bytes(payload[i * img.fsize:(i + 1) * img.fsize]))
    img._f.flush()

    _write_inode_fields(img, ino, size=len(data),
                        mtime=mtime if mtime is not None else inode.mtime)

    # Read-back verification through the same parser.  This cannot catch a bug
    # shared by reader and writer; the independent check is the guest booting.
    check = rhap_image.Image(img.path)
    try:
        got = check.read_file(check.resolve(path))
    finally:
        check.close()
    if got != data:
        raise SafetyError("%s: read-back mismatch after write" % path)

    return len(data)
