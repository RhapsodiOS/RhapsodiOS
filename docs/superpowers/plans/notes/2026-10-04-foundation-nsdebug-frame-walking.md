# Foundation NSDebug frame and allocation-statistics helpers

Reference: Foundation i386 IDA database `703cb6287da7`, with the frame helper
addresses recovered from the Mach-O export table.

Implemented the six exported frame helpers in `NSDebug.m`:

| Export | IDA address |
| --- | ---: |
| `_NSCountFrames` | `0x4256ed88` |
| `_NSFrameAddress` | `0x4256ede0` |
| `_NSReturnAddress` | `0x4256fb98` |
| `__NSFirstFrameAddress` | `0x42570750` |
| `__NSNextFrameAddress` | `0x42570b98` |
| `__NSReturnAddressFromFrameAddress` | `0x42571888` |

The i386 behavior follows IDA's frame-chain walk and `0x7ff` termination
check. The PPC return-address path follows the local prologue in
`src/architecture-1/ppc/asm_help.h`: the backchain is at offset 0 and the
saved link register is at offset 8 from the previous stack pointer. This is
architecture evidence from the repository; the IDA database is i386 only.

The six exports were added to `NSDebug.json` and assigned to `NSDebug.m` in
`symbols.json`. Also implemented the two allocation-statistics port helpers,
whose IDA addresses are `_NSGetAllocationStatisticsOutputPort` at
`0x4256ee18` and `_NSSetAllocationStatisticsOutputPort` at `0x4256fbc0`.
The getter wraps the stored port with `+[NSPort portWithMachPort:]`; the
setter stores `-[NSPort machPort]`, or zero for a null argument, matching the
reference pseudocode.

The static symbol audit reports 62 unclaimed exported functions, down from
70 before these eight helpers. JSON parsing and `git diff --check` found no
errors (Git reports only the existing CRLF normalization notice for
`symbols.json`). No tests or builds were run.

## `NSStringFromStack` recheck (2026-10-06)

The i386 and PPC bodies at `0x4256fbfc` and `0x4257d48c` match the current
`NSDebug.m` implementation: create an autoreleased mutable string, start at
`_NSFirstFrameAddress`, separate frames after the first, append the formatted
return address for each frame, and stop when `_NSNextFrameAddress` returns an
address at or below `0x7ff`. PPC pseudocode directly shows
`initWithCapacity:1024`; i386 disassembly confirms the same `0x400` argument,
which its decompiler omitted. Both targets default a nil format and separator
before walking. This closes the old divergences entry that called uncaught
stack formatting unreconstructed; no runtime test or build was run.
