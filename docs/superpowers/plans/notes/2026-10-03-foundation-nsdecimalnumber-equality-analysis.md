# Foundation `NSDecimalNumber` equality analysis

Reference: Foundation i386 IDA database `d12fe2f23883`, function
`-[NSDecimalNumber isEqual:]` at `0x4259c254`.

IDA confirms identity succeeds, non-`NSNumber` operands fail, and `NSNumber`
operands are compared through an indirect selector whose result is tested for
zero. The selector reference is indirect in the database; the source routes it
through this class's `compare:` implementation and returns whether the result
is `NSOrderedSame`, matching the observed zero comparison. This selector mapping
is an inference from the local comparison method and `compare:` selector string.

The implementation is in `NSDecimalNumber.m`. ABI-owner and whitespace checks
pass. Tests and builds were not run.
