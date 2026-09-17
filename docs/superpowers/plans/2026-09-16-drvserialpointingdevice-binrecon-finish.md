# drvSerialPointingDevice binrecon finish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drive `drvSerialPointingDevice` to function-level `raw_equal` / `masked_equal` (or recorded compiler-shaped accepts) against Apple's `SerialPointingDevice_reloc`, with local `VERS_OFILE` symbols, a guest `_reloc`, and an honest ledger.

**Architecture:** Sequential measured close. Restore or extend the guest harness, baseline the current tree under IDA, wire `VERS_OFILE`, then cheapest-first source-shape grinding. One edit, one guest rebuild, one `binrecon function --list`. Layout, strings, linkage, and Findings 1–16 stay closed. No QEMU.

**Tech Stack:** Python in `.venv-binrecon`, `tools/binrecon` (IDA 9.2 only), Rhapsody guest `gnumake` / `pb_makefiles`, `vm/sync-src.ps1` + `vm/build-i386-input-recon.sh`.

**Spec:** [2026-09-16-drvserialpointingdevice-binrecon-finish-design.md](../specs/2026-09-16-drvserialpointingdevice-binrecon-finish-design.md)

## File map

| File | Responsibility |
|---|---|
| `vm/build-i386-input-recon.sh` | Guest harness. Restore if missing; keep sibling arms and add `drvSerialPointingDevice`. |
| `tools/binrecon/profiles/serialpointingdevice.json` | IDA-only; `rebuilt` path via `${BINRECON_REBUILT}`. |
| `src/drivers-i386/input/drvSerialPointingDevice/SerialPointingDevice.drvproj/SerialPointingDevice.lksproj/SerialPointingDevice.m` | Only translation unit for instruction-shape edits. |
| `src/drivers-i386/input/drvSerialPointingDevice/SerialPointingDevice.drvproj/SerialPointingDevice.lksproj/SerialPointingDevice.h` | Touch only if a typed rewrite is required. No ivar or superclass churn. |
| `src/drivers-i386/input/drvSerialPointingDevice/SerialPointingDevice.drvproj/SerialPointingDevice.lksproj/Makefile.postamble` | Created. One line: `OTHER_GENERATED_OFILES += $(VERS_OFILE)`. |
| `src/drivers-i386/input/drvSerialPointingDevice/reconstruction/function-worklist.md` | Baseline and per-phase `--list` snapshots. |
| `src/drivers-i386/input/drvSerialPointingDevice/reconstruction/divergences.md` | VERS close, experiment outcomes, accepts. Findings 1–16 stay. |
| `src/drivers-i386/input/drvSerialPointingDevice/reconstruction/ledger.json` | Per-function status; `rebuilt_sha256` of last kept `_reloc`. |
| `src/drivers-i386/input/drvSerialPointingDevice/reconstruction/source-map.json` | Line numbers when bodies move. 16 mapped / 2 unmapped. |
| `src/drivers-i386/README` | Final status line. Still not hardware-tested. |

## Global constraints

```text
VENVPY=D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe
REF=C:/Users/raynorpat/Downloads/test/Drivers/i386/SerialPointingDevice.config/SerialPointingDevice_reloc
REFSHA=59C0C95C5A4D93456BDD6667970AC4A3605A961FEAC2CF7CE97F586D3A958F59
LKS=src/drivers-i386/input/drvSerialPointingDevice/SerialPointingDevice.drvproj/SerialPointingDevice.lksproj
RECON=src/drivers-i386/input/drvSerialPointingDevice/reconstruction
PROFILE=tools/binrecon/profiles/serialpointingdevice.json
REBUILT=out/i386/drvSerialPointingDevice/SerialPointingDevice.config/SerialPointingDevice_reloc
```

Work in a dedicated worktree, not the main checkout. `.worktrees/` is gitignored.

```powershell
git worktree add .worktrees/drvserialpointingdevice-finish -b drvserialpointingdevice-binrecon-finish HEAD
```

Set `REPO` to that worktree and run every command from there. `VENVPY` stays the main-repo venv unless the worktree has its own.

- **Never commit** `$REF`, `tools/binrecon/out/`, `out/i386/`, or a rebuilt `_reloc`.
- **`BINRECON_REFERENCE` and `BINRECON_REBUILT` must be exported** in every shell that runs `binrecon` after Task 2's first `_reloc` exists. Until that file exists, do not run `binrecon validate` / `analyze` / `function`.
- **Python is `$VENVPY`.** `PYTHONPATH=tools/binrecon`.
- **Commits:** `drvSerialPointingDevice: `, `drivers-i386: `, `vm: `, or `docs: ` prefix, one to two lines, no metadata, no trailers. Stage by explicit path. Never `git add -A`.
- **Reviewer:** `Pat Raynor`.
- **Guest sync:** `powershell -File vm\sync-src.ps1 -Path drivers-i386/input/drvSerialPointingDevice`. Never `-All`. `sync-src.ps1` cannot upload `vm/`; copy the harness separately (block below).
- **Guest unreachable:** stop, record it in `divergences.md`, do not invent byte diffs.
- **Diagnosed edit stays** even if extents do not close: the `VERS_OFILE` line. Experiments revert on miss.
- **Regression gate is established in Task 2**, not assumed from the five July `assembly-matched` claims. After Task 2, any row that is `raw_equal` or `masked_equal` is a gate. If a later edit loses that, revert.
- **`setIntValues:` 312-versus-263 gap is codegen.** Do not add dummy stack spills.
- **IDA extents are the comparison extents.** Do not use symbol-gap sizes.
- **Do not touch:** `Default.table`, `Load_Commands.sect`, `Unload_Commands.sect`, `Makefile` / `Makefile.preamble`, `dpkg/`, `src/kernel-7`, sibling input drivers, `compare.py`, `kernel-drivers-blacklist.json`, `driverTools`, compiler flags beyond the existing `-Wno-format -DDRIVER_PRIVATE`, glue methods. Do not split `SerialPointingDevice.m`. Do not re-enable Ghidra or angr. Do not grind envelope size. Do not chase `__TEXT,__text` 4468.
- **This session runs every guest rebuild.** Do not invent instruction diffs. Every source edit comes from `binrecon function --name` of a named function. If the dump is not in hand, stop.
- **`normalized-functions=FAIL` is expected** until the campaign closes. Analyze may exit 1; the gate is `complete: true` and the three published IDA files listed in Host measure.

### Guest rebuild (copy this block)

```powershell
powershell -NoProfile -File vm\sync-src.ps1 -Path drivers-i386/input/drvSerialPointingDevice
. .\vm\rhap-remote.ps1
$cfg = Get-RhapVmConfig
$ssh = Resolve-RhapTool $cfg.Ssh
$sshHost = "$($cfg.User)@$($cfg.Host)"
$opts = @($script:RhapLegacySshOptions)
# Upload harness (sync-src.ps1 cannot copy vm/).
Invoke-RhapSshAskPass -Cfg $cfg -Action {
  & $ssh @opts $sshHost "mkdir -p /build/source/vm"
}
$localHarness = (Resolve-Path 'vm\build-i386-input-recon.sh').Path
Invoke-RhapSshAskPass -Cfg $cfg -Action {
  cmd /c "scp $($opts -join ' ') `"$localHarness`" ${sshHost}:/build/source/vm/build-i386-input-recon.sh"
  if ($LASTEXITCODE -ne 0) { throw "scp harness exit $LASTEXITCODE" }
}
$ec = Invoke-RhapRemote -Cfg $cfg -Ssh $ssh -RemoteCommand 'tr -d "\r" < /build/source/vm/build-i386-input-recon.sh > /tmp/binput.sh && mv /tmp/binput.sh /build/source/vm/build-i386-input-recon.sh; sh /build/source/vm/build-i386-input-recon.sh drvSerialPointingDevice'
if ($ec -ne 0) { throw "guest build ssh exit $ec" }
$dst = 'out/i386/drvSerialPointingDevice/SerialPointingDevice.config'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
$remoteTar = "cd /build/out/i386/drvSerialPointingDevice/SerialPointingDevice.config && tar cf - SerialPointingDevice_reloc"
Invoke-RhapSshAskPass -Cfg $cfg -Action {
  cmd /c "ssh $($opts -join ' ') $sshHost `"$remoteTar`" | tar xf - -C $dst"
  if ($LASTEXITCODE -ne 0) { throw "tar pull exit $LASTEXITCODE" }
}
if (-not (Test-Path $dst\SerialPointingDevice_reloc)) { throw "missing $dst\SerialPointingDevice_reloc" }
```

Expected guest log: `=== input-recon done fail=0 built: drvSerialPointingDevice ===` and a staged `SerialPointingDevice_reloc`. The guest root shell is `tcsh` and `/bin/sh` is 1999 Bourne: no `2>&1` inside the remote command string.

### Host measure (copy this block)

```powershell
$env:PYTHONPATH = "tools/binrecon"
$env:BINRECON_REFERENCE = "C:\Users\raynorpat\Downloads\test\Drivers\i386\SerialPointingDevice.config\SerialPointingDevice_reloc"
$env:BINRECON_REBUILT = (Resolve-Path "out\i386\drvSerialPointingDevice\SerialPointingDevice.config\SerialPointingDevice_reloc").Path
& "D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe" -m binrecon validate --profile tools/binrecon/profiles/serialpointingdevice.json
# Analyze may exit 1 until normalized-functions acceptance passes. That is expected.
# Gate: published/ contains analysis-reference-ida.json, analysis-rebuilt-ida.json, comparison-ida.json.
& "D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe" -m binrecon analyze --profile tools/binrecon/profiles/serialpointingdevice.json --output tools/binrecon/out/serialpointingdevice/run-summary.json
& "D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe" -m binrecon function --profile tools/binrecon/profiles/serialpointingdevice.json --list
& "D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe" tools/binrecon/parity_check.py $env:BINRECON_REFERENCE $env:BINRECON_REBUILT
```

`validate` must print `reference ... sha256=59C0C95C5A4D93456BDD6667970AC4A3605A961FEAC2CF7CE97F586D3A958F59`. `parity_check.py` must print `missing_strings (0):` and `missing_symbols (0):`. Extra unstripped symbols are not a failure.

Reuse published reference analysis if `tools/binrecon/out/serialpointingdevice/published/` already has `complete: true` and the SHA is `59C0C95C…`. Always IDA-analyze the new rebuilt `_reloc`. Do not treat leftover Ghidra/angr published files as current. Do not hand-edit published JSON.

For one function:

```powershell
& "D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe" -m binrecon function --profile tools/binrecon/profiles/serialpointingdevice.json --name "-[SerialPointingDevice mouseInit:]"
```

Use the symbol name as it appears in `--list`.

---

### Task 1: Guest harness and IDA-only profile

**Files:**
- Create or modify: `vm/build-i386-input-recon.sh`
- Modify: `tools/binrecon/profiles/serialpointingdevice.json`

No driver source. No guest. Do not run `binrecon analyze`.

- [ ] **Step 1: Restore or extend the harness**

If `vm/build-i386-input-recon.sh` is missing:

```powershell
git checkout d529b15f1^ -- vm/build-i386-input-recon.sh
```

That restores the file as of `1b1b68b93` (includes sibling arms such as `drvISASerialPort`). Do not delete sibling arms. Then add `drvSerialPointingDevice` if it is not already present.

If the file already exists, keep it. Ensure this `case` arm is present (add it if missing, do not delete sibling arms, do not restore a five-driver dispatcher):

```sh
	drvSerialPointingDevice)
		build_one SerialPointingDevice drvSerialPointingDevice SerialPointingDevice.drvproj || fail=1
		;;
```

If the restored script has no `build_one` helper and uses a `NAME`/`PROJ` `case` instead, add:

```sh
drvSerialPointingDevice)
	NAME=SerialPointingDevice
	PROJ=SerialPointingDevice.drvproj
	;;
```

and stage that arm to `/build/out/i386/$DRV/${NAME}.config`. Keep existing arms and their stage paths. Do not change another driver's `NAME`/`PROJ`.

The script must invoke `gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386`, strip CR from Makefiles, stage `SerialPointingDevice_reloc` under `/build/out/i386/drvSerialPointingDevice/SerialPointingDevice.config/`, and must not use `set -e` on predicates. Rhapsody's `/bin/sh` kills a script if a predicate function returns nonzero under `set -e`. Prefer no `set -e` at all. POSIX Bourne only: no `local`, no bashisms. LF line endings. No CRLF.

If `git checkout d529b15f1^` fails and the file is still absent, create it with only the `drvSerialPointingDevice` arm. Whole script in that case:

```sh
#!/bin/sh
# Build one i386 input driver under reconstruction and stage its _reloc.
# Usage: sh vm/build-i386-input-recon.sh drvSerialPointingDevice
#
# Gating is on artifact presence, not gnumake's exit code. A recursive
# pb_makefiles build can return nonzero for a step outside what we need.
# Keep this POSIX sh — Rhapsody's /bin/sh is a 1999 Bourne shell.

DRV="$1"
NAME=""
PROJ=""
case "$DRV" in
drvSerialPointingDevice)
	NAME=SerialPointingDevice
	PROJ=SerialPointingDevice.drvproj
	;;
*)
	echo "usage: $0 drvSerialPointingDevice" >&2
	exit 2
	;;
esac

ROOT="${SRCROOT:-/build/source}"
SRC="$ROOT/src/drivers-i386/input/$DRV"
STAGE="/build/out/i386/$DRV/${NAME}.config"

if [ ! -d "$SRC" ]; then
	echo "build-i386-input-recon: missing $SRC" >&2
	exit 1
fi

find "$SRC" -type f \( -name Makefile -o -name Makefile.preamble -o -name Makefile.postamble -o -name '*.make' \) -print |
while read f
do
	tr -d '\r' < "$f" > /tmp/rhap_cr && mv /tmp/rhap_cr "$f"
done

LKS=`ls -d "$SRC"/*.drvproj/*.lksproj 2>/dev/null | head -1`
if [ -z "$LKS" ]; then
	echo "FAILED: no .lksproj under $SRC" >&2
	exit 1
fi

echo "======== build $NAME ($DRV) ========"
cd "$LKS" || exit 1
gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386
echo "make exit=$?"

RELOC=`ls -1 ${NAME}_reloc 2>/dev/null | head -1`
if [ -z "$RELOC" ] || [ ! -f "$RELOC" ]; then
	echo "FAILED: no ${NAME}_reloc for $NAME" >&2
	find "$SRC" \( -name '*reloc*' -o -name '*.config' \) 2>/dev/null | head -40 >&2
	exit 1
fi

mkdir -p "$STAGE"
cp -p "$RELOC" "$STAGE/"
for f in "$SRC/$PROJ"/*.table; do
	[ -f "$f" ] || continue
	cp -p "$f" "$STAGE/"
done

echo "=== input-recon done fail=0 built: $DRV ==="
ls -l "$STAGE"
```

- [ ] **Step 2: Make the profile IDA-only with a rebuilt key**

Replace `tools/binrecon/profiles/serialpointingdevice.json` with:

```json
{
  "schema_version": "profile-v1",
  "name": "drvSerialPointingDevice reconstruction (IDA only)",
  "architecture": "i386",
  "endianness": "little",
  "reference": {
    "path": "${BINRECON_REFERENCE}"
  },
  "rebuilt": {
    "path": "${BINRECON_REBUILT}"
  },
  "analyzers": {
    "ida": {
      "enabled": true,
      "executable": "C:/Program Files/IDA Professional 9.2/idat.exe",
      "timeout_seconds": 900,
      "version": "9.2"
    },
    "ghidra": {
      "enabled": false,
      "executable": "D:/ghidra/support/analyzeHeadless.bat",
      "timeout_seconds": 900,
      "version": "12.1"
    },
    "angr": {
      "enabled": false,
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
  "output_dir": "../out/serialpointingdevice"
}
```

- [ ] **Step 3: Check the files without analyzing**

```powershell
Select-String -Path vm\build-i386-input-recon.sh -Pattern "drvSerialPointingDevice" | Select-Object -First 3
python -c "import json; p=json.load(open('tools/binrecon/profiles/serialpointingdevice.json')); assert p['analyzers']['ghidra']['enabled'] is False; assert p['analyzers']['angr']['enabled'] is False; assert p['analyzers']['ida']['enabled'] is True; assert 'rebuilt' in p; assert p['output_dir']=='../out/serialpointingdevice'; print('profile ok')"
```

Expected: a `drvSerialPointingDevice)` arm and `profile ok`.

Optional host syntax check (Git Bash or WSL):

```bash
sh -n vm/build-i386-input-recon.sh && echo "syntax OK"
```

If you have no Unix `sh` on Windows, skip that line and rely on the guest `sh` in Task 2.

- [ ] **Step 4: Commit**

```powershell
git add vm/build-i386-input-recon.sh tools/binrecon/profiles/serialpointingdevice.json
git commit -m "vm: restore input recon harness and IDA-only serialpointingdevice profile"
```

If the harness already existed and you only added an arm:

```powershell
git commit -m "drivers-i386: add SerialPointingDevice guest harness arm and rebuilt profile path"
```

---

### Task 2: Phase 1 baseline on the guest

**Files:**
- Create: `src/drivers-i386/input/drvSerialPointingDevice/reconstruction/function-worklist.md`
- Modify: `src/drivers-i386/input/drvSerialPointingDevice/reconstruction/divergences.md` (baseline note only)
- Depends on: Task 1 harness in the worktree

No driver source edits. No `Makefile.postamble` yet.

- [ ] **Step 1: Confirm the reference binary**

```powershell
Get-FileHash -Algorithm SHA256 $env:BINRECON_REFERENCE
```

Set `$env:BINRECON_REFERENCE` to `$REF` first if needed. Expected: `59C0C95C5A4D93456BDD6667970AC4A3605A961FEAC2CF7CE97F586D3A958F59`. If it differs, **BLOCKED**.

- [ ] **Step 2: Guest-build the current tree**

Run the Guest rebuild block. `$REBUILT` must exist afterwards. Expected: `=== input-recon done fail=0 built: drvSerialPointingDevice ===`. If the build fails, **BLOCKED** — the July fix pass already compiled this tree; report the log and fix only what it names. Do not start function edits.

- [ ] **Step 3: Host-measure**

Run the Host measure block. Capture `--list` and `parity_check.py` counts. Record the `_reloc` file size and SHA-256:

```powershell
Get-FileHash -Algorithm SHA256 $env:BINRECON_REBUILT | Format-List
(Get-Item $env:BINRECON_REBUILT).Length
```

Expected: `missing_strings (0):` and `missing_symbols (0):`. `validate` prints the reference SHA above and a `rebuilt` line with this SHA.

- [ ] **Step 4: Confirm instance_size 356**

```powershell
$env:PYTHONPATH = "tools/binrecon"
& "D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe" -c @"
from binrecon.macho import read_macho
from pathlib import Path
import os
m = read_macho(Path(os.environ['BINRECON_REBUILT']))
print(m.keys())
for s in m.get('objc_classes', m.get('classes', [])):
    print(s)
"@
```

`SerialPointingDevice` `instance_size` must stay 356. If the helper is not on the macho document, read `__OBJC,__class` the way `divergences.md` Finding 1 did (class name + `instance_size`). Do not guess. If instance size is not 356, **BLOCKED** — that is a July regression.

- [ ] **Step 5: Write the worklist**

Create `src/drivers-i386/input/drvSerialPointingDevice/reconstruction/function-worklist.md` with:

- Date and worktree branch
- Reference SHA-256 and size (39928)
- Rebuilt SHA-256 and size
- `__TEXT,__text` sizes (reference 4468; rebuilt measured)
- `parity_check.py` missing counts (must be 0 / 0)
- `SerialPointingDevice` `instance_size` (must stay 356)
- Full `--list` pasted or summarized: identical / masked-eq counts, cheapest remaining rows
- Which of the five July `assembly-matched` rows actually show `raw_equal` or `masked_equal` on this `_reloc` (those become the regression gate)
- Reachability: which cheapest rows look source-shaped vs already compiler-shaped (register allocation / instruction scheduling)

- [ ] **Step 6: Note the baseline in divergences.md**

Append a short "Finish campaign" heading: date, rebuilt SHA, how many rows were already `masked_equal` / `raw_equal` at baseline, which July `assembly-matched` rows held. Do not delete Findings 1–16.

- [ ] **Step 7: Commit**

```powershell
git add src/drivers-i386/input/drvSerialPointingDevice/reconstruction/function-worklist.md src/drivers-i386/input/drvSerialPointingDevice/reconstruction/divergences.md
git commit -m "drvSerialPointingDevice: record instruction-stream baseline worklist"
```

Never stage `out/` or `tools/binrecon/out/`.

---

### Task 3: Advance already-identical functions in the ledger

**Files:**
- Modify: `src/drivers-i386/input/drvSerialPointingDevice/reconstruction/ledger.json`
- Modify: `src/drivers-i386/input/drvSerialPointingDevice/reconstruction/divergences.md` (short note only)
- Depends on: Task 2 `--list`

No driver source. No rebuild.

- [ ] **Step 1: Read the worklist**

Every `--list` row that is identical or `masked_equal` (`raw_equal` or `masked_equal` true), except the two glue methods, becomes `assembly-matched` if it is not already.

The two glue methods stay `intentional-mismatch`:

- `+[SerialPointingDeviceKernelServerInstance kernelServerInstance]`
- `+[SerialPointingDeviceVersion driverKitVersionForSerialPointingDevice]`

- [ ] **Step 2: Transition the ledger**

Use `binrecon ledger` with `$env:BINRECON_REBUILT` set so `rebuilt_sha256` updates, or edit `ledger.json` with the same vocabulary. Forward-only: `control-flow-confirmed` → `assembly-matched`. Do not skip down to `unexamined`. Do not mark compiler-shaped leftovers `assembly-matched`. Do not demote a July `assembly-matched` row that failed `masked_equal` until Task 5 accepts it; leave it `control-flow-confirmed` and name it in the worklist grind set.

Reviewer: `Pat Raynor` (match existing ledger entries).

- [ ] **Step 3: Commit**

```powershell
git add src/drivers-i386/input/drvSerialPointingDevice/reconstruction/ledger.json src/drivers-i386/input/drvSerialPointingDevice/reconstruction/divergences.md
git commit -m "drvSerialPointingDevice: mark baseline-identical functions assembly-matched"
```

---

### Task 4: Wire local `VERS_OFILE`

**Files:**
- Create: `src/drivers-i386/input/drvSerialPointingDevice/SerialPointingDevice.drvproj/SerialPointingDevice.lksproj/Makefile.postamble`
- Modify: reconstruction records; do not edit `driverTools` or guest-installed makefiles
- Depends on: Task 2 baseline (so regressions are visible)

- [ ] **Step 1: Create the Kernel Server postamble**

File contents, entire file:

```
OTHER_GENERATED_OFILES += $(VERS_OFILE)
```

`SerialPointingDevice.lksproj/Makefile` already has `-include Makefile.postamble` and already names `Makefile.postamble` in `OTHERSRCS`. Do not create a Driver-project postamble. Do not edit `Makefile` or `Makefile.preamble`. The MH_BUNDLE is not a gate.

- [ ] **Step 2: Rebuild and prove the symbols**

Guest rebuild + Host measure. Then:

```powershell
$env:PYTHONPATH = "tools/binrecon"
& "D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe" -c @"
from pathlib import Path
from binrecon.macho import read_macho
p = Path(r'$env:BINRECON_REBUILT')
d = read_macho(p)
secs = [(s['name'], s['size']) for s in d['sections']]
print('sections:', secs)
names = [s['name'] for s in d['symbols']]
for n in ('_SerialPointingDevice_VERS_STRING', '_SerialPointingDevice_VERS_NUM'):
    print(n, 'present' if n in names else 'MISSING')
"@
```

Gate: a `__TEXT,__const` section exists and both symbols are present. Do not compare the 160-byte string to Apple's. If symbols are missing, record whether `SerialPointingDevice_vers.c` / `.o` were generated and whether they appear on the `kl_ld` line. Do not then edit `driverTools`. Existence stays unmet until a later local makefile fix that is still inside this driver's tree; if none exists, accept the gap in `divergences.md` and continue.

Hand-written `__text` identity must not regress: every Task 2/3 `raw_equal` / `masked_equal` row stays equal. `parity_check.py` stays 0 / 0.

This edit stays even if `__text` extents do not close.

- [ ] **Step 3: Record and commit**

Note in `divergences.md` that the `__TEXT,__const` gap is closed (or accepted with guest evidence). Refresh the worklist.

```powershell
git add src/drivers-i386/input/drvSerialPointingDevice/SerialPointingDevice.drvproj/SerialPointingDevice.lksproj/Makefile.postamble src/drivers-i386/input/drvSerialPointingDevice/reconstruction
git commit -m "drvSerialPointingDevice: emit vers_string objects from the Kernel Server postamble"
```

---

### Task 5: Cheapest-first instruction-shape grind

**Files:**
- Modify: `src/drivers-i386/input/drvSerialPointingDevice/SerialPointingDevice.drvproj/SerialPointingDevice.lksproj/SerialPointingDevice.m`
- Modify headers in that directory only if a typed rewrite is required
- Modify: `reconstruction/function-worklist.md`, `divergences.md`, `ledger.json`, `source-map.json` (line numbers if bodies move)
- Depends on: Tasks 2–4

Do not start until Tasks 2–4 are committed. Glue methods stay generated.

- [ ] **Step 1: Write named experiment lists into the worklist**

Before the first source edit, append to `function-worklist.md` a short list per remaining non-equal paired function, cheapest `differing` first. One experiment idea per function to start; add more only after a miss.

Allowed: statement order, local vs expression, signedness of *locals*, loop shape, `if` vs `else if`, operand-reversed `cmp`, declaration order of existing locals.

Forbidden: padding ivars; changing instance layout; renaming ivars; inventing temporaries whose only purpose is to pick a register after the list is empty; repeating a reverted experiment; chasing `__text` size; rewriting a Task 2/3 gate row; reordering load-bearing control listed below; splitting the `.m` file.

Load-bearing (already match Apple's algorithm; shape experiments may retarget a local or a store order, not this control):

- `detect`: four-iteration baud sweep (`baudRate` 1200, 2400, 4800, 9600 sending `executeEvent:0x33` at 2400, 4800, 9600, 19200); `M` / `M3` / `*?` → `mouseType` 1–4; Mouse Systems `C` at slot 5.
- `getByte:sleep:`: `do` / `while (active)` — one dequeue always happens before `_active` is consulted.
- `MSProtocol`: three-byte packet, 40 ms unsigned 64-bit gate, no `IOLog`.
- `FiveBProtocol`: `lastTimeStamp` updates on case 2 only, not case 4; same 40 ms gate; no `IOLog`.
- `mouseInit:`: `[portDevice acquire:nil]`; `PCPatoi`; `BOOL` polarity (YES success, NO failure).

Optional starters if `--name` shows a source-shaped gap (rewrite from the current `--list` if ranking differs):

1. `MSProtocol`: fold `maskedByte` so the high bit is masked in place (`and [ebp+var_1], 7Fh`).
2. `MSProtocol`: let `default:` fall through with the incremented `byteIndex` rather than forcing 0. Chase only if it is the cheapest remaining difference.
3. `detect`: compute `byte & 0x3F` inline in the verbose `*?` log instead of the `resolution` local.

`-[SerialPointingDevice setIntValues:forParameter:count:]` — list is empty unless `--name` shows a *source-level* difference. The 312-versus-263 gap is codegen. Do not add stack spills by hand.

Compiler-shaped means the `--name` columns differ only by register choice, instruction scheduling, or equivalent gcc 2.x shape — not a wrong constant, missing call, inverted branch, or wrong offset.

- [ ] **Step 2: Loop until every remaining paired function is equal or accepted**

For each cheapest still-open source-shaped row:

1. `--name` the current function. Keep the dump.
2. Apply one experiment in `SerialPointingDevice.m`.
3. Run the Guest rebuild procedure. `parity_check.py` must stay 0 / 0.
4. Fresh analyze of the rebuilt. `--name` on the **new** published comparison. `--list` to confirm previously identical rows (the Task 2/3 gate set) did not regress.
5. Match (`raw_equal` or `masked_equal`) → keep the edit, ledger `assembly-matched`, record outcome in `divergences.md`, commit `drvSerialPointingDevice: ` describing the behaviour.
6. Miss, no regression → revert the experiment, mark tried in the worklist, try the next item on that function's list. Reverted experiments are not committed.
7. Regression of a closed function → revert, record failed-with-regression, continue.
8. Empty list, still not equal → accept: paste `--name` dump under `divergences.md`, ledger `intentional-mismatch` with reason `compiler-shaped leftover after exhausted source-shape list` and reviewer `Pat Raynor`. Do not grind further.

One shared cause is one edit cluster (one commit). Relined `source-map.json` when bodies move; keep 16 mapped / 2 unmapped.

If `--list` grows unpaired functions other than the two glue methods, stop grinding. That is a layout or linkage finding.

If `__text` stays away from 4468 after all accepts, record the sizes. Not a failure.

- [ ] **Step 3: Stop condition**

`--list`: unpaired only the two glue methods. Every other hand-written row is identical, `masked_equal`, or accepted. Ledger has no `unexamined` hand-written function. Glue is still only:

- `+[SerialPointingDeviceKernelServerInstance kernelServerInstance]`
- `+[SerialPointingDeviceVersion driverKitVersionForSerialPointingDevice]`

Do not hand-write them.

---

### Task 6: Campaign close

**Files:**
- Modify: `reconstruction/function-worklist.md`
- Modify: `reconstruction/ledger.json` (`rebuilt_sha256` = last kept `_reloc`)
- Modify: `src/drivers-i386/README` drvSerialPointingDevice line
- Depends on: Task 5 stop condition

No further source-shape edits.

- [ ] **Step 1: Refresh the worklist summary**

Final SHA-256s, `--list` counts (identical / masked-eq / accepted / unpaired glue), `__text` sizes, statement that hardware testing is still out, statement that the two `vers_string` symbols exist (or the accepted gap).

- [ ] **Step 2: Set ledger `rebuilt_sha256`**

Must equal the SHA-256 of the last kept `SerialPointingDevice_reloc` (uppercase hex, no `0x`). Keep `reference_sha256` as `59C0C95C5A4D93456BDD6667970AC4A3605A961FEAC2CF7CE97F586D3A958F59`.

- [ ] **Step 3: Update README**

Change only the drvSerialPointingDevice bullet. Keep "not yet tested." Name the new counts and that version objects exist. Do not write `complete`. Example shape (fill in the real numbers from `--list`):

```
 * drvSerialPointingDevice - compiles; reconstructed against the reference binary, N/16 hand-written functions byte-identical under relocation masking, remainder accepted as compiler-shaped, apple-generic version objects present; not yet tested
```

- [ ] **Step 4: Commit**

```powershell
git add src/drivers-i386/input/drvSerialPointingDevice/reconstruction/function-worklist.md src/drivers-i386/input/drvSerialPointingDevice/reconstruction/ledger.json src/drivers-i386/README
git commit -m "drivers-i386: record drvSerialPointingDevice instruction-stream finish"
```

---

## Spec coverage

| Spec section | Task |
|---|---|
| Phase 0 harness, SerialPointingDevice arm, no five-driver dispatcher | 1 |
| Profile IDA-only, `rebuilt.path`, angr/Ghidra off | 1 |
| Phase 1 baseline, parity 0/0, worklist, instance_size 356, regression gate from measurement | 2 |
| Already-identical rows → `assembly-matched` | 3 |
| Phase 2 `VERS_OFILE`, symbols exist, no string match, no `driverTools` | 4 |
| Phase 3 cheapest-first grind, allowed/forbidden, load-bearing, accepts | 5 |
| Phase 4 close, README, `rebuilt_sha256` | 6 |
| Guest SSH, no `-All`, no pscp-as-primary (scp via rhap-remote is allowed) | Guest rebuild procedure |
| Glue unpaired, no QEMU, no kernel-7, no split TUs | Tasks 3–6 constraints |
