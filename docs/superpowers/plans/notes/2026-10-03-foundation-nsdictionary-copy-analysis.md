# Foundation `NSDictionary` copy-family ABI analysis

Reference: project Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSDictionary.json`, and the current
`src/Kits/Foundation/NSDictionary.m`.

## Source-to-ABI finding

A static inventory compared the 109 method records in `NSDictionary.json` with
method definitions in `NSDictionary.m`. It found 45 target definitions whose
class ownership has no corresponding source definition, plus five source
definitions not present under the same class in the ABI record. This is a
class-ownership audit, not proof those selectors are wholly absent: many
generic methods currently live on the base classes while the binary overrides
them on concrete dictionary classes.

The copy family is one material gap. Current `NSDictionary.m` has no instance
`copyWithZone:` or `mutableCopyWithZone:` implementation, and neither concrete
dictionary class defines those overrides. The inherited `NSObject -copy` and
`-mutableCopy` wrappers dispatch to these missing selectors.

## IDA-confirmed copy behavior

- `-[NSDictionary copyWithZone:]` at `0x4255d804` allocates an
  `NSConcreteDictionary` in the requested zone and calls
  `initWithDictionary:copyItems:YES`.
- `-[NSConcreteDictionary copyWithZone:]` at `0x42529fbc` returns a retained
  self.
- `-[NSDictionary mutableCopyWithZone:]` at `0x4255ecd4` allocates an
  `NSConcreteMutableDictionary` in the requested zone and calls
  `initWithDictionary:copyItems:NO`.
- `-[NSConcreteDictionary mutableCopyWithZone:]` at `0x42514e80` copies its
  simple-dictionary table, then copies each key and retains each value. Its
  empty-table path allocates and initializes an empty mutable dictionary.
- `-[NSConcreteMutableDictionary mutableCopyWithZone:]` at `0x4251496c` uses
  the same table/key/value ownership sequence.
- `-[NSConcreteMutableDictionary copyWithZone:]` at `0x42510594` copies a
  nonempty table and then copies both keys and values. Its empty path creates
  an empty immutable dictionary.

The concrete copy methods call `NSCopySimpleDictionary`; the current source
has no equivalent helper. IDA's body at `0x42519964` allocates
`12 * bucketCount + 12` bytes in the requested zone, copies the source table
bytes, and zeros word 1 (the mutation counter in the source table layout).
The calling copy method then walks the new buckets and replaces each shallow
key/value pointer with its requested copied or retained object. This exposes
the helper's raw table contract, though the callers' empty-table branches and
per-object ownership still need to be preserved separately.

## Related concrete override

`-[NSConcreteMutableDictionary addEntriesFromDictionary:]` at `0x42506e18`
uses a direct bucket path when the argument's exact class is
`NSConcreteMutableDictionary` or `NSConcreteDictionary`: it copies each key,
retains each value, computes the copied key's hash, and inserts into the
receiver's table. Other dictionary classes fall back to
`-[NSMutableDictionary addEntriesFromDictionary:]`. Current source only has
the generic enumerator/setter implementation on `NSMutableDictionary`; its
`setObject:forKey:` path copies keys and retains values through
`NSSimpleDictionaryInsert`. The final contents may agree, but traversal and
mutation behavior are not established as identical.

## Selectors absent across current Foundation sources

Checking the `NSDictionary.json` selector set against method definitions in
all Foundation `.m` files distinguishes wholly missing selectors from methods
implemented on another class. These target selectors have no source method
definition anywhere: `NSDictionary -getKeys:`, `-containsKey:`,
`-invertedDictionary`, `-dictionaryByCompositingWithDictionary:operation:`,
and `NSMutableDictionary -removeKeysForObject:`.

The target's generic `-[NSDictionary getKeys:]` body at `0x4255e6a0` checks
`count`, obtains `keyEnumerator`, then writes successive `nextObject` results
through the output pointer. Its concrete immutable override at `0x4250ab0c`
walks buckets directly and writes bucket keys. The source currently has the
generic `getObjects:` methods, but no `getKeys:` implementation.

Further IDA traces resolved those four bodies:

- `-[NSDictionary containsKey:]` at `0x4255d738` returns whether
  `objectForKey:` returns non-nil.
- `-[NSDictionary invertedDictionary]` at `0x4255eb24` passes `allKeys` as
  the objects array and `allValues` as the keys array to
  `dictionaryWithObjects:forKeys:`. The instruction sequence confirms the
  pseudocode's apparently unused `allValues` result is the second argument.
- `-[NSDictionary dictionaryByCompositingWithDictionary:operation:]` at
  `0x4255e340` compares the operation argument against five named constant
  slots for Add, Replace, Remove, Set, and Toggle. It initializes a
  mutable result from the receiver, enumerates the supplied dictionary's
  keys, applies the selected operation, then returns an immutable dictionary
  copy of the result. Add only inserts absent keys; replace only overwrites
  existing keys; remove deletes listed keys; set overwrites or inserts; toggle
  inserts absent keys and removes present keys. An unrecognized operation
  raises `NSInvalidArgumentException` with the method proem and supplied value.
  The operation constants are `NSDictionaryAddComponents`,
  `NSDictionaryReplaceComponents`, `NSDictionaryRemoveComponents`,
  `NSDictionarySetComponents`, and `NSDictionaryToggleComponents`.
- `-[NSMutableDictionary removeKeysForObject:]` at `0x4255fa84` collects keys
  whose values are pointer-identical (`==`) to the supplied object, then
  removes the collected keys after enumeration.

No source implementation, tests, or builds were added or run for this
analysis. The generic copy selectors are suitable for a bounded reconstruction;
the concrete table-copy overrides remain gated on helper analysis and an
approved design.

## Utility selector implementation status (2026-10-03)

Added the IDA-confirmed generic `getKeys:`, `containsKey:`, and
`invertedDictionary` methods to `NSDictionary.m`. The inverted dictionary
evaluates `allValues` before `allKeys` and passes keys as objects and values as
keys, matching the traced call order and argument order. Copy-family methods
remain outside this implementation increment. No tests or builds were run.

Added `NSMutableDictionary -removeKeysForObject:` from the recorded IDA trace:
it gathers keys whose current values are pointer-identical to the argument,
then removes those keys after enumeration.

Implemented `NSMutableDictionary -invert` from IDA at `0x4255f994`: capture
parallel key/value arrays, remove the original keys, then reinsert each original
key as the value under its original value as the new key.

Implemented `dictionaryByCompositingWithDictionary:operation:` with the five
IDA-resolved operation strings and the traced validation, lookup, mutation,
copy, and exception paths. Static selector and whitespace checks are recorded
for this continuation; tests and builds were not run.

Implemented the generic `NSDictionary` copy methods from the IDA traces:
`copyWithZone:` allocates an immutable concrete dictionary and copies keys,
while `mutableCopyWithZone:` allocates a mutable concrete dictionary and
shares keys. Concrete table-copy overrides remain a separate open slice.

Implemented `NSConcreteDictionary -copyWithZone:` from IDA at `0x42529fbc`;
it returns a retained receiver. The concrete mutable-copy and mutable-dictionary
table-copy overrides remain open. Static selector and ABI checks pass, and
`git diff --check` is clean; tests and builds were not run.

Implemented `NSConcreteDictionary -mutableCopyWithZone:` from IDA at
`0x42514e80`. Its nonempty path clones the table into the requested zone,
resets the mutation count, copies each live key into that zone, and retains
each live value. Its empty path allocates and initializes a zero-capacity
`NSMutableDictionary`.

Implemented `NSConcreteDictionary -getKeys:` from IDA at `0x4250ab0c`. It
returns immediately for an empty table and otherwise walks buckets in reverse
index order, writing each occupied bucket's key. Static selector ownership
and ABI checks pass; `git diff --check` is clean. Tests and builds were not
run.

Implemented `NSConcreteMutableDictionary -mutableCopyWithZone:` from IDA at
`0x4251496c`. It uses the same table/key/value ownership path as the immutable
dictionary's mutable copy. That shared path assumes mutable concrete instances
have an initialized table, as the target method does. Both mutable-copy paths
visit buckets in descending index order, matching the target loop.

Implemented `NSConcreteMutableDictionary -copyWithZone:` from IDA at
`0x42510594`. For an empty table it returns an initialized empty immutable
dictionary; otherwise it clones the table into the requested zone and copies
each live key and value into that zone in descending bucket order. Static
selector ownership and ABI checks pass, and `git diff --check` is clean. Tests
and builds were not run.

Implemented `NSConcreteMutableDictionary -getKeys:` from IDA at `0x4251d700`.
It uses the same empty-table guard and descending bucket traversal as the
immutable concrete dictionary override. Static selector ownership and ABI
checks pass; tests and builds were not run.

Implemented `getObjects:andKeys:` overrides for `NSConcreteDictionary` and
`NSConcreteMutableDictionary` from IDA at `0x4252baa8` and `0x42512afc`. Both
use the same descending live-bucket traversal, writing keys to the second
argument and values to the first. Static selector ownership and ABI checks
pass, and `git diff --check` is clean. Tests and builds were not run.

Implemented `allKeysForObject:` overrides for both concrete dictionary classes
from IDA at `0x4255af58` and `0x4255b4fc`. The shared scan compares values by
identity or by sending `isEqual:` to the stored value, preserves reverse
bucket order, uses 128 stack slots before default-zone allocation, and returns
an autoreleased array. Static selector ownership and ABI checks pass; tests and
builds were not run.

Implemented `allKeys` and `allValues` overrides for both concrete dictionary
classes from IDA at `0x4255b0f4`, `0x4255b264`, `0x4252bf34`, and `0x42545de0`.
The shared helper returns the array singleton for empty tables and otherwise
collects live bucket keys or values in descending order, using stack storage
through 128 entries and a default-zone buffer above that. Static selector
ownership and ABI checks pass; tests and builds were not run.

Implemented concrete `getObjects:` overrides from IDA at `0x4255b498` and
`0x4250cc64`. Both return without writes for an empty table and otherwise
write live bucket values through the output pointer in descending bucket
order. Static selector ownership and ABI checks pass; tests and builds were
not run.

Implemented `isEqualToDictionary:` overrides for both concrete classes from
IDA at `0x425315a4` and `0x4255b698`. They compare counts first, then look up
each live key in the other dictionary and compare values by identity or by
sending `isEqual:` to the stored value, in descending bucket order. Static
selector ownership and ABI checks pass; tests and builds were not run.

Implemented `NSConcreteMutableDictionary -addEntriesFromDictionary:` from IDA
at `0x42506e18`. Nil input is a no-op. Exact concrete immutable or mutable
dictionary sources use a descending live-bucket scan and the existing table
insertion helper; other dictionary classes use the superclass implementation.

Implemented concrete `initWithDictionary:copyItems:` overrides from IDA at
`0x42515034` and `0x4253e50c`. Exact concrete dictionary sources use a raw table
copy, copy every key, and copy or retain values according to `copyItems`, in
descending bucket order. Empty concrete sources use the class's
`initWithObjects:forKeys:count:` path; non-concrete sources retain the existing
generic initializer behavior. Static selector ownership and ABI checks pass;
tests and builds were not run.

Implemented `encodeWithCoder:` overrides for both concrete classes from IDA at
`0x4255b3d4` and `0x42545d30`. Both encode the count using Objective-C type
`i`, then encode each live bucket key followed by its value using
`encodeBycopyObject:` in descending bucket order.

Implemented `NSConcreteMutableDictionary -initWithObjects:forKeys:count:` from
IDA at `0x4251011c`. It uses the shared dictionary size guard, initializes the
requested capacity, validates nil keys and values, and inserts each pair into
the simple table.

Added each concrete dictionary's ABI `_retainCount` ivar at offset 8 after its
table pointer, then implemented `retain`, `release`, and `retainCount` using
the IDA-confirmed internal refcount helpers and global retain lock. The paired
methods match at `0x425187ac`/`0x42518c34`, `0x42510444`/`0x4250d000`, and
`0x4251a328`/`0x4255b75c`.
