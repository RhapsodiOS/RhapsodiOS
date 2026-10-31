# Foundation `NSMachPort` remaining selector analysis

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSPort.json`, and current
`src/Kits/Foundation/NSPort.m`.

## Confirmed owner gaps

The current source has no owner for the four `NSMachPort` class methods
`_enableLogging:`, `allPorts`, `handleMachMessage:`, and
`statusForMachPort:`, nor for `-description`. IDA confirms:

- `+_enableLogging:` (`0x4257746c`) stores its Boolean argument in the
  `enableLogging5` global.
- `+allPorts` (`0x42577484`) locks `_NSPortTableLock` when present, returns
  `NSAllHashTableObjects(_NSPortTable)` or `[NSArray array]` when the table is
  absent, and unlocks before returning.
- `+handleMachMessage:` (`0x42577510`) reads the message id at word offset 5.
  For id 65 it wraps the port name at word offset 7 with
  `[NSPort portWithMachPort:]` and invalidates it; other ids raise
  `NSInternalInconsistencyException` using the method proem and
  `"%@: bad notify msg %d"`.
- `+statusForMachPort:` (`0x425775e8`) calls `port_status(task_self_, port, ...`;
  failures log `"port_status returned %d (%s)"`, while success logs
  `"port %d inSet=%d num_msgs=%d backlog=%d amOwner=%d isRecvr=%d\n"`.
- `-description` (`0x4257ff5c`) formats `"<MachPort %d %s>"`, using the Mach
  port number and `"valid"` or `"invalid"` according to the validity bit.

At the time of the initial analysis, no source definitions for these methods
were present in `NSPort.m`. No tests or builds were run for that analysis.

## Implementation status (2026-10-03)

All five methods are now implemented in `NSPort.m`. `+handleMachMessage:`
uses the declared deleted-port notification structure and rejects other
message IDs with the reference exception format. `+statusForMachPort:` uses
the legacy `port_status` interface and both reference log formats.
`+[NSMachPort _enableLogging:]` stores the flag consumed by
`-[NSMachPort invalidate]`; the invalidate log text and condition were
confirmed by decompiling the read xref at `0x42580013`.

The focused ABI owner audit reports 24 expected `NSMachPort` selectors, 24
source definitions, and no missing, extra, or duplicate selectors.
`git diff --check` is clean. No tests or builds were run.
