# Stress suite phase 3 design

## Purpose

Phase 3 extends the stress suite from phases 1 and 2
(`2026-10-13-stress-suite-design.md`, `2026-10-14-stress-suite-phase2-design.md`)
toward the bugs this kernel has actually shown: rename/vnode panics (#45), slow
kernel leaks, failures that only appear under mixed load, pty trouble behind
sshd, network resource exhaustion, and signal/syscall races. It also follows up
#43 (`MAP_ANON`, `mlock`, `msync`, `madvise`, `mincore`) and adds `mmap` of
`/dev/zero`.

The goal is unchanged: find kernel stability bugs, measure kernel performance,
and let the QEMU harness compare kernels.

## Base

Branch `stress-phase3`, cut from `issue-43` (ffs-perf plus the #43 kernel work).
Items under "#43 follow-ups" need that kernel.

Everything in phases 1 and 2 applies unchanged:
- **Result lines:** the grammar, and the `worker=`/`iter=`/`seed=` fields on FAIL lines.
- **Self-check and timing:** the `-x` self-check, `ops`/`maxlat` timing, and the watchdog.
- **Test table:** `name`, `def_iters`, `solo`, `probe`, `body`, `named_only`; UNSUP only for a refused or missing feature.
- **Cleanup:** scratch files under `-d/stress.<cat>.*`, `st_set_cleanup`, `st_readfull`/`st_writefull`.
- **Packaging and harness:** `run`, `Report/`, `ffsbench stress`, `stress_report.py`.

## Success criteria

- **Healthy kernel:** `run 1` finishes with every test PASS or UNSUP and exits 0, apart from failures traced to filed kernel issues.
- **Every new data test:** the hidden `-x` mode makes it FAIL.
- **Leak check:** every result line from a test that grew a zone, wired pages or mbufs past the threshold carries `leak=`; nothing fails because of it unless `-L` is given.
- **Soak:** `soak -t 600 -j 4` on the dev guest runs tests from every default category, writes `Report/soak.out` and a summary, and exits 0 on a healthy kernel.
- **Exhaustion:** `STRESS_EXHAUST=1 stress-net flood` either PASSes or fails with a FAIL line; the guest is usable afterwards (or the failure is filed as a kernel issue).
- **Harness:** `ffsbench stress` runs the new tests and reports them in `result.txt`.

## Library changes

- **`-l`:** every binary prints the names of the tests a default run would run (no `named_only` ones), one per line, and exits 0. `soak` uses it.
- **Leak snapshot:** `st_leak_snap(struct st_leak *)` and `st_leak_diff(const struct st_leak *before, const struct st_leak *after, char *out, int len)` in a new `lib/leak.c`.
  - A snapshot holds the element count of every zone (`host_zone_info`), the wired page count (`vm_statistics`), and the mbufs in use (the same counters `netstat -m` reads).
  - The leader snapshots after its probe and again after reaping its workers, then appends the diff to the result line: `leak=<zone>:+N,<zone>:+N wired=+N mbufs=+N`, listing only growth past the threshold and at most the top 3 zones.
  - Thresholds: a zone grows by more than 64 elements and by more than 10% of its starting count; wired pages grow by more than 32; mbufs grow by more than 64. These are starting values to tune.
  - A snapshot call that fails leaves the fields off; it never fails a test.
  - `-L` (or `STRESS_LEAK=fail` in the environment) turns a reported leak into a FAIL with `reason=leak`.
- **`run`:** after the summary, it lists every result line that carries `leak=` under a `leaks:` heading in `Report/summary`. It passes `-L` through when given.

## stress-fs (#45)

| test | does | catches |
|---|---|---|
| rename | a shared tree of 8 directories; each file holds a unique id in its content; workers rename files between directories (also over an existing name), and rename directories into other directories that are not their descendants; any read mid-run sees ENOENT or a file whose content matches its id; at the end each id exists exactly once | rename races, lost or duplicated files, vnode panics |
| link | workers `link`, `unlink`, `symlink` and `readlink` in the shared tree; each worker keeps its own record of names it created; at the end every surviving file's `st_nlink` equals the number of directory entries naming it, and every symlink reads back its target | link count corruption, symlink races |

## stress-proc

| test | does | catches |
|---|---|---|
| pty | each worker takes a free BSD pty pair (`/dev/pty[p-s][0-9a-f]` with its `/dev/tty..` slave); a forked child calls `setsid`, makes the slave its controlling tty with `TIOCSCTTY`, and echoes what it reads; the worker checks patterned data both ways, then closes master and slave in varying order; at the end every pty a worker used can be opened again | pty leaks, data loss, session/ctty bugs |

No free pty at the start of an iteration is a FAIL only if the worker's own
ptys are not all closed; otherwise it retries for up to 5 s.

## stress-net

| test | does | catches |
|---|---|---|
| storm | a listener with a backlog of 5 receives 64 connections at once, half blocking and half non-blocking (`connect` then `select` for writability); every accepted connection exchanges a short patterned message; every connect that fails must fail with ECONNREFUSED, ETIMEDOUT or EINPROGRESS-then-error, never hang | listen queue overflow, half-open connection leaks |
| flood | **named_only, needs `STRESS_EXHAUST=1`**: opens unix and TCP socket pairs until the system refuses, fills each with patterned data until EWOULDBLOCK or ENOBUFS, then drains and checks every byte; finally a fresh TCP connection must carry 64 KB intact | mbuf exhaustion and recovery |

Without `STRESS_EXHAUST=1`, naming `flood` reports UNSUP with
`reason="needs STRESS_EXHAUST=1"`.

## stress-misc

| test | does | catches |
|---|---|---|
| eintr | `setitimer(ITIMER_REAL)` interrupts four blocking calls: `read` on a pipe a child feeds slowly, `select` on that pipe, `waitpid` on a sleeping child, and `flock` on a file a child holds; each round runs once with `SA_RESTART` and once without; without it the call returns EINTR or a correct short count, with it the call completes; across the whole run the bytes read equal the bytes written, in order | lost or duplicated data on EINTR, restart bugs |

## #43 follow-ups and /dev/zero

- **Kernel, `kern_mman.c`:** `mmap` of the `mem` driver's minor 3 (`/dev/zero`) is handled as `MAP_ANON`: zero-fill, copy-on-write for MAP_PRIVATE, shared for MAP_SHARED. The device is recognized by its `cdevsw` open routine and minor, not by path. Every other character device still gets EOPNOTSUPP.
- **`stress-mmap anon`:** after filling, `mincore` must report every page resident and `madvise(MADV_NORMAL..MADV_DONTNEED)` must succeed; an out-of-range hint must be EINVAL.
- **`stress-mmap anonshared`:** new; a MAP_SHARED anonymous mapping that parent and child write in alternating, patterned halves, each checking the other's half.
- **`stress-mmap zero`:** new; reads from `/dev/zero` return zeros, writes succeed; a MAP_PRIVATE mapping is zero and writable without changing a second mapping; a MAP_SHARED mapping is shared with a forked child. Probe: no `/dev/zero` node, or EOPNOTSUPP from the mapping, is UNSUP.
- **`stress-vm wire`:** if dyld finds no `_mlock`, the test calls syscalls 177 (`mlock`) and 178 (`munlock`) directly through `syscall()`; ENOSYS or a SIGSYS-killed probe is still UNSUP.
- **Guest setup:** `stress_dev.py up` and `ffsbench`'s guest setup run `mknod /dev/zero c 3 3; chmod 666 /dev/zero` when the node is missing. Snapshot guests only; no image is written.

## soak

A new script, `soak [-t total-secs] [-j slots] [-T test-secs] [-s seed] [-d dir] [cat ...]`.

- **Defaults:** `-t 3600`, `-j 4`, `-T 60`, categories `vm mmap fs proc net ipc thread misc` (never `disk`).
- **Pool:** for each category, `stress-<cat> -l` lists its tests.
- **Loop:** until the total time runs out, it keeps `-j` slots busy. Each slot picks a random `cat test` pair from the seeded pool and runs `stress-<cat> -t <test-secs> -s <seed> -d <dir> <test>`, appending its output to `Report/soak.out`.
- **Randomness:** a small awk-based generator seeded from `-s` (default: the time), logged as the first line of `soak.out`, so a run can be replayed.
- **Summary:** per-category PASS/FAIL/UNSUP counts, the FAIL lines, and the `leaks:` section, in `Report/soak.summary`; exit 1 if any FAIL.
- **Harness:** `ffsbench stress --soak SECS` runs it and reports like `run`.

## Testing

- **Host:** `vm/test_ffsbench.py` gains tests for `--soak` and for `stress_report.py` parsing `leak=` fields; `lib/t_lib.c` gains tests for `st_leak_diff` (threshold, top-3 ordering, no output when below).
- **Self-check:** each new data test (rename, link, pty, storm, flood, eintr, anonshared, zero) FAILs under `-x`.
- **Acceptance on the dev guest:** `make check`, each new test by name, `soak -t 600 -j 4`, and `STRESS_EXHAUST=1 stress-net flood`. Results kept under `vm/work/stress-suite-evidence/phase3/`.

## Out of scope

- `disk` in soak; NFS; `ptrace`.
- Failing on leaks by default (needs thresholds tuned on real runs first).
- A per-process `RLIMIT_MEMLOCK` for `mlock` (kernel has no per-pmap wired count).
