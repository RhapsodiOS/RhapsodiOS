# ProcessViewer Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct ProcessViewer in `src/Applications/Administration/ProcessViewer` with faithful original behavior and verified 32-bit PowerPC and i386 builds.

**Architecture:** Shared historical Objective-C/C source preserving original translation units, classes, resources, and NIB contracts. The supplied PowerPC binary is authoritative; architecture-specific evidence and validation remain separate. Recover contracts before implementing them, rather than guessing types or accepting decompiler output as source.

**Tech Stack:** Historical Objective-C runtime, AppKit C, Foundation C, System B, Project Builder application makefiles, Python 3.12 binrecon, IDA 9.4, compatible build and GUI guests.

**Spec:** [Approved design](../specs/2026-10-01-processviewer-reconstruction-design.md), approved by the user on 2026-10-01.

## Global Constraints

- Both 32-bit PowerPC and i386 are required targets.
- Source belongs in `src/Applications/Administration/ProcessViewer`.
- Preserve manual memory management and historical Foundation/AppKit APIs. Do not modernize the UI or add functionality.
- Preserve existing NIB archives byte-for-byte initially; retain localized resources and original bundle hierarchy.
- Use the supplied PowerPC executable as the behavioral authority. Never use it as an i386 binary-comparison oracle.
- Ghidra and angr remain disabled for PowerPC because current adapters reject it.
- Keep raw binary inputs, analyzer databases, and large generated outputs outside Git or under ignored `tools/binrecon/out/processviewer-ppc`.
- Do not expand this app reconstruction into framework or kernel reconstruction, toolchain installation, or global OS-image integration.
- Use disposable guest disk images/overlays for runtime tests; preserve shared guests and their installed applications.
- Exercise process termination only against controlled child processes.
- Report compilation, static parity, deterministic tests, and guest GUI validation separately for each architecture. Any unavailable validation remains explicitly incomplete.
- Do not count stubs, source-map coverage, analyzer agreement, or successful compilation alone as behavioral parity.
- Preserve unrelated work; stage and commit only task-owned changes.

## Review Focus

- A process exits or a PID is reused between refresh, inspection, and termination: recover original identity/invalidation behavior and test transitions in Tasks 3, 6, and 7.
- `/bin/ps` or kernel data is empty, partial, or fails: reproduce observed parsing/error behavior and cleanup in Task 3.
- Preferences or custom process-type files contain missing or unexpected values: verify original defaults and rejection/fallback behavior in Tasks 4 and 6.
- A selection becomes hidden after filtering or sorting: verify table, count, inspector, and action state together in Tasks 5–7.
- Endianness, structure layout, NIB unarchiving, or host API differences break i386 despite a good PowerPC build: verify both architectures in Tasks 2, 3, and 8.

## Execution conventions and file ownership

Read `CLAUDE.md`, the spec, and this plan first. At execution start, inspect active
worktrees and use a suitable isolated checkout, following the native worktree
tools and `codex/` branch convention. Preserve all unrelated modifications.
Planning has not created product source, profiles, or analyzer output.

All paths below are repository-relative. `APP` means
`src/Applications/Administration/ProcessViewer`; expand it when creating files.
`EVIDENCE` means `APP/reconstruction`. Commands run from repository root unless
identified as guest commands. Host setup:

```powershell
$env:PYTHONPATH = 'tools/binrecon'
$pvPython = '.\.venv-binrecon\Scripts\python.exe'
$pvSource = 'src/Applications/Administration/ProcessViewer'
$pvProfile = 'tools/binrecon/profiles/processviewer-ppc.json'
$env:BINRECON_REFERENCE = 'C:\Users\raynorpat\Downloads\test\Applications_ppc\Administration\ProcessViewer.app\ProcessViewer'
& $pvPython -m binrecon --help
```

Confirm the interpreter and analyzer exist. Use the installed environment; do not
install or downgrade tools to match stale README examples. Record baseline
tooling failures without treating unrelated failures as reconstruction defects.
All `make` commands below are guest/build-environment commands run from `APP`;
use the exact environment and external output roots recorded in Task 2.

Product units are `Inspector.m`, `Process.m`, `ProcessControl.m`, `ProcessType.m`,
`ProcessTableView.m`, `UserIdCache.m`, and their corresponding proposed headers.
Use metadata to place `MapTableEnumerator`, `ProcessTableHeaderView`,
`Process(Private)`, `_main`, globals, and C helpers in the recovered owning units.
Headers are organizational choices, not claims of original filenames.

Create `EVIDENCE/reference.md`, `abi.md`, `dependencies.md`, `function-worklist.md`,
`build-environment.md`, `validation.md`, `resources.sha256`, and architecture
directories `ppc/` and `i386/`. Put reviewed `source-map.json` and `ledger.json`
under the architecture whose actual reference they describe. Raw evidence stays
in ignored output directories; records identify its hash and how to reproduce it.

Tests live under `APP/tests/`: `Makefile`, `test_support.h`, `test_support.m`,
`abi.m`, `process.m`, `process_types.m`, `table.m`, `controller.m`, `inspector.m`,
and `integration.md`. Add only necessary fixtures and a controlled child helper
`process_child.c`. Test binaries link the real reconstructed units rather than
mirroring their logic. Interpose external data sources only in test builds when
needed; avoid changing the shipped API for testing.

Task 1 must freeze signatures and constants in `abi.md` before consuming tasks
begin. This plan names observed selectors but deliberately does not invent their
parameter/return types. Unresolved signatures block their consuming methods.

## Task 1: Establish complete reference evidence and contracts

**Files:** Create `tools/binrecon/profiles/processviewer-ppc.json` and the reference,
ABI, dependency, worklist, and resource-hash records above. Create the i386 profile
only if a usable i386 reference is found. Modify binrecon only for reproduced
blocking defects, with focused regression tests.

**Interfaces:** Produce an address-keyed function inventory with aliases, sizes,
owners, recovered signatures, callers, and evidence. `abi.md` supplies exact
Objective-C encodings, ivar layouts, C prototypes, notification names, dictionary
keys, defaults, sort context, and NIB connections consumed by Tasks 2–7.

- [ ] Verify the PowerPC reference is 70852 bytes with SHA-256 `4a08718bd848e733a7e4ef8ef8f7b9a282a2fe56c8d38b14f23622c9983b7179`. Hash every bundle resource with a relative path; preserve the source bundle unchanged.
- [ ] Inventory local reference media once for another ProcessViewer. Identify CPU, release, and resources of each candidate; record searched locations and conclude the search if none is usable. Extract fat slices externally only after recording container identity. Document release deltas before accepting an i386 oracle.
- [ ] Copy the structure of `tools/binrecon/profiles/interceptor-ppc.json`, changing the name, reference size/hash, and output directory to `../out/processviewer-ppc`. Keep architecture `ppc`, endianness `big`, IDA 9.4 enabled, Ghidra/angr disabled, and acceptance `normalized-functions`. Omit `rebuilt` initially; check the output is ignored with `git check-ignore tools/binrecon/out/processviewer-ppc/probe.json`.
- [ ] Run the following commands. Require matching identity and complete reference analysis; inspect the run summary and retain diagnostics when analysis fails.

```powershell
& $pvPython -m binrecon validate --profile $pvProfile
& $pvPython -m binrecon analyze --profile $pvProfile `
  --output tools/binrecon/out/processviewer-ppc/run-summary.json
```

- [ ] Reconcile all 78 symbol-named Objective-C methods with metadata and IDA functions, plus application C helpers and `_main`. Audit every executable section. Account explicitly for imported stubs, runtime startup, aliases, and unidentified code; do not scope analysis to Objective-C methods alone.
- [ ] Investigate the metadata-index shortfall before relying on metadata-derived coverage. If a parser fix is required, reproduce the precise case in `tools/binrecon/tests/test_objc_index.py`, demonstrate failure, apply the smallest fix, and run that test plus `test_macho.py`; then run the full binrecon suite once. A documented metadata limitation is acceptable only when independent evidence supplies complete coverage.
- [ ] Read IDA disassembly and available pseudocode per owned function. Recover module ownership, type encodings, ivars, table/kernel structures, `/bin/ps` invocation and parsing, error strings, process-type search paths, defaults, refresh rules, export format, and termination confirmation/signal behavior. Record tool limitations explicitly if pseudocode is unavailable.
- [ ] Audit both NIBs against class metadata and responder-chain behavior. Record all outlet/action targets, column identifiers, inspector views, and archived classes; do not manufacture methods merely because `classes.nib` lists an action.
- [ ] Verify each worklist item has an owner and evidence route, and that no exact signature/constant needed by the next task remains guessed. Commit: `ProcessViewer: record reference contracts and analysis profile`.

## Task 2: Establish dual-architecture builds, resources, and ABI tests

**Files:** Create the six headers, `APP/Makefile`, `Makefile.preamble`,
`Makefile.postamble`, `PB.project`, `Resources/`, `tests/Makefile`,
`tests/test_support.{h,m}`, `tests/abi.m`, and `EVIDENCE/build-environment.md`.

**Interfaces:** Declarations match Task 1. The build honors `RC_ARCHS`, `OBJROOT`,
`SYMROOT`, and `DSTROOT`. Test targets introduced here and below are `abi`,
`process`, `process-types`, `table`, `controller`, and `inspector`; each executes
its assertions and returns nonzero on failure.

- [ ] Record actual compiler/linker, SDK, framework, Project Builder makefile, guest transport, source, output, and disposable-image paths for each CPU. Probe historical Objective-C compilation and the required process APIs. Mark unavailable prerequisites without pretending host Python checks substitute for target execution.
- [ ] Write ABI assertions against recovered superclass, instance size, ivar offsets, selector encodings, and C structure layouts. Run against compatible reference runtime observations where available; verify an intentionally wrong expected layout fails, then restore it. For i386 without an oracle, derive expected layouts from its actual headers/compiler and the shared contracts, not copied PowerPC offsets.
- [ ] Add declarations from Task 1 and application build files using `src/pb_makefiles-1/app.make`, `wrapped.make`, and `common.make` as authoritative conventions. Preserve app name `ProcessViewer`, principal class `NSApplication`, main NIB `ProcessViewer.nib`, and measured framework dependencies. Register source files as their implementations arrive; do not add placeholder method bodies to force a link.
- [ ] Copy the original `Resources` hierarchy; verify every file against `resources.sha256`. Retain provenance and existing notices without assigning an invented license. Confirm the build's resource-copy rules preserve localization and NIB subdirectories.
- [ ] Establish test support for explicit selected-artifact identity and isolated temporary fixtures/preferences. Reference GUI observations use the original executable in a separate process. Do not assume a Mach-O executable can be dynamically loaded as a test library; use debugger observations or instruction evidence where direct invocation is unavailable.
- [ ] Compile headers, ABI probes, and test support for both CPUs. Record the fully resolved guest commands. The eventual app commands use `make RC_ARCHS=ppc OBJROOT="$PV_PPC_OBJ" SYMROOT="$PV_PPC_SYM"` and the corresponding i386 roots, with those variables bound to verified external directories. Full linking awaits Tasks 3–7.
- [ ] Commit: `ProcessViewer: add historical application build and ABI checks`.

## Task 3: Reconstruct process data, comparisons, and UID caching

**Files:** Create `APP/Process.m`, `UserIdCache.m`, `tests/process.m`,
`tests/process_child.c`, and necessary fixture files. Update their headers and
evidence records; keep `MapTableEnumerator` and C helpers with recovered owners.

**Interfaces:** Implement Task 1's exact prototypes for `NameForUID`, numeric
conversion/comparison helpers, and the `Process`/`MapTableEnumerator` methods.
Consumers rely on `+enumerateProcessesAndFetch:`, `+getSortContext:forKey:ascending:`,
`-initWithPid:`, `-objectForKey:`, `-arguments`, `-compare:context:`,
`-dictionaryRepresentation`, identity getters, and invalidation notifications.

- [ ] Capture expected observations or reviewed instruction-derived fixtures for enumeration, arguments containing spaces, numeric suffixes, absent fields, unknown UID, repeated UID lookups, empty results, and failed/partial process-data reads. Assert exact returned values, ordering, notification count, and cleanup behavior where the reference defines them.
- [ ] Add sorting assertions for numeric and textual keys, ascending/descending order, ties, and missing values using the recovered comparator semantics. Add refresh cases for a stable PID, process exit, and PID reuse with recorded identity behavior; avoid imposing a new PID policy.
- [ ] Run `make -C tests process RC_ARCHS=ppc` in the recorded target test environment; verify the missing implementation or identified mismatch is the failure. Keep output roots configured per Task 2. Repeat meaningful cases for i386 as implementations become available.
- [ ] Reconstruct enumeration, exact external-command invocation, kernel queries, parsing, lazy data fetch, dictionary representations, UID cache, map enumeration, comparisons, and lifecycle from evidence. Use target headers for kernel layout; introduce CPU conditionals only for measured differences.
- [ ] Run `process` and `abi` targets for both CPUs. Assert controlled-child identity/arguments and reference-defined failure behavior; compare stable fields separately from volatile time/memory samples. Review allocation, retain/release, notification, pipe, and task cleanup paths.
- [ ] Update source mappings and reviewed evidence for all owned functions in these units. Commit: `ProcessViewer: reconstruct process data and UID caching`.

## Task 4: Reconstruct process-type loading and matching

**Files:** Create `APP/ProcessType.m`, `tests/process_types.m`, and small temporary
file fixtures. Update `ProcessType.h` and evidence.

**Interfaces:** Exact Task 1 signatures for `+allProcessTypes`,
`-initWithDictionary:strings:`, `-matchesProcess:`, `-localizedName`, `-name`,
`-dealloc`, and the recovered file-reading helper. Consume Task 3's process keys.

- [ ] Add tests for supplied All Processes, User Processes, Administrator Processes, and NetBoot Processes definitions. Assert matching uses the recovered key/value and current-user rules and returns the correct localized names.
- [ ] Add cases for custom-file search order, duplicate definitions, missing fields/strings, unreadable files, malformed input, and empty lists where supported. Derive exact reject/fallback behavior from Task 1; test absent optional data without adding a new configuration mechanism.
- [ ] Run the `process-types` target and observe the expected missing implementation or mismatch. Reconstruct loading, matching, localization, and ownership, then rerun `process-types` and `process` for both CPUs.
- [ ] Update evidence and source mappings. Commit: `ProcessViewer: reconstruct process type loading and matching`.

## Task 5: Reconstruct table and header behavior

**Files:** Create `APP/ProcessTableView.m`, `tests/table.m`; update the matching
header and NIB contract evidence. Keep `ProcessTableHeaderView` in the module
confirmed by Task 1.

**Interfaces:** Recover and implement `-initWithCoder:`,
`-highlightedColumnIdentifier`, `-setHighlightedColumn:`, header `-drawRect:`,
and `-_modifySelectionWithEvent:onColumn:` exactly. Consume original NIB column
identifiers and ascending/descending resources.

- [ ] Add cases for NIB decoding, selected/highlighted columns, header clicks with each reference-supported modifier, no selected column, resized columns, and sort indicator drawing. Record expected selection and action dispatch from reference observations.
- [ ] Demonstrate failing table tests, then implement the table/header classes without modernizing rendering or event behavior.
- [ ] Run `table` and `abi` on both CPUs in a Window Server-capable test session. Compare drawing and event observations; record GUI checks explicitly if automated rendering inspection is unavailable. Full main-NIB app launch is deferred until its controller and inspector exist.
- [ ] Commit: `ProcessViewer: reconstruct process table and header behavior`.

## Task 6: Reconstruct controller lifecycle and user actions

**Files:** Create `APP/ProcessControl.m`, `tests/controller.m`; update its header,
build source list, test fixtures, and evidence.

**Interfaces:** Implement the full Task 1 `ProcessControl` inventory, including
startup, timer management, `-updateForSortChange:filterChange:`, data-source and
delegate methods, filter/type/sort actions, column visibility, export/print,
`-killProcesses:`, `-killProcessWithConfirmation:`, menu validation, and teardown.
Inspector calls use recovered signatures from Task 1; controller unit tests may
use a test-only receiver until Task 7 provides the real implementation.

- [ ] Add assertions for launch defaults, refresh interval boundaries/reset/bump behavior, timer replacement/cleanup, filtering and sorting, counts, current selection, type changes, column hide/show, menu state, and window close behavior. Include missing/invalid preferences and selection hidden by filtering.
- [ ] Add exact export-format fixtures, save-panel cancellation, output failure behavior, and print-operation setup checks. Match recovered encoding, delimiters, ordering, and formatting; do not substitute an assumed CSV format.
- [ ] Add termination tests for cancellation, successful signal delivery to a controlled child, permission denial, and a child exiting before delivery. Verify recovered signal, confirmations, messages, selected-PID handling, refresh behavior, and cleanup. Use a test-only failure injection for permission denial when a safe real setup is unavailable and label that evidence accordingly.
- [ ] Run `controller` to establish failures, reconstruct each method from Task 1 evidence, and rerun the target for both CPUs. Observe expected localized prompts and state transitions rather than assuming a modern AppKit equivalent.
- [ ] Review controller paths against all NIB actions, including export, print, about, help/responder-chain actions, and inspector toggles. Update evidence; commit: `ProcessViewer: reconstruct controller and process actions`.

## Task 7: Reconstruct inspector and complete application integration

**Files:** Create `APP/Inspector.m`, `tests/inspector.m`, and
`tests/integration.md`; add the recovered entry point in its original owning
module. Finish build registration and update evidence.

**Interfaces:** Exact `Inspector` signatures for `-setSplitView:`, `-setVisible:`,
`-isVisible`, `-showInfoForProcess:`, `-showInfoForNoSelection`,
`-showInfoForMultipleSelection`, private view/process transitions, notification
handling, table/tab/split-view delegates, and lifecycle. Entry point calls the
historical application runtime with the recovered arguments and behavior.

- [ ] Add cases for first and repeated inspector opening, zero/single/multiple selections, split-view resizing, tab changes, arguments table contents, selected process invalidation, selection hidden after filter/sort, and hide/show/teardown. Assert observed field contents, visible view, retained process, and notification lifetime.
- [ ] Run `inspector` to demonstrate the missing behavior, then reconstruct the inspector and entry point. Restore actual controller-to-inspector interaction in integration tests.
- [ ] Build complete `ProcessViewer.app` products for both CPUs with Task 2's recorded commands. Verify Mach-O architecture, measured dependencies, executable and resource paths, class/selector presence, and all resource hashes. No dummy methods or unresolved application-owned bodies may remain.
- [ ] Launch the original PowerPC app and each rebuilt architecture in their compatible disposable guests. Execute the integration checklist: NIB load, refresh, all process types, text filter, both sort directions, selection transitions, inspector fields/tabs, columns, export, print setup/output where available, about/help behavior, defaults persistence, termination confirmations, and quit cleanup.
- [ ] Record exact artifact identities, environment, expected/actual observations, and screenshots where useful. A missing print destination or GUI guest is a named incomplete check, not a pass. Commit: `ProcessViewer: reconstruct inspector and integrate application`.

## Task 8: Close parity gaps and validate both architectures

**Files:** Update architecture source maps/ledgers, `EVIDENCE/validation.md`,
profile rebuilt configuration, and only source files implicated by evidence.
Add focused regression fixtures for any newly discovered behavior defects.

**Interfaces:** A complete evidence record connects each owned function to source,
its recovered contract, reviewed implementation, test evidence, and unresolved
differences. Validation distinguishes binary parity from cross-CPU portability.

- [ ] Set `BINRECON_REBUILT` to the actual staged PowerPC executable recorded in Task 7 and add `rebuilt.path` to the profile. Revalidate identity, analyze both artifacts, and inspect comparison results. Exit 1 means inspect mismatches or incompleteness, not permission to weaken acceptance or hide functions.

```powershell
& $pvPython -m binrecon validate --profile $pvProfile
& $pvPython -m binrecon analyze --profile $pvProfile `
  --output tools/binrecon/out/processviewer-ppc/run-summary.json
& $pvPython -m binrecon function --profile $pvProfile --list
& $pvPython tools/binrecon/selector_check.py $env:BINRECON_REFERENCE $pvSource
& $pvPython tools/binrecon/symbol_name_check.py --binary $env:BINRECON_REFERENCE --source-dir $pvSource
& $pvPython tools/binrecon/parity_check.py $env:BINRECON_REFERENCE $env:BINRECON_REBUILT
& $pvPython tools/binrecon/import_check.py $env:BINRECON_REFERENCE $env:BINRECON_REBUILT
```

- [ ] Inspect every missing/extra/renamed selector, C symbol, string, and import; helper exit status alone is insufficient. Explain runtime/toolchain differences separately from app defects. Review all owned functions for branch structure, calls, constants, ordering, ownership, and failure behavior. Fix discrepancies from instruction evidence, with a focused failing regression before behavioral fixes.
- [ ] Resolve `$pvReferenceAnalysis` to the published reference analysis identified by `run-summary.json`, then generate a complete source map without `--scope-to-objc`. Review non-owned runtime entries separately rather than dropping them from the analysis silently.

```powershell
& $pvPython -m binrecon source-map --reference-analysis $pvReferenceAnalysis `
  --binary $env:BINRECON_REFERENCE --source-dir $pvSource --repo-root . `
  --objc-methods --output "$pvSource/reconstruction/ppc/source-map.json"
```

- [ ] Validate the map with `binrecon.schema.load_source_map`, passing the saved reference analysis and repository root. Require complete function partition and valid source lines; document runtime-only unmapped entries with reasons in the worklist. No app-owned unmapped functions or unresolved boundaries may remain.
- [ ] Seed a ledger once with `tools/binrecon/seed_ledger.py SOURCE_MAP REFERENCE_BINARY OUTPUT`, then use reviewed `binrecon ledger` transitions without overwriting prior reviews. Record signatures, control flow, assembly matches, or justified intentional differences honestly. Single-analyzer evidence is not independent consensus; a reviewed difference must not be relabeled as an assembly match.
- [ ] With an i386 oracle, run its separate analysis/comparison and ledger process and account for release deltas. Initialize its ledger with `binrecon analyze --ledger`, not the PowerPC-specific agreement labels in `seed_ledger.py`. Without an oracle, retain the explicit absence in `i386/` evidence and verify its ABI, shared contracts, build, deterministic tests, and GUI integration. Do not invent instruction-level i386 parity.
- [ ] Run all six test targets once on both final builds and repeat the integration cases affected by parity fixes. Recheck bundle hashes, all owned-function coverage, no placeholders, and isolated output locations. Record final artifact hashes and a per-CPU matrix for build, ABI, static evidence, deterministic tests, and GUI observations, including any blocked rows.
- [ ] Run `git diff --check`; review the scoped diff and changed evidence against the approved spec. Commit: `ProcessViewer: verify reconstruction parity and dual-architecture behavior`. Report any remaining verification blockers explicitly; do not claim full reconstruction acceptance until all required checks pass.

## Review and execution handoff

This plan is the deliverable of the current request; implementation has not
started. Tasks depend on earlier recovered contracts and should execute in order.
Native execution is recommended because these eight tasks share ABI, NIB, and
process-data evidence heavily. Subagent-driven execution remains an option with
fresh implementation/review contexts per task. Review this plan and choose an
execution method before beginning product changes.
