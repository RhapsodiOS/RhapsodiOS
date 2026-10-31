# Foundation concrete array decoder decompilation

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSArray.json`, and current
`src/Kits/Foundation/NSArray.m`.

## Confirmed source gaps

The ABI lists `initWithCoder:` under both `NSConcreteArray` and
`NSConcreteMutableArray`. Neither concrete owner currently defines the method
in source. IDA locations are `0x42534700` and `0x4251c54c`, respectively.

Both methods decode the count with Objective-C type `i`, reject counts above
`0x07ffffff` by cleaning up the receiver and raising the NSArray size exception,
then decode each member with type `@`. A decoded nil member sets the receiver's
logical count to the number of preceding valid members, deallocates the partial
array, and raises the NSArray nil-insertion exception. Both methods preserve
the high five flag bits in `_info` while setting its low 27-bit element count.

The base `NSArray -initWithCoder:` is also missing from source. IDA at
`0x4255a6e4` confirms it decodes the same signed `i` count and enforces the
same maximum. It decodes into 128 stack slots or a default-zone buffer for
larger arrays, initializes through `initWithObjects:count:`, releases every
decoded object in reverse order, and frees a heap buffer when used. It does not
special-case an empty array or pre-check nil members; those behaviors follow
from the selected initializer.

The base `NSArray -encodeWithCoder:` is another missing source selector. IDA
at `0x4253b1bc` encodes the count with type `i`. Exact concrete array classes
take the count and item buffer directly from their inline fields; other array
implementations use `count` and fetch objects in batches of 128 via
`getObjects:range:`. Members are encoded by copy in forward index order. This
keeps generic subclass dispatch while avoiding per-element accessor messages
for the two concrete array classes.

## Immutable array

`-[NSConcreteArray initWithCoder:]` allocates the object buffer from the
receiver's zone. For a nonempty array it decodes objects directly into that
buffer; successful decoded references become the array's owned members. On a
nil member, setting `_info` to the successfully decoded prefix allows the
regular deallocator to release that prefix before the exception is raised. A
zero count deallocates the allocated receiver and returns the retained shared
empty array.

## Mutable array

`-[NSConcreteMutableArray initWithCoder:]` calls `initWithCapacity:` with the
decoded count, ensures the buffer is large enough, and decodes directly into
the mutable array's item buffer. It transfers decoded object ownership into the
array and sets `_info` after the complete sequence or to the valid prefix on a
nil member. Unlike the immutable decoder, a zero count returns the initialized
mutable receiver.

## Implementation status (2026-10-03)

Implemented the base NSArray coder and decoder plus both concrete array
decoders in `NSArray.m`. The concrete decoders preserve the high `_info` flag
bits, release valid decoded prefixes on nil failure through their deallocators,
and retain the target's distinct empty immutable and mutable outcomes. Static
ABI-owner and whitespace checks pass. Tests and builds were not run.
