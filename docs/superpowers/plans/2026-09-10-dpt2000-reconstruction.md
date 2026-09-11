# drvDPT2000 Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct `drvDPT2000` against Apple's `DPTSCSIDriver_reloc` so the 55 reference functions exist as `EATAController` plus `EATASCSIBus`, then guest-compile a `_reloc`.

**Architecture:** Report pass first (IDA partition, source-map, ledger, table diff). Then layered rewrite: types from the reloc, `EATAController`, `EATASCSIBus`, residue removal, bundle extras. The Linux-`eata.c` stub is replaced, not adapted. No HIM/sequencer layer unless the reloc has standalone C symbols.

**Tech Stack:** Python 3.12 in `.venv-binrecon`, `tools/binrecon`, IDA Professional 9.2, Ghidra 12.1 on Java 21, angr 9.3.0, Rhapsody guest `gnumake` / `pb_makefiles`.

**Spec:** [2026-09-10-dpt2000-reconstruction-design.md](../specs/2026-09-10-dpt2000-reconstruction-design.md)

## Global Constraints

```text
VENVPY=D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe
REF=C:/Users/raynorpat/Downloads/test/Drivers/i386/DPTSCSIDriver.config/DPTSCSIDriver_reloc
REFSHA=5AE7A361F645EC693444A8AFC829DB477F34DE2576AFC0EB2A0D4128D3BD68A6
REFSIZE=53952
LKS=src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/DPT2000.lksproj
DRVPROJ=src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj
RECON=src/drivers-i386/scsi/drvDPT2000/reconstruction
PROFILE=tools/binrecon/profiles/dpt2000.json
REFBUNDLE=C:/Users/raynorpat/Downloads/test/Drivers/i386/DPTSCSIDriver.config
```

Work in a dedicated worktree, not the main checkout. `.worktrees/` is gitignored.

```powershell
git worktree add .worktrees/dpt2000-recon HEAD
```

Set `REPO` to that worktree and run every command from there.

- **Never commit** `$REF`, `$REFBUNDLE`, `tools/binrecon/out/`, or `out/i386/` artifacts.
- **`BINRECON_REFERENCE` must be exported** in every shell that runs `binrecon validate`, `analyze`, `source-map`, or `ledger`.
- **Python is `$VENVPY`.** Not `python`, not `py`. `PYTHONPATH=tools/binrecon`.
- **IDA is the partition of record.** Ghidra is a second opinion on bodies. angr `CFGFast` is not evidence.
- **The `_reloc` beats Linux `eata.c` and EATA manuals** on offset, width, polarity, control flow, ivars, and symbol names.
- **Do not import Linux `eata.c` control flow.** Do not keep `@interface DPTSCSIDriver`.
- **`binrecon analyze` on a reference-only profile exits 1** with `normalized-functions=FAIL`. That is expected. The real gate is `run-summary.json` → `"complete": true` and a published `analysis-reference-ida.json`.
- **Reline the source map after every source edit** that adds or removes lines (Task 12 procedure).
- **Commits:** `drivers-i386: ` or `binrecon: ` or `docs: ` or `vm: ` prefix, one to two lines, no metadata.
- **Reviewer name** for ledger `intentional-mismatch`: `Pat Raynor`.
- **Guest sync:** `powershell -File vm\sync-src.ps1 -Path drivers-i386/scsi/drvDPT2000`. Do not `sync-src.ps1 -All`.
- Do not touch the other SCSI stubs. Do not copy `IntrInspector.nib`.
- **`DRIVERNAME` stays `DPT2000`.** Table `"Server Name"` stays `DPTSCSIDriver`. Installed config name `DPT2000.config` vs reference `DPTSCSIDriver.config` is a recorded bundle divergence, not a rename.

### Forbidden Linux residue

After Task 10 these must have no definition site and no call site in `$LKS` live code:

```
@interface DPTSCSIDriver
eataInitController
eataResetBus
eataAllocateResources
eataFreeResources
allocCp
freeCp:
runPendingCommands
processCmdComplete
struct dpt_config
Based on Linux eata.c
```

`DPTSCSIDriver` as `"Server Name"` in tables is required and is not residue. Scan `$LKS` only.

### Required classes after Task 10

```
@interface EATAController
@interface EATASCSIBus
```

Exact superclasses, selectors, and any extra C symbols come from the report pass (Tasks 3–5). Do not invent a HIM layer unless Task 3’s IDA function list contains non-ObjC `__text` symbols that need a `.c` home.

## File Structure

**Created:**
- `tools/binrecon/profiles/dpt2000.json`
- `tools/binrecon/tests/test_dpt2000_profile.py`
- `tools/binrecon/tests/test_dpt2000_linux_residue.py`
- `$RECON/{source-map.json,ledger.json,divergences.md}`
- `$LKS/EATAController.m`, `EATAController.h`, `EATAControllerPrivate.h`, `EATAControllerTypes.h`
- `$LKS/EATAControllerThread.m` (only if the reloc has `(IOThread)`)
- `$LKS/EATASCSIBus.m`, `EATASCSIBus.h` (+ Private if the reloc has a category)
- `$DRVPROJ/English.lproj/…` (from the reference bundle, minus `IntrInspector.nib`)
- `vm/build-i386-scsi.sh` (create if absent; reuse if 6X60 already added it)

**Modified:**
- `$LKS/Makefile`, `$LKS/PB.project`
- `src/drivers-i386/scsi/drvDPT2000/Makefile.preamble`
- `$DRVPROJ/{Default,DPT_EISA,DPT_PCI,DPT_OnBoard}.table`
- `$DRVPROJ/DriverInfo`, `$LKS/Load_Commands.sect` only if Task 5 recorded a real divergence
- `docs/drivers/scsi-reconstruction.md`, `src/drivers-i386/README`

**Deleted:**
- `$LKS/DPTSCSIDriver.m`, `DPTSCSIDriver.h`, `DPTSCSIDriverPrivate.h`, `DPTSCSIDriverTypes.h`, `DPTSCSIDriverRoutines.m`, `DPTSCSIDriverThread.m` once the new names are in place

---

### Task 1: Worktree and reference identity

**Files:**
- None committed

- [ ] **Step 1: Create the worktree**

```powershell
cd D:\RhapsodiOS
git worktree add .worktrees/dpt2000-recon HEAD
```

Expected: new checkout at `D:\RhapsodiOS\.worktrees\dpt2000-recon`. All later steps use that as `REPO`. If the controller already created this worktree, `cd` into it and skip `git worktree add`.

- [ ] **Step 2: Confirm the reference file**

```powershell
cd $REPO
$env:BINRECON_REFERENCE = 'C:\Users\raynorpat\Downloads\test\Drivers\i386\DPTSCSIDriver.config\DPTSCSIDriver_reloc'
$env:PYTHONPATH = 'tools/binrecon'
Get-FileHash -Algorithm SHA256 $env:BINRECON_REFERENCE
(Get-Item $env:BINRECON_REFERENCE).Length
```

Expected: SHA-256 `5AE7A361F645EC693444A8AFC829DB477F34DE2576AFC0EB2A0D4128D3BD68A6`. Size `53952`. Stop if either differs — the spec and this plan are then wrong.

- [ ] **Step 3: Confirm the venv**

```powershell
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -c "import binrecon, sys; print(sys.executable)"
```

If that fails, set `PYTHONPATH=tools/binrecon` and retry. Expected: a path ending in `.venv-binrecon\Scripts\python.exe`.

- [ ] **Step 4: Commit nothing.** Identity check only.

---

### Task 2: Add the reference-only profile

**Files:**
- Create: `tools/binrecon/profiles/dpt2000.json`
- Test: `tools/binrecon/tests/test_dpt2000_profile.py`

- [ ] **Step 1: Write the failing test**

```python
"""drvDPT2000 binrecon profile is reference-only i386."""
import json
from pathlib import Path

import pytest

from binrecon.profile import load_profile

PROFILE = Path("tools/binrecon/profiles/dpt2000.json")
REF = Path(
    r"C:\Users\raynorpat\Downloads\test\Drivers\i386\DPTSCSIDriver.config\DPTSCSIDriver_reloc"
)
REFSHA = "5AE7A361F645EC693444A8AFC829DB477F34DE2576AFC0EB2A0D4128D3BD68A6"


def test_dpt2000_profile_document_has_no_rebuilt_key():
    document = json.loads(PROFILE.read_text(encoding="utf-8"))
    assert "rebuilt" not in document
    assert document["schema_version"] == "profile-v1"
    assert document["architecture"] == "i386"
    assert document["endianness"] == "little"
    assert document["output_dir"] == "../out/dpt2000"
    assert document["reference"]["path"] == "${BINRECON_REFERENCE}"
    assert document["comparison"]["acceptance"] == "normalized-functions"


def test_dpt2000_profile_loads_reference_only(monkeypatch):
    if not REF.is_file():
        pytest.skip("DPTSCSIDriver_reloc not on this host")
    monkeypatch.setenv("BINRECON_REFERENCE", str(REF))
    profile = load_profile(PROFILE, {"BINRECON_REFERENCE": str(REF)})
    assert profile.rebuilt is None
    assert profile.architecture == "i386"
    assert profile.reference_identity.sha256 == REFSHA
    assert profile.reference_identity.size == 53952
    assert profile.output_dir.name == "dpt2000"
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PYTHONPATH = 'tools/binrecon'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m pytest tools/binrecon/tests/test_dpt2000_profile.py -q
```

Expected: FAIL with `FileNotFoundError` / `No such file` for `dpt2000.json`.

- [ ] **Step 3: Write the profile**

Copy `tools/binrecon/profiles/adaptec6x60.json`. Change only:

```json
{
  "schema_version": "profile-v1",
  "name": "drvDPT2000 reconstruction",
  "architecture": "i386",
  "endianness": "little",
  "reference": {
    "path": "${BINRECON_REFERENCE}"
  },
  "analyzers": {
    "ida": {
      "enabled": true,
      "executable": "C:/Program Files/IDA Professional 9.2/idat.exe",
      "timeout_seconds": 900,
      "version": "9.2"
    },
    "ghidra": {
      "enabled": true,
      "executable": "D:/ghidra/support/analyzeHeadless.bat",
      "timeout_seconds": 900,
      "version": "12.1"
    },
    "angr": {
      "enabled": true,
      "executable": ".venv-binrecon/Scripts/python.exe",
      "timeout_seconds": 900,
      "version": "9.3.0"
    }
  },
  "comparison": {
    "acceptance": "normalized-functions",
    "ignore_metadata": [],
    "entry_points": []
  },
  "output_dir": "../out/dpt2000"
}
```

Do not add a `rebuilt` key.

- [ ] **Step 4: Run tests and validate**

```powershell
$env:PYTHONPATH = 'tools/binrecon'
$env:BINRECON_REFERENCE = 'C:\Users\raynorpat\Downloads\test\Drivers\i386\DPTSCSIDriver.config\DPTSCSIDriver_reloc'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m pytest tools/binrecon/tests/test_dpt2000_profile.py -q
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m binrecon validate --profile tools/binrecon/profiles/dpt2000.json
```

Expected: pytest PASS. Validate stdout contains size `53952` and sha256 `5AE7A361F645EC693444A8AFC829DB477F34DE2576AFC0EB2A0D4128D3BD68A6`. No `rebuilt` line. Exit 0.

- [ ] **Step 5: Commit**

```powershell
git add tools/binrecon/profiles/dpt2000.json tools/binrecon/tests/test_dpt2000_profile.py
git commit -m "binrecon: add reference-only drvDPT2000 profile"
```

---

### Task 3: Analyze the reference

**Files:**
- Generated (gitignored): `tools/binrecon/out/dpt2000/published/analysis-reference-ida.json`
- Generated: `analysis-reference-ghidra.json`, `analysis-reference-angr.json`, `consensus-reference.json`, `run-summary.json`

- [ ] **Step 1: Run analyzers**

```powershell
$env:BINRECON_REFERENCE = 'C:\Users\raynorpat\Downloads\test\Drivers\i386\DPTSCSIDriver.config\DPTSCSIDriver_reloc'
$env:PYTHONPATH = 'tools/binrecon'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m binrecon analyze `
  --profile tools/binrecon/profiles/dpt2000.json `
  --output tools/binrecon/out/dpt2000/run-summary.json
```

Expected: process exit 1, last line `normalized-functions=FAIL`. That is success for a reference-only profile.

If Ghidra dies with `Ghidra relocation operand metadata is ambiguous`, set `analyzers.ghidra.enabled` to `false` in the profile, commit that change alone (`binrecon: disable Ghidra for dpt2000 after normalize error`), and re-run. Do not invent another workaround.

- [ ] **Step 2: Confirm the summary**

```powershell
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -c @"
import json
d = json.load(open('tools/binrecon/out/dpt2000/run-summary.json'))
assert d['complete'] is True, d
assert d.get('consensus', {}).get('reference') or d.get('published'), d
print('complete', d['complete'])
print('sha', d.get('reference_sha256'))
"@
Get-ChildItem tools/binrecon/out/dpt2000/published
```

Expected: `complete True`, SHA matching `$REFSHA`, and at least `analysis-reference-ida.json` plus `consensus-reference.json`. A leftover `binrecon-run-*` directory with no `published/` means the run did not finish — do not reuse it.

- [ ] **Step 3: Count IDA `__text` functions and list ObjC classes**

```powershell
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -c @"
import json
from pathlib import Path
p = Path('tools/binrecon/out/dpt2000/published/analysis-reference-ida.json')
d = json.loads(p.read_text(encoding='utf-8'))
fns = d.get('functions') or d.get('functions_by_address') or []
if isinstance(fns, dict):
    fns = list(fns.values())
print('functions', len(fns))
for f in sorted(fns, key=lambda x: x.get('address', 0) or 0):
    names = f.get('names') or f.get('aliases') or [f.get('name')]
    print(f.get('address'), f.get('size'), names)
"@
```

Expected: a count near 55. Record the exact list in `divergences.md` in Task 5. Partition names into `EATAController`, `EATASCSIBus`, Kernel Server glue, and any standalone C. If the JSON shape differs, print `d.keys()` and walk the actual function list — do not invent a parser that drops functions.

- [ ] **Step 4: Commit nothing.** Analyzer output is gitignored.

---

### Task 4: Source map

**Files:**
- Create: `src/drivers-i386/scsi/drvDPT2000/reconstruction/source-map.json`

- [ ] **Step 1: Generate the map from IDA**

```powershell
$env:BINRECON_REFERENCE = 'C:\Users\raynorpat\Downloads\test\Drivers\i386\DPTSCSIDriver.config\DPTSCSIDriver_reloc'
$env:PYTHONPATH = 'tools/binrecon'
New-Item -ItemType Directory -Force -Path src/drivers-i386/scsi/drvDPT2000/reconstruction | Out-Null
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m binrecon source-map `
  --reference-analysis tools/binrecon/out/dpt2000/published/analysis-reference-ida.json `
  --binary $env:BINRECON_REFERENCE `
  --source-dir src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/DPT2000.lksproj `
  --repo-root . `
  --objc-methods `
  --output src/drivers-i386/scsi/drvDPT2000/reconstruction/source-map.json
```

Expected: the command writes the JSON and re-validates it. `EATASCSIBus` names land in `unmapped`. `EATAController` selectors may land in `mapped` only if a `DPTSCSIDriver` method was accepted as a class-name alias — if the mapper does not alias classes, they are `unmapped` too. Do not point `EATASCSIBus` symbols at `DPTSCSIDriver` methods.

- [ ] **Step 2: Hand-place Kernel Server glue in `unmapped`**

Open the map. Move (or confirm) the build-generated methods into `unmapped` with no `source_path`. 1542B’s names were:

```
+[Adaptec1542BKernelServerInstance kernelServerInstance]
+[Adaptec1542BVersion driverKitVersionForAdaptec1542B]
```

Expect the same pattern with `DPTSCSIDriver`, `EATAController`, and/or `EATASCSIBus`. Two classes may emit more than two glue methods. Use the names the symbol table actually has.

Sort each bucket by `(address, reference_names)`. `load_source_map` rejects any other order.

Every other reference `__text` function stays in exactly one bucket. Do not map a reloc name onto a Linux invented selector (`allocCp`, `eataInitController`, …) just to turn the row green.

- [ ] **Step 3: Validate**

Write `check_map.py` in the worktree (do not commit it):

```python
from pathlib import Path
from binrecon.schema import load_json, load_source_map

analysis = load_json(Path("tools/binrecon/out/dpt2000/published/analysis-reference-ida.json"))
load_source_map(
    Path("src/drivers-i386/scsi/drvDPT2000/reconstruction/source-map.json"),
    reference_analysis=analysis,
    repo_root=Path.cwd(),
)
print("source map OK")
```

```powershell
$env:PYTHONPATH = 'tools/binrecon'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe check_map.py
```

Expected: `source map OK`. Fix the map on any `SemanticValidationError`. Confirm `reference_sha256` is `$REFSHA`.

- [ ] **Step 4: Commit the map**

```powershell
git add src/drivers-i386/scsi/drvDPT2000/reconstruction/source-map.json
git commit -m "drivers-i386: source-map drvDPT2000 against DPTSCSIDriver_reloc"
```

---

### Task 5: Ledger, table diff, divergences

**Files:**
- Create: `$RECON/ledger.json`, `$RECON/divergences.md`

- [ ] **Step 1: Seed the ledger from the map**

```powershell
$env:PYTHONPATH = 'tools/binrecon'
$env:BINRECON_REFERENCE = 'C:\Users\raynorpat\Downloads\test\Drivers\i386\DPTSCSIDriver.config\DPTSCSIDriver_reloc'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe tools/binrecon/seed_ledger.py `
  src/drivers-i386/scsi/drvDPT2000/reconstruction/source-map.json `
  $env:BINRECON_REFERENCE `
  src/drivers-i386/scsi/drvDPT2000/reconstruction/ledger.json
```

Expected: prints `N entries` where N equals the source-map function count.

`seed_ledger.py` stamps PPC-style `analyzer_agreement` (`IDA` only). Rewrite every entry to:

```json
"analyzer_agreement": {
  "status": "agreed",
  "analyzers": ["IDA", "Ghidra"],
  "reasons": ["IDA is the partition of record; Ghidra is a second opinion on bodies"]
}
```

If Ghidra was disabled in Task 3, use `["IDA"]` only and say so in `divergences.md`.

- [ ] **Step 2: Mark glue `intentional-mismatch`**

For each Kernel Server glue method, with `$ADDR` from the map:

```powershell
$env:BINRECON_REFERENCE = 'C:\Users\raynorpat\Downloads\test\Drivers\i386\DPTSCSIDriver.config\DPTSCSIDriver_reloc'
$env:PYTHONPATH = 'tools/binrecon'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m binrecon ledger `
  --profile tools/binrecon/profiles/dpt2000.json `
  --ledger src/drivers-i386/scsi/drvDPT2000/reconstruction/ledger.json `
  --address $ADDR --status intentional-mismatch `
  --reason "Kernel Server project type emits this method; not hand-written" `
  --reviewer "Pat Raynor"
```

Everyone else stays `unexamined`.

```powershell
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m binrecon ledger `
  --profile tools/binrecon/profiles/dpt2000.json `
  --ledger src/drivers-i386/scsi/drvDPT2000/reconstruction/ledger.json
```

Expected: `entries=<N>` and a status mix of `unexamined` plus the glue `intentional-mismatch` count.

- [ ] **Step 3: Diff the bundle extras**

Compare these host files to `$REFBUNDLE`. Ignore `"Driver Version"`. Do not copy `IntrInspector.nib`.

| Ours | Reference |
| --- | --- |
| `$DRVPROJ/Default.table` | `DPTSCSIDriver.config/Default.table` |
| `$DRVPROJ/DPT_EISA.table` | `DPTSCSIDriver.config/DPT_EISA.table` |
| `$DRVPROJ/DPT_PCI.table` | `DPTSCSIDriver.config/DPT_PCI.table` |
| `$DRVPROJ/DPT_OnBoard.table` | `DPTSCSIDriver.config/DPT_OnBoard.table` |
| `$DRVPROJ/DriverInfo` | bundle `DriverInfo` if present; else record absence |
| `$LKS/Load_Commands.sect` | `Loaded Server,Load Commands` in the `_reloc` |
| `$DRVPROJ/English.lproj/Localizable.strings` | `English.lproj/Localizable.strings` |
| (missing) `DPT_EISA.strings`, `DPT_PCI.strings`, `DPT_OnBoard.strings` | those three files |
| (missing) Help RTFDs + TOC | `English.lproj/Help/…` |

Known starting diffs (confirm, do not assume they are the complete set):

- Ours `Default.table` `"Family" = "SDSI"`; reference `"SCSI"`. Reference also has `"Location"` and `"IRQ Levels" = "15"`.
- Ours `DPT_PCI.table` `"Share IRQ Levels" = "NO"` and default `"IRQ Levels" = "15"`; reference `"YES"` and no default IRQ line.
- Ours `Localizable.strings` is `"Driver Name" = "DPT2000"`; reference `"DPTSCSIDriver" = "DPT 2021"`.
- Ours has no help RTFDs. Reference has `DPT_ISA.rtfd`, `DPT_EISA.rtfd`, `DPT_PCI.rtfd`, `DPT_On_Board.rtfd`, `TableOfContents.rtf`.

- [ ] **Step 4: Write `divergences.md`**

Follow `src/drivers-i386/scsi/drvAdaptec1542B/reconstruction/divergences.md`:

1. Header: binary `DPTSCSIDriver_reloc`, SHA `$REFSHA`, analyzers actually used.
2. Baseline-build note: not yet compiled; `rebuilt_sha256` is null.
3. Bucket-count table from the source map.
4. Statement that the architecture is a Linux-shaped stub under `DPTSCSIDriver` with no `EATASCSIBus`. List forbidden residue that exists in our tree and the reloc class/method names that do not.
5. Superclasses of `EATAController` and `EATASCSIBus`. Who implements `executeRequest:buffer:client:`. Ivar / CP / SP layouts from IDA and `__OBJC,__instance_vars`. Record field offsets here. Do not guess from `DPTSCSIDriverTypes.h`.
6. Completion policy: whether the IRQ handler wakes an IOThread or finishes the command buf. Quote the call targets.
7. Channel count: one `EATASCSIBus` vs several. Quote the evidence.
8. Standalone C symbols, if any, and the file they will live in.
9. Numbered findings for every mapped method whose body still calls Linux helpers.
10. Table / help findings from Step 3.
11. Analyzer disagreement section (or “none”).
12. Unmapped reason classes: glue vs missing `EATASCSIBus` vs Linux-name mismatch vs anything else.

- [ ] **Step 5: Commit**

```powershell
git add src/drivers-i386/scsi/drvDPT2000/reconstruction/ledger.json `
        src/drivers-i386/scsi/drvDPT2000/reconstruction/divergences.md
git commit -m "drivers-i386: ledger and divergences for drvDPT2000"
```

Do not start the rewrite until this commit exists.

---

### Task 6: Guest build script and baseline compile

**Files:**
- Create or reuse: `vm/build-i386-scsi.sh`

- [ ] **Step 1: Ensure the guest script exists**

If `vm/build-i386-scsi.sh` already exists (6X60 work), do not replace it. Confirm it takes one `drv*` argument. If the usage line lists only `drvAdaptec6X60`, leave the script as-is — `drvDPT2000` is a valid `$1`.

If it does not exist, write:

```sh
#!/bin/sh
# Build one i386 SCSI driver on the Rhapsody guest and stage its _reloc.
# Usage: sh vm/build-i386-scsi.sh drvDPT2000

set -e

DRV="$1"
if [ -z "$DRV" ]; then
    echo "usage: $0 drvAdaptec6X60|drvDPT2000" >&2
    exit 2
fi

ROOT="${SRCROOT:-/build/source}"
SRC="$ROOT/src/drivers-i386/scsi/$DRV"
STAGE="$ROOT/out/i386/$DRV"
DST="/tmp/${DRV}-dst"

if [ ! -d "$SRC" ]; then
    echo "build-i386-scsi: missing $SRC" >&2
    exit 1
fi

# Strip CR so gnumake does not treat it as part of a target name.
find "$SRC" -type f \( -name Makefile -o -name Makefile.preamble -o -name Makefile.postamble -o -name '*.make' \) -print | while read f
do
    tr -d '\r' < "$f" > "$f.nocr" && mv "$f.nocr" "$f"
done

LKS=`ls -d "$SRC"/*.drvproj/*.lksproj 2>/dev/null | head -1`
if [ -z "$LKS" ]; then
    echo "build-i386-scsi: no .lksproj under $SRC" >&2
    exit 1
fi

cd "$LKS"
gnumake clean || true
gnumake

RELOC=`ls -1 *_reloc 2>/dev/null | head -1`
if [ -z "$RELOC" ]; then
    echo "FAILED: no _reloc in $LKS" >&2
    exit 1
fi

rm -rf "$DST"
mkdir -p "$DST" "$STAGE"
if gnumake DSTROOT="$DST" install; then
    find "$DST" -name '*_reloc' -exec cp {} "$STAGE/" \;
else
    cp "$RELOC" "$STAGE/"
fi

echo "=== scsi-recon done fail=0 built: $DRV reloc=$RELOC ==="
ls -l "$STAGE"
```

- [ ] **Step 2: Sync only this driver and the script**

```powershell
powershell -NoProfile -File vm\sync-src.ps1 -Path drivers-i386/scsi/drvDPT2000
```

Copy `vm/build-i386-scsi.sh` with the same OpenSSH path used by `sync-src.ps1` (see `vm/README.md`). Do not upload all of `src/`.

- [ ] **Step 3: Run the baseline on the guest**

```sh
tr -d '\r' < /build/source/vm/build-i386-scsi.sh > /tmp/bscsi.sh
sh /tmp/bscsi.sh drvDPT2000
```

Expected on success: `=== scsi-recon done fail=0 built: drvDPT2000` and a `_reloc` under `/build/source/out/i386/drvDPT2000/`. Record the filename (`DPT2000_reloc` vs `DPTSCSIDriver_reloc`) in `divergences.md`.

Today’s tree uses undefined macros (`EATA_CP_ADDR`, `AUX_IRQ`, `STAT_IRQ`). If the baseline fails, fix the project files in their own commit (`drivers-i386: build drvDPT2000`) before any two-class rewrite. Do not “fix” by implementing Apple’s classes early.

- [ ] **Step 4: Commit the script** (and any baseline compile fix)

```powershell
git add vm/build-i386-scsi.sh
git commit -m "vm: add i386 SCSI driver guest build script"
```

Skip the `git add` of the script if it already existed and was unchanged. If the guest is down, commit the script (when new) and leave the baseline note in `divergences.md`. Do not block Tasks 7–11 on the guest.

---

### Task 7: Replace types and write the residue test

**Files:**
- Create: `$LKS/EATAControllerTypes.h`, `$LKS/EATAControllerPrivate.h`, `$LKS/EATAController.h`
- Modify: none of the live `DPTSCSIDriver.*` yet except as needed so the project still lists old files until Task 8
- Test: `tools/binrecon/tests/test_dpt2000_linux_residue.py` (written here, expected FAIL until Task 10)

- [ ] **Step 1: Write the residue test (RED)**

```python
"""Linux-eata stub residue must not remain in drvDPT2000 Kernel Server sources."""
from pathlib import Path

import pytest

LKS = Path(
    "src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/DPT2000.lksproj"
)

FORBIDDEN = (
    "@interface DPTSCSIDriver",
    "eataInitController",
    "eataResetBus",
    "eataAllocateResources",
    "eataFreeResources",
    "allocCp",
    "freeCp:",
    "runPendingCommands",
    "processCmdComplete",
    "struct dpt_config",
    "Based on Linux eata.c",
)

REQUIRED_FILES = (
    "EATAController.m",
    "EATAController.h",
    "EATASCSIBus.m",
    "EATASCSIBus.h",
)

GONE_FILES = (
    "DPTSCSIDriver.m",
    "DPTSCSIDriver.h",
    "DPTSCSIDriverRoutines.m",
    "DPTSCSIDriverThread.m",
    "DPTSCSIDriverPrivate.h",
    "DPTSCSIDriverTypes.h",
)

TEXT_SUFFIXES = {".h", ".m", ".c", ".s"}


def _lks_text_files():
    assert LKS.is_dir(), LKS
    for path in sorted(LKS.rglob("*")):
        if path.is_file() and path.suffix in TEXT_SUFFIXES:
            yield path


def test_lks_has_no_linux_eata_residue():
    hits = []
    for path in _lks_text_files():
        text = path.read_text(encoding="latin-1")
        for token in FORBIDDEN:
            if token in text:
                hits.append(f"{path.name}: {token}")
    assert hits == [], hits


def test_both_reloc_classes_exist_and_stub_files_are_gone():
    for name in REQUIRED_FILES:
        assert (LKS / name).is_file(), name
    for name in GONE_FILES:
        assert not (LKS / name).exists(), name
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PYTHONPATH = 'tools/binrecon'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m pytest `
  tools/binrecon/tests/test_dpt2000_linux_residue.py -q
```

Expected: FAIL. `test_lks_has_no_linux_eata_residue` hits `DPTSCSIDriver.m` / types. `test_both_reloc_classes_exist_and_stub_files_are_gone` misses `EATAController.m` / `EATASCSIBus.m`. Do not xfail. Do not delete `DPTSCSIDriver.*` in this task — that is Tasks 8–10.

- [ ] **Step 3: Dump IDA layouts, then write types headers**

Use the Task 8 dump script against the IDA JSON. Record ivar offsets, CP size, SP size, and register immediates in `divergences.md` if Task 5 did not already.

Write `$LKS/EATAControllerTypes.h` with those offsets. Bit *names* may come from EATA docs; every offset, width, and polarity comes from the reloc. Do not copy `struct dpt_config` or the Linux software-extension `struct eata_cp`.

Write `$LKS/EATAController.h` as `@interface EATAController` with the ivar list IDA shows. Superclass is whatever Task 5 recorded (do not assume `IOSCSIController` if IDA says otherwise).

Write `$LKS/EATAControllerPrivate.h` with the private selectors and command-buf struct from IDA. Do not declare `allocCp` / `runPendingCommands` unless those exact names are in the reloc.

Leave `DPTSCSIDriver.*` in the project so the baseline still has something to compile. The new headers can sit unused until Task 8.

- [ ] **Step 4: Residue test still RED**

Re-run the pytest from Step 2. Expected: still FAIL (`DPTSCSIDriver` files remain). That is correct.

- [ ] **Step 5: Commit**

```powershell
git add src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/DPT2000.lksproj/EATAControllerTypes.h `
        src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/DPT2000.lksproj/EATAController.h `
        src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/DPT2000.lksproj/EATAControllerPrivate.h `
        tools/binrecon/tests/test_dpt2000_linux_residue.py `
        src/drivers-i386/scsi/drvDPT2000/reconstruction/divergences.md
git commit -m "drivers-i386: add EATAController types from DPTSCSIDriver_reloc"
```

---

### Task 8: Write EATAController from IDA

**Files:**
- Create: `$LKS/EATAController.m`, `$LKS/EATAControllerThread.m` (if Task 5 says `(IOThread)` exists)
- Modify: `$LKS/Makefile`, `$LKS/PB.project`, `src/drivers-i386/scsi/drvDPT2000/Makefile.preamble`
- Keep `DPTSCSIDriver.*` in the tree until Task 10 deletes them (both class names must not be live together — switch `CLASSES` to `EATAController*.m` in this task and stop compiling `DPTSCSIDriver.m`)

- [ ] **Step 1: Dump helper (do not commit)**

`dump_ida.py` in the worktree:

```python
import json, sys
from pathlib import Path

name = sys.argv[1]
doc = json.loads(Path("tools/binrecon/out/dpt2000/published/analysis-reference-ida.json").read_text(encoding="utf-8"))
fns = doc.get("functions") or []
if isinstance(fns, dict):
    fns = list(fns.values())
for fn in fns:
    names = fn.get("names") or fn.get("aliases") or [fn.get("name")]
    if name in names or f"_{name}" in names:
        print("address", fn.get("address"), "size", fn.get("size"))
        for key in ("decompiled", "pseudocode", "instructions", "blocks"):
            if fn.get(key):
                print("===", key, "===")
                print(fn[key] if key != "instructions" else fn[key][:40])
        break
else:
    sys.exit(f"not found: {name}")
```

Run it for every `EATAController` method in the source-map (class method, instance method, `(PrivateMethods)`, `(IOThread)`). Expected: address, size, and either decompilation or instruction/block lists. This is the source of every prototype and body.

- [ ] **Step 2: Write `EATAController.m` (and Thread if needed)**

For each method in address order:

1. Dump IDA.
2. Write Objective-C whose control-flow shape, call targets, port immediates, and struct offsets match.
3. Account for every branch. Do not leave a stub that `IOLog`s and returns.
4. Probe failure (bad signature, config read fails, resources fail) returns `NO` / `nil` as IDA shows.
5. `interruptOccurred` reads the status packet the reloc reads, not `REG_LOW`..`MSB` unless IDA does that.
6. Do not call `eataInitController`, `allocCp`, or `runPendingCommands`.

If Task 5 found standalone C symbols owned by the controller, put them in `EATAControllerRoutines.c` (or the filename IDA’s locality suggests) and add `CFILES` in the Makefile. Do not invent `HIM6X60.c`.

- [ ] **Step 3: Point the Kernel Server project at EATAController**

`$LKS/Makefile`:

```
CLASSES = EATAController.m EATAControllerThread.m
HFILES = EATAController.h EATAControllerPrivate.h EATAControllerTypes.h
```

Drop `EATAControllerThread.m` from `CLASSES` if Task 5 says there is no `(IOThread)` file. Do not list `EATASCSIBus.m` until Task 9. Do not list `DPTSCSIDriver*.m`.

`$LKS/PB.project` `CLASSES` matches. `src/drivers-i386/scsi/drvDPT2000/Makefile.preamble` `MFILES` / `HFILES` match.

Leave the old `DPTSCSIDriver.*` files on disk until Task 10 so the residue test stays RED for `GONE_FILES` / `@interface DPTSCSIDriver` until deletion. They must not remain in `CLASSES`.

- [ ] **Step 4: Confirm controller symbols have definition sites**

```powershell
$env:PYTHONPATH = 'tools/binrecon'
$env:BINRECON_REFERENCE = 'C:\Users\raynorpat\Downloads\test\Drivers\i386\DPTSCSIDriver.config\DPTSCSIDriver_reloc'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe tools/binrecon/symbol_name_check.py `
  $env:BINRECON_REFERENCE `
  src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/DPT2000.lksproj
```

Expected: `EATAController` methods no longer listed as missing. `EATASCSIBus` methods still missing. Glue still missing. Extra source names may include leftover `DPTSCSIDriver` files on disk — Task 10 removes them.

- [ ] **Step 5: Commit**

```powershell
git add src/drivers-i386/scsi/drvDPT2000
git commit -m "drivers-i386: implement EATAController from DPTSCSIDriver_reloc"
```

Do not `git add` leftover `DPTSCSIDriver.*` as if they were new.

---

### Task 9: Write EATASCSIBus from IDA

**Files:**
- Create: `$LKS/EATASCSIBus.m`, `$LKS/EATASCSIBus.h` (+ `EATASCSIBusPrivate.h` if Task 5 recorded a category)
- Modify: `$LKS/Makefile`, `$LKS/PB.project`, `src/drivers-i386/scsi/drvDPT2000/Makefile.preamble`

- [ ] **Step 1: Residue test still RED**

```powershell
$env:PYTHONPATH = 'tools/binrecon'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m pytest `
  tools/binrecon/tests/test_dpt2000_linux_residue.py -q
```

Expected: FAIL (`DPTSCSIDriver.*` still on disk; `EATASCSIBus.m` not yet present).

- [ ] **Step 2: Dump and implement every EATASCSIBus method**

Same dump helper as Task 8. Work the source-map `EATASCSIBus` names in address order. Superclass and relationship to `EATAController` are Task 5 facts.

Empty `@interface` shells do not count. Each method body must match IDA the same way Task 8 required. If `executeRequest:buffer:client:` lives here, it forwards to the controller the way the reloc does — not via `DPTSCSIDriverCommandBuf` unless that struct’s layout is in the reloc.

- [ ] **Step 3: Add the class to the project**

`$LKS/Makefile` `CLASSES` includes `EATASCSIBus.m`. `HFILES` includes `EATASCSIBus.h` (and Private if present). `PB.project` and top-level `Makefile.preamble` match.

- [ ] **Step 4: Confirm bus symbols have definition sites**

```powershell
$env:PYTHONPATH = 'tools/binrecon'
$env:BINRECON_REFERENCE = 'C:\Users\raynorpat\Downloads\test\Drivers\i386\DPTSCSIDriver.config\DPTSCSIDriver_reloc'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe tools/binrecon/symbol_name_check.py `
  $env:BINRECON_REFERENCE `
  src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/DPT2000.lksproj
```

Expected: `EATASCSIBus` methods no longer missing. Glue still missing.

- [ ] **Step 5: Commit**

```powershell
git add src/drivers-i386/scsi/drvDPT2000
git commit -m "drivers-i386: implement EATASCSIBus from DPTSCSIDriver_reloc"
```

---

### Task 10: Delete DPTSCSIDriver residue

**Files:**
- Delete: `$LKS/DPTSCSIDriver.m`, `DPTSCSIDriver.h`, `DPTSCSIDriverPrivate.h`, `DPTSCSIDriverTypes.h`, `DPTSCSIDriverRoutines.m`, `DPTSCSIDriverThread.m`
- Modify: `$LKS/Makefile`, `$LKS/PB.project`, `Makefile.preamble` if any leftover names remain

- [ ] **Step 1: Re-run residue test — still RED until deletion**

```powershell
$env:PYTHONPATH = 'tools/binrecon'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m pytest `
  tools/binrecon/tests/test_dpt2000_linux_residue.py -q
```

Expected: FAIL on `GONE_FILES` / `@interface DPTSCSIDriver` until Step 2.

- [ ] **Step 2: `git rm` the stub files**

```powershell
git rm src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/DPT2000.lksproj/DPTSCSIDriver.m `
       src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/DPT2000.lksproj/DPTSCSIDriver.h `
       src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/DPT2000.lksproj/DPTSCSIDriverPrivate.h `
       src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/DPT2000.lksproj/DPTSCSIDriverTypes.h `
       src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/DPT2000.lksproj/DPTSCSIDriverRoutines.m `
       src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/DPT2000.lksproj/DPTSCSIDriverThread.m
```

Grep `$LKS` for every Forbidden Linux residue token. Delete comments that still contain `Based on Linux eata.c`. Do not weaken the test. Do not remove `"Server Name" = "DPTSCSIDriver"` from tables.

- [ ] **Step 3: Residue test GREEN**

```powershell
$env:PYTHONPATH = 'tools/binrecon'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m pytest `
  tools/binrecon/tests/test_dpt2000_linux_residue.py tools/binrecon/tests/test_dpt2000_profile.py -q
```

Expected: PASS.

- [ ] **Step 4: Commit**

```powershell
git add src/drivers-i386/scsi/drvDPT2000 tools/binrecon/tests/test_dpt2000_linux_residue.py
git commit -m "drivers-i386: remove DPTSCSIDriver Linux-eata stub"
```

---

### Task 11: Config tables and English.lproj

**Files:**
- Modify: `$DRVPROJ/Default.table`, `DPT_EISA.table`, `DPT_PCI.table`, `DPT_OnBoard.table`
- Modify: `$DRVPROJ/English.lproj/Localizable.strings`
- Create: `$DRVPROJ/English.lproj/DPT_EISA.strings`, `DPT_PCI.strings`, `DPT_OnBoard.strings`
- Create: `$DRVPROJ/English.lproj/Help/DPT_ISA.rtfd/…`, `DPT_EISA.rtfd/…`, `DPT_PCI.rtfd/…`, `DPT_On_Board.rtfd/…`, `TableOfContents.rtf`
- Modify: `DriverInfo` and `$LKS/Load_Commands.sect` only if Task 5 recorded a real divergence

- [ ] **Step 1: Align the four tables with the reference, except `"Driver Version"`**

Copy every key from `$REFBUNDLE` except `"Driver Version"`. Keep our `"Driver Version"` line as sibling reconstructed drivers do.

Must match the reference after this step:

- `Default.table`: `"Family" = "SCSI"` (not `SDSI`); `"Location"`; `"IRQ Levels" = "15"`; `"Class Names" = "EATAController EATASCSIBus"`; `"Server Name" = "DPTSCSIDriver"`.
- `DPT_PCI.table`: `"Share IRQ Levels" = "YES"`; no extra default IRQ line the reference lacks.
- All four tables: `"Class Names" = "EATAController EATASCSIBus"`.

- [ ] **Step 2: Copy `English.lproj` from the reference bundle, then drop the inspector**

```powershell
$src = 'C:\Users\raynorpat\Downloads\test\Drivers\i386\DPTSCSIDriver.config\English.lproj'
$dst = 'src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/English.lproj'
Copy-Item -Recurse -Force $src $dst
Remove-Item -Recurse -Force "$dst\IntrInspector.nib" -ErrorAction SilentlyContinue
```

Confirm committed files are strings / RTF / RTFD `TXT.rtf` (and any image resources the help already ships). No `.nib`.

- [ ] **Step 3: Commit**

```powershell
git add src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/Default.table `
        src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/DPT_EISA.table `
        src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/DPT_PCI.table `
        src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/DPT_OnBoard.table `
        src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/English.lproj
git commit -m "drivers-i386: align drvDPT2000 tables and help with DPTSCSIDriver.config"
```

---

### Task 12: Remap, ledger statuses, final compile, status docs

**Files:**
- Modify: `$RECON/source-map.json`, `$RECON/ledger.json`, `$RECON/divergences.md`
- Modify: `docs/drivers/scsi-reconstruction.md`, `src/drivers-i386/README`

- [ ] **Step 1: Remap to scratch, then merge lines by address**

```powershell
$env:BINRECON_REFERENCE = 'C:\Users\raynorpat\Downloads\test\Drivers\i386\DPTSCSIDriver.config\DPTSCSIDriver_reloc'
$env:PYTHONPATH = 'tools/binrecon'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m binrecon source-map `
  --reference-analysis tools/binrecon/out/dpt2000/published/analysis-reference-ida.json `
  --binary $env:BINRECON_REFERENCE `
  --source-dir src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/DPT2000.lksproj `
  --repo-root . `
  --objc-methods `
  --output $env:TEMP/dpt2000-fresh.json
```

`EATAController` and `EATASCSIBus` names must now be `mapped` to the new `.m` / `.c` files. Glue stays `unmapped`. If a reloc name is still `unmapped`, the definition site is wrong (leading underscore, `static`, class name mismatch) — fix the source, do not edit the map by hand to lie.

Copy fresh `source_path` / `source_line` into the committed map by `address`. Run `check_map.py` from Task 4. Expected: `source map OK`. Mapped count = 55 minus the glue set recorded in Task 5.

- [ ] **Step 2: Advance the ledger**

For each mapped function, after reading IDA against the new source:

- `assembly-matched` if every instruction was compared.
- `control-flow-confirmed` only for the largest function, and only if `divergences.md` says which parts were not traced operand-by-operand.

```powershell
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m binrecon ledger `
  --profile tools/binrecon/profiles/dpt2000.json `
  --ledger src/drivers-i386/scsi/drvDPT2000/reconstruction/ledger.json `
  --address $ADDR --status assembly-matched `
  --source-path src/drivers-i386/scsi/drvDPT2000/DPT2000.drvproj/DPT2000.lksproj/EATAController.m `
  --source-line $LINE
```

Do not claim `assembly-matched` without the read. Leave `unexamined` rather than guess.

- [ ] **Step 3: Final guest compile**

Host sync first (`sync-src.ps1 -Path drivers-i386/scsi/drvDPT2000`).

```sh
tr -d '\r' < /build/source/vm/build-i386-scsi.sh > /tmp/bscsi.sh
sh /tmp/bscsi.sh drvDPT2000
```

Expected: exit 0, `_reloc` staged under `out/i386/drvDPT2000/`. Warnings go in `divergences.md`; they do not gate. Do not run `binrecon compare` on the rebuilt file. If the guest is down, record that in `divergences.md` and still finish the docs; do not claim compiled in README.

- [ ] **Step 4: Residue and profile tests still green**

```powershell
$env:PYTHONPATH = 'tools/binrecon'
$env:BINRECON_REFERENCE = 'C:\Users\raynorpat\Downloads\test\Drivers\i386\DPTSCSIDriver.config\DPTSCSIDriver_reloc'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m pytest `
  tools/binrecon/tests/test_dpt2000_linux_residue.py `
  tools/binrecon/tests/test_dpt2000_profile.py -q
```

Expected: PASS.

- [ ] **Step 5: Update status docs**

In `docs/drivers/scsi-reconstruction.md`, change the drvDPT2000 row from `stub; missing the EATASCSIBus class` to reconstructed against the reference; guest `_reloc` produced (omit “compiled” if Step 3 could not run); not hardware-tested. Class-name cell: ours `EATAController` (+ `EATASCSIBus`), reference the same. Resolved count = mapped count from Step 1.

In `src/drivers-i386/README`:

```
 * drvDPT2000 - reconstructed against the reference binary, compiled; not hardware-tested
```

Use “not yet compiled” instead of “compiled” if the guest did not produce a `_reloc`.

- [ ] **Step 6: Commit**

```powershell
git add src/drivers-i386/scsi/drvDPT2000/reconstruction `
        docs/drivers/scsi-reconstruction.md `
        src/drivers-i386/README
git commit -m "drivers-i386: finish drvDPT2000 reconstruction ledger and status"
```

---

## Spec coverage

| Spec section | Task |
| --- | --- |
| §1.1 reference identity / profile | 1–2 |
| §1.2 tables, help, Load_Commands | 5, 11 |
| §1.3 no inspector, no QEMU, no Linux template, DPT only | Global Constraints |
| §2 two classes, Linux stub, invented symbols, table drift | 5, 7–11 |
| §3 two-class architecture | 8–9 |
| §4 components / DPTSCSIDriver retirement | 7–10 |
| §5 data flow / completion from `_reloc` | 5 (record), 8–9 (implement) |
| §6 reconstruction/ artifacts | 4–5 |
| §7.1 report pass | 2–5 |
| §7.2 fix pass layers | 6–12 |
| §8 error handling | 3 (Ghidra), 7–10 (no shells), 6/12 (compile) |
| §9 done bar | 12 |
| §10 sequencing | Task order |
| `vm/build-i386-scsi.sh` | 6 |

## Self-review notes

- No TBD/TODO. Method lists and prototypes are taken from IDA in Tasks 5/8/9, not invented here.
- `seed_ledger.py` agreement rewrite is explicit so i386 ledgers match 1542B, not the PPC default.
- Residue pytest is RED from Task 7 through Task 10 on purpose; do not skip it or mark xfail.
- `DRIVERNAME` stays `DPT2000`; `"Server Name"` stays `DPTSCSIDriver`; inspector nib is never copied.
- If `vm/build-i386-scsi.sh` already exists from 6X60, Task 6 reuses it.
