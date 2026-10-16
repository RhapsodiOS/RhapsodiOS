# Foundation Placeholder Cache Design

## Goal

Reconstruct the Foundation placeholder caches and their synchronization for
`NSString`, `NSValue`, `NSNumber`, and `NSDecimalNumber` from the MOSXS PPC
and DR2 i386 Foundation binaries. Preserve the target's architecture-specific
lock representation and `NSThread` lifecycle.

## Target evidence

IDA confirms that both binaries use `NSMutableArray` caches for these
placeholder objects. `NSString` and `NSDecimalNumber` each keep their own
placeholder array and most recently used placeholder. `NSValue` and
`NSNumber` share one placeholder array, one cached placeholder, and one lock;
the cached entry is checked by both class and zone.

The current `NSString.m` already uses an array and last-used placeholder. The
current `NSValue.m` uses separate linked lists and separate lock objects for
NSValue and NSNumber. The current `NSDecimalNumber.m` uses a linked-list cache.
These three sources therefore diverge from the target cache representation.

Synchronization differs by architecture:

- PPC stores each placeholder lock as a zero-initialized 32-bit word. The
  three placeholder factories acquire it only when `_NSIsMultiThreaded` is
  true, using `lwarx`/`stwcx.`, yielding while contended, then `isync`; they
  release with `sync` and a zero store. The value factory uses the same lock
  for both NSValue and NSNumber.
- i386 stores object-pointer locks. Its factories send `lock` and `unlock`
  when their lock pointer is non-null. `__NSToDoAtFirstThreadStart` creates
  the three lock objects and `__NSToDoAtLastThreadExit` releases them.
- The PPC thread-start and thread-exit hooks do not create or release these
  placeholder lock globals. The current `NSThread.m` performs the object
  lifecycle unconditionally, so it diverges on PPC.
- The exported linker names differ by architecture. i386 uses
  `__NSPlaceholderStringLock`, `__NSPlaceholderValueLock`, and
  `__NSPlaceholderDecimalNumberLock`. PPC uses
  `___NSStringPlaceholderLock`, `___NSValuePlaceholderLock`, and
  `___NSDecimalNumberPlaceholderLock`. On PPC each lock is defined by its
  corresponding placeholder source; on i386 `NSThread.m` owns the shared
  value lock and the string and decimal sources own their lock objects.

The confirmed factory entry points are PPC `__NSPlaceholderStringFromZone`
(`0x42503a70`), `__NSPlaceholderFromZone` (`0x4251b458`), and
`__NSDecimalNumberPlaceholderWithZone` (`0x4255b0d8`); i386 counterparts are
`__NSPlaceholderStringFromZone` (`0x42503c08`), `__NSPlaceholderFromZone`
(`0x4251f534`), and `__NSDecimalNumberPlaceholderWithZone` (`0x425a2d78`).
The thread lifecycle entries are PPC `__NSToDoAtFirstThreadStart`
(`0x4257f6dc`) and `__NSToDoAtLastThreadExit` (`0x4257fdfc`), and i386
`__NSToDoAtFirstThreadStart` (`0x425547f8`) and
`__NSToDoAtLastThreadExit` (`0x42571898`).

## Design

Make the cache state in each source file match the target's array model and
lookup order. `NSString` retains its existing array/cache behavior. Replace
the NSValue and NSNumber linked lists with a single shared array and cached
entry, selecting placeholder class before lookup and matching both class and
zone. Replace the decimal-number linked list with its target array and cached
entry. Preserve each target factory's allocation, zone storage, array
insertion, retain/release, and cache-update order as confirmed by IDA.

Have both NSValue and NSNumber factories use the existing
`_NSPlaceholderValueLock` global owned by `NSThread.m` on i386; remove their
two per-factory static lock objects. On PPC, both factories use the same
zero-initialized word. Keep lock acquire/release code private to Foundation
sources rather than adding a new exported lock API.

Keep the i386 lock objects and thread-start/exit lifecycle. For PPC, represent
the three exported lock symbols as zero-initialized 32-bit words, use the
target's atomic acquire/yield/release sequence in the three factories, and
exclude these words from Objective-C lock creation and release in the
`NSThread` hooks. The single NSValue/NSNumber word protects both caches.

Update ABI, symbol-owner, ownership, and architecture-divergence records to
reflect the architecture-specific exported names and ensure each exported
data symbol has one source owner. Do not merge this work with the other
exported retain-lock globals.

## Scope

In scope:

- Placeholder factory cache representations and most-recently-used cache
  behavior in `NSString.m`, `NSValue.m`, and `NSDecimalNumber.m`.
- PPC spinlock words and their atomic synchronization sequences.
- i386 `NSLock` objects and `NSThread` first-start/last-exit lifecycle.
- Required declarations, build metadata if a private shared lock helper is
  needed, ABI records, symbol ownership, and divergence documentation.

Out of scope:

- Other Foundation retain locks and allocator/refcount synchronization.
- Placeholder initialization methods after the factories return.
- Changes to exported selectors or placeholder object instance layouts.
- Runtime tests and builds; use the repo's IDA-backed and static metadata
  checks only.

## Verification

- Compare the cache hit path, reverse array search, class/zone match, cache
  update, allocation, insertion, and ownership operations against all six
  factory bodies.
- Compare i386 lock creation/release and the absence of placeholder lock
  lifecycle in PPC `NSThread` hooks.
- Confirm both architecture source paths use the expected lock representation
  and acquisition condition: `_NSIsMultiThreaded` on PPC and a non-null lock
  pointer on i386.
- Parse changed JSON manifests and run `git diff --check` for the slice.
- Do not add or run tests or builds.
