# Binrecon Multi-Analyzer Toolkit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable command-line toolkit that exports, normalizes, compares, and reconciles IDA, Ghidra, and angr analysis for legacy i386 Mach-O reconstruction work.

**Architecture:** A Python orchestration package owns profiles, schemas, comparison, consensus, and ledgers. IDAPython and headless Ghidra adapters export tool-native analysis into the shared schema; angr supplies an independent CFG and bounded symbolic checks. Reference bytes remain authoritative, and generated projects/results remain untracked.

**Tech Stack:** Python 3.12+, angr 9.3.0, jsonschema 4.26.0, pytest 9.1.1, IDA Professional 9.2, Ghidra 12.1, Java 21 required by Ghidra 12.1.

**Spec:** [docs/superpowers/specs/2026-07-21-binrecon-toolkit-design.md](../specs/2026-07-21-binrecon-toolkit-design.md)

---

## File structure

| Path | Responsibility |
|------|----------------|
| `.gitignore` | Ignore the local Python environment and generated analysis |
| `tools/binrecon/README.md` | Installation, profiles, commands, and analyzer limitations |
| `tools/binrecon/requirements.txt` | Runtime dependency pins |
| `tools/binrecon/requirements-dev.txt` | Test dependency pins |
| `tools/binrecon/binrecon/` | Python package and `python -m binrecon` CLI |
| `tools/binrecon/binrecon/schema/analysis-v1.json` | Normalized analyzer-output schema |
| `tools/binrecon/binrecon/schema/profile-v1.json` | Profile schema |
| `tools/binrecon/binrecon/schema/ledger-v1.json` | Parity-ledger schema |
| `tools/binrecon/binrecon/macho.py` | Legacy 32-bit Mach-O identity, section, symbol, and relocation reader |
| `tools/binrecon/binrecon/profile.py` | Profile loading, path resolution, and validation |
| `tools/binrecon/binrecon/runner.py` | Analyzer invocation and stale-output protection |
| `tools/binrecon/binrecon/normalize.py` | Instruction and relocation normalization |
| `tools/binrecon/binrecon/consensus.py` | Address-based analyzer agreement report |
| `tools/binrecon/binrecon/compare.py` | Function, section, and whole-image comparison |
| `tools/binrecon/binrecon/ledger.py` | Ledger creation and status validation |
| `tools/binrecon/binrecon/adapters/` | IDA, Ghidra, and angr command builders |
| `tools/binrecon/adapters/ida/export_analysis.py` | Script executed inside IDA |
| `tools/binrecon/adapters/ghidra/ExportAnalysis.java` | Ghidra headless post-script |
| `tools/binrecon/adapters/angr/export_analysis.py` | angr CFG/VEX exporter |
| `tools/binrecon/tests/` | Unit and CLI tests with synthetic fixtures |

---

### Task 1: Create the isolated Python package and dependency contract

**Files:**
- Modify: `.gitignore`
- Create: `tools/binrecon/requirements.txt`
- Create: `tools/binrecon/requirements-dev.txt`
- Create: `tools/binrecon/binrecon/__init__.py`
- Create: `tools/binrecon/binrecon/__main__.py`
- Create: `tools/binrecon/binrecon/cli.py`
- Create: `tools/binrecon/tests/test_cli.py`

- [ ] **Step 1: Write the failing CLI test**

```python
from binrecon.cli import build_parser


def test_parser_exposes_required_commands():
    parser = build_parser()
    help_text = parser.format_help()
    for command in ("validate", "analyze", "consensus", "compare", "ledger"):
        assert command in help_text
```

- [ ] **Step 2: Run the test and verify package import fails**

```powershell
$env:PYTHONPATH='tools/binrecon'
python -m pytest tools/binrecon/tests/test_cli.py -q
```

Expected: collection fails because `binrecon.cli` does not exist.

- [ ] **Step 3: Pin dependencies**

`tools/binrecon/requirements.txt`:

```text
angr==9.3.0
jsonschema==4.26.0
```

`tools/binrecon/requirements-dev.txt`:

```text
-r requirements.txt
pytest==9.1.1
```

- [ ] **Step 4: Add generated paths to `.gitignore`**

```gitignore
# Binary reconstruction tooling
/.venv-binrecon/
/tools/binrecon/out/
/tools/binrecon/.pytest_cache/
/tools/binrecon/**/__pycache__/
```

- [ ] **Step 5: Implement the CLI skeleton**

`cli.py` must define `build_parser()` with the five subcommands from the test and `main(argv=None) -> int`. Each unimplemented command returns exit code 2 with `binrecon: command not implemented: {command}`; `__main__.py` exits with `main()`.

```python
import argparse


COMMANDS = ("validate", "analyze", "consensus", "compare", "ledger")


def build_parser():
    parser = argparse.ArgumentParser(prog="binrecon")
    sub = parser.add_subparsers(dest="command", required=True)
    for name in COMMANDS:
        command = sub.add_parser(name)
        command.add_argument("--profile", required=True)
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    print(f"binrecon: command not implemented: {args.command}")
    return 2
```

- [ ] **Step 6: Create and verify the local environment**

```powershell
py -3.12 -m venv .venv-binrecon
& .\.venv-binrecon\Scripts\python.exe -m pip install -r tools\binrecon\requirements-dev.txt
$env:PYTHONPATH='tools/binrecon'
& .\.venv-binrecon\Scripts\python.exe -m pytest tools\binrecon\tests\test_cli.py -q
```

Expected: `1 passed`.

- [ ] **Step 7: Commit**

```powershell
git add .gitignore tools/binrecon
git commit -m "tools: scaffold binrecon toolkit"
```

---

### Task 2: Define and validate the normalized schemas

**Files:**
- Create: `tools/binrecon/binrecon/schema/analysis-v1.json`
- Create: `tools/binrecon/binrecon/schema/profile-v1.json`
- Create: `tools/binrecon/binrecon/schema/ledger-v1.json`
- Create: `tools/binrecon/binrecon/schema.py`
- Create: `tools/binrecon/tests/test_schema.py`
- Create: `tools/binrecon/tests/fixtures/minimal-analysis.json`

- [ ] **Step 1: Write failing schema tests**

Tests must prove that a minimal valid analysis passes, missing `input.sha256` fails, duplicate function addresses fail in `validate_analysis_semantics`, an unknown ledger status fails, and relative paths are accepted in profiles while unknown keys are rejected.

```python
def test_analysis_requires_input_hash(analysis_document):
    del analysis_document["input"]["sha256"]
    with pytest.raises(ValidationError):
        validate_document("analysis-v1.json", analysis_document)
```

- [ ] **Step 2: Run and verify failure**

```powershell
$env:PYTHONPATH='tools/binrecon'
python -m pytest tools/binrecon/tests/test_schema.py -q
```

Expected: import failure for `binrecon.schema`.

- [ ] **Step 3: Implement Draft 2020-12 schemas**

The analysis schema must require `schema_version`, `input`, `analyzer`, `sections`, `symbols`, `relocations`, and `functions`. Function entries require address, size, names, blocks, instructions, calls, and confidence. The profile schema must require `schema_version`, `name`, `architecture`, `reference`, `rebuilt`, `analyzers`, `comparison`, and `output_dir`. The ledger schema must restrict statuses to the five values approved in the design.

- [ ] **Step 4: Implement schema loading and semantic validation**

`schema.py` must expose:

```python
def validate_document(schema_name: str, document: dict) -> None: ...
def validate_analysis_semantics(document: dict) -> None: ...
def load_json(path: Path) -> dict: ...
```

Semantic validation rejects duplicate function starts, blocks outside their function, instructions outside their block, overlapping sections, and malformed lowercase/uppercase SHA-256 strings.

- [ ] **Step 5: Run tests**

```powershell
python -m pytest tools/binrecon/tests/test_schema.py -q
```

Expected: all schema tests pass.

- [ ] **Step 6: Commit**

```powershell
git add tools/binrecon/binrecon/schema* tools/binrecon/tests
git commit -m "tools: define binrecon interchange schemas"
```

---

### Task 3: Implement profile loading and immutable input identity

**Files:**
- Create: `tools/binrecon/binrecon/profile.py`
- Create: `tools/binrecon/binrecon/identity.py`
- Create: `tools/binrecon/tests/test_profile.py`
- Create: `tools/binrecon/tests/test_identity.py`

- [ ] **Step 1: Write failing tests**

Cover profile-relative path resolution, environment expansion only for an allowlisted `${BINRECON_REFERENCE}`, missing input failure, exact size/hash validation, and rejection when a file changes after identity capture.

- [ ] **Step 2: Run and verify failure**

```powershell
python -m pytest tools/binrecon/tests/test_profile.py tools/binrecon/tests/test_identity.py -q
```

- [ ] **Step 3: Implement the APIs**

```python
@dataclass(frozen=True)
class InputIdentity:
    path: Path
    size: int
    sha256: str


def identify(path: Path) -> InputIdentity: ...
def assert_identity(expected: InputIdentity) -> None: ...
def load_profile(path: Path, environ: Mapping[str, str]) -> Profile: ...
```

Hash files in 1 MiB chunks, use `Path.resolve(strict=True)`, and preserve the profile directory for relative outputs.

- [ ] **Step 4: Wire `binrecon validate`**

The command validates the profile, resolves both artifacts, prints size and SHA-256, and returns nonzero on mismatch.

- [ ] **Step 5: Verify**

```powershell
python -m pytest tools/binrecon/tests/test_profile.py tools/binrecon/tests/test_identity.py tools/binrecon/tests/test_cli.py -q
```

- [ ] **Step 6: Commit**

```powershell
git add tools/binrecon
git commit -m "tools: validate binrecon profiles and inputs"
```

---

### Task 4: Parse legacy 32-bit Mach-O metadata without LLVM assumptions

**Files:**
- Create: `tools/binrecon/binrecon/macho.py`
- Create: `tools/binrecon/tests/macho_fixture.py`
- Create: `tools/binrecon/tests/test_macho.py`

- [ ] **Step 1: Build a synthetic MH_OBJECT fixture and failing tests**

The fixture contains `LC_SEGMENT`, two sections, `LC_SYMTAB`, one external symbol, one section relocation, and an `LC_UNIXTHREAD` command with an unknown flavor. Tests require the parser to skip unknown thread flavors by command size rather than reject the file.

- [ ] **Step 2: Run and verify failure**

```powershell
python -m pytest tools/binrecon/tests/test_macho.py -q
```

- [ ] **Step 3: Implement bounded binary readers**

Use explicit little-endian `struct.Struct` definitions for the Mach header, load-command header, `segment_command`, `section`, `symtab_command`, `nlist`, and relocation entries. Every offset-plus-size operation must use a shared checked-slice helper and raise `MachOFormatError` with the command index and file offset.

- [ ] **Step 4: Export normalized base analysis**

`read_macho(path)` returns sections, symbols, relocations, header identity, and unparsed load commands in analysis-schema form. It must not guess functions.

- [ ] **Step 5: Verify malformed inputs**

Tests cover truncated commands, section bytes outside the file, invalid string offsets, scattered relocations, and unknown load commands.

- [ ] **Step 6: Commit**

```powershell
git add tools/binrecon
git commit -m "tools: parse legacy i386 Mach-O metadata"
```

---

### Task 5: Add deterministic IDA export

**Files:**
- Create: `tools/binrecon/adapters/ida/export_analysis.py`
- Create: `tools/binrecon/binrecon/adapters/ida.py`
- Create: `tools/binrecon/tests/test_ida_adapter.py`

- [ ] **Step 1: Write command-construction and stale-output tests**

Require the runner to invoke `idat.exe -A -S"export_analysis.py --output analysis.tmp.json" input.i64`, write to a temporary output, verify the exported input hash, and atomically replace the final JSON only after validation.

- [ ] **Step 2: Implement the IDAPython exporter**

Iterate `ida_segment`, `ida_funcs`, `ida_gdl.FlowChart`, `idautils.FuncItems`, `ida_xref`, `ida_name`, and legacy Objective-C names. Export bytes with `ida_bytes.get_bytes`, decoded operands, references, imports, selectors, and function aliases. Sort every collection by address and stable secondary key before JSON serialization.

- [ ] **Step 3: Implement the host adapter**

The host adapter discovers the configured IDA executable, passes reference/output arguments, enforces a profile timeout, captures the IDA log, validates schema and identity, and records IDA version.

- [ ] **Step 4: Run unit tests and an IDA fixture smoke test**

```powershell
python -m pytest tools/binrecon/tests/test_ida_adapter.py -q
python -m binrecon analyze --profile tools/binrecon/tests/fixtures/ida-smoke-profile.json --analyzer ida
```

Expected: valid `ida.analysis.json`; rerunning produces an identical hash.

- [ ] **Step 5: Commit**

```powershell
git add tools/binrecon
git commit -m "tools: export deterministic IDA analysis"
```

---

### Task 6: Add independent headless Ghidra export

**Files:**
- Create: `tools/binrecon/adapters/ghidra/ExportAnalysis.java`
- Create: `tools/binrecon/binrecon/adapters/ghidra.py`
- Create: `tools/binrecon/tests/test_ghidra_adapter.py`

- [ ] **Step 1: Write command and failure tests**

Cover `analyzeHeadless.bat work project -import input.bin -processor x86:LE:32:default -postScript ExportAnalysis.java analysis.tmp.json -deleteProject`, missing Java/Ghidra, analysis timeout, script error, stale output, and retry through `BinaryLoader` with profile-supplied section layout when the legacy Mach-O loader rejects a load command.

- [ ] **Step 2: Implement `ExportAnalysis.java`**

Export memory blocks, symbols, relocations, functions, basic blocks, instructions, references, calls, strings, and decompiler/P-code summaries through Ghidra APIs. Include the input SHA-256 and `Application.getApplicationVersion()`. Use a JSON writer that escapes control characters and sorts address-keyed collections.

- [ ] **Step 3: Implement the host adapter**

Require Ghidra 12.1 in the EISABus profile, use a unique temporary project directory per run, retain logs on failure, delete the project on success, validate output, and atomically publish it. Native Mach-O import is attempted once; the deterministic fallback imports as raw i386 and applies memory blocks, permissions, base addresses, and entry points from `macho.py` before analysis.

- [ ] **Step 4: Run tests and fixture smoke**

```powershell
python -m pytest tools/binrecon/tests/test_ghidra_adapter.py -q
python -m binrecon analyze --profile tools/binrecon/tests/fixtures/ghidra-smoke-profile.json --analyzer ghidra
```

- [ ] **Step 5: Commit**

```powershell
git add tools/binrecon
git commit -m "tools: export headless Ghidra analysis"
```

---

### Task 7: Add angr CFG and bounded symbolic checks

**Files:**
- Create: `tools/binrecon/adapters/angr/export_analysis.py`
- Create: `tools/binrecon/binrecon/adapters/angr.py`
- Create: `tools/binrecon/tests/test_angr_adapter.py`

- [ ] **Step 1: Write failing loader and CFG tests**

Use the synthetic Mach-O fixture to prove Mach-O load is attempted first, flat i386 fallback uses profile base/entry/regions, `CFGFast` starts from profile and symbol addresses, and output is deterministic.

- [ ] **Step 2: Implement CFG export**

Load with `auto_load_libs=False`, run `CFGFast(normalize=True, function_starts=..., resolve_indirect_jumps=True)`, export functions/blocks/edges/calls and VEX operation summaries, and record `cfg.errors`.

- [ ] **Step 3: Implement bounded-check contract**

Profiles may name a function, symbolic input bytes, concrete register/memory setup, hooked call addresses, maximum active states, maximum steps, and assertions over return value or memory. Terminate with `passed`, `failed`, `unsupported`, or `limit-reached`; never report `limit-reached` as success.

- [ ] **Step 4: Add deterministic checksum example**

The fixture check supplies 8 symbolic bytes to a checksum routine and asserts the reference and rebuilt return expressions are equal under identical constraints.

- [ ] **Step 5: Verify and commit**

```powershell
python -m pytest tools/binrecon/tests/test_angr_adapter.py -q
git add tools/binrecon
git commit -m "tools: add angr CFG and bounded checks"
```

---

### Task 8: Normalize instructions and compute analyzer consensus

**Files:**
- Create: `tools/binrecon/binrecon/normalize.py`
- Create: `tools/binrecon/binrecon/consensus.py`
- Create: `tools/binrecon/tests/test_normalize.py`
- Create: `tools/binrecon/tests/test_consensus.py`

- [ ] **Step 1: Write failing normalization tests**

Prove a relocated `call 0x12345678` normalizes to the relocation target while `cmp eax, 0x12345678` remains a literal; preserve operand width, signed displacement, prefixes, and port constants.

- [ ] **Step 2: Write failing consensus tests**

Cover exact three-way agreement, one analyzer splitting a function, one missing edge, code/data disagreement, aliases at the same address, and confidence retained per analyzer.

- [ ] **Step 3: Implement normalization and consensus**

Match functions by section-relative byte range. Emit `agreed`, `partial`, or `disputed` plus precise analyzer claims. Do not use names as identity and do not majority-vote disputed boundaries.

- [ ] **Step 4: Wire `binrecon consensus` and verify**

```powershell
python -m pytest tools/binrecon/tests/test_normalize.py tools/binrecon/tests/test_consensus.py -q
```

- [ ] **Step 5: Commit**

```powershell
git add tools/binrecon
git commit -m "tools: normalize analysis and report consensus"
```

---

### Task 9: Compare functions, sections, and images

**Files:**
- Create: `tools/binrecon/binrecon/compare.py`
- Create: `tools/binrecon/tests/test_compare.py`

- [ ] **Step 1: Write failing comparator tests**

Cover identical bytes, relocation-only operand differences, literal opcode/constant differences, branch-shape differences, section reordering, padding changes, symbol/string ordering, metadata differences, and exact-image equality.

- [ ] **Step 2: Implement comparison layers**

Return structured categories `code`, `relocation`, `symbol-string-order`, `layout`, `padding`, and `metadata`. A function reaches `assembly-matched` only when raw or relocation-normalized instructions, CFG edges, calls, constants, and access widths agree.

- [ ] **Step 3: Wire `binrecon compare`**

Write JSON and concise text reports, return 0 for the configured acceptance level and 1 for mismatch. `--require exact-image|exact-sections|normalized-functions` overrides the profile.

- [ ] **Step 4: Verify and commit**

```powershell
python -m pytest tools/binrecon/tests/test_compare.py -q
git add tools/binrecon
git commit -m "tools: compare reconstructed functions and images"
```

---

### Task 10: Implement parity ledgers and end-to-end orchestration

**Files:**
- Create: `tools/binrecon/binrecon/ledger.py`
- Create: `tools/binrecon/binrecon/runner.py`
- Create: `tools/binrecon/tests/test_ledger.py`
- Create: `tools/binrecon/tests/test_runner.py`

- [ ] **Step 1: Write failing transition tests**

Allow only `unexamined -> signature-confirmed -> control-flow-confirmed -> assembly-matched`; permit `intentional-mismatch` from a reviewed state only with a nonempty reason and reviewer. Reject a ledger whose stored reference hash differs from current input.

- [ ] **Step 2: Implement atomic ledgers**

Store source path/line, reference range, aliases, analyzer agreement, comparison artifact paths, status, reason, reviewer, and reference/rebuilt identities. Sort by reference address and write through a temporary file plus `os.replace`.

- [ ] **Step 3: Implement `analyze` orchestration**

Run required adapters sequentially to avoid IDA/Ghidra resource contention, validate each output, generate consensus, compare reference/rebuilt when both exist, and update ledger evidence without advancing human-reviewed statuses automatically.

- [ ] **Step 4: Run the entire suite**

```powershell
$env:PYTHONPATH='tools/binrecon'
python -m pytest tools/binrecon/tests -q
```

Expected: all tests pass with analyzer integration tests skipped only when explicitly marked for missing external executables.

- [ ] **Step 5: Commit**

```powershell
git add tools/binrecon
git commit -m "tools: orchestrate binrecon parity ledgers"
```

---

### Task 11: Document installation and prove a clean reusable workflow

**Files:**
- Create: `tools/binrecon/README.md`
- Create: `tools/binrecon/profiles/example.json`
- Modify: `tools/binrecon/tests/test_cli.py`

- [ ] **Step 1: Document exact setup**

Include Python 3.12 venv commands, pinned pip install, IDA 9.2 executable configuration, Ghidra 12.1 plus Java 21, external reference-path environment variables, every CLI command, output directory semantics, analyzer limitations, and stale-output guarantees.

- [ ] **Step 2: Add an example profile**

Use `${BINRECON_REFERENCE}` and `${BINRECON_REBUILT}`, i386 little-endian architecture, all three analyzers, normalized-function acceptance, timeouts, and generated output under `tools/binrecon/out/example`.

- [ ] **Step 3: Add help and example-validation tests**

```powershell
python -m binrecon --help
python -m binrecon validate --profile tools/binrecon/profiles/example.json
```

The second command is expected to fail clearly when example environment variables are unset; the test asserts the message and exit code.

- [ ] **Step 4: Run final verification**

```powershell
python -m pytest tools/binrecon/tests -q
git diff --check
git status --short
```

- [ ] **Step 5: Commit**

```powershell
git add tools/binrecon
git commit -m "docs: document binrecon reconstruction workflow"
```

---

## Spec coverage

| Requirement | Tasks |
|-------------|-------|
| Reusable driver-neutral core | 1-4, 8-11 |
| IDA export | 5 |
| Ghidra headless export | 6 |
| angr CFG and bounded symbolic checks | 7 |
| Common versioned schema | 2 |
| Analyzer disagreement reporting | 8 |
| Relocation-aware function comparison | 4, 8, 9 |
| Section and whole-image comparison | 9 |
| Machine-readable parity ledger | 10 |
| Pinned and recorded dependencies | 1, 5-7, 11 |
| No reference artifacts in Git | 1, 3, 11 |
