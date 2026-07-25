"""In-place writer for the Rhapsody disk image.

Never allocates.  Only the contents of already-mapped fragments and di_size
are ever modified; di_mtime is preserved rather than advanced (write_file's
default mtime=None writes the old value back).  This module does not touch
directory entries or link counts (d_ino, di_nlink) at all; the sacrificial-
inode graft that does is a separate, later addition with its own
justification.  Every refusal raises SafetyError rather than writing
something questionable.
"""

import os
import struct

import rhap_image


class SafetyError(Exception):
    pass


def check_target(image_path):
    """Refuse to write anything but vm/work/test.img.

    Both sides are resolved with os.path.realpath (follows symlinks and
    Windows junctions/hardlinks) and normalised with os.path.normcase (folds
    case and separators on Windows) before comparison. This is canonical-path
    equality, not a suffix match: an unrelated directory that merely ends in
    "work/test.img" is refused, and a differently-spelled path to the real
    file (mixed separators, redundant "." or ".." components, different case)
    is accepted.

    As a second, independent check, the resolved target is also refused if it
    is the same underlying file as golden.img or rhapsody.vmdk (e.g. reached
    via a link), even though its path resolved to the expected location.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    canonical_target = os.path.normcase(
        os.path.realpath(os.path.join(here, "work", "test.img"))
    )
    resolved = os.path.normcase(os.path.realpath(image_path))
    if resolved != canonical_target:
        raise SafetyError(
            "refusing to write %s; only vm/work/test.img may be modified" % image_path
        )

    for name in ("golden.img", "rhapsody.vmdk"):
        protected = os.path.join(here, name)
        if not os.path.exists(protected) or not os.path.exists(image_path):
            continue
        try:
            if os.path.samefile(image_path, protected):
                raise SafetyError(
                    "refusing to write %s; it is the same file as %s"
                    % (image_path, protected)
                )
        except OSError:
            pass
    return True


def _write_inode_fields(img, ino, size=None, mtime=None, nlink=None):
    check_target(img.path)
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
    already-allocated fragments, if the payload would change the file's
    fragment count, or if the file has holes.
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

    current_frags = (inode.size + img.fsize - 1) // img.fsize
    new_frags = (len(data) + img.fsize - 1) // img.fsize
    if new_frags != current_frags:
        raise SafetyError(
            "%s: payload needs %d fragment(s) but the file currently occupies "
            "%d fragment(s); writes that change fragment count are refused"
            % (path, new_frags, current_frags)
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


def _replace_table_key(text, key, value):
    """Pure parse/replace step for set_table_key.

    Takes the raw table file contents and returns (old_value, updated_text).
    Raises SafetyError on anything that is not a single, unambiguous,
    well-formed entry: a missing key, a duplicated key (ambiguous - a human
    should look at it), a value containing an escaped quote (this tool never
    needs to write one, so it refuses rather than mis-locating the terminator),
    or an entry not terminated by '";' immediately after the closing quote.
    """
    needle = b'"%s" = "' % key.encode()
    count = text.count(needle)
    if count == 0:
        raise SafetyError("key %r not present" % (key,))
    if count > 1:
        raise SafetyError(
            "key %r appears %d times; ambiguous table entry" % (key, count)
        )
    start = text.find(needle)
    vstart = start + len(needle)
    vend = text.find(b'"', vstart)
    if vend < 0:
        raise SafetyError("malformed entry for %r: no closing quote found" % (key,))
    if text[vend - 1:vend] == b"\\":
        raise SafetyError(
            "malformed entry for %r: value contains an escaped quote" % (key,)
        )
    if text[vend:vend + 2] != b'";':
        raise SafetyError(
            "malformed entry for %r: entry not terminated by \";" % (key,)
        )
    old_value = text[vstart:vend].decode()
    updated = text[:vstart] + value.encode() + text[vend:]
    return old_value, updated


def set_table_key(img, path, key, value):
    """Rewrite one "key" = "value"; line in a DriverKit config table."""
    ino = img.resolve(path)
    if ino is None:
        raise SafetyError("%s does not exist" % path)
    text = img.read_file(ino)
    try:
        old_value, updated = _replace_table_key(text, key, value)
    except SafetyError as e:
        raise SafetyError("%s: %s" % (path, e))
    write_file(img, path, updated)
    return old_value, value


def _find_dirent(img, dir_ino, name):
    """Byte offset of a directory entry's d_ino field within the directory."""
    for n, ino, _t, off in img.iter_dir(dir_ino):
        if n == name:
            return off, ino
    return None, None


def graft_file(img, target_path, donor_path, data, mtime=None):
    """Point target_path at donor_path's inode, after filling it with data.

    Used when data is too large for target_path's own allocation.  Performs no
    allocation: the donor's existing blocks are overwritten, its di_size is set,
    its di_nlink is bumped so the extra name is a legitimate hard link, and the
    target's directory entry d_ino is repointed.

    This does not go through write_file: write_file refuses any write that
    would change a file's fragment count, but grafting always changes the
    donor's effective size (that's the point), so it does its own bounds and
    hole checks directly against the donor's existing fragments instead.

    Known inconsistency: this leaves di_blocks unchanged while di_size now
    reflects only the payload, even though all of the donor's original blocks
    remain allocated and referenced by its inode. fsck would flag that
    mismatch. There is no allocator here to free the unused blocks, and
    working around that would require building one - out of scope for this
    tool. It is acceptable because vm/work/test.img is a disposable scratch
    image recreated by reset-image.cmd, never anything durable.
    """
    check_target(img.path)

    donor_ino = img.resolve(donor_path)
    if donor_ino is None:
        raise SafetyError("donor %s does not exist" % donor_path)
    donor = img.inode(donor_ino)
    if not donor.is_reg():
        raise SafetyError("donor %s is not a regular file" % donor_path)

    limit = img.max_writable(donor)
    if len(data) > limit:
        raise SafetyError(
            "donor %s holds %d bytes; payload is %d" % (donor_path, limit, len(data))
        )
    frags = img.frags(donor)
    if any(f == 0 for f in frags):
        raise SafetyError("donor %s has holes; refusing" % donor_path)

    parent = "/" + target_path.strip("/").rsplit("/", 1)[0] if "/" in target_path.strip("/") else "/"
    leaf = target_path.strip("/").rsplit("/", 1)[-1]
    parent_ino = img.resolve(parent)
    if parent_ino is None:
        raise SafetyError("parent of %s does not exist" % target_path)
    ent_off, old_ino = _find_dirent(img, parent_ino, leaf)
    if ent_off is None:
        raise SafetyError("%s does not exist; graft cannot create names" % target_path)
    if old_ino == donor_ino:
        raise SafetyError("%s already points at the donor inode" % target_path)

    # 1. Fill the donor's blocks.
    payload = bytearray(data)
    need = (len(payload) + img.fsize - 1) // img.fsize
    payload += bytes(need * img.fsize - len(payload))
    for i in range(need):
        img._f.seek(img.frag_offset(frags[i]))
        img._f.write(bytes(payload[i * img.fsize:(i + 1) * img.fsize]))
    img._f.flush()

    # 2. Set the donor's size and link count.
    _write_inode_fields(img, donor_ino, size=len(data),
                        mtime=mtime if mtime is not None else donor.mtime,
                        nlink=max(2, donor.nlink + 1))

    # 3. Repoint the target's directory entry (4 bytes).
    dir_frags = img.frags(img.inode(parent_ino))
    frag_index = ent_off // img.fsize
    within = ent_off % img.fsize
    img._f.seek(img.frag_offset(dir_frags[frag_index]) + within)
    img._f.write(struct.pack("<I", donor_ino))
    img._f.flush()

    check = rhap_image.Image(img.path)
    try:
        if check.resolve(target_path) != donor_ino:
            raise SafetyError("%s: repoint did not take" % target_path)
        if check.read_file(donor_ino) != data:
            raise SafetyError("%s: read-back mismatch after graft" % target_path)
    finally:
        check.close()

    return donor_ino


def main(argv):
    if len(argv) < 3:
        print("usage: rhap_inject.py <image> set-key <path> <key> <value>")
        print("       rhap_inject.py <image> put <path> <local-file>")
        return 2
    image, cmd = argv[1], argv[2]
    img = rhap_image.Image(image, writable=True)
    try:
        if cmd == "set-key":
            path, key, value = argv[3], argv[4], argv[5]
            old, new = set_table_key(img, path, key, value)
            print("%s: %r %r -> %r" % (path, key, old, new))
        elif cmd == "put":
            path, local = argv[3], argv[4]
            with open(local, "rb") as fh:
                data = fh.read()
            n = write_file(img, path, data)
            print("%s: wrote %d bytes" % (path, n))
        else:
            print("unknown command: %s" % cmd)
            return 2
    finally:
        img.close()
    return 0


if __name__ == "__main__":
    import sys
    raise SystemExit(main(sys.argv))
