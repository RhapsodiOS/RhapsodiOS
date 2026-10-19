# NSPortCoder Typed-Value Walker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Make `NSConcretePortCoder` typed-value encode/decode follow the i386 and PPC `_NSWalkData` paths.

**Architecture:** Add a mode-aware adapter to `_NSWalkData` in `NSSerialization.m`, using the existing stream context layout and its flag byte to distinguish port callbacks from generic archive callbacks. Replace the typed-value switches in `NSPortCoder.m` with direct walker calls.

**Tech Stack:** Objective-C, Foundation reconstruction source, paired i386/PPC IDA databases.

**Spec:** `docs/superpowers/specs/2026-10-08-foundation-portcoder-walkdata-stream-design.md`

## Global Constraints

- Preserve both i386 and PPC ABI layouts and target-specific byte ordering.
- Preserve generic `NSData` serialization behavior when callbackMode is zero.
- Do not change public headers, ABI records, ownership records, or exported symbols.
- Static IDA/source checks only; do not add/run tests or builds.

## Review Focus

- Stream callbacks receive the stream context, while generic callbacks receive the backing `NSMutableData`.
- The stream callback table uses distinct signatures for bytes, compact integers, and C strings.
- PPC short-value byte order differs from i386.
- Cursor offsets in stream mode are relative to `start`, not the first `data` field.
- Object qualifiers remain local to the current recursive walk.

### Task 1: Add stream-mode dispatch to `_NSWalkData`

**Files:**
- Modify: `src/Kits/Foundation/NSSerialization.m`

**Interface:**
- Keep `_NSWalkData(int operation, BOOL walkPointers, void *context, void *value, const char *type)` unchanged.
- Treat `callbackMode != 0` as port-stream mode; use context itself as stream receiver and `reserved` as stream start.

- [x] Add typed helpers for the stream byte, fast-integer, and C-string callback slots.
- [x] Use stream-aware writer dispatch for primitives, class/selector/C-string values, pointer markers, and bitfields.
- [x] Use `start` for stream cursor offsets while leaving generic storage offsets unchanged.
- [x] Preserve generic callbackMode-zero logic and verify it remains unchanged by source review.

### Task 2: Route typed port-coder methods through the walker

**Files:**
- Modify: `src/Kits/Foundation/NSPortCoder.m`

**Interface:**
- Add a matching extern declaration for `_NSWalkData`.
- Call operation 1 for encode and operation 0 for decode with `walkPointers=YES`, `&streamData.stream`, the value address, and the original type.

- [x] Replace the local type switches in both typed-value methods with the walker calls.
- [x] Remove any helpers made unused by this change only if no remaining callsites use them.

### Task 3: Verify the paired source path

**Files:**
- Review: `src/Kits/Foundation/NSSerialization.m`
- Review: `src/Kits/Foundation/NSPortCoder.m`
- Update: `docs/superpowers/plans/notes/2026-10-08-foundation-current-gap-audit.md`

- [x] Compare the final stream calls with IDA i386 (`0x42513800`, `0x42519760`) and PPC (`0x4250d2d0`, `0x425112e8`).
- [x] Confirm the three stream callback call shapes, cursor base, and architecture-specific `s`/`S` order from source and IDA.
- [x] Run `git diff --check`; do not run tests or builds.
- [x] Record implementation and verification evidence in the audit note.
