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
against a filesystem deliberately malformed to trigger it. Four of the six
changes cannot be demonstrated here; they are named in "The gap worth naming"
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
| `extern int prtactive` in `ufs_inode.c` | In xnu-124 this stops UFS shadowing a VFS-wide variable. In `kernel-7` there is nothing to shadow: `ufs_inode.c:80` is the **only** definition in the tree, and HFS, cd9660, msdosfs and NFS all reference it as `extern`. Making UFS `extern` too leaves the symbol undefined and the kernel unlinkable. |
| `fs_fsize < DIRBLKSIZ` mount refusal (was change 3) | `DIRBLKSIZ` is 1024 in this build, not 512: the kernel compiles with `-D__APPLE__` (`conf/Makefile.template:104`), which selects it (`ufs/ufs/dir.h:102-103`). xnu-124 builds the same way, but no hazard from 512-byte fragments was found in this kernel, and the check does not catch what it looks like it should: keying on fragment size, it passes a volume made by another BSD, since 4.4BSD's `newfs`, like this tree's (`src/Commands/diskdev_cmds/newfs.tproj/newfs.c:115`), defaults to 1K fragments. What it would do is refuse a `newfs -f 512` volume, and make a root like that unbootable. Ported, reviewed, then dropped. |

The first of these is the reason this spec exists in written form rather than
as a patch. It is not obvious from reading the xnu-124 diff, and it is fatal.

## The changes

Line numbers are from the tree as it stood before this series, and were
verified individually. They drift as the edits below land.

**1. Refuse to mount a filesystem that was not cleanly unmounted.**
`fs_clean` is maintained correctly today — set at `ffs_vfsops.c:192`, `739` and
cleared at `195`, `219`, `675`, `741` — and never once consulted before
mounting. Two gates:

- `ffs_mountfs` refuses a read-write mount of a non-root filesystem with
  `EOPNOTSUPP`. This kernel predates the POSIX name `ENOTSUP` that xnu-124 uses;
  `bsd/sys/errno.h:134` defines only `EOPNOTSUPP`. Read-only mounts are allowed,
  and that exemption is load-bearing: root is first mounted through this same
  function before `MNT_ROOTFS` is set (`bsd/kern/init_main.c:579`), so only the
  `MNT_RDONLY` that `vfs_rootmountalloc` gives it tells the two apart. Without the
  exemption a dirty root would be refused at boot. xnu-124 has no such exemption.
- A read-write upgrade of a dirty filesystem is refused with `EPERM`: always for
  a non-root filesystem, and for root only when the machine was booted
  single-user, as xnu-124 does. Root in multi-user prints
  `ffs: / was unclean when mounted; mounting read-write anyway` and proceeds, so
  a normal boot is never stranded read-only. Gating non-root upgrades closes a
  bypass the read-only exemption would otherwise open: `mount -r` followed by
  `mount -uw`. xnu-124 avoids that by refusing even the read-only mount.
  Refusals name the live mount point (`mnt_stat.f_mntonname`), not the name
  recorded on disk. `issingleuser()` does not exist here; `boothowto &
  RB_SINGLE` is its equivalent. Written against `kernel-7`'s `mnt_flag &
  MNT_WANTRDWR` (`bsd/sys/mount.h:182`), not xnu's renamed `MNTK_` form.

The upgrade gate cannot trust the in-memory `fs_clean`. Rhapsody's `fsck` marks the
disk clean *without* reloading the root when that is its only repair —
`src/Commands/diskdev_cmds/fsck.tproj/utilities.c:375-383` saves and restores
`fsmodified` around the write, and `main.c:413` reloads only if `fsmodified` —
which is the usual case after a crash. So on the one path that would refuse, the
gate first rereads the superblock with `ffs_reload` and refuses only if the
disk is still dirty. (`ffs_reload` keeps `fs_ronly` set across its copy; see
change 2.) xnu-124 forces that reload
before every upgrade of a read-only filesystem; this port confines it to the
refusal path, so a normal boot never runs `ffs_reload`.

**2. Release the buffer when `bread` fails during reload.**
`ffs_reload` has three `bread` calls that return without releasing `bp`: the
superblock at `ffs_vfsops.c:337`, the cylinder-group summary at `:382`, and the
per-vnode inode re-read in its Step 6 loop. `bread` sets `*bpp` before it waits
(`bsd/vfs/vfs_bio.c:305-308`), so it returns a held buffer even on failure. Each
of these strands one busy, and later I/O to the same block sleeps on it forever.

`ffs_mountfs` is not affected: its error label already does `if (bp) brelse(bp)`,
and its cylinder-group read releases explicitly. An earlier draft of this spec
"corrected" the research pass's three sites down to two, having searched for
only one spelling of the call. Review found the third, in Step 6. Since the
Task 7 gate now calls `ffs_reload`, all three are reachable from one more path.

`ffs_reload` needed two more fixes once the gate started calling it. Its copy
of the on-disk superblock also overwrote `fs_ronly` (0 after any read-write
mount) and the 4 GB `fs_maxfilesize` limit that `ffs_mountfs` imposes under
`NeXT`. It now sets `fs_ronly` back to 1 — always correct there, since it
refuses to run unless the mount is read-only — and re-applies the limit through
a helper shared with `ffs_mountfs`. Both were pre-existing, and also affected
`fsck`'s own reload of the root.

**3. Dropped: a fragment size below `DIRBLKSIZ`.** Ported, reviewed, then
removed. See "What does not port". The numbering of the other changes is kept
so the plan's task references still line up.

**4. Validate the superblock magic before byte-swapping it.**
The `REV_ENDIAN_FS` path in `ffs_mountfs` at `ffs_vfsops.c:525` swaps the entire
in-memory superblock, then checks whether the result looks sane. The reload path
at `:342` is not affected: it swaps only a superblock already established as
reverse-endian at mount time, so there is nothing speculative to guard. `kernel-7` does
restore it with `byte_swap_sbout` when the check fails, so this is not the
corruption it first appears to be — but it still mutates a shared buffer that
another thread can observe, for no reason. xnu-124 swaps only `fs_magic` into a
local, checks that, and touches nothing else until it knows the volume is
reverse-endian.

The same block also held a genuine memory-safety bug. It entered
`byte_swap_sbin` whenever the superblock merely looked wrong — including one with
native `FS_MAGIC` and an out-of-range `fs_bsize`. `byte_swap_sbin` sizes part of
its in-place swap from byte-swapped `fs_postbloff`, `fs_cpc` and `fs_nrpos`
(`ufs/ufs/ufs_byte_order.c:97-101`), which are garbage for a native superblock,
so a corrupt disk could drive a write outside the buffer. With the magic gate in
front, the magic is known to be one of the two values, so the block now swaps
only when it is `FS_MAGIC_SWAPPED`. A native superblock with a bad block size is
rejected by the ordinary validation that follows.

What remains: a superblock that genuinely carries `FS_MAGIC_SWAPPED` but is
otherwise corrupt still reaches `byte_swap_sbin`, whose swap is sized from the
superblock's own fields and is not bounds-checked. Closing that means validating
those fields before the swap, which is beyond this spec.

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
errno is `EINVAL`. `WRITE` also rejects a negative offset, at `:301`, though
with `EFBIG` rather than `EINVAL`, as xnu-124 does. This change leaves it alone.

**7. Return early from a zero-length write.**
`WRITE` falls into the full allocation and locking path for a request that will
move no bytes. Added after the bounds check at `ufs_readwrite.c:301`.

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
| Unclean non-root mount | `fs_clean = 0` | `EOPNOTSUPP` | 1 |
| Corrupt superblock | `fs_magic` garbage | `EINVAL`, superblock unmodified afterward | 4 |

**Harness B — unclean root.** Clear `fs_clean` in `vm/work/test.img` and boot,
to exercise the root read-write upgrade and its interaction with `rc.boot`'s
`fsck`. A qcow2 overlay was the first idea and is not worth it: every `-drive`
in the tree hardcodes `format=raw`, so an overlay means editing the runners,
and the thing being changed is one byte in an image that `reset-image.cmd`
already rebuilds from `golden.img` on demand.

**Regression.** A `golden.img` clone boots, root mounts read-write, and
`fsck -n` reports nothing beyond the four pre-existing graft-caused complaints
catalogued during the UFS allocation work.

### The gap worth naming

Four of the six changes ship argued rather than demonstrated. The two that are
demonstrated — the mount gate and the magic pre-check — are the two that change
what the kernel refuses, which is where the risk is. The rest are worth being precise about.

Changes 6 and 7 would need a program in the guest calling `pread` at a negative
offset and `write` with a count of zero. There is no way to get one there: the
guest console accepts synthetic keystrokes whose keymap has no `#`, so C source
cannot even be typed in, and no compiler or file-transfer path into a running
guest exists. Both changes are two lines with no failure mode beyond returning
a different errno, so they ship on inspection.

Change 5 is a race. It follows from the code — `dounmount` sets the flag before
calling `VFS_UNMOUNT`, so any `ffs_vget` that observes it is by definition too
late — but there is no way to schedule the two threads against each other on
demand.

Change 2 lives in `ffs_reload`, which runs when `fsck` reloads a repaired
read-only root and from the upgrade gate, and
triggering it needs the superblock read to fail on a filesystem that mounted
successfully a moment earlier. A malformed disk cannot produce that, because a
disk bad enough to fail the read is too bad to have mounted. Doing it properly
means injecting an I/O error at that specific read, which QEMU's `blkdebug`
driver can do. That is a worthwhile harness and it is not part of this spec;
if change 2 is ever suspected, `blkdebug` is the route.

## Risks

Change 1 is the only one that alters the behaviour of a working system, and its
failure mode is a machine that will not come up read-write. The design keeps
that failure narrow: the non-root gate spares every read-only mount, which is how
root is first mounted, and the root gate refuses only in single-user. In this
development loop, a hard-killed QEMU leaves `fs_clean = 0` on that work image; a
multi-user boot of it warns and carries on, and a single-user boot refuses
`mount -uw /` until `fsck` has run.

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

## Outcome

Built and booted on 2026-09-23, from branch `xnu124-p0-integration`: these UFS
changes plus the companion HFS backport, which touch disjoint files. There were
two rounds. The first round's harness could not settle two of its claims. Then
the final whole-branch review found that the first round's ppc build had
compiled the wrong sources. So everything was rebuilt and the harness re-run.

### Builds

The build box's `/build/src` is shared with other sessions, and that nearly
produced a false result.

**The first ppc build compiled master's unpatched sources.** Another session
re-synced `kernel-7` between our i386 and ppc builds. The mismatched warning
line numbers were explained away as compiler drift, until the final review
compared them with HEAD.

**The rebuild proved its inputs.**
- A `cksum` of each of the nine changed files on the box matched HEAD at three
  points: before the i386 build, between the two builds, and after the ppc
  build.
- Every warning the compilers reported names a line whose content at HEAD is
  the construct warned about. For example, the 4 GB constant is reported at
  `ffs_vfsops.c:330`, where the stale build had reported `:668`.
- The rebuild caught a second trap on the way: `rbuild` silently reused a stale
  cached i386 package, given away only by a 455-byte build log.

**i386: clean.** No warning falls on a line this series changed. Seventeen
pre-existing warnings remain in `bsd/ufs`. They include "integer constant out
of range" on the 4 GB constant, which change 2's helper moved verbatim. This
kernel differs from the first round's, and it carries the final message
strings.

**ppc: every changed file compiled without error.** The build still does not
produce a kernel, for reasons unrelated to this work:
- The first ppc attempt stopped at `fdesc_vnops.o`. There, `conf/Makefile.ppc:61`
  uses a GNU Make target-specific variable (from `a5236b800`, the msdosfs work)
  that the box's GNU Make 3.74 cannot parse. Keep-going mode (`MAKEFLAGS=k`) got
  past it.
- By the rebuild, `fdesc_vnops.c` compiled on the shared box. The only failure
  left was the final link, which wants a `pexpertpowermac.o` the box does not
  have.

The Makefile problem is filed separately. This branch syncs neither `conf/` nor
the platform expert.

### Boot harness

Every boot ran through `guest-console.py`'s `Guest`:
- on QMP port 4491;
- against the private image named by `RHAP_TEST_IMAGE`;
- under QEMU's `-snapshot`;
- reading kernel output from the serial log.

Round 2 used the rebuilt kernel.

| Run | Round | What it tests | Result |
|---|---|---|---|
| 1 | 1, 2 | The evidence channel | **Pass.** `serial_dbg: i386 kernel console up` reached the log, and there were no `ffs: ` lines on a clean image. In round 2, answering `y` at a "Continue without network?" prompt took the boot through to the Setup Assistant. |
| 2 | 1 | A second disk mounts single-user | **Pass**, as `/dev/hd1a`. The stock kernel wedges here (`hc0: interrupt timeout, cmd: 0xc4`). |
| 3 | 1 | Change 4, corrupt magic | **Pass.** One `ffs: superblock magic invalid, refusing` line; the mount failed cleanly. |
| 4 | 1 | Change 1, dirty non-root mount | **Pass.** Read-write refused with one line; read-only allowed. |
| 5 | 1 | Change 5, unmount then remount | **Pass.** No hang. |
| 6 | 1 | A dirty root boots multi-user, unattended | **Not testable on this image.** See below. |
| 6b | 1, 2 | Change 1, root upgrade outside single-user | **Pass.** One warning line, no refusal, and root read-write. Round 2 shows the final wording: `ffs: / was unclean when mounted; mounting read-write anyway`. |
| 7 | 1, 2 | Change 1, root upgrade in single-user | **Pass.** Exactly one `ffs: root not cleanly unmounted, refusing read-write upgrade; run fsck` line; after `fsck -y`, the upgrade went through. Byte-identical in both rounds. |
| 9 | 2 | Change 1, dirty non-root upgrade, and the superblock reread | **Pass.** See below. |
| 8b | 1, 2 | `fsck -n` baseline | **Pass.** Identical in both rounds: only the graft's own artifacts. Those are the donor inode's `UNKNOWN FILE TYPE`, `DUP/BAD` and `BAD TYPE VALUE`; `LINK COUNT FILE I=1253202`; and the three Phase 5 complaints. |

So both gates of change 1 are demonstrated: the non-root mount refusal, and
the upgrade gate in all three of its branches. So is change 4. Changes 2, 5, 6
and 7 remain argued, for the reasons in "The gap worth naming"; Run 5 shows
only that change 5 does not break unmounting.

### What Run 7 does and does not show, and Run 9

The first round's Outcome claimed that Run 7 proved the gate's superblock
reread. It did not. `fsck -y` on the grafted root also repaired the graft's
inconsistencies and printed `FILE SYSTEM WAS MODIFIED`. So `fsck` reloaded the
root itself, and the second `mount -uw /` would have passed without the reread.
Run 7 shows that root refuses in single-user and that `fsck` recovers it.

Run 9 isolates the reread. A non-root image from `make_badfs` is dirty only in
its flag, and `fsck` never reloads a non-root filesystem at all. The sequence
was:
1. Mounted read-only, `mount -uw /mnt` was refused with one
   `ffs: /mnt not cleanly unmounted, refusing read-write upgrade; run fsck` line.
2. `fsck -y` printed `FILE SYSTEM MARKED CLEAN`, and no `WAS MODIFIED`.
3. A second `mount -uw /mnt` succeeded, leaving `/mnt` read-write.

Only the kernel's reread can have let it through.

### What Run 6 found

With the root marked unclean, the boot never reached the gate:
1. `rc.boot` runs `fsck -p`, which skips a cleanly unmounted disk but examines
   a dirty one.
2. It finds the graft's donor-inode inconsistency, the same one Run 8b reports,
   refuses to preen it, and exits 8.
3. `rc.boot` prints "Reboot failed - serious errors" and drops to a shell with
   root still read-only.

That all happens in userland, before any `mount -uw /`, and any kernel would do
the same on a grafted image. Run 6b used that shell to show the kernel's part.

So "a crashed machine comes up multi-user unattended" remains unverified end to
end. It needs an image with the kernel installed as a proper file rather than
grafted over a donor inode. `vm/ufs_alloc.py` can build one, and that is
recorded as follow-up work.

### Other observations

- **Tooling holes this series introduced, found in final review and fixed.**
  - The `RHAP_TEST_IMAGE` override protected `golden.img` only at the tool's
    own path. From a git worktree, where the real image lives in the main
    checkout, it would have accepted the master image. `check_target` now also
    refuses the protected images by name.
  - `guest-console.py` never consulted `check_target`, so `--persist` could
    have booted the master image read-write. It now refuses.
  - Both fixes have tests that use temporary files only.
- **An extra log line on non-UFS roots.** A boot from a non-UFS root now logs
  `ffs: superblock magic invalid, refusing` once, because UFS is tried first and
  the new pre-check reports its refusal. This is harmless.
- **The override needs reconciling at merge.** The harness depends on the
  `RHAP_TEST_IMAGE` override. master has since given `Guest` an `image=`
  parameter of its own (`4f3288045`), and the two need reconciling when this
  branch merges. When they are, the `--persist` guard must check that `image`
  argument rather than the module-level `IMAGE`. Otherwise
  `Guest(persist=True, image=...)` would get past it.
