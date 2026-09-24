# HFS on i386: kernel endian port

## Goal

Make `kernel-7`'s HFS filesystem work on i386. HFS and HFS+ are big-endian on
disk; the kernel code was written for ppc and reads every on-disk field raw.
This spec ports the kernel side, plus the one userland tool needed to exercise
it (`mount_hfs`).

**Done when:**

1. The i386 kernel builds with `hfs`, and compile-time size/offset checks pass
   for every on-disk struct on both architectures.
2. Every HFS object in the ppc kernel has an identical `__TEXT` section before
   and after the change.
3. The Apple-mastered wrapped HFS+ volume in `vm/devtools.toast` mounts
   read-only on i386, and its listing and file checksums match the host-side
   reader.
4. Host-built HFS, HFS+ and wrapped HFS+ volumes mount read-write on i386. After
   the guest creates, renames and deletes enough to split catalog nodes and
   allocate across bitmap words and blocks, the host checker reports zero
   consistency errors, and the tree and contents match what the guest did.
5. Those volumes, remounted on i386 with a cold cache, read back identically.

All boot testing uses throwaway disk images (CLAUDE.md §6).

## Out of scope

- `newfs_hfs` and `hfs.util` from `src/hfs-1`: spec 2.
- `fsck_hfs` in `src/Commands/diskdev_cmds`: its own spec. The host checker
  below replaces it as the oracle here.
- `hfs_glue` (VDI library): it talks to the kernel through `getattrlist` and
  is expected to be endian-neutral; it is looked at in spec 2.
- Anything from xnu-124 that is not about byte order: UBC, cluster I/O, cnode
  and VFS renames. The UFS backport spec
  (`2026-09-21-ufs-xnu124-backport-design.md`) already rules that layer out as
  unportable.

## Where things stand

- `conf/MASTER.i386:72` omits `hfs` from both `RELEASE` and `DEBUG`;
  `conf/MASTER.ppc:72` has it. HFS has never been compiled for i386.
- `bsd/hfs` (~50k lines) contains no byte swapping at all, and nothing in it
  branches on `BYTE_ORDER`, `TARGET_RT_*` or CPU, and it has no inline asm.
  There are no half-finished endian paths to untangle.
- `hfscommon/headers/system/ConditionalMacros.h:486-560` hard-codes
  `TARGET_CPU_PPC 1` and `TARGET_RT_BIG_ENDIAN 1` for every gcc build. It is
  wrong on i386, though currently unread by HFS.
- On-disk structs are laid out with `#pragma options align=mac68k` (six
  headers). Apple's cc implements that pragma in
  `cc-1/cc/config/next/nextstep.c:152` under `APPLE_MAC68K_ALIGNMENT`, which
  `config/next/nextstep.h:161` defines for every NeXT target, i386 included.
  Expected to be fine; proven, not assumed (component 2).
- `hfs_vfsutils.c:181` copies the MDB into the VCB with one `bcopy`, relying on
  identical field order and byte order.
- `vm/golden.img` (i386) has no `mount_hfs` and no `hfs.fs`.

## Reference

xnu-124.7 `bsd/hfs` is the same code two years later, already running on
little-endian x86. Its swap model is adopted, and it is used as a **map of
which sites need a swap**. Code is written against `kernel-7`'s own sources,
not copied from xnu. The mechanical diffs are large because xnu reorganised
files (for example, `VolumeRequests.c` is 3226 lines here and 491 there), but
the functions that touch disk bytes are the same functions.

For `mount_hfs`, the reference is diskdev_cmds-143
(`apple-oss-distributions/diskdev_cmds` @ `a768f5c`), `mount_hfs.tproj` and
its `hfs_endian.h`.

## Approach

Nodes of the extents and catalog B-trees are swapped **whole**, to host order,
when they come into the buffer cache, and back to big-endian when they go out.
The B-tree, catalog and extent code in `hfscommon` then runs unchanged in host
order. Everything outside B-tree nodes (MDB, volume header, allocation bitmap,
fork data in the volume header) is swapped field by field where it is read or
written.

Rejected alternatives:

- **Replace `bsd/hfs` with xnu-124's.** It is endian-clean but depends on UBC
  and renamed VFS interfaces that `kernel-7` does not have.
- **Keep nodes big-endian in memory and swap at every field access.** That
  means hundreds of sites across B-tree, catalog and extent code with no
  reference to check against, and every missed site is silent corruption.

## Components

### 1. Build enablement

- Add `hfs` to the `RELEASE` and `DEBUG` lists at `conf/MASTER.i386:72`.
- Correct `ConditionalMacros.h`'s gcc branch to derive `TARGET_CPU_*` and
  `TARGET_RT_*_ENDIAN` from `__i386__` / `__ppc__`, so any future use is right
  on both architectures. On ppc the values are unchanged.
- Fix whatever else fails to compile on i386. Each fix must be ppc-neutral.

### 2. Layout proof

One header, included by the HFS sources, with compile-time checks: the
negative-array-size idiom, since this cc has no `_Static_assert`. It covers
`sizeof` and key field offsets of:

- `HFSMasterDirectoryBlock`, `HFSPlusVolumeHeader`
- `BTNodeDescriptor`, `BTHeaderRec`
- HFS and HFS+ catalog keys, folder, file and thread records
- HFS and HFS+ extent keys and extent records
- `HFSPlusForkData`, `HFSPlusExtentDescriptor`

Expected values come from Apple's published format (TN1150 and the HFS format
in *Inside Macintosh: Files*), not from compiling on ppc. The header generates
no code.

### 3. Swap layer: `bsd/hfs/hfs_endian.[ch]`

Ported from xnu-124.7 and adapted to `kernel-7`'s struct names:

- `SWAP_BE16/32/64` map to `NXSwapBig{Short,Long,LongLong}ToHost`, and are
  identity on big-endian.
- `hfs_swap_BTNode(block, isHFSPlus, fileID, direction)` swaps a whole node of
  the extents or catalog tree, HFS or HFS+, in either direction: the
  descriptor, the offset table, keys (including HFS+ `UniChar` names) and
  records.
- **FinderInfo stays big-endian and opaque in memory**, exactly as in xnu-124
  (`/* Don't swap srcRec->userInfo */`). `getattrlist` hands userland the same
  bytes on both architectures.
- The file is added to `conf/files` as `optional hfs`. Its body is under
  `#if BYTE_ORDER == LITTLE_ENDIAN`.

### 4. B-tree node boundary

**Read side, `GetBTreeBlock` (`hfs_btreeio.c:69`).** After `bread`/`getblk`,
unless `kGetEmptyBlock` is set, swap the node to host order when the last
`UInt16` of the node reads as a big-endian 14. The first record always starts
at offset 14 (`sizeof(BTNodeDescriptor)`), so this sentinel tells the two
orders apart, and a buffer that was written out big-endian and stayed cached
is re-swapped automatically. The header-node special case (node size not yet
known when the tree is first opened) follows xnu-124's `hfs_btreeio.c:114-133`.

**Write side, `hfs_strategy` (`hfs_readwrite.c:1125`).** This is a labelled
divergence from xnu-124, which traps writes in `VOP_BWRITE`. In `kernel-7`,
B-tree buffers reach the disk without passing through `VOP_BWRITE`:
`ReleaseBTreeBlock` calls `bwrite()` directly (`hfs_btreeio.c:138`, `142`),
and `blkflush` does too (`vfs_bio.c:963`). Every write of an HFS vnode buffer
does pass through `hfs_strategy`. For a write (`!(b_flags & B_READ)`) on the
extents or catalog vnode whose node is in host order by the sentinel, swap it
to big-endian before handing it to the device. The buffer is `B_BUSY` for the
whole I/O, so no one observes the big-endian bytes, and the read-side sentinel
restores host order on next use. An all-zero buffer (never initialised) is
left alone, as in xnu-124.

A host-order buffer whose size is not the tree's node size (from the file's
`BTreeControlBlock`) is refused, so a buffer spanning several nodes can never be
half-swapped.

Unlike xnu-124, which panics, a node that fails validation is never swapped
and never panics the kernel. The swap validates the whole node first (the
offset table, then every key and record against the bounds of its slot), and
only then changes any byte. On read, `GetBTreeBlock` invalidates the buffer
and returns `EIO`. On write, `hfs_strategy` fails the I/O with `EIO`. Both log
one `hfs: ` line. This matches the P0 series, which made corrupt nodes fail
safely rather than crash.

### 4a. B-tree node map words

Map records, in the header node and in map nodes, are not swapped with the
node; they stay big-endian, and the four places in
`hfscommon/BTree/BTreeAllocate.c` that read or modify a map word swap that
word (xnu-124 does the same). These are `AllocateNode`'s read and set, `FreeNode`'s
clear, and `ExtendBTree`'s set.

### 4b. Attributes B-tree

`hfs_endian.c` knows the catalog and extents record formats only. On a
little-endian host, `hfs_MountHFSPlusVolume` refuses, with `EINVAL` and one
`hfs: ` line, an HFS Plus volume whose attributes B-tree is non-empty. Mac OS
8 and 9 never create one, and neither does kernel-7.

### 5. MDB and volume header

Each function that reads or writes one of these structs swaps the whole
struct to host order in place right after its `bread`, and back to disk order
right before the buffer is released or written. `SWAP_MDB(p)` and `SWAP_VH(p)`
expand to self-inverse full-struct swaps on little-endian hosts and to nothing
on ppc, so the existing field code, including the two MDB-to-VCB `bcopy`s in
`hfs_MountHFSVolume`, is untouched and sees host-order values. The sites are:

- `hfs_vfsops.c`: `hfs_mountfs` (MDB probe, wrapperless and wrapped volume
  headers), `hfs_flushMDB`, `hfs_flushvolumeheader` (including its wrapper
  MDB update).
- `hfs_vfsutils.c` needs no MDB/VH changes: `hfs_MountHFSVolume` and
  `hfs_MountHFSPlusVolume` receive already-swapped structs.

Checked and left alone: `hfs_vnodeops.c:1341` sits inside `#if 0`.
`FlushAlternateVolumeControlBlock` copies the MDB or volume header block to its
alternate location as raw bytes, which is endian-neutral because every other
writer leaves those buffers in disk order. `CheckCreateDate` returns before
touching the MDB. The remaining `VolumeRequests.c` MDB/VH code is Mac OS only
(`TARGET_OS_MAC`) or unreachable from this kernel. Volume `drFndrInfo`, like
all Finder information, stays big-endian.

### 6. Allocation bitmap

`hfscommon/Misc/VolumeAllocation.c` reads and modifies the bitmap as 32-bit
words in eight functions. The kernel reads and writes the bitmap in 512-byte
blocks of 4096 bits (`kBitsPerBlock`). Each of the 34 word loads, stores and
masked compares gets `SWAP_BE32`; xnu-124's `VolumeAllocation.c` (21 sites) is
the cross-check. The two sites that compare with or store zero are
endian-neutral and are left alone.

### 7. FinderInfo field touches

Because FinderInfo stays big-endian in memory:

- `hfs_vfsutils.c:1077-1082`: storing `kSymLinkFileType`, `kSymLinkCreator`
  and `kIsAlias` needs `SWAP_BE32` / `SWAP_BE16` on the constants.
- `hfs_vfsutils.c:1293`: reading `fdFlags` needs `SWAP_BE16`.

The plan re-greps for any other `finderInfo` field access before closing.

### 8. `mount_hfs` for i386

Build `src/hfs-1/hfs_mount` for i386. The top-level `Makefile.preamble` sets
`INCLUDED_ARCHS = ppc` and passes it to every subproject through
`OTHER_RECURSIVE_VARIABLES`. Both lines move into the preambles of
`hfs_glue`, `hfs_util` and `hfs_newfs`, which keep building for ppc only,
while `hfs_mount` builds for every architecture (`pb_makefiles-1/recursion.make:75-84`
filters per project and suppresses a project left with none). Add `SWAP_BE16/32` to
the four raw on-disk reads in `getVolumeCreateDate`
(`drSigWord` twice, `drEmbedSigWord`, `drCrDate`, `createDate`), following
diskdev_cmds-143 `mount_hfs.c`, with the macros in a new local
`hfs_mount/hfs_endian.h`. The tool's other behaviour is unchanged. golden.img
has no `/sbin/mount_hfs` and the root image cannot take new files, so the
tests run the binary from the results disk.

### The ppc invariant

Every kernel change is either a macro that is identity on big-endian or code
under `#if BYTE_ORDER == LITTLE_ENDIAN`, apart from the `ConditionalMacros.h`
correction (same values on ppc) and the layout-check header (no code). That is
what makes "ppc HFS `__TEXT` unchanged" a reachable bar. If a change cannot
meet it, the plan stops and names it rather than accepting a difference.

## Test harness

### `tools/hfsimg/` (host, Python 3, standard library only)

**Reader/checker.** It parses the MDB or volume header (including the wrapper
and its embedded HFS+ volume), walks the catalog and extents B-trees, and
reports:

- node structure: descriptor kinds and heights, the offset table, key ordering
  within and across nodes, sibling links, header-record counts, the node
  allocation map
- the allocation bitmap equals the union of every file's extents plus the
  special files, with no overlaps
- folder valences, and file and folder counts against the MDB/VH
- a listing of the tree, and extraction of files for checksumming

**Builder.** From a manifest of directories and files, it writes a whole-disk
image as HFS, HFS+, or HFS+ wrapped in HFS. Default manifests are sized to
force a catalog tree at least two levels deep, at least one extents-overflow
record, and files spanning more than one bitmap block.

**Anchor.** The reader must parse the Apple-mastered volume in
`vm/devtools.toast` (Apple partition map entry 8, `Apple_HFS` at sector 968,
1324080 sectors; MDB signature `BD`, embedded `H+`, volume name
`Mac_OS_X_CD`) with zero check failures before it is used to judge anything
else. This keeps the reader and the kernel from sharing a misreading of the
format.

### Guest side

Each test boots the per-session root image (`RHAP_TEST_IMAGE`) through
`guest-console.Guest` with two more IDE disks, both `snapshot=off`:

- **index 1, the HFS volume under test**, as partition `a` of a NeXT disk
  label, which the kernel opens as `/dev/hd1a`. The block device of a disk's
  live partition cannot be opened (`bsd/dev/ata_hd_registry.m:585-589` returns
  `nil` for it), so a label is required. The label must say `dl_secsize 512`:
  a partition's block size is its label's `dl_secsize`
  (`driverkit-3/libDriver/IODiskPartition.m:1531`), the ATA strategy passes
  `b_blkno` through in those units (`ata_hd_registry.m:857`), and HFS
  addresses the device in 512-byte blocks (`hfs_mountfs` sets
  `hfs_phys_block_size` to 512). The images therefore copy the installation
  floppy's label area and rewrite every label copy from 1024-byte to 512-byte
  sectors.
- **index 2, a small UFS results disk** (`/dev/hd2a`), built with
  `vm/ufs_build.py`. It holds the guest script `run.sh`, the i386 `mount_hfs`
  and an `h/` mount point. The guest mounts it at `/mnt`, runs `/mnt/run.sh`,
  and leaves `out.txt`, `list.txt` (the `find` listing) and `sums.txt`
  (`cksum` of each file) on it. The host reads them back with
  `vm/rhap_image.py` after qemu exits. Nothing needs to cross the console,
  which is output-only; kernel `printf`s still land in the serial log, which
  the host also scans for `panic` and `hfs: ` lines.

File contents are generated deterministically from file names (the name and a
newline, repeated) by a one-line `perl` on the guest and by
`tools/hfsimg/content.py` on the host.

**Scope limit this exposes.** The HFS kernel assumes 512-byte device blocks.
On i386 that holds only for a NeXT-labelled partition with
`dl_secsize 512`. Standard i386 NeXT labels use 1024, Apple partition maps are
read on ppc only (`GROK_APPLE`, `IODiskPartition.m:79`), and CD-ROMs have
2048-byte sectors. Teaching HFS the device block size, as xnu-124's
`hfs_mountfs` does with `DKIOCGETBLOCKSIZE`, is a separate follow-up; this
spec does not attempt it.

### Matrix

| # | Volume | On i386 | Pass |
|---|---|---|---|
| T1 | `devtools.toast` HFS partition, extracted | read-only mount; list the tree; checksum a sample of files | matches the host reader |
| T2 | built HFS | mount; walk; checksum everything | matches the manifest |
| T3 | built HFS+ | same | same |
| T4 | built wrapped HFS+ | same | same |
| T5 | built HFS | read-write: create 150 files and 20 folders (enough to split catalog nodes and grow the catalog file), rename and move, delete, rewrite a file larger, delete the file with extents-overflow records, write one 20 MiB file spanning several bitmap blocks, unmount | host checker: zero errors; tree and contents match the guest script |
| T6 | built HFS+ | same | same |
| T7 | built wrapped HFS+ | same | same |
| T8 | T5-T7 output | remount on i386 with a cold cache and re-read everything | matches T5-T7 |

### ppc regression

Build the ppc kernel on the build box from the tree before and after the
change, and compare every `__TEXT` section, bytes and relocations, of every
`bsd/hfs` object with `tools/hfsimg/macho_text.py`. Expected: identical. This
is sound because RELEASE_PPC compiles in neither `MACH_ASSERT` (a `<test>`
option in `conf/MASTER:119`) nor `DIAGNOSTIC`, so no `__LINE__` reaches ppc
code and moved lines cannot show up as differences.

## Feasibility gates

1. **Device nodes.** The first boot confirms that the HFS disk appears as
   `/dev/hd1a` and the results disk as `/dev/hd2a`, that `snapshot=off` lets
   the guest's writes reach both files while the root disk stays in snapshot
   mode, and that the 512-byte label is accepted (`check_label` checks only
   the magic number, location and checksum).
2. **Graft.** The boot tests graft the kernel into `golden.img` through
   `vm/graft-kernel.py`, whose donor is a 23 MB file. The spec's earlier
   mention of `measure-kernel-fit.py` was wrong: that tool measures the
   installation floppy, which these tests do not use.

## Risks

- **A write path that bypasses `hfs_strategy`.** Every write of a buffer
  belonging to an HFS vnode reaches the device through `VOP_STRATEGY` on that
  vnode, which is `hfs_strategy`. The one other B-tree reader,
  `BTreeScanner.c`'s `ReadMultipleNodes`, is Mac OS only and falls back to
  `GetNode` on Rhapsody, so every read goes through `GetBTreeBlock`. T5-T8
  exercise sync, async and delayed writes and unmount flushes.
- **mac68k packing differs on i386.** Caught at compile time by component 2,
  before any image is touched.
- **HFS standard has no Apple-made anchor.** Only the HFS+ reader paths are
  anchored by `devtools.toast`. The HFS-standard reader shares most of its
  code (B-tree walking, bitmap check) and is checked against the published
  format; this residual gap is accepted and named rather than hidden.
