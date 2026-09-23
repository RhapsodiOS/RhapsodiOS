# drvIntelE100 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `drvIntelE100`, an original BSD-2-Clause DriverKit driver for Intel's 8255x (e100) 10/100 Ethernet family, prove it passes traffic under QEMU, and retire `drvIntel82557`.

**Architecture:**
- The code is split by responsibility:
  - pure logic in `E100Logic.c`
  - register access in `E100Hw.c`, which goes through the port macros in `E100Port.h` so tests can mock them
  - one Objective-C `IOEthernet` subclass, `IntelE100.m`, that owns DMA, the rings, interrupts, the watchdog and filtering
- The C logic is unit-tested on the build guest, following drvAHCI's precedent.
- The whole driver is boot-tested under QEMU's eepro100 models by a new runner, `vm/e100-boot.py`. It works on images of its own and checks a host-side packet capture.

**Tech Stack:**
- NeXT Objective-C and C89, built with cc 2.7.2.1
- DriverKit (`IOEthernet`, `IONetbufQueue`)
- rbuild on the Rhapsody build guest
- Python 3.13 and PowerShell on the Windows host
- QEMU 11.1 (`qemu-system-i386`)

**Spec:** `docs/superpowers/specs/2026-09-22-intele100-driver-design.md`. Read it before starting. It explains every design choice this plan implements.

## Global Constraints

These apply to every task.

**Licensing and sources**
- License: BSD-2-Clause, `Copyright (c) 2026, Pat Raynor`, on every new source file.
- References:
  - The primary reference is Intel's *8255x Open Source Software Developer Manual* rev 1.0, "SDM".
  - FreeBSD `sys/dev/fxp` (BSD-2) supplies the facts the SDM lacks.
  - Linux `e100.c` is GPL. **Never copy from it or derive code from it.**
  - No code is copied from any reference; only facts are taken, and each is cited in a comment.

**Code**
- **Language:** strict C89 plus NeXT Objective-C.
  - No `//` comments.
  - Declarations only at the top of a block.
  - No libc in kernel code.
- **Kernel code must not sleep in `-resetAndEnable:`.** Use bounded `IODelay` loops only; Pro1000 learned this by hanging the machine.
- Test code compiles with `cc -ansi -pedantic -Wall -Werror -traditional-cpp` on the **PowerPC** build guest, as drvAHCI's tests do. Under `-ansi` the default cpp-precomp rewrites the system headers' `__inline`, which gcc 2.7.2.1 then rejects; `-traditional-cpp` uses GNU cpp instead. Tests assert values, never little-endian byte images.
- **Log prefix:** every `IOLog` line starts `IntelE100: `.
- **QEMU identity:** MAC `52:54:00:12:34:56`, PCI slot `addr=03.0`, gateway `10.0.2.2`.

**Commits**
- The message is one or two lines, starting `drvIntelE100: ` or `vm: `.
- **No trailers or other metadata** (CLAUDE.md).

**Where to work and test**
- Work only in the git worktree created in "Before you start". Parallel sessions share the main checkout's index.
- Boot tests use only images under the worktree's `vm/work/`. **Never boot or write `D:\RhapsodiOS\vm\work\test.img`** (CLAUDE.md §6).

## Before you start

- [ ] **Create the worktree.** Use superpowers:using-git-worktrees. Its equivalent:

```bash
cd /d/RhapsodiOS
git worktree add -b intele100 .claude/worktrees/intele100 HEAD
cd .claude/worktrees/intele100
```

- [ ] **Stage the gitignored prerequisites.** These don't travel with a worktree; the memory note `concurrent-sessions-need-worktrees` says so.

```bash
cp /d/RhapsodiOS/vm/vm.conf vm/vm.conf
export E100_GOLDEN='D:/RhapsodiOS/vm/golden.img'
export E100_KERNEL='D:/RhapsodiOS/vm/install/mach_kernel'
ls -l "$E100_GOLDEN" "$E100_KERNEL"
```

Expected: both files are listed. `mach_kernel` is the rebuilt i386 kernel the other boot tests use.

The build guest at 10.10.0.241 (see `vm/vm.conf`) is shared with other sessions. Sync only `drivers-i386/network/drvIntelE100`, never `-All`.

## File map

| File | Responsibility |
|---|---|
| `vm/guest-console.py` (modify) | `qemu_args()` split out; `Guest` gains `image=` and `nic=` |
| `vm/test_guest_console.py` | unit test for `qemu_args()` |
| `vm/e100-pcap.py` | summarise a QEMU `filter-dump` pcap for one MAC |
| `vm/test_e100_pcap.py` | unit test for it |
| `vm/guest-remote.ps1` | run a script on the build guest, or fetch one file from it |
| `vm/build-i386-e100.sh` | guest side: run `tests/`, then rbuild the package |
| `vm/e100-boot.py` | host side: image, install, boot, capture, report |
| `src/drivers-i386/network/drvIntelE100/…` | the driver (layout in spec §1) |
| `src/drivers-i386/network/drvIntel82557/` | deleted in Task 7 |
| `src/drivers-i386/README` | network entry replaced in Task 7 |

---

### Task 1: QEMU harness — selectable NIC and image, and a pcap summariser

**Files:**
- Modify: `vm/guest-console.py:63-81` (the `Guest.__init__` argument list and QEMU command line)
- Create: `vm/test_guest_console.py`
- Create: `vm/e100-pcap.py`
- Create: `vm/test_e100_pcap.py`

**Interfaces:**
- Produces:
  - `qemu_args(image, persist, port, com1, nic, extra, serial) -> list[str]`, where `nic` is the `-device` value without `,netdev=n0`
  - `Guest(outdir, persist=False, port=4481, com1="null", extra=(), image=IMAGE, nic="ne2k_pci")`
  - `e100-pcap.py`: `summarize(path, mac) -> dict` with keys `from_guest`, `to_guest`, `arp_replies_to_guest`, `icmp_replies_to_guest`, and `main(argv) -> int` (0 only when traffic flowed both ways)

- [ ] **Step 1: Write the failing tests**

`vm/test_guest_console.py`:

```python
"""Unit test for guest-console.py's QEMU command line.

Run with: cd vm && python -m unittest test_guest_console -v
"""
import importlib.util
import os
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "guest_console", os.path.join(_HERE, "guest-console.py"))
gc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gc)


class QemuArgsTest(unittest.TestCase):
    def test_defaults_keep_the_old_command_line(self):
        a = gc.qemu_args(gc.IMAGE, False, 4481, "null", "ne2k_pci", (), "s.log")
        self.assertIn("ne2k_pci,netdev=n0", a)
        i = a.index("-drive")
        self.assertEqual(
            a[i + 1], "file=%s,format=raw,if=ide,index=0,media=disk" % gc.IMAGE)
        self.assertEqual(a[i + 2], "-snapshot")
        self.assertIn("file:s.log", a)

    def test_image_nic_and_extra(self):
        extra = ("-object", "filter-dump,id=f0,netdev=n0,file=p.pcap")
        a = gc.qemu_args("x.img", True, 4600, "null",
                         "i82559er,addr=03.0", extra, "s.log")
        self.assertIn("file=x.img,format=raw,if=ide,index=0,media=disk", a)
        self.assertIn("i82559er,addr=03.0,netdev=n0", a)
        self.assertNotIn("-snapshot", a)
        self.assertEqual(a[-2:], list(extra))
        self.assertIn("tcp:127.0.0.1:4600,server,nowait", a)


if __name__ == "__main__":
    unittest.main()
```

`vm/test_e100_pcap.py`:

```python
"""Unit test for e100-pcap.py.

Run with: cd vm && python -m unittest test_e100_pcap -v
"""
import importlib.util
import os
import struct
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "e100_pcap", os.path.join(_HERE, "e100-pcap.py"))
pcap = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pcap)

MAC = "52:54:00:12:34:56"
GUEST = bytes.fromhex("525400123456")
SLIRP = bytes.fromhex("52550a000202")
OTHER = bytes.fromhex("020000000001")
BCAST = b"\xff" * 6


def eth(dst, src, etype, payload):
    return dst + src + struct.pack(">H", etype) + payload


def arp(op):
    return struct.pack(">HHBBH", 1, 0x0800, 6, 4, op) + b"\0" * 20


def icmp(kind):
    ip = bytes([0x45, 0, 0, 28, 0, 0, 0, 0, 64, 1, 0, 0,
                10, 0, 2, 2, 10, 0, 2, 15])
    return ip + bytes([kind, 0, 0, 0, 0, 0, 0, 0])


def write_pcap(path, frames, big_endian=False):
    e = ">" if big_endian else "<"
    with open(path, "wb") as f:
        f.write(struct.pack(e + "IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
        for fr in frames:
            f.write(struct.pack(e + "IIII", 0, 0, len(fr), len(fr)))
            f.write(fr)


class SummarizeTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.dir.name, "t.pcap")

    def tearDown(self):
        self.dir.cleanup()

    def both_ways(self):
        return [eth(BCAST, GUEST, 0x0806, arp(1)),
                eth(GUEST, SLIRP, 0x0806, arp(2)),
                eth(SLIRP, GUEST, 0x0800, icmp(8)),
                eth(GUEST, SLIRP, 0x0800, icmp(0)),
                eth(OTHER, SLIRP, 0x0800, icmp(0))]

    def test_counts_both_directions(self):
        write_pcap(self.path, self.both_ways())
        s = pcap.summarize(self.path, MAC)
        self.assertEqual(s["from_guest"], 2)
        self.assertEqual(s["to_guest"], 2)
        self.assertEqual(s["arp_replies_to_guest"], 1)
        self.assertEqual(s["icmp_replies_to_guest"], 1)
        self.assertEqual(pcap.main(["e100-pcap.py", self.path, MAC]), 0)

    def test_one_direction_fails(self):
        write_pcap(self.path, [eth(BCAST, GUEST, 0x0806, arp(1))])
        self.assertEqual(pcap.main(["e100-pcap.py", self.path, MAC]), 1)

    def test_big_endian_file(self):
        write_pcap(self.path, self.both_ways(), big_endian=True)
        self.assertEqual(pcap.summarize(self.path, MAC)["to_guest"], 2)

    def test_not_a_pcap(self):
        with open(self.path, "wb") as f:
            f.write(b"\0" * 64)
        with self.assertRaises(ValueError):
            pcap.summarize(self.path, MAC)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd vm && python -m unittest test_guest_console test_e100_pcap -v`

Expected: both modules error out:
- `test_guest_console` with `AttributeError: module 'guest_console' has no attribute 'qemu_args'`
- `test_e100_pcap` with `FileNotFoundError` for `e100-pcap.py`

- [ ] **Step 3: Implement `qemu_args` in `vm/guest-console.py`**

Replace the start of `class Guest` and its `__init__` down to and including the `self.proc = subprocess.Popen(args)` line. That is, replace this:

```python
class Guest(object):
    def __init__(self, outdir, persist=False, port=4481, com1="null", extra=()):
        # com1 is the first serial port, which the kernel does not use -- pass
        # "msmouse" to put a Microsoft serial mouse on it.  extra appends raw
        # qemu arguments, for hardware a driver under test needs (e.g.
        # "-parallel", "null").
        self.outdir = outdir
        os.makedirs(outdir, exist_ok=True)
        self.serial = os.path.join(outdir, "serial.log")
        args = [
            "qemu-system-i386", "-M", "pc", "-cpu", "pentium", "-accel", "tcg",
            "-m", "128", "-nodefaults", "-vga", "cirrus", "-display", "none",
            "-drive", "file=%s,format=raw,if=ide,index=0,media=disk" % IMAGE,
            "-netdev", "user,id=n0", "-device", "ne2k_pci,netdev=n0",
            "-serial", com1, "-serial", "file:%s" % self.serial,
            "-rtc", "base=1998-05-08T12:00:00",
            "-qmp", "tcp:127.0.0.1:%d,server,nowait" % port, "-boot", "order=c",
        ]
        args.extend(extra)
        if not persist:
            args.insert(args.index("-drive") + 2, "-snapshot")
        self.proc = subprocess.Popen(args)
```

with this:

```python
def qemu_args(image, persist, port, com1, nic, extra, serial):
    """The qemu-system-i386 command line a Guest runs.  nic is the -device
    value without its netdev, e.g. "ne2k_pci" or "i82559er,addr=03.0"."""
    args = [
        "qemu-system-i386", "-M", "pc", "-cpu", "pentium", "-accel", "tcg",
        "-m", "128", "-nodefaults", "-vga", "cirrus", "-display", "none",
        "-drive", "file=%s,format=raw,if=ide,index=0,media=disk" % image,
        "-netdev", "user,id=n0", "-device", "%s,netdev=n0" % nic,
        "-serial", com1, "-serial", "file:%s" % serial,
        "-rtc", "base=1998-05-08T12:00:00",
        "-qmp", "tcp:127.0.0.1:%d,server,nowait" % port, "-boot", "order=c",
    ]
    args.extend(extra)
    if not persist:
        args.insert(args.index("-drive") + 2, "-snapshot")
    return args


class Guest(object):
    def __init__(self, outdir, persist=False, port=4481, com1="null", extra=(),
                 image=IMAGE, nic="ne2k_pci"):
        # com1 is the first serial port, which the kernel does not use -- pass
        # "msmouse" to put a Microsoft serial mouse on it.  extra appends raw
        # qemu arguments, for hardware a driver under test needs (e.g.
        # "-parallel", "null").  image and nic let a test boot an image of
        # its own with a different network card.
        self.outdir = outdir
        os.makedirs(outdir, exist_ok=True)
        self.serial = os.path.join(outdir, "serial.log")
        self.proc = subprocess.Popen(
            qemu_args(image, persist, port, com1, nic, extra, self.serial))
```

- [ ] **Step 4: Implement `vm/e100-pcap.py`**

```python
"""Summarise a QEMU filter-dump capture for one guest MAC address.

usage: python e100-pcap.py FILE.pcap GUEST_MAC

Counts frames the guest sent, frames addressed to it, and among the latter
the ARP replies and ICMP echo replies. Exits 0 only when frames went both
ways, which is what proves a network driver both transmits and receives.
"""
import struct
import sys


def frames(path):
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 24:
        raise ValueError("%s is too short to be a pcap file" % path)
    magic = struct.unpack("<I", data[:4])[0]
    if magic == 0xA1B2C3D4:
        endian = "<"
    elif magic == 0xD4C3B2A1:
        endian = ">"
    else:
        raise ValueError("%s is not a pcap file" % path)
    off = 24
    while off + 16 <= len(data):
        incl = struct.unpack(endian + "I", data[off + 8:off + 12])[0]
        off += 16
        yield data[off:off + incl]
        off += incl


def summarize(path, mac):
    me = bytes(int(x, 16) for x in mac.split(":"))
    s = {"from_guest": 0, "to_guest": 0,
         "arp_replies_to_guest": 0, "icmp_replies_to_guest": 0}
    for fr in frames(path):
        if len(fr) < 14:
            continue
        dst, src = fr[0:6], fr[6:12]
        etype = struct.unpack(">H", fr[12:14])[0]
        if src == me:
            s["from_guest"] += 1
            continue
        if dst != me:
            continue
        s["to_guest"] += 1
        if etype == 0x0806 and len(fr) >= 22 \
                and struct.unpack(">H", fr[20:22])[0] == 2:
            s["arp_replies_to_guest"] += 1
        if etype == 0x0800 and len(fr) >= 15:
            ihl = (fr[14] & 0x0F) * 4
            if len(fr) > 14 + ihl and fr[23] == 1 and fr[14 + ihl] == 0:
                s["icmp_replies_to_guest"] += 1
    return s


def main(argv):
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    s = summarize(argv[1], argv[2])
    for key in sorted(s):
        print("%s %d" % (key, s[key]))
    return 0 if s["from_guest"] and s["to_guest"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd vm && python -m unittest test_guest_console test_e100_pcap -v`

Expected: `Ran 6 tests … OK`.

Then run the existing harness tests to confirm nothing else broke:

Run: `cd vm && python -m unittest test_qemu_shot -v`

Expected: OK.

- [ ] **Step 6: Commit**

```bash
git add vm/guest-console.py vm/test_guest_console.py vm/e100-pcap.py vm/test_e100_pcap.py
git commit -m "vm: let guest-console boot any image with any NIC, and summarise pcap captures"
```

---

### Task 2: Guest remote runner and file fetch

**Files:**
- Create: `vm/guest-remote.ps1`

**Interfaces:**
- Consumes:
  - `rhap-remote.ps1`: `Get-RhapVmConfig -DiePrefix`, `Resolve-RhapTool -Name -Kind`, `Invoke-RhapSshCapture -Cfg -Ssh -ScriptBody`
  - `$script:RhapLastSshCapture` with `.ExitCode`, `.Stdout` and `.Stderr`
- Produces:
  - `guest-remote.ps1 -Run <script>`: runs the script and exits with the remote exit code
  - `guest-remote.ps1 -Fetch <remote path> -To <local path>`: copies one file, verifying its size

- [ ] **Step 1: Write `vm/guest-remote.ps1`**

```powershell
<#
Run a shell script on the build guest, or copy one file back from it.

  powershell -NoProfile -File vm\guest-remote.ps1 -Run vm\build-i386-e100.sh
  powershell -NoProfile -File vm\guest-remote.ps1 -Fetch /build/out/x.apk -To vm\work\x.apk

-Fetch sends the file as a hex dump on stdout. This guest's sshd only
speaks the legacy algorithms rhap-remote.ps1 sets up, and modern scp cannot
talk to it at all (vm/README.md), so there is no binary channel to use.
#>
param(
    [string]$Run,
    [string]$Fetch,
    [string]$To
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'rhap-remote.ps1')

if ([string]::IsNullOrEmpty($Run) -eq [string]::IsNullOrEmpty($Fetch)) {
    Write-RhapDie 'guest-remote' 'give exactly one of -Run or -Fetch'
}
$cfg = Get-RhapVmConfig -DiePrefix 'guest-remote'
$ssh = Resolve-RhapTool -Name $cfg.Ssh -Kind 'ssh'

if ($Run) {
    $body = Get-Content -LiteralPath $Run -Raw
    Invoke-RhapSshCapture -Cfg $cfg -Ssh $ssh -ScriptBody $body | Out-Null
    $r = $script:RhapLastSshCapture
    Write-Host $r.Stdout
    if ($r.Stderr) { Write-Host '--- stderr ---'; Write-Host $r.Stderr }
    exit $r.ExitCode
}

if ([string]::IsNullOrEmpty($To)) { Write-RhapDie 'guest-remote' '-Fetch needs -To' }
$body = @'
f='__FILE__'
wc -c < "$f" || exit 1
hexdump -v -e '32/1 "%02x" "\n"' "$f" || exit 1
'@
$body = $body.Replace('__FILE__', $Fetch)
Invoke-RhapSshCapture -Cfg $cfg -Ssh $ssh -ScriptBody $body | Out-Null
$r = $script:RhapLastSshCapture
if ($r.ExitCode -ne 0) { Write-RhapDie 'guest-remote' "reading $Fetch failed: $($r.Stderr)" }

$lines = @($r.Stdout -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
$size = [int64]$lines[0]
$hex = -join ($lines | Select-Object -Skip 1)
$bytes = New-Object byte[] ($hex.Length / 2)
for ($i = 0; $i -lt $bytes.Length; $i++) {
    $bytes[$i] = [Convert]::ToByte($hex.Substring(2 * $i, 2), 16)
}
if ($bytes.Length -ne $size) {
    Write-RhapDie 'guest-remote' "got $($bytes.Length) bytes but the guest says $size"
}
$dest = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($To)
[IO.File]::WriteAllBytes($dest, $bytes)
Write-Host "fetched $size bytes to $dest"
```

- [ ] **Step 2: Verify `-Run` and that `hexdump` exists on the guest**

```bash
mkdir -p vm/work
printf 'uname -a\nls -l /usr/bin/hexdump\nexit 3\n' > vm/work/probe.sh
powershell.exe -NoProfile -File vm/guest-remote.ps1 -Run vm/work/probe.sh; echo "exit=$?"
```

Expected:
- A Rhapsody `uname` line.
- A listing for `/usr/bin/hexdump`.
- `exit=3`, which proves the remote exit code is passed through.

If `hexdump` is missing, stop and report it; `-Fetch` depends on it.

- [ ] **Step 3: Verify `-Fetch` byte-for-byte**

```bash
powershell.exe -NoProfile -File vm/guest-remote.ps1 -Fetch /etc/rc -To vm/work/rc.fetched
printf 'cat /etc/rc\n' > vm/work/cat.sh
powershell.exe -NoProfile -File vm/guest-remote.ps1 -Run vm/work/cat.sh > vm/work/rc.cat
python -c "a=open('vm/work/rc.fetched','rb').read(); b=open('vm/work/rc.cat','rb').read().replace(b'\r\n',b'\n'); print('MATCH' if b.startswith(a) else 'DIFFER', len(a))"
```

Expected:
- `fetched N bytes to …`
- `MATCH N`

The `-Run` copy carries a trailing newline from `Write-Host`, which is why the check uses `startswith`.

- [ ] **Step 4: Commit**

```bash
git add vm/guest-remote.ps1
git commit -m "vm: add guest-remote.ps1 to run a script on the build guest or fetch a file from it"
```

---

### Task 3: Register definitions and pure logic, with guest-run unit tests

**Files:**
- Create: `src/drivers-i386/network/drvIntelE100/IntelE100.drvproj/IntelE100.lksproj/E100Regs.h`
- Create: `.../IntelE100.lksproj/E100Logic.h`
- Create: `.../IntelE100.lksproj/E100Logic.c`
- Create: `src/drivers-i386/network/drvIntelE100/tests/Makefile`
- Create: `src/drivers-i386/network/drvIntelE100/tests/e100_logic_test.c`
- Create: `vm/build-i386-e100.sh`

Paths below abbreviate `src/drivers-i386/network/drvIntelE100` as `E100/` and `E100/IntelE100.drvproj/IntelE100.lksproj` as `LKS/`.

**Interfaces:**
- Produces, in `E100Logic.h` (every later task uses these exact names):
  - `typedef struct { unsigned short device; short revision; unsigned char ich; const char *name; } E100Chip;`
  - `const E100Chip *e100ChipTable(void);` returns the table, terminated by `name == 0`
  - `const E100Chip *e100ChipLookup(unsigned short device, unsigned char revision);`
  - `int e100EffectiveRevision(const E100Chip *chip, unsigned char pciRevision, const unsigned short *eeprom);`
  - `unsigned int e100Quirks(const E100Chip *chip, int revision, const unsigned short *eeprom);` returns an OR of `E100_Q_RXBUG`, `E100_Q_SERIAL` and `E100_Q_CU_RESUME`
  - `const char *e100GenerationName(int revision);`
  - `void e100MacFromEeprom(const unsigned short *eeprom, unsigned char *mac);` and `int e100MacValid(const unsigned char *mac);`
  - `void e100BuildConfig(unsigned char *bytes, int revision, unsigned int quirks, int promiscuous, int allMulticast);`
  - `void e100FillMcast(E100McastCB *cb, const unsigned char *addrs, int count);`
  - `int e100StatsComplete(const volatile unsigned long *stats);`
  - `unsigned int e100NextThreshold(unsigned int threshold, unsigned long underruns);`
  - `void e100DecodeLink(int bmsr, int anar, int anlpar, int intelStatus, E100Link *link);`, where `E100Link` is `{ int up, known, speed100, fullDuplex; }`
  - The `eeprom` arrays hold at least `E100_EEPROM_WORDS_KEPT` (11) words.
  - Constants: `E100_REV_82557` (1), `E100_REV_82558` (4), `E100_REV_82559` (8) and `E100_REV_82550` (12); `E100_TX_THRESHOLD_START` (64), `_STEP` (64) and `_MAX` (192).
- Produces `E100Regs.h`: every constant, struct and offset below, used by all later tasks.

- [ ] **Step 1: Write `LKS/E100Regs.h`**

```c
/*
 * E100Regs.h - Intel 8255x registers, command blocks and EEPROM layout.
 *
 * Copyright (c) 2026, Pat Raynor. BSD-2-Clause; see LICENSE.
 *
 * "SDM" is Intel's 8255x 10/100 Mbps Ethernet Controller Family Open
 * Source Software Developer Manual, rev 1.0. Values the SDM does not give
 * (the EEPROM word map, the PHY word bits) follow FreeBSD's if_fxpreg.h and
 * say so.
 *
 * Plain C89: tests/ compiles this on the build guest.
 */
#ifndef E100REGS_H
#define E100REGS_H

/* Control/status registers, as offsets into the I/O BAR (SDM Table 11) */
#define E100_SCB_STATUS         0x00    /* byte: CU and RU state          */
#define E100_SCB_STATACK        0x01    /* byte: causes; write 1s to ack  */
#define E100_SCB_CMD            0x02    /* byte: CU and RU commands       */
#define E100_SCB_INTR           0x03    /* byte: interrupt mask           */
#define E100_SCB_GENPTR         0x04    /* long: general pointer          */
#define E100_PORT               0x08    /* long: PORT interface           */
#define E100_EECTL              0x0E    /* word: EEPROM control           */
#define E100_MDICTL             0x10    /* long: MDI control              */

/* SCB status byte (SDM 6.3.2.1) */
#define E100_CUS_MASK           0xC0    /* 00 = CU idle                   */

/* STAT/ACK byte */
#define E100_STAT_CX            0x80    /* CB with the I bit completed    */
#define E100_STAT_FR            0x40    /* frame received                 */
#define E100_STAT_CNA           0x20    /* CU left the active state       */
#define E100_STAT_RNR           0x10    /* RU left the ready state        */

/* SCB command byte: CU command in bits 7:4, RU command in bits 2:0 */
#define E100_CUC_NOP            0x00
#define E100_CUC_START          0x10
#define E100_CUC_RESUME         0x20
#define E100_CUC_DUMP_ADDR      0x40    /* load dump counters address     */
#define E100_CUC_LOAD_BASE      0x60
#define E100_CUC_DUMP_RESET     0x70    /* dump and reset counters        */
#define E100_RUC_START          0x01
#define E100_RUC_LOAD_BASE      0x06

/* Interrupt control byte */
#define E100_INTR_MASK_ALL      0x01    /* M: masks every source          */

/* PORT opcodes (SDM 6.3.3) */
#define E100_PORT_SOFTWARE_RESET        0x00000000UL
#define E100_PORT_SELECTIVE_RESET       0x00000002UL

/* EEPROM control word (SDM 6.3.4) */
#define E100_EE_SK              0x01
#define E100_EE_CS              0x02
#define E100_EE_DI              0x04
#define E100_EE_DO              0x08
#define E100_EE_OP_READ         0x6     /* 110b, sent most significant first */

/* EEPROM word map (FreeBSD if_fxpreg.h) */
#define E100_EEPROM_COMPAT      0x03
#define E100_EEPROM_CONTROLLER  0x05    /* high byte 1 means an 82557     */
#define E100_EEPROM_PHY         0x06
#define E100_EEPROM_ID          0x0A
#define E100_EEPROM_WORDS_KEPT  0x0B    /* words 0..0x0A are all we use   */
#define E100_EEPROM_SUM         0xBABA  /* sum of every word, checksum too */

#define E100_COMPAT_RXBUG_FIXED 0x0003  /* both set: 82557 lockup fixed   */
#define E100_PHY_ADDR_MASK      0x001F
#define E100_PHY_DEVICE_MASK    0x3F00
#define E100_PHY_SERIAL_ONLY    0x8000  /* 82503 serial interface, no MII */
#define E100_ID_STANDBY         0x0002  /* Dynamic Standby enabled        */

/* MDI control register (SDM 6.3.5) */
#define E100_MDI_OP_WRITE       0x04000000UL
#define E100_MDI_OP_READ        0x08000000UL
#define E100_MDI_READY          0x10000000UL
#define E100_MDI_PHY_SHIFT      21
#define E100_MDI_REG_SHIFT      16

/* MII registers and bits (IEEE 802.3 clause 22; register 16 is SDM 7.5) */
#define MII_BMCR                0
#define MII_BMSR                1
#define MII_PHYID1              2
#define MII_PHYID2              3
#define MII_ANAR                4
#define MII_ANLPAR              5
#define MII_INTEL_STATUS        16
#define BMCR_AUTONEG            0x1000
#define BMCR_RESTART_AUTONEG    0x0200
#define BMSR_AUTONEG_DONE       0x0020
#define BMSR_LINK               0x0004
#define ANLPAR_100FD            0x0100
#define ANLPAR_100TX            0x0080
#define ANLPAR_10FD             0x0040
#define ANLPAR_10               0x0020
#define INTEL_STATUS_100        0x0002
#define INTEL_STATUS_FD         0x0001
#define INTEL_PHYID1            0x02A8  /* OUI 00AA00 (SDM 7.5)           */

/*
 * Command block header (SDM 6.4.2). Dword 0 is status in its low half and
 * command in its high half, which on the little-endian i386 is the order
 * of the two shorts in memory.
 */
typedef struct {
    volatile unsigned short     status;
    volatile unsigned short     command;
    volatile unsigned long      link;
} E100CBHeader;

#define E100_CB_C               0x8000  /* status: complete               */
#define E100_CB_OK              0x2000  /* status: no error               */
#define E100_CB_EL              0x8000  /* command: end of list           */
#define E100_CB_S               0x4000  /* command: suspend after this CB */
#define E100_CB_NOP             0x0000
#define E100_CB_IAS             0x0001
#define E100_CB_CONFIGURE       0x0002
#define E100_CB_MCAS            0x0003
#define E100_CB_XMIT            0x0004

#define E100_NO_LINK            0xFFFFFFFFUL
#define E100_MAX_FRAME          1514    /* the chip appends the CRC       */

/* Transmit CB in simplified mode: the frame follows inline (SDM 6.4.2.5) */
typedef struct {
    E100CBHeader                hdr;
    volatile unsigned long      tbdArray;       /* E100_NO_LINK           */
    volatile unsigned short     byteCount;      /* 13:0 count, 15 EOF     */
    volatile unsigned char      threshold;      /* units of 8 bytes       */
    volatile unsigned char      tbdNumber;
    unsigned char               data[E100_MAX_FRAME];
} E100TxCB;

#define E100_TCB_EOF            0x8000

#define E100_CONFIG_BYTES       22

typedef struct {
    E100CBHeader                hdr;
    unsigned char               bytes[E100_CONFIG_BYTES];
} E100ConfigCB;

typedef struct {
    E100CBHeader                hdr;
    unsigned char               addr[6];
} E100IaCB;

#define E100_MAX_MCAST          32

typedef struct {
    E100CBHeader                hdr;
    volatile unsigned short     byteCount;      /* 6 per address          */
    unsigned char               addr[E100_MAX_MCAST * 6];
} E100McastCB;

/* Receive frame descriptor, simplified mode (SDM 6.4.3.1) */
#define E100_RFD_BUF            1520

typedef struct {
    volatile unsigned short     status;
    volatile unsigned short     command;
    volatile unsigned long      link;
    volatile unsigned long      rbdPointer;     /* unused: E100_NO_LINK   */
    volatile unsigned short     actualCount;    /* 13:0 count, F, EOF     */
    volatile unsigned short     size;
    unsigned char               data[E100_RFD_BUF];
} E100Rfd;

#define E100_RFD_C              0x8000
#define E100_RFD_OK             0x2000
#define E100_RFD_ERRORS         0x0F80  /* CRC, align, no-res, overrun, short */
#define E100_RFD_EL             0x8000
#define E100_RFD_EOF            0x8000
#define E100_RFD_COUNT_MASK     0x3FFF

/* Statistics dump (SDM 6.3.2.4), indexed in dwords */
#define E100_STAT_TX_GOOD       0
#define E100_STAT_TX_MAXCOL     1
#define E100_STAT_TX_LATECOL    2
#define E100_STAT_TX_UNDERRUN   3
#define E100_STAT_TX_LOSTCRS    4
#define E100_STAT_TX_TOTALCOL   8
#define E100_STAT_RX_GOOD       9
#define E100_STAT_RX_CRC        10
#define E100_STAT_RX_ALIGN      11
#define E100_STAT_RX_RESOURCE   12
#define E100_STAT_RX_OVERRUN    13
#define E100_STAT_RX_SHORT      15
#define E100_STATS_DWORDS       21      /* the largest layout, completion too */
#define E100_DUMP_RESET_DONE    0x0000A007UL

#endif
```

- [ ] **Step 2: Write `LKS/E100Logic.h`**

```c
/*
 * E100Logic.h - the parts of the 8255x driver that are pure functions:
 * chip identification, quirk flags, configure bytes, statistics and link
 * decoding. No I/O and no kernel calls, so tests/ runs them anywhere.
 *
 * Copyright (c) 2026, Pat Raynor. BSD-2-Clause; see LICENSE.
 */
#ifndef E100LOGIC_H
#define E100LOGIC_H

#include "E100Regs.h"

typedef struct {
    unsigned short      device;
    short               revision;       /* PCI revision ID, or -1 for any */
    unsigned char       ich;            /* ICH generation; 0 = discrete   */
    const char         *name;
} E100Chip;

/* Effective revisions (FreeBSD if_fxpreg.h FXP_REV_*) */
#define E100_REV_82557          1
#define E100_REV_82558          4
#define E100_REV_82559          8       /* every ICH part counts as this  */
#define E100_REV_82550          12

/* Quirk flags */
#define E100_Q_RXBUG            0x01    /* 82557 receive lockup not fixed */
#define E100_Q_SERIAL           0x02    /* 82503 serial interface, no MII */
#define E100_Q_CU_RESUME        0x04    /* CU NOP before each CU Resume   */

/* Transmit threshold in the TxCB's units of 8 bytes (FreeBSD if_fxp.c) */
#define E100_TX_THRESHOLD_START 64
#define E100_TX_THRESHOLD_STEP  64
#define E100_TX_THRESHOLD_MAX   192

typedef struct {
    int up;
    int known;          /* speed100 and fullDuplex are meaningful */
    int speed100;
    int fullDuplex;
} E100Link;

const E100Chip *e100ChipTable(void);
const E100Chip *e100ChipLookup(unsigned short device, unsigned char revision);
int e100EffectiveRevision(const E100Chip *chip, unsigned char pciRevision,
                          const unsigned short *eeprom);
unsigned int e100Quirks(const E100Chip *chip, int revision,
                        const unsigned short *eeprom);
const char *e100GenerationName(int revision);

void e100MacFromEeprom(const unsigned short *eeprom, unsigned char *mac);
int e100MacValid(const unsigned char *mac);

void e100BuildConfig(unsigned char *bytes, int revision, unsigned int quirks,
                     int promiscuous, int allMulticast);
void e100FillMcast(E100McastCB *cb, const unsigned char *addrs, int count);

int e100StatsComplete(const volatile unsigned long *stats);
unsigned int e100NextThreshold(unsigned int threshold, unsigned long underruns);

void e100DecodeLink(int bmsr, int anar, int anlpar, int intelStatus,
                    E100Link *link);

#endif
```

- [ ] **Step 3: Write the failing test `E100/tests/e100_logic_test.c`**

```c
/*
 * e100_logic_test.c - unit tests for E100Logic.c.
 *
 * Copyright (c) 2026, Pat Raynor. BSD-2-Clause; see ../LICENSE.
 *
 * Built and run on the build guest by `gnumake check`. The guest is
 * PowerPC, so these assert values, never little-endian byte images.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "E100Logic.h"

static int failures;

static void
check(int ok, const char *test, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL %s: %s\n", test, what);
        failures++;
    }
}

static void
blank(unsigned short *ee)
{
    int i;

    for (i = 0; i < E100_EEPROM_WORDS_KEPT; i++)
        ee[i] = 0;
}

static void
test_chip_lookup(void)
{
    static const char t[] = "chip lookup";
    const E100Chip *c;

    c = e100ChipLookup(0x1229, 0x02);
    check(c != 0 && strcmp(c->name, "82557") == 0, t, "1229 rev 2 is an 82557");
    c = e100ChipLookup(0x1229, 0x09);
    check(c != 0 && strcmp(c->name, "82559ER") == 0, t, "1229 rev 9 is an 82559ER");
    c = e100ChipLookup(0x1229, 0x10);
    check(c != 0 && strcmp(c->name, "82551") == 0, t, "1229 rev 0x10 is an 82551");
    c = e100ChipLookup(0x1229, 0x42);
    check(c != 0 && c->revision == -1, t, "other 1229 revisions take the catch-all");
    c = e100ChipLookup(0x2449, 0x03);
    check(c != 0 && c->ich == 2, t, "2449 is ICH2");
    c = e100ChipLookup(0x1039, 0x00);
    check(c != 0 && c->ich == 4, t, "1039 is ICH4");
    check(e100ChipLookup(0x1234, 0x01) == 0, t, "unknown device refused");
}

/* Default.table must list exactly the devices the chip table knows. */
static void
test_default_table(void)
{
    static const char t[] = "Default.table";
    char buf[4096], id[16], *p, *end, *q;
    const E100Chip *c;
    unsigned long v;
    size_t n;
    FILE *f;

    f = fopen("../IntelE100.drvproj/Default.table", "r");
    if (f == 0) {
        check(0, t, "cannot open ../IntelE100.drvproj/Default.table");
        return;
    }
    n = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    buf[n] = 0;
    p = strstr(buf, "\"Auto Detect IDs\"");
    if (p == 0) {
        check(0, t, "no Auto Detect IDs key");
        return;
    }
    end = strchr(p, ';');
    if (end != 0)
        *end = 0;
    for (c = e100ChipTable(); c->name != 0; c++) {
        sprintf(id, "0x%04X8086", (unsigned int)c->device);
        check(strstr(p, id) != 0, t, id);
    }
    for (q = strstr(p, "0x"); q != 0; q = strstr(q, "0x")) {
        v = strtoul(q, &q, 16);
        check((v & 0xFFFFUL) == 0x8086UL
              && e100ChipLookup((unsigned short)(v >> 16), 0x42) != 0,
              t, "a listed ID has no chip table entry");
    }
}

static void
test_revision(void)
{
    static const char t[] = "effective revision";
    unsigned short ee[E100_EEPROM_WORDS_KEPT];

    blank(ee);
    check(e100EffectiveRevision(e100ChipLookup(0x2449, 3), 3, ee) == 8,
          t, "ICH parts count as revision 8");
    ee[E100_EEPROM_CONTROLLER] = 0x0100;
    check(e100EffectiveRevision(e100ChipLookup(0x1229, 2), 2, ee) == 1,
          t, "EEPROM word 5 high byte 1 means an 82557");
    ee[E100_EEPROM_CONTROLLER] = 0;
    check(e100EffectiveRevision(e100ChipLookup(0x1229, 2), 2, ee) == 2,
          t, "otherwise the PCI revision");
    check(e100EffectiveRevision(e100ChipLookup(0x1209, 9), 9, ee) == 9,
          t, "82559ER keeps its PCI revision");
}

static void
test_quirks(void)
{
    static const char t[] = "quirks";
    unsigned short ee[E100_EEPROM_WORDS_KEPT];
    const E100Chip *c557 = e100ChipLookup(0x1229, 2);
    const E100Chip *ich2 = e100ChipLookup(0x2449, 3);
    const E100Chip *ich4 = e100ChipLookup(0x1039, 0);

    blank(ee);
    check((e100Quirks(c557, 2, ee) & E100_Q_RXBUG) != 0, t, "82557 without the fix");
    ee[E100_EEPROM_COMPAT] = 0x0003;
    check((e100Quirks(c557, 2, ee) & E100_Q_RXBUG) == 0, t, "82557 with the fix");
    ee[E100_EEPROM_COMPAT] = 0;
    check((e100Quirks(c557, 4, ee) & E100_Q_RXBUG) == 0, t, "no lockup from rev 4");

    ee[E100_EEPROM_PHY] = 0x8300;
    check((e100Quirks(c557, 1, ee) & E100_Q_SERIAL) != 0, t, "82503 on rev 1");
    check((e100Quirks(c557, 2, ee) & E100_Q_SERIAL) == 0, t, "serial only on rev 1");
    ee[E100_EEPROM_PHY] = 0x0701;
    check((e100Quirks(c557, 1, ee) & E100_Q_SERIAL) == 0, t, "MII PHY is not serial");
    ee[E100_EEPROM_PHY] = 0;

    ee[E100_EEPROM_ID] = E100_ID_STANDBY;
    check((e100Quirks(ich2, 8, ee) & E100_Q_CU_RESUME) != 0, t, "ICH2 with standby");
    check((e100Quirks(ich4, 8, ee) & E100_Q_CU_RESUME) == 0, t, "not ICH4");
    check((e100Quirks(c557, 8, ee) & E100_Q_CU_RESUME) != 0, t, "discrete rev 8");
    check((e100Quirks(c557, 5, ee) & E100_Q_CU_RESUME) == 0, t, "not discrete rev 5");
    ee[E100_EEPROM_ID] = 0;
    check((e100Quirks(ich2, 8, ee) & E100_Q_CU_RESUME) == 0, t, "not without standby");
}

static void
test_generation(void)
{
    static const char t[] = "generation name";

    check(strcmp(e100GenerationName(1), "82557") == 0, t, "rev 1");
    check(strcmp(e100GenerationName(5), "82558") == 0, t, "rev 5");
    check(strcmp(e100GenerationName(8), "82559") == 0, t, "rev 8");
    check(strcmp(e100GenerationName(9), "82559") == 0, t, "rev 9");
    check(strcmp(e100GenerationName(13), "82550/82551") == 0, t, "rev 13");
}

static void
test_mac(void)
{
    static const char t[] = "MAC";
    unsigned short ee[E100_EEPROM_WORDS_KEPT];
    unsigned char mac[6];
    static const unsigned char want[6] = { 0x52, 0x54, 0x00, 0x12, 0x34, 0x56 };
    static const unsigned char zero[6] = { 0, 0, 0, 0, 0, 0 };
    static const unsigned char ones[6] = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };
    static const unsigned char group[6] = { 0x01, 0x00, 0x5E, 0x00, 0x00, 0x01 };

    blank(ee);
    ee[0] = 0x5452;
    ee[1] = 0x1200;
    ee[2] = 0x5634;
    e100MacFromEeprom(ee, mac);
    check(memcmp(mac, want, 6) == 0, t, "low byte of each word first");
    check(e100MacValid(mac), t, "station address accepted");
    check(!e100MacValid(zero), t, "all zeros refused");
    check(!e100MacValid(ones), t, "all ones refused");
    check(!e100MacValid(group), t, "multicast refused");
}

static void
test_config(void)
{
    static const char t[] = "configure bytes";
    unsigned char b[E100_CONFIG_BYTES];

    e100BuildConfig(b, 1, 0, 0, 0);
    check(b[0] == 0x16 && b[1] == 0x08 && b[6] == 0x32 && b[7] == 0x03, t, "82557 bytes 0-7");
    check(b[8] == 0x01 && b[10] == 0x2E && b[12] == 0x60, t, "82557 bytes 8-12");
    check(b[15] == 0x48 && b[17] == 0x40 && b[18] == 0xF2, t, "82557 bytes 15-18");
    check(b[19] == 0x80 && b[20] == 0x3F && b[21] == 0x05, t, "82557 bytes 19-21");

    e100BuildConfig(b, 8, 0, 0, 0);
    check(b[12] == 0x61, t, "82558+ sets byte 12 bit 0");

    e100BuildConfig(b, 1, E100_Q_SERIAL, 0, 0);
    check(b[8] == 0x00 && b[15] == 0xC8, t, "82503 serial interface");

    e100BuildConfig(b, 8, 0, 1, 0);
    check(b[15] == 0x49 && b[6] == 0xB2 && b[7] == 0x02 && b[21] == 0x0D,
          t, "promiscuous");

    e100BuildConfig(b, 8, 0, 0, 1);
    check(b[21] == 0x0D && b[15] == 0x48 && b[6] == 0x32, t, "all multicast only");
}

static void
test_mcast(void)
{
    static const char t[] = "multicast CB";
    static const unsigned char addrs[12] = {
        0x01, 0x00, 0x5E, 0x00, 0x00, 0x01, 0x01, 0x00, 0x5E, 0x00, 0x00, 0x02
    };
    unsigned char many[40 * 6];
    E100McastCB cb;

    e100FillMcast(&cb, addrs, 2);
    check(cb.byteCount == 12, t, "count is in bytes");
    check(cb.addr[5] == 0x01 && cb.addr[11] == 0x02, t, "addresses copied");
    memset(many, 0x01, sizeof(many));
    e100FillMcast(&cb, many, 40);
    check(cb.byteCount == E100_MAX_MCAST * 6, t, "capped at E100_MAX_MCAST");
    e100FillMcast(&cb, addrs, 0);
    check(cb.byteCount == 0, t, "empty list");
}

static void
test_stats(void)
{
    static const char t[] = "statistics completion";
    unsigned long s[E100_STATS_DWORDS];

    memset(s, 0, sizeof(s));
    check(!e100StatsComplete(s), t, "zeroed block is not complete");
    s[16] = E100_DUMP_RESET_DONE;
    check(e100StatsComplete(s), t, "82557 layout, dword 16");
    s[16] = 0;
    s[19] = E100_DUMP_RESET_DONE;
    check(e100StatsComplete(s), t, "82558 layout, dword 19");
    s[19] = 0;
    s[20] = E100_DUMP_RESET_DONE;
    check(e100StatsComplete(s), t, "82559 layout, dword 20");
    s[20] = 0;
    s[16] = 0x0000A005UL;
    check(!e100StatsComplete(s), t, "dump-without-reset code is not ours");
}

static void
test_threshold(void)
{
    static const char t[] = "transmit threshold";

    check(e100NextThreshold(64, 0) == 64, t, "no underruns, no change");
    check(e100NextThreshold(64, 3) == 128, t, "underruns raise it one step");
    check(e100NextThreshold(128, 1) == 192, t, "up to the maximum");
    check(e100NextThreshold(192, 9) == 192, t, "never past the maximum");
}

static void
test_link(void)
{
    static const char t[] = "link decode";
    E100Link l;

    e100DecodeLink(0x0000, 0x01E1, 0x01E1, -1, &l);
    check(!l.up && !l.known, t, "down");
    e100DecodeLink(0x0024, 0x01E1, 0x01E1, -1, &l);
    check(l.up && l.known && l.speed100 && l.fullDuplex, t, "100 full");
    e100DecodeLink(0x0024, 0x01E1, 0x0081, -1, &l);
    check(l.up && l.known && l.speed100 && !l.fullDuplex, t, "100 half");
    e100DecodeLink(0x0024, 0x01E1, 0x0041, -1, &l);
    check(l.up && l.known && !l.speed100 && l.fullDuplex, t, "10 full");
    e100DecodeLink(0x0004, 0x01E1, 0x0000, 0x0003, &l);
    check(l.up && l.known && l.speed100 && l.fullDuplex, t, "Intel register 16");
    e100DecodeLink(0x0004, -1, -1, -1, &l);
    check(l.up && !l.known, t, "up, nothing to say how");
}

int
main(void)
{
    test_chip_lookup();
    test_default_table();
    test_revision();
    test_quirks();
    test_generation();
    test_mac();
    test_config();
    test_mcast();
    test_stats();
    test_threshold();
    test_link();
    if (failures == 0)
        printf("e100_logic_test: all passed\n");
    return failures != 0;
}
```

- [ ] **Step 4: Write `E100/tests/Makefile`**

The `e100_hw_test` target is added in Task 4. Recipe lines start with a TAB.

```make
# Unit tests for drvIntelE100's plain C, built and run on the build guest:
#   cd tests && gnumake check
# Same flags as drvAHCI's tests: -traditional-cpp uses GNU cpp, because
# under -ansi cpp-precomp rewrites the system headers' __inline, which
# gcc 2.7.2.1 then rejects.
CC = cc
CFLAGS = -ansi -pedantic -Wall -Werror -traditional-cpp
LKS = ../IntelE100.drvproj/IntelE100.lksproj
INCLUDES = -I. -I$(LKS)

.PHONY: all check test clean

all: e100_logic_test

e100_logic_test: e100_logic_test.c $(LKS)/E100Logic.c $(LKS)/E100Logic.h $(LKS)/E100Regs.h
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ e100_logic_test.c $(LKS)/E100Logic.c

check: test

test: all
	./e100_logic_test

clean:
	rm -f e100_logic_test e100_hw_test
```

- [ ] **Step 5: Write `vm/build-i386-e100.sh`**

```sh
#!/bin/sh
# Test and build drvIntelE100 for i386. Runs on the build guest through
#   powershell -NoProfile -File vm\guest-remote.ps1 -Run vm\build-i386-e100.sh
# after vm\sync-src.ps1 -Path drivers-i386/network/drvIntelE100.
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH
SRC=/build/src/drivers-i386/network/drvIntelE100
DST=/build/out/drvIntelE100-rbuild

echo "======== drvIntelE100 tests `date` ========"
( cd $SRC/tests && gnumake clean check ) || { echo "TESTS_RC=1"; exit 1; }
echo "TESTS_RC=0"

if [ ! -f $SRC/apk/pkginfo ]; then
    echo "no apk/pkginfo yet - tests only"
    exit 0
fi

rm -rf "$DST"; mkdir -p "$DST"
echo "======== drvIntelE100 via rbuild (i386) `date` ========"
rbuild buildpackage --state /build/state --arch i386 --dir --target all \
    $SRC /build/repo "$DST" > "$DST.log" 2>&1
rc=$?
echo "BUILD_RC=$rc"
echo "--- compiler diagnostics from the driver's own sources ---"
grep -n "IntelE100\.m\|E100Hw\.c\|E100Logic\.c" "$DST.log" | grep -i "warning\|error"
[ $rc -ne 0 ] && tail -40 "$DST.log"
ls -l "$DST"/*.apk
# A fixed name for guest-remote.ps1 -Fetch, whatever version rbuild stamps
for f in "$DST"/*.apk; do cp "$f" /build/out/intele100.apk; done
exit $rc
```

- [ ] **Step 6: Run the test to verify it fails**

```bash
powershell.exe -NoProfile -File vm/sync-src.ps1 -Path drivers-i386/network/drvIntelE100
powershell.exe -NoProfile -File vm/guest-remote.ps1 -Run vm/build-i386-e100.sh; echo "exit=$?"
```

Expected:
- `TESTS_RC=1` and `exit=1`.
- gnumake reports that it has no rule to make `../IntelE100.drvproj/IntelE100.lksproj/E100Logic.c`.

- [ ] **Step 7: Implement `LKS/E100Logic.c`**

```c
/*
 * E100Logic.c - pure logic for the 8255x driver.
 *
 * Copyright (c) 2026, Pat Raynor. BSD-2-Clause; see LICENSE.
 *
 * The chip table, the effective-revision rule and the quirk conditions
 * follow FreeBSD's if_fxp.c (fxp_ident_table, fxp_attach); the configure
 * bytes and statistics layouts follow the SDM. No code is taken from
 * either.
 */
#include "E100Logic.h"

/*
 * FreeBSD's ident list. 0x1229 is identified by revision first (SDM
 * Table 2); its catch-all entry must come after those.
 */
static const E100Chip chipTable[] = {
    { 0x1029, -1, 0, "82559 PCI/CardBus" },
    { 0x1030, -1, 0, "82559 InBusiness 10/100" },
    { 0x1031, -1, 3, "82801CAM (ICH3) PRO/100 VE" },
    { 0x1032, -1, 3, "82801CAM (ICH3) PRO/100 VE" },
    { 0x1033, -1, 3, "82801CAM (ICH3) PRO/100 VM" },
    { 0x1034, -1, 3, "82801CAM (ICH3) PRO/100 VM" },
    { 0x1035, -1, 3, "82801CAM (ICH3) PRO/100" },
    { 0x1036, -1, 3, "82801CAM (ICH3) PRO/100" },
    { 0x1037, -1, 3, "82801CAM (ICH3) PRO/100" },
    { 0x1038, -1, 3, "82801CAM (ICH3) PRO/100 VM" },
    { 0x1039, -1, 4, "82801DB (ICH4) PRO/100 VE" },
    { 0x103A, -1, 4, "82801DB (ICH4) PRO/100" },
    { 0x103B, -1, 4, "82801DB (ICH4) PRO/100 VM" },
    { 0x103C, -1, 4, "82801DB (ICH4) PRO/100" },
    { 0x103D, -1, 4, "82801DB (ICH4) PRO/100 VE" },
    { 0x103E, -1, 4, "82801DB (ICH4) PRO/100 VM" },
    { 0x1050, -1, 5, "82801BA (D865) PRO/100 VE" },
    { 0x1051, -1, 5, "82562ET (ICH5) PRO/100 VE" },
    { 0x1059, -1, 0, "82551QM" },
    { 0x1064, -1, 6, "82562EZ (ICH6)" },
    { 0x1065, -1, 6, "82562ET/EZ/GT/GZ PRO/100 VE" },
    { 0x1068, -1, 6, "82801FBM (ICH6-M) PRO/100 VE" },
    { 0x1069, -1, 6, "82562EM/EX/GX PRO/100" },
    { 0x1091, -1, 7, "82562GX PRO/100" },
    { 0x1092, -1, 7, "PRO/100 VE (ICH7)" },
    { 0x1093, -1, 7, "PRO/100 VM (ICH7)" },
    { 0x1094, -1, 7, "946GZ (ICH7) PRO/100" },
    { 0x1209, -1, 0, "82559ER" },
    { 0x1229, 0x01, 0, "82557" },
    { 0x1229, 0x02, 0, "82557" },
    { 0x1229, 0x03, 0, "82557" },
    { 0x1229, 0x04, 0, "82558" },
    { 0x1229, 0x05, 0, "82558" },
    { 0x1229, 0x06, 0, "82559" },
    { 0x1229, 0x07, 0, "82559" },
    { 0x1229, 0x08, 0, "82559" },
    { 0x1229, 0x09, 0, "82559ER" },
    { 0x1229, 0x0C, 0, "82550" },
    { 0x1229, 0x0D, 0, "82550" },
    { 0x1229, 0x0E, 0, "82550" },
    { 0x1229, 0x0F, 0, "82551" },
    { 0x1229, 0x10, 0, "82551" },
    { 0x1229, -1,   0, "82557/8/9" },
    { 0x2449, -1, 2, "82801BA/CAM (ICH2/3) PRO/100" },
    { 0x27DC, -1, 7, "82801GB (ICH7) PRO/100" },
    { 0, 0, 0, 0 }
};

const E100Chip *
e100ChipTable(void)
{
    return chipTable;
}

const E100Chip *
e100ChipLookup(unsigned short device, unsigned char revision)
{
    const E100Chip *c;

    for (c = chipTable; c->name != 0; c++) {
        if (c->device == device
            && (c->revision < 0 || c->revision == (short)revision))
            return c;
    }
    return 0;
}

/*
 * FreeBSD's rule (if_fxp.c, fxp_attach): every ICH part is treated as an
 * 82559 A0, and an EEPROM that calls the controller an 82557 wins over
 * the PCI revision.
 */
int
e100EffectiveRevision(const E100Chip *chip, unsigned char pciRevision,
                      const unsigned short *eeprom)
{
    if (chip->ich > 0)
        return E100_REV_82559;
    if ((eeprom[E100_EEPROM_CONTROLLER] >> 8) == 1)
        return E100_REV_82557;
    return pciRevision;
}

unsigned int
e100Quirks(const E100Chip *chip, int revision, const unsigned short *eeprom)
{
    unsigned int q = 0;
    unsigned short phy = eeprom[E100_EEPROM_PHY];

    /* 82557 receive lockup, unless EEPROM word 3 says it is fixed */
    if (revision < E100_REV_82558
        && (eeprom[E100_EEPROM_COMPAT] & E100_COMPAT_RXBUG_FIXED)
           != E100_COMPAT_RXBUG_FIXED)
        q |= E100_Q_RXBUG;

    /* 82503 serial interface: a device type is set and so is serial-only */
    if (revision == E100_REV_82557
        && (phy & E100_PHY_DEVICE_MASK) != 0
        && (phy & E100_PHY_SERIAL_ONLY) != 0)
        q |= E100_Q_SERIAL;

    /* Intel 82801BA erratum 30: Dynamic Standby left on in the EEPROM */
    if ((chip->ich == 2 || chip->ich == 3
         || (chip->ich == 0 && revision >= E100_REV_82559))
        && (eeprom[E100_EEPROM_ID] & E100_ID_STANDBY) != 0)
        q |= E100_Q_CU_RESUME;

    return q;
}

/* Generation names follow SDM Table 2's revision IDs. */
const char *
e100GenerationName(int revision)
{
    if (revision < 4)
        return "82557";
    if (revision < 6)
        return "82558";
    if (revision < E100_REV_82550)
        return "82559";
    return "82550/82551";
}

void
e100MacFromEeprom(const unsigned short *eeprom, unsigned char *mac)
{
    int i;

    for (i = 0; i < 3; i++) {
        mac[2 * i]     = (unsigned char)(eeprom[i] & 0xFF);
        mac[2 * i + 1] = (unsigned char)(eeprom[i] >> 8);
    }
}

int
e100MacValid(const unsigned char *mac)
{
    int i, zero = 1, ones = 1;

    for (i = 0; i < 6; i++) {
        if (mac[i] != 0x00)
            zero = 0;
        if (mac[i] != 0xFF)
            ones = 0;
    }
    return !zero && !ones && (mac[0] & 0x01) == 0;
}

/* The SDM's recommended configure bytes (SDM 6.4.2.3); see the spec. */
static const unsigned char configTemplate[E100_CONFIG_BYTES] = {
    0x16,       /*  0: 22 bytes                                       */
    0x08,       /*  1: receive FIFO limit 8, transmit 0               */
    0x00,       /*  2: adaptive IFS off                               */
    0x00,       /*  3: no MWI, no read or write alignment             */
    0x00,       /*  4: receive DMA byte count unused                  */
    0x00,       /*  5: transmit DMA byte count unused                 */
    0x32,       /*  6: CNA interrupts, standard TxCB and statistics   */
    0x03,       /*  7: underrun retry 1, discard short frames         */
    0x01,       /*  8: MII interface                                  */
    0x00,       /*  9                                                 */
    0x2E,       /* 10: 7-byte preamble, no source address insertion   */
    0x00,       /* 11                                                 */
    0x60,       /* 12: interframe spacing 6                           */
    0x00,       /* 13                                                 */
    0xF2,       /* 14                                                 */
    0x48,       /* 15                                                 */
    0x00,       /* 16                                                 */
    0x40,       /* 17                                                 */
    0xF2,       /* 18: pad short frames                               */
    0x80,       /* 19: duplex from the PHY's FDX pin                  */
    0x3F,       /* 20                                                 */
    0x05        /* 21                                                 */
};

void
e100BuildConfig(unsigned char *bytes, int revision, unsigned int quirks,
                int promiscuous, int allMulticast)
{
    int i;

    for (i = 0; i < E100_CONFIG_BYTES; i++)
        bytes[i] = configTemplate[i];

    /* Byte 12 bit 0 is reserved on the 82558 and 82559 and "should be set
     * to 1" (SDM 6.4.2.3); on the 82557 it selects linear priority. */
    if (revision >= E100_REV_82558)
        bytes[12] |= 0x01;

    if (quirks & E100_Q_SERIAL) {
        bytes[8] = 0x00;                /* 82503 serial, not MII        */
        bytes[15] |= 0x80;              /* CRS and CDT                  */
    }
    if (promiscuous) {
        bytes[6] |= 0x80;               /* save bad frames              */
        bytes[7] &= (unsigned char)~0x01; /* keep short frames          */
        bytes[15] |= 0x01;              /* promiscuous                  */
    }
    if (promiscuous || allMulticast)
        bytes[21] |= 0x08;              /* all multicast                */
}

void
e100FillMcast(E100McastCB *cb, const unsigned char *addrs, int count)
{
    int i;

    if (count > E100_MAX_MCAST)
        count = E100_MAX_MCAST;
    cb->byteCount = (unsigned short)(count * 6);
    for (i = 0; i < count * 6; i++)
        cb->addr[i] = addrs[i];
}

/*
 * The completion code lands after the last counter, and where that is
 * depends on the layout: 82557 format (16 counters), 82558 extended (19)
 * or 82559 TCO (dword 20, FreeBSD's offset). Configure byte 6 asks for the
 * 82557 format everywhere; accepting all three keeps a part that ignores
 * it readable.
 */
int
e100StatsComplete(const volatile unsigned long *stats)
{
    return stats[16] == E100_DUMP_RESET_DONE
        || stats[19] == E100_DUMP_RESET_DONE
        || stats[20] == E100_DUMP_RESET_DONE;
}

/* FreeBSD's policy (if_fxp.c, fxp_update_stats): any underrun since the
 * last dump raises the threshold one step, up to 192 (1536 bytes). */
unsigned int
e100NextThreshold(unsigned int threshold, unsigned long underruns)
{
    if (underruns != 0 && threshold < E100_TX_THRESHOLD_MAX)
        return threshold + E100_TX_THRESHOLD_STEP;
    return threshold;
}

void
e100DecodeLink(int bmsr, int anar, int anlpar, int intelStatus, E100Link *link)
{
    int common = 0;

    link->up = (bmsr & BMSR_LINK) != 0;
    link->known = 0;
    link->speed100 = 0;
    link->fullDuplex = 0;
    if (!link->up)
        return;

    if (anar >= 0 && anlpar >= 0 && (bmsr & BMSR_AUTONEG_DONE))
        common = anar & anlpar;

    if (common & ANLPAR_100FD) {
        link->speed100 = 1;
        link->fullDuplex = 1;
        link->known = 1;
    } else if (common & ANLPAR_100TX) {
        link->speed100 = 1;
        link->known = 1;
    } else if (common & ANLPAR_10FD) {
        link->fullDuplex = 1;
        link->known = 1;
    } else if (common & ANLPAR_10) {
        link->known = 1;
    } else if (intelStatus >= 0) {
        /* Not negotiated (parallel detection, or forced): Intel PHYs
         * report the result in register 16 (SDM 7.5). */
        link->speed100 = (intelStatus & INTEL_STATUS_100) != 0;
        link->fullDuplex = (intelStatus & INTEL_STATUS_FD) != 0;
        link->known = 1;
    }
}
```

- [ ] **Step 8: Write a stub `E100/IntelE100.drvproj/Default.table` so `test_default_table` has its input**

Task 5 adds the table's other keys. For now, write the complete file:

```
"Title" = "Intel 8255x 10/100 Ethernet";
"Family" = "Network";
"Location" = "";
"Instance" = "0";
"Version" = "1.0";
"Driver Name" = "IntelE100";
"DMA Channels" = "";
"Memory Maps" = "";
"I/O Ports" = "";
"Share IRQ Levels" = "YES";
"Bus Type" = "PCI";
"Network Interface" = "AUTO";
"Auto Detect IDs" = "0x10298086 0x10308086 0x10318086 0x10328086 0x10338086 0x10348086 0x10358086 0x10368086 0x10378086 0x10388086 0x10398086 0x103A8086 0x103B8086 0x103C8086 0x103D8086 0x103E8086 0x10508086 0x10518086 0x10598086 0x10648086 0x10658086 0x10688086 0x10698086 0x10918086 0x10928086 0x10938086 0x10948086 0x12098086 0x12298086 0x24498086 0x27DC8086";
"Class Names" = "IntelE100";
"Server Name" = "IntelE100";
"Driver Version" = "IntelE100 1.0 (8255x family)";
```

- [ ] **Step 9: Run the test to verify it passes**

```bash
powershell.exe -NoProfile -File vm/sync-src.ps1 -Path drivers-i386/network/drvIntelE100
powershell.exe -NoProfile -File vm/guest-remote.ps1 -Run vm/build-i386-e100.sh; echo "exit=$?"
```

Expected:
- `e100_logic_test: all passed`
- `TESTS_RC=0`
- `no apk/pkginfo yet - tests only`
- `exit=0`

Any `FAIL …` line means the implementation is wrong. Fix the code, not the test, unless the test contradicts the spec.

- [ ] **Step 10: Commit**

```bash
git add src/drivers-i386/network/drvIntelE100 vm/build-i386-e100.sh
git commit -m "drvIntelE100: add the 8255x register map and chip, quirk, configure and link logic with unit tests"
```

---

### Task 4: Register-level hardware access, tested against a simulated device

**Files:**
- Create: `LKS/E100Port.h`
- Create: `LKS/E100Hw.h`
- Create: `LKS/E100Hw.c`
- Create: `E100/tests/e100_test_ports.h`
- Create: `E100/tests/e100_hw_test.c`
- Modify: `E100/tests/Makefile` (add the `e100_hw_test` target)

**Interfaces:**
- Consumes: `E100Regs.h` from Task 3.
- Produces, in `E100Hw.h`. `io` is the I/O BAR base, and every `int` return is 1 for success and 0 for a timeout unless noted:
  - `int e100WaitScb(unsigned int io);`
  - `int e100ScbCommand(unsigned int io, unsigned char command);`
  - `int e100ScbCommandPtr(unsigned int io, unsigned char command, unsigned long pointer);` writes GENPTR, then the command.
  - `int e100CuResume(unsigned int io, int nopFirst);`
  - `int e100WaitCuIdle(unsigned int io);`
  - `void e100PortCommand(unsigned int io, unsigned long opcode);` includes the settling delay.
  - `int e100WaitCB(const volatile unsigned short *status, int loops);` waits 2 µs per loop.
  - `int e100EepromAddressBits(unsigned int io);` returns 0 if no EEPROM answers.
  - `unsigned short e100EepromRead(unsigned int io, int addressBits, int word);`
  - `int e100MdiRead(unsigned int io, int phy, int reg);` returns -1 on timeout.
  - `int e100MdiWrite(unsigned int io, int phy, int reg, unsigned short value);`
- Produces `E100Port.h` macros: `E100_INB/INW/INL(port)`, `E100_OUTB/OUTW/OUTL(port, value)` and `E100_DELAY(us)`.

- [ ] **Step 1: Write `LKS/E100Port.h`**

```c
/*
 * E100Port.h - port I/O and delay for E100Hw.c and IntelE100.m.
 *
 * Copyright (c) 2026, Pat Raynor. BSD-2-Clause; see LICENSE.
 *
 * In the kernel these are DriverKit's inline port instructions and
 * IODelay. tests/ builds with -DE100_HOST_TEST, which swaps in a
 * simulated device (tests/e100_test_ports.h).
 */
#ifndef E100PORT_H
#define E100PORT_H

#ifdef E100_HOST_TEST
#include "e100_test_ports.h"
#else
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/ioPorts.h>
#define E100_INB(p)             inb((IOEISAPortAddress)(p))
#define E100_INW(p)             inw((IOEISAPortAddress)(p))
#define E100_INL(p)             inl((IOEISAPortAddress)(p))
#define E100_OUTB(p, v)         outb((IOEISAPortAddress)(p), (v))
#define E100_OUTW(p, v)         outw((IOEISAPortAddress)(p), (v))
#define E100_OUTL(p, v)         outl((IOEISAPortAddress)(p), (v))
#define E100_DELAY(us)          IODelay(us)
#endif

#endif
```

- [ ] **Step 2: Write `LKS/E100Hw.h`**

```c
/*
 * E100Hw.h - register-level access to the 8255x.
 *
 * Copyright (c) 2026, Pat Raynor. BSD-2-Clause; see LICENSE.
 *
 * io is the base of the I/O BAR. Functions returning int give 1 for
 * success and 0 for a timeout unless noted.
 */
#ifndef E100HW_H
#define E100HW_H

int e100WaitScb(unsigned int io);
int e100ScbCommand(unsigned int io, unsigned char command);
int e100ScbCommandPtr(unsigned int io, unsigned char command,
                      unsigned long pointer);
int e100CuResume(unsigned int io, int nopFirst);
int e100WaitCuIdle(unsigned int io);
void e100PortCommand(unsigned int io, unsigned long opcode);
int e100WaitCB(const volatile unsigned short *status, int loops);

/* Address width in bits (6 or 8), or 0 when no EEPROM answers. */
int e100EepromAddressBits(unsigned int io);
unsigned short e100EepromRead(unsigned int io, int addressBits, int word);

/* The register value, or -1 when the MDI never reports ready. */
int e100MdiRead(unsigned int io, int phy, int reg);
int e100MdiWrite(unsigned int io, int phy, int reg, unsigned short value);

#endif
```

- [ ] **Step 3: Write `E100/tests/e100_test_ports.h`**

```c
/*
 * e100_test_ports.h - the simulated device E100Hw.c talks to under
 * -DE100_HOST_TEST. e100_hw_test.c implements these.
 *
 * Copyright (c) 2026, Pat Raynor. BSD-2-Clause; see ../LICENSE.
 */
#ifndef E100_TEST_PORTS_H
#define E100_TEST_PORTS_H

unsigned char e100TestInb(unsigned int port);
unsigned short e100TestInw(unsigned int port);
unsigned long e100TestInl(unsigned int port);
void e100TestOutb(unsigned int port, unsigned char value);
void e100TestOutw(unsigned int port, unsigned short value);
void e100TestOutl(unsigned int port, unsigned long value);
void e100TestDelay(unsigned int microseconds);

#define E100_INB(p)             e100TestInb(p)
#define E100_INW(p)             e100TestInw(p)
#define E100_INL(p)             e100TestInl(p)
#define E100_OUTB(p, v)         e100TestOutb((p), (v))
#define E100_OUTW(p, v)         e100TestOutw((p), (v))
#define E100_OUTL(p, v)         e100TestOutl((p), (v))
#define E100_DELAY(us)          e100TestDelay(us)

#endif
```

- [ ] **Step 4: Write the failing test `E100/tests/e100_hw_test.c`**

```c
/*
 * e100_hw_test.c - unit tests for E100Hw.c against a simulated device:
 * a microwire EEPROM of 6 or 8 address bits, one MDI PHY, and the SCB
 * command byte.
 *
 * Copyright (c) 2026, Pat Raynor. BSD-2-Clause; see ../LICENSE.
 */
#include <stdio.h>

#include "E100Regs.h"
#include "E100Hw.h"
#include "e100_test_ports.h"

#define IO 0xC000U

static int failures;

static void
check(int ok, const char *test, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL %s: %s\n", test, what);
        failures++;
    }
}

/* --- the simulated device ---------------------------------------------- */

static unsigned long delayTotal;
static int seq;                         /* orders writes across registers */

static int scbStuck;                    /* the command byte never clears  */
static unsigned char scbStatus;
static unsigned char cmdLog[8];
static int cmdCount, cmdSeq, genptrSeq;
static unsigned long genptr, portValue;

static unsigned short eeWords[256];
static int eeAddrBits, eePresent, eeOpcode;
static int eeCs, eeSk, eeDo, eePhase, eeBitsIn;
static unsigned int eeShift;
static unsigned short eeData;

static unsigned short phyRegs[32];
static int phyAddress, mdiHang;
static unsigned long mdiValue;

static void
resetSim(void)
{
    int i;

    delayTotal = 0;
    seq = 0;
    scbStuck = 0;
    scbStatus = 0;
    cmdCount = cmdSeq = genptrSeq = 0;
    genptr = portValue = 0;
    for (i = 0; i < 256; i++)
        eeWords[i] = (unsigned short)(0x1000 + i);
    eeAddrBits = 6;
    eePresent = 1;
    eeOpcode = -1;
    eeCs = eeSk = 0;
    eeDo = 1;
    eePhase = eeBitsIn = 0;
    eeShift = 0;
    for (i = 0; i < 32; i++)
        phyRegs[i] = 0;
    phyAddress = 1;
    mdiHang = 0;
    mdiValue = 0;
}

/* A 93C46/93C66-style part: acts on the rising edge of SK while CS is high. */
static void
eeWrite(unsigned short v)
{
    int cs = (v & E100_EE_CS) != 0;
    int sk = (v & E100_EE_SK) != 0;
    int di = (v & E100_EE_DI) != 0;

    if (!cs) {
        eeCs = eeSk = 0;
        eeDo = 1;
        return;
    }
    if (!eeCs) {
        eePhase = eeBitsIn = 0;
        eeShift = 0;
    }
    eeCs = 1;
    if (sk && !eeSk && eePresent) {
        switch (eePhase) {
        case 0:                         /* opcode */
            eeShift = (eeShift << 1) | (unsigned int)di;
            if (++eeBitsIn == 3) {
                eeOpcode = (int)eeShift;
                eePhase = 1;
                eeBitsIn = 0;
                eeShift = 0;
            }
            break;
        case 1:                         /* address */
            eeShift = (eeShift << 1) | (unsigned int)di;
            if (++eeBitsIn == eeAddrBits) {
                eeData = eeWords[eeShift];
                eeDo = 0;               /* the dummy zero */
                eePhase = 2;
                eeBitsIn = 0;
            }
            break;
        default:                        /* data, most significant first */
            eeDo = (eeData >> (15 - eeBitsIn)) & 1;
            eeBitsIn++;
            break;
        }
    }
    eeSk = sk;
}

unsigned char
e100TestInb(unsigned int port)
{
    if (port == IO + E100_SCB_CMD)
        return (unsigned char)(scbStuck ? E100_CUC_START : 0);
    if (port == IO + E100_SCB_STATUS)
        return scbStatus;
    return 0xFF;
}

unsigned short
e100TestInw(unsigned int port)
{
    if (port == IO + E100_EECTL)
        return (unsigned short)(eeDo ? E100_EE_DO : 0);
    return 0xFFFF;
}

unsigned long
e100TestInl(unsigned int port)
{
    if (port == IO + E100_MDICTL)
        return mdiValue;
    return 0xFFFFFFFFUL;
}

void
e100TestOutb(unsigned int port, unsigned char value)
{
    if (port == IO + E100_SCB_CMD) {
        if (cmdCount < 8)
            cmdLog[cmdCount++] = value;
        cmdSeq = ++seq;
    }
}

void
e100TestOutw(unsigned int port, unsigned short value)
{
    if (port == IO + E100_EECTL)
        eeWrite(value);
}

void
e100TestOutl(unsigned int port, unsigned long value)
{
    int phy, reg;

    if (port == IO + E100_SCB_GENPTR) {
        genptr = value;
        genptrSeq = ++seq;
    } else if (port == IO + E100_PORT) {
        portValue = value;
    } else if (port == IO + E100_MDICTL) {
        phy = (int)((value >> E100_MDI_PHY_SHIFT) & 0x1F);
        reg = (int)((value >> E100_MDI_REG_SHIFT) & 0x1F);
        if (mdiHang) {
            mdiValue = 0;
        } else if (phy != phyAddress) {
            mdiValue = E100_MDI_READY;  /* reads as 0, as QEMU's does */
        } else {
            if ((value & 0x0C000000UL) == E100_MDI_OP_WRITE)
                phyRegs[reg] = (unsigned short)(value & 0xFFFFUL);
            mdiValue = E100_MDI_READY | phyRegs[reg];
        }
    }
}

void
e100TestDelay(unsigned int microseconds)
{
    delayTotal += microseconds;
}

/* --- tests ----------------------------------------------------------- */

static void
test_scb_command(void)
{
    static const char t[] = "SCB command";

    resetSim();
    check(e100ScbCommandPtr(IO, E100_CUC_START, 0x00123450UL) == 1, t, "accepted");
    check(genptr == 0x00123450UL, t, "pointer written");
    check(cmdCount == 1 && cmdLog[0] == E100_CUC_START, t, "command written");
    check(genptrSeq != 0 && genptrSeq < cmdSeq, t, "pointer before command");

    resetSim();
    scbStuck = 1;
    check(e100ScbCommand(IO, E100_CUC_RESUME) == 0, t, "reports a busy SCB");
    check(cmdCount == 0, t, "writes nothing while busy");
    check(delayTotal >= 20000UL, t, "waits at least 20 ms first");
}

static void
test_cu_resume(void)
{
    static const char t[] = "CU resume";

    resetSim();
    check(e100CuResume(IO, 0) == 1, t, "plain resume accepted");
    check(cmdCount == 1 && cmdLog[0] == E100_CUC_RESUME, t, "one command");

    resetSim();
    check(e100CuResume(IO, 1) == 1, t, "erratum resume accepted");
    check(cmdCount == 2 && cmdLog[0] == E100_CUC_NOP
          && cmdLog[1] == E100_CUC_RESUME, t, "NOP, then resume");
}

static void
test_port_and_waits(void)
{
    static const char t[] = "PORT and waits";
    volatile unsigned short status;

    resetSim();
    e100PortCommand(IO, E100_PORT_SELECTIVE_RESET);
    check(portValue == E100_PORT_SELECTIVE_RESET, t, "PORT written");
    check(delayTotal >= 10UL, t, "settles at least 10 us");

    resetSim();
    status = E100_CB_C | E100_CB_OK;
    check(e100WaitCB(&status, 5) == 1, t, "completed CB");
    status = 0;
    check(e100WaitCB(&status, 5) == 0, t, "CB timeout");
    check(delayTotal == 10UL, t, "2 us per loop");

    resetSim();
    scbStatus = 0x40;
    check(e100WaitCuIdle(IO) == 0, t, "CU suspended is not idle");
    scbStatus = 0x10;
    check(e100WaitCuIdle(IO) == 1, t, "RU state does not matter");
}

static void
test_eeprom(int bits)
{
    static const char t[] = "EEPROM";
    int last = (1 << bits) - 1;

    resetSim();
    eeAddrBits = bits;
    check(e100EepromAddressBits(IO) == bits, t, "address width found");
    check(eeOpcode == E100_EE_OP_READ, t, "read opcode 110b");
    check(e100EepromRead(IO, bits, 5) == 0x1005, t, "word 5");
    check(e100EepromRead(IO, bits, last) == 0x1000 + last, t, "last word");
    check(!eeCs, t, "deselected afterwards");
}

static void
test_eeprom_absent(void)
{
    resetSim();
    eePresent = 0;
    check(e100EepromAddressBits(IO) == 0, "EEPROM absent", "reports 0");
}

static void
test_mdi(void)
{
    static const char t[] = "MDI";

    resetSim();
    phyRegs[MII_PHYID1] = INTEL_PHYID1;
    check(e100MdiRead(IO, 1, MII_PHYID1) == INTEL_PHYID1, t, "read");
    check(e100MdiRead(IO, 5, MII_PHYID1) == 0, t, "no PHY at 5");
    check(e100MdiWrite(IO, 1, MII_BMCR, 0x1200) == 1 && phyRegs[MII_BMCR] == 0x1200,
          t, "write");
    mdiHang = 1;
    check(e100MdiRead(IO, 1, MII_BMSR) == -1, t, "read timeout");
    check(e100MdiWrite(IO, 1, MII_BMCR, 0) == 0, t, "write timeout");
}

int
main(void)
{
    test_scb_command();
    test_cu_resume();
    test_port_and_waits();
    test_eeprom(6);
    test_eeprom(8);
    test_eeprom_absent();
    test_mdi();
    if (failures == 0)
        printf("e100_hw_test: all passed\n");
    return failures != 0;
}
```

- [ ] **Step 5: Add the target to `E100/tests/Makefile`**

Change `all:` to build both tests, add the rule, and run both in `test:`. Recipe lines start with a TAB. The file becomes:

```make
# Unit tests for drvIntelE100's plain C, built and run on the build guest:
#   cd tests && gnumake check
# Same flags as drvAHCI's tests: -traditional-cpp uses GNU cpp, because
# under -ansi cpp-precomp rewrites the system headers' __inline, which
# gcc 2.7.2.1 then rejects.
CC = cc
CFLAGS = -ansi -pedantic -Wall -Werror -traditional-cpp
LKS = ../IntelE100.drvproj/IntelE100.lksproj
INCLUDES = -I. -I$(LKS)

.PHONY: all check test clean

all: e100_logic_test e100_hw_test

e100_logic_test: e100_logic_test.c $(LKS)/E100Logic.c $(LKS)/E100Logic.h $(LKS)/E100Regs.h
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ e100_logic_test.c $(LKS)/E100Logic.c

e100_hw_test: e100_hw_test.c e100_test_ports.h $(LKS)/E100Hw.c $(LKS)/E100Hw.h $(LKS)/E100Port.h $(LKS)/E100Regs.h
	$(CC) $(CFLAGS) -DE100_HOST_TEST $(INCLUDES) -o $@ e100_hw_test.c $(LKS)/E100Hw.c

check: test

test: all
	./e100_logic_test
	./e100_hw_test

clean:
	rm -f e100_logic_test e100_hw_test
```

- [ ] **Step 6: Run the tests to verify they fail**

```bash
powershell.exe -NoProfile -File vm/sync-src.ps1 -Path drivers-i386/network/drvIntelE100
powershell.exe -NoProfile -File vm/guest-remote.ps1 -Run vm/build-i386-e100.sh; echo "exit=$?"
```

Expected:
- `TESTS_RC=1` and `exit=1`.
- gnumake has no rule to make `…/E100Hw.c`.

- [ ] **Step 7: Implement `LKS/E100Hw.c`**

```c
/*
 * E100Hw.c - register-level access to the 8255x: SCB commands, PORT, the
 * microwire EEPROM and the MDI. Every access goes through the macros in
 * E100Port.h, so tests/ runs this against a simulated device.
 *
 * Copyright (c) 2026, Pat Raynor. BSD-2-Clause; see LICENSE.
 */
#include "E100Regs.h"
#include "E100Hw.h"
#include "E100Port.h"

#define SCB_WAIT_LOOPS  10000   /* x 2 us = 20 ms, what FreeBSD allows    */
#define CU_IDLE_LOOPS   500     /* x 2 us = 1 ms                          */
#define MDI_WAIT_LOOPS  1000    /* x 10 us = 10 ms                        */
#define EE_PHASE_US     4       /* SK at least 4 us each way (SDM 6.3.4)  */

/* The SCB command byte reads 0 once the chip has accepted a command. */
int
e100WaitScb(unsigned int io)
{
    int i;

    for (i = 0; i < SCB_WAIT_LOOPS; i++) {
        if (E100_INB(io + E100_SCB_CMD) == 0)
            return 1;
        E100_DELAY(2);
    }
    return 0;
}

int
e100ScbCommand(unsigned int io, unsigned char command)
{
    if (!e100WaitScb(io))
        return 0;
    E100_OUTB(io + E100_SCB_CMD, command);
    return 1;
}

int
e100ScbCommandPtr(unsigned int io, unsigned char command, unsigned long pointer)
{
    if (!e100WaitScb(io))
        return 0;
    E100_OUTL(io + E100_SCB_GENPTR, pointer);
    E100_OUTB(io + E100_SCB_CMD, command);
    return 1;
}

/*
 * CU Resume, optionally preceded by a CU NOP. The NOP is FreeBSD's
 * workaround for Intel 82801BA erratum 30 (if_fxp.c, fxp_scb_cmd): with
 * Dynamic Standby enabled in the EEPROM, a resume that arrives as the chip
 * drops into standby can violate the PCI protocol.
 */
int
e100CuResume(unsigned int io, int nopFirst)
{
    if (!e100WaitScb(io))
        return 0;
    if (nopFirst) {
        E100_OUTB(io + E100_SCB_CMD, E100_CUC_NOP);
        if (!e100WaitScb(io))
            return 0;
    }
    E100_OUTB(io + E100_SCB_CMD, E100_CUC_RESUME);
    return 1;
}

int
e100WaitCuIdle(unsigned int io)
{
    int i;

    for (i = 0; i < CU_IDLE_LOOPS; i++) {
        if ((E100_INB(io + E100_SCB_STATUS) & E100_CUS_MASK) == 0)
            return 1;
        E100_DELAY(2);
    }
    return 0;
}

void
e100PortCommand(unsigned int io, unsigned long opcode)
{
    E100_OUTL(io + E100_PORT, opcode);
    /* SDM 6.2: leave the SCB alone for 10 system plus 5 transmit clocks,
     * about 10 us; FreeBSD waits 50 after a reset. */
    E100_DELAY(50);
}

int
e100WaitCB(const volatile unsigned short *status, int loops)
{
    while (loops-- > 0) {
        if (*status & E100_CB_C)
            return 1;
        E100_DELAY(2);
    }
    return 0;
}

/* --- microwire EEPROM (SDM 6.3.4) ------------------------------------ */

static void
eeOut(unsigned int io, int bit)
{
    unsigned short v = (unsigned short)(E100_EE_CS | (bit ? E100_EE_DI : 0));

    E100_OUTW(io + E100_EECTL, v);
    E100_DELAY(EE_PHASE_US);
    E100_OUTW(io + E100_EECTL, (unsigned short)(v | E100_EE_SK));
    E100_DELAY(EE_PHASE_US);
    E100_OUTW(io + E100_EECTL, v);
    E100_DELAY(EE_PHASE_US);
}

static int
eeIn(unsigned int io)
{
    int bit;

    E100_OUTW(io + E100_EECTL, E100_EE_CS | E100_EE_SK);
    E100_DELAY(EE_PHASE_US);
    bit = (E100_INW(io + E100_EECTL) & E100_EE_DO) ? 1 : 0;
    E100_OUTW(io + E100_EECTL, E100_EE_CS);
    E100_DELAY(EE_PHASE_US);
    return bit;
}

static void
eeStartRead(unsigned int io)
{
    int i;

    E100_OUTW(io + E100_EECTL, E100_EE_CS);
    E100_DELAY(EE_PHASE_US);
    for (i = 2; i >= 0; i--)
        eeOut(io, (E100_EE_OP_READ >> i) & 1);
}

static void
eeStop(unsigned int io)
{
    E100_OUTW(io + E100_EECTL, 0);
    E100_DELAY(EE_PHASE_US);
}

/*
 * SDM 6.3.4.2: after a read opcode, clock address zeros until the part
 * drives its dummy zero on EEDO; the number clocked is the address width.
 */
int
e100EepromAddressBits(unsigned int io)
{
    int bits, i, found = 0;

    eeStartRead(io);
    for (bits = 1; bits <= 8; bits++) {
        eeOut(io, 0);
        if ((E100_INW(io + E100_EECTL) & E100_EE_DO) == 0) {
            found = bits;
            break;
        }
    }
    for (i = 0; i < 16; i++)
        (void)eeIn(io);
    eeStop(io);
    return found;
}

unsigned short
e100EepromRead(unsigned int io, int addressBits, int word)
{
    unsigned short data = 0;
    int i;

    eeStartRead(io);
    for (i = addressBits - 1; i >= 0; i--)
        eeOut(io, (word >> i) & 1);
    for (i = 0; i < 16; i++)
        data = (unsigned short)((data << 1) | eeIn(io));
    eeStop(io);
    return data;
}

/* --- MDI (SDM 6.3.5) ------------------------------------------------- */

static int
mdiWait(unsigned int io, unsigned long *value)
{
    int i;

    for (i = 0; i < MDI_WAIT_LOOPS; i++) {
        *value = E100_INL(io + E100_MDICTL);
        if (*value & E100_MDI_READY)
            return 1;
        E100_DELAY(10);
    }
    return 0;
}

int
e100MdiRead(unsigned int io, int phy, int reg)
{
    unsigned long v;

    E100_OUTL(io + E100_MDICTL, E100_MDI_OP_READ
              | ((unsigned long)phy << E100_MDI_PHY_SHIFT)
              | ((unsigned long)reg << E100_MDI_REG_SHIFT));
    if (!mdiWait(io, &v))
        return -1;
    return (int)(v & 0xFFFFUL);
}

int
e100MdiWrite(unsigned int io, int phy, int reg, unsigned short value)
{
    unsigned long v;

    E100_OUTL(io + E100_MDICTL, E100_MDI_OP_WRITE
              | ((unsigned long)phy << E100_MDI_PHY_SHIFT)
              | ((unsigned long)reg << E100_MDI_REG_SHIFT)
              | (unsigned long)value);
    return mdiWait(io, &v);
}
```

- [ ] **Step 8: Run the tests to verify they pass**

```bash
powershell.exe -NoProfile -File vm/sync-src.ps1 -Path drivers-i386/network/drvIntelE100
powershell.exe -NoProfile -File vm/guest-remote.ps1 -Run vm/build-i386-e100.sh; echo "exit=$?"
```

Expected:
- `e100_logic_test: all passed`
- `e100_hw_test: all passed`
- `TESTS_RC=0` and `exit=0`

- [ ] **Step 9: Commit**

```bash
git add src/drivers-i386/network/drvIntelE100
git commit -m "drvIntelE100: add SCB, PORT, EEPROM and MDI access with tests against a simulated device"
```

---

### Task 5: Package the driver and prove identification under QEMU

This task builds the full bundle with an identification-only class. The class probes, logs what it finds, and declines to attach. That proves the build, the packaging, the install and the probe path before any DMA code exists.

**Files:**
- Create in `E100/`: `Makefile`, `Makefile.preamble`, `PB.project`, `LICENSE`, `NOTICE`, `apk/pkginfo`
- Create in `E100/IntelE100.drvproj/`: `Makefile`, `Makefile.preamble`, `PB.project`, `DriverInfo`, `Instance0.table`, `English.lproj/Localizable.strings`, `English.lproj/DriverHelp/TableOfContents`
- Keep `E100/IntelE100.drvproj/Default.table` from Task 3.
- Create in `LKS/`: `Makefile`, `Makefile.preamble`, `PB.project`, `Load_Commands.sect`, `IntelE100.m`
- Create: `vm/e100-boot.py`

**Interfaces:**
- Consumes:
  - `E100Logic.h` and `E100Hw.h` from Tasks 3–4
  - `guest-console.Guest(image=, nic=)` and `e100-pcap.summarize` from Task 1
  - `guest-remote.ps1` from Task 2
- Produces:
  - `vm/e100-boot.py BUNDLE MODEL MODE [PORT]`: `MODE` is `probe`, `single` or `multi`, and `BUNDLE` is an `.apk` or an `IntelE100.config` directory. It exits 1 on a panic or, in `single` mode, on one-way traffic.
  - `IntelE100.m` methods kept by Task 6: `+probe:`, `-_findPhy:`, and the identification part of `-initFromDeviceDescription:`.

- [ ] **Step 1: Write the aggregate project files in `E100/`**

`E100/Makefile`:

```make
#
# Generated by the NeXT Project Builder.
#
# NOTE: Do NOT change this file -- Project Builder maintains it.
#
# Put all of your customizations in files called Makefile.preamble
# and Makefile.postamble (both optional), and Makefile will include them.
#

NAME = IntelE100

PROJECTVERSION = 2.6
PROJECT_TYPE = Aggregate
LANGUAGE = English

BUNDLES = IntelE100.drvproj

OTHERSRCS = Makefile Makefile.preamble

MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
CODE_GEN_STYLE = DYNAMIC
MAKEFILE = aggregate.make
LIBS =
DEBUG_LIBS = $(LIBS)
PROF_LIBS = $(LIBS)

include $(MAKEFILEDIR)/platform.make

-include Makefile.preamble

include $(MAKEFILEDIR)/$(MAKEFILE)

-include Makefile.postamble

-include Makefile.dependencies
```

`E100/Makefile.preamble`:

```make
INCLUDED_ARCHS = i386
```

`E100/PB.project`:

```
{
    DYNAMIC_CODE_GEN = YES;
    FILESTABLE = {
        OTHER_SOURCES = (Makefile, Makefile.preamble);
        SUBPROJECTS = (IntelE100.drvproj);
    };
    LANGUAGE = English;
    LOCALIZABLE_FILES = {};
    MAKEFILEDIR = "$(MAKEFILEPATH)/pb_makefiles";
    NEXTSTEP_BUILDTOOL = /bin/gnumake;
    PROJECTNAME = IntelE100;
    PROJECTTYPE = Aggregate;
    PROJECTVERSION = 2.6;
}
```

`E100/apk/pkginfo`:

```
pkgname = intele100
pkgver = 1.0
arch = i386
pkgdesc = Intel 8255x (e100) 10/100 Ethernet device driver
maintainer = Pat Raynor
license = BSD
makedepends = build-base, drivertools, driverkit, kernload
```

`E100/LICENSE`:

```
BSD 2-Clause License

Copyright (c) 2026, Pat Raynor

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

`E100/NOTICE`:

```
drvIntelE100 - acknowledgements and notices

This driver is licensed under the BSD 2-Clause License; see LICENSE. This
file records what was consulted while writing it, and what was not.

The driver is original work written for RhapsodiOS. No source code from any
of the works below was copied into it, and none of them is redistributed
here. Where a decision rests on one of them, the source comment says so.


Intel - "8255x 10/100 Mbps Ethernet Controller Family Open Source Software
Developer Manual", revision 1.0 (January 2003)

    The primary specification: the CSR layout, the SCB, the command and
    receive units, the command block, TxCB and RFD formats, the configure
    bytes, the PORT commands, the microwire EEPROM protocol, the MDI and
    the statistics dump.


FreeBSD - sys/dev/fxp (if_fxp.c, if_fxpreg.h, if_fxpvar.h)
SPDX: BSD-2-Clause

    Consulted for what the SDM leaves out:
      - the list of device IDs, including the ICH-integrated parts
      - the EEPROM word map, the 0xBABA checksum and the PHY word bits
      - the rule for a part's effective revision
      - the 82557 receive-lockup condition and its recovery
      - the Dynamic Standby / CU-resume erratum (Intel 82801BA spec
        update, erratum 30) and its CU NOP workaround
      - the transmit-threshold policy
    Its values were written down in this driver's own words and code.


Linux - drivers/net/ethernet/intel/e100.c (GPL-2.0)

    Background reading only. Nothing in this driver is copied from it or
    derived from it, and it was not used as an implementation reference.


RhapsodiOS - drvIntel1000 (Pro1000) and drvAHCI

    The in-tree drivers whose conventions this one follows: the bundle
    and kernel-server layout, the DMA allocation idiom, the interrupt
    re-enable sequence, and plain-C logic with unit tests run on the build
    guest.


If you copy code from FreeBSD into this tree, its copyright notice and
licence terms must travel with it. Nothing here relieves that.
```

- [ ] **Step 2: Write the driver bundle files in `E100/IntelE100.drvproj/`**

`Makefile`:

```make
#
# Generated by the NeXT Project Builder.
#
# NOTE: Do NOT change this file -- Project Builder maintains it.
#
# Put all of your customizations in files called Makefile.preamble
# and Makefile.postamble (both optional), and Makefile will include them.
#

NAME = IntelE100

PROJECTVERSION = 2.6
PROJECT_TYPE = Driver
LANGUAGE = English

LOCAL_RESOURCES = Localizable.strings DriverHelp

GLOBAL_RESOURCES = Default.table Instance0.table

CLASSES =

HFILES =

TOOLS = IntelE100.lksproj

OTHERSRCS = Makefile Makefile.preamble DriverInfo

MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
CODE_GEN_STYLE = DYNAMIC
MAKEFILE = driver.make
NEXTSTEP_INSTALLDIR = $(NEXT_ROOT)/private/Drivers
LIBS =
DEBUG_LIBS = $(LIBS)
PROF_LIBS = $(LIBS)
BUNDLE_EXTENSION = config

FRAMEWORK_PATHS = -F$(SYSTEM_LIBRARY_DIR)/PrivateFrameworks
FRAMEWORKS =

include $(MAKEFILEDIR)/platform.make

-include Makefile.preamble

include $(MAKEFILEDIR)/$(MAKEFILE)

-include Makefile.postamble

-include Makefile.dependencies
```

`Makefile.preamble`:

```make
INCLUDED_ARCHS = i386
```

`PB.project`:

```
{
    BUNDLE_EXTENSION = config;
    DYNAMIC_CODE_GEN = YES;
    FILESTABLE = {
        OTHER_RESOURCES = (Default.table, Instance0.table, Localizable.strings);
        OTHER_SOURCES = (Makefile, Makefile.preamble, DriverInfo);
        SUBPROJECTS = (IntelE100.lksproj);
    };
    LANGUAGE = English;
    LOCALIZABLE_FILES = {
        Localizable.strings = Localizable.strings;
    };
    MAKEFILEDIR = "$(MAKEFILEPATH)/pb_makefiles";
    NEXTSTEP_BUILDTOOL = /bin/gnumake;
    NEXTSTEP_INSTALLDIR = "$(NEXT_ROOT)/private/Drivers";
    PROJECTNAME = IntelE100;
    PROJECTTYPE = Driver;
    PROJECTVERSION = 2.6;
}
```

`DriverInfo`:

```
#
# used by geninfo: DRIVER_NAME is the name which appears on the
# installer window
#
DRIVER_NAME="IntelE100"
DEFAULT_DRIVER_VERSION="1.0";
```

`Instance0.table`. It is shaped for QEMU `-M pc` with the NIC at `addr=03.0`, where SeaBIOS routes INTA to IRQ 11. `"IRQ Levels"` is required; without it DriverKit hands over no interrupt (Pro1000's `README-Instance0.md`).

```
"Title" = "Intel 8255x 10/100 Ethernet";
"Family" = "Network";
"Location" = "";
"Instance" = "0";
"Version" = "1.0";
"Driver Name" = "IntelE100";
"DMA Channels" = "";
"Memory Maps" = "";
"I/O Ports" = "";
"IRQ Levels" = "11";
"Share IRQ Levels" = "YES";
"Bus Type" = "PCI";
"Network Interface" = "AUTO";
"Auto Detect IDs" = "0x10298086 0x10308086 0x10318086 0x10328086 0x10338086 0x10348086 0x10358086 0x10368086 0x10378086 0x10388086 0x10398086 0x103A8086 0x103B8086 0x103C8086 0x103D8086 0x103E8086 0x10508086 0x10518086 0x10598086 0x10648086 0x10658086 0x10688086 0x10698086 0x10918086 0x10928086 0x10938086 0x10948086 0x12098086 0x12298086 0x24498086 0x27DC8086";
"Class Names" = "IntelE100";
"Server Name" = "IntelE100";
"Driver Version" = "IntelE100 1.0 (8255x family)";
```

`English.lproj/Localizable.strings`:

```
/* The first key must match "Server Name" in Default.table. */
"IntelE100" = "Intel 8255x 10/100";
"Long Name" = "Intel 8255x (EtherExpress PRO/100) 10/100 Ethernet Adapter";
```

`English.lproj/DriverHelp/TableOfContents`:

```
Intel 8255x 10/100 Ethernet
```

- [ ] **Step 3: Write the kernel server files in `LKS/`**

`Makefile`:

```make
#
# Generated by the NeXT Project Builder.
#
# NOTE: Do NOT change this file -- Project Builder maintains it.
#
# Put all of your customizations in files called Makefile.preamble
# and Makefile.postamble (both optional), and Makefile will include them.
#

NAME = IntelE100

PROJECTVERSION = 2.6
PROJECT_TYPE = Kernel Server
LANGUAGE = English

CFILES = E100Hw.c E100Logic.c

CLASSES = IntelE100.m

HFILES = E100Regs.h E100Logic.h E100Hw.h E100Port.h

OTHERSRCS = Load_Commands.sect Makefile Makefile.preamble

MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
CODE_GEN_STYLE = DYNAMIC
MAKEFILE = kernelserver.make
NEXTSTEP_INSTALLDIR = $(NEXT_ROOT)/private/Drivers
LIBS =
DEBUG_LIBS = $(LIBS)
PROF_LIBS = $(LIBS)

include $(MAKEFILEDIR)/platform.make

-include Makefile.preamble

include $(MAKEFILEDIR)/$(MAKEFILE)

-include Makefile.postamble

-include Makefile.dependencies
```

`Makefile.preamble`:

```make
INCLUDED_ARCHS = i386
```

`PB.project`:

```
{
    DYNAMIC_CODE_GEN = NO;
    FILESTABLE = {
        C_FILES = (E100Hw.c, E100Logic.c);
        CLASSES = (IntelE100.m);
        H_FILES = (E100Regs.h, E100Logic.h, E100Hw.h, E100Port.h);
        OTHER_SOURCES = (Load_Commands.sect, Makefile, Makefile.preamble);
    };
    LANGUAGE = English;
    LOCALIZABLE_FILES = {};
    MAKEFILEDIR = "$(MAKEFILEPATH)/pb_makefiles";
    NEXTSTEP_BUILDTOOL = /bin/gnumake;
    NEXTSTEP_INSTALLDIR = "$(NEXT_ROOT)/private/Drivers";
    PROJECTNAME = IntelE100;
    PROJECTTYPE = "Kernel Server";
    PROJECTVERSION = 2.6;
}
```

`Load_Commands.sect`:

```
#
# Load commands for the IntelE100 kernel server.
#
# WIRE only, like every driver in this tree that has been built. It is
# loaded as a boot driver, and boot drivers are never unloaded.
#
WIRE
```

- [ ] **Step 4: Write the identification-only `LKS/IntelE100.m`**

```objc
/*
 * IntelE100.m - Intel 8255x (e100) 10/100 ethernet driver for RhapsodiOS
 * i386.
 *
 * Copyright (c) 2026, Pat Raynor. BSD-2-Clause; see LICENSE.
 *
 * IDENTIFICATION-ONLY BUILD: this finds the part, reads its EEPROM and
 * PHY, logs them, and declines to attach. The full driver replaces this
 * file.
 */

#import <driverkit/IODevice.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/i386/directDevice.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IOEthernet.h>

#import "E100Regs.h"
#import "E100Logic.h"
#import "E100Hw.h"
#import "E100Port.h"

#define E100_VENDOR     0x8086

@interface IntelE100 : IOEthernet
{
    unsigned short      ioBase;
    const E100Chip     *chip;
    int                 revision;
    unsigned int        quirks;
    int                 irqCount;
    int                 phyAddr;
    unsigned short      phyId1, phyId2;
}
+ (BOOL)probe:(IODeviceDescription *)devDesc;
- initFromDeviceDescription:(IODeviceDescription *)devDesc;
- (void)_findPhy:(unsigned short)phyWord;
@end

@implementation IntelE100

+ (BOOL)probe:(IODeviceDescription *)devDesc
{
    IntelE100 *dev = [self alloc];

    if (dev == nil)
        return NO;
    return [dev initFromDeviceDescription:devDesc] != nil;
}

- initFromDeviceDescription:(IODeviceDescription *)devDesc
{
    IOPCIConfigSpace    config;
    unsigned long       command;
    unsigned short      ee[E100_EEPROM_WORDS_KEPT];
    unsigned short      sum, word;
    unsigned char       mac[6];
    int                 eeBits, words, i;

    if ([super initFromDeviceDescription:devDesc] == nil)
        return nil;

    if ([IODirectDevice getPCIConfigSpace:&config
                    withDeviceDescription:devDesc] != IO_R_SUCCESS) {
        IOLog("IntelE100: cannot read PCI configuration space\n");
        [self free];
        return nil;
    }
    if (config.VendorID != E100_VENDOR) {
        IOLog("IntelE100: vendor %04x is not Intel\n",
              (unsigned int)config.VendorID);
        [self free];
        return nil;
    }
    chip = e100ChipLookup(config.DeviceID, (unsigned char)config.RevisionID);
    if (chip == 0) {
        IOLog("IntelE100: device %04x is not an 8255x this driver knows\n",
              (unsigned int)config.DeviceID);
        [self free];
        return nil;
    }

    /*
     * The CSRs are decoded through the I/O BAR as well as the memory BAR,
     * and port I/O needs no mapping. Scan for it rather than assume BAR1.
     */
    ioBase = 0;
    for (i = 0; i < 6; i++) {
        unsigned long bar = config.BaseAddress[i];

        if ((bar & 1UL) && (bar & 0xFFFFFFFCUL) != 0UL
            && (bar & 0xFFFFFFFCUL) <= 0xFFFFUL) {
            ioBase = (unsigned short)(bar & 0xFFFCUL);
            break;
        }
    }
    if (ioBase == 0) {
        IOLog("IntelE100: %s has no I/O BAR assigned\n", chip->name);
        [self free];
        return nil;
    }

    /* I/O decoding and bus mastering. The status half of the dword goes
     * back as zero, which leaves its write-one-to-clear bits alone. */
    if ([IODirectDevice getPCIConfigData:&command atRegister:0x04
                   withDeviceDescription:devDesc] == IO_R_SUCCESS
        && (command & 0x0005UL) != 0x0005UL) {
        [IODirectDevice setPCIConfigData:((command & 0xFFFFUL) | 0x0005UL)
                              atRegister:0x04 withDeviceDescription:devDesc];
        IOLog("IntelE100: turned on I/O decoding and bus mastering"
              " (command was %04x)\n", (unsigned int)(command & 0xFFFFUL));
    }

    /* A warm boot leaves the chip as the last driver left it (SDM 8.1.1).
     * Both PORT commands clear the SCB M bit, so mask again at once. */
    e100PortCommand(ioBase, E100_PORT_SELECTIVE_RESET);
    e100PortCommand(ioBase, E100_PORT_SOFTWARE_RESET);
    E100_OUTB(ioBase + E100_SCB_INTR, E100_INTR_MASK_ALL);

    eeBits = e100EepromAddressBits(ioBase);
    if (eeBits < 6 || eeBits > 8) {
        IOLog("IntelE100: EEPROM did not answer (address width %d)\n", eeBits);
        [self free];
        return nil;
    }
    words = 1 << eeBits;
    sum = 0;
    for (i = 0; i < words; i++) {
        word = e100EepromRead(ioBase, eeBits, i);
        sum = (unsigned short)(sum + word);
        if (i < E100_EEPROM_WORDS_KEPT)
            ee[i] = word;
    }
    e100MacFromEeprom(ee, mac);
    if (!e100MacValid(mac)) {
        IOLog("IntelE100: EEPROM holds %02x:%02x:%02x:%02x:%02x:%02x,"
              " which is not a station address\n",
              mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
        [self free];
        return nil;
    }

    revision = e100EffectiveRevision(chip, (unsigned char)config.RevisionID, ee);
    quirks = e100Quirks(chip, revision, ee);
    irqCount = [devDesc numInterrupts];

    /* "0 irq" is the signature of a missing "IRQ Levels" key in the
     * instance table (drvIntel1000's README-Instance0.md). */
    IOLog("IntelE100: %s [8086:%04x rev %02x] %s generation, I/O 0x%04x,"
          " config IRQ %d, %d irq\n",
          chip->name, (unsigned int)config.DeviceID,
          (unsigned int)config.RevisionID, e100GenerationName(revision),
          (unsigned int)ioBase, (int)config.InterruptLine, irqCount);
    IOLog("IntelE100: MAC %02x:%02x:%02x:%02x:%02x:%02x, EEPROM %d words,"
          " checksum %s\n",
          mac[0], mac[1], mac[2], mac[3], mac[4], mac[5], words,
          (sum == E100_EEPROM_SUM) ? "OK" : "BAD - continuing");
    if (quirks & E100_Q_RXBUG)
        IOLog("IntelE100: EEPROM word 3 does not mark the receive lockup"
              " fixed - watching for it\n");
    if (quirks & E100_Q_CU_RESUME)
        IOLog("IntelE100: EEPROM enables Dynamic Standby (82801BA erratum 30)"
              " - a CU NOP precedes every resume; the EEPROM is left alone\n");
    if (revision >= E100_REV_82550)
        IOLog("IntelE100: %s runs in simplified mode here, which no reference"
              " driver exercises on this part\n", chip->name);

    [self _findPhy:ee[E100_EEPROM_PHY]];

    IOLog("IntelE100: identification-only build - not attaching\n");
    [self free];
    return nil;
}

/*
 * The MII address from EEPROM word 6 first (SDM 7.1), then every other
 * address, taking the first whose PHYID1 is neither 0 nor all ones.
 */
- (void)_findPhy:(unsigned short)phyWord
{
    int want = phyWord & E100_PHY_ADDR_MASK;
    int i, addr, id1;

    phyAddr = -1;
    if (quirks & E100_Q_SERIAL) {
        IOLog("IntelE100: 82503 serial interface - no MII PHY\n");
        return;
    }
    for (i = -1; i < 32; i++) {
        addr = (i < 0) ? want : i;
        if (i == want)
            continue;
        id1 = e100MdiRead(ioBase, addr, MII_PHYID1);
        if (id1 > 0 && id1 != 0xFFFF) {
            phyAddr = addr;
            phyId1 = (unsigned short)id1;
            phyId2 = (unsigned short)(e100MdiRead(ioBase, addr, MII_PHYID2)
                                      & 0xFFFF);
            IOLog("IntelE100: PHY at MII address %d%s, ID %04x:%04x\n",
                  addr, (i < 0) ? "" : " (found by scanning; the EEPROM"
                  " names another)", (unsigned int)phyId1,
                  (unsigned int)phyId2);
            /* Autonegotiate once, here. Restarting it on every
             * -resetAndEnable: would drop the link at each filter change. */
            (void)e100MdiWrite(ioBase, addr, MII_BMCR,
                               BMCR_AUTONEG | BMCR_RESTART_AUTONEG);
            return;
        }
    }
    IOLog("IntelE100: no MII PHY answered - link will be reported as up\n");
}

@end
```

- [ ] **Step 5: Build on the guest**

```bash
powershell.exe -NoProfile -File vm/sync-src.ps1 -Path drivers-i386/network/drvIntelE100
powershell.exe -NoProfile -File vm/guest-remote.ps1 -Run vm/build-i386-e100.sh; echo "exit=$?"
```

Expected:
- `TESTS_RC=0` and `BUILD_RC=0`.
- Nothing under `--- compiler diagnostics from the driver's own sources ---`.
- One `intele100-1.0*-i386.apk` listed, and `exit=0`.

If the build fails:
1. Read `/build/out/drvIntelE100-rbuild.log` on the guest with a `-Run` script that runs `tail -80` on it.
2. Compare against drvAHCI's project files, which are known to build.
3. Use superpowers:systematic-debugging; don't guess.

- [ ] **Step 6: Fetch the apk**

The build script copies it to a fixed name:

```bash
powershell.exe -NoProfile -File vm/guest-remote.ps1 -Fetch /build/out/intele100.apk -To vm/work/intele100.apk
python -c "import tarfile; t=tarfile.open('vm/work/intele100.apk','r:gz',ignore_zeros=True); print('\n'.join(n for n in t.getnames() if 'IntelE100' in n))"
```

Expected: a file listing that includes `…/IntelE100.config/IntelE100_reloc`, `…/Default.table` and `…/Instance0.table`. A clean gzip read also proves the fetch was byte-exact.

- [ ] **Step 7: Write `vm/e100-boot.py`**

```python
"""Boot-test drvIntelE100 under QEMU, on images of its own.

usage: python e100-boot.py BUNDLE MODEL MODE [PORT]

BUNDLE  an IntelE100.config directory, or the intele100 .apk holding one
MODEL   a QEMU eepro100 model (i82557b, i82559er, i82801, i82551, ...), or
        ne2k_pci for the negative check
MODE    probe   boot -s and stop at the shell: identification only
        single  boot -s, bring en0 up by hand and ping QEMU's gateway
        multi   boot normally, answer the network prompt, reach the
                Setup Assistant
PORT    QMP port, default 4510

golden.img and the rebuilt kernel come from E100_GOLDEN and E100_KERNEL
(default: golden.img and install/mach_kernel beside this script), so this
runs from a git worktree that has neither. Everything it writes lands under
this checkout's work/: e100-base.img, one e100-MODEL-MODE.img per run, and
e100-MODEL-MODE/ with serial.log, e100.pcap and the screenshots.
work/test.img is written only as graft-kernel.py's staging target - the
one image that tool will write - and nothing boots it.

Exits 1 if the serial log shows a panic, or if a single run's capture
lacks frames in either direction.
"""
import glob
import hashlib
import importlib.util
import os
import shutil
import sys
import tarfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rhap_image  # noqa: E402
import ufs_alloc  # noqa: E402

GOLDEN = os.environ.get("E100_GOLDEN", os.path.join(HERE, "golden.img"))
KERNEL = os.environ.get("E100_KERNEL",
                        os.path.join(HERE, "install", "mach_kernel"))
SHELL_WAIT = int(os.environ.get("E100_SHELL_WAIT", "110"))
WORK = os.path.join(HERE, "work")
MAC = "52:54:00:12:34:56"
GATEWAY = "10.0.2.2"


def load(name, filename):
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(HERE, filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def bundle_dir(path):
    if os.path.isdir(path):
        return os.path.abspath(path)
    dest = os.path.join(WORK, "e100-bundle")
    shutil.rmtree(dest, ignore_errors=True)
    os.makedirs(dest)
    with tarfile.open(path, "r:gz", ignore_zeros=True) as apk:
        apk.extractall(dest, filter="data")
    hits = glob.glob(os.path.join(dest, "**", "IntelE100.config"),
                     recursive=True)
    if len(hits) != 1:
        sys.exit("expected one IntelE100.config in %s, found %r" % (path, hits))
    return hits[0]


def read_file(image, path):
    with rhap_image.Image(image) as img:
        ino = img.resolve(path)
        if ino is None:
            sys.exit("%s has no %s" % (image, path))
        return img.read_file(ino)


def base_image():
    base = os.path.join(WORK, "e100-base.img")
    staging = os.path.join(WORK, "test.img")
    os.makedirs(WORK, exist_ok=True)
    load("graft_kernel", "graft-kernel.py").graft_kernel(GOLDEN, KERNEL,
                                                         staging)
    shutil.copyfile(staging, base)
    with open(KERNEL, "rb") as f:
        want = hashlib.sha256(f.read()).hexdigest()
    if hashlib.sha256(read_file(base, "/mach_kernel")).hexdigest() != want:
        sys.exit("the kernel in %s is not %s" % (base, KERNEL))
    return base


def install(base, bundle, image):
    """install-driver.py's steps without its `cp -c` clone, which GNU cp
    on this host rejects: copy, add the bundle, list it as a boot driver."""
    shutil.copyfile(base, image)
    inst = load("install_driver", "install-driver.py")
    name = inst._driver_name(bundle)
    with ufs_alloc.Allocator(image, writable=True) as a:
        a.validate()
        inst._install_bundle(a, "/private/Drivers/i386/%s.config" % name,
                             bundle)
        a.flush()
    print("  installed %s; Boot Drivers: %s"
          % (name, inst._add_boot_driver(image, name)))


def boot(image, model, mode, port):
    out = os.path.join(WORK, "e100-%s-%s" % (model, mode))
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    pcap = os.path.join(out, "e100.pcap").replace("\\", "/")
    nic = model if model == "ne2k_pci" else "%s,addr=03.0,mac=%s" % (model, MAC)
    gc = load("guest_console", "guest-console.py")
    g = gc.Guest(out, port=port, image=image, nic=nic,
                 extra=("-object",
                        "filter-dump,id=f0,netdev=n0,file=%s" % pcap))
    try:
        time.sleep(6)
        if mode == "multi":
            g.line("mach_kernel")
            time.sleep(105)
            g.shot("t105")
            g.line("y")
            time.sleep(40)
            g.shot("t145")
        else:
            g.line("-s")
            time.sleep(SHELL_WAIT)
            g.shot("shell")
            if mode == "single":
                g.line("ifconfig en0 10.0.2.15 netmask 255.255.255.0 up")
                time.sleep(8)
                g.shot("ifconfig")
                g.line("ping -c 3 " + GATEWAY)
                time.sleep(12)
                g.shot("ping")
                g.line("netstat -in")
                time.sleep(3)
                g.shot("netstat")
                time.sleep(20)  # two more statistics harvests reach the log
    finally:
        g.close()
    return out, pcap


def report(out, pcap, model, mode):
    with open(os.path.join(out, "serial.log"), "rb") as f:
        serial = f.read().decode("latin-1").splitlines()
    ours = [line for line in serial if "IntelE100" in line]
    print("--- IntelE100 lines in serial.log (%d) ---" % len(ours))
    print("\n".join(ours) if ours else "(none)")
    ok = True
    panics = [line for line in serial if "panic" in line.lower()]
    if panics:
        print("--- PANIC ---")
        print("\n".join(panics))
        ok = False
    if model != "ne2k_pci" and os.path.exists(pcap):
        s = load("e100_pcap", "e100-pcap.py").summarize(pcap, MAC)
        print("--- capture ---")
        for key in sorted(s):
            print("%s %d" % (key, s[key]))
        if mode == "single" and not (s["from_guest"] and s["to_guest"]):
            print("FAIL: no frames in one direction")
            ok = False
    print("logs and screenshots: %s" % out)
    return ok


def main(argv):
    if len(argv) not in (4, 5) or argv[3] not in ("probe", "single", "multi"):
        print(__doc__, file=sys.stderr)
        return 2
    bundle = bundle_dir(argv[1])
    model, mode = argv[2], argv[3]
    port = int(argv[4]) if len(argv) == 5 else 4510
    image = os.path.join(WORK, "e100-%s-%s.img" % (model, mode))
    install(base_image(), bundle, image)
    out, pcap = boot(image, model, mode, port)
    return 0 if report(out, pcap, model, mode) else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

- [ ] **Step 8: Boot the identification build on three models**

```bash
cd vm
for m in i82559er i82557b i82801; do python e100-boot.py work/intele100.apk $m probe; done
```

Expected for each model:
- An identity line `IntelE100: <chip name> [8086:<id> rev <rr>] <generation> generation, I/O 0x…, config IRQ 11, 1 irq`:

  | Model | Chip name | Device and revision | Generation |
  |---|---|---|---|
  | `i82559er` | `82559ER` | `1209`, any revision | `82559` |
  | `i82557b` | `82557` | `1229` rev 02 | `82557` |
  | `i82801` | `82801BA/CAM (ICH2/3) PRO/100` | `2449` | `82559` |

- `IntelE100: MAC 52:54:00:12:34:56, EEPROM 64 words, checksum OK`. The word count may be 256.
- A `PHY at MII address …` line.
- `identification-only build - not attaching`.
- No panic.
- `work/e100-<model>-probe/shell.png` shows a single-user shell prompt.

If a model deviates, adjust as follows:
- **`config IRQ` is not 11:** set `"IRQ Levels"` in `Instance0.table` to the logged value, rebuild, and rerun.
- **`0 irq`:** the IRQ Levels key did not take effect. Stop and debug with superpowers:systematic-debugging.
- **No `IntelE100:` lines at all:** the booter did not load the driver. Check `serial.log` for the boot-driver loader's messages, and read `docs/boot/sarld-driver-link-limit.md`.
- **`checksum BAD`:** check whether QEMU's eepro100 writes a checksum before calling it a driver bug.
- **`shell.png` shows no prompt yet:** rerun with `E100_SHELL_WAIT=150`.

- [ ] **Step 9: Commit**

```bash
git add src/drivers-i386/network/drvIntelE100 vm/e100-boot.py
git commit -m "drvIntelE100: package the driver and identify 8255x parts under QEMU"
```

---

### Task 6: The full driver — rings, transmit, receive, interrupts, watchdog, filters

**Files:**
- Replace: `LKS/IntelE100.m` (full listing below)

**Interfaces:**
- Consumes: everything in `E100Logic.h`, `E100Hw.h`, `E100Port.h` and `E100Regs.h`.
- Produces: the `IntelE100` class as DriverKit sees it:
  - `+probe:`, `-initFromDeviceDescription:`, `-free`, `-resetAndEnable:`
  - `-enableAllInterrupts`, `-disableAllInterrupts`, `-interruptOccurred`
  - `-transmit:`, `-timeoutOccurred`
  - `-enablePromiscuousMode`, `-disablePromiscuousMode`, `-enableMulticastMode`, `-disableMulticastMode`, `-addMulticastAddress:`, `-removeMulticastAddress:`

- [ ] **Step 1: Replace `LKS/IntelE100.m` with the full driver**

```objc
/*
 * IntelE100.m - Intel 8255x (e100) 10/100 ethernet driver for RhapsodiOS
 * i386.
 *
 * Copyright (c) 2026, Pat Raynor. BSD-2-Clause; see LICENSE.
 *
 * An IOEthernet subclass. The kernel matches "Auto Detect IDs" in the
 * config tables against the PCI bus, calls +probe:, and the instance
 * attaches to the network stack as enN.
 *
 * The specification is Intel's 8255x Open Source Software Developer Manual
 * ("SDM"). FreeBSD's if_fxp supplied what the SDM leaves out - the ICH
 * device IDs, the EEPROM map and the errata - and each such choice is
 * cited where it is made. NOTICE records what was and was not consulted.
 *
 * How the hardware is driven:
 *
 *   - CSRs through the I/O BAR; SCB command and status a byte at a time.
 *   - Linear addressing (CU and RU base 0): every pointer is physical.
 *   - Configure, individual-address and multicast setup run polled from
 *     one command block while the CU is idle, inside -resetAndEnable:. A
 *     change to the receive filter re-runs -resetAndEnable: rather than
 *     slipping a command into the live transmit ring, as FreeBSD does.
 *   - Transmit: 16 simplified TxCBs in a static circle. The CU is started
 *     once on a NOP with S set and never goes idle again; each frame sets
 *     S on its own TxCB, clears it on the previous one and issues CU
 *     Resume (SDM 8.2).
 *   - Receive: 32 simplified RFDs in a circle with EL on the tail only. EL
 *     moves forward as RFDs are recycled, and RNR restarts the RU.
 *
 * Strict C89 + NeXT Objective-C (cc 2.7.2.1), kernel context. There is no
 * locking: the kernel is not preemptive, so -transmit:, the interrupt
 * handler and the watchdog never run at the same time - the guarantee
 * Pro1000 relies on too. Stores to DMA memory are ordered before the SCB
 * write that hands them to the chip because every SCB access is a call
 * into E100Hw.c, which the compiler cannot see through, and the i386
 * keeps stores in order.
 */

#import <driverkit/IODevice.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/i386/directDevice.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IOEthernet.h>
#import <driverkit/IONetwork.h>
#import <driverkit/IONetbufQueue.h>
#import <net/etherdefs.h>
#import <net/netbuf.h>

#import "E100Regs.h"
#import "E100Logic.h"
#import "E100Hw.h"
#import "E100Port.h"

#define E100_VENDOR     0x8086
#define PAGE_BYTES      4096

#define NTX             16      /* transmit slots                        */
#define NRX             32      /* receive frame descriptors             */
#define SLOT_BYTES      1536    /* one TxCB (1530 bytes) or one RFD      */
#define CB_BYTES        256     /* configure, IA or multicast setup      */
#define STATS_BYTES     (E100_STATS_DWORDS * 4)

#define TICK_MS         2000    /* watchdog period                       */
#define STATS_EVERY     5       /* ticks between statistics dumps        */
#define TX_STALL_TICKS  2       /* no transmit progress for 4 s          */
#define RX_IDLE_TICKS   8       /* 16 s: if_fxp resets after 15 s idle   */
#define TX_QUEUE_MAX    32
#define CB_WAIT_LOOPS   25000   /* x 2 us = 50 ms for a polled command   */
#define LOUD_RESETS     3       /* transmit resets before the log shouts */

/* True at 1, 10, 100, ... so a repeating condition logs on a log scale. */
static BOOL
logMilestone(unsigned long n)
{
    unsigned long m;

    for (m = 1UL; m != 0UL && m <= n; m *= 10UL) {
        if (m == n)
            return YES;
    }
    return NO;
}

static void
zeroBytes(vm_address_t p, int n)
{
    unsigned char *b = (unsigned char *)p;

    while (n-- > 0)
        *b++ = 0;
}

static BOOL
sameAddress(enet_addr_t *a, enet_addr_t *b)
{
    int i;

    for (i = 0; i < 6; i++) {
        if (a->ether_addr_octet[i] != b->ether_addr_octet[i])
            return NO;
    }
    return YES;
}

/*
 * DMA memory the chip can reach: physically contiguous, with a known
 * physical address. IOMalloc promises neither, so take twice the size and
 * use whichever half lies inside one page - for any size up to half a
 * page, one of them does. Pro1000 uses the same idiom (NeXT's own, from
 * AMDPCSCSIDriver). Returns the usable address, or 0; the caller frees
 * *allocOut with freeDmaBlock.
 */
static vm_address_t
allocDmaBlock(int size, vm_address_t *allocOut, unsigned long *physOut)
{
    vm_address_t    alloc, use;
    unsigned int    phys, physEnd;

    *allocOut = 0;
    *physOut = 0;
    alloc = (vm_address_t)IOMalloc(size * 2);
    if (alloc == 0) {
        IOLog("IntelE100: IOMalloc(%d) failed\n", size * 2);
        return 0;
    }
    *allocOut = alloc;

    use = alloc;
    if ((use & ~(PAGE_BYTES - 1)) != ((use + size - 1) & ~(PAGE_BYTES - 1)))
        use = alloc + size;

    if ((use & 3) != 0
        || IOPhysicalFromVirtual(IOVmTaskSelf(), use, &phys) != IO_R_SUCCESS
        || IOPhysicalFromVirtual(IOVmTaskSelf(), use + size - 1, &physEnd)
           != IO_R_SUCCESS
        || physEnd != phys + size - 1) {
        IOLog("IntelE100: no aligned, physically contiguous %d bytes\n", size);
        return 0;
    }
    zeroBytes(use, size);
    *physOut = (unsigned long)phys;
    return use;
}

static void
freeDmaBlock(vm_address_t *alloc, int size)
{
    if (*alloc != 0) {
        IOFree((void *)*alloc, size * 2);
        *alloc = 0;
    }
}

@interface IntelE100 : IOEthernet
{
    unsigned short      ioBase;
    const E100Chip     *chip;
    int                 revision;       /* see e100EffectiveRevision   */
    unsigned int        quirks;
    int                 irqCount;
    enet_addr_t         myAddress;
    IONetwork          *network;
    id                  transmitQueue;
    BOOL                irqSeen;

    int                 phyAddr;        /* -1: no MII                  */
    unsigned short      phyId1, phyId2;
    BOOL                linkUp;

    vm_address_t        txAlloc[NTX], txSlot[NTX];
    unsigned long       txPhys[NTX];
    int                 txHead;         /* next slot to fill           */
    int                 txTail;         /* oldest slot not completed   */
    int                 txCount;        /* frames from txTail to txHead */
    int                 txLast;         /* the slot holding S          */
    unsigned int        txThreshold;

    vm_address_t        rxAlloc[NRX], rxSlot[NRX];
    unsigned long       rxPhys[NRX];
    int                 rxHead;         /* next RFD to look at         */
    int                 rxTail;         /* the RFD holding EL          */

    vm_address_t        cbAlloc, cbBlock;
    unsigned long       cbPhys;
    vm_address_t        statsAlloc, statsBlock;
    unsigned long       statsPhys;
    BOOL                dumpPending;

    unsigned int        ticks;
    int                 txStallTicks;
    int                 rxIdleTicks;

    unsigned long       txDropped, txResets, rxBadFrames, rxNoNetbufs;
    unsigned long       rxRestarts, rxLockupResets, scbTimeouts, statsMissed;

    enet_addr_t         mcast[E100_MAX_MCAST];
    int                 mcastCount;
    int                 mcastExtra;     /* addresses beyond the list   */
    BOOL                mcastMode;
    BOOL                promiscMode;
}
+ (BOOL)probe:(IODeviceDescription *)devDesc;
- initFromDeviceDescription:(IODeviceDescription *)devDesc;
- (void)_findPhy:(unsigned short)phyWord;
- (BOOL)_allocateDma;
- (BOOL)_initChip;
- (BOOL)_runCommand:(unsigned short)command name:(const char *)name;
- (BOOL)_startTransmitRing;
- (BOOL)_startReceiveRing;
- (BOOL)_queueFrame:(netbuf_t)pkt;
- (void)_startTransmit;
- (void)_reapTransmit;
- (void)_drainTransmitQueue;
- (void)_flushTransmitQueue;
- (void)_serviceReceive:(BOOL)rnr;
- (void)_checkLink;
- (void)_harvestStatistics;
- (BOOL)_allMulticast;
- (void)_filtersChanged;
@end

@implementation IntelE100

+ (BOOL)probe:(IODeviceDescription *)devDesc
{
    IntelE100 *dev = [self alloc];

    if (dev == nil)
        return NO;
    return [dev initFromDeviceDescription:devDesc] != nil;
}

- initFromDeviceDescription:(IODeviceDescription *)devDesc
{
    IOPCIConfigSpace    config;
    unsigned long       command;
    unsigned short      ee[E100_EEPROM_WORDS_KEPT];
    unsigned short      sum, word;
    unsigned char       mac[6];
    int                 eeBits, words, i;

    if ([super initFromDeviceDescription:devDesc] == nil)
        return nil;

    if ([IODirectDevice getPCIConfigSpace:&config
                    withDeviceDescription:devDesc] != IO_R_SUCCESS) {
        IOLog("IntelE100: cannot read PCI configuration space\n");
        [self free];
        return nil;
    }
    if (config.VendorID != E100_VENDOR) {
        IOLog("IntelE100: vendor %04x is not Intel\n",
              (unsigned int)config.VendorID);
        [self free];
        return nil;
    }
    chip = e100ChipLookup(config.DeviceID, (unsigned char)config.RevisionID);
    if (chip == 0) {
        IOLog("IntelE100: device %04x is not an 8255x this driver knows\n",
              (unsigned int)config.DeviceID);
        [self free];
        return nil;
    }

    /*
     * The CSRs are decoded through the I/O BAR as well as the memory BAR,
     * and port I/O needs no mapping. Scan for it rather than assume BAR1.
     */
    ioBase = 0;
    for (i = 0; i < 6; i++) {
        unsigned long bar = config.BaseAddress[i];

        if ((bar & 1UL) && (bar & 0xFFFFFFFCUL) != 0UL
            && (bar & 0xFFFFFFFCUL) <= 0xFFFFUL) {
            ioBase = (unsigned short)(bar & 0xFFFCUL);
            break;
        }
    }
    if (ioBase == 0) {
        IOLog("IntelE100: %s has no I/O BAR assigned\n", chip->name);
        [self free];
        return nil;
    }

    /* I/O decoding and bus mastering. The status half of the dword goes
     * back as zero, which leaves its write-one-to-clear bits alone. */
    if ([IODirectDevice getPCIConfigData:&command atRegister:0x04
                   withDeviceDescription:devDesc] == IO_R_SUCCESS
        && (command & 0x0005UL) != 0x0005UL) {
        [IODirectDevice setPCIConfigData:((command & 0xFFFFUL) | 0x0005UL)
                              atRegister:0x04 withDeviceDescription:devDesc];
        IOLog("IntelE100: turned on I/O decoding and bus mastering"
              " (command was %04x)\n", (unsigned int)(command & 0xFFFFUL));
    }

    /* A warm boot leaves the chip as the last driver left it (SDM 8.1.1).
     * Both PORT commands clear the SCB M bit, so mask again at once. */
    e100PortCommand(ioBase, E100_PORT_SELECTIVE_RESET);
    e100PortCommand(ioBase, E100_PORT_SOFTWARE_RESET);
    E100_OUTB(ioBase + E100_SCB_INTR, E100_INTR_MASK_ALL);

    eeBits = e100EepromAddressBits(ioBase);
    if (eeBits < 6 || eeBits > 8) {
        IOLog("IntelE100: EEPROM did not answer (address width %d)\n", eeBits);
        [self free];
        return nil;
    }
    words = 1 << eeBits;
    sum = 0;
    for (i = 0; i < words; i++) {
        word = e100EepromRead(ioBase, eeBits, i);
        sum = (unsigned short)(sum + word);
        if (i < E100_EEPROM_WORDS_KEPT)
            ee[i] = word;
    }
    e100MacFromEeprom(ee, mac);
    if (!e100MacValid(mac)) {
        IOLog("IntelE100: EEPROM holds %02x:%02x:%02x:%02x:%02x:%02x,"
              " which is not a station address\n",
              mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
        [self free];
        return nil;
    }
    for (i = 0; i < 6; i++)
        myAddress.ether_addr_octet[i] = mac[i];

    revision = e100EffectiveRevision(chip, (unsigned char)config.RevisionID, ee);
    quirks = e100Quirks(chip, revision, ee);
    irqCount = [devDesc numInterrupts];

    /* "0 irq" is the signature of a missing "IRQ Levels" key in the
     * instance table (drvIntel1000's README-Instance0.md). */
    IOLog("IntelE100: %s [8086:%04x rev %02x] %s generation, I/O 0x%04x,"
          " config IRQ %d, %d irq\n",
          chip->name, (unsigned int)config.DeviceID,
          (unsigned int)config.RevisionID, e100GenerationName(revision),
          (unsigned int)ioBase, (int)config.InterruptLine, irqCount);
    IOLog("IntelE100: MAC %02x:%02x:%02x:%02x:%02x:%02x, EEPROM %d words,"
          " checksum %s\n",
          mac[0], mac[1], mac[2], mac[3], mac[4], mac[5], words,
          (sum == E100_EEPROM_SUM) ? "OK" : "BAD - continuing");
    if (quirks & E100_Q_RXBUG)
        IOLog("IntelE100: EEPROM word 3 does not mark the receive lockup"
              " fixed - watching for it\n");
    if (quirks & E100_Q_CU_RESUME)
        IOLog("IntelE100: EEPROM enables Dynamic Standby (82801BA erratum 30)"
              " - a CU NOP precedes every resume; the EEPROM is left alone\n");
    if (revision >= E100_REV_82550)
        IOLog("IntelE100: %s runs in simplified mode here, which no reference"
              " driver exercises on this part\n", chip->name);

    [self _findPhy:ee[E100_EEPROM_PHY]];

    if (![self _allocateDma]) {
        [self free];
        return nil;
    }
    txThreshold = E100_TX_THRESHOLD_START;
    transmitQueue = [[IONetbufQueue alloc] initWithMaxCount:TX_QUEUE_MAX];
    network = [super attachToNetworkWithAddress:myAddress];
    return self;
}

/*
 * The MII address from EEPROM word 6 first (SDM 7.1), then every other
 * address, taking the first whose PHYID1 is neither 0 nor all ones.
 */
- (void)_findPhy:(unsigned short)phyWord
{
    int want = phyWord & E100_PHY_ADDR_MASK;
    int i, addr, id1;

    phyAddr = -1;
    if (quirks & E100_Q_SERIAL) {
        IOLog("IntelE100: 82503 serial interface - no MII PHY\n");
        return;
    }
    for (i = -1; i < 32; i++) {
        addr = (i < 0) ? want : i;
        if (i == want)
            continue;
        id1 = e100MdiRead(ioBase, addr, MII_PHYID1);
        if (id1 > 0 && id1 != 0xFFFF) {
            phyAddr = addr;
            phyId1 = (unsigned short)id1;
            phyId2 = (unsigned short)(e100MdiRead(ioBase, addr, MII_PHYID2)
                                      & 0xFFFF);
            IOLog("IntelE100: PHY at MII address %d%s, ID %04x:%04x\n",
                  addr, (i < 0) ? "" : " (found by scanning; the EEPROM"
                  " names another)", (unsigned int)phyId1,
                  (unsigned int)phyId2);
            /* Autonegotiate once, here. Restarting it on every
             * -resetAndEnable: would drop the link at each filter change. */
            (void)e100MdiWrite(ioBase, addr, MII_BMCR,
                               BMCR_AUTONEG | BMCR_RESTART_AUTONEG);
            return;
        }
    }
    IOLog("IntelE100: no MII PHY answered - link will be reported as up\n");
}

- (BOOL)_allocateDma
{
    int i;

    for (i = 0; i < NTX; i++) {
        txSlot[i] = allocDmaBlock(SLOT_BYTES, &txAlloc[i], &txPhys[i]);
        if (txSlot[i] == 0)
            return NO;
    }
    for (i = 0; i < NRX; i++) {
        rxSlot[i] = allocDmaBlock(SLOT_BYTES, &rxAlloc[i], &rxPhys[i]);
        if (rxSlot[i] == 0)
            return NO;
    }
    cbBlock = allocDmaBlock(CB_BYTES, &cbAlloc, &cbPhys);
    statsBlock = allocDmaBlock(STATS_BYTES, &statsAlloc, &statsPhys);
    return (cbBlock != 0 && statsBlock != 0) ? YES : NO;
}

- free
{
    int i;

    if (ioBase != 0) {
        /* Stop every DMA engine before the memory it targets goes away. */
        e100PortCommand(ioBase, E100_PORT_SELECTIVE_RESET);
        E100_OUTB(ioBase + E100_SCB_INTR, E100_INTR_MASK_ALL);
    }
    if (transmitQueue != nil) {
        [self _flushTransmitQueue];
        [transmitQueue free];
        transmitQueue = nil;
    }
    for (i = 0; i < NTX; i++)
        freeDmaBlock(&txAlloc[i], SLOT_BYTES);
    for (i = 0; i < NRX; i++)
        freeDmaBlock(&rxAlloc[i], SLOT_BYTES);
    freeDmaBlock(&cbAlloc, CB_BYTES);
    freeDmaBlock(&statsAlloc, STATS_BYTES);
    return [super free];
}

/*
 * Called by the network stack, so it must not sleep: every wait below is a
 * bounded IODelay loop (Pro1000 hung the machine with an IOSleep here).
 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    [self disableAllInterrupts];
    [self clearTimeout];
    [self setRunning:NO];

    /* Selective reset stops the CU and RU; the software reset returns the
     * rest to power-on state (the pair FreeBSD issues). Both clear the
     * SCB M bit, so mask again straight away. */
    e100PortCommand(ioBase, E100_PORT_SELECTIVE_RESET);
    e100PortCommand(ioBase, E100_PORT_SOFTWARE_RESET);
    E100_OUTB(ioBase + E100_SCB_INTR, E100_INTR_MASK_ALL);

    if (!enable) {
        [self _flushTransmitQueue];
        return YES;
    }
    if (![self _initChip]) {
        IOLog("IntelE100: %s did not come up after reset\n", chip->name);
        return NO;
    }

    /* Starting the transmit ring raised CNA; nothing from before the reset
     * can be pending, so acknowledge everything. */
    E100_OUTB(ioBase + E100_SCB_STATACK, 0xFF);

    if ([self enableAllInterrupts] != IO_R_SUCCESS) {
        IOLog("IntelE100: enableAllInterrupts failed\n");
        return NO;
    }
    [self setRunning:YES];
    [self setRelativeTimeout:TICK_MS];

    IOLog("IntelE100: %s enabled, %d irq, tx threshold %u bytes,"
          " %d multicast%s%s\n", chip->name, irqCount, txThreshold * 8,
          mcastCount, promiscMode ? ", promiscuous" : "",
          [self _allMulticast] ? ", all multicast" : "");
    [self _drainTransmitQueue];
    return YES;
}

- (BOOL)_initChip
{
    E100ConfigCB   *config = (E100ConfigCB *)cbBlock;
    E100IaCB       *ia = (E100IaCB *)cbBlock;
    unsigned char   list[E100_MAX_MCAST * 6];
    int             i, j;

    if (!e100ScbCommandPtr(ioBase, E100_CUC_LOAD_BASE, 0UL)
        || !e100ScbCommandPtr(ioBase, E100_RUC_LOAD_BASE, 0UL)) {
        IOLog("IntelE100: SCB did not accept the base address loads\n");
        return NO;
    }

    zeroBytes(statsBlock, STATS_BYTES);
    dumpPending = NO;
    if (!e100ScbCommandPtr(ioBase, E100_CUC_DUMP_ADDR, statsPhys)) {
        IOLog("IntelE100: SCB did not accept the statistics address\n");
        return NO;
    }

    e100BuildConfig(config->bytes, revision, quirks, promiscMode,
                    [self _allMulticast]);
    if (![self _runCommand:E100_CB_CONFIGURE name:"configure"])
        return NO;

    for (i = 0; i < 6; i++)
        ia->addr[i] = myAddress.ether_addr_octet[i];
    if (![self _runCommand:E100_CB_IAS name:"individual address setup"])
        return NO;

    for (i = 0; i < mcastCount; i++) {
        for (j = 0; j < 6; j++)
            list[i * 6 + j] = mcast[i].ether_addr_octet[j];
    }
    e100FillMcast((E100McastCB *)cbBlock, list, mcastCount);
    if (![self _runCommand:E100_CB_MCAS name:"multicast setup"])
        return NO;

    if (![self _startTransmitRing] || ![self _startReceiveRing])
        return NO;

    txStallTicks = 0;
    rxIdleTicks = 0;
    return YES;
}

/* One polled action command, with the CU idle (SDM 6.4.2). */
- (BOOL)_runCommand:(unsigned short)command name:(const char *)name
{
    E100CBHeader *hdr = (E100CBHeader *)cbBlock;

    if (!e100WaitCuIdle(ioBase)) {
        IOLog("IntelE100: CU not idle before %s (SCB status 0x%02x)\n", name,
              (unsigned int)E100_INB(ioBase + E100_SCB_STATUS));
        return NO;
    }
    hdr->status = 0;
    hdr->command = (unsigned short)(command | E100_CB_EL);
    hdr->link = E100_NO_LINK;
    if (!e100ScbCommandPtr(ioBase, E100_CUC_START, cbPhys)) {
        IOLog("IntelE100: SCB did not accept CU Start for %s\n", name);
        return NO;
    }
    if (!e100WaitCB(&hdr->status, CB_WAIT_LOOPS)) {
        IOLog("IntelE100: %s did not complete (CB status 0x%04x)\n", name,
              (unsigned int)hdr->status);
        return NO;
    }
    if (!(hdr->status & E100_CB_OK)) {
        IOLog("IntelE100: %s failed (CB status 0x%04x)\n", name,
              (unsigned int)hdr->status);
        return NO;
    }
    return YES;
}

- (BOOL)_startTransmitRing
{
    E100TxCB   *first;
    int         i;

    for (i = 0; i < NTX; i++) {
        E100TxCB *cb = (E100TxCB *)txSlot[i];

        cb->hdr.status = E100_CB_C | E100_CB_OK;
        cb->hdr.command = E100_CB_NOP;
        cb->hdr.link = txPhys[(i + 1) % NTX];
    }

    /* Park the CU on a NOP with S set. From here on it only ever
     * suspends, and every frame is a CU Resume (FreeBSD's fxp_init_body
     * does the same). */
    first = (E100TxCB *)txSlot[0];
    first->hdr.status = 0;
    first->hdr.command = E100_CB_NOP | E100_CB_S;
    txLast = 0;
    txHead = 1;
    txTail = 1;
    txCount = 0;

    if (!e100WaitCuIdle(ioBase)
        || !e100ScbCommandPtr(ioBase, E100_CUC_START, txPhys[0])
        || !e100WaitCB(&first->hdr.status, CB_WAIT_LOOPS)) {
        IOLog("IntelE100: transmit ring did not start (CB status 0x%04x)\n",
              (unsigned int)first->hdr.status);
        return NO;
    }
    return YES;
}

- (BOOL)_startReceiveRing
{
    int i;

    for (i = 0; i < NRX; i++) {
        E100Rfd *rfd = (E100Rfd *)rxSlot[i];

        rfd->status = 0;
        rfd->command = (i == NRX - 1) ? E100_RFD_EL : 0;
        rfd->link = rxPhys[(i + 1) % NRX];
        rfd->rbdPointer = E100_NO_LINK;
        rfd->actualCount = 0;
        rfd->size = E100_RFD_BUF;
    }
    rxHead = 0;
    rxTail = NRX - 1;
    if (!e100ScbCommandPtr(ioBase, E100_RUC_START, rxPhys[0])) {
        IOLog("IntelE100: SCB did not accept RU Start\n");
        return NO;
    }
    return YES;
}

- (IOReturn)enableAllInterrupts
{
    E100_OUTB(ioBase + E100_SCB_INTR, 0);
    return [super enableAllInterrupts];
}

- (void)disableAllInterrupts
{
    if (ioBase != 0)
        E100_OUTB(ioBase + E100_SCB_INTR, E100_INTR_MASK_ALL);
    [super disableAllInterrupts];
}

- (void)interruptOccurred
{
    unsigned char   stat;
    int             pass;

    for (pass = 0; pass < 16; pass++) {
        stat = E100_INB(ioBase + E100_SCB_STATACK);
        if (stat == 0x00 || stat == 0xFF)
            break;              /* not ours (shared line), or card gone */
        E100_OUTB(ioBase + E100_SCB_STATACK, stat);

        if (!irqSeen) {
            irqSeen = YES;
            IOLog("IntelE100: interrupts flowing, first STAT/ACK 0x%02x\n",
                  (unsigned int)stat);
        }
        if (stat & (E100_STAT_FR | E100_STAT_RNR))
            [self _serviceReceive:(stat & E100_STAT_RNR) ? YES : NO];
        if (stat & (E100_STAT_CX | E100_STAT_CNA)) {
            [self _reapTransmit];
            [self _drainTransmitQueue];
        }
    }

    /* Re-enable at the framework level as well as in the chip: Pro1000
     * measured that the IRQ stays stranded without the disable/enable
     * pair. */
    if ([self isRunning]) {
        [self disableAllInterrupts];
        [self enableAllInterrupts];
    }
}

- (void)transmit:(netbuf_t)pkt
{
    if (![self isRunning]) {
        nb_free(pkt);
        return;
    }
    [self _reapTransmit];

    if ([transmitQueue count] > 0 || txCount >= NTX - 1) {
        /* IONetbufQueue frees a netbuf "without notice" once it is full
         * (its header says so), so count it here. */
        if ([transmitQueue count] >= [transmitQueue maxCount]) {
            txDropped++;
            if (network != nil)
                [network incrementOutputErrors];
            if (logMilestone(txDropped))
                IOLog("IntelE100: transmit queue full, %u frames dropped\n",
                      (unsigned int)txDropped);
        }
        [transmitQueue enqueue:pkt];
        [self _drainTransmitQueue];
        return;
    }
    if ([self _queueFrame:pkt])
        [self _startTransmit];
}

- (BOOL)_queueFrame:(netbuf_t)pkt
{
    E100TxCB       *cb = (E100TxCB *)txSlot[txHead];
    E100TxCB       *prev = (E100TxCB *)txSlot[txLast];
    unsigned int    length = nb_size(pkt);

    if (length > E100_MAX_FRAME) {
        txDropped++;
        if (network != nil)
            [network incrementOutputErrors];
        nb_free(pkt);
        return NO;
    }
    [self performLoopback:pkt];
    IOCopyMemory(nb_map(pkt), (void *)cb->data, length, 1);
    nb_free(pkt);

    cb->hdr.status = 0;
    cb->tbdArray = E100_NO_LINK;
    cb->byteCount = (unsigned short)(length | E100_TCB_EOF);
    cb->threshold = (unsigned char)txThreshold;
    cb->tbdNumber = 0;
    cb->hdr.command = E100_CB_XMIT | E100_CB_S;

    /* S on the new CB first, then off the previous one (SDM 8.2), so the
     * CU can never run past the end of what is ready. */
    prev->hdr.command = (unsigned short)(prev->hdr.command & ~E100_CB_S);

    txLast = txHead;
    txHead = (txHead + 1) % NTX;
    txCount++;
    if (network != nil)
        [network incrementOutputPackets];
    return YES;
}

- (void)_startTransmit
{
    if (!e100CuResume(ioBase, (quirks & E100_Q_CU_RESUME) != 0)) {
        scbTimeouts++;
        if (logMilestone(scbTimeouts))
            IOLog("IntelE100: SCB did not accept CU Resume (%u times) - the"
                  " watchdog will reset\n", (unsigned int)scbTimeouts);
    }
}

- (void)_reapTransmit
{
    while (txCount > 0
           && (((E100TxCB *)txSlot[txTail])->hdr.status & E100_CB_C)) {
        txTail = (txTail + 1) % NTX;
        txCount--;
        txStallTicks = 0;
    }
}

- (void)_drainTransmitQueue
{
    netbuf_t    pkt;
    BOOL        queued = NO;

    if (![self isRunning])
        return;
    while (txCount < NTX - 1 && [transmitQueue count] > 0) {
        pkt = [transmitQueue dequeue];
        if (pkt != NULL && [self _queueFrame:pkt])
            queued = YES;
    }
    if (queued)
        [self _startTransmit];
}

- (void)_flushTransmitQueue
{
    while (transmitQueue != nil && [transmitQueue count] > 0)
        nb_free([transmitQueue dequeue]);
}

- (void)_serviceReceive:(BOOL)rnr
{
    int budget = NRX;

    while (budget-- > 0) {
        E100Rfd        *rfd = (E100Rfd *)rxSlot[rxHead];
        unsigned short  status = rfd->status;
        unsigned int    length;
        netbuf_t        pkt = NULL;

        if (!(status & E100_RFD_C))
            break;
        length = rfd->actualCount & E100_RFD_COUNT_MASK;

        if (!(status & E100_RFD_OK) || (status & E100_RFD_ERRORS)
            || !(rfd->actualCount & E100_RFD_EOF)
            || length < 14 || length > E100_RFD_BUF) {
            rxBadFrames++;
            /* Bad frames only reach an RFD in promiscuous mode (configure
             * byte 6 bit 7), and the statistics dump counts them already. */
            if (network != nil && !promiscMode)
                [network incrementInputErrors];
            if (logMilestone(rxBadFrames))
                IOLog("IntelE100: bad receive, status 0x%04x count 0x%04x,"
                      " %u so far\n", (unsigned int)status,
                      (unsigned int)rfd->actualCount,
                      (unsigned int)rxBadFrames);
        } else {
            pkt = nb_alloc(length);
            if (pkt == NULL) {
                rxNoNetbufs++;
                if (network != nil)
                    [network incrementInputErrors];
                if (logMilestone(rxNoNetbufs))
                    IOLog("IntelE100: no netbuf for a %u byte frame,"
                          " %u dropped so far\n", length,
                          (unsigned int)rxNoNetbufs);
            } else {
                IOCopyMemory((void *)rfd->data, nb_map(pkt), length, 1);
            }
        }

        /* Recycle: this RFD becomes the end of the list, and only then
         * does the old end stop holding the RU back. */
        rfd->status = 0;
        rfd->actualCount = 0;
        rfd->command = E100_RFD_EL;
        ((E100Rfd *)rxSlot[rxTail])->command = 0;
        rxTail = rxHead;
        rxHead = (rxHead + 1) % NRX;
        rxIdleTicks = 0;

        if (pkt != NULL) {
            if ([super isUnwantedMulticastPacket:
                           (ether_header_t *)nb_map(pkt)]) {
                nb_free(pkt);
            } else {
                [network incrementInputPackets];
                [network handleInputPacket:pkt extra:0];
            }
        }
    }

    /* RU Resume is illegal from no resources (SDM Table 53): start again
     * at the first free RFD. */
    if (rnr) {
        rxRestarts++;
        if (!e100ScbCommandPtr(ioBase, E100_RUC_START, rxPhys[rxHead]))
            IOLog("IntelE100: SCB did not accept RU Start\n");
        if (logMilestone(rxRestarts))
            IOLog("IntelE100: receive ring ran out, RU restarted"
                  " (%u so far)\n", (unsigned int)rxRestarts);
    }
}

- (void)timeoutOccurred
{
    if (![self isRunning])
        return;
    ticks++;
    [self _checkLink];
    [self _reapTransmit];
    [self _drainTransmitQueue];

    if (txCount > 0 && linkUp) {
        if (++txStallTicks >= TX_STALL_TICKS) {
            txResets++;
            IOLog("IntelE100: transmit stalled %d s with %d frames"
                  " outstanding - resetting (%u)%s\n",
                  TX_STALL_TICKS * TICK_MS / 1000, txCount,
                  (unsigned int)txResets, (txResets >= LOUD_RESETS)
                  ? " - repeatedly; check the IRQ Levels key" : "");
            [self resetAndEnable:YES];
            return;
        }
    } else {
        txStallTicks = 0;
    }

    /* 82557 receive lockup (FreeBSD if_fxp.c, fxp_tick): nothing received
     * for more than 15 s on a part whose EEPROM does not mark the fix, so
     * reinitialise - if_fxp's comment says multicast, its code does this. */
    if ((quirks & E100_Q_RXBUG) && ++rxIdleTicks >= RX_IDLE_TICKS) {
        rxLockupResets++;
        if (logMilestone(rxLockupResets))
            IOLog("IntelE100: nothing received for %d s on an 82557 without"
                  " the receive fix - reinitialising (%u)\n",
                  RX_IDLE_TICKS * TICK_MS / 1000,
                  (unsigned int)rxLockupResets);
        [self resetAndEnable:YES];
        return;
    }

    if (ticks % STATS_EVERY == 0)
        [self _harvestStatistics];
    [self setRelativeTimeout:TICK_MS];
}

- (void)_checkLink
{
    E100Link    link;
    int         bmsr, intel = -1;

    if (phyAddr < 0) {
        if (!linkUp) {
            linkUp = YES;
            IOLog("IntelE100: no MII PHY - reporting link up\n");
        }
        return;
    }
    (void)e100MdiRead(ioBase, phyAddr, MII_BMSR);   /* link latches low */
    bmsr = e100MdiRead(ioBase, phyAddr, MII_BMSR);
    if (bmsr < 0 || ((bmsr & BMSR_LINK) != 0) == linkUp)
        return;

    if (phyId1 == INTEL_PHYID1)
        intel = e100MdiRead(ioBase, phyAddr, MII_INTEL_STATUS);
    e100DecodeLink(bmsr, e100MdiRead(ioBase, phyAddr, MII_ANAR),
                   e100MdiRead(ioBase, phyAddr, MII_ANLPAR), intel, &link);
    linkUp = link.up ? YES : NO;
    if (!link.up)
        IOLog("IntelE100: link down\n");
    else if (!link.known)
        IOLog("IntelE100: link up, speed and duplex unknown\n");
    else
        IOLog("IntelE100: link up, %s, %s duplex\n",
              link.speed100 ? "100Mb/s" : "10Mb/s",
              link.fullDuplex ? "full" : "half");
}

/*
 * Read the previous Dump and Reset, then issue the next. The dump happens
 * when it is issued, so what is read here covers the interval up to the
 * previous harvest.
 */
- (void)_harvestStatistics
{
    volatile unsigned long *s = (volatile unsigned long *)statsBlock;
    unsigned long           txErrors, rxErrors, collisions;
    unsigned int            threshold;
    int                     i;

    if (dumpPending) {
        if (!e100StatsComplete(s)) {
            statsMissed++;
            if (logMilestone(statsMissed))
                IOLog("IntelE100: statistics dump did not complete"
                      " (%u times)\n", (unsigned int)statsMissed);
        } else {
            collisions = s[E100_STAT_TX_TOTALCOL];
            txErrors = s[E100_STAT_TX_MAXCOL] + s[E100_STAT_TX_LATECOL]
                     + s[E100_STAT_TX_UNDERRUN] + s[E100_STAT_TX_LOSTCRS];
            rxErrors = s[E100_STAT_RX_CRC] + s[E100_STAT_RX_ALIGN]
                     + s[E100_STAT_RX_RESOURCE] + s[E100_STAT_RX_OVERRUN]
                     + s[E100_STAT_RX_SHORT];
            if (network != nil) {
                if (collisions != 0UL)
                    [network incrementCollisionsBy:(unsigned)collisions];
                if (txErrors != 0UL)
                    [network incrementOutputErrorsBy:(unsigned)txErrors];
                if (rxErrors != 0UL)
                    [network incrementInputErrorsBy:(unsigned)rxErrors];
            }
            threshold = e100NextThreshold(txThreshold,
                                          s[E100_STAT_TX_UNDERRUN]);
            if (threshold != txThreshold) {
                IOLog("IntelE100: %u transmit underruns - threshold now"
                      " %u bytes\n", (unsigned int)s[E100_STAT_TX_UNDERRUN],
                      threshold * 8);
                txThreshold = threshold;
            }
            if (s[E100_STAT_TX_GOOD] != 0UL || s[E100_STAT_RX_GOOD] != 0UL
                || txErrors != 0UL || rxErrors != 0UL)
                IOLog("IntelE100: stats: tx %u rx %u, errors tx %u rx %u,"
                      " collisions %u\n",
                      (unsigned int)s[E100_STAT_TX_GOOD],
                      (unsigned int)s[E100_STAT_RX_GOOD],
                      (unsigned int)txErrors, (unsigned int)rxErrors,
                      (unsigned int)collisions);
        }
    }
    for (i = 0; i < E100_STATS_DWORDS; i++)
        s[i] = 0UL;
    dumpPending = e100ScbCommand(ioBase, E100_CUC_DUMP_RESET) ? YES : NO;
}

/* Pro1000's rule: multicast wanted but no list means accept all of it. */
- (BOOL)_allMulticast
{
    return (mcastExtra > 0 || (mcastMode && mcastCount == 0)) ? YES : NO;
}

/* A filter change re-runs the whole bring-up (FreeBSD's approach), which
 * keeps configure and multicast setup out of the live transmit ring. */
- (void)_filtersChanged
{
    if ([self isRunning])
        [self resetAndEnable:YES];
}

- (BOOL)enablePromiscuousMode
{
    promiscMode = YES;
    [self _filtersChanged];
    return YES;
}

- (void)disablePromiscuousMode
{
    promiscMode = NO;
    [self _filtersChanged];
}

- (BOOL)enableMulticastMode
{
    mcastMode = YES;
    [self _filtersChanged];
    return YES;
}

- (void)disableMulticastMode
{
    mcastMode = NO;
    [self _filtersChanged];
}

- (void)addMulticastAddress:(enet_addr_t *)address
{
    int i;

    for (i = 0; i < mcastCount; i++) {
        if (sameAddress(&mcast[i], address))
            return;
    }
    if (mcastCount < E100_MAX_MCAST) {
        mcast[mcastCount++] = *address;
    } else {
        /* No room: accept all multicast until the extras are removed. */
        if (mcastExtra++ == 0)
            IOLog("IntelE100: more than %d multicast addresses - accepting"
                  " all multicast\n", E100_MAX_MCAST);
    }
    [self _filtersChanged];
}

- (void)removeMulticastAddress:(enet_addr_t *)address
{
    int i, j;

    for (i = 0; i < mcastCount; i++) {
        if (sameAddress(&mcast[i], address)) {
            for (j = i; j < mcastCount - 1; j++)
                mcast[j] = mcast[j + 1];
            mcastCount--;
            [self _filtersChanged];
            return;
        }
    }
    /* Not in the list, so it was one of the extras. */
    if (mcastExtra > 0) {
        mcastExtra--;
        [self _filtersChanged];
    }
}

@end
```

- [ ] **Step 2: Build on the guest**

```bash
powershell.exe -NoProfile -File vm/sync-src.ps1 -Path drivers-i386/network/drvIntelE100
powershell.exe -NoProfile -File vm/guest-remote.ps1 -Run vm/build-i386-e100.sh; echo "exit=$?"
```

Expected:
- `TESTS_RC=0` and `BUILD_RC=0`.
- No compiler diagnostics from the driver's own sources.
- The apk is listed, and `exit=0`.

Fix every warning in `IntelE100.m` before going on.

- [ ] **Step 3: Fetch the new apk**

```bash
powershell.exe -NoProfile -File vm/guest-remote.ps1 -Fetch /build/out/intele100.apk -To vm/work/intele100.apk
```

- [ ] **Step 4: Single-user traffic test on the 82559ER**

```bash
cd vm && python e100-boot.py work/intele100.apk i82559er single; echo "exit=$?"
```

Expected in the serial lines:
- the identity, MAC, checksum-OK and PHY lines from Task 5
- `IntelE100: 82559ER enabled, 1 irq, tx threshold 512 bytes, 0 multicast`, printed when `ifconfig` brings en0 up. The multicast count may be higher if the stack joins groups.
- `IntelE100: link up, 100Mb/s, full duplex`
- `IntelE100: interrupts flowing, first STAT/ACK 0x…`
- at least one `IntelE100: stats: tx N rx M …` line with `rx` greater than 0

Expected in the capture:
- `from_guest` > 0 and `to_guest` > 0
- `arp_replies_to_guest` ≥ 1, and, if QEMU's slirp answers pings to its gateway, `icmp_replies_to_guest` ≥ 1

Also expected:
- `work/e100-i82559er-single/ping.png` shows ping replies from 10.0.2.2
- `exit=0`

If something is wrong, use superpowers:systematic-debugging and change one thing at a time:
- **No `enabled` line:** en0 never came up. Look at `ifconfig.png` for an error.
- **`transmit stalled`:** interrupts or CU Resume are not working. Check `1 irq` and `interrupts flowing`.
- **Frames only leave the guest:** check the receive path, and the RNR restarts in the log.

- [ ] **Step 5: Multi-user boot on the 82559ER**

```bash
cd vm && python e100-boot.py work/intele100.apk i82559er multi; echo "exit=$?"
```

Expected:
- the identity and `enabled` lines in the serial log
- no panic
- `work/e100-i82559er-multi/t145.png` shows the Setup Assistant
- `exit=0`

- [ ] **Step 6: Commit**

```bash
git add src/drivers-i386/network/drvIntelE100/IntelE100.drvproj/IntelE100.lksproj/IntelE100.m
git commit -m "drvIntelE100: drive the rings, interrupts, watchdog and receive filters; passes traffic under QEMU"
```

---

### Task 7: Test matrix, retire drvIntel82557, document

**Files:**
- Delete: `src/drivers-i386/network/drvIntel82557/` (all of it)
- Modify: `src/drivers-i386/README`, the `drvIntel82557` line in the `network` section

**Interfaces:**
- Consumes: the apk from Task 6 and `vm/e100-boot.py`.

- [ ] **Step 1: Run the full matrix**

```bash
cd vm
for m in i82557b i82559er i82801 i82551; do
  python e100-boot.py work/intele100.apk $m single; echo "$m single exit=$?"
  python e100-boot.py work/intele100.apk $m multi;  echo "$m multi exit=$?"
done
python e100-boot.py work/intele100.apk ne2k_pci multi; echo "ne2k negative exit=$?"
```

Check each run against the spec's Testing section, and record the results as you go.
- **Every eepro100 run** must meet all of these:
  - identity line with the right chip and generation
  - checksum OK
  - MAC `52:54:00:12:34:56`
  - a PHY found
  - `1 irq`
  - link up at 100 Mb/s full
  - no panic
- **Single runs:** exit 0, ping replies in `ping.png`, and a stats line with rx > 0.
- **Multi runs:** exit 0, and the Setup Assistant in `t145.png`.
- **`i82557b` runs:** if the log says `watching for it` (RXBUG), the single run may also log `nothing received for 16 s … reinitialising` during quiet periods. That is the erratum path working, not a failure.
- **`i82551` runs:** must log `runs in simplified mode here`.
- **`ne2k_pci` negative run:**
  - no `IntelE100:` line mentions an NE2000
  - the driver did not claim `10ec:8029`, so no identity line appears
  - `t145.png` shows the Setup Assistant

If any criterion fails, stop and debug; don't write the README entry.

- [ ] **Step 2: Retire drvIntel82557**

```bash
git rm -r -q src/drivers-i386/network/drvIntel82557
git grep -n "drvIntel82557" -- src
```

Expected: the only remaining hit is the README line that Step 3 replaces.

- [ ] **Step 3: Replace the README entry**

In `src/drivers-i386/README`, replace the line:

```
 * drvIntel82557 - needs compiled and then tested
```

with the entry below. Keep it on one line, as every other entry in the file is. Put the date the matrix was run where the text says `on 2026-09-2N`, using the output of `date +%F`.

```
 * drvIntelE100 - new, not a reconstruction: an original BSD-2-Clause driver for the Intel 8255x (e100) 10/100 family - 82557, 82558, 82559, 82559ER, 82550, 82551 and the ICH2-ICH7 integrated parts - written from Intel's 8255x Open Source Software Developer Manual, with FreeBSD's if_fxp consulted for the device IDs, the EEPROM map and the errata (see its NOTICE). It replaces drvIntel82557, the decompiled Apple driver, which is deleted. Its plain-C logic and register access have unit tests in tests/, run on the build guest by vm/build-i386-e100.sh. Boot-tested on 2026-09-2N under QEMU with vm/e100-boot.py on i82557b, i82559er, i82801 and i82551, each on its own image: every one identifies the part, reads the MAC with a good EEPROM checksum, finds the PHY and reports 100Mb/s full duplex; in single-user mode en0 pings 10.0.2.2 with frames both ways in the host-side capture, and a normal boot reaches the Setup Assistant. With an NE2000 in place of the card it does not probe and the boot is unaffected. Known limits: duplex follows the PHY's FDX pin, so an 82557 with a DP83840 that does not wire it runs half duplex; Dynamic Standby left enabled in an ICH2/82559 EEPROM is worked around, never cleared; simplified mode on the 82550/82551 is proven only against QEMU. Not hardware-tested
```

- [ ] **Step 4: Verify nothing else referenced the old driver, and that the tests still pass**

```bash
git grep -n "drvIntel82557" -- src docs ':!docs/superpowers'
powershell.exe -NoProfile -File vm/sync-src.ps1 -Path drivers-i386/network/drvIntelE100
powershell.exe -NoProfile -File vm/guest-remote.ps1 -Run vm/build-i386-e100.sh; echo "exit=$?"
cd vm && python -m unittest test_guest_console test_e100_pcap -v
```

Expected:
- no `git grep` hits
- `exit=0` with `TESTS_RC=0` and `BUILD_RC=0`
- Python tests OK

- [ ] **Step 5: Commit**

```bash
git add -A src/drivers-i386/network/drvIntel82557 src/drivers-i386/README
git commit -m "drvIntelE100: replace drvIntel82557, and record the QEMU test matrix in the README"
```

- [ ] **Step 6: Finish the branch**

Use superpowers:finishing-a-development-branch to merge `intele100` back into `master` or open a PR, whichever the user chooses. Remove the worktree afterwards.
