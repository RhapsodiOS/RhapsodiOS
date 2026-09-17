# drvISASerialPort binrecon finish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish `drvISASerialPort` against Apple's `ISASerialPort_reloc` by extracting the remaining translation units, applying the July `divergences.md` findings, guest-building after every change, and grinding each paired function to `raw_equal` / `masked_equal` or an exhausted-list accept.

**Architecture:** Phase 0 restores the missing guest harness and proves `IODirectDevice` (instance_size 604). Then TU 4 → 3 → 2 → 1, each with an algorithm pass then a shape pass. Implementer subagents never touch the guest. The controller runs the Guest rebuild block and returns a results file.

**Tech Stack:** Python `./.venv-binrecon/Scripts/python.exe` with `PYTHONPATH=tools/binrecon`, IDA 9.2 via `tools/binrecon`, Objective-C / C DriverKit on a Rhapsody guest, `vm/sync-src.ps1` + `vm/build-i386-input-recon.sh`.

**Spec:** [2026-09-16-isaserialport-binrecon-finish-design.md](../specs/2026-09-16-isaserialport-binrecon-finish-design.md)

## File map

| File | Responsibility |
|---|---|
| `vm/build-i386-input-recon.sh` | Guest `gnumake RC_ARCHS=i386` for this driver; stage `_reloc`. |
| `tools/binrecon/profiles/isaserialport.json` | Add `rebuilt.path`. Ghidra stays off. |
| `ISASerialPortInternal.h` | `Port` / `Queue` / eleven externs / `Chip` type. No enqueue body. |
| `ISASerialPortEnqueue.h` | `static RX_enqueueLongEvent`. Included only by TUs 1, 3, 4. |
| `ISASerialPortFlow.c` | TU 4. Finding 75 lock. Include enqueue header. |
| `ISASerialPortQueue.c` | TU 3 six-pack. |
| `ISASerialPortChip.c` | `_Chip[9]`, `_msr_state_lut`, identify/init/program. |
| `ISASerialPort.m` / `.h` | TU 1 class. Drop extracted bodies. `IODirectDevice` + `PortDevices`. |
| lksproj `Makefile` | `CFILES` and `HFILES` grow as TUs land. |
| `reconstruction/` | `ledger.json`, `source-map.json`, `divergences.md`, `function-worklist.md`. |

Work in a dedicated worktree:

```powershell
git worktree add .worktrees/isaserialport-finish -b isaserialport-binrecon-finish
```

`.worktrees/` is gitignored. Set `REPO` to that path. `VENVPY` stays `D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe`.

## Global constraints

```text
VENVPY=D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe
REF=C:/Users/raynorpat/Downloads/test/Drivers/i386/ISASerialPort.config/ISASerialPort_reloc
REFSHA=4CAA1BB9E8CE3309560F14E352F3D68902EA1C59937DC84DBB5EBCDA330EA932
LKS=src/drivers-i386/input/drvISASerialPort/ISASerialPort.drvproj/ISASerialPort.lksproj
DRV=src/drivers-i386/input/drvISASerialPort
RECON=src/drivers-i386/input/drvISASerialPort/reconstruction
PROFILE=tools/binrecon/profiles/isaserialport.json
REBUILT=out/i386/drvISASerialPort/ISASerialPort.config/ISASerialPort_reloc
```

- **Implementer subagents never touch the guest.** No `vm/vm.conf`, no `sync-src.ps1`, no SSH, no `pscp`/`plink`. After source edits, report DONE and wait for `reconstruction/results-N.md` from the controller.
- **Controller** runs the Guest rebuild block after every source or makefile change, then Host compare, then writes `results-N.md`.
- **Never commit** `$REF`, `tools/binrecon/out/`, `out/i386/`, or `results-N.md`.
- **`BINRECON_REFERENCE` and `BINRECON_REBUILT`** must be exported in every host binrecon shell.
- **Python is `$VENVPY`.** `PYTHONPATH=tools/binrecon`.
- **Do not touch** other drivers, `src/kernel-7`, comparator code, Ghidra, `normalize.py`, or `nextEvent` / `release` bodies.
- **Apple bugs stay:** identifyChip rung 7 missing MCR write; requestEvent 0x27 uses `RX.Size - TX.Count`; executeEvent 0x0B validates RX then stores TX.
- **Unpaired leftovers:** `__udivdi3`, `__umoddi3`, two Kernel Server glue stubs.
- **Ledger:** one rung at a time. Reviewer `Pat Raynor`. No `unexamined` → `intentional-mismatch`.
- **Commits:** `drvISASerialPort:` or `drivers-i386:`, one to two lines, no trailers. Stage by explicit path. Never `git add -A`.
- **Another agent commits to this repository.** Stage only this campaign's files.

### Guest rebuild (controller only)

Sync the driver, then the harness (it lives under `vm/`, which `-Path` cannot upload):

```powershell
powershell -NoProfile -File vm\sync-src.ps1 -Path drivers-i386/input/drvISASerialPort
. .\vm\rhap-remote.ps1
$cfg = Get-RhapVmConfig
$ssh = Resolve-RhapTool $cfg.Ssh
# Upload harness: same tar-over-ssh path sync-src uses, one-off for vm/build-i386-input-recon.sh
$ec = Invoke-RhapRemote -Cfg $cfg -Ssh $ssh -RemoteCommand 'tr -d "\r" < /build/source/vm/build-i386-input-recon.sh > /tmp/bisa.sh && sh /tmp/bisa.sh drvISASerialPort'
if ($ec -ne 0) { throw "guest build ssh exit $ec" }
$dst = 'out/i386/drvISASerialPort/ISASerialPort.config'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
$sshHost = "$($cfg.User)@$($cfg.Host)"
$opts = ($script:RhapLegacySshOptions -join ' ')
$remoteTar = "cd /build/out/i386/drvISASerialPort/ISASerialPort.config && tar cf - ISASerialPort_reloc"
Invoke-RhapSshAskPass -Cfg $cfg -Action {
    cmd /c "ssh $opts $sshHost `"$remoteTar`" | tar xf - -C $dst"
    if ($LASTEXITCODE -ne 0) { throw "tar pull exit $LASTEXITCODE" }
}
```

If `/build/source/vm/build-i386-input-recon.sh` is missing on the guest, `cat` the local script over SSH into that path first (CR stripped). Never `sync-src.ps1 -All`.

Expected guest log: `=== input-recon done fail=0 built: drvISASerialPort ===` and a staged `ISASerialPort_reloc`.

### Host compare (controller only)

```powershell
$env:PYTHONPATH = 'tools/binrecon'
$env:BINRECON_REFERENCE = $REF
$env:BINRECON_REBUILT = (Resolve-Path $REBUILT).Path
& $VENVPY -m binrecon validate --profile $PROFILE
& $VENVPY -m binrecon analyze --profile $PROFILE
# analyze may exit 1 until the campaign closes; gate is complete:true plus a comparison
& $VENVPY -m binrecon function --profile $PROFILE --list
```

Write `reconstruction/results-N.md` with: rebuild SHA-256, `instance_size` from `__OBJC,__class` (must be 604 after Phase 0), `__OBJC,__module_info` size (must stay 32), `__OBJC,__instance_vars` (28), `__DATA,__bss` size, eleven-extern nlist check, `parity_check.py` missing-symbol/string counts, and the `--list` summary for the open unit.

Read `instance_size` with `$VENVPY -c` using `binrecon.macho.read_macho` on `$REBUILT`; do not guess.

### Unit grind cycle (Tasks 4, 6, 8, 10)

Parameter: `UNIT` (4|3|2|1), `FILES` (that unit's sources).

1. From `--list`, keep rows whose names belong to `UNIT`.
2. Write a named experiment list per remaining paired function into `function-worklist.md`. Source-shape only (spec §5.5).
3. One experiment in `FILES` only. Stop. Controller rebuilds.
4. Keep the experiment only if `raw_equal`/`masked_equal` or `differing` strictly decreased, and no closed function regressed. Else revert.
5. Repeat until every paired function in `UNIT` matches or its list is empty (accept with `--name` dump + reviewer).
6. Reline `source-map.json`. Advance ledger one rung per function. Commit `drvISASerialPort: `.

---

### Task 1: Guest harness and rebuilt profile path

**Files:**
- Create: `vm/build-i386-input-recon.sh`
- Modify: `tools/binrecon/profiles/isaserialport.json`

Host-only. No driver source.

- [ ] **Step 1: Write the harness**

Create `vm/build-i386-input-recon.sh` with Unix LF line endings. POSIX Bourne: no `local`, no bashisms. Do **not** use `set -e` (Rhapsody `/bin/sh` applies it to functions returning nonzero). Gate on artifact presence.

```sh
#!/bin/sh
# Build drvISASerialPort on the Rhapsody guest and stage ISASerialPort_reloc.
# Usage: sh vm/build-i386-input-recon.sh drvISASerialPort
#
# Rhapsody /bin/sh is a 1999 Bourne shell: no local, no bashisms, and set -e
# kills the script when a function returns nonzero even from an if.

export PATH=/build/bin:/usr/local/bin:/build/tools/usr/local/bin:/bin:/usr/bin
OUT=/build/out/i386
INPUT=/build/source/src/drivers-i386/input
fail=0

if [ "$1" != "drvISASerialPort" ]; then
	echo "usage: $0 drvISASerialPort" >&2
	exit 2
fi

run_make() {
	src="$1"
	if [ ! -f "$src/Makefile" ]; then
		echo "MISSING $src/Makefile" >&2
		MAKE_EC=127
		return 1
	fi
	cd "$src"
	find . -type f \( -name Makefile -o -name 'Makefile.*' \) -print |
	while read f; do
		tr -d '\r' < "$f" > /tmp/rhap_cr && mv /tmp/rhap_cr "$f"
	done
	gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386 2>&1
	MAKE_EC=$?
	return 0
}

echo "======== build ISASerialPort (drvISASerialPort) ========"
run_make "$INPUT/drvISASerialPort"
echo "make exit=$MAKE_EC for ISASerialPort"

reloc=`find "$INPUT/drvISASerialPort" -name 'ISASerialPort_reloc' -type f 2>/dev/null | head -1`
if [ -z "$reloc" ] || [ ! -f "$reloc" ]; then
	echo "FAILED: no ISASerialPort_reloc" >&2
	find "$INPUT/drvISASerialPort" \( -name '*reloc*' -o -name '*.config' \) 2>/dev/null | head -40 >&2
	echo "=== input-recon done fail=1 built: ==="
	exit 1
fi

dst="$OUT/drvISASerialPort/ISASerialPort.config"
rm -rf "$dst"
mkdir -p "$dst"
cp -p "$reloc" "$dst/"
for f in "$INPUT/drvISASerialPort/ISASerialPort.drvproj"/*.table; do
	[ -f "$f" ] || continue
	cp -p "$f" "$dst/"
done
echo "staged $dst"
ls -la "$dst"
echo "=== input-recon done fail=0 built: drvISASerialPort ==="
exit 0
```

- [ ] **Step 2: Syntax-check on the host**

```powershell
# Git bash or WSL if present; otherwise skip and rely on guest sh -n in Task 2
bash -n vm/build-i386-input-recon.sh; echo "syntax $LASTEXITCODE"
```

Expected: `syntax 0`. If no bash, the guest `tr -d '\r' ... && sh /tmp/bisa.sh` in Task 2 is the syntax gate.

- [ ] **Step 3: Add rebuilt path to the profile**

In `tools/binrecon/profiles/isaserialport.json`, immediately after the `reference` object, add:

```json
  "rebuilt": {
    "path": "${BINRECON_REBUILT}"
  },
```

Leave Ghidra `enabled: false`. Leave IDA and angr as they are. Do not change `output_dir`.

- [ ] **Step 4: Commit**

```powershell
git add vm/build-i386-input-recon.sh tools/binrecon/profiles/isaserialport.json
git commit -m "drivers-i386: restore ISASerialPort guest harness and rebuilt profile path"
```

---

### Task 2: Phase 0 baseline (controller build, implementer records)

**Files:**
- Create: `src/drivers-i386/input/drvISASerialPort/reconstruction/function-worklist.md`

Depends on Task 1. Controller runs Guest rebuild then Host compare first, writes `reconstruction/results-0.md` (uncommitted). Implementer then records the worklist.

- [ ] **Step 1: Controller rebuild**

Run the Guest rebuild block. If the guest lacks `/build/source/vm/build-i386-input-recon.sh`, upload it (CR-stripped) before the `sh`. Copy `$REBUILT` back.

Expected: `_reloc` exists, log contains `fail=0`.

- [ ] **Step 2: Controller compare**

Host compare. Record in `results-0.md`:

- SHA-256 of `$REBUILT`
- `instance_size` (must be **604**; if 572 the `IODirectDevice` import is not linking — stop, do not open TU 4)
- `__OBJC,__module_info` == 32
- `__OBJC,__instance_vars` == 28
- `__DATA,__bss` size
- whether the eleven exports are `external`
- `--list` full dump

- [ ] **Step 3: Implementer writes the worklist**

Create `$RECON/function-worklist.md`:

```markdown
# drvISASerialPort function worklist

Reference SHA-256: 4CAA1BB9E8CE3309560F14E352F3D68902EA1C59937DC84DBB5EBCDA330EA932
Phase 0 rebuilt SHA-256: <from results-0.md>
instance_size: <from results-0.md>
__DATA,__bss: <from results-0.md>

## Phase 0 baseline

Paste the `--list` summary grouped by TU:

- TU 4: `_flowMachine`, `_watchState`, `_RX_enqueueLongEvent` at 23200
- TU 3: queue six-pack plus `_RX_enqueueLongEvent` at 20684
- TU 2: `_identifyChip`, `_initChip`, `_programChip`
- TU 1: remaining hand-written
- unpaired: `__udivdi3`, `__umoddi3`, two glue stubs
```

Fill SHA and sizes from `results-0.md`. Do not invent `--list` rows.

- [ ] **Step 4: Commit**

```powershell
git add src/drivers-i386/input/drvISASerialPort/reconstruction/function-worklist.md
git commit -m "drvISASerialPort: record Phase 0 function worklist from guest reloc"
```

---

### Task 3: TU 4 algorithm — enqueue header and watchState lock

**Files:**
- Create: `$LKS/ISASerialPortEnqueue.h`
- Modify: `$LKS/ISASerialPortFlow.c`
- Modify: `$LKS/ISASerialPort.m` (delete `_RX_enqueueLongEvent` body; include the header)
- Modify: `$LKS/Makefile` `HFILES`

Host-only. Wait for `results-1.md` after the controller rebuild.

- [ ] **Step 1: Write `ISASerialPortEnqueue.h`**

```c
/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * ... same Apple Public Source License 1.0 block as ISASerialPortInternal.h ...
 * @APPLE_LICENSE_HEADER_END@
 */
/*
 * Static RX_enqueueLongEvent, emitted once per translation unit that includes
 * this header. Include from ISASerialPort.m, ISASerialPortQueue.c, and
 * ISASerialPortFlow.c only — never from ISASerialPortChip.c.
 */
#ifndef _BSD_DEV_I386_ISASERIALPORTENQUEUE_H_
#define _BSD_DEV_I386_ISASERIALPORTENQUEUE_H_

#import "ISASerialPortInternal.h"

static void RX_enqueueLongEvent(Port *port, unsigned char event, unsigned int data)
{
    unsigned short *writePtr;
    unsigned int spaceAvailable;

    writePtr = (unsigned short *)port->RX.Input;
    spaceAvailable = port->RX.Size - port->RX.Count;
    if (spaceAvailable > 2) {
        *writePtr++ = (unsigned short)event;
        if ((char *)writePtr >= port->RX.End)
            writePtr = (unsigned short *)port->RX.Base;
        port->RX.Input = (char *)writePtr;
        port->RX.Count++;
        *writePtr++ = (unsigned short)data;
        if ((char *)writePtr >= port->RX.End)
            writePtr = (unsigned short *)port->RX.Base;
        port->RX.Input = (char *)writePtr;
        port->RX.Count++;
        *writePtr++ = (unsigned short)(data >> 16);
        if ((char *)writePtr >= port->RX.End)
            writePtr = (unsigned short *)port->RX.Base;
        port->RX.Input = (char *)writePtr;
        port->RX.Count++;
    } else if (port->RX.Size > port->RX.Count) {
        *writePtr++ = 0x6C;
        if ((char *)writePtr >= port->RX.End)
            writePtr = (unsigned short *)port->RX.Base;
        port->RX.Input = (char *)writePtr;
        port->RX.Count++;
    } else {
        port->RX.OverRun = 1;
    }
}

#endif
```

Copy the APSL header verbatim from `ISASerialPortInternal.h`. Event parameter is a byte (Finding 59). Return is `void`. Three-cell path is `Size-Count > 2`, not `< 3` inverted with an early `IOReturn`.

- [ ] **Step 2: Include it from Flow.c and replace the watchState lock**

At the top of `ISASerialPortFlow.c`, after `#import "ISASerialPortInternal.h"`:

```c
#import "ISASerialPortEnqueue.h"
```

Replace the lock block (the `while (port->WatchLock.locked != 0)` through `IOExitCriticalSection();`) with:

```c
        for (;;) {
            while (port->WatchLock.locked != 0)
                ;
            {
                unsigned int prev = 1;
                __asm__ volatile ("xchgl %0, %1"
                    : "+r" (prev), "+m" (port->WatchLock.locked)
                    : : "memory");
                if (prev == 0)
                    break;
            }
        }
```

Do not `continue` the outer `do`. Do not call `IOEnterCriticalSection` / `IOExitCriticalSection`. Leave the `-714`/`-703` returns and the `wakeWaiters` cleanup.

- [ ] **Step 3: Switch ISASerialPort.m to the header**

Delete the `_RX_enqueueLongEvent` function body. Add `#import "ISASerialPortEnqueue.h"` after the Internal include. Rename remaining call sites from `_RX_enqueueLongEvent` to `RX_enqueueLongEvent`.

- [ ] **Step 4: Makefile HFILES**

```make
HFILES = ISASerialPort.h ISASerialPortInternal.h ISASerialPortEnqueue.h
```

- [ ] **Step 5: Report DONE**

Controller rebuilds → `results-1.md`. Then:

- Confirm `__OBJC,__module_info` still 32.
- Confirm a local `_RX_enqueueLongEvent` appears in TU 4's text range (near 23200).
- Advance `_watchState` and `_flowMachine` one ledger rung if the nlist/signatures still match.
- Reline source-map for Flow.c.

- [ ] **Step 6: Commit**

```powershell
git add $LKS/ISASerialPortEnqueue.h $LKS/ISASerialPortFlow.c $LKS/ISASerialPort.m $LKS/Makefile $RECON/source-map.json $RECON/ledger.json $RECON/divergences.md
git commit -m "drvISASerialPort: emit RX_enqueueLongEvent from a shared header and match watchState lock"
```

---

### Task 4: TU 4 shape grind

**Files:** `$LKS/ISASerialPortFlow.c`, `$RECON/function-worklist.md`, `$RECON/divergences.md`, `$RECON/ledger.json`

Run the Unit grind cycle with `UNIT=4`, `FILES=ISASerialPortFlow.c`. Paired names: `_flowMachine`, `_watchState`. The TU 4 `_RX_enqueueLongEvent` copy is paired with the header body; grind it here if `--list` still shows a diff.

Do not edit Queue/Chip/class files. Stop when both (or three) match or lists are empty.

---

### Task 5: TU 3 extract and algorithm findings

**Files:**
- Create: `$LKS/ISASerialPortQueue.c`
- Modify: `$LKS/ISASerialPort.m` (remove the six functions)
- Modify: `$LKS/Makefile` `CFILES`
- Modify: `$RECON/*` after `results-2.md`

- [ ] **Step 1: Create Queue.c**

```c
#import "ISASerialPortInternal.h"
#import "ISASerialPortEnqueue.h"
#import <driverkit/generalFuncs.h>
#import <kernserv/prototypes.h>
```

Move these bodies from `ISASerialPort.m`, drop any remaining `static` on the six exports:

- `validateRingBufferSize`
- `freeRingBuffer`
- `allocateRingBuffer`
- `RX_dequeueEvent`
- `TX_enqueueEvent`
- `RX_dequeueData`

- [ ] **Step 2: Rewrite the three ring helpers to the reference**

`validateRingBufferSize` is already `(requestedSize, Queue *)`. Keep the 0 → `q->DefaultSize`, max `0x40000`, min `0x12` clamps.

Replace `freeRingBuffer` with named fields (Finding 56–57):

```c
void freeRingBuffer(Queue *q)
{
    if (q->AllocBase != 0)
        IOFree(q->AllocBase, q->AllocSize);
    q->AllocBase = 0;
    q->Base = 0;
    q->End = 0;
    q->Output = 0;
    q->Input = 0;
    q->AllocSize = 0;
    q->OverRun = 0;
    q->Count = 0;
}
```

Do **not** clear `Size`, `HighWater`, `LowWater`, or `Enqueue`.

Replace `allocateRingBuffer` (Findings 53–55). Return 1 on success, 0 on failure. Store `AllocSize` and `AllocBase` in different fields. Seed `Enqueue = LowWater` (not `LowWater = HighWater`):

```c
int allocateRingBuffer(Queue *q)
{
    unsigned int size;
    unsigned int allocSize;
    char *buffer;

    freeRingBuffer(q);
    size = q->Size;
    allocSize = size * 2 + 2;
    q->AllocSize = allocSize;
    buffer = IOMalloc(allocSize);
    if (buffer == 0)
        return 0;
    q->AllocBase = buffer;
    if (((unsigned int)buffer & 1) != 0)
        buffer = buffer + 1;
    q->Base = buffer;
    q->End = buffer + size * 2;
    q->Input = buffer;
    q->Output = buffer;
    q->OverRun = 0;
    q->Count = 0;
    q->Dequeue = 0;
    q->Enqueue = q->LowWater;
    return 1;
}
```

- [ ] **Step 3: Apply Findings 59–65 in the three event/data functions**

- `TX_enqueueEvent`: second data cell is `(unsigned short)data`, not `data >> 8`. MCR from **new** state. Payload `(newState & 0xFFFF) | (changed << 16)`.
- `RX_dequeueEvent`: hardware-flow `or` uses `0x10` not `STATE_RTS` (`0x04`). `FlowControl` is 32-bit.
- `RX_dequeueData`: empty-ring returns `IO_R_RESOURCE` (`-702`), never `-727`. Flow-control tests are an exclusive if/else chain. Do not wrap `outb` in empty `IOEnterCriticalSection` pairs.

Read each finding in `divergences.md` before editing. Do not unify FIFO/NonFIFO handlers (they are not in this file).

- [ ] **Step 4: Makefile**

```make
CFILES = ISASerialPortFlow.c ISASerialPortQueue.c
```

- [ ] **Step 5: Wait for results-2.md, reline, commit**

```powershell
git add $LKS/ISASerialPortQueue.c $LKS/ISASerialPort.m $LKS/Makefile $RECON/source-map.json $RECON/ledger.json $RECON/divergences.md
git commit -m "drvISASerialPort: extract queue TU and match ring-buffer helpers"
```

Confirm `__OBJC,__module_info` is still 32. Confirm six exports remain `external`.

---

### Task 6: TU 3 shape grind

Unit grind cycle, `UNIT=3`, `FILES=ISASerialPortQueue.c`. Paired names: `_TX_enqueueEvent`, `_RX_dequeueEvent`, `_RX_dequeueData`, `_validateRingBufferSize`, `_freeRingBuffer`, `_allocateRingBuffer`, and the TU 3 `_RX_enqueueLongEvent` copy.

---

### Task 7: TU 2 chip table and extract

**Files:**
- Create: `$LKS/ISASerialPortChip.c`
- Modify: `$LKS/ISASerialPortInternal.h` (add `Chip` typedef and `extern Chip Chip[9]; extern unsigned char msr_state_lut[16];`)
- Modify: `$LKS/ISASerialPort.m` (delete identify/init/program, `chipCapTable`, `chipTypeNames`, identity lut)
- Modify: `$LKS/Makefile` `CFILES`

- [ ] **Step 1: Chip type in Internal.h**

Add, after the `Port` typedef:

```c
typedef struct {
    unsigned long   MaxBaud;
    unsigned int    FIFOsize;
    void          (*IntHandler)(void *identity, void *state, Port *port);
    char           *ShortName;
    char           *LongName;
} Chip;

extern Chip Chip[9];
extern unsigned char msr_state_lut[16];
```

Drop invented `CHIP_16750` / `CHIP_16950` macros. Indices 0–8 are `_Chip` rows. The C symbol is `Chip` so the compiler emits `_Chip`. Both tables are external and non-`const`.

The interrupt handlers stay `static` in `ISASerialPort.m`. `_Chip` therefore cannot live in `ISASerialPortChip.c` (a different TU cannot take the address of a `static`). Define `Chip Chip[9]` and `msr_state_lut[16]` in `ISASerialPort.m` next to those handlers. Chip.c only *reads* the table.

- [ ] **Step 2: Write Chip.c (three functions only) and the tables in ISASerialPort.m**

`ISASerialPortChip.c` must **not** `#import "ISASerialPortEnqueue.h"`.

```c
#import "ISASerialPortInternal.h"
#import <driverkit/i386/ioPorts.h>
```

Move `identifyChip`, `initChip`, `programChip` here.

In `ISASerialPort.m`, file-scope, not `static`, not `const`:

```c
Chip Chip[9] = {
    {      0,  0, NonFIFOIntHandler, "Auto",   "Unknown" },
    {  38400,  0, NonFIFOIntHandler, "8250",   "8250" },
    {  76800,  0, NonFIFOIntHandler, "16450",  "8250A or 16450" },
    {  76800,  0, NonFIFOIntHandler, "16450",  "16C1450" },
    {  76800,  0, NonFIFOIntHandler, "16450",  "16550 with defective FIFO" },
    { 230400, 16, FIFOIntHandler,    "16550",  "16550AF/C/CF" },
    { 230400, 16, FIFOIntHandler,    "16550",  "16C1550" },
    { 921600, 32, FIFOIntHandler,    "16650",  "ST16C650" },
    { 230400,  4, NonFIFOIntHandler, "82510",  "82510" },
};

unsigned char msr_state_lut[16] = {
    0x00, 0x01, 0x08, 0x09, 0x04, 0x05, 0x0C, 0x0D,
    0x02, 0x03, 0x0A, 0x0B, 0x06, 0x07, 0x0E, 0x0F
};
```

Delete `chipCapTable`, `chipTypeNames`, and the identity lut. Handler names in the initializer are the `static` functions in this file; they must be declared before the table.

- [ ] **Step 3: Rewrite identifyChip from Finding 43**

Zero `call` instructions. No `IODelay`. Return a `_Chip` index. Ladder (Finding 43 in `divergences.md`): `t == 0x40` returns 5; `t == 0x80` returns 4 immediately; `t == 0xC0` runs rungs 6 and 7; rung 7 reads MCR without writing it. Size gate: rebuilt extent near 684 bytes.

- [ ] **Step 4: initChip and programChip**

`void initChip(Port *port)`: CharLength 16, StopBits 2, TX_Parity 1, RX_Parity 0, BaudRate 0x4B00, DLRimage 0 (16-bit), FCRimage 0 (8-bit); return if Type == 0; else LCR/IER/MCR zero and `programChip(port)`. No IODelay.

`void programChip(Port *port)`: parity half-bits add 2 when TX_Parity == 1 else 4; baud clamp `if (Chip[Type].MaxBaud < BaudRate) BaudRate = Chip[Type].MaxBaud`; FIFO trigger loop may drive `n` negative; FCR switch types 4, 5, 6, 7 only; 64-bit math is `unsigned long long` `/` and `%`, not four-argument helper calls. Follow Findings 44–52.

- [ ] **Step 5: Makefile**

```make
CFILES = ISASerialPortFlow.c ISASerialPortQueue.c ISASerialPortChip.c
```

- [ ] **Step 6: results-3.md, reline, commit**

```powershell
git add $LKS/ISASerialPortChip.c $LKS/ISASerialPortInternal.h $LKS/ISASerialPort.m $LKS/Makefile $RECON/source-map.json $RECON/ledger.json $RECON/divergences.md
git commit -m "drvISASerialPort: extract chip TU and land Apple Chip table"
```

`__DATA,__data` should be 196. `identifyChip` size against 684.

---

### Task 8: TU 2 shape grind

Unit grind cycle, `UNIT=2`, `FILES=ISASerialPortChip.c` (and the table in `ISASerialPort.m` only if `--name` shows table-driven immediate diffs — prefer Chip.c control flow first).

---

### Task 9: TU 1 algorithm

**Files:** `$LKS/ISASerialPort.m`, `$LKS/ISASerialPort.h`, `$RECON/*`

- [ ] **Step 1: Rename ten underscored locals**

Drop the leading underscore on: `activatePort`, `deactivatePort`, `executeEvent`, `FIFOIntHandler`, `NonFIFOIntHandler`, `PCMCIA_yanked`, `dataLatTOHandler`, `frameTOHandler`, `delayTOHandler`, `heartBeatTOHandler`. They stay `static` so the nlist is `local`. Update call sites.

- [ ] **Step 2: PortDevices and IODirectDevice**

Header already subclasses `IODirectDevice`. Add protocol conformance so `__OBJC,__protocol` matches:

```objc
@interface ISASerialPort : IODirectDevice <PortDevices>
```

If `PortDevices` is not in a DriverKit header the guest has, declare an empty `@protocol PortDevices` in `ISASerialPort.h` matching the reference's instance methods (the PortDevices methods are the ones already on the class: acquire/release/enqueue/dequeue/state). Do not invent extra methods.

Phase 0 already required `instance_size` 604. If Task 2 passed, do not change ivar layout.

- [ ] **Step 3: Config keys (Finding 81)**

In `initFromDeviceDescription:`, send `configTable` once and cache it:

```objc
id table = [[deviceDescription configTable]];
```

Then `[table valueForStringKey:"Instance"]`, `"Chip Type"`, `"Bus Type"`, `"TX Buffer Size"`, `"RX Buffer Size"`, `"Chip Clock"`, `"Heart Beat Interval"`, `"Enable MSR Interrupts"`. Do not send `valueForStringKey:` to the device description.

Cache `configTable` once. Double parsed buffer sizes before `validateRingBufferSize`. TX key writes `TX.DefaultSize`, RX key writes `RX.DefaultSize`. `"Bus Type"` `"PCMCIA"` sets `PCMCIA = 1`. Chip Type loops `i = 0..8` `strcmp(Chip[i].ShortName, str)`. Heart beat default 11000 microseconds. Enable MSR Interrupts present → `IERmask = 0xFF`, absent → `0xFB`.

Do not `[instance free]` in `probe:` after `registerDevice`.

- [ ] **Step 4: Dispatch through Chip[Type].IntHandler**

`frameTOHandler`, `delayTOHandler`, `heartBeatTOHandler`, and `getHandler:level:argument:forInterrupt:` call `Chip[port->Type].IntHandler(0, 0, port)` (or store that pointer). Uncomment the dispatch arms. No `hasFIFO`.

- [ ] **Step 5: Remaining TU 1 findings**

Apply Findings 8–42 and 67–92 as written in `divergences.md`. `setState:mask:` rejects `mask & 0xC0001000`. `executeEvent:data:` must not overwrite `_executeEvent`'s return with 0. Event values are 32-bit, not `event & 0xFF`, except where the reference masks. `STATE_RX_ENABLED` is `0x00400000` where the interrupt handlers use that constant (Finding 10).

- [ ] **Step 6: 64-bit helpers**

Call sites become ordinary `unsigned long long` `/` and `%` (Finding 95). Rewrite `__udivdi3` / `__umoddi3` bodies with 32-bit `div` only (Finding 94) so they do not recurse. Mark them `static`. Do not grind them against libgcc.

- [ ] **Step 7: results-4.md, reline, commit**

```powershell
git add $LKS/ISASerialPort.m $LKS/ISASerialPort.h $RECON/source-map.json $RECON/ledger.json $RECON/divergences.md
git commit -m "drvISASerialPort: match class init, Chip dispatch, and 64-bit helper calls"
```

---

### Task 10: TU 1 shape grind

Unit grind cycle, `UNIT=1`, `FILES=ISASerialPort.m`. Skip `nextEvent` and `release` unless `--list` shows a new regression (revert the causing edit). Unpaired glue and helpers are not ground.

This is the long task. Cheapest `differing` first. One shared cause per experiment cluster.

---

### Task 11: README

**Files:** `src/drivers-i386/README`

Only after Task 10's `--list` shows unpaired leftovers are only the four names in the spec.

Change the input-block line:

```
 * drvISASerialPort - compiles; reconstructed against the reference binary, fixes applied, not yet tested
```

Do not write `complete`. `git diff` must be that one line.

```powershell
git add src/drivers-i386/README
git commit -m "drivers-i386: record the drvISASerialPort reconstruction status"
```

---

## Self-review (spec coverage)

| Spec section | Task |
|---|---|
| Phase 0 harness, rebuilt profile, instance_size 604 | 1–2 |
| `ISASerialPortEnqueue.h`, TU 4 lock, unused static copy | 3 |
| TU 4 byte identity | 4 |
| Queue extract, Findings 53–65 | 5 |
| TU 3 byte identity | 6 |
| Chip table, identify/init/program, no enqueue include in Chip.c | 7 |
| TU 2 byte identity | 8 |
| TU 1 keys, dispatch, helpers, PortDevices, underscore names | 9 |
| TU 1 byte identity | 10 |
| README sibling wording | 11 |
| Guest by controller, no `-All`, no QEMU, no Ghidra, unpaired libgcc | Global constraints |
| `__OBJC,__module_info` 32 | Tasks 3, 5, 7 verify |
| Apple bugs reproduced | Tasks 7, 9 |
