# FFS Stall, Hard Lock and Corruption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make UFS survive and stay responsive under the `rbuild kernel` build-root extraction.
- During the extraction the system stays responsive.
- A crash in the middle leaves a filesystem `fsck` can repair.
- Throughput is no worse than today.

**Architecture:** Measure first, then fix the cause, one commit per fix.
- **Phase 0:** a host-driven harness (`vm/ffsbench.py`) boots a private i386 QEMU guest. It replays rbuild's extraction onto a fresh scratch UFS disk, measures throughput and responsiveness, and kills the guest mid-run to grade the `fsck` damage.
- **Phase 1:** a debug kernel option, `FFSDEBUG`, confirms or rules out the lead hypotheses. The corruption and hard-lock fixes follow.
- **Phase 2:** fixes for the stall and throughput.
- **Phase 3:** a written decision on soft updates, dirhash and UBC.

**Tech Stack:**
- Kernel: C in `src/kernel-7` (K&R, Apple gcc 2.7.x, Mach 2.5 with `OLD_VM_CODE`, `MACH_NBC`).
- Host tooling: Python 3 with pytest in `vm/`.
- Guest programs: C compiled with the guest's `cc`.
- QEMU (`qemu-system-i386`, TCG) with QMP and the gdbstub.

**Spec:** `docs/superpowers/specs/2026-10-05-ffs-stall-corruption-design.md`. Read it first: the "Findings" section is the reasoning behind every Phase 1 task.

## Global Constraints

**Workspace and guests**
- Work in a git worktree on branch `ffs-perf` (memory: concurrent-sessions-need-worktrees). Commit before every kernel build, because builds export a commit.
- Keep durable scratch in the **main checkout**'s `vm/work/ffsbench/` (gitignored), not in the worktree (memory: worktrees-removed-while-idle).
- Never touch the shared 2222 guest. Never write `vm/golden.img`, `vm/work/rhap-i386-bootstrapped.img` or `rhapsody.vmdk`.
- The base image is always booted with `-snapshot`.
- **Ports.** The build guest uses ssh 2531 and QMP 4531. The bench guest uses ssh 2532, QMP 4532 and gdbstub 1232. Before every boot, `netstat -ano | grep -E ":(2531|4531|2532|4532|1232) " | grep LISTEN` must print nothing.
- **One SSH session at a time per guest, and no polling loops against it** (memory: build-box-freezes-dont-poll). The only exception is the spec's banner probe: one TCP connect every 5 s to the bench guest, during a run.
- **Quit a guest only with QMP `quit`, after `query-name` confirms it is ours.** Never kill QEMU by process name.

**Boot rules for the bench guest**
- Shut down with `/sbin/reboot`, never `halt`.
- The base root filesystem is already corrupt (memory: i386-guest-boot-testing-gotchas). Never run `fsck -y` on hd0, and never measure anything on it.

**Kernel builds**
- Build only with `rbuild kernel --arch i386` on the private build guest (memory: bootstrapped-i386-guest-kernel-build).
- The kernel compiles without `-Wall`, so an undefined function or macro fails only at link, as `ld: Undefined symbols:`.

**Code and commits**
- Code style matches the surrounding file: tabs, K&R definitions in `vfs_bio.c` and `ffs_*.c`. Every changed line traces to a task step.
- `FFSDEBUG` code is entirely inside `#if FFSDEBUG`. A RELEASE build without the option must be byte-identical in behaviour to one built before this plan.
- Commit messages: one or two lines, prefixed `kernel: `, `vm: ` or `docs: `, describing what the change does. No trailing metadata and no `Co-Authored-By` (CLAUDE.md §5).
- `slow.c` has no license. Never commit it. It is downloaded to `vm/work/ffsbench/slow.c` and patched there.

**Exit criteria (copied from the spec)**
- **Phase 1:** 20 of 20 crash runs *preen-fixable* or better with 0 *destroyed*; no hard lock in 10 back-to-back replays; no `FFSDEBUG` assertion fires.
- **Phase 2,** during the replay:
  - maximum `wakeprobe` lateness under 1 s;
  - every sshd banner within 2 s;
  - replay time and `slow.c` MB/s no worse than the Phase 0 baseline;
  - crash runs still have 0 *destroyed*.
- **No ppc testing** in this plan.

## Review Focus

1. **A crash run's QMP `quit` lands before the replay has started.** That produces a "clean" result that proves nothing. The run is invalid unless the guest had printed `REPLAY-START` first. Pinned by `test_crash_before_replay_start_is_invalid` in Task 1.
2. **A wedged guest leaves the run hanging forever.** Then there's no hard-lock capture and the harness never exits. `wakeprobe` silence of 60 s must trigger capture, then a quit, and the run is recorded as `hardlock`. Pinned by `test_silence_triggers_hardlock` in Task 1.
3. **fsck text that matches no rule.** The classifier must answer `manual`, never `clean`. Pinned by `test_unknown_fsck_text_is_manual` in Task 1.
4. **A test kernel that silently failed to boot,** so the guest fell back to the stock `/mach_kernel`. Results would be credited to the wrong kernel. The harness compares the booted `Kernel Release` stamp in `serial.log` with the stamp in the kernel file, and refuses to measure on a mismatch. Pinned by `test_kernel_stamp_mismatch_refuses` in Task 4.
5. **The NBC assertion on a file that was never mapped** (`v_vm_info == 0` or `!mapped`). That must not panic. Covered by Task 8's code step, and exercised by every replay, since most small files are written through `mapfs_io` but some are never mapped.

---

## Shared procedures

These are referenced by name from the tasks.

### Build a kernel ("run the build")

`W` is the main checkout's `D:/RhapsodiOS/vm/work/ffsbench`. `NAME` labels the build.

1. **Export the commit.**
   ```bash
   T=$W/tree-NAME
   mkdir -p $T
   git -c core.autocrlf=false archive <commit> src/kernel-7 | tar -x -C $T
   ```
   For an `FFSDEBUG` build, also run:
   ```bash
   sed -i 's/^\(#  RELEASE = \[.*\) nbc\]/\1 nbc ffsdebug]/' $T/src/kernel-7/conf/MASTER.i386
   grep -c ffsdebug $T/src/kernel-7/conf/MASTER.i386
   ```
   The `grep` must print `1`. This edit stays in the export and is never committed.
2. **Boot the build guest.**
   ```bash
   python $W/private/boot.py
   ```
   `$W/private/` holds copies of `vm/work/vmfix/private/boot.py` and the Port-aware `vm/*.ps1` helpers. In the copy, the ports are changed to 2531/4531 and `-name` to `RhapsodiOS ffs-build`.
3. **Point a scratch `vm.conf` at the export.**
   ```bash
   sed -e 's/^Port=.*/Port=2531/' -e 's|^RemoteRoot=.*|RemoteRoot=/build/ffs|' -e "s|^# LocalRoot=.*|LocalRoot=$T|" vm/vm.conf > $W/private/vm/vm.conf
   ```
4. **About 4 minutes after boot, sync once.**
   ```bash
   powershell -NoProfile -File $W/private/vm/sync-src.ps1 -Path kernel-7 < /dev/null
   ```
   Expected: `sync-src: complete`.
5. **Build and pull.** This takes about 20 minutes; run it in the background.
   ```bash
   powershell -NoProfile -File $W/ffs-kernel.ps1 -Out $W/mach_kernel-NAME < /dev/null > $W/build-NAME.log 2>&1
   ```
   `ffs-kernel.ps1` is a copy of `vm/work/vmfix/vmfix-kernel.ps1` with `/build/vmfix` replaced by `/build/ffs`. Expected log tail:
   - `rbuild: kernel complete`
   - a `guest cksum:` line
   - `pulled N bytes … matches guest`
6. **Quit the build guest** after its last build of the session: QMP `quit` on 4531, then `rm -f $W/private/vm/vm.conf`.

### Bench a kernel ("run the bench")

```bash
python vm/ffsbench.py bench --kernel $W/mach_kernel-NAME --label NAME --runs 3
python vm/ffsbench.py crash --kernel $W/mach_kernel-NAME --label NAME --runs 20
```
Both write under `$W/runs/NAME/`. `bench` prints the median CSV row; `crash` prints the tally per class. Both take hours; run them in the background, one at a time.

---

## Phase 0 — Harness

### Task 1: ffsbench pure logic

**Files:**
- Create: `vm/ffsbench.py`
- Create: `vm/test_ffsbench.py`

**Interfaces:**
- Produces:
  - `qemu_args(root_img: str, hd1: str, hd2: str, serial: str, ssh_port=2532, qmp_port=4532, gdb_port=1232, mem_mb=128) -> list[str]`
  - `parse_probe(line: str) -> ProbeSample | None`
  - `ProbeSample(t: float, late_ms: int, free: int, pageouts: int)`, a namedtuple
  - `summarize(samples: list[ProbeSample], banners: list[float | None]) -> dict` with keys `late_max_ms`, `late_p99_ms`, `banner_max_s`, `banner_missed`
  - `classify(fsck_n: str, preen_status: int) -> str`, one of `"clean"`, `"preen"`, `"manual"`, `"destroyed"`
  - `crash_valid(guest_log: str) -> bool`
  - `Watchdog(timeout_s=60)` with `.feed(now: float)` and `.expired(now: float) -> bool`
  - `CSV_HEADER: str` and `csv_row(label: str, run: dict) -> str`

**Formats these functions parse:**
- **`wakeprobe` lines:** `wp <sec> <late_ms_max> <free_pages> <pageouts>`, all integers, for example `wp 17 2350 412 8812`.
- **`classify` rules**, checked in this order:
  1. **destroyed:** `fsck_n` matches (case-insensitive) any of `BAD SUPER BLOCK`, `CANNOT READ` against block 16 (`BLK(S): 16`), `SEARCH FOR ALTERNATE SUPER-BLOCK`, `ROOT INODE UNALLOCATED`, `ROOT INODE NOT DIRECTORY`, `CANNOT ALLOCATE ROOT INODE`.
  2. **clean:** `fsck_n` contains `** Phase 5` and no line ending in `? no`, and `preen_status == 0`.
  3. **preen:** `preen_status == 0`.
  4. **manual:** everything else.
- **`crash_valid`** is true only if the guest log contains a line `REPLAY-START`.

- [ ] **Step 1: Write the failing tests** in `vm/test_ffsbench.py`. Each is one assertion block:
  - `test_qemu_args_snapshot_only_root`: `-snapshot` is absent; the hd0 `-drive` contains `snapshot=on`; hd1 and hd2 contain `snapshot=off`; `-m 128`; `hostfwd=tcp:127.0.0.1:2532-10.10.0.240:22`; `-gdb tcp:127.0.0.1:1232`; `-qmp tcp:127.0.0.1:4532,server=on,wait=off`.
  - `test_parse_probe`: `parse_probe("wp 17 2350 412 8812") == ProbeSample(17, 2350, 412, 8812)`. Both `parse_probe("garbage")` and `parse_probe("wp 1 2")` return `None`.
  - `test_summarize`: lateness `[10, 20, 3000]`, banners `[0.1, None, 1.5]` → `late_max_ms == 3000`, `banner_max_s == 1.5`, `banner_missed == 1`.
  - `test_classify_destroyed`: `classify("** /dev/hd1a\nBAD SUPER BLOCK: MAGIC NUMBER WRONG\n", 8) == "destroyed"`.
  - `test_classify_clean`: phase 1–5 output with no `? no` line, status 0 → `"clean"`.
  - `test_classify_preen`: output containing `FREE BLK COUNT(S) WRONG IN SUPERBLK\nSALVAGE? no`, status 0 → `"preen"`.
  - `test_unknown_fsck_text_is_manual`: `classify("something new\n", 8) == "manual"`.
  - `test_crash_before_replay_start_is_invalid`: `crash_valid("booted\n") is False`; `crash_valid("x\nREPLAY-START\n") is True`.
  - `test_silence_triggers_hardlock`: `w = Watchdog(60)`, `w.feed(100)` → `w.expired(159.9) is False`, `w.expired(160.1) is True`.
  - `test_csv_row_matches_header`: the comma count in `csv_row("x", run)` equals the comma count in `CSV_HEADER`. `CSV_HEADER` is `label,replay_s,rm_s,slow1_mbs,slow2_mbs,late_max_ms,late_p99_ms,banner_max_s,banner_missed`.
- [ ] **Step 2: Confirm they fail.** Run `cd vm && python -m pytest test_ffsbench.py -q`. Expected: errors on `import ffsbench`.
- [ ] **Step 3: Implement the functions above in `vm/ffsbench.py`.**
  - `qemu_args` starts from the command line in `vm/work/vmfix/private/boot.py`: `-cpu pentium`, `ne2k_pci` with `mac=52:54:00:12:34:56`, `net=10.10.0.0/16`, `-rtc base=utc`.
  - It uses per-drive `snapshot=` flags instead of the global `-snapshot`, because hd1 must persist (memory: qemu-blkdebug-fault-injection-dr2).
  - The second `-serial` is `file:<serial>`.
  - `late_p99_ms` is the nearest-rank p99.
- [ ] **Step 4: Confirm they pass.** Run `cd vm && python -m pytest test_ffsbench.py -q`. Expected: all pass.
- [ ] **Step 5: Commit.**
  ```bash
  git add vm/ffsbench.py vm/test_ffsbench.py
  git commit -m "vm: ffsbench parsing, fsck classification and QEMU command line"
  ```

### Task 2: Guest programs and disk images

**Files:**
- Create: `tests/ffsbench/wakeprobe.c`
- Create: `tests/ffsbench/run.sh`
- Create: `tests/ffsbench/crash.sh`
- Modify: `vm/ffsbench.py` (add the image builders)
- Modify: `vm/test_ffsbench.py`

**Interfaces:**
- Consumes: `ufs_build.build(template_path, nodes, total_frags=None, medium_sectors=None) -> bytes`, `ufs_extract.Node`, `rhap_image.Image`, and `hfs_guest.TEMPLATE` for the label and geometry.
- Produces:
  - `build_scratch(path: str, mb: int = 1024) -> None`: an empty UFS with only `/`.
  - `build_workload(path: str, apk_dir: str, replay: list[str], kernel: str, slow_c: str) -> None`: holds `/apks/*`, `/replay.list`, `/wakeprobe.c`, `/slow.c`, `/run.sh`, `/crash.sh` and `/mach_kernel.ffs`.
  - Guest scripts print fixed markers that the host waits for: `PROBE-BUILT`, `REPLAY-START`, `REPLAY-END <seconds>`, `RM-END <seconds>`, `SLOW1 <MB/s>`, `SLOW2 <MB/s>`, `RUN-END`.

**What the guest pieces do:**
- **`wakeprobe.c`:**
  - Loop on `usleep(100000)`. After each sleep, take `gettimeofday` and track how late the wakeup was.
  - Once per second print a `wp` line (Task 1 format) and `fflush`. Free pages and pageouts come from `vm_statistics(task_self(), &s)` (`s.free_count`, `s.pageouts`). That is the Mach 2.5 equivalent of the spec's `host_statistics(HOST_VM_INFO)`.
  - Run until killed.
- **`run.sh`** (Bourne shell; DR2 `/bin/sh` has no `type` builtin). Arguments: hd1 mount point `/mnt1`, hd2 mount point `/mnt2`.
  1. `cc -O -o /tmp/wakeprobe /mnt2/wakeprobe.c` and `cc -O -o /tmp/slow /mnt2/slow.c`, then echo `PROBE-BUILT`.
  2. Start `/tmp/wakeprobe &`.
  3. `mkdir /mnt1/root /mnt1/tmp`, then echo `REPLAY-START`.
  4. For each line of `/mnt2/replay.list`:
     ```sh
     s=/mnt1/tmp/stage.$n; mkdir $s
     gzip -dc /mnt2/apks/$apk | (cd $s && pax -r -pe)
     (cd $s && pax -rw -pe . /mnt1/root)
     rm -rf $s
     ```
     Time the whole loop with `date +%s` before and after, then echo `REPLAY-END <s>`.
  5. Time `rm -rf /mnt1/root` → `RM-END <s>`.
  6. Run `/tmp/slow /mnt1/s 64` and turn its two "Transferred" lines into `SLOW1 <MB/s>` and `SLOW2 <MB/s>`.
  7. Kill `wakeprobe`, then echo `RUN-END`.
- **`crash.sh`:** steps 1–4 of `run.sh` only. The host kills QEMU during step 4.

- [ ] **Step 1: Write the failing tests.**
  - `test_build_scratch_is_clean`: build a 64 MB scratch image in `tmp_path`, then `ufs_check.check(path) == []`.
  - `test_build_workload_contents`: build with two dummy apks and a dummy kernel. `rhap_image` resolves `/replay.list`, `/run.sh`, `/mach_kernel.ffs` and `/apks/<name>` to inodes, and `/replay.list` reads back as the two names in order.
- [ ] **Step 2: Confirm they fail.** `python -m pytest test_ffsbench.py -q -k build`. Expected: `AttributeError`.
- [ ] **Step 3: Implement `build_scratch` and `build_workload`,** using `ufs_build.build` the way `hfs_guest.results_disk` does. Size the workload image from the total input bytes plus 25%. Write `wakeprobe.c`, `run.sh` and `crash.sh` as described above.
- [ ] **Step 4: Confirm they pass.** `python -m pytest test_ffsbench.py -q`. Expected: all pass. If the template asset is absent, these tests skip, the same way `test_hfs_guest.py` does.
- [ ] **Step 5: Commit.**
  ```bash
  git add tests/ffsbench vm/ffsbench.py vm/test_ffsbench.py
  git commit -m "vm: ffsbench guest replay scripts, wakeup probe and disk images"
  ```

### Task 3: Capture the workload

This task produces data, not code. Nothing is committed.

**Files:**
- Create (gitignored): `$W/apks/`, `$W/replay.list`, `$W/apks.sha256`, `$W/slow.c`

- [ ] **Step 1: Get the apk list.** Boot the build guest (build procedure, steps 2–3). Run the i386 `rbuild kernel` command from memory bootstrapped-i386-guest-kernel-build, but as `rbuild -n kernel …` with a fresh `--state` directory. Save the output to `$W/rbuild-n.txt`.
  - Expected: lines `validate APK <path> for i386 and install`.
  - `grep 'and install' $W/rbuild-n.txt | awk '{print $3}' > $W/replay.paths` gives the ordered list.
- [ ] **Step 2: Pull the apks** with one `guest-remote.ps1 -Fetch` per path into `$W/apks/`. Write the basenames, in order, to `$W/replay.list`, and run `sha256sum $W/apks/* > $W/apks.sha256`.
  - Expected: one file per listed path, none empty.
- [ ] **Step 3: Get `slow.c`.**
  ```bash
  curl -sL -o $W/slow.c "https://web.archive.org/web/20060702154633id_/http://www.jburgess.uklinux.net/slow.c"
  sed -i 's/fdatasync(/fsync(/' $W/slow.c
  ```
  Expected: `grep -c fsync $W/slow.c` prints `1`, and the file is 3747 bytes before the edit.
- [ ] **Step 4: Quit the build guest** as in build procedure step 6.

### Task 4: Bench and crash drivers

**Files:**
- Modify: `vm/ffsbench.py` (add the `bench`, `crash` and `capture` subcommands)
- Modify: `vm/test_ffsbench.py`

**Interfaces:**
- Consumes: Task 1's functions, Task 2's builders and markers, and Task 3's `$W` data. Also `qemu-shot.py`'s `QMP` class and `chars_to_qcodes`, loaded through `importlib` the way `hfs_guest._guest_console` loads its module.
- Produces:
  - `kernel_stamp(path_or_text: bytes) -> str`: returns the `Kernel Release …;` match.
  - `banner_time(port: int, timeout: float = 10) -> float | None`: seconds until the first 4 bytes received are `SSH-`, or `None`.
  - CLI subcommands:
    - `bench --kernel K --label L --runs N`
    - `crash --kernel K --label L --runs N [--seed S]`
    - `capture --label L`: savevm, plus the gdbstub dump, by hand.

**How one boot is driven (shared by `bench` and `crash`):**
1. Refuse to start if a port is busy.
2. Build hd1 fresh: copy the pristine `$W/scratch.img`, which `build_scratch` made once. Build hd2 with `build_workload`, embedding `K`.
3. Start QEMU with `qemu_args`.
4. **First boot (stock kernel):** wait for sshd with one `banner_time` attempt every 30 s, at most 10. Then run, in one ssh session:
   - `mknod` the hd1 and hd2 nodes if missing: block major 3, minors 8 and 16, as in `hfs_guest.boot`;
   - `mount -r /dev/hd2a /mnt2`;
   - `cp /mnt2/mach_kernel.ffs /mach_kernel.ffs`;
   - `/sbin/reboot`.

   The copy lands only in QEMU's snapshot overlay, which survives a guest reboot within the same QEMU process.
5. **Boot the test kernel.** At `boot:`, send `mach_kernel.ffs -v` plus Enter through QMP `send-key`. The booter accepts a kernel file name there (`src/boot-2/i386/boot2/boot.c` `getBootString`).
6. **Check the kernel stamp.** Once `serial.log` has the network prompt, check `kernel_stamp(serial.log)` against `kernel_stamp(K)`. On a mismatch, write `result.txt` saying `WRONG KERNEL`, quit, and exit non-zero.
7. **Run the workload** after sshd answers. Mount hd1 on `/mnt1` and hd2 read-only on `/mnt2`, then run `sh /mnt2/run.sh` (bench) or `sh /mnt2/crash.sh` (crash) through `vm/guest-remote.ps1 -Run`, using a scratch `vm.conf` with `Port=2532`.
   - Stream its stdout to `guest.log` with host timestamps.
   - Feed the `Watchdog` on every `wp` line.
   - Call `banner_time(2532)` every 5 s on a second thread.
8. **Hard lock:** if the watchdog expires, run `capture` (savevm `hang`, then a gdbstub dump of the registers and 4 KB below ESP to `gdb.txt`, then detach with `D`). Quit, and record the run as `hardlock`.
9. **Crash runs:**
   - Wait for `REPLAY-START`, then send QMP `quit` at `random.Random(seed + i).uniform(5, B)`, where `B` is the median `replay_s` of this kernel's bench rows or, without one, 600.
   - Then boot a fresh QEMU on the same hd1 with the stock kernel. In one ssh session run `fsck -n /dev/hd1a; echo PREEN; fsck -p /dev/hd1a; echo STATUS $?`.
   - Before that boot, copy hd1 to `run-<i>-hd1.img`. Delete the copy if `classify` returns `clean`.
   - A run where `crash_valid` is false is retried and not counted.
10. Every boot ends with QMP `quit` and leaves `serial.log`, `guest.log`, `result.txt` and, for bench runs, one CSV row in `$W/runs/L/bench.csv`.

- [ ] **Step 1: Write the failing tests.**
  - `test_kernel_stamp`: `kernel_stamp(b"xx Kernel Release 154.5.1-7 RELEASE_I386 Tue; yy") == "Kernel Release 154.5.1-7 RELEASE_I386 Tue;"`.
  - `test_kernel_stamp_mismatch_refuses`: `check_stamp(serial_text="… Kernel Release A;", kernel_bytes=b"Kernel Release B;")` raises `SystemExit`.
  - `test_banner_time_against_local_server`: a thread serving `SSH-2.0-x\r\n` on an ephemeral port → a float under 1. A server that accepts and then sends nothing within `timeout=1` → `None`.
- [ ] **Step 2: Confirm they fail.** `python -m pytest test_ffsbench.py -q`.
- [ ] **Step 3: Implement** `kernel_stamp`, `check_stamp(serial_text: str, kernel_bytes: bytes) -> None`, `banner_time`, and the three subcommands as described above.
- [ ] **Step 4: Confirm they pass.** `python -m pytest test_ffsbench.py -q`.
- [ ] **Step 5: Smoke test against a real guest.** Build the stock kernel from `master` with the build procedure (label `stock`). Then run:
  ```bash
  python vm/ffsbench.py bench --kernel $W/mach_kernel-stock --label smoke --runs 1
  ```
  Expected:
  - `guest.log` contains `PROBE-BUILT`, `REPLAY-START`, `REPLAY-END`, `RM-END`, `SLOW1`, `SLOW2` and `RUN-END`, or the run is recorded as `hardlock` with `gdb.txt` present;
  - `bench.csv` has one row;
  - `serial.log` shows the stock stamp.
- [ ] **Step 6: Commit.**
  ```bash
  git add vm/ffsbench.py vm/test_ffsbench.py
  git commit -m "vm: ffsbench bench and crash drivers for a private i386 guest"
  ```

### Task 5: Baseline

- [ ] **Step 1: Bench the stock kernel** (label `stock`, 3 runs), then crash it (20 runs).
- [ ] **Step 2: Create `docs/kernel/ffs-bsd-comparison.md`** with a `## Measurements` section holding:
  - the median `stock` CSV row;
  - the crash tally (clean / preen / manual / destroyed / hardlock);
  - the worst `wp` lines around the largest lateness, with free pages;
  - the `$W/apks.sha256` digest of `replay.list`.
- [ ] **Step 3: Commit.**
  ```bash
  git add docs/kernel/ffs-bsd-comparison.md
  git commit -m "docs: baseline FFS replay, responsiveness and crash results"
  ```
- [ ] **Step 4: Report the baseline to the user before Phase 1.** If the stock tally has 0 *destroyed* and 0 *hardlock*, say so. Then rerun the crash set with `bufpages` shrunk once Task 13 exists, or with blkdebug delays on hd1 (spec "Risks"). Ask which before continuing.

## Phase 1 — Corruption and hard lock

### Task 6: Reference comparison

This task can run in parallel with Tasks 1–5.

**Files:**
- Modify: `docs/kernel/ffs-bsd-comparison.md`

- [ ] **Step 1: Clone the references.**
  ```bash
  git clone --depth 1 -b releng/4.11 https://github.com/freebsd/freebsd-src F:/ref/freebsd-4
  git clone --depth 1 -b netbsd-2 https://github.com/NetBSD/src F:/ref/netbsd-2
  ```
  - FreeBSD's git has no `RELENG_4` branch. `releng/4.11` is the last 4.x release branch; record the commit hashes.
  - Expected: `F:/ref/freebsd-4/sys/kern/vfs_bio.c` and `F:/ref/netbsd-2/sys/kern/vfs_bio.c` exist.
  - xnu is at `F:/xnu-124.13`.
- [ ] **Step 2: Write the comparison** under `## Comparison`, one subsection per file:
  - `vfs_bio.c` and `vfs_cluster.c` against all three references;
  - the ufs/ffs write-path files against FreeBSD 4.x and NetBSD 2.0;
  - `kern/mapfs.c` plus every `MACH_NBC` hook on its own (`grep -rn MACH_NBC src/kernel-7/bsd/ufs src/kernel-7/bsd/vfs`), noting where `F:/xnu-124.13/bsd/kern/ubc_subr.c` handles the same case.

  Each divergence gets one table row: our function and line, reference function, *bug fix* / *performance* / *irrelevant*, one-line reason. Rows for Findings 1–3 in the spec must appear, and must quote the references' re-check code by file and line.
- [ ] **Step 3: Commit.**
  ```bash
  git add docs/kernel/ffs-bsd-comparison.md
  git commit -m "docs: compare our buffer cache, FFS and mapfs with FreeBSD 4, NetBSD 2 and xnu-124"
  ```
- [ ] **Step 4: Ask the user to approve new tasks.** Every *bug fix* row not covered by Tasks 10–11 becomes a new task appended to Phase 1, written in this plan's template. Get the user's approval before implementing it.

### Task 7: `FFSDEBUG` option and buffer-identity assertions

**Files:**
- Modify: `src/kernel-7/conf/MASTER`: add `options		FFSDEBUG	# FFS buffer and NBC assertions	# <ffsdebug>` after the `DIAGNOSTIC` line.
- Modify: `src/kernel-7/bsd/vfs/vfs_bio.c`: add `#include <ffsdebug.h>`, plus checks in `getblk`, `bgetvp` callers, `bwrite`, `biodone` and `cluster` paths.
- Modify: `src/kernel-7/bsd/vfs/vfs_cluster.c`: the cluster check.

**Interfaces:**
- Produces: `void ffsdebug_check_dup(struct vnode *vp, daddr_t blkno, struct buf *self)`, defined in `vfs_bio.c` under `#if FFSDEBUG`. It walks `BUFHASH(vp, blkno)` and panics with `"ffsdebug: duplicate buffer"` if a buffer other than `self` has the same `b_vp` and `b_lblkno` and is not `B_INVAL`.

- [ ] **Step 1: Write the "test".** There is no kernel unit-test harness, so the test is the harness itself plus a forced trip. Create the throwaway `$W/trip-dup.py`, which edits an export so that `getblk` skips `incore()` once in every 64 calls. That creates duplicates on purpose.
- [ ] **Step 2: Add the four checks.** All `panic` messages start `ffsdebug: `.
  - **Duplicate identity:** call `ffsdebug_check_dup(vp, blkno, bp)` at both `getblk` exits.
  - **Superblock:** in `bwrite`, when `bp->b_vp->v_type == VBLK` and `bp->b_blkno == SBLOCK` (`SBOFF / DEV_BSIZE` on i386 as in `ffs_sbupdate`), panic unless the `fs_magic` field equals `FS_MAGIC` or `NXSwapLong(FS_MAGIC)`.
  - **`biodone`:** panic if `bp->b_vp == NULL` on a non-`B_RAW`, non-`B_CALL` buffer, or if `B_INVAL` and `B_DELWRI` are both set.
  - **Cluster:** in `vfs_cluster.c`'s write-cluster builder, panic if component `i` has a `b_blkno` other than `first->b_blkno + i * btodb(size)`.
- [ ] **Step 3: Check the trip.** Build an `FFSDEBUG` kernel from the export with `trip-dup.py` applied (label `trip`), then run `bench --runs 1`. Expected: `serial.log` contains `ffsdebug: duplicate buffer`.
- [ ] **Step 4: Check the clean build.** Build an `FFSDEBUG` kernel without the trip (label `dbg0`) and run `bench --runs 1`. Expected: the run completes or reproduces a real panic. Record either outcome in `ffs-bsd-comparison.md` `## Measurements`.
- [ ] **Step 5: Check that the RELEASE build is unchanged.** Build without `ffsdebug` (label `rel0`) and confirm a `bench --runs 1` completes.
- [ ] **Step 6: Commit.**
  ```bash
  git add src/kernel-7/conf/MASTER src/kernel-7/bsd/vfs/vfs_bio.c src/kernel-7/bsd/vfs/vfs_cluster.c
  git commit -m "kernel: FFSDEBUG assertions for duplicate buffers, superblock writes and clusters"
  ```

### Task 8: `FFSDEBUG` NBC truncation assertion

**Files:**
- Modify: `src/kernel-7/bsd/ufs/ffs/ffs_inode.c`, in `ffs_truncate` after the `MACH_NBC` `mapfs_trunc` calls (about lines 234–246).

**Interfaces:**
- Consumes: `struct vm_info` (`kern/mapfs.h:76`: `object`, `mapped`, `vnode_size`) and `vm_page_lookup(vm_object_t, vm_offset_t)`.

The spec puts this check "when `ffs_alloc` hands out a block for metadata". It sits here instead, at the end of `ffs_truncate`, because `ffs_alloc` can't tell which file last held a block. A truncated file whose freed blocks still have resident mapped pages is the precondition for a stale page landing on a reallocated block, and that can be checked at this point.

- [ ] **Step 1: Confirm the offset convention.** Read `mapfs_io` (`kern/mapfs.c:1085`) to confirm that the object offset equals the file offset. Write the answer, with line numbers, into the commit body. If they differ, adjust the lookup offset accordingly.
- [ ] **Step 2: Add the check.** Under `#if FFSDEBUG && MACH_NBC`: when `vp->v_vm_info != NULL`, `->mapped` is set and `->object != NULL`, call `vm_page_lookup(object, off)` for every page offset from `round_page(length)` up to the old size. Panic with `"ffsdebug: page past truncation"` if any lookup returns a page. Files that are not mapped skip the check (Review Focus 5).
- [ ] **Step 3: Verify.** Build an `FFSDEBUG` kernel (label `dbg1`) and run `bench --runs 1` plus `crash --runs 5`. Record any panic in `## Measurements`.
- [ ] **Step 4: Commit.**
  ```bash
  git add src/kernel-7/bsd/ufs/ffs/ffs_inode.c
  git commit -m "kernel: FFSDEBUG check that truncation leaves no mapped pages past EOF"
  ```

### Task 9: Confirm the hypotheses

- [ ] **Step 1: Run the full set on the debug kernel.** Run `bench --runs 3` and `crash --runs 20` on `dbg1`.
- [ ] **Step 2: Record what fired.** In `## Measurements`, write which assertions fired, their stacks from `serial.log`, and any `hardlock` `gdb.txt` with the blocked threads' `wait_mesg` (offset `+0x50`; memory: i386-guest-kernel-debugging-gdbstub).
- [ ] **Step 3: Report to the user and wait for a decision.**
  - If the duplicate check fired, Tasks 10–11 are confirmed.
  - If only the NBC check fired, stop. A `mapfs` fix needs its own task, approved by the user, and Phase 3's UBC question becomes live.
- [ ] **Step 4: Commit.**
  ```bash
  git add docs/kernel/ffs-bsd-comparison.md
  git commit -m "docs: FFSDEBUG results on the rbuild replay"
  ```

### Task 10: `getblk` re-checks the hash after sleeping

**Files:**
- Modify: `src/kernel-7/bsd/vfs/vfs_bio.c`, `getblk` (lines 601–640).

- [ ] **Step 1: Confirm the failure on record.** Task 9's duplicate panic, or Task 7's trip, is the failing test. Name its run directory in the commit body.
- [ ] **Step 2: Implement the fix.** In the miss path, after `getnewbuf` returns a buffer:
  1. Raise to `splbio()` and call `incore(vp, blkno)`.
  2. If the block now exists, set `B_INVAL` on the new buffer, `brelse` it, and `goto start`.
  3. Otherwise, under the same `splbio`, set `b_blkno`/`b_lblkno`, `bgetvp`, and `binshash` before `allocbuf`.

  This follows the FreeBSD 4.x `gbincore` re-check and NetBSD's ordering. Cite their lines from Task 6 in a short comment.
- [ ] **Step 3: Verify.** Build `FFSDEBUG` (label `fix1`), then run `bench --runs 3` and `crash --runs 20`. Expected: no `ffsdebug: duplicate buffer` in any `serial.log`. Record the tally.
- [ ] **Step 4: Commit.**
  ```bash
  git add src/kernel-7/bsd/vfs/vfs_bio.c
  git commit -m "kernel: getblk rechecks the buffer hash after getnewbuf may have slept"
  ```

### Task 11: `allocbuf` waits instead of spinning

**Files:**
- Modify: `src/kernel-7/bsd/vfs/vfs_bio.c`, `allocbuf` (line 686).

- [ ] **Step 1: Implement the change.** Replace `while ((nbp = getnewbuf(0, 0)) == NULL) ;` with:
  ```c
  while ((nbp = getnewbuf(0, 0)) == NULL)
  	(void) tsleep(&needbuffer, PRIBIO + 1, "allocbuf", hz);
  ```
  so each retry waits for a `brelse` wakeup, or at most one tick, instead of re-entering `getnewbuf` immediately. Callers assume the requested size, so `allocbuf` cannot give up and return a smaller buffer.

  If Task 9's `gdb.txt` shows a cycle here (threads in `allocbuf`, each holding the busy buffer another wants), this is not enough. Write the FreeBSD/NetBSD structure as a new task instead, and get it approved. In that structure, buffers are sized from a page pool, not stolen from other buffers.
- [ ] **Step 2: Verify.** Build (label `fix2`) and run 10 back-to-back `bench --runs 1` plus `crash --runs 20`. Expected: 0 `hardlock`.
- [ ] **Step 3: Commit.**
  ```bash
  git add src/kernel-7/bsd/vfs/vfs_bio.c
  git commit -m "kernel: allocbuf sleeps for a free buffer instead of spinning"
  ```

### Task 12: Phase 1 exit check and byte-order regression

- [ ] **Step 1: Run the exit set.** Build the final Phase 1 commit both as `FFSDEBUG` (label `p1dbg`) and plain (label `p1`). On `p1dbg`: `crash --runs 20` and 10 × `bench --runs 1`. On `p1`: `bench --runs 3`.
  - Expected, per the Phase 1 exit criteria: 20/20 `preen` or `clean`, 0 `hardlock`, no `ffsdebug:` line.
- [ ] **Step 2: Byte-order check.** Run `python vm/ffsbench.py endian --kernel $W/mach_kernel-p1 --image <path to rhapsody.img>`. This new subcommand:
  1. attaches a copy of the big-endian MOSXS image as hd1;
  2. mounts its UFS partition read-only and runs `find /mnt1 -type f | wc -l`;
  3. remounts read-write, creates 100 files in `/mnt1/tmp/ffsbench`, deletes them, unmounts;
  4. runs `fsck -n`.

  Expected: a non-zero file count, and `classify(...) == "clean"`. Locating the partition's device minor is part of this step; memory mosxs-12v3-ppc-image describes the APM + NeXT label layout. Commit the subcommand with a unit test on its argument handling.
- [ ] **Step 3: Record and commit.** Write the results into `## Measurements`.
  ```bash
  git add vm/ffsbench.py vm/test_ffsbench.py docs/kernel/ffs-bsd-comparison.md
  git commit -m "docs: Phase 1 FFS exit results and reverse-endian check"
  ```

## Phase 2 — Stall and throughput

Every Phase 2 task ends by benching its kernel (`bench --runs 3`, `crash --runs 20`) and adding a row to `## Measurements`. A change that makes any exit-criteria column worse than the previous row is reverted, not committed.

### Task 13: `bufpages` boot argument, then measure pool size

**Files:**
- Modify: `src/kernel-7/machdep/i386/i386_init.c:64-73`: add `"bufpages", &bufpages,` to `kernargs[]` after `"nbuf"`, and declare `extern int bufpages;`.

- [ ] **Step 1: Add the entry.** Build (label `bp`).
- [ ] **Step 2: Add `--bootargs`.** Give `ffsbench.py bench` a `--bootargs STR` option that is appended to the typed `mach_kernel.ffs -v` line, with a unit test that `boot_line("x")` returns `"mach_kernel.ffs -v x"`.
- [ ] **Step 3: Measure three pool sizes.** On a 128 MB guest, 655 pages is 2%. Bench `bufpages=1638` (5%) and `bufpages=3276` (10%).
- [ ] **Step 4: Commit and ask.**
  ```bash
  git add src/kernel-7/machdep/i386/i386_init.c vm/ffsbench.py vm/test_ffsbench.py docs/kernel/ffs-bsd-comparison.md
  git commit -m "kernel: accept a bufpages boot argument on i386"
  ```
  Changing the default `mem_size / 50` in `machdep/i386/unix_startup.c:128` is a separate one-line commit. Make it only if 5% or 10% improves the exit columns, and only after the user approves the chosen value.

### Task 14: `getnewbuf` prefers clean buffers and bounds its flushing

**Files:**
- Modify: `src/kernel-7/bsd/vfs/vfs_bio.c`, `getnewbuf` (lines 753–846).

**Interfaces:**
- Produces: `#define GETNEWBUF_FLUSH_MAX 8`. This is the most delayed writes one call may start.

- [ ] **Step 1: Implement the change.** When the head candidate is `B_DELWRI`:
  - scan that queue, then the other one, for the first buffer that is not `B_DELWRI`, and take it;
  - only if none exists, start `bawrite` on up to `GETNEWBUF_FLUSH_MAX` delayed buffers, then `tsleep(&needbuffer, slpflag|(PRIBIO+1), "getnewbuf", slptimeo)` and return 0.

  The existing `getblk` loop retries.
- [ ] **Step 2: Bench** (label `gnb`). Record the row.
- [ ] **Step 3: Commit.**
  ```bash
  git add src/kernel-7/bsd/vfs/vfs_bio.c docs/kernel/ffs-bsd-comparison.md
  git commit -m "kernel: getnewbuf takes clean buffers first and flushes at most eight at a time"
  ```

### Task 15: Dirty-buffer and in-flight write throttling

**Files:**
- Modify: `src/kernel-7/bsd/vfs/vfs_bio.c` (`bdwrite`, `bwrite`, `biodone`, `bufinit`).

**Interfaces:**
- Produces these globals:
  - `int numdirtybuffers, hidirtybuffers, lodirtybuffers`: hi = `nbuf / 4`, lo = `nbuf / 8`, set in `bufinit`;
  - `long runningbufspace, hirunningspace`: hi = `1024 * 1024`.
- Maintenance:
  - `numdirtybuffers` changes on `B_DELWRI` set and clear;
  - `runningbufspace` grows by `b_bufsize` at write start in `bwrite` and shrinks in `biodone` for writes.

- [ ] **Step 1: Implement the throttles.**
  - In `bdwrite`, after marking dirty: while `numdirtybuffers > hidirtybuffers`, the calling process `bawrite`s the oldest delayed buffer of its own vnode if it has one, otherwise the head of `BQ_LRU`, until it is at or below `lodirtybuffers`.
  - In `bwrite`, before `VOP_STRATEGY`: while `runningbufspace > hirunningspace`, `tsleep(&runningbufspace, PRIBIO, "wdrain", 0)`. `biodone` calls `wakeup(&runningbufspace)` when it drops below half of `hirunningspace`.
  - These are FreeBSD 4.x `bd_wait` / `waitrunningbufspace`, cut down; cite the Task 6 rows.
- [ ] **Step 2: Bench** (label `thr`). Record the row.
- [ ] **Step 3: Commit.**
  ```bash
  git add src/kernel-7/bsd/vfs/vfs_bio.c docs/kernel/ffs-bsd-comparison.md
  git commit -m "kernel: throttle writers on dirty buffers and on writes in flight"
  ```

### Task 16: utimes update, only if FreeBSD 4.x does it asynchronously

**Files:**
- Modify: `src/kernel-7/bsd/ufs/ufs/ufs_vnops.c:492`.

- [ ] **Step 1: Check the comparison.** Look up the Task 6 row for `ufs_setattr`. If FreeBSD 4.x passes `waitfor = 0` for the utimes update, change our `VOP_UPDATE(vp, &atimeval, &mtimeval, 1)` to `0`. Otherwise skip this task and record "skipped: FreeBSD is synchronous too".
- [ ] **Step 2: Bench** (label `utm`). Record the row.
- [ ] **Step 3: Commit.**
  ```bash
  git add src/kernel-7/bsd/ufs/ufs/ufs_vnops.c docs/kernel/ffs-bsd-comparison.md
  git commit -m "kernel: write utimes inode updates asynchronously, as FreeBSD 4 does"
  ```

### Task 17: Mapped-page and syncer stalls

- [ ] **Step 1: Line up stalls with memory and sync.** Take the latest `bench` `guest.log`. Find each `wp` line with `late_ms > 1000`, and note its free-page count and its time relative to 30 s boundaries.
  - **Correlation with free pages under 5% of RAM or with 30 s boundaries:** go to Step 2.
  - **No correlation:** record "no mapped-page stall seen" and skip to Task 18.
- [ ] **Step 2: Find where the time goes.** Build a throwaway profiling export (`$W/prof-sync.py`, never committed). It prints the `time` deltas around `mapfs_sync`, `vmp_push_all` and `vm_pageout_scan`'s laundering when they exceed 500 ms. Bench it once and record which one dominates.
- [ ] **Step 3: Get a fix task approved.** Write a new task in this template for the dominant cause, using one of the spec's candidates:
  - a per-file dirty mapped-page limit that makes the writer push its own pages, in `mapfs_io`;
  - or spreading the 30 s sync.

  Get the user's approval before implementing it.

### Task 18: Phase 2 exit check

- [ ] **Step 1: Run the exit set.** Build the final Phase 2 commit plain (label `p2`) and `FFSDEBUG` (label `p2dbg`). Run `bench --runs 3` on `p2`, `crash --runs 20` on `p2dbg`, and `endian` on `p2`.
  - Expected: every Phase 2 exit criterion holds, and `endian` is clean.
- [ ] **Step 2: Commit.**
  ```bash
  git add docs/kernel/ffs-bsd-comparison.md
  git commit -m "docs: Phase 2 FFS exit results"
  ```

## Phase 3 — Decision

### Task 19: Backport recommendation

- [ ] **Step 1: Measure the async upper bound.** Bench `p2` once with the workload mounted async: give `run.sh` an `ASYNC=1` environment switch that mounts hd1 with `-o async`.
- [ ] **Step 2: Write `## Recommendation`** with three paragraphs, each citing measurements:
  - **Soft updates:** yes if the async `replay_s` is less than half of `p2`'s.
  - **Dirhash:** yes only if Task 17-style profiling showed `ufs_lookup` time. Otherwise no.
  - **UBC:** yes only if Phase 1 or Task 17 traced corruption or stalls to `mapfs`/`MACH_NBC` that could not be fixed in place. Include the spec's cost note.
- [ ] **Step 3: Commit.**
  ```bash
  git add tests/ffsbench/run.sh docs/kernel/ffs-bsd-comparison.md
  git commit -m "docs: recommend next FFS steps from the measured results"
  ```
- [ ] **Step 4: Hand over.** Tell the user the branch is ready for `superpowers:finishing-a-development-branch`.
