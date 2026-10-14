# Open POSIX test suite design

## Purpose

Port the Open POSIX Test Suite 1.5.2 (posixtestsuite-1.5.2.tar.gz from
sourceforge.net/projects/posixtest, sha256
`15a2185672127cba851d35ec9d538ff6148defdbb75f99c7e9c50aeba0f94757`) to
RhapsodiOS as part of testing the BSD subsystem. It ships as an OS package,
like the stress suite (`src/Commands/stress`), and a dev-guest driver runs it
on a v2 snapshot guest.

The suite gives two things:

- a **conformance map**: which POSIX interfaces build, link and pass here;
- a **regression check**: a checked-in baseline of expected results, so a
  kernel or Libc change that breaks a passing test is caught.

The suite is GPLv2, like bash and gnutar already in `src/`.

## What the suite meets here

The 1.5.2 tree holds 2146 conformance tests, 1979 in C and 167 in sh
(`conformance/interfaces`,
`definitions`, `behavior`), plus `functional/` and `stress/`. RhapsodiOS has
no `pthread.h`, `semaphore.h`, `mqueue.h`, `aio.h` or userland `sched.h`
(Libc has cthreads only), and no `timer_*`, `clock_*` or `sigqueue`. 974 of the
C tests include none of those headers; the rest are expected to fail
to build. A test that does not build is a result, not an error: the whole
suite is imported and every test is recorded.

The upstream runner does not work as shipped:

- its Makefile needs `$(call)`, which GNU Make 3.74 on the guest lacks;
- its timeout helper `t0.c` includes `pthread.h`, and arms `alarm` in the
  test's own process, so any test that catches SIGALRM defeats it;
- it builds with `-Werror -std=gnu99`, which turns every warning from the old
  headers into a build failure.

So upstream stays byte-for-byte and the runner is ours.

## Scope

- **Phase 1 (this spec):** import, package, runner, timeout helper, baseline,
  dev-guest driver, conformance tests only.
- Not run: `functional/` and `stress/`. They are imported but each has its own
  Makefile and `run.sh`, and all except `stress/signals` are built on threads,
  message queues, semaphores or timers. They get wired in once those APIs
  exist.
- Not in scope: fixing the failures the suite finds. Real FAILs in interfaces
  the system has are listed as follow-up bugs.

## Branch

The work branches off `ffs-perf`, because `vm/posix_dev.py` reuses
`vm/ffsbench.py` and follows `vm/stress_dev.py`, which exist only there.

## Layout and packaging

`src/Commands/posixtestsuite-1/`:

```
Makefile          plain make, GNU Make 3.74 safe: builds ptimeout, installs
apk/pkginfo       pkgname = posixtestsuite, pkgver = 1.5.2, license = GPL,
                  makedepends = build-base
posixtestsuite/   upstream 1.5.2, unmodified
run               the runner, plain /bin/sh
ptimeout.c        the timeout helper
baseline          expected result per test on the current kernel
t/                runner self-test fixtures (not part of upstream)
README            running, result meanings, updating the baseline
```

`make install` installs to `$(DSTROOT)/usr/local/posixtestsuite`: the
upstream tree, `run`, `ptimeout`, `baseline` and `README`. No test is compiled
at package time; the package needs `cc` (build-base) where it runs.

## The runner

```
run [-t secs] [-d dir] [-r root] [-b baseline] [-u] [path ...]
```

- `-t` per-test timeout, default 240 s (upstream's value).
- `-d` directory holding the scratch directory `posix.<pid>`, default `/tmp`;
  only that subdirectory is removed, on exit or on a signal.
- `-r` suite root and `-b` baseline file, for the fixture tests in `t/`.
- `-u` merges this run's results into `baseline` instead of comparing: tests
  not run keep their entry and `FLAKY` marks survive. The merge is written to
  `Report/baseline.new`, which `posix_dev.py baseline` copies.
- `path` limits the run to tests under those directories, relative to the
  suite root; the default is `conformance`.

Tests are found with upstream's naming (`N-N.c`, `N-N.sh`, `N-buildonly.c`,
as in `locate-test`) and run in sorted path order.

Per `.c` test, in its own work directory, which is also its cwd:

1. Compile: `cc -O -Wall -D_POSIX_C_SOURCE=200112L -I<suite>/include -c`.
   Failure is `BUILD-FAIL`.
2. If `nm -g` shows no `_main` (Mach-O names carry an underscore) or the name
   contains `-buildonly`, the result is `BUILD-ONLY`.
3. Link: `cc -o`. Failure is `LINK-FAIL`.
4. Run under `ptimeout`. Exit status maps as upstream's `posixtest.h`:
   0 `PASS`, 1 `FAIL`, 2 `UNRESOLVED`, 4 `UNSUPPORTED`, 5 `UNTESTED`.
   A timeout is `HUNG`, death by signal n is `SIGNAL=n`, any other status n
   is `EXIT=n`.

A `.sh` test runs as `ptimeout <secs> /bin/sh <test>`, exit 0 `PASS`, else
mapped the same way.

Output:

- one line per test on stdout and in `Report/results`:
  `POSIX conformance/interfaces/sigaction/1-1 PASS`
  Result fields contain no spaces.
- compiler, linker and test output in `Report/log/<path>.log`.
- `Report/summary`: counts per result; build failures counted per API family
  (the interface directory name up to its first `_`); then every
  **regression** (baseline `PASS`, now anything else), every **improvement**
  (now `PASS`, baseline something else), every other change, and every test
  not in the baseline, listed as **new**.

A baseline entry may be `FLAKY`; changes in such tests are never reported.

Exit status: 0 when there is no regression, 1 on any regression, 2 when the
run could not start (no `cc`, work directory not creatable, `baseline`
missing without `-u`, `-t` not a positive integer, a path that does not exist).

## The timeout helper

`ptimeout secs cmd [args]`: forks; the child calls `setpgid(0, 0)` and execs
the command; the parent sets `alarm(secs)` and waits. On SIGALRM it sends
SIGKILL to the child's process group and exits with a status the runner maps
to `HUNG`. After the child exits normally it also kills the process group, so
orphaned children cannot accumulate across the run. It passes the child's
exit status or signal through so the runner can tell them apart. No pthreads.

## Dev-guest driver

`vm/posix_dev.py` follows `vm/stress_dev.py` and imports `ffsbench` the same
way:

- `up [--kernel PATH]` boots a v2 snapshot guest named
  `RhapsodiOS posix-dev` on ports `2549,4549,1249` (ssh, QMP, gdb), overridable
  with `POSIX_DEV_PORTS`.
- `sync` tars `src/Commands/posixtestsuite-1` to `/tmp/posix-src` on the
  guest and runs `make install` there.
- `sh "<cmd>"` runs a `/bin/sh` command, exiting with its status.
- `run [args]` starts `run` detached on the guest (`nohup ... &`), so a long
  pass does not depend on one ssh session; checks every few minutes for
  `Report/summary`; then copies `Report/` to
  `vm/work/posix/<timestamp>/` and exits with the run's status.
- `baseline` copies the last run's `Report/results` over
  `src/Commands/posixtestsuite-1/baseline`, for review and commit.
- `down` quits through QMP after `query-name` returns this guest's name.

The guest is a snapshot: a restart loses `/tmp/posix-src`, so `sync` again.

## Updating the baseline

When an API lands or a bug is fixed, the run shows improvements. Run
`posix_dev.py baseline`, review the diff, commit it with a message naming the
kernel it came from. Tests seen to change result between runs on the same
kernel are marked `FLAKY` by hand.

## Safety

Tests run as root in the guest. The tree was checked for tests that change
system-wide state: only `clock_settime` sets the clock, and it cannot build
here. The `kill` and `sigqueue` tests call `setuid` only in their own process;
nothing calls `kill(-1, ...)`. The guest is a snapshot. No exclude list.

## Testing the suite

`make check` runs the runner against fixtures in `t/` (laid out like upstream,
`t/conformance/interfaces/<name>/N-N.c`) with `run -t 3 -d <tmp>` and a
fixture baseline, and greps each expected line:

| fixture | expected |
|---|---|
| exits 0, 1, 2, 4, 5 | `PASS`, `FAIL`, `UNRESOLVED`, `UNSUPPORTED`, `UNTESTED` |
| exits 7 | `EXIT=7` |
| syntax error | `BUILD-FAIL` |
| undefined symbol | `LINK-FAIL` |
| no `main` | `BUILD-ONLY` |
| raises SIGSEGV | `SIGNAL=11` |
| catches SIGALRM and loops | `HUNG` within the timeout |
| forks a child that sleeps, then exits 0 | `PASS`, and no leftover process in `ps` |
| `.sh` test exiting 0 | `PASS` |

Then the fixture baseline is varied: a regression makes `run` exit 1 and is
listed; an improvement alone exits 0 and is listed; a change in a `FLAKY` test
is not listed; a test missing from the baseline is listed as new and exits 0.

## Success criteria

1. `make check` passes on the v2 guest.
2. A full `posix_dev.py run` on the current kernel finishes with exactly one
   result line for each of the 2146 conformance tests; its results become the
   first committed `baseline`.
3. A second run on the same kernel exits 0, after any tests it shows as
   flaky are marked `FLAKY`.
4. `Report/summary` gives the conformance map, and real FAILs in interfaces
   the system has (signals, fork, mmap, time) are listed as follow-up bugs.
