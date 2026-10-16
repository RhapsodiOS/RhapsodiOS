# Foundation cthreads Timeout Helpers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Reconstruct Foundation's paired condition-wait and wake helpers in `NSLock.m` with the exact seconds-based timeout boundary and cproc queue protocol shown in i386 and PPC IDA.

**Architecture:** Keep all five helpers beside the lock callers in `NSLock.m`. Use the repository's private cproc definitions, implement the Foundation Mach message and exception paths locally, and route Foundation callers through these helpers with seconds values. Add paired source maps and record the static IDA comparison.

**Tech Stack:** Objective-C/C, Mach message APIs, the repository's cthreads headers, IDA pseudocode/disassembly, and source-map JSON.

**Spec:** `docs/superpowers/specs/2026-10-14-foundation-cthreads-timeout-design.md`.

## Global Constraints

- Preserve i386 and PPC behavior, including the 24-byte wake message, retry rules, `CPROC_EATING` race checks, lock order, and Foundation exceptions for unexpected Mach errors.
- Keep Foundation wait timeouts in seconds; pass `1.0e20` for unbounded waits and the computed remaining seconds for timed waits.
- Do not modify the generic Libc cthreads implementation or public cthreads API.
- Do not change Foundation class layouts, selectors, or public ABI manifests.
- Do not add or run tests or builds; use static paired IDA/source/map review only.

## Review Focus

- Timeout conversion: multiply seconds by 1000, truncate toward zero, and use `UINT_MAX` when the product is greater than or equal to `UINT_MAX`.
- Timeout/signal race: check `CPROC_EATING` before and after acquiring the condition lock and avoid removing a waiter already claimed by a signaler.
- Queue lock ownership: verify signal releases the lock before send and broadcast releases it only after the recursive drain.
- Mach message shape: compare every field and accepted return code on both architectures.
- Error diagnostics: preserve the i386/PPC helper-name strings and raise path for unexpected send/receive results.

---

### Task 1: Implement Foundation-local timeout and wake helpers

**Files:**
- Modify: `src/Kits/Foundation/NSLock.m`

**Interfaces:**
- Consumes: the existing `condition_t`/`mutex_t` API and private `cproc_t` definitions from `../../Libc-1/threads.subproj/cthread_internals.h`.
- Produces: static Foundation-local helpers for condition wait, single signal, broadcast, send-to-waiter, and recursive queue draining. The wait helper accepts a `double` timeout in seconds and returns whether it woke from a message.

- [x] Include the private cproc definitions from the repository-relative header without changing Foundation project include settings.
- [x] Implement the wait helper with seconds-to-milliseconds conversion, blocked-state enqueue, mutex release/reacquire, interrupted receive retry, timeout race checks, self-removal, and the target's return value.
- [x] Implement waiter send, single signal, and recursive broadcast with the 24-byte message, `SEND_SUCCESS`/`SEND_TIMED_OUT` acceptance, exact lock boundaries, and Foundation exception diagnostics.
- [x] Replace `condition_wait_timeout`, `condition_signal_timeout`, and `condition_broadcast_timeout` calls in `NSLock.m` with the local helpers; pass `1.0e20` for indefinite waits and seconds for timed waits.
- [x] Review every helper and call site against both IDA bodies and raw instructions; do not run tests or builds.

### Task 2: Map and audit the reconstructed helpers

**Files:**
- Modify: `src/Kits/Foundation/reconstruction/locking/source-map.json`
- Modify: `src/Kits/Foundation/reconstruction/locking-i386/source-map.json`
- Modify: `src/Kits/Foundation/reconstruction/divergences.md`

**Interfaces:**
- Consumes: the local helper definitions from Task 1.
- Produces: paired address/name/size records for all five helpers and an audit entry describing their verified behavior.

- [x] Add the five PPC records: wait `0x4259d714`/560, signal `0x4259d694`/128, broadcast `0x4259d654`/64, send `0x4259d944`/156, and drain `0x4259da70`/108.
- [x] Add the five i386 records: wait `0x42519558`/506, signal `0x42503410`/85, broadcast `0x42585c94`/32, send `0x425380b4`/124, and drain `0x42585d2c`/69.
- [x] Refresh affected source-line anchors and verify map JSON, address ordering, names, sizes, and helper coverage against both live IDA databases.
- [x] Append the paired behavior comparison to `divergences.md` and run `git diff --check` on the files changed by this plan.
- [x] Report that behavior was statically reviewed and remains unverified by tests or builds.
