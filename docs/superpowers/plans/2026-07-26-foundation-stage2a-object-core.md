# Foundation Stage 2a: Object Core — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct Rhapsody's object core — `NSObject`, `NSProxy`, `NSAutoreleasePool`, two private helper classes, and the 25 C functions behind zones, object allocation and retain counting.

**Architecture:** A runtime-hosting gate runs first and decides whether Objective-C behaviour can be tested at all. The 25 C functions land next in `NSZone.m`, independent of that gate. The five classes follow in dependency order. Each module is verified by `binrecon abi-check` against a committed ABI baseline plus a C or Objective-C test suite on a Rhapsody guest.

**Tech Stack:** Python 3.12 (binrecon, pytest 9.1.1, jsonschema 4.26.0), IDA Professional 9.2, Objective-C compiled with gcc 2.7.2.1 on a native ppc Rhapsody 5.6 guest cross-compiling i386.

## Global Constraints

- Spec of record: [docs/superpowers/specs/2026-07-26-foundation-stage2a-object-core-design.md](../specs/2026-07-26-foundation-stage2a-object-core-design.md). Programme spec: [2026-07-26-foundation-i386-reconstruction-design.md](../specs/2026-07-26-foundation-i386-reconstruction-design.md).
- **Working directory is the worktree** `D:\RhapsodiOS\.claude\worktrees\foundation-recon` (branch `foundation-recon`). Run every command from there.
- **Reference of record:** the extracted thin i386 slice at `C:/Users/raynorpat/Downloads/test/Foundation-i386`, size **1630488**, SHA-256 **`1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6`**. Never point tooling at the fat container.
- **The venv lives at the main repo root and is gitignored, so this worktree has none.** Use `/d/RhapsodiOS/.venv-binrecon/Scripts/python.exe` with `PYTHONPATH=tools/binrecon`, which resolves `binrecon` to the worktree's copy.
- Test command: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q`
- **The full binrecon suite takes ~1-5 minutes** (baseline at stage 2a start: **798 passed, 4 skipped**). Run the focused file during red/green; run the full suite once before committing.
- **Known flake:** the angr subprocess tests (`tools/binrecon/tests/test_angr_adapter.py`, and an angr pipeline test in `tools/binrecon/tests/test_cli.py`) time out under load and pass standalone. If one fails, rerun it alone, confirm, and say so — do not report it as a regression.
- **No header under `src/Kits/Foundation` may be modified.** Hard constraint across the whole programme. If reconstruction appears to need a header change, stop and report.
- **Reconstruct, do not transcribe.** No `param_1`, `v3`, `sub_42501428`, or decompiler comments in committed source. Read `src/Kits/Foundation/NSDecimal.m` and `NSGeometry.m` for the house style: Apple's copyright header preserved, C89 (declarations at the top of a block, no `//` comments), working variables named for what they hold, comments explaining why.
- **Never `git add -A` or `git add .`** — this repo tracks `__pycache__`, and `tools/binrecon/out/` is gitignored evidence. Each commit step names its exact paths; use those.
- Commit messages: start with the subsystem (`binrecon: `, `Foundation: `, `docs: `), one line, describe behaviour not files, no trailers or metadata.
- Do not add Foundation to `src/Manifest` or build it as a framework — still deferred.

### Guest access

- Native ppc Rhapsody 5.6 at `10.10.0.241`, `cc-783.1` / gcc 2.7.2.1, cross-compiling i386 objects with `-arch i386`. The reference is the i386 slice, so `-arch i386` is required.
- Compile invocation, run inside the synced `Foundation` directory on the guest:
  `cc -c -arch i386 -I.. -I/System/Library/Frameworks/System.framework/Headers -o /tmp/NSZone.o NSZone.m`
  The `-I..` is load-bearing.
- Full procedure: `docs/superpowers/plans/notes/2026-07-26-foundation-compile-probe.md` (committed).
- The harness config `vm/vm.conf` is **untracked and exists only in the MAIN worktree** at `/d/RhapsodiOS/vm/vm.conf`. It contains a password. Reference that path directly — do **not** copy it into this worktree, where it is not gitignored and could be committed by accident.
- **The guest login shell is tcsh.** Bash-style `2>&1` silently kills a command with no output. Use `>&` and `$status`.
- `/build/source/src/Kits/Foundation` on the guest is shared with other sessions. Compile in an isolated sibling directory and clean up afterwards.

---

### Task 1: Prove the Objective-C runtime can host our root class

This is spec §2.3 and §3.2 step 1 — the stage's go/no-go gate. It decides whether the 168 Objective-C methods in Tasks 7–10 can be behaviourally tested at all. **It runs before any reconstruction.**

**Files:**
- Create: `docs/superpowers/plans/notes/2026-07-26-objc-hosting-probe.md`

**Interfaces:**
- Consumes: nothing.
- Produces: a recorded verdict plus, if it passes, the exact compile-and-link line Tasks 7–10 reuse verbatim to build Objective-C test binaries.

- [ ] **Step 1: Understand why this is not the same as stage 1's gate**

Stage 1 compiled leaf C functions and linked test binaries using a hand-written `test_link_stubs.m` that supplied a handful of missing Foundation symbols. Those stubs were written **on the guest and never committed**, so stage 1's test binaries are not reproducible from the tree.

`NSObject` cannot use that approach. It is the class the runtime dispatches through, so a test must run in a process where **our** `NSObject` is the registered root class. If the system Foundation is also linked, there are two `NSObject` implementations and the behaviour observed is not ours.

- [ ] **Step 2: Write the probe**

Create these two files in your isolated guest directory (not in the repo — this is a throwaway probe):

`probe_root.m`:

```objc
/*  Minimal Objective-C root class, to establish whether the guest runtime
    will host one supplied by us rather than by Foundation.  */

#import <objc/objc.h>
#import <objc/Object.h>

@interface ProbeRoot
{
    Class isa;
}
+ alloc;
+ new;
- init;
- free;
- (int)answer;
@end

@implementation ProbeRoot

+ alloc       { return class_createInstance(self, 0); }
+ new         { return [[self alloc] init]; }
- init        { return self; }
- free        { return object_dispose(self); }
- (int)answer { return 42; }

@end
```

`probe_main.m`:

```objc
#import <stdio.h>

@interface ProbeRoot
+ new;
- free;
- (int)answer;
@end

int main(void)
{
    id probe;
    int value;

    probe = [ProbeRoot new];
    if (probe == 0) {
        printf("FAIL: +new returned nil\n");
        return 1;
    }
    value = [probe answer];
    [probe free];

    printf("%s: answer=%d\n", value == 42 ? "PASS" : "FAIL", value);
    return value == 42 ? 0 : 1;
}
```

- [ ] **Step 3: Try to build and run it without Foundation**

On the guest, in your isolated directory:

```
cc -arch i386 -o probe probe_root.m probe_main.m -lobjc >& build.log
echo $status
./probe
```

Expected on success: `PASS: answer=42` and exit 0.

Record the **complete** build log either way — if it fails, the linker's exact complaint is the finding.

- [ ] **Step 4: If it fails, characterise the failure before giving up**

Distinguish three cases, because they have different consequences:

1. **Missing runtime symbols** (e.g. `class_createInstance` undefined) — try `-lobjc -lSystem`, and check what the guest actually provides with `nm -g /usr/lib/libobjc.a 2>/dev/null | head` or the equivalent for a dylib.
2. **The runtime demands a root class it recognises** (e.g. it wants `NSObject` or `Object` to pre-exist) — note precisely which symbol it demands.
3. **It links but crashes at run time** — capture where.

Record which case applies. Case 1 may be solvable; cases 2 and 3 likely mean Objective-C behavioural testing must wait for a linkable framework.

- [ ] **Step 5: Record the verdict**

Write `docs/superpowers/plans/notes/2026-07-26-objc-hosting-probe.md` containing: the two probe sources, the exact build command, the complete build log, the run output, and one of:

- `RESULT: hosted` — plus the exact compile-and-link line Tasks 7–10 must reuse.
- `RESULT: not hosted` — plus which of the three cases applied and the verbatim error.

- [ ] **Step 6: Gate**

If `not hosted`, **stop and report to the user.** Do not proceed to Task 2. Tasks 5 and 6 (the C functions) remain valid and could be done, but the stage's shape changes and the user decides.

If `hosted`, continue.

- [ ] **Step 7: Commit**

```bash
git add docs/superpowers/plans/notes/2026-07-26-objc-hosting-probe.md
git commit -m "Foundation: record whether the guest runtime hosts our root class"
```

---

### Task 2: Audit which exported symbols no module claims

Spec §5.4. Stage 1 found 12 exported `_NSInteger*` symbols owned by no module; stage 2a adds 25 more whose owner is unknowable from the binary. Both were caught by a human reading a review. This makes it mechanical, and run once it enumerates the remaining stages' hidden work in a single pass.

**Files:**
- Create: `tools/binrecon/binrecon/symbol_audit.py`
- Modify: `tools/binrecon/binrecon/cli.py`
- Test: `tools/binrecon/tests/test_symbol_audit.py` (create)

**Interfaces:**
- Consumes: `load_image(path) -> tuple[bytes, dict]` from `binrecon.macho`. Symbol records are `{"name": str, "address": int, "binding": str, "section": str | None}` — `binding` is `"external"` or `"local"`; `section` is `"__SEG,__sect"` for a definition and `None` for an import.
- Produces:
  - `binrecon.symbol_audit.unclaimed_text_symbols(document, assignment) -> list[str]` — sorted names of external `__TEXT,__text` symbols that no module claims. Objective-C method symbols (`-[…]`, `+[…]`) are excluded: they are attributed by `__OBJC,__module_info`, not by `symbols.json`.
  - CLI `binrecon symbol-audit --profile P --symbols FILE`, printing the unclaimed symbols and a count, exit 0 always (it is a report, not a gate).

- [ ] **Step 1: Write the failing test**

Create `tools/binrecon/tests/test_symbol_audit.py`:

```python
from binrecon.symbol_audit import unclaimed_text_symbols


DOCUMENT = {"symbols": [
    {"name": "_NSClaimed", "address": 0x1000, "binding": "external",
     "section": "__TEXT,__text"},
    {"name": "_NSOrphan", "address": 0x1040, "binding": "external",
     "section": "__TEXT,__text"},
    {"name": "_NSLocalHelper", "address": 0x1080, "binding": "local",
     "section": "__TEXT,__text"},
    {"name": "_NSConstant", "address": 0x2000, "binding": "external",
     "section": "__TEXT,__const"},
    {"name": "_NSImported", "address": 0, "binding": "external",
     "section": None},
    {"name": "-[NSThing doThing]", "address": 0x10C0, "binding": "external",
     "section": "__TEXT,__text"},
]}


def test_reports_only_unclaimed_external_text_functions():
    assignment = {"NSThing.m": ["_NSClaimed"]}

    assert unclaimed_text_symbols(DOCUMENT, assignment) == ["_NSOrphan"]


def test_everything_claimed_reports_nothing():
    assignment = {"NSThing.m": ["_NSClaimed", "_NSOrphan"]}

    assert unclaimed_text_symbols(DOCUMENT, assignment) == []


def test_claims_from_several_modules_are_all_honoured():
    assignment = {"A.m": ["_NSClaimed"], "B.m": ["_NSOrphan"]}

    assert unclaimed_text_symbols(DOCUMENT, assignment) == []
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_symbol_audit.py -q`

Expected: FAIL with `ModuleNotFoundError: No module named 'binrecon.symbol_audit'`.

- [ ] **Step 3: Implement it**

Create `tools/binrecon/binrecon/symbol_audit.py`:

```python
"""Report exported functions that no module's symbol assignment claims.

Objective-C definitions carry their owning module in ``__OBJC,__module_info``.
Plain C functions do not, so they are attributed by hand in ``symbols.json``.
Nothing checked that the hand-written assignment was complete, and two stages
have now each discovered exported functions it silently omitted.
"""


def unclaimed_text_symbols(document, assignment):
    """Return sorted names of exported functions no module claims.

    Objective-C method symbols are excluded: ``__module_info`` attributes them,
    so they are not the assignment's responsibility.
    """
    claimed = {name for names in assignment.values() for name in names}
    return sorted(
        symbol["name"] for symbol in document["symbols"]
        if symbol["binding"] == "external"
        and symbol["section"] == "__TEXT,__text"
        and not symbol["name"].startswith(("-[", "+["))
        and symbol["name"] not in claimed
    )
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_symbol_audit.py -q`

Expected: PASS, 3 tests.

- [ ] **Step 5: Register the CLI command**

In `tools/binrecon/binrecon/cli.py`, add `"symbol-audit"` to the `COMMANDS` tuple and register the parser beside the others:

```python
    symbol_audit = subparsers.add_parser("symbol-audit")
    symbol_audit.add_argument("--profile", required=True)
    symbol_audit.add_argument("--symbols", required=True)
```

Add to the import block at the top of `cli.py`:

```python
from binrecon.symbol_audit import unclaimed_text_symbols
```

`main` dispatches with inline `if args.command == ...:` blocks, each wrapping its
work in a try/except printing `binrecon: {error}` to stderr and returning 1.
`os`, `sys`, `json`, `hashlib` and `Path` are already imported at module level.
Follow that shape:

```python
    if args.command == "symbol-audit":
        try:
            profile = load_profile(Path(args.profile), os.environ)
            _payload, document = load_image(profile.reference.path)
            assignment = json.loads(Path(args.symbols).read_text())
            unclaimed = unclaimed_text_symbols(document, assignment)
            for name in unclaimed:
                print(name)
            print(f"symbol-audit: {len(unclaimed)} unclaimed exported function(s)",
                  file=sys.stderr)
            return 0
        except (OSError, ValueError, ValidationError) as error:
            print(f"binrecon: {error}", file=sys.stderr)
            return 1
```

- [ ] **Step 6: Run it against the real reference and record the result**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Foundation-i386" PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon symbol-audit --profile tools/binrecon/profiles/foundation-i386.json --symbols src/Kits/Foundation/reconstruction/symbols.json > /tmp/unclaimed.txt
wc -l /tmp/unclaimed.txt
grep -c "^_NSInteger" /tmp/unclaimed.txt
```

The `_NSInteger*` family (12 symbols) **must** appear — stage 1 established they are unclaimed, so their absence means the audit is not working. Record the total count and the first 40 names in your report; this is the programme-wide inventory the spec asked for.

- [ ] **Step 7: Run the full suite and commit**

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q`

Expected: PASS (baseline 798 passed, 4 skipped, plus 3 new tests).

```bash
git add tools/binrecon/binrecon/symbol_audit.py tools/binrecon/binrecon/cli.py tools/binrecon/tests/test_symbol_audit.py
git commit -m "binrecon: report exported functions that no module claims"
```

---

### Task 3: Assign 2a's symbols, scope the analysis, and run IDA

**Files:**
- Modify: `src/Kits/Foundation/reconstruction/symbols.json`
- Create: `tools/binrecon/profiles/foundation-i386-object-core.json`
- Create: `docs/superpowers/plans/notes/2026-07-26-object-core-analysis-run.md`

**Interfaces:**
- Consumes: `binrecon module-scope` and `binrecon analyze` (built in stage 1).
- Produces: `tools/binrecon/out/foundation-i386-object-core/published/analysis-reference-ida.json`, the analysis of record for Tasks 5–10.

- [ ] **Step 1: Add NSZone.m's 25 symbols to the assignment**

Per spec §2.1, **all 25 go to `NSZone.m`** — including the 7 that `NSObject.h`
declares. This deliberately overrides the attribute-by-declaring-header rule and
is a divergence in file organisation only; Task 11 records it.

Add this key to `src/Kits/Foundation/reconstruction/symbols.json`, preserving the
existing three modules:

```json
 "NSZone.m": [
  "_NSAllocateMemoryPages", "_NSAllocateObject", "_NSCopyMemoryPages",
  "_NSCopyObject", "_NSCreateZone", "_NSDeallocateMemoryPages",
  "_NSDeallocateObject", "_NSDecrementExtraRefCountWasZero",
  "_NSDefaultMallocZone", "_NSExtraRefCount", "_NSIncrementExtraRefCount",
  "_NSLogPageSize", "_NSPageSize", "_NSRealMemoryAvailable",
  "_NSRecycleZone", "_NSRoundDownToMultipleOfPageSize",
  "_NSRoundUpToMultipleOfPageSize", "_NSSetZoneName",
  "_NSShouldRetainWithZone", "_NSZoneCalloc", "_NSZoneFree",
  "_NSZoneFromPointer", "_NSZoneMalloc", "_NSZoneName", "_NSZoneRealloc"
 ]
```

Verify all 25 exist and none is a duplicate:

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -c "
import json, collections
from binrecon.macho import load_image
a = json.load(open('src/Kits/Foundation/reconstruction/symbols.json'))
_p, d = load_image(r'C:\Users\raynorpat\Downloads\test\Foundation-i386')
have = {s['name'] for s in d['symbols'] if s['section'] == '__TEXT,__text'}
z = a['NSZone.m']
print('count', len(z), 'unique', len(set(z)))
print('missing from binary:', [n for n in z if n not in have])
flat = [n for v in a.values() for n in v]
print('claimed twice:', [n for n, c in collections.Counter(flat).items() if c > 1])
"
```

Expected: `count 25 unique 25`, `missing from binary: []`, `claimed twice: []`.

- [ ] **Step 2: Write the profile without a scope**

Create `tools/binrecon/profiles/foundation-i386-object-core.json`. A **separate**
profile, not an edit to `foundation-i386.json` — overwriting stage 1's scope would
leave its analysis unreproducible (spec §3.3):

```json
{
  "schema_version": "profile-v1",
  "name": "Foundation i386 object core",
  "architecture": "i386",
  "endianness": "little",
  "reference": {
    "path": "${BINRECON_REFERENCE}",
    "expected_size": 1630488,
    "expected_sha256": "1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6"
  },
  "analyzers": {
    "ida": {
      "enabled": true,
      "executable": "C:/Program Files/IDA Professional 9.2/idat.exe",
      "timeout_seconds": 5400,
      "version": "9.2"
    },
    "ghidra": { "enabled": false },
    "angr": { "enabled": false }
  },
  "comparison": {
    "acceptance": "normalized-functions",
    "ignore_metadata": [],
    "entry_points": []
  },
  "output_dir": "../out/foundation-i386-object-core"
}
```

- [ ] **Step 3: Validate**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Foundation-i386" PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon validate --profile tools/binrecon/profiles/foundation-i386-object-core.json
```

Expected: `reference ...Foundation-i386 size=1630488 sha256=1165B906...`.

- [ ] **Step 4: Generate the scope**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Foundation-i386" PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon module-scope --profile tools/binrecon/profiles/foundation-i386-object-core.json --module NSObject.m --module NSProxy.m --module NSAutoreleasePool.m --module NSPrivate.m --module NSZone.m --symbols src/Kits/Foundation/reconstruction/symbols.json
```

**`NSZone.m` is not a module in the binary** (spec §2.1), so `module-scope` will
reject it with `image defines no module NSZone.m`. That is expected. Run it with
only the four real modules, then append the 25 C functions' ranges yourself:

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Foundation-i386" PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -c "
import json, os
from binrecon.macho import load_image
from binrecon.module_scope import function_ranges
_p, d = load_image(os.environ['BINRECON_REFERENCE'])
text = next(s for s in d['sections'] if s['name'] == '__TEXT,__text')
names = json.load(open('src/Kits/Foundation/reconstruction/symbols.json'))['NSZone.m']
print(json.dumps(function_ranges(d['symbols'], text, names), indent=1))
"
```

Merge the two range lists, sort by `start`, and paste into the profile as
`analysis_scope`. The total must be **193** ranges — 168 Objective-C methods plus
25 C functions. If it is not 193, stop and reconcile against spec §1.1.

- [ ] **Step 5: Analyse, timing the run**

The run will exceed a single command's timeout. Run it **in the background**,
redirecting to a scratch log, and poll:

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Foundation-i386" PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon analyze --profile tools/binrecon/profiles/foundation-i386-object-core.json
```

Expected: `complete: true` and a populated `tools/binrecon/out/foundation-i386-object-core/published/`. Stage 1's comparable run took 128 s.

If it fails with `IDA output exceeds maximum JSON size`, do **not** raise the limit. The cap is 64 MB (`tools/binrecon/binrecon/adapters/ida.py:31`) and stage 1 measured 15.1 MB, so this is unlikely; narrow to one module at a time if it happens.

- [ ] **Step 6: Confirm the export**

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -c "
import json
d = json.load(open('tools/binrecon/out/foundation-i386-object-core/published/analysis-reference-ida.json'))
print(d['input']['sha256'])
print(len(d['functions']), 'functions')
"
```

Expected: `1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6` and 193 functions.

- [ ] **Step 7: Record the run and commit**

Write `docs/superpowers/plans/notes/2026-07-26-object-core-analysis-run.md` with wall-clock, published JSON size, IDA version, and whether splitting was needed. Spec §5.5 and the programme spec's §5.2 want these so later stages size from data.

```bash
git add src/Kits/Foundation/reconstruction/symbols.json tools/binrecon/profiles/foundation-i386-object-core.json docs/superpowers/plans/notes/2026-07-26-object-core-analysis-run.md
git commit -m "binrecon: add the object-core profile and record its analysis run"
```

---

### Task 4: Commit the ABI baseline for the five modules

**Files:**
- Create: `src/Kits/Foundation/reconstruction/abi/NSObject.json`, `NSProxy.json`, `NSAutoreleasePool.json`, `NSPrivate.json`, `NSZone.json`

**Interfaces:**
- Consumes: `binrecon abi` (stage 1); `symbols.json` from Task 3.
- Produces: the committed ABI contract Task 11's `abi-check` measures against.

- [ ] **Step 1: Emit the four real modules**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Foundation-i386" PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon abi --profile tools/binrecon/profiles/foundation-i386-object-core.json --module NSObject.m --module NSProxy.m --module NSAutoreleasePool.m --module NSPrivate.m --symbols src/Kits/Foundation/reconstruction/symbols.json --output src/Kits/Foundation/reconstruction/abi
```

- [ ] **Step 2: Hand-build NSZone.json**

`NSZone.m` is not a module in the binary, so `binrecon abi` cannot emit it. Its
ABI is purely the 25 C symbols, all of which are functions in `__TEXT,__text`, so
`data_symbols` is empty. Write `src/Kits/Foundation/reconstruction/abi/NSZone.json`
with `schema_version` `"abi-v1"`, `module` `"NSZone.m"`, empty `classes` and
`categories`, `text_symbols` set to the 25 names from `symbols.json` sorted, and
empty `data_symbols`.

Generate it rather than typing it, so it cannot drift from `symbols.json`:

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -c "
import json, pathlib
names = json.load(open('src/Kits/Foundation/reconstruction/symbols.json'))['NSZone.m']
doc = {'schema_version': 'abi-v1', 'module': 'NSZone.m', 'classes': [],
       'categories': [], 'text_symbols': sorted(names), 'data_symbols': []}
p = pathlib.Path('src/Kits/Foundation/reconstruction/abi/NSZone.json')
p.write_text(json.dumps(doc, indent=1, sort_keys=True) + '\n')
print('wrote', p)
"
```

- [ ] **Step 3: Verify the contents against spec §1.1**

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -c "
import json, pathlib, jsonschema
schema = json.loads(pathlib.Path('tools/binrecon/binrecon/schema/abi-v1.json').read_text())
for name in ('NSObject', 'NSProxy', 'NSAutoreleasePool', 'NSPrivate', 'NSZone'):
    d = json.loads(pathlib.Path(f'src/Kits/Foundation/reconstruction/abi/{name}.json').read_text())
    jsonschema.validate(d, schema)
    print('%-18s classes %d  text %2d  data %d' % (name, len(d['classes']), len(d['text_symbols']), len(d['data_symbols'])))
    for c in d['classes']:
        print('     %-28s super=%-10s size=%-3d ivars=%d  -%d/+%d' % (
            c['name'], c['superclass'], c['instance_size'], len(c['ivars']),
            len(c['instance_methods']), len(c['class_methods'])))
"
```

Expected, exactly matching spec §1.1:

```
NSObject           classes 2  text  0  data 0
     _NSZombie                    super=NSProxy   size=4   ivars=0  -9/+0
     NSObject                     super=None      size=4   ivars=1  -37/+47
NSProxy            classes 1  text  0  data 0
     NSProxy                      super=None      size=4   ivars=1  -27/+20
NSAutoreleasePool  classes 1  text  0  data 0
     NSAutoreleasePool            super=NSObject  size=20  ivars=4  -8/+15
NSPrivate          classes 1  text  0  data 0
     _NSAutoreleasedMallocMemory  super=NSObject  size=12  ivars=2  -4/+1
NSZone             classes 0  text 25  data 0
```

Class ordering within a file may differ; the values must not. **Both root classes must show `super=None`** — spec §2.2 flags this as never previously exercised. If any value differs, stop and reconcile; this baseline is what every later gate measures against.

- [ ] **Step 4: Commit**

```bash
git add src/Kits/Foundation/reconstruction/abi
git commit -m "Foundation: record the ABI baseline for the object core"
```

---

### Task 5: Reconstruct the 18 zone and page functions

**Files:**
- Modify: `src/Kits/Foundation/NSZone.m`
- Create: `src/Kits/Foundation/reconstruction/tests/test_zone.c`

**Interfaces:**
- Consumes: the analysis from Task 3; declarations in `src/Kits/Foundation/NSZone.h` (do not modify).
- Produces: `NSCreateZone`, `NSRecycleZone`, `NSSetZoneName`, `NSZoneName`, `NSDefaultMallocZone`, `NSZoneFromPointer`, `NSZoneMalloc`, `NSZoneCalloc`, `NSZoneRealloc`, `NSZoneFree`, `NSPageSize`, `NSLogPageSize`, `NSRoundUpToMultipleOfPageSize`, `NSRoundDownToMultipleOfPageSize`, `NSRealMemoryAvailable`, `NSAllocateMemoryPages`, `NSDeallocateMemoryPages`, `NSCopyMemoryPages` — signatures exactly as `NSZone.h` declares them.

- [ ] **Step 1: Read the reference**

The analysis carries disassembly, not decompiled C. Reuse stage 1's committed helper:

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe src/Kits/Foundation/reconstruction/tests/dump.py _NSZone _NSCreateZone _NSRecycleZone _NSSetZoneName _NSDefaultMallocZone _NSPageSize _NSLogPageSize _NSRoundUp _NSRoundDown _NSRealMemory _NSAllocateMemoryPages _NSDeallocateMemoryPages _NSCopyMemoryPages
```

It defaults to stage 1's analysis path. Point it at this stage's by editing the `ANALYSIS` constant, or copy it to a scratch file with the path changed — **do not commit a change to `dump.py` that breaks stage 1's usage**; if you generalise it, take a `--analysis` argument defaulting to stage 1's path and say so in your report.

For pseudocode rather than raw disassembly, IDA 9.2 is at `C:/Program Files/IDA Professional 9.2/idat.exe` and the slice at `C:/Users/raynorpat/Downloads/test/Foundation-i386`.

- [ ] **Step 2: Write the failing tests**

Create `src/Kits/Foundation/reconstruction/tests/test_zone.c`:

```c
/*  Behavioural tests for the zone and page functions in NSZone.m, stage 2a
    of the Foundation reconstruction.  These are ordinary C over plain
    memory and need no Objective-C runtime.  */

#import <Foundation/NSZone.h>
#include <stdio.h>
#include <string.h>

static int failures = 0;

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #condition); \
            failures++; \
        } \
    } while (0)

static void test_page_size_is_a_power_of_two(void)
{
    unsigned size = NSPageSize();

    CHECK(size > 0);
    CHECK((size & (size - 1)) == 0);
    CHECK((1U << NSLogPageSize()) == size);
}

static void test_rounding_to_page_size(void)
{
    unsigned page = NSPageSize();

    CHECK(NSRoundUpToMultipleOfPageSize(0) == 0);
    CHECK(NSRoundUpToMultipleOfPageSize(1) == page);
    CHECK(NSRoundUpToMultipleOfPageSize(page) == page);
    CHECK(NSRoundUpToMultipleOfPageSize(page + 1) == 2 * page);

    CHECK(NSRoundDownToMultipleOfPageSize(0) == 0);
    CHECK(NSRoundDownToMultipleOfPageSize(page - 1) == 0);
    CHECK(NSRoundDownToMultipleOfPageSize(page) == page);
    CHECK(NSRoundDownToMultipleOfPageSize(page + 1) == page);
}

static void test_default_zone_exists(void)
{
    CHECK(NSDefaultMallocZone() != 0);
}

static void test_malloc_from_the_default_zone(void)
{
    NSZone *zone = NSDefaultMallocZone();
    char *block = (char *)NSZoneMalloc(zone, 64);

    CHECK(block != 0);
    memset(block, 0x5A, 64);
    CHECK(block[0] == 0x5A && block[63] == 0x5A);
    NSZoneFree(zone, block);
}

static void test_calloc_zeroes(void)
{
    NSZone *zone = NSDefaultMallocZone();
    unsigned char *block = (unsigned char *)NSZoneCalloc(zone, 16, 4);
    int i, nonzero;

    CHECK(block != 0);
    nonzero = 0;
    for (i = 0; i < 64; i++)
        if (block[i] != 0)
            nonzero++;
    CHECK(nonzero == 0);
    NSZoneFree(zone, block);
}

static void test_realloc_preserves_contents(void)
{
    NSZone *zone = NSDefaultMallocZone();
    char *block = (char *)NSZoneMalloc(zone, 16);

    strcpy(block, "preserved");
    block = (char *)NSZoneRealloc(zone, block, 128);
    CHECK(block != 0);
    CHECK(strcmp(block, "preserved") == 0);
    NSZoneFree(zone, block);
}

static void test_created_zone_round_trip(void)
{
    NSZone *zone = NSCreateZone(NSPageSize(), NSPageSize(), 1);
    void *block;

    CHECK(zone != 0);
    block = NSZoneMalloc(zone, 32);
    CHECK(block != 0);
    NSZoneFree(zone, block);
    NSRecycleZone(zone);
}

static void test_zone_from_pointer_finds_the_owning_zone(void)
{
    NSZone *zone = NSDefaultMallocZone();
    void *block = NSZoneMalloc(zone, 32);

    CHECK(NSZoneFromPointer(block) == zone);
    NSZoneFree(zone, block);
}

static void test_memory_pages_round_trip(void)
{
    unsigned page = NSPageSize();
    void *pages = NSAllocateMemoryPages(page * 2);
    void *copy;

    CHECK(pages != 0);
    memset(pages, 0x33, page * 2);

    copy = NSAllocateMemoryPages(page * 2);
    CHECK(copy != 0);
    NSCopyMemoryPages(pages, copy, page * 2);
    CHECK(((unsigned char *)copy)[0] == 0x33);
    CHECK(((unsigned char *)copy)[page * 2 - 1] == 0x33);

    NSDeallocateMemoryPages(pages, page * 2);
    NSDeallocateMemoryPages(copy, page * 2);
}

static void test_real_memory_available_is_plausible(void)
{
    CHECK(NSRealMemoryAvailable() > 0);
}

int main(void)
{
    test_page_size_is_a_power_of_two();
    test_rounding_to_page_size();
    test_default_zone_exists();
    test_malloc_from_the_default_zone();
    test_calloc_zeroes();
    test_realloc_preserves_contents();
    test_created_zone_round_trip();
    test_zone_from_pointer_finds_the_owning_zone();
    test_memory_pages_round_trip();
    test_real_memory_available_is_plausible();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
```

`NSSetZoneName` and `NSZoneName` take and return an `NSString *`, which does not
exist until stage 3, so no test above exercises them — an `@"..."` literal needs
`NSConstantString`, which is also stage 3. Implement both properly regardless
and record the deferral for Task 11's `divergences.md`.

- [ ] **Step 3: Run the tests to verify they fail**

On the guest, in an isolated sibling directory (tcsh — use `>&`, not `2>&1`):

```
cc -arch i386 -I.. -I/System/Library/Frameworks/System.framework/Headers -o /tmp/test_zone reconstruction/tests/test_zone.c NSZone.m >& build.log
echo $status
```

Expected: link failure on the undefined zone functions, since `NSZone.m` is still a stub.

- [ ] **Step 4: Write the implementations**

Replace the zone and page portion of `src/Kits/Foundation/NSZone.m`, keeping Apple's copyright header. Signatures must match `NSZone.h` exactly.

Rhapsody's zones sit on the Mach/BSD allocator, so expect `vm_allocate`/`vm_deallocate` or `malloc_zone_*` underneath — read what the reference actually calls rather than assuming, and name your helpers for what they do.

- [ ] **Step 5: Run the tests until they pass**

```
cc -arch i386 -I.. -I/System/Library/Frameworks/System.framework/Headers -o /tmp/test_zone reconstruction/tests/test_zone.c NSZone.m >& build.log
echo $status
/tmp/test_zone
```

Expected: `PASSED: 0 failure(s)`.

If a test disagrees with the reference's actual behaviour, the **reference is the authority** and the test changes. Record the correction for Task 11.

- [ ] **Step 6: Commit**

```bash
git add src/Kits/Foundation/NSZone.m src/Kits/Foundation/reconstruction/tests/test_zone.c
git commit -m "Foundation: reconstruct the zone and page allocators"
```

---

### Task 6: Reconstruct the 7 object-allocation and retain-count functions

Spec §5.3: these are the subtle part. `NSIncrementExtraRefCount` (612 bytes) and `NSDecrementExtraRefCountWasZero` (480) are an order of magnitude above this stage's method average because they implement a side table rather than an inline counter. Getting the overflow, the zero-transition return value, or the table's hashing wrong produces leaks or double-frees that **no ABI check detects**.

**Files:**
- Modify: `src/Kits/Foundation/NSZone.m`
- Create: `src/Kits/Foundation/reconstruction/tests/test_refcount.c`

**Interfaces:**
- Consumes: the zone functions from Task 5; declarations in `src/Kits/Foundation/NSObject.h` (do not modify).
- Produces: `NSAllocateObject`, `NSDeallocateObject`, `NSCopyObject`, `NSShouldRetainWithZone`, `NSExtraRefCount`, `NSIncrementExtraRefCount`, `NSDecrementExtraRefCountWasZero`.

- [ ] **Step 1: Read the reference**

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe src/Kits/Foundation/reconstruction/tests/dump.py _NSAllocateObject _NSDeallocateObject _NSCopyObject _NSShouldRetainWithZone _NSExtraRefCount _NSIncrementExtraRefCount _NSDecrementExtraRefCountWasZero
```

Pay attention to three things the tests below assert:
- Where the count lives. A freshly allocated object has an *extra* refcount of 0, not 1 — the object's own reference is implicit. Confirm this from the reference before writing anything.
- What `NSDecrementExtraRefCountWasZero` returns at the transition, and whether it decrements past zero.
- How the side table keys objects, and what happens on overflow.

- [ ] **Step 2: Write the failing tests**

Create `src/Kits/Foundation/reconstruction/tests/test_refcount.c`:

```c
/*  Behavioural tests for the object-allocation and retain-count functions in
    NSZone.m, stage 2a.  These operate on raw allocations rather than live
    Objective-C objects, so they need no runtime.  */

#import <Foundation/NSObject.h>
#import <Foundation/NSZone.h>
#include <stdio.h>
#include <string.h>

static int failures = 0;

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #condition); \
            failures++; \
        } \
    } while (0)

/*  A stand-in for an object: the runtime only requires that the first word
    be the isa pointer, which these tests never dereference.  */
static id make_object(void)
{
    NSZone *zone = NSDefaultMallocZone();
    void *raw = NSZoneCalloc(zone, 1, 16);
    return (id)raw;
}

static void release_object(id object)
{
    NSZoneFree(NSDefaultMallocZone(), (void *)object);
}

static void test_fresh_object_has_no_extra_references(void)
{
    id object = make_object();

    CHECK(NSExtraRefCount(object) == 0);
    release_object(object);
}

static void test_increment_then_read(void)
{
    id object = make_object();

    NSIncrementExtraRefCount(object);
    CHECK(NSExtraRefCount(object) == 1);

    NSIncrementExtraRefCount(object);
    CHECK(NSExtraRefCount(object) == 2);

    NSDecrementExtraRefCountWasZero(object);
    NSDecrementExtraRefCountWasZero(object);
    release_object(object);
}

static void test_decrement_reports_the_zero_transition(void)
{
    id object = make_object();

    NSIncrementExtraRefCount(object);
    CHECK(NSDecrementExtraRefCountWasZero(object) == NO);
    CHECK(NSExtraRefCount(object) == 0);

    CHECK(NSDecrementExtraRefCountWasZero(object) == YES);
    release_object(object);
}

static void test_counts_are_per_object(void)
{
    id first = make_object();
    id second = make_object();

    NSIncrementExtraRefCount(first);
    NSIncrementExtraRefCount(first);
    NSIncrementExtraRefCount(second);

    CHECK(NSExtraRefCount(first) == 2);
    CHECK(NSExtraRefCount(second) == 1);

    NSDecrementExtraRefCountWasZero(first);
    NSDecrementExtraRefCountWasZero(first);
    NSDecrementExtraRefCountWasZero(second);
    release_object(first);
    release_object(second);
}

static void test_many_objects_exercise_the_side_table(void)
{
    id objects[256];
    int i;

    for (i = 0; i < 256; i++) {
        objects[i] = make_object();
        NSIncrementExtraRefCount(objects[i]);
    }
    for (i = 0; i < 256; i++)
        CHECK(NSExtraRefCount(objects[i]) == 1);
    for (i = 0; i < 256; i++) {
        CHECK(NSDecrementExtraRefCountWasZero(objects[i]) == NO);
        release_object(objects[i]);
    }
}

static void test_deep_count_survives(void)
{
    id object = make_object();
    int i;

    for (i = 0; i < 1000; i++)
        NSIncrementExtraRefCount(object);
    CHECK(NSExtraRefCount(object) == 1000);
    for (i = 0; i < 1000; i++)
        NSDecrementExtraRefCountWasZero(object);
    CHECK(NSExtraRefCount(object) == 0);
    release_object(object);
}

static void test_should_retain_with_zone(void)
{
    id object = make_object();

    /*  A nil zone means "any zone", so retaining is always allowed.  */
    CHECK(NSShouldRetainWithZone(object, 0) == YES);
    release_object(object);
}

int main(void)
{
    test_fresh_object_has_no_extra_references();
    test_increment_then_read();
    test_decrement_reports_the_zero_transition();
    test_counts_are_per_object();
    test_many_objects_exercise_the_side_table();
    test_deep_count_survives();
    test_should_retain_with_zone();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
```

`NSAllocateObject`, `NSDeallocateObject` and `NSCopyObject` take a `Class` and are not exercised here — they need a registered class, so their tests belong with Task 7's Objective-C suite. Implement them properly regardless; record the deferral for Task 11.

- [ ] **Step 3: Run the tests to verify they fail**

```
cc -arch i386 -I.. -I/System/Library/Frameworks/System.framework/Headers -o /tmp/test_refcount reconstruction/tests/test_refcount.c NSZone.m >& build.log
echo $status
```

Expected: link failure on the undefined refcount functions.

- [ ] **Step 4: Write the implementations**

Add them to `src/Kits/Foundation/NSZone.m`. Signatures exactly as `NSObject.h` declares them.

Reconstruct the side table's real structure from the reference rather than inventing a simpler one — its size, hashing and growth policy are observable behaviour that later stages depend on.

- [ ] **Step 5: Run both suites until they pass**

```
cc -arch i386 -I.. -I/System/Library/Frameworks/System.framework/Headers -o /tmp/test_refcount reconstruction/tests/test_refcount.c NSZone.m >& build.log
echo $status
/tmp/test_refcount
/tmp/test_zone
```

Expected: `PASSED: 0 failure(s)` from both — Task 5's suite must still pass.

If a test disagrees with the reference, the reference wins and the test changes. Record it for Task 11.

- [ ] **Step 6: Commit**

```bash
git add src/Kits/Foundation/NSZone.m src/Kits/Foundation/reconstruction/tests/test_refcount.c
git commit -m "Foundation: reconstruct object allocation and retain counting"
```

---

### Task 7: Reconstruct NSObject's instance methods

Spec §5.2: the risk here is volume, not complexity — 93 methods averaging 31 bytes, largest 116. `abi-check` catches a wrong selector or signature; it cannot catch a method whose body does the wrong correct-looking thing. This task takes the 37 instance methods; Task 8 takes the 47 class methods and `_NSZombie`.

**Files:**
- Modify: `src/Kits/Foundation/NSObject.m`
- Create: `src/Kits/Foundation/reconstruction/tests/link_stubs.m`
- Create: `src/Kits/Foundation/reconstruction/tests/test_object.m`

**Interfaces:**
- Consumes: Task 1's verdict and its link line; `NSZone.m`'s allocation and refcount functions from Tasks 5–6; declarations in `src/Kits/Foundation/NSObject.h` (do not modify).
- Produces: `@implementation NSObject` with the 37 instance methods in `abi/NSObject.json`, layout `superclass` null, `instance_size` 4, one ivar `isa` of type `#` at offset 0.

- [ ] **Step 1: Confirm Task 1 passed**

Read `docs/superpowers/plans/notes/2026-07-26-objc-hosting-probe.md`. If it records `RESULT: not hosted`, **stop** — this task cannot be behaviourally tested and the user has already been asked to decide. If it records `RESULT: hosted`, use its recorded link line for every build below.

- [ ] **Step 2: Commit the link stubs**

Stage 1's link stubs lived only on the guest and were never committed, so its test binaries cannot be rebuilt from the tree. Fix that here.

Create `src/Kits/Foundation/reconstruction/tests/link_stubs.m` supplying the minimum set of Foundation symbols the reconstructed modules reference but that stage 2a does not yet implement. Determine the set empirically — build, read the undefined-symbol list, and stub exactly those. Each stub must `abort()` rather than return a plausible value, so that a test accidentally depending on one fails loudly instead of silently passing:

```objc
/*  Link stubs for stage 2a's test binaries.

    Foundation symbols that the reconstructed modules reference but that this
    stage does not implement.  Every stub aborts: a test that reaches one is
    depending on unreconstructed behaviour and must fail loudly rather than
    quietly observing a plausible-looking default.  */

#include <stdio.h>
#include <stdlib.h>

static void unimplemented(const char *name)
{
    fprintf(stderr, "link stub reached: %s\n", name);
    abort();
}
```

Add one stub per undefined symbol, each calling `unimplemented("<name>")`.

- [ ] **Step 3: Write the failing tests**

Create `src/Kits/Foundation/reconstruction/tests/test_object.m`. Cover the instance methods whose behaviour is observable without the rest of Foundation — identity, equality, hashing, class introspection, retain/release/autorelease against Task 6's counters, and `respondsToSelector:`/`conformsToProtocol:`:

```objc
/*  Behavioural tests for NSObject's instance methods, stage 2a.  */

#import <Foundation/NSObject.h>
#include <stdio.h>

static int failures = 0;

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #condition); \
            failures++; \
        } \
    } while (0)

static void test_self_and_identity(void)
{
    id object = [[NSObject alloc] init];

    CHECK([object self] == object);
    CHECK([object isEqual:object]);
    CHECK(![object isEqual:nil]);
    [object release];
}

static void test_hash_is_stable_and_matches_equality(void)
{
    id object = [[NSObject alloc] init];
    unsigned first = [object hash];

    CHECK([object hash] == first);
    [object release];
}

static void test_distinct_objects_are_not_equal(void)
{
    id first = [[NSObject alloc] init];
    id second = [[NSObject alloc] init];

    CHECK(![first isEqual:second]);
    [first release];
    [second release];
}

static void test_class_introspection(void)
{
    id object = [[NSObject alloc] init];

    CHECK([object class] == [NSObject class]);
    CHECK([object isKindOfClass:[NSObject class]]);
    CHECK([object isMemberOfClass:[NSObject class]]);
    CHECK([object superclass] == nil);
    [object release];
}

static void test_responds_to_selector(void)
{
    id object = [[NSObject alloc] init];

    CHECK([object respondsToSelector:@selector(hash)]);
    CHECK(![object respondsToSelector:@selector(thisDoesNotExist)]);
    [object release];
}

static void test_retain_count_tracks_the_extra_count(void)
{
    id object = [[NSObject alloc] init];

    CHECK([object retainCount] == 1);
    [object retain];
    CHECK([object retainCount] == 2);
    [object release];
    CHECK([object retainCount] == 1);
    [object release];
}

static void test_retain_returns_self(void)
{
    id object = [[NSObject alloc] init];

    CHECK([object retain] == object);
    [object release];
    [object release];
}

int main(void)
{
    test_self_and_identity();
    test_hash_is_stable_and_matches_equality();
    test_distinct_objects_are_not_equal();
    test_class_introspection();
    test_responds_to_selector();
    test_retain_count_tracks_the_extra_count();
    test_retain_returns_self();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
```

`description` returns an `NSString` and is therefore untestable until stage 3; implement it properly and record the deferral.

Note the relationship this pins down: `retainCount` is `NSExtraRefCount(self) + 1`, which is why a fresh object reports 1 while its extra count is 0. Confirm that from the reference before relying on it.

- [ ] **Step 4: Run the tests to verify they fail**

Use Task 1's recorded link line, adding the reconstruction's sources:

```
cc -arch i386 -I.. -I/System/Library/Frameworks/System.framework/Headers -o /tmp/test_object reconstruction/tests/test_object.m NSObject.m NSZone.m reconstruction/tests/link_stubs.m -lobjc >& build.log
echo $status
```

Expected: FAIL — either a link error on the unimplemented methods or a run reporting failures.

- [ ] **Step 5: Write the implementations**

Replace `@implementation NSObject`'s instance methods in `src/Kits/Foundation/NSObject.m`, keeping Apple's copyright header. Exactly the 37 selectors in `abi/NSObject.json`'s `instance_methods`, with its type encodings.

Work through them in behavioural groups rather than file order — identity and equality, class introspection, message forwarding, retain/release, coding and copying — so review can follow the reasoning. That grouping is spec §5.2's mitigation and matters more here than anywhere else in the stage.

- [ ] **Step 6: Run the tests until they pass**

```
cc -arch i386 -I.. -I/System/Library/Frameworks/System.framework/Headers -o /tmp/test_object reconstruction/tests/test_object.m NSObject.m NSZone.m reconstruction/tests/link_stubs.m -lobjc >& build.log
echo $status
/tmp/test_object
```

Expected: `PASSED: 0 failure(s)`.

- [ ] **Step 7: Commit**

```bash
git add src/Kits/Foundation/NSObject.m src/Kits/Foundation/reconstruction/tests/test_object.m src/Kits/Foundation/reconstruction/tests/link_stubs.m
git commit -m "Foundation: reconstruct NSObject's instance methods"
```

---

### Task 8: Reconstruct NSObject's class methods and _NSZombie

**Files:**
- Modify: `src/Kits/Foundation/NSObject.m`
- Modify: `src/Kits/Foundation/reconstruction/tests/test_object.m`

**Interfaces:**
- Consumes: Task 7's `@implementation NSObject`.
- Produces: the 47 class methods in `abi/NSObject.json`, and `@implementation _NSZombie` with its 9 instance methods (superclass `NSProxy`, `instance_size` 4, no ivars).

- [ ] **Step 1: Read the reference**

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe src/Kits/Foundation/reconstruction/tests/dump.py '+[NSObject' '-[_NSZombie'
```

`_NSZombie` is the debugging aid that replaces a deallocated object's `isa` so later messages report the original class rather than crashing. Its methods are mostly one forwarding path — read it before assuming.

- [ ] **Step 2: Write the failing tests**

Append to `src/Kits/Foundation/reconstruction/tests/test_object.m` and call each from `main`:

```objc
static void test_class_side_allocation(void)
{
    id object = [NSObject alloc];

    CHECK(object != nil);
    CHECK([object class] == [NSObject class]);
    [object release];
}

static void test_new_allocates_and_initialises(void)
{
    id object = [NSObject new];

    CHECK(object != nil);
    CHECK([object retainCount] == 1);
    [object release];
}

static void test_class_introspection_on_the_class_object(void)
{
    CHECK([NSObject class] == [NSObject class]);
    CHECK([NSObject superclass] == nil);
    CHECK([NSObject isKindOfClass:[NSObject class]] == NO);
    CHECK([NSObject instancesRespondToSelector:@selector(hash)]);
    CHECK(![NSObject instancesRespondToSelector:@selector(thisDoesNotExist)]);
}

static void test_allocWithZone_uses_the_named_zone(void)
{
    NSZone *zone = NSDefaultMallocZone();
    id object = [NSObject allocWithZone:zone];

    CHECK(object != nil);
    CHECK([object zone] == zone);
    [object release];
}
```

- [ ] **Step 3: Run to verify the new tests fail**

```
cc -arch i386 -I.. -I/System/Library/Frameworks/System.framework/Headers -o /tmp/test_object reconstruction/tests/test_object.m NSObject.m NSZone.m reconstruction/tests/link_stubs.m -lobjc >& build.log
echo $status
/tmp/test_object
```

Expected: FAILED, with the new checks failing and Task 7's still passing.

- [ ] **Step 4: Write the implementations**

Add the 47 class methods and `@implementation _NSZombie` to `src/Kits/Foundation/NSObject.m`.

- [ ] **Step 5: Run until green**

Same command. Expected: `PASSED: 0 failure(s)`.

- [ ] **Step 6: Commit**

```bash
git add src/Kits/Foundation/NSObject.m src/Kits/Foundation/reconstruction/tests/test_object.m
git commit -m "Foundation: reconstruct NSObject's class methods and the zombie class"
```

---

### Task 9: Reconstruct NSProxy

**Files:**
- Modify: `src/Kits/Foundation/NSProxy.m`
- Create: `src/Kits/Foundation/reconstruction/tests/test_proxy.m`

**Interfaces:**
- Consumes: Task 7's link stubs and link line.
- Produces: `@implementation NSProxy` with 27 instance and 20 class methods per `abi/NSProxy.json` — a **root class**: `superclass` null, `instance_size` 4, one ivar `isa` of type `#` at offset 0.

- [ ] **Step 1: Read the reference**

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe src/Kits/Foundation/reconstruction/tests/dump.py '-[NSProxy' '+[NSProxy'
```

`NSProxy` is a second root class that exists to forward everything it does not implement. Its `forwardInvocation:` and `methodSignatureForSelector:` are abstract — read what the reference does when they are not overridden.

- [ ] **Step 2: Write the failing tests**

Create `src/Kits/Foundation/reconstruction/tests/test_proxy.m`:

```objc
/*  Behavioural tests for NSProxy, stage 2a.  NSProxy is a root class whose
    purpose is to forward; a concrete subclass supplies the forwarding.  */

#import <Foundation/NSProxy.h>
#import <Foundation/NSObject.h>
#include <stdio.h>

static int failures = 0;

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #condition); \
            failures++; \
        } \
    } while (0)

static void test_proxy_is_a_root_class(void)
{
    CHECK([NSProxy superclass] == nil);
}

static void test_alloc_produces_an_instance(void)
{
    id proxy = [NSProxy alloc];

    CHECK(proxy != nil);
    CHECK([proxy class] == [NSProxy class]);
    [proxy dealloc];
}

static void test_proxy_reports_its_own_class(void)
{
    id proxy = [NSProxy alloc];

    CHECK([proxy self] == proxy);
    [proxy dealloc];
}

static void test_retain_count_starts_at_one(void)
{
    id proxy = [NSProxy alloc];

    CHECK([proxy retainCount] == 1);
    [proxy dealloc];
}

int main(void)
{
    test_proxy_is_a_root_class();
    test_alloc_produces_an_instance();
    test_proxy_reports_its_own_class();
    test_retain_count_starts_at_one();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
```

`NSProxy`'s forwarding methods need `NSInvocation` and `NSMethodSignature`, which are stage 2c. Implement them properly; record the deferral for Task 11.

- [ ] **Step 3: Run to verify failure**

```
cc -arch i386 -I.. -I/System/Library/Frameworks/System.framework/Headers -o /tmp/test_proxy reconstruction/tests/test_proxy.m NSProxy.m NSObject.m NSZone.m reconstruction/tests/link_stubs.m -lobjc >& build.log
echo $status
```

Expected: link failure on the undefined `NSProxy` methods.

- [ ] **Step 4: Write the implementation, then run until green**

Replace `src/Kits/Foundation/NSProxy.m`'s body, keeping Apple's copyright header. Same build command; expected `PASSED: 0 failure(s)`.

- [ ] **Step 5: Commit**

```bash
git add src/Kits/Foundation/NSProxy.m src/Kits/Foundation/reconstruction/tests/test_proxy.m
git commit -m "Foundation: reconstruct NSProxy"
```

---

### Task 10: Reconstruct NSAutoreleasePool and the private malloc-memory class

**Files:**
- Modify: `src/Kits/Foundation/NSAutoreleasePool.m`
- Create: `src/Kits/Foundation/NSPrivate.m`
- Modify: `src/Kits/Foundation/Makefile`
- Create: `src/Kits/Foundation/reconstruction/tests/test_autoreleasepool.m`

**Interfaces:**
- Consumes: `NSObject` from Tasks 7–8; the refcount functions from Task 6.
- Produces: `@implementation NSAutoreleasePool` (8 instance, 15 class methods; superclass `NSObject`, `instance_size` 20, ivars `_token`, `_reserved3`, `_reserved2`, `_reserved` all `^v` at offsets 4/8/12/16) and `@implementation _NSAutoreleasedMallocMemory` (4 instance, 1 class method; superclass `NSObject`, `instance_size` 12, ivars `mutableBytes` `^v` @4 and `length` `I` @8).

- [ ] **Step 1: Create NSPrivate.m and register it**

`NSPrivate.m` does **not** exist in the tree — it is a private module with no public header, so the stub generation that produced the other 66 `.m` files skipped it.

Create `src/Kits/Foundation/NSPrivate.m` with Apple's copyright header in the same form as the other modules, and add `NSPrivate.m` to the `CLASSES` list in `src/Kits/Foundation/Makefile`, preserving the existing alphabetical-ish grouping and the trailing-backslash line continuations.

This is the first new source file the programme has added. Record it in Task 11's `divergences.md`.

- [ ] **Step 2: Read the reference**

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe src/Kits/Foundation/reconstruction/tests/dump.py '-[NSAutoreleasePool' '+[NSAutoreleasePool' '_NSAutoreleasedMallocMemory'
```

The pool's four ivars are all `void *` and three are named `_reserved*`, which suggests only `_token` is live — confirm what the reference actually stores. The class has nearly twice as many class methods as instance methods, so most of the API is class-level.

- [ ] **Step 3: Write the failing tests**

Create `src/Kits/Foundation/reconstruction/tests/test_autoreleasepool.m`:

```objc
/*  Behavioural tests for NSAutoreleasePool, stage 2a.  */

#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSObject.h>
#include <stdio.h>

static int failures = 0;

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #condition); \
            failures++; \
        } \
    } while (0)

static void test_pool_allocates_and_releases(void)
{
    id pool = [[NSAutoreleasePool alloc] init];

    CHECK(pool != nil);
    [pool release];
}

static void test_autoreleased_object_survives_until_the_pool_drains(void)
{
    id pool = [[NSAutoreleasePool alloc] init];
    id object = [[NSObject alloc] init];

    [object autorelease];
    CHECK([object retainCount] == 1);
    [pool release];
}

static void test_extra_retain_survives_the_pool(void)
{
    id pool = [[NSAutoreleasePool alloc] init];
    id object = [[[NSObject alloc] init] autorelease];

    [object retain];
    CHECK([object retainCount] == 2);
    [pool release];
    CHECK([object retainCount] == 1);
    [object release];
}

static void test_nested_pools_drain_independently(void)
{
    id outer = [[NSAutoreleasePool alloc] init];
    id object = [[[NSObject alloc] init] autorelease];
    id inner;

    [object retain];
    inner = [[NSAutoreleasePool alloc] init];
    [object autorelease];
    [inner release];
    CHECK([object retainCount] == 1);

    [outer release];
}

static void test_addObject_accepts_an_object(void)
{
    id pool = [[NSAutoreleasePool alloc] init];
    id object = [[NSObject alloc] init];

    [NSAutoreleasePool addObject:object];
    [pool release];
}

int main(void)
{
    test_pool_allocates_and_releases();
    test_autoreleased_object_survives_until_the_pool_drains();
    test_extra_retain_survives_the_pool();
    test_nested_pools_drain_independently();
    test_addObject_accepts_an_object();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
```

- [ ] **Step 4: Run to verify failure**

```
cc -arch i386 -I.. -I/System/Library/Frameworks/System.framework/Headers -o /tmp/test_pool reconstruction/tests/test_autoreleasepool.m NSAutoreleasePool.m NSPrivate.m NSObject.m NSZone.m reconstruction/tests/link_stubs.m -lobjc >& build.log
echo $status
```

Expected: link failure on the undefined pool methods.

- [ ] **Step 5: Write both implementations, then run until green**

Fill in `src/Kits/Foundation/NSAutoreleasePool.m` and `src/Kits/Foundation/NSPrivate.m`. Same build command; expected `PASSED: 0 failure(s)`.

- [ ] **Step 6: Commit**

```bash
git add src/Kits/Foundation/NSAutoreleasePool.m src/Kits/Foundation/NSPrivate.m src/Kits/Foundation/Makefile src/Kits/Foundation/reconstruction/tests/test_autoreleasepool.m
git commit -m "Foundation: reconstruct the autorelease pool and its private memory class"
```

---

### Task 11: Verify the stage and record divergences

**Files:**
- Modify: `src/Kits/Foundation/reconstruction/divergences.md`
- Modify: `src/Kits/Foundation/reconstruction/ownership.json`
- Create: `src/Kits/Foundation/reconstruction/object-core/source-map.json`
- Create: `src/Kits/Foundation/reconstruction/object-core/ledger.json`

**Interfaces:**
- Consumes: everything.
- Produces: the reviewed evidence that closes spec §4.

- [ ] **Step 1: Build the five objects and run abi-check**

Build `NSObject.o`, `NSProxy.o`, `NSAutoreleasePool.o`, `NSPrivate.o` and `NSZone.o` on the guest and retrieve them to a scratch directory outside the repo. Then:

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon abi-check --abi-dir src/Kits/Foundation/reconstruction/abi --built NSObject.m=/path/NSObject.o --built NSProxy.m=/path/NSProxy.o --built NSAutoreleasePool.m=/path/NSAutoreleasePool.o --built NSPrivate.m=/path/NSPrivate.o --built NSZone.m=/path/NSZone.o
```

**`--abi-dir` contains stage 1's three documents as well**, and `abi-check` reports a module with no `--built` object as a divergence. Pass stage 1's three objects too, or copy just the five 2a documents to a scratch directory and point `--abi-dir` there. Say which you did.

Expected: `abi-check: ABI matches`, exit 0. This is spec §4 gate 4, and the first time it compares real classes — **both root classes must come back with a null superclass**.

If it reports a divergence, fix the **source**, never the committed `abi/*.json`.

- [ ] **Step 2: Run every test suite**

```
/tmp/test_zone
/tmp/test_refcount
/tmp/test_object
/tmp/test_proxy
/tmp/test_pool
```

Expected: five `PASSED: 0 failure(s)` lines. Spec §4 criteria 5 and 6.

- [ ] **Step 3: Extend ownership.json and run source-map**

Add 2a's function names to `src/Kits/Foundation/reconstruction/ownership.json`, mapping each to its module. Note the naming rule stage 1 established: the **IDA analysis** names category methods without the category qualifier while the **symbol table** names them with it. `ownership.json` must match the analysis.

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon source-map --reference-analysis tools/binrecon/out/foundation-i386-object-core/published/analysis-reference-ida.json --binary "C:/Users/raynorpat/Downloads/test/Foundation-i386" --source-dir src/Kits/Foundation --repo-root . --objc-methods --ownership src/Kits/Foundation/reconstruction/ownership.json --output src/Kits/Foundation/reconstruction/object-core/source-map.json
```

`--objc-methods` is required or the Objective-C methods resolve to nothing.

Expected: all 193 functions in `mapped`, the other three buckets empty, and a `by_module` block accounting for all 193 across the five modules.

- [ ] **Step 4: Run compare and disposition the ledger**

Gate 3 is **evidence only**. Instruction divergence is expected — a per-module excerpt rebuild cannot be positionally correlated against the reference's profile-guided layout, which stage 1 established. Run `compare`, then review every entry and set its status with `binrecon ledger`, writing the output to `src/Kits/Foundation/reconstruction/object-core/ledger.json`.

**Record the review cost** — elapsed time and the per-function rate. Spec §5.5 asks for this specifically: stage 1's number measured CLI overhead because all 43 entries took one shared disposition, and 193 entries across five classes is the first chance at a usable figure for stages 3–5.

- [ ] **Step 5: Append to divergences.md**

It is shared and append-only across all ten stages; open with a heading for stage 2a. Record at minimum:

- **All 25 zone, allocation and refcount C functions live in `NSZone.m`**, though the reference has no `NSZone.m` module and 7 of them are declared in `NSObject.h`. A divergence in file organisation only; symbols, linkage and behaviour are unchanged. Include the reasoning from spec §2.1.
- **`NSPrivate.m` is a new file** the tree did not have, plus its `Makefile` registration.
- **The `binrecon symbol-audit` inventory from Task 2** — the total count of unclaimed exported functions and what that implies for the remaining stages. This is the programme-wide finding, so it belongs in the shared record.
- Every function implemented but not behaviourally tested, and which stage picks it up: `NSAllocateObject`/`NSDeallocateObject`/`NSCopyObject` (need a registered class), `description` and `NSSetZoneName`/`NSZoneName` (need `NSString`, stage 3), `NSProxy`'s forwarding methods (need `NSInvocation`, stage 2c).
- Every ledger entry's disposition, and the measured review cost.
- Any test expectation corrected against the reference, and what the reference actually does.
- Task 1's runtime-hosting verdict and what it means for later stages.

- [ ] **Step 6: Confirm no header changed**

Check against the commit stage 2a started from, not merely the previous task.
Find it with `git log --oneline --all | grep "spec the Foundation object core"`
— stage 2a's work begins immediately after that commit.

```bash
git diff --stat <stage-2a-base> HEAD -- 'src/Kits/Foundation/*.h'
```

Expected: empty output. Spec §4 criterion 10.

- [ ] **Step 7: Run the binrecon suite**

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```

Expected: PASS. Spec §4 criterion 9.

- [ ] **Step 8: Commit**

```bash
git add src/Kits/Foundation/reconstruction
git commit -m "Foundation: record stage 2a parity evidence and divergences"
```
