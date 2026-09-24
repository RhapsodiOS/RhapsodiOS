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

The strategy hook must stay correct if a B-tree buffer is ever built by
cluster code spanning several nodes. The plan confirms that this cannot happen
for the extents and catalog vnodes, and the hook asserts
`b_bcount == node size`.

### 5. MDB and volume header

Every read and write of these structs gets explicit per-field `SWAP_BE*`:

- `hfs_vfsops.c`: the mount probe (`:511-600`), `hfs_flushMDB` (`:1149`),
  `hfs_flushvolumeheader` (`:1225`, including the wrapper MDB update at
  `:1255-1266`).
- `hfs_vfsutils.c`: `hfs_MountHFSVolume` (`:156`) and `hfs_MountHFSPlusVolume`
  (`:296`), including their special-file extent and fork setup. The
  `bcopy` at `:181` becomes a field-by-field copy.
- `hfs_vnodeops.c:1341` in `hfs_setattrlist` (volume rename rewrites the MDB).
- `hfscommon/Misc/VolumeRequests.c` and `VolumeCheck.c`: the plan first
  establishes which of their MDB/VH sites are reachable in this kernel (much of
  this is Mac OS File Manager code driven by `lowMemParamBlock`). Reachable
  sites are swapped; unreachable ones are listed in the plan and left alone.
- `HFSPlusForkData` in the volume header goes through
  `hfs_swap_HFSPlusForkData`.

### 6. Allocation bitmap

`hfscommon/Misc/VolumeAllocation.c` reads and modifies the bitmap as 32-bit
words (`:657-750`, `:1032-1145` and siblings). Each word load and store gets
`SWAP_BE32`. xnu-124's `VolumeAllocation.c` (21 sites) is the checklist.

### 7. FinderInfo field touches

Because FinderInfo stays big-endian in memory:

- `hfs_vfsutils.c:1077-1082`: storing `kSymLinkFileType`, `kSymLinkCreator`
  and `kIsAlias` needs `SWAP_BE32` / `SWAP_BE16` on the constants.
- `hfs_vfsutils.c:1293`: reading `fdFlags` needs `SWAP_BE16`.

The plan re-greps for any other `finderInfo` field access before closing.

### 8. `mount_hfs` for i386

Build `src/hfs-1/hfs_mount` for i386. The top-level `Makefile.preamble` sets
`INCLUDED_ARCHS = ppc`; the change lets `hfs_mount` build for i386 without
opening the rest of `hfs-1`. Add `SWAP_BE16/32` to its three raw on-disk reads
(`drSigWord`/`drEmbedSigWord`, `drCrDate`, `createDate`), following
diskdev_cmds-143 `mount_hfs.c`. The tool's other behaviour is unchanged.

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

Each test boots a fresh copy of the i386 image as `vm/work/test.img` with a
fresh HFS image attached as a second QEMU disk, and drives the guest over the
existing `guest-console.py` channel. File contents are generated
deterministically from file names with tools already in the Rhapsody userland,
and the host checker mirrors the generator, so only summaries and checksums
cross the console.

### Matrix

| # | Volume | On i386 | Pass |
|---|---|---|---|
| T1 | `devtools.toast` HFS partition, extracted | read-only mount; list the tree; checksum a sample of files | matches the host reader |
| T2 | built HFS | mount; walk; checksum everything | matches the manifest |
| T3 | built HFS+ | same | same |
| T4 | built wrapped HFS+ | same | same |
| T5 | built HFS | read-write: create files and directories until catalog nodes split, rename, delete, write one file spanning bitmap words and blocks, set a volume name, unmount | host checker: zero errors; tree and contents match the guest script |
| T6 | built HFS+ | same | same |
| T7 | built wrapped HFS+ | same | same |
| T8 | T5-T7 output | remount on i386 with a cold cache and re-read everything | matches T5-T7 |

### ppc regression

Build the ppc kernel on the build box from the tree before and after the
change, and compare `__TEXT` of every `bsd/hfs` object with
`tools/binrecon/compare_text.py`. Expected: identical.

## Feasibility gates

These are the first tasks in the plan. Each can change tooling, not the design.

1. **Addressing the second disk.** The i386 disk drivers have a live partition
   (`ATA_HD_LIVE_PART` in `bsd/dev/ata_hd_registry.m:22`; `SD_LIVE_PART`), but
   whether its block device can be opened and mounted is unproven
   (`ATADiskKernel.m:189` special-cases it). If it cannot, the builder wraps
   the volume in a NeXT disk label with one partition, and the extracted
   `devtools.toast` volume is wrapped the same way.
2. **Kernel size.** Confirm an HFS-enabled i386 kernel still fits the graft
   path (`vm/measure-kernel-fit.py`, `vm/graft-kernel.py`) before building on
   that assumption.

## Risks

- **A write path that bypasses `hfs_strategy`.** Mitigation: the plan audits
  every route by which a buffer on the extents or catalog vnode reaches the
  device, and T5-T8 exercise sync, async and delayed writes and unmount
  flushes.
- **mac68k packing differs on i386.** Caught at compile time by component 2,
  before any image is touched.
- **HFS standard has no Apple-made anchor.** Only the HFS+ reader paths are
  anchored by `devtools.toast`. The HFS-standard reader shares most of its
  code (B-tree walking, bitmap check) and is checked against the published
  format; this residual gap is accepted and named rather than hidden.
