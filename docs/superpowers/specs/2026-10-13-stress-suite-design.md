# Stress suite (phase 1) design

## Purpose

A system stress suite for RhapsodiOS, modelled on the layout and test ideas of
IRIX 6.5's `irix/cmd/stress`, to find kernel stability bugs and measure kernel
performance regressions. It ships as an OS package, runnable on any machine,
and the QEMU bench harness (`vm/ffsbench.py`) drives it under host load to
compare kernels.

The IRIX sources carry SGI proprietary notices. Nothing is copied from them:
the structure (per-category programs, `runtests`, `run`, `Report/`) and the
kinds of tests are the model; every line is written fresh.

## Phases

- **Phase 1 (this spec):** framework, `vm`, `mmap`, `fs`, `proc`, `net`.
- Phase 2: System V IPC (if the kernel has it), more socket and fd-passing depth.
- Phase 3: cthreads (IRIX `Sproc`), misc services (locks, timers, rlimits), raw
  disk I/O.

Each later phase gets its own spec.

## Success criteria

- `run 1` on a healthy kernel finishes with every test PASS or UNSUP and exits 0.
- A known-bad kernel fails in a reproducible way. Two regressions fixed this
  month must be caught: MapFS write/map incoherency (fixed in 7ed3069ab) and the
  dyld signal dead lock (fixed in 733bbd587, caught when run on the old dyld).
- Every FAIL line carries enough to replay it: category, test, seed, iteration,
  and for data failures the file or address, offset, expected and actual bytes.
- Every PASS line carries a rate (`ops/s`) and worst latency (`maxlat`), so two
  kernels can be compared from their reports.
- `ffsbench stress` runs the suite in a bench guest and writes a parsable result.

## Layout and packaging

`src/Commands/stress/`, a plain-Makefile project (like `apk-tools-1`) with
`apk/pkginfo` (`pkgname = stress`, `makedepends = build-base`). Installs to
`/usr/local/stress`:

```
lib/                 libstress.a (not installed)
vm/   stress-vm      + runtests
mmap/ stress-mmap    + runtests
fs/   stress-fs      + runtests
proc/ stress-proc    + runtests, plus stress-exec-child (exec target)
net/  stress-net     + runtests
run                  top-level runner
README
```

Builds with the repo toolchain for i386 and ppc; no code is architecture
specific. Page size comes from `getpagesize()` (8 KB on this system), never a
constant.

## libstress

One small static library shared by the five binaries:

- **Options:** `-n procs`, `-i iters`, `-t secs` (per-test time limit),
  `-s seed`, `-d dir` (scratch directory, default `/tmp`), `-m size` (memory
  target where relevant), `-v`. Unknown options are an error.
- **Seeding:** one seed per run (from time and pid unless `-s`), printed first;
  each child derives its own stream from (seed, test, child index), so a run
  replays exactly given the seed.
- **Patterns:** `fill(buf, len, key, off)` and `check(...)` produce bytes that
  depend on a key (seed, file or region id) and the absolute offset, so any
  byte can be recomputed. `check` reports the first mismatching offset and up
  to 16 expected and actual bytes.
- **Timing:** monotonic enough wall clock from `gettimeofday`; `op_begin()` /
  `op_end()` track operation count and the slowest single operation.
- **Supervision:** each test runs in a forked child; the parent waits with a
  watchdog (`-t`, default 600 s). Death by signal, nonzero exit, or timeout is a
  FAIL with the reason. Child processes the test spawns are killed with it.
- **Reporting:** exactly one result line per test on stdout:

```
STRESS <cat> <test> PASS  iters=N procs=N secs=S ops=R/s maxlat=Lms seed=X
STRESS <cat> <test> FAIL  <reason fields> seed=X
STRESS <cat> <test> UNSUP reason="<call>: <errno name>"
```

  Field values never contain spaces except inside quotes. Diagnostics go to
  stderr. A binary's exit status is 1 if any test failed, else 0.
- **UNSUP rule:** a test reports UNSUP only when the kernel refuses the
  feature (ENOSYS, EOPNOTSUPP, EPROTONOSUPPORT, or a stubbed call), checked
  once up front; errors after that are FAIL.

## Binaries and tests

`stress-<cat> [options] [test ...]` runs the named tests, or all of them in the
order below. `-n` processes run each test concurrently unless noted.

### stress-vm

| test | does | catches |
|---|---|---|
| pressure | each process takes its share of `-m` (default 1.5x physical memory), fills it, re-reads in random order | page-out/page-in loss, free-page reuse while referenced |
| cow | parent fills memory, forks generations of children that rewrite random pages and check untouched ones; parent rechecks its copy | copy-on-write and shadow-object bugs |
| machvm | `vm_allocate` / `vm_copy` / `vm_protect` / `vm_deallocate` churn with content checks after `vm_copy` | Mach VM object bugs |
| brk | malloc/realloc/free storms, each block patterned and checked on free | heap and sbrk interaction with VM |
| wire | `mlock`/`munlock` of patterned buffers while `pressure` runs alongside | wiring under memory pressure (UNSUP if refused) |

### stress-mmap

| test | does | catches |
|---|---|---|
| shared | processes `MAP_SHARED` one file, write disjoint patterned regions, verify others' regions through the map and through `read()` | shared mapping coherency |
| mixed | `write()` then read through a map, and map-write then `read()`, across processes | MapFS / buffer cache incoherency |
| private | `MAP_PRIVATE` writes must not reach the file or other processes | private COW of file pages |
| trunc | `ftruncate` shrink and regrow while mapped; past-EOF access must SIGBUS, data before EOF must survive | truncate vs mapped pages |
| anon | anonymous mappings with `mprotect`; expected faults arrive as SIGSEGV | protection handling |
| sync | `msync` and data reaching the file | UNSUP while msync is stubbed |

### stress-fs

All files live under `-d`, so the same tests run on hd1 or the root.

| test | does | catches |
|---|---|---|
| rw | create, random-offset/size writes, read back, delete; many files per process | block mapping and allocation errors |
| append | concurrent appenders write checksummed lines; final file verified | NUL holes, lost appends |
| tree | mkdir/rmdir/rename storms in a shared tree, then a readdir+stat consistency walk | directory and namei bugs |
| fill | fill to ENOSPC, verify everything written, free, repeat | allocator boundary bugs |
| fsync | write, fsync, read back through another descriptor | sync and buffer cache ordering |

### stress-proc

| test | does | catches |
|---|---|---|
| fork | fork/exit/wait storms checking every exit status | process table and wait bookkeeping |
| exec | fork + exec of `stress-exec-child` (dynamically linked) | exec, dyld, teardown |
| signal | timers and peers flood a process that spends its time in dyld calls (`NSIsSymbolNameDefined`) while its handlers call libc and dyld too; delivered counts checked | signal delivery, dyld re-entry |
| stack | deep recursion, then syscalls from the deepest frame | stack growth (IRIX Pigs) |
| pipe | pipeline chains carry patterned data, verified at the end | pipe buffering and wakeups |

### stress-net

| test | does | catches |
|---|---|---|
| tcp | many loopback TCP connections send patterned streams in random-sized writes; receiver verifies every byte | TCP data corruption (IRIX DV) |
| udp | datagrams with sequence numbers and checksums; loss counted, corruption FAIL | UDP and mbuf corruption |
| unix | as tcp over AF_UNIX stream and `socketpair` | UNIX-domain sockets |
| select | one process serves many sockets with `select`; checks missed wakeups, cross-talk, early timeouts | select and wakeup races |
| accept | connect/accept/close storms; descriptor count checked after | fd and socket leaks |
| fdpass | pass descriptors with `sendmsg` access rights; receiver checks it got the right file | fd passing (UNSUP if refused) |

Every test counts its unit of work for `ops/s`: pages touched, bytes moved,
forks, connections.

## Runners

- **`<cat>/runtests <cycles>`:** per cycle, runs each test alone, then all of
  the category's tests at once; prints result lines; exits nonzero on any FAIL.
- **`run [-a] [-s seed] [-t secs] <cycles> [cat ...]`:** runs each category's
  `runtests` in turn, or all at once with `-a`; output to `Report/<cat>.out`;
  then writes `Report/summary` (counts of PASS/FAIL/UNSUP per category and each
  FAIL line) and exits nonzero on any FAIL. Core files found are moved into
  `Report/cores/` and noted.
- Scripts are plain `/bin/sh` (the system shell), no bash or ksh features.

## ffsbench integration

A `stress` mode in `vm/ffsbench.py`, alongside `stall`:

1. Boot a lane guest (optionally `--kernel`), with the usual burners if set.
2. Push the stress tree (from a built apk or a host directory) to the guest.
3. Run `run -a <cycles>` with `-d` on hd1, under the harness's time limit.
4. Collect `Report/` and the serial log into the run directory.
5. Write `result.txt`: per-category PASS/FAIL/UNSUP counts, every FAIL line,
   and per-test `ops/s` and `maxlat`, as JSON like the other modes.

A small compare helper prints two result files side by side with rate changes,
so a kernel change shows which areas got faster or slower.

## Error handling

- Setup failures (cannot create scratch files, fork fails at start) are FAIL
  with the reason, never silent skips.
- Tests clean up their scratch files and children on PASS and FAIL; a killed
  run leaves files only under `-d/stress.*`, which `run` removes at start.
- Expected faults (SIGBUS past EOF, SIGSEGV on protected pages) are caught with
  handlers and counted; an unexpected signal is a FAIL.

## Testing the suite

- Each test gets a self-check mode where the code that verifies data is
  exercised against a deliberately corrupted buffer and must report FAIL with
  the right offset (`-x` hidden option, used by the suite's own tests).
- On the v2 image: `run 1` passes on the current kernel.
- Regression proof: `stress-mmap mixed` fails on a kernel without 7ed3069ab,
  and `stress-proc signal` fails when run with the old dyld
  (`/usr/lib/dyld.cctools-266`).
