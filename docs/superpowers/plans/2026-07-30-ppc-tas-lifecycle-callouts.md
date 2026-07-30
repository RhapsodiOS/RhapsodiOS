# PPC TAS Lifecycle and Callouts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make TAS debounce/poll work genuinely asynchronous and make teardown safe while DMA or stale callouts exist.

**Architecture:** A singleton callout broker owns stable callback tokens and serializes access to the one driver instance; per-instance generation/deadline flags reject stale work. Runtime teardown disables IRQs and proves active/faulted DMA reset before releasing descriptors or mappings, intentionally preserving resources if hardware cleanup fails.

**Tech Stack:** C89 TAS host tests, Objective-C DriverKit callouts/messages, PPC DBDMA state machine.

---

### Task 1: Faulted DBDMA reset

**Files:** `PPCDBDMAAudio.c`, `tas_audio_test.c`, `PPCTASAudio.m`

- [x] Add failing tests for StopRing from Faulted and reset success/failure.
- [x] Run strict parser/core tests and confirm the Faulted stop precondition fails.
- [x] Permit StopRing from Running or Faulted, issue bounded clear/flush, retain Faulted on failure, and let the adapter reset after successful stop.
- [x] Rerun strict tests.

### Task 2: Runtime teardown and mute truth

**Files:** `TASRuntime.h`, `TASRuntime.c`, `tas_runtime_test.c`

- [x] Add failing tests for IRQ-first active unwind, active/faulted direction cleanup, stale latch clearing, cleanup-failure resource preservation, and DMA/start/stop mute truth.
- [x] Run strict runtime tests and confirm lifecycle assertions fail.
- [x] Make unwind status-returning and operation-serialized; disable IRQ stages, clean directions, release clocks, clear latches, then release resources only after cleanup succeeds.
- [x] Centralize DMA/start/stop failure invalidation and rerun strict runtime tests.

### Task 3: Asynchronous debounce and polling broker

**Files:** `PPCTASAudio.h`, `PPCTASAudio.m`, `tas_runtime_test.c`, `English.lproj/DriverHelp/README.txt`

- [x] Add failing static assertions for `ns_timeout`/`ns_untimeout`, `CALLOUT_PRI_THREAD`, zeroed `msg_header_t`, kernel-port message posting, no debounce `IODelay`, no direct `_interruptOccurred`, singleton-owner rejection, cancel-before-unwind/free, and 250ms Ready-only polling.
- [x] Run strict runtime tests and confirm source-contract failures.
- [x] Implement stable broker tokens, owner registration/rejection, deadline/generation checks, message helper, debounce/poll callouts, safe cancellation, and Ready polling rearm.
- [x] Document 250ms fallback latency and intentional resource preservation on teardown cleanup failure.
- [x] Run both strict host suites, static scan, and `git diff --check`; remove generated binaries and create one commit.
