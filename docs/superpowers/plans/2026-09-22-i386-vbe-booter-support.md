# i386 VESA Booter Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make our booter enter a VBE mode and record it where spec 1's driver and spec 2's kernel read it, and make the kernel map the frame buffer, so the i386 boot console draws through the frame-buffer console.

**Architecture:** Nine tasks.

- **Tasks 1 and 2 build and test tools**, with complete code below:
  - capture options for `qemu-shot.py`;
  - a boot-area writer;
  - link-order control for `install-driver.py`;
  - a capstone-based byte comparator for code with no relocation table.
- **Task 3 measures.** It covers the ten items in spec §4.2 plus the kernel mapping, and records them in a new evidence record.
- **Task 4 names the `KERNBOOTSTRUCT` fields** at the 4.2 offsets.
- **Task 5 trims `boot2`** to make room.
- **Tasks 6 and 7 reconstruct the 4.2 booter's VBE code**, function by function, to byte parity where the compiler allows.
- **Task 8 adds the kernel's frame-buffer mapping.**
- **Task 9 runs gates G1-G5** and writes the records.

Tasks 5-8 reconstruct code whose shape comes from Task 3's measurements. So they carry exact procedures, commands and acceptance checks rather than code, as spec 2's plan did for the same reason.

**Tech Stack:**
- Python 3.12 in `.venv-binrecon`, with capstone 5.0.6 and pytest.
- The Rhapsody build guest, driven by `rbuild` over one SSH session.
- QEMU through `vm/qemu-shot.py`, `vm/graft-kernel.py`, `vm/install-driver.py` and the new `vm/install-booter.py`.

**Spec:** [2026-09-22-i386-vbe-booter-support-design.md](../specs/2026-09-22-i386-vbe-booter-support-design.md)

## Global Constraints

```text
VENVPY=D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe
PATCH=C:/Users/raynorpat/Downloads/OS42MachUserPatch4.tar
BREF=C:/Users/raynorpat/Downloads/test/OS42/boot_i386
BREFSHA=925D35B683644CDA6C090B223B00C115F1C83116D466F230B71231B7AB75CBCE
KREF=C:/Users/raynorpat/Downloads/test/OS42/mach_kernel_i386
KREFSHA=33469393C0843FC741942C3AE9D91D838467D72ABD647DCF2E5BF499A3F14890
GOLDEN=D:/RhapsodiOS/vm/golden.img
GOLDENSHA=E1968E3EF57F3060AA01CEAB8B4D5C49C067E6ACC5F8626EBABEEFE0E663879F
KSPEC2=vm/work/task4c-mach_kernel
KSPEC2SHA=74B12FCD53E886AAFCBB29AD400C5DEDD10B26F04BBA0FBC6E02DAEFEA25CFF4
DRV=D:/RhapsodiOS/.worktrees/vbe20-recon/out/i386/drvVBE20DisplayDriver/VBE20DisplayDriver.config
DRVSHA=77399531152E287487668F6222467CF9C1ECA449859B169A66352B608A3A36A1
BDIV=src/boot-2/reconstruction/vbe/divergences.md
KDIV=src/kernel-7/reconstruction/vbe/divergences.md
GATE=docs/kernel/i386-vbe-console.md
```

`DRVSHA` is the hash of `$DRV/VBE20DisplayDriver_reloc`, and it equals spec 1's
recorded `rebuilt_sha256`.

**Where to work.** Use the worktree `.worktrees/vbe20-kernel`, on branch
`vbe20-booter`. Its parents `vbe20-kernel` and `vbe20-recon` are **not merged
to master**.

**The main checkout has another session's uncommitted work.** Never `cd` to
`D:\RhapsodiOS`, never check out master, and never merge. A bare `cd` in one
Bash call moves the shell for every later call. It has already landed this
session in the main checkout twice. Use absolute paths, `git -C`, or a subshell
`(cd <worktree> && ...)`.

**Never commit:** `$BREF`, `$KREF`, `out/`, `vm/work/`, `vm/install/`,
`vm/vm.conf`, `vm/bridge.conf`, `tools/binrecon/out/`, any pulled binary, or any
throwaway script. Stage files by name. Never use `git add -A` or `git add .`:
`vm/` has hundreds of untracked files.

**Python is `$VENVPY`.** binrecon tools need `PYTHONPATH=tools/binrecon`.

**Build with `rbuild` only. Never fall back to `gnumake`.**
- The booter: `rbuild buildpackage --state /build/state --arch i386 --dir --target all /build/src/boot-2 /build/repo <dest>`, as `vm/build-i386-booter.sh` runs it.
- The kernel: `rbuild kernel --state /build/state --toolchain /tmp/<task>-gcc-darwin.conf --arch i386 /build/src /build/repo /tmp/<task>-dst`.
- The kernel's toolchain profile is a `sed` copy that appends `/usr/local/bin` to `path=`. Write it first:
  ```sh
  sed -e 's|^path=.*|path=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin|' \
      /build/src/rbuild-1/toolchains/gcc-darwin.conf > /tmp/<task>-gcc-darwin.conf
  ```
  `$KDIV` "The build: `rbuild kernel` needs `--toolchain`" explains why.
- If either build fails, report it.

**The guest.** The build guest is reached as `vm/vm.conf` describes.
- **One SSH session at a time, no polling.** Two earlier runs killed the guest's `sshd` by starving it of processes.
- Its login shell is `csh`, where `2>&1` fails. Send scripts to `/bin/sh -s` on stdin instead:
  ```powershell
  powershell -NoProfile -File vm\sync-src.ps1 -Path <project>
  . .\vm\rhap-remote.ps1
  $cfg = Get-RhapVmConfig
  $ssh = Resolve-RhapTool $cfg.Ssh
  $ec = Invoke-RhapSshScript -Cfg $cfg -Ssh $ssh -ScriptBody (Get-Content -Raw <local script>) -Stream
  ```
- **Get results back through the same session.** Print the log, then print each binary `uuencode`d. `-Stream` writes through `Write-Host`, so to keep the output in a file, append `6>&1 | Out-File -Encoding ascii <local log>`. Decode locally with this throwaway, which is never committed:
  ```python
  import binascii, sys
  out, on = bytearray(), False
  for line in open(sys.argv[1], "rb"):
      line = line.rstrip(b"\r\n")
      if line.startswith(b"begin "):
          on = True
          continue
      if line == b"end":
          break
      if on and line and line != b"`":
          out += binascii.a2b_uu(line)
  open(sys.argv[2], "wb").write(out)
  ```
- **Check every pulled binary two ways.** Print `sum` and `cksum` on the guest, and reproduce both from the decoded bytes.

**Images.** Only `vm/work/test.img` is ever written. `rhap_inject.check_target`
enforces this, and every boot tool calls it. Rebuild the image from `$GOLDEN`
before every boot:
```bash
MSYS_NO_PATHCONV=1 $VENVPY vm/graft-kernel.py "$GOLDEN" <kernel> vm/work/test.img     # when a kernel is under test
mv vm/work/test.img vm/work/kern.img && MSYS_NO_PATHCONV=1 $VENVPY vm/install-driver.py vm/work/kern.img "$DRV" vm/work/test.img   # when the driver is
MSYS_NO_PATHCONV=1 $VENVPY vm/install-booter.py vm/work/test.img <booter>          # when our booter is
```
Order matters: `install-booter.py` runs last, on the finished `test.img`.
Before booting, read `/mach_kernel` and every installed driver file back out of
the image and hash them against the source, as spec 2's gate record did.

**Do not modify:**
- `src/drivers-i386`, except the `src/drivers-i386/README` status row in
  Task 9. Spec 1's `_reloc` hash is the driver's evidence, and even a comment
  edit shifts its stabs line numbers.
- `src/boot-2/i386/boot1`, or anything that moves the boot-area copies. Spec 3
  keeps `boot1`, `LOADSZ` and the disk layout as they are.

**Do not invent.** If the disassembly does not show it, it is not written.
Record the gap in the evidence record.
- Reproduce reference defects verbatim, and label them on the line.
- Mark every claim `[measured]` or `[inference]` on the line that states it.
- Label retracted text in place; do not delete it.

**Address notation.**
- `boot+N` is a **file offset** into `$BREF`. The 4.2 booter loads at
  `0x3000`, so the address is `boot+N + 0x3000`.
- Kernel addresses are `0x...` in `$KREF`, whose file offset is the address
  minus `0x100000`.
- Source comments cite reference addresses. Records may cite task numbers,
  but never "the brief": briefs are gitignored.

**Commits:** one to two lines, prefixed by subsystem, ending with
`Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and nothing else.
- `boot:` for `src/boot-2`;
- `kernel:` for `src/kernel-7`;
- `vm:` for `vm/` tools;
- `binrecon:` for `tools/binrecon`;
- `docs:` for documents only.

### The contract (spec §3), restated because every task touches it

| Address | Offset | Field (named in Task 4) | Written by |
| --- | --- | --- | --- |
| `0x12854` | 6228 | `vbeFrameBuffer` | kernel, `pmap_bootstrap` (Task 8) |
| `0x12858` | 6232 | `vbeCurrentMode` | booter (Task 6/7) |
| `0x12870` | 6256 | `vbeModes[89]` | booter (Task 6/7) |
| `0x130D8` | 8408 | `video` (unchanged) | not written by VBE code |

- **At most 89 records.** The booter writes nothing at or beyond offset 8408.
  Index 89 stays zero, so the driver's scan stops at 89.
- **Write order.** Every booter write happens after `getKernBootStruct()`
  (`src/boot-2/i386/libsaio/bootstruct.c:79`), which `bzero`s the whole
  struct at `:84`.
- **The large-memory branch** (`worktree-i386-large-memory`) plans to cut
  bytes 908-1296 from the front of `_reserved`. It does not overlap. Whichever
  branch merges second updates the other's size assertion.

### Measured during planning, 2026-09-22 [measured]

- **`$GOLDEN`'s NeXT label is at sector 15**, and there is no fdisk partition
  (the MBR's four entries are zero). `d_secsize` is 1024, `d_front` 160, and
  `d_boot0_blkno` is (32, 96). So the two boot copies start at bytes 32,768
  and 98,304, and each slot is 65,536 bytes. Both hold the stock
  `/usr/standalone/i386/boot` (39,616 bytes, SHA-256
  `AA06C3C5BFE56C79573E36D20C662DA10CA67D0CEC5BE17F13A5B562F6B5F2C2`)
  followed by zeros.
- **The file itself is not what boots.** `boot1` reads the label's
  `d_boot0_blkno[0]`. The file's slot is 39,936 bytes, too small for our
  booter anyway.
- **The 4.2 booter loads at `0x3000`.** All twelve VBE-related strings are
  referenced there as absolute addresses, and none at 0, `0x1000` or `0x2000`.
  Its record writer is `boot+27556..27702`, 147 bytes plus one pad `nop`.
  Its signature is `(VBEModeRec *dst, unsigned short mode, VBEModeInfoBlock *mib)`.
  It assembles the physical base address byte by byte, like our `vbe.c`'s
  `ADDRESS()` macro.
- **The golden image's `Active Drivers`** is
  `CirrusLogicGD5434DisplayDriver BusMouse NE2K`. On `-vga std` the Window
  Server may therefore not find a display. **No gate needs the desktop.**
- **`install-driver.py` does not run as written on this host.** It clones its
  input with `cp -c`, which Git Bash's `cp` rejects. Task 1 fixes it.

### Comparison rules for every A-B-A (from spec 2)

1. **Same session, on an image rebuilt from `$GOLDEN`:** control, then
   candidate, then control, back to back.
2. **Serial line 4:** mask only its build date. The config and version string
   must match.
3. **Serial, everything else:** unsorted identity. The IDE-probe block
   (`Registering: hc0`, `hd0: ...`) and the `intr: phantom IRQ 15` lines may
   swap position; any other reordering is a finding.
4. **Frames:** mask only the boot-clock digit cells. Everything outside the
   mask must be pixel-identical.
5. **Verbose boots:** type `--keys $'mach_kernel -v\n' --keys-at 8`. Never use
   `--keys-at 3`: it truncates the string to `mach_ke`.

---

## File Structure

| File | Responsibility | Task |
| --- | --- | --- |
| `vm/qemu-shot.py`, `vm/test_qemu_shot.py` | `--vga`, `--pmemsave` | 1 |
| `vm/install-booter.py`, `vm/test_install_booter.py` | write `boot2` into both boot-area copies | 1 |
| `vm/install-driver.py`, `vm/test_install_driver.py` | `--first`; portable image copy | 1 |
| `tools/binrecon/compare_flat.py`, `tools/binrecon/tests/test_compare_flat.py` | byte-compare one function between two flat images | 2 |
| `$BDIV` | booter evidence record | 3, 5, 6, 7 |
| `$KDIV` | kernel mapping evidence | 3, 8 |
| `src/boot-2/i386/libsa/kernBootStruct.h`, `src/kernel-7/machdep/i386/kernBootStruct.h` | named VBE fields and offset assertions | 4 |
| `src/boot-2/i386/**` | the trim | 5 |
| `src/boot-2/i386/libsaio/vbe.c`, `vbe.h` | 4.2's VBE functions | 6 |
| `src/boot-2/i386/boot2/boot.c`, `graphics.c` | `VBE Mode` key, `VBE Check`, mode set in the boot flow | 7 |
| `src/kernel-7/machdep/i386/pmap.c`, `src/kernel-7/bsd/dev/i386/FBConsole.c` | frame-buffer mapping; the comment on `0x12854` | 8 |
| `$GATE`, `docs/drivers/video-reconstruction.md`, `src/drivers-i386/README` | gate record and status | 9 |

---

## Task 1: Boot and capture tooling

**Files:**
- Modify: `vm/qemu-shot.py`, `vm/test_qemu_shot.py`
- Create: `vm/install-booter.py`, `vm/test_install_booter.py`
- Modify: `vm/install-driver.py`
- Create: `vm/test_install_driver.py`

**Interfaces:**
- Consumes: `rhap_inject.check_target`, `rhap_inject.SafetyError`,
  `rhap_image.LABEL_OFFSETS`, `rhap_image.LABEL_MAGIC`.
- Produces:
  - `qemu-shot.py IMAGE OUTDIR ... [--vga cirrus|std] [--pmemsave SECONDS:ADDR:LEN]...`.
    Dumps are named `OUTDIR/pmem-<SECONDS>s-0x<addr>.bin`.
  - `install-booter.py IMAGE BOOTER`: returns 0 on success, 1 on refusal.
  - `install-driver.py SRC DRIVER_DIR OUT [--first]`.

All code below was run against copies of these files on 2026-09-22. The tests
passed with the change, and the new tests failed without it.

**Merge note.** `worktree-i386-large-memory` adds `--mem` to `qemu-shot.py`.
Keep these changes additive: new keyword parameters with defaults, appended
at the end. Its merge then needs only a textual resolution.

- [ ] **Step 1: Write the failing `qemu-shot.py` tests**

In `vm/test_qemu_shot.py`, insert these classes immediately before
`class TestFixKeysArg(unittest.TestCase):`:

```python
class TestVgaChoice(unittest.TestCase):
    def test_vga_defaults_to_cirrus(self):
        args = qemu_shot.build_qemu_args("work/test.img", 1234, False, "out/serial.log")
        self.assertEqual(args[args.index("-vga") + 1], "cirrus")

    def test_vga_std_is_passed_through(self):
        args = qemu_shot.build_qemu_args("work/test.img", 1234, False, "out/serial.log", "std")
        self.assertEqual(args[args.index("-vga") + 1], "std")


class TestParsePmem(unittest.TestCase):
    def test_parses_seconds_and_hex(self):
        self.assertEqual(qemu_shot.parse_pmem("60:0x11000:0x2200"), (60.0, 0x11000, 0x2200))

    def test_rejects_a_missing_field(self):
        with self.assertRaises(ValueError):
            qemu_shot.parse_pmem("60:0x11000")

    def test_rejects_a_zero_length(self):
        with self.assertRaises(ValueError):
            qemu_shot.parse_pmem("60:0x11000:0")


class TestPmemsaveEvent(unittest.TestCase):
    def test_run_issues_pmemsave_with_an_absolute_path(self):
        fake_qmp = mock.MagicMock()
        with mock.patch.object(qemu_shot.rhap_inject, "check_target", lambda p: None), \
                mock.patch.object(qemu_shot.subprocess, "Popen") as popen, \
                mock.patch.object(qemu_shot, "QMP", return_value=fake_qmp):
            with tempfile.TemporaryDirectory() as tmpdir:
                qemu_shot.run("work/test.img", tmpdir, [], None, 3.0, False,
                              vga="std", pmem=[(0.0, 0x11000, 0x2200)])
                want = os.path.abspath(os.path.join(tmpdir, "pmem-0s-0x11000.bin"))
        fake_qmp.execute.assert_any_call("pmemsave", val=0x11000, size=0x2200, filename=want)
        launched = popen.call_args[0][0]
        self.assertEqual(launched[launched.index("-vga") + 1], "std")
```

- [ ] **Step 2: Run them and see them fail**

Run: `$VENVPY -m unittest discover -s vm -p test_qemu_shot.py -v`

Expected: 5 errors (`TestParsePmem` x3, `TestPmemsaveEvent`,
`test_vga_std_is_passed_through`). `test_vga_defaults_to_cirrus` already
passes: it is a regression guard.

- [ ] **Step 3: Implement `--vga` and `--pmemsave`**

In `vm/qemu-shot.py`:

The usage block in the module docstring becomes:

```
Usage:
    python qemu-shot.py IMAGE OUTDIR [--at SECONDS[,SECONDS...]]
                         [--keys STRING] [--keys-at SECONDS] [--trace]
                         [--vga cirrus|std] [--pmemsave SECONDS:ADDR:LEN]...

--vga picks QEMU's display adapter. cirrus, the default, is what every
earlier capture used; std is QEMU's Bochs VBE adapter.

--pmemsave saves LEN bytes of guest physical memory from ADDR at SECONDS,
as OUTDIR/pmem-<SECONDS>s-<ADDR>.bin, through QMP's pmemsave. Repeatable.
```

After `DEFAULT_KEYS_AT = 3.0` add:

```python
VGA_CHOICES = ("cirrus", "std")
```

Change the signature and the `-vga` argument of `build_qemu_args`:

```python
def build_qemu_args(image, qmp_port, trace, serial_log, vga="cirrus"):
```
```python
        "-nodefaults", "-vga", vga, "-display", "none",
```

After `fmt_seconds` add:

```python
def parse_pmem(spec):
    """Parse --pmemsave's SECONDS:ADDR:LEN, e.g. 60:0x11000:0x2200."""
    parts = spec.split(":")
    if len(parts) != 3:
        raise ValueError("--pmemsave wants SECONDS:ADDR:LEN, got %r" % spec)
    seconds, addr, length = float(parts[0]), int(parts[1], 0), int(parts[2], 0)
    if seconds < 0 or addr < 0 or length <= 0:
        raise ValueError("--pmemsave values out of range in %r" % spec)
    return seconds, addr, length
```

In `run`, change the signature and the `build_qemu_args` call:

```python
def run(image, outdir, at_points, keys, keys_at, trace, vga="cirrus", pmem=()):
```
```python
    qemu_args = build_qemu_args(image, qmp_port, trace, serial_log, vga)
```

Before `events.sort(...)` add:

```python
        for seconds, addr, length in pmem:
            events.append((seconds, "pmem", (addr, length)))
```

Between the `if kind == "shot":` branch and the `else:` that sends keys add:

```python
            elif kind == "pmem":
                addr, length = payload
                pmem_path = os.path.abspath(os.path.join(
                    outdir, "pmem-%ss-0x%x.bin" % (fmt_seconds(target), addr)))
                qmp.execute("pmemsave", val=addr, size=length, filename=pmem_path)
                print("wrote %s (%d bytes at 0x%x)" % (pmem_path, length, addr))
```

In `main`, after the `--trace` argument add:

```python
    p.add_argument("--vga", choices=VGA_CHOICES, default="cirrus",
                    help="QEMU display adapter (default: cirrus)")
    p.add_argument("--pmemsave", type=parse_pmem, action="append", default=[],
                    metavar="SECONDS:ADDR:LEN",
                    help="save guest physical memory at SECONDS; repeatable")
```

and change the final call to:

```python
    run(args.image, args.outdir, at_points, args.keys, args.keys_at, args.trace,
        args.vga, args.pmemsave)
```

- [ ] **Step 4: Run the tests and see them pass**

Run: `$VENVPY -m unittest discover -s vm -p test_qemu_shot.py -v`

Expected: 15 tests, OK.

- [ ] **Step 5: Write the failing `install-booter` tests**

Create `vm/test_install_booter.py`:

```python
"""Unit tests for install-booter.py.

Run from the repository root with:
    python -m unittest discover -s vm -p test_install_booter.py -v
"""
import importlib.util
import os
import struct
import tempfile
import unittest
import unittest.mock as mock

_HERE = os.path.dirname(os.path.abspath(__file__))


def _load():
    spec = importlib.util.spec_from_file_location(
        "install_booter", os.path.join(_HERE, "install-booter.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ib = _load()

KB = 1024


def _make_image(path, front=160, boot0=(32, 96), secsize=1024):
    """A disk image with only a NeXT label at sector 15, laid out like
    golden.img: 1 KB sectors, copies at blocks 32 and 96, porch of 160."""
    label = bytearray(1024)
    label[:4] = b"dlV3"
    struct.pack_into(">i", label, 92, secsize)
    struct.pack_into(">h", label, 112, front)
    struct.pack_into(">ii", label, 124, *boot0)
    data = bytearray(b"\xAA" * (200 * KB))      # non-zero, to see what changes
    data[7680:7680 + 1024] = label
    with open(path, "wb") as f:
        f.write(data)
    return bytes(data)


class InstallBooterTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.image = os.path.join(self.tmp.name, "test.img")
        self.guard = mock.patch.object(ib.rhap_inject, "check_target", lambda p: None)
        self.guard.start()

    def tearDown(self):
        self.guard.stop()
        self.tmp.cleanup()

    def _read(self):
        with open(self.image, "rb") as f:
            return f.read()

    def test_writes_both_copies_and_zero_fills_each_slot(self):
        before = _make_image(self.image)
        booter = bytes(range(256)) * 100             # 25,600 bytes
        slots = ib.install_booter(self.image, booter, 45056)
        self.assertEqual(slots, [(32 * KB, 64 * KB), (96 * KB, 64 * KB)])
        after = self._read()
        for off, length in slots:
            self.assertEqual(after[off:off + len(booter)], booter)
            self.assertEqual(after[off + len(booter):off + length], bytes(length - len(booter)))
        self.assertEqual(after[:32 * KB], before[:32 * KB])        # label untouched
        self.assertEqual(after[160 * KB:], before[160 * KB:])      # past the porch untouched

    def test_refuses_a_booter_longer_than_loadsz(self):
        before = _make_image(self.image)
        with self.assertRaises(ib.rhap_inject.SafetyError):
            ib.install_booter(self.image, b"\x01" * 45057, 45056)
        self.assertEqual(self._read(), before)

    def test_refuses_a_booter_longer_than_a_slot_before_writing_either(self):
        before = _make_image(self.image, front=104)   # second slot is 8 KB
        with self.assertRaises(ib.rhap_inject.SafetyError):
            ib.install_booter(self.image, b"\x01" * (9 * KB), 45056)
        self.assertEqual(self._read(), before)

    def test_refuses_an_image_the_guard_refuses(self):
        before = _make_image(self.image)
        self.guard.stop()
        try:
            with mock.patch.object(ib.rhap_inject, "check_target",
                                   side_effect=ib.rhap_inject.SafetyError("no")):
                with self.assertRaises(ib.rhap_inject.SafetyError):
                    ib.install_booter(self.image, b"\x01" * 100, 45056)
        finally:
            self.guard.start()
        self.assertEqual(self._read(), before)

    def test_read_loadsz_reads_boot1(self):
        path = os.path.join(self.tmp.name, "boot1.s")
        with open(path, "w") as f:
            f.write("BUFSZ\t\tEQU\t2000h\nLOADSZ\t\tEQU\t88\t; maxiumum possible size\n")
        self.assertEqual(ib.read_loadsz(path), 45056)

    def test_read_loadsz_refuses_a_file_without_it(self):
        path = os.path.join(self.tmp.name, "boot1.s")
        with open(path, "w") as f:
            f.write("BUFSZ\t\tEQU\t2000h\n")
        with self.assertRaises(ValueError):
            ib.read_loadsz(path)

    def test_repository_boot1_gives_45056(self):
        self.assertEqual(ib.read_loadsz(), 45056)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 6: Run them and see them fail**

Run: `$VENVPY -m unittest discover -s vm -p test_install_booter.py -v`

Expected: an import error, because `install-booter.py` does not exist.

- [ ] **Step 7: Write `vm/install-booter.py`**

```python
"""Write a boot2 image into both boot-area copies of vm/work/test.img.

boot1 does not load /usr/standalone/i386/boot. It reads the NeXT disk label
at sector 15, takes dl_boot0_blkno[0] and loads LOADSZ sectors from there
(src/boot-2/i386/boot1/boot1.s:185-210). The label names a second copy in
dl_boot0_blkno[1]; both are written so they stay identical, as they are on
golden.img. Each copy's slot runs from its block to the next copy's block,
or to the end of the front porch for the last one, and the whole slot is
rewritten: the booter, then zeros.

Refuses, before writing anything, a booter longer than LOADSZ sectors (read
out of boot1.s, as boot2/Makefile does) or longer than either slot. Only
vm/work/test.img may be written (rhap_inject.check_target). Every slot is
read back and compared after writing.

Usage: install-booter.py IMAGE BOOTER
"""
import hashlib
import os
import re
import struct
import sys

import rhap_image
import rhap_inject

_HERE = os.path.dirname(os.path.abspath(__file__))
BOOT1_SRC = os.path.join(_HERE, "..", "src", "boot-2", "i386", "boot1", "boot1.s")

# Offsets into the disk label: dl_dt (a disktab_t) starts at 44, and
# d_secsize, d_front and d_boot0_blkno[2] sit at 48, 68 and 80 within it
# (src/kernel-7/bsd/sys/disktab.h). All big-endian.
SECSIZE_OFF = 92
FRONT_OFF = 112
BOOT0_OFF = 124


def read_loadsz(boot1_src=BOOT1_SRC):
    """Return boot1's LOADSZ in bytes."""
    with open(boot1_src) as f:
        m = re.search(r"^LOADSZ\s+EQU\s+(\d+)", f.read(), re.M)
    if m is None:
        raise ValueError("no LOADSZ in %s" % boot1_src)
    return int(m.group(1)) * 512


def boot_slots(f):
    """Return [(offset, length)] for the two boot-area copies."""
    for off in rhap_image.LABEL_OFFSETS:
        f.seek(off)
        buf = f.read(1024)
        if buf[:4] == rhap_image.LABEL_MAGIC:
            break
    else:
        raise rhap_inject.SafetyError("no NeXT disk label found")
    secsize = struct.unpack_from(">i", buf, SECSIZE_OFF)[0]
    front = struct.unpack_from(">h", buf, FRONT_OFF)[0]
    b0, b1 = struct.unpack_from(">ii", buf, BOOT0_OFF)
    if not 0 < b0 < b1 < front:
        raise rhap_inject.SafetyError(
            "boot blocks %d, %d do not fit a front porch of %d" % (b0, b1, front))
    return [(b0 * secsize, (b1 - b0) * secsize),
            (b1 * secsize, (front - b1) * secsize)]


def install_booter(image, booter, limit):
    """Write `booter` into both slots of `image`. Returns the slots."""
    rhap_inject.check_target(image)
    if len(booter) > limit:
        raise rhap_inject.SafetyError(
            "booter is %d bytes; boot1 reads only %d" % (len(booter), limit))
    with open(image, "r+b") as f:
        slots = boot_slots(f)
        for off, length in slots:
            if len(booter) > length:
                raise rhap_inject.SafetyError(
                    "booter is %d bytes; the slot at %d holds %d" % (len(booter), off, length))
        for off, length in slots:
            f.seek(off)
            f.write(booter + bytes(length - len(booter)))
        f.flush()
        want = hashlib.sha256(booter).digest()
        for off, length in slots:
            f.seek(off)
            got = f.read(length)
            if hashlib.sha256(got[:len(booter)]).digest() != want or any(got[len(booter):]):
                raise rhap_inject.SafetyError("read-back of the slot at %d differs" % off)
    return slots


def main(argv):
    if len(argv) != 3:
        print("usage: install-booter.py IMAGE BOOTER", file=sys.stderr)
        return 2
    with open(argv[2], "rb") as f:
        booter = f.read()
    try:
        slots = install_booter(argv[1], booter, read_loadsz())
    except (rhap_inject.SafetyError, ValueError) as e:
        print("install-booter: %s" % e, file=sys.stderr)
        return 1
    print("booter %d bytes, sha256 %s" % (len(booter), hashlib.sha256(booter).hexdigest().upper()))
    for off, length in slots:
        print("  written and verified at byte %d (slot %d bytes)" % (off, length))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

- [ ] **Step 8: Run the tests and see them pass**

Run: `$VENVPY -m unittest discover -s vm -p test_install_booter.py -v`

Expected: 7 tests, OK.

Then confirm the slot geometry on the real image, read-only:

```bash
MSYS_NO_PATHCONV=1 $VENVPY -c "import importlib.util as u; s=u.spec_from_file_location('ib','vm/install-booter.py'); m=u.module_from_spec(s); import sys; sys.path.insert(0,'vm'); s.loader.exec_module(m); print(m.boot_slots(open(r'$GOLDEN','rb')))"
```

Expected: `[(32768, 65536), (98304, 65536)]`.

- [ ] **Step 9: Write the failing `install-driver` test**

Create `vm/test_install_driver.py`:

```python
"""Unit tests for install-driver.py's Boot Drivers edit.

Run from the repository root with:
    python -m unittest discover -s vm -p test_install_driver.py -v
"""
import importlib.util
import os
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))


def _load():
    spec = importlib.util.spec_from_file_location(
        "install_driver", os.path.join(_HERE, "install-driver.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


install_driver = _load()


class BootDriversValueTest(unittest.TestCase):
    def test_appends_by_default(self):
        self.assertEqual(install_driver._boot_drivers_value("EISABus PCIBus", "VBE20DisplayDriver"),
                         "EISABus PCIBus VBE20DisplayDriver")

    def test_prepends_when_first(self):
        self.assertEqual(install_driver._boot_drivers_value("EISABus PCIBus", "VBE20DisplayDriver", True),
                         "VBE20DisplayDriver EISABus PCIBus")

    def test_already_listed_is_unchanged(self):
        self.assertIsNone(install_driver._boot_drivers_value("EISABus VBE20DisplayDriver", "VBE20DisplayDriver", True))


if __name__ == "__main__":
    unittest.main()
```

Run: `$VENVPY -m unittest discover -s vm -p test_install_driver.py -v`

Expected: 3 errors, `AttributeError: ... '_boot_drivers_value'`.

- [ ] **Step 10: Add `--first` and replace `cp -c`**

In `vm/install-driver.py`, add before `_add_boot_driver`:

```python
def _boot_drivers_value(current, name, first=False):
    """Return the Boot Drivers value with `name` added -- at the end, or at
    the front when `first` -- or None when `name` is already listed."""
    if name in current.split():
        return None
    return name + " " + current if first else current + " " + name
```

Change `def _add_boot_driver(out_image, name):` to
`def _add_boot_driver(out_image, name, first=False):`, and replace

```python
    current = _current_value(text, key)
    if name in current.split():
        return "unchanged"
    new_value = current + " " + name
```

with

```python
    new_value = _boot_drivers_value(_current_value(text, key), name, first)
    if new_value is None:
        return "unchanged"
```

Change `def install_driver(src_image, driver_dir, out_image):` to take
`first=False`. Replace its `subprocess.check_call(["cp", "-c", src_image,
out_image])` with `shutil.copyfile(src_image, out_image)`, and its last line
with `return _add_boot_driver(out_image, name, first)`. Replace
`import subprocess` with `import shutil`. `subprocess` has no other use in the
file; confirm with `grep -n subprocess vm/install-driver.py`.

`cp -c` is a macOS clone flag, and Git Bash's GNU `cp` rejects it. Spec 2's
gate had to wrap the tool to get past it (`$GATE`, "Procedure").

Replace the top of `main` through the `install_driver` call:

```python
    first = "--first" in argv[1:]
    args = [a for a in argv[1:] if a != "--first"]
    if len(args) != 3:
        print("usage: install-driver.py SRC_IMAGE DRIVER_DIR OUT_IMAGE [--first]",
              file=sys.stderr)
        return 2
    src_image, driver_dir, out_image = args
    try:
        via = install_driver(src_image, driver_dir, out_image, first)
```

- [ ] **Step 11: Run all three test files**

```bash
$VENVPY -m unittest discover -s vm -p test_install_driver.py -v
$VENVPY -m unittest discover -s vm -p test_install_booter.py -v
$VENVPY -m unittest discover -s vm -p test_qemu_shot.py -v
```

Expected: 3, 7 and 15 tests, all OK.

- [ ] **Step 12: Commit**

```bash
git add vm/qemu-shot.py vm/test_qemu_shot.py vm/install-booter.py vm/test_install_booter.py vm/install-driver.py vm/test_install_driver.py
git commit -m "vm: add a boot-area booter writer, VBE capture options and driver link order

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 2: A byte comparator for code without relocations

**Files:**
- Create: `tools/binrecon/compare_flat.py`
- Create: `tools/binrecon/tests/test_compare_flat.py`

**Interfaces:**
- Produces:
  - `compare_flat.compare(ref, ref_base, ref_fn, ours, ours_base, ours_fn, size, ours_size=None, tables=(), ref_window=(0x3000, 0x11000), ours_window=(0x3000, 0x11000)) -> Result`,
    where `Result` has `.match`, `.problems`, `.mapping`, `.compared`, `.masked` and `.instructions`.
  - The CLI `compare_flat.py REF REF_BASE REF_START OURS OURS_BASE OURS_START SIZE [--ours-size N] [--table OFF:COUNT]... [--ref-window LO:HI] [--ours-window LO:HI]`,
    which exits 0 on MATCH and 1 on MISMATCH.

**Why a new tool.** Spec 1's comparator masks relocated operands. Neither the
headerless booter nor a linked kernel has a relocation table. So this one
decodes both slices and masks only operands that behave as addresses: a
32-bit value inside each image's address window, or a branch leaving the
function. A masked address must map consistently everywhere, both ways.

Two things are never masked:
- a 16-bit immediate (VBE function numbers like `0x4F02` are 16-bit);
- a constant outside the window (the `kbs` offsets `0x1858` and `0x1870`).

Both were run against a copy on 2026-09-22: 11 tests passed. A
self-comparison of the 4.2 record writer (`boot+27556`, 148 bytes) gave
MATCH over 50 instructions.

- [ ] **Step 1: Write the failing tests**

Create `tools/binrecon/tests/test_compare_flat.py`:

```python
import compare_flat

BASE = 0x3000
FN = 0x3100


def _image(code, fn=FN, base=BASE):
    """A flat image with `code` at address `fn`, zero-filled around it."""
    return bytes(fn - base) + code + bytes(64)


def _run(ref_code, ours_code, **kw):
    return compare_flat.compare(_image(ref_code), BASE, FN,
                                _image(ours_code), BASE, FN,
                                len(ref_code), **kw)


PROLOGUE = bytes.fromhex("5589e5")          # push ebp; mov ebp,esp
EPILOGUE = bytes.fromhex("c9c3")            # leave; ret


def _push(addr):
    return b"\x68" + addr.to_bytes(4, "little")


def test_identical_code_matches():
    code = PROLOGUE + _push(0x9000) + EPILOGUE
    res = _run(code, code)
    assert res.match, res.problems
    assert res.mapping == {0x9000: 0x9000}


def test_string_address_differing_inside_window_is_masked_and_mapped():
    res = _run(PROLOGUE + _push(0x9000) + EPILOGUE,
               PROLOGUE + _push(0x9400) + EPILOGUE)
    assert res.match, res.problems
    assert res.mapping == {0x9000: 0x9400}
    assert res.masked == 4


def test_constant_outside_window_must_match():
    add_1870 = bytes.fromhex("81c770180000")   # add edi,0x1870
    add_1858 = bytes.fromhex("81c758180000")   # add edi,0x1858
    res = _run(PROLOGUE + add_1870 + EPILOGUE, PROLOGUE + add_1858 + EPILOGUE)
    assert not res.match


def test_external_call_targets_are_mapped():
    def call_to(target):
        # call rel32 at FN+3; next instruction at FN+8
        return b"\xe8" + (target - (FN + 8)).to_bytes(4, "little", signed=True)
    res = _run(PROLOGUE + call_to(0x6000) + EPILOGUE,
               PROLOGUE + call_to(0x7000) + EPILOGUE)
    assert res.match, res.problems
    assert res.mapping == {0x6000: 0x7000}


def test_internal_branch_to_a_different_offset_fails():
    ref = PROLOGUE + bytes.fromhex("7501") + b"\x90" + EPILOGUE    # jne +1
    ours = PROLOGUE + bytes.fromhex("7500") + b"\x90" + EPILOGUE   # jne +0
    assert not _run(ref, ours).match


def test_one_reference_address_mapped_two_ways_fails():
    ref = PROLOGUE + _push(0x9000) + _push(0x9000) + EPILOGUE
    ours = PROLOGUE + _push(0x9400) + _push(0x9800) + EPILOGUE
    res = _run(ref, ours)
    assert not res.match
    assert "elsewhere" in res.problems[0]


def test_sixteen_bit_immediate_is_never_masked():
    # mov word ptr [0x9000], 0x4f02 versus 0x4f01: the disp is an address,
    # the imm16 is a VBE function number and must compare.
    ref = PROLOGUE + bytes.fromhex("66c70500900000024f") + EPILOGUE
    ours = PROLOGUE + bytes.fromhex("66c70500940000014f") + EPILOGUE
    assert not _run(ref, ours).match


def test_jump_table_entries_compare_as_function_offsets():
    body = PROLOGUE + b"\x90" * 5 + EPILOGUE           # 10 bytes
    ref_table = (FN + 3).to_bytes(4, "little") + (FN + 4).to_bytes(4, "little")
    same = _run(body + ref_table, body + ref_table, tables=[(10, 2)])
    assert same.match, same.problems
    moved = (FN + 3).to_bytes(4, "little") + (FN + 5).to_bytes(4, "little")
    assert not _run(body + ref_table, body + moved, tables=[(10, 2)]).match


def test_different_mnemonic_fails():
    ref = PROLOGUE + b"\x90" + EPILOGUE
    ours = PROLOGUE + b"\x40" + EPILOGUE        # inc eax
    assert not _run(ref, ours).match


def test_different_sizes_fail_even_when_the_prefix_matches():
    code = PROLOGUE + EPILOGUE
    res = compare_flat.compare(_image(code), BASE, FN, _image(code), BASE, FN,
                               len(code), ours_size=len(code) + 1)
    assert not res.match


def test_cli_exit_status(tmp_path):
    ref = tmp_path / "ref.bin"
    ours = tmp_path / "ours.bin"
    ref.write_bytes(_image(PROLOGUE + _push(0x9000) + EPILOGUE))
    ours.write_bytes(_image(PROLOGUE + _push(0x9400) + EPILOGUE))
    args = [str(ref), "0x3000", "0x3100", str(ours), "0x3000", "0x3100", "10"]
    assert compare_flat.main(args) == 0
    ours.write_bytes(_image(PROLOGUE + bytes.fromhex("81c770180000")[:5] + EPILOGUE))
    assert compare_flat.main(args) == 1
```

- [ ] **Step 2: Run them and see them fail**

Run: `PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests/test_compare_flat.py -q`

Expected: collection error, `ModuleNotFoundError: No module named 'compare_flat'`.

- [ ] **Step 3: Write `tools/binrecon/compare_flat.py`**

```python
"""Compare one i386 function between two flat images, masking only addresses.

Byte parity for code with no relocation table -- the headerless 4.2 booter,
or a fully linked MH_EXECUTE kernel -- cannot mask by relocation. This tool
decodes both slices with capstone and requires the two instruction streams to
agree exactly, with three allowances:

- a 32-bit displacement or immediate whose two values differ is masked only
  when each value lies inside its own image's address window;
- a relative branch or call leaving the function is masked the same way, by
  its absolute target;
- a relative branch staying inside the function must land at the same
  function-relative offset in both.

Every masked reference address must map to one rebuilt address throughout,
and vice versa, or the comparison fails. An inline jump table (--table) is
compared entry by entry as function-relative offsets.

Usage:
  compare_flat.py REF REF_BASE REF_START OURS OURS_BASE OURS_START SIZE
                  [--ours-size N] [--table OFF:COUNT]...
                  [--ref-window LO:HI] [--ours-window LO:HI]

BASE is the address of the file's first byte. Numbers accept a 0x prefix.
Exit status: 0 MATCH, 1 MISMATCH, 2 usage error.
"""
import argparse
import sys

import capstone

BOOTER_WINDOW = (0x3000, 0x11000)


class Result(object):
    def __init__(self):
        self.problems = []
        self.mapping = {}
        self.reverse = {}
        self.compared = 0
        self.masked = 0
        self.instructions = 0

    @property
    def match(self):
        return not self.problems

    def fail(self, message):
        self.problems.append(message)

    def map_address(self, ref, ours, where):
        if self.mapping.setdefault(ref, ours) != ours:
            self.fail("%s: 0x%x maps to 0x%x here but 0x%x elsewhere"
                      % (where, ref, ours, self.mapping[ref]))
        elif self.reverse.setdefault(ours, ref) != ref:
            self.fail("%s: rebuilt 0x%x is 0x%x here but 0x%x elsewhere"
                      % (where, ours, ref, self.reverse[ours]))


def _inside(value, window):
    return window[0] <= value < window[1]


def _decode(code, address):
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
    md.detail = True
    return list(md.disasm(code, address))


def _regions(size, tables):
    """Split [0, size) into code regions around the jump tables."""
    edges = sorted((off, off + 4 * count) for off, count in tables)
    regions, pos = [], 0
    for lo, hi in edges:
        if lo > pos:
            regions.append((pos, lo))
        pos = hi
    if pos < size:
        regions.append((pos, size))
    return regions


def _compare_insn(r, o, ref_fn, ours_fn, size, windows, res):
    where = "+%d" % (r.address - ref_fn)
    rb, ob = bytes(r.bytes), bytes(o.bytes)
    if r.size != o.size or r.mnemonic != o.mnemonic:
        res.fail("%s: %s %s | %s %s" % (where, r.mnemonic, r.op_str, o.mnemonic, o.op_str))
        return
    masked = set()
    groups = set(r.groups)
    if capstone.CS_GRP_BRANCH_RELATIVE in groups:
        tr, to = r.operands[0].imm, o.operands[0].imm
        in_r = ref_fn <= tr < ref_fn + size
        in_o = ours_fn <= to < ours_fn + size
        if in_r and in_o:
            if tr - ref_fn != to - ours_fn:
                res.fail("%s: branch to +%d | +%d" % (where, tr - ref_fn, to - ours_fn))
        elif _inside(tr, windows[0]) and _inside(to, windows[1]):
            res.map_address(tr, to, where)
        else:
            res.fail("%s: branch target 0x%x | 0x%x" % (where, tr, to))
        masked.update(range(r.imm_offset, r.imm_offset + r.imm_size))
    else:
        for off, width in ((r.disp_offset, r.disp_size), (r.imm_offset, r.imm_size)):
            if width != 4:
                continue
            vr = int.from_bytes(rb[off:off + 4], "little")
            vo = int.from_bytes(ob[off:off + 4], "little")
            if _inside(vr, windows[0]) and _inside(vo, windows[1]):
                res.map_address(vr, vo, where)
                masked.update(range(off, off + 4))
    for i in range(r.size):
        if i in masked:
            res.masked += 1
        elif rb[i] != ob[i]:
            res.fail("%s: byte %d differs in %s %s | %s %s"
                     % (where, i, r.mnemonic, r.op_str, o.mnemonic, o.op_str))
            return
        else:
            res.compared += 1


def compare(ref, ref_base, ref_fn, ours, ours_base, ours_fn, size,
            ours_size=None, tables=(), ref_window=BOOTER_WINDOW,
            ours_window=BOOTER_WINDOW):
    res = Result()
    if ours_size is not None and ours_size != size:
        res.fail("size %d | %d" % (size, ours_size))
    ref_code = ref[ref_fn - ref_base:ref_fn - ref_base + size]
    ours_code = ours[ours_fn - ours_base:ours_fn - ours_base + size]
    if len(ref_code) != size or len(ours_code) != size:
        res.fail("function runs past the end of an image")
        return res
    windows = (ref_window, ours_window)

    for off, count in tables:
        for k in range(count):
            at = off + 4 * k
            er = int.from_bytes(ref_code[at:at + 4], "little") - ref_fn
            eo = int.from_bytes(ours_code[at:at + 4], "little") - ours_fn
            if er != eo or not 0 <= er < size:
                res.fail("+%d: table entry %d is +%d | +%d" % (at, k, er, eo))
            res.masked += 4

    for lo, hi in _regions(size, tables):
        ri = _decode(ref_code[lo:hi], ref_fn + lo)
        oi = _decode(ours_code[lo:hi], ours_fn + lo)
        for insns, fn, label in ((ri, ref_fn, "reference"), (oi, ours_fn, "rebuilt")):
            covered = sum(i.size for i in insns)
            if covered != hi - lo:
                res.fail("%s does not decode at +%d" % (label, lo + covered))
        for r, o in zip(ri, oi):
            res.instructions += 1
            _compare_insn(r, o, ref_fn, ours_fn, size, windows, res)
            if not res.match:
                return res
        if len(ri) != len(oi):
            res.fail("+%d..+%d: %d instructions | %d" % (lo, hi, len(ri), len(oi)))
    return res


def _number(text):
    return int(text, 0)


def _pair(text):
    a, b = text.split(":")
    return _number(a), _number(b)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("ref")
    p.add_argument("ref_base", type=_number)
    p.add_argument("ref_start", type=_number)
    p.add_argument("ours")
    p.add_argument("ours_base", type=_number)
    p.add_argument("ours_start", type=_number)
    p.add_argument("size", type=_number)
    p.add_argument("--ours-size", type=_number)
    p.add_argument("--table", type=_pair, action="append", default=[])
    p.add_argument("--ref-window", type=_pair, default=BOOTER_WINDOW)
    p.add_argument("--ours-window", type=_pair, default=BOOTER_WINDOW)
    a = p.parse_args(argv)
    with open(a.ref, "rb") as f:
        ref = f.read()
    with open(a.ours, "rb") as f:
        ours = f.read()
    res = compare(ref, a.ref_base, a.ref_start, ours, a.ours_base, a.ours_start,
                  a.size, a.ours_size, a.table, a.ref_window, a.ours_window)
    for problem in res.problems:
        print("MISMATCH %s" % problem)
    for ref_addr in sorted(res.mapping):
        print("map 0x%x -> 0x%x" % (ref_addr, res.mapping[ref_addr]))
    print("%s: %d instructions, %d bytes compared, %d masked, %d addresses mapped"
          % ("MATCH" if res.match else "MISMATCH", res.instructions,
             res.compared, res.masked, len(res.mapping)))
    return 0 if res.match else 1


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run the tests and see them pass**

Run: `PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests/test_compare_flat.py -q`

Expected: `11 passed`.

- [ ] **Step 5: Check it on real reference code**

This needs `$BREF`. If Task 3 has not staged it yet, stage it now; Task 3
Step 1 gives the command. Then:

```bash
PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/compare_flat.py "$BREF" 0x3000 0x9BA4 "$BREF" 0x3000 0x9BA4 148
```

Expected: `MATCH: 50 instructions, 148 bytes compared, 0 masked, 0 addresses mapped`.

- [ ] **Step 6: Commit**

```bash
git add tools/binrecon/compare_flat.py tools/binrecon/tests/test_compare_flat.py
git commit -m "binrecon: compare a function across two flat i386 images, masking only addresses

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 3: Measure

**Files:**
- Create: `$BDIV`
- Modify: `$KDIV`: add a section, "Spec 3: the frame-buffer mapping".
- Modify: `docs/superpowers/specs/2026-09-22-i386-vbe-booter-support-design.md`:
  §6 gets the boot-area facts "Measured during planning", above.

**Interfaces:**
- Consumes: the Task 1 tools and Task 2's comparator.
- Produces:
  - **The function inventory.** For each 4.2 VBE function: its extent
    (`boot+start..end`), its size, its role, its counterpart in our tree
    (file:line, or "new"), and whether its 32-bit operands can be masked by
    Task 2's windows.
  - **The byte budget**, and a ranked list of trim candidates.
  - **The QEMU adapter for G2.**
  - **The kernel mapping's shape.**
  - Answers to spec §4.2 items 1-10, each tagged `[measured]` or
    `[inference]`.

- [ ] **Step 1: Stage the 4.2 booter**

```bash
MSYS_NO_PATHCONV=1 $VENVPY vm/extract-os42-patch.py "$PATCH" C:/Users/raynorpat/Downloads/test/OS42/bootx ./usr/standalone/i386/boot
mv C:/Users/raynorpat/Downloads/test/OS42/bootx/boot "$BREF" && rmdir C:/Users/raynorpat/Downloads/test/OS42/bootx
sha256sum "$BREF"
```

Expected: 44,848 bytes, SHA-256 `$BREFSHA`. **If it differs, stop and
report.**

- [ ] **Step 2: Build our booter as it stands, keeping its symbols**

Write a guest script, `/tmp/t3-boot.sh` in content, and run it as Global
Constraints describe. It must:

1. `touch /tmp/t3-stamp`;
2. run
   `rbuild buildpackage --state /build/state --arch i386 --dir --target all /build/src/boot-2 /build/repo /tmp/t3-boot-dst > /tmp/t3-boot.log 2>&1; echo RC=$?`;
3. print the log's last 60 lines, including the Makefile's
   `booter N bytes of 45056, M to spare` line;
4. `find / -xdev -newer /tmp/t3-stamp \( -name boot.sys -o -name boot -o -name '*.o' -o -name 'libsaio.a' -o -name 'libsa.a' \) -type f`,
   to locate `SYMROOT` and `OBJROOT`;
5. `nm -n <boot.sys>`, then `size` on every `.o` and on each `.a`'s members;
6. `uuencode` both `boot` and `boot.sys`, with `sum` and `cksum` for each.

Sync first: `vm/sync-src.ps1 -Path boot-2`.

Decode and verify locally. Record the size (expected 44,576, per
`docs/boot/sarld-driver-link-limit.md`), both SHA-256s, and the symbol table.
**If the build fails, stop and report. Do not fall back to `gnumake`.**

- [ ] **Step 3: Prove the boot-area writer and our booter on a real boot**

1. Graft nothing: this boot uses the image's own kernel.
2. `cp "$GOLDEN" vm/work/test.img`.
3. `install-booter.py vm/work/test.img <our boot>`.
4. `qemu-shot.py vm/work/test.img vm/shots-t3-ours --at 5,15,30,60 --keys $'mach_kernel -v\n' --keys-at 8`.
5. Then the stock control, on a fresh copy of `$GOLDEN` with no
   `install-booter`: `vm/shots-t3-stock`.

**Pass:**
- The `5s` frame of `shots-t3-ours` shows our banner (`Rhapsody boot v...`
  from `boot2/prompt.c:31`) and differs from the stock one. Record both banner
  lines exactly. This is the "which booter ran" proof that Task 9 relies on.
- Both boots reach the same last serial line. Our booter reaching userland is
  documented in `docs/boot/sarld-driver-link-limit.md`.

If ours does not boot, stop and report. Nothing later can run.

- [ ] **Step 4: Inventory 4.2's VBE functions (items 1, 4, 5, 8)**

Disassemble `$BREF` at base `0x3000` with capstone, or IDA as a binary file
at `0x3000`. Start from the string operands in spec §4.1 and the record writer
at `boot+27556`. For each function reached, record the table row described
under **Produces**. Specifically:

- **Item 4:** find which table the `VBE Mode` lookup reads (operands at
  `boot+0x3D6`, `0x403`). Trace which `getStringForKey`-family call receives
  it, and against which table. Our equivalents live in
  `src/boot-2/i386/libsaio/stringTable.c`.
- **Item 5:** find the `VESAVersion` test before `VESA not available.\n`
  (operand at `boot+0x6DB0`), and give its exact comparison.
- **Item 8:** after the enumerator's loop (`boot+27704..28030`), check
  whether a zero record is written after the last one.
- List every store through the `0xDA7C` pointer, and which `kbs` offset each
  hits. Spec 1's record shows `+0x1858` and `+0x1870`. Confirm there are no
  others, and **name any other you find**.

- [ ] **Step 5: The budget (item 2)**

For each function to reconstruct:
- the reference size;
- our counterpart's size, from Step 2's `nm -n` deltas;
- the net growth, which is the reference size minus the counterpart's, or the
  reference size if new.

Byte parity means our build will be the reference's size, so the reference
sizes are the budget. Sum the growth and compare it with Step 2's spare bytes.
Record the arithmetic.

- [ ] **Step 6: Where the 5 KB comes from (item 3)**

Apple's stock booter is 39,616 bytes; ours is about 44,576. Using Step 2's
per-object sizes:

1. List our booter's functions and strings.
2. Find which of them appear in the stock booter, by distinctive strings and
   by call structure. Pull the stock booter out of `$GOLDEN` with
   `$VENVPY vm/rhap_image.py`.
3. Compare the build flags (`boot2/Makefile:5-7`, `-O2 -g`) with what the
   stock booter's code suggests.

Produce a ranked candidate list. For each: the bytes, why nothing needs it
(for example, never called, or only under a `#if` that is off), and how that
was established. **This list is input to Task 5, not a decision.** Mark each
reason `[measured]` or `[inference]`.

- [ ] **Step 7: The booter under QEMU (items 6, 7, 10)**

> **This step needs the user's approval, obtained by the controller before
> Task 3 is dispatched and passed to the implementer as a plain yes or no.**
> It boots Apple's 4.2 booter binary, `$BREF`, under QEMU. An earlier request
> to run Apple's reference driver binary was declined at the permission
> prompt, so do not assume this one is approved. If the answer is no, or the
> implementer was not told, skip to "Without the reference boot" below.

With approval, for `--vga cirrus` and `--vga std`:
1. Build a fresh `test.img` from `$GOLDEN`, install the driver (for its
   `VBE Mode` key) and then `install-booter.py vm/work/test.img "$BREF"`.
2. At the booter's prompt, type the 4.2 `VBE Check` interaction. Its exact
   form comes from Step 4's reading of `boot+0xA15`.
3. Capture the `Usable VBE modes:` listing, and any VESA error.
4. Boot once with `-v` and once without. Use `--pmemsave 20:0x11000:0x2200`
   to see what the booter left at `kbs`.

The 4.2 booter is not expected to start our kernel: its `KERNBOOTSTRUCT`
differs. Record what it prints, not whether it boots.

**Without the reference boot:**
- Record items 6, 7 and 10 as `[inference]` from the disassembly.
- Item 6 (QEMU's VBE version and modes) is then measured in Task 7 Step 5,
  by our own reconstructed `VBE Check`, before any gate relies on it.

- [ ] **Step 8: The kernel mapping**

In `$KREF`, read `pmap_bootstrap` around `0x0018F1B4`
(`mov ds:[0x12854],ecx`), and record:
- where `ecx` comes from;
- which physical address and length are mapped, from which `kbs` fields;
- the mapping primitive it calls, with its arguments;
- the guard when `xResolution` is 0.

Then find the matching point in our
`src/kernel-7/machdep/i386/pmap.c:347` `pmap_bootstrap`, and the primitive our
tree offers for the same job. **This closes spec 2's D2 inference, or corrects
it.** Say which, in both `$KDIV` and `$BDIV`.

- [ ] **Step 9: Frame-buffer console depths (item 9)**

From `src/kernel-7/bsd/dev/i386/FBConsole.c`, list which `bitsPerPixel` values
`FBAllocateConsole` and its drawing code handle. Pick G2's mode: the first
mode in Step 7's listing, or Task 7's, that both the console and QEMU support.
Prefer 257 (640x480, 8-bit), which the driver's `Default.table` already sets.

- [ ] **Step 10: Write the records**

Create `$BDIV` with a **Conventions** header, a **Staging** section and a
**Task 3** section holding Steps 1-9. Follow `$KDIV`'s conventions:
`[measured]` and `[inference]` on the line, and `boot+N` file offsets.

Append the kernel half to `$KDIV`. Add the planning-time boot-area facts to
spec §6.

- [ ] **Step 11: The stop gate**

If Step 5's growth exceeds Step 2's spare plus the Step 6 candidates that
Task 5 could remove with a `[measured]` reason, **stop and report to the
user** (spec §4.4). Otherwise continue.

- [ ] **Step 12: Commit**

```bash
git add "$BDIV" "$KDIV" docs/superpowers/specs/2026-09-22-i386-vbe-booter-support-design.md
git commit -m "boot: measure the 4.2 booter's VBE code, the size budget and the kernel mapping

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 4: Name the VBE fields in `KERNBOOTSTRUCT`

**Files:**
- Modify: `src/boot-2/i386/libsa/kernBootStruct.h`
- Modify: `src/kernel-7/machdep/i386/kernBootStruct.h`: the **live** struct
  after `#else` (around line 179), not the dead `#if 0` one.

**Interfaces:**
- Produces: `struct boot_vbe_mode` / `boot_vbe_mode` (24 bytes), and
  `KERNBOOTSTRUCT` members `vbeFrameBuffer`, `vbeCurrentMode` and
  `vbeModes[BOOT_VBE_MAX_MODES]`, with `BOOT_VBE_MAX_MODES == 89`.
  Tasks 6-8 write through these names.

- [ ] **Step 1: Write the probe that must fail first**

Create a throwaway, `/tmp/t4-probe.c` on the guest:

```c
#include <stdio.h>
#include "kernBootStruct.h"
#define OFF(f) ((unsigned long)&((KERNBOOTSTRUCT *)0)->f)
int main(void)
{
    printf("vbeFrameBuffer %lu vbeCurrentMode %lu vbeModes %lu video %lu sizeof %lu\n",
           OFF(vbeFrameBuffer), OFF(vbeCurrentMode), OFF(vbeModes), OFF(video),
           (unsigned long)sizeof(KERNBOOTSTRUCT));
    return 0;
}
```

Compile it against the booter header:
`cc -arch i386 -I/build/src/boot-2/i386/libsa -I/build/src/boot-2/i386/libsaio -o /tmp/t4-probe /tmp/t4-probe.c`.

Expected now: a compile error naming `vbeFrameBuffer`. Also record `OFF(video)`
and `sizeof` from a variant with only those two fields printed, plus
`OFF(_reserved)`. Those are the invariants.

Confirm nothing else uses `_reserved` before carving it:

```bash
grep -rn "_reserved\b" --include=*.c --include=*.m --include=*.h src/boot-2/i386 src/kernel-7/machdep/i386 src/kernel-7/bsd/dev/i386
```

Expected: the two live declarations, the kernel header's dead `#if 0` one, and
at most a `sizeof` print in `src/boot-2/i386/boot2/test.c`. **Anything else
reading or writing `_reserved` makes the carve-out unsafe: stop and report.**

- [ ] **Step 2: Add the type and the fields to the booter header**

Above the `typedef struct { short version; ...` in
`src/boot-2/i386/libsa/kernBootStruct.h`:

```c
/*
 * One VBE mode as OPENSTEP 4.2 User Patch 4 recorded it for the kernel and
 * the VBE20DisplayDriver. 24 bytes; 0x12-0x13 are padding. The layout is
 * spec 1's, confirmed by the driver's type encoding and by the kernel's
 * VBEModeInfo2IODisplayInfo (0x0019ED8C in the 4.2 kernel).
 */
struct boot_vbe_mode {
	unsigned short	modeNumber;		/* 0x00 */
	unsigned short	modeAttributes;		/* 0x02 */
	unsigned short	xResolution;		/* 0x04 */
	unsigned short	yResolution;		/* 0x06 */
	unsigned short	bytesPerScanline;	/* 0x08 */
	unsigned char	bitsPerPixel;		/* 0x0A */
	unsigned char	memoryModel;		/* 0x0B */
	unsigned char	redMaskSize;		/* 0x0C */
	unsigned char	redFieldPosition;	/* 0x0D */
	unsigned char	greenMaskSize;		/* 0x0E */
	unsigned char	greenFieldPosition;	/* 0x0F */
	unsigned char	blueMaskSize;		/* 0x10 */
	unsigned char	blueFieldPosition;	/* 0x11 */
	unsigned long	frameBuffer;		/* 0x14, physical */
};

typedef struct boot_vbe_mode boot_vbe_mode;

/*
 * 4.2 allowed 90 records (0x880 bytes from 0x1870). In this struct the 90th
 * would overwrite `video`, so the booter stops at 89 and leaves the 90th
 * slot's xResolution zero for the driver's scan to stop on.
 */
#define BOOT_VBE_MAX_MODES	89
```

Replace `char   _reserved[7500];` with:

```c
    char   _reserved[5320];		// 908 .. 6228

    /*
     * VBE hand-off, at OPENSTEP 4.2 User Patch 4's offsets. The driver and
     * the kernel address these as bare constants, because the 4.2 binaries
     * do: VBE20DisplayDriver.m's VBE_BOOTER_MODE (0x12858) and
     * VBE_BOOTER_MODES (0x12870), FBConsole.c's VBE_BOOTER_MODE and
     * VBE_FRAMEBUFFER_VIRT (0x12854). The assertions below keep these
     * members on those addresses.
     */
    unsigned long	vbeFrameBuffer;		// 0x1854: kernel virtual, pmap_bootstrap
    boot_vbe_mode	vbeCurrentMode;		// 0x1858: the mode the booter set
    boot_vbe_mode	vbeModes[BOOT_VBE_MAX_MODES];	// 0x1870
    char   _reserved2[16];		// 8392 .. 8408, keeps `video` at 8408
```

After `} KERNBOOTSTRUCT;` add:

```c
#define __KBS_OFF(f)	((unsigned long)&((KERNBOOTSTRUCT *)0)->f)
typedef char __kbs_vbe_mode_size[(sizeof (boot_vbe_mode) == 24) ? 1 : -1];
typedef char __kbs_vbe_fb[(__KBS_OFF(vbeFrameBuffer) == 0x1854) ? 1 : -1];
typedef char __kbs_vbe_current[(__KBS_OFF(vbeCurrentMode) == 0x1858) ? 1 : -1];
typedef char __kbs_vbe_modes[(__KBS_OFF(vbeModes) == 0x1870) ? 1 : -1];
typedef char __kbs_video[(__KBS_OFF(video) == 8408) ? 1 : -1];
```

`5320` is `0x1854 - 908`. `908` is `_reserved`'s offset, measured on the guest
in spec 1 §3. Step 1 re-measures it. **If Step 1 printed anything other than
908 for the old `_reserved`, recompute `5320` from it.** The `video`
assertion is what catches a wrong number.

- [ ] **Step 3: Mirror into the kernel header**

Apply the same three edits to `src/kernel-7/machdep/i386/kernBootStruct.h`:
the type block, the replacement of `_reserved[7500]` and the assertions. Do
not touch the dead `#if 0` struct. Then:

```bash
diff <(sed -n '/^struct boot_vbe_mode/,/BOOT_VBE_MAX_MODES\t89/p' src/boot-2/i386/libsa/kernBootStruct.h) \
     <(sed -n '/^struct boot_vbe_mode/,/BOOT_VBE_MAX_MODES\t89/p' src/kernel-7/machdep/i386/kernBootStruct.h)
diff <(sed -n '/_reserved\[5320\]/,/__kbs_video/p' src/boot-2/i386/libsa/kernBootStruct.h) \
     <(sed -n '/_reserved\[5320\]/,/__kbs_video/p' src/kernel-7/machdep/i386/kernBootStruct.h)
```

Expected: no output from either.

- [ ] **Step 4: Run the probe and see it pass**

On the guest, after `vm/sync-src.ps1 -Path boot-2` and
`vm/sync-src.ps1 -Path kernel-7`, compile the probe once against each header.
The kernel's needs its include path: the same `-I` pattern pointing at
`/build/src/kernel-7/machdep/i386`.

Expected, both times:
`vbeFrameBuffer 6228 vbeCurrentMode 6232 vbeModes 6256 video 8408 sizeof <Step 1's value>`.

Then show the assertions bite. Change one `0x1870` to `0x1871` in a `/tmp`
copy of the header, and confirm the compile fails with a negative-size-array
error.

The assertions rely on GCC folding `(unsigned long)&((T *)0)->f` to a
constant, which is how old `offsetof` was spelled. **If the guest compiler
rejects it as non-constant, stop and report. Do not drop the assertions:**
they are what keeps the driver's and the kernel's bare constants on these
fields.

- [ ] **Step 5: Rebuild the booter and compare it with Task 3's**

Rebuild with Task 3 Step 2's script, renamed to `t4`. The header change moves
no code, so `boot` must be **byte-identical** to Task 3's. If it is not, find
out why before continuing: the build stamp in `vers.h`, or a real layout
change.

- [ ] **Step 6: Commit**

```bash
git add src/boot-2/i386/libsa/kernBootStruct.h src/kernel-7/machdep/i386/kernBootStruct.h
git commit -m "boot: name the VBE hand-off fields in KERNBOOTSTRUCT at 4.2's offsets

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

The file touches both projects. `boot:` leads because the booter owns the
hand-off.

---

## Task 5: Make room in `boot2`

**Files:**
- Modify: whatever Task 3 Step 6's accepted candidates name, under `src/boot-2/i386/`
- Modify: `$BDIV`: a "Task 5: the trim" section

**Interfaces:**
- Consumes: Task 3's budget and candidate list.
- Produces: a `boot2` whose spare bytes are at least Task 3's budget plus 256
  bytes of margin, with unchanged behaviour.

- [ ] **Step 1: Choose from the list, in order**

Take candidates from Task 3 Step 6 in rank order until the spare bytes cover
the budget plus 256. **Only `[measured]` candidates.** An `[inference]`
candidate needs its reason measured first, for example by showing a function
has no caller in `nm` and no address taken.

**Never remove anything a later task reconstructs**, and never remove
anything that runs on today's boot path.

- [ ] **Step 2: Remove, one candidate per edit**

For each, record in `$BDIV`: what was removed (file:line), its size, and the
evidence nothing needs it.

- [ ] **Step 3: Build and read the size line**

Build as in Task 3 Step 2, as `t5`. Expected: `booter N bytes of 45056, M to
spare`, with `M >= budget + 256`.

**If the candidates run out first, stop and report to the user.** Do not
reach for `[inference]` candidates, and do not change `boot1`.

- [ ] **Step 4: Prove behaviour is unchanged**

Run a same-session A-B-A on the verbose path, with the stock kernel:
- **A** is Task 3's booter;
- **B** is the trimmed booter.

Apply the comparison rules. Expected: serial identical except line 4, and
frames identical. The banner is the same build, so it matches too.

- [ ] **Step 5: Commit**

```bash
git add <each changed file by name> "$BDIV"
git commit -m "boot: remove <what> to make room for the VBE code

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Name what was removed in the subject, for example "unused scrollbar code".

---

## Task 6: Reconstruct 4.2's VBE functions in `libsaio`

**Files:**
- Modify: `src/boot-2/i386/libsaio/vbe.c`, `src/boot-2/i386/libsaio/vbe.h`
- Modify: `src/boot-2/i386/libsaio/saio_internal.h`, for any prototype whose
  signature changes
- Modify: `$BDIV`: "Task 6"

**Interfaces:**
- Consumes: Task 3's inventory rows for the `boot+0x6B00..0x6F00` region, and
  Task 4's `boot_vbe_mode`, `vbeCurrentMode`, `vbeModes` and
  `BOOT_VBE_MAX_MODES`.
- Produces: the record writer, the mode enumerator and the mode setter, under
  the names and signatures Task 3 recorded. Task 7 calls them.
  `set_linear_video_mode()`'s `void` return is loader problem 3. If 4.2's
  setter returns a status, ours does too.

The procedure per function is the same one spec 2 used. Do the record writer
first: it is a leaf, 147 bytes, fully read in spec 1's record, and it proves
the build-and-compare loop.

- [ ] **Step 1: Read the reference function**

From `$BREF`, disassemble the function's full extent as Task 3 recorded it.

- [ ] **Step 2: Write the C**

Put it in `vbe.c`, in 4.2's order where Task 3 found it.
- Record defects verbatim, with a comment on the line.
- The current record goes through `&kernBootStruct->vbeCurrentMode`, and the
  array through `kernBootStruct->vbeModes`.
- Keep the names our tree already uses where a function has a counterpart,
  unless 4.2's call structure forces otherwise. **Say which applies in
  `$BDIV`.**

- [ ] **Step 3: Build**

Build as in Task 3 Step 2, as `t6`, pulling `boot` and `boot.sys`. Take the
new function's address and size from `nm -n boot.sys`: the next symbol's
address minus this one's.

- [ ] **Step 4: Compare**

```bash
PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/compare_flat.py "$BREF" 0x3000 <ref address> <our boot> 0x3000 <our address> <ref size> --ours-size <our size>
```

Add `--table OFF:COUNT` for any inline jump table Task 3 found.

Expected: MATCH. Otherwise record one outcome in `$BDIV`:
- **Structural parity:** same operations in the same order. Give the exact
  count of unmatched bytes and the instruction-level reason, such as
  register allocation, a different libsa helper, or a stack-frame size.
- **Forced divergence:** say what behaviour differs and why.

**Never mark a function matched with an unexplained byte.**

- [ ] **Step 5: Apply the forced divergences**

These are expected, per spec §4.3:
- **The 89-record cap.** 4.2's enumerator bound is `cmp eax, 897h` at
  `boot+27911`, relative to `base + 0x1840`, so 4.2 stops after index 89.
  Change only that constant, so the enumerator writes at most 89 records
  (indices 0-88). Derive the constant, show the arithmetic in `$BDIV`, and
  label it in source as a forced divergence, citing the `video` overlap.
- **The version check, if Task 3 item 5 made it one.** Label it the same way.

With these in, the comparison reports exactly these differences. Record the
byte count.

- [ ] **Step 6: Commit per function or per closely related pair**

```bash
git add src/boot-2/i386/libsaio/vbe.c src/boot-2/i386/libsaio/vbe.h "$BDIV"
git commit -m "boot: add 4.2's VBE mode record writer

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Keep each build under the size limit as you go. The Makefile check fails the
build otherwise.

---

## Task 7: Wire the VBE path into the boot flow

**Files:**
- Modify: `src/boot-2/i386/boot2/boot.c`, `src/boot-2/i386/boot2/graphics.c`,
  `src/boot-2/i386/boot2/boot.h` (the dead `G_MODE_KEY`)
- Modify: `$BDIV`: "Task 7"

**Interfaces:**
- Consumes: Task 6's functions; Task 3's rows for the region near the image's
  top: the `VBE Mode` key, `VBE Check`, the adapter warning and `Boot Graphics`.
- Produces: a booter that, with a `VBE Mode` key present:
  - sets the mode;
  - fills `vbeCurrentMode` and `vbeModes`;
  - enters graphics.

  Without a key, it behaves as Task 5's booter did.

- [ ] **Step 1: Reconstruct the boot-flow functions**

Use Task 6's procedure: read, write, build, compare, record. These include:
- where `VBE Mode` is read;
- the `VBE Check` interaction that prints `Usable VBE modes:`
  (`boot+2652..2857` only reads the array);
- the adapter warning;
- the graphics-mode entry that replaces `setMode()`'s dead `"Graphics Mode"`
  branch (`graphics.c:189-208`).

Remove that branch's `kernBootStruct->video` stores with it (spec §4.3).
`G_MODE_KEY` goes when nothing uses it. Check with
`grep -rn G_MODE_KEY src/boot-2`.

Our `setMode()` has no non-VBE graphics mode (`graphics.c:209-211`). What 4.2
does after `Reverting to VGA` is Task 3 item 10. Reproduce that, and if it
needs something our booter lacks, record it as a divergence rather than
inventing it.

- [ ] **Step 2: Check the write order**

Show with `nm` or the disassembly that every store into `vbeCurrentMode` and
`vbeModes` runs after `getKernBootStruct()`. Record the call path in `$BDIV`.

- [ ] **Step 3: Build and read the size line**

Build as `t7`. Expected: under 45,056, and the size line recorded.

- [ ] **Step 4: Boot the VBE path with spec 2's kernel**

Build `test.img` from `$GOLDEN`:
1. graft `$KSPEC2` (check `$KSPEC2SHA`);
2. install `$DRV` (check `DRVSHA` on the installed `_reloc`);
3. `install-booter.py` Task 7's `boot`.

Boot on Task 3's adapter:

```bash
MSYS_NO_PATHCONV=1 $VENVPY vm/qemu-shot.py vm/work/test.img vm/shots-t7-vbe --vga <adapter> --at 5,15,30,60,95 --pmemsave 30:0x11000:0x2200
```

This sends no keys, so the boot takes the default graphics-mode path. If
Task 3 item 7 found that 4.2 also enters VBE on a verbose boot, run a second
capture with `--keys $'mach_kernel -v\n' --keys-at 8` as well.

The dump starts at `kbs` (`0x11000`), so a dump offset is a `kbs` offset.

Pass when all of these hold:
- The booter prints `Using VBE Mode <N>.`
- In the dump:
  - `vbeCurrentMode` (offset 6232) names N, with a non-zero `xResolution`;
  - `vbeModes` holds 1 to 89 records, and the next record's `xResolution` is
    zero;
  - bytes 8408..8431 (`video`) are all zero;
  - `vbeFrameBuffer` (6228) is zero, because spec 2's kernel has no producer.
- Serial shows the driver's `using VBE mode <N>` line and one
  `VBE mode ... is width=` line per record.
- The kernel console is still VGA. `FBAllocateVBEConsole` still returns NULL,
  because nothing writes `0x12854` yet.

- [ ] **Step 5: Item 6, if Task 3 Step 7 was skipped**

Run our `VBE Check` on `--vga cirrus` and `--vga std`. Record QEMU's VBE
version and mode list in `$BDIV`, and settle G2's adapter.

- [ ] **Step 6: Commit**

```bash
git add src/boot-2/i386/boot2/boot.c src/boot-2/i386/boot2/graphics.c src/boot-2/i386/boot2/boot.h "$BDIV"
git commit -m "boot: set the VBE mode from the VBE Mode key and hand it to the kernel

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 8: Map the frame buffer in `pmap_bootstrap`

**Files:**
- Modify: `src/kernel-7/machdep/i386/pmap.c`
- Modify: `src/kernel-7/bsd/dev/i386/FBConsole.c`, **comments only**. The
  block above `VBE_BOOTER_MODE` / `VBE_FRAMEBUFFER_VIRT` (around lines
  1482-1511) still says nothing writes `0x12854` and that the producer
  arrives with spec 3.
- Modify: `$KDIV`: "Spec 3 Task 8"

**Interfaces:**
- Consumes: Task 3 Step 8's reading; Task 4's `vbeFrameBuffer` and
  `vbeCurrentMode`.
- Produces: `KERNSTRUCT_ADDR->vbeFrameBuffer` holds the kernel virtual address
  of the mapped linear frame buffer when `vbeCurrentMode.xResolution != 0`,
  and 0 otherwise.

- [ ] **Step 1: Write the mapping**

Write it in `pmap_bootstrap`, at the point Task 3 identified, using the
primitive Task 3 named. Mirror 4.2's physical address, length and guard.
**Mapping nothing when `xResolution` is zero is required** (spec §5), whatever
4.2 does.

Rewrite the `FBConsole.c` comment block to say:
- where the producer is now (`pmap.c:<line>`);
- that the D2 reading is now confirmed or corrected (Task 3 Step 8);
- that the stock v5.0.41.1 booter's zeroing code was not read, only its
  strings were scanned. That corrects the one remaining Minor from spec 2's
  final review, which said the booter "was not read" at all.

- [ ] **Step 2: Build the kernel**

```sh
sed -e 's|^path=.*|path=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin|' \
    /build/src/rbuild-1/toolchains/gcc-darwin.conf > /tmp/t8-gcc-darwin.conf
rbuild kernel --state /build/state --toolchain /tmp/t8-gcc-darwin.conf \
  --arch i386 /build/src /build/repo /tmp/t8-kvbe-dst > /tmp/t8-build.log 2>&1; echo RC=$?
```

Run it in one session, after `vm/sync-src.ps1 -Path kernel-7`. Extract
`mach_kernel` from `kernel-154.5.1-7-i386.apk` and pull it `uuencode`d, with
`sum` and `cksum`. Record its SHA-256.

- [ ] **Step 3: Compare, and re-check spec 2's oracles**

- **The mapping code.** Run `compare_flat.py` over its extent in both
  kernels. `$KREF`'s base is `0x100000`, since its file offset is the address
  minus `0x100000`. For our kernel, take `__TEXT`'s `vmaddr - fileoff` from
  its load commands, and do not assume it. Pass
  `--ref-window 0x100000:0x400000` and an `--ours-window` spanning our
  kernel's `__TEXT` and `__DATA`. The expected outcome is structural parity,
  recorded like `FBAllocateVBEConsole` was.
- **Spec 2's oracle for `VBEModeInfo2IODisplayInfo`.** Re-run it
  (`compare_kvbe.py` in the session scratchpad, or `compare_flat.py` with
  `--table 76:31`). It must still MATCH.
- **The 72-byte `BasicAllocateConsole` check.** Re-run it the same way.

- [ ] **Step 4: Check it**

- **With the stock booter (G4 in miniature):** graft the new kernel onto
  `$GOLDEN` and boot `-v`, with `--pmemsave 60:0x11000:0x2200`. `0x12854`
  must read zero. Serial must match a spec 2 kernel's except line 4, in a
  same-session A-B.
- **With Task 7's booter, the driver and this kernel:** boot on the G2
  adapter with `--pmemsave 60:0x11000:0x2200`. `0x12854` must be non-zero,
  and the console must render through the frame buffer at the mode's size.
  The full checks are in Task 9's G2.

- [ ] **Step 5: Commit**

```bash
git add src/kernel-7/machdep/i386/pmap.c src/kernel-7/bsd/dev/i386/FBConsole.c "$KDIV"
git commit -m "kernel: map the VESA frame buffer and publish it for the VBE console

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 9: Gates and records

**Files:**
- Modify: `$GATE`: add a "Spec 3" part, keeping spec 2's text
- Modify: `docs/drivers/video-reconstruction.md`, `src/drivers-i386/README`:
  the driver's `using VBE mode` path
- Modify: the spec's §7 only if a gate's form had to change, with the reason
  and a `[SUPERSEDED — ...]` label on the old text

**Interfaces:**
- Consumes:
  - Task 3's "which booter ran" banner;
  - Task 5's booter, as G1's control;
  - Task 7's booter;
  - Task 8's kernel;
  - `$KSPEC2`;
  - `$GOLDEN`'s stock kernel, for G5.
- Produces: the spec 3 gate record.

**Before any boot:** record `git status --short src/` (it must be clean, since
the sync copies the working tree), `$GOLDENSHA` re-hashed, and the hash of
every kernel, booter and `_reloc` used.

**Every boot proves which booter ran** (spec §6). Its first frame must show the
banner Task 3 Step 3 recorded for the booter that boot claims to use. A boot
whose first frame does not show it proves nothing.

- [ ] **Step 1: G1, nothing changes without a VBE mode**

Build the image with no driver and no `VBE Mode` key. Run the verbose path
with Task 8's kernel:
- **A** is Task 5's booter;
- **B** is Task 7's booter;
- then **A** again.

Use `--pmemsave 60:0x11000:0x2200`. Pass when both hold:
- the comparison rules hold, except the banner line if the two builds'
  banners differ (record it);
- `kbs+0x1854..0x20D7` is zero in every dump.

- [ ] **Step 2: G2, the VBE path**

Use the driver, Task 7's booter and Task 8's kernel, on the chosen adapter.
Boot verbose and in graphics mode, whichever item 7 says 4.2 used for the
VBE console. Pass on all five checks of spec §7 G2:
- the booter's panel is drawn in the VBE mode;
- the dump shows `0x12854` non-zero, the record at `0x12858` naming N, 1 to
  89 records from `0x12870`, and the next record zero;
- serial shows `Using VBE Mode N`, `using VBE mode N` and the per-mode lines;
- the console renders through the frame-buffer console at the mode's size;
- `boot_video` matches G1's dump.

- [ ] **Step 3: G3, the fallback**

Two cases:
- the driver's table `VBE Mode` set to a mode the BIOS does not list;
- an adapter with no usable VBE, if Task 3 found one.

Pass when the booter prints 4.2's message for each case, the boot continues
on the VGA console, and `vbeCurrentMode.xResolution` is zero.

To edit the table in the image, use `rhap_inject.py`'s `set-key` on the
installed `Instance0.table`, on `vm/work/test.img`.

- [ ] **Step 4: G4, the kernel alone**

Run a same-session A-B-A:
- **A** is `$KSPEC2` with the stock booter and the driver;
- **B** is Task 8's kernel with the stock booter and the driver.

Pass when these hold:
- both show `Skipping framebuffer initialization`;
- the serial matches except line 4;
- `0x12854` is zero in B's dump.

- [ ] **Step 5: G5, link order**

1. Build the image from `$GOLDEN` with **no kernel graft**. The stock kernel
   lacks `_VBEModeInfo2IODisplayInfo`; confirm that from its symbol table
   before relying on it.
2. `install-driver.py vm/work/kern.img "$DRV" vm/work/test.img --first`, then
   read `Boot Drivers` back. It must start with `VBE20DisplayDriver`.
3. Boot verbose with the stock booter.
4. Capture the booter screen and confirm its driver-loading lines are
   actually in the frame; otherwise the result is inconclusive.
5. Compare the list of registered devices with the same boot minus the
   driver.

Record the result either way. Every other Boot Driver still registering
upgrades spec 2's "no cascade at any position" from `[inference]` to
`[measured]` **for the first position**. Update `$GATE`'s wording to match.
A cascade is a finding about `sarld`, recorded, not a failure here.

- [ ] **Step 6: Write the records**

Extend `$GATE` in spec 2's shape:
- procedure;
- hashes of every artifact and image;
- the captured lines;
- "what this establishes and what it does not".

That last section must say that nothing here is established on hardware, and
it must list the alert-console consequence (spec §8) as observed or not.

State that the captures cannot be regenerated. Update the status rows in
`docs/drivers/video-reconstruction.md` and `src/drivers-i386/README`.

- [ ] **Step 7: Commit**

```bash
git add "$GATE" docs/drivers/video-reconstruction.md src/drivers-i386/README
git commit -m "docs: record the VBE booter and frame-buffer console gates

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
