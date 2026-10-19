# Foundation NSFileHandle Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct the DR2 i386 `NSFileHandle`, concrete descriptor handles, null handles, pipes, and asynchronous notifications from the IDA reference.

**Architecture:** Keep `NSFileHandle` abstract and put runtime behavior in private `NSConcreteFileHandle`, `NSNullFileHandle`, and `NSConcretePipe` classes in the existing implementation file. Record reference class layouts and selector encodings in the module ABI document.

**Tech Stack:** Objective-C, existing Foundation APIs and POSIX descriptor calls, IDA pseudocode, and the repository's binrecon ABI extractor.

**Spec:** `docs/superpowers/specs/2026-10-01-foundation-nsfilehandle-design.md`.

## Global Constraints

- Modify `src/Kits/Foundation/NSFileHandle.m` for runtime behavior and add `src/Kits/Foundation/reconstruction/abi/NSFileHandle.json`.
- Preserve the i386 instance sizes, ivar offsets, selectors, encodings, ownership, and constants documented in the spec.
- Do not change public headers or unrelated Foundation modules.
- Do not add or run tests or builds; use IDA comparison, ABI metadata inspection, and static source/whitespace checks.

## Review Focus

- Abstract base methods must keep raising concrete-implementation exceptions while private concrete classes implement the operations.
- Standard handles and null handles must preserve the reference's descriptor ownership and flags.
- Read and write paths must preserve EOF, partial read, zero-length, and syscall error behavior.
- Pipe construction must close any descriptor already acquired if wrapping either endpoint fails.
- Async operations must reject conflicting activities and deliver the matching notification while releasing hidden state and removing registered run-loop modes.

### Task 1: Record the reference ABI and define private classes

**Files:**
- Modify: `src/Kits/Foundation/NSFileHandle.m`
- Create: `src/Kits/Foundation/reconstruction/abi/NSFileHandle.json`

- [x] Extract the reference ABI record and verify the five class sizes, ivar offsets, and selector encodings against the design spec.
- [x] Declare private concrete classes with the exact ABI layouts and selectors; keep the public base methods abstract.

### Task 2: Implement descriptor and null-handle behavior

**Files:**
- Modify: `src/Kits/Foundation/NSFileHandle.m`

- [x] Implement path and descriptor initializers, descriptor access, read/write, offset, seek, truncate, synchronize, and close behavior from their IDA bodies.
- [x] Implement null-device operations and cached standard input/output/error handles with target ownership flags.
- [x] Compare each implementation path and error context with the corresponding IDA pseudocode.

### Task 3: Implement pipes and asynchronous notifications

**Files:**
- Modify: `src/Kits/Foundation/NSFileHandle.m`

- [x] Implement `NSPipe` allocation, descriptor creation, endpoint wrapping, accessors, and cleanup on partial failure.
- [x] Implement async read, read-to-EOF, accepted connection, and data-available operations using the target port/run-loop delegate flow.
- [x] Verify notification names, user-info keys, activity conflicts, worker cleanup, and run-loop mode removal against IDA.

### Task 4: Static integration review

**Files:**
- Review: `src/Kits/Foundation/NSFileHandle.m`
- Review: `src/Kits/Foundation/reconstruction/abi/NSFileHandle.json`

- [x] Confirm every spec requirement maps to source and ABI evidence.
- [x] Run focused whitespace/source checks; do not run tests or a build.
