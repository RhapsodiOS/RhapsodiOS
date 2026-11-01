# Foundation `NSStringArray` review finding resolution

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSStringArray.json`, and the approved
design at `docs/superpowers/specs/2026-10-02-foundation-nsstringarray-design.md`.

The three reported edge cases were checked against the reference before
changing the source. Each is present in IDA, so none is a reconstruction
mismatch under this module's requirement to preserve reference behavior.

## Empty array initialization

`-[NSStringArray initWithUTF8Data:]` returns the result of `release` when the
input data length is zero. `-[NSStringArray initWithArray:]` then unconditionally
stores the original array count through that returned pointer. An empty input
therefore follows the same invalid receiver write in IDA as in the current
source. This target behavior is preserved.

## Non-string array members

IDA logs and skips non-string members while packing the data, then assigns the
original input array count to `_count`. This can make `_count` exceed the
number of packed strings. The initializer preserves that observed assignment.
When `objectAtIndex:` first builds the packed-string records, IDA recounts NUL
bytes and replaces any nonzero cached `_count` with the number of packed
strings. The source previously used `count` directly, which only recomputed
when `_count` was `UINT_MAX`; that left uninitialized records when the original
array included non-string members. The source now performs the IDA-equivalent
recount before allocating the records. A zero cached count remains zero, as in
the target branch.

## Missing terminal NUL

`count` and `objectAtIndex:` validate the final NUL when they process packed
data. IDA's `containsObject:` and string-array matching loops instead scan
bytes until a NUL without first invoking that validation. Malformed, unterminated
data can therefore be read past its buffer by those paths in the reference and
the reconstruction. No extra guard was added because it would change the
observed invalid-input behavior.

No tests or builds were run; the correction was checked statically against the
IDA behavior described above.

## `_findString` nil-data call order (2026-10-07)

IDA `findString` at `0x42563f30` obtains the query string length and chooses
its stack or zone buffer, then sends `bytes` and `length` to the array's
backing data before checking whether that data is nil. It returns zero for nil
data before encoding the query. `NSStringArray.m` now follows that order. For
long query strings, the target also leaves the allocated query buffer
unreleased on this nil-data return; the source preserves the observed early
return. Static source/IDA review only; no tests or builds were run.

## String-array matching count and bit-vector allocation (2026-10-07)

IDA `_findStringArray` (`0x425643b4`) obtains the query data through
`UTF8Data`, checks the query array's `count`, then scans the receiver's packed
data. It calls the receiver's `count` only after a match when the caller asks
for a bit vector, and obtains that count separately for allocation and zeroing.
`_findStringArray` now follows this order instead of eagerly calling the
receiver's `count` before scanning. `_findString` (`0x42563f30`) likewise
allocates and zeroes its result vector with the two target count calls rather
than `NSZoneCalloc`. This preserves the target's lazy count-validation path
for ordinary match queries. Static i386 IDA/source review only; no tests or
builds were run.

## `_findString` query-buffer cleanup order (2026-10-07)

The i386 `findString` body (`0x42563f30`) frees its heap query buffer after
scanning and before constructing the optional bit-vector `NSData`. The source
previously created the `NSData` before releasing that buffer. Reordered cleanup
to match IDA, including the allocation-failure path if bit-vector construction
raises. Static IDA/source review only; no tests or builds were run.
