"""Read a UFS image back with rhap_image and compare it with its node tree.

Independent of the writer: it walks the directories it finds on disk, and
works out link counts and di_blocks from first principles.  What it checks
is what fsck's passes 1, 2 and 4 would complain about, plus the contents.
"""
import collections

import rhap_image
from instmedia import ufs, ufs_geometry as ug


def _join(path, name):
    return path.rstrip("/") + "/" + name


def _blocks(img, size):
    """di_blocks for size bytes of data: a fragment tail only while the file
    has direct blocks alone, plus every indirect block, in sectors."""
    nblocks = ug.howmany(size, img.bsize)
    if nblocks <= ug.NDADDR:
        frags = ug.howmany(size, img.fsize)
    else:
        rest = nblocks - ug.NDADDR - img.nindir
        nind = 1 + (1 + ug.howmany(rest, img.nindir) if rest > 0 else 0)
        frags = (nblocks + nind) * img.frag
    return frags * (img.fsize // img.label["secsize"])


def diff(image_path, nodes):
    """Every way the image disagrees with nodes, as a list of strings."""
    problems = []
    want = {node.path: node for node in nodes}
    with rhap_image.Image(image_path) as img:
        found = {"/": ufs.ROOTINO}
        dtype_of = {}
        refs = collections.Counter()
        pending = ["/"]
        while pending:
            path = pending.pop()
            for name, ino, dtype, _ in img.iter_dir(found[path]):
                refs[ino] += 1
                if name == ".":
                    expect = found[path]
                elif name == "..":
                    expect = found[path.rsplit("/", 1)[0] or "/"]
                else:
                    child = _join(path, name)
                    found[child] = ino
                    dtype_of[child] = dtype
                    if dtype == ufs.DTYPE["dir"]:
                        pending.append(child)
                    continue
                if ino != expect:
                    problems.append("%s: %r is inode %d, not %d"
                                    % (path, name, ino, expect))

        for path in sorted(want.keys() - found.keys()):
            problems.append("%s: missing" % path)
        for path in sorted(found.keys() - want.keys()):
            problems.append("%s: not in the tree" % path)

        for node in nodes:
            if node.path not in found:
                continue
            ino = found[node.path]
            inode = img.inode(ino)
            target = node
            if node.kind == "hlink":
                target = want[node.data]
                if found.get(node.data) != ino:
                    problems.append("%s: inode %d, but %s is inode %s"
                                    % (node.path, ino, node.data,
                                       found.get(node.data)))
            kind = target.kind
            if inode.mode != ufs.IFMT[kind] | (target.mode & 0o7777):
                problems.append("%s: mode 0%o" % (node.path, inode.mode))
            if node.path != "/" and dtype_of[node.path] != ufs.DTYPE[kind]:
                problems.append("%s: d_type %d" % (node.path,
                                                   dtype_of[node.path]))
            if (inode.uid, inode.gid, inode.mtime) != (
                    target.uid, target.gid, target.mtime):
                problems.append("%s: uid/gid/mtime %d/%d/%d"
                                % (node.path, inode.uid, inode.gid,
                                   inode.mtime))
            if inode.nlink != refs[ino]:
                problems.append("%s: nlink %d, %d names"
                                % (node.path, inode.nlink, refs[ino]))
            if kind in ("chr", "blk"):
                major, minor = target.data
                if (inode.db[0], inode.size, inode.blocks) != (
                        (major << 8) | minor, 0, 0):
                    problems.append("%s: rdev 0x%x size %d blocks %d"
                                    % (node.path, inode.db[0], inode.size,
                                       inode.blocks))
                continue
            if kind == "lnk":
                if img.readlink(inode) != target.data:
                    problems.append("%s: link text %r"
                                    % (node.path, img.readlink(inode)))
                fast = inode.size < img.maxsymlinklen
                expect = 0 if fast else _blocks(img, inode.size)
            else:
                if kind == "reg" and img.read_file(inode) != target.data:
                    problems.append("%s: contents differ" % node.path)
                expect = _blocks(img, inode.size)
            if inode.blocks != expect:
                problems.append("%s: di_blocks %d, expected %d"
                                % (node.path, inode.blocks, expect))
    return problems
