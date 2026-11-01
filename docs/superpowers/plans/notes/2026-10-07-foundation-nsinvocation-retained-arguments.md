# `NSInvocation` retained argument parity (2026-10-07)

IDA comparison confirmed the argument ownership paths in both Foundation
targets:

- i386 `setArgument:atIndex:` at `0x42525a38` uses
  `_NSParseAndRelease` / `_NSParseAndRetain` around the frame copy when the
  retained-arguments bit is set. `retainArguments` at `0x42573e6c` retains the
  target and type-walks arguments from index 2. `invalidate` at `0x425262bc`
  releases frame arguments in reverse index order.
- PPC `setArgument:atIndex:` at `0x42532ad0` releases and retains values by
  walking nested argument records; it scatters struct arguments and widens
  4-byte float inputs into 8-byte frame slots. `retainArguments` at
  `0x4254cf84` retains the target and nested object/C-string slots.
  `invalidate` at `0x425204d0` releases the frame records in reverse index
  order.
- PPC `+[NSMethodSignature signatureWithObjCTypes:]` at `0x4251ab64` builds
  those child records through `_compute_pip_offset` at `0x42514efc`; its
  `_argumentInfoAtIndex:` at `0x42584900` copies all five record fields.
  `NSMethodSignature.m` now constructs the nested aggregate records and the
  PPC register/stack offsets consumed by the invocation helpers. The i386
  signature layout path remains unchanged.
- PPC `_postInitWithCoder:...` at `0x4253c678` sets the retained-arguments bit
  after the target and selector, then clears and restores it around each
  `setArgument:atIndex:` call. Both targets route index `-1` through
  `setReturnValue:`.
- Both targets implement `target`, `selector`, `setTarget:`, and `setSelector:`
  through `getArgument:atIndex:` / `setArgument:atIndex:` (i386 accessors at
  `0x4254ea30`, `0x42545c64`, `0x42574334`, and `0x42574310`; PPC accessors at
  `0x4253a294`, `0x425344e4`, `0x4254cde0`, and `0x4258473c`). The source now
  routes these accessors through the same frame and ownership logic.
- PPC `getArgument:atIndex:` at `0x42514020` gathers aggregate fields from
  their register/stack slots and converts 8-byte frame floats back to 4-byte
  float arguments; `_gather_struct` at `0x425869c4` walks the same nested
  records as `_scatter_struct`. `NSInvocation.m` now mirrors both read paths.

`NSInvocation.m` now implements those setter, retain, invalidation, struct
scattering, and coder flag transitions without changing the ivar layout.
Static source/IDA review and `git diff --check` only; no tests or build were
run. Object-level ABI verification remains unperformed because it requires a
build.

### Argument reads use overlap-safe copies

The i386 `getArgument:atIndex:` body at `0x42517698` uses `memmove` for
argument slots and for return values represented as a C string or struct; its
scalar return cases load and store the exact tagged value. The PPC body at
`0x42514020` uses `memmove` for ordinary argument slots, with separate gather
and float-conversion paths. `NSInvocation.m` now uses `memmove` for its
byte-copy paths so a caller buffer overlapping the invocation frame follows
the target's copy semantics. Static IDA/source review and
`git diff --check` only; no tests or builds were run.

The i386 return-value case for `{` at `0x42517698` takes the stored
`structLocation` directly into the common `memmove` path. The source's
null-buffer early return was therefore removed; a missing struct buffer now
follows the target's direct-copy path.

For compound returns, both target accessors take the copy length from the
signature's `methodReturnLength` field (i386 offset `+16`; PPC offset `+16`).
The source now uses that recorded length for struct/union return reads and
retains `NSGetSizeAndAlignment` for scalar reads.

### Return-retain flag clearing (2026-10-08)

Both i386 `-[NSInvocation invalidate]` (`0x425262bc`) and PPC
`-[NSInvocation invalidate]` (`0x425204d0`) enter the object-return branch by
type, release the return object only when the retained-return bit is set, and
clear that bit unconditionally within the branch. `NSInvocation.m` now follows
that sequence. Static IDA/source review and `git diff --check` only; no tests
or builds were run.

### Invoke return ownership recheck (2026-10-08)

i386 `-[NSInvocation invoke]` (`0x42526400`) releases the previous non-void
return before dispatch, then parses and retains the new return and sets the
retained-return flag. Its `performSelector:` cases use the invoked method's
signature and skip retention when that method returns void. PPC
`-[NSInvocation invoke]` (`0x4253d840`) does not retain the returned object or
set that flag; its `performSelector:` path only reads the invoked return type.
The current architecture-guarded `NSInvocationRetainReturnedValue` helper and
`invoke` body preserve those differences. Static paired IDA/source review
only; no tests or builds were run.
