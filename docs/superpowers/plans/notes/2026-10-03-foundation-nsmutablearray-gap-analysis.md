# Foundation `NSMutableArray` missing-selector analysis

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSArray.json`, and current
`src/Kits/Foundation/NSArray.m`.

The ABI/source-owner audit found four `NSMutableArray` instance selectors
without source definitions: `classForCoder`,
`exchangeObjectAtIndex:withObjectAtIndex:`, `initWithContentsOfFile:`, and
`removeObject:range:identical:`. IDA confirms the following behavior.

## `classForCoder`

`-[NSMutableArray classForCoder]` at `0x425447dc` returns the
`__NSMutableArrayClass` class object.

## `exchangeObjectAtIndex:withObjectAtIndex:`

`-[NSMutableArray exchangeObjectAtIndex:withObjectAtIndex:]` at `0x4255f26c`
gets the count directly from `_info` for exact concrete array classes and via
`count` for other implementations. It checks each index against that count
using `_NSArrayRaiseBoundException`. Concrete arrays swap the two item-buffer
slots directly. Other mutable arrays retain the first object, fetch the second,
replace both positions in order, and release the temporary retain.

## `initWithContentsOfFile:`

`-[NSMutableArray initWithContentsOfFile:]` at `0x4255f3b0` loads an `NSData`
instance from the path, captures the receiver's zone, and deallocates the
receiver. If the file data exists, it parses the ASCII property-list or
serialization representation and releases the data. A successfully parsed
array is returned as a mutable copy in the captured zone; parse failure or a
non-array result returns nil.

The existing `NSArray -initWithContentsOfFile:` delegates to `_initWithData:`,
which returns an immutable copy. That path cannot be reused directly for the
mutable initializer without performing the IDA-confirmed mutable copy in the
receiver's captured zone.

## `removeObject:range:identical:`

`-[NSMutableArray removeObject:range:identical:]` at `0x42516a10` checks that
`range.location + range.length` does not exceed the current count and returns
without work for an empty range. With identity matching enabled it compares
pointers; otherwise it also uses the requested object's `isEqual:` IMP.

For exact concrete arrays the method compacts the inline item buffer, releases
removed members, moves the tail with `memmove`, and writes the new low 27-bit
count while preserving `_info`'s high flag bits. For other mutable-array
implementations it reads batches of up to 128 objects, records which entries
match, and removes matching indexes through `removeObjectAtIndex:` while
adjusting the current range. The loop also uses the requested object's retain
count as a bound and decrements it when a pointer-identical occurrence is
released, as shown by the IDA body.

These selectors remain unimplemented under the `NSMutableArray` source owner.
No source code, tests, or builds were added or run for this analysis.

## Fresh IDA body recheck (2026-10-03)

-[NSMutableArray classForCoder] at 0x425447dc returns the mutable array class object. exchangeObjectAtIndex:withObjectAtIndex: at 0x4255f26c classifies exact NSConcreteMutableArray and NSConcreteArray receivers, loads their low-27-bit _info count directly (other receivers use count), then raises for idx1 and idx2 independently. Concrete receivers swap _items slots without retain traffic. Other receivers retain the first object, fetch the second, replace the two positions in order, then release the temporary retain.

-[NSMutableArray initWithContentsOfFile:] at 0x4255f3b0 reads the file into NSData, captures the receiver zone, deallocates the receiver before parsing, releases the data after parsing, and returns a mutable copy in the saved zone only when the parse result is an NSArray. The current NSArray.m keeps only the immutable NSArray -initWithContentsOfFile: path; there is no mutable override.

-[NSMutableArray removeObject:range:identical:] at 0x42516a10 uses a retained target and retain-count bound. Concrete storage compacts matching slots and preserves the high _info flags; non-concrete implementations process up to 128 elements per batch and remove matches through a cached IMP. The current generic removeObject:inRange: and removeObjectIdenticalTo:inRange: bodies instead iterate and mutate one element at a time, so they do not delegate through this target helper.

Current-source layout check: NSArray.m declares _info and _items at the same offsets as the ABI records for both concrete array classes, so the two concrete fast paths can use existing private layouts. No code, tests, or builds were changed in this recheck.

## Current-source dispatch parity (2026-10-07)

`NSArray.m` now defines all four selectors identified as missing in the initial
audit. In `removeObject:range:identical:`, both concrete and batched paths
resolve the requested object's `isEqual:` IMP once through
`_NSIMPForObjectAndSelector`; the non-concrete path also resolves
`removeObjectAtIndex:` once and invokes that IMP for each removal. The batched
path decrements the retained-target bound for each pointer-identical element,
matching IDA's unconditional decrement inside its scan loop. Static source,
JSON, and whitespace checks passed; no tests or builds were run.
