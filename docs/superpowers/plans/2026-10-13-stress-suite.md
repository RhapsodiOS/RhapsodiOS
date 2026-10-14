# Stress Suite (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `src/Commands/stress`, an IRIX-style system stress suite (vm, mmap, fs, proc, net) that finds kernel bugs and records per-test rates, and drive it from `vm/ffsbench.py stress`.

**Architecture:** A static library `libstress.a` supervises tests (one forked leader per test, worker children, watchdog), seeds them, fills and checks recomputable patterns, times operations and prints one `STRESS` line per test. Five binaries (`stress-vm` … `stress-net`) are tables of tests over that library; `runtests` per category and a top-level `run` produce `Report/`. The QEMU harness pushes the source to a guest, builds it there, runs it under load and parses the report.

**Tech Stack:** C (gcc 2.7-era `cc` on the guest, K&R-tolerant ANSI C, no C99), GNU make 3.74, `/bin/sh` scripts, Python 3 + pytest on the Windows host for harness code.

**Spec:** `docs/superpowers/specs/2026-10-13-stress-suite-design.md`

## Global Constraints

- Nothing is copied from the IRIX sources; all code is new.
- C must build with the guest's `cc` for i386 and ppc: no C99 (`//` comments, mixed declarations, `long long` printf `%lld` is allowed), no `getopt_long`, no pthreads.
- Page size from `getpagesize()` (8 KB here), never a constant.
- Scripts are plain `/bin/sh`; no bash/ksh features. Root's login shell is tcsh, so harness commands go through `/bin/sh -c`.
- Plain Makefile (like `src/Commands/apk-tools-1/Makefile`), GNU make 3.74 features only (no `$(call)`, no target-specific variables). rbuild runs `make install` with `DSTROOT`, `SRCROOT`, `OBJROOT`, `SYMROOT`, `RC_CFLAGS`, `CC`.
- Installs to `$(DSTROOT)/usr/local/stress`; apk `pkgname = stress`, `pkgver = 1`, `makedepends = build-base`.
- Result line grammar, exactly:
  `STRESS <cat> <test> PASS iters=N procs=N secs=S.S ops=R/s maxlat=Lms seed=X`
  `STRESS <cat> <test> FAIL <field=value ...> seed=X`
  `STRESS <cat> <test> UNSUP reason="<call>: <ERRNAME>"`
  Values contain no spaces except inside double quotes.
- Binary exit status: 1 if any test FAILed, else 0. Diagnostics go to stderr.
- UNSUP only when the up-front probe gets ENOSYS, EOPNOTSUPP, EPROTONOSUPPORT, or the call is known stubbed (msync); later errors are FAIL.
- Commits: short, subsystem prefix (`stress:`, `ffsbench:`), no metadata, no Co-Authored-By.
- Never write `vm/golden.img`, `vm/work/rhap-i386-bootstrapped.img` or `rhapsody.vmdk`; guests boot `vm/work/rhap-i386-bootstrapped-v2.img` with snapshot only. Stop guests only via QMP after `query-name` matches.

## Review Focus

1. A test whose child forks past the process limit gets `EAGAIN`: it must FAIL with `reason="fork: EAGAIN"`, not hang or report PASS (Task 2).
2. A hung test that has spawned its own children: the watchdog must kill the whole group, leaving no stray processes (Task 2).
3. Same `-s` seed twice must give identical sizes/offsets, so a FAIL replays (Task 1).
4. `-d` pointing at a missing or unwritable directory must FAIL at setup with the errno, not crash (Task 5).
5. A run killed midway leaves `stress.*` files; the next `run` must remove them before starting (Task 8).

---

## File Structure

```
src/Commands/stress/
  Makefile               build lib + 5 binaries, check, install
  apk/pkginfo
  README                 usage and result format
  run                    top-level runner (sh)
  lib/stress.h           the whole library interface
  lib/rng.c              seeding, xorshift, mix
  lib/pattern.c          st_fill / st_check / st_fail_data
  lib/report.c           st_fail, st_errname, result line printing
  lib/main.c             stress_main: options, leader/workers, watchdog
  lib/sysinfo.c          st_physmem, st_unique_path
  lib/t_lib.c            make check: unit tests for rng/pattern/report
  lib/t_main.c           make check: demo binary exercising supervision
  vm/vm.c   vm/runtests
  mmap/mmap.c mmap/runtests
  fs/fs.c   fs/runtests
  proc/proc.c proc/child.c proc/runtests
  net/net.c net/runtests
vm/stress_dev.py         host helper: up / sync / sh / down a dev guest
vm/stress_report.py      host: parse STRESS lines, summarize, compare
vm/test_stress_report.py pytest for stress_report.py
vm/ffsbench.py           + stress mode
```

---

### Task 1: Project skeleton, dev guest helper, rng and patterns

**Files:**
- Create: `src/Commands/stress/Makefile`, `apk/pkginfo`, `lib/stress.h`, `lib/rng.c`, `lib/pattern.c`, `lib/report.c`, `lib/t_lib.c`
- Create: `vm/stress_dev.py`

**Interfaces:**
- Produces (in `lib/stress.h`):
  - `unsigned long st_mix(unsigned long x);` 32-bit integer hash: `x ^= x >> 16; x *= 0x7feb352dUL; x ^= x >> 15; x *= 0x846ca68bUL; x ^= x >> 16;` masked to 32 bits.
  - `struct st_rng { unsigned long s; };` `void st_rng_init(struct st_rng *, unsigned long seed, const char *test, int idx);` seeds with `st_mix(seed ^ st_strhash(test) ^ (idx * 0x9e3779b9UL))`, never 0. `unsigned long st_rand(struct st_rng *);` xorshift32 (13, 17, 5). `unsigned long st_range(struct st_rng *, unsigned long lo, unsigned long hi);` inclusive.
  - `unsigned long st_strhash(const char *);` FNV-1a 32-bit.
  - `void st_fill(void *buf, unsigned long len, unsigned long key, unsigned long off);` byte at absolute offset `o` is byte `(o & 3)` (little-endian order) of `st_mix(key ^ (o >> 2))`. Same on i386 and ppc.
  - `long st_check(const void *buf, unsigned long len, unsigned long key, unsigned long off);` returns index of first mismatch or -1.
  - `const char *st_errname(int err);` names for at least EPERM ENOENT EINTR EIO EBADF ECHILD EAGAIN ENOMEM EACCES EFAULT EEXIST ENOTDIR EISDIR EINVAL ENFILE EMFILE ENOSPC EPIPE ENOSYS EOPNOTSUPP EPROTONOSUPPORT EADDRINUSE ECONNREFUSED ECONNRESET ENOBUFS ETIMEDOUT; otherwise `"E<n>"` in a static buffer.
- `vm/stress_dev.py` CLI: `up` boots a v2 snapshot lane guest (ports from `STRESS_DEV_PORTS`, default `2548,4548,1248`, `-name "RhapsodiOS stress-dev"`) through `ffsbench.Guest`, waits for a real login, leaves it running; `sync` tars `src/Commands/stress` (LF line endings, `tarfile` USTAR) to `/tmp/stress-src` on the guest; `sh "<cmd>"` runs a `/bin/sh` command there and exits with its status; `down` QMP-quits after `query-name` matches.

- [ ] **Step 1: Write the failing unit test `lib/t_lib.c`**

`make check` builds and runs `t_lib`, which prints `t_lib: ok` and exits 0, or prints the failing assertion and exits 1. Assertions:
```c
CHECK(st_mix(0) == 0);                          /* the mix fixes 0; seeds avoid it */
CHECK(st_mix(1) != 1);
CHECK(st_strhash("") == 0x811c9dc5UL);
/* determinism: same seed/test/idx -> same stream; different idx -> different */
st_rng_init(&a, 1234, "cow", 0); st_rng_init(&b, 1234, "cow", 0); st_rng_init(&c, 1234, "cow", 1);
CHECK(st_rand(&a) == st_rand(&b)); CHECK(st_rand(&a) != st_rand(&c));
for (i = 0; i < 1000; i++) { v = st_range(&a, 5, 9); CHECK(v >= 5 && v <= 9); }
/* patterns: offset-addressable, unaligned windows agree with the whole */
st_fill(big, 4096, 77, 0); st_fill(win, 100, 77, 13);
CHECK(memcmp(big + 13, win, 100) == 0);
CHECK(st_check(big, 4096, 77, 0) == -1);
big[1234] ^= 0x40; CHECK(st_check(big, 4096, 77, 0) == 1234);
CHECK(st_check(big, 4096, 78, 0) == 0);          /* wrong key fails at once */
/* known vector pins the byte order for ppc too */
st_fill(win, 4, 0, 0); CHECK(win[0] == (st_mix(0) & 0xff));
CHECK(strcmp(st_errname(ENOSYS), "ENOSYS") == 0);
CHECK(strcmp(st_errname(9999), "E9999") == 0);
```

- [ ] **Step 2: Bring up the dev guest and see the test fail**

Run: `python vm/stress_dev.py up`, then `python vm/stress_dev.py sync`, then `python vm/stress_dev.py sh "cd /tmp/stress-src && make check"`
Expected: build fails (functions undefined).

- [ ] **Step 3: Implement `rng.c`, `pattern.c`, `st_errname` in `report.c`, and the Makefile**

Makefile targets: `all` (libstress.a and, as later tasks add them, the five binaries), `check` (builds and runs `lib/t_lib`, later also `lib/t_main`), `install` (empty until Task 8), `installhdrs:` (empty), `installsrc` (as apk-tools), `clean`. `CFLAGS = -O -Wall $(RC_CFLAGS) -Ilib`. Build objects next to sources (rbuild copies the source tree).

`apk/pkginfo`:
```
pkgname = stress
pkgver = 1
pkgdesc = System stress tests
maintainer = RhapsodiOS
license = APSL
makedepends = build-base
```

- [ ] **Step 4: Run the test**

Run: `python vm/stress_dev.py sync`, `python vm/stress_dev.py sh "cd /tmp/stress-src && make check"`
Expected: last line `t_lib: ok`, exit 0.

- [ ] **Step 5: Commit**

```
git add src/Commands/stress vm/stress_dev.py
git commit -m "stress: add the project skeleton, seeded rng and offset patterns"
```

---

### Task 2: Test supervision and result lines (`stress_main`)

**Files:**
- Create: `lib/main.c`, `lib/sysinfo.c`, `lib/t_main.c`
- Modify: `lib/stress.h`, `lib/report.c`, `Makefile` (check also runs `t_main` cases)

**Interfaces:**
- Consumes: Task 1's rng, `st_errname`.
- Produces:
```c
struct st_opts { int procs; long iters; int secs; unsigned long seed; const char *dir;
                 unsigned long mem; int verbose; int selfcheck; };
extern struct st_opts st_opt;           /* parsed once in stress_main */

struct st_ctx {
    const char *cat, *test;
    int idx, nprocs;                    /* worker index and count */
    long iters;                         /* -i, else the test's default */
    struct st_rng rng;
    int selfcheck;                      /* -x */
    /* private: op counters, result fd */
};

struct st_test {
    const char *name;
    long def_iters;
    int solo;                           /* 1: one worker; the test forks its own */
    int (*probe)(char *why, int len);   /* NULL, or nonzero + why when unsupported */
    void (*body)(struct st_ctx *);      /* returns = success; failures go via st_fail */
};

int  stress_main(int argc, char **argv, const char *cat, const struct st_test *tests);
void st_fail(struct st_ctx *, const char *fmt, ...);      /* noreturn: _exit(1) */
void st_fail_errno(struct st_ctx *, const char *call);     /* reason="call: ERRNAME" */
void st_fail_data(struct st_ctx *, const char *what, const unsigned char *got,
                  unsigned long len, unsigned long key, unsigned long off, long bad);
     /* fields: what=<what> off=0x<off+bad> want=<16 hex bytes> got=<16 hex bytes> */
void st_op_begin(struct st_ctx *);
void st_op_end(struct st_ctx *, unsigned long units);
int  st_more(struct st_ctx *, long i);                    /* i < iters */
unsigned long st_physmem(void);                           /* sysctl CTL_HW HW_PHYSMEM */
void st_path(struct st_ctx *, char *buf, int len, const char *tag);
     /* "<dir>/stress.<cat>.<test>.<tag>.<pid>" */
```
- Options: `-n procs` (default 4), `-i iters`, `-t secs` (watchdog, default 600), `-s seed` (default `time ^ pid`), `-d dir` (default `/tmp`), `-m bytes` (accepts `k`/`m` suffix), `-v`, `-x`. First output line on stderr: `stress-<cat>: seed=<X>`. Unknown option or unknown test name: usage to stderr, exit 2.

**Supervision (decided algorithm):** for each selected test in table order:
1. If `probe` says unsupported, print the UNSUP line and continue.
2. Fork a leader. The leader calls `setpgid(0,0)`, creates a pipe, forks `solo ? 1 : procs` workers (each gets `idx`, a seeded rng, the pipe's write end; on fork failure the leader reports `FAIL reason="fork: <ERR>"`), and waits for them all.
3. Workers run `body`, then write `STAT <units> <maxlat_us>` to the pipe and `_exit(0)`. `st_fail` writes `FAIL <fields>` and `_exit(1)`.
4. The leader reads all pipe lines. It prints the first FAIL; else, if a worker died by signal, `FAIL signal=<n> worker=<idx>`; else, a nonzero exit without a FAIL line, `FAIL exit=<n> worker=<idx>`; else the PASS line, with `ops` = summed units / elapsed seconds and `maxlat` = the max over workers. The leader exits 1 on FAIL.
5. The top-level process waits for the leader with the `-t` watchdog (an `alarm` and a wait loop). On expiry it `killpg(leader, SIGKILL)`, reaps, and prints `FAIL reason=timeout secs=<t>`.

- [ ] **Step 1: Write the failing check `lib/t_main.c`**

A `stress-tmain` binary with tests `pass` (counts 10 units), `fail` (`st_fail(c, "reason=planned")`), `crash` (raises SIGSEGV), `hang` (forks 3 sleeping children, then pauses), `unsup` (probe returns "msync: ENOSYS"), `data` (fills 64 bytes with key 5, flips byte 17, checks, calls `st_fail_data`), and `forkbomb` (solo; forks until EAGAIN, then `st_fail_errno(c, "fork")`). `make check` runs these and greps the output:
```
./stress-tmain -n 2 pass        -> line matches '^STRESS tmain pass PASS iters=.* procs=2 .*ops=.*maxlat=.*seed=', exit 0
./stress-tmain fail             -> 'STRESS tmain fail FAIL reason=planned seed=', exit 1
./stress-tmain crash            -> 'FAIL signal=11 worker=', exit 1
./stress-tmain -t 5 hang        -> 'FAIL reason=timeout secs=5'; afterwards `ps -ax | grep -c "[s]tress-tmain"` = 0
./stress-tmain unsup            -> 'STRESS tmain unsup UNSUP reason="msync: ENOSYS"', exit 0
./stress-tmain data             -> 'FAIL what=buf off=0x11 want=' 
./stress-tmain -s 42 pass; again -> both stderr lines 'seed=42'
./stress-tmain forkbomb         -> 'FAIL reason="fork: EAGAIN"' within 60 s
./stress-tmain bogus            -> exit 2
```
Print `t_main: ok` when all hold.

- [ ] **Step 2: Run it and see it fail**

Run: `python vm/stress_dev.py sync; python vm/stress_dev.py sh "cd /tmp/stress-src && make check"`
Expected: FAIL (stress_main undefined).

- [ ] **Step 3: Implement `main.c`, `sysinfo.c`, the rest of `report.c`**

- [ ] **Step 4: Run the checks**

Run: as Step 2.
Expected: `t_lib: ok` and `t_main: ok`.

- [ ] **Step 5: Commit**

`git commit -m "stress: supervise tests with a leader per test, a watchdog and one result line each"`

---

### Task 3: stress-vm

**Files:** Create `src/Commands/stress/vm/vm.c`, `vm/runtests`; modify `Makefile`.

**Interfaces:** Consumes Task 2's `st_test`/`st_ctx` API. Produces the binary `vm/stress-vm`.

Tests (defaults in parentheses are `def_iters`):
- `pressure` (3 passes): each worker takes `st_opt.mem / procs` bytes, or, when `-m` is unset, `st_physmem() * 3 / 2 / procs`. It allocates with `malloc`, fills each page with key `(seed, idx)` at offset `page index * pagesize`, then re-checks pages in `st_range` random order every pass. Units: pages touched.
- `cow` (solo, 20 generations): the parent fills 4 MB; each generation forks a child that rewrites 16 random pages with a new key, checks every page it did not rewrite, and exits; the parent waits, then rechecks all 4 MB with the original key. Units: pages checked.
- `machvm` (200): `vm_allocate(task_self(), &a, 256 KB, TRUE)`, fill, `vm_copy` into a second `vm_allocate`d region, check the copy, `vm_protect` it read-only, `vm_deallocate` both. Units: KB copied. Mach call failure: `st_fail(c, "reason=\"vm_copy: kr=%d\"", kr)`.
- `brk` (20000): random `malloc`/`realloc`/`free` over a table of 64 blocks of 16 B–64 KB; each block filled with key `(block id, generation)`; checked before realloc and free. Units: operations.
- `wire` (50): probe `mlock` of one page (EPERM, ENOSYS, EOPNOTSUPP → UNSUP); body: `mlock` 1 MB patterned, run a 1.5×-RAM malloc pass in a child, check, `munlock`. Units: MB wired.

`-x`: each test flips one byte of its data after filling and before checking, at an `st_range` offset, and must FAIL reporting that offset.

`vm/runtests [-s seed] [-t secs] [-n procs] cycles`: each cycle runs `./stress-vm <test>` for each test, then all tests at once in the background and `wait`s; prints all STRESS lines; exits 1 if any line contains ` FAIL `.

- [ ] **Step 1: Failing check** — add `check-vm` to the Makefile: runs `vm/stress-vm -n 2 -m 8m -i 1` (expects 4 PASS lines plus wire PASS or UNSUP, exit 0), then `vm/stress-vm -x -n 1 -m 4m -i 1 pressure cow machvm brk` (expects 4 FAIL lines with `off=`). Run via `stress_dev.py sh "cd /tmp/stress-src && make check-vm"`; expect failure.
- [ ] **Step 2: Implement `vm.c` and `vm/runtests`.**
- [ ] **Step 3: Run `make check-vm`.** Expected: as described, exit 0.
- [ ] **Step 4: Commit** `stress: add the vm tests (pressure, cow, Mach VM, heap, wiring)`

---

### Task 4: stress-mmap

**Files:** Create `mmap/mmap.c`, `mmap/runtests`; modify `Makefile` (`check-mmap`).

Each test uses a file from `st_path(c, ..., "map")` under `-d`, sized `16 * pagesize` unless noted.
- `shared` (50): the first worker creates the file; each worker `MAP_SHARED` maps it, writes its own region `[idx*R, (idx+1)*R)` with key `(seed, pass)` through the map, then checks the other workers' regions through the map and through `pread`/`lseek+read`. Page 0 is a counter page holding each worker's pass number; a worker checks the others' regions only once every counter has reached its own pass (barrier by polling with 10 ms sleeps, bounded by the watchdog). Units: pages verified.
- `mixed` (100): solo test, 2 processes. A writes patterned blocks with `write()` at random page offsets; B has the file mapped and checks each block through the map once A signals it over a pipe; then the roles reverse (B writes through the map, A reads with `read()`). Units: blocks verified.
- `private` (50): one worker writes the file with key K, maps it `MAP_PRIVATE`, rewrites half the pages with key K2 in memory; then `read()` must still return K, a second process's private map must show K, and the first map must show K2 on the rewritten pages.
- `trunc` (30): map 16 pages shared, fill, `ftruncate` to 5 pages, touch page 7 → SIGBUS expected (handler with `sigsetjmp`/`siglongjmp`); pages 0–4 still match; `ftruncate` back to 16 pages; the new pages read as zero. A missing SIGBUS is `FAIL reason=no-sigbus`.
- `anon` (200): `mmap(MAP_ANON|MAP_PRIVATE)` 64 KB, fill, `mprotect(PROT_READ)`, write → SIGSEGV expected (counted), `mprotect(PROT_READ|PROT_WRITE)`, check, `munmap`. Any other signal is FAIL.
- `sync` (20): probe calls `msync` on a one-page mapping; ENOSYS/EINVAL from the stub → UNSUP with reason `msync: <ERR>`. Body: write through the map, `msync`, read through a fresh descriptor, check.

`-x` behaviour as in Task 3. `mmap/runtests` like `vm/runtests`.

- [ ] **Step 1: Failing check** — `check-mmap`: `mmap/stress-mmap -n 3 -i 2 -d /tmp` gives PASS for shared mixed private trunc anon and `sync` PASS or UNSUP; `-x -i 1 shared mixed private` gives 3 FAIL lines with `off=`.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Run `make check-mmap`.**
- [ ] **Step 4: Commit** `stress: add the mmap tests (shared, mixed I/O, private, truncate, protect, msync)`

---

### Task 5: stress-fs

**Files:** Create `fs/fs.c`, `fs/runtests`; modify `Makefile` (`check-fs`).

Setup for every test: `mkdir` `<dir>/stress.fs.<test>.<pid>`. On failure it is `st_fail_errno(c, "mkdir")` (Review Focus 4). Everything is removed on return.
- `rw` (200 files per worker): create, then 1–32 writes of 1 B–64 KB at random offsets inside 1 MB, each with key `(seed, file)` at its absolute offset; read back the whole extent. Holes must read as zero; written ranges must match. Track written ranges in a bitmap per 512 B. Unlink. Units: bytes verified.
- `append` (2000 lines per worker): all workers open one file with `O_APPEND` and write 100-byte lines `"<idx> <seq> <16 hex of st_mix(idx,seq)> <padding>\n"`; afterwards worker 0 reads the file. Every line must be well formed and every `(idx, seq)` present exactly once. A NUL byte is `FAIL what=nul off=`. Units: lines.
- `tree` (500): workers churn `mkdir`/`rename`/`rmdir`/create/unlink in a shared 3-level tree of names `d<0-7>/d<0-7>/f<0-7>`, tolerating ENOENT/EEXIST/ENOTEMPTY races. Then worker 0 walks the tree with `opendir`/`readdir`/`stat`: every entry stats, `.` and `..` resolve, and no name appears twice. Units: operations.
- `fill` (2 rounds, solo): write 1 MB patterned files until ENOSPC (the file that hits ENOSPC is truncated to what was written), verify every file, delete all. Fail if ENOSPC never comes within `st_opt.mem` or 4 GB. Units: MB.
- `fsync` (200): write a block, `fsync`, read it through a second descriptor opened before the write, check. Units: blocks.

`-x`: rw corrupts one written byte via `pwrite`-equivalent (`lseek`+`write`) before verify; append writes one line with a bad checksum; fill corrupts one byte in one file. The rest must still PASS.

- [ ] **Step 1: Failing check** — `check-fs`: `fs/stress-fs -n 3 -i 20 -d /tmp` gives PASS for rw append tree fsync; `fs/stress-fs -d $STRESS_FILL_DIR fill` gives PASS, run only when `STRESS_FILL_DIR` names a scratch file system (the dev guest mounts hd1 at `/mnt1` for this); `fs/stress-fs -d /nonexistent rw` gives `FAIL reason="mkdir: ENOENT"`; `-x -i 5 rw append` gives 2 FAIL lines.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Run `make check-fs`.**
- [ ] **Step 4: Commit** `stress: add the filesystem tests (rw, append, tree, fill, fsync)`

---

### Task 6: stress-proc

**Files:** Create `proc/proc.c`, `proc/child.c` (builds `proc/stress-exec-child`), `proc/runtests`; modify `Makefile` (`check-proc`).

- `fork` (500 per worker): fork a child that `_exit(st_range(0,250))`; `waitpid` must return that pid and status. Units: forks.
- `exec` (200): fork + `execl` of `stress-exec-child` (located next to argv[0]) with an argument N. The child prints `st_mix(N)` in hex and exits `N & 0x7f`; the parent checks both. Units: execs.
- `signal` (solo, 5 s worth or `-i` loops of 20000): install handlers for SIGALRM and SIGUSR1; the handlers call `NSIsSymbolNameDefined("_printf")` and `getpid()`, and count. Arm `setitimer(ITIMER_REAL)` at 2 ms. Fork 2 children that `kill(parent, SIGUSR1)` 2000 times each with 1 ms sleeps. The main loop calls `NSIsSymbolNameDefined("_strlen")` repeatedly. Pass if the process survives, SIGUSR1 count ≥ 1 (signals coalesce) and SIGALRM count ≥ 50. With the 1998 dyld this dies with "dead lock" exit 68 → `FAIL exit=68`. Units: signals handled.
- `stack` (20): recurse to depth D = 2 MB / frame (each frame holds a 512-byte patterned array keyed by depth); at the bottom call `getpid`, `stat("/")`, `write` to a pipe; on unwind check each frame's array. Units: frames.
- `pipe` (50): a chain of 4 processes linked by pipes. The head writes 1 MB patterned in random-sized writes; the middle ones copy through; the tail checks. Units: bytes.

`-x`: pipe's head corrupts one byte; stack corrupts one frame; exec's child is passed a flag to print a wrong value; fork exits with a different status than chosen.

- [ ] **Step 1: Failing check** — `check-proc`: `proc/stress-proc -n 2 -i 50` gives 5 PASS lines; `-x -i 5 fork exec stack pipe` gives 4 FAIL lines; also the dyld regression: on a guest that still has `/usr/lib/dyld.cctools-266`, the check builds a copy of `stress-proc` whose LC_LOAD_DYLINKER is patched with `perl -pe 's|/usr/lib/dyld|/tmp/dyldOLD1|'` (13 chars), copies the old dyld to `/tmp/dyldOLD1` (mode 555), and expects `signal` to FAIL with `exit=68`. Skip that part with a note if `/usr/lib/dyld.cctools-266` is absent.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Run `make check-proc`.**
- [ ] **Step 4: Commit** `stress: add the process tests (fork, exec, signals under dyld, deep stack, pipes)`

---

### Task 7: stress-net

**Files:** Create `net/net.c`, `net/runtests`; modify `Makefile` (`check-net`).

All tests use `127.0.0.1`, with the port from `bind(0)` + `getsockname`.
- `tcp` (solo, `procs` connections): a listener accepts `procs` connections. Each client sends 1 MB patterned with key `(seed, conn)` in random 1 B–16 KB writes. The server side reads with random sizes and checks every byte at its stream offset. Units: bytes.
- `udp` (5000 datagrams per worker): each datagram is `seq` (4 bytes) + `len` (2 bytes) + a patterned payload keyed by seq. The receiver checks the payload. Loss is counted (`lost=` field, no fail); corruption or a duplicate → FAIL. Units: datagrams.
- `unix` (solo): as tcp over a `socketpair(AF_UNIX, SOCK_STREAM)` per pair and over a bound AF_UNIX path socket under `-d`.
- `select` (solo, 32 sockets): one server process `select`s over 32 accepted sockets with a 2 s timeout. Clients send framed messages (`id`, `seq`, payload keyed by id) at random intervals. The server checks the framing per socket. A `select` that returns 0 while data was sent at least 500 ms earlier → `FAIL reason=missed-wakeup`; a frame on the wrong socket → `FAIL reason=crosstalk`. Units: messages.
- `accept` (2000): connect/accept/close storms. Before and after, count open descriptors by probing `fcntl(fd, F_GETFD)` for fd 0..`getdtablesize()`; the counts must match. Units: connections.
- `fdpass` (200): probe that `sendmsg` with `SCM_RIGHTS` over a socketpair works; otherwise UNSUP. Body: the sender opens a patterned temp file and passes the fd; the receiver reads through the received fd and checks the data and that `fstat` inode matches. Units: fds.

`-x`: tcp, unix and udp corrupt one payload byte before sending; fdpass passes the wrong file.

- [ ] **Step 1: Failing check** — `check-net`: `net/stress-net -n 4 -i 50` gives tcp udp unix select accept PASS and fdpass PASS or UNSUP; `-x -i 5 tcp udp unix` gives 3 FAIL lines.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Run `make check-net`.**
- [ ] **Step 4: Commit** `stress: add the network tests (tcp, udp, unix, select, accept, fd passing)`

---

### Task 8: Top-level run, README, install and package

**Files:** Create `src/Commands/stress/run`, `README`; modify `Makefile` (`install`).

- `run [-a] [-s seed] [-t secs] [-d dir] cycles [cat ...]` (default cats: `vm mmap fs proc net`):
  1. `rm -rf <dir>/stress.*` first (Review Focus 5).
  2. Ensure `Report/` next to the script exists; clear `Report/*.out`.
  3. For each cat, `(cd <cat>; ./runtests [-s][-t][-d] cycles) > Report/<cat>.out 2>&1`, in the background when `-a`, then `wait`.
  4. Move any `core` files under the tree into `Report/cores/<cat>.core.<n>`.
  5. Write `Report/summary`: per cat `<cat> PASS=n FAIL=n UNSUP=n`, then every FAIL line.
  6. Exit 1 if any FAIL.
- `install`: `install -d $(DSTROOT)/usr/local/stress/{vm,mmap,fs,proc,net,Report}`; binaries mode 755; runtests and run mode 755; README mode 644.
- README: one-screen usage, the result line grammar, and the options.

- [ ] **Step 1: Failing check** — `check-run`: `touch /tmp/stress.junk.1; ./run -d /tmp 1 vm` exits 0, `/tmp/stress.junk.1` is gone, `Report/summary` has a `vm PASS=` line with `FAIL=0`.
- [ ] **Step 2: Implement `run`, README, `install`.**
- [ ] **Step 3: Run the check, then the package build** on the dev guest: `rbuild buildpackage --state /build/stress-state --toolchain /build/src/rbuild-1/toolchains/gcc-darwin-i386.conf --arch i386 --dir --target all Commands/stress /build/repo /build/stressout`. The source must be synced to `/build/src/Commands/stress` first. Expected: `stress-1-i386.apk` lists `usr/local/stress/run` and the five binaries (`gzip -dc ... | tar tf -`).
- [ ] **Step 4: Commit** `stress: add the top-level runner, README and install rules`

---

### Task 9: Harness integration

**Files:** Create `vm/stress_report.py`, `vm/test_stress_report.py`; modify `vm/ffsbench.py` (add a `stress` subcommand).

**Interfaces:**
- `stress_report.parse(text) -> list[dict]`: one dict per STRESS line, `{"cat","test","result", **fields}`, with numbers as int/float (`ops` from `R/s`, `maxlat` from `Lms`), and the quotes stripped from `reason`.
- `stress_report.summarize(rows) -> dict`: `{"counts": {cat: {"PASS":n,"FAIL":n,"UNSUP":n}}, "fails": [raw lines], "rates": {"cat.test": {"ops": max, "maxlat": max}}}`.
- `stress_report.compare(a, b) -> list[tuple]`: `(name, ops_a, ops_b, pct_change, maxlat_a, maxlat_b)` for tests present in both, sorted by `pct_change`. CLI: `python vm/stress_report.py A/result.txt B/result.txt` prints a table.
- `ffsbench.py stress [--kernel K] --label L [--cycles 1] [--bootargs ""]`:
  1. With `--kernel`, `boot_or_skip`; without it, run on the image's own kernel (wait for sshd only).
  2. Tar `src/Commands/stress` (LF) and push it to `/tmp/stress-src`.
  3. On the guest: `make && make install DSTROOT=/`.
  4. Mount hd1 with the existing `MOUNT`.
  5. Run `/usr/local/stress/run -a -d /mnt1 <cycles>` under `STRESS_RUN_LIMIT_S = 4 * 3600`.
  6. Fetch every `Report/*.out` and `summary` into the run dir.
  7. Write `result.txt` with `json.dumps(summarize(parse(all out text)))`.

- [ ] **Step 1: Write failing pytest `vm/test_stress_report.py`**
```python
LINES = """STRESS vm cow PASS iters=20 procs=1 secs=3.5 ops=812/s maxlat=41ms seed=7
STRESS mmap sync UNSUP reason="msync: ENOSYS"
STRESS fs append FAIL what=nul off=0x3e000 want=a5c3 got=0000 seed=7
noise line
"""
def test_parse():
    rows = stress_report.parse(LINES)
    assert [r["result"] for r in rows] == ["PASS", "UNSUP", "FAIL"]
    assert rows[0]["ops"] == 812 and rows[0]["maxlat"] == 41
    assert rows[1]["reason"] == "msync: ENOSYS"
    assert rows[2]["off"] == "0x3e000"
def test_summarize():
    s = stress_report.summarize(stress_report.parse(LINES))
    assert s["counts"]["vm"]["PASS"] == 1 and s["counts"]["fs"]["FAIL"] == 1
    assert s["fails"] == ["STRESS fs append FAIL what=nul off=0x3e000 want=a5c3 got=0000 seed=7"]
    assert s["rates"]["vm.cow"] == {"ops": 812, "maxlat": 41}
def test_compare():
    a = {"rates": {"vm.cow": {"ops": 800, "maxlat": 40}, "x.y": {"ops": 1, "maxlat": 1}}}
    b = {"rates": {"vm.cow": {"ops": 400, "maxlat": 90}}}
    assert stress_report.compare(a, b) == [("vm.cow", 800, 400, -50.0, 40, 90)]
```
- [ ] **Step 2: Run** `python -m pytest vm/test_stress_report.py -q` → fails (no module).
- [ ] **Step 3: Implement `stress_report.py` and the `stress` subcommand.**
- [ ] **Step 4: Run** pytest → 3 passed; also `python -m pytest vm/test_ffsbench.py -q` still passes.
- [ ] **Step 5: Commit** `ffsbench: run the stress suite in a guest and compare kernels by its report`

---

### Task 10: Acceptance on the v2 image

**Files:** none new; results go in the ledger and the spec's success-criteria evidence.

- [ ] **Step 1:** Run `python vm/ffsbench.py stress --label stress-accept --cycles 1` (the image's own kernel) with `FFSBENCH_ROOT=vm/work/rhap-i386-bootstrapped-v2.img`. Expected: `result.txt` shows FAIL=0 in every category. UNSUP is allowed only for `mmap.sync`, and for `vm.wire` / `net.fdpass` if refused.
- [ ] **Step 2:** MapFS regression proof: run `stress --kernel` with a kernel built from ffs-perf before 7ed3069ab (`mach_kernel-pm` in `vm/work/ffsbench` predates it) and `--cycles 1`. Expected: `mmap mixed` (or `fs append`) FAIL with `off=` in at least one of 3 runs. Record the rate.
- [ ] **Step 3:** dyld regression proof: Task 6's check-proc case on the v2 guest (old dyld present as `/usr/lib/dyld.cctools-266`). Expected: `signal` FAIL exit=68 on the old dyld and PASS on `/usr/lib/dyld`.
- [ ] **Step 4:** Compare the two kernels' result files with `python vm/stress_report.py A B` and paste the table into the ledger.
- [ ] **Step 5: Commit** any fixes found along the way with their own messages. If none, no commit.
