# IONDRVSupport Measurement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure Apple's shipped PowerPC `IONDRVSupport` against its in-tree source and produce the map, ledger, findings and a verified gap list, so that four follow-on specs can be written from evidence.

**Architecture:** Fix the scoping tooling first, because this driver's source shares a directory with three other binaries and the checkers currently return zero for a file path instead of erroring. Then profiles and analysis. Then re-derive the scoped file list and build the map against it. A final task enumerates the four clusters and records the Registry underscore exception.

**Tech Stack:** Python 3.13 in `.venv-binrecon`, binrecon CLI, IDA Professional 9.2 (reference analysis only), Mach-O/PowerPC big-endian.

**Spec:** [2026-07-28-iondrvsupport-measurement-design.md](../specs/2026-07-28-iondrvsupport-measurement-design.md)

## Global Constraints

```bash
VENVPY="D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe"
REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc/IONDRVSupport.config/IONDRVSupport_reloc"
PPC="src/driverkit-3/libDriver/ppc"
RECON="src/drivers-ppc/reconstruction/IONDRVSupport"
```

**Work in a dedicated worktree, not the main checkout.** Several worktrees are
active in this repository, and a shared git index lets parallel sessions
overwrite each other's commits. Create one from `qemu-debug-loop` before Task 1
and set `REPO` to it.

- **There is no PowerPC toolchain and no host C compiler. Nothing compiles, and you may not claim it does.** Do not run `make`.
- **This plan measures. Write no function bodies and rename nothing.**
- **Do not modify any source under `src/driverkit-3/`** — the follow-on specs do that.
- **Never modify `src/kernel-7/`.**
- **The disassembly is the authority** — not a function name, not what would be reasonable.
- **A confident guess is a defect; a recorded uncertainty is a result.**
- **Establish presence by a definition site** — never by an occurrence count, never by a regex over declaration syntax, never by `find | head -1`. Six ad-hoc surveys in this series were recorded as measurement and every one had to be retracted, including the one that reported this driver as having no source at all.
- Commits: `binrecon: ` for the tooling change, `drivers-ppc: ` for the artifacts. One to two lines, no metadata/trailers/emoji.

### The rule inverts for eight functions — read before interpreting any checker output

Eight functions carry a **double** underscore in the binary:

```
__eRegistryEntryIterateCreate    __eRegistryCStrEntryToName
__eRegistryEntryIterateDispose   __eRegistryCStrEntryCreate
__eRegistryEntryIterate          __eGetInterruptFunctions
__eInstallInterruptFunctions     __eLMGetPowerMgrVars
```

The Mach-O ABI prepends exactly one underscore, so `__eRegistryEntryIterate`
means Apple's source wrote **`_eRegistryEntryIterate`** — a legitimate leading
underscore.

**Five specs in this series stripped a leading underscore from every C name. That
reflex is wrong here.** `symbol_name_check.py` will report these eight as
"missing" against a bare spelling that must never be written. Record the
exception; do not act on it.

### The function at `__text` offset 0

`-[IONDRVFramebuffer doControl:params:]` sits at `__text+0`, first word
`7c0802a6` (`mflr r0`) — **real code**. IDA's function list has no entry there, so
`ppc_invariant_check` will report it as "not a function start", which means only
that IDA's list lacks an entry. It is **not** evidence of an absent body; that
misreading was recorded across five earlier specs and retracted in 22 places.

Unlike Floppy, this one **is** an Objective-C method, so `selector_check.py` can
confirm it once Task 1's scoping fix lands.

### Established before this plan — treat as predictions, not inputs

`__text` is 38,852 bytes across **192 defined symbols**. Classes:

```
IONDRVFramebuffer : IOFramebuffer     IOOFFramebuffer : IOFramebuffer
IOATINDRV  : IONDRVFramebuffer        IOIX3DNDRV : IONDRVFramebuffer
IOIXMNDRV  : IONDRVFramebuffer
IONDRVSupportVersion / IONDRVSupportKernelServerInstance  (build-generated)
```

An **unscoped** run reported 45 missing C functions (16,276 bytes), 8 missing
`IOATINDRV` methods, 1 missing data symbol, and **183 extra** selectors. Those
numbers will move once scoping lands. Task 3 re-derives them.

## File Structure

**Created:**
- `tools/binrecon/source_paths.py` — the file-or-directory resolver (Task 1)
- `tools/binrecon/tests/test_source_paths.py` — its tests (Task 1)
- `tools/binrecon/profiles/iondrvsupport-ppc.json`, `iondrvsupport-bundle-ppc.json` (Task 2)
- `$RECON/{source-map.json,ledger.json,findings.md}` (Tasks 3, 4)

**Modified:**
- `tools/binrecon/symbol_name_check.py` — `source_definitions`, `data_definitions` (Task 1)
- `tools/binrecon/selector_check.py` — `source_methods` (Task 1)
- `tools/binrecon/tests/test_profile.py` — `test_ppc_profile_inventory` (Task 2)

---

## Task 1: Teach the checkers to accept a file path

**Files:**
- Create: `tools/binrecon/source_paths.py`, `tools/binrecon/tests/test_source_paths.py`
- Modify: `tools/binrecon/symbol_name_check.py:44` (`source_definitions`), `:60` (`data_definitions`), `tools/binrecon/selector_check.py:64` (`source_methods`), `tools/binrecon/binrecon/source_map.py:130` (`source_sites`)

**Interfaces:**
- Produces: `source_files(path, suffixes, recursive=True) -> list[Path]` in `tools/binrecon/source_paths.py`, used by all three call sites and by Task 3.

`source_definitions()` does `Path(source_dir).rglob("*")`, which yields **nothing**
for a file path. Verified against the tree:

```
given a FILE path : 0 definitions
given its DIR     : 152 definitions
```

**Silently returning zero is the dangerous shape** — a scoped gate reads green
while measuring nothing. This driver needs file-granular scoping because its
source shares a directory with three other binaries.

- [ ] **Step 1: Write the failing tests**

Create `tools/binrecon/tests/test_source_paths.py`:

```python
import pytest

from source_paths import source_files


def test_a_directory_yields_its_source_files(tmp_path):
    (tmp_path / "a.m").write_text("")
    (tmp_path / "b.c").write_text("")
    (tmp_path / "notes.txt").write_text("")
    found = source_files(tmp_path, {".m", ".c"})
    assert [p.name for p in found] == ["a.m", "b.c"]


def test_a_file_yields_just_that_file(tmp_path):
    (tmp_path / "a.m").write_text("")
    (tmp_path / "b.m").write_text("")
    found = source_files(tmp_path / "a.m", {".m", ".c"})
    assert [p.name for p in found] == ["a.m"]


def test_a_file_of_the_wrong_suffix_raises(tmp_path):
    (tmp_path / "notes.txt").write_text("")
    with pytest.raises(ValueError, match="not a source file"):
        source_files(tmp_path / "notes.txt", {".m", ".c"})


def test_a_directory_with_no_source_files_raises(tmp_path):
    (tmp_path / "notes.txt").write_text("")
    with pytest.raises(ValueError, match="no source files"):
        source_files(tmp_path, {".m", ".c"})


def test_a_missing_path_raises(tmp_path):
    with pytest.raises(ValueError, match="does not exist"):
        source_files(tmp_path / "absent", {".m", ".c"})


def test_recursive_finds_a_nested_file(tmp_path):
    (tmp_path / "sub").mkdir()
    (tmp_path / "sub" / "a.m").write_text("")
    assert [p.name for p in source_files(tmp_path, {".m"})] == ["a.m"]


def test_non_recursive_skips_a_nested_file(tmp_path):
    (tmp_path / "top.m").write_text("")
    (tmp_path / "sub").mkdir()
    (tmp_path / "sub" / "nested.m").write_text("")
    found = source_files(tmp_path, {".m"}, recursive=False)
    assert [p.name for p in found] == ["top.m"]
```

- [ ] **Step 2: Run them and confirm they fail**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest \
  tools/binrecon/tests/test_source_paths.py -q
```

Expected: collection error — `No module named 'source_paths'`.

- [ ] **Step 3: Write the resolver**

Create `tools/binrecon/source_paths.py`:

```python
"""Resolve a source-tree argument that may name a file or a directory.

The checkers used to walk a directory and silently yield nothing when handed a
file path. A gate built on that reads green while measuring nothing, which is
exactly the failure this module removes: every path that cannot produce source
files raises instead.

File granularity matters because some drivers' sources share a directory with
other binaries' sources — `IONDRVSupport` is three files out of eleven in
`src/driverkit-3/libDriver/ppc`.
"""

from pathlib import Path


def source_files(path, suffixes, recursive=True):
    """Return the source files named by path, which may be a file or directory.

    `suffixes` is a set such as {".m", ".c"}. Raises ValueError rather than
    returning an empty list, so a mis-scoped argument cannot pass unnoticed.
    """
    root = Path(path)
    if not root.exists():
        raise ValueError(f"{root} does not exist")
    if root.is_file():
        if root.suffix not in suffixes:
            raise ValueError(
                f"{root} is not a source file; expected one of {sorted(suffixes)}"
            )
        return [root]
    walk = root.rglob("*") if recursive else root.glob("*")
    found = sorted(p for p in walk if p.suffix in suffixes)
    if not found:
        raise ValueError(f"no source files matching {sorted(suffixes)} under {root}")
    return found
```

- [ ] **Step 4: Run them and confirm they pass**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest \
  tools/binrecon/tests/test_source_paths.py -q
```

Expected: `7 passed`.

- [ ] **Step 5: Route the three call sites through it, preserving each one's semantics**

`symbol_name_check.py:44` `source_definitions` and `:60` `data_definitions` both
walk with `rglob` over `.m` and `.c` — use `source_files(source_dir, {".m", ".c"})`,
recursive.

`selector_check.py:64` `source_methods` walks with **non-recursive** `glob("*.m")` —
use `source_files(source_dir, {".m"}, recursive=False)`. **Do not make it
recursive**; that would change results for every existing caller.

`binrecon/source_map.py:130` `source_sites` is the fourth call site and the one
that matters most here:

```python
paths = sorted(Path(source_dir).glob("*.m")) + sorted(Path(source_dir).glob("*.c"))
```

Non-recursive, and it yields nothing for a file path — so without this change
Task 3 would map **nothing** while looking like "every function is absent". Use
`source_files(source_dir, {".m", ".c"}, recursive=False)`.

**Note the ordering change**: today all `.m` files sort first, then all `.c`;
`source_files` returns one sorted list. Step 6 checks whether that matters.

Rename each function's parameter from `source_dir` to `source_path`, since all
four now accept either.

`selector_check.py` and `binrecon/source_map.py` will both need
`from source_paths import source_files`; `tools/binrecon/` is on `PYTHONPATH`.

- [ ] **Step 6: Confirm existing behaviour is unchanged**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: `892 passed, 4 skipped` — the baseline is 885 plus your 7. If the count
differs, say so rather than adjusting the expectation.

Then spot-check that a directory argument still gives the same answer as before:

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
from symbol_name_check import source_definitions
print(len(source_definitions('$PPC')))"
```

Expected: `152`, the figure measured before this change.

**Then prove `source_sites`' ordering change is inert** by rebuilding an existing
driver's map from a directory argument and diffing it against the committed one:

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map   --reference-analysis tools/binrecon/out/floppy-ppc/analysis-named.json   --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/Floppy.config/Floppy_reloc"   --source-dir src/drivers-ppc/ide/drvPPCSwimFloppy/Floppy.drvproj/Floppy.lksproj   --repo-root . --objc-methods --output /tmp/floppy-check.json
diff /tmp/floppy-check.json src/drivers-ppc/reconstruction/Floppy/source-map.json
```

Expected: **no difference**. If the files differ, the ordering change is not inert
and you must preserve the original `.m`-then-`.c` order instead. Write the scratch
file somewhere both the MSYS shell and the Windows Python can see — `/tmp` is
MSYS-local.

- [ ] **Step 7: Commit**

```bash
cd $REPO && git add tools/binrecon/source_paths.py \
  tools/binrecon/tests/test_source_paths.py \
  tools/binrecon/symbol_name_check.py tools/binrecon/selector_check.py && \
  git commit -m "binrecon: let the source checkers take a file, not only a directory"
```

---

## Task 2: Profiles, inventory test, reference analysis

**Files:**
- Create: `tools/binrecon/profiles/iondrvsupport-ppc.json`, `tools/binrecon/profiles/iondrvsupport-bundle-ppc.json`
- Modify: `tools/binrecon/tests/test_profile.py`

**Interfaces:**
- Produces: the analysis JSON under `tools/binrecon/out/iondrvsupport-ppc/published/`, consumed by Tasks 3 and 4.

- [ ] **Step 1: Add both profiles to the inventory test — RED first**

`test_ppc_profile_inventory` asserts the complete sorted list. The two new names
sort between `iodisplay-ppc.json` and `mace-bundle-ppc.json`:

```python
        "iodisplay-bundle-ppc.json", "iodisplay-ppc.json",
        "iondrvsupport-bundle-ppc.json", "iondrvsupport-ppc.json",
        "mace-bundle-ppc.json", "mace-ppc.json",
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest \
  tools/binrecon/tests/test_profile.py::test_ppc_profile_inventory -q
```

Expected: FAIL naming exactly the two missing files.

- [ ] **Step 3: Create `iondrvsupport-ppc.json`**

```json
{
  "schema_version": "profile-v1",
  "name": "IONDRVSupport ppc reconstruction",
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
  "output_dir": "../out/iondrvsupport-ppc"
}
```

- [ ] **Step 4: Create `iondrvsupport-bundle-ppc.json`**

Identical except:

```json
  "name": "IONDRVSupport bundle ppc reconstruction",
  "output_dir": "../out/iondrvsupport-bundle-ppc"
```

- [ ] **Step 5: Run the profile tests and confirm they pass**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests/test_profile.py -q
```

Expected: PASS. `test_ppc_profiles_are_reference_only_ida_runs` is parametrised
over every PPC profile and will exercise both new ones.

- [ ] **Step 6: Run the reference analysis**

```bash
cd $REPO && BINRECON_REFERENCE="$REF" PYTHONPATH=tools/binrecon \
  $VENVPY -m binrecon analyze --profile tools/binrecon/profiles/iondrvsupport-ppc.json
```

**Expected: exit 1, and that is correct.** `cli.py:105` returns 0 only when
acceptance passes, and a reference-only profile has no `rebuilt` binary to
compare, so `normalized-functions` can never pass. What matters is that the run
reports `analysis complete` and publishes under
`tools/binrecon/out/iondrvsupport-ppc/published/`. A real failure prints
`analysis incomplete` or a `binrecon: {error}` on stderr — report either.

The analysis JSON is
`tools/binrecon/out/iondrvsupport-ppc/published/analysis-reference-ida.json`;
later steps call it `$ANALYSIS`.

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
contradicts the plan; report it rather than proceeding.

- [ ] **Step 8: Full suite, then commit**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: `894 passed, 4 skipped` — 892 from Task 1 plus one parametrised case per
new profile.

```bash
cd $REPO && git add tools/binrecon/profiles tools/binrecon/tests/test_profile.py && \
  git commit -m "drivers-ppc: add the IONDRVSupport binrecon profiles"
```

---

## Task 3: Scope the source, build the map

**Files:**
- Create: `$RECON/source-map.json`, `$RECON/ledger.json`

**Interfaces:**
- Consumes: `source_files()` from Task 1; `$ANALYSIS` from Task 2.
- Produces: `$RECON/source-map.json` and the confirmed scoped file list, both consumed by Task 4.

- [ ] **Step 1: Re-derive the scoped file list**

**Do not take the list below as input.** It is my own derivation, produced by the
same definition-matching method that has given six wrong answers in this series —
including one that reported this driver as having no source at all.

Derive it yourself: read the binary's `__TEXT,__text` symbol names, then for each
`.m` file in `$PPC` count how many of those names it defines (C functions by
definition site, Objective-C methods by selector). Report the full table.

My derivation, for comparison only:

| File | C definitions | Selectors |
| --- | --- | --- |
| `IONDRVLibraries.m` | 54 | 0 |
| `IONDRVFramebuffer.m` | 8 | 48 |
| `IONDRVInterface.m` | 5 | 0 |

and eight files contributing nothing but coincidental selector matches, of which
`IOFramebuffer.m` is the largest at 11 — it is the superclass of two of this
binary's classes, so names like `open` and `free` collide.

**If your table disagrees with mine, yours is the evidence.** Say so and proceed
on yours.

- [ ] **Step 2: Confirm the scoping fix changes the selector result**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/selector_check.py \
  "$REF" $PPC
```

Expected: **183 extra** — the unscoped baseline. Record it.

Then run it once per scoped file and combine, or extend the invocation if
`selector_check.py` takes only one path. Expected after scoping: **0 extra**. If
you cannot reach 0, enumerate what remains and why.

- [ ] **Step 3: Filter unnamed functions**

```bash
cd $REPO && $VENVPY tools/binrecon/filter_named_functions.py \
  $ANALYSIS tools/binrecon/out/iondrvsupport-ppc/analysis-named.json
```

Expected: exit 0. Re-run Task 2 Step 7's snippet against the output; `unnamed`
must be 0 and `input.sha256` unchanged.

- [ ] **Step 4: Build the source map over the scoped files**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --reference-analysis tools/binrecon/out/iondrvsupport-ppc/analysis-named.json \
  --binary "$REF" \
  --source-dir $PPC/IONDRVFramebuffer.m \
  --source-dir $PPC/IONDRVLibraries.m \
  --source-dir $PPC/IONDRVInterface.m \
  --repo-root . \
  --objc-methods \
  --output $RECON/source-map.json
```

`--source-dir` is repeatable, and Task 1 Step 5 taught `source_map.py:130`'s
walker to accept a file. If it still rejects one, stop and say so rather than
falling back to the directory — a directory argument here silently pulls in three
other binaries' sources.

Use **your** file list from Step 1, not necessarily these three.

- [ ] **Step 5: Check coverage across all four categories**

```bash
cd $REPO && $VENVPY -c "
import json
m=json.load(open('$RECON/source-map.json'))
for k in ('mapped','unmapped','duplicate_candidates','boundary_disputed'):
    v=m.get(k,[]); print(f'{k}: {len(v)}')
    for e in v[:80]: print('   ', e.get('name') or e)"
```

Do not judge coverage from `mapped` and `unmapped` alone — an earlier spec in this
series missed addresses that way. Every `duplicate_candidates` and
`boundary_disputed` entry needs an explanation in Task 4's findings.

- [ ] **Step 6: Bucket the functions**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/bucket_functions.py \
  tools/binrecon/out/iondrvsupport-ppc/analysis-named.json \
  $RECON/source-map.json
```

Both arguments are **positional**. Expected: a table ending `RECONCILES: yes`.
Bucket 4 should hold the two build-generated class methods. Bucket 6 is **not**
the gap count — account for what is in it.

- [ ] **Step 7: Run the PowerPC invariant check**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
  --binary "$REF" --analysis tools/binrecon/out/iondrvsupport-ppc/analysis-named.json
```

Expect the `-[IONDRVFramebuffer doControl:params:]` line to report **code
present**. Any other violation gets a written explanation — the single violation
deserves more scrutiny than the clean relocations, not less.

- [ ] **Step 8: Seed the ledger**

`seed_ledger.py` takes three **positional** arguments — source map, reference
binary, output:

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/seed_ledger.py \
  $RECON/source-map.json "$REF" $RECON/ledger.json
```

Then verify programmatically that every entry's `source_line` agrees with the map,
and record the entry count.

- [ ] **Step 9: Commit**

```bash
cd $REPO && git add $RECON && \
  git commit -m "drivers-ppc: map IONDRVSupport against its scoped source files"
```

---

## Task 4: Findings, cluster enumeration, acceptance

**Files:**
- Create: `$RECON/findings.md`
- Modify: `src/drivers-ppc/reconstruction/report.md`

**Interfaces:**
- Consumes: the map, ledger and scoped file list from Task 3.

This task produces the document the three follow-on specs are written from, so its
cluster table is the deliverable, not a summary.

- [ ] **Step 1: Enumerate the four clusters with addresses and sizes**

For every function the map reports as absent, record its address, size and
cluster. Derive sizes as next-symbol deltas and say so — they include any trailing
jump island and are not measured extents.

My unscoped derivation, for comparison only — **re-derive it**:

| Cluster | Functions | Bytes |
| --- | --- | --- |
| PEF / PCode loader | 25 | 12,060 |
| IXMicro acceleration | 7 | 1,948 |
| ATI Mach64 acceleration | 5 | 1,420 |
| Name Registry shims | 8 | 848 |

Plus 8 `IOATINDRV` methods and 1 data symbol.

Each cluster's table must be complete enough that a later spec can be written
from it without re-deriving the measurement.

- [ ] **Step 2: Record the Registry exception**

Write into `findings.md` that the eight `__e`-prefixed functions are **not**
instances of the over-underscore defect corrected in five earlier drivers: the
double underscore is what the ABI produces from a source name that legitimately
begins with one.

State that `symbol_name_check.py` reports them as missing against a bare spelling
that must never be written, and record whether the checker should learn to
distinguish the two cases — that is a judgement for the follow-on spec, so record
the question rather than answering it in code.

- [ ] **Step 3: Record the scoping finding**

Document that this is the first driver in the series whose source shares a
directory with other binaries', which files were scoped in and out, the before and
after `extra` counts from Task 3 Step 2, and how the file list was derived and
cross-checked against the map's own `source_path` values.

- [ ] **Step 4: Record the address-0 exclusion**

`-[IONDRVFramebuffer doControl:params:]` at `__text+0`, first word `7c0802a6` —
real code, no IDA entry, therefore outside any map's universe. A known exclusion,
**not a gap and not a phantom**, confirmed present by `selector_check.py`.

- [ ] **Step 5: Write the rest of findings.md**

Task 2 Step 7's three analysis numbers; the four-category coverage; the bucket
table; the invariant-check result; the ledger entry count and citation
verification; and every `duplicate_candidates` and `boundary_disputed` entry with
its explanation.

State plainly that nothing was compiled, and that this spec wrote no bodies and
renamed nothing.

- [ ] **Step 6: State acceptance**

Against each of the spec's **eleven** acceptance items, say whether it passed and
with what evidence.

- [ ] **Step 7: Cross-reference from the driver report**

Add a section to `src/drivers-ppc/reconstruction/report.md` giving IONDRVSupport's
headline numbers, pointing at `$RECON/findings.md`, and noting that its source
lives under `src/driverkit-3/libDriver/ppc/` rather than a driver project — and
that an earlier survey wrongly recorded it as having no source.

- [ ] **Step 8: Full suite, then commit**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: `894 passed, 4 skipped`.

```bash
cd $REPO && git add $RECON src/drivers-ppc/reconstruction/report.md && \
  git commit -m "drivers-ppc: record the IONDRVSupport measurement and its four gap clusters"
```

---

## Self-Review

**Spec coverage.** §1 goal → Tasks 3, 4. §1.1 decomposition → Task 4 Step 1.
§2 partition → Task 3 Steps 5–6. §2.1 classes and ivars → Task 3 Step 4.
§3 scoping → Task 3 Steps 1–2, Task 4 Step 3. §3.1 the tooling fix → Task 1.
§3.2 the list is a prediction → Task 3 Step 1. §4 Registry exception → Global
Constraints, Task 4 Step 2. §5 address-0 → Global Constraints, Task 3 Step 7,
Task 4 Step 4. §6.1 profiles → Task 2. §6.2 mapping → Task 3 Steps 3–4. §6.3
presence by definition site → Global Constraints. §7 artifacts → Tasks 3, 4.
§8 acceptance items 1–11 → Task 2 Step 5 (1), Task 1 (2), Task 3 Step 1 (3),
Task 3 Steps 4–5 (4), Task 3 Step 2 (5), Task 4 Step 4 (6), Task 3 Step 6 (7),
Task 3 Step 8 (8), Task 4 Step 1 (9), Task 4 Step 2 (10), Task 4 Step 8 (11).
§9 constraints → Global Constraints. §10 risks → Task 3 Step 1, Task 4 Step 1.

**Naming consistency.** `source_files(path, suffixes, recursive=True)` is defined
in Task 1 Step 3 and used with that exact signature in Task 1 Steps 1 and 5.
`analysis-named.json` is produced in Task 3 Step 3 and consumed in Steps 4, 6, 7.
`$RECON` is `src/drivers-ppc/reconstruction/IONDRVSupport` throughout.

**Suite counts.** Baseline 885 (`tools/binrecon/tests`, from the repo root with
`PYTHONPATH=tools/binrecon`). Task 1 adds 7 → 892. Task 2 adds 2 parametrised
profile cases → 894. Tasks 3 and 4 expect 894 and add no tests.

**A soft spot closed during self-review.** Task 3 Step 4 originally assumed
`binrecon source-map` would accept a file path once Task 1 landed. It would not:
`source_map.py:130` has its own non-recursive walker, so Task 3 would have mapped
nothing while reporting every function absent. It is now the fourth call site in
Task 1 Step 5, with an ordering regression check in Step 6.
