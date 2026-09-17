# PnPDump binrecon finish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drive `PnPDump` to function-level `raw_equal` / `masked_equal` (or recorded compiler-shaped accepts) against Apple's shipped tool, and drive every shared PnP class method to the same bar on `EISABus_reloc`, with a guest `gnumake` rebuild loop and one close `rbuild`.

**Architecture:** PnPDump-led dual match. IDA 9.2 + angr (Ghidra off) on Apple's `PnPDump` decide the shared class set and whether stubs are local. `PnPDump.tproj` compiles the matching `EISABus.lksproj` class `.m` files by path plus a new `PnPDump.m` extracted from `R.m`'s `main`. Kernel-only reloc symbols stay frozen. Name-paired `masked_equal` in `compare.py` is reused as-is.

**Tech Stack:** Objective-C DriverKit / userland Tool on a Rhapsody PPC guest (`gnumake RC_ARCHS=i386`), OpenSSH via `vm/rhap-remote.ps1`, IDA 9.2 through `tools/binrecon`, Python `./.venv-binrecon/Scripts/python.exe` with `PYTHONPATH=tools/binrecon`.

**Spec:** [2026-09-16-pnpdump-binrecon-finish-design.md](../specs/2026-09-16-pnpdump-binrecon-finish-design.md)

## File map

| File | Responsibility |
|---|---|
| `vm/build-i386-bus-recon.sh` | Guest harness. Build `EISABus.drvproj`; stage `EISABus_reloc` and `PnPDump`. |
| `tools/binrecon/profiles/pnpdump.json` | New. IDA+angr, Ghidra off, `rebuilt.path` `${BINRECON_REBUILT}`. |
| `tools/binrecon/profiles/eisabus.json` | Add `rebuilt.path` only. Leave Ghidra enabled. |
| `PnPDump.tproj/PnPDump.m` | New. `main` + `bail` from `R.m`. |
| `PnPDump.tproj/IOStubs.m` | Only if Apple's nlist defines local `IOMalloc` / `IOLog` / callouts. |
| `PnPDump.tproj` Makefile / `PB.project` | Shared class `.m` via `../EISABus.lksproj/` plus PnPDump-only TUs. |
| `EISABus.drvproj/PB.project` | Add `PnPDump.tproj` to `SUBPROJECTS`. |
| Nine lksproj class `.m` files | Dual-target instruction-shape edits. |
| `R.m` | Deleted after `PnPDump.m` exists. |
| `dumpConfig.m` | Unchanged, never `MFILES`. |
| `reconstruction/pnpdump/` | Tool ledger, source-map, divergences, function-worklist. |
| `reconstruction/` | Reloc ledger: shared-method rows only. |
| `src/drivers-i386/README` | Close-out counts; still not retested. |

## Global constraints

- **This session runs every guest rebuild.** Sync only `drivers-i386/bus/drvEISABus`. Never `sync-src.ps1 -All`.
- **Do not invent instruction diffs.** Every source-shape edit comes from `binrecon function --name` of a named function. If the dump is not in hand, stop.
- **Shared method = dual bar.** Keep an edit only if both Mach-Os move toward `raw_equal` / `masked_equal`, or record one compiler-shaped accept citing both `--name` dumps. One-sided win → revert.
- **Kernel-only reloc symbols are frozen:** `EISAKernBus*`, `EISAResourceDriver`, `PnPBios`, `PnPArgStack`, `bios.c`, `eisa.c`, and any name Apple's `PnPDump` nlist does not define.
- **Do not grind envelope size.** `__TEXT,__text` need not match Apple. `cfg_equal` is not a pass.
- **Do not touch:** `Default.table`, `Load_Commands.sect`, `dpkg/`, `src/kernel-7`, sibling drivers, `compare.py`, `normalize.py`, `driverTools`, `kernel-drivers-blacklist.json`, `dumpConfig.m` as compiled source.
- **Do not enable Ghidra** on `pnpdump.json`. **Do not disable Ghidra** on `eisabus.json`.
- **Commit messages:** `drvEISABus: ` for driver/reconstruction; `drivers-i386: ` for harness and README; `binrecon: ` for profiles; `docs: ` for spec/plan. One to two lines. No trailers. Stage by explicit path. Never `git add -A`. Never commit `_reloc`, rebuilt `PnPDump`, or `tools/binrecon/out/`.
- **Python:** `$env:PYTHONPATH = "tools/binrecon"` then `.\.venv-binrecon/Scripts/python.exe`.
- **Tool reference SHA** must stay `006DC6BB73CEBC6243DA669E5199AEC808F309E72C3EE617A3FD8ED310364772`. **Reloc reference SHA** must stay `8F252AF66CD49A8E03B51E57E90CB613D0B9DC1602263F4B7B6393E483977B23`. Wrong binary → stop.
- **Reviewer** on ledger accepts: `Pat Raynor`.

## Paths and env

Two profiles share the env var names. Set them **per invocation**. Worktree root = `<repo>`.

```powershell
$env:PYTHONPATH = "tools/binrecon"
$py = ".\.venv-binrecon\Scripts\python.exe"
$pnp = "tools/binrecon/profiles/pnpdump.json"
$eisa = "tools/binrecon/profiles/eisabus.json"
```

**Tool**

```powershell
$env:BINRECON_REFERENCE = "C:\Users\raynorpat\Downloads\test\Drivers\i386\EISABus.config\PnPDump"
$env:BINRECON_REBUILT = "<repo>\out\i386\drvEISABus\EISABus.config\PnPDump"
```

**Reloc**

```powershell
$env:BINRECON_REFERENCE = "C:\Users\raynorpat\Downloads\test\Drivers\i386\EISABus.config\EISABus_reloc"
$env:BINRECON_REBUILT = "<repo>\out\i386\drvEISABus\EISABus.config\EISABus_reloc"
```

Guest source: `/build/source/src/drivers-i386/bus/drvEISABus/`
Guest stage: `/build/out/i386/drvEISABus/EISABus.config/`
Guest harness: `/build/source/vm/build-i386-bus-recon.sh`

`normalized-functions=FAIL` is expected until the campaign closes. A reference-only analyze may exit 1; the gate is `complete: true`.

## Guest rebuild procedure

Use this exact sequence after the harness exists. Do not use PuTTY `pscp`/`plink`.

**Upload harness** (once per host copy of the script, and again if you edit it):

```powershell
. .\vm\rhap-remote.ps1
$cfg = Get-RhapVmConfig
$ssh = Resolve-RhapTool -NameOrPath $cfg.Ssh
$lf = ([IO.File]::ReadAllText((Resolve-Path .\vm\build-i386-bus-recon.sh)) -replace "`r`n","`n") -replace "`r","`n"
$body = "mkdir -p /build/source/vm`ncat > /build/source/vm/build-i386-bus-recon.sh << 'ENDHARNESS'`n$lf`nENDHARNESS`nchmod +x /build/source/vm/build-i386-bus-recon.sh`n"
Invoke-RhapSshScript -Cfg $cfg -Ssh $ssh -ScriptBody $body -Stream
```

**Sync + build:**

```powershell
powershell -NoProfile -File vm\sync-src.ps1 -Path drivers-i386/bus/drvEISABus
. .\vm\rhap-remote.ps1
$cfg = Get-RhapVmConfig
$ssh = Resolve-RhapTool -NameOrPath $cfg.Ssh
Invoke-RhapSshScript -Cfg $cfg -Ssh $ssh -ScriptBody "sh /build/source/vm/build-i386-bus-recon.sh" -Stream
```

Expected after Task 3: a line `=== bus-recon done fail=0 built: drvEISABus ===` and staged `EISABus_reloc` plus `PnPDump`.

**Copy both Mach-Os back** (binary-safe via `cmd.exe` so PowerShell 5 does not corrupt the pipe). Create the host directory first. Use the worktree `<repo>`:

```bat
cmd /c "mkdir <repo>\out\i386\drvEISABus\EISABus.config 2>nul & ssh -o KexAlgorithms=diffie-hellman-group1-sha1 -o HostKeyAlgorithms=ssh-dss -o Ciphers=3des-cbc -o MACs=hmac-sha1 -o PubkeyAuthentication=no -o StrictHostKeyChecking=no root@HOST tar cf - -C /build/out/i386/drvEISABus/EISABus.config EISABus_reloc PnPDump | tar xf - -C <repo>\out\i386\drvEISABus\EISABus.config"
```

`HOST` and password come from `vm/vm.conf`. Prefer wrapping that `ssh` with `Invoke-RhapSshAskPass` if the interactive password prompt fails. Each file on disk after copy must be a Mach-O (`CE FA ED FE`), not an SSH error string.

**After every successful copy:**

Tool pair:

```powershell
$env:BINRECON_REFERENCE = "C:\Users\raynorpat\Downloads\test\Drivers\i386\EISABus.config\PnPDump"
$env:BINRECON_REBUILT = "<repo>\out\i386\drvEISABus\EISABus.config\PnPDump"
& $py tools\binrecon\parity_check.py $env:BINRECON_REFERENCE $env:BINRECON_REBUILT
```

Reloc pair:

```powershell
$env:BINRECON_REFERENCE = "C:\Users\raynorpat\Downloads\test\Drivers\i386\EISABus.config\EISABus_reloc"
$env:BINRECON_REBUILT = "<repo>\out\i386\drvEISABus\EISABus.config\EISABus_reloc"
& $py tools\binrecon\parity_check.py $env:BINRECON_REFERENCE $env:BINRECON_REBUILT
```

Expected: exit 0, `missing_strings (0):`, `missing_symbols (0):` on both. Extra unstripped symbols are not findings.

Then IDA-analyze each rebuilt (and a reference only if published output is missing or SHA differs):

```powershell
$env:BINRECON_REFERENCE = "C:\Users\raynorpat\Downloads\test\Drivers\i386\EISABus.config\PnPDump"
$env:BINRECON_REBUILT = "<repo>\out\i386\drvEISABus\EISABus.config\PnPDump"
& $py -m binrecon analyze --profile $pnp

$env:BINRECON_REFERENCE = "C:\Users\raynorpat\Downloads\test\Drivers\i386\EISABus.config\EISABus_reloc"
$env:BINRECON_REBUILT = "<repo>\out\i386\drvEISABus\EISABus.config\EISABus_reloc"
& $py -m binrecon analyze --profile $eisa
```

`--list` / `--name`:

```powershell
& $py -m binrecon function --profile $pnp --list
& $py -m binrecon function --profile $eisa --list
& $py -m binrecon function --profile $pnp --name "_main"
```

Use the symbol name as it appears in `--list`. Shared methods require `--name` on **both** profiles.

If the guest is unreachable, stop. Do not invent instruction-stream results.

The nine candidate shared class files (nlist in Task 2 may drop some; do not add kernel-only classes without amending the spec):

- `PnPDependentResources.m`
- `PnPDeviceResources.m`
- `PnPLogicalDevice.m`
- `PnPResource.m`
- `PnPResources.m`
- `pnpDMA.m`
- `pnpIOPort.m`
- `pnpIRQ.m`
- `pnpMemory.m`

All live under `src/drivers-i386/bus/drvEISABus/EISABus.drvproj/EISABus.lksproj/`.

---

### Task 1: Profiles and guest harness

**Files:**
- Create: `tools/binrecon/profiles/pnpdump.json`
- Modify: `tools/binrecon/profiles/eisabus.json`
- Create: `vm/build-i386-bus-recon.sh`

No driver source. No guest build.

**Interfaces:**
- Consumes: nothing
- Produces: `$pnp` profile Ghidra off; `$eisa` `rebuilt.path`; harness that stages both Mach-Os from `EISABus.drvproj`

- [ ] **Step 1: Write `pnpdump.json`**

Copy the analyzer block from `tools/binrecon/profiles/ps2keyboard.json` (IDA 9.2 on, Ghidra **off**, angr 9.3.0 on). Entire file:

```json
{
  "schema_version": "profile-v1",
  "name": "PnPDump reconstruction",
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
  "output_dir": "../out/pnpdump"
}
```

- [ ] **Step 2: Add rebuilt path to `eisabus.json`**

After the `reference` object, add (keep Ghidra `enabled: true`, keep `output_dir` `../out/eisabus`):

```json
  "rebuilt": {
    "path": "${BINRECON_REBUILT}"
  },
```

- [ ] **Step 3: Write the harness**

POSIX Bourne only. No `local`. No bashisms. No `set -e`. LF line endings. Build **`EISABus.drvproj`**, not the lksproj alone.

```sh
#!/bin/sh
# Build drvEISABus (kernel server + PnPDump) and stage both Mach-Os.
# Usage: sh vm/build-i386-bus-recon.sh
#
# Gating is on artifact presence, not gnumake's exit code. A recursive
# pb_makefiles build can return nonzero for a step outside what we need.
# Keep this POSIX sh — Rhapsody's /bin/sh is a 1999 Bourne shell.

ROOT="${SRCROOT:-/build/source}"
SRC="$ROOT/src/drivers-i386/bus/drvEISABus"
PROJ="$SRC/EISABus.drvproj"
STAGE="$ROOT/out/i386/drvEISABus/EISABus.config"

if [ ! -d "$PROJ" ]; then
	echo "build-i386-bus-recon: missing $PROJ" >&2
	exit 1
fi

find "$SRC" -type f \( -name Makefile -o -name Makefile.preamble -o -name Makefile.postamble -o -name '*.make' \) -print |
while read f
do
	tr -d '\r' < "$f" > /tmp/rhap_cr && mv /tmp/rhap_cr "$f"
done

echo "======== build EISABus (drvEISABus) ========"
cd "$PROJ" || exit 1
gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386
echo "make exit=$?"

RELOC=""
for f in `find "$SRC" -name EISABus_reloc -print`
do
	RELOC="$f"
	break
done
if [ -z "$RELOC" ] || [ ! -f "$RELOC" ]; then
	echo "FAILED: no EISABus_reloc" >&2
	find "$SRC" \( -name '*reloc*' -o -name '*.config' \) 2>/dev/null | head -40 >&2
	exit 1
fi

PNP=""
for f in `find "$SRC" -name PnPDump -print`
do
	case "$f" in
	*.m|*.h)
		;;
	*)
		PNP="$f"
		break
		;;
	esac
done
if [ -z "$PNP" ] || [ ! -f "$PNP" ]; then
	echo "FAILED: no PnPDump executable" >&2
	find "$SRC" -name 'PnPDump*' 2>/dev/null | head -40 >&2
	exit 1
fi

mkdir -p "$STAGE"
cp -p "$RELOC" "$STAGE/"
cp -p "$PNP" "$STAGE/"
for f in "$PROJ"/*.table; do
	[ -f "$f" ] || continue
	cp -p "$f" "$STAGE/"
done

echo "=== bus-recon done fail=0 built: drvEISABus ==="
ls -l "$STAGE"
```

- [ ] **Step 4: Syntax-check the harness and validate the tool profile (reference only)**

Git Bash or WSL:

```bash
sh -n vm/build-i386-bus-recon.sh && echo "syntax OK"
```

Expected: `syntax OK`. If you have no Unix `sh` on Windows, skip `sh -n` and note that in the Task 4 report.

```powershell
$env:PYTHONPATH = "tools/binrecon"
$env:BINRECON_REFERENCE = "C:\Users\raynorpat\Downloads\test\Drivers\i386\EISABus.config\PnPDump"
$py = ".\.venv-binrecon\Scripts\python.exe"
Get-FileHash -Algorithm SHA256 $env:BINRECON_REFERENCE
& $py -m binrecon validate --profile tools/binrecon/profiles/pnpdump.json
```

Expected: SHA `006DC6BB73CEBC6243DA669E5199AEC808F309E72C3EE617A3FD8ED310364772`. `validate` prints a `reference` line with that SHA. Missing `BINRECON_REBUILT` may error; if so, set `BINRECON_REBUILT` to the same reference path for this validate-only check, or omit rebuilt if the CLI allows reference-only. Do not invent a rebuilt file.

- [ ] **Step 5: Commit**

```powershell
git add tools/binrecon/profiles/pnpdump.json tools/binrecon/profiles/eisabus.json vm/build-i386-bus-recon.sh
git commit -m "binrecon: add PnPDump profile, EISABus rebuilt path, and bus harness"
```

---

### Task 2: Apple PnPDump nlist and reference analyze

**Files:**
- Create: `src/drivers-i386/bus/drvEISABus/reconstruction/pnpdump/nlist.md`

No driver source edits. No guest.

**Interfaces:**
- Consumes: Task 1 `$pnp` profile
- Produces: nlist.md listing ObjC classes, whether `_IOMalloc` / `_IOLog` / `_IOFree` / callouts are local, and the shared-file subset of the nine candidates

- [ ] **Step 1: Confirm both reference SHAs**

```powershell
Get-FileHash -Algorithm SHA256 "C:\Users\raynorpat\Downloads\test\Drivers\i386\EISABus.config\PnPDump"
Get-FileHash -Algorithm SHA256 "C:\Users\raynorpat\Downloads\test\Drivers\i386\EISABus.config\EISABus_reloc"
```

Expected: `006DC6BB73CEBC6243DA669E5199AEC808F309E72C3EE617A3FD8ED310364772` and `8F252AF66CD49A8E03B51E57E90CB613D0B9DC1602263F4B7B6393E483977B23`. If either differs, **BLOCKED**.

- [ ] **Step 2: Dump the tool nlist**

```powershell
$env:PYTHONPATH = "tools/binrecon"
$py = ".\.venv-binrecon\Scripts\python.exe"
& $py -c @"
from pathlib import Path
from binrecon.macho import read_macho
m = read_macho(Path(r'C:\Users\raynorpat\Downloads\test\Drivers\i386\EISABus.config\PnPDump'))
print('sha', m.get('sha256'))
print('filetype', m.get('extensions', {}).get('macho', {}).get('header', {}))
for s in m['symbols']:
    print('%s %s 0x%x %s' % (s['binding'], s.get('section'), s['address'], s['name']))
"@
```

Record every `.objc_class_name_*`, `_main`, `__IOGetCharValues` / `__IOLookupByDeviceName`, `_IOMalloc`, `_IOLog`, `_IOFree`, `_IOGetTimestamp`, `_IOScheduleFunc`, `_NXLock`, `_IODeviceMaster`.

- [ ] **Step 3: Analyze the tool reference**

```powershell
$env:PYTHONPATH = "tools/binrecon"
$env:BINRECON_REFERENCE = "C:\Users\raynorpat\Downloads\test\Drivers\i386\EISABus.config\PnPDump"
$env:BINRECON_REBUILT = $env:BINRECON_REFERENCE
$py = ".\.venv-binrecon\Scripts\python.exe"
& $py -m binrecon analyze --profile tools/binrecon/profiles/pnpdump.json
```

Expected: `complete: true`. Exit 1 is OK. Do not enable Ghidra.

Reuse published `tools/binrecon/out/eisabus/` reference analysis if `complete: true` and SHA `8F252AF6…`. Otherwise analyze the reloc reference with `eisabus.json` the same way. Do not hand-edit published JSON.

- [ ] **Step 4: Write `nlist.md`**

Create `src/drivers-i386/bus/drvEISABus/reconstruction/pnpdump/nlist.md` with:

- Date
- Tool SHA-256 and size 59260
- Classes present vs the nine candidates (shared compile list)
- Whether `IOStubs.m` is required (local `IOMalloc` / `IOLog` / callouts)
- Whether `IODeviceMaster.m` / `NXLock.m` stay (local symbols)
- **BLOCKED** note if a class this spec called kernel-only appears in the tool nlist

If a candidate class is absent, it is **not** a shared compile input and is **not** a dual-target.

- [ ] **Step 5: Commit**

```powershell
git add src/drivers-i386/bus/drvEISABus/reconstruction/pnpdump/nlist.md
git commit -m "drvEISABus: record Apple PnPDump nlist for the shared class split"
```

---

### Task 3: Split `R.m` and wire shared class sources

**Files:**
- Create: `src/drivers-i386/bus/drvEISABus/EISABus.drvproj/PnPDump.tproj/PnPDump.m`
- Create: `src/drivers-i386/bus/drvEISABus/EISABus.drvproj/PnPDump.tproj/IOStubs.m` only if Task 2 nlist requires it
- Modify: `src/drivers-i386/bus/drvEISABus/EISABus.drvproj/PnPDump.tproj/Makefile`
- Modify: `src/drivers-i386/bus/drvEISABus/EISABus.drvproj/PnPDump.tproj/Makefile.preamble`
- Modify: `src/drivers-i386/bus/drvEISABus/EISABus.drvproj/PnPDump.tproj/PB.project`
- Modify: `src/drivers-i386/bus/drvEISABus/EISABus.drvproj/PB.project`
- Delete: `src/drivers-i386/bus/drvEISABus/EISABus.drvproj/PnPDump.tproj/R.m`

Do not compile `dumpConfig.m`. Do not copy lksproj files into the tproj. Do not edit kernel-only lksproj files.

**Interfaces:**
- Consumes: Task 2 shared-file list and IOStubs decision
- Produces: `MFILES` that compile `PnPDump.m` + `IODeviceMaster.m` + `NXLock.m` + nlist-selected `../EISABus.lksproj/*.m` (+ `IOStubs.m` if required)

- [ ] **Step 1: Write `PnPDump.m` from `R.m`'s `main` and `bail`**

Do not use `dumpConfig.m` as compiled source. Keep `R.m`'s control flow (`objc_msgSend`, `sprintf`, `dumpConfig`/`dumpCards`, `argc = argc - 1` parse, `initForBuf:Length:CSN:`, `parseConfig` then `deviceList`). Replace only the Ghidra `FILE`/`stderr`/`unsigned int id` wreckage with normal headers.

```objc
/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

#import <objc/Object.h>
#import <objc/objc-runtime.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import "IODeviceMaster.h"

static char *progname;
static char cmdBuffer[512];
static char valueBuffer[512];

void bail(const char *msg, int code)
{
    fprintf(stderr, "%s: %s %d\n", progname, msg, code);
    exit(1);
}

int main(int argc, char **argv)
{
    int dumpConfig;
    int dumpCards;
    id deviceMaster;
    int result;
    unsigned int objNum;
    const char *kind;
    Class pnpDevResClass;
    Class pnpResClass;
    unsigned int csn;
    char *argPtr;
    unsigned int valueSize;
    id deviceResources;
    int deviceCount;
    id deviceList;
    int deviceIndex;
    id currentConfig;

    progname = argv[0];

    if (argc == 1) {
        dumpConfig = 1;
        dumpCards = 1;
    } else {
        dumpConfig = 0;
        dumpCards = 0;

        while (argc = argc - 1, argc != 0) {
            argv = argv + 1;
            if (**argv == '-') {
                argPtr = *argv;
                while (argPtr = argPtr + 1, *argPtr != '\0') {
                    if (*argPtr == 'c') {
                        dumpCards = 1;
                    } else if (*argPtr == 'd') {
                        dumpConfig = 1;
                    } else {
                        bail("invalid option\n", 0);
                    }
                }
            }
        }
    }

    deviceMaster = objc_msgSend(objc_getClass("IODeviceMaster"), sel_getUid("new"));
    result = (int)objc_msgSend(deviceMaster, sel_getUid("lookUpByDeviceName:objectNumber:deviceKind:"),
                         "EISA0", &objNum, &kind);
    if (result != 0) {
        bail("lookup EISA0 failed", result);
    }

    pnpDevResClass = objc_getClass("PnPDeviceResources");
    pnpResClass = objc_getClass("PnPResources");

    objc_msgSend(pnpDevResClass, sel_getUid("setVerbose:"), 1);

    for (csn = 1; csn <= 254; csn++) {
        valueSize = 0x200;

        if (dumpCards) {
            sprintf(cmdBuffer, "%s( %d", "GetPnPInfo", csn);
            result = (int)objc_msgSend(deviceMaster,
                                sel_getUid("getCharValues:forParameter:objectNumber:count:"),
                                valueBuffer, cmdBuffer, objNum, &valueSize);

            if (result == 0) {
                printf("\n");
                printf("=========================================================\n");
                printf("csn %d:\n", csn);
                printf("=====================\n");
                printf("Resource Description:\n");
                printf("=====================\n");

                deviceResources = objc_msgSend(pnpDevResClass, sel_getUid("alloc"));
                deviceResources = objc_msgSend(deviceResources,
                                              sel_getUid("initForBuf:Length:CSN:"),
                                              valueBuffer, valueSize, csn);

                result = (int)objc_msgSend(deviceResources, sel_getUid("parseConfig"));
                if (result == 0) {
                    exit(1);
                }

                deviceList = objc_msgSend((id)result, sel_getUid("deviceList"));
                deviceCount = (int)objc_msgSend(deviceList, sel_getUid("count"));
                objc_msgSend((id)result, sel_getUid("free"));
            } else {
                continue;
            }
        } else {
            deviceCount = 10;
        }

        if (dumpConfig && deviceCount > 0) {
            for (deviceIndex = 0; deviceIndex < deviceCount; deviceIndex++) {
                sprintf(cmdBuffer, "%s( %d %d", "GetPnPDeviceCfg", csn, deviceIndex);
                valueSize = 0x200;

                result = (int)objc_msgSend(deviceMaster,
                                    sel_getUid("getCharValues:forParameter:objectNumber:count:"),
                                    valueBuffer, cmdBuffer, objNum, &valueSize);

                if (result == 0) {
                    printf("\n");
                    printf("============================================\n");
                    printf("Current configuration for Logical Device %d:\n", deviceIndex);
                    printf("============================================\n");

                    currentConfig = objc_msgSend(pnpResClass, sel_getUid("alloc"));
                    currentConfig = objc_msgSend(currentConfig,
                                                sel_getUid("initFromRegisters:"),
                                                valueBuffer);

                    result = (int)objc_msgSend(currentConfig, sel_getUid("parseConfig"));
                    if (result == 0) {
                        printf("config is nil - continuing\n");
                    } else {
                        objc_msgSend((id)result, sel_getUid("free"));
                    }
                }
            }
        }
    }

    exit(0);
    return 0;
}
```

If `IODeviceMaster.h` in this tproj does not declare `lookUpByDeviceName:objectNumber:deviceKind:`, keep the `objc_msgSend` form above; do not rewrite `main` into `dumpConfig.m`'s message-send syntax.

- [ ] **Step 2: `IOStubs.m` only if nlist requires it**

If Task 2 says local `_IOMalloc` / `_IOLog` / `_IOFree` / callouts, extract **only those functions** from `R.m` (the DriverKit stub section, not the class `@implementation`s) into `IOStubs.m`. Do not copy `char pad[20]` class stubs. If the nlist does not define them locally, do not create the file.

- [ ] **Step 3: Wire Makefiles and PB.project**

`PnPDump.tproj/Makefile.preamble` becomes:

```make
INCLUDED_ARCHS = i386

OTHER_CFLAGS = -Wno-format -I../EISABus.lksproj

OTHER_INCLUDES =

FRAMEWORKS =
```

Do not add `LIBS = -lDriver` unless Task 4's link line names unresolved libDriver symbols. Do not invent `-DDRIVER_PRIVATE` on the tool.

`PnPDump.tproj/Makefile` `MFILES` (drop any class Task 2 excluded; add `IOStubs.m` only if created):

```make
MFILES = PnPDump.m IODeviceMaster.m NXLock.m ../EISABus.lksproj/PnPDependentResources.m ../EISABus.lksproj/PnPDeviceResources.m ../EISABus.lksproj/PnPLogicalDevice.m ../EISABus.lksproj/PnPResource.m ../EISABus.lksproj/PnPResources.m ../EISABus.lksproj/pnpDMA.m ../EISABus.lksproj/pnpIOPort.m ../EISABus.lksproj/pnpIRQ.m ../EISABus.lksproj/pnpMemory.m
```

Keep `HFILES = IODeviceMaster.h NXLock.h`. If `pb_makefiles` rejects `../` in `MFILES`, set `VPATH = ../EISABus.lksproj` in the preamble and list **basenames only** in `MFILES`. Do not copy the `.m` files.

`PnPDump.tproj/PB.project` `CLASSES` must match `MFILES` (same paths or same VPATH basenames).

`EISABus.drvproj/PB.project` `SUBPROJECTS` becomes:

```
        SUBPROJECTS = (EISABus.lksproj, PnPDump.tproj);
```

Leave `EISABus.drvproj/Makefile` `TOOLS = EISABus.lksproj PnPDump.tproj` as it already is.

- [ ] **Step 4: Delete `R.m`**

```powershell
git rm src/drivers-i386/bus/drvEISABus/EISABus.drvproj/PnPDump.tproj/R.m
```

Confirm `dumpConfig.m` is not in `MFILES`.

- [ ] **Step 5: Commit**

```powershell
git add src/drivers-i386/bus/drvEISABus/EISABus.drvproj/PnPDump.tproj/PnPDump.m src/drivers-i386/bus/drvEISABus/EISABus.drvproj/PnPDump.tproj/Makefile src/drivers-i386/bus/drvEISABus/EISABus.drvproj/PnPDump.tproj/Makefile.preamble src/drivers-i386/bus/drvEISABus/EISABus.drvproj/PnPDump.tproj/PB.project src/drivers-i386/bus/drvEISABus/EISABus.drvproj/PB.project
git add src/drivers-i386/bus/drvEISABus/EISABus.drvproj/PnPDump.tproj/IOStubs.m
git commit -m "drvEISABus: split PnPDump main out of R.m and share lksproj PnP classes"
```

If `IOStubs.m` was not created, omit it from `git add`. `git rm` of `R.m` is part of this commit.

---

### Task 4: First dual guest rebuild and worklist

**Files:**
- Create: `src/drivers-i386/bus/drvEISABus/reconstruction/pnpdump/function-worklist.md`
- Create: `src/drivers-i386/bus/drvEISABus/reconstruction/pnpdump/divergences.md`
- Create: `src/drivers-i386/bus/drvEISABus/reconstruction/pnpdump/ledger.json`
- Create: `src/drivers-i386/bus/drvEISABus/reconstruction/pnpdump/source-map.json` if `binrecon source-map` supports the tool; otherwise omit and note in the worklist
- Modify: `PnPDump.tproj/Makefile.preamble` only if the guest log names a missing include or `LIBS`

No instruction-shape edits.

**Interfaces:**
- Consumes: Task 3 sources + Task 1 harness
- Produces: both host Mach-Os, worklist with both rebuilt SHA-256s and the shared-name set

- [ ] **Step 1: Guest rebuild procedure**

Upload harness, sync, build, copy both Mach-Os back, both `parity_check.py` runs.

If the tool fails to compile: fix **only** what the log names (include path, `LIBS = -lDriver`, a typo in `PnPDump.m`). Do not edit kernel-only files. Do not start function-shape edits. If a class `.m` cannot compile in userland without changing a kernel-only file, **BLOCKED**.

If a copied file is not `CE FA ED FE`, re-copy via `tar`. Do not pipe Mach-Os through PowerShell 5.

- [ ] **Step 2: Analyze both rebuilt binaries**

Follow Guest rebuild procedure analyze + `--list` for both profiles. Reuse Task 2 reference analyses when SHAs match.

- [ ] **Step 3: Write the worklist**

`function-worklist.md` must contain:

- Date and worktree branch
- Tool reference SHA `006DC6BB…`, size 59260; rebuilt SHA and size
- Reloc reference SHA `8F252AF6…`, size 100752; rebuilt SHA and size
- `__TEXT,__text` sizes for both pairs
- `parity_check.py` missing counts (must be 0 / 0 on both)
- Shared-name set: names that appear in **both** `--list` outputs among the nlist-selected classes
- Tool-only names (`_main`, MIG wrappers, stubs, `IODeviceMaster`, `NXLock`)
- Full tool `--list` summary: identical / masked-eq / remaining
- Reachability: cheapest remaining rows source-shaped vs already compiler-shaped

Also write a short `divergences.md` heading "Finish campaign" with the two rebuilt SHAs. Do not delete reloc `reconstruction/divergences.md` findings.

Initialize `reconstruction/pnpdump/ledger.json` with the same ledger-v1 vocabulary as `reconstruction/ledger.json` (`unexamined` / `control-flow-confirmed` / `assembly-matched` / `intentional-mismatch`). `reference_sha256` is `006DC6BB73CEBC6243DA669E5199AEC808F309E72C3EE617A3FD8ED310364772`. `rebuilt_sha256` is the Task 4 tool SHA. If `python -m binrecon source-map --help` exists, generate `source-map.json` from the tool reference + `PnPDump.tproj` / shared class sources; otherwise skip.

- [ ] **Step 4: Commit**

```powershell
git add src/drivers-i386/bus/drvEISABus/reconstruction/pnpdump
git commit -m "drvEISABus: record PnPDump instruction-stream baseline worklist"
```

Never stage `out/` or `tools/binrecon/out/`. If preamble/`LIBS` changed to make the guest compile, include those paths in this commit or a preceding `drvEISABus: ` compile-fix commit.

---

### Task 5: Mark baseline-identical rows

**Files:**
- Modify: `src/drivers-i386/bus/drvEISABus/reconstruction/pnpdump/ledger.json`
- Modify: `src/drivers-i386/bus/drvEISABus/reconstruction/ledger.json` (shared names only)
- Modify: both `divergences.md` files (short note only)

No driver source. No rebuild.

**Interfaces:**
- Consumes: Task 4 `--list`
- Produces: `assembly-matched` on every baseline `raw_equal` / `masked_equal` row (tool all such rows; reloc only shared names)

- [ ] **Step 1: Advance the PnPDump ledger**

Every tool `--list` row that is identical or `masked_equal` becomes `assembly-matched` if it is not already. Forward-only. Do not mark compiler-shaped leftovers `assembly-matched`. Reviewer `Pat Raynor`. Set `rebuilt_sha256` to the Task 4 tool SHA.

- [ ] **Step 2: Advance shared reloc rows only**

For each shared name that is identical or `masked_equal` on the **reloc** `--list`, set that reloc ledger entry to `assembly-matched` if it is not already. Do not change kernel-only reloc statuses. Do not skip `unexamined` kernel-only rows down to `assembly-matched`.

- [ ] **Step 3: Note the baseline identical set**

Append under each divergences "Finish campaign" heading: how many tool rows and how many shared reloc rows were already equal.

- [ ] **Step 4: Commit**

```powershell
git add src/drivers-i386/bus/drvEISABus/reconstruction/pnpdump/ledger.json src/drivers-i386/bus/drvEISABus/reconstruction/pnpdump/divergences.md src/drivers-i386/bus/drvEISABus/reconstruction/ledger.json src/drivers-i386/bus/drvEISABus/reconstruction/divergences.md
git commit -m "drvEISABus: mark baseline-identical PnPDump and shared reloc methods"
```

---

### Task 6: Cheapest-first dual instruction-shape grind

**Files:**
- Modify: nlist-selected lksproj class `.m` files under `EISABus.drvproj/EISABus.lksproj/`
- Modify: `PnPDump.tproj/PnPDump.m` (and `IOStubs.m` / `IODeviceMaster.m` / `NXLock.m` only for tool-only functions)
- Modify headers in the lksproj only if a typed rewrite is required
- Modify: `reconstruction/pnpdump/function-worklist.md`, both `divergences.md`, both `ledger.json`, `source-map.json` if present (line numbers if bodies move)

**Interfaces:**
- Consumes: Task 4 worklist + Task 5 regression set
- Produces: every paired tool function equal or accepted; every shared name equal or accepted on both binaries

- [ ] **Step 1: Write named experiment lists into the worklist**

Before the first source edit, append to `function-worklist.md` a short list per remaining non-equal paired **tool** function, cheapest `differing` first, tagged `shared` or `tool-only`. One experiment idea per function to start; add more only after a miss.

Allowed: statement order, local vs expression, signedness of *locals*, loop shape, `if` vs `else if`, operand-reversed `cmp`, declaration order of existing locals.

Forbidden: padding ivars; copying `R.m`'s `pad[20]` stubs into lksproj files; putting `dumpConfig.m` in `MFILES`; inventing temporaries whose only purpose is to pick a register after the list is empty; repeating a reverted experiment; chasing `__text` size; editing kernel-only files; `-D` flags to chase identity.

Compiler-shaped means the `--name` columns differ only by register choice, instruction scheduling, or equivalent gcc 2.x shape — not a wrong constant, missing call, inverted branch, or wrong offset. Different CFLAGS between kernel server and tool are an expected source of compiler-shaped leftovers on shared methods.

- [ ] **Step 2: Loop until every remaining paired tool function is equal or accepted and every shared name meets the dual bar**

For each cheapest still-open source-shaped row:

1. `--name` the current function (both profiles if `shared`). Keep the dump(s).
2. Apply one experiment in the owning `.m` file.
3. Run the Guest rebuild procedure. Both `parity_check.py` runs must stay 0 / 0.
4. Fresh analyze of **both** rebuilt files. `--name` on the new published comparison(s). `--list` to confirm previously identical rows did not regress.
5. **Shared:** match on both (`raw_equal` or `masked_equal`) → keep, both ledgers `assembly-matched`, record both dumps, commit `drvEISABus: ` describing the behaviour. Match on one and miss/regress the other → revert, record both dumps, try the next experiment or accept as compiler-shaped on **both** with both dumps. **Tool-only:** match on PnPDump → keep, PnPDump ledger `assembly-matched`.
6. Miss, no regression → revert the experiment, mark tried in the worklist, try the next item on that function's list.
7. Regression of a closed function → revert, record, continue.
8. Empty list, still not equal → accept: paste `--name` dump(s) under the appropriate `divergences.md`, ledger `intentional-mismatch` with reason `compiler-shaped leftover after exhausted source-shape list` and reviewer `Pat Raynor`. Shared accepts need both dumps. Do not grind further.

One shared cause is one edit cluster (one commit). Relined source-maps when bodies move.

If `--list` grows unpaired functions that are not Kernel Server glue / vers symbols, stop grinding. That is a layout or linkage finding.

If `__text` disagrees after all accepts, record the sizes. Not a failure.

- [ ] **Step 3: Stop condition**

PnPDump `--list`: every hand-written row is identical, `masked_equal`, or accepted. Every shared name meets that bar on the reloc `--list` as well. Kernel-only reloc statuses unchanged except a note they were not reopened. PnPDump ledger has no `unexamined` hand-written function.

---

### Task 7: Campaign close and rbuild gate

**Files:**
- Modify: `reconstruction/pnpdump/function-worklist.md`
- Modify: both `ledger.json` (`rebuilt_sha256` = last kept artifacts)
- Modify: `src/drivers-i386/README` drvEISABus line

No further source-shape edits.

**Interfaces:**
- Consumes: Task 6 stop condition
- Produces: README counts; one guest `rbuild buildpackage` attempt

- [ ] **Step 1: Refresh the worklist summary**

Final SHA-256s for both Mach-Os, `--list` counts (identical / masked-eq / accepted / shared), `__text` sizes, statement that hardware testing is still out.

- [ ] **Step 2: Update README**

Change only the drvEISABus bullet. Keep not-retested. Name both binaries and the new counts. Do not write `complete`. Example shape (fill in the real numbers from `--list`):

```
 * drvEISABus - crashing; reconstructed against the reference binary, PnPDump N/M functions byte-identical under relocation masking remainder accepted as compiler-shaped, shared PnP class methods match on EISABus_reloc; guest-packaged; not yet retested
```

- [ ] **Step 3: Set ledger `rebuilt_sha256` fields**

PnPDump ledger must equal the SHA of the last kept `PnPDump`. Reloc ledger must equal the SHA of the last kept `EISABus_reloc`.

- [ ] **Step 4: `rbuild` once**

On the guest, after the last kept rebuild is synced:

```sh
rbuild buildpackage --arch i386 --dir /build/source/src/drivers-i386/bus/drvEISABus /build/repo /build/built
```

Invoke via `Invoke-RhapSshScript`. Record the exit status and the last log lines in the worklist. If it fails on `drivertools` / APK extract, reconstruction may still close; do not call packaging done and do not paper over it by extracting the APK by hand.

- [ ] **Step 5: Commit**

```powershell
git add src/drivers-i386/bus/drvEISABus/reconstruction/pnpdump/function-worklist.md src/drivers-i386/bus/drvEISABus/reconstruction/pnpdump/ledger.json src/drivers-i386/bus/drvEISABus/reconstruction/ledger.json src/drivers-i386/README
git commit -m "drivers-i386: record drvEISABus PnPDump instruction-stream finish"
```

---

## Spec coverage

| Spec section | Task |
|---|---|
| Phase 0 harness, build drvproj not lksproj-only | 1 |
| `pnpdump.json` Ghidra off; `eisabus.json` rebuilt.path, Ghidra unchanged | 1 |
| nlist authority, IOStubs only if local, kernel-only class stop | 2 |
| `PnPDump.m` from `R.m` main, delete `R.m`, share lksproj `.m`, PB SUBPROJECTS | 3 |
| First dual rebuild, parity 0/0, worklist, both SHAs | 4 |
| Baseline identical → `assembly-matched` (shared reloc only) | 5 |
| Cheapest-first dual grind, allowed/forbidden, one-sided revert | 6 |
| Close, README, `rebuilt_sha256`, one `rbuild` | 7 |
| Guest SSH, no pscp, no `-All`, tar copy | Guest rebuild procedure |
| Frozen kernel-only reloc, no dumpConfig compile, no QEMU, no kernel-7 | Tasks 3–7 constraints |
