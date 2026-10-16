# Foundation `NSArray` utility selector analysis

Reference: project Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSArray.json`, and the current
`src/Kits/Foundation/NSArray.m`.

## Missing selectors and current helpers

The selector inventory found these three methods in the reference ABI with no
source definitions: `makeObjectsPerform:`,
`makeObjectsPerform:withObject:`, and `containsObjectIdenticalTo:`. The source
already implements the corresponding `makeObjectsPerformSelector:` methods
and a shared identity-search helper named `NSArrayIndexOfObjectInRange`.

IDA confirms the selector aliases are direct forwards:

- `-[NSArray makeObjectsPerform:]` at `0x425582e0` sends
  `makeObjectsPerformSelector:` with the same selector argument.
- `-[NSArray makeObjectsPerform:withObject:]` at `0x4255073c` sends
  `makeObjectsPerformSelector:withObject:` with the same selector and object.

`-[NSArray containsObjectIdenticalTo:]` at `0x42529734` returns false for a
nil object or empty array. For exact `NSConcreteArray` and
`NSConcreteMutableArray` instances, it reads the inline count from `_info &
0x07ffffff` and searches the object buffer. For other arrays it gets `count`
and calls `_NSArrayIndexOfObject` over the full range. Both paths request
identity comparison, forward traversal, and compare against the
`0x7fffffff` not-found sentinel.

The helper trace confirms `_NSArrayIndexOfObject` at `0x42533e64` obtains the
requested range with `getObjects:range:` (512-byte stack storage up to 128
objects, zone allocation above that), then calls `_ArrayIndexOfObject` at
`0x425054b4`. In identity mode, `_ArrayIndexOfObject` compares pointers and
returns the first matching index in forward order. The current source helper
also handles nil/empty inputs and performs a forward pointer comparison, so
the generic source path is available without a new helper API.

## Other wholly missing NSArray selectors

Additional IDA traces show a few direct wrappers and several independent
helpers that should not be grouped into the three-method utility change:

- `sortedArrayUsingSelector:hint:` at `0x4255aeb4` forwards to
  `sortedArrayUsingFunction:context:hint:` with `_NSUseParamAsSortSelector`
  as the comparator context.
- `indexOf:::` at `0x4255a3ec` bounds-checks its start index, then searches to
  the end in forward mode or back to zero in reverse mode. Its equality mode
  is object equality, not pointer identity.
- `indexOfObject:range:identical:` at `0x42506304` validates the requested
  range and passes the identity flag to the shared array search helper.
- `indexOfAttributeBySelector:equalToObject:` at `0x4255a558` processes the
  receiver in batches of 128. For each item it sends the requested selector,
  then compares the result with the supplied object using that object's
  `isEqual:` implementation.
- `arrayByExcludingIdenticalObjectsInArray:` and
  `arrayByExcludingObjectsInArray:` at `0x42559f74` and `0x42559f98` forward
  to `arrayByExcludingObjectsInArray:identical:` with identity enabled or
  disabled. The shared method at `0x42559fbc` preserves source order and
  duplicates while dropping elements found in the other array; an empty
  receiver returns the shared empty array, while a nil or empty other array
  returns a non-copying array copy of the receiver.
- `arrayByExcludingToObjectsInArray:` at `0x42529a14` keeps source elements
  found in the other array by object equality, so its observed behavior is an
  intersection. It returns the shared empty array for an empty receiver and
  a non-copying array copy when the other array is nil or empty.
- `arrayByApplyingSelector:` at `0x42559d8c` sends the selector to each
  element, drops nil results, and returns the remaining results in source
  order. It uses a 128-object stack buffer and allocates a larger buffer from
  the default zone when needed.

## Implementation status (2026-10-03)

Implemented the selector aliases, identity containment, range-identity search,
the three search helpers, selector sorting with a hint, selector application,
and array exclusion/intersection helpers in `NSArray.m`. The shared
`NSArrayIndexOfObjectInRange` helper supplies the confirmed forward identity
search behavior. Static ABI-owner and whitespace checks pass. Tests and builds
were not run.

The same source pass also added the remaining ABI-owned base methods for
coding classification, equality/hash, mutable copying, port-coder replacement,
and the concrete arrays' packed inline/external retain count. The array path
category is audited separately in
`2026-10-03-foundation-nsarray-path-extensions-analysis.md`.
