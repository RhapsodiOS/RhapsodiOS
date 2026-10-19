# Foundation `NSScanner setScanLocation:` paired IDA evidence (2026-10-07)

DR2 i386 implements `-[NSConcreteScanner setScanLocation:]` at `0x42534e9e`;
MOSXS PPC implements it at `0x42557abc`. Both compare the current
`_scanLocation` ivar to `[_scanString length]`. If that current cursor exceeds
the string length, they raise `NSRangeException` using the concrete scanner's
class name and `setScanLocation:` selector. Otherwise they assign the caller's
requested position without checking it against the string length.

`NSScanner.m` already preserves this control flow. The odd guard is target
behavior: with a valid current cursor, an out-of-range requested position is
accepted; a later operation can then observe the invalid cursor. No source or
ABI change was needed. This is paired IDA/source evidence only; no tests or
builds were run.
