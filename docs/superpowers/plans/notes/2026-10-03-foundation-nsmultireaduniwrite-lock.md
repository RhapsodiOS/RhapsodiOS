# Foundation `NSMultiReadUniWriteLock` reconstruction

Reference: Foundation i386 IDA database `d12fe2f23883` and
`src/Kits/Foundation/reconstruction/abi/NSLock.json`.

IDA confirms all ten selectors owned by `NSMultiReadUniWriteLock`, from
`0x4257766c` (`allocWithZone:`) through `0x42580354` (`unlock`). The class
allocates `0x34` extra bytes and points `_priv` immediately after its
Objective-C instance. Its state uses a mutex at offset 0, reader and writer
conditions at offsets 8 and 24, waiting-reader and waiting-writer counts at
word indices 10 and 11, active readers in the low 31 bits of word 12, and the
writer-held flag in its high bit.

Reader acquisition waits while a writer is active or queued. Writer
acquisition waits while a writer or any reader is active. Try-lock methods
preserve the target's distinct checks. Unlock prefers queued readers after a
writer releases; when the final reader exits, it signals a queued writer
before broadcasting to readers. Deallocation broadcasts to condition queues
with waiters and spins on their condition locks before superclass deallocation.
The description format reports active and waiting readers and writers.

All ten methods are implemented in `NSLock.m`. The focused ABI-owner audit
reports 49 expected selectors, zero missing, and zero duplicates. `git diff
--check` is clean. Tests and builds were not run.


## PPC packed-state follow-up (2026-10-07)

The earlier reconstruction note records the i386 layout. Paired PPC IDA shows
that `_priv[12]` instead packs the writer flag in bit 0 and the reader count in
bits 31:1. `NSLock.m` now has architecture-specific packing in initialization,
description, reader/writer acquisition, try-locks, and unlock. The shared wait
queue offsets, waiter counts, and wakeup order match the PPC body. The i386
branch remains unchanged; no ABI or ownership entries changed. Static paired
IDA/source review and whitespace check only; no tests or builds were run.
