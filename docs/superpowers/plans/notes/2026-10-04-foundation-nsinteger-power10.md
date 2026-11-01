# NSInteger power-of-ten helper

Reference: Foundation i386 IDA database `703cb6287da7`.

IDA identifies `_NSIntegerMultiplyByPowerOf10` at `0x425a1d70` with
arguments `(destination, destinationLength, source, sourceLength, power)`.
The positive path preflights the output length, then multiplies by powers
of ten in chunks of 38; the reference's chunk word count at `0x425bbcb0`
is 8. Negative powers divide in the same chunks and truncate. The helper
copies the source first when the destination pointer differs.

`NSDecimal.m` now reconstructs that flow using the existing
`NSIntegerMultiply`/`NSIntegerDivide` functions and a local builder for
the 16-bit words of `10^n` where `n <= 38`. The ABI, ownership, and module
symbol maps claim the export. The stale bignum open-item text in
`divergences.md` now records this gap as closed.

IDA lists `_NSDecimalDivide` and `_NSDecimalNormalize` as callers. Both
source implementations now use the exported helper along their matching
scale-up paths; division also uses the existing short-divide primitive when
reducing its quotient to eight mantissa words.

No tests or builds were run.
