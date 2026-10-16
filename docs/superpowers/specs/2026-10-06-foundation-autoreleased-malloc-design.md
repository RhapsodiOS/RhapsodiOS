# Foundation `_NSAutoreleasedMallocMemory` Design

## Goal

Match the PPC and i386 Foundation per-thread scratch-chunk cache and cleanup
behavior in `NSPrivate.m`.

## Reference behavior

Both targets route requests larger than 500 bytes to an exact-size autoreleased
chunk without consulting the cache. Requests at or below 500 bytes read the
current thread's `threadDictionary` entry named `NSAutoreleaseMalloc`, unwrap
its `NSValue` nonretained-object value, and inspect the chunk's remaining
capacity. If the existing chunk has enough room, use it. Otherwise, when
`500 - capacity > remainingCapacity`, allocate and autorelease a 500-byte chunk
and replace the dictionary value; when that comparison is false, allocate and
autorelease an exact-size dedicated chunk without replacing the cache.

On deallocation, both targets obtain the current thread dictionary and remove
the key only when its unwrapped object is the chunk being deallocated, then
free the chunk's bytes and call superclass deallocation. The target's thread
deallocators release and clear `threadDictionary` before draining autorelease
pools; this order is part of the observed lifecycle and must not be changed as
part of this slice.

## Design

Replace `currentMallocMemoryChunk` with the target's dictionary lookup and
nonretained `NSValue` wrapper in `+mallocMemoryWithCapacity:`. Preserve the
existing allocation thresholds, autorelease ownership, bump-allocation order,
and exact comparison at the cache replacement boundary. In `-dealloc`, clear
the dictionary key only when it still refers to `self`, then free the bytes
and invoke `[super dealloc]`.

Use the existing `_NSCurrentThread`, `NSThread.threadDictionary`, `NSValue` nonretained-object,
`NSMutableDictionary`, and autorelease APIs. This is shared behavior confirmed
in both target binaries; no ABI export or public header is added. Preserve the
target's exact `-remainingCapacity` result, `500 - length`, including its
unsigned arithmetic behavior.

## Scope

In scope: cache lookup and replacement, exact-size and cached allocation
branches, cache-key cleanup during chunk deallocation, and the source comments
that explain the per-thread representation.

Out of scope: changes to `NSThread` teardown order, chunk layout, public APIs,
other Foundation scratch allocators, runtime tests, and builds.

## Verification

Compare both architecture implementations with PPC entries
`0x42525c40`, `0x42528480`, `0x42531fb8` and i386 entries `0x4251ba24`,
`0x42518bb4`, `0x425282b4`. Confirm the key string, `NSValue` wrapper,
comparison boundary, dictionary cleanup condition, and teardown call order.
Use static source review and `git diff --check`; do not add or run tests or
builds.
