# Foundation PPC Fast Java Bundle Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Reconstruct the PPC-only `__NSFastJavaBundleSetup` path and its `_usesFastJavaBundleSetup` dispatch in `NSJavaSetup.m`.

**Architecture:** Add the private bundle-path helper and fast setup routine beside the existing Java bundle setup implementation. Guard the new bodies and dispatch with the PPC target macros, preserve the current non-fast path, and record the PPC export without adding it to i386 metadata.

**Tech Stack:** Objective-C, Foundation runtime APIs, MOSXS PPC IDA database, reconstruction JSON manifests.

**Spec:** `docs/superpowers/specs/2026-10-06-foundation-fast-java-bundle-setup-design.md`

## Global Constraints

- Implement only the behavior confirmed in the PPC IDA call graph.
- Preserve the existing non-fast `NSJavaBundleSetup` path and DR2 i386 behavior.
- Keep `NSJavaSetupVirtualMachine` outside this slice.
- Do not add or run tests or builds; use IDA comparison and static source/metadata checks.

## Review Focus

- When VM creation is unnecessary because `_NSJavaVM` exists and the settings do not request an owned VM, return the existing VM without posting setup notifications.
- When VM bundle lookup fails, return nil at the same point relative to setup notifications and path construction as the reference.
- Preserve ordering of VM class path, user paths, framework paths, and bundle paths.
- Preserve the target's asymmetry: the fast routine registers library paths from the setup dictionary once, while the non-fast routine does so per Java-providing bundle.
- Preserve bundle loaded-state updates and `load` message order before requested-class loading and the final setup notification.

---

### Task 1: Implement and route the fast setup path

**Files:**
- Modify: `src/Kits/Foundation/NSJavaSetup.m`

**Interfaces:**
- Consumes: existing `NSJavaDefinitiveSetupDictionary`, `_NSJavaAbsolutePath`, `NSJavaProvidesClasses`, `NSJavaClassLoaderForPath`, and `NSBundle` setup helpers.
- Produces: PPC-only `id _NSFastJavaBundleSetup(NSBundle *bundle, NSDictionary *settings)` and private `NSArray *_NSJavaPathCompsForBundle(NSBundle *bundle, NSDictionary *settings, BOOL absolutePath)`; PPC `NSJavaBundleSetup` dispatches to the fast function only when `_usesFastJavaBundleSetup > 0`.

- [x] **Step 1: Add the PPC path-components helper** using the target's settings fallback and normalization, selecting absolute `NSJavaPath` components or typed `NSJavaUserPath` components from the Boolean argument.
- [x] **Step 2: Add `_NSFastJavaBundleSetup`** in IDA operation order: VM reuse check, JavaVM bundle/default class path, setup dictionary and classpath assembly, framework/bundle path aggregation, notifications, VM creation, library search-path registration, system class-loader creation, bundle loaded-state updates and `load`, requested class loading, and final notification.
- [x] **Step 3: Route `NSJavaBundleSetup` on PPC** before the existing non-fast path, passing the original bundle and settings; preserve the non-fast body unchanged and keep i386 routing unchanged.
- [x] **Step 4: Compare the helper, fast setup, and dispatch against IDA** at `0x4257ea94`, `0x4257dd78`, and `0x4257bb14`, checking early returns, path ordering, notification order, and message signatures.
- [x] **Step 5: Run `git diff --check -- src/Kits/Foundation/NSJavaSetup.m`** (expected: exit 0, no output).

### Task 2: Record the PPC-only export and divergence

**Files:**
- Modify: `src/Kits/Foundation/reconstruction/abi-ppc/NSJavaSetup.json`
- Modify: `src/Kits/Foundation/reconstruction/symbols.json`
- Modify: `src/Kits/Foundation/reconstruction/ownership.json`
- Modify: `src/Kits/Foundation/reconstruction/divergences.md`

**Interfaces:**
- Consumes: PPC-only `_NSFastJavaBundleSetup` definition from Task 1.
- Produces: PPC ABI text symbol `__NSFastJavaBundleSetup`, shared source-symbol assignment to `NSJavaSetup.m`, and an ownership record mapping the export to that module.

- [x] **Step 1: Add the PPC ABI, symbol, and ownership records** for `__NSFastJavaBundleSetup`; do not add it to the shared i386 ABI.
- [x] **Step 2: Document the PPC flag-controlled path and i386 absence** in `reconstruction/divergences.md`, including that `NSJavaSetupVirtualMachine` remains outside the slice.
- [x] **Step 3: Parse the changed JSON manifests** and confirm the export is defined once, assigned to `NSJavaSetup.m`, and absent from the i386 ABI.
- [x] **Step 4: Run `git diff --check` for the slice** (expected: exit 0, no output).

## Self-review

- Spec coverage: Task 1 covers the private helper, fast routine, PPC dispatch, and all IDA-confirmed path/control-flow details. Task 2 covers the ABI, symbol ownership, and architecture divergence.
- Step scan: each implementation step targets one behavior or verification result; the plan leaves exact API calls and ordering to the attached IDA spec.
- Type consistency: the C export uses source identifier `_NSFastJavaBundleSetup` and PPC linker/ABI name `__NSFastJavaBundleSetup`; `_NSJavaPathCompsForBundle` remains private.
- Review focus: VM reuse, early VM-bundle failure, class path ordering, library path asymmetry, and loaded-state/class-load ordering are explicit.
- Proportion: two tasks follow the source and metadata boundaries; no test/build work is added because the spec excludes it.

### PPC default-flag correction (2026-10-07)

Live IDA shows `__usesFastJavaBundleSetup` at `0x426260c0` contains
`0x00000001`. The PPC source global now has the matching initializer, so the
default `NSJavaBundleSetup` route enters `__NSFastJavaBundleSetup`; the i386
build remains unaffected by the existing target guard. ABI, symbol, and
ownership records are unchanged. Static source and whitespace checks only;
no tests or builds were run.
