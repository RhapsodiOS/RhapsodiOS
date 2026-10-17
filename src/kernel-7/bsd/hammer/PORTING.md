# HAMMER port state

Source: DragonFly BSD `4e10f78d03f3d76c5bbe99c5d65022a03ea21e2e`, see `ORIGIN`.
Design: `docs/superpowers/specs/2026-10-17-hammer-design.md`.
Plan: `docs/superpowers/plans/2026-10-17-hammer-phase1.md`.

This is a single-volume, single-namespace (root PFS only), version-7 HAMMER.
Phase 1 is read-only.

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
compiles silently. In that position the type check catches nothing. A
`lelint.py`-style audit (every on-disk field access must sit inside
`hget*()` or be stored with `hmk*()`) is run over each converted file, and
its hits are fixed or confirmed as host-struct fields of the same name. The
first such bug it found was `hammer show` printing `mode=27777600755`.

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
  `hexdump(3)` and `hammer_device_size()` (`DKIOCGPARTINFO` or `fstat`).
- Rhapsody's printf supports `%q`. `%ll` prints only the low 32 bits and
  `%j` is unknown, so every 64-bit conversion uses `%q`.
- gcc 2.7's cpp has no variadic macros, so `hwarn`/`hwarnx` are functions.
- `newfs_hammer` creates a single version-7 volume only. `-E` (TRIM) is
  refused, and the version comes from `-V` or the default, not
  `sysctlbyname`.
- `hammer` dispatches `show`, `show-undo`, `blockmap`, `checkmap` and the
  `namekey*` helpers. The other commands stay in `hammer.c` under `#if 0`,
  and their sources are left out of the Makefile.
- Rhapsody has no `/dev/zero`, and `dd` will not extend a file with `seek`.
  Test images are made with perl `truncate`, at 2047 MiB to stay below 2^31.

## Upstream defects found (to examine in Phase 2)

- **`utimes()` does not persist** on DragonFly 6.4.2 HAMMER. An explicit mtime
  holds in memory and through `sync`/`hammer synctid`, but a remount shows the
  creation time again, even after a forced inode rewrite (`chmod`/`chown`).
  Reproduced in `vm/work/dfly/run-diag-4` and `run-diag-5`
  (`vm/dfly-reference.md`). This breaks `cp -p`, `tar x` and `make`. Phase 2
  owns the write path; decide there whether to fix it as a labelled
  divergence.

## Evidence

| Check | CPU | Result | Date |
| --- | --- | --- | --- |
| `tests: make check` (swap_test, admit_test) | i386 guest, native cc | PASS | 2026-10-17 |
| `tests: make check CPPFLAGS=-DHAMMER_TEST_SWAP` | i386 guest, swap forced | PASS | 2026-10-17 |
| ppc runtime | ppc | **open**, no ppc runtime available | |
