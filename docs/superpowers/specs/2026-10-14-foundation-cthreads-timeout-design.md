# Foundation cthreads Timeout Helpers Design

## Goal

Reconstruct the five condition-wait and wake helpers that are present in both
Foundation images and currently supplied to `NSLock.m` by the generic Libc
cthreads implementation. Preserve the Foundation helpers' seconds-based
timeout boundary, Mach message protocol, and exception behavior on i386 and
PPC.

## Evidence

IDA identifies the same five helpers on both targets:

| Helper | i386 address / size | PPC address / size |
| --- | --- | --- |
| `condition_wait_timeout` | `0x42519558` / 506 | `0x4259d714` / 560 |
| `condition_signal_timeout` | `0x42503410` / 85 | `0x4259d694` / 128 |
| `condition_broadcast_timeout` | `0x42585c94` / 32 | `0x4259d654` / 64 |
| `cproc_continue_timeout` | `0x425380b4` / 124 | `0x4259d944` / 156 |
| `dequeue_unlock_send` | `0x42585d2c` / 69 | `0x4259da70` / 108 |

Both wait helpers enqueue the current cproc, mark it blocked, release the
condition spin lock and caller mutex, then receive a 24-byte wake message.
Interrupted receives retry. Timeout checks `CPROC_EATING` before and after
taking the condition lock; if no signaler claimed the cproc, the helper removes
it from the wait queue and restores its running state. A successful receive
also restores the running state. Both paths reacquire the caller mutex before
returning. Signal removes and marks one waiter before sending. Broadcast
recursively drains and marks the queue while holding the condition lock, then
sends to each waiter as recursion unwinds. `SEND_SUCCESS` and
`SEND_TIMED_OUT` are accepted; other receive/send results raise Foundation
exceptions.

The Foundation wait helper receives seconds and converts them to milliseconds
for `msg_receive` by multiplying by 1000, truncating toward zero, and using
`UINT_MAX` when the product is greater than or equal to `UINT_MAX`. Both targets
pass that sentinel through as the receive timeout. Callers pass `1.0e20` for
unbounded waits and the remaining interval in seconds for timed waits. Timed
callers reject expired negative intervals before entering the helper. The existing Libc
`condition_wait_timeout` instead accepts milliseconds and logs/asserts/aborts on
Mach errors. `src/Libc-1/threads.subproj/cprocs.c:443-569` is useful protocol
evidence, but is not an exact Foundation body.

## Design

- Keep the reconstruction in `src/Kits/Foundation/NSLock.m`, where `NSLock`,
  `NSCondition`, and the other condition callers already live.
- Add Foundation-local helper names to avoid colliding with the Libc declarations
  from `cthreads.h`.
- Include the repository's private
  `../../Libc-1/threads.subproj/cthread_internals.h` from `NSLock.m` for
  `cproc_t`, state values, and `cproc_self`; do not duplicate private cproc
  offsets in Foundation or change the project include configuration.
- Implement wait, single-signal, broadcast, send, and recursive queue-drain
  helpers from the paired IDA flows. Preserve the 24-byte Mach message fields,
  retry rules, queue lock boundaries, and `CPROC_EATING` race checks.
- Change Foundation call sites to pass seconds directly. Use `1.0e20` for
  unbounded waits and pass the computed remaining interval for date-based waits.
  Keep caller-side deadline checks and mutex behavior as shown in IDA.
- Preserve target-specific helper names and error strings in comments and
  source maps. Add paired entries for all five helpers.
- Do not modify `src/Libc-1/threads.subproj/cprocs.c`; its public API remains
  millisecond-based and its failure policy remains Libc-specific.

## Scope and checks

Files in scope:

- `src/Kits/Foundation/NSLock.m`
- `src/Kits/Foundation/reconstruction/locking/source-map.json`
- `src/Kits/Foundation/reconstruction/locking-i386/source-map.json`
- `src/Kits/Foundation/reconstruction/divergences.md`

Static review only: compare all helper control flow and call boundaries against
both IDA databases, validate the paired source-map addresses/names/sizes, and
run `git diff --check`. Do not add or run tests or builds.

## Risks to resolve during implementation

- Keep exception format strings architecture-specific where the reference
  differs, including PPC's trailing underscores in the helper names.
