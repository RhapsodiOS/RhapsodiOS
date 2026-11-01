# Foundation `Object(NSCompatibility)` analysis

Reference: Foundation i386 IDA database `d12fe2f23883`, Mach-O symbol table
from `C:\Users\raynorpat\Downloads\test\Foundation-i386`, and
`src/Kits/Foundation/reconstruction/abi/NSCompatibility.json`.

## Current source state

`NSCompatibility.m` contains `NSTimeZone` compatibility methods and the
`NSCoder (NSTypedstreamCompatibility)` category. It does not contain an
`Object (NSCompatibility)` category. The ABI record lists 32 methods in
that category: eight class methods and 24 instance methods.

IDA's name table has the category name and a name for `description`, but not
the other method names. The Mach-O text symbols contain all 32 names and
addresses. Decompiling at those symbol addresses succeeds, so the method
addresses below come from the reference binary rather than selector-based
guessing.

## Method map

The class methods are `allocWithZone:`, `autorelease`,
`instanceMethodForSelector:`, `instancesRespondToSelector:`, `poseAsClass:`,
`release`, `retainCount`, and `retain`. They each log a compatibility
warning once. `allocWithZone:` substitutes the default malloc zone for a
null zone and forwards to runtime allocation. The method lookup, selector
query, and pose methods forward to the corresponding runtime operations.
Class `retain` returns the class object, `retainCount` returns `-1`, and
`release` has no further effect.

The instance methods are `autorelease`, `awakeAfterUsingCoder:`,
`classForArchiver`, `classForCoder`, `conformsToProtocol:`, `copyWithZone:`,
`dealloc`, `description`, `doesNotRecognizeSelector:`, `encodeWithCoder:`,
`initWithCoder:`, `isKindOfClass:`, `isMemberOfClass:`, `methodForSelector:`,
`perform:withObject:`, `perform:withObject:withObject:`,
`performSelector:withObject:`, `performSelector:withObject:withObject:`,
`release`, `replacementObjectForArchiver:`, `replacementObjectForCoder:`,
`respondsToSelector:`, `retainCount`, and `retain`.

Most methods log their warning once per method, then forward to the matching
runtime operation. `classForCoder` returns the receiver's class;
`classForArchiver` delegates to it. `encodeWithCoder:` is a no-op and
`initWithCoder:` returns the receiver. `replacementObjectForArchiver:`
delegates to `replacementObjectForCoder:`. `description` formats the class
name and receiver address. Instance `retain` and `release` use the external
extra-reference count; `retainCount` returns that count plus one.
`autorelease` calls `_NSAutoreleaseObject`, and `dealloc` forwards to the
runtime object deallocator.

## Text symbol addresses

The 32 text symbols fall in two address ranges: class methods at
`0x4256a820` through `0x4256aa54`, and instance methods at `0x4256d368`
through `0x4256db9c`. The IDA pseudocode confirms the signatures and
forwarding behavior. A complete address-to-selector map is available from
the Mach-O symbol table; no function names were added to the IDA database.

No source implementation, test, or build was added or run for this analysis.

## Address-to-selector map

| Kind | Selector | Address |
| --- | --- | ---: |
| class | `allocWithZone:` | `0x4256a820` |
| class | `autorelease` | `0x4256a884` |
| class | `instanceMethodForSelector:` | `0x4256a8c8` |
| class | `instancesRespondToSelector:` | `0x4256a920` |
| class | `poseAsClass:` | `0x4256a978` |
| class | `release` | `0x4256a9d0` |
| class | `retainCount` | `0x4256aa10` |
| class | `retain` | `0x4256aa54` |
| instance | `autorelease` | `0x4256d368` |
| instance | `awakeAfterUsingCoder:` | `0x4256d3b4` |
| instance | `classForArchiver` | `0x4256d45c` |
| instance | `classForCoder` | `0x4256d4b0` |
| instance | `conformsToProtocol:` | `0x4256d4f4` |
| instance | `copyWithZone:` | `0x4256d54c` |
| instance | `dealloc` | `0x4256d5b0` |
| instance | `description` | `0x4256d604` |
| instance | `doesNotRecognizeSelector:` | `0x4256d66c` |
| instance | `encodeWithCoder:` | `0x4256d6c4` |
| instance | `initWithCoder:` | `0x4256d704` |
| instance | `isKindOfClass:` | `0x4256d748` |
| instance | `isMemberOfClass:` | `0x4256d7a0` |
| instance | `methodForSelector:` | `0x4256d7f8` |
| instance | `perform:withObject:` | `0x4256d850` |
| instance | `perform:withObject:withObject:` | `0x4256d8ac` |
| instance | `performSelector:withObject:` | `0x4256d90c` |
| instance | `performSelector:withObject:withObject:` | `0x4256d968` |
| instance | `release` | `0x4256d9c8` |
| instance | `replacementObjectForArchiver:` | `0x4256da28` |
| instance | `replacementObjectForCoder:` | `0x4256da80` |
| instance | `respondsToSelector:` | `0x4256daf8` |
| instance | `retainCount` | `0x4256db50` |
| instance | `retain` | `0x4256db9c` |

## External runtime references

The IDA image spans `0x42500000` through `0x4262fb08`. Selector/message reference slots used by this category can contain pointers in the `0x4140…` range (for example, the observed value `0x4140787c`), outside every loaded segment. IDA therefore cannot resolve those targets in this database. The method symbols establish the category selectors, and the decompiler output establishes each method's operation shape, but external runtime selector/reference details should not be inferred from unresolved pointers.

## Implementation status (2026-10-03)

Implemented all 32 ABI-owned methods in `NSCompatibility.m`. Each method emits
its own one-time compatibility warning using the exact constant-string format
recovered from IDA. Runtime forwarding follows the public legacy `Object`
primitives declared in `objc/Object.h` and implemented in `src/objc-1/Object.m`:
`allocFromZone:`, `copyFromZone:`, `free`, `doesNotRecognize:`, `isKindOf:`,
`isMemberOf:`, `methodFor:`, `perform:`, `respondsTo:`, `conformsTo:`,
`instancesRespondTo:`, `instanceMethodFor:`, and `poseAs:`. `NSCoder.h` confirms
the archive hooks use `awake`, `finishUnarchiving`, and `startArchiving:`.

The focused ABI owner audit reports 32 expected methods, 32 definitions, no
missing selectors, no duplicates, and 32 unique warning IDs. `git diff --check`
is clean. No tests or builds were run.

## Conformance forwarding recheck (2026-10-04)

The apparent cycle between `Object -conformsToProtocol:` and
`NSObject (NXCompatibilityFixes) -conformsTo:` is not recursive for
`NSObject` instances. `NSObject.m` provides a concrete instance
`-conformsToProtocol:` implementation that calls
`_NSClassConformsToProtocol(isa, protocol)`, so the compatibility category's
`-conformsTo:` reaches that implementation. For legacy `Object` instances,
`Object.m` provides `-conformsTo:` and forwards to `[isa conformsTo:]`, whose
class implementation performs the protocol-list walk. The forwarding
implementations therefore terminate through distinct base implementations;
no special-case change is indicated.

## Focused IDA/source behavior recheck (2026-10-04)

Re-decompiled `awakeAfterUsingCoder:`, `description`,
`doesNotRecognizeSelector:`, `encodeWithCoder:`, `initWithCoder:`,
`replacementObjectForArchiver:`, `replacementObjectForCoder:`, and
`respondsToSelector:`. The source matches the observed operations: `awake` and
`finishUnarchiving` are conditional, `description` passes the class name and
receiver to the format string, coding encode is a no-op, init returns self,
archiver replacement forwards to coder replacement, and coder replacement
conditionally sends `startArchiving:` with a null argument and falls back to
self for a null result. No source discrepancy was found in this group.

## Allocation and reference-count source recheck (2026-10-04)

Re-decompiled `+[Object allocWithZone:]`, `-[Object copyWithZone:]`,
`-[Object dealloc]`, `-[Object release]`, and `-[Object retainCount]` and
compared them with the current `Object(NSCompatibility)` category. The source
matches the reference operations: null zones become the default malloc zone;
copy forwards to `copyFromZone:`; deallocation forwards to `free`; release
calls the extra-reference decrement and deallocates only when it reaches zero;
and retain count is the extra-reference count plus one. No discrepancy was
found in this group. No tests or builds were run.

## Full compatibility ABI owner audit (2026-10-05)

The current `NSCompatibility.json` manifest contains 66 methods across the
legacy `Object`, `NSCoder`/`StreamTable`/`HashTable`/`List`/`Storage`, and
`NSObject` categories. The manifest-to-source owner scan finds all 66 exactly
once in `NSCompatibility.m`, with no missing selectors, duplicates, or source
extras. This is a static selector-ownership check; it does not verify compiled
encodings or runtime forwarding.
