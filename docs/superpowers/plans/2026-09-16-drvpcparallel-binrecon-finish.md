# drvPCParallel binrecon finish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drive `drvPCParallel` to function-level `raw_equal` / `masked_equal` against Apple's `ParallelPort_reloc`, emit local `VERS_OFILE` symbols, reconstruct `RemovePPDev` and `InstallPPDev`, and guest-build all three artifacts.

**Architecture:** Sequential measured close. Restore the guest harness and `TOOLS`, baseline the current tree, wire `VERS_OFILE`, reverse Finding 53 and the `_strobeChar` order, then cheapest-first grinding of the eighteen `control-flow-confirmed` functions. After the reloc meets the done bar, decide `InstallPPDev`'s `IODeviceMaster` from the reference nlist and reconstruct both user-space tools. The fifty Task 10 `assembly-matched` functions are a regression gate. `physbuf` encoding is a noted non-closer. No QEMU.

**Tech Stack:** Python in `.venv-binrecon`, `tools/binrecon` (IDA 9.2; Ghidra off), Rhapsody guest `gnumake` / `pb_makefiles` / `tool.make`, `vm/sync-src.ps1` + `vm/build-i386-input-recon.sh`.

**Spec:** [2026-09-16-drvpcparallel-binrecon-finish-design.md](../specs/2026-09-16-drvpcparallel-binrecon-finish-design.md)

## File map

| File | Responsibility |
|---|---|
| `vm/build-i386-input-recon.sh` | Guest harness. Restore if missing; keep a sibling copy and add `drvPCParallel` otherwise. Builds `.lksproj` first (reloc gate), then attempts `.drvproj` for tools. Stages `_reloc` plus tools. |
| `tools/binrecon/profiles/parallelport.json` | Add `rebuilt` path. IDA on, Ghidra off, angr stays on for the reference. |
| `tools/binrecon/profiles/installppdev.json` | Phase 3. IDA-only. |
| `tools/binrecon/profiles/removeppdev.json` | Phase 3. IDA-only. |
| `PCParallelPort.drvproj/Makefile` | Restore `TOOLS = PCParallelPort.lksproj PostLoad.tproj PreLoad.tproj`. |
| `PCParallelPort.lksproj/Makefile.postamble` | Created. One line: `OTHER_GENERATED_OFILES += $(VERS_OFILE)`. |
| `IOParallelPort.m` | Finding 53 (`initDevice`, `probeForController`) and reloc shape edits. |
| `IOParallelPortKern.m` | `_strobeChar` load-then-test and remaining C entry-point shape edits. |
| `PreLoad.tproj/*` | `InstallPPDev`. Phase 3: PB `tool.make`; drop or replace invented `IODeviceMaster.m`. |
| `PostLoad.tproj/*` | `RemovePPDev`. Phase 3: PB `tool.make`. |
| `reconstruction/function-worklist.md` | Baseline and per-phase `--list` snapshots. |
| `reconstruction/divergences.md` | Finding 53 / `_strobeChar` reversals, VERS close, tool findings, accepts. |
| `reconstruction/ledger.json` | Reloc status; `rebuilt_sha256` of last kept `_reloc`. |
| `reconstruction/source-map.json` | Reloc line numbers. 73 mapped / 2 unmapped. |
| `reconstruction/installppdev-ledger.json` | Tool status of record. |
| `reconstruction/removeppdev-ledger.json` | Tool status of record. |
| `reconstruction/installppdev-source-map.json` | Tool function → file/line. |
| `reconstruction/removeppdev-source-map.json` | Tool function → file/line. |
| `src/drivers-i386/README` | Final status line. |

Do not touch `Default.table`, `Load_Commands.sect`, `src/kernel-7`, sibling drivers, `compare.py`, `kernel-drivers-blacklist.json`, `driverTools`, guest-installed `kernelserver.make`. Do not re-enable Ghidra. Do not swap `RemovePPDev` / `InstallPPDev` across tproj folders (`PostLoad.tproj` builds `RemovePPDev`; `PreLoad.tproj` builds `InstallPPDev`). Do not function-compare the `ParallelPort` MH_BUNDLE wrapper.

## Global constraints

```text
VENVPY=D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe
REF=C:/Users/raynorpat/Downloads/test/Drivers/i386/ParallelPort.config/ParallelPort_reloc
REF_INSTALL=C:/Users/raynorpat/Downloads/test/Drivers/i386/ParallelPort.config/InstallPPDev
REF_REMOVE=C:/Users/raynorpat/Downloads/test/Drivers/i386/ParallelPort.config/RemovePPDev
REFSHA=D188A4D909005683B0C943C84CD99514C14A84AD1D378425B3B1DB343F1EAAA2
DRV=src/drivers-i386/input/drvPCParallel
LKS=src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PCParallelPort.lksproj
RECON=src/drivers-i386/input/drvPCParallel/reconstruction
PROFILE=tools/binrecon/profiles/parallelport.json
REBUILT=out/i386/drvPCParallel/ParallelPort.config/ParallelPort_reloc
```

Work in a dedicated worktree, not the main checkout. `.worktrees/` is gitignored.

```powershell
git worktree add .worktrees/drvpcparallel-finish -b drvpcparallel-binrecon-finish HEAD
```

Set `REPO` to that worktree and run every command from there. `VENVPY` stays the main-repo venv unless the worktree has its own.

- **Never commit** `$REF`, `$REF_INSTALL`, `$REF_REMOVE`, `tools/binrecon/out/`, `out/i386/`, a rebuilt `_reloc`, or rebuilt tools.
- **`BINRECON_REFERENCE` and `BINRECON_REBUILT` must be exported** in every shell that runs `binrecon` after Task 4's first `_reloc` exists. Until that file exists, do not run `binrecon validate` / `analyze` / `function` on the reloc.
- **Python is `$VENVPY`.** `PYTHONPATH=tools/binrecon`.
- **Commits:** `drvPCParallel: `, `drivers-i386: `, or `docs: ` prefix, one to two lines, no metadata, no trailers.
- **Reviewer:** `Pat Raynor`.
- **Guest sync:** `powershell -File vm\sync-src.ps1 -Path drivers-i386/input/drvPCParallel`. Never `-All`. `sync-src.ps1` cannot upload `vm/`; copy the harness separately.
- **Guest unreachable:** stop, record it in `divergences.md`, do not invent byte diffs.
- **Diagnosed reloc edits stay** even if extents do not close: `VERS_OFILE` line, Finding 53 uninitialized local, `_strobeChar` load-then-test. Experiments revert on miss.
- **Regression gate:** every Task 10 `assembly-matched` function (50 of them). If any lose `masked_equal`, revert.
- **`physbuf` / `setPhysbuf:` encoding** (`^vi[3l]` vs `^vllll`) is not a closer. Do not edit `buf.h`. Do not grind those two accessors.
- **IDA extents are the comparison extents.** Do not use symbol-gap sizes.
- **Do not invent instruction diffs.** Every source-shape edit after Task 6 comes from `binrecon function --name`. If the dump is not in hand, stop.

### Guest rebuild (copy this block)

Use this exact sequence after the harness exists. Do not use PuTTY `pscp`/`plink`. The guest root shell is `tcsh` and `/bin/sh` is 1999 Bourne: no `2>&1` inside the remote command string.

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
powershell -NoProfile -File vm\sync-src.ps1 -Path drivers-i386/input/drvPCParallel
. .\vm\rhap-remote.ps1
$cfg = Get-RhapVmConfig
$ssh = Resolve-RhapTool -NameOrPath $cfg.Ssh
Invoke-RhapSshScript -Cfg $cfg -Ssh $ssh -ScriptBody "sh /build/source/vm/build-i386-input-recon.sh drvPCParallel" -Stream
```

Expected: a line `=== input-recon done fail=0 built: drvPCParallel ===` and a staged `ParallelPort_reloc`. Tools may be missing on the first baseline; that is recorded, not a reloc failure.

**Copy artifacts back** (binary-safe via `cmd.exe` so PowerShell 5 does not corrupt the pipe). Create the host directory first. Use the worktree `<repo>`:

```bat
cmd /c "mkdir <repo>\out\i386\drvPCParallel\ParallelPort.config 2>nul & ssh -o KexAlgorithms=diffie-hellman-group1-sha1 -o HostKeyAlgorithms=ssh-dss -o Ciphers=3des-cbc -o MACs=hmac-sha1 -o PubkeyAuthentication=no -o StrictHostKeyChecking=no root@HOST tar cf - -C /build/out/i386/drvPCParallel ParallelPort.config | tar xf - -C <repo>\out\i386\drvPCParallel"
```

`HOST` and password come from `vm/vm.conf`. Prefer wrapping that `ssh` with `Invoke-RhapSshAskPass` if the interactive password prompt fails; the file on disk after copy must be a Mach-O, not an SSH error string.

### Host measure — reloc (copy this block)

```powershell
$env:PYTHONPATH = "tools/binrecon"
$env:BINRECON_REFERENCE = "C:\Users\raynorpat\Downloads\test\Drivers\i386\ParallelPort.config\ParallelPort_reloc"
$env:BINRECON_REBUILT = (Resolve-Path "out\i386\drvPCParallel\ParallelPort.config\ParallelPort_reloc").Path
$py = "D:\RhapsodiOS\.venv-binrecon\Scripts\python.exe"
$prof = "tools/binrecon/profiles/parallelport.json"
& $py -m binrecon validate --profile $prof
# Analyze may exit 1 until normalized-functions acceptance passes. That is expected.
# Gate: published/ contains analysis-reference-ida.json, analysis-rebuilt-ida.json, comparison-ida.json.
& $py -m binrecon analyze --profile $prof
& $py -m binrecon function --profile $prof --list
& $py tools/binrecon/parity_check.py $env:BINRECON_REFERENCE $env:BINRECON_REBUILT
```

`validate` must print `reference ... sha256=D188A4D909005683B0C943C84CD99514C14A84AD1D378425B3B1DB343F1EAAA2`. `parity_check.py` must print `missing_strings (0):` and `missing_symbols (0):`. Extra unstripped symbols are not a failure.

For one function:

```powershell
& $py -m binrecon function --profile $prof --name "-[IOParallelPort initDevice]"
```

Use the symbol name as it appears in `--list`.

---

### Task 1: Guest harness and rebuilt reloc profile path

**Files:**
- Create or modify: `vm/build-i386-input-recon.sh`
- Modify: `tools/binrecon/profiles/parallelport.json`

No driver source. No guest build in this task.

- [ ] **Step 1: Check whether the harness already exists**

If `vm/build-i386-input-recon.sh` is already in the worktree with another driver's arm, keep that arm and add `drvPCParallel`. Do not delete sibling arms. Do not restore a five-driver dispatcher. If the file is absent, create it with only `drvPCParallel`.

- [ ] **Step 2: Write or extend the harness**

POSIX Bourne only. No `local`. No bashisms. Do not use `set -e` on predicates (Rhapsody `/bin/sh` applies `set -e` inside `if`). Prefer no `set -e` at all. CR-strip Makefiles. `gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386`. Gate on `ParallelPort_reloc` presence, not `gnumake`'s exit code. Build the Kernel Server `.lksproj` first (required); then attempt the `.drvproj` for tools (optional — do not fail the arm if drvproj/tools die). Stage under `/build/out/i386/drvPCParallel/ParallelPort.config/`. Copy `InstallPPDev` and `RemovePPDev` if they exist; warn if they do not; do not fail the arm.

If creating the file from scratch, this is the whole script:

```sh
#!/bin/sh
# Build one i386 input driver under reconstruction and stage its artifacts.
# Usage: sh vm/build-i386-input-recon.sh drvPCParallel
#
# Gating is on ParallelPort_reloc presence, not gnumake's exit code.
# Keep this POSIX sh — Rhapsody's /bin/sh is a 1999 Bourne shell.

DRV="$1"
NAME=""
PROJ=""
case "$DRV" in
drvPCParallel)
	NAME=ParallelPort
	PROJ=PCParallelPort.drvproj
	;;
*)
	echo "usage: $0 drvPCParallel" >&2
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

DRVPROJ="$SRC/$PROJ"
if [ ! -d "$DRVPROJ" ]; then
	echo "FAILED: no $PROJ under $SRC" >&2
	exit 1
fi

LKS="$DRVPROJ/PCParallelPort.lksproj"
if [ ! -d "$LKS" ]; then
	echo "FAILED: no PCParallelPort.lksproj" >&2
	exit 1
fi

echo "======== build $NAME Kernel Server ========"
cd "$LKS" || exit 1
gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386
echo "lks make exit=$?"

echo "======== build $NAME Driver (tools) ========"
cd "$DRVPROJ" || exit 1
gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386
echo "drvproj make exit=$?"

RELOC=`find "$SRC" -name "${NAME}_reloc" -type f 2>/dev/null | head -1`
if [ -z "$RELOC" ] || [ ! -f "$RELOC" ]; then
	echo "FAILED: no ${NAME}_reloc for $NAME" >&2
	find "$SRC" \( -name '*reloc*' -o -name '*.config' \) 2>/dev/null | head -40 >&2
	exit 1
fi

mkdir -p "$STAGE"
cp -p "$RELOC" "$STAGE/"
for f in "$DRVPROJ"/*.table; do
	[ -f "$f" ] || continue
	cp -p "$f" "$STAGE/"
done
for tool in InstallPPDev RemovePPDev; do
	t=`find "$SRC" -name "$tool" -type f 2>/dev/null | head -1`
	if [ -n "$t" ] && [ -f "$t" ]; then
		cp -p "$t" "$STAGE/"
		echo "staged $tool"
	else
		echo "WARNING: no $tool for $NAME"
	fi
done

echo "=== input-recon done fail=0 built: $DRV ==="
ls -l "$STAGE"
```

If the file already exists, add a `drvPCParallel)` arm with `NAME=ParallelPort` and `PROJ=PCParallelPort.drvproj`. That arm must build the `.lksproj` first, then attempt the `.drvproj` for tools, and stage tools as above, even if sibling arms still build only from their `.lksproj`. Keep existing arms and their stage paths. Do not change another driver's `NAME`/`PROJ`.

LF line endings. No CRLF.

- [ ] **Step 3: Add rebuilt path to the reloc profile**

In `tools/binrecon/profiles/parallelport.json`, after the `reference` object, add:

```json
  "rebuilt": {
    "path": "${BINRECON_REBUILT}"
  },
```

Do not change analyzer flags. Ghidra stays `enabled: false`. angr stays `enabled: true`. `output_dir` stays `../out/parallelport`.

- [ ] **Step 4: Syntax-check the harness on the host**

Git Bash or WSL:

```bash
sh -n vm/build-i386-input-recon.sh && echo "syntax OK"
```

Expected: `syntax OK`. If you have no Unix `sh` on Windows, skip this step and rely on the guest `sh` in Task 4; note that in the Task 4 report.

- [ ] **Step 5: Commit**

```powershell
git add vm/build-i386-input-recon.sh tools/binrecon/profiles/parallelport.json
git commit -m "drivers-i386: add ParallelPort guest harness and rebuilt profile path"
```

---

### Task 2: Restore PreLoad/PostLoad on TOOLS

**Files:**
- Modify: `src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/Makefile`
- Depends on: none (can land with Task 1)

No guest build. Do not convert the tproj Makefiles yet.

- [ ] **Step 1: Restore TOOLS**

Replace the comment-plus-single-tool block:

```make
# PostLoad/PreLoad are userspace tools; skip on PPC cross-host i386 builds.
TOOLS = PCParallelPort.lksproj
```

with:

```make
TOOLS = PCParallelPort.lksproj PostLoad.tproj PreLoad.tproj
```

`PB.project` already lists those three. Do not edit `Default.table`. Do not swap tproj contents.

- [ ] **Step 2: Commit**

```powershell
git add src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/Makefile
git commit -m "drvPCParallel: restore PreLoad and PostLoad on the Driver TOOLS list"
```

---

### Task 3: Local VERS_OFILE

**Files:**
- Create: `src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PCParallelPort.lksproj/Makefile.postamble`

No guest build in this task. The line is a reconstruction; keep it even if later extents do not close.

- [ ] **Step 1: Create the postamble**

The lksproj `Makefile` already has `-include Makefile.postamble`. Create that file with exactly:

```make
OTHER_GENERATED_OFILES += $(VERS_OFILE)
```

LF endings. Match `src/drivers-i386/video/drvCirrusLogicGD5434/CirrusLogicGD5434.drvproj/CirrusLogicGD5434DisplayDriver.lksproj/Makefile.postamble`. Do not edit `driverTools` or `kernelserver.make`.

- [ ] **Step 2: Commit**

```powershell
git add src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PCParallelPort.lksproj/Makefile.postamble
git commit -m "drvPCParallel: emit ParallelPort vers_string objects from the Kernel Server"
```

---

### Task 4: Phase 1 baseline on the guest

**Files:**
- Create: `src/drivers-i386/input/drvPCParallel/reconstruction/function-worklist.md`
- Depends on: Tasks 1–3

No reloc shape edits. This is the regression snapshot.

- [ ] **Step 1: Confirm the reference binary**

```powershell
Get-FileHash "C:\Users\raynorpat\Downloads\test\Drivers\i386\ParallelPort.config\ParallelPort_reloc" -Algorithm SHA256
```

Expected: `D188A4D909005683B0C943C84CD99514C14A84AD1D378425B3B1DB343F1EAAA2`. Wrong hash → **BLOCKED**.

- [ ] **Step 2: Guest rebuild**

Run the Guest rebuild block. Required: staged `ParallelPort_reloc`. Record whether `InstallPPDev` and `RemovePPDev` staged. If they failed to link (missing i386 crt / libDriver), write that into the worklist and continue the reloc baseline. Do not invent `IODeviceMaster`. Phase 3 waits until they link.

- [ ] **Step 3: Host measure**

Run the Host measure — reloc block. `missing_strings` 0, `missing_symbols` 0. `instance_size` of `IOParallelPort` stays 404. If it is not 404, **BLOCKED** — that is a Task 10 regression.

- [ ] **Step 4: Write the worklist**

Create `function-worklist.md` with:

- both reloc SHA-256s
- `__TEXT,__text` / `__TEXT,__const` sizes (confirm `_ParallelPort_VERS_STRING` and `_ParallelPort_VERS_NUM` exist after Task 3)
- `--list` counts: identical / `masked_equal` / differing / unpaired
- the 18 `control-flow-confirmed` names plus the three reopened rows (`initDevice`, `probeForController`, `_strobeChar`)
- tool file sizes and Mach-O types, or the missing-library note
- whether the cheapest differing rows look source-shaped or already compiler-shaped

Do not open tool bodies yet.

- [ ] **Step 5: Commit**

```powershell
git add src/drivers-i386/input/drvPCParallel/reconstruction/function-worklist.md
git commit -m "drvPCParallel: record instruction-stream baseline worklist"
```

Never stage `out/` or `tools/binrecon/out/`.

---

### Task 5: Mark baseline-identical reloc functions assembly-matched

**Files:**
- Modify: `src/drivers-i386/input/drvPCParallel/reconstruction/ledger.json`
- Modify: `src/drivers-i386/input/drvPCParallel/reconstruction/divergences.md`
- Depends on: Task 4 `--list`

No driver source. No rebuild.

- [ ] **Step 1: Transition the ledger**

Every `--list` row that is identical or `masked_equal`, except the two glue methods and the `physbuf` encoding pair, becomes `assembly-matched` if it is not already. Glue stays `intentional-mismatch`:

- `+[ParallelPortKernelServerInstance kernelServerInstance]`
- `+[ParallelPortVersion driverKitVersionForParallelPort]`

`physbuf` / `setPhysbuf:` stay `intentional-mismatch` for the `struct buf` encoding. Forward-only: `control-flow-confirmed` → `assembly-matched`. Do not mark compiler-shaped leftovers `assembly-matched`. Reviewer: `Pat Raynor`. Set `rebuilt_sha256` to the Task 4 `_reloc` SHA.

- [ ] **Step 2: Note the baseline in divergences.md**

Append a "Finish campaign" heading: date, rebuilt SHA, how many rows were already `masked_equal` / `raw_equal`, that VERS objects were checked, that tools were staged or missing. Do not delete Task 10 findings.

- [ ] **Step 3: Commit**

```powershell
git add src/drivers-i386/input/drvPCParallel/reconstruction/ledger.json src/drivers-i386/input/drvPCParallel/reconstruction/divergences.md
git commit -m "drvPCParallel: mark baseline-identical functions assembly-matched"
```

---

### Task 6: Reverse Finding 53 (uninitialized control byte)

**Files:**
- Modify: `src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PCParallelPort.lksproj/IOParallelPort.m` (`probeForController` at line 223, `initDevice` at line 258)
- Modify: `reconstruction/divergences.md`, `ledger.json`, `source-map.json` (line numbers), `function-worklist.md`
- Depends on: Task 4 `--name` dumps for both methods

This is a reconstruction, not an experiment. Keep the uninitialized local even if extents do not close.

- [ ] **Step 1: Read the reference shape**

```powershell
& $py -m binrecon function --profile $prof --name "-[IOParallelPort probeForController]"
& $py -m binrecon function --profile $prof --name "-[IOParallelPort initDevice]"
```

Transcribe the `and`/`or` immediates from the **reference** column. Apple reads the control register into one stack slot and `and`/`or`s a *different, never-initialised* slot. Bits 0–5 of the emitted byte already match; bits 6–7 are leftover stack.

- [ ] **Step 2: Rewrite both methods to that shape**

`probeForController` today initialises `controlValue` to `PP_CONTROL_AUTOFEED | PP_CONTROL_INIT | PP_CONTROL_SELECT | PP_CONTROL_IRQ_EN` then `PP_CONTROL_INIT`. Replace that with:

- `unsigned char readBack;` — receives `inb(PP_PORT(controlRegister))`
- `unsigned char controlValue;` — **not initialised**
- `controlValue &= <imm>; controlValue |= <imm>;` using the immediates from Step 1
- keep the two read-back checks `(readValue & 0x1F) != 0x1E` and `(readValue & 0x15) != 0x04` and the `BOOL` return

`initDevice` today initialises `controlValue = PP_CONTROL_SELECT | PP_CONTROL_INIT` then optionally `|= PP_CONTROL_AUTOFEED`. Same split: read into one local, `and`/`or` the uninitialized local, including the autofeed bit and the later `|= PP_CONTROL_IRQ_EN` for `controlRegisterDefaults`. Do not change any `IO_R_*` return.

Do not inject dummy stack values to force bits 6–7. If gcc 2.x zero-fills anyway, keep the uninitialized local and accept the leftover as compiler-shaped in Task 8.

- [ ] **Step 3: Guest rebuild and measure**

Guest rebuild. Parity 0/0. Fresh analyze. `--name` both methods. `--list` must not regress any Task 5 identical row.

- [ ] **Step 4: Record**

In `divergences.md`, reverse Finding 53's accept. Paste the `--name` summary. Ledger: `assembly-matched` if `masked_equal`, else leave `intentional-mismatch` with reason `Finding 53 uninitialized control byte; leftover is gcc 2.x zero-fill` and reviewer `Pat Raynor`. Relined `source-map.json`.

- [ ] **Step 5: Commit**

```powershell
git add src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PCParallelPort.lksproj/IOParallelPort.m src/drivers-i386/input/drvPCParallel/reconstruction/divergences.md src/drivers-i386/input/drvPCParallel/reconstruction/ledger.json src/drivers-i386/input/drvPCParallel/reconstruction/source-map.json src/drivers-i386/input/drvPCParallel/reconstruction/function-worklist.md
git commit -m "drvPCParallel: build control bytes from an uninitialized local like Apple"
```

---

### Task 7: Reverse `_strobeChar` load-then-test order

**Files:**
- Modify: `src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PCParallelPort.lksproj/IOParallelPortKern.m` (`_strobeChar` at line 639)
- Modify: `reconstruction/divergences.md`, `ledger.json`, `source-map.json`, `function-worklist.md`
- Depends on: Task 4

This is a reconstruction, not an experiment. After the reorder, a nil device with leftover count faults like Apple.

- [ ] **Step 1: Reorder the prologue**

Today `_strobeChar` tests `pp_softc[portNum].count <= 0` then loads `port` / registers. Apple loads the device pointer and the three register values first. Change the top of the function to:

```c
int _strobeChar(int portNum, unsigned int delay, char useSpl)
{
    IOParallelPort *port;
    unsigned char controlRegValue;
    IOEISAPortAddress dataRegAddr;
    IOEISAPortAddress controlRegAddr;
    int savedPriority = 0;

    port = (IOParallelPort *)pp_softc[portNum].device;
    controlRegValue = port->controlRegisterDefaults;
    controlRegAddr = PP_PORT(port->controlRegister);
    dataRegAddr = PP_PORT(port->dataRegister);

    if (pp_softc[portNum].count <= 0)
        return 0;
```

Leave the `useSpl` / `spl3` block, the second count check, the three `outb`/`IODelay` strobes, and the pointer/count advance unchanged.

- [ ] **Step 2: Guest rebuild and measure**

Guest rebuild. Parity 0/0. Fresh analyze. `--name __strobeChar`. `--list` must not regress closed rows (including Task 6 if those matched).

- [ ] **Step 3: Record**

In `divergences.md`, reverse the `_strobeChar` ordering accept (Finding 51 leftover). Ledger `assembly-matched` or compiler-shaped accept. Relined `source-map.json`.

- [ ] **Step 4: Commit**

```powershell
git add src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PCParallelPort.lksproj/IOParallelPortKern.m src/drivers-i386/input/drvPCParallel/reconstruction/divergences.md src/drivers-i386/input/drvPCParallel/reconstruction/ledger.json src/drivers-i386/input/drvPCParallel/reconstruction/source-map.json src/drivers-i386/input/drvPCParallel/reconstruction/function-worklist.md
git commit -m "drvPCParallel: load the strobe device pointer before testing the byte count"
```

---

### Task 8: Cheapest-first reloc instruction-shape grind

**Files:**
- Modify: `.../PCParallelPort.lksproj/IOParallelPort.m`
- Modify: `.../PCParallelPort.lksproj/IOParallelPortKern.m`
- Modify headers in that directory only if a typed rewrite is required
- Modify: `reconstruction/function-worklist.md`, `divergences.md`, `ledger.json`, `source-map.json`
- Depends on: Tasks 4–7

- [ ] **Step 1: Write named experiment lists into the worklist**

Before the first Task 8 source edit, append to `function-worklist.md` a short list per remaining non-equal paired hand-written function, cheapest `differing` first. Skip glue, skip `physbuf` / `setPhysbuf:`, skip already-identical rows. One experiment idea per function to start; add more only after a miss.

Allowed: statement order, local vs expression, signedness of *locals*, loop shape, `if` vs `else if`, operand-reversed `cmp`, declaration order of existing locals.

Forbidden: padding ivars; changing `IOParallelPort` instance layout; renaming ivars or protocols; inventing temporaries whose only purpose is to pick a register; repeating a reverted experiment; chasing `__text` size; rewriting the fifty Task 10 matches; editing `buf.h`; injecting dummy stack junk; hand-writing Kernel Server glue.

Compiler-shaped means the `--name` columns differ only by register choice, instruction scheduling, or equivalent gcc 2.x shape — not a wrong constant, missing call, inverted branch, or wrong offset.

- [ ] **Step 2: Loop until every remaining paired reloc function is equal or accepted**

For each cheapest still-open source-shaped row:

1. `--name` the current function. Keep the dump.
2. Apply one experiment in the owning `.m` file.
3. Run the Guest rebuild procedure. `parity_check.py` must stay 0 / 0.
4. Fresh analyze of the rebuilt. `--name` on the **new** published comparison. `--list` to confirm previously identical rows did not regress.
5. Match (`raw_equal` or `masked_equal`) → keep the edit, ledger `assembly-matched`, record outcome in `divergences.md`, commit `drvPCParallel: ` describing the behaviour.
6. Miss, no regression → revert the experiment, mark tried in the worklist, try the next item on that function's list.
7. Regression of a closed function → revert, record, continue.
8. Empty list, still not equal → accept: paste `--name` dump under `divergences.md`, ledger `intentional-mismatch` with reason `compiler-shaped leftover after exhausted source-shape list` and reviewer `Pat Raynor`. Do not grind further.

One shared cause is one edit cluster (one commit). Relined `source-map.json` when bodies move; keep 73 mapped / 2 unmapped.

If `--list` grows unpaired functions other than the two glue methods, stop grinding. That is a layout or linkage finding.

If `__text` stays short of Apple's after all accepts, record the sizes. Not a failure.

- [ ] **Step 3: Stop condition**

`--list`: unpaired only the two glue methods. Every other hand-written row is identical, `masked_equal`, or accepted compiler-shaped. `physbuf` encoding still differs and does not block. Ledger has no `unexamined` hand-written function. `__TEXT,__const` still names the two `vers_string` symbols.

---

### Task 9: Reloc close

**Files:**
- Modify: `reconstruction/function-worklist.md`
- Modify: `reconstruction/ledger.json` (`rebuilt_sha256` = last kept `_reloc`)
- Depends on: Task 8 stop condition

No further reloc source-shape edits. Do not update README yet — Task 12 does the package line after the tools close.

- [ ] **Step 1: Refresh the worklist summary**

Final reloc SHA-256s, `--list` counts (identical / masked-eq / accepted / unpaired glue), `__text` / `__const` sizes, statement that tools are still open.

- [ ] **Step 2: Set ledger `rebuilt_sha256`**

Must equal the SHA of the last kept `ParallelPort_reloc`.

- [ ] **Step 3: Commit**

```powershell
git add src/drivers-i386/input/drvPCParallel/reconstruction/function-worklist.md src/drivers-i386/input/drvPCParallel/reconstruction/ledger.json
git commit -m "drvPCParallel: record reloc instruction-stream close"
```

---

### Task 10: Tool profiles, nlist decision, PB tool.make

**Files:**
- Create: `tools/binrecon/profiles/installppdev.json`
- Create: `tools/binrecon/profiles/removeppdev.json`
- Modify: `PCParallelPort.drvproj/PreLoad.tproj/Makefile`, `Makefile.preamble`, `PB.project`
- Modify: `PCParallelPort.drvproj/PostLoad.tproj/Makefile`, `Makefile.preamble`, `PB.project`
- Delete or replace: `PreLoad.tproj/IODeviceMaster.m`, `IODeviceMaster.h` (path depends on nlist)
- Depends on: Task 4 (tools must link; if they still do not, this task is **BLOCKED** on crt/libDriver — do not invent IODeviceMaster)

No instruction-shape grind yet.

- [ ] **Step 1: Read the InstallPPDev nlist**

```powershell
$env:PYTHONPATH = "tools/binrecon"
& $py -c @"
from binrecon.macho import read_macho
from pathlib import Path
m = read_macho(Path(r'C:\Users\raynorpat\Downloads\test\Drivers\i386\ParallelPort.config\InstallPPDev'))
for s in m['symbols']:
    name = s.get('name') or s.get('n_name')
    bind = s.get('binding') or s.get('n_type')
    sect = s.get('section')
    if name and ('IODevice' in name or 'IOGet' in name or 'IOLookup' in name or 'IOSet' in name or 'IOCreate' in name or name.startswith('_IO')):
        print(bind, sect, name)
"@
```

If `InstallPPDev` does **not** define `IODeviceMaster` methods / `_IOGetCharValues` (they are undefined imports), take **-lDriver**: delete `PreLoad.tproj/IODeviceMaster.m` and `IODeviceMaster.h`; `InstallPPDev.m` must `#import <driverkit/IODeviceMaster.h>`.

If it **does** define them, take the **local-TU** path: replace `IODeviceMaster.m` with a copy shaped like `src/driverkit-3/libDriver/User/IODeviceMaster.m` (import `<driverkit/driverServer.h>`, call `_IOGetCharValues` and friends). Do not keep the 2180-line invented Mach-message file either way.

Write the decision into `function-worklist.md`.

- [ ] **Step 2: Convert PostLoad.tproj to PB tool.make**

Replace `PostLoad.tproj/Makefile` with:

```make
#
# Generated by the NeXT Project Builder.
#
# NOTE: Do NOT change this file -- Project Builder maintains it.
#
# Put all of your customizations in files called Makefile.preamble
# and Makefile.postamble (both optional), and Makefile will include them.
#

NAME = RemovePPDev

PROJECTVERSION = 2.6
PROJECT_TYPE = Tool
LANGUAGE = English

CFILES = RemovePPDev.c

OTHERSRCS = Makefile Makefile.preamble Makefile.postamble

MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
CODE_GEN_STYLE = DYNAMIC
MAKEFILE = tool.make
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

Replace `PostLoad.tproj/Makefile.preamble` so it is the PB template with `INCLUDED_ARCHS = i386` and no `-O2` / `-Wall`. Leave `Makefile.postamble` as the existing stub or empty.

Update `PostLoad.tproj/PB.project` `FILESTABLE` `C_FILES = (RemovePPDev.c);` and `PROJECTNAME = RemovePPDev;` (already true). `LIBS` stays empty.

- [ ] **Step 3: Convert PreLoad.tproj to PB tool.make**

Same Makefile shape as Step 2 with `NAME = InstallPPDev`, `CLASSES = InstallPPDev.m` on the `-lDriver` path (`CLASSES = InstallPPDev.m IODeviceMaster.m` on the local-TU path), `LIBS = -lDriver` on the `-lDriver` path (`LIBS =` on the local-TU path if the MIG stubs are in the `.m`). `HFILES` empty on the `-lDriver` path.

On the `-lDriver` path, change `InstallPPDev.m` line 8 from `#import "IODeviceMaster.h"` to `#import <driverkit/IODeviceMaster.h>`.

Update `PreLoad.tproj/PB.project` `CLASSES` to match, drop `H_FILES = (IODeviceMaster.h);` on the `-lDriver` path.

- [ ] **Step 4: Write the two IDA-only profiles**

`tools/binrecon/profiles/removeppdev.json`:

```json
{
  "schema_version": "profile-v1",
  "name": "RemovePPDev reconstruction (IDA only)",
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
  "output_dir": "../out/removeppdev"
}
```

`installppdev.json` is the same with `"name": "InstallPPDev reconstruction (IDA only)"` and `"output_dir": "../out/installppdev"`.

- [ ] **Step 5: Guest rebuild**

Guest rebuild. Both tools must now stage (this task's gate). Reloc `__text` identity must not regress. Copy all three artifacts back.

- [ ] **Step 6: Commit**

```powershell
git add vm/build-i386-input-recon.sh tools/binrecon/profiles/installppdev.json tools/binrecon/profiles/removeppdev.json src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PreLoad.tproj src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PostLoad.tproj src/drivers-i386/input/drvPCParallel/reconstruction/function-worklist.md src/drivers-i386/input/drvPCParallel/reconstruction/divergences.md
git commit -m "drvPCParallel: build InstallPPDev and RemovePPDev as DriverKit tools"
```

Do not add `vm/build-i386-input-recon.sh` unless this task actually changed it. Stage deleted `IODeviceMaster` files with `git add -u` on those two paths only.

---

### Task 11: Reconstruct RemovePPDev

**Files:**
- Modify: `src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PostLoad.tproj/RemovePPDev.c`
- Create: `reconstruction/removeppdev-ledger.json`, `reconstruction/removeppdev-source-map.json`
- Modify: `reconstruction/function-worklist.md`, `divergences.md`
- Depends on: Task 10 staged `RemovePPDev`

- [ ] **Step 1: Baseline the tool**

```powershell
$env:PYTHONPATH = "tools/binrecon"
$env:BINRECON_REFERENCE = "C:\Users\raynorpat\Downloads\test\Drivers\i386\ParallelPort.config\RemovePPDev"
$env:BINRECON_REBUILT = (Resolve-Path "out\i386\drvPCParallel\ParallelPort.config\RemovePPDev").Path
$prof = "tools/binrecon/profiles/removeppdev.json"
& $py -m binrecon analyze --profile $prof
& $py -m binrecon function --profile $prof --list
```

Write the ranked list into `function-worklist.md` under a `RemovePPDev` heading. Create `removeppdev-source-map.json` mapping paired functions to `RemovePPDev.c`. libc / crt imports stay unpaired.

- [ ] **Step 2: Grind `main` (and any other paired locals) cheapest-first**

Same loop as Task 8, scoped to `RemovePPDev.c`. One experiment, one guest rebuild, `--name` on the new comparison. Reloc `--list` must not regress: after each rebuild also run the reloc Host measure block and confirm closed reloc rows stay identical. Match → `removeppdev-ledger.json` `assembly-matched`. Exhausted list → accept with dump.

Do not link `-lDriver` here. Do not rename the binary.

- [ ] **Step 3: Stop condition**

Every paired `RemovePPDev` function is identical, `masked_equal`, or accepted. Commit `drvPCParallel: ` describing the tool behaviour.

```powershell
git add src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PostLoad.tproj/RemovePPDev.c src/drivers-i386/input/drvPCParallel/reconstruction
git commit -m "drvPCParallel: reconstruct RemovePPDev against the reference executable"
```

---

### Task 12: Reconstruct InstallPPDev

**Files:**
- Modify: `src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PreLoad.tproj/InstallPPDev.m`
- Modify: `PreLoad.tproj/IODeviceMaster.m` only if Task 10 took the local-TU path
- Create: `reconstruction/installppdev-ledger.json`, `reconstruction/installppdev-source-map.json`
- Modify: `reconstruction/function-worklist.md`, `divergences.md`
- Depends on: Tasks 10–11

- [ ] **Step 1: Baseline the tool**

Same as Task 11 Step 1 with `InstallPPDev` paths and `tools/binrecon/profiles/installppdev.json`. LibDriver imports stay unpaired on the `-lDriver` path. If the local-TU path is active, those `IODeviceMaster` methods are paired and join the grind set.

- [ ] **Step 2: Grind cheapest-first**

Same loop as Task 8, scoped to `InstallPPDev.m` (and the local `IODeviceMaster.m` only if present). After each rebuild, reloc `--list` must not regress and `RemovePPDev` must not regress. SCSI Tape's PostLoad is the behavioural model for `main` (`Instance=`, `lookUpByDeviceName:`, `IOMajorDevice` / `IOMinorDevice`, `unlink`, `mknod`); do not invent extra keys.

- [ ] **Step 3: Stop condition and commit**

Every paired `InstallPPDev` function is identical, `masked_equal`, or accepted.

```powershell
git add src/drivers-i386/input/drvPCParallel/PCParallelPort.drvproj/PreLoad.tproj src/drivers-i386/input/drvPCParallel/reconstruction
git commit -m "drvPCParallel: reconstruct InstallPPDev against the reference executable"
```

---

### Task 13: Campaign close

**Files:**
- Modify: `reconstruction/function-worklist.md`
- Modify: `reconstruction/ledger.json` (`rebuilt_sha256` of last kept reloc)
- Modify: `src/drivers-i386/README` drvPCParallel line only
- Depends on: Tasks 9, 11, 12 stop conditions

No further source-shape edits.

- [ ] **Step 1: Refresh the worklist**

Final SHA-256s for all three artifacts, reloc `--list` counts, tool `--list` counts, VERS symbols present, `physbuf` encoding still noted, hardware testing still out.

- [ ] **Step 2: Update README**

Change only the drvPCParallel bullet. Keep "not yet tested." Name the new reloc counts and that both tools were rebuilt and compared. Do not write `complete`. Do not un-blacklist the driver. Example shape (fill in the real numbers):

```
 * drvPCParallel - compiles; reconstructed against the reference binary, N/73 hand-written reloc functions byte-identical under relocation masking, remainder accepted as compiler-shaped; InstallPPDev and RemovePPDev rebuilt and compared; not yet tested
```

- [ ] **Step 3: Commit**

```powershell
git add src/drivers-i386/input/drvPCParallel/reconstruction/function-worklist.md src/drivers-i386/input/drvPCParallel/reconstruction/ledger.json src/drivers-i386/README
git commit -m "drivers-i386: record drvPCParallel instruction-stream finish"
```

---

## Spec coverage

| Spec section | Task |
|---|---|
| Phase 0 harness, ParallelPort arm, stage tools, no five-driver dispatcher | 1 |
| Reloc profile `rebuilt.path`, Ghidra off | 1 |
| Restore `TOOLS` | 2 |
| Local `VERS_OFILE` | 3 |
| Phase 1 baseline, parity 0/0, worklist, instance size 404 | 4 |
| Already-identical rows → `assembly-matched` | 5 |
| Finding 53 uninitialized control byte | 6 |
| `_strobeChar` load-then-test | 7 |
| Cheapest-first reloc grind, allowed/forbidden, accepts | 8 |
| Reloc close, `rebuilt_sha256` | 9 |
| Tool nlist decision, `-lDriver` default, delete invented IODeviceMaster, `tool.make` | 10 |
| `RemovePPDev` then `InstallPPDev` to the same bar | 11, 12 |
| README, no `complete`, no un-blacklist, no QEMU | 13 |
| `physbuf` encoding not a closer, no `buf.h` | Tasks 5, 8, 13 |
| Guest SSH, no pscp, no `-All` | Guest rebuild procedure |
| Glue unpaired | Tasks 5, 8 |
