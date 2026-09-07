# IONDRVSupport Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close out `IONDRVSupport` — verify the 20 inherited bodies against the reference, rename 12 over-underscored functions, flatten the ATI class split to match the binary, remove three duplicate definitions, and write the one absent function.

**Architecture:** Verification first, because everything after it moves or renames code we have never checked, and a material divergence halts the plan rather than being absorbed. Then the rename, then the class flattening, then the small source fixes, then a remap that proves all of it.

**Tech Stack:** Python 3.13 in `.venv-binrecon`, binrecon CLI, IDA Professional 9.2 (reference analysis only), Mach-O/PowerPC big-endian.

**Spec:** [2026-07-28-iondrvsupport-completion-design.md](../specs/2026-07-28-iondrvsupport-completion-design.md)

## Global Constraints

```bash
VENVPY="D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe"
REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc/IONDRVSupport.config/IONDRVSupport_reloc"
PPC="src/driverkit-3/libDriver/ppc"
RECON="src/drivers-ppc/reconstruction/IONDRVSupport"
ANALYSIS="tools/binrecon/out/iondrvsupport-ppc/published/analysis-reference-ida.json"
```

**Work in a dedicated worktree, not the main checkout.** Several worktrees are
active in this repository, and another session has committed to
`qemu-debug-loop` twice during this work. Create one from `qemu-debug-loop`
before Task 1 and set `REPO` to it.

- **There is no PowerPC toolchain and no host C compiler. Nothing compiles, and you may not claim it does.** Do not run `make`. Removing a duplicate removes a known link error; that is not a claim the tree links.
- **Never modify `src/kernel-7/`.**
- Modify only the five files of "The five contributing files" below, plus artifacts under `$RECON`.
- **Do not rename anything outside the 12 named in Task 2.**
- **The disassembly is the authority** — not a function name, not a commit message, not what would be reasonable.
- **A confident guess is a defect; a recorded uncertainty is a result.**
- **Reproduce Apple's *form*, not Apple's *defects*.** Where the reference is demonstrably buggy, keep correct behaviour and record `intentional-mismatch` with evidence. Standing user ruling.
- Resolve every `bl` through `read_macho`'s relocation table — PowerPC jump islands (`lis r12 / ori / mtctr / bctr`) are not in IDA's export, and the real target comes from the **island's** HI16/LO16 pair.
- Verify a rename by a whole-file token-multiset diff, never a line-based check; a line-based check produced seven false positives on Floppy.
- Commits: `driverkit: ` for source under `src/driverkit-3/`, `drivers-ppc: ` for artifacts under `$RECON`. One to two lines, no metadata/trailers/emoji.

### THE HAZARD — read before renaming anything

This driver carries **both underscore cases at once, in the same directory,
pointing opposite ways.**

- **12 functions are over-underscored** and must lose their leading underscore (Task 2).
- **59 `__e*` symbols are correctly underscored** and must keep theirs. Their source spelling is `_eRegistryEntryIterate`, which emits `__eRegistryEntryIterate` — exactly what the binary carries. **58 of the 59 map on that spelling today**; the 59th is Task 4's.

The family is much broader than its name suggests — `__eRegistryEntryIterate`,
`__eATIIsAllInOne`, `__eATISetMBRES`, `__eAbsoluteToNanoseconds`,
`__eAddAbsoluteToAbsolute`, `__eGetInterruptFunctions`, and more.

**Five earlier specs in this series stripped a leading underscore from every C
name. Applying that reflex here would break 58 working functions** — nearly half
this binary's hand-written C surface, and almost five times the number being
renamed.

**The gate will not catch it**: a wrongly-renamed `_e*` function becomes
"missing" rather than visibly wrong. Drive the rename from the binary's exact
symbol list, one name at a time.

### The five contributing files

`IONDRVFramebuffer.m` (2,113 lines), `IONDRVLibraries.m`, `IONDRVInterface.m`,
`IOPEFInternals.c`, `IOPEFLoader.c` — five of the seventeen `.m`/`.c` files in
`$PPC`. The other twelve belong to other binaries, so **scope every checker to
these five**; a directory argument silently pulls in three other binaries'
sources.

`symbol_name_check.py` and `selector_check.py` accept a file path as well as a
directory. `binrecon source-map`'s `--source-dir` is repeatable and also accepts
files.

### Class boundaries in IONDRVFramebuffer.m, as of this plan

```
1135  @implementation IOATINDRV          1154  @end     (one method)
1415  @implementation IOATIMACH64NDRV    1595  @end     (the 8 bodies)
1601  @implementation IOATIRAGE128NDRV   1618  @end
```

The 12 blit/fill C functions sit at 1227–1959, interleaved with these
implementations rather than grouped. Line numbers are pre-change; locate by name.

### Current gate state

```
symbol_name_check.py  → 124 hand-written C symbols, 13 missing
selector_check.py     → 12 extra, 10 missing
suite                 → 905 passed, 4 skipped
```

## File Structure

**Modified:**
- `$PPC/IONDRVFramebuffer.m` — renames (Task 2), class flattening (Task 3), duplicate removal (Task 4)
- `$PPC/IONDRVFramebuffer.h` — class declarations (Task 3)
- `$PPC/IONDRVLibraries.m` — duplicate removal and the absent function (Task 4)
- `$RECON/{source-map.json,ledger.json,findings.md}` (Tasks 1, 5)

---

## Task 1: Verify the twenty inherited bodies

**Files:**
- Modify: `$RECON/findings.md`

**Interfaces:**
- Produces: a per-function verdict for all 20, consumed by Tasks 2 and 3. **Task 3 must not proceed on a material divergence.**

Commit `6f3d886c` ("driverkit: Add hardware blit and fill code for Mach64, Rage
128, and IMS video cards for PPC") wrote these 20 bodies. **They are in-repo
reconstruction, not recovered Apple source, and none has ever been compared
against the disassembly.** Apple's own `.m` implements only `IOATINDRV`, with the
single method `getStartupMode:depth:`.

- [ ] **Step 1: Confirm the provenance yourself**

```bash
cd $REPO && git log --oneline -- $PPC/IONDRVFramebuffer.m
cd $REPO && git log -L 1415,1595:$PPC/IONDRVFramebuffer.m --oneline | head -20
```

Expect three commits on the file: `19ffee9a` (Original Darwin 0.3), `6f3d886c`,
`3a0ab68f` (path move). Confirm the 8 `IOATIMACH64NDRV` bodies and the 12
blit/fill functions arrived in `6f3d886c`, and that `19ffee9a` has no
`@implementation IOATIMACH64NDRV`.

- [ ] **Step 2: Verify the 12 blit/fill functions against the reference**

3,000 bytes. For each, disassemble the reference at its address, resolve every
`bl` through the island's HI16/LO16 relocation pair, and compare
instruction-by-instruction against the source body. Account for every branch.

Addresses come from the map — `$RECON/source-map.json`'s `unmapped` entries carry
them, since these are the 12 the gate reports missing.

- [ ] **Step 3: Verify the 8 `IOATIMACH64NDRV` methods against the reference**

996 bytes, at the addresses the binary assigns to `-[IOATINDRV …]`. The reference
has these as flat `IOATINDRV` methods; compare each against the corresponding
`IOATIMACH64NDRV` body in our tree.

The eight pair name-for-name: `hideCursor:`, `initEngine`, `moveCursor:frame:token:`,
`open`, `setDisplayMode:depth:page:`, `setIntValues:forParameter:count:`,
`showCursor:frame:token:`, `tempFlags`.

- [ ] **Step 4: Record a verdict for each of the 20**

For each: `matches`, `diverges` with the specific instruction and what differs, or
`cannot-determine` with what you would need. Write them into `$RECON/findings.md`.

- [ ] **Step 5: Decide whether the plan continues**

**If any body diverges materially, stop here and report.** Rewriting 4 KB of
bodies is a different spec from renaming them, and this one is scoped for
renaming. Halting is a correct outcome, not a failure.

A cosmetic difference — a variable name, a reordered independent statement — is
not a material divergence. A different constant, a different call target, a
missing or extra branch is.

- [ ] **Step 6: Commit**

```bash
cd $REPO && git add $RECON/findings.md && \
  git commit -m "drivers-ppc: verify IONDRVSupport's twenty inherited bodies against the reference"
```

---

## Task 2: The twelve renames

**Files:**
- Modify: `$PPC/IONDRVFramebuffer.m`

**Interfaces:**
- Consumes: Task 1's verdicts.
- Produces: source whose C definition names match the binary's symbols minus one underscore. Task 5 remaps and expects all 12 mapped.

All twelve are `static` in `IONDRVFramebuffer.m` and emit a doubled underscore:

| Source (wrong) | Binary symbol | Line |
| --- | --- | --- |
| `_m64WaitForIdle` | `_m64WaitForIdle` | 1227 |
| `_m64WaitForFIFO` | `_m64WaitForFIFO` | 1245 |
| `_m64Init` | `_m64Init` | 1270 |
| `_m64DoFill` | `_m64DoFill` | 1341 |
| `_m64DoBlit` | `_m64DoBlit` | 1368 |
| `_ixDoBlit` | `_ixDoBlit` | 1628 |
| `_ixDoFill` | `_ixDoFill` | 1637 |
| `_ixIdleEngine` | `_ixIdleEngine` | 1674 |
| `_ix3dDoBlit` | `_ix3dDoBlit` | 1870 |
| `_ix3dDoFill` | `_ix3dDoFill` | 1879 |
| `_ix3dIdleEngine` | `_ix3dIdleEngine` | 1897 |
| `_ix3dInterruptHandler` | `_ix3dInterruptHandler` | 1959 |

- [ ] **Step 1: Read the exact name list from the binary**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
from binrecon.macho import read_macho
d=read_macho(r'$REF')
n=[s['name'] for s in d['symbols'] if s.get('section')=='__TEXT,__text'
   and not s['name'].startswith(('-[','+['))]
print('total C symbols:', len(n))
print('starting __e   :', sum(1 for x in n if x.startswith('__e')))
print('the twelve     :', sorted(x for x in n if x.startswith(('_m64','_ix'))))"
```

Expect 124 C symbols, 59 beginning `__e`, and exactly the twelve above. **The
`__e*` count is the hazard's size — those must not move.**

- [ ] **Step 2: Record the before-state**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/symbol_name_check.py \
  --binary "$REF" \
  --source-dir $PPC/IONDRVFramebuffer.m --source-dir $PPC/IONDRVLibraries.m \
  --source-dir $PPC/IONDRVInterface.m --source-dir $PPC/IOPEFInternals.c \
  --source-dir $PPC/IOPEFLoader.c
```

Expected: 124 hand-written C symbols, **13 missing** — the twelve plus
`_eLMGetPowerMgrVars`. Save the output.

- [ ] **Step 3: Rename, one name at a time, word-bounded**

For each of the twelve names `Name` from the table, replace the identifier
`\b_Name\b` with `Name` throughout `IONDRVFramebuffer.m` — definition, any
declaration, and every call site.

**A blanket transformation over `_[A-Za-z]\w*` is prohibited.** It would strip the
underscore from the 59 `__e*` functions and break 58 of them.

Watch for prefix relationships among the twelve (`_ixDoBlit` versus
`_ix3dDoBlit`) — word-bounded replacement handles them; substring replacement does
not. Do not rewrite string literals.

- [ ] **Step 4: Verify with the gate**

Re-run Step 2's command. Expected: **exactly 1 missing** — `_eLMGetPowerMgrVars`,
which Task 4 writes. Any other name means the rename broke or missed something.

- [ ] **Step 5: Verify nothing else moved**

Take a whole-file token-multiset diff of `IONDRVFramebuffer.m` against the parent
commit. For each of the twelve, `drop(_Name)` must equal `rise(Name)`, and **no
other identifier's count may change** — in particular no `_e*` name.

A line-based check is not sufficient; Floppy's produced seven false positives.

- [ ] **Step 6: Full suite, then commit**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: `905 passed, 4 skipped`.

```bash
cd $REPO && git add $PPC/IONDRVFramebuffer.m && \
  git commit -m "driverkit: drop the spurious leading underscore from IONDRVSupport's blit and fill helpers"
```

---

## Task 3: Flatten the ATI class split

**Files:**
- Modify: `$PPC/IONDRVFramebuffer.m`, `$PPC/IONDRVFramebuffer.h`

**Interfaces:**
- Consumes: Task 1's verdicts for the 8 `IOATIMACH64NDRV` methods. **Do not proceed if Task 1 found them divergent.**
- Produces: source emitting the flat `-[IOATINDRV …]` symbols the binary carries. Task 5 expects `selector_check.py`'s `extra` to fall from 12.

The binary has a single flat `IOATINDRV : IONDRVFramebuffer` carrying nine
methods. Our tree splits it into three classes, so eight symbols Apple never
emitted are emitted.

The history, which Task 1 Step 1 confirms:

- Apple's Darwin 0.3 header **does** declare `@interface IOATIMACH64NDRV : IOATINDRV` — but empty.
- Apple's `.m` has **no** `@implementation IOATIMACH64NDRV`.
- `IOATIRAGE128NDRV` is **not** Apple's; `6f3d886c` added it.

- [ ] **Step 1: Move the eight bodies into `IOATINDRV`**

`@implementation IOATINDRV` runs 1135–1154 and `@implementation IOATIMACH64NDRV`
runs 1415–1595. Move the eight method bodies from the latter into the former,
leaving `IOATINDRV` with nine methods: its existing `getStartupMode:depth:` plus
`hideCursor:`, `initEngine`, `moveCursor:frame:token:`, `open`,
`setDisplayMode:depth:page:`, `setIntValues:forParameter:count:`,
`showCursor:frame:token:`, `tempFlags`.

Delete the now-empty `@implementation IOATIMACH64NDRV` block.

**Change no body text.** This is a move, verified by Task 1; a diff of the moved
lines against their originals must show only relocation.

- [ ] **Step 2: Keep Apple's empty declaration**

`IONDRVFramebuffer.h` declares `@interface IOATIMACH64NDRV : IOATINDRV`. **Keep
it.** It is genuinely Apple's — Darwin 0.3 has it — and costs nothing.

- [ ] **Step 3: Leave `IOATIRAGE128NDRV` alone**

Its `@implementation` at 1601–1618 and its declaration stay exactly as they are.
Added hardware support is a separate question from symbol correspondence, and
deleting a working Rage 128 path to lower a count would be the wrong trade.

- [ ] **Step 4: Check the selector gate**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/selector_check.py \
  "$REF" $PPC/IONDRVFramebuffer.m
```

Before this task: **12 extra, 10 missing**. Expect `extra` to fall to roughly 3
and `missing` to fall by 8. **Report the actual figures and enumerate every
remaining entry with its disposition** — do not tune toward a predicted number.

- [ ] **Step 5: Full suite, then commit**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: `905 passed, 4 skipped`.

```bash
cd $REPO && git add $PPC/IONDRVFramebuffer.m $PPC/IONDRVFramebuffer.h && \
  git commit -m "driverkit: flatten IOATIMACH64NDRV's methods into IOATINDRV to match the shipped binary"
```

---

## Task 4: The duplicates and the absent function

**Files:**
- Modify: `$PPC/IONDRVFramebuffer.m`, `$PPC/IONDRVLibraries.m`, `$RECON/findings.md`

**Interfaces:**
- Produces: three fewer duplicate definitions and one new function body. Task 5 expects `duplicate_candidates` to fall to 0 and the gate to reach 0 missing.

- [ ] **Step 1: Determine which copy of the duplicates survives**

`StdIntHandler`, `StdIntEnabler` and `StdIntDisabler` are each defined
**non-`static` in two files** — `IONDRVFramebuffer.m:602-612` and
`IONDRVLibraries.m:809-819`. Both are in the same link unit, so this is a
**duplicate-symbol link error**, not the benign `static`-shadows-`extern` pattern
seen on Floppy.

**The spec said to use the map's `source_path` to decide which file Apple's
definition belongs to. That does not work** — all three are
`duplicate_candidates`, and those entries carry no citation by construction:

```
['_StdIntHandler']  -> source_path None
['_StdIntEnabler']  -> source_path None
['_StdIntDisabler'] -> source_path None
```

Decide by evidence instead. Disassemble each at its reference address and compare
against **both** copies. If the two copies are textually identical, say so and
choose the file whose surrounding content the reference otherwise maps to — and
record the reasoning rather than presenting it as settled.

- [ ] **Step 2: Delete the losing copy**

Keep one definition of each. `IONDRVLibraries.m:822-824` builds `TVector`
structures from all three:

```c
static TVector _eStdIntHandler  = { StdIntHandler,  0 };
static TVector _eStdIntEnabler  = { StdIntEnabler,  0 };
```

so that file needs at least declarations after the change. Add them if the
definitions move out.

- [ ] **Step 3: Write `_eLMGetPowerMgrVars`**

At `0x5fd8`, 136-byte span. The only symbol in this binary with no definition site
anywhere under `src/`.

**Its leading underscore is correct.** It belongs to the 59-strong `_e*` family,
so the source name is `_eLMGetPowerMgrVars` and the emitted symbol is
`__eLMGetPowerMgrVars`. **Writing it bare would be the exact defect Task 2
removes** — the two cases sit two tasks apart and point opposite ways.

Span is a next-symbol delta and includes any trailing jump island; confirm the
true extent from its `blr`. Produce an instruction-by-instruction account with
every branch covered. Place it in `IONDRVLibraries.m` beside its `_e*` siblings
unless the disassembly says otherwise.

- [ ] **Step 4: Verify the gate reaches zero**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/symbol_name_check.py \
  --binary "$REF" \
  --source-dir $PPC/IONDRVFramebuffer.m --source-dir $PPC/IONDRVLibraries.m \
  --source-dir $PPC/IONDRVInterface.m --source-dir $PPC/IOPEFInternals.c \
  --source-dir $PPC/IOPEFLoader.c
```

Expected: 124 hand-written C symbols, **0 missing**, exit 0.

- [ ] **Step 5: Record uncertainties**

Anything you could not settle from evidence goes into `$RECON/findings.md` as a
numbered uncertainty with what you observed and what you would need — in
particular the reasoning behind Step 1's choice.

- [ ] **Step 6: Full suite, then commit**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: `905 passed, 4 skipped`.

```bash
cd $REPO && git add $PPC/IONDRVFramebuffer.m $PPC/IONDRVLibraries.m $RECON/findings.md && \
  git commit -m "driverkit: drop IONDRVSupport's duplicate interrupt shims and write _eLMGetPowerMgrVars"
```

---

## Task 5: Remap and acceptance

**Files:**
- Modify: `$RECON/source-map.json`, `$RECON/ledger.json`, `$RECON/findings.md`, `src/drivers-ppc/reconstruction/report.md`

- [ ] **Step 1: Regenerate the map**

```bash
cd $REPO && $VENVPY tools/binrecon/filter_named_functions.py \
  $ANALYSIS tools/binrecon/out/iondrvsupport-ppc/analysis-named.json

cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --reference-analysis tools/binrecon/out/iondrvsupport-ppc/analysis-named.json \
  --binary "$REF" \
  --source-dir $PPC/IONDRVFramebuffer.m --source-dir $PPC/IONDRVLibraries.m \
  --source-dir $PPC/IONDRVInterface.m --source-dir $PPC/IOPEFInternals.c \
  --source-dir $PPC/IOPEFLoader.c \
  --repo-root . --objc-methods \
  --output $RECON/source-map.json
```

Before this plan: mapped 165, unmapped 23, duplicate_candidates 3,
boundary_disputed 0 = 191. Expect `mapped` to rise by the 12 renamed plus the 8
moved plus the 1 written, and `duplicate_candidates` to reach 0. **Report what you
actually get.**

**Do not compare maps with `diff`.** `cli.py` writes CRLF on this host while
committed maps are LF, so `diff` reports every line as differing. Use a
parsed-JSON comparison.

- [ ] **Step 2: Bucket the functions**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/bucket_functions.py \
  tools/binrecon/out/iondrvsupport-ppc/analysis-named.json \
  $RECON/source-map.json
```

Both arguments are **positional**. Expected: `RECONCILES: yes`. Bucket 4 should
hold the two build-generated class methods. Bucket 6 is **not** the gap count —
account for what is in it.

- [ ] **Step 3: Run the invariant check**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
  --binary "$REF" --analysis tools/binrecon/out/iondrvsupport-ppc/analysis-named.json
```

Expect one violation — `-[IONDRVFramebuffer doControl:params:]` at `__text+0`,
reporting **code present**. That is a known exclusion, not a gap and not a
phantom; the opposite reading was retracted across 22 locations in this repo.

- [ ] **Step 4: Regenerate the ledger**

`seed_ledger.py` takes three **positional** arguments — source map, reference
binary, output:

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/seed_ledger.py \
  $RECON/source-map.json "$REF" $RECON/ledger.json
```

Verify programmatically that every entry's `source_line` agrees with the new map,
and state the entry count. **Do not skip this** — on the PPCSerialPort branch the
ledger was left unregenerated after a remap and all 64 of its citations were
wrong.

- [ ] **Step 5: Run both gates**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/symbol_name_check.py \
  --binary "$REF" \
  --source-dir $PPC/IONDRVFramebuffer.m --source-dir $PPC/IONDRVLibraries.m \
  --source-dir $PPC/IONDRVInterface.m --source-dir $PPC/IOPEFInternals.c \
  --source-dir $PPC/IOPEFLoader.c

cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/selector_check.py \
  "$REF" $PPC/IONDRVFramebuffer.m
```

Expected: 124 symbols / **0 missing** / exit 0; and `extra` reduced from 12 with
every remaining entry enumerated.

- [ ] **Step 6: Full suite**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: `905 passed, 4 skipped`. `PYTHONPATH` is required; without it collection
fails.

- [ ] **Step 7: State acceptance**

Against each of the spec's **eleven** acceptance items, say whether it passed and
with what evidence. Include the standing constraint: **nothing was compiled**, so
every claim is of correspondence to the binary, never of buildability — and
removing the duplicate removes a known link error without being a claim that the
tree links.

- [ ] **Step 8: Update the driver report**

Update IONDRVSupport's section in `src/drivers-ppc/reconstruction/report.md` with
the final numbers, and record what the completion changed: the 12 renames, the
class flattening, the duplicate removal, the one function, and the verification
verdict for the 20 inherited bodies.

- [ ] **Step 9: Commit**

```bash
cd $REPO && git add $RECON src/drivers-ppc/reconstruction/report.md && \
  git commit -m "drivers-ppc: remap IONDRVSupport and record completion acceptance"
```

---

## Self-Review

**Spec coverage.** §1 goal → Tasks 2–4. §2 measurement inputs → Global
Constraints. §2.1 five files → Global Constraints, every checker invocation.
§3 verification and the halt → Task 1. §4 the twelve → Task 2. §4.1 the hazard →
Global Constraints "THE HAZARD", Task 2 Steps 1/3/5. §5 flattening → Task 3.
§6 duplicates → Task 4 Steps 1–2. §7 the absent function → Task 4 Step 3.
§8 disciplines → Global Constraints. §9 acceptance items 1–11 → Task 1 Step 4
(1), Task 2 Steps 3–4 (2), Task 2 Steps 1/5 (3), Task 4 Step 4 (4), Task 3
Steps 1–3 (5), Task 3 Step 4 and Task 5 Step 5 (6), Task 4 Steps 1–2 (7), Task 4
Step 3 (8), Task 5 Steps 1–4 (9), Task 5 Steps 7–8 (10), Task 5 Step 6 (11).
§10 constraints → Global Constraints. §11 risks → Global Constraints "THE
HAZARD", Task 1 Step 5, Task 3 Interfaces.

**A spec instruction that does not work, corrected here.** §6 says to use the
map's `source_path` to decide which duplicate copy survives. All three are
`duplicate_candidates`, which carry no citation by construction — I verified all
three report `source_path: None`. Task 4 Step 1 substitutes a disassembly
comparison against both copies and requires the reasoning be recorded.

**Naming consistency.** The five `--source-dir` arguments are spelled identically
in Task 2 Step 2, Task 4 Step 4, Task 5 Steps 1 and 5.
`analysis-named.json` is produced in Task 5 Step 1 and consumed in Steps 2 and 3.
`$RECON` is `src/drivers-ppc/reconstruction/IONDRVSupport` throughout.

**Suite counts.** Baseline **905 passed, 4 skipped** from the repo root with
`PYTHONPATH=tools/binrecon`. No task adds tests, so every task expects 905.

**Known soft spot.** Task 3 Step 4's "roughly 3" is a prediction, not a
requirement — the step says to report the actual figure and enumerate the
remainder rather than tune toward it. The exact number depends on how
`selector_check.py` treats `IOATIRAGE128NDRV`'s method and the methods with no
reference counterpart, which no task has measured.
