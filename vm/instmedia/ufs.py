"""Write a node tree as a UFS filesystem laid out the way Rhapsody's newfs
lays one out.

The metadata follows mkfs.c: the superblock and an identical copy in every
cylinder group, cylinder-group headers as initcg() builds them (with NeXT's
cg_clustersumoff), zeroed inode tables and the cylinder summary.  Contents
then go in the way the kernel would have put them: fragments only for the
last direct block of a file, single and double indirect blocks, fast
symlinks for targets shorter than fs_maxsymlinklen, and device numbers in
di_db[0].  Little-endian, like DR2 media.

Nodes are ufs_extract.Node(path, kind, mode, uid, gid, mtime, data):

    dir    data None
    reg    data bytes
    lnk    data the target, str
    chr    data (major, minor)
    blk    data (major, minor)
    hlink  data the path of the node it is another name for (not a dir)

nodes[0] must be the root directory "/".  Inodes are numbered from 2 in
node order, hard links taking their target's.  Only mode's permission bits
are used; the type comes from kind.
"""
import collections
import struct

import ufs_cg
from instmedia import ufs_geometry as ug
from instmedia.space import Space

SBOFF = ug.BBSIZE         # the superblock follows the boot block
ROOTINO = 2
DIRBLKSIZ = 1024        # src/kernel-7/bsd/ufs/ufs/dir.h
MAXNAMLEN = 255
CG_MAGIC = 0x090255

IFMT = {"dir": 0o040000, "reg": 0o100000, "lnk": 0o120000,
        "chr": 0o020000, "blk": 0o060000}
DTYPE = {"dir": 4, "reg": 8, "lnk": 10, "chr": 2, "blk": 6}


class TreeError(Exception):
    pass


def _name(path):
    raw = path.rsplit("/", 1)[1].encode("utf-8")
    if not 0 < len(raw) <= MAXNAMLEN:
        raise TreeError("%r: a name is 1 to %d bytes" % (path, MAXNAMLEN))
    return raw


def _parent(path):
    return path.rsplit("/", 1)[0] or "/"


def _index(g, nodes):
    """Check the tree and number it: (inode of each path, kind of each
    inode, directory entries of each directory, link count of each inode)."""
    if not nodes or nodes[0].path != "/" or nodes[0].kind != "dir":
        raise TreeError('nodes[0] must be the root directory "/"')
    by_path = {}
    for node in nodes:
        if node.kind not in DTYPE and node.kind != "hlink":
            raise TreeError("%s: unknown kind %r" % (node.path, node.kind))
        if node.path != "/" and (not node.path.startswith("/")
                                 or node.path.endswith("/")
                                 or "//" in node.path):
            raise TreeError("%r is not a normalised absolute path"
                            % node.path)
        if node.path in by_path:
            raise TreeError("%s appears twice" % node.path)
        by_path[node.path] = node
    ino_of = {}
    kind_of = {}
    for node in nodes:
        if node.kind != "hlink":
            ino_of[node.path] = ROOTINO + len(kind_of)
            kind_of[ino_of[node.path]] = node.kind
    if ROOTINO + len(kind_of) > g.ncg * g.ipg:
        raise TreeError("%d inodes needed, the filesystem has %d"
                        % (len(kind_of), g.ncg * g.ipg - ROOTINO))
    nlink = collections.Counter()
    entries = collections.defaultdict(list)
    for node in nodes:
        if node.kind == "hlink":
            target = by_path.get(node.data)
            if target is None or target.kind in ("dir", "hlink"):
                raise TreeError("%s: hard link to %r, which is not a file"
                                % (node.path, node.data))
            ino_of[node.path] = ino_of[node.data]
        ino = ino_of[node.path]
        nlink[ino] += 1                     # the root's stands for its ".."
        if node.path == "/":
            continue
        parent = by_path.get(_parent(node.path))
        if parent is None or parent.kind != "dir":
            raise TreeError("%s: parent is not a directory in the tree"
                            % node.path)
        entries[parent.path].append(
            (ino, _name(node.path), DTYPE[kind_of[ino]]))
        if kind_of[ino] == "dir":
            nlink[ino_of[parent.path]] += 1         # its ".."
    for path, ino in ino_of.items():
        if kind_of[ino] == "dir":
            nlink[ino] += 1                         # its "."
    return ino_of, kind_of, entries, nlink


def _dir_data(entries):
    """Directory contents in DIRBLKSIZ chunks.  No entry crosses a chunk
    boundary, and each chunk's last entry stretches to its end."""
    chunks = [bytearray()]
    last = [0]
    for ino, name, dtype in entries:
        reclen = 8 + ug.roundup(len(name) + 1, 4)
        rec = struct.pack("<IHBB", ino, reclen, dtype, len(name)) + name
        if len(chunks[-1]) + reclen > DIRBLKSIZ:
            chunks.append(bytearray())
            last.append(0)
        last[-1] = len(chunks[-1])
        chunks[-1] += rec.ljust(reclen, b"\0")
    for chunk, at in zip(chunks, last):
        struct.pack_into("<H", chunk, at + 4, DIRBLKSIZ - at)
        chunk.extend(bytes(DIRBLKSIZ - len(chunk)))
    return b"".join(chunks)


def _store(put, g, space, data):
    """Allocate and write data; return (di_db, di_ib, fragments used)."""
    nblocks = ug.howmany(len(data), g.bsize)
    if nblocks > ug.NDADDR + g.nindir + g.nindir * g.nindir:
        raise TreeError("%d bytes needs triple indirect blocks" % len(data))
    addrs = []
    used = 0
    for lbn in range(nblocks):
        chunk = data[lbn * g.bsize:(lbn + 1) * g.bsize]
        n = ug.howmany(len(chunk), g.fsize)
        # fs.h blksize(): only a direct block may be short of a whole block.
        if lbn < ug.NDADDR and n < g.frag:
            addr = space.frags(n)
        else:
            addr, n = space.block(), g.frag
        put(addr, chunk.ljust(n * g.fsize, b"\0"))
        addrs.append(addr)
        used += n

    def indirect(ptrs):
        addr = space.block()
        put(addr, struct.pack("<%di" % len(ptrs), *ptrs).ljust(g.bsize, b"\0"))
        return addr

    db = addrs[:ug.NDADDR] + [0] * (ug.NDADDR - len(addrs[:ug.NDADDR]))
    ib = [0] * ug.NIADDR
    rest = addrs[ug.NDADDR:]
    if rest:
        ib[0] = indirect(rest[:g.nindir])
        used += g.frag
        rest = rest[g.nindir:]
    if rest:
        second = [indirect(rest[i:i + g.nindir])
                  for i in range(0, len(rest), g.nindir)]
        ib[1] = indirect(second)
        used += g.frag * (len(second) + 1)
    return db, ib, used


def _dinode(mode, nlink, size, mtime, addr_area, blocks, uid, gid):
    raw = bytearray(ug.DINODE_SIZE)
    struct.pack_into("<Hh", raw, 0, mode, nlink)
    struct.pack_into("<Q", raw, 8, size)
    for off in (16, 24, 32):                # atime, mtime, ctime
        struct.pack_into("<i", raw, off, mtime)
    raw[40:100] = addr_area                 # di_db[12], di_ib[3]
    struct.pack_into("<i", raw, 104, blocks)
    struct.pack_into("<2I", raw, 112, uid, gid)
    return bytes(raw)


def cg_offsets(g):
    """(btotoff, boff, iusedoff, freeoff, nextfreeoff, clustersumoff,
    clusteroff) exactly as initcg() computes them, NeXT variant."""
    btotoff = ug.SIZEOF_CG - 4              # &cg_space[0]
    boff = btotoff + g.cpg * 4
    iusedoff = boff + g.cpg * g.nrpos * 2
    freeoff = iusedoff + ug.howmany(g.ipg, 8)
    mapbytes = ug.howmany(g.fpg, 8)
    if g.contigsumsize <= 0:
        return btotoff, boff, iusedoff, freeoff, freeoff + mapbytes, 0, 0
    # PR2216969: NeXT dropped BSD's "- sizeof(long)" here.
    clustersumoff = ug.roundup(freeoff + mapbytes, 4)
    clusteroff = clustersumoff + (g.contigsumsize + 1) * 4
    nextfreeoff = clusteroff + ug.howmany(g.fpg // g.frag, 8)
    return (btotoff, boff, iusedoff, freeoff, nextfreeoff, clustersumoff,
            clusteroff)


def cg_block(g, c, now, blksfree, inosused, ndir, nifree):
    """Cylinder group c's header block; returns (bytes, its struct csum)."""
    btotoff, boff, iusedoff, freeoff, nextfreeoff, clustersumoff, \
        clusteroff = cg_offsets(g)
    ndblk = ug.cg_data_end(g, c) - ug.cgbase(g, c)
    ncyl = g.ncyl % g.cpg if c == g.ncg - 1 else g.cpg
    nclusterblks = ndblk // g.frag if g.contigsumsize > 0 else 0
    t = ufs_cg.recompute_cg_tables(g, blksfree)
    cs = (ndir, t.nbfree, nifree, t.nffree)
    frsum = list(t.frsum) + [0] * (ug.MAXFRAG - len(t.frsum))
    buf = bytearray(g.bsize)
    struct.pack_into("<4ihhi4i3i8i8i", buf, 0, 0, CG_MAGIC, now, c,
                     ncyl, g.ipg, ndblk, *cs, 0, 0, 0, *frsum,
                     btotoff, boff, iusedoff, freeoff, nextfreeoff,
                     clustersumoff, clusteroff, nclusterblks)
    struct.pack_into("<%di" % g.cpg, buf, btotoff, *t.blktot)
    struct.pack_into("<%dh" % (g.cpg * g.nrpos), buf, boff, *t.blks)
    buf[iusedoff:iusedoff + len(inosused)] = inosused
    buf[freeoff:freeoff + len(blksfree)] = blksfree
    if g.contigsumsize > 0:
        clustersfree, clustersum = ufs_cg.recompute_cluster_maps(
            g, blksfree, nclusterblks)
        struct.pack_into("<%di" % len(clustersum), buf, clustersumoff,
                         *clustersum)
        buf[clusteroff:clusteroff + len(clustersfree)] = clustersfree
    return bytes(buf), cs


def superblock(g, now, cstotal):
    """The superblock: fs_sbsize bytes, clean, with its rotational tables."""
    buf = bytearray(g.sbsize)
    for field, off in ug.SB_OFFSETS.items():
        struct.pack_into("<i", buf, off, getattr(g, field))
    for field, off in ug.SB_QUAD_OFFSETS.items():
        struct.pack_into("<q", buf, off, getattr(g, field))
    struct.pack_into("<i", buf, 32, now)                # fs_time
    struct.pack_into("<4i", buf, 192, *cstotal)         # fs_cstotal
    buf[209] = 1                                        # fs_clean
    if g.cpc:
        struct.pack_into("<%dh" % len(g.postbl), buf, g.postbloff, *g.postbl)
        buf[g.rotbloff:g.rotbloff + len(g.rotbl)] = bytes(
            v & 0xff for v in g.rotbl)
    return bytes(buf)


def write(f, offset, g, nodes, now):
    """Write the filesystem into file object f, starting at byte offset.

    g is a ufs_geometry.Geometry and now the time stamped on the superblock
    and cylinder groups.  Every byte the filesystem's metadata occupies is
    written, inode tables included, so f need not be zeroed first.
    """
    ino_of, kind_of, entries, nlink = _index(g, nodes)
    space = Space(g)

    def put(frag, data):
        f.seek(offset + frag * g.fsize)
        f.write(data)

    dinodes = {}
    for node in nodes:
        if node.kind == "hlink":
            continue
        ino = ino_of[node.path]
        mode = IFMT[node.kind] | (node.mode & 0o7777)
        size = used = 0
        area = bytes(60)
        if node.kind in ("chr", "blk"):
            major, minor = node.data
            area = struct.pack("<i", (major << 8) | minor).ljust(60, b"\0")
        else:
            if node.kind == "dir":
                parent = ino_of[_parent(node.path)]
                data = _dir_data([(ino, b".", DTYPE["dir"]),
                                  (parent, b"..", DTYPE["dir"])]
                                 + entries[node.path])
            elif node.kind == "lnk":
                data = node.data.encode("utf-8")
            else:
                data = node.data
            size = len(data)
            if node.kind == "lnk" and size < g.maxsymlinklen:
                area = data.ljust(60, b"\0")
            elif data:
                db, ib, used = _store(put, g, space, data)
                area = struct.pack("<15i", *(db + ib))
        dinodes[ino] = _dinode(mode, nlink[ino], size, node.mtime, area,
                               used * g.nspf, node.uid, node.gid)

    per_cg = []
    for c in range(g.ncg):
        first = c * g.ipg
        table = bytearray(g.ipg * ug.DINODE_SIZE)
        inosused = bytearray(ug.howmany(g.ipg, 8))
        ndir = 0
        for i in range(g.ipg):
            ino = first + i
            if ino < ROOTINO or ino in dinodes:
                inosused[i >> 3] |= 1 << (i & 7)
            if ino in dinodes:
                at = i * ug.DINODE_SIZE
                table[at:at + ug.DINODE_SIZE] = dinodes[ino]
                ndir += kind_of[ino] == "dir"
        nifree = g.ipg - sum(bin(b).count("1") for b in inosused)
        put(ug.cgimin(g, c), table)
        block, cs = cg_block(g, c, now, space.blksfree(c), bytes(inosused),
                             ndir, nifree)
        put(ug.cgtod(g, c), block)
        per_cg.append(cs)

    put(g.csaddr, b"".join(struct.pack("<4i", *cs) for cs in per_cg)
        .ljust(g.cssize, b"\0"))
    sb = superblock(g, now, [sum(col) for col in zip(*per_cg)])
    f.seek(offset + SBOFF)
    f.write(sb)
    for c in range(g.ncg):
        put(ug.cgsblock(g, c), sb)
