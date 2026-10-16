# Filesystem regressions for issues 52–55

The repair branch is based on `issue-43` (`12607a01b`), the kernel lineage
used in the reports. It requires that branch's earlier rename and MapFS
fixes; those prerequisites are not yet present on `master`.

Use a private QEMU snapshot of the bootstrapped i386 image and disposable
ext2, HFS+ and FAT16 volumes. Never run these tests on data to keep.

## Focused regressions

Build with the guest compiler:

```sh
cc -O -o ext2_mmap_truncate_test ext2_mmap_truncate_test.c
cc -O -o hfs_rename_test hfs_rename_test.c
cc -O -o msdosfs_rename_test msdosfs_rename_test.c
./ext2_mmap_truncate_test /mnt/e/truncate-test
./hfs_rename_test /mnt/h
./hfs_rename_test /mnt/h locks
./msdosfs_rename_test /mnt/m
```

The ext2 test checks dirty sparse mappings shrunk across direct/indirect
block boundaries, partial-page EOF, truncation to zero, and zero-filled
regrowth. The HFS test checks stale case aliases and `..`, failed busy
replacement cleanup, successful replacement, and rename versus lookup
between ancestor and descendant directories. The MSDOS test checks source
preservation on refused renames and concurrent opposing file/directory moves.

The host pageout test compiles the production pageout and write-size code
against a controlled write boundary:

```sh
python vm/msdosfs_pageout_test.py --cc /path/to/clang
```

It checks stale pageouts past EOF, partial final pages, errors, and legitimate
cached extension before the denode's on-disk size catches up.

## Original stress workloads

Use the phase-3 `src/Commands/stress` suite from the reported baseline:

```sh
stress-mmap -n 1 -i 1 -s 1 -d /mnt/e trunc
stress-mmap -n 1 -i 2 -s 1 -d /mnt/m private
stress-mmap -n 1 -i 1 -s 1 -d /mnt/m trunc
stress-fs -n 4 -s 10 -d /mnt/h tree
stress-fs -n 4 -s 1 -d /mnt/h rename
stress-fs -n 4 -s 1 -d /mnt/m rename
stress-fs -n 4 -s 3 -d /mnt/m rename
```

HFS may return `EBUSY` for in-use objects; distinguish that existing
limitation from a kernel deadlock. Use a host watchdog because blocked
kernel vnode-lock waits cannot reliably be terminated by a guest signal.
Unmount and check each scratch filesystem after testing.

## Baseline evidence (2026-10-15)

On `mach_kernel.issue43` (cksum `1562297808`, 1,853,336 bytes):

- ext2 focused test: `TRUNCATE start length=20480`, then
  `panic: ext2fs_truncate2` (the same block-pointer snapshot violation as #52).
- HFS focused test: old case alias and cached `..` both survived the move.
- FAT16 original `private`: `short-read off=0x2000`, worker 0, iteration 1.
- FAT16 original `trunc`: `no-sigbus`, worker 0, iteration 0.
- Host pageout regression failed before both the EOF and cached-size fixes;
  the corrected production code reports `msdosfs pageout failures=0`.

## Repair verification (2026-10-15)

The native `rbuild kernel --arch i386` build completed with status 0 using
the GCC Darwin i386 toolchain. The booted repair kernel has cksum
`3500498149`, size 1,853,372 bytes, and SHA-256
`ef727796e745f4a6fc26163afcc97bc00a839a47d2525987a6c510724c661448`.

- Ext2 focused shrink/regrow test: all four lengths passed. The original
  `trunc -n 1 -i 1 -s 1` reproducer also passed without a panic.
- HFS focused cache and busy-replacement checks passed. The lock test
  completed 4,000 moves against 10,000 concurrent descendant lookups.
- MSDOS focused rename test passed: four workers each completed 4,000
  opposing moves, including file and directory moves and lookup checks.
- FAT16 original `private -n 1 -i 2 -s 1` and
  `trunc -n 1 -i 1 -s 1` reproducers passed.
- Extended `shared mixed private trunc -n 3 -i 20 -s 2` workloads passed
  on ext2, FAT16, HFS+, and UFS. The suite runs `mixed` with one worker.
- FAT16 `tree` and `rename` passed with four workers, 500 iterations, and
  seeds 1, 3, and 10. Ext2 and UFS passed the same workloads with seed 1.
- HFS `tree` and `rename` for those three seeds terminated with `EBUSY`
  rather than hanging. These are not full stress-suite passes: in-use
  object limitations remain, while the focused lock test completes.
- The host pageout fixture passed under Windows Clang and Linux GCC.
- After unmounting, FAT16 `fsck_msdos -n` passed. After shutting down the
  guest, HFS's host consistency checker reported zero problems and ext2
  `e2fsck -fn` passed all five phases without filesystem errors.

An additional experiment ran the ext2 shrink/regrow test on FAT16 and UFS.
It exposes pre-existing direct-user-mmap coherency failures: FAT16 returns
old data after the truncated EOF on regrowth; UFS loses retained dirty data.
Both failures were reproduced on the unmodified `issue-43` kernel as well
as the repair kernel. They are separate from the private-file shortening
and missing-SIGBUS failures in #55. The equivalent FAT16 test using `write`
instead of mmap passes. No fix for these additional cases is claimed here.

Testing used an i386 QEMU snapshot with separate disposable data volumes.
PowerPC runtime behavior was not tested. The kernel package, binary, native
build log, and detailed run logs are retained outside Git in the primary
checkout's `vm/work/issues52-55/` directory. The first mmap script referenced
focused test binaries removed by boot-time `/tmp` cleanup; those tests were
rebuilt in `/var/t` and rerun successfully in their separate focused logs.
