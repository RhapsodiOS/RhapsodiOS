# Foundation `NSObject(NXCompatibilityFixes)` reconstruction

Reference: Foundation i386 IDA database `d12fe2f23883` and
`src/Kits/Foundation/reconstruction/abi/NSCompatibility.json`.

IDA confirms six compatibility wrappers. Each logs the shared compatibility
warning once, then forwards to the corresponding modern `NSObject` operation:

| Kind | Selector | Address | Forwarding selector |
| --- | --- | ---: | --- |
| class | `conformsTo:` | `0x4256a770` | `conformsToProtocol:` |
| class | `methodFor:` | `0x4256a7c8` | `methodForSelector:` |
| instance | `conformsTo:` | `0x4256c4e0` | `conformsToProtocol:` |
| instance | `isKindOf:` | `0x4256c538` | `isKindOfClass:` |
| instance | `methodFor:` | `0x4256c590` | `methodForSelector:` |
| instance | `respondsTo:` | `0x4256c5e8` | `respondsToSelector:` |

The type encodings in the ABI manifest are preserved by the source signatures:
the predicates return `BOOL`, the method lookups return `IMP`, and the selector
arguments retain their Objective-C encodings.

## Implementation status (2026-10-04)

All six methods are implemented in the `NSObject(NXCompatibilityFixes)`
category in `NSCompatibility.m`, using warning slots distinct from the other
compatibility categories in that file. The focused owner audit reports six
expected methods and six definitions, with no missing, extra, or duplicate
selectors. The global selector audit reports 32 missing selectors, zero
renames, and zero duplicates. `git diff --check` is clean. No tests or builds
were run.
