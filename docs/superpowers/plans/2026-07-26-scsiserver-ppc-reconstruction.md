# PowerPC SCSIServer Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct `src/drvSCSIServer` against Apple's shipped PowerPC `SCSIServer_reloc` — a report pass that dispositions all 68 reference functions, then a fix pass that repairs the divergences.

**Architecture:** Phase 1 produces `src/drvSCSIServer/reconstruction/{source-map.json,ledger.json,divergences.md}` and is committed in full before any source changes, so the evidence records the tree as it was found. Phase 2 changes source one translation unit per commit: the misnamed selector, then a recovered `IOSCSISessionMig.defs` replacing 562 hand-written lines, then a new `IOTask.m` holding the task/notification plumbing, then `_serverThreadFunc`, then whatever divergences Phase 1 found in the mapped functions.

**Tech Stack:** Python 3.12 (`.venv-binrecon`), binrecon (`source-map`, `ledger`, `filter_named_functions.py`, `selector_check.py`, `ppc_invariant_check.py`), Objective-C / MiG source for Rhapsody DriverKit.

**Spec:** [docs/superpowers/specs/2026-07-26-scsiserver-ppc-reconstruction-design.md](../specs/2026-07-26-scsiserver-ppc-reconstruction-design.md)

## Global Constraints

- **Nothing here is compile-verified.** There is no PowerPC compiler in this environment (`vm/` holds only `build-i386-*.sh`). Source changes are verified by static comparison against Apple's binary, never by building. Do not claim a change "works"; claim only what the checks prove.
- The reference binary is read-only and lives outside the repository: `C:/Users/raynorpat/Downloads/test/Drivers/ppc/SCSIServer.config/SCSIServer_reloc`, SHA-256 `E813777748A4FAC9348AA1CF4E979863B96D75B09FDAC16DF586031499A122A2`. Never modify or copy it into the repo.
- Analysis of record: `tools/binrecon/out/scsiserver-ppc/published/analysis-reference-ida.json` (IDA 9.2). Do not regenerate it. `tools/binrecon/out/` is git-ignored — never commit anything under it.
- Both scanners are non-recursive. `--source-dir` and `selector_check.py`'s source argument must be `src/drvSCSIServer/SCSIServer.drvproj/SCSIServer.lksproj`. Pointing them at `src/drvSCSIServer` silently yields 0 mapped, 68 unmapped.
- `source-map` requires every analysis function to be named, so the analysis must first pass through `tools/binrecon/filter_named_functions.py` — the 138 unnamed jump islands otherwise fail with `analysis function at address 212 has no names`.
- The 138 jump islands and the two build-generated classes (`+[SCSIServerKernelServerInstance kernelServerInstance]`, `+[SCSIServerVersion driverKitVersionForSCSIServer]`) are out of scope for source mapping. The two classes stay in the `unmapped` bucket when the work is done.
- Commit style: subsystem prefix, short, human-readable, no metadata. Use `drvSCSIServer: ` for source and report commits, `binrecon: ` for the tooling commit in Task 1.
- Run everything from `D:/RhapsodiOS`. Shorthand used throughout this plan:

```bash
export REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc/SCSIServer.config/SCSIServer_reloc"
export SRC="src/drvSCSIServer/SCSIServer.drvproj/SCSIServer.lksproj"
export RECON="src/drvSCSIServer/reconstruction"
export NAMED="tools/binrecon/out/scsiserver-ppc/analysis-reference-ida.named.json"
export ANALYSIS="tools/binrecon/out/scsiserver-ppc/published/analysis-reference-ida.json"
export PY="./.venv-binrecon/Scripts/python.exe"
```

Every `$PY` invocation needs `PYTHONPATH=tools/binrecon`.

## File Structure

| Path | Responsibility |
| --- | --- |
| `tools/binrecon/seed_ledger.py` | **new.** Seeds a `ledger-v1` document from a source map, one entry per accounted-for function. |
| `tools/binrecon/tests/test_seed_ledger.py` | **new.** Tests for the above, matching the pattern of `test_parity_check.py`. |
| `src/drvSCSIServer/reconstruction/source-map.json` | **new.** The `source-map-v1` document. |
| `src/drvSCSIServer/reconstruction/ledger.json` | **new.** One `ledger-v1` entry per reference function. |
| `src/drvSCSIServer/reconstruction/divergences.md` | **new.** Prose findings with reference evidence. |
| `$SRC/IOSCSISessionMig.defs` | **new.** MiG interface: subsystem `IOSCSISessionMig`, base ID 4242, 18 routines. |
| `$SRC/IOSCSISession.m` | Hand-rolled MiG apparatus deleted; task plumbing moved out; `_serverThreadFunc` added; selector renamed. |
| `$SRC/IOSCSISession.h` | Task-plumbing declarations moved to `IOTask.h`. |
| `$SRC/IOTask.m` | **new.** Task, memory-wiring and death-notification plumbing. |
| `$SRC/IOTask.h` | **new.** Its declarations. |
| `$SRC/SCSIServer.m` | Fixes only where Phase 1 finds them. |
| `$SRC/Makefile.preamble` | `DEFSFILES` and the generated server object. |
| `$SRC/PB.project` | `FILESTABLE` gains `IOTask.m` / `IOTask.h`; `.defs` listed as an other source. |

---

## Phase 1 — Report

### Task 1: `seed_ledger.py`

**Files:**
- Create: `tools/binrecon/seed_ledger.py`
- Test: `tools/binrecon/tests/test_seed_ledger.py`

**Interfaces:**
- Consumes: `binrecon.identity.identify`, `binrecon.ledger.new_ledger`, `binrecon.ledger.validate_ledger`.
- Produces: `seed_entries(source_map: dict) -> list[dict]` and `main(argv=None) -> int`. CLI: `seed_ledger.py SOURCE_MAP REFERENCE_BINARY OUTPUT`, exit 0 on success, 1 on identity mismatch, 2 on usage error.

**Why this exists:** `binrecon analyze --ledger` seeds entries from the analyzer's raw function list. Run against this driver it produced 206 entries, 138 of them build-generated jump islands under IDA `sub_XXXX` names. A reconstruction ledger needs one entry per function the source map accounts for — 68 here. `validate_ledger` does not require entries to correspond to an analysis document, only that they are sorted, non-overlapping and positively sized, so a 68-entry ledger is valid.

- [ ] **Step 1: Write the failing test**

Create `tools/binrecon/tests/test_seed_ledger.py`:

```python
import json

import pytest

from macho_fixture import build_macho_fixture
from seed_ledger import main, seed_entries


SOURCE_MAP = {
    "schema_version": "source-map-v1",
    "reference_sha256": "0" * 64,
    "mapped": [
        {"address": 16, "size": 20, "reference_names": ["+[C m]"],
         "source_path": "src/a.m", "source_line": 7},
    ],
    "unmapped": [
        {"address": 36, "size": 40, "reference_names": ["_absent"]},
    ],
    "duplicate_candidates": [],
    "boundary_disputed": [],
}


def test_seeds_one_entry_per_accounted_function():
    entries = seed_entries(SOURCE_MAP)

    assert [entry["address"] for entry in entries] == [16, 36]
    assert entries[0]["source_path"] == "src/a.m"
    assert entries[0]["source_line"] == 7
    assert entries[1]["source_path"] is None
    assert entries[1]["source_line"] is None
    assert {entry["status"] for entry in entries} == {"unexamined"}
    assert entries[0]["names"] == ["+[C m]"]


def test_entries_are_sorted_by_address():
    unsorted_map = dict(SOURCE_MAP, mapped=[
        {"address": 500, "size": 4, "reference_names": ["_late"],
         "source_path": "src/a.m", "source_line": 1},
        {"address": 8, "size": 4, "reference_names": ["_early"],
         "source_path": "src/a.m", "source_line": 2},
    ], unmapped=[])

    assert [entry["address"] for entry in seed_entries(unsorted_map)] == [8, 500]


def test_every_entry_satisfies_the_ledger_schema_fields():
    required = {"address", "size", "names", "source_path", "source_line", "status",
                "analyzer_agreement", "artifacts", "reason", "reviewer"}

    for entry in seed_entries(SOURCE_MAP):
        assert set(entry) == required


def test_cli_writes_a_valid_ledger(tmp_path):
    binary = tmp_path / "reference"
    binary.write_bytes(build_macho_fixture(architecture="ppc", relocations=b""))
    import hashlib
    digest = hashlib.sha256(binary.read_bytes()).hexdigest().upper()
    map_path = tmp_path / "source-map.json"
    map_path.write_text(json.dumps(dict(SOURCE_MAP, reference_sha256=digest)))
    output = tmp_path / "ledger.json"

    assert main([str(map_path), str(binary), str(output)]) == 0

    document = json.loads(output.read_text())
    assert document["schema_version"] == "ledger-v1"
    assert document["reference_sha256"] == digest
    assert document["rebuilt_sha256"] is None
    assert len(document["entries"]) == 2


def test_cli_rejects_a_map_for_a_different_binary(tmp_path):
    binary = tmp_path / "reference"
    binary.write_bytes(build_macho_fixture(architecture="ppc", relocations=b""))
    map_path = tmp_path / "source-map.json"
    map_path.write_text(json.dumps(SOURCE_MAP))

    assert main([str(map_path), str(binary), str(tmp_path / "out.json")]) == 1


def test_cli_reports_usage_error(tmp_path):
    assert main(["only-one-argument"]) == 2
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -m pytest tools/binrecon/tests/test_seed_ledger.py -q
```

Expected: collection error, `ModuleNotFoundError: No module named 'seed_ledger'`.

- [ ] **Step 3: Write the implementation**

Create `tools/binrecon/seed_ledger.py`:

```python
"""Seed a ledger-v1 document from a reference source map.

`binrecon analyze --ledger` builds its entries from the analyzer's raw function
list, which for a PowerPC driver includes every build-generated jump island under
an IDA `sub_XXXX` name -- 206 entries for SCSIServer, 138 of them glue. A
reconstruction ledger should carry one entry per function the source map accounts
for, so this seeds from the map instead: mapped entries keep their source path
and line, every other bucket carries nulls, and every entry starts unexamined.
"""

import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent))

from binrecon.identity import identify
from binrecon.ledger import new_ledger, validate_ledger

_BUCKETS = ("mapped", "unmapped", "duplicate_candidates", "boundary_disputed")
# Only IDA supports PowerPC; the Ghidra and angr adapters reject a ppc profile.
_AGREEMENT = {
    "analyzers": ["IDA"],
    "status": "agreed",
    "reasons": ["IDA is the only analyzer that supports PowerPC"],
}


def seed_entries(source_map: dict) -> list[dict]:
    """Return sorted ledger entries for every function the map accounts for."""
    entries = []
    for bucket in _BUCKETS:
        for item in source_map.get(bucket, ()):
            entries.append({
                "address": item["address"],
                "size": item["size"],
                "names": list(item["reference_names"]),
                "source_path": item.get("source_path"),
                "source_line": item.get("source_line"),
                "status": "unexamined",
                "analyzer_agreement": dict(_AGREEMENT),
                "artifacts": [],
                "reason": None,
                "reviewer": None,
            })
    entries.sort(key=lambda entry: (entry["address"], entry["size"]))
    return entries


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if len(argv) != 3:
        print("usage: seed_ledger.py SOURCE_MAP REFERENCE_BINARY OUTPUT", file=sys.stderr)
        return 2
    source_map = json.loads(Path(argv[0]).read_text(encoding="utf-8"))
    reference = identify(Path(argv[1]))
    if str(source_map["reference_sha256"]).upper() != reference.sha256:
        print("source map reference_sha256 does not match the binary", file=sys.stderr)
        return 1
    document = new_ledger(reference, None, seed_entries(source_map))
    validate_ledger(document, reference, None)
    Path(argv[2]).write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"{len(document['entries'])} entries")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -m pytest tools/binrecon/tests/test_seed_ledger.py -q
```

Expected: `6 passed`.

- [ ] **Step 5: Run the full binrecon suite**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -m pytest tools/binrecon -q
```

Expected: all pass. Baseline before this task is 753 passed, 4 skipped; expect 759 passed.

- [ ] **Step 6: Commit**

```bash
cd /d/RhapsodiOS && git add tools/binrecon/seed_ledger.py tools/binrecon/tests/test_seed_ledger.py && git commit -m "binrecon: seed a reconstruction ledger from a source map"
```

---

### Task 2: Generate the report artifacts

**Files:**
- Create: `src/drvSCSIServer/reconstruction/source-map.json`, `src/drvSCSIServer/reconstruction/ledger.json`, `src/drvSCSIServer/reconstruction/divergences.md`

**Interfaces:**
- Consumes: `seed_ledger.py` from Task 1.
- Produces: the three artifacts every later task reads and updates. Ledger addresses are the stable keys later tasks pass to `binrecon ledger --address`.

- [ ] **Step 1: Filter the analysis**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY tools/binrecon/filter_named_functions.py "$ANALYSIS" "$NAMED"
```

Expected: writes `$NAMED`. Confirm it kept 68 functions:

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "import json,os; d=json.load(open(os.environ['NAMED'])); print(len(d['functions']), d['input']['sha256'])"
```

Expected: `68 E813777748A4FAC9348AA1CF4E979863B96D75B09FDAC16DF586031499A122A2`.

- [ ] **Step 2: Generate the source map**

```bash
cd /d/RhapsodiOS && mkdir -p "$RECON" && PYTHONPATH=tools/binrecon $PY -m binrecon source-map \
  --reference-analysis "$NAMED" --binary "$REF" --source-dir "$SRC" \
  --repo-root . --output "$RECON/source-map.json"
```

- [ ] **Step 3: Confirm the starting numbers match the spec**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os
m = json.load(open(os.environ['RECON'] + '/source-map.json'))
for bucket in ('mapped', 'unmapped', 'duplicate_candidates', 'boundary_disputed'):
    print('%-22s %d' % (bucket, len(m[bucket])))
print('mapped bytes', sum(e['size'] for e in m['mapped']))
print('unmapped bytes', sum(e['size'] for e in m['unmapped']))
"
```

Expected exactly: mapped 41, unmapped 27, duplicate_candidates 0, boundary_disputed 0, mapped bytes 5796, unmapped bytes 5724. Any other numbers mean the inputs differ from what the spec measured — stop and report rather than proceeding.

- [ ] **Step 4: Seed the ledger**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY tools/binrecon/seed_ledger.py \
  "$RECON/source-map.json" "$REF" "$RECON/ledger.json"
```

Expected: `68 entries`.

- [ ] **Step 5: Write the divergences skeleton**

Create `src/drvSCSIServer/reconstruction/divergences.md` with the frame and the two out-of-scope records. Findings are added by Tasks 3–7; this step establishes the file and the facts that need no examination:

```markdown
# drvSCSIServer divergences

Reference: `SCSIServer.config/SCSIServer_reloc`, SHA-256
`E813777748A4FAC9348AA1CF4E979863B96D75B09FDAC16DF586031499A122A2`, `__text`
13744 bytes.
Analysis: IDA 9.2 (`tools/binrecon/out/scsiserver-ppc/published/analysis-reference-ida.json`).
Ghidra and angr are i386-only and cannot analyse this binary.

No PowerPC build exists in this environment, so nothing recorded here is
compile-verified. Every claim rests on the reference disassembly.

## Starting state

| Bucket | Count | Bytes |
| --- | --- | --- |
| mapped | 41 | 5796 |
| unmapped | 27 | 5724 |
| duplicate_candidates | 0 | — |
| boundary_disputed | 0 | — |

## Out of scope

**138 jump islands.** IDA finds 206 functions; 138 are unnamed 16-byte
`lis`/`mr`/`mtctr`/`bctr` sequences — build-generated branch glue for calls that
exceed the PowerPC branch displacement. They are not source and are excluded
from the map by `filter_named_functions.py`. Note that a 16-byte size alone does
not identify one: `+[IOSCSISession controllerNameList]`, `-[IOSCSISession name]`
and `+[SCSIServerVersion driverKitVersionForSCSIServer]` are also 16 bytes.

**Two build-generated classes.**
`+[SCSIServerKernelServerInstance kernelServerInstance]` (address 13708, 20
bytes) and `+[SCSIServerVersion driverKitVersionForSCSIServer]` (13728, 16
bytes) are emitted by the Kernel Server build from the project's own settings,
not written by hand. They remain in the `unmapped` bucket permanently.

## The analyzer gap at address 0

`+[SCSIServer deviceStyle]` occupies address 0 in the symbol table, but IDA
emits no function entry there, so it cannot appear in `source-map.json` — the map
covers 68 functions, not the symbol table's 69. Our `SCSIServer.m:37` implements
it. This is the same mismatch `ppc_invariant_check.py --analysis` reported during
the binrecon PowerPC acceptance run, and it is an analyzer artifact, not a
missing function.
```

- [ ] **Step 6: Validate the artifacts**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import os
from pathlib import Path
from binrecon.identity import identify
from binrecon.ledger import load_ledger
from binrecon.schema import load_source_map
recon = Path(os.environ['RECON'])
reference = identify(Path(os.environ['REF']))
load_ledger(recon / 'ledger.json', reference, None)
load_source_map(recon / 'source-map.json', repo_root=Path('.'))
print('both artifacts validate')
"
```

Expected: `both artifacts validate`. If `load_source_map` requires a reference analysis argument, pass `reference_analysis=json.load(open(os.environ['NAMED']))`; check its signature with `$PY -c "import inspect, binrecon.schema as s; print(inspect.signature(s.load_source_map))"`.

- [ ] **Step 7: Commit**

```bash
cd /d/RhapsodiOS && git add src/drvSCSIServer/reconstruction && git commit -m "drvSCSIServer: add the PowerPC reconstruction source map and ledger"
```

---

### Task 3: Examine the SCSIServer.m block

**Files:**
- Modify: `src/drvSCSIServer/reconstruction/ledger.json`, `src/drvSCSIServer/reconstruction/divergences.md`

**Interfaces:**
- Consumes: the artifacts from Task 2.
- Produces: six ledger entries dispositioned; any divergence recorded for Task 12 to fix.

**The six functions, with the source site the map found:**

| Address | Size | Reference name | Source |
| --- | --- | --- | --- |
| 16 | 20 | `+[SCSIServer requiredProtocols]` | `SCSIServer.m:118` |
| 36 | 176 | `+[SCSIServer probe:]` | `SCSIServer.m:60` |
| 228 | 220 | `-[SCSIServer initFromDeviceDescription:]` | `SCSIServer.m:138` |
| 480 | 136 | `-[SCSIServer registerSCSIController:]` | `SCSIServer.m:218` |
| 632 | 124 | `-[SCSIServer serverConnect:taskPort:]` | `SCSIServer.m:284` |
| 772 | 324 | `-[SCSIServer getCharValues:forParameter:count:]` | `SCSIServer.m:342` |

- [ ] **Step 1: Dump each function's disassembly**

For each address in the table:

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os, sys
address = int(sys.argv[1])
d = json.load(open(os.environ['NAMED']))
fn = next(f for f in d['functions'] if f['address'] == address)
print(fn['names'][0], 'size', fn['size'])
for i in fn['instructions']:
    print('  %6d  %-10s %s' % (i['address'], i['mnemonic'], i['operands']))
print('calls:', [c['name'] for c in fn['calls']])
" 16
```

- [ ] **Step 2: Read each against its source site and decide a status**

For each function, compare the disassembly to the source at the mapped line and choose:

- `assembly-matched` — read instruction by instruction, our source accounts for every instruction.
- `control-flow-confirmed` — same structure and calls, differences cosmetic (register allocation, instruction scheduling, a reordered but equivalent test).
- `intentional-mismatch` — we deliberately differ; requires `--reason` and `--reviewer`.

A divergence that is *not* intentional is not a status: leave the entry `unexamined`, record the finding in `divergences.md`, and Task 12 fixes it. This is the convention the drvEISABus and drvISASerialPort passes used, so a reader can tell "examined and correct" from "examined and wrong".

- [ ] **Step 3: Apply each transition**

```bash
cd /d/RhapsodiOS && BINRECON_REFERENCE="$REF" PYTHONPATH=tools/binrecon $PY -m binrecon ledger \
  --profile tools/binrecon/profiles/scsiserver-ppc.json --ledger "$RECON/ledger.json" \
  --address 16 --status assembly-matched --reviewer claude \
  --reason "read instruction by instruction against SCSIServer.m:118; returns the protocol array unchanged"
```

Repeat per function with its own address, status and reason. `--reason` must state what was compared and what was found — "looks fine" is not a reason.

- [ ] **Step 4: Record findings**

Append a `## Finding: <name>` section to `divergences.md` for every function where our source diverges, and a short `## SCSIServer.m block` summary naming the statuses reached. Each finding presents the reference's disassembled behaviour first, then our source, then the consequence.

- [ ] **Step 5: Verify no entry in the block is left unexamined without a finding**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os
entries = json.load(open(os.environ['RECON'] + '/ledger.json'))['entries']
block = [e for e in entries if e['address'] < 1100]
for e in block:
    print('%6d  %-46s %s' % (e['address'], e['names'][0], e['status']))
print('unexamined in block:', sum(1 for e in block if e['status'] == 'unexamined'))
"
```

Every `unexamined` entry printed must have a corresponding finding in `divergences.md`.

- [ ] **Step 6: Commit**

```bash
cd /d/RhapsodiOS && git add src/drvSCSIServer/reconstruction && git commit -m "drvSCSIServer: disposition the SCSIServer class methods"
```

---

### Task 4: Examine the session and reservation block

**Files:**
- Modify: `src/drvSCSIServer/reconstruction/ledger.json`, `src/drvSCSIServer/reconstruction/divergences.md`

**Interfaces:** same as Task 3.

**The nine functions:**

| Address | Size | Reference name | Source |
| --- | --- | --- | --- |
| 1604 | 16 | `+[IOSCSISession controllerNameList]` | `IOSCSISession.m:59` |
| 1620 | 40 | `-[IOSCSISession init]` | `IOSCSISession.m:74` |
| 1676 | 40 | `-[IOSCSISession initForDevice:result:]` | `IOSCSISession.m:96` |
| 1732 | 248 | `-[IOSCSISession free]` | `IOSCSISession.m:122` |
| 2076 | 16 | `-[IOSCSISession name]` | `IOSCSISession.m:202` |
| 2092 | 104 | `_findReservation` | `IOSCSISession.m:1373` |
| 2196 | 160 | `_addReservation` | `IOSCSISession.m:1188` |
| 2388 | 140 | `_removeReservation` | `IOSCSISession.m:1308` |
| 2544 | 112 | `_blastAllReservations` | `IOSCSISession.m:1258` |

- [ ] **Step 1: Dump each function's disassembly**

Use Task 3 Step 1's command with each address above.

- [ ] **Step 2: Pay particular attention to the reservation four**

`_findReservation`, `_addReservation`, `_removeReservation` and `_blastAllReservations` share a data structure. Read all four before dispositioning any, and check they agree with each other on that structure's layout — element size, the field holding target and lun, and the sentinel marking a free slot. A layout disagreement between our four and Apple's four is a single finding, not four.

- [ ] **Step 3: Apply each transition**

Use Task 3 Step 3's command form, per address.

- [ ] **Step 4: Record findings**

Append a finding per divergence plus a `## IOSCSISession class and reservations` summary.

- [ ] **Step 5: Verify the block**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os
entries = json.load(open(os.environ['RECON'] + '/ledger.json'))['entries']
block = [e for e in entries if 1100 <= e['address'] < 3000]
for e in block:
    print('%6d  %-46s %s' % (e['address'], e['names'][0], e['status']))
"
```

- [ ] **Step 6: Commit**

```bash
cd /d/RhapsodiOS && git add src/drvSCSIServer/reconstruction && git commit -m "drvSCSIServer: disposition the session class and reservation table"
```

---

### Task 5: Examine the 18 Objective-C dispatch wrappers

**Files:**
- Modify: `src/drvSCSIServer/reconstruction/ledger.json`, `src/drvSCSIServer/reconstruction/divergences.md`

**Interfaces:** same as Task 3.

**What these are:** hand-written C wrappers that dispatch an Objective-C message — `IOSCSISession_free(session)` is `[session free]`. The spec establishes this from disassembly (§2.6): each loads a selector from `__OBJC,__message_refs` and branches to `_objc_msgSend` through a jump island. They are **not** MiG output and must not be deleted when Task 9 adds the `.defs`.

**The 18 functions:**

| Address | Size | Reference name | Source |
| --- | --- | --- | --- |
| 3028 | 144 | `_IOSCSISession_initForDevice` | `IOSCSISession.m:1071` |
| 3204 | 44 | `_IOSCSISession_free` | `IOSCSISession.m:1049` |
| 3264 | 76 | `_IOSCSISession_releaseAllUnits` | `IOSCSISession.m:1022` |
| 3372 | 140 | `_IOSCSISession_reserveTarget` | `IOSCSISession.m:964` |
| 3544 | 204 | `_IOSCSISession_releaseTarget` | `IOSCSISession.m:2582` |
| 3796 | 156 | `_IOSCSISession_reserveSCSI3Target` | `IOSCSISession.m:2522` |
| 3984 | 172 | `_IOSCSISession_releaseSCSI3Target` | `IOSCSISession.m:2456` |
| 4204 | 68 | `_IOSCSISession_numberOfTargets` | `IOSCSISession.m:2416` |
| 4288 | 208 | `_IOSCSISession_executeRequest` | `IOSCSISession.m:2141` |
| 4544 | 220 | `_IOSCSISession_executeRequestOOLScatter` | `IOSCSISession.m:2357` |
| 4828 | 376 | `_IOSCSISession_executeRequestScatter` | `IOSCSISession.m:2239` |
| 5220 | 208 | `_IOSCSISession_executeSCSI3Request` | `IOSCSISession.m:1852` |
| 5476 | 220 | `_IOSCSISession_executeSCSI3RequestOOLScatter` | `IOSCSISession.m:2063` |
| 5760 | 376 | `_IOSCSISession_executeSCSI3RequestScatter` | `IOSCSISession.m:1947` |
| 6152 | 68 | `_IOSCSISession_resetSCSIBus` | `IOSCSISession.m:1808` |
| 6236 | 52 | `_IOSCSISession_returnFromScStatus` | `IOSCSISession.m:1790` |
| 6304 | 68 | `_IOSCSISession_maxTransfer` | `IOSCSISession.m:1137` |
| 6388 | 56 | `_IOSCSISession_getDMAAlignment` | `IOSCSISession.m:1113` |

- [ ] **Step 1: Dump each function's disassembly**

Use Task 3 Step 1's command with each address above.

- [ ] **Step 2: Check the selector each dispatches**

For every wrapper, confirm the selector it loads matches the method our source sends. The selector name appears in the operand as IDA's `pa<Selector>` reference; resolve it against the reference's Objective-C metadata if the operand is ambiguous:

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
from binrecon.macho import objc_method_index
import os
index = objc_method_index(os.environ['REF'])
for address, names in sorted(index.items()):
    print(hex(address), names)
"
```

A wrapper that dispatches a different selector than ours is a finding, and a likely one given the message-ID evidence in the spec.

- [ ] **Step 3: Check the six scatter/OOL variants against each other**

`executeRequest`, `executeRequestScatter`, `executeRequestOOLScatter` and their three `SCSI3` counterparts differ only in how they pass the buffer list. Read all six together and confirm our source draws the same distinctions — an out-of-line versus in-line mix-up here would be invisible in any single function.

- [ ] **Step 4: Apply each transition**

Use Task 3 Step 3's command form, per address.

- [ ] **Step 5: Record findings and verify the block**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os
entries = json.load(open(os.environ['RECON'] + '/ledger.json'))['entries']
block = [e for e in entries if 3000 <= e['address'] < 6460]
for e in block:
    print('%6d  %-46s %s' % (e['address'], e['names'][0], e['status']))
"
```

- [ ] **Step 6: Commit**

```bash
cd /d/RhapsodiOS && git add src/drvSCSIServer/reconstruction && git commit -m "drvSCSIServer: disposition the Objective-C dispatch wrappers"
```

---

### Task 6: Examine the task plumbing and the MiG demux

**Files:**
- Modify: `src/drvSCSIServer/reconstruction/ledger.json`, `src/drvSCSIServer/reconstruction/divergences.md`

**Interfaces:** same as Task 3. This task completes the 41 mapped functions (6 + 9 + 18 + 8 = 41).

**The eight functions:**

| Address | Size | Reference name | Source |
| --- | --- | --- | --- |
| 6460 | 96 | `_IOTaskPortAllocateName` | `IOSCSISession.m:1760` |
| 6652 | 48 | `_IOTaskPortDeallocate` | `IOSCSISession.m:1744` |
| 6716 | 80 | `_IOTaskWireMemory` | `IOSCSISession.m:1691` |
| 6812 | 80 | `_IOTaskUnwireMemory` | `IOSCSISession.m:1716` |
| 6908 | 232 | `_IOReferenceClientTask` | `IOSCSISession.m:1590` |
| 7156 | 148 | `_IODereferenceClientTask` | `IOSCSISession.m:1519` |
| 8988 | 192 | `_IOReleaseNotifyForFunc` | `IOSCSISession.m:1479` |
| 13520 | 188 | `_IOSCSISessionMig_server` | `IOSCSISession.m:411` |

- [ ] **Step 1: Dump each function's disassembly**

Use Task 3 Step 1's command with each address above.

- [ ] **Step 2: Disposition `_IOSCSISessionMig_server` as an intentional mismatch, pending Task 9**

Our demux is functionally reachable but its dispatch table is wired wrong on every entry (spec §2.2), and Task 9 replaces the whole apparatus with MiG output. Record it accordingly rather than pretending it matches:

```bash
cd /d/RhapsodiOS && BINRECON_REFERENCE="$REF" PYTHONPATH=tools/binrecon $PY -m binrecon ledger \
  --profile tools/binrecon/profiles/scsiserver-ppc.json --ledger "$RECON/ledger.json" \
  --address 13520 --status intentional-mismatch --reviewer claude \
  --reason "our IOSCSISessionMig_server is hand-written where Apple's is MiG output; the ID range and reply convention match but the dispatch table order is wrong on all 18 entries (see divergences.md). Replaced by IOSCSISessionMig.defs; re-dispositioned after the fix."
```

- [ ] **Step 3: Check `_IOReferenceClientTask`'s signature against our source**

Our `IOReferenceClientTask(int **param_1)` carries a decompiler-generated parameter name, a signal the function was transcribed from decompiler output rather than reconstructed. Read the reference to recover what the parameter actually is, and record the true signature in the finding so Task 12 can correct the declaration.

- [ ] **Step 4: Apply the remaining transitions**

Use Task 3 Step 3's command form for the seven plumbing functions.

- [ ] **Step 5: Verify all 41 mapped entries are now dispositioned**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os
entries = json.load(open(os.environ['RECON'] + '/ledger.json'))['entries']
mapped = [e for e in entries if e['source_path']]
print('mapped entries:', len(mapped))
from collections import Counter
print(Counter(e['status'] for e in mapped))
"
```

Expected: `mapped entries: 41`, and every `unexamined` remaining must have a finding in `divergences.md`.

- [ ] **Step 6: Commit**

```bash
cd /d/RhapsodiOS && git add src/drvSCSIServer/reconstruction && git commit -m "drvSCSIServer: disposition the task plumbing and the MiG demux"
```

---

### Task 7: Document the 27 unmapped functions and finish the report

**Files:**
- Modify: `src/drvSCSIServer/reconstruction/divergences.md`, `src/drvSCSIServer/reconstruction/ledger.json`

**Interfaces:**
- Consumes: everything from Tasks 3–6.
- Produces: the completed Phase 1 report. Phase 2 tasks read its findings.

- [ ] **Step 1: Write the MiG dispatch-order finding**

This is the report's central finding. Reproduce the evidence rather than asserting it:

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
from binrecon.macho import read_macho
import os
d = read_macho(os.environ['REF'])
syms = {s['address']: s['name'] for s in d['symbols'] if s['section'] == '__TEXT,__text'}
table = sorted((r for r in d['extensions']['macho']['relocations']
                if r['section'] == '__TEXT,__const'), key=lambda r: r['address'])
for index, r in enumerate(table):
    print('%2d  id %d  0x%04x -> %s' % (index, 4242 + index, r['address'], syms.get(r['addend'], '?')))
"
```

Write the finding with: the demux arithmetic (`addic r0, r0, -0x1092` giving base 4242, `cmplwi cr1, r0, 0x11` giving 18 routines, `addic r0, r0, 0x64` giving reply = request + 100), Apple's table order from the command above, our table order from `IOSCSISession.m:921`, a side-by-side of the two, and the consequence: no message ID dispatches to the correct routine, so any client RPC lands in the wrong handler.

- [ ] **Step 2: Write the PIC misreading finding**

Record that `IOSCSISession.m`'s comment on the `-0xaa4` offset — "you would need to use linker scripts or compiler-specific directives to place this at the correct address" — misreads a position-independent displacement as a required absolute address. Explain what `lis r9, 0` / `addi r9, r9, -0xAA4` actually is: the table's offset from the code's anchor, resolved by the scattered `HA16`/`LO16` relocation pair whose `r_value` is `0x37a4` in `__TEXT,__const`. Nothing needs placing at a fixed address. This belief is why the author treated a faithful reconstruction as impossible, so it is a finding in its own right.

- [ ] **Step 3: Write the absent-functions finding**

One section covering the six functions our tree lacks, each with what the reference does and what our tree has instead:

| Function | Bytes | State in our tree |
| --- | --- | --- |
| `__io_task_notification` | 644 | absent |
| `_IORequestNotifyForClientTask` | 480 | declared `extern`, never defined |
| `_serverThreadFunc` | 276 | absent |
| `_IOConvertTaskPortToVMTask` | 160 | absent |
| `_IOTaskPortAllocate` | 48 | absent (only `_IOTaskPortAllocateName` exists) |
| `_IODestroyMappedVMTask` | 32 | absent |

Dump each with Task 3 Step 1's command and describe its behaviour, since Task 10 and Task 11 write these from this description.

- [ ] **Step 4: Write the naming findings**

Two findings. First, `-[IOSCSISession(Private) _initServerWithTask:sendPort:]` at `IOSCSISession.m:234` carries a spurious leading underscore; Apple's is `-[IOSCSISession(Private) initServerWithTask:sendPort:]`, and the category is already correct. Second, `-[IOSCSISession(Private) _reserveTarget:lun:]` has no counterpart in the reference — determine from the reference whether it corresponds to something Apple named differently or is ours alone, and state the disposition Task 8 should apply. Show the evidence:

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY tools/binrecon/selector_check.py "$REF" "$SRC"
```

Expected today: 1 rename, 0 duplicates, 2 missing (build-generated), 1 extra.

- [ ] **Step 5: Disposition the 27 unmapped ledger entries**

The 18 `__XIOSCSISession_*` entries and the six absent functions stay `unexamined` — they are examined but absent, and Phase 2 supplies them; the findings carry the evidence. The two build-generated classes get `intentional-mismatch`:

```bash
cd /d/RhapsodiOS && BINRECON_REFERENCE="$REF" PYTHONPATH=tools/binrecon $PY -m binrecon ledger \
  --profile tools/binrecon/profiles/scsiserver-ppc.json --ledger "$RECON/ledger.json" \
  --address 13708 --status intentional-mismatch --reviewer claude \
  --reason "emitted by the Kernel Server build from the project's own settings, not hand-written source"
```

Repeat for address 13728.

- [ ] **Step 6: Add the summary table**

Add a `## Summary` section near the top of `divergences.md` counting statuses reached across all 68 entries, and stating plainly how many functions were read at instruction level and how many are absent from our tree.

- [ ] **Step 7: Validate and commit**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import os
from pathlib import Path
from binrecon.identity import identify
from binrecon.ledger import load_ledger
load_ledger(Path(os.environ['RECON']) / 'ledger.json', identify(Path(os.environ['REF'])), None)
print('ledger validates')
"
```

```bash
cd /d/RhapsodiOS && git add src/drvSCSIServer/reconstruction && git commit -m "drvSCSIServer: record the PowerPC reconstruction divergences"
```

---

## Phase 2 — Fix

### Task 8: Correct the selector names

**Files:**
- Modify: `src/drvSCSIServer/SCSIServer.drvproj/SCSIServer.lksproj/IOSCSISession.m`, `.../IOSCSISession.h`

**Interfaces:**
- Consumes: Task 7's naming findings.
- Produces: `selector_check.py` reaching 0 renames and 0 duplicates — a gate every later task must keep green.

- [ ] **Step 1: Confirm the current state**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY tools/binrecon/selector_check.py "$REF" "$SRC"; echo "exit=$?"
```

Expected: `renames (1)` naming `-[IOSCSISession(Private) _initServerWithTask:sendPort:]` at `IOSCSISession.m:234`.

- [ ] **Step 2: Rename the method and every call site**

In `IOSCSISession.m`, change the definition at line 234 from `_initServerWithTask:sendPort:` to `initServerWithTask:sendPort:`, and update its declaration in `IOSCSISession.h` plus every send. Find them all first:

```bash
cd /d/RhapsodiOS && grep -rn "_initServerWithTask" "$SRC"
```

Every hit must be updated, including the ones inside comments — a comment naming the old selector is stale documentation the moment the method is renamed.

- [ ] **Step 3: Disposition the extra method**

Apply Task 7 Step 4's decision for `-[IOSCSISession(Private) _reserveTarget:lun:]`. If Task 7 found it has no counterpart and nothing calls it, delete it and its declaration; confirm nothing calls it first:

```bash
cd /d/RhapsodiOS && grep -rn "_reserveTarget:" "$SRC"
```

If Task 7 found it corresponds to something Apple named differently, rename it instead and record which reference function it serves.

- [ ] **Step 4: Verify the gate**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY tools/binrecon/selector_check.py "$REF" "$SRC"; echo "exit=$?"
```

Expected: `renames (0)`, `duplicates (0)`, `exit=0`. `missing (2)` remains — both build-generated. `extra` must be 0 if the method was deleted.

- [ ] **Step 5: Update the ledger entry**

```bash
cd /d/RhapsodiOS && BINRECON_REFERENCE="$REF" PYTHONPATH=tools/binrecon $PY -m binrecon ledger \
  --profile tools/binrecon/profiles/scsiserver-ppc.json --ledger "$RECON/ledger.json" \
  --address 1160 --status signature-confirmed --reviewer claude \
  --source-path "src/drvSCSIServer/SCSIServer.drvproj/SCSIServer.lksproj/IOSCSISession.m" --source-line 234 \
  --reason "renamed from _initServerWithTask:sendPort: to match the reference selector; body not yet read instruction by instruction"
```

Adjust `--source-line` to the definition's line after editing.

- [ ] **Step 6: Commit**

```bash
cd /d/RhapsodiOS && git add "$SRC" src/drvSCSIServer/reconstruction && git commit -m "drvSCSIServer: drop the spurious underscore from initServerWithTask:sendPort:"
```

---

### Task 9: Recover the MiG interface

**Files:**
- Create: `src/drvSCSIServer/SCSIServer.drvproj/SCSIServer.lksproj/IOSCSISessionMig.defs`
- Modify: `.../IOSCSISession.m` (delete the hand-rolled apparatus), `.../Makefile.preamble`, `.../PB.project`

**Interfaces:**
- Consumes: Task 7's dispatch-order finding, which carries Apple's routine order.
- Produces: the 18 `__XIOSCSISession_*` server stubs and `_IOSCSISessionMig_server` as build output rather than hand-written source.

**Facts the `.defs` must encode**, all from the spec §2.1:

- Subsystem name `IOSCSISessionMig` — the demux symbol is `_IOSCSISessionMig_server`, and MiG names a subsystem's demux `<subsystem>_server`. The filename must match the subsystem, because `pb_makefiles` derives generated filenames from the basename; `IOSCSISession.defs` would generate an `IOSCSISession.h` that collides with our hand-written header.
- Base message ID 4242, 18 routines, reply IDs at request + 100.
- Routine names `IOSCSISession_free`, `IOSCSISession_initForDevice`, … so MiG's `_X<routine>` server stubs match the `__XIOSCSISession_*` symbols.

- [ ] **Step 1: Recover each routine's signature**

For each of the 18 `__X` stubs, read the request and reply message layout — argument count, sizes, and `in`/`out` direction:

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os, sys
d = json.load(open(os.environ['NAMED']))
for fn in sorted((f for f in d['functions'] if f['names'][0].startswith('__XIOSCSISession')),
                 key=lambda f: f['address']):
    print('===', fn['names'][0], 'size', fn['size'])
    for i in fn['instructions']:
        print('   %-10s %s' % (i['mnemonic'], i['operands']))
"
```

The stub's loads from the request buffer give the in-arguments and their offsets; its stores into the reply give the out-arguments. Cross-check each against the corresponding `IOSCSISession_*` wrapper's C signature, which our tree already has and Task 5 confirmed.

- [ ] **Step 2: Write the `.defs`**

Create `IOSCSISessionMig.defs` with the 18 routines in Apple's order — `free`, `initForDevice`, `releaseAllUnits`, `reserveTarget`, `releaseTarget`, `reserveSCSI3Target`, `releaseSCSI3Target`, `numberOfTargets`, `executeRequest`, `executeSCSI3Request`, `executeRequestScatter`, `executeSCSI3RequestScatter`, `executeRequestOOLScatter`, `executeSCSI3RequestOOLScatter`, `resetSCSIBus`, `returnFromScStatus`, `maxTransfer`, `getDMAAlignment` — in this shape:

```
subsystem IOSCSISessionMig 4242;

#include <mach/std_types.defs>

routine IOSCSISession_free(
        server          : mach_port_t);

routine IOSCSISession_initForDevice(
        server          : mach_port_t;
    in  deviceName      : <type recovered in Step 1>);
```

The order is what fixes the dispatch bug: MiG emits the table in routine order, so declaring them in Apple's order makes our table match by construction. Argument names and types come from Step 1; do not guess them.

- [ ] **Step 3: Delete the hand-rolled apparatus**

From `IOSCSISession.m`, delete the 562-line block spanning `IOSCSISessionMig_server` (line 411) through the end of `_IOSCSISessionMig_handlers[18]` (line 940), which includes the demux, the 18 `_IOSCSISession_*_handler` functions and the dispatch table. Delete the `mig_handler_func_t` typedef and the handler declarations from `IOSCSISession.h`.

**Do not delete the 18 `IOSCSISession_*` C wrappers.** They are hand-written Objective-C dispatch wrappers (spec §2.6), not MiG output, and MiG's generated user side is deliberately not compiled so their symbols do not collide. Confirm they survive:

```bash
cd /d/RhapsodiOS && grep -c "^int IOSCSISession_\|^void IOSCSISession_" "$SRC/IOSCSISession.m"
```

Expected: `18`.

- [ ] **Step 4: Wire the build**

In `Makefile.preamble`, declare the `.defs` and compile only the generated server side:

```make
DEFSFILES = IOSCSISessionMig.defs
OTHER_GENERATED_OFILES += IOSCSISessionMigServer.o
```

`MIGFILES` is for `.mig` files and is the wrong key. `src/pb_makefiles-1/common.make:238` expands each `DEFSFILES` entry into `%.h`, `%User.c` and `%Server.c`; `common.make:242` shows generated sources become objects only when declared, so leaving `IOSCSISessionMigUser.c` out of both `CFILES` and `OTHER_GENERATED_OFILES` is what prevents duplicate `_IOSCSISession_*` symbols. Read both lines before editing to confirm the variable names in this checkout.

In `PB.project`, add `IOSCSISessionMig.defs` to `OTHER_SOURCES` so Project Builder shows it.

- [ ] **Step 5: Verify what can be verified**

There is no MiG here and no compiler, so verification is limited to consistency checks. Run all three:

```bash
cd /d/RhapsodiOS && grep -c "^routine\|^simpleroutine" "$SRC/IOSCSISessionMig.defs"
```

Expected: `18`.

```bash
cd /d/RhapsodiOS && grep -n "IOSCSISessionMig_server\|_handler\b\|mig_handler_func_t" "$SRC/IOSCSISession.m" "$SRC/IOSCSISession.h"
```

Expected: no output — every trace of the hand-rolled apparatus is gone.

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY tools/binrecon/selector_check.py "$REF" "$SRC"; echo "exit=$?"
```

Expected: still `renames (0)`, `duplicates (0)`, `exit=0`.

Then confirm the `.defs` routine order against the binary one final time, by eye, using Task 7 Step 1's command output. An order mismatch here reintroduces the exact bug this task exists to fix.

- [ ] **Step 6: Re-disposition the ledger entries**

Set the 18 `__XIOSCSISession_*` entries and `_IOSCSISessionMig_server` to `intentional-mismatch` with a reason recording that they are now build output from `IOSCSISessionMig.defs` rather than checked-in source, so no source line can be cited. Addresses: 9212, 9316, 9540, 9668, 9864, 10060, 10256, 10452, 10596, 10956, 11316, 11736, 12156, 12536, 12916, 13060, 13232, 13376, 13520.

```bash
cd /d/RhapsodiOS && BINRECON_REFERENCE="$REF" PYTHONPATH=tools/binrecon $PY -m binrecon ledger \
  --profile tools/binrecon/profiles/scsiserver-ppc.json --ledger "$RECON/ledger.json" \
  --address 9212 --status intentional-mismatch --reviewer claude \
  --reason "generated by MiG from IOSCSISessionMig.defs (subsystem IOSCSISessionMig, base 4242, routine 0); no checked-in source line exists"
```

Repeat per address, giving each its routine index.

- [ ] **Step 7: Commit**

```bash
cd /d/RhapsodiOS && git add "$SRC" src/drvSCSIServer/reconstruction && git commit -m "drvSCSIServer: recover the MiG interface and delete the hand-rolled dispatch"
```

---

### Task 10: Split out and complete the task plumbing

**Files:**
- Create: `.../IOTask.m`, `.../IOTask.h`
- Modify: `.../IOSCSISession.m`, `.../IOSCSISession.h`, `.../PB.project`

**Interfaces:**
- Consumes: Task 7's absent-functions finding, which describes what each missing function does.
- Produces: `IOTask.m` holding all eight task/notification functions — the four already in our tree plus the four absent ones that belong here.

**Functions this file owns**, in the reference's address order:

| Address | Size | Function | Source today |
| --- | --- | --- | --- |
| 6460 | 96 | `_IOTaskPortAllocateName` | `IOSCSISession.m:1760` |
| 6588 | 48 | `_IOTaskPortAllocate` | absent |
| 6652 | 48 | `_IOTaskPortDeallocate` | `IOSCSISession.m:1744` |
| 6716 | 80 | `_IOTaskWireMemory` | `IOSCSISession.m:1691` |
| 6812 | 80 | `_IOTaskUnwireMemory` | `IOSCSISession.m:1716` |
| 6908 | 232 | `_IOReferenceClientTask` | `IOSCSISession.m:1590` |
| 7156 | 148 | `_IODereferenceClientTask` | `IOSCSISession.m:1519` |
| 7320 | 160 | `_IOConvertTaskPortToVMTask` | absent |
| 7576 | 32 | `_IODestroyMappedVMTask` | absent |
| 7624 | 644 | `__io_task_notification` | absent |
| 8412 | 480 | `_IORequestNotifyForClientTask` | `extern` only |
| 8988 | 192 | `_IOReleaseNotifyForFunc` | `IOSCSISession.m:1479` |

- [ ] **Step 1: Create `IOTask.h`**

Move the declarations for the functions above out of `IOSCSISession.h` into a new `IOTask.h`, and add declarations for the five that had none. Include `IOTask.h` from `IOSCSISession.m`, which still calls into this layer.

- [ ] **Step 2: Move the seven existing definitions**

Move `_IOTaskPortAllocateName`, `_IOTaskPortDeallocate`, `_IOTaskWireMemory`, `_IOTaskUnwireMemory`, `_IOReferenceClientTask`, `_IODereferenceClientTask` and `_IOReleaseNotifyForFunc` from `IOSCSISession.m` into `IOTask.m` **unchanged**, in the reference's address order. Moving and editing in one commit makes a reviewer unable to tell which is which; corrections come in Step 4.

- [ ] **Step 3: Verify the move changed nothing**

```bash
cd /d/RhapsodiOS && git diff --stat -- "$SRC"
```

Insertions into `IOTask.m` and deletions from `IOSCSISession.m` should be within a few lines of each other. Then confirm no definition was lost:

```bash
cd /d/RhapsodiOS && for f in IOTaskPortAllocateName IOTaskPortDeallocate IOTaskWireMemory IOTaskUnwireMemory IOReferenceClientTask IODereferenceClientTask IOReleaseNotifyForFunc; do printf "%-30s %s\n" "$f" "$(grep -c "^[a-z].*$f(" "$SRC/IOTask.m")"; done
```

Expected: `1` for each.

- [ ] **Step 4: Write the five absent functions**

Add `_IOTaskPortAllocate`, `_IOConvertTaskPortToVMTask`, `_IODestroyMappedVMTask`, `_io_task_notification` and `IORequestNotifyForClientTask` to `IOTask.m`, each written from the disassembly Task 7 Step 3 recorded. Place each at its address-order position. Remove the now-redundant `extern` declaration of `IORequestNotifyForClientTask` from wherever Task 7 found it.

Also correct `_IOReferenceClientTask`'s signature using the true parameter type Task 6 Step 3 recovered, replacing the decompiler-generated `int **param_1`.

- [ ] **Step 5: Update the project file**

Add `IOTask.m` to `PB.project`'s `FILESTABLE` `CLASSES` list and `IOTask.h` to `H_FILES`, matching the existing entries' formatting exactly.

- [ ] **Step 6: Verify**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY tools/binrecon/selector_check.py "$REF" "$SRC"; echo "exit=$?"
```

Expected: `renames (0)`, `duplicates (0)`, `exit=0` — the split moved C functions, not Objective-C methods, so the selector picture must be unchanged.

```bash
cd /d/RhapsodiOS && grep -n "IOTask" "$SRC/PB.project"
```

Expected: `IOTask.m` under `CLASSES`, `IOTask.h` under `H_FILES`.

- [ ] **Step 7: Update the ledger**

Point all twelve entries at their new `source_path` and `source_line` in `IOTask.m`, and set a status for the five newly written functions:

```bash
cd /d/RhapsodiOS && BINRECON_REFERENCE="$REF" PYTHONPATH=tools/binrecon $PY -m binrecon ledger \
  --profile tools/binrecon/profiles/scsiserver-ppc.json --ledger "$RECON/ledger.json" \
  --address 6588 --status control-flow-confirmed --reviewer claude \
  --source-path "src/drvSCSIServer/SCSIServer.drvproj/SCSIServer.lksproj/IOTask.m" --source-line 1 \
  --reason "written from the reference disassembly at 6588; allocates a task port and returns it through the out-parameter"
```

Use each function's real line number after editing.

- [ ] **Step 8: Commit**

```bash
cd /d/RhapsodiOS && git add "$SRC" src/drvSCSIServer/reconstruction && git commit -m "drvSCSIServer: move the task plumbing into IOTask.m and complete it"
```

---

### Task 11: Add `_serverThreadFunc`

**Files:**
- Modify: `.../IOSCSISession.m`, `.../IOSCSISession.h`

**Interfaces:**
- Consumes: Task 7's description of `_serverThreadFunc` (address 2672, 276 bytes).
- Produces: the session's server thread entry point, restoring the last absent function outside `IOTask.m`.

- [ ] **Step 1: Re-read the reference**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os
d = json.load(open(os.environ['NAMED']))
fn = next(f for f in d['functions'] if f['address'] == 2672)
print(fn['names'][0], 'size', fn['size'])
for i in fn['instructions']:
    print('  %6d  %-10s %s' % (i['address'], i['mnemonic'], i['operands']))
print('calls:', [c['name'] for c in fn['calls']])
"
```

- [ ] **Step 2: Write the function**

Add `_serverThreadFunc` to `IOSCSISession.m` positioned after `_blastAllReservations`, matching the reference's address order (2544 then 2672). Its declaration goes in `IOSCSISession.h` only if the reference shows it called from another translation unit; a file-static function needs none, and the reference's symbol is a defined `__TEXT,__text` entry, which does not by itself prove external linkage — check whether any other function calls it before deciding.

- [ ] **Step 3: Verify**

```bash
cd /d/RhapsodiOS && grep -n "serverThreadFunc" "$SRC/IOSCSISession.m" "$SRC/IOSCSISession.h"
```

Expected: a definition, plus a send site if the reference has one.

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY tools/binrecon/selector_check.py "$REF" "$SRC"; echo "exit=$?"
```

Expected: unchanged, `exit=0`.

- [ ] **Step 4: Update the ledger**

```bash
cd /d/RhapsodiOS && BINRECON_REFERENCE="$REF" PYTHONPATH=tools/binrecon $PY -m binrecon ledger \
  --profile tools/binrecon/profiles/scsiserver-ppc.json --ledger "$RECON/ledger.json" \
  --address 2672 --status control-flow-confirmed --reviewer claude \
  --source-path "src/drvSCSIServer/SCSIServer.drvproj/SCSIServer.lksproj/IOSCSISession.m" --source-line 1 \
  --reason "written from the reference disassembly at 2672"
```

Use the real line number.

- [ ] **Step 5: Commit**

```bash
cd /d/RhapsodiOS && git add "$SRC" src/drvSCSIServer/reconstruction && git commit -m "drvSCSIServer: add the session server thread entry point"
```

---

### Task 12: Fix the divergences Phase 1 found

**Files:**
- Modify: whichever source files Phase 1's findings name.

**Interfaces:**
- Consumes: every `## Finding:` section in `divergences.md`, and every ledger entry Tasks 3–6 left `unexamined` with a finding attached.
- Produces: each of those entries reaching `assembly-matched`, `control-flow-confirmed` or `intentional-mismatch`.

**This task's content comes from Phase 1 and cannot be enumerated here** — the findings do not exist until Tasks 3–7 run. What is fixed is the procedure, not the list.

- [ ] **Step 1: List the work**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os
entries = json.load(open(os.environ['RECON'] + '/ledger.json'))['entries']
todo = [e for e in entries if e['status'] == 'unexamined' and e['source_path']]
for e in todo:
    print('%6d  %-46s %s:%s' % (e['address'], e['names'][0], e['source_path'].split('/')[-1], e['source_line']))
print('to fix:', len(todo))
"
```

Every address printed must have a `## Finding:` section in `divergences.md`. An `unexamined` entry with no finding means Tasks 3–6 skipped it — go back rather than inventing a fix.

- [ ] **Step 2: Fix one function per commit**

For each, in address order: re-read the reference disassembly (Task 3 Step 1's command), apply the change the finding calls for, then transition the ledger entry with a reason stating what changed. One function per commit, message naming the function:

```bash
cd /d/RhapsodiOS && git add "$SRC" src/drvSCSIServer/reconstruction && git commit -m "drvSCSIServer: <what changed> in <function>"
```

If re-reading shows the finding was wrong, do not force a fix: correct the finding in `divergences.md`, disposition the entry to the status the evidence supports, and say so in the commit message.

- [ ] **Step 3: Verify nothing is left**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os
from collections import Counter
entries = json.load(open(os.environ['RECON'] + '/ledger.json'))['entries']
print(Counter(e['status'] for e in entries))
print('unexamined:', [e['names'][0] for e in entries if e['status'] == 'unexamined'])
"
```

Expected: no `unexamined` entries remain.

- [ ] **Step 4: Keep the selector gate green**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY tools/binrecon/selector_check.py "$REF" "$SRC"; echo "exit=$?"
```

Expected: `renames (0)`, `duplicates (0)`, `exit=0`.

---

### Task 13: Regenerate the artifacts and run the acceptance gates

**Files:**
- Modify: `src/drvSCSIServer/reconstruction/source-map.json`, `.../ledger.json`, `.../divergences.md`

**Interfaces:**
- Consumes: the finished source tree.
- Produces: artifacts describing the tree as it now stands, plus the recorded acceptance evidence.

- [ ] **Step 1: Regenerate the source map**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -m binrecon source-map \
  --reference-analysis "$NAMED" --binary "$REF" --source-dir "$SRC" \
  --repo-root . --output "$RECON/source-map.json"
```

- [ ] **Step 2: Check the acceptance numbers**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os
m = json.load(open(os.environ['RECON'] + '/source-map.json'))
for bucket in ('mapped', 'unmapped', 'duplicate_candidates', 'boundary_disputed'):
    print('%-22s %d' % (bucket, len(m[bucket])))
print('unmapped:', [e['reference_names'][0] for e in m['unmapped']])
"
```

Expected: **mapped 48, unmapped 20**, duplicate_candidates 0, boundary_disputed 0, per spec §4.2 item 2.

The 48 are the 41 that mapped at the start plus the seven this work supplied: the renamed `initServerWithTask:sendPort:`, `_serverThreadFunc`, and the five plumbing functions from Task 10. The 20 unmapped are the 2 build-generated classes plus the 18 `__XIOSCSISession_*` stubs — the stubs cannot map because `source-map` needs a source site on disk and MiG's generated `IOSCSISessionMigServer.c` does not exist here. Recovering the `.defs` makes them correct, not mapped.

If you observe different numbers, do not adjust anything to reach these — record what you actually saw in `divergences.md` and report it.

- [ ] **Step 3: Reconcile the ledger with the regenerated map**

Re-seed a fresh ledger, then re-apply every status the report established. Do not hand-edit the JSON:

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os
old = {e['address']: e for e in json.load(open(os.environ['RECON'] + '/ledger.json'))['entries']}
print(json.dumps({str(a): [e['status'], e['reason'], e['reviewer']] for a, e in sorted(old.items())}, indent=1))
" > /tmp/ledger-statuses.json
```

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY tools/binrecon/seed_ledger.py \
  "$RECON/source-map.json" "$REF" "$RECON/ledger.json"
```

Then replay each status with `binrecon ledger --address … --status … --reason … --reviewer …` from the saved file.

- [ ] **Step 4: Run every acceptance gate**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY tools/binrecon/selector_check.py "$REF" "$SRC"; echo "exit=$?"
```

Expected: `renames (0)`, `duplicates (0)`, `exit=0`.

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
import json, os
from pathlib import Path
from binrecon.identity import identify
from binrecon.ledger import load_ledger
from binrecon.schema import load_source_map
recon = Path(os.environ['RECON'])
reference = identify(Path(os.environ['REF']))
load_ledger(recon / 'ledger.json', reference, None)
load_source_map(recon / 'source-map.json', repo_root=Path('.'))
print('artifacts validate')
"
```

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY tools/binrecon/ppc_invariant_check.py \
  --binary "$REF" --analysis "$ANALYSIS"; echo "exit=$?"
```

Expected: 998 fused relocations, 0 relocation violations. The single symbol-versus-function-start mismatch for `+[SCSIServer deviceStyle]` at 0 is expected and is the subject of `divergences.md`'s analyzer-gap section.

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -m pytest tools/binrecon -q
```

Expected: all pass — Task 1 added tooling, so this guards against having broken it.

- [ ] **Step 5: Write the acceptance record**

Add a `## Acceptance` section to `divergences.md` with the output of every command in Step 4, the final bucket counts, and the status histogram. Where a spec expectation was not met — the mapped count of Step 2 being the likely case — state the actual result and why, not the expectation.

- [ ] **Step 6: Commit**

```bash
cd /d/RhapsodiOS && git add src/drvSCSIServer/reconstruction && git commit -m "drvSCSIServer: regenerate the reconstruction artifacts and record acceptance"
```

---

## Self-Review Notes

- Spec coverage: §1.2 starting state → Task 2 Step 3; §2.1/§2.2 MiG evidence → Task 7 Step 1 and Task 9; §2.3 PIC misreading → Task 7 Step 2; §2.4 absent/misnamed/invented → Tasks 7, 8, 10, 11; §2.5 translation units → Task 10; §2.6 wrappers stay → Task 5 and Task 9 Step 3; §3.1 two phases → the Phase 1/Phase 2 split with Task 7 as the boundary commit; §3.2 tooling facts → Global Constraints and Task 2; §3.3 address-0 gap → Task 2 Step 5; §3.4 target tree → Tasks 9–11; §3.5 ledger vocabulary → Task 3 Step 2; §3.6 build wiring → Task 9 Step 4; §4.1 no compile verification → Global Constraints; §4.2 acceptance → Task 13.
- Writing this plan found a defect in the spec: acceptance criterion 2 originally said "66 mapped, 2 unmapped", which is unreachable because `source-map` needs a source site on disk and MiG cannot run here to generate one for the 18 server stubs. The spec has been corrected to 48/20 with the reason, and Task 13 Step 2 states the same numbers, so plan and spec now agree.
- Contingent-content warning: Task 12 has no enumerable step list by construction, since its input is Phase 1's findings. Its procedure, gates and definition of done are fully specified; do not treat the absent list as a placeholder to fill in at plan time.
- Ledger addresses used as keys across tasks (16, 36, 228, 480, 632, 772; 1160; 1604, 1620, 1676, 1732, 2076, 2092, 2196, 2388, 2544, 2672; the 3028–6388 wrapper block; 6460–8988 plumbing; 9212–13376 MiG stubs; 13520 demux; 13708, 13728 build-generated) all come from the same measured map, so a later task's `--address` always names an entry an earlier task created.
