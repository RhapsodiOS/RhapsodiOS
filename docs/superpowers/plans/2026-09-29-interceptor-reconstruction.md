# Interceptor Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct the complete Interceptor framework in `src/Kits/Interceptor`, with PowerPC and i386 builds and separately documented parity and runtime verification.

**Architecture:** Shared historical Objective-C/C source, using the supplied PowerPC framework as behavioral authority and DR2's two slices to distinguish architecture differences from release differences. Recover wire contracts and private state from evidence; use separate architecture ledgers and preserve original Objective-C translation units.

**Tech Stack:** Historical Objective-C runtime, C, Mach IPC/MIG, Project Builder framework makefiles, Python 3.12 binrecon tooling, IDA, compatible Rhapsody/Mac OS X Server build and test environments.

**Spec:** [Approved design](../specs/2026-09-29-interceptor-reconstruction-design.md).

## Global Constraints

- Target both 32-bit PowerPC and i386; reconstruct under `src/Kits/Interceptor`.
- Preserve manual memory management, the historical Objective-C runtime, published layouts, selectors, error behavior, and wire contracts.
- Reference binaries and generated analyzer databases remain outside Git.
- Use version A and install name `/System/Library/Frameworks/Interceptor.framework/Versions/A/Interceptor`.
- Do not expand this reconstruction into Foundation, AppKit, or Window Server reimplementation.
- Use disposable disk images/overlays; never modify a shared guest base or replace its installed framework for testing.
- No global `src/Manifest` or OS-image packaging changes in this plan.
- Do not count placeholders, successful compilation, source-map coverage, or analyzer agreement alone as behavioral parity.
- Stage only task-owned files. Existing unrelated untracked files must remain untouched.

## Review Focus

- Window Server dies with mappings/locks outstanding: recover notification and teardown order; test in Tasks 6 and 7.
- Geometry changes while a direct bitmap is locked or buffered: preserve observed transition and flush behavior; test in Task 10.
- Palettes have unsupported sizes or indices, or modes change during a fade: reproduce observed validation and restoration; test in Tasks 8 and 9.
- Pixel data has nontrivial stride, multiple planes, or byte-order-sensitive values: preserve supported copy/address behavior; test in Tasks 4 and 7.
- DR2 lacks the two newer default-palette methods: retain newer behavior on i386 without falsely reporting DR2 parity; test in Tasks 2 and 8.

## Execution conventions and file map

Read `CLAUDE.md` and the spec first. At execution start, inspect attached worktrees
and use a suitable isolated checkout under a `codex/` branch. Do not move or clean
the current checkout's unrelated work. All commands below are repository-relative
unless marked as guest commands. Keep build products in external output roots.

Host test setup uses the existing environment:

```powershell
$env:PYTHONPATH = 'tools/binrecon'
$interceptorPython = '.\.venv-binrecon\Scripts\python.exe'
& $interceptorPython -m pytest tools/binrecon/tests/test_macho.py tools/binrecon/tests/test_objc_index.py -q
```

Record baseline failures before changing tooling. Confirm the interpreter and
analyzer versions actually installed; current driverLoader profiles specify IDA
9.4, while the README contains older installation examples. Do not downgrade or
install tools merely to match stale examples.

The primary binary's module metadata names these exact original units:
`NSDirectBitmap.m`, `NSDirectPalette.m`, `NSDirectScreen.m`, `NSFramebuffer.m`,
`NSInterceptedRect.m`, `NSInterceptorClient.m`, `NSShape.m`, `NSSimpleBitmap.m`,
and `NSFramework_Interceptor.m`. Preserve these names. Keep categories with their
owning module and `_NSShapeEnumerator` with `NSShape.m`. Locate C helpers from
call references/module evidence; use `InterceptorIPC.c` and private
`InterceptorIPC.h` for standalone IPC routines, and `Interceptor.defs` only if
MIG regeneration is demonstrably wire-compatible. These C filenames are planned
organization, not claimed recovered original names.

Create `Private/NSInterceptorClient.h`, `Private/NSInterceptedRect.h`, and
`Private/InterceptorPrivate.h` for recovered internal declarations. Do not invent
private method signatures ahead of metadata/disassembly recovery.

Create `reconstruction/{reference.md,abi.md,release-differences.md,function-worklist.md,build-environment.md,validation.md}`
and `reconstruction/{ppc,i386}/` beneath the framework. Keep compact reviewed
evidence and ledgers there; raw analyzer outputs go under ignored
`tools/binrecon/out/interceptor-{ppc,i386}`. Check ignore rules before generation.

Tests live under `src/Kits/Interceptor/tests/`. Add a historical makefile with
targets `abi`, `bitmap`, `shape`, `ipc`, `client`, `framebuffer`, `palette`,
`screen`, `direct-bitmap`, and `integration` as their owners are implemented.
Each target executes its test program and fails on failed assertions. Tests must
load the explicitly selected reference or rebuilt framework, verify its identity,
and never silently resolve to the system-installed framework. Use separate
processes for reference and rebuilt runs because Objective-C class names collide.

Expected results below are established from the primary reference first. Tests
compare structured observations rather than assumed modern API behavior. Cases
that could fault the reference run in disposable child processes and report exit
status as part of the observation. Do not normalize away ownership, ordering,
message-layout, error, or data differences.

## Task 1: Support framework dylibs in the analysis pipeline

**Files:** Modify `tools/binrecon/binrecon/macho.py`; extend
`tools/binrecon/tests/macho_fixture.py`, `test_macho.py`, and `test_objc_index.py`.
Modify adapters/schema only if a reproduced dylib-specific failure requires it.
**Interfaces:** Preserve `read_macho(path: Path) -> dict` and
`objc_method_index(path) -> dict`; accept `MH_DYLIB` (6) in addition to existing types.

- [ ] Add synthetic little- and big-endian dylib fixture tests asserting file type 6, correct section addresses/symbols, and identical Objective-C names to the corresponding executable fixture. Retain malformed-command and truncated-image rejection tests.
- [ ] Run the targeted host tests above; confirm failure specifically on dylib rejection.
- [ ] Add minimal dylib support without changing input bytes or pretending dylibs are executables. Preserve load-command evidence needed to inspect install names and dependencies.
- [ ] Run targeted tests, then the full `tools/binrecon/tests` suite once. Read the primary binary and confirm 540 symbol-table entries and 57332 text bytes. Cross-check the 234 named methods against metadata, explicitly resolving aliases rather than assuming equal counts.
- [ ] Commit only tooling changes: `binrecon: support framework dylib analysis`.

## Task 2: Establish reference inventories and a complete worklist

**Files:** Create the reconstruction documents listed above; create
`tools/binrecon/profiles/interceptor-ppc.json` and `interceptor-i386.json`.
**Interfaces:** Function-worklist entries identify reference hash, CPU, address,
symbol/selector aliases, module, source owner, callers, evidence, and unresolved
questions. `abi.md` records exact recovered public/private signatures and layouts
for later tasks; consumers must use these declarations rather than infer types.

- [ ] Hash all supplied headers, normal/profile binaries, and DR2 container. Verify the exact hashes and slice offsets in the spec before extraction. Extract both DR2 slices into an external evidence directory and verify their slice hashes.
- [ ] Inventory modules/classes/categories/protocols/ivars/type encodings, exports/imports, C functions, constants, and indirect symbols. Check every executable section for unattributed owned code; symbol counts alone are not a function inventory.
- [ ] Confirm the symbol-level release delta: newer-only `+[NSDirectPalette defaultColorPalette]` and `+[NSDirectPalette defaultGrayPalette]`; no DR2-only named Objective-C methods were found during planning. Compare method bodies, C symbols, globals, layouts, and headers as well; two extra methods do not prove that all shared behavior is identical.
- [ ] Configure profiles from current driverLoader examples, pinning reference size/hash. Begin reference-only (omit `rebuilt`); enable IDA on both CPUs and leave unsupported PowerPC adapters disabled. Enable another i386 analyzer only after its dylib fixture test succeeds. Record analyzer limitations rather than equating one analyzer with consensus.
- [ ] With `BINRECON_REFERENCE` set to each correct thin image, run `python -m binrecon validate --profile tools/binrecon/profiles/interceptor-CPU.json`, then `analyze` for that profile using the existing venv interpreter. Inspect run summaries and produce complete owned-function worklists. Record decompiler/disassembly disagreements.
- [ ] Recover private signatures, state fields, message layouts, and source ownership needed by Tasks 4–10. A task with unresolved signatures stays blocked until its evidence is recovered; do not fill the gap with a guessed implementation.
- [ ] Commit profiles and reviewed evidence: `Interceptor: record reference ABI and reconstruction worklist`.

## Task 3: Establish dual-architecture build and test isolation

**Files:** Create the nine public headers, `Makefile`, `Makefile.preamble`,
`Makefile.postamble`, `PB.project`, `Resources/Info-nextstep.plist`, private headers,
`tests/Makefile`, `tests/abi.m`, and `tests/test_support.{h,m}`.
**Interfaces:** Build honors `RC_ARCHS`, `OBJROOT`, `SYMROOT`, `DSTROOT`; test
invocations accept `FRAMEWORK_ROOT` pointing at the explicitly selected framework.
Private signatures come verbatim from Task 2's recovered declarations.

- [ ] Copy public headers byte-for-byte from the supplied reference and verify hashes. Keep precompiled `Interceptor.p` external. Do not attach an invented license to recovered material or copy SoundKit's license as though it applied here.
- [ ] Record exact compiler, linker, MIG, SDK, dependency, and guest paths in `build-environment.md`. Probe Objective-C compilation and linkage for each CPU. Verify libDriver, Foundation, AppKit, and System imports can be resolved. Missing prerequisites block the affected build/runtime claim, not independent reconstruction work.
- [ ] Write ABI tests for enum values, public struct sizes/offsets, class instance sizes, ivars, selector type encodings, and exported globals against Task 2's architecture-specific inventories. Verify they reject an intentionally altered fixture.
- [ ] Adapt SoundKit's framework build conventions for Interceptor version A; remove unrelated SoundKit resources/flags. Set measured install name and dependencies. Add source units as their implementations become available; do not ship a dummy stub framework to satisfy linking.
- [ ] Establish staged commands in the compatible build environment: `make RC_ARCHS=ppc OBJROOT=<external-ppc-obj> SYMROOT=<external-ppc-sym>`, then the i386 equivalent. Record resolved runnable commands, not placeholders, in `build-environment.md`. Validate header/test compilation now; full linking awaits implementation.
- [ ] Add a test-only loading arrangement that proves the selected library identity without replacing the installed framework. Exercise reference-side ABI tests on each available CPU and record unavailable guest execution separately.
- [ ] Commit build/test foundation: `Interceptor: add historical framework build and ABI checks`.

## Task 4: Reconstruct simple bitmaps and copy primitives

**Files:** Create `NSSimpleBitmap.m`, `NSFramework_Interceptor.m`, `tests/bitmap.m`;
place copy helpers in the Task 2 evidence-established owning module.
**Interfaces:** Implement the exact `NSDirectBitmapProtocol`, published
`initWithBitmapDataPlanes:...bitsPerPixel:`, categories, and global symbols from
the inventory. Recover `CopyLong`, `CopyShort`, `CopyByte`, `CopySrcToDst` signatures
before writing calls; their symbol names alone do not establish parameter types.

- [ ] Add reference cases for packed/planar images, null/supplied planes, zero dimensions, explicit/default row bytes, asymmetric pixel byte patterns, and supported alpha/color-space combinations. Assert metadata, copied bytes, ownership, and recorded failure behavior.
- [ ] Run reference observations; run the rebuilt target to demonstrate the missing implementation or specific mismatch.
- [ ] Reconstruct methods, globals, and copy routines from instruction/data evidence; preserve partial-row and alignment behavior without assuming overlap support.
- [ ] Run guest `make -C tests bitmap RC_ARCHS=<cpu> FRAMEWORK_ROOT=<selected-root>` for both CPU artifacts as available. Assert exact bytes and metadata; update source mappings and per-function evidence.
- [ ] Commit: `Interceptor: reconstruct simple bitmap and copy behavior`.

## Task 5: Reconstruct shapes and enumeration

**Files:** Create `NSShape.m`, `tests/shape.m`.
**Interfaces:** Published NSShape methods and `- (NSRect *)nextRect`; internal
`empty_shape`, `rect_shape`, equality, offset, union, intersection, and difference
helpers use Task 2's recovered signatures and ownership.

- [ ] Capture reference results for empty/disjoint/touching/overlapping rectangles, negative coordinates, repeated operations, copy independence, and self-aliasing operations. Assert enumeration order and rectangle decomposition as observed, not merely equal covered area.
- [ ] Confirm the rebuilt test fails before implementing each operation group.
- [ ] Reconstruct shape storage, operations, and enumerator lifetime, including behavior when the shape is mutated during enumeration as established by the reference.
- [ ] Run `make -C tests shape` with explicit architecture/framework selection; compare exact observations on each CPU, then record function coverage.
- [ ] Commit: `Interceptor: reconstruct shape operations and enumeration`.

## Task 6: Recover Mach IPC and client/rectangle state

**Files:** Create `InterceptorIPC.{c,h}`, `NSInterceptorClient.m`,
`NSInterceptedRect.m`, `tests/ipc.c`, `tests/client.m`; populate recovered private
headers. Add `Interceptor.defs` only if verified regeneration is selected.
**Interfaces:** Exact recovered exported `Interceptor*` and private `_Interceptor*`
signatures, context-port ownership, message IDs/descriptors, notifications, and
private selectors from Task 2. Do not assign wire values from public enums.

- [ ] Add a test transport that captures outgoing messages and supplies recorded successful/error replies. Tests assert IDs, sizes, type descriptors, payload fields, reply checks, port disposition, and cleanup. Normalize only recorded nondeterministic port/address values using explicit field maps.
- [ ] Include wrong reply ID, short reply, failed send/receive, partial context creation, repeated teardown, geometry notification, and server-death-with-live-context cases. Capture expected behavior before implementation and demonstrate mismatches.
- [ ] Reconstruct rendezvous/context routines and each IPC operation in small verified groups. If using MIG, compare emitted messages and validation behavior against the binary before accepting generated output.
- [ ] Reconstruct client and intercepted-rectangle state transitions, callbacks, locking, and teardown. Preserve ordering established by references; do not add speculative retries.
- [ ] Run `make -C tests ipc` and `make -C tests client` for both CPU selections. Separate transport-fixture passes from real server integration. Record the wire layouts and evidence for every operation.
- [ ] Commit IPC and client groups separately with `Interceptor: reconstruct ...` messages.

## Task 7: Reconstruct framebuffer access

**Files:** Create `NSFramebuffer.m`, `tests/framebuffer.m`.
**Interfaces:** Published initializers, mapping, locking, conversion-table methods,
`addressForPoint:`, private category, and `NSRemapMegaPixelDisplayForCurrentThread`;
consume the recovered IPC/client interface from Task 6.

- [ ] Capture cases for mapped/unmapped initialization, mapping refusal, row padding, asymmetric pixel data, screen origins, mode-specific locks, repeated unmap, and server death while locked. Assert returned addresses as offsets, state, and cleanup ordering.
- [ ] Run cases against missing/reconstructed behavior and confirm meaningful failures.
- [ ] Reconstruct mapping/token ownership, cached per-screen instances, access checks, conversion tables, and failure paths. Preserve architecture-specific behavior only where evidenced.
- [ ] Run `make -C tests framebuffer` on each CPU; ensure fixture mapping tests never dereference arbitrary recorded target addresses. Perform real mapping tests only in disposable compatible guests.
- [ ] Commit: `Interceptor: reconstruct framebuffer mapping and access`.

## Task 8: Reconstruct palette management

**Files:** Create `NSDirectPalette.m`, `tests/palette.m`.
**Interfaces:** All published palette methods, coding/copying/enumeration behavior,
private helpers, and both newer default-palette class methods.

- [ ] Capture default palette bytes/counts, indexed updates, nearest-color ties, copy independence, coding round trips, blended palette values, boundary indices, and unsupported sizes. Record actual rounding and failure behavior; do not impose clamping without evidence.
- [ ] Add dedicated primary-reference observations for `defaultColorPalette` and `defaultGrayPalette`. On DR2, explicitly assert their absence as a reference capability result; on reconstructed i386 assert primary-reference behavior, not absence.
- [ ] Confirm failing cases, reconstruct methods and constants, then run `make -C tests palette` for both architectures. Inspect raw palette byte ordering separately from numerical RGB values.
- [ ] Update the release-difference ledger so the two newer methods cannot be counted as unexplained i386 extras or incorrectly omitted.
- [ ] Commit: `Interceptor: reconstruct palettes and newer defaults`.

## Task 9: Reconstruct direct screen behavior

**Files:** Create `NSDirectScreen.m`, `tests/screen.m`.
**Interfaces:** Published screen/mode/fade/shield/palette methods, private/obsolete
categories, mode dictionary keys, exception names, and notifications from inventory.

- [ ] Capture mode filtering/selection and ties, unavailable modes, shielding lifecycle, zero/nonzero fade duration, interrupted fades, palette changes, mode switches during fades, and cursor balancing. Assert notification sequence and resulting state; use timing tolerances only where reference measurements justify them.
- [ ] Confirm missing/mismatching behavior, then reconstruct mode selection, driver access, shielding, fade scheduling, palette restoration, and teardown using Tasks 6–8.
- [ ] Run `make -C tests screen` for both CPUs. Keep deterministic fixture results separate from hardware/Window Server results; document any unavailable mode or palette capability.
- [ ] Commit: `Interceptor: reconstruct screen modes shielding and fades`.

## Task 10: Reconstruct direct bitmap state and flushing

**Files:** Create `NSDirectBitmap.m`, `tests/direct_bitmap.m`.
**Interfaces:** Published direct bitmap API and obsolete categories; consume shape,
client/rectangle, framebuffer, and palette implementations from Tasks 4–8.

- [ ] Capture buffered/direct paths, obscured/exposed windows, depth mismatch, clipping, cross-screen moves, try-lock failure, geometry change while locked, delegate reentrancy, and partial/full flush. Assert dirty regions, copy results, callback order, and balanced cursor/lock operations.
- [ ] Demonstrate failures; reconstruct the state transitions before optimizing pixel-copy paths. Use the copy and shape contracts already verified; do not infer desired behavior from method names.
- [ ] Run `make -C tests direct-bitmap` for each CPU; re-run affected framebuffer/shape tests only when shared code changed. Review lifecycle paths jointly with client/rectangle implementation.
- [ ] Commit: `Interceptor: reconstruct direct bitmap transitions and flushing`.

## Task 11: Close ABI, build, and function parity gaps

**Files:** Finalize project/build lists, both profiles, architecture ledgers and
source maps, and `reconstruction/function-worklist.md`.
**Interfaces:** Complete thin dylibs and combined framework, all recorded exports,
class/category metadata, and all owned code mapped to implementation/evidence.

- [ ] Build each architecture into separate roots with the commands resolved in Task 3; build/stage a combined framework with `RC_ARCHS='ppc i386'`. Confirm both slices, version-A bundle structure, public headers, install name, dependencies, and unstripped analysis artifacts. Test `install` only with an external `DSTROOT`.
- [ ] Add `rebuilt` to each profile using `${BINRECON_REBUILT}`. Set it to the corresponding thin rebuilt image; never compare a fat image or the wrong CPU. Run `validate`, `analyze`, and `function --list` for each profile.
- [ ] Run `source-map --reference-analysis <published-analysis> --binary <thin-reference> --source-dir src/Kits/Interceptor --repo-root . --output <architecture-source-map> --objc-methods`. Do not use `--scope-to-objc`, which would drop C routines from scope.
- [ ] Review every owned function and data contract. Use existing ledger states only with supporting evidence. Normalized-function mismatches require investigation; compiler effects/release differences need explicit reasons, never a blanket ignore. Export/string checks supplement behavioral review and do not replace it.
- [ ] Run all implemented target test groups and ABI checks for each CPU. Require zero unknown owned entries, zero stubs, and no unexplained ABI or behavioral discrepancies. Unavailable execution remains blocked, not passed.
- [ ] Commit: `Interceptor: complete dual-architecture build and parity evidence` only when that statement is supported; otherwise commit the precise partial milestone.

## Task 12: Run disposable-guest integration and report acceptance

**Files:** Create `tests/integration.m`; finalize `reconstruction/validation.md`
and exact reproduction commands in `build-environment.md`.
**Interfaces:** Standalone test application loading the selected staged framework;
machine-readable outcomes identify CPU, guest/OS, artifact hashes, and case IDs.

- [ ] Exercise framework loading, window-backed bitmap drawing, move/resize/occlusion, buffered/direct switching, cursor handling, mapping/lock failure, and teardown. Include display-mode/palette/fade restoration when the guest exposes those capabilities.
- [ ] Run reference and rebuilt applications in separate processes against the same disposable guest configuration per CPU. Capture observation traces and compare supported common behavior; apply only documented release-specific expectations.
- [ ] Exercise server-death recovery in a disposable session, verify cleanup and notifications, and discard the test overlay afterward. Never interrupt another session's guest.
- [ ] Publish a per-CPU matrix for build, ABI, static/function parity, pure tests, IPC fixture tests, and real graphics integration. Every skipped case names the missing prerequisite and exact command needed to resume it. Missing runtime evidence prevents full validation claims.
- [ ] Review the complete change against the approved spec, run `git diff --check`, and commit reviewed evidence with `Interceptor: record framework integration results`.

## Handoff and self-review

Execution order is Tasks 1–3, then 4–10 in dependency order, then 11–12. A discovered
dependency blocker does not authorize expanding the scope into another framework.
Continue independent evidence/reconstruction work and report the concrete blocker.

Self-review: all spec components map to Tasks 4–10; tooling and build prerequisites
map to 1–3; both-architecture acceptance maps to 11–12. All five review-focus
conditions have explicit owning tests. Exact private signatures, wire values,
and runtime expectations are evidence-recovery deliverables, not invented facts.
No product source or tooling was modified while writing this plan.

Recommended execution is native in-session implementation because IPC, ownership,
and graphics state require shared evidence across tightly coupled tasks. The
alternative is subagent-driven execution with a fresh implementation/review cycle
per task. Obtain the user's plan review and execution choice before implementation.
