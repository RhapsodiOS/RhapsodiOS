# Foundation cross-target simple retain-lock design

## Goal

Match the reference retain/release synchronization for the simple dictionary/set helpers and `NSStringArray` on PPC and i386, including the different lifetime of the simple-hashing lock in `NSThread`.

## Confirmed behavior

The PPC binary uses zero-initialized 32-bit spin words for these helper paths. When `_NSIsMultiThreaded` is nonzero, acquisition uses `lwarx`/`stwcx.` with `cthread_yield()` while contended, followed by `isync`; release uses `sync` and stores zero. The DR2 i386 binary uses Objective-C lock objects instead.

For `NSSimpleHashing`, PPC `NSRetainSimpleDictionary`, `NSReleaseSimpleDictionary`, `NSRetainSimpleSet`, and `NSReleaseSimpleSet` use `___NSSimpleHashingRetainLock`. Their i386 counterparts use `_NSSimpleHashingLock`. The current source implements the i386 path on both targets.

For `NSStringArray`, PPC `retainArray` and `releaseArray` use `___NSStringArrayRetainLock`, preserving the target's saturation and allocation-event behavior. i386 uses `_NSGlobalRetainLock`. The current source uses `_NSGlobalRetainLock` on both targets.

The i386 first-thread and last-thread hooks create and release `_NSSimpleHashingLock`. PPC exports no `_NSSimpleHashingLock`; its corresponding hooks do not create or release one. The PPC spin word is statically zero-initialized.

## Design

Keep the existing Objective-C lock paths for i386. Add target-specific PPC spin-word paths to the six confirmed helpers, with the multi-threaded check guarding lock operations and with counter changes and allocation events in the order established by IDA. Define the PPC lock words in the source modules that use them and record them in the PPC ABI, symbol, and ownership metadata.

In `NSThread.m`, retain `_NSSimpleHashingLock` creation and teardown only on i386. Do not add a PPC object lock or lifecycle call. Keep the existing lock counter semantics, including saturated retain counts and zero-count release results.

## Boundaries

This slice covers only `NSSimpleHashing.m`, `NSStringArray.m`, the `_NSSimpleHashingLock` lifecycle in `NSThread.m`, and the reconstruction records needed for those symbols. Other class-specific retain-lock globals and the placeholder locks have their own PPC/i386 differences; they remain separate reconstruction work and must not be changed as part of this slice.

No tests or builds are included. Verification is a direct PPC/i386 IDA comparison plus static source, ABI, symbol, ownership, and whitespace checks.

## IDA anchors

- PPC simple dictionary/set helpers: `0x4256d7cc`, `0x4256d5c8`, `0x4256d88c`, `0x4256d694`.
- i386 simple dictionary/set helpers: `0x4256328c`, `0x42563194`, `0x425632f8`, `0x42563204`.
- PPC array helpers: `0x4253758c`, `0x4252ffdc`.
- i386 array helpers: `0x42514484`, `0x4251840c`.
- i386 thread hooks: `0x425547f8`, `0x42571898`.
- PPC thread hooks: `0x4257f6dc`, `0x4257fdfc`.

The detailed cross-target observations are recorded in `docs/superpowers/plans/notes/2026-10-04-foundation-c-symbol-coverage.md` under “Cross-target simple retain-lock paths (2026-10-06)”.
