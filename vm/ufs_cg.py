"""Shared UFS geometry and cylinder-group summary math.

Imported by both ufs_build.py (which builds fresh single-group images) and
ufs_alloc.py (which allocates within existing multi-group ones).  It lives in
one place because a divergence between the two would corrupt a filesystem in a
way that only shows up later, under fsck or the kernel.

Pure computation: no I/O policy, no writes, no safety rules.
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

Geometry = collections.namedtuple("Geometry", sorted(SB_FIELDS))
CgTables = collections.namedtuple("CgTables", "blktot blks frsum nbfree nffree")


class UfsError(Exception):
    pass


def read_geometry(image_path):
    """Read the superblock.  Unlike ufs_build's, this accepts any ncg."""
    with rhap_image.Image(image_path) as img:
        sb = img._read_at(img.part_start + rhap_image.SBOFF, rhap_image.SBOFF)
    values = {name: struct.unpack_from("<i", sb, off)[0]
              for name, off in SB_FIELDS.items()}
    if values["magic"] != rhap_image.FS_MAGIC:
        raise UfsError("bad UFS magic 0x%x in %s"
                       % (values["magic"], image_path))
    return Geometry(**values)


def cbtocylno(g, bno):
    return bno * g.nspf // g.spc


def cbtorpos(g, bno):
    if g.nrpos <= 1:
        return 0
    if g.npsect <= 0:
        raise UfsError("fs_npsect is %d; cannot compute rotational position"
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
