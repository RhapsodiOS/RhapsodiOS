# Stress Suite Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `stress-ipc`, `stress-thread`, `stress-misc` and `stress-disk` to `src/Commands/stress`, wire them into `run`, install and `ffsbench stress`, and prove them on the v2 guest.

**Architecture:** Each category is a binary built on phase 1's `libstress.a` (`stress_main`, test tables, `st_fail*`, patterns, timing) with its own `runtests` modelled on `vm/runtests`. Two small library additions are shared by the new categories: a per-test cleanup hook and full read/write helpers. Raw disk is opt-in behind `-D` with refusal checks.

**Tech Stack:** C89 on the guest (gcc 2.7-era `cc`, GNU make 3.74, `/bin/sh`), Mach IPC and cthreads from the system headers, Python 3 + pytest on the host for harness code.

**Spec:** `docs/superpowers/specs/2026-10-14-stress-suite-phase2-design.md` (phase 1: `docs/superpowers/specs/2026-10-13-stress-suite-design.md`)

## Global Constraints

- All phase 1 global constraints hold. That covers: C89, no `//`, page size from `getpagesize()`, plain `/bin/sh`, a plain Makefile on GNU make 3.74, the result-line grammar, exit 1 on any FAIL, and the UNSUP rule. Commits are short, with a `stress:`/`ffsbench:` prefix and no metadata. Never write the golden or v2 images, and stop guests only via QMP after `query-name`.
- FAIL lines keep the phase 1 suffix ` worker=N iter=N` (added by `st_fail`) and the leader's `seed=`.
- `stress-disk` must never write a device unless `-D` names it. It refuses mounted, root or non-character devices with `FAIL reason=unsafe-device`. With no `-D` it reports `UNSUP reason="no device"` for every test.
- `run`'s default categories become `vm mmap fs proc net ipc thread misc`. `disk` runs only when named and `-D` is given.
- At most 32 live cthreads per test. Bounded fork counts (root forking past ~517 panics this kernel, #42).
- System V IPC is reported as UNSUP by a probe. Nothing else depends on it.

## Review Focus

1. A Mach test whose peer dies mid-exchange must FAIL promptly with a reason (bounded receive timeouts), never hang until the watchdog (Task 2).
2. Ports and bootstrap names must be released on every path. A rerun must not find the previous run's names (Task 2).
3. Thread tests must not leave threads running after FAIL. The worker's `_exit` ends them (Task 3).
4. `stress-disk -D /dev/rhd0a` and a mounted device must be refused before any write (Task 5).
5. `timer` must not FAIL on #40's microsecond backward steps; it reports them as `clockback=` (Task 4).

---

## File Structure

```
src/Commands/stress/
  lib/stress.h, lib/main.c, lib/report.c   + st_set_cleanup, st_readfull, st_writefull
  lib/io.c                                 st_readfull / st_writefull (new)
  ipc/ipc.c        ipc/runtests
  thread/thread.c  thread/runtests
  misc/misc.c      misc/runtests
  disk/disk.c      disk/runtests
  Makefile, run, README                    new targets, install, defaults, -D
vm/ffsbench.py                             stress --disk
vm/test_ffsbench.py                        test for the --disk command line
```

Phase 1 categories are not migrated to the new library helpers (the spec makes that optional).

---

### Task 1: Library cleanup hook and full I/O helpers

**Files:** Create `src/Commands/stress/lib/io.c`. Modify `lib/stress.h`, `lib/report.c` (`st_fail`), `lib/t_lib.c` or `lib/t_main.c`, and the `Makefile`.

**Interfaces (produces):**
```c
void st_set_cleanup(struct st_ctx *c, void (*fn)(struct st_ctx *));
     /* st_fail (and st_fail_errno/st_fail_data) call fn(c) once, before writing the FAIL line;
        fn must not call st_fail; the hook is cleared before it runs so a fault inside it cannot recurse */
long st_readfull(int fd, void *buf, unsigned long len);   /* loops on EINTR and short reads; returns bytes read (< len only at EOF) or -1 */
long st_writefull(int fd, const void *buf, unsigned long len); /* loops on EINTR and short writes; returns len or -1 */
```

- [ ] **Step 1: Failing checks.** Add `make check` cases:
  - A `stress-tmain` test `hook` that registers a cleanup creating `/tmp/stress.tmain.hook.<pid>`, then calls `st_fail(c, "reason=planned")`. The output must have the FAIL line and the marker file must exist; the check removes it afterwards.
  - A `t_lib` assertion that `st_writefull`/`st_readfull` round-trip 100000 bytes through a pipe written by a forked child in 1-byte writes. The child is reaped.
- [ ] **Step 2:** On the dev guest (`python vm/stress_dev.py up`, `sync`, `sh "cd /tmp/stress-src && make check"`), see the failure.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `make check` passes: `t_lib: ok`, `t_main: ok`.
- [ ] **Step 5:** Commit: `stress: add a per-test cleanup hook and full read/write helpers`.

---

### Task 2: stress-ipc (Mach IPC)

**Files:** Create `ipc/ipc.c` and `ipc/runtests`. Modify the `Makefile` (`all`, `check-ipc`, `clean`).

**API decision (Step 0 of this task):**
- Compile a probe on the guest that includes `<mach/mach.h>` and `<servers/bootstrap.h>` (or `<mach/bootstrap.h>`, whichever exists) and references each candidate call.
- Use the Mach 3 user API if it links: `mach_port_allocate`, `mach_msg`, `mach_port_deallocate`, `mach_port_names`, `bootstrap_register`, `bootstrap_look_up`. Otherwise use the NeXT/Mach 2.5 API: `port_allocate`, `msg_send`/`msg_receive`, `port_deallocate`, `port_names`, `bootstrap_register`, `bootstrap_look_up`.
- Record which family links in the report. A test whose needed call is missing in both families reports `UNSUP reason="<call>: ENOSYS"`.

**Tests:** see the spec table. Defaults are `msg` 2000, `ool` 200, `rights` 500, `deadname` 50, `bootstrap` 500, and `sysv` (probe only).
- **Shared rules:**
  - Ports are passed to peers through the bootstrap server under `stress.<leaderpid>.<test>.<idx>`.
  - Every receive has a 5 s timeout. A timeout is `FAIL reason=timeout what=<msg|ool|...>`.
  - The cleanup hook deregisters names and deallocates ports.
- **`msg` body:** `seq` (4 bytes), `idx` (4 bytes), `len` (4 bytes), then `len` patterned bytes (0-1024), keyed `st_mix(seed ^ idx)` at offset `seq * 1024`.
- **`ool`:** 1-64 pages. Copy mode leaves the sender's region unchanged, which is rechecked. Dealloc mode removes the sender's mapping.
- **`rights`:** compare `port_names` counts before and after with exact equality.
- **`deadname`:** the receiver destroys its receive right after N messages. The sender must get `SEND_INVALID_DEST`/`MACH_SEND_INVALID_DEST`, or a dead-name notification if the API supports one, within 5 s.
- **`sysv`:** a probe calls `semget` through dyld lookup (as vm.c binds `mlock`). The symbol is absent, or the call returns ENOSYS, so the test reports `UNSUP reason="semget: ENOSYS"`.

`-x`: msg and ool flip one body byte before sending; rights deallocates one fewer right, so the count check FAILs.

- [ ] **Step 1: Failing check.** `check-ipc`:
  - `ipc/stress-ipc -n 2 -i 50` gives PASS or UNSUP for every test. `sysv` must be UNSUP.
  - `ipc/stress-ipc -x -i 5 msg ool rights` gives 3 FAIL lines, with `off=` on msg and ool.
  - Running the same command twice in a row leaves no `stress.` names: list them with the bootstrap API, or just require that the second run PASSes.
- [ ] **Step 2:** Implement.
- [ ] **Step 3:** `make check-ipc` passes on the dev guest.
- [ ] **Step 4:** Commit: `stress: add the Mach IPC tests (messages, out-of-line memory, rights, dead names, bootstrap)`.

---

### Task 3: stress-thread (cthreads)

**Files:** Create `thread/thread.c` and `thread/runtests`. Modify the `Makefile` (`check-thread`).

Uses `<cthreads.h>`: `cthread_fork`, `cthread_join`, `cthread_yield`, `mutex_alloc`/`mutex_lock`/`mutex_unlock`, `condition_alloc`/`condition_wait`/`condition_signal`.

**Tests and defaults:**
- **`create` (200):** rounds of up to 32 threads. Each returns `(any_t)st_mix(idx)`, checked at join.
- **`mutex` (20):** 8 threads × 10000 increments. The counter must equal 80000 exactly. Each thread also rewrites its patterned 64-byte record under the lock, and records are checked at the end.
- **`cond` (20):** 4 producers and 4 consumers pass 2000 items. Each item is `(producer, seq)`. Every item arrives once, in per-producer order.
- **`stack` (50):** each of 16 threads fills a 32 KB local array with `key = st_mix(idx ^ round)`, calls `cthread_yield` 10 times, then checks the array.
- **`fork` (20):** while 4 threads run the mutex loop, the main thread forks. The child mallocs 1 MB, fills it, checks it and `_exit(0)`s. The parent checks the child's status.
- **`signal` (5):** 8 threads spin on counters while a 2 ms `setitimer` and a sender child deliver SIGALRM and SIGUSR1. Counts must reach ≥ 50 SIGALRM and ≥ 1 SIGUSR1, and every thread must have advanced.

`-x`: mutex skips one increment, so the total is off. stack flips a byte. cond drops one item.

- [ ] **Step 1: Failing check.** `check-thread`:
  - `thread/stress-thread -n 1 -i 3` gives 6 PASS.
  - `-x -i 2 mutex stack cond` gives 3 FAIL lines.
- [ ] **Step 2:** Implement.
- [ ] **Step 3:** `make check-thread` passes.
- [ ] **Step 4:** Commit: `stress: add the cthreads tests (create, mutex, condition, stacks, fork, signals)`.

---

### Task 4: stress-misc (system services)

**Files:** Create `misc/misc.c` and `misc/runtests`. Modify the `Makefile` (`check-misc`).

**Tests and defaults:**
- **`flock` (2000 increments per worker):** the counter is a decimal string in `<dir>/stress.misc.flock.<leaderpid>`. Each worker does open, `flock(LOCK_EX)`, read, +1, `lseek` 0, write, unlock. The final value must be `procs*iters`.
- **`fcntl`:** the same with `F_SETLKW` byte-range locks on 8-byte records, one record per worker pair.
- **`timer` (50):** `setitimer` intervals of 10-200 ms, and `select` timeouts of 10-500 ms. The measured interval must be at least the requested one minus 1 ms. Early firing is `FAIL what=early want=<ms> got=<ms>`. Backward steps counted by the library show up as `clockback=`.
- **`rlimit` (each once):** in a child, with the limit set to 16, 64 KB, 4 MB and 0 respectively:
  - `RLIMIT_NOFILE`: EMFILE at the limit.
  - `RLIMIT_FSIZE`: SIGXFSZ or EFBIG on writing past it.
  - `RLIMIT_DATA`: malloc returns NULL before exceeding it by 1 MB.
  - `RLIMIT_CORE`: no core file is written.
- **`fifo` (50):** `mkfifo` under `-d`. The writer child sends 256 KB patterned in random sizes; the reader checks every byte.
- **`fds` (50):** open `/dev/null` until EMFILE, close them all, and compare the count of open descriptors with the start (same probe as net accept).
- **`pgrp` (20):** a child does `setsid`, forks a grandchild that `kill(getpid(), SIGSTOP)`s, then the child exits. The orphaned stopped grandchild must receive SIGHUP then SIGCONT (it reports via a pipe) within 5 s.

`-x`: flock and fcntl skip one increment, fifo flips a byte, and timer requests 1 ms more than it measures against.

- [ ] **Step 1: Failing check.** `check-misc`:
  - `misc/stress-misc -n 3 -i 20` gives PASS or UNSUP for all 7.
  - `-x -i 5 flock fifo` gives 2 FAIL lines.
- [ ] **Step 2:** Implement.
- [ ] **Step 3:** `make check-misc` passes.
- [ ] **Step 4:** Commit: `stress: add the system service tests (locks, timers, limits, fifos, descriptors, process groups)`.

---

### Task 5: stress-disk (raw device I/O)

**Files:** Create `disk/disk.c` and `disk/runtests`. Modify the `Makefile` (`check-disk`) and `lib` only if `-D` must be a library option: add `-D dev` to `st_opts` as `const char *dev` (default NULL), parsed by `stress_main`.

**Safety checks (run in the probe, before any write):** `stat(dev)` must be a character device. Its block-device twin is derived by dropping the leading `r` of the basename. Neither name may appear in `getmntinfo`'s `f_mntfromname`, and neither may be the device of `/` (`stat("/").st_dev` vs the block device's `st_rdev`). Any failure is `FAIL reason=unsafe-device`. With no `-D`, the result is `UNSUP reason="no device"`.

**Tests:**
- **`seq` (1):** writes `-m` bytes (default 64 MB) in 64 KB blocks, keyed by sector (`key = st_mix(seed)`, offset = absolute byte offset), then reads them all back and checks.
- **`rand` (500):** random sector-aligned offsets and sizes (512 B-128 KB) within `-m`, write then read back.
- **`verify` (solo, 200):** one writer child rewrites regions with new keys and records `(region, key)` in a pipe log. Three readers read regions not being written and check them against the last key for that region.

`-x`: seq and rand write one sector with the wrong key, so the read-back check must FAIL with `off=` at that sector's offset.

- [ ] **Step 1: Failing check.** `check-disk` (on the dev guest, hd1 unmounted, as `/dev/rhd1a`):
  - `disk/stress-disk seq` (no -D) gives UNSUP.
  - `disk/stress-disk -D /dev/rhd0a seq` gives `FAIL reason=unsafe-device`.
  - After mounting hd1, `-D /dev/rhd1a seq` gives `unsafe-device`, then unmount.
  - `-D /dev/rhd1a -m 8m` gives 3 PASS.
  - `-x -D /dev/rhd1a -m 8m seq` gives FAIL with off=.
- [ ] **Step 2:** Implement.
- [ ] **Step 3:** `make check-disk` passes.
- [ ] **Step 4:** Commit: `stress: add the raw disk tests behind -D with mounted and root device refusal`.

---

### Task 6: run, install, package and harness

**Files:** Modify `src/Commands/stress/run`, `README`, the `Makefile` (`install`), `vm/ffsbench.py` and `vm/test_ffsbench.py`.

- **`run`:**
  - The default categories become `vm mmap fs proc net ipc thread misc`.
  - Add `-D dev`, which is passed to `disk/runtests`.
  - `disk` runs only when named, and refuses with exit 2 when named without `-D`.
- **`install`:** the four new binaries and runtests. README documents the new categories and `-D`.
- **`ffsbench.py stress`:**
  - Add `--disk`. It adds `disk` to the categories and passes `-D /dev/rhd1a` to `run`, without mounting hd1 for that invocation.
  - `--disk` cannot be combined with `fs` in `--cats` (argparse error).
  - A unit test checks the built remote command line for `--disk`. Factor out a small `stress_run_command(cats, cycles, seed, disk)` helper so it is testable.
- **Package:** rebuild with rbuild on the dev guest as in phase 1 Task 8. The apk lists the four new binaries.

- [ ] **Step 1: Failing tests.**
  - pytest: `stress_run_command(["ipc"], 1, 7, False)` contains `-s 7` and `ipc`. With `disk=True` it contains `-D /dev/rhd1a`.
  - `check-run` gains `sh ./run -d /tmp 1 ipc`, which exits 0.
- [ ] **Step 2:** Implement.
- [ ] **Step 3:** pytest and `check-run` pass. The apk listing includes `ipc/stress-ipc`, `thread/stress-thread`, `misc/stress-misc` and `disk/stress-disk`.
- [ ] **Step 4:** Commit: `stress: run, install and the harness know the phase 2 categories`.

---

### Task 7: Acceptance

- [ ] **Step 1:** `python vm/ffsbench.py stress --label p2-img --cycles 1 --cats "ipc thread misc"` on the v2 image's kernel.
- [ ] **Step 2:** `python vm/ffsbench.py stress --label p2-disk --cycles 1 --disk --cats disk` on the same kernel.
- [ ] **Step 3:** Map every FAIL, lost guest or UNSUP to a filed issue, a known gap (System V IPC, #43), or a NEW finding with command, seed and FAIL line.
- [ ] **Step 4:** Commit only fixes to suite or harness bugs found, each with its own message.
