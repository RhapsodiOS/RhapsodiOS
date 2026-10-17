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

## Admission

`hammer_admit_volume()` (`hammer_admit.c`) is the single admission rule set,
shared by the kernel mount and the tools. It refuses:

- A short header, an unknown device size, a wrong or byte-swapped signature,
  a CRC mismatch, bad geometry or a volume larger than its device: `EINVAL`.
- A version other than 7, `vol_count != 1`, `vol_no != 0`, or an UNDO FIFO
  that needs recovery: `EOPNOTSUPP`.

## Evidence

| Check | CPU | Result | Date |
| --- | --- | --- | --- |
| `tests: make check` (swap_test, admit_test) | i386 guest, native cc | PASS | 2026-10-17 |
| `tests: make check CPPFLAGS=-DHAMMER_TEST_SWAP` | i386 guest, swap forced | PASS | 2026-10-17 |
| ppc runtime | ppc | **open**, no ppc runtime available | |
