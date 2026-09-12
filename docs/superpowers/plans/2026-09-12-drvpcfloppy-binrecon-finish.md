# drvPCFloppy binrecon finish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make name-paired `masked_equal` trustworthy, re-baseline `drvPCFloppy` after a guest rebuild, then take each class to byte identity or a recorded accept, with layout as a required step.

**Architecture:** Phase 0 changes only `binrecon`'s comparator: name-paired functions compare concatenated per-instruction bytes after each side's relocation fields are zeroed independently. Offset-paired functions keep envelope comparison. Phase 1 is a user guest build plus `function-worklist.md`. Later tasks follow the Class cycle below, in hierarchy order.

**Tech Stack:** Python 3.13, pytest, IDA 9.2 via `tools/binrecon`, Objective-C DriverKit on a Rhapsody guest. Interpreter: `./.venv-binrecon/Scripts/python.exe` with `PYTHONPATH=tools/binrecon`.

**Spec:** [2026-09-12-drvpcfloppy-binrecon-finish-design.md](../specs/2026-09-12-drvpcfloppy-binrecon-finish-design.md)

## File map

| File | Responsibility |
|---|---|
| `tools/binrecon/binrecon/compare.py` | Pairing-aware equality. Name-paired: instruction-stream masks. Offset-paired: envelope masks. |
| `tools/binrecon/tests/test_compare.py` | Phase 0 tests. |
| `src/drivers-i386/ide/drvPCFloppy/reconstruction/function-worklist.md` | Baseline and per-class close summaries. |
| `src/drivers-i386/ide/drvPCFloppy/reconstruction/divergences.md` | Accepts. |
| `src/drivers-i386/ide/drvPCFloppy/reconstruction/ledger.json` | Per-function status of record. |
| `src/drivers-i386/ide/drvPCFloppy/reconstruction/source-map.json` | Function → file/line. |
| `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/*.m` / `*.h` | Class currently open only. |

## Global constraints

- **You cannot build the driver.** The user runs `vm/build-i386-floppy.sh` on the Rhapsody guest. Never claim a driver-side result a build has not produced.
- **Task 3 is a user gate.** Do not start Task 4 or later without `function-worklist.md` from that rebuild.
- **Another agent commits to this repository.** Stage by explicit path. Never `git add -A`. Never `git commit -a`.
- **Commit messages:** `binrecon: ` or `drvPCFloppy: `, one to two lines, no metadata, no trailers, no `Co-Authored-By`.
- **Tests:** `PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q` — judge the delta, not the absolute count.
- **Reference:** `C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc`
- **Rebuilt:** `D:/RhapsodiOS/out/i386/drvPCFloppy/Floppy.config/Floppy_reloc` (in a worktree, use that worktree's `out/` path)
- **Profile:** `tools/binrecon/profiles/floppy.json`
- **TDD for Task 1.** No production code before a failing test.
- **Do not invent instruction diffs.** After Phase 1, every source edit comes from `binrecon function --name` of a named function. If the dump is not in hand, stop.

## Class cycle (Tasks 4–12)

Parameter: `CLASS`, `FILES` (the headers and `.m` files that class owns), `LAYOUT` (skip | confirm | rebuild).

1. Read `function-worklist.md` and the current `--list`. Keep rows whose names belong to `CLASS`.
2. If `LAYOUT` is not skip: dump Apple's `__OBJC` instance size and ivar offsets for `CLASS` from the reference `Floppy_reloc`. Diff against our header. Rewrite that class's ivars so size and offsets match. Do not insert padding or unused ivars the reference does not have. If source cannot match, accept the gap in `divergences.md` and continue.
3. If `LAYOUT` is rebuild: ask the user to build, then `binrecon analyze` and refresh `--list`. Instance size must equal Apple's (or the gap is accepted) before function chasing.
4. Function step: cheapest remaining `differing` in `CLASS` first. One shared cause is one edit cluster in `FILES` only. Ask the user to build after a cluster. Confirm each claimed win with `--name` on the new published comparison (`raw_equal` or `masked_equal`).
5. Stop the class when the cheapest remaining row is register allocation or instruction scheduling. Write the `--name` dump into `divergences.md` with disposition accept. Set `intentional-mismatch` plus reason and reviewer on those ledger entries.
6. Update `source-map.json` line numbers for bodies you moved. Append a class-close summary to `function-worklist.md`. Commit with `drvPCFloppy: `.

Compiler-shaped means: the `--name` columns differ only by register choice, instruction scheduling, or equivalent gcc 2.x shape, not by a wrong constant, missing call, inverted branch, or wrong offset.

---

### Task 1: Name-paired masked equality

**Files:**
- Modify: `tools/binrecon/binrecon/compare.py` (`_compare_function_range`, `_compare_functions`)
- Test: `tools/binrecon/tests/test_compare.py`

No driver source. No profile change.

- [ ] **Step 1: Write the failing tests**

Append to `tools/binrecon/tests/test_compare.py` after `test_name_paired_functions_of_unequal_size`:

```python
def test_name_paired_functions_mask_relocated_immediates_independently(tmp_path):
    """Same call, different displacement and target offset, paired by name.

    Offset-paired masking already zeros fields whose portable semantics match.
    Independently linked binaries never match those semantics, which is why
    floppy's eight identical-stream functions still report masked_equal False.
    """
    reference = bytearray(b"\x90" * 64)
    rebuilt = bytearray(b"\x90" * 64)
    reference[0:5] = b"\xe8\x78\x56\x34\x12"
    rebuilt[16:21] = b"\xe8\x11\x11\x11\x11"
    rp, bp, left, right = _case(tmp_path, bytes(reference), bytes(rebuilt))

    def place(document, offset, displacement_hex, callee_offset):
        address = 0x1000 + offset
        document["sections"][0].update(
            size=64, sha256=hashlib.sha256(Path(document["input"]["path"]).read_bytes()).hexdigest())
        document["symbols"] = [{"name": "callee", "address": 0x1000 + callee_offset,
                                "binding": "global", "section": ".text"}]
        document["relocations"] = [{"address": address + 1,
                                    "kind": "i386-vanilla-32-pc-relative",
                                    "target": "callee", "addend": -4}]
        document["functions"] = [{
            "address": address, "size": 5, "names": ["alpha"],
            "blocks": [{"address": address, "size": 5, "successors": []}],
            "instructions": [{"address": address, "bytes": "E8" + displacement_hex,
                              "mnemonic": "call", "operands": "callee",
                              "normalized_operands": "callee", "relocations": [0]}],
            "calls": [{"address": address, "target": 0x1000 + callee_offset, "name": "callee"}],
            "confidence": 1.0}]
        document["references"] = [{"address": address, "target": 0x1000 + callee_offset,
                                   "kind": "call"}]
        document["extensions"] = {"macho": {"relocations": [
            {"address": address + 1, "target": "callee", "width": 4}]}}

    place(left, 0, "78563412", 0x20)
    place(right, 16, "11111111", 0x30)

    report = compare_artifacts(rp, bp, left, right, "normalized-functions")

    validate_comparison_report(report)
    record = report["functions"][0]
    assert record["pairing"] == "name"
    assert record["raw_equal"] is False
    assert record["masked_equal"] is True


def test_name_paired_functions_ignore_envelope_padding(tmp_path):
    """Listed instructions match; trailing envelope bytes do not.

    Envelope comparison is for offset-paired functions. Name-paired equality
    is the instruction stream.
    """
    reference = bytearray(b"\x90" + b"\xcc" * 7 + b"\x90" * 56)
    rebuilt = bytearray(b"\x90" * 16 + b"\x90" + b"\xdd" * 7 + b"\x90" * 40)
    rp, bp, left, right = _case(tmp_path, bytes(reference), bytes(rebuilt))
    section = {"name": ".text", "address": 0x1000, "offset": 0, "size": 64,
               "permissions": "rx", "sha256": hashlib.sha256(bytes(reference)).hexdigest()}
    right_section = dict(section)
    right_section["sha256"] = hashlib.sha256(bytes(rebuilt)).hexdigest()

    def function(offset, size):
        address = 0x1000 + offset
        return {"address": address, "size": size, "names": ["alpha"],
                "blocks": [{"address": address, "size": size, "successors": []}],
                "instructions": [{"address": address, "bytes": "90", "mnemonic": "nop",
                                  "operands": "", "normalized_operands": "",
                                  "relocations": []}],
                "calls": [], "confidence": 1.0}

    left["sections"] = [section]
    right["sections"] = [right_section]
    left["functions"] = [function(0, 8)]
    right["functions"] = [function(16, 8)]
    for document in (left, right):
        document["symbols"] = []
        document["relocations"] = []
        document["references"] = []
        document["extensions"] = {}

    report = compare_artifacts(rp, bp, left, right, "normalized-functions")

    validate_comparison_report(report)
    record = report["functions"][0]
    assert record["pairing"] == "name"
    assert record["raw_equal"] is True
    assert record["masked_equal"] is True
```

Add `from pathlib import Path` at the top of `test_compare.py` if it is not already imported. Prefer `tmp_path` files already written by `_case`: use `rp.read_bytes()` inside `place` instead of `Path(document["input"]["path"])` if that is simpler — then drop the Path import. The `place` helper must hash the bytes `_case` already wrote.

- [ ] **Step 2: Run the new tests and confirm they fail**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_compare.py::test_name_paired_functions_mask_relocated_immediates_independently tools/binrecon/tests/test_compare.py::test_name_paired_functions_ignore_envelope_padding -q
```

Expected: both FAIL. The relocation test fails on `masked_equal is True` (it is False). The padding test fails the same way. If either test errors on normalize (relocation ownership, analyzer bytes), fix the *test fixture* until the assertion is a failed `masked_equal`, not a `ComparisonError`. Do not change `compare.py` yet.

- [ ] **Step 3: Implement name-paired instruction-stream comparison**

In `tools/binrecon/binrecon/compare.py`:

Add this function immediately above `_compare_function_range`:

```python
def _compare_name_paired_instructions(left_instructions, right_instructions,
                                      left_map, right_map, printable, section):
    def stream(instructions, section_map):
        raw = bytearray(); masked = bytearray()
        for instruction, actual, _ in instructions:
            raw.extend(actual)
            masked.extend(_masked(instruction, actual, section_map)[0])
        return bytes(raw), bytes(masked)

    left_raw, left_masked = stream(left_instructions, left_map)
    right_raw, right_masked = stream(right_instructions, right_map)
    evidence = None
    if left_masked != right_masked:
        width = max(len(left_masked), len(right_masked))
        left_pad = left_masked.ljust(width, b"\0")
        right_pad = right_masked.ljust(width, b"\0")
        index = next((i for i, (a, b) in enumerate(zip(left_pad, right_pad)) if a != b),
                     min(len(left_masked), len(right_masked)))
        end = index + 1
        while end < width and left_pad[end] != right_pad[end]:
            end += 1
        evidence = _instruction_evidence(
            "function-range", "code", "function range bytes differ", printable, section,
            index, end, left_masked[index:index + 32].hex().upper(),
            right_masked[index:index + 32].hex().upper())
    return {"raw_equal": left_raw == right_raw, "masked_equal": left_masked == right_masked,
            "reference_sha256": hashlib.sha256(left_raw).hexdigest().upper(),
            "rebuilt_sha256": hashlib.sha256(right_raw).hexdigest().upper(),
            "reference_masked_sha256": hashlib.sha256(left_masked).hexdigest().upper(),
            "rebuilt_masked_sha256": hashlib.sha256(right_masked).hexdigest().upper(),
            "evidence": evidence}
```

Change `_compare_function_range` to take `pairing` and dispatch:

```python
def _compare_function_range(left_function, right_function, left_instructions, right_instructions,
                            left_map, right_map, pair, printable, pairing):
    if pairing == "name":
        return _compare_name_paired_instructions(
            left_instructions, right_instructions, left_map, right_map, printable,
            _section_tag(left_function["range"]["section"], left_map))
```

Leave the rest of `_compare_function_range` unchanged after that early return.

In `_compare_functions`, pass `pairing` into the call:

```python
            range_result = _compare_function_range(a, b, ai, bi, left_map, right_map, pair, printable,
                                                   pairing)
```

Do not change the offset-paired envelope path, `_function_masks`, or `_apply_masks`.

- [ ] **Step 4: Run the two new tests and confirm they pass**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_compare.py::test_name_paired_functions_mask_relocated_immediates_independently tools/binrecon/tests/test_compare.py::test_name_paired_functions_ignore_envelope_padding tools/binrecon/tests/test_compare.py::test_name_paired_functions_of_unequal_size tools/binrecon/tests/test_compare.py::test_uniquely_named_functions_at_different_offsets tools/binrecon/tests/test_compare.py::test_relocation_field_difference_is_not_code_difference tools/binrecon/tests/test_compare.py::test_unlisted_function_gap_bytes_are_artifact_authoritative -q
```

Expected: 6 passed. Unequal-size name pairs still have `masked_equal` False and `instruction shape differs`. Offset-paired relocation masking and unlisted-gap authority still hold.

- [ ] **Step 5: Run the whole binrecon suite**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```

Expected: 2 more passed than before this task, nothing failing.

- [ ] **Step 6: Commit**

```bash
git add tools/binrecon/tests/test_compare.py tools/binrecon/binrecon/compare.py
git commit -m "binrecon: mask name-paired functions from their instruction streams"
```

---

### Task 2: Prove the eight floppy rows, if published output exists

**Files:** none modified unless the proof fails, in which case return to Task 1 (do not start driver edits).

- [ ] **Step 1: Look for published output**

From the repository root (or worktree root):

```bash
./.venv-binrecon/Scripts/python.exe -c "from pathlib import Path; p=Path('tools/binrecon/profiles/../out/floppy/published'); print(p.resolve()); print('yes' if p.is_dir() else 'no'); print(list(p.glob('comparison-*.json')) if p.is_dir() else '')"
```

If `no`, record that in the task report and skip to Task 3. Phase 1's first `--list` is then the proof.

- [ ] **Step 2: If published output exists, list the eight**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc" \
BINRECON_REBUILT="D:/RhapsodiOS/out/i386/drvPCFloppy/Floppy.config/Floppy_reloc" \
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon function --profile tools/binrecon/profiles/floppy.json --list
```

On Windows PowerShell, set `$env:BINRECON_REFERENCE` and `$env:BINRECON_REBUILT` instead of the `\` continuations.

Find these four (and the other four that had `differing == 0` with `raw_equal` False):

- `+[FloppyKernelServerInstance kernelServerInstance]`
- `-[IODiskNEW eject]`
- `-[IODiskNEW lockLogicalDisks]`
- `-[IODiskPartitionNEW setBlockDeviceOpen:]`

Expected: flags column `masked-eq` or `identical`. If still empty flags with `differing` 0, Phase 0 is not done — go back to Task 1 with the real `--name` dump of one of those four as the new failing fixture. Do not edit the driver.

- [ ] **Step 3: Commit nothing if there is no file change.** If you had to extend tests in Task 1's files, commit on that same pair of paths with `binrecon: `.

---

### Task 3: Guest rebuild and worklist

**This task requires the user to build.** Ask, and wait. Do not report driver-side numbers before the new `Floppy_reloc` exists.

**Files:**
- Create: `src/drivers-i386/ide/drvPCFloppy/reconstruction/function-worklist.md`

- [ ] **Step 1: Ask the user to build**

Tell them `drvPCFloppy` needs building via `vm/build-i386-floppy.sh`. This is the first compile of the invented-symbol commits plus inheritance changes. A failure may originate outside this campaign. Wait.

- [ ] **Step 2: Validate and analyze**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc"
BINRECON_REBUILT="<repo-or-worktree>/out/i386/drvPCFloppy/Floppy.config/Floppy_reloc"
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon validate --profile tools/binrecon/profiles/floppy.json
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon analyze --profile tools/binrecon/profiles/floppy.json
```

Expected validate: two lines `reference …` and `rebuilt …` with size and sha256, exit 0. Expected analyze: `analysis complete; analyzers=1 comparisons=1 normalized-functions=FAIL` (~10 minutes). If normalize errors, report the named artifact, analyzer, and instruction; do not work around it.

- [ ] **Step 3: Produce the worklist**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon function --profile tools/binrecon/profiles/floppy.json --list
```

Expected: a table ending in `N functions: X byte-identical, Y differing, Z unpaired`.

- [ ] **Step 4: Spot-check `--name`**

Pick the first row whose `diff` is not `0` and whose flags are not `identical` / `masked-eq`. Run `--name` with that exact name. Confirm the `*` count equals that row's `diff`.

- [ ] **Step 5: Write `function-worklist.md`**

Include: date; both SHA-256 and sizes; the summary line; comparison against the stale 2026-07-26 baseline (230 compared, 49 byte-identical, 174 differing, 5 ours-only, 2 reference-only); whether `isAnyOtherOpen`, `_queueEmpty`, `_dequeueOperation`, `_appendOperationToQueue` are gone; per-class counts of still-differing functions; the full `--list` table; a heading `## Is this reachable?` answering whether the cheapest twenty rows are source-controlled or compiler-shaped.

If the eight masking rows are not `masked-eq` / `identical` on this fresh analysis, stop the campaign and return to Task 1. This rebuild's only job in that case is to re-prove masking.

- [ ] **Step 6: Commit**

```bash
git add src/drivers-i386/ide/drvPCFloppy/reconstruction/function-worklist.md
git commit -m "drvPCFloppy: record the post-rebuild function baseline and worklist"
```

---

### Task 4: Shared layout for IODiskNEW, IODriveNEW, IOLogicalDiskNEW

**Files:**
- Modify only if the reference `__OBJC` layouts disagree with:
  - `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/IODiskNew.h`
  - `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/IODriveNEW.h`
  - `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/IOLogicalDiskNEW.h`
- Possibly: matching `.m` files if ivar uses must move with the header

`LAYOUT=rebuild` once for all three. Do not chase functions in this task.

- [ ] **Step 1:** Dump Apple's instance sizes and ivar offsets for the three classes from the reference. Diff against the three headers. These classes were already aligned once; this step confirms they still match after the invented-symbol work.
- [ ] **Step 2:** If they already match, write that fact into `function-worklist.md` under `## Base class layout` and skip the rebuild. If they do not, edit only those headers (and `.m` uses that the move requires), then ask the user to build, re-analyze, and confirm instance sizes.
- [ ] **Step 3:** Commit only if source or the worklist changed: `drvPCFloppy: confirm base class instance layouts against the reference`

---

### Task 5: IODiskNEW functions

**Files:** `IODiskNew.m`, `IODiskNew.h`, `kernelDiskMethodsNEW.m` / `.h` for methods this class owns.

`CLASS=IODiskNEW`, `LAYOUT=skip` (Task 4 did it), then the Class cycle function steps 4–6.

- [ ] Execute the function half of the Class cycle for `IODiskNEW`.
- [ ] Commit when the class is identical or accepted.

---

### Task 6: IODriveNEW functions

**Files:** `IODriveNEW.m`, `IODriveNEW.h`.

`CLASS=IODriveNEW`, `LAYOUT=skip`.

- [ ] Execute the function half of the Class cycle for `IODriveNEW`.
- [ ] Commit when the class is identical or accepted.

---

### Task 7: IOLogicalDiskNEW functions

**Files:** `IOLogicalDiskNEW.m`, `IOLogicalDiskNEW.h`.

`CLASS=IOLogicalDiskNEW`, `LAYOUT=skip`.

- [ ] Execute the function half of the Class cycle for `IOLogicalDiskNEW`.
- [ ] Commit when the class is identical or accepted.

---

### Task 8: IODiskPartitionNEW

**Files:** `IODiskPartitionNEW.m`, `IODiskPartitionNEW.h`.

`CLASS=IODiskPartitionNEW`, `LAYOUT=rebuild`.

- [ ] Execute the full Class cycle.
- [ ] Commit when the class is identical or accepted.

---

### Task 9: IOFloppyDisk

**Files:** `IOFloppyDisk.m`, `IOFloppyDisk.h`, `Geometry.m`, `Geometry.h`, `Request.m`, `Request.h`, `Thread.m`, `Thread.h`, `Support.m`, `Support.h`.

`CLASS=IOFloppyDisk`, `LAYOUT=rebuild`.

- [ ] Execute the full Class cycle.
- [ ] Commit when the class is identical or accepted.

---

### Task 10: IOFloppyDrive

**Files:** `IOFloppyDrive.m`, `IOFloppyDrive.h`, `FloppyDriveInt.m`, `FloppyDriveInt.h`, `FloppyDriveInt2.m`, `FloppyDriveInt2.h`, `VolCheck.m`, `VolCheck.h`.

`CLASS=IOFloppyDrive`, `LAYOUT=rebuild`.

Known layout debt, to be confirmed against `__OBJC` rather than trusted blindly: our instance size is 424 vs Apple 444; `lastAccess` is last in the header and belongs at `+368`. Move it to the reference offset and add the missing ivars the reference actually has. Do not invent names for bytes the metadata does not name — use the reference ivar names.

- [ ] Execute the full Class cycle.
- [ ] Commit when the class is identical or accepted.

---

### Task 11: FloppyController

**Files:** `FloppyCnt.m`, `FloppyCnt.h`, `FloppyCntIo.m`, `FloppyCntIo.h`, `FloppyCmds.m`, `FloppyCmds.h`, `FloppyArch.m`, `FloppyArch.h`.

`CLASS=FloppyController`, `LAYOUT=rebuild`.

Do this after Task 10. `_fcUnitNum` already exists in `FloppyCnt.m`; layout still has to match Apple's instance size and ivar offsets.

- [ ] Execute the full Class cycle.
- [ ] Commit when the class is identical or accepted.

---

### Task 12: BSD helpers

**Files:** `Bsd.m`, `Bsd.h`.

`CLASS` names: `_HandleBsdOpen`, `_HandleBsdClose`, `_HandleBsdRead`, `_HandleBsdWrite`, `_fakeStrategySuccess`. `LAYOUT=skip`.

- [ ] Function cycle only for those five names (and any other `Bsd.m` functions still differing that these five share a cause with — still `Bsd.m` only).
- [ ] Commit when they are identical or accepted.

---

### Task 13: Campaign close

**Files:** `function-worklist.md`, `divergences.md`, `ledger.json`, `src/drivers-i386/README` (only if a factual line is stale; do not claim hardware testing).

- [ ] Run `--list`. Unpaired must be only `__udivdi3` and the two `kl_ld` glue names, or an accept that names any new unpaired symbol.
- [ ] Every other row `identical`, `masked-eq`, or accepted in `divergences.md` with ledger `intentional-mismatch`.
- [ ] `missing_symbols` still `__udivdi3` only. Strings and imports must not have regressed.
- [ ] `ledger.json` has no `unexamined` hand-written function.
- [ ] Commit `drvPCFloppy: close the binrecon function-parity campaign`

---

## Plan self-review

**Spec coverage:** Phase 0 → Task 1–2. Phase 1 → Task 3. Shared base layout → Task 4. Per-class function parity → Tasks 5–7. Remaining classes → Tasks 8–11. BSD → Task 12. Done bar / campaign close → Task 13. Error handling is in Global constraints and the Class cycle. Masking required behaviour is the Task 1 implementation. Excluded items have no tasks.

**Placeholders:** None. Class tasks cannot include the C bodies of unknown diffs; they bind the implementer to `--name` dumps after Task 3.

**Types:** `_compare_function_range(..., pairing)` and `_compare_name_paired_instructions` are named consistently across Task 1 steps.
