"""Write a NeXT-labelled UFS volume from a node tree.

The geometry is cloned from a template image rather than invented: the disk
label and every geometry field of the superblock are copied verbatim, and only
allocation state is regenerated.  The result is the filesystem newfs would have
produced for this geometry, with our contents in it.

Layout and macros follow src/kernel-7/bsd/ufs/ffs/fs.h.
"""

import collections
import struct

import rhap_image

SB_FIELDS = {
    "sblkno": 8, "cblkno": 12, "iblkno": 16, "dblkno": 20,
    "cgoffset": 24, "cgmask": 28, "size": 36, "dsize": 40, "ncg": 44,
    "bsize": 48, "fsize": 52, "frag": 56, "minfree": 60,
    "nindir": 116, "inopb": 120, "nspf": 124,
    "npsect": 132, "interleave": 136, "trackskew": 140,
    "csaddr": 152, "cssize": 156, "cgsize": 160,
    "ntrak": 164, "nsect": 168, "spc": 172, "ncyl": 176, "cpg": 180,
    "ipg": 184, "fpg": 188,
    "cpc": 856, "contigsumsize": 1316, "maxsymlinklen": 1320,
    "postblformat": 1356, "nrpos": 1360,
    "magic": 1372,
}

# src/kernel-7/bsd/ufs/ufs/dir.h:102 - Apple's UFS uses 1024, not DEV_BSIZE.
DIRBLKSIZ = 1024

# src/kernel-7/bsd/ufs/ufs/dinode.h:89 - direct block pointers per inode.
NDADDR = 12

Geometry = collections.namedtuple("Geometry", sorted(SB_FIELDS))
CgTables = collections.namedtuple("CgTables", "blktot blks frsum nbfree nffree")


class BuildError(Exception):
    pass


def read_geometry(image_path):
    with rhap_image.Image(image_path) as img:
        sb = img._read_at(img.part_start + rhap_image.SBOFF, rhap_image.SBOFF)
    values = {name: struct.unpack_from("<i", sb, off)[0]
              for name, off in SB_FIELDS.items()}
    if values["magic"] != rhap_image.FS_MAGIC:
        raise BuildError("bad UFS magic 0x%x in %s" % (values["magic"], image_path))
    if values["ncg"] != 1:
        raise BuildError(
            "%s has %d cylinder groups; this writer only handles single-group "
            "volumes (the two install floppies)" % (image_path, values["ncg"]))
    return Geometry(**values)


def cbtocylno(g, bno):
    return bno * g.nspf // g.spc


def cbtorpos(g, bno):
    if g.nrpos <= 1:
        return 0
    if g.npsect <= 0:
        raise BuildError("fs_npsect is %d; cannot compute rotational position"
                         % g.npsect)
    n = bno * g.nspf
    skewed = (n % g.spc // g.nsect * g.trackskew
              + n % g.spc % g.nsect * g.interleave)
    return skewed % g.nsect * g.nrpos // g.npsect


def bit_is_set(bitmap, i):
    return (bitmap[i // 8] >> (i % 8)) & 1


def recompute_cg_tables(g, blksfree):
    """Derive every allocation summary from the free-fragment bitmap.

    A set bit means the fragment is free.  A block counts as free only if all
    fs_frag of its fragments are; otherwise its maximal runs of free fragments
    are accounted individually, and runs never cross a block boundary.
    """
    blktot = [0] * g.cpg
    blks = [0] * (g.cpg * g.nrpos)
    frsum = [0] * g.frag
    nbfree = 0
    nffree = 0

    for base in range(0, g.fpg, g.frag):
        if all(bit_is_set(blksfree, base + i) for i in range(g.frag)):
            nbfree += 1
            cyl = cbtocylno(g, base)
            blktot[cyl] += 1
            blks[cyl * g.nrpos + cbtorpos(g, base)] += 1
            continue
        run = 0
        for i in range(g.frag):
            if bit_is_set(blksfree, base + i):
                run += 1
                continue
            if run:
                frsum[run] += 1
                nffree += run
            run = 0
        if run:
            frsum[run] += 1
            nffree += run

    return CgTables(blktot, blks, frsum, nbfree, nffree)


def recompute_cluster_maps(g, blksfree, nclusterblks):
    """Derive the cluster map and its run-length histogram from blksfree.

    One bit per block, set when every fragment of the block is free.  The
    histogram counts maximal runs of free blocks by length, with everything at
    or above fs_contigsumsize accumulated in the last bucket; see
    ffs_clusteracct in src/kernel-7/bsd/ufs/ffs/ffs_alloc.c:1810.
    """
    clustersfree = bytearray((g.fpg // g.frag + 7) // 8)
    for b in range(nclusterblks):
        base = b * g.frag
        if all(bit_is_set(blksfree, base + i) for i in range(g.frag)):
            clustersfree[b // 8] |= 1 << (b % 8)

    clustersum = [0] * (g.contigsumsize + 1)
    run = 0
    for b in range(nclusterblks):
        if bit_is_set(clustersfree, b):
            run += 1
            continue
        if run:
            clustersum[min(run, g.contigsumsize)] += 1
        run = 0
    if run:
        clustersum[min(run, g.contigsumsize)] += 1

    return bytes(clustersfree), clustersum


def _roundup(n, m):
    return (n + m - 1) // m * m


def _dirent(ino, name, kind):
    namlen = len(name)
    reclen = 8 + _roundup(namlen + 1, 4)
    dtype = {"dir": 4, "reg": 8, "lnk": 10}[kind]
    rec = bytearray(struct.pack("<IHBB", ino, reclen, dtype, namlen))
    rec += name.encode("ascii")
    rec += b"\0" * (reclen - 8 - namlen)
    return bytes(rec)


def _dir_block(entries):
    """Pack directory entries into DIRBLKSIZ chunks.

    No entry may straddle a chunk boundary; the last entry in each chunk has
    its record length stretched to the boundary.
    """
    out = bytearray()
    chunk = bytearray()
    for rec in entries:
        if len(chunk) + len(rec) > DIRBLKSIZ:
            struct.pack_into("<H", chunk, len(chunk) - _last_reclen(chunk) + 4,
                             DIRBLKSIZ - (len(chunk) - _last_reclen(chunk)))
            chunk += b"\0" * (DIRBLKSIZ - len(chunk))
            out += chunk
            chunk = bytearray()
        chunk += rec
    if chunk:
        struct.pack_into("<H", chunk, len(chunk) - _last_reclen(chunk) + 4,
                         DIRBLKSIZ - (len(chunk) - _last_reclen(chunk)))
        chunk += b"\0" * (DIRBLKSIZ - len(chunk))
        out += chunk
    return bytes(out)


def _last_reclen(chunk):
    """Record length of the final entry already packed into chunk."""
    p = 0
    last = 0
    while p < len(chunk):
        reclen = struct.unpack_from("<H", chunk, p + 4)[0]
        last = reclen
        p += reclen
    return last


def _dinode(ino_size, db, ib, blocks, mtime, mode, uid, gid, nlink):
    raw = bytearray(rhap_image.DINODE_SIZE)
    struct.pack_into("<Hh", raw, 0, mode, nlink)
    struct.pack_into("<Q", raw, 8, ino_size)
    for off in (16, 24, 32):
        struct.pack_into("<i", raw, off, mtime)
    struct.pack_into("<12i", raw, 40, *db)
    struct.pack_into("<3i", raw, 88, *ib)
    struct.pack_into("<i", raw, 104, blocks)
    struct.pack_into("<2I", raw, 112, uid, gid)
    return bytes(raw)


def build(template_path, nodes, total_frags=None):
    g = read_geometry(template_path)
    if total_frags is not None:
        raise BuildError(
            "resizing is not implemented; apply Task 7a of the plan first")
    with open(template_path, "rb") as f:
        image = bytearray(f.read())
    with rhap_image.Image(template_path) as img:
        part = img.part_start

    for node in nodes:
        if node.kind not in ("dir", "reg"):
            raise BuildError(
                "%s is a %s; this writer handles only directories and regular "
                "files (neither install floppy contains anything else)"
                % (node.path, node.kind))

    ino_of = {}
    for i, node in enumerate(nodes):
        ino_of[node.path] = 2 + i
    if 2 + len(nodes) - 1 >= g.ipg:
        raise BuildError("tree needs %d inodes, volume holds %d"
                         % (len(nodes) + 1, g.ipg))

    children = collections.defaultdict(list)
    for node in nodes[1:]:
        parent = node.path.rsplit("/", 1)[0] or "/"
        children[parent].append(node)

    # Serialise every object's bytes before allocating, so the allocator sees
    # final sizes.
    payload = {}
    for node in nodes:
        if node.kind == "dir":
            if node.path == "/":
                parent = "/"
            else:
                parent = node.path.rsplit("/", 1)[0] or "/"
            entries = [_dirent(ino_of[node.path], ".", "dir"),
                       _dirent(ino_of[parent], "..", "dir")]
            for child in children[node.path]:
                entries.append(_dirent(ino_of[child.path],
                                       child.path.rsplit("/", 1)[1], child.kind))
            payload[node.path] = _dir_block(entries)
        else:
            payload[node.path] = node.data

    # Data begins after the cylinder summary.  Whole blocks must start on a
    # multiple of fs_frag, so allocation starts at the next block boundary; the
    # few fragments before it stay genuinely free rather than being written off.
    first_data = g.csaddr + _roundup(g.cssize, g.fsize) // g.fsize
    next_frag = _roundup(first_data, g.frag)
    limit = g.size

    # The output must be a function of the node tree alone, so nothing of the
    # template's own data area may show through the slack we do not write.
    image[part + first_data * g.fsize:part + g.size * g.fsize] = \
        bytes((g.size - first_data) * g.fsize)

    blksfree = bytearray(b"\xff" * ((g.fpg + 7) // 8))
    for f in range(0, first_data):
        blksfree[f // 8] &= ~(1 << (f % 8)) & 0xff
    for f in range(g.size, g.fpg):
        blksfree[f // 8] &= ~(1 << (f % 8)) & 0xff

    def _claim(start, nfrags):
        nonlocal next_frag
        if start + nfrags > limit:
            raise BuildError(
                "tree does not fit: needed %d more fragments at %d, volume ends "
                "at %d" % (nfrags, start, limit))
        for f in range(start, start + nfrags):
            blksfree[f // 8] &= ~(1 << (f % 8)) & 0xff
        next_frag = start + nfrags
        return start

    def alloc_block():
        """A whole block, block-aligned.

        ffs_blkfree derives the block number by dividing by fs_frag, so a
        misaligned whole block would free somebody else's fragments.
        """
        return _claim(_roundup(next_frag, g.frag), g.frag)

    def alloc_frags(nfrags):
        """A run of fewer than fs_frag fragments, never straddling a block."""
        start = next_frag
        if start // g.frag != (start + nfrags - 1) // g.frag:
            start = _roundup(start, g.frag)
        return _claim(start, nfrags)

    inodes = {}
    for node in nodes:
        data = payload[node.path]
        nblocks = _roundup(len(data), g.bsize) // g.bsize
        db = [0] * NDADDR
        ib = [0] * 3
        charged = 0
        blocks = []
        for lbn in range(nblocks):
            remaining = len(data) - lbn * g.bsize
            # fs.h:498 (blksize): only a tail at a direct logical block may be
            # fragmented.  An indirect-mapped block is always a full block.
            if lbn == nblocks - 1 and lbn < NDADDR and remaining < g.bsize:
                nfrags = _roundup(remaining, g.fsize) // g.fsize
                blocks.append(alloc_frags(nfrags))
            else:
                nfrags = g.frag
                blocks.append(alloc_block())
            charged += nfrags
        if len(blocks) > NDADDR + g.nindir:
            raise BuildError("%s needs double indirect blocks" % node.path)
        for i, b in enumerate(blocks[:NDADDR]):
            db[i] = b
        if len(blocks) > NDADDR:
            ind = alloc_block()
            charged += g.frag
            ib[0] = ind
            table = bytearray(g.bsize)
            for i, b in enumerate(blocks[NDADDR:]):
                struct.pack_into("<i", table, i * 4, b)
            image[part + ind * g.fsize:part + ind * g.fsize + g.bsize] = table
        off = 0
        for b in blocks:
            chunk = data[off:off + g.bsize]
            image[part + b * g.fsize:part + b * g.fsize + len(chunk)] = chunk
            off += g.bsize
        nlink = 2 + sum(1 for c in children[node.path] if c.kind == "dir") \
            if node.kind == "dir" else 1
        inodes[node.path] = _dinode(len(data), db, ib, charged,
                                    node.mtime, node.mode, node.uid, node.gid,
                                    nlink)

    # Inode table.
    table = bytearray(g.ipg * rhap_image.DINODE_SIZE)
    inosused = bytearray((g.ipg + 7) // 8)
    for i in range(2):
        inosused[i // 8] |= 1 << (i % 8)
    ndir = 0
    for node in nodes:
        ino = ino_of[node.path]
        table[ino * rhap_image.DINODE_SIZE:(ino + 1) * rhap_image.DINODE_SIZE] = \
            inodes[node.path]
        inosused[ino // 8] |= 1 << (ino % 8)
        if node.kind == "dir":
            ndir += 1
    image[part + g.iblkno * g.fsize:
          part + g.iblkno * g.fsize + len(table)] = table

    # Cylinder group.
    cg = bytearray(image[part + g.cblkno * g.fsize:
                         part + g.cblkno * g.fsize + g.bsize])
    btotoff, boff, iusedoff, freeoff = struct.unpack_from("<4i", cg, 84)
    t = recompute_cg_tables(g, blksfree)
    nifree = g.ipg - (len(nodes) + 2)
    struct.pack_into("<4i", cg, 24, ndir, t.nbfree, nifree, t.nffree)
    struct.pack_into("<%di" % g.frag, cg, 52, *t.frsum)
    struct.pack_into("<%di" % g.cpg, cg, btotoff, *t.blktot)
    struct.pack_into("<%dh" % (g.cpg * g.nrpos), cg, boff, *t.blks)
    cg[iusedoff:iusedoff + len(inosused)] = inosused
    cg[freeoff:freeoff + len(blksfree)] = blksfree
    if g.contigsumsize > 0:
        clustersumoff, clusteroff, nclusterblks = struct.unpack_from("<3i", cg, 104)
        clustersfree, clustersum = recompute_cluster_maps(g, blksfree, nclusterblks)
        struct.pack_into("<%di" % len(clustersum), cg, clustersumoff, *clustersum)
        cg[clusteroff:clusteroff + len(clustersfree)] = clustersfree
    image[part + g.cblkno * g.fsize:
          part + g.cblkno * g.fsize + g.bsize] = cg

    # Superblock counters and the cylinder summary block.
    sb_off = part + rhap_image.SBOFF
    struct.pack_into("<4i", image, sb_off + 192, ndir, t.nbfree, nifree, t.nffree)
    struct.pack_into("<4i", image, part + g.csaddr * g.fsize,
                     ndir, t.nbfree, nifree, t.nffree)

    return bytes(image)
