# HAMMER Phase 2 (Read-Write) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mount a single-volume HAMMER v7 volume read-write on RhapsodiOS and
create, change and delete files, directories and links through HAMMER
transactions, the flusher and the UNDO FIFO, so that DragonFly BSD mounts the
result and finds nothing wrong.

**Architecture:** Phase 1 left the write side compiled out or stubbed:
`hammer_io.c` panics on writes, `hammer_rostubs.c` stands in for the flusher and
UNDO units, and the DragonFly VOPs sit under `#if 0 /* phase 2 */`. This plan
turns those on in dependency order. First the buffer layer learns to write, a
Mach kernel thread runs the flusher, and an empty read-write mount round-trips.
Then the namespace VOPs, then file data, then scale, ENOSPC and memory, then
`mount -u` and history. DragonFly's own `hammer show`/`checkmap` and file
checksums are the oracle for every volume we write.

**Tech Stack:** As Phase 1: Darwin 0.3 BSD VFS, Rhapsody `cc` (gcc 2.7.2.1),
pb_makefiles, rbuild/apk, Python/pytest harnesses, QEMU i386, a DragonFly BSD
6.4.2 QEMU guest, `qemu-img`.

**Spec:** [HAMMER design](../specs/2026-10-17-hammer-design.md) (Phase 2).
Phase 1's state, rulings and harness are in `src/kernel-7/bsd/hammer/PORTING.md`
and the Phase 1 plan; read both first.

## Global Constraints

- Everything in the Phase 1 plan's Global Constraints still holds, except that
  read-write mounts are now allowed under the rules below.
- **Writes go through HAMMER transactions, the flusher and the UNDO FIFO.
  There is no mode that skips UNDO.**
- Read-write admission refuses, with a console message and the volume left
  unchanged: everything read-only admission refuses; a volume that needs UNDO
  recovery (Phase 3 replays it); a volume holding any record outside PFS 0.
- Write ordering: data and UNDO reach the disk before the meta-data they
  cover, and the volume header is written last. Do not raise `MAXBSIZE`.
- Every on-disk store goes through `hmk*`/`hget*`; CRCs are computed over the
  little-endian bytes. A ppc and an i386 build must never disagree on disk.
- Must run its workloads on a **128 MB** guest without exhausting kernel
  memory.
- Never silently repair. History is retained as the format requires.
- Every volume a case writes is checked twice: our `hammer -f DEV show` and
  `hammer -f DEV checkmap` report nothing on the Rhapsody guest, and at each
  task's sign-off the same image passes `vm/dfly-check.sh` on DragonFly.
- Guests, images and commits follow CLAUDE.md and the Phase 1 rules (private
  overlays, own ports and `-name`, QMP-only shutdown, `kernel:`/`hammer:`/`vm:`
  prefixes). ppc builds; ppc runtime stays an open item in `PORTING.md`.

## Decisions this plan makes (record each in PORTING.md)

- **Device writes are synchronous.** `hammer_io_flush()` copies `io->data` into
  `getblk(devvp, blkno, 8192)` buffers and `bwrite()`s them in order. Each
  write completes before the next starts, so the flusher's stage order (data,
  UNDO, meta-data, volume header) is the on-disk order. Mark it
  `shortcut: synchronous 8 KB writes; move to async VOP_STRATEGY with
  completion ordering when throughput matters`.
- **One flusher thread per read-write mount**, a Mach kernel thread started by
  the rw mount (or `-u` upgrade) and stopped, after a final flush, by unmount
  or downgrade. Upstream's worker pool becomes that one thread running each
  flush group inline. LWKT tokens stay no-ops (Phase 1 audit: uniprocessor,
  no kernel preemption, and DragonFly drops tokens across sleeps anyway);
  `hammer_lock_*` stay real.
- **No REDO generation in Phase 2.** `hammer_fsync_mode` is fixed to a full
  flush; REDO replay arrives with recovery in Phase 3.
- **PFS-0 check is one lookup.** B-tree keys sort by localization first, so
  `hammer_btree_last()` over the whole key range finds any record outside PFS
  0: refuse if its `localization >> 16` is non-zero.
- **Memory limits scale with RAM:** `hammer_limit_dirtybufspace =
  min(mem_size / 16, 32 MB)` and `hammer_limit_inodes = max(mem_size / 65536,
  256)` (128 MB: 8 MB and 2048), set in `hammer_vfs_init`.
- `mknod` stays `EOPNOTSUPP` (device and FIFO nodes cannot be opened yet;
  Phase 1 shortcut); `whiteout`, NFS cookies and `telldir` stay as Phase 1
  documents them.

## Review Focus

1. **Unlink of an open file:** the data stays readable and writable through the
   open descriptor, the name is gone, and the space is freed only at last
   close; nothing leaks at unmount (Task 3).
2. **Rename:** over an existing file, over an empty directory, a directory into
   its own subtree (`EINVAL`), across directories (the moved directory's `..`
   follows), and onto itself (no-op) (Task 2).
3. **Writes around EOF:** writing past EOF leaves a hole that reads as zeros;
   truncating to the middle of a block and growing again reads zeros, not old
   bytes; a partial last block survives remount (Task 3).
4. **Byte order on the new write paths:** every new store is wrapped, including
   through varargs; `lelint.py` (moved into the tree) is clean and the host
   swap tests cover the UNDO and inode encoders (Task 1).
5. **ENOSPC mid-operation:** a create, mkdir, write or rename that fails for
   space leaves no half-made state (an entry without an inode, an inode
   without an entry, a short file that claims full length) (Task 5).

## File and interface map

| Files | Responsibility |
| --- | --- |
| `bsd/hammer/hammer_io.c` | Buffer layer: add `hammer_io_new`, modify/modify_done, flush and wait on the write side |
| `bsd/hammer/hammer_flusher.c`, `hammer_undo.c` | Now compiled: flusher thread, UNDO FIFO |
| `bsd/hammer/hammer_rhapsody.[ch]` | Kernel thread start/stop, `kernel_thread` wrapper, memory-limit setup |
| `bsd/hammer/hammer_vfsops.c` | rw admission, flusher lifecycle, `sync`, `mount -u` |
| `bsd/hammer/hammer_vnops.c` | Rhapsody VOPs for create/mkdir/remove/rmdir/link/symlink/rename/write/setattr/fsync, replacing the EROFS stubs |
| `bsd/hammer/hammer_object.c`, `hammer_inode.c` | Un-fence the Phase 2 write paths |
| `bsd/hammer/hammer_ioctl.c` | Subset: `HAMMERIOC_SYNCTID`, `HAMMERIOC_GETHISTORY` |
| `src/hammer-1/hammer/` | Add `synctid` and `history` (`cmd_synctid.c`, `cmd_history.c`) |
| `src/hammer-1/tests/{hammer_io.c,run-native.sh,lelint.py}` | Write-side checks; `lelint.py` moves here from `vm/work` |
| `vm/hammer_guest.py`, `vm/test_hammer_guest.py` | Writable cases, image export, DragonFly check hook |

## Harness changes used by every task

- `run()` grows a `writes=True` mode for read-write cases. It skips the
  unchanged-image check, ships the `hammer` tool too, and expects the case
  script to end with `hammer -f /dev/rhd1a show` and `checkmap`, each of which
  must print no error lines (run-native.sh fails the case otherwise).
- `export_volume(outdir) -> Path` converts the case's data overlay to a raw
  volume (`qemu-img convert`, then `unwrap_volume_file`) for DragonFly.
- `dfly_check(raw, outdir) -> list[str]` runs `vm/dfly-check.sh` on DragonFly
  against a copy and returns its findings (empty means clean). Task 1 extends
  `dfly-check.sh` to also run `hammer recover` into a scratch directory: it
  must recover exactly the files the case wrote, with matching checksums, and
  report no damaged records.
- Base volume for writes: a fresh 2 GB volume from our `newfs_hammer`, wrapped
  as `vm/work/hammer-vols/blank.wrapped`; each case writes to its own overlay.

---

### Task 1: Buffer-layer writes, flusher thread, UNDO and an empty rw mount

**Files:** `hammer_io.c`, `hammer_flusher.c`, `hammer_undo.c`, `hammer_rostubs.c`
(shrinks), `hammer_rhapsody.[ch]`, `hammer_vfsops.c`, `conf/files`, `PORTING.md`,
`tests/{run-native.sh,lelint.py}`, `vm/hammer_guest.py`, `vm/test_hammer_guest.py`

**Interfaces:**
- Produces: `int hammer_io_write_sync(struct vnode *devvp, int64_t offset,
  const void *src, int bytes)` (8 KB `getblk`/`bwrite` chunks, the mirror of
  `hammer_dev_read`); `int hammer_flusher_start(hammer_mount_t)`,
  `void hammer_flusher_stop(hammer_mount_t)`; `int hammer_admit_rw(hammer_mount_t,
  const char **why)` (recovery-needed, PFS-0, and Phase 1 rules).
- Consumes: Phase 1's `hammer_dev_read`, `hammer_admit_volume`, buffer cache.

- [ ] **Step 1: Write cases.**
  - `rw-empty`: mount the blank volume read-write, `sync`, unmount; `show` and
    `checkmap` clean on the guest; `vol0_next_tid` in the exported header is
    larger than before (host asserts); `dfly_check` clean.
  - `refuse-rw-recovery` and `refuse-rw-pfs` (fixture: one leaf element's
    `localization` set to `0x00010002`, node CRC resealed): rw mount fails
    with `EOPNOTSUPP` and the image is unchanged; the ro mount of
    `refuse-rw-pfs` still works.
  - Host: `lelint.py` runs in `make check` over every compiled `.c` and
    reports nothing; swap tests cover `hammer_undo_ondisk` field encoding.
- [ ] **Step 2: Run them.** Expected: `rw-empty` fails (`read-only in this release`).
- [ ] **Step 3: Implement** the write side of `hammer_io.c`, compile
  `hammer_flusher.c` and `hammer_undo.c` with the thread model above, rw
  admission, the flusher lifecycle in mount/unmount, `hammer_vfs_sync`, and
  the memory limits.
- [ ] **Step 4: Run all Phase 1 cases plus these, and build ppc.** Expected: all
  pass; Phase 1 read-only cases unchanged.
- [ ] **Step 5: Commit** `kernel: write hammer volumes through the flusher and UNDO`.

### Task 2: Namespace operations

**Files:** `hammer_vnops.c`, `hammer_object.c`, `hammer_inode.c` (un-fence create,
add/del direntry, update, sync), `tests/{hammer_io.c,run-native.sh}`

**Interfaces:**
- Produces Rhapsody VOPs `hammer_vop_create`, `_mkdir`, `_remove`, `_rmdir`,
  `_link`, `_symlink`, `_rename` (4.4BSD `componentname` protocol: they `vput`
  what they are passed, as `ufs_*` do), replacing the EROFS stubs.
  `hammer_vop_lookup` returns `EJUSTRETURN` for CREATE/RENAME on a missing last
  component of a writable mount and honours `SAVENAME`/`SAVESTART`.
- Consumes: Task 1's transactions and flusher.

- [ ] **Step 1: Write cases.** `ns-ops` runs a fixed script on the blank volume:
  `mkdir -p a/b/c`, 50 files, 24- and 200-byte symlinks, a 3-name hard link,
  `rmdir`, `rm`, and the rename matrix from Review Focus 2 (each checked with
  its exact errno: `EINVAL`, `ENOTEMPTY`, `EEXIST`/success as POSIX says).
  The host compares `hammer_walk -n` of the result, after remount, with the
  manifest the same script produces on DragonFly (`vm/dfly-ns-ops.sh`, run once
  and stored as `ns-ops.walk`). `show`/`checkmap` and `dfly_check` clean.
- [ ] **Step 2: Run them.** Expected: fail with `EROFS` from the stubs.
- [ ] **Step 3: Implement** the VOPs over the un-fenced HAMMER object code.
- [ ] **Step 4: Run all cases and build ppc.** Expected: walks identical, checks clean.
- [ ] **Step 5: Commit** `kernel: create, rename and remove hammer names`.

### Task 3: File data, attributes and open-unlinked files

**Files:** `hammer_vnops.c` (write, strategy write, setattr, fsync, pageout,
inactive and reclaim for unlinked inodes), `hammer_inode.c`, `tests/...`

**Interfaces:**
- Produces `hammer_vop_write` (8 KB logical blocks, `vnode_pager_setsize` on
  extend), the write branch of `hammer_vop_strategy` (bulk records as
  upstream's strategy_write), `hammer_vop_setattr` (size, mode, uid/gid,
  times, flags), `hammer_vop_fsync` (full flush), `pageout` via `ufs_pageout`.
  `hammer_inode_unloadable_check` gets its upstream body back for rw mounts.

- [ ] **Step 1: Write cases.** `data-ops`: sizes 0, 1, 16383, 16385, 1048577 and
  64 MiB written with known patterns; append; overwrite in the middle; the EOF
  matrix from Review Focus 3; `chmod`/`chown`/`utimes` (times survive remount);
  `mmap(MAP_SHARED)` write then `msync`; `fsync` then QMP `quit` without
  unmount and remount ro shows the data (UNDO not needed: the flush completed).
  `unlinked`: open, unlink, write, read back through the descriptor, close,
  then `df` space returns; no `hammer: leaked`. Full walks with CRCs after
  remount equal the host-computed expected manifest; checks clean.
- [ ] **Step 2: Run them.** Expected: write fails `EROFS`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run all cases and build ppc.**
- [ ] **Step 5: Commit** `kernel: write hammer file data and attributes`.

### Task 4: Scale: B-tree splits, deletions and rebalancing

**Files:** tests only, unless a case finds a bug (`hammer_btree.c` is already
compiled whole).

- [ ] **Step 1: Write cases.** `big-dir`: create 20,000 entries, list them,
  delete every other one, then all; `big-file`: write and delete a 512 MiB
  file in 64 KB chunks; `churn`: 1,000 rounds of create/write/rename/unlink in
  50 directories. After each, remount; `show`/`checkmap` clean on the guest and
  `dfly_check` clean; DragonFly's walk of `big-dir` midway equals ours.
- [ ] **Step 2: Run them; fix what they find (each fix with its own failing
  case first).**
- [ ] **Step 3: Commit** `kernel: exercise hammer b-tree splits and deletes`.

### Task 5: ENOSPC and a 128 MB guest

**Files:** `hammer_vnops.c`/`hammer_object.c` as the cases require, `hammer_rhapsody.c`
(limits), tests.

- [ ] **Step 1: Write cases.** `enospc`: on a 768 MB volume, fill with 1 MiB
  files until `ENOSPC`, then try each of create, mkdir, write, rename and link
  at the edge; every failure is `ENOSPC` and leaves no half-made state (Review
  Focus 5); earlier files read back intact; `rm` everything and space is
  reusable; checks clean. `small-ram`: `data-ops` and `big-dir` on a guest
  booted with `-m 128`, no panic, no kernel memory exhaustion message.
- [ ] **Step 2: Run them; fix.**
- [ ] **Step 3: Commit** `kernel: keep hammer consistent at ENOSPC and in 128 MB`.

### Task 6: `mount -u` between read-only and read-write

**Files:** `hammer_vfsops.c`, `src/hammer-1/mount_hammer/mount_hammer.c` (accept
`update`), tests.

- [ ] **Step 1: Write cases.** `remount`: ro mount, `-u -o rw` (flusher starts,
  rw admission runs), write, `-u -o ro` (final flush, flusher stops, further
  writes `EROFS`), unmount; checks clean. Downgrade with a file open for
  writing fails with `EBUSY` unless `force`.
- [ ] **Step 2–4:** run (fail), implement, run all, build ppc.
- [ ] **Step 5: Commit** `kernel: switch hammer mounts between ro and rw`.

### Task 7: History and `hammer synctid`/`history`

**Files:** `hammer_ioctl.c` (compile the `SYNCTID` and `GETHISTORY` subset),
`hammer_vnops.c` (`VOP_IOCTL`), `src/hammer-1/hammer/{cmd_synctid.c,cmd_history.c}`, tests.

- [ ] **Step 1: Write cases.** `history`: write a file three times with
  `hammer synctid` between; `hammer history FILE` lists three versions with
  increasing TIDs; DragonFly's `hammer history` on the exported image lists
  the same TIDs.
- [ ] **Step 2–4:** run (fail), implement, run all, build ppc.
- [ ] **Step 5: Commit** `hammer: list hammer file history`.

### Task 8: Phase 2 acceptance record

- [ ] Rerun every Phase 1 and Phase 2 case on the final kernel; ext2, HFS and
  UFS regressions as in Phase 1 Task 8; `cycle` with a write per cycle.
- [ ] `PORTING.md`: the evidence table, the decisions above with what was
  measured (flush times, memory use on 128 MB), the stubs left for Phase 3
  (recovery, REDO, pruner, reblocker), ppc runtime open.
- [ ] Commit `hammer: record phase 2 acceptance`.
