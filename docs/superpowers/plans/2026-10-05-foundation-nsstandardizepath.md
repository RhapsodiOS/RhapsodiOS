# Foundation `_NSStandardizePath` Implementation Plan

> **For agentic workers:** Use this plan task-by-task. Steps use checkbox syntax.

**Goal:** Reconstruct the target's `_NSStandardizePath` export and route its four confirmed callers through the in-place UTF-16 normalizer.

**Architecture:** Implement the C helper beside the existing path-buffer helpers in `NSPathUtilities.m`. Replace the current `NSPathStoreStandardize` and generic `NSString` object-array/UTF-8 standardization paths with the four IDA-confirmed wrapper flows, returning `NSPathStore2` instances as the target does.

**Tech Stack:** Objective-C, Foundation path classes, binrecon ABI and source-symbol metadata.

**Spec:** `docs/superpowers/specs/2026-10-05-foundation-nsstandardizepath-design.md`

## Global Constraints

- Match the DR2 i386 Foundation reference identified by SHA-256 `1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6`.
- Keep the change limited to `NSPathUtilities.m` and its reconstruction ABI, symbol, and ownership records.
- Preserve the target's 1,024-unit temporary resolution capacity and caller capacity behavior. Allocate caller workspaces for the full input length so the target's truncated-stack-buffer hazard is not reproduced.
- Do not add or run tests or builds in this session.

## Review Focus

- Relative paths retain leading `..` components; only `/` and `~` paths enter the target's dot-dot symlink-resolution path.
- A complete `..` component is required; names such as `..hidden` do not trigger resolution.
- If the resolved temporary path exceeds caller capacity, preserve the initial slash-transmutation/trailing-slash result and return its accumulated flag.
- UNC server/share components are not crossed by dot-dot reduction; the UNC branch in `_pathHasDotDot` remains unreachable under the target's absolute-path predicate.
- `/private/` is removed only when the suffix path exists; empty or missing suffixes retain the prefix.

---

### Task 1: Reconstruct and wire `_NSStandardizePath`

**Files:**
- Modify: `src/Kits/Foundation/NSPathUtilities.m`
- Modify: `src/Kits/Foundation/reconstruction/abi/NSPathUtilities.json`
- Modify: `src/Kits/Foundation/reconstruction/symbols.json`
- Modify: `src/Kits/Foundation/reconstruction/ownership.json`
- Update evidence: `docs/superpowers/plans/notes/2026-10-04-foundation-c-symbol-coverage.md`

**Interfaces:**
- Consumes: `NSPathStoreTransmuteSlashes`, `NSPathStoreStripTrailingSlashes`, `_NSResolveSymlinksInPath`, and the existing Foundation file-existence path.
- Produces: `int _NSStandardizePath(unichar *characters, unsigned *length, int capacity)`.

- [x] **Step 1: Recheck the target call sites and current metadata.** Confirm the four saved addresses and each wrapper's stack-buffer capacity, tilde expansion, symlink-resolution order, and `NSPathStore2` return factory. The helper's three arguments are confirmed by raw i386 disassembly at `[ebp+8]`, `[ebp+0xc]`, and `[ebp+0x10]`. Confirm the current ABI and ownership maps do not already claim the export.
- [x] **Step 2: Implement the helper in `NSPathUtilities.m`.** Follow the spec's ordered stages: initial slash transmutation/trailing cleanup; eligible temporary symlink resolution and capacity check; terminal `/.` trim; non-UNC leading `./` removal; `/./` collapse; root-bounded `/../` reduction; final slash cleanup; conditional `/private/` removal; and target return behavior.
- [x] **Step 3: Route all four callers through the helper.** Preserve tilde expansion in both standardizing methods; call `_NSResolveSymlinksInPath` before standardization in both resolving methods; have all four return `NSPathStore2` through `pathStoreWithCharacters:length:`. Generic `NSString` wrappers retain the target's 1,024-unit input clamp. `NSPathStore2` wrappers copy the complete input into a dynamically sized workspace, while keeping the helpers' 1,024-unit output/resolution capacity; this follows the saved NSPathStore2 analysis, which explicitly says not to reproduce the target's truncated-buffer out-of-bounds hazard.
- [x] **Step 4: Register the export.** Add Mach-O symbol `__NSStandardizePath` (C identifier `_NSStandardizePath`) to `NSPathUtilities.json`, `symbols.json`, and `ownership.json`, with `NSPathUtilities.m` as the owner.
- [x] **Step 5: Run static verification only.** Parse the edited JSON; run `git diff --check`; run the exact-profile `binrecon symbol-audit` and `selector_check.py`. Confirm `_NSStandardizePath` is claimed and selector coverage remains at zero missing/renamed/duplicate selectors. Do not run tests or builds.
- [x] **Step 6: Record evidence and limits.** Update the coverage note with the implementation and static verification results; state that runtime behavior remains unverified in this session.
