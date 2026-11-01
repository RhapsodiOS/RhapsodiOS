# Foundation `_NSAutoreleasedMallocMemory` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the process-global scratch chunk with the reference's per-thread dictionary cache on PPC and i386.

**Architecture:** Keep the shared implementation in `NSPrivate.m`; use `NSThread.threadDictionary` and an `NSValue` nonretained-object wrapper for cached chunks. Preserve the target's allocation and autorelease sequence, including the exact cache replacement comparison and conditional removal during deallocation.

**Tech Stack:** Objective-C, Foundation thread dictionaries and values, PPC/i386 Foundation IDA databases.

**Spec:** `docs/superpowers/specs/2026-10-06-foundation-autoreleased-malloc-design.md`

## Global Constraints

- Match both reference targets' behavior; do not add an architecture-specific substitute where the bodies agree.
- Keep the private class layout, method signatures, and public headers unchanged.
- Keep `NSThread` dictionary-release and autorelease-pool-drain order unchanged.
- Do not add or run tests or builds; verify against IDA and static source checks only.

## Review Focus

- Requests greater than 500 bytes allocate an exact-size autoreleased chunk without looking up or changing the cached entry.
- A cached chunk with exactly enough remaining capacity is reused.
- At the replacement boundary where `500 - capacity == remainingCapacity`, allocate a dedicated chunk and preserve the cached wrapper.
- Deallocation removes the dictionary entry only when its wrapped object is the deallocating chunk.
- Thread teardown preserves the reference order: release and clear the dictionary, then drain autorelease pools.

---

### Task 1: Replace the process-global cache with the thread dictionary

**Files:**
- Modify: `src/Kits/Foundation/NSPrivate.m`

**Interfaces:**
- Consumes: `_NSCurrentThread()`, `-[NSThread threadDictionary]`, `-[NSDictionary objectForKey:]`, `-[NSMutableDictionary setObject:forKey:]`, `+[NSValue valueWithNonretainedObject:]`, and `-[NSValue nonretainedObjectValue]`.
- Produces: PPC/i386-equivalent `+[_NSAutoreleasedMallocMemory mallocMemoryWithCapacity:]` cache lookup and replacement behavior.

- [x] Import the existing dictionary, thread, and value interfaces; remove `currentMallocMemoryChunk` and obtain `[_NSCurrentThread() threadDictionary]` for requests at or below 500 bytes.
- [x] Look up `NSAutoreleaseMalloc`, unwrap the nonretained value when present, and preserve the target's `capacity > remaining`, `500 - capacity > remaining` branch order.
- [x] Store a nonretained `NSValue` wrapper only when a newly allocated 500-byte chunk replaces the cached chunk; preserve the exact-size paths and autorelease order.
- [x] Compare all allocation branches and the equality boundary against PPC `0x42525c40` and i386 `0x4251ba24`; run `git diff --check -- src/Kits/Foundation/NSPrivate.m`.

### Task 2: Match conditional cache cleanup during deallocation

**Files:**
- Modify: `src/Kits/Foundation/NSPrivate.m`

**Interfaces:**
- Consumes: the `NSAutoreleaseMalloc` dictionary entry defined by Task 1.
- Produces: target-equivalent conditional key removal in `-[_NSAutoreleasedMallocMemory dealloc]`.

- [x] Resolve the current thread dictionary, unwrap the cached value, and remove the key only when the wrapped object is `self`.
- [x] Preserve byte-buffer freeing and superclass deallocation order; match the exact sequence against PPC `0x42531fb8` and i386 `0x425282b4`.
- [x] Confirm the existing `NSThread` teardown order matches PPC `0x42599728` and i386 `0x42583904`; do not change that lifecycle in this slice.
- [x] Re-read the class initializer and `-remainingCapacity` against both targets; make `-remainingCapacity` return the target's exact unsigned `500 - length`; remove any obsolete global-cache explanation and run `git diff --check -- src/Kits/Foundation/NSPrivate.m`.

## Self-review

- **Spec coverage:** Task 1 covers lookup, wrapper representation, allocation branches, and comparison boundary. Task 2 covers deallocation cleanup and verifies the coupled thread teardown order.
- **Step granularity:** Each step changes one behavior or performs its corresponding IDA/static check.
- **Type consistency:** The plan uses the existing Foundation `NSThread`, `NSDictionary`, and `NSValue` interfaces; no new declaration or ABI export is required.
- **Review focus:** All five edge conditions are pinned to the task that owns their code and checked directly against the target binaries, as runtime checks are excluded by the spec.
- **Proportion:** Two tasks follow the allocation and deallocation method boundaries in the reference.
