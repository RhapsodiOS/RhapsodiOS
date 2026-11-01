# Foundation dictionary enumerator fidelity

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSEnumerator.json`, and the current
`NSDictionary.m` / `NSArray.m` sources.

IDA confirms that `-[NSConcreteDictionary keyEnumerator]` at
`0x425234b4` and `-[NSConcreteMutableDictionary keyEnumerator:]` at
`0x42534278` both snapshot keys with `getKeys:`, allocate an `NSIdEnumerator`
in `NSZoneFromPointer(self)`, initialize it with `reverse:NO` and
`freeWhenDone:YES`, and autorelease it. `-[NSDictionary objectEnumerator]`
at `0x425247a0` follows the same path after snapshotting values with
`getObjects:`.

`NSEnumerator.json` records `NSIdEnumerator` and its
`initWithObjects:count:target:reverse:freeWhenDone:` initializer. That class
is already implemented in `NSArray.m`, including retained-target lifetime,
snapshot cleanup, and the final-object retain/autorelease behavior.

`NSDictionary.m` previously defined a separate `NSSimpleDictionaryEnumerator`
and used it for both key and object enumeration. The dictionary factories now
use the existing `NSIdEnumerator`, allocate it in the dictionary's zone, and
set `freeWhenDone:YES`. Key snapshots use the dictionary's `getKeys:` method,
preserving the concrete class's ordering path. The private enumerator class
and its four source-only methods were removed.

The full selector audit reports 3,253 reference selectors, zero missing,
renamed, or duplicate selectors, and 58 source extras. The C-symbol audit
reports all 249 reference C text symbols mapped to source. `git diff --check`
is clean for the source change. No tests or builds were run.
