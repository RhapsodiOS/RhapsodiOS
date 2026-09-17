# Floppy Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure Apple's shipped PowerPC `Floppy` driver against `src/drivers-ppc/ide/drvPPCSwimFloppy`, correct the symbol-naming defect in 136 of its 141 hand-written C functions, write the five that are absent, and remove three redundant duplicate definitions.

**Architecture:** Profiles and analysis first, because nothing can be measured without them. Then the rename — driven by the binary's exact name list, gated by a committed checker, never by a blanket prefix-strip. Then map, to prove the rename fixed 136 functions at once. Then the five bodies and the duplicate removals. A final task remaps and runs acceptance.

**Tech Stack:** Python 3.13 in `.venv-binrecon`, binrecon CLI, IDA Professional 9.2 (reference analysis only), Mach-O/PowerPC big-endian.

**Spec:** [2026-07-28-floppy-reconstruction-design.md](../specs/2026-07-28-floppy-reconstruction-design.md)

## Global Constraints

```bash
VENVPY="D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe"
REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc/Floppy.config/Floppy_reloc"
LKS="src/drivers-ppc/ide/drvPPCSwimFloppy/Floppy.drvproj/Floppy.lksproj"
RECON="src/drivers-ppc/reconstruction/Floppy"
```

**Work in a dedicated worktree, not the main checkout.** Several worktrees are
active in this repository, and a shared git index lets parallel sessions
overwrite each other's commits. Create one from `qemu-debug-loop` before Task 1
and set `REPO` to it.

- **There is no PowerPC toolchain and no host C compiler. Nothing compiles, and you may not claim it does.** Do not run `make`. That the renamed symbols "would now match" is an argument from the Mach-O naming rule, not an observation.
- **Never modify `src/kernel-7/`.**
- **Do not rename anything outside `drvPPCSwimFloppy`.**
- **Do not reason from `src/drivers-i386/ide/drvPCFloppy` about SWIM III, GCR, or DBDMA behaviour.** It shares the class name `FloppyController : IODirectDevice` but targets a PC 82077-class controller; only 5 of 141 C functions and 29 of 61 selectors overlap, all in the shared BSD/DriverKit surface.
- **The disassembly is the authority** — not the function name, not a sibling, not what would be reasonable.
- **A confident guess is a defect; a recorded uncertainty is a result.**
- **Reproduce Apple's *form*, not Apple's *defects*.** Where the reference is demonstrably buggy, keep correct behaviour and record `intentional-mismatch` with its evidence. Standing user ruling; "reproduce by default" statements elsewhere in the tree are superseded.
- Commits: `drivers-ppc: ` prefix, one to two lines, no metadata/trailers/emoji. One per task.

### Disciplines, each of which has caught a real defect in this series

- **Establish presence by a definition site** — never by an occurrence count, never by a regex over declaration syntax, never by `find | head -1`. Five ad-hoc surveys in this series were recorded as measurement and every one had to be retracted, including the one that reported this driver as having no source at all.
- **Resolve every `bl` through `read_macho`'s relocation table.** PowerPC jump islands (`lis r12 / ori / mtctr / bctr`) are not in IDA's export; the real target comes from the **island's** HI16/LO16 relocation pair.
- **Read ivars from `__OBJC,__instance_vars`**, never by inference.
- **Trace every bare constant to a named constant in this tree** before writing it as one.
- **Account for every instruction and every branch in writing.**

### The address-0 rule — read before interpreting any tool output

`_fdrToIo` sits at `__text+0`. Its first word is `9421ffe0` (`stwu r1,-32(r1)`) —
**real code**. IDA's analysis has no function entry there, so
`ppc_invariant_check` will report:

```
symbol _fdrToIo at 0x0 is not a function start
```

**That means only that IDA's function list lacks an entry.** It is not evidence
of an absent body. The opposite reading was recorded across five earlier specs
and retracted in 22 places. `read_macho` also reports address 0 for *undefined*
symbols, which is what made the two cases look alike.

**Unlike every prior driver in this series, the address-0 function here is a C
function, not a `+probe:` method**, so `selector_check.py` cannot confirm it.
Confirm it with `symbol_name_check.py`, which matches C definition sites by name.

### Established before this plan — use, do not re-derive

`__text` spans `0x0`–`0xc05c` (49,244 bytes) across **203 defined symbols**:

| Origin | Count |
| --- | --- |
| Build-generated (`FloppyVersion`, `FloppyKernelServerInstance`) | 2 |
| Hand-written Objective-C | 60 |
| Hand-written C | 141 |

`2 + 60 + 141 = 203`. **201 are hand-written.** Classes:

```
FloppyDisk : IODisk    28 methods      FloppyDisk (Internal)  21
FloppyDisk (Thread)    10 methods      FloppyController : IODirectDevice  1
```

Source, all four files in `CLASSES`:

```
FloppyDisk.m        8,891 lines   29 methods   135 of the C definitions
FloppyDiskInt.m     1,031 lines   23 methods     2
FloppyDiskThread.m    824 lines   10 methods     1
FloppyDiskKern.m       12 lines    0 methods     0
```

### The five functions to write

| # | Function | Addr | Span | Layer |
| --- | --- | --- | --- | --- |
| 1 | `_fdminphys` | `0x5b84` | 40 | BSD device entry |
| 2 | `_MediaScanTask` | `0xa284` | 60 | Media scan |
| 3 | `_TestCacheDirtyState` | `0x9444` | 88 | Track cache |
| 4 | `_fd_dev_to_id` | `0x5bac` | 216 | BSD device entry |
| 5 | `_OpenDBDMAChannel` | `0x68a8` | 380 | DBDMA |

784 bytes. Spans are next-symbol deltas including any trailing jump island —
confirm each function's true extent from its `blr` before writing.

## File Structure

**Created:**
- `tools/binrecon/profiles/floppy-ppc.json`, `floppy-bundle-ppc.json` (Task 1)
- `$RECON/{source-map.json,ledger.json,findings.md}` (Task 3)

**Modified:**
- `tools/binrecon/tests/test_profile.py` — `test_ppc_profile_inventory` (Task 1)
- `$LKS/FloppyDisk.m`, `FloppyDisk.h`, `FloppyDiskInt.m`, `FloppyDiskThread.m` — rename (Task 2), bodies and duplicate removal (Task 4)

---

## Task 1: Profiles, inventory test, reference analysis

**Files:**
- Create: `tools/binrecon/profiles/floppy-ppc.json`, `tools/binrecon/profiles/floppy-bundle-ppc.json`
- Modify: `tools/binrecon/tests/test_profile.py`

**Interfaces:**
- Produces: the analysis JSON under `tools/binrecon/out/floppy-ppc/published/`, consumed by Tasks 3 and 5.

- [ ] **Step 1: Add both profiles to the inventory test — RED first**

`test_ppc_profile_inventory` asserts the complete sorted list of PPC profile
filenames. Insert the two new names in sorted position — they sort between
`dec21040-ppc.json` and `gem-bundle-ppc.json`:

```python
        "dec21040-bundle-ppc.json", "dec21040-ppc.json",
        "floppy-bundle-ppc.json", "floppy-ppc.json",
        "gem-bundle-ppc.json", "gem-ppc.json",
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest \
  tools/binrecon/tests/test_profile.py::test_ppc_profile_inventory -q
```

Expected: FAIL — the two files do not exist, so the actual list lacks them.
Confirm the failure names exactly those two before continuing.

- [ ] **Step 3: Create `floppy-ppc.json`**

```json
{
  "schema_version": "profile-v1",
  "name": "drvPPCSwimFloppy ppc reconstruction",
  "architecture": "ppc",
  "endianness": "big",
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
  "output_dir": "../out/floppy-ppc"
}
```

- [ ] **Step 4: Create `floppy-bundle-ppc.json`**

Identical except:

```json
  "name": "drvPPCSwimFloppy bundle ppc reconstruction",
  "output_dir": "../out/floppy-bundle-ppc"
```

- [ ] **Step 5: Run the profile tests and confirm they pass**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests/test_profile.py -q
```

Expected: PASS. `test_ppc_profiles_are_reference_only_ida_runs` is parametrised
over every PPC profile and will exercise both new ones, asserting
`schema_version`, `architecture: ppc`, `endianness: big`, the
`${BINRECON_REFERENCE}` reference, absence of a `rebuilt` key, and
`ida.enabled is True`.

- [ ] **Step 6: Run the reference analysis**

```bash
cd $REPO && BINRECON_REFERENCE="$REF" PYTHONPATH=tools/binrecon \
  $VENVPY -m binrecon analyze --profile tools/binrecon/profiles/floppy-ppc.json
```

**Expected: exit 1, and that is correct.** `cli.py:105` returns
`0 if report["complete"] and acceptance["passed"] else 1`, and a reference-only
profile carries no `rebuilt` binary, so `normalized-functions` acceptance has
nothing to compare and can never pass. What matters is that the run reports
`analysis complete` and publishes output under
`tools/binrecon/out/floppy-ppc/published/`. A real failure prints
`analysis incomplete` or a `binrecon: {error}` on stderr.

The analysis JSON will be
`tools/binrecon/out/floppy-ppc/published/analysis-reference-ida.json`; later
steps call it `$ANALYSIS`.

- [ ] **Step 7: Record the analysis shape**

```bash
cd $REPO && $VENVPY -c "
import json,sys
d=json.load(open(sys.argv[1]))
fns=d['functions']
print('functions:', len(fns))
print('unnamed  :', sum(1 for f in fns if not f['names']))
print('lowest   :', hex(min(f['address'] for f in fns)))" $ANALYSIS
```

`lowest` must be **greater than 0** — that confirms the address-0 rule in advance
rather than discovering and misreading it later. If it comes back 0, that
contradicts the plan; report it rather than proceeding. Record all three numbers
for Task 3's findings.

- [ ] **Step 8: Full suite, then commit**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: `866 passed, 4 skipped` — the baseline is 864 and
`test_ppc_profiles_are_reference_only_ida_runs` gains one case per new profile.
If the count differs, say so rather than adjusting the expectation.

```bash
cd $REPO && git add tools/binrecon/profiles tools/binrecon/tests/test_profile.py && \
  git commit -m "drivers-ppc: add the Floppy binrecon profiles"
```

---

## Task 2: The 136-function rename

**Files:**
- Modify: `$LKS/FloppyDisk.m`, `$LKS/FloppyDisk.h`, `$LKS/FloppyDiskInt.m`, `$LKS/FloppyDiskThread.m`

**Interfaces:**
- Consumes: `tools/binrecon/symbol_name_check.py`, already committed.
- Produces: source whose C definition names match the binary's symbols minus one underscore.

Every C function in this source is defined with a spurious leading underscore —
`void _AssignTrackInCache(int param_1)` emits `__AssignTrackInCache` where
Apple's binary carries `_AssignTrackInCache`. **136 of 141 affected; none
correct.** The other five are absent entirely and are Task 4's.

- [ ] **Step 1: Read the exact name list from the binary**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
from binrecon.macho import read_macho
d=read_macho(r'$REF')
n=[s['name'][1:] for s in d['symbols'] if s.get('section')=='__TEXT,__text'
   and not s['name'].startswith(('-[','+['))]
print(len(n)); [print(x) for x in sorted(n)]"
```

Expected: 141 names. **This list is the only authority for what gets renamed.**

- [ ] **Step 2: Record the before-state**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/symbol_name_check.py \
  --binary "$REF" --source-dir $LKS
```

Expected: 141 hand-written C symbols, **141 missing**. Save this output; Task 3's
findings quote it as the baseline.

- [ ] **Step 3: Rename, one name at a time, word-bounded**

For each of the 141 names `Name` from Step 1, replace the identifier `\b_Name\b`
with `Name` across `FloppyDisk.m`, `FloppyDisk.h`, `FloppyDiskInt.m` and
`FloppyDiskThread.m`.

**A blanket transformation over `_[A-Za-z]\w*` is prohibited and will corrupt
this source.** Unlike `PPCSerialPort`, this file has **157 `_`-prefixed
identifiers that are not among the 141** and must not move **in this step** —
globals and types such as `_BusyFlag`, `_FloppyState`, `_FdBuffer`,
`_Floppy_dev`, `_FloppySWIMIIIRegs`, and Objective-C selectors such as
`_rwBlockCount:blockCount:` and `_timerEvent`.

**"Must not move here" is not "is spelled right".** The one-underscore Mach-O
rule is not function-specific: **zero** of the binary's 306 symbols carry a
double underscore, and `_FloppyState`, `_Floppy_dev`, `_FloppyIdMap`,
`_busyflag`, `_slock`, `_ReadDataPresent`, `_PrivDBDMAChannelArea` and
`_GRCFloppyDMAChannel` are one-underscore `__DATA` symbols, so Apple spelled
those globals bare too. Ours emit the double-underscore forms and match nothing.
`symbol_name_check.py` measured `__TEXT,__text` only, so its gate could not see
it; it now also checks `__DATA,*` under `--check-data`, and the names above were
renamed to their bare spelling.
That defect is out of scope for this plan and is recorded as uncertainty 5 in
`findings.md` — the next driver must **schedule** it, not preserve it.

**Two names are prefixes of others:**

```
_GetDisketteFormat              is a prefix of  _GetDisketteFormatType
_MemListDescriptorDataCompare   is a prefix of  _MemListDescriptorDataCompareWithMemory
```

Word-bounded `\b_Name\b` handles both correctly, because the character after the
shorter name is a word character and `\b` fails there. Substring replacement does
not. **Do not use substring replacement.**

**Do not rewrite string literals.**

**Expected scale — 997 token occurrences:**

```
FloppyDisk.m        809
FloppyDisk.h        163
FloppyDiskInt.m      13
FloppyDiskThread.m   12
```

Substantially fewer changed tokens means the rename missed something; more means
it caught something it should not have.

- [ ] **Step 4: Verify with the checker**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/symbol_name_check.py \
  --binary "$REF" --source-dir $LKS
```

Expected: **exactly 5 missing** — `_fdminphys`, `_fd_dev_to_id`,
`_OpenDBDMAChannel`, `_TestCacheDirtyState`, `_MediaScanTask`. Any other name in
the list means the rename broke or missed something; fix it before continuing.

- [ ] **Step 5: Verify nothing outside the 141 moved**

```bash
cd $REPO && git diff -U0 -- $LKS | grep '^[-+]' | grep -v '^[-+][-+]' > /tmp/fl.txt
$VENVPY -c "
import re
names=set(open('/tmp/fl-names.txt').read().split())
bad=set()
for line in open('/tmp/fl.txt'):
    for tok in re.findall(r'\b_[A-Za-z]\w*', line):
        if tok[1:] not in names: bad.add(tok)
print('identifiers changed that are NOT among the 141:', sorted(bad) or 'none')"
```

Write the 141 names to `/tmp/fl-names.txt` first (one per line, without the
leading underscore). Expected: **none**. Any hit is a corrupted identifier — fix
before continuing.

- [ ] **Step 6: Full suite, then commit**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: `866 passed, 4 skipped`.

```bash
cd $REPO && git add $LKS && \
  git commit -m "drivers-ppc: drop the spurious leading underscore from Floppy's C functions"
```

---

## Task 3: Map, buckets, findings

**Files:**
- Create: `$RECON/source-map.json`, `$RECON/ledger.json`, `$RECON/findings.md`

**Interfaces:**
- Consumes: `$ANALYSIS` from Task 1; the renamed source from Task 2.
- Produces: `$RECON/source-map.json` and the recorded route, which Task 5 re-runs verbatim.

- [ ] **Step 1: Filter unnamed functions**

```bash
cd $REPO && $VENVPY tools/binrecon/filter_named_functions.py \
  $ANALYSIS tools/binrecon/out/floppy-ppc/analysis-named.json
```

Expected: exit 0. Re-run Task 1 Step 7's snippet against the output; `unnamed`
must be 0 and `input.sha256` unchanged.

- [ ] **Step 2: Build the source map — no `--scope-to-objc`**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --reference-analysis tools/binrecon/out/floppy-ppc/analysis-named.json \
  --binary "$REF" \
  --source-dir $LKS \
  --repo-root . \
  --objc-methods \
  --output $RECON/source-map.json
```

141 of the 201 hand-written functions are C. **`--scope-to-objc` would cover 60
of 201 and look complete** — the failure mode this route exists to avoid.

- [ ] **Step 3: Check coverage across all four categories**

```bash
cd $REPO && $VENVPY -c "
import json
m=json.load(open('$RECON/source-map.json'))
for k in ('mapped','unmapped','duplicate_candidates','boundary_disputed'):
    v=m.get(k,[]); print(f'{k}: {len(v)}')
    for e in v[:60]: print('   ', e.get('name') or e)"
```

Do not judge coverage from `mapped` and `unmapped` alone — an earlier spec in
this series missed addresses that way. Every `duplicate_candidates` and
`boundary_disputed` entry needs an explanation in `findings.md`.

**Expect `duplicate_candidates` to be non-zero**: three functions are defined
twice — `GetBusyFlag` and `ResetBusyFlag` (§6.1 of the spec; Task 5 Step 6
removes the redundant statics). `getStatusName` is defined twice too but has no
binary counterpart, so it cannot appear here.

- [ ] **Step 4: Bucket the functions**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/bucket_functions.py \
  tools/binrecon/out/floppy-ppc/analysis-named.json \
  $RECON/source-map.json
```

Both arguments are **positional**. Expected: a table ending `RECONCILES: yes`.
Buckets 1 and 2 are always empty for a `_reloc` kernel server. Bucket 4 should
hold the two build-generated class methods. Bucket 6 is **not** the gap count —
account for what is in it.

- [ ] **Step 5: Run the PowerPC invariant check**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
  --binary "$REF" --analysis tools/binrecon/out/floppy-ppc/analysis-named.json
```

Expect the `_fdrToIo` line to report **code present**. Any other violation gets a
written explanation — the single violation deserves more scrutiny than the clean
relocations, not less.

- [ ] **Step 6: Seed the ledger**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/seed_ledger.py \
  $RECON/source-map.json "$REF" $RECON/ledger.json
```

`seed_ledger.py` takes three **positional** arguments — source map, reference
binary, output. Then verify programmatically that every entry's `source_line`
agrees with the map, and record the entry count.

- [ ] **Step 7: Write findings.md**

Record: Task 1 Step 7's three analysis numbers; the four-category coverage; the
bucket table; the invariant-check result; the `_fdrToIo` exclusion and why; the
before/after `symbol_name_check.py` output from Task 2 Steps 2 and 4 as the
evidence that the rename fixed 136 functions at once; the two duplicate
definitions; the six source-only debug helpers; and the five remaining gaps.

State plainly that nothing was compiled.

- [ ] **Step 8: Commit**

```bash
cd $REPO && git add $RECON && \
  git commit -m "drivers-ppc: map Floppy against the shipped binary"
```

---

## Task 4: The 52-selector rename

**Files:**
- Modify: `$LKS/FloppyDisk.m`, `$LKS/FloppyDisk.h`, `$LKS/FloppyDiskInt.m`, `$LKS/FloppyDiskInt.h`, `$LKS/FloppyDiskThread.m`, `$LKS/FloppyDiskThread.h`

**Interfaces:**
- Consumes: `tools/binrecon/selector_check.py`, already committed.
- Produces: source whose Objective-C selectors match the binary's. Task 6's remap expects all 52 mapped.

**This task was added after Task 3's measurement.** The spec and plan originally
asserted all 60 Objective-C methods were present and correct. They are present,
but **52 of the 60 carry a spurious leading underscore on the selector** —
`- (void)_timerEvent` where Apple's binary has `-[FloppyDisk(Internal) timerEvent]`.

This is the same defect class as Task 2's, in the other half of the language, and
it is **worse than a naming mismatch**: a selector is not a symbol decoration.
`[self _timerEvent]` and `[self timerEvent]` are different messages at runtime, so
the current source would fail to respond to the selectors Apple's callers send.

**Apple's binary carries zero underscored selectors** — verified across all 62
Objective-C method symbols.

- [ ] **Step 1: Read the exact selector list from the binary**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
import re
from binrecon.macho import read_macho
d=read_macho(r'\$REF')
s={re.split(r'[:\]]', x['name'][x['name'].index(' ')+1:])[0]
   for x in d['symbols'] if x.get('section')=='__TEXT,__text'
   and x['name'].startswith(('-[','+['))}
print(len(s)); [print(n) for n in sorted(s)]"
```

Expected: 61 distinct selector base names. **This list is the only authority for
what gets renamed.**

- [ ] **Step 2: Record the before-state**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/selector_check.py \
  "$REF" $LKS
```

Expected: 62 reference selectors, 60 our definitions, **52 renames**, 0
duplicates, **2 missing** (`+[FloppyKernelServerInstance kernelServerInstance]`
and `+[FloppyVersion driverKitVersionForFloppy]`, both build-generated), 0 extra.

Save this output; Task 6's findings quote it as the baseline.

- [ ] **Step 3: Rename the 52 selectors, one at a time, word-bounded**

For each source selector `_name` whose bare form `name` appears in Step 1's list,
replace `_name` with `name` — at its definition, in its declaration in the
matching `.h`, and at every `[receiver _name…]` call site.

Distribution: 21 in `FloppyDisk.m` (`@implementation FloppyDisk`), 21 in
`FloppyDiskInt.m` (`FloppyDisk(Internal)`), 10 in `FloppyDiskThread.m`
(`FloppyDisk(Thread)`). **174 token occurrences** across the six files.

**Corrected after the measurement (see the design spec §3.2).** This step first
said "185 token occurrences" and "eight source selectors are legitimately
underscored and must not move". Both are refuted:

- The token figure is **174**, not 185. Eleven of the 185 were the `_innerRetry`
  and `_outerRetry` ivars, not selectors; renaming them would have altered driver
  state.
- **No legitimately-underscored selector exists.** Apple's
  `__OBJC,__meth_var_names` holds 130 names and **not one** begins with an
  underscore. The "eight" are simply the eight source selectors that were already
  written **bare** — they need no rename because they are already correct, not
  because their underscore is legitimate.
- The count of selectors to rename is **53**, not 52: `_fcCmdXfr:driveInfo:` is
  a 53rd instance that is absent from Step 1's symbol-derived list because
  `FloppyController`'s only `__TEXT,__text` method symbol is `+probe:`. It is
  renamed in Task 5.

Any selector whose bare form is absent from Step 1's list stays exactly as it is.

**Do not touch C function names.** Task 2 already renamed those 141; they are a
disjoint set. Do not rewrite string literals.

- [ ] **Step 4: Verify with the checker**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/selector_check.py \
  "$REF" $LKS
```

Expected: **0 renames**, 0 duplicates, **2 missing** (the same two
build-generated), 0 extra.

- [ ] **Step 5: Verify nothing else moved**

Confirm the C-function gate is unchanged — this task must not disturb Task 2's
work:

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/symbol_name_check.py \
  --binary "$REF" --source-dir $LKS
```

Expected: 141 hand-written C symbols, **5 missing** — the same five as before
(`_fdminphys`, `_fd_dev_to_id`, `_OpenDBDMAChannel`, `_TestCacheDirtyState`,
`_MediaScanTask`). Any change here means the selector rename touched C functions.

Then diff the changed-token multiset per file and confirm every changed token is
one of the 52 selectors: `drop(_name) == rise(name)` for each, and no other
identifier's count moved. A line-based check is not sufficient — Task 2's
line-based verification produced seven false positives.

- [ ] **Step 6: Full suite, then commit**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: `866 passed, 4 skipped`.

```bash
cd $REPO && git add $LKS && \
  git commit -m "drivers-ppc: drop the spurious leading underscore from Floppy's selectors"
```

---

## Task 5: The five absent functions and duplicate removals

**Files:**
- Modify: `$LKS/FloppyDisk.m`, `$LKS/FloppyDisk.h`, `$LKS/FloppyDiskInt.m`, `$LKS/FloppyDiskThread.m`, `$RECON/findings.md`

**Interfaces:**
- Consumes: `$RECON/source-map.json` for addresses.
- Produces: five function bodies; three fewer duplicate definitions. Task 5 remaps and expects all five mapped and `duplicate_candidates` at 0.

**Source names carry no leading underscore.** Task 2 established this: the ABI
prepends exactly one, so source `fdminphys` produces symbol `_fdminphys`. Writing
`_fdminphys` would emit `__fdminphys` and reintroduce the defect this spec exists
to fix. `symbol_name_check.py` enforces it.

Work smallest first.

- [ ] **Step 1: Write `fdminphys` (`0x5b84`, 40 bytes)**

Smallest. `_fdminphys` is the only one of the five with a same-name counterpart
in `src/drivers-i386/ide/drvPCFloppy` — treat that as a hint to check, **not** as
evidence, and derive the body from this binary's disassembly.

Resolve every `bl` through the island's HI16/LO16 relocation pair. Produce an
instruction-by-instruction account covering every branch.

- [ ] **Step 2: Write `MediaScanTask` (`0xa284`, 60 bytes)**

`_LaunchMediaScanTask` and `_KillMediaScanTask` already exist in the source and
bracket this one; read them for the task's conventions before writing.

- [ ] **Step 3: Write `TestCacheDirtyState` (`0x9444`, 88 bytes)**

Track-cache layer. `_TestTrackInCache` and `_AssignTrackInCache` are its
neighbours and already exist.

- [ ] **Step 4: Write `fd_dev_to_id` (`0x5bac`, 216 bytes)**

BSD device layer. Sits immediately after `fdminphys`; `_fd_init_idmap` and
`_floppy_idmap` are related and already exist — read them for the id-map layout
before writing, rather than inferring it.

- [ ] **Step 5: Write `OpenDBDMAChannel` (`0x68a8`, 380 bytes)**

Largest. The DBDMA layer has **no i386 sibling constraint at all**, so the
disassembly is the sole authority. `_CloseDBDMAChannel`, `_PrepDBDMA`,
`_ResetDBDMA` and `_SetDBDMAPhysicalAddress` already exist; read them for the
channel-structure layout first.

- [ ] **Step 6: Remove the three redundant duplicate definitions**

Each of these is defined twice — external in `FloppyDisk.m` and `static` in a
second file. That is **not** legal C: both second files import `FloppyDisk.h`,
which declares all three `extern` at file scope, so each `static` definition
follows an external declaration of the same name **in the same translation
unit** — C99 6.2.2p7, which GCC diagnoses. Apple's binary also carries **one**
symbol each, and `static` functions do receive symbol-table entries in a `_reloc`
output.

Line numbers are pre-rename; locate them by name:

```
getStatusName    FloppyDisk.m:136    (extern)   FloppyDiskThread.m:94   (static)
GetBusyFlag      FloppyDisk.m:3608   (extern)   FloppyDiskInt.m:125     (static)
ResetBusyFlag    FloppyDisk.m:6447   (extern)   FloppyDiskInt.m:130     (static)
```

**Delete the `static` copies; keep the external definitions.** Add a declaration
in the second file where it needs one. **Verify against the disassembly that the
surviving body is the one matching Apple's**, rather than assuming the external
one is right — `getStatusName` has no binary counterpart at all (it is one of the
six source-only helpers), so for that one keep whichever body is correct and say
which you kept and why.

- [ ] **Step 7: Verify all five now have definition sites**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/symbol_name_check.py \
  --binary "$REF" --source-dir $LKS
```

Expected: 141 hand-written C symbols, **0 missing**, exit 0.

- [ ] **Step 8: Record uncertainties**

Anything you could not settle from evidence goes into `$RECON/findings.md` as a
numbered uncertainty with what you observed and what you would need. Do not
resolve an ambiguity by silently picking the plausible option.

- [ ] **Step 9: Full suite, then commit**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: `866 passed, 4 skipped`.

```bash
cd $REPO && git add $LKS $RECON/findings.md && \
  git commit -m "drivers-ppc: write Floppy's five absent C functions and drop the duplicate statics"
```

---

## Task 6: Remap and acceptance

**Files:**
- Modify: `$RECON/source-map.json`, `$RECON/ledger.json`, `$RECON/findings.md`, `src/drivers-ppc/reconstruction/report.md`

- [ ] **Step 1: Regenerate the map**

Re-run Task 3 Steps 1–2 verbatim. All five new functions should now map, and
`duplicate_candidates` should be 0 — Task 5 Step 6 removed all three redundant
statics, two of which (`GetBusyFlag`, `ResetBusyFlag`) were the map's duplicate
candidates. `getStatusName`'s static is removed too but never appeared as one,
since it has no binary counterpart.
If it is not 0, enumerate what remains with evidence.

- [ ] **Step 2: Confirm coverage against acceptance**

The map must cover **200** of the 201 hand-written functions. The 201st is
`_fdrToIo`, excluded by construction per the address-0 rule.

Confirm `_fdrToIo` is present in source independently:

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/symbol_name_check.py \
  --binary "$REF" --source-dir $LKS
```

0 missing means every C symbol including `_fdrToIo` has a definition site.
`selector_check.py` cannot help here — the address-0 function is a C function,
not a selector.

- [ ] **Step 3: Re-run buckets and the invariant check**

Task 3 Steps 4 and 5, unchanged. Expect `RECONCILES: yes` and the same single
`_fdrToIo` line reporting code present.

- [ ] **Step 4: Regenerate the ledger**

Re-run Task 3 Step 6 against the **new** map, so the ledger's entry set and every
`source_line` match. Verify programmatically that all citations agree, and state
the entry count.

Do not skip this: on the `PPCSerialPort` branch the ledger was left unregenerated
after a remap and all 64 of its citations were wrong.

- [ ] **Step 5: Run `selector_check.py` for the Objective-C surface**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/selector_check.py \
  "$REF" $LKS
```

Both arguments are **positional**. Expected: `missing` contains only
`+[FloppyKernelServerInstance kernelServerInstance]` and
`+[FloppyVersion driverKitVersionForFloppy]`, the two build-generated methods.

**Record what this does and does not prove**: it matches selectors by name, not
behaviour. The 60 Objective-C bodies came from a decompiler and remain
unverified against the reference. Coverage is not correctness.

- [ ] **Step 6: Full suite**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: `866 passed, 4 skipped`. `PYTHONPATH` is required; without it
collection fails.

- [ ] **Step 7: Cross-reference from the driver report**

Add a section to `src/drivers-ppc/reconstruction/report.md` giving Floppy's
headline numbers and pointing at `$RECON/findings.md`. Note that the source was
previously recorded as absent, and why that was wrong.

- [ ] **Step 8: Final acceptance statement**

In `$RECON/findings.md`, state against each of the spec's eleven acceptance items
whether it passed, with the evidence. Include the standing constraint: **nothing
was compiled**, so every claim is of correspondence to the binary, never of
buildability — and "the renamed symbols would now match" follows from the Mach-O
naming rule, not from a build.

- [ ] **Step 9: Commit**

```bash
cd $REPO && git add $RECON src/drivers-ppc/reconstruction/report.md && \
  git commit -m "drivers-ppc: remap Floppy and record acceptance"
```

---

## Self-Review

**Spec coverage.** §1 goal → Tasks 2, 4, 5. §1.1 the missed source → Global
Constraints disciplines, Task 6 Step 7. §2 partition → Task 3 Steps 3–4. §2.1
classes → Task 4, Task 6 Step 5. §2.2 C layers → Task 5 step ordering. §2.3 the
i386 sibling → Global Constraints, Task 5 Steps 1 and 5. §3 the C defect → Task 2.
§3.1 why it is dangerous → Task 2 Steps 3 and 5. §3.2 the selector defect → Task 4
(added after Task 3's measurement). §4.1 address-0 → Global Constraints, Task 1
Step 7, Task 6 Step 2. §4.2 profiles → Task 1. §4.3 mapping → Task 3 Steps 1–2,
Task 6 Step 1. §4.4 the gate → Task 2 Steps 2/4, Task 4 Steps 2/4, Task 5 Step 7.
§4.5 disciplines → Global Constraints. §5 the five → Task 5 Steps 1–5. §6.1
duplicates → Task 5 Step 6. §6.2 the six helpers → Task 3 Step 7; never renamed,
because no binary symbol matches them. §7 artifacts → Task 3. §8 acceptance items
1–11 → Task 1 Step 5, Task 2 Steps 4–5, Task 3 Steps 3–4, Task 4 Steps 4–5, Task 5
Steps 6–7, Task 6 Steps 1–6/8. §9 constraints → Global Constraints. §10 risks →
Task 2 Step 5, Task 4 Step 5, Task 5 Step 5, Task 6 Step 5.

**Naming consistency.** `analysis-named.json` is produced in Task 3 Step 1 and
consumed in Steps 2, 4, 5 and Task 5 Steps 1, 3. `$RECON` is
`src/drivers-ppc/reconstruction/Floppy` throughout. `symbol_name_check.py`'s
counts are quoted identically in Task 2 Steps 2/4 and Task 4 Step 7: 141 → 5 → 0.

**Suite counts.** Baseline 864 (`tools/binrecon/tests`). Task 1 adds 2
parametrised profile cases → 866. Tasks 2, 4 and 5 expect 866; no task adds
tests.

**Known soft spot.** Task 2 Step 5 writes scratch files under `/tmp`,
which is MSYS-local; if the verification snippet is run through the Windows
Python it will not see them, so keep both halves in the same shell or use the
scratchpad directory.
