# HFS P0 correctness backport from xnu-124

## Goal

Port the crash and corruption fixes that Apple made to HFS between Darwin 0.3
and xnu-124 into `kernel-7`'s HFS, where they apply to this kernel's older
design.

**Done when:** each fix below is applied, reviewed against both trees, and the
ppc kernel — the only configuration that compiles HFS — builds cleanly.

## Why this is its own piece of work

The companion UFS backport (`2026-09-21-ufs-xnu124-backport-design.md`) found
a fairly direct lineage. HFS has diverged much further: xnu-124 has a unified
buffer cache, catalog iterators, HFS Plus hard links and a volume-damage flag,
none of which exist here. A fix copied from xnu-124 often depends on one of
them. So every fix in this spec was researched before any code was written:
each dependency grepped for in `kernel-7`, each patch adapted to the older
design, and anything that could not stand on its own dropped.

The research is in `.superpowers/sdd/hfs-research-{mount,vnops,btree,extents}.md`,
with exact before-and-after code and grep evidence for every symbol. The HFS
sources it read are byte-identical to this branch's.

## What ports

| ID | Bug | Where | Adaptation |
|---|---|---|---|
| A1 | `mount -u -r` on HFS is a guaranteed panic: `hfs_flushfiles` releases and flushes away the catalog B-tree vnode while the volume stays mounted | `hfs_vfsops.c`, `hfs_flushfiles` | One `vflush(mp, NULLVP, SKIPSYSTEM \| flags)` — every B-tree vnode is already `VSYSTEM` — plus `VFS_SYNC` before it and a device fsync after the header, since releasing the catalog was what used to flush it. Unmount is unaffected: `hfs_unmount` never calls `hfs_flushfiles`. Goes one step beyond xnu-124: `mount(2)` sets `MNT_RDONLY` before calling `VFS_MOUNT`, so `hfs_update` would silently discard pending timestamp updates during that sync, and a remount that then failed with `EBUSY` would leave the volume writable without them. `hfs_update` now tests HFS's own `hfs_fs_ronly` rather than the mount flag, so during the sync it still writes while `hfs_access` keeps refusing new writes. After `hfs_flushfiles`, whose reclaims also produce updates, the catalog vnode is fsynced under the catalog lock before the header is written; without the lock the fsync could spin forever on a busy node held by a sleeping B-tree writer. Testing `hfs_fs_ronly` required xnu-124's ordering fix on the read-write upgrade path too: it is now cleared only after the flush succeeds, so a failed upgrade cannot leave a read-only volume that `hfs_update` writes to. |
| A2 | Unmount writes "cleanly unmounted" to disk before confirming the flush, so a failed flush leaves a volume that skips repair next time | `hfs_vfsops.c`, `hfs_unmount` | Fsync catalog, extents and device first; mark clean only after; clear the bit if the header write fails. Does not copy xnu-124's forced-unmount path, which marks clean even after a failed fsync. |
| B1 | `hfs_readdir` underflows an unsigned count, then overruns the caller's buffer — **reachable by any user**: `lseek` a directory to offset 600, `read` 4 bytes | `hfs_vnodeops.c`, `hfs_readdir` | Reject a multi-iovec `uio`, or one smaller than a record, with `EINVAL` up front — using this kernel's fixed 264-byte `struct hfsdirentry`, not xnu-124's variable-length constant. xnu-124's iterator rewrite is not ported. The final review found two more holes in the same function. A negative offset, which `lseek` allows, made the count grow and let `uiomove` read kernel memory at a user-chosen address. And `rootdots + uio_offset` scaled a byte offset by the 264-byte record, which leaked kernel memory in ordinary reads. Negative offsets are now rejected up front, and the pointer uses a byte offset. |
| B2 | `hfs_close` locks and unlocks twice with no revalidation, so a forced unmount can recycle the vnode between | `hfs_vnodeops.c`, `hfs_close` | One lock span over the truncate and `cluster_close`, rechecking `v_type` and `v_id` after locking. Keeps this kernel's `cluster_close` (xnu-124's `cluster_push` needs UBC) and its `LK_CANRECURSE`. Also reads the file length under the lock rather than before it, so a close that waits behind a writer cannot truncate away data that writer just appended. That race predates this work and is in xnu-124 too. |
| C1 | `CheckNode` never checks that a leaf record's on-disk key length fits its slot, so a corrupt node can drive reads and copies past the buffer | `hfscommon/BTree/BTreeNodeOps.c`, `CheckNode` | xnu-124's check, with its renamed `kind`/`kBTLeafNode` mapped back to this kernel's `type`/`kLeafNode`. |
| C2 | A folder's unsigned item count wraps from 0 to about 4 billion and is written to disk | `hfscommon/Catalog/CatalogUtilities.c`, `UpdateFolderCount` | Clamp at zero. xnu-124 also marks the volume damaged; that flag does not exist here. |
| C3 | A node that fails `CheckNode` is released normally and can be handed out again from the buffer cache | `hfscommon/BTree/BTreeNodeOps.c`, `GetNode` | Release it through a new `TrashNode()` with `kReleaseBlock \| kTrashBlock`. This kernel already defines `kTrashBlock`, uses it for the same purpose in `BTOpenPath`, and its release callback turns it into `B_INVAL`. |
| D1 | `ExtendFileC` leaks the blocks it just allocated when the extents B-tree cannot grow | `hfscommon/Misc/FileExtentMapping.c`, `ExtendFileC` | Deallocate them and return `dskFulErr`. Triggers on `dskFulErr` as well as xnu-124's `fxOvFlErr`, because a full disk leaks just the same and both fail before the tree is modified. |
| D2 | The extents B-tree header is flushed only when no error occurred, not when a record was actually created or deleted | `hfscommon/Misc/FileExtentMapping.c` | Two `static` functions gain a record-deleted flag; `ExtendFileC`, `TruncateFileC` and `DeleteFile` flush when it is set. The three parts land together. xnu-124's change to `DeleteFile`'s return value is not ported. The two error variables this left unread in `DeleteFile` are removed; they were never part of its return value. |
| D3 | Newly grown B-tree space is never zeroed, so stale data from a freed file can be read as a node | `hfs_btreeio.c`, `ExtendBTreeFile` | Add `ClearBTNodes` after the EOF update, written for this kernel's five-argument `getblk` and plain `bwrite`. |

## What does not

**A3 — refusing a read-write mount of a dirty HFS volume.** xnu-124 returns
`EINVAL` and leaves repair to userland. Here that would strand the volume: this
tree's `fsck_hfs` never sets the clean bit, and nothing runs it before an HFS
mount, so a refused volume could never become writable again. The in-kernel
`MountCheck()` repair stays. (HFS cannot be root here, so this was never a boot
risk.) Porting A3 needs `fsck_hfs` to mark volumes clean first — userland work,
and a precondition, not part of this spec.

**D4 — locking and contiguous allocation around B-tree growth.** Already
present. `ExtendBTreeFile` at `hfs_btreeio.c:203-230` takes the extents lock and
forces contiguous allocation. The original finding came from reading
`BTreeWrapper.c`'s `SetEndOfForkProc`, which is compiled but dead: both its
callers are under `#if TARGET_OS_MAC`, which is 0 in the kernel. Every live site
takes the catalog lock before the extents lock.

**The volume-damage flag.** Several xnu-124 fixes (A2, C2, C3) also set
`kHFS_DamagedVolume` so that unmount leaves the volume marked for repair.
Neither the flag nor anything that reads it exists here, and this spec does not
invent it. What is lost: a volume that hits a B-tree error while mounted still
unmounts "clean", exactly as it does today.

## Verification

HFS compiles only into the ppc kernel — `conf/MASTER.i386` has no `hfs` — and
there is no ppc machine or emulator here to boot one. So these fixes can be
**compiled** but not run.

That puts the weight on review. Every fix was researched against both trees
before being written, and each patch is reviewed against its research entry
and against `kernel-7` itself, with every identifier confirmed to exist.

The one available hard check is the ppc build. It must complete cleanly, and
it is the gate this spec is done at.

Running these fixes needs HFS enabled on i386, which in turn needs this
kernel to byte-swap HFS's big-endian on-disk structures. That is the roadmap's
endian-safety spec, and the point at which these fixes can actually be
exercised.

## Out of scope

- A3 and D4, above.
- Everything from the original comparison that is not a P0: HFS Plus hard
  links, text encodings, endian safety, the unified buffer cache.

## Outcome

Compiled on 2026-09-23 from branch `xnu124-p0-integration`: this backport plus
the companion UFS one, which touch disjoint files.

**The first compile of these fixes was not what it claimed.** The ppc build
first reported as compiling all six files had in fact compiled master's
unpatched sources. The build box's `/build/src` is shared, and another session
re-synced `kernel-7` between this branch's i386 and ppc builds. The compiler's
warnings named lines such as `hfs_vnodeops.c:579`, which is blank at HEAD; it
is where `cluster_close` sat before B2 moved it. The final whole-branch review
caught this by comparing those line numbers with HEAD.

**The verified rebuild compiled every changed HFS file for ppc without
errors**: `hfs_vfsops.c`, `hfs_vnodeops.c`, `hfs_btreeio.c`, `BTreeNodeOps.c`,
`CatalogUtilities.c` and `FileExtentMapping.c`, plus the header
`BTreesPrivate.h`. Two checks prove it saw this branch's sources:
- a `cksum` of each changed file on the box matched HEAD before, between and
  after the builds;
- each warning's reported line holds the construct warned about at HEAD. For
  example, `cluster_close`'s implicit declaration is reported at
  `hfs_vnodeops.c:592`, exactly where B2 put it.

No warning falls on a line this series introduced, apart from `cluster_close`'s
implicit declaration, which is old code that B2 moved verbatim. The full ppc
build still does not link, for reasons unrelated to this work:
- the final link wants a `pexpertpowermac.o` the box lacks;
- the first attempt stopped even earlier, on a `conf/Makefile.ppc` line the
  box's GNU Make cannot parse. That is filed separately.

That compile is the gate this spec set. It is also the only hard check these
fixes have had, because there is no ppc machine or emulator here to run them.

**Review.** The series went through four rounds.
- Round one confirmed all ten patches against their research, and found one
  Important issue: A1's sync discarded pending catalog updates.
- Fixing that introduced a Critical issue, found in round two: an unlocked
  catalog fsync that could spin forever on a non-preemptive kernel.
- Round three approved the resulting design.
- The final whole-branch review found B1 incomplete. A negative directory
  offset still made `hfs_readdir` overrun the caller's buffer and read kernel
  memory at a user-chosen address. A pre-existing pointer-scaling bug in the
  same function leaked kernel memory in ordinary small-buffer reads. Both are
  fixed; see B1.

**Deferred.** Each of these is Minor or pre-existing, and each was accepted in
the final review:
- the read-only remount does not fsync the extents B-tree under its lock;
- D1 fixes `ExtendFileC`'s outer leak, but not a nested extension of the
  extents file, exactly as in xnu-124;
- C2 does not clamp the volume-level root counts;
- D3 keeps a dead `NULL` check, for parity with xnu-124;
- A2 prints lock warnings on DIAGNOSTIC kernels;
- D3 may leave a small range unzeroed after an earlier partial extension.

One problem spotted on the way is filed as its own task: the `getdirentryattr`
system call leaves `uio_offset` uninitialised before calling into
`hfs_readdirattr`.
