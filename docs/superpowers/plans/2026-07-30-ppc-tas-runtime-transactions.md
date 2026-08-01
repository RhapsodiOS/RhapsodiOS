# PPC TAS Runtime Transactions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make TAS task-context state, DMA lifecycle, controls, and detect failures safe under concurrency without blocking while holding the state lock.

**Architecture:** Add one operation lock that serializes task-context runtime transactions and retain short state-lock critical sections for `TASAudioState`. Raw ISRs remain isolated on the interrupt lock. Hardware callbacks execute under the operation lock when needed for transaction serialization, but never under the state lock.

**Tech Stack:** C89 host runtime tests, Objective-C DriverKit bindings, TAS core/runtime APIs.

---

### Task 1: Transaction and DMA lifecycle tests

**Files:**
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/tests/tas_runtime_test.c`
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/TASRuntime.h`
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/TASRuntime.c`

- [x] Add operation-lock callbacks to the mock and tests asserting callbacks run outside `stateLock`.
- [x] Add failing tests for every start-gate constituent, failed-start harmless stop, isolated deferred DMA cleanup, restart blocking, reset recovery, and Ready power recovery.
- [x] Run the strict runtime test and confirm failures describe the missing gates/cleanup/serialization.
- [x] Add operation serialization to Reset, Power, Controls, Start, Stop, and Deferred service; keep lock order `operation -> state`, with interrupt locking independent.
- [x] Implement per-direction fault cleanup and explicit recovery, then rerun the strict runtime test.

### Task 2: Detect and control truth tests

**Files:**
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/tests/tas_runtime_test.c`
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/TASRuntime.h`
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/TASRuntime.c`

- [x] Change test mocks to wished-for status-returning `sampleDetects(out)` and `failMuteOutputs()` callbacks.
- [x] Add failing tests proving detect read failure propagates and failed controls preserve desired state while invalidating hardware/route truth and recording mute certainty.
- [x] Run the strict runtime test and confirm the new tests fail for the old callback contracts.
- [x] Implement the callback contracts and failure-state updates without holding `stateLock` across hardware callbacks.
- [x] Rerun the strict runtime test and confirm green.

### Task 3: DriverKit controls and initialization ordering

**Files:**
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/PPCTASAudio.h`
- Modify: `src/drivers-ppc/sound/drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj/PPCTASAudio.m`
- Test: `src/drivers-ppc/sound/drvPPCTASAudio/tests/tas_runtime_test.c`

- [x] Add source/static assertions for attenuation `-84..0`, gain `0..32768`, conversion helper use, unsupported-source rejection, operation-lock binding, and DMA-op initialization before reset/IRQ acquisition.
- [x] Run the strict runtime test and confirm the source assertions fail against the old bindings.
- [x] Add the operation lock, status-returning detect/fail-mute adapters, converted IOAudio callbacks and matching advertised limits, recognized-source-only handling, and pre-reset DMA-op initialization.
- [x] Run both strict host binaries, `git diff --check`, and focused source scans.
- [x] Commit all plan, tests, runtime, and binding changes as one focused commit.
