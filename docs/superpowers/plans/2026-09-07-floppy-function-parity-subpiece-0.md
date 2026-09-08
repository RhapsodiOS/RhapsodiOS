# drvPCFloppy Function Parity, Sub-piece 0 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a trustworthy per-function baseline for `drvPCFloppy` and the tooling to query it, so the reconstruction campaign that follows is driven by evidence instead of stale numbers.

**Architecture:** A new `binrecon function` subcommand reads output that `binrecon analyze` has already published — the per-function instruction lists are in there — so querying any function is instant and needs no analyzer run. `--list` ranks every function by how many instructions differ, cheapest first; `--name` prints one function's two instruction sequences side by side. The driver's profile is repaired to IDA-only, since angr and Ghidra both fail on it. Finally the user builds, the baseline is re-measured, and the worklist is recorded.

**Tech Stack:** Python 3.13, argparse, difflib, pytest. binrecon lives at `tools/binrecon/`; its interpreter is `./.venv-binrecon/Scripts/python.exe` and its tests run with `PYTHONPATH=tools/binrecon`.

**Spec:** [2026-09-07-floppy-function-parity-design.md](../specs/2026-09-07-floppy-function-parity-design.md)

## Global Constraints

- **This sub-piece changes no driver source.** It touches `tools/binrecon/`, one
  profile, and documentation under
  `src/drivers-i386/ide/drvPCFloppy/reconstruction/`. No `.m`, `.h` or `.c` file
  in any driver may be modified.
- **You cannot build the driver.** The build runs on a Rhapsody guest and only the user can do it. Task 3 is the sole build gate. Never claim a driver-side result that a build has not produced.
- **The binrecon suite must stay green.** It stands at **905 passed, 4 skipped**. Another agent adds tests concurrently, so judge the delta, not the absolute number.
- Run tests with: `PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q`
- **Another agent commits to this repository.** Stage only your own files by explicit path. Never `git add -A`, never `git commit -a`.
- **Commit messages:** short, `binrecon: ` prefixed (or `drvPCFloppy: ` for the profile), one to two lines, no metadata, no trailers, no `Co-Authored-By`.
- **Published output layout**, produced by `binrecon analyze` under a profile's `output_dir`:
  `published/analysis-reference-<analyzer>.json`, `published/analysis-rebuilt-<analyzer>.json`, `published/comparison-<analyzer>.json`.
- **Analysis function records** carry: `address`, `size`, `names` (list), `blocks`, `calls`, `confidence`, and `instructions`, where each instruction has `address`, `bytes`, `mnemonic`, `operands`, `normalized_operands`, `relocations`.
- **Comparison function records** carry: `key`, `status`, `pairing`, `reasons`, `reference_aliases`, `rebuilt_aliases`, `raw_equal`, `masked_equal`, `semantics_equal`, `cfg_equal`, `calls_equal`, and the four sha256 fields.

---

### Task 1: Repair the drvPCFloppy profile

`floppy.json` enables three analyzers. Two of them fail on this driver, so every run of the committed profile aborts.

**Files:**
- Modify: `tools/binrecon/profiles/floppy.json`
- Create: `src/drivers-i386/ide/drvPCFloppy/reconstruction/analyzer-notes.md`

- [ ] **Step 1: Confirm the current state**

Run, from the repository root:

```bash
./.venv-binrecon/Scripts/python.exe -c "
import json
p=json.load(open('tools/binrecon/profiles/floppy.json'))
for k,v in p['analyzers'].items(): print(k, v['enabled'])
print('output_dir:', p['output_dir'])
"
```

Expected: `ida True`, `ghidra False`, `angr True`, `output_dir: ../out/floppy`.

- [ ] **Step 2: Disable angr and record why**

Set `analyzers.angr.enabled` to `false`. Leave `ghidra` disabled. Leave IDA enabled and every other field untouched, including `output_dir`.

JSON has no comments and `profile-v1.json` sets `additionalProperties: false`, so a `_comment` key would fail validation. `name` is an unconstrained string and is the only free-text field, so change it from `"drvPCFloppy reconstruction"` to exactly:

```
drvPCFloppy reconstruction (IDA only; see reconstruction/analyzer-notes.md)
```

Then create `src/drivers-i386/ide/drvPCFloppy/reconstruction/analyzer-notes.md` holding the reasoning, so the next person does not re-derive it:

```markdown
# Why binrecon runs IDA only on this driver

Both other analyzers fail, for unrelated reasons. Neither failure is a defect in
the driver, and both were diagnosable only after binrecon's normalizer was taught
to name the artifact, analyzer and instruction in its errors.

**angr mis-decodes our binary.** At `0x27` it reports a one-byte
`lodsd eax, dword ptr [esi]`, but relocation 0 covers `0x27..0x2b` — four bytes,
`i386-vanilla-32-pc-relative`. angr began decoding inside a `call`/`jmp rel32`
that starts at `0x26`, so the relocation no longer lies within the instruction it
belongs to and normalization refuses it.

**Ghidra cannot attribute relocations to operands.** At `0x3ab8` in the
*reference*, `CMP dword ptr [0x00000000], EDI` carries a relocation targeting
`_page_size`. Ghidra leaves the operand unrelocated and prints no symbol, so
binrecon's textual owner-matching finds zero candidates among
`['dword ptr [0x00000000]', 'EDI']` and reports the ownership as ambiguous.

Fixing either adapter is out of scope. Re-enable them only with evidence that
the underlying behaviour has changed.
```

- [ ] **Step 3: Verify the profile still validates**

Run, from the repository root:

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc" \
BINRECON_REBUILT="D:/RhapsodiOS/out/i386/drvPCFloppy/Floppy.config/Floppy_reloc" \
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon validate --profile tools/binrecon/profiles/floppy.json
```

Expected: two lines, one beginning `reference ` and one beginning `rebuilt `, each with a `size=` and `sha256=`. Exit code 0.

- [ ] **Step 4: Commit**

```bash
git add tools/binrecon/profiles/floppy.json src/drivers-i386/ide/drvPCFloppy/reconstruction/analyzer-notes.md
git commit -m "drvPCFloppy: run binrecon with IDA only, recording why the others fail"
```

---

### Task 2: The `binrecon function` subcommand

Delivers both modes together. `--list` ranks every compared function by how many instructions differ; `--name` prints one function's two instruction sequences side by side.

**Files:**
- Create: `tools/binrecon/binrecon/functions.py`
- Modify: `tools/binrecon/binrecon/cli.py`
- Test: `tools/binrecon/tests/test_functions.py`

**Interfaces produced** (Task 3 reads the output, not the API):
- `FunctionQueryError(ValueError)`
- `load_published(output_dir: Path, analyzer: str) -> tuple[dict, dict, dict]` returning `(reference_analysis, rebuilt_analysis, comparison)`
- `function_index(analysis: dict) -> dict[str, dict]` mapping every name in each function's `names` list to that function record
- `instruction_pairs(function: dict) -> list[tuple[str, str]]` returning `(mnemonic, normalized_operands)` per instruction
- `differing_count(reference_function: dict | None, rebuilt_function: dict | None) -> int | None`
- `worklist(reference: dict, rebuilt: dict, comparison: dict) -> list[dict]` with row keys `name`, `status`, `raw_equal`, `masked_equal`, `differing`, `reference_instructions`, `rebuilt_instructions`, `reasons`
- `render_worklist(rows: list[dict]) -> str`
- `render_function(name: str, reference_function: dict | None, rebuilt_function: dict | None, record: dict | None) -> str`

- [ ] **Step 1: Write the failing tests**

Create `tools/binrecon/tests/test_functions.py`:

```python
import json
from pathlib import Path

import pytest

from binrecon.functions import (
    FunctionQueryError, differing_count, function_index, instruction_pairs,
    load_published, render_worklist, worklist,
)


def _function(name, mnemonics, address=0x1000):
    return {
        "address": address,
        "size": len(mnemonics) * 2,
        "names": [name],
        "blocks": [],
        "calls": [],
        "confidence": 1.0,
        "instructions": [
            {"address": address + index * 2, "bytes": "90", "mnemonic": mnemonic,
             "operands": "", "normalized_operands": operands, "relocations": []}
            for index, (mnemonic, operands) in enumerate(mnemonics)
        ],
    }


def _analysis(functions):
    return {"schema_version": "analysis-v1", "functions": functions}


def _comparison(rows):
    return {"functions": rows}


def test_function_index_maps_every_alias():
    fn = _function("one", [("push", "ebp")])
    fn["names"].append("also_one")

    index = function_index(_analysis([fn]))

    assert index["one"] is fn
    assert index["also_one"] is fn


def test_instruction_pairs_uses_mnemonic_and_normalized_operands():
    fn = _function("f", [("mov", "eax, ebx"), ("ret", "")])

    assert instruction_pairs(fn) == [("mov", "eax, ebx"), ("ret", "")]


def test_differing_count_is_zero_for_identical_sequences():
    left = _function("f", [("push", "ebp"), ("ret", "")])
    right = _function("f", [("push", "ebp"), ("ret", "")], address=0x2000)

    assert differing_count(left, right) == 0


def test_differing_count_counts_only_changed_instructions():
    left = _function("f", [("push", "ebp"), ("mov", "eax, 1"), ("ret", "")])
    right = _function("f", [("push", "ebp"), ("mov", "eax, 2"), ("ret", "")])

    assert differing_count(left, right) == 1


def test_differing_count_is_none_when_a_side_is_missing():
    assert differing_count(_function("f", [("ret", "")]), None) is None
    assert differing_count(None, _function("f", [("ret", "")])) is None


def test_worklist_sorts_by_differing_count_ascending_with_unpaired_last():
    reference = _analysis([
        _function("far", [("a", ""), ("b", ""), ("c", "")]),
        _function("near", [("a", ""), ("b", "")]),
        _function("gone", [("a", "")]),
    ])
    rebuilt = _analysis([
        _function("far", [("x", ""), ("y", ""), ("z", "")]),
        _function("near", [("a", ""), ("q", "")]),
    ])
    comparison = _comparison([
        {"status": "different", "reference_aliases": ["far"], "rebuilt_aliases": ["far"],
         "raw_equal": False, "masked_equal": False, "reasons": ["instruction shape differs"]},
        {"status": "different", "reference_aliases": ["near"], "rebuilt_aliases": ["near"],
         "raw_equal": False, "masked_equal": False, "reasons": ["instruction shape differs"]},
        {"status": "missing-rebuilt", "reference_aliases": ["gone"], "rebuilt_aliases": [],
         "raw_equal": False, "masked_equal": False, "reasons": ["missing rebuilt function"]},
    ])

    rows = worklist(reference, rebuilt, comparison)

    assert [row["name"] for row in rows] == ["near", "far", "gone"]
    assert rows[0]["differing"] == 1
    assert rows[1]["differing"] == 3
    assert rows[2]["differing"] is None


def test_worklist_reports_instruction_counts_and_equality_flags():
    reference = _analysis([_function("f", [("a", ""), ("b", "")])])
    rebuilt = _analysis([_function("f", [("a", ""), ("b", "")])])
    comparison = _comparison([
        {"status": "different", "reference_aliases": ["f"], "rebuilt_aliases": ["f"],
         "raw_equal": True, "masked_equal": True, "reasons": ["cfg differs"]},
    ])

    row = worklist(reference, rebuilt, comparison)[0]

    assert row["raw_equal"] is True
    assert row["reference_instructions"] == 2
    assert row["rebuilt_instructions"] == 2
    assert row["differing"] == 0


def test_render_worklist_marks_byte_identical_rows():
    rows = [
        {"name": "same", "status": "different", "raw_equal": True, "masked_equal": True,
         "differing": 0, "reference_instructions": 2, "rebuilt_instructions": 2,
         "reasons": ["cfg differs"]},
        {"name": "other", "status": "different", "raw_equal": False, "masked_equal": False,
         "differing": 4, "reference_instructions": 9, "rebuilt_instructions": 9,
         "reasons": ["instruction shape differs"]},
    ]

    text = render_worklist(rows)

    assert "same" in text and "other" in text
    assert "identical" in text
    assert text.index("same") < text.index("other")


def test_load_published_reports_a_missing_directory_by_path(tmp_path):
    with pytest.raises(FunctionQueryError) as error:
        load_published(tmp_path / "nowhere", "ida")

    assert str(tmp_path / "nowhere") in str(error.value)


def test_render_function_marks_differing_rows_and_keeps_equal_ones_unmarked():
    from binrecon.functions import render_function

    left = _function("f", [("push", "ebp"), ("mov", "eax, 1"), ("ret", "")])
    right = _function("f", [("push", "ebp"), ("mov", "eax, 2"), ("ret", "")])
    record = {"status": "different", "raw_equal": False, "masked_equal": False,
              "reasons": ["instruction shape differs"]}

    text = render_function("f", left, right, record)

    lines = [line for line in text.splitlines() if "mov" in line]
    assert lines and all(line.startswith("*") for line in lines)
    assert any(line.startswith(" ") and "push" in line for line in text.splitlines())
    assert "eax, 1" in text and "eax, 2" in text


def test_render_function_shows_the_verdict_and_reasons():
    from binrecon.functions import render_function

    fn = _function("f", [("ret", "")])
    record = {"status": "different", "raw_equal": True, "masked_equal": True,
              "reasons": ["cfg differs"]}

    text = render_function("f", fn, fn, record)

    assert "raw_equal=True" in text
    assert "cfg differs" in text


def test_render_function_handles_a_missing_side():
    from binrecon.functions import render_function

    fn = _function("f", [("ret", "")])
    record = {"status": "missing-rebuilt", "raw_equal": False, "masked_equal": False,
              "reasons": ["missing rebuilt function"]}

    text = render_function("f", fn, None, record)

    assert "missing" in text
    assert "ret" in text


def test_render_function_rejects_an_unknown_name():
    from binrecon.functions import FunctionQueryError, render_function

    with pytest.raises(FunctionQueryError) as error:
        render_function("nope", None, None, None)

    assert "nope" in str(error.value)


def test_parser_accepts_function_list_and_name():
    from binrecon.cli import build_parser

    listed = build_parser().parse_args(["function", "--profile", "p.json", "--list"])
    named = build_parser().parse_args(["function", "--profile", "p.json", "--name", "f"])

    assert listed.list_functions is True and listed.name is None
    assert named.list_functions is False and named.name == "f"
    assert listed.analyzer == "ida"


def test_help_lists_the_function_command():
    from binrecon.cli import build_parser

    assert "function" in build_parser().format_help()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_functions.py -q
```

Expected: collection error, `ModuleNotFoundError: No module named 'binrecon.functions'`.

- [ ] **Step 3: Write the module**

Create `tools/binrecon/binrecon/functions.py`:

```python
"""Per-function queries over already-published binrecon output.

`binrecon analyze` publishes each analyzer's full instruction listing per
function.  Everything here reads those files, so any function can be examined
without re-running an analyzer -- which is what makes examining a few hundred
functions practical.
"""

from __future__ import annotations

import difflib
import json
from pathlib import Path


class FunctionQueryError(ValueError):
    """Raised when published output cannot be read or a function is unknown."""


def _read(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise FunctionQueryError(f"published file is missing: {path}") from error
    except (OSError, ValueError) as error:
        raise FunctionQueryError(f"published file is unreadable: {path}: {error}") from error


def load_published(output_dir: Path, analyzer: str) -> tuple[dict, dict, dict]:
    published = Path(output_dir) / "published"
    if not published.is_dir():
        raise FunctionQueryError(f"no published output directory: {published}")
    return (_read(published / f"analysis-reference-{analyzer}.json"),
            _read(published / f"analysis-rebuilt-{analyzer}.json"),
            _read(published / f"comparison-{analyzer}.json"))


def function_index(analysis: dict) -> dict[str, dict]:
    index: dict[str, dict] = {}
    for function in analysis.get("functions") or []:
        for name in function.get("names") or []:
            index.setdefault(name, function)
    return index


def instruction_pairs(function: dict) -> list[tuple[str, str]]:
    return [(item["mnemonic"], item.get("normalized_operands") or "")
            for item in function.get("instructions") or []]


def differing_count(reference_function: dict | None,
                    rebuilt_function: dict | None) -> int | None:
    if reference_function is None or rebuilt_function is None:
        return None
    left = [str(item) for item in instruction_pairs(reference_function)]
    right = [str(item) for item in instruction_pairs(rebuilt_function)]
    matcher = difflib.SequenceMatcher(a=left, b=right, autojunk=False)
    return sum(max(i2 - i1, j2 - j1)
               for tag, i1, i2, j1, j2 in matcher.get_opcodes() if tag != "equal")


def _row_name(record: dict) -> str:
    for key in ("reference_aliases", "rebuilt_aliases"):
        names = record.get(key) or []
        if names:
            return names[0]
    return "?"


def worklist(reference: dict, rebuilt: dict, comparison: dict) -> list[dict]:
    reference_index = function_index(reference)
    rebuilt_index = function_index(rebuilt)
    rows = []
    for record in comparison.get("functions") or []:
        name = _row_name(record)
        reference_function = next(
            (reference_index[alias] for alias in record.get("reference_aliases") or []
             if alias in reference_index), None)
        rebuilt_function = next(
            (rebuilt_index[alias] for alias in record.get("rebuilt_aliases") or []
             if alias in rebuilt_index), None)
        rows.append({
            "name": name,
            "status": record.get("status"),
            "raw_equal": record.get("raw_equal"),
            "masked_equal": record.get("masked_equal"),
            "differing": differing_count(reference_function, rebuilt_function),
            "reference_instructions":
                len(instruction_pairs(reference_function)) if reference_function else None,
            "rebuilt_instructions":
                len(instruction_pairs(rebuilt_function)) if rebuilt_function else None,
            "reasons": record.get("reasons") or [],
        })
    rows.sort(key=lambda row: (row["differing"] is None,
                               row["differing"] if row["differing"] is not None else 0,
                               row["name"]))
    return rows


def render_worklist(rows: list[dict]) -> str:
    lines = [f"{'diff':>6}  {'ref':>5}  {'new':>5}  {'flags':<10}  name", ""]
    for row in rows:
        differing = "-" if row["differing"] is None else str(row["differing"])
        reference = "-" if row["reference_instructions"] is None else str(row["reference_instructions"])
        rebuilt = "-" if row["rebuilt_instructions"] is None else str(row["rebuilt_instructions"])
        if row["raw_equal"]:
            flags = "identical"
        elif row["masked_equal"]:
            flags = "masked-eq"
        elif row["status"] != "different":
            flags = row["status"]
        else:
            flags = ""
        lines.append(f"{differing:>6}  {reference:>5}  {rebuilt:>5}  {flags:<10}  {row['name']}")
    identical = sum(1 for row in rows if row["raw_equal"])
    unpaired = sum(1 for row in rows if row["differing"] is None)
    lines += ["", f"{len(rows)} functions: {identical} byte-identical, "
                  f"{len(rows) - identical - unpaired} differing, {unpaired} unpaired"]
    return "\n".join(lines)


def render_function(name: str, reference_function: dict | None,
                    rebuilt_function: dict | None, record: dict | None) -> str:
    if reference_function is None and rebuilt_function is None:
        raise FunctionQueryError(f"no function named {name!r} in the published output")
    left = instruction_pairs(reference_function) if reference_function else []
    right = instruction_pairs(rebuilt_function) if rebuilt_function else []
    header = [name]
    if record is not None:
        header.append(f"  status={record.get('status')} "
                      f"raw_equal={record.get('raw_equal')} "
                      f"masked_equal={record.get('masked_equal')}")
        for reason in record.get("reasons") or []:
            header.append(f"  reason: {reason}")
    if reference_function is None:
        header.append("  reference side is missing")
    if rebuilt_function is None:
        header.append("  rebuilt side is missing")
    header.append("")
    header.append(f"  {'reference':<38}  {'rebuilt':<38}")

    def text(pair):
        return f"{pair[0]} {pair[1]}".strip() if pair else ""

    lines = []
    matcher = difflib.SequenceMatcher(a=[str(item) for item in left],
                                      b=[str(item) for item in right],
                                      autojunk=False)
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        width = max(i2 - i1, j2 - j1)
        for offset in range(width):
            source = left[i1 + offset] if i1 + offset < i2 else None
            target = right[j1 + offset] if j1 + offset < j2 else None
            marker = " " if tag == "equal" else "*"
            lines.append(f"{marker} {text(source):<38}  {text(target):<38}".rstrip())
    return "\n".join(header + lines)
```

- [ ] **Step 4: Run the module tests to verify they pass**

Run:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_functions.py -q -k "not parser and not help"
```

Expected: `13 passed`.

- [ ] **Step 5: Wire both modes into the CLI**

In `tools/binrecon/binrecon/cli.py`, add `"function"` to the `COMMANDS` tuple so it reads:

```python
COMMANDS = ("validate", "analyze", "consensus", "compare", "ledger", "source-map", "function")
```

Add this import beside the existing ones:

```python
from binrecon.functions import (
    FunctionQueryError, function_index, load_published, render_function,
    render_worklist, worklist,
)
```

In `build_parser()`, after the `source_map` block and before `return parser`:

```python
    function = subparsers.add_parser("function")
    function.add_argument("--profile", required=True)
    function.add_argument("--analyzer", default="ida")
    function.add_argument("--list", action="store_true", dest="list_functions",
                          help="print every compared function, cheapest difference first")
    function.add_argument("--name", help="print one function's two instruction sequences")
```

In `main()`, before the final return, add the whole block — both modes, with no path that falls through silently:

```python
    if args.command == "function":
        if args.list_functions == bool(args.name):
            print("binrecon: give exactly one of --list or --name", file=sys.stderr)
            return 1
        try:
            profile = load_profile(Path(args.profile), os.environ)
            reference, rebuilt, comparison = load_published(profile.output_dir, args.analyzer)
            if args.list_functions:
                print(render_worklist(worklist(reference, rebuilt, comparison)))
                return 0
            record = next((item for item in comparison.get("functions") or []
                           if args.name in (item.get("reference_aliases") or [])
                           or args.name in (item.get("rebuilt_aliases") or [])), None)
            print(render_function(args.name, function_index(reference).get(args.name),
                                  function_index(rebuilt).get(args.name), record))
            return 0
        except (OSError, ValueError, ValidationError, FunctionQueryError) as error:
            print(f"binrecon: {error}", file=sys.stderr)
            return 1
```

Note the mutual-exclusion check runs **before** the profile is loaded, so a malformed invocation is rejected on its own terms rather than after an unrelated failure.

- [ ] **Step 6: Run the whole suite**

Run:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```

Expected: 15 more tests than the 905-passed baseline, nothing failing. If `test_cli.py`'s command lists fail, they assert on a fixed tuple of command names — read them and decide whether they should include `function`, rather than assuming.

- [ ] **Step 7: Commit**

```bash
git add tools/binrecon/binrecon/functions.py tools/binrecon/binrecon/cli.py tools/binrecon/tests/test_functions.py
git commit -m "binrecon: add a function subcommand for per-function worklists and diffs"
```

---

### Task 3: Rebuild, re-baseline, and record the worklist

**This task requires the user to build the driver.** Ask, and wait. Nothing in this task may be reported before the build completes.

**Files:**
- Create: `src/drivers-i386/ide/drvPCFloppy/reconstruction/function-worklist.md`

- [ ] **Step 1: Ask the user to build**

Tell the user that `drvPCFloppy` needs building on the Rhapsody guest. Warn them that this is the **first compile** of nine committed changes from the invented-symbol piece plus inheritance changes across four drivers, none of which has ever been compiled, so a failure may originate outside this campaign. Wait for them.

- [ ] **Step 2: Re-run the analysis**

Run, from the repository root:

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc" \
BINRECON_REBUILT="D:/RhapsodiOS/out/i386/drvPCFloppy/Floppy.config/Floppy_reloc" \
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon analyze --profile tools/binrecon/profiles/floppy.json
```

Expected: `analysis complete; analyzers=1 comparisons=1 normalized-functions=FAIL`. This takes roughly ten minutes. `normalized-functions=FAIL` is expected — it is the acceptance gate the driver is not yet meant to pass.

If it fails instead with a normalization error, the message now names the artifact, analyzer and instruction address. Report it rather than working around it.

- [ ] **Step 3: Produce the worklist**

Run:

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc" \
BINRECON_REBUILT="D:/RhapsodiOS/out/i386/drvPCFloppy/Floppy.config/Floppy_reloc" \
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon function --profile tools/binrecon/profiles/floppy.json --list
```

Expected: a table of every compared function, cheapest difference first, ending in a summary line of the form `N functions: X byte-identical, Y differing, Z unpaired`.

- [ ] **Step 4: Spot-check `--name` against a real function**

Pick the first row in the worklist whose `diff` column is not `0` and run:

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc" \
BINRECON_REBUILT="D:/RhapsodiOS/out/i386/drvPCFloppy/Floppy.config/Floppy_reloc" \
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon function --profile tools/binrecon/profiles/floppy.json --name '<that function name>'
```

Expected: the verdict and reasons, then two aligned instruction columns with `*` on the differing rows. Confirm the number of `*` rows equals that row's `diff` count.

- [ ] **Step 5: Record the baseline**

Create `src/drivers-i386/ide/drvPCFloppy/reconstruction/function-worklist.md` containing:

- the date, the rebuilt binary's size and SHA-256, and the reference's;
- the summary line from Step 3;
- a comparison against the stale 2026-07-26 baseline — 230 compared, 49 byte-identical, 174 differing, 5 ours-only, 2 reference-only — stating how each number moved;
- whether the four functions the invented-symbol piece deleted (`isAnyOtherOpen`, `_queueEmpty`, `_dequeueOperation`, `_appendOperationToQueue`) are indeed gone;
- the per-class counts of differing functions, so the campaign's remaining sub-pieces can be re-cut against real numbers;
- the full worklist table from Step 3.

- [ ] **Step 6: Judge whether the campaign's premise still holds**

The spec carries an explicit abort condition. Read the top twenty rows of the worklist — the cheapest differences — and answer in the same file, under a heading `## Is this reachable?`:

Do the cheapest functions differ by things source can control (a wrong constant, a missing call, an inverted branch), or by things it cannot (register allocation, instruction scheduling)? If predominantly the latter, say so plainly: it means most of the 174 are unreachable and the campaign should be re-scoped rather than continued. This judgement is the deliverable, not a formality.

- [ ] **Step 7: Commit**

```bash
git add src/drivers-i386/ide/drvPCFloppy/reconstruction/function-worklist.md
git commit -m "drvPCFloppy: record the post-rebuild function baseline and worklist"
```
