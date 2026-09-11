# drvSym53C8xx Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct `drvSym53C8xx` against Apple's `SYM53c8_reloc` so the 158 reference functions exist as a DriverKit `SYM53c8` class plus a CAM/SIM C engine and SCRIPTS bytes from this `_reloc`, then guest-compile a `_reloc`.

**Architecture:** Report pass first (IDA partition, source-map, ledger, table diff). Then layered rewrite: class rename and types, SIM API, CAM helpers, SCRIPTS blob, DriverKit glue, bundle extras. BusLogic CCB code is deleted, not adapted. Linux `ncr53c8xx` is a reading aid only.

**Tech Stack:** Python 3.12 in `.venv-binrecon`, `tools/binrecon`, IDA Professional 9.2, Ghidra 12.1 on Java 21, angr 9.3.0, Rhapsody guest `gnumake` / `pb_makefiles`.

**Spec:** [2026-09-10-sym53c8xx-reconstruction-design.md](../specs/2026-09-10-sym53c8xx-reconstruction-design.md)

## Global Constraints

```text
VENVPY=D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe
REF=C:/Users/raynorpat/Downloads/test/Drivers/i386/SYM53c8.config/SYM53c8_reloc
REFSHA=E0AC193DF652271D1B4249440140842B788F0BAAC13F93008B7E029A095CF6D3
REFSIZE=120756
LKS=src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/SYM53c8.lksproj
DRVPROJ=src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj
RECON=src/drivers-i386/scsi/drvSym53C8xx/reconstruction
PROFILE=tools/binrecon/profiles/sym53c8xx.json
```

Work in a dedicated worktree, not the main checkout. `.worktrees/` is gitignored.

```powershell
git worktree add .worktrees/sym53c8xx-recon HEAD
```

Set `REPO` to that worktree and run every command from there.

- **Never commit** `$REF`, `tools/binrecon/out/`, or `out/i386/` artifacts.
- **`BINRECON_REFERENCE` must be exported** in every shell that runs `binrecon validate`, `analyze`, `source-map`, or `ledger`.
- **Python is `$VENVPY`.** Not `python`, not `py`. `PYTHONPATH=tools/binrecon`.
- **IDA is the partition of record.** Ghidra is a second opinion on bodies. angr `CFGFast` is not evidence.
- **The `_reloc` beats datasheet, Linux, and ppc Sym8xx** on offset, width, polarity, SCRIPT bytes, and control flow.
- **Do not import Linux `ncr53c8xx` / `sym53c8xx` control flow, type names, or SCRIPT bytes.** Linux may explain CAM/SIM ideas only.
- **Do not copy ppc `drvSymbios8xx` or `Sym8xxScript.ss`.**
- **`binrecon analyze` on a reference-only profile exits 1** with `normalized-functions=FAIL`. That is expected. The real gate is `run-summary.json` → `"complete": true` and a published `analysis-reference-ida.json`.
- **Reline the source map after every source edit** that adds or removes lines (Task 11 procedure).
- **Commits:** `drivers-i386: ` or `binrecon: ` or `docs: ` or `vm: ` prefix, one to two lines, no metadata.
- **Reviewer name** for ledger `intentional-mismatch`: `Pat Raynor`.
- **Guest sync:** `powershell -File vm\sync-src.ps1 -Path drivers-i386/scsi/drvSym53C8xx`. Do not `sync-src.ps1 -All`.
- Do not touch the other SCSI stubs.

### Expected CAM / SIM C names (starting list)

These must become definition sites. The report pass extends the list to every C symbol in the `_reloc`. Do not invent names that IDA does not show.

```
CCBInSIMQueue AddToDeviceList DeletePathFromDeviceTable
FCalcSync FSetWide FWideInit
FResumeXFer FSendMsg
AutosenseSetup BeginScan
```

SIM public API (Controller/Thread call only these — exact prototypes from IDA in Task 7): init, ISR, queue CCB, abort, bus reset. If IDA uses the names above rather than `SYM53c8SIM*` wrappers, export those names; do not invent a second C API.

### Forbidden BusLogic residue

After Task 9 these must have no definition site and no call site in live code:

```
sym_reset_chip sym_init_chip
allocCcb: freeCcb: ccbFromCmd:ccb: runPendingCommands
@interface SYM53c8Controller
```

Filenames may stay `SYM53c8Controller.*`. The ObjC class must be `SYM53c8`.

`sym_read_reg` / `sym_write_reg` / `sym_put_dsp` stay only if the reference actually has those names; otherwise match IDA.

## File Structure

**Created:**
- `$PROFILE`
- `$RECON/{source-map.json,ledger.json,divergences.md}`
- `$LKS/SYM53c8SIM.c`, `$LKS/SYM53c8SIM.h`, `$LKS/SYM53c8CAM.c`, `$LKS/SYM53c8Scripts.c`
- `$DRVPROJ/English.lproj/Help/…` (from the reference bundle; replace `DriverHelp/`)
- `vm/build-i386-scsi.sh` if it does not already exist
- `tools/binrecon/tests/test_sym53c8xx_buslogic_residue.py`

**Modified:**
- `$LKS/SYM53c8Types.h`, `SYM53c8Inline.h`, `SYM53c8ControllerPrivate.h`
- `$LKS/SYM53c8Controller.m`, `SYM53c8Controller.h`, `SYM53c8Thread.m`, `SYM53c8Thread.h`
- `$LKS/Makefile`, `$LKS/PB.project`, `src/drivers-i386/scsi/drvSym53C8xx/Makefile.preamble`
- `$DRVPROJ/Makefile` (`LOCAL_RESOURCES`: `Help` not `DriverHelp`)
- `$DRVPROJ/Default.table`
- `docs/drivers/scsi-reconstruction.md`, `src/drivers-i386/README`

**Deleted:**
- `$LKS/SYM53c8Routines.m` once every remaining C symbol has a SIM/CAM/Scripts home
- `$DRVPROJ/English.lproj/DriverHelp/` after `Help/` is in place

---

### Task 1: Worktree, profile, and reference identity

**Files:**
- Create: `tools/binrecon/profiles/sym53c8xx.json`

- [ ] **Step 1: Create the worktree**

```powershell
cd D:\RhapsodiOS
git worktree add .worktrees/sym53c8xx-recon HEAD
```

Expected: new checkout at `D:\RhapsodiOS\.worktrees\sym53c8xx-recon`. All later steps use that as `REPO`.

- [ ] **Step 2: Write the reference-only profile**

Copy `tools/binrecon/profiles/adaptec6x60.json` and change only `name`, `output_dir`, and leave `reference.path` as `${BINRECON_REFERENCE}`. Do **not** add a `rebuilt` key.

```json
{
  "schema_version": "profile-v1",
  "name": "drvSym53C8xx reconstruction",
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
  "output_dir": "../out/sym53c8xx"
}
```

- [ ] **Step 3: Confirm the reference file**

```powershell
cd $REPO
$env:BINRECON_REFERENCE = 'C:\Users\raynorpat\Downloads\test\Drivers\i386\SYM53c8.config\SYM53c8_reloc'
$env:PYTHONPATH = 'tools/binrecon'
Get-Item $env:BINRECON_REFERENCE | Select-Object Length
Get-FileHash -Algorithm SHA256 $env:BINRECON_REFERENCE
```

Expected: Length `120756`, SHA-256 `E0AC193DF652271D1B4249440140842B788F0BAAC13F93008B7E029A095CF6D3`. Stop if either differs — the spec and this plan are then wrong.

- [ ] **Step 4: Validate the profile**

```powershell
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m binrecon validate --profile tools/binrecon/profiles/sym53c8xx.json
```

Expected stdout contains:

```
reference C:\Users\raynorpat\Downloads\test\Drivers\i386\SYM53c8.config\SYM53c8_reloc size=120756 sha256=E0AC193DF652271D1B4249440140842B788F0BAAC13F93008B7E029A095CF6D3
```

No `rebuilt` line. Exit 0.

- [ ] **Step 5: Commit the profile**

```powershell
git add tools/binrecon/profiles/sym53c8xx.json
git commit -m "binrecon: add reference-only profile for drvSym53C8xx"
```

---

### Task 2: Analyze the reference

**Files:**
- Generated (gitignored): `tools/binrecon/out/sym53c8xx/published/analysis-reference-ida.json`
- Generated: `analysis-reference-ghidra.json`, `analysis-reference-angr.json`, `consensus-reference.json`, `run-summary.json`

- [ ] **Step 1: Run analyzers**

```powershell
$env:BINRECON_REFERENCE = 'C:\Users\raynorpat\Downloads\test\Drivers\i386\SYM53c8.config\SYM53c8_reloc'
$env:PYTHONPATH = 'tools/binrecon'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m binrecon analyze `
  --profile tools/binrecon/profiles/sym53c8xx.json `
  --output tools/binrecon/out/sym53c8xx/run-summary.json
```

Expected: process exit 1, last line `normalized-functions=FAIL`. That is success for a reference-only profile.

If Ghidra dies with `Ghidra relocation operand metadata is ambiguous`, set `analyzers.ghidra.enabled` to `false` in the profile, commit that change alone (`binrecon: disable Ghidra for sym53c8xx after normalize error`), and re-run. Do not invent another workaround.

- [ ] **Step 2: Confirm the summary**

```powershell
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -c @"
import json
d = json.load(open('tools/binrecon/out/sym53c8xx/run-summary.json'))
assert d['complete'] is True, d
assert d.get('consensus', {}).get('reference') or d.get('published'), d
print('complete', d['complete'])
print('sha', d.get('reference_sha256'))
"@
Get-ChildItem tools/binrecon/out/sym53c8xx/published
```

Expected: `complete True`, SHA matching `$REFSHA`, and at least `analysis-reference-ida.json` plus `consensus-reference.json`. A leftover `binrecon-run-*` directory with no `published/` means the run did not finish — do not reuse it.

- [ ] **Step 3: Count IDA `__text` functions**

```powershell
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -c @"
import json
from pathlib import Path
p = Path('tools/binrecon/out/sym53c8xx/published/analysis-reference-ida.json')
d = json.loads(p.read_text(encoding='utf-8'))
fns = d.get('functions') or d.get('functions_by_address') or []
if isinstance(fns, dict):
    fns = list(fns.values())
print('functions', len(fns))
for f in sorted(fns, key=lambda x: x.get('address', 0)):
    names = f.get('names') or f.get('aliases') or [f.get('name')]
    print(f.get('address'), f.get('size'), names)
"@
```

Expected: a count near 158. Record the exact list in `divergences.md` in Task 4. If the JSON shape differs, print `d.keys()` and walk the actual function list — do not invent a parser that drops functions.

- [ ] **Step 4: Commit nothing.** Analyzer output is gitignored.

---

### Task 3: Source map

**Files:**
- Create: `src/drivers-i386/scsi/drvSym53C8xx/reconstruction/source-map.json`

- [ ] **Step 1: Generate the map from IDA**

```powershell
$env:BINRECON_REFERENCE = 'C:\Users\raynorpat\Downloads\test\Drivers\i386\SYM53c8.config\SYM53c8_reloc'
$env:PYTHONPATH = 'tools/binrecon'
New-Item -ItemType Directory -Force -Path src/drivers-i386/scsi/drvSym53C8xx/reconstruction | Out-Null
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m binrecon source-map `
  --reference-analysis tools/binrecon/out/sym53c8xx/published/analysis-reference-ida.json `
  --binary $env:BINRECON_REFERENCE `
  --source-dir src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/SYM53c8.lksproj `
  --repo-root . `
  --objc-methods `
  --output src/drivers-i386/scsi/drvSym53C8xx/reconstruction/source-map.json
```

Expected: most CAM/SIM names land in `unmapped` because the class is still `SYM53c8Controller`. DriverKit selectors that exist under that class may land in `unmapped` too until Task 6 renames the class — that is correct for this snapshot. Do not point CAM names at BusLogic helpers.

- [ ] **Step 2: Hand-place Kernel Server glue in `unmapped`**

Open the map. Move (or confirm) the two build-generated methods into `unmapped` with no `source_path`. 1542B's names were:

```
+[Adaptec1542BKernelServerInstance kernelServerInstance]
+[Adaptec1542BVersion driverKitVersionForAdaptec1542B]
```

Expect the same pattern with `SYM53c8`. Use the names the symbol table actually has.

Sort each bucket by `(address, reference_names)`. `load_source_map` rejects any other order.

Every other reference `__text` function stays in exactly one bucket.

- [ ] **Step 3: Validate**

Write `check_map.py` in the worktree (do not commit it):

```python
from pathlib import Path
from binrecon.schema import load_json, load_source_map

analysis = load_json(Path("tools/binrecon/out/sym53c8xx/published/analysis-reference-ida.json"))
load_source_map(
    Path("src/drivers-i386/scsi/drvSym53C8xx/reconstruction/source-map.json"),
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
git add src/drivers-i386/scsi/drvSym53C8xx/reconstruction/source-map.json
git commit -m "drivers-i386: source-map drvSym53C8xx against SYM53c8_reloc"
```

---

### Task 4: Ledger, table diff, divergences

**Files:**
- Create: `$RECON/ledger.json`, `$RECON/divergences.md`

- [ ] **Step 1: Seed the ledger from the map**

```powershell
$env:PYTHONPATH = 'tools/binrecon'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe tools/binrecon/seed_ledger.py `
  src/drivers-i386/scsi/drvSym53C8xx/reconstruction/source-map.json `
  $env:BINRECON_REFERENCE `
  src/drivers-i386/scsi/drvSym53C8xx/reconstruction/ledger.json
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

If Ghidra was disabled in Task 2, use `["IDA"]` only and say so in `divergences.md`.

- [ ] **Step 2: Mark glue `intentional-mismatch`**

For each of the two Kernel Server methods, with `$ADDR` from the map:

```powershell
$env:BINRECON_REFERENCE = 'C:\Users\raynorpat\Downloads\test\Drivers\i386\SYM53c8.config\SYM53c8_reloc'
$env:PYTHONPATH = 'tools/binrecon'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m binrecon ledger `
  --profile tools/binrecon/profiles/sym53c8xx.json `
  --ledger src/drivers-i386/scsi/drvSym53C8xx/reconstruction/ledger.json `
  --address $ADDR --status intentional-mismatch `
  --reason "Kernel Server project type emits this method; not hand-written" `
  --reviewer "Pat Raynor"
```

Everyone else stays `unexamined`.

```powershell
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m binrecon ledger `
  --profile tools/binrecon/profiles/sym53c8xx.json `
  --ledger src/drivers-i386/scsi/drvSym53C8xx/reconstruction/ledger.json
```

Expected: `entries=<N>` and a status mix of `unexamined` plus two `intentional-mismatch`.

- [ ] **Step 3: Diff the bundle extras**

Compare these host files to the reference bundle. Ignore `"Driver Version"`.

| Ours | Reference |
| --- | --- |
| `$DRVPROJ/Default.table` | `SYM53c8.config/Default.table` |
| `$DRVPROJ/DriverInfo` | (bundle `DriverInfo` if present; else record absence) |
| `$LKS/Load_Commands.sect` | `Loaded Server,Load Commands` in the `_reloc` |
| `$DRVPROJ/English.lproj/Localizable.strings` | `SYM53c8.config/English.lproj/Localizable.strings` |
| `$DRVPROJ/English.lproj/DriverHelp/…` | `SYM53c8.config/English.lproj/Help/…` |

Known starting diffs (confirm, do not assume they are the complete set):

- Ours `Default.table` lacks `"Version" = "5.00";`. Other keys already match, including Auto Detect IDs `0x00011000 0x00021000 0x00031000 0x00041000`.
- Help directory is `DriverHelp/` here vs `Help/` in the reference.
- `Localizable.strings` already matches.
- Inspector nib and the `SYM53c8` DYLDLINK beside the `_reloc` are out of scope.

- [ ] **Step 4: Write `divergences.md`**

Follow `src/drivers-i386/scsi/drvAdaptec1542B/reconstruction/divergences.md`:

1. Header: binary `SYM53c8_reloc`, SHA `$REFSHA`, size 120756, analyzers actually used.
2. Baseline-build note: not yet compiled; `rebuilt_sha256` is null.
3. Bucket-count table from the source map.
4. Statement that the architecture is wrong: BusLogic CCB vs CAM/SIM + SCRIPTS. List the forbidden symbols that exist in our tree and the CAM/SIM names that do not.
5. Ivar / CAM CCB / device-table / SIM-state layouts read from IDA and `__OBJC,__instance_vars`. Record field offsets here. Do not guess from `SYM53c8Types.h`.
6. I/O vs MMIO: which BAR and accessors the `_reloc` uses.
7. SCRIPTS location: Mach-O section, file offset, virtual address, length in bytes. Quote enough immediates that Task 8 can dump the blob without guessing.
8. Completion policy: whether the SIM ISR wakes the IOThread or finishes the command buf. Quote the call targets.
9. Numbered findings for every mapped DriverKit method that still calls BusLogic helpers, and the class-name mismatch (`SYM53c8Controller` vs `SYM53c8`).
10. Table / help findings from Step 3.
11. Analyzer disagreement section (or “none”).
12. Unmapped reason classes: glue vs absent CAM/SIM vs class-name miss vs anything else.

- [ ] **Step 5: Commit**

```powershell
git add src/drivers-i386/scsi/drvSym53C8xx/reconstruction/ledger.json `
        src/drivers-i386/scsi/drvSym53C8xx/reconstruction/divergences.md
git commit -m "drivers-i386: ledger and divergences for drvSym53C8xx"
```

Do not start the rewrite until this commit exists.

---

### Task 5: Guest build script and baseline compile

**Files:**
- Create: `vm/build-i386-scsi.sh` (skip create if the file already exists on this branch and accepts `drvSym53C8xx` as `$1`)

- [ ] **Step 1: Write or reuse the guest script**

If `vm/build-i386-scsi.sh` already exists and takes a driver directory name, do not rewrite it. Otherwise write:

```sh
#!/bin/sh
# Build one i386 SCSI driver on the Rhapsody guest and stage its _reloc.
# Usage: sh vm/build-i386-scsi.sh drvSym53C8xx

set -e

DRV="$1"
if [ -z "$DRV" ]; then
    echo "usage: $0 drvAdaptec6X60|drvSym53C8xx" >&2
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
powershell -NoProfile -File vm\sync-src.ps1 -Path drivers-i386/scsi/drvSym53C8xx
```

Copy `vm/build-i386-scsi.sh` with the same OpenSSH path used by `sync-src.ps1` (see `vm/README.md`). Do not upload all of `src/`.

- [ ] **Step 3: Run the baseline on the guest**

```sh
tr -d '\r' < /build/source/vm/build-i386-scsi.sh > /tmp/bscsi.sh
sh /tmp/bscsi.sh drvSym53C8xx
```

Expected on success: `=== scsi-recon done fail=0 built: drvSym53C8xx` and a `_reloc` under `/build/source/out/i386/drvSym53C8xx/`. Record the filename in `divergences.md`. Ours will be unstripped and not byte-identical to 120756 bytes.

If the baseline fails, fix the project files in their own commit (`drivers-i386: build drvSym53C8xx`) before any CAM/SIM edit.

- [ ] **Step 4: Commit the script** (and any baseline compile fix)

```powershell
git add vm/build-i386-scsi.sh
git commit -m "vm: add i386 SCSI driver guest build script"
```

If the script already existed, skip this commit. If the guest is down, commit the script (when new) and leave the baseline note in `divergences.md`. Do not block Tasks 6–10 on the guest.

---

### Task 6: Rename the class and replace BusLogic types

**Files:**
- Modify: `$LKS/SYM53c8Types.h`, `$LKS/SYM53c8Inline.h`, `$LKS/SYM53c8ControllerPrivate.h`, `$LKS/SYM53c8Controller.h`, `$LKS/SYM53c8Thread.h`
- Test: `tools/binrecon/tests/test_sym53c8xx_buslogic_residue.py` (written here, expected FAIL until Task 9)

- [ ] **Step 1: Write the residue test (RED)**

```python
"""BusLogic CCB residue must not remain in drvSym53C8xx sources."""
from pathlib import Path

import pytest

LKS = Path("src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/SYM53c8.lksproj")

FORBIDDEN = (
    "sym_reset_chip",
    "sym_init_chip",
    "runPendingCommands",
    "allocCcb:",
    "@interface SYM53c8Controller",
    "@implementation SYM53c8Controller",
)

SOURCE_SUFFIXES = (".h", ".m", ".c")


def _source_text():
    chunks = []
    for path in LKS.iterdir():
        if path.suffix in SOURCE_SUFFIXES:
            chunks.append(path.read_text(encoding="utf-8", errors="replace"))
    return "\n".join(chunks)


@pytest.mark.parametrize("token", FORBIDDEN)
def test_no_buslogic_residue(token):
    assert token not in _source_text(), token
```

- [ ] **Step 2: Run it and confirm it fails**

```powershell
$env:PYTHONPATH = 'tools/binrecon'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m pytest `
  tools/binrecon/tests/test_sym53c8xx_buslogic_residue.py -q
```

Expected: FAIL — those tokens still exist.

- [ ] **Step 3: Replace `SYM53c8Types.h` from the report-pass layouts**

Delete BusLogic `struct ccb`, `SYM_HOST_*` mailbox-style host codes used as that CCB, and invented chip-ID macros that IDA never loads. Write the register map, CAM CCB, device-table entry, and SIM state using **offsets recorded in `divergences.md`**. Bit *names* may come from the 53C8xx programming guide or Linux as a reading aid. Every `#define` offset must appear as an immediate in the IDA listing of a SIM/CAM function; if it does not, do not invent it.

Keep the copyright block. Keep `#import`s the DriverKit headers still need.

Inline accessors in `SYM53c8Inline.h` must match the I/O vs MMIO decision in `divergences.md`. Rename `sym_*` accessors to the names IDA shows. Keep `inb`/`outb`/`inl`/`outl` wrappers only if the reference uses them.

- [ ] **Step 4: Rename the class to `SYM53c8` in headers and strip BusLogic APIs**

In `SYM53c8Controller.h` and `SYM53c8Thread.h`:

```objc
@interface SYM53c8 : IOSCSIController
```

```objc
@interface SYM53c8(IOThread)
```

Remove `allocCcb:`, `ccbFromCmd:ccb:`, `freeCcb:`, `runPendingCommands` from the IOThread category. Remove `symCcb`, `numFreeCcbs`, `outstandingQ`, `pendingQ` **only if** the reference ivar list in `divergences.md` does not contain them. Replace with the SIM/CCB ivars IDA named. Keep `commandQ`, `commandLock`, `ioBase` / BAR, `interruptPortKern`, DDM macros, and `SYMCommandBuf` if the reference still has an IOThread command queue. If IDA shows a different command-buf layout, use that.

Delete the `extern` declarations for `sym_reset_chip` and `sym_init_chip`.

Filenames stay `SYM53c8Controller.h` / `SYM53c8Thread.h`. Do not rename files in this task.

The `.m` files will not compile until Tasks 7–9. That is expected. Do not leave stub `runPendingCommands` bodies.

- [ ] **Step 5: Commit headers only**

```powershell
git add src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/SYM53c8.lksproj/SYM53c8Types.h `
        src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/SYM53c8.lksproj/SYM53c8Inline.h `
        src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/SYM53c8.lksproj/SYM53c8ControllerPrivate.h `
        src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/SYM53c8.lksproj/SYM53c8Controller.h `
        src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/SYM53c8.lksproj/SYM53c8Thread.h `
        tools/binrecon/tests/test_sym53c8xx_buslogic_residue.py
git commit -m "drivers-i386: rename SYM53c8 class and replace BusLogic CCB types"
```

The residue test is still RED. That is the point of Task 9.

---

### Task 7: SIM API

**Files:**
- Create: `$LKS/SYM53c8SIM.h`, `$LKS/SYM53c8SIM.c`
- Modify: `$LKS/Makefile`, `$LKS/PB.project`

- [ ] **Step 1: Dump one function from IDA JSON before writing anything**

```python
import json, sys
from pathlib import Path

name = sys.argv[1]
doc = json.loads(Path("tools/binrecon/out/sym53c8xx/published/analysis-reference-ida.json").read_text(encoding="utf-8"))
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

Run it for every C symbol that `divergences.md` identifies as the SIM API (init, ISR, queue, abort, reset — names may be `CCBInSIMQueue` and neighbors, not `SYM53c8SIM*`). Expected: address, size, and either decompilation or instruction/block lists. This is the source of every prototype and body.

- [ ] **Step 2: Write `SYM53c8SIM.h`**

Public API is exactly the functions Controller/Thread will call, plus the SIM-instance types from Task 6. Prototypes copy IDA’s argument counts and widths. Do not invent a fifth exported entry the `_reloc` does not have.

```c
#ifndef _SYM53C8SIM_H_
#define _SYM53C8SIM_H_

#import "SYM53c8Types.h"

/* Argument types and names come from IDA of the SIM symbols.
 * Replace this comment block with the real prototypes. */

#endif
```

CAM functions live in `SYM53c8CAM.c` and are `extern` here only if the SIM translation unit calls them.

- [ ] **Step 3: Write `SYM53c8SIM.c`**

For each SIM-API function:

1. Print its IDA instructions/blocks.
2. Write C whose control-flow shape, call targets, port immediates, and struct offsets match.
3. Account for every branch. Do not leave a `return 0;` stub.
4. After writing, tick the function in `divergences.md` and leave the ledger `unexamined` until Task 11.

Include:

```c
#import "SYM53c8SIM.h"
#import "SYM53c8Inline.h"
```

No `#import` of Linux headers. No `runPendingCommands`. No `sym_init_chip`.

If the report pass shows SIM+CAM as one blob, still put only the DriverKit-facing API in this file; the rest goes in Task 8.

- [ ] **Step 4: Hook `SYM53c8SIM.c` into the Kernel Server project**

`$LKS/Makefile`:

```
CLASSES = SYM53c8Controller.m SYM53c8Routines.m SYM53c8Thread.m
CFILES = SYM53c8SIM.c
HFILES = scsivar.h SYM53c8Controller.h SYM53c8ControllerPrivate.h SYM53c8Inline.h SYM53c8Thread.h SYM53c8Types.h SYM53c8SIM.h
```

`$LKS/PB.project` `FILESTABLE` `H_FILES` gains `SYM53c8SIM.h`. NeXT PB.project often omits `CFILES`; the Makefile `CFILES` line is what `kernelserver.make` consumes.

- [ ] **Step 5: Commit**

```powershell
git add src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/SYM53c8.lksproj/SYM53c8SIM.c `
        src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/SYM53c8.lksproj/SYM53c8SIM.h `
        src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/SYM53c8.lksproj/Makefile `
        src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/SYM53c8.lksproj/PB.project
git commit -m "drivers-i386: add SYM53c8 SIM API"
```

---

### Task 8: CAM helpers and SCRIPTS bytes

**Files:**
- Create: `$LKS/SYM53c8CAM.c`, `$LKS/SYM53c8Scripts.c`
- Modify: `$LKS/Makefile`, `$LKS/PB.project`, `$LKS/SYM53c8SIM.h` if CAM symbols need prototypes

- [ ] **Step 1: Dump IDA for the starting CAM names, then every remaining unmapped C symbol**

Use the Task 7 dump script for `CCBInSIMQueue` (if not already in SIM.c), `AddToDeviceList`, `DeletePathFromDeviceTable`, `FCalcSync`, `FSetWide`, `FWideInit`, `FResumeXFer`, `FSendMsg`, `AutosenseSetup`, `BeginScan`. Then walk the source-map `unmapped` C names (not glue, not ObjC) and dump each. Expected: a complete work list in `divergences.md`.

- [ ] **Step 2: Write `SYM53c8CAM.c`**

Same discipline as Task 7 for every remaining C function that is not SCRIPT data. Group roughly:

1. device table (`AddToDeviceList`, `DeletePathFromDeviceTable`, …)
2. scan (`BeginScan`, …)
3. autosense (`AutosenseSetup`, …)
4. sync/wide (`FCalcSync`, `FSetWide`, `FWideInit`, …)
5. xfer/message (`FResumeXFer`, `FSendMsg`, …)

Do not leave `return 0;` stubs. Do not copy Linux `ncr53c8xx` function bodies and rename them.

- [ ] **Step 3: Write `SYM53c8Scripts.c`**

Extract the SCRIPT bytes from `$REF` using the section/offset/length recorded in `divergences.md`. Emit a `const unsigned int` / `unsigned char` array whose contents match the `_reloc` exactly. Include a comment with file offset and length. Verify after writing:

```powershell
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -c @"
from pathlib import Path
# Fill OFFSET and LENGTH from divergences.md
OFFSET = 0  # replace
LENGTH = 0  # replace
ref = Path(r'C:\Users\raynorpat\Downloads\test\Drivers\i386\SYM53c8.config\SYM53c8_reloc').read_bytes()
blob = ref[OFFSET:OFFSET+LENGTH]
src = Path('src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/SYM53c8.lksproj/SYM53c8Scripts.c').read_text(encoding='utf-8')
print('blob', len(blob))
print('source bytes mentioned', LENGTH)
assert LENGTH == len(blob)
assert hex(blob[0])[2:] in src.lower() or str(blob[0]) in src
print('scripts header OK — finish by matching the full dump in the C array')
"@
```

Replace `OFFSET`/`LENGTH` with the report-pass numbers. The C array must be the full blob, not a placeholder of zeros. Not ppc `Sym8xxScript.ss`. Not Linux.

If SCRIPTS live as generated instructions inside several functions rather than one data blob, say so in `divergences.md` and put those functions in `SYM53c8CAM.c` instead of inventing a fake array. In that case `SYM53c8Scripts.c` is omitted and this step records why.

- [ ] **Step 4: Add the new C files to the Makefile**

```
CFILES = SYM53c8SIM.c SYM53c8CAM.c SYM53c8Scripts.c
```

Drop `SYM53c8Scripts.c` from `CFILES` only if Step 3 omitted the file.

- [ ] **Step 5: Confirm definition sites exist**

```powershell
$env:PYTHONPATH = 'tools/binrecon'
$env:BINRECON_REFERENCE = 'C:\Users\raynorpat\Downloads\test\Drivers\i386\SYM53c8.config\SYM53c8_reloc'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe tools/binrecon/symbol_name_check.py `
  $env:BINRECON_REFERENCE `
  src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/SYM53c8.lksproj
```

Expected: CAM/SIM names no longer appear as missing C symbols. BusLogic extras may still be reported as extra source names. Glue methods stay missing. Do not “fix” extras by renaming CAM functions to BusLogic names.

- [ ] **Step 6: Commit**

```powershell
git add src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/SYM53c8.lksproj/SYM53c8CAM.c `
        src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/SYM53c8.lksproj/SYM53c8Scripts.c `
        src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/SYM53c8.lksproj/Makefile `
        src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/SYM53c8.lksproj/PB.project `
        src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/SYM53c8.lksproj/SYM53c8SIM.h
git commit -m "drivers-i386: add SYM53c8 CAM helpers and SCRIPTS bytes"
```

---

### Task 9: Rewrite DriverKit methods and delete BusLogic residue

**Files:**
- Modify: `$LKS/SYM53c8Controller.m`, `$LKS/SYM53c8Thread.m`, `$LKS/SYM53c8Thread.h`, `$LKS/Makefile`, `$LKS/PB.project`, `src/drivers-i386/scsi/drvSym53C8xx/Makefile.preamble`
- Delete: `$LKS/SYM53c8Routines.m`

- [ ] **Step 1: Re-run the residue test — still RED**

```powershell
$env:PYTHONPATH = 'tools/binrecon'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m pytest `
  tools/binrecon/tests/test_sym53c8xx_buslogic_residue.py -q
```

Expected: FAIL until this task finishes.

- [ ] **Step 2: Rewrite each DriverKit method from IDA**

Class implementations become `@implementation SYM53c8` and `@implementation SYM53c8(PrivateMethods)` / `@implementation SYM53c8(IOThread)`.

Work reference ObjC methods in address order. For each method:

1. Dump IDA (Task 7 Step 1 script, method name as in the map, e.g. `-[SYM53c8 executeRequest:buffer:client:]`).
2. Replace the body so it matches. `executeRequest` / IOThread execute path must call the SIM queue, not `allocCcb:` / `runPendingCommands`.
3. `interruptOccurred` / `interruptOccurredAt:` must call the SIM ISR.
4. `resetSCSIBus` / thread reset must call SIM bus-reset / abort as IDA shows.
5. `probe:` / `initFromDeviceDescription:` must call SIM init. Failure → `probe:` returns `NO`.
6. Delete `runPendingCommands`, `allocCcb:`, `freeCcb:`, `ccbFromCmd:ccb:` from `SYM53c8Thread.h` and both `.m` files.

Do not invent a second class. Do not rename files.

- [ ] **Step 3: Delete `SYM53c8Routines.m` and drop it from the project**

`$LKS/Makefile`:

```
CLASSES = SYM53c8Controller.m SYM53c8Thread.m
CFILES = SYM53c8SIM.c SYM53c8CAM.c SYM53c8Scripts.c
```

`$LKS/PB.project` `CLASSES` = `(SYM53c8Controller.m, SYM53c8Thread.m)`.

`src/drivers-i386/scsi/drvSym53C8xx/Makefile.preamble`:

```
MFILES = SYM53c8Controller.m SYM53c8Thread.m
```

`git rm` `SYM53c8Routines.m`.

- [ ] **Step 4: Residue test GREEN**

```powershell
$env:PYTHONPATH = 'tools/binrecon'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m pytest `
  tools/binrecon/tests/test_sym53c8xx_buslogic_residue.py -q
```

Expected: PASS. If a token remains in a comment, delete the comment or the file. Do not weaken the test.

- [ ] **Step 5: Commit**

```powershell
git add src/drivers-i386/scsi/drvSym53C8xx tools/binrecon/tests/test_sym53c8xx_buslogic_residue.py
git commit -m "drivers-i386: point SYM53c8 DriverKit paths at the SIM"
```

---

### Task 10: Config tables and English.lproj/Help

**Files:**
- Modify: `$DRVPROJ/Default.table`, `$DRVPROJ/Makefile`
- Create: `$DRVPROJ/English.lproj/Help/…`
- Delete: `$DRVPROJ/English.lproj/DriverHelp/`
- Modify: `DriverInfo` and `$LKS/Load_Commands.sect` only if Task 4 recorded a real divergence

- [ ] **Step 1: Align `Default.table` with the reference, except `"Driver Version"`**

Add `"Version" = "5.00";`. Do not copy the reference `"Driver Version"` PROGRAM line. Keep the existing keys that already match (Title, Auto Detect IDs, Help File name, Server Name, Wide SCSI, Synchronous, Valid IRQ Levels). Do not add 875/895 PCI IDs unless Task 4 showed the `_reloc` probe enumerates them.

- [ ] **Step 2: Copy Help from the reference and switch `LOCAL_RESOURCES`**

```powershell
$src = 'C:\Users\raynorpat\Downloads\test\Drivers\i386\SYM53c8.config\English.lproj\Help'
$dst = 'src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/English.lproj/Help'
Copy-Item -Recurse -Force $src $dst
git rm -r src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/English.lproj/DriverHelp
```

`$DRVPROJ/Makefile`:

```
LOCAL_RESOURCES = Localizable.strings Help SYM53c8Inspector.nib
```

Leave `SYM53c8Inspector.nib` in place. Do not copy the `SYM53c8` DYLDLINK inspector binary.

Confirm copied help is text/RTF you are willing to commit (RTFD `TXT.rtf` and any image resources the reference already ships).

- [ ] **Step 3: Commit**

```powershell
git add src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/Default.table `
        src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/Makefile `
        src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/English.lproj
git commit -m "drivers-i386: align drvSym53C8xx tables and help with SYM53c8.config"
```

---

### Task 11: Remap, ledger statuses, final compile, status docs

**Files:**
- Modify: `$RECON/source-map.json`, `$RECON/ledger.json`, `$RECON/divergences.md`
- Modify: `docs/drivers/scsi-reconstruction.md`, `src/drivers-i386/README`

- [ ] **Step 1: Remap to scratch, then merge lines by address**

```powershell
$env:BINRECON_REFERENCE = 'C:\Users\raynorpat\Downloads\test\Drivers\i386\SYM53c8.config\SYM53c8_reloc'
$env:PYTHONPATH = 'tools/binrecon'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m binrecon source-map `
  --reference-analysis tools/binrecon/out/sym53c8xx/published/analysis-reference-ida.json `
  --binary $env:BINRECON_REFERENCE `
  --source-dir src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/SYM53c8.lksproj `
  --repo-root . `
  --objc-methods `
  --output $env:TEMP/sym53c8xx-fresh.json
```

CAM/SIM names must now be `mapped` to `SYM53c8SIM.c` or `SYM53c8CAM.c`. ObjC methods must map to `SYM53c8`, not `SYM53c8Controller`. Glue stays `unmapped`. If a CAM name is still `unmapped`, the definition site is wrong (leading underscore, `static`, or name mismatch) — fix the source, do not edit the map by hand to lie.

Copy fresh `source_path` / `source_line` into the committed map by `address`. Run `check_map.py` from Task 3. Expected: `source map OK`. Mapped count = IDA `__text` count minus the two glue methods (and any other stated unmapped reason class).

- [ ] **Step 2: Advance the ledger**

For each mapped function, after reading IDA against the new source:

- `assembly-matched` if every instruction was compared.
- `control-flow-confirmed` only for the largest function, and only if `divergences.md` says which parts were not traced operand-by-operand.

```powershell
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m binrecon ledger `
  --profile tools/binrecon/profiles/sym53c8xx.json `
  --ledger src/drivers-i386/scsi/drvSym53C8xx/reconstruction/ledger.json `
  --address $ADDR --status assembly-matched `
  --source-path src/drivers-i386/scsi/drvSym53C8xx/SYM53c8.drvproj/SYM53c8.lksproj/SYM53c8SIM.c `
  --source-line $LINE
```

Do not claim `assembly-matched` without the read. Leave `unexamined` rather than guess.

- [ ] **Step 3: Final guest compile**

Host sync first (`sync-src.ps1 -Path drivers-i386/scsi/drvSym53C8xx`).

```sh
tr -d '\r' < /build/source/vm/build-i386-scsi.sh > /tmp/bscsi.sh
sh /tmp/bscsi.sh drvSym53C8xx
```

Expected: exit 0, `_reloc` staged under `out/i386/drvSym53C8xx/`. Warnings go in `divergences.md`; they do not gate. Do not run `binrecon compare` on the rebuilt file.

- [ ] **Step 4: Residue test still green**

```powershell
$env:PYTHONPATH = 'tools/binrecon'
& D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe -m pytest `
  tools/binrecon/tests/test_sym53c8xx_buslogic_residue.py -q
```

Expected: PASS.

- [ ] **Step 5: Update status docs**

In `docs/drivers/scsi-reconstruction.md`, change the drvSym53C8xx row from `stub, wrong architecture` to reconstructed against the reference; guest `_reloc` produced; not hardware-tested. Change the class-name cell from `SYM53c8Controller` to `SYM53c8` (ours now matches). Leave other driver rows alone.

In `src/drivers-i386/README`:

```
 * drvSym53C8xx - reconstructed against the reference binary, compiled; not hardware-tested
```

- [ ] **Step 6: Commit**

```powershell
git add src/drivers-i386/scsi/drvSym53C8xx/reconstruction `
        docs/drivers/scsi-reconstruction.md `
        src/drivers-i386/README
git commit -m "drivers-i386: finish drvSym53C8xx reconstruction ledger and status"
```

---

## Spec coverage

| Spec section | Task |
| --- | --- |
| §1.1 reference identity / profile | 1–2 |
| §1.2 tables, help, Load_Commands | 4, 10 |
| §1.3 no inspector, no QEMU, Linux reading aid only, this driver only | Global Constraints |
| §2 BusLogic vs CAM/SIM, invented symbols, class name | 4, 6, 9 |
| §3 three-layer architecture | 7–9 |
| §4 components / Routines.m retirement | 7–9 |
| §5 data flow / completion from `_reloc` | 4 (record), 9 (implement) |
| §6 reconstruction/ artifacts | 3–4 |
| §7.1 report pass | 2–4 |
| §7.2 fix pass layers | 6–11 |
| §8 error handling | 2 (Ghidra), 6–9 (no stubs / no Linux copy), 5/11 (compile) |
| §9 done bar | 11 |
| §10 sequencing | Task order |
| `vm/build-i386-scsi.sh` | 5 |
| SCRIPTS from this `_reloc` | 4 (locate), 8 (emit) |

## Self-review notes

- No TBD/TODO. SIM prototypes are taken from IDA in Task 7, not invented here.
- `seed_ledger.py` agreement rewrite is explicit so i386 ledgers match 1542B, not the PPC default.
- Residue pytest is RED from Task 6 through Task 9 on purpose; do not skip it or mark xfail.
- Installed `_reloc` name is already `SYM53c8`; do not rename `drvSym53C8xx`.
- If SCRIPTS are not a data blob, Task 8 omits `SYM53c8Scripts.c` with a recorded reason rather than inventing zeros.
