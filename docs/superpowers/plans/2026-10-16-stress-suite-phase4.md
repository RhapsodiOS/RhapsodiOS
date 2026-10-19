# Stress Suite Phase 4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make ext2fs, HFS+, FAT16 and loopback NFS first-class `ffsbench stress` targets, add `mmap regrow`, the `lost-child` FAIL and the `msync` fallback, and limit leak fields to tests that ran alone.

**Architecture:** In `--fs` mode the harness replaces the workload disk (hd2) with one targets disk holding three empty partitions (a=ext2, b=hfs, c=msdos) built by `ext2_guest.wrap_volumes`; the guest builds the filesystems' tools from `src/ext2fs-1`, `src/hfs-1`, `src/msdosfs-1`, formats and mounts each partition, runs the existing `run` on it, fscks it, and the host records a per-target section in `result.txt`. Library changes are small additions to `lib/main.c`, `mmap/mmap.c` and `fs/fs.c`.

**Tech Stack:** C89 on RhapsodiOS i386 (NeXT cc), POSIX sh, GNU make 3.74, Python 3 harness (pytest).

**Spec:** `docs/superpowers/specs/2026-10-16-stress-suite-phase4-design.md`

## Global Constraints

- Worktree `D:\RhapsodiOS\.claude\worktrees\stress-phase4` (branch `stress-phase4`); suite sources `src/Commands/stress/` (`S/` below). Edit/commit only there; no bare `git stash`.
- C89 house style of `S/lib/*.c`; failures only via `st_fail*`; result grammar unchanged except the new reasons `lost-child` and `"EBUSY: in-use object"`.
- GNU make 3.74 pattern rules only; guest scripts POSIX sh; guest root shell tcsh (wrap in `sh -c`); guest `ls` of a missing path exits 0.
- Guests: boot `vm/work/rhap-i386-bootstrapped-v2.img` only with `-snapshot`; dev guest via `STRESS_DEV_PORTS=2563,4563,1263 python vm/stress_dev.py ...`; other guests own ports + `-name`; stop only by QMP quit after `query-name`; never write a base image.
- Commits: one line, subsystem prefix (`stress:`, `vm:`, `docs:`), no trailers.
- `--fs` values: `ufs` (default), `ext2`, `hfs`, `msdos`, `nfs`, `all`; non-UFS default cats `fs mmap`; `--fs` with `--soak` is an argument error.
- Mounts: `/mnt/ext2`, `/mnt/hfs`, `/mnt/msdos`, `/mnt/nfs`; targets disk partitions hd2a=ext2, hd2b=hfs, hd2c=msdos, each 128 MiB; device nodes block major 3 / raw major 15, hd2 minors 16 (a), 17 (b), 18 (c).
- `result.txt` per target: `"targets": {"<fs>": {"status": "ran"|"unsup", "reason": str, "counts": {...}, "fails": [...], "fsck": "clean"|str}}`.
- Host tests baseline: `python -m pytest vm/test_ffsbench.py vm/test_stress_report.py` = 53 passed, 1 skipped.

## Review Focus

1. A filesystem tool that fails to build, or a format/mount that fails: only that target is UNSUP with the command's error as reason; the other targets still run (Task 5 test: a fake failing step for one target).
2. A target whose `run` hangs or the guest stops answering mid-target: the harness marks that target `"status": "lost"` and still records the targets that finished (Task 5 host test of the result assembly).
3. `--fs all` while `nfs` is UNSUP: `all` still runs the other four (Task 4 host test of `all` expansion keeps nfs; Task 6 makes nfs report UNSUP cleanly).
4. HFS EBUSY: only on an hfs mount does EBUSY become UNSUP; on UFS an EBUSY from rmdir/rename stays a FAIL (Task 3 test via a non-hfs run).
5. `-N` with `-L`: `-N` wins, no fields and no leak FAIL (Task 1 check line).

---

### Task 1: `-N` (no leak report); runtests and soak use it

**Files:** Modify `S/lib/main.c`, `S/lib/stress.h` (`st_opts.noleak`), every `S/*/runtests`, `S/soak`, `S/Makefile` (`check`), `S/README`.

**Interfaces:** Produces binary option `-N`: no snapshots, no leak fields, `-L`/`STRESS_LEAK=fail` ignored.

- [ ] **Step 1:** Add to `check`: `$(TMAIN) -N -L pass >lib/t.out` exits 0 and `test \`grep -c ' leak=\| wired=\| mbufs=' lib/t.out\` = 0`. (Use a test that reliably leaks if one exists in t_main; otherwise the assertion is that -N -L exits 0 with PASS.)
- [ ] **Step 2:** Run `make check` on the dev guest → fails (unknown option).
- [ ] **Step 3:** Implement `-N` in getopt/usage; skip both `st_leak_snap` calls and the diff when set. In each runtests' all-at-once loop add `-N` to the binary's options (the one-at-a-time loop unchanged). In `soak`: pass `-N` unless `-L` was given.
- [ ] **Step 4:** `make check` passes; `sh ./run 1 misc` → no leak fields in the all-at-once phase lines; README options table + leak section updated.
- [ ] **Step 5:** Commit `stress: -N drops the leak report; runtests' concurrent phase and soak use it`.

### Task 2: `lost-child`, `msync` fallback, `mmap regrow`

**Files:** Modify `S/lib/main.c` (leader loop), `S/lib/t_main.c`, `S/mmap/mmap.c`, `S/mmap/runtests`, `S/Makefile` (`check`, `check-mmap`), `S/README`.

**Interfaces:** Produces FAIL `reason=lost-child live=N`; test `regrow` (def_iters 40); `sync` uses `syscall(65, addr, len)` when dyld has no `_msync`.

- [ ] **Step 1:** First check branch `issue-59` (`git log issue-59 -- src/Commands/stress`) for a regrow test; if one exists, cherry-pick it instead of writing Step 3's regrow and say so.
- [ ] **Step 2: Tests.**
  - `check`: a `tmain` test `lostkid` whose worker makes the leader see ECHILD with live > 0 — simplest provable trigger: the worker forks a grandchild and then calls `_exit` while the leader's `waitpid` is made to fail, OR expose the decision as a static helper `lost(int live, int err)` and assert it from `lib/t_lib.c` (`lost(1, ECHILD) == 1`, `lost(0, ECHILD) == 0`, `lost(1, EINTR) == 0`). Prefer the helper if no clean trigger exists; record which.
  - `check-mmap`: `regrow` PASS in the default run (comment: needs the #59 kernel fix); `-x` run includes `regrow` and its FAIL count joins the derived total; `sync` now `PASS` on kernels with msync (keep `PASS|UNSUP`).
- [ ] **Step 3: Implement.**
  - Leader: in the `while (live > 0)` loop, when `waitpid(-1, &status, WNOHANG)` returns -1 with errno ECHILD, set `fail` to `lost-child live=%d` and break out the same way a worker failure ends the test.
  - `bindsync`: like `vm.c`'s wire fallback (wrappers calling `syscall(65, ...)`, SIGSYS ignored around the probe).
  - `regrow`: per iteration on its own `st_path` file: create, `ftruncate` 64 KiB, `mmap` MAP_SHARED, fill with `st_fill(key)`, `ftruncate` to `lens[i % 4]` with `lens = {20480, 20517, 5157, 0}`, `st_check` the mapping below the cut, `munmap`, `ftruncate` 64 KiB, `fsync`, close, reopen, `read` all: `st_check` below the cut, zeros above (`what=zero` FAIL with off on a nonzero byte). `-x`: flip one byte of the read buffer below the cut (when cut > 0) before the check.
- [ ] **Step 4:** `make check` and `make check-mmap` on the dev guest: `regrow` FAILs at off=0x5000 on the dev guest's kernel unless it has the #59 fix — record the line; everything else passes. The final PASS is shown in Task 7.
- [ ] **Step 5:** Commit `stress: lost-child FAIL, msync syscall fallback and mmap regrow`.

### Task 3: HFS EBUSY reports UNSUP

**Files:** Modify `S/fs/fs.c` (`tree`, `rename`), `S/README`.

**Interfaces:** Produces `static int on_hfs(const char *dir)` (statfs `f_fstypename` == "hfs"); `tree`/`rename` end `UNSUP reason="EBUSY: in-use object"` when rmdir/rename returns EBUSY and `on_hfs(st_opt.dir)`.

- [ ] **Step 1:** Check how a body can end as UNSUP today (only probes return UNSUP). If the library has no body-side UNSUP, add `void st_unsup(struct st_ctx *c, const char *fmt, ...)` to `lib/main.c`/`stress.h` that sends an UNSUP line through the result pipe and `_exit(0)`s, with the leader printing UNSUP instead of PASS when any worker sent one; `check` gets a `tmain unsupbody` line asserting `UNSUP reason=` and exit 0.
- [ ] **Step 2:** Implement `on_hfs` and the EBUSY branch; EBUSY on any other filesystem still FAILs (Review Focus 4: `check-fs` unchanged on /tmp proves no regression).
- [ ] **Step 3:** `make check check-fs` on the dev guest pass. The hfs path is exercised in Task 5.
- [ ] **Step 4:** Commit `stress: fs tree and rename report UNSUP for HFS's in-use EBUSY`.

### Task 4: harness `--fs` (host side)

**Files:** Modify `vm/ffsbench.py`, `vm/stress_report.py`, `vm/test_ffsbench.py`, `vm/test_stress_report.py`.

**Interfaces:** Produces:
- `parse_fs(arg: str) -> list[str]` — `""`/`ufs` → `["ufs"]`; `all` → `["ufs","ext2","hfs","msdos","nfs"]`; comma list validated; raises `ValueError` on unknown names.
- `targets_disk(path: str, mb: int = 128) -> None` — writes `ext2_guest.wrap_volumes([bytes(mb MiB)] * 3)` to path (a=ext2, b=hfs, c=msdos).
- `TARGET_MOUNT = {"ext2": "/mnt/ext2", "hfs": "/mnt/hfs", "msdos": "/mnt/msdos", "nfs": "/mnt/nfs"}`; `TARGET_PART = {"ext2": "a", "hfs": "b", "msdos": "c"}`.
- `target_result(name, status, reason="", report_text="", fsck="") -> dict` building the spec's per-target record from a target's `Report.<fs>/` outputs via `stress_report.summarize(parse(...))`.
- `stress_report.summarize_targets(targets: dict) -> list[str]` — one line per target `<fs> PASS=n FAIL=n UNSUP=n fsck=<..>` or `<fs> unsup: <reason>`.
- CLI: `stress --fs LIST`; `--fs` + `--soak` → `p.error`.

- [ ] **Step 1: Tests** in `vm/test_ffsbench.py`: `parse_fs` cases above incl. `"ext2,msdos"` and `"bogus"` → ValueError; `targets_disk` writes a file whose NeXT label lists three partitions of 128 MiB at increasing bases (read back with `rhap_image`/label struct like `test_ext2_guest.py` does); `target_result` for a status `unsup` and for a report text with one FAIL; CLI `--fs ext2 --soak 60` errors. In `vm/test_stress_report.py`: `summarize_targets` formats both kinds.
- [ ] **Step 2:** pytest → fail. **Step 3:** implement. **Step 4:** pytest → 53 + new pass, 1 skipped.
- [ ] **Step 5:** Commit `vm: ffsbench stress --fs parsing, targets disk and per-target results`.

### Task 5: harness `--fs` (guest side): tools, format, mount, run, fsck

**Files:** Modify `vm/ffsbench.py` (`stress()`), create `vm/stress_fs.sh` (guest script, shipped with the suite tar), `vm/test_ffsbench.py`.

**Interfaces:** Consumes Task 4. Produces guest script `stress_fs.sh <fs> <cats> <seed>` that: makes nodes for `/dev/hd2<p>`/`/dev/rhd2<p>` (minors 16/17/18), formats (`ext2`: the guest-built mke2fs from `src/ext2fs-1` with `-r 1 -O filetype,sparse_super -I 128 -b 1024`; `hfs`: guest-built `newfs_hfs`; `msdos`: guest-built `newfs_msdos`), mounts at the target mount, runs `/usr/local/stress/run -s <seed> -d <mount> 1 <cats>`, copies `Report` to `Report.<fs>`, unmounts, fscks (`ext2`: guest e2fsck `-fn`; `msdos`: `fsck_msdos -n`; `hfs`: none on guest — the host checks after shutdown with `vm/hfs_guest.py`'s checker on partition b of the targets disk), and prints `STRESSFS <fs> status=<ran|unsup> reason="..." fsck="..."` as its last line.

- [ ] **Step 1: Manual bring-up first** on a throwaway guest (ssh 2653 / QMP 4653 / `-name phase4-fs`, kernel `D:\RhapsodiOS\vm\work\issue58\mach_kernel` which has msdosfs + #58 + #47): build each project's tools on the guest (`make` in `src/ext2fs-1`, `src/hfs-1`, `src/msdosfs-1`, or the subdirectories that produce mke2fs/e2fsck, newfs_hfs/mount_hfs, newfs_msdos/mount_msdos/fsck_msdos — find the right make targets; earlier sessions' recipes: `vm/work/fsrepro/`, `vm/work/fs-races/msdos/`, `vm/ext2-acceptance.md`, `vm/hfs_guest.py`). Format, mount, write a file, unmount, fsck each of the three partitions of a `targets_disk`. Record the exact working commands in `vm/stress_fs.sh`.
- [ ] **Step 2: Host test** for the per-target loop's error handling with the guest stubbed (the `Ssh`/`Guest` fakes `test_ffsbench.py` already uses for stress): one target's script ends `status=unsup reason="mount_hfs: ..."` → that target recorded unsup, the others ran (Review Focus 1); a target whose ssh call times out → `"status": "lost"` and earlier targets kept (Review Focus 2).
- [ ] **Step 3: Wire `stress()`**: when `--fs` names non-UFS targets, build the targets disk with `targets_disk` as hd2 instead of `_workload()`, mount only hd1 (`/mnt1`) for UFS, ship and build the fs tools once, run UFS as today if `ufs` is in the list, then `stress_fs.sh` per target in order, fetching `Report.<fs>/*` and the STRESSFS line; after `g.quit()` run the HFS host check; assemble `"targets"` with `target_result`.
- [ ] **Step 4:** pytest passes; on the throwaway guest's lane, `python vm/ffsbench.py stress --kernel D:\RhapsodiOS\vm\work\issue58\mach_kernel --label p4-fs --fs ext2,hfs,msdos` produces a `result.txt` with three target sections. Kernel bugs found → issue drafts, not fixes.
- [ ] **Step 5:** Commit `vm: ffsbench stress runs the suite on ext2, HFS and FAT16 targets and fscks them`.

### Task 6: loopback NFS target

**Files:** Modify `vm/stress_fs.sh`, `vm/ffsbench.py`, `S/README`.

- [ ] **Step 1: Feasibility** on the throwaway guest: what the image has (`ls /usr/sbin /usr/etc /etc | grep -i -E "nfs|mount|portmap|rpc"`, `/etc/rc*`, `/etc/exports`), start portmap/mountd/nfsd as the image's rc would, export `/mnt1/nfsexp` (on hd1) to 127.0.0.1, `mount 127.0.0.1:/mnt1/nfsexp /mnt/nfs` (try the image's mount syntax variants), write and read back a file. Record exact results.
- [ ] **Step 2:** If it works: `stress_fs.sh nfs` does that setup and runs `fs mmap` on `/mnt/nfs`, then unmounts; the UFS fsck of hd1 covers the server side. If not: `stress_fs.sh nfs` prints `STRESSFS nfs status=unsup reason="<exact failure>"` without hanging (time-limit each daemon start and the mount at 60 s).
- [ ] **Step 3:** Run `--fs nfs` once on the lane; README notes the result.
- [ ] **Step 4:** Commit `vm: loopback NFS stress target` (or `vm: nfs target reports UNSUP: <reason>`).

### Task 7: README and acceptance

- [ ] **Step 1:** README: `--fs` targets, how volumes are made, per-target results, HFS EBUSY UNSUP, `-N`, `regrow`, `lost-child`, msync fallback.
- [ ] **Step 2:** If `issue-59` has been merged into ffs-perf, merge ffs-perf into `stress-phase4` first. Build a kernel from this branch exactly as `vm/work/issue58/` did (driverkit-3, driverTools-1, drvPExpert, kernel-7; check the #47 code), save `vm/work/stress-phase4/mach_kernel` + cksum.
- [ ] **Step 3:** `python vm/ffsbench.py stress --kernel <it> --label phase4-accept --fs all`; dev guest on it: `make check` + every `check-<cat>`, `sh ./run 1`, `sh ./soak -t 600 -j 4`. Save outputs in `vm/work/stress-suite-evidence/phase4/`. New kernel bugs → issue drafts there.
- [ ] **Step 4:** pytest passes.
- [ ] **Step 5:** Commit `stress: document phase 4 targets and tests`.
