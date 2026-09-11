# IODisplay Absent Methods Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Write the six functions Apple's `IODisplay_reloc` contains that `src/driverkit-3/libDriver/ppc` does not, each from its own disassembly.

**Architecture:** Three writing tasks ordered by difficulty — three small methods, then two medium, then the largest — each with its instruction-by-instruction account. A fourth task regenerates the source map to prove the selectors match and runs acceptance.

**Tech Stack:** Objective-C for DriverKit, Python 3.13 in `.venv-binrecon` for binrecon, 32-bit big-endian PowerPC disassembly.

**Spec:** [2026-07-27-iodisplay-absent-methods-design.md](../specs/2026-07-27-iodisplay-absent-methods-design.md)

## Global Constraints

```bash
REPO="D:/RhapsodiOS/.claude/worktrees/ppc-iodisplay-recon"
VENVPY="D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe"
DISASM="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/d97cb28c-f6f2-48c4-b66f-85d46244ce4d/scratchpad/iodisplay-disasm.txt"
cd $REPO
```

- **There is no PowerPC toolchain. Nothing here compiles, and nothing may claim to.** No `make`, no build attempt, no "ready to build".
- **All six go into `src/driverkit-3/libDriver/ppc/IOSmartDisplay.m`.** Do not create new files. Do not modify any other source file in that directory.
- **Match the file's existing style exactly** — brace placement, `UInt16`/`SInt16`/`IOReturn` spellings, comment idiom. Apple wrote this file; new code must not stand out by formatting.
- **Never modify `src/kernel-7/`, any measurement artifact, or any binrecon code.** binrecon's suite must stay at **845 passed, 4 skipped**.
- **Every instruction must be accounted for.** A branch with no counterpart in your source is a missed case or a misreading — both defects.
- **A confident guess is a defect; a recorded uncertainty is a result.** If the disassembly does not settle something, write it with the uncertainty in a comment and list it in your report.
- Commit messages: `driverkit: ` prefix, one to two lines, no metadata/trailers/emoji. **One commit per task.**

### The disassembly

`$DISASM` holds annotated listings for `_UnpackString`, `findADBDisplayInfoForType:`, `IOSMADBGetLogicalRegister:size:result:size:` and `_SMADBHandler`, with relocation targets. For the other two, regenerate with:

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY - <<'PY'
import json
a=json.load(open('tools/binrecon/out/iodisplay-ppc/published/analysis-reference-ida.json'))
fns={(f.get('names') or [None])[0]: f for f in a['functions'] if f.get('names')}
for t in ('+[IOSmartDisplay probe:]',
          '-[IOSmartADBDisplay IOSMADBGetAVDeviceID:size:]',
          '-[IOSmartADBDisplay IOSMADBSetLogicalRegister:size:]'):
    f=fns[t]
    print(f"\n===== {t} ({f['size']}B @ 0x{f['address']:x}) =====")
    for i in f['instructions']:
        print(f"  0x{i['address']:04x}: {i['mnemonic']:<9} {i.get('operands','')}")
PY
```

### Established — do not re-derive

- **Unnamed `sub_XXXX` targets are jump islands.** Resolve every `bl` through the Mach-O relocation table with `read_macho`; IDA's export does not carry it. `sub_4C` and `sub_1330` are both **`_objc_msgSend`**.
- **`IO_R_INVALID_ARG` is `(-706)`** — `src/driverkit-3/driverkit/return.h:44`. That is the `-0x2C2` / `li r3, -0x2C2` the `IOSMADB*` methods return. **Write the name.**
- **`IOSmartADBDisplay` ivars** (`IOSmartDisplay.m:67-74`): `UInt8 adbAddr`, `UInt8 waitAckValue`, `SInt16 avDisplayID`, `const AVDeviceInfo *deviceInfo`. The `lha` at `+0x120` is `avDisplayID`.
- **`setLogicalRegister:data:`** (`:463`) and **`getLogicalRegister:data:`** (`:486`) already exist, both `UInt16`.
- **`configTable` returns `IOConfigTable *`** (`IOTreeDevice.m:351`). No `_configTable` static exists in `IOSmartDisplay.m`; it must be introduced as a file-static `IOConfigTable *`.
- **Externals available:** `_IOMalloc`, `_IOSleep`, `_adb_devices`, `_adb_readreg`, `_adb_register_dev`, `_adb_writereg`, `_kprintf`, `_objc_msgSend`, `_objc_msgSendSuper`, `_sprintf`, `_strtol`.

---

## Task 1: The three small methods

**Files:** Modify `src/driverkit-3/libDriver/ppc/IOSmartDisplay.m`

Write `+[IOSmartDisplay probe:]` (60B @ `0x10`), `-[IOSmartADBDisplay IOSMADBGetAVDeviceID:size:]` (44B @ `0x1248`), `-[IOSmartADBDisplay IOSMADBSetLogicalRegister:size:]` (68B @ `0x12ec`).

- [ ] **Step 1: Dump all three disassemblies** using the Global Constraints snippet. Read all three before writing anything.

- [ ] **Step 2: Write `+probe:`**

The evidence: `mr r3, r5` puts the third argument (`deviceDescription`) in the receiver register; `r4` comes from the `configTable` selector reference; `bl` reaches `_objc_msgSend`; the result is stored to the `_configTable` static; `li r3, 1` returns.

Introduce the file-static `IOConfigTable *_configTable` near the top of the file, in the file's existing style. Write the method.

- [ ] **Step 3: Write the two `IOSMADB` wrappers**

`IOSMADBGetAVDeviceID:size:` dereferences its **size** argument (`lwz r0, 0(r6)`), compares to 4, returns `IO_R_INVALID_ARG` on mismatch, else `lha` from `+0x120` into `*param1`, returns 0.

`IOSMADBSetLogicalRegister:size:` compares its **size argument by value** (`cmpwi r6, 8`) — note the difference from the previous method, which dereferenced — returns `IO_R_INVALID_ARG` on mismatch, else calls `setLogicalRegister:data:` with `lhz` loads from offsets **+2** and **+6** of its first argument, returning that result.

Get the argument types right: one takes `size` by pointer, the other by value. The disassembly is the authority.

- [ ] **Step 4: Account for every instruction**

For each of the three, write a mapping from every instruction to the source construct that produces it. Every branch must be covered. Put this in your report.

- [ ] **Step 5: Confirm the file still parses as the tree expects**

```bash
cd $REPO && grep -c "^@implementation\|^@end" src/driverkit-3/libDriver/ppc/IOSmartDisplay.m
grep -n "probe:\|IOSMADBGetAVDeviceID\|IOSMADBSetLogicalRegister\|_configTable" src/driverkit-3/libDriver/ppc/IOSmartDisplay.m
```

`@implementation`/`@end` counts must still balance, and each new method must appear inside the right class's block.

- [ ] **Step 6: Commit**

```bash
cd $REPO && git add src/driverkit-3/libDriver/ppc/IOSmartDisplay.m && \
git commit -m "driverkit: write IOSmartDisplay probe: and the two IOSMADB wrappers

Reconstructed from IODisplay_reloc; no PowerPC toolchain exists to verify them."
```

---

## Task 2: `IOSMADBGetLogicalRegister:size:result:size:` and `_UnpackString`

**Files:** Modify `src/driverkit-3/libDriver/ppc/IOSmartDisplay.m`

`IOSMADBGetLogicalRegister:size:result:size:` (104B @ `0x1274`) and `_UnpackString` (232B @ `0x314`). Both listings are in `$DISASM`.

- [ ] **Step 1: Read both listings in full** before writing anything.

- [ ] **Step 2: Write `IOSMADBGetLogicalRegister:size:result:size:`**

A four-argument wrapper over `getLogicalRegister:data:`. Establish from the disassembly which arguments are checked, against what sizes, and how the result is returned. Follow the sibling wrappers' shape only where the instructions agree — **the two you already wrote differ from each other in exactly this respect**, so do not assume.

- [ ] **Step 3: Write `_UnpackString`**

A static C function using `_strtol` in a loop — confirmed by the relocation at `0x370`. It parses a string into a numeric array. Establish from the disassembly: the signature, the loop bound, the terminating condition, and what it returns. It saves six callee-saved registers (`r26`–`r31`) and the CR, so it has real state; account for each.

- [ ] **Step 4: Account for every instruction** in both, as Task 1 Step 4. `_UnpackString` has the most branches of anything in this plan — every one must be covered.

- [ ] **Step 5: Confirm the file structure**

```bash
cd $REPO && grep -c "^@implementation\|^@end" src/driverkit-3/libDriver/ppc/IOSmartDisplay.m
grep -n "IOSMADBGetLogicalRegister\|UnpackString" src/driverkit-3/libDriver/ppc/IOSmartDisplay.m
```

`_UnpackString` is a static C function and must sit **outside** any `@implementation` block.

- [ ] **Step 6: Commit**

```bash
cd $REPO && git add src/driverkit-3/libDriver/ppc/IOSmartDisplay.m && \
git commit -m "driverkit: write IOSmartDisplay's logical-register getter and UnpackString

Reconstructed from IODisplay_reloc; not compile-verified."
```

---

## Task 3: `findADBDisplayInfoForType:`

**Files:** Modify `src/driverkit-3/libDriver/ppc/IOSmartDisplay.m`

`-[IOSmartADBDisplay findADBDisplayInfoForType:]` (324B @ `0x754`) — the largest of the six. Listing in `$DISASM`.

- [ ] **Step 1: Read the listing in full.** Also read `_SMADBHandler` (68B @ `0xa48`), which is in `$DISASM` and **is already present in source** — it is included as a worked reference for how this file's ADB code looks compiled.

- [ ] **Step 2: Establish the shape before writing**

Its name and the `deviceInfo` ivar (`const AVDeviceInfo *`) suggest a table search returning a matching entry for a display type. Determine from the disassembly: what it searches, how the table is reached, the loop bound and termination, what it returns on hit and on miss. **Record which of these the disassembly settles and which it does not.**

- [ ] **Step 3: Write it**, in the file's style, inside `@implementation IOSmartADBDisplay`.

- [ ] **Step 4: Account for every instruction**, including every branch and the loop's exit paths.

- [ ] **Step 5: Confirm the file structure**

```bash
cd $REPO && grep -c "^@implementation\|^@end" src/driverkit-3/libDriver/ppc/IOSmartDisplay.m
grep -n "findADBDisplayInfoForType" src/driverkit-3/libDriver/ppc/IOSmartDisplay.m
```

- [ ] **Step 6: Commit**

```bash
cd $REPO && git add src/driverkit-3/libDriver/ppc/IOSmartDisplay.m && \
git commit -m "driverkit: write IOSmartADBDisplay findADBDisplayInfoForType:

Reconstructed from IODisplay_reloc; not compile-verified."
```

---

## Task 4: Regenerate the map and run acceptance

**Files:** Modify `src/drivers-ppc/reconstruction/IODisplay/{source-map.json,findings.md}`

- [ ] **Step 1: Regenerate the source map**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --objc-methods --scope-to-objc \
  --reference-analysis tools/binrecon/out/iodisplay-ppc/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/IODisplay.config/IODisplay_reloc" \
  --source-dir src/driverkit-3/libDriver/ppc \
  --repo-root . \
  --output src/drivers-ppc/reconstruction/IODisplay/source-map.json
```

- [ ] **Step 2: Confirm the six moved from unmapped to mapped**

```bash
cd $REPO && $VENVPY -c "
import json
d=json.load(open('src/drivers-ppc/reconstruction/IODisplay/source-map.json'))
print('mapped',len(d['mapped']),'unmapped',len(d['unmapped']),'dup',len(d['duplicate_candidates']),'disputed',len(d['boundary_disputed']))
for u in d['unmapped']: print('  unmapped:', u['reference_names'], u['size'])
"
```

Before this plan: mapped 18, unmapped 7. The five *Objective-C* methods among the six should now map, leaving only the two build-generated accessors unmapped. `_UnpackString` is a C function and is **outside `--scope-to-objc`'s view** — it will not appear in either list; that is expected, and its evidence is the bucket table instead.

**If a method you wrote does not map, its selector does not match the binary** — that is a real defect in your signature, not a tooling quirk. Report BLOCKED.

- [ ] **Step 3: Re-run the bucket reconciliation**

```bash
cd $REPO && $VENVPY tools/binrecon/bucket_functions.py \
  tools/binrecon/out/iodisplay-ppc/published/analysis-reference-ida.json \
  src/drivers-ppc/reconstruction/IODisplay/source-map.json
```

Must print `RECONCILES: yes`. `_UnpackString` should move from bucket 6 to bucket 5 once you resolve it by hand against the source you wrote.

- [ ] **Step 4: Verify the map loads**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
import json
from pathlib import Path
from binrecon.schema import load_json, load_source_map
MAP='src/drivers-ppc/reconstruction/IODisplay/source-map.json'
a=load_json(Path('tools/binrecon/out/iodisplay-ppc/published/analysis-reference-ida.json'))
m=json.load(open(MAP))
cov=set()
for c in ('mapped','unmapped','duplicate_candidates','boundary_disputed'): cov |= {e['address'] for e in m[c]}
before=len(a['functions']); a['functions']=[f for f in a['functions'] if f['address'] in cov]
print('analysis functions', before, '-> scoped', len(a['functions']))
load_source_map(Path(MAP), reference_analysis=a, repo_root=Path.cwd())
print('load_source_map OK')
"
```

- [ ] **Step 5: Update `findings.md`**

Rewrite the sections the change affects: `Correspondence`, `Buckets`, `Unmapped detail`. Replace the "six genuine unresolved gaps" account with what is now true, citing this spec. **State plainly that the six are written but not compile-verified**, and carry forward every uncertainty recorded in Tasks 1–3.

- [ ] **Step 6: Run the suites**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q && \
  $VENVPY tools/ppc_package_check.py
```

Expected: **845 passed, 4 skipped**, and `no divergences`. This plan touches neither, so any change is a regression.

- [ ] **Step 7: Walk the acceptance list**

Confirm each of spec §4's seven items with output. **Do not claim anything compiles, links, loads or is behaviourally correct** — spec §4's "Not claimed" paragraph governs. Item 5 proves the selectors match the binary; it does not prove the bodies do.

- [ ] **Step 8: Commit**

```bash
cd $REPO && git add src/drivers-ppc/reconstruction/IODisplay && \
git commit -m "drivers-ppc: remap IODisplay after writing its six absent functions"
```

---

## Notes for the executing agent

- **Nothing compiles here.** Do not attempt a build or claim one would succeed.
- **The disassembly is the authority**, not the method name, not a sibling method, not what would be reasonable.
- **Every instruction must be accounted for in writing.** That account is the deliverable as much as the code is.
- **Resolve `bl` targets through `read_macho`'s relocations.** Unnamed `sub_XXXX` are jump islands.
- **Write `IO_R_INVALID_ARG`, not `-706`.**
- **The two wrappers you write in Task 1 differ in how they take `size`** — one by pointer, one by value. Do not let one contaminate the other, and do not assume Task 2's takes either form.
- **If something is undetermined, say so in a comment and in your report.** Four material errors were caught in the equivalent SCSITape work; the ones that survive review are the confident-sounding ones.
