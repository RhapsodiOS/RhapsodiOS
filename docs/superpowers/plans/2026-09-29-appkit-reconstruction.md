# Portable AppKit Reconstruction — Stage 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish reproducible AppKit analysis and architecture-specific ABI inventories, then reconstruct and verify one complete bounded module in `src/Kits/AppKit`.

**Architecture:** Extend binrecon's existing Mach-O reader and scoped IDA workflow. Preserve the supplied PowerPC release as the behavior reference and use the two DR2 slices to distinguish architecture differences from release changes. Keep binary comparison evidence separate from behavioral and integration acceptance.

**Tech Stack:** Python 3.12, existing binrecon/pytest/jsonschema dependencies, IDA's PowerPC and i386 analysis, historical Objective-C/C, and available Rhapsody-compatible compiler/guest environments.

**Spec:** [Approved portable reconstruction design](../specs/2026-09-29-appkit-reconstruction-design.md).

## Global Constraints

- Production source belongs in `src/Kits/AppKit`; preserve all 124 matching public headers.
- Primary reference: `C:/Users/raynorpat/Downloads/test/Frameworks/AppKit.framework/Versions/C/AppKit`.
- Primary size: 5,268,704 bytes; SHA-256: `6897A7FA932BA92CFE92A4A1AF36DB9300D63C1DCC81EB66CEBA5963710A9240`.
- Target architectures: 32-bit big-endian PowerPC and 32-bit little-endian i386.
- Reference install name: `/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit`.
- Secondary reference: `C:/Users/raynorpat/Downloads/test/DR2/Frameworks/AppKit.framework/Versions/C/AppKit`; hash it and its slices before use.
- DR2 slices: i386 offset 8,192, size 4,764,136; PowerPC offset 4,775,936, size 5,239,976.
- Keep binaries, extracted slices, analyzer databases, and bulk pseudocode outside Git.
- Keep unrelated changes intact. Use temporary guest disk images for tests.
- Do not modernize the Objective-C runtime, add Foundation implementations, or replace window-server services within this stage.
- No claim of dual-target completion without both targets' build and runtime evidence.
- Commit only task-owned files. Prefix short commit messages with `binrecon:`, `AppKit:`, or `docs:`; no trailers or metadata.

## Review Focus

1. Fat slices with invalid offsets or ambiguous CPU selection must fail without analyzing the wrong artifact (Task 2).
2. Truncated metadata, cyclic protocol lists, and shared method implementations must produce explicit diagnostics without silently losing coverage (Task 3).
3. Cross-release or cross-architecture ABI comparisons must not treat differing offsets or method encodings as automatically interchangeable (Task 4).
4. Fragmented code and unassigned C helpers must not be attributed to a module merely because they share an address span (Task 5).
5. Tests can accidentally call the original class instead of reconstructed code when both register the same Objective-C name (Task 7).

## Execution setup and file responsibilities

Read `CLAUDE.md` and the approved spec. At execution time inspect attached worktrees
and use the worktree skill if isolation is needed; do not change another task's
checkout or guest. No worktree or execution is required merely to review this plan.

Commands below run from the repository root in PowerShell:

```powershell
$env:PYTHONPATH = 'tools/binrecon'
$appkitPython = '.\.venv-binrecon\Scripts\python.exe'
$env:BINRECON_REFERENCE = 'C:\Users\raynorpat\Downloads\test\Frameworks\AppKit.framework\Versions\C\AppKit'
& $appkitPython -m pytest tools/binrecon/tests -q
```

Record baseline failures before editing. Do not reinstall dependencies unless the
existing environment is unusable. The CLI commands introduced below are proposed
interfaces, not currently available commands.

| Files | Responsibility |
| --- | --- |
| `tools/binrecon/binrecon/macho.py` | Existing thin Mach-O parsing; add dylib load metadata |
| `tools/binrecon/binrecon/slices.py` (new) | Explicit slice selection and identity-preserving extraction |
| `tools/binrecon/binrecon/objc_abi.py` (new) | Strict historical Objective-C metadata recovery |
| `tools/binrecon/binrecon/abi.py` (new) | Inventory documents and architecture-aware comparisons |
| `tools/binrecon/binrecon/module_scope.py` (new) | Module method scopes with explicit helper attribution |
| `tools/binrecon/binrecon/cli.py` | Small command adapters for those modules |
| `tools/binrecon/binrecon/schema/abi-v1.json` (new) | Versioned ABI inventory contract |
| `tools/binrecon/tests/` | Synthetic fixtures, focused tests, and regressions |
| `docs/appkit/` (new) | Compact inventory, dependency, evidence, and verification records |
| `tools/binrecon/profiles/appkit-pilot-ppc.json` (new) | Reference-only scoped analysis configuration |
| `src/Kits/AppKit/NSAffineTransform.m` (conditional) | Leading pilot candidate, subject to Task 6 gate |
| `tests/AppKit/` (new) | Guest compile/runtime probes and behavioral harness |

Dependencies: Task 1 establishes provenance; Tasks 2–5 build on each other;
Task 6 consumes their inventories; Task 7 requires a passed pilot selection gate;
Task 8 records acceptance and follow-on boundaries. Environment investigation in
Task 1 may continue independently of parser work if a guest is unavailable.

---

### Task 1: Record source, reference, and environment baselines

**Files:** Create `docs/appkit/reference-baseline.md`, `docs/appkit/environment.md`;
create `tests/AppKit/compile-probe.m` when running the compiler probe.

**Interfaces:** Produces the exact binary hashes, header comparison, existing
implementation inventory, compiler invocation per target, and a target capability
matrix with separate compile/link/run results.

- [ ] Verify the primary hash and size against Global Constraints; stop reference-dependent work on mismatch.
- [ ] Hash `AppKit_profile`, the DR2 container, all reference headers, and resources. Record filenames and sizes; do not commit binary payloads.
- [ ] Inspect all 103 `.m` files, not just `NSApplication.m`. Record implemented bodies, stub-only files, and build membership; preserve existing useful work.
- [ ] Inspect `vm/build-src.ps1`, `vm/build-src-lib.ps1`, and `src/rbuild-1` for the current build route. Record installed IDA capability and existing Python/tool versions. Do not assume older Foundation notes prove current build availability.
- [ ] Create a minimal compile probe importing `<AppKit/NSAffineTransform.h>` that passes and returns `NSAffineTransformStruct`, `NSPoint`, and `NSSize`. It must not require reconstructed AppKit at link time. Compile to objects in each available target environment and inspect Mach-O CPU types.
- [ ] Record exact compiler commands, framework search paths, compiler versions, guest images, and missing dependencies. Separately identify a route to run the original supplied PowerPC framework and DR2 i386 framework.
- [ ] Commit the baseline and probe with `AppKit: record reconstruction baselines`. A blocked guest blocks its dependent runtime checks, not independent inventory work.

### Task 2: Accept dylibs and extract explicit fat slices

**Files:** Modify `tools/binrecon/binrecon/macho.py`, `cli.py`,
`tests/macho_fixture.py`, `tests/test_macho.py`, `tests/test_cli.py`;
create `binrecon/slices.py`, `tests/test_slices.py` under `tools/binrecon`.

**Interfaces:** Preserve `read_macho(path: Path) -> dict` for thin inputs.
Add `extract_slice(source: Path, destination: Path, *, architecture: str) -> dict`
in `slices.py`, returning `container_sha256`, `slice_sha256`, `architecture`,
`offset`, `size`, and `path`. Add CLI
`extract-slice --binary PATH --architecture {ppc,i386} --output PATH --manifest PATH`.
Downstream analyzers consume the extracted thin file, avoiding changes to every
adapter's identity handling.

- [ ] Add tests `test_reads_dylib_i386`, `test_reads_dylib_ppc`, and `test_dylib_dependencies_and_install_name`. Assert file type 6 is accepted and `LC_ID_DYLIB`/`LC_LOAD_DYLIB` names and version fields survive under `extensions.macho.dylibs`, with a `kind` distinguishing identity from dependency.
- [ ] Add `test_extracts_requested_slice`, `test_rejects_missing_or_duplicate_architecture`, `test_rejects_slice_outside_file`, and `test_rejects_container_header_overlap`. Assert exact slice bytes, both SHA-256 identities, and no successful manifest after failure. Reject wrong thin CPU type and source/destination aliasing; refuse to overwrite an existing destination containing different bytes.
- [ ] Run `& $appkitPython -m pytest tools/binrecon/tests/test_macho.py tools/binrecon/tests/test_slices.py tools/binrecon/tests/test_cli.py -q`; confirm new cases fail for missing behavior.
- [ ] Implement `MH_DYLIB = 6` acceptance, bounded dylib command strings, and fat-header parsing with explicit architecture selection. Keep extraction separate from thin parsing. Validate slice bounds, alignment declarations, overlapping slices, and header/selected-slice architecture agreement.
- [ ] Run the same tests to passing, then the existing binrecon suite. Extract both DR2 slices under ignored `tools/binrecon/out/appkit/reference/`; record manifests in `docs/appkit/reference-baseline.md` and verify observed offsets/sizes match the spec.
- [ ] Commit only changed tooling/tests and compact evidence with `binrecon: read dylibs and extract verified Mach-O slices`.

### Task 3: Recover historical Objective-C metadata without silent omissions

**Files:** Create `tools/binrecon/binrecon/objc_abi.py`,
`tools/binrecon/tests/objc_abi_fixture.py`, `tools/binrecon/tests/test_objc_abi.py`.
Read existing `macho.py::objc_methods_from_sections` and `tests/test_objc_index.py`.

**Interfaces:** `extract_objc_abi(payload: bytes, sections: list[dict], *,
endianness: str) -> dict` returns `modules`, `classes`, `categories`, `protocols`,
`methods`, `diagnostics`, and `complete`. Methods carry module, class, optional
category, class/instance kind, selector, raw type encoding, and implementation
address. Class records include superclass, instance size, and ivars with name,
type, and offset. Protocol methods are declarations, not implementation coverage.

- [ ] Add endian-parameterized tests recovering one module, class, metaclass, category, ivar, and adopted protocol. Assert names, offsets, method ownership, and raw encodings exactly match fixture inputs.
- [ ] Add tests for two methods sharing an IMP, repeated module filenames, cyclic protocol references, invalid pointers, oversized list counts, and truncated strings. Assert shared IMPs preserve both methods; invalid required records set `complete == False` and emit located diagnostics; valid repeated protocol references do not recurse indefinitely.
- [ ] Run `& $appkitPython -m pytest tools/binrecon/tests/test_objc_abi.py -q` and confirm the new behavior fails before implementation.
- [ ] Implement bounded virtual-address reads using the selected thin file's section mappings. Recover metadata from module symtabs, not guessed source order; distinguish unresolved external superclass names from corruption. Preserve diagnostic location and record kind.
- [ ] Run the new tests and `test_objc_index.py`. Preserve the existing tolerant method-index API and its truncation semantics; the new strict inventory must not silently inherit that API's skip-on-error behavior.
- [ ] Commit with `binrecon: recover complete Objective-C ABI records`.

### Task 4: Emit ABI inventories and classify comparison results

**Files:** Create `tools/binrecon/binrecon/abi.py`,
`binrecon/schema/abi-v1.json`, `tests/test_abi.py`; modify `cli.py` and
`tests/test_cli.py`. Register `abi-v1` and `abi-v1.json` in
`schema.py::_SCHEMA_FILES`.

**Interfaces:** `inventory_abi(binary: Path) -> dict` combines thin Mach-O
identity, architecture, dylib linkage, exports/imports, and Task 3 metadata.
`compare_abi(reference: dict, candidate: dict, *, mode: str) -> dict` accepts
`same-target` or `descriptive`, returning `passed` (boolean for same-target,
null for descriptive), structured differences, and completeness diagnostics.
CLI: `abi --binary PATH --output PATH`; `abi-check --reference PATH
--candidate PATH --mode {same-target,descriptive} --output PATH`.

- [ ] Write `test_inventory_schema_and_identity`, `test_reports_missing_export_and_changed_ivar`, `test_same_target_rejects_architecture_mismatch`, and `test_incomplete_inventory_cannot_pass`. Assert an added/removed selector is distinct from a changed raw encoding; protocol declarations never count as implemented methods.
- [ ] Write `test_descriptive_cross_architecture_is_not_acceptance`: offsets and encodings remain visible, but `passed is None`. Same-target comparison ignores code addresses and module ordering while checking ABI-relevant fields. CLI exits nonzero for incomplete inventories and failed same-target checks.
- [ ] Run `& $appkitPython -m pytest tools/binrecon/tests/test_abi.py tools/binrecon/tests/test_cli.py -q`, confirm new tests fail, then implement the functions, schema, and CLI adapters.
- [ ] Rerun those tests and the full suite. Generate inventories for the supplied PowerPC release and both DR2 slices under ignored `tools/binrecon/out/appkit/abi/`.
- [ ] Create `docs/appkit/abi-baseline.md`: compare DR2 PowerPC versus DR2 i386 descriptively, then supplied PowerPC versus DR2 PowerPC for release changes. Record 296 supplied module records as an integration expectation, not a fabricated class count. Investigate every extraction diagnostic before calling the inventory complete.
- [ ] Commit with `binrecon: inventory and compare framework ABI contracts`.

### Task 5: Generate bounded module analysis and coverage records

**Files:** Create `tools/binrecon/binrecon/module_scope.py`,
`tests/test_module_scope.py`; modify `cli.py`, `tests/test_cli.py`;
create `docs/appkit/coverage.json`, `docs/appkit/dependencies.md`.

**Interfaces:** `build_module_scope(abi: dict, analysis: dict, *, modules:
list[str], helper_addresses: list[int]) -> dict` returns `ranges`, `unresolved`,
and `attribution`. Ranges use existing profile `{start, end}` half-open format.
CLI: `module-scope --abi PATH --analysis PATH --module NAME` (repeatable),
`--helper-address ADDRESS` (repeatable), `--output PATH`.
`analysis` is a normalized binrecon analyzer document providing actual function
extents. No inferred contiguous module-wide spans are permitted.

- [ ] Add tests `test_fragmented_methods_exclude_intervening_functions`, `test_shared_imp_keeps_all_owners`, `test_missing_function_extent_is_unresolved`, and `test_helpers_require_explicit_attribution`. Assert an absent module is an error rather than an empty scope that means analyze everything.
- [ ] Run `& $appkitPython -m pytest tools/binrecon/tests/test_module_scope.py tools/binrecon/tests/test_cli.py -q`; confirm failures, then implement scope generation using existing profile conventions. Do not copy reference addresses into `rebuilt_analysis_scope`.
- [ ] Rerun to passing. Obtain initial function extents from IDA's function analysis without bulk decompilation. Record unresolved boundaries; only generate accepted scopes once extents are verified. Do not increase global analysis limits to force the whole framework through.
- [ ] Populate the compact coverage ledger from metadata. Each entry records reference hash, architecture, module/method or symbol identity, source path if known, evidence references, dependency requirements, and separate analyzed/implemented/compiled/behavior-tested statuses. Unknowns and blockers remain explicit; existing binrecon parity statuses retain their original meanings.
- [ ] Record superclass, C-call, dynamic selector, resource, and service dependencies in `dependencies.md`. Label static evidence separately from dependencies confirmed at runtime.
- [ ] Commit with `AppKit: map module coverage and analysis dependencies`.

### Task 6: Select a complete pilot and capture implementation evidence

**Files:** Create `docs/appkit/pilot-contract.md`, `tests/AppKit/pilot-contract.json`,
`tools/binrecon/profiles/appkit-pilot-ppc.json`; update `coverage.json` and
`dependencies.md`. Add `appkit-pilot-dr2-i386.json` only if the pilot exists in DR2.

**Interfaces:** Produces a closed pilot contract: exact module names, all methods
and helpers, production source files, dependency providers, target-specific
expected ABI, observed behavior cases, and scoped analyzer evidence identities.
Task 7 consumes this contract; method behavior is recovered here, not invented
by the plan.

- [ ] Inspect every recovered `NSAffineTransform` method, including private methods, copying/coding, `transformBezierPath:`, `set`, and `concat`. Determine whether path/context dependencies can be supplied without loading original AppKit into the reconstructed test process.
- [ ] Select `NSAffineTransform` only if its complete dependency closure is bounded. If not, choose the smallest complete module whose dependencies are available, update the contract's exact file list and tests, and record why. Do not implement only its arithmetic and label the module complete. If no module qualifies, report the specific dependency blocker and revise the pilot design before product changes.
- [ ] Derive reference-only scoped profiles from the existing PowerPC profile structure. Use the primary hash and extracted analysis ranges, disable unsupported adapters, and retain separate DR2 identity if analyzing i386. Validate with `& $appkitPython -m binrecon validate --profile tools/binrecon/profiles/appkit-pilot-ppc.json`.
- [ ] Run scoped analysis with `& $appkitPython -m binrecon analyze --profile tools/binrecon/profiles/appkit-pilot-ppc.json`. Inspect the run summary; reference-only analysis success is not reconstruction acceptance.
- [ ] Review disassembly and pseudocode together. Record ownership, class initialization, float precision, exceptions, call order, archive field order/types, constants, and external behavior for every method/helper. Resolve ambiguous decompiler types against headers and calling conventions.
- [ ] Write exact oracle scenarios and expected assertions into `pilot-contract.md` and their machine-readable checks into `tests/AppKit/pilot-contract.json`. The JSON contains `schema_version: "appkit-pilot-v1"`, `targets` keyed by architecture with oracle binary hash and expected rebuilt image identity, and `cases` keyed by unique case name with comparison kind (`exact`, `numeric`, or `exception`), expected value, and explicit absolute/relative tolerances for numeric cases. Encode nonfinite floats as tagged strings. For an affine pilot include noncommuting append/prepend, point versus size translation, identity, singular inversion behavior, rotations, copy independence, coding round trips, and context/path operations. Singular behavior and tolerances must come from the reference, not modern AppKit assumptions.
- [ ] Commit with `AppKit: define the evidence-backed pilot contract`.

### Task 7: Reconstruct the pilot and prove which implementation runs

**Files:** Modify the pilot `.m` file(s) named in Task 6's contract under
`src/Kits/AppKit`; create `tests/AppKit/pilot-main.m`,
`tests/AppKit/build-pilot.sh`, `tests/AppKit/compare-results.py`,
`tests/AppKit/test_compare_results.py`; update `pilot-contract.md` and coverage.
For an affine pilot the primary source file is `src/Kits/AppKit/NSAffineTransform.m`.

**Interfaces:** `build-pilot.sh oracle|rebuilt OUTPUT_DIR` uses the exact
target-native compiler settings recorded in Task 1. Oracle mode links the
original framework; rebuilt mode links reconstructed objects and permitted
non-AppKit dependencies. `pilot-main.m` emits named results and implementation
provenance as JSON with `architecture`, `image_sha256`, `implementation_image`,
and `cases` keyed by the contract's names. `compare-results.py --oracle PATH
--rebuilt PATH --contract tests/AppKit/pilot-contract.json` returns zero only
when identity checks and every specified behavior check pass. Record the actual
rebuilt image hash after each build; retain the reference-derived case assertions.

- [ ] Implement the reference scenarios from Task 6 in the harness and capture oracle results in each runnable target. Record module ownership for tested method IMPs using runtime/image inspection or debugger evidence. Run oracle and rebuilt in separate processes.
- [ ] Write comparator tests for a wrong result, omitted case, wrong reference hash, mismatched target, failed provenance, unexpected exception, and numeric tolerance boundaries. Run `& $appkitPython -m pytest tests/AppKit/test_compare_results.py -q`; observe failure, implement the comparator, and rerun to passing.
- [ ] Run the rebuilt harness against the existing stub state; record the expected compile/link/behavior failure. Demonstrate that built mode cannot quietly resolve the pilot class from the original AppKit image. If external dependencies force duplicate class registration, stop and revise the harness isolation before interpreting results.
- [ ] Implement each recovered method and required helper in historical Objective-C/C, preserving public headers. Use descriptive names and native types; do not commit decompiler identifiers, pseudocode, guessed success returns, or unrelated stubs.
- [ ] Build and run the pilot on each available architecture using the recorded native commands. Check struct returns, byte order, object ownership, and floating-point outcomes independently. Compare same-target metadata for linked pilot artifacts; do not compare an unresolved object file's relocatable pointers as if it were a loaded dylib.
- [ ] For a supplied-release feature absent from DR2, run portable invariants on i386 and identify the missing same-release oracle explicitly. A DR2 result cannot establish supplied-release behavioral parity by itself.
- [ ] Run `compare-results.py` for each comparable pair; require all cases and provenance checks to pass. Record separate original-dependency and reconstructed-RhapsodiOS-dependency results. Leave unavailable target checks blocked.
- [ ] Commit verified source/tests/evidence with `AppKit: reconstruct the verified pilot module`, naming the actual module in the final commit message. Do not claim full-stage completion if a target remains unverified.

### Task 8: Audit acceptance and hand off the remaining reconstruction

**Files:** Create `docs/appkit/stage-1-results.md`; update `coverage.json`,
`environment.md`, and `dependencies.md` with final observed status.

**Interfaces:** Produces the next-stage entry conditions, explicit blockers,
and a repeatable list of commands and artifacts proving current coverage.

- [ ] Run the complete binrecon suite once after the final tooling changes and the pilot comparator suite. Rerun guest checks only when relevant source/environment changed or unresolved failures require it.
- [ ] Verify all 124 public headers still match baseline hashes, only intended files changed, no binary/database/pseudocode artifacts are staged, and `git diff --check` passes.
- [ ] Reconcile every pilot method/helper with coverage evidence. Record source, analysis, compile, ABI, behavior, and integration statuses separately. Report a partial result if any required target gate is blocked.
- [ ] Record the module's measured effort and dependency findings. Identify the next smallest independently verifiable group; do not extrapolate a full-project deadline from source-file count.
- [ ] Commit with `AppKit: record pilot acceptance and remaining gates`.

## Follow-on plans and full-framework completion

Stage 1 is the detailed executable plan. The remaining program is deliberately
split into subsystem plans after evidence establishes the boundaries; these are
not implementation permissions or promises that every group is independent.

| Follow-on group | Entry condition | Required exit evidence |
| --- | --- | --- |
| Graphics/resources | Identified context, DPS, and resource dependencies | Drawing/state comparisons, resource inventory and provenance |
| Application/events/windows/views | Available runtime and window-server interfaces | Lifecycle, responder dispatch, nib loading, first working window |
| Cells/controls/menus | Working view/event foundations | Actions, state transitions, menu behavior, scrolling and widget tests |
| Images/fonts | Verified graphics and resource providers | Decoding, metrics, representations, rendering comparisons |
| Text/layout/input | Available font/view/archive dependencies | Separate bounded plans for storage, layout, editing, input, and coding |
| Documents/printing/services/media | Required external service interfaces available | Document/panel, print, pasteboard, workspace, sound/movie behavior |
| Framework packaging/integration | All required module groups accounted for | PowerPC/i386 builds, version C install name, resources, representative apps |

Each follow-on plan names its source files from recovered module ownership,
records public and private coverage, and applies the same provenance and target
gates. Inventory includes remaining exports/modules not listed in the examples.

At packaging time reconcile `src/Kits/AppKit/PB.project` version B with reference
version C, updating generated build settings through the existing Project Builder
conventions. Add framework installation/build-manifest participation only after
dependency and package acceptance; do not change `src/Manifest` in Stage 1.

Full acceptance requires complete coverage accounting, successful builds and
applicable ABI checks on both architectures, required resource packaging, and
representative application tests for startup, nibs, windows, controls, menus,
drawing, text, persistence, and services. Accounted-for but unresolved entries
remain gaps; compilation, decompilation output, or source-file presence alone
cannot establish reconstructed behavior.

## Plan review record

Self-review mapped reference identity and source preservation to Task 1;
Mach-O/tooling to Tasks 2–5; architecture and release differences to Tasks 1/4/7;
dependency-bounded reconstruction to Tasks 6–7; and verification/reporting to
Task 8. Full packaging and broader subsystems are explicitly deferred as the
approved spec requires. Review Focus cases have owning tests. Pilot selection
and native compiler invocations are evidence gates with named outputs rather
than invented environment commands or unverified behavior.
