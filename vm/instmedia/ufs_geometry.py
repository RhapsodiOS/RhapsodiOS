"""Filesystem geometry exactly as Rhapsody's newfs computes it.

A port of mkfs() in src/Commands/diskdev_cmds/newfs.tproj/mkfs.c, with
newfs.c's defaults for a plain `newfs /dev/r...a` (which is how `disk -i`
runs it): cpg 16, density 4 * fsize, minfree 5, optimisation for time,
rotdelay 0, maxcontig MAXPHYS / bsize, maxbpg bsize / 4, nrpos 8,
interleave 1, trackskew 0.  Checked against three filesystems Apple's newfs
made: golden.img, the DR2 install floppy (made with cpg 128) and the DR2 CD.

Units follow the superblock: sizes in fragments unless named otherwise, and
fssize in the label's sectors (secsize bytes each).
"""
import collections

BBSIZE = 8192
SBSIZE = 8192
MAXBSIZE = 8192
MINBSIZE = 4096
MAXFRAG = 8
NBBY = 8
DINODE_SIZE = 128
NDADDR = 12
NIADDR = 3
FS_MAXCONTIG = 16
MAXPHYS = 64 * 1024
FS_MAGIC = 0x011954
# i386 struct sizes and offsets (src/kernel-7/bsd/ufs/ffs/fs.h): struct fs is
# 1377 bytes rounded to 1380; fs_opostbl sits at 860 and fs_space at 1376.
SIZEOF_FS = 1380
SIZEOF_CG = 172
SIZEOF_CSUM = 16
OPOSTBL_OFF = 860
SPACE_OFF = 1376

# Where the geometry's int32 fields sit in the superblock (i386 struct fs).
SB_OFFSETS = {
    "sblkno": 8, "cblkno": 12, "iblkno": 16, "dblkno": 20, "cgoffset": 24,
    "cgmask": 28, "size": 36, "dsize": 40, "ncg": 44, "bsize": 48,
    "fsize": 52, "frag": 56, "minfree": 60, "rotdelay": 64, "rps": 68,
    "bmask": 72, "fmask": 76, "bshift": 80, "fshift": 84, "maxcontig": 88,
    "maxbpg": 92, "fragshift": 96, "fsbtodb": 100, "sbsize": 104,
    "csmask": 108, "csshift": 112, "nindir": 116, "inopb": 120,
    "nspf": 124, "optim": 128, "npsect": 132, "interleave": 136,
    "trackskew": 140, "csaddr": 152, "cssize": 156, "cgsize": 160,
    "ntrak": 164, "nsect": 168, "spc": 172, "ncyl": 176, "cpg": 180,
    "ipg": 184, "fpg": 188, "cpc": 856, "contigsumsize": 1316,
    "maxsymlinklen": 1320, "inodefmt": 1324, "postblformat": 1356,
    "nrpos": 1360, "postbloff": 1364, "rotbloff": 1368, "magic": 1372}
# And its int64 fields.
SB_QUAD_OFFSETS = {"maxfilesize": 1328, "qbmask": 1336, "qfmask": 1344}

FIELDS = (
    "fssize secsize nsect ntrak rpm bsize fsize frag fragshift bmask fmask "
    "bshift fshift nrpos nindir inopb nspf fsbtodb sblkno cblkno iblkno "
    "dblkno cgoffset cgmask maxfilesize spc cpc cpg ipg fpg contigsumsize "
    "cgsize size ncyl ncg interleave trackskew npsect postblformat sbsize "
    "postbloff rotbloff postbl rotbl csaddr cssize csmask csshift rotdelay "
    "minfree maxcontig maxbpg rps optim maxsymlinklen inodefmt qbmask "
    "qfmask magic dsize"
).split()

Geometry = collections.namedtuple("Geometry", FIELDS)


class GeometryError(Exception):
    pass


def howmany(x, y):
    return (x + y - 1) // y


def roundup(x, y):
    return howmany(x, y) * y


def _ilog2(x):
    n = 0
    while x > 1:
        x >>= 1
        n += 1
    return n


def cgstart(g, c):
    """First fragment of cylinder group c (fs.h cgstart)."""
    return g.fpg * c + g.cgoffset * (c & ~g.cgmask)


def cgbase(g, c):
    return g.fpg * c


def cgsblock(g, c):
    return cgstart(g, c) + g.sblkno


def cgtod(g, c):
    return cgstart(g, c) + g.cblkno


def cgimin(g, c):
    return cgstart(g, c) + g.iblkno


def cgdmin(g, c):
    return cgstart(g, c) + g.dblkno


def cg_data_end(g, c):
    """One past the last fragment of cylinder group c."""
    return min(cgbase(g, c) + g.fpg, g.size)


def geometry(fssize, secsize, nsect, ntrak, rpm, bsize=8192, fsize=1024,
             cpg=16):
    """Superblock geometry for a filesystem of fssize secsize-byte sectors."""
    density = 4 * fsize
    minfree = 5
    nrpos = 8
    for name, v in (("bsize", bsize), ("fsize", fsize), ("secsize", secsize)):
        if v <= 0 or v & (v - 1):
            raise GeometryError("%s must be a power of 2, not %d"
                                % (name, v))
    if (fsize < secsize or bsize < MINBSIZE or bsize > MAXBSIZE
            or bsize < fsize):
        raise GeometryError("bsize %d / fsize %d / secsize %d is not a valid "
                            "combination" % (bsize, fsize, secsize))
    if bsize // fsize > MAXFRAG:
        raise GeometryError("at most %d fragments per block" % MAXFRAG)
    if nsect <= 0 or ntrak <= 0 or fssize <= 0:
        raise GeometryError("nsect, ntrak and fssize must be positive")

    frag = bsize // fsize
    fragshift = _ilog2(frag)
    nindir = bsize // 4
    inopb = bsize // DINODE_SIZE
    nspf = fsize // secsize
    fsbtodb = _ilog2(nspf)
    nspb = nspf << fragshift
    inopf = inopb >> fragshift
    maxipg = roundup(bsize * NBBY // 3, inopb)
    sblkno = roundup(howmany(BBSIZE + SBSIZE, fsize), frag)
    cblkno = sblkno + roundup(howmany(SBSIZE, fsize), frag)
    iblkno = cblkno + frag
    cgoffset = roundup(howmany(nsect, nspf), frag)
    cgmask = -1
    i = ntrak
    while i > 1:
        cgmask <<= 1
        i >>= 1
    if ntrak & (ntrak - 1):
        cgmask <<= 1
    maxfilesize = bsize * NDADDR - 1
    sizepb = bsize
    for _ in range(NIADDR):
        sizepb *= nindir
        maxfilesize += sizepb
    spc = nsect * ntrak

    cpc = nspb
    i = spc
    while cpc > 1 and (i & 1) == 0:
        cpc >>= 1
        i >>= 1
    mincpc = cpc
    bpcg = spc * secsize
    maxcontig = max(1, MAXPHYS // bsize)
    contigsumsize = min(maxcontig, FS_MAXCONTIG) if maxcontig > 1 else 0

    def cgsize(cpg_, ipg_):
        n = (SIZEOF_CG + 4 + cpg_ * 4 + cpg_ * nrpos * 2
             + howmany(ipg_, NBBY) + howmany(cpg_ * spc // nspf, NBBY))
        if contigsumsize > 0:
            n += contigsumsize * 4 + howmany(cpg_ * spc // nspb, NBBY)
        return n

    def calcipg(cpg_):
        ncg_ = howmany(howmany(fssize, spc), cpg_)
        ipg_ = 0
        for _ in range(10):
            usedb = (iblkno + ipg_ // inopf) * nspf * secsize
            new = ((cpg_ * bpcg - usedb) // density * fssize // ncg_
                   // spc // cpg_)
            new = roundup(new, inopb)
            if new == ipg_:
                break
            ipg_ = new
        return ipg_

    # mkfs checks the minimum-cylinder group first; this port refuses the
    # geometries where mkfs would have had to change bsize or fsize.
    inospercg = min(roundup(bpcg // DINODE_SIZE, inopb), maxipg)
    used = (iblkno + inospercg // inopf) * nspf
    mincpgcnt = howmany(cgoffset * (~cgmask) + used, spc)
    mincpg = roundup(mincpgcnt, mincpc)
    if cgsize(mincpg, inospercg) > bsize:
        raise GeometryError("block maps do not fit; mkfs would change bsize")
    if calcipg(mincpg) > maxipg:
        raise GeometryError("inodes do not fit; mkfs would change bsize")

    cpg_ = roundup(cpg, mincpc)
    ipg = calcipg(cpg_)
    while ipg > maxipg:
        cpg_ -= mincpc
        ipg = calcipg(cpg_)
    while cgsize(cpg_, ipg) > bsize:
        cpg_ -= mincpc
        ipg = calcipg(cpg_)
    if cpg_ < mincpg:
        raise GeometryError("cylinder groups need at least %d cylinders"
                            % mincpg)
    fpg = cpg_ * spc // nspf
    cg_bytes = roundup(cgsize(cpg_, ipg), fsize)

    size = fssize >> fsbtodb
    ncyl = howmany(size * nspf, spc)

    sbsize = roundup(SIZEOF_FS, fsize)
    postbloff = OPOSTBL_OFF
    rotbloff = SPACE_OFF
    postbl = rotbl = ()
    if ntrak == 1:
        cpc = 0
    else:
        postblsize = nrpos * cpc * 2
        rotblsize = cpc * spc // nspb
        totalsbsize = SIZEOF_FS + rotblsize
        if not (nrpos == 8 and cpc <= 16):
            postbloff = SPACE_OFF
            rotbloff = SPACE_OFF + postblsize
            totalsbsize += postblsize
        if totalsbsize > SBSIZE or nsect > (1 << NBBY) * nspb:
            cpc = 0
        else:
            sbsize = roundup(totalsbsize, fsize)
            post = [[-1] * nrpos for _ in range(cpc)]
            rot = [0] * rotblsize
            for f in range((rotblsize - 1) * frag, -1, -frag):
                cylno = f * nspf // spc
                n = f * nspf
                # interleave 1, trackskew 0, npsect == nsect (newfs.c on NeXT)
                rpos = n % spc % nsect * nrpos // nsect
                blk = f // frag
                prev = post[cylno][rpos]
                rot[blk] = 0 if prev == -1 else prev - blk
                post[cylno][rpos] = blk
            postbl = tuple(v for row in post for v in row)
            rotbl = tuple(rot)

    ncg = howmany(ncyl, cpg_)
    dblkno = iblkno + ipg // inopf

    def start(c):
        return fpg * c + cgoffset * (c & ~cgmask)

    j = ncg - 1
    if (size - j * fpg < fpg
            and start(j) + dblkno - fpg * j > size - j * fpg):
        if j == 0:
            raise GeometryError("filesystem too small for one cylinder group")
        ncg -= 1
        ncyl -= ncyl % cpg_
        size = ncyl * spc // nspf
    csaddr = start(0) + dblkno
    cssize = roundup(ncg * SIZEOF_CSUM, fsize)
    per = bsize // SIZEOF_CSUM
    csmask = ~(per - 1)
    csshift = _ilog2(per)

    dsize = 0
    for c in range(ncg):
        base = fpg * c
        dmax = min(base + fpg, size)
        dlower = start(c) + sblkno - base
        dupper = start(c) + dblkno - base
        if c == 0:
            dupper += howmany(cssize, fsize)
        else:
            dsize += dlower
        dsize += (dmax - base) - dupper

    return Geometry(
        fssize=fssize, secsize=secsize, nsect=nsect, ntrak=ntrak, rpm=rpm,
        bsize=bsize, fsize=fsize, frag=frag, fragshift=fragshift,
        bmask=~(bsize - 1), fmask=~(fsize - 1), bshift=_ilog2(bsize),
        fshift=_ilog2(fsize), nrpos=nrpos, nindir=nindir, inopb=inopb,
        nspf=nspf, fsbtodb=fsbtodb, sblkno=sblkno, cblkno=cblkno,
        iblkno=iblkno, dblkno=dblkno, cgoffset=cgoffset, cgmask=cgmask,
        maxfilesize=maxfilesize, spc=spc, cpc=cpc, cpg=cpg_, ipg=ipg, fpg=fpg,
        contigsumsize=contigsumsize, cgsize=cg_bytes, size=size, ncyl=ncyl,
        ncg=ncg, interleave=1, trackskew=0, npsect=nsect, postblformat=1,
        sbsize=sbsize, postbloff=postbloff, rotbloff=rotbloff, postbl=postbl,
        rotbl=rotbl, csaddr=csaddr, cssize=cssize, csmask=csmask,
        csshift=csshift, rotdelay=0, minfree=minfree, maxcontig=maxcontig,
        maxbpg=bsize // 4, rps=rpm // 60, optim=0,
        maxsymlinklen=(NDADDR + NIADDR) * 4, inodefmt=2,
        qbmask=bsize - 1, qfmask=fsize - 1, magic=FS_MAGIC, dsize=dsize)
