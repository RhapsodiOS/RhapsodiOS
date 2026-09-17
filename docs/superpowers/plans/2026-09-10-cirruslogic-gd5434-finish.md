# drvCirrusLogicGD5434 Finish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close `drvCirrusLogicGD5434` against Apple's `CirrusLogicGD5434DisplayDriver_reloc` by landing `strcmp`, wiring local `VERS_OFILE`, and chasing the four unmatched functions until each is `assembly-matched` or proven unreachable.

**Architecture:** Sequential measured close. One edit, guest rebuild, masked instruction-stream diff, then the next edit. The 17 already-identical functions are a regression gate. Source-shape only; no compiler flags; no shared `driverTools`.

**Tech Stack:** Python in `.venv-binrecon`, `tools/binrecon`, Rhapsody guest `gnumake` / `pb_makefiles`, `vm/sync-src.ps1` + `vm/build-i386-video-recon.sh`.

**Spec:** [2026-09-10-cirruslogic-gd5434-finish-design.md](../specs/2026-09-10-cirruslogic-gd5434-finish-design.md)

## Global Constraints

```text
VENVPY=D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe
REF=C:/Users/raynorpat/Downloads/test/Drivers/i386/CirrusLogicGD5434DisplayDriver.config/CirrusLogicGD5434DisplayDriver_reloc
REFSHA=7DA038CCEA1CDE68B6CF2ACF4D12EE5056E7F0248ADD34D451FB96EA79C13D0D
LKS=src/drivers-i386/video/drvCirrusLogicGD5434/CirrusLogicGD5434.drvproj/CirrusLogicGD5434DisplayDriver.lksproj
DRV=src/drivers-i386/video/drvCirrusLogicGD5434/CirrusLogicGD5434.drvproj
RECON=src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction
LEDGER=src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/CirrusLogicGD5434DisplayDriver_reloc/ledger.json
MAP=src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/CirrusLogicGD5434DisplayDriver_reloc/source-map.json
PROFILE=tools/binrecon/profiles/cirruslogic-gd5434.json
REBUILT=out/i386/drvCirrusLogicGD5434/CirrusLogicGD5434DisplayDriver.config/CirrusLogicGD5434DisplayDriver_reloc
BUNDLE=out/i386/drvCirrusLogicGD5434/CirrusLogicGD5434DisplayDriver.config/CirrusLogicGD5434DisplayDriver
```

Work in a dedicated worktree, not the main checkout. `.worktrees/` is gitignored.

```powershell
git worktree add .worktrees/cirrus-gd5434-finish HEAD
```

Set `REPO` to that worktree and run every command from there. `VENVPY` stays the main-repo venv (`D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe`) unless the worktree has its own.

- **Never commit** `$REF`, `tools/binrecon/out/`, `out/i386/`, or the throwaway `compare_cirrus.py`.
- **`BINRECON_REFERENCE` must be exported** in every shell that runs `binrecon` or `parity_check.py`.
- **`BINRECON_REBUILT` must be exported** for `binrecon ledger` (point at `$REBUILT` after it exists; a placeholder file is fine only before the first rebuild).
- **Python is `$VENVPY`.** `PYTHONPATH=tools/binrecon`.
- **Do not touch** ThinkPad, VGA, `driverTools`, other drivers, compiler flags, Ghidra/angr enablement, or the glue methods.
- **Forbidden source shapes:** unsigned `chipType` ivar; `switch` on `chipType`.
- **`strcmp` and the two postamble lines stay** even if they do not close an extent gap. Experiments revert on miss.
- **Commits:** `drvCirrusLogicGD5434: ` or `docs: ` prefix, one to two lines, no metadata.
- **Reviewer:** `Pat Raynor`.
- **Guest sync:** `powershell -File vm\sync-src.ps1 -Path drivers-i386/video/drvCirrusLogicGD5434`. Also sync `vm/build-i386-video-recon.sh` if the guest copy is missing (`-Path` cannot upload `vm/`; copy that file with the same tar-over-ssh path `sync-src.ps1` uses, or a one-off `Invoke-RhapRemote` `cat`). Do not `sync-src.ps1 -All`.
- **Guest unreachable:** stop the campaign, record that in `divergences.md`, do not invent byte diffs.

### Guest rebuild (copy this block)

```powershell
powershell -NoProfile -File vm\sync-src.ps1 -Path drivers-i386/video/drvCirrusLogicGD5434
. .\vm\rhap-remote.ps1
$cfg = Get-RhapVmConfig
$ssh = Resolve-RhapTool $cfg.Ssh
$ec = Invoke-RhapRemote -Cfg $cfg -Ssh $ssh -RemoteCommand 'tr -d "\r" < /build/source/vm/build-i386-video-recon.sh > /tmp/bvideo.sh && sh /tmp/bvideo.sh drvCirrusLogicGD5434'
if ($ec -ne 0) { throw "guest build ssh exit $ec" }
$dst = 'out/i386/drvCirrusLogicGD5434/CirrusLogicGD5434DisplayDriver.config'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
$sshHost = "$($cfg.User)@$($cfg.Host)"
$opts = ($script:RhapLegacySshOptions -join ' ')
# cmd.exe pipe is binary-safe on Windows PowerShell 5.x; PowerShell `|` is not.
$remoteTar = "cd /build/out/i386/drvCirrusLogicGD5434/CirrusLogicGD5434DisplayDriver.config && tar cf - CirrusLogicGD5434DisplayDriver_reloc CirrusLogicGD5434DisplayDriver"
Invoke-RhapSshAskPass -Cfg $cfg -Action {
    cmd /c "ssh $opts $sshHost `"$remoteTar`" | tar xf - -C $dst"
    if ($LASTEXITCODE -ne 0) { throw "tar pull exit $LASTEXITCODE" }
}
```

`$REBUILT` must exist afterwards. If the version bundle is absent the tar warning is fine until Task 3.

Expected guest log: `make exit=0`, `staged .../CirrusLogicGD5434DisplayDriver_reloc`. After Task 3 the log must also contain `staged version bundle CirrusLogicGD5434DisplayDriver` and must not print `WARNING: no CirrusLogicGD5434DisplayDriver version bundle produced`.

### Host compare (throwaway `compare_cirrus.py`)

Create at worktree root, do not commit:

```python
"""Masked instruction-stream compare for Cirrus GD5434 finish pass."""
import sys
from pathlib import Path
from binrecon.macho import read_macho

TEXT = "__TEXT,__text"
MATCHED_NAMES = [
    "-[CirrusLogicGD5434DisplayDriver initFromDeviceDescription:]",
    "-[CirrusLogicGD5434DisplayDriver selectMode]",
    "-[CirrusLogicGD5434DisplayDriver enterLinearMode]",
    "-[CirrusLogicGD5434DisplayDriver revertToVGAMode]",
    "-[CirrusLogicGD5434DisplayDriver isValidPCIAssignedBaseAddress:]",
    "-[CirrusLogicGD5434DisplayDriver clearScreen]",
    "-[CirrusLogicGD5434DisplayDriver name]",
    "-[CirrusLogicGD5434DisplayDriver displayModeCount]",
    "-[CirrusLogicGD5434DisplayDriver displayModes]",
    "-[CirrusLogicGD5434DisplayDriver displayMemorySize]",
    "-[CirrusLogicGD5434DisplayDriver ramdacSpeed]",
    "-[CirrusLogicGD5434DisplayDriver(ProgramDAC) setTransferTable:count:]",
    "-[CirrusLogicGD5434DisplayDriver(ProgramDAC) setBrightness:token:]",
    "_SetGammaValue",
    "-[CirrusLogicGD5434DisplayDriver(ProgramDAC) setGammaTable]",
]
GLUE = [
    "+[CirrusLogicGD5434DisplayDriverKernelServerInstance kernelServerInstance]",
    "+[CirrusLogicGD5434DisplayDriverVersion driverKitVersionForCirrusLogicGD5434DisplayDriver]",
]
CAMPAIGN = [
    "-[CirrusLogicGD5434DisplayDriver determineConfiguration]",
    "-[CirrusLogicGD5434DisplayDriver setPCIConfiguration]",
    "-[CirrusLogicGD5434DisplayDriver setMode:]",
    "-[CirrusLogicGD5434DisplayDriver setPendingDisplayMode:]",
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


def main(ref_path, rebuilt_path):
    ref_p, reb_p = Path(ref_path), Path(rebuilt_path)
    ref_doc, reb_doc = read_macho(ref_p), read_macho(reb_p)
    ref_buf, ref_a0, _ = _text(ref_doc, ref_p.read_bytes())
    reb_buf, reb_a0, _ = _text(reb_doc, reb_p.read_bytes())
    _mask(ref_buf, ref_a0, ref_doc["relocations"])
    _mask(reb_buf, reb_a0, reb_doc["relocations"])
    ref_ext, reb_ext = _extents(ref_doc), _extents(reb_doc)
    failed = 0
    for name in MATCHED_NAMES + GLUE:
        rs, rz = ref_ext[name]
        bs, bz = reb_ext[name]
        r = slice_fn(ref_buf, ref_a0, rs, rz)
        b = slice_fn(reb_buf, reb_a0, bs, bz)
        ok = r == b
        print(("MATCH" if ok else "DIFF "), name, "ref", rz, "reb", bz)
        if not ok:
            failed += 1
    print("--- campaign ---")
    for name in CAMPAIGN:
        rs, rz = ref_ext[name]
        bs, bz = reb_ext[name]
        r = slice_fn(ref_buf, ref_a0, rs, rz)
        b = slice_fn(reb_buf, reb_a0, bs, bz)
        print(("MATCH" if r == b else "DIFF "), name, "ref", rz, "reb", bz)
    # call targets for determineConfiguration: count CALL rel32 to symbols
    print("failed_matched", failed)
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1], sys.argv[2]))
```

```powershell
$env:PYTHONPATH = 'tools/binrecon'
& $VENVPY compare_cirrus.py $env:BINRECON_REFERENCE $REBUILT
```

`failed_matched` must stay 0 after every rebuild. Glue DIFF is a defect (they matched). Campaign DIFF is expected until that campaign ends.

### Call-target list for `determineConfiguration`

After `strcmp`, the rebuilt body must not contain `call _strncmp`. Count `E8` calls in the rebuilt extent whose relocation target is `_strncmp`. Expected after Task 1: zero `_strncmp` calls, seven calls total matching the reference (15 `_objc_msgSend` / `_IOLog` mix as recorded: 7 calls in the reference including none to `_strncmp`). Practical check: `dumpbin` is not available; grep the rebuilt disassembly or scan for the `_strncmp` undefined symbol being relocated from that extent. If `read_macho` relocations in `[892, 892+size)` include a target `_strncmp`, Task 1 failed.

### Ledger command

```powershell
$env:BINRECON_REFERENCE = $REF
$env:BINRECON_REBUILT = (Resolve-Path $REBUILT).Path
$env:PYTHONPATH = 'tools/binrecon'
& $VENVPY -m binrecon ledger --profile $PROFILE --ledger $LEDGER `
  --address $ADDR --status assembly-matched `
  --reason "Rebuilt instruction stream matches the reference under 32-bit relocation masking." `
  --reviewer "Pat Raynor" `
  --source-path $LKS/CirrusLogicGD5434DisplayDriver.m `
  --source-line $LINE
```

Do not claim `assembly-matched` unless `compare_cirrus.py` printed `MATCH` for that name.

## File Structure

**Created:**
- `$DRV/Makefile.postamble`

**Modified:**
- `$LKS/CirrusLogicGD5434DisplayDriver.m` (`strcmp`, then campaign bodies)
- `$LKS/Makefile.postamble`
- `$RECON/divergences.md`, `$LEDGER`, `$MAP` as needed
- `src/drivers-i386/README`
- `docs/drivers/video-reconstruction.md`

**Unchanged:**
- `$LKS/ProgramDAC.m`, `$LKS/CirrusLogicGD5434DisplayDriver.h`
- `tools/binrecon/profiles/cirruslogic-gd5434.json`
- `vm/build-i386-video-recon.sh` (warning goes quiet on its own when the bundle exists)

---

### Task 1: `strcmp` for `"Bus Type"`

**Files:**
- Modify: `$LKS/CirrusLogicGD5434DisplayDriver.m` (the `strncmp` at the `"Bus Type"` test)
- Modify: `$MAP` if source lines after the edit moved
- Modify: `$RECON/divergences.md`

- [ ] **Step 1: Confirm the failing check**

Need a current `$REBUILT`. If `out/i386/` has no reloc, run the Guest rebuild block on HEAD before editing. Then:

```powershell
$env:PYTHONPATH = 'tools/binrecon'
& $VENVPY tools/binrecon/parity_check.py $REF $REBUILT
& $VENVPY compare_cirrus.py $REF $REBUILT
```

Expected: `parity_check.py` exit 0 (or only extras). `compare_cirrus.py`: `DIFF` on `determineConfiguration`, `MATCH` on `MATCHED_NAMES` and `GLUE`. Relocations in the determineConfiguration extent include `_strncmp` or the disassembly has `call _strncmp`.

- [ ] **Step 2: Replace `strncmp` with `strcmp`**

In `$LKS/CirrusLogicGD5434DisplayDriver.m` change only:

```
    if (strncmp([[[self deviceDescription] configTable]
		 valueForStringKey:"Bus Type"], "PCI", 4) == 0)
```

to:

```
    if (strcmp([[[self deviceDescription] configTable]
		valueForStringKey:"Bus Type"], "PCI") == 0)
```

Do not add `#include <string.h>`. Do not touch the `chipType` tests.

- [ ] **Step 3: Guest rebuild and compare**

Run the Guest rebuild block, then `parity_check.py` and `compare_cirrus.py`.

Expected:
- `make exit=0`
- `parity_check.py`: 0 missing strings, 0 missing symbols
- `failed_matched` is 0
- `determineConfiguration` still `DIFF` on extent (768 vs likely still ~712) but **no** `_strncmp` relocation in its extent
- The other three campaign functions still `DIFF` (unchanged)

If any `MATCHED_NAMES` or `GLUE` becomes `DIFF`, revert the edit and STOP.

- [ ] **Step 4: Reline the source map**

If line numbers in `$LKS/CirrusLogicGD5434DisplayDriver.m` changed, update every `source_line` in `$MAP` that points at that file. `load_source_map` must still accept the map:

```powershell
$env:PYTHONPATH = 'tools/binrecon'
$env:BINRECON_REFERENCE = $REF
& $VENVPY -c "from pathlib import Path; from binrecon.schema import load_json, load_source_map; a=load_json(Path('tools/binrecon/out/cirruslogic-gd5434/published/analysis-reference-ida.json')); load_source_map(Path(r'$MAP'), reference_analysis=a, repo_root=Path('.')); print('source map OK')"
```

If `analysis-reference-ida.json` is missing from this worktree, copy it from `D:/RhapsodiOS/tools/binrecon/out/cirruslogic-gd5434/published/` (gitignored analyzer output) or skip validation and keep line numbers consistent with `grep -n 'determineConfiguration'`.

- [ ] **Step 5: Record in divergences.md**

Under Build and parity, state that `strcmp` is in source, the call list no longer includes `_strncmp`, and the extent gap remains the `ja`/`jg` plus block placement. Do not mark `assembly-matched`.

- [ ] **Step 6: Commit**

```powershell
git add $LKS/CirrusLogicGD5434DisplayDriver.m $MAP $RECON/divergences.md
git commit -m "drvCirrusLogicGD5434: use strcmp for the PCI bus-type test"
```

---

### Task 2: Kernel Server `VERS_OFILE`

**Files:**
- Modify: `$LKS/Makefile.postamble`

- [ ] **Step 1: Confirm version symbols are absent**

```powershell
$env:PYTHONPATH = 'tools/binrecon'
& $VENVPY -c "from pathlib import Path; from binrecon.macho import read_macho; d=read_macho(Path(r'$REBUILT')); print([s['name'] for s in d['symbols'] if 'VERS' in s['name']])"
```

Expected: `[]`.

- [ ] **Step 2: Wire the Kernel Server postamble**

Replace the empty `$LKS/Makefile.postamble` with exactly:

```
OTHER_GENERATED_OFILES += $(VERS_OFILE)
```

Keep a trailing newline. Do not set `VERSIONING_SYSTEM`. Do not edit `Makefile` or `Makefile.preamble`.

- [ ] **Step 3: Guest rebuild**

Run the Guest rebuild block.

Expected: `make exit=0`. Rebuilt nlist contains `_CirrusLogicGD5434DisplayDriver_VERS_STRING` and `_CirrusLogicGD5434DisplayDriver_VERS_NUM`. `failed_matched` stays 0. If `$(NAME)_vers.c` was not generated, record the guest log in `divergences.md`; do not edit `driverTools`. A missing MH_BUNDLE is still OK here — that is Task 3.

- [ ] **Step 4: Commit**

```powershell
git add $LKS/Makefile.postamble $RECON/divergences.md
git commit -m "drvCirrusLogicGD5434: link VERS_OFILE into the kernel server"
```

---

### Task 3: Driver-project version bundle

**Files:**
- Create: `$DRV/Makefile.postamble`

- [ ] **Step 1: Confirm the bundle is still missing**

Guest log from Task 2 still has `WARNING: no CirrusLogicGD5434DisplayDriver version bundle produced`, or `$BUNDLE` does not exist on the host.

- [ ] **Step 2: Create the Driver-project postamble**

Create `$DRV/Makefile.postamble` with exactly:

```
OTHER_GENERATED_OFILES += $(VERS_OFILE)
```

`$DRV/Makefile` already has `-include Makefile.postamble`. Do not change `NAME`, `TOOLS`, or resource lists.

- [ ] **Step 3: Guest rebuild**

Run the Guest rebuild block, including pulling `CirrusLogicGD5434DisplayDriver` if tar listed it.

Expected:
- Log contains `staged version bundle CirrusLogicGD5434DisplayDriver`
- No `WARNING: no CirrusLogicGD5434DisplayDriver version bundle produced`
- `$BUNDLE` exists (any size near 16k is fine; do not compare bytes to 1998)
- `_reloc` still has the two `VERS_*` symbols
- `failed_matched` is 0

If the bundle is still missing, dump the Driver-project link line from the guest log into `divergences.md` and stop this task without editing `driverTools`. Existence remains unmet.

- [ ] **Step 4: Commit**

```powershell
git add $DRV/Makefile.postamble $RECON/divergences.md
git commit -m "drvCirrusLogicGD5434: emit the Driver-project version bundle"
```

---

### Task 4: `determineConfiguration` campaign

**Files:**
- Modify: `$LKS/CirrusLogicGD5434DisplayDriver.m` (`chipType` tests only)
- Modify: `$LEDGER`, `$RECON/divergences.md`, `$MAP` as needed

The `strcmp` from Task 1 stays. Campaign the list in spec §7.1, **one item per rebuild**. After each miss, revert the `chipType` edit (keep `strcmp`). Never apply unsigned ivar or `switch`.

Starting source (after Task 1):

```
    if (chipType <= 1) {
	modeTable = GD5434_modeTable;
	modeTableCount = GD5434_modeTableCount;
	defaultMode = GD5434_defaultMode;
    } else if (chipType <= 4) {
	modeTable = GD5446_modeTable;
	modeTableCount = GD5446_modeTableCount;
	defaultMode = GD5446_defaultMode;
    }
```

- [ ] **Step 1: Experiment 1 — `unsigned int kind = chipType`**

```
    {
	unsigned int kind = chipType;
	if (kind <= 1) {
	    modeTable = GD5434_modeTable;
	    modeTableCount = GD5434_modeTableCount;
	    defaultMode = GD5434_defaultMode;
	} else if (kind <= 4) {
	    modeTable = GD5446_modeTable;
	    modeTableCount = GD5446_modeTableCount;
	    defaultMode = GD5446_defaultMode;
	}
    }
```

Rebuild, `compare_cirrus.py`. If `determineConfiguration` is `MATCH` and `failed_matched` is 0, skip remaining experiments, go to Step 8. If `failed_matched` != 0, revert. If DIFF only on campaign, revert this experiment, record, continue.

- [ ] **Step 2: Experiment 2 — `(unsigned)chipType`**

```
    if ((unsigned)chipType <= 1) {
```

and the matching `else if ((unsigned)chipType <= 4)`. Same rebuild/revert rule.

- [ ] **Step 3: Experiment 3 — `1u` / `4u`**

```
    if (chipType <= 1u) {
```

`else if (chipType <= 4u)`. Same rule.

- [ ] **Step 4: Experiment 4 — cast into `unsigned int kind`**

```
    unsigned int kind = (unsigned int)chipType;
```

then `if (kind <= 1)` / `else if (kind <= 4)` without an extra inner block if it compiles. Same rule.

- [ ] **Step 5: Experiment 5 — `int kind = chipType`**

Signed local, one load. Same rule.

- [ ] **Step 6: Experiment 6 — polarity `chipType > 1`**

```
    if (chipType > 1) {
	modeTable = GD5446_modeTable;
	modeTableCount = GD5446_modeTableCount;
	defaultMode = GD5446_defaultMode;
    } else {
	modeTable = GD5434_modeTable;
	modeTableCount = GD5434_modeTableCount;
	defaultMode = GD5434_defaultMode;
    }
```

Same rule.

- [ ] **Step 7: Experiment 7 — two sequential `if`s**

```
    if (chipType <= 1) {
	modeTable = GD5434_modeTable;
	modeTableCount = GD5434_modeTableCount;
	defaultMode = GD5434_defaultMode;
    }
    if (chipType > 1 && chipType <= 4) {
	modeTable = GD5446_modeTable;
	modeTableCount = GD5446_modeTableCount;
	defaultMode = GD5446_defaultMode;
    }
```

Same rule.

- [ ] **Step 8: Ledger and divergences**

If a match landed, `binrecon ledger --address 892 --status assembly-matched` with the source line of `determineConfiguration`. If the list is exhausted, leave `signature-confirmed` or set `control-flow-confirmed` only if call targets now match (no `_strncmp`) and block count is 14 as in the reference; record each failed experiment.

```powershell
git add $LKS/CirrusLogicGD5434DisplayDriver.m $LEDGER $MAP $RECON/divergences.md
git commit -m "drvCirrusLogicGD5434: close or record determineConfiguration shape"
```

---

### Task 5: `setMode:` campaign

**Files:**
- Modify: `$LKS/CirrusLogicGD5434DisplayDriver.m` (`setMode:` body only)
- Modify: `$LEDGER`, `$RECON/divergences.md`, `$MAP` as needed

Do not reorder the 67 `in`/`out` operations. Campaign spec §7.2.

- [ ] **Step 1: Experiment 1 — walking pointers on all four loops**

Replace the four indexed loops with:

```
    {
	const unsigned char *p = mode->seq;
	for (i = 1; i <= 4; i++)
	    outw(0x3C4, (*p++ << 8) | i);
    }
    outw(0x3C4, 0x0300);
    outb(0x3C2, mode->misc);
    outb(0x3D4, 0x11);
    value = inb(0x3D5);
    outb(0x3D5, value & 0x7F);
    {
	const unsigned char *p = mode->crtc;
	for (i = 0; i <= 24; i++)
	    outw(0x3D4, (*p++ << 8) | i);
    }
    inb(0x3DA);
    {
	const unsigned char *p = mode->attr;
	for (i = 0; i <= 20; i++) {
	    outb(0x3C0, i);
	    outb(0x3C0, *p++);
	}
    }
    {
	const unsigned char *p = mode->gfx;
	for (i = 0; i <= 8; i++)
	    outw(0x3CE, (*p++ << 8) | i);
    }
```

Keep the SR01–SR04 / CR11 unlock / CR00–CR18 / AR / GR order exactly as today. Rebuild. Match → Step 6. Regression → revert and STOP. Miss → revert, continue.

- [ ] **Step 2: Experiment 2 — walking pointers with `while`**

Same pointers, `while (i <= N)` instead of `for`. Same rule.

- [ ] **Step 3: Experiment 3 — indexed `while`**

No walking pointer. `i = 0; while (i <= 24) { outw(..., mode->crtc[i] ...); i++; }` for each loop. Same rule.

- [ ] **Step 4: Experiment 4 — one pointer at function top**

Declare `const unsigned char *p;` next to `value` / `i`, assign before each loop. Walking `*p++`. Same rule.

- [ ] **Step 5: Experiment 5 — pointer declared immediately before each loop**

Same as experiment 1 if experiment 1 was reverted; if experiment 1 already *was* this shape, skip. Use this step for the variant with no extra inner `{ }` blocks, pointers as statements before each `for`. Same rule.

- [ ] **Step 6: Ledger and commit**

Match → `assembly-matched` at address 2276. Exhausted → stay `control-flow-confirmed`, list each miss.

```powershell
git add $LKS/CirrusLogicGD5434DisplayDriver.m $LEDGER $MAP $RECON/divergences.md
git commit -m "drvCirrusLogicGD5434: close or record setMode register-loop shape"
```

---

### Task 6: `setPendingDisplayMode:` campaign

**Files:**
- Modify: `$LKS/CirrusLogicGD5434DisplayDriver.m` (`setPendingDisplayMode:` only)
- Modify: `$LEDGER`, `$RECON/divergences.md`, `$MAP` as needed

Current test: `if (modeTable[mode].memorySize > installedVRAMBytes) return NO;`

- [ ] **Step 1: Experiment 1 — reversed compare**

```
    if (installedVRAMBytes < modeTable[mode].memorySize)
	return NO;
```

Rebuild. Match → Step 6. Else revert and continue.

- [ ] **Step 2: Experiment 2 — `needed` local**

```
    unsigned int needed = modeTable[mode].memorySize;
    if (needed > installedVRAMBytes)
	return NO;
```

Same rule.

- [ ] **Step 3: Experiment 3 — `needed` at top of function**

Declare `unsigned int needed;` with the other locals, assign before the test. Same rule.

- [ ] **Step 4: Experiment 4 — negated `<=`**

```
    if (!(modeTable[mode].memorySize <= installedVRAMBytes))
	return NO;
```

Same rule.

- [ ] **Step 5: Experiment 5 — `needed` plus reversed compare**

```
    unsigned int needed = modeTable[mode].memorySize;
    if (installedVRAMBytes < needed)
	return NO;
```

Same rule.

- [ ] **Step 6: Ledger and commit**

Match → `assembly-matched` at address 3388. Exhausted → stay `control-flow-confirmed`.

```powershell
git add $LKS/CirrusLogicGD5434DisplayDriver.m $LEDGER $MAP $RECON/divergences.md
git commit -m "drvCirrusLogicGD5434: close or record setPendingDisplayMode compare shape"
```

---

### Task 7: `setPCIConfiguration` campaign

**Files:**
- Modify: `$LKS/CirrusLogicGD5434DisplayDriver.m` (`setPCIConfiguration` only)
- Modify: `$LEDGER`, `$RECON/divergences.md`, `$MAP` as needed

Do not change call targets or log strings.

- [ ] **Step 1: Experiment 1 — `range[3]` before `configSpace`**

```
    IORange range[3];
    IOPCIConfigSpace configSpace;
    unsigned char deviceNumber, functionNumber, busNumber;
```

Keep the rest of the method. Rebuild. Match → Step 6. Else revert, continue.

- [ ] **Step 2: Experiment 2 — `rangeCount == 3` success path**

Replace the `if (rangeCount != 3) { IOLog; return NO; }` plus following success with:

```
	if (rangeCount == 3) {
	    for (i = 0; i < rangeCount; i++)
		range[i] = rangeList[i];
	    range[0].start = physicalAddress;
	    if ([deviceDescription setMemoryRangeList:range num:3] ==
		IO_R_SUCCESS)
		return YES;
	    IOLog("%s: Can't set memory range, using default.\n", [self name]);
	    for (i = 0; i < rangeCount; i++)
		range[i] = rangeList[i];
	    physicalAddress = range[0].start;
	    if ([deviceDescription setMemoryRangeList:range num:3] ==
		IO_R_SUCCESS)
		return YES;
	    IOLog("%s: Can't set to default range either!\n", [self name]);
	    return NO;
	}
	IOLog("%s: Incorrect number of address ranges: %d.\n",
	      [self name], rangeCount);
	return NO;
```

Keep the `isValidPCIAssignedBaseAddress:` guard around this. Same rebuild rule.

- [ ] **Step 3: Experiment 3 — `while` on both copy loops**

Keep experiment 1's declaration order reverted unless it matched. Convert both `for (i = 0; i < rangeCount; i++) range[i] = rangeList[i];` to `i = 0; while (i < rangeCount) { range[i] = rangeList[i]; i++; }`. Same rule.

- [ ] **Step 4: Experiment 4 — `while` on the first copy only**

Same rule.

- [ ] **Step 5: Experiment 5 — sink the range-count `IOLog` after the success returns**

Keep `if (rangeCount != 3) return NO;` without the `IOLog`, and after both success `return YES` paths and the "can't set default" `return NO`, add the `Incorrect number of address ranges` log only on the `!= 3` path — actually that would drop the log on the early path. Correct equivalent: goto-less trailing error:

```
	if (rangeCount == 3) {
	    /* existing success body including its IOLogs and returns */
	} else {
	    IOLog("%s: Incorrect number of address ranges: %d.\n",
		  [self name], rangeCount);
	    return NO;
	}
```

This is experiment 2 if experiment 2 already did it; skip if so. Same rule.

- [ ] **Step 6: Ledger and commit**

Match → `assembly-matched` at address 1692. Exhausted → stay `control-flow-confirmed`.

```powershell
git add $LKS/CirrusLogicGD5434DisplayDriver.m $LEDGER $MAP $RECON/divergences.md
git commit -m "drvCirrusLogicGD5434: close or record setPCIConfiguration frame shape"
```

---

### Task 8: Status docs and final ledger SHA

**Files:**
- Modify: `$RECON/divergences.md`
- Modify: `$LEDGER` (`rebuilt_sha256` if the tool records it)
- Modify: `src/drivers-i386/README`
- Modify: `docs/drivers/video-reconstruction.md`

- [ ] **Step 1: Final rebuild on the committed tree**

Guest rebuild once more with no dirty source. `compare_cirrus.py` + `parity_check.py`. Record SHA-256 of `$REBUILT` in `divergences.md`.

- [ ] **Step 2: Update README**

`src/drivers-i386/README` Cirrus line becomes a single factual sentence: how many of 21 are byte-identical, version bundle present or still missing, any unreachable function names, not hardware-tested.

- [ ] **Step 3: Update `docs/drivers/video-reconstruction.md`**

Replace the Cirrus "two things remain open" paragraph with the Task 1–7 outcomes. Do not claim ThinkPad or VGA progress.

- [ ] **Step 4: Commit**

```powershell
git add src/drivers-i386/README docs/drivers/video-reconstruction.md $RECON/divergences.md $LEDGER
git commit -m "docs: record drvCirrusLogicGD5434 finish-pass status"
```

---

## Spec coverage

| Spec section | Task |
| --- | --- |
| §1.2 `strcmp` | 1 |
| §1.2 Kernel Server VERS | 2 |
| §1.2 Driver bundle VERS | 3 |
| §1.2 campaigns | 4–7 |
| §1.2 records | 1, 4–8 |
| §1.3 out of scope | Global Constraints |
| §4.1 `strcmp` snippet | 1 |
| §4.2 postambles | 2–3 |
| §5 data flow | Guest rebuild block |
| §6 error handling | every campaign step |
| §7.1 list | Task 4 steps 1–7 |
| §7.2 list | Task 5 |
| §7.3 list | Task 6 |
| §7.4 list | Task 7 |
| §8 testing | compare_cirrus.py + parity_check |
| §9 success | Task 8 |

## Placeholder scan

No TBD, no "similar to Task N", no unimplemented error-handling handwaves. Experiment bodies are inlined in each step.
