# Stress Suite Phase 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add phase 3 of the stress suite: rename/link, pty, net storm/flood and eintr tests, a per-test kernel leak report, a soak runner, the #43 follow-ups, and `mmap` of `/dev/zero`.

**Architecture:** New tests are entries in each category's `st_test` table on `libstress.a`. Leak reporting lives in a new `lib/leak.c`, called by the leader in `lib/main.c`. `soak` is a new sh script beside `run`. The `/dev/zero` mapping is a small change to `mmap()` in `kern_mman.c` that reuses the `MAP_ANON` path.

**Tech Stack:** C89 on RhapsodiOS i386 (NeXT cc, Mach + BSD), POSIX sh, GNU make 3.74, Python 3 host harness (`vm/ffsbench.py`, `vm/stress_report.py`, pytest).

**Spec:** `docs/superpowers/specs/2026-10-15-stress-suite-phase3-design.md`

## Global Constraints

- All paths below are relative to the worktree `D:\RhapsodiOS\.claude\worktrees\stress-phase3`; suite sources are under `src/Commands/stress/` (written `S/` below).
- C89, the house style of `S/lib/*.c`: tabs, `static` helpers, failures only through `st_fail`/`st_fail_errno`/`st_fail_data`, scratch files via `st_path` under `-d`.
- Result grammar unchanged; new fields: `leak=<zone>:+N[,<zone>:+N]... wired=+N mbufs=+N` (each only when past its threshold).
- GNU make 3.74: pattern rules only, no `$(call)`, no target-specific variables; every new `.o` goes in an existing pattern rule's directory.
- Guest shell scripts are POSIX `sh`; the guest's `ls` of a missing path exits 0 (use `test -f`/`test -c`).
- Guest testing: boot `vm/work/rhap-i386-bootstrapped-v2.img` only as a snapshot; own ports and `-name`; stop only by QMP `quit` after `query-name`; never write a base image.
- Commits: one line, subsystem prefix (`stress:`, `kernel:`, `vm:`), describe the change; no trailers or metadata.
- Thresholds (spec, verbatim): a zone grows by more than 64 elements and by more than 10% of its starting count; wired pages grow by more than 32; mbufs grow by more than 64; at most the top 3 zones listed.
- `soak` defaults (spec): `-t 3600`, `-j 4`, `-T 60`, categories `vm mmap fs proc net ipc thread misc`; never `disk`.
- `storm`: listener backlog 5, 64 connections. `flood` is `named_only` and needs `STRESS_EXHAUST=1`. `pty` retries up to 5 s for a free pty.
- `mlock` = syscall 177, `munlock` = 178 (from issue-43).

## Review Focus

1. Leak snapshot as a non-root user, or with `/dev/kmem` unreadable: the `mbufs=` field is simply absent and the test result is unchanged. (Task 2 test.)
2. A soak category whose binary is missing or whose `-l` prints nothing: soak skips it with a note in `soak.out` and still runs the others; it never spins with an empty pool. (Task 4 test.)
3. Every pty already in use (sshd holds some): `pty`'s probe reports UNSUP `reason="no free pty"` instead of FAILing. (Task 6 test.)
4. `eintr` timer firing before the call blocks: the round is retried, not failed; only lost or duplicated bytes and wrong return codes fail. (Task 8 test.)
5. `mmap` of `/dev/zero` with a nonzero offset or `MAP_FIXED`: offset ignored, `MAP_FIXED` behaves as for `MAP_ANON`; any other character device still EOPNOTSUPP. (Task 9 test.)

---

### Task 1: `-l` lists default tests; `fs fill` becomes `named_only`

**Files:**
- Modify: `S/lib/main.c` (getopt string `"n:i:t:s:d:m:D:vx"`, `usage`, `stress_main`)
- Modify: `S/fs/fs.c` (tests table, delete `named_any` and its use in `main`)
- Modify: `S/Makefile` (`check` target)

**Interfaces:**
- Produces: `stress-<cat> -l` prints each test with `named_only == 0`, one name per line, on stdout, exits 0, runs nothing. Task 4 relies on it.

- [ ] **Step 1:** Add a `named_only` entry to `lib/t_main.c`'s table, `{ "named", 1, 0, NULL, t_pass, 1 }` (reusing the `pass` body), and add to `check` in `S/Makefile`, after the `bogus` line:
```make
	$(TMAIN) -l >lib/t.out; grep -x pass lib/t.out; test `grep -c -x named lib/t.out` = 0
```
- [ ] **Step 2:** Build on the dev guest (`python vm/stress_dev.py up`, `sync`, `sh "cd /tmp/stress-src && make check"`); expect the new line to fail (`-l` unknown → usage, exit 2).
- [ ] **Step 3:** Implement `-l` in `stress_main`: parse it in getopt, then print and `return 0` before the seed line. Mark `fill` `named_only` (6th field `1`) and delete `named_any` plus the table-truncation it drives.
- [ ] **Step 4:** `make check` and `make check-fs` pass on the dev guest; `fs/stress-fs -l` prints `rw append tree fsync` (no `fill`).
- [ ] **Step 5:** Commit `stress: add -l to list a binary's default tests; fill is named_only`.

### Task 2: per-test leak report

**Files:**
- Create: `S/lib/leak.c`
- Modify: `S/lib/stress.h`, `S/lib/main.c` (`leader`, `run`, option `-L`), `S/lib/t_lib.c`, `S/Makefile` (`LIBOBJS`, link flags if needed)

**Interfaces:**
- Produces in `stress.h`:
```c
#define ST_LEAK_ZONES 256
struct st_leak {
	int nzones;			/* -1: zone info unavailable */
	char name[ST_LEAK_ZONES][80];
	long count[ST_LEAK_ZONES];
	long wired;			/* -1: unavailable */
	long mbufs;			/* -1: unavailable */
};
void st_leak_snap(struct st_leak *s);
/* Appends " leak=... wired=+N mbufs=+N" (only parts past the thresholds) to out; returns 1 if anything was appended. */
int st_leak_diff(const struct st_leak *before, const struct st_leak *after, char *out, int len);
```
- `st_opt.leakfail` (int) set by `-L` or env `STRESS_LEAK=fail`.

- [ ] **Step 1: Tests in `S/lib/t_lib.c`** (build `struct st_leak` values by hand, no kernel calls):
  - zone `"vm.objects"` 1000 → 1065 (+65, 6.5%): no output (fails the 10% rule).
  - zone `"ipc ports"` 100 → 165 (+65, 65%): output contains ` leak=ipc ports:+65`. Zone names may contain spaces; replace each space with `_` in the output, so expect ` leak=ipc_ports:+65`.
  - four zones growing +100, +200, +300, +400 (each >10%): output lists exactly the top 3 in descending order, `+400` first.
  - wired 500 → 533: ` wired=+33`; 500 → 532: nothing.
  - mbufs 10 → 75: ` mbufs=+65`; `mbufs == -1` in either snapshot: no mbufs field.
  - a zone present only in `after`: compared against 0 (so it reports if > 64 and the 10% rule is trivially met).
  - return value 0 and `out` unchanged when nothing passes.
- [ ] **Step 2:** `make check` on the dev guest fails to link (`st_leak_diff` undefined).
- [ ] **Step 3: Implement `S/lib/leak.c`.**
  - `st_leak_snap`: zones from `host_zone_info(host_self(), ...)` (`zn_name`, `zi_count`; `vm_deallocate` both arrays afterward); wired from `vm_statistics(task_self(), &vs)` `.wire_count`; mbufs by `nlist("/mach_kernel", ...)` on `_mbstat` and a read of `struct mbstat` from `/dev/kmem` at that address, mbufs in use = sum of `m_mtypes[1..255]` (what `netstat -m` reports). Any failing step sets that part to -1; nothing prints, nothing fails.
  - `st_leak_diff` exactly per the thresholds in Global Constraints; matches zones by name.
- [ ] **Step 4: Wire into the leader.** `run()` snaps `before` just before it forks the leader (after the probe); the leader snaps `after` after reaping its workers (both FAIL and PASS paths), and appends `st_leak_diff` output to `what` before `st_line`. With `st_opt.leakfail` and a non-empty diff on a PASS, print `FAIL reason=leak` plus the fields instead and exit 1. Add `-L` to getopt and `usage`.
- [ ] **Step 5:** `make check` passes. On the dev guest, `vm/stress-vm -i 1 cow` prints a normal line (snapshot works as root). Run the same as uid 1 (the `setuid(1)` approach check-disk uses) — no `mbufs=` field, result PASS (Review Focus 1). Put both lines in the task report.
- [ ] **Step 6:** Commit `stress: report kernel zone, wired-page and mbuf growth on each result line; -L fails on it`.

### Task 3: leaks in `run`'s summary and `stress_report.py`

**Files:**
- Modify: `S/run`, `vm/stress_report.py`, `vm/test_ffsbench.py`

**Interfaces:**
- Consumes: `leak=`/`wired=`/`mbufs=` fields (Task 2).
- Produces: `stress_report.summarize()` result gains `"leaks": [raw lines with any of those fields]`; `run -L` passes `-L` to every `runtests` (each runtests forwards unknown-to-it `-L` to its binary — add `-L` to every `runtests` option loop as a flag without a value).

- [ ] **Step 1: Test** `test_summarize_collects_leak_lines`: two PASS lines, one with ` leak=ipc_ports:+65 wired=+33`; `summarize(parse(text))["leaks"]` equals `[that line stripped]`, and the counts still show 2 PASS.
- [ ] **Step 2:** `python -m pytest vm/test_ffsbench.py -k leak` fails (KeyError).
- [ ] **Step 3:** Implement in `summarize`; in `run`, after the FAIL lines append `leaks:` then every `STRESS` line from all `$rep/*.out` that contains ` leak=`, ` wired=+` or ` mbufs=+` (awk), only if there is at least one. Add `-L` to `run`'s and each `runtests`' option parsing.
- [ ] **Step 4:** pytest passes (whole file: previous 50 passed, 1 skipped, plus the new one). On the dev guest `./run -L 1 misc` exits like before and its summary has no `leaks:` heading unless a line carries one.
- [ ] **Step 5:** Commit `stress: list leak lines in run's summary and the harness report; run -L`.

### Task 4: `soak`

**Files:**
- Create: `S/soak`
- Modify: `S/Makefile` (`install`), `S/README`, `vm/ffsbench.py` (`stress` subcommand `--soak SECS`), `vm/test_ffsbench.py`

**Interfaces:**
- Consumes: `-l` (Task 1), `run`'s report layout, `leaks:` format (Task 3).
- Produces: `soak [-t total] [-j slots] [-T test-secs] [-s seed] [-d dir] [-L] [cat ...]`; writes `Report/soak.out` (first line `soak: seed=<n>`) and `Report/soak.summary` (same format as `run`'s summary: per-category counts, FAIL lines, `leaks:`); exits 1 on any FAIL. `ffsbench.stress_soak_command(secs, seed)` returns the remote command string.

- [ ] **Step 1: Host test** `test_stress_soak_command`: `stress_soak_command(600, 7)` contains `/usr/local/stress/soak -s 7 -t 600 -d /mnt1` and ends by writing `$?` to `/tmp/stress.exit`, like `stress_run_command`.
- [ ] **Step 2:** pytest fails (no attribute).
- [ ] **Step 3: Implement `soak`.**
  - Pool: for each category, `(cd $here/$c && ./stress-$c -l)`; a category whose binary is missing or prints nothing is noted in `soak.out` (`soak: skip <cat>`) and left out; an empty pool exits 2 with a message (Review Focus 2).
  - Random picks from a seeded awk LCG (`seed = (seed * 1103515245 + 12345) % 2147483648`), state kept in a shell variable; each pick also gets its own `-s` from the generator so a run replays.
  - Slots: start up to `-j` background jobs; loop with `wait` on the oldest pid (POSIX sh has no `wait -n`), refilling until `-t` has passed (use `date +%s` if it prints digits on the guest; otherwise count launched jobs and stop when `launched * T / j >= t`, commented as the approximation it is).
  - Each job: `(cd $here/$cat && ./stress-$cat $L -t $T -s $s -d $dir $test) >>$rep/soak.out 2>/dev/null`.
  - Summary as `run` builds it, into `soak.summary`, then `cat` it.
  - In `ffsbench.py`: `--soak SECS` on the `stress` subcommand uses `stress_soak_command` instead of `stress_run_command`; the poll/fetch/report code is shared.
- [ ] **Step 4:** pytest passes. On the dev guest: `./soak -t 120 -j 2 -T 20` exits 0, `Report/soak.out` starts with `soak: seed=`, has `STRESS` lines from at least 3 categories, and `soak.summary` exists. `./soak -t 60 bogus` exits 2.
- [ ] **Step 5:** Commit `stress: add soak, a timed random mix of every category's tests; ffsbench stress --soak`.

### Task 5: `fs rename` and `fs link` (#45)

**Files:**
- Modify: `S/fs/fs.c`, `S/fs/runtests` (`tests=`), `S/Makefile` (`check-fs`)

**Interfaces:**
- Consumes: `st_path`, `st_set_cleanup`, `st_rng`.
- Produces: tests `rename` (def_iters 500) and `link` (def_iters 500), not solo; both share the tree `st_path(c, ..., "tree")`-style directory under `-d`, created by worker 0 and waited for by the others (follow how `tree` coordinates, or create it in a probe-free first-iteration step guarded by `mkdir` EEXIST).

- [ ] **Step 1: `check-fs` additions:** a run `$(FSBIN) -n 3 -i 100 -d /tmp rename link` must exit 0 with both PASS; `$(FSBIN) -x -i 20 -d /tmp rename link` must exit 1 with 2 FAIL lines. Add `rename link` to `fs/runtests` `tests=`.
- [ ] **Step 2:** `make check-fs` fails (unknown test).
- [ ] **Step 3: Implement.**
  - `rename`: 8 directories `d0..d7`; each worker owns ids `idx*1000000 + n`; a file's content is its id as 4 bytes (`st_fill` with key = id over 64 bytes). Ops chosen by `st_range`: move own file to a random dir under a new name; rename over another of its own files (the target's id is retired — record it); rename one of its own subdirectories `dN/wI.sub<k>` into another `dM` (never into itself). Concurrent reads of other workers' names: `open` → ENOENT is fine; else content must check out (`st_check` → `st_fail_data`). At the end worker 0, after the others finish (use the existing end-barrier pattern, or have each worker verify only its own ids), walks the tree: each live id exactly once. `-x`: corrupt one file's content before the final walk.
  - `link`: each worker creates files, adds 1-3 hard links in random dirs, removes random names, makes symlinks to its own files and checks `readlink`; it records names per file; at the end each surviving file's `st_nlink` equals its recorded name count, each symlink reads back. `-x`: record one name too many.
- [ ] **Step 4:** `make check-fs` passes on the dev guest. Run `./stress-fs -n 4 -i 2000 -d /mnt1 rename link` on the ffsbench hd1 (`mount` as in `vm/ffsbench.py MOUNT`) once and report the line.
- [ ] **Step 5:** Commit `stress: add fs rename and link churn tests (#45)`.

### Task 6: `proc pty`

**Files:**
- Modify: `S/proc/proc.c`, `S/proc/runtests`, `S/Makefile` (`check-proc`)

**Interfaces:**
- Produces: test `pty` (def_iters 50), probe `p_pty` (UNSUP `reason="no free pty"` if no `/dev/pty[p-s][0-9a-f]` opens; Review Focus 3).

- [ ] **Step 1: `check-proc`:** keep the count of the five old PASS lines and add `grep '^STRESS proc pty \(PASS\|UNSUP\) ' proc/t.out`; `-x -i 5 pty` must FAIL. Add `pty` to `proc/runtests`.
- [ ] **Step 2:** `make check-proc` fails.
- [ ] **Step 3: Implement.** Find a pty by trying masters `/dev/ptyXY` in order (X in `pqrs`, Y in `0-9a-f`), slave is the same name with `t` for `p`; retry up to 5 s when none free, then FAIL only if this worker holds any open pty, else `st_fail(c, "reason=\"no free pty\"")`. Child: `setsid()`, `ioctl(slave, TIOCSCTTY, 0)`, raw mode (`cfmakeraw` if present, else clear `ICANON|ECHO|OPOST|ICRNL` via `tcgetattr`/`tcsetattr`), echo loop until EOF. Worker writes a patterned 1-4 KB block, reads the echo, `st_check`s it; closes master and slave in an order chosen by `st_range`; reaps the child. End: reopen every master it used, then close. `-x`: flip one byte of the echo before the check.
- [ ] **Step 4:** `make check-proc` passes on the dev guest; `./stress-proc -n 4 -i 200 pty` PASS.
- [ ] **Step 5:** Commit `stress: add proc pty open/echo/close test`.

### Task 7: `net storm` and `net flood`

**Files:**
- Modify: `S/net/net.c`, `S/net/runtests` (add `storm` only), `S/Makefile` (`check-net`)

**Interfaces:**
- Produces: `storm` (def_iters 20, solo), `flood` (def_iters 1, solo, `named_only`, probe UNSUP `reason="needs STRESS_EXHAUST=1"` unless `getenv("STRESS_EXHAUST")` equals `"1"`).

- [ ] **Step 1: `check-net`:** default run includes `storm` PASS; `$(NETBIN) flood` without the env var prints `UNSUP reason="needs STRESS_EXHAUST=1"` and exits 0; `-x -i 2 storm` FAILs. Add `storm` to `net/runtests`.
- [ ] **Step 2:** `make check-net` fails.
- [ ] **Step 3: Implement.**
  - `storm`: loopback TCP listener, `listen(fd, 5)`; a forked client process opens 64 connections as fast as it can, even-numbered blocking, odd-numbered `O_NONBLOCK` with `connect` → EINPROGRESS → `select` for write (10 s cap) → `getsockopt(SO_ERROR)`. Allowed failures: ECONNREFUSED, ETIMEDOUT, ECONNRESET; anything else, or a `select` that times out, FAILs. The server accepts in a loop (non-blocking listener + `select`, 15 s overall cap) and for each connection exchanges a 64-byte patterned message both ways, keyed by connection number. Client reports its count of successful connects through a pipe; server's accepted count must equal it. `-x`: corrupt one message.
  - `flood`: create unix `socketpair`s and loopback TCP pairs alternately until `socket`/`socketpair`/`connect` fails (cap 4096 pairs); set every writer non-blocking and write patterned data until EWOULDBLOCK or ENOBUFS; then drain each reader and `st_check` everything written; close all; then a fresh TCP pair carries 64 KB and checks it. Any errno other than the expected ones FAILs. Record counts as `pairs=N bytes=N` via `st_op_end` units.
- [ ] **Step 4:** `make check-net` passes on the dev guest. `STRESS_EXHAUST=1 ./stress-net flood` run once on a throwaway snapshot guest; report its line and whether ssh still answers afterwards.
- [ ] **Step 5:** Commit `stress: add net storm and the opt-in flood exhaustion test`.

### Task 8: `misc eintr`

**Files:**
- Modify: `S/misc/misc.c`, `S/misc/runtests`, `S/Makefile` (`check-misc`)

**Interfaces:**
- Produces: test `eintr` (def_iters 20).

- [ ] **Step 1: `check-misc`:** count goes from 7 to 8 PASS/UNSUP; the `-x` run adds `eintr` and expects 3 FAILs. Add `eintr` to `misc/runtests`.
- [ ] **Step 2:** `make check-misc` fails.
- [ ] **Step 3: Implement.** For each iteration and each of the four calls, two rounds: handler for SIGALRM installed with `sigaction`, `sa_flags` 0 then `SA_RESTART`; `setitimer(ITIMER_REAL)` at 20 ms one-shot.
  - `read`: a child writes a numbered byte stream to a pipe in bursts with 50 ms pauses; the worker reads into a buffer; without restart a `-1/EINTR` or a short count is fine, with restart the call must not return EINTR; the concatenation of everything read must equal the stream exactly (sequence check; `-x` drops one byte).
  - `select` on the same pipe: without restart, `-1/EINTR` expected when the timer fires first; with restart BSD select still returns EINTR — accept EINTR in both rounds, but no other error.
  - `waitpid` on a child sleeping 100 ms: without restart EINTR or the pid; with restart only the pid.
  - `flock(LOCK_EX)` on a file a child holds for 100 ms: same rule as waitpid.
  - If the timer fired before the call blocked (handler count incremented before the call started), retry the round, up to 5 times, then skip it without failing (Review Focus 4).
- [ ] **Step 4:** `make check-misc` passes on the dev guest.
- [ ] **Step 5:** Commit `stress: add misc eintr, signals interrupting blocking calls`.

### Task 9: kernel `mmap` of `/dev/zero`

**Files:**
- Modify: `src/kernel-7/bsd/kern/kern_mman.c` (`mmap`)

**Interfaces:**
- Consumes: the `MAP_ANON` path from issue-43 (`flags & MAP_ANON` → `vm_map_find` → `goto mapped`).
- Produces: `mmap(..., fd of /dev/zero, ...)` behaves as `MAP_ANON` with the same `prot`/`MAP_SHARED`/`MAP_PRIVATE`/`MAP_FIXED`; offset ignored. Recognize the device by `major(vp->v_rdev)` having `cdevsw[major].d_open == mmopen` and `minor(vp->v_rdev) == 3`; check `mmopen`'s exact name in `src/kernel-7/bsd/dev/i386/mem.c` and `.../ppc/mem.c` (both must match the same open routine name, else compare both).

- [ ] **Step 1: Guest test program** (scratch, not committed) `zmap.c`: map `/dev/zero` (create the node first: `mknod /dev/zero c 3 3`) MAP_PRIVATE 4 pages at offset 0 and at offset 8192 → all zero, writable; two private mappings don't share; MAP_SHARED 1 page shared with a forked child; `MAP_FIXED` at the address of a just-unmapped anon region succeeds; mapping `/dev/null` still fails with EOPNOTSUPP (Review Focus 5).
- [ ] **Step 2:** On the stock v2 kernel, `zmap` fails at the first mapping (EOPNOTSUPP).
- [ ] **Step 3:** Implement: in the `VCHR` branch before `return(EOPNOTSUPP)`, if the device is `/dev/zero`, set `flags |= MAP_ANON` and jump into the anon path (move the anon block below the vnode lookup, or factor it into a label both reach — whichever keeps the diff smallest; do not leave `fp`/`UF_MAPPED` set for it).
- [ ] **Step 4:** Build the kernel as `vm/work/issue43/` did (rbuild kernel on a snapshot v2 guest; needs `drvPExpert` and `driverTools-1` shipped beside `kernel-7` and `driverkit-*.apk` linked into the private repo); boot it; `zmap` passes; the issue-43 test `vm/work/issue43/i43b.c` still passes. Keep the kernel at `vm/work/stress-phase3/mach_kernel` for Task 11.
- [ ] **Step 5:** Commit `kernel: mmap of /dev/zero gives anonymous memory`.

### Task 10: #43 follow-ups in `mmap` and `vm`; `/dev/zero` on harness guests

**Files:**
- Modify: `S/mmap/mmap.c`, `S/mmap/runtests`, `S/vm/vm.c`, `S/Makefile` (`check-mmap`, `check-vm`), `vm/stress_dev.py` (`up`), `vm/ffsbench.py` (stress setup), `vm/test_ffsbench.py`

**Interfaces:**
- Consumes: syscalls 177/178; Task 9 kernel.
- Produces: tests `anonshared` (def_iters 100) and `zero` (def_iters 100, probe `p_zero`); `ffsbench.DEVZERO` = `"test -c /dev/zero || (mknod /dev/zero c 3 3 && chmod 666 /dev/zero)"`, run right after login in both `stress()` and `stress_dev.up()`.

- [ ] **Step 1: Host test** `test_devzero_command`: `DEVZERO` contains `mknod /dev/zero c 3 3` and starts with `test -c /dev/zero`. **`check-mmap`:** accept `anonshared` and `zero` as PASS or UNSUP; the `-x` run adds `anonshared zero` and expects 5 FAILs at an offset. **`check-vm`:** unchanged lines; wire stays `PASS|UNSUP`. Add `anonshared zero` to `mmap/runtests`.
- [ ] **Step 2:** pytest and `make check-mmap` fail.
- [ ] **Step 3: Implement.**
  - `t_anon`: after `st_fill`, `mincore(p, ANONSIZE, vec)` → every byte nonzero, `madvise(p, ANONSIZE, MADV_NORMAL..MADV_DONTNEED)` each 0, `madvise(..., 99)` → EINVAL. `mincore`/`madvise` stubs exist in Libc; declare `mincore` if the guest's `<sys/mman.h>` lacks it.
  - `anonshared`: MAP_SHARED|MAP_ANON region of `ANONSIZE`; fork; parent fills the first half, child the second, each waits on a pipe handshake then checks the other's half; child exits with status; `-x` corrupts the parent's view of one byte before its check.
  - `zero`: `p_zero` returns UNSUP when `/dev/zero` is absent (`stat` fails or not `S_ISCHR`) or a one-page mapping fails with EOPNOTSUPP/ENODEV/EINVAL. Body: `read` 64 KB → all zero; `write` 64 KB → returns 64 KB; MAP_PRIVATE map, check zero, fill, a second private map of the same fd still zero; MAP_SHARED map shared with a forked child as in `anonshared`.
  - `vm.c` `bindwire`: when dyld lacks `_mlock`, use `syscall(177, p, len)` / `syscall(178, p, len)` through two small static wrappers; in `p_wire`, ignore SIGSYS around the probe call (`signal(SIGSYS, SIG_IGN)` then restore) so an old kernel reports `mlock: ENOSYS`-style UNSUP instead of dying.
  - Update the `p_anon` comment ("this kernel refuses MAP_ANON") to say older kernels refuse it.
- [ ] **Step 4:** pytest passes; on the dev guest booted with Task 9's kernel (`python vm/stress_dev.py up --kernel vm/work/stress-phase3/mach_kernel`): `make check-mmap` and `make check-vm` pass with `anon`, `anonshared`, `zero` and `wire` all PASS. On the stock kernel they pass with those UNSUP.
- [ ] **Step 5:** Commit `stress: cover mincore, madvise, shared anon memory and /dev/zero mappings; wire falls back to syscalls 177/178`.

### Task 11: README and acceptance

**Files:**
- Modify: `S/README`
- Create: `vm/work/stress-suite-evidence/phase3/` (outside git; results only)

- [ ] **Step 1:** README: document `-l`, `-L`/`STRESS_LEAK=fail`, the `leak=`/`wired=`/`mbufs=` fields, `soak` and its options, `STRESS_EXHAUST=1`, and each new test in its category's table.
- [ ] **Step 2: Acceptance on the dev guest with Task 9's kernel:** `make check check-vm check-mmap check-fs check-proc check-net check-ipc check-thread check-misc`; `./run 1`; `./soak -t 600 -j 4`; on a separate throwaway snapshot guest `STRESS_EXHAUST=1 ./net/stress-net flood`. Save every output under the evidence directory. Failures traced to filed kernel issues (#41, #46, #47) are expected; anything else is reported, and a new kernel bug gets a GitHub issue draft in the report (not filed).
- [ ] **Step 3:** Host: `python -m pytest vm/test_ffsbench.py` passes.
- [ ] **Step 4:** Commit `stress: document phase 3 tests, leak report and soak`.
