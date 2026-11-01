# Foundation autorelease-pool reconstruction design

## Goal

Replace the process-global autorelease-pool frame stack in `NSAutoreleasePool.m`
with the per-thread paged state used by both MOSXS PPC and DR2 i386. Preserve
the existing Objective-C API while matching nested-pool drains, counters,
configuration, subclass routing, pool recycling, and thread-exit cleanup.

## Evidence

Both IDA databases contain the same private helpers and state shape:

- `__NSAPDataCreate` allocates 144 bytes, initializes twelve header words and
  eight three-word nesting records, and snapshots the current global defaults.
- `__NSAPAddPage` links a page of `NSPageSize()` bytes into the active list or
  reuses a cleared page from the AP-data free list. The 12-byte page header is
  `{next, previous, objectCount}`; object pointers begin at byte 12.
- `NSPushAutoreleasePool` and `NSPopAutoreleasePool` use the existing
  `NSThread.autoreleasePool` pointer at byte offset 24. A pool token is the
  nesting index, not a frame pointer.
- The per-thread AP-data header is: active-page head (0), total queued object
  count (4), high-water mark (8), high-water resolution (12), release enabled
  (16), freed-object checking enabled (17), drain-exception guard (18),
  subclass `addObject:` routing flag (19), free-page head (20), four recycled
  pool object pointers (24..36), nesting capacity (40), and nesting depth (44).
  Nesting records begin at byte 48 and contain the saved page count, page
  pointer, and pool instance for each depth.
- The nesting array starts with capacity 8 and doubles. Data allocation and
  page allocation both use the existing zone/page APIs in `NSZone.h`.
- `NSAutoreleaseObject`, object/pool counts, `autoreleasePoolExists`, the
  high-water settings, `+[NSAutoreleasePool addObject:]`, pool allocation,
  release, and thread `releaseAllPools` all read or mutate the current thread's
  AP data.
- PPC and i386 have matching page, counter, and recycling behavior. Their
  caught-exception logging paths differ; preserve target messages per
  architecture.

## Design

Keep the pool implementation in `NSAutoreleasePool.m`. Add only the direct
`NSPushAutoreleasePool` declaration/call adjustment in `NSThread.m` so its
thread-exit sentinel uses the target's no-argument helper ABI. Introduce private C structs
whose field offsets and sizes reproduce the AP-data header, nesting record,
and page header, with compile-time layout checks if supported by the source
compiler. Route state through `_NSCurrentThread()->autoreleasePool`; avoid
adding another TLS mechanism or a process-global fallback stack.

Implement the page list and nesting snapshots directly from `__NSAPAddPage`,
`NSPushAutoreleasePool`, `NSAutoreleaseObject`, `NSPopAutoreleasePool`, and
`-[NSAutoreleasePool addObject:]`. Preserve the target's per-thread settings
and global total-autorelease counter. `-[NSAutoreleasePool release]` drains by
its numeric token; class allocation takes one of up to four recycled pool
instances before calling `NSAllocateObject`. `releaseAllPools` drains depth
zero, detaches AP data from the current thread, then frees active pages, free
pages, recycled instances, and the AP-data block.

During a drain, release objects in reverse insertion order and decrement each
page cursor before invoking user code. After a page batch returns normally,
subtract its completed-release count from AP data. If a release throws, follow
the target's handler path directly to pool cleanup without subtracting the
current batch or retrying the remaining drain. Use the repository's
`NS_DURING`/`NS_HANDLER` machinery to match the target's exception guard and
diagnostics. Preserve custom-subclass `addObject:` dispatch when the innermost
pool is not exactly `NSAutoreleasePool`.

The existing public counts and debug dump become views over the current
thread's linked pages and saved nesting cursors. Keep existing allocator,
freed-object, stderr, and high-water logging helpers unless direct IDA
comparison demonstrates a mismatch.

## Scope and constraints

- Modify `NSAutoreleasePool.m`, its corresponding divergence paragraph, and
  only the `NSThread.m` declaration/call needed for the no-argument pool-push helper.
- Keep `NSThread` layout and the `autoreleasePool` ivar at offset 24 unchanged.
- Keep the public API, selector ownership, and global total-autoreleased count.
- Match the target page and nesting layout; do not retain the growable global
  array representation as a fallback.
- Preserve PPC/i386 target-specific exception messages and any confirmed
  low-level difference.
- Do not add or run tests or builds. Verify against both IDA databases, source
  layout, metadata, and static whitespace checks.

## Out of scope

- Reconstructing the separate `NSThread` implementation or changing its
  ivar layout.
- Changing NSZone allocation/page implementations.
- Changing autorelease allocation-event packet behavior.
