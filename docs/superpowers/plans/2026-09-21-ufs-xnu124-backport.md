# UFS/FFS xnu-124 Correctness Backport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port seven UFS/FFS correctness fixes from xnu-124 into `src/kernel-7/bsd/ufs`, and demonstrate the three that change what the kernel refuses.

**Architecture:** Each fix is a few lines in `ffs_vfsops.c` or `ufs_readwrite.c`. Because the guest has no readable shell output channel, every new refusal also emits one `printf` line, which reaches the guest serial log and is the machine-readable evidence. Two harnesses drive the refusals: malformed 1.44MB UFS images attached as a second QEMU disk, and a one-byte mutation of the root work image.

**Tech Stack:** C (Darwin 0.3 BSD kernel), Python 3 on the Windows host for image generation, `rbuild` on the Rhapsody build box, QEMU 11.1.0 (`qemu-system-i386`), QMP send-key for guest input.

**Spec:** [2026-09-21-ufs-xnu124-backport-design.md](../specs/2026-09-21-ufs-xnu124-backport-design.md)

## Global Constraints

```text
REPO   = D:\RhapsodiOS
FFS    = src/kernel-7/bsd/ufs/ffs/ffs_vfsops.c
RW     = src/kernel-7/bsd/ufs/ufs/ufs_readwrite.c
RUNNER = vm/guest-console.py  (Guest class; launches its own qemu)
SERIAL = vm/out/<task>/serial.log  (written by Guest)
TMPL   = vm/install/rhapsody_dr2_x86_InstallationFloppy.img
```

Work in a dedicated worktree, not the main checkout. `.worktrees/` is gitignored.

```bash
git worktree add .worktrees/ufs-backport HEAD
```

- **The UEFI runners do not work.** `vm/firmware/OVMF32_CODE.fd` is absent and gitignored, so `run-q35-uefi.sh` and `run-pc-uefi-virtio-esp.sh` abort immediately.
- **Boot through `guest-console.py`'s `Guest` class, not through a `run-*.sh` script.** `Guest.__init__` (`vm/guest-console.py:64-88`) launches its own `qemu-system-i386` against the hardcoded `vm/work/test.img`, and it is the only mechanism in the tree that can both type into the guest (`.line()`) and screenshot it (`.shot()`). Starting a `run-*.sh` runner as well would give you two virtual machines. Attach extra disks with its `extra=` argument, which appends raw qemu arguments verbatim.
- **The serial log is `<outdir>/serial.log`**, where `outdir` is the first argument to `Guest` — not `vm/logs/ahci-serial.log`, which only the `run-*.sh` runners write. The kernel console is on the second serial port; `Guest` wires that to this file.
- **`Guest` runs with `-snapshot` unless `persist=True`.** Leave snapshots on: writes are discarded at exit, which is exactly what you want when deliberately mounting broken filesystems, and it keeps `work/test.img` reusable between tasks.
- **Every boot task must export `RHAP_TEST_IMAGE=D:/RhapsodiOS/vm/work/ufs-backport.img` first** (Task 2a added the override). Without it, `Guest` boots the shared `vm/work/test.img` and fights roughly a dozen concurrent sessions for it. The image lives in the main checkout's `vm/work/` because that is where `golden.img` is; the worktree's code reads the absolute path from the variable, so it does not matter that the worktree has no images of its own.
- **The guest cannot report errno to a script.** The serial console is output-only; input is synthetic keystrokes over QMP and the only output channel is a PNG screenshot. Every refusal added by this plan therefore emits a `printf`, because kernel `printf` does reach the serial log. Do not add a refusal without its log line.
- **Every new log line starts with `ffs: `** so the serial log can be grepped.
- **`graft-kernel.py` writes only to `vm/work/test.img`**, and always from a fresh copy — re-grafting an already-grafted image silently truncates at the shrunken donor size.
- **Never `git add -A`.** The tree carries many untracked `vm/_*.sh` scratch files. Stage named paths only.
- **Commits:** `kernel: ` prefix for kernel changes, `vm: ` for tooling, `docs: ` for the spec. One to two lines, no metadata.
- **Do not port** the `fs_bsize > PAGE_SIZE` check, the `vflush(SKIPSWAP)` two-phase unmount, the `ffs_radvisory` fragment fix, or `extern int prtactive`. The spec's "What does not port" table explains each; the last two would break readahead and the kernel link respectively.

### Superblock field offsets

Relative to `sb_off = image.part_start + rhap_image.SBOFF`, verified by reading `golden.img`:

| Field | Offset | Type |
|---|---|---|
| `fs_size` | +36 | int32 |
| `fs_dsize` | +40 | int32 |
| `fs_ncg` | +44 | int32 |
| `fs_bsize` | +48 | int32 |
| `fs_fsize` | +52 | int32 |
| `fs_fmod` | +208 | int8 |
| `fs_clean` | +209 | int8 |
| `fs_ronly` | +210 | int8 |
| `fs_magic` | +1372 | int32 (`0x00011954`) |

### Build and boot cycle

Every kernel task ends with this cycle. It is written once here; tasks refer to it as "the build cycle".

```powershell
powershell -File vm\sync-src.ps1 -Path kernel-7/bsd/ufs
```

On the Rhapsody build box:

```sh
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin; export PATH
rbuild kernel --state /build/state --arch i386 /build/src /build/repo /build/out
gzip -dc /build/out/kernel-154.5.1-7-i386.apk | tar xf - ./private/tftpboot/mach_kernel
```

Bring `mach_kernel` back to the host, then graft it into this branch's own
image. `graft-kernel.py` copies the source image first, so this refreshes from
`golden.img` every time and there is no `reset-image.cmd` step:

```bash
export RHAP_TEST_IMAGE=D:/RhapsodiOS/vm/work/ufs-backport.img
python vm/graft-kernel.py D:/RhapsodiOS/vm/golden.img <path-to-mach_kernel> \
    D:/RhapsodiOS/vm/work/ufs-backport.img
```

Always graft from `golden.img`, never from an already-grafted image — re-grafting
truncates at the shrunken donor size.

---

### Task 1: Malformed-image generator

Pure host-side Python. No kernel, no QEMU — this task is fully testable on Windows and gates the harness for Tasks 4 through 7.

**Files:**
- Create: `vm/make_badfs.py`
- Test: `vm/test_make_badfs.py`

**Interfaces:**
- Consumes: `ufs_build.build(template_path, nodes)` (`vm/ufs_build.py:150`), `ufs_extract.Node(path, kind, mode, uid, gid, mtime, data)` (`vm/ufs_extract.py:11`), `rhap_image.Image` and `rhap_image.SBOFF` (`vm/rhap_image.py:28,19`).
- Produces: `make_badfs.build_good(out_path) -> None` and `make_badfs.corrupt(out_path, field, value) -> None` where `field` is one of `"fs_clean"`, `"fs_fsize"`, `"fs_magic"`. Tasks 4-7 call these.

- [ ] **Step 1: Write the failing test**

```python
# vm/test_make_badfs.py
import os, struct, tempfile
import make_badfs, rhap_image

def _sb(path, off, fmt):
    img = rhap_image.Image(path)
    buf = img._read_at(img.part_start + rhap_image.SBOFF, 1536)
    img.close()
    return struct.unpack_from(fmt, buf, off)[0]

def test_build_good_is_a_valid_ufs_image():
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "good.img")
        make_badfs.build_good(out)
        assert os.path.getsize(out) == 1474560
        assert _sb(out, 1372, "<i") == 0x00011954
        assert _sb(out, 209, "<b") == 1

def test_corrupt_fs_clean_clears_only_that_byte():
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "dirty.img")
        make_badfs.build_good(out)
        make_badfs.corrupt(out, "fs_clean", 0)
        assert _sb(out, 209, "<b") == 0
        assert _sb(out, 1372, "<i") == 0x00011954

def test_corrupt_fs_fsize_and_magic():
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "bad.img")
        make_badfs.build_good(out)
        make_badfs.corrupt(out, "fs_fsize", 256)
        assert _sb(out, 52, "<i") == 256
        make_badfs.corrupt(out, "fs_magic", 0xDEADBEEF)
        assert _sb(out, 1372, "<I") == 0xDEADBEEF

def test_corrupt_rejects_unknown_field():
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "x.img")
        make_badfs.build_good(out)
        try:
            make_badfs.corrupt(out, "fs_nonsense", 1)
        except ValueError:
            return
        raise AssertionError("expected ValueError")
```

- [ ] **Step 2: Run it to make sure it fails**

Run from `vm/`: `python -m pytest test_make_badfs.py -v`
Expected: FAIL, `ModuleNotFoundError: No module named 'make_badfs'`

- [ ] **Step 3: Write the implementation**

```python
# vm/make_badfs.py
"""Build small UFS images and corrupt one superblock field, for kernel
mount-refusal testing. Writes only to caller-named paths; never touches
golden.img or vm/work/test.img."""

import os
import struct

import rhap_image
import ufs_build
import ufs_extract

TEMPLATE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "install", "rhapsody_dr2_x86_InstallationFloppy.img")

# offset, struct format
FIELDS = {
    "fs_fsize": (52, "<i"),
    "fs_clean": (209, "<b"),
    "fs_magic": (1372, "<I"),
}


def build_good(out_path):
    """Write a minimal single-cylinder-group UFS image with a clean superblock."""
    nodes = [ufs_extract.Node("/", "dir", 0o040755, 0, 0, 0, None)]
    data = ufs_build.build(TEMPLATE, nodes)
    with open(out_path, "wb") as f:
        f.write(data)
    _poke(out_path, "fs_clean", 1)


def corrupt(out_path, field, value):
    """Overwrite one superblock field in an existing image."""
    if field not in FIELDS:
        raise ValueError("unknown field %r; known: %s"
                         % (field, ", ".join(sorted(FIELDS))))
    _poke(out_path, field, value)


def _poke(out_path, field, value):
    offset, fmt = FIELDS[field]
    img = rhap_image.Image(out_path)
    sb_off = img.part_start + rhap_image.SBOFF
    img.close()
    with open(out_path, "r+b") as f:
        f.seek(sb_off + offset)
        f.write(struct.pack(fmt, value))
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run from `vm/`: `python -m pytest test_make_badfs.py -v`
Expected: 4 passed

- [ ] **Step 5: Commit**

```bash
git add vm/make_badfs.py vm/test_make_badfs.py
git commit -m "vm: generate small UFS images with one corrupted superblock field"
```

---

### Task 2a: Per-session test image

Added mid-execution. This machine routinely runs a dozen concurrent sessions,
and `vm/work/test.img` is a single shared file that `guest-console.py`
hardcodes and that `rhap_inject.check_target` treats as the sole permitted write
target. Running Tasks 2-9 against it would clobber other sessions' boot testing
and be clobbered in turn. CLAUDE.md section 6 asks for isolated images exactly
here.

The change is an opt-in override, not a relaxation: with the environment
variable unset, behaviour is byte-identical to today, so no other session is
affected.

**Files:**
- Modify: `vm/rhap_inject.py` (`check_target`, from `:23`)
- Modify: `vm/guest-console.py:18` (`IMAGE`)
- Test: `vm/test_rhap_inject.py`

**Interfaces:**
- Produces: the `RHAP_TEST_IMAGE` environment variable. Set to an absolute path,
  `check_target` additionally accepts that path and `guest-console.Guest` boots
  it. Unset, both behave exactly as before. Tasks 2-9 set it to
  `D:/RhapsodiOS/vm/work/ufs-backport.img`.

**The safety property that must not regress:** `check_target`'s second,
independent check refuses any target resolving to the same underlying file as
`golden.img` or `rhapsody.vmdk`. The override must not defeat it — pointing
`RHAP_TEST_IMAGE` at `golden.img` must still be refused. The override widens
which *path* is allowed, never which *file* may be destroyed.

- [ ] **Step 1: Write the failing tests**

`vm/test_rhap_inject.py` is `unittest`-based, not pytest-fixture based, and its
`TestSafety` class is gated `@unittest.skipUnless(os.path.exists(WORK))`. These
new tests must NOT go in that class: `check_target` is purely path-based and
tolerates missing files (`rhap_inject.py:48-58` skips the `samefile` check when
either side is absent), so they need no images and must run in a worktree that
has none. Add a new ungated class:

```python
class TestPerSessionImageOverride(unittest.TestCase):
    def test_override_accepts_the_named_image(self):
        with tempfile.TemporaryDirectory() as d:
            alt = os.path.join(d, "ufs-backport.img")
            with mock.patch.dict(os.environ, {"RHAP_TEST_IMAGE": alt}):
                rhap_inject.check_target(alt)  # must not raise

    def test_override_still_accepts_the_default_target(self):
        with tempfile.TemporaryDirectory() as d:
            alt = os.path.join(d, "ufs-backport.img")
            with mock.patch.dict(os.environ, {"RHAP_TEST_IMAGE": alt}):
                rhap_inject.check_target(WORK)  # must not raise

    def test_override_cannot_authorise_golden(self):
        with mock.patch.dict(os.environ, {"RHAP_TEST_IMAGE": GOLDEN}):
            with self.assertRaises(rhap_inject.SafetyError):
                rhap_inject.check_target(GOLDEN)

    def test_override_cannot_authorise_the_vmdk(self):
        with mock.patch.dict(os.environ, {"RHAP_TEST_IMAGE": VMDK}):
            with self.assertRaises(rhap_inject.SafetyError):
                rhap_inject.check_target(VMDK)

    def test_unset_override_refuses_an_arbitrary_path(self):
        with tempfile.TemporaryDirectory() as d:
            alt = os.path.join(d, "ufs-backport.img")
            env = {k: v for k, v in os.environ.items() if k != "RHAP_TEST_IMAGE"}
            with mock.patch.dict(os.environ, env, clear=True):
                with self.assertRaises(rhap_inject.SafetyError):
                    rhap_inject.check_target(alt)
```

- [ ] **Step 2: Run them and confirm they fail**

Run from `vm/`: `python -m pytest test_rhap_inject.py -k PerSessionImageOverride -v`
Expected: the first two FAIL (no override exists yet, so the alternate path is
refused). `test_unset_override_refuses_an_arbitrary_path` should already PASS,
confirming it is checking something real. The two "cannot authorise" tests will
also pass at this point for the wrong reason — the path check refuses them
because no override is honoured yet. They are the regression guard for Step 3,
which is where they start being meaningful.

- [ ] **Step 3: Implement the override in `check_target`**

Resolve `RHAP_TEST_IMAGE` through the same `os.path.realpath` plus
`os.path.normcase` treatment the default target gets, and accept the incoming
target when it matches either the default or the override.

The override must refuse to authorise the protected images **by resolved path**,
not only through the existing `samefile` loop. That loop at `rhap_inject.py:48-58`
skips whenever either file is absent, so on a checkout without `golden.img`
present an override aimed at it would otherwise sail through — and the whole
point of the guard is that it holds everywhere, not only where golden.img
happens to exist. So: if the resolved override equals the resolved `golden.img`
or `rhapsody.vmdk`, raise `SafetyError` regardless of existence.

Leave the existing `samefile` loop exactly where it is and applying to both
paths; it still catches links that resolve differently.

Update the docstring to record that an override exists and that it cannot
authorise `golden.img` or `rhapsody.vmdk`.

- [ ] **Step 4: Honour the same variable in `guest-console.py`**

`vm/guest-console.py:18` currently reads:

```python
IMAGE = os.path.join(HERE, "work", "test.img")
```

Replace with:

```python
IMAGE = os.environ.get("RHAP_TEST_IMAGE") or os.path.join(HERE, "work", "test.img")
```

- [ ] **Step 5: Prove nothing regressed**

Run the whole existing suite, not just the new tests — these files are in live
use by other sessions right now:

Run from `vm/`: `python -m pytest test_rhap_inject.py -v`
Expected: the five new tests pass. The pre-existing `TestSafety` class is
skip-gated on `work/test.img`, which does not exist in this worktree, so expect
those to report as skipped rather than passed — report the skip count. Any
pre-existing test that *fails* (rather than skips) means stop and report.

- [ ] **Step 6: Commit**

```bash
git add vm/rhap_inject.py vm/guest-console.py vm/test_rhap_inject.py
git commit -m "vm: allow an opt-in per-session test image via RHAP_TEST_IMAGE"
```

---

### Task 2: Positive control — SUPERSEDED, do not run

Attempted and abandoned. It booted `golden.img`'s stock 1999 Apple kernel, which
has no serial console (that is a RhapsodiOS addition to this tree —
`subr_prf.c:751`, `i386_init.c:126`) and none of this tree's EIDE fixes. It
therefore found no serial output and a single-user ATA wedge, neither of which
tells us anything about the kernel Tasks 4-8 actually run.

Its two questions — which device node a second disk gets, and whether kernel
output reaches `serial.log` — are folded into Task 3, which is the first task to
boot a kernel built from this tree.

One real finding survives and is now applied throughout: `g.line("-s")` must be
preceded by `time.sleep(6)`, or the leading `-` is swallowed and the loader
looks for a kernel named `s`. `fix_mouse()` and `probe()` in
`vm/guest-console.py` both do this; the earlier draft of this plan did not.

**Files:**
- Create: `vm/work/good-control.img` (generated, not committed)
- Read: `vm/guest-console.py:64-88` (how `Guest` launches qemu and where `extra=` lands)

**Interfaces:**
- Consumes: `make_badfs.build_good` from Task 1.
- Produces: two facts every later task depends on — the second-disk device node (expected `/dev/hd1a`; confirm rather than assume), and confirmation that kernel console output actually reaches `out/task2/serial.log`, which is the evidence channel for every refusal in Tasks 4-7.

- [ ] **Step 1: Build a known-good small image**

```bash
cd vm && python -c "import make_badfs; make_badfs.build_good('work/good-control.img')"
```

- [ ] **Step 2: Boot to a single-user shell with the control disk attached**

`Guest` launches its own qemu against the hardcoded `vm/work/test.img`, so there
is no runner script to invoke and no image argument to pass. The control image
goes on as the IDE slave through `extra=`. Snapshot mode is on by default, so
nothing you do in the guest touches `work/test.img` on disk.

```python
# run from vm/
import importlib.util, pathlib, time
spec = importlib.util.spec_from_file_location("guest_console", pathlib.Path("guest-console.py"))
gc = importlib.util.module_from_spec(spec); spec.loader.exec_module(gc)

g = gc.Guest("out/task2", extra=(
    "-drive", "file=work/good-control.img,format=raw,if=ide,index=1,media=disk",
))
g.line("-s"); time.sleep(135)          # boot prompt -> single user
g.line("mount /dev/hd1a /mnt"); time.sleep(5); g.shot("mount-hd1a")
g.line("df"); time.sleep(3); g.shot("df")
```

The 135-second sleep is copied from the working `fix_mouse()` template
(`vm/guest-console.py:165-201`), not guessed.

- [ ] **Step 3: Confirm the kernel console reaches the serial log**

Run: `grep -c . vm/out/task2/serial.log`
Expected: a non-zero count, with recognisable kernel boot output in the file.

This is not a formality. Every refusal in Tasks 4-7 is verified by grepping this
file for a `printf` the kernel emits. If kernel output does not land here, that
whole evidence strategy is void and the plan needs rethinking before any kernel
change is made — stop and say so rather than continuing.

- [ ] **Step 4: Read the screenshots and record the device node**

Open `vm/out/task2/mount-hd1a.png` and `df.png`. Expected: the mount succeeds silently and `df` lists `/mnt`. If `mount` reports no such device, retry with `/dev/hd1b`, then `/dev/hd2a`, until one succeeds.

Write the working node into the checkbox below before continuing.

- [ ] **Step 5: Record the result**

Tasks 4 through 8 are written against `/dev/hd1a`. If Step 4 found a different
node, edit those tasks to match before running them — the mount commands are
otherwise correct as written.

- [ ] **Step 6: Commit only if the node differed**

If Step 4 found `/dev/hd1a`, there is nothing to commit — the plan already says
that. Skip this step.

If it found a different node and you edited Tasks 4-8 in Step 5:

```bash
git add docs/superpowers/plans/2026-09-21-ufs-xnu124-backport.md
git commit -m "vm: correct the second-disk device node in the UFS harness plan"
```

---

### Task 3: The three inert fixes

Changes 2, 6 and 7 from the spec. None alters what the kernel accepts or refuses, so they share one build cycle and one regression boot. Grouped because a reviewer would accept or reject them together on inspection.

**Files:**
- Modify: `src/kernel-7/bsd/ufs/ffs/ffs_vfsops.c:337`, `:382`
- Modify: `src/kernel-7/bsd/ufs/ufs/ufs_readwrite.c:145`, `:301`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Release the buffer on the first reload failure**

`ffs_vfsops.c:337` currently reads:

```c
	if (error = bread(devvp, (ufs_daddr_t)(SBOFF/size), SBSIZE, NOCRED,&bp))
		return (error);
```

Replace with:

```c
	if (error = bread(devvp, (ufs_daddr_t)(SBOFF/size), SBSIZE, NOCRED,&bp)) {
		brelse(bp);
		return (error);
	}
```

- [ ] **Step 2: Release the buffer on the second reload failure**

`ffs_vfsops.c:382` currently reads:

```c
		if (error = bread(devvp, fsbtodb(fs, fs->fs_csaddr + i), size,
		    NOCRED, &bp))
			return (error);
```

Replace with:

```c
		if (error = bread(devvp, fsbtodb(fs, fs->fs_csaddr + i), size,
		    NOCRED, &bp)) {
			brelse(bp);
			return (error);
		}
```

Do **not** touch the `bread` calls at `:519`, `:561` or `:623`. Those are in `ffs_mountfs`, whose `out:` label at `:679` already does `if (bp) brelse(bp)`, and `:561` releases explicitly. Adding a second `brelse` there would be a double release.

- [ ] **Step 3: Reject a negative read offset**

`ufs_readwrite.c:145` currently reads:

```c
	fs = ip->I_FS;
	if ((u_int64_t)uio->uio_offset > fs->fs_maxfilesize)
		return (EFBIG);
```

Replace with:

```c
	fs = ip->I_FS;
	if (uio->uio_offset < 0)
		return (EINVAL);
	if ((u_int64_t)uio->uio_offset > fs->fs_maxfilesize)
		return (EFBIG);
```

The `WRITE` path at `:301` already checks this and needs no change.

- [ ] **Step 4: Return early from a zero-length write**

`ufs_readwrite.c:301` currently reads:

```c
	fs = ip->I_FS;
	if (uio->uio_offset < 0 ||
	    (u_int64_t)uio->uio_offset + uio->uio_resid > fs->fs_maxfilesize)
		return (EFBIG);
```

Append the early return immediately after it:

```c
	fs = ip->I_FS;
	if (uio->uio_offset < 0 ||
	    (u_int64_t)uio->uio_offset + uio->uio_resid > fs->fs_maxfilesize)
		return (EFBIG);
	if (uio->uio_resid == 0)
		return (0);
```

- [ ] **Step 5: Run the build cycle**

Run the build cycle from Global Constraints.
Expected: `rbuild kernel` completes and produces `kernel-154.5.1-7-i386.apk`. Any compiler error here is a typo in Steps 1-4; fix and rebuild before continuing.

- [ ] **Step 6: Graft the new kernel into this branch's image**

```bash
export RHAP_TEST_IMAGE=D:/RhapsodiOS/vm/work/ufs-backport.img
python vm/graft-kernel.py D:/RhapsodiOS/vm/golden.img <path-to-mach_kernel> \
    D:/RhapsodiOS/vm/work/ufs-backport.img
```

Expected: it prints the donor inode, old and new size, and the headroom left.

- [ ] **Step 7: Boot plain, and confirm the evidence channel works**

This is the step Task 2 could not do, because it had no kernel from this tree.
Boot with no extra disk first — the lowest-risk configuration.

```python
# run from vm/, with RHAP_TEST_IMAGE exported
import importlib.util, pathlib, time
spec = importlib.util.spec_from_file_location("guest_console", pathlib.Path("guest-console.py"))
gc = importlib.util.module_from_spec(spec); spec.loader.exec_module(gc)

g = gc.Guest("out/task3")
time.sleep(6)                 # REQUIRED before any g.line(); otherwise the
g.line("")                    # first character is swallowed
time.sleep(200)
g.shot("multiuser")
```

Run: `grep "serial_dbg" vm/out/task3/serial.log`
Expected: the banner `serial_dbg: i386 kernel console up`, emitted by
`machdep/i386/i386_init.c:127`.

**If that banner is absent, stop and report.** Every refusal in Tasks 4-7 is
verified by grepping this file for a kernel `printf`. Without it the evidence
strategy is void and the remaining tasks need redesigning — that is a finding,
not a failure to work around.

Also confirm from the screenshot that the machine reached multi-user with root
mounted read-write. That doubles as the regression check for Steps 1-4: those
three fixes must change nothing observable.

- [ ] **Step 8: Boot single-user with a second disk, and confirm the device node**

The other half of what Task 2 could not establish. Tasks 4-6 mount a malformed
filesystem from a second disk, so both the single-user shell and the second disk
have to work.

```python
g = gc.Guest("out/task3b", extra=(
    "-drive", "file=work/good-control.img,format=raw,if=ide,index=1,media=disk",
))
time.sleep(6)
g.line("-s")
time.sleep(135)
g.line("mount /dev/hd1a /mnt"); time.sleep(5); g.shot("mount-hd1a")
g.line("df"); time.sleep(3); g.shot("df")
```

Build `work/good-control.img` first if it does not exist:
`python -c "import make_badfs; make_badfs.build_good('work/good-control.img')"`

Expected: the mount succeeds and `df` lists `/mnt`. If `mount` reports no such
device, try `/dev/hd1b`, then `/dev/hd2a`.

Task 2 saw this configuration wedge in an `hc0: interrupt timeout, cmd: 0xc4`
ATA retry loop on the stock kernel. This tree carries EIDE fixes that the stock
kernel does not, so it may simply work now. If it still wedges, report that —
Harness A depends on it, and Tasks 4-6 would need a different way to present a
malformed filesystem.

- [ ] **Step 9: Record the device node and commit**

Tasks 4 through 8 are written against `/dev/hd1a`. If Step 8 found a different
node, edit them before they run.

```bash
git add src/kernel-7/bsd/ufs/ffs/ffs_vfsops.c src/kernel-7/bsd/ufs/ufs/ufs_readwrite.c
git commit -m "kernel: release the reload buffer on error and tighten UFS read/write bounds"
```

---

### Task 4: Validate the superblock magic before byte-swapping it

Change 4. The first demonstrated refusal, and the simplest, so it also proves the Task 1 harness end to end.

**Files:**
- Modify: `src/kernel-7/bsd/ufs/ffs/ffs_vfsops.c` — a `#define` near the includes, and a gate inserted before `:523`

**Interfaces:**
- Consumes: `make_badfs.corrupt(path, "fs_magic", ...)` from Task 1; the device node from Task 2.
- Produces: the serial-log token `ffs: superblock magic invalid, refusing`, grepped by this task only.

- [ ] **Step 1: Pre-check the magic instead of swapping the whole superblock**

`ffs_vfsops.c:523-531` currently reads:

```c
#if REV_ENDIAN_FS
	if (fs->fs_magic != FS_MAGIC || fs->fs_bsize > MAXBSIZE ||
	    fs->fs_bsize < sizeof(struct fs)) {
		byte_swap_sbin(fs);
		if (fs->fs_magic != FS_MAGIC || fs->fs_bsize > MAXBSIZE ||
	    		fs->fs_bsize < sizeof(struct fs)) {
			byte_swap_sbout(fs);
			error = EINVAL;		/* XXX needs translation */
			goto out;
		}
		rev_endian=1;
	}
#endif /* REV_ENDIAN_FS */
```

Insert a magic gate immediately **before** it, and leave the existing block
unchanged:

```c
	/*
	 * Refuse anything that is not FS_MAGIC in one byte order or the
	 * other before byte_swap_sbin() rewrites the whole superblock.
	 */
	if (fs->fs_magic != FS_MAGIC && fs->fs_magic != FS_MAGIC_SWAPPED) {
		printf("ffs: superblock magic invalid, refusing\n");
		error = EINVAL;		/* XXX needs translation */
		goto out;
	}
#if REV_ENDIAN_FS
	if (fs->fs_magic != FS_MAGIC || fs->fs_bsize > MAXBSIZE ||
	    fs->fs_bsize < sizeof(struct fs)) {
		byte_swap_sbin(fs);
```

Define the constant next to the existing includes near the top of the file:

```c
#define	FS_MAGIC_SWAPPED	0x54190100	/* FS_MAGIC, bytes reversed */
```

This deliberately avoids `NXSwapLong`: the `byte_swap_int` wrappers are defined
inside `ufs_byte_order.c` (`:45`, `:49`) and are not visible in `ffs_vfsops.c`.
Comparing against the reversed constant needs no helper and says exactly what
is meant. Garbage is now refused before the buffer is touched at all, and a
genuinely reverse-endian superblock still reaches `byte_swap_sbin` as before.

- [ ] **Step 2: Build**

Run the build cycle.
Expected: clean compile.

- [ ] **Step 3: Generate the bad-magic image**

```bash
cd vm && python -c "
import make_badfs
make_badfs.build_good('work/bad-magic.img')
make_badfs.corrupt('work/bad-magic.img', 'fs_magic', 0xDEADBEEF)"
```

- [ ] **Step 4: Boot and attempt the mount**

Boot with the malformed image as the IDE slave, using `Guest`'s `extra=`:

```python
# run from vm/
import importlib.util, pathlib, time
spec = importlib.util.spec_from_file_location("guest_console", pathlib.Path("guest-console.py"))
gc = importlib.util.module_from_spec(spec); spec.loader.exec_module(gc)

g = gc.Guest("out/task4", extra=(
    "-drive", "file=work/bad-magic.img,format=raw,if=ide,index=1,media=disk",
))
```

Drive the guest as in Task 2 Step 3, substituting the recorded device node:

```python
g.line("-s"); time.sleep(135)
g.line("mount /dev/hd1a /mnt"); time.sleep(5); g.shot("bad-magic")
```

- [ ] **Step 5: Confirm the refusal**

Run: `grep "ffs: superblock magic invalid" vm/out/task4/serial.log`
Expected: one matching line. The screenshot should show `mount` reporting an error and the root filesystem still healthy.

- [ ] **Step 6: Commit**

```bash
git add src/kernel-7/bsd/ufs/ffs/ffs_vfsops.c
git commit -m "kernel: validate the UFS superblock magic before byte-swapping it"
```

---

### Task 5: Refuse a fragment size below DIRBLKSIZ

Change 3.

**Files:**
- Modify: `src/kernel-7/bsd/ufs/ffs/ffs_vfsops.c` — one include near `:85-93`, and
  one refusal block after the 4.2-format check that ends at `:552`

**Interfaces:**
- Consumes: `make_badfs.corrupt(path, "fs_fsize", 256)`; the second-disk device
  node confirmed in Task 3 Step 8.
- Produces: the serial-log token `ffs: fragment size`.

**Why each refusal swaps back before bailing.** Past the `REV_ENDIAN_FS` block at
`:523-534`, a reverse-endian superblock has already been byte-swapped *in place*
in the buffer cache. Jumping to `out:` without `byte_swap_sbout` leaves that
swapped buffer cached, and the next mount of the same device reads native-endian
magic off a reverse-endian filesystem. Every existing refusal in this function
swaps back first — the bad-magic check at `:535-543` and the 4.2-format check at
`:545-552`. New refusals follow the same idiom rather than inventing a new one.

- [ ] **Step 1: Add the include**

`DIRBLKSIZ` lives in `<ufs/ufs/dir.h>`, which `ffs_vfsops.c` does not include —
its `ufs/ufs/` includes are `quota.h`, `ufsmount.h`, `inode.h`, `ufs_extern.h`
and `ufs_byte_order.h` (`:85-93`). Add beside them:

```c
#include <ufs/ufs/dir.h>
```

- [ ] **Step 2: Add the refusal**

`ffs_vfsops.c:545-552` currently reads:

```c
	/* XXX updating 4.2 FFS superblocks trashes rotational layout tables */
	if (fs->fs_postblformat == FS_42POSTBLFMT && !ronly) {
#if REV_ENDIAN_FS
		if (rev_endian)
			byte_swap_sbout(fs);
#endif /* REV_ENDIAN_FS */
		error = EROFS;          /* needs translation */
		goto out;
	}
```

Immediately after its closing brace, insert:

```c
	if (fs->fs_fsize < DIRBLKSIZ) {
		printf("ffs: fragment size %d below DIRBLKSIZ, refusing\n",
		    fs->fs_fsize);
#if REV_ENDIAN_FS
		if (rev_endian)
			byte_swap_sbout(fs);
#endif /* REV_ENDIAN_FS */
		error = ENOTSUP;
		goto out;
	}
```

The `printf` comes before the swap-back so it reports the native value.
`golden.img` has `fs_fsize` 1024 against a `DIRBLKSIZ` of 512, so root is
unaffected.

- [ ] **Step 3: Commit**

```bash
git add src/kernel-7/bsd/ufs/ffs/ffs_vfsops.c
git commit -m "kernel: refuse a UFS fragment size below DIRBLKSIZ at mount"
```

- [ ] **Step 4: Harness (after the build cycle)**

Generate the image, boot with it as the IDE slave, attempt the mount:

```bash
cd vm && python -c "
import make_badfs
make_badfs.build_good('work/bad-fsize.img')
make_badfs.corrupt('work/bad-fsize.img', 'fs_fsize', 256)"
```

```python
g = gc.Guest("out/task5", extra=(
    "-drive", "file=work/bad-fsize.img,format=raw,if=ide,index=1,media=disk",
))
time.sleep(6); g.line("-s"); time.sleep(135)
g.line("mount /dev/hd1a /mnt"); time.sleep(5); g.shot("bad-fsize")
```

Run: `grep "ffs: fragment size 256 below DIRBLKSIZ" vm/out/task5/serial.log`
Expected: one line. Then repeat with `work/good-control.img` and confirm it still
mounts.

---

### Task 6: Refuse a read-write mount of an unclean non-root filesystem

Change 1, non-root half.

**Files:**
- Modify: `src/kernel-7/bsd/ufs/ffs/ffs_vfsops.c`, immediately after Task 5's block

**Interfaces:**
- Consumes: `make_badfs.corrupt(path, "fs_clean", 0)`; the Task 3 device node.
- Produces: the serial-log token `ffs: filesystem not cleanly unmounted`.

**Why `!ronly` is load-bearing, and a deliberate departure from xnu-124.**
xnu-124's version has no read-only guard:
`((!(mp->mnt_flag & MNT_ROOTFS)) && (!fs->fs_clean))`. Ported verbatim into this
kernel, it would refuse a dirty root at boot. `MNT_ROOTFS` is only set at
`bsd/kern/init_main.c:579`, *after* `ffs_mountroot` returns — so during the
root's own `ffs_mountfs` it is still clear and the root looks like any other
filesystem. What saves it is that `vfs_rootmountalloc` mounts root with
`MNT_RDONLY` (`bsd/vfs/vfs_subr.c`), making `ronly` true. Without `!ronly`, every
unclean shutdown would leave a machine that cannot boot. A read-only mount of a
dirty non-root disk also cannot compound its damage, so allowing it costs
nothing and lets someone read data off a disk from a crashed machine.

- [ ] **Step 1: Add the refusal**

Immediately after Task 5's block, insert:

```c
	if (!ronly && (mp->mnt_flag & MNT_ROOTFS) == 0 && fs->fs_clean == 0) {
		printf("ffs: filesystem not cleanly unmounted, refusing; run fsck\n");
#if REV_ENDIAN_FS
		if (rev_endian)
			byte_swap_sbout(fs);
#endif /* REV_ENDIAN_FS */
		error = ENOTSUP;
		goto out;
	}
```

`ronly` is computed at `:505`. `fs_clean` is a single byte, so testing it before
the swap-back is endian-safe. `bp` and `ump` are nulled at `:517-518`, so `out:`
releases correctly from here.

- [ ] **Step 2: Commit**

```bash
git add src/kernel-7/bsd/ufs/ffs/ffs_vfsops.c
git commit -m "kernel: refuse a read-write mount of an unclean UFS filesystem"
```

- [ ] **Step 3: Harness (after the build cycle)**

```bash
cd vm && python -c "
import make_badfs
make_badfs.build_good('work/dirty.img')
make_badfs.corrupt('work/dirty.img', 'fs_clean', 0)"
```

```python
g = gc.Guest("out/task6", extra=(
    "-drive", "file=work/dirty.img,format=raw,if=ide,index=1,media=disk",
))
time.sleep(6); g.line("-s"); time.sleep(135)
g.line("mount /dev/hd1a /mnt"); time.sleep(5); g.shot("dirty-rw")
g.line("mount -r /dev/hd1a /mnt"); time.sleep(5); g.shot("dirty-ro")
```

Run: `grep -c "ffs: filesystem not cleanly unmounted" vm/out/task6/serial.log`
Expected: exactly `1` — from the read-write attempt only. `dirty-ro.png` must show
the read-only mount succeeding. The most important related check is the one
Task 7 Step 4 makes: that a dirty *root* still boots.

---

### Task 7: Refuse a single-user read-write upgrade of an unclean root

Change 1, root half.

**Files:**
- Modify: `src/kernel-7/bsd/ufs/ffs/ffs_vfsops.c` — one include, and a gate at `:203`

**Interfaces:**
- Consumes: `make_badfs.corrupt` from Task 1, applied to this branch's root image.
- Produces: serial-log tokens `ffs: root not cleanly unmounted` (refusal) and
  `not cleanly unmounted; mounting read-write anyway` (warning).

**What xnu-124 actually does, and why this is narrower than the first draft.**
xnu-124 (`bsd/ufs/ffs/ffs_vfsops.c:207-223`) refuses only when the machine was
booted single-user *and* the filesystem is root; otherwise it prints a warning
and proceeds. Its own comment states the intent: stop someone who booted
single-user from running `mount -uw /` without running `fsck` first. A normal
multi-user boot must never be stranded read-only.

xnu-124 also forces `ffs_reload` before every upgrade of a read-only filesystem,
so that a repair made by `fsck` becomes visible in the in-core superblock. That
is **not** ported: Rhapsody's `fsck` already reloads the root itself after
repairing it (`src/Commands/diskdev_cmds/fsck.tproj/main.c:418-432`, issuing
`MNT_UPDATE | MNT_RELOAD`), and forcing it in the kernel would run the
rarely-exercised `ffs_reload` on every single boot.

`issingleuser()` does not exist in this kernel. Its xnu-124 implementation just
parses the `-s` boot argument; here the `-s` flag sets `RB_SINGLE` in
`boothowto` (`machdep/i386/i386_init.c:555`). `boothowto` is declared in
`sys/systm.h:120`, already included; `RB_SINGLE` needs `<sys/reboot.h>`.

- [ ] **Step 1: Add the include**

Add beside the other `sys/` includes near the top of `ffs_vfsops.c`:

```c
#include <sys/reboot.h>
```

- [ ] **Step 2: Add the gate**

`ffs_vfsops.c:203` currently begins:

```c
		if (fs->fs_ronly && (mp->mnt_flag & MNT_WANTRDWR)) {
			/*
			 * If upgrade to read-write by non-root, then verify
			 * that user has necessary permissions on the device.
			 */
```

Insert the gate as the first statement inside that block:

```c
		if (fs->fs_ronly && (mp->mnt_flag & MNT_WANTRDWR)) {
			if (fs->fs_clean == 0) {
				if ((boothowto & RB_SINGLE) &&
				    (mp->mnt_flag & MNT_ROOTFS)) {
					printf("ffs: root not cleanly unmounted, refusing read-write upgrade; run fsck\n");
					return (EPERM);
				}
				printf("ffs: %s not cleanly unmounted; mounting read-write anyway\n",
				    fs->fs_fsmnt);
			}
			/*
			 * If upgrade to read-write by non-root, then verify
			 * that user has necessary permissions on the device.
			 */
```

Returning here is clean: nothing has been modified yet (`fs_ronly` is still set,
no superblock write), and `mount(2)` restores `mnt_flag` on error. Placing the
gate inside the upgrade block — rather than before it, as xnu-124 does — means
an update that keeps the filesystem read-only is never refused.

- [ ] **Step 3: Commit**

```bash
git add src/kernel-7/bsd/ufs/ffs/ffs_vfsops.c
git commit -m "kernel: refuse a single-user read-write upgrade of an unclean root"
```

- [ ] **Step 4: Harness — a dirty root must still boot multi-user (after the build cycle)**

This is the check that matters most in the whole plan.

```bash
cd vm && python -c "import make_badfs; make_badfs.corrupt('D:/RhapsodiOS/vm/work/ufs-backport.img', 'fs_clean', 0)"
```

```python
g = gc.Guest("out/task7a")
time.sleep(6); g.line(""); time.sleep(200); g.shot("dirty-multiuser")
```

Expected: the machine reaches multi-user with root read-write. `rc.boot`'s `fsck`
repairs and reloads the root before the upgrade, so the gate should not fire at
all; if it does, it may only warn. Run
`grep "ffs: root not cleanly unmounted" vm/out/task7a/serial.log` and expect **no**
match. A match means the gate is stranding multi-user boots — stop.

- [ ] **Step 5: Harness — single-user refuses, and `fsck` recovers**

Re-graft first (the multi-user boot repaired the image), then mark it dirty again:

```bash
python vm/graft-kernel.py D:/RhapsodiOS/vm/golden.img <path-to-mach_kernel> \
    D:/RhapsodiOS/vm/work/ufs-backport.img
cd vm && python -c "import make_badfs; make_badfs.corrupt('D:/RhapsodiOS/vm/work/ufs-backport.img', 'fs_clean', 0)"
```

```python
g = gc.Guest("out/task7b")
time.sleep(6); g.line("-s"); time.sleep(135)
g.line("mount -uw /"); time.sleep(5); g.shot("refused")
g.line("fsck -y /dev/hd0a"); time.sleep(120); g.shot("fsck")
g.line("mount -uw /"); time.sleep(10); g.shot("remounted")
```

Run: `grep "ffs: root not cleanly unmounted" vm/out/task7b/serial.log`
Expected: exactly one line, from the first `mount -uw /`. `remounted.png` must show
the second attempt succeeding — `fsck` marks the root clean and reloads it, and
the gate lets it through.

`vm/README.md:287-300` says never to run `fsck` on a grafted image. Running it
here is a deliberate, approved exception: this image is this branch's own and is
rebuilt from `golden.img` by every graft. Do not run `fsck -y` on any image you
care about.

---

### Task 8: Refuse ffs_vget during an unmount

Change 5. Ships argued, not demonstrated — a race with no deterministic trigger.

**Files:**
- Modify: `src/kernel-7/bsd/ufs/ffs/ffs_vfsops.c:936`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing. Deliberately no `printf` — this fires on a legitimate race, not on operator error, and logging it would be noise.

- [ ] **Step 1: Add the guard**

`ffs_vfsops.c:934-936` currently reads:

```c
	dev_t dev;
	int i, type, error;

	ump = VFSTOUFS(mp);
```

Replace with:

```c
	dev_t dev;
	int i, type, error;

	if (mp->mnt_flag & MNT_UNMOUNT) {
		*vpp = NULL;
		return (EPERM);
	}

	ump = VFSTOUFS(mp);
```

`MNT_UNMOUNT` is `bsd/sys/mount.h:180`, set by `dounmount` at `bsd/vfs/vfs_syscalls.c:417` and cleared at `:434`. This is the adaptation of xnu-124's `mnt_kern_flag & MNTK_UNMOUNT`, which does not exist in this tree.

- [ ] **Step 2: Build**

Run the build cycle.
Expected: clean compile.

- [ ] **Step 3: Regression boot plus an unmount**

Boot with the malformed image as the IDE slave, using `Guest`'s `extra=`:

```python
# run from vm/
import importlib.util, pathlib, time
spec = importlib.util.spec_from_file_location("guest_console", pathlib.Path("guest-console.py"))
gc = importlib.util.module_from_spec(spec); spec.loader.exec_module(gc)

g = gc.Guest("out/task8", extra=(
    "-drive", "file=work/good-control.img,format=raw,if=ide,index=1,media=disk",
))
```

```python
g.line("-s"); time.sleep(135)
g.line("mount /dev/hd1a /mnt"); time.sleep(5)
g.line("umount /mnt"); time.sleep(5); g.shot("umount")
g.line("mount /dev/hd1a /mnt"); time.sleep(5); g.shot("remount")
```

Expected: unmount succeeds, and the filesystem can be mounted again afterwards. The guard must not leave a mount point permanently unusable.

- [ ] **Step 4: Commit**

```bash
git add src/kernel-7/bsd/ufs/ffs/ffs_vfsops.c
git commit -m "kernel: refuse ffs_vget while an unmount is in progress"
```

---

### Task 9: Full regression and spec outcome

**Files:**
- Modify: `docs/superpowers/specs/2026-09-21-ufs-xnu124-backport-design.md`

- [ ] **Step 1: Clean build from scratch**

```bash
cd vm && cmd /c reset-image.cmd
```

Run the full build cycle, then graft.

- [ ] **Step 2: Boot to multi-user**

```python
# run from vm/  (same importlib preamble as Task 2)
g = gc.Guest("out/task9")
g.line(""); time.sleep(200)
g.shot("final-boot")
```

Expected: full boot, root read-write, no `ffs: ` lines in `vm/out/task9/serial.log`.

- [ ] **Step 3: Run fsck and compare against the known baseline**

At a single-user prompt, run `fsck -n /dev/hd0a` and screenshot the full run.
Expected: nothing beyond the four pre-existing graft-caused complaints catalogued in the UFS allocation work — `UNKNOWN FILE TYPE`/`BAD TYPE VALUE` on the graft donor inode, `LINK COUNT FILE I=1253202`, and the three Phase 5 superblock/bitmap/summary complaints. Anything new is a regression introduced by this branch.

- [ ] **Step 4: Write the Outcome section**

Append an `## Outcome` section to the spec recording, for each of the seven changes: whether it was demonstrated or argued, the serial-log line or screenshot that evidences it, and anything that behaved differently from what the spec predicted. Follow the style of the outcome section in `2026-09-18-ufs-allocation-design.md` — specific, including what failed on the way.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-09-21-ufs-xnu124-backport-design.md
git commit -m "docs: record the UFS backport outcome and fsck baseline"
```

---

## Notes for the implementer

**If the build box is unreachable.** Every kernel task depends on `rbuild` on the Rhapsody guest; there is no Windows-host kernel build. `gnumake` is not on the host PATH. If the box is down, Task 1 is still fully executable and worth doing first for exactly that reason.

**If `guest-console.py` import fails.** The filename has a hyphen, so `import guest_console` does not work directly. Use:

```python
import importlib.util, pathlib
spec = importlib.util.spec_from_file_location("guest_console", pathlib.Path("guest-console.py"))
guest_console = importlib.util.module_from_spec(spec); spec.loader.exec_module(guest_console)
Guest = guest_console.Guest
```

**Keystroke limits.** The QMP keymap has no `#`, `$`, `*`, `&`, `!` or `%`. Every command in this plan was chosen to avoid them. If a new command is needed, check `vm/guest-console.py:20-29` before assuming it can be typed.

**The 135-second sleep** in the guest-console pattern is copied from the working `fix_mouse()` template. It is the time to single-user prompt on this hardware, not a guess; shorten it only after observing a faster boot.
