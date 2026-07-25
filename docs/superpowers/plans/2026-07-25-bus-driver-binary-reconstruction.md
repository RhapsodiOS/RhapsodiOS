# i386 Bus Driver Binary Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Map every function in Apple's shipped `PCIBus_reloc`, `PCMCIABus_reloc`, and `EISABus_reloc` binaries to our source, record the divergences, and fix them driver by driver.

**Architecture:** Each driver gets a *report pass* (run the three analyzers, build a `source-map.json` that partitions every reference function into mapped/unmapped/disputed/duplicate buckets, decompile-diff the mapped ones, write `divergences.md`) followed by a separate *fix pass* verified by a guest compile check. Drivers are done smallest-first so the cheapest one calibrates the conventions. A new `binrecon.source_map` module automates the address→symbol→source-line mapping; the analytical judgement stays human.

**Tech Stack:** Python 3.12, binrecon (`tools/binrecon`), IDA Professional 9.2, Ghidra 12.1 on Java 21, angr 9.3.0, pytest 9.1.1, jsonschema 4.26.0. Guest builds use `gnumake` + `pb_makefiles` on the Rhapsody QEMU guest.

**Spec:** `docs/superpowers/specs/2026-07-25-bus-driver-binary-reconstruction-design.md`

## Global Constraints

- Python 3.13.9 is the runtime. The binrecon README names 3.12, but 3.12 is not installed on this host and angr 9.3.0, jsonschema 4.26.0, and pytest 9.1.1 all install and pass on 3.13.9 at their pinned versions. Do not change the pins.
- **Known pre-existing test failure:** `tools/binrecon/tests/test_source_map.py::test_loader_validates_the_committed_eisabus_source_map_schema_and_semantics` fails at `test_source_map.py:320`, which expects a committed source map at the pre-`src/` path `src/drivers/x86/bus/drvEISABus/reconstruction/source-map.json`. No such file has ever existed in git history. Baseline is **607 passed, 4 skipped, 1 failed**. Task 12 fixes it. Do not attribute it to your change, and do not "fix" it outside Task 12.
- IDA `version` must be `9.2`; Ghidra `version` must be `12.1` with a Java 21 `java.exe`. The adapters reject other versions.
- Reference binaries live at `C:\Users\raynorpat\Downloads\test\Drivers\i386` and are **never** committed.
- **Never point a profile's `rebuilt` at the reference.** That is what produced the false `exact-image` pass in `tools/binrecon/out/eisabus/`.
- Architecture is `i386`, endianness `little`, for all three profiles.
- `source-map-v1` `reference_sha256` and all hashes use the pattern `^[0-9A-F]{64}$` — **uppercase**.
- `source_path` in a source map must be a canonical repo-relative **POSIX** path: forward slashes only, not absolute, no `.` or `..` parts, no drive letter. This is generated on Windows, so paths must be converted explicitly.
- Every source-map category array must be sorted by `(address, tuple(reference_names))`, and every `reference_names` and `reasons` array must be sorted and unique. The semantic validator rejects otherwise.
- Ledger status vocabulary is exactly: `unexamined`, `signature-confirmed`, `control-flow-confirmed`, `assembly-matched`, `intentional-mismatch`. There is no "fix" state.
- Commit messages: short, subsystem-prefixed (`binrecon: `, `drvPCIBus: `, `vm: `), one to two lines, no metadata.
- Fixes touch only code the ledger flags. No adjacent cleanup or refactoring.

## File Structure

**Created:**

| Path | Responsibility |
| --- | --- |
| `tools/binrecon/binrecon/source_map.py` | Build a `source-map-v1` document from a reference analysis, a Mach-O document, and a source tree |
| `tools/binrecon/tests/test_source_map_builder.py` | Tests for the builder (distinct from the existing `test_source_map.py`, which tests the schema loader) |
| `tools/binrecon/profiles/pcibus.json` | drvPCIBus reference-only profile |
| `tools/binrecon/profiles/pcmciabus.json` | drvPCMCIABus reference-only profile |
| `tools/binrecon/profiles/eisabus.json` | drvEISABus reference-only profile |
| `src/drivers-i386/bus/drv<Name>/reconstruction/source-map.json` | Complete function partition, per driver |
| `src/drivers-i386/bus/drv<Name>/reconstruction/ledger.json` | Parity confidence ledger, per driver |
| `src/drivers-i386/bus/drv<Name>/reconstruction/divergences.md` | Report-pass findings, per driver |
| `docs/drivers/drv<Name>-issues.md` | Human-readable summary, per driver |
| `vm/build-i386-bus-drivers.sh` | Guest build + staging for all three drivers |

**Modified:**

| Path | Change |
| --- | --- |
| `tools/binrecon/binrecon/schema/profile-v1.json` | Drop `rebuilt` from `required` |
| `tools/binrecon/binrecon/profile.py:27,31,47-48,57,61` | `rebuilt` / `rebuilt_identity` become optional |
| `tools/binrecon/binrecon/cli.py` | Add the `source-map` subcommand |
| `.gitignore` | Ignore `tools/binrecon/out/` |
| `src/drivers-i386/README` | Update the three driver status lines |
| `docs/superpowers/specs/2026-07-25-bus-driver-binary-reconstruction-design.md` | Add the builder to the deliverables list |

**Note on scope:** the `source_map.py` builder and its CLI subcommand are not in the spec's §7 deliverables list. Building 260 function mappings by hand is not viable, so Task 4 adds them and Task 8 amends the spec to match.

---

### Task 1: Reference-only profile support

The runner already handles a null rebuilt artifact end to end — it selects `artifact_names = ("reference",)`, skips comparison, and its summary validator accepts `rebuilt_sha256: None`. Only the profile schema and loader block it.

**Files:**
- Modify: `tools/binrecon/binrecon/schema/profile-v1.json`
- Modify: `tools/binrecon/binrecon/profile.py:27,31,47-48,57,61`
- Test: `tools/binrecon/tests/test_profile.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `Profile.rebuilt: ArtifactSpec | None` and `Profile.rebuilt_identity: InputIdentity | None`, both `None` when the profile document has no `rebuilt` key.

- [ ] **Step 1: Confirm the virtualenv is present**

`.venv-binrecon` has already been created on Python 3.13.9 with all pinned dependencies installed. Verify rather than recreate:

```bash
./.venv-binrecon/Scripts/python.exe --version
./.venv-binrecon/Scripts/python.exe -m pip show angr jsonschema pytest | grep -E "^(Name|Version)"
```

Expected: `Python 3.13.9`, then `angr 9.3.0`, `jsonschema 4.26.0`, `pytest 9.1.1`.

- [ ] **Step 2: Record the baseline test result before touching anything**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```

Expected: **607 passed, 4 skipped, 1 failed**. The one failure is the known pre-existing `test_loader_validates_the_committed_eisabus_source_map_schema_and_semantics` described in Global Constraints. Any *other* failure means stop and report.

- [ ] **Step 3: Write the failing test**

Append to `tools/binrecon/tests/test_profile.py`:

```python
def test_load_profile_allows_missing_rebuilt(tmp_path):
    document = _profile_document()
    del document["rebuilt"]
    profile_path = _write_profile(tmp_path, document)

    profile = load_profile(profile_path, {})

    assert profile.rebuilt is None
    assert profile.rebuilt_identity is None
    assert profile.reference.path == (tmp_path / "reference.bin").resolve()


def test_load_profile_still_loads_rebuilt_when_present(tmp_path):
    profile = load_profile(_write_profile(tmp_path), {})

    assert profile.rebuilt is not None
    assert profile.rebuilt.path == (tmp_path / "rebuilt.bin").resolve()
    assert profile.rebuilt_identity is not None
```

- [ ] **Step 4: Run the tests to verify the first one fails**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_profile.py -q -k rebuilt
```

Expected: `test_load_profile_allows_missing_rebuilt` FAILS with `jsonschema.exceptions.ValidationError: 'rebuilt' is a required property`. `test_load_profile_still_loads_rebuilt_when_present` passes.

- [ ] **Step 5: Drop `rebuilt` from the schema's required list**

In `tools/binrecon/binrecon/schema/profile-v1.json`, change the `required` array from:

```json
  "required": [
    "schema_version",
    "name",
    "architecture",
    "reference",
    "rebuilt",
    "analyzers",
    "comparison",
    "output_dir"
  ],
```

to:

```json
  "required": [
    "schema_version",
    "name",
    "architecture",
    "reference",
    "analyzers",
    "comparison",
    "output_dir"
  ],
```

Leave the `rebuilt` entry under `properties` exactly as it is — a rebuilt artifact is still valid, just no longer mandatory.

- [ ] **Step 6: Make the loader tolerate the missing key**

In `tools/binrecon/binrecon/profile.py`, change the two `Profile` field declarations:

```python
    rebuilt: ArtifactSpec | None
```

```python
    rebuilt_identity: InputIdentity | None
```

Then replace the unconditional load at lines 47-48:

```python
    rebuilt, rebuilt_identity = _load_artifact(
        "rebuilt", document["rebuilt"], base_dir, environ
    )
```

with:

```python
    if "rebuilt" in document:
        rebuilt, rebuilt_identity = _load_artifact(
            "rebuilt", document["rebuilt"], base_dir, environ
        )
    else:
        rebuilt, rebuilt_identity = None, None
```

The `Profile(...)` construction at lines 57 and 61 already passes these names through and needs no change.

- [ ] **Step 7: Run the full suite**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```

Expected: **609 passed, 4 skipped, 1 failed** — the two new tests added to the 607 baseline, with the known pre-existing failure unchanged. The runner and CLI tests must stay green; they already exercise the rebuilt-present path.

- [ ] **Step 8: Commit**

```bash
git add tools/binrecon/binrecon/schema/profile-v1.json tools/binrecon/binrecon/profile.py tools/binrecon/tests/test_profile.py
git commit -m "binrecon: allow profiles without a rebuilt artifact

The runner already handled a null rebuilt artifact; only the schema and
loader required one."
```

---

### Task 2: Stop tracking generated analyzer output

`tools/binrecon/out/` is not gitignored, contrary to the README's guarantee. 46 files from the stale eisabus run are tracked, including a 1.2 MB IDA `.i64` database and two `.binrecon-run.lock` files.

**Files:**
- Modify: `.gitignore`
- Delete from index: `tools/binrecon/out/**` (46 files)

**Interfaces:**
- Consumes: nothing.
- Produces: a gitignored `tools/binrecon/out/` that later tasks write into freely.

- [ ] **Step 1: Confirm the current state**

```bash
git ls-files tools/binrecon/out | wc -l
```

Expected: `46`.

- [ ] **Step 2: Add the ignore rule**

Append to `.gitignore`:

```
# binrecon: analyzer output is generated evidence, not source
tools/binrecon/out/
```

- [ ] **Step 3: Untrack the generated files**

```bash
git rm -r --cached --quiet tools/binrecon/out
```

- [ ] **Step 4: Verify the rule takes effect**

```bash
git ls-files tools/binrecon/out | wc -l
git check-ignore -v tools/binrecon/out/eisabus/run-summary.json
```

Expected: `0` from the first command, and the second prints `.gitignore:<n>:tools/binrecon/out/ tools/binrecon/out/eisabus/run-summary.json`.

- [ ] **Step 5: Delete the stale eisabus run from the working tree**

Its "pass" compared the reference against a byte-identical copy of itself and its ledger points at a dead network share. drvEISABus is re-run from scratch in Task 12.

```bash
rm -rf tools/binrecon/out/eisabus
```

- [ ] **Step 6: Commit**

```bash
git add .gitignore
git commit -m "binrecon: stop tracking generated analyzer output

Adds tools/binrecon/out/ to .gitignore and untracks the 46 files from the
stale eisabus run, including a 1.2 MB IDA database."
```

---

### Task 3: Symbol index and source site scanner

The reference binaries retain full symbol tables, so address→name is exact. This task builds the two lookup halves; Task 4 assembles them into a document.

**Files:**
- Create: `tools/binrecon/binrecon/source_map.py`
- Create: `tools/binrecon/tests/test_source_map_builder.py`

**Interfaces:**
- Consumes: `binrecon.macho.read_macho(path) -> dict`, whose `"symbols"` value is a list of `{"name": str, "address": int, "binding": str, "section": str | None}`. `section` is `None` for undefined symbols.
- Produces:
  - `defined_symbols(macho_document: dict) -> dict[int, list[str]]` — address to sorted unique defined names.
  - `source_sites(repo_root: Path, source_dir: Path) -> dict[str, list[tuple[str, int]]]` — symbol name to a list of `(posix_repo_relative_path, line_number)`. Objective-C keys have the form `-[Class selector]` or `+[Class selector]`; C keys have a leading underscore, e.g. `_testSlotForID`.

- [ ] **Step 1: Write the failing tests**

Create `tools/binrecon/tests/test_source_map_builder.py`:

```python
from pathlib import Path

from binrecon.source_map import defined_symbols, source_sites


def test_defined_symbols_groups_names_and_drops_undefined():
    document = {
        "symbols": [
            {"name": "_second", "address": 0x1000, "binding": "local", "section": "__text"},
            {"name": "_first", "address": 0x1000, "binding": "external", "section": "__text"},
            {"name": "_undefined", "address": 0x0, "binding": "external", "section": None},
            {"name": "_later", "address": 0x2000, "binding": "external", "section": "__text"},
        ]
    }

    assert defined_symbols(document) == {
        0x1000: ["_first", "_second"],
        0x2000: ["_later"],
    }


def test_source_sites_finds_objc_methods_and_c_functions(tmp_path):
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "Bus.m").write_text(
        "#import \"Bus.h\"\n"
        "\n"
        "@implementation PCIKernBus\n"
        "\n"
        "- (void)dealloc\n"
        "{\n"
        "}\n"
        "\n"
        "- initForResource:(id)resource item:(int)item shareable:(BOOL)flag\n"
        "{\n"
        "    return self;\n"
        "}\n"
        "\n"
        "+ (void)initialize\n"
        "{\n"
        "}\n"
        "\n"
        "@end\n",
        encoding="utf-8",
    )
    (source_dir / "pci.c").write_text(
        "#include <stdio.h>\n"
        "\n"
        "static int helper(int value);\n"
        "\n"
        "int testSlotForID(unsigned slot)\n"
        "{\n"
        "    return slot;\n"
        "}\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites["-[PCIKernBus dealloc]"] == [("src/driver/Bus.m", 5)]
    assert sites["-[PCIKernBus initForResource:item:shareable:]"] == [
        ("src/driver/Bus.m", 9)
    ]
    assert sites["+[PCIKernBus initialize]"] == [("src/driver/Bus.m", 14)]
    assert sites["_testSlotForID"] == [("src/driver/pci.c", 5)]
    assert "_helper" not in sites
```

The `_helper` assertion matters: `static int helper(int value);` is a forward declaration ending in `;`, and the scanner must skip it rather than record a phantom definition.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_source_map_builder.py -q
```

Expected: FAIL with `ModuleNotFoundError: No module named 'binrecon.source_map'`.

- [ ] **Step 3: Implement the module**

Create `tools/binrecon/binrecon/source_map.py`:

```python
"""Build a source map from a reference analysis and a source tree.

Address-to-name comes from the Mach-O symbol table, which these legacy
driver binaries retain in full. Name-to-source-line comes from scanning
Objective-C implementations and C function definitions.
"""

from pathlib import Path
import re


_IMPLEMENTATION = re.compile(r"^@implementation\s+(\w+)")
_END = re.compile(r"^@end")
_METHOD = re.compile(r"^\s*([-+])\s+(.*)$")
_C_DEFINITION = re.compile(r"^[A-Za-z_][A-Za-z_0-9 \t*]*?\b(\w+)\s*\(")


def defined_symbols(macho_document):
    """Map each address to the sorted unique names defined there.

    Symbols with no section are undefined imports and are skipped.
    """
    index = {}
    for symbol in macho_document["symbols"]:
        if symbol["section"] is None:
            continue
        index.setdefault(symbol["address"], set()).add(symbol["name"])
    return {address: sorted(names) for address, names in index.items()}


def _selector(declaration):
    """Reduce an Objective-C method declaration to its bare selector."""
    text = re.sub(r"\([^()]*\)", " ", declaration)
    text = text.split("{")[0]
    keywords = re.findall(r"(\w+)\s*:", text)
    if keywords:
        return "".join(keyword + ":" for keyword in keywords)
    words = re.findall(r"\w+", text)
    return words[0] if words else None


def _relative_posix(repo_root, path):
    return path.resolve().relative_to(repo_root.resolve()).as_posix()


def source_sites(repo_root, source_dir):
    """Map symbol names to the source locations that define them."""
    sites = {}
    paths = sorted(Path(source_dir).glob("*.m")) + sorted(Path(source_dir).glob("*.c"))
    for path in paths:
        relative = _relative_posix(Path(repo_root), path)
        current_class = None
        for number, line in enumerate(
            path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1
        ):
            implementation = _IMPLEMENTATION.match(line)
            if implementation:
                current_class = implementation.group(1)
                continue
            if _END.match(line):
                current_class = None
                continue

            if current_class is not None:
                method = _METHOD.match(line)
                if method and not line.rstrip().endswith(";"):
                    selector = _selector(method.group(2))
                    if selector:
                        key = f"{method.group(1)}[{current_class} {selector}]"
                        sites.setdefault(key, []).append((relative, number))
                continue

            if line.rstrip().endswith(";") or line.startswith((" ", "\t", "#", "}")):
                continue
            definition = _C_DEFINITION.match(line)
            if definition:
                sites.setdefault("_" + definition.group(1), []).append((relative, number))
    return sites
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_source_map_builder.py -q
```

Expected: 2 passed.

- [ ] **Step 5: Commit**

```bash
git add tools/binrecon/binrecon/source_map.py tools/binrecon/tests/test_source_map_builder.py
git commit -m "binrecon: add symbol index and source site scanner"
```

---

### Task 4: Source map document assembly

Turns the two lookups into a `source-map-v1` document that satisfies the semantic validator.

**Files:**
- Modify: `tools/binrecon/binrecon/source_map.py`
- Test: `tools/binrecon/tests/test_source_map_builder.py`

**Interfaces:**
- Consumes: `defined_symbols`, `source_sites` from Task 3; `binrecon.schema.load_source_map(path, *, reference_analysis, repo_root)`.
- Produces: `build_source_map(reference_analysis: dict, macho_document: dict, sites: dict, *, disputed: set[int] | None = None) -> dict` returning a `source-map-v1` document.

Bucketing rule, one bucket per reference function: address in `disputed` → `boundary_disputed`; exactly one candidate site → `mapped`; two or more → `duplicate_candidates`; zero → `unmapped`.

- [ ] **Step 1: Write the failing test**

Append to `tools/binrecon/tests/test_source_map_builder.py`:

```python
from binrecon.source_map import build_source_map


def _analysis(functions, sha256="A" * 64):
    return {"input": {"sha256": sha256}, "functions": functions}


def _function(address, size, names):
    return {
        "address": address,
        "size": size,
        "names": names,
        "blocks": [],
        "instructions": [],
        "calls": [],
        "confidence": 1.0,
    }


def test_build_source_map_buckets_every_function():
    analysis = _analysis(
        [
            _function(0x1000, 0x10, ["-[PCIKernBus init]"]),
            _function(0x1010, 0x10, ["_PCIBus_VERS_NUM"]),
            _function(0x1020, 0x10, ["_ambiguous"]),
            _function(0x1030, 0x10, ["_disputed"]),
        ]
    )
    macho = {"symbols": []}
    sites = {
        "-[PCIKernBus init]": [("src/driver/Bus.m", 12)],
        "_ambiguous": [("src/driver/a.c", 3), ("src/driver/b.c", 7)],
        "_disputed": [("src/driver/c.c", 5)],
    }

    document = build_source_map(analysis, macho, sites, disputed={0x1030})

    assert document["schema_version"] == "source-map-v1"
    assert document["reference_sha256"] == "A" * 64
    assert document["mapped"] == [
        {
            "address": 0x1000,
            "size": 0x10,
            "reference_names": ["-[PCIKernBus init]"],
            "source_path": "src/driver/Bus.m",
            "source_line": 12,
        }
    ]
    assert [entry["address"] for entry in document["unmapped"]] == [0x1010]
    assert [entry["address"] for entry in document["duplicate_candidates"]] == [0x1020]
    assert [entry["address"] for entry in document["boundary_disputed"]] == [0x1030]


def test_symbol_table_names_drive_lookup_without_entering_reference_names():
    """The analysis calls it sub_2000; the symbol table knows it as _helper.

    Lookup must succeed via the symbol-table name, but reference_names must
    still mirror the analysis exactly or schema.py:267 rejects the document.
    """
    analysis = _analysis([_function(0x2000, 0x10, ["sub_2000"])])
    macho = {
        "symbols": [
            {
                "name": "_helper",
                "address": 0x2000,
                "binding": "local",
                "section": "__TEXT,__text",
            }
        ]
    }

    document = build_source_map(analysis, macho, {"_helper": [("src/driver/x.c", 4)]})

    assert document["mapped"][0]["reference_names"] == ["sub_2000"]
    assert document["mapped"][0]["source_path"] == "src/driver/x.c"
    assert document["mapped"][0]["source_line"] == 4


def test_build_source_map_rejects_a_nameless_analysis_function():
    analysis = _analysis([_function(0x3000, 0x10, [])])

    with pytest.raises(ValueError, match="has no names"):
        build_source_map(analysis, {"symbols": []}, {})
```

Add `import pytest` at the top of the test file if it is not already there.

- [ ] **Step 2: Run the test to verify it fails**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_source_map_builder.py -q -k build_source_map
```

Expected: FAIL with `ImportError: cannot import name 'build_source_map'`.

- [ ] **Step 3: Implement the assembler**

Append to `tools/binrecon/binrecon/source_map.py`:

```python
def build_source_map(reference_analysis, macho_document, sites, *, disputed=None):
    """Partition every reference function into exactly one source-map bucket."""
    disputed = set() if disputed is None else disputed
    symbols = defined_symbols(macho_document)
    mapped, unmapped, duplicates, boundary = [], [], [], []

    for function in reference_analysis["functions"]:
        address = function["address"]
        # reference_names must mirror the analysis exactly: schema.py:267 requires
        # entry["reference_names"] == sorted(expected["names"]). Symbol-table names
        # still drive site lookup, they just don't enter the output field.
        names = sorted(function["names"])
        if not names:
            raise ValueError(
                f"analysis function at address {address} has no names; "
                "source-map-v1 requires at least one and the semantic validator "
                "requires an exact match against the analysis"
            )
        entry = {
            "address": address,
            "size": function["size"],
            "reference_names": names,
        }

        lookup = set(names) | set(symbols.get(address, []))
        candidates = sorted({site for name in lookup for site in sites.get(name, [])})

        if address in disputed:
            boundary.append(
                {**entry, "reasons": ["analyzers disagree on function extent"]}
            )
        elif len(candidates) == 1:
            path, line = candidates[0]
            mapped.append({**entry, "source_path": path, "source_line": line})
        elif candidates:
            duplicates.append(
                {
                    **entry,
                    "candidates": [
                        {"source_path": path, "source_line": line}
                        for path, line in candidates
                    ],
                    "reasons": ["symbol name resolves to multiple definitions"],
                }
            )
        else:
            unmapped.append(entry)

    return {
        "schema_version": "source-map-v1",
        "reference_sha256": reference_analysis["input"]["sha256"].upper(),
        "mapped": _canonical(mapped),
        "unmapped": _canonical(unmapped),
        "duplicate_candidates": _canonical(duplicates),
        "boundary_disputed": _canonical(boundary),
    }


def _canonical(entries):
    """Sort entries the way the semantic validator requires."""
    return sorted(
        entries, key=lambda entry: (entry["address"], tuple(entry["reference_names"]))
    )
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_source_map_builder.py -q
```

Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
git add tools/binrecon/binrecon/source_map.py tools/binrecon/tests/test_source_map_builder.py
git commit -m "binrecon: assemble source-map-v1 documents from analysis and sources"
```

---

### Task 5: `binrecon source-map` subcommand

Makes the report passes reproducible from the command line instead of ad-hoc scripts.

**Files:**
- Modify: `tools/binrecon/binrecon/cli.py:50-54`
- Test: `tools/binrecon/tests/test_cli.py`

**Interfaces:**
- Consumes: `build_source_map`, `source_sites` from Tasks 3-4; `binrecon.macho.read_macho`.
- Produces: CLI `binrecon source-map --reference-analysis PATH --binary PATH --source-dir PATH --repo-root PATH --output PATH`, writing a validated `source-map-v1` document and exiting 0.

- [ ] **Step 0: Fix `validate` crashing on a reference-only profile**

Task 1 made `rebuilt_identity` optional but did not update the `validate` command, which iterates both identities and dereferences `identity.path`. Against a profile with no `rebuilt`, it prints the reference line and then dies:

```
AttributeError: 'NoneType' object has no attribute 'path'
```

at `cli.py:73`. Task 6 Step 2 runs exactly this command, so it must be fixed first. In `main`, skip a `None` identity:

```python
        for label, identity in (
            ("reference", profile.reference_identity),
            ("rebuilt", profile.rebuilt_identity),
        ):
            if identity is None:
                continue
            print(
                f"{label} {identity.path} size={identity.size} "
                f"sha256={identity.sha256}"
            )
```

Add a test in `tools/binrecon/tests/test_cli.py` that `validate` on a profile without `rebuilt` returns 0 and prints only a `reference ...` line. Confirm the test fails before the fix.

- [ ] **Step 1: Write the failing test**

Append to `tools/binrecon/tests/test_cli.py`:

```python
def test_source_map_command_writes_validated_document(tmp_path, monkeypatch):
    import json

    from binrecon.cli import main

    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "bus.c").write_text(
        "int testSlotForID(unsigned slot)\n{\n    return slot;\n}\n", encoding="utf-8"
    )
    analysis_path = tmp_path / "reference.analysis.json"
    analysis_path.write_text(
        json.dumps(
            {
                "input": {"sha256": "B" * 64},
                "functions": [
                    {
                        "address": 4096,
                        "size": 16,
                        "names": ["_testSlotForID"],
                        "blocks": [],
                        "instructions": [],
                        "calls": [],
                        "confidence": 1.0,
                    }
                ],
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr("binrecon.cli.read_macho", lambda path: {"symbols": []})
    output_path = tmp_path / "source-map.json"

    exit_code = main(
        [
            "source-map",
            "--reference-analysis", str(analysis_path),
            "--binary", str(analysis_path),
            "--source-dir", str(source_dir),
            "--repo-root", str(tmp_path),
            "--output", str(output_path),
        ]
    )

    assert exit_code == 0
    document = json.loads(output_path.read_text(encoding="utf-8"))
    assert document["schema_version"] == "source-map-v1"
    assert document["mapped"][0]["source_path"] == "src/driver/bus.c"
    assert document["mapped"][0]["source_line"] == 1
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_cli.py -q -k source_map
```

Expected: FAIL — argparse exits with `invalid choice: 'source-map'`.

- [ ] **Step 3: Register the subcommand**

In `tools/binrecon/binrecon/cli.py`, add these imports near the existing ones:

```python
from binrecon.macho import read_macho
from binrecon.source_map import build_source_map, source_sites
```

After the `consensus` parser block (currently ending at line 54), add:

```python
    source_map = subparsers.add_parser("source-map")
    source_map.add_argument("--reference-analysis", required=True)
    source_map.add_argument("--binary", required=True)
    source_map.add_argument("--source-dir", required=True)
    source_map.add_argument("--repo-root", required=True)
    source_map.add_argument("--output", required=True)
```

- [ ] **Step 4: Implement the handler**

Add a handler function alongside the other command handlers in `cli.py`:

```python
def _source_map_command(arguments):
    from pathlib import Path

    from binrecon.schema import load_json, load_source_map, write_json

    analysis = load_json(Path(arguments.reference_analysis))
    sites = source_sites(Path(arguments.repo_root), Path(arguments.source_dir))
    document = build_source_map(analysis, read_macho(Path(arguments.binary)), sites)
    write_json(Path(arguments.output), document)
    load_source_map(
        Path(arguments.output),
        reference_analysis=analysis,
        repo_root=Path(arguments.repo_root),
    )
    return 0
```

Then dispatch it from `main` in the same style as the existing commands:

```python
    if arguments.command == "source-map":
        return _source_map_command(arguments)
```

If `binrecon.schema` has no `write_json`, use `Path(arguments.output).write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")` with `import json` at module scope, matching how other commands serialize.

- [ ] **Step 5: Run the full suite**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```

Expected: the running total plus your new test, with only the known pre-existing failure still red.

- [ ] **Step 6: Commit**

```bash
git add tools/binrecon/binrecon/cli.py tools/binrecon/tests/test_cli.py
git commit -m "binrecon: add source-map subcommand"
```

---

### Task 6: drvPCIBus profile and reference analysis

drvPCIBus is the smallest driver (39 defined symbols, 21 methods) and the README already marks it complete, so it calibrates the conventions cheaply.

**Files:**
- Create: `tools/binrecon/profiles/pcibus.json`

**Interfaces:**
- Consumes: reference-only profile support from Task 1.
- Produces: `tools/binrecon/out/pcibus/published/analysis-reference-{ida,ghidra,angr}.json` and `consensus-reference.json`.

- [ ] **Step 1: Write the profile**

Create `tools/binrecon/profiles/pcibus.json`:

```json
{
  "schema_version": "profile-v1",
  "name": "drvPCIBus reconstruction",
  "architecture": "i386",
  "endianness": "little",
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
      "enabled": true,
      "executable": "D:/ghidra/support/analyzeHeadless.bat",
      "timeout_seconds": 900,
      "version": "12.1"
    },
    "angr": {
      "enabled": true,
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
  "output_dir": "../out/pcibus"
}
```

- [ ] **Step 2: Validate the profile resolves with no rebuilt artifact**

Run from the repository root:

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/PCIBus.config/PCIBus_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon validate --profile tools/binrecon/profiles/pcibus.json
```

Expected: prints the reference absolute path, size `41360`, and its SHA-256. No rebuilt artifact is reported. Exit code 0.

- [ ] **Step 3: Run the analyzers**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/PCIBus.config/PCIBus_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon analyze --profile tools/binrecon/profiles/pcibus.json
```

Expected: **exit code 1**, with `run-summary.json` showing `"complete": true`, `"rebuilt_sha256": null`, `"comparisons": []`, and `"acceptance": {"passed": false, ...}`.

Exit 1 is the correct outcome for every reference-only run and is not a failure. [runner.py:259](tools/binrecon/binrecon/runner.py:259) computes `expected_pass = bool(comparisons) and all(...)`, so with nothing compared the acceptance is `false`, and line 262 *enforces* that it stay `false` — the tool refuses to report acceptance as passed when no comparison happened. That conservatism is deliberate and is exactly what the stale eisabus run lacked.

**The real gate for this task** is therefore: `"complete": true`, a `published/` directory holding `analysis-reference-{ida,ghidra,angr}.json` plus `consensus-reference.json`, and `"reference"` non-null for all three analyzers. Judge success on those, not the exit code.

If Ghidra's Mach-O loader rejects the input, the adapter falls back to deterministic raw i386 import — expected, not a failure. If a run times out, the summary is marked `"complete": false`; fix the cause and re-run rather than proceeding.

**Do not launch `analyze` from a subagent that then exits** — the run is a long-lived child process and dies with its parent. Run it as a detached background task owned by the session.

- [ ] **Step 4: Confirm the published output**

```bash
ls tools/binrecon/out/pcibus/published/
git status --porcelain tools/binrecon/out
```

Expected: the three `analysis-reference-*.json` files plus `consensus-reference.json`; `git status` prints nothing, confirming Task 2's ignore rule holds.

- [ ] **Step 5: Commit**

```bash
git add tools/binrecon/profiles/pcibus.json
git commit -m "binrecon: add drvPCIBus reference-only profile"
```

---

### Task 7: drvPCIBus report pass

**Files:**
- Create: `src/drivers-i386/bus/drvPCIBus/reconstruction/source-map.json`
- Create: `src/drivers-i386/bus/drvPCIBus/reconstruction/ledger.json`
- Create: `src/drivers-i386/bus/drvPCIBus/reconstruction/divergences.md`

**Interfaces:**
- Consumes: the `source-map` subcommand from Task 5 and the analyses from Task 6.
- Produces: a validated source map and a ledger entry for every function, establishing the conventions Tasks 9 and 12 reuse.

- [ ] **Step 1: Generate the source map**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon source-map \
  --reference-analysis tools/binrecon/out/pcibus/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/i386/PCIBus.config/PCIBus_reloc" \
  --source-dir src/drivers-i386/bus/drvPCIBus/PCIBus.drvproj/PCIBus.lksproj \
  --repo-root . \
  --output src/drivers-i386/bus/drvPCIBus/reconstruction/source-map.json
```

Expected: exit code 0. A non-zero exit means the semantic validator rejected the document — read the `SemanticValidationError` message, which names the exact failing constraint.

- [ ] **Step 2: Review the buckets**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
import json
d = json.load(open('src/drivers-i386/bus/drvPCIBus/reconstruction/source-map.json'))
for key in ('mapped', 'unmapped', 'duplicate_candidates', 'boundary_disputed'):
    print(key, len(d[key]))
for entry in d['unmapped']:
    print('  unmapped:', entry['reference_names'])
"
```

Expected: the `unmapped` list contains `+[PCIBusKernelServerInstance kernelServerInstance]`, `+[PCIBusVersion driverKitVersionForPCIBus]`, `_PCIBus_VERS_NUM`, `_PCIBus_VERS_STRING`, and `_PCIBus_instance` — all build-generated. Anything else unmapped is a finding for Step 4.

Resolve every `duplicate_candidates` entry by hand: pick the correct site, move the entry to `mapped` with that `source_path`/`source_line`, and re-run Step 1's validation via the loader. Keep each array sorted by `(address, reference_names)`.

- [ ] **Step 3: Decompile-diff every mapped function**

Work in batches, one source file at a time, in this order: `pci.c`, `PCIKernBus.m`, `PCIKernBusPrivate.m`, `PCIResourceDriver.m`.

For each mapped function, compare the reference decompilation against our source on: control-flow shape, literal constants, I/O port addresses, struct field offsets, and call targets. The reference decompilation for address `A` comes from the published IDA and Ghidra analyses; where the two disagree on a function's body, record the disagreement rather than choosing one.

A function matches at one of three levels, which become its ledger status:
- `signature-confirmed` — name and signature agree, body not yet compared.
- `control-flow-confirmed` — block structure and call targets agree.
- `assembly-matched` — instruction-level agreement.

- [ ] **Step 4: Write `divergences.md`**

Create `src/drivers-i386/bus/drvPCIBus/reconstruction/divergences.md` using this structure, one section per finding:

```markdown
# drvPCIBus divergences

Reference: `PCIBus_reloc`, SHA-256 `<uppercase hash from the source map>`
Analyses: IDA 9.2, Ghidra 12.1, angr 9.3.0

## Summary

| Bucket | Count |
| --- | --- |
| mapped | N |
| unmapped | N |
| duplicate_candidates | N |
| boundary_disputed | N |

## Unmapped: build-generated

`+[PCIBusKernelServerInstance kernelServerInstance]`,
`+[PCIBusVersion driverKitVersionForPCIBus]`, `_PCIBus_VERS_NUM`,
`_PCIBus_VERS_STRING`, `_PCIBus_instance` — emitted by the Kernel Server
project type and `Load_Commands.sect`, not written by hand. Accepted.

## Finding 1: <function name> at 0x<address>

**Source:** `src/drivers-i386/bus/drvPCIBus/PCIBus.drvproj/PCIBus.lksproj/<file>:<line>`

**Reference behaviour**

<decompilation excerpt>

**Our source**

<source excerpt>

**Difference:** <what differs, concretely>

**Disposition:** fix | accept

**Rationale:** <why>
```

- [ ] **Step 5: Create the ledger**

Every function needs an entry. Set matching functions to the status Step 3 established. Leave diverging functions at `unexamined` — the fix pass advances them. Accepted divergences get `intentional-mismatch`, which requires both a reason and a reviewer:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/pcibus.json \
  --ledger src/drivers-i386/bus/drvPCIBus/reconstruction/ledger.json \
  --address 0x<address> --status intentional-mismatch \
  --reason "build-generated kernel server glue, not present in source" \
  --reviewer "<your name>"
```

`rebuilt_sha256` stays `null` throughout, which `ledger-v1` permits.

- [ ] **Step 6: Verify the source map against the reference analysis**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.schema import load_json, load_source_map
analysis = load_json(Path('tools/binrecon/out/pcibus/published/analysis-reference-ida.json'))
load_source_map(
    Path('src/drivers-i386/bus/drvPCIBus/reconstruction/source-map.json'),
    reference_analysis=analysis,
    repo_root=Path.cwd(),
)
print('source map valid')
"
```

Expected: `source map valid`. This enforces the complete function partition, names, sizes, and source-line bounds.

- [ ] **Step 7: Commit**

```bash
git add src/drivers-i386/bus/drvPCIBus/reconstruction
git commit -m "drvPCIBus: add reconstruction source map, ledger and divergence report"
```

---

### Task 8: Guest build script and drvPCIBus baseline

Establishes that each driver built cleanly *before* any source edits, so a pre-existing failure is never misattributed to a fix.

**Files:**
- Create: `vm/build-i386-bus-drivers.sh`
- Modify: `docs/superpowers/specs/2026-07-25-bus-driver-binary-reconstruction-design.md`

**Interfaces:**
- Consumes: the guest conventions in `vm/build-i386-kernel-eide.sh`.
- Produces: `out/i386/drv<Name>/<Name>.config/<Name>_reloc` for each driver named on the command line, plus `out/i386/drv<Name>-build.log`.

- [ ] **Step 1: Write the build script**

All three drivers use the same Aggregate → `.drvproj` → `.lksproj` structure as drvEIDE, so one script covers them. Create `vm/build-i386-bus-drivers.sh`:

```sh
#!/bin/sh
# Build the i386 bus drivers on the Rhapsody guest; stage artifacts.
# Usage: build-i386-bus-drivers.sh drvPCIBus [drvPCMCIABus ...]
set -e
export PATH=/build/bin:/usr/local/bin:/build/tools/usr/local/bin:/build/tools/usr/bin:/bin:/usr/bin:/sbin:/usr/sbin

if [ $# -eq 0 ]; then
	echo "usage: $0 drvPCIBus [drvPCMCIABus ...]" >&2
	exit 1
fi

if [ -x /usr/bin/gnumake ] && [ ! -x /usr/local/bin/make ]; then
	mkdir -p /usr/local/bin
	ln -sf /usr/bin/gnumake /usr/local/bin/make
fi

OUT=/build/out/i386
mkdir -p "$OUT"

for driver in "$@"; do
	D=/build/source/src/drivers-i386/bus/$driver
	if [ ! -f "$D/Makefile" ]; then
		echo "missing $D/Makefile" >&2
		exit 1
	fi

	# Strip CR from makefiles under this tree (Windows sync).
	find "$D" -type f \( -name Makefile -o -name 'Makefile.*' -o -name '*.make' \) -print |
	while read f; do
		tr -d '\r' < "$f" > /tmp/rhap_cr && mv /tmp/rhap_cr "$f"
	done

	echo "=== build $driver ==="
	cd "$D"
	rm -rf "/tmp/$driver-dst"
	mkdir -p "/tmp/$driver-dst"
	gnumake clean 2>/dev/null || true
	gnumake DSTROOT="/tmp/$driver-dst" install 2>&1 | tee "$OUT/$driver-build.log"

	mkdir -p "$OUT/$driver"
	find "/tmp/$driver-dst" -type d -name '*.config' -print > /tmp/found
	if [ ! -s /tmp/found ]; then
		echo "no .config produced for $driver" >&2
		find "/tmp/$driver-dst" | head -80 >&2
		exit 1
	fi
	while read d; do
		echo "found $d"
		cp -rp "$d" "$OUT/$driver/"
	done < /tmp/found
done

echo "=== artifacts ==="
find "$OUT" -name '*_reloc' -print | sort
echo "=== build-i386-bus-drivers done ==="
```

- [ ] **Step 2: Record the existing baseline**

All three drivers have **already been built clean** and staged to `out/i386/` outside this plan:

| Driver | Artifact | Size |
| --- | --- | --- |
| drvPCIBus | `out/i386/drvPCIBus/PCIBus.config/PCIBus_reloc` | 155312 |
| drvPCMCIABus | `out/i386/drvPCMCIABus/PCMCIABus.config/PCMCIABus_reloc` | 344196 |
| drvEISABus | `out/i386/drvEISABus/EISABus.config/EISABus_reloc` | 577656 |

These are larger than the references because they are unstripped; the plan never compares them byte-for-byte. Their existence satisfies the baseline gate for all three drivers — **drvPCMCIABus does compile**, contrary to the README's "needs compiled and then tested".

Confirm they are still present, then record a `## Baseline build` section in each driver's `divergences.md` noting the artifact and size. Do not run a guest build in this task — the QEMU guest is currently in use by another session.

```bash
find out/i386 -name '*_reloc' -exec ls -la {} \;
```

- [ ] **Step 3: Add the builder to the spec's deliverables**

The spec's §7 does not list the source-map builder added in Tasks 3-5. Under "Repository-wide", after the reference-only mode line, add:

```markdown
- `binrecon.source_map` builder and the `binrecon source-map` subcommand
```

- [ ] **Step 4: Commit**

```bash
git add vm/build-i386-bus-drivers.sh docs/superpowers/specs/2026-07-25-bus-driver-binary-reconstruction-design.md
git commit -m "vm: add i386 bus driver build script

Builds and stages drvPCIBus, drvPCMCIABus and drvEISABus on the guest."
```

---

### Task 9: drvPCIBus fix pass

**Files:**
- Modify: files named in `src/drivers-i386/bus/drvPCIBus/reconstruction/divergences.md`
- Modify: `src/drivers-i386/bus/drvPCIBus/reconstruction/ledger.json`

**Interfaces:**
- Consumes: the divergence findings from Task 7 and the build script from Task 8.
- Produces: source changes plus advanced ledger statuses.

- [ ] **Step 1: Confirm the baseline build passed**

Re-read the `## Baseline build` section of `divergences.md`. If it records a failure, stop and fix the build breakage as its own commit first.

- [ ] **Step 2: Apply each fix marked `fix`**

Work one finding at a time, in `divergences.md` order. Change only the lines the finding names. Do not reformat, rename, or clean up adjacent code.

- [ ] **Step 3: Rebuild**

```bash
sh /build/source/vm/build-i386-bus-drivers.sh drvPCIBus
```

Expected: exit 0 and `PCIBus_reloc` produced. Compare the warning count in `/build/out/i386/drvPCIBus-build.log` against the baseline log; new warnings are reviewed but do not gate.

- [ ] **Step 4: Advance the ledger**

For each fixed function, set the status to the level the change now supports:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/pcibus.json \
  --ledger src/drivers-i386/bus/drvPCIBus/reconstruction/ledger.json \
  --address 0x<address> --status control-flow-confirmed \
  --source-path src/drivers-i386/bus/drvPCIBus/PCIBus.drvproj/PCIBus.lksproj/<file> \
  --source-line <line>
```

`--source-path` and `--source-line` must be supplied together.

- [ ] **Step 5: Record the outcome**

In `divergences.md`, append to each finding a `**Outcome:**` line stating what changed and the new ledger status.

- [ ] **Step 6: Commit**

```bash
git add src/drivers-i386/bus/drvPCIBus
git commit -m "drvPCIBus: align source with reference binary

Applies the divergences confirmed by the reconstruction report pass."
```

---

### Task 10: drvPCMCIABus report pass

Second driver, 97 defined symbols and 65 methods. Scoping already found `_parseIDTable` and `_parseTable` defined in the reference and absent from our source under any name.

**Files:**
- Create: `tools/binrecon/profiles/pcmciabus.json`
- Create: `src/drivers-i386/bus/drvPCMCIABus/reconstruction/{source-map.json,ledger.json,divergences.md}`

**Interfaces:**
- Consumes: the conventions established in Tasks 6-7.
- Produces: the same three artifacts for drvPCMCIABus.

- [ ] **Step 1: Write the profile**

Copy `tools/binrecon/profiles/pcibus.json` to `tools/binrecon/profiles/pcmciabus.json` and change exactly two fields:

```json
  "name": "drvPCMCIABus reconstruction",
```

```json
  "output_dir": "../out/pcmciabus"
```

- [ ] **Step 2: Validate and analyze**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/PCMCIABus.config/PCMCIABus_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon validate --profile tools/binrecon/profiles/pcmciabus.json
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/PCMCIABus.config/PCMCIABus_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon analyze --profile tools/binrecon/profiles/pcmciabus.json
```

Expected: `validate` reports size `92192`; `analyze` exits **1** with `"complete": true` and `"acceptance": {"passed": false}` — see Task 6 Step 3 for why exit 1 is the correct outcome of a reference-only run. Gate on `complete` and the published artifacts, not the exit code.

- [ ] **Step 3: Generate the source map**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon source-map \
  --reference-analysis tools/binrecon/out/pcmciabus/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/i386/PCMCIABus.config/PCMCIABus_reloc" \
  --source-dir src/drivers-i386/bus/drvPCMCIABus/PCMCIABus.drvproj/PCMCIABus.lksproj \
  --repo-root . \
  --output src/drivers-i386/bus/drvPCMCIABus/reconstruction/source-map.json
```

Expected: exit 0.

- [ ] **Step 4: Confirm the expected unmapped set**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
import json
d = json.load(open('src/drivers-i386/bus/drvPCMCIABus/reconstruction/source-map.json'))
for entry in d['unmapped']:
    print(entry['reference_names'], hex(entry['address']))
"
```

Expected to include the build-generated set (`+[PCMCIABusKernelServerInstance kernelServerInstance]`, `+[PCMCIABusVersion driverKitVersionForPCMCIABus]`, `_PCMCIABus_VERS_NUM`, `_PCMCIABus_VERS_STRING`, `_PCMCIABus_instance`) **plus `_parseIDTable` and `_parseTable`**, which are real missing code, not glue.

- [ ] **Step 5: Decompile-diff every mapped function**

Batch by source file, in this order: `PCMCIAKernBus.m`, `PCMCIAKernBusParsing.m`, `PCMCIAKernBusPrivate.m`, `PCMCIATuple.m`, `PCMCIATupleTypes.m`, `PCMCIAConfigEntry.m`, `PCMCIAPool.m`, `PCMCIAPoolElement.m`, `PCMCIAid.m`, `PCMCIAResourceDriver.m`. Apply the same three confidence levels as Task 7 Step 3.

- [ ] **Step 6: Write `divergences.md` and the ledger**

Use the identical structure given in Task 7 Step 4, with `drvPCMCIABus` and its reference hash. Give `_parseIDTable` and `_parseTable` their own findings documenting what the reference does and what calls them. Create the ledger as in Task 7 Step 5.

- [ ] **Step 7: Validate the source map**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.schema import load_json, load_source_map
analysis = load_json(Path('tools/binrecon/out/pcmciabus/published/analysis-reference-ida.json'))
load_source_map(
    Path('src/drivers-i386/bus/drvPCMCIABus/reconstruction/source-map.json'),
    reference_analysis=analysis,
    repo_root=Path.cwd(),
)
print('source map valid')
"
```

Expected: `source map valid`.

- [ ] **Step 8: Commit**

```bash
git add tools/binrecon/profiles/pcmciabus.json src/drivers-i386/bus/drvPCMCIABus/reconstruction
git commit -m "drvPCMCIABus: add reconstruction source map, ledger and divergence report"
```

---

### Task 11: drvPCMCIABus fix pass

The README marks this driver "needs compiled and then tested" — it may never have been built, so the baseline may fail.

**Files:**
- Modify: files named in `src/drivers-i386/bus/drvPCMCIABus/reconstruction/divergences.md`
- Modify: `src/drivers-i386/bus/drvPCMCIABus/reconstruction/ledger.json`

**Interfaces:**
- Consumes: the findings from Task 10 and the build script from Task 8.
- Produces: source changes plus advanced ledger statuses.

- [ ] **Step 1: Run the baseline build before any edits**

```bash
sh /build/source/vm/build-i386-bus-drivers.sh drvPCMCIABus
```

Record the result under `## Baseline build` in `divergences.md`.

- [ ] **Step 2: If the baseline failed, repair the build first**

Fix only what blocks compilation. Re-run Step 1 until it exits 0, then commit separately:

```bash
git add src/drivers-i386/bus/drvPCMCIABus
git commit -m "drvPCMCIABus: fix build breakage

Pre-existing failures found by the reconstruction baseline build."
```

- [ ] **Step 3: Apply each fix marked `fix`**

One finding at a time, in `divergences.md` order. Restoring `_parseIDTable` and `_parseTable` is expected to be the largest change; implement them from the reference decompilation recorded in Task 10.

- [ ] **Step 4: Rebuild**

```bash
sh /build/source/vm/build-i386-bus-drivers.sh drvPCMCIABus
```

Expected: exit 0 and `PCMCIABus_reloc` produced.

- [ ] **Step 5: Advance the ledger and record outcomes**

Same commands and `**Outcome:**` lines as Task 9 Steps 4-5, against `tools/binrecon/profiles/pcmciabus.json` and the drvPCMCIABus ledger.

- [ ] **Step 6: Commit**

```bash
git add src/drivers-i386/bus/drvPCMCIABus
git commit -m "drvPCMCIABus: align source with reference binary

Restores the table parsers and applies the confirmed divergences."
```

---

### Task 12: drvEISABus report pass

The largest driver: 209 defined symbols, 144 methods. Scoping found that its PnP BIOS layer is architecturally different from the reference, which is the leading crash candidate.

**Files:**
- Create: `tools/binrecon/profiles/eisabus.json`
- Create: `src/drivers-i386/bus/drvEISABus/reconstruction/{source-map.json,ledger.json,divergences.md}`

**Interfaces:**
- Consumes: the conventions from Tasks 6-7 and 10.
- Produces: the same three artifacts plus the evidence for the Task 13 go/no-go.

- [ ] **Step 1: Write the profile**

Copy `tools/binrecon/profiles/pcibus.json` to `tools/binrecon/profiles/eisabus.json` and change exactly two fields:

```json
  "name": "drvEISABus reconstruction",
```

```json
  "output_dir": "../out/eisabus"
```

Task 2 deleted the stale `out/eisabus` directory, so this run starts clean.

- [ ] **Step 2: Validate and analyze**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/EISABus.config/EISABus_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon validate --profile tools/binrecon/profiles/eisabus.json
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/i386/EISABus.config/EISABus_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon analyze --profile tools/binrecon/profiles/eisabus.json
```

Expected: `validate` reports size `100752` and SHA-256 `8F252AF66CD49A8E03B51E57E90CB613D0B9DC1602263F4B7B6393E483977B23`; `analyze` exits **1** with `"complete": true` and `"rebuilt_sha256": null` — see Task 6 Step 3 for why exit 1 is the correct outcome of a reference-only run. Gate on `complete` and the published artifacts.

- [ ] **Step 3: Generate the source map**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon source-map \
  --reference-analysis tools/binrecon/out/eisabus/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/i386/EISABus.config/EISABus_reloc" \
  --source-dir src/drivers-i386/bus/drvEISABus/EISABus.drvproj/EISABus.lksproj \
  --repo-root . \
  --output src/drivers-i386/bus/drvEISABus/reconstruction/source-map.json
```

Expected: exit 0.

- [ ] **Step 4: Confirm the known gaps appear as unmapped**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
import json
d = json.load(open('src/drivers-i386/bus/drvEISABus/reconstruction/source-map.json'))
for entry in d['unmapped']:
    print(entry['reference_names'], hex(entry['address']), entry['size'])
"
```

Expected to include `-[PnPArgStack initWithData:Selector:]`, `-[PnPArgStack pushFarPtr:]`, `-[PnPBios releaseSegments]`, and `_call_bios`, alongside the build-generated set. The register-save globals (`save_es`, `save_eax`, `save_ecx`, `save_edx`, `save_flag`, `new_eax`, `new_edx`, `save_seg`, `save_addr`, `targ_addr`) are data, not functions, and will not appear in the function partition — note them in `divergences.md` regardless, since `_call_bios` depends on them.

- [ ] **Step 5: Decompile-diff every mapped function**

Batch by source file, in this order: `bios.c`, `eisa.c`, `PnPBios.m`, `PnPResource.m`, `PnPResources.m`, `PnPDeviceResources.m`, `PnPDependentResources.m`, `PnPLogicalDevice.m`, `pnpDMA.m`, `pnpIOPort.m`, `pnpIRQ.m`, `pnpMemory.m`, `EISAKernBus.m`, `EISAKernBus+PlugAndPlay.m`, `EISAKernBus+PlugAndPlayPrivate.m`, `EISAKernBusDMAChannel.m`, `EISAKernBusInterrupt.m`, `EISAKernBusPortRange.m`, `EISAResourceDriver.m`.

Give `bios.c` and `PnPBios.m` particular attention. Our `bios.c` is an independent rewrite whose comment describes it as matching the Linux kernel, using GCC inline `__asm__` where the reference uses a `_call_bios` thunk with named register-save globals. Document the calling-convention difference concretely: how the reference marshals arguments through `PnPArgStack`, how it enters real mode, and what our version does instead.

- [ ] **Step 6: Write `divergences.md` and the ledger**

Same structure as Task 7 Step 4. Add a `## Crash candidates` section ranking the divergences by how plausibly each explains the "crashing, needs debugging" status, with the PnP BIOS calling convention assessed explicitly.

- [ ] **Step 7: Validate the source map**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.schema import load_json, load_source_map
analysis = load_json(Path('tools/binrecon/out/eisabus/published/analysis-reference-ida.json'))
load_source_map(
    Path('src/drivers-i386/bus/drvEISABus/reconstruction/source-map.json'),
    reference_analysis=analysis,
    repo_root=Path.cwd(),
)
print('source map valid')
"
```

Expected: `source map valid`.

- [ ] **Step 8: Repoint the committed-source-map test**

`tools/binrecon/tests/test_source_map.py:320` expects the EISABus source map at the pre-`src/` path and has been failing since the tooling landed — no such file has ever existed in git history. The map produced by this task is exactly what it wants. Change line 320 from:

```python
    source_map = repo_root / "src/drivers/x86/bus/drvEISABus/reconstruction/source-map.json"
```

to:

```python
    source_map = repo_root / "src/drivers-i386/bus/drvEISABus/reconstruction/source-map.json"
```

Leave the `reference_sha256` assertion alone — `8F252AF66CD49A8E03B51E57E90CB613D0B9DC1602263F4B7B6393E483977B23` is the correct `EISABus_reloc` hash and your source map must already carry it.

- [ ] **Step 9: Confirm the suite is fully green**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```

Expected: **zero failures** — this is the task that clears the long-standing baseline failure. If it still fails, the source map is at the wrong path or carries the wrong hash.

- [ ] **Step 10: Commit**

```bash
git add tools/binrecon/profiles/eisabus.json tools/binrecon/tests/test_source_map.py src/drivers-i386/bus/drvEISABus/reconstruction
git commit -m "drvEISABus: add reconstruction source map, ledger and divergence report

Also repoints the committed-source-map test at the current tree layout."
```

---

### Task 13: drvEISABus go/no-go, driver docs, README

Reconstructing `PnPArgStack` and the `_call_bios` thunk is closer to new implementation than to fixing divergences. The spec deliberately does not commit to absorbing it; this task makes the call with the report pass's measurements in hand.

**Files:**
- Create: `docs/drivers/drvPCIBus-issues.md`, `docs/drivers/drvPCMCIABus-issues.md`, `docs/drivers/drvEISABus-issues.md`
- Modify: `src/drivers-i386/README`

**Interfaces:**
- Consumes: all three `divergences.md` documents.
- Produces: the human-readable summaries and an explicit decision on the drvEISABus fix pass.

- [ ] **Step 1: Run the drvEISABus baseline build**

```bash
sh /build/source/vm/build-i386-bus-drivers.sh drvEISABus
```

Record the result under `## Baseline build` in the drvEISABus `divergences.md`.

- [ ] **Step 2: Write the three driver summaries**

Follow the structure of the existing `docs/drivers/drvEIDE-issues.md`: a short preamble naming the driver and where its source lives, a numbered section per problem with **Symptom**, **Root cause**, and **Resolution** headings, and independent problems kept separate.

For drvPCIBus and drvPCMCIABus, the resolutions are the fixes landed in Tasks 9 and 11. For drvEISABus, the resolution section states what the report pass found and what remains open.

- [ ] **Step 3: Record the go/no-go decision**

Add a `## Fix pass decision` section to `docs/drivers/drvEISABus-issues.md` stating whether the fix pass proceeds in this effort or splits into its own spec, with the reasoning. Base it on what Task 12 measured: how many functions diverge, how much of `PnPArgStack` and `_call_bios` must be written from scratch, and whether the reference decompilation is complete enough to implement from.

If the decision is **split**, stop after Step 5 and start a new brainstorming cycle for the drvEISABus PnP BIOS reconstruction. If the decision is **proceed**, carry out Task 9's steps against drvEISABus, then return here.

- [ ] **Step 4: Update the driver status lines**

In `src/drivers-i386/README`, replace these three lines under `bus`:

```
 * drvEISABus - crashing, needs debugging
 * drvPICBus - complete
 * drvPCMCIABus - needs compiled and then tested
```

with lines reflecting the actual state after this work. Note that `drvPICBus` is a typo for `drvPCIBus` in the current README — correct it, since this task is what changes that line.

- [ ] **Step 5: Commit**

```bash
git add docs/drivers src/drivers-i386/README
git commit -m "docs: record bus driver reconstruction findings

Adds per-driver issue summaries and updates the driver status list."
```

---

## Plan Self-Review

**Spec coverage.** §1.1 targets → Tasks 6, 10, 12. §1.2 out-of-scope → no tasks, correct. §1.3 retiring the stale run → Task 2 Step 5 and Task 12 Step 1. §2.1 reference-only mode → Task 1. §2.2 committed output → Task 2. §2.3 PnP BIOS gap → Task 12 Steps 4-5, Task 13 Step 3. §2.4 missing parsers → Task 10 Step 4, Task 11 Step 3. §2.5 build-generated residue → Task 7 Step 2. §3.1 committed layout → Tasks 7, 10, 12, 13. §3.2 not-committed → Task 2. §4.1 report pass → Tasks 7, 10, 12. §4.2 fix pass → Tasks 9, 11, 13. §5 failure modes → Task 6 Step 3 (Ghidra fallback, timeouts), Task 7 Step 2 (duplicates), Task 12 Step 2 (env var). §6 sequencing → task order. §7 deliverables → all covered; the builder was missing from the spec and Task 8 Step 3 adds it.

**Placeholder scan.** The `<Name>`, `<address>`, `<file>`, `<line>`, and `<your name>` tokens are per-driver and per-finding substitutions, not unfinished text. `divergences.md` content cannot be pre-written because it records analysis results; Task 7 Step 4 gives the complete document template instead.

**Type consistency.** `defined_symbols(macho_document) -> dict[int, list[str]]` is defined in Task 3 and consumed in Task 4. `source_sites(repo_root, source_dir) -> dict[str, list[tuple[str, int]]]` is defined in Task 3 and consumed in Tasks 4 and 5. `build_source_map(reference_analysis, macho_document, sites, *, disputed=None)` is defined in Task 4 and called with that exact signature in Task 5. Ledger statuses match the enum in every use.

**Known limits, recorded rather than hidden.** The `_selector` helper strips one level of parenthesis nesting, so a method whose argument type is itself a function pointer resolves incorrectly; such cases land in `unmapped` and are caught by human review. The C definition scanner uses the column-zero heuristic, which suits this codebase's style but will miss a definition whose return type sits on its own line. Neither silently corrupts a mapping — both fail toward `unmapped`, which the report pass requires a stated reason for.
