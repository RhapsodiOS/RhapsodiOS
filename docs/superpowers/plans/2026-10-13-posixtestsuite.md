# Open POSIX Test Suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import Open POSIX Test Suite 1.5.2 unmodified, run its 2146 conformance tests on RhapsodiOS with our own runner, and compare each run against a checked-in baseline.

**Architecture:** Upstream lives untouched in `src/Commands/posixtestsuite-1/posixtestsuite/`. Beside it, a `/bin/sh` runner (`run`) compiles, links and runs each test under `ptimeout` (a small C helper) and writes one result line per test, then compares against `baseline`. `vm/posix_dev.py` (modelled on `vm/stress_dev.py`, reusing `vm/ffsbench.py`) drives it on a v2 snapshot guest.

**Tech Stack:** C (system cc), Bourne `/bin/sh`, GNU Make 3.74, Python 3 on the host.

**Spec:** `docs/superpowers/specs/2026-10-13-posixtestsuite-design.md`

## Global Constraints

- Work in worktree `D:\RhapsodiOS\.claude\worktrees\posixtestsuite`, branch `posixtestsuite` (off `ffs-perf`). Never `cd` to the main checkout.
- Upstream tarball: `posixtestsuite-1.5.2.tar.gz`, sha256 `15a2185672127cba851d35ec9d538ff6148defdbb75f99c7e9c50aeba0f94757`, 2867 files, all LF text. Already extracted at `C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/1bc97acd-c3c2-4e40-add7-2eb9fc98a079/scratchpad/posixsrc/posixtestsuite`. Nothing in it is edited.
- Makefile: GNU Make 3.74 — pattern rules only, no `$(call)`, no target-specific variables; make runs `sh -e`, so catch statuses with `||` (see `src/Commands/stress/Makefile`).
- Shell: plain `/bin/sh` — backquotes not `$(...)`, no `local`, no bash/ksh features; style as `src/Commands/stress/vm/runtests`.
- Compile flags for tests: `cc -O -Wall -D_POSIX_C_SOURCE=200112L -I<root>/include` (no `-Werror`, no `-std=`).
- Default per-test timeout 240 s. Default paths: `conformance`. Work dir default `/tmp/posix.<pid>`.
- Result words, exactly: `BUILD-FAIL LINK-FAIL BUILD-ONLY PASS FAIL UNRESOLVED UNSUPPORTED UNTESTED HUNG SIGNAL=n EXIT=n`; baseline-only word `FLAKY`.
- Installed to `$(DSTROOT)/usr/local/posixtestsuite`.
- Dev guest: name `RhapsodiOS posix-dev`, ports `2549,4549,1249` (ssh, QMP, gdb), override `POSIX_DEV_PORTS`; boot only snapshot guests of the v2 image; stop only through QMP after `query-name`.
- Spec clarifications made here: `run` also takes `-r root` and `-b baseline` (so `make check` can point it at `t/`), and always writes `Report/baseline.new`, which `-u` and `posix_dev.py baseline` copy, so the baseline format lives in one place.
- Commit messages: `posixtestsuite: ...` / `vm: ...` / `docs: ...`, one or two lines, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. A test that signals its own process group (`kill(0, …)`, `killpg(getpgrp(), …)` — real `killpg` tests do this) must not take `run` down: it gets `SIGNAL=n` and the run continues. Pinned by fixture `killgrp` (Task 3).
2. A test that reads stdin must not wait for a terminal or the ssh session: `run` gives every test `</dev/null`. Pinned by fixture `stdin` (Task 3).
3. A test that catches SIGALRM or leaves children behind must not stall or litter the run. Pinned by fixtures `alarmhang` and `orphan` (Task 3) and the ptimeout checks (Task 2).
4. Tests with the same file name in different directories (every directory has a `1-1.c`) must not share objects, binaries or logs: work dirs and logs are keyed by full path. Pinned because every fixture is `1-1.c` in its own directory (Task 3).
5. Baseline comparison must match whole paths exactly, so `sigaction/1-1` never matches `sigaction/1-10` or a `speculative/` twin: compare with `sort`/`join`/`awk` on fields, never `grep` with a path as the pattern. Pinned by the Task 4 checks, which vary single entries.

---

### Task 1: Import upstream and the project skeleton

**Files:**
- Create: `src/Commands/posixtestsuite-1/posixtestsuite/` (upstream copy)
- Create: `src/Commands/posixtestsuite-1/Makefile`, `apk/pkginfo`, `README`, `baseline` (empty)

**Interfaces:**
- Produces: `make install` puts `posixtestsuite/`, `run`, `ptimeout`, `baseline`, `README` in `$(DSTROOT)/usr/local/posixtestsuite` (`run`, `ptimeout` mode 755). Later tasks add the `ptimeout`, `run` and `check` pieces to this Makefile.

- [ ] **Step 1: Copy upstream in** with `cp -R <extracted>/posixtestsuite src/Commands/posixtestsuite-1/`.

- [ ] **Step 2: Verify byte-for-byte after staging**

Run: `git add src/Commands/posixtestsuite-1/posixtestsuite && git ls-files src/Commands/posixtestsuite-1/posixtestsuite | wc -l` → `2867`. Then, for every file, `git show :<path> | sha256sum` equals `sha256sum <extracted>/<path>` (a small loop; zero mismatches). If the count is short, a `.gitignore` rule is hiding files: add them with `git add -f`.

- [ ] **Step 3: Write `apk/pkginfo`**

```
pkgname = posixtestsuite
pkgver = 1.5.2
pkgdesc = Open POSIX conformance tests
maintainer = RhapsodiOS
license = GPL
url = https://sourceforge.net/projects/posixtest/
makedepends = build-base
```

- [ ] **Step 4: Write the Makefile** with targets `all` (empty for now), `install`, `installhdrs` (empty), `installsrc` (as stress's), `clean`, `.PHONY`. `install`: `DEST = $(DSTROOT)/usr/local/posixtestsuite`; `mkdir -p`, `rm -rf $(DEST)/posixtestsuite`, `cp -R posixtestsuite $(DEST)/`, `install -m 755 run ptimeout $(DEST)/`, `install -m 644 baseline README $(DEST)/`. Leave the `run`/`ptimeout` lines in; they fail until Tasks 2–3, which is fine — install is not exercised before then.

- [ ] **Step 5: Write `README`**: what the suite is (upstream, version, sha256, GPL), `run` usage and options (from Task 3/4), result words and their meaning, how to update the baseline (`posix_dev.py baseline`, review, commit naming the kernel; `FLAKY` by hand), and that `functional/` and `stress/` are imported but not run because they need threads, message queues, semaphores or timers. Create an empty `baseline`.

- [ ] **Step 6: Commit**

```bash
git add src/Commands/posixtestsuite-1
git commit -m "posixtestsuite: import Open POSIX Test Suite 1.5.2 unmodified, with package files"
```

### Task 2: ptimeout

**Files:**
- Create: `src/Commands/posixtestsuite-1/ptimeout.c`
- Modify: `src/Commands/posixtestsuite-1/Makefile` (`all: ptimeout`, `check-ptimeout`, clean)

**Interfaces:**
- Produces: `ptimeout secs cmd [args...]`. Exit status: the child's exit status if it exits; `128+n` if it dies by signal n; `124` on timeout; `127` if usage is wrong, `secs < 1`, or fork/exec fails (message on stderr).

- [ ] **Step 1: Write the failing check** as a `check-ptimeout` target, each line its own shell:

```make
check-ptimeout: ptimeout
	rc=0; ./ptimeout 5 sh -c 'exit 3' || rc=$$?; test $$rc = 3
	rc=0; ./ptimeout 5 sh -c 'kill -SEGV $$$$' || rc=$$?; test $$rc = 139
	rc=0; ./ptimeout 2 sh -c 'trap "" ALRM; while :; do :; done' || rc=$$?; test $$rc = 124
	./ptimeout 5 sh -c 'sleep 77 & exit 0'; sleep 1; test `ps -ax | grep -c '[s]leep 77'` = 0
	rc=0; ./ptimeout 5 /nonexistent || rc=$$?; test $$rc = 127
	rc=0; ./ptimeout 0 true || rc=$$?; test $$rc = 127
	@echo ptimeout: ok
```

- [ ] **Step 2: Run on the guest to see it fail** (no `ptimeout.c` yet): `make check-ptimeout` stops at the build. (Until Task 5 exists, use a private snapshot guest per the memory notes; push the project dir with `tar` over ssh.)

- [ ] **Step 3: Implement `ptimeout.c`.** Parent: `fork`; child does `setpgid(0, 0)` then `execvp(argv[2], argv+2)`, `_exit(127)` on failure; parent also calls `setpgid(pid, pid)` (closes the race with `killpg`). Install the SIGALRM handler with `sigaction` and `sa_flags = 0` (no `SA_RESTART`, so `waitpid` returns `EINTR`; `signal()` would restart it on BSD), then `alarm(secs)` and `waitpid`. On `EINTR` with the flag set: `killpg(pid, SIGKILL)`, reap, exit 124. After a normal reap: `killpg(pid, SIGKILL)` (ignore `ESRCH`), then exit with the mapped status. No pthreads.

- [ ] **Step 4: Run the check on the guest**: `make check-ptimeout` → `ptimeout: ok`.

- [ ] **Step 5: Commit** — `posixtestsuite: add ptimeout, a timeout wrapper that kills the test's process group`.

### Task 3: run — discover, build, execute, record

**Files:**
- Create: `src/Commands/posixtestsuite-1/run`
- Create: fixtures `src/Commands/posixtestsuite-1/t/conformance/interfaces/<name>/…` (below)
- Modify: `Makefile` (`check-run`, `check: check-ptimeout check-run check-baseline`, clean removes `Report`)

**Interfaces:**
- Consumes: `ptimeout` (Task 2) from `dirname $0`.
- Produces: `run [-t secs] [-d workdir] [-r root] [-b baseline] [-u] [path ...]`.
  - `-r` suite root, default `` `dirname $0`/posixtestsuite ``; `-b` baseline file, default `` `dirname $0`/baseline ``.
  - Writes `Report/` in the current directory (removed and recreated at start): `Report/results` (lines `POSIX <path> <RESULT>`, in run order; same lines on stdout), `Report/log/<path>.log`, `Report/baseline.new` (lines `<path> <RESULT>`, sorted). `<path>` is relative to the root without extension, e.g. `conformance/interfaces/sigaction/1-1`.
  - Task 4 adds the comparison and exit status; until then `run` exits 0 after a complete run.

- [ ] **Step 1: Write the fixtures**, each `1-1.c` unless noted, under `t/conformance/interfaces/`:

| dir | body | expected |
|---|---|---|
| `pass` | `return 0` | `PASS` |
| `fail` | `return 1` | `FAIL` |
| `unres` | `return 2` | `UNRESOLVED` |
| `unsup` | `return 4` | `UNSUPPORTED` |
| `untested` | `return 5` | `UNTESTED` |
| `exit7` | `return 7` | `EXIT=7` |
| `nobuild` | syntax error | `BUILD-FAIL` |
| `nolink` | calls undefined `no_such_function()` | `LINK-FAIL` |
| `buildonly` | file `1-buildonly.c`, has `main` | `BUILD-ONLY` |
| `nomain` | defines only `int f(void)` | `BUILD-ONLY` |
| `segv` | `raise(SIGSEGV)` | `SIGNAL=11` |
| `alarmhang` | catches SIGALRM, loops forever | `HUNG` |
| `orphan` | forks a child that execs `sleep 77`; parent returns 0 | `PASS`, no `sleep 77` left |
| `killgrp` | `kill(0, SIGKILL)` | `SIGNAL=9`, run continues |
| `stdin` | reads stdin to EOF, returns 0 | `PASS` quickly |
| `shpass` | file `1-1.sh`: `exit 0` | `PASS` |

- [ ] **Step 2: Write the failing check** `check-run`: `rc=0; sh ./run -r t -b /dev/null -t 3 -d /tmp/posixcheck conformance >Report.out || rc=$$?; test $$rc = 0`, then one `grep '^POSIX conformance/interfaces/<dir>/1-1 <RESULT>$$' Report/results` per fixture row (with `1-buildonly` for `buildonly`), then `test \`grep -c '^POSIX ' Report/results\` = 16`, `test \`ps -ax | grep -c '[s]leep 77'\` = 0`, `test -f Report/log/conformance/interfaces/nobuild/1-1.log`, `test ! -d /tmp/posixcheck`, and `@echo run: ok`. Run it on the guest: fails (no `run`).

- [ ] **Step 3: Implement `run`.** Option parsing like `runtests`; unknown option → usage, exit 2. Exit 2 with a message if `cc` is not found or the work dir cannot be created. At start: `rm -rf /tmp/posix.*` (only when using the default `-d`), recreate `Report/`. Discovery: `cd $root && find <paths> \( -name '[0-9]*-*.c' -o -name '[0-9]*-[0-9]*.sh' \) -print | sort`. For each test, with `w=$work/<path>` created and used as cwd, stdin `</dev/null`, all output to the test's log:
  - `.c`: `cc <flags> -c $root/<path>.c -o $w/t.o` (compile from the source path so `"testfrmw.h"`/`"../helpers.h"` resolve) → else `BUILD-FAIL`; if the name contains `-buildonly` or `nm -g t.o | grep ' T _main$'` fails → `BUILD-ONLY`; `cc -o t t.o` → else `LINK-FAIL`; `ptimeout $secs ./t`.
  - `.sh`: `ptimeout $secs /bin/sh $root/<path>.sh`.
  - Map status: 0 `PASS`, 1 `FAIL`, 2 `UNRESOLVED`, 4 `UNSUPPORTED`, 5 `UNTESTED`, 124 `HUNG`, 129–159 `SIGNAL=<status-128>`, else `EXIT=<status>`.
  - Remove `$w` after each test; remove the work dir at the end.
  Then write `Report/baseline.new` from `Report/results` (`sed 's/^POSIX //' | sort`).

- [ ] **Step 4: Run `make check-run` on the guest** → `run: ok`.

- [ ] **Step 5: Commit** — `posixtestsuite: add the runner that builds, links and runs each test and records one result line`.

### Task 4: run — baseline comparison, summary, -u

**Files:**
- Modify: `src/Commands/posixtestsuite-1/run`
- Create: `src/Commands/posixtestsuite-1/t/baseline.ok` (the 16 expected `<path> <RESULT>` lines, sorted)
- Modify: `Makefile` (`check-baseline`)

**Interfaces:**
- Consumes: `Report/results`, `Report/baseline.new` (Task 3).
- Produces: `Report/summary`, sections in this order, each header on its own line, entries indented two spaces:
  - `== counts` — `  <n> <RESULT>` per result word seen;
  - `== build failures by family` — `  <n> <family>`, family = the directory after `interfaces/` up to its first `_` (`definitions`/`behavior` tests use the directory after those), counting `BUILD-FAIL` and `LINK-FAIL`;
  - `== regressions` / `== improvements` / `== changes` — `  <path> <old> -> <new>`;
  - `== new` — `  <path> <RESULT>`.
  Exit: 1 if `== regressions` has entries, else 0; 2 if the baseline file is missing and `-u` not given (checked before any test runs). `-u`: copy `Report/baseline.new` over the baseline file, write the summary without comparison sections, exit 0. Blank lines in the baseline are ignored; `FLAKY` entries are never listed.

- [ ] **Step 1: Write the failing check** `check-baseline` (fixtures already built by `check-run` are re-run; keep `-t 3`):
  - `t/baseline.ok` → exit 0; `Report/summary` has `== regressions` with no entries after it (`sed -n '/^== regressions/,/^==/p' | grep -c '^  '` = 0).
  - copy with the `fail` entry changed to `PASS` → exit 1; summary lists `  conformance/interfaces/fail/1-1 PASS -> FAIL` under regressions.
  - `pass` entry changed to `FAIL` → exit 0; listed under improvements.
  - `fail` entry changed to `FLAKY` → exit 0; `grep -c 'interfaces/fail/1-1' Report/summary` = 0.
  - `pass` entry deleted → exit 0; `  conformance/interfaces/pass/1-1 PASS` under new.
  - missing baseline → exit 2 and no `Report/results` lines.
  - `-u -b /tmp/posixcheck.base` → exit 0 and `cmp /tmp/posixcheck.base t/baseline.ok`.
  - `== counts` contains `  1 HUNG`; `== build failures by family` contains `  1 nobuild` and `  1 nolink`.
  Variants are made with `sed` into `/tmp/posixcheck.base`; end with `@echo baseline: ok`. Run on the guest: fails.

- [ ] **Step 2: Implement** the comparison in `run`: `join` the sorted `baseline.new` with the sorted baseline on field 1 (both `sort`ed the same way first); classify with `awk` per the rules above; `join -v1` gives new tests.

- [ ] **Step 3: Run `make check` on the guest** → `ptimeout: ok`, `run: ok`, `baseline: ok`.

- [ ] **Step 4: Commit** — `posixtestsuite: compare runs against a checked-in baseline and fail only on regressions`.

### Task 5: vm/posix_dev.py

**Files:**
- Create: `vm/posix_dev.py`, `vm/test_posix_dev.py`

**Interfaces:**
- Consumes: `ffsbench` exactly as `vm/stress_dev.py` loads and uses it (`Guest`, `_fresh_hd1`, `_workload`, `Ssh.run/push`, `Qmp`, `boot_test_kernel`, `_conf`); state file `vm/work/posix-dev.json` holding `ports` and `last_run`.
- Produces: `python vm/posix_dev.py up [--kernel PATH] | sync | sh "<cmd>" | run [run-args...] | baseline | down`; pure helpers `tar_source() -> bytes` (USTAR, entries under `posix-src/`, bytes unchanged) and `hex_to_bytes(text: str) -> bytes` (parses `od -An -v -tx1` output).

- [ ] **Step 1: Write failing tests** in `vm/test_posix_dev.py` (unittest, as `vm/test_ffsbench.py`):
  - `test_tar_source_layout`: names include `posix-src/run`, `posix-src/posixtestsuite/include/posixtest.h`; that member's bytes equal the file's bytes; no member contains `\r\n` where the source has none.
  - `test_hex_to_bytes_roundtrip`: `hex_to_bytes(" 1f 8b 08\n 00 ff\n") == b"\x1f\x8b\x08\x00\xff"`.
  - `test_main_rejects_bad_usage`: `main(["x", "bogus"])` raises `SystemExit`.

  Run: `python -m unittest vm.test_posix_dev -v` → fails (no module).

- [ ] **Step 2: Implement `vm/posix_dev.py`**, copying `stress_dev.py`'s structure and changing: `SRC` → `src/Commands/posixtestsuite-1`, ports/env/name/state per Global Constraints, guest source `/tmp/posix-src`; `sync` ends with `cd /tmp/posix-src && make && make install`.
  - `run(args)`: `mkdir -p /tmp/posix-run && cd /tmp/posix-run && rm -f status && nohup sh -c '/usr/local/posixtestsuite/run <args> >run.out 2>&1; echo $? >status' >/dev/null 2>&1 &`. Every 300 s check `test -f /tmp/posix-run/status`; give up after 8 h with a message. Then `cd /tmp/posix-run && tar cf - Report run.out status | gzip -c | od -An -v -tx1`, decode with `hex_to_bytes`, gunzip, extract into `vm/work/posix/<YYYYmmdd-HHMMSS>/`, record it as `last_run`, print `Report/summary`, exit with `status`.
  - `baseline()`: copy `<last_run>/Report/baseline.new` over `src/Commands/posixtestsuite-1/baseline` and print the `git diff --stat` line for it.

- [ ] **Step 3: Run tests** → 3 pass.

- [ ] **Step 4: Commit** — `vm: add posix_dev.py to run the POSIX test suite on a dev guest`.

### Task 6: First runs and the baseline

**Files:**
- Modify: `src/Commands/posixtestsuite-1/baseline`, and `README` only if a step below shows it is wrong.

- [ ] **Step 1:** `python vm/posix_dev.py up`, `sync`, then `sh "cd /tmp/posix-src && make check"` → `ptimeout: ok`, `run: ok`, `baseline: ok`.

- [ ] **Step 2: First full run** with `-u`: `python vm/posix_dev.py run -u`. Expect exit 0 and `grep -c '^POSIX ' Report/results` = 2146 in the copied run dir. If `BUILD-FAIL` dominates tests that include none of `pthread/semaphore/mqueue/aio/sched` headers, read a few logs: if `-D_POSIX_C_SOURCE=200112L` hides declarations the tests need, stop and report to Pat before changing flags (the flag is fixed by the spec).

- [ ] **Step 3:** `python vm/posix_dev.py baseline`, review the diff (2146 lines), commit — `posixtestsuite: record the first baseline` with the kernel named in the second line.

- [ ] **Step 4: Second run** without `-u` (after a fresh `sync` if the guest restarted). Any entries under regressions/improvements/changes are flaky: set them to `FLAKY` in `baseline`, commit — `posixtestsuite: mark tests that change between runs on one kernel as flaky`. Re-run until it exits 0.

- [ ] **Step 5:** `python vm/posix_dev.py down`. Report to Pat: the `== counts` and `== build failures by family` sections, and every `FAIL`, `HUNG`, `SIGNAL=n` or `EXIT=n` test in the signal, fork, kill, mmap, munmap, mprotect, mlock, nanosleep and time interface families, as follow-up bugs (not fixed here).
