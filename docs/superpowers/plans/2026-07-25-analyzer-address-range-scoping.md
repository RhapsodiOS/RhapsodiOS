# Analyzer Address-Range Scoping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a binrecon profile declare an address range so the analyzers export only the functions inside it, making large images reconstructible a subsystem at a time.

**Architecture:** One new optional `analysis_scope` field in `profile-v1`. A shared helper validates and normalises it on the binrecon side. Each of the three adapters copies it into the JSON side-file its exporter already receives, and each exporter skips functions whose entry point falls outside. Absent field means analyze everything, byte-for-byte as today.

**Tech Stack:** Python 3.13.9, binrecon (`tools/binrecon`), IDA Professional 9.2 (IDAPython), Ghidra 12.1 on Java 21, angr 9.3.0, pytest 9.1.1, jsonschema 4.26.0.

**Spec:** `docs/superpowers/specs/2026-07-25-analyzer-address-range-scoping-design.md`

## Global Constraints

- Python is 3.13.9 at `./.venv-binrecon/Scripts/python.exe`. Every binrecon invocation needs `PYTHONPATH=tools/binrecon` and runs from the repository root.
- **Measure the test baseline yourself before your first edit** and treat every later count as a delta:

  ```bash
  PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
  ```

  It was 659 passed, 4 skipped when this plan was written, but **another agent adds tests to `tools/binrecon` concurrently**, so the absolute number drifts. What matters is that your change adds exactly the tests your task introduces and breaks none.
- **`analysis_scope` is opt-in and absent from every existing profile.** No existing profile may change behaviour. This is the single most important property in the plan: three completed driver reconstructions depend on it.
- `start` is inclusive, `end` is exclusive. A function is in scope when its **entry point** lies in a range.
- The scope is omitted entirely from a side-file when the profile has no scope — never written as an empty list, so "no scope" and "a scope matching nothing" stay distinguishable.
- Reference binaries live under `C:\Users\raynorpat\Downloads\test\` and are **never** committed.
- Commit messages: short, subsystem-prefixed (`binrecon: `), one to two lines, no metadata, no trailers.
- **Another agent commits to this repository concurrently and edits `tools/binrecon` too.** Re-read files before editing rather than trusting quoted line numbers. Stage only your own paths. Never `git add -A`, never `git commit -a`.

## Key facts established while specifying

- `Profile` is a dataclass carrying `document: Mapping[str, object]`, the raw validated profile. Adapters already read optional fields straight off it — `adapters/ida.py:76` and `adapters/angr.py:158` both do `profile.document.get("regions", ())`. **So no `profile.py` loader change is needed**; only the schema must declare the property, because `profile-v1.json` sets `additionalProperties: false`.
- `analysis-v1.json` also sets `additionalProperties: false`, but its `extensions` property is an open object (`propertyNames` a non-empty string, `additionalProperties: {}`). **Recording the scope in the emitted analysis therefore needs no schema change** — it goes under `extensions.binrecon`.
- The three exporters cannot share code: they run inside IDA's Python, a plain Python process, and a Ghidra JVM respectively, and none can import `binrecon`. Each gets its own small predicate. That duplication is unavoidable, not an oversight.

## The kernel scope value

The consuming effort's 24 method implementations run from `0x1fd0d4` (2085076) to `0x1fdcd4` (2088148), the latter being the *entry point* of the last method. Because `end` is exclusive it must exceed that:

```json
"analysis_scope": [ { "start": 2085076, "end": 2088160 } ]
```

A scope ending at 2088148 silently drops `-[IOPCMCIATuple data]`. Task 5 asserts all 24 are present precisely to catch that class of error.

## File Structure

**Modified:**

| Path | Change |
| --- | --- |
| `tools/binrecon/binrecon/schema/profile-v1.json` | Declare `analysis_scope` and a `scope_range` definition |
| `tools/binrecon/binrecon/profile.py` | Add `analysis_scope(profile)` helper |
| `tools/binrecon/tests/test_profile.py` | Helper and schema tests |
| `tools/binrecon/binrecon/adapters/ida.py` | `_mapping_manifest` emits the scope |
| `tools/binrecon/adapters/ida/export_analysis.py` | Accept the key; filter the function loop; record in `extensions.binrecon` |
| `tools/binrecon/binrecon/adapters/angr.py` | `_layout` emits the scope |
| `tools/binrecon/adapters/angr/export_analysis.py` | Narrow `executable`; record in `extensions.binrecon` |
| `tools/binrecon/binrecon/adapters/ghidra.py` | `_layout` emits the scope |
| `tools/binrecon/adapters/ghidra/ExportAnalysis.java` | Filter the `FunctionIterator` loop; record in `extensions.binrecon` |
| `tools/binrecon/profiles/kernel-driverkit.json` | Carry the kernel scope |

---

### Task 1: Schema and the shared scope helper

**Files:**
- Modify: `tools/binrecon/binrecon/schema/profile-v1.json`
- Modify: `tools/binrecon/binrecon/profile.py`
- Test: `tools/binrecon/tests/test_profile.py`

**Interfaces:**
- Produces: `profile.analysis_scope(profile) -> tuple[tuple[int, int], ...]`, returning sorted non-overlapping `(start, end)` pairs, or an empty tuple when the profile declares no scope. Raises `ProfileError` on an inverted, empty, or overlapping range. Tasks 2, 3 and 4 all call it.

- [ ] **Step 1: Write the failing tests**

Append to `tools/binrecon/tests/test_profile.py`. Read the top of that file first and reuse whatever helper it already has for building a profile document; if it builds documents inline, follow that style.

```python
def test_analysis_scope_is_empty_when_absent():
    profile = SimpleNamespace(document={})

    assert analysis_scope(profile) == ()


def test_analysis_scope_returns_sorted_pairs():
    profile = SimpleNamespace(document={
        "analysis_scope": [{"start": 0x2000, "end": 0x3000},
                           {"start": 0x1000, "end": 0x1500}]
    })

    assert analysis_scope(profile) == ((0x1000, 0x1500), (0x2000, 0x3000))


def test_analysis_scope_rejects_an_inverted_range():
    profile = SimpleNamespace(document={
        "analysis_scope": [{"start": 0x3000, "end": 0x2000}]
    })

    with pytest.raises(ProfileError):
        analysis_scope(profile)


def test_analysis_scope_rejects_an_empty_range():
    profile = SimpleNamespace(document={
        "analysis_scope": [{"start": 0x2000, "end": 0x2000}]
    })

    with pytest.raises(ProfileError):
        analysis_scope(profile)


def test_analysis_scope_rejects_overlapping_ranges():
    profile = SimpleNamespace(document={
        "analysis_scope": [{"start": 0x1000, "end": 0x2000},
                           {"start": 0x1800, "end": 0x2400}]
    })

    with pytest.raises(ProfileError):
        analysis_scope(profile)
```

Add `from types import SimpleNamespace` and extend the existing `binrecon.profile` import to include `analysis_scope` and `ProfileError`.

- [ ] **Step 2: Run them and confirm they fail**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_profile.py -q
```

Expected: `ImportError: cannot import name 'analysis_scope'`.

- [ ] **Step 3: Declare the schema property**

In `tools/binrecon/binrecon/schema/profile-v1.json`, add to `properties`, beside the existing `regions` line:

```json
    "analysis_scope": {"type": "array", "minItems": 1,
                       "items": {"$ref": "#/$defs/scope_range"}},
```

and add to `$defs`:

```json
    "scope_range": {
      "type": "object",
      "additionalProperties": false,
      "required": ["start", "end"],
      "properties": {
        "start": {"type": "integer", "minimum": 0},
        "end": {"type": "integer", "minimum": 1}
      }
    },
```

Do **not** add `analysis_scope` to the top-level `required` list. JSON Schema cannot express `end > start`; the helper enforces that.

- [ ] **Step 4: Implement the helper**

Add to `tools/binrecon/binrecon/profile.py`, after `load_profile`:

```python
def analysis_scope(profile):
    """Return the profile's analysis scope as sorted (start, end) pairs.

    An empty tuple means the profile declares no scope, so everything is
    analyzed. ``start`` is inclusive and ``end`` exclusive.
    """
    declared = profile.document.get("analysis_scope")
    if not declared:
        return ()
    ranges = []
    for item in declared:
        start, end = int(item["start"]), int(item["end"])
        if end <= start:
            raise ProfileError(
                f"analysis_scope range {start}..{end} is empty or inverted"
            )
        ranges.append((start, end))
    ranges.sort()
    for (_, previous_end), (next_start, _) in zip(ranges, ranges[1:]):
        if next_start < previous_end:
            raise ProfileError(
                f"analysis_scope ranges overlap at {next_start}"
            )
    return tuple(ranges)
```

Overlapping ranges are rejected rather than merged: they are harmless to a predicate but always indicate a mistake in the profile, and silently merging would hide it.

- [ ] **Step 5: Run the tests and the full suite**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```

Expected: baseline + 5, zero failures.

- [ ] **Step 6: Confirm existing profiles still validate**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/PCIC.config/PCIC_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon validate --profile tools/binrecon/profiles/intel82365pcmcia.json
```

Expected: exit 0, size `38700`. A schema change that broke existing profiles would surface here.

- [ ] **Step 7: Commit**

```bash
git add tools/binrecon/binrecon/schema/profile-v1.json tools/binrecon/binrecon/profile.py tools/binrecon/tests/test_profile.py
git commit -m "binrecon: add an optional analysis_scope profile field"
```

---

### Task 2: IDA honours the scope

The IDA exporter validates its own manifest against an exact key set, so producer and consumer must change together or it rejects its own input.

**Files:**
- Modify: `tools/binrecon/binrecon/adapters/ida.py` (`_mapping_manifest`)
- Modify: `tools/binrecon/adapters/ida/export_analysis.py` (`_validate_mapping`, the function loop, the output document)

**Interfaces:**
- Consumes: `analysis_scope(profile)` from Task 1.
- Produces: an `ida-mapping-v1` manifest that may carry an `analysis_scope` key, and an analysis whose `extensions.binrecon.analysis_scope` records the scope when one applied.

- [ ] **Step 1: Emit the scope from the producer**

In `tools/binrecon/binrecon/adapters/ida.py`, `_mapping_manifest` currently returns:

```python
    return {"schema_version": "ida-mapping-v1",
            "input": {"size": identity.size, "sha256": identity.sha256,
                      "architecture": profile.document.get("architecture", "i386"),
                      "endianness": profile.document.get("endianness", "little")},
            "runs": runs}
```

Change it to include the scope only when there is one:

```python
    manifest = {"schema_version": "ida-mapping-v1",
                "input": {"size": identity.size, "sha256": identity.sha256,
                          "architecture": profile.document.get("architecture", "i386"),
                          "endianness": profile.document.get("endianness", "little")},
                "runs": runs}
    scope = analysis_scope(profile)
    if scope:
        manifest["analysis_scope"] = [{"start": start, "end": end}
                                      for start, end in scope]
    return manifest
```

Import `analysis_scope` from `binrecon.profile` at the top of the file, matching the existing import style.

- [ ] **Step 2: Accept the optional key in the consumer**

In `tools/binrecon/adapters/ida/export_analysis.py`, `_validate_mapping` begins:

```python
def _validate_mapping(mapping, size, digest):
    if (not isinstance(mapping, dict) or set(mapping) != {"schema_version", "input", "runs"}
            or mapping["schema_version"] != "ida-mapping-v1"):
        raise ExportError("artifact mapping manifest is malformed")
```

Change the key-set test so the new key is permitted but nothing else is:

```python
def _validate_mapping(mapping, size, digest):
    if (not isinstance(mapping, dict)
            or set(mapping) - {"analysis_scope"} != {"schema_version", "input", "runs"}
            or mapping["schema_version"] != "ida-mapping-v1"):
        raise ExportError("artifact mapping manifest is malformed")
```

Subtracting the optional key keeps the check strict: an unexpected key still fails.

- [ ] **Step 3: Parse the scope and filter the function loop**

Still in `export_analysis.py`, add a helper near `_validate_mapping`:

```python
def _scope_from_mapping(mapping):
    """Return sorted (start, end) pairs, or () when the manifest has no scope."""
    declared = mapping.get("analysis_scope")
    if not declared:
        return ()
    ranges = []
    for item in declared:
        start, end = int(item["start"]), int(item["end"])
        if end <= start:
            raise ExportError(f"analysis scope range {start}..{end} is empty or inverted")
        ranges.append((start, end))
    return tuple(sorted(ranges))


def _in_scope(address, scope):
    return not scope or any(start <= address < end for start, end in scope)
```

The function loop reads:

```python
    for address in idautils.Functions():
        function = ida_funcs.get_func(address)
        if function is None:
            raise ExportError(f"could not read function at {address:#x}")
        canonical_entry = function.start_ea
        if canonical_entry in seen_functions:
            continue
        seen_functions.add(canonical_entry)
```

Add the scope test immediately after `canonical_entry` is computed, so the entry point — not the iteration address — decides:

```python
        canonical_entry = function.start_ea
        if not _in_scope(canonical_entry, scope):
            continue
        if canonical_entry in seen_functions:
            continue
```

Thread `scope` in from where the mapping is validated. Read the surrounding function to see how `mapping` reaches this loop and pass `scope` the same way.

- [ ] **Step 4: Record the scope in the output**

The exporter builds its document with an `"extensions": {"ida": {...}}` key. Add a sibling `binrecon` entry when a scope applied:

```python
    extensions = {"ida": { ... existing content unchanged ... }}
    if scope:
        extensions["binrecon"] = {
            "analysis_scope": [{"start": start, "end": end} for start, end in scope]
        }
```

`extensions` is an open object in `analysis-v1`, so no schema change is needed.

- [ ] **Step 5: Fail loudly when a scope matches nothing**

After the function loop, if a scope applied and no functions survived it, raise rather than publishing an empty analysis:

```python
    if scope and not functions:
        raise ExportError("analysis scope matched no functions")
```

A scoped run that quietly produces nothing would report `complete: true` and look like success — the most dangerous failure mode in this change.

- [ ] **Step 6: Run the full suite**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```

Expected: unchanged from Task 1's total, zero failures. This task adds no tests — the IDA exporter runs only inside IDA, so its real verification is the end-to-end run in Task 5. Any pre-existing IDA adapter test that constructs a manifest must still pass; if one fails, your key-set change is wrong.

- [ ] **Step 7: Commit**

```bash
git add tools/binrecon/binrecon/adapters/ida.py tools/binrecon/adapters/ida/export_analysis.py
git commit -m "binrecon: let the IDA exporter honour an analysis scope"
```

---

### Task 3: angr honours the scope

angr already filters by executable region, so this narrows an existing set rather than adding a mechanism.

**Files:**
- Modify: `tools/binrecon/binrecon/adapters/angr.py` (`_layout`)
- Modify: `tools/binrecon/adapters/angr/export_analysis.py` (`export_cfg`, the output document)

**Interfaces:**
- Consumes: `analysis_scope(profile)` from Task 1.

- [ ] **Step 1: Emit the scope from the producer**

In `tools/binrecon/binrecon/adapters/angr.py`, `_layout(profile, identity)` builds the layout document. It has a `try`/`except` with a Mach-O fallback path, and both paths converge on a single `return`. Attach the scope at that return, so a parse failure does not silently drop it:

```python
    document = { ... whatever the function already returns ... }
    scope = analysis_scope(profile)
    if scope:
        document["analysis_scope"] = [{"start": start, "end": end}
                                      for start, end in scope]
    return document
```

If the function currently returns a dict literal directly, bind it to `document` first rather than duplicating the literal. Import `analysis_scope` from `binrecon.profile` at the top of the file, matching the existing import style.

- [ ] **Step 2: Narrow the executable set in the consumer**

In `tools/binrecon/adapters/angr/export_analysis.py`, `export_cfg` currently reads:

```python
def export_cfg(project, layout: dict, canonical: dict) -> tuple[list[dict], dict, list[dict]]:
    starts = function_starts(layout, canonical)
    cfg_errors = []
    executable = [(item["address"], item["address"] + item["size"])
                  for item in layout.get("sections", [])
                  if "x" in item.get("permissions", "") and item.get("size", 0)]
```

Intersect that with the scope:

```python
def export_cfg(project, layout: dict, canonical: dict) -> tuple[list[dict], dict, list[dict]]:
    starts = function_starts(layout, canonical)
    cfg_errors = []
    executable = [(item["address"], item["address"] + item["size"])
                  for item in layout.get("sections", [])
                  if "x" in item.get("permissions", "") and item.get("size", 0)]
    scope = [(int(item["start"]), int(item["end"]))
             for item in layout.get("analysis_scope", ())]
    if scope:
        executable = [(max(low, start), min(high, end))
                      for low, high in executable
                      for start, end in scope
                      if max(low, start) < min(high, end)]
        if not executable:
            raise ExportError("analysis scope matched no executable region")
```

Intersecting rather than replacing matters: `executable` also feeds `CFGFast(regions=...)`, and handing it a range covering non-executable bytes would change what angr tries to disassemble.

The existing `in_executable(address)` predicate at the same site then filters functions against the narrowed set with no further change.

- [ ] **Step 3: Record the scope in the output**

The exporter writes `"extensions": {"angr": {...}}`. Add a sibling entry when a scope applied:

```python
            "extensions": {"angr": { ... existing content unchanged ... },
                           **({"binrecon": {"analysis_scope":
                                [{"start": start, "end": end} for start, end in scope]}}
                              if scope else {})},
```

If that inline form reads badly in context, build the `extensions` dict on a preceding line instead — the requirement is the resulting shape, not the expression.

- [ ] **Step 4: Run the full suite**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```

Expected: unchanged total, zero failures. Existing angr adapter tests exercise `_layout`; if one fails, the scope is being emitted when it should not be.

- [ ] **Step 5: Commit**

```bash
git add tools/binrecon/binrecon/adapters/angr.py tools/binrecon/adapters/angr/export_analysis.py
git commit -m "binrecon: let the angr exporter honour an analysis scope"
```

---

### Task 4: Ghidra honours the scope

The only adapter in Java, and the only one needing a compile step.

**Files:**
- Modify: `tools/binrecon/binrecon/adapters/ghidra.py` (`_layout`)
- Modify: `tools/binrecon/adapters/ghidra/ExportAnalysis.java` (`exportFunctions`, the output document)

**Interfaces:**
- Consumes: `analysis_scope(profile)` from Task 1.

- [ ] **Step 1: Emit the scope from the producer**

In `tools/binrecon/binrecon/adapters/ghidra.py`, `_layout(profile, identity)` builds the layout document Ghidra receives via `--layout`. Attach the scope at its return, the same shape Tasks 2 and 3 use:

```python
    document = { ... whatever the function already returns ... }
    scope = analysis_scope(profile)
    if scope:
        document["analysis_scope"] = [{"start": start, "end": end}
                                      for start, end in scope]
    return document
```

Import `analysis_scope` from `binrecon.profile` at the top of the file, matching the existing import style. Note the resulting document still declares `"schema_version": "ghidra-layout-v1"` — the Java side accepts extra keys, so this needs no version bump.

- [ ] **Step 2: Filter the function iterator**

In `tools/binrecon/adapters/ghidra/ExportAnalysis.java`, `exportFunctions` begins:

```java
    private List<Object> exportFunctions(List<Object> summaries) throws Exception {
        List<Function> functions = new ArrayList<>();
        FunctionIterator iterator=currentProgram.getFunctionManager().getFunctions(true);
        while(iterator.hasNext()) {
            Function function = iterator.next();
            if (function.getEntryPoint().isMemoryAddress()) functions.add(function);
        }
```

Add the scope test alongside the existing one, keying on the entry point:

```java
            Function function = iterator.next();
            if (function.getEntryPoint().isMemoryAddress()
                    && inScope(function.getEntryPoint().getOffset())) functions.add(function);
```

Add the scope as a field on the class, populated in `readLayout` (around line 75), which already parses the layout and validates its `schema_version` and identity. The file has its own JSON handling with accessor helpers `object(value, label)`, `array(value, label)`, `number(value)` and `string(value)` — use those, not an external library:

```java
    private final List<long[]> scope = new ArrayList<>();
```

In `readLayout`, after the existing identity validation:

```java
        Object declaredScope = layout.get("analysis_scope");
        if (declaredScope != null) {
            for (Object item : array(declaredScope, "analysis_scope")) {
                Map<String,Object> range = object(item, "analysis_scope range");
                long start = number(range.get("start"));
                long end = number(range.get("end"));
                if (end <= start) throw new IOException("analysis scope range is empty or inverted");
                scope.add(new long[]{start, end});
            }
        }
```

And the predicate:

```java
    private boolean inScope(long address) {
        if (scope.isEmpty()) return true;
        for (long[] range : scope) if (address >= range[0] && address < range[1]) return true;
        return false;
    }
```

- [ ] **Step 3: Fail loudly when a scope matches nothing**

After the iterator loop, when a scope applied and `functions` is empty, throw rather than exporting nothing:

```java
        if (!scope.isEmpty() && functions.isEmpty())
            throw new IOException("analysis scope matched no functions");
```

- [ ] **Step 4: Record the scope in the output**

`ExportAnalysis.java` around line 280 does `extensions.put("ghidra", ghidra); root.put("extensions", extensions);`. Add a sibling entry when a scope applied, holding `analysis_scope` as a list of objects with `start` and `end`, matching the other two adapters exactly.

- [ ] **Step 5: Run the full suite**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```

Expected: unchanged total, zero failures. The Java is not exercised by pytest; the Python-side `_layout` change is.

- [ ] **Step 6: Commit**

```bash
git add tools/binrecon/binrecon/adapters/ghidra.py tools/binrecon/adapters/ghidra/ExportAnalysis.java
git commit -m "binrecon: let the Ghidra exporter honour an analysis scope"
```

---

### Task 5: End to end, and the unscoped regression

**Files:**
- Modify: `tools/binrecon/profiles/kernel-driverkit.json`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Give the kernel profile its scope**

Add to `tools/binrecon/profiles/kernel-driverkit.json`, as a sibling of `output_dir`:

```json
  "analysis_scope": [ { "start": 2085076, "end": 2088160 } ],
```

- [ ] **Step 2: Validate it**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/mach_kernel_dr2_x86" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon validate --profile tools/binrecon/profiles/kernel-driverkit.json
```

Expected: exit 0, size `1404116`, SHA-256 `BE98A33F71B80AEE00A6921333943DA02D0B676C8AF056843EB868C14EBB497C`.

- [ ] **Step 3: Run the analyzers on the kernel — the decisive check**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/mach_kernel_dr2_x86" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon analyze --profile tools/binrecon/profiles/kernel-driverkit.json
```

This previously failed with `IDA output is invalid: IDA output exceeds maximum JSON size` and `complete: false`. It must now reach `"complete": true` with `published/` holding `analysis-reference-{ida,ghidra,angr}.json` plus `consensus-reference.json`.

Exit code 1 is still correct — this is a reference-only profile with no comparisons, and the runner refuses to report acceptance when nothing was compared. Judge on `"complete": true` and the published files.

**Run it detached and owned by the session**; it is a long-lived child process that dies with a subagent that exits.

- [ ] **Step 4: Confirm the 24 methods are present**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
import json
from pathlib import Path
from binrecon.macho import objc_method_index
index = objc_method_index(Path(r'C:\Users\raynorpat\Downloads\test\mach_kernel_dr2_x86'))
wanted = {a for a, n in index.items() if any('PCI' in x or 'PCMCIA' in x for x in n)}
print('expected', len(wanted))
for analyzer in ('ida', 'ghidra', 'angr'):
    p = f'tools/binrecon/out/kernel-driverkit/published/analysis-reference-{analyzer}.json'
    doc = json.load(open(p))
    found = {f['address'] for f in doc['functions']}
    print(analyzer, 'functions', len(found), '| of the 24 found', len(wanted & found),
          '| missing', sorted(hex(a) for a in wanted - found))
    print('   recorded scope:', doc.get('extensions', {}).get('binrecon'))
"
```

Expected: `expected 24`; IDA and Ghidra each find all 24 with an empty missing list; each analysis records the scope under `extensions.binrecon`. angr may differ — `CFGFast` restricts recovery rather than merely filtering output, so record any difference rather than treating it as failure.

Each analyzer's total function count should now be a small number, not thousands. If one still reports thousands, its filter is not firing.

- [ ] **Step 5: The unscoped regression check — as important as Step 3**

Re-run a completed driver profile, which has no `analysis_scope`, and confirm its output is unchanged:

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/PCIC.config/PCIC_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon analyze --profile tools/binrecon/profiles/intel82365pcmcia.json
```

Then compare against the known-good result from before this change:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
import json
for analyzer in ('ida', 'ghidra', 'angr'):
    p = f'tools/binrecon/out/intel82365pcmcia/published/analysis-reference-{analyzer}.json'
    doc = json.load(open(p))
    print(analyzer, len(doc['functions']), 'functions | binrecon ext:',
          doc.get('extensions', {}).get('binrecon'))
"
```

Expected: **IDA 82 functions, Ghidra 79, angr 153** — the counts this profile produced before the change — and `binrecon ext: None` for all three, since no scope applied. Any difference means an unscoped run changed behaviour, which is the failure this whole plan must not cause.

- [ ] **Step 6: Confirm nothing is tracked**

```bash
git status --porcelain tools/binrecon/out
```

Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add tools/binrecon/profiles/kernel-driverkit.json
git commit -m "binrecon: scope the kernel profile to the DriverKit PCI/PCMCIA region"
```

---

## Verification summary

| Gate | Where | Check |
| --- | --- | --- |
| Schema accepts the field | Task 1 | Existing profile still validates |
| Helper rejects bad ranges | Task 1 | Inverted, empty, overlapping all raise |
| IDA manifest round-trips | Task 2 | Exporter accepts its own manifest |
| Scoped run completes | Task 5 | `"complete": true`, three analyses published |
| All 24 methods analyzed | Task 5 | IDA and Ghidra each find 24, none missing |
| Scope is recorded | Task 5 | `extensions.binrecon.analysis_scope` present |
| **Unscoped behaviour unchanged** | Task 5 | Driver profile yields 82 / 79 / 153 and no `binrecon` extension |
| No regressions | Tasks 1-4 | Suite is baseline + 5, zero failures |
