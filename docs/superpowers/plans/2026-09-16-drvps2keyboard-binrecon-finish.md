# drvPS2Keyboard binrecon finish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drive `drvPS2Keyboard` to function-level `raw_equal` / `masked_equal` (or recorded compiler-shaped accepts) against Apple's `PS2Keyboard_reloc`, with a guest rebuild of the current tree.

**Architecture:** Task 8 already matched layout, protocols, strings, and symbols. This campaign restores a PS2Keyboard guest harness, baselines the current `_reloc` under IDA, then cheapest-first source-shape edits across both translation units. Name-paired `masked_equal` in `compare.py` is reused as-is. No QEMU.

**Tech Stack:** Objective-C DriverKit on a Rhapsody PPC guest (`gnumake RC_ARCHS=i386`), OpenSSH via `vm/rhap-remote.ps1`, IDA 9.2 through `tools/binrecon`, Python `./.venv-binrecon/Scripts/python.exe` with `PYTHONPATH=tools/binrecon`.

**Spec:** [2026-09-16-drvps2keyboard-binrecon-finish-design.md](../specs/2026-09-16-drvps2keyboard-binrecon-finish-design.md)

## File map

| File | Responsibility |
|---|---|
| `vm/build-i386-input-recon.sh` | Guest harness. Create or add a `drvPS2Keyboard` arm. |
| `tools/binrecon/profiles/ps2keyboard.json` | Add `rebuilt.path` `${BINRECON_REBUILT}` so `function --list` can load both analyses. Leave IDA+angr / Ghidra-off as they are. |
| `PS2Controller.m` / `PS2Keyboard.m` | Instruction-shape edits only (Task 4). |
| `PS2Controller.h` / `PS2Keyboard.h` | Touch only if a typed rewrite is required for instruction shape. No layout changes. |
| `reconstruction/function-worklist.md` | Baseline after Task 2; refreshed at close. |
| `reconstruction/divergences.md` | Accepts and experiment outcomes. Task 8 resolutions stay. |
| `reconstruction/ledger.json` | Status of record. |
| `reconstruction/source-map.json` | Relined when bodies move. 47 mapped / 2 unmapped. |
| `src/drivers-i386/README` | New counts; still "not yet tested." |

## Global constraints

- **This session runs every guest rebuild.** Sync only `drivers-i386/input/drvPS2Keyboard`. Never `sync-src.ps1 -All`.
- **Do not invent instruction diffs.** Every source edit comes from `binrecon function --name` of a named function. If the dump is not in hand, stop.
- **Do not grind envelope size.** `__TEXT,__text` 4652 vs 4952 is expected.
- **Do not touch:** `Default.table`, `Load_Commands.sect`, `Unload_Commands.sect`, Makefiles, `dpkg/`, `src/kernel-7`, sibling input drivers, `compare.py`, `kernel-drivers-blacklist.json`, `driverTools`, Ghidra, `normalize.py`.
- **Commit messages:** `drvPS2Keyboard: ` for driver/reconstruction; `drivers-i386: ` for harness and README. One to two lines. No trailers. Stage by explicit path. Never `git add -A`. Never commit `_reloc` files or `tools/binrecon/out/`.
- **Python:** `$env:PYTHONPATH = "tools/binrecon"` then `.\.venv-binrecon\Scripts\python.exe`.
- **Reference SHA** must stay `AB413CA3919950F22A1F5D10B0BF1167387FEF320C9FB82A3EA66E586A6BE02A`. Wrong binary → stop.
- **Eight Task 8 matches are a regression gate.** Do not rewrite their bodies: `-[PS2Controller getHandler:level:argument:forInterrupt:]` (1388), `-[PS2Controller setLEDs:]` (1472), `_clearOutputBuffer` (1960), `+[PS2Keyboard deviceStyle]` (2404), `-[PS2Keyboard interfaceId]` (4340), `-[PS2Keyboard handlerId]` (4356), `-[PS2Keyboard setAlphaLockFeedback:]` (4372), `-[PS2Keyboard relinquishOwnership:]` (4632).

## Paths and env

Set in every host shell that runs binrecon (worktree root = `<repo>`):

```powershell
$env:PYTHONPATH = "tools/binrecon"
$env:BINRECON_REFERENCE = "C:\Users\raynorpat\Downloads\test\Drivers\i386\PS2Keyboard.config\PS2Keyboard_reloc"
$env:BINRECON_REBUILT = "<repo>\out\i386\drvPS2Keyboard\PS2Keyboard.config\PS2Keyboard_reloc"
$py = ".\.venv-binrecon\Scripts\python.exe"
$prof = "tools/binrecon/profiles/ps2keyboard.json"
```

Guest source: `/build/source/src/drivers-i386/input/drvPS2Keyboard/`
Guest stage: `/build/out/i386/drvPS2Keyboard/PS2Keyboard.config/`
Guest harness: `/build/source/vm/build-i386-input-recon.sh`

`normalized-functions=FAIL` is expected until the campaign closes. A reference-only analyze may exit 1; the gate is `complete: true`.

## Guest rebuild procedure

Use this exact sequence after the harness exists. Do not use PuTTY `pscp`/`plink`.

**Upload harness** (once per host copy of the script, and again if you edit it):

```powershell
. .\vm\rhap-remote.ps1
$cfg = Get-RhapVmConfig
$ssh = Resolve-RhapTool -NameOrPath $cfg.Ssh
$lf = ([IO.File]::ReadAllText((Resolve-Path .\vm\build-i386-input-recon.sh)) -replace "`r`n","`n") -replace "`r","`n"
$body = "mkdir -p /build/source/vm`ncat > /build/source/vm/build-i386-input-recon.sh << 'ENDHARNESS'`n$lf`nENDHARNESS`nchmod +x /build/source/vm/build-i386-input-recon.sh`n"
Invoke-RhapSshScript -Cfg $cfg -Ssh $ssh -ScriptBody $body -Stream
```

**Sync + build:**

```powershell
powershell -NoProfile -File vm\sync-src.ps1 -Path drivers-i386/input/drvPS2Keyboard
. .\vm\rhap-remote.ps1
$cfg = Get-RhapVmConfig
$ssh = Resolve-RhapTool -NameOrPath $cfg.Ssh
Invoke-RhapSshScript -Cfg $cfg -Ssh $ssh -ScriptBody "sh /build/source/vm/build-i386-input-recon.sh drvPS2Keyboard" -Stream
```

Expected: a line `=== input-recon done fail=0 built: drvPS2Keyboard ===` and a staged `PS2Keyboard_reloc`.

**Copy `_reloc` back** (binary-safe via `cmd.exe` so PowerShell 5 does not corrupt the pipe). Create the host directory first. Use the worktree `<repo>`:

```bat
cmd /c "mkdir <repo>\out\i386\drvPS2Keyboard\PS2Keyboard.config 2>nul & ssh -o KexAlgorithms=diffie-hellman-group1-sha1 -o HostKeyAlgorithms=ssh-dss -o Ciphers=3des-cbc -o MACs=hmac-sha1 -o PubkeyAuthentication=no -o StrictHostKeyChecking=no root@HOST tar cf - -C /build/out/i386/drvPS2Keyboard/PS2Keyboard.config PS2Keyboard_reloc | tar xf - -C <repo>\out\i386\drvPS2Keyboard\PS2Keyboard.config"
```

`HOST` and password come from `vm/vm.conf`. Prefer wrapping that `ssh` with `Invoke-RhapSshAskPass` if the interactive password prompt fails; the file on disk after copy must be a Mach-O, not an SSH error string.

**After every successful copy:**

```powershell
& $py tools\binrecon\parity_check.py $env:BINRECON_REFERENCE $env:BINRECON_REBUILT
```

Expected: exit 0, `missing_strings (0):`, `missing_symbols (0):`. Then IDA-analyze the rebuilt (and the reference only if published output is missing or SHA differs):

```powershell
& $py -m binrecon analyze --profile $prof
```

Then:

```powershell
& $py -m binrecon function --profile $prof --list
```

`--name` for one function:

```powershell
& $py -m binrecon function --profile $prof --name "_clearOutputBuffer"
```

Use the symbol name as it appears in `--list`.

If the guest is unreachable, stop. Do not invent instruction-stream results.

---

### Task 1: Guest harness and rebuilt profile path

**Files:**
- Create or modify: `vm/build-i386-input-recon.sh`
- Modify: `tools/binrecon/profiles/ps2keyboard.json`

No driver source. No guest build in this task.

- [ ] **Step 1: Check whether the harness already exists**

If `vm/build-i386-input-recon.sh` is already in the worktree with another driver's arm (for example `drvISASerialPort`), keep that arm and add `drvPS2Keyboard`. Do not delete sibling arms. Do not restore a five-driver dispatcher. If the file is absent, create it with only `drvPS2Keyboard`.

- [ ] **Step 2: Write the harness**

POSIX Bourne only. No `local`. No bashisms. Do not use `set -e` on predicates (Rhapsody `/bin/sh` applies `set -e` inside `if`). Prefer no `set -e` at all. CR-strip Makefiles. `gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386`. Gate on `_reloc` presence, not `gnumake`'s exit code. Stage under `/build/out/i386/drvPS2Keyboard/PS2Keyboard.config/`.

If creating the file from scratch, this is the whole script:

```sh
#!/bin/sh
# Build one i386 input driver under reconstruction and stage its _reloc.
# Usage: sh vm/build-i386-input-recon.sh drvPS2Keyboard
#
# Gating is on artifact presence, not gnumake's exit code. A recursive
# pb_makefiles build can return nonzero for a step outside what we need.
# Keep this POSIX sh — Rhapsody's /bin/sh is a 1999 Bourne shell.

DRV="$1"
NAME=""
PROJ=""
case "$DRV" in
drvPS2Keyboard)
	NAME=PS2Keyboard
	PROJ=PS2Keyboard.drvproj
	;;
*)
	echo "usage: $0 drvPS2Keyboard" >&2
	exit 2
	;;
esac

ROOT="${SRCROOT:-/build/source}"
SRC="$ROOT/src/drivers-i386/input/$DRV"
STAGE="$ROOT/out/i386/$DRV/${NAME}.config"

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

If the file already exists, add the `drvPS2Keyboard)` arm with `NAME=PS2Keyboard` and `PROJ=PS2Keyboard.drvproj` and stage that arm to `$ROOT/out/i386/$DRV/${NAME}.config`. Keep existing arms and their stage paths. Do not change another driver's `NAME`/`PROJ`.

LF line endings. No CRLF.

- [ ] **Step 3: Add rebuilt path to the profile**

In `tools/binrecon/profiles/ps2keyboard.json`, after the `reference` object, add:

```json
  "rebuilt": {
    "path": "${BINRECON_REBUILT}"
  },
```

Do not change analyzer flags. Ghidra stays `enabled: false`. angr stays `enabled: true`. `output_dir` stays `../out/ps2keyboard`.

- [ ] **Step 4: Syntax-check the harness on the host**

Git Bash or WSL:

```bash
sh -n vm/build-i386-input-recon.sh && echo "syntax OK"
```

Expected: `syntax OK`. If you have no Unix `sh` on Windows, skip this step and rely on the guest `sh` in Task 2; note that in the commit message body? No — do not add a body. Note it in the Task 2 report instead.

- [ ] **Step 5: Commit**

```powershell
git add vm/build-i386-input-recon.sh tools/binrecon/profiles/ps2keyboard.json
git commit -m "drivers-i386: add PS2Keyboard guest harness and rebuilt profile path"
```

---

### Task 2: Phase 1 baseline on the guest

**Files:**
- Create: `src/drivers-i386/input/drvPS2Keyboard/reconstruction/function-worklist.md`
- Depends on: Task 1 harness in the worktree

No driver source edits.

- [ ] **Step 1: Confirm the reference binary**

```powershell
Get-FileHash -Algorithm SHA256 $env:BINRECON_REFERENCE
```

Expected: `AB413CA3919950F22A1F5D10B0BF1167387FEF320C9FB82A3EA66E586A6BE02A`. If it differs, **BLOCKED**.

- [ ] **Step 2: Run the Guest rebuild procedure**

Upload harness, sync, build, copy `_reloc` back, `parity_check.py`.

Expected: `missing_strings (0):` and `missing_symbols (0):`. If the build fails, **BLOCKED** — Task 8 already compiled this tree; report the log and fix only what it names. Do not start function edits.

Record the rebuilt file size and SHA-256.

- [ ] **Step 3: Validate the profile**

```powershell
& $py -m binrecon validate --profile $prof
```

Expected: a `reference` line with `sha256=AB413CA3…` and a `rebuilt` line with the SHA from Step 2.

- [ ] **Step 4: Analyze**

If `tools/binrecon/out/ps2keyboard/published/` already has `complete: true` reference output whose SHA is `AB413CA3…`, reuse it. Always IDA-analyze the new rebuilt `_reloc` (`binrecon analyze` with both env vars set). Do not hand-edit published JSON. Do not re-enable Ghidra.

Expected: `complete: true`. `normalized-functions=FAIL` is OK. Exit code 1 is OK if `complete: true`.

- [ ] **Step 5: Write the worklist**

```powershell
& $py -m binrecon function --profile $prof --list
```

Create `src/drivers-i386/input/drvPS2Keyboard/reconstruction/function-worklist.md` with:

- Date and worktree branch
- Reference SHA-256 and size
- Rebuilt SHA-256 and size
- `__TEXT,__text` sizes (reference 4952; rebuilt measured)
- `parity_check.py` missing counts (must be 0 / 0)
- `instance_size` for `PS2Controller` (must stay 308) and `PS2Keyboard` (must stay 548), read from `__OBJC` via `binrecon.macho.read_macho` or `otool`-equivalent on the host
- Full `--list` pasted or summarized: identical / masked-eq counts, cheapest remaining rows
- Reachability: which cheapest rows look source-shaped vs already compiler-shaped (register allocation / instruction scheduling)

Dump `instance_size` with:

```powershell
& $py -c @"
from binrecon.macho import read_macho
from pathlib import Path
import os
m = read_macho(Path(os.environ['BINRECON_REBUILT']))
for s in m.get('objc_classes', m.get('classes', [])):
    print(s)
"@
```

If that helper is not on the macho document, read `__OBJC,__class` the way Task 8's `divergences.md` did (class name + `instance_size`). Do not guess. If instance sizes are not 308 / 548, **BLOCKED** — that is a Task 8 regression.

- [ ] **Step 6: Commit**

```powershell
git add src/drivers-i386/input/drvPS2Keyboard/reconstruction/function-worklist.md
git commit -m "drvPS2Keyboard: record instruction-stream baseline worklist"
```

Never stage `out/` or `tools/binrecon/out/`.

---

### Task 3: Advance already-identical functions in the ledger

**Files:**
- Modify: `src/drivers-i386/input/drvPS2Keyboard/reconstruction/ledger.json`
- Modify: `src/drivers-i386/input/drvPS2Keyboard/reconstruction/divergences.md` (short note only)
- Depends on: Task 2 `--list`

No driver source. No rebuild.

- [ ] **Step 1: Read the worklist**

Every `--list` row that is identical or `masked_equal` (`raw_equal` or `masked_equal` true), except the two glue methods, becomes `assembly-matched` if it is not already.

The two glue methods stay `intentional-mismatch`:

- `+[PS2KeyboardKernelServerInstance kernelServerInstance]`
- `+[PS2KeyboardVersion driverKitVersionForPS2Keyboard]`

- [ ] **Step 2: Transition the ledger**

Use `binrecon ledger` with `$env:BINRECON_REBUILT` set so `rebuilt_sha256` updates, or edit `ledger.json` with the same vocabulary. Forward-only: `control-flow-confirmed` → `assembly-matched`. Do not skip down to `unexamined`. Do not mark compiler-shaped leftovers `assembly-matched`.

Reviewer: `Pat Raynor` (match existing ledger entries).

- [ ] **Step 3: Note the baseline identical set in divergences.md**

Append a short "Finish campaign" heading: date, rebuilt SHA, how many rows were already `masked_equal` / `raw_equal` at baseline. Do not delete Task 8 findings.

- [ ] **Step 4: Commit**

```powershell
git add src/drivers-i386/input/drvPS2Keyboard/reconstruction/ledger.json src/drivers-i386/input/drvPS2Keyboard/reconstruction/divergences.md
git commit -m "drvPS2Keyboard: mark baseline-identical functions assembly-matched"
```

---

### Task 4: Cheapest-first instruction-shape grind

**Files:**
- Modify: `src/drivers-i386/input/drvPS2Keyboard/PS2Keyboard.drvproj/PS2Keyboard.lksproj/PS2Controller.m`
- Modify: `src/drivers-i386/input/drvPS2Keyboard/PS2Keyboard.drvproj/PS2Keyboard.lksproj/PS2Keyboard.m`
- Modify headers in that directory only if a typed rewrite is required
- Modify: `reconstruction/function-worklist.md`, `divergences.md`, `ledger.json`, `source-map.json` (line numbers if bodies move)
- Depends on: Tasks 2–3

- [ ] **Step 1: Write named experiment lists into the worklist**

Before the first source edit, append to `function-worklist.md` a short list per remaining non-equal paired function, cheapest `differing` first. One experiment idea per function to start; add more only after a miss.

Allowed: statement order, local vs expression, signedness of *locals*, loop shape, `if` vs `else if`, operand-reversed `cmp`, declaration order of existing locals.

Forbidden: padding ivars; changing instance layout; renaming ivars or protocols; restoring `NXLock`; putting queue state back into ivars; inventing temporaries whose only purpose is to pick a register after the list is empty; repeating a reverted experiment; chasing `__text` size; rewriting the eight Task 8 matches.

Compiler-shaped means the `--name` columns differ only by register choice, instruction scheduling, or equivalent gcc 2.x shape — not a wrong constant, missing call, inverted branch, or wrong offset.

- [ ] **Step 2: Loop until every remaining paired function is equal or accepted**

For each cheapest still-open source-shaped row:

1. `--name` the current function. Keep the dump.
2. Apply one experiment in the owning `.m` file.
3. Run the Guest rebuild procedure. `parity_check.py` must stay 0 / 0.
4. Fresh analyze of the rebuilt. `--name` on the **new** published comparison. `--list` to confirm previously identical rows (including Task 3 and the eight Task 8 matches) did not regress.
5. Match (`raw_equal` or `masked_equal`) → keep the edit, ledger `assembly-matched`, record outcome in `divergences.md`, commit `drvPS2Keyboard: ` describing the behaviour.
6. Miss, no regression → revert the experiment, mark tried in the worklist, try the next item on that function's list.
7. Regression of a closed function → revert, record, continue.
8. Empty list, still not equal → accept: paste `--name` dump under `divergences.md`, ledger `intentional-mismatch` with reason `compiler-shaped leftover after exhausted source-shape list` and reviewer `Pat Raynor`. Do not grind further.

One shared cause is one edit cluster (one commit). Relined `source-map.json` when bodies move; keep 47 mapped / 2 unmapped.

If `--list` grows unpaired functions other than the two glue methods, stop grinding. That is a layout or linkage finding.

If `__text` stays ~300 bytes short after all accepts, record the sizes. Not a failure.

- [ ] **Step 3: Stop condition**

`--list`: unpaired only the two glue methods. Every other hand-written row is identical, `masked_equal`, or accepted. Ledger has no `unexamined` hand-written function.

---

### Task 5: Campaign close

**Files:**
- Modify: `reconstruction/function-worklist.md`
- Modify: `reconstruction/ledger.json` (`rebuilt_sha256` = last kept `_reloc`)
- Modify: `src/drivers-i386/README` drvPS2Keyboard line
- Depends on: Task 4 stop condition

No further source-shape edits.

- [ ] **Step 1: Refresh the worklist summary**

Final SHA-256s, `--list` counts (identical / masked-eq / accepted / unpaired glue), `__text` sizes, statement that hardware testing is still out.

- [ ] **Step 2: Update README**

Change only the drvPS2Keyboard bullet. Keep "not yet tested." Name the new counts. Do not write `complete`. Example shape (fill in the real numbers from `--list`):

```
 * drvPS2Keyboard - compiles; reconstructed against the reference binary, N/47 hand-written functions byte-identical under relocation masking, remainder accepted as compiler-shaped; not yet tested
```

- [ ] **Step 3: Set ledger `rebuilt_sha256`**

Must equal the SHA of the last kept `PS2Keyboard_reloc`.

- [ ] **Step 4: Commit**

```powershell
git add src/drivers-i386/input/drvPS2Keyboard/reconstruction/function-worklist.md src/drivers-i386/input/drvPS2Keyboard/reconstruction/ledger.json src/drivers-i386/README
git commit -m "drivers-i386: record drvPS2Keyboard instruction-stream finish"
```

---

## Spec coverage

| Spec section | Task |
|---|---|
| Phase 0 harness, PS2Keyboard arm, no five-driver dispatcher | 1 |
| Profile IDA on rebuilt (`rebuilt.path`) | 1 |
| Phase 1 baseline, parity 0/0, worklist, instance sizes | 2 |
| Already-identical rows → `assembly-matched` | 3 |
| Cheapest-first grind, allowed/forbidden, accepts | 4 |
| Close, README, `rebuilt_sha256` | 5 |
| Guest SSH, no pscp, no `-All` | Guest rebuild procedure |
| Glue unpaired, no VERS_STRING chase, no QEMU, no kernel-7 | Tasks 3–5 constraints |
