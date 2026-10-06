# FFS Stall, Hard Lock and Corruption — Design

Date: 2026-10-05
Status: draft for review

## Problem

Heavy small-file I/O on UFS makes RhapsodiOS unusable. The reference workload is the
build-root extraction of `rbuild kernel`: dozens of apks unpacked with `gzip -dc | pax -r`.
While it runs:

1. **Stall.** File activity continues, but the rest of the system stops responding. sshd stops
   accepting connections.
2. **Hard lock.** Sometimes the machine never recovers.
3. **Corruption.** On the ppc box, after a hard lock the UFS partition is destroyed: the
   superblock or root directory is unusable, and only a reformat and reinstall recovers it.
   That partition has only ever been mounted by ppc (native byte order).

It reproduces on the i386 QEMU build guest (128 MB), on a real ThinkPad, and on ppc. So the
cause is in shared code, not in one disk driver or in QEMU.

## Goal and non-goals

**Goal.** During the extraction the system stays responsive, a crash in the middle leaves a
filesystem `fsck` can repair, and throughput is no worse than today.

**Non-goals.**
- Replacing our FFS wholesale with FreeBSD 4.x's or NetBSD 2.0's. Both sit on VM/buffer
  layers (FreeBSD's VMIO buffer cache, NetBSD's UBC) that our Mach 2.5 `OLD_VM_CODE` kernel
  does not have. And the lead suspect is below FFS, so a new FFS on the same `vfs_bio.c`
  would inherit it.
- Soft updates and dirhash. Phase 3 decides whether either gets its own spec.
- Testing on ppc. That is deferred: this spec verifies on i386 only, although the fixes are
  in shared code.

**Existing requirement, kept.** Opposite-endian UFS volumes keep working.
`ufs/ufs/ufs_byte_order.c` and the `REV_ENDIAN_FS` paths already provide this. The work
must not regress it, which is checked as described under Cross-cutting rules.

## Findings that shape the design

These come from reading `src/kernel-7` on 2026-10-05.

1. **The same disk block can end up in two buffers.** In `getblk`'s miss path
   (`bsd/vfs/vfs_bio.c:601`), `getnewbuf` can sleep before it returns a buffer: its
   delayed-write path calls `bawrite`, then `VOP_STRATEGY`, then `VOP_BMAP`, which can
   `bread`. After `getnewbuf` returns, `binshash` places the buffer in a hash bucket while
   `b_vp` and `b_lblkno` are still stale, and then `allocbuf` can sleep in its own
   `getnewbuf` loop. Nothing re-checks the hash afterwards. Another process's `getblk` for the
   same (vnode, block) misses in `incore()` and creates a second buffer. Whichever copy is
   written last wins. That explains a lost root directory or a garbage superblock, and it gets
   likelier as the cache shrinks and the disk queue grows. NetBSD and FreeBSD 4.x re-check
   the hash after `getnewbuf` and release their buffer if they lost the race.
2. **`allocbuf` spins while holding a busy buffer.** It calls
   `while ((nbp = getnewbuf(0, 0)) == NULL) ;` (`vfs_bio.c:686`). Several processes doing
   this can each wait on buffers the others hold. This is a candidate for the hard lock.
3. **`getnewbuf` flushes without limit.** When the head of the free list is a delayed write,
   it calls `bawrite` on it and starts again (`vfs_bio.c:803`). With a cache full of dirty
   metadata, one request for a buffer queues writes for the whole cache. Every other process
   that needs a buffer, including sshd and exec page-ins, waits behind them.
4. **The i386 buffer pool is small.** `bufpages = mem_size / 50`, which is 2% of RAM, about
   2.5 MB on a 128 MB guest (`machdep/i386/unix_startup.c:128`). ppc uses 3–5% or more.
   The `nbuf` boot argument (`machdep/i386/i386_init.c:66`) adds buffer headers, not pool
   memory.
5. **Metadata writes are synchronous.**
   - `ufs_makeinode` calls `VOP_UPDATE(…, 1)` (`ufs_vnops.c:2187`).
   - `ufs_direnter2` calls `VOP_BWRITE` (`ufs_lookup.c:864–973`).
   - `ufs_setattr` utimes calls `VOP_UPDATE(…, 1)` (`ufs_vnops.c:492`).

   So each extracted file costs at least two or three synchronous writes. That is 4.4BSD's
   price for crash consistency without soft updates.

## Approach

Diagnose and fix in place, then backport selectively. There are four phases. Each ends at a
measurement that decides whether the next phase is needed.

### Phase 0 — Benchmark and crash harness

**Files.**
- `vm/ffsbench.py`: host driver.
- `vm/test_ffsbench.py`: unit tests for run classification and CSV parsing.
- `tests/ffsbench/slow.c`: Jon Burgess's reiserfs benchmark (archived at
  `web.archive.org/web/20060702154633/http://www.jburgess.uklinux.net/slow.c`), patched to
  use `fsync` instead of `fdatasync`, with the size taken from the command line.
- `tests/ffsbench/wakeprobe.c`: a loop of `usleep(100 ms)` that prints the worst wakeup
  lateness once per second.
- Run output goes to `vm/work/ffsbench/<run-id>/`, which is gitignored.

**Guest.** A private QEMU guest from `vm/work/rhap-i386-bootstrapped.img`:
- `-snapshot`, `-m 128`, and its own ssh and QMP ports, chosen after checking `netstat`;
- multi-user, so `update` runs;
- one SSH session at a time, with no polling loops against the guest.

**Disks.** Nothing is measured on root. The base image's root filesystem is already corrupt
(DUP blocks).
- **hd0** is the root disk, under `-snapshot`.
- **hd1** is the test disk, attached with `snapshot=off`. Before every run the host copies in a
  pristine empty UFS image built once by `ufs_build.py` from the golden template geometry.
- **hd2** is a read-only UFS image built by `ufs_build.py`. It holds the workload apks and
  `replay.list`, and the guest mounts it with `-r`.

**Workload capture.** Run one real `rbuild kernel --arch i386` on the private guest. From
rbuild's state log, record the ordered list of apks unpacked into the build root, copy those
apks to the host, and record their SHA-256 hashes.

**Throughput run.** Everything runs in one ssh session per run:
1. Mount hd1 on `/mnt`.
2. For each apk in `replay.list`, run `gzip -dc <apk> | pax -r -pe` into `/mnt/root`, the same
   pipeline as `src/rbuild-1/apk.c`. Time the whole replay.
3. Time `rm -rf /mnt/root`.
4. Run `slow.c /mnt/s 64`, which writes 1 file and then 2 files in parallel.
5. Keep `wakeprobe` running throughout.
6. Meanwhile the host times a fresh ssh connect every 5 s. This loop targets only this
   private guest, and only during a run.

Each run produces one CSV row with these columns:
- replay seconds and rm seconds;
- MB/s for each `slow.c` phase;
- maximum and p99 wakeup lateness;
- maximum ssh connect time.

Each configuration gets 3 runs, and the median is reported.

**Crash run.**
1. Start the replay, then send QMP `quit` at a random time between 5 s and the baseline replay
   time. Log the seed.
2. Boot again with hd1 unmounted and run `fsck -n /dev/rhd1a`.
3. Run `vm/ufs_check.py` on the hd1 image.
4. Classify the run as one of:
   - **clean**;
   - **preen-fixable**: `fsck -p` would succeed;
   - **manual**: needs interactive `fsck` answers;
   - **destroyed**: superblock or root directory unusable.
5. Keep the hd1 image from every run that is not clean.

N = 20 crash runs per configuration.

**Hard-lock capture.** If `wakeprobe` output stops for 60 s:
1. Take a QMP `savevm`.
2. Attach the gdbstub and dump the registers, `_active_threads[0]` and its kernel stack.
3. Detach with `D`.

**Output.** A baseline table for the stock kernel, and the stall, lock and corruption rates the
harness reproduces.

### Phase 1 — Corruption and hard lock

1. **Reference comparison.** Shallow-clone FreeBSD `RELENG_4` and NetBSD `netbsd-2` into
   `F:\ref\`, outside the repo and read-only. Compare function by function:
   - `vfs_bio.c` and `vfs_cluster.c`;
   - the ufs/ffs write paths (`ufs_vnops.c`, `ufs_lookup.c`, `ffs_alloc.c`, `ffs_balloc.c`,
     `ffs_inode.c`, `ffs_vfsops.c`).

   Write the result to `docs/kernel/ffs-bsd-comparison.md`, classifying each divergence as
   *bug fix*, *performance* or *irrelevant*.
2. **Debug kernel.** Add a kernel config option `FFSDEBUG` that only adds assertions. A build
   without it is byte-identical to today's. The assertions:
   - **Duplicate identity:** at `getblk` exit and in `bgetvp`, panic if two hashed, valid
     buffers share (vnode, block).
   - **Superblock writes:** on a write to the device vnode at `SBLOCK`, panic if the data
     lacks `FS_MAGIC` in either byte order.
   - **`biodone`:** panic if `b_vp` is null, or if a buffer is `B_INVAL` while `B_DELWRI` is
     still set.
   - **Clusters:** panic unless each component buffer's `b_blkno` is contiguous with the
     cluster's.
3. **Confirm.** Run the harness on the debug kernel. A duplicate-identity panic confirms
   finding 1 and gives the stack. A hard lock gives a gdbstub dump.
4. **Fix.** Each fix is one commit and is re-verified with the harness:
   - **`getblk`:** after `getnewbuf` returns, re-check the hash; if someone else created the
     block, release the new buffer and retry. Set the buffer's identity before anything can
     sleep. Follow FreeBSD 4.x / NetBSD.
   - **`allocbuf`:** replace the spin with a proper wait that cannot deadlock against other
     holders of busy buffers.
   - Fix anything else the comparison classifies as *bug fix*, or that the assertions catch.

**Exit criteria.**
- 20 of 20 crash runs are *preen-fixable* or better, with 0 *destroyed*.
- No hard lock in 10 back-to-back replays.
- No assertion fires.

### Phase 2 — Stall and throughput

The goal is to slow down the process doing the writing, not everyone else.

1. **Write throttling, a minimal port of FreeBSD 4.x.**
   - Count dirty buffers. Above a high watermark, `bdwrite` makes the calling process flush
     and wait, as in FreeBSD's `bd_wait`.
   - Cap the bytes of writes in flight, as with `runningbufspace` and `waitrunningbufspace`,
     so the disk queue stays short.
2. **`getnewbuf`.**
   - Take a clean buffer whenever one exists.
   - Otherwise start a bounded batch of delayed writes and sleep, instead of looping without
     limit.
3. **Pool sizing.**
   - Add a `bufpages` boot argument next to `nbuf` in `machdep/i386/i386_init.c`.
   - Measure with the pool at 2%, 5% and 10% of RAM.
   - Change the default in `machdep/i386/unix_startup.c` only if the data supports it.
4. **Synchronous metadata.**
   - `ufs_makeinode` and `ufs_direnter` stay synchronous, because that ordering is what keeps a
     crash repairable.
   - The utimes update in `ufs_setattr` adopts FreeBSD 4.x's behaviour, but only if the
     comparison shows it is asynchronous there.
5. **Syncer.** If the harness shows periodic stalls of about 30 s, measure `update`'s
   flush-everything sync, and spread it out FreeBSD-style only if the data shows it matters.
6. **Upper bound.** Measure once with `mount -o async`, only to bound the remaining cost of
   synchronous metadata. It is not a fix.

**Exit criteria,** during the replay:
- maximum `wakeprobe` lateness under 1 s;
- every ssh connect under 2 s;
- replay time and `slow.c` MB/s no worse than the Phase 0 baseline;
- crash runs still have 0 *destroyed*.

### Phase 3 — Backport decision (no code)

Write a recommendation in `docs/kernel/ffs-bsd-comparison.md`:
- **Soft updates.** If the replay under `-o async` is still more than 2× faster than the
  Phase 2 kernel, synchronous metadata dominates. Soft updates (FreeBSD 4.x
  `ffs_softdep.c` plus the `bioops` hooks in `vfs_bio.c`) then gets its own spec.
- **Dirhash.** It gets its own spec only if directory lookups show up as a cost.

## Cross-cutting rules

- **Workspace.** Work in a git worktree on branch `ffs-perf`. Use a private guest only, never
  the shared 2222 box.
- **Building.** Build the kernel with `rbuild kernel` on the private guest. Boot-test on a
  private image through `RHAP_TEST_IMAGE`.
- **Commits.** One fix per commit, `kernel: ` prefix, one or two lines describing behaviour.
- **Code style.** Match the surrounding K&R code. No changes beyond what a task needs.
- **Byte-order regression check,** after Phase 1 and after Phase 2:
  1. Attach a copy of the big-endian MOSXS 1.2v3 ppc image as an extra disk on the i386
     guest.
  2. Mount it read-only and walk the whole tree.
  3. Remount the copy read-write, create and delete a small tree, then run `fsck -n`. It must
     be clean.
- **Host tests.** `vm/test_ffsbench.py` and the existing `vm/test_ufs_*` suites must pass.
  The 38 golden `test_ufs_alloc` tests that need APFS `cp -c` are a known exception on this
  host.

## Risks

- **The race may not reproduce in QEMU.** QEMU's IDE timing differs from real disks. If 20
  crash runs show no damage on the stock kernel, add I/O latency with blkdebug delays on hd1,
  or shrink the pool with the new `bufpages` argument to provoke it.
- **The assertions can change timing** enough to hide the race. Keep the duplicate-identity
  check cheap: one hash-chain walk at the existing `incore` points.
- **Write throttling moves latency onto the writer.** That is intended, but replay time is an
  exit criterion so the cost stays visible.
