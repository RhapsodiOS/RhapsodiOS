# Foundation per-thread autorelease-pool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reconstruct the target's per-thread paged autorelease-pool state and lifecycle in `NSAutoreleasePool.m`.

**Architecture:** Replace the global growable frame stack with the 144-byte `APData` block stored in the existing `NSThread.autoreleasePool` field. Use fixed-size linked pages, three-word nesting cursors, four recycled pool objects, and the existing NSZone page and exception APIs. PPC and i386 share this state layout; retain architecture-specific drain diagnostics where IDA differs.

**Tech Stack:** Objective-C, NSZone page allocation, NSThread current-thread storage, NSException handler macros, live PPC/i386 IDA.

**Spec:** `docs/superpowers/specs/2026-10-06-foundation-autoreleasepool-design.md`

## Global Constraints

- Keep the public API and `NSThread.autoreleasePool` offset 24 unchanged.
- Store pool state per thread in the target's 144-byte AP-data layout; do not keep the global stack as a fallback.
- Keep the total autoreleased-object counter global, while pool depth, queued-object count, settings, and recycling are per thread.
- Do not add or run tests or builds; verify against IDA and static source/layout checks only.

## Review Focus

- Releasing an outer token with nested pools drains every nested pool exactly once and leaves depth at the target token.
- Releasing an object that throws leaves page cursors as advanced by the target, skips the current batch's aggregate count subtraction, and continues through target pool cleanup without retrying the drain.
- A subclass pool's overridden `addObject:` receives autorelease traffic only while it is the innermost pool.
- Page exhaustion allocates or reuses one page and preserves older nesting snapshots across the linked-page boundary.
- Thread exit detaches and frees only that thread's pages and recycled pool objects.

---

### Task 1: Target AP-data and page storage

**Files:**
- Modify: `src/Kits/Foundation/NSAutoreleasePool.m`
- Modify: `src/Kits/Foundation/NSThread.m` (helper declaration and thread-exit sentinel call only)

**Interfaces:**
- Produces private AP-data, nesting-record, and page structures matching the offsets in the spec.
- Produces private helpers to lazily create AP data, grow nesting records by doubling, and obtain/link/clear pages.
- Consumes `_NSCurrentThread`, `NSPageSize`, `NSAllocateMemoryPages`, `NSDeallocateMemoryPages`, and NSZone allocation functions.

- [x] Replace the global `poolStack` and `NSAutoreleasePoolFrame` declarations with the target data structures and AP-data access helper.
- [x] Implement AP-data initialization with eight zeroed nesting records, copied default settings, four empty recycle slots, cached page size initialization, and exact 144-byte initial allocation.
- [x] Implement page acquisition from the free-page list or `NSAllocateMemoryPages`, preserving the 12-byte header and doubly linked active-page chain.
- [x] Change the cross-file `NSPushAutoreleasePool` declaration and thread-exit sentinel call to the target's no-argument signature; `-initWithCapacity:` capacity remains ignored as in IDA.
- [x] Compare structure offsets, allocation sizes, page linking, free-list reuse, and record-array growth against PPC and i386 `__NSAPDataCreate`, `__NSAPAddPage`, and `_NSPushAutoreleasePool`.

### Task 2: Push, append, and per-thread queries

**Files:**
- Modify: `src/Kits/Foundation/NSAutoreleasePool.m`

**Interfaces:**
- Consumes the Task 1 AP-data and page helpers.
- Produces target-token `NSPushAutoreleasePool`, page-backed `NSAutoreleaseObject`, and per-thread count/query helpers.

- [x] Rewrite `NSPushAutoreleasePool` to snapshot active page/count, clear the subclass-routing flag, and return/increment the per-thread nesting index.
- [x] Rewrite `NSAutoreleaseObject` to route to the innermost custom pool when flagged; otherwise append to the active page, update thread/global counts, and apply per-thread high-water settings.
- [x] Rewrite total/top count, object count, pool-existence, and `NSPrintAutoreleasePools` traversal to use page chains and nesting cursors.
- [x] Rewrite class getters/setters for high-water and release/freed-object settings to lazily create and access current-thread AP data.
- [x] Compare append thresholds, cursors, settings scope, global total, and reporting traversal against both IDA databases.

### Task 3: Drain, nested-object movement, and recycling

**Files:**
- Modify: `src/Kits/Foundation/NSAutoreleasePool.m`

**Interfaces:**
- Consumes AP-data, page helpers, and per-thread query/append code from Tasks 1 and 2.
- Produces target `NSPopAutoreleasePool`, object-to-parent-pool movement, and four-entry recycled pool lifecycle.

- [x] Rewrite `NSPopAutoreleasePool` to drain from the active page head back to the saved page/count for the token, decrement page cursors before callbacks, subtract completed batch counts after normal returns, and continue through nested tokens.
- [x] Use `NS_DURING`/`NS_HANDLER` around release callbacks; match each architecture's confirmed caught-exception log path and guard against recursive logging.
- [x] Move `-[NSAutoreleasePool addObject:]` entries from the innermost cursor to the receiver's saved pool cursor using the target's page-slot shifting algorithm.
- [x] Recycle up to four deallocated pool objects per thread; preserve custom subclass dispatch and allocation-statistics hooks where already present.
- [x] Compare nested drains, exception paths, custom subclasses, pool recycling, page recycling, and token reset against PPC and i386 IDA.

### Task 4: Thread teardown integration and records

**Files:**
- Modify: `src/Kits/Foundation/NSAutoreleasePool.m`
- Modify: `src/Kits/Foundation/reconstruction/divergences.md`

**Interfaces:**
- Consumes the completed per-thread pool state and drain helpers.
- Produces full `releaseAllPools` teardown and closes the documented global-stack/per-thread-storage divergence.

- [x] Rewrite `+[NSAutoreleasePool releaseAllPools]` to drain token zero, clear the current thread's AP-data pointer, deallocate active and free pages, deallocate recycled objects, and free AP data.
- [x] Remove comments describing global stack/frame storage and replace them with concise target-layout ownership notes.
- [x] Update the autorelease-pool divergence record to describe any remaining, directly confirmed difference only.
- [x] Run `git diff --check` on the slice and perform static scans for obsolete `poolStack`/`NSAutoreleasePoolFrame` references, layout offsets, and target-specific guards. Do not run tests or builds.
- [x] Preserve IDA's varargs call shape for autorelease diagnostics; retain the PPC direct-stderr and i386 `NSLog` split for distributed-notification diagnostics.

## Self-review

- **Spec coverage:** Tasks 1–4 cover AP-data layout, page lists, nesting growth, per-thread settings and counts, append/routing, nested drains, exception recovery, pool reuse, and thread teardown.
- **Step granularity:** Each step changes one coherent unit or compares one family of IDA behaviors. All steps are static/IDA verification because tests/builds are excluded by the global constraints.
- **Type consistency:** Pool tokens remain `void *` in the public object ivar but carry the integer nesting index as in the binary; the C push/pop helper signatures remain cross-translation-unit compatible.
- **Review focus:** Five high-risk conditions are named above for the final source-to-IDA pass.
- **Proportion:** The plan is four tasks aligned to the state, append/query, drain/recycling, and teardown boundaries of this single subsystem.

### Drain-path IDA correction (2026-10-06)

The paired i386/PPC drain bodies subtract the count of each fully completed
release batch after reacquiring current AP data; neither clamps that count to
`objectCount`. The source-only clamp was removed. Both targets also send
`-class` to the parent pool when setting the custom-subclass routing flag, so
the source now uses `[parentPool class]` instead of a direct `isa` comparison.
No ABI fields changed. Static source checks only; no tests or builds were run.
