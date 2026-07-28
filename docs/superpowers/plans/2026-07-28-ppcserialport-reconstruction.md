# PPCSerialPort Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure Apple's shipped `PPCSerialPort` against our source, correct the symbol-naming defect in 50 of its 55 hand-written C functions and 2 of GNic's, write the five absent C functions, and record the measurement.

**Architecture:** Build the profiles and analysis first, because nothing can be measured without them. Then the rename, gated by a new committed checker rather than by a clean-looking `sed`. Then map, to prove the rename fixed 50 functions at once. Then the five bodies, largest last. A final task remaps both drivers and runs acceptance.

**Tech Stack:** Python 3.13 in `.venv-binrecon`, binrecon CLI, IDA Professional 9.2 (reference analysis only), Mach-O/PowerPC big-endian.

**Spec:** [2026-07-28-ppcserialport-reconstruction-design.md](../specs/2026-07-28-ppcserialport-reconstruction-design.md)

## Global Constraints

```bash
VENVPY="D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe"
REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc/PPCSerialPort.config/PPCSerialPort_reloc"
LKS="src/drivers-ppc/input/drvPPCSerialPort/PPCSerialPort.drvproj/PPCSerialPort.lksproj"
GNIC="src/drivers-ppc/network/drvPPCGNic/GNic.drvproj/GNic.lksproj"
RECON="src/drivers-ppc/reconstruction/PPCSerialPort"
```

**Work in a dedicated worktree, not the main checkout.** Several worktrees are
active in this repository (`isaserialport-recon`, `mesa-recon`,
`foundation-recon` and others), and a shared git index lets parallel sessions
overwrite each other's commits. Create one from `qemu-debug-loop` before Task 1
and set `REPO` to it.

- **There is no PowerPC toolchain and no host C compiler. Nothing compiles, and you may not claim it does.** Do not run `make`. That the renamed symbols "would now match" is an argument from the Mach-O naming rule, not an observation.
- **Never modify `src/kernel-7/`.**
- **Do not rename anything outside `drvPPCSerialPort` and `drvPPCGNic`.** A project-wide sweep was considered and deliberately deferred.
- **The disassembly is the authority** — not the function name, not a sibling, not what would be reasonable.
- **A confident guess is a defect; a recorded uncertainty is a result.**
- **Reproduce Apple's *form*, not Apple's *defects*.** Where the reference is demonstrably buggy, keep correct behaviour and record `intentional-mismatch` with its evidence. This is a standing user ruling; "reproduce by default" statements elsewhere in the tree are superseded.
- Commits: `drivers-ppc: ` prefix, one to two lines, no metadata/trailers/emoji. One per task.

### Disciplines, each of which has caught a real defect in this series

- **Settle every signature from `__OBJC,__meth_var_types`** where Objective-C is involved, never by inferring from instructions.
- **Resolve every `bl` through `read_macho`'s relocation table.** PowerPC jump islands (`lis r12 / ori / mtctr / bctr`) are not in IDA's export; the real target comes from the **island's** HI16/LO16 relocation pair.
- **Read ivars from `__OBJC,__instance_vars`**, never by inference.
- **Trace every bare constant to a named constant in this tree** before writing it as one.
- **Account for every instruction and every branch in writing.**
- **Establish presence by a definition site** — never by an occurrence count, never by a regex over declaration syntax. Three ad-hoc surveys in this series were recorded as measurement and all three had to be retracted.

### The address-0 rule — read before interpreting any tool output

`+[PPCSerialPort probe:]` sits at `__text+0`. Its first word is `7c0802a6`
(`mflr r0`) — **real code**. IDA's analysis has no function entry there, so
`ppc_invariant_check` will report:

```
symbol +[PPCSerialPort probe:] at 0x0 is not a function start
```

**That means only that IDA's function list lacks an entry.** It is not evidence
of an absent body. The opposite reading was recorded across five earlier specs
and retracted in 22 places. `read_macho` also reports address 0 for *undefined*
symbols, which is what made the two cases look alike. `probe:` is present in our
source; record it as a known exclusion.

### Established before this plan — use, do not re-derive

`__text` spans `0x0`–`0x4fe0` (20,448 bytes) across **76 defined symbols**:

| Origin | Count |
| --- | --- |
| Build-generated (`PPCSerialPortVersion`, `PPCSerialPortKernelServerInstance`) | 2 |
| Compiler runtime (`__udivdi3`, `__umoddi3`, libgcc) | 2 |
| Hand-written Objective-C | 17 |
| Hand-written C | 55 |

`2 + 2 + 17 + 55 = 76`. **72 are hand-written.** Classes:

```
PPCSerialPort : IODirectDevice
```

Source is one file pair: `PPCSerialPort.m` (3,138 lines), `PPCSerialPort.h` (298).

### The five functions to write

| # | Function | Addr | Span | Note |
| --- | --- | --- | --- | --- |
| 1 | `_dataLatTOHandler` | `0x1e3c` | 96 | No mention anywhere in source |
| 2 | `_frameTOHandler` | `0x1e9c` | 172 | No mention anywhere in source |
| 3 | `_delayTOHandler` | `0x1f48` | 176 | No mention anywhere in source |
| 4 | `_heartBeatTOHandler` | `0x1ff8` | 228 | No mention anywhere in source |
| 5 | `_activatePort` | `0x0bb0` | 284 | Called 4× in source, never defined |

956 bytes. Spans are next-symbol deltas including any trailing jump island —
confirm each function's true extent from its `blr` before writing.

## File Structure

**Created:**
- `tools/binrecon/profiles/ppcserialport-ppc.json`, `ppcserialport-bundle-ppc.json` (Task 1)
- `tools/binrecon/symbol_name_check.py` — the definition-site checker (Task 2)
- `tools/binrecon/tests/test_symbol_name_check.py` — its tests (Task 2)
- `$RECON/{source-map.json,ledger.json,findings.md}` (Task 3)

**Modified:**
- `tools/binrecon/tests/test_profile.py` — `test_ppc_profile_inventory` (Task 1)
- `$LKS/PPCSerialPort.m`, `$LKS/PPCSerialPort.h` — rename (Task 2), five bodies (Task 4)
- `$GNIC/GNicEnet.m` and any caller — rename (Task 2)
- `src/drivers-ppc/reconstruction/GNic/findings.md` (Task 5)
- `src/drivers-ppc/reconstruction/report.md` or `report-network.md` (Task 5)

---

## Task 1: Profiles, inventory test, reference analysis

**Files:**
- Create: `tools/binrecon/profiles/ppcserialport-ppc.json`, `tools/binrecon/profiles/ppcserialport-bundle-ppc.json`
- Modify: `tools/binrecon/tests/test_profile.py`

**Interfaces:**
- Produces: the analysis JSON under `tools/binrecon/out/ppcserialport-ppc/`, consumed by Tasks 3 and 5; two profile names that `test_ppc_profile_inventory` asserts.

- [ ] **Step 1: Add both profiles to the inventory test — RED first**

`tools/binrecon/tests/test_profile.py`'s `test_ppc_profile_inventory` asserts the
complete sorted list of PPC profile filenames. Insert the two new names in sorted
position — they sort between `pmu-ppc.json` and `scsiserver-bundle-ppc.json`:

```python
        "pmu-bundle-ppc.json", "pmu-ppc.json",
        "ppcserialport-bundle-ppc.json", "ppcserialport-ppc.json",
        "scsiserver-bundle-ppc.json", "scsiserver-ppc.json",
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest \
  tools/binrecon/tests/test_profile.py::test_ppc_profile_inventory -q
```

Expected: FAIL — the two files do not exist yet, so the actual list is missing
them. Confirm the failure names exactly those two before continuing.

- [ ] **Step 3: Create `ppcserialport-ppc.json`**

Copy the shape of `tools/binrecon/profiles/mesh-ppc.json` exactly, changing only
`name` and `output_dir`:

```json
{
  "schema_version": "profile-v1",
  "name": "drvPPCSerialPort ppc reconstruction",
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
  "output_dir": "../out/ppcserialport-ppc"
}
```

- [ ] **Step 4: Create `ppcserialport-bundle-ppc.json`**

Identical except:

```json
  "name": "drvPPCSerialPort bundle ppc reconstruction",
  "output_dir": "../out/ppcserialport-bundle-ppc"
```

- [ ] **Step 5: Run the profile tests and confirm they pass**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests/test_profile.py -q
```

Expected: PASS. `test_ppc_profiles_are_reference_only_ida_runs` is parametrised
over every PPC profile and will also exercise the two new ones — it asserts
`schema_version`, `architecture: ppc`, `endianness: big`, the `${BINRECON_REFERENCE}`
reference, absence of a `rebuilt` key, and `ida.enabled is True`.

- [ ] **Step 6: Run the reference analysis**

```bash
cd $REPO && BINRECON_REFERENCE="$REF" PYTHONPATH=tools/binrecon \
  $VENVPY -m binrecon analyze --profile tools/binrecon/profiles/ppcserialport-ppc.json
```

**Expected: exit 1, and that is correct.** `cli.py:105` returns
`0 if report["complete"] and acceptance["passed"] else 1`, and a reference-only
profile carries no `rebuilt` binary, so `normalized-functions` acceptance has
nothing to compare and can never pass. What matters is that the run reports
`analysis complete` and publishes its output under
`tools/binrecon/out/ppcserialport-ppc/published/`.

Note the analysis JSON path; later steps call it `$ANALYSIS`. It is
`tools/binrecon/out/ppcserialport-ppc/published/analysis-reference-ida.json`.

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

`lowest` must be **greater than 0** — that is the address-0 rule confirmed in
advance rather than discovered and misread later. Record all three numbers for
Task 3's findings.

- [ ] **Step 8: Full suite, then commit**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: `853 passed, 4 skipped` — the baseline is 851 and
`test_ppc_profiles_are_reference_only_ida_runs` gains one case per new profile.
If the count differs, say so rather than adjusting the expectation.

```bash
cd $REPO && git add tools/binrecon/profiles tools/binrecon/tests/test_profile.py && \
  git commit -m "drivers-ppc: add the PPCSerialPort binrecon profiles"
```

---

## Task 2: The symbol-name rename, gated by a committed checker

**Files:**
- Create: `tools/binrecon/symbol_name_check.py`, `tools/binrecon/tests/test_symbol_name_check.py`
- Modify: `$LKS/PPCSerialPort.m`, `$LKS/PPCSerialPort.h`, `$GNIC/GNicEnet.m`

**Interfaces:**
- Produces: `missing_definitions(symbols, definitions) -> list[str]` and `source_definitions(source_dir) -> set[str]` in `tools/binrecon/symbol_name_check.py`, used by Task 5's acceptance.

Every C function in `PPCSerialPort.m` is defined with a spurious leading
underscore — `static void _changeState(...)` emits `__changeState` where Apple's
binary carries `_changeState`. **50 of 55 are affected; none is correct.** GNic
has the same defect in both of its two C functions.

The survey that found this **also reported two defects in `drvPPCGem` that do not
exist**, so this task builds a real checker first and renames second.

- [ ] **Step 1: Write the failing tests**

Create `tools/binrecon/tests/test_symbol_name_check.py`:

```python
from symbol_name_check import missing_definitions, source_definitions


def test_symbol_matches_when_source_drops_the_leading_underscore():
    assert missing_definitions(["_changeState"], {"changeState"}) == []


def test_symbol_is_missing_when_source_keeps_the_leading_underscore():
    assert missing_definitions(["_changeState"], {"_changeState"}) == ["_changeState"]


def test_symbol_is_missing_when_no_definition_exists():
    assert missing_definitions(["_activatePort"], {"changeState"}) == ["_activatePort"]


def test_compiler_runtime_helpers_are_not_reported():
    assert missing_definitions(["__udivdi3", "__umoddi3"], set()) == []


def test_objective_c_methods_are_not_reported():
    assert missing_definitions(["-[PPCSerialPort free]", "+[PPCSerialPort probe:]"], set()) == []


def test_source_definitions_finds_a_static_function(tmp_path):
    (tmp_path / "a.m").write_text("static void changeState(int x)\n{\n    return;\n}\n")
    assert "changeState" in source_definitions(tmp_path)


def test_source_definitions_ignores_a_prototype(tmp_path):
    (tmp_path / "a.m").write_text("extern void changeState(int x);\n")
    assert source_definitions(tmp_path) == set()


def test_source_definitions_finds_a_brace_on_the_next_line(tmp_path):
    (tmp_path / "a.m").write_text("unsigned int ReadGNicRegister(int base)\n{\n    return 0;\n}\n")
    assert "ReadGNicRegister" in source_definitions(tmp_path)
```

- [ ] **Step 2: Run them and confirm they fail**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest \
  tools/binrecon/tests/test_symbol_name_check.py -q
```

Expected: collection error — `No module named 'symbol_name_check'`.

- [ ] **Step 3: Write the checker**

Create `tools/binrecon/symbol_name_check.py`:

```python
"""Check that every hand-written C symbol has a source definition site.

Under the Mach-O ABI the compiler prepends exactly one underscore, so a source
function `changeState` becomes the symbol `_changeState`. A source function
written as `_changeState` becomes `__changeState` and silently fails to match
the reference binary. This checker compares a reference binary's hand-written C
symbols against the definition sites in a source tree.

Presence is established by a definition site, never by an occurrence count.
"""

import argparse
import re
import sys
from pathlib import Path

from binrecon.macho import read_macho

# libgcc helpers linked into the driver rather than written by hand.
COMPILER_RUNTIME = {"__udivdi3", "__umoddi3", "__divdi3", "__moddi3"}

_DEFINITION = re.compile(r"^(?:static\s+)?[A-Za-z_][\w \t\*]*?([A-Za-z_]\w*)\s*\(")


def source_definitions(source_dir):
    """Return the C function names defined in .m and .c files under source_dir."""
    names = set()
    for path in sorted(Path(source_dir).rglob("*")):
        if path.suffix not in (".m", ".c"):
            continue
        lines = path.read_text(encoding="utf-8", errors="replace").split("\n")
        for index, line in enumerate(lines):
            match = _DEFINITION.match(line)
            if not match or ";" in line:
                continue
            if "{" in "".join(lines[index:index + 4]):
                names.add(match.group(1))
    return names


def hand_written_c_symbols(document):
    """Return reference __text symbols that are hand-written C."""
    return [
        symbol["name"]
        for symbol in document["symbols"]
        if symbol.get("section") == "__TEXT,__text"
        and not symbol["name"].startswith(("-[", "+["))
    ]


def missing_definitions(symbols, definitions):
    """Return symbols with no definition site named symbol-minus-one-underscore."""
    missing = []
    for symbol in symbols:
        if symbol in COMPILER_RUNTIME or symbol.startswith(("-[", "+[")):
            continue
        if symbol[1:] not in definitions:
            missing.append(symbol)
    return missing


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True)
    parser.add_argument("--source-dir", required=True, action="append")
    arguments = parser.parse_args(argv)

    definitions = set()
    for source_dir in arguments.source_dir:
        definitions |= source_definitions(source_dir)

    symbols = hand_written_c_symbols(read_macho(Path(arguments.binary)))
    missing = missing_definitions(symbols, definitions)

    print(f"hand-written C symbols: {len(symbols)}")
    print(f"missing definitions   : {len(missing)}")
    for name in missing:
        print(f"  {name}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run the tests and confirm they pass**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest \
  tools/binrecon/tests/test_symbol_name_check.py -q
```

Expected: `8 passed`.

- [ ] **Step 5: Record the before-state**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/symbol_name_check.py \
  --binary "$REF" --source-dir $LKS
```

Expected: 55 hand-written C symbols, **55 missing** — 50 misnamed plus the 5
absent. Save this output; Task 3's findings quote it as the baseline.

- [ ] **Step 6: Rename in `PPCSerialPort.m` and `PPCSerialPort.h`**

For each of the 55 names, replace the identifier `_Name` with `Name`. The
preconditions were verified when the spec was written and hold:

- no name in the set is a prefix of another, so word-bounded replacement is safe;
- every `_Foo` token in the file is one of these 55;
- the 14 apparent collisions are string literals inside `_MyIOLog("changeState\n\r")`
  and Objective-C selectors such as `- (IOReturn)executeEvent:`. Stripping a
  prefix touches neither — the literals already lack the underscore, and a C
  function may share a name with a selector;
- `unsigned int watchState;` is a local in `-[PPCSerialPort dequeueData:]`, and
  that scope never calls the C function, so nothing is shadowed.

**Use word-bounded replacement** (`\b_Name\b`), not a bare substring replace, and
**do not touch string literals**.

**Scale:** 308 `_`-prefixed identifier occurrences in `PPCSerialPort.m`, of which
**74 are `_MyIOLog`** — it is one of the 55 and becomes `MyIOLog`, so most of the
diff is its call sites. A rename that leaves the file with far fewer than ~308
changed tokens has missed something; one that changes more has caught something
it should not have.

- [ ] **Step 7: Verify the rename with the checker**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/symbol_name_check.py \
  --binary "$REF" --source-dir $LKS
```

Expected: **exactly 5 missing** — `_dataLatTOHandler`, `_frameTOHandler`,
`_delayTOHandler`, `_heartBeatTOHandler`, `_activatePort`. Any other name in the
list means the rename broke or missed something; fix it before continuing.

- [ ] **Step 8: Rename GNic's two**

`$GNIC/GNicEnet.m:32` and `:66`:

```c
unsigned int ReadGNicRegister(int base, unsigned int offset_and_size)
void WriteGNicRegister(int base, unsigned int offset_and_size, unsigned int value)
```

Update every call site — there are several in `GNicEnet.m` (for example lines
315, 360, 484, 487). Search the whole `$GNIC` directory, not just that file.

- [ ] **Step 9: Verify GNic**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/symbol_name_check.py \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCGNic.config/drvPPCGNic_reloc" \
  --source-dir $GNIC
```

Expected: 2 hand-written C symbols, **0 missing**, exit 0.

- [ ] **Step 10: Full suite, then commit**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: `861 passed, 4 skipped` — 853 from Task 1 plus 8 new. If it differs,
say so rather than adjusting the expectation.

```bash
cd $REPO && git add tools/binrecon/symbol_name_check.py \
  tools/binrecon/tests/test_symbol_name_check.py $LKS $GNIC && \
  git commit -m "drivers-ppc: drop the spurious leading underscore from PPCSerialPort and GNic C functions"
```

---

## Task 3: Map, buckets, findings

**Files:**
- Create: `$RECON/source-map.json`, `$RECON/ledger.json`, `$RECON/findings.md`

**Interfaces:**
- Consumes: `$ANALYSIS` from Task 1; the renamed source from Task 2.
- Produces: `$RECON/source-map.json` and the recorded mapping route, which Task 5 re-runs verbatim.

- [ ] **Step 1: Filter unnamed functions**

```bash
cd $REPO && $VENVPY tools/binrecon/filter_named_functions.py \
  $ANALYSIS tools/binrecon/out/ppcserialport-ppc/analysis-named.json
```

Expected: exit 0. Re-run Task 1 Step 7's snippet against the output; `unnamed`
must be 0 and `input.sha256` unchanged.

- [ ] **Step 2: Build the source map — no `--scope-to-objc`**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --reference-analysis tools/binrecon/out/ppcserialport-ppc/analysis-named.json \
  --binary "$REF" \
  --source-dir $LKS \
  --repo-root . \
  --objc-methods \
  --output $RECON/source-map.json
```

55 of the 72 hand-written functions are C. **`--scope-to-objc` would cover 17 of
72 and look complete** — that is the failure mode this route exists to avoid. It
is the same route SCSIServer proved on PowerPC.

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

- [ ] **Step 4: Bucket the functions**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/bucket_functions.py \
  tools/binrecon/out/ppcserialport-ppc/analysis-named.json \
  $RECON/source-map.json
```

Both arguments are **positional**. Expected: a table ending `RECONCILES: yes`.
Buckets 1 and 2 are always empty for a `_reloc` kernel server. Bucket 4 should
hold the two build-generated class methods. `__udivdi3` and `__umoddi3` will land
in bucket 6 — account for them there as compiler runtime, not as gaps.

- [ ] **Step 5: Run the PowerPC invariant check**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
  --binary "$REF" --analysis tools/binrecon/out/ppcserialport-ppc/analysis-named.json
```

The tool distinguishes "no analyzer function and no code" from "no analyzer
function but code is present". Expect the `probe:` line to report **code
present**. Any other violation gets a written explanation — the single violation
deserves more scrutiny than the clean relocations, not less.

- [ ] **Step 6: Write findings.md**

Record: Task 1 Step 7's three analysis numbers; the four-category coverage; the
bucket table; the invariant-check result; the `probe:` exclusion and why;
`__udivdi3`/`__umoddi3` as compiler runtime; the before/after
`symbol_name_check.py` output from Task 2 Steps 5 and 7 as the evidence that the
rename fixed 50 functions at once; and the five remaining gaps.

State plainly that nothing was compiled.

- [ ] **Step 7: Commit**

```bash
cd $REPO && git add $RECON && \
  git commit -m "drivers-ppc: map PPCSerialPort against the shipped binary"
```

---

## Task 4: The five absent C functions

**Files:**
- Modify: `$LKS/PPCSerialPort.m`, `$LKS/PPCSerialPort.h`, `$RECON/findings.md`

**Interfaces:**
- Consumes: `$RECON/source-map.json` for addresses.
- Produces: five function bodies. Task 5 remaps and expects them mapped.

Work smallest first — the small ones establish the idioms the large ones reuse.

- [ ] **Step 1: Establish how the four handlers are registered, before writing any**

The four `TOHandler` functions have **no counterpart in our source at all** — not
even a call site. Nothing in the tree constrains a wrong reading, which is the
condition that made the IOADBDevice reconstruction expensive.

They are **expected** to be `IOScheduleFunc` timeout callbacks. That is a
hypothesis, not a finding. Before writing any of them, find each one's
registration site in the disassembly — search for its address being materialised
(`lis`/`addi` of `__TEXT,__text + offset`) and resolve what consumes it. Record
what you find, including the true signature. If a handler's registration site
cannot be located, **record that as an uncertainty and write what the body's own
instructions support**, rather than assuming the callback shape.

- [ ] **Step 2: Write `dataLatTOHandler` (`0x1e3c`, 96 bytes)**

Smallest. Resolve every `bl` through the relocation table. Produce an
instruction-by-instruction account covering every branch.

- [ ] **Step 3: Write `frameTOHandler` (`0x1e9c`, 172 bytes)**

Sits immediately after `dataLatTOHandler`; read both before writing this one,
since sibling handlers commonly share a tail or a helper.

- [ ] **Step 4: Write `delayTOHandler` (`0x1f48`, 176 bytes)**

- [ ] **Step 5: Write `heartBeatTOHandler` (`0x1ff8`, 228 bytes)**

Largest of the four handlers.

- [ ] **Step 6: Write `activatePort` (`0x0bb0`, 284 bytes)**

Largest overall, but the best constrained: it is called four times in
`PPCSerialPort.m` already, and those call sites fix its argument list and return
usage. Confirm the signature against the disassembly rather than against the call
sites alone — the call sites were written by an earlier session and are not
evidence of Apple's signature.

- [ ] **Step 7: Verify all five now have definition sites**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/symbol_name_check.py \
  --binary "$REF" --source-dir $LKS
```

Expected: 55 hand-written C symbols, **0 missing**, exit 0.

- [ ] **Step 8: Record uncertainties**

Anything you could not settle from evidence goes into `$RECON/findings.md` as a
numbered uncertainty with what you observed and what you would need. Do not
resolve an ambiguity by silently picking the plausible option.

- [ ] **Step 9: Commit**

```bash
cd $REPO && git add $LKS $RECON/findings.md && \
  git commit -m "drivers-ppc: write PPCSerialPort's timeout handlers and activatePort"
```

---

## Task 5: Remap, GNic, acceptance

**Files:**
- Modify: `$RECON/source-map.json`, `$RECON/findings.md`, `src/drivers-ppc/reconstruction/GNic/findings.md`, `src/drivers-ppc/reconstruction/report-network.md`

- [ ] **Step 1: Regenerate the PPCSerialPort map**

Re-run Task 3 Steps 1–2 verbatim. All five new functions should now map.

- [ ] **Step 2: Confirm coverage against acceptance**

The map must cover **71** of the 72 hand-written functions. The 72nd is
`+[PPCSerialPort probe:]`, excluded by construction per the address-0 rule.
Confirm it is present in source independently:

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/selector_check.py \
  "$REF" $LKS
```

Both arguments are **positional**. `selector_check.py` matches by string rather
than by address, so it sees `probe:` where the map cannot.

- [ ] **Step 3: Re-run buckets and the invariant check**

Task 3 Steps 4 and 5, unchanged. Expect `RECONCILES: yes` and the same single
`probe:` line reporting code present.

- [ ] **Step 4: Re-run GNic's existing source map**

`src/drivers-ppc/reconstruction/GNic/` already holds a map from an earlier spec.
Regenerate it with the same route and confirm `_ReadGNicRegister` and
`_WriteGNicRegister` now map. Record the before/after counts.

- [ ] **Step 5: Update GNic's findings and the network report**

`src/drivers-ppc/reconstruction/GNic/findings.md`: record that both of its
hand-written C functions carried the underscore defect, that they were renamed
here, and the map counts before and after.

`src/drivers-ppc/reconstruction/report-network.md`: correct GNic's gap count and
note the fix, so the report no longer reads as complete-and-correct on a driver
that had two unmapped functions.

- [ ] **Step 6: Full suite**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: `861 passed, 4 skipped`. `PYTHONPATH` is required; without it
collection fails.

- [ ] **Step 7: Final acceptance statement**

In `$RECON/findings.md`, state against each of the spec's nine acceptance items
whether it passed, with the evidence. Include the standing constraint: **nothing
was compiled**, so every claim is of correspondence to the binary, never of
buildability — and specifically that "the symbols would now match" follows from
the Mach-O naming rule, not from a build.

- [ ] **Step 8: Commit**

```bash
cd $REPO && git add $RECON src/drivers-ppc/reconstruction/GNic \
  src/drivers-ppc/reconstruction/report-network.md && \
  git commit -m "drivers-ppc: remap PPCSerialPort and GNic and record acceptance"
```

---

## Self-Review

**Spec coverage.** §1 goal → Tasks 2, 4. §2 partition → Task 3 Steps 4, 6. §2.1
class and ivars → Task 4 disciplines. §3 the defect → Task 2. §3.1 mechanical
safety → Task 2 Step 6. §3.2 GNic → Task 2 Steps 8–9, Task 5 Steps 4–5. §3.3 why
the survey is not trusted → Task 2 Steps 1–4 build the checker instead. §4.1
address-0 → Global Constraints, Task 1 Step 7, Task 5 Step 2. §4.2 profiles →
Task 1. §4.3 mapping → Task 3 Steps 1–2, Task 5 Step 1. §4.4 verification → Task
2 Steps 5/7/9, Task 4 Step 7. §4.5 disciplines → Global Constraints. §5 the five
→ Task 4. §6 artifacts → Task 3. §7 acceptance items 1–9 → Task 1 Step 5, Task 2
Steps 7/9, Task 3 Steps 3–4, Task 5 Steps 2/4/6/7. §8 constraints → Global
Constraints. §9 risks → Task 2 Step 7, Task 4 Step 1.

**Naming consistency.** `missing_definitions(symbols, definitions)` and
`source_definitions(source_dir)` are defined in Task 2 Step 3 and used with those
exact signatures in Task 2 Step 1's tests. `analysis-named.json` is produced in
Task 3 Step 1 and consumed in Steps 2, 4, 5 and Task 5 Steps 1, 3. `$RECON` is
`src/drivers-ppc/reconstruction/PPCSerialPort` throughout.

**Suite counts.** Baseline 851 (`tools/binrecon/tests`). Task 1 adds 2 profile
cases → 853. Task 2 adds 8 checker tests → 861. Task 5 expects 861.

**Known soft spot.** `$ANALYSIS` is referenced before its exact filename is
known — Task 1 Step 6 instructs the implementer to note it from the `analyze`
output, because the name depends on the analyzer's run naming. Deliberate, not a
placeholder.
