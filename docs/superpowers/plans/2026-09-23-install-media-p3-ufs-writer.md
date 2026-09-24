# Install media phase 3: host UFS writer — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Write UFS filesystems and NeXT disk labels on the Windows host,
from a tree of nodes, laid out exactly as Rhapsody's `newfs` and `disk -i`
lay them out, so that later phases can build install media without Apple
templates.

**Architecture:** A new package, `vm/instmedia/`. `ufs_geometry.py` ports
`newfs`'s geometry arithmetic. `label.py` encodes `dlV3` labels, and
`space.py` hands out free space the way `initcg()` leaves it. `ufs.py`
writes the superblock, cylinder groups, inodes, directories and data.
`readback.py` reads an image back with `rhap_image` and diffs it against the
tree. `sample.py` builds the two images phase 3 is judged on: an fdisk disk
with label `secsize` 512, and a CD-style volume with `secsize` 2048. Last,
`vm/qemu_boot.py` learns to attach a second IDE disk and type at the guest,
which the `fsck -n` gate needs.

**Tech Stack:**
- Python 3.13, standard library only, with `unittest`
- QEMU 11.1 at `C:\Program Files\qemu`, with its bundled SeaBIOS

**Spec:** `docs/superpowers/specs/2026-09-22-install-media-design.md`,
phase 3, and the `ufs.py` and `label.py` rows of *Host builder*.

## Already verified

Every source file in this plan was prototyped before the plan was written.
All 45 `instmedia` tests pass. On the i386 guest, `fsck -n` came back clean
on both sample images. The executor still runs everything again. These are
the expected results:

- **Geometry:** every superblock geometry field equals what Apple's `newfs`
  wrote on `golden.img`, the DR2 install floppy and the DR2 CD.
- **Superblock:** `ufs.superblock()` is byte-identical to all three
  references over `fs_sbsize` bytes. The only exceptions are four fields the
  kernel rewrites at mount time: `fs_fsmnt`, `fs_cgrotor`, `fs_csp` and
  `fs_maxcluster`, at bytes 212 to 855.
- **Labels:** `label.label()` is byte-identical to the labels on `golden.img`
  and the install floppy.
- **fdisk512 gate:** `fsck -n /dev/rhd1a` ran all five phases with no
  complaints and printed
  `1805 files, 16558 used, 46801 free (9 frags, 5849 blocks, 0.0% fragmentation)`.
- **cd2048 gate:** the same check printed
  `8077 files, 32872 used, 96143 free (3 frags, 24035 blocks, 0.0% fragmentation)`.

## Global Constraints

- **Worktree.** Work in a git worktree, not the shared checkout:
  `git worktree add -b install-media-p3 .claude/worktrees/install-media-p3 HEAD`.
  Parallel sessions share the main checkout's git index, so stage explicit
  paths only and never run a bare `git stash`.
- **Run tests from the worktree's `vm/`.** Use
  `RHAPSODY_MEDIA_DIR=D:/RhapsodiOS/vm python -m unittest instmedia.<module> -v`.
- **Reference images live in the main checkout.** They are gitignored, so a
  worktree has none, and without `RHAPSODY_MEDIA_DIR` the oracle tests skip.
  For this plan a skip counts as a failure: in `-v` output,
  `TestAgainstAppleNewfs`, `TestAgainstDiskI` and `TestLayoutAgainstNewfs`
  must say `ok`, never `skipped`.
- **References are read, never written or booted.** That covers
  `vm/golden.img`, `vm/install/rhapsody_dr2_x86_InstallationFloppy.img` and
  `vm/install/rhapsody_dr2_x86.iso`. Spec: "No Apple bits. Every byte on the
  media comes from our apks or our own builds … No DR2 media and no
  `golden.img` are used, not even as templates." The writer takes nothing
  from them. Only the tests compare against them.
- **Spec, phase 3 row, done when:** "Round-trips through `rhap_image` with
  label `secsize` 512 (fdisk disk) and 2048 (CD); `fsck -n` passes on its
  output in a guest".
- **Spec, phase 3 host tests:** "`unittest`: `rhap_image` round-trip with
  label `secsize` 512 and 2048, with several cylinder groups, symlinks, hard
  links, device nodes and double-indirect files".
- **Spec, `ufs.py` row:** "Computes geometry the way `newfs` would (bsize
  8192, fsize 1024 or 2048), handles several cylinder groups and single and
  double indirect blocks, and supports symlinks, hard links and device
  nodes. Little-endian by default, like DR2 media." Little-endian is the
  only byte order written. Nothing in phase 3 needs big-endian.
- **Spec, rules:** "Standard library only." "Deterministic output: sorted
  walks, apk mtimes preserved, no host timestamps." The writer stamps the
  `now` it is given, never the host clock.
- **Spec, "Left as it is":** `vm/ufs_build.py` and the injection tooling.
  `ufs_build.py`, `ufs_cg.py`, `ufs_check.py`, `ufs_extract.py` and
  `rhap_image.py` are imported unchanged.
- **Two path spellings.** Shell tools take `/d/RhapsodiOS/...`. Python on
  Windows needs `D:/RhapsodiOS/...`, because a `/d/...` path names nothing
  there.
- **QEMU boots go only through `vm/qemu_boot.py`,** which opens every drive
  with `-snapshot`.
  - The one boot disk is `D:/RhapsodiOS/vm/work/p1-eide.img`, the fixture
    phase 1 kept.
  - Never boot `golden.img`, `rhapsody.vmdk` or `vm/work/test.img`.
  - Sample images are written fresh for each run under the worktree's
    `vm/work/p3-gate/` (CLAUDE.md §6).
- **Style.**
  - Match `vm/`: 4-space indents, lines of 79 columns or fewer, docstrings,
    and `%` formatting.
  - Use LF line endings. On Windows, Python's text mode writes CRLF, so
    create and change files with the editor tools, not ad-hoc scripts.
- **Commits** follow CLAUDE.md §5.
  - One or two lines, starting with `vm:` or `docs:` and saying what
    changed.
  - No trailers or other metadata.

## File structure

| File | Status | Responsibility |
|---|---|---|
| `vm/instmedia/__init__.py` | create | Package marker |
| `vm/instmedia/ufs_geometry.py` | create | `newfs`'s geometry arithmetic (`mkfs.c`), and superblock field offsets |
| `vm/instmedia/test_ufs_geometry.py` | create | Geometry against three Apple-made filesystems |
| `vm/instmedia/label.py` | create | `dlV3` label encoder and placement |
| `vm/instmedia/test_label.py` | create | Labels against `golden.img`'s and the DR2 media's |
| `vm/instmedia/space.py` | create | Free-space allocator for a fresh filesystem |
| `vm/instmedia/test_space.py` | create | Allocator tests |
| `vm/instmedia/ufs.py` | create | The writer |
| `vm/instmedia/test_ufs.py` | create | Superblock and cylinder-group layout against the references; tree checks |
| `vm/instmedia/readback.py` | create | Read an image back and diff it against its tree |
| `vm/instmedia/sample.py` | create | The two phase 3 images, and a CLI that writes them |
| `vm/instmedia/test_sample.py` | create | Round trips through `rhap_image` and `ufs_check` |
| `vm/qemu_boot.py` | modify | `--hd1 IMAGE` and `--type SECONDS:TEXT` |
| `vm/test_qemu_boot.py` | modify | Tests for both |
| `docs/build/instmedia-ufs.md` | create | What the writer does, how it is checked, and the gate's results |
| `docs/superpowers/specs/2026-09-22-install-media-design.md` | modify | Host-builder table: the new modules |

## Background for implementers

- **Node model:** nodes are `ufs_extract.Node(path, kind, mode, uid, gid, mtime, data)`.
  `kind` is one of:

  | kind | `data` |
  |---|---|
  | `dir` | `None` |
  | `reg` | bytes |
  | `lnk` | the target, as a str |
  | `chr`, `blk` | `(major, minor)` |
  | `hlink` | the path of another, non-directory node |

  `nodes[0]` is the root directory `/`.
- **Units:**
  - The superblock counts in fragments (`fs_fsize` bytes).
  - The label counts in `secsize` sectors.
  - Label copies sit at 512-byte physical block numbers.
  - `di_blocks` counts `secsize` sectors, which is fragments × `fs_nspf`.
- **Layout on disk:**
  - Inode `n` lives in cylinder group `n // fs_ipg`.
  - A device inode keeps `(major << 8) | minor` in `di_db[0]`. The fixture's
    `/private/dev/rhd1a` is `0xf08`.
  - A symlink whose target is shorter than 60 bytes is stored inline in the
    inode, over `di_db` and `di_ib`.
- **fsck's two comparisons that the writer must match:**
  - Pass 5 rebuilds every cylinder group from scratch and compares it with
    what is on disk: header, summaries and maps.
  - `readsb` compares the primary superblock with the copy in the last
    cylinder group.

  That is why every group's header follows `initcg()` exactly, and every
  superblock copy is identical.

---

### Task 1: Package and `newfs` geometry

**Files:**
- Create: `vm/instmedia/__init__.py`
- Create: `vm/instmedia/ufs_geometry.py`
- Test: `vm/instmedia/test_ufs_geometry.py`

**Interfaces:**
- Consumes:
  - `rhap_image.Image(path)`, with `.part_start` and `._read_at(offset, n)`
  - `rhap_image.SBOFF` (8192)
- Produces:
  - `ufs_geometry.geometry(fssize, secsize, nsect, ntrak, rpm, bsize=8192, fsize=1024, cpg=16)`
    returns a `Geometry` namedtuple. Its fields are the ones in `FIELDS`,
    including `fssize`, `secsize`, `size`, `ncg`, `fpg`, `ipg`, `frag`,
    `nspf`, `nindir`, `csaddr`, `cssize`, `sbsize`, `postbl`, `rotbl`,
    `minfree` and `maxsymlinklen`. It raises `GeometryError`.
  - Helpers, each taking `(g, c)` and returning a fragment number: `cgstart`,
    `cgbase`, `cgsblock`, `cgtod`, `cgimin`, `cgdmin` and `cg_data_end`.
  - `howmany(x, y)` and `roundup(x, y)`.
  - Constants: `SB_OFFSETS` (int32 field → byte offset), `SB_QUAD_OFFSETS`,
    `BBSIZE`, `NDADDR`, `NIADDR`, `DINODE_SIZE`, `MAXFRAG` and `SIZEOF_CG`.
  - The test module's `MEDIA` and `REFERENCES`, which Task 4's tests import.

- [ ] **Step 1: Create the worktree**

```bash
cd /d/RhapsodiOS
git worktree add -b install-media-p3 .claude/worktrees/install-media-p3 HEAD
cd .claude/worktrees/install-media-p3
```

Every later command runs inside this worktree.

- [ ] **Step 2: Write the package marker and the failing test**

`vm/instmedia/__init__.py`:

```python
"""Host-side tools that build RhapsodiOS install media."""
```

`vm/instmedia/test_ufs_geometry.py`:

```python
import os
import struct
import unittest

import rhap_image
from instmedia import ufs_geometry

HERE = os.path.dirname(os.path.abspath(__file__))
VM = os.path.dirname(HERE)
MEDIA = os.environ.get("RHAPSODY_MEDIA_DIR", VM)

REFERENCES = [
    ("golden.img",
     dict(fssize=8217087, secsize=1024, nsect=63, ntrak=16, rpm=3600)),
    (os.path.join("install", "rhapsody_dr2_x86_InstallationFloppy.img"),
     dict(fssize=1344, secsize=1024, nsect=9, ntrak=2, rpm=300, cpg=128)),
    (os.path.join("install", "rhapsody_dr2_x86.iso"),
     dict(fssize=300000, secsize=2048, nsect=64, ntrak=32, rpm=300,
          fsize=2048)),
]


def _superblock(path):
    with rhap_image.Image(path) as img:
        return img._read_at(img.part_start + rhap_image.SBOFF,
                            rhap_image.SBOFF)


class TestAgainstAppleNewfs(unittest.TestCase):
    """Every geometry field must equal what Apple's newfs wrote."""

    def _check(self, name, params):
        path = os.path.join(MEDIA, name)
        if not os.path.exists(path):
            self.skipTest("%s not present (set RHAPSODY_MEDIA_DIR)" % path)
        sb = _superblock(path)
        g = ufs_geometry.geometry(**params)
        for field, off in ufs_geometry.SB_OFFSETS.items():
            self.assertEqual(getattr(g, field),
                             struct.unpack_from("<i", sb, off)[0], field)
        for field, off in ufs_geometry.SB_QUAD_OFFSETS.items():
            self.assertEqual(getattr(g, field),
                             struct.unpack_from("<q", sb, off)[0], field)
        if g.cpc:
            n = g.cpc * g.nrpos
            self.assertEqual(
                g.postbl, struct.unpack_from("<%dh" % n, sb, g.postbloff))
            self.assertEqual(
                bytes(v & 0xff for v in g.rotbl),
                sb[g.rotbloff:g.rotbloff + len(g.rotbl)])

    def test_golden(self):
        self._check(*REFERENCES[0])

    def test_install_floppy(self):
        self._check(*REFERENCES[1])

    def test_dr2_cd(self):
        self._check(*REFERENCES[2])


class TestProjectGeometries(unittest.TestCase):
    """Pinned results for the two shapes this project writes."""

    def test_fdisk_disk_512(self):
        # 64 MB partition, QEMU IDE geometry, 512-byte label sectors.
        g = ufs_geometry.geometry(fssize=131072, secsize=512, nsect=63,
                                  ntrak=16, rpm=3600)
        self.assertEqual((g.nspf, g.fsbtodb, g.sblkno, g.cblkno, g.iblkno),
                         (2, 1, 16, 24, 32))
        self.assertEqual((g.cpg, g.fpg, g.ipg, g.ncg, g.size, g.dblkno),
                         EXPECTED_512)

    def test_cd_2048(self):
        # 256 MB volume, the DR2 CD's geometry.
        g = ufs_geometry.geometry(fssize=131072, secsize=2048, nsect=64,
                                  ntrak=32, rpm=300, fsize=2048)
        self.assertEqual((g.nspf, g.fsbtodb, g.sblkno, g.cblkno, g.iblkno),
                         (1, 0, 8, 12, 16))
        self.assertEqual((g.cpg, g.fpg, g.ipg, g.ncg, g.size, g.dblkno),
                         EXPECTED_2048)

    def test_cg_helpers(self):
        g = ufs_geometry.geometry(fssize=131072, secsize=512, nsect=63,
                                  ntrak=16, rpm=3600)
        self.assertEqual(ufs_geometry.cgstart(g, 0), 0)
        self.assertEqual(ufs_geometry.cgsblock(g, 0), g.sblkno)
        self.assertEqual(ufs_geometry.cgdmin(g, 1),
                         g.fpg + g.cgoffset * (1 & ~g.cgmask) + g.dblkno)
        self.assertEqual(ufs_geometry.cg_data_end(g, g.ncg - 1), g.size)


class TestRefusals(unittest.TestCase):
    def test_fragment_smaller_than_sector(self):
        with self.assertRaises(ufs_geometry.GeometryError):
            ufs_geometry.geometry(fssize=131072, secsize=2048, nsect=64,
                                  ntrak=32, rpm=300, fsize=1024)

    def test_block_larger_than_maxbsize(self):
        with self.assertRaises(ufs_geometry.GeometryError):
            ufs_geometry.geometry(fssize=131072, secsize=512, nsect=63,
                                  ntrak=16, rpm=3600, bsize=16384,
                                  fsize=2048)

    def test_too_small(self):
        with self.assertRaises(ufs_geometry.GeometryError):
            ufs_geometry.geometry(fssize=64, secsize=512, nsect=63,
                                  ntrak=16, rpm=3600)


# (cpg, fpg, ipg, ncg, size, dblkno), from this port once it matched all
# three reference media.
EXPECTED_512 = (16, 8064, 1792, 9, 65536, 256)
EXPECTED_2048 = (16, 32768, 8064, 4, 131072, 520)

if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd vm && RHAPSODY_MEDIA_DIR=D:/RhapsodiOS/vm python -m unittest instmedia.test_ufs_geometry -v`
Expected: an import error, `ImportError: cannot import name 'ufs_geometry'`.

- [ ] **Step 4: Write `vm/instmedia/ufs_geometry.py`**

```python
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
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd vm && RHAPSODY_MEDIA_DIR=D:/RhapsodiOS/vm python -m unittest instmedia.test_ufs_geometry -v`
Expected: `Ran 9 tests`, `OK`. `test_golden`, `test_install_floppy` and
`test_dr2_cd` each say `ok`, not `skipped`.

- [ ] **Step 6: Commit**

```bash
git add vm/instmedia/__init__.py vm/instmedia/ufs_geometry.py vm/instmedia/test_ufs_geometry.py
git commit -m "vm: port newfs's geometry arithmetic, matching three Apple-made filesystems"
```

---

### Task 2: NeXT labels

**Files:**
- Create: `vm/instmedia/label.py`
- Test: `vm/instmedia/test_label.py`

**Interfaces:**
- Consumes:
  - `ufs_build.label_checksum(buf)`, and `ufs_build.LABEL_CHECKSUM` (0x22e,
    the checksum's byte offset)
  - `ufs_geometry.geometry()` and its `Geometry` fields, from Task 1
- Produces:
  - `label.label(secsize, ntracks, nsectors, ncylinders, rpm, front, p_base, p_size, bsize, fsize, cpg, density, minfree, name, d_name, d_type, boot0=(-1, -1), tag=0)`
    returns 1024 bytes: checksummed, with `dl_label_blkno` still 0.
  - `label.for_filesystem(g, front, p_base, ncylinders, name, d_type)`
    returns the same, filled in from a `Geometry`.
  - `label.place(f, lbl, copies, relsect=0)` writes each copy at byte
    `(relsect + blk) * 512` with `dl_label_blkno = relsect + blk`.
  - Constants `DISK_COPIES = (15, 30, 45)` and `CD_COPIES = (0, 15, 30, 45)`,
    and the exception `LabelError`.

- [ ] **Step 1: Write the failing test**

`vm/instmedia/test_label.py`:

```python
import io
import os
import struct
import unittest

import ufs_build
from instmedia import label, ufs_geometry

HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.environ.get("RHAPSODY_MEDIA_DIR", os.path.dirname(HERE))

GOLDEN = dict(
    secsize=1024, ntracks=16, nsectors=63, ncylinders=16383, rpm=3600,
    front=160, p_base=0, p_size=8217087, bsize=8192, fsize=1024, cpg=16,
    density=4096, minfree=10, name="Disk", d_name="Type 255-512",
    d_type="fixed_rw_ide", boot0=(32, 96), tag=0xac86a6f8)
FLOPPY = dict(
    secsize=1024, ntracks=2, nsectors=9, ncylinders=80, rpm=300,
    front=96, p_base=0, p_size=1344, bsize=8192, fsize=1024, cpg=32,
    density=2048, minfree=0, name="RhapsodyInstall",
    d_name="Floppy Drive-512", d_type="removable_rw_floppy",
    boot0=(32, -1), tag=0xf16809dc)
CD = dict(
    secsize=2048, ntracks=32, nsectors=64, ncylinders=1024, rpm=300,
    front=160, p_base=160, p_size=300000, bsize=8192, fsize=2048, cpg=16,
    density=4096, minfree=10, name="RhapsodyDR2", d_name="RhapsodyDR2",
    d_type="removable_rw_scsi", boot0=(32, 96), tag=0xe662b8f6)


def _reference(name, blk):
    path = os.path.join(MEDIA, name)
    if not os.path.exists(path):
        raise unittest.SkipTest("%s not present (set RHAPSODY_MEDIA_DIR)"
                                % path)
    with open(path, "rb") as f:
        f.seek(blk * 512)
        return f.read(label.LABEL_SIZE)


def _placed(lbl, blk):
    f = io.BytesIO()
    label.place(f, lbl, (blk,))
    return f.getvalue()[blk * 512:blk * 512 + label.LABEL_SIZE]


class TestAgainstDiskI(unittest.TestCase):
    """The encoder must reproduce labels disk -i wrote."""

    def test_golden(self):
        self.assertEqual(_placed(label.label(**GOLDEN), 15),
                         _reference("golden.img", 15))

    def test_install_floppy(self):
        self.assertEqual(
            _placed(label.label(**FLOPPY), 15),
            _reference(os.path.join(
                "install", "rhapsody_dr2_x86_InstallationFloppy.img"), 15))

    def test_dr2_cd_header_and_partition_a(self):
        # The CD's unused entries carry p_cpg 0 where disk -i writes -1, so
        # compare everything up to the end of partition a.
        ref = _reference(os.path.join("install", "rhapsody_dr2_x86.iso"), 0)
        self.assertEqual(_placed(label.label(**CD), 0)[:236], ref[:236])


class TestPlace(unittest.TestCase):
    def test_fdisk_copies_are_absolute_and_checksummed(self):
        lbl = label.label(**GOLDEN)
        f = io.BytesIO()
        label.place(f, lbl, label.DISK_COPIES, relsect=2048)
        raw = f.getvalue()
        for blk in label.DISK_COPIES:
            copy = raw[(2048 + blk) * 512:(2048 + blk) * 512 + 1024]
            self.assertEqual(copy[:4], b"dlV3")
            self.assertEqual(struct.unpack_from(">i", copy, 4)[0], 2048 + blk)
            self.assertEqual(
                struct.unpack_from(">H", copy, ufs_build.LABEL_CHECKSUM)[0],
                ufs_build.label_checksum(copy))

    def test_cd_copies_include_block_zero(self):
        f = io.BytesIO()
        label.place(f, label.label(**CD), label.CD_COPIES)
        raw = f.getvalue()
        self.assertEqual([struct.unpack_from(">i", raw, b * 512 + 4)[0]
                          for b in label.CD_COPIES], [0, 15, 30, 45])


class TestForFilesystem(unittest.TestCase):
    def test_fills_partition_a_from_the_geometry(self):
        g = ufs_geometry.geometry(fssize=8217087, secsize=1024, nsect=63,
                                  ntrak=16, rpm=3600)
        self.assertEqual(
            label.for_filesystem(g, front=160, p_base=0, ncylinders=16383,
                                 name="Disk", d_type="fixed_rw_ide"),
            label.label(**dict(GOLDEN, minfree=5, d_name="Disk",
                               boot0=(-1, -1), tag=0)))


class TestRefusals(unittest.TestCase):
    def test_name_too_long(self):
        with self.assertRaises(label.LabelError):
            label.label(**dict(GOLDEN, name="x" * 24))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd vm && RHAPSODY_MEDIA_DIR=D:/RhapsodiOS/vm python -m unittest instmedia.test_label -v`
Expected: `ImportError: cannot import name 'label'`.

- [ ] **Step 3: Write `vm/instmedia/label.py`**

```python
"""NeXT dlV3 disk labels, as `disk -i` writes them.

Layout from src/kernel-7/bsd/dev/disk_label.h and sys/disktab.h, big-endian
and packed the way the m68k compiler packed it (no padding before an int).
Only partition a is used; the other seven entries hold the pattern disk -i
leaves in them.  Checked byte for byte against golden.img's label and the DR2
install floppy's.
"""
import struct

import ufs_build

LABEL_SIZE = 1024       # bytes per copy; only the first 560 are ever non-zero
DISK_COPIES = (15, 30, 45)
# A CD needs the copy at 0 too: the kernel reads it in 2048-byte blocks, and
# the others are not on a 2048-byte boundary.
CD_COPIES = (0, 15, 30, 45)

_PART_OFF = 190
_PART_SIZE = 46
_NPART = 8
_UNUSED_PART = b"\xff" * 12 + b"\0\0" + b"\xff" * 5 + b"\0" * 27


class LabelError(Exception):
    pass


def _cstr(text, size):
    raw = text.encode("ascii")
    if len(raw) >= size:
        raise LabelError("%r does not fit in %d bytes with its NUL"
                         % (text, size))
    return raw.ljust(size, b"\0")


def label(secsize, ntracks, nsectors, ncylinders, rpm, front, p_base, p_size,
          bsize, fsize, cpg, density, minfree, name, d_name, d_type,
          boot0=(-1, -1), tag=0):
    """One label copy, checksummed, with dl_label_blkno still 0.

    p_base and front are in secsize sectors, and on an fdisk disk p_base is
    absolute (it includes the 0xA7 partition's start), as disk -i -b writes
    it.  boot0 is d_boot0_blkno; (-1, -1) says there are no boot blocks.
    """
    buf = bytearray(LABEL_SIZE)
    struct.pack_into(">4sii24sII", buf, 0, b"dlV3", 0, 0, _cstr(name, 24),
                     0, tag)
    struct.pack_into(">24s24s5i6h2i24s32scc", buf, 44,
                     _cstr(d_name, 24), _cstr(d_type, 24),
                     secsize, ntracks, nsectors, ncylinders, rpm,
                     front, 0, 0, 0, 0, 0, boot0[0], boot0[1],
                     _cstr("mach_kernel", 24), _cstr("localhost", 32),
                     b"a", b"b")
    struct.pack_into(">iihhcxhhbb16sb8sx", buf, _PART_OFF,
                     p_base, p_size, bsize, fsize, b"t", cpg, density,
                     minfree, 1, b"", 1, _cstr("4.4BSD", 8))
    for n in range(1, _NPART):
        off = _PART_OFF + n * _PART_SIZE
        buf[off:off + _PART_SIZE] = _UNUSED_PART
    struct.pack_into(">H", buf, ufs_build.LABEL_CHECKSUM,
                     ufs_build.label_checksum(buf))
    return bytes(buf)


def for_filesystem(g, front, p_base, ncylinders, name, d_type):
    """The label for a filesystem of ufs_geometry g, as disk -i would write
    it after newfs: partition a covers g.fssize sectors from p_base, and
    carries g's block, fragment and cylinder-group sizes, newfs's default
    density and g's minfree.  No boot blocks."""
    return label(secsize=g.secsize, ntracks=g.ntrak, nsectors=g.nsect,
                 ncylinders=ncylinders, rpm=g.rpm, front=front,
                 p_base=p_base, p_size=g.fssize, bsize=g.bsize,
                 fsize=g.fsize, cpg=g.cpg, density=4 * g.fsize,
                 minfree=g.minfree, name=name, d_name=name, d_type=d_type)


def place(f, lbl, copies, relsect=0):
    """Write lbl at each copy's 512-byte block, counted from relsect.

    check_label only accepts a copy whose dl_label_blkno is the physical
    block it was read from, so each copy gets its own; the checksum does not
    cover that field.
    """
    for blk in copies:
        buf = bytearray(lbl)
        struct.pack_into(">i", buf, 4, relsect + blk)
        f.seek((relsect + blk) * 512)
        f.write(buf)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd vm && RHAPSODY_MEDIA_DIR=D:/RhapsodiOS/vm python -m unittest instmedia.test_label -v`
Expected: `Ran 7 tests`, `OK`, with the three `TestAgainstDiskI` tests `ok`.

- [ ] **Step 5: Commit**

```bash
git add vm/instmedia/label.py vm/instmedia/test_label.py
git commit -m "vm: write NeXT dlV3 labels byte-identical to what disk -i writes"
```

---

### Task 3: Free-space allocator

**Files:**
- Create: `vm/instmedia/space.py`
- Test: `vm/instmedia/test_space.py`

**Interfaces:**
- Consumes: `ufs_geometry` from Task 1: `geometry`, `cgbase`, `cgsblock`,
  `cgdmin`, `cg_data_end`, `howmany` and `roundup`.
- Produces:
  - `space.Space(g)`, with these methods:
    - `.block()` returns the first fragment of a free, block-aligned whole
      block.
    - `.frags(n)` returns the first of `n` contiguous fragments, where
      `0 < n < g.frag`, all inside one block.
    - `.blksfree(c)` returns group `c`'s free map as `cg_blksfree` stores
      it, as bytes.
  - `.free`, a bytearray with one byte per fragment, 1 while the fragment is
    free.
  - `space.NoSpace`, raised when the filesystem is full.

- [ ] **Step 1: Write the failing test**

`vm/instmedia/test_space.py`:

```python
import unittest

from instmedia import ufs_geometry as ug
from instmedia.space import NoSpace, Space

# 64 MB, 512-byte sectors: 9 groups, cssize one fragment, so group 0's data
# starts one fragment past a block boundary.
G = ug.geometry(fssize=131072, secsize=512, nsect=63, ntrak=16, rpm=3600)


class TestSpace(unittest.TestCase):
    def test_initial_free_regions_match_initcg(self):
        s = Space(G)
        first = G.csaddr + ug.howmany(G.cssize, G.fsize)
        self.assertEqual(s.free[first - 1], 0)
        self.assertEqual(s.free[first], 1)
        # Group 1: free before its superblock copy, used through dmin.
        self.assertEqual(s.free[ug.cgbase(G, 1)], 1)
        self.assertEqual(s.free[ug.cgsblock(G, 1) - 1], 1)
        self.assertEqual(s.free[ug.cgsblock(G, 1)], 0)
        self.assertEqual(s.free[ug.cgdmin(G, 1) - 1], 0)
        self.assertEqual(s.free[ug.cgdmin(G, 1)], 1)
        self.assertEqual(sum(s.free), G.dsize)

    def test_blocks_are_aligned_and_ascending(self):
        s = Space(G)
        a, b = s.block(), s.block()
        self.assertEqual(a % G.frag, 0)
        self.assertEqual(b, a + G.frag)
        self.assertEqual(a, ug.roundup(G.csaddr + 1, G.frag))

    def test_tails_pack_into_one_block(self):
        s = Space(G)
        t1 = s.frags(3)
        t2 = s.frags(5)
        self.assertEqual(t2, t1 + 3)
        t3 = s.frags(1)                     # block is full: a new one
        self.assertEqual(t3 % G.frag, 0)
        self.assertNotEqual(t3 // G.frag, t1 // G.frag)

    def test_blocks_skip_group_metadata(self):
        s = Space(G)
        got = [s.block() for _ in range(G.dsize // G.frag - 8)]
        for c in range(1, G.ncg):
            meta = range(ug.cgsblock(G, c), ug.cgdmin(G, c))
            self.assertFalse(any(b in meta for b in got))

    def test_full(self):
        s = Space(G)
        with self.assertRaises(NoSpace):
            for _ in range(G.dsize):
                s.block()

    def test_blksfree_bit_order(self):
        s = Space(G)
        bits = s.blksfree(1)
        self.assertEqual(bits[0] & 1, 1)                # cgbase(1) is free
        i = ug.cgsblock(G, 1) - ug.cgbase(G, 1)
        self.assertEqual((bits[i >> 3] >> (i & 7)) & 1, 0)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd vm && python -m unittest instmedia.test_space -v`
Expected: `ModuleNotFoundError: No module named 'instmedia.space'`.

- [ ] **Step 3: Write `vm/instmedia/space.py`**

```python
"""Free space in a fresh filesystem, handed out in ascending order.

The free regions are the ones initcg() leaves free (mkfs.c): in cylinder
group 0 everything from the end of the cylinder summary to the end of the
group, and in every later group also the stretch before its superblock
copy.  Whole blocks come out block-aligned; file tails are packed into
partly used blocks.  Nothing is ever freed.
"""
from instmedia import ufs_geometry as ug


class NoSpace(Exception):
    pass


class Space(object):
    def __init__(self, g):
        self.g = g
        # One byte per fragment of every group, 1 while it is free.
        self.free = bytearray(g.ncg * g.fpg)
        self._extents = []
        for c in range(g.ncg):
            if c > 0:
                self._extents.append((ug.cgbase(g, c), ug.cgsblock(g, c)))
            lo = ug.cgdmin(g, c)
            if c == 0:
                lo += ug.howmany(g.cssize, g.fsize)
            self._extents.append((lo, ug.cg_data_end(g, c)))
        for lo, hi in self._extents:
            self.free[lo:hi] = b"\x01" * (hi - lo)
        self._i = 0
        self._pos = 0
        self._tail = None       # (next fragment, end of block) for tails

    def _next_block(self):
        frag = self.g.frag
        while self._i < len(self._extents):
            lo, hi = self._extents[self._i]
            start = ug.roundup(max(self._pos, lo), frag)
            if start + frag <= hi:
                self._pos = start + frag
                return start
            self._i += 1
        raise NoSpace("the filesystem is full")

    def _claim(self, start, n):
        self.free[start:start + n] = bytes(n)
        return start

    def block(self):
        """First fragment of a free, block-aligned whole block."""
        return self._claim(self._next_block(), self.g.frag)

    def frags(self, n):
        """First of n < fs_frag contiguous free fragments inside one block."""
        if not 0 < n < self.g.frag:
            raise ValueError("a tail is 1 to %d fragments, not %d"
                             % (self.g.frag - 1, n))
        if self._tail is None or self._tail[0] + n > self._tail[1]:
            b = self._next_block()
            self._tail = (b, b + self.g.frag)
        start = self._tail[0]
        self._tail = (start + n, self._tail[1])
        return self._claim(start, n)

    def blksfree(self, c):
        """Group c's free-fragment bitmap, as cg_blksfree stores it."""
        base = ug.cgbase(self.g, c)
        out = bytearray(ug.howmany(self.g.fpg, 8))
        for i in range(self.g.fpg):
            if self.free[base + i]:
                out[i >> 3] |= 1 << (i & 7)
        return bytes(out)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd vm && python -m unittest instmedia.test_space -v`
Expected: `Ran 6 tests`, `OK`.

- [ ] **Step 5: Commit**

```bash
git add vm/instmedia/space.py vm/instmedia/test_space.py
git commit -m "vm: hand out a fresh UFS's free space the way initcg leaves it"
```

---

### Task 4: The UFS writer

**Files:**
- Create: `vm/instmedia/ufs.py`
- Test: `vm/instmedia/test_ufs.py`

**Interfaces:**
- Consumes:
  - `ufs_cg.recompute_cg_tables(g, blksfree)` and
    `ufs_cg.recompute_cluster_maps(g, blksfree, nclusterblks)`. They read
    only `Geometry` attributes that Task 1's namedtuple also has.
  - `space.Space` from Task 3.
  - `ufs_geometry` from Task 1.
  - `test_ufs_geometry.MEDIA` and `test_ufs_geometry.REFERENCES`, from
    Task 1.
- Produces:
  - `ufs.write(f, offset, g, nodes, now)` writes the whole filesystem into
    the file object `f`, starting at byte `offset`. It raises
    `ufs.TreeError` for a malformed tree, and `space.NoSpace` when the tree
    doesn't fit.
  - `ufs.superblock(g, now, cstotal)` returns `g.sbsize` bytes.
  - `ufs.cg_offsets(g)` returns a 7-tuple.
  - `ufs.cg_block(g, c, now, blksfree, inosused, ndir, nifree)` returns
    `(bytes, csum)`.
  - Constants: `SBOFF`, `ROOTINO`, `DIRBLKSIZ`, `CG_MAGIC`, `IFMT` and
    `DTYPE`, the last two keyed by kind.

- [ ] **Step 1: Write the failing test**

`vm/instmedia/test_ufs.py`:

```python
import os
import struct
import unittest

import rhap_image
from ufs_extract import Node
from instmedia import ufs, ufs_geometry as ug
from instmedia.test_ufs_geometry import MEDIA, REFERENCES

# The superblock fields the kernel rewrites at mount time -- fs_fsmnt,
# fs_cgrotor, fs_csp and fs_maxcluster -- which fsck's alternate-superblock
# check also skips.
MOUNT_FIELDS = slice(212, 856)
G512 = ug.geometry(fssize=131072, secsize=512, nsect=63, ntrak=16, rpm=3600)


def _open(name):
    path = os.path.join(MEDIA, name)
    if not os.path.exists(path):
        raise unittest.SkipTest("%s not present (set RHAPSODY_MEDIA_DIR)"
                                % path)
    return rhap_image.Image(path)


class TestLayoutAgainstNewfs(unittest.TestCase):
    """The metadata newfs wrote, reproduced from the geometry alone."""

    def _superblock(self, name, params):
        g = ug.geometry(**params)
        with _open(name) as img:
            ref = bytearray(img._read_at(img.part_start + ufs.SBOFF,
                                         g.sbsize))
        mine = bytearray(ufs.superblock(
            g, struct.unpack_from("<i", ref, 32)[0],
            struct.unpack_from("<4i", ref, 192)))
        self.assertEqual(bytes(mine[MOUNT_FIELDS]), bytes(856 - 212))
        ref[MOUNT_FIELDS] = bytes(856 - 212)
        self.assertEqual(mine, ref)

    def _cg_headers(self, name, params):
        g = ug.geometry(**params)
        with _open(name) as img:
            for c in (0, g.ncg - 1):
                ref = img._read_at(
                    img.part_start + ug.cgtod(g, c) * g.fsize, g.bsize)
                ndblk = ug.cg_data_end(g, c) - ug.cgbase(g, c)
                ncyl = g.ncyl % g.cpg if c == g.ncg - 1 else g.cpg
                self.assertEqual(struct.unpack_from("<iihhi", ref, 4)[0],
                                 ufs.CG_MAGIC)
                self.assertEqual(struct.unpack_from("<ihhi", ref, 12),
                                 (c, ncyl, g.ipg, ndblk))
                self.assertEqual(struct.unpack_from("<7i", ref, 84),
                                 ufs.cg_offsets(g))
                self.assertEqual(struct.unpack_from("<i", ref, 112)[0],
                                 ndblk // g.frag)

    def test_golden(self):
        self._superblock(*REFERENCES[0])
        self._cg_headers(*REFERENCES[0])

    def test_install_floppy(self):
        self._superblock(*REFERENCES[1])
        self._cg_headers(*REFERENCES[1])

    def test_dr2_cd(self):
        self._superblock(*REFERENCES[2])
        self._cg_headers(*REFERENCES[2])


def _n(path, kind, data=None):
    return Node(path, kind, 0o755, 0, 0, 0, data)


class TestTreeChecks(unittest.TestCase):
    def _refuse(self, nodes):
        with self.assertRaises(ufs.TreeError):
            ufs._index(G512, nodes)

    def test_root_first(self):
        self._refuse([_n("/etc", "dir"), _n("/", "dir")])

    def test_duplicate(self):
        self._refuse([_n("/", "dir"), _n("/a", "reg", b""),
                      _n("/a", "reg", b"")])

    def test_orphan(self):
        self._refuse([_n("/", "dir"), _n("/no/such", "reg", b"")])

    def test_parent_is_a_file(self):
        self._refuse([_n("/", "dir"), _n("/a", "reg", b""),
                      _n("/a/b", "reg", b"")])

    def test_hard_link_to_directory(self):
        self._refuse([_n("/", "dir"), _n("/d", "dir"),
                      _n("/l", "hlink", "/d")])

    def test_unnormalised_path(self):
        self._refuse([_n("/", "dir"), _n("/a/", "dir")])

    def test_too_many_inodes(self):
        self._refuse([_n("/", "dir")]
                     + [_n("/f%d" % i, "reg", b"")
                        for i in range(G512.ncg * G512.ipg)])

    def test_link_counts(self):
        ino_of, _, _, nlink = ufs._index(G512, [
            _n("/", "dir"), _n("/d", "dir"), _n("/d/e", "dir"),
            _n("/f", "reg", b""), _n("/g", "hlink", "/f")])
        self.assertEqual(nlink[ino_of["/"]], 3)
        self.assertEqual(nlink[ino_of["/d"]], 3)
        self.assertEqual(nlink[ino_of["/d/e"]], 2)
        self.assertEqual(nlink[ino_of["/f"]], 2)
        self.assertEqual(ino_of["/g"], ino_of["/f"])


class TestDirData(unittest.TestCase):
    def test_entries_never_cross_a_chunk(self):
        entries = [(3 + i, b"name-%03d" % i, 8) for i in range(100)]
        data = ufs._dir_data(entries)
        self.assertEqual(len(data) % ufs.DIRBLKSIZ, 0)
        seen = []
        for chunk in range(0, len(data), ufs.DIRBLKSIZ):
            p = chunk
            while p < chunk + ufs.DIRBLKSIZ:
                ino, reclen, dtype, namlen = struct.unpack_from(
                    "<IHBB", data, p)
                self.assertEqual(reclen % 4, 0)
                seen.append(data[p + 8:p + 8 + namlen])
                p += reclen
            self.assertEqual(p, chunk + ufs.DIRBLKSIZ)
        self.assertEqual(seen, [name for _, name, _ in entries])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd vm && RHAPSODY_MEDIA_DIR=D:/RhapsodiOS/vm python -m unittest instmedia.test_ufs -v`
Expected: `ImportError: cannot import name 'ufs'`.

- [ ] **Step 3: Write `vm/instmedia/ufs.py`**

```python
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd vm && RHAPSODY_MEDIA_DIR=D:/RhapsodiOS/vm python -m unittest instmedia.test_ufs -v`
Expected: `Ran 12 tests`, `OK`, with the three `TestLayoutAgainstNewfs`
tests `ok`.

- [ ] **Step 5: Commit**

```bash
git add vm/instmedia/ufs.py vm/instmedia/test_ufs.py
git commit -m "vm: write node trees as multi-group UFS filesystems laid out as newfs does"
```

---

### Task 5: Read-back and the two sample images

**Files:**
- Create: `vm/instmedia/readback.py`
- Create: `vm/instmedia/sample.py`
- Test: `vm/instmedia/test_sample.py`

**Interfaces:**
- Consumes:
  - `rhap_image.Image`, which has `iter_dir`, `inode`, `read_file`,
    `readlink`, `frags`, `frag_offset`, `resolve`, `label` and `part_start`
  - `ufs_check.check(path)`, which returns a list of problems
  - `ufs_extract.Node`
  - From earlier tasks: `label.for_filesystem`, `label.place`,
    `label.DISK_COPIES`, `label.CD_COPIES`, `ufs.write`, `ufs.IFMT`,
    `ufs.DTYPE`, `ufs.ROOTINO` and `ufs_geometry`
- Produces:
  - `readback.diff(image_path, nodes)` returns a list of strings, empty when
    the image matches the tree.
  - `sample.tree(g)` returns a list of Nodes.
  - `sample.fdisk_disk(path, now=NOW)` and `sample.cd_volume(path, now=NOW)`
    each return `(g, nodes)`.
  - `python -m instmedia.sample OUTDIR` writes `OUTDIR/fdisk512.img` and
    `OUTDIR/cd2048.img`.

- [ ] **Step 1: Write the failing test**

`vm/instmedia/test_sample.py`:

```python
import os
import shutil
import tempfile
import unittest

import rhap_image
import ufs_check
from instmedia import readback, sample


class _RoundTrip(object):
    """Build one sample image and read it back every way we can."""

    build = None

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.path = os.path.join(cls.tmp, "sample.img")
        cls.g, cls.nodes = cls.build(cls.path)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def test_tree_reads_back(self):
        self.assertEqual(readback.diff(self.path, self.nodes), [])

    def test_allocation_accounting(self):
        self.assertEqual(ufs_check.check(self.path), [])

    def test_label_secsize(self):
        with rhap_image.Image(self.path) as img:
            self.assertEqual(img.label["secsize"], self.g.secsize)

    def test_covers_what_phase_3_requires(self):
        self.assertGreater(self.g.ncg, 1)
        with rhap_image.Image(self.path) as img:
            big = img.inode(img.resolve("/big"))
            self.assertNotEqual(big.ib[1], 0)       # double indirect
            groups = {f // self.g.fpg for f in img.frags(big)}
            self.assertGreater(len(groups), 1)
            last = img.resolve("/many/f%05d" % (self.g.ipg - 1))
            self.assertGreaterEqual(last // self.g.ipg, 1)

    def test_diff_notices_corruption(self):
        bad = os.path.join(self.tmp, "bad.img")
        shutil.copyfile(self.path, bad)
        with rhap_image.Image(bad) as img:
            frag = img.frags(img.inode(img.resolve("/etc/motd")))[0]
            where = img.frag_offset(frag)
        with open(bad, "r+b") as f:
            f.seek(where)
            f.write(b"w")
        self.assertEqual(readback.diff(bad, self.nodes),
                         ["/etc/motd: contents differ"])


class TestFdiskDisk512(_RoundTrip, unittest.TestCase):
    build = staticmethod(sample.fdisk_disk)


class TestCdVolume2048(_RoundTrip, unittest.TestCase):
    build = staticmethod(sample.cd_volume)


class TestMain(unittest.TestCase):
    def test_writes_both_images(self):
        tmp = tempfile.mkdtemp()
        try:
            self.assertEqual(sample.main(["sample", tmp]), 0)
            self.assertEqual(sorted(os.listdir(tmp)),
                             ["cd2048.img", "fdisk512.img"])
        finally:
            shutil.rmtree(tmp)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd vm && python -m unittest instmedia.test_sample -v`
Expected: `ImportError: cannot import name 'readback'`.

- [ ] **Step 3: Write `vm/instmedia/readback.py`**

```python
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
```

- [ ] **Step 4: Write `vm/instmedia/sample.py`**

```python
"""The two images phase 3 is checked with, holding a tree of every node kind.

    python -m instmedia.sample OUTDIR

writes OUTDIR/fdisk512.img, a disk with an MBR whose one 0xA7 partition
starts at LBA 2048 and holds a label with secsize 512 (what disk -i writes
on an fdisk disk), and OUTDIR/cd2048.img, a whole-medium label with secsize
2048 and fsize 2048, laid out like the DR2 CD.  Both filesystems have
several cylinder groups, and the tree is sized from the geometry so that
its inodes spill out of group 0 and one file needs double indirect blocks
and crosses a group boundary.
"""
import os
import struct
import sys

from ufs_extract import Node
from instmedia import label, ufs, ufs_geometry

NOW = 946684800             # 2000-01-01; nothing depends on the host clock
FRONT_BYTES = 160 * 1024    # front porch, the size golden.img's has
FDISK_RELSECT = 2048


def tree(g):
    """The sample tree for a filesystem of geometry g."""
    t = NOW - 86400
    big_blocks = max(ufs_geometry.NDADDR + g.nindir + 1,
                     g.fpg // g.frag + 1)
    big = b"".join(struct.pack("<I", i) * (g.bsize // 4)
                   for i in range(big_blocks)) + b"tail" * 25
    nodes = [
        Node("/", "dir", 0o755, 0, 0, t, None),
        Node("/bin", "dir", 0o755, 0, 0, t + 1, None),
        Node("/bin/sh", "reg", 0o555, 0, 0, t + 2,
             bytes(range(256)) * 11 + b"end"),
        Node("/bin/sh-again", "hlink", 0, 0, 0, 0, "/bin/sh"),
        Node("/etc", "dir", 0o755, 0, 0, t + 3, None),
        Node("/etc/motd", "reg", 0o644, 501, 20, t + 4,
             b"Welcome to RhapsodiOS.\n"),
        Node("/etc/empty", "reg", 0o600, 0, 0, t + 5, b""),
        Node("/etc/fast-link", "lnk", 0o755, 0, 0, t + 6, "../bin/sh"),
        Node("/etc/slow-link", "lnk", 0o755, 0, 0, t + 7,
             "/" + "/".join(["a-long-directory-name"] * 4)),
        Node("/dev", "dir", 0o755, 0, 0, t + 8, None),
        Node("/dev/rhd1a", "chr", 0o640, 0, 5, t + 9, (15, 8)),
        Node("/dev/hd1a", "blk", 0o640, 0, 5, t + 10, (3, 8)),
        Node("/dev/hd1a-again", "hlink", 0, 0, 0, 0, "/dev/hd1a"),
        Node("/big", "reg", 0o644, 0, 0, t + 11, big),
        Node("/many", "dir", 0o755, 0, 0, t + 12, None),
    ]
    nodes += [Node("/many/f%05d" % i, "reg", 0o644, 0, 0, t + 13, b"")
              for i in range(g.ipg)]
    return nodes


def fdisk_disk(path, now=NOW):
    """64 MB of UFS in an 0xA7 partition; returns (geometry, nodes)."""
    g = ufs_geometry.geometry(fssize=131072, secsize=512, nsect=63,
                              ntrak=16, rpm=3600)
    nodes = tree(g)
    front = FRONT_BYTES // 512
    nsect = front + g.fssize
    total = FDISK_RELSECT + nsect
    lbl = label.for_filesystem(g, front=front, p_base=FDISK_RELSECT,
                               ncylinders=total // g.spc,
                               name="instmedia sample", d_type="fixed_rw_ide")
    # The kernel and rhap_image read only an entry's type and start.
    mbr = bytearray(512)
    struct.pack_into("<B3sB3sII", mbr, 446, 0, b"", 0xA7, b"",
                     FDISK_RELSECT, nsect)
    mbr[510:512] = b"\x55\xaa"
    with open(path, "wb") as f:
        f.truncate(total * 512)
        f.write(mbr)
        label.place(f, lbl, label.DISK_COPIES, FDISK_RELSECT)
        ufs.write(f, (FDISK_RELSECT + front) * 512, g, nodes, now)
    return g, nodes


def cd_volume(path, now=NOW):
    """256 MB of UFS with fsize 2048 under a CD-style label."""
    g = ufs_geometry.geometry(fssize=131072, secsize=2048, nsect=64,
                              ntrak=32, rpm=300, fsize=2048)
    nodes = tree(g)
    front = FRONT_BYTES // 2048
    total = front + g.fssize
    lbl = label.for_filesystem(g, front=front, p_base=0,
                               ncylinders=ufs_geometry.howmany(total, g.spc),
                               name="instmedia sample",
                               d_type="removable_rw_scsi")
    with open(path, "wb") as f:
        f.truncate(total * 2048)
        label.place(f, lbl, label.CD_COPIES)
        ufs.write(f, front * 2048, g, nodes, now)
    return g, nodes


def main(argv):
    if len(argv) != 2:
        print("usage: python -m instmedia.sample OUTDIR")
        return 2
    os.makedirs(argv[1], exist_ok=True)
    for name, build in (("fdisk512.img", fdisk_disk),
                        ("cd2048.img", cd_volume)):
        path = os.path.join(argv[1], name)
        build(path)
        print("wrote %s" % path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd vm && python -m unittest instmedia.test_sample -v`
Expected: `Ran 11 tests`, `OK`, in roughly 5 to 10 seconds. The two images
are 65 MB and 256 MB, written to temp directories and then deleted.

- [ ] **Step 6: Run the whole package**

Run: `cd vm && RHAPSODY_MEDIA_DIR=D:/RhapsodiOS/vm python -m unittest instmedia.test_ufs_geometry instmedia.test_label instmedia.test_space instmedia.test_ufs instmedia.test_sample -v`
Expected: `Ran 45 tests`, `OK`, and no `skipped`.

- [ ] **Step 7: Commit**

```bash
git add vm/instmedia/readback.py vm/instmedia/sample.py vm/instmedia/test_sample.py
git commit -m "vm: read UFS images back against their trees, and build the phase 3 sample images"
```

---

### Task 6: A second disk and typing in `qemu_boot.py`

**Files:**
- Modify: `vm/qemu_boot.py`
- Test: `vm/test_qemu_boot.py`

**Interfaces:**
- Consumes: `qemu_shot.KEY_MAP` (character → list of qcodes; it has letters,
  digits, space, `-`, `_`, `=`, `"` and `\n` → `ret`), and `qemu_shot.QMP`.
- Produces:
  - `qemu_boot.parse_typed("SECONDS:TEXT")` returns `(float, str)`. It
    raises `ValueError` when the colon is missing, or when a character has
    no key.
  - `qemu_boot.build_args(..., esp=None, hd1=None, qemu=...)`.
    `qemu_boot.run(..., esp=None, hd1=None, typed=())`, where `typed` is a
    list of `(seconds, text)`.
  - CLI: `--hd1 IMAGE`, and `--type SECONDS:TEXT`, which may be repeated.
    Each types `TEXT`, then presses Enter.
  - `qemu_boot.KEYS`.

- [ ] **Step 1: Write the failing tests**

Append this class to `vm/test_qemu_boot.py`, just above the
`if __name__ == "__main__":` block, with two blank lines before it:

```python
class TestSecondDiskAndTyping(unittest.TestCase):
    def test_hd1_is_the_primary_slave_and_snapshotted(self):
        args = qemu_boot.build_args("bios", "a.img", "o", 1, "fw",
                                    hd1="b.img")
        self.assertIn("file=b.img,format=raw,if=ide,index=1,media=disk",
                      args)
        self.assertIn("-snapshot", args)

    def test_parse_typed(self):
        self.assertEqual(qemu_boot.parse_typed("70:fsck -n /dev/rhd1a"),
                         (70.0, "fsck -n /dev/rhd1a"))
        self.assertEqual(qemu_boot.parse_typed("6:-s"), (6.0, "-s"))

    def test_parse_typed_refuses_bad_specs(self):
        for spec in ("fsck", "5:a|b"):
            with self.assertRaises(ValueError):
                qemu_boot.parse_typed(spec)

    def test_run_types_each_key_then_enter(self):
        with tempfile.TemporaryDirectory() as tmp:
            image = os.path.join(tmp, "disk.img")
            open(image, "w").close()
            fake_qmp = mock.Mock()
            with mock.patch("qemu_boot.subprocess.Popen"), \
                 mock.patch("qemu_boot.qemu_shot.QMP",
                            return_value=fake_qmp), \
                 mock.patch("qemu_boot.time.sleep", return_value=None):
                qemu_boot.run("bios", image, os.path.join(tmp, "out"), [],
                              "fw", typed=[(5.0, "-s")])
            keys = [c.kwargs["keys"] for c in fake_qmp.execute.call_args_list
                    if c.args == ("send-key",)]
            self.assertEqual(keys, [[{"type": "qcode", "data": "minus"}],
                                    [{"type": "qcode", "data": "s"}],
                                    [{"type": "qcode", "data": "ret"}]])

    def test_main_passes_hd1_and_typed_to_run(self):
        with mock.patch("qemu_boot.run") as run:
            qemu_boot.main(["qemu_boot.py", "bios", "a.img", "out",
                            "--hd1", "b.img", "--type", "6:-s",
                            "--type", "70:fsck -n /dev/rhd1a",
                            "--at", "90", "--firmware-dir", "fw"])
        run.assert_called_once_with(
            "bios", "a.img", "out", [90.0], "fw", esp=None, hd1="b.img",
            typed=[(6.0, "-s"), (70.0, "fsck -n /dev/rhd1a")])
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd vm && python -m unittest test_qemu_boot -v`
Expected: `FAILED (errors=5)`, all five from the new class:
- `TypeError`: `build_args()` got an unexpected keyword argument `hd1`
- `TypeError`: `run()` got an unexpected keyword argument `typed`
- `AttributeError` for `parse_typed`, twice
- a `SystemExit` from argparse, which rejects `--hd1`

The twelve existing tests still pass.

- [ ] **Step 3: Change `vm/qemu_boot.py`**

Make it read exactly as below. The changes from master are:
- the usage and docstring lines for `--hd1` and `--type`
- `KEYS`
- `parse_typed()`
- `hd1` in `build_args()` and `run()`, with `hd1` added to the
  existence-and-master check
- one time-ordered event loop in `run()` that either types or takes a
  screenshot
- `_type()`
- the two new arguments in `main()`

```python
#!/usr/bin/env python3
"""Boot a disk image under QEMU and capture its consoles and screen.

    python vm/qemu_boot.py {bios,uefi} IMAGE OUTDIR [--esp ESP_IMAGE]
                           [--hd1 IMAGE] [--type SECONDS:TEXT ...]
                           [--at SECONDS[,SECONDS...]] [--firmware-dir DIR]

bios boots QEMU's own SeaBIOS.  uefi boots the IA32 edk2 firmware QEMU ships
as share/edk2-i386-code.fd, so no OVMF build is needed.  IMAGE is the first
IDE disk (i440FX/PIIX3, the controller the EIDE boot driver probes); --esp
adds a virtio disk for the two-disk layout, whose loader sits on an
ESP-only disk.  --hd1 adds a second IDE disk, the primary slave, which the
guest sees as hd1.  Each --type types TEXT and presses Enter at SECONDS,
for a boot prompt or a single-user shell.

OUTDIR gets console.log (COM1: firmware and loader), kernel.log (COM2: the
kernel's serial console) and shot-<N>s.png screenshots.  QEMU quits after
the last --at or --type time.

Every drive is opened with -snapshot, so no boot ever writes an image, and
any path named golden.img or rhapsody.vmdk is refused outright, wherever it
lives (so the main checkout's masters are refused from a worktree too).
QEMU gets native paths straight from Python: Git Bash does not rewrite
`-serial file:/d/...` for native programs, which is why this is not a shell
script.  Standard library only.
"""
import argparse
import importlib.util
import os
import shutil
import subprocess
import sys
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
_MASTERS = ("golden.img", "rhapsody.vmdk")
DEFAULT_AT = "60,120,180"


def _load_qemu_shot():
    spec = importlib.util.spec_from_file_location(
        "qemu_shot", os.path.join(_HERE, "qemu-shot.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


qemu_shot = _load_qemu_shot()
# What --type can send: qemu-shot's boot-prompt keys plus a path's.
KEYS = dict(qemu_shot.KEY_MAP, **{"/": ["slash"], ".": ["dot"]})


def refuse_masters(path):
    """Exit if path is one of the read-only master images, wherever it
    lives: by same-file identity against this checkout's own copy, or by
    basename against golden.img/rhapsody.vmdk anywhere (e.g. the main
    checkout, when running from a worktree that has no copy of its own)."""
    for name in _MASTERS:
        master = os.path.join(_HERE, name)
        if (os.path.exists(master) and os.path.exists(path)
                and os.path.samefile(path, master)):
            raise SystemExit("refusing to boot %s: it is a read-only master"
                             % path)
    if os.path.basename(path).lower() in (n.lower() for n in _MASTERS):
        raise SystemExit("refusing to boot %s: it is a read-only master"
                         % path)


def default_firmware_dir(qemu):
    found = shutil.which(qemu)
    if found is None:
        raise SystemExit("%s is not on PATH" % qemu)
    return os.path.join(os.path.dirname(os.path.realpath(found)), "share")


def parse_typed(spec):
    """"SECONDS:TEXT" -> (seconds, text), refusing keys KEYS cannot send."""
    seconds, sep, text = spec.partition(":")
    if not sep:
        raise ValueError("--type wants SECONDS:TEXT, not %r" % spec)
    for ch in text:
        if ch not in KEYS:
            raise ValueError("--type cannot send %r" % ch)
    return float(seconds), text


def build_args(mode, image, outdir, qmp_port, firmware_dir, esp=None,
               hd1=None, qemu="qemu-system-i386"):
    args = [qemu, "-M", "pc", "-m", "256", "-nodefaults", "-vga", "cirrus",
            "-display", "none", "-snapshot",
            "-drive", "file=%s,format=raw,if=ide,index=0,media=disk" % image,
            "-serial", "file:%s" % os.path.join(outdir, "console.log"),
            "-serial", "file:%s" % os.path.join(outdir, "kernel.log"),
            "-rtc", "base=%s" % qemu_shot.RTC_BASE,
            "-qmp", "tcp:127.0.0.1:%d,server=on,wait=off" % qmp_port]
    if mode == "uefi":
        # Nehalem: QEMU's default CPU model lacks features edk2 asserts on.
        # disable_s3: stops edk2 reserving low ACPI NVS for S3 resume, which
        # would cap the contiguous memory the kernel is given.
        args += ["-cpu", "Nehalem", "-global", "PIIX4_PM.disable_s3=1",
                 "-drive", "if=pflash,format=raw,unit=0,readonly=on,file=%s"
                 % os.path.join(firmware_dir, "edk2-i386-code.fd"),
                 "-drive", "if=pflash,format=raw,unit=1,file=%s"
                 % os.path.join(outdir, "edk2-i386-vars.fd")]
    elif mode == "bios":
        args += ["-cpu", "pentium", "-boot", "order=c"]
    else:
        raise ValueError("mode must be bios or uefi, not %r" % mode)
    if esp is not None:
        args += ["-drive", "id=esp,file=%s,format=raw,if=none" % esp,
                 "-device", "virtio-blk-pci,drive=esp"]
    if hd1 is not None:
        args += ["-drive",
                 "file=%s,format=raw,if=ide,index=1,media=disk" % hd1]
    return args


def run(mode, image, outdir, at_points, firmware_dir, esp=None, hd1=None,
        typed=()):
    for path in (image, esp, hd1):
        if path is not None:
            if not os.path.exists(path):
                raise SystemExit("no such image: %s" % path)
            refuse_masters(path)
    os.makedirs(outdir, exist_ok=True)
    if mode == "uefi":
        shutil.copyfile(os.path.join(firmware_dir, "edk2-i386-vars.fd"),
                        os.path.join(outdir, "edk2-i386-vars.fd"))
    port = qemu_shot.find_free_port()
    stderr_path = os.path.join(outdir, "qemu-stderr.log")
    proc = None
    qmp = None
    try:
        stderr_f = open(stderr_path, "wb")
        try:
            proc = subprocess.Popen(
                build_args(mode, image, outdir, port, firmware_dir, esp=esp,
                           hd1=hd1),
                stdout=subprocess.DEVNULL, stderr=stderr_f)
        finally:
            stderr_f.close()
        start = time.monotonic()
        try:
            qmp = qemu_shot.QMP("127.0.0.1", port)
        except RuntimeError as e:
            raise SystemExit(_qemu_failure_message(proc, stderr_path, e))
        events = sorted([(t, None) for t in at_points] + list(typed),
                        key=lambda e: e[0])
        for t, text in events:
            remaining = t - (time.monotonic() - start)
            if remaining > 0:
                time.sleep(remaining)
            try:
                if text is not None:
                    _type(qmp, text)
                    print("typed %r at %ss" % (text, qemu_shot.fmt_seconds(t)))
                    continue
                ppm = os.path.join(outdir, "_shot.ppm")
                qmp.execute("screendump", filename=ppm)
                with open(ppm, "rb") as f:
                    w, h, _, pixels = qemu_shot.parse_ppm(f.read())
                os.remove(ppm)
            except (OSError, RuntimeError) as e:
                raise SystemExit(_qemu_failure_message(proc, stderr_path, e))
            png = os.path.join(outdir,
                               "shot-%ss.png" % qemu_shot.fmt_seconds(t))
            qemu_shot.write_png(png, w, h, pixels)
            print("wrote %s" % png)
    finally:
        if qmp is not None:
            try:
                qmp.execute("quit")
            except Exception:
                pass
            qmp.close()
        if proc is not None:
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
    print("console: %s" % os.path.join(outdir, "console.log"))
    print("kernel:  %s" % os.path.join(outdir, "kernel.log"))


def _type(qmp, text):
    for ch in text + "\n":
        qmp.execute("send-key", keys=[{"type": "qcode", "data": code}
                                      for code in KEYS[ch]])
        time.sleep(0.05)


def _qemu_failure_message(proc, stderr_path, error):
    status = proc.poll()
    if status is not None:
        return ("QEMU exited with status %s during the boot; its stderr "
                "is in %s" % (status, stderr_path))
    return ("lost the QMP connection (%s) while QEMU was still running; "
            "its stderr is in %s" % (error, stderr_path))


def main(argv):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("mode", choices=("bios", "uefi"))
    p.add_argument("image")
    p.add_argument("outdir")
    p.add_argument("--esp", default=None)
    p.add_argument("--hd1", default=None)
    p.add_argument("--type", dest="typed", action="append", default=[],
                   type=parse_typed, metavar="SECONDS:TEXT")
    p.add_argument("--at", default=DEFAULT_AT,
                   help="comma-separated screenshot times in seconds")
    p.add_argument("--firmware-dir", default=None)
    a = p.parse_args(argv[1:])
    at_points = [float(x) for x in a.at.split(",") if x]
    firmware_dir = a.firmware_dir or default_firmware_dir("qemu-system-i386")
    run(a.mode, a.image, a.outdir, at_points, firmware_dir, esp=a.esp,
        hd1=a.hd1, typed=a.typed)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd vm && python -m unittest test_qemu_boot -v`
Expected: `Ran 17 tests`, `OK`.

- [ ] **Step 5: Commit**

```bash
git add vm/qemu_boot.py vm/test_qemu_boot.py
git commit -m "vm: let qemu_boot attach a second IDE disk and type at the guest"
```

---

### Task 7: `fsck -n` in the guest, and the write-up

**Files:**
- Create: `docs/build/instmedia-ufs.md`
- Modify: `docs/superpowers/specs/2026-09-22-install-media-design.md`, the
  *Host builder* module table

**Interfaces:**
- Consumes:
  - `python -m instmedia.sample OUTDIR` (Task 5)
  - `qemu_boot.py --hd1 --type` (Task 6)
  - The phase 1 fixture `D:/RhapsodiOS/vm/work/p1-eide.img`, booted only
    through `qemu_boot.py`, which always adds `-snapshot`. It roots from
    `hd0a` and has `/dev/rhd1a` (character 15, 8).
- Produces: the phase 3 gate evidence, and the doc.

- [ ] **Step 1: Write fresh sample images**

```bash
cd vm
python -m instmedia.sample work/p3-gate
```

Expected output:
```
wrote work/p3-gate\fdisk512.img
wrote work/p3-gate\cd2048.img
```

- [ ] **Step 2: Check the 512-byte-sector image in the guest**

This boots the fixture, types `-s` at the `boot:` prompt for single-user,
then types the check at the `#` prompt:

```bash
python qemu_boot.py bios D:/RhapsodiOS/vm/work/p1-eide.img work/p3-gate/run512 --hd1 work/p3-gate/fdisk512.img --type "6:-s" --type "70:fsck -n /dev/rhd1a" --at 40,65,90,110
```

Pass requires all of the following:
- `work/p3-gate/run512/kernel.log` contains
  `hd1: Disk Label:        instmedia sample` and `rootdev 300, howto 40002`.
- Viewed with the Read tool, `shot-110s.png` shows the `# fsck -n /dev/rhd1a`
  line, then `** /dev/rhd1a (NO WRITE)`.
- The screenshot then shows the five `** Phase N - …` lines with nothing
  between them.
- It ends with
  `1805 files, 16558 used, 46801 free (9 frags, 5849 blocks, 0.0% fragmentation)`.

If `shot-65s.png` doesn't yet show the `#` prompt, the guest was slower than
it was when this plan was written. In that case add 30 to the fsck `--type`
time and to every `--at` time after it, and rerun. Any other fsck output is
a failure. Stop and report it with the screenshot. Don't adjust the writer
to silence it without understanding it.

- [ ] **Step 3: Check the 2048-byte-sector image in the guest**

```bash
python qemu_boot.py bios D:/RhapsodiOS/vm/work/p1-eide.img work/p3-gate/run2048 --hd1 work/p3-gate/cd2048.img --type "6:-s" --type "70:fsck -n /dev/rhd1a" --at 40,65,90,120
```

The pass criteria are the same as in Step 2, except for these:
- `kernel.log` also says `hd1: Device Capacity:   256 MB`.
- The final screenshot, `shot-120s.png`, ends with
  `8077 files, 32872 used, 96143 free (3 frags, 24035 blocks, 0.0% fragmentation)`.

- [ ] **Step 4: Write `docs/build/instmedia-ufs.md`**

Fill in `<date>` and the two summary lines from your own runs:

````markdown
# instmedia's UFS writer

`vm/instmedia/` writes UFS filesystems and NeXT `dlV3` labels on the Windows
host. It works from an in-memory tree of nodes, and lays everything out as
Rhapsody's `newfs` and `disk -i` would. It is phase 3 of the install-media
design (`docs/superpowers/specs/2026-09-22-install-media-design.md`), and
the live-root builder in phase 4 is its first user.

| Module | Job |
|---|---|
| `ufs_geometry.py` | `newfs`'s geometry arithmetic, ported from `mkfs()` in `src/Commands/diskdev_cmds/newfs.tproj/mkfs.c` with `newfs.c`'s defaults |
| `label.py` | Encodes a label and writes its copies, each with its own `dl_label_blkno` |
| `space.py` | Hands out free space in ascending order, starting from what `initcg()` leaves free |
| `ufs.py` | The writer: superblock and copies, cylinder groups, inodes, directories, data |
| `readback.py` | Reads an image back with `rhap_image` and diffs it against its tree |
| `sample.py` | The two images phase 3 is checked with |

## Nodes

A tree is a list of `ufs_extract.Node(path, kind, mode, uid, gid, mtime, data)`:

| kind | `data` | stored as |
|---|---|---|
| `dir` | `None` | `.`, `..`, then the children in list order |
| `reg` | bytes | fragments for the last direct block only, then single and double indirect blocks |
| `lnk` | target | inline when shorter than 60 bytes, otherwise a data block |
| `chr`, `blk` | `(major, minor)` | `(major << 8) \| minor` in `di_db[0]` |
| `hlink` | another node's path | a directory entry naming that node's inode |

Inodes are numbered from 2 in list order and spill into later cylinder
groups as they fill. The caller supplies the time stamped on the
filesystem, so the same tree always gives the same bytes.

## How it is checked

1. **Against Apple's own output.** Three references are used: `golden.img`,
   the DR2 install floppy and the DR2 CD.
   - Every geometry field matches.
   - The serialized superblock is byte-identical, except for the four
     fields the kernel rewrites at mount time: `fs_fsmnt`, `fs_cgrotor`,
     `fs_csp` and `fs_maxcluster`.
   - Cylinder-group offsets and sizes match.
   - The labels on `golden.img` and the floppy are reproduced byte for byte.

   The tests only read these images. The writer takes nothing from them.
2. **Read back on the host.** `readback.diff` walks the image's directories
   and checks every node's type, mode, owner, mtime, contents, link count
   and `di_blocks`. `ufs_check.check` then recomputes the allocation
   accounting.
3. **`fsck -n` in the guest.** Each sample image is attached as IDE `hd1` to
   the phase 1 fixture, booted single-user:

```bash
cd vm
python -m instmedia.sample work/p3-gate
python qemu_boot.py bios D:/RhapsodiOS/vm/work/p1-eide.img work/p3-gate/run512 --hd1 work/p3-gate/fdisk512.img --type "6:-s" --type "70:fsck -n /dev/rhd1a" --at 40,65,90,110
python qemu_boot.py bios D:/RhapsodiOS/vm/work/p1-eide.img work/p3-gate/run2048 --hd1 work/p3-gate/cd2048.img --type "6:-s" --type "70:fsck -n /dev/rhd1a" --at 40,65,90,120
```

Results on <date>: all five phases were clean on both images.

| Image | Label | Summary |
|---|---|---|
| `fdisk512.img` | `secsize` 512 in an `0xA7` partition at LBA 2048, 9 cylinder groups | `1805 files, 16558 used, 46801 free (9 frags, 5849 blocks, 0.0% fragmentation)` |
| `cd2048.img` | `secsize` 2048, fsize 2048, copies at 0/15/30/45, 4 cylinder groups | `8077 files, 32872 used, 96143 free (3 frags, 24035 blocks, 0.0% fragmentation)` |

## Worth knowing

- **Label partition fields.** `golden.img`'s label says `minfree` 10, but
  its filesystem was made with 5. `disk -i` fills the label from disktab
  defaults, and `newfs` then uses its own. `label.for_filesystem` records
  the values the filesystem actually has.
- **NeXT's `cg_clustersumoff`.** NeXT dropped BSD's `- sizeof(long)`
  (PR2216969, in both `mkfs.c` and `fsck`'s `pass5.c`). Pass 5 compares the
  whole map region from `cg_iusedoff`, so BSD's offset would fail it.
- **A `secsize` 2048 label on a 512-byte disk works.** `IODiskPartition`
  scales `p_base + d_front` by `d_secsize / physical block size`, and fsck
  takes its device block size from `fs_fsize / fs_nspf`. That is how the
  CD-style image was checked as an IDE disk.
- **Label copies are addressed in 512-byte physical blocks.** This holds on
  a CD too: DR2's copies say 0, 15, 30 and 45. A CD needs the copy at 0,
  because the kernel reads it in 2048-byte blocks.
- **Free space.**
  - Group 0's data starts right after the cylinder summary. That is often
    in the middle of a block, and the fragments before the next block
    boundary stay free.
  - In later groups, the stretch before the superblock copy is data space
    too.
  - Space never hands out a whole block that straddles either edge.
````

- [ ] **Step 5: Update the spec's module table**

In `docs/superpowers/specs/2026-09-22-install-media-design.md`, *Host
builder*, change the `label.py` row's last cell from
`the label helpers in \`ufs_build.py\`, the rebase in \`build_uefi_image.py\``
to `` `label_checksum` in `ufs_build.py` ``. The labels are written with
absolute addresses in the first place, so no rebase is needed. Then add
these rows after the `label.py` row:

```markdown
| `ufs_geometry.py` | `newfs`'s geometry arithmetic from `mkfs.c`, matching three Apple-made filesystems field for field. | none |
| `space.py` | Hands out a fresh filesystem's free space in the order `initcg()` leaves it. | none |
| `readback.py` | Reads an image back and diffs it against its node tree: contents, modes, link counts, `di_blocks`. | `rhap_image.py` |
| `sample.py` | Phase 3's two test images: an fdisk disk with label `secsize` 512 and a CD-style volume with `secsize` 2048. | none |
```

- [ ] **Step 6: Commit**

```bash
git add docs/build/instmedia-ufs.md docs/superpowers/specs/2026-09-22-install-media-design.md
git commit -m "docs: record the phase 3 UFS writer and its clean fsck in the guest"
```
