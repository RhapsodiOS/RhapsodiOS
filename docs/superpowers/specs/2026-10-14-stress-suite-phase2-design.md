# Stress suite phase 2 design

## Purpose

Phase 2 completes the stress suite started in phase 1
(`docs/superpowers/specs/2026-10-13-stress-suite-design.md`). It adds the four
remaining areas: Mach IPC, cthreads, smaller system services, and raw disk I/O.
The goal is unchanged: find kernel stability bugs, measure kernel performance,
and let the QEMU harness compare kernels.

Phase 1's plan for System V IPC does not apply. kernel-7 has no `semget`,
`shmget` or `msgget`, so `stress-ipc` exercises Mach IPC, the system's native
messaging, and reports System V IPC as UNSUP.

## Scope

Four new categories, each a binary on the existing `libstress.a` with its own
`runtests`:

- `stress-ipc`: Mach messaging.
- `stress-thread`: cthreads.
- `stress-misc`: locks, timers, limits, FIFOs, descriptors, process groups.
- `stress-disk`: raw device I/O.

Everything in phase 1 applies unchanged:
- **Result lines:** the grammar, and the `worker=`/`iter=`/`seed=` fields on FAIL lines.
- **Self-check and timing:** the `-x` self-check, `ops`/`maxlat` timing, and the watchdog.
- **Cleanup:** scratch files go under `-d/stress.<cat>.*`.
- **Packaging and harness:** packaging, `run`, `Report/`, `ffsbench stress` and `stress_report.py`.

## Success criteria

- **Healthy kernel:** `run 1 ipc thread misc` finishes with every test PASS or UNSUP and exits 0, apart from failures traced to filed kernel issues.
- **Raw disk:** `stress-disk -D <scratch raw device>` passes on the harness's hd1 and refuses a mounted or root device.
- **Every data test:** the hidden `-x` mode makes it FAIL at the corrupted offset or item.
- **Harness:** `ffsbench stress` runs the new categories and reports them in `result.txt`.

## Library changes

Two small additions, both used by more than one category:
- **`st_cleanup_hook`:** a per-test function that `st_fail` calls before it writes the FAIL line. This replaces the copied "cleanup, then st_fail" wrappers in fs, mmap and net. Phase 1 categories may move to it, but don't have to.
- **`st_readfull` / `st_writefull`:** read and write with EINTR and short-transfer handling, replacing the per-category copies.

Neither changes the result grammar.

## stress-ipc (Mach IPC)

All ports are made with `port_allocate` (or `mach_port_allocate`, whichever the
headers provide) and passed between processes through the bootstrap server
under a name unique to the test, (`stress.<pid>.<idx>`). Each port is
deregistered on exit.

| test | does | catches |
|---|---|---|
| msg | pairs of processes exchange `-i` inline messages; each carries seq, idx and a patterned body sized 0-1 KB; receiver checks order and body; then the reverse direction | message loss, reordering, corruption |
| ool | messages carry out-of-line memory (1-64 pages), copy and dealloc modes; receiver checks every page with the pattern; sender rechecks its own copy after send (copy mode must stay intact) | VM copy-on-write through IPC, page loss |
| rights | send rights created, transferred in messages and deallocated in loops; afterwards the task's port name count (`port_names`) must equal the starting count | port right leaks, refcount bugs |
| deadname | receiver destroys its port mid-stream; sender must see send errors / a dead-name notification within 5 s, never a hang | dead-name handling |
| bootstrap | concurrent register / look_up / deregister of unique names against mach_init | bootstrap server races |
| sysv | probe only: `semget`/`shmget`/`msgget` absent → UNSUP | records the gap |

If the system's Mach headers do not provide a call a test needs, that test
reports UNSUP with the missing call's name.

## stress-thread (cthreads)

| test | does | catches |
|---|---|---|
| create | `cthread_fork` / `cthread_join` storms (bounded at 32 live threads); each thread returns `st_mix(idx)`, checked at join | thread lifecycle bugs |
| mutex | N threads × M increments of shared counters under one `mutex_t`; final value must equal N×M; also a per-thread patterned record updated under the lock and checked | lost updates, lock bugs |
| cond | producers hand numbered items to consumers through a `condition_t` queue; every item delivered exactly once, in per-producer order | missed wakeups, lost or duplicated items |
| stack | each thread fills a 32 KB patterned array on its own stack, yields, rechecks | stack overlap, wrong stack switching |
| fork | one thread forks while others run the mutex loop; the child must run, allocate, exit 0 | fork in a multithreaded task |
| signal | process with 8 threads receives timer and peer signals; handlers count; counts and thread progress checked | signal delivery with threads |

## stress-misc (system services)

| test | does | catches |
|---|---|---|
| flock | processes increment a counter stored in a file, guarded only by `flock`; final value exact | lock bugs |
| fcntl | the same with `fcntl` byte-range locks on separate records; each record's value exact | range lock bugs |
| timer | `setitimer` and `select`/`sleep` timeouts must never fire early (measured with `gettimeofday`, allowing for #40 steps up to 1 ms); counts backward clock steps as `clockback=` | early timeouts, clock bugs |
| rlimit | set `RLIMIT_NOFILE`, `RLIMIT_FSIZE`, `RLIMIT_DATA`, `RLIMIT_CORE` low in a child; the documented error (EMFILE, SIGXFSZ/EFBIG, ENOMEM) must come at the limit | limit enforcement |
| fifo | `mkfifo` under `-d`, writer/reader processes pass patterned data in random sizes; every byte checked | named pipe bugs |
| fds | open descriptors until EMFILE, close them all, repeat; descriptor count must return to the start value | descriptor table leaks |
| pgrp | `setsid`, `setpgid`, and an orphaned stopped process group must get SIGHUP+SIGCONT | job control |

## stress-disk (raw device I/O)

Requires `-D <raw device>`. With no `-D`, every test reports `UNSUP reason="no
device"` and touches nothing. Before writing, the binary refuses the device
(`FAIL reason=unsafe-device`) if any of these hold:
- **Mounted:** the block or raw form appears in `getmntinfo`.
- **Root disk:** it is the root file system's disk.
- **Not character special:** `stat` says it isn't a character device.

`stress-disk` is not in `run`'s default category list. It runs only when named
together with `-D`.

| test | does | catches |
|---|---|---|
| seq | write the device sequentially in 64 KB blocks with a pattern keyed by sector number, then read back and check | driver/DMA data corruption |
| rand | random-offset, random-size (sector-aligned, 512 B-128 KB) writes then reads | request ordering, partial transfers |
| verify | concurrent readers and one writer on disjoint regions; readers check that unwritten regions keep their last known pattern | cross-request corruption |

Size limit: `-m` bytes (default 64 MB) from the start of the device.

## Runners and harness

- Each new category gets a `runtests` modelled on `vm/runtests`.
- **`run`:** its default categories become `vm mmap fs proc net ipc thread misc`. `disk` runs only when named and `-D` is given; `run` gains `-D dev` and passes it on.
- **`ffsbench stress`:** gains `--disk`, which passes `-D /dev/rhd1a`. The scratch disk is not mounted for that invocation, and fs is not run alongside it.
- **Install and package:** cover the new binaries and scripts.

## Error handling

Same rules as phase 1:
- **Setup failures:** FAIL with the errno.
- **UNSUP:** only for refused or missing features.
- **Cleanup:** children, threads, ports and scratch files are cleaned up on every path.
- **Expected faults:** handled and counted.

## Testing the suite

- **Self-checks:** a `make check-<cat>` for each new category, with real runs and `-x` runs, on the dev guest (`vm/stress_dev.py`).
- **Disk safety:** `check-disk` uses a throwaway raw device. That is hd1 on the dev guest, unmounted first. It must show the refusal of a mounted device.
- **Acceptance:** `ffsbench stress --cats "ipc thread misc"` and `--disk` on the v2 image's kernel. Every FAIL is either traced to a filed issue or reported as a new finding.
