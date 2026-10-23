# HAMMER port state

Source: DragonFly BSD `4e10f78d03f3d76c5bbe99c5d65022a03ea21e2e`, see `ORIGIN`.
Design: `docs/superpowers/specs/2026-10-17-hammer-design.md`.
Plan: `docs/superpowers/plans/2026-10-17-hammer-phase1.md`.

This is a single-volume, single-namespace (root PFS only), version-7 HAMMER.
Phase 1 is read-only; Phase 2 (`docs/superpowers/plans/2026-10-23-hammer-phase2.md`)
adds read-write mounts.

## Removed upstream units

- `hammer_pfs.c` (pseudo-filesystems) and `hammer_volume.c` (volume add and
  remove) are deleted. Callers are cut as the files that call them are adapted.
- `hammer_mirror.c` stays until Phase 4, where it is reduced to the
  `HAMMERIOC_MIRROR_READ` scan used by `hammer dedup`.

## Byte order

HAMMER is little-endian on disk on every CPU. Upstream had no byte-order
handling, because it assumed x86.

- `hammer_port.h` defines `hle16_t`, `hle32_t` and `hle64_t`: one-member
  structs holding the little-endian bytes. Read a field with `hget16/32/64()`
  and build one with `hmk16/32/64()`. These are the identity on little-endian
  hosts and swap on big-endian ones.
- Every multi-byte field of every on-disk structure in `hammer_disk.h` and
  `hammer_btree.h` uses those types. This includes `hammer_off_t`,
  `hammer_tid_t` and CRC fields, and the integer members of the on-disk
  `hammer_uuid_t`. Byte arrays stay arrays. Any direct use of a field (an
  arithmetic operation, a compare, an assignment from a host integer) is a
  compile error on every CPU, so a missed conversion cannot hide on i386.
- In-memory copies of on-disk structures (cached leaf elements, inode data)
  stay in disk format and are read through the accessors.
- CRCs are computed over the raw on-disk bytes. They are compared and stored
  with `hget32`/`hmk32`. Mirror-record CRCs (`hammer_ioc_mrecord_head`) are
  ioctl data in host order and are not converted.
- `-DHAMMER_TEST_SWAP` forces the swapping path on a little-endian host
  (`tests/Makefile`). This proves the swap code paths, but it is not ppc
  runtime evidence.

## Compiler

The target `cc` is gcc 2.7.2.1. `hammer_port.h` supplies `uint8_t` to
`uint64_t`, `uintptr_t`, `bool`, `offsetof`, `rounddown` and `__packed`.
C99 constructs (mixed declarations, loop-scoped declarations, `__func__`)
are rewritten in place as each file is adapted.

## CRC sources

`crc32.c` and `icrc32.c` come from DragonFly `sys/libkern` (Rhapsody's
libkern has neither). They include `hammer_port.h` and always declare their
prototypes, since the Rhapsody kernel defines `KERNEL`, not `_KERNEL`.
`icrc32.c`'s slicing-by-8 path already handles big-endian hosts.

### Varargs escape the type check

A wrapper struct passed to `printf()`/`panic()` or any other varargs function
compiles silently. In that position the type check catches nothing.
`src/hammer-1/tests/lelint.py` reports every on-disk field passed to a
varargs function outside `hget*()`; host-struct fields with the same names
(`ip->obj_id`, `io->offset`, ...) are listed in the script.  The host test
`vm/test_hammer_guest.py` runs it over every compiled kernel source and
expects nothing.  The first such bug it found was `hammer show` printing
`mode=27777600755`.

## Imported support headers

`hammer_tree.h` is DragonFly `sys/sys/tree.h` at the pinned commit. Its
`RB_SCAN` spinlock is a placeholder (`int rbh_spin`) and
`RB_SCAN_LOCK`/`RB_SCAN_UNLOCK` do nothing, because Rhapsody's BSD side is
uniprocessor (see the token audit in Task 5). gcc 2.7's cpp rejects an empty
macro argument, so the storage-class argument is passed as the empty macro
`RB_STORQUAL_NONE`.

`hammer_port.h` also supplies the `<sys/queue.h>` accessors that 4.4BSD-Lite
lacks (`TAILQ_FIRST`, `TAILQ_NEXT`, `TAILQ_EMPTY`, `TAILQ_FOREACH` and
`TAILQ_HEAD_INITIALIZER`), plus `__unused`, `__dead2` and `__always_inline`.

## Admission

`hammer_admit_volume()` (`hammer_admit.c`) is the single admission rule set,
shared by the kernel mount and the tools. It refuses:

- A short header, an unknown device size, a wrong or byte-swapped signature,
  a CRC mismatch, bad geometry or a volume larger than its device: `EINVAL`.
- A version other than 7, `vol_count != 1`, `vol_no != 0`, or an UNDO FIFO
  that needs recovery: `EOPNOTSUPP`. The recovery case returns the
  `hammer_admit_needs_recovery` string, so offline tools can warn and continue.

Upstream `newfs_hammer` never sets `vol_crc`. The kernel sets it on its first
flush and never checks it. Admission therefore treats `vol_crc == 0` as "not
yet set" and verifies any non-zero CRC. Our `newfs_hammer` sets it on every
volume flush.

## Tools (src/hammer-1)

- `common/` holds the shared upstream tool sources. It also holds mirrors of
  `crc32.c`, `icrc32.c` and `hammer_admit.c`. `tests/Makefile mirrors` runs
  `cmp` on each against this directory.
- The headers come from `kernel-hdrs` (`install_hammer_hdrs` in
  `conf/Makefile.template`).
- `common/compat.[ch]` cover Rhapsody libc gaps: `pread`/`pwrite`,
  `strtoull`/`strtoll` (`strtouq`/`strtoq`), `intmax_t`, `ULLONG_MAX`,
  `hexdump(3)` and `hammer_device_size()` (`fstat`, or `DKIOCNUMBLKS` x
  `DKIOCBLKSIZE`; the stock disk drivers lack `DKIOCGPARTINFO`).
- Rhapsody's printf supports `%q`. `%ll` prints only the low 32 bits and
  `%j` is unknown, so every 64-bit conversion uses `%q`.
- gcc 2.7's cpp has no variadic macros, so `hwarn`/`hwarnx` are functions.
- `newfs_hammer` creates a single version-7 volume only. `-E` (TRIM) is
  refused, and the version comes from `-V` or the default, not
  `sysctlbyname`.
- `mount_hammer` is rewritten in the shape of `mount_ext2fs`: one special
  file, `struct hammer_args`, and the generic ro/rw/exec/suid/dev options.
  The PFS, history, master-id and as-of options are gone.
- `hammer` dispatches `show`, `show-undo`, `blockmap`, `checkmap` and the
  `namekey*` helpers. The other commands stay in `hammer.c` under `#if 0`,
  and their sources are left out of the Makefile.
- Rhapsody has no `/dev/zero`, and `dd` will not extend a file with `seek`.
  Test images are made with perl `truncate`, at 2047 MiB to stay below 2^31.

## Kernel glue (Phase 1)

- The kernel option is `HAMMERFS` (`options HAMMERFS`, `<hammerfs.h>`), and
  the filesystem registers as type 19, name `hammer`, in `vfs_conf.c`.
- `hammer_rhapsody.[ch]` hold the DragonFly kernel API that HAMMER calls:
  kmalloc on `_MALLOC(M_HAMMER)`, a private `hammer_vsnprintf` (the kernel
  has no snprintf and its printf has no 64-bit conversions), `tsleep`, and
  `hammer_dev_read`, which reads the device through the buffer cache.
- `hammer_io.c` is rewritten.  `struct hammer_io` holds a kmalloc'd copy of
  the 16/64 KB buffer (`io->data`) rather than a `struct buf`, because
  Rhapsody's MAXBSIZE is 8 KB.  Reads copy through 8 KB `bread`; see "Write
  path" for writes.
- The device size comes from `DKIOCNUMBLKS` and `DKIOCBLKSIZE`, as HFS
  does. The IDE driver returns EINVAL for `DKIOCGPARTINFO`.
- Rhapsody has no `VDATABASE` or `DT_DBF`, so `HAMMER_OBJTYPE_DBFILE`
  objects appear as regular files.
- `hammer_to_unix_xid` and `hammer_guid_to_uuid` assemble the uid/gid from
  uuid bytes `node[2..5]` little-endian; upstream read them as a native
  `uint32_t`, which is wrong on ppc.

### Token and atomics audit

LWKT tokens, critical sections and the `atomic_*` operations are plain
memory operations here. The kernel is uniprocessor (`NCPUS 1`) and does not
preempt kernel code: on i386 `catch_interrupt` checks for an AST only when
the interrupted context is user or VM86 mode (`machdep/i386/catch.c`), and
on ppc the interrupt return skips the AST check when returning to the
kernel (`machdep/ppc/hw_exception.s`). Kernel code therefore switches only
where it sleeps, which is where HAMMER already expects a token to be
released.

## Upstream defects found (to examine in Phase 2)

- None so far.  (Task 4 logged "`utimes()` does not persist"; that was a
  misreading.  The times are on disk: a DragonFly read-only mount flags every
  inode `HAMMER_INODE_RO` and `getattr` then reports ctime as atime and
  mtime.  See "Read-only mounts and times" below.)

## Read-only mounts and times

Upstream reports ctime as atime and mtime for `HAMMER_INODE_RO` inodes, so
that snapshots give stable `tar | md5` results, and it sets that flag on every
inode of a read-only mount.  Every Phase 1 mount is read-only, so this port
reports the stored atime and mtime instead: `ls -l`, `make` and backup tools
would otherwise see ctime everywhere.  The ctime rule returns for as-of
(snapshot) access in Phase 4.  The DragonFly reference manifests are
therefore taken from a read-write `noatime` mount (`vm/dfly-walk.sh`).

## File data (Phase 1)

`read` goes through the buffer cache in 8 KB logical blocks; `strategy`
fills each block from the data records covering it (upstream's buffered
"hard way"; the direct and double-buffered paths are not used), zeroing
holes and the tail.  `bmap` is the identity mapping.  `mmap` pages in
through `ufs_pagein`, which is `VOP_READ`.  A data CRC failure is EIO.
`fsync` is `nop_fsync`: vnode reclaim calls it before dropping cached
blocks, and an error there would leave them on a recycled vnode.

## Damaged and crafted volumes

Upstream asserts or panics on several impossible on-disk values.  On a
read-only data volume, which may be any disk someone hands you, each of
these is an EIO with a console line instead:

- A B-Tree node whose type is not leaf or internal, or whose element count
  exceeds 63 (leaf) or 62 (internal): treated like a node CRC failure
  (`hammer_load_node`).
- A child node offset outside the B-Tree zone or not node-aligned
  (`hammer_get_node`).
- A record whose data length is outside 0..64 KB, whose data offset is 0
  with a length, outside the meta and data zones, or whose extent runs past
  the buffer it lands in (`hammer_btree_extract`).
- A buffer offset in zone 1, 3 (UNDO), 4 or 15, or past the end of the
  volume (`hammer_get_buffer`).
- An inode record that is not exactly one `struct hammer_inode_data`
  (`hammer_get_inode`).
- A directory naming an unknown name-hash algorithm
  (`hammer_direntry_namekey` returns -1).
- A directory whose parent is itself or 0 (lookup of `..`; `namei` never asks
  for `..` of the mount root).
- A directory entry whose name is longer than `NAME_MAX` or shorter than one
  byte, and a symlink record shorter than its header.

A read at a negative file offset fails with EINVAL, as in `ffs_read`.

## Directory offsets and telldir

A directory's seek offset is the 64-bit HAMMER namekey of the next entry
(0 and 1 are `.` and `..`).  Sequential `getdirentries` and `lseek` with a
64-bit `off_t` work, but Rhapsody's `getdirentries` returns `*basep` as a
`long` and Libc keeps `dd_seek` as a `long`, so `telldir`/`seekdir` lose the
upper 32 bits, where the hash lives.  A `seekdir` on a HAMMER directory
therefore restarts or repeats the listing.  Fixing it needs a 32-bit
directory cookie scheme; it is not done in Phase 1.

## Kernel memory

Allocations of a page or more (the 16 and 64 KB buffers) come from
`kmem_alloc` with their own VM object, behind an 8-byte size header
(`hammer_kmalloc`).  Through `_MALLOC`, Rhapsody serves them with
`kmem_alloc_wired`/`kmem_free` on `kernel_object`, and under HAMMER's
buffer churn that panics with `pmap_remove_all 3`: the freed page is still
wired.  A gdbstub backtrace put the panic in `kfree` from
`hammer_io_release`; guard words showed no overrun or double free.  The
kernel fault itself is not fixed and may hit other heavy large-`_MALLOC`
users.

## Provenance check (Phase 1)

`sha256sum -c ORIGIN` in this directory fails only for files this port
changed or removed:

- Modified: `crc32.c`, `icrc32.c`, `hammer.h`, `hammer_btree.h`,
  `hammer_crc.h`, `hammer_disk.h`, `hammer_mount.h`, `hammer_blockmap.c`,
  `hammer_btree.c`, `hammer_cursor.c`, `hammer_inode.c`, `hammer_io.c`,
  `hammer_object.c`, `hammer_ondisk.c`, `hammer_subs.c`, `hammer_vfsops.c`,
  `hammer_vnops.c`.
- Removed (single volume, no PFS): `hammer_pfs.c`, `hammer_volume.c`.

In `src/hammer-1` it fails for `hammer/Makefile`, `hammer/cmd_blockmap.c`,
`hammer/cmd_mirror.c`, `hammer/cmd_show.c`, `hammer/hammer.c`,
`mount_hammer/{Makefile,mount_hammer.8,mount_hammer.c}` and
`newfs_hammer/{Makefile,newfs_hammer.c}` (modified), and for the shared
sources moved to `common/` (`blockmap.c`, `cache.c`, `hammer_util.h`,
`misc.c`, `ondisk.c`, `uuid.c`).

`grep -L "DragonFly Project"` lists only files that are new (`hammer_admit.[ch]`,
`hammer_port.h`, `hammer_rhapsody.[ch]`, `hammer_rostubs.c`,
`common/compat.[ch]` and the `common/` mirrors of the kernel's admission
and CRC files) or carry another upstream notice (`crc32.c` and `icrc32.c`:
Gary S. Brown; `hammer_tree.h`: Niels Provos; `hammer/test_dupkey.c` has
none upstream).  `hammer_io.c` keeps the DragonFly notice with a RhapsodiOS
line added.

## Write path (Phase 2)

- **Device writes are synchronous.**  `hammer_io_flush()` writes `io->data`
  through `hammer_io_write_sync()` (8 KB `getblk`/`bwrite` chunks, the
  mirror of `hammer_dev_read`) and returns when the device has it, so the
  flusher's stage order (data, UNDO, volume header, meta-data) is the
  on-disk order and no write is ever left running.
  shortcut: synchronous 8 KB writes; move to async VOP_STRATEGY with
  completion ordering when throughput matters.
- **Dirty buffers stay in kernel memory until the flusher writes them.**
  Upstream let the kernel write dirty data and UNDO buffers whenever it
  liked; here only the flusher writes, so a modified io keeps `io->data`
  across its last release, and every dirty type counts in
  `locked_dirty_space`, against `hammer_limit_dirtybufspace`.
- **One flusher thread per read-write mount**, a Mach kernel thread
  (`hammer_kthread_create`, the argument passed through `ith_other`)
  started by the mount and stopped, after `hammer_flush_dirty()`, by
  unmount.  Upstream's slave pool becomes `hammer_flusher_run_group()`, run
  inline by that thread.  LWKT tokens stay no-ops (see the token audit);
  `hammer_lock_*` stay real.
- **Read-write admission** (`hammer_admit_rw`, after `hammer_admit_volume`):
  recovery stage 1 scans the UNDO FIFO for the end of its sequence space
  (this also sets `hmp->undo_seqno`) and refuses any active range with
  EOPNOTSUPP; and B-Tree keys sort by localization first, so the tree's last
  element is the only one whose PFS needs checking.  `hammer_recover.c` is
  compiled for stage 1 and the FIFO scan only; replay waits for Phase 3.
- **No REDO.**  `hammer_generate_redo_sync`, REDO_TERM generation and the
  redo FIFO bookkeeping are fenced; the flags that would trigger them are
  only set by REDO generation.  `hammer_fsync_mode` is a full flush.
- **Memory limits scale with RAM** (`hammer_rhapsody_limits`, from
  `hammer_vfs_init`): `hammer_limit_dirtybufspace = min(mem/16, 32 MB)`, and
  upstream's `hammer_limit_reclaims` is capped at `max(mem/65536, 256)`.
  On 128 MB that is 8 MB and 2048.
- **Sync** walks the mount's vnode list as `ffs_sync` does (Rhapsody has no
  `vsyncscan`), fsyncs dirty inodes, then runs the flusher twice.
- **Critical write errors** set `hmp->ronly = 2`.  Upstream also set
  MNT_RDONLY and reopened the device read-only (`hammer_adjust_volume_mode`,
  removed with `hammer_volume.c`); the HAMMER VOPs check `hmp->ronly`.
- Rhapsody has no `ticks`, `MNT_NOATIME` or `VINACTIVE`: `hammer_ticks()`
  derives a tick count from the time of day, atime updates stay off
  (`hammer_noatime`), and a vnode with no users has `v_usecount == 0`.
- The UNDO zone is readable through `hammer_get_buffer` again
  (`hammer_undo_lookup`); B-Tree and record offsets are checked against their
  own zones before they get there.

## Left for Phase 2

- Write paths still behind `#if 0 /* phase 2 */`: `hammer_inode.c` (create,
  PFS save and unload), the read/flush time multiplexing in
  `hammer_cursor.c`, and the DragonFly VOPs in `hammer_vnops.c`.
- Not compiled yet: `hammer_redo.c`, `hammer_reblock.c`,
  `hammer_rebalance.c`, `hammer_prune.c`, `hammer_dedup.c`,
  `hammer_mirror.c`, `hammer_ioctl.c`, `hammer_signal.c`.  `hammer_inode.c`
  generates the redo tree until the redo unit returns.
- `telldir`/`seekdir` on HAMMER directories (see "Directory offsets and
  telldir").
- Device and FIFO nodes use the regular op table (they stat but cannot be
  opened); readdir returns no NFS cookies; `hammer info` waits for the
  ioctls.

## Evidence

| Check | CPU | Result | Date |
| --- | --- | --- | --- |
| `tests: make check` (swap_test, admit_test) | i386 guest, native cc | PASS | 2026-10-17 |
| `tests: make check CPPFLAGS=-DHAMMER_TEST_SWAP` | i386 guest, swap forced | PASS | 2026-10-17 |
| `rbuild kernel`, HAMMERFS on: links, 212 hammer symbols | i386, ppc | PASS | 2026-10-18 |
| `rbuild kernel`, HAMMERFS off: links, 0 hammer symbols | i386 | PASS | 2026-10-18 |
| `rbuild buildpackage hammer-1` (newfs_hammer, mount_hammer, hammer) | i386, ppc | PASS | 2026-10-18 |
| `hammer_guest.py run` admit, refuse-rw, refuse-{badsig,badcrc,v6,twovol,needs-recovery} | i386 guest | PASS, volume unchanged | 2026-10-18 |
| Task 6 read path: `rbuild kernel` links (i386 in the build root; ppc 376 hammer symbols) | i386, ppc | PASS | 2026-10-19 |
| `hammer_guest.py run` namespace (walk matches DragonFly's read-write manifest, 20,128 lines), readdir-small (20,002 names, d_fileno == st_ino), times, erofs, crafted-name, plus the seven Task 5 cases | i386 guest | PASS, volumes unchanged | 2026-10-19 |
| Task 7 file data: `hammer_guest.py run` data and dedup (full walks with content CRCs match DragonFly), holes, mmap, crafted-data (EIO, other files still read), plus all Task 5 and 6 cases | i386 guest | PASS, volumes unchanged | 2026-10-19 |
| `hammer_guest.py run cycle`: 100 mount -o ro / walk -n / unmount cycles on ref-main, no `hammer: leaked`, no panic | i386 guest | PASS, volume unchanged | 2026-10-22 |
| Regression on the HAMMER kernel: ext2 `readonly` (v2-based root; on the golden root ext2fs's own `DKIOCGPARTINFO` call fails with EINVAL, as it does without HAMMER), HFS `read`, UFS root boot | i386 guest | PASS | 2026-10-22 |
| `sha256sum -c ORIGIN` and notice check (see "Provenance check") | host | as documented | 2026-10-22 |
| ppc: kernel (376 hammer symbols) and hammer-1 package built; `make check CPPFLAGS=-DHAMMER_TEST_SWAP` passes on i386 | ppc build | PASS | 2026-10-22 |
| ppc runtime | ppc | **open**, no ppc runtime available | |
