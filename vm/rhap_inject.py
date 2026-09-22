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
import sys

import rhap_image


class SafetyError(Exception):
    pass


def check_target(image_path):
    """Refuse to write anything but vm/work/test.img, or the image named by
    the RHAP_TEST_IMAGE environment variable, if set.

    Both sides are resolved with os.path.realpath (follows symlinks and
    Windows junctions/hardlinks) and normalised with os.path.normcase (folds
    case and separators on Windows) before comparison. This is canonical-path
    equality, not a suffix match: an unrelated directory that merely ends in
    "work/test.img" is refused, and a differently-spelled path to the real
    file (mixed separators, redundant "." or ".." components, different case)
    is accepted.

    RHAP_TEST_IMAGE is an opt-in per-session override letting concurrent
    sessions each use their own working image instead of contending for the
    shared vm/work/test.img; unset, behaviour is unchanged. The override
    cannot be used to authorise golden.img or rhapsody.vmdk: if the resolved
    RHAP_TEST_IMAGE equals either of those, by resolved path, it is refused
    regardless of whether the target is that same path or whether those
    files even exist.

    As a second, independent check, the resolved target is also refused if it
    is the same underlying file as golden.img or rhapsody.vmdk (e.g. reached
    via a link), even though its path resolved to the expected location.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    canonical_target = os.path.normcase(
        os.path.realpath(os.path.join(here, "work", "test.img"))
    )
    resolved = os.path.normcase(os.path.realpath(image_path))

    protected_paths = [
        os.path.normcase(os.path.realpath(os.path.join(here, name)))
        for name in ("golden.img", "rhapsody.vmdk")
    ]

    override = os.environ.get("RHAP_TEST_IMAGE")
    canonical_override = None
    if override:
        canonical_override = os.path.normcase(os.path.realpath(override))
        if canonical_override in protected_paths:
            raise SafetyError(
                "refusing to write %s; RHAP_TEST_IMAGE cannot authorise "
                "golden.img or rhapsody.vmdk" % image_path
            )

    if resolved != canonical_target and resolved != canonical_override:
        raise SafetyError(
            "refusing to write %s; only vm/work/test.img (or RHAP_TEST_IMAGE, "
            "if set) may be modified" % image_path
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
    an entry not terminated by '";' immediately after the closing quote, or a
    replacement value containing a double quote, semicolon, or newline (this
    table format has no escaping for those; letting one through would either
    terminate the entry early or inject an unrelated extra entry).
    """
    if '"' in value or ";" in value or "\n" in value:
        raise SafetyError(
            "replacement value %r contains a double quote, semicolon, or "
            "newline; refusing" % (value,)
        )
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

    Re-grafting the same target onto the same donor (the normal case in a
    rebuild -> inject -> boot -> rebuild loop, where a newer binary replaces
    the previous graft) is idempotent ONLY for a payload that still fits the
    donor's *current* size: the first graft sets the donor's di_size to that
    payload's size, and img.max_writable() derives the writable limit from
    di_size, so every later graft onto that donor is capped there too - not
    at the donor's original size - even though most of its original blocks
    are still allocated. A rebuild that grows past that shrunk limit is
    refused (see the size check below); it cannot be grafted onto the same
    donor again. Recovering requires recreating the working image
    (reset-image.cmd) and re-applying injections from scratch, not another
    graft.

    When a re-graft does fit, the donor's blocks and di_size are rewritten as
    usual, but di_nlink is left untouched and the directory entry is not
    rewritten, since it already points at the donor. A fresh donor must have
    di_nlink exactly 1 (see below); a donor already grafted to this target
    legitimately has di_nlink 2, so that check only applies to the first
    graft of a given donor.

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

    The inode previously named by target_path is left completely untouched,
    including its di_nlink: this module never decrements link counts, so
    after a graft that inode's di_nlink is one higher than the number of
    names that now actually point at it. That is a useful recovery route: for
    example, grafting over /mach_kernel leaves the original mach_kernel inode
    intact and reachable via /private/tftpboot/mach_kernel, which still names
    it.
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
            "donor %s currently addresses only %d bytes; payload is %d bytes. "
            "If this donor was previously grafted, that graft reduced its "
            "addressable size to its own payload - re-grafting a larger "
            "payload onto the same donor is not possible. Run reset-image.cmd "
            "and re-apply injections to restore full donor capacity."
            % (donor_path, limit, len(data))
        )
    frags = img.frags(donor)
    if any(f == 0 for f in frags):
        raise SafetyError("donor %s has holes; refusing" % donor_path)

    stripped = target_path.strip("/")
    if "/" in stripped:
        parent_part, leaf = stripped.rsplit("/", 1)
        parent = "/" + parent_part
    else:
        parent, leaf = "/", stripped
    parent_ino = img.resolve(parent)
    if parent_ino is None:
        raise SafetyError("parent of %s does not exist" % target_path)
    ent_off, old_ino = _find_dirent(img, parent_ino, leaf)
    if ent_off is None:
        raise SafetyError("%s does not exist; graft cannot create names" % target_path)
    if not img.inode(old_ino).is_reg():
        raise SafetyError(
            "%s is not a regular file; refusing to repoint it" % target_path
        )

    regrafting = old_ino == donor_ino
    if not regrafting and donor.nlink != 1:
        raise SafetyError(
            "donor %s has nlink %d; a graft donor must be a private, "
            "single-named file" % (donor_path, donor.nlink)
        )

    # 1. Fill the donor's blocks.
    payload = bytearray(data)
    need = (len(payload) + img.fsize - 1) // img.fsize
    payload += bytes(need * img.fsize - len(payload))
    for i in range(need):
        img._f.seek(img.frag_offset(frags[i]))
        img._f.write(bytes(payload[i * img.fsize:(i + 1) * img.fsize]))
    img._f.flush()

    # 2. Set the donor's size, and bump its link count unless this is a
    # re-graft (the link already exists; bumping again would be wrong).
    _write_inode_fields(img, donor_ino, size=len(data),
                        mtime=mtime if mtime is not None else donor.mtime,
                        nlink=None if regrafting else max(2, donor.nlink + 1))

    # 3. Repoint the target's directory entry (4 bytes) - unless this is a
    # re-graft, where it already points at the donor.
    if not regrafting:
        dir_frags = img.frags(img.inode(parent_ino))
        frag_index = ent_off // img.fsize
        within = ent_off % img.fsize
        dir_frag = dir_frags[frag_index]
        if dir_frag == 0:
            raise SafetyError(
                "%s: directory entry falls in a hole" % target_path
            )
        img._f.seek(img.frag_offset(dir_frag) + within)
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
    if cmd == "set-key" and len(argv) < 6:
        print("usage: rhap_inject.py <image> set-key <path> <key> <value>")
        return 2
    if cmd == "put" and len(argv) < 5:
        print("usage: rhap_inject.py <image> put <path> <local-file>")
        return 2

    try:
        check_target(image)
    except SafetyError as e:
        print(e, file=sys.stderr)
        return 1

    try:
        img = rhap_image.Image(image, writable=True)
    except (FileNotFoundError, ValueError) as e:
        print("%s: %s" % (image, e), file=sys.stderr)
        return 1
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
    raise SystemExit(main(sys.argv))
