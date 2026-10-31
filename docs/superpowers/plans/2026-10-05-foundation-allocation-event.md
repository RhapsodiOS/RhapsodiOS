# Foundation allocation event reconstruction

## Goal

Reconstruct the exported `NSRecordAllocationEvent` sender for i386 and PPC
from the Foundation IDA databases. Keep the existing public API and make the
matching `NSWaitForAllocationEvent` / `NSParseAllocationEvent` receiver path
understand the packet produced by the current target.

## Evidence

- i386 wrapper at `0x4256fae4` forwards the event and four variadic argument
  words to `__NSRecordAllocationEvent` at `0x42571124`.
- PPC wrapper at `0x4257d2fc` forwards to the PPC helper at `0x4257f0c8`.
- Both targets accept event IDs 0–11 and 16–24, apply the output mask, resolve
  `NSAllocationStatisticsOutputPortName`, serialize fields, and send with
  `msg_send`; a first result of `-103` retries with option `0x20`.
- Existing `NSDebug.m` supplies the output-port accessors, environment-derived
  settings, receiver, parser, and negative-retain reporter. Existing
  `NSThread.m` declares, allocates, and frees `__NSDebugRecordLock`.
- Event field routing and known header-comment discrepancies are recorded in
  `docs/superpowers/plans/notes/2026-10-04-foundation-c-symbol-coverage.md`.
- Pool-deallocation events 8 and 9 have no source-level payload at call sites,
  but the target copies the first variadic slot into the packet pointer field;
  preserve that raw read in the sender.

## Design

1. Add a variadic exported wrapper and a private sender implementation in
   `NSDebug.m`. Decode the documented arguments by event case; preserve the
   observed event 11 behavior, which copies the third variadic argument into
   the class-name field. Unsupported IDs 12–15 and IDs above 24 emit no packet.
   If their output-mask bit is enabled, preserve the target's preceding lock
   and lazy port-resolution work before the event switch reaches its default.
2. Keep the shared semantic packet fields in one implementation: version,
   destination port, timestamp, sequence, event type, size, trace count,
   thread, zone, pointer, data, class name, and bounded frame addresses.
   Preserve the per-event payload routing confirmed by both targets and the
   current `NSZone.m` call sites.
3. Use target-specific packet initialization and timestamp conversion:
   - i386 copies its 7,608-byte template; class starts at word 7, timestamp at
     words 39–40, sequence/type at 42–43, size/count at 44–45, thread at
     50–51, zone/pointer/data at 52–57, and trace pairs at word 62 onward.
     Its template SHA-256 and nonzero words are in the evidence note.
   - PPC uses its 3,512-byte template and the same semantic field positions;
     its parser treats the timestamp as the native double at message offset
     156. The i386 template must not be reused for PPC.
   - The packet sizes bound the trace to 920 frames on i386 and 408 frames on
     PPC.
4. Preserve lock differences: i386 uses the record mutex when its pointer is
   non-null; PPC takes the debug-record lock only when the runtime is
   multithreaded. The lock is released on every path after acquisition.
5. Resolve the output port lazily under the lock. Preserve the
   `mach-port://host/name` split and lookup semantics; i386 allocates the host
   substring dynamically, while PPC clamps it to 259 bytes in a zeroed
   260-byte stack buffer.
6. Make `NSWaitForAllocationEvent` use the target's receive buffer size and
   packet copy length. Make `NSParseAllocationEvent` decode the target's
   timestamp representation while preserving the common event field and
   backtrace mapping.
7. Use `NSAutoreleasePoolCountForObject` for the negative-retain check. The
   Foundation autorelease-pool reconstruction now stores AP data on the
   current `NSThread` and counts that thread's active pages, matching the
   target's per-thread lookup.

## Source and metadata

- Implement sender and receiver changes in `src/Kits/Foundation/NSDebug.m`.
- Change lock lifecycle in `NSThread.m` only if review of the current source
  against both IDA paths finds a missing initialization/free behavior.
- Register `_NSRecordAllocationEvent` in the shared symbol map, ownership map,
  and the `NSDebug.m` ABI manifest. The symbol is exported by both target
  profiles.
- Record any remaining target divergence in `reconstruction/divergences.md`
  and the evidence note.

## Review checks

- Compare every event case's argument routing against the i386 and PPC IDA
  bodies and `NSZone.m` callers.
- Check packet size, template constants, offsets, and retry flags per target.
- Check all lock exits and lazy port-resolution failure paths.
- Parse edited JSON and run `git diff --check`; do not add or run tests/builds
  unless requested.

## Resolved dependency

The negative-retain check's per-thread count dependency is satisfied by the
2026-10-06 autorelease-pool reconstruction. `NSAutoreleasePoolCountForObject`
uses `NSAutoreleasePoolDataForThread(_NSCurrentThread(), NO)` and traverses the
current thread's active pages; `NSDebugRecordAllocationEvent` calls that helper.
The previous process-global-stack limitation no longer applies to this path.
