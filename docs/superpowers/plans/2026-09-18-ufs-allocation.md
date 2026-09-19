# UFS Allocation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create, grow and remove files and directories in an existing Rhapsody UFS image, so a driver bundle can be installed without a running guest.

**Architecture:** A new `vm/ufs_alloc.py` is the only thing in the tree that can grow a filesystem; `vm/rhap_inject.py` keeps its "never allocates" guarantee untouched. The cylinder-group summary math already in `vm/ufs_build.py` is extracted to a shared `vm/ufs_cg.py` so the builder and the allocator cannot diverge. Three layers: cylinder-group access, raw fragment/inode allocators, then namespace operations.

**Tech Stack:** Python 3 (stdlib only — `struct`, `os`, `unittest`), matching the existing `vm/` tooling. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-09-18-ufs-allocation-design.md`

## Global Constraints

- **Never write to `vm/golden.img`.** It is the read-only master. Refuse any target not under `vm/work`, and refuse any target that resolves by real path to `golden.img`.
- Every refusal raises `SafetyError` (or a subclass). Refusals happen **before the first byte is written**.
- Mutations are collected as `(offset, bytes)` and applied only after every step has succeeded.
- `vm/rhap_inject.py` behaviour must not change. Its "never allocates" property is deliberate.
- `vm/ufs_build.py` keeps its `ncg == 1` restriction. Only `ufs_cg.py` and `ufs_alloc.py` handle multiple groups.
- `test_ufs_build.py` must keep passing unchanged throughout. It calls `ufs_build.read_geometry` and `ufs_build.recompute_cg_tables` by those names.
- Size bound: direct + single indirect only. Refuse files larger than **16 MB** with an error naming the limit.
- Python stdlib only. Match the existing `vm/` style: `main(argv)` + `sys.exit`, no argparse.
- Work images are created with `cp -c` (APFS `clonefile`) — instant and near-zero space. Never full-copy an 8 GB image.
- `vm/*.img` is gitignored. Never commit an image, and never commit `vm/mach_kernel` or `vm/AHCI.config/`.

## Measured facts about `golden.img` (do not re-derive)

| Property | Value |
|---|---|
| `ncg` | 510 |
| `bsize` | 8192 |
| `fsize` | 1024 |
| `frag` | 8 |
| `NDADDR` | 12 |
| `NIADDR` | 3 |
| `DINODE_SIZE` | 128 |
| `/mach_kernel` | 1459520 bytes, 704 bytes slack |

## Cylinder group header layout (verified against `src/kernel-7/bsd/ufs/ffs/fs.h`)

Byte offsets within a CG header:

| Offset | Field |
|---|---|
| 4 | `cg_magic` |
| 16 | `cg_ncyl` (int16), 18 `cg_niblk` (int16) |
| 20 | `cg_ndblk` |
| 24 | `cg_cs` — `struct csum` = `cs_ndir, cs_nbfree, cs_nifree, cs_nffree` (4 × int32) |
| 52 | `cg_frsum[8]` |
| 84 | `cg_btotoff`, 88 `cg_boff`, 92 `cg_iusedoff`, 96 `cg_freeoff` |
| 112 | `cg_nclusterblks` |

`ufs_build.py:462` already unpacks the four `*off` values from offset 84; that is the confirmation this layout is right.

## File Structure

| File | Responsibility |
|---|---|
| `vm/ufs_cg.py` | **New.** Shared geometry + CG summary math, extracted from `ufs_build.py`. No I/O policy, no writes. |
| `vm/ufs_alloc.py` | **New.** Allocating writer: CG access, fragment/inode allocation, namespace operations. |
| `vm/ufs_check.py` | **New.** Python consistency checker — recomputes all five invariants and reports disagreements. |
| `vm/test_ufs_cg.py` | **New.** Tests for the extracted math. |
| `vm/test_ufs_alloc.py` | **New.** Tests for allocation and namespace operations. |
| `vm/ufs_build.py` | **Modify.** Import shared math from `ufs_cg`, re-export for compatibility. |

---

### Task 1: Extract shared cylinder-group math into `vm/ufs_cg.py`

Pure refactor. No behaviour change. This exists so the builder and the allocator can never compute a summary differently — a divergence would produce an image that looks correct until fsck disagrees.

**Files:**
- Create: `vm/ufs_cg.py`
- Modify: `vm/ufs_build.py`
- Create: `vm/test_ufs_cg.py`

**Interfaces:**
- Produces: `ufs_cg.SB_FIELDS` (dict), `ufs_cg.Geometry` (namedtuple over `sorted(SB_FIELDS)`), `ufs_cg.CgTables` (namedtuple `blktot blks frsum nbfree nffree`), `ufs_cg.UfsError`, `ufs_cg.read_geometry(image_path)`, `ufs_cg.bit_is_set(bitmap, i)`, `ufs_cg.cbtocylno(g, bno)`, `ufs_cg.cbtorpos(g, bno)`, `ufs_cg.recompute_cg_tables(g, blksfree)`, `ufs_cg.recompute_cluster_maps(g, blksfree, nclusterblks)`.
- `ufs_build.read_geometry` keeps its `ncg == 1` check and delegates to `ufs_cg.read_geometry` for parsing.
- `ufs_build.BuildError` becomes an alias of `ufs_cg.UfsError` so existing `except BuildError` sites keep working.

- [ ] **Step 1: Write the failing test**

Create `vm/test_ufs_cg.py`:

```python
"""The shared CG math must behave identically wherever it is imported from.

ufs_build and ufs_alloc both derive allocation summaries.  If they ever
disagreed the result would be an image that looks correct until fsck says
otherwise, so they share one implementation and this pins it.
"""
import os
import unittest

import rhap_image
import ufs_build
import ufs_cg

HERE = os.path.dirname(os.path.abspath(__file__))
GOLDEN = os.path.join(HERE, "golden.img")


def _present(*paths):
    return all(os.path.exists(p) for p in paths)


class TestSharedMath(unittest.TestCase):
    def test_ufs_build_reexports_the_shared_names(self):
        self.assertIs(ufs_build.recompute_cg_tables, ufs_cg.recompute_cg_tables)
        self.assertIs(ufs_build.bit_is_set, ufs_cg.bit_is_set)
        self.assertIs(ufs_build.CgTables, ufs_cg.CgTables)
        self.assertIs(ufs_build.BuildError, ufs_cg.UfsError)

    def test_bit_is_set_reads_little_endian_bit_order(self):
        # A set bit means the fragment is FREE.  Bit i lives in byte i//8 at
        # position i%8, which is the order the kernel's bitmaps use.
        self.assertEqual(ufs_cg.bit_is_set(bytearray(b"\x01"), 0), 1)
        self.assertEqual(ufs_cg.bit_is_set(bytearray(b"\x01"), 1), 0)
        self.assertEqual(ufs_cg.bit_is_set(bytearray(b"\x80"), 7), 1)

    @unittest.skipUnless(_present(GOLDEN), "golden.img not present")
    def test_reads_multi_group_geometry_that_ufs_build_refuses(self):
        # ufs_cg has no single-group restriction; ufs_build keeps one.
        g = ufs_cg.read_geometry(GOLDEN)
        self.assertEqual(g.ncg, 510)
        self.assertEqual(g.bsize, 8192)
        self.assertEqual(g.fsize, 1024)
        self.assertEqual(g.frag, 8)
        with self.assertRaises(ufs_build.BuildError):
            ufs_build.read_geometry(GOLDEN)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
cd vm && python3 -m unittest test_ufs_cg -v
```

Expected: `ModuleNotFoundError: No module named 'ufs_cg'`.

- [ ] **Step 3: Create `vm/ufs_cg.py`**

Move these from `vm/ufs_build.py` **verbatim** — do not retype or "improve" them, the exact arithmetic is load-bearing: `SB_FIELDS`, `Geometry`, `CgTables`, `cbtocylno`, `cbtorpos`, `bit_is_set`, `recompute_cg_tables`, `recompute_cluster_maps`.

Add a geometry reader with no single-group restriction:

```python
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


class UfsError(Exception):
    pass
```

`read_geometry` parses the superblock and validates only the magic:

```python
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
```

The moved `cbtorpos` raises `BuildError` today; change that raise to `UfsError`.

- [ ] **Step 4: Rewire `vm/ufs_build.py`**

Delete the moved definitions and import them instead. Keep the public names so `test_ufs_build.py` is untouched:

```python
import ufs_cg
from ufs_cg import (SB_FIELDS, Geometry, CgTables, UfsError,
                    bit_is_set, cbtocylno, cbtorpos,
                    recompute_cg_tables, recompute_cluster_maps)

# Existing callers catch BuildError; it is the same class now.
BuildError = ufs_cg.UfsError


def read_geometry(image_path):
    """As ufs_cg.read_geometry, but this writer only handles one group."""
    g = ufs_cg.read_geometry(image_path)
    if g.ncg != 1:
        raise BuildError(
            "%s has %d cylinder groups; this writer only handles single-group "
            "volumes (the two install floppies)" % (image_path, g.ncg))
    return g
```

- [ ] **Step 5: Run both suites and verify they pass**

```bash
cd vm && python3 -m unittest test_ufs_cg test_ufs_build -v
```

Expected: all tests PASS. `test_ufs_build`'s tests must pass **unchanged** — if you had to edit them, the refactor changed behaviour and is wrong.

- [ ] **Step 6: Commit**

```bash
git add vm/ufs_cg.py vm/ufs_build.py vm/test_ufs_cg.py
git commit -m "vm: extract shared cylinder-group math into ufs_cg"
```

---

### Task 2: Cylinder-group access and the summary cross-check

Read any group's header and bitmaps, and verify our model of the on-disk format against a filesystem known to be good — before anything is ever written.

**Files:**
- Create: `vm/ufs_alloc.py`
- Create: `vm/ufs_check.py`
- Create: `vm/test_ufs_alloc.py`

**Interfaces:**
- Consumes: everything from `ufs_cg` (Task 1).
- Produces:
  - `ufs_alloc.SafetyError`
  - `ufs_alloc.CG_CS_OFF = 24`, `ufs_alloc.CG_OFFSETS_OFF = 84`
  - `ufs_alloc.Allocator(image_path)` — context manager, opens `r+b`
  - `Allocator.cg_count` → int
  - `Allocator.cg_header_offset(c)` → absolute byte offset of group `c`'s header
  - `Allocator.read_cg(c)` → `bytearray` of the whole group header block
  - `Allocator.cg_summary(c)` → `(ndir, nbfree, nifree, nffree)`
  - `Allocator.blksfree(c)` → `bytearray`, `Allocator.inosused(c)` → `bytearray`
  - `Allocator.fs_cstotal()` → `(ndir, nbfree, nifree, nffree)`
  - `Allocator.validate()` — raises `SafetyError` if the summed per-group values disagree with `fs_cstotal`
  - `ufs_check.check(image_path)` → list of human-readable problem strings, empty when clean

**Background.** Group `c`'s header starts at fragment `cgstart(c) + g.cblkno`, where `cgstart` is `rhap_image._cgstart(img, c)` = `fpg*c + cgoffset*(c & ~cgmask)`. Multiply by `g.fsize` and add `img.part_start` for an absolute byte offset.

`fs_cstotal` is a `struct csum` in the superblock (`src/kernel-7/bsd/ufs/ffs/fs.h:241`). **Derive its byte offset by counting fields in that header, then prove it** with `validate()` on an untouched `golden.img`: the sum of all 510 per-group summaries must equal it exactly. If it does not, your offset is wrong — fix the offset, do not adjust the check.

- [ ] **Step 1: Write the failing test**

Create `vm/test_ufs_alloc.py`:

```python
"""Allocation must leave the filesystem consistent by fsck's definition.

The checks here are the cheap tier: they recompute invariants from the raw
bitmaps.  The acceptance gate is the guest's own /sbin/fsck (see the plan).
"""
import os
import shutil
import subprocess
import tempfile
import unittest

import ufs_alloc
import ufs_check

HERE = os.path.dirname(os.path.abspath(__file__))
GOLDEN = os.path.join(HERE, "golden.img")


def _present(*paths):
    return all(os.path.exists(p) for p in paths)


def clone(src, dst):
    """APFS clonefile: instant, near-zero space until written."""
    subprocess.check_call(["cp", "-c", src, dst])


class TestCylinderGroupAccess(unittest.TestCase):
    @unittest.skipUnless(_present(GOLDEN), "golden.img not present")
    def test_summed_group_summaries_equal_fs_cstotal(self):
        # This is the precondition the allocator refuses to write without.
        # If it fails, our model of the on-disk format is wrong.
        with ufs_alloc.Allocator(GOLDEN) as a:
            self.assertEqual(a.cg_count, 510)
            a.validate()

    @unittest.skipUnless(_present(GOLDEN), "golden.img not present")
    def test_untouched_image_is_reported_clean(self):
        self.assertEqual(ufs_check.check(GOLDEN), [])

    @unittest.skipUnless(_present(GOLDEN), "golden.img not present")
    def test_refuses_to_open_the_master_for_writing(self):
        with self.assertRaises(ufs_alloc.SafetyError):
            ufs_alloc.Allocator(GOLDEN, writable=True)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it and verify it fails**

```bash
cd vm && python3 -m unittest test_ufs_alloc -v
```

Expected: `ModuleNotFoundError: No module named 'ufs_alloc'`.

- [ ] **Step 3: Implement `vm/ufs_alloc.py`'s access layer**

Module docstring first — say why this file exists, because the neighbouring tool promises the opposite:

```python
"""Allocating writer for the Rhapsody disk image.

Unlike rhap_inject.py, which never allocates and only rewrites already-mapped
fragments, this module grows the filesystem: it claims fragments and inodes,
creates directory entries, and maintains every summary the kernel and fsck
rely on.  That power is why the safety rules here are strict.

Never operates on vm/golden.img.  Every refusal raises SafetyError, and
refusals happen before the first byte is written.
"""
import os
import struct

import rhap_image
import ufs_cg

CG_CS_OFF = 24          # struct csum inside the cg header
CG_OFFSETS_OFF = 84     # cg_btotoff, cg_boff, cg_iusedoff, cg_freeoff


class SafetyError(Exception):
    pass
```

The writable-target rule checks the property, not a filename. Define
`HERE = os.path.dirname(os.path.abspath(__file__))` at module level first, as the
other `vm/` tools do:

```python
def _refuse_master(path):
    """Refuse the read-only master and anything outside vm/work."""
    real = os.path.realpath(path)
    golden = os.path.realpath(os.path.join(HERE, "golden.img"))
    if real == golden:
        raise SafetyError("refusing to write to the master image: %s" % path)
    work = os.path.realpath(os.path.join(HERE, "work"))
    if not real.startswith(work + os.sep):
        raise SafetyError("writable images must live under %s: %s"
                          % (work, path))
```

`validate()` is the precondition from the spec:

```python
def validate(self):
    """Refuse to proceed unless our model already matches a good filesystem."""
    totals = [0, 0, 0, 0]
    for c in range(self.cg_count):
        for i, v in enumerate(self.cg_summary(c)):
            totals[i] += v
    recorded = self.fs_cstotal()
    if tuple(totals) != tuple(recorded):
        raise SafetyError(
            "summed cylinder-group summaries %s disagree with fs_cstotal %s; "
            "the on-disk layout is not what this tool expects"
            % (tuple(totals), tuple(recorded)))
```

- [ ] **Step 4: Implement `vm/ufs_check.py`**

```python
"""Recompute every UFS allocation invariant and report disagreements.

Fast enough for unit tests, and independent of the write path in the sense
that it derives everything from the raw bitmaps.  It shares assumptions with
the code it checks, which is why the acceptance gate is the guest's fsck and
not this.
"""
```

`check(image_path)` returns a list of strings, one per problem, empty when clean. It verifies, for every group: `recompute_cg_tables(g, blksfree)` against the recorded `cg_cs` and `cg_frsum`; the inode bitmap's popcount against `cs_nifree`; the group's `cg_cs` against its slot in the `fs_csaddr` array; and finally the sum of all groups against `fs_cstotal`.

- [ ] **Step 5: Run the tests and verify they pass**

```bash
cd vm && python3 -m unittest test_ufs_alloc -v
```

Expected: 3 tests PASS. If `test_summed_group_summaries_equal_fs_cstotal` fails, your `fs_cstotal` offset is wrong — correct it against `src/kernel-7/bsd/ufs/ffs/fs.h`.

- [ ] **Step 6: Commit**

```bash
git add vm/ufs_alloc.py vm/ufs_check.py vm/test_ufs_alloc.py
git commit -m "vm: read cylinder groups and cross-check the allocation summaries"
```

---

### Task 3: Fragment allocation and release

**Files:**
- Modify: `vm/ufs_alloc.py`
- Modify: `vm/test_ufs_alloc.py`

**Interfaces:**
- Consumes: `Allocator` from Task 2.
- Produces:
  - `Allocator.alloc_frags(n)` → list of `n` absolute fragment numbers. Raises `SafetyError` when no group can satisfy it.
  - `Allocator.free_frags(frags)` → None.
  - `Allocator.frag_is_free(frag)` → bool. Reads the owning group's bitmap.
  - `Allocator.flush()` → None. Applies the collected writes; the only method that writes.
  - Both allocators update the group bitmap, the group's `cg_cs` and `cg_frsum`, the `fs_csaddr` slot, and `fs_cstotal`.

**Policy.** UFS allocates whole 8-fragment blocks for everything except a file's tail. Follow that: for `n >= frag`, take whole free blocks; allocate a partial run only for the remainder. Any other packing is internally legal but leaves accounting the kernel does not expect.

- [ ] **Step 1: Write the failing tests**

Add to `vm/test_ufs_alloc.py`:

```python
class TestFragmentAllocation(unittest.TestCase):
    def setUp(self):
        if not _present(GOLDEN):
            self.skipTest("golden.img not present")
        self.tmp = tempfile.mkdtemp(prefix="ufsalloc-", dir=os.path.join(HERE, "work"))
        self.addCleanup(shutil.rmtree, self.tmp)
        self.img = os.path.join(self.tmp, "test.img")
        clone(GOLDEN, self.img)

    def test_allocation_then_release_restores_every_count(self):
        before = None
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            a.validate()
            before = a.fs_cstotal()
            frags = a.alloc_frags(9)       # one whole block plus a tail
            self.assertEqual(len(frags), 9)
            self.assertEqual(len(set(frags)), 9)
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])

        with ufs_alloc.Allocator(self.img, writable=True) as a:
            after_alloc = a.fs_cstotal()
            self.assertNotEqual(after_alloc, before)
            a.free_frags(frags)
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])

        with ufs_alloc.Allocator(self.img) as a:
            self.assertEqual(a.fs_cstotal(), before)

    def test_allocated_fragments_are_marked_used(self):
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            frags = a.alloc_frags(8)
            for f in frags:
                self.assertFalse(a.frag_is_free(f),
                                 "fragment %d still marked free" % f)
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])
```

- [ ] **Step 2: Run and verify failure**

```bash
cd vm && python3 -m unittest test_ufs_alloc.TestFragmentAllocation -v
```

Expected: FAIL — `Allocator` has no attribute `alloc_frags`.

- [ ] **Step 3: Implement allocation, release and `flush`**

`flush()` applies the collected `(offset, bytes)` writes and is the only method that writes. Before it runs, the image is byte-identical.

After mutating a group's bitmap, recompute that group's tables with `ufs_cg.recompute_cg_tables(g, blksfree)` and write back `cg_cs`, `cg_frsum`, the `btot`/`blks` tables and the cluster maps, then adjust the `fs_csaddr` slot and `fs_cstotal` by the delta.

- [ ] **Step 4: Run and verify the tests pass**

```bash
cd vm && python3 -m unittest test_ufs_alloc -v
```

Expected: all PASS, and `ufs_check.check` clean after every mutation.

- [ ] **Step 5: Commit**

```bash
git add vm/ufs_alloc.py vm/test_ufs_alloc.py
git commit -m "vm: allocate and release fragments, maintaining every summary"
```

---

### Task 4: Inode allocation and release

**Files:**
- Modify: `vm/ufs_alloc.py`
- Modify: `vm/test_ufs_alloc.py`

**Interfaces:**
- Produces:
  - `Allocator.alloc_inode(is_dir=False)` → inode number. Updates the group's inode bitmap, `cs_nifree`, and `cs_ndir` when `is_dir`.
  - `Allocator.free_inode(ino, is_dir=False)` → None.
  - `Allocator.write_inode(ino, mode, size, db, ib, nlink, mtime)` → None. Writes a 128-byte dinode; `db` is 12 direct and `ib` 3 indirect block pointers.
  - `Allocator.set_inode_blocks(ino, nsectors)` → None. `di_blocks` counts **512-byte sectors**, not fragments.

- [ ] **Step 1: Write the failing test**

```python
class TestInodeAllocation(unittest.TestCase):
    def setUp(self):
        if not _present(GOLDEN):
            self.skipTest("golden.img not present")
        self.tmp = tempfile.mkdtemp(prefix="ufsalloc-", dir=os.path.join(HERE, "work"))
        self.addCleanup(shutil.rmtree, self.tmp)
        self.img = os.path.join(self.tmp, "test.img")
        clone(GOLDEN, self.img)

    def test_inode_allocation_then_release_restores_counts(self):
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            before = a.fs_cstotal()
            ino = a.alloc_inode()
            self.assertGreater(ino, 2)
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])

        with ufs_alloc.Allocator(self.img, writable=True) as a:
            a.free_inode(ino)
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])
        with ufs_alloc.Allocator(self.img) as a:
            self.assertEqual(a.fs_cstotal(), before)

    def test_directory_inode_bumps_ndir(self):
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            ndir_before = a.fs_cstotal()[0]
            a.alloc_inode(is_dir=True)
            a.flush()
        with ufs_alloc.Allocator(self.img) as a:
            self.assertEqual(a.fs_cstotal()[0], ndir_before + 1)
        self.assertEqual(ufs_check.check(self.img), [])
```

- [ ] **Step 2: Run and verify failure**

```bash
cd vm && python3 -m unittest test_ufs_alloc.TestInodeAllocation -v
```

Expected: FAIL — no attribute `alloc_inode`.

- [ ] **Step 3: Implement inode allocation, release and dinode writing**

Inode `i` lives in group `i // g.ipg`; use `rhap_image._inode_location` for the fragment and byte offset. The dinode layout is in `rhap_image.Inode`: mode at 0, nlink at 2, size at 8 (int64), mtime, direct pointers at 40 (12 × int32), indirect at 88 (3 × int32).

- [ ] **Step 4: Run and verify the tests pass**

```bash
cd vm && python3 -m unittest test_ufs_alloc -v
```

Expected: all PASS, `ufs_check` clean.

- [ ] **Step 5: Commit**

```bash
git add vm/ufs_alloc.py vm/test_ufs_alloc.py
git commit -m "vm: allocate and release inodes"
```

---

### Task 5: File creation with direct and single indirect blocks

**Files:**
- Modify: `vm/ufs_alloc.py`
- Modify: `vm/test_ufs_alloc.py`

**Interfaces:**
- Produces:
  - `Allocator.write_new_file(data, mode=0o100644)` → inode number. Allocates fragments, fills direct pointers, allocates and fills one indirect block when the file exceeds 12 blocks, writes the dinode.
  - `Allocator.grow_file(ino, data)` → None. Replaces an existing file's contents, allocating more fragments when `data` exceeds its current allocation and releasing the surplus when it shrinks. This is what `rhap_inject` cannot do and is why the spec's goal says "create, grow and remove".
  - `ufs_alloc.MAX_FILE_BYTES` — computed as `(NDADDR + nindir) * bsize`, 16 MB on this filesystem.
  - Raises `SafetyError` naming the limit for anything larger.

**Background.** 12 direct pointers × 8192 = 96 KB. One indirect block holds `bsize // 4` = 2048 pointers → 16 MB. Double indirect is out of scope; the spec records that decision.

- [ ] **Step 1: Write the failing tests**

```python
class TestFileCreation(unittest.TestCase):
    def setUp(self):
        if not _present(GOLDEN):
            self.skipTest("golden.img not present")
        self.tmp = tempfile.mkdtemp(prefix="ufsalloc-", dir=os.path.join(HERE, "work"))
        self.addCleanup(shutil.rmtree, self.tmp)
        self.img = os.path.join(self.tmp, "test.img")
        clone(GOLDEN, self.img)

    def _roundtrip(self, payload):
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            ino = a.write_new_file(payload)
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])
        import rhap_image
        with rhap_image.Image(self.img) as img:
            self.assertEqual(img.read_file(ino), payload)

    def test_small_file_uses_direct_blocks(self):
        self._roundtrip(b"A" * 5000)

    def test_file_spanning_every_direct_block(self):
        self._roundtrip(bytes(range(256)) * 384)      # 96 KB exactly

    def test_file_needing_an_indirect_block(self):
        self._roundtrip(b"Z" * (200 * 1024))          # past 96 KB

    def test_growing_a_file_past_its_allocation(self):
        # The case rhap_inject refuses: /mach_kernel has 704 bytes of slack,
        # so growing it at all requires real allocation.
        import rhap_image
        big = b"G" * 300000
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            ino = a.write_new_file(b"small")
            a.flush()
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            a.grow_file(ino, big)
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])
        with rhap_image.Image(self.img) as img:
            self.assertEqual(img.read_file(ino), big)

    def test_shrinking_a_file_releases_its_surplus(self):
        import rhap_image
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            before = a.fs_cstotal()
            ino = a.write_new_file(b"B" * 200000)
            a.flush()
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            a.grow_file(ino, b"tiny")
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])
        with rhap_image.Image(self.img) as img:
            self.assertEqual(img.read_file(ino), b"tiny")

    def test_oversized_file_is_refused_before_writing(self):
        import hashlib
        digest = hashlib.sha256(open(self.img, "rb").read(1 << 20)).hexdigest()
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            with self.assertRaises(ufs_alloc.SafetyError) as cm:
                a.write_new_file(b"\0" * (ufs_alloc.MAX_FILE_BYTES + 1))
            self.assertIn("16", str(cm.exception))
        after = hashlib.sha256(open(self.img, "rb").read(1 << 20)).hexdigest()
        self.assertEqual(digest, after, "image was modified despite refusal")
```

- [ ] **Step 2: Run and verify failure**

```bash
cd vm && python3 -m unittest test_ufs_alloc.TestFileCreation -v
```

Expected: FAIL — no attribute `write_new_file`.

- [ ] **Step 3: Implement `write_new_file`**

Check the size bound **first**, before allocating anything. Allocate whole blocks for all but the tail, write the payload into the fragments, allocate one more block for the indirect pointer array when needed, and set `di_blocks` to the total fragments × `fsize // 512`.

`grow_file` reuses that machinery: compute the new fragment requirement, allocate the shortfall or free the surplus, rewrite the block pointers and `di_size`, and release the indirect block when the file shrinks back under 12 blocks.

- [ ] **Step 4: Run and verify the tests pass**

```bash
cd vm && python3 -m unittest test_ufs_alloc -v
```

Expected: all PASS. The round-trip assertions matter most — `rhap_image.read_file` is an independent reader, so agreement means the block pointers are genuinely right rather than merely self-consistent.

- [ ] **Step 5: Commit**

```bash
git add vm/ufs_alloc.py vm/test_ufs_alloc.py
git commit -m "vm: create files with direct and single indirect blocks"
```

---

### Task 6: Directory operations

**Files:**
- Modify: `vm/ufs_alloc.py`
- Modify: `vm/test_ufs_alloc.py`

**Interfaces:**
- Produces:
  - `Allocator.add_dirent(dir_ino, name, ino, dtype)` → None
  - `Allocator.mkdir(path, mode=0o040755)` → inode number. Creates `.` and `..`, bumps the parent's `di_nlink`.
  - `Allocator.create_file(path, data, mode=0o100644)` → inode number
  - `Allocator.unlink(path)`, `Allocator.rmdir(path)` → None

**Background.** UFS packs directories by over-sizing `d_reclen`: an entry's record often has slack after its name. To add an entry, walk the chain looking for an existing record whose actual need (`8 + namlen`, rounded up to 4) leaves room for the new one, split it, and only grow the directory when nothing fits. Entry layout is `struct.pack("<IHBB", ino, reclen, dtype, namlen)` followed by the name — `ufs_build.py:161` shows the same packing.

- [ ] **Step 1: Write the failing tests**

```python
class TestDirectoryOperations(unittest.TestCase):
    def setUp(self):
        if not _present(GOLDEN):
            self.skipTest("golden.img not present")
        self.tmp = tempfile.mkdtemp(prefix="ufsalloc-", dir=os.path.join(HERE, "work"))
        self.addCleanup(shutil.rmtree, self.tmp)
        self.img = os.path.join(self.tmp, "test.img")
        clone(GOLDEN, self.img)

    def test_created_directory_and_file_are_visible_to_the_reader(self):
        import rhap_image
        payload = b"hello rhapsody" * 100
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            a.mkdir("/private/Drivers/i386/TEST.config")
            a.create_file("/private/Drivers/i386/TEST.config/TEST_reloc", payload)
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])
        with rhap_image.Image(self.img) as img:
            ino = img.resolve("/private/Drivers/i386/TEST.config/TEST_reloc")
            self.assertIsNotNone(ino)
            self.assertEqual(img.read_file(ino), payload)
            names = [e[0] for e in img.listdir("/private/Drivers/i386/TEST.config")]
            self.assertIn(".", names)
            self.assertIn("..", names)

    def test_create_then_remove_restores_the_free_counts(self):
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            before = a.fs_cstotal()
            a.flush()
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            a.mkdir("/private/Drivers/i386/TEST.config")
            a.create_file("/private/Drivers/i386/TEST.config/TEST_reloc", b"x" * 9000)
            a.flush()
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            a.unlink("/private/Drivers/i386/TEST.config/TEST_reloc")
            a.rmdir("/private/Drivers/i386/TEST.config")
            a.flush()
        self.assertEqual(ufs_check.check(self.img), [])
        with ufs_alloc.Allocator(self.img) as a:
            self.assertEqual(a.fs_cstotal(), before)

    def test_rmdir_refuses_a_non_empty_directory(self):
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            a.mkdir("/private/Drivers/i386/TEST.config")
            a.create_file("/private/Drivers/i386/TEST.config/f", b"x")
            a.flush()
        with ufs_alloc.Allocator(self.img, writable=True) as a:
            with self.assertRaises(ufs_alloc.SafetyError):
                a.rmdir("/private/Drivers/i386/TEST.config")
```

- [ ] **Step 2: Run and verify failure**

```bash
cd vm && python3 -m unittest test_ufs_alloc.TestDirectoryOperations -v
```

Expected: FAIL — no attribute `mkdir`.

- [ ] **Step 3: Implement the directory operations**

`mkdir` allocates a directory inode, allocates one block for its contents, writes `.` and `..`, adds the entry to the parent and increments the parent's `di_nlink`. `rmdir` refuses unless only `.` and `..` remain.

- [ ] **Step 4: Run and verify the tests pass**

```bash
cd vm && python3 -m unittest test_ufs_alloc -v
```

Expected: all PASS. The free-count restoration test is the one that catches leaks — a leak passes fsck but silently loses blocks.

- [ ] **Step 5: Commit**

```bash
git add vm/ufs_alloc.py vm/test_ufs_alloc.py
git commit -m "vm: create and remove directories and files by path"
```

---

### Task 7: Command-line interface and a clone helper

**Files:**
- Modify: `vm/ufs_alloc.py`
- Create: `vm/install-driver.py`

**Interfaces:**
- Produces:
  - `ufs_alloc.main(argv)` — `ufs_alloc.py IMAGE mkdir PATH` and `ufs_alloc.py IMAGE put PATH LOCALFILE`
  - `install-driver.py SRC_IMAGE DRIVER_DIR OUT_IMAGE` — clones the image, creates `/private/Drivers/i386/<Name>.config/`, copies every file from `DRIVER_DIR` into it, and adds `<Name>` to the `Boot Drivers` key of `System.config/Instance0.table` using `rhap_inject.set_table_key`.

**Background.** The loader opens `/private/Drivers/i386/<Name>.config/<Name>_reloc` (`src/boot-2/i386/libsaio/load.c:382`) and reads `Instance0.table` from the same directory. `vm/AHCI.config/` ships `Default.table` but no `Instance0.table`, so copy `Default.table` to both names.

- [ ] **Step 1: Write the failing test**

Add to `vm/test_ufs_alloc.py`:

```python
class TestDriverInstall(unittest.TestCase):
    @unittest.skipUnless(_present(GOLDEN, os.path.join(HERE, "AHCI.config")),
                         "golden.img or AHCI.config not present")
    def test_installs_the_driver_bundle_and_lists_it_as_a_boot_driver(self):
        import rhap_image
        tmp = tempfile.mkdtemp(prefix="ufsalloc-", dir=os.path.join(HERE, "work"))
        self.addCleanup(shutil.rmtree, tmp)
        out = os.path.join(tmp, "test.img")
        subprocess.check_call(
            ["python3", os.path.join(HERE, "install-driver.py"),
             GOLDEN, os.path.join(HERE, "AHCI.config"), out])
        self.assertEqual(ufs_check.check(out), [])
        with rhap_image.Image(out) as img:
            base = "/private/Drivers/i386/AHCI.config"
            for name in ("AHCI_reloc", "Default.table", "Instance0.table"):
                self.assertIsNotNone(img.resolve(base + "/" + name), name)
            reloc = img.read_file(img.resolve(base + "/AHCI_reloc"))
            self.assertEqual(
                reloc, open(os.path.join(HERE, "AHCI.config/AHCI_reloc"), "rb").read())
            sysconf = img.read_file(img.resolve(
                "/private/Drivers/i386/System.config/Instance0.table"))
            self.assertIn(b"AHCI", sysconf)
```

- [ ] **Step 2: Run and verify failure**

```bash
cd vm && python3 -m unittest test_ufs_alloc.TestDriverInstall -v
```

Expected: FAIL — `install-driver.py` does not exist.

- [ ] **Step 3: Implement the CLI and `install-driver.py`**

Clone with `cp -c` so an 8 GB image costs nothing until written.

- [ ] **Step 4: Run the whole suite**

```bash
cd vm && python3 -m unittest test_ufs_cg test_ufs_alloc test_ufs_build test_rhap_image -v
```

Expected: all PASS, zero skips given `golden.img` and `AHCI.config` are present.

- [ ] **Step 5: Commit**

```bash
git add vm/ufs_alloc.py vm/install-driver.py vm/test_ufs_alloc.py
git commit -m "vm: install a driver bundle into an image from the command line"
```

---

### Task 8: Acceptance — boot the modified image and let the guest's fsck judge it

The only verdict that is not ours.

**Files:**
- None created. This task runs the tooling and reports.

- [ ] **Step 1: Build the image**

```bash
cd vm && python3 install-driver.py golden.img AHCI.config work/test.img
python3 -c "import ufs_check; print(ufs_check.check('work/test.img') or 'clean')"
```

Expected: `clean`.

- [ ] **Step 2: Graft in the current kernel**

`golden.img`'s `mach_kernel` predates the i8259 fix and cannot mount root. Use the freshly built one:

```bash
cd vm && python3 graft-kernel.py work/test.img mach_kernel work/test.img
```

Check `graft-kernel.py`'s usage for its exact argument order before running it.

- [ ] **Step 3: Boot and confirm the driver loads**

Build an ESP from `src/bootefi-1/BUILD/BOOTIA32.EFI` with `build_uefi_image.build_esp(...)`, then run `vm/run-q35-uefi.sh` — the **q35/AHCI** runner, because the point of this exercise is an AHCI controller the guest can now drive. Run qemu under a timeout, then read the logs and take a QMP screendump.

Expected: the loader reports `boot drivers linked: 7` (six plus AHCI), and the kernel console shows AHCI probing and registering a disk rather than `hc0: no devices detected at port 0x1f0`.

- [ ] **Step 4: Run the guest's own fsck**

Boot single-user and run `/sbin/fsck -n` against the root device, capturing the output by screendump.

Expected: the filesystem is reported clean. **This is the acceptance gate** — if fsck reports errors, the allocation is wrong regardless of what our own checker says, and the specific complaint tells you which invariant broke.

- [ ] **Step 5: Record the outcome**

Write the result into `docs/superpowers/specs/2026-09-18-ufs-allocation-design.md` under a short "Outcome" heading: whether fsck passed, whether AHCI loaded, and anything that had to change.

```bash
git add docs/superpowers/specs/2026-09-18-ufs-allocation-design.md
git commit -m "docs: record the UFS allocation acceptance result"
```
