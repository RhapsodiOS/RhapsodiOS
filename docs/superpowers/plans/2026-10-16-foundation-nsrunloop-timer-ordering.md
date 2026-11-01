# NSRunLoop Timer Ordering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Match the i386 and PPC timer-vector publication and count-update order in `NSRunLoop.m`.

**Architecture:** Keep the existing insertion helper and its two call sites. Publish a new vector before normal insertion, then insert the timer pointer and mode pointer as two target-ordered vector phases. Each phase updates count before its retain callback and publishes the vector after storing the retained object; mode combination stays between the timer and mode phases. Preserve all unrelated timer ordering and ownership behavior.

**Tech Stack:** Objective-C, paired i386/PPC IDA databases, JSON source maps.

**Spec:** `docs/superpowers/specs/2026-10-16-foundation-nsrunloop-timer-ordering.md`

## Global Constraints

- Match both i386 and PPC IDA behavior.
- Change only the timer-vector state order described in the spec.
- Do not add or run tests or builds; use static paired IDA/source-map review.

## Review Focus

- Reentrant `retain` observes `_timers` pointing at the newly allocated vector during normal addition.
- Timer and mode retain callbacks each observe the corresponding incremented element count.
- A vector grown during either insertion phase is published after that slot's retain and store.
- `combineModes` runs after the timer slot is retained, stored, and published, before the mode slot is inserted.
- Both normal addition and post-fire reinsertion continue to use the shared helper.
- Duplicate timer insertion and mode-combination paths remain unchanged.

---

### Task 1: Match paired timer-vector ordering

**Files:**
- Modify: `src/Kits/Foundation/NSRunLoop.m:226-278,1119-1142`
- Modify: `src/Kits/Foundation/reconstruction/run-loop/source-map.json`
- Modify: `src/Kits/Foundation/reconstruction/run-loop-i386/source-map.json`
- Modify: `src/Kits/Foundation/reconstruction/divergences.md`

**Interfaces:**
- Consumes: `NSRunLoopInsertTimer(NSRunLoopPortVector **timerVector, NSTimer *timer, id modes, BOOL combineModes)` and its two existing call sites.
- Produces: the same helper interface with target-matching publication and count order.

- [x] In `addTimer:forMode:`, publish a newly created vector to `_timers` before calling `NSRunLoopInsertTimer`, and pass the pointer to `_timers` through the existing helper interface.
- [x] In `NSRunLoopInsertTimer`, preserve duplicate lookup and insertion-point selection. For new entries, reproduce the paired timer-slot then mode-slot capacity, count, shift, retain, store, and pointer-publication order; run `combineModes` between the two slot phases when requested.
- [x] Refresh only source-line anchors shifted by the edit; confirm both maps still identify all four target functions and resolve the source anchors. Add the paired behavior to `divergences.md`.
- [x] Run `git diff --check` on the changed text and inspect the focused source/map diffs. Do not run tests or builds.
