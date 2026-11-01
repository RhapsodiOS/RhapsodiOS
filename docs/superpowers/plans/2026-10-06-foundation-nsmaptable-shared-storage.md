# Foundation `NSMapTable` Shared Storage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `NSMapTable.m`'s duplicate bucket engine with the shared dictionary path used by PPC and i386 Foundation.

**Architecture:** Preserve the 40-byte wrapper and callback records, but store an `NSSimpleDictionary *` and route lookup, mutation, reset, free, and enumeration through `NSSimpleHashing.m`. Keep callback invocation, ownership order, public symbols, and traversal order from both IDA targets.

**Tech Stack:** Objective-C, `NSSimpleHashing.m`, PPC and i386 Foundation IDA databases, ABI/source ownership manifests.

**Spec:** `docs/superpowers/specs/2026-10-06-foundation-nsmaptable-storage-design.md`

## Global Constraints

- Keep the public `NSMapTable` callback structs and exported function signatures unchanged.
- Keep the wrapper layout as one `NSSimpleDictionary *` followed by the existing key and value callback records.
- Reuse current `NSSimpleHashing.m` helpers; do not move or duplicate their algorithms.
- Match PPC and i386 behavior where the two IDA bodies agree; preserve any directly confirmed target difference.
- Do not add or run tests or builds. Verify the wrapper and callback order against both IDA databases, validate any touched JSON only if metadata must change, and run `git diff --check` for the slice.

## Review Focus

- `NSMapInsert`, `NSMapInsertKnownAbsent`, `NSMapInsertIfAbsent`, and `NSMapRemove` must retain their `notAKeyMarker` checks; `NSMapMember` and `NSMapGet` must not gain marker checks.
- Replacing an existing key must preserve the stored key and release exactly the old value after the new value retain.
- `NSMapInsertKnownAbsent` must raise on a duplicate after non-replacing lookup; `NSMapInsertIfAbsent` must return the original stored key without retaining the attempted pair.
- Deleting from compact and open-addressed table levels must return the original key/value, then release key before value.
- Reset and free must only run entry release callbacks when either key or value release callback exists, and must preserve reverse bucket order.

These conditions are verified by method-by-method IDA comparison; runtime tests and builds are excluded by the spec.

---

### Task 1: Replace table storage and core operations

**Files:**
- Modify: `src/Kits/Foundation/NSMapTable.m`

**Interfaces:**
- Consumes: `NSCreateSimpleDictionary`, `NSFreeSimpleDictionary`, `NSSimpleDictionaryCount`, `NSSimpleDictionaryLookup`, `NSSimpleDictionaryInsert`, `NSSimpleDictionaryDelete`, and `NSResetSimpleDictionary` from `NSSimpleHashing.m`.
- Produces: the target 40-byte `NSMapTable` wrapper and storage-backed create/free/reset/count, lookup, insertion, and removal APIs.

- [x] Replace `NSSimpleMapDictionary`, local bucket capacity/search/resize code, and local map insert machinery with an opaque `NSSimpleDictionary *`, the target bucket view for key/value reads, and narrow private declarations for the shared helper signatures. Keep the wrapper fields at offsets 0, 4, and 28.
- [x] Implement `NSCreateMapTableWithZone`, `NSCreateMapTable`, `NSFreeMapTable`, and `NSResetMapTable` using the helper calls and the target release callback. Preserve wrapper and nested dictionary allocation zones, reset callback condition, reverse release order, then free order.
- [x] Implement `NSMapMember`, `NSMapGet`, `NSMapInsert`, `NSMapInsertKnownAbsent`, `NSMapInsertIfAbsent`, and `NSMapRemove` over helper lookup/insert/delete calls. Preserve marker checks, computed-hash inputs, wrapper comparison context, helper return values, and callback ownership order.
- [x] Compare wrapper layout and core operations against PPC `NSCreateMapTableWithZone` `0x425159b0`, `NSFreeMapTable` `0x4251a7f0`, `NSMapMember` `0x42503438`, `NSMapGet` `0x42501664`, `NSMapInsert` `0x425016f4`, `NSMapInsertKnownAbsent` `0x425094bc`, `NSMapInsertIfAbsent` `0x42525930`, `NSMapRemove` `0x4250aa94`, `NSResetMapTable` `0x4256d78c`; and i386 counterparts `0x4251f898`, `0x42524980`, `0x42504eac`, `0x42503468`, `0x4250489c`, `0x4251301c`, `0x425293cc`, `0x4250dd88`, `0x42546198`. Run `git diff --check -- src/Kits/Foundation/NSMapTable.m` (expected: exit 0, no output).

### Task 2: Route enumeration and collection operations through shared buckets

**Files:**
- Modify: `src/Kits/Foundation/NSMapTable.m`

**Interfaces:**
- Consumes: Task 1's `NSSimpleDictionary *` wrapper and the shared helper declarations.
- Produces: target traversal for map enumeration, key/value arrays, comparison, copying, and string formatting.

- [x] Implement `NSEnumerateMapTable`, `NSNextMapEnumeratorPair`, and `NSCountMapTable` using `NSSimpleDictionaryNumBuckets`, `NSSimpleDictionaryGetBucket`, and `NSSimpleDictionaryCount`; preserve initial cursor, reverse traversal, and empty-bucket cursor updates.
- [x] Implement `NSAllMapTableKeys` and `NSAllMapTableValues` using shared buckets in reverse order, the 128-pointer stack buffer, zone-allocated overflow storage, `NSArray` construction, and the target free order.
- [x] Implement `NSCompareMapTables` and `NSCopyMapTableWithZone` using target-table hash callbacks, shared lookup/insert helpers, and the target retain and iteration order.
- [x] Implement `NSStringFromMapTable` with shared count/bucket traversal and the existing key/value `describe` callbacks and target formatting.
- [x] Compare enumeration, arrays, comparison, copying, and description against PPC `NSEnumerateMapTable` `0x425220b8`, `NSNextMapEnumeratorPair` `0x4250d364`, `NSCountMapTable` `0x4255001c`, `NSAllMapTableKeys` `0x4256cf68`, `NSAllMapTableValues` `0x4256d080`, `NSCompareMapTables` `0x4256d280`, `NSCopyMapTableWithZone` `0x4256d474`, `NSStringFromMapTable` `0x4256de94`; and i386 counterparts `0x42525e48`, `0x425034c0`, `0x425251f0`, `0x42530314`, `0x42562ccc`, `0x42562edc`, `0x42563054`, `0x425637bc`. Run `git diff --check -- src/Kits/Foundation/NSMapTable.m` (expected: exit 0, no output).

### Task 3: Reconcile the remaining divergence and audit the complete slice

**Files:**
- Modify: `src/Kits/Foundation/reconstruction/divergences.md`
- Verify: `src/Kits/Foundation/reconstruction/abi/NSMapTable.json`
- Verify: `src/Kits/Foundation/reconstruction/symbols.json`
- Verify: `src/Kits/Foundation/reconstruction/ownership.json`

**Interfaces:**
- Consumes: Tasks 1 and 2's shared-storage implementation.
- Produces: an accurate note that `NSZone.m` retains its private compact table for low refcounts but uses `NSMapTable` for overflow counts and the zombie-class cache; unchanged ABI/source ownership records.

- [x] Update the `NSZone.m` divergence note: the low-count refcount table remains private, while overflow counts and the zombie-class cache use the reconstructed `NSMapTable`; leave the compact low-count path in place in this slice.
- [x] Parse the existing `NSMapTable.json`, `symbols.json`, and `ownership.json`; verify all existing NSMapTable exports/constants still have one owner and their ABI entries remain unchanged.
- [x] Confirm `NSMapTable.m` no longer contains a private capacity table, bucket probe/resize implementation, or direct count/state manipulation; confirm `NSSimpleHashing.m` remains unchanged.
- [x] Compare the complete wrapper and helper call closure against both IDA targets, then run `git diff --check` for `src/Kits/Foundation/NSMapTable.m` and `src/Kits/Foundation/reconstruction/divergences.md` (expected: exit 0, no output). Do not run tests or builds.

---

## Self-review

- **Spec coverage:** Task 1 covers wrapper layout, helper setup, allocation/cleanup, callback ownership, and all core lookup/mutation APIs. Task 2 covers enum state, key/value arrays, comparison, copying, and descriptions. Task 3 covers the remaining cross-module divergence and ABI/source ownership invariants.
- **Step granularity:** Each implementation step changes one method family or performs a specific IDA/static check. The plan contains no runtime test steps because the approved spec excludes them.
- **Type consistency:** The wrapper keeps `NSSimpleDictionary *`, key callbacks, and value callbacks in the agreed 0/4/28 layout. Shared helper prototypes must match `NSSimpleHashing.m`, including pointer-to-pointer arguments for insert/delete where resize or result outputs require them.
- **Review focus:** The five callback, marker, duplicate, deletion, and release-order conditions are checked in Tasks 1 and 2 against both binaries.
- **Proportion:** Three tasks follow storage/core mutation, traversal/derived operations, and metadata/divergence reconciliation. The public ABI, callback constants, and helper module stay outside structural changes.

## Final review

- Independent scoped review found no confirmed target mismatches.
- **Ruling:** `NSCompareMapTables` compares counts and key membership, not mapped values — both PPC `0x4256d280` and i386 `0x42562edc` pseudocode look up each key and never inspect its value, so the reconstruction follows the reference — cost if wrong: maps with the same keys and different values compare equal.

## Follow-up callback-context correction (2026-10-07)

A paired recheck of `NSCopyMapTableWithZone` found that both IDA targets
invoke the key and value retain callbacks with the new copy as the callback
context (i386 `0x42563054`, PPC `0x4256d474`). The source passed the original
table as that context. `NSMapTable.m` was updated to pass `copy` as the
callback context. A later call-source recheck below found that IDA loads each
callback pointer from the original table while checking the copied table's
callback slot; the callback context remains `copy`. That newer finding
supersedes this entry's description of the callback pointer source. `git diff
--check` passed; no tests or builds were run.

## Reset callback condition recheck (2026-10-08)

Rechecked `NSResetMapTable` and `NSFreeMapTable` in both targets. i386
`NSResetMapTable` (`0x42546198`) and PPC (`0x4256d78c`) unconditionally pass
`releaseKeyValue` to `NSResetSimpleDictionary`; the source does the same, and
the callback itself checks the key/value release functions before invoking
them. `NSFreeMapTable` guards the reset call on a nonempty dictionary and at
least one release callback in both targets (i386 `0x42524980`, PPC
`0x4251a7f0`), matching the source. The apparent reset-condition concern is
therefore not a source mismatch. No code change, tests, or builds were needed.
