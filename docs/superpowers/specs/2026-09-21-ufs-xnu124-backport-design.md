# UFS/FFS correctness backport from xnu-124

## Goal

Port the UFS/FFS correctness fixes that Apple made between Darwin 0.3 and
xnu-124 into `kernel-7`'s FFS, and prove each one fires.

Every fix here is a refusal or an error path. A machine that boots normally
never reaches any of them, so "it still boots" is evidence of no regression and
nothing else. The work is only finished when each refusal has been made to
happen on purpose.

**Done when:** a clone of `golden.img` still boots with root mounted and
`fsck -n` no worse than its four known graft artifacts, and every refusal that
can be triggered on demand has been observed returning its expected errno
against a filesystem deliberately malformed to trigger it. Three of the eight
changes cannot be triggered on demand; they are named in "The gap worth naming"
rather than quietly counted as done.

## Why these fixes, and why now

`src/kernel-7/bsd/ufs` is the Darwin 0.3 snapshot RhapsodiOS forked in 1999.
`xnu-124` is the same code two years later. A file-by-file diff of the two
trees found that the overwhelming majority of the difference is the Unified
Buffer Cache — `cluster_read`/`cluster_write`, UPL-based pagein/pageout,
`meta_bread`, `ubc_setsize` — which belongs to xnu's osfmk VM and has no
meaning in a Mach 2.5-era kernel built with `nbc`. That architecture is not
portable and is not attempted here.

Underneath it sits a much smaller set of plain correctness fixes that have
nothing to do with UBC: a buffer leaked on an error path, a filesystem mounted
read-write without checking whether it was cleanly unmounted, a vnode handed
out during an unmount. Those are what this spec ports.

## What does not port

Three of the xnu-124 changes look applicable and are not. Each was checked
against the tree rather than assumed.

| Not ported | Why |
|---|---|
| `fs_bsize > PAGE_SIZE` mount refusal | `golden.img` has `fs_bsize` 8192; `I386_PGBYTES` is 4096 (`mach/i386/vm_param.h:44`). A verbatim port refuses the root filesystem and the machine does not boot. The check guards xnu's page-backed bufs; `kernel-7` already bounds block size with `fs_bsize > MAXBSIZE` (`ffs_vfsops.c:535`) and has been serving 8K blocks all along. |
| Two-phase `vflush(SKIPSWAP)` in `ffs_unmount` | `SKIPSWAP` does not exist in `kernel-7` — zero occurrences in the tree. It orders swap-backed vnodes ahead of the final flush, which matters only when UFS is backing swap. |
| `ffs_radvisory` fragment-tail fix | `kernel-7`'s `advisory_read` takes a caller-computed `runt_size` (`bsd/vfs/vfs_cluster.c:561`, called from `ufs_vnops.c:690`). xnu-124's is offset-based and handles the runt internally. Porting the caller without its callee would break readahead rather than fix it. |

The first of these is the reason this spec exists in written form rather than
as a patch. It is not obvious from reading the xnu-124 diff, and it is fatal.

## The changes

Line numbers are from the current tree and were verified individually.

**1. Refuse to mount a filesystem that was not cleanly unmounted.**
`fs_clean` is maintained correctly today — set at `ffs_vfsops.c:192`, `739` and
cleared at `195`, `219`, `675`, `741` — and never once consulted before
mounting. Two gates, matching xnu-124: the root read-write upgrade at
`ffs_vfsops.c:203` refuses with `EPERM`, and `ffs_mountfs` refuses any non-root
filesystem with `ENOTSUP`. Written against `kernel-7`'s `mnt_flag &
MNT_WANTRDWR` (`bsd/sys/mount.h:182`), not xnu's renamed `MNTK_` form.

Gating the upgrade rather than the initial read-only mount is what makes this
safe: the standard boot sequence mounts root read-only, `rc.boot` runs `fsck`,
and the upgrade then succeeds.

**2. Release the buffer when `bread` fails during reload.**
`ffs_reload` returns bare at `ffs_vfsops.c:337` and `:382` without releasing
`bp`. `bread` returns a busy buffer even on failure, so each of these strands
one permanently; later I/O hashing to the same block waits on it forever.

Only these two sites. `ffs_mountfs` looked affected and is not — its error
label at `ffs_vfsops.c:679` already does `if (bp) brelse(bp)`, and its
cylinder-group read at `:561` releases explicitly. The research pass that found
this reported three sites including one in `ffs_mountfs`; that was wrong, and
checking it is the only reason the spec says two.

**3. Reject a fragment size below `DIRBLKSIZ`.**
Added beside the existing geometry checks at `ffs_vfsops.c:535`. Directory code
throughout `ufs_lookup.c` assumes entries are packed and rounded per
`DIRBLKSIZ`; a filesystem with a smaller fragment violates that and fails later,
deep in directory traversal, instead of at mount. `golden.img` has `fs_fsize`
1024 against a `DIRBLKSIZ` of 512 and is unaffected.

**4. Validate the superblock magic before byte-swapping it.**
The `REV_ENDIAN_FS` paths at `ffs_vfsops.c:342` and `:525` swap the entire
in-memory superblock, then check whether the result looks sane. `kernel-7` does
restore it with `byte_swap_sbout` when the check fails, so this is not the
corruption it first appears to be — but it still mutates a shared buffer that
another thread can observe, for no reason. xnu-124 swaps only `fs_magic` into a
local, checks that, and touches nothing else until it knows the volume is
reverse-endian.

**5. Refuse `ffs_vget` during an unmount.**
`ffs_vget` (`ffs_vfsops.c:922`) goes straight to `ufs_ihashget` with no check
that the mount is being torn down, so a lookup racing an unmount can take a
reference on a vnode belonging to a dying mount. Adapted: xnu-124 tests
`mnt_kern_flag & MNTK_UNMOUNT`, which does not exist here, so this uses
`mnt_flag & MNT_UNMOUNT` (`bsd/sys/mount.h:180`) — already set by `dounmount`
at `bsd/vfs/vfs_syscalls.c:417` and already honoured by `bsd/vfs/vfs_subr.c:202`.

**6. Return `EINVAL` for a negative read offset.**
`READ` checks only the upper bound at `ufs_readwrite.c:145`, so a negative
offset becomes an enormous unsigned value and is rejected as `EFBIG`. The right
errno is `EINVAL`. `WRITE` already gets this right at `:301` — read is the only
side that needs it.

**7. Return early from a zero-length write.**
`WRITE` falls into the full allocation and locking path for a request that will
move no bytes. Added after the bounds check at `ufs_readwrite.c:301`.

**8. Stop shadowing the VFS-wide `prtactive`.**
`ufs_inode.c:80` defines `int prtactive = 0;` at file scope while `:97`
declares `extern int prtactive;` inside a function in the same file. The
definition wins for UFS, so toggling the VFS-wide variable silently does not
affect UFS reclaim tracing. Remove the definition.

Note that `ufs_readwrite.c` is textually included (`ffs_vnops.c:266`) rather
than compiled on its own, and carries `#define fs_maxfilesize lfs_maxfilesize`
at `:79` for a parallel LFS build. Changes 6 and 7 therefore reach LFS as well.
LFS is `optional lfs` and appears in neither the i386 nor the ppc config, so
nothing built today is affected, but the coupling is real and worth knowing.

## Verification

Two harnesses, because the two halves of change 1 are reachable from different
places and only one of them involves the root filesystem.

**Harness A — malformed secondary disks.** `ufs_build.py` already produces
single-cylinder-group images for the install floppies, which is exactly the
right size for this. Build one per case, mutate a single superblock field, and
attach them to QEMU as additional disks; then mount each by hand from a
single-user shell and record what comes back. Many cases per boot, and no
multi-gigabyte images anywhere.

| Case | Mutation | Expected | Covers |
|---|---|---|---|
| Unclean non-root mount | `fs_clean = 0` | `ENOTSUP` | 1 |
| Undersized fragment | `fs_fsize = 256` | `ENOTSUP` | 3 |
| Corrupt superblock | `fs_magic` garbage | `EINVAL`, superblock unmodified afterward | 4 |

**Harness B — root overlay.** A qcow2 overlay over `golden.img` with
`fs_clean` cleared, to exercise the root read-write upgrade and its interaction
with `rc.boot`'s `fsck`. Overlays rather than copies: `graft-kernel.py` uses
`shutil.copyfile`, and the APFS `clonefile` trick the allocation work relied on
does not exist on this host.

**Userland probe.** A short program run in the guest covering changes 6 and 7 —
a `pread` at a negative offset expecting `EINVAL`, and a zero-length `write`
expecting success with no side effect.

**Regression.** A `golden.img` clone boots, root mounts read-write, and
`fsck -n` reports nothing beyond the four pre-existing graft-caused complaints
catalogued during the UFS allocation work.

### The gap worth naming

Three changes ship argued rather than demonstrated, and it is worth being
precise about why.

Change 5 is a race. It follows from the code — `dounmount` sets the flag before
calling `VFS_UNMOUNT`, so any `ffs_vget` that observes it is by definition too
late — but there is no way to schedule the two threads against each other on
demand.

Change 2 lives in `ffs_reload`, which runs only on `mount -u -o reload`, and
triggering it needs the superblock read to fail on a filesystem that mounted
successfully a moment earlier. A malformed disk cannot produce that, because a
disk bad enough to fail the read is too bad to have mounted. Doing it properly
means injecting an I/O error at that specific read, which QEMU's `blkdebug`
driver can do. That is a worthwhile harness and it is not part of this spec;
if change 2 is ever suspected, `blkdebug` is the route.

Change 8 is verified by inspection. Its whole observable effect is that a
debugger-set `prtactive` now reaches UFS reclaim tracing, which does not earn a
harness.

## Risks

Change 1 is the only one that alters the behaviour of a working system, and its
failure mode is a machine that will not come up read-write. The hazard in this
development loop specifically: a hard-killed QEMU leaves `fs_clean = 0` on that
work image, and its next boot will refuse the upgrade until `fsck` has run.

This is recoverable and should be documented in the plan rather than designed
around — boot single-user and run `fsck`, or discard the work image, which is a
clone of `golden.img` anyway. Both `golden.img` and `vm/work/test.img` currently
read `fs_clean = 1`, and no host tool in `vm/` touches that byte, so nothing in
the existing tooling is disturbed by making the kernel care about it.

## Out of scope

- Everything UBC-dependent: clustered read and write, UPL pagein/pageout,
  `meta_bread`/`BLK_META`, `ubc_setsize` in truncate, `VHASDIRTY` in sync,
  `cluster_bp` in strategy, and `NODELETEBUSY`.
- `ffs_reallocblks` **stays**. xnu-124 guts it to `return (ENOSPC)` because UBC
  allocates contiguously at write time; here it remains the only mechanism for
  post-hoc block clustering, and removing it would be a pure regression.
- The `ufslabel` volume-naming structure, which is a header addition wired to
  nothing.
- All HFS work.

## Roadmap

This is the first of several specs covering the same research pass. The
remainder, in dependency order:

1. HFS stability fixes on ppc — twelve bugs including a use-after-free in
   `hfs_flushfiles` on a read-only remount, an unmount that records a clean
   volume before confirming the flush, and an integer underflow in
   `hfs_readdir`.
2. HFS endian safety, and enabling HFS on i386 at all. `MASTER.i386` has no
   `hfs`; it is a ppc-only filesystem today. The on-disk format is big-endian
   and nothing in `kernel-7` swaps it, so these two are one piece of work.
3. HFS catalog and B-tree hardening — bounds-checking records read from disk,
   clamping folder valence, CNID allocation.
4. HFS+ text encodings, so non-ASCII filenames survive a round trip.
5. HFS+ hard links.
6. Micro-optimisations: bulk B-tree iteration, the Latin-1 case-fold fast path,
   tightened node search.

UBC is not on this list and will not be. Porting it means replacing the
kernel's VM and buffer cache, which is not a filesystem project.

Implementation happens in a dedicated worktree, not the main checkout.
