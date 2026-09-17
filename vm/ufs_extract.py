"""Read a NeXT-labelled UFS volume into a plain tree of nodes.

Read-only.  The output is everything ufs_build.py needs to lay the same tree
back down: ordering, ownership, modes, and contents.
"""

import collections

import rhap_image

Node = collections.namedtuple("Node", "path kind mode uid gid mtime data")

KIND = {4: "dir", 8: "reg", 10: "lnk"}


class UnsupportedNode(Exception):
    pass


def _node(img, path, ino, kind):
    inode = img.inode(ino)
    if kind == "reg":
        data = img.read_file(inode)
    elif kind == "lnk":
        data = img.readlink(inode)
    else:
        data = None
    return Node(path, kind, inode.mode, inode.uid, inode.gid, inode.mtime, data)


def extract(image_path):
    with rhap_image.Image(image_path) as img:
        out = [_node(img, "/", 2, "dir")]
        seen = {2: "/"}
        pending = [("/", 2)]
        while pending:
            path, ino = pending.pop(0)
            for name, child, dtype in img.listdir(path):
                if name in (".", ".."):
                    continue
                kind = KIND.get(dtype)
                if kind is None:
                    raise UnsupportedNode(
                        "%s/%s has directory-entry type %d; only directories, "
                        "regular files and symlinks can be repackaged"
                        % (path.rstrip("/"), name, dtype))
                child_path = path.rstrip("/") + "/" + name
                if child in seen:
                    raise UnsupportedNode(
                        "inode %d is reachable as both %s and %s; hard links "
                        "cannot be repackaged" % (child, seen[child], child_path))
                seen[child] = child_path
                out.append(_node(img, child_path, child, kind))
                if kind == "dir":
                    pending.append((child_path, child))
        return out
