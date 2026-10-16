# Stress suite phase 4 design

## Purpose

Phase 4 finishes the stress suite (phases 1-3: `2026-10-13-stress-suite-design.md`,
`2026-10-14-stress-suite-phase2-design.md`, `2026-10-15-stress-suite-phase3-design.md`). The one manual run of the
suite against ext2fs, HFS+ and FAT16 found five kernel bugs (#52-#56) and led to #58, while the harness has only
ever exercised UFS. Phase 4 makes other filesystems — and loopback NFS — first-class harness targets, closes three
small gaps phase 3 left, and makes the leak report usable.

## Base

Branch `stress-phase4`, cut from ffs-perf `d9b706dc7` (phase 3, #43, #51, #52-#56, #58 fixes). Everything from
phases 1-3 applies unchanged: result grammar, `-x` self-check, `-l`/`-L`/`-T`, leak fields, `run`, `soak`,
`Report/`, `ffsbench stress`, `stress_report.py`, guest rules.

## Success criteria

- `ffsbench stress --fs all` on a kernel built from this branch (driverkit rebuilt, so #47 is in) builds, mounts
  and stresses every target filesystem; each target's `fs` and `mmap` lines end PASS or UNSUP apart from failures
  traced to filed kernel issues; every post-run fsck is clean; `result.txt` reports each target separately.
- A target that cannot be built, mounted or served is reported as UNSUP with the reason; the run continues.
- `run 1` and `soak -t 600 -j 4` on the dev guest still exit 0.
- Leak fields appear only on lines from tests that ran alone (`run`'s one-at-a-time phase, direct invocations).
- `mmap regrow`, the `lost-child` FAIL and the `msync` fallback each have a `make check-*` assertion; new data
  tests FAIL under `-x`.

## 1. Filesystem targets

- `ffsbench stress --fs LIST` where LIST is a comma list of `ufs` (default), `ext2`, `hfs`, `msdos`, `nfs`, or `all`.
  `--fs` combines with `--cats` (default for non-UFS targets: `fs mmap`). `--soak` runs on UFS only, so `--fs` with
  `--soak` is an argument error.
- One scratch disk per non-UFS target, attached beside hd1, each a throwaway file in the run's outdir:
  - **hfs:** HFS+ volume built on the host with `tools/hfsimg` + `vm/hfs_guest.wrap_label` (as `vm/hfs_guest.py`).
  - **msdos:** a 512-byte-label disk (`vm/ext2_guest.wrap_volume` layout); formatted on the guest with the fixed
    `newfs_msdos` (#56).
  - **ext2:** prefer a builder already in the repo (host Python, or a guest `mke2fs`/`newfs_ext2` from
    `src/ext2fs-1`); else the WSL `mke2fs -r 1 -O filetype,sparse_super -I 128 -b 1024` + `wrap_volume` route the
    manual run used. The plan's first ext2 step decides which, by checking.
  - **nfs:** no disk; see section 3.
- Guest tools built on the guest from source, like the suite itself: `mount_ext2fs` (`src/ext2fs-1`), `mount_hfs`
  (`src/hfs-1`), `mount_msdos`/`newfs_msdos`/`fsck_msdos` (`src/msdosfs-1`). Shipped with
  `git -c core.autocrlf=false archive`. A tool that fails to build makes only its target UNSUP.
- Per target: make the filesystem, mount it at `/mnt/<fs>`, run `run -d /mnt/<fs> 1 <cats>` (the existing runner),
  copy its `Report/` aside as `Report.<fs>/`, unmount, then fsck: `fsck_msdos -n` on the guest; ext2 `e2fsck -fn`
  (WSL) and the HFS checker (`vm/hfs_guest.py` check path) on the host against the disk image after the guest
  stops; UFS keeps today's behaviour.
- Expected filesystem limits are UNSUP, not FAIL: no hard links/symlinks (phase 3's `link` probe); HFS refuses
  `rmdir`/`rename` of in-use objects with EBUSY — `tree` and `rename` on HFS report UNSUP
  `reason="EBUSY: in-use object"` when they hit it (implemented as: when the test's directory lives on an hfs
  mount — `statfs` f_fstypename "hfs" — EBUSY from rmdir/rename ends the test as UNSUP), recorded in the README.
- `result.txt` gains `"targets": {"<fs>": {"status": "ran"|"unsup", "reason": ..., "counts": ..., "fails": [...],
  "fsck": "clean"|"<summary>"}}`; `stress_report.py` summarizes per target. The UFS section stays where it is.

## 2. Follow-ups

- **`mmap regrow`**: the #59 test (`vm/ext2_mmap_truncate_test.c`) as a stress test: per iteration, a MAP_SHARED
  file of 64 KiB patterned through the mapping, shrunk to a length chosen from {20480, 20517, 5157, 0} while mapped,
  mapping checked below the cut, munmap, regrown, fsync, re-read with `read()`: pattern below the cut, zeros above.
  `-x` corrupts one byte before the re-read check. If branch `issue-59` already added an equivalent test, reuse it.
  It FAILs on kernels without the #59 fix (filed). `check-mmap` requires `regrow` PASS and its comment says the #59
  fix is needed; on an older kernel that line failing is the known #59 result.
- **`lost-child`**: in `lib/main.c`'s leader loop, when `live > 0` and `waitpid(-1, ...)` fails with ECHILD, end
  the test as `FAIL reason=lost-child live=N`. A `make check` line proves it with a `tmain` test that makes the
  leader lose its children (e.g. a worker that `setpgid`s and is reaped by an intermediate — the plan picks the
  simplest provable trigger, or tests the helper directly).
- **`msync` fallback**: `mmap/mmap.c`'s `bindsync` falls back to `syscall(65, addr, len)` like `wire`'s 177/178,
  ignoring SIGSYS around the probe; `sync` then runs on images whose Libc lacks `_msync`.

## 3. Loopback NFS

- First a feasibility step on the guest: start whatever the image provides (`portmap`, `mountd`, `nfsd` /
  `nfsiod`; `/etc/exports` with a scratch UFS directory on hd1 exported to 127.0.0.1), mount it with `mount -t nfs
  127.0.0.1:/mnt1/nfsexp /mnt/nfs` (or the image's equivalent), and write/read a file. Record exactly what works.
- If it works: `nfs` is a `--fs` target — server dir on the UFS scratch disk, client mount at `/mnt/nfs`, `fs mmap`
  run there, then UFS fsck of hd1 as today.
- If it does not: the `nfs` target reports UNSUP with the precise reason (missing daemon, mount error, hang), and
  the phase records it; fixing NFS daemons or the NFS kernel code is out of scope.

## 4. Leak report only where meaningful

- New binary option `-N`: no leak snapshot, no leak fields, `-L` ignored.
- Every `runtests` passes `-N` in its all-at-once phase; `soak` passes `-N` unless `soak -L` is given (then it
  passes `-L` and the README's caveat about concurrent noise applies).
- README updated; `check` asserts `-N` suppresses the fields (`tmain -N pass` line has no `leak=`).

## Testing

- Host: `vm/test_ffsbench.py` for `--fs` parsing (`all` expansion, `--soak` conflict), the per-target result
  structure and volume-building helpers that run on the host; `vm/test_stress_report.py` for per-target summaries.
- Guest: each new test FAILs under `-x`; `make check` and every `check-<cat>`.
- Acceptance: kernel built from this branch with driverkit; `ffsbench stress --fs all`; `run 1`; `soak -t 600 -j 4`.
  Any new kernel bug gets an issue draft in `vm/work/stress-suite-evidence/phase4/`.

## Out of scope

- Fixing kernel bugs the targets find (each gets an issue).
- NFS daemon or NFS kernel work if loopback NFS does not run.
- `soak` on non-UFS targets; `disk` category changes.
- Rebuilding/installing Libc on the image.
