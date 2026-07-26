# PowerPC SCSITape Family Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct `src/drvSCSITape` against Apple's four shipped PowerPC binaries — dispositioning all 49 mapped functions, writing the four our tree lacks, and repairing the divergences found.

**Architecture:** Phase 1 produces `src/drvSCSITape/reconstruction/` with per-binary `source-map.json` and `ledger.json` plus one shared `divergences.md`, committed in full before any source change. Phase 2 then changes source one translation unit per commit: the naming and declaration class, the four absent `SCSITape` methods, and the remaining divergences.

**Tech Stack:** Python 3.12 (`.venv-binrecon`), binrecon (`source-map`, `ledger`, `seed_ledger.py`, `filter_named_functions.py`, `selector_check.py`, `ppc_invariant_check.py`), Objective-C and C for Rhapsody DriverKit.

**Spec:** [docs/superpowers/specs/2026-07-26-scsitape-ppc-reconstruction-design.md](../specs/2026-07-26-scsitape-ppc-reconstruction-design.md)

## Global Constraints

- **Nothing here is compile-verified.** There is no PowerPC compiler in this environment (`vm/` holds only `build-i386-*.sh`). This includes the four function bodies Task 9 writes. Do not claim anything "works"; claim only what the checks prove.
- The four reference binaries are read-only inputs outside the repository, under `C:/Users/raynorpat/Downloads/test/Drivers/ppc/SCSITape.config/`. Never modify them or copy them into the repo.
- Analyses of record live under `tools/binrecon/out/{scsitape,scsitape-preload,scsitape-postload,stblocksize}-ppc/published/analysis-reference-ida.json`. Do not regenerate them. `tools/binrecon/out/` is git-ignored — never commit anything under it.
- Neither `source-map` nor `selector_check.py` recurses. Each `--source-dir` must be the subproject directory holding the sources.
- `source-map` requires every analysis function to be named, so each analysis passes through `filter_named_functions.py` first.
- Ledgers are seeded by `seed_ledger.py` and changed only through the `binrecon ledger` CLI — **never hand-edited**.
- `binrecon ledger` transitions are forward-only, one step at a time, with no way back to `unexamined`; `unexamined → intentional-mismatch` needs an intermediate `signature-confirmed`. **Decide an entry's final status before transitioning it.**
- `--reason` is persisted only for `intentional-mismatch`. For every other status, `divergences.md` is the durable record of what was compared.
- A non-intentional divergence is **not** a status: the entry stays `unexamined` with a recorded finding, and Phase 2 repairs it. This is how a reader tells "examined and correct" from "examined and wrong".
- Commit style: subsystem prefix, short, human-readable, no metadata. `drvSCSITape: ` for source and report commits.

### Working commands

Run everything from the repository root. Every task uses these:

```bash
export TAPE="C:/Users/raynorpat/Downloads/test/Drivers/ppc/SCSITape.config"
export RECON="src/drvSCSITape/reconstruction"
export DRV="src/drvSCSITape/SCSITape.drvproj/SCSITape.lksproj"
export PY="./.venv-binrecon/Scripts/python.exe"
```

Every `$PY` invocation needs `PYTHONPATH=tools/binrecon`.

Dump a reference function's disassembly (substitute the analysis path and address):

```bash
PYTHONPATH=tools/binrecon $PY -c "
import json, sys
d = json.load(open(sys.argv[1]))
fn = next(f for f in d['functions'] if f['address'] == int(sys.argv[2]))
print(fn['names'][0], 'size', fn['size'])
for i in fn['instructions']:
    print('  %6d  %-10s %s' % (i['address'], i['mnemonic'], i['operands']))
print('calls:', [c['name'] for c in fn['calls']])
" tools/binrecon/out/scsitape-ppc/analysis.named.json 5000
```

Resolve a `bl sub_XXXX` jump island — the IDA export does not carry the Mach-O relocation table, `read_macho` does:

```bash
PYTHONPATH=tools/binrecon $PY -c "
from binrecon.macho import read_macho
import os
d = read_macho(os.environ['TAPE'] + '/SCSITape_reloc')
for r in d['extensions']['macho']['relocations']:
    if r['section'] == '__TEXT,__text' and 5000 <= r['address'] <= 5432:
        print(r['address'], r['kind'], r['target'], r['external'])
"
```

Imported symbols appear with a `<self>:` prefix in the symbol list — match on the suffix.

Apply a ledger transition:

```bash
PYTHONPATH=tools/binrecon $PY -m binrecon ledger \
  --profile tools/binrecon/profiles/scsitape-ppc.json --ledger "$RECON/SCSITape/ledger.json" \
  --address 5000 --status control-flow-confirmed --reviewer claude
```

Set `BINRECON_REFERENCE` to the matching binary for the profile in use.

### Three techniques spec 2 paid to learn

- **Jump islands resolve through the relocation table**, as above. Two questions declared unanswerable in spec 2 were one lookup away.
- **Message and MiG type descriptors are named symbols in `__TEXT,__const`** (`<arg>Check` / `<arg>Type`), decodable against `src/kernel-7/mach/message.h:707-726`.
- **When a constant or type is unknown, search this tree before recording it as undeterminable.** Every such item in spec 2 was in `src/kernel-7/mach/`, `src/kernel-7/ipc/` or `src/cc-1`.

## File Structure

| Path | Responsibility |
| --- | --- |
| `src/drvSCSITape/reconstruction/divergences.md` | **new.** Prose findings for all four binaries. |
| `src/drvSCSITape/reconstruction/SCSITape/{source-map.json,ledger.json}` | **new.** Driver artifacts. |
| `src/drvSCSITape/reconstruction/PreLoad/{source-map.json,ledger.json}` | **new.** |
| `src/drvSCSITape/reconstruction/PostLoad/{source-map.json,ledger.json}` | **new.** |
| `src/drvSCSITape/reconstruction/stblocksize/{source-map.json,ledger.json}` | **new.** |
| `$DRV/SCSITape.m` | Four absent methods added; divergences repaired. |
| `$DRV/SCSITape.h` | Declarations for the added methods. |
| `$DRV/SCSITapeKern.m` | Divergences repaired. |
| `.gitignore` | Lock rule widened to reach per-binary subdirectories. |
| `tools/binrecon/binrecon/source_map.py` | K&R scanner fix (Task 10). |

---

## Phase 1 — Report

### Task 1: Generate the four artifact sets

**Files:**
- Create: `$RECON/divergences.md`, and `{source-map.json,ledger.json}` under `$RECON/SCSITape/`, `$RECON/PreLoad/`, `$RECON/PostLoad/`, `$RECON/stblocksize/`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: `seed_ledger.py` and `filter_named_functions.py`, both already in `tools/binrecon`.
- Produces: the artifacts every later task reads and updates. Ledger addresses are the stable keys later tasks pass to `binrecon ledger --address`.

- [ ] **Step 1: Widen the lock rule and untrack drvVGA's two locks**

`.gitignore` currently has `**/reconstruction/*.lock`, which matches only directly beneath `reconstruction/`. This plan puts ledgers in per-binary subdirectories, so their locks would be tracked. `drvVGA` has that problem today.

Change the rule to `**/reconstruction/**/*.lock`, keeping the existing `ledger.json.lock` line, then untrack the two existing files:

```bash
cd /d/RhapsodiOS && git rm --cached src/drivers-i386/video/drvVGA/reconstruction/VGA_psdrvr/ledger.json.lock src/drivers-i386/video/drvVGA/reconstruction/VGA_reloc/ledger.json.lock
```

Verify nothing else is tracked:

```bash
cd /d/RhapsodiOS && git ls-files | grep '\.lock$'
```

Expected: no output.

- [ ] **Step 2: Filter each analysis**

```bash
cd /d/RhapsodiOS && for p in scsitape scsitape-preload scsitape-postload stblocksize; do
  PYTHONPATH=tools/binrecon $PY tools/binrecon/filter_named_functions.py \
    tools/binrecon/out/$p-ppc/published/analysis-reference-ida.json \
    tools/binrecon/out/$p-ppc/analysis.named.json
done
```

Confirm the named counts:

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json
for p, expect in (('scsitape',50), ('scsitape-preload',12), ('scsitape-postload',16), ('stblocksize',20)):
    d = json.load(open('tools/binrecon/out/%s-ppc/analysis.named.json' % p))
    print('%-18s %d (expect %d)' % (p, len(d['functions']), expect))
"
```

Expected: 50, 12, 16, 20. Any other number means the inputs differ from what the spec measured — stop and report rather than proceeding.

- [ ] **Step 3: Generate the four source maps**

```bash
cd /d/RhapsodiOS && mkdir -p "$RECON"/{SCSITape,PreLoad,PostLoad,stblocksize}
PYTHONPATH=tools/binrecon $PY -m binrecon source-map --reference-analysis tools/binrecon/out/scsitape-ppc/analysis.named.json --binary "$TAPE/SCSITape_reloc" --source-dir "$DRV" --repo-root . --output "$RECON/SCSITape/source-map.json"
PYTHONPATH=tools/binrecon $PY -m binrecon source-map --reference-analysis tools/binrecon/out/scsitape-preload-ppc/analysis.named.json --binary "$TAPE/PreLoad" --source-dir src/drvSCSITape/PreLoad.tproj --repo-root . --output "$RECON/PreLoad/source-map.json"
PYTHONPATH=tools/binrecon $PY -m binrecon source-map --reference-analysis tools/binrecon/out/scsitape-postload-ppc/analysis.named.json --binary "$TAPE/PostLoad" --source-dir src/drvSCSITape/PostLoad.tproj --repo-root . --output "$RECON/PostLoad/source-map.json"
PYTHONPATH=tools/binrecon $PY -m binrecon source-map --reference-analysis tools/binrecon/out/stblocksize-ppc/analysis.named.json --binary "$TAPE/stblocksize" --source-dir src/drvSCSITape/stblocksize.tproj --repo-root . --output "$RECON/stblocksize/source-map.json"
```

- [ ] **Step 4: Confirm the starting numbers match the spec**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os
recon = os.environ['RECON']
for name in ('SCSITape', 'PreLoad', 'PostLoad', 'stblocksize'):
    m = json.load(open('%s/%s/source-map.json' % (recon, name)))
    print('%-12s mapped=%3d unmapped=%3d dup=%d bnd=%d' % (name, len(m['mapped']), len(m['unmapped']), len(m['duplicate_candidates']), len(m['boundary_disputed'])))
"
```

Expected exactly: `SCSITape 44/6/0/0`, `PreLoad 1/11/0/0`, `PostLoad 1/15/0/0`, `stblocksize 3/17/0/0`. Different numbers mean the inputs are not what the spec measured — stop and report.

- [ ] **Step 5: Seed the four ledgers**

```bash
cd /d/RhapsodiOS && for n in SCSITape PreLoad PostLoad stblocksize; do
  case $n in
    SCSITape) B="$TAPE/SCSITape_reloc";; PreLoad) B="$TAPE/PreLoad";;
    PostLoad) B="$TAPE/PostLoad";; stblocksize) B="$TAPE/stblocksize";;
  esac
  PYTHONPATH=tools/binrecon $PY tools/binrecon/seed_ledger.py "$RECON/$n/source-map.json" "$B" "$RECON/$n/ledger.json"
done
```

Expected: `50 entries`, `12 entries`, `16 entries`, `20 entries`.

- [ ] **Step 6: Write the divergences skeleton**

Create `$RECON/divergences.md` with the frame and the facts that need no examination:

```markdown
# drvSCSITape divergences

References, all under `SCSITape.config`:

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `SCSITape_reloc` | 47624 | `ABB8D7E5FDEB9188A4C58D10AE6A7A1313A79EFBE49513AD3804E386BB65131A` |
| `PreLoad` | 9060 | `177355F05BDCBD6EDE34121F93E6B6A176B105ACF8EAD1945761A9E1D3BFB60A` |
| `PostLoad` | 21520 | `A6025294E3E1AB96270BBE3AFAD73A3885C7C5F44644241E44DD553632699F87` |
| `stblocksize` | 13408 | `E36D1320E5543E9F8B46D522D19150DC6BA21B348C6ECAB8D13AE9CF83BC7648` |

Analysis: IDA 9.2. Ghidra and angr are i386-only and cannot analyse these
binaries.

No PowerPC build exists in this environment, so nothing recorded here is
compile-verified — including the function bodies the fix pass writes. Every
claim rests on the reference disassembly.

## Starting state

| Artifact | Named | Mapped | Unmapped |
| --- | --- | --- | --- |
| `SCSITape_reloc` | 50 | 44 | 6 |
| `PreLoad` | 12 | 1 | 11 |
| `PostLoad` | 16 | 1 | 15 |
| `stblocksize` | 20 | 3 | 17 |

## Out of scope

**94 jump islands.** `SCSITape_reloc`'s IDA analysis finds 144 functions; 94 are
unnamed 16-byte `lis`/`mr`/`mtctr`/`bctr` sequences — build-generated branch glue
for calls exceeding the PowerPC branch displacement. `filter_named_functions.py`
excludes them.

**crt and dyld startup, six per helper.** `start`, `__start`,
`__call_mod_init_funcs`, `__dyld_init_check`, `dyld_stub_binding_helper` and
`__dyld_func_lookup` come from the C runtime and the dynamic linker, not from
our source.

**Every 36-byte `__picsymbol_stub` entry.** 5 in `PreLoad`, 9 in `PostLoad`, 10
in `stblocksize` — confirmed against each binary's stub-section size (180, 324
and 360 bytes, all exact multiples of 36), and matching the libc names one for
one (`_printf`, `_ioctl`, `_open`, `_atoi`, `_strlen`, `_strcmp`, `_bzero`,
`_close`, `_exit`, `_perror`, `_sprintf`, `_unlink`).

Unlike the jump islands these are *named*, so `filter_named_functions.py` cannot
remove them and they stay in the `unmapped` bucket. They are explained here
rather than filtered out of sight.

**Two build-generated classes.**
`+[SCSITapeKernelServerInstance kernelServerInstance]` (20 bytes) and
`+[SCSITapeVersion driverKitVersionForSCSITape]` (16) are emitted by the Kernel
Server build from the project's own settings, exactly as `SCSIServer`'s pair
were. They remain `unmapped` permanently.
```

- [ ] **Step 7: Validate and commit**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import os
from pathlib import Path
from binrecon.identity import identify
from binrecon.ledger import load_ledger
from binrecon.schema import load_source_map
recon, tape = Path(os.environ['RECON']), os.environ['TAPE']
for name, binary in (('SCSITape','SCSITape_reloc'), ('PreLoad','PreLoad'), ('PostLoad','PostLoad'), ('stblocksize','stblocksize')):
    load_ledger(recon / name / 'ledger.json', identify(Path(tape) / binary), None)
    load_source_map(recon / name / 'source-map.json', repo_root=Path('.'))
    print(name, 'validates')
"
```

Expected: four `validates` lines.

```bash
cd /d/RhapsodiOS && git add "$RECON" .gitignore && git commit -m "drvSCSITape: add the PowerPC reconstruction source maps and ledgers"
```

---

### Task 2: Examine the SCSITape accessors and lifecycle

**Files:**
- Modify: `$RECON/SCSITape/ledger.json`, `$RECON/divergences.md`

**Interfaces:**
- Consumes: Task 1's artifacts.
- Produces: 20 ledger entries dispositioned; findings for Phase 2.

**The 20 functions**, all mapped to `SCSITape.m`:

| Address | Size | Function | Source line |
| --- | --- | --- | --- |
| 16 | 20 | `+[SCSITape requiredProtocols]` | 62 |
| 36 | 440 | `+[SCSITape probe:]` | 69 |
| 1544 | 144 | `-[SCSITape free]` | 318 |
| 1736 | 244 | `-[SCSITape getIntValues:forParameter:count:]` | 330 |
| 2028 | 16 | `-[SCSITape target]` | 364 |
| 2044 | 16 | `-[SCSITape lun]` | 369 |
| 2060 | 16 | `-[SCSITape controller]` | 374 |
| 2076 | 20 | `-[SCSITape isInitialized]` | 379 |
| 2096 | 20 | `-[SCSITape didWrite]` | 384 |
| 2116 | 24 | `-[SCSITape isFixedBlock]` | 389 |
| 2140 | 20 | `-[SCSITape senseDataValid]` | 398 |
| 2160 | 20 | `-[SCSITape forceSenseDataInvalid]` | 403 |
| 2180 | 16 | `-[SCSITape senseDataPtr]` | 409 |
| 2196 | 16 | `-[SCSITape blockSize]` | 414 |
| 2212 | 20 | `-[SCSITape suppressIllegalLength]` | 419 |
| 2232 | 16 | `-[SCSITape setSuppressIllegalLength:]` | 424 |
| 2248 | 16 | `-[SCSITape setIgnoreCheckCondition:]` | 435 |
| 2264 | 16 | `-[SCSITape majorDevNum]` | 441 |
| 2280 | 168 | `-[SCSITape acquireDevice]` | 457 |
| 2464 | 128 | `-[SCSITape releaseDevice]` | 472 |

- [ ] **Step 1: Read the fourteen accessors as a group**

Addresses 2028 through 2264 are 16–24 byte accessors. Dump all fourteen and read them together: each should be a single load from a fixed instance-variable offset, or a single store. Recover the **ivar offset each one uses**, and check our source's `@interface` layout produces the same offsets in the same order. A shifted ivar layout would make every accessor read the wrong field while each one individually looks correct — the same class of defect as `SCSIServer`'s reservation-structure check.

Record the recovered offset table in the finding or the block summary, whichever applies.

- [ ] **Step 2: Read the six substantial functions**

Dump 16, 36, 1544, 1736, 2280 and 2464 and compare each to its source site. `+[SCSITape probe:]` at 440 bytes is the largest; `-[SCSITape free]`, `getIntValues:forParameter:count:`, `acquireDevice` and `releaseDevice` follow.

Two patterns recurred throughout `SCSIServer` and are worth checking for here: extra `IOLog` calls our source makes that the reference does not, and `objc_getClass()` calls where the reference loads a static class reference.

- [ ] **Step 3: Disposition each entry**

For each of the 20, choose `assembly-matched` (our source accounts for every instruction *and* the data it depends on), `control-flow-confirmed` (differences cosmetic), or `intentional-mismatch` (deliberate, needs reason and reviewer). A non-intentional divergence leaves the entry `unexamined` with a `## Finding:` section.

```bash
cd /d/RhapsodiOS && BINRECON_REFERENCE="$TAPE/SCSITape_reloc" PYTHONPATH=tools/binrecon $PY -m binrecon ledger \
  --profile tools/binrecon/profiles/scsitape-ppc.json --ledger "$RECON/SCSITape/ledger.json" \
  --address 2028 --status assembly-matched --reviewer claude
```

Reaching `assembly-matched` from `unexamined` takes three calls (`signature-confirmed`, then `control-flow-confirmed`, then `assembly-matched`).

- [ ] **Step 4: Record findings and the block summary**

Append a `## Finding:` section per divergence and a `## SCSITape accessors and lifecycle` summary stating, per function, what was compared and what was found. `--reason` is dropped for these statuses, so this is the durable record.

- [ ] **Step 5: Verify the block**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os
e = json.load(open(os.environ['RECON'] + '/SCSITape/ledger.json'))['entries']
for x in [y for y in e if y['address'] < 2600]:
    print('%6d  %-52s %s' % (x['address'], x['names'][0], x['status']))
"
```

Every `unexamined` entry printed must have a matching finding.

- [ ] **Step 6: Commit**

```bash
cd /d/RhapsodiOS && git add "$RECON" && git commit -m "drvSCSITape: disposition the accessors and device lifecycle"
```

---

### Task 3: Examine the SCSI command methods

**Files:**
- Modify: `$RECON/SCSITape/ledger.json`, `$RECON/divergences.md`

**Interfaces:**
- Consumes: Task 1's artifacts.
- Produces: 9 ledger entries dispositioned, including the jump-table comparison the spec calls for.

**The nine functions**, all in `SCSITape.m`:

| Address | Size | Function | Source line |
| --- | --- | --- | --- |
| 2608 | 420 | `-[SCSITape stInquiry:]` | 484 |
| 3124 | 160 | `-[SCSITape stTestReady]` | 569 |
| 3332 | 164 | `-[SCSITape stCloseFile]` | 606 |
| 3560 | 132 | `-[SCSITape stRewind]` | 626 |
| 3740 | 368 | `-[SCSITape requestSense:]` | 648 |
| 4172 | 332 | `-[SCSITape stModeSelect:]` | 696 |
| 4584 | 336 | `-[SCSITape stModeSense:]` | 748 |
| 5000 | 432 | `-[SCSITape executeMTOperation:]` | 801 |
| 5496 | 260 | `-[SCSITape setBlockSize:]` | 895 |

- [ ] **Step 1: Compare `executeMTOperation:`'s jump table — the spec's §2.1 check**

This function owns the 14 `PPC_RELOC_SECTDIFF` relocations at `0x2e34`–`0x2e68`, the fixups whose 32-bit wrap broke the exporter in spec 1. Resolve the table:

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os, struct
from binrecon.macho import read_macho
p = os.environ['TAPE'] + '/SCSITape_reloc'
d = read_macho(p); raw = open(p, 'rb').read()
const = next(s for s in d['sections'] if s['name'] == '__TEXT,__const')
a = json.load(open('tools/binrecon/out/scsitape-ppc/analysis.named.json'))
def owner(addr):
    for f in a['functions']:
        if f['address'] <= addr < f['address'] + f['size']: return f['names'][0]
    return '?'
for i in range(14):
    v = struct.unpack_from('>i', raw, const['offset'] + i*4)[0]
    t = (0x2e34 + v) & 0xFFFFFFFF
    print('  case %2d -> 0x%04x  %s' % (i, t, owner(t)))
"
```

Expected: 14 entries, all inside `-[SCSITape executeMTOperation:]`, with distinct targets for cases 0–6 (`0x140c`, `0x1418`, `0x1448`, `0x1478`, `0x14a4`, `0x14d4`, `0x14dc`) and cases 7–13 all collapsing onto `0x14f0`.

Then compare against our `SCSITape.m:801` `switch`: the same case set, the same order, and the same collapse of 7–13 onto one body. A reordered table is the same class of defect as `SCSIServer`'s mis-wired MiG dispatch table — invisible in our source alone. Record the comparison as a finding whether or not it diverges, since the spec requires the check be shown.

- [ ] **Step 2: Read the other eight**

Dump each and compare to its source site. These issue SCSI commands, so check the **CDB each one builds** — opcode, and the byte offsets it writes into the command block — against our source. A wrong opcode or a field at the wrong offset is a functional defect that reads plausibly in isolation.

- [ ] **Step 3: Disposition each entry**

Use Task 2 Step 3's command form, per address.

- [ ] **Step 4: Record findings and a `## SCSI command methods` summary**

- [ ] **Step 5: Verify the block**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os
e = json.load(open(os.environ['RECON'] + '/SCSITape/ledger.json'))['entries']
for x in [y for y in e if 2600 <= y['address'] < 6000]:
    print('%6d  %-52s %s' % (x['address'], x['names'][0], x['status']))
"
```

- [ ] **Step 6: Commit**

```bash
cd /d/RhapsodiOS && git add "$RECON" && git commit -m "drvSCSITape: disposition the SCSI command methods"
```

---

### Task 4: Examine the SCSITape.m C helpers

**Files:**
- Modify: `$RECON/SCSITape/ledger.json`, `$RECON/divergences.md`

**Interfaces:**
- Consumes: Task 1's artifacts.
- Produces: 6 ledger entries dispositioned.

**The six functions**, all in `SCSITape.m`:

| Address | Size | Function | Source line |
| --- | --- | --- | --- |
| 6748 | 124 | `_moveString` | 1093 |
| 6872 | 32 | `_assign_cdb_c6s_len` | 1127 |
| 6904 | 24 | `_assign_msbd_numblocks` | 1154 |
| 6928 | 24 | `_assign_msbd_blocklength` | 1167 |
| 6952 | 40 | `_cdb_c6s_len_value` | 1180 |
| 6992 | 20 | `_er_info_value` | 1190 |

- [ ] **Step 1: Read all six together**

These are bit-field accessors over SCSI command and sense structures — `cdb_c6s`, `msbd` and `er_info`. Read them as a set and recover the **bit positions and widths** each one packs or extracts. Four of the six are under 40 bytes, so each is a handful of `rlwinm`/`rlwimi` instructions whose shift and mask operands give the field layout directly.

Check our source's corresponding structure definitions produce the same layout. A field at the wrong bit offset is invisible in any single accessor and corrupts every command built with it.

- [ ] **Step 2: Disposition each entry**

Use Task 2 Step 3's command form, per address.

- [ ] **Step 3: Record findings and a `## SCSITape.m C helpers` summary**

Include the recovered bit-layout table — later tasks writing the absent methods will need it, since those methods build the same structures.

- [ ] **Step 4: Verify and commit**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os
e = json.load(open(os.environ['RECON'] + '/SCSITape/ledger.json'))['entries']
for x in [y for y in e if 6700 <= y['address'] < 7000]:
    print('%6d  %-52s %s' % (x['address'], x['names'][0], x['status']))
"
```

```bash
cd /d/RhapsodiOS && git add "$RECON" && git commit -m "drvSCSITape: disposition the command-structure helpers"
```

---

### Task 5: Examine SCSITapeKern.m

**Files:**
- Modify: `$RECON/SCSITape/ledger.json`, `$RECON/divergences.md`

**Interfaces:**
- Consumes: Task 1's artifacts.
- Produces: 9 ledger entries dispositioned. This completes `SCSITape_reloc`'s 44 mapped functions.

**The nine functions**, all in `SCSITapeKern.m`:

| Address | Size | Function | Source line |
| --- | --- | --- | --- |
| 7424 | 184 | `_st_devsw_init` | 87 |
| 7640 | 508 | `_stopen` | 121 |
| 8228 | 196 | `_stclose` | 227 |
| 8440 | 36 | `_stread` | 252 |
| 8492 | 36 | `_stwrite` | 258 |
| 8544 | 872 | `_st_rw` | 265 |
| 9544 | 740 | `_stioctl` | 434 |
| 10332 | 840 | `_st_doiocsrq` | 574 |
| 11300 | 20 | `_read_er_info_low_24` | 739 |

- [ ] **Step 1: Read `_st_devsw_init` first**

It installs the device-switch entry points. Recover **which slot each function pointer goes into**, because that mapping determines what the kernel calls for read, write, ioctl and so on. Our source must install the same functions in the same slots — a transposition here misroutes every operation and is invisible in the individual functions.

- [ ] **Step 2: Read the three large functions**

`_st_rw` (872), `_st_doiocsrq` (840) and `_stioctl` (740) are the bulk of this file. For each, compare against its source site with attention to the **error paths**: which errno each failure returns, and in what order the checks occur. `SCSIServer`'s examination found several divergences that lived only in error handling.

- [ ] **Step 3: Read the remaining five**

`_stopen`, `_stclose`, `_stread`, `_stwrite`, `_read_er_info_low_24`. The two 36-byte ones are thin wrappers; confirm what each delegates to.

- [ ] **Step 4: Disposition each entry**

Use Task 2 Step 3's command form, per address.

- [ ] **Step 5: Record findings and a `## SCSITapeKern.m` summary**

- [ ] **Step 6: Verify all 44 mapped entries are dispositioned**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os
from collections import Counter
e = json.load(open(os.environ['RECON'] + '/SCSITape/ledger.json'))['entries']
mapped = [x for x in e if x['source_path']]
print('mapped entries:', len(mapped))
print(Counter(x['status'] for x in mapped))
print('open:', [x['names'][0] for x in mapped if x['status'] == 'unexamined'])
"
```

Expected: `mapped entries: 44`. Every open entry must have a finding.

- [ ] **Step 7: Commit**

```bash
cd /d/RhapsodiOS && git add "$RECON" && git commit -m "drvSCSITape: disposition the kernel device-switch layer"
```

---

### Task 6: Examine the three helper binaries

**Files:**
- Modify: `$RECON/PreLoad/ledger.json`, `$RECON/PostLoad/ledger.json`, `$RECON/stblocksize/ledger.json`, `$RECON/divergences.md`

**Interfaces:**
- Consumes: Task 1's artifacts.
- Produces: 5 mapped entries dispositioned, and the out-of-scope entries recorded.

**The five mapped functions:**

| Binary | Address | Size | Function | Source |
| --- | --- | --- | --- | --- |
| `PreLoad` | — | 276 | `_main` | `PreLoad.tproj/PreLoad.m` |
| `PostLoad` | — | 592 | `_main` | `PostLoad.tproj/PostLoad.m` |
| `stblocksize` | — | 624 | `_main` | `stblocksize.tproj/stblocksize.c` |
| `stblocksize` | — | 148 | `_read_block_limits` | `stblocksize.tproj/stblocksize.c` |
| `stblocksize` | — | 56 | `_usage` | `stblocksize.tproj/stblocksize.c` |

The helper analyses were not enumerated at plan time, so read the exact addresses from the seeded ledgers before starting:

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os
for n in ('PreLoad', 'PostLoad', 'stblocksize'):
    e = json.load(open('%s/%s/ledger.json' % (os.environ['RECON'], n)))['entries']
    print(n, [(x['address'], x['names'][0], x['size']) for x in e if x['source_path']])
"
```

- [ ] **Step 1: Examine the five**

Dump each from its own analysis (`tools/binrecon/out/{scsitape-preload,scsitape-postload,stblocksize}-ppc/analysis.named.json`) and compare to its source. These are small user-space programs, so also compare **what each prints and the exact argument handling** — a `usage` string or an option letter that differs is a real divergence and cheap to check.

- [ ] **Step 2: Disposition the five mapped entries**

Use Task 2 Step 3's command form with the matching profile and `BINRECON_REFERENCE` per binary: `tools/binrecon/profiles/scsitape-preload-ppc.json`, `scsitape-postload-ppc.json`, `stblocksize-ppc.json`.

- [ ] **Step 3: Disposition the out-of-scope entries**

The crt/dyld routines and `__picsymbol_stub` entries are not our source and never will be. Set each to `intentional-mismatch` with a reason naming its class, so no entry is left implying unfinished work:

```bash
cd /d/RhapsodiOS && BINRECON_REFERENCE="$TAPE/PreLoad" PYTHONPATH=tools/binrecon $PY -m binrecon ledger \
  --profile tools/binrecon/profiles/scsitape-preload-ppc.json --ledger "$RECON/PreLoad/ledger.json" \
  --address <addr> --status signature-confirmed --reviewer claude
```

then the second step to `intentional-mismatch` with `--reason "C runtime startup from crt/dyld, not driver source"` or `--reason "__picsymbol_stub entry for a dynamically bound libc call, not driver source"` as appropriate.

- [ ] **Step 4: Record `_do_ioc` as absent**

`stblocksize`'s `_do_ioc` (228 bytes) has no counterpart in our source. Write a `## Finding:` describing what it does from its disassembly — Task 10 writes the body from this description, so state what it calls, its arguments, its return values and its error paths. Where you cannot determine something, say so explicitly rather than writing a plausible guess.

- [ ] **Step 5: Verify and commit**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os
from collections import Counter
for n in ('PreLoad', 'PostLoad', 'stblocksize'):
    e = json.load(open('%s/%s/ledger.json' % (os.environ['RECON'], n)))['entries']
    print(n, Counter(x['status'] for x in e))
"
```

```bash
cd /d/RhapsodiOS && git add "$RECON" && git commit -m "drvSCSITape: disposition the user-space helpers"
```

---

### Task 7: Document the four absent methods and finish the report

**Files:**
- Modify: `$RECON/SCSITape/ledger.json`, `$RECON/divergences.md`

**Interfaces:**
- Consumes: Tasks 2–6.
- Produces: the completed Phase 1 report. Tasks 9 and 10 write source from its descriptions.

**This task's descriptions are the input Tasks 9 and 10 write driver source from, with no compiler to catch a misreading.** Spec 2's review found four material errors in exactly this kind of description — a wrong global name, a third of a function omitted, and two inverted readings. Give these the care that history justifies.

- [ ] **Step 1: Describe the four absent methods**

| Address | Size | Method |
| --- | --- | --- |
| — | 908 | `-[SCSITape initSCSITape:target:lun:controller:majorDeviceNumber:]` |
| — | 832 | `-[SCSITape executeRequest:buffer:client:senseBuf:]` |
| — | 236 | `-[SCSITape reserveAllLuns]` |
| — | 128 | `-[SCSITape releaseAllLuns]` |

Read their addresses from the ledger's unmapped entries. For each, dump the disassembly and write a description covering: what it calls (resolving every jump island through the relocation table), its arguments and their types, what it returns on each path, which instance variables it reads and writes at which offsets, and its error handling.

The two large ones warrant the most care. Cross-check the ivar offsets against the accessor table Task 2 recovered and the structure layouts Task 4 recovered — those methods build the same structures.

- [ ] **Step 2: Add the summary table**

Add a `## Summary` section near the top counting statuses across all four ledgers, and stating plainly how many functions were read at instruction level, how many are absent, and how many entries remain open with findings.

- [ ] **Step 3: Validate all four ledgers**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import os
from pathlib import Path
from binrecon.identity import identify
from binrecon.ledger import load_ledger
recon, tape = Path(os.environ['RECON']), os.environ['TAPE']
for name, binary in (('SCSITape','SCSITape_reloc'), ('PreLoad','PreLoad'), ('PostLoad','PostLoad'), ('stblocksize','stblocksize')):
    load_ledger(recon / name / 'ledger.json', identify(Path(tape) / binary), None)
    print(name, 'validates')
"
```

- [ ] **Step 4: Commit**

```bash
cd /d/RhapsodiOS && git add "$RECON" && git commit -m "drvSCSITape: record the PowerPC reconstruction divergences"
```

---

## Phase 2 — Fix

### Task 8: Naming, declarations and compile errors

**Files:**
- Modify: whichever of `$DRV/SCSITape.m`, `$DRV/SCSITape.h`, `$DRV/SCSITapeKern.m`, `src/drvSCSITape/stblocksize.tproj/stblocksize.c` the findings name.

**Interfaces:**
- Consumes: Phase 1's findings.
- Produces: `selector_check.py` at exit 0 — a gate every later task must keep green.

- [ ] **Step 1: Establish the current state**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY tools/binrecon/selector_check.py "$TAPE/SCSITape_reloc" "$DRV"; echo "exit=$?"
```

Record the output. `renames` and `duplicates` must both reach 0; the two build-generated classes will remain in `missing`.

- [ ] **Step 2: Fix every rename and duplicate**

A rename is a selector of ours that matches a reference name only after dropping a leading underscore — the defect `SCSIServer` had twice. A duplicate is the same, where a correctly-named sibling already exists, so the underscored definition is redundant and must be deleted rather than renamed. Update every send site too, including in comments; find them with `grep -rn`.

- [ ] **Step 3: Fix the compile-error class from Phase 1's findings**

Anything Phase 1 recorded as a hard compile error — a call with the wrong argument count against a prototype in scope, a `void` function's result assigned to a value, an undeclared protocol or type. These carry no uncompiled body and are in scope regardless of size.

- [ ] **Step 4: Verify the gate**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY tools/binrecon/selector_check.py "$TAPE/SCSITape_reloc" "$DRV"; echo "exit=$?"
```

Expected: `renames (0)`, `duplicates (0)`, `exit=0`.

- [ ] **Step 5: Update the ledger and commit**

Transition each repaired entry to the status the evidence now supports, then:

```bash
cd /d/RhapsodiOS && git add "$DRV" src/drvSCSITape "$RECON" && git commit -m "drvSCSITape: correct selector names and declaration errors"
```

---

### Task 9: Write the four absent SCSITape methods

**Files:**
- Modify: `$DRV/SCSITape.m`, `$DRV/SCSITape.h`
- Modify: `$RECON/SCSITape/ledger.json`, `$RECON/divergences.md`

**Interfaces:**
- Consumes: Task 7's descriptions, Task 2's ivar offset table, Task 4's structure bit layouts.
- Produces: four methods defined and declared; their ledger entries mapped and dispositioned.

**Nothing here is compile-verified.** Write each body from the reference disassembly directly, not from a paraphrase of it.

- [ ] **Step 1: Write `-[SCSITape reserveAllLuns]` and `-[SCSITape releaseAllLuns]`**

The two small ones first (236 and 128 bytes). Re-read each function's disassembly before writing it — do not work from Task 7's prose alone; the prose exists to orient you, the instructions are the specification.

Place each at its address-order position among the existing methods, and declare it in `SCSITape.h` if the reference shows it called from another translation unit.

- [ ] **Step 2: Commit**

```bash
cd /d/RhapsodiOS && git add "$DRV" && git commit -m "drvSCSITape: add reserveAllLuns and releaseAllLuns"
```

- [ ] **Step 3: Write `-[SCSITape executeRequest:buffer:client:senseBuf:]`**

832 bytes. Re-read the disassembly. This is the driver's central request path, so check every call it makes against the relocation table rather than inferring from names, and cross-check the structure fields it fills against Task 4's recovered bit layouts.

- [ ] **Step 4: Commit**

```bash
cd /d/RhapsodiOS && git add "$DRV" && git commit -m "drvSCSITape: add executeRequest:buffer:client:senseBuf:"
```

- [ ] **Step 5: Write `-[SCSITape initSCSITape:target:lun:controller:majorDeviceNumber:]`**

908 bytes, the largest. Re-read the disassembly. Pay particular attention to which instance variables it initialises and at which offsets — cross-check against Task 2's accessor offset table, since a mismatch there would make every accessor read a field this method never set.

- [ ] **Step 6: Commit**

```bash
cd /d/RhapsodiOS && git add "$DRV" && git commit -m "drvSCSITape: add initSCSITape:target:lun:controller:majorDeviceNumber:"
```

- [ ] **Step 7: Verify the gate and update the ledger**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY tools/binrecon/selector_check.py "$TAPE/SCSITape_reloc" "$DRV"; echo "exit=$?"
```

Expected: still `renames (0)`, `duplicates (0)`, `exit=0`, and the four methods no longer in `missing`.

Transition each of the four ledger entries with `--source-path` and `--source-line` pointing at the new definitions.

```bash
cd /d/RhapsodiOS && git add "$RECON" && git commit -m "drvSCSITape: map the four recovered SCSITape methods"
```

---

### Task 10: Fix the source-map K&R scanner so `do_ioc` maps

> **Task repurposed after Task 6.** This task originally said to *write* `_do_ioc`. That premise is
> void: `stblocksize.c:170` already defines it, in K&R style, and it matches the reference
> instruction for instruction — verified independently three times. The function was reported
> unmapped because of a bug in binrecon's scanner, not because it is missing. **Do not write any
> function body in this task.**

**Files:**
- Modify: `tools/binrecon/binrecon/source_map.py`
- Test: `tools/binrecon/tests/test_source_map_builder.py`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `source-map` recording K&R definitions whose parameter declarations are not indented, so `stblocksize`'s regenerated map reports 4 mapped / 16 unmapped in Task 12.

**The bug.** `source_map.py`'s forward scan treats an unindented line as a structural boundary. Its guard comment says K&R parameter declarations are indented, but this codebase's idiom allows column 0:

```c
int
do_ioc(srp)
struct scsi_req *srp;
{
```

`struct scsi_req *srp;` matches `_C_DEFINITION`, so the scan concludes the definition never resolved and no site is recorded. This is the only unindented-K&R definition across `src/drvSCSITape` and `src/drvSCSIServer`, so no existing reconstruction's numbers change — but the scanner is wrong for a construct this tree uses.

- [ ] **Step 1: Write the failing test**

Add to `tools/binrecon/tests/test_source_map_builder.py`, following the file's existing fixture style for source scanning:

```python
def test_kandr_definition_with_unindented_parameters_is_recorded(tmp_path):
    source = tmp_path / "kandr.c"
    source.write_text(
        "int\n"
        "do_ioc(srp)\n"
        "struct scsi_req *srp;\n"
        "{\n"
        "    return 0;\n"
        "}\n",
        encoding="utf-8",
    )

    sites = scan_source_sites([tmp_path], repo_root=tmp_path)

    assert [(site["name"], site["line"]) for site in sites] == [("do_ioc", 2)]
```

Read the module first for the real scanning entry point and the shape it returns — use those names rather than the ones above if they differ, and say so in your report.

- [ ] **Step 2: Run it to verify it fails**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -m pytest tools/binrecon/tests/test_source_map_builder.py -q -k kandr
```

Expected: FAIL — no site recorded.

- [ ] **Step 3: Fix the guard**

Make the scan recognise a K&R parameter declaration at column 0. The `kandr` flag is already computed from the definition line ending in `)`; the fix is to stop treating a following `;`-terminated line as a structural boundary while that flag is set. Keep the existing behaviour for indented parameters and for genuine prototypes — a line ending in `;` that is *not* part of a K&R parameter list must still terminate the scan.

- [ ] **Step 4: Verify the fix and the whole suite**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -m pytest tools/binrecon -q
```

Expected: all pass, including the new test.

Then confirm the real map now records it:

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -m binrecon source-map \
  --reference-analysis tools/binrecon/out/stblocksize-ppc/analysis.named.json \
  --binary "$TAPE/stblocksize" --source-dir src/drvSCSITape/stblocksize.tproj \
  --repo-root . --output .superpowers/sdd/stblocksize-check.json
PYTHONPATH=tools/binrecon $PY -c "
import json
m = json.load(open('.superpowers/sdd/stblocksize-check.json'))
print('mapped', len(m['mapped']), 'unmapped', len(m['unmapped']))
print([e['reference_names'][0] for e in m['mapped']])
"
```

Expected: `mapped 4 unmapped 16`, with `_do_ioc` among the mapped. This is a throwaway check written to the git-ignored scratch directory; the committed map is regenerated in Task 12.

- [ ] **Step 5: Commit**

```bash
cd /d/RhapsodiOS && git add tools/binrecon/binrecon/source_map.py tools/binrecon/tests/test_source_map_builder.py && git commit -m "binrecon: record K&R definitions whose parameters are not indented"
```

Note the `binrecon: ` prefix — this task changes shared tooling, not driver source.

---

### Task 11: Fix the divergences Phase 1 found

**Files:**
- Modify: whichever source files Phase 1's findings name.

**Interfaces:**
- Consumes: every `## Finding:` in `divergences.md`, and every ledger entry Tasks 2–6 left `unexamined` with a finding.
- Produces: each such entry either repaired and dispositioned, or left open with a stated reason.

**This task's content comes from Phase 1 and cannot be enumerated at plan time.** The procedure is fixed, not the list.

**Scope:** small, precisely-evidenced corrections inside existing bodies — the class spec 2's Task 12 handled. A divergence too large to repair as a targeted correction stays open with an explicit statement of why, per the spec's §4.2 item 4.

- [ ] **Step 1: List the work**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os
recon = os.environ['RECON']
for n in ('SCSITape', 'PreLoad', 'PostLoad', 'stblocksize'):
    e = json.load(open('%s/%s/ledger.json' % (recon, n)))['entries']
    todo = [x for x in e if x['status'] == 'unexamined' and x['source_path']]
    for x in todo:
        print('%-12s %6d  %-52s %s:%s' % (n, x['address'], x['names'][0], x['source_path'].split('/')[-1], x['source_line']))
"
```

Every address printed must have a `## Finding:` section. An open entry with no finding means an earlier task skipped it — go back rather than inventing a fix.

- [ ] **Step 2: Fix one function per commit**

For each, in address order: re-read the reference disassembly, apply what the finding calls for, transition the ledger entry, and commit naming the function.

```bash
cd /d/RhapsodiOS && git add src/drvSCSITape "$RECON" && git commit -m "drvSCSITape: <what changed> in <function>"
```

If re-reading shows the finding was wrong, do not force the fix: correct the finding in `divergences.md`, disposition to what the evidence supports, and say so in the commit message. Spec 2 disproved one of its own findings this way, by checking the tree's GCC front end rather than reasoning from general knowledge.

- [ ] **Step 3: Verify**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY tools/binrecon/selector_check.py "$TAPE/SCSITape_reloc" "$DRV"; echo "exit=$?"
```

Expected: `renames (0)`, `duplicates (0)`, `exit=0`.

---

### Task 12: Regenerate the artifacts and run the acceptance gates

**Files:**
- Modify: all four `source-map.json`, all four `ledger.json`, `$RECON/divergences.md`

**Interfaces:**
- Consumes: the finished source tree.
- Produces: artifacts describing the tree as it now stands, plus the recorded acceptance evidence.

- [ ] **Step 1: Regenerate the four source maps**

Re-run Task 1 Step 3's four commands unchanged.

- [ ] **Step 2: Check the acceptance numbers**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os
recon = os.environ['RECON']
for name in ('SCSITape', 'PreLoad', 'PostLoad', 'stblocksize'):
    m = json.load(open('%s/%s/source-map.json' % (recon, name)))
    print('%-12s mapped=%3d unmapped=%3d dup=%d bnd=%d' % (name, len(m['mapped']), len(m['unmapped']), len(m['duplicate_candidates']), len(m['boundary_disputed'])))
    print('   unmapped:', [e['reference_names'][0] for e in m['unmapped']])
"
```

Expected per the spec's §4.2: `SCSITape 48/2`, `PreLoad 1/11`, `PostLoad 1/15`, `stblocksize 4/16`, all with 0 duplicates and 0 boundary-disputed. The unmapped entries must be exactly the out-of-scope classes — the two build-generated classes for `SCSITape`, and crt/dyld plus `__picsymbol_stub` entries for the helpers.

**If you observe different numbers, do not adjust anything to reach these** — record what you saw in `divergences.md` and report it.

- [ ] **Step 3: Re-seed and replay the four ledgers**

Save the current statuses, re-seed from the regenerated maps, then replay. Do not hand-edit the JSON.

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os
recon = os.environ['RECON']
out = {}
for n in ('SCSITape', 'PreLoad', 'PostLoad', 'stblocksize'):
    e = json.load(open('%s/%s/ledger.json' % (recon, n)))['entries']
    out[n] = {str(x['address']): [x['status'], x['reason'], x['reviewer'], x['source_path'], x['source_line']] for x in e}
print(json.dumps(out, indent=1))
" > .superpowers/sdd/scsitape-ledger-statuses.json
```

Re-seed with Task 1 Step 5's loop, then replay each status with `binrecon ledger`. Replaying `assembly-matched` takes three calls, `intentional-mismatch` two.

Re-seeding is what makes the ledger honest: any entry whose recorded divergence was found after it had already been promoted can now land on the status the evidence actually supports. Use the status the **evidence** supports, and note in your report wherever that differs from what the old ledger held.

- [ ] **Step 4: Run every gate**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY tools/binrecon/selector_check.py "$TAPE/SCSITape_reloc" "$DRV"; echo "exit=$?"
```

Expected: `renames (0)`, `duplicates (0)`, `exit=0`; `missing` holds only the two build-generated classes.

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import os
from pathlib import Path
from binrecon.identity import identify
from binrecon.ledger import load_ledger
from binrecon.schema import load_source_map
recon, tape = Path(os.environ['RECON']), os.environ['TAPE']
for name, binary in (('SCSITape','SCSITape_reloc'), ('PreLoad','PreLoad'), ('PostLoad','PostLoad'), ('stblocksize','stblocksize')):
    load_ledger(recon / name / 'ledger.json', identify(Path(tape) / binary), None)
    load_source_map(recon / name / 'source-map.json', repo_root=Path('.'))
    print(name, 'validates')
"
```

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY tools/binrecon/ppc_invariant_check.py --binary "$TAPE/SCSITape_reloc"; echo "exit=$?"
```

Expected: 976 fused relocations, 0 violations, exit 0.

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -m pytest tools/binrecon -q
```

Expected: all pass.

- [ ] **Step 5: Write the acceptance record**

Add an `## Acceptance` section to `divergences.md` with the output of every command in Step 4, the final bucket counts, and the status histogram across all four ledgers.

Per the spec's §4.2 item 4, state for every entry still `unexamined` why the fix pass did not repair it. Where a spec expectation was not met, state the actual result and why — not the expectation.

State plainly that nothing is compile-verified, including the four bodies Task 9 wrote.

- [ ] **Step 6: Commit**

```bash
cd /d/RhapsodiOS && git add "$RECON" && git commit -m "drvSCSITape: regenerate the reconstruction artifacts and record acceptance"
```

---

## Self-Review Notes

- Spec coverage: §1.1 artifacts → Task 1; §1.2 starting state → Task 1 Step 4; §1.3 absent functions → Tasks 7, 9, 10; §1.4 out-of-scope → Task 1 Step 6 and Task 6 Step 3; §2.1 jump table → Task 3 Step 1; §2.2 techniques → Global Constraints; §3.1 layout → Task 1; §3.2 two phases → the Phase 1/Phase 2 split with Task 7 as the boundary commit; §3.3 tooling constraints → Global Constraints; §3.4 gitignore → Task 1 Step 1; §4.1 no compile verification → Global Constraints and Tasks 9, 10; §4.2 acceptance → Task 12.
- The 49 examined functions distribute as 20 + 9 + 6 + 9 (Tasks 2–5, totalling `SCSITape_reloc`'s 44) + 5 (Task 6). The four absent bodies are Task 9. Task 10 was repurposed after Task 6 disproved its premise: `_do_ioc` already exists and the scanner was at fault.
- Task 11 has no enumerable step list by construction, since its input is Phase 1's findings. Its procedure, gates and definition of done are specified; the absent list is not a placeholder.
- Ledger addresses are keys shared across tasks. Tasks 2–5 use the address ranges printed in their own tables; Task 6 reads addresses from the seeded ledgers, using the command given immediately above its Step 1, because the helper analyses were not enumerated at plan time.
- Acceptance arithmetic: `SCSITape` 44 mapped + 4 written = 48, unmapped 6 − 4 = 2; `stblocksize` 3 + 1 = 4, unmapped 17 − 1 = 16; the helpers unchanged. Each reconciles against §1.2's named counts of 50, 12, 16 and 20.
