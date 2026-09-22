# UFS/FFS xnu-124 Correctness Backport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port seven UFS/FFS correctness fixes from xnu-124 into `src/kernel-7/bsd/ufs`, and demonstrate the three that change what the kernel refuses.

**Architecture:** Each fix is a few lines in `ffs_vfsops.c` or `ufs_readwrite.c`. Because the guest has no readable shell output channel, every new refusal also emits one `printf` line, which reaches `vm/logs/ahci-serial.log` and is the machine-readable evidence. Two harnesses drive the refusals: malformed 1.44MB UFS images attached as a second QEMU disk, and a one-byte mutation of the root work image.

**Tech Stack:** C (Darwin 0.3 BSD kernel), Python 3 on the Windows host for image generation, `rbuild` on the Rhapsody build box, QEMU 11.1.0 (`qemu-system-i386`), QMP send-key for guest input.

**Spec:** [2026-09-21-ufs-xnu124-backport-design.md](../specs/2026-09-21-ufs-xnu124-backport-design.md)

## Global Constraints

```text
REPO   = D:\RhapsodiOS
FFS    = src/kernel-7/bsd/ufs/ffs/ffs_vfsops.c
RW     = src/kernel-7/bsd/ufs/ufs/ufs_readwrite.c
RUNNER = vm/run-q35-ahci.sh
SERIAL = vm/logs/ahci-serial.log
TMPL   = vm/install/rhapsody_dr2_x86_InstallationFloppy.img
```

Work in a dedicated worktree, not the main checkout. `.worktrees/` is gitignored.

```bash
git worktree add .worktrees/ufs-backport HEAD
```

- **The UEFI runners do not work.** `vm/firmware/OVMF32_CODE.fd` is absent and gitignored, so `run-q35-uefi.sh` and `run-pc-uefi-virtio-esp.sh` abort immediately. Use `vm/run-q35-ahci.sh` (BIOS), which also already implements `--second-disk`.
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

Bring `mach_kernel` back to the host, then from `vm/`:

```bash
cmd /c reset-image.cmd
python graft-kernel.py golden.img <path-to-mach_kernel> work/test.img
```

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

### Task 2: Positive control — prove the second-disk harness works

No kernel change. This runs the **current, unmodified** kernel and answers one question the rest of the plan depends on: what device node does a second disk get? Do not skip it; Tasks 4-6 cannot be interpreted without it.

**Files:**
- Create: `vm/work/good-control.img` (generated, not committed)
- Read: `vm/run-q35-ahci.sh:117-120` (the `--second-disk` wiring)

**Interfaces:**
- Consumes: `make_badfs.build_good` from Task 1.
- Produces: the confirmed second-disk device node, recorded in this plan's Task 2 checkbox notes and used verbatim by Tasks 4-6. Expected `/dev/hd1a`; confirm rather than assume.

- [ ] **Step 1: Build a known-good small image**

```bash
cd vm && python -c "import make_badfs; make_badfs.build_good('work/good-control.img')"
```

- [ ] **Step 2: Verify the runner accepts it**

Run: `sh vm/run-q35-ahci.sh --dry-run --second-disk vm/work/good-control.img vm/golden.img vm/work/test.img`
Expected: the printed argv contains `-drive if=none,id=ahci-second,format=raw,file=vm/work/good-control.img` and `-device ide-hd,drive=ahci-second,bus=ide.1`

- [ ] **Step 3: Boot to a single-user shell and mount it**

```bash
cd vm && cmd /c reset-image.cmd
sh run-q35-ahci.sh --second-disk work/good-control.img golden.img work/test.img
```

Then drive the guest with the `guest-console.py` pattern (`vm/guest-console.py:165-201`): at the boot prompt send `-s`, wait for single user, then send the mount command and screenshot.

```python
# run from vm/
from guest_console import Guest   # module is guest-console.py; import via importlib if the hyphen bites
g = Guest("out/task2", persist=True, port=4445)
g.line("-s"); import time; time.sleep(135)
g.line("mount /dev/hd1a /mnt"); time.sleep(5); g.shot("mount-hd1a")
g.line("df"); time.sleep(3); g.shot("df")
```

- [ ] **Step 4: Read the screenshots and record the device node**

Open `vm/out/task2/mount-hd1a.png` and `df.png`. Expected: the mount succeeds silently and `df` lists `/mnt`. If `mount` reports no such device, retry with `/dev/hd1b`, then `/dev/hd2a`, until one succeeds.

Write the working node into the checkbox below before continuing.

- [ ] **Step 5: Record the result**

Tasks 4 through 8 are written against `/dev/hd1a`. If Step 4 found a different
node, edit those tasks to match before running them — the mount commands are
otherwise correct as written.

- [ ] **Step 6: Commit the control image recipe note**

```bash
git add docs/superpowers/plans/2026-09-21-ufs-xnu124-backport.md
git commit -m "vm: record the confirmed second-disk device node for the UFS harness"
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

- [ ] **Step 6: Regression boot**

```bash
cd vm && sh run-q35-ahci.sh golden.img work/test.img
```

Expected: the machine boots to multi-user, root mounts read-write. Check `vm/logs/ahci-serial.log` contains no new panic or error text versus a pre-change boot.

- [ ] **Step 7: Commit**

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

```bash
cd vm && sh run-q35-ahci.sh --second-disk work/bad-magic.img golden.img work/test.img
```

Drive the guest as in Task 2 Step 3, substituting the recorded device node:

```python
g.line("-s"); time.sleep(135)
g.line("mount /dev/hd1a /mnt"); time.sleep(5); g.shot("bad-magic")
```

- [ ] **Step 5: Confirm the refusal**

Run: `grep "ffs: superblock magic invalid" vm/logs/ahci-serial.log`
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
- Modify: `src/kernel-7/bsd/ufs/ffs/ffs_vfsops.c:535-540`

**Interfaces:**
- Consumes: `make_badfs.corrupt(path, "fs_fsize", 256)`; the Task 2 device node.
- Produces: the serial-log token `ffs: fragment size`.

- [ ] **Step 1: Add the check beside the existing geometry validation**

`ffs_vfsops.c:535` currently begins:

```c
	if (fs->fs_magic != FS_MAGIC || fs->fs_bsize > MAXBSIZE ||
	    fs->fs_bsize < sizeof(struct fs)) {
```

Immediately **after** the closing brace of that existing validation block (the one that ends with `goto out;` and its `}`), insert:

```c
	if (fs->fs_fsize < DIRBLKSIZ) {
		printf("ffs: fragment size %d below DIRBLKSIZ, refusing\n",
		    fs->fs_fsize);
		error = ENOTSUP;
		goto out;
	}
```

- [ ] **Step 2: Add the missing include**

`DIRBLKSIZ` lives in `<ufs/ufs/dir.h>`, which `ffs_vfsops.c` does **not**
currently include — verified: its `ufs/ufs/` includes are `quota.h`,
`ufsmount.h`, `inode.h`, `ufs_extern.h` and `ufs_byte_order.h` only
(`:85-93`). Add it beside them:

```c
#include <ufs/ufs/dir.h>
```

Without this the build fails with `DIRBLKSIZ undeclared`.

- [ ] **Step 3: Build**

Run the build cycle.
Expected: clean compile.

- [ ] **Step 4: Generate the undersized-fragment image**

```bash
cd vm && python -c "
import make_badfs
make_badfs.build_good('work/bad-fsize.img')
make_badfs.corrupt('work/bad-fsize.img', 'fs_fsize', 256)"
```

- [ ] **Step 5: Boot and attempt the mount**

```bash
cd vm && sh run-q35-ahci.sh --second-disk work/bad-fsize.img golden.img work/test.img
```

Drive the guest as before, screenshotting as `bad-fsize`.

- [ ] **Step 6: Confirm the refusal**

Run: `grep "ffs: fragment size 256 below DIRBLKSIZ" vm/logs/ahci-serial.log`
Expected: one matching line.

- [ ] **Step 7: Confirm no regression on the good image**

Boot once more with `--second-disk work/good-control.img` and mount it.
Expected: still mounts. `golden.img`'s own fragment size is 1024, well above `DIRBLKSIZ` of 512, so root is unaffected.

- [ ] **Step 8: Commit**

```bash
git add src/kernel-7/bsd/ufs/ffs/ffs_vfsops.c
git commit -m "kernel: refuse a UFS fragment size below DIRBLKSIZ at mount"
```

---

### Task 6: Refuse an unclean non-root filesystem

Change 1a — the `ffs_mountfs` half of the dirty-mount gate.

**Files:**
- Modify: `src/kernel-7/bsd/ufs/ffs/ffs_vfsops.c`, in `ffs_mountfs` after the geometry checks from Task 5

**Interfaces:**
- Consumes: `make_badfs.corrupt(path, "fs_clean", 0)`; the Task 2 device node.
- Produces: the serial-log token `ffs: filesystem not cleanly unmounted`.

- [ ] **Step 1: Add the gate**

Immediately after the `fs_fsize` check added in Task 5, insert:

```c
	if (!ronly && (mp->mnt_flag & MNT_ROOTFS) == 0 && fs->fs_clean == 0) {
		printf("ffs: filesystem not cleanly unmounted, refusing; run fsck\n");
		error = ENOTSUP;
		goto out;
	}
```

`ronly` is already computed at `ffs_vfsops.c:505`. A read-only mount is still permitted — that is deliberate, and it is what lets `fsck` examine the volume. The root filesystem is excluded here and handled in Task 7.

- [ ] **Step 2: Build**

Run the build cycle.
Expected: clean compile.

- [ ] **Step 3: Generate the unclean image**

```bash
cd vm && python -c "
import make_badfs
make_badfs.build_good('work/dirty.img')
make_badfs.corrupt('work/dirty.img', 'fs_clean', 0)"
```

- [ ] **Step 4: Boot and attempt a read-write mount**

```bash
cd vm && sh run-q35-ahci.sh --second-disk work/dirty.img golden.img work/test.img
```

```python
g.line("-s"); time.sleep(135)
g.line("mount /dev/hd1a /mnt"); time.sleep(5); g.shot("dirty-rw")
g.line("mount -r /dev/hd1a /mnt"); time.sleep(5); g.shot("dirty-ro")
```

- [ ] **Step 5: Confirm the refusal and the read-only escape hatch**

Run: `grep "ffs: filesystem not cleanly unmounted" vm/logs/ahci-serial.log`
Expected: exactly one matching line — from the read-write attempt. The `dirty-ro.png` screenshot must show the read-only mount **succeeding**; if it also refused, the `!ronly` guard is wrong and must be fixed before committing.

- [ ] **Step 6: Commit**

```bash
git add src/kernel-7/bsd/ufs/ffs/ffs_vfsops.c
git commit -m "kernel: refuse a read-write mount of an unclean UFS filesystem"
```

---

### Task 7: Refuse a read-write upgrade of an unclean root

Change 1b. The riskiest change in the plan: get it wrong and the machine will not come up read-write.

**Files:**
- Modify: `src/kernel-7/bsd/ufs/ffs/ffs_vfsops.c:203-221`

**Interfaces:**
- Consumes: nothing from Task 1 — this harness mutates `vm/work/test.img` directly.
- Produces: the serial-log token `ffs: root not cleanly unmounted`.

- [ ] **Step 1: Gate the upgrade**

`ffs_vfsops.c:203` currently begins:

```c
		if (fs->fs_ronly && (mp->mnt_flag & MNT_WANTRDWR)) {
			/*
			 * If upgrade to read-write by non-root, then verify
			 * that user has necessary permissions on the device.
			 */
```

Insert the gate as the first statement inside that block, before the permission check:

```c
		if (fs->fs_ronly && (mp->mnt_flag & MNT_WANTRDWR)) {
			if (fs->fs_clean == 0) {
				printf("ffs: root not cleanly unmounted, refusing read-write upgrade; run fsck\n");
				return (EPERM);
			}
			/*
			 * If upgrade to read-write by non-root, then verify
			 * that user has necessary permissions on the device.
			 */
```

- [ ] **Step 2: Build**

Run the build cycle.
Expected: clean compile.

- [ ] **Step 3: Confirm the happy path still boots**

```bash
cd vm && sh run-q35-ahci.sh golden.img work/test.img
```

Expected: full multi-user boot. `work/test.img` has `fs_clean = 1`, so the gate must not fire. Run `grep "ffs: root not cleanly" vm/logs/ahci-serial.log` and expect **no** match. If it matches, stop — the gate is inverted and would brick every boot.

- [ ] **Step 4: Mark the root filesystem unclean**

```bash
cd vm && python -c "
import make_badfs
make_badfs.corrupt('work/test.img', 'fs_clean', 0)"
```

This reuses Task 1's `corrupt()` against the grafted work image. It is a single byte; `reset-image.cmd` restores the image if anything goes wrong.

- [ ] **Step 5: Boot and observe the refusal**

```bash
cd vm && sh run-q35-ahci.sh golden.img work/test.img
```

- [ ] **Step 6: Confirm**

Run: `grep "ffs: root not cleanly unmounted" vm/logs/ahci-serial.log`
Expected: one matching line, and the boot does not reach multi-user — it stops with root still read-only, which is the intended behaviour.

- [ ] **Step 7: Confirm fsck clears it**

At the single-user prompt:

```python
g.line("fsck -y /dev/hd0a"); time.sleep(120); g.shot("fsck")
g.line("mount -w /"); time.sleep(10); g.shot("remount")
```

Expected: `fsck` marks the filesystem clean and the subsequent read-write remount succeeds. This is the recovery path the spec promises; if it does not work, the gate is unusable and the task must be reconsidered rather than committed.

- [ ] **Step 8: Restore the image and commit**

```bash
cd vm && cmd /c reset-image.cmd
git add src/kernel-7/bsd/ufs/ffs/ffs_vfsops.c
git commit -m "kernel: refuse a read-write upgrade of an unclean root filesystem"
```

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

```bash
cd vm && sh run-q35-ahci.sh --second-disk work/good-control.img golden.img work/test.img
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

```bash
cd vm && sh run-q35-ahci.sh golden.img work/test.img
```

Expected: full boot, root read-write, no `ffs: ` lines in `vm/logs/ahci-serial.log`.

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
