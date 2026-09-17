# i386 Large Memory Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let i386 machines with more than 1GB of RAM boot correctly, and actually use up to ~1.75GB of it.

**Architecture:** Two phases. Phase 1 keeps the existing 1GB kernel linear window but fixes the E820 sizing bugs, plumbs the physical memory map through `kernBootStruct`, and clamps usable memory to what the kernel address space can hold — so a 4GB machine boots and uses ~816MB instead of corrupting memory. Phase 2 moves the segmented user/kernel split from 3G/1G to 2G/2G, which raises the same clamp to ~1776MB with no structural change to the page directory. Tasks are ordered so the kernel-only changes land and are verified first, using the stock booter, before the booter itself is touched.

**Tech Stack:** C (gcc 2.x era, no C99), i386 assembly, Rhapsody `pb_makefiles` + `gnumake` builds on a Rhapsody QEMU builder guest. Host-side tooling is Python 3.13 stdlib (`unittest`), run from inside `vm/`.

**Spec:** `docs/superpowers/specs/2026-07-25-i386-large-memory-design.md`

## Global Constraints

- **No host C compiler.** `gcc`, `cc` and `clang` are all absent from this Windows host. All C changes are compiled on the Rhapsody builder guest. Pure-arithmetic logic is modelled and tested in Python on the host first (Task 1).
- **This is a 1999 toolchain.** No `_Static_assert`, no C99 declarations-after-statements, no `//` comments in kernel `.c` files that must match surrounding style, no `long long` in kernel code. Declare all locals at the top of a block.
- **`/usr/standalone/i386/boot` has only 320 bytes of slack** in the disk image (39616 used, 39936 max writable, measured with `rhap_image.py slack`). `rhap_inject.py put` refuses a payload needing more fragments. If the rebuilt booter exceeds 39936 bytes, use `rhap_inject.graft_file` onto a donor instead. The booter Makefile also enforces `MAXBOOTSIZE = 45056`.
- **`/mach_kernel` has 704 bytes of slack** (1459520 used, 1460224 max), so a rebuilt kernel needs `graft_file`, not `put`. Grafting also needs a donor with enough already-allocated blocks: everything under `/usr/standalone/i386` is far too small (`sarld` is the largest at 148KB), so the donor is `/System/Documentation/Developer/YellowBox/TasksAndConcepts/PB/ProjectBuilder.pdf` at 23MB — the same one `vm/test_rhap_inject.py` uses. Task 2 wraps this in `vm/graft.py`.
- **Never run `fsck` on an image with a grafted file**, and a grafted inode will not survive a normal multi-user boot. See `vm/README.md` "Things that are not obvious".
- **Only `vm/work/test.img` may be booted or written.** `golden.img` and `rhapsody.vmdk` are read-only masters. `reset-image.cmd` recreates the working image.
- **`kernBootStruct.h` exists in two hand-kept i386 copies** that must stay byte-for-byte identical in layout:
  - `src/boot-2/i386/libsa/kernBootStruct.h`
  - `src/kernel-7/machdep/i386/kernBootStruct.h`

  The kernel copy contains a second, dead `#if 0` version of the struct near the top. Do not edit that one; the live struct is the one after `#else`.
- **`KERNBOOTSTRUCT` lives at the fixed address `0x11000`** and is read by drivers. Total struct size must not change.
- **The ppc side is out of scope.** `src/boot-2/ppc/ppcMac/libsa/kernBootStruct.h` and `src/kernel-7/machdep/ppc/` have their own copies and are not touched.
- Commit messages: short, human-readable, subsystem-prefixed (`boot: `, `kernel: `, `vm: `), one to two lines, describing behaviour not files. No metadata, no co-author trailers.
- Surgical changes only. Every changed line traces to this plan. Do not reformat or "improve" adjacent code.

## File Structure

**Created:**

| Path | Responsibility |
| --- | --- |
| `vm/memtool.py` | Host-side reference model of the booter's contiguous-RAM scan and the kernel's kmem VA estimate + clamp. Also predicts the expected clamp for a QEMU run. |
| `vm/test_memtool.py` | `unittest` suite for `memtool.py` |
| `vm/graft.py` | Graft a rebuilt binary into `work/test.img` using a donor large enough to hold it |
| `vm/rebuild-i386-boot.sh` | Guest build + staging for the i386 booter, mirroring `vm/rebuild-i386-kernel.sh` |
| `vm/scan-dylib-addrs.py` | Phase 2 pre-flight: report the highest `__TEXT` address of every dylib/framework in the image |

**Modified:**

| Path | Change |
| --- | --- |
| `vm/qemu-shot.py:191-194,221,307-321` | `--mem` option so the boot matrix can vary guest RAM (currently hardcoded `-m 128`) |
| `vm/test_qemu_shot.py` | Test for the new `--mem` plumbing |
| `src/kernel-7/machdep/i386/pmap.c:263` | Panic in `pmap_map()` when the kernel window would be overrun |
| `src/kernel-7/machdep/i386/i386_init.c:92-94,433-468` | Saturating KB conversion, kmem estimator, clamp loop, reporting globals, memory-map consumption |
| `src/kernel-7/machdep/i386/unix_startup.c:232` | Report the detected-vs-clamped size |
| `src/kernel-7/machdep/i386/kernBootStruct.h:160-211` | `boot_mem_range_t`, `memMapCount`, `memMap`, size assertions |
| `src/boot-2/i386/libsa/kernBootStruct.h:113-165` | Identical mirror of the above |
| `src/boot-2/i386/libsaio/biosfn.c:97-160` | `getMemoryMap()` returns the contiguous top, sets `bb.es`, emits 32-bit ranges |
| `src/boot-2/i386/libsaio/saio_internal.h:43-51` | `getMemoryMap()` signature |
| `src/boot-2/i386/boot2/sizememory.c:51-65` | Populate `kernBootStruct->memMap`, use the new return value |
| `src/kernel-7/mach/i386/vm_param.h:66,69` | Phase 2: `VM_MAX_ADDRESS`, `VM_MAX_KERNEL_ADDRESS` |
| `src/kernel-7/bsd/i386/vmparam.h:46` | Phase 2: `USRSTACK` |

---

## Task 1: Host-side arithmetic model and tests

The booter's contiguous-RAM scan and the kernel's reserve estimate are pure integer functions. Getting them wrong produces a machine that hangs in `pmap_bootstrap` with no output — the worst possible debugging loop. Model them in Python first, test them here, then transcribe to C in later tasks.

`memtool.py` also earns its keep afterwards: `predict` tells you what a given `-m` size *should* report, so the QEMU matrix in later tasks is checked against a number rather than eyeballed.

**Files:**
- Create: `vm/memtool.py`
- Test: `vm/test_memtool.py`

**Interfaces:**
- Consumes: nothing
- Produces (used by Tasks 3, 5, 6, 8 as the reference for the C transcription, and by their verification steps):
  - `contiguous_top(ranges) -> int` where `ranges` is a list of `(base, end, type)` int triples
  - `kb_to_bytes(kb) -> int`
  - `zone_map_estimate(mem_size) -> int`
  - `buffer_map_estimate(mem_size) -> int`
  - `kmem_va_estimate(mem_size) -> int`
  - `clamp_to_budget(raw_bytes, budget) -> int`
  - Constants `MB`, `PAGE_SIZE`, `EXT_BASE`, `ADDR_MAX`, `CLAMP_STEP`, `BUDGET_1G`, `BUDGET_2G`, `E820_RAM`

- [ ] **Step 1: Write the failing tests**

Create `vm/test_memtool.py`:

```python
"""Tests for memtool, the host-side model of the i386 memory arithmetic."""

import unittest

import memtool
from memtool import MB


class ContiguousTopTests(unittest.TestCase):
    def test_stops_at_the_first_hole_above_1mb(self):
        ranges = [
            (0x0, 0x9FC00, memtool.E820_RAM),
            (0x100000, 0x40000000, memtool.E820_RAM),
            (0x50000000, 0x60000000, memtool.E820_RAM),
        ]
        self.assertEqual(memtool.contiguous_top(ranges), 0x40000000)

    def test_ignores_the_legacy_hole_below_1mb(self):
        # Anchoring at 0 instead of 1MB would stop at 0x9FC00.
        ranges = [
            (0x0, 0x9FC00, memtool.E820_RAM),
            (0x100000, 0x20000000, memtool.E820_RAM),
        ]
        self.assertEqual(memtool.contiguous_top(ranges), 0x20000000)

    def test_handles_unsorted_entries(self):
        ranges = [
            (0x40000000, 0x60000000, memtool.E820_RAM),
            (0x100000, 0x40000000, memtool.E820_RAM),
        ]
        self.assertEqual(memtool.contiguous_top(ranges), 0x60000000)

    def test_ignores_non_ram_types(self):
        ranges = [
            (0x100000, 0x20000000, memtool.E820_RAM),
            (0x20000000, 0x30000000, 2),  # reserved
        ]
        self.assertEqual(memtool.contiguous_top(ranges), 0x20000000)

    def test_returns_ext_base_when_no_ram_above_1mb(self):
        ranges = [(0x0, 0x9FC00, memtool.E820_RAM)]
        self.assertEqual(memtool.contiguous_top(ranges), memtool.EXT_BASE)

    def test_overlapping_entries_do_not_loop_forever(self):
        ranges = [
            (0x100000, 0x20000000, memtool.E820_RAM),
            (0x100000, 0x30000000, memtool.E820_RAM),
            (0x10000000, 0x30000000, memtool.E820_RAM),
        ]
        self.assertEqual(memtool.contiguous_top(ranges), 0x30000000)


class KbToBytesTests(unittest.TestCase):
    def test_saturates_instead_of_overflowing(self):
        # 4GB expressed in KB; kb * 1024 would wrap to 0 in 32 bits.
        self.assertEqual(memtool.kb_to_bytes(4194304), memtool.ADDR_MAX)

    def test_ordinary_value_is_exact(self):
        self.assertEqual(memtool.kb_to_bytes(786432), 768 * MB)

    def test_never_exceeds_the_address_ceiling(self):
        for kb in (0, 1, 65536, 4194304, 0xFFFFFFFF):
            self.assertLessEqual(memtool.kb_to_bytes(kb), memtool.ADDR_MAX)


class ClampTests(unittest.TestCase):
    def test_768mb_is_untouched_under_a_1gb_budget(self):
        self.assertEqual(
            memtool.clamp_to_budget(768 * MB, memtool.BUDGET_1G), 768 * MB)

    def test_4gb_clamps_to_816mb_under_a_1gb_budget(self):
        self.assertEqual(
            memtool.clamp_to_budget(memtool.ADDR_MAX, memtool.BUDGET_1G),
            816 * MB)

    def test_1gb_and_above_all_clamp_to_the_same_value(self):
        budget = memtool.BUDGET_1G
        results = {
            memtool.clamp_to_budget(raw, budget)
            for raw in (1024 * MB, 1536 * MB, 2048 * MB, memtool.ADDR_MAX)
        }
        self.assertEqual(results, {816 * MB})

    def test_1536mb_is_untouched_under_a_2gb_budget(self):
        self.assertEqual(
            memtool.clamp_to_budget(1536 * MB, memtool.BUDGET_2G), 1536 * MB)

    def test_4gb_clamps_to_1776mb_under_a_2gb_budget(self):
        self.assertEqual(
            memtool.clamp_to_budget(memtool.ADDR_MAX, memtool.BUDGET_2G),
            1776 * MB)

    def test_result_always_fits_the_budget(self):
        for budget in (memtool.BUDGET_1G, memtool.BUDGET_2G):
            for raw_mb in (16, 256, 768, 1024, 1536, 2048, 3072):
                mem = memtool.clamp_to_budget(raw_mb * MB, budget)
                self.assertLessEqual(
                    mem + memtool.kmem_va_estimate(mem), budget,
                    "raw=%dMB budget=%dMB" % (raw_mb, budget // MB))

    def test_clamp_is_monotonic_in_the_budget(self):
        for raw_mb in (256, 1024, 4096):
            raw = min(raw_mb * MB, memtool.ADDR_MAX)
            self.assertLessEqual(
                memtool.clamp_to_budget(raw, memtool.BUDGET_1G),
                memtool.clamp_to_budget(raw, memtool.BUDGET_2G))


class EstimateTests(unittest.TestCase):
    def test_zone_map_is_capped_at_128mb(self):
        self.assertEqual(memtool.zone_map_estimate(4096 * MB), 128 * MB)

    def test_zone_map_has_a_12mb_floor(self):
        self.assertEqual(memtool.zone_map_estimate(16 * MB), 12 * MB)

    def test_niobuf_floor_applies_to_tiny_memory(self):
        # bufpages // 8 is 5 at 16MB, so niobuf floors at 32.
        self.assertEqual(memtool.buffer_map_estimate(16 * MB),
                         104 * 8192 + 32 * 65536)

    def test_estimate_is_monotonic(self):
        prev = 0
        for mb in range(16, 4096, 64):
            cur = memtool.kmem_va_estimate(mb * MB)
            self.assertGreaterEqual(cur, prev)
            prev = cur


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd vm && python -m unittest test_memtool -v
```

Expected: `ModuleNotFoundError: No module named 'memtool'`

- [ ] **Step 3: Write the model**

Create `vm/memtool.py`:

```python
"""Reference model for the i386 boot/kernel physical-memory arithmetic.

The booter's contiguous-RAM scan and the kernel's kmem address-space reserve
are pure integer functions.  Modelling them here lets the arithmetic be tested
on a host with no C compiler, and lets a QEMU run's expected report be
predicted before booting.

Keep in sync with:
    src/boot-2/i386/libsaio/biosfn.c          getMemoryMap()
    src/kernel-7/machdep/i386/i386_init.c     kmem_va_estimate(), size_memory()
    src/kernel-7/kern/zalloc.c                zone_map_sizer()
    src/kernel-7/machdep/i386/unix_startup.c  buffer_map_sizer()
"""

import sys

MB = 1024 * 1024

PAGE_SIZE = 8192            # kernel MI page: 2 * I386_PGBYTES
MAXBSIZE = 8192             # bsd/sys/param.h
MAXPHYS = 64 * 1024         # bsd/i386/param.h

KMEM_BASE = 64 * MB         # literal base size in pmap_bootstrap()
ZONE_MIN = 12 * MB          # zone_map_size_min
ZONE_MAX = 128 * MB         # zone_map_size_max

E820_RAM = 1
EXT_BASE = 0x100000         # extended memory starts at 1MB
ADDR_MAX = 0xFFFFF000       # saturation ceiling, page-aligned below 4GB
CLAMP_STEP = 16 * MB

BUDGET_1G = 0x40000000      # VM_MAX_KERNEL_ADDRESS today
BUDGET_2G = 0x80000000      # VM_MAX_KERNEL_ADDRESS after phase 2


def _clamp(value, low, high):
    if value < low:
        return low
    if value > high:
        return high
    return value


def contiguous_top(ranges):
    """Top of the contiguous RAM run starting at 1MB.

    "ranges" is a sequence of (base, end, type) triples with an exclusive end.
    Anchored at 1MB rather than 0 because E820 always reports the legacy hole
    at 0x9FC00-0x100000; a run anchored at 0 would stop there.

    Entries are not guaranteed sorted, so this repeats until stable rather
    than making a single pass.  Returns EXT_BASE when no RAM adjoins 1MB.
    """
    top = EXT_BASE
    changed = True
    while changed:
        changed = False
        for base, end, type_ in ranges:
            if type_ != E820_RAM:
                continue
            if base <= top < end:
                top = end
                changed = True
    return top


def kb_to_bytes(kb):
    """Saturating KB -> bytes.

    The kernel computes this in 32-bit unsigned arithmetic, where a 4GB
    machine's 4194304 KB would wrap to 0.
    """
    if kb > ADDR_MAX // 1024:
        return ADDR_MAX
    return kb * 1024


def zone_map_estimate(mem_size):
    """Mirrors zone_map_sizer() for the non-ppc case."""
    return _clamp(mem_size // 8, ZONE_MIN, ZONE_MAX)


def buffer_map_estimate(mem_size):
    """Mirrors buffer_map_sizer() with bufpages/nbuf/niobuf unset.

    The bufpages > nbuf * (MAXBSIZE / PAGE_SIZE) cap in the original cannot
    trigger here: MAXBSIZE == PAGE_SIZE, and nbuf is always bufpages + 64.
    """
    bufpages = (mem_size // 50) // PAGE_SIZE
    nbuf = max(bufpages, 16) + 64
    niobuf = _clamp(bufpages // (MAXPHYS // PAGE_SIZE), 32, 1024)
    return nbuf * MAXBSIZE + niobuf * MAXPHYS


def kmem_va_estimate(mem_size):
    """Kernel VA consumed above the V==P direct map, rounded up."""
    return KMEM_BASE + zone_map_estimate(mem_size) + buffer_map_estimate(mem_size)


def clamp_to_budget(raw_bytes, budget):
    """Largest memory size whose direct map plus reserve fits "budget".

    The subtraction is done on the budget side so the sum can never overflow
    32 bits in the C transcription.
    """
    mem = raw_bytes
    while True:
        if mem <= budget and kmem_va_estimate(mem) <= budget - mem:
            return mem
        if mem < CLAMP_STEP:
            return 0
        mem -= CLAMP_STEP


def predict(raw_mb, budget=BUDGET_1G):
    """What the kernel should report for a machine with raw_mb of RAM."""
    raw = min(raw_mb * MB, ADDR_MAX)
    mem = clamp_to_budget(raw, budget)
    return {
        "detected_mb": raw / float(MB),
        "reported_mb": mem / float(MB),
        "reserve_mb": kmem_va_estimate(mem) / float(MB),
        "clamped": mem != raw,
    }


def main(argv):
    budget = BUDGET_2G if "--2g" in argv else BUDGET_1G
    sizes = [int(a) for a in argv[1:] if not a.startswith("--")]
    if not sizes:
        sizes = [256, 768, 1024, 1536, 2048, 4096]
    print("budget = %d MB" % (budget // MB))
    for mb in sizes:
        p = predict(mb, budget)
        print("  -m %5dM  detected %7.1fMB  reported %7.1fMB  "
              "reserve %6.1fMB  %s"
              % (mb, p["detected_mb"], p["reported_mb"], p["reserve_mb"],
                 "clamped" if p["clamped"] else "full"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd vm && python -m unittest test_memtool -v
```

Expected: `OK`, 20 tests.

- [ ] **Step 5: Record the expected matrix**

```bash
cd vm && python memtool.py && python memtool.py --2g
```

Expected output — these are the numbers every later QEMU task checks against:

```
budget = 1024 MB
  -m   256M  detected   256.0MB  reported   256.0MB  reserve  106.7MB  full
  -m   768M  detected   768.0MB  reported   768.0MB  reserve  191.2MB  full
  -m  1024M  detected  1024.0MB  reported   816.0MB  reserve  199.1MB  clamped
  -m  1536M  detected  1536.0MB  reported   816.0MB  reserve  199.1MB  clamped
  -m  2048M  detected  2048.0MB  reported   816.0MB  reserve  199.1MB  clamped
  -m  4096M  detected  4096.0MB  reported   816.0MB  reserve  199.1MB  clamped
budget = 2048 MB
  -m   256M  detected   256.0MB  reported   256.0MB  reserve  106.7MB  full
  -m   768M  detected   768.0MB  reported   768.0MB  reserve  191.2MB  full
  -m  1024M  detected  1024.0MB  reported  1024.0MB  reserve  233.4MB  full
  -m  1536M  detected  1536.0MB  reported  1536.0MB  reserve  253.9MB  full
  -m  2048M  detected  2048.0MB  reported  1776.0MB  reserve  263.5MB  clamped
  -m  4096M  detected  4096.0MB  reported  1776.0MB  reserve  263.5MB  clamped
```

- [ ] **Step 6: Commit**

```bash
git add vm/memtool.py vm/test_memtool.py
git commit -m "vm: model the i386 memory sizing and clamp arithmetic on the host

Pure-integer reference for the booter's contiguous-RAM scan and the
kernel's kmem address-space reserve, with tests."
```

---

## Task 2: Boot-test tooling — variable RAM and a graft helper

Two gaps block every boot test that follows. `qemu-shot.py` hardcodes `-m 128`, and grafting a rebuilt binary needs an open writable `Image` plus a donor large enough to hold it — `rhap_inject.graft_file` takes an `Image` object, not a path, and the only donor in the image big enough for a 1.4MB kernel is a 23MB PDF under `/System/Documentation`.

**Files:**
- Modify: `vm/qemu-shot.py:191-194,221,238,307-321`
- Test: `vm/test_qemu_shot.py`
- Create: `vm/graft.py`

**Interfaces:**
- Consumes: `rhap_image.Image(path, writable=True)`, `rhap_inject.graft_file(img, target_path, donor_path, data)`
- Produces:
  - `build_qemu_args(image, qmp_port, trace, serial_log, mem="128")` and a `--mem` CLI flag. The existing 4-positional-argument call in `test_qemu_shot.py` keeps working because `mem` has a default.
  - `vm/graft.py TARGET LOCAL-FILE` — grafts `LOCAL-FILE` over `TARGET` in `work/test.img` using the standard donor. Used by Tasks 3, 4, 5, 7 and 9.

- [ ] **Step 1: Write the failing test**

Add to `vm/test_qemu_shot.py`, inside the same class as `test_snapshot_and_serial_log_are_present`:

```python
    def test_mem_defaults_to_128(self):
        args = qemu_shot.build_qemu_args("work/test.img", 1234, False, "out/serial.log")
        self.assertIn("-m", args)
        self.assertEqual(args[args.index("-m") + 1], "128")

    def test_mem_is_overridable(self):
        args = qemu_shot.build_qemu_args(
            "work/test.img", 1234, False, "out/serial.log", mem="4096")
        self.assertEqual(args[args.index("-m") + 1], "4096")
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd vm && python -m unittest test_qemu_shot -v
```

Expected: `test_mem_is_overridable` FAILS with `TypeError: build_qemu_args() takes 4 positional arguments but 5 were given`. `test_mem_defaults_to_128` passes already.

- [ ] **Step 3: Add the parameter**

In `vm/qemu-shot.py`, change the signature at line 191 and the `-m` entry at line 194:

```python
def build_qemu_args(image, qmp_port, trace, serial_log, mem="128"):
    args = [
        "qemu-system-i386", "-M", "pc", "-cpu", "pentium", "-accel", "tcg",
        "-m", str(mem), "-k", "en-us",
```

Change `run()` at line 221 to accept and forward it:

```python
def run(image, outdir, at_points, keys, keys_at, trace, mem="128"):
```

and at line 238:

```python
    qemu_args = build_qemu_args(image, qmp_port, trace, serial_log, mem)
```

Add the CLI flag next to the other `add_argument` calls around line 315:

```python
    p.add_argument("--mem", default="128",
                   help="guest RAM passed to qemu -m (default 128)")
```

and forward it at line 321:

```python
    run(args.image, args.outdir, at_points, args.keys, args.keys_at,
        args.trace, args.mem)
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd vm && python -m unittest test_qemu_shot -v
```

Expected: `OK`. No previously-passing test regresses.

- [ ] **Step 5: Write the graft helper**

Create `vm/graft.py`:

```python
"""Graft a rebuilt binary into work/test.img.

rhap_inject.graft_file takes an open writable Image, not a path, and needs a
donor with enough already-allocated blocks to hold the payload.  The kernel is
~1.4MB, far larger than anything under /usr/standalone, so the donor is the
same 23MB documentation PDF vm/test_rhap_inject.py uses.

Grafting leaves the donor's blocks allocated but unreferenced.  Never run fsck
on an image after using this - see vm/README.md.
"""

import sys

import rhap_image
import rhap_inject

IMAGE = "work/test.img"
DONOR = ("/System/Documentation/Developer/YellowBox/TasksAndConcepts"
         "/PB/ProjectBuilder.pdf")


def main(argv):
    if len(argv) != 3:
        print("usage: graft.py TARGET-PATH LOCAL-FILE", file=sys.stderr)
        print("  e.g. graft.py /mach_kernel artifacts/mach_kernel",
              file=sys.stderr)
        return 2

    target, local = argv[1], argv[2]

    with open(local, "rb") as fh:
        data = fh.read()

    with rhap_image.Image(IMAGE, writable=True) as img:
        rhap_inject.graft_file(img, target, DONOR, data)

    print("grafted %s (%d bytes) onto %s via %s" % (target, len(data), IMAGE, DONOR))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

`graft_file` calls `check_target(img.path)` itself, so a non-`work/test.img` target is still refused.

- [ ] **Step 6: Verify the helper round-trips**

```bash
cd vm && cmd //c reset-image.cmd && MSYS_NO_PATHCONV=1 python rhap_image.py work/test.img cat /mach_kernel > /tmp/orig_kernel && python graft.py /mach_kernel /tmp/orig_kernel && MSYS_NO_PATHCONV=1 python rhap_image.py work/test.img cat /mach_kernel | cmp - /tmp/orig_kernel && echo ROUNDTRIP-OK
```

Expected: `grafted /mach_kernel (...) onto work/test.img ...` followed by `ROUNDTRIP-OK`. Grafting the kernel's own bytes back over itself must read back byte-identical.

- [ ] **Step 7: Commit**

```bash
git add vm/qemu-shot.py vm/test_qemu_shot.py vm/graft.py
git commit -m "vm: set guest RAM with --mem and add a graft helper

graft.py wraps the open-writable-Image plus large-donor dance that every
rebuilt-kernel injection needs."
```

---

## Task 3: Panic instead of corrupting memory past the kernel window

Today, mapping past `VM_MAX_KERNEL_ADDRESS` walks `pmap_pd_entry()` off the end of the single kernel page-directory page and scribbles on the following allocation. This is the backstop for everything else in the plan, and it is worth having on its own.

**Files:**
- Modify: `src/kernel-7/machdep/i386/pmap.c:263`

**Interfaces:**
- Consumes: nothing
- Produces: no new symbols. Establishes that `pmap_map()` will panic rather than corrupt, which Tasks 5 and 8 rely on as their safety net.

- [ ] **Step 1: Establish the baseline**

Reset the image and capture a known-good boot at the current default size, so the next step's comparison is against something real.

```bash
cd vm && cmd //c reset-image.cmd && python qemu-shot.py work/test.img shots-t3-base --at 45,90 --mem 128 --keys "mach_kernel -v\n"
```

Expected in `shots-t3-base/serial.log`: a `physical memory = 127.9...` line (or similar) and the boot proceeding past it. Record the exact line.

- [ ] **Step 2: Add the guard**

In `src/kernel-7/machdep/i386/pmap.c`, in `pmap_map()`, insert the check as the first statement inside the `while (start < end)` loop at line 263:

```c
    while (start < end) {
	if (virt >= VM_MAX_KERNEL_ADDRESS)
	    panic("pmap_map: kernel address space exhausted at virt 0x%x "
		  "(phys 0x%x, end 0x%x)", virt, start, end);

	pte = pmap_pt_entry(kernel_pmap, virt);
	if (pte == PT_ENTRY_NULL) {
	    pmap_kernel_pt_alloc(virt);
	    pte = pmap_pt_entry(kernel_pmap, virt);
	}
```

The check is at the top of the loop, before `virt` is used, so the final post-increment leaving `virt == VM_MAX_KERNEL_ADDRESS` is still a legal return value for `*virt_end`.

- [ ] **Step 3: Build the kernel on the guest**

Sync the tree to the builder guest the same way `vm/rebuild-i386-kernel.sh` expects (`/build/source/src/kernel-7`), then on the guest:

```bash
sh /build/source/vm/rebuild-i386-kernel.sh
```

Expected: `=== kernel rebuild done ===` and a `mach_kernel` staged at `/build/out/i386/mach_kernel`. Copy it back to `vm/artifacts/mach_kernel`.

- [ ] **Step 4: Inject and boot**

```bash
cd vm && cmd //c reset-image.cmd && python graft.py /mach_kernel artifacts/mach_kernel && python qemu-shot.py work/test.img shots-t3-guard --at 45,90 --mem 128 --keys "mach_kernel -v\n"
```

Expected in `shots-t3-guard/serial.log`: the same `physical memory =` line as Step 1, and **no** `pmap_map: kernel address space exhausted` panic. At 128MB the guard must never fire — if it does, the guard's comparison is wrong, not the kernel.

- [ ] **Step 5: Commit**

```bash
git add src/kernel-7/machdep/i386/pmap.c
git commit -m "kernel: panic when pmap_map runs past the kernel address space

Overrunning VM_MAX_KERNEL_ADDRESS walked off the end of the kernel page
directory and silently corrupted the next allocation."
```

---

## Task 4: Fix the overflow and clamp memory to the address-space budget

This is the change that makes a >1GB machine boot. It is verifiable with the **stock, unmodified booter**: the existing `extmem` path already reports ~2GB at `-m 2048`, and the current `KB(extmem)` overflow already produces 0MB at `-m 4096`.

**Files:**
- Modify: `src/kernel-7/machdep/i386/i386_init.c:92-94,433-468`
- Modify: `src/kernel-7/machdep/i386/unix_startup.c:232`

**Interfaces:**
- Consumes: the arithmetic defined in `vm/memtool.py` (Task 1) — `kb_to_bytes`, `kmem_va_estimate`, `clamp_to_budget`. The C must produce identical results.
- Produces:
  - `vm_size_t mem_size_detected;` — raw detected size in bytes, before clamping
  - `boolean_t mem_size_clamped;` — TRUE when `mem_size != mem_size_detected`

  Both are globals in `i386_init.c`, declared `extern` in `unix_startup.c`. Task 6 reads neither; Task 8 changes only the budget they are computed against.

- [ ] **Step 1: Capture the broken baseline**

```bash
cd vm && cmd //c reset-image.cmd && python qemu-shot.py work/test.img shots-t4-base-2g --at 45,90 --mem 2048 --keys "mach_kernel -v\n" && python qemu-shot.py work/test.img shots-t4-base-4g --at 45,90 --mem 4096 --keys "mach_kernel -v\n"
```

Expected: neither run reaches a login. `shots-t4-base-4g/serial.log` shows `physical memory = 0.00 megabytes.` if it gets that far, or stops before it. `shots-t4-base-2g/serial.log` shows a large `physical memory =` value followed by a hang or crash rather than a boot. Record both.

This is the failing test. Do not proceed until both runs are captured and confirmed broken.

- [ ] **Step 2: Add the reporting globals**

In `src/kernel-7/machdep/i386/i386_init.c`, after the existing `extmem` declaration at line 94:

```c
/* parameters passed from bootstrap loader */
unsigned int cnvmem = 0;	/* must be in .data section */
unsigned int extmem = 0;	/* extended memory in KB */

/* memory sizing results, reported by unix_startup.c */
vm_size_t	mem_size_detected = 0;	/* before clamping */
boolean_t	mem_size_clamped = FALSE;
```

- [ ] **Step 3: Add the saturating conversion and the estimator**

In `src/kernel-7/machdep/i386/i386_init.c`, immediately before `size_memory()` at line 433:

```c
/*
 * Kernel virtual address consumed by the kmem reservations that
 * pmap_bootstrap() makes on top of the V==P direct map.  This must track:
 *
 *	kern/zalloc.c			zone_map_sizer()
 *	machdep/i386/unix_startup.c	buffer_map_sizer()
 *
 * plus the literal base size in machdep/i386/pmap.c's pmap_bootstrap().
 *
 * The real sizers cannot be called from here: they memoize their results
 * into bufpages/nbuf/niobuf, which startup_early() consumes later, so
 * calling them this early would corrupt the buffer cache configuration.
 * This estimate rounds up wherever it is inexact.  vm/memtool.py is the
 * host-testable model of the same arithmetic.
 */
#define EST_KMEM_BASE	(64 * 1024 * 1024)	/* pmap_bootstrap base size */
#define EST_ZONE_MIN	(12 * 1024 * 1024)	/* zone_map_size_min */
#define EST_ZONE_MAX	(128 * 1024 * 1024)	/* zone_map_size_max */
#define EST_MAXBSIZE	8192			/* bsd/sys/param.h MAXBSIZE */
#define EST_MAXPHYS	(64 * 1024)		/* bsd/i386/param.h MAXPHYS */
#define CLAMP_STEP	(16 * 1024 * 1024)
#define ADDR_MAX	0xFFFFF000		/* page-aligned below 4GB */

static
vm_size_t
kmem_va_estimate(
    vm_size_t	memsz
)
{
    vm_size_t	zone, bufpages, nbuf, niobuf;

    zone = memsz / 8;
    if (zone < EST_ZONE_MIN)
	zone = EST_ZONE_MIN;
    else if (zone > EST_ZONE_MAX)
	zone = EST_ZONE_MAX;

    bufpages = (memsz / 50) / page_size;
    nbuf = (bufpages < 16 ? 16 : bufpages) + 64;

    niobuf = bufpages / (EST_MAXPHYS / page_size);
    if (niobuf > 1024)
	niobuf = 1024;
    if (niobuf < 32)
	niobuf = 32;

    return (EST_KMEM_BASE + zone
	    + (nbuf * EST_MAXBSIZE) + (niobuf * EST_MAXPHYS));
}

/*
 * Convert a KB count to bytes, saturating rather than wrapping.  A 4GB
 * machine reports 4194304 KB, which times 1024 is 0 in 32 bits.
 */
static
vm_offset_t
kb_to_bytes(
    unsigned int	kb
)
{
    if (kb > (ADDR_MAX / 1024))
	return ((vm_offset_t) ADDR_MAX);

    return ((vm_offset_t) kb * 1024);
}
```

`page_size` is already set to `2 * I386_PGBYTES` at `i386_init.c:143`, before `size_memory()` is called at line 153, so it is valid here.

- [ ] **Step 4: Rewrite size_memory()**

Replace the body of `size_memory()` in `src/kernel-7/machdep/i386/i386_init.c` (lines 433-468) with:

```c
static
void
size_memory(void)
{
    KERNBOOTSTRUCT	*kernBootStruct = (KERNBOOTSTRUCT *)KERNSTRUCT_ADDR;
    vm_offset_t		end_of_image, end_of_memory;
    vm_size_t		budget;
    int			i;
#define KB(x)		((x)*1024)

    end_of_image = getlastaddr();

    for (i=0; i < kernBootStruct->numBootDrivers; i++)
        end_of_image += kernBootStruct->driverConfig[i].size;

    if (maxmem)
        end_of_memory = kb_to_bytes((unsigned int) maxmem);
    else
        end_of_memory = kb_to_bytes(extmem);

    mem_size_detected = end_of_memory;

    /*
     * Physical memory is mapped V == P starting at kernel VA 0, and
     * pmap_bootstrap() reserves further kernel VA directly above it.
     * Both have to fit inside the kernel's linear window, so give back
     * whatever does not.  The comparison subtracts on the budget side so
     * the sum can never wrap.
     */
    budget = VM_MAX_KERNEL_ADDRESS - VM_MIN_KERNEL_ADDRESS;

    for (;;) {
	if (end_of_memory <= budget
	    && kmem_va_estimate(end_of_memory) <= budget - end_of_memory)
	    break;

	if (end_of_memory < CLAMP_STEP) {
	    end_of_memory = 0;
	    break;
	}

	end_of_memory -= CLAMP_STEP;
    }

    mem_size_clamped = (end_of_memory != mem_size_detected);

    /*
     * This is the Mach notion of
     * how much physical memory the
     * machine contains.
     */

    mem_size = end_of_memory;

    first_addr0 = round_page(kernBootStruct->first_addr0);
    last_addr0 = trunc_page(KB(cnvmem));

    first_addr = round_page(end_of_image);
    last_addr = trunc_page(end_of_memory);
#undef	KB
}
```

Note the comment above `mem_size` loses its old "only used for informational purposes" claim, which was never true — `mem_size` feeds both `zone_map_sizer()` and `buffer_map_sizer()`, which is precisely why clamping it is the right lever.

- [ ] **Step 5: Report the clamp**

In `src/kernel-7/machdep/i386/unix_startup.c`, add the externs near the top of the file with the other declarations:

```c
extern vm_size_t	mem_size_detected;
extern boolean_t	mem_size_clamped;
```

and extend the report at line 232:

```c
#define MEG	(1024*1024)
    printf("physical memory = %d.%d%d megabytes.\n",
	mem_size/MEG,
	((mem_size%MEG)*10)/MEG,
	((mem_size%(MEG/10))*100)/MEG);

    if (mem_size_clamped)
	printf("physical memory clamped from %d megabytes: "
	       "the kernel address space holds %d megabytes.\n",
	       mem_size_detected/MEG,
	       (VM_MAX_KERNEL_ADDRESS - VM_MIN_KERNEL_ADDRESS)/MEG);
```

- [ ] **Step 6: Build the kernel on the guest**

```bash
sh /build/source/vm/rebuild-i386-kernel.sh
```

Expected: `=== kernel rebuild done ===`. Copy `/build/out/i386/mach_kernel` back to `vm/artifacts/mach_kernel`.

- [ ] **Step 7: Run the boot matrix**

For each size, reset, graft and boot:

```bash
cd vm && for M in 256 768 1024 1536 2048 4096; do cmd //c reset-image.cmd; python graft.py /mach_kernel artifacts/mach_kernel; python qemu-shot.py work/test.img shots-t4-$M --at 45,90 --mem $M --keys "mach_kernel -v\n"; done
```

Then check each `serial.log` against the Task 1 Step 5 table:

```bash
cd vm && grep -h "physical memory" shots-t4-*/serial.log
```

Expected, matching the 1024 MB budget column exactly:

- `shots-t4-256/serial.log` — `physical memory = 255.9...`, no clamp line
- `shots-t4-768/serial.log` — `physical memory = 767.9...`, no clamp line
- `shots-t4-1024`, `-1536`, `-2048`, `-4096` — all `physical memory = 816.0...` (or `815.9...`) followed by a `physical memory clamped from ...` line
- No `pmap_map: kernel address space exhausted` panic in any run
- Every run reaches a login prompt

The four clamped runs must report the **same** value. If they differ, the clamp is reading a size that varies with the detected value, which means the loop or the estimator diverges from `memtool.py`.

- [ ] **Step 8: Commit**

```bash
git add src/kernel-7/machdep/i386/i386_init.c src/kernel-7/machdep/i386/unix_startup.c
git commit -m "kernel: clamp physical memory to the kernel address space

Also stop KB(extmem) wrapping to zero on a 4GB machine.  Memory beyond
what the direct map plus the kmem reservations can hold is given back
instead of overrunning the kernel window."
```

---

## Task 5: Carry a physical memory map in kernBootStruct

Layout-only change. No behaviour changes yet, so the verification is that both trees still compile and the kernel still boots identically.

**Files:**
- Modify: `src/kernel-7/machdep/i386/kernBootStruct.h:160-211`
- Modify: `src/boot-2/i386/libsa/kernBootStruct.h:113-165`

**Interfaces:**
- Consumes: nothing
- Produces, in both copies identically:
  - `#define BOOT_MEMMAP_MAX 32`
  - `#define BOOT_MEM_RAM 1`
  - `typedef struct { unsigned int base; unsigned int end; unsigned int type; } boot_mem_range_t;`
  - `KERNBOOTSTRUCT.memMapCount` (`int`) and `KERNBOOTSTRUCT.memMap` (`boot_mem_range_t[BOOT_MEMMAP_MAX]`)

  Task 6 writes these fields from the booter; Task 7 reads them in the kernel.

- [ ] **Step 1: Confirm `_reserved` is unused**

```bash
cd D:/RhapsodiOS && grep -rn "_reserved" --include=*.c --include=*.m --include=*.h src/boot-2/i386 src/kernel-7/machdep/i386
```

Expected: only the two struct declarations and one `sizeof` print in `src/boot-2/i386/boot2/test.c`. If anything else reads or writes `_reserved`, stop — the carve-out is not safe.

- [ ] **Step 2: Add the type and fields to the kernel copy**

In `src/kernel-7/machdep/i386/kernBootStruct.h`, in the **live** struct (after the `#else` at line 99, not the dead `#if 0` block), add the type above `typedef struct { short version; ...`:

```c
/*
 * Physical memory ranges handed over by the booter, derived from the BIOS
 * INT 0x15 E820h map.  Clamped to 32 bits: the kernel cannot address memory
 * above 4GB, so the booter drops ranges lying wholly above it and clips any
 * range that crosses it.  "end" is exclusive.
 */
#define BOOT_MEMMAP_MAX	32
#define BOOT_MEM_RAM	1		/* E820 type 1: usable RAM */

typedef struct {
    unsigned int	base;
    unsigned int	end;		/* exclusive, <= 0xFFFFF000 */
    unsigned int	type;		/* raw E820 type */
} boot_mem_range_t;
```

and replace line 201's `char   _reserved[7500];` with:

```c
    int			memMapCount;	/* 0 == no map, fall back to extmem */
    boot_mem_range_t	memMap[BOOT_MEMMAP_MAX];
    char   _reserved[7500 - 4 - (BOOT_MEMMAP_MAX * 12)];
```

Then, immediately after the closing `} KERNBOOTSTRUCT;` and before the `#define KERNSTRUCT_ADDR` line, add:

```c
/*
 * The booter and the kernel keep separate copies of this file and must agree
 * byte for byte.  KERNBOOTSTRUCT is also read by drivers at a fixed address,
 * so its total size must not change.  These fail to compile if either drifts.
 */
typedef char __kbs_range_size[(sizeof (boot_mem_range_t) == 12) ? 1 : -1];
typedef char __kbs_reserved_size[
	(sizeof (((KERNBOOTSTRUCT *)0)->_reserved) == 7112) ? 1 : -1];
```

`7112` is `7500 - 4 - 384`. Together with the 12-byte range assertion this pins the carved block at the original 7500 bytes.

- [ ] **Step 3: Mirror into the booter copy**

Apply the identical edits to `src/boot-2/i386/libsa/kernBootStruct.h` — the same type definition, the same three replacement lines at its `char _reserved[7500];` (line 160), and the same two assertions after its `} KERNBOOTSTRUCT;`.

- [ ] **Step 4: Verify the two copies agree**

```bash
cd D:/RhapsodiOS && diff <(sed -n '/BOOT_MEMMAP_MAX/,/__kbs_reserved_size/p' src/boot-2/i386/libsa/kernBootStruct.h) <(sed -n '/BOOT_MEMMAP_MAX/,/__kbs_reserved_size/p' src/kernel-7/machdep/i386/kernBootStruct.h)
```

Expected: no output. Any difference here is the bug this task exists to prevent.

- [ ] **Step 5: Build both trees on the guest**

```bash
sh /build/source/vm/rebuild-i386-kernel.sh
```

Expected: `=== kernel rebuild done ===`. A negative-array-size error (`size of array __kbs_reserved_size is negative`) means the arithmetic in Step 2 is wrong — recompute rather than adjusting the assertion.

- [ ] **Step 6: Confirm the kernel still boots unchanged**

```bash
cd vm && cmd //c reset-image.cmd && python graft.py /mach_kernel artifacts/mach_kernel && python qemu-shot.py work/test.img shots-t5 --at 45,90 --mem 768 --keys "mach_kernel -v\n"
```

Expected: `shots-t5/serial.log` shows `physical memory = 767.9...` with no clamp line, identical to `shots-t4-768/serial.log`, and reaches a login. The struct grew new fields but the booter does not write them and the kernel does not read them yet, so nothing may change.

- [ ] **Step 7: Commit**

```bash
git add src/kernel-7/machdep/i386/kernBootStruct.h src/boot-2/i386/libsa/kernBootStruct.h
git commit -m "boot: reserve a physical memory map in kernBootStruct

Carved out of the unused _reserved block so the struct size and every
field after it are unchanged.  Compile-time assertions pin the layout."
```

---

## Task 6: Make the booter report the contiguous memory top

Three fixes in one place: `getMemoryMap()` currently returns the *sum* of RAM rather than a usable top, relies on a stale `bb.es` left behind by other BIOS callers, and throws the map away.

**Files:**
- Create: `vm/rebuild-i386-boot.sh`
- Modify: `src/boot-2/i386/libsaio/biosfn.c:97-160`
- Modify: `src/boot-2/i386/libsaio/saio_internal.h:43-51`
- Modify: `src/boot-2/i386/boot2/sizememory.c:24-79`

**Interfaces:**
- Consumes: `boot_mem_range_t`, `BOOT_MEMMAP_MAX`, `BOOT_MEM_RAM`, `KERNBOOTSTRUCT.memMap`, `KERNBOOTSTRUCT.memMapCount` (Task 5)
- Produces: `unsigned long getMemoryMap(boot_mem_range_t *map, int maxEntries, int *numEntries)` — **returns a byte address**, the top of the contiguous RAM run starting at 1MB, or 0 if the BIOS has no E820 map or reports no RAM adjoining 1MB. This is a contract change: it previously returned a KB total. `sizememory()` is its only caller.

- [ ] **Step 1: Write the booter build script**

Create `vm/rebuild-i386-boot.sh`, mirroring `vm/rebuild-i386-kernel.sh`:

```sh
#!/bin/sh
# Sync-friendly i386 booter rebuild. Stages /usr/standalone/i386/boot.
set -e
export PATH=/build/bin:/usr/local/bin:/build/tools/usr/local/bin:/build/tools/usr/bin:/bin:/usr/bin:/sbin:/usr/sbin

if [ -x /usr/bin/gnumake ] && [ ! -x /usr/local/bin/make ]; then
	mkdir -p /usr/local/bin
	ln -sf /usr/bin/gnumake /usr/local/bin/make
fi

B=/build/source/src/boot-2/i386
OUT=/build/out/i386
mkdir -p "$OUT"

if [ ! -f "$B/Makefile" ]; then
	echo "missing $B/Makefile" >&2
	exit 1
fi

echo "=== strip CR from booter Makefiles ==="
find /build/source/src/boot-2 -type f \( -name Makefile -o -name 'Makefile.*' \) -print |
while read f; do
	tr -d '\r' < "$f" > /tmp/rhap_cr && mv /tmp/rhap_cr "$f"
done

echo "=== build i386 booter ==="
cd "$B"
rm -rf ../obj ../sym ../dst 2>/dev/null || true
gnumake install 2>&1

BOOT=../dst/i386/usr/standalone/i386/boot
ls -l "$BOOT"
SIZE=`wc -c < "$BOOT"`
echo "booter size: $SIZE bytes"
if [ "$SIZE" -gt 45056 ]; then
	echo "ERROR: booter exceeds MAXBOOTSIZE 45056" >&2
	exit 1
fi
if [ "$SIZE" -gt 39936 ]; then
	echo "WARNING: booter exceeds the image slack for /usr/standalone/i386/boot"
	echo "         (39936 bytes) - rhap_inject.py put will refuse it, use graft_file"
fi
cp -p "$BOOT" "$OUT/boot"
ls -la "$OUT/boot"
echo "=== booter rebuild done ==="
```

- [ ] **Step 2: Verify the script builds the stock booter**

Sync and run on the guest before changing any code, so a build failure is attributable to the script rather than to the C changes:

```bash
sh /build/source/vm/rebuild-i386-boot.sh
```

Expected: `=== booter rebuild done ===` and a `booter size:` line near 39616. Record that number — it is the budget for the next steps.

- [ ] **Step 3: Change the getMemoryMap declaration**

`saio_internal.h` currently imports only `saio_types.h`, so `boot_mem_range_t` is not in scope there. Add the boot-struct import next to that existing import at line 25:

```c
#define SAIO_INTERNAL 1
#import "saio_types.h"
#import <kernBootStruct.h>
```

Then replace the `e820_entry_t` block and the `getMemoryMap` declaration at lines 43-51 with:

```c
/* Raw entry returned by the INT 0x15, E820h BIOS call */
typedef struct {
    unsigned long long base;
    unsigned long long length;
    unsigned long type;
    unsigned long acpi_extended;
} __attribute__((packed)) e820_entry_t;

/*
 * Fills "map" with up to maxEntries ranges clamped to 32 bits and returns
 * the top of the contiguous RAM run starting at 1MB, or 0 if the BIOS has
 * no E820 map.  See biosfn.c.
 */
extern unsigned long getMemoryMap(boot_mem_range_t *map, int maxEntries,
				  int *numEntries);
extern unsigned long getExtendedMemoryE801(void);
```

`e820_entry_t` stays — it is still the shape the BIOS writes. Only the handoff type changes.

- [ ] **Step 4: Rewrite getMemoryMap**

In `src/boot-2/i386/libsaio/biosfn.c`, replace the `getMemoryMap()` function (lines 102-160, keeping the `E820_*` defines above it) with:

```c
#define E820_ADDR_MAX	0xFFFFF000	/* page-aligned below 4GB */

/*
 * Read the BIOS INT 0x15, E820h memory map.
 *
 * Fills "map" with up to maxEntries ranges clamped to 32 bits, and returns
 * the top of the contiguous run of usable RAM starting at 1MB - the highest
 * address the kernel can map V == P without crossing a hole.  Returns 0 if
 * the BIOS has no E820 map or reports no RAM adjoining 1MB.
 *
 * Anchoring the run at 1MB rather than 0 is deliberate: E820 always reports
 * the legacy hole at 0x9FC00-0x100000, so a run anchored at 0 would stop at
 * 640K.  Conventional memory is memsize(0)'s business.
 */
unsigned long getMemoryMap(boot_mem_range_t *map, int maxEntries, int *numEntries)
{
    unsigned long	continuation = 0;
    unsigned long	top;
    int			count = 0;
    int			changed, i;
    e820_entry_t	entry;

    if (!map || !numEntries || maxEntries < 1) {
        return 0;
    }

    *numEntries = 0;

    do {
	bzero((char *)&entry, sizeof(entry));

        bb.intno = 0x15;
        bb.eax.rx = 0xE820;
        bb.edx.rx = 0x534D4150;  /* 'SMAP' signature */
        bb.ebx.rx = continuation;
        bb.ecx.rx = sizeof(entry);

	/*
	 * The BIOS writes the entry through ES:DI.  boot2's stack sits just
	 * below 64K (STACK_ADDR), so &entry is reachable with ES == 0 - but
	 * "bb" is a shared global that vbe.c and get_diskinfo() leave their
	 * own segment in, so ES must be set here rather than inherited.
	 */
	bb.es = 0;
        bb.edi.rr = ((unsigned)&entry & 0xffff);

        bios(&bb);

        if (bb.flags.cf || bb.eax.rx != 0x534D4150) {
            break;
        }

	if (count < maxEntries && entry.length > 0) {
	    unsigned long long ebase = entry.base;
	    unsigned long long eend  = entry.base + entry.length;

	    /* Drop ranges wholly above 4GB; clip any that cross it. */
	    if (ebase < 0x100000000ULL) {
		if (eend > (unsigned long long)E820_ADDR_MAX)
		    eend = (unsigned long long)E820_ADDR_MAX;

		if (eend > ebase) {
		    map[count].base = (unsigned int)ebase;
		    map[count].end  = (unsigned int)eend;
		    map[count].type = (unsigned int)entry.type;
		    count++;
		}
	    }
        }

        continuation = bb.ebx.rx;

    } while (continuation != 0 && count < maxEntries);

    *numEntries = count;

    /*
     * Top of the contiguous RAM run starting at 1MB.  E820 entries are not
     * guaranteed sorted, so repeat until stable rather than making one pass.
     */
    top = EXTENDED_ADDR;
    changed = 1;
    while (changed) {
	changed = 0;
	for (i = 0; i < count; i++) {
	    if (map[i].type != BOOT_MEM_RAM)
		continue;
	    if (map[i].base <= top && map[i].end > top) {
		top = map[i].end;
		changed = 1;
	    }
	}
    }

    return (top > EXTENDED_ADDR) ? top : 0;
}
```

`biosfn.c` already imports both `memory.h` (for `EXTENDED_ADDR`, `0x100000`) and `kernBootStruct.h` (for `boot_mem_range_t` and `BOOT_MEM_RAM`) at lines 31-32, so no new includes are needed here.

- [ ] **Step 5: Update sizememory()**

In `src/boot-2/i386/boot2/sizememory.c`, add the boot-struct include after line 25:

```c
#import <mach/i386/vm_types.h>
#import "libsaio.h"
#import <kernBootStruct.h>
#import <memory.h>
```

and replace the E820 block (lines 51-65) with:

```c
    /* Method 1: E820h memory map, which also hands the kernel the map */
    {
    	unsigned long top;
    	int numEntries = 0;

    	top = getMemoryMap(kernBootStruct->memMap, BOOT_MEMMAP_MAX,
    			   &numEntries);
    	kernBootStruct->memMapCount = numEntries;

    	if (top > EXTENDED_ADDR) {
    	    extmem_kb = (top - EXTENDED_ADDR) / 1024;
    	    printf("%dK", (int)(extmem_kb + 1024));
    	    return extmem_kb;
    	}
    }
```

`getKernBootStruct()` bzeros the whole struct before calling `sizememory()`, so `memMapCount` is already 0 on the fallback paths.

Also update the comment block at lines 27-34 to describe what the function now does:

```c
/*
 * Memory detection using BIOS INT 0x15 with multiple fallback methods:
 * 1. E820h - full memory map; also handed to the kernel in kernBootStruct
 * 2. E801h - extended memory size (up to 4GB)
 * 3. INT 88h - legacy extended memory size (up to 64MB)
 *
 * Returns extended memory size in KB (memory above 1MB)
 */
```

- [ ] **Step 6: Build the booter and check the size**

```bash
sh /build/source/vm/rebuild-i386-boot.sh
```

Expected: `=== booter rebuild done ===`. Compare `booter size:` against Step 2's number and against 39936. If it exceeds 39936, Step 8 must use `graft_file`; if it exceeds 45056 the build fails outright and the code must shrink.

- [ ] **Step 7: Verify E820 actually reaches the kernel**

The `bb.es` fix is the risky part — if ES was previously wrong, the map was garbage and nothing depended on it; if it was previously right by accident, this changes nothing. Either way the reported size is the evidence.

Copy `/build/out/i386/boot` back to `vm/artifacts/boot`, then:

```bash
cd vm && cmd //c reset-image.cmd && python rhap_inject.py work/test.img put /usr/standalone/i386/boot artifacts/boot && python qemu-shot.py work/test.img shots-t6-768 --at 45,90 --mem 768 --keys "mach_kernel -v\n"
```

If `rhap_inject.py put` refuses the payload (the booter grew past its 320 bytes of slack), use instead:

```bash
cd vm && python graft.py /usr/standalone/i386/boot artifacts/boot
```

Prefer `put` when it works: grafting the booter makes the image unbootable after any `fsck`, and `boot1` reads `/usr/standalone/i386/boot` through the filesystem.

Expected in `shots-t6-768/serial.log`: a `Sizing memory... 786432K` line (768MB expressed as KB above 1MB, plus the 1MB the print adds back) and the kernel still reporting `physical memory = 767.9...`. A wildly wrong `Sizing memory...` value means the E820 entries are not landing in `entry` — check `bb.es` and `bb.edi.rr`.

- [ ] **Step 8: Boot the matrix with the new booter**

Note this task still uses the **stock kernel path** — the kernel ignores `memMap` until Task 7 — so the reported sizes come from `extmem`, which now derives from the contiguous top rather than the sum.

```bash
cd vm && for M in 256 768 1024 2048 4096; do cmd //c reset-image.cmd; python rhap_inject.py work/test.img put /usr/standalone/i386/boot artifacts/boot; python graft.py /mach_kernel artifacts/mach_kernel; python qemu-shot.py work/test.img shots-t6-$M --at 45,90 --mem $M --keys "mach_kernel -v\n"; done
cd vm && grep -h "Sizing memory\|physical memory" shots-t6-*/serial.log
```

Expected: same `physical memory` results as Task 4 Step 7 (256/768 full, the rest clamped to 816.0), and every run reaching a login. At `-m 4096` the `Sizing memory...` value must now be the contiguous top below QEMU's PCI hole (roughly 3.5GB in KB), **not** a 4GB sum.

- [ ] **Step 9: Commit**

```bash
git add vm/rebuild-i386-boot.sh src/boot-2/i386/libsaio/biosfn.c src/boot-2/i386/libsaio/saio_internal.h src/boot-2/i386/boot2/sizememory.c
git commit -m "boot: report the contiguous memory top instead of the E820 sum

Summing every E820 RAM range ignored the PCI hole below 4GB.  Also set
ES explicitly for the E820 call and pass the map to the kernel."
```

---

## Task 7: Consume the memory map in the kernel

**Files:**
- Modify: `src/kernel-7/machdep/i386/i386_init.c:433-468`

**Interfaces:**
- Consumes: `KERNBOOTSTRUCT.memMapCount`, `KERNBOOTSTRUCT.memMap`, `BOOT_MEM_RAM` (Task 5), populated by Task 6; `kb_to_bytes()` and the clamp loop (Task 4)
- Produces: no new external symbols. `size_memory()` now prefers the map over `extmem`.

- [ ] **Step 1: Add the contiguous-top helper**

In `src/kernel-7/machdep/i386/i386_init.c`, after `kb_to_bytes()`:

```c
#define EXT_BASE	0x100000	/* extended memory starts at 1MB */

/*
 * Top of the contiguous run of usable RAM starting at 1MB, from the map the
 * booter handed over.  Mirrors getMemoryMap()'s scan in libsaio/biosfn.c:
 * entries are not guaranteed sorted, so repeat until stable.  Returns
 * EXT_BASE when no RAM adjoins 1MB.
 */
static
vm_offset_t
memmap_contiguous_top(
    KERNBOOTSTRUCT *	kbp
)
{
    vm_offset_t		top = EXT_BASE;
    int			changed = 1;
    int			i;

    while (changed) {
	changed = 0;
	for (i = 0; i < kbp->memMapCount; i++) {
	    if (kbp->memMap[i].type != BOOT_MEM_RAM)
		continue;
	    if (kbp->memMap[i].base <= top && kbp->memMap[i].end > top) {
		top = kbp->memMap[i].end;
		changed = 1;
	    }
	}
    }

    return (top);
}
```

- [ ] **Step 2: Prefer the map in size_memory()**

In `size_memory()`, replace the selection written in Task 4 Step 4:

```c
    if (maxmem)
        end_of_memory = kb_to_bytes((unsigned int) maxmem);
    else
        end_of_memory = kb_to_bytes(extmem);
```

with:

```c
    if (maxmem) {
        end_of_memory = kb_to_bytes((unsigned int) maxmem);
    }
    else {
	vm_offset_t	top = 0;

	if (kernBootStruct->memMapCount > 0)
	    top = memmap_contiguous_top(kernBootStruct);

	if (top > EXT_BASE)
	    end_of_memory = top;
	else
	    end_of_memory = kb_to_bytes(extmem);
    }
```

`memmap_contiguous_top()` is called once and its result reused, so a large map is scanned only once.

- [ ] **Step 3: Build the kernel on the guest**

```bash
sh /build/source/vm/rebuild-i386-kernel.sh
```

Expected: `=== kernel rebuild done ===`. Copy `/build/out/i386/mach_kernel` back to `vm/artifacts/mach_kernel`.

- [ ] **Step 4: Run the full Phase 1 matrix**

Both the new booter and the new kernel:

```bash
cd vm && for M in 256 768 1024 1536 2048 4096; do cmd //c reset-image.cmd; python rhap_inject.py work/test.img put /usr/standalone/i386/boot artifacts/boot; python graft.py /mach_kernel artifacts/mach_kernel; python qemu-shot.py work/test.img shots-t7-$M --at 45,90 --mem $M --keys "mach_kernel -v\n"; done
cd vm && grep -h "physical memory" shots-t7-*/serial.log
```

Expected — the Phase 1 exit criteria, matching `python memtool.py` exactly:

| `--mem` | `physical memory =` | clamp line |
| --- | --- | --- |
| 256 | 255.9 | absent |
| 768 | 767.9 | absent |
| 1024 | 816.0 | present, `clamped from 1024` |
| 1536 | 816.0 | present, `clamped from 1536` |
| 2048 | 816.0 | present, `clamped from 2048` |
| 4096 | 816.0 | present, clamped from the contiguous top below the PCI hole |

Every run reaches a login. No `pmap_map: kernel address space exhausted` panic.

- [ ] **Step 5: Commit**

```bash
git add src/kernel-7/machdep/i386/i386_init.c
git commit -m "kernel: size memory from the booter's map when it is present

Falls back to extmem when the BIOS has no E820 map."
```

---

## Task 8: Phase 2 pre-flight — confirm no prebound binary sits above 2GB

**Gate.** Phase 2 costs every process 1GB of virtual address space. Nothing in the source tree is endangered — the highest fixed load address in-tree is driverkit at `0x66700000`, libSystem at `0x41300000`, dyld at `0x41100000` — but AppKit, Foundation and friends ship prebound in the binary distribution and are not built from this tree.

If this task finds anything at or above `0x80000000`, **stop**. Phase 1 is already delivered and stands on its own; report the finding rather than proceeding.

**Files:**
- Create: `vm/scan-dylib-addrs.py`

**Interfaces:**
- Consumes: `vm/rhap_image.py` — the class is `Image` (used as a context manager), and its methods are bound at module level: `img.listdir(path)` yields `(name, ino, dtype)` where **`dtype` is an int** (`4` dir, `8` reg, `10` lnk), and file contents come from `img.read_file(img.resolve(path))`. There is no `cat` method.
- Produces: a CLI reporting the highest `__TEXT` end address across the image's dylibs and frameworks. Not consumed by later tasks — it is a gate, not a dependency.

- [ ] **Step 1: Write the scanner**

Create `vm/scan-dylib-addrs.py`:

```python
"""Report the highest __TEXT address of every Mach-O dylib in a Rhapsody image.

Phase 2 of the large-memory work shrinks user virtual address space from 3GB
to 2GB.  Prebound libraries load at fixed addresses, so anything whose __TEXT
segment reaches 0x80000000 would break.  This reads the image directly - no
mount, no otool - reusing rhap_image.py's UFS reader.
"""

import struct
import sys

import rhap_image

MH_MAGIC = 0xFEEDFACE
MH_CIGAM = 0xCEFAEDFE
LC_SEGMENT = 0x1
CEILING = 0x80000000

DT_DIR = 4
DT_REG = 8

SEARCH_DIRS = [
    "/usr/lib",
    "/usr/local/lib",
    "/System/Library/Frameworks",
    "/System/Library/PrivateFrameworks",
]


def text_extent(data):
    """Return (vmaddr, vmsize) of __TEXT, or None if not a 32-bit Mach-O."""
    if len(data) < 28:
        return None

    magic = struct.unpack("<I", data[0:4])[0]
    if magic == MH_MAGIC:
        end = "<"
    elif magic == MH_CIGAM:
        end = ">"
    else:
        return None

    ncmds = struct.unpack(end + "I", data[16:20])[0]
    off = 28

    for _ in range(ncmds):
        if off + 8 > len(data):
            return None
        cmd, cmdsize = struct.unpack(end + "II", data[off:off + 8])
        if cmdsize < 8:
            return None
        if cmd == LC_SEGMENT and off + 48 <= len(data):
            name = data[off + 8:off + 24].rstrip(b"\0").decode("ascii", "replace")
            if name == "__TEXT":
                vmaddr, vmsize = struct.unpack(end + "II", data[off + 24:off + 32])
                return (vmaddr, vmsize)
        off += cmdsize

    return None


def walk(img, path, out, depth=0):
    if depth > 6:
        return
    try:
        entries = img.listdir(path)
    except (FileNotFoundError, NotADirectoryError, OSError):
        return

    for name, ino, dtype in entries:
        if name in (".", ".."):
            continue
        child = path.rstrip("/") + "/" + name
        if dtype == DT_DIR:
            walk(img, child, out, depth + 1)
        elif dtype == DT_REG:
            try:
                data = img.read_file(ino)
            except (OSError, ValueError):
                continue
            extent = text_extent(data)
            if extent is not None:
                out.append((child, extent[0], extent[0] + extent[1]))


def main(argv):
    if len(argv) < 2:
        print("usage: scan-dylib-addrs.py IMAGE [DIR ...]", file=sys.stderr)
        return 2

    dirs = argv[2:] or SEARCH_DIRS

    found = []
    with rhap_image.Image(argv[1]) as img:
        for d in dirs:
            walk(img, d, found)

    found.sort(key=lambda row: row[2], reverse=True)

    over = [row for row in found if row[2] >= CEILING]

    print("scanned %d Mach-O images" % len(found))
    print("\nhighest 20 by __TEXT end:")
    for path, start, end in found[:20]:
        flag = "  <-- OVER 2GB" if end >= CEILING else ""
        print("  0x%08X-0x%08X  %s%s" % (start, end, path, flag))

    print("")
    if over:
        print("FAIL: %d image(s) reach or exceed 0x%08X" % (len(over), CEILING))
        for path, start, end in over:
            print("  0x%08X-0x%08X  %s" % (start, end, path))
        return 1

    print("PASS: no image reaches 0x%08X" % CEILING)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

The directory walk skips symlinks (`dtype == 10`) by only recursing on `DT_DIR` and reading `DT_REG`, which matters because `/usr/lib` and friends sit under real paths while `/etc`, `/private/Devices` and `/usr/Devices` are symlinks that `rhap_image.py` does not follow.

- [ ] **Step 2: Run the scan**

```bash
cd vm && python scan-dylib-addrs.py golden.img
```

`golden.img` is safe here — the scanner is read-only and `rhap_image.py` accepts any path.

Expected: `PASS: no image reaches 0x80000000`, and the highest-20 list topping out well below it (libSystem near `0x41300000`, driverkit's libDriver near `0x66700000`).

- [ ] **Step 3: Decide the gate**

- **PASS** → commit the scanner and continue to Task 9.
- **FAIL** → commit the scanner, then **stop and report**. Record which images sit above the ceiling in `docs/superpowers/specs/2026-07-25-i386-large-memory-design.md` under Phase 2, and do not change `VM_MAX_ADDRESS`. Phase 1 is complete and shipped regardless.

- [ ] **Step 4: Commit**

```bash
git add vm/scan-dylib-addrs.py
git commit -m "vm: scan a Rhapsody image for prebound libraries above 2GB

Pre-flight for shrinking user address space from 3GB to 2GB."
```

---

## Task 9: Move the split to 2G/2G

Three constants. The page-directory arithmetic works out with no structural change: `KERNEL_LINEAR_BASE / I386_SECTBYTES` becomes `0x80000000 / 4MB` = 512, so the kernel owns `pd[512..1023]` and `pmap_enable_pg()`'s double-map lands in `pd[0..511]` — adjacent, no overlap. Segment limits encode exactly: `page_limit(0x80000000)` is `0x7FFFF000`, a 20-bit field of `0x7FFFF` with page granularity.

**Files:**
- Modify: `src/kernel-7/mach/i386/vm_param.h:66,69`
- Modify: `src/kernel-7/bsd/i386/vmparam.h:46`

**Interfaces:**
- Consumes: the clamp loop from Task 4, which reads its budget from `VM_MAX_KERNEL_ADDRESS` and so retargets itself
- Produces: no new symbols. `KERNEL_LINEAR_BASE` follows `VM_MAX_ADDRESS` automatically via `machdep/i386/pmap.h:84`.

- [ ] **Step 1: Confirm Task 8 passed**

```bash
cd vm && python scan-dylib-addrs.py golden.img | tail -3
```

Expected: `PASS: no image reaches 0x80000000`. Do not proceed on a FAIL.

- [ ] **Step 2: Confirm no other hardcoded copy of the constants**

```bash
cd D:/RhapsodiOS && grep -rn "0xc0000000\|0xC0000000" --include=*.c --include=*.h --include=*.s src/kernel-7 | grep -v netinet | grep -v "/ppc/"
```

Expected: exactly two hits — `mach/i386/vm_param.h:66` and `bsd/i386/vmparam.h:46`. Any third hit is a hardcoded duplicate that must move too; add it to this task rather than leaving it behind.

- [ ] **Step 3: Move the constants**

In `src/kernel-7/mach/i386/vm_param.h`, lines 65-69:

```c
#define VM_MIN_ADDRESS		((vm_offset_t) 0)
#define VM_MAX_ADDRESS		((vm_offset_t) 0x80000000)

#define VM_MIN_KERNEL_ADDRESS	((vm_offset_t) 0x00000000)
#define VM_MAX_KERNEL_ADDRESS	((vm_offset_t) 0x80000000)
```

In `src/kernel-7/bsd/i386/vmparam.h`, line 46:

```c
#define	USRSTACK	0x80000000
```

- [ ] **Step 4: Build the kernel on the guest**

```bash
sh /build/source/vm/rebuild-i386-kernel.sh
```

Expected: `=== kernel rebuild done ===`. Copy `/build/out/i386/mach_kernel` back to `vm/artifacts/mach_kernel`.

- [ ] **Step 5: Run the Phase 2 matrix**

```bash
cd vm && for M in 256 768 1024 1536 2048 4096; do cmd //c reset-image.cmd; python rhap_inject.py work/test.img put /usr/standalone/i386/boot artifacts/boot; python graft.py /mach_kernel artifacts/mach_kernel; python qemu-shot.py work/test.img shots-t9-$M --at 45,90 --mem $M --keys "mach_kernel -v\n"; done
cd vm && grep -h "physical memory" shots-t9-*/serial.log
```

Expected — the Phase 2 exit criteria, matching `python memtool.py --2g` exactly:

| `--mem` | `physical memory =` | clamp line |
| --- | --- | --- |
| 256 | 255.9 | absent |
| 768 | 767.9 | absent |
| 1024 | 1024.0 | absent |
| 1536 | 1536.0 | absent |
| 2048 | 1776.0 | present |
| 4096 | 1776.0 | present |

The headline result is `-m 1536` reporting the full 1536MB where Task 7 clamped it to 816MB. Every run must still reach a login — this is where a prebound-address collision would surface, as userland failing to start while the kernel itself boots fine.

- [ ] **Step 6: Commit**

```bash
git add src/kernel-7/mach/i386/vm_param.h src/kernel-7/bsd/i386/vmparam.h
git commit -m "kernel: split the address space 2G/2G instead of 3G/1G

Doubles the kernel linear window, raising usable RAM from ~816MB to
~1776MB.  Costs each process 1GB of virtual address space."
```

---

## Task 10: Record the outcome

**Files:**
- Modify: `docs/superpowers/specs/2026-07-25-i386-large-memory-design.md`

- [ ] **Step 1: Replace the predicted numbers with the measured ones**

In the spec's "Phase 1 success criteria" and "Phase 2 success criteria" sections, replace the expected ranges with the values actually observed in `shots-t7-*` and `shots-t9-*`. If any measured value differs from `memtool.py`'s prediction, note the discrepancy and its cause — a divergence means the C estimator and the Python model disagree, which is a bug in one of them, not a documentation matter.

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-07-25-i386-large-memory-design.md
git commit -m "docs: record measured memory sizing results for i386"
```

---

## Self-Review Notes

**Spec coverage:** every spec section maps to a task — 1a→Task 6, 1b→Task 5, 1c→Tasks 4+7, 1d→Task 3, 1e→Task 4, 2a→Task 8, 2b→Task 9, 2c→verified in Task 9's preamble, 2d→Task 4's budget symbol, 2e→left alone as the spec says. The spec's "Out of scope" items generate no tasks, as intended.

**Deviation from spec ordering:** the spec presents Phase 1 as boot-side-then-kernel-side. This plan inverts it — kernel first (Tasks 3, 4), booter second (Task 6). The kernel clamp is fully testable against the *stock* booter, since the existing `extmem` path already reports ~2GB at `-m 2048` and already overflows to 0 at `-m 4096`. Landing it first means the highest-risk change (the booter, which has 320 bytes of image slack and an ES-register bug) is made against a kernel already proven to survive large values.

**Known risk, not designed around:** Task 6 Step 7 is the first point where the `bb.es` fix is exercised. If E820 was silently returning garbage before, the `Sizing memory...` value will change noticeably at that step — that is the signal to check, and the step calls it out rather than assuming the map was ever correct.
