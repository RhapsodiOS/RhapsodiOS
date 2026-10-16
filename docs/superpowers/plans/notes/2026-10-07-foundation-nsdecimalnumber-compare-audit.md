# `NSDecimalNumber -compare:` paired audit (2026-10-07)

DR2 i386 `-[NSDecimalNumber compare:]` (`0x4259b72c`) and MOSXS PPC
(`0x4255a4fc`) both use the receiver's inline `NSDecimal`. If the argument is
an `NSDecimalNumber`, they compare against its inline decimal; otherwise they
obtain the argument's `decimalValue` into a temporary and pass that to
`NSDecimalCompare`. `NSDecimalCompare` has the same target flow: not-a-number
ordering, sign ordering, zero-length handling, copies, normalization with
`NSRoundDown`, mantissa comparison, and sign reversal for negative values.

The current `NSDecimalNumber.m` and `NSDecimal.m` source follow those paths.
`NSIntegerCompare` on both targets compares mantissa lengths and then 16-bit
words from most significant to least significant, matching the source's
`CompareMantissas`. No source or ABI changes were needed. Static paired
IDA/source review only; no tests or builds were run.
