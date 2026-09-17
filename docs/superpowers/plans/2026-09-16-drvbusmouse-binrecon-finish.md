# drvBusMouse binrecon finish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drive `drvBusMouse` to function-level `raw_equal` / `masked_equal` against Apple's `BusMouse_reloc`, with local `VERS_OFILE` symbols, a guest `_reloc`, and an honest ledger.

**Architecture:** Sequential measured close. Restore the deleted guest harness, baseline the current tree, wire `VERS_OFILE`, then cheapest-first grinding of the three named compiler residuals. One edit, one guest rebuild, one `binrecon function --list`. The eight already `assembly-matched` methods are a regression gate. Findings 1–19 stay closed.

**Tech Stack:** Python in `.venv-binrecon`, `tools/binrecon` (IDA 9.2 only), Rhapsody guest `gnumake` / `pb_makefiles`, `vm/sync-src.ps1` + `vm/build-i386-input-recon.sh`.

**Spec:** [2026-09-16-drvbusmouse-binrecon-finish-design.md](../specs/2026-09-16-drvbusmouse-binrecon-finish-design.md)

## File map

| File | Responsibility |
|---|---|
| `vm/build-i386-input-recon.sh` | Guest harness. Restore if missing; keep a sibling copy and add `drvBusMouse` otherwise. |
| `tools/binrecon/profiles/busmouse.json` | IDA-only; `rebuilt` path via `${BINRECON_REBUILT}`. |
| `src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj/BusMouse.m` | Only translation unit for Phase 3 shape experiments. |
| `src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj/Makefile.postamble` | Created. One line: `OTHER_GENERATED_OFILES += $(VERS_OFILE)`. |
| `src/drivers-i386/input/drvBusMouse/reconstruction/function-worklist.md` | Baseline and per-phase `--list` snapshots. |
| `src/drivers-i386/input/drvBusMouse/reconstruction/divergences.md` | VERS close, exhausted experiment lists, accepts. |
| `src/drivers-i386/input/drvBusMouse/reconstruction/ledger.json` | Per-function status; `rebuilt_sha256` of last kept `_reloc`. |
| `src/drivers-i386/input/drvBusMouse/reconstruction/source-map.json` | Line numbers when bodies move. |
| `src/drivers-i386/README` | Final status line. |

Do not touch `BusMouse.h`, `src/kernel-7`, other input drivers, `driverTools`, compiler flags, or glue methods. Do not re-enable Ghidra or angr. Do not reopen Findings 1–19. Do not invert the doubled `outb(0x23E, 0x80)`, the unguarded `target` send, or the shared `return NO` in `validConfiguration:`.

## Global constraints

```text
VENVPY=D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe
REF=C:/Users/raynorpat/Downloads/test/Drivers/i386/BusMouse.config/BusMouse_reloc
REFSHA=A1AAB49F4D9F2BA90B4D7105F3D76BBF054F6D2D150B041D2156FC4F75E71864
LKS=src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj
RECON=src/drivers-i386/input/drvBusMouse/reconstruction
PROFILE=tools/binrecon/profiles/busmouse.json
REBUILT=out/i386/drvBusMouse/BusMouse.config/BusMouse_reloc
```

Work in a dedicated worktree, not the main checkout. `.worktrees/` is gitignored.

```powershell
git worktree add .worktrees/drvbusmouse-finish -b drvbusmouse-binrecon-finish HEAD
```

Set `REPO` to that worktree and run every command from there. `VENVPY` stays the main-repo venv unless the worktree has its own.

- **Never commit** `$REF`, `tools/binrecon/out/`, `out/i386/`, or a rebuilt `_reloc`.
- **`BINRECON_REFERENCE` and `BINRECON_REBUILT` must be exported** in every shell that runs `binrecon` after Task 2's first `_reloc` exists. Until that file exists, do not run `binrecon validate` / `analyze` / `function`.
- **Python is `$VENVPY`.** `PYTHONPATH=tools/binrecon`.
- **Commits:** `drvBusMouse: `, `binrecon: `, `vm: `, or `docs: ` prefix, one to two lines, no metadata, no trailers.
- **Reviewer:** `Pat Raynor`.
- **Guest sync:** `powershell -File vm\sync-src.ps1 -Path drivers-i386/input/drvBusMouse`. Never `-All`. `sync-src.ps1` cannot upload `vm/`; copy the harness separately (block below).
- **Guest unreachable:** stop, record it in `divergences.md`, do not invent byte diffs.
- **The `VERS_OFILE` line stays** even if `__text` extents do not close. Experiments revert on miss.
- **Regression gate:** `-[BusMouse validConfiguration:]`, `-[BusMouse interruptHandler]`, `_BusMouseThread`, `-[BusMouse mouseInit:]`, `-[BusMouse free]`, `-[BusMouse getHandler:level:argument:forInterrupt:]`, `-[BusMouse getResolution]`, `-[BusMouse getIntValues:forParameter:count:]`. If any lose `masked_equal`, revert.
- **`setIntValues:` 12-byte gcc spill is accepted** once `--name` shows only hoist/spill. Do not add dummy stack spills.
- **IDA extents are the comparison extents.** Do not use symbol-gap sizes.

### Guest rebuild (copy this block)

```powershell
powershell -NoProfile -File vm\sync-src.ps1 -Path drivers-i386/input/drvBusMouse
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
$ec = Invoke-RhapRemote -Cfg $cfg -Ssh $ssh -RemoteCommand 'tr -d "\r" < /build/source/vm/build-i386-input-recon.sh > /tmp/binput.sh && mv /tmp/binput.sh /build/source/vm/build-i386-input-recon.sh; sh /build/source/vm/build-i386-input-recon.sh drvBusMouse'
if ($ec -ne 0) { throw "guest build ssh exit $ec" }
$dst = 'out/i386/drvBusMouse/BusMouse.config'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
$remoteTar = "cd /build/out/i386/drvBusMouse/BusMouse.config && tar cf - BusMouse_reloc"
Invoke-RhapSshAskPass -Cfg $cfg -Action {
  cmd /c "ssh $($opts -join ' ') $sshHost `"$remoteTar`" | tar xf - -C $dst"
  if ($LASTEXITCODE -ne 0) { throw "tar pull exit $LASTEXITCODE" }
}
if (-not (Test-Path $dst\BusMouse_reloc)) { throw "missing $dst\BusMouse_reloc" }
```

Expected guest log: `=== input-recon done fail=0 built: drvBusMouse ===` and a staged `BusMouse_reloc`. The guest root shell is `tcsh` and `/bin/sh` is 1999 Bourne: no `2>&1` inside the remote command string.

### Host measure (copy this block)

```powershell
$env:PYTHONPATH = "tools/binrecon"
$env:BINRECON_REFERENCE = "C:\Users\raynorpat\Downloads\test\Drivers\i386\BusMouse.config\BusMouse_reloc"
$env:BINRECON_REBUILT = (Resolve-Path "out\i386\drvBusMouse\BusMouse.config\BusMouse_reloc").Path
& "D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe" -m binrecon validate --profile tools/binrecon/profiles/busmouse.json
# Analyze may exit 1 until normalized-functions acceptance passes. That is expected.
# Gate: published/ contains analysis-reference-ida.json, analysis-rebuilt-ida.json, comparison-ida.json.
& "D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe" -m binrecon analyze --profile tools/binrecon/profiles/busmouse.json --output tools/binrecon/out/busmouse/run-summary.json
& "D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe" -m binrecon function --profile tools/binrecon/profiles/busmouse.json --list
& "D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe" tools/binrecon/parity_check.py $env:BINRECON_REFERENCE $env:BINRECON_REBUILT
```

`validate` must print `reference ... sha256=A1AAB49F4D9F2BA90B4D7105F3D76BBF054F6D2D150B041D2156FC4F75E71864`. `parity_check.py` must print `missing_strings (0):` and `missing_symbols (0):`. Extra unstripped symbols are not a failure.

For one function:

```powershell
& "D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe" -m binrecon function --profile tools/binrecon/profiles/busmouse.json --name "_GetIRQFromBoard"
```

---

### Task 1: Restore harness and IDA-only profile

**Files:**
- Create or keep: `vm/build-i386-input-recon.sh`
- Modify: `tools/binrecon/profiles/busmouse.json`

No driver source. No guest. Do not run `binrecon analyze`.

- [ ] **Step 1: Restore or extend the harness**

If `vm/build-i386-input-recon.sh` is missing:

```powershell
git checkout d529b15f1^ -- vm/build-i386-input-recon.sh
```

That restores the file as of `1b1b68b93` (includes `drvISASerialPort` and `drvBusMouse`). Do not edit other drivers' arms.

If the file already exists, keep it. Ensure this `case` arm is present (add it if missing, do not delete sibling arms):

```sh
	drvBusMouse)
		build_one BusMouse drvBusMouse BusMouse.drvproj || fail=1
		;;
```

The script must invoke `gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386`, strip CR from Makefiles, stage `${name}_reloc` under `/build/out/i386/$dir/$name.config/`, and end with `exit $fail`. Do not add `set -e`. Rhapsody's `/bin/sh` kills a script if a predicate function returns nonzero under `set -e`.

- [ ] **Step 2: Make the profile IDA-only with a rebuilt key**

Replace `tools/binrecon/profiles/busmouse.json` with:

```json
{
  "schema_version": "profile-v1",
  "name": "drvBusMouse reconstruction (IDA only)",
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
  "output_dir": "../out/busmouse"
}
```

- [ ] **Step 3: Check the files without analyzing**

```powershell
Select-String -Path vm\build-i386-input-recon.sh -Pattern "drvBusMouse" | Select-Object -First 3
python -c "import json; p=json.load(open('tools/binrecon/profiles/busmouse.json')); assert p['analyzers']['ghidra']['enabled'] is False; assert p['analyzers']['angr']['enabled'] is False; assert p['analyzers']['ida']['enabled'] is True; assert 'rebuilt' in p; assert p['output_dir']=='../out/busmouse'; print('profile ok')"
```

Expected: a `drvBusMouse)` arm and `profile ok`.

- [ ] **Step 4: Commit**

```powershell
git add vm/build-i386-input-recon.sh tools/binrecon/profiles/busmouse.json
git commit -m "vm: restore input recon harness and IDA-only busmouse profile"
```

If a sibling already restored the harness and this commit would only change `busmouse.json`, drop `vm/build-i386-input-recon.sh` from `git add` and use `binrecon: make the busmouse profile IDA-only with a rebuilt path`.

---

### Task 2: Baseline guest build and worklist

**Files:**
- Create: `src/drivers-i386/input/drvBusMouse/reconstruction/function-worklist.md`
- Modify: `src/drivers-i386/input/drvBusMouse/reconstruction/divergences.md` (baseline note only)

No `BusMouse.m` edits.

- [ ] **Step 1: Guest-build the current tree**

Run the Guest rebuild block. `$REBUILT` must exist afterwards.

- [ ] **Step 2: Host-measure**

Run the Host measure block. Capture `--list` and `parity_check.py` counts. Record the `_reloc` file size and SHA-256:

```powershell
Get-FileHash -Algorithm SHA256 $env:BINRECON_REBUILT | Format-List
(Get-Item $env:BINRECON_REBUILT).Length
```

Expect `__TEXT,__text` near 1584 and `__TEXT,__const` still absent. The eight regression-gate methods should have `masked_equal`. `missing_strings` 0, `missing_symbols` 0.

- [ ] **Step 3: Write `function-worklist.md`**

Create `src/drivers-i386/input/drvBusMouse/reconstruction/function-worklist.md` with:

- date and rebuilt SHA-256 and byte size
- `parity_check.py` four counts
- the full `binrecon function --list` table
- a reachability note: VERS objects are still absent, so this snapshot is pre-Phase-2

Do not advance any ledger status. Do not set `rebuilt_sha256` yet (this `_reloc` is not kept as the campaign result).

Append a short "Phase 1 baseline" paragraph to `divergences.md` with size, SHA, and the four parity counts.

- [ ] **Step 4: Commit**

```powershell
git add src/drivers-i386/input/drvBusMouse/reconstruction/function-worklist.md src/drivers-i386/input/drvBusMouse/reconstruction/divergences.md
git commit -m "drvBusMouse: record the instruction-stream baseline worklist"
```

---

### Task 3: Wire local `VERS_OFILE`

**Files:**
- Create: `src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj/Makefile.postamble`
- Modify: reconstruction records; do not edit `driverTools` or guest-installed makefiles

Keep even if `__text` extents do not close.

- [ ] **Step 1: Create the Kernel Server postamble**

File contents, entire file, with a trailing newline:

```
OTHER_GENERATED_OFILES += $(VERS_OFILE)
```

`BusMouse.lksproj/Makefile` already has `-include Makefile.postamble` and names `Makefile.postamble` in `OTHERSRCS`. Do not create a Driver-project postamble. The MH_BUNDLE is not a gate.

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
for n in ('_BusMouse_VERS_STRING', '_BusMouse_VERS_NUM'):
    print(n, 'present' if n in names else 'MISSING')
"@
```

Gate: a `__TEXT,__const` section exists and both symbols are present. Do not compare the 160-byte string to Apple's. If symbols are missing, record whether `BusMouse_vers.c` / `.o` were generated and whether they appear on the `kl_ld` line. Do not then edit `driverTools`. Existence stays unmet until a later local makefile fix that is still inside this driver's tree; if none exists, accept the gap in `divergences.md` and continue.

The eight regression-gate methods must still have `masked_equal`. `__text` identity of the three residuals may stay mismatched.

- [ ] **Step 3: Record and commit**

Note in `divergences.md` that the `__TEXT,__const` gap is closed (or accepted with guest evidence). Refresh the worklist.

```powershell
git add src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj/Makefile.postamble src/drivers-i386/input/drvBusMouse/reconstruction
git commit -m "drvBusMouse: emit vers_string objects from the Kernel Server postamble"
```

---

### Task 4: Cheapest-first grinding

**Files:**
- Modify: `src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj/BusMouse.m` only, one experiment per rebuild
- Modify: reconstruction records after each kept rebuild

Do not start until Task 3 is committed. Glue methods stay generated. Do not edit `BusMouse.h`.

**Cycle (repeat until the done bar in Step 4):**

1. Run `--list`. Ignore the two `+[...]` glue rows. Ignore any row with `raw_equal` or `masked_equal`.
2. Take the cheapest remaining hand-written row.
3. If that row is `-[BusMouse setIntValues:forParameter:count:]` and `--name` differs only by gcc hoist/spill of `parameterArray` / compare count (ours smaller, no missing call, no wrong offset): accept. Write the `--name` dump into `divergences.md` with disposition accept. Ledger: `intentional-mismatch`, reason naming gcc spill, reviewer `Pat Raynor`. Next row.
4. If the cheapest leftover is register allocation or instruction scheduling (same calls, same constants, same offsets, different register or `cmp` operand order): accept the same way. Do not add dummy locals or reorder statements.
5. Otherwise run **one** experiment from the list below that matches the `--name` dump. Guest rebuild + Host measure.
   - Match (`raw_equal` or `masked_equal`): keep, ledger `assembly-matched`, next function.
   - Miss, no regression: revert the experiment, mark tried in `divergences.md`, next list item.
   - Regression of a gate method: revert, record failed-with-regression, next list item.
6. Empty list and still not matching: accept as unreachable with the dump.

**Starter lists** (rewrite from the current `--list` if ranking differs):

#### `_GetIRQFromBoard` (addr 0)

Do not change the port (`0x23E`), the `0xF000` count, or the 5/4/3/2/0 ladder. One item per rebuild.

**Experiment 1 — drop `lowBits`, inline the mask.** Replace the ladder:

```objc
    lowBits = changed & 0x0f;

    if (changed & 1) {
	irq = 5;
    } else if (lowBits & 2) {
	irq = 4;
    } else if (lowBits & 4) {
	irq = 3;
    } else {
	irq = 0;
	if (lowBits & 8) {
	    irq = 2;
	}
    }
```

with:

```objc
    if (changed & 1) {
	irq = 5;
    } else if ((changed & 0x0f) & 2) {
	irq = 4;
    } else if ((changed & 0x0f) & 4) {
	irq = 3;
    } else {
	irq = 0;
	if ((changed & 0x0f) & 8) {
	    irq = 2;
	}
    }
```

and delete the `unsigned char lowBits;` declaration.

**Experiment 2 — use `lowBits` for bit 0 too.** Keep `lowBits = changed & 0x0f;` and change only `if (changed & 1)` to `if (lowBits & 1)`.

**Experiment 3 — `unsigned int lowBits`.** Change the declaration from `unsigned char lowBits;` to `unsigned int lowBits;`. Leave the ladder as in current source. Task 12 tried this under capstone; retry under IDA.

**Experiment 4 — flatten the IRQ-2 case.** Replace the nested else with:

```objc
    if (changed & 1) {
	irq = 5;
    } else if (lowBits & 2) {
	irq = 4;
    } else if (lowBits & 4) {
	irq = 3;
    } else if (lowBits & 8) {
	irq = 2;
    } else {
	irq = 0;
    }
```

#### `_MouseIntHandler` (addr 244)

Do not reorder the ten port accesses, the doubled `outb(0x23e, 0x80)`, or the busy-accumulate vs post-and-clear split.

Current decode:

```objc
    left = ((unsigned int)(buttonByte >> 7)) ^ 1;
    right = ~((unsigned int)(buttonByte >> 5)) & 1;
```

**Experiment 1 — widen left before xor:**

```objc
    left = (unsigned int)(buttonByte >> 7);
    left ^= 1;
    right = ~((unsigned int)(buttonByte >> 5)) & 1;
```

**Experiment 2 — stage right through a byte temporary:**

```objc
    left = ((unsigned int)(buttonByte >> 7)) ^ 1;
    {
	unsigned char temp;

	temp = buttonByte >> 5;
	right = ~((unsigned int)temp) & 1;
    }
```

(If a nested block is ugly in this file, declare `unsigned char temp;` with the other locals at the top of the function instead.)

**Experiment 3 — xor-form right:**

```objc
    left = ((unsigned int)(buttonByte >> 7)) ^ 1;
    right = ((buttonByte >> 5) & 1) ^ 1;
```

#### `-[BusMouse setIntValues:forParameter:count:]` (addr 1420)

If `--name` after Task 3 shows only the hoist/spill, treat this list as empty and accept. Do not add dummy spills to chase 148.

**Experiment 1 — no locals.** Replace the body of the two match branches so there are no `resolutionValue` / `invertedValue` locals:

```objc
    if (strcmp(parameterName, RESOLUTION) == 0) {
	resolution = *parameterArray;
	[target setResolution:[self getResolution]];
    } else if (strcmp(parameterName, INVERTED) == 0) {
	inverted = *(char *)parameterArray;
	[target setInverted:(int)inverted];
    } else {
	return IO_R_UNSUPPORTED;
    }

    return IO_R_SUCCESS;
```

and delete the two local declarations. The unguarded `target` send stays. Do not add a `target != nil` test.

**Experiment 2 — swap declaration order** of `resolutionValue` and `invertedValue` if `--name` shows reversed stack slots. Leave the rest of the method as in current source.

#### Regression only

`validConfiguration:`, `interruptHandler`, `_BusMouseThread`, `mouseInit:`, `free`, `getHandler:…`, `getResolution`, `getIntValues:…`. No experiments.

- [ ] **Step 1: Grind until every hand-written function is matched or accepted**

- [ ] **Step 2: Refresh worklist, ledger, source-map, divergences after the last kept rebuild**

- [ ] **Step 3: Confirm glue is still only the two generated methods**

`--list` may still show `+[BusMouseKernelServerInstance kernelServerInstance]` and `+[BusMouseVersion driverKitVersionForBusMouse]` unmatched. That is required. Do not hand-write them.

- [ ] **Step 4: Done-bar check for this task**

Every paired hand-written function is `raw_equal` / `masked_equal` or recorded unreachable. `missing_strings` 0, `missing_symbols` 0.

Commit after each **kept** rebuild (`drvBusMouse: `). Reverted experiments are not committed.

---

### Task 5: Final records

**Files:**
- Modify: `src/drivers-i386/input/drvBusMouse/reconstruction/ledger.json` (`rebuilt_sha256`)
- Modify: `src/drivers-i386/README`
- Modify: `divergences.md` / `function-worklist.md` closing summary

- [ ] **Step 1: Set `rebuilt_sha256`**

In `ledger.json`, set `rebuilt_sha256` to the SHA-256 of the last kept `$REBUILT` (uppercase hex, no `0x`). Keep `reference_sha256` as `A1AAB49F4D9F2BA90B4D7105F3D76BBF054F6D2D150B041D2156FC4F75E71864`.

Validate:

```powershell
$env:PYTHONPATH = "tools/binrecon"
$env:BINRECON_REFERENCE = "C:\Users\raynorpat\Downloads\test\Drivers\i386\BusMouse.config\BusMouse_reloc"
$env:BINRECON_REBUILT = (Resolve-Path "out\i386\drvBusMouse\BusMouse.config\BusMouse_reloc").Path
& "D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe" -m binrecon ledger --profile tools/binrecon/profiles/busmouse.json --ledger src/drivers-i386/input/drvBusMouse/reconstruction/ledger.json
```

Expected: exit 0.

- [ ] **Step 2: Update the README line**

Replace:

```
 * drvBusMouse - compiles; reconstructed against the reference binary, fixes applied, not yet tested
```

with a line that names the new `masked_equal` / `assembly-matched` counts, that `_BusMouse_VERS_STRING` / `_VERS_NUM` exist, and that the driver is still untested on hardware. Example shape (fill in the real counts from `--list`):

```
 * drvBusMouse - compiles; N/11 hand-written functions masked-equal to BusMouse_reloc, version objects emitted; not yet tested on hardware
```

- [ ] **Step 3: Closing paragraph in `divergences.md` and `function-worklist.md`**

State which functions matched, which were accepted and why, and the last rebuilt SHA.

- [ ] **Step 4: Commit**

```powershell
git add src/drivers-i386/README src/drivers-i386/input/drvBusMouse/reconstruction
git commit -m "drvBusMouse: record instruction-stream finish counts and rebuilt hash"
```

---

## Spec coverage (self-review)

| Spec requirement | Task |
|---|---|
| Restore / keep harness, only run `drvBusMouse` | 1 |
| IDA-only profile + `rebuilt` key | 1 |
| Baseline guest `_reloc` + worklist | 2 |
| Kernel Server `VERS_OFILE`, symbols exist, no string match, no `driverTools` | 3 |
| Cheapest-first, experiment lists, accept gcc spill | 4 |
| Regression gate on eight methods | 2–4 |
| `rebuilt_sha256`, README, no QEMU | 5 |
| No `BusMouse.h`, no `kernel-7`, no other drivers | global |
| Findings 1–19 not reopened | global |
| Glue stays generated | Task 4 Step 3 |
| Dummy spills forbidden | Task 4 |
