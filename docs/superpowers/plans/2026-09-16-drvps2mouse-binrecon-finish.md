# drvPS2Mouse binrecon finish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drive `drvPS2Mouse` to function-level `raw_equal` / `masked_equal` against Apple's `PS2Mouse_reloc`, with local `VERS_OFILE` symbols, a guest `_reloc`, and an honest ledger.

**Architecture:** Sequential measured close. Restore the deleted guest harness, baseline the current tree, drop the Finding 13 null guards, make the interrupt handler `void`, wire `VERS_OFILE`, then cheapest-first grinding. One edit, one guest rebuild, one `binrecon function --list`. The three already `assembly-matched` methods are a regression gate.

**Tech Stack:** Python in `.venv-binrecon`, `tools/binrecon` (IDA 9.2 only), Rhapsody guest `gnumake` / `pb_makefiles`, `vm/sync-src.ps1` + `vm/build-i386-input-recon.sh`.

**Spec:** [2026-09-16-drvps2mouse-binrecon-finish-design.md](../specs/2026-09-16-drvps2mouse-binrecon-finish-design.md)

## File map

| File | Responsibility |
|---|---|
| `vm/build-i386-input-recon.sh` | Guest harness. Restore if missing; keep a sibling copy and add `drvPS2Mouse` otherwise. |
| `tools/binrecon/profiles/ps2mouse.json` | IDA-only; `rebuilt` path via `${BINRECON_REBUILT}`. |
| `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m` | Only translation unit for guards, handler type, and Phase 5 shape. |
| `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/Makefile.postamble` | Created. One line: `OTHER_GENERATED_OFILES += $(VERS_OFILE)`. |
| `src/drivers-i386/input/drvPS2Mouse/reconstruction/function-worklist.md` | Baseline and per-phase `--list` snapshots. |
| `src/drivers-i386/input/drvPS2Mouse/reconstruction/divergences.md` | Finding 13/14 reversals, VERS close, accepts. |
| `src/drivers-i386/input/drvPS2Mouse/reconstruction/ledger.json` | Per-function status; `rebuilt_sha256` of last kept `_reloc`. |
| `src/drivers-i386/input/drvPS2Mouse/reconstruction/source-map.json` | Line numbers when bodies move. |
| `src/drivers-i386/README` | Final status line. |

Do not touch `PS2Mouse.h`, `src/kernel-7`, other input drivers, `driverTools`, compiler flags, or glue methods. Do not strip unused `PS2_CMD_*` macros. Do not re-enable Ghidra or angr. Do not invert `Force Detection`.

## Global constraints

```text
VENVPY=D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe
REF=C:/Users/raynorpat/Downloads/test/Drivers/i386/PS2Mouse.config/PS2Mouse_reloc
REFSHA=4C43D8A9AE0B83ACD1BA4D17340A4C6BF5FDACD84634CE5C7FC457D97DE11A7E
LKS=src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj
RECON=src/drivers-i386/input/drvPS2Mouse/reconstruction
PROFILE=tools/binrecon/profiles/ps2mouse.json
REBUILT=out/i386/drvPS2Mouse/PS2Mouse.config/PS2Mouse_reloc
```

Work in a dedicated worktree, not the main checkout. `.worktrees/` is gitignored.

```powershell
git worktree add .worktrees/drvps2mouse-finish -b drvps2mouse-binrecon-finish HEAD
```

Set `REPO` to that worktree and run every command from there. `VENVPY` stays the main-repo venv unless the worktree has its own.

- **Never commit** `$REF`, `tools/binrecon/out/`, `out/i386/`, or a rebuilt `_reloc`.
- **`BINRECON_REFERENCE` and `BINRECON_REBUILT` must be exported** in every shell that runs `binrecon` after Task 2's first `_reloc` exists. Until that file exists, do not run `binrecon validate` / `analyze` / `function`.
- **Python is `$VENVPY`.** `PYTHONPATH=tools/binrecon`.
- **Commits:** `drvPS2Mouse: `, `binrecon: `, `vm: `, or `docs: ` prefix, one to two lines, no metadata, no trailers.
- **Reviewer:** `Pat Raynor`.
- **Guest sync:** `powershell -File vm\sync-src.ps1 -Path drivers-i386/input/drvPS2Mouse`. Never `-All`. `sync-src.ps1` cannot upload `vm/`; copy the harness separately (block below).
- **Guest unreachable:** stop, record it in `divergences.md`, do not invent byte diffs.
- **Diagnosed edits stay** even if extents do not close: drop guards, `void` handler, `VERS_OFILE` line. Experiments revert on miss.
- **Regression gate:** `-[PS2Mouse getHandler:level:argument:forInterrupt:]`, `-[PS2Mouse getResolution]`, `-[PS2Mouse getIntValues:forParameter:count:]`. If any lose `masked_equal`, revert.
- **`setIntValues:` 12-byte gcc spill is accepted.** Do not add dummy stack spills.
- **IDA extents are the comparison extents.** Do not use symbol-gap sizes.

### Guest rebuild (copy this block)

```powershell
powershell -NoProfile -File vm\sync-src.ps1 -Path drivers-i386/input/drvPS2Mouse
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
$ec = Invoke-RhapRemote -Cfg $cfg -Ssh $ssh -RemoteCommand 'tr -d "\r" < /build/source/vm/build-i386-input-recon.sh > /tmp/binput.sh && mv /tmp/binput.sh /build/source/vm/build-i386-input-recon.sh; sh /build/source/vm/build-i386-input-recon.sh drvPS2Mouse'
if ($ec -ne 0) { throw "guest build ssh exit $ec" }
$dst = 'out/i386/drvPS2Mouse/PS2Mouse.config'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
$remoteTar = "cd /build/out/i386/drvPS2Mouse/PS2Mouse.config && tar cf - PS2Mouse_reloc"
Invoke-RhapSshAskPass -Cfg $cfg -Action {
  cmd /c "ssh $($opts -join ' ') $sshHost `"$remoteTar`" | tar xf - -C $dst"
  if ($LASTEXITCODE -ne 0) { throw "tar pull exit $LASTEXITCODE" }
}
if (-not (Test-Path $dst\PS2Mouse_reloc)) { throw "missing $dst\PS2Mouse_reloc" }
```

Expected guest log: `=== input-recon done fail=0 built: drvPS2Mouse ===` and a staged `PS2Mouse_reloc`. The guest root shell is `tcsh` and `/bin/sh` is 1999 Bourne: no `2>&1` inside the remote command string.

### Host measure (copy this block)

```powershell
$env:PYTHONPATH = "tools/binrecon"
$env:BINRECON_REFERENCE = "C:\Users\raynorpat\Downloads\test\Drivers\i386\PS2Mouse.config\PS2Mouse_reloc"
$env:BINRECON_REBUILT = (Resolve-Path "out\i386\drvPS2Mouse\PS2Mouse.config\PS2Mouse_reloc").Path
& "D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe" -m binrecon validate --profile tools/binrecon/profiles/ps2mouse.json
# Analyze may exit 1 until normalized-functions acceptance passes. That is expected.
# Gate: published/ contains analysis-reference-ida.json, analysis-rebuilt-ida.json, comparison-ida.json.
& "D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe" -m binrecon analyze --profile tools/binrecon/profiles/ps2mouse.json --output tools/binrecon/out/ps2mouse/run-summary.json
& "D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe" -m binrecon function --profile tools/binrecon/profiles/ps2mouse.json --list
& "D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe" tools/binrecon/parity_check.py $env:BINRECON_REFERENCE $env:BINRECON_REBUILT
```

`validate` must print `reference ... sha256=4C43D8A9AE0B83ACD1BA4D17340A4C6BF5FDACD84634CE5C7FC457D97DE11A7E`. `parity_check.py` must print `missing_strings (0):` and `missing_symbols (0):`. Extra unstripped symbols are not a failure.

For one function:

```powershell
& "D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe" -m binrecon function --profile tools/binrecon/profiles/ps2mouse.json --name "-[PS2Mouse mouseInit:]"
```

---

### Task 1: Restore harness and IDA-only profile

**Files:**
- Create or keep: `vm/build-i386-input-recon.sh`
- Modify: `tools/binrecon/profiles/ps2mouse.json`

No driver source. No guest. Do not run `binrecon analyze`.

- [ ] **Step 1: Restore or extend the harness**

If `vm/build-i386-input-recon.sh` is missing:

```powershell
git checkout d529b15f1^ -- vm/build-i386-input-recon.sh
```

That restores the file as of `1b1b68b93` (includes `drvISASerialPort`). Do not edit other drivers' arms.

If the file already exists, keep it. Ensure this `case` arm is present (add it if missing, do not delete sibling arms):

```sh
	drvPS2Mouse)
		build_one PS2Mouse drvPS2Mouse PS2Mouse.drvproj || fail=1
		;;
```

The script must invoke `gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386`, strip CR from Makefiles, stage `${name}_reloc` under `/build/out/i386/$dir/$name.config/`, and end with `exit $fail`. Do not add `set -e`. Rhapsody's `/bin/sh` kills a script if a predicate function returns nonzero under `set -e`.

- [ ] **Step 2: Make the profile IDA-only with a rebuilt key**

Replace `tools/binrecon/profiles/ps2mouse.json` with:

```json
{
  "schema_version": "profile-v1",
  "name": "drvPS2Mouse reconstruction (IDA only)",
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
  "output_dir": "../out/ps2mouse"
}
```

- [ ] **Step 3: Check the files without analyzing**

```powershell
Select-String -Path vm\build-i386-input-recon.sh -Pattern "drvPS2Mouse" | Select-Object -First 3
python -c "import json; p=json.load(open('tools/binrecon/profiles/ps2mouse.json')); assert p['analyzers']['ghidra']['enabled'] is False; assert p['analyzers']['angr']['enabled'] is False; assert p['analyzers']['ida']['enabled'] is True; assert 'rebuilt' in p; assert p['output_dir']=='../out/ps2mouse'; print('profile ok')"
```

Expected: a `drvPS2Mouse)` arm and `profile ok`.

- [ ] **Step 4: Commit**

```powershell
git add vm/build-i386-input-recon.sh tools/binrecon/profiles/ps2mouse.json
git commit -m "vm: restore input recon harness and IDA-only ps2mouse profile"
```

---

### Task 2: Baseline guest build and worklist

**Files:**
- Create: `src/drivers-i386/input/drvPS2Mouse/reconstruction/function-worklist.md`
- Modify: `src/drivers-i386/input/drvPS2Mouse/reconstruction/divergences.md` (baseline note only)

No `PS2Mouse.m` edits.

- [ ] **Step 1: Guest-build the current tree**

Run the Guest rebuild block. `$REBUILT` must exist afterwards.

- [ ] **Step 2: Host-measure**

Run the Host measure block. Capture `--list` and `parity_check.py` counts. Record the `_reloc` file size and SHA-256:

```powershell
Get-FileHash -Algorithm SHA256 $env:BINRECON_REBUILT | Format-List
(Get-Item $env:BINRECON_REBUILT).Length
```

- [ ] **Step 3: Write `function-worklist.md`**

Create `src/drivers-i386/input/drvPS2Mouse/reconstruction/function-worklist.md` with:

- date and rebuilt SHA-256 and byte size
- `parity_check.py` four counts
- the full `binrecon function --list` table
- a reachability note: Finding 13/14/VERS are still in source, so this snapshot is pre-fix

Do not advance any ledger status. Do not set `rebuilt_sha256` yet (this `_reloc` is not kept as the campaign result).

Append a short "Phase 1 baseline" paragraph to `divergences.md` with size, SHA, and the four parity counts.

- [ ] **Step 4: Commit**

```powershell
git add src/drivers-i386/input/drvPS2Mouse/reconstruction/function-worklist.md src/drivers-i386/input/drvPS2Mouse/reconstruction/divergences.md
git commit -m "drvPS2Mouse: record the instruction-stream baseline worklist"
```

---

### Task 3: Drop Finding 13 null guards

**Files:**
- Modify: `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m`
- Modify: `src/drivers-i386/input/drvPS2Mouse/reconstruction/divergences.md`
- Modify: `src/drivers-i386/input/drvPS2Mouse/reconstruction/source-map.json` (line numbers)
- Modify: `src/drivers-i386/input/drvPS2Mouse/reconstruction/function-worklist.md`
- Modify: `src/drivers-i386/input/drvPS2Mouse/reconstruction/ledger.json` (status text only after measure)

Keep even if extents do not close.

- [ ] **Step 1: Remove the three early returns**

In `_PS2MouseIntHandler`, delete:

```objc
    /* Check if controller functions are available */
    if (controllerFunctions == NULL) {
        return 0;
    }

```

The next statement is `status = controllerFunctions->readMouseByte(&dataByte);`.

In `- (BOOL)isMousePresent`, delete:

```objc
    /* Check if controller functions are available */
    if (controllerFunctions == NULL) {
        return NO;
    }

```

The next statement is `status = controllerFunctions->sendMouseCommand(PS2_CMD_SET_RESOLUTION);`.

In `- (void)resetMouse`, delete:

```objc
    /* Check if controller functions are available */
    if (controllerFunctions == NULL) {
        return;
    }

```

The next statement is `controllerFunctions->sendMouseCommand(PS2_CMD_SET_DEFAULTS);`.

- [ ] **Step 2: Unguard `initWithController:`**

Replace the drain:

```objc
    if (controllerFunctions != NULL && controllerFunctions->reserved[3] != NULL) {
        ((void (*)(void))controllerFunctions->reserved[3])();
    }
```

with:

```objc
    ((void (*)(void))controllerFunctions->reserved[3])();
```

Replace the 8042 block (the outer `if (controllerFunctions != NULL)` and every per-slot `!= NULL`, including the `else { statusByte = 0; }`) with:

```objc
    ((void (*)(unsigned char))controllerFunctions->reserved[0])(K8042_READ_COMMAND_BYTE);
    statusByte = ((unsigned char (*)(void))controllerFunctions->reserved[1])();
    ((void (*)(unsigned char))controllerFunctions->reserved[0])(K8042_WRITE_COMMAND_BYTE);
    ((void (*)(unsigned char))controllerFunctions->reserved[4])((statusByte & 0xDF) | 0x02);
```

Leave `if (controllerDevice == nil)` alone. Leave `if (!force_detection)` alone. Do not invert Force Detection.

Confirm no remaining `controllerFunctions == NULL` or `controllerFunctions != NULL` and no `reserved[N] != NULL` in this file:

```powershell
Select-String -Path src\drivers-i386\input\drvPS2Mouse\PS2Mouse.drvproj\PS2Mouse.lksproj\PS2Mouse.m -Pattern "controllerFunctions == NULL|controllerFunctions != NULL|reserved\[[0-9]\] != NULL"
```

Expected: no matches.

- [ ] **Step 3: Rebuild, measure, record**

Guest rebuild + Host measure. `__TEXT,__text` should move toward 1804. `isMousePresent`, `resetMouse`, `initWithController:`, and `_PS2MouseIntHandler` should shrink. The three regression-gate methods must still have `masked_equal`. `missing_strings` 0, `missing_symbols` 0.

If a regression-gate method loses `masked_equal`, revert this task and stop.

Update Finding 13 in `divergences.md`: disposition **fixed**, acceptance reversed. Refresh `function-worklist.md` with the new `--list`. Update `source-map.json` `source_line` values to the new method starts. Do not yet mark functions `assembly-matched` unless `--name` shows `raw_equal` or `masked_equal`; if they match, set `assembly-matched`. If they still differ, leave `intentional-mismatch` until Task 4 (handler) or Task 6.

- [ ] **Step 4: Commit**

```powershell
git add src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m src/drivers-i386/input/drvPS2Mouse/reconstruction
git commit -m "drvPS2Mouse: drop controllerFunctions null guards the reference does not have"
```

---

### Task 4: Make `_PS2MouseIntHandler` void

**Files:**
- Modify: `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m` only (header stays untouched)
- Modify: `src/drivers-i386/input/drvPS2Mouse/reconstruction/divergences.md`
- Modify: `src/drivers-i386/input/drvPS2Mouse/reconstruction/source-map.json`
- Modify: `src/drivers-i386/input/drvPS2Mouse/reconstruction/function-worklist.md`
- Modify: `src/drivers-i386/input/drvPS2Mouse/reconstruction/ledger.json`

Keep even if the extent does not close.

- [ ] **Step 1: Change the signature and every `return 0` in the handler**

Forward declaration, currently:

```objc
static unsigned int PS2MouseIntHandler(unsigned int param_1, unsigned int param_2);
```

becomes:

```objc
static void PS2MouseIntHandler(unsigned int param_1, unsigned int param_2);
```

Definition and comment: replace `static unsigned int PS2MouseIntHandler(...)` with `static void PS2MouseIntHandler(...)`. Replace the `@return always 0...` paragraph with:

```objc
 * @return void. DriverKit discards the handler result; the reference never writes eax.
```

Every `return 0;` **inside `_PS2MouseIntHandler` only** becomes `return;`. Do not change `return NO;` / `return YES;` / `return IO_R_*` in methods. The `if (status == 0)` test (no data from `readMouseByte`) stays; only its `return 0` becomes `return`.

`-getHandler:level:argument:forInterrupt:` still assigns `*handler = (IOInterruptHandler)PS2MouseIntHandler;`. Do not edit `PS2Mouse.h`.

- [ ] **Step 2: Rebuild, measure, record**

Guest rebuild + Host measure. Handler epilogue must not write `eax` if gcc emits the reference shape. Regression gate must still `masked_equal`. Finding 14 handler-return half: disposition **fixed**. Do not reopen the already-fixed `mouseInit:` half of Finding 14.

If `_PS2MouseIntHandler` is now `raw_equal` or `masked_equal`, set ledger `assembly-matched` and clear `reason`/`reviewer`. Otherwise leave it for Task 6 with the `--name` dump in `divergences.md`.

Refresh worklist and source-map line numbers.

- [ ] **Step 3: Commit**

```powershell
git add src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m src/drivers-i386/input/drvPS2Mouse/reconstruction
git commit -m "drvPS2Mouse: declare the interrupt handler void like the reference"
```

---

### Task 5: Wire local `VERS_OFILE`

**Files:**
- Create: `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/Makefile.postamble`
- Modify: reconstruction records; do not edit `driverTools` or guest-installed makefiles

- [ ] **Step 1: Create the Kernel Server postamble**

File contents, entire file:

```
OTHER_GENERATED_OFILES += $(VERS_OFILE)
```

`PS2Mouse.lksproj/Makefile` already has `-include Makefile.postamble`. Do not create a Driver-project postamble. The MH_BUNDLE is not a gate.

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
for n in ('_PS2Mouse_VERS_STRING', '_PS2Mouse_VERS_NUM'):
    print(n, 'present' if n in names else 'MISSING')
"@
```

Gate: a `__TEXT,__const` section exists and both symbols are present. Do not compare the 160-byte string to Apple's. If symbols are missing, record whether `PS2Mouse_vers.c` / `.o` were generated and whether they appear on the `kl_ld` line. Do not then edit `driverTools`. Existence stays unmet until a later local makefile fix that is still inside this driver's tree; if none exists, accept the gap in `divergences.md` and continue.

Hand-written `__text` identity must not regress.

- [ ] **Step 3: Record and commit**

Note in `divergences.md` that the `__TEXT,__const` gap is closed (or accepted with guest evidence). Refresh the worklist.

```powershell
git add src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/Makefile.postamble src/drivers-i386/input/drvPS2Mouse/reconstruction
git commit -m "drvPS2Mouse: emit vers_string objects from the Kernel Server postamble"
```

---

### Task 6: Cheapest-first grinding

**Files:**
- Modify: `PS2Mouse.m` only, one experiment per rebuild
- Modify: reconstruction records after each kept rebuild

Do not start until Tasks 3–5 are committed. Glue methods stay generated.

**Cycle (repeat until the done bar in Step 4):**

1. Run `--list`. Ignore the two `+[...]` glue rows. Ignore any row with `raw_equal` or `masked_equal`.
2. Take the cheapest remaining hand-written row.
3. If that row is `-[PS2Mouse setIntValues:forParameter:count:]` and `--name` differs only by gcc hoist/spill of `parameterArray` / compare count (ours smaller, no missing call, no wrong offset): accept. Write the `--name` dump into `divergences.md` with disposition accept. Ledger: `intentional-mismatch`, reason naming gcc spill, reviewer `Pat Raynor`. Next row.
4. If the cheapest leftover is register allocation or instruction scheduling (same calls, same constants, same offsets, different register or `cmp` operand order): accept the same way. Do not add dummy locals or reorder statements.
5. Otherwise run **one** experiment from the list below that matches the `--name` dump. Guest rebuild + Host measure.
   - Match (`raw_equal` or `masked_equal`): keep, ledger `assembly-matched`, next function.
   - Miss, no regression: revert the experiment, mark tried in `divergences.md`, next list item.
   - Regression of a gate method: revert, record failed-with-regression, next list item.
6. Empty list and still not matching: accept as unreachable with the dump.

**Starter lists** (rewrite from the current `--list` if ranking differs):

`isMousePresent` / `resetMouse` / `initWithController:` / `_PS2MouseIntHandler` — should already be closed by Tasks 3–4. If not, the next experiment is the cheapest remaining instruction from `--name`, not a new invention. Do not reorder `_PS2MouseIntHandler` resync / timeout / `seqBeingProcessed` / `seqInProgress` branches.

`-[PS2Mouse mouseInit:]` — reference store order is `seqInProgress`, `seqBeingProcessed`, `indexInSequence`, `summedEvent.deltaY` (`buf[2]`), `summedEvent.deltaX` (`buf[1]`), `resolution = 0x96`. Experiments, one per rebuild: (1) match that store order if source differs; (2) write the two `BOOL` flags as `0` rather than `NO`; (3) write resolution as `150` rather than `0x96`.

`-[PS2Mouse readConfigTable:]` — (1) declaration order of `forceDetectionStr` / `invertedStr` / `resolutionStr`; (2) NULL-or-not-`y`/`Y` branch layout if `--name` shows a different shape. Do not invert stored sense.

`-[PS2Mouse interruptOccurred]` — (1) pass `&currentEvent` (already required by Finding 6). If `--name` shows a local copy, stop using the copy.

`getHandler:` / `getResolution` / `getIntValues:` — regression only. No experiments.

Commit after each **kept** rebuild (`drvPS2Mouse: `). Reverted experiments are not committed.

- [ ] **Step 1: Grind until every hand-written function is matched or accepted**

- [ ] **Step 2: Refresh worklist, ledger, source-map, divergences after the last kept rebuild**

- [ ] **Step 3: Confirm glue is still only the two generated methods**

`--list` may still show the two `+[PS2MouseKernelServerInstance kernelServerInstance]` and `+[PS2MouseVersion driverKitVersionForPS2Mouse]` rows unmatched. That is required. Do not hand-write them.

- [ ] **Step 4: Done-bar check for this task**

Every paired hand-written function is `raw_equal` / `masked_equal` or recorded unreachable. `missing_strings` 0, `missing_symbols` 0.

---

### Task 7: Final records

**Files:**
- Modify: `src/drivers-i386/input/drvPS2Mouse/reconstruction/ledger.json` (`rebuilt_sha256`)
- Modify: `src/drivers-i386/README`
- Modify: `divergences.md` / `function-worklist.md` closing summary

- [ ] **Step 1: Set `rebuilt_sha256`**

In `ledger.json`, set `rebuilt_sha256` to the SHA-256 of the last kept `$REBUILT` (uppercase hex, no `0x`). Keep `reference_sha256` as `4C43D8A9AE0B83ACD1BA4D17340A4C6BF5FDACD84634CE5C7FC457D97DE11A7E`.

Validate:

```powershell
$env:PYTHONPATH = "tools/binrecon"
$env:BINRECON_REFERENCE = "C:\Users\raynorpat\Downloads\test\Drivers\i386\PS2Mouse.config\PS2Mouse_reloc"
$env:BINRECON_REBUILT = (Resolve-Path "out\i386\drvPS2Mouse\PS2Mouse.config\PS2Mouse_reloc").Path
& "D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe" -m binrecon ledger --profile tools/binrecon/profiles/ps2mouse.json --ledger src/drivers-i386/input/drvPS2Mouse/reconstruction/ledger.json
```

Expected: exit 0.

- [ ] **Step 2: Update the README line**

Replace:

```
 * drvPS2Mouse - compiles; reconstructed against the reference binary, fixes applied, not yet tested
```

with a line that names the new `masked_equal` / `assembly-matched` counts, that `_PS2Mouse_VERS_STRING` / `_VERS_NUM` exist, and that the driver is still untested on hardware. Example shape (fill in the real counts from `--list`):

```
 * drvPS2Mouse - compiles; N/11 hand-written functions masked-equal to PS2Mouse_reloc, version objects emitted; not yet tested on hardware
```

- [ ] **Step 3: Closing paragraph in `divergences.md` and `function-worklist.md`**

State which functions matched, which were accepted and why, and the last rebuilt SHA.

- [ ] **Step 4: Commit**

```powershell
git add src/drivers-i386/README src/drivers-i386/input/drvPS2Mouse/reconstruction
git commit -m "drvPS2Mouse: record instruction-stream finish counts and rebuilt hash"
```

---

## Spec coverage (self-review)

| Spec requirement | Task |
|---|---|
| Restore / keep harness, only run `drvPS2Mouse` | 1 |
| IDA-only profile + `rebuilt` key | 1 |
| Baseline guest `_reloc` + worklist | 2 |
| Drop Finding 13 guards, keep even if extents miss | 3 |
| Void handler, keep even if extent misses | 4 |
| Kernel Server `VERS_OFILE`, symbols exist, no string match, no `driverTools` | 5 |
| Cheapest-first, experiment lists, accept gcc spill | 6 |
| Regression gate on three methods | 3–6 |
| `rebuilt_sha256`, README, no QEMU | 7 |
| No `PS2Mouse.h`, no `kernel-7`, no other drivers | global |
| `Force Detection` not inverted | Task 3 |
| Glue stays generated | Task 6 Step 3 |
