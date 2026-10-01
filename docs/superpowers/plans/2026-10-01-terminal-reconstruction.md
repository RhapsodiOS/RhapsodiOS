# Terminal Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct every application-owned Terminal function and original feature in `src/Applications/Administration/Terminal`, with PowerPC and i386 builds and verified runtime behavior.

**Architecture:** Shared historical Objective-C/C source, with the supplied PowerPC executable as behavioral authority. Recover interfaces and ownership before implementing bodies; maintain separate architecture evidence and distinguish i386 portability from direct reference-binary parity.

**Tech Stack:** Historical Objective-C runtime, Foundation/AppKit and other measured dependencies, PTYs, Mach/process APIs, Project Builder makefiles, Python 3.12 binrecon, IDA, and compatible native guests.

**Spec:** [Approved Terminal design](../specs/2026-10-01-terminal-reconstruction-design.md).

## Global Constraints

- Both 32-bit PowerPC and i386 are required build and runtime targets.
- Source destination is `src/Applications/Administration/Terminal`.
- Preserve classes, categories, selectors, ownership rules, document formats, resource connections, and error behavior.
- No modern Cocoa replacements, speculative features, or unrelated framework reconstruction.
- Reference executables, rebuilt executables, analyzer databases, and bulk generated evidence remain outside Git.
- Use temporary disk images for guest testing; preserve concurrent sessions and unrelated working-tree changes.
- Compilation, source-map completeness, and analyzer agreement alone are not behavioral parity.
- No matching i386 reference is currently identified. Never compare PowerPC instructions with i386 instructions as a parity test.
- Exact image identity is optional; all recovered owned functions and features are mandatory.
- Do not fabricate prototypes, expected outputs, licenses, or passing results to fill missing evidence.

## Review Focus

- A multibyte escape sequence split across PTY reads must preserve parser state and match the reference (Task 5).
- A child exits while output, timers, or a close action remain pending: preserve ordering without orphan processes or stale callbacks (Tasks 4 and 7).
- Documents contain nondefault colors, fonts, or embedded serialized values: preserve byte-order and typed-stream semantics across CPUs (Task 8).
- A distributed-object client requests captured stdout/stderr while its child produces sustained output: reproduce completion and buffering semantics (Task 10).
- NIB editor metadata names stale classes or actions: validate actual instantiated connections rather than requiring every editor listing to become a class (Tasks 3 and 7).

## File ownership and evidence contracts

In this plan, `APP` means `src/Applications/Administration/Terminal`. Paths under
it below are exact planned files unless specifically subject to recovered module
ownership. Keep original translation-unit/category boundaries where recovered;
Task 2 records any filename correction before dependent implementation begins.

| Files under APP | Responsibility |
| --- | --- |
| `reconstruction/reference.md`, `resource-inventory.md`, `build-environment.md` | Input identities, resource provenance, dependencies and runnable environment commands |
| `reconstruction/architecture.md`, `function-worklist.md`, `interfaces.md` | ABI, complete ownership partition, recovered declarations and task ownership |
| `reconstruction/ppc/source-map.json`, `ledger.json`, `verification.md` | PowerPC source coverage and reviewed verification |
| `reconstruction/i386/verification.md` | i386 build/runtime evidence; add native source map/ledger only against an identified native analysis |
| `PB.project`, `Makefile`, `Makefile.preamble`, `Makefile.postamble`, `Resources/` | Historical app build and original bundle contracts |
| `Shell.{h,m}`, `Filer.{h,m}`, `DirtMonitor.{h,m}` | Process lifecycle and asynchronous I/O |
| `Emulation.{h,m}`, `vt100.{h,m}`, `vt52.{h,m}` | Recovered emulation engines |
| `FieldView.{h,m}`, `FieldDraw.m`, `FieldEmulation.m`, `FieldMouseScroll.m` | Screen view and original categories |
| `Terminal.{h,m}`, `TerminalAgent.{h,m}`, `TerminalApp.{h,m}`, `CommandPanel.{h,m}`, `main.m` | Window/application orchestration |
| `Preferences.{h,m}`, `TString.{h,m}`, `FindPanel.{h,m}` | Settings, recovered string class, search |
| `EmulationController.m`, `MiscController.m`, `ProcessMonitorController.m`, `ShellController.m`, `StartupController.m`, `TextAttributeController.m`, `TitleBarController.m`, `WindowController.m` | Observed preference controllers; declarations in corresponding headers |
| `FieldPrint.{h,m}`, `ServiceCache.{h,m}`, `ServiceManager.{h,m}`, `ServiceProvider.{h,m}`, `TerminalDO.{h,m}`, `TerminalDOProtocol.h` | Printing, Services, distributed objects |
| `MutableEvent.{h,m}` | Observed event class; assign dependencies from analysis |
| `tests/Makefile`, `tests/README.md`, `tests/observe.{h,m}`, `tests/compare_observations.py` | Native observations and host comparison |

C helper owners, globals, and Display PostScript wrappers are deliberately
assigned by Task 2 from binary evidence, not invented as new abstractions.
No owned function may remain outside the resulting task/file manifest.

`interfaces.md` is the mandatory interface handoff: each entry contains symbol
or selector, exact return/argument types, source owner, instance/global layout,
ownership, callers, architecture differences, and evidence addresses. Names
below identify observed selectors, not invented type signatures. Resolve types
before writing their declarations or downstream calls.

Each worklist entry records reference hash, address, size, aliases, module,
owning task/file, classification, evidence, and review state. Source maps use
the existing `source-map-v1` schema and semantic loader; do not invent a parallel
coverage format. Shared IMPs retain all names without double-counting code.

## Commands and test conventions

From `D:\RhapsodiOS`, initial host commands are:

```powershell
$terminalPython = '.\.venv-binrecon\Scripts\python.exe'
$env:PYTHONPATH = 'tools/binrecon'
$env:BINRECON_REFERENCE = 'C:\Users\raynorpat\Downloads\test\Applications_ppc\Administration\Terminal.app\Terminal'
& $terminalPython -m pytest tools/binrecon/tests/test_macho.py tools/binrecon/tests/test_objc_index.py -q
```

After Task 2 creates the profile:

```powershell
& $terminalPython -m binrecon validate --profile tools/binrecon/profiles/terminal-ppc.json
& $terminalPython -m binrecon analyze --profile tools/binrecon/profiles/terminal-ppc.json --ledger tools/binrecon/out/terminal-ppc/ledger.json --output tools/binrecon/out/terminal-ppc/run-summary.json
```

Inspect `complete`, diagnostics, and published artifact hashes in the summary;
reference-only success is not reconstruction acceptance. Keep reviewed compact
ledger entries distinct from generated runs and never promote status automatically.

Task 3 creates native test targets `abi`, `process`, `storage`, `emulation`,
`display`, `application`, `preferences`, `documents`, `find`, `printing`,
`services`, `distributed-objects`, and `integration` as implementations arrive.
Run them from APP with `make -C tests TARGET RC_ARCHS=ppc` and the equivalent
`RC_ARCHS=i386`; supply `TERMINAL_APP`, `OBSERVATION_DIR`, and `CASE_FILE` as
documented absolute paths. These variables are contracts for the new harness,
not claims that targets already exist. Record actual guest paths in Task 3.

Use separate processes/guest snapshots for reference and rebuilt runs. Native
inspection loads or launches the selected app with its own identity recorded;
never silently inspect the installed system app. If internal classes cannot be
loaded independently, use a test-only rebuilt entrypoint plus reference UI/PTY
observations and disassembly; document this limit instead of claiming equivalent
private-method execution. Preserve the production entrypoint and binary behavior.

Fixtures record exact reference observations first. The host comparator may
normalize explicitly named nondeterministic fields (PID, port, address, clock),
but never error values, output bytes, serialized fields, or event ordering.
Each behavior task follows capture -> meaningful failing check -> implementation
-> passing check -> evidence update. Unavailable reference execution remains
an open verification item; fabricated fixtures are prohibited.

## Task 1: Freeze input and resource provenance

**Files:** Create `APP/reconstruction/reference.md`, `resource-inventory.md`,
and `build-environment.md`.
**Interfaces:** Produces immutable executable/resource identities and a dependency
inventory consumed by analysis, packaging, and the test harness.

- [ ] Hash the executable and every bundle file with `Get-FileHash -Algorithm SHA256`; verify executable size 333472 and SHA-256 `B83EDEF820DF31A406FBFBBFB86DD5B80DB6818BD6D8BD14211680F2BD8E57D7` against the spec.
- [ ] Inventory all seven NIBs, localized strings, service definitions, images, credits, bundle metadata, document types, external help reference, and the Developer `Headers/Apps/TerminalDOProtocol.h`. Record original relative paths and hashes.
- [ ] Decode linked dependencies and launch metadata. Inspect available guest/compiler/SDK capabilities using `vm/README.md`; do not start shared builds, expose credentials, or alter running guests.
- [ ] Check any accessible candidate i386 reference by identity and release, including fat slices if encountered. Record the search scope and absence if none is available; keep i386 runtime acceptance required.
- [ ] Review identities against the spec and resource inventory against the directory listing; commit only these documents as `Terminal: record reference and resource provenance`.

## Task 2: Recover complete function ownership and interfaces

**Files:** Create `tools/binrecon/profiles/terminal-ppc.json`,
`APP/reconstruction/{architecture,interfaces,function-worklist}.md` and initial
PowerPC coverage records. Create `terminal-i386.json` when a native artifact
exists, using its real role and identity.
**Interfaces:** Consumes Task 1 identities; produces the typed interface and
function-to-task contracts used by all later tasks.

- [ ] Run the targeted reader tests above. Confirm `read_macho` still reports 191288 text bytes and 972 symbols and `objc_method_index` reports 441 distinct addresses; investigate differences instead of overwriting the baseline.
- [ ] Adapt `tools/binrecon/profiles/scsiserver-ppc.json` to Terminal: reference-only initially, PowerPC/big-endian, IDA enabled, Ghidra/angr disabled, and output `../out/terminal-ppc`. Set `reference.expected_size` to 333472 and `reference.expected_sha256` to Task 1's verified hash.
- [ ] Run validation and analysis commands above. Inspect analyzer logs, metadata, disassembly, and pseudocode; resolve missing functions, aliases, tail code, jump tables, and conflicting boundaries.
- [ ] Account for every executable region and every observed class/category, including `vt100`, `vt52`, all controllers, `MutableEvent`, `TString`, startup/runtime code, and imported stubs. Explicitly justify exclusions; 441 methods is not the coverage denominator.
- [ ] Recover declarations, ivars, globals, Objective-C encodings, protocols, constants, serialization layouts, PTY/signal/Mach contracts, and module ownership. Verify the full Developer protocol header against the executable before reuse.
- [ ] Assign every C helper, including Chunk/line operations, default-stream helpers, process helpers, search helpers, and DPS routines to its evidence-established source file and later task. Record exact file paths before their implementation.
- [ ] Publish a dependency-ordered worklist and review recovered interfaces before dependent code. Tooling changes are allowed only for reproduced blockers, with a failing fixture, minimal fix, and passing targeted/full binrecon tests.
- [ ] Commit as `Terminal: recover function inventory and ABI contracts`.

## Task 3: Establish build, resource, and observation infrastructure

**Files:** Create APP build files, `Resources/`, recovered headers,
`tests/{Makefile,README.md,observe.h,observe.m,compare_observations.py,abi.m}`,
and `tests/test_compare_observations.py`; update `build-environment.md`.
**Interfaces:** Build honors historical `RC_ARCHS`, `OBJROOT`, `SYMROOT`, and
`DSTROOT`. Test targets consume the explicit app/case/output paths above.

- [ ] Inspect the repository's Project Builder application rules and available SDK examples; record exact compiler/linker/SDK paths and native build commands for each CPU. Verify Objective-C compilation and all measured dependencies independently of missing app bodies.
- [ ] Create the historical application project and resource rules with separate architecture output roots. Preserve executable name, main NIB, icons, `.term`/`.svcs` metadata, and resource paths; avoid speculative global manifest or image integration.
- [ ] Preserve resources with provenance and hashes, or record exact reconstruction transformations. Verify actual NIB classes, outlets, and actions against recovered interfaces, distinguishing editor listings from instantiated connections.
- [ ] Define deterministic observation cases and a comparator. Add tests proving it rejects wrong app hashes, changed bytes/error codes/order, missing cases, and unsupported normalization while accepting explicitly normalized PID/address fields.
- [ ] Run `& $terminalPython -m pytest src/Applications/Administration/Terminal/tests/test_compare_observations.py -q`, first failing for missing comparator behavior, then passing after minimal implementation.
- [ ] Add ABI observations for recovered enums, sizes, offsets, ivar/type encodings, and public protocol signatures. Test both CPU compilations and available reference execution; record unavailable native steps separately.
- [ ] Commit as `Terminal: add dual-architecture build and observation harness`.

## Task 4: Reconstruct process and asynchronous I/O behavior

**Files:** `Shell.{h,m}`, `Filer.{h,m}`, `DirtMonitor.{h,m}`, evidence-owned
signal/process/environment helpers, `tests/process.m`, `tests/cases/process.json`.
**Interfaces:** Task 2 types for `system:login:folder:env:`, `handleFileActivity:`,
`output:len:`, `handleSignal`, `registerDevice:withFD:`, and process callbacks.

- [ ] Capture reference cases for shell selection, login bookkeeping, environment/directory, PTY allocation, partial I/O, EOF, SIGCHLD, SIGHUP, allocation/exec failure, and status monitoring; assert bytes, status, callback order, descriptor/child cleanup.
- [ ] Include child exit during pending output and repeated close/kill requests. Run missing/rebuilt behavior and record specific mismatches before implementation.
- [ ] Reconstruct process creation, privilege transitions if present, signal integration, buffer ownership, process queries, cleanup, and original error paths from evidence. Preserve historical interfaces rather than replacing them with modern PTY APIs.
- [ ] Run `process` on both CPU builds as linkable groups become available; keep full-app checks pending until Task 7. Update per-function source/evidence records.
- [ ] Commit verified groups with `Terminal: reconstruct process and PTY handling`.

## Task 5: Reconstruct storage and terminal emulation

**Files:** Evidence-owned Chunk/line helper units from Task 2, `TString.{h,m}`,
`Emulation.{h,m}`, `vt100.{h,m}`, `vt52.{h,m}`, `FieldEmulation.m`,
`tests/{storage,emulation}.m`, `tests/cases/{storage,emulation}.json`.
**Interfaces:** Exact Task 2 line/node structures and helper prototypes;
`output:len:`, `key:`, `termDidResize:`, `translateChars:len:` and recovered view callbacks.

- [ ] Capture line insertion/deletion/split/join, empty lines, capacity growth, asymmetric byte values, scrollback pruning, and ownership behavior; assert contents, lengths, and state without comparing allocator addresses.
- [ ] Capture every recovered VT100/VT52 command and mode with cursor, cells, attributes, margins, wrap, tab, erase, and scrolling observations. Add split-at-every-byte versions of escape fixtures and malformed/incomplete sequences.
- [ ] Demonstrate the relevant missing behavior or mismatch, then reconstruct storage and parser groups in dependency order. Derive limits and transition tables from evidence; do not substitute a modern terminal emulator.
- [ ] Run `storage` and `emulation` for both architectures; assert whole-buffer and split-buffer observations agree where reference behavior does. Audit signed-character and endian-sensitive accesses.
- [ ] Commit storage and emulator groups separately; update the worklist after each verified group.

## Task 6: Reconstruct drawing, selection, and input

**Files:** `FieldView.{h,m}`, `FieldDraw.m`, `FieldMouseScroll.m`,
`MutableEvent.{h,m}`, evidence-owned DPS wrappers, `tests/display.m`,
`tests/cases/display.json`.
**Interfaces:** Task 2 view ivars, category selectors, event semantics and DPS
signatures; consumes Task 5 screen state and Task 4 output interface.

- [ ] Capture fonts/metrics, cursor shapes and blink, clipping, attributes/colors, redraw, scrolling, mouse selection/word boundaries, paste, keyboard modifiers, and resize observations; record visual evidence with font/display configuration.
- [ ] Run failing cases, then reconstruct drawing and input groups, preserving direct class references and original categories. Recover DPS wrappers from instructions/strings; use generated wrappers only after verifying their emitted contract.
- [ ] Run `display` on both guests. Compare cursor/cell geometry and output bytes; distinguish rasterization differences from incorrect geometry or state instead of masking all screenshot differences.
- [ ] Commit as `Terminal: reconstruct display and input behavior`; update method/helper mappings.

## Task 7: Reconstruct application and window lifecycle

**Files:** `Terminal.{h,m}`, `TerminalAgent.{h,m}`, `TerminalApp.{h,m}`,
`CommandPanel.{h,m}`, `main.m`, `tests/application.m`, `tests/cases/application.json`.
**Interfaces:** Recovered startup, `setUpWithDefaults:inFolder:env:`,
`newShell:inFolder:env:`, `childExit:status:`, timers, and NIB contracts.

- [ ] Capture startup actions, new command/window, titles, resize notification, activation, miniaturization, close policies, pending timers, process dirtiness, and quit-with-live-children. Assert lifecycle and resource cleanup order.
- [ ] Reconstruct orchestration after demonstrating missing/mismatched behavior; connect actual NIB instances and verify each connected action/outlet. Do not implement stale editor-only classes merely to satisfy a text scan.
- [ ] Build the complete implemented app portion for each CPU, record remaining undefined symbols as worklist items, and run `application` where link-complete. Re-run process/display scenarios affected by integration.
- [ ] Commit as `Terminal: reconstruct application and window lifecycle`.

## Task 8: Reconstruct defaults, preferences, and documents

**Files:** `Preferences.{h,m}`, all eight controller units/headers in the ownership
table, evidence-owned default-stream units, affected TerminalApp methods,
`tests/{preferences,documents}.m`, `tests/cases/{preferences,documents}.json`.
**Interfaces:** Task 2 defaults keys/types, controller actions/outlets, and
`_defaultsFromDB`, `_writeDefaultsToTypedStream`, `_readDefaultsFromTypedStream` prototypes.

- [ ] Capture absent/present defaults, startup/shell/emulation/display/process options, per-window changes, save/save-as/save-all, library entries, and reference behavior for truncated or malformed documents.
- [ ] Include nondefault colors/fonts, asymmetric numeric values, and cross-CPU `.term` exchange. Assert reference-compatible serialized interpretation; do not impose raw byte equality when documented stream metadata is nondeterministic.
- [ ] Demonstrate failures, reconstruct each controller and serialization helper from evidence, and preserve original keys, units, limits, error behavior, and ownership.
- [ ] Run `preferences` and `documents` on both CPUs, including PowerPC-created documents opened on i386 and the reverse. Verify UI defaults actually affect shell/emulator/window behavior.
- [ ] Commit verified preference and persistence groups separately.

## Task 9: Reconstruct search and printing

**Files:** `FindPanel.{h,m}`, `FieldPrint.{h,m}`, recovered search/stream helpers,
`tests/{find,printing}.m`, `tests/cases/{find,printing}.json`.
**Interfaces:** Task 2 search comparison/direction rules, selection APIs,
print range/attribute actions, and PrintAccessory NIB connections.

- [ ] Capture forward/backward searches, case modes, empty/multiline patterns, scrollback boundaries, imported/exported find text, and selection navigation; assert exact reference match/selection behavior.
- [ ] Capture all print ranges and attribute choices, cancellation, and original error paths; compare emitted print data and pagination under recorded settings without requiring physical printing.
- [ ] Run failing cases and reconstruct corresponding methods/helpers, preserving stream positions and view state across search/print operations.
- [ ] Run `find` and `printing` on both guests and commit as `Terminal: reconstruct search and printing`.

## Task 10: Reconstruct Services and distributed objects

**Files:** `ServiceCache.{h,m}`, `ServiceManager.{h,m}`, `ServiceProvider.{h,m}`,
`TerminalDO.{h,m}`, `TerminalDOProtocol.h`, evidence-owned service helpers,
`tests/{services,distributed_objects}.m`, `tests/cases/{services,distributed_objects}.json`.
**Interfaces:** Verified `TSTerminalDOServices` header and Task 2 Services contracts;
consumes process/application ownership and completion interfaces.

- [ ] Capture `.svcs` loading/saving, service editing, prompts, pasteboard types, cache refresh and errors. Assert exact reference-visible service behavior.
- [ ] Verify enum values from the supporting header against evidence: window 0/2/4/8, shell 1/2/4/8, exit action 0/1/2. Recover protocol version and all overloads, especially the full `runCommand:inputData:outputData:errorData:waitForReturn:windowType:windowHandle:exitAction:shellType:windowTitle:directory:environment:returnCode:` selector.
- [ ] Capture synchronous/asynchronous calls, input, separate stdout/stderr, existing/new/no window, directory/environment, handles, return status, invalid inputs, and client disconnect. Add sustained-output cases while capturing both streams; assert completion and reference buffering semantics.
- [ ] Demonstrate mismatches, reconstruct service and DO groups, and preserve marshalling qualifiers, ownership, command selection, failure behavior, and exit policies.
- [ ] Run `services` and `distributed-objects` on both guests; exercise cross-CPU DO exchange if both compatible guests are available, recording unavailable coverage explicitly. Commit groups separately.

## Task 11: Close function coverage and both-architecture acceptance

**Files:** Finalize architecture source maps/ledgers/verification documents,
`tests/integration.m`, `tests/cases/integration.json`, and only source/build files
whose measured discrepancies require correction.
**Interfaces:** Consumes the complete Task 2 inventory and all native test targets;
produces reproducible acceptance evidence tied to artifact identities.

- [ ] Finish every unassigned or incomplete owned function, category, helper, global and original feature from the worklist. Check naming, imports, selectors, constants, memory access widths, control flow, and decompiler residue against instructions; no success-return stubs or dead approximations count as complete.
- [ ] Build clean, separate PowerPC and i386 artifacts with the recorded commands. Verify CPU headers, dependencies, resource packaging and runtime identities. Add rebuilt artifacts to profiles without replacing reference identity.
- [ ] Analyze and compare PowerPC reference/rebuilt artifacts with binrecon. Investigate normalized-function mismatches individually; classify compiler/layout differences with evidence and behavioral checks rather than weakening acceptance globally.
- [ ] Analyze the native i386 artifact using a single-input profile if no reference exists. The current schema requires a `reference` slot: place the rebuilt i386 input there only for analysis, name the profile explicitly "Terminal i386 rebuilt-only analysis", omit `rebuilt`, and record its non-oracle role in verification evidence. If a matching reference is found, establish release compatibility first, then replace this configuration with native comparison/source-map/ledger evidence. Never describe rebuilt-only analysis as reference parity.
- [ ] Validate `ppc/source-map.json` with `binrecon.schema.load_source_map(path, reference_analysis=analysis, repo_root=Path.cwd())`, as documented in the binrecon README. Require complete partition, exact input identity, valid source bounds, and reviewed overlap/alias handling.
- [ ] Run all native targets and integrated scenarios on both CPUs in isolated guests. Include sustained sessions, multiple windows, preferences/documents, search/print, Services/DO, and quit during pending output; preserve artifacts/logs externally and record hashes and outcomes.
- [ ] Run targeted regressions after discrepancy fixes; run the full binrecon suite if shared tooling changed. Explicitly report blocked tests, remaining mismatches and unresolved functions; any mandatory omission prevents full-completion claims.
- [ ] Review the final scope against every spec section and function inventory entry. Commit task-owned source and compact evidence as `Terminal: verify reconstruction on PowerPC and i386` only if the message accurately reflects achieved verification.

## Execution and completion handoff

The stages share recovered ABI and state contracts, so execute in dependency
order. Within a stage, use small function groups and focused commits; do not
declare the stage complete based on a subset of its worklist. Recommend native
execution to retain the evolving reference context, followed by independent
whole-branch review. Subagent-driven execution is also supported once Task 2
provides explicit ownership/interfaces for each worker.

This document is an implementation plan, not an execution report. The user
reviews it and selects an execution method before source reconstruction begins.
