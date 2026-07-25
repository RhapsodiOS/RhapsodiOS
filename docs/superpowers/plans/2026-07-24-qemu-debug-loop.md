# QEMU Debug Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Rhapsody DR2 guest debuggable under modern QEMU by building an offline UFS image injector (so a non-booting image can be modified from Windows) and an i386 kernel serial console (so kernel output can be captured with scrollback).

**Architecture:** A cheapest-first ladder. QEMU flag changes and IDE tracing cost nothing and may identify the bug outright. A read-only Python inspector for the NeXT-labelled, little-endian-UFS image comes next, then an in-place writer restricted to already-allocated blocks. A one-byte config edit (`"Multiple Sectors" = "No"`) may unwedge the boot, which restores every guest-side capability. Only then the kernel serial console, which needs the sacrificial-inode mechanism because the kernel has 704 bytes of headroom.

**Tech Stack:** Python 3.13 standard library only (no pip dependencies), `unittest` for tests, QEMU 11.0.50, Windows `cmd` for launch scripts, C for the kernel changes.

## Global Constraints

- **Python standard library only.** No pip installs. Tests use `unittest`, run with `python -m unittest`.
- **`vm/rhapsody.vmdk` is never opened for write.** It is the original artifact.
- **The injector writes only `vm/work/test.img`.** Path is checked; anything else is refused.
- **No allocation, ever.** No cylinder-group bitmaps, no summary counts, no directory-entry insertion, no block allocation. Only existing block contents, `di_size`, `di_mtime`, `d_ino`, and `di_nlink` are ever written.
- **The disk is mixed-endian.** The NeXT disk label is **big-endian**; the UFS filesystem is **little-endian**. Getting this backwards produces plausible-looking garbage.
- **`di_blocks` is in 1024-byte units** on this filesystem (NeXT `DEV_BSIZE`), not the usual 512.
- Kernel changes target **i386 only** and are guarded `#if defined(i386)` where they touch shared files.
- Commit after every task.

## Reference constants (verified against `vm/rhapsody.vmdk`)

These were measured, not derived. Tests assert them.

**Disk label** — big-endian, at byte offset 7680 (candidates: 7680, 15360, 23040, 30720; use the first with magic `dlV3`):

| Field | Offset | Type | Value |
|---|---|---|---|
| `dl_version` | 0 | char[4] | `dlV3` |
| `dl_label_blkno` | 4 | BE int32 | 15 |
| `d_secsize` | 92 | BE int32 | 1024 |
| `d_front` | 112 | BE int16 | 160 |
| `d_bootfile` | 132 | char[24] | `mach_kernel` |
| `d_rootpartition` | 188 | char | `a` |
| `p_base` (part a) | 190 | BE int32 | 0 |
| `p_size` (part a) | 194 | BE int32 | 8217087 |

`d_partitions` begins at **190**, immediately after `d_rwpartition` with no padding. This contradicts naive C-alignment arithmetic; it is empirically confirmed by `p_size` matching `fs_size` exactly.

Filesystem start = `(d_front + p_base) * d_secsize` = `(160 + 0) * 1024` = **163840**.

**Superblock** — little-endian, at 163840 + 8192 = **172032**:

| Field | Offset | Value |
|---|---|---|
| `fs_sblkno` | 8 | 16 |
| `fs_iblkno` | 16 | 32 |
| `fs_dblkno` | 20 | 520 |
| `fs_cgoffset` | 24 | 64 |
| `fs_cgmask` | 28 | -16 |
| `fs_size` | 36 | 8217087 |
| `fs_ncg` | 44 | 510 |
| `fs_bsize` | 48 | 8192 |
| `fs_fsize` | 52 | 1024 |
| `fs_frag` | 56 | 8 |
| `fs_nindir` | 116 | 2048 |
| `fs_inopb` | 120 | 64 |
| `fs_ipg` | 184 | 3904 |
| `fs_fpg` | 188 | 16128 |
| `fs_magic` | 1372 | 0x011954 |
| `fs_fsmnt` | 212 | `/` |

**Addressing:** `byte_offset = 163840 + frag_number * 1024` (because `fs_fsbtodb` is 0).

```
cgstart(c)  = fs_fpg * c + fs_cgoffset * (c & ~fs_cgmask)
cgimin(c)   = cgstart(c) + fs_iblkno
inode i     -> cg = i // fs_ipg, off = i % fs_ipg
              block = cgimin(cg) + (off // fs_inopb) * fs_frag
              entry = (off % fs_inopb) * 128
```

**On-disk inode** — 128 bytes, little-endian: `di_mode` u16@0, `di_nlink` i16@2, `di_size` u64@8, `di_mtime` i32@24, `di_db[12]` i32@40, `di_ib[3]` i32@88, `di_blocks` i32@104.

**Directory entry:** `d_ino` u32@0, `d_reclen` u16@4, `d_type` u8@6, `d_namlen` u8@7, name@8.

**Known-good values for tests:**

| Path | Inode | Size | `di_blocks` | Writable slack |
|---|---|---|---|---|
| `/` | 2 | 1024 | — | mode `040755` |
| `/mach_kernel` | 1253202 | 1459520 | 1440 | **704** |
| `/private/Drivers/i386/EIDE.config/EIDE_reloc` | 827669 | 121056 | 128 | **800** |
| `/private/Drivers/i386/EIDE.config/Instance0.table` | 827672 | 890 | 1 | **134** |
| `/System/Documentation/Developer/YellowBox/TasksAndConcepts/PB/ProjectBuilder.pdf` | — | 23221465 | 22704 | sacrificial candidate |

**Writable slack rule:** `max_writable = ceil(size / 1024) * 1024`. FFS packs several files' tails into one block, so writing past the file's own frag count would stomp a *different* file. Never use `di_blocks` as the bound.

## File Structure

| File | Responsibility |
|---|---|
| `vm/start-vm.cmd` | *(modify)* Launch QEMU: raw image, serial ports, no default CD-ROM, optional tracing |
| `vm/reset-image.cmd` | *(create)* Recreate `work/test.img` from `golden.img` |
| `vm/rhap_image.py` | *(create)* Read-only: label, superblock, inodes, block lists, path resolution |
| `vm/rhap_inject.py` | *(create)* Write path: in-place overwrite, sacrificial-inode repoint, safety rules |
| `vm/test_rhap_image.py` | *(create)* Tests for the reader |
| `vm/test_rhap_inject.py` | *(create)* Tests for the writer |
| `src/kernel-7/machdep/i386/serial_dbg.h` | *(create)* Serial console interface |
| `src/kernel-7/machdep/i386/serial_dbg.c` | *(create)* Polled 8250/16550 driver |
| `src/kernel-7/machdep/i386/i386_init.c` | *(modify)* `kernargs[]` entry, early init call |
| `src/kernel-7/bsd/dev/i386/cons.c` | *(modify)* Real `kprintf()` body |
| `src/kernel-7/bsd/kern/subr_prf.c` | *(modify)* Serial tap in `putchar()` |
| `src/kernel-7/conf/files.i386` | *(modify)* Build the new file |

Python module names use underscores (`rhap_image.py`) so they are importable; existing `vm/` scripts use hyphens but those are shell scripts, not modules.

---

### Task 1: QEMU harness and raw working image

**Files:**
- Modify: `vm/start-vm.cmd`
- Create: `vm/reset-image.cmd`
- Modify: `vm/.gitignore` (or `.gitignore`) to exclude `vm/work/` and `vm/golden.img`

**Interfaces:**
- Consumes: nothing
- Produces: `vm/golden.img` (raw, read-only), `vm/work/test.img` (raw, writable), a QEMU launch that exposes COM2 on stdio

- [ ] **Step 1: Create the golden raw image**

```bash
cd vm
qemu-img convert -O raw rhapsody.vmdk golden.img
```

Expected: completes in roughly 5 seconds, produces an 8589934592-byte file.

- [ ] **Step 2: Verify the golden image is faithful**

```bash
cd vm
python -c "d=open('golden.img','rb').read(8192); print(d[7680:7684])"
```

Expected: `b'dlV3'`

- [ ] **Step 3: Write `vm/reset-image.cmd`**

```bat
@echo off
setlocal
cd /d "%~dp0"

if not exist golden.img (
    echo ERROR: golden.img missing. Run: qemu-img convert -O raw rhapsody.vmdk golden.img
    exit /b 1
)

if not exist work mkdir work
if exist work\test.img del work\test.img

echo Recreating work\test.img from golden.img ...
qemu-img convert -O raw golden.img work\test.img
if errorlevel 1 exit /b 1

echo Done.
exit /b 0
```

- [ ] **Step 4: Run it and confirm the working image appears**

```bash
cd vm && cmd //c reset-image.cmd && ls -la work/test.img
```

Expected: `Done.` and an 8589934592-byte `work/test.img`.

- [ ] **Step 5: Rewrite `vm/start-vm.cmd`**

`-nodefaults` removes QEMU's default empty DVD-ROM, which is what produced the `hc1` ATAPI TEST UNIT READY failures. VGA and the NIC are added back explicitly. Port order matters: the first `-serial` is COM1 (0x3f8, owned by `drvISASerialPort`), the second is COM2 (0x2f8), which is where the kernel console will appear.

```bat
@echo off
setlocal
cd /d "%~dp0"

if not exist work\test.img (
    echo ERROR: work\test.img missing. Run reset-image.cmd first.
    exit /b 1
)

set TRACEARGS=
if /i "%~1"=="-trace" (
    if not exist logs mkdir logs
    set TRACEARGS=-trace enable=ide_* -trace enable=pci_cfg_* -d int -D logs\qemu-trace.log
    echo Tracing enabled -^> logs\qemu-trace.log
)

echo Launching QEMU. Kernel serial output ^(COM2^) appears in this window.
echo.

qemu-system-i386 -M pc -cpu pentium -accel tcg -m 128 -k en-us ^
  -nodefaults -vga cirrus ^
  -drive file=work\test.img,format=raw,if=ide,index=0,media=disk ^
  -netdev user,id=n0 -device ne2k_pci,netdev=n0 ^
  -serial null -serial stdio ^
  -rtc base=1999-01-01 ^
  -boot order=c %TRACEARGS%

echo.
exit /b %ERRORLEVEL%
```

- [ ] **Step 6: Boot and confirm the CD-ROM is gone**

```bash
cd vm && cmd //c start-vm.cmd
```

Expected on the VGA window: the boot proceeds as before, but `hc1` no longer reports `Checking for ATAPI drive 0... Detected`, there is no `sd0: QEMU QEMU DVD-ROM`, no `hc1: FATAL: ATAPI Drive: 0 Command 0 failed`, and no `WARNING: preposterous time in Real Time Clock`.

The `hc0: interrupt timeout, cmd: 0xc4` wedge is **expected to persist**. If it disappears, the hypothesis in the spec is wrong and the ATAPI path was implicated after all — stop and reassess before continuing.

- [ ] **Step 7: Ignore generated images**

Append to `.gitignore`:

```
vm/work/
vm/golden.img
vm/logs/
```

- [ ] **Step 8: Commit**

```bash
git add vm/start-vm.cmd vm/reset-image.cmd .gitignore
git commit -m "vm: boot a raw working image with COM2 on stdio and no default CD-ROM"
```

---

### Task 2: IDE tracing and interrupt diagnosis

**Files:**
- Test: manual observation of `vm/logs/qemu-trace.log`

**Interfaces:**
- Consumes: `vm/start-vm.cmd -trace` from Task 1
- Produces: a determination of whether QEMU raises IRQ 14 and whether the driver acknowledges it

- [ ] **Step 1: Boot with tracing**

```bash
cd vm && cmd //c start-vm.cmd -trace
```

Let it run until `hc0: ATA drive 0 is not present.` appears, then close QEMU.

- [ ] **Step 2: Find the last successful command before the wedge**

```bash
cd vm && grep -n "ide_bus_exec_cmd" logs/qemu-trace.log | tail -20
```

Expected: a series of commands ending with `cmd 0xc4` (READ MULTIPLE), then `0xec` (IDENTIFY).

- [ ] **Step 3: Check whether the driver reads Status after the failing command**

```bash
cd vm && grep -n "ide_status_read\|ide_ctrl_write\|ide_bus_exec_cmd" logs/qemu-trace.log | tail -40
```

Reading the ATA Status register is what deasserts INTRQ. On an edge-triggered ISA IRQ 14, a missing Status read means no further interrupt can ever be delivered.

- [ ] **Step 4: Check whether nIEN was set and left set**

```bash
cd vm && grep -n "ide_ctrl_write" logs/qemu-trace.log | tail -20
```

`ide_ctrl_write` logs writes to 0x3F6. Bit 1 is `nIEN`; if set and never cleared, the device stops asserting INTRQ entirely.

- [ ] **Step 5: Record the finding**

Append a short section to `docs/drivers/drvEIDE-issues.md` under §2 stating which of the two mechanisms the trace shows: no IRQ raised by QEMU, an IRQ raised but never acknowledged, or `nIEN` left set. Quote the three or four relevant trace lines.

- [ ] **Step 6: Commit**

```bash
git add docs/drivers/drvEIDE-issues.md
git commit -m "drvEIDE: record QEMU IDE trace evidence for the IRQ 14 timeout"
```

---

### Task 3: Image reader — disk label and superblock

**Files:**
- Create: `vm/rhap_image.py`
- Create: `vm/test_rhap_image.py`

**Interfaces:**
- Consumes: `vm/golden.img` from Task 1
- Produces:
  - `class Image(path)` with attributes `part_start` (int, bytes), `fsize`, `bsize`, `frag`, `ipg`, `fpg`, `cgoffset`, `cgmask`, `iblkno`, `inopb`, `nindir`, `ncg`, `fs_size`
  - `Image.label` -> `dict` with keys `blkno`, `secsize`, `front`, `bootfile`, `rootpartition`, `p_base`, `p_size`
  - `Image.read_frag(frag_no, nbytes) -> bytes`

- [ ] **Step 1: Write the failing test**

Create `vm/test_rhap_image.py`:

```python
import os
import unittest

import rhap_image

IMAGE = os.path.join(os.path.dirname(__file__), "golden.img")


@unittest.skipUnless(os.path.exists(IMAGE), "golden.img not built yet")
class TestLabel(unittest.TestCase):
    def setUp(self):
        self.img = rhap_image.Image(IMAGE)

    def test_label_is_big_endian_and_sane(self):
        lab = self.img.label
        self.assertEqual(lab["blkno"], 15)
        self.assertEqual(lab["secsize"], 1024)
        self.assertEqual(lab["front"], 160)
        self.assertEqual(lab["bootfile"], "mach_kernel")
        self.assertEqual(lab["rootpartition"], "a")

    def test_partition_a_offsets(self):
        lab = self.img.label
        self.assertEqual(lab["p_base"], 0)
        self.assertEqual(lab["p_size"], 8217087)

    def test_partition_start(self):
        self.assertEqual(self.img.part_start, 163840)


@unittest.skipUnless(os.path.exists(IMAGE), "golden.img not built yet")
class TestSuperblock(unittest.TestCase):
    def setUp(self):
        self.img = rhap_image.Image(IMAGE)

    def test_geometry(self):
        self.assertEqual(self.img.bsize, 8192)
        self.assertEqual(self.img.fsize, 1024)
        self.assertEqual(self.img.frag, 8)
        self.assertEqual(self.img.ipg, 3904)
        self.assertEqual(self.img.fpg, 16128)
        self.assertEqual(self.img.ncg, 510)
        self.assertEqual(self.img.inopb, 64)
        self.assertEqual(self.img.nindir, 2048)

    def test_label_and_superblock_agree(self):
        # p_size is in d_secsize units, fs_size in frags; both are 1024 bytes.
        self.assertEqual(self.img.fs_size, self.img.label["p_size"])

    def test_is_root_filesystem(self):
        self.assertEqual(self.img.fsmnt, "/")
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd vm && python -m unittest test_rhap_image -v
```

Expected: FAIL with `ModuleNotFoundError: No module named 'rhap_image'`

- [ ] **Step 3: Write the implementation**

Create `vm/rhap_image.py`:

```python
"""Read-only reader for the Rhapsody DR2 disk image.

The disk is mixed-endian: the NeXT disk label is big-endian, the UFS
filesystem inside it is little-endian.  Offsets here were measured against
vm/rhapsody.vmdk, cross-validated by p_size == fs_size.

Label layout follows src/kernel-7/bsd/dev/disk_label.h and
src/kernel-7/bsd/sys/disktab.h; the partition-start formula is what the boot
loader computes at src/boot-2/i386/libsaio/disk.c:381.
"""

import struct

LABEL_OFFSETS = (7680, 15360, 23040, 30720)
LABEL_MAGIC = b"dlV3"

FS_MAGIC = 0x011954
SBOFF = 8192
MAGIC_OFF = 1372
DINODE_SIZE = 128


def _cstr(buf):
    return buf.split(b"\0", 1)[0].decode("ascii", "replace")


class Image(object):
    def __init__(self, path, writable=False):
        self.path = path
        self._f = open(path, "r+b" if writable else "rb")
        self.label = self._read_label()
        self.part_start = (self.label["front"] + self.label["p_base"]) * self.label[
            "secsize"
        ]
        self._read_superblock()

    def close(self):
        self._f.close()

    def _read_at(self, offset, n):
        self._f.seek(offset)
        return self._f.read(n)

    def _read_label(self):
        for off in LABEL_OFFSETS:
            buf = self._read_at(off, 1024)
            if buf[:4] == LABEL_MAGIC:
                self.label_offset = off
                return {
                    "blkno": struct.unpack_from(">i", buf, 4)[0],
                    "secsize": struct.unpack_from(">i", buf, 92)[0],
                    "front": struct.unpack_from(">h", buf, 112)[0],
                    "bootfile": _cstr(buf[132:156]),
                    "rootpartition": chr(buf[188]),
                    "p_base": struct.unpack_from(">i", buf, 190)[0],
                    "p_size": struct.unpack_from(">i", buf, 194)[0],
                }
        raise ValueError("no NeXT disk label found in %s" % self.path)

    def _read_superblock(self):
        sb = self._read_at(self.part_start + SBOFF, SBOFF)
        magic = struct.unpack_from("<i", sb, MAGIC_OFF)[0]
        if magic != FS_MAGIC:
            raise ValueError("bad UFS magic 0x%x at %d" % (magic, self.part_start + SBOFF))
        g = lambda o: struct.unpack_from("<i", sb, o)[0]
        self.iblkno = g(16)
        self.cgoffset = g(24)
        self.cgmask = g(28)
        self.fs_size = g(36)
        self.ncg = g(44)
        self.bsize = g(48)
        self.fsize = g(52)
        self.frag = g(56)
        self.nindir = g(116)
        self.inopb = g(120)
        self.ipg = g(184)
        self.fpg = g(188)
        self.fsmnt = _cstr(sb[212:212 + 512])

    def frag_offset(self, frag_no):
        """Byte offset of a fragment.  fs_fsbtodb is 0 on this filesystem."""
        return self.part_start + frag_no * self.fsize

    def read_frag(self, frag_no, nbytes):
        return self._read_at(self.frag_offset(frag_no), nbytes)
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd vm && python -m unittest test_rhap_image -v
```

Expected: 6 tests, all PASS.

- [ ] **Step 5: Commit**

```bash
git add vm/rhap_image.py vm/test_rhap_image.py
git commit -m "vm: add read-only NeXT label and UFS superblock reader"
```

---

### Task 4: Image reader — inodes, block lists, path resolution

**Files:**
- Modify: `vm/rhap_image.py`
- Modify: `vm/test_rhap_image.py`

**Interfaces:**
- Consumes: `Image` from Task 3
- Produces:
  - `Image.inode(ino) -> Inode`
  - `Inode` with `.ino`, `.mode`, `.nlink`, `.size`, `.blocks`, `.db` (list of 12), `.ib` (list of 3)
  - `Inode.frags()` -> list of fragment numbers covering the file, holes as 0
  - `Image.read_file(ino) -> bytes`
  - `Image.resolve(path) -> int | None`
  - `Image.listdir(path) -> list of (name, ino, dtype)`
  - `Image.max_writable(ino) -> int`

- [ ] **Step 1: Write the failing test**

Append to `vm/test_rhap_image.py`:

```python
@unittest.skipUnless(os.path.exists(IMAGE), "golden.img not built yet")
class TestInodes(unittest.TestCase):
    def setUp(self):
        self.img = rhap_image.Image(IMAGE)

    def test_root_inode(self):
        root = self.img.inode(2)
        self.assertEqual(root.mode & 0o170000, 0o040000)
        self.assertEqual(root.mode & 0o7777, 0o755)

    def test_root_listing_contains_expected_entries(self):
        names = [e[0] for e in self.img.listdir("/")]
        for expected in ("mach_kernel", "private", "usr", "System", "sbin"):
            self.assertIn(expected, names)

    def test_resolve_mach_kernel(self):
        self.assertEqual(self.img.resolve("/mach_kernel"), 1253202)

    def test_mach_kernel_metadata(self):
        ino = self.img.inode(self.img.resolve("/mach_kernel"))
        self.assertEqual(ino.size, 1459520)
        self.assertEqual(ino.blocks, 1440)

    def test_resolve_nested_driver_path(self):
        p = "/private/Drivers/i386/EIDE.config/Instance0.table"
        self.assertEqual(self.img.resolve(p), 827672)

    def test_missing_path_returns_none(self):
        self.assertIsNone(self.img.resolve("/no/such/file"))

    def test_read_instance_table(self):
        p = "/private/Drivers/i386/EIDE.config/Instance0.table"
        data = self.img.read_file(self.img.resolve(p))
        self.assertEqual(len(data), 890)
        self.assertIn(b'"Multiple Sectors" = "Yes";', data)

    def test_max_writable_is_frag_rounded_size(self):
        p = "/private/Drivers/i386/EIDE.config/Instance0.table"
        ino = self.img.resolve(p)
        # 890 bytes -> one 1024-byte fragment
        self.assertEqual(self.img.max_writable(ino), 1024)

    def test_max_writable_kernel_slack_is_small(self):
        ino = self.img.resolve("/mach_kernel")
        self.assertEqual(self.img.max_writable(ino), 1460224)
        self.assertEqual(self.img.max_writable(ino) - self.img.inode(ino).size, 704)

    def test_indirect_blocks_are_followed(self):
        # EIDE_reloc is 121056 bytes, past the 12 direct blocks (98304 bytes)
        p = "/private/Drivers/i386/EIDE.config/EIDE_reloc"
        data = self.img.read_file(self.img.resolve(p))
        self.assertEqual(len(data), 121056)
        self.assertEqual(data[:4], b"\xce\xfa\xed\xfe")  # Mach-O, little-endian
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd vm && python -m unittest test_rhap_image -v
```

Expected: FAIL with `AttributeError: 'Image' object has no attribute 'inode'`

- [ ] **Step 3: Write the implementation**

Append to `vm/rhap_image.py`:

```python
NDADDR = 12
NIADDR = 3


class Inode(object):
    def __init__(self, ino, buf):
        self.ino = ino
        self.mode, self.nlink = struct.unpack_from("<Hh", buf, 0)
        self.size = struct.unpack_from("<Q", buf, 8)[0]
        self.mtime = struct.unpack_from("<i", buf, 24)[0]
        self.db = list(struct.unpack_from("<%di" % NDADDR, buf, 40))
        self.ib = list(struct.unpack_from("<%di" % NIADDR, buf, 88))
        self.blocks = struct.unpack_from("<i", buf, 104)[0]

    def is_dir(self):
        return (self.mode & 0o170000) == 0o040000

    def is_reg(self):
        return (self.mode & 0o170000) == 0o100000


def _cgstart(img, c):
    return img.fpg * c + img.cgoffset * (c & ~img.cgmask)


def _inode_location(img, ino):
    cg = ino // img.ipg
    off = ino % img.ipg
    frag = _cgstart(img, cg) + img.iblkno + (off // img.inopb) * img.frag
    return frag, (off % img.inopb) * DINODE_SIZE


def _inode(self, ino):
    frag, entry = _inode_location(self, ino)
    blk = self.read_frag(frag, self.bsize)
    return Inode(ino, blk[entry:entry + DINODE_SIZE])


def _frags(self, inode):
    """Fragment numbers covering the file.  Holes appear as 0."""
    need = (inode.size + self.fsize - 1) // self.fsize
    out = []

    def take(frag_of_block):
        # A block covers fs_frag fragments with consecutive numbers.
        for k in range(self.frag):
            if len(out) >= need:
                return
            out.append(frag_of_block + k if frag_of_block else 0)

    for b in inode.db:
        if len(out) >= need:
            break
        take(b)

    if len(out) < need and inode.ib[0]:
        ind = self.read_frag(inode.ib[0], self.bsize)
        for b in struct.unpack_from("<%di" % self.nindir, ind, 0):
            if len(out) >= need:
                break
            take(b)

    if len(out) < need and inode.ib[1]:
        l1 = self.read_frag(inode.ib[1], self.bsize)
        for b1 in struct.unpack_from("<%di" % self.nindir, l1, 0):
            if len(out) >= need:
                break
            if not b1:
                # A zero entry here is a hole spanning nindir blocks, not the end.
                for _ in range(self.nindir):
                    if len(out) >= need:
                        break
                    take(0)
                continue
            l2 = self.read_frag(b1, self.bsize)
            for b in struct.unpack_from("<%di" % self.nindir, l2, 0):
                if len(out) >= need:
                    break
                take(b)

    if len(out) < need:
        raise ValueError(
            "inode %d: block list resolved %d of %d fragments; "
            "file may need triple-indirect blocks, which are not supported"
            % (inode.ino, len(out), need)
        )

    return out[:need]


def _read_file(self, ino):
    inode = self.inode(ino) if isinstance(ino, int) else ino
    buf = bytearray()
    for f in self.frags(inode):
        buf += self.read_frag(f, self.fsize) if f else bytes(self.fsize)
    return bytes(buf[:inode.size])


def _iter_dir(self, ino):
    data = self.read_file(ino)
    p = 0
    while p < len(data):
        d_ino, d_reclen = struct.unpack_from("<IH", data, p)
        d_type = data[p + 6]
        d_namlen = data[p + 7]
        if d_reclen == 0:
            break
        if d_ino:
            name = data[p + 8:p + 8 + d_namlen].decode("ascii", "replace")
            yield name, d_ino, d_type, p
        p += d_reclen


def _listdir(self, path):
    ino = self.resolve(path)
    if ino is None:
        raise FileNotFoundError(path)
    return [(n, i, t) for n, i, t, _ in self.iter_dir(ino)]


def _lookup(self, dir_ino, name):
    for n, i, _t, _off in self.iter_dir(dir_ino):
        if n == name:
            return i
    return None


def _resolve(self, path):
    ino = 2
    for part in path.strip("/").split("/"):
        if not part:
            continue
        ino = self.lookup(ino, part)
        if ino is None:
            return None
    return ino


def _max_writable(self, ino):
    """Bytes that may be overwritten in place.

    Rounded up to a fragment because FFS packs several files' tails into one
    block: writing past this file's own fragment count would corrupt an
    unrelated file.
    """
    inode = self.inode(ino) if isinstance(ino, int) else ino
    return ((inode.size + self.fsize - 1) // self.fsize) * self.fsize


Image.inode = _inode
Image.frags = _frags
Image.read_file = _read_file
Image.iter_dir = _iter_dir
Image.listdir = _listdir
Image.lookup = _lookup
Image.resolve = _resolve
Image.max_writable = _max_writable
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd vm && python -m unittest test_rhap_image -v
```

Expected: 16 tests, all PASS.

- [ ] **Step 5: Commit**

```bash
git add vm/rhap_image.py vm/test_rhap_image.py
git commit -m "vm: add UFS inode, block list and path resolution to the image reader"
```

---

### Task 5: Inspector CLI

**Files:**
- Modify: `vm/rhap_image.py`

**Interfaces:**
- Consumes: `Image` from Tasks 3 and 4
- Produces: `python rhap_image.py <image> {ls|stat|cat|slack} <path>`

- [ ] **Step 1: Add the CLI**

Append to `vm/rhap_image.py`:

```python
def _fmt_stat(img, path):
    ino = img.resolve(path)
    if ino is None:
        return "%s: not found" % path
    n = img.inode(ino)
    frags = img.frags(n)
    holes = sum(1 for f in frags if f == 0)
    return (
        "%s\n  inode      %d\n  mode       0%o\n  nlink      %d\n"
        "  size       %d\n  di_blocks  %d (x1024 = %d bytes)\n"
        "  writable   %d (slack %d)\n  holes      %d"
        % (
            path, ino, n.mode, n.nlink, n.size, n.blocks, n.blocks * 1024,
            img.max_writable(n), img.max_writable(n) - n.size, holes,
        )
    )


def main(argv):
    if len(argv) < 4:
        print("usage: rhap_image.py <image> {ls|stat|cat|slack} <path>")
        return 2
    path_img, cmd, path = argv[1], argv[2], argv[3]
    img = Image(path_img)
    if cmd == "ls":
        for name, ino, dtype in img.listdir(path):
            kind = {4: "dir", 8: "reg", 10: "lnk"}.get(dtype, str(dtype))
            print("  %-32s ino=%-9d %s" % (name, ino, kind))
    elif cmd == "stat":
        print(_fmt_stat(img, path))
    elif cmd == "cat":
        ino = img.resolve(path)
        if ino is None:
            print("%s: not found" % path)
            return 1
        import sys as _sys
        _sys.stdout.buffer.write(img.read_file(ino))
    elif cmd == "slack":
        ino = img.resolve(path)
        if ino is None:
            print("%s: not found" % path)
            return 1
        n = img.inode(ino)
        print("%d %d %d" % (n.size, img.max_writable(n), img.max_writable(n) - n.size))
    else:
        print("unknown command: %s" % cmd)
        return 2
    return 0


if __name__ == "__main__":
    import sys
    raise SystemExit(main(sys.argv))
```

- [ ] **Step 2: Verify `ls` against the driver bundle**

```bash
cd vm && python rhap_image.py golden.img ls /private/Drivers/i386/EIDE.config
```

Expected output includes:

```
  EIDE_reloc                       ino=827669    reg
  Instance0.table                  ino=827672    reg
  Default.table                    ino=827673    reg
```

- [ ] **Step 3: Verify `stat` reports the expected slack**

```bash
cd vm && python rhap_image.py golden.img stat /mach_kernel
```

Expected: `size 1459520`, `di_blocks 1440`, `writable 1460224 (slack 704)`, `holes 0`.

- [ ] **Step 4: Verify `cat` on the live config table**

```bash
cd vm && python rhap_image.py golden.img cat /private/Drivers/i386/EIDE.config/Instance0.table | grep "Multiple Sectors"
```

Expected: `"Multiple Sectors" = "Yes";`

- [ ] **Step 5: Commit**

```bash
git add vm/rhap_image.py
git commit -m "vm: add ls/stat/cat/slack inspector CLI for the disk image"
```

---

### Task 6: In-place writer with safety rules

**Files:**
- Create: `vm/rhap_inject.py`
- Create: `vm/test_rhap_inject.py`

**Interfaces:**
- Consumes: `rhap_image.Image` (opened with `writable=True`)
- Produces:
  - `write_file(img, path, data)` — overwrite in place, update `di_size` and `di_mtime`, verify by read-back
  - `SafetyError` — raised by every refusal
  - `check_target(image_path)` — refuses anything but `work/test.img`

- [ ] **Step 1: Write the failing test**

Create `vm/test_rhap_inject.py`:

```python
import os
import shutil
import unittest

import rhap_image
import rhap_inject

HERE = os.path.dirname(__file__)
GOLDEN = os.path.join(HERE, "golden.img")
WORK = os.path.join(HERE, "work", "test.img")
TABLE = "/private/Drivers/i386/EIDE.config/Instance0.table"


@unittest.skipUnless(os.path.exists(WORK), "work/test.img not built yet")
class TestSafety(unittest.TestCase):
    def test_refuses_non_work_image(self):
        with self.assertRaises(rhap_inject.SafetyError):
            rhap_inject.check_target(GOLDEN)

    def test_accepts_work_image(self):
        rhap_inject.check_target(WORK)  # must not raise

    def test_refuses_oversized_payload(self):
        img = rhap_image.Image(WORK, writable=True)
        try:
            oversized = b"x" * (img.max_writable(img.resolve(TABLE)) + 1)
            with self.assertRaises(rhap_inject.SafetyError):
                rhap_inject.write_file(img, TABLE, oversized)
        finally:
            img.close()

    def test_refuses_missing_path(self):
        img = rhap_image.Image(WORK, writable=True)
        try:
            with self.assertRaises(rhap_inject.SafetyError):
                rhap_inject.write_file(img, "/no/such/file", b"hi")
        finally:
            img.close()


@unittest.skipUnless(os.path.exists(WORK), "work/test.img not built yet")
class TestRoundTrip(unittest.TestCase):
    def test_write_then_read_back(self):
        img = rhap_image.Image(WORK, writable=True)
        try:
            original = img.read_file(img.resolve(TABLE))
            modified = original.replace(
                b'"Multiple Sectors" = "Yes";', b'"Multiple Sectors" = "No";'
            )
            self.assertNotEqual(original, modified)
            rhap_inject.write_file(img, TABLE, modified)
        finally:
            img.close()

        img = rhap_image.Image(WORK)
        try:
            self.assertEqual(img.read_file(img.resolve(TABLE)), modified)
            self.assertEqual(img.inode(img.resolve(TABLE)).size, len(modified))
        finally:
            img.close()

        # restore
        img = rhap_image.Image(WORK, writable=True)
        try:
            rhap_inject.write_file(img, TABLE, original)
        finally:
            img.close()

    def test_shrinking_write_updates_size(self):
        img = rhap_image.Image(WORK, writable=True)
        try:
            original = img.read_file(img.resolve(TABLE))
            rhap_inject.write_file(img, TABLE, original[:100])
            self.assertEqual(img.inode(img.resolve(TABLE)).size, 100)
            rhap_inject.write_file(img, TABLE, original)
            self.assertEqual(img.inode(img.resolve(TABLE)).size, len(original))
        finally:
            img.close()
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd vm && python -m unittest test_rhap_inject -v
```

Expected: FAIL with `ModuleNotFoundError: No module named 'rhap_inject'`

- [ ] **Step 3: Write the implementation**

Create `vm/rhap_inject.py`:

```python
"""In-place writer for the Rhapsody disk image.

Never allocates.  Only the contents of already-mapped fragments, di_size,
di_mtime, d_ino and di_nlink are ever modified.  Every refusal raises
SafetyError rather than writing something questionable.
"""

import os
import struct

import rhap_image


class SafetyError(Exception):
    pass


def check_target(image_path):
    """Refuse to write anything but vm/work/test.img."""
    norm = os.path.normpath(os.path.abspath(image_path)).replace("\\", "/")
    if not norm.endswith("/work/test.img"):
        raise SafetyError(
            "refusing to write %s; only vm/work/test.img may be modified" % image_path
        )
    return True


def _write_inode_fields(img, ino, size=None, mtime=None, nlink=None):
    frag, entry = rhap_image._inode_location(img, ino)
    off = img.frag_offset(frag) + entry
    img._f.seek(off)
    buf = bytearray(img._f.read(rhap_image.DINODE_SIZE))
    if size is not None:
        struct.pack_into("<Q", buf, 8, size)
    if mtime is not None:
        struct.pack_into("<i", buf, 24, mtime)
    if nlink is not None:
        struct.pack_into("<h", buf, 2, nlink)
    img._f.seek(off)
    img._f.write(bytes(buf))
    img._f.flush()


def write_file(img, path, data, mtime=None):
    """Overwrite an existing file in place.

    Refuses if the path does not exist, if the payload exceeds the file's
    already-allocated fragments, or if the file has holes.
    """
    check_target(img.path)

    ino = img.resolve(path)
    if ino is None:
        raise SafetyError("%s does not exist; this writer cannot create files" % path)

    inode = img.inode(ino)
    if not inode.is_reg():
        raise SafetyError("%s is not a regular file" % path)

    limit = img.max_writable(inode)
    if len(data) > limit:
        raise SafetyError(
            "%s: payload %d bytes exceeds allocated %d bytes (slack %d)"
            % (path, len(data), limit, limit - inode.size)
        )

    frags = img.frags(inode)
    if any(f == 0 for f in frags):
        raise SafetyError("%s has holes; refusing in-place write" % path)

    # The new content may need fewer fragments than the old; only write what
    # we have, then shrink di_size.
    payload = bytearray(data)
    need = (len(payload) + img.fsize - 1) // img.fsize
    payload += bytes(need * img.fsize - len(payload))

    for i in range(need):
        img._f.seek(img.frag_offset(frags[i]))
        img._f.write(bytes(payload[i * img.fsize:(i + 1) * img.fsize]))
    img._f.flush()

    _write_inode_fields(img, ino, size=len(data),
                        mtime=mtime if mtime is not None else inode.mtime)

    # Read-back verification through the same parser.  This cannot catch a bug
    # shared by reader and writer; the independent check is the guest booting.
    check = rhap_image.Image(img.path)
    try:
        got = check.read_file(check.resolve(path))
    finally:
        check.close()
    if got != data:
        raise SafetyError("%s: read-back mismatch after write" % path)

    return len(data)
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd vm && python -m unittest test_rhap_inject -v
```

Expected: 6 tests, all PASS. The round-trip tests take a few seconds because verification reopens the 8 GB image.

- [ ] **Step 5: Confirm the golden image was not touched**

```bash
cd vm && python rhap_image.py golden.img cat /private/Drivers/i386/EIDE.config/Instance0.table | grep "Multiple Sectors"
```

Expected: `"Multiple Sectors" = "Yes";` — unchanged.

- [ ] **Step 6: Commit**

```bash
git add vm/rhap_inject.py vm/test_rhap_inject.py
git commit -m "vm: add in-place UFS writer with allocation and target safety checks"
```

---

### Task 7: Disable multisector and test the boot — GATE

**Files:**
- Modify: `vm/rhap_inject.py` (add the CLI)

**Interfaces:**
- Consumes: `write_file` from Task 6
- Produces: `python rhap_inject.py <image> set-key <path> <key> <value>` and a boot result that gates Tasks 8-10

- [ ] **Step 1: Add a config-table key setter**

Append to `vm/rhap_inject.py`:

```python
def set_table_key(img, path, key, value):
    """Rewrite one "key" = "value"; line in a DriverKit config table."""
    ino = img.resolve(path)
    if ino is None:
        raise SafetyError("%s does not exist" % path)
    text = img.read_file(ino)
    needle = b'"%s" = "' % key.encode()
    start = text.find(needle)
    if start < 0:
        raise SafetyError("%s: key %r not present" % (path, key))
    vstart = start + len(needle)
    vend = text.find(b'"', vstart)
    if vend < 0:
        raise SafetyError("%s: malformed entry for %r" % (path, key))
    updated = text[:vstart] + value.encode() + text[vend:]
    write_file(img, path, updated)
    return text[vstart:vend].decode(), value


def main(argv):
    if len(argv) < 3:
        print("usage: rhap_inject.py <image> set-key <path> <key> <value>")
        print("       rhap_inject.py <image> put <path> <local-file>")
        return 2
    image, cmd = argv[1], argv[2]
    img = rhap_image.Image(image, writable=True)
    try:
        if cmd == "set-key":
            path, key, value = argv[3], argv[4], argv[5]
            old, new = set_table_key(img, path, key, value)
            print("%s: %r %r -> %r" % (path, key, old, new))
        elif cmd == "put":
            path, local = argv[3], argv[4]
            with open(local, "rb") as fh:
                data = fh.read()
            n = write_file(img, path, data)
            print("%s: wrote %d bytes" % (path, n))
        else:
            print("unknown command: %s" % cmd)
            return 2
    finally:
        img.close()
    return 0


if __name__ == "__main__":
    import sys
    raise SystemExit(main(sys.argv))
```

- [ ] **Step 2: Reset the working image to a known state**

```bash
cd vm && cmd //c reset-image.cmd
```

Expected: `Done.`

- [ ] **Step 3: Flip the key**

```bash
cd vm && python rhap_inject.py work/test.img set-key /private/Drivers/i386/EIDE.config/Instance0.table "Multiple Sectors" No
```

Expected: `/private/Drivers/i386/EIDE.config/Instance0.table: 'Multiple Sectors' 'Yes' -> 'No'`

- [ ] **Step 4: Confirm the change landed**

```bash
cd vm && python rhap_image.py work/test.img cat /private/Drivers/i386/EIDE.config/Instance0.table | grep "Multiple Sectors"
```

Expected: `"Multiple Sectors" = "No";`

- [ ] **Step 5: Boot**

```bash
cd vm && cmd //c start-vm.cmd
```

Expected on the VGA console: `hd0: using multisector (16) transfers.` is **gone**, and there is no `hc0: interrupt timeout, cmd: 0xc4`.

Three possible outcomes, each of which changes what happens next:

1. **The guest boots to a login prompt.** The workaround holds. Record it, then continue to Task 8 — but note that Tasks 10-11 become much easier, because you can now seed a placeholder kernel from inside the guest and skip the sacrificial-inode path entirely.
2. **A different failure appears.** The write landed and the multisector hypothesis was at least partly right. Capture the new console output and reassess before Task 8.
3. **The same `0xC4` timeout appears.** The driver is not honouring the table key. Confirm with `python rhap_image.py work/test.img cat ...` that the file really changed, then check whether the driver reads `Instance0.table` or falls back to a compiled-in default.

- [ ] **Step 6: Record the outcome**

Add a short subsection to `docs/drivers/drvEIDE-issues.md` §2 recording which outcome occurred and the console output.

- [ ] **Step 7: Commit**

```bash
git add vm/rhap_inject.py docs/drivers/drvEIDE-issues.md
git commit -m "vm: add config-table key setter and record the multisector boot result"
```

---

### Task 8: Sacrificial-inode injection for oversized payloads

**Files:**
- Modify: `vm/rhap_inject.py`
- Modify: `vm/test_rhap_inject.py`

**Interfaces:**
- Consumes: `write_file`, `_write_inode_fields` from Task 6
- Produces: `graft_file(img, target_path, donor_path, data)` — overwrite the donor's blocks with `data`, then repoint the target's directory entry at the donor inode

**Why:** `/mach_kernel` has 704 bytes of slack and `EIDE_reloc` has 800. A rebuilt binary will exceed both. This grafts the payload onto a large, boot-irrelevant file's blocks and repoints the name, using three small writes and no allocation.

- [ ] **Step 1: Write the failing test**

Append to `vm/test_rhap_inject.py`:

```python
DONOR = ("/System/Documentation/Developer/YellowBox/TasksAndConcepts"
         "/PB/ProjectBuilder.pdf")


@unittest.skipUnless(os.path.exists(WORK), "work/test.img not built yet")
class TestGraft(unittest.TestCase):
    def test_donor_is_large_and_hole_free(self):
        img = rhap_image.Image(WORK)
        try:
            ino = img.resolve(DONOR)
            self.assertIsNotNone(ino)
            n = img.inode(ino)
            self.assertGreater(img.max_writable(n), 8 * 1024 * 1024)
            self.assertTrue(all(f for f in img.frags(n)))
        finally:
            img.close()

    def test_graft_repoints_name_and_content(self):
        payload = b"GRAFTED" + b"\0" * (2 * 1024 * 1024 - 7)
        img = rhap_image.Image(WORK, writable=True)
        try:
            donor_ino = img.resolve(DONOR)
            rhap_inject.graft_file(img, "/mach_kernel", DONOR, payload)
        finally:
            img.close()

        img = rhap_image.Image(WORK)
        try:
            self.assertEqual(img.resolve("/mach_kernel"), donor_ino)
            got = img.read_file(img.resolve("/mach_kernel"))
            self.assertEqual(len(got), len(payload))
            self.assertEqual(got[:7], b"GRAFTED")
            self.assertGreaterEqual(img.inode(donor_ino).nlink, 2)
        finally:
            img.close()

    def test_graft_refuses_donor_too_small(self):
        img = rhap_image.Image(WORK, writable=True)
        try:
            with self.assertRaises(rhap_inject.SafetyError):
                rhap_inject.graft_file(
                    img, "/mach_kernel", TABLE, b"x" * 100000
                )
        finally:
            img.close()
```

Note: `test_graft_repoints_name_and_content` deliberately damages the image. Run `reset-image.cmd` afterwards.

- [ ] **Step 2: Run to verify it fails**

```bash
cd vm && python -m unittest test_rhap_inject.TestGraft -v
```

Expected: FAIL with `AttributeError: module 'rhap_inject' has no attribute 'graft_file'`

- [ ] **Step 3: Write the implementation**

Append to `vm/rhap_inject.py`:

```python
def _find_dirent(img, dir_ino, name):
    """Byte offset of a directory entry's d_ino field within the directory."""
    for n, ino, _t, off in img.iter_dir(dir_ino):
        if n == name:
            return off, ino
    return None, None


def graft_file(img, target_path, donor_path, data, mtime=None):
    """Point target_path at donor_path's inode, after filling it with data.

    Used when data is too large for target_path's own allocation.  Performs no
    allocation: the donor's existing blocks are overwritten, its di_size is set,
    its di_nlink is bumped so the extra name is a legitimate hard link, and the
    target's directory entry d_ino is repointed.
    """
    check_target(img.path)

    donor_ino = img.resolve(donor_path)
    if donor_ino is None:
        raise SafetyError("donor %s does not exist" % donor_path)
    donor = img.inode(donor_ino)
    if not donor.is_reg():
        raise SafetyError("donor %s is not a regular file" % donor_path)

    limit = img.max_writable(donor)
    if len(data) > limit:
        raise SafetyError(
            "donor %s holds %d bytes; payload is %d" % (donor_path, limit, len(data))
        )
    frags = img.frags(donor)
    if any(f == 0 for f in frags):
        raise SafetyError("donor %s has holes; refusing" % donor_path)

    parent = "/" + target_path.strip("/").rsplit("/", 1)[0] if "/" in target_path.strip("/") else "/"
    leaf = target_path.strip("/").rsplit("/", 1)[-1]
    parent_ino = img.resolve(parent)
    if parent_ino is None:
        raise SafetyError("parent of %s does not exist" % target_path)
    ent_off, old_ino = _find_dirent(img, parent_ino, leaf)
    if ent_off is None:
        raise SafetyError("%s does not exist; graft cannot create names" % target_path)
    if old_ino == donor_ino:
        raise SafetyError("%s already points at the donor inode" % target_path)

    # 1. Fill the donor's blocks.
    payload = bytearray(data)
    need = (len(payload) + img.fsize - 1) // img.fsize
    payload += bytes(need * img.fsize - len(payload))
    for i in range(need):
        img._f.seek(img.frag_offset(frags[i]))
        img._f.write(bytes(payload[i * img.fsize:(i + 1) * img.fsize]))
    img._f.flush()

    # 2. Set the donor's size and link count.
    _write_inode_fields(img, donor_ino, size=len(data),
                        mtime=mtime if mtime is not None else donor.mtime,
                        nlink=max(2, donor.nlink + 1))

    # 3. Repoint the target's directory entry (4 bytes).
    dir_frags = img.frags(img.inode(parent_ino))
    frag_index = ent_off // img.fsize
    within = ent_off % img.fsize
    img._f.seek(img.frag_offset(dir_frags[frag_index]) + within)
    img._f.write(struct.pack("<I", donor_ino))
    img._f.flush()

    check = rhap_image.Image(img.path)
    try:
        if check.resolve(target_path) != donor_ino:
            raise SafetyError("%s: repoint did not take" % target_path)
        if check.read_file(donor_ino) != data:
            raise SafetyError("%s: read-back mismatch after graft" % target_path)
    finally:
        check.close()

    return donor_ino
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd vm && python -m unittest test_rhap_inject.TestGraft -v
```

Expected: 3 tests, all PASS.

- [ ] **Step 5: Reset the damaged image**

```bash
cd vm && cmd //c reset-image.cmd
```

- [ ] **Step 6: Commit**

```bash
git add vm/rhap_inject.py vm/test_rhap_inject.py
git commit -m "vm: add sacrificial-inode graft for payloads exceeding in-place slack"
```

---

### Task 9: Inject the rebuilt drvEIDE binary

**Files:**
- No source changes; this task fetches, injects and verifies the driver.

**Interfaces:**
- Consumes: `write_file` from Task 6, `graft_file` from Task 8
- Produces: a working image running the rebuilt `drvEIDE` with multisector restored

**Why this comes before the kernel work:** it tests the injector against a real
build artifact on a target with 800 bytes of slack, which is the same situation
the kernel faces but with a far cheaper failure. If the driver alone fixes the
boot, the serial console becomes a convenience rather than a necessity.

- [ ] **Step 1: Build drvEIDE on the PPC machine and fetch it**

Build `src/drivers-i386/ide/drvEIDE` for i386 on the PPC build machine, then
fetch the driver binary from the built `EIDE.config` bundle:

```bash
cd vm && pscp <user>@<ppc-host>:<build-path>/EIDE.config/EIDE_reloc artifacts/EIDE_reloc
```

Expected: `artifacts/EIDE_reloc` exists.

- [ ] **Step 2: Confirm it is an i386 Mach-O and note its size**

```bash
cd vm && python -c "
d=open('artifacts/EIDE_reloc','rb').read()
print(len(d), d[:4].hex(), 'little-endian Mach-O' if d[:4]==b'\xce\xfa\xed\xfe' else 'UNEXPECTED')
"
```

Expected: a size, then `cefaedfe little-endian Mach-O`.

- [ ] **Step 3: Reset and compare against the available slack**

```bash
cd vm && cmd //c reset-image.cmd && python rhap_image.py work/test.img slack /private/Drivers/i386/EIDE.config/EIDE_reloc
```

Expected: `121056 121856 800` — size, writable limit, slack. Compare the middle
number against the size from Step 2.

- [ ] **Step 4: Inject**

If the new binary is at most 121856 bytes:

```bash
cd vm && python rhap_inject.py work/test.img put /private/Drivers/i386/EIDE.config/EIDE_reloc artifacts/EIDE_reloc
```

Otherwise graft it onto the documentation PDF, which has 14 MB available:

```bash
cd vm && python -c "
import rhap_image, rhap_inject
DONOR='/System/Documentation/Developer/YellowBox/TasksAndConcepts/IB/InterfaceBuilderGuide.pdf'
TARGET='/private/Drivers/i386/EIDE.config/EIDE_reloc'
img = rhap_image.Image('work/test.img', writable=True)
try:
    data = open('artifacts/EIDE_reloc','rb').read()
    ino = rhap_inject.graft_file(img, TARGET, DONOR, data)
    print('grafted onto inode', ino, '(%d bytes)' % len(data))
finally:
    img.close()
"
```

A different donor is used here than in Task 11 so the driver and the kernel can
be grafted at the same time without colliding.

- [ ] **Step 5: Verify the injected binary reads back correctly**

```bash
cd vm && python rhap_image.py work/test.img cat /private/Drivers/i386/EIDE.config/EIDE_reloc > /tmp/eide.bin && cmp /tmp/eide.bin artifacts/EIDE_reloc && echo IDENTICAL
```

Expected: `IDENTICAL`

- [ ] **Step 6: Boot with multisector still disabled**

```bash
cd vm && python rhap_inject.py work/test.img set-key /private/Drivers/i386/EIDE.config/Instance0.table "Multiple Sectors" No
cmd //c start-vm.cmd
```

Expected: the guest boots at least as far as it did in Task 7. This separates
"the new driver works" from "the new driver fixes multisector".

- [ ] **Step 7: Boot with multisector restored — the real test**

```bash
cd vm && python rhap_inject.py work/test.img set-key /private/Drivers/i386/EIDE.config/Instance0.table "Multiple Sectors" Yes
cmd //c start-vm.cmd
```

Expected: `hd0: using multisector (16) transfers.` appears **and** the boot
continues past it with no `hc0: interrupt timeout, cmd: 0xc4`. That is the
rebuilt driver fixing the bug rather than the workaround avoiding it.

If it still wedges, the driver changes do not cover this failure mode. The
serial console in Tasks 10-11 becomes the priority, since the next step needs
`IOLog` visibility from inside the driver.

- [ ] **Step 8: Record the outcome**

Update `docs/drivers/drvEIDE-issues.md` §2 with whether the rebuilt driver
survives multisector under QEMU, and the installed driver version it replaced
(the stock image ships `drvEIDE-28` / version `5.01`, per `Instance0.table`).

- [ ] **Step 9: Commit**

```bash
git add docs/drivers/drvEIDE-issues.md
git commit -m "drvEIDE: record modern-QEMU boot results for the rebuilt driver"
```

---

### Task 10: i386 kernel serial console

**Files:**
- Create: `src/kernel-7/machdep/i386/serial_dbg.h`
- Create: `src/kernel-7/machdep/i386/serial_dbg.c`
- Modify: `src/kernel-7/machdep/i386/i386_init.c` (lines 61-72 and 122)
- Modify: `src/kernel-7/bsd/dev/i386/cons.c` (the `kprintf` stub near line 191)
- Modify: `src/kernel-7/bsd/kern/subr_prf.c` (`putchar`)
- Modify: `src/kernel-7/conf/files.i386`

**Interfaces:**
- Consumes: nothing from earlier tasks
- Produces: `void serial_dbg_init(void)`, `void serial_dbg_putc(char c)`, `extern int serial_dbg_port`

There is no host-side test for this task; it is verified in Task 11 by booting. Match the surrounding NeXT/Apple style: `#import` rather than `#include`, tabs for indentation.

- [ ] **Step 1: Create the header**

`src/kernel-7/machdep/i386/serial_dbg.h`:

```c
/*
 * serial_dbg.h -- polled 8250/16550 debug console for i386.
 *
 * Output only.  Safe with paging disabled, in interrupt context, and during
 * panic: no locks, no allocation, no interrupts, and a bounded spin so a
 * missing UART cannot wedge the kernel.
 */

#ifndef _MACHDEP_I386_SERIAL_DBG_
#define _MACHDEP_I386_SERIAL_DBG_

extern int	serial_dbg_port;	/* 0 disables; default 0x2f8 (COM2) */

void	serial_dbg_init(void);
void	serial_dbg_putc(char c);
void	serial_dbg_puts(const char *s);

#endif /* _MACHDEP_I386_SERIAL_DBG_ */
```

- [ ] **Step 2: Create the driver**

COM1 (0x3f8) is left alone because `drvISASerialPort` claims it; the boot log confirms `ISASerialPort0: Base=0x03f8, IRQ=4`.

`src/kernel-7/machdep/i386/serial_dbg.c`:

```c
/*
 * serial_dbg.c -- polled 8250/16550 debug console for i386.
 *
 * The kernel console on i386 is VGA only, and kprintf() was a no-op, so
 * early-boot, driver and panic output could not be captured.  This drives a
 * UART directly with programmed I/O.
 *
 * Default port is COM2 (0x2f8); COM1 belongs to drvISASerialPort.  Override
 * with the "serial=" boot argument, e.g. "serial=0x3f8" or "serial=0".
 */

#import <machdep/i386/serial_dbg.h>
#import <machdep/i386/io_inline.h>

int	serial_dbg_port = 0x2f8;

/* 8250 register offsets */
#define	UART_DATA	0	/* data (DLAB=0) */
#define	UART_IER	1	/* interrupt enable */
#define	UART_DLL	0	/* divisor low  (DLAB=1) */
#define	UART_DLM	1	/* divisor high (DLAB=1) */
#define	UART_FCR	2	/* FIFO control */
#define	UART_LCR	3	/* line control */
#define	UART_MCR	4	/* modem control */
#define	UART_LSR	5	/* line status */

#define	LCR_DLAB	0x80
#define	LCR_8N1		0x03
#define	FCR_ENABLE	0x07	/* enable + clear both FIFOs */
#define	MCR_DTR_RTS	0x03
#define	LSR_THRE	0x20	/* transmit holding register empty */

#define	DIVISOR_115200	1	/* 115200 baud from a 1.8432 MHz clock */

/*
 * Bounded so a missing or wedged UART costs a dropped character rather than a
 * hung kernel.  Sized to be comfortably longer than one character time at
 * 115200 baud even on a slow machine.
 */
#define	TX_SPIN_LIMIT	100000

void
serial_dbg_init(void)
{
	int port = serial_dbg_port;

	if (port == 0)
		return;

	outb(port + UART_IER, 0x00);			/* no interrupts */
	outb(port + UART_LCR, LCR_DLAB);
	outb(port + UART_DLL, DIVISOR_115200);
	outb(port + UART_DLM, 0x00);
	outb(port + UART_LCR, LCR_8N1);			/* 8N1, DLAB off */
	outb(port + UART_FCR, FCR_ENABLE);
	outb(port + UART_MCR, MCR_DTR_RTS);
}

void
serial_dbg_putc(char c)
{
	int port = serial_dbg_port;
	int spin;

	if (port == 0)
		return;

	if (c == '\n')
		serial_dbg_putc('\r');

	for (spin = TX_SPIN_LIMIT; spin > 0; spin--) {
		if (inb(port + UART_LSR) & LSR_THRE) {
			outb(port + UART_DATA, c);
			return;
		}
	}
	/* Dropped: better than deadlocking the kernel. */
}

void
serial_dbg_puts(const char *s)
{
	while (*s)
		serial_dbg_putc(*s++);
}
```

- [ ] **Step 3: Verify `outb`/`inb` are spelled as this tree spells them**

```bash
cd src/kernel-7 && grep -n "outb\|inb" machdep/i386/io_inline.h | head -20
```

Expected: declarations of `inb` and `outb`. If this tree names them differently (for example `outb(port, val)` versus `outb(val, port)` argument order), correct `serial_dbg.c` to match before continuing — argument order reversed here would write to the wrong port silently.

- [ ] **Step 4: Add the boot argument and the early init call**

In `src/kernel-7/machdep/i386/i386_init.c`, add the import near the other machdep imports:

```c
#import <machdep/i386/serial_dbg.h>
```

Add an entry to the `kernargs[]` table (currently at line 64):

```c
} kernargs[] = {
	"nbuf", &nbuf,
	"rootdev", (int*) rootdevice,
	"maxmem", &maxmem,
	"subtype", &subtype,
	"srv", &srv,
	"ncl", &ncl,
	"serial", &serial_dbg_port,
	0,0,
};
```

Then, in `i386_init()`, immediately after the existing `getargs()` call at line 122:

```c
    getargs(kernBootStruct->bootString);

    serial_dbg_init();
    serial_dbg_puts("\nserial_dbg: i386 kernel console up\n");
```

The banner is the first checkpoint in Task 10: it must appear before any VGA output.

- [ ] **Step 5: Implement `kprintf()`**

In `src/kernel-7/bsd/dev/i386/cons.c`, add the import at the top with the others:

```c
#import <machdep/i386/serial_dbg.h>
```

Replace the stub (near line 191):

```c
void
kprintf( const char *format, ...)
{
        /* on PPC this outputs to the serial line */
        /* nop on intel ... umeshv@apple.com */

}
```

with:

```c
/*
 * Formats to a stack buffer and writes straight to the debug UART.  It
 * deliberately avoids cnputc() and the tty layer so it stays usable in early
 * boot, in interrupt context and during panic.
 */
void
kprintf( const char *format, ...)
{
	char	buf[256];
	char	*bp = buf;
	va_list	ap;

	va_start(ap, format);
	prf(format, ap, TOSTR, (struct tty *)&bp);
	va_end(ap);
	*bp = '\0';

	serial_dbg_puts(buf);
}
```

`prf` with `TOSTR` writes through a `char **` passed in the `tty` slot; `putchar` implements this as `**sp = c; (*sp)++`. Confirm the declaration of `prf` visible in this file matches, and add `extern` if needed.

- [ ] **Step 6: Add the `putchar` tap**

In `src/kernel-7/bsd/kern/subr_prf.c`, add near the top with the other imports:

```c
#if defined(i386)
#import <machdep/i386/serial_dbg.h>
#endif
```

In `putchar()`, immediately before the closing `return 0;`:

```c
	if (flags & TOSTR) {
		**sp = c;
		(*sp)++;
	}
#if defined(i386)
	/*
	 * Mirror console and log traffic to the debug UART.  TOLOG matters:
	 * once syslogd opens /dev/klog, log() stops falling back to TOCONS,
	 * so a TOCONS-only tap would go silent for IOLog output.
	 */
	if ((flags & (TOCONS|TOLOG)) && c != '\0' && serial_dbg_port)
		serial_dbg_putc((char)c);
#endif
	return 0;
```

- [ ] **Step 7: Add the file to the build**

In `src/kernel-7/conf/files.i386`, next to the other `machdep/i386` entries:

```
machdep/i386/serial_dbg.c	standard
```

- [ ] **Step 8: Verify the tap is not inside the TOSTR branch**

```bash
cd src/kernel-7 && sed -n '/^putchar(/,/^}/p' bsd/kern/subr_prf.c
```

Expected: the `serial_dbg_putc` call sits at the function's top level, after the `TOSTR` block closes, not nested inside it. Nesting it would emit only for `TOSTR` callers, which is the opposite of the intent.

- [ ] **Step 9: Commit**

```bash
git add src/kernel-7/machdep/i386/serial_dbg.c src/kernel-7/machdep/i386/serial_dbg.h \
        src/kernel-7/machdep/i386/i386_init.c src/kernel-7/bsd/dev/i386/cons.c \
        src/kernel-7/bsd/kern/subr_prf.c src/kernel-7/conf/files.i386
git commit -m "kernel: add polled i386 serial debug console and route printf, panic and IOLog to it"
```

---

### Task 11: Build, inject and verify the serial console

**Files:**
- No source changes; this task builds, injects and verifies.

**Interfaces:**
- Consumes: Task 10's kernel changes, Task 6's `write_file`, Task 8's `graft_file`
- Produces: a booting guest emitting kernel output on COM2

- [ ] **Step 1: Build the kernel on the PPC machine**

Build `kernel-7` for i386 on the PPC build machine using its normal procedure. Fetch the result to the Windows host:

```bash
cd vm && pscp <user>@<ppc-host>:<path>/mach_kernel artifacts/mach_kernel
```

Expected: `artifacts/mach_kernel` exists and is a little-endian Mach-O.

- [ ] **Step 2: Confirm the binary is i386 Mach-O**

```bash
cd vm && python -c "
d=open('artifacts/mach_kernel','rb').read(4)
print(d.hex(), 'little-endian Mach-O' if d==b'\xce\xfa\xed\xfe' else 'UNEXPECTED')
"
```

Expected: `cefaedfe little-endian Mach-O`

- [ ] **Step 3: Reset and check whether it fits in place**

```bash
cd vm && cmd //c reset-image.cmd && python rhap_image.py work/test.img slack /mach_kernel && ls -l artifacts/mach_kernel
```

Compare the second number from `slack` (the writable limit, 1460224) against the file size.

- [ ] **Step 4: Inject**

If the kernel fits within the writable limit:

```bash
cd vm && python rhap_inject.py work/test.img put /mach_kernel artifacts/mach_kernel
```

If it does not fit (the expected case, given 704 bytes of slack), graft it onto the documentation PDF instead:

```bash
cd vm && python -c "
import rhap_image, rhap_inject
DONOR='/System/Documentation/Developer/YellowBox/TasksAndConcepts/PB/ProjectBuilder.pdf'
img = rhap_image.Image('work/test.img', writable=True)
try:
    data = open('artifacts/mach_kernel','rb').read()
    ino = rhap_inject.graft_file(img, '/mach_kernel', DONOR, data)
    print('grafted onto inode', ino, '(%d bytes)' % len(data))
finally:
    img.close()
"
```

Expected: `grafted onto inode <n> (<size> bytes)`

- [ ] **Step 5: Verify the injected kernel reads back correctly**

```bash
cd vm && python rhap_image.py work/test.img cat /mach_kernel > /tmp/check.bin && cmp /tmp/check.bin artifacts/mach_kernel && echo IDENTICAL
```

Expected: `IDENTICAL`

- [ ] **Step 6: Boot and check the banner — checkpoint 1**

```bash
cd vm && cmd //c start-vm.cmd
```

Expected in the terminal, before any VGA output appears:

```
serial_dbg: i386 kernel console up
```

If the banner never appears but the guest boots, the UART setup or `outb` argument order is wrong. If the guest now fails earlier than before, the kernel itself is bad — reset and boot the stock kernel to confirm the image is fine.

- [ ] **Step 7: Check printf and panic reach serial — checkpoint 2**

Boot again and, at the boot prompt, type:

```
mach_kernel -s
```

Expected: the same boot messages appear on both the VGA window and the terminal.

Then force a panic:

```
mach_kernel rootdev=9999
```

Expected: a `panic:` line appears in the terminal.

- [ ] **Step 8: Check IOLog reaches serial after syslogd — checkpoint 3**

This is the check that distinguishes the `putchar` tap from a `TOCONS`-only tap. Enable driver debug output:

```bash
cd vm && python rhap_inject.py work/test.img set-key /private/Drivers/i386/EIDE.config/Instance0.table "Debug" Yes
```

Boot multi-user and log in. Expected: `drvEIDE` chatter continues to appear in the terminal **after** login, once syslogd has opened `/dev/klog`. If it appears on VGA but not on serial, the `TOLOG` half of the tap is wrong — recheck Step 6 of Task 10.

- [ ] **Step 9: Check rollback — checkpoint 4**

```bash
cd vm && cmd //c reset-image.cmd && cmd //c start-vm.cmd
```

Expected: the guest behaves exactly as it did at the end of Task 1, proving the golden image is intact and every change is confined to the working image.

- [ ] **Step 10: Document the working loop**

Add a section to `vm/README.md` covering: creating `golden.img`, `reset-image.cmd`, the inspector and injector commands, the boot-prompt syntax for selecting a kernel and setting `serial=`, and where serial output appears.

- [ ] **Step 11: Commit**

```bash
git add vm/README.md
git commit -m "vm: document the offline injection and serial debug loop"
```

---

## Notes for the implementer

**The `-nodefaults` change in Task 1 must be verified, not assumed.** If removing the default CD-ROM also removes something the guest needs, `hc1` will report differently rather than simply going quiet. Compare against the pre-change boot log.

**Task 7 is a gate, not a formality.** All three outcomes are informative and two of them change the remaining work. Do not proceed to Task 8 without recording which one occurred.

**Writer tests mutate `work/test.img`.** Run `reset-image.cmd` before any boot that is meant to be clean. `TestGraft` deliberately destroys a documentation file.

**If Task 7 makes the guest boot,** Tasks 10-11 get easier: seed a placeholder with `dd if=/dev/zero of=/mach_kernel.serial bs=1024k count=8` from inside the guest, promote that image to `golden.img`, and use `write_file` against `/mach_kernel.serial` instead of grafting. Select it at the boot prompt with `mach_kernel.serial serial=0x2f8 -v`. That leaves the stock `/mach_kernel` untouched as a one-keystroke fallback.

**An 8 GB `probe.img` may still exist in the session scratchpad** from the design investigation. It is a raw conversion of `rhapsody.vmdk` and is useful for experimenting with the reader without touching `vm/`.
