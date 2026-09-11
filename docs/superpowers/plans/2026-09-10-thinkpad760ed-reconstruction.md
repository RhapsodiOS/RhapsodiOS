# drvIBMThinkPad760EDDisplay Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close `drvIBMThinkPad760EDDisplay` against Apple's `IBMThinkPad760EDDisplayDriver_reloc`: in-scope extents, `vidBIOS`/`_emu486` reconstructed from this binary, and `_VERS_STRING` / `_VERS_NUM` linked.

**Architecture:** Two sequential phases. Phase 1 keeps today's four-object link and closes the 12 in-scope extent deltas against a kept rebuilt `_reloc`. Phase 2 reconstructs `vidBIOS.m` and `emu486.s` from this `_reloc` (VGA is a read-only cross-check), links them after `_instance.o` via `OPTIONAL_LDFLAGS`, and adds `$(VERS_OFILE)` in this lksproj's `Makefile.preamble` only.

**Tech Stack:** Python in `.venv-binrecon`, `tools/binrecon`, Rhapsody guest `gnumake` / `pb_makefiles`, `vm/sync-src.ps1` + `vm/build-i386-video-recon.sh`.

**Spec:** [2026-09-10-thinkpad760ed-reconstruction-design.md](../specs/2026-09-10-thinkpad760ed-reconstruction-design.md)

## Global Constraints

```text
VENVPY=D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe
REF=C:/Users/raynorpat/Downloads/test/Drivers/i386/IBMThinkPad760EDDisplayDriver.config/IBMThinkPad760EDDisplayDriver_reloc
REFSHA=47539E03C441BBFD6724EB6778D85BFACD0961B78A8DFA33D56321C938EB5AEC
LKS=src/drivers-i386/video/drvIBMThinkPad760EDDisplay/IBMThinkPad760EDDisplayDriver.drvproj/IBMThinkPad760EDDisplayDriver.lksproj
DRV=src/drivers-i386/video/drvIBMThinkPad760EDDisplay
RECON=src/drivers-i386/video/drvIBMThinkPad760EDDisplay/reconstruction
LEDGER=src/drivers-i386/video/drvIBMThinkPad760EDDisplay/reconstruction/IBMThinkPad760EDDisplayDriver_reloc/ledger.json
MAP=src/drivers-i386/video/drvIBMThinkPad760EDDisplay/reconstruction/IBMThinkPad760EDDisplayDriver_reloc/source-map.json
PROFILE=tools/binrecon/profiles/thinkpad760ed.json
REBUILT=out/i386/drvIBMThinkPad760EDDisplay/IBMThinkPad760EDDisplayDriver.config/IBMThinkPad760EDDisplayDriver_reloc
IDA_REF=tools/binrecon/out/thinkpad760ed/published/analysis-reference-ida.json
VGA_VIDBIOS=src/drivers-i386/video/drvVGA/VGA.drvproj/VGA.lksproj/vidBIOS.m
VGA_EMU=src/drivers-i386/video/drvVGA/VGA.drvproj/VGA.lksproj/emu486.s
```

Work in a dedicated worktree, not the main checkout. `.worktrees/` is gitignored.

```powershell
git worktree add .worktrees/thinkpad760ed-recon HEAD
```

Set `REPO` to that worktree. Run every command from there. `VENVPY` stays `D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe` unless the worktree has its own.

- **Never commit** `$REF`, `tools/binrecon/out/`, `out/i386/`, or throwaway `compare_thinkpad.py`.
- **`BINRECON_REFERENCE` must be exported** in every shell that runs `binrecon` or `parity_check.py`.
- **`BINRECON_REBUILT` must be exported** for `binrecon ledger` and `binrecon compare` (placeholder file only before the first rebuild).
- **Python is `$VENVPY`.** `PYTHONPATH=tools/binrecon`.
- **Do not touch** Cirrus sources, VGA sources, `driverTools`, other drivers, compiler flags, or Ghidra/angr enablement. The shared `vm/build-i386-video-recon.sh` may change **only** the ThinkPad arm and comments about ThinkPad.
- **Do not copy** `$VGA_VIDBIOS` or `$VGA_EMU` into `$LKS` to close a mismatch. This `_reloc` wins. VGA is a diff after a first complete draft.
- **`vidBIOS.m` is not in `CLASSES`. `emu486.s` is not in `OTHERLINKED`.**
- **Commits:** `drvIBMThinkPad760EDDisplay: `, `vm: `, or `docs: ` prefix, one to two lines, no metadata.
- **Reviewer:** `Pat Raynor`.
- **Guest sync:** `powershell -File vm\sync-src.ps1 -Path drivers-i386/video/drvIBMThinkPad760EDDisplay`. If the guest `vm/build-i386-video-recon.sh` is stale, copy that file the same way Cirrus finish does (not `sync-src.ps1 -All`).
- **Guest unreachable:** stop. Record it in `divergences.md`. Do not invent byte diffs. Do not advance the ledger.
- **Accepted compiler-only deltas** start with `initFromDeviceDescription:` (`IOLog` tail merge, +8). Add members only after a rebuilt instruction stream shows the same class of cause. Ledger those `control-flow-confirmed`. `binrecon compare` `normalized-functions` may stay FAIL while any accepted delta remains; that is expected. Every other function must be `assembly-matched` in `compare_thinkpad.py`.

### Guest rebuild (copy this block)

Phase 1 uses `build_objects` (three objects + staged `_reloc`). Phase 2 uses the same script after Task 7 switches the ThinkPad arm.

```powershell
powershell -NoProfile -File vm\sync-src.ps1 -Path drivers-i386/video/drvIBMThinkPad760EDDisplay
. .\vm\rhap-remote.ps1
$cfg = Get-RhapVmConfig
$ssh = Resolve-RhapTool $cfg.Ssh
$ec = Invoke-RhapRemote -Cfg $cfg -Ssh $ssh -RemoteCommand 'tr -d "\r" < /build/source/vm/build-i386-video-recon.sh > /tmp/bvideo.sh && sh /tmp/bvideo.sh drvIBMThinkPad760EDDisplay'
if ($ec -ne 0) { throw "guest build ssh exit $ec" }
$dst = 'out/i386/drvIBMThinkPad760EDDisplay/IBMThinkPad760EDDisplayDriver.config'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
$sshHost = "$($cfg.User)@$($cfg.Host)"
$opts = ($script:RhapLegacySshOptions -join ' ')
$remoteTar = "cd /build/out/i386/drvIBMThinkPad760EDDisplay/IBMThinkPad760EDDisplayDriver.config && tar cf - IBMThinkPad760EDDisplayDriver_reloc"
Invoke-RhapSshAskPass -Cfg $cfg -Action {
    cmd /c "ssh $opts $sshHost `"$remoteTar`" | tar xf - -C $dst"
    if ($LASTEXITCODE -ne 0) { throw "tar pull exit $LASTEXITCODE" }
}
```

`$REBUILT` must exist afterwards. Keep it for the whole session.

Expected Phase 1 guest log: `make exit=0`, `compiled … IBMThinkPad760ED.o`, `compiled … TransferTable.o`, `compiled … smapi.o`, `relocatable link produced …_reloc`. Missing `_emu486` / eight `vidBIOS` strings in `parity_check.py` is expected until Phase 2.

After Task 7: also `compiled … vidBIOS.o`, assembled `emu486.o`, version symbols present, and the script must **not** print `NOTE: … leaves .objc_class_name_vidBIOS`.

### Host compare (throwaway `compare_thinkpad.py`)

Create at worktree root, do not commit. Same masking idea as Cirrus finish.

```python
"""Masked instruction-stream compare for ThinkPad 760ED completion."""
import sys
from pathlib import Path
from binrecon.macho import read_macho

TEXT = "__TEXT,__text"
MATCHED_NAMES = [
    "_set555Mode",
    "-[IBMThinkPad760EDDisplayDriver selectMode]",
    "-[IBMThinkPad760EDDisplayDriver defaultMode]",
    "-[IBMThinkPad760EDDisplayDriver enterLinearMode]",
    "-[IBMThinkPad760EDDisplayDriver isValidPCIAssignedBaseAddress:]",
    "-[IBMThinkPad760EDDisplayDriver getDisplayDeviceState]",
    "-[IBMThinkPad760EDDisplayDriver free]",
    "-[IBMThinkPad760EDDisplayDriver displayModeCount]",
    "-[IBMThinkPad760EDDisplayDriver displayModes]",
    "-[IBMThinkPad760EDDisplayDriver displayMemorySize]",
    "-[IBMThinkPad760EDDisplayDriver ramdacSpeed]",
    "-[IBMThinkPad760EDDisplayDriver readCMOS:]",
    "-[IBMThinkPad760EDDisplayDriver setTransferTable:count:]",
    "-[IBMThinkPad760EDDisplayDriver setBrightness:token:]",
    "-[IBMThinkPad760EDDisplayDriver SetGammaValueRed:Green:Blue:Level:]",
    "-[IBMThinkPad760EDDisplayDriver setGammaTable]",
    "_smapi_asm",
]
GLUE = [
    "+[IBMThinkPad760EDDisplayDriverKernelServerInstance kernelServerInstance]",
    "+[IBMThinkPad760EDDisplayDriverVersion driverKitVersionForIBMThinkPad760EDDisplayDriver]",
]
CAMPAIGN = [
    "-[IBMThinkPad760EDDisplayDriver initFromDeviceDescription:]",
    "-[IBMThinkPad760EDDisplayDriver updateModeTable]",
    "-[IBMThinkPad760EDDisplayDriver revertToVGAMode]",
    "-[IBMThinkPad760EDDisplayDriver getModeInfo:]",
    "-[IBMThinkPad760EDDisplayDriver determineConfiguration:]",
    "-[IBMThinkPad760EDDisplayDriver setPCIConfiguration]",
    "-[IBMThinkPad760EDDisplayDriver setPendingDisplayMode:]",
    "-[IBMThinkPad760EDDisplayDriver setDisplayDeviceState:]",
    "-[IBMThinkPad760EDDisplayDriver unlockRegisters]",
    "-[IBMThinkPad760EDDisplayDriver lockRegisters]",
    "-[IBMThinkPad760EDDisplayDriver reportSystemConfiguration]",
    "-[IBMThinkPad760EDDisplayDriver name]",
]
PHASE2 = [
    "-[vidBIOS init]",
    "-[vidBIOS free]",
    "-[vidBIOS int10:outregs:iorange:ionum:smmport:]",
    "-[vidBIOS int10:outregs:iorange:ionum:]",
    "-[vidBIOS scratchSegment]",
    "-[vidBIOS realToVirtual::]",
    "_emu486",
]


def _text(doc, data):
    for section in doc["sections"]:
        if section["name"] == TEXT:
            off, size = section["offset"], section["size"]
            return bytearray(data[off:off + size]), section["address"], off
    raise SystemExit("no __TEXT,__text")


def _extents(doc):
    names = {}
    text_syms = [s for s in doc["symbols"] if s.get("section") == TEXT]
    text_syms.sort(key=lambda s: (s["address"], s["name"]))
    addrs = [s["address"] for s in text_syms]
    for i, s in enumerate(text_syms):
        end = addrs[i + 1] if i + 1 < len(addrs) else None
        if end is None:
            for sec in doc["sections"]:
                if sec["name"] == TEXT:
                    end = sec["address"] + sec["size"]
        names[s["name"]] = (s["address"], end - s["address"])
    return names


def _mask(buf, addr0, relocs):
    for rel in relocs:
        if rel.get("width") != 4:
            continue
        a = rel["address"]
        if addr0 <= a < addr0 + len(buf):
            o = a - addr0
            buf[o:o + 4] = b"\x00\x00\x00\x00"
    return buf


def slice_fn(buf, addr0, start, size):
    o = start - addr0
    return buf[o:o + size]


def _report(label, names, ref_ext, reb_ext, ref_buf, reb_buf, ref_a0, reb_a0):
    failed = 0
    print("---", label, "---")
    for name in names:
        if name not in reb_ext:
            print("MISSING", name)
            failed += 1
            continue
        rs, rz = ref_ext[name]
        bs, bz = reb_ext[name]
        r = slice_fn(ref_buf, ref_a0, rs, rz)
        b = slice_fn(reb_buf, reb_a0, bs, bz)
        ok = r == b
        print(("MATCH" if ok else "DIFF "), name, "ref", rz, "reb", bz)
        if not ok:
            failed += 1
    return failed


def main(ref_path, rebuilt_path):
    ref_p, reb_p = Path(ref_path), Path(rebuilt_path)
    ref_doc, reb_doc = read_macho(ref_p), read_macho(reb_p)
    ref_buf, ref_a0, _ = _text(ref_doc, ref_p.read_bytes())
    reb_buf, reb_a0, _ = _text(reb_doc, reb_p.read_bytes())
    _mask(ref_buf, ref_a0, ref_doc["relocations"])
    _mask(reb_buf, reb_a0, reb_doc["relocations"])
    ref_ext, reb_ext = _extents(ref_doc), _extents(reb_doc)
    failed = 0
    failed += _report("matched", MATCHED_NAMES, ref_ext, reb_ext, ref_buf, reb_buf, ref_a0, reb_a0)
    failed += _report("glue", GLUE, ref_ext, reb_ext, ref_buf, reb_buf, ref_a0, reb_a0)
    _report("campaign", CAMPAIGN, ref_ext, reb_ext, ref_buf, reb_buf, ref_a0, reb_a0)
    if "_emu486" in reb_ext:
        _report("phase2", PHASE2, ref_ext, reb_ext, ref_buf, reb_buf, ref_a0, reb_a0)
    print("failed_matched_or_glue", failed)
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1], sys.argv[2]))
```

```powershell
$env:PYTHONPATH = 'tools/binrecon'
$env:BINRECON_REFERENCE = $REF
& $VENVPY compare_thinkpad.py $env:BINRECON_REFERENCE $REBUILT
```

`failed_matched_or_glue` must stay 0 after every rebuild. Campaign `DIFF` is expected until that function closes or is listed as compiler-only. Phase 2 names are `MISSING` until Task 8.

### Ledger command

```powershell
$env:BINRECON_REFERENCE = $REF
$env:BINRECON_REBUILT = (Resolve-Path $REBUILT).Path
$env:PYTHONPATH = 'tools/binrecon'
& $VENVPY -m binrecon ledger --profile $PROFILE --ledger $LEDGER `
  --address $ADDR --status assembly-matched `
  --reason "Rebuilt instruction stream matches the reference under 32-bit relocation masking." `
  --reviewer "Pat Raynor" `
  --source-path $SRC --source-line $LINE
```

Do not claim `assembly-matched` unless `compare_thinkpad.py` printed `MATCH` for that name. Compiler-only: `--status control-flow-confirmed` and a reason that names the mechanism.

## File Structure

**Created:**
- `$LKS/vidBIOS.m`
- `$LKS/emu486.s`
- `$LKS/Makefile.preamble` contents (file exists empty)

**Modified:**
- `$LKS/IBMThinkPad760ED.m` (Phase 1 extents; Phase 2 `biosRegs` → `emu486regs_t`)
- `$LKS/IBMThinkPad760ED.h` (Phase 2 `vidBIOS` interface)
- `$LKS/Makefile` only if Project Builder fields must list `vidBIOS.m` / `emu486.s` in `OTHERSRCS` so they ship in the project; they still must not enter `CLASSES` / `OTHERLINKED`
- `vm/build-i386-video-recon.sh` (ThinkPad arm only)
- `$RECON/divergences.md`, `$LEDGER`, `$MAP`
- `src/drivers-i386/README`

**Unchanged:**
- `$LKS/TransferTable.m`, `$LKS/smapi.s` unless a rebuild proves a regression
- Config tables / `English.lproj`
- `tools/binrecon/profiles/thinkpad760ed.json` (path variables already correct)
- drvVGA, drvCirrusLogicGD5434 sources

---

### Task 1: Baseline rebuild and compare harness

**Files:**
- Create (untracked): `compare_thinkpad.py` at worktree root
- Modify: `$RECON/divergences.md` only if the guest is unreachable (record that and stop)

- [ ] **Step 1: Write `compare_thinkpad.py`**

Paste the script from Global Constraints. Do not commit it.

- [ ] **Step 2: Guest rebuild of the current tree**

Run the Guest rebuild block. Current tree already contains the uncompiled `1cb44e28` edits (`name` ternary, `updateModeTable` subscripts, `determineConfiguration:` common-path CR2A, duplicated 0x100D SMAPI). If it does not compile, fix those four methods until `make exit=0` before any new extent work.

- [ ] **Step 3: Measure**

```powershell
$env:PYTHONPATH = 'tools/binrecon'
$env:BINRECON_REFERENCE = $REF
& $VENVPY tools/binrecon/parity_check.py $REF $REBUILT
& $VENVPY compare_thinkpad.py $REF $REBUILT
```

Expected: `parity_check.py` missing `_emu486` and 8 strings; extras are stabs. `failed_matched_or_glue` is 0. Print the twelve campaign `ref`/`reb` sizes into `$RECON/divergences.md` under a new "Phase 1 baseline (this rebuild)" table. `initFromDeviceDescription:` may still be `DIFF` (+8); that is the accepted compiler-only starting member.

- [ ] **Step 4: Commit the table only if you edited `divergences.md`**

```powershell
git add $RECON/divergences.md
git commit -m "drvIBMThinkPad760EDDisplay: record Phase 1 baseline extents from guest rebuild"
```

If the only local file is untracked `compare_thinkpad.py`, skip the commit.

---

### Task 2: Nested `unlockRegisters` / `lockRegisters`

**Files:**
- Modify: `$LKS/IBMThinkPad760ED.m` (those two methods only)
- Modify: `$RECON/divergences.md`

Do this only if Task 1 still shows `DIFF` and sizes 152 vs 168. If already `MATCH`, skip to Task 2 Step 4 with no source change.

- [ ] **Step 1: Fold the RMW into one expression**

Replace both methods with:

```objc
- (void)unlockRegisters
{
    outb(0x3C4, 0x08);
    if ((signed char)inb(0x3C5) >= 0) {
	outb(0x3C4, 0x0B);
	inb(0x3C5);
	outb(0x3C4, 0x0E);
	outb(0x3C5, inb(0x3C5) | 0x80);
	outw(0x3C4, 0x000B);
    } else {
	outb(0x3C4, 0x0E);
	outb(0x3C5, inb(0x3C5) | 0x80);
    }
}

- (void)lockRegisters
{
    outb(0x3C4, 0x08);
    if ((signed char)inb(0x3C5) >= 0) {
	outb(0x3C4, 0x0B);
	inb(0x3C5);
	outb(0x3C4, 0x0E);
	outb(0x3C5, inb(0x3C5) & 0x7F);
	outw(0x3C4, 0x000B);
    } else {
	outb(0x3C4, 0x0E);
	outb(0x3C5, inb(0x3C5) & 0x7F);
    }
}
```

- [ ] **Step 2: Rebuild and compare**

Guest rebuild block. `compare_thinkpad.py`: both methods `MATCH` at extent 168. `failed_matched_or_glue` still 0. If still `DIFF`, revert this edit and stop for this pair — do not invent a third shape.

- [ ] **Step 3: Update `divergences.md`**

Record predicted 152→168 closed or still open.

- [ ] **Step 4: Commit**

```powershell
git add $LKS/IBMThinkPad760ED.m $RECON/divergences.md
git commit -m "drvIBMThinkPad760EDDisplay: nest unlock/lock sequencer RMW to match reference"
```

---

### Task 3: Remaining in-scope campaign

**Files:**
- Modify: `$LKS/IBMThinkPad760ED.m` (only the method under test)
- Modify: `$RECON/divergences.md`

`failed_matched_or_glue` must stay 0. One experiment per rebuild. Miss → revert that experiment before the next. Do not stack unmeasured edits.

For each still-`DIFF` campaign name except `initFromDeviceDescription:` (already accepted):

- [ ] **Step 1: `setDisplayDeviceState:` (−4)**

If still `DIFF`, try only this association (same value, different HImode):

```objc
    reg.cx.x = ((state & 3) << 8) | 0x8000;
```

in place of `((state & 3) | 0x80) << 8`. Rebuild. `MATCH` → keep. Else revert.

- [ ] **Step 2: `reportSystemConfiguration` (+28)**

Disassemble the rebuilt prologue. If it contains `sub esp`, the spill hypothesis is confirmed: keep `vendor` / `panelType` / `panelSize` as immediates by inlining the string literals in each `IOLog` (no pointer locals). Rebuild. If there is no `sub esp`, do not chase stack; record the rebuilt prologue bytes and leave `control-flow-confirmed` only if statement-for-statement identity still holds.

- [ ] **Step 3: `setPCIConfiguration` (−12)**

Compare rebuilt frame to the reference `sub esp, 0x124` layout in `divergences.md`. First experiment: declare `IORange range[3]` before `IOPCIConfigSpace configSpace`. Miss → revert, then try matching Cirrus finish's `rangeCount == 3` success-path shape **without** changing log strings or call targets. Miss → revert and record.

- [ ] **Step 4: `getModeInfo:` (−4) and `revertToVGAMode` (−4)**

Do not retry "hold `&regs` in a callee-saved register" — `divergences.md` refuted that. Diff the rebuilt stream against the reference. Change only what the diff names (including `bzero` size or `int10:` argument shape). One edit per rebuild.

- [ ] **Step 5: Re-measure `name`, `updateModeTable`, `determineConfiguration:`, `setPendingDisplayMode:`**

These four are already in the tree from `1cb44e28`. If Task 1 left any `DIFF`, do not blindly rewrite; diff first. `name` should be the ternary already. `updateModeTable` should already subscript. `determineConfiguration:` should already write CR2A on the common path. `setPendingDisplayMode:` should already duplicate the 0x100D block.

- [ ] **Step 6: Commit**

```powershell
git add $LKS/IBMThinkPad760ED.m $RECON/divergences.md
git commit -m "drvIBMThinkPad760EDDisplay: close remaining in-scope extent campaign"
```

---

### Task 4: Freeze Phase 1 accepted deltas

**Files:**
- Modify: `$RECON/divergences.md`
- Modify: `$LEDGER` only for in-scope functions whose status is now evidenced
- Modify: `$MAP` if `source_line` moved

- [ ] **Step 1: Write the accepted-compiler list**

In `divergences.md`, a table of remaining `DIFF` campaign functions with mechanism. `initFromDeviceDescription:` stays on it unless this rebuild actually `MATCH`ed. No other function joins it without a named compiler mechanism.

- [ ] **Step 2: Ledger in-scope functions that `MATCH`**

For each `MATCH` name in `MATCHED_NAMES` + closed campaign + `GLUE` if matched, `binrecon ledger` → `assembly-matched`. For each accepted compiler-only name → `control-flow-confirmed`. Leave `vidBIOS` / `_emu486` / unnamed 15796 / 15877 `unexamined` until Phase 2. `rebuilt_sha256` must become the guest file's SHA-256 (not `$REFSHA`).

- [ ] **Step 3: Commit**

```powershell
git add $RECON/divergences.md $LEDGER $MAP
git commit -m "drvIBMThinkPad760EDDisplay: ledger Phase 1 extents against guest rebuild"
```

---

### Task 5: `vidBIOS.m` from this binary

**Files:**
- Create: `$LKS/vidBIOS.m`
- Modify: `$LKS/IBMThinkPad760ED.h`
- Modify: `$LKS/IBMThinkPad760ED.m` (`biosRegs` typedef removed; uses `emu486regs_t`)

Do not add `vidBIOS.m` to `CLASSES`. Do not guest-build this task (link order is Task 7).

- [ ] **Step 1: Header — shared register type and `vidBIOS` interface**

In `$LKS/IBMThinkPad760ED.h`, after `#import <driverkit/IOFrameBufferDisplay.h>`:

Remove `@class vidBIOS;`.

Add (before `struct smapiReg`):

```objc
#import <objc/Object.h>
#import <driverkit/driverTypes.h>

typedef struct {
    unsigned int	eax, ecx, edx, ebx;
    unsigned int	esp, ebp, esi, edi;
    unsigned int	eip, eflags;
    unsigned int	es, cs, ss, ds, fs, gs;
} emu486regs_t;

extern int	emu486(void *lowMemBase, const emu486regs_t *inregs,
		       emu486regs_t *outregs, const char *pagePerm,
		       const char *ioPerm, unsigned int smmport);

@interface vidBIOS : Object
{
    void	       *biosStackVirtual;
    unsigned int	biosStackPhysical;
    unsigned int	lowMem;
}
- init;
- free;
- (int)int10	: (const emu486regs_t *)inregs
	outregs	: (emu486regs_t *)outregs
	iorange	: (const IORange *)ranges
	  ionum	: (int)nranges;
- (int)int10	: (const emu486regs_t *)inregs
	outregs	: (emu486regs_t *)outregs
	iorange	: (const IORange *)ranges
	  ionum	: (int)nranges
	smmport	: (unsigned int)smmport;
- (unsigned int)scratchSegment;
- (void *)realToVirtual:(unsigned int)segment :(unsigned int)offset;
@end
```

Keep `vidBIOS *bios;` in the driver ivars.

- [ ] **Step 2: Replace `biosRegs` in `IBMThinkPad760ED.m`**

Delete the file-static `typedef struct { … } biosRegs;`. Change every `biosRegs` to `emu486regs_t`.

- [ ] **Step 3: Write `$LKS/vidBIOS.m` from this `_reloc` at 6552–7708**

Decompile the six methods from `$IDA_REF` / IDA of `$REF` (starts 6552, not VGA's 6396). Control flow, strings, and calls must match this binary.

This `_reloc` attributes `_xxx.8` / `_xxx.11` / `_xxx.14` to the deferred region. If those statics belong to `vidBIOS.m`, `#import <driverkit/i386/ioPorts.h>` here even though VGA's `vidBIOS.m` does not. If they do not, omit that header.

Do not add `__data` / `__bss` / `__const` / file-static counters.

Method bodies follow the same shape as `$VGA_VIDBIOS` only where this binary agrees: `IOMallocLow` / `IOPhysicalFromVirtual` / `IOMapPhysicalIntoIOTask` in `-init`, four `IOLog` failure strings at `__cstring` 19296–19453, five-argument `-int10:…smmport:` building `pagePerm[256]` and `ioPerm` 0x2000, `emu486(...)`, four `IOLog`s on `err`, four-argument `-int10:` forwarding with `smmport:0x10000`, `scratchSegment` as `biosStackPhysical >> 4`, `realToVirtual::` as `(segment << 4) + lowMem + offset`.

Write no shared `fail:` label in `-init` (cross-jumped tails).

- [ ] **Step 4: Cross-check VGA, do not copy**

Diff the new file against `$VGA_VIDBIOS`. Record every disagreement in `divergences.md` with ThinkPad address and VGA address. Keep ThinkPad.

- [ ] **Step 5: Commit**

```powershell
git add $LKS/vidBIOS.m $LKS/IBMThinkPad760ED.h $LKS/IBMThinkPad760ED.m $RECON/divergences.md
git commit -m "drvIBMThinkPad760EDDisplay: reconstruct vidBIOS.m from this reloc"
```

---

### Task 6: `emu486.s` from this binary

**Files:**
- Create: `$LKS/emu486.s`
- Modify: `$RECON/divergences.md`

Do not add `emu486.s` to `OTHERLINKED` (that would place it before `_instance.o`).

- [ ] **Step 1: Dump this `__text` 7708–18204**

From `$REF` via `binrecon.macho.read_macho`, slice `__TEXT,__text` bytes at address 7708 through section end (18204). Size is 10496. `_emu486` is the only exported symbol. Unnamed bodies at 15796 and 15877 stay inside this file as `L`-prefixed labels, not `.globl`.

- [ ] **Step 2: Transcribe**

Hand-written i386 assembly. `_emu486` is `.globl`. All interior labels are `L` + ThinkPad `__text` address (so they stay out of the symbol table). Entry contract:

```
int emu486(void *lowMemBase, const emu486regs_t *inregs, emu486regs_t *outregs,
           const char *pagePerm, const char *ioPerm, unsigned int smmport);
```

Transcribe Apple's three emulator defects; do not repair them. `cmpxchg` as i486 A-step `0F A6` / `0F A7`. Long-form branches where the reference used them.

`$VGA_EMU` is a second copy of the same source at `__text` 7552 (156 bytes lower). After a first complete draft, compare instruction streams with a uniform +156 offset. If they match, record that. If they do not, this dump wins — do not paste VGA bytes over a mismatch.

- [ ] **Step 3: Host-assemble check (optional)**

If a GNU assembler targeting i386 is available on the host, assemble and confirm the object defines only `_emu486`. Guest assembly in Task 8 is the real gate.

- [ ] **Step 4: Commit**

```powershell
git add $LKS/emu486.s $RECON/divergences.md
git commit -m "drvIBMThinkPad760EDDisplay: transcribe emu486.s from this reloc"
```

---

### Task 7: Link order, `VERS_OFILE`, harness

**Files:**
- Modify: `$LKS/Makefile.preamble`
- Modify: `$LKS/Makefile` (`OTHERSRCS` may list `vidBIOS.m emu486.s`; `CLASSES` stays `IBMThinkPad760ED.m TransferTable.m`; `OTHERLINKED` stays `smapi.s`)
- Modify: `vm/build-i386-video-recon.sh`

- [ ] **Step 1: `Makefile.preamble`**

Replace the empty file with:

```make
# Always generate a version file. Apple's kernelserver.make.preamble does
# this when installed; we do not install that preamble on the guest.
ifndef VERSIONING_SYSTEM
    VERSIONING_SYSTEM = next-sgs
endif
ifeq "" "$(findstring $(VERS_OFILE), $(OTHER_GENERATED_OFILES))"
    OTHER_GENERATED_OFILES += $(VERS_OFILE)
endif

# vidBIOS.o and emu486.o must follow IBMThinkPad760EDDisplayDriver_instance.o.
# CLASSES would put vidBIOS.o before smapi.o; OTHERLINKED would put emu486.o
# before the instance object. The harness builds the two objects and passes
# absolute paths in these variables; kl_ld sees them via OPTIONAL_LDFLAGS.
OPTIONAL_LDFLAGS = $(VIDBIOS_I386) $(EMU486_I386)
```

`vers.o` must not insert `__text` between `smapi.o` and `_instance.o`. If Task 8 shows instance not at 6528 relative to the in-scope span, fix this preamble/harness, not reconstructed functions.

- [ ] **Step 2: `Makefile` OTHERSRCS**

Add `vidBIOS.m` and `emu486.s` to `OTHERSRCS` so they are part of the project. Do not add them to `CLASSES` or `OTHERLINKED`.

- [ ] **Step 3: ThinkPad arm of `vm/build-i386-video-recon.sh`**

Before `gnumake` for ThinkPad:

1. `cd` to the lksproj directory.
2. Compile `vidBIOS.m` with the same `cc` line the log used for `IBMThinkPad760ED.m` (copy that recipe from the Phase 1 build log; substitute the source and `-o vidBIOS.i386.o`).
3. Assemble `emu486.s` with the same `as` line the log used for `smapi.s` (substitute `-o emu486.i386.o`).
4. `export VIDBIOS_I386=`pwd`/vidBIOS.i386.o` and `export EMU486_I386=`pwd`/emu486.i386.o` so `gnumake` expands `OPTIONAL_LDFLAGS`.
5. After a successful `_reloc`, require `.objc_class_name_vidBIOS` **absent** from `nm -u` and `_emu486` **present** as a defined symbol. Fail the arm if not.
6. Delete the two `NOTE:` lines about leaving vidBIOS undefined.
7. Stage `_VERS_STRING` presence: `nm` the `_reloc` for `_IBMThinkPad760EDDisplayDriver_VERS_STRING` and `_IBMThinkPad760EDDisplayDriver_VERS_NUM`. Warn (do not fail the whole video script's Cirrus arm) if missing; fail the ThinkPad arm.

Keep Cirrus on `build_reloc` unchanged.

- [ ] **Step 4: Commit**

```powershell
git add $LKS/Makefile.preamble $LKS/Makefile vm/build-i386-video-recon.sh
git commit -m "drvIBMThinkPad760EDDisplay: link vidBIOS and emu486 after instance; emit VERS_OFILE"
```

---

### Task 8: Phase 2 guest build, parity, compare

**Files:**
- Modify: `$RECON/divergences.md`
- Untracked: `$REBUILT`

- [ ] **Step 1: Sync harness and driver, rebuild**

Sync both `drvIBMThinkPad760EDDisplay` and `vm/build-i386-video-recon.sh`. Guest rebuild block. Keep `$REBUILT`.

Confirm `kl_ld` object order is:

```
IBMThinkPad760ED.o TransferTable.o smapi.o
IBMThinkPad760EDDisplayDriver_vers.o
IBMThinkPad760EDDisplayDriver_instance.o
vidBIOS.o emu486.o
```

(`vers.o` may appear as `$(NAME)_vers.o`. Paths may be arch-suffixed.)

- [ ] **Step 2: `parity_check.py`**

```powershell
$env:PYTHONPATH = 'tools/binrecon'
$env:BINRECON_REFERENCE = $REF
& $VENVPY tools/binrecon/parity_check.py $REF $REBUILT
```

Expected: 0 missing symbols, 0 missing strings. Stab extras only.

- [ ] **Step 3: `compare_thinkpad.py` and `binrecon compare`**

```powershell
$env:BINRECON_REBUILT = (Resolve-Path $REBUILT).Path
& $VENVPY compare_thinkpad.py $REF $REBUILT
& $VENVPY -m binrecon compare --profile $PROFILE
```

`failed_matched_or_glue` is 0. Phase 2 names: `MATCH` or recorded compiler-only. `normalized-functions` may be false if any accepted compiler-only function remains; record `acceptance.passed` in `divergences.md`. Every function not on that list must be `MATCH`.

If `vers.o` shifted `__text`, fix Task 7 artifacts and rebuild. Do not pad reconstructed functions.

- [ ] **Step 4: Commit divergences only**

```powershell
git add $RECON/divergences.md
git commit -m "drvIBMThinkPad760EDDisplay: record Phase 2 parity and compare against guest reloc"
```

---

### Task 9: Source map, ledger, README

**Files:**
- Modify: `$MAP`, `$LEDGER`, `$RECON/divergences.md`, `src/drivers-i386/README`

- [ ] **Step 1: Refresh source map**

```powershell
$env:PYTHONPATH = 'tools/binrecon'
$env:BINRECON_REFERENCE = $REF
$env:BINRECON_REBUILT = (Resolve-Path $REBUILT).Path
& $VENVPY -m binrecon source-map `
  --reference-analysis $IDA_REF `
  --binary $REF `
  --source-dir $LKS `
  --repo-root . `
  --objc-methods `
  --output $MAP
```

All 40 entries `mapped`. `_smapi_asm` → `smapi.s`. Instance glue → generated `_instance.m` (or null path with generated reason — match existing Cirrus/VGA maps). `vidBIOS` methods → `vidBIOS.m`. `_emu486` and 15796/15877 → `emu486.s`. `unmapped` is empty.

- [ ] **Step 2: Advance every ledger entry**

`rebuilt_sha256` is the guest artifact. `MATCH` → `assembly-matched`. Accepted compiler-only → `control-flow-confirmed`. Reviewer `Pat Raynor`. No leftover `unexamined`.

- [ ] **Step 3: README**

Replace the ThinkPad bullet in `src/drivers-i386/README` with: reconstructed against the reference, built, ledger advanced, not hardware-tested.

- [ ] **Step 4: Commit**

```powershell
git add $MAP $LEDGER $RECON/divergences.md src/drivers-i386/README
git commit -m "drvIBMThinkPad760EDDisplay: map and ledger the completed reloc"
```

---

## Self-review vs spec

| Spec requirement | Task |
| --- | --- |
| Phase 1 four-object rebuild, keep `_reloc` | 1 |
| Close 12 extents; `1cb44e28` through compiler | 1–3 |
| Nested unlock/lock | 2 |
| Accepted compiler-only; `initFromDeviceDescription:` | 3–4 |
| `vidBIOS.m` from this binary, not `CLASSES` | 5, 7 |
| `emu486.s` from this binary, not `OTHERLINKED`; defects transcribed | 6, 7 |
| VGA read-only cross-check | 5–6 |
| `OTHER_GENERATED_OFILES += $(VERS_OFILE)` in this preamble only | 7 |
| `OPTIONAL_LDFLAGS` after instance | 7 |
| ThinkPad-only harness; drop undefined NOTE | 7 |
| `parity_check.py` 0 missing after Phase 2 | 8 |
| `binrecon compare` run; pass not required if accepted deltas remain | 8 |
| Source map 40 mapped; ledger off `unexamined`; README | 9 |
| No QEMU, no Cirrus/VGA source edits, no guest preamble install | Global Constraints |
