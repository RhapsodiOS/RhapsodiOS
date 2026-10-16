# Foundation `NSDecimalNumber` ownership analysis

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSDecimalNumber.json`,
`src/Kits/Foundation/NSDecimalNumber.h`, and current
`src/Kits/Foundation/NSDecimalNumber.m`.

## Confirmed source gap

The ABI contains custom `retain`, `release`, and `retainCount` methods owned by
the variable-sized `NSDecimalNumber` class. The source declares `_hasExternalRefCount`
and `_refs` in `NSDecimalNumber.h`, but does not implement these methods under
`@implementation NSDecimalNumber`.

The similarly named methods in `NSDecimalNumber.m` belong to
`NSDecimalNumberPlaceholder`, the cached `allocWithZone:` receiver. That
placeholder intentionally behaves as an immortal object; its methods do not
implement ownership for the decimal instances allocated by
`initWithDecimal:`.

## IDA behavior

- `-[NSDecimalNumber retain]` at `0x42549fc8` optionally takes
  `_NSGlobalRetainLock`, increments the 16-bit `_refs` field at `self + 6`,
  and sets the external-refcount flag at `self + 5` when the inline count
  saturates at `0xffff`. If already external, it calls
  `_NSIncrementExtraRefCount`. It unlocks, records allocation event `6` when
  allocation statistics are enabled, and returns `self`.
- `-[NSDecimalNumber release]` at `0x42553230` records allocation event `7`
  when enabled, then optionally takes the global retain lock. A nonzero inline
  count is decremented. At zero, a clear external flag causes unlock and
  `-[NSObject dealloc]`. With the external flag set, it calls
  `_NSDecrementExtraRefCountWasZero`, clears and then conditionally restores
  the external flag from that result, sets `_refs` to `0xffff`, and unlocks.
- `-[NSDecimalNumber retainCount]` at `0x4259c35c` starts with `_refs + 1`;
  when the external flag is set it adds
  `(_NSExtraRefCount(self) << 16) + 0x10000`.
- IDA has no `-[NSDecimalNumber dealloc]` implementation. No custom deallocation
  behavior is inferred from the ownership methods.

The source should not copy the placeholder's immortal ownership methods onto
`NSDecimalNumber`; its IDA-confirmed inline and external count protocol is
distinct.

## Source helper mapping

Instruction-level review confirms the helper calls correspond to the existing
`NSZone.m` functions `NSIncrementExtraRefCount`,
`NSDecrementExtraRefCountWasZero`, and `NSExtraRefCount`. The Mach-O symbols
carry the leading underscore recorded by IDA. `NSDebug.h` defines allocation
events 6 and 7 as `NSObjectInternalRefIncrementedEvent` and
`NSObjectInternalRefDecrementedEvent`; `NSRecordAllocationEvent` is declared
in that header. `_NSGlobalRetainLock` is defined in `NSThread.m` and already
used by other custom Foundation ownership implementations.

The generic `_NSIncrementInternalRefCount` helper does not match this class's
overflow transition: it increments the side table at the inline limit without
resetting `_refs` or setting `_hasExternalRefCount`. An implementation must
preserve the explicit IDA sequence for the two fields and use the extra-count
helpers only for the external table operations.

## Implementation status (2026-10-03)

Implemented `retain`, `release`, and `retainCount` in `NSDecimalNumber.m` with
the inline/external transition above, optional global lock, extra-refcount
helpers, and allocation-statistics events. Static ABI-owner and whitespace
checks pass. Tests and builds were not run.
