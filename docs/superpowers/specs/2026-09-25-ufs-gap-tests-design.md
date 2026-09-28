# UFS backport: closing the two verification gaps

## Goal

Demonstrate two claims the UFS backport
(`2026-09-21-ufs-xnu124-backport-design.md`) could only argue:

1. **A crashed machine comes up multi-user unattended.** The backport's Run 6
   never reached the kernel: `rc.boot`'s `fsck -p` stopped on the damage the
   kernel graft leaves behind, so the root gate was only shown from a shell
   (Run 6b).
2. **Change 2 works.** `ffs_reload` now releases the buffer when any of its
   three `bread` calls fails, sets `fs_ronly` back to 1 after copying the
   on-disk superblock, and re-applies the 4 GB `fs_maxfilesize` clamp. None of
   the three has been exercised.

The tests run on the fixed kernel only. A negative-control kernel with change
2 reverted was considered and declined.

## What makes each claim testable

**An image with the kernel installed as a real file.** `golden.img` passes
`ufs_check` with zero problems (checked read-only, 2026-09-25). A copy of it
can take a rebuilt `/mach_kernel` through `ufs_alloc`'s `grow_file`, which
rewrites the kernel's inode in place, allocating and freeing fragments, with
bitmaps, cylinder-group summaries and `fs_cstotal` maintained. Unlike
`graft-kernel.py`, this leaves no donor inode for `fsck -p` to stop on.

`golden.img`'s `/mach_kernel` is inode 1253202 with two links; the other is
`/private/tftpboot/mach_kernel`. `grow_file` keeps the inode, its mode and its
link count, so both names stay valid. `ufs_alloc.unlink` would not do: it
frees the inode whatever its link count.

**Injected read errors at exactly the right moment.** QEMU's `blkdebug`
driver, probed with `qemu-io` on 2026-09-25, supports a small state machine:
- In state 1, reads succeed.
- The first write to the disk moves it to state 2. There, every read covering
  one chosen sector fails with EIO (`once = off`), so driver retries fail too.
- A second write moves it to state 3. There, a dummy error rule on a sector
  nothing reads takes over as the active rule, so the real error stops. Without
  that dummy, a fired `once = off` rule stays active forever.

Both writes can come from the host, through QMP
`human-monitor-command` → `qemu-io <drive> "write ..."`. They land in padding
past the end of the filesystem, so the guest never writes to arm or disarm
anything.

**`fs_ronly` has a visible consequence.** `ffs_unmount` marks the filesystem
clean and writes the superblock whenever `fs_ronly == 0`
(`ffs_vfsops.c:806`). Before change 2, a reload on a read-only mount copied the
on-disk `fs_ronly`, which is 0 after any read-write mount. So a refused upgrade
followed by `umount` would have written a dirty, unchecked filesystem back as
clean.

## Design

### 1. Kernel, base image, and per-run disks

**Kernel.** Build a fresh i386 kernel from current master on a private
`-snapshot` build guest of `rhap-i386-bootstrapped.img`. Use the same recipe
as the post-merge ppc build of 2026-09-25, recorded in the xnu124-p0 ledger,
but with `--arch i386` and a source root holding only `kernel-7`. It takes
about 20 minutes. Fetch the apk, and extract `private/tftpboot/mach_kernel` (no leading
`./`). A tree-built kernel carries the serial console, so every run's kernel
messages reach `serial.log`.

**Base image.** `vm/work/ufs-e2e.img` is one copy of `golden.img` with that
kernel installed through `ufs_alloc`. It must pass two checks before any dirty
test runs:
- `ufs_check` reports zero problems;
- the guest's own `fsck -n /dev/hd0a`, from a single-user snapshot boot,
  reports nothing.

Nothing writes the base after that.

**Per-run disks.** Every boot runs on its own qcow2 overlay of the base
(`qemu-img create -f qcow2 -F raw -b ...`), so each run starts from the same
clean state. D: is 96% full (38 GB free), which rules out an 8 GB copy per
run. Where a run needs a dirty root, `qemu-io` writes `fs_clean = 0` into that
run's overlay; the base itself is never modified and restored.
`guest-console.py`'s `qemu_args` passes `format=qcow2` for `.qcow2` images
instead of its fixed `format=raw`.

**Isolation.** Persistent boots name their overlay through `RHAP_TEST_IMAGE`,
so `check_target` still refuses `golden.img`. Each run's QMP port is checked
free first. The build guest is shut down before the test boots start.

### 2. Gap 1: a crashed machine boots multi-user unattended

Every boot in this group uses the same keystrokes:
- `-v` at the `boot:` prompt, so `rc.boot`'s and `fsck`'s output stays on
  screen;
- `y` at the "Continue without network?" prompt, which clean boots also show.

A dirty boot passes if it reaches the same screen as the clean control with
**no extra keystrokes**. Screenshots are taken every 15 seconds through the
`fsck` phase, and kernel output is read from `serial.log`.

- **E1, clean control.** A plain boot of a fresh overlay. Expect the
  `serial_dbg: i386 kernel console up` banner, no `ffs: ` lines, and the Setup
  Assistant.
- **E2, flag-only dirty root.** An overlay with `fs_clean = 0` and nothing
  else wrong. A single-user snapshot boot first runs `fsck -n`, which must
  report no damage beyond the unclean state: the run's premise. Then a
  snapshot boot, unattended as in E1. Expect:
  - `fsck -p` checks root, finds nothing, and marks it clean without a reload;
  - exactly one `ffs: / was unclean when mounted; mounting read-write anyway`,
    and no refusal line;
  - the same end screen as E1.
- **E3, real power-off, three runs.** Each run uses a fresh overlay:
  1. Boot single-user, persistently, and run `mount -uw /`.
  2. Start `cp -R /usr/lib /private/tmp/<run>` in the foreground; the console
     keymap has no `&`, and the host kills QEMU on its own schedule anyway.
  3. Kill QEMU with QMP `quit`: after 15 seconds in the first run, 30 in the
     second and 60 in the third, to land at different points in the syncer's
     30-second cycle.
  4. Boot unattended as in E1, as a snapshot of the crashed overlay.

  Expect `fsck -p` to preen the real damage, printing each repair prefixed
  with the device name. Preen mode does not print `FILE SYSTEM WAS MODIFIED`.
  Then one of two things happens, and the run records which:
  - If `fsck` modified root, it reloads it through `MNT_RELOAD`. That runs
    `ffs_reload` on root, including change 2's `fs_ronly` fix. Root is then
    clean in memory, so `mount -uw /` prints no `ffs: ` line.
  - If `fsck` repaired only the clean flag, it does not reload, and the E2
    warning appears instead.

  Either way, the boot must reach the E1 end screen. Record what `fsck`
  repaired, from the screenshots. A follow-up single-user snapshot boot of
  the same crashed overlay runs `fsck -p`, whose output is then readable in
  full, and then `fsck -n`, which must report nothing.

**Only the crash boots write their overlay.** Every other boot is a snapshot.
A persistent boot that reaches the Setup Assistant has no shell to shut it
down cleanly, and killing it would dirty root again, confounding any
follow-up `fsck`. As snapshots, the unattended boot and its follow-up start
from the same state.

**When a boot stops, its cause decides the verdict.** A kernel refusal, panic
or hang is a **failure**. `fsck -p` declining to preen genuine damage (exit 8,
"Reboot failed - serious errors") is a **finding about `fsck` policy**. It is
recorded with the damage `fsck` named, not counted as a kernel result, and not
retried away.

### 3. Gap 2: change 2 on the fixed kernel

**Test disk.** Each run gets its own copy of a `make_badfs` image with
`fs_clean = 0`, plus 64 KiB of zero padding past the filesystem. It is attached
as `hd1` to a single-user boot of a base overlay. `make_badfs.reload_sectors`
reads the image's superblock and returns the first sector of each `ffs_reload`
read:
- the superblock, at partition start + 16 (`SBOFF` / 512);
- the cylinder summary, at `fsbtodb(fs_csaddr)`;
- the inode block holding the root inode, inode 2, at
  `fsbtodb(ino_to_fsba(2))`, which is `fs_iblkno` in cylinder group 0.

**R1–R3: the three `bread` calls, one run each.** The disk is attached through
`blkdebug`, with the error aimed at that run's sector.
1. `mount -r /dev/hd1a /mnt`, then **arm**.
2. `mount -uw /mnt`. Expect exactly one
   `ffs: /mnt superblock reload failed (5), refusing read-write upgrade`. The
   gate prints that wording for any reload error, and seeing it proves that the
   injected read hit `ffs_reload`.
3. **Disarm**, then `ls /mnt; mount`. `/mnt` should still be listed, and still
   read-only.
4. `mount -uw /mnt` again. It must return, refused with
   `ffs: /mnt not cleanly unmounted, refusing read-write upgrade; run fsck`.
   All three reads are on the device vnode. A buffer left busy by the failed
   read would make this reload's first step, `vinvalbuf(devvp, ...)`, sleep
   forever.
5. `umount /mnt` must return.

For R3, the root vnode is still in use while `mount -uw /mnt` runs, so Step 6
reads its inode block. If that run shows a plain "not cleanly unmounted"
refusal at step 2 instead of "reload failed", the injected read was never
reached, and the run fails.

**R4: `fs_ronly` (no injection).**
1. `mount -r /dev/hd1a /mnt`.
2. `mount -uw /mnt`, which is refused after a reload.
3. `umount /mnt`.
4. `mount /dev/hd1a /mnt`, read-write. Expect
   `ffs: filesystem not cleanly unmounted, refusing; run fsck`. Without the
   fix, step 3 would have written the filesystem back as clean, and this mount
   would have succeeded.

**R5: the 4 GB clamp.** First, the host checks that the test image's on-disk
`fs_maxfilesize` exceeds 4 GiB. If it doesn't, the clamp changes nothing, and
R5 cannot tell fixed from unfixed. Then:
1. `mount -r /dev/hd1a /mnt`.
2. `mount -uw /mnt`, which is refused.
3. `fsck -y /dev/hd1a`.
4. `mount -uw /mnt`, which succeeds. The in-memory `fs_clean` was still 0, so
   the gate reloaded first, and that reload re-applied the clamp.
5. `dd if=/dev/zero of=/mnt/below bs=2 count=1 seek=2147483647` must succeed,
   and `ls -l /mnt/below` must show 4294967296 bytes. That proves `dd` reaches
   64-bit offsets.
6. The same `dd` at `seek=2147483648` must fail with "File too large".

If step 5 shows `dd` cannot reach a 64-bit offset, R5 is recorded as
untestable with this userland. It is not counted as passed.

Every R run also requires no panic, and no `ffs: ` lines beyond those listed.

### 4. Files

Implementation happens in `.worktrees/ufs-gap-tests`.

- `vm/guest-console.py`: `qemu_args` uses `format=qcow2` for a `.qcow2` image.
  A `QemuArgsTest` case covers it.
- `vm/make_badfs.py`: `build_good` takes an optional padding size, and a new
  `reload_sectors(image)` computes the three read sectors from the
  superblock. Tests check those sectors against values worked out
  independently from the image.
- `vm/ufs-e2e-image.py` (new): copies `golden.img` to `vm/work/ufs-e2e.img`
  (refusing if the target exists), replaces `/mach_kernel` through `ufs_alloc`,
  and requires `ufs_check` to report zero problems.
- `vm/ufs_gap_lib.py` (new): what both run scripts share: paths, overlays,
  waiting on the serial log, and each run's `result.txt`.
- `vm/ufs-e2e-boot.py` (new): runs E1–E3 and the `fsck` follow-up boots. It
  covers overlay creation, dirtying an overlay's root with `qemu-io`, the
  keystroke sequences, and the QMP kills.
- `vm/ufs-reload-inject.py` (new): runs R1–R5. It covers building the test
  disk, writing the `blkdebug` config, and arming and disarming over QMP. The
  config text comes from a pure function, which has its own test.

**Evidence.** Each run writes `vm/work/ufs-gap/<run>/`, holding `serial.log`
and the screenshots. A run report goes in `.superpowers/sdd/`. The verdicts go
in this spec's Outcome, and the UFS spec's "The gap worth naming" gets a
pointer to them.

## Done when

1. The base image passes `ufs_check` with zero problems, and the guest's
   `fsck -n` reports nothing.
2. E1 and E2 pass.
3. Each E3 run reaches the end screen unattended, or stops on a documented
   `fsck`-policy finding, and never on a kernel failure. Each follow-up
   `fsck -n` reports nothing.
4. R1–R5 pass. R5 may instead be recorded as untestable because of `dd`, as
   described above.
5. The new unit tests pass.

## Risks

- **The IDE driver's handling of a hard read error is unknown.** It may retry,
  reset the controller, log, or panic. A panic is a finding about the driver,
  reported as such.
- **The booter must load a kernel that `ufs_alloc` placed.** The grafted kernel
  occupies a donor's blocks; this one gets freshly allocated fragments. If the
  booter cannot load it, the E runs stop until that is understood.
- **E3's damage varies from run to run.** That is why a stop needs a cause
  before it gets a verdict.
- **`dd`'s offset arithmetic, and the test image's `fs_maxfilesize`, are
  unverified.** R5 has an explicit untestable outcome for each.
- **Disk space.** The base image takes 8 GB of the 38 GB free. Overlays are
  small.

## Out of scope

- A negative-control kernel with change 2 reverted.
- Changes 5, 6 and 7, which remain argued for the reasons the UFS spec gives.
- All HFS work.
- Fixing anything these runs find. A kernel bug found here is reported with its
  evidence, and fixing it becomes a separate change for Pat to decide on.

At the end, Pat decides whether to keep the 8 GB base image.

## Outcome

Run on 2026-09-25 and 2026-09-27, from branch `ufs-gap-tests`. The kernel was an
i386 build of `kernel-7` as it stands on master at `b7cb931e0`; this branch
changes no kernel source. Every boot ran on a qcow2 overlay of the base image,
and the evidence for each run was copied, without the qcow2 overlays, to
`D:/RhapsodiOS/vm/work/ufs-gap/<run>/` (gitignored there). The per-run overlays
were not kept, since they only work with this worktree's base image.

### Verdicts

| Run | What it tests | Result |
|---|---|---|
| Gate | The base image is clean | **Pass**, on the second attempt. The first failed `fsck -n` Phase 5 because of a `ufs_alloc` bug, below. |
| E1 | Clean control | **Pass.** No `ffs: ` lines; network prompt at 39 s; Setup Assistant. |
| E2 | Flag-only dirty root | **Pass.** `fsck -p` checked root and found nothing. Exactly one `ffs: / was unclean when mounted; mounting read-write anyway`. Same end screen as E1, with no extra keystrokes. |
| E3 ×3 | Real power-off | **Pass** for all three, though the plan wanted `before-quit.png` to show the copy still running, and in all three runs it had finished. `fsck -p` preened genuine damage unattended and reloaded root, so no `ffs: ` line appeared, and the boot reached the Setup Assistant. The follow-up `fsck -p` repaired the same damage, and the `fsck -n` after it was clean. But the three runs were not independent; see below. |
| R1 | Superblock read fails in `ffs_reload` | **Pass.** |
| R2 | Cylinder-summary read fails | **Pass.** |
| R3 | Step 6 inode-block read fails | **Pass**, once retargeted; see below. |
| R4 | `fs_ronly` after a refused upgrade | **Pass.** |
| R5 | The 4 GB clamp after a reload | **Pass.** |

So both claims are now demonstrated rather than argued:
- A crashed machine comes up multi-user unattended. That holds both for a root that is dirty only in its flag, and for a root with real damage from a power-off.
- Change 2 works:
  - all three `bread` failure sites release their buffer;
  - `fs_ronly` stays 1, so an unmount does not write a dirty filesystem back as clean;
  - the 4 GB clamp survives a reload.

### Change 2 in detail

**R1–R3.** In each, the injected read reached `ffs_reload`, and the kernel printed `ffs: /mnt superblock reload failed (45), refusing read-write upgrade`. The gate prints that wording for any reload error. After the disarm:
- `/mnt` was still mounted read-only;
- the second `mount -uw` returned `ffs: /mnt not cleanly unmounted, refusing read-write upgrade; run fsck`;
- `umount` returned.

A buffer left busy by the failed read would have made that second reload's `vinvalbuf(devvp)` sleep forever.

The errno is **45**, not the EIO (5) blkdebug injects. The IDE driver reports its own code, which is `EOPNOTSUPP`, "Operation not supported", in this errno table.

**R4.** The sequence was: read-only mount, refused upgrade, unmount, then a direct read-write mount. That mount was refused with `ffs: filesystem not cleanly unmounted, refusing; run fsck`. So the unmount did not mark the dirty filesystem clean.

**R5.** After `fsck -y` and an upgrade through a reload:
- `dd ... bs=2 count=1 seek=2147483647` wrote 2 bytes, and `ls -l` showed 4294967296 bytes;
- `seek=2147483648` failed with `File too large`.

### What the runs found

- **`ufs_alloc` ignored FFS's `blksize` rule** (`fs.h`): a block past the 12 direct blocks is always a full block. `grow_file` therefore leaked 6 fragments of golden's old `/mach_kernel`, whose last block is full. That caused all three Phase 5 complaints at the first gate. `ufs_check` cannot see such a leak.
  - The allocation side had the same flaw. The new kernel escaped only because its tail needed all 8 fragments.
  - Fixed on this branch: one helper now drives allocation, freeing and layout.
  - A directory can no longer grow past its direct blocks, because that path still assumed the old rule.
  - With the fix, the rebuilt base frees exactly the old kernel's 1,440 fragments. Its gate `fsck -n` is clean.
  - Images written by the old `ufs_alloc` may hold a file past 12 blocks with a short last block; do not edit them with the new code, since its free path would release all 8 fragments of that block, which may since belong to another file - rebuild such images from golden.
- **QEMU's `-snapshot` covers every drive.** `Guest`'s global `-snapshot` also wrapped the injected test disk, so the host's arm and disarm writes landed in QEMU's temporary overlay, and blkdebug never fired. The test disk now carries `snapshot=off`. A paused-QEMU test proves the injection fires on the exact command line a run uses.
- **The stock DR2 IDE driver retries a failed read three times** before the kernel sees the error.
  - Each attempt takes about 90–100 s and prints `hc0: ATA command c4 failed. Retrying...` then `hc0: Resetting drives...`. The error reached `ffs_reload` 315 s after arming.
  - The plan's 10 s window ended long before the first retry, and a 66 s window let the retry succeed. The runner now waits for the reload's outcome, for up to 10 minutes.
- **The lookup of `/mnt` re-reads the root inode's block before the mount code runs.**
  - R3's first target was that block. The lookup hit the error first, and `mount -uw` failed with "Operation not supported" without calling `ffs_reload`, so no `ffs: ` line appeared.
  - R3 now holds a file open (`exec 3< /mnt/f69`), so its vnode is active, and it aims at that file's inode block, which only Step 6 reads.
  - Along the way this showed that a failed inode read during lookup also returns cleanly.
- **DR2 has no `/dev/zero`.** R5's `dd` reads its two bytes from `/mach_kernel`.
- **The three E3 crashes reached the same state.**
  - The copy of `/usr/lib` finished before every kill. A single-user system also runs no `update` daemon, so nothing was flushed in between.
  - All three `fsck -p` passes repaired the same 13 `INCORRECT BLOCK COUNT` inodes, plus `FREE BLK COUNT(S) WRONG`, `BLK(S) MISSING IN BIT MAPS` and `SUMMARY INFORMATION BAD`.
  - Every repair read `INCORRECT BLOCK COUNT ... SHOULD BE 104` - 12 direct blocks plus the indirect block - so those 13 copied files lost their data past 96 KiB, because the indirect block's pointers were never written. This is ordinary FFS behaviour after a crash, not a kernel bug.
  - The spread of 15, 30 and 60 s did not vary the crash point as the design intended. Varying it needs `update` started first and a larger tree copied, so that kills land mid-copy.
- **The kernel apk's member name varies.** This build had `./private/tftpboot/mach_kernel`, with a leading `./`.

### Still open

- Changes 5, 6 and 7 remain argued, as the UFS spec explains.
- An E3 variant whose kills land mid-copy and at different syncer phases.
- 41 `test_ufs_alloc.py` tests are golden-gated: 38 clone `golden.img` with `cp -c` (APFS clonefile), and 3 read it directly. None can run on this Windows host.
