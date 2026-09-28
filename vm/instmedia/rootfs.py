"""Build a node tree from apk payloads, as `apk add` would lay them down.

Control members (.PKGINFO and the install scripts) are skipped; everything
else is data.  A member whose parent directory is a symlink in the tree
goes where the symlink leads, as it would when apk extracts into a real
filesystem: `files` makes etc a link to private/etc, so a package's etc/foo
lands in /private/etc/foo.  Directories two packages share merge; any other
path two packages both claim is recorded in Tree.conflicts, because apk add
would refuse the second package, and the first package's node is kept.
Install scripts are not run.
"""
import collections
import posixpath
import tarfile

from ufs_extract import Node
from instmedia import apkrepo

Conflict = collections.namedtuple("Conflict", "path first second")
OVERLAY = "(overlay)"
MAX_LINKS = 32


class TreeError(Exception):
    pass


def _sort_key(path):
    return () if path == "/" else tuple(path[1:].split("/"))


class Tree:
    def __init__(self, root_mtime=0):
        self._nodes = {"/": Node("/", "dir", 0o755, 0, 0, root_mtime, None)}
        self._owner = {"/": None}
        self.conflicts = []

    def get(self, path):
        return self._nodes.get(path)

    def data(self, path):
        """The contents of the regular file at path (links followed)."""
        node = self._nodes.get(self.resolve(path))
        if node is not None and node.kind == "hlink":
            node = self._nodes[node.data]
        if node is None or node.kind != "reg":
            raise TreeError("%s is not a regular file in the tree" % path)
        return node.data

    def nodes(self):
        """Every node, "/" first and each directory before its contents."""
        return [self._nodes[p] for p in sorted(self._nodes, key=_sort_key)]

    def newest_mtime(self):
        return max(n.mtime for n in self._nodes.values())

    def resolve(self, path):
        """path with every symlink along it followed, the last one too."""
        parent = self._dir(posixpath.dirname(path), None, 0, False)
        return self._follow(posixpath.join(parent, posixpath.basename(path)))

    def _follow(self, path, depth=0):
        node = self._nodes.get(path)
        if node is None or node.kind != "lnk":
            return path
        if depth > MAX_LINKS:
            raise TreeError("too many symlinks resolving %s" % path)
        target = posixpath.normpath(posixpath.join(
            posixpath.dirname(path), node.data))
        parent = self._dir(posixpath.dirname(target), None, 0, False)
        return self._follow(posixpath.join(parent,
                                           posixpath.basename(target)),
                            depth + 1)

    def _dir(self, path, owner, mtime, create):
        """The real path of directory path, following symlinks.  Missing
        directories are made when create is set, else refused."""
        real = "/"
        for part in [p for p in path.split("/") if p]:
            here = posixpath.join(real, part)
            real = self._follow(here)
            node = self._nodes.get(real)
            if node is None:
                # apk cannot extract through a symlink to nowhere either.
                if not create or real != here:
                    raise TreeError("%s: no directory %s" % (path, real))
                self._nodes[real] = Node(real, "dir", 0o755, 0, 0, mtime,
                                         None)
                self._owner[real] = owner
            elif node.kind != "dir":
                raise TreeError("%s: %s is a %s, not a directory"
                                % (path, real, node.kind))
        return real

    def add(self, path, kind, mode, uid, gid, mtime, data, owner):
        """Add a member of owner's apk at path ("/"-rooted)."""
        parent = self._dir(posixpath.dirname(path), owner, mtime, True)
        full = posixpath.join(parent, posixpath.basename(path))
        if kind == "hlink":
            data = self.resolve(data)
            target = self._nodes.get(data)
            if target is None or target.kind != "reg":
                raise TreeError("%s: hard link to %s, which is not a "
                                "regular file" % (path, data))
        existing = self._nodes.get(full)
        if existing is not None:
            if kind == "dir" and self._nodes.get(
                    self._follow(full), existing).kind == "dir":
                return
            if not (kind != "dir" and existing.kind != "dir"
                    and self._owner[full] == owner):
                self.conflicts.append(Conflict(full, self._owner[full],
                                               owner))
                return
        self._nodes[full] = Node(full, kind, mode, uid, gid, mtime, data)
        self._owner[full] = owner

    def put(self, node):
        """Place node, replacing whatever is at its path; the overlay's way
        in.  Missing parents are made."""
        parent = self._dir(posixpath.dirname(node.path), OVERLAY,
                           node.mtime, True)
        full = posixpath.join(parent, posixpath.basename(node.path))
        existing = self._nodes.get(full)
        if existing is not None and (existing.kind == "dir") != (
                node.kind == "dir"):
            raise TreeError("overlay %s would replace a %s with a %s"
                            % (full, existing.kind, node.kind))
        self._nodes[full] = node._replace(path=full)
        self._owner[full] = OVERLAY


def add_apk(tree, source, owner):
    """Add every data member of the apk at source (a path or its bytes)."""
    with apkrepo.open_apk(source) as tar:
        for m in tar:
            name = apkrepo.member_name(m.name)
            if not name or apkrepo.is_control(name):
                continue
            path = "/" + name
            mode = m.mode & 0o7777
            if m.isdir():
                kind, data = "dir", None
            elif m.isreg():
                kind, data = "reg", tar.extractfile(m).read()
            elif m.issym():
                kind, data = "lnk", m.linkname
            elif m.islnk():
                kind, data = "hlink", "/" + apkrepo.member_name(m.linkname)
            elif m.ischr() or m.isblk():
                kind = "chr" if m.ischr() else "blk"
                data = (m.devmajor, m.devminor)
            else:
                raise TreeError("%s: %s has unsupported tar type %r"
                                % (owner, name, m.type))
            tree.add(path, kind, mode, m.uid, m.gid, int(m.mtime), data,
                     owner)
