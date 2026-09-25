# UFS gap tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Demonstrate on the fixed kernel that a crashed machine boots multi-user unattended, and that change 2's three `ffs_reload` fixes work, as specified in `docs/superpowers/specs/2026-09-25-ufs-gap-tests-design.md`.

**Architecture:** Host-side Python scripts under `vm/` drive QEMU through `guest-console.py`'s `Guest`. A base image is a copy of `golden.img` with a rebuilt kernel installed through `ufs_alloc`. Every boot runs on a qcow2 overlay of that base. Change 2's read errors come from QEMU's `blkdebug` driver, armed and disarmed by the host over QMP. Tasks 1–5 write and unit-test the scripts. Tasks 6–10 are operational: the coordinating session builds the kernel, runs the boots, reads the evidence and records the verdicts.

**Tech Stack:** Python 3 (pytest), QEMU 11.1 (`qemu-system-i386`, `qemu-img`, `qemu-io`, all on PATH), the existing `vm/` UFS tooling (`rhap_image`, `ufs_cg`, `ufs_build`, `ufs_alloc`, `ufs_check`, `make_badfs`), and `rbuild` on a private QEMU build guest.

## Global Constraints

- Work only in `D:\RhapsodiOS\.worktrees\ufs-gap-tests` (branch `ufs-gap-tests`). Run tests from its `vm/` directory: `cd vm && python -m pytest -q <files>`.
- Commit messages: short, subsystem prefix (`vm: `, `docs: `), describe what the change does, one or two lines, **no metadata and no Co-Authored-By lines**.
- `git add` explicit paths only; never `git add -A` or `git add .`. Never stage `vm/install/`, `vm/work/`, or `vm/vm.conf`.
- Never write `vm/golden.img` or `vm/work/test.img`. The master image lives only in the main checkout at `D:/RhapsodiOS/vm/golden.img`; read it, never write it.
- Persistent boots name their image through `RHAP_TEST_IMAGE` so `rhap_inject.check_target` applies.
- Before any QEMU boot, check its QMP port is free. Other sessions run many guests on this host.
- No kernel source changes. A kernel bug found here is reported with evidence, not fixed in this branch.
- The worktree needs two gitignored inputs that are already staged: `vm/install/rhapsody_dr2_x86_InstallationFloppy.img` (and the DriverDisk image) and `vm/vm.conf`.

## Deviations from the spec, found while planning

1. **The kernel is installed with `grow_file`, not `unlink` + `create_file`.** `golden.img`'s `/mach_kernel` is inode 1253202 with **two** links (the other is `/private/tftpboot/mach_kernel`). `ufs_alloc.unlink` frees the inode whatever its link count, which would leave the second name dangling. `grow_file(ino, data)` rewrites the inode's contents in place, allocating or freeing fragments, and keeps its mode and link count. Verified on a small image: same inode, mode 100444 kept, contents exact, `ufs_check` clean.
2. **Only crash boots write their overlay; every other boot is a snapshot.** A persistent boot that reaches the Setup Assistant cannot be shut down cleanly (there is no shell), and killing it would dirty root again and confound the follow-up `fsck`. So E2's boot, and every boot after a crash, is a snapshot of the run's overlay, which then starts every follow-up from the same state. E3's follow-up is a single-user `fsck -p` (showing what preen repairs), then `fsck -n`. E2's follow-up `fsck -n` checks its premise: nothing wrong beyond the clean flag.
3. **E3's copy runs in the foreground.** The console keymap has no `&`; the host kills QEMU on its own schedule anyway.
4. **A small shared module, `vm/ufs_gap_lib.py`**, holds what both run scripts need: paths, overlays, waiting on the serial log, and the result file.
5. **`fsck` names the block device (`/dev/hd0a`, `/dev/hd1a`)**, as the P0 harness did successfully, rather than `/dev/rhd0a`.

Two timing facts the scripts rely on, from the P0 harness's serial logs: `Continue without network? (y/n)` is printed by the kernel and reaches `serial.log`, after root's read-write upgrade; and `initPointer: Can't find active pointer device` follows once the window system starts. `fsck`'s own output is userland and reaches only the screen.

## File map

- Modify `vm/guest-console.py` — `qemu_args` picks `format=qcow2` for `.qcow2` images.
- Modify `vm/test_guest_console.py` — one `QemuArgsTest` case.
- Modify `vm/make_badfs.py` — `fs_maxfilesize` field, `build_good(pad=)`, `field_offset`, `read_field`, `reload_sectors`.
- Modify `vm/test_make_badfs.py` — tests for those.
- Create `vm/ufs_gap_lib.py` and `vm/test_ufs_gap_lib.py`.
- Create `vm/ufs-e2e-image.py` and `vm/test_ufs_e2e_image.py`.
- Create `vm/ufs-e2e-boot.py` and `vm/test_ufs_e2e_boot.py`.
- Create `vm/ufs-reload-inject.py` and `vm/test_ufs_reload_inject.py`.
- Modify `docs/superpowers/specs/2026-09-25-ufs-gap-tests-design.md` (Outcome, Task 10) and `docs/superpowers/specs/2026-09-21-ufs-xnu124-backport-design.md` (pointer, Task 10).

---

### Task 1: `guest-console.py` boots qcow2 overlays

**Files:**
- Modify: `vm/guest-console.py` (`qemu_args`, around line 62)
- Test: `vm/test_guest_console.py` (`QemuArgsTest`)

**Interfaces:**
- Produces: `qemu_args(image, ...)` emits `format=qcow2` when `image` ends in `.qcow2` (case-insensitive), `format=raw` otherwise. `Guest(image=...)` therefore boots overlays.

- [ ] **Step 1: Write the failing test**

Add this method to `class QemuArgsTest` in `vm/test_guest_console.py`, after `test_image_nic_and_extra`:

```python
    def test_qcow2_image_gets_qcow2_format(self):
        a = gc.qemu_args("run/disk.qcow2", False, 4481, "null", "ne2k_pci",
                         (), "s.log")
        self.assertIn(
            "file=run/disk.qcow2,format=qcow2,if=ide,index=0,media=disk", a)
        self.assertEqual(a[a.index("-drive") + 2], "-snapshot")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd vm && python -m pytest -q test_guest_console.py`
Expected: 1 failed (`test_qcow2_image_gets_qcow2_format`), 6 passed.

- [ ] **Step 3: Implement**

In `vm/guest-console.py`, `qemu_args`, replace the drive line. The function starts:

```python
def qemu_args(image, persist, port, com1, nic, extra, serial):
    """The qemu-system-i386 command line a Guest runs.  nic is the -device
    value without its netdev, e.g. "ne2k_pci" or "i82559er,addr=03.0"."""
    fmt = "qcow2" if image.lower().endswith(".qcow2") else "raw"
    args = [
        "qemu-system-i386", "-M", "pc", "-cpu", "pentium", "-accel", "tcg",
        "-m", "128", "-nodefaults", "-vga", "cirrus", "-display", "none",
        "-drive", "file=%s,format=%s,if=ide,index=0,media=disk" % (image, fmt),
```

(the rest of the list and function is unchanged).

- [ ] **Step 4: Run the tests**

Run: `cd vm && python -m pytest -q test_guest_console.py`
Expected: 7 passed.

- [ ] **Step 5: Commit**

```bash
git add vm/guest-console.py vm/test_guest_console.py
git commit -m "vm: let guest-console boot a qcow2 overlay"
```

---

### Task 2: `make_badfs` pads images and locates `ffs_reload`'s reads

**Files:**
- Modify: `vm/make_badfs.py`
- Test: `vm/test_make_badfs.py`

**Interfaces:**
- Produces:
  - `make_badfs.FIELDS["fs_maxfilesize"] == (1328, "<Q")` (struct fs: `fs_inodefmt` at 1324, `fs_maxfilesize` at 1328, `fs_qbmask` at 1336, consistent with `fs_postblformat` at 1356).
  - `build_good(out_path, pad=0)` — `pad` zero bytes appended after the filesystem image.
  - `field_offset(path, field) -> int` — absolute byte offset of a superblock field; raises `ValueError` for an unknown field.
  - `read_field(path, field)` — the field's value.
  - `reload_sectors(path) -> {"superblock": int, "csum": int, "inode2": int}` — first 512-byte sector, counted from the start of the image, of each read `ffs_reload` makes. For a `build_good` image these are 208, 352 and 256.

- [ ] **Step 1: Write the failing tests**

Append to `vm/test_make_badfs.py`:

```python
def test_pad_appends_zeros_after_a_valid_filesystem():
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "padded.img")
        make_badfs.build_good(out, pad=65536)
        assert os.path.getsize(out) == 1474560 + 65536
        assert _sb(out, 1372, "<i") == 0x00011954
        assert _sb(out, 209, "<b") == 1
        with open(out, "rb") as f:
            f.seek(1474560)
            assert f.read() == bytes(65536)

def test_field_offset_and_read_field():
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "good.img")
        make_badfs.build_good(out)
        part_start = make_badfs._read_partition_start(out)
        assert make_badfs.field_offset(out, "fs_clean") == part_start + 8192 + 209
        assert make_badfs.read_field(out, "fs_clean") == 1
        assert make_badfs.read_field(out, "fs_magic") == 0x00011954
        # well past 4 GiB, so the kernel's 4 GB clamp is not a no-op here
        assert make_badfs.read_field(out, "fs_maxfilesize") > 1 << 32
        with pytest.raises(ValueError):
            make_badfs.field_offset(out, "fs_nonsense")

def test_reload_sectors_point_at_what_ffs_reload_reads():
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "good.img")
        make_badfs.build_good(out)
        s = make_badfs.reload_sectors(out)
        assert len(set(s.values())) == 3
        with open(out, "rb") as f:
            def sector(n, length=512):
                f.seek(n * 512)
                return f.read(length)
            sb = sector(s["superblock"], 8192)
            # the superblock: its magic
            assert struct.unpack_from("<i", sb, 1372)[0] == 0x00011954
            # the summary area: one cylinder group, so its only struct csum
            # equals the superblock's fs_cstotal, at byte 192
            assert sector(s["csum"])[:16] == sb[192:208]
            # the block holding inode 2, 128 bytes per dinode: the root
            # directory
            mode = struct.unpack_from("<H", sector(s["inode2"], 8192), 2 * 128)[0]
            assert mode & 0o170000 == 0o040000
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd vm && python -m pytest -q test_make_badfs.py`
Expected: 3 failed (`build_good() got an unexpected keyword argument 'pad'`, `has no attribute 'field_offset'`, `has no attribute 'reload_sectors'`), 5 passed.

- [ ] **Step 3: Implement**

Replace `vm/make_badfs.py` with:

```python
"""Build small UFS images and corrupt one superblock field, for kernel
mount-refusal testing. Writes only to caller-named paths; never touches
golden.img or vm/work/test.img."""

import os
import struct

import rhap_image
import ufs_build
import ufs_cg
import ufs_extract

TEMPLATE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "install", "rhapsody_dr2_x86_InstallationFloppy.img")

# offset within the superblock, struct format
FIELDS = {
    "fs_clean": (209, "<b"),
    "fs_magic": (1372, "<I"),
    "fs_maxfilesize": (1328, "<Q"),
}


def build_good(out_path, pad=0):
    """Write a minimal single-cylinder-group UFS image with a clean
    superblock.  pad appends that many zero bytes past the filesystem: room
    a host can write without touching it."""
    nodes = [ufs_extract.Node("/", "dir", 0o040755, 0, 0, 0, None)]
    data = ufs_build.build(TEMPLATE, nodes)
    with open(out_path, "wb") as f:
        f.write(data)
        f.write(bytes(pad))
    _poke(out_path, "fs_clean", 1)


def corrupt(out_path, field, value):
    """Overwrite one superblock field in an existing image."""
    if field not in FIELDS:
        raise ValueError("unknown field %r; known: %s"
                         % (field, ", ".join(sorted(FIELDS))))
    _poke(out_path, field, value)


def field_offset(path, field):
    """Absolute byte offset of a superblock field in an image."""
    if field not in FIELDS:
        raise ValueError("unknown field %r; known: %s"
                         % (field, ", ".join(sorted(FIELDS))))
    return _read_partition_start(path) + rhap_image.SBOFF + FIELDS[field][0]


def read_field(path, field):
    """The value of a superblock field."""
    fmt = FIELDS[field][1]
    with open(path, "rb") as f:
        f.seek(field_offset(path, field))
        return struct.unpack(fmt, f.read(struct.calcsize(fmt)))[0]


def reload_sectors(path):
    """First 512-byte sector, counted from the start of the image, of each
    disk read ffs_reload makes: the superblock (its Step 2), the
    cylinder-group summary (Step 3) and the inode block holding the root
    inode (Step 6).  blkdebug's sector= option takes exactly this unit."""
    g = ufs_cg.read_geometry(path)
    base = _read_partition_start(path) // 512
    per_frag = g.fsize // 512
    # ino_to_fsba(fs, 2) is cgimin(fs, 0) + (2 % ipg) / inopb blocks;
    # cgstart(fs, 0) is 0 and inopb exceeds 2, so that is fs_iblkno
    return {
        "superblock": base + rhap_image.SBOFF // 512,
        "csum": base + g.csaddr * per_frag,
        "inode2": base + g.iblkno * per_frag,
    }


def _poke(out_path, field, value):
    fmt = FIELDS[field][1]
    offset = field_offset(out_path, field)
    with open(out_path, "r+b") as f:
        f.seek(offset)
        f.write(struct.pack(fmt, value))


def _read_partition_start(out_path):
    """Read partition start offset by parsing the disk label directly.

    This mirrors the logic from rhap_image.Image._read_label() and computes
    the offset without validating the superblock magic. Used by corrupt()
    which may be invoked after the magic has been intentionally corrupted.
    """
    with open(out_path, "rb") as f:
        for label_off in rhap_image.LABEL_OFFSETS:
            f.seek(label_off)
            if f.read(4) == rhap_image.LABEL_MAGIC:
                f.seek(label_off + 92)
                secsize = struct.unpack(">i", f.read(4))[0]
                f.seek(label_off + 112)
                front = struct.unpack(">h", f.read(2))[0]
                f.seek(label_off + 190)
                p_base = struct.unpack(">i", f.read(4))[0]
                return (front + p_base) * secsize
    raise ValueError("no NeXT disk label found in %s" % out_path)
```

- [ ] **Step 4: Run the tests**

Run: `cd vm && python -m pytest -q test_make_badfs.py`
Expected: 8 passed.

- [ ] **Step 5: Commit**

```bash
git add vm/make_badfs.py vm/test_make_badfs.py
git commit -m "vm: let make_badfs pad an image and find the sectors ffs_reload reads"
```

---

### Task 3: Shared helpers, `vm/ufs_gap_lib.py`

**Files:**
- Create: `vm/ufs_gap_lib.py`
- Test: `vm/test_ufs_gap_lib.py`

**Interfaces:**
- Produces:
  - `WORK` = `<vm>/work/ufs-gap`; `BASE` = `<vm>/work/ufs-e2e.img`; `SHELL_WAIT = 135`.
  - `load_guest_console()` → the `guest-console.py` module.
  - `port_free(port) -> bool`.
  - `overlay_args(base, overlay) -> list` and `make_overlay(base, overlay)` (raises `SystemExit` if the overlay exists).
  - `wait_for(path, text, timeout, tick=15, on_tick=None) -> bool`.
  - `ffs_lines(serial_path) -> list[str]`.
  - `write_result(outdir, notes)` — writes and prints `outdir/result.txt`: the notes, then every `ffs: ` line from `outdir/serial.log`.
  - `single_user(g)` — waits 6 s, types `-s`, waits `SHELL_WAIT`, screenshots `shell`.

- [ ] **Step 1: Write the failing tests**

Create `vm/test_ufs_gap_lib.py`:

```python
import os
import socket
import tempfile

import ufs_gap_lib as lib


def test_overlay_args_name_a_raw_backing_file():
    overlay = os.path.join("r", "disk.qcow2")
    assert lib.overlay_args("base.img", overlay) == [
        "qemu-img", "create", "-q", "-f", "qcow2", "-F", "raw",
        "-b", os.path.abspath("base.img"), os.path.abspath(overlay)]


def test_wait_for_sees_text_already_there():
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "serial.log")
        with open(p, "w") as f:
            f.write("boot\nContinue without network? (y/n)")
        assert lib.wait_for(p, "Continue without network?", timeout=0, tick=0)


def test_wait_for_times_out_and_ticks_while_waiting():
    ticks = []
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "serial.log")
        with open(p, "w") as f:
            f.write("boot\n")
        assert not lib.wait_for(p, "never", timeout=0.05, tick=0.01,
                                on_tick=lambda: ticks.append(1))
    assert ticks


def test_wait_for_notices_text_written_between_polls():
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "serial.log")
        open(p, "w").close()

        def tick():
            with open(p, "a") as f:
                f.write("initPointer: Can't find active pointer device\n")
        assert lib.wait_for(p, "initPointer:", timeout=5, tick=0, on_tick=tick)


def test_wait_for_tolerates_a_missing_file():
    with tempfile.TemporaryDirectory() as d:
        assert not lib.wait_for(os.path.join(d, "none.log"), "x",
                                timeout=0, tick=0)


def test_ffs_lines_keeps_only_the_kernels_ffs_lines():
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "serial.log")
        with open(p, "wb") as f:
            f.write(b"serial_dbg: i386 kernel console up\r\n"
                    b"ffs: / was unclean when mounted; mounting read-write anyway\r\n"
                    b"Registering: en0\n"
                    b"\rffs: /mnt not cleanly unmounted, refusing read-write upgrade; run fsck\n")
        assert lib.ffs_lines(p) == [
            "ffs: / was unclean when mounted; mounting read-write anyway",
            "ffs: /mnt not cleanly unmounted, refusing read-write upgrade; run fsck"]


def test_ffs_lines_of_a_missing_log_is_empty():
    with tempfile.TemporaryDirectory() as d:
        assert lib.ffs_lines(os.path.join(d, "serial.log")) == []


def test_write_result_lists_notes_then_ffs_lines():
    with tempfile.TemporaryDirectory() as d:
        with open(os.path.join(d, "serial.log"), "w") as f:
            f.write("ffs: superblock magic invalid, refusing\n")
        lib.write_result(d, ["note one"])
        with open(os.path.join(d, "result.txt")) as f:
            assert f.read() == ("note one\nffs: lines:\n"
                                "  ffs: superblock magic invalid, refusing\n")


def test_port_free_sees_a_listener():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    s.listen(1)
    try:
        assert not lib.port_free(s.getsockname()[1])
    finally:
        s.close()
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd vm && python -m pytest -q test_ufs_gap_lib.py`
Expected: collection error, `ModuleNotFoundError: No module named 'ufs_gap_lib'`.

- [ ] **Step 3: Implement**

Create `vm/ufs_gap_lib.py`:

```python
"""Shared pieces of the UFS gap tests (ufs-e2e-boot.py and
ufs-reload-inject.py): where their files live, qcow2 overlays, waiting on the
kernel's serial log, and each run's result.txt.  See
docs/superpowers/specs/2026-09-25-ufs-gap-tests-design.md."""
import importlib.util
import os
import socket
import subprocess
import time

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work", "ufs-gap")
BASE = os.path.join(HERE, "work", "ufs-e2e.img")
SHELL_WAIT = 135    # seconds from "-s" to a single-user shell, as in the P0 harness


def load_guest_console():
    spec = importlib.util.spec_from_file_location(
        "guest_console", os.path.join(HERE, "guest-console.py"))
    gc = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gc)
    return gc


def port_free(port):
    """True if nothing is listening on 127.0.0.1:port."""
    s = socket.socket()
    try:
        s.settimeout(1)
        return s.connect_ex(("127.0.0.1", port)) != 0
    finally:
        s.close()


def overlay_args(base, overlay):
    return ["qemu-img", "create", "-q", "-f", "qcow2", "-F", "raw",
            "-b", os.path.abspath(base), os.path.abspath(overlay)]


def make_overlay(base, overlay):
    """A fresh qcow2 overlay backed by the raw base; never reuses one."""
    if os.path.exists(overlay):
        raise SystemExit("%s already exists; each run starts from a fresh "
                         "overlay" % overlay)
    os.makedirs(os.path.dirname(overlay), exist_ok=True)
    subprocess.run(overlay_args(base, overlay), check=True)


def wait_for(path, text, timeout, tick=15, on_tick=None):
    """Poll path until it contains text, calling on_tick() after each tick
    seconds of waiting.  True if text appeared, False on timeout."""
    deadline = time.time() + timeout
    while True:
        if os.path.exists(path):
            with open(path, "r", errors="replace") as f:
                if text in f.read():
                    return True
        if time.time() >= deadline:
            return False
        time.sleep(tick)
        if on_tick:
            on_tick()


def ffs_lines(serial_path):
    """The kernel's 'ffs: ' lines, in order."""
    if not os.path.exists(serial_path):
        return []
    with open(serial_path, "r", errors="replace") as f:
        return [s for s in (l.strip("\r\n") for l in f)
                if s.startswith("ffs: ")]


def write_result(outdir, notes):
    """Write and print outdir/result.txt: the notes, then every ffs: line."""
    lines = list(notes) + ["ffs: lines:"] + [
        "  " + l for l in ffs_lines(os.path.join(outdir, "serial.log"))]
    with open(os.path.join(outdir, "result.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))


def single_user(g):
    """Boot a Guest to its single-user shell and screenshot it."""
    time.sleep(6)
    g.line("-s")
    time.sleep(SHELL_WAIT)
    g.shot("shell")
```

- [ ] **Step 4: Run the tests**

Run: `cd vm && python -m pytest -q test_ufs_gap_lib.py`
Expected: 9 passed.

- [ ] **Step 5: Commit**

```bash
git add vm/ufs_gap_lib.py vm/test_ufs_gap_lib.py
git commit -m "vm: add helpers the UFS gap tests share"
```

---

### Task 4: The base image, `vm/ufs-e2e-image.py`

**Files:**
- Create: `vm/ufs-e2e-image.py`
- Test: `vm/test_ufs_e2e_image.py`

**Interfaces:**
- Consumes: `ufs_alloc.Allocator(path, writable=True)` with `validate()`, `_resolve(path)`, `grow_file(ino, data)`, `flush()`; `ufs_alloc._refuse_master(path)` (raises `ufs_alloc.SafetyError` for `golden.img` or any path outside `vm/work`); `ufs_check.check(path) -> list`.
- Produces: `install_kernel(image, kernel_bytes) -> int` (the unchanged inode number); CLI `python ufs-e2e-image.py GOLDEN KERNEL [OUT]`, exit 0 only when `ufs_check` reports zero problems.

- [ ] **Step 1: Write the failing tests**

Create `vm/test_ufs_e2e_image.py`:

```python
import importlib.util
import os
import tempfile

import pytest

import make_badfs
import rhap_image
import ufs_build
import ufs_check
import ufs_extract

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")

pytestmark = pytest.mark.skipif(not os.path.exists(make_badfs.TEMPLATE),
                                reason="install floppy template not present")


def _load():
    spec = importlib.util.spec_from_file_location(
        "ufs_e2e_image", os.path.join(HERE, "ufs-e2e-image.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def _image_with_kernel(d, data):
    N = ufs_extract.Node
    path = os.path.join(d, "k.img")
    with open(path, "wb") as f:
        f.write(ufs_build.build(make_badfs.TEMPLATE, [
            N("/", "dir", 0o040755, 0, 0, 0, None),
            N("/mach_kernel", "reg", 0o100444, 0, 0, 0, data)]))
    return path


def test_install_kernel_rewrites_the_same_inode_consistently():
    m = _load()
    old = bytes(range(256)) * 400                # 100 KB
    new = bytes(reversed(range(256))) * 900      # 225 KB, so it must allocate
    os.makedirs(WORK, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=WORK) as d:
        path = _image_with_kernel(d, old)
        with rhap_image.Image(path) as img:
            before = img.resolve("/mach_kernel")
        assert m.install_kernel(path, new) == before
        with rhap_image.Image(path) as img:
            ino = img.resolve("/mach_kernel")
            inode = img.inode(ino)
            assert ino == before
            assert inode.mode == 0o100444
            assert inode.nlink == 1
            assert img.read_file(ino) == new
        assert ufs_check.check(path) == []


def test_main_refuses_an_existing_output():
    m = _load()
    os.makedirs(WORK, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=WORK) as d:
        out = os.path.join(d, "exists.img")
        open(out, "wb").close()
        assert m.main(["ufs-e2e-image.py", "unread-golden.img",
                       "unread-kernel", out]) == 1
        assert os.path.getsize(out) == 0


def test_main_refuses_an_output_outside_vm_work():
    m = _load()
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "outside.img")
        assert m.main(["ufs-e2e-image.py", "unread-golden.img",
                       "unread-kernel", out]) == 1
        assert not os.path.exists(out)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd vm && python -m pytest -q test_ufs_e2e_image.py`
Expected: 3 failed, `FileNotFoundError` for `ufs-e2e-image.py`.

- [ ] **Step 3: Implement**

Create `vm/ufs-e2e-image.py`:

```python
"""Build the UFS gap tests' base image: a copy of golden.img whose
/mach_kernel is a rebuilt kernel, installed as a real file.

usage: python ufs-e2e-image.py GOLDEN KERNEL [OUT]

graft-kernel.py repoints /mach_kernel at a donor file, which leaves damage
fsck -p will not preen.  This rewrites the kernel's own inode in place with
ufs_alloc's grow_file, which allocates and frees fragments and keeps every
summary consistent.  golden.img's /mach_kernel has two links (the other is
/private/tftpboot/mach_kernel), and grow_file keeps the inode, its mode and
its link count, so both names stay valid.

OUT defaults to work/ufs-e2e.img beside this script.  It must not exist and
must be under vm/work.  If ufs_check finds any problem in the result, OUT is
removed and the exit status is 1.
"""
import os
import shutil
import sys

import ufs_alloc
import ufs_check

HERE = os.path.dirname(os.path.abspath(__file__))
USAGE = "usage: python ufs-e2e-image.py GOLDEN KERNEL [OUT]"


def install_kernel(image, kernel):
    """Replace /mach_kernel's contents in image with the bytes kernel.
    Returns its inode number, which does not change."""
    with ufs_alloc.Allocator(image, writable=True) as a:
        a.validate()
        ino = a._resolve("/mach_kernel")
        if ino is None:
            raise ufs_alloc.SafetyError("%s has no /mach_kernel" % image)
        a.grow_file(ino, kernel)
        a.flush()
    return ino


def main(argv):
    if len(argv) not in (3, 4):
        print(USAGE, file=sys.stderr)
        return 2
    golden, kernel_path = argv[1], argv[2]
    out = argv[3] if len(argv) == 4 else os.path.join(HERE, "work", "ufs-e2e.img")
    if os.path.exists(out):
        print("ufs-e2e-image: %s already exists" % out, file=sys.stderr)
        return 1
    try:
        ufs_alloc._refuse_master(out)
    except ufs_alloc.SafetyError as e:
        print("ufs-e2e-image: %s" % e, file=sys.stderr)
        return 1
    with open(kernel_path, "rb") as f:
        kernel = f.read()
    print("copying %s to %s" % (golden, out))
    shutil.copyfile(golden, out)
    try:
        ino = install_kernel(out, kernel)
        problems = ufs_check.check(out)
    except BaseException:
        os.remove(out)
        raise
    if problems:
        os.remove(out)
        print("ufs-e2e-image: ufs_check found %d problem(s); %s removed"
              % (len(problems), out), file=sys.stderr)
        for p in problems:
            print("  %s" % p, file=sys.stderr)
        return 1
    print("installed a %d-byte kernel in inode %d; ufs_check: 0 problems"
          % (len(kernel), ino))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

- [ ] **Step 4: Run the tests**

Run: `cd vm && python -m pytest -q test_ufs_e2e_image.py`
Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add vm/ufs-e2e-image.py vm/test_ufs_e2e_image.py
git commit -m "vm: build an image with a rebuilt kernel installed as a real file, for crash-boot tests"
```

---

### Task 5: Gap 1 runner, `vm/ufs-e2e-boot.py`

**Files:**
- Create: `vm/ufs-e2e-boot.py`
- Test: `vm/test_ufs_e2e_boot.py`

**Interfaces:**
- Consumes: `ufs_gap_lib` (Task 3), `make_badfs.field_offset` (Task 2), `Guest(outdir, persist=, port=, image=)` with `line`, `shot`, `cmd`, `close`, `serial`, `proc` (Task 1 makes `.qcow2` work).
- Produces: `dirty_args(overlay, offset) -> list`; `new(base, name, dirty)`; `multi(name, port)`; `fsck(name, port, preen)`; `crash(name, seconds, port)`; CLI:

```
python ufs-e2e-boot.py new NAME [--dirty] [--base IMG]
python ufs-e2e-boot.py multi|fsck|preen NAME [--port N]
python ufs-e2e-boot.py crash NAME SECONDS [--port N]
```

Overlay: `work/ufs-gap/NAME/disk.qcow2`. Evidence: `work/ufs-gap/NAME/{multi,fsck,preen,crash}/`, each holding `serial.log`, PNG screenshots and `result.txt`. Default QMP port 4492.

- [ ] **Step 1: Write the failing tests**

Create `vm/test_ufs_e2e_boot.py`:

```python
import importlib.util
import os
import shutil
import subprocess
import tempfile

import pytest

import make_badfs
import ufs_gap_lib as lib

HERE = os.path.dirname(os.path.abspath(__file__))

needs_qemu = pytest.mark.skipif(
    not (shutil.which("qemu-img") and shutil.which("qemu-io")
         and os.path.exists(make_badfs.TEMPLATE)),
    reason="needs qemu-img, qemu-io and the install floppy template")


def _load():
    spec = importlib.util.spec_from_file_location(
        "ufs_e2e_boot", os.path.join(HERE, "ufs-e2e-boot.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def test_dirty_args_write_one_zero_byte():
    overlay = os.path.join("x", "disk.qcow2")
    assert _load().dirty_args(overlay, 106705) == [
        "qemu-io", "-f", "qcow2", "-c", "write -P 0 106705 1",
        os.path.abspath(overlay)]


@needs_qemu
def test_new_dirty_changes_the_overlay_and_not_the_base(monkeypatch):
    m = _load()
    with tempfile.TemporaryDirectory() as d:
        base = os.path.join(d, "base.img")
        make_badfs.build_good(base)
        monkeypatch.setattr(lib, "WORK", d)
        m.new(base, "t", dirty=True)
        flat = os.path.join(d, "flat.img")
        subprocess.run(["qemu-img", "convert", "-O", "raw",
                        os.path.join(d, "t", "disk.qcow2"), flat], check=True)
        assert make_badfs.read_field(flat, "fs_clean") == 0
        assert make_badfs.read_field(flat, "fs_magic") == 0x00011954
        assert make_badfs.read_field(base, "fs_clean") == 1


@needs_qemu
def test_new_refuses_to_reuse_an_overlay(monkeypatch):
    m = _load()
    with tempfile.TemporaryDirectory() as d:
        base = os.path.join(d, "base.img")
        make_badfs.build_good(base)
        monkeypatch.setattr(lib, "WORK", d)
        m.new(base, "t", dirty=False)
        with pytest.raises(SystemExit):
            m.new(base, "t", dirty=False)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd vm && python -m pytest -q test_ufs_e2e_boot.py`
Expected: 3 failed, `FileNotFoundError` for `ufs-e2e-boot.py`.

- [ ] **Step 3: Implement**

Create `vm/ufs-e2e-boot.py`:

```python
"""Gap 1 of the UFS gap tests: does a crashed machine boot multi-user
unattended?  See docs/superpowers/specs/2026-09-25-ufs-gap-tests-design.md.

usage:
  python ufs-e2e-boot.py new NAME [--dirty] [--base IMG]
        create work/ufs-gap/NAME/disk.qcow2 over the base image;
        --dirty writes fs_clean = 0 into the overlay, never the base
  python ufs-e2e-boot.py multi NAME [--port N]
        snapshot boot, unattended multi-user                  -> NAME/multi
  python ufs-e2e-boot.py fsck NAME [--port N]
        snapshot single-user boot: fsck -n                     -> NAME/fsck
  python ufs-e2e-boot.py preen NAME [--port N]
        snapshot single-user boot: fsck -p, then fsck -n       -> NAME/preen
  python ufs-e2e-boot.py crash NAME SECONDS [--port N]
        persistent single-user boot: mount -uw /, copy /usr/lib in the
        foreground, QMP quit SECONDS later                     -> NAME/crash

Only crash writes the overlay.  Every other boot is a snapshot, so each
starts from the overlay exactly as new or crash left it.  Each run's
directory holds serial.log, the screenshots, and result.txt.

A multi boot types -v at the boot prompt and y at the kernel's network
prompt, the same keystrokes a clean boot needs, and nothing else.
"""
import argparse
import os
import subprocess
import sys
import time

import make_badfs
import ufs_gap_lib as lib

NETWORK_PROMPT = "Continue without network?"
MULTIUSER_MARKER = "initPointer:"
PROMPT_WAIT = 1800      # boot, rc.boot's fsck -p and the root upgrade
MARKER_WAIT = 600
FSCK_WAIT = 600         # per fsck pass, screenshotted every 20 s


def dirty_args(overlay, offset):
    """qemu-io command writing fs_clean = 0 at offset in the overlay."""
    return ["qemu-io", "-f", "qcow2", "-c", "write -P 0 %d 1" % offset,
            os.path.abspath(overlay)]


def _overlay(name):
    return os.path.join(lib.WORK, name, "disk.qcow2")


def new(base, name, dirty):
    overlay = _overlay(name)
    lib.make_overlay(base, overlay)
    if dirty:
        offset = make_badfs.field_offset(base, "fs_clean")
        subprocess.run(dirty_args(overlay, offset), check=True)
    print("created %s%s" % (overlay, ", fs_clean = 0" if dirty else ""))


def _guest(name, run, port, persist):
    overlay = _overlay(name)
    if not os.path.exists(overlay):
        raise SystemExit("%s does not exist; run 'new %s' first"
                         % (overlay, name))
    if not lib.port_free(port):
        raise SystemExit("QMP port %d is in use" % port)
    outdir = os.path.join(lib.WORK, name, run)
    if os.path.exists(outdir):
        raise SystemExit("%s already exists; evidence is never overwritten"
                         % outdir)
    if persist:
        os.environ["RHAP_TEST_IMAGE"] = os.path.abspath(overlay)
    gc = lib.load_guest_console()
    g = gc.Guest(outdir, persist=persist, port=port,
                 image=os.path.abspath(overlay))
    return g, outdir


def multi(name, port):
    g, outdir = _guest(name, "multi", port, persist=False)
    start = time.time()

    def tick():
        g.shot("t%04d" % (time.time() - start))
    notes = []
    try:
        time.sleep(6)
        g.line("-v")
        if lib.wait_for(g.serial, NETWORK_PROMPT, PROMPT_WAIT, 15, tick):
            notes.append("network prompt after %d s" % (time.time() - start))
            g.line("y")
            seen = lib.wait_for(g.serial, MULTIUSER_MARKER, MARKER_WAIT, 15, tick)
            notes.append("%s %s after %d s" % (
                MULTIUSER_MARKER, "seen" if seen else "NOT seen",
                time.time() - start))
            time.sleep(60)
        else:
            notes.append("NO network prompt within %d s" % PROMPT_WAIT)
        g.shot("final")
    finally:
        g.close()
    lib.write_result(outdir, notes)


def fsck(name, port, preen):
    g, outdir = _guest(name, "preen" if preen else "fsck", port, persist=False)
    cmds = (["fsck -p /dev/hd0a"] if preen else []) + ["fsck -n /dev/hd0a"]
    try:
        lib.single_user(g)
        for c in cmds:
            g.line(c)
            flag = c.split()[1][1:]
            for t in range(20, FSCK_WAIT + 1, 20):
                time.sleep(20)
                g.shot("%s-%03d" % (flag, t))
    finally:
        g.close()
    lib.write_result(outdir, ["commands: " + "; ".join(cmds)])


def crash(name, seconds, port):
    g, outdir = _guest(name, "crash", port, persist=True)
    try:
        lib.single_user(g)
        g.line("mount -uw /")
        time.sleep(10)
        g.shot("rw")
        g.line("cp -R /usr/lib /private/tmp/%s" % name)
        time.sleep(seconds)
        g.shot("before-quit")
        g.cmd("quit")
        g.proc.wait(timeout=30)
    finally:
        g.close()
    lib.write_result(outdir, ["QMP quit %d s after starting the copy" % seconds])


def main(argv):
    p = argparse.ArgumentParser(
        description="UFS gap 1: an unattended boot after a crash")
    p.add_argument("command", choices=("new", "multi", "fsck", "preen", "crash"))
    p.add_argument("name")
    p.add_argument("seconds", nargs="?", type=int)
    p.add_argument("--dirty", action="store_true")
    p.add_argument("--base", default=lib.BASE)
    p.add_argument("--port", type=int, default=4492)
    a = p.parse_args(argv[1:])
    if a.command == "new":
        new(a.base, a.name, a.dirty)
    elif a.command == "multi":
        multi(a.name, a.port)
    elif a.command in ("fsck", "preen"):
        fsck(a.name, a.port, preen=(a.command == "preen"))
    else:
        if a.seconds is None:
            p.error("crash needs SECONDS")
        crash(a.name, a.seconds, a.port)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

- [ ] **Step 4: Run the tests**

Run: `cd vm && python -m pytest -q test_ufs_e2e_boot.py`
Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add vm/ufs-e2e-boot.py vm/test_ufs_e2e_boot.py
git commit -m "vm: add the runner for unattended-boot-after-crash tests"
```

---

### Task 6: Gap 2 runner, `vm/ufs-reload-inject.py`

**Files:**
- Create: `vm/ufs-reload-inject.py`
- Test: `vm/test_ufs_reload_inject.py`

**Interfaces:**
- Consumes: `make_badfs.build_good(pad=)`, `corrupt`, `read_field`, `reload_sectors` (Task 2); `ufs_gap_lib` (Task 3); `Guest(..., extra=[...])` and `Guest.cmd("human-monitor-command", **{"command-line": ...})`.
- Produces: `PAD = 65536`, `DRIVE_ID = "t1"`, `SITES = {"r1": "superblock", "r2": "csum", "r3": "inode2"}`, `blkdebug_config(target_sector, dummy_sector) -> str`, `drive_args(disk, conf=None) -> list`, `hmp_write(offset) -> str`, `make_test_disk(path) -> int` (byte offset where the padding starts: 1474560), `run(name, base, port)`; CLI `python ufs-reload-inject.py r1|r2|r3|r4|r5 [--base IMG] [--port N]`, default port 4493. Evidence: `work/ufs-gap/RUN/` with `test.img`, `blkdebug.conf` (r1–r3), `serial.log`, screenshots, `result.txt`. The root disk is `work/ufs-gap/r-root/disk.qcow2`, created once and only ever booted as a snapshot.

- [ ] **Step 1: Write the failing tests**

Create `vm/test_ufs_reload_inject.py`:

```python
import importlib.util
import os
import shutil
import subprocess
import tempfile

import pytest

import make_badfs

HERE = os.path.dirname(os.path.abspath(__file__))


def _load():
    spec = importlib.util.spec_from_file_location(
        "ufs_reload_inject", os.path.join(HERE, "ufs-reload-inject.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def test_blkdebug_config_names_both_sectors():
    c = _load().blkdebug_config(208, 2880)
    assert 'sector = "208"' in c
    assert 'sector = "2880"' in c
    assert c.count("[set-state]") == 2
    assert c.count("[inject-error]") == 2


@pytest.mark.skipif(not shutil.which("qemu-io"), reason="needs qemu-io")
def test_blkdebug_config_arms_and_disarms_under_qemu_io():
    m = _load()
    with tempfile.TemporaryDirectory() as d:
        disk = os.path.join(d, "disk.raw")
        with open(disk, "wb") as f:
            f.write(bytes(1 << 20))
        conf = os.path.join(d, "blkdebug.conf")
        with open(conf, "w") as f:
            # error on sector 16; the dummy is sector 128, the one the host
            # writes to arm and disarm
            f.write(m.blkdebug_config(16, 128))
        opts = ("driver=raw,file.driver=blkdebug,file.config=%s,"
                "file.image.filename=%s"
                % (conf.replace("\\", "/"), disk.replace("\\", "/")))
        out = subprocess.run(
            ["qemu-io", "--image-opts",
             "-c", "read 8192 8192",     # before arming: fine
             "-c", "write 65536 512",    # arm
             "-c", "read 0 512",         # another sector: fine
             "-c", "read 8192 8192",     # covers sector 16: fails
             "-c", "read 8192 8192",     # a retry fails too
             "-c", "write 65536 512",    # disarm
             "-c", "read 8192 8192",     # fine again
             opts],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True).stdout
        results = [l for l in out.splitlines()
                   if l.startswith(("read ", "wrote "))]
        assert results == [
            "read 8192/8192 bytes at offset 8192",
            "wrote 512/512 bytes at offset 65536",
            "read 512/512 bytes at offset 0",
            "read failed: Input/output error",
            "read failed: Input/output error",
            "wrote 512/512 bytes at offset 65536",
            "read 8192/8192 bytes at offset 8192"]


def test_drive_args_plain_and_through_blkdebug():
    m = _load()
    disk = os.path.abspath("t.img").replace("\\", "/")
    conf = os.path.abspath("b.conf").replace("\\", "/")
    assert m.drive_args("t.img") == [
        "-drive", "file=%s,format=raw,if=ide,index=1,media=disk" % disk]
    assert m.drive_args("t.img", "b.conf") == [
        "-drive",
        "file.driver=blkdebug,file.config=%s,file.image.filename=%s,"
        "format=raw,if=ide,index=1,media=disk,id=t1" % (conf, disk)]


def test_hmp_write_writes_one_sector_through_the_drive():
    assert _load().hmp_write(1474560) == 'qemu-io t1 "write -P 0 1474560 512"'


@pytest.mark.skipif(not os.path.exists(make_badfs.TEMPLATE),
                    reason="install floppy template not present")
def test_make_test_disk_is_dirty_and_padded():
    m = _load()
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "test.img")
        assert m.make_test_disk(p) == 1474560
        assert os.path.getsize(p) == 1474560 + m.PAD
        assert make_badfs.read_field(p, "fs_clean") == 0
        assert make_badfs.read_field(p, "fs_magic") == 0x00011954
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd vm && python -m pytest -q test_ufs_reload_inject.py`
Expected: 5 failed, `FileNotFoundError` for `ufs-reload-inject.py`.

- [ ] **Step 3: Implement**

Create `vm/ufs-reload-inject.py`:

```python
"""Gap 2 of the UFS gap tests: change 2 in ffs_reload, on the fixed kernel.
See docs/superpowers/specs/2026-09-25-ufs-gap-tests-design.md.

usage: python ufs-reload-inject.py RUN [--base IMG] [--port N]

  r1 r2 r3   a read error in ffs_reload's superblock (r1), cylinder-summary
             (r2) or root-inode-block (r3) read; each must be released so
             later mounts and the unmount still return
  r4         fs_ronly: a refused upgrade, umount, then a read-write mount,
             which must still be refused
  r5         the 4 GB clamp after a reload: a write ending at 4 GiB works,
             one past it fails with "File too large"

Each run boots a snapshot of work/ufs-gap/r-root/disk.qcow2 single-user,
with a fresh dirty test disk as hd1 at work/ufs-gap/RUN/test.img.  r1-r3
attach it through QEMU's blkdebug driver.  The host arms and disarms the
error by writing into padding past the filesystem over QMP, so the guest
never writes.
"""
import argparse
import os
import sys
import time

import make_badfs
import ufs_gap_lib as lib

PAD = 65536
DRIVE_ID = "t1"
SITES = {"r1": "superblock", "r2": "csum", "r3": "inode2"}

BLKDEBUG = """\
[set-state]
state = "1"
event = "write_aio"
new_state = "2"

[set-state]
state = "2"
event = "write_aio"
new_state = "3"

[inject-error]
state = "2"
event = "read_aio"
sector = "%d"
errno = "5"
once = "off"

[inject-error]
state = "3"
event = "read_aio"
sector = "%d"
errno = "5"
once = "off"
"""


def blkdebug_config(target_sector, dummy_sector):
    """blkdebug rules: reads succeed until the first write (arm); then every
    read covering target_sector fails with EIO, driver retries included,
    until the second write (disarm).  A fired once = off rule otherwise stays
    active forever, so state 3 has a rule of its own on dummy_sector, which
    only the host writes and nothing reads; the first read in state 3 makes
    it the active rule and the real error stops."""
    return BLKDEBUG % (target_sector, dummy_sector)


def drive_args(disk, conf=None):
    """QEMU arguments attaching disk as hd1, through blkdebug if conf."""
    disk = os.path.abspath(disk).replace("\\", "/")
    if conf is None:
        return ["-drive", "file=%s,format=raw,if=ide,index=1,media=disk" % disk]
    conf = os.path.abspath(conf).replace("\\", "/")
    return ["-drive",
            "file.driver=blkdebug,file.config=%s,file.image.filename=%s,"
            "format=raw,if=ide,index=1,media=disk,id=%s"
            % (conf, disk, DRIVE_ID)]


def hmp_write(offset):
    """The HMP command writing one zero sector at offset through hd1."""
    return 'qemu-io %s "write -P 0 %d 512"' % (DRIVE_ID, offset)


def make_test_disk(path):
    """A dirty make_badfs image with PAD zero bytes past the filesystem.
    Returns the byte offset where the padding starts."""
    make_badfs.build_good(path, pad=PAD)
    make_badfs.corrupt(path, "fs_clean", 0)
    return os.path.getsize(path) - PAD


def run(name, base, port):
    outdir = os.path.join(lib.WORK, name)
    if os.path.exists(outdir):
        raise SystemExit("%s already exists; evidence is never overwritten"
                         % outdir)
    if not lib.port_free(port):
        raise SystemExit("QMP port %d is in use" % port)
    root = os.path.join(lib.WORK, "r-root", "disk.qcow2")
    if not os.path.exists(root):
        lib.make_overlay(base, root)
    os.makedirs(outdir)
    disk = os.path.join(outdir, "test.img")
    pad_start = make_test_disk(disk)
    notes = []
    if name == "r5":
        maxfs = make_badfs.read_field(disk, "fs_maxfilesize")
        notes.append("on-disk fs_maxfilesize %d" % maxfs)
        if maxfs <= 1 << 32:
            raise SystemExit("fs_maxfilesize %d does not exceed 4 GiB; R5 "
                             "cannot tell fixed from unfixed" % maxfs)
    conf = None
    if name in SITES:
        sector = make_badfs.reload_sectors(disk)[SITES[name]]
        conf = os.path.join(outdir, "blkdebug.conf")
        with open(conf, "w") as f:
            f.write(blkdebug_config(sector, pad_start // 512))
        notes.append("EIO on sector %d (%s); arm at byte %d, disarm at %d"
                     % (sector, SITES[name], pad_start, pad_start + 512))

    gc = lib.load_guest_console()
    g = gc.Guest(outdir, port=port, image=os.path.abspath(root),
                 extra=drive_args(disk, conf))

    def step(cmd, wait, shot):
        g.line(cmd)
        time.sleep(wait)
        g.shot(shot)

    def hmp(offset, what):
        g.cmd("human-monitor-command", **{"command-line": hmp_write(offset)})
        notes.append(what)
        time.sleep(1)

    try:
        lib.single_user(g)
        step("mount -r /dev/hd1a /mnt", 5, "1-ro")
        if name in SITES:
            hmp(pad_start, "armed before the first mount -uw")
            step("mount -uw /mnt", 10, "2-upgrade-refused")
            hmp(pad_start + 512, "disarmed after it")
            step("ls /mnt; mount", 5, "3-still-ro")
            step("mount -uw /mnt", 10, "4-second-upgrade")
            step("umount /mnt", 8, "5-umount")
            step("mount", 5, "6-mount")
        elif name == "r4":
            step("mount -uw /mnt", 10, "2-upgrade-refused")
            step("umount /mnt", 8, "3-umount")
            step("mount /dev/hd1a /mnt", 8, "4-rw-mount")
            step("mount", 5, "5-mount")
        else:
            step("mount -uw /mnt", 10, "2-upgrade-refused")
            step("fsck -y /dev/hd1a", 60, "3-fsck")
            step("mount -uw /mnt", 10, "4-upgrade")
            step("mount", 5, "5-mount")
            step("dd if=/dev/zero of=/mnt/below bs=2 count=1 seek=2147483647",
                 15, "6-dd-below")
            step("ls -l /mnt/below", 5, "7-ls-below")
            step("dd if=/dev/zero of=/mnt/above bs=2 count=1 seek=2147483648",
                 15, "8-dd-above")
            step("ls -l /mnt", 5, "9-ls")
    finally:
        g.close()
    lib.write_result(outdir, notes)


def main(argv):
    p = argparse.ArgumentParser(description="UFS gap 2: change 2 in ffs_reload")
    p.add_argument("run", choices=("r1", "r2", "r3", "r4", "r5"))
    p.add_argument("--base", default=lib.BASE)
    p.add_argument("--port", type=int, default=4493)
    a = p.parse_args(argv[1:])
    run(a.run, a.base, a.port)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

- [ ] **Step 4: Run the tests**

Run: `cd vm && python -m pytest -q test_ufs_reload_inject.py`
Expected: 5 passed.

- [ ] **Step 5: Run every test this plan touches**

Run: `cd vm && python -m pytest -q test_guest_console.py test_make_badfs.py test_ufs_gap_lib.py test_ufs_e2e_image.py test_ufs_e2e_boot.py test_ufs_reload_inject.py test_rhap_inject.py`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add vm/ufs-reload-inject.py vm/test_ufs_reload_inject.py
git commit -m "vm: add the runner that injects read errors into ffs_reload through blkdebug"
```

---

### Task 7: Build the i386 kernel (coordinating session)

This task holds a guest password in a scratch file and drives a private build guest; the coordinating session runs it, not a subagent. Every command below starts with

```bash
S=C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/e9147e2a-6461-4ff1-b451-e73947bbb8ed/scratchpad
B=$S/ufsgap-build
```

- [ ] **Step 1: Pick ports.** List the other guests' ports and check the pair this task uses:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$S/qemu-list.ps1"
netstat -ano | grep LISTENING | grep -E '127.0.0.1:(2646|4646) ' || echo free
```

Expected: `free`. Otherwise pick the next free pair and use it throughout.

- [ ] **Step 2: Stage the scripts and source.**

```bash
mkdir -p $B/vm $B/export $B/logs
for f in rhap-remote.ps1 build-src-lib.ps1 sync-src.ps1 sync-src-lib.ps1 guest-remote.ps1; do git show HEAD:vm/$f > $B/vm/$f; done
git -c core.autocrlf=false archive HEAD^{tree} src/kernel-7 | tar -x -C $B/export
tr -cd '\r' < $B/export/src/kernel-7/conf/Makefile.i386 | wc -c
```

Expected: the last command prints 0. Then write `$B/vm/vm.conf` as a copy of `D:/RhapsodiOS/vm/vm.conf` with `Host=127.0.0.1`, `Port=2646`, `RemoteRoot=/build/ufsgap`, and `LocalRoot=` the Windows form of `$B/export`, as the post-merge ppc build did (never print its `Password=` line).

- [ ] **Step 3: Boot the build guest.** Copy `$S/p0merge/boot.py` to `$B/boot.py`, change `D` to `$B`, `-name` to `ufsgap`, the hostfwd to `127.0.0.1:2646-10.10.0.240:22` and the QMP port to 4646, then `python $B/boot.py`. It is a `-snapshot` boot of `D:/RhapsodiOS/vm/work/rhap-i386-bootstrapped.img`, a backing file other sessions share, which must never be written. Wait about five minutes; `$B/logs/kernel.log` shows the NE2000 registering first.

- [ ] **Step 4: Prepare the guest.** Write `$B/prep.sh`:

```sh
mkdir -p /build/ufsgap/src /build/ufsgap/state /build/ufsgap/out-i386 || exit 1
tc=/build/src/rbuild-1/toolchains/gcc-darwin-i386.conf
test -f $tc || { echo "no $tc"; exit 1; }
if grep '^path' $tc | grep /usr/local/bin > /dev/null; then
    cp $tc /build/ufsgap/gcc-darwin-i386-lb.conf
else
    sed '/^path/s|$|:/usr/local/bin|' $tc > /build/ufsgap/gcc-darwin-i386-lb.conf
fi
grep '^path' /build/ufsgap/gcc-darwin-i386-lb.conf
ps -axww | grep -E 'rbuild|make' | grep -v grep
echo done
```

Run it once (one real ssh attempt, no port polling), then sync:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$B/vm/guest-remote.ps1" -Run "$B/prep.sh"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$B/vm/sync-src.ps1" -Path kernel-7
```

Expected: a `path=` line ending in `:/usr/local/bin`, no other rbuild or make processes, then `sync-src: complete`.

- [ ] **Step 5: Build**, with the Bash tool's background mode. Write `$B/build-i386.sh`, filling the heredoc from `(cd $B/export/src && cksum kernel-7/bsd/ufs/ffs/ffs_vfsops.c kernel-7/bsd/ufs/ufs/ufs_readwrite.c)`:

```sh
cd /build/ufsgap/src || exit 1
cat > /tmp/ufsgap.expected <<'XEOF'
<the two cksum lines from the export>
XEOF
cksum kernel-7/bsd/ufs/ffs/ffs_vfsops.c kernel-7/bsd/ufs/ufs/ufs_readwrite.c > /tmp/ufsgap.actual
cmp -s /tmp/ufsgap.expected /tmp/ufsgap.actual || { echo "CKSUM MISMATCH"; diff /tmp/ufsgap.expected /tmp/ufsgap.actual; exit 2; }
echo "CKSUM OK"
PATH=/build/tools/bin:$PATH; export PATH
cd /
rbuild kernel --state /build/ufsgap/state --toolchain /build/ufsgap/gcc-darwin-i386-lb.conf --arch i386 /build/ufsgap/src /build/repo /build/ufsgap/out-i386 > /build/ufsgap/rbuild-i386.log 2>&1
rc=$?
echo "rbuild exit $rc"; tail -5 /build/ufsgap/rbuild-i386.log; ls -l /build/ufsgap/out-i386
exit $rc
```

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$B/vm/guest-remote.ps1" -Run "$B/build-i386.sh" > $B/logs/build-i386-run.log 2>&1; echo "exit $?"; tr -d '\r' < $B/logs/build-i386-run.log
```

Expected: `CKSUM OK`, `rbuild exit 0`, and `kernel-154.5.1-7-i386.apk` listed, in about 20 minutes. Do not poll the guest while it builds.

- [ ] **Step 6: Fetch and extract.**

```bash
mkdir -p D:/RhapsodiOS/.worktrees/ufs-gap-tests/vm/work/ufs-gap
MSYS_NO_PATHCONV=1 powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$B/vm/guest-remote.ps1" -Fetch /build/ufsgap/out-i386/kernel-154.5.1-7-i386.apk -To D:/RhapsodiOS/.worktrees/ufs-gap-tests/vm/work/ufs-gap/kernel-i386.apk
cd D:/RhapsodiOS/.worktrees/ufs-gap-tests/vm/work/ufs-gap && tar -xzf kernel-i386.apk private/tftpboot/mach_kernel && mv private/tftpboot/mach_kernel mach_kernel && rmdir -p private/tftpboot
head -c 4 mach_kernel | od -An -tx1
grep -a -c 'serial_dbg: i386 kernel console up' mach_kernel
grep -a -c 'was unclean when mounted' mach_kernel
```

Expected: `ce fa ed fe`, and each `grep` prints at least 1.

- [ ] **Step 7: Shut the build guest down.** Run one `guest-remote.ps1 -Run` of `ps -axww | grep -E 'sshd|rbuild|make' | grep -v grep` and confirm only the sshd listener and this session remain. Send QMP `qmp_capabilities` then `quit` to 127.0.0.1:4646. Confirm the process has exited, the ports are released, and `rhap-i386-bootstrapped.img`'s timestamp is unchanged. Then `rm $B/vm/vm.conf`.

---

### Task 8: Base image and its gate (coordinating session)

- [ ] **Step 1: Build the base.** From the worktree's `vm/`:

```bash
python ufs-e2e-image.py D:/RhapsodiOS/vm/golden.img work/ufs-gap/mach_kernel
```

Expected: `installed a <n>-byte kernel in inode 1253202; ufs_check: 0 problems`, and `work/ufs-e2e.img` exists (8 GB).

- [ ] **Step 2: Gate boot.**

```bash
python ufs-e2e-boot.py new gate
python ufs-e2e-boot.py fsck gate
```

Expected, from `work/ufs-gap/gate/fsck/`: `serial.log` has `serial_dbg: i386 kernel console up` (so the new kernel booted); the last `n-*.png` shots show `fsck -n` finishing phases 1–5 with no complaint lines, only the phase headers and the summary; `result.txt` lists no `ffs: ` lines. Any complaint stops the plan here: the base is not clean, and the E runs would test nothing.

---

### Task 9: Gap 1 runs (coordinating session)

Each command is run from the worktree's `vm/`. Read `serial.log`, `result.txt` and the screenshots of every run before starting the next.

- [ ] **Step 1: E1, clean control.**

```bash
python ufs-e2e-boot.py new e1
python ufs-e2e-boot.py multi e1
```

Pass: banner present; `result.txt` shows `network prompt after ...`, `initPointer: seen`, and no `ffs: ` lines; `final.png` shows the Setup Assistant. If `initPointer:` is not seen but `final.png` shows the Setup Assistant, pick a line from the end of E1's `serial.log` that follows the network prompt, set `MULTIUSER_MARKER` to it, commit that one-line change (`vm: wait for <line> as the multi-user marker`), and repeat E1 as `e1b`.

- [ ] **Step 2: E2, flag-only dirty root.**

```bash
python ufs-e2e-boot.py new e2 --dirty
python ufs-e2e-boot.py fsck e2
python ufs-e2e-boot.py multi e2
```

Pass: `e2/fsck` shows `fsck -n` reporting no damage beyond the unclean state (the premise). `e2/multi/result.txt` lists exactly one `ffs: / was unclean when mounted; mounting read-write anyway` and no other `ffs: ` line; the `t*.png` shots show `rc.boot`'s `fsck -p` passing; `final.png` matches E1's.

- [ ] **Step 3: E3, three real power-offs.** For `S` in 15, 30, 60:

```bash
python ufs-e2e-boot.py new e3-$S
python ufs-e2e-boot.py crash e3-$S $S
python ufs-e2e-boot.py multi e3-$S
python ufs-e2e-boot.py preen e3-$S
```

Pass for each: `crash/before-quit.png` shows the copy still running; `multi` reaches E1's end screen with no keystrokes beyond E1's. Its `result.txt` lists either no `ffs: ` line (fsck modified root and reloaded it) or exactly the E2 warning (fsck repaired only the flag); record which. `preen`'s `p-*.png` shows what preen repairs, and its `n-*.png` shows `fsck -n` clean afterwards. If `multi` stops, classify it by the spec's rule: a kernel refusal, panic or hang is a failure; `fsck -p` exiting 8 on genuine damage is a finding about `fsck` policy, recorded with what it named.

---

### Task 10: Gap 2 runs (coordinating session)

- [ ] **Step 1: R1–R3.** For each of `r1`, `r2`, `r3`:

```bash
python ufs-reload-inject.py r1
```

Pass: `result.txt` lists, in order, exactly `ffs: /mnt superblock reload failed (5), refusing read-write upgrade`, then `ffs: /mnt not cleanly unmounted, refusing read-write upgrade; run fsck`. `3-still-ro.png` shows `/mnt` listed and read-only. `4-second-upgrade.png`, `5-umount.png` and `6-mount.png` each show the prompt back, and `6-mount.png` no longer lists `/mnt`. For r3 especially, a first line of "not cleanly unmounted" instead of "reload failed" means the injected read was never reached: a failure. Record any IDE driver messages in `serial.log`.

- [ ] **Step 2: R4.**

```bash
python ufs-reload-inject.py r4
```

Pass: `result.txt` lists `ffs: /mnt not cleanly unmounted, refusing read-write upgrade; run fsck`, then `ffs: filesystem not cleanly unmounted, refusing; run fsck`; `5-mount.png` does not list `/mnt`.

- [ ] **Step 3: R5.**

```bash
python ufs-reload-inject.py r5
```

Pass: `result.txt` records an on-disk `fs_maxfilesize` above 4294967296 and lists the one refusal line; `3-fsck.png` shows `FILE SYSTEM MARKED CLEAN`; `5-mount.png` lists `/mnt` without `read-only`; `7-ls-below.png` shows `/mnt/below` at 4294967296 bytes; `8-dd-above.png` shows `File too large`. If `7-ls-below.png` shows any other size, `dd` cannot reach 64-bit offsets: record R5 as untestable with this userland, not passed.

---

### Task 11: Record the outcome

**Files:**
- Modify: `docs/superpowers/specs/2026-09-25-ufs-gap-tests-design.md` (append `## Outcome`)
- Modify: `docs/superpowers/specs/2026-09-21-ufs-xnu124-backport-design.md` ("The gap worth naming")
- Create: `.superpowers/sdd/ufs-gap-report.md` in the main checkout (untracked, like the other reports)

- [ ] **Step 1: Write the report** with, per run: the command, what each screenshot showed, the exact `ffs: ` lines, and PASS, FAIL, FINDING or UNTESTABLE.

- [ ] **Step 2: Append `## Outcome` to this plan's spec**: the kernel's source revision, the base image's checks, a table of E1, E2, E3 ×3 and R1–R5 with verdicts, what `fsck` repaired in each E3 run, and anything found. Follow the style of the UFS spec's Outcome: short sentences, bullets for series.

- [ ] **Step 3: Add a pointer** to the end of the UFS spec's "The gap worth naming" section:

```markdown
Change 2 and the end-to-end crash boot were later demonstrated on the fixed
kernel; see the Outcome of `2026-09-25-ufs-gap-tests-design.md`.
```

(adjust the wording to what the runs actually showed; if a run failed, say so instead).

- [ ] **Step 4: Run the full `vm/` suite** from the worktree: `cd vm && python -m pytest -q`. Expected: everything passes except `test_ahci_scripts`'s known failure, which master shares.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-09-25-ufs-gap-tests-design.md docs/superpowers/specs/2026-09-21-ufs-xnu124-backport-design.md
git commit -m "docs: record the UFS crash-boot and ffs_reload test results"
```

- [ ] **Step 6: Ask Pat** whether to keep `vm/work/ufs-e2e.img` (8 GB) and the overlays, before finishing the branch.
